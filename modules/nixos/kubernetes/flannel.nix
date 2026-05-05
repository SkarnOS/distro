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

  flannelSettingsFormat = pkgs.formats.json { };
in
{
  options.skarnos.kubernetes.network.cni = lib.mkOption {
    type = lib.types.attrTag {
      "flannel" = lib.mkOption {
        type = lib.types.submodule {
          options = {
            package = lib.mkOption {
              type = lib.types.str;
              default = "${pkgs.flannel.src}/Documentation/kube-flannel.yml";
            };

            settings = {
              cni = lib.mkOption {
                type = flannelSettingsFormat.type;
                default = { };
              };

              network = lib.mkOption {
                type = flannelSettingsFormat.type;
                default = { };
              };

              arguments = lib.mkOption {
                type = lib.types.listOf lib.types.str;
              };
            };
          };

          config = {
            settings.cni = {
              name = lib.mkDefault "cbr0";
              cniVersion = lib.mkDefault "0.3.1";
              plugins = lib.mkDefault [
                {
                  type = "flannel";
                  delegate = {
                    hairpinMode = true;
                    isDefaultGateway = true;
                  };
                }
                {
                  type = "portmap";
                  capabilities = {
                    portMappings = true;
                  };
                }
              ];
            };

            settings.network = {
              Network = lib.mkDefault cfgK8s.network.podSubnet;
              EnableNFTables = lib.mkDefault config.networking.nftables.enable;
              Backend = lib.mkDefault {
                Type = "vxlan";
              };
            };

            settings.arguments = [
              "--ip-masq"
              "--kube-subnet-mgr"
            ];
          };
        };
      };
    };
  };
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
        pkgs.yq-go
        cfgK8s.package
      ];

      script = ''
        { yq ' with(select(.kind == "ConfigMap" and .metadata.name == "kube-flannel-cfg");
                 .data."cni-conf.json" = load_str("${flannelSettingsFormat.generate "cni-conf.json" cfg.settings.cni}")
               | .data."net-conf.json" = load_str("${flannelSettingsFormat.generate "net-conf.json" cfg.settings.network}"))
             | with(select(.kind == "DaemonSet" and .metadata.name == "kube-flannel-ds");
                 .spec.template.spec.containers = [
                   .spec.template.spec.containers[] | with(select(.name == "kube-flannel");
                     .args = ${builtins.toJSON cfg.settings.arguments})
                 ])
             ' \
        | kubectl apply -f - \
        ; } < ${cfg.package}
      '';
    };
  };
}
