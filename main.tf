module "kube" {
  source   = "./modules/kube"
  for_each = var.vms

  name           = each.value.name
  node_name      = coalesce(each.value.node_name, var.default_node)
  vm_id          = each.value.vm_id
  template_vm_id = each.value.template_vm_id
  cores          = each.value.cores
  memory         = each.value.memory
  disk_size      = each.value.disk_size
  datastore_id   = each.value.datastore_id
  bridge         = each.value.bridge
  ip_address     = each.value.ip_address
  gateway        = each.value.gateway
  username       = each.value.username
  ssh_keys       = each.value.ssh_keys
  tags           = each.value.tags
}
