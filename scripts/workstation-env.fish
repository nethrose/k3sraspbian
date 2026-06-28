# Homelab k3s-rbps workstation defaults (fish).
#
# One-time setup — add to ~/.config/fish/config.fish:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.fish
#
# Default: LAN admin kubeconfig (~/.kube/k3s-rbps.yaml, context "default").
# Twingate kube autosync still updates ~/.kube/config; use k3s-twingate to switch.

set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml

if not test -f $KUBECONFIG
    echo "workstation-env.fish: missing $KUBECONFIG — run scripts/fetch-kubeconfig.sh" >&2
end

# LAN cluster-admin (secrets, Flux, debugging). Default for homelab ops.
function k3s-lan
    set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml
    echo "kubectl → LAN admin ($KUBECONFIG, context default)"
end

# Remote kubectl via Twingate gateway (k3s.int). Requires twingate kube config autosync.
function k3s-twingate
    set -e KUBECONFIG
    kubectl config use-context twingate-k3s-rbps-api
    echo "kubectl → Twingate (context twingate-k3s-rbps-api, identity RBAC applies)"
end

# Run once per new shell if you sourced this file earlier without functions:
k3s-lan
