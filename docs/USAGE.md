# Kubernetes Cluster Cgroup Driver Fix & Cilium Installation — Usage Guide

> **Purpose:** This document explains how to apply the cgroup driver fix (containerd/kubelet mismatch) and install Cilium CNI via Helm using the Ansible playbooks in this repository.

---

## 1. Feature Overview & Purpose

This feature resolves a critical **cgroup driver mismatch** between `containerd` and `kubelet` that prevented Kubernetes nodes from reaching `Ready` state and blocked Cilium CNI initialization.

### The Problem (Before the Fix)

| Symptom | Root Cause |
|---------|------------|
| All nodes stuck in `NotReady` | `containerd` configured with `SystemdCgroup = true` |
| Pods (`cilium-*`, `kube-proxy`, `coredns`) stuck in `ContainerCreating` / `Init:0/6` | `kubelet` running with `cgroupfs` driver (overriding its `systemd` config) |
| Error: `expected cgroupsPath to be of format "slice:prefix:name" for systemd cgroups, got "/kubepods/burstable/pod<uid>/<sandbox-id>" instead` | Ubuntu 22.04 `runc` (compiled with systemd cgroup support) rejects cgroupfs-style paths when `SystemdCgroup=true` |

**Key insight:** Cilium was a **red herring** — the cluster failed *before* Cilium could even start. No sandbox could be created → CNI plugin never initialized → nodes never became Ready.

### The Solution

Normalize **both** `containerd` and `kubelet` to use the **`cgroupfs`** driver consistently:

1. Set `SystemdCgroup = false` in containerd config (control plane + workers)
2. Restart containerd
3. Explicitly configure kubelet with `--cgroup-driver=cgroupfs` via systemd drop-in
4. Restart kubelet
5. Wait for nodes to become `Ready`
6. Install Helm on control plane
7. Install Cilium via Helm

---

## 2. Root Cause Explanation (Detailed)

### The Mismatch Chain

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BEFORE THE FIX                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  kubelet config.yaml:     cgroupDriver: systemd                            │
│         │                                                                   │
│         ▼ (overridden at runtime by CRI-reported driver)                   │
│  kubelet actual driver:   cgroupfs  ◄─── "Using cgroup driver setting      │
│                              received from the CRI runtime"                │
│         │                                                                   │
│         ▼ (sends cgroupfs-style parent path to containerd)                 │
│  containerd config:       SystemdCgroup = true                             │
│         │                                                                   │
│         ▼ (hands cgroupfs path to runc)                                    │
│  runc (Ubuntu 22.04):     REJECTS path — expects "slice:prefix:name"       │
│         │                                                                   │
│         ▼                                                                   │
│  SANDBOX CREATION FAILS → CNI NEVER INITIALIZES → NODES NotReady           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Diagnostic Log Lines (from the failing cluster)

```bash
# kubelet log — shows it OVERRIDES config.yaml to cgroupfs
$ journalctl -u kubelet | grep -i "cgroup driver setting"
"Using cgroup driver setting received from the CRI runtime" cgroupDriver="cgroupfs"

# containerd config — shows SystemdCgroup=true
$ crictl info | grep -i SystemdCgroup
"SystemdCgroup": true

# The fatal error repeating in containerd journal
$ journalctl -u containerd | grep -i "expected cgroupsPath"
expected cgroupsPath to be of format "slice:prefix:name" for systemd cgroups,
got "/kubepods/burstable/pod<uid>/<sandbox-id>" instead
```

### Why `cgroupfs` Was Chosen

- Ubuntu 22.04 runs systemd as PID 1 with cgroup v2
- Both `cgroupfs` and `systemd` are valid **if they match on both sides**
- `cgroupfs` is simpler: no systemd slice hierarchy needed, works reliably with the current runc
- The fix normalizes to `cgroupfs` on **both** containerd and kubelet

---

## 3. Installation / Setup / How to Run

### Prerequisites

- Ansible control machine with access to target hosts
- Inventory configured at `src/ansible/inventory/kube/inventory.yml` with groups:
  - `kube_control_plane` (1 host)
  - `kube_worker` (N hosts)
