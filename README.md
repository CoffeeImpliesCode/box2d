# Box2D — a Zig SDK

Box2D 3.1.1, the official `erincatto/box2d` 2D physics engine, built as a
standalone Zig SDK: the complete upstream C core compiled by this repository's own
build graph, a typed Zig surface over the whole public API, an optional
runtime-loading route, and separate static and shared Nix packages.

Upstream is MIT. This fork's own files are MIT. See `NOTICE.md` for the
per-file inventory and `FORK-LICENSE.md` for the fork grant.

| Record | What it holds |
| --- | --- |
| [`UPSTREAM.md`](UPSTREAM.md) | the pin, the full source inventory, the vendored trees |
| [`NOTICE.md`](NOTICE.md) | every licence term and copyright notice, per file |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the owner's grant for the fork-authored files |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 267 digests of the carried bytes; `sha256sum -c UPSTREAM.sha256` |
| [`CHANGELOG.md`](CHANGELOG.md) | the numbered change history |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the working record, including open items |
| [`README.zig.md`](README.zig.md) | the Zig interface: options, both routes, the typed surface, the ABI boundaries |
| [`README.upstream.md`](README.upstream.md) | upstream's own README, byte for byte |

**Status.** Results exist on this host for the shared install whose library the
runtime gate then loaded, for the linked `zig build smoke test`, for the
runtime-loaded dispatch with a **static** delivery against a shared provider
named explicitly from outside this tree, for `zig build test smoke install` in
all four optimize modes and both linkages, for nine cases of the `consumer`
route, and for the two Nix derivations. Section 3 gives each of them a row and
its own bound. What has not been run is named there too: the `smoke`
runtime-loaded branch with a shared delivery, any runtime-loaded branch outside
`Debug`, a direct `cd consumer` entry, a filtered fetched package, a standalone
`zig build upstream-test`, the two compile matrices and the devenv entries.
Nothing in this document reports a run that did not happen.

---

## 1. Native-source deviations

**None.**

No file under `src/`, `include/`, `test/`, `shared/`, `benchmark/`, `samples/`,
`docs/` or upstream's vendored `extern/glad` and `extern/jsmn` has been edited.
Every one of them is byte-identical to upstream `v3.1.1`
(`8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`) and is pinned in
`UPSTREAM.sha256`, which was observed passing 267/267 with 0 failures.

The one upstream file the fork does extend is `.gitignore`, so that upstream's own
ignore patterns keep working alongside the fork's. Its pristine upstream digest
is recorded in `UPSTREAM.md`; it is deliberately not pinned in
`UPSTREAM.sha256`, because pinning a file the contract requires the fork to
extend would report an ordinary review edit as an integrity failure.

`build_support/box2d_inline_bridge.c` is the mirror image of that exception: a
translation unit this fork authors that upstream does not ship, kept outside
every upstream tree so the "none" above stays true. Deviation 13 below says what
it is for and why it is not a second implementation of anything.

---

## 2. Native-build deviations

Each of these is a deliberate departure from upstream's own build system, with
the source line that motivates it. Dated history is in
[`CHANGELOG.md`](CHANGELOG.md).

