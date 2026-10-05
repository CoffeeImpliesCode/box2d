# Canonical development environment for the Box2D SDK.
#
# `packages` is tools only. The SDK package is deliberately absent: entering a
# shell must not build the library you came to work on.
#
# `outputs` exposes the same `package.nix` the flake builds, lazily. Nothing is
# realised until `devenv build outputs.static` (or `.shared`) is run, so the
# shell stays cheap while the packaging route stays real.
#
# No host path, account, mount or store path is written in this file, and no
# variable the caller supplied is erased. Where the Zig caches go is decided by
# the environment this shell is entered from: `enterShell` fills a missing one
# so an interactive build agrees with the tasks, and every task body repeats
# that fill, because `devenv tasks run --mode single` reaches a body without
# passing through the shell hook. Every task and script below starts from this
# module's own directory, because devenv runs both of them with the caller's
# working directory.
#
# What was observed, and what was not. On 2026-10-04 the driver built this SDK's
# two Nix outputs from the flake (`path:<sdk>#static` and `path:<sdk>#shared`)
# and both were realised: `nix-acceptance-20261004T175328Z`,
# `box2d-nix-build.log`, exit 0, two `drvPath`s and two store outputs. The six
# devenv gates in that same run never reached a task or a script — `flake: false`
# in `devenv.yaml` made devenv's nixpkgs a plain source tree with no `lib`, and
# every subcommand died in bootstrap at `lib = nixpkgs.lib` with
# `error: attribute 'lib' missing`. The key is deleted; the pinned revision is
# unchanged. Nothing in this file has been run since that edit, so its
# statements about the build graph remain SOURCE-CONFIRMED by reading
# `build.zig` and `package.nix` in this repository, and every derivation, task
# and script below is PENDING-VERIFICATION again.
#
# Nothing below derives from `$PWD` or `$DEVENV_ROOT`. Under the canonical
# `devenv --from path:<sdk>` run those name a scratch project that holds
# neither `build.zig` nor `UPSTREAM.sha256` nor `consumer/`: observed for this
# SDK's siblings on 2026-10-04, in `devenv info`'s own `DEVENV_ROOT`, and again
# as `error: no build.zig file found` from a canonical entry.

{ pkgs, lib, ... }:

let
  mkBox2d = linkage:
    pkgs.callPackage ./package.nix {
      inherit linkage;
      zig = pkgs.zig_0_16;
    };

  # Read for its declared identity only; reading `.version` does not realise it.
  box2dStatic = mkBox2d "static";

  # This module's own directory, and the shell-quoted form every body below
  # starts from.
  #
  # `./.` in an expression is relative to the file that contains it, so this is
  # the SDK root however devenv was invoked. It is `builtins.toString` and not
  # `"${./.}"` deliberately: interpolating a path copies it into the read-only
  # Nix store, which for this tree would be a second, frozen copy of the whole
  # SDK rather than the working tree an integrity record, an edit and a
  # consumer's path dependency are about.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # The build cache and every delivery output go beneath the local cache the
  # caller's environment already names, never into this repository and never
  # onto a volume this file knows nothing about. The path is assembled here, in
  # Nix, and expanded by the shell at run time because the location is the
  # caller's rather than this file's.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/box2d";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/box2d-prefix";

  # The one preamble every task and script below opens with: this module's own
  # directory, then the two Zig cache locations, then a refusal rather than a
  # guess. A value the caller already exported is used unchanged; only a missing
  # one is filled in, from `XDG_CACHE_HOME` first and `TMPDIR` second, which is
  # the order `blake3`, `box3d` and `geographiclib-c` already use. The fill is
  # repeated here rather than left to `enterShell` because
  # `devenv tasks run --mode single` bypasses the shell hook and reaches a body
  # on its own, so this has to happen before the compiler is invoked. No
  # fallback is a literal `/tmp`, `/var/tmp`, an NFS mount or a path inside this
  # repository, and nothing here invents a name of its own.
  cdSdkRoot = ''
    cd ${sdkRootArg} || exit 1
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="''${XDG_CACHE_HOME}/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="''${TMPDIR}/zig-local-cache"
      else
        echo "box2d devenv: ZIG_LOCAL_CACHE_DIR is unset and neither XDG_CACHE_HOME nor TMPDIR names a location, so no cache or prefix is chosen here." >&2
        exit 1
      fi
      export ZIG_LOCAL_CACHE_DIR
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${XDG_CACHE_HOME}/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${TMPDIR}/zig-global-cache"
      else
        echo "box2d devenv: ZIG_GLOBAL_CACHE_DIR is unset and neither XDG_CACHE_HOME nor TMPDIR names a location, so no global cache is chosen here." >&2
        exit 1
      fi
      export ZIG_GLOBAL_CACHE_DIR
    fi
  '';
