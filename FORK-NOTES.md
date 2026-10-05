# FORK-NOTES.md — Box2D SDK working record

The provenance role's record for this SDK: what was decided, what was read out
of which file, and what is still open. Written 2026-10-04.

Status vocabulary is the workspace's: `SOURCE-CONFIRMED` (read out of a file),
`OBSERVED` (a driver run printed it, receipt named), and `PENDING-VERIFICATION`
(landed, not yet gated).

This role ran no build, test, smoke, formatter, cross-target or Nix command. The
gates the driver has run are in `README.md` §3 and are repeated in section 6
below; two of them exist, and only at host `Debug` scope: the linked
`zig build smoke test`, and the runtime-loaded dispatch with a **static**
delivery against a shared provider named on the command line
(`local://foundation-contract-box2d-current-canonical-runtime-static-real-provider-smoke.log`).
Nothing wider than that is claimed here.

---

## 1. Ownership

Three disjoint roles worked on this SDK, one per file set:

| Role | Files |
| --- | --- |
| NativeDelivery | `build.zig`, `build.zig.zon`, `build_support/`, `.gitignore`, `zig/translate.h`, `.github/workflows/verify.yml`, `cross-test.profile.sh`, `consumer/{build.zig,build.zig.zon}` (wiring only) |
| ApiConsumer | `zig/*.zig`, `runtime/{library.zig,graph.zig}`, `tests.zig`, `smoke.zig`, `consumer/src/main.zig` |
| ProvenanceNix (this file) | `README.md`, `README.zig.md`, `UPSTREAM.md`, `NOTICE.md`, `FORK-LICENSE.md`, `CHANGELOG.md`, `UPSTREAM.sha256`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` |

`runtime/{loader.zig,generate.zig,sync.c,sync.h}` are the driver's shared core and
are not this SDK's API role's files.

Interface points between the roles, all settled before the files were written:
the public module name is `box2d` and the translated namespace is imported as
`c`; `-Dlinkage` and `-Druntime` are independent booleans; the installed closure
is the one in `README.md` §2; the runtime synchronisation prefix is `box2d_rt`.

---

## 2. Licence decisions

**Fork-authored files: MIT, matching upstream's primary term.**
`SOURCE-CONFIRMED` — upstream `LICENSE` is the MIT text, `Copyright (c) 2022
Erin Catto`, 20 lines, 1067 bytes. The owner authorized per-project terms for the
fork's own additions on 2026-10-04. That authorization and the resulting grant
are in `FORK-LICENSE.md`; the SPDX identifier handed to the other two roles is
`MIT`, and no copyright line naming a person was requested or written.

**The tree is not one licence.** Four things travel with it that `LICENSE` does
not cover, and one that is only partly covered:

* `extern/enkiTS/` — zlib, `Copyright (c) 2013 Doug Binks`. Vendored, 35 files,
  revision `404a3bf8f855039dfff2052184d6308655286c07`. Used by the determinism
  test and the benchmark driver only.
* `extern/jsmn/jsmn.h` — MIT, `Copyright (c) 2010 Serge Zaitsev`.
* `extern/glad/include/KHR/khrplatform.h` — Khronos grant.
* `extern/glad/{include/glad/glad.h,src/glad.c}` — no grant of their own.
* `samples/data/droid_sans.ttf` — Apache-2.0, `© 2007 Google Corporation`.

**Not invented:** no patent claim (neither MIT nor zlib carries an explicit
patent clause), no personal copyright identity, and no claim that upstream's OR
terms forced or prevented any particular choice for independently authored files.

---

## 3. The integrity record

`UPSTREAM.sha256`, 267 records. `SOURCE-CONFIRMED` by construction; `OBSERVED`
as a check:

```
sha256sum -c UPSTREAM.sha256   ->   267 OK, 0 failures   (2026-10-04)
```

Design decisions:

* **`sha256sum` format, header as `#` comments.** `sha256sum` skips comment lines,
  so the explanation travels with the record and costs nothing at check time.
* **`.gitignore` is deliberately excluded.** It is an upstream file the contract
  requires the fork to extend (upstream's `build/`, `.cache/`, `.idea/`,
  `.vscode/`, `.vs/` must keep working). Pinning it would fail on the first
  legitimate extension. Its pristine digest is in `UPSTREAM.md` instead.
* **`extern/enkiTS/build.zig` and `build.zig.zon` are pinned.** They are carried
  bytes this fork did not write. They are enkiTS's, and they are never invoked;
  the SDK compiles enkiTS through its own graph. `README.md` and the record's
  header both say so, because a stray `build.zig` inside `extern/` is exactly the
  kind of file that gets mistaken for the project's own.
* **Fork-authored files are not pinned.** Reviewing them is a source review; a
  digest would only make an ordinary edit look like an integrity failure.

One mechanism worth recording: the first regeneration of this record lost its
comment header, because a shell `awk` accumulator silently produced an empty file
and the digest block was written on its own. The header was rewritten afterwards
and the check was re-run. A provenance record that is only digests is still a
valid record; it is just a much less useful one.

---

## 4. Packaging decisions

**One derivation, variants at the entry points.** `package.nix` is an uncurried
function of `{ lib, stdenv, zig, pkg-config, linkage ? "static" }` returning one
derivation. `flake.nix` names `.#static`, `.#shared` and `.#default`;
`devenv.nix` names `outputs.static`, `outputs.shared` and `outputs.default`. All
three go through `pkgs.callPackage ./package.nix`.

**`linkage` is `static` or `dynamic`, and static is the default.** Static is this
SDK's policy and upstream's own CMake default: `BUILD_SHARED_LIBS` is unset, and
upstream skips its own unit tests when it is on (`CMakeLists.txt:101`).

