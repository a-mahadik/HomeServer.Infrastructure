variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "timeout" {
  type    = string
  default = "10m"
}

variable "resource_count" {
  type = number
}

variable "img_download_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  type    = number
  default = null
}

variable "template_vm_id" {
  type = number
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "disk_size" {
  type    = number
  default = 32
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "disk_interface" {
  type    = string
  default = "scsi0"
}

variable "meta_datastore_id" {
  description = "Datastore that has the 'snippets' content type enabled (e.g. local)"
  type        = string
  default     = "local"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "ip_address" {
  type    = string
  default = "dhcp"
}

variable "gateway" {
  type    = string
  default = null
}

variable "username" {
  type    = string
  default = "ubuntu"
}

variable "ssh_keys" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = list(string)
  default = ["terraform"]
}

variable "hostname" {
  type    = string
  default = "machine"
}

