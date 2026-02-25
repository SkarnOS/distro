{ lib, inputs, ... }:
{
  flake.nixosConfigurations."worker-1" = inputs."nixpkgs".lib.nixosSystem {
    system = "x86_64-linux";

    modules = lib.singleton {
      imports = [
        inputs."self".nixosModules."aio"
        inputs."srvos".nixosModules."hardware-hetzner-cloud"
      ];

      rename-me.settings = {
        enable = true;

        hostName = "worker-1";
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVkFvalffJ/SMjJGG3WPiqCqFygnWzhGUaeALBIoCsJ cardno:23_148_290"
        ];
        boot = "efi";

        networking = {
          nodeIp = "10.100.6.1";
          nodeNetworkCidr = "10.100.0.0/16";
          uplink = {
            macAddress = "92:00:07:45:a4:b1";

            address.static = [ "2a01:4f8:1c19:2e2c::2/64" ];
            address.dhcp = "ipv4";
          };

          internal = {
            macAddress = "86:00:00:76:6d:ca";

            address.dhcp = true;
          };
        };

        role.worker.enable = true;
      };
    };
  };
}