**The build graph owns every installed file.** `package.nix` does not place
`include/` or `lib/` by hand, does not write a `.pc`, and does not copy a licence
file the graph installs. Its `installCheckPhase` asserts the paths the graph
installs and resolves the `.pc` with `pkg-config` — a check, not a second copy.

**`dontConfigure` and `dontBuild`, with a real `installPhase`.** The Zig setup
hook replaces a phase only while it is still empty, so the hook's own
configure/build phases cannot run first with default flags and then be repeated
with the flags this derivation needs. `dontInstall` is deliberately not set: it
would disable the real install phase.

**Both Zig caches under `$TMPDIR`,** exported explicitly, never defaulted to the
source tree and never to a small system temporary filesystem.

**One optimize selection, `-Dcpu=baseline`, one linkage.** Optional native
settings are left at upstream's defaults rather than enabled by `callPackage`:
validation on, SIMD on, AVX2 off, runtime dispatch off.

**Cross-compilation is refused, by comparing platforms.** `zig build` gets no
`-Dtarget`, so it builds for the builder; a cross stdenv would install the
builder's native library under the host's name. The guard compares
`stdenv.hostPlatform.system` with `stdenv.buildPlatform.system` instead of naming
a system, so an ordinary remote builder — where the two agree — stays valid.
`builtins.currentSystem` is not used anywhere: it makes evaluation impure.

**The shell is tools only.** Entering `devenv shell` must not build the library,
so the SDK is not in `packages`. It is reachable through `outputs.*`, which are
lazy and are built with `devenv build outputs.static` / `outputs.shared`.

**Tasks are namespaced.** `box2d:build`, `box2d:test`, `box2d:smoke`,
`box2d:check`, `box2d:install`, `box2d:runtime`, `box2d:matrix`, each a real
`exec` command. Bare `build` or `test` would shadow the ordinary shell commands
of the same name. `box2d-integrity`, `box2d-consumer`, `box2d-package-static` and
`box2d-package-shared` are scripts, because they need quoting.

**Every body starts from this file's own directory.** devenv runs a task and a
script with the *caller's* working directory, not with this module's, so a body
that names `UPSTREAM.sha256`, `consumer/` or `build.zig` relatively depends on
wherever the caller stood. `sdkRoot = builtins.toString ./.` is the directory
holding that line, `sdkRootArg` is it shell-quoted, and every body opens with
the `cd`. `builtins.toString` rather than `"${./.}"` is the point of it:
interpolating a path copies it into the read-only Nix store, so the SDK would be
built and checked from a frozen copy of itself rather than from the working tree
an edit, an integrity record and the consumer's own
`.box2d = .{ .path = ".." }` are about. `$PWD` and `$DEVENV_ROOT` are used
nowhere: under `devenv --from path:<sdk>` both name a scratch project holding
none of `build.zig`, `UPSTREAM.sha256` or `consumer/`.

**Delivery output goes beneath the exported cache, never into the tree.** Bare
`zig build` defaults to the install step, so `box2d:build` and `box2d:install`
both pass `--prefix "$ZIG_LOCAL_CACHE_DIR/box2d-prefix"`; every `zig build` body
also passes `--cache-dir "$ZIG_LOCAL_CACHE_DIR/box2d"` and `-j8`, so a run writes
neither `zig-out/` nor `.zig-cache/` into this repository. Both names are the
caller's — `enterShell` exports them from `TMPDIR`, and a body run without one
refuses instead of choosing a second location — and both are sub-paths of a
variable rather than literals, so this file still names no host path.
`box2d:matrix` passes neither path flag, because `cross-test.profile.sh`
forbids naming a compiler cache or an output directory and owns its own paths;
it does name the harness's own concurrency, `--jobs 8 --build-jobs 8`, because
neither this file nor `cross-test.profile.sh` sets `CROSS_JOBS` or
`CROSS_BUILD_JOBS` and the harness defaults are `--jobs 2 --build-jobs 1`.
`box2d:package-static` and `box2d:package-shared` name `path:<sdkRoot>` rather
than `path:$PWD` and keep forwarding `"$@"`.

**No lock is written, and the devenv input is a flake.** `devenv.yaml` and
`flake.nix` each name one pinned nixpkgs revision and say that the lock is the
driver's to create from an observed run. No hash is invented here.
`devenv.yaml` carries no `flake: false`: that key turns devenv's nixpkgs into a
plain source tree, a plain source tree has no `lib`, and devenv's own bootstrap
at `lib = nixpkgs.lib` then fails before a line of `devenv.nix` is read.
Observed for this SDK on 2026-10-04 in `nix-acceptance-20261004T175328Z`: six
gates, `error: attribute 'lib' missing`, exit 1 each.

**Scratch policy is read, not written.** Neither `package.nix` nor `devenv.nix`
names `/vol`, `/home/tmp2`, an account or a store path. `devenv.nix` fills in a
Zig cache under `$TMPDIR` only when the caller supplied `TMPDIR`, and never
overrides a value the caller already exported. `.envrc` sources the host's
storage policy at load time if it exists and sets `DEVENV_HOME`,
`XDG_DATA_HOME` and `XDG_RUNTIME_DIR` from the scratch root it exports; without
that policy it sets nothing and says nothing false.

---

## 5. Source facts worth keeping

* **Version 3.1.1 is stated three times**: `CMakeLists.txt:6`,
  `src/core.c:69-76` (`b2GetVersion` returns 3, 1, 1), and
  `src/CMakeLists.txt:96-97` (VERSION/SOVERSION, hence soname 3).
