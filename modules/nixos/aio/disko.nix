{ config, lib, ... }:
let
  cfg = config.rename-me.settings;
in
{
  disko.devices = {
    disk."main" = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions."boot" = lib.mkIf (cfg.boot == "mbr") {
          size = "1M";
          type = "EF02"; # for grub MBR
        };
        partitions."ESP" = {
          size = "500M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        partitions."root" = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/nix/persist";
          };
        };
      };
    };
    nodev."/tmp" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=200M"
      ];
    };
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=200M"
        "mode=755"
      ];
    };

    nodev."/nix/store" = {
      fsType = "none";
      device = "/mnt/nix/persist/nix/store";
      preMountHook = ''
        mkdir -p /mnt/nix/persist/nix/store
      '';
      mountOptions = [
        "bind"
        "X-mount.mkdir"
      ];
    };

    nodev."/nix/var" = {
      fsType = "none";
      device = "/mnt/nix/persist/nix/var";
      preMountHook = ''
        mkdir -p /mnt/nix/persist/nix/var
      '';
      mountOptions = [
        "bind"
        "X-mount.mkdir"
      ];
    };
  };

  fileSystems."/nix/persist".neededForBoot = true;
  fileSystems."/nix/var" = {
    neededForBoot = true;
    device = lib.mkForce "/nix/persist/nix/var";
  };
  fileSystems."/nix/store" = {
    neededForBoot = true;
    device = lib.mkForce "/nix/persist/nix/store";
  };

  environment.persistence."/nix/persist" = {
    # hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/containerd"
      "/opt/cni"
    ];
    files = [
      "/etc/machine-id"
    ]
    ++ (lib.map (hostKey: hostKey.path) config.services.openssh.hostKeys);
  };
}
