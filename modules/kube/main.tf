resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  tags        = var.tags
  description = "Managed by Terraform"

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
    dynamic "ip_config" {
      for_each = var.ip_address != null ? [1] : []
      content {
        ipv4 {
          address = var.ip_address
          gateway = var.gateway
        }
      }
    }

    # DHCP when no static IP is given
    dynamic "ip_config" {
      for_each = var.ip_address == null ? [1] : []
      content {
        ipv4 {
          address = "dhcp"
        }
      }
    }

    user_account {
      username = var.username
      keys     = var.ssh_keys
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      # Useful if you change things in the GUI later
      # initialization,
    ]
  }
}
