{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.treefmt.build.wrapper
          (pkgs.python3.withPackages (ps: [
            ps.pydantic
            ps.requests
          ]))
        ];
      };
    };
}
