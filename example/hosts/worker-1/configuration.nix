{ inputs, hostName, ... }:
{
  imports = [
    inputs."srvos".nixosModules."hardware-hetzner-cloud"
    inputs."disko".nixosModules."default"
    inputs."skarnos".nixosModules."kubernetes"
    ./disko.nix
    ./kubernetes.nix
  ];

  systemd.network.networks."10-uplink" = {
    matchConfig.Name = [
      "eth*"
      "enp*"
    ];
    networkConfig.DHCP = "yes";
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
  };
  users.users."root" = {
    password = "toor";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFVkFvalffJ/SMjJGG3WPiqCqFygnWzhGUaeALBIoCsJ magic_rb"
    ];
  };

  disabledModules = [
    inputs."srvos".nixosModules."mixins-cloud-init"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  networking = {
    inherit hostName;
    domain = "m.skarnos.com";
  };
}
