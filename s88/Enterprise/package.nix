{ self, nixpkgs }:
system:
let
  pkgs = import nixpkgs { inherit system; };
  template = builtins.readFile ../../bin/network-renderer-nebula;
  # Nix excludes flake.lock from a flake's store source tree, so the running
  # wrapper cannot read `${self.outPath}/flake.lock`.  Embed the locked input
  # summary at build time instead so emitter provenance can still record it
  # (FS-100-HDS-010-SDS-010-SMS-010).
  rendererLockSummary = builtins.toJSON {
    available = true;
    nodes = builtins.mapAttrs
      (name: input: {
        type = "github";
        owner = "esp0xdeadbeef";
        repo = name;
        rev = input.rev or null;
        narHash = input.narHash or null;
      } // (if input ? lastModified then { inherit (input) lastModified; } else { }))
      self.inputs;
  };
  executable = builtins.replaceStrings
    [
      "@SELF_PATH@"
      "@NIXPKGS_LIB_PATH@"
      "@RENDERER_GIT_REV@"
      "@RENDERER_DIRTY@"
      "@RENDERER_LOCK_SUMMARY@"
    ]
    [
      (toString self.outPath)
      "${nixpkgs}/lib"
      (self.rev or (self.dirtyRev or "unknown"))
      (if self ? dirtyRev then "true" else "false")
      rendererLockSummary
    ]
    template;
in
pkgs.writeShellApplication {
  name = "network-renderer-nebula";
  runtimeInputs = [
    pkgs.jq
    pkgs.nix
  ];
  text = executable;
}
