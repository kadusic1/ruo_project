#!/usr/bin/env bash
# Zajednicke funkcije za tests/*.sh (ucitava se sa `source`, ne pokrece se).
# Inventar generise Terraform; adrese i SSH podatke citamo iz njega.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$ROOT/ansible/inventory.ini}"
export PATH="$PATH:/usr/sbin:/sbin"

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

SSH_USER="${SSH_USER:-$(all_vars ansible_user)}"
SSH_USER="${SSH_USER:-student}"
SSH_KEY="${SSH_KEY:-$(all_vars ansible_ssh_private_key_file)}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

SSH=(ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

ssh_to() { # host naredba...
  local host="$1"
  shift
  "${SSH[@]}" "$SSH_USER@$host" "$@"
}

RAZLIKA=0
rezultat() { # opis ocekivano dobijeno
  if [ "$2" = "$3" ]; then
    printf '  %-52s ok\n' "$1"
  else
    printf '  %-52s RAZLIKA (ocekivano: %s, dobijeno: %s)\n' \
      "$1" "$2" "${3:-<prazno>}"
    RAZLIKA=$((RAZLIKA + 1))
  fi
}
