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

      withHostModule =
        systemLib:
        systemLib // {
          renderer = systemLib.renderer // {
            hostModule =
              _rendererInput:
              { ... }:
              {
                # TODO: implement the Nebula backend NixOS host module.
                # Temporary no-op so consumers can depend on the standard renderer
                # contract without patching downstream NixOS host profiles.
              };
          };
        };

      mkPackage =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          executable = pkgs.replaceVars ./bin/network-renderer-nebula {
            SELF_PATH = self.outPath;
            NIXPKGS_LIB_PATH = "${nixpkgs}/lib";
            RENDERER_GIT_REV = self.rev or (self.dirtyRev or "unknown");
            RENDERER_DIRTY = if self ? dirtyRev then "true" else "false";
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
      libBySystem = forAllSystems (
        system:
        withHostModule (mkSystemLib system)
      );

      lib = withHostModule (mkSystemLib "x86_64-linux");

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
