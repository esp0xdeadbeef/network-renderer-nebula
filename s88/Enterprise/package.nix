{ self, nixpkgs }:
system:
let
  pkgs = import nixpkgs { inherit system; };
  template = builtins.readFile ../../bin/network-renderer-nebula;
  executable = builtins.replaceStrings
    [
      "@SELF_PATH@"
      "@NIXPKGS_LIB_PATH@"
      "@RENDERER_GIT_REV@"
      "@RENDERER_DIRTY@"
    ]
    [
      (toString self.outPath)
      "${nixpkgs}/lib"
      (self.rev or (self.dirtyRev or "unknown"))
      (if self ? dirtyRev then "true" else "false")
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
