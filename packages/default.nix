{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages.kubernetes = lib.pipe (lib.importJSON ./sources.json) [
        (
          versions:
          lib.mapAttrs (_: target: if lib.isString target then versions.${target} else target) versions
        )
        (lib.mapAttrs' (
          name:
          {
            version,
            hash,
            is_maintained,
          }:
          lib.nameValuePair (lib.replaceString "." "_" name) (
            pkgs.callPackage ./kubernetes.nix { inherit version hash is_maintained; }
          )
        ))
      ];

      legacyPackages.ociImages = lib.mapAttrs (
        _: image:
        pkgs.dockerTools.pullImage {
          inherit (image)
            finalImageName
            finalImageTag
            hash
            imageDigest
            imageName
            ;
        }
      ) (lib.importJSON ./images.json);
    };
}