- SSH access with `become: yes` (sudo) on all targets
- Ubuntu 22.04 on target hosts
- Internet access from control plane for Helm repo and chart downloads

### Running via Ansible Playbook (Primary Method)

```bash
cd /Users/ameymahadik/REPOS/OpenSource/HomeServer.Infrastructure

# Apply the fix + install Cilium in one run
ansible-playbook -i src/ansible/inventory/kube/inventory.yml \
  src/ansible/playbooks/kubernetes-onboarding.yml
```

### Running via CI/CD (GitHub Actions)

The repository includes a CI workflow (`.github/workflows/ansible-apply.yml`) that runs automatically after the Terraform apply workflow completes. To trigger manually:

1. Go to **Actions** → **Ansible Apply** → **Run workflow**
2. Select the target environment/branch
3. The workflow executes the same playbook against the Terraform-provisioned inventory

### What the Playbook Does (High-Level)

```yaml
# kubernetes-onboarding.yml
- name: Onboard Kubernetes control plane nodes
  hosts: kube_control_plane
  become: true
  roles:
    - k8s_control_plane    # ← Contains the fix + Helm + Cilium

- name: Onboard Kubernetes worker nodes
  hosts: kube_worker
  become: true
  roles:
    - k8s_worker_node      # ← Contains the fix (no Helm/Cilium)
```

---

## 4. Configuration Options

All configurable variables are defined in role `defaults/main.yml` files. Override them via:
- Inventory `group_vars` / `host_vars`
- `-e` / `--extra-vars` on the command line
- Ansible Vault for secrets

### Control Plane Role (`src/ansible/roles/k8s_control_plane/defaults/main.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `kubelet_cgroup_driver` | `"cgroupfs"` | Cgroup driver for kubelet (must match containerd). **Do not change unless you also change containerd.** |
| `helm_version` | `"v3.16.4"` | Helm binary version to install |
| `helm_arch` | `"amd64"` | Architecture for Helm binary |
| `helm_os` | `"linux"` | OS for Helm binary |
| `helm_checksum` | `"sha256:fc307327959aa38ed8f9f7e66d45492bb022a66c3e5da6063958254b9767d179"` | SHA256 of the Helm tarball. **Must be updated if `helm_version` changes.** |
| `cilium_repo_url` | `"https://helm.cilium.io/"` | Cilium Helm repository URL |
| `cilium_repo_name` | `"cilium"` | Local name for the Helm repo |
| `cilium_release_name` | `"cilium"` | Helm release name |
| `cilium_namespace` | `"kube-system"` | Namespace to install Cilium into |
| `cilium_version` | `"1.20.1"` | Cilium chart version (pinned). Verify compatibility with your Kubernetes version (v1.36). |
| `cilium_image_pull_policy` | `"IfNotPresent"` | Image pull policy for Cilium pods |
| `cilium_ipam_mode` | `"kubernetes"` | IPAM mode (`kubernetes`, `cluster-pool`, `eni`, etc.) |
| `cilium_etcd_enabled` | `false` | Use etcd for KV-store (false = use Kubernetes API server) |

### Worker Node Role (`src/ansible/roles/k8s_worker_node/defaults/main.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `kubelet_cgroup_driver` | `"cgroupfs"` | Cgroup driver for kubelet (must match containerd and control plane) |

### Shared Kubernetes Variables (both roles)

| Variable | Default | Description |
|----------|---------|-------------|
| `k8s_repo_version` | `"v1.36"` | Kubernetes apt repository minor version |
| `k8s_package_version` | `"1.36.0-1.1"` | Exact package version for kubelet/kubeadm/kubectl |
| `k8s_pod_network_cidr` | `"10.244.0.0/16"` (control) / `"10.200.0.0/24"` (worker) | Pod network CIDR |
| `k8s_discovery_ipv4` / `k8s_ctrl_discovery_ipv4` | `"10.200.0.200"` | Control plane API server address |

### Example: Overriding Variables

