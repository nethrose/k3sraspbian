#!/usr/bin/env bash
set -euo pipefail

LEADER_IP="${LEADER_IP:-192.168.0.12}"
LEADER_USER="${LEADER_USER:-leader01}"
OUT="${1:-$HOME/.kube/k3s-rbps.yaml}"

mkdir -p "$(dirname "$OUT")"
ssh -F /dev/null "${LEADER_USER}@${LEADER_IP}" sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed "s|https://127.0.0.1:6443|https://${LEADER_IP}:6443|" > "$OUT"
chmod 600 "$OUT"
echo "Wrote $OUT"
echo "export KUBECONFIG=$OUT"
