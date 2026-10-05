// SPDX-License-Identifier: MIT

//! Zig 0.16 build for the Box2D 2D physics engine.
//!
//! The library is upstream's own C, byte for byte: the 35 translation units of
//! `src/CMakeLists.txt`'s `BOX2D_SOURCE_FILES` and the six public headers of its
//! `BOX2D_API_FILES`, nothing else. Nothing is downloaded, no CMake, Make or
//! FetchContent script is executed, and there is no system-library mode, so
//! every build compiles the sources in this repository.
//!
//! The one thing compiled beside them that upstream does not ship is
//! `build_support/box2d_inline_bridge.c`, one translation unit of this fork's
//! that adds no algorithm: it gives `b2MakeAABB` the linkable definition
//! `include/box2d/math_functions.h:625` declares `B2_INLINE` and therefore
//! never emits, by renaming that name around one `#include` and calling the
//! body the header's own text defined. No upstream file is edited to
//! accommodate it and none of the 35 differs by a byte; `UPSTREAM.sha256`
//! still passes unchanged. It is described where it is written and, for why
//! the translated facade needs it, in the `bridge_dir` declaration below.
//!
//! Upstream reference: tag `v3.1.1`, `CMakeLists.txt:5-10`
//! (`project(box2d VERSION 3.1.1 DESCRIPTION "A 2D physics engine for games" ...)`)
//! and `src/core.c:69-77`, where `b2GetVersion` returns `{3, 1, 1}`. The pinned
//! commit SHA belongs in `UPSTREAM.md`, which the fork's provenance owner
//! writes from `git log`; this script does not restate a SHA it cannot read.
//!
//! Entry points
//! -----------
//!   zig build            install the compiled C library, the six public
//!                        headers, the pkg-config metadata, the licence and
//!                        provenance records, and the benchmark tool, and
//!                        compile the example program
//!   zig build test       run this fork's Zig tests and upstream's own
//!                        `test/main.c` suite, for the selected target
//!                        (`-Dtarget`; the host when it is absent)
//!   zig build smoke      run the example program
//!   zig build upstream-test
//!                        build and run upstream's own unmodified `test/main.c`
//!                        suite on its own, which is the entry point upstream's
//!                        own CI executes as `./bin/test`
//!   zig build benchmark  build upstream's `benchmark/main.c` tool
//!   zig build consumer   build the separate `consumer/` package, which reaches
//!                        this one through `dep.module("box2d")`, and run it
//!                        when this host can execute the selected target
//!   zig build check      compile the C core, the facade, `tests.zig`,
//!                        `smoke.zig`, upstream's own C suite and the benchmark
//!                        tool for the six-target matrix, running nothing
//!
//!   cross-test           the same `test` step, for the published 53-platform
//!                   Zig 0.16.0 Tier 1/2 table rather than the host alone.
//!                   `cross-test` discovers `cross-test.profile.sh` from the
//!                   package root, runs `zig build test -Dtarget=TARGET` for
//!                   each of them, and executes the binary where a runner
//!                   exists and records explicit `build_only` coverage where
//!                   one does not. `test` is what the harness reaches for, and
//!                   it builds the same graph and the same binaries for
//!                   whatever `-Dtarget` says: nothing in `build()` narrows the
//!                   graph to the host, and the `check` matrix below is
//!                   compile-only and is not a substitute for it.
//!
//! Options
//! -------
//!   -Dlinkage=static|dynamic
//!                      `static` is the default and is what this package has
//!                      always produced: upstream leaves `BUILD_SHARED_LIBS`
//!                      unset, and `CMakeLists.txt:101` only adds the unit
//!                      tests when `NOT BUILD_SHARED_LIBS`, so the default graph
//!                      is the one in which upstream's own test entry exists.
//!                      `dynamic` builds a real shared object with upstream's
//!                      soname; see "Static and shared delivery" below.
//!   -Druntime=true     resolve the native entry points at run time instead of
//!                      linking them. The facade keeps the same translated
//!                      header and the same public types; each selected native
//!                      function becomes a dispatch through one
//!                      process-lifetime table an explicit `load(source)`
//!                      fills, and the module links no archive. Orthogonal to
//!                      `-Dlinkage`, which still decides which artifact this
//!                      build delivers and installs. Default off, and a linked
//!                      build is unchanged in every respect.
//!   -Dvalidate=true|false
//!                      upstream's `option(BOX2D_VALIDATE "Enable heavy
//!                      validation" ON)` at `CMakeLists.txt:66`. Default `true`,
//!                      which is what upstream's own CI configures
//!                      (`.github/workflows/build.yml` passes
//!                      `-DBOX2D_VALIDATE=ON` on every job). It is a private
//!                      define on the library's own compile line
//!                      (`src/CMakeLists.txt:119-122`) and changes no public
//!                      header, so the translation is the same either way.
//!   -Ddisable-simd=true|false
//!                      upstream's `option(BOX2D_DISABLE_SIMD "Disable SIMD
//!                      math (slower)" OFF)` at `CMakeLists.txt:43`. Default
//!                      `false`. `src/core.h:59` is its only reader.
//!   -Davx2=true|false  upstream's `BOX2D_AVX2`, default `OFF`
//!                      (`CMakeLists.txt:47`, `cmake_dependent_option` with the
//!                      condition `NOT BOX2D_DISABLE_SIMD` and the processor
//!                      test `MATCHES "x86_64|AMD64"`). Accepted on any target;
//!                      applied only where upstream would apply it, and
//!                      `build` prints on its configure line when a request is
//!                      not applied and why.
//!   -Dtarget=<triple>, -Doptimize=<mode>, -Dcpu=<model>
//!                      standard. `-Dcpu` is registered by
//!                      `b.standardTargetOptions`, which is what `package.nix`
//!                      relies on when it passes `-Dcpu=baseline`.
//!
//! Options upstream has that this package deliberately does not offer
//! ----------------------------------------------------------------
//!   * `BOX2D_SAMPLES` (`CMakeLists.txt:62`), default `ON`. The samples are a
//!     GLFW + OpenGL + imgui + glad application. This SDK has no graphical
//!     requirement and no download, so they are not built, not installed and
//!     not an option. `extern/glad` and `extern/jsmn` stay in the tree because
//!     they are upstream's own sources, and neither is compiled here.
//!   * `BOX2D_PROFILE` (`CMakeLists.txt:65`), default `OFF`. It `FetchContent`s
//!     Tracy and links `TracyClient` (`src/CMakeLists.txt:104-117`). A source
//!     build that downloads a profiler is not a source build, so the macro is
//!     not defined and `src/core.h`'s `BOX2D_PROFILE` branch is never taken.
//!   * `BOX2D_SANITIZE` (`CMakeLists.txt:22`), MSVC and Apple only. It is a
//!     choice of compiler flags for a debug build, not a delivery option.
//!   * `BOX2D_COMPILE_WARNING_AS_ERROR` (`CMakeLists.txt:44`), default `OFF`.
//!     This build never adds `-Werror`, so the option has nothing to switch.
//!   * `BOX2D_DOCS`, `BOX2D_BENCHMARKS` and `BOX2D_UNIT_TESTS`
//!     (`CMakeLists.txt:63-65`). The unit tests and the benchmark are always
//!     built here, and the docs are Doxygen targets for upstream's website.
//!   * `BUILD_SHARED_LIBS`, which is what `-Dlinkage` replaces.
//!   * System-library mode. This package has none, by contract: it would have
//!     to translate a system `box2d/*.h` of unknown version against the
//!     library it links, which is the header/ABI mismatch `WISDOM.md` W14
//!     forbids. The rule is recorded as NOT APPLICABLE rather than claimed as
//!     a satisfied gate, and there is no `b.systemIntegrationOption` call: an
//!     unused option is a knob nobody has checked, and a mode that cannot be
//!     entered is better named in this comment than half-built behind a flag.
//!
//! Static and shared delivery
//! -------------------------
//! `-Dlinkage` selects which artifact this package produces, and the default
//! is upstream's. Nothing about the compiled C changes between the two: the
//! same 35 sources, the same macros, the same language level, the same
//! deterministic flags. The option selects the *delivery*, never the dispatch.
//!
//! `dynamic` is a real shared object, which takes four things this build would
//! otherwise not do.
//!
//!   * **A soname, and it is upstream's.** `src/CMakeLists.txt:91-98` sets
//!     `VERSION ${PROJECT_VERSION}` to 3.1.1 and `SOVERSION ${PROJECT_VERSION_MAJOR}`
//!     to 3, and `b.addLibrary`'s `version` field is what
//!     `std/Build/Step/Compile.zig:492-506` turns into that shape:
//!     `libbox2d.so.3.1.1` with `libbox2d.so.3` and `libbox2d.so` beside it on
//!     ELF, `libbox2d.3.1.1.dylib` with `libbox2d.3.dylib` and `libbox2d.dylib`
//!     on Darwin (`Compile.zig:493-497`, install name `@rpath/...` at
//!     `:1497-1500`), and `box2d.dll` with its import library `box2d.lib` on
//!     Windows, where `std.Build.wantSharedLibSymLinks` is false
//!     (`lib/std/Build.zig:2717-2719`). The soname — the number a consumer's
//!     `DT_NEEDED` records and the string a `.system` load has to name — is
//!     `libbox2d.so.3` either way.
//!   * **Position independence.** The module carrying the 35 core translation
//!     units is PIC when the delivered artifact is a shared object. Nothing
//!     about the static, non-shared case changes.
//!   * **An export surface.** `src/CMakeLists.txt:72-75` sets
//!     `CMAKE_C_VISIBILITY_PRESET hidden` and
//!     `CMAKE_VISIBILITY_INLINES_HIDDEN 1`, and
//!     `include/box2d/base.h:11-23` is the only thing that widens it again: no
//!     declaration in upstream's tree uses `B2_API` except the six public
//!     headers (`grep -c B2_API src/*.h src/*.c` is zero), so the exported set
//!     is exactly the public interface. This build passes `-fvisibility=hidden`
//!     for the same reason on every linkage, which needs no version script and
//!     no hand-written export list, and defines `box2d_EXPORTS` on the shared
//!     build so `base.h:17-19` resolves `B2_API` to
//!     `__attribute__((visibility("default")))` on GCC and Clang.
//!   * **The DLL macros, split the way upstream splits them.**
//!     `base.h:11-16` reads `box2d_EXPORTS` (lowercase: CMake's per-target
//!     define symbol for a target called `box2d`) with `_MSC_VER` to choose
//!     `__declspec(dllexport)` over `__declspec(dllimport)`, and
//!     `src/CMakeLists.txt:131-133` sets `BOX2D_DLL` `INTERFACE` under
//!     `if (MSVC AND BUILD_SHARED_LIBS)`. This build does the same:
//!     `box2d_EXPORTS` on the shared build's own compile line, `BOX2D_DLL`
//!     alone on the translation and on the module, and both only where they
//!     are read — `BOX2D_DLL` needs a Windows target, because the `_MSC_VER`
//!     guard is what makes every other platform ignore both. The installed
//!     `box2d.pc` carries `-DBOX2D_DLL` in `Cflags` for a shared install. A
//!     static build defines none of them, which is why `base.h:22-23` leaves
//!     `B2_API` empty there, and why MinGW shared builds correctly take the
//!     visibility attribute: `_MSC_VER` is not defined under MinGW.
//!
//! One target boundary belongs here rather than only in the code, and it is a
//! refusal rather than a substitution. WASI has no dynamic linker —
//! `std.Target.DynamicLinker.kind` is `.none` for it
//! (`lib/std/Target.zig:2345-2402`) — so it cannot carry a shared object, and a
//! `.so` there is a file nothing can load. `-Dlinkage=dynamic` therefore
//! *fails* on such a target instead of quietly producing a static archive:
//! `targetCanCarry` answers the question, `addTargetCheck` leaves that one
//! matrix target out of a dynamic `check` and says so by name, and a
//! `-Dtarget` naming an unsupported platform is rejected outright by
//! `rejectUnsupportedLinkage`. A caller who asked for a shared object and
//! receives an archive has been given something else, and the artifact the
//! package installs has to be the one the option names.
//!
//! The default is unaffected: `zig build` with no `-Dtarget` and no
//! `-Dlinkage` is a static build on the host, and `zig build check` with no
//! options still walks all six matrix targets, WASI included. The distinction
//! is between the *default* static linkage, which WASI carries as well as any
//! other target does, and a *requested* dynamic one, which it cannot.
//!
//! The C++ tools
//! -------------
//! Two of the things this package builds are C and reach an external task
//! system rather than Box2D:
//!
//!   * upstream's own unit tests, `test/main.c`. `test/CMakeLists.txt:32` links
//!     `box2d shared enkiTS`, and `test/test_determinism.c:4` includes
//!     enkiTS's `TaskScheduler_c.h` for the multithreading subtest. Box2D
//!     itself never requires a thread library: `b2WorldDef` takes the caller's
//!     `enqueueTask`/`finishTask` callbacks and `workerCount`
//!     (`include/box2d/types.h:35-38`), which is why the 35 core sources and
//!     the six public headers need no C++ and no threads at all.
//!   * upstream's `benchmark/main.c`, which reaches the same two files
//!     (`benchmark/main.c:8-9`) and is non-graphical, unlike the samples.
//!
//! enkiTS is a real third-party dependency that upstream fetches at build time
//! (`CMakeLists.txt:86-95`, `FetchContent_Declare(enkits ... GIT_TAG master)`),
//! which a source build must not do. This package therefore compiles the
//! vendored tree in `extern/enkiTS` — `src/TaskScheduler.cpp` and
//! `src/TaskScheduler_c.cpp`, the whole C++ closure behind the C bridge — into
//! a static `libenkits.a` at `-std=c++11` (`extern/enkiTS/CMakeLists.txt:99`
//! and its own `build.zig:85`), with libc++ and the platform's POSIX thread
//! library. Its bytes, its `License.txt` and its header guards are untouched.
//!
//! That closure is the one place in this package where a target boundary
//! appears a second time. `extern/enkiTS/src/TaskScheduler.h:22` includes
//! `<thread>`, and Zig 0.16's `wasm32-wasi` C++ library has no threads, so for
//! a WASI target `addEnkiTS` returns null and the upstream suite and the
//! benchmark tool are not compiled for it. `build` and `addTargetCheck` print
//! exactly that, so the target is never silently narrowed; every other
//! artifact in this package — the 35-file core, the six headers, the
//! translation, the facade, `tests.zig` and `smoke.zig` — is still compiled
//! for `wasm32-wasi`.
//!
//! Installed closure
//! -----------------
//! `zig build` installs, in this order of interest to a consumer:
//!
//!   * the native library, through `b.installArtifact`. `libbox2d.a`, or the
//!     shared object described above.
//!   * the six public headers into `include/box2d/`, through the
//!     `installHeader` call in `addCoreLibrary`. That is upstream's own
//!     installed set and layout (`src/CMakeLists.txt:208-211`, into
//!     `${CMAKE_INSTALL_INCLUDEDIR}/box2d`), and `src/CMakeLists.txt:81-85`
//!     puts the install include directory on the interface, so a consumer
//!     writes `#include <box2d/box2d.h>`. Installing a header also puts it on
//!     the include path of anything that links this artifact, so a C consumer
//!     of the installed archive needs nothing from this tree.
//!   * `lib/pkgconfig/box2d.pc`, generated by `addPkgConfig`.
//!   * `share/licenses/box2d/` with `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`,
//!     `UPSTREAM.md`, `FORK-NOTES.md` and `enkiTS-License.txt`, through
//!     `installLicenceRecords`. A private repository removes no licence
//!     obligation, and a package that ships a binary without them is the
//!     failure this prevents.
//!   * `bin/box2d-benchmark`, upstream's own benchmark tool. It is the one
//!     useful native program in this package that is not graphical; the
//!     samples are the other candidate and need GLFW, OpenGL, imgui and glad.
//!
//! No data is installed: upstream's `samples/data/` is font and image material
//! for a graphical application this package does not build.
//!
//! One upstream install rule is deliberately not reproduced. `src/CMakeLists.txt:202-223`
//! generates and installs `lib/cmake/box2d/box2dConfig.cmake` and
//! `box2dConfigVersion.cmake` through `install(EXPORT)`. Those files are a CMake
//! target export, not link metadata, and hand-writing them would be a second
//! packaging dialect this package would then have to keep correct. The
//! pkg-config file above is the relocatable link metadata this package
//! delivers. `FORK-NOTES.md` records the difference.
//!
//! Published routes
//! ----------------
//! This package publishes the routes below, and one name it deliberately does
//! not publish:
//!
//!   * `dep.module("box2d")`: the Zig facade, `zig/root.zig`. This is the one
//!     registered module. It carries `link_libc`, the translated header as
//!     `c`, and the library behind it, so a dependent that adds this module
//!     needs nothing further to call the facade or to reach `box2d.h`.
//!   * `box2d.c` on that same module: the translated header itself, for a
//!     caller that needs a declaration the facade does not name. It is
//!     deliberately *not* registered as a module of its own: `addModule("c")`
//!     would make `dep.module("c")` resolve and hand over the same
//!     declarations without the library that satisfies them, which is a
//!     reachability a dependent cannot tell from support.
//!   * `dep.artifact("box2d")`: the compiled native library, in whichever
//!     `-Dlinkage` selected. This is the C-ABI route for a dependent that
//!     links the library into its own C or Zig build.
//!   * the installed `box2d.pc` and `share/licenses/box2d/`, which make a C
//!     consumer a package rather than a source drop.
//!
//! `README.zig.md` states the same routes for a reader deciding what to import,
//! and `zig/root.zig` states the Zig one on the module itself.

