# zona u obliku koji trazi provider dns: projekat.lab.
output "zone" {
  value = local.zone
}

# puna imena zapisa: { web = "web.projekat.lab.", app = "...", db = "..." }
output "zapisi" {
  value = { for ime in keys(local.service_ips) : ime => "${ime}.${local.zone}" }
}