```bash
# Use a different Cilium version
ansible-playbook -i src/ansible/inventory/kube/inventory.yml \
  -e "cilium_version=1.21.0" \
  src/ansible/playbooks/kubernetes-onboarding.yml

# Use a different Helm version (update checksum too!)
ansible-playbook -i src/ansible/inventory/kube/inventory.yml \
  -e "helm_version=v3.17.0 helm_checksum=sha256:NEW_CHECKSUM_HERE" \
  src/ansible/playbooks/kubernetes-onboarding.yml
```

---

## 5. What Happens During the Run

### Task Ordering (Control Plane Role)

The tasks execute in this strict order (enforced by `meta: flush_handlers`):

```
1.  Load kernel modules (overlay, br_netfilter)
2.  Configure sysctl (IP forwarding, bridge nf call)
3.  Install containerd (apt)
4.  Create /etc/containerd directory
5.  Deploy containerd config (SystemdCgroup=false)  ──notify──▶ [Restart containerd]
6.  Add Kubernetes apt repo + GPG key
7.  Install kubelet, kubeadm, kubectl (pinned version)
8.  Hold Kubernetes package versions
9.  Configure kubelet cgroup driver via systemd drop-in  ──notify──▶ [Restart kubelet]
10. FLUSH HANDLERS (containerd + kubelet restart NOW)
11. Ensure kubelet enabled & started
12. Check if cluster already initialized (admin.conf exists)
13. kubeadm init (if not initialized)
14. Copy kubeconfig to root + admin user
15. Generate join token + CA cert hash
16. Set facts for worker nodes
17. WAIT FOR CONTROL PLANE NODE READY (60 retries × 5s)
18. ASSERT DRIVER MATCH (hard fail if containerd≠false or kubelet≠cgroupfs)
19. Check/install Helm (binary to /usr/local/bin, checksum verified)
20. Add Cilium Helm repo + update
21. Install Cilium via Helm (idempotent: skipped if release exists)
```

### Task Ordering (Worker Node Role)

```
1.  Load kernel modules
2.  Configure sysctl
3.  Install containerd
4.  Create /etc/containerd directory
5.  Deploy containerd config (SystemdCgroup=false)  ──notify──▶ [Restart containerd]
6.  Add Kubernetes apt repo + GPG key
7.  Install kubelet, kubeadm, kubectl
8.  Hold Kubernetes package versions
9.  Configure kubelet cgroup driver via systemd drop-in  ──notify──▶ [Restart kubelet]
10. FLUSH HANDLERS (containerd + kubelet restart NOW)
11. Ensure kubelet enabled & started
12. Check if already joined (kubelet.conf exists)
13. kubeadm join (if not joined)
```

### Idempotency Behavior

| Task | Idempotency Mechanism |
|------|----------------------|
| Containerd config template | Only notifies restart if content changes |
| Kubelet drop-in template | Only notifies restart if content changes |
| `meta: flush_handlers` | Runs handlers only when notified |
| `kubeadm init` | Guarded by `admin.conf` existence check |
| `kubeadm join` | Guarded by `kubelet.conf` existence check |
| Helm install | Guarded by `helm version` check (version match) |
| Cilium repo add | Tolerates "already exists" in output |
| Cilium Helm install | Guarded by `helm list` — skipped if release exists |

**Re-running the playbook is safe** — it will only make changes if configuration has drifted.

---

## 6. Usage / Verification

After the playbook completes, verify the fix worked:

### 6.1 Node Readiness

```bash
# All nodes should show Ready
kubectl get nodes
# Expected:
# NAME            STATUS   ROLES           AGE   VERSION
# kube-ctrl       Ready    control-plane   5m    v1.36.0
# kube-worker-0   Ready    <none>          4m    v1.36.0
```

### 6.2 System Pods Running

```bash
# All pods in kube-system should be Running (or Completed for jobs)
kubectl get pods -A
# Expected: cilium-*, kube-proxy-*, coredns-* all Running
```

### 6.3 Containerd Cgroup Driver

```bash
# On each node (control plane + workers)
crictl info | grep -i SystemdCgroup
# Expected: "SystemdCgroup": false
```

### 6.4 Kubelet Cgroup Driver