in
{
  # Tools only, and unconditional: the SDK package is never among them, so
  # entering the shell cannot build the library. A caller who wants a
  # different tool list overrides `packages` in their own module.
  packages = [
    pkgs.zig_0_16
    pkgs.pkg-config
    pkgs.git
  ];

  # `outputs`, `tasks`, `scripts`, `enterShell` and `assertions` are top-level
  # devenv options, so they are declared at the top level too. Under a
  # `lib.mkIf` guard they would all vanish unless a flag were set in
  # `devenv.yaml`, and `devenv build outputs.static` would have nothing to build.
  outputs = {
    static = box2dStatic;
    shared = mkBox2d "dynamic";
    default = box2dStatic;
  };

  env = {
    BOX2D_SDK_NAME = "box2d";
    BOX2D_SDK_VERSION = box2dStatic.version;
  };

  enterShell = ''
    # Approved local scratch, never the repository and never a small system
    # temporary filesystem. A value the caller already exported wins; this
    # shell only fills in a default derived from XDG_CACHE_HOME first and
    # TMPDIR second, which is the same order and the same names every task body
    # below uses, and if neither names a location it says so rather than
    # choosing one.
    if [ -n "''${XDG_CACHE_HOME:-}" ] || [ -n "''${TMPDIR:-}" ]; then
      box2d_cache_base="''${XDG_CACHE_HOME:-''${TMPDIR}}"
      : "''${ZIG_GLOBAL_CACHE_DIR:=$box2d_cache_base/zig-global-cache}"
      : "''${ZIG_LOCAL_CACHE_DIR:=$box2d_cache_base/zig-local-cache}"
      export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
    else
      echo "box2d devenv: XDG_CACHE_HOME and TMPDIR are both unset, so no Zig cache location is chosen here; a task refuses to run until one of them is set." >&2
    fi

    echo "Box2D SDK development environment"
    echo "  sdk:       $BOX2D_SDK_NAME $BOX2D_SDK_VERSION (upstream v3.1.1)"
    echo "  compiler:  $(zig version)"
    echo "  licence:   MIT native core and MIT fork files; NOTICE.md records the rest"
    echo "  build:     zig build | zig build test | zig build smoke | zig build check"
    echo "  linkage:   static is the default; -Dlinkage=dynamic delivers the shared form"
    echo "  runtime:   -Druntime=true, then load(.{.path=...}) or load(.{.system=...})"
    echo "  tasks:     devenv tasks run box2d:build | box2d:test | box2d:smoke"
    echo "             box2d:check | box2d:install | box2d:runtime | box2d:matrix"
    echo "  scripts:   box2d:integrity | box2d:consumer"
    echo "             box2d:package-static | box2d:package-shared"
    echo "  packages:  devenv build outputs.static | devenv build outputs.shared"
    echo "  cache:     ZIG_LOCAL_CACHE_DIR/box2d, ZIG_LOCAL_CACHE_DIR/box2d-prefix"
  '';

  # Namespaced: devenv puts task names on one list, and a bare `build` or
  # `test` would collide with the ordinary shell commands of the same name.
  #
  # Every body below starts from this module's own directory: `cdSdkRoot` for
  # every task and script that reaches a compiler, a plain `cd` for the two Nix
  # builds and the integrity check, which need the directory but no cache. A
  # task is executed with the caller's working directory, not with this
  # module's, and that directory is not required to hold `build.zig`.
  #
  # `--cache-dir` and `--prefix` then keep what the run generates under the
  # local cache the caller's environment already named; `-j8` is this
  # workspace's job count and `--summary all` the step list this workspace's
  # gates are read against, so a task does not silently drop to one job or to
  # a single-line build summary.
  tasks = {
    "box2d:build" = {
      description = "Build the native library and compile the smoke example";
      exec = ''
        ${cdSdkRoot}
        zig build --cache-dir "${cacheDir}" --prefix "${installPrefix}" -j8 --summary all
      '';
    };

    "box2d:test" = {
      description = "Run the behavioural tests";
      exec = ''
        ${cdSdkRoot}
        zig build test --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

    "box2d:smoke" = {
      description = "Run the deterministic smoke example";
      exec = ''
        ${cdSdkRoot}
        zig build smoke --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

    "box2d:check" = {
      description = "Compile the public surface for every selected target, running nothing";
      exec = ''
        ${cdSdkRoot}
        zig build check --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

    "box2d:install" = {
      description = "Install the library, headers, pkg-config and licence material under $ZIG_LOCAL_CACHE_DIR";
      exec = ''
        ${cdSdkRoot}
        zig build install --cache-dir "${cacheDir}" --prefix "${installPrefix}" -j8 --summary all
      '';
    };

    "box2d:runtime" = {
      description = "Build the runtime-loading dispatch instead of a linked archive";
      exec = ''
        ${cdSdkRoot}
        zig build smoke -Druntime=true --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

    # `cross-test` is the workspace's own tool and it owns every path it uses:
    # `cross-test.profile.sh` refuses to name a compiler cache or an output
    # directory, and the harness refuses `--cache-dir`, `--prefix`, `--summary`
    # and `-j` after `--` outright, so this body names neither path flag. It
    # starts from this module's own directory and lets the preamble place the
    # global cache it reads at `cross-test:752`.
    #
    # Its concurrency is named here rather than left to the harness defaults,
    # which are `--jobs 2 --build-jobs 1`: this workspace's eight jobs on both
    # axes, so the matrix does not silently drop to one compiler job per target.
    # These are the harness's own flags, two separate tokens each; every other
    # setting, the matrix, the build step and the deadlines stays with
    # `cross-test.profile.sh`.
    "box2d:matrix" = {
      description = "Run this workspace's full published platform matrix";
      exec = ''
        ${cdSdkRoot}
        cross-test --jobs 8 --build-jobs 8
      '';
    };
  };

  # devenv runs a string script through a shell, which is what these need:
  # the integrity check has to be able to fail the script, and the two Nix
  # builds need their own arguments.
  scripts = {
    # The integrity record compares the bytes this fork did not author
    # against the digests recorded when the tree was acquired. Its paths are
    # relative to the tree, so this one has to run there and not in whatever
    # directory the caller happened to be standing in.
    "box2d:integrity" = {
      description = "Check every upstream and vendored digest in UPSTREAM.sha256";
      exec = ''
        cd ${sdkRootArg}
        sha256sum -c UPSTREAM.sha256
      '';
    };

    # The consumer is a separate package with its own build graph, so a
    # failure here localises to the consumer rather than to the SDK.
    "box2d:consumer" = {
      description = "Build and run the separate consumer package";
      exec = ''
        ${cdSdkRoot}
        cd consumer
        zig build run --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

    # `path:` rather than `.`: a flake evaluated from a git checkout carries
    # only committed files, and this working copy is uncommitted. `path:`
    # evaluates the tree this module lives in, which is what makes these two
    # work from any directory and not only from the one the caller started in.
    # That tree's `flake.lock` is what makes these builds resolve the pinned
    # revision rather than a branch.
    "box2d:package-static" = {
      description = "Build the static Nix variant through the flake";
      exec = ''
        cd ${sdkRootArg}
        nix build --no-link --print-out-paths "path:${sdkRoot}#static" "$@"
      '';
    };

    "box2d:package-shared" = {
      description = "Build the shared Nix variant through the flake";
      exec = ''
        cd ${sdkRootArg}
        nix build --no-link --print-out-paths "path:${sdkRoot}#shared" "$@"
      '';
    };
  };

  assertions = [
    {
      assertion = pkgs.zig_0_16.version == "0.16.0";
      message = "box2d is written against Zig 0.16.0; this nixpkgs exposes "
        + pkgs.zig_0_16.version;
    }
  ];
}