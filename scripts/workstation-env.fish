# Homelab k3s-rbps workstation defaults (fish).
# One-time: add to ~/.config/fish/config.fish:
#   source ~/Documents/GitHub/k3sraspbian/scripts/workstation-env.fish
#
# Or set globally without sourcing this file:
#   set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml

if not set -q KUBECONFIG
    set -gx KUBECONFIG $HOME/.kube/k3s-rbps.yaml
end

if not test -f $KUBECONFIG
    echo "workstation-env.fish: missing $KUBECONFIG — run scripts/fetch-kubeconfig.sh" >&2
end
