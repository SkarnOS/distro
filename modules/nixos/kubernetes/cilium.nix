{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfgK8s = config.rename-me.kubernetes;
  cfg =
    if cfgK8s.network.cni ? "cilium" then
      { enable = true; } // cfgK8s.network.cni.cilium
    else
      { enable = false; };
in
{
  config = lib.mkIf (cfgK8s.enable && cfg.enable) {
    rename-me.kubernetes.network.internal.extraNetworkdConfig =
      lib.mkIf (cfgK8s.network.internal.interface == null)
        {
          address = [
            "192.168.8.1/24"
            "fd08:4e1:0::1/64"
          ];
        };

    systemd = {
      # Dummy interface for single-node clusters
      network.netdevs =
        lib.mkIf ((!cfgK8s.network.dontConfigureNetworkd) && cfgK8s.network.internal.interface == null)
          {
            "10-single-node-dummy" = {
              netdevConfig = {
                Name = "dummy0";
                Kind = "dummy";
              };
            };
          };

      # The default preStart will remove the Cilium CNI :/
      services.kubelet.preStart = lib.mkForce ''
        ${lib.concatMapStrings (img: ''
          echo "Seeding container image: ${img}"
          ${
            if (lib.hasSuffix "gz" img) then
              ''${pkgs.gzip}/bin/zcat "${img}" | ${pkgs.containerd}/bin/ctr -n k8s.io image import -''
            else
              ''${pkgs.coreutils}/bin/cat "${img}" | ${pkgs.containerd}/bin/ctr -n k8s.io image import -''
          }
        '') config.services.kubernetes.kubelet.seedDockerImages}
      '';
    };

    boot = {
      kernelModules = [
        "cls_bpf"
        "ip6table_filter"
        "ip6table_mangle"
        "ip6table_raw"
        "ip6tables"
        "ip_set"
        "ip_tables"
        "nf_log_syslog"
        "sch_fq"
        "sch_ingress"
        "veth"
        "vxlan"
        "xfrm_user"
        "xt_CT"
        "xt_TPROXY"
        "xt_mark"
        "xt_socket"
      ];
    };

    environment.systemPackages = [
      pkgs.bpftools
    ];

    services.kubernetes.kubelet.nodeIp = lib.mkIf (
      cfgK8s.network.internal.interface == null
    ) "192.168.8.1,fd08:4e1::1";
  };
}
