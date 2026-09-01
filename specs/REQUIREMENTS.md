# Requirements Document: Kubernetes Cluster Cgroup Driver Fix & Cilium Installation

**Project:** HomeServer.Infrastructure  
**Version:** 1.0  
**Date:** 2026-09-01  
**Status:** Draft  
**Author:** Requirements Engineer  

---

## 1. Overview

This document specifies the requirements for fixing a critical cgroup driver inconsistency in the Kubernetes cluster provisioned by this Infrastructure-as-Code repository, and for installing Cilium CNI via Helm after the fix is applied.

### 1.1 Problem Summary

The cluster exhibits the following symptoms after Cilium installation:
- All nodes remain in `NotReady` state
- Non-static pods (`cilium-*`, `kube-proxy`, `coredns`) stuck in `ContainerCreating` / `Init:0/6`
- Error in logs: `expected cgroupsPath to be of format "slice:prefix:name" for systemd cgroups, got "/kubepods/burstable/pod<uid>/<sandbox-id>" instead`

### 1.2 Root Cause

A cgroup driver mismatch between kubelet and containerd:
- **kubelet** configured with `cgroupDriver: systemd` in `/var/lib/kubelet/config.yaml`, but overrides to `cgroupfs` at runtime based on CRI runtime report
- **containerd** configured with `SystemdCgroup = true` (containerd 2.x style)
- **Ubuntu 22.04 runc** (compiled with systemd cgroup support) rejects cgroupfs-style paths when `SystemdCgroup = true`
- Result: No sandbox can be created → CNI plugin never initializes → nodes never become Ready

### 1.3 Solution Strategy

Normalize both kubelet and containerd to use **cgroupfs** driver consistently:
1. Set `SystemdCgroup = false` in containerd config (both control plane and worker roles)
2. Restart containerd after config change
3. Explicitly configure kubelet to use `cgroupDriver: cgroupfs` (via config.yaml or systemd drop-in)
4. Restart kubelet after cgroup driver change
5. Ensure nodes reach `Ready` state before installing Cilium
6. Install Helm on control plane
7. Install Cilium via Helm with appropriate settings

---

## 2. Functional Requirements

### 2.1 Containerd Configuration Fix

| ID | Requirement | Description |
|----|-------------|-------------|
| **REQ-001** | Update containerd template for control plane | Modify `src/ansible/roles/k8s_control_plane/templates/containerd.toml.j2` to set `SystemdCgroup = false` under `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` |
| **REQ-002** | Update containerd template for worker nodes | Modify `src/ansible/roles/k8s_worker_node/templates/containerd.toml.j2` to set `SystemdCgroup = false` under `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` |
| **REQ-003** | Trigger containerd restart on config change | Ensure the existing "Restart containerd" handler in both roles is notified when the containerd template is deployed |

### 2.2 Kubelet Cgroup Driver Alignment

| ID | Requirement | Description |
|----|-------------|-------------|
| **REQ-004** | Explicitly set kubelet cgroup driver to cgroupfs | Configure kubelet to use `cgroupDriver: cgroupfs` explicitly so it does not rely on runtime-reported driver. Implement via **either**: (a) `/var/lib/kubelet/config.yaml` with `cgroupDriver: cgroupfs`, or (b) systemd drop-in at `/etc/systemd/system/kubelet.service.d/10-cgroup.conf` with `Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs"` |
| **REQ-005** | Apply kubelet cgroup driver config on both roles | Ensure the kubelet cgroup driver configuration is applied in both `k8s_control_plane` and `k8s_worker_node` roles |
| **REQ-006** | Trigger kubelet restart on cgroup driver change | Add a "Restart kubelet" handler in both roles and notify it when the kubelet cgroup driver configuration changes |

### 2.3 Execution Ordering & Node Readiness

| ID | Requirement | Description |
|----|-------------|-------------|
| **REQ-007** | Enforce correct task ordering | Ensure task sequence: (1) containerd config → (2) containerd restart → (3) kubelet cgroup config → (4) kubelet restart → (5) wait for nodes Ready → (6) Cilium Helm install |
| **REQ-008** | Wait for node readiness before Cilium install | Add a task that polls `kubectl get nodes` until all nodes report `Ready=True` with retry logic (e.g., 60 retries × 5s delay) before proceeding to Helm install |

### 2.4 Helm Installation on Control Plane

| ID | Requirement | Description |
|----|-------------|-------------|
| **REQ-009** | Install Helm on control plane node | Add a task in `k8s_control_plane` role to install Helm (via apt/snap/binary) on the control plane host |
| **REQ-010** | Add Cilium Helm repository | Add task to run `helm repo add cilium https://helm.cilium.io/` on control plane |

### 2.5 Cilium Installation via Helm

| ID | Requirement | Description |
|----|-------------|-------------|
| **REQ-011** | Install Cilium via Helm with required settings | Execute `helm install cilium cilium/cilium --namespace kube-system --set image.pullPolicy=IfNotPresent --set ipam.mode=kubernetes --set etcd.enabled=false` on control plane after nodes are Ready |
| **REQ-012** | Support configurable Cilium version | Allow specifying Cilium chart version (default to latest stable, e.g., 1.20.x) via Ansible variable |

