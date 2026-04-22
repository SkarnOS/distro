{
  inputs."nixpkgs" = {
    url = "github:NixOS/nixpkgs?ref=nixos-unstable";
  };

  inputs."srvos" = {
    url = "github:nix-community/srvos";
    inputs."nixpkgs".follows = "nixpkgs";
  };

  inputs."disko" = {
    url = "github:nix-community/disko";
    inputs."nixpkgs".follows = "nixpkgs";
  };

  inputs."treefmt-nix" = {
    url = "github:numtide/treefmt-nix";
    inputs."nixpkgs".follows = "nixpkgs";
  };

  inputs."blueprint" = {
    url = "github:numtide/blueprint";
    inputs."nixpkgs".follows = "nixpkgs";
  };

  inputs."skarnos" = {
    url = "github:skarnos/distro";
    inputs."nixpkgs".follows = "nixpkgs";
    inputs."treefmt-nix".follows = "treefmt-nix";
    inputs."disko".follows = "disko";
    inputs."srvos".follows = "srvos";
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
