_interface="$1"

_interface_ip="$(ip --json  addr | jq '[.[] | select(.ifname == "'"$_interface"'") | .addr_info[] | select(.family == "inet")] | first | .local' --raw-output)"

if [[ "$_interface_ip" == "null" ]] ; then
  echo "could not figure out primary IP address of $_interface, exiting..." 1>&2
  exit 1
fi

printf '%s\n' "$_interface_ip"
