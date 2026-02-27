{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    impermanence.url = "github:nix-community/impermanence?rev=4b3e914cdf97a5b536a889e939fb2fd2b043a170";
    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        ./treefmt.nix
        ./dev-shell.nix
        ./packages
        ./checks
        ./modules/nixos
        ./systems/nixos
      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      flake.lib.fromTOML =
        tomlFile:
        inputs."nixpkgs".lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            (
              { lib, ... }:
              {
                imports = [
                  inputs."self".nixosModules."aio"
                  inputs."srvos".nixosModules."hardware-hetzner-cloud"
                ];

                rename-me.settings = lib.mkMerge [
                  {
                    enable = true;
                  }
                  (builtins.fromTOML tomlFile)
                ];
              }
            )
          ];
        };
    };
}