* **No generated or configuration header.** `BOX2D_VALIDATE`,
  `BOX2D_DISABLE_SIMD`, `BOX2D_AVX2`, `box2d_EXPORTS` and `BOX2D_DLL` are
  compile-line macros, and no struct field or function signature in the six
  public headers is conditional on any of them. So `-Dvalidate` and
  `-Ddisable-simd` change behaviour, not layout.
* **One declaration/definition mismatch**: `b2InternalAssertFcn` is declared only
  when `NDEBUG` is undefined or `B2_ENABLE_ASSERT` is defined
  (`include/box2d/base.h:101`), while `src/core.c:62-67` defines it whenever
  either is true. The library therefore exports a symbol the header does not
  always declare.
* **No exported data symbols.** Every `B2_API` entity in the six public headers
  is a function. The two globals in the core, `b2AssertHandler`
  (`src/core.c:54`) and `b2_byteCount` (`src/core.c:81`), carry no export
  declaration and upstream compiles with `CMAKE_C_VISIBILITY_PRESET hidden`
  (`src/CMakeLists.txt:74`). A runtime table for this SDK has no data entries
  whose address must stay live in the provider.
* **Upstream's `id.h` contributes no externs**: `b2Store*`/`b2Load*` are
  `B2_INLINE`.
* **libm is part of the closure on some targets.** `box2d.pc` carries `-lm`
  where the target's core system libraries include it, because
  `include/box2d/math_functions.h:9` includes `<math.h>` and the scalar paths
  call `sinf`, `cosf` and `atan2f`. There is no `Libs.private`: the same file
  describes the static install, where the consumer's link line is the only
  place libm can come from.
* **`bin/box2d-benchmark` is not installed for `wasm32-wasi`.**
  `extern/enkiTS/src/TaskScheduler.h:22` includes `<thread>`, which Zig 0.16's
  WASI C++ library has none of. Every other target installs it. The build graph
  prints that on its configure line.
* **A requested linkage is never substituted.** `targetCanCarry(target,
  requested)` gates a refusal and nothing else: no function in the graph can
  return a linkage other than the one asked for. A target that cannot carry it
  is rejected at configure time (`build.zig:1946-1949`) with a printed `error:`
  and an exit, so no artifact is produced at all. This is a behaviour, not a
  deviation, and it is deliberately **not** in the `README.md` deviation list.
* **`-ffp-contract=off` is reproduced, unconditionally.** The build graph's
  single flag function emits it for every C translation unit it flags: the
  35-file core, the 4-file `shared` support library, the 10-file upstream `test/`
  suite and `benchmark/main.c` — exactly the set upstream's directory-scope
  guard covers (`CMakeLists.txt:37-41`, above `src`, `shared`, `test` and
  `benchmark`). The only difference is that upstream's `MINGW OR APPLE OR UNIX`
  condition is gone: the two OS tags it excludes are MSVC and Emscripten, and
  this graph can produce neither. `SOURCE-CONFIRMED` from the build graph, not
  from a run. It becomes a result when `zig build upstream-test` runs.

* **73 inline functions, 72 of them translated and one bridged.** Counting
  `^B2_INLINE` definitions in the six public headers at this pin gives 63 in
  `math_functions.h` and 10 in `id.h`, none in the other four. `include/box2d/base.h:33`
  makes `B2_INLINE` `static inline` in C, so upstream needs no symbol for any of
  them and `src/world.c:2159` is the only caller of `b2MakeAABB`. Zig 0.16
  translates 72 bodies; the 73rd opens with `B2_ASSERT( count > 0 )`
  (`math_functions.h:627`) whose `B2_BREAKPOINT` is `__builtin_trap()`
  (`base.h:94`), so it is demoted to an `extern` declaration of a symbol nothing
  defines. `build_support/box2d_inline_bridge.c` is the fill, it is compiled into
  the core module itself, and it is the only C translation unit in this package
  that upstream does not ship. `README.zig.md` §6 has the long form.
* **Sensor events are opt-in on both shapes.** `include/box2d/types.h:385-386`
  says `enableSensorEvents` is "False by default, even for sensors", and
  `src/sensor.c:65-67` skips an overlap whose other shape has not opted in. A
  visitor that does not set the flag is silently never reported, which is a
  consumer-visible precondition rather than a defect; `tests.zig` and
  `consumer/src/main.zig` set it on both.
* **Three of this SDK's own checks are deliberately bounds, not equalities.**
  `tests.zig` checks `shapeAabb` conservatively — the reported box must *contain*
  the square, without pinning Box2D's speculative-contact margin — checks the
  dynamic-tree query by the *membership* of the proxies it returned rather than
  the order the tree visited them in, and checks the free fall against the
  continuous trajectory `y0 - g t^2 / 2` inside the sub-step discretisation
  envelope rather than against one stepper's exact output. A test that pinned
  any of those three would fail on an upstream change that is not a defect.
* **The C library math names are classified separately from the library's own
  declarations.** `runtime/graph.zig` holds the bases, expands them over the
  `""`/`"__"` prefixes and the precision suffixes, and passes the result to the
  generator as `--noise`; a name in that list stays a direct `extern` resolved
  against the process's libc, and no provider has to export one. The asymmetry is
  deliberate: over-listing is inert, under-listing makes the provider responsible
  for `sinf` and breaks the load. No Box2D name can collide with it — they all
  begin `b2` or `B2`.
