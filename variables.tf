variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (true for self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_agent" {
  description = "Use the SSH agent for uploading snippets/cloud-init files"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH user used to upload snippets/cloud-init files (usually root)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_private_key" {
  description = "Filesystem path to the SSH private key used to upload snippets/cloud-init files. Leave empty to use ssh-agent. Agent takes precedence over this key."
  type        = string
  default     = null
  sensitive   = true
}

variable "default_node" {
  description = "Default Proxmox node name"
  type        = string
  default     = "pve"
}

variable "img_download_url" {
  description = "URL of the Ubuntu cloud image to download once and share across VMs"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "kube_bridge_name" {
  description = "Name of the dedicated Linux bridge on the Proxmox host for Kubernetes nodes"
  type        = string
  default     = "vmbr1"
}

variable "kube_mgmt_subnet" {
  description = "CIDR for the Kubernetes node management subnet (must not overlap with host, pod, or service CIDRs)"
  type        = string
  default     = "10.200.0.0/24"

  validation {
    condition     = can(cidrhost(var.kube_mgmt_subnet, 0))
    error_message = "kube_mgmt_subnet must be a valid CIDR notation (e.g. '10.200.0.0/24')."
  }

  validation {
    condition     = !can(regex("^192\\.168\\.178\\.", cidrhost(var.kube_mgmt_subnet, 0)))
    error_message = "kube_mgmt_subnet must not overlap with the host network (192.168.178.0/24)."
  }

  validation {
    condition     = !can(regex("^10\\.168\\.178\\.", cidrhost(var.kube_mgmt_subnet, 0)))
    error_message = "kube_mgmt_subnet must not overlap with the pod network (10.168.178.0/24)."
  }

  validation {
    condition     = !contains([for i in range(96, 112) : tostring(i)], split(".", cidrhost(var.kube_mgmt_subnet, 0))[1])
    error_message = "kube_mgmt_subnet must not overlap with the Kubernetes service CIDR (10.96.0.0/12, covering 10.96.x.x – 10.111.x.x)."
  }
}

variable "kube_mgmt_gateway" {
  description = "Gateway for the Kubernetes management subnet. Set to null for an isolated bridge (no route to home LAN)."
  type        = string
  default     = null
}

variable "kube_vms" {
  description = "Map of VMs to create"
  type = map(
    object({
      name              = string
      description       = string
      resource_count    = number
      node_name         = optional(string)
      vm_id             = optional(number)
      template_vm_id    = number
      cores             = optional(number, 2)
      memory            = optional(number, 4096)
      disk_size         = optional(number, 32)
      datastore_id      = optional(string, "local-lvm")
      meta_datastore_id = optional(string, "local")
      bridge            = optional(string, "vmbr0")
      ip_address        = optional(string) # e.g. "10.0.10.50/24" or null for DHCP
      gateway           = optional(string)
      second_bridge     = optional(string) # secondary NIC for internet access (e.g. "vmbr0")
      second_ip_address = optional(string) # secondary NIC IP (e.g. "dhcp" or "192.168.178.x/24")
      username          = optional(string, "ubuntu")
      ssh_keys          = optional(list(string), [])
      tags              = optional(list(string), ["terraform"])
      hostname          = string
    })
  )
}

