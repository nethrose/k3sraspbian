# Homelab k3s-rbps workstation defaults (bash/zsh).
#
# One-time setup — add to ~/.bashrc or ~/.zshrc:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.sh
#
# Aligns with Twingate Privileged Access for Kubernetes:
#   https://www.twingate.com/docs/kubernetes-access
#   https://www.twingate.com/docs/kubernetes-kubeconfig-sync

mkdir -p "$HOME/.kube"
export KUBECONFIG="$HOME/.kube/config"

_k3s_ctx="twingate-k3s-rbps-api"
if kubectl config get-contexts -o name 2>/dev/null | grep -qx "$_k3s_ctx"; then
  kubectl config use-context "$_k3s_ctx" >/dev/null
  echo "kubectl → Twingate ($_k3s_ctx via k3s.int; enable: twingate kube config autosync)"
else
  echo "workstation-env.sh: no $_k3s_ctx — run: twingate kube config sync" >&2
fi

k3s-lan() {
  export KUBECONFIG="$HOME/.kube/k3s-rbps.yaml"
  kubectl config use-context default >/dev/null 2>&1
  echo "kubectl → LAN admin ($KUBECONFIG, context default)"
}

k3s-twingate() {
  export KUBECONFIG="$HOME/.kube/config"
  kubectl config use-context twingate-k3s-rbps-api
  echo "kubectl → Twingate (context twingate-k3s-rbps-api)"
}