* **A provider inherits one requirement from the consumer's optimize mode.**
  `b2InternalAssertFcn` is declared and defined under the same guard
  (`include/box2d/base.h:101-102`, `src/core.c:62-67`), so a `Debug` or
  `ReleaseSafe` consumer declares it and a provider built with `NDEBUG` is
  refused at load. Under `-Druntime` nothing is linked, so leaving that `extern`
  direct would be a link-time hole; routing it turns the mismatch into a
  load-time refusal.
  * `OBSERVED`, and the controlled comparison is the whole of it. Four loaded
    gates — `box2d-current-loaded-dynamic-Debug`,
    `box2d-current-loaded-dynamic-ReleaseSafe`,
    `box2d-current-loaded-static-Debug`,
    `box2d-current-loaded-static-ReleaseSafe`, receipts under
    `…/contract-physics-lua/current-native-evidence/` and
    `local://foundation-current-failures-box2d.json` — were all offered the same
    `BOX2D_TEST_PROVIDER`,
    `…/contract-physics-lua/box2d-shared/lib/libbox2d.so`, and every test in each
    stopped at `tests.zig:93` with `MissingSymbol`. The other four loaded gates,
    `ReleaseFast` and `ReleaseSmall`, took that same path in the same
    environment and exited 0. The provider is therefore the constant in the
    comparison and `-Doptimize` is the variable.
  * Reading that provider's dynamic symbol table (`nm -D --defined-only`) gives
    422 defined names, all `b2*`. The six public headers declare 422 `B2_API`
    functions, and the set difference runs one name in each direction:
    `b2InternalAssertFcn` is declared and not exported, and `b2MakeAABB` is
    exported and not declared — that one is this fork's inline bridge
    (`build_support/box2d_inline_bridge.c`), which upstream reaches as a
    `static inline` and never exports. So `b2InternalAssertFcn` is the only
    entry point in this table that provider lacks, every other required name
    resolved in the four green gates, and no helper and no `optional` entry
    point was involved.
  * The refusal used to return `MissingSymbol` without saying which of the 422
    names was absent, so the receipt named a condition and not a cause.
    `runtime/loader.zig` now prints the library name and the symbol before
    closing the candidate, the way `validate` prints its own refusal. The check
    itself is untouched: same required table, same error, same closed
    candidate, same nothing published. `PENDING-VERIFICATION` — no gate has run
    a build carrying that print.
  * The recipe the four red gates needed is a provider per consumer mode, in
    `runtime/library.zig` and `README.zig.md` §3: install with
    `-Dlinkage=dynamic -Doptimize=<the consumer's mode>` into a per-mode
    prefix and point `BOX2D_TEST_PROVIDER` at that prefix's
    `lib/libbox2d.so`. `-Dlinkage=static -Druntime=true` installs an archive
    and still has to be handed a shared object. `ReleaseFast` and `ReleaseSmall`
    consumers accept any provider this package builds.

---

## 6. Open items and integration needs

Open items are unresolved source facts, not failed gates. Items marked CLOSED
were answered by another role from source, not by a run; the evidence line says
which.

1. **CLOSED — `-Dcpu=baseline` is a real option here.** The build graph calls
   `b.standardTargetOptions(.{})` (`build.zig:1875`) and
   `b.standardOptimizeOption(.{})` on the next line, which is where Zig 0.16
   registers `cpu` (`std/Build.zig:1414`, `1473-1483`). `package.nix` keeps
   `-Dcpu=baseline`. `SOURCE-CONFIRMED` from the native role, not from a run.
2. **CLOSED — `-ffp-contract=off` is reproduced.** See the source facts above.
   The one difference is recorded as a native-build deviation in `README.md` §2:
   the flag is unconditional where upstream's is guarded by an OS test whose
   excluded cases this build graph cannot produce. `test/test_determinism.c` is
   the fixture that would notice, and it becomes a result only when the driver
   runs `zig build upstream-test`.
3. **`.fingerprint` is compiler-provided.** It must be left absent in source and
   taken from the first real command; no placeholder hash is invented. Its
   `.paths` list stays complete.
4. **CLOSED — both install paths exist.** `package.nix` asserts
   `bin/box2d-benchmark` and `share/licenses/box2d/enkiTS-License.txt`; the
   graph installs the licence record unconditionally in every linkage and
   optimize mode, and the benchmark in every linkage and optimize mode on every
   non-WASI target. `UPSTREAM.sha256` is deliberately not installed and is not
   asserted: it is a repository record, not material that ships with a library.
5. **Locks.** `devenv.lock` and `flake.lock` are the driver's, created from an
   observed resolution. The two pinned nixpkgs revisions in `devenv.yaml` and
   `flake.nix` are written down. `devenv.lock` is still absent from this tree;
   `flake.lock` is now present and pins `nixpkgs` at the revision `flake.nix`
   already named, `c7def046b9a883d46974757852106483d741586f`, with
   `narHash` `sha256-6RSEDHIWQtesQKWSu5qRai8L2h4KgCgMEfJHstW99G4=` and
   `lastModified` 1789370336. `OBSERVED` as file contents only: this note did
   not derive those values and has not seen the resolution that produced them.
   `.gitignore:42-45` deliberately keeps both names out of the ignore list, so
   the file is a real input rather than a stray artifact. `build.zig.zon`'s
   `.paths` carries the advertised canonical Nix and devenv files
   (`package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`) and
   `flake.lock` beside `flake.nix`, because `zig fetch` hashes a packaged file
   and a manifest that shipped the flake without its lock would describe a
   package nobody resolved. `devenv.lock` stays unnamed because it does not
   exist and a named absent path is one `zig fetch` would have to hash. The
   lock is fork-authored rather than upstream's, so it is deliberately not in
   `UPSTREAM.sha256` and does not change that record's count: that gate checks
   the lines the record names and never walks `.paths`.
   `package.nix:80-81` filtering both lock names out of the derivation's source
   is deliberate and correct on its own axis: the flake frontend resolves the
   locked inputs before that filter applies, so a lock is not build input
   material. Package identities are derived once, after source and
   documentation freeze, so no per-edit hash is claimed here.
