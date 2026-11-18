# adresa dns VM-a i zona dolaze iz terraform/vm stanja; ovdje se ne prepisuju
locals {
  dns_ip = data.terraform_remote_state.vm.outputs.ip["dns"]

  # provider dns trazi FQDN zonu (zavrsna tacka)
  zone = "${trimsuffix(data.terraform_remote_state.vm.outputs.dns_zone, ".")}."
}

# adrese servisa u zoni: ime -> adresa iz terraform/vm stanja
locals {
  service_ips = {
    for ime in var.service_names :
    ime => data.terraform_remote_state.vm.outputs.ip[ime]
  }
}
