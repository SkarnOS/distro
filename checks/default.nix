{ inputs, lib, ... }:
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
        (lib.mapAttrs' (
          name: value: lib.nameValuePair ("kubernetes_" + name) value
        ) config.legacyPackages.kubernetes)

        (lib.pipe config.legacyPackages.kubernetes [
          (lib.filterAttrs (version: _: lib.length (lib.splitString "_" version) == 3))
          (lib.mapAttrs' (
            version: kubernetes:
            lib.nameValuePair "nixos-kubernetes-${version}" (
              lib.optionalAttrs (
                lib.meta.availableOn { inherit system; } kubernetes && kubernetes.passthru.is_maintained
              ) (pkgs.callPackage ./kubernetes.nix { inherit kubernetes inputs; })
            )
          ))
          (lib.filterAttrs (_: v: v != { }))
        ])
      ];
    };
}
