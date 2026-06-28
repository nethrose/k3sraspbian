# k3sraspbian

Ansible playbooks to provision **64-bit Raspberry Pi OS** nodes and install [k3s](https://k3s.io/).

Derived from [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible). Workloads are deployed
separately via GitOps ([k3s-gitops](https://github.com/nethrose/k3s-gitops)).

## Topology (example)

| Role | Hostname | Notes |
|------|----------|-------|
| control-plane | `leader01` | k3s server |
| worker ×3 | `follower01` … `follower03` | k3s agents |

This repo ships an **example inventory** (`inventory/my-cluster/`) with private LAN IPs — fork and
edit for your network.

## Prerequisites

- Ansible 2.14+
- SSH access to each Pi (user = hostname per SD card image, or your choice)
- Raspberry Pi OS **64-bit** Lite (or Desktop with GUI disabled)
- Your SSH public key at `~/.ssh/id_rsa.pub` (or set `homelab_admin_ssh_pubkey_file`)

## Quick start

```bash
# 1. Edit inventory — IPs, hostnames, k3s version
cp -r inventory/my-cluster inventory/your-cluster   # optional: keep example as reference
# edit inventory/my-cluster/hosts.yml and group_vars/all.yml

# 2. Provision k3s + homelab admin user (snuffy by default)
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml

# 3. Fetch kubeconfig (from a machine that can SSH to the leader)
./scripts/fetch-kubeconfig.sh
export KUBECONFIG=~/.kube/k3s-rbps.yaml
kubectl get nodes
```

A **reboot** is expected after the first run (cgroup flags written to `/boot/firmware/cmdline.txt`).

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `site.yml` | Homelab admin user + k3s server/agents + Pi prereqs |
| `homelab-nas.yml` | `snuffy` user + Twingate SSH CA on CM3588 NAS (OMV `admin` bootstrap) |
| `twingate-ssh-sshd.yml` | Trust Twingate gateway User CA on Pis and NAS |
| `reset.yml` | Teardown k3s |

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml homelab-nas.yml --ask-become-pass
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

Requires Flux + Twingate gateway running (see k3s-gitops `docs/bootstrap.md`).

## kubectl

- **Remote:** `twingate kube config autosync` → `kubectl --context=twingate-k3s-rbps-api …`
- **LAN admin:** `./scripts/fetch-kubeconfig.sh` → `export KUBECONFIG=~/.kube/k3s-rbps.yaml`

## Configuration

`inventory/my-cluster/group_vars/all.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `k3s_use_latest_version` | `true` | Fetch latest k3s from GitHub |
| `k3s_version` | `v1.31.0+k3s1` | Fallback when latest is disabled |
| `homelab_admin_user` | `snuffy` | Shared admin + Twingate SSH upstream user |
| `homelab_admin_ssh_pubkey_file` | `~/.ssh/id_rsa.pub` | SSH key installed for admin user |

`homelab_admin_user` must match `gateway.ssh.gateway.username` in k3s-gitops.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/fetch-kubeconfig.sh` | Pull k3s.yaml from leader, fix API URL |
| `scripts/verify-ssh.sh` | Ping all inventory hosts over SSH |
| `scripts/post-k3s-bootstrap.sh` | Post-Flux helpers (secrets, hints) |

## Modern Pi OS notes

- **Cgroup flags** → `/boot/firmware/cmdline.txt` (not the `/boot/cmdline.txt` stub)
- **iptables** → auto-detects nft vs legacy (`k3s_use_iptables_legacy: false` on kernel 6.18+)

## Related

- [k3s-gitops](https://github.com/nethrose/k3s-gitops) — Flux manifests, Twingate, monitoring
- [k3s-gitops bootstrap runbook](https://github.com/nethrose/k3s-gitops/blob/main/docs/bootstrap.md)

## License

Personal homelab configuration — use as reference; no warranty.
