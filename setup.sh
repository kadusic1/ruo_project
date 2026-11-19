#!/usr/bin/env bash
# setup.sh: instalira i podesava alate hosta koje trazi `make all` (pokretanje: make setup).
# Podrzano: Ubuntu 24.04 (x86_64) sa KVM-om i systemd-om, i WSL2 Ubuntu 24.04 (Windows 11, nested virtualizacija).
# Pokretati kao obican korisnik (sudo se trazi po potrebi).
#
# Skripta je idempotentna: svaki korak prvo provjerava stanje i mijenja nesto samo kad treba,
# pa se sigurno moze pokrenuti vise puta (drugo pokretanje ne mijenja nista).
set -euo pipefail

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_step=$'\033[1;36m'; c_off=$'\033[0m'
step() { printf '\n%s== %s%s\n' "$c_step" "$*" "$c_off"; }
ok()   { printf '  %sok%s    %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!!%s    %s\n' "$c_warn" "$c_off" "$*"; }
die()  { printf '  %s!!%s    %s\n' "$c_warn" "$c_off" "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1 || [ -x "/usr/sbin/$1" ]; }

[ "$(id -u)" -ne 0 ] || { echo "Ne pokretati kao root; skripta sama koristi sudo."; exit 1; }
[ "$(uname -s)" = "Linux" ] || { echo "Potreban je Linux (Ubuntu 24.04)."; exit 1; }
have apt-get || { echo "Skripta podrzava samo apt (Ubuntu)."; exit 1; }
sudo -v

IN_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IN_WSL=1
HAS_SYSTEMD=0; [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ] && HAS_SYSTEMD=1
NEED_RELOGIN=0
NEED_WSL_RESTART=0
APT_UPDATED=0

# instalira samo pakete koji nedostaju; apt-get update samo ako ima sta instalirati
apt_install() {
  local p miss=()
  for p in "$@"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || true)" == *"ok installed"* ]] || miss+=("$p")
  done
  if [ "${#miss[@]}" -eq 0 ]; then ok "vec instalirano: $*"; return; fi
  if [ "$APT_UPDATED" = 0 ]; then sudo apt-get update -y; APT_UPDATED=1; fi
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${miss[@]}"
  ok "instalirano: ${miss[*]}"
}

# dodaje korisnika u grupu samo ako vec nije clan
add_group() {
  if [[ " $(id -nG "$USER") " == *" $1 "* ]]; then
    ok "$USER je u grupi $1"
  else
    sudo usermod -aG "$1" "$USER"; NEED_RELOGIN=1
    ok "$USER dodan u grupu $1"
  fi
}

# WSL: postavlja kljuc u /etc/wsl.conf samo ako vec nema tu vrijednost (vazi tek poslije wsl --shutdown)
wsl_conf_set() { # sekcija kljuc vrijednost
  local f=/etc/wsl.conf
  if grep -qsiE "^\s*$2\s*=\s*$3\s*$" "$f"; then ok "/etc/wsl.conf: $2=$3"; return 0; fi
  if grep -qsiE "^\s*$2\s*=" "$f"; then
    sudo sed -i -E "s/^\s*$2\s*=.*/$2=$3/I" "$f"
  elif grep -qsiE "^\s*\[$1\]" "$f"; then
    sudo sed -i -E "/^\s*\[$1\]/I a $2=$3" "$f"
  else
    printf '\n[%s]\n%s=%s\n' "$1" "$2" "$3" | sudo tee -a "$f" >/dev/null
  fi
  NEED_WSL_RESTART=1
  warn "/etc/wsl.conf: postavljeno [$1] $2=$3"
}

# ukljucuje servis samo ako nije ukljucen ili ne radi
enable_now() {
  if systemctl is-enabled -q "$1" 2>/dev/null && systemctl is-active -q "$1"; then
    ok "servis $1 radi"
  else
    sudo systemctl enable --now "$1"
    ok "servis $1 ukljucen"
  fi
}

step "1/7 Provjera okruzenja"
. /etc/os-release
ok "$PRETTY_NAME, $(uname -m)"
[ "${VERSION_ID:-}" = "24.04" ] || warn "projekat je provjeren samo na Ubuntu 24.04"
[ "$(uname -m)" = "x86_64" ] || die "potreban je x86_64 (Packer slika je amd64)"
if [ "$IN_WSL" = 1 ]; then
  ok "WSL2 detektovan"
  # systemd trebaju libvirt, ruo-firewall i ruo-dns; resolv.conf mora biti od systemd-resolved
  # (split DNS za projekat.lab), pa ga WSL ne smije sam generisati
  wsl_conf_set boot systemd true
  wsl_conf_set network generateResolvConf false
  [ "$HAS_SYSTEMD" = 1 ] || die "systemd jos nije aktivan: u PowerShellu pokrenuti wsl --shutdown, pa ponovo otvoriti Ubuntu i make setup"
fi
[ "$HAS_SYSTEMD" = 1 ] || die "systemd nije PID 1 (trebaju ga libvirt, ruo-firewall i ruo-dns)"
ok "systemd"
if [ ! -e /dev/kvm ]; then
  if [ "$IN_WSL" = 1 ]; then die "nema /dev/kvm: potreban Windows 11 i nestedVirtualization=true u %UserProfile%\\.wslconfig"
  else die "nema /dev/kvm: ukljuciti virtualizaciju u BIOS-u (Packer i VM-ovi koriste KVM)"; fi