```bash
# Option A: Check kubelet config (if kubeadm wrote it)
grep cgroupDriver /var/lib/kubelet/config.yaml
# Expected: cgroupDriver: cgroupfs

# Option B: Check kubelet logs (shows actual driver at startup)
journalctl -u kubelet --no-pager --since "5 min ago" | grep -i "cgroup driver setting"
# Expected: cgroupDriver="cgroupfs"

# Option C: Check the systemd drop-in
cat /etc/systemd/system/kubelet.service.d/10-cgroup.conf
# Expected: Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs"
```

### 6.5 Helm Installation

```bash
# On control plane only
which helm && helm version
# Expected: version v3.16.4 (or your configured version)
```

### 6.6 Cilium Helm Release

```bash
# On control plane
helm list -n kube-system
# Expected: NAME    NAMESPACE   REVISION  UPDATED   STATUS    CHART       APP VERSION
#           cilium  kube-system 1         ...       deployed  cilium-1.20.1  1.20.1

helm status cilium -n kube-system
# Expected: STATUS: deployed
```

### 6.7 Cilium Pods Specifically

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
# Expected: All cilium pods Running (cilium-*, cilium-operator-*, cilium-envoy-*)
```

---

## 7. Limitations & Caveats

| Limitation | Details | Workaround / Note |
|------------|---------|-------------------|
| **Control-plane-first wait** | The wait-for-ready task only waits for the control plane node to become Ready. Workers join in a separate play. | Acceptable — Cilium DaemonSet rolls out to workers as they join. If you need strict "all nodes Ready", modify the wait task to check for expected node count. |
| **Cgroup driver normalized to `cgroupfs`** | Both containerd and kubelet **must** use the same driver. Changing one without the other will break the cluster again. | If you need `systemd` driver, change BOTH `SystemdCgroup = true` in containerd templates AND `kubelet_cgroup_driver: "systemd"` in defaults. |
| **Helm checksum tied to version** | `helm_checksum` must match the pinned `helm_version`. Updating one without the other breaks the install. | Always update both together. Get checksum from <https://get.helm.sh/helm-{version}-linux-amd64.tar.gz.sha256> |
| **Cilium version pinned to 1.20.1** | Default `cilium_version: "1.20.1"` is pinned for reproducibility. Must be compatible with Kubernetes v1.36. | Check Cilium compatibility matrix before upgrading. Override with `-e cilium_version=X.Y.Z` if needed. |
| **Helm binary integrity via SHA256 only** | No GPG signature verification — only SHA256 checksum of the tarball. | Acceptable for most environments. For higher security, add GPG verification step. |
| **No CNI before Cilium** | The cluster has no CNI until Cilium installs. Nodes will be NotReady until step 21 completes. | This is by design — the fix enables Cilium to install successfully. |
| **Worker nodes join after Cilium install on control plane** | Cilium is installed in the control-plane play; workers join in the worker play. | Cilium DaemonSet automatically schedules on new nodes as they join. |

---

## 8. Troubleshooting

### 8.1 Nodes Still NotReady After Playbook Run

```bash
# 1. Check containerd driver
crictl info | grep -i SystemdCgroup
# If "true" → containerd config not applied or not restarted

# 2. Check kubelet driver
journalctl -u kubelet --no-pager --since "10 min ago" | grep -i "cgroup driver setting"
# If "systemd" → kubelet drop-in not applied or not restarted

# 3. Check containerd logs for the fatal error
journalctl -u containerd --no-pager | grep -i "expected cgroupsPath"
# If present → mismatch still exists

# 4. Force restart both services
sudo systemctl restart containerd kubelet
```

### 8.2 Containerd SystemdCgroup Mismatch

```bash
# Verify the deployed config
grep -A2 "runc.options" /etc/containerd/config.toml
# Should show: SystemdCgroup = false

# If it shows true, re-run the playbook (template task is idempotent)
# Or manually fix and restart:
sudo sed -i 's/SystemdCgroup = true/SystemdCgroup = false/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

### 8.3 Helm Repo Already Exists (Non-Error)

