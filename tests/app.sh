#!/usr/bin/env bash
# Provjera aplikacije (AO-1, AO-6, AO-7): svaki VM pokrece samo kontejner
# svog sloja, frontend odgovara preko DNS imena, cijeli lanac
# web -> app -> db vraca fakture iz baze, a baza nema objavljen port.
# Test samo cita podatke (upis i trajnost provjerava test za AO-10).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
VARS="${VARS:-$ROOT/ansible/group_vars/all/terraform.yml}"

command -v curl >/dev/null || { echo "GRESKA: nedostaje curl" >&2; exit 2; }

# zona dolazi iz Terraform izlaza (yamlencode: "dns_zone": "projekat.lab")
ZONE="${ZONE:-$(sed -n 's/^"dns_zone": *"\(.*\)"$/\1/p' "$VARS" 2>/dev/null)}"
# faktura iz seed podataka (app/backend/db/schema.sql)
SEED="${SEED:-INV-2026-001}"

WEB="$(group_host web)"
APP="$(group_host app)"
DB="$(group_host db)"
if [ -z "$ZONE" ] || [ -z "$WEB" ] || [ -z "$APP" ] || [ -z "$DB" ]; then
  echo "GRESKA: ne mogu procitati zonu iz $VARS ili adrese web/app/db" >&2
  exit 2
fi

echo "Provjere aplikacije (http://web.$ZONE)"

# AO-1: na svakom VM-u radi samo servis njegovog sloja (compose profil = grupa)
servisi() { # host -> imena compose servisa koji rade, razdvojena zarezom
  ssh_to "$1" \
    "docker ps --format '{{.Label \"com.docker.compose.service\"}}'" 2>/dev/null |
    sort | paste -sd, -
}
rezultat "web: kontejneri koji rade" "frontend" "$(servisi "$WEB")"
rezultat "app: kontejneri koji rade" "backend" "$(servisi "$APP")"
rezultat "db: kontejneri koji rade" "db" "$(servisi "$DB")"

# AO-6: baza je na mrezi VM-a (network_mode: host) bez objavljenog porta
rezultat "db: objavljeni portovi kontejnera baze" "" \
  "$(ssh_to "$DB" \
    "docker ps --filter label=com.docker.compose.service=db --format '{{.Ports}}'" \
    2>/dev/null)"

# frontend izvana, preko DNS imena (host razrjesava zonu preko dns VM-a)
rezultat "host: GET http://web.$ZONE/" "200" \
  "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://web.$ZONE/")"

# backend iz web segmenta preko DNS imena, kao sto ga zove nginx
rezultat "web: GET http://app.$ZONE:8080/health" "ok" \
  "$(ssh_to "$WEB" "curl -s -m 5 http://app.$ZONE:8080/health" 2>/dev/null)"

# cijeli lanac: nginx (/api/) -> backend -> baza
ODGOVOR="$(curl -s -m 5 -w '\n%{http_code}' "http://web.$ZONE/api/invoices")"
rezultat "host: GET http://web.$ZONE/api/invoices" "200" "${ODGOVOR##*$'\n'}"

rezultat "odgovor sadrzi fakturu $SEED iz baze" "da" \
  "$(printf '%s' "${ODGOVOR%$'\n'*}" | python3 -c '
import json, sys
try:
    fakture = json.load(sys.stdin)
except ValueError:
    print("nije JSON"); sys.exit()
print("da" if any(f.get("number") == sys.argv[1] for f in fakture) else "ne")
' "$SEED")"

echo
if [ "$RAZLIKA" -eq 0 ]; then
  echo "sve provjere aplikacije odgovaraju ocekivanjima"
else
  echo "$RAZLIKA provjera aplikacije odstupa od ocekivanja"
  exit 1
fi
