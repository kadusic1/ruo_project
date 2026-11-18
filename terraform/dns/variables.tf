variable "tsig_secret" {
  description = "TSIG tajna kljuca ruo-tf (ansible/.secrets/tsig_ruo-tf)"
  type        = string
  sensitive   = true
}

# servisna imena koja se dodaju u zonu preko RFC 2136; moraju postojati
# kao segmenti u terraform/vm
variable "service_names" {
  description = "imena servisa za A zapise u zoni"
  type        = list(string)
  default     = ["web", "app", "db"]
}
