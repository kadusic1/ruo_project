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

provider "dns" {
  update {
    server        = local.dns_ip
    key_name      = "${local.tsig_key_name}."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}

resource "dns_a_record_set" "service" {
  for_each = local.service_ips

  zone      = local.zone
  name      = each.key
  addresses = [each.value]
  ttl       = local.record_ttl
}
