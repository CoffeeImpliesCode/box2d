# Source-only Nix derivation for the Box2D SDK.
#
# One derivation; `linkage` selects the variant. `flake.nix` and `devenv.nix`
# both reach this through `pkgs.callPackage`. No sibling import, no fetch, no
# host path, no store path, no `builtins.getEnv`, no `builtins.currentSystem`.
#
# The build graph owns C flags, the source list, the header configuration and
# every installed file. This file calls `zig build install` and checks the
# result. It does not place `include/` or `lib/` by hand and does not duplicate a
# `.pc`, a licence file or a header the graph already installs.
#
#   linkage   "static" (default) or "dynamic". Static is this SDK's policy and
#             upstream's own CMake default: `BUILD_SHARED_LIBS` is unset in
#             upstream's build, and upstream skips its own unit tests when it is
#             on (CMakeLists.txt:101).

{ lib
, stdenv
, zig
, pkg-config
, linkage ? "static"
}:

assert lib.elem linkage [ "static" "dynamic" ];

# `zig build` is invoked with no `-Dtarget`, so it resolves the build machine.
# A cross stdenv would install the builder's native library under the host's
# name. The guard compares platforms rather than naming a system, so an ordinary
# remote builder — where host and build agree — stays valid.
assert lib.assertMsg (stdenv.hostPlatform.system == stdenv.buildPlatform.system)
  "box2d/package.nix builds for the build platform; it is given no -Dtarget";

let
  version = "3.1.1";

  # One writer per path: `build.zig` installs these. The list is the contract
  # `installCheckPhase` enforces, not a second copy of the install step.
  installedFiles = [
    "include/box2d/base.h"
    "include/box2d/box2d.h"
    "include/box2d/collision.h"
    "include/box2d/id.h"
    "include/box2d/math_functions.h"
    "include/box2d/types.h"
    "lib/pkgconfig/box2d.pc"
    # Installed in every linkage and optimize mode on every non-WASI target.
    # wasm32-wasi is the one exception: extern/enkiTS/src/TaskScheduler.h:22
    # includes <thread>, which Zig 0.16's WASI C++ library has none of. This
    # derivation's stdenv is never wasm32-wasi (package.nix refuses a cross
    # stdenv, and every entry point offers only Linux and Darwin systems), so
    # the assertion below cannot meet that case.
    "bin/box2d-benchmark"
  ];

  # `meta.licenseFiles` and the installed licence record are the same list, and
  # that list is what `build.zig` installs: `licence_records` is five entries
  # (build.zig:559-565) and `installLicenceRecords` adds the enkiTS grant below
  # through its own `getInstallStep().dependOn` (build.zig:1448-1463), so six
  # files, unconditionally, in every linkage and optimize mode. Naming five
  # here under-checks the sixth instead of failing on it, which is the worse
  # failure for a gate whose only job is to notice a licence text that did not
  # install.
  # `enkiTS-License.txt` is the vendored task scheduler's own zlib notice:
  # `bin/box2d-benchmark` links it, and enkiTS's third condition is that its
  # notice may not be removed from a source distribution.
  # `UPSTREAM.sha256` is deliberately not in this list: it is a repository
  # integrity record, not material that ships with a library.
  licenseFiles = [
    "LICENSE"
    "NOTICE.md"
    "FORK-LICENSE.md"
    "UPSTREAM.md"
    "FORK-NOTES.md"
    "enkiTS-License.txt"
  ];

  # Build output, version-control metadata and development state. Everything
  # else stays: the whole native core, upstream's tests, its docs, its samples,
  # the vendored `extern/` trees including enkiTS, its benchmark data and every
  # licence file.
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

  # The installed library's name and directory are the compiler's own rules, not
  # this file's guesses: std/zig.zig:binNameAlloc spells a coff target
  # `box2d.lib` or `box2d.dll`, an elf one `libbox2d.a` or `libbox2d.so`, a
  # macho one `libbox2d.a` or `libbox2d.dylib`, and
  # std/Build/Step/InstallArtifact.zig:100-141 installs a DLL under bin/ and
  # every other library under lib/. The shared build here is versioned
  # (`soversion` 3.1.1), so the unversioned name is the symlink written beside
  # the versioned file, which std.Build.wantSharedLibSymLinks (std/Build.zig:
  # 2717) keeps everywhere off Windows.
  libraryFile =
    if stdenv.hostPlatform.isWindows
    then if linkage == "static" then "lib/box2d.lib" else "bin/box2d.dll"
    else if linkage == "static" then "lib/libbox2d.a"
    else if stdenv.hostPlatform.isDarwin then "lib/libbox2d.dylib"
    else "lib/libbox2d.so";

  # One optimize selection, one CPU baseline, one linkage. Optional native
  # settings are left at upstream's own defaults rather than enabled here:
  # validation on, SIMD on, AVX2 off, runtime dispatch off. A let binding and
  # not an attribute of the derivation: installPhase is an interpolated string
  # and a derivation attribute set is not recursive.
  buildFlags = [
    "-Doptimize=ReleaseSafe"
    "-Dcpu=baseline"
    "-Dlinkage=${linkage}"
  ];
in
stdenv.mkDerivation {
  pname = "box2d";
  inherit version;

  # The tree `unpackPhase` copies. Bound with the other bindings above so the
  # filter is stated once, here next to the `linkage` selection and the install
  # contract; `inherit` is the same wiring `box3d`, `lua`, `pcre2`, `predicates`,
  # `blake3` and `utf8proc` use. Without it the derivation reaches `unpackPhase`
  # with no source at all and stops at "variable $src or $srcs should point to
  # the source".
  inherit src;

  strictDeps = true;
  nativeBuildInputs = [ zig pkg-config ];

  # Every phase of the Zig setup hook is replaced by the install and installCheck
  # phases below, so none of its own builds can run first with default flags.
  # `dontConfigure` also keeps the global Zig cache out of the unpacked source.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;

  installPhase = ''
    runHook preInstall

    # Both caches live in the sandbox's writable TMPDIR, never in the source
    # tree and never on a small system temporary filesystem.
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

  # `installCheckPhase` is not run unless this is true: stdenv defines
  # `doInstallCheck ? doCheckByDefault`, and no stdenv here sets
  # `doCheckByDefault`, so the default is false and the phase below would never
  # execute. `spglib`, `luajit` and `libunibreak` say the same thing explicitly
  # for the same reason.
  doInstallCheck = true;

  # A partial install must fail here rather than publish an output missing a
  # public header, the link metadata or a licence text.
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

    # Resolve the metadata the graph wrote rather than trusting it.
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