| # | Deviation | Why |
| --- | --- | --- |
| 1 | Upstream's CMake build is not invoked. The full core closure is compiled by `build.zig`, with no CMake, Make or autotools target and no build-time download | a source-built SDK may not fetch anything at build time |
| 2 | enkiTS is vendored at `extern/enkiTS/`, revision `404a3bf8f855039dfff2052184d6308655286c07`, rather than fetched | upstream fetches it with an **unpinned** `GIT_TAG master` (`CMakeLists.txt:88-95`) |
| 3 | No CMake package export is installed — neither `lib/cmake/box2d/box2dConfig.cmake` nor `box2dConfigVersion.cmake` | upstream generates them through `install(EXPORT ...)` (`src/CMakeLists.txt:202-223`); hand-writing a second packaging dialect is not this contract's job. pkg-config metadata is installed instead |
| 4 | `lib/pkgconfig/box2d.pc` is fork-authored | upstream ships no `.pc.in` at this pin, so the file's field set is this fork's |
| 5 | No system-integration option | not applicable to this SDK. It is **not** a satisfied gate; nothing here links an installed system library |
| 6 | No profiling option | upstream's `BOX2D_PROFILE` links TracyClient, fetched from the network (`src/CMakeLists.txt:106-117`) |
| 7 | The graphical samples are not built | they need GLFW 3.4 and imgui v1.91.3 fetched at build time (`samples/CMakeLists.txt:20-51`). The samples are carried for audit, unmodified |
| 8 | The unit tests are always built; there is no knob | upstream builds them by default, and gates here depend on them |
| 9 | Upstream's `build.sh`, `build_emscripten.sh`, `create_sln.bat` and `deploy_docs.sh` are carried but never run | they are upstream's build system, kept byte-exact for audit |
| 10 | Upstream's Debug postfix is not reproduced: a CMake Debug build emits `libbox2dd.a`, this one emits `libbox2d.a` in Debug too | `src/CMakeLists.txt:88` and `:97` set `CMAKE_DEBUG_POSTFIX "d"`. Reproducing it would make the installed Debug tree unlinkable by the `-lbox2d` its own `box2d.pc` names |
| 11 | No `RelWithDebInfo` counterpart: `B2_ENABLE_ASSERT` is not added as a public define | `src/CMakeLists.txt:140` adds it under `$<$<CONFIG:RELWITHDEBINFO>:...>` for MSVC only. Zig has no such configuration and this package never targets the MSVC ABI, so there is no counterpart to reproduce; adding one would change upstream's compiled behaviour. What does hold: `NDEBUG` reaches `include/box2d/base.h:101` and `src/core.c:62-67` from the optimize mode alone, so the optimize mode alone selects whether `b2InternalAssertFcn` is compiled at all |
| 12 | `-ffp-contract=off` is applied to every translation unit unconditionally, not under upstream's `MINGW OR APPLE OR UNIX` guard | upstream's guard (`CMakeLists.txt:37-41`) sits at directory scope above `src`, `shared`, `test` and `benchmark`, so the set of files it reaches is identical — the core, the shared support library, upstream's test suite and `benchmark/main.c`. The guard's only excluded OS tags are MSVC and Emscripten, and this build graph can produce neither: Zig has no MSVC ABI target and Emscripten is not emulated. Every target it does produce — including `wasm32-wasi` and `x86_64-windows-gnu`, which is MinGW — gets the flag either way, so observable behaviour is identical |
| 13 | `build_support/box2d_inline_bridge.c` is compiled into the core module, beside the 35 upstream translation units | `include/box2d/math_functions.h:625` declares `b2MakeAABB` `B2_INLINE`, and `include/box2d/base.h:33` makes that `static inline`, so nothing this build compiles puts the name in a symbol table — upstream never needed one, because `src/world.c:2159` reaches it through the header. Zig 0.16's `translate-c` compiles 72 of the 73 inline bodies the six public headers declare and cannot compile that one: its first statement is `B2_ASSERT( count > 0 )` (`math_functions.h:627`), `B2_ASSERT` calls `B2_BREAKPOINT` (`base.h:103-109`), and `B2_BREAKPOINT` is `__builtin_trap()` (`base.h:94`), so the whole function is demoted to an `extern` declaration of a symbol nothing defines. The bridge renames the name around one `#include`, undoes the rename, and exports a definition that calls the header's own body — upstream's bytes at upstream's line numbers, not a second algorithm that could drift from it. Being part of the core, one definition serves the static archive, the shared object, and the second static archive a `-Dlinkage=dynamic` build compiles for upstream's own suite |

`box2d.pc` records `Libs: -L"${libdir}" -lbox2d -lm`, with `-lm` present only on
the targets whose core system libraries include libm — Linux and the
BSD/illumos/Solaris family — and absent on macOS, the iOS family and Windows.
`include/box2d/math_functions.h:9` includes `<math.h>` and the scalar paths call
`sinf`, `cosf` and `atan2f`, which live in libm on glibc and musl. There is no
`Libs.private`: the same file has to describe the static install, where the
consumer's own link line is the only place libm can come from. A shared install
does not strictly need `-lm` — the `.so` records its own `DT_NEEDED` — but the
one file serves both.

### Installed closure

Written by the build graph, once, for every linkage variant:

