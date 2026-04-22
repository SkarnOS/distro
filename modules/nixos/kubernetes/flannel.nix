{ lib, config, ... }:
let
  cfgK8s = config.skarnos.kubernetes;
  cfg =
    if cfgK8s.network.cni ? "flannel" then
      { enable = true; } // cfgK8s.network.cni.flannel
    else
      { enable = false; };
in
{
  config = lib.mkIf (cfgK8s.enable && cfg.enable) {
    boot.kernelModules = [
      # Absolutely required by kube-proxy and flannel
      "ipt_REJECT"
      "nf_conntrack"
      "nft_reject_inet"
      "veth"
      "xt_MASQUERADE"
      "xt_addrtype"
      "xt_mark"
      "xt_nat"
      "xt_recent"
      "xt_statistic"
      "xt_tcpudp"
    ];
  };
}
