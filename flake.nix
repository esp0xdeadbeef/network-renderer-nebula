{
  description = "network-renderer-nebula";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    network-control-plane-model.url = "github:esp0xdeadbeef/network-control-plane-model";
    network-control-plane-model.inputs.nixpkgs.follows = "nixpkgs";
    # Unify the control-plane model's network-labs with ours: without this the
    # pinned control-plane model keeps its own network-labs, whose lock points
    # back at the control-plane model -- a circular flake import that breaks
    # `nix flake lock`/`metadata` here.  Same shape as network-renderer-nixos.
    network-control-plane-model.inputs.network-labs.follows = "network-labs";

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

      # THE ENVIRONMENT THE TESTS NEED, DECLARED IN THE REPO-ROOT FLAKE.
      #
      # Every suite here shells out to nix, jq and git, and some use rg, ssh and
      # python3. Until this existed those came from the runner image plus ad-hoc
      # `curl`s in the workflow, so the environment was implicit: no derivation
      # described it, nothing could cache it coherently, and each job re-fetched the
      # same bytes.
      #
      # `nix develop` and `nix build .#devShells.<sys>.default` are the two consumers.
      # CI reads the PATH that `nix print-dev-env` reports and exports it, so the tools
      # a test runs are the ones declared here and nothing is installed outside it.
      #
      # Deliberately no `pkgs.nix`: CI installs its own Nix, and two versions evaluate
      # the same flake to different derivations -- which silently breaks every cache.
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "network-tests";
            packages = [
              pkgs.git
              pkgs.jq
              pkgs.openssh
              pkgs.python3
              pkgs.ripgrep
              pkgs.zstd
            ];
          };
        }
      );

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
          # RR_RAW_CPM_INPUT: a bare control-plane artifact is not a renderer
          # input. `validateInput` must reject it rather than accept it as a
          # bundle that happens to be missing every required field.
          rawRejected =
            !(builtins.tryEval (
              builtins.deepSeq (renderer.canonical.validateInput {
                bundle = {
                  kind = "network-control-plane-artifact";
                  control_plane_envelope = { };
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