```
lib/libbox2d.a                                            (static)
lib/libbox2d.so.3.1.1, libbox2d.so.3, libbox2d.so         (ELF dynamic; VERSION 3.1.1, SOVERSION 3)
lib/libbox2d.3.1.1.dylib, lib/libbox2d.dylib             (Darwin; install name @rpath/libbox2d.3.1.1.dylib)
bin/box2d.dll, lib/box2d.lib                              (Windows-gnu dynamic; no .so symlinks)
include/box2d/{base,box2d,collision,id,math_functions,types}.h
lib/pkgconfig/box2d.pc
bin/box2d-benchmark                                       (every non-WASI target)
share/licenses/box2d/{LICENSE,NOTICE.md,FORK-LICENSE.md,UPSTREAM.md,FORK-NOTES.md,enkiTS-License.txt}
```

`enkiTS-License.txt` is the vendored task scheduler's zlib notice: the benchmark
tool links enkiTS, and enkiTS's third condition is that its notice may not be
removed from a source distribution.

Those are six files, and `build.zig` installs all six in every linkage and
optimize mode: `LICENSE` is upstream's own text, the four `.md` files are this
fork's licence and provenance records, and `enkiTS-License.txt` is enkiTS's own
grant renamed on the way so it cannot be read as a second `License.txt` beside
Box2D's. `package.nix` names the same six in its `licenseFiles`
(`package.nix:68-75`), and its `installCheckPhase` asserts each of them is
present and non-empty (`package.nix:185-190`), so the packaging layer checks the
whole set rather than a copy of it.

`bin/box2d-benchmark` is installed in every linkage and optimize mode on every
target except `wasm32-wasi`, where
`extern/enkiTS/src/TaskScheduler.h:22` includes `<thread>` and Zig 0.16's WASI
C++ library has none. The build graph prints that on its configure line. This
affects the cross matrix, not the Nix outputs: `package.nix` refuses a cross
stdenv and every entry point offers only Linux and Darwin systems.

`UPSTREAM.sha256` is deliberately **not** installed. It is a repository
integrity record, not material that ships with a library.

The VERSION/SOVERSION values are upstream's own, from `src/CMakeLists.txt:96-97`.
`package.nix` asserts the headers, the library, the `.pc`, the benchmark tool and
the licence files, and resolves the `.pc` with `pkg-config` rather than trusting
it.

---

## 3. Build, run and test matrix

Build status, run status and test status are separate things, and this section
records only what a command on this host actually printed. The four optimize
columns are filled where the native final matrix ran, which is native and
linked only; the runtime-loaded and consumer rows are `Debug` only, and each
row says which. This SDK is new in this wave, so there is no earlier history to
carry forward and the "pending" columns are not inherited — they are simply
unrun.

