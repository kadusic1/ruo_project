package db

import "time"

// Invoice is the single domain model of the app.
type Invoice struct {
	ID        int64      `json:"id"`
	Number    string     `json:"number"`
	Client    string     `json:"client"`
	Amount    float64    `json:"amount"`
	Status    string     `json:"status"`
	DueDate   *time.Time `json:"due_date"`
	CreatedAt *time.Time `json:"created_at"`
}
