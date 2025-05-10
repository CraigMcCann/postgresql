locals {
  environment = split(".", split("-", var.PROXMOX_URL)[1])[0]

  password = local.environment == "dev" ? var.DEV_ROOT_PASSWORD : var.PRD_ROOT_PASSWORD
}
