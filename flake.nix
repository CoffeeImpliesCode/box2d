{
  description = "Box2D (erincatto/box2d v3.1.1) as a standalone Zig SDK: the full native core, a typed Zig surface and separate static and shared variants";

  # Pin nixpkgs here and keep its resolved input in flake.lock.
  inputs.nixpkgs.url =
    "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

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
      # Exposes static and shared derivations; static is the default.
      packages = forAllSystems (pkgs:
        # Use the pinned Zig 0.17.0 package, not the moving pkgs.zig alias.
        assert pkgs.zig_0_17.version == "0.17.0";
        # Without -Dtarget, build and host platforms must match.
        assert pkgs.stdenv.hostPlatform.system == pkgs.stdenv.buildPlatform.system;
        let
          box2d = linkage: pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_17;
            inherit linkage;
          };
        in
        rec {
          static = box2d "static";
          shared = box2d "dynamic";
          default = static;
        });

      # Tool-only fallback shell; it does not build the SDK package.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "box2d";
          packages = [
            pkgs.zig_0_17
            pkgs.pkg-config
            pkgs.gnumake
            pkgs.git
          ];
        };
      });
    };
}