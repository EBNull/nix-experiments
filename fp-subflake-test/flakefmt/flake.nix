{
  description = "Automatically use and configure treefmt-nix (and the importing flake's formatter)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{
        config,
        withSystem,
        moduleWithSystem,
        ...
      }:
      let
        flakeModules.default = flake-parts.lib.importApply ./flake-module.nix { localInputs = inputs; };
      in
      {
        imports = [
          flakeModules.default
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];

        flake = {
          inherit flakeModules;
        };

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
            # An example of adding additional flake perSystem outputs
            packages.flakefmt-hello = pkgs.hello;
          };
      }
    );
}
