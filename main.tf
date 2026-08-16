# download image for kube module
resource "proxmox_download_file" "kube_module_img" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.default_node
  url          = var.img_download_url
  file_name    = "jammy-server-cloudimg-amd64.qcow2"
}

resource "null_resource" "kube_bridge" {
  triggers = {
    bridge_name = var.kube_bridge_name
    subnet      = var.kube_mgmt_subnet
  }

  connection {
    type        = "ssh"
    host        = split(":", replace(replace(var.proxmox_endpoint, "https://", ""), "http://", ""))[0]
    user        = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key != null ? file(var.proxmox_ssh_private_key) : null
    agent       = var.proxmox_ssh_agent
  }

  provisioner "remote-exec" {
    inline = [
      "if ! ip link show ${var.kube_bridge_name} > /dev/null 2>&1; then",
      "  ip link add name ${var.kube_bridge_name} type bridge",
      "  ip addr add ${var.kube_mgmt_subnet} dev ${var.kube_bridge_name}",
      "  ip link set ${var.kube_bridge_name} up",
      "fi",
      "mkdir -p /etc/network/interfaces.d",
      "cat > /etc/network/interfaces.d/${var.kube_bridge_name} <<'BRIDGEOF'",
      "auto ${var.kube_bridge_name}",
      "iface ${var.kube_bridge_name} inet static",
      "    address ${var.kube_mgmt_subnet}",
      "    bridge-ports none",
      "    bridge-stp off",
      "    bridge-fd 0",
      "BRIDGEOF",
    ]
  }
}

module "kube" {
  source   = "./modules/kube"
  for_each = var.kube_vms

  depends_on = [null_resource.kube_bridge]

  name              = each.value.name
  description       = each.value.description
  resource_count    = each.value.resource_count
  import_file_id    = proxmox_download_file.kube_module_img.id
  node_name         = coalesce(each.value.node_name, var.default_node)
  vm_id             = each.value.vm_id
  template_vm_id    = each.value.template_vm_id
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = each.value.disk_size
  datastore_id      = each.value.datastore_id
  meta_datastore_id = each.value.meta_datastore_id
  bridge            = each.value.bridge
  ip_address        = each.value.ip_address
  gateway           = each.value.gateway
  second_bridge     = each.value.second_bridge
  second_ip_address = each.value.second_ip_address
  username          = each.value.username
  ssh_keys          = each.value.ssh_keys
  tags              = each.value.tags
  hostname          = each.value.hostname
}
