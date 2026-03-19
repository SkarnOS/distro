{
  config,
  ...
}:
{
  options.rename-me.kubernetes.openebs = {
    enable = lib.mkEnableOption "Enable OpenEBS";
  };

  config = {
    boot.kernelModules = [
      "nvme-tcp"
    ];
    boot.extraModprobeConfig = ''
      options nvme_core multipath=Y
    '';
  };
}