const std = @import("std");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it makes the loader-core
/// module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch,
/// where there is no dispatch and the facade's `rt` import is where those two
/// public types come from.
///
/// The two branches must not both call `createCoreModule`. `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the *same*
/// types in one build: a second core instance would be a second, nominally
/// distinct `LoadSource`, and `box2d.load(source)` would be handing the
/// facade's type to a function expecting the dispatch's. `addGraph` documents
/// the branch and is the only function that calls either of these.
const runtime_graph = @import("runtime/graph.zig");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it.
const manifest = @import("build.zig.zon");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest
/// whose `.version` is not a semantic version fails to configure here rather
/// than being silently compared as something else.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Package id, published module name, and name of the C artifact.
///
/// One string for all three is right here: `std.zig.system` prepends the
/// platform `lib` prefix to a library artifact's own name
/// (`lib/std/zig.zig:156`), so the emitted archive is exactly upstream's
/// `libbox2d.a`, which is what an installed C consumer's `-lbox2d` needs.
const module_name = "box2d";
const lib_name = "box2d";

/// The Zig facade: a typed wrapper over the translated `b2*` calls. The API
/// role owns it. It re-exports the translated module as `c`.
const facade_source = "zig/root.zig";

/// The one header this package translates: a fork-authored aggregate whose
/// whole job is to name the six headers upstream installs.
const translate_header = "zig/translate.h";

/// Test root, owned by the API role. `zig/root.zig` names the test blocks; a
/// root that only re-exported them would discover no tests and still exit
/// zero.
const test_source = "tests.zig";

/// The deterministic example program that `zig build smoke` runs.
const example_source = "smoke.zig";

/// Upstream's own version, read out of `CMakeLists.txt:6`
/// (`project(box2d VERSION 3.1.1 ...)`) and out of `src/core.c:69-77`, where
/// `b2GetVersion` returns `{3, 1, 1}`.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 1, .patch = 1 };

/// Upstream's `VERSION 3.1.1` / `SOVERSION 3` (`src/CMakeLists.txt:95-97`).
///
/// Both components, because `addLibrary`'s `version` is one field and the
/// pair is what `Compile.zig:492-506` expands into the versioned file name
/// and the soname. `.major` is the soname number, which is what a `.system`
/// load has to name on ELF.
const soversion: std.SemanticVersion = .{ .major = 3, .minor = 1, .patch = 1 };

/// The core sources: the `.c` entries of `BOX2D_SOURCE_FILES`
/// (`src/CMakeLists.txt:3-61`), in upstream's order.
///
/// Thirty-five translation units. The list is worth stating rather than
/// globbing: the 24 `.h` entries in the same CMake variable are headers, not
/// translation units, and `src/CMakeLists.txt:189` uses the variable only to
/// build an IDE source group — `add_library(box2d ...)` is handed the whole
/// variable, so a file that is absent from it would silently not be compiled.
/// Naming them makes the count a fact a reader can check against
/// `BOX2D_SOURCE_FILES`, and it makes a future upstream source an error here
/// rather than a silently smaller library.
const core_sources = [_][]const u8{
    "aabb.c",
    "arena_allocator.c",
    "array.c",
    "bitset.c",
    "body.c",
    "broad_phase.c",
    "constraint_graph.c",
    "contact.c",
    "contact_solver.c",
    "core.c",
    "distance.c",
    "distance_joint.c",
    "dynamic_tree.c",
    "geometry.c",
    "hull.c",
    "id_pool.c",
    "island.c",
    "joint.c",
    "manifold.c",
    "math_functions.c",
    "motor_joint.c",
    "mouse_joint.c",
    "mover.c",
    "prismatic_joint.c",
    "revolute_joint.c",
    "sensor.c",
    "shape.c",
    "solver.c",
    "solver_set.c",
    "table.c",
    "timer.c",
    "types.c",
    "weld_joint.c",
    "wheel_joint.c",
    "world.c",
};

/// Upstream's `BOX2D_API_FILES` (`src/CMakeLists.txt:63-70`): the six headers
/// upstream installs, which are the six this package installs and the six
/// `zig/translate.h` names.
///
/// The internal headers in `src/` are not here and are not installed, because
/// upstream installs none of them. They are on the compile line of the core,
/// of upstream's own test target — `test/CMakeLists.txt:29-30` adds
/// `${CMAKE_SOURCE_DIR}/src` for exactly this, and `test/test_table.c:4-7`
/// includes `atomic.h`, `core.h`, `ctz.h` and `table.h` directly — and of the
/// benchmark tool.
const public_headers = [_][]const u8{
    "include/box2d/base.h",
    "include/box2d/box2d.h",
    "include/box2d/collision.h",
    "include/box2d/id.h",
    "include/box2d/math_functions.h",
    "include/box2d/types.h",
};

/// The directory that holds the six public headers, and the include path every
/// C compilation, every translation and the installed interface get.
///
/// `src/*.c` reaches its own headers by quoted include relative to `src/`, but
/// every translation unit also spells its public headers `box2d/box2d.h`, and
/// the installed interface is `${CMAKE_INSTALL_INCLUDEDIR}` with the headers
/// one directory below it (`src/CMakeLists.txt:81-85`). So the path here is
/// `include`, not `include/box2d`: a consumer that writes
/// `#include <box2d/box2d.h>` against this package's install must find it, and
/// one that writes `#include <base.h>` must not.
const include_dir = "include";

/// The core source directory, and the *private* include path of everything
/// that reaches Box2D internals: the core itself, upstream's test target
/// (`test/CMakeLists.txt:30`) and the benchmark tool.
const source_dir = "src";

