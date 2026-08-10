# HomeServer Infrastructure

Infrastructure-as-Code for a home server using [Proxmox VE](https://www.proxmox.com/) and [Terraform](https://www.terraform.io/). Provisions virtual machines from a cloud-init template, intended to host a Kubernetes cluster.

## Architecture

- **Provider**: [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) (`~> 0.11`)
- **Module**: [`modules/kube`](./modules/kube) — clones a cloud-init VM template and applies CPU, memory, disk, network, and user configuration
- **Orchestration**: [`main.tf`](./main.tf) loops over the `kube_vms` variable to create one VM per entry

Each VM is configured with:

- Full clone of an existing cloud-init template
- Host-type CPU with configurable cores
- Configurable memory and disk (with discard)
- VirtIO network device on a configurable bridge
- Static IP + gateway, or DHCP when no IP is given
- SSH keys and username injected via cloud-init

## Requirements

- Terraform `>= 1.5.0`
- Proxmox VE node with a prepared cloud-init template (see [Prerequisites](#prerequisites))

## Usage

### 1. Prerequisites

Create a Proxmox API token with permission to create VMs:

1. In the Proxmox web UI go to **Datacenter → Permissions → API Tokens**.
2. Add a token for a user in the format `user@realm!tokenid`.
3. Grant it the appropriate VM and pool permissions.

Prepare a cloud-init ready VM template (e.g. Ubuntu Cloud Image). Record its VM ID (e.g. `900`) and use it as `template_vm_id`.

### 2. Configure variables

Copy the example and fill in your values:

```sh
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your Proxmox endpoint, API token, and desired VMs.

### 3. Initialize and apply

```sh
terraform init
terraform plan
terraform apply
```

## Variables

| Variable           | Type          | Default       | Description                                  |
| ------------------ | ------------- | ------------- | -------------------------------------------- |
| `proxmox_endpoint` | `string`      | —             | Proxmox API endpoint (e.g. `https://192.168.1.10:8006/`) |
| `proxmox_api_token` | `string`     | —             | API token in the form `user@realm!tokenid=secret` |
| `proxmox_insecure` | `bool`        | `true`        | Skip TLS verification (true for self-signed certs) |
| `default_node`     | `string`      | `"pve"`       | Default Proxmox node name                   |
| `kube_vms`         | `map(object)` | —             | Map of VMs to create (see below)            |

### `kube_vms` object attributes

| Attribute        | Type             | Default              | Description                              |
| ---------------- | ---------------- | -------------------- | ---------------------------------------- |
| `name`           | `string`         | —                    | VM name                                  |
| `node_name`      | `string`         | `default_node`       | Proxmox node to create the VM on         |
| `vm_id`          | `number`         | `null`               | Optional explicit VM ID                  |
| `template_vm_id` | `number`         | —                    | VM ID of the cloud-init template to clone |
| `cores`          | `number`         | `2`                  | Number of CPU cores                      |
| `memory`         | `number`         | `4096`               | Memory in MiB                            |
| `disk_size`      | `number`         | `32`                 | Disk size in GiB                         |
| `datastore_id`   | `string`         | `"local-lvm"`        | Datastore for the disk                   |
| `bridge`         | `string`         | `"vmbr0"`            | Network bridge                           |
| `ip_address`     | `string`         | `null`               | Static IP (e.g. `10.0.10.51/24`) or `null` for DHCP |
| `gateway`        | `string`         | `null`               | Network gateway for static IP            |
| `username`       | `string`         | `"ubuntu"`           | Default user created via cloud-init      |
| `ssh_keys`       | `list(string)`   | `[]`                 | SSH public keys to inject               |
| `tags`           | `list(string)`   | `["terraform"]`      | VM tags                                 |

## Example

```hcl
kube_vms = {
  web01 = {
    name           = "web-01"
    template_vm_id = 900
    cores          = 2
    memory         = 4096
    disk_size      = 40
    ip_address     = "10.0.10.51/24"
    gateway        = "10.0.10.1"
    username       = "ubuntu"
    ssh_keys       = ["ssh-ed25519 AAAA... your-key"]
    tags           = ["web", "terraform"]
  }

  db01 = {
    name           = "db-01"
    template_vm_id = 900
    cores          = 4
    memory         = 8192
    disk_size      = 80
    # No ip_address = DHCP
    username       = "ubuntu"
    ssh_keys       = ["ssh-ed25519 AAAA... your-key"]
    tags           = ["db", "terraform"]
  }
}
```

## Outputs

The `modules/kube` module exposes `vm_id`, `name`, and `node_name` for each provisioned VM.

## Notes

- `proxmox_insecure` defaults to `true` because home servers commonly use self-signed certificates. Only set it to `false` with a valid CA.
- `terraform.tfvars` is gitignored; only `terraform.tfvars.example` is committed.
- The `lifecycle.ignore_changes` block in the module is preconfigured so you can keep tweaking a VM in the Proxmox GUI without Terraform reverting it.

## License

[Apache-2.0](./LICENSE)
