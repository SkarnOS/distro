{ lib, inputs, ... }:
{
  flake.nixosModules."kubernetes" = lib.modules.importApply ./kubernetes { inherit inputs; };
  flake.nixosModules."aio" = lib.modules.importApply ./aio { inherit inputs; };
  flake.nixosModules."helsinkiKubernetes" = ./helsinkiKubernetes.nix;
}