/// This fork's own C, compiled into the core library beside upstream's 35.
///
/// One file today. `build_support/box2d_inline_bridge.c` exists because
/// `include/box2d/math_functions.h:625` declares `b2MakeAABB` as `B2_INLINE`,
/// which `include/box2d/base.h:33` makes `static inline`: every translation
/// unit that includes the header gets a private copy and no symbol enters the
/// archive. Upstream is served by that -- `src/world.c:2159` is its only
/// caller. `zig build` is not. The six public headers declare 73 `B2_INLINE`
/// functions between them, 63 in `math_functions.h` and 10 in `id.h`, and
/// `translate-c` compiles the bodies of 72 of them into the `c` module
/// `zig/root.zig` imports. It cannot compile the remaining one, because that
/// body opens with `B2_ASSERT( count > 0 )` (`math_functions.h:627`), which
/// reaches `__builtin_trap()` at `base.h:94`. The translation reports
/// `unable to translate function, demoted to extern` and emits
/// `pub extern fn b2MakeAABB(...)` instead, a declaration of a C symbol the
/// archive does not contain -- so every Zig caller of `box2d.c.b2MakeAABB`,
/// including this package's own `box2d.makeAabb`, is an undefined symbol at
/// link time.
///
/// That one function is the whole of the gap. One demoted extern is the
/// complete list `zig/translate.h` produces at this pin, and every other
/// `extern` in it is a `B2_API` declaration one of the 35 upstream translation
/// units already defines, which is why the linker reports this name and no
/// other.
///
/// It is a source in this directory and not a separate bridge library because
/// it has to *be* the core for the symbol to exist in every configuration: the
/// static archive, the shared object, and the second static archive
/// `addGraph` builds for upstream's own test suite when `-Dlinkage=dynamic`
/// asked for the shared one. A library of its own would be a second
/// configuration that could disagree with the first about macros, flags,
/// `-fvisibility=hidden` and `box2d_EXPORTS`, and a symbol that is present in
/// one linkage and absent in another is worse than the hole it fills.
///
/// Nothing upstream is pinned here and nothing is fetched: `FORK-LICENSE.md`
/// already scopes `build_support/` to this fork's grant, `UPSTREAM.sha256`
/// already names the directory as fork-authored so a file added to it moves no
/// digest, and `package.nix:73-74` filters `./.` whole so the Nix derivation
/// carries the directory without a list edit. `build.zig.zon` `.paths` is the
/// one list in this package that names entries individually rather than
/// carrying a directory, so `build_support` belongs in it for the same reason
/// `zig` and `runtime` are there: a dependent that fetches this package has to
/// receive a tree that still builds.
const bridge_dir = "build_support";

/// The fork's C sources in `bridge_dir`. A list rather than a bare
/// `addCSourceFile` so that a second one is one added line here, under the one
/// module and the one flag set, and not a second configuration.
const bridge_sources = [_][]const u8{
    "box2d_inline_bridge.c",
};

/// Upstream's `shared` support library (`shared/CMakeLists.txt:3-12`): the code
/// the samples, the benchmarks and the unit tests share. It is a `STATIC`
/// library in upstream's own build and is not installed.
const support_sources = [_][]const u8{
    "benchmarks.c",
    "determinism.c",
    "human.c",
    "random.c",
};
const support_dir = "shared";

/// Upstream's own unit test suite, `BOX2D_TEST_FILES`
/// (`test/CMakeLists.txt:3-15`), unmodified. `main.c` is the entry point:
/// `test/main.c:53-61` runs the nine suites through `RUN_TEST` and
/// `test/main.c:73` returns 0 only when every one of them did, which is the
/// exit status upstream's own CI checks as `./bin/test`.
const upstream_test_sources = [_][]const u8{
    "main.c",
    "test_bitset.c",
    "test_collision.c",
    "test_determinism.c",
    "test_distance.c",
    "test_id.c",
    "test_math.c",
    "test_shape.c",
    "test_table.c",
    "test_world.c",
};
const test_dir = "test";

/// Upstream's benchmark tool, `BOX2D_BENCHMARK_FILES`
/// (`benchmark/CMakeLists.txt:3-7`). One file, non-graphical, and the reason
/// `benchmark` is a separate step rather than part of the default build.
const benchmark_source = "benchmark/main.c";

/// The vendored enkiTS C++ closure: the task scheduler implementation and the
/// C bridge over it. `extern/enkiTS/src/TaskScheduler_c.cpp:19-20` includes
/// `TaskScheduler_c.h` and `TaskScheduler.h`, and `TaskScheduler.cpp:19-20`
/// includes `TaskScheduler.h` and `LockLessMultiReadPipe.h`; those two `.cpp`
/// files are therefore the whole compile closure, and `TaskScheduler.h:21-24`
/// and `LockLessMultiReadPipe.h:21-26` are the whole include closure.
///
/// Compiled unmodified at the language level enkiTS's own two build files
/// agree on: `-std=c++11` (`extern/enkiTS/CMakeLists.txt:99` and
/// `extern/enkiTS/build.zig:85`).
const enki_source_dir = "extern/enkiTS/src";
const enki_sources = [_][]const u8{
    "TaskScheduler.cpp",
    "TaskScheduler_c.cpp",
};

/// The carried licence and provenance material `zig build` installs under
/// `share/licenses/box2d/`.
///
/// `LICENSE` is upstream's own MIT text, installed unmodified and not
/// rewritten, and it covers the whole compiled library. `NOTICE.md`,
/// `FORK-LICENSE.md`, `UPSTREAM.md` and `FORK-NOTES.md` are this fork's
/// records and are the provenance role's files. `UPSTREAM.sha256` is not
/// installed: it describes this working tree's upstream bytes and is an
/// integrity record for this repository, not material that ships with a
/// binary.
const licence_records = [_][]const u8{
    "LICENSE",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "FORK-NOTES.md",
};

/// enkiTS's own grant, and the name it installs under.
///
/// enkiTS is zlib-licensed: `extern/enkiTS/License.txt`, "Copyright (c) 2013
/// Doug Binks", three conditions, the same text as the in-file comment header
/// on all four files under `extern/enkiTS/src/`. Its third condition is that
/// the notice may not be removed from a source distribution, and
/// `libenkits.a` is linked into `bin/box2d-benchmark`, so that notice travels
/// with the output. It is renamed on the way so that it is unambiguous whose
/// grant it is, sitting beside Box2D's own MIT `LICENSE` rather than beside a
/// second file also called `License.txt`.
const enki_licence = "extern/enkiTS/License.txt";
const enki_licence_dest = "enkiTS-License.txt";

/// The cross-compilation matrix `check` walks when no target is named. The
/// order is the one this workspace uses everywhere; nothing is skipped, and
/// nothing here is pre-judged: if a target cannot be satisfied on the machine
/// running the gate, that is for the gate to report.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// One target's library and facade.
const Graph = struct {
    /// The compiled C library in the linkage `-Dlinkage` selected. This is the
    /// artifact this package delivers and installs.
    c_lib: *std.Build.Step.Compile,
    /// A static core, which is `c_lib` itself when the requested linkage is
    /// already static. Upstream's unit tests link the static library only —
    /// `CMakeLists.txt:101` does not even add them otherwise — because
    /// `test/test_table.c` calls internal functions that a shared build hides.
    /// It is the same 35 sources and the same flags either way.
    static_lib: *std.Build.Step.Compile,
    /// The facade module, with `c` bound to the translated headers for the
    /// library this graph compiled.
    module: *std.Build.Module,
    /// The translated headers, shared by the facade and by the upstream C
    /// tools so all of them describe exactly one C ABI in a graph.
    c_module: *std.Build.Module,
};

/// The C++ and support targets upstream's own test entry and its benchmark
/// link, per `test/CMakeLists.txt:32` and `benchmark/CMakeLists.txt:18`.
const Tools = struct {
    /// `libenkits.a`, or null for a target whose C++ library has no threads.
    enki: ?*std.Build.Step.Compile,
    /// The static `shared` support library.
    support: *std.Build.Step.Compile,
};

/// Everything one configuration decided, so the functions that consume it do
/// not each re-read a `-D` option.
const Options = struct {
    /// The linkage the caller asked for.
    requested_linkage: std.builtin.LinkMode,
    /// upstream's `BOX2D_VALIDATE`, default ON.
    validate: bool,
    /// upstream's `BOX2D_DISABLE_SIMD`, default OFF.
    disable_simd: bool,
    /// upstream's `BOX2D_AVX2`, default OFF.
    avx2: bool,
    /// Whether `-Druntime` selected the loaded dispatch.
    runtime_loaded: bool,
};

/// The name a compiled artifact carries in this build graph.
///
/// The published graph installs `libbox2d.a`, the name an installed C
/// consumer's `-lbox2d` needs. A check graph installs nothing, so its artifacts
/// carry the target triple instead: six targets share one build graph, and six
/// steps all called "box2d" make `--summary all` impossible to read.
fn artifactName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Whether this target can carry the shared object a dynamic `-Dlinkage`
/// asks for.
///
/// Windows loads PE/COFF DLLs without an interpreter path. For other targets,
/// `std.Target.DynamicLinker.kind` identifies the dynamic linker.
/// WASI has neither form of shared-library loading.
///
/// It gates a refusal and nothing else. There is deliberately no second return
/// value that would let a caller substitute another linkage: `deliveredLinkage`
/// used to be that function, it silently turned a requested shared object into
/// a static archive on WASI, and a caller who passed `-Dlinkage=dynamic` got
/// back a package whose own `box2d.pc` described an artifact nobody asked for.
/// The option names the artifact, and the graph either produces that artifact
/// or says it cannot.
fn targetCanCarry(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) bool {
    return requested == .static or target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// The exact reason `-Dlinkage=dynamic` cannot be honoured for `target`.
///
/// One message, so the refusal a caller reads for one target is the refusal
/// they would read for any other, and so `addTargetCheck` and `build` cannot
/// describe the same boundary two different ways.
fn unsupportedLinkageReason(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) []const u8 {
    return b.fmt(
        "box2d: -Dlinkage=dynamic cannot be honoured for {s}: that OS has no " ++
            "dynamic linker, so it cannot carry a shared object at all. This " ++
            "build will not substitute a static archive for one you asked for " ++
            "as shared. Use -Dlinkage=static for this target, or build for a " ++
            "target that has a dynamic linker.",
        .{@tagName(target.result.os.tag)},
    );
}

/// Whether this target's C++ library can provide `std::thread`.
///
/// `extern/enkiTS/src/TaskScheduler.h:22` includes `<thread>` and
/// `TaskScheduler.cpp` constructs `std::thread`s, and Zig 0.16's `wasm32-wasi`
/// C++ library has no threads and no WASIp1-threads runtime. This is the only
/// target in this package's matrix where that is true, and it is why
/// `addEnkiTS` is allowed to answer null.
fn targetHasCxxThreads(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag != .wasi;
}

/// Whether this target has to compile Box2D's scalar math path even though the
/// caller did not ask for it.
///
/// ## What upstream selects
///
/// `src/core.h:50-51` defines `B2_CPU_ARM` for every ARM target, 32-bit and
/// 64-bit alike, and `src/core.h:72-74` then selects `B2_SIMD_NEON` with no
/// further condition. `src/contact_solver.c:518-523` acts on that by including
/// `<arm_neon.h>`. Upstream has no switch between "ARM" and "ARM with the
/// intrinsics this toolchain ships", so on a target where that header does not
/// compile the one portable answer is the macro upstream provides for exactly
/// that case: `BOX2D_DISABLE_SIMD` (`src/core.h:59-62`), which selects the
/// plain `struct { float x, y, z, w; }` wide-float path at
/// `src/contact_solver.c:535-538`.
///
/// ## The one target that needs it
///
/// Zig's `<arm_neon.h>` includes `<arm_bf16.h>` unconditionally for every ARM
/// target (`lib/include/arm_neon.h:35`), and that header opens with
/// `typedef __bf16 bfloat16_t;` (`lib/include/arm_bf16.h:14`). Clang rejects
/// `__bf16` where the target has no BFloat16 extension, so the whole header
/// fails and with it every core translation unit that reaches it. That is
/// observed rather than inferred: the 53-platform run reports
/// `__bf16 is not supported on this target` at that line and nineteen
/// follow-on errors from it, for `arm-openbsd` and for no other target in the
/// matrix.
///
/// The condition is the OS tag beside the 32-bit ARM family rather than the
/// triple, and it is deliberately narrow:
///
///   * `aarch64` is excluded. `__bf16` is part of ARMv8-A, so the header
///     compiles there and every AArch64 target in this matrix does. Widening
///     the rule would silently give up NEON on hardware that has it, which is
///     the cost of being wrong in this direction.
///   * `arm-netbsd` and `armeb-netbsd` are excluded by observation rather than
///     by guesswork: `compile lib box2d` *succeeded* for both in the same run,
///     so a 32-bit ARM NetBSD target does include `<arm_neon.h>` and
///     `<arm_bf16.h>` here. The boundary is this toolchain's OpenBSD ARM
///     triple, not "ARM", and not "a target that is not Linux".
///
/// ## Why the caller's option is untouched
///
/// `-Ddisable-simd` still decides everything it decided before: an explicit
/// `-Ddisable-simd=true` is the same define for the same reason, and
/// `-Davx2` is untouched because upstream only offers `BOX2D_AVX2` on x86_64
/// (`CMakeLists.txt:46-48`), which is not in this family. There is no build in
/// which a caller can ask for the NEON path on this target, because there is
/// no such build; the configure line prints the difference between a caller who
/// asked for the scalar path and a target that needed it.
fn armNeonNeedsScalar(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag != .openbsd) return false;
    return switch (target.result.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => true,
        else => false,
    };
}

