{ inputs }:
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
  options.rename-me.kubernetes.network.cni = lib.mkOption {
    type = lib.types.attrTag {
      "cilium" = lib.mkOption {
        type = lib.types.submodule {
          options = {
            package = lib.mkPackageOption pkgs "cilium-cli" { } // {
              default = inputs.self.legacyPackages.${pkgs.hostPlatform.system}.cilium-cli;
            };

            routingMode = lib.mkOption {
              type = lib.types.attrTag {
                native = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      localIpv4 = lib.mkOption {
                        type = lib.types.str;
                      };

                      ipv4NativeRoutingCIDR = lib.mkOption {
                        type = lib.types.str;
                      };
                    };
                  };
                };

                tunnel = lib.mkOption {
                  type = lib.types.submodule {
                    options = {
                      protocol = lib.mkOption {
                        type = lib.types.enum [
                          "geneve"
                          "vxlan"
                        ];
                      };
                    };
                  };
                };
              };
            };

            values = lib.mkOption {
              type = (pkgs.formats.yaml { }).type;
              default = { };
            };
          };

          config = {
            values = {
              bpf.masquerade = true;
              # "ipv6.enabled" = true; # no need for now
              ipam.mode = "kubernetes";
              bpf.lbExternalClusterIP = true;
              envoy.enabled = false;
              encryption.enabled = true;
              encryption.type = "wireguard";
              k8sServiceHost = "127.0.0.1";
              image.useDigest = false;
              certgen.useDigest = false;
              hubble.relay.image.useDigest = false;
              hubble.ui.enabled = true;
              hubble.relay.enabled = true;
              hubble.ui.backend.image.useDigest = false;
              hubble.ui.frontend.image.useDigest = false;
              envoy.image.useDigest = false;
              operator.image.useDigest = false;
              nodeinit.image.useDigest = false;
              preflight.image.useDigest = false;
              preflight.envoy.image.useDigest = false;
              clustermesh.apiserver.image.useDigest = false;
              authentication.mutual.spire.install.initImage.useDigest = false;
              authentication.mutual.spire.install.agent.image.useDigest = false;
              authentication.mutual.spire.install.server.image.useDigest = false;
              standaloneDnsProxy.image.useDigest = false;
              endpointRoutes.enabled = true;
              debug.enabled = true;
              extraConfig = {
                cluster-name = cfgK8s.clusterName;
              };
            }
            // (lib.optionalAttrs (cfg.routingMode ? native) {
              routingMode = "native";
              inherit (cfg.routingMode.native) ipv4NativeRoutingCIDR;
              extraArgs = [ "--local-router-ipv4=${cfg.localIpv4}" ];
            })
            // (lib.optionalAttrs (cfg.routingMode ? tunnel) {
              routingMode = "tunnel";
              tunnelProtocol = cfg.routingMode.tunnel.protocol;
            });
          };
        };
        default = { };
      };
    };
  };

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
      cfg.package
    ];

    services.kubernetes.kubelet.nodeIp = lib.mkIf (
      cfgK8s.network.internal.interface == null
    ) "192.168.8.1,fd08:4e1::1";

    systemd.services."kube-cilium-install" = lib.mkIf cfgK8s.role.controlPlane.enable {
      requiredBy = [ "kubernetes-full.target" ];
      requires = [ "kubeadm-init.service" ];
      after = [ "kubeadm-init.service" ];

      environment."KUBECONFIG" = "/etc/kubernetes/admin.conf";

      path = [
        inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}."cilium-cli"
        pkgs.yq-go
        config.services.kubernetes.package
      ];

      script = ''
        _config_file="$RUNTIME_DIRECTORY/values.yaml"

        cp --no-preserve=all ${
          (pkgs.formats.yaml { }).generate "cilium-values.yaml" cfg.values
        } "$_config_file"

        _interface_ip=$(${
          lib.getExe (pkgs.callPackage ./fish-out-netif-ip.nix { })
        } ${cfgK8s.network.internal.interface})

        echo "Using $_interface_ip as 'localAPIEndpoint.advertiseAddress'"

        yq --inplace \
           '.k8s.apiServerURLs = ( [ "'"$_interface_ip"':6443" ] | join(" ") )' \
           "$_config_file"

        if kubectl get configmaps -n kube-system cilium-config >/dev/null 2>&1 ; then
          echo "Cilium looks to be installed already, upgrading to the same version, with new config"
          cilium upgrade --version ${config.services.kubernetes.package.passthru.cilium_image_version} --values "$_config_file"
        else
          echo "Performing a fresh Cilium install"
          cilium install --version ${config.services.kubernetes.package.passthru.cilium_image_version} --values "$_config_file"
        fi
        cilium status --wait
      '';

      serviceConfig = {
        SetLoginEnvironment = "yes";
        Type = "oneshot";
        RemainAfterExit = "yes";
        RuntimeDirectory = "kube-cilium-install";
      };
    };
  };
}