---

## 3. Non-Functional Requirements

| ID | Requirement | Category | Description |
|----|-------------|----------|-------------|
| **REQ-013** | Idempotency | Reliability | All Ansible tasks must be idempotent — re-running the playbook must not cause errors or unnecessary changes |
| **REQ-014** | Consistency across nodes | Correctness | Both control plane and worker nodes must have identical cgroup driver configuration (both `cgroupfs`) |
| **REQ-015** | Version compatibility | Compatibility | Containerd template must use containerd 2.x plugin key path (`io.containerd.cri.v1.runtime`) matching the deployed version (2.2.1) |
| **REQ-016** | Minimal disruption | Operations | Fix must be applicable to existing cluster without requiring full reprovision (in-place config update + service restarts) |
| **REQ-017** | Documentation | Maintainability | Update inline comments in modified templates and tasks to explain the cgroup driver choice and why `SystemdCgroup = false` is used |
| **REQ-018** | Verification capability | Observability | Provide a way to verify the fix (e.g., task that asserts containerd's reported driver matches kubelet's configured driver) |

---

## 4. Acceptance Criteria

### 4.1 Containerd Configuration (REQ-001, REQ-002, REQ-003)

| Criterion | Verification Method |
|-----------|---------------------|
| `containerd.toml.j2` templates contain `SystemdCgroup = false` | `grep -A2 "runc.options" templates/containerd.toml.j2` shows `SystemdCgroup = false` |
| Handler "Restart containerd" exists in both roles' `handlers/main.yml` | `grep -A5 "Restart containerd" roles/*/handlers/main.yml` |
| Template task notifies "Restart containerd" handler | `grep -B2 -A2 "notify.*Restart containerd" roles/*/tasks/main.yml` |
| After playbook run: `crictl info | grep SystemdCgroup` returns `false` on all nodes | Manual verification on target hosts |

### 4.2 Kubelet Cgroup Driver (REQ-004, REQ-005, REQ-006)

| Criterion | Verification Method |
|-----------|---------------------|
| Kubelet configured with explicit `cgroupDriver: cgroupfs` | Check `/var/lib/kubelet/config.yaml` or `/etc/systemd/system/kubelet.service.d/10-cgroup.conf` on nodes |
| "Restart kubelet" handler exists in both roles | `grep -A5 "Restart kubelet" roles/*/handlers/main.yml` |
| Kubelet restart triggered on config change | `grep -B2 -A2 "notify.*Restart kubelet" roles/*/tasks/main.yml` |
| After playbook run: kubelet logs show `cgroupDriver="cgroupfs"` | `journalctl -u kubelet | grep "cgroup driver setting"` |

### 4.3 Node Readiness & Ordering (REQ-007, REQ-008)

| Criterion | Verification Method |
|-----------|---------------------|
| Tasks execute in correct order | Review playbook/role task sequence |
| Wait-for-ready task retries until all nodes Ready | Task has `retries: 60`, `delay: 5`, `until` condition checking for `Ready=True` |
| Cilium Helm install only runs after nodes Ready | Helm task depends on wait-for-ready task completion |

### 4.4 Helm & Cilium Installation (REQ-009, REQ-010, REQ-011, REQ-012)

| Criterion | Verification Method |
|-----------|---------------------|
| Helm installed on control plane | `which helm` or `helm version` succeeds on control plane |
| Cilium repo added | `helm repo list` shows `cilium` entry |
| Cilium installed in `kube-system` namespace | `helm list -n kube-system` shows `cilium` release |
| Cilium pods running | `kubectl get pods -n kube-system -l k8s-app=cilium` shows `Running` |
| Nodes become Ready after Cilium install | `kubectl get nodes` shows all nodes `Ready` |

---

## 5. Traceability Matrix

| Requirement ID | Source | Component | Status |
|----------------|--------|-----------|--------|
| REQ-001 | CLUSTER_FIX_DIAGNOSIS.md §1 | `k8s_control_plane` role template | Proposed |
| REQ-002 | CLUSTER_FIX_DIAGNOSIS.md §1 | `k8s_worker_node` role template | Proposed |
| REQ-003 | CLUSTER_FIX_DIAGNOSIS.md Checklist #2 | Both roles handlers | Proposed |
| REQ-004 | CLUSTER_FIX_DIAGNOSIS.md Checklist #3 | Both roles tasks | Proposed |
| REQ-005 | CLUSTER_FIX_DIAGNOSIS.md Checklist #3 | Both roles tasks | Proposed |
| REQ-006 | CLUSTER_FIX_DIAGNOSIS.md Checklist #4 | Both roles handlers/tasks | Proposed |
| REQ-007 | CLUSTER_FIX_DIAGNOSIS.md Checklist #5 | Playbook/role ordering | Proposed |
| REQ-008 | CLUSTER_FIX_DIAGNOSIS.md Checklist #6 | Playbook task | Proposed |
| REQ-009 | User request | `k8s_control_plane` role tasks | Proposed |
| REQ-010 | User request / CLUSTER_FIX_DIAGNOSIS.md §Cilium Install | `k8s_control_plane` role tasks | Proposed |
| REQ-011 | User request / CLUSTER_FIX_DIAGNOSIS.md §Cilium Install | `k8s_control_plane` role tasks | Proposed |
| REQ-012 | CLUSTER_FIX_DIAGNOSIS.md Notes | `k8s_control_plane` role vars | Proposed |
| REQ-013 | Ansible best practices | All tasks | Proposed |
| REQ-014 | Root cause analysis | Both roles | Proposed |
| REQ-015 | CLUSTER_FIX_DIAGNOSIS.md Note (line 106-111) | Templates | Proposed |
| REQ-016 | User request (in-place fix) | All changes | Proposed |
| REQ-017 | Maintainability | Templates, tasks | Proposed |
| REQ-018 | CLUSTER_FIX_DIAGNOSIS.md Pro-tip | Verification task | Proposed |

