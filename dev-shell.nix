{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.treefmt.build.wrapper
          pkgs.skopeo
          pkgs.nix-prefetch-docker
          pkgs.nix-eval-jobs
          pkgs.nix-fast-build
          config.legacyPackages.cilium-cli
          (pkgs.python3.withPackages (ps: [
            ps.pydantic
            ps.requests
            ps.semver
            ps.async-lru
          ]))
        ];
      };
    };
}
