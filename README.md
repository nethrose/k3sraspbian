# k3sraspbian

Ansible playbooks to install k3s on **64-bit Raspberry Pi OS** (derivative of
[k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)).

## Topology

1 control-plane (`leader01`) + 3 worker agents (`follower01`..`follower03`). Workloads are managed
separately by the [`k3s-gitops`](https://github.com/nethrose/k3s-gitops) Flux repo.

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml              # k3s + homelab admin user
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml # after Flux + gateway (SSH CA)
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml           # teardown
```

`ansible.cfg` points at `inventory/my-cluster/hosts.yml` by default. A reboot is expected after the
first run (cgroup flags in `/boot/cmdline.txt`).

## Homelab admin user (`snuffy`)

`site.yml` creates user **`snuffy`** on every node (passwordless `sudo`, your `~/.ssh/id_rsa.pub`).
This matches `gateway.ssh.gateway.username` in `k3s-gitops` for Twingate SSH. Ansible still
connects as the per-host user from the SD card image (`leader01`, `follower01`, …).

Override `homelab_admin_ssh_pubkey_file` in `inventory/my-cluster/group_vars/all.yml` if needed.

## Twingate SSH gateway (`sshd` trust)

After Flux deploys the gateway with `gateway.ssh.enabled`, run:

```bash
export KUBECONFIG=~/.kube/k3s-rbps.yaml
ansible-playbook -i inventory/my-cluster/hosts.yml twingate-ssh-sshd.yml
```

This fetches the gateway **User CA** public key from the gateway pod logs and installs
`TrustedUserCAKeys` on each Pi. You still need `TwingateResource` CRs for each Pi SSH endpoint in
`k3s-gitops` (see `twingate/resources.example.yaml`).
