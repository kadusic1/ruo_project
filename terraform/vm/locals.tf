# putanje do generisanih Ansible fajlova: ~ se siri, a relativna putanja se
# veze za radni direktorij (Terraform ga postavlja na korijen root modula)
locals {
  ansible_dir            = abspath(pathexpand(var.ansible_dir))
  ansible_inventory_file = "${local.ansible_dir}/inventory.ini"
  ansible_vars_file      = "${local.ansible_dir}/group_vars/all/terraform.yml"
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
