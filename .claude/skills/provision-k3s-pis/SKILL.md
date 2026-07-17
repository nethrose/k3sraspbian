---
name: provision-k3s-pis
description: Provision the Raspberry Pi k3s cluster with the k3sraspbian Ansible playbooks (1 leader + 3 agents on 64-bit Raspberry Pi OS). Use when running site.yml/reset.yml, editing inventory or roles, or rebuilding nodes after a microSD reflash.
---

# Provision k3s on Raspberry Pis (Ansible)

Operational guide for running the `k3sraspbian` Ansible project. For homelab-wide context and the
full rebuild runbook, see the global `homelab-k3s-pi` skill. For project facts and gotchas, see the
repo `CLAUDE.md`.

## Pre-flight (do this first)

1. `ansible.cfg` points at `inventory/my-cluster/hosts.yml` — still pass `-i` if you use another inventory.
2. Use a real inventory: `inventory/my-cluster/hosts.yml`, or copy `inventory/sample/` and edit
   hosts/users. Confirm `ansible_user` and host reachability (reserved IPs; SSH user = hostname).
3. Passwordless SSH (key-based) to every node must work: `ssh <user>@<host> true`
   (helper: `./scripts/verify-ssh.sh`).
4. Consider pinning a current `k3s_version` in `group_vars/all.yml` for reproducible rebuilds
   (otherwise `roles/k3s_setup` resolves the latest release at run time).

## Install

```bash
cd /home/snuffy/Documents/GitHub/k3sraspbian
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml
```

What happens: **`homelab_admin`** creates user `snuffy` (sudo, your SSH key), then `k3s_setup`
(resolve version), `prereq`, `download` (arm64 k3s binary), and **`raspberrypi`** (cgroup flags in
**`/boot/firmware/cmdline.txt`** + iptables backend — **nft by default**, legacy only if
`k3s_use_iptables_legacy` is set AND `ip_tables.ko` exists; **reboot** expected); then `k3s/master`
on the leader and `k3s/node` on the followers.

## Twingate SSH gateway (`sshd` User CA)

After Flux deploys the gateway (`gateway.ssh.enabled`, username `snuffy` in `k3s-gitops`):

```bash
export KUBECONFIG=~/.kube/k3s-rbps.yaml
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

Installs `TrustedUserCAKeys` on every Pi from the committed pubkey
**`twingate_gateway_user_ca_pubkey`** (the gateway's manual SSH User CA — `ssh_ca.pub` from
k3s-gitops `scripts/gen-gateway-cas.sh`); no gateway-pod-log scraping. Per-host SSH endpoints are
registered by the one-shot register Job in k3s-gitops (`sshResourceCreate`), **not** by
`TwingateResource` CRs. NAS (`jellyfin.ssh`) uses `homelab-nas.yml` instead (separate OMV bootstrap).

## Teardown

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml
```

Note: `reset.yml` currently targets `hosts: all` (includes the `homelab_nas` group) — scope-check the
inventory before running.

## Get the kubeconfig

```bash
./scripts/fetch-kubeconfig.sh                 # → ~/.kube/k3s-rbps.yaml (rewrites 127.0.0.1 → leader IP)
export KUBECONFIG=~/.kube/k3s-rbps.yaml
```

On the leader the admin config is `/etc/rancher/k3s/k3s.yaml`; the script copies it and rewrites
`server: https://127.0.0.1:6443` to the leader's IP so `kubectl`/`flux` work from this box.

## After provisioning

Hand off to GitOps: bootstrap Flux from `k3s-gitops` (see the homelab rebuild runbook), then verify
`kubectl get nodes -o wide` shows 1 control-plane + 3 workers `Ready`.

## Safety

- Running `site.yml`/`reset.yml` changes/destroys node state — confirm the inventory targets the
  intended Pis before running.
- Both k3s roles print the join token via `debug` (and render it into `k3s-node.service`); treat
  playbook output as a secret and never paste it into docs, rules, or commits.
