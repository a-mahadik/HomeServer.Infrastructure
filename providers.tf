terraform {
  required_version = ">= 1.5.0"

  # State is stored in MinIO on the self-hosted runner (see .github/workflows/).
  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent       = var.proxmox_ssh_agent
    username    = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key != null ? file(var.proxmox_ssh_private_key) : null
  }
}

