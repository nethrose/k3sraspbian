# Homelab k3s-rbps workstation defaults (fish).
#
# One-time setup — add to ~/.config/fish/config.fish:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.fish
#
# Aligns with Twingate Privileged Access for Kubernetes:
#   https://www.twingate.com/docs/kubernetes-access
#   https://www.twingate.com/docs/kubernetes-kubeconfig-sync
#
# twingate kube config autosync writes contexts to ~/.kube/config.
# This script sets that as the default kubeconfig and selects the homelab context.

mkdir -p $HOME/.kube
set -gx KUBECONFIG $HOME/.kube/config

set -l _k3s_ctx twingate-k3s-rbps-api
if kubectl config get-contexts -o name 2>/dev/null | grep -qx $_k3s_ctx
    kubectl config use-context $_k3s_ctx >/dev/null
    echo "kubectl → Twingate ($_k3s_ctx via k3s.int; enable: twingate kube config autosync)"
else
    echo "workstation-env.fish: no $_k3s_ctx — run: twingate kube config sync" >&2
end

# LAN cluster-admin (secrets, Flux, break-glass). Separate cert from fetch-kubeconfig.sh.
function k3s-lan
    set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml
    kubectl config use-context default >/dev/null 2>&1
    echo "kubectl → LAN admin ($KUBECONFIG, context default)"
end

# Back to Twingate identity kubectl (default after sourcing this file).
function k3s-twingate
    set -gx KUBECONFIG $HOME/.kube/config
    kubectl config use-context twingate-k3s-rbps-api
    echo "kubectl → Twingate (context twingate-k3s-rbps-api)"
end
