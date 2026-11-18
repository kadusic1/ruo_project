# adresa dns VM-a i zona dolaze iz terraform/vm stanja; ovdje se ne prepisuju
locals {
  dns_ip = data.terraform_remote_state.vm.outputs.ip["dns"]

  # provider dns trazi FQDN zonu (zavrsna tacka)
  zone = "${trimsuffix(data.terraform_remote_state.vm.outputs.dns_zone, ".")}."
}

# TTL dolazi iz terraform/vm (isti kao u roli dns); naziv TSIG kljuca je
# konstanta koja se poklapa s dns_tsig_key_name u roli dns
locals {
  record_ttl    = data.terraform_remote_state.vm.outputs.dns_ttl
  tsig_key_name = "ruo-tf"
}

# adrese servisa u zoni: ime -> adresa iz terraform/vm stanja
locals {
  service_ips = {
    for ime in var.service_names :
    ime => data.terraform_remote_state.vm.outputs.ip[ime]
  }
}
