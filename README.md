# k3sraspbian

Ansible playbooks to install k3s on **64-bit Raspberry Pi OS** (derivative of
[k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)).

## Topology

1 control-plane (`leader01`) + worker agents (`follower01`..). Workloads are managed separately by
the [`k3s-gitops`](https://github.com/nethrose/k3s-gitops) Flux repo.

## Usage

```bash
ansible-playbook -i inventory/my-cluster/hosts.yml site.yml   # install
ansible-playbook -i inventory/my-cluster/hosts.yml reset.yml  # teardown
```

`ansible.cfg` points at `inventory/my-cluster/hosts.yml` by default. A reboot is expected after the
first run (cgroup flags in `/boot/cmdline.txt`).

## Rebuild notes (2026)

- Inventory uses reserved DHCP IPs (`192.168.0.12` leader, `.11` follower). `follower02`/`.03` are
  commented out until additional microSD cards are available.
- `k3s_version` is pinned in `inventory/my-cluster/group_vars/all.yml`.
- After `site.yml`, bootstrap Flux from `k3s-gitops` and apply cluster secrets (Twingate API key)
  out-of-band on the cluster — see that repo's `twingate/secret.example.yaml`.