/// Whether `BOX2D_DISABLE_SIMD` is on the core's compile line: the caller's
/// request, or this build's own answer for the target.
///
/// One function answers it for the compile line (`coreMacros`) and for the
/// configure line `build` prints, because a report of a configuration the
/// compile line did not get is worse than no report.
fn scalarMath(target: std.Build.ResolvedTarget, options: Options) bool {
    return options.disable_simd or armNeonNeedsScalar(target);
}

/// The private defines on the core's own compile line, resolved from where
/// upstream reads them.
///
/// `BOX2D_VALIDATE` is the heavy validation switch
/// (`src/CMakeLists.txt:119-122`); `BOX2D_DISABLE_SIMD` and `BOX2D_AVX2` are
/// read at `src/core.h:59` and `src/core.h:65` and nowhere else. None of the
/// three is on the translation and none changes a public header, which is why
/// `zig/translate.h` does not set them and why the translated declaration set
/// is the same in every mode.
///
/// `BOX2D_DISABLE_SIMD` has two sources and `scalarMath` is where they are
/// joined: the caller's `-Ddisable-simd`, and `armNeonNeedsScalar`'s answer
/// for a target whose `<arm_neon.h>` this toolchain cannot include.
fn coreMacros(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    options: Options,
    out_flags: *std.ArrayList([]const u8),
) void {
    if (options.validate) out_flags.append(b.allocator, "-DBOX2D_VALIDATE") catch @panic("OOM");

    if (scalarMath(target, options)) {
        out_flags.append(b.allocator, "-DBOX2D_DISABLE_SIMD") catch @panic("OOM");
    } else if (options.avx2 and target.result.cpu.arch == .x86_64) {
        // `CMakeLists.txt:46-48` only offers `BOX2D_AVX2` when
        // `CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64"`, and
        // `cmake_dependent_option` at :47 also makes it require
        // `NOT BOX2D_DISABLE_SIMD`; `src/CMakeLists.txt:180-184` then adds
        // `-mavx2`. The two are kept together here for the same reason.
        out_flags.append(b.allocator, "-DBOX2D_AVX2") catch @panic("OOM");
        out_flags.append(b.allocator, "-mavx2") catch @panic("OOM");
    }
}

/// The compile flags for one C translation unit, by what upstream compiles it
/// with.
///
/// Three different shapes, all from upstream's own CMake:
///
///   * **Core**: `C_STANDARD 17` with `C_EXTENSIONS YES`
///     (`src/CMakeLists.txt:91-98`), which is `-std=gnu17`. The level is
///     load-bearing rather than stylistic: Box2D uses `_Static_assert` and
///     anonymous unions, and `src/CMakeLists.txt:90` says so in as many words.
///   * **Tests and benchmark**: `C_STANDARD 17` with `C_EXTENSIONS NO`
///     (`test/CMakeLists.txt:19-23`, `benchmark/CMakeLists.txt:11-15`), which
///     is `-std=c17`.
///   * **Determinism**: `-ffp-contract=off` on MINGW, APPLE and UNIX
///     (`CMakeLists.txt:37-41`), with the reason in place — the post linked
///     there is Box2D's own determinism article. It applies to every target in
///     this package's matrix, because none of them is MSVC and the MINGW,
///     Apple and UNIX cases are exactly the ones present.
///   * **Visibility**: `-fvisibility=hidden`, from
///     `CMAKE_C_VISIBILITY_PRESET hidden` at `src/CMakeLists.txt:74`. That
///     `set()` is in `src/`'s own directory scope, so it applies to the
///     `box2d` target and not to `shared`, `test` or `benchmark` — which is
///     why `standard_flags` takes it as an argument rather than adding it
///     everywhere.
///   * **Warnings**: `-Wmissing-prototypes -Wall -Wextra -pedantic
///     -Wno-unused-value` on UNIX (`src/CMakeLists.txt:172-174`), the same
///     without `-Wno-unused-value` on Apple (`src/CMakeLists.txt:164-166`), and
///     nothing on MinGW, whose branch (`src/CMakeLists.txt:156-163`) adds flags
///     only under `BOX2D_AVX2`, which is already handled above. No `-Werror`:
///     upstream's `BOX2D_COMPILE_WARNING_AS_ERROR` is OFF by default
///     (`CMakeLists.txt:44`).
fn standard_flags(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    std_level: []const u8,
    visibility_hidden: bool,
) []const []const u8 {
    const os_tag = target.result.os.tag;
    var flags: std.ArrayList([]const u8) = .empty;
    const out = &flags;
    out.append(b.allocator, b.fmt("-std={s}", .{std_level})) catch @panic("OOM");
    out.append(b.allocator, "-ffp-contract=off") catch @panic("OOM");
    if (visibility_hidden) out.append(b.allocator, "-fvisibility=hidden") catch @panic("OOM");
    switch (os_tag) {
        .macos, .ios, .tvos, .watchos, .visionos => {
            out.appendSlice(b.allocator, &.{ "-Wmissing-prototypes", "-Wall", "-Wextra", "-pedantic" }) catch @panic("OOM");
        },
        .windows => {},
        else => {
            out.appendSlice(b.allocator, &.{
                "-Wmissing-prototypes", "-Wall", "-Wextra", "-pedantic", "-Wno-unused-value",
            }) catch @panic("OOM");
        },
    }
    return out.items;
}

/// The system libraries the compiled sources need.
///
/// `libm` because `include/box2d/math_functions.h:9` includes `<math.h>` and
/// the scalar paths call `sqrtf`, `sinf`, `cosf` and `atan2f`
/// (`include/box2d/math_functions.h` and `src/math_functions.c`) — on glibc and
/// musl those live in `libm`, not `libc`, which is why upstream's UNIX branch
/// gets it for free from CMake. Not on Darwin, where they are in `libSystem`,
/// and not on Windows, where `src/CMakeLists.txt:156-163` adds nothing either.
fn coreSystemLibraries(target: std.Build.ResolvedTarget) []const []const u8 {
    const os_tag = target.result.os.tag;
    return switch (os_tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .windows => &.{},
        else => &.{"m"},
    };
}

/// Compiles the core library for one target: the 35 translation units above at
/// the pinned C level, plus this fork's one bridge source, with `include/` and
/// `src/` on the compile line.
///
/// The bridge source is added to *this* module rather than to a library of its
/// own, and that is the whole reason it lives here: `b2MakeAABB` has to be a
/// symbol of this artifact in every configuration that delivers one -- the
/// static archive, the shared object, and the second static archive
/// `addGraph` builds for upstream's own suite when the requested linkage is
/// dynamic -- and it has to be the symbol under this module's `-D` set, this
/// module's `-fvisibility=hidden` and this module's `box2d_EXPORTS` split. A
/// separate bridge artifact would be a second place for those to be stated,
/// and a caller could then link one core and not the other.
///
/// No generated input and no config header are involved. Every macro this
/// library is configured with is a `-D` on this compile line
/// (`src/CMakeLists.txt:104-132` defines them all with
/// `target_compile_definitions`), and none of them is installed or translated,
/// so there is nothing to generate per target and no way for a host's
/// configuration to reach a cross target's compile line.
fn addCoreLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: Options,
    name: []const u8,
) *std.Build.Step.Compile {
    const shared = options.requested_linkage == .dynamic;

    var macro_flags: std.ArrayList([]const u8) = .empty;
    coreMacros(b, target, options, &macro_flags);

    const flags = std.mem.concat(b.allocator, []const u8, &.{
        standard_flags(b, target, "gnu17", true),
        macro_flags.items,
    }) catch @panic("OOM");

    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because every translation unit reaches `<string.h>`, and
        // `src/core.c` also reaches `<stdlib.h>` for the allocator default.
        .link_libc = true,
        // A shared library is position-independent whether or not this says
        // so; naming it makes the requirement explicit.
        .pic = if (shared) true else null,
    });
    // The quoted includes every `src/*.c` uses, and the `box2d/...` spelling
    // every one of them uses for the public interface.
    c_mod.addIncludePath(b.path(include_dir));
    c_mod.addIncludePath(b.path(source_dir));
    for (coreSystemLibraries(target)) |lib| {
        c_mod.linkSystemLibrary(lib, .{});
    }
    if (shared) {
        // CMake's per-target define symbol for a target called `box2d`, and
        // the half of `base.h:11-19` that exports. CMake adds it to the
        // library's own `COMPILE_DEFINITIONS` for a shared library and to
        // nothing else; this build states it rather than relying on that.
        c_mod.addCMacro("box2d_EXPORTS", "1");
    }
    c_mod.addCSourceFiles(.{
        // The names are relative to `src/`, which is also the source root.
        .root = b.path(source_dir),
        .files = &core_sources,
        .flags = flags,
        .language = .c,
    });

    // The fork's own C, on the same module and the same flags, so it is one
    // compilation configuration rather than two that must be kept in agreement.
    // It needs no include path of its own: it includes the public headers the
    // spelling `<box2d/...>` that `include_dir` already satisfies, and it adds
    // nothing to the installed header set -- the symbol it exports is declared
    // by `include/box2d/math_functions.h:625`, which is already installed, so
    // a C consumer of the install needs this object and nothing beside it.
    c_mod.addCSourceFiles(.{
        // The names are relative to `build_support/`, which is deliberately
        // not on any include path: nothing includes from it.
        .root = b.path(bridge_dir),
        .files = &bridge_sources,
        .flags = flags,
        .language = .c,
    });

    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = options.requested_linkage,
        // Upstream's `SOVERSION 3` with `VERSION 3.1.1`
        // (`src/CMakeLists.txt:95-97`). `version` is null for a static archive,
        // which has no soname and no versioned file name.
        .version = if (shared) soversion else null,
        .root_module = c_mod,
    });

    // Installing a header also puts it on the include path of anything that
    // links this artifact, so a C consumer of the installed archive needs
    // nothing from this tree to call it. These six are the whole of upstream's
    // `BOX2D_API_FILES`, and they install into `include/box2d/` as upstream's
    // `install(FILES ${BOX2D_API_FILES} DESTINATION
    // ${CMAKE_INSTALL_INCLUDEDIR}/box2d)` does: the second argument is the path
    // inside the installed include tree, not the path in this repository, so it
    // is `box2d/<name>` and not `include/box2d/<name>`.
    for (public_headers) |header| {
        c_lib.installHeader(b.path(header), b.fmt("box2d/{s}", .{std.fs.path.basename(header)}));
    }

    return c_lib;
}

/// Compiles upstream's static `shared` support library for one target.
///
/// `shared/CMakeLists.txt:14-18` makes it a `STATIC` library with
/// `C_STANDARD 17` and no `C_EXTENSIONS` setting, so it takes CMake's default
/// and compiles as `-std=gnu17`. Its public include directory is `shared/`
/// itself (`shared/CMakeLists.txt:24`), which is how `test_determinism.c:5`
/// finds `determinism.h`.
fn addSupportLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const support_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    support_mod.addIncludePath(b.path(include_dir));
    support_mod.addIncludePath(b.path(support_dir));
    support_mod.addCSourceFiles(.{
        .root = b.path(support_dir),
        .files = &support_sources,
        .flags = standard_flags(b, target, "gnu17", false),
        .language = .c,
    });

    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = support_mod,
    });
}

