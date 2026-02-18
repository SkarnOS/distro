{ lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      options.rename-me.kubernetes = {
        versions = lib.mkOption {
          type = lib.types.lazyAttrsOf (
            lib.types.submodule {
              options = {
                version = lib.mkOption {
                  type = lib.types.str;
                };

                hash = lib.mkOption {
                  type = lib.types.str;
                };

                is_maintained = lib.mkOption {
                  type = lib.types.bool;
                };

                containers = lib.mkOption {
                  type = lib.types.attrsOf (lib.types.listOf lib.types.str);
                };

                cilium_image_version = lib.mkOption {
                  type = lib.types.str;
                };
              };
            }
          );
        };

        images = lib.mkOption {
          type = lib.types.attrsOf (
            (lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  hash = lib.mkOption {
                    type = lib.types.str;
                  };

                  digest = lib.mkOption {
                    type = lib.types.str;
                  };
                };
              }
            ))
          );
          default = { };
        };
      };

      config = {
        rename-me.kubernetes.images = lib.importJSON ./images.json;
        rename-me.kubernetes.versions = lib.mapAttrs (
          _: version:
          if lib.isString version then config.rename-me.kubernetes.versions.${version} else version
        ) (lib.importJSON ./sources.json);

        legacyPackages.cilium-cli = pkgs.callPackage ./cilium-cli.nix { };

        legacyPackages.kubernetes = lib.pipe config.rename-me.kubernetes.versions [
          (lib.mapAttrs' (
            name:
            {
              version,
              hash,
              is_maintained,
              containers,
              cilium_image_version,
            }:
            lib.nameValuePair (lib.replaceString "." "_" name) (
              pkgs.callPackage ./kubernetes.nix {
                inherit
                  version
                  hash
                  is_maintained
                  cilium_image_version
                  ;
                containers = lib.mapAttrs (
                  name: tags: lib.map (tag: config.legacyPackages.ociImages.${name}.${tag}) tags
                ) containers;
              }
            )
          ))
        ];

        legacyPackages.ociImages = lib.mapAttrs (
          name: versions:
          lib.mapAttrs (
            version: image:
            pkgs.dockerTools.pullImage {
              finalImageName = name;
              finalImageTag = version;
              imageName = name;
              imageDigest = image.digest;

              inherit (image)
                hash
                ;
            }
            // {
              passthru = image // {
                inherit name version;
              };
            }
          ) versions
        ) config.rename-me.kubernetes.images;
      };
    };
}