| Gate | Command | Debug | ReleaseSafe | ReleaseFast | ReleaseSmall | Historical |
| --- | --- | --- | --- | --- | --- | --- |
| Build and install, static | `zig build` | **observed** in all four modes: the native matrix run installed into a fresh prefix per cell, 15 files each | **observed**, same run | **observed**, same run | **observed**, same run | none |
| Build, install, shared | `zig build -Dlinkage=dynamic --prefix …` | **observed** in all four modes, 17 files per cell including `libbox2d.so`, `libbox2d.so.3` and `libbox2d.so.3.1.1` | **observed**, same run | **observed**, same run | **observed**, same run | none |
| Behavioural tests and example | `zig build smoke test` | **observed**: upstream's full C suite passed, this package's 14 SDK tests passed, and the smoke program ran and held every value it checks | **observed**, same run | **observed**, same run | **observed**, same run | none |
| Runtime-loaded dispatch, static delivery | `zig build smoke -Druntime=true -Dlinkage=static -- --provider …` | **observed**: 6/6 build steps and the smoke program ran through the generated dispatch | pending | pending | pending | none |
| Runtime-loaded dispatch, shared delivery | the same with `-Dlinkage=dynamic` | pending | pending | pending | pending | none |
| Upstream's own C tests alone | `zig build upstream-test` | not run on its own; its suite ran inside `zig build test` above | pending | pending | pending | none |
| Six-target compile matrix | `zig build check` | **observed** once, 2026-10-05: exit 0, `Build Summary: 61/61 steps succeeded`, all six declared targets compiled and linked, nothing run | not run per mode | not run per mode | not run per mode | observed 2026-10-05 |
| 53-platform matrix | `cross-test` | **observed** once, run `20261004T221720228710Z-45046`: 6 pass, 31 build-only, 5 build failures, 11 run failures of 53, `Debug` only | not run per mode | not run per mode | not run per mode | observed 2026-10-04 |
| Consumer package | `cd consumer && zig build run` | **observed** only through the SDK route `zig build consumer`, which nests this same command, or `zig build install` for a target this host cannot execute: nine cases, eight passing and one refusal. A direct `cd consumer` entry has not been run | pending | pending | pending | none |
| Installed C consumer | against `$out`, via `pkg-config` | pending | pending | pending | pending | none |
| Fetched Zig consumer | `consumer/`, path dependency | pending — the nine cases below build the published path dependency from this tree, and no filtered fetched package has been materialised | pending | pending | pending | none |
| Nix static derivation | `nix build .#static` | — | **observed**, both variants realised in one run | — | — | observed 2026-10-04 |
| Nix shared derivation | `nix build .#shared` | — | **observed** in that same run | — | — | observed 2026-10-04 |
| devenv outputs | `devenv build outputs.static` / `.shared` | — | pending | — | — | none |
| Source integrity | `sha256sum -c UPSTREAM.sha256` | **267/267, 0 failures** | — | — | — | observed 2026-10-04 |

The runtime row is one command, not six:

```sh
zig build smoke -Druntime=true -Dlinkage=static -- \
  --provider /home/tmp2/gertullj/scratch/foundation-libs/contract-physics-lua/box2d-shared/lib/libbox2d.so.3.1.1
```

Its `6/6` is the dependency-step count from the build summary line
(`local://foundation-contract-box2d-current-canonical-runtime-static-real-provider-smoke.log`).
That command builds neither the delivered artifact nor the provider: a
runtime-loaded module links nothing, so the provider is a Box2D shared object
installed by a `-Dlinkage=dynamic` build of this tree into a scratch prefix
outside the repository, and it is named explicitly rather than found.

The two consumer rows are one proof run, not two commands. The driver's
nested-delivery proof ran nine cases against this package on 2026-10-04: the
four routes, a static and a dynamic delivery each with the linked and the
runtime-loaded dispatch, each of them twice, once with the caller's `-Dtarget`
and `-Dcpu` omitted and once with them named, plus a ninth case that hands the
loaded route no provider at all. Eight exited 0 with the consumer program
reporting that every value matched the expectation derived for it. The ninth
exited 1 and printed the missing-provider refusal `consumer/src/main.zig`
declares.

What a case establishes is bounded to the handover. Every nested command line
carried `-j8`, `--summary all`, the local cache under the caller's cache root,
the caller's global cache and the caller's `--prefix`, and each of the nine
records the prefix as not resolving into this repository. The linked cases
needed no provider. The loaded cases named one with `--provider` after `--`,
with every provider variable absent from the child environment, so each loaded
route came from the command line and not from a variable. Two things this run
is not. It built the published path dependency from this tree, so it is
evidence for the `Consumer package` row and not for the `Fetched Zig consumer`
row. And it is `Debug` on one host, with one explicitly named `x86_64-linux-gnu`
and `baseline` as the only non-default target, so it says nothing about
`check` in either linkage, about `cross-test` or about the devenv rows.

One field of that receipt is an erratum in the driver, not a fact about this
package: its top-level `status_note` still carries the template sentence
"SOURCE ONLY: this driver has never been executed", while every case record
carries `plan_only: false`, a start and a finish timestamp, an exit code and
the program's own output. A new driver is expected to drop that sentence. This
section rests on the case records.

