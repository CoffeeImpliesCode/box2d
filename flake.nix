{
  description = "Box2D (erincatto/box2d v3.1.1) as a standalone Zig SDK: the full native core, a typed Zig surface and separate static and shared variants";

  # One fixed nixpkgs input, pinned to a revision rather than a channel: this
  # package's build, its Zig version and its licence metadata must not move
  # because a branch moved. `flake.lock` records a resolution of that pin: it is
  # in this tree, it names the revision below, it travels in `build.zig.zon`'s
  # `.paths`, and it is reviewed like the rest of the tree. No hash is invented
  # here.
  inputs.nixpkgs.url =
    "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Two derivations, not two modules. One source tree, one build graph, one
      # C ABI; `linkage` is the only difference, exactly as in `package.nix`.
      #
      # `default` is `static`, which is this SDK's policy and upstream's own
      # CMake default (`BUILD_SHARED_LIBS` unset).
      packages = forAllSystems (pkgs:
        # `zig_0_16` is named, not aliased: `pkgs.zig` is a moving alias and
        # this SDK is written against 0.16.0.
        assert pkgs.zig_0_16.version == "0.16.0";
        # `zig build` runs without -Dtarget, so a cross stdenv would install the
        # build machine's library under the host's name. Comparing the two
        # platforms keeps an ordinary remote native builder valid.
        assert pkgs.stdenv.hostPlatform.system == pkgs.stdenv.buildPlatform.system;
        let
          box2d = linkage: pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_16;
            inherit linkage;
          };
        in
        rec {
          static = box2d "static";
          shared = box2d "dynamic";
          default = static;
        });

      # Tools only. Entering a shell must never build the library, so the SDK
      # package is deliberately absent. Canonical development is `devenv shell`
      # (`devenv.nix`, `devenv.yaml`, `.envrc`); this shell is parity for a host
      # without devenv, and it is not claimed to be equivalent.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "box2d";
          packages = [
            pkgs.zig_0_16
            pkgs.pkg-config
            pkgs.gnumake
            pkgs.git
          ];
        };
      });
    };
}