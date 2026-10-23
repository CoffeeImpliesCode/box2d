  # Nix derivation for Box2D; build.zig owns compilation and installation.

{ lib
, stdenv
, zig
, pkg-config
, linkage ? "static"
}:

assert lib.elem linkage [ "static" "dynamic" ];

  # Without -Dtarget, host and build platforms must match.
assert lib.assertMsg (stdenv.hostPlatform.system == stdenv.buildPlatform.system)
  "box2d/package.nix builds for the build platform; it is given no -Dtarget";

let
  version = "3.1.1";

  # These paths are checked against build.zig's install outputs.
  installedFiles = [
    "include/box2d/base.h"
    "include/box2d/box2d.h"
    "include/box2d/collision.h"
    "include/box2d/id.h"
    "include/box2d/math_functions.h"
    "include/box2d/types.h"
    "lib/pkgconfig/box2d.pc"
    # WASI lacks std::thread in Zig 0.17's C++ runtime, so no benchmark is built there.
    "bin/box2d-benchmark"
  ];

  # Keep this list aligned with build.zig's installed licence records.
  # Includes enkiTS-License.txt; UPSTREAM.sha256 is a repository integrity record.
  licenseFiles = [
    "LICENSE"
    "NOTICE.md"
    "FORK-LICENSE.md"
    "UPSTREAM.md"
    "FORK-NOTES.md"
    "enkiTS-License.txt"
  ];

  # Exclude build output and VCS metadata; retain project and vendored sources.
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _type:
      let name = baseNameOf (toString path);
      in !(builtins.elem name [
        ".git" ".hg" ".svn" ".bzr" ".jj"
        ".zig-cache" "zig-cache" "zig-out" "zig-pkg"
        ".devenv" ".devenv.flake.nix" ".direnv"
        "devenv.lock" "flake.lock" ".envrc.lock"
        "result"
      ] || lib.hasPrefix "result-" name);
  };

  # Artifact names and output directories follow Zig's platform rules.
  # Shared output is versioned (soversion 3.1.1).
  libraryFile =
    if stdenv.hostPlatform.isWindows
    then if linkage == "static" then "lib/box2d.lib" else "bin/box2d.dll"
    else if linkage == "static" then "lib/libbox2d.a"
    else if stdenv.hostPlatform.isDarwin then "lib/libbox2d.dylib"
    else "lib/libbox2d.so";

  # Use one optimize mode, CPU baseline and linkage; other options keep upstream defaults.
  buildFlags = [
    "-Doptimize=ReleaseSafe"
    "-Dcpu=baseline"
    "-Dlinkage=${linkage}"
  ];
in
stdenv.mkDerivation {
  pname = "box2d";
  inherit version;

  # Reuse the filtered source tree declared above.
  inherit src;

  strictDeps = true;
  nativeBuildInputs = [ zig pkg-config ];

  # Disable Zig setup builds; this derivation invokes zig build install directly.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches in the writable build sandbox.
    export ZIG_GLOBAL_CACHE_DIR="''${TMPDIR:-/tmp}/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="''${TMPDIR:-/tmp}/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

    zig build install \
      --prefix "$out" \
      --cache-dir "$ZIG_LOCAL_CACHE_DIR" \
      -j"''${NIX_BUILD_CORES:-1}" \
      --summary all \
      --color off \
      ${lib.concatStringsSep " " buildFlags}

    runHook postInstall
  '';

  # Enable install checks; stdenv disables them by default.
  doInstallCheck = true;

  # Require each declared artifact and licence file to be non-empty.
  installCheckPhase = ''
    runHook preInstallCheck

    for path in "$out/${libraryFile}" ${lib.concatMapStringsSep " " (p: ''"$out/${p}"'') installedFiles}; do
      if [ ! -s "$path" ]; then
        echo "package.nix: expected install output missing or empty: $path" >&2
        exit 1
      fi
    done

    for path in ${lib.concatMapStringsSep " " (p: ''"$out/share/licenses/box2d/${p}"'') licenseFiles}; do
      if [ ! -s "$path" ]; then
        echo "package.nix: licence material missing or empty: $path" >&2
        exit 1
      fi
    done

    # Check the generated pkg-config metadata.
    export PKG_CONFIG_PATH="$out/lib/pkgconfig"
    pkg-config --exists box2d \
      || { echo "package.nix: box2d.pc does not resolve" >&2; exit 1; }
    pkg-config --cflags box2d
    pkg-config --libs box2d
    pkg-config --libs --static box2d

    runHook postInstallCheck
  '';

  passthru = {
    inherit linkage installedFiles licenseFiles;
    upstreamReadme = "README.upstream.md";
    integrityRecord = "UPSTREAM.sha256";
  };

  meta = {
    description = "Box2D, a 2D physics engine for games, as a native library";
    longDescription = ''
      A build of upstream erincatto/box2d at tag v3.1.1, compiled from this
      repository by the SDK's own Zig build graph and installed as a native
      library with its six public headers, its pkg-config metadata and its
      licence record. No simulation result is produced by this package.

      The SDK compiles the full upstream core closure: no CMake, Make or
      autotools target is invoked and nothing is downloaded at build time.

      Upstream Box2D is MIT; upstream's own text is installed unmodified at
      share/licenses/box2d/LICENSE. The installed library itself carries no
      vendored third-party code. The installed benchmark tool does: it links the
      vendored enkiTS task scheduler, which is zlib, and its notice is installed
      at share/licenses/box2d/enkiTS-License.txt. NOTICE.md records the further
      terms that travel with the carried source tree but are outside this output
      — the vendored jsmn and Khronos grants and the Apache-2.0 sample font.
      Fork-authored files are MIT as well (FORK-LICENSE.md).

      The static and shared variants are the same sources and the same build
      graph; only `linkage` differs. Neither is a wholly static closure: each
      links the C runtime its target provides, exactly as `zig build` does.
    '';
    homepage = "https://github.com/erincatto/box2d";
    license = lib.licenses.mit;
    licenseFiles = licenseFiles;
    platforms = lib.platforms.all;
  };
}