The four-mode rows come from a separate run. The native final matrix
(`native-final-evidence/contract-final-after-20261004/run.json`, 2026-10-04,
176 cells over 22 SDKs, 144 pass and 32 not passed) gave this package eight
cells, and all eight passed: `zig build test smoke install` in each of the four
optimize modes and both linkages, every one with `-Druntime=false` because the
run's policy is native and linked only and nothing was opened through the
platform loader. The four static cells each printed `Build Summary: 27/27 steps
succeeded; 14/14 tests passed`, the four dynamic cells `29/29 steps succeeded;
14/14 tests passed`, and every cell carried `test success` and `smoke success`
with 77 lines of program output. Each static cell installed 15 files and each
dynamic cell 17: the six public headers, `box2d.pc`, six licence and upstream
files, and `lib/libbox2d.a` in the static case or `lib/libbox2d.so`,
`lib/libbox2d.so.3` and `lib/libbox2d.so.3.1.1` in the dynamic one. The run
recorded the whole tree's compiled-input closure at 6070 files before and after
with one digest, so nothing in the source moved while it ran. The 32 cells
that did not pass belong to geographiclib-c, libunibreak, predicates and ryu,
and none of them to this SDK.

Boundaries on what the observed rows establish. Every Zig row above is on this
host: the four-mode rows are the native matrix run, and the runtime-loaded and
consumer rows are `Debug` only. The pre-load panic is a source fact rather than
a result in ReleaseFast and ReleaseSmall. The two Nix rows are `ReleaseSafe`,
because `package.nix:116` builds with `-Doptimize=ReleaseSafe` and with no
other value. And in the matrix rows, a successful foreign compile is
`build_only`, not a passing test, and a cell with no runtime is not a pass
either.

### The target matrix and the six-target baseline

Two gates were run over this tree with the harness's own `--jobs 8 --build-jobs
8`. Both hold one source stamp for the whole run, so both are evidence about the
tree at that stamp and about nothing later.

`zig build check` over the six declared compile targets exited 0 with `Build
Summary: 61/61 steps succeeded` and no failing step. Label `baseline-box2d-check`
in baseline run `20261005T014547Z-797a73f2`, 2026-10-05. It compiles and links
and runs nothing, so it is compile evidence.

`cross-test` over the published 53-target table exited 1. Run
`20261004T221720228710Z-45046`, receipt `box2d-53-target-8.json`, source stamp
`49e9048898…` before and after. Of the 53 cells, **6 pass**, **31 are
build-only**, **5 fail to build** and **11 fail their run**. A build-only cell
compiled and had no runner. It is not a passing test.

The 5 build failures are two families. `aarch64-netbsd` and `aarch64_be-netbsd`
stop inside `translate-c` with `use of undeclared identifier '__int128_t'` at
`box2d-translate.zig:3590:43`, reached from a preprocessed macro in the
compiler's own vendored NetBSD header. `aarch64_be-linux`, `armeb-linux` and
`thumbeb-linux` report `build=timeout` at the harness's 3600 s limit, and each
of their logs ends on the line `Starting Box2D unit tests`.

The 11 run failures are two families, and they are different things. Five of
them, `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux` and
`s390x-linux`, fail inside upstream's own C suite with `Assertion failed: false
(test/test_determinism.c: SingleMultithreadingTest: 125)`. On `mips-linux` this
package's own Zig suite still reports `14 pass (14 total)` in the same run.

The other six, `hexagon-linux`, `loongarch64-linux`, `mips64el-linux`,
`powerpc64le-linux`, `riscv32-linux` and `x86-linux`, fail only where Zig calls
the C library. Each of those six logs prints `All Box2D tests passed!` for the
pure-C run first, and then the C library traps while reading a definition
pointer that Zig supplied: `member access within misaligned address 0x1 for
type 'const b2BodyDef'` at `src/body.c:179`, `Illegal instruction` on the same
`B2_CHECK_DEF`, and `Segmentation fault` on `powerpc-linux`. The structs this
SDK exchanges are aliases of the translated ones (`zig/root.zig:375-635`), so no
hand-written layout in this tree can disagree with C.

**What these receipts do not cover.** Each run holds one source stamp. Every
build-graph, header, helper and normalisation edit made after a run describes a
tree that run never saw, including the entries `CHANGELOG.md` records for
2026-10-05. Nothing above is a platform-support claim for a cell that did not
execute.

Two eight-cell waves from the same night, native and linked against this tree's
own provider: `native-final-evidence/20261004T233628757747Z-69351` gives **8 of
8 `exit 0`**, each `27/27 steps succeeded` static and `29/29` dynamic, each
`14/14 tests passed`, with `-Druntime=false` because nothing was opened through
the platform loader. `loaded-final-evidence/20261004T232823091897Z-23133` gives
the same eight shapes under `-Druntime=true`: **8 of 8 `pass`**, each `29/29`
static and `30/30` dynamic, each `14/14 tests passed`.

The two Nix rows are one observed run rather than two: `nix build
--no-write-lock-file --no-link --json --cores 8 --max-jobs 2
path:<this package>#static path:<this package>#shared` from a scratch directory,
exit 0, two `drvPath`s and two realised store outputs
(`box2d-nix-build.log`, run `nix-acceptance-20261004T175328Z`, 2026-10-04).
`path:` and `.` name the same tree, and `.` is the spelling that would refuse to
see this uncommitted working copy. That run establishes that the derivations
evaluate and build; it is not a substitute for the `devenv outputs` row, which
has never been run, nor for `devenv build outputs.static`, which reaches the
same `package.nix` through a different entry point.

