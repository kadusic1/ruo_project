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
      dns_ttl      = var.dns_ttl
    }),
  ])
}
