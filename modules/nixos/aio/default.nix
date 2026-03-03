{
  inputs,
}:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.rename-me.settings;
in
{
  imports = [
    inputs."self".nixosModules."kubernetes"
    inputs."disko".nixosModules."default"
    inputs."srvos".nixosModules."server"
    inputs."impermanence".nixosModules."default"
    ./disko.nix
  ];

  options.rename-me.settings = {
    enable = lib.mkEnableOption "Enable settings";

    hostName = lib.mkOption {
      type = lib.types.str;
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
    };

    boot = lib.mkOption {
      type = lib.types.enum [
        "efi"
        "mbr"
      ];
    };

    deployment = {
      address = lib.mkOption {
        type = lib.types.str;
      };
    };

    networking = {
      nodeIp = lib.mkOption {
        type = lib.types.str;
      };

      nodeNetworkCidr = lib.mkOption {
        type = lib.types.str;
      };

      uplink = {
        macAddress = lib.mkOption {
          type = lib.types.str;
        };

        address = {
          static = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          dhcp = lib.mkOption {
            type = lib.types.enum [
              "ipv4"
              "ipv6"
              true
              false
            ];
            default = false;
          };
        };
      };
      internal = {
        macAddress = lib.mkOption {
          type = lib.types.str;
        };

        address = {
          static = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };

          dhcp = lib.mkOption {
            type = lib.types.enum [
              "ipv4"
              "ipv6"
              true
              false
            ];
            default = false;
          };
        };
      };
    };

    role = {
      controlPlane.enable = lib.mkEnableOption "";
      worker.enable = lib.mkEnableOption "";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.root.password = "";
    users.mutableUsers = false;

    systemd.network.enable = true;
    networking = {
      useNetworkd = true;
      firewall = {
        logRefusedPackets = true;
        trustedInterfaces = [
          # only works on iptables, not nftables
          "lxc+"
          "kube-int"
        ];
      };
    };

    services.cloud-init.enable = lib.mkForce false;

    systemd.network.links."10-uplink" = {
      matchConfig.PermanentMACAddress = cfg.networking.uplink.macAddress;
      linkConfig.Name = "uplink";
    };

    systemd.network.networks."10-uplink" = {
      matchConfig.Name = "uplink";
      networkConfig = {
        DHCP = cfg.networking.uplink.address.dhcp;
        Address = cfg.networking.uplink.address.static;
      };
    };

    systemd.network.links."10-int" = {
      matchConfig.PermanentMACAddress = cfg.networking.internal.macAddress;
      linkConfig.Name = "kube-int";
    };

    systemd.network.networks."10-int" = {
      matchConfig.Name = "kube-int";
      networkConfig.DHCP = cfg.networking.internal.address.dhcp;
    };

    services.kubernetes.package =
      inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.kubernetes."1_35";

    rename-me.kubernetes = {
      enable = true;
      network = {
        cni."cilium" = {
          localIpv4 = cfg.networking.nodeIp;
          ipv4NativeRoutingCIDR = cfg.networking.nodeNetworkCidr;
        };
        internal.interface = "kube-int";
        ingress.interface = "uplink";
        nameservers = [ cfg.networking.nodeIp ];
      };
      clusterName = "test-cluster";

      role.controlPlane.enable = cfg.role.controlPlane.enable;
      role.worker.enable = cfg.role.worker.enable;
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "show-files-to-be-deleted" ''
        if [[ "$#" != "1" ]] ; then
          echo "Invalid number ($#) of argumets, one expected."
          exit 1
        fi

        _mount_point="$1"

        find "$1" -mount -type f
      '')
    ];

    networking.hostName = cfg.hostName;
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    boot.loader.systemd-boot.enable = lib.mkIf (cfg.boot == "efi") true;
  };
}