6. **CLOSED for this tree — runtime core distribution.** `runtime/loader.zig`,
   `runtime/generate.zig`, `runtime/sync.c` and `runtime/sync.h` are present and
   are the driver's shared files rather than this SDK's, re-copied into every SDK
   rather than forked. `runtime/library.zig` and `runtime/graph.zig` are
   authored against those interfaces, and the two agree on the `box2d_rt`
   synchronisation prefix — a build where they disagreed would fail to link,
   which is the whole error report.
7. **CLOSED — `-Dlinkage=dynamic` on `wasm32-wasi` is a refusal, not a
   substitution.** What the driver still has to do is record it that way:
   `check` leaves that one target out of the run and names it:
   `box2d: check: <triple> is NOT covered by this run.` plus the reason.
   `cross-test.profile.sh` records the WASI refusal under
   `CROSS_BUILD_ARGS=(-Dlinkage=dynamic)` and reports it as a platform failure
   under that flag, not as coverage. Under the default static linkage the
   six-target `check` is complete, `wasm32-wasi` included.
   `SOURCE-CONFIRMED` from `build.zig` and `cross-test.profile.sh`, not from a
   run.

8. **Open gates.** The `Debug` rows in `README.md` §3 are the whole of what has
   run against this tree's own build graph. The two Nix derivations have also
   run, and not through `devenv`: in `nix-acceptance-20261004T175328Z` the
   driver's `nix build … path:<sdk>#static path:<sdk>#shared` exited 0 and
   realised both store outputs, and `repo:untouched` passed beside it with an
   identical 363-entry listing digest. Two further gates have since run over
   this tree, both source-bound: `zig build check` over the six declared
   compile targets, exit 0 and `Build Summary: 61/61 steps succeeded` on
   2026-10-05 (`baseline-box2d-check`, run `20261005T014547Z-797a73f2`), and
   `cross-test` over the published 53-target table, exit 1 on 2026-10-04 (run
   `20261004T221720228710Z-45046`, 6 pass, 31 build-only, 5 build failures, 11
   run failures). Still unrun: every devenv gate, `devenv build outputs.static`
   and `outputs.shared` included, none of which has been re-run since
   `devenv.yaml` lost `flake: false`; the runtime-loaded branch with a shared
   delivery; an installed C consumer through `pkg-config`; and a fetched Zig
   consumer. Two of those are boundaries worth naming rather than rows: the
   pre-load panic is a source fact about `runtime/loader.zig` until a
   `ReleaseFast` and a `ReleaseSmall` build exercise it, and `zig build check
   -Dlinkage=dynamic` still has to record the WASI exclusion as an exclusion
   rather than as coverage. Both new gates hold one source stamp each, so the
   build-graph and helper edits made after them — including `CHANGELOG.md`
   [13] and [12] — are not covered by either receipt, and `README.md` §3 names
   the per-cell boundaries.

---

## 7. What this role did not do

No build, test, smoke, cross-target check, formatter, compiler probe, `nix`,
`devenv` or `cross-test` command was run. No commit, no publication, no account
or repository change, no lock file, no root workspace file. The one command this
role ran is `sha256sum -c UPSTREAM.sha256` and `sha256sum`, over carried bytes;
its result is recorded above as an integrity observation and nowhere as a build
or test result. The gates the driver has since run are recorded in `README.md`
§3; this role did not run them and does not characterise them further.

---

## 8. Cross-log repair round (build role, 2026-10-04)

Source: `contract-physics-lua/cross-8/box2d/runs/20261004-133328-60213-27994`,
53 targets, `zig build test -Dtarget=TARGET` per target, Zig 0.16.0. This role
read those logs and the tree; it ran nothing. Every line below about a target is
`OBSERVED` from that run's own log or `summary.json`; everything this round
changed is `PENDING-VERIFICATION`.

### 8.1 Files as they were, against what the logs actually say

`zig build test` built, per target, the 35-file core, the `shared` support
library, the ten-file upstream `test/main.c` suite, the enkiTS closure, the
translated header, this fork's `tests.zig` and `smoke.zig`. The published
aggregate was already complete — all 35 core translation units, all six public
headers, the fork bridge source — and the log's own configure line says so on
every target. Nothing in the tree was missing a source, a header or a target.

Classification of every red cell, from the logs rather than from the file names:

| Group | Targets | Where it is visible |
| --- | --- | --- |
| A — aggregate ABI across the C boundary | `x86-linux`, `hexagon-linux`, `riscv32-linux`, `s390x-linux`, `powerpc-linux`, `powerpc64le-linux`, `mips64el-linux`, `loongarch64-linux`; plus `mips64-linux` and `powerpc64-linux` for the aggregate *return* half | `member access within misaligned address 0x1 for type 'const b2BodyDef'` / `Illegal instruction` at `src/body.c:179 B2_CHECK_DEF( def )`, `null pointer of type 'const b2Polygon'`, `member access within misaligned address 0x… for type 'const b2WorldDef'` at `src/world.c`, `expected Box2D major 3, got 1.0.-2080380932` |
| B — NetBSD `translate-c` | all nine NetBSD targets | `generic-netbsd/math.h:607:1: error: unknown type name 'pragma'`, five errors, via `generic-netbsd/sys/cdefs.h:413,432` `_Pragma("GCC visibility pop")` |
| C — `arm-openbsd` NEON | `arm-openbsd` | `lib/include/arm_bf16.h:14:9: error: __bf16 is not supported on this target` plus nineteen errors cascading from it |
| D — boundaries left standing | `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux`, `s390x-linux`; `wasm32-wasi`; `aarch64_be-linux`, `armeb-linux`, `thumbeb-linux` | `test_determinism.c:125 ENSURE( data.hash == EXPECTED_HASH )`; the no-C++-threads `addFail`; build exit 124 at the 3600 s deadline |

