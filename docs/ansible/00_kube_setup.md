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
DO NOT DO ANYTHING REGARDING OPERATIONAL OBJECTIVES


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
