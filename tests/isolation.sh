#!/usr/bin/env bash
# Matrica povezivosti za izolaciju segmenata (AO-6).
# Na odredisnoj VM se privremeno otvori TCP slusalac, pa se s izvorne VM
# pokusa veza preko /dev/tcp. Ocekivanja odgovaraju politici iz
# ansible/group_vars/rtr/vars.yml. Adrese i SSH podaci se citaju iz inventara
# koji generise Terraform.
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$ROOT/ansible/inventory.ini}"

if [ ! -r "$INVENTORY" ]; then
  echo "GRESKA: nema inventara $INVENTORY (pokreni terraform apply)" >&2
  exit 2
fi

group_host() { # grupa -> ansible_host prve masine u grupi
  awk -v g="$1" '
    $0 ~ "^\\[" g "\\]$" { u = 1; next }
    /^\[/ { u = 0 }
    u && /ansible_host=/ {
      for (i = 1; i <= NF; i++)
        if ($i ~ /^ansible_host=/) { sub(/^ansible_host=/, "", $i); print $i; exit }
    }
  ' "$INVENTORY"
}

all_vars() { # kljuc -> vrijednost iz [all:vars]
  sed -n '/^\[all:vars\]/,$p' "$INVENTORY" |
    awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }'
}

WEB="${WEB_HOST:-$(group_host web)}"
APP="${APP_HOST:-$(group_host app)}"
DB="${DB_HOST:-$(group_host db)}"
DNS="${DNS_HOST:-$(group_host dns)}"
SSH_USER="${SSH_USER:-$(all_vars ansible_user)}"
SSH_KEY="${SSH_KEY:-$(all_vars ansible_ssh_private_key_file)}"
INTERNET_TARGET="${INTERNET_TARGET:-1.1.1.1:443}"
INT_IP="${INTERNET_TARGET%:*}"
INT_PORT="${INTERNET_TARGET##*:}"

SSH_USER="${SSH_USER:-student}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

if [ -z "$WEB" ] || [ -z "$APP" ] || [ -z "$DB" ] || [ -z "$DNS" ]; then
  echo "GRESKA: inventar nema adrese za web, app, db i dns" >&2
  exit 2
fi

SSH=(ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

ssh_to() { # host naredba...
  local host="$1"
  shift
  "${SSH[@]}" "$SSH_USER@$host" "$@"
}

host_ip() { # oznaka segmenta -> adresa VM-a
  case "$1" in
    web) echo "$WEB" ;;
    app) echo "$APP" ;;
    db)  echo "$DB" ;;
    dns) echo "$DNS" ;;
    *)   echo "$1" ;;
  esac
}

LISTENER='import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("0.0.0.0",int(sys.argv[1]))); s.listen(16)
while True: s.accept()[0].close()'

LISTENERS=()
cleanup() {
  local entry host port
  for entry in "${LISTENERS[@]}"; do
    host="${entry%:*}"
    port="${entry##*:}"
    ssh_to "$host" "pkill -f 'ruo-isolation-$port'" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

slusaj() { # host port -> otvori slusalac i cekaj da bude dostupan s hosta
  local host="$1" port="$2" i
  ssh_to "$host" \
    "nohup timeout 120 python3 -c '$LISTENER' $port ruo-isolation-$port </dev/null >/dev/null 2>&1 &" \
    >/dev/null 2>&1 || true
  LISTENERS+=("$host:$port")
  for i in 1 2 3 4 5 6 7 8 9 10; do
    # host -> VM ide kroz output, ne forward: provjera da slusalac radi
    if timeout 1 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

RAZLIKA=0
proba() { # izvor oznaka ip port ocekivano
  local src="$1" oznaka="$2" ip="$3" port="$4" ocek="$5" rez src_host
  src_host="$(host_ip "$src")"
  if ssh_to "$src_host" "timeout 2 bash -c 'exec 3<>/dev/tcp/$ip/$port'" >/dev/null 2>&1; then
    rez=dozvoljeno
  else
    rez=blokirano
  fi
  if [ "$rez" = "$ocek" ]; then
    printf '  %-5s -> %-10s :%-5s  %-11s (ocekivano: %-11s) ok\n' \
      "$src" "$oznaka" "$port" "$rez" "$ocek"
  else
    printf '  %-5s -> %-10s :%-5s  %-11s (ocekivano: %-11s) RAZLIKA\n' \
      "$src" "$oznaka" "$port" "$rez" "$ocek"
    RAZLIKA=$((RAZLIKA + 1))
  fi
}

echo "Matrica povezivosti (inventar: $INVENTORY)"

if ! slusaj "$APP" 8080; then
  echo "GRESKA: ne mogu otvoriti slusalac na app ($APP:8080)" >&2
  exit 2
fi
if ! slusaj "$DB" 3306; then
  echo "GRESKA: ne mogu otvoriti slusalac na db ($DB:3306)" >&2
  exit 2
fi

proba web app "$APP" 8080 dozvoljeno     # web -> app: aplikacijski port
proba app db  "$DB"  3306 dozvoljeno     # app -> db: baza
proba web db  "$DB"  3306 blokirano      # web -> db: preskakanje sloja
proba web app "$APP" 22   blokirano      # web -> app: SSH
proba app db  "$DB"  22   blokirano      # app -> db: SSH
proba web dns "$DNS" 53   dozvoljeno     # web -> dns: BIND (TCP)
proba app dns "$DNS" 53   dozvoljeno     # app -> dns: BIND (TCP)
proba db  dns "$DNS" 53   dozvoljeno     # db -> dns: BIND (TCP)
proba web dns "$DNS" 22   blokirano      # web -> dns: SSH
proba dns db  "$DB"  3306 blokirano      # dns ne doseze bazu
proba app internet "$INT_IP" "$INT_PORT" blokirano  # app nema izlaz
proba db  internet "$INT_IP" "$INT_PORT" blokirano  # db nema izlaz
proba dns internet "$INT_IP" "$INT_PORT" blokirano  # dns samo na port 53
proba web internet "$INT_IP" "$INT_PORT" dozvoljeno # samo web ima opci izlaz

echo
if [ "$RAZLIKA" -eq 0 ]; then
  echo "sve provjere odgovaraju ocekivanjima"
else
  echo "$RAZLIKA provjera odstupa od ocekivanja"
  exit 1
fi
