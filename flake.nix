{
  description = "network-renderer-nebula";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";

    network-labs.url = "github:esp0xdeadbeef/network-labs";

    network-realization-model.url = "github:esp0xdeadbeef/network-realization-model";
    network-realization-model.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      network-control-plane-model,
      network-labs,
      network-realization-model,
      ...
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

      withHostModule = import ./host-module.nix {
        inherit
          lib
          network-realization-model
          ;
      };

      mkPackage = import ./s88/Enterprise/package.nix {
        inherit self nixpkgs;
      };
    in
    {
      libBySystem = forAllSystems (system: withHostModule (mkSystemLib system) system);

      lib = withHostModule (mkSystemLib "x86_64-linux") "x86_64-linux";

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

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          renderer = self.libBySystem.${system}.renderer;
          bundle = network-realization-model.lib.realize {
            input = import "${network-realization-model}/examples/cpm-result.nix";
            requestScope = {
              kind = "complete-artifact";
              identity = "nebula-renderer-boundary";
            };
            rootLockIdentity = "network-renderer-nebula-flake-lock";
            producerRevision = network-realization-model.rev;
          };
          accepted = renderer.canonical.validateInput { inherit bundle; };
          rawRejected =
            !(builtins.tryEval (
              builtins.deepSeq (renderer.canonical.validateInput {
                bundle = {
                  control_plane_model = { };
                };
              }) true
            )).success;
        in
        assert accepted.bundleIdentity == bundle.bundleIdentity;
        assert rawRejected;
        {
          canonical-renderer-input = pkgs.runCommand "network-renderer-nebula-canonical-input" { } ''
            touch "$out"
          '';
        }
      );
    };
}
