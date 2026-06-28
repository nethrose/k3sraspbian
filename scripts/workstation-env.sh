# Homelab k3s-rbps workstation defaults (bash/zsh).
#
# One-time setup — add to ~/.bashrc or ~/.zshrc:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.sh
#
# Default: LAN admin kubeconfig (~/.kube/k3s-rbps.yaml, context "default").
# Twingate kube autosync still updates ~/.kube/config; use k3s-twingate to switch.

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s-rbps.yaml}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "workstation-env.sh: missing $KUBECONFIG — run scripts/fetch-kubeconfig.sh" >&2
fi

k3s-lan() {
  export KUBECONFIG="$HOME/.kube/k3s-rbps.yaml"
  echo "kubectl → LAN admin ($KUBECONFIG, context default)"
}

k3s-twingate() {
  unset KUBECONFIG
  kubectl config use-context twingate-k3s-rbps-api
  echo "kubectl → Twingate (context twingate-k3s-rbps-api, identity RBAC applies)"
}

k3s-lan
