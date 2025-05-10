terraform {
  required_version = "< 2.0.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "< 1.0.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.PROXMOX_URL
  username = "root@pam"
  password = local.password

  ssh {
    username    = "root"
    private_key = file("/path/to/id_rsa.pem")
  }
}
