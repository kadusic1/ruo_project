variable "tsig_secret" {
  description = "TSIG tajna kljuca ruo-tf (ansible/.secrets/tsig_ruo-tf)"
  type        = string
  sensitive   = true
}

# mora se poklapati s dns_tsig_key_name u roli dns (podrazumijevano ruo-tf)
variable "tsig_key_name" {
  description = "naziv TSIG kljuca kojim provider dns mijenja zonu"
  type        = string
  default     = "ruo-tf"
}

# TTL zapisa servisa; isti kao dns_ttl u roli dns
variable "record_ttl" {
  description = "TTL zapisa servisa u sekundama"
  type        = number
  default     = 300
}

# servisna imena koja se dodaju u zonu preko RFC 2136; moraju postojati
# kao segmenti u terraform/vm
variable "service_names" {
  description = "imena servisa za A zapise u zoni"
  type        = list(string)
  default     = ["web", "app", "db"]
}
