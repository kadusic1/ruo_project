terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
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
  value = { for ime, s in var.segments : ime => s.ip }
}

# mreza svakog segmenta: podmreza, gateway (host) i libvirt bridge
output "mreze" {
  value = {
    for ime, mreza in libvirt_network.segment : ime => {
      podmreza = var.segments[ime].subnet
      gateway  = cidrhost(var.segments[ime].subnet, 1)
      bridge   = mreza.bridge
    }
  }
}
