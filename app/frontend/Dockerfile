# --- faza 1: izgradnja statickog React/Next.js bundle-a ---
FROM node:20-alpine AS build

WORKDIR /app

# Optimizacija keširanja: instalacija zavisnosti prije kopiranja koda
COPY package.json package-lock.json ./
RUN npm ci

# Kopiranje koda i statički export
COPY . .
RUN npm run build

# --- faza 2: lagani Nginx runtime koji servira statiku i proxy-a /api ---
FROM nginx:1.27-alpine

WORKDIR /usr/share/nginx/html

# Kopiranje generisanih statičkih datoteka
COPY --from=build /app/out .

# Nginx Docker slika automatski radi envsubst nad fajlovima u /etc/nginx/templates/
COPY nginx.conf /etc/nginx/templates/default.conf.template

# Podrazumijevana adresa backenda (može se promijeniti varijablom BACKEND_URL)
ENV BACKEND_URL=http://backend:8080

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
