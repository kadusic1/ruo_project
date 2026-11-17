# --- faza 1: kompajliranje aplikacije (zasebna zbog keširanja slojeva) ---
FROM golang:1.24-alpine AS build

WORKDIR /app

# Zavisnosti se kopiraju i preuzimaju prije koda aplikacije (optimizacija keša)
COPY go.mod go.sum ./
RUN go mod download

# Kopiranje koda i statičko kompajliranje bez CGO
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-w -s" -o /app/server .

# --- faza 2: minimalna i sigurna finalna slika ---
FROM alpine:3.20

# Proces ne smije raditi kao root
RUN addgroup -S app && adduser -S -G app app

WORKDIR /app
COPY --from=build /app/server /app/server

USER app

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["/app/server"]
