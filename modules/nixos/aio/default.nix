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
  };

  config = lib.mkIf cfg.enable {
    users.users.root.password = "";
    users.mutableUsers = false;

    systemd.network.enable = true;
    networking.useNetworkd = true;
    networking.firewall.enable = lib.mkForce false;

    services.cloud-init.enable = lib.mkForce false;

    systemd.network.links."10-uplink" = {
      matchConfig.PermanentMACAddress = "92:00:07:44:f5:5d";
      linkConfig.Name = "uplink";
    };

    systemd.network.networks."10-uplink" = {
      matchConfig.Name = "uplink";
      networkConfig = {
        DHCP = "ipv4";
        Address = "2a01:4f8:1c19:2251::2/64";
      };
    };

    systemd.network.links."10-int" = {
      matchConfig.PermanentMACAddress = "86:00:00:76:6d:d0";
      linkConfig.Name = "kube-int";
    };

    systemd.network.networks."10-int" = {
      matchConfig.Name = "kube-int";
      networkConfig.DHCP = "yes";
    };

    services.kubernetes.package =
      inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.kubernetes."1_35";

    services.resolved.settings.Resolve = {
      DNSStubListenerExtra = "10.224.6.1";
    };

    rename-me.kubernetes = {
      enable = true;
      network = {
        cni."cilium" = {
          localIpv4 = "10.224.6.1";
          ipv4NativeRoutingCIDR = "10.100.0.0/16";
        };
        internal.interface = "kube-int";
        ingress.interface = "uplink";
        nameservers = [ "10.224.6.1" ];
      };
      clusterName = "test-cluster";

      role.controlPlane = {
        enable = true;
      };
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
