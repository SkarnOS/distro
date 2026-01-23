{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    {
      checks = lib.mkMerge [
        (lib.pipe config.legacyPackages.kubernetes [
          (lib.filterAttrs (version: _: lib.length (lib.splitString "_" version) == 3))
          (lib.mapAttrs' (
            version: kubernetes:
            lib.nameValuePair version (pkgs.callPackage ./kubernetes.nix { inherit kubernetes; })
          ))
        ])
      ];
    };
}
