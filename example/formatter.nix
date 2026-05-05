{
  pname,
  inputs,
  pkgs,
}:
let
  treefmt = inputs."treefmt-nix".lib.evalModule pkgs ./treefmt.nix;
in
treefmt.config.build.wrapper.overrideAttrs (old: {
  passthru = old.passthru // {
    check = treefmt.config.build.check inputs."self";
  };
})
