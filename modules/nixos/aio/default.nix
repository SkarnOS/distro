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

    systemd.network.networks."10-uplink" = {
      matchConfig = {
        Name = "enp?s? eth?";
      };
      networkConfig = {
        DHCP = "ipv4";
        Address = "2a01:4f8:1c19:2251::2/64";
      };
    };

    services.kubernetes.package =
      inputs."self".legacyPackages.${pkgs.stdenv.hostPlatform.system}.kubernetes."1_35";

    rename-me.kubernetes = {
      enable = true;
      network = {
        cni."cilium" = {
          localIpv4 = "10.224.6.1";
          ipv4NativeRoutingCIDR = "10.100.0.0/16";
        };
        ingress.interface = "eth0";
        nameservers = [ "10.224.6.1" ];
      };
      clusterName = "test-cluster";
    };

    networking.hostName = cfg.hostName;
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedKeys;

    boot.loader.systemd-boot.enable = lib.mkIf (cfg.boot == "efi") true;
  };
}