/// Compiles the vendored enkiTS C++ closure for one target, or answers null.
///
/// Null means "this target's C++ library has no `std::thread`", which is WASI
/// in this package's matrix, and it is reported by `build` and by
/// `addTargetCheck` rather than swallowed. There is no third answer: the two
/// `.cpp` files are the whole closure and nothing is stubbed, substituted or
/// dropped when they are compiled.
fn addEnkiTS(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) ?*std.Build.Step.Compile {
    if (!targetHasCxxThreads(target)) return null;

    const enki_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // `TaskScheduler.h:21-24` and `LockLessMultiReadPipe.h:21-26` reach
        // `<atomic>`, `<thread>` and `<functional>`, so the closure needs the
        // C++ runtime. s2geometry states the same on every module it compiles
        // C++ for.
        .link_libcpp = true,
    });
    enki_mod.addIncludePath(b.path(enki_source_dir));
    for (posixThreadLibraries(target)) |lib| {
        enki_mod.linkSystemLibrary(lib, .{});
    }
    enki_mod.addCSourceFiles(.{
        .root = b.path(enki_source_dir),
        .files = &enki_sources,
        // `-std=c++11`, which is what enkiTS's own `CMakeLists.txt:99` and its
        // own `build.zig:85` both state.
        .flags = &.{"-std=c++11"},
        .language = .cpp,
    });

    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = enki_mod,
    });
}

/// The platform's POSIX thread library, where there is one.
///
/// `extern/enkiTS/src/TaskScheduler.h:22` includes `<thread>` and
/// `TaskScheduler.cpp` constructs `std::thread`s, which needs the platform's
/// threads at link time on every target whose C++ runtime does not fold them
/// in: Linux and the BSDs name `pthread`, Apple and Windows carry them in the
/// platform runtime that is already on the line, and WASI never gets here.
fn posixThreadLibraries(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => &.{"pthread"},
        else => &.{},
    };
}

/// Builds upstream's own unit test suite, unmodified, for one target.
///
/// It is a C program, so it needs `include/` for the `box2d/...` headers,
/// `src/` for the internals `test_table.c:4-7` and `test_world.c:5` include by
/// bare name, `shared/` for `determinism.h` (`test_determinism.c:5`), and
/// `extern/enkiTS/src` for `TaskScheduler_c.h` (`test_determinism.c:4`) —
/// upstream's own `target_include_directories(test PRIVATE
/// ${CMAKE_SOURCE_DIR}/src)` at `test/CMakeLists.txt:30` is the same fact for
/// one of those four.
///
/// It links the *static* core, because upstream's unit tests do:
/// `CMakeLists.txt:100-104` only adds `test/` when `NOT BUILD_SHARED_LIBS`, and
/// the reason is in the comment there — the suite calls internal functions a
/// shared build hides.
fn addUpstreamTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    graph: Graph,
    tools: Tools,
    name: []const u8,
) ?*std.Build.Step.Compile {
    const enki = tools.enki orelse return null;

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // The suite links `libenkits.a`, so it carries the C++ runtime itself
        // rather than inheriting a requirement from a static archive.
        .link_libcpp = true,
    });
    mod.addIncludePath(b.path(include_dir));
    mod.addIncludePath(b.path(source_dir));
    mod.addIncludePath(b.path(support_dir));
    mod.addIncludePath(b.path(enki_source_dir));
    mod.addCSourceFiles(.{
        .root = b.path(test_dir),
        .files = &upstream_test_sources,
        .flags = standard_flags(b, target, "c17", false),
        .language = .c,
    });
    mod.linkLibrary(graph.static_lib);
    mod.linkLibrary(tools.support);
    mod.linkLibrary(enki);
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// Builds upstream's benchmark tool for one target, or answers null.
///
/// `benchmark/CMakeLists.txt:17-18` links `box2d shared enkiTS` and
/// `:9-15` sets `C_STANDARD 17` with `C_EXTENSIONS NO`, and
/// `benchmark/main.c:8-9` reaches `TaskScheduler_c.h` and `benchmarks.h`. It
/// is null for the same target `addEnkiTS` is.
fn addBenchmark(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    graph: Graph,
    tools: Tools,
    name: []const u8,
) ?*std.Build.Step.Compile {
    const enki = tools.enki orelse return null;

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    mod.addIncludePath(b.path(include_dir));
    mod.addIncludePath(b.path(support_dir));
    mod.addIncludePath(b.path(enki_source_dir));
    mod.addCSourceFile(.{
        .file = b.path(benchmark_source),
        .flags = standard_flags(b, target, "c17", false),
        .language = .c,
    });
    mod.linkLibrary(graph.static_lib);
    mod.linkLibrary(tools.support);
    mod.linkLibrary(enki);
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// `zig translate-c` parses C with Aro, and Aro preprocesses as well as parses,
/// so `zig/translate.h` can be read either way round: Aro can do both jobs, or
/// the target's own C preprocessor can do the first and Aro the second. Both
/// routes read this repository's six public headers on the same include path
/// with the same macros; only the preprocessor that has to understand the
/// target's C library changes.
///
/// Every target but NetBSD keeps the route it already had. `zig/translate.h`
/// reaches five C library headers and no others — `base.h:6,97`
/// (`<stdint.h>`, `<assert.h>`), `math_functions.h:8-9` (`<float.h>`,
/// `<math.h>`) and `<stdbool.h>` at `box2d.h:11`, `collision.h:9`,
/// `math_functions.h:10` and `types.h:11` — and every one of them except
/// NetBSD's spells `__END_DECLS` as plain tokens Aro parses.
///
/// NetBSD's does not. `generic-netbsd/sys/cdefs.h:432` routes `__END_DECLS`
/// through `__END_PUBLIC_DECLS`, which `:413` defines as `extern "C"` framing
/// around `_Pragma("GCC visibility pop")`. `<math.h>` closes every
/// declaration block with `__END_DECLS`, so every NetBSD translation drags a
/// `_Pragma` operator invocation into it, and Aro destringizes it into a
/// `#pragma` line it then hands to the parser as C. Observed on all nine
/// NetBSD targets in the 53-platform run and on no other target, with the C
/// archive itself compiled every time:
/// `generic-netbsd/math.h:607:1: error: unknown type name 'pragma'`, five
/// errors per target, at `translate-c` and not anywhere else. Those targets
/// take the extra front end; nothing about their declaration set changes.
///
/// The condition is the OS tag rather than a list of nine triples because the
/// whole family shares that one header and that one cause: every NetBSD target
/// that reaches it fails for the same reason, and a list would silently stop
/// covering the next architecture.
const TranslateRoute = enum {
    /// Aro preprocesses `zig/translate.h` for itself and parses the result.
    aro,
    /// The target's own C preprocessor expands `zig/translate.h` first, and
    /// Aro parses what that produced.
    preprocessed,
};

fn translateRoute(target: std.Build.ResolvedTarget) TranslateRoute {
    return if (target.result.os.tag == .netbsd) .preprocessed else .aro;
}

/// `zig/translate.h`, preprocessed for the target being built.
///
/// The extra front end `translateRoute` selects for NetBSD. What this writes is
/// the aggregate header with every `#include` resolved, every conditional
/// settled and every macro definition kept, for the target the C core is being
/// compiled for. Nothing is stubbed, narrowed, renamed or substituted, and no
/// declaration is dropped: the six headers arrive whole or not at all.
///
/// ## Why this preprocessor may run at all
///
/// It is the compiler running this build script -- `b.graph.zig_exe` -- so the
/// target, the include path and the widths are the ones the 35 core units are
/// compiled with.
///
/// ## Why `-dD`
///
/// Without it the expansion carries no macro definitions. The six public
/// headers are almost entirely macros (`B2_ASSERT`, `B2_INLINE`,
/// `B2_LITERAL`, the `b2*` enumerant spellings), and a header a C or Zig
/// caller reads as a macro still has to reach Zig as a constant, so a dump of
/// used macros only would take the constant set with it.
///
/// ## Why `-MD`
///
/// The six headers are reached only through `#include`, and a `-I` directory
/// argument contributes nothing but its own resolved path to a run step's
/// manifest. Without a depfile this step's declared inputs would be
/// `zig/translate.h` and two path strings, and a later revision of
/// `include/box2d/types.h` would be served from the run cache while the
/// translation went on describing the previous one. `-MD` with `-MF` hands the
/// discovered headers to the build system as this step's own inputs.
///
/// ## What is deliberately not on this line
///
/// No `-D`. `BOX2D_DLL` is the one macro the translation can carry
/// (`addGraph`), it is Windows-only, and this route is NetBSD-only, so the two
/// are mutually exclusive by construction and a macro here would be a
/// statement about a configuration that cannot occur.
fn preprocessedTranslateHeader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD" });
    run.setName("preprocess box2d translate.h");
    if (!target.query.isNative()) {
        const triple = target.query.zigTriple(b.allocator) catch @panic("box2d: unspellable target");
        run.addArg("-target");
        run.addArg(triple);
    }
    // The same include root the C compile line gives every core source, so
    // `<box2d/base.h>` and its five siblings resolve to this repository's files
    // and never to an installed `box2d/` (`WISDOM.md` W14).
    run.addPrefixedDirectoryArg("-I", b.path(include_dir));
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("box2d-translate.c");
    run.addArg("-MD");
    _ = run.addPrefixedDepFileOutputArg("-MF", "box2d-translate.d");
    run.addFileArg(b.path(translate_header));
    return preprocessed;
}

