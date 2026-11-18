# Troslojna aplikacija kao kod: minimalni Makefile (infra -> config -> test).
# Pokretanje: `make help`. Umjesto tabulatora naredbe pocinju s ">" (.RECIPEPREFIX).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX := >
.DEFAULT_GOAL := help

# -K trazi sudo lozinku jer se vatrozid primjenjuje na host (grupa rtr);
# ako sudo ne trazi lozinku: make ANSIBLE_ARGS= config
ANSIBLE_ARGS ?= -K

TF := terraform -chdir=terraform/vm
TFD := terraform -chdir=terraform/dns
IMAGE := packer/output/ruo-base.qcow2
# TSIG tajna se cita iz fajla koji generise Ansible (rola dns), nikad iz Gita
TSIG := TF_VAR_tsig_secret="$$(cat ansible/.secrets/tsig_ruo-tf 2>/dev/null || true)"

banner = printf '\n\033[1;36m== %s\033[0m\n' '$(1)'
need = command -v $(1) >/dev/null || { echo "Nedostaje '$(1)'"; exit 1; }

.PHONY: help check image clean-image infra config dns deploy test all destroy

##@ Pomoc
help: ## ovaj popis
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

##@ Okruzenje
check: ## provjera alata, libvirta i SSH kljuca
> @$(call need,terraform)
> @$(call need,packer)
> @$(call need,ansible-playbook)
> @$(call need,docker)
> @docker info >/dev/null 2>&1 || { echo "docker ne radi (korisnik u grupi docker?)"; exit 1; }
> @$(call need,virsh)
> @virsh -c qemu:///system list >/dev/null || { echo "libvirt ne radi"; exit 1; }
> @test -f ~/.ssh/id_ed25519.pub || { echo "Nema ~/.ssh/id_ed25519.pub (ssh-keygen -t ed25519)"; exit 1; }
> @echo "sve je spremno"

image: $(IMAGE) ## Packer: bazna slika s dockerom i bind9 (gradi se samo kad se kod promijeni)

# pravilo nad datotekom: make gradi sliku samo ako je nema ili je Packer kod noviji
$(IMAGE): packer/ubuntu.pkr.hcl packer/seed/user-data packer/seed/meta-data
> @$(call banner,image)
> packer init packer
> packer build -force packer

infra: check image ## Terraform: mreze i VM-ovi, generise ansible/inventory.ini
> @$(call banner,infra)
> $(TF) init -input=false
> $(TF) apply -auto-approve

config: ## Ansible: konfiguracija VM-ova i vatrozid hosta (trazi sudo lozinku)
> @test -f ansible/inventory.ini || { echo "Nema inventara (make infra)"; exit 1; }
> @$(call banner,config)
> cd ansible && ansible-playbook site.yml $(ANSIBLE_ARGS)

dns: ## DNS zapisi servisa preko RFC 2136 (trazi TSIG kljuc iz make config)
> @test -s ansible/.secrets/tsig_ruo-tf || { echo "Nema TSIG kljuca (prvo make config)"; exit 1; }
> @$(call banner,dns)
> $(TFD) init -input=false
> $(TSIG) $(TFD) apply -auto-approve

# host gradi slike i salje ih VM-ovima (docker save/load); sudo na hostu ne treba
deploy: ## Ansible: build slika na hostu, isporuka i pokretanje aplikacije
> @test -f ansible/inventory.ini || { echo "Nema inventara (make infra)"; exit 1; }
> @test -s ansible/.secrets/tsig_ruo-tf || { echo "Nema DNS-a (make config pa make dns)"; exit 1; }
> @$(call banner,deploy)
> cd ansible && ansible-playbook deploy.yml

test: ## test izolacije, DNS-a, SSH-a, aplikacije i trajnosti baze
> @$(call banner,test)
> bash tests/isolation.sh
> bash tests/dns.sh
> bash tests/ssh.sh
> bash tests/app.sh
> bash tests/db.sh

all: infra config dns deploy test ## od praznog sistema do aplikacije koja radi

destroy: ## uklanja DNS zapise, VM-ove, mreze, slike aplikacije i vatrozid na hostu
> -$(TFD) init -input=false
> -$(TSIG) $(TFD) destroy -auto-approve
> $(TF) init -input=false
> $(TF) destroy -auto-approve
> rm -rf terraform/vm/terraform.tfstate* terraform/dns/terraform.tfstate* ansible/.secrets ansible/.build
# slike aplikacije na hostu (imena kao u app/compose.yaml), bazne slike iz
# FROM linija Dockerfile-ova i build kes (docker builder prune je za cijeli host)
> -docker image rm ruo/backend:1.0 ruo/frontend:1.0 mariadb:11.4
> -docker image rm $$(awk '/^FROM/{print $$2}' app/*/Dockerfile | sort -u)
> -docker builder prune -f
# vatrozid, split DNS (systemd uniti) i sysctl fajl na hostu; ip_forward se u
# kernelu ne vraca na 0 (trebaju ga i libvirt i Docker), bez 90-ruo.conf
# poslije restarta vrijedi sistemski default
> -sudo nft delete table ip ruo
> -sudo systemctl disable --now ruo-firewall.service
> -sudo systemctl disable --now ruo-dns.service
> sudo rm -f /etc/nftables.d/ruo.nft /etc/systemd/system/ruo-firewall.service /etc/systemd/system/ruo-dns.service /etc/sysctl.d/90-ruo.conf
# direktorij pravi rola firewall; brise se samo ako je prazan
> -sudo rmdir --ignore-fail-on-non-empty /etc/nftables.d
> sudo systemctl daemon-reload

# destroy ne brise sliku (artefakt, kao kes); potpuno od nule: make destroy clean-image all
# Packer kes (~/.cache/packer: preuzeta Ubuntu cloud slika) i pluginovi iz
# `packer init` ostaju namjerno, da ponovni `make image` ne preuzima sve iznova
clean-image: ## brise Packer sliku (sljedeci make infra je ponovo gradi)
> rm -rf packer/output
