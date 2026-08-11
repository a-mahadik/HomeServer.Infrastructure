module "kube" {
  source   = "./modules/kube"
  for_each = var.kube_vms

  name           = each.value.name
  description    = each.value.description
  resource_count = each.value.resource_count
  node_name      = coalesce(each.value.node_name, var.default_node)
  vm_id          = each.value.vm_id
  template_vm_id = each.value.template_vm_id
  cores          = each.value.cores
  memory         = each.value.memory
  disk_size      = each.value.disk_size
  datastore_id   = each.value.datastore_id
  meta_datastore_id = each.value.meta_datastore_id
  bridge         = each.value.bridge
  ip_address     = each.value.ip_address
  gateway        = each.value.gateway
  username       = each.value.username
  ssh_keys       = each.value.ssh_keys
  tags           = each.value.tags
  hostname       = each.value.hostname
}
