---
name: provision-k3s-pis
description: Provision the Raspberry Pi k3s cluster with the k3sraspbian Ansible playbooks (1 leader + 3 agents on 64-bit Raspberry Pi OS). Use when running site.yml/reset.yml, editing inventory or roles, or rebuilding nodes after a microSD reflash.
---

# Provision k3s on Raspberry Pis (Ansible)

Operational guide for running the `k3sraspbian` Ansible project. For homelab-wide context and the
full rebuild runbook, see the global `homelab-k3s-pi` skill. For project facts and gotchas, see
`.cursor/rules/k3sraspbian.mdc`.

## Pre-flight (do this first)

1. `ansible.cfg` points at `inventory/my-cluster/hosts.yml` — still pass `-i` if you use another inventory.
2. Use a real inventory: `inventory/my-cluster/hosts.yml`, or copy `inventory/sample/` and edit
   hosts/users. Confirm `ansible_user` and host reachability (mDNS `.local` or reserved IPs).
3. Passwordless SSH (key-based) to every node must work: `ssh <user>@<host> true`.
4. Consider pinning a current `k3s_version` in `group_vars/all.yml` for reproducible rebuilds
   (otherwise `roles/k3s_setup` resolves the latest release at run time).

## Install

```bash
cd /home/snuffy/Documents/GitHub/k3sraspbian
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml
```

What happens: **`homelab_admin`** creates user `snuffy` (sudo, your SSH key), then prereq sysctl,
k3s binary download (arm64), Pi prep (cgroup flags in `/boot/cmdline.txt` + iptables-legacy,
**reboot**), then `k3s/master` on the leader and `k3s/node` on the followers.

## Twingate SSH gateway (`sshd` User CA)

After Flux deploys the gateway (`gateway.ssh.enabled`, username `snuffy` in `k3s-gitops`):

```bash
export KUBECONFIG=~/.kube/k3s-rbps.yaml
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

Fetches the gateway User CA from pod logs and configures `TrustedUserCAKeys` on every Pi. Still
requires `TwingateResource` SSH endpoints in GitOps / Admin Console.

## Teardown

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml
```

## Get the kubeconfig

On the leader the admin config is `/etc/rancher/k3s/k3s.yaml`. Copy it locally and replace the
`server: https://127.0.0.1:6443` with the leader's IP/hostname to use `kubectl`/`flux` from this box.

## After provisioning

Hand off to GitOps: bootstrap Flux from `k3s-gitops` (see the homelab rebuild runbook), then verify
`kubectl get nodes -o wide` shows 1 control-plane + 3 workers `Ready`.

## Safety

- Running `site.yml`/`reset.yml` changes/destroys node state - confirm the inventory targets the
  intended Pis before running.
- The master role prints the join token via `debug`; treat that output as a secret.
