#!/usr/bin/env nix
#! nix shell nixpkgs#openssl -c bash --

set -euEo pipefail

_control_plane="$1"
_worker="$2"

if [[ -z "${_control_plane}" ]] || [[ -z "${_worker}" ]] ; then
    cat <<EOF
something.sh CONTROL_PLANE WORKER
  - CONTROL_PLANE - SSH target for a control plane node
  - WORKER - SSH target for the worker node you want to join
EOF
fi

_control_plane_address="$(nix eval --raw ".#nixosConfigurations.${_control_plane}.config.skarnos.kubernetes.sshTarget")"
_interface="$(nix eval --raw ".#nixosConfigurations.${_control_plane}.config.skarnos.kubernetes.network.internal.interface")"
_worker_address="$(nix eval --raw ".#nixosConfigurations.${_worker}.config.skarnos.kubernetes.sshTarget")"

_tmpdir="$(mktemp -d)"
trap "rm -r $_tmpdir" EXIT

function _ssh () {
    ssh -o ControlMaster=auto -o ControlPath="$_tmpdir/control_master_%C" "$@"
}

function _get_token() {
  _ssh "$_control_plane_address" kubeadm token create --ttl 1h
}

if _ssh "$_control_plane_address" kubectl get node "$_worker" >/dev/null 2>&1; then
    printf "Worker $_worker is already part of the cluster, doing nothing...\n"
    exit 0
fi

_token="$(_get_token "$1")"
_cert_digest="$(openssl x509 -pubkey -in <(_ssh "$_control_plane_address" cat /etc/kubernetes/pki/ca.crt) \
                 | openssl rsa -pubin -outform der 2>/dev/null \
                 | openssl dgst -sha256 -hex \
                 | cut -f2 -d" ")"
_control_plane_internal_address="$(_ssh "$_control_plane_address" fish-out-netif-ip "$_interface")"

_ssh "$_worker_address" "mkdir -p /var/lib/kubeadm-join ; umask 0077 ; touch /var/lib/kubeadm-join/secret.env"
_ssh "$_worker_address" "cat > /var/lib/kubeadm-join/secret.env" <<EOF
CONTROL_PLANE_ADDRESS="$_control_plane_internal_address"
JOIN_TOKEN="$_token"
DISCOVERY_TOKEN_CA_CERT_HASH="sha256:$_cert_digest"
EOF
_ssh "$_worker_address" "systemctl restart kubernetes-full.target"