/// Builds one target's library, facade and the support targets its own C tools
/// link.
///
/// `public` chooses between the package module set, which is what a dependent
/// reaches through `dep.module("box2d")`, and a private module. A cross-target
/// check needs the private form: modules are registered by name against the
/// whole build, so registering `box2d` once per matrix target would leave only
/// the last of them reachable and silently stop checking the rest. The
/// translated header is imported rather than registered in both forms; the
/// published routes are named above.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: Options,
    public: bool,
) struct { graph: Graph, tools: Tools } {
    const shared = options.requested_linkage == .dynamic;
    var static_options = options;
    static_options.requested_linkage = .static;
    const c_lib = addCoreLibrary(b, target, optimize, options, artifactName(b, target, public));
    // One core compile when the requested linkage is already static; a second
    // one when it is not. Both are the same 35 sources with the same flags,
    // and both honour the same requested linkage: the second one exists only so
    // upstream's own suite has a static archive to link, not as a fallback for
    // the delivered artifact.
    const static_lib = if (!shared)
        c_lib
    else
        addCoreLibrary(b, target, optimize, static_options, b.fmt("{s}-static", .{
            artifactName(b, target, public),
        }));

    const translate = b.addTranslateC(.{
        // Which front end reads the aggregate is `translateRoute`'s call. The
        // two routes differ in exactly one respect: the `.aro` one hands the
        // translator this repository's `zig/translate.h` to preprocess for
        // itself, and the `.preprocessed` one hands it what `zig cc -E -dD`
        // already wrote for the same target, on the same include path.
        .root_source_file = switch (translateRoute(target)) {
            .aro => b.path(translate_header),
            .preprocessed => preprocessedTranslateHeader(b, target),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // `zig/translate.h` includes the six headers as `<box2d/...>`, and this is
    // the only header search path the translation has. Without it the
    // translation would silently bind to whatever `box2d/` happens to be
    // installed on the build machine and describe that library's declarations
    // rather than the ones this graph compiles (`WISDOM.md` W14).
    translate.addIncludePath(b.path(include_dir));
    if (shared and target.result.os.tag == .windows) {
        // The declaration half of upstream's DLL split. The library's own
        // compile line gets `box2d_EXPORTS` (`addCoreLibrary`); this line gets
        // `BOX2D_DLL` alone, so `include/box2d/base.h:14-16` decorates the
        // public declarations with `__declspec(dllimport)` on a Windows
        // consumer rather than re-exporting them from a module that does not
        // define them. That is upstream's own `INTERFACE` half
        // (`src/CMakeLists.txt:131-133`), and it is Windows-only because
        // `base.h:11` and `:14` both test `_MSC_VER`: under MinGW both macros
        // are unread and `B2_API` is the visibility attribute, which is what
        // upstream's MinGW shared build uses.
        translate.defineCMacro("BOX2D_DLL", "1");
    }
    const c_module = translate.createModule();

    const module = if (public)
        b.addModule(module_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    // The same include path as the archive's own module, on the module a
    // dependent actually imports, so a dependent that compiles its own C
    // against this package finds the same headers the core was compiled with.
    module.addIncludePath(b.path(include_dir));
    if (shared and target.result.os.tag == .windows) {
        module.addCMacro("BOX2D_DLL", "1");
    }

    // Where the runtime-loading seam is
    // ---------------------------------
    // `runtime/graph.zig`, which the API role owns, exposes
    //
    //     pub fn createModule(
    //         b: *std.Build,
    //         translate: *std.Build.Step.TranslateC,
    //         target: std.Build.ResolvedTarget,
    //         optimize: std.builtin.OptimizeMode,
    //     ) *std.Build.Module
    //
    // and `-Druntime` substitutes that one call for `translate.createModule()`.
    // It takes the `TranslateC` step this function has already built, so the
    // generated dispatch keeps the exact translated type and constant
    // namespace rather than compiling a second copy of the native extern
    // structs and casting between two nominally distinct Zig modules: every
    // type and constant in the dispatch is re-exported from the translation it
    // was generated from, so `c.b2Vec2` in the facade and the declaration
    // behind the table are one type.
    //
    // `-Dlinkage` is orthogonal and keeps meaning what it means: it selects
    // which artifact this build *delivers* and installs, never which one the
    // module dispatches through.
    //
    // The `rt` import is for the linked branch only, and the reason is the
    // nominal type rather than the code. `graph.createModule` creates the one
    // core-module instance the generated dispatch uses and re-exports
    // `LoadSource`/`LoadError` from it; a second instance created here for the
    // facade would be a *different* `LoadSource`, and `box2d.load(source)`
    // would be handing the facade's type to a function expecting the
    // dispatch's. One instance per build, no more. In a linked build there is
    // no dispatch, so the facade's own `rt` import is where those two public
    // types come from; `zig/root.zig` picks between the two with a comptime
    // branch on `runtime_loaded`, so the module a configuration does not need
    // is never resolved and never compiled.
    if (options.runtime_loaded) {
        // A loaded provider must arrive through the platform loader, so the
        // link line names nothing. Linking the archive as well would make the
        // linker resolve the same symbols statically and the runtime route
        // would quietly be a linked one. The artifact itself is still built
        // and installed above, because delivery and dispatch are separate
        // questions: the whole point of the mode is that a caller may name a
        // provider this tree did not build.
        module.addImport("c", runtime_graph.createModule(b, translate, target, optimize));
    } else {
        // The translated header is imported, never registered. `addModule("c")`
        // would make `dep.module("c")` resolve and hand a dependent the same
        // declarations without the library that satisfies them; `box2d.c` on
        // the facade is the supported way in and carries the facade's own
        // linkage.
        module.addImport("c", c_module);
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

    // A private graph names its internal artifacts with the target triple too,
    // for the reason `artifactName` gives: six targets in one build graph would
    // otherwise produce six steps called "enkits" and six called
    // "box2d-shared", which makes `--summary all` impossible to read.
    const suffix: []const u8 = if (public)
        ""
    else
        b.fmt("-{s}", .{target.result.zigTriple(b.allocator) catch @panic("unspellable target")});
    const tools: Tools = .{
        .enki = addEnkiTS(b, target, optimize, b.fmt("enkits{s}", .{suffix})),
        .support = addSupportLibrary(b, target, optimize, b.fmt("box2d-shared{s}", .{suffix})),
    };

    return .{
        .graph = .{
            .c_lib = c_lib,
            .static_lib = static_lib,
            .module = module,
            .c_module = c_module,
        },
        .tools = tools,
    };
}

/// Whether every Zig compilation root in this package selects LLVM.
///
/// ## What is observed
///
/// The C library is compiled by Clang, from `addCSourceFiles` on
/// `addCoreLibrary`'s module, and it is correct on the targets where this
/// package's own Zig tests crash: in the same 53-platform run,
/// `compile lib box2d` succeeded *and* upstream's own unmodified `test/main.c`
/// printed `All Box2D tests passed!` for `x86-linux`, `hexagon-linux`,
/// `riscv32-linux`, `powerpc64le-linux`, `mips64el-linux` and
/// `loongarch64-linux`, while the Zig facade tests on those same targets died
/// inside a call that had just been handed a pointer the callee could not
/// dereference (`B2_CHECK_DEF( def )`, `src/body.c:179`) or returned a null
/// `b2Polygon` / a `b2Version` reading `1.0.-2080380932`. The defect is on the
/// Zig side of the boundary and it is an aggregate-ABI one: `b2WorldId` is a
/// four-byte struct passed by value (`include/box2d/box2d.h:210` takes
/// `const b2BodyDef*`, `b2CreateWorld` takes `const b2WorldDef*` at `:27`) and
/// `b2MakeBox` returns `b2Polygon` by value.
///
/// ## Why LLVM, and what it does not do
///
/// It does not change the public ABI. No declaration, no struct layout and no
/// exported symbol moves; this is only which code generator compiles the Zig
/// half of a link that already mixes two languages. It is the same lever, for
/// the same class of failure, that this workspace already uses for ERFA's
/// external Zig roots (`AGENTS.md` §6, `erfa/build.zig:1207-1233`), where the
/// recorded cause is that Zig 0.16 mispasses a wide C ABI.
///
/// ## The dependent-root requirement
///
/// `use_llvm` is a property of a compilation, not of a module
/// (`std/Build/Step/Compile.zig:284`), so it can only be set where a root is
/// created: `addTest`, `addExecutable`. The facade in `zig/root.zig` is an
/// *imported* module here and it cannot carry the setting for its importer, and
/// neither can the published `box2d` module carry it for a dependent. Every
/// root in this package therefore states it for itself — `build`'s `test` and
/// `box2d-smoke`, `addTargetCheck`'s `box2d-tests-<triple>` and
/// `box2d-smoke-<triple>`, and `consumer/build.zig`'s own executable — and
/// that is the documented requirement for anyone else building a Zig root on
/// top of this module: **a dependent must select LLVM in its own root.** A
/// dependent that does not gets the compiler's default choice back.
///
/// `addUpstreamTest` and `addBenchmark` are pure C executables and do not
/// state it: there is no Zig code in them for a code generator to choose, and
/// the C compile line is unchanged either way.
const llvm_required = true;

/// A Zig program or test root that imports the published facade module.
///
/// `link_libc` is stated on every one of them even though the facade carries
/// it: a dependent states its own, and this build should fail here if the
/// facade ever stopped bringing libc along. The archive is not linked a second
/// time: it arrives with the imported facade module, which is what makes that
/// module self-contained, and a redundant `linkLibrary` here would put the same
/// archive on the link line twice.
fn programModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module: *std.Build.Module,
    source: []const u8,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport(module_name, module);
    return mod;
}

/// Compiles the full graph, the tests, the example, upstream's own C suite and
/// the benchmark tool for one matrix target, and attaches all of them to
/// `step`.
///
/// Building the test binary and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and `tests.zig` and `smoke.zig` call the
/// public facade. The full C source is compiled by the same graph. Nothing is
/// run here, so every result this step produces is compile evidence and not a
/// claim that a cross-built binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);
    // The triple names the cross artifacts. Six targets in one build graph
    // otherwise produce six steps called "box2d", which makes `--summary all`
    // useless for telling them apart.
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    // A target that cannot carry the requested linkage is left out of this
    // check, by name and with the reason, rather than checked against a
    // different artifact than the one that was asked for. Under the default
    // static linkage `targetCanCarry` is true for every target and all six are
    // checked, so the six-target matrix is complete for the default graph and
    // nothing is lost by the rule. Under `-Dlinkage=dynamic` a target with no
    // dynamic linker is not covered, and the line below says so: a printed
    // exclusion is not a pass, and this build will not produce a static
    // archive to stand in for the shared object the run asked for.
    if (!targetCanCarry(cross_target, options.requested_linkage)) {
        std.debug.print(
            "box2d: check: {s} is NOT covered by this run. {s}\n",
            .{ triple, unsupportedLinkageReason(b, cross_target) },
        );
        return;
    }

    const built = addGraph(b, cross_target, optimize, options, false);

    step.dependOn(&b.addTest(.{
        .name = b.fmt("box2d-tests-{s}", .{triple}),
        .use_llvm = llvm_required,
        .root_module = programModule(b, cross_target, optimize, built.graph.module, test_source),
    }).step);

    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("box2d-smoke-{s}", .{triple}),
        .use_llvm = llvm_required,
        .root_module = programModule(b, cross_target, optimize, built.graph.module, example_source),
    }).step);

    if (addUpstreamTest(b, cross_target, optimize, built.graph, built.tools, b.fmt("box2d-upstream-test-{s}", .{triple}))) |suite| {
        step.dependOn(&suite.step);
    } else {
        // Never a silent narrowing. This target's C++ library has no
        // `std::thread`, so `extern/enkiTS` and therefore upstream's own suite
        // and its benchmark tool are not compiled for it; everything else in
        // the graph above still was.
        std.debug.print("box2d: check: {s} has no C++ threads; upstream's own test suite and the benchmark tool are not compiled for it\n", .{triple});
    }

    if (addBenchmark(b, cross_target, optimize, built.graph, built.tools, b.fmt("box2d-benchmark-{s}", .{triple}))) |tool| {
        step.dependOn(&tool.step);
    }
}