### 8.2 What established that group A is a Zig-side defect

The decisive observation is in the same run: on `x86-linux`, `hexagon-linux`,
`riscv32-linux`, `powerpc64le-linux`, `mips64el-linux` and `loongarch64-linux`,
`compile lib box2d` succeeded **and** upstream's own unmodified `test/main.c`
printed `All Box2D tests passed!`, while the Zig facade tests on those same
targets died inside the library on a pointer they had just been handed. A
correct C archive and a broken Zig caller in one binary is a defect on the Zig
side of the boundary.

The shapes are aggregate ones on both directions. `b2WorldId` is a four-byte
struct passed by value (`include/box2d/box2d.h:210`), `b2CreateWorld` takes
`const b2WorldDef*` (`include/box2d/box2d.h:27`, and `src/world.c:100`),
`b2MakeBox` returns `b2Polygon` by value and `b2GetVersion` returns `b2Version`
by value. `powerpc-linux`'s panic names `const b2WorldDef` and the others name
`const b2BodyDef`; both are the pointee of a definition pointer upstream takes
directly — `B2_CHECK_DEF( DEF )` dereferences it (`src/core.h:129`) — so both
messages are the same misalignment of that pointer, and neither names a by-value
parameter.

### 8.3 The ARM discriminator, and why it is this narrow

`BOX2D_DISABLE_SIMD` was chosen over a CPU-feature test after checking the
model rather than assuming it. `std.Target.Cpu.Model.baseline(.arm, _)` is
`std.Target.arm.cpu.baseline` for every OS but 3ds and Vita
(`std/Target.zig:2012-2016`), and that model is `v7a`
(`std/Target/arm.zig:1928-1934`); `v7a` pulls in `neon` but **not** `bf16`
(`std/Target/arm.zig:1192-1203`). So `arm-linux`, `arm-freebsd`, `thumb-linux`
and `arm-openbsd` all resolve to the same Zig feature set, yet three of them
compile `<arm_neon.h>` and one does not. A feature test therefore cannot
discriminate, and it would have taken NEON away from three working targets.

What the logs do discriminate is the OS: `compile lib box2d Debug arm-netbsd`
and `... armeb-netbsd` both **succeeded** in the same run, so a 32-bit ARM
NetBSD target does include `<arm_bf16.h>` successfully here, and only the
OpenBSD ARM triple fails. `armNeonNeedsScalar` keys on `os.tag == .openbsd`
inside the 32-bit ARM family and names that boundary in its own documentation.
It is a toolchain boundary, not an upstream portability rule, and widening it
is the failure mode that costs working targets their vector width.

### 8.4 Parent probes, one per change

No gate was run here. Each command below is focused on exactly one change and
names what would refute it.

```sh
# 1. The LLVM roots (group A). Refuted if the misaligned-`def` crashes survive.
zig build test -Dtarget=loongarch64-linux -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/llvm-loongarch64" --test-timeout 1800s
zig build test -Dtarget=mips64-linux -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/llvm-mips64" --test-timeout 1800s
zig build test -Dtarget=x86-linux -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/llvm-x86" --test-timeout 1800s

# 2. The same change must not disturb a target that already worked.
zig build test -Dtarget=x86_64-linux -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/llvm-x86_64" --test-timeout 1800s

# 3. The NetBSD front end (group B). Refuted if `translate-c` still reports the
#    five `unknown type name 'pragma'` errors, or if the aggregate loses a
#    declaration: the `All Box2D tests passed!` line must still appear.
zig build test -Dtarget=x86_64-netbsd -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/netbsd-x86_64" --test-timeout 1800s

# 4. The OpenBSD-ARM scalar rule (group C). The configure line must name the
#    triple and say the scalar path was the target's need, and the archive must
#    compile.
zig build test -Dtarget=arm-openbsd -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/bf16-arm-openbsd" --test-timeout 1800s

# 5. The same rule must not fire where NEON works. Both configure lines must
#    print `BOX2D_AVX2`-free, `BOX2D_DISABLE_SIMD`-free first lines.
zig build test -Dtarget=arm-linux -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/bf16-arm-linux" --test-timeout 1800s
zig build test -Dtarget=arm-netbsd -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/bf16-arm-netbsd" --test-timeout 1800s

# 6. The dependent root. A consumer built on this module must say the same
#    thing on its own executable.
zig build consumer -j8 --summary all --color off \
  --cache-dir "$CACHE/box2d/llvm-consumer"
```

### 8.5 Bounded and unresolved, with what would settle each

* **Is the backend the whole of group A, or only part of it?** `SOURCE-CONFIRMED`
  that the defect is on the Zig side; not proven that the code generator is the
  variable. Two observations point at it (this workspace already uses
  `use_llvm = true` for ERFA's external Zig roots for a wide C ABI, and the
  default is null here, so setting it is a change) and one points away: the
  failures are target-selective inside one compiler build, which a global
  default would not explain. Probe 1 settles it. If the crashes survive
  unchanged, the cause is Zig 0.16's aggregate argument/return lowering for
  those targets and this repository has no build-side fix that does not alter
  the public ABI, which this round is not allowed to do. Nothing was changed on
  the strength of the weaker hypothesis: no struct was repacked, no declaration
  was wrapped, no `-f` flag was invented.
