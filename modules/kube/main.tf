terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# Random password  for the user
resource "random_password" "ubuntu_vm_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}

# TLS private key
resource "tls_private_key" "ubuntu_vm_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Custom cloud-init vendor data to install qemu-guest-agent
resource "proxmox_virtual_environment_file" "cloud_init_vendor" {
  content_type = "snippets"
  datastore_id = var.meta_datastore_id
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF

    file_name = "cloud-init-vendor-${var.name}.yaml"
  }
}

# VM Setup
resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name        = var.name
  description = var.description
  tags        = ["terraform", "ubuntu"]

  node_name = var.node_name
  vm_id     = var.vm_id

  agent {
    # read 'Qemu guest agent' section, change to true only when ready
    enabled = true

    timeout = var.timeout

    # wait for IP
    wait_for_ip {
      ipv4 = true
      ipv6 = false
    }
  }
  # if agent is not enabled, the VM may not be able to shutdown properly, and may need to be forced off
  stop_on_destroy = true

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES" # recommended for modern CPUs
  }

  memory {
    dedicated = var.memory
    floating  = var.memory # set equal to dedicated to enable ballooning
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = var.import_file_id
    interface    = var.disk_interface
    size         = var.disk_size
  }

  initialization {
    # uncomment and specify the datastore for cloud-init disk if default `local-lvm` is not available
    # datastore_id = "local-lvm"

    vendor_data_file_id = proxmox_virtual_environment_file.cloud_init_vendor.id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      keys     = [trimspace(tls_private_key.ubuntu_vm_key.public_key_openssh)]
      password = random_password.ubuntu_vm_password.result
      username = var.username
    }
  }

  network_device {
    bridge = var.bridge
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}

  #  virtiofs {
  #    mapping = "data_share"
  #    cache = "always"
  #    direct_io = true
  #  }
}

