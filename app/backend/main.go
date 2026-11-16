package main

import (
	"log"
	"net/http"
	"os"

	"github.com/joho/godotenv"

	"invoice-tracker/db"
	"invoice-tracker/handlers"
)

func main() {
	// Load .env from the backend directory if present; real env vars win.
	_ = godotenv.Load()

	dsn := requireEnv("DSN")
	port := requireEnv("PORT")
	origin := requireEnv("FRONTEND_ORIGIN")

	database := db.Connect(dsn)
	defer database.Close()

	mux := handlers.NewMux(db.NewInvoiceRepository(database), origin)

	log.Println("backend listening on :" + port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

// requireEnv fails fast with a helpful message when a required env var is unset.
func requireEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("missing required env var: %s", key)
	}
	return value
}
