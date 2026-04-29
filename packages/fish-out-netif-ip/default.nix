{
  writeShellApplication,
  iproute2,
  jq,
}:
writeShellApplication {
  name = "fish-out-netif-ip";
  text = builtins.readFile ./main.sh;
  runtimeInputs = [
    jq
    iproute2
  ];
}
