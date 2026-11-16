package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"invoice-tracker/db"
)

type InvoicesHandler struct {
	repo db.InvoiceRepository
}

func NewInvoicesHandler(repo db.InvoiceRepository) *InvoicesHandler {
	return &InvoicesHandler{repo: repo}
}

type invoiceRequest struct {
	Number  string  `json:"number"`
	Client  string  `json:"client"`
	Amount  float64 `json:"amount"`
	Status  string  `json:"status"`
	DueDate *string `json:"due_date"` // "YYYY-MM-DD" or RFC3339, optional
}

func (h *InvoicesHandler) list(w http.ResponseWriter, r *http.Request) {
	invoices, err := h.repo.List()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	writeJSON(w, invoices)
}

func (h *InvoicesHandler) create(w http.ResponseWriter, r *http.Request) {
	invoice, ok := decodeInvoice(w, r)
	if !ok {
		return
	}
	created, err := h.repo.Create(invoice)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Location", "/invoices/"+strconv.FormatInt(created.ID, 10))
	writeJSON(w, created)
}

// decodeInvoice parses the request body into an Invoice, writing an error
// response and returning false if the payload is invalid.
func decodeInvoice(w http.ResponseWriter, r *http.Request) (db.Invoice, bool) {
	var req invoiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return db.Invoice{}, false
	}
	if req.Number == "" || req.Client == "" {
		http.Error(w, "number and client are required", http.StatusBadRequest)
		return db.Invoice{}, false
	}
	switch req.Status {
	case "":
		req.Status = "draft"
	case "draft", "sent", "paid":
	default:
		http.Error(w, "status must be draft, sent or paid", http.StatusBadRequest)
		return db.Invoice{}, false
	}

	var dueDate *time.Time
	if req.DueDate != nil && *req.DueDate != "" {
		parsed, err := parseDate(*req.DueDate)
		if err != nil {
			http.Error(w, "invalid due_date: "+err.Error(), http.StatusBadRequest)
			return db.Invoice{}, false
		}
		dueDate = parsed
	}

	return db.Invoice{
		Number:  req.Number,
		Client:  req.Client,
		Amount:  req.Amount,
		Status:  req.Status,
		DueDate: dueDate,
	}, true
}

func parseDate(value string) (*time.Time, error) {
	for _, layout := range []string{"2006-01-02", time.RFC3339} {
		if t, err := time.Parse(layout, value); err == nil {
			return &t, nil
		}
	}
	return nil, errors.New("must be YYYY-MM-DD or RFC3339")
}

func writeJSON(w http.ResponseWriter, body any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(body); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
