# Homelab k3s-rbps workstation defaults (bash/zsh).
# One-time: add to ~/.bashrc or ~/.zshrc:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.sh
#
# Or export directly:
#   export KUBECONFIG="$HOME/.kube/k3s-rbps.yaml"

: "${KUBECONFIG:=$HOME/.kube/k3s-rbps.yaml}"
export KUBECONFIG

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "workstation-env.sh: missing $KUBECONFIG — run scripts/fetch-kubeconfig.sh" >&2
fi
