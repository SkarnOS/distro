#!/usr/bin/env nix
#! nix shell nixpkgs#openssl -c bash --

set -euEo pipefail

_control_plane="$1"

_tmpdir="$(mktemp -d)"
trap "rm -r $_tmpdir" EXIT

function _ssh () {
  ssh -o ControlMaster=auto -o ControlPath="$_tmpdir/control_master" "$@"
}

function _get_token() {
  _ssh "$_control_plane" kubeadm token create --ttl 1h
}

_token="$(_get_token "$1")"
_cert_digest="$(openssl x509 -pubkey -in <(_ssh "$_control_plane" cat /etc/kubernetes/pki/ca.crt) \
                 | openssl rsa -pubin -outform der 2>/dev/null \
                 | openssl dgst -sha256 -hex \
                 | cut -f2 -d" ")"

echo "$_token"
echo "$_cert_digest"
