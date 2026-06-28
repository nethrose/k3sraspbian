# k3sraspbian

Ansible playbooks to install k3s on **64-bit Raspberry Pi OS** (derivative of
[k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)).

## Topology

1 control-plane (`leader01`) + 3 worker agents (`follower01`..`follower03`). Workloads are managed
separately by the [`k3s-gitops`](https://github.com/nethrose/k3s-gitops) Flux repo.

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml              # k3s + homelab admin user
ansible-playbook -i inventory/my-cluster/hosts.yml homelab-nas.yml       # NAS snuffy + SSH CA (OMV admin)
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml # Pis + NAS gateway User CA
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml           # teardown
```

### Workstation `kubectl` (fish / bash)

Add to your shell config once (see `scripts/workstation-env.fish`):

```fish
source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.fish
```

Defaults to **Twingate kubectl** (`~/.kube/config`, context `twingate-k3s-rbps-api`). Keep
**`twingate kube config autosync`** on. LAN admin break-glass:

```fish
k3s-lan       # cluster-admin via ~/.kube/k3s-rbps.yaml
k3s-twingate  # back to Twingate identity context
```

See [Twingate kubeconfig sync](https://www.twingate.com/docs/kubernetes-kubeconfig-sync).

---

`ansible.cfg` points at `inventory/my-cluster/hosts.yml` by default. A reboot is expected after the
first run (cgroup flags in `/boot/cmdline.txt`).

## Homelab admin user (`snuffy`)

`site.yml` creates user **`snuffy`** on every k3s node (passwordless `sudo`, your `~/.ssh/id_rsa.pub`).
`homelab-nas.yml` does the same on the **CM3588 NAS** (`192.168.0.72`), bootstrapping over OMV
**`admin`**. Both match `gateway.ssh.gateway.username` in `k3s-gitops` for Twingate SSH (`leader01.ssh`,
`jellyfin.ssh`, …). Ansible still connects as the per-host bootstrap user from inventory (`leader01`, …,
`admin` on NAS).

Override `homelab_admin_ssh_pubkey_file` in `inventory/my-cluster/group_vars/all.yml` if needed.

## CM3588 NAS (`homelab-nas.yml`)

OpenMediaVault ships with **`admin`**, not `snuffy`. Run once (password sudo on OMV):

```bash
export KUBECONFIG=~/.kube/k3s-rbps.yaml
ansible-playbook -i inventory/my-cluster/hosts.yml homelab-nas.yml --ask-become-pass
```

Override `ansible_user` on host `cm3588` in `inventory/my-cluster/hosts.yml` if your OMV admin name
differs. Afterward: `ssh snuffy@192.168.0.72` on LAN, or `ssh snuffy@jellyfin.ssh` via Twingate.

## Twingate SSH gateway (`sshd` trust)

After Flux deploys the gateway with `gateway.ssh.enabled`, run:

```bash
export KUBECONFIG=~/.kube/k3s-rbps.yaml
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

This fetches the gateway **User CA** public key from the gateway pod logs and installs
`TrustedUserCAKeys` on each Pi and the NAS. You still need `TwingateResource` CRs for SSH endpoints in
`k3s-gitops` (`twingate/manifests/resources-ssh.yaml`).
