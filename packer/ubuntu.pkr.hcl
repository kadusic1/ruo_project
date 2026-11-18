# Bazna slika svih VM-ova (DO-4): pinovana noble cloud slika + docker i bind9.
# Paketi su u slici, pa VM-ovima ne treba internet za konfiguraciju (Ansible ne
# instalira nista). Build ide kroz QEMU user-mode mrezu hosta, ne kroz segmente.
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

source "qemu" "ubuntu" {
  # datirani release, ne `current`: ista slika pri svakom buildu
  iso_url      = "https://cloud-images.ubuntu.com/noble/20261017/noble-server-cloudimg-amd64.img"
  iso_checksum = "sha256:04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94"
  disk_image   = true
  disk_size    = "10G"
  format       = "qcow2"
  accelerator  = "kvm"
  headless     = true

  # privremeni cidata ISO s korisnikom samo za build
  cd_files = ["${path.root}/seed/user-data", "${path.root}/seed/meta-data"]
  cd_label = "cidata"

  ssh_username     = "ubuntu"
  ssh_password     = "packer"
  ssh_timeout      = "10m"
  shutdown_command = "sudo shutdown -P now"

  output_directory = "${path.root}/output"
  vm_name          = "ruo-base.qcow2"
}

build {
  sources = ["source.qemu.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait",
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 bind9 bind9-utils bind9-dnsutils",
      "sudo systemctl enable docker",
      # named radi samo na dns VM-u; ukljucuje ga rola dns
      "sudo systemctl disable named",
      # lozinka je sluzila samo za build; cloud-init se ponovo izvrsava na svakoj VM
      "sudo passwd -l ubuntu",
      "sudo cloud-init clean --logs --seed",
    ]
  }
}