/// Writes `lib/pkgconfig/box2d.pc` and installs it.
///
/// `Name`, `Description` and `Version` are upstream's own, from
/// `CMakeLists.txt:5-10`. Upstream ships no `.pc.in` at this pin — it installs
/// a CMake target export instead — so the field set below is fork-authored, and
/// `FORK-NOTES.md` records that. Two choices inside it are worth naming:
///
///   * `prefix` is `${pcfiledir}/../..` rather than a configured absolute
///     prefix. This graph does not know where `--prefix` will point when it
///     writes the file, and pkg-config resolves `${pcfiledir}` against the
///     `.pc` file it found, so the installed file is correct wherever the
///     prefix landed, including a Nix store path only known at build time.
///   * `includedir` is `${prefix}/include`, not `${prefix}/include/box2d`,
///     because the headers install one directory below it
///     (`src/CMakeLists.txt:208-211`) and `src/CMakeLists.txt:84` puts the
///     include directory itself on the interface. A C consumer therefore
///     writes `#include <box2d/box2d.h>`, which is upstream's own spelling.
///
/// `Libs:` is `-lbox2d` in both linkages, because the library *name* does not
/// change with linkage: a C consumer asks for `-lbox2d` and the linker resolves
/// it to `libbox2d.a` or, through the `libbox2d.so` symlink, to the shared
/// object.
///
/// `Cflags:` differs, and only for the shared build: `-DBOX2D_DLL` is what
/// makes a Windows consumer's declarations `__declspec(dllimport)` through
/// `base.h:14-16`.
///
/// `Libs:` carries the platform's math library where the library needs one,
/// because that need is the *consumer's* to satisfy and not this build's:
/// `include/box2d/math_functions.h:9` includes `<math.h>` and the scalar paths
/// call `sinf`, `cosf` and `atan2f`, which live in `libm` on glibc and musl. A
/// shared install would not strictly need it — the shared object already
/// records its own `DT_NEEDED` — but the same `.pc` describes the static
/// install too, where the consumer's link line is the only place `libm` can
/// come from. `coreSystemLibraries` is the one place that knows which targets
/// those are, so the field is derived from it rather than from this file's
/// memory of them.
///
/// There is no `Libs.private` for the same reason: the whole of Box2D's own
/// closure is libc and, where it needs one, `libm`, and both belong on the
/// consumer's line in both linkages.
fn addPkgConfig(b: *std.Build, target: std.Build.ResolvedTarget, linkage: std.builtin.LinkMode) void {
    var libs: std.ArrayList([]const u8) = .empty;
    libs.appendSlice(b.allocator, &.{ "-L\"${libdir}\"", "-lbox2d" }) catch @panic("OOM");
    for (coreSystemLibraries(target)) |lib| {
        libs.append(b.allocator, b.fmt("-l{s}", .{lib})) catch @panic("OOM");
    }
    const files = b.addWriteFiles();
    // pkg-config's `Libs:` field is a whitespace-separated token list, so the
    // entries are joined into one string. `{s}` formats a single `[]const u8`;
    // `libs.items` is a `[]const []const u8`, which is not one.
    const libs_line = std.mem.join(b.allocator, " ", libs.items) catch @panic("OOM");
    const install_pc = b.addInstallFileWithDir(files.add("box2d.pc", b.fmt(
        \\# Generated by build.zig for the vendored Box2D source build.
        \\# Upstream ships no pkg-config template at this pin; see
        \\# FORK-NOTES.md. `prefix` is relative to this file so the
        \\# installed metadata is correct wherever --prefix put it.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: box2d
        \\Description: A 2D physics engine for games
        \\Version: {f}
        \\
        \\Requires:
        \\Libs: {s}
        \\Cflags: -I"${{includedir}}"{s}
        \\
    , .{
        upstream_version,
        libs_line,
        // Upstream's `INTERFACE BOX2D_DLL` under `MSVC AND BUILD_SHARED_LIBS`
        // (src/CMakeLists.txt:131-133); empty for a static build.
        if (linkage == .dynamic) " -DBOX2D_DLL" else "",
    })), .lib, "pkgconfig/box2d.pc");
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Installs the carried licence texts and provenance records under
/// `share/licenses/box2d/`.
///
/// A private repository removes no upstream obligation. Upstream's MIT text is
/// the whole grant for the 35-file core and the six headers; `NOTICE.md` says
/// which is which and records the per-file exceptions upstream's own tree
/// carries; `FORK-LICENSE.md` records the owner-authorised grant for this
/// fork's own files; `UPSTREAM.md` records the pin and what changed;
/// `FORK-NOTES.md` records what this fork changed about the pinned tree;
/// `extern/enkiTS/License.txt` is enkiTS's own grant for the C++ closure that
/// goes into the benchmark tool, which is why it travels here too.
///
/// `share/licenses/<name>` is the location `package.nix` uses as well, so the
/// packaging layer's own `install -Dm644` is an idempotent overwrite of these
/// bytes rather than a second copy.
///
/// Every step is attached to the install step explicitly, because
/// `addInstallFileWithDir` only *creates* the step and attaches it to nothing
/// (`lib/std/Build/Step/InstallFile.zig:15-36`). Without the `dependOn` below
/// this function describes every file in `licence_records` and the enkiTS
/// grant, and installs none of them, and `zig build` still exits zero — which
/// is exactly what it did before this line existed.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
    const install_enki_licence = b.addInstallFileWithDir(
        b.path(enki_licence),
        .prefix,
        b.fmt("share/licenses/{s}/{s}", .{ lib_name, enki_licence_dest }),
    );
    b.getInstallStep().dependOn(&install_enki_licence.step);
}

/// Runs the consumer package as its own `zig build` in `consumer/`.
///
/// The consumer is a separate package on purpose: a manifest dependency here
/// would close a cycle, because its manifest points back at this package by
/// path. Running it as a separate build is what makes the proof real — that a
/// package which only writes `b.dependency("box2d", ...)` and
/// `dep.module("box2d")` gets a working, correctly linked library, with the
/// archive and libc arriving through the module and nothing else.
///
/// Runs the consumer when an enabled executor can run target; otherwise
/// installs it without execution. Foreign installation is build-only evidence.
///
/// `-Dlinkage` and `-Druntime` are both forwarded, written out in each of
/// their two values and independently of each other, because the consumer
/// declares both as its own options and hands them to `b.dependency` (a
/// nullable value is not recorded at all, `std/Build.zig:435`,
/// `:569-581`). Forwarding `-Dlinkage` only when it was `dynamic` let the
/// static half of the matrix fall to whatever the nested package decided, and
/// `-Druntime` was not forwarded at all, so the loaded route could not be
/// exercised through this step in any configuration.
///
/// `-Dvalidate`, `-Ddisable-simd` and `-Davx2` are forwarded for the same
/// reason and on the same terms. They are Box2D's own private compile-line
/// defines (`src/CMakeLists.txt:119-122`, `src/core.h:59`, `src/core.h:65`), so
/// a nested build left to choose its own answers compiles a different library
/// than the one under test, and the whole point of this step is that the
/// package the nested build consumes is this one. They are written out in both
/// of their values rather than only when true: `false` is upstream's own
/// answer for the two vector-width switches and `true` is this package's for
/// validation, and forwarding a request rather than an effect keeps the two
/// builds reading the same question — the library reports on its own configure
/// line when it declines to apply one, and the nested build reports it for
/// itself the same way.
///
/// `-Dcpu` travels beside `-Dtarget` because the triple does not carry it.
/// `Target.Query.zigTriple` spells arch, OS and ABI (`std/Target/Query.zig:421`)
/// and the model and its feature set are a separate string in
/// `Target.Query.serializeCpu` (`:488-528`); `standardTargetOptions` reads them
/// from two separate `-D` options (`std/Build.zig:1474-1483`) and `b.dependency`
/// hands a dependent the same pair (`lib/std/Build.zig:439-449`).
///
/// Dropping it is invisible twice over: with no `-Dcpu` at all the nested build
/// re-derives the same answer from the architecture
/// (`std/Target/Query.zig:174-176`), and `-Dcpu=baseline` — which is how
/// `package.nix:109` builds this package, and the reason `-Dcpu` is documented
/// at `:99-102` above — re-derives it as well. It is visible for `-Dcpu=native`,
/// for an explicit model such as `x86_64_v3`, and for an added or subtracted
/// feature. Each of those is a different Box2D compile line, and a nested build
/// left to its own default would compile the baseline one, so `consumer` would
/// prove a library this build never produced and exit zero saying so.
///
/// The nested build is given this workspace's own job width and summary, the
/// cache directories this build was told about, the caller's own install
/// prefix when it named one, and the caller's own trailing arguments, so that
/// everything a caller can change about the selection reaches the process
/// that consumes the result. Job width, summary and a cache directory are on
/// every CLI entry in this repository (`AGENTS.md:157-158`,
/// `devenv.nix:190-222`); a nested build left to derive the rest resolves its
/// own width, its own package store, its own install prefix and an empty
/// argument list for itself.
fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The same query, the other half of it, for the reason the doc comment
    // above gives. `serializeCpu` cannot fail for a query the build system
    // itself resolved, and both "native" and "baseline" are the spellings
    // `Target.Query.parseCpu` recognises (`std/Target/Query.zig:280-283`).
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // `b.graph.zig_exe` is the compiler running this build script, so the
    // nested build is the same toolchain rather than whatever is on PATH.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    // The delivery the caller asked for, in full: `static` is a real answer
    // here, not the absence of one.
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(options.requested_linkage)}));
    // And how the facade reaches that artifact, which is a separate question
    // and may be either value while the linkage above stays as it is.
    run.addArg(b.fmt("-Druntime={s}", .{if (options.runtime_loaded) "true" else "false"}));
    // Box2D's own compile-line configuration, as the three requests the caller
    // made. Each of them reaches the nested dependency through the consumer's
    // own options and nothing else.
    run.addArg(b.fmt("-Dvalidate={s}", .{if (options.validate) "true" else "false"}));
    run.addArg(b.fmt("-Ddisable-simd={s}", .{if (options.disable_simd) "true" else "false"}));
    run.addArg(b.fmt("-Davx2={s}", .{if (options.avx2) "true" else "false"}));
    // Forward the selected executor and its dynamic-linker support.
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // The nested build carries this workspace's job count in its own command
    // line, for the reason every `zig build` entry in `devenv.nix` writes one:
    // nothing can append a `-j` to a `Run` step's command, so a nested build
    // left to derive its own width takes `cpu_count - 1`
    // (`std/Io/Threaded.zig:1639`) instead, and the consumer this step proves
    // then compiles at a different width from the build that asked for it --
    // and at a different width again on whichever machine runs the gate.
    // `AGENTS.md:157-158` names `-j8`, `--cache-dir` and `--summary all` as
    // what every entry adds. `--summary` takes its value as a second token
    // (`lib/compiler/build_runner.zig:263-265`, documented at `:1639-1640`), so
    // it is written the same two-token way as the cache options around it.
    run.addArg("-j8");
    run.addArgs(&.{ "--summary", "all" });
    // A null `path` means "the current directory", and the working directory
    // is already the consumer package, so the default is right.
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // The global cache is the other directory this build was told about, and
    // the one the nested build could not see. `b.graph.global_cache_root`
    // (`lib/std/Build.zig:122`) is the directory the runner is handed at
    // `lib/compiler/build_runner.zig:54` and installed into the graph at
    // `:73-76` and `:89`, so a selection the caller made for it reached this
    // graph and stopped there, and the nested build resolved its own package
    // store outside it.
    //
    // Two tokens, and the path verbatim rather than a `/consumer` subdirectory
    // of it. `--global-cache-dir [path]` is the spelling the runner documents
    // (`lib/compiler/build_runner.zig:1675`) and the one the compiler emits
    // for every build step it spawns
    // (`lib/std/Build/Step/Compile.zig:1478-1479`). The subdirectory above is
    // right for the local cache, whose manifest directory two build graphs
    // must not share, and wrong here: the global cache is the shared package
    // store both builds are meant to read, and a subdirectory of it would make
    // the nested build materialise its own copy of every dependency.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArgs(&.{ "--global-cache-dir", global_cache });
    }
    // The caller's own install prefix, when it named one. Without it the
    // nested build resolves its own `zig-out`, which is a build artefact
    // inside `consumer/` rather than the place the caller asked for. The
    // default is this build's `<build root>/zig-out`, and a relative
    // `--prefix` would resolve against `consumer/` instead of against this
    // build's root, so a non-default prefix is made absolute before it is
    // handed on. `DESTDIR` needs no forwarding: the nested build inherits the
    // environment this one ran with.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    // The caller's own arguments, last and behind `--`. Everything above is
    // this package's negotiation with the nested build; an argument the caller
    // typed is forwarded verbatim or not at all, and `zig build consumer
    // -Druntime=true -- --provider <path>` is how the loaded route names the
    // shared object the consumer program then loads
    // (`consumer/src/main.zig:439-451`), the way the `smoke` step already hands
    // them to the example program. The `--` follows every forwarded option
    // because that is what ends the nested runner's own parsing
    // (`lib/compiler/build_runner.zig:428-430`), and it is emitted only when
    // there are arguments to carry.
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    // The nested build is the step's only observable effect.
    run.has_side_effects = true;
    return run;
}

