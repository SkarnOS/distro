{ lib, inputs, ... }:
{
  flake.nixosConfigurations."control-plane" = inputs."nixpkgs".lib.nixosSystem {
    system = "x86_64-linux";

    modules = lib.singleton {
      imports = [
        inputs."self".nixosModules."aio"
        inputs."srvos".nixosModules."hardware-hetzner-cloud"
      ];

      rename-me.settings = {
        enable = true;

        hostName = "control-plane";
        authorizedKeys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVkFvalffJ/SMjJGG3WPiqCqFygnWzhGUaeALBIoCsJ cardno:23_148_290"
        ];
        boot = "efi";
      };
    };
  };
}
