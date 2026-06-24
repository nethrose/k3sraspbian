#!/usr/bin/env bash
# Post-flash helper: verify SSH, optionally run Ansible, fetch kubeconfig.
# Does not run flux bootstrap (one-time, needs GitHub auth).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$REPO_ROOT/inventory/my-cluster/hosts.yml}"
LEADER_IP="${LEADER_IP:-192.168.0.12}"
LEADER_USER="${LEADER_USER:-leader01}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$HOME/.kube/k3s-rbps.yaml}"
RUN_ANSIBLE=false
SECRETS_ONLY=false

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options:"
  echo "  --ansible          Run ansible-playbook site.yml before kubeconfig"
  echo "  --secrets-only     Only create Twingate operator secret (cluster must exist)"
  echo "  -h, --help         Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ansible) RUN_ANSIBLE=true; shift ;;
    --secrets-only) SECRETS_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  ;;
  esac
done

create_twingate_secret() {
  if [[ -z "${TWINGATE_API_KEY:-}" ]]; then
    echo "Set TWINGATE_API_KEY to create the operator secret." >&2
    return 1
  fi
  kubectl create namespace twingate --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n twingate create secret generic twingate-operator-credentials \
    --from-literal=TWINGATE_API_KEY="$TWINGATE_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "Twingate secret applied. Reconcile: flux reconcile helmrelease twingate-operator -n twingate"
}

if $SECRETS_ONLY; then
  create_twingate_secret
  exit 0
fi

echo "==> Verifying SSH to all inventory hosts"
ansible -i "$INVENTORY" all -m ping

if $RUN_ANSIBLE; then
  echo "==> Running site.yml"
  ansible-playbook -i "$INVENTORY" "$REPO_ROOT/site.yml"
fi

echo "==> Fetching kubeconfig to $KUBECONFIG_OUT"
mkdir -p "$(dirname "$KUBECONFIG_OUT")"
ssh -F /dev/null "${LEADER_USER}@${LEADER_IP}" sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed "s|https://127.0.0.1:6443|https://${LEADER_IP}:6443|" > "$KUBECONFIG_OUT"
chmod 600 "$KUBECONFIG_OUT"
echo "export KUBECONFIG=$KUBECONFIG_OUT"

if [[ -n "${TWINGATE_API_KEY:-}" ]]; then
  export KUBECONFIG="$KUBECONFIG_OUT"
  create_twingate_secret || true
fi

cat <<EOF

Next steps (if this is a new cluster):
  export KUBECONFIG=$KUBECONFIG_OUT
  flux bootstrap github --owner=nethrose --repository=k3s-gitops \\
    --branch=main --path=clusters/k3s-rbps --personal

After Flux reconciles:
  kubectl -n monitoring create secret generic jellyfin-exporter-credentials \\
    --from-literal=JELLYFIN_TOKEN='<jellyfin-api-key>'

See k3s-gitops/docs/bootstrap.md for the full procedure.
EOF
