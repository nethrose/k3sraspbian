# k3sraspbian

Ansible playbooks to provision **64-bit Raspberry Pi OS** nodes and install [k3s](https://k3s.io/).

Derived from [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible). Application workloads are
deployed separately with your own **Flux / GitOps** repository (not included here).

## Topology (example)

| Role | Hostname | Notes |
|------|----------|-------|
| control-plane | `leader01` | k3s server |
| worker ×3 | `follower01` … `follower03` | k3s agents |

Ships an **example inventory** (`inventory/my-cluster/`) — copy and edit IPs, hostnames, and usernames
for your network.

## Prerequisites

- Ansible 2.14+
- SSH access to each Pi (Imager user per host, or your choice)
- Raspberry Pi OS **64-bit** Lite (or Desktop with GUI disabled)
- Your SSH public key (default path: `~/.ssh/id_rsa.pub`)

## Quick start

```bash
# 1. Customize inventory
cp -r inventory/my-cluster inventory/your-cluster   # optional
# edit hosts.yml (IPs, ansible_user) and group_vars/all.yml (homelab_admin_user, keys)

# 2. Provision k3s + homelab admin user
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml

# Or override the admin username for this run only:
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml -e homelab_admin_user=yourname

# 3. Fetch kubeconfig (from a machine that can SSH to the leader)
./scripts/fetch-kubeconfig.sh
export KUBECONFIG=~/.kube/k3s-rbps.yaml
kubectl get nodes
```

A **reboot** is expected after the first run (cgroup flags in `/boot/firmware/cmdline.txt`).

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `site.yml` | Homelab admin user + k3s server/agents + Pi prereqs |
| `homelab-nas.yml` | Homelab admin user + Twingate SSH CA on a NAS (OMV `admin` bootstrap) |
| `twingate-ssh-sshd.yml` | Trust Twingate gateway User CA on cluster nodes and NAS |
| `reset.yml` | Teardown k3s |

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml homelab-nas.yml --ask-become-pass
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

Requires a Twingate access gateway deployed in-cluster (e.g. via Flux + Twingate operator).

## Homelab admin user

`site.yml` and `homelab-nas.yml` create a shared admin account for day-to-day ops and **Twingate SSH
gateway** upstream auth.

Set the username in **`inventory/.../group_vars/all.yml`**:

```yaml
homelab_admin_user: homelab   # or your preferred name
```

Or per run: `-e homelab_admin_user=yourname`

**Must match** `gateway.ssh.gateway.username` in your GitOps Twingate HelmRelease values.

Connect via Twingate SSH: `ssh <homelab_admin_user>@leader01.ssh` (after gateway + resource CRs are up).

## kubectl

- **Remote:** `twingate kube config autosync` → `kubectl --context=<your-twingate-context> …`
- **LAN admin:** `./scripts/fetch-kubeconfig.sh` → `export KUBECONFIG=~/.kube/k3s-rbps.yaml`

## Configuration

`inventory/my-cluster/group_vars/all.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `k3s_use_latest_version` | `true` | Fetch latest k3s from GitHub |
| `k3s_version` | `v1.31.0+k3s1` | Fallback when latest is disabled |
| `homelab_admin_user` | `homelab` | Shared admin + Twingate SSH upstream user |
| `homelab_admin_ssh_pubkey_file` | `~/.ssh/id_rsa.pub` | SSH key for admin user |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/fetch-kubeconfig.sh` | Pull k3s.yaml from leader, fix API URL |
| `scripts/verify-ssh.sh` | Ping all inventory hosts over SSH |
| `scripts/post-k3s-bootstrap.sh` | Post-Flux helpers (optional) |

## Modern Pi OS notes

- **Cgroup flags** → `/boot/firmware/cmdline.txt`
- **iptables** → nft on kernel 6.18+ (`k3s_use_iptables_legacy: false`)

## GitOps companion

This repo stops at **k3s on metal**. You still need a separate repo for Flux, HelmReleases, and app
manifests. Typical flow: bootstrap Flux → point at your GitOps repo → create out-of-band secrets
(Twingate API key, etc.).

## License

Personal homelab configuration — use as reference; no warranty.
