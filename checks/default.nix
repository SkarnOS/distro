{
  inputs,
  lib,
  ...
}:
let
  doTestKubernetes =
    system: kubernetes:
    lib.meta.availableOn { inherit system; } kubernetes
    && kubernetes.passthru.is_maintained
    # we don't have aarch64-linux runners that can do KVM...
    && system != "aarch64-linux";
in
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
        (lib.mapAttrs' (name: lib.nameValuePair "package-${name}") config.packages)

        (lib.mapAttrs' (name: lib.nameValuePair "devshell-${name}") config.devShells)

        (lib.pipe inputs.self.nixosConfigurations [
          (lib.filterAttrs (_: nixos: nixos.pkgs.stdenv.hostPlatform.system == system))
          (lib.mapAttrs' (name: nixos: lib.nameValuePair "nixos-${name}" nixos.config.system.build.toplevel))
        ])

        (lib.pipe config.legacyPackages.kubernetes [
          (lib.filterAttrs (version: _: lib.length (lib.splitString "_" version) == 3))
          (lib.mapAttrs' (
            version: kubernetes:
            lib.nameValuePair "nixos-kubernetes-${version}" (
              lib.optionalAttrs (doTestKubernetes system kubernetes) (
                pkgs.callPackage ./kubernetes.nix { inherit kubernetes inputs; }
              )
            )
          ))
          (lib.filterAttrs (_: v: v != { }))
        ])
      ];
    };
}
