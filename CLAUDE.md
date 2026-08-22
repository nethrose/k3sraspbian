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

- `site.yml` — install: on `k3s_cluster` runs `homelab_admin` (user `snuffy`), then `k3s_setup`,
  `prereq`, `download`, `raspberrypi`; then `k3s/master` on `k3sleaders` and `k3s/node` on
  `k3sfollowers`.
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

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml              # install
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml  # after Flux + gateway
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml           # teardown
./scripts/fetch-kubeconfig.sh                # kubeconfig → ~/.kube/k3s-rbps.yaml
./scripts/post-k3s-bootstrap.sh              # incl. the grafana-admin secret k3s-gitops waits on
```

`homelab_admin_user` (`snuffy`) must match `gateway.ssh.gateway.username` in `k3s-gitops`.

A reboot is expected after the cgroup `cmdline.txt` change on first provision.

## Known gotchas (do not re-trip on these)

- `ansible.cfg` defaults to `inventory/my-cluster/hosts.yml` on this Linux box. Its values carry
  trailing ` ;` (Ansible strips them, verified) and `become = True` sits in the wrong section
  (`[defaults]`, ignored) — playbooks set `become` explicitly so behavior is correct.
- `inventory/sample/group_vars/all.yml` pins ancient `k3s_version: v1.17.5+k3s1` (public-repo
  cosmetics only; `my-cluster` uses `k3s_use_latest_version: true`).
- `roles/k3s/master` and `roles/k3s/node` use `systemd: state: restarted` — **every `site.yml` run
  restarts the whole cluster**, changed or not. Known issue, fix pending (k3s-gitops `TODO.md`
  review notes, 2026-07-02).
- The join token is rendered into `k3s-node.service` (mode 0755) and `debug`-printed by both k3s
  roles. Treat playbook output as secret; never paste it into docs, rules, or commits.
- `reset.yml` targets `hosts: all`, which includes the NAS (`homelab_nas`) — scope-check before
  running it.
- `roles/k3s/node/tasks/main.yml` hardcodes `leader01.local` in `/etc/hosts` (unused by the join,
  which uses `master_ip`) — keep leader naming consistent anyway.
- `prereq` role contains upstream RHEL/SELinux tasks that are dead code on Pi OS (harmless).
- CI (`.github/workflows/validate.yml`) runs yamllint + syntax-check on everything but
  ansible-lint only on `homelab_admin`/`twingate_ssh_sshd` (legacy upstream roles skipped).

## Hardware / network

- Raspberry Pi (64-bit OS), microSD boot. Nodes reachable over SSH.
- Networking is fixed-DHCP via reservations on the router (eth0 MAC → IP); reflashing does not change
  the MAC. Capture each node's MAC/IP during discovery before relying on addresses.

## Backlog

The full 2026-07-02 review backlog (idempotency, token handling, GitHub API once-per-play, sample
inventory pin, dead code) lives in the local `k3s-gitops/TODO.md` under "Repo review findings"
(gitignored).