---

## 6. Ambiguities & Open Questions

| ID | Question | Impact | Resolution Needed |
|----|----------|--------|-------------------|
| **AMB-001** | Which kubelet configuration method to use: `/var/lib/kubelet/config.yaml` vs systemd drop-in? | Implementation approach for REQ-004 | Decision required: config.yaml is more "Kubernetes-native"; drop-in is more "systemd-native". Config.yaml preferred for consistency with kubeadm. |
| **AMB-002** | Should the fix target `cgroupfs` (as documented) or `systemd` (alternative mentioned in diagnosis)? | Affects REQ-001, REQ-002, REQ-004 values | Diagnosis recommends `cgroupfs` as simplest for Ubuntu 22.04 + cgroup v2. Confirm with user. |
| **AMB-003** | What Helm installation method for Helm itself? (apt, snap, binary download) | REQ-009 implementation | Ubuntu 22.04 has Helm in snap; binary download is version-controllable. Recommend binary download to `/usr/local/bin`. |
| **AMB-004** | Should Cilium version be pinned to specific version (e.g., 1.20.1) or use latest? | REQ-012 default value | Diagnosis mentions `v1.20.1` was used. Recommend pinning to known-working version via variable. |
| **AMB-005** | Where should the wait-for-ready task live? In control plane role, or as a separate playbook task? | REQ-008 placement | Since it requires `kubectl` access to API server, it must run on/from control plane. Place in `k8s_control_plane` role or main playbook. |
| **AMB-006** | Should the verification task (assert driver match) be a hard failure or warning? | REQ-018 behavior | Recommend hard failure (block Cilium install) to prevent deploying with mismatch. |

---

## 7. Implementation Notes

### 7.1 Files to Modify

| File | Requirements Addressed |
|------|------------------------|
| `src/ansible/roles/k8s_control_plane/templates/containerd.toml.j2` | REQ-001 |
| `src/ansible/roles/k8s_worker_node/templates/containerd.toml.j2` | REQ-002 |
| `src/ansible/roles/k8s_control_plane/handlers/main.yml` | REQ-003, REQ-006 |
| `src/ansible/roles/k8s_worker_node/handlers/main.yml` | REQ-003, REQ-006 |
| `src/ansible/roles/k8s_control_plane/tasks/main.yml` | REQ-004, REQ-005, REQ-007, REQ-009, REQ-010, REQ-011 |
| `src/ansible/roles/k8s_worker_node/tasks/main.yml` | REQ-004, REQ-005, REQ-007 |
| `src/ansible/roles/k8s_control_plane/defaults/main.yml` | REQ-012 (Cilium version variable) |
| `src/ansible/playbooks/kubernetes-onboarding.yml` | REQ-007, REQ-008 (ordering) |

### 7.2 Key Technical Details

- **Containerd version:** 2.2.1 → uses plugin key `io.containerd.cri.v1.runtime` (not v1/grpc)
- **OS:** Ubuntu 22.04, systemd PID 1, cgroup v2
- **Runc behavior:** Compiled with systemd cgroup support → enforces `slice:prefix:name` format when `SystemdCgroup=true`
- **Kubelet behavior:** Overrides configured `cgroupDriver` with CRI-reported driver at startup
- **Fix validation:** `crictl info | grep SystemdCgroup` → `false`; kubelet log → `cgroupDriver="cgroupfs"`

---

## 8. Dependencies & Assumptions

| Assumption | Validation |
|------------|------------|
| Terraform-provisioned VMs are accessible via Ansible inventory | Inventory `src/ansible/inventory/kube/inventory.yml` exists and correct |
| Control plane host has `kubectl` configured and can reach API server | `k8s_control_plane` role sets up kubeconfig |
| Worker nodes can join cluster via kubeadm join token | `k8s_worker_node` role handles join |
| Internet access for Helm repo add and chart pull | Network connectivity from control plane |
| Ansible run with sufficient privileges (become: yes) | Playbook uses become |

---

## 9. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-09-01 | Requirements Engineer | Initial requirements extraction from CLUSTER_FIX_DIAGNOSIS.md and user request |

---

*End of Requirements Document*