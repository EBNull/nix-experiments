{ localInputs }:

inp@{ inputs, perSystem, ... }:
{
  config = {
    perSystem =
      {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }:
      {
        treefmt = {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = pkgs.lib.meta.availableOn pkgs.stdenv.buildPlatform pkgs.nixfmt-rfc-style.compiler;
          programs.nixfmt.package = pkgs.nixfmt-rfc-style;
        };
      };
  };
}
// ((import localInputs.treefmt-nix.flakeModule) inp)