Unresolved source prerequisites and integration needs are listed in
[`FORK-NOTES.md`](FORK-NOTES.md).

---

## 4. Consumption

### As a Zig package dependency

The public module is named **`box2d`**.

```zig
// build.zig.zon
.dependencies = .{
    .box2d = .{ .path = "../box2d" },
},

// build.zig
const box2d = b.dependency("box2d", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("box2d", box2d.module("box2d"));
```

```zig
const box2d = @import("box2d");

pub fn main() !void {
    var world_def = box2d.defaultWorldDef();
    const ground = try box2d.createWorld(&world_def);

    var body_def = box2d.defaultBodyDef();
    _ = try box2d.createBody(ground, &body_def);

    for (0..60) |_| box2d.worldStep(ground, 1.0 / 60.0, 8);
}
```

The whole typed surface is listed in
[`README.zig.md` §4](README.zig.md). Every call is available on the raw route
too: `box2d.c.b2CreateWorld(...)`.

### Runtime loading

Build with `-Druntime=true` and name the provider explicitly. There is no
fallback from a path to a system lookup, no owning handle and no unload:

```zig
const box2d = @import("box2d");

try box2d.load(.{ .path = "/usr/local/lib/libbox2d.so.3.1.1" });
// or: try box2d.load(.{ .system = "libbox2d.so.3" });
```

Calling an ordinary Box2D function before a successful load panics, in all four
optimize modes, and the panic names the function that was reached for.

`-Druntime` and `-Dlinkage` are independent axes, and `-Dlinkage` keeps meaning
what this tree **delivers and installs** even in the row where the module links
nothing:

| `-Dlinkage` | `-Druntime` | What the module calls | What the caller supplies |
| --- | --- | --- | --- |
| `static` | `false` | the compiled-in `libbox2d.a` | nothing |
| `dynamic` | `false` | the compiled-in `libbox2d.so.3` | nothing |
| `static` | `true` | the generated dispatch table | a loadable shared object; this build installs the archive and builds no provider for it |
| `dynamic` | `true` | the generated dispatch table | a loadable shared object; the one this build installs will do |

The table describes what each configuration *is*, not that each has been run.
Section 3 records which cells have results behind them; the third row is the one
that does so far.

A provider is opened by the platform loader, so it has to be one: a static
archive is not a loadable object, and the runtime-loaded row that delivers
`libbox2d.a` still needs a shared object from somewhere — this tree, another
build of it, or a distribution. That row is a configuration, not a degraded
one: the build graph neither builds a provider for it nor refuses it, and it
still compiles and installs the artifact the option asked for.
`README.zig.md` §3 states the rest of the loader's rules, including what a
`Debug` consumer requires of a provider.

### From C, or from anything with pkg-config

```sh
zig build install --prefix "$PREFIX"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags --libs box2d
```

`box2d.pc` is relocatable (`prefix=${pcfiledir}/../..`) and is the only link
metadata installed: it names `-lbox2d`, and `-lm` on the targets whose core
system libraries include libm. There is no CMake package export; see
deviation 3.

### Development environment

`devenv` is canonical:

```sh
devenv shell
devenv tasks run box2d:build
devenv build outputs.static
devenv build outputs.shared
```