* **Will the NetBSD route need what ERFA's needed?** ERFA's `zig/translate.h`
  restates `__int128_t` and `__uint128_t` because `generic-netbsd/arm/cdefs.h`
  spells `__ALIGNBYTES` through that name under `__ARM_PCS_AAPCS64` and Clang
  declares it next to the `__int128` primitive rather than in a header. Box2D's
  six public headers reach `<stdint.h>`, `<assert.h>`, `<float.h>`,
  `<math.h>` and `<stdbool.h>` and use no `__int128`, so the failure is not
  expected — but `zig/translate.h` belongs to another role and was not touched.
  If probe 3 reports `use of undeclared identifier '__int128_t'`, that is the
  same one-line restatement ERFA already carries, in the API role's file, and it
  belongs there.
* **`arm-openbsd` is a toolchain boundary, not a portability rule.** If a later
  Zig makes `<arm_neon.h>` includeable on that triple, the rule is stale rather
  than wrong; the symptom to re-check is the absence of
  `__bf16 is not supported on this target` in a fresh `arm-openbsd` log.
* **The three big-endian-ARM build timeouts** (`aarch64_be-linux`, `armeb-linux`,
  `thumbeb-linux`) have no identified cause. `SYMPTOM` only: three targets hit
  the same 3600 s deadline and produced no diagnostic. Nothing was changed for
  it.
* **Upstream's determinism hash on big-endian and mips** is upstream's own test
  with upstream's own expected hash, failing at `test_determinism.c:125`. Not
  skipped, not weakened, not excluded, and not attributed to this fork's build.
  `wasm32-wasi` stays the explicit no-C++-threads boundary it already was.

---

## 9. Contract-review round (facade and docs, 2026-10-04)

Six findings were raised against this package and read against the sources
before anything was edited. One was refuted by the driver's own probe, four
landed as documentation corrections, and one landed as a decision recorded in
prose rather than as an API change.

### 9.1 Refuted: the `load` guard needs no rewrite

`zig/root.zig` guards the linked configuration with
`if (comptime !runtime_loaded) { std.debug.panic(...) }` and then calls
`return c.load(source);` outside that arm, and a reviewer read the trailing
statement as analysed in every configuration — which would make a linked
consumer's `try box2d.load(...)` fail to compile, because the linked `c` is the
translation of `zig/translate.h` and the generated module declares no `load`.
That part is `SOURCE-CONFIRMED`: the approved cache's generated
`box2d-standalone-linked-static/.../translate.zig` carries no `load`,
`loadedSource`, `LoadSource`, `LoadError` or `rt_runtime_loaded`, while
`box2d-standalone-loaded-static/.../dispatch.zig:17,34,46,53` carries all of
them.

The consequence is not. The driver's linked-load probe
(`/home/tmp2/gertullj/scratch/foundation-libs/review-contract-probes/evidence/before-20261004T195312Z/index.json`)
compiled a linked consumer that calls `box2d.load` and reached the documented
panic, exit 1, and `loadedSource` answered `null`. `WITHDRAWN`: no guard was
rewritten, and no other SDK's guard was touched. The panic-first shape is what
nineteen SDKs in this wave use; lua, luajit, gmp, mpfr, predicates and
libunibreak use the early-return shape, and both compile.

### 9.2 `CreateError` stays one set; the width is documented instead

`computeHull` returns the whole `CreateError` while checking one condition, and
so do the seven other creation calls in their own way: `createWorld` reaches
only `WorldLimitReached`, the body, shape and chain creators only `WorldLocked`.
Narrowing one function would have made it the only call that does not speak the
shared vocabulary, and would have forced a second public error set. The set's
own doc claimed "one error per null handle upstream can return", which was
already wrong of `HullNotConvex` — `b2ComputeHull` returns a `b2Hull` by value
and reports `count == 0` (`src/hull.c:89-96`), which is not a null handle. The
module documentation, `CreateError`'s own comment, `computeHull`'s comment and
`README.zig.md` §4 now say what is true: one shared vocabulary, and each call
reaches only its own tags inside it. No signature moved.

### 9.3 Corrections that were false against the sources

* **`b2WorldDef.allocator` does not exist.** `README.zig.md` §5 told a reader
  that the field "may own a per-world allocation whose lifetime is the world's".
  `include/box2d/types.h:81-143` has seventeen members and no allocator, and the
  approved cache's generated `translate.zig:2454-2473` has the same seventeen.
  The clause is gone; the surrounding statement about the C allocator stands.
* **`b2CreateWorld` takes a pointer, not a definition by value.** `build.zig`'s
  LLVM note, `FORK-NOTES.md` §8.2 and `CHANGELOG.md` entry [7] all said
  by-value. `include/box2d/box2d.h:27` and `src/world.c:100` both take
  `const b2WorldDef*`, which is why `zig/root.zig:1914` declares
  `createWorld(def: *const WorldDef)`. The surrounding by-value claims
  (`b2WorldId`, `b2MakeBox`, `b2GetVersion`) are correct and stand. The
  observation the note rests on is unchanged; only the reading of the panic's
  type name as a by-value parameter was wrong.
* **The package-dependency examples did not compile.** `README.md` §4 and
  `README.zig.md` §2 passed `defaultWorldDef()` / `defaultBodyDef()` by value
  to `createWorld` / `createBody`, which take `*const WorldDef` and
  `*const BodyDef`, and dropped the `CreateError!` without `try` in a `!void`
  function. Both now use the form the facade's own module documentation uses at
  `zig/root.zig:29-45`, and both still do real work: create a world, create a
  body, step it.
