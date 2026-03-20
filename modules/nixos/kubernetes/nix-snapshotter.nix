{ inputs }:
{
  config,
  lib,
  ...
}:
let
  cfgK8s = config.rename-me.kubernetes;
  cfg = config.rename-me.kubernetes.nix-snapshotter;
in
{
  options.rename-me.kubernetes.nix-snapshotter = {
    enable = lib.mkEnableOption "Enable nix-snapshotter";
  };

  imports = [
    inputs.nix-snapshotter.nixosModules.default
  ];

  config = lib.mkIf (cfgK8s.enable && cfg.enable) {
    nixpkgs.overlays = [ inputs.nix-snapshotter.overlays.default ];

    virtualisation.containerd.nixSnapshotterIntegration = true;
    services.nix-snapshotter.enable = true;
  };
}
