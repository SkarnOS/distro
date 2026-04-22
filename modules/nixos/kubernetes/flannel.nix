{
  lib,
  pkgs,
  config,
  ...
}:
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

    systemd.services."kube-flannel-install" = lib.mkIf cfgK8s.role.controlPlane.enable {
      requiredBy = [ "kubernetes-full.target" ];
      requires = [ "kubeadm-init.service" ];
      after = [ "kubeadm-init.service" ];

      environment."KUBECONFIG" = "/etc/kubernetes/admin.conf";

      path = [
        pkgs.curl
        config.services.kubernetes.package
      ];

      script = ''
        curl -L https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \
          | sed 's~10.244.0.0/16~${cfgK8s.network.podSubnet}~' \
          | kubectl apply -f -
      '';
    };
  };
}