```bash
# This is handled gracefully by the playbook (changed_when/failed_when tolerate it)
# If you see this in output, it's normal:
# "repository cilium already exists"
```

### 8.4 Helm Checksum Mismatch

```bash
# Error: "checksum mismatch" during Helm download
# Cause: helm_version changed but helm_checksum not updated
# Fix: Get correct checksum from Helm releases page:
curl -sL https://get.helm.sh/helm-v3.16.4-linux-amd64.tar.gz.sha256
# Update helm_checksum in defaults/main.yml or via -e
```

### 8.5 Driver-Verify Task Failing

```bash
# Task: "Assert containerd and kubelet cgroup drivers match"
# Failure output shows:
# containerd SystemdCgroup=... kubelet cgroupDriver=...

# Common causes:
# 1. Handlers didn't flush before verification → ensure meta:flush_handlers ran
# 2. crictl not in PATH → install containerd first (playbook does this)
# 3. jq not installed → verification falls back to grep (works but slower)
# 4. Journal logs rotated → falls back to config.yaml

# Debug manually:
crictl info -o json | jq -r '.config.containerd.runtimes.runc.options.SystemdCgroup'
grep cgroupDriver /var/lib/kubelet/config.yaml
```

### 8.6 Cilium Pods Stuck in Init/ContainerCreating

```bash
# If Cilium installed but pods not Running:
kubectl describe pod -n kube-system -l k8s-app=cilium
# Check events for: CNI config not found, IPAM errors, etc.

# Common fix: Ensure kubelet has --cgroup-driver=cgroupfs (drop-in present)
# and containerd restarted after config change.
```

---

## 9. References

| Document | Purpose |
|----------|---------|
| [`specs/REQUIREMENTS.md`](../specs/REQUIREMENTS.md) | Formal requirements (REQ-001 → REQ-018) with acceptance criteria |
| [`docs/plans/PLAN.md`](../docs/plans/PLAN.md) | Implementation plan with design decisions (DEC-1 → DEC-6), step-by-step tasks, risk matrix |
| [`.temp/CLUSTER_FIX_DIAGNOSIS.md`](../.temp/CLUSTER_FIX_DIAGNOSIS.md) | Original root cause diagnosis with log excerpts and manual fix commands |
| [`docs/ansible/00_kube_setup.md`](../docs/ansible/00_kube_setup.md) | Overall Ansible setup documentation (inventory, CI, paths) |

### Key Source Files (for reference)

| File | Role |
|------|------|
| `src/ansible/roles/k8s_control_plane/tasks/main.yml` | Control plane task sequence (fix + Helm + Cilium) |
| `src/ansible/roles/k8s_worker_node/tasks/main.yml` | Worker node task sequence (fix only) |
| `src/ansible/roles/k8s_control_plane/templates/containerd.toml.j2` | Containerd config template (SystemdCgroup=false) |
| `src/ansible/roles/k8s_worker_node/templates/containerd.toml.j2` | Worker containerd config template |
| `src/ansible/roles/k8s_control_plane/templates/kubelet-cgroup.conf.j2` | Kubelet systemd drop-in template |
| `src/ansible/roles/k8s_worker_node/templates/kubelet-cgroup.conf.j2` | Worker kubelet drop-in template |
| `src/ansible/playbooks/kubernetes-onboarding.yml` | Main playbook (2 plays: control plane → workers) |

---

## 10. Quick Reference Card

```bash
# Apply the fix + install Cilium
ansible-playbook -i src/ansible/inventory/kube/inventory.yml \
  src/ansible/playbooks/kubernetes-onboarding.yml

# Verify nodes Ready
kubectl get nodes

# Verify containerd driver (run on each node)
crictl info | grep SystemdCgroup   # → false

# Verify kubelet driver (run on each node)
journalctl -u kubelet | grep "cgroup driver setting"   # → cgroupfs

# Verify Helm
helm version   # → v3.16.4

# Verify Cilium
helm list -n kube-system
helm status cilium -n kube-system
kubectl get pods -n kube-system -l k8s-app=cilium
```

---

*Generated from implementation artifacts. For questions or issues, refer to the linked reference documents or the Ansible role source code.*