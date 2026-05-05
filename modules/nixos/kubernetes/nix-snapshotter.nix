{ inputs }:
{
  config,
  lib,
  ...
}:
let
  cfgK8s = config.skarnos.kubernetes;
  cfg = config.skarnos.kubernetes.nix-snapshotter;
in
{
  options.skarnos.kubernetes.nix-snapshotter = {
    enable = lib.mkEnableOption "Enable nix-snapshotter";
  };

  imports = [
    inputs.nix-snapshotter.nixosModules.default
  ];

  config = lib.mkIf (cfgK8s.enable && cfg.enable) {
    nixpkgs.overlays = [ inputs.nix-snapshotter.overlays.default ];

    services.kubernetes.kubelet.extraOpts = "--image-service-endpoint unix:///run/nix-snapshotter/nix-snapshotter.sock";

    virtualisation.containerd.nixSnapshotterIntegration = true;
    services.nix-snapshotter.enable = true;
  };
}
