{
  description = "network-renderer-nebula";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";

    network-labs.url = "github:esp0xdeadbeef/network-labs";
  };

  outputs =
    { self
    , nixpkgs
    , network-control-plane-model
    , network-labs
    , ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      mkSystemLib =
        system:
        import ./s88/Enterprise/default.nix {
          inherit lib system;
          flakeInputs = {
            inherit
              nixpkgs
              network-control-plane-model
              network-labs
              ;
          };
        };

      mkPackage =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          executable = pkgs.replaceVars ./bin/network-renderer-nebula {
            SELF_PATH = self.outPath;
          };
        in
        pkgs.writeShellApplication {
          name = "network-renderer-nebula";
          runtimeInputs = [
            pkgs.jq
            pkgs.nix
          ];
          text = builtins.readFile executable;
        };
    in
    {
      libBySystem = forAllSystems mkSystemLib;
      lib = mkSystemLib "x86_64-linux";
      packages = forAllSystems (system: {
        default = mkPackage system;
        network-renderer-nebula = mkPackage system;
      });
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/network-renderer-nebula";
        };
      });
    };
}