The shell is tools only — entering it never builds the library. Both Nix
variants are defined from the same `package.nix` the flake uses, through
`outputs`, and are built on demand rather than at shell entry.

Every task and every script starts from this package's own directory, whatever
directory the caller invoked devenv from, because devenv runs a task and a
script with the *caller's* working directory. That directory is not required to
hold `build.zig`, `UPSTREAM.sha256` or `consumer/`, and under the canonical
`devenv --from path:<this package>` run it is a scratch project holding none of
them. `box2d:build` and `box2d:install` are the two that install anything, and
they pass `--prefix "$ZIG_LOCAL_CACHE_DIR/box2d-prefix"`; every `zig build` task
and script passes `--cache-dir "$ZIG_LOCAL_CACHE_DIR/box2d"` and `-j8`, so a run
neither writes `zig-out/` nor leaves `.zig-cache/` in this repository.
`ZIG_LOCAL_CACHE_DIR` is exported by `enterShell`, filled in from the caller's
`TMPDIR` and never overridden, so the location stays the caller's and this tree
carries no path for it. `box2d:matrix` passes neither path flag, because
`cross-test.profile.sh` refuses to name a compiler cache or an output directory
and owns every path it uses; it does name the harness's own concurrency,
`--jobs 8 --build-jobs 8`, because neither this package nor
`cross-test.profile.sh` sets `CROSS_JOBS` or `CROSS_BUILD_JOBS` and the harness
defaults are `--jobs 2 --build-jobs 1`.

`nix build .#static` and `nix build .#shared` are the flake's equivalent;
`default` is `static`, this SDK's policy and upstream's own CMake default.

`flake.lock` is in this tree, and it pins the flake's one input rather than
leaving it floating: `nixpkgs`, locked to revision
`c7def046b9a883d46974757852106483d741586f` with a `narHash`, which is the same
revision `flake.nix:8-9` names in `inputs.nixpkgs.url`, so the lock and the
flake agree and neither can move alone. `devenv.lock` is **not** in this tree;
`devenv.yaml:31` pins a different input of its own
(`cachix/devenv-nixpkgs` at `c2f38fe7f9e04d9aadd354d380f2bd40531d9737`),
because a development shell resolves through devenv rather than through the
flake. That input is evaluated as a flake, and `devenv.yaml` carries no
`flake: false` on purpose: the key makes devenv's nixpkgs a plain source tree, a
plain source tree has no `lib`, and every devenv subcommand then stops in
bootstrap at `lib = nixpkgs.lib` with `error: attribute 'lib' missing`. Observed
for this SDK on 2026-10-04 — six devenv gates, exit 1 each, in the run
`nix-acceptance-20261004T175328Z` (`box2d-devenv-*.log`). The key is deleted and
the revision is byte-for-byte what it was.
`.gitignore:43-45` deliberately keeps both lock names out of its ignore
list: a lock is a real input, not build output. `package.nix:83-91`
filters `devenv.lock`, `flake.lock` and `.envrc.lock` (`:89`) out of the
derivation's own source, which is a separate axis and not a hole in the pin —
the flake frontend resolves the locked input before any derivation is handed a
source, so a derivation never needs the lock file itself.

The "no build-time download" in deviation 1 is a statement about `zig build`,
and there it is exact: that graph fetches nothing. A Nix evaluation still
resolves the pinned `nixpkgs` input, and `flake.lock` is what makes that
resolution a fixed revision rather than a branch. Section 3 records what the one
Nix run observed. Every devenv row there, and every entry point in this
subsection, is unrun since the `devenv.yaml` change, so none of it is a claim
about the current state of the development environment.

### The consumer package

```sh
cd consumer && zig build run
```

A linked consumer needs nothing. A runtime consumer needs a provider:
`zig build run -- --provider /abs/path/to/libbox2d.so.3.1.1`, or the
`BOX2D_TEST_PROVIDER` environment variable.

