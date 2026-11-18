#!/usr/bin/env bash
# Provjera SSH konfiguracije VM-ova (AO-4): prijava lozinkom mora biti
# onemogucena, a prijava kljucem radi. Efektivna sshd konfiguracija se cita
# naredbom `sshd -T`, pa provjera ne ovisi o tome kako je postavljena.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "SSH provjere (korisnik $SSH_USER)"

for grupa in web app db dns; do
  ip="$(group_host "$grupa")"
  if [ -z "$ip" ]; then
    echo "GRESKA: inventar nema adresu za $grupa" >&2
    exit 2
  fi
  rezultat "$grupa: sshd passwordauthentication" "passwordauthentication no" \
    "$(ssh_to "$ip" "sudo sshd -T 2>/dev/null | grep -i '^passwordauthentication'")"
done

echo
if [ "$RAZLIKA" -eq 0 ]; then
  echo "sve SSH provjere odgovaraju ocekivanjima"
else
  echo "$RAZLIKA SSH provjera odstupa od ocekivanja"
  exit 1
fi
