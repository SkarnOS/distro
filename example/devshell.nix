{ pkgs, perSystem, ... }:
pkgs.mkShell {
  packages = [
    perSystem."skarnos"."skarnos"
  ];
}
