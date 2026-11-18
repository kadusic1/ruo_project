variable "vm_memory" {
  description = "memorija VM-a u MiB"
  type        = number
  default     = 1024
}

variable "vm_vcpu" {
  description = "broj virtuelnih CPU jezgara"
  type        = number
  default     = 1
}

variable "disk_size" {
  description = "velicina diska VM-a u bajtovima"
  type        = number
  default     = 10 * 1024 * 1024 * 1024
}

variable "base_image" {
  description = "bazna slika diskova VM-a koju gradi Packer (make image); relativno na ovaj modul"
  type        = string
  default     = "../../packer/output/ruo-base.qcow2"
}

variable "pool" {
  description = "libvirt storage pool za diskove i cloud-init ISO"
  type        = string
  default     = "default"
}

variable "ssh_key_path" {
  description = "javni SSH kljuc koji se ubacuje u VM"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ansible_dir" {
  description = "Ansible direktorij; relativno na ovaj modul ili apsolutno"
  type        = string
  default     = "../../ansible"
}

# jedan segment = jedna libvirt mreza (route mode) + jedna VM
# gateway svake mreze je .1 (postavlja ga libvirt), a VM dobija staticku adresu
variable "segments" {
  type = map(object({
    subnet = string
    ip     = string
    mac    = string
  }))
  default = {
    web = { subnet = "10.40.1.0/24", ip = "10.40.1.2", mac = "52:54:00:40:01:02" }
    app = { subnet = "10.40.2.0/24", ip = "10.40.2.2", mac = "52:54:00:40:02:02" }
    db  = { subnet = "10.40.3.0/24", ip = "10.40.3.2", mac = "52:54:00:40:03:02" }
    dns = { subnet = "10.40.4.0/24", ip = "10.40.4.2", mac = "52:54:00:40:04:02" }
  }
}

# zona koju posluzuje dns VM; koristi je i terraform/dns za zapise servisa
variable "dns_zone" {
  description = "naziv DNS zone koju posluzuje dns VM"
  type        = string
  default     = "projekat.lab"
}

# TTL zone i zapisa: jedini izvor istine, koriste ga Ansible (rola dns) i
# terraform/dns preko izlaza ovog modula
variable "dns_ttl" {
  description = "TTL zone i zapisa servisa u sekundama"
  type        = number
  default     = 300
}

# dns VM prosljedjuje upite za vanjska imena na ove servere
variable "upstream_dns" {
  description = "vanjski DNS serveri na koje dns VM prosljedjuje upite"
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}
