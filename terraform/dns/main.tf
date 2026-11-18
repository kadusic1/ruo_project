terraform {
  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.4"
    }
  }
}

# adrese VM-a i zona dolaze iz terraform/vm stanja; ovdje se ne prepisuju
data "terraform_remote_state" "vm" {
  backend = "local"

  config = {
    path = "${path.module}/../vm/terraform.tfstate"
  }
}

variable "tsig_secret" {
  description = "TSIG tajna kljuca ruo-tf (ansible/.secrets/tsig_ruo-tf)"
  type        = string
  sensitive   = true
}

locals {
  dns_ip = data.terraform_remote_state.vm.outputs.ip["dns"]

  # provider dns trazi FQDN zonu (zavrsna tacka)
  zone = "${trimsuffix(data.terraform_remote_state.vm.outputs.dns_zone, ".")}."

  # servisna imena koja se dodaju u zonu preko RFC 2136
  service_ips = {
    for ime in ["web", "app", "db"] :
    ime => data.terraform_remote_state.vm.outputs.ip[ime]
  }
}

provider "dns" {
  update {
    server        = local.dns_ip
    key_name      = "ruo-tf."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}

resource "dns_a_record_set" "service" {
  for_each = local.service_ips

  zone      = local.zone
  name      = each.key
  addresses = [each.value]
  ttl       = 300
}
