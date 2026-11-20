# k3sraspbian

Ansible project that provisions a lightweight Kubernetes (k3s) cluster on Raspberry Pis.
Fork/derivative of [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible), adapted for
**64-bit Raspberry Pi OS** (not 32-bit Raspbian). Remote: `git@github.com:nethrose/k3sraspbian`
(**public**).

This repo provisions the *nodes*. Workloads on the cluster are managed separately by the
`k3s-gitops` repo (Flux). For homelab-wide context and the full rebuild runbook, see the
`homelab-k3s-pi` skill in the k3s-gitops repo
(`../k3s-gitops/.claude/skills/homelab-k3s-pi/SKILL.md`); the step-by-step provisioning runbook
is the project skill `.claude/skills/provision-k3s-pis`.

## Topology

- 1 control-plane node (group `k3sleaders`, host `leader01`) running `k3s server`.
- 3 agents (group `k3sfollowers`, hosts `follower01`..`follower03`) running `k3s agent`.
- k3s API on port `6443`. systemd units: `k3s.service` (server), `k3s-node.service` (agent).

## Layout

- `site.yml` — install: on `k3s_cluster` runs `node_dns`, then `homelab_admin` (user `snuffy`),
  `k3s_setup`, `prereq`, `download`, `raspberrypi`; then `k3s/master` on `k3sleaders` and
  `k3s/node` on `k3sfollowers`.
- `roles/node_dns` — pins each node's DNS to `node_dns_servers` (public resolvers) via
  NetworkManager global DNS or `dhcpcd.conf`, whichever manager is detected active; fails closed
  if neither is active. Sets `k3s_resolv_conf_flag` (consumed by the k3s service templates as
  `--resolv-conf`) only if `/etc/resolv.conf` is a `systemd-resolved` stub. See README.md
  "Node DNS (Pi-hole compatibility)" for why and how to verify.
- `twingate-ssh-sshd.yml` — install `TrustedUserCAKeys` on k3s Pis from
  `twingate_gateway_user_ca_pubkey` (k3s-gitops `scripts/gen-gateway-cas.sh`). NAS: `homelab-nas.yml`
  only.
- `reset.yml` — teardown (stop services, kill containerd shims, unmount, remove binaries/data).
- `roles/k3s_setup` — resolves `k3s_version` by querying the GitHub releases API at run time.
- `roles/raspberrypi` — Pi detection + cgroup flags (`/boot/firmware/cmdline.txt` on modern Pi OS)
  + iptables backend selection (nft by default; legacy only if `k3s_use_iptables_legacy` AND the
  `ip_tables` module exists).
