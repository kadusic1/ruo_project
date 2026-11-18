# adrese VM-a: { web = "10.40.1.2", app = "...", db = "..." }
output "ip" {
  value = local.vm_ips
}

# naziv zone: projekat.lab
output "dns_zone" {
  value = var.dns_zone
}

# mreza svakog segmenta: podmreza, gateway (host) i libvirt bridge
output "mreze" {
  value = {
    for ime, mreza in libvirt_network.segment : ime => {
      podmreza = local.vm_subnets[ime]
      gateway  = cidrhost(local.vm_subnets[ime], 1)
      bridge   = mreza.bridge
    }
  }
}
