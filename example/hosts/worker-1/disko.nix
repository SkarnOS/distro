{
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
  };

  disko.devices = {
    disk."sda" = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions."ESP" = {
          type = "EF00";
          size = "1G";
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
            mountpoint = "/";
          };
        };
      };
    };
  };
}