fi
ok "/dev/kvm"
if [ "$IN_WSL" = 1 ]; then
  # WSL-ov DNS server (iz resolv.conf koji je WSL generisao) postaje upstream za resolved;
  # cita se prije instalacije systemd-resolved, jer ona preusmjerava /etc/resolv.conf
  RCONF=/etc/systemd/resolved.conf.d/90-ruo-wsl.conf
  RESOLVED_CHANGED=0
  if [ ! -f "$RCONF" ]; then
    UP="$(awk '$1 == "nameserver" && $2 !~ /^127\./ { printf "%s ", $2 }' /etc/resolv.conf 2>/dev/null || true)"
    sudo mkdir -p "$(dirname "$RCONF")"
    printf '# make setup (WSL): upstream DNS za systemd-resolved\n[Resolve]\nDNS=%s\nFallbackDNS=1.1.1.1 8.8.8.8\n' "${UP% }" \
      | sudo tee "$RCONF" >/dev/null
    RESOLVED_CHANGED=1
    ok "upstream DNS za resolved: ${UP:-samo FallbackDNS}"
  fi
  apt_install systemd-resolved
  enable_now systemd-resolved
  [ "$RESOLVED_CHANGED" = 0 ] || sudo systemctl restart systemd-resolved
  STUB=/run/systemd/resolve/stub-resolv.conf
  if [ "$(readlink -f /etc/resolv.conf)" != "$STUB" ]; then
    sudo ln -sfn "$STUB" /etc/resolv.conf
    ok "/etc/resolv.conf -> $STUB"
  fi
fi
if systemctl is-active -q systemd-resolved; then ok "systemd-resolved (split DNS za projekat.lab)"
else warn "systemd-resolved ne radi: host nece razrjesavati imena projekat.lab"; fi

step "2/7 Osnovni paketi (git, make, curl, ansible, dig, nftables, xorriso)"
apt_install git make curl wget gnupg lsb-release ca-certificates python3 openssh-client \
  ansible bind9-dnsutils iproute2 nftables xorriso

step "3/7 HashiCorp repozitorij: Terraform i Packer"
KEYRING=/usr/share/keyrings/hashicorp-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/hashicorp.list
if [ ! -s "$KEYRING" ]; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o "$KEYRING"
  ok "HashiCorp kljuc dodan"
fi
LINE="deb [signed-by=$KEYRING] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
if [ "$(cat "$LIST" 2>/dev/null)" != "$LINE" ]; then
  echo "$LINE" | sudo tee "$LIST" >/dev/null
  APT_UPDATED=0 # novi izvor: apt-get update je potreban
  ok "HashiCorp repozitorij dodan"
fi
apt_install terraform packer

step "4/7 KVM i libvirt (pool default)"
apt_install qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients
add_group libvirt
add_group kvm
enable_now libvirtd
# Terraform (terraform/vm) pravi diskove u poolu "default"; mreze pravi sam
V="sudo virsh -c qemu:///system"
if ! $V pool-info default >/dev/null 2>&1; then
  $V pool-define-as default dir --target /var/lib/libvirt/images >/dev/null
  ok "pool default definisan"
fi
# izlaz se cita u varijablu: `virsh | grep -q` uz pipefail zna vratiti gresku (SIGPIPE) i kad grep nadje red
POOL="$($V pool-info default)"
if grep -qE '^Autostart:\s+no' <<<"$POOL"; then $V pool-autostart default >/dev/null; fi
if ! grep -qE '^State:\s+running' <<<"$POOL"; then $V pool-start default >/dev/null; fi
ok "pool default aktivan i s autostartom"

step "5/7 Docker (compose v2 i buildx)"
# postojeci docker (npr. docker-ce iz Dockerovog repozitorija) se ne dira
if have docker; then
  ok "docker postoji: $(docker --version)"
else
  apt_install docker.io docker-compose-v2 docker-buildx
fi
docker compose version >/dev/null 2>&1 && ok "docker compose" || warn "nema docker compose plugina (paket docker-compose-v2)"
docker buildx version >/dev/null 2>&1 && ok "docker buildx" || warn "nema docker buildx plugina (paket docker-buildx)"
# Docker Desktop (WSL integracija) nema servis ni grupu u distribuciji
if systemctl cat docker.service >/dev/null 2>&1; then enable_now docker
else ok "docker bez lokalnog servisa (npr. Docker Desktop)"; fi
if getent group docker >/dev/null; then add_group docker; fi

step "6/7 SSH kljuc za VM-ove"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  ok "~/.ssh/id_ed25519 vec postoji"
else
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@ruo"
  ok "napravljen ~/.ssh/id_ed25519"
fi

step "7/7 Provjera"
for t in git make terraform packer ansible-playbook docker virsh qemu-img xorriso dig curl nft resolvectl; do
  if have "$t"; then ok "$t"; else warn "$t nije instaliran"; fi
done
COLL="$(ansible-galaxy collection list 2>/dev/null || true)"
for c in community.docker ansible.posix; do
  if grep -q "^$c " <<<"$COLL"; then ok "kolekcija $c"; else warn "nema Ansible kolekcije $c"; fi
done
# sed -n 1p cita cijeli ulaz (head -1 bi uz pipefail prekinuo skriptu zbog SIGPIPE)
terraform version | sed -n 1p
packer version | sed -n 1p
ansible --version | sed -n 1p

printf '\n%sGotovo.%s Sljedeci koraci: make check, make all\n' "$c_ok" "$c_off"
if [ "$NEED_RELOGIN" = 1 ]; then
  warn "Dodani ste u nove grupe (libvirt/kvm/docker). Odjavite se i prijavite ponovo prije make all (WSL: wsl --shutdown)."
fi
if [ "$NEED_WSL_RESTART" = 1 ]; then
  warn "/etc/wsl.conf je promijenjen: u PowerShellu pokrenuti wsl --shutdown, pa ponovo otvoriti Ubuntu i make setup."
fi
