output "ubuntu_vm_private_keys" {
  value     = { for name, m in module.kube : name => m.ubuntu_vm_private_key }
  sensitive = true
}

output "ubuntu_vm_passwords" {
  value     = { for name, m in module.kube : name => m.ubuntu_vm_password }
  sensitive = true
}

output "ubuntu_vm_public_keys" {
  value     = { for name, m in module.kube : name => m.ubuntu_vm_public_key }
  sensitive = true
}
