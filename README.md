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
| `upgrade.yml` | Rolling k3s upgrade to the pinned `k3s_version` |
| `patching.yml` | Unattended OS security updates on `k3s_cluster` nodes (see below) |
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
| `k3s_use_latest_version` | `false` in `my-cluster` (`true` in `sample`) | Fetch latest k3s from GitHub instead of using the pin below |
| `k3s_version` | `v1.37.2+k3s1` | Pinned version installed when `k3s_use_latest_version` is `false` |
| `homelab_admin_user` | `homelab` | Shared admin + Twingate SSH upstream user |
| `homelab_admin_ssh_pubkey_file` | `~/.ssh/id_rsa.pub` | SSH key for admin user |
| `node_dns_servers` | `[1.1.1.1, 9.9.9.9]` | Public DNS the k3s nodes resolve through directly (see "Node DNS" below) |
| `extra_server_args` | `--disable=traefik` in `my-cluster` | Extra flags appended to `k3s server`; `my-cluster` disables the bundled Traefik ingress controller (unused on this cluster) so it stops listening on :80/:443 on every node. Changing this value changes the leader's `k3s.service` unit, which restarts the k3s server |
| `extra_agent_args` | `""` | Extra flags appended to `k3s agent` |
| `prereq_enable_ipv6_forwarding` | `true` (role default); `false` in `my-cluster` | Whether the `prereq` role sets `net.ipv6.conf.all.forwarding=1`. `my-cluster` is IPv4-only and its nodes don't run with it, so it's left untouched |

## Node DNS (Pi-hole compatibility)

`roles/node_dns` pins every k3s node's DNS to `node_dns_servers` (public resolvers, not the
router/DHCP-supplied DNS), persistently across reboots and DHCP renewals. This keeps the nodes —
and therefore CoreDNS (which forwards to the node's `/etc/resolv.conf`) and any in-cluster
Twingate connector — resolving even if you point your router's DNS at a Pi-hole on the LAN and
that Pi-hole goes down. The NAS and the Pi-hole deployment itself are out of scope for this repo.

It detects which DNS manager is active on each node and uses that manager's supported, idempotent
mechanism:

- **NetworkManager** (Raspberry Pi OS Bookworm/Trixie, the current default): a global DNS drop-in
  at `/etc/NetworkManager/conf.d/10-node-dns.conf`, applied with `nmcli general reload conf,dns-rc`.
- **dhcpcd** (Raspberry Pi OS Bullseye and earlier): a `static domain_name_servers=...` line
  managed in `/etc/dhcpcd.conf`, applied with a `dhcpcd` restart.

If neither is active, the play fails on that host instead of guessing. If `/etc/resolv.conf`
turns out to be a `systemd-resolved` stub (`127.0.0.53`), the role also sets
`k3s_resolv_conf_flag`, which `k3s server`/`k3s agent` pick up via `--resolv-conf` so CoreDNS
doesn't try to forward to the stub — no other k3s flags are touched.

`roles/node_dns` is tagged `node_dns`, so it can run on its own without touching the rest of
`site.yml` (k3s, Pi prereqs, the admin user). Apply just the DNS change:

```fish
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml --tags node_dns
```

A full `ansible-playbook -i inventory/my-cluster/hosts.yml site.yml` (no `--tags`) is only needed
when the `systemd-resolved` stub case above sets `k3s_resolv_conf_flag` — that changes the k3s
unit files and restarts `k3s`/`k3s-node` on every node, so the k3s roles need to run too.

Verify on a node (SSH or Twingate SSH):

```fish
# Confirm the node itself resolves through the public servers, not the router/Pi-hole
cat /etc/resolv.conf
resolvectl status   # if present; NetworkManager nodes show the DNS servers per interface

# Confirm CoreDNS in the cluster resolves correctly from a node that's off Pi-hole
kubectl run dns-test --rm -it --restart=Never --image=busybox:1.36 -- nslookup kubernetes.default
```

## Upgrading k3s

`my-cluster` pins `k3s_version` so re-running `site.yml` never jumps minors unexpectedly; the
`download` role also refuses to install anything older than what's already running, or a jump
of more than one minor. To upgrade, step **one minor at a time**: bump `k3s_version` in
`inventory/my-cluster/group_vars/all.yml` to the newest patch of the next minor (e.g.
`v1.36.6+k3s1` → `v1.37.2+k3s1`), then run `upgrade.yml` — it upgrades the server first, then
each agent one at a time, restarting k3s onto the new binary (`site.yml` alone only swaps the
binary on disk and never restarts k3s). Confirm the cluster is healthy, then repeat for the next
minor. Do not set `k3s_use_latest_version: true` against a live cluster — it fetches whatever is
newest on GitHub and can skip several minors in one run.

Take the target from the k3s release channel for that minor, which redirects to the newest
release in it:

```bash
curl -s -o /dev/null -w '%{redirect_url}\n' https://update.k3s.io/v1-release/channels/v1.37
```

Read the Kubernetes and k3s release notes for the new minor before bumping. From v1.37, k3s
deploys the Gateway API CRDs as their own packaged component (`gateway-api-crd`), separate from
Traefik, so `--disable=traefik` no longer keeps them off; add `--disable=gateway-api-crd` to
`extra_server_args` to keep them off as well.

## Unattended security updates

`patching.yml` installs `unattended-upgrades` and `apt-listchanges` on every `k3s_cluster` node and
configures security-relevant packages to install overnight, automatically. It does **not** reboot
nodes, even when a kernel update needs one — reboots are coordinated separately, cluster-wide, in
the `k3s-gitops` repo (via `kured`), because that's the only place that can see whether the API and
Pi-hole are healthy before taking a node down.

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml patching.yml --check --diff   # dry run first
ansible-playbook -i inventory/my-cluster/hosts.yml patching.yml
```

What it does on each node:

- Installs from three origins: `Debian-Security` always, plus `Debian` (point-release, no-DSA
  fixes) and `Raspberry Pi Foundation` (kernel, firmware, and RPi rebuilds — e.g. `openssl` — that
  shadow Debian security fixes and have no separate security suite of their own). Set
  `unattended_upgrades_extra_origins: []` in `group_vars`/`host_vars` to narrow installs to
  `Debian-Security` alone.
- Stays off `needrestart` — its interactive restart prompts fight the reboot model below.
- Stays off `Automatic-Reboot` (`"false"` in `52unattended-upgrades-k3s`) — the node sets
  `/run/reboot-required` for the cluster-side tooling to act on, but never reboots itself.
- Stages `apt-daily.timer`/`apt-daily-upgrade.timer` at a different install time per node
  (`apt_upgrade_time` in `inventory/my-cluster/host_vars/`), so sshd/NetworkManager don't all
  restart from a package upgrade at once.
- Sets `/run/reboot-required` itself after every `dpkg` run, since Pi OS kernel packages don't
  (only `dbus`'s postinst does).
- Writes `node_exporter` textfile metrics (`node_apt_upgrades_pending`, `node_apt_lists_age_seconds`,
  `node_unattended_upgrades_last_run_timestamp_seconds`/`_success`, `node_dpkg_audit_problems`,
  `node_reboot_required`/`_info`, `node_kernel_pending`, `node_stale_library_processes`) to
  `/var/lib/node_exporter/textfile_collector/node_patch.prom`, refreshed after every apt run and
  hourly. The metric names are relied on by alerts defined in `k3s-gitops`; don't rename them
  without updating that repo too.

Apt sources stay on plain HTTP: deb.debian.org and archive.raspberrypi.com both serve HTTPS, but
switching isn't done here (not validated end-to-end against these nodes' sources and out of scope
for this change).

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
