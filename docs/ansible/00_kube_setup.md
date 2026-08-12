# Kubernetes cluster setup
Objective of this part of ansible playbooks should be setup of kubernetes cluster.
The objectives should be categorised in three parts:
1.  Operational objectives
2.  DevOps objectives
3.  Documentation objectives

## 1.   Operational objectives

### Paths
-   Inventory:  `src/ansible/inventory/kube/inventory.yml`
-   Playbooks:  `src/ansible/playbooks/`
-   Roles:      `src/ansible/roles/`

### Objectives
Following operational objectives should be managed from the Operational perspective.

#### Inventory
The hosts specified in the inventory would be generated and managed with Terraform. 
The machine authentication and communication with ansible should be done over the openssl certificates.
These certificates should be taken from the terraform state outputs.

Following outputs should represent the SSL public keys from terraform state:
- `ubuntu_vm_public_keys`
- `ubuntu_vm_private_keys`

The correct keys should be used for authentication, while maintaining the sensitivity of the repository. DO NOT EXPOSE any paths to private/public keys or to passwords! Also not in the CI operations!

These public keys should be saved in the temporary file system for the ansible execution. 

At the end of ansible oprations, these temprary files should be flushed out.

#### Playbooks
DO NOT DO ANYTHING REGARDING PLAYBOOKS

## 2.   DevOps objectives
This should bring in all the necessary environments to implementation with continuous integration.
The primary CI operations are handled by `github actions`. 

### Paths
-   CI Pipeline:    `.github/workflows/ansible-apply.yml`
-   Ansible venv:   `$HOME/.environments/ansible`

### Dependencies
This pipeline should be executed after successful execution of `.github/workflows/terraform-apply.yml`

## 3.   Documentation objectives
DO NOT DO ANYTHING REGARDING DOCUMENTATION OBJECTIVES
