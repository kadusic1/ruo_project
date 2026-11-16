package handlers

import (
	"net/http"

	"invoice-tracker/db"
)

// NewMux builds the router with all routes registered and CORS applied
// to the given frontend origin.
func NewMux(repo db.InvoiceRepository, allowedOrigin string) http.Handler {
	h := NewInvoicesHandler(repo)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /invoices", h.list)
	mux.HandleFunc("POST /invoices", h.create)

	return withCORS(mux, allowedOrigin)
}

func withCORS(next http.Handler, allowedOrigin string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
