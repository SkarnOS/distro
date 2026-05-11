#!/usr/bin/env nix
#! nix shell nixpkgs#openssl -c bash --

set -euEo pipefail

if [[ -n "${NIX_DEBUG:-}" ]] ; then
    set -x
fi

function _ssh () {
    _sudo="$1" ; shift 1
    _hostname="$1" ; shift 1

    _command=( ssh )
    if [[ -n "${NIX_SSHOPTS:-}" ]] ; then
        # shellcheck disable=SC2206
        _command+=( $NIX_SSHOPTS )
    else
        _command+=( -o ControlMaster=auto -o ControlPath="$_tmpdir/control_master_%C" )
    fi
    _command+=( "$_hostname" )
    if [[ "$_sudo" = "true" ]] ; then
        _command+=( sudo sh -c )
        _subcommand=""
        for _arg in "$@" ; do
            _subcommand="$_subcommand $_arg"
        done
        _command+=( "\"$_subcommand\"" )
    fi

    printf ">> %s\n" "${_command[@]}" >&2

    "${_command[@]}"
}

function _get_token() {
    _sudo="$1"

    _ssh "$_sudo" "$_control_plane_address" kubeadm token create --ttl 1h
}

function _command_join() {
    function _command_join_help() {
        cat <<EOF
skarnos join [--address] [--sudo] CONTROL_PLANE WORKER
  - CONTROL_PLANE - SSH target for a control plane node
  - WORKER - SSH target for the worker node you want to join
EOF
        exit 1
    }

    declare _address _control_plane _worker _interface
    while [[ "$#" -gt 0 ]] ; do
        case "$1" in
            "--interface")
                _interface="$2"
                shift 2
                ;;
            "--address")
                _address=true
                shift 1
                ;;
            "--sudo")
                _sudo=true
                shift 1
                ;;
            *)
                if [[ -z "${_control_plane:-}" ]] ; then
                    _control_plane="$1"
                elif [[ -z "${_worker:-}" ]] ; then
                    _worker="$1"
                else
                    printf 'Unknown argument "%s"\n' "$1"
                    _command_join_help
                fi
                shift 1
                ;;
        esac
    done

    : "${_sudo:=false}"

    if [[ -z "${_control_plane:-}" ]] || [[ -z "${_worker:-}" ]] ; then
        _command_join_help
    fi

    declare _control_plane_address _worker_address

    if [[ -z "${_interface:-}" ]] ; then
        _interface="$(nix eval --raw ".#nixosConfigurations.${_control_plane}.config.skarnos.kubernetes.network.internal.interface")"
    fi

    if [[ "${_address:-}" = "true" ]] ; then
        _control_plane_address="${_control_plane}"
        _worker_address="${_worker}"
    else
        _control_plane_address="$(nix eval --raw ".#nixosConfigurations.${_control_plane}.config.skarnos.kubernetes.sshTarget")"
        _worker_address="$(nix eval --raw ".#nixosConfigurations.${_worker}.config.skarnos.kubernetes.sshTarget")"
    fi

    declare _tmpdir
    _tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -r $_tmpdir" EXIT

    if _ssh "$_sudo" "$_control_plane_address" kubectl get node "$_worker" >/dev/null; then
        printf 'Worker %s is already part of the cluster, doing nothing...\n' "$_worker"
        exit 0
    fi

    declare _token _cert_digest _control_plane_internal_address
    _token="$(_get_token "$_sudo" "$_control_plane_address")"
    _cert_digest="$(openssl x509 -pubkey -in <(_ssh "$_sudo" "$_control_plane_address" cat /etc/kubernetes/pki/ca.crt) \
                         | openssl rsa -pubin -outform der 2>/dev/null \
                         | openssl dgst -sha256 -hex \
                         | cut -f2 -d" ")"
    _control_plane_internal_address="$(_ssh "$_sudo" "$_control_plane_address" fish-out-netif-ip "$_interface")"

    _ssh "$_sudo" "$_worker_address" "mkdir -p /var/lib/kubeadm-join ; umask 0077 ; touch /var/lib/kubeadm-join/secret.env"
    _ssh "$_sudo" "$_worker_address" "cat > /var/lib/kubeadm-join/secret.env" <<EOF
CONTROL_PLANE_ADDRESS="$_control_plane_internal_address"
JOIN_TOKEN="$_token"
DISCOVERY_TOKEN_CA_CERT_HASH="sha256:$_cert_digest"
EOF
    _ssh "$_sudo" "$_worker_address" "systemctl start kubeadm-join.service"
    _ssh "$_sudo" "$_worker_address" "systemctl restart kubernetes-full.target"
}

function _command_install() {
    local _node="${1:-}"

    if [[ -z "${_node}" ]] ; then
        cat <<-EOF
skarnos install NODE
  - NODE - SSH target for a control plane node
EOF
        exit 1
    fi

    declare _address
    _address="$(nix eval --raw ".#nixosConfigurations.${_node}.config.skarnos.kubernetes.sshTarget")"
    nix run github:nix-community/nixos-anywhere -- --target-host "$_address" --flake ".#$_node"
}

function _command_deploy() {
    local _action="${1:-}"
    shift 1
    local _nodes=( "$@" )


    if [[ "${#_nodes[@]}" == 0 ]] || [[ -z "${_action}" ]]; then
        cat <<-EOF
skarnos install ACTION [NODE]
  - ACTION - one of 'switch', 'test', 'boot', or 'dry-activate'
  - NODE - SSH target for a control plane node
EOF
        exit 1
    fi

    for _node in "${_nodes[@]}" ; do
        declare _address
        _address="$(nix eval --raw ".#nixosConfigurations.${_node}.config.skarnos.kubernetes.sshTarget")"
        nixos-rebuild "$_action" --target-host "$_address" --flake ".#$_node"
    done
}

function _command_ssh() {
    local _node="${1:-}"

    if [[ -z "${_node}" ]] ; then
        cat <<-EOF
skarnos install NODE
  - NODE - SSH target for a control plane node
EOF
        exit 1
    fi

    declare _address
    _address="$(nix eval --raw ".#nixosConfigurations.${_node}.config.skarnos.kubernetes.sshTarget")"
    ssh "$_address"
}

if [[ "$#" -lt 1 ]] ; then
    cat <<-EOF
skarnos COMMAND
  - join
  - install
  - deploy
  - ssh
EOF
    exit 1
fi

case "$1" in
    join)
        shift 1
        _command_join "$@"
        ;;
    install)
        shift 1
        _command_install "$@"
        ;;
    deploy)
        shift 1
        _command_deploy "$@"
        ;;
    ssh)
        shift 1
        _command_ssh "$@"
        ;;
esac
