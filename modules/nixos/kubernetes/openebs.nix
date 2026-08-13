{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.skarnos.kubernetes.openebs;
in
{
  options.skarnos.kubernetes.openebs = {
    enable = lib.mkEnableOption "Enable OpenEBS";
  };

  config = {
    boot.kernelModules = [
      "nvme-tcp"
    ];
    boot.extraModprobeConfig = ''
      options nvme_core multipath=Y
    '';

    environment.systemPackages = lib.mkIf cfg.enable [ pkgs.lvm2 ];

    # lvm-localpv also needs a dedicated LVM volume group on the node. Create
    # an empty VG (e.g. with disko) and point the StorageClass at it.

    # OpenEBS's lvm-localpv mounts the host and expects this binary to exist.
    systemd.tmpfiles.rules = lib.mkIf cfg.enable [
      "d /sbin 0755 root root -"
      "L+ /sbin/fsadm - - - - /run/current-system/sw/bin/fsadm"
    ];
  };
}
