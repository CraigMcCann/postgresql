resource "proxmox_virtual_environment_file" "postgresql" {
  content_type = "snippets"
  datastore_id = "local"
  file_mode    = "0740"
  node_name    = "proxmox-${local.environment}"
  overwrite    = true

  source_file {
    changed  = false
    insecure = false
    path     = "./postgresql.sh"
  }
}

resource "proxmox_virtual_environment_container" "postgresql" {
  description         = "Managed by Terraform"
  hook_script_file_id = "local:snippets/postgresql.sh"
  node_name           = "proxmox-${local.environment}"
  protection          = local.environment == "dev" ? false : true
  start_on_boot       = true
  started             = true
  tags = [
    "terraform",
  ]
  template     = false
  unprivileged = true
  vm_id        = 103

  clone {
    datastore_id = "local-zfs"
    node_name    = "proxmox-${local.environment}"
    vm_id        = 199
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  cpu {
    architecture = "amd64"
    cores        = 2
    units        = 100
  }

  initialization {
    hostname = "postgresql-${local.environment}"

    dns {
      domain = "your.search.domain"
      servers = [
        "your.name.server.one",
        "your.name.server.two",
      ]
    }

    ip_config {
      ipv4 {
        address = local.environment == "dev" ? "x.x.x.x/x" : "x.x.x.x/x"
        gateway = "x.x.x.x"
      }
    }
  }

  memory {
    dedicated = 4096
    swap      = 2048
  }

  network_interface {
    bridge   = "vmbr0"
    enabled  = true
    firewall = true
    mtu      = 1500
    name     = "eth0"
    vlan_id  = 20
  }

  startup {
    order = 3
  }

  depends_on = [proxmox_virtual_environment_file.postgresql]
}

resource "proxmox_virtual_environment_firewall_rules" "postgresql" {
  container_id = 103
  node_name    = "proxmox-${local.environment}"

  rule {
    action  = "ACCEPT"
    comment = "Allow ICMP - Managed by Terraform"
    enabled = true
    iface   = "net0"
    log     = "info"
    proto   = "icmp"
    source  = "x.x.x.x/x"
    type    = "in"
  }
  rule {
    action  = "ACCEPT"
    comment = "Allow SSH - Managed by Terraform"
    enabled = true
    iface   = "net0"
    log     = "info"
    macro   = "SSH"
    source  = "x.x.x.x/x"
    type    = "in"
  }
  rule {
    action  = "ACCEPT"
    comment = "Allow PostgreSQL - Managed by Terraform"
    enabled = true
    iface   = "net0"
    log     = "info"
    macro   = "PostgreSQL"
    source  = "x.x.x.x/x"
    type    = "in"
  }
  rule {
    action  = "ACCEPT"
    comment = "Allow pgAdmin - Managed by Terraform"
    enabled = true
    iface   = "net0"
    log     = "info"
    macro   = "https"
    source  = "x.x.x.x/x"
    type    = "in"
  }

  depends_on = [proxmox_virtual_environment_container.postgresql]
}

resource "proxmox_virtual_environment_firewall_options" "postgresql" {
  dhcp          = false
  enabled       = true
  input_policy  = "REJECT"
  ipfilter      = true
  log_level_in  = "info"
  log_level_out = "info"
  macfilter     = true
  ndp           = false
  node_name     = "proxmox-${local.environment}"
  output_policy = "ACCEPT"
  radv          = false
  vm_id         = 103

  depends_on = [proxmox_virtual_environment_firewall_rules.postgresql]
}