- `inventory/sample` — template inventory (SSH user `pi`).
- `inventory/my-cluster` — author's real inventory (fixed IPs, per-host SSH user = hostname).
- `patching.yml` / `roles/unattended_upgrades` — unattended OS security updates on `k3s_cluster`.
  Never reboots a node itself (coordinated reboots are `kured` in `k3s-gitops`); see README
  "Unattended security updates" for what it installs and why.

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml              # install
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml  # after Flux + gateway
ansible-playbook -i inventory/my-cluster/hosts.yml upgrade.yml         # rolling k3s upgrade to the pin
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml           # teardown
./scripts/fetch-kubeconfig.sh                # kubeconfig → ~/.kube/k3s-rbps.yaml
./scripts/post-k3s-bootstrap.sh              # incl. the grafana-admin secret k3s-gitops waits on
```

`homelab_admin_user` (`snuffy`) must match `gateway.ssh.gateway.username` in `k3s-gitops`.

A reboot is expected after the cgroup `cmdline.txt` change on first provision.

## Known gotchas (do not re-trip on these)

- `ansible.cfg` defaults to `inventory/my-cluster/hosts.yml` on this Linux box.
- `inventory/my-cluster` pins `k3s_version` with `k3s_use_latest_version: false`. The pin must equal
  what the nodes run (`k3s --version`): the `download` role swaps `/usr/local/bin/k3s` to the pin on
  every run and k3s loads it at its next restart. The role refuses a downgrade or a multi-minor jump.
  Upgrade one minor at a time by bumping the pin (README "Upgrading k3s").
- The k3s roles are idempotent: units use `state: started` plus a restart handler, so an unchanged
  run leaves k3s alone (verified 2026-09-09: second run `changed=0` on all nodes).
- The join token lives only in `/etc/systemd/system/k3s-node.service.env` (root, 0600,
  `K3S_TOKEN`); the unit is 0644 and token tasks are `no_log`. Still treat `--diff` output as
  secret.
- `reset.yml` targets `k3s_cluster` only; the NAS is out of scope by design.
- `inventory/my-cluster` sets each host's `ansible_user` to a literal, not `"{{ inventory_hostname }}"`:
  under `delegate_to`, `inventory_hostname` resolves to the delegating host, not the delegate target, so
  a templated `ansible_user` silently connects as the wrong user (hit in `upgrade.yml`'s agent-wait task,
  delegated to the leader — SSH was refused as the agent's own name). Any new `delegate_to` must use a
  host whose `ansible_user` is literal, or set the user explicitly on the task.
- Any read-only probe a later task's guard depends on (e.g. `roles/download`'s installed-version check)
  needs `check_mode: false`: `command`/`shell` skip in `--check` by default, returning empty `stdout`, and
  a guard that indexes into it crashes. A wait task gated on a restart that's a no-op in check mode needs
  `when: not ansible_check_mode` instead, or it retries for the full `retries * delay` before failing.
- `homelab_admin` with `homelab_admin_install_ssh_pubkey: false` (the `my-cluster` default)
  **removes** the admin's static `authorized_keys` entry on every run — intentional, SSH auth is
  via the Twingate gateway CA. Only flip it to `true` for a bootstrap where the gateway is not up.
- The NAS (`homelab_nas`) is hardened differently from the Pi nodes (item 12, 2026-11-18):
  admin user in `_ssh` not `root`, no passwordless sudo, `TrustedUserCAKeys` set through OMV's
  `Ssh` RPC (OMV discards an sshd_config.d drop-in or a direct sshd_config edit). This is driven
  entirely by `inventory/my-cluster/group_vars/homelab_nas.yml` overriding `homelab_admin` and
  `twingate_ssh_sshd` role defaults; the Pi nodes keep the role defaults unchanged. Any new
  per-host-group behavior in those two roles should follow the same pattern: a role default that
  preserves today's behavior, overridden only in that group's `group_vars`.
- `prereq` role contains upstream RHEL/SELinux tasks that are dead code on Pi OS (harmless).
- `roles/node_dns`'s NetworkManager reload handler must use `nmcli general reload conf,dns-rc`
  (`conf` re-reads `conf.d/*.conf`, `dns-rc` rewrites `/etc/resolv.conf`); `dns` alone is not a
  valid flag on current NetworkManager (`nmcli general reload help` lists `conf`, `dns-rc`,
  `dns-full`). Ansible does run notified handlers in check mode, as check-mode calls: a module
  handler such as `systemd` reports changed without acting, and a raw `command` or `shell` handler
  is skipped, so a dry run still cannot catch a broken handler command —
  `roles/node_dns/tasks/main.yml` compensates with a plain (non-handler) task
  that reads `/etc/resolv.conf` and re-notifies the reload whenever it doesn't yet match
  `node_dns_servers`, so the role converges even when the drop-in file was already written by a
  prior run whose reload failed or never fired, and `--check` reports truthfully. Any new handler
  in this repo that runs a raw `command`/`shell` (not a dedicated module like `systemd`/`service`)
  has the same blind spot — verify its exact syntax against the real tool before relying on lint
  or `--syntax-check` alone.
- `inventory/my-cluster` sets `extra_server_args: "--disable=traefik --disable=gateway-api-crd"` (README "Configuration"):
  nothing on this cluster uses the bundled Traefik ingress controller; the second item stops k3s >= 1.37
  deploying its Gateway API CRD component. The flag goes into the
  leader's `k3s.service` unit (`roles/k3s/master/templates/k3s.service.j2`), so changing it
  restarts the k3s server only, per the role's `Restart k3s` handler — never the agents.
- CI (`.github/workflows/validate.yml`) runs yamllint + syntax-check, and ansible-lint on
  `homelab_admin`, `twingate_ssh_sshd`, `k3s`, `k3s_setup`, `node_dns`, `download`,
  `unattended_upgrades`, `upgrade.yml`, `patching.yml` (`prereq`/`reset` still skipped), plus
  shellcheck on the two `unattended_upgrades` scripts.
- `roles/unattended_upgrades` requires `apt_upgrade_time` set per host in
  `inventory/my-cluster/host_vars/` (fails closed otherwise) to stagger
  `apt-daily-upgrade.timer` across the cluster. The two shell scripts
  (`node-reboot-required.sh`, `node-patch-metrics.sh`) read `NODE_REBOOT_REQUIRED_*` /
  `NODE_PATCH_METRICS_*` env vars that default to the real paths — only tests should set them.
  The textfile metric names (`node_apt_upgrades_pending`, `node_reboot_required`, etc.) are
  matched by alerts in `k3s-gitops`; don't rename them there without updating that repo too.

## Hardware / network

- Raspberry Pi (64-bit OS), microSD boot. Nodes reachable over SSH.
- Networking is fixed-DHCP via reservations on the router (eth0 MAC → IP); reflashing does not change
  the MAC. Capture each node's MAC/IP during discovery before relying on addresses.

## Backlog

The full 2026-07-02 review backlog (idempotency, token handling, GitHub API once-per-play, sample
inventory pin, dead code) lives in the local `k3s-gitops/TODO.md` under "Repo review findings"
(gitignored).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
