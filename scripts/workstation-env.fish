# Homelab k3s-rbps workstation defaults (fish).
# One-time: add to ~/.config/fish/config.fish:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.fish
#
# Sets LAN admin kubeconfig (full cluster access). For Twingate remote kubectl, instead:
#   set -e KUBECONFIG
#   kubectl config use-context twingate-k3s-rbps-api

if not set -q KUBECONFIG
    set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml
end

if not test -f $KUBECONFIG
    echo "workstation-env.fish: missing $KUBECONFIG — run scripts/fetch-kubeconfig.sh" >&2
end
