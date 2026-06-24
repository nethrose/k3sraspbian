#!/usr/bin/env bash
set -euo pipefail

HOSTS=(
  leader01@192.168.0.12
  follower01@192.168.0.11
  follower02@192.168.0.10
  follower03@192.168.0.9
)

for host in "${HOSTS[@]}"; do
  echo "==> $host"
  ssh -F /dev/null -o ConnectTimeout=5 "$host" true
done
echo "All hosts reachable."
