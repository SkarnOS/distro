{
  flake.nixosModules."kubernetes" = ./kubernetes;
  flake.nixosModules."helsinkiKubernetes" = ./helsinkiKubernetes.nix;
}
