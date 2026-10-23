# Development environment for the Box2D SDK.
# Tool-only shell; package outputs build only when requested.

{ pkgs, lib, ... }:

let
  mkBox2d = linkage:
    pkgs.callPackage ./package.nix {
      inherit linkage;
      zig = pkgs.zig_0_16;
    };

  # Read for its declared identity only; reading `.version` does not realise it.
  box2dStatic = mkBox2d "static";

  # Resolve this source root without copying the tree into the Nix store.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # Keep build outputs beneath the caller's local cache.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/box2d";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/box2d-prefix";

  # Enter the SDK root and fill only unset Zig cache paths.
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
  # The shell includes tools only; entering it does not build the SDK.
  packages = [
    pkgs.zig_0_16
    pkgs.pkg-config
    pkgs.git
  ];

  # Keep outputs, tasks, scripts and assertions at the module root.
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
    # Fill missing cache paths from XDG_CACHE_HOME or TMPDIR.
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

  # Namespace tasks and run each command from the SDK root.
  # Forward cache, prefix, job and summary options.
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

    # Matrix settings live in cross-test.profile.sh; this task sets concurrency.
    "box2d:matrix" = {
      description = "Run this workspace's full published platform matrix";
      exec = ''
        ${cdSdkRoot}
        cross-test --jobs 8 --build-jobs 8
      '';
    };
  };

  # Scripts run through a shell to support hooks and arguments.
  scripts = {
    # Run the integrity check from the SDK root; its paths are relative.
    "box2d:integrity" = {
      description = "Check every upstream and vendored digest in UPSTREAM.sha256";
      exec = ''
        cd ${sdkRootArg}
        sha256sum -c UPSTREAM.sha256
      '';
    };

    # Keep the consumer build as a separate task.
    "box2d:consumer" = {
      description = "Build and run the separate consumer package";
      exec = ''
        ${cdSdkRoot}
        cd consumer
        zig build run --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };

  # Use path: to evaluate this source tree from any working directory.
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