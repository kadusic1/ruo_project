#!/usr/bin/env bash
# Provjera trajnosti baze (AO-10): faktura upisana kroz aplikaciju mora
# ostati u bazi nakon sto se kontejner baze ponovo kreira (podaci su u
# imenovanom volumenu db_data). Testna faktura se na kraju brise iz baze.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
VARS="${VARS:-$ROOT/ansible/group_vars/all/terraform.yml}"
# direktorij aplikacije na VM-u (app_dir u ansible/roles/app/defaults)
APP_DIR="${APP_DIR:-/opt/ruo-app}"

command -v curl >/dev/null || { echo "GRESKA: nedostaje curl" >&2; exit 2; }

ZONE="${ZONE:-$(sed -n 's/^"dns_zone": *"\(.*\)"$/\1/p' "$VARS" 2>/dev/null)}"
DB="$(group_host db)"
if [ -z "$ZONE" ] || [ -z "$DB" ]; then
  echo "GRESKA: ne mogu procitati zonu iz $VARS ili adresu db" >&2
  exit 2
fi

API="http://web.$ZONE/api/invoices"
BROJ="AO10-TEST-$(date +%s)"
# .env je 0600 root, pa compose na VM-u ide preko sudo
COMPOSE="cd $APP_DIR && sudo docker compose --profile db"

echo "Trajnost baze (faktura $BROJ)"

ima_fakturu() { # -> da | ne | greska
  curl -s -m 5 -f "$API" | python3 -c '
import json, sys
try:
    fakture = json.load(sys.stdin)
except ValueError:
    print("greska"); sys.exit()
print("da" if any(f.get("number") == sys.argv[1] for f in fakture) else "ne")
' "$BROJ"
}

id_baze() { # -> ID kontejnera baze
  ssh_to "$DB" "$COMPOSE ps -q db" 2>/dev/null
}

# testna faktura se brise direktno u bazi (API nema DELETE), i kad test padne
obrisi() {
  ssh_to "$DB" "$COMPOSE exec -T db sh -c 'mariadb -uroot \
    -p\"\$MARIADB_ROOT_PASSWORD\" \"\$MARIADB_DATABASE\" \
    -e \"DELETE FROM invoices WHERE number = '\''$BROJ'\''\"'" \
    >/dev/null 2>&1 || echo "  (upozorenje: faktura $BROJ nije obrisana)"
}
trap obrisi EXIT

# 1. upis kroz cijeli lanac (nginx -> backend -> baza)
rezultat "POST $API" "200" \
  "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"number\":\"$BROJ\",\"client\":\"Test AO-10\",\"amount\":1}" "$API")"
rezultat "faktura postoji prije rekreiranja" "da" "$(ima_fakturu)"

# 2. ponovno kreiranje kontejnera baze (novi kontejner, isti volumen)
STARI="$(id_baze)"
ssh_to "$DB" "$COMPOSE up -d --force-recreate --wait db" >/dev/null 2>&1
NOVI="$(id_baze)"
rezultat "db: kontejner ponovo kreiran (novi ID)" "da" \
  "$([ -n "$NOVI" ] && [ "$NOVI" != "$STARI" ] && echo da || echo ne)"

# 3. backend se ponovo spaja na bazu; cekamo da API opet odgovara
for _ in $(seq 1 30); do
  [ "$(ima_fakturu)" != "greska" ] && break
  sleep 2
done
rezultat "faktura postoji nakon rekreiranja" "da" "$(ima_fakturu)"

echo
if [ "$RAZLIKA" -eq 0 ]; then
  echo "podaci baze prezivljavaju ponovno kreiranje kontejnera"
else
  echo "$RAZLIKA provjera trajnosti odstupa od ocekivanja"
  exit 1
fi
