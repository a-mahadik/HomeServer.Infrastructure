terraform {
  required_version = ">= 1.5.0"

  # State is stored on the self-hosted runner at $HOME/tf-state/
  # (see .github/workflows/terraform-apply.yml for the init command).
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }

    null = {
      source = "hashicorp/null"
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

