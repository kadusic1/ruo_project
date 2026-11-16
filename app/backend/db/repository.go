package db

import (
	"database/sql"
	"time"
)

// InvoiceRepository is the data-access contract used by the handlers.
type InvoiceRepository interface {
	List() ([]Invoice, error)
	Create(invoice Invoice) (Invoice, error)
}

type mariadbInvoiceRepository struct {
	db *sql.DB
}

// NewInvoiceRepository returns the MariaDB-backed implementation.
func NewInvoiceRepository(database *sql.DB) InvoiceRepository {
	return &mariadbInvoiceRepository{db: database}
}

func (r *mariadbInvoiceRepository) List() ([]Invoice, error) {
	rows, err := r.db.Query("SELECT id, number, client, amount, status, due_date, created_at FROM invoices ORDER BY id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	invoices := []Invoice{}
	for rows.Next() {
		var inv Invoice
		var dueDate, createdAt sql.NullTime
		if err := rows.Scan(&inv.ID, &inv.Number, &inv.Client, &inv.Amount, &inv.Status, &dueDate, &createdAt); err != nil {
			return nil, err
		}
		inv.DueDate = nullTime(dueDate)
		inv.CreatedAt = nullTime(createdAt)
		invoices = append(invoices, inv)
	}
	return invoices, rows.Err()
}

func (r *mariadbInvoiceRepository) Create(invoice Invoice) (Invoice, error) {
	res, err := r.db.Exec(
		"INSERT INTO invoices (number, client, amount, status, due_date) VALUES (?, ?, ?, ?, ?)",
		invoice.Number, invoice.Client, invoice.Amount, invoice.Status, dateArg(invoice.DueDate),
	)
	if err != nil {
		return Invoice{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Invoice{}, err
	}
	invoice.ID = id
	return invoice, nil
}

func dateArg(t *time.Time) any {
	if t == nil {
		return nil
	}
	return *t
}

func nullTime(nt sql.NullTime) *time.Time {
	if !nt.Valid {
		return nil
	}
	return &nt.Time
}