The consumer package declares the SDK's own options and forwards each one to
the dependency instead of accepting it and dropping it: `-Dtarget`, `-Dcpu`,
`-Doptimize`, `-Dlinkage`, `-Druntime`, `-Dvalidate`, `-Ddisable-simd` and
`-Davx2` (`consumer/build.zig`, where each is declared with `b.option` or read
from `standardTargetOptions` and `standardOptimizeOption`, reached from the SDK
side by `runConsumer` in `build.zig`). `-Dcpu` arrives with `-Dtarget` because
`standardTargetOptions` reads arch, OS, ABI and CPU model from separate `-D`
options (`lib/std/Build.zig:1473-1491`). None of the five Box2D options carries
a default in `consumer/`: an option left unset is not forwarded at all, so the
library's own default decides and this package never holds a second copy of one.
`zig build consumer -Ddisable-simd=true` and `zig build consumer -Davx2=true`
are therefore configurations the consumer really builds rather than flags it
silently ignores. `README.zig.md` §7 states the same for the consumer package
and §8 lists the commands.

`zig build consumer` is the one step that runs another build. `runConsumer` in
`build.zig` hands that nested build the target triple, the CPU model, the
optimize mode, the linkage, the runtime flag and the three Box2D compile-line
switches. It also forwards each of the five executor switches that is on, `-j8`,
`--summary all`, the local cache under a `consumer` subdirectory, and the
global cache the caller chose. A `--prefix` other than this build's default
`zig-out` is forwarded as well, made absolute first, so the nested build writes
outside the package rather than into `consumer/zig-out`. The caller's own
arguments follow behind `--`, and `consumer/build.zig` hands them to the
program. So `zig build consumer -Druntime=true -- --provider <path>` reaches
`consumer/src/main.zig` and names the shared object to load.

The nested sub-command is `run` when an enabled executor can execute the
resolved target and `install` when none can. An installed consumer is
`<prefix>/bin/box2d-consumer`: build-only evidence, not a run.

### Build options

| Option | Values | Default |
| --- | --- | --- |
| `-Dlinkage` | `static`, `dynamic` | `static` |
| `-Druntime` | `true`, `false` | `false` |
| `-Dvalidate` | `true`, `false` | `true` (upstream's `BOX2D_VALIDATE`) |
| `-Ddisable-simd` | `true`, `false` | `false` (upstream's `BOX2D_DISABLE_SIMD`) |
| `-Davx2` | `true`, `false` | `false`; applied on x86/x86_64 only, and the configure line says when it is ignored elsewhere |

A requested linkage is never substituted. If a selected `-Dtarget` cannot carry
the requested linkage, the build graph refuses at configure time: it prints
`error: <reason>` and exits, producing no artifact rather than a static one with
a warning. `zig build check` under `-Dlinkage=dynamic` therefore leaves the
offending target out of that run and names it — `box2d: check: <triple> is NOT
covered by this run.` — with the reason. Under the default static linkage all
six matrix targets are still checked, so the six-target `check` is complete for
the default graph.

`README.zig.md` §1 explains each one and lists the options deliberately not
offered.

---

## 5. Licence

The installed closure is MIT: upstream's own `LICENSE`, installed unmodified.
This fork's files are MIT as well, under the owner's direct grant of 2026-10-04
recorded in `FORK-LICENSE.md`.

The tree is **not** uniformly MIT, and `NOTICE.md` names every exception:

| Material | Term |
| --- | --- |
| `LICENSE`, `include/`, `src/`, `test/`, `shared/`, `samples/`, shaders, `benchmark/main.c` | MIT, `Copyright (c) 2022 Erin Catto` in `LICENSE`; 119 files also carry `SPDX-License-Identifier: MIT` |
| `extern/enkiTS/` | zlib, `Copyright (c) 2013 Doug Binks` |
| `extern/jsmn/jsmn.h` | MIT, `Copyright (c) 2010 Serge Zaitsev` |
| `extern/glad/include/KHR/khrplatform.h` | MIT-style Khronos grant, `Copyright (c) 2008-2018 The Khronos Group Inc.` |
| `extern/glad/include/glad/glad.h`, `extern/glad/src/glad.c` | no grant of their own; covered by `LICENSE` |
| `samples/data/droid_sans.ttf` | Apache-2.0, `© 2007 Google Corporation`, by its own embedded name table |

**The library does not depend on enkiTS, jsmn, glad or the font.** enkiTS is
used by upstream's determinism test and benchmark driver only; the other three
serve upstream's graphical samples, which this SDK does not build.