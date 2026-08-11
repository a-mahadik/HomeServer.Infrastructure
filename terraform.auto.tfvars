proxmox_insecure = true
default_node     = "pve"

kube_vms = {
  kube-ctrl = {
    name           = "kube-ctrl"
    description    = "Kubernetes control plane managed by Terraform"
    resource_count = 1
    template_vm_id = 900
    vm_id          = 1001
    cores          = 2
    memory         = 4096
    disk_size      = 32
    ip_address     = "192.168.178.200/24"
    gateway        = "192.168.178.1"
    username       = "ubuntu"
    tags           = ["k8s", "terraform"]
    hostname       = "machine"
  }

  kube-worker-0 = {
    name           = "kube-worker-0"
    description    = "Kubernetes worker node 0 managed by Terraform"
    resource_count = 1
    template_vm_id = 900
    vm_id          = 1001
    cores          = 2
    memory         = 4096
    disk_size      = 32
    ip_address     = "192.168.178.201/24"
    gateway        = "192.168.178.1"
    username       = "ubuntu"
    tags           = ["k8s", "terraform"]
    hostname       = "machine"
  }
}
