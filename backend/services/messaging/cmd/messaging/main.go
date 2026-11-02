// Messaging Service (Go): WebSocket-чат, APNs, напоминания, fan-out рассылок.
// Каркас: health-эндпоинты. Логика уведомлений — internal/notify.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func main() {
	mux := http.NewServeMux()
	up := func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "UP"})
	}
	mux.HandleFunc("GET /health/live", up)
	mux.HandleFunc("GET /health/ready", up)

	addr := ":" + envOr("PORT", "3005")
	log.Printf("messaging listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