/// True when this build can execute `target`'s binaries: the question
/// `std.Build.Step.Run` asks about the artifact it is about to spawn, asked
/// here of the resolved target with the same libc and runtimes facts.
fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // QEMU reaches a foreign dynamic linker only with `--libc-runtimes`.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
        // Without a runtimes directory `Run` fails a foreign GNU-libc target
        // rather than skipping it, so that one case answers no.
        .qemu => !candidate.isGnuLibC() or b.libc_runtimes_dir != null,
        .wine, .wasmtime, .darling => true,
        .bad_dl, .bad_os_or_cpu => false,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as a static archive (the default, and what " ++
            "upstream's own build produces) or as a real shared object with " ++
            "upstream's soname libbox2d.so.3. This selects the delivery and " ++
            "never the dispatch: the same C is compiled either way.",
    );

    // upstream leaves `BUILD_SHARED_LIBS` unset, and `CMakeLists.txt:101` only
    // adds the unit tests when `NOT BUILD_SHARED_LIBS`, so a caller who passes
    // nothing gets the graph in which upstream's own test entry exists.
    const requested_linkage: std.builtin.LinkMode = linkage_option orelse .static;

    const options: Options = .{
        .requested_linkage = requested_linkage,
        .validate = b.option(
            bool,
            "validate",
            "Compile Box2D's heavy validation switch (upstream BOX2D_VALIDATE). " ++
                "Default true, which is upstream's own default at " ++
                "CMakeLists.txt:66 and what upstream's CI configures. Private " ++
                "to the library's compile line; no public header changes.",
        ) orelse true,
        .disable_simd = b.option(
            bool,
            "disable-simd",
            "Compile the scalar math only (upstream BOX2D_DISABLE_SIMD). " ++
                "Default false, upstream's own default at CMakeLists.txt:43.",
        ) orelse false,
        .avx2 = b.option(
            bool,
            "avx2",
            "Compile Box2D's AVX2 vector width on x86_64 (upstream BOX2D_AVX2). " ++
                "Default false, upstream's own default at CMakeLists.txt:47. " ++
                "Ignored where upstream would not offer it: off x86_64, and " ++
                "while -Ddisable-simd is on.",
        ) orelse false,
        // `-Druntime` selects the *dispatch*, and it is orthogonal to
        // `-Dlinkage`: the option says which artifact this build delivers and
        // installs, this one says whether the facade calls it through a link
        // line or through a table an explicit `load` fills. Under `-Druntime`
        // nothing is linked into the module at all, so a caller may name a
        // provider this tree did not build -- and the artifact is still built
        // and installed, so a caller may equally name the one it did.
        .runtime_loaded = b.option(
            bool,
            "runtime",
            "Resolve the native entry points at run time instead of linking them. " ++
                "The facade keeps the same translated header and the same public " ++
                "types; each selected native function becomes a dispatch through " ++
                "one process-lifetime table that an explicit load(source) fills, " ++
                "and the module links no archive. Independent of -Dlinkage, which " ++
                "still decides which artifact this build delivers and installs. " ++
                "Default off, and a linked build is unchanged in every respect.",
        ) orelse false,
    };

    // A requested shared object on a target whose OS has no dynamic linker is
    // refused here, at configure time, before a single file is compiled. The
    // alternative — building a static archive and telling the caller it was
    // shared — hands back an artifact that is not the one that was asked for,
    // under a `box2d.pc` and a soname that would describe it. This is a
    // configuration error, not a fallback, so it ends the configure with a
    // message naming the target and the way out rather than a warning and a
    // different result. `zig build check -Dlinkage=dynamic` is unaffected: the
    // target it selects here is the native one, and `addTargetCheck` handles
    // each matrix target separately.
    if (!targetCanCarry(target, options.requested_linkage)) {
        std.debug.print("error: {s}\n", .{unsupportedLinkageReason(b, target)});
        std.process.exit(1);
    }

    // `build.zig.zon .version` and the version this build stamps into
    // `box2d.pc`, names into the shared object's file name and documents in
    // three other places are one fact. `std.SemanticVersion.parse` fails loudly
    // rather than wrapping a non-version, and the comparison catches a manifest
    // edited without the source it describes.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of CMakeLists.txt and src/core.c; see UPSTREAM.md");
    }

    const built = addGraph(b, target, optimize, options, true);
    const graph = built.graph;

    // The installed C library and, through `installHeader` in
    // `addCoreLibrary`, the six public headers under `include/box2d/`.
    b.installArtifact(graph.c_lib);

    // The rest of the delivery, not just the archive. A shared object with no
    // pkg-config metadata and a package with no licence material beside the
    // binary are both source drops, not packages: one leaves a C consumer no
    // `-lbox2d` to resolve and the other removes an obligation a private
    // repository does not remove.
    addPkgConfig(b, target, options.requested_linkage);
    installLicenceRecords(b);

    // Upstream's benchmark tool, which is the one useful non-graphical native
    // program this package carries. It needs the vendored enkiTS closure, so it
    // is null only for a target whose C++ library has no `std::thread`, and
    // that case is printed below rather than left as a missing file.
    const benchmark = addBenchmark(b, target, optimize, graph, built.tools, "box2d-benchmark");

    // `zig build` also compiles the example. The example is the cheapest thing
    // that proves the facade, the translated headers and the C archive agree on
    // types, symbols and link-time dependencies. It is compiled, not installed:
    // it is a proof, not a deliverable.
    const example = b.addExecutable(.{
        .name = "box2d-smoke",
        .use_llvm = llvm_required,
        .root_module = programModule(b, target, optimize, graph.module, example_source),
    });
    b.getInstallStep().dependOn(&example.step);

    // A run artifact already depends on building the executable, which depends
    // on compiling the C and linking the facade. `zig build smoke` deliberately
    // does not depend on the install step: installing is `zig build`'s job and
    // conflating the two would make a smoke run depend on the install layout.
    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // The test root is `tests.zig`, which names the test blocks; a root that
    // only re-exported them would discover no tests and still exit zero.
    // `addRunArtifact` is used rather than a plain compile so that this is a
    // real runnable test step for whatever `-Dtarget` names: a foreign target
    // is left to whichever executor the cross-test harness detects, and this
    // build does not decide that.
    const unit_tests = b.addTest(.{
        .name = "box2d-tests",
        .use_llvm = llvm_required,
        .root_module = programModule(b, target, optimize, graph.module, test_source),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;

    // Upstream's own suite is part of `test`, not a separate gate nobody runs:
    // `test/main.c` is the entry point upstream's own CI executes as
    // `./bin/test`, and the whole point of carrying it is that it runs.
    const test_step = b.step("test", "Run this fork's Zig tests and upstream's own unmodified test/main.c suite");
    test_step.dependOn(&run_tests.step);

    if (addUpstreamTest(b, target, optimize, graph, built.tools, "box2d-upstream-test")) |suite| {
        const run_suite = b.addRunArtifact(suite);
        run_suite.has_side_effects = true;
        run_suite.step.name = b.fmt("test/main.c ({s})", .{@tagName(target.result.os.tag)});
        test_step.dependOn(&run_suite.step);
        b.step("upstream-test", "Build and run upstream's own unmodified test/main.c suite on its own")
            .dependOn(&run_suite.step);
    } else {
        // A target with no C++ threads cannot build upstream's suite, and that
        // is reported rather than hidden: `upstream-test` exists and fails with
        // the reason, instead of passing because it did nothing. `test` also
        // depends on the same failure, because `test` claims to run that suite.
        const no_threads_reason =
            "box2d: upstream's own test/main.c suite needs extern/enkiTS, whose " ++
            "TaskScheduler.h includes <thread>; this target's C++ library has " ++
            "no threads. The core library, the facade, tests.zig and smoke.zig " ++
            "are still built for it.";
        test_step.dependOn(&b.addFail(no_threads_reason).step);
        b.step("upstream-test", "Build and run upstream's own unmodified test/main.c suite on its own")
            .dependOn(&b.addFail(no_threads_reason).step);
    }

    // The benchmark tool on its own, for a driver that wants to build it
    // without installing. It installs with the library when it exists.
    if (benchmark) |tool| {
        b.getInstallStep().dependOn(&tool.step);
        b.installArtifact(tool);
        b.step("benchmark", "Build upstream's benchmark/main.c tool").dependOn(&tool.step);
    }

    // Build the separate consumer package; run it only where this host can
    // execute the selected target, and install it otherwise.
    b.step("consumer", "Build the consumer/ package for the selected target, and run it when this host can execute it")
        .dependOn(&runConsumer(b, target, optimize, options).step);

    // The cross target gate. Compiling the tests, the example, upstream's own
    // suite and the benchmark for each target is what makes this a check of the
    // facade rather than of an unreferenced archive, and `addTargetCheck` says
    // why. Nothing runs here.
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests, the example, upstream's own " ++
            "C suite and the benchmark tool for the six-target matrix without " ++
            "running any of them",
    );
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, target.query, optimize, options);
    } else {
        for (check_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, options);
        }
    }

    // Which configuration this is, and which artifact it hands back, are facts
    // worth reading out of the build rather than inferring from a cache
    // directory. These are configure-time lines, not gate results: nothing has
    // been compiled when they print.
    //
    // The answer `coreMacros` gives for this target, read once here and taken
    // from the same function there, so this line cannot report a configuration
    // the compile line did not get.
    const scalar = scalarMath(target, options);

    std.debug.print(
        "box2d: {d} core translation units from {s}/, C17, {s}{s}{s}, {d} public headers" ++
            ", {d} fork source from {s}/\n",
        .{
            core_sources.len,
            source_dir,
            if (options.validate) "BOX2D_VALIDATE" else "no BOX2D_VALIDATE",
            if (scalar)
                ", BOX2D_DISABLE_SIMD"
            else if (options.avx2 and target.result.cpu.arch == .x86_64)
                ", BOX2D_AVX2 -mavx2"
            else
                "",
            if (scalar and options.avx2)
                " (BOX2D_AVX2 ignored: upstream's cmake_dependent_option requires NOT BOX2D_DISABLE_SIMD)"
            else
                "",
            public_headers.len,
            bridge_sources.len,
            bridge_dir,
        },
    );

    // Which target these lines describe, and whether the scalar math path was
    // the caller's request or this build's own answer for the target. Both are
    // facts a reader of a cross run otherwise has to infer, and the second one
    // is the difference between a caller who asked for `-Ddisable-simd` and a
    // target that needed it.
    const configured_triple = target.result.zigTriple(b.allocator) catch
        @panic("box2d: unspellable target");
    std.debug.print(
        "box2d: target {s}, optimize {s}, Zig code generator LLVM on every Zig root\n",
        .{ configured_triple, @tagName(optimize) },
    );
    if (scalar and !options.disable_simd) {
        std.debug.print(
            "box2d: BOX2D_DISABLE_SIMD is on although -Ddisable-simd was not passed: " ++
                "{s} cannot include <arm_neon.h> with this toolchain (see armNeonNeedsScalar)\n",
            .{configured_triple},
        );
    }
    // Typed, because the two arms are a `*const [N:0]u8` and a `[]u8` and a
    // switch has to settle on one type before either is printed.
    const delivery: []const u8 = switch (options.requested_linkage) {
        .static => "static archive libbox2d.a (default)",
        .dynamic => b.fmt("shared object, soname libbox2d.so.{d}", .{soversion.major}),
    };
    std.debug.print("box2d: {s}\n", .{delivery});
    if (options.avx2 and target.result.cpu.arch != .x86_64) {
        std.debug.print(
            "box2d: -Davx2 is ignored for {s}: upstream only offers BOX2D_AVX2 when the processor matches x86_64 (CMakeLists.txt:46-48)\n",
            .{@tagName(target.result.cpu.arch)},
        );
    }
    if (options.runtime_loaded) {
        // Dispatch is a separate fact from delivery, and a runtime-loaded
        // build links nothing into the module: the caller names a provider
        // with an explicit `load(source)` and the symbols arrive through the
        // platform loader. Printing it here is what keeps "the library is
        // still built and installed" from reading as "the module links it".
        std.debug.print(
            "box2d: runtime-loaded dispatch (-Druntime=true); no library is linked into the module, " ++
                "and a provider is named by an explicit load(source)\n",
            .{},
        );
    }

    if (built.tools.enki == null) {
        std.debug.print(
            "box2d: {s} has no C++ threads, so extern/enkiTS, upstream's own test/main.c suite and the benchmark tool are not built for it\n",
            .{@tagName(target.result.os.tag)},
        );
    }
    if (benchmark == null) {
        std.debug.print(
            "box2d: bin/box2d-benchmark is not installed: {s} has no C++ threads\n",
            .{@tagName(target.result.os.tag)},
        );
    }
}
