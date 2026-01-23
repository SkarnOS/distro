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
            lib.nameValuePair version (
              lib.optionalAttrs (
                lib.meta.availableOn { inherit system; } kubernetes && kubernetes.passthru.is_maintained
              ) (pkgs.callPackage ./kubernetes.nix { inherit kubernetes; })
            )
          ))
          (lib.filterAttrs (_: v: v != { }))
        ])
      ];
    };
}
