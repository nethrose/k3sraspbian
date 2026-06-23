# k3sraspbian

Ansible playbooks to install k3s on **64-bit Raspberry Pi OS** (derivative of
[k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)).

## Topology

1 control-plane (`leader01`) + 3 worker agents (`follower01`..`follower03`). Workloads are managed
separately by the [`k3s-gitops`](https://github.com/nethrose/k3s-gitops) Flux repo.

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml   # install
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml  # teardown
```

`ansible.cfg` points at `inventory/my-cluster/hosts.yml` by default. A reboot is expected after the
first run (cgroup flags in `/boot/cmdline.txt`).
