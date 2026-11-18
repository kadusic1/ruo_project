#!/usr/bin/env bash
# Provjera vlastitog DNS-a (AO-7, AO-8): zapisi servisa koje dodaje Terraform
# preko RFC 2136, prosljedjivanje vanjskih imena i NXDOMAIN za nepostojeca
# imena. Adrese se citaju iz Terraform izlaza, a ako njih nema iz generisanih
# Ansible varijabli (ansible/group_vars/all/terraform.yml).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
VARS="${VARS:-$ROOT/ansible/group_vars/all/terraform.yml}"

command -v dig >/dev/null || { echo "GRESKA: nedostaje dig" >&2; exit 2; }

# --- adrese VM-a i zona ---
OUT="$(terraform -chdir="$ROOT/terraform/vm" output -json 2>/dev/null || true)"
if [ -n "$OUT" ]; then
  eval "$(printf '%s' "$OUT" | python3 -c '
import json, shlex, sys
d = json.load(sys.stdin)
ips = d["ip"]["value"]
for ime, ip in ips.items():
    print(f"{ime.upper()}_IP={shlex.quote(ip)}")
print("DNS_IP=" + shlex.quote(ips["dns"]))
print("ZONE=" + shlex.quote(d["dns_zone"]["value"]))
')"
elif [ -r "$VARS" ]; then
  # yamlencode iz Terraform-a: "kljuc": "vrijednost" (navodnici se uklanjaju)
  yaml_get() { sed 's/"//g' "$VARS" | awk -v k="$1" '$1 == k ":" { print $2; exit }'; }
  yaml_ip() {
    sed 's/"//g' "$VARS" | awk -v n="$1" '
      /^tf_ips:/ { u = 1; next }
      /^[^ ]/ { u = 0 }
      u && $1 == n ":" { print $2; exit }'
  }
  WEB_IP="$(yaml_ip web)"
  APP_IP="$(yaml_ip app)"
  DB_IP="$(yaml_ip db)"
  DNS_IP="$(yaml_ip dns)"
  ZONE="$(yaml_get dns_zone)"
else
  echo "GRESKA: nema terraform output ni $VARS" >&2
  exit 2
fi

if [ -z "${DNS_IP:-}" ] || [ -z "${ZONE:-}" ] || [ -z "${WEB_IP:-}" ] ||
  [ -z "${APP_IP:-}" ] || [ -z "${DB_IP:-}" ]; then
  echo "GRESKA: ne mogu procitati adrese web/app/db/dns i zonu" >&2
  exit 2
fi

# --- SSH podaci (lib.sh) ---
WEB="$(group_host web)"
APP="$(group_host app)"
if [ -z "$WEB" ] || [ -z "$APP" ]; then
  echo "GRESKA: inventar nema adrese za web i app" >&2
  exit 2
fi

echo "DNS provjere (zona $ZONE, server $DNS_IP)"

# zapisi servisa u zoni (dodaje ih Terraform preko RFC 2136)
for ime in web app db; do
  var="${ime^^}_IP"
  rezultat "dig @$DNS_IP $ime.$ZONE" "${!var}" \
    "$(dig +time=2 +tries=1 +short "@$DNS_IP" "$ime.$ZONE" A | head -1)"
done

# VM koristi dns iz netplan-a, ne pita Terraform
rezultat "web: getent hosts db.$ZONE" "$DB_IP" \
  "$(ssh_to "$WEB" "getent hosts db.$ZONE" 2>/dev/null | awk '{ print $1; exit }')"

# prosljedjivanje vanjskih imena preko forwarders
VANJSKO="$(ssh_to "$APP" "getent hosts archive.ubuntu.com" 2>/dev/null | awk '{ print $1; exit }')"
if [ -n "$VANJSKO" ]; then
  printf '  %-52s ok (%s)\n' "app: getent hosts archive.ubuntu.com" "$VANJSKO"
else
  printf '  %-52s RAZLIKA (nema odgovora)\n' "app: getent hosts archive.ubuntu.com"
  RAZLIKA=$((RAZLIKA + 1))
fi

# nepostojece ime mora dati NXDOMAIN, ne SERVFAIL ili prazan odgovor
rezultat "dig @$DNS_IP nepostoji.$ZONE (NXDOMAIN)" "NXDOMAIN" \
  "$(dig +time=2 +tries=1 "@$DNS_IP" "nepostoji.$ZONE" +noall +comments |
    sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)"

echo
if [ "$RAZLIKA" -eq 0 ]; then
  echo "sve DNS provjere odgovaraju ocekivanjima"
else
  echo "$RAZLIKA DNS provjera odstupa od ocekivanja"
  exit 1
fi
