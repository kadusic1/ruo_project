terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

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

variable "base_image_url" {
  description = "cloud slika od koje nastaju diskovi VM-a"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
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

# putanje do generisanih Ansible fajlova: relativna putanja se veze za modul
# (radi i pod terraform -chdir), apsolutna i ~ ostaju kakve jesu
locals {
  ansible_dir_input      = pathexpand(var.ansible_dir)
  ansible_dir            = startswith(local.ansible_dir_input, "/") ? local.ansible_dir_input : abspath("${path.module}/${local.ansible_dir_input}")
  ansible_inventory_file = "${local.ansible_dir}/inventory.ini"
  ansible_vars_file      = "${local.ansible_dir}/group_vars/all/terraform.yml"
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

# dns VM prosljedjuje upite za vanjska imena na ove servere
variable "upstream_dns" {
  description = "vanjski DNS serveri na koje dns VM prosljedjuje upite"
  type        = list(string)
  default     = ["1.1.1.1", "9.9.9.9"]
}

# adrese i podmreze VM-a na jednom mjestu: koriste ih outputi, cloud-init i
# fajl za Ansible, pa se ne mogu razici
locals {
  vm_ips     = { for ime, s in var.segments : ime => s.ip }
  vm_subnets = { for ime, s in var.segments : ime => s.subnet }
}

# DNS serveri po VM-u: dns VM koristi vanjske, svi ostali nas dns VM
locals {
  vm_dns = {
    for ime, _ in var.segments : ime => (
      ime == "dns" ? var.upstream_dns : [local.vm_ips["dns"]]
    )
  }
}

# mreza svakog segmenta je u route modu: libvirt ne radi NAT, a host
# (bridge sa adresom .1) usmjerava promet izmedju segmenata
resource "libvirt_network" "segment" {
  for_each = var.segments

  name      = "seg-${each.key}"
  mode      = "route"
  addresses = [each.value.subnet]
  bridge    = "br-${each.key}"
  autostart = true

  # adrese su staticke (netplan iz cloud-init-a), pa DHCP nije potreban
  dhcp {
    enabled = false
  }
}

# bazna slika se preuzima jednom, a disk VM-a je njen "copy-on-write" potomak
resource "libvirt_volume" "base" {
  name   = "ubuntu-noble-base.qcow2"
  pool   = var.pool
  format = "qcow2"
  source = var.base_image_url
}

resource "libvirt_volume" "disk" {
  for_each       = var.segments
  name           = "${each.key}.qcow2"
  pool           = var.pool
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.segments
  name     = "${each.key}-init.iso"
  pool     = var.pool
  user_data = templatefile("${path.module}/cloud-init/user-data.tftpl", {
    hostname = each.key
    ssh_key  = trimspace(file(pathexpand(var.ssh_key_path)))
  })
  network_config = templatefile("${path.module}/cloud-init/network-config.tftpl", {
    mac     = each.value.mac
    address = "${each.value.ip}/24"
    gateway = cidrhost(each.value.subnet, 1)
    dns     = join(", ", local.vm_dns[each.key])
  })
}

resource "libvirt_domain" "vm" {
  for_each  = var.segments
  name      = each.key
  memory    = var.vm_memory
  vcpu      = var.vm_vcpu
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  disk { volume_id = libvirt_volume.disk[each.key].id }

  network_interface {
    network_name = libvirt_network.segment[each.key].name
    mac          = each.value.mac
    # nema DHCP-a: adresa je staticka, pa se ne ceka lease
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

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

# generisanje Ansible inventara iz Terraform konfiguracije (DO-6)
resource "local_file" "inventory" {
  filename = local.ansible_inventory_file
  content  = <<-EOT
    [web]
    web1 ansible_host=${local.vm_ips["web"]}

    [app]
    app1 ansible_host=${local.vm_ips["app"]}

    [db]
    db1 ansible_host=${local.vm_ips["db"]}

    [dns]
    dns1 ansible_host=${local.vm_ips["dns"]}

    [rtr]
    host ansible_connection=local

    [all:vars]
    ansible_user=student
    ansible_ssh_private_key_file=${pathexpand(replace(var.ssh_key_path, ".pub", ""))}
    ansible_python_interpreter=/usr/bin/python3
  EOT
}

# varijable za Ansible iz Terraform konfiguracije (DO-6): podmreze, adrese i DNS
resource "local_file" "ansible_vars" {
  filename = local.ansible_vars_file
  content = join("\n", [
    "# Generisano iz terraform/vm, ne uredjivati rucno",
    yamlencode({
      tf_subnets   = local.vm_subnets
      tf_ips       = local.vm_ips
      dns_zone     = var.dns_zone
      dns_ip       = local.vm_ips["dns"]
      upstream_dns = var.upstream_dns
    }),
  ])
}