* **`zig build test` does not run the example.** `build.zig`'s entry-point list
  said it did. `run_example` is attached to `smoke` (`build.zig:1925`);
  `test_step` depends on the Zig tests and upstream's `test/main.c`, or on the
  explicit no-threads failure (`build.zig:1944-1966`). The step's own
  description, `README.md` §3 and `README.zig.md` §8 already said the narrower
  thing.

### 9.4 The devenv matrix body, restated

`devenv.nix`'s `box2d:matrix` now runs `cross-test --jobs 8 --build-jobs 8`
from this package's own directory. The three places that described what it
passes — `CHANGELOG.md`, `README.md` and this file — now name the two
concurrency flags as well as the two path flags it still refuses, and
`README.zig.md` §8's bare `"$HOME/.local/bin/cross-test"` line carries the same
flags the task now names.

Everything in this section is `PENDING-VERIFICATION` except the refutation in
§9.1 and the observations already recorded in `README.md` §3. This role ran no
build, test, compiler probe or formatter.

---

## 10. The nested `consumer` helper, as the source reads it now

`zig build consumer` is the only step in this package that starts a second
build. `runConsumer` in `build.zig` composes that child's command line. In
emission order it carries:

* **The selection the caller made.** `-Dtarget` from
  `target.query.zigTriple`, `-Dcpu` from `target.query.serializeCpuAlloc`,
  `-Doptimize`, `-Dlinkage`, `-Druntime`, `-Dvalidate`, `-Ddisable-simd` and
  `-Davx2`. Each is written as `key=value`, so the nested build parses it as
  its own option rather than as a bare word.
* **The execution environment.** `-fdarling`, `-fqemu`, `-frosetta`,
  `-fwasmtime` and `-fwine`, one per switch `b` reports enabled, then
  `--libc-runtimes` when `b.libc_runtimes_dir` carries a directory.
* **This workspace's own settings.** `-j8` and `--summary all`, the two
  options every `zig build` entry here adds and a nested build cannot derive
  for itself.
* **Both caches.** `--cache-dir` under `b.cache_root.path` with a `/consumer`
  subdirectory, because two build graphs must not share one manifest
  directory; and `--global-cache-dir` with `b.graph.global_cache_root.path`
  verbatim, because the global cache is the shared package store and a
  subdirectory of it would make the child materialise its own copy of every
  dependency. Each is guarded on a non-null path, so no directory is invented.
* **The caller's install prefix.** `--prefix` with an absolute value, and only
  when `b.install_prefix` differs from `<build root>/zig-out`. A relative value
  is made absolute against `b.graph.cache.cwd` first, because the child's
  working directory is `consumer/`. `DESTDIR` is not forwarded: the child
  inherits the environment this build ran with.
* **The caller's own arguments.** Last, behind `--`, and only when `b.args` is
  non-null.

The helper asks `hostCanExecute` in `build.zig` for `run` or `install`:
`run` when an enabled executor can execute the resolved target, `install` when
none can, so a target this host cannot execute is installed instead of spawned.
`b.graph.zig_exe` is the toolchain that ran this build script, and the step
asks for no external executor of its own.

The second hop is one line in `consumer/build.zig`:
`if (b.args) |args| run_exe.addArgs(args);`. Without it the forwarded arguments
stop in the *nested* build's `b.args`. With it, the provider route
`zig build consumer -Druntime=true -- --provider <path>` reaches
`consumer/src/main.zig`.

`PENDING-VERIFICATION`, with one bounded exception. The driver's
nested-delivery proof ran nine cases against this package on 2026-10-04 and
recorded every one of them: the four routes, a static and a dynamic delivery
each with the linked and the runtime-loaded dispatch, each of them twice, once
with the caller's `-Dtarget` and `-Dcpu` omitted and once with them named, plus
a ninth case that hands the loaded route no provider. Eight exited 0 with the
consumer program reporting that every value matched the expectation derived for
it. The ninth exited 1 and printed the missing-provider refusal
`consumer/src/main.zig` declares. Every case recorded the nested command line
this helper emits, with `-j8`, `--summary all`, both caches and the caller's
`--prefix` present, the propagated prefix resolving outside this repository,
and the loaded cases carrying `--provider` after `--` with every provider
variable absent from the child.

Three bounds on that. The run built the published path dependency from this
tree, so it settles the consumer route and not a filtered fetched package; no
filtered fetch has been run. The receipt's own top-level `status_note` is an
erratum in the driver rather than a fact about this SDK: it still carries the
template sentence "SOURCE ONLY: this driver has never been executed", while
every case record carries `plan_only: false`, a start and a finish timestamp, an
exit code and the program's own output, and a new driver is expected to drop
the sentence. And the run is `Debug` on one host, with one explicitly named
`x86_64-linux-gnu` and `baseline` as the only non-default target, so it settles
nothing about `check` in either linkage, about `cross-test` or about the devenv
entries.

The four optimize modes are a separate run, and it did cover them. The native
final matrix (`native-final-evidence/contract-final-after-20261004/run.json`,
2026-10-04, 176 cells over 22 SDKs, 144 pass and 32 not passed) gave this
package eight cells and all eight passed: `zig build test smoke install` in each
mode and both linkages, each with `-Druntime=false`, the four static cells at
`27/27 steps succeeded; 14/14 tests passed` and the four dynamic cells at
`29/29 steps succeeded; 14/14 tests passed`, each cell installing fifteen files
or seventeen. That run is what corrected this tree's claim that the other three
optimize modes were unrun. It is native and linked only, so it says nothing
about either runtime-loaded branch.

`README.md` §3 and `README.zig.md` §8 carry both runs: the nine cases as the
`Consumer package` row, and the eight cells in the mode columns and in the run
list. This role ran no build, no test, no compiler probe and no formatter.
