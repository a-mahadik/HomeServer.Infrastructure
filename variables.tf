variable "proxmox_endpoint" {
	description	= "Proxmox API endpoint (e.g. https://192.168.1.10:8006/)"
	type		= string
}

variable "proxmox_api_token" {
	description 	= "API token in the form user@realm!tokenid=secret"
	type        	= string
	sensitive   	= true
}

variable "proxmox_insecure" {
	description 	= "Skip TLS verification (true for self-signed certs)"
	type        	= bool
	default     	= true
}

variable "default_node" {
	description 	= "Default Proxmox node name"
	type        	= string
	default     	= "pve"
}

variable "kube_vms" {
	description = "Map of VMs to create"
	type = map(
		object({
			name           = string
			node_name      = optional(string)
			vm_id          = optional(number)
			template_vm_id = number
			cores          = optional(number, 2)
			memory         = optional(number, 4096)
			disk_size      = optional(number, 32)
			datastore_id   = optional(string, "local-lvm")
			bridge         = optional(string, "vmbr0")
			ip_address     = optional(string)          # e.g. "10.0.10.50/24" or null for DHCP
			gateway        = optional(string)
			username       = optional(string, "ubuntu")
			ssh_keys       = optional(list(string), [])
			tags           = optional(list(string), ["terraform"])
			})
	)
}
