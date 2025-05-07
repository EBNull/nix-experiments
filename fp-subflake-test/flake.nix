{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    flakefmt.url = "path:./flakefmt";
    flakefmt.inputs.nixpkgs.follows = "nixpkgs";
    flakefmt.inputs.flake-parts.follows = "flake-parts";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      debug = true;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      imports = [
        #inputs.flake-parts.flakeModules.flakeModules
        inputs.flakefmt.flakeModules.default
      ];

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
          packages.foo = pkgs.writeShellApplication {
            name = "foo";
            text = ''echo hi'';
          };

          #packages.default = self'.packages.foo;
          packages.default = inputs'.flakefmt.packages.flakefmt-hello;

        };

      #packages.x86_64-linux.default = self.inputs.subtest.packages.x86_64-linux.hello;

    };
}
