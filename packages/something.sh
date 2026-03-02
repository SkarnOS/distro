#!/usr/bin/env nix
#! nix shell nixpkgs#openssl -c bash --

set -xeuEo pipefail

_control_plane="$1"
_worker="$2"

_tmpdir="$(mktemp -d)"
trap "rm -r $_tmpdir" EXIT

function _ssh () {
    ssh -o ControlMaster=auto -o ControlPath="$_tmpdir/control_master_%C
" "$@"
}

function _get_token() {
  _ssh "$_control_plane" kubeadm token create --ttl 1h
}

_token="$(_get_token "$1")"
_cert_digest="$(openssl x509 -pubkey -in <(_ssh "$_control_plane" cat /etc/kubernetes/pki/ca.crt) \
                 | openssl rsa -pubin -outform der 2>/dev/null \
                 | openssl dgst -sha256 -hex \
                 | cut -f2 -d" ")"
_control_plane_address="$(_ssh "$_control_plane" fish-out-netif-ip kube-int)"

_ssh "$_worker" "mkdir -p /var/lib/kubeadm-join ; umask 0077 ; touch /var/lib/kubeadm-join/secret.env"
_ssh "$_worker" "cat > /var/lib/kubeadm-join/secret.env" <<EOF
CONTROL_PLANE_ADDRESS="$_control_plane_address"
JOIN_TOKEN="$_token"
DISCOVERY_TOKEN_CA_CERT_HASH="sha256:$_cert_digest"
EOF
_ssh "$_worker" "systemctl restart kubernetes-full.target"
