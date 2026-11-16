package db

import (
	"database/sql"
	"log"

	_ "github.com/go-sql-driver/mysql"
)

// Connect opens a connection to MariaDB using the given DSN, e.g.
// "invoices:invoices@tcp(localhost:3306)/invoices?parseTime=true".
func Connect(dsn string) *sql.DB {
	database, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	if err := database.Ping(); err != nil {
		log.Fatalf("ping db: %v", err)
	}
	return database
}
