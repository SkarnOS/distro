#!/usr/bin/env nix
#! nix shell nixpkgs#jq -c bash --

set -eEuo pipefail

_flake=""
_reboot="0"

while [ "$#" -gt 0 ] ; do
    case "$1" in
        "--reboot")
            _reboot="1"
            shift 1
            ;;
        "--flake"|"-f")
            _flake="$1"
            shift 2
            ;;
        *)
            if [ -z "${_host:-}" ] ; then
                _host="$1"
                shift 1
            elif [ -z "${_action:-}" ] ; then
                _action="$1"
                shift 1
            else
                echo "unknown arg: $1"
                exit 1
            fi
            ;;
    esac
done

if [ -n "${_flake:-}" ] ; then
    echo "_flake unset, exitting..."
    exit 1
fi

_flake_metadata="$(nix flake metadata --json "$_flake")"
_flake_path="$(jq --raw-output '.path' <<<"$_flake_metadata")"
_flake_hash="$(jq --raw-output '.locked.narHash' <<<"$_flake_metadata")"

_ip_address="$(nix eval --raw --expr '
  let
    flake = builtins.getFlake "path://'"$_flake_path"'?narHash='"$_flake_hash"'";
  in
    (builtins.fromTOML '"''"'
'"$(cat "$_host")"'
'"''"').deployment.address
')"

_store_path="$(nix build --print-out-paths --expr '
  let
    flake = builtins.getFlake "path://'"$_flake_path"'?narHash='"$_flake_hash"'";
  in
    (flake.lib.fromTOML '"''"'
'"$(cat "$_host")"'
'"''"').config.system.build.toplevel
')"

if [[ "$_action" == "install" ]] ; then
    _disko_script="$(nix build --print-out-paths --expr '
      let
        flake = builtins.getFlake "path://'"$_flake_path"'?narHash='"$_flake_hash"'";
      in
        (flake.lib.fromTOML '"''"'
    '"$(cat "$_host")"'
    '"''"').config.system.build.diskoScript
    ')"

    nix run "github:nix-community/nixos-anywhere" -- --target-host "root@$_ip_address" --store-paths "$_disko_script" "$_store_path"
else
    nixos-rebuild "$_action" --target-host "root@$_ip_address" --store-path "$_store_path" --show-trace --no-reexec

    if [ "$_reboot" = "1" ] ; then
        ssh "root@$_ip_address" reboot
    fi
fi
