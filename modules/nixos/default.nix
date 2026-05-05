{ lib, inputs, ... }:
{
  flake.nixosModules."kubernetes" = lib.modules.importApply ./kubernetes { inherit inputs; };
}
