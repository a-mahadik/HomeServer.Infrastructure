terraform {
	required_version = ">= 1.5.0"

	required_providers {
		proxmox = {
			source = "bpg/proxmox"
			version = "~> 0.111.1"
		}
	}
}

provider "proxmox" {
	endpoint		= var.proxmox_endpoint
	api_token		= var.proxmox_api_token
	insecure		= var.proxmox_insecure
	ssh_username	= var.proxmox_ssh_username
	ssh_private_key	= var.proxmox_ssh_private_key
}
