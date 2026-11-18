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

banner = printf '\n\033[1;36m== %s\033[0m\n' '$(1)'
need = command -v $(1) >/dev/null || { echo "Nedostaje '$(1)'"; exit 1; }

.PHONY: help check infra plan config dns test all destroy fw-clean

##@ Pomoc
help: ## ovaj popis
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

##@ Okruzenje
check: ## provjera alata, libvirta i SSH kljuca
> @$(call need,terraform)
> @$(call need,ansible-playbook)
> @$(call need,virsh)
> @virsh -c qemu:///system list >/dev/null || { echo "libvirt ne radi"; exit 1; }
> @test -f ~/.ssh/id_ed25519.pub || { echo "Nema ~/.ssh/id_ed25519.pub (ssh-keygen -t ed25519)"; exit 1; }
> @echo "sve je spremno"

infra: check ## Terraform: mreze i VM-ovi, generise ansible/inventory.ini
> @$(call banner,infra)
> $(TF) init -input=false
> $(TF) apply -auto-approve

plan: ## terraform plan: nakon apply mora biti 0 promjena (AO-3)
> $(TF) plan

config: ## Ansible: konfiguracija VM-ova i vatrozid hosta (trazi sudo lozinku)
> @test -f ansible/inventory.ini || { echo "Nema inventara (make infra)"; exit 1; }
> @$(call banner,config)
> cd ansible && ansible-playbook site.yml $(ANSIBLE_ARGS)

dns: ## DNS zapisi servisa preko RFC 2136 (trazi TSIG kljuc iz make config)
> @test -s ansible/.secrets/tsig_ruo-tf || { echo "Nema TSIG kljuca (prvo make config)"; exit 1; }
> @$(call banner,dns)
> $(TFD) init -input=false
> TF_VAR_tsig_secret="$$(cat ansible/.secrets/tsig_ruo-tf)" $(TFD) apply -auto-approve

test: ## test izolacije i DNS-a
> @$(call banner,test)
> bash tests/isolation.sh
> bash tests/dns.sh

all: infra config dns ## od praznog sistema do konfigurisanih VM-ova i DNS zapisa

destroy: ## uklanja DNS zapise, VM-ove, mreze i vatrozid na hostu
> -$(TFD) init -input=false
> -TF_VAR_tsig_secret="$$(cat ansible/.secrets/tsig_ruo-tf 2>/dev/null || true)" $(TFD) destroy -auto-approve
> $(TF) init -input=false
> $(TF) destroy -auto-approve
> rm -rf terraform/dns/terraform.tfstate* ansible/.secrets
> $(MAKE) --no-print-directory fw-clean

fw-clean: ## uklanja pravila i systemd unit vatrozida s hosta
> -sudo nft delete table ip ruo
> -sudo systemctl disable --now ruo-firewall.service
> sudo rm -f /etc/nftables.d/ruo.nft /etc/systemd/system/ruo-firewall.service
> sudo systemctl daemon-reload
