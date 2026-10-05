# CHANGELOG.md — Box2D SDK

Numbered entries, newest first. Every entry names what changed and where. An
entry records a gate result only when the driver observed that command, and it
names the receipt; everything else is `PENDING-VERIFICATION` until a command
looks at it. The authoritative statement of scope is the matrix in `README.md`
§3, and an entry never claims a cell that matrix does not.

Upstream re-syncs are ordinary entries: re-fetch the tag, re-run
`sha256sum -c UPSTREAM.sha256`, and update `UPSTREAM.md`, `UPSTREAM.sha256` and
`NOTICE.md` in the same change.

---

## [13] — 2026-10-05 — the 53-target matrix and the six-target `check` baseline, bound to one source stamp

* `README.md`, `README.zig.md`, `FORK-NOTES.md`, `CHANGELOG.md`. No native
  source, header, upstream test, data file, licence file, algorithm, exported
  symbol, struct layout, public ABI, declaration, option, step or target
  changed. This role ran no build, test, matrix, Nix, devenv, formatter or git
  command; every number below is read out of a receipt the driver already wrote.
* **The six-target `check` baseline.** Label `baseline-box2d-check`, baseline run
  `20261005T014547Z-797a73f2`, 2026-10-05: exit 0, `Build Summary: 61/61 steps
  succeeded`, no failing step, all six declared compile targets seen. It
  compiles and links and runs nothing, so it is compile evidence and not a
  passing test.
* **The 53-target matrix.** Run `20261004T221720228710Z-45046`, receipt
  `box2d-53-target-8.json`, `--jobs 8 --build-jobs 8`, source stamp
  `49e9048898…` identical before and after, exit 1. Of 53 cells: **6 pass, 31
  build-only, 5 build failures, 11 run failures**. Build-only means the cell
  compiled and no runner existed; it is coverage, not a pass.
* **The 5 build failures.** `aarch64-netbsd` and `aarch64_be-netbsd` stop inside
  `translate-c` at `box2d-translate.zig:3590:43` with `use of undeclared
  identifier '__int128_t'`, which comes from a preprocessed macro in the
  compiler's own vendored NetBSD header. `aarch64_be-linux`, `armeb-linux` and
  `thumbeb-linux` report `build=timeout` at 3600 s and each log ends on
  `Starting Box2D unit tests`. The first two are a toolchain defect below this
  SDK; the last three hang in upstream's own C determinism suite, which this
  contract does not change.
* **The 11 run failures, in two families.** Five, `mips-linux`, `mips64-linux`,
  `powerpc-linux`, `powerpc64-linux` and `s390x-linux`, fail in upstream's own C
  suite with `Assertion failed: false (test/test_determinism.c:
  SingleMultithreadingTest: 125)`; on `mips-linux` this SDK's Zig suite still
  reports `14 pass (14 total)` in the same run. Six, `hexagon-linux`,
  `loongarch64-linux`, `mips64el-linux`, `powerpc64le-linux`, `riscv32-linux` and
  `x86-linux`, fail only on the Zig-to-C boundary: each prints
  `All Box2D tests passed!` for the pure-C run first, then traps inside the C
  library on a definition pointer Zig supplied (`src/body.c:179`,
  `B2_CHECK_DEF`). Every struct this SDK exchanges is an alias of the
  translated one (`zig/root.zig:375-635`), so no layout in this tree can
  disagree with C.
* **What the receipts do not establish.** Each run holds one source stamp.
  Every build-graph, header, helper and normalisation edit made afterwards
  describes a tree no receipt here covers, including entries [12] and this one.
  No cell that did not execute is a platform-support claim in either direction.

## [12] — 2026-10-05 — `consumer` runs the nested build when this host can execute the target, and installs it when it cannot

* `build.zig` (`runConsumer`, the new `hostCanExecute`, the `consumer` step's
  comment and `--help`), `consumer/build.zig` (the install hook and the package
  doc), `README.md`, `README.zig.md`, `FORK-NOTES.md`, `CHANGELOG.md`. No native
  source, header, upstream test, algorithm, exported symbol, struct layout,
  public ABI, declaration, option, step or target changed; no option was added,
  removed or given a default; no test was added.
* **Fixed.** `runConsumer` asked the nested build for `run` on every target, and
  `consumer/build.zig` installed nothing, so a target this host cannot execute
  was spawned anyway and an install would have delivered an empty prefix. The
  sub-command is now `run` or `install` from `hostCanExecute`, the same
  `std.zig.system.getExternalExecutor` predicate the other nested helpers in
  this workspace use, and the consumer's executable is installed by
  `b.installArtifact(exe)`, so the nested `install` writes
  `<prefix>/bin/box2d-consumer`. An installed consumer is build-only evidence:
  nothing is executed and no semantic pass is claimed from it.
* Unchanged: `-Dtarget` and `-Dcpu` from the resolved query, `-Doptimize`,
  `-Dlinkage`, `-Druntime`, `-Dvalidate`, `-Ddisable-simd`, `-Davx2`, the five
  executor switches, `--libc-runtimes`, `-j8`, `--summary all`, both cache
  directories, the `--prefix` rule and `b.args` behind `--`.
* **Status: `PENDING-VERIFICATION`.** This role ran no build, test, smoke,
  matrix, Nix, devenv, fmt or git command, and no receipt is named here. The
  host-target run and the install for a target without an executor are the
  driver's to observe.

## [10] — 2026-10-04 — the nested `consumer` build is given the caller's cache, prefix, job width, summary and arguments

* `build.zig` (`runConsumer` only) and `consumer/build.zig` (the `run` step's
  own argument handover). No native source, header, upstream test, algorithm,
  exported symbol, struct layout, public ABI, declaration, signature, option,
  step or target changed; no upstream byte changed; no option was added,
  removed or given a default; no test was added; nothing else needed to
  change. The target, CPU, optimize mode, linkage, runtime, `-Dvalidate`,
  `-Ddisable-simd`, `-Davx2`, the five executor switches, `--libc-runtimes` and
  the local `--cache-dir` subdirectory are exactly as they were, and so are the
  consumer package's manifest fingerprint and the load-bearing absence of a
  default on each of its seven options. Everything below is
  `PENDING-VERIFICATION` except the last three bullets, which name the one
  driver run that has covered this change. No other box2d gate has run since it
  landed, and this role ran none.
* **The nested build now derives neither its own job width nor its own
  summary** (`runConsumer`). Nothing can append a `-j` to a `Run`
  step's command, so the nested `zig build` left to work its own width out of
  `std.Thread.getCpuCount()` took `cpu_count - 1`
  (`std/Io/Threaded.zig:1639`) -- the consumer this step proves then compiled
  at a width the caller never asked for, and at a different one again on
  whichever machine ran the gate. `AGENTS.md:157-158` and this package's own
  `devenv.nix:190-222` name `-j8`, `--cache-dir` and `--summary all` as what
  every entry adds: the local `--cache-dir` was already written below,
  `random123`'s nested helper is this tree's landed form of `-j8`, and
  `--summary all` was on none of the nested helpers. All three are
  two-token options (`lib/compiler/build_runner.zig:1639-1640` for `--summary`,
  `:422-427` for `-j`), so the summary value is a second argument rather than
  an `=`-joined string.
* **`--global-cache-dir` is forwarded** (`runConsumer`). It is the
  sibling of the `--cache-dir` block directly above it and the same read that
  block already makes: `b.graph.global_cache_root` (`lib/std/Build.zig:122`) is
  the directory the runner is handed at `lib/compiler/build_runner.zig:54` and
  installs at `:73-76`/`:89`. It is reached through `b.graph` because it is a
  field of `pub const Graph` (`:112`, "Shared state among all Build
  instances"); `Build` itself carries only the local `cache_root` (`:58`), and
  the guard above reads that one. So a `--global-cache-dir` the
  caller named reached this build graph and stopped there, and the nested build
  resolved its own package store outside the approved root. Two tokens, because
  that is the only spelling the runner documents
  (`lib/compiler/build_runner.zig:1675`) and the one the compiler itself emits
  for every build step it spawns (`lib/std/Build/Step/Compile.zig:1478-1479`).
  The path goes across **verbatim**, with no `/consumer` subdirectory: that
  subdirectory is right for the local cache, whose manifest directory two build
  graphs must not share, and wrong here, where a subdirectory of the shared
  package store would make the nested build materialise its own copy of every
  dependency into it.
* **`--prefix` is forwarded when the caller named one** (the block in
  `runConsumer` that sits between the global cache above and the `--` below).
  Left alone, the nested build resolves its own `zig-out` under `consumer/`,
  which is a build artefact inside the package rather than the place the caller
  asked for. The default this graph compares against is
  `b.build_root.join(b.allocator, &.{"zig-out"})`, and the test is an exact
  string comparison, so a caller who passes that default explicitly gets the
  nested build's own answer and the tree holds one. A relative `--prefix` would
  resolve against `consumer/` instead of against this build's root, so a
  non-default prefix is made absolute with
  `b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix })` before it is handed
  on. Two tokens, `--prefix` then the value, and the block stays ahead of the
  `--` so the nested runner still reads it as one of its own options.
  `DESTDIR` needs no forwarding because the nested build inherits the
  environment this one ran with. `tzdata`'s nested helper carries the same
  block, and this one is the SDK-root copy of it.
* **The caller's own arguments are forwarded, last and behind `--`**
  (the `--` block in `runConsumer`). The route
  `zig build consumer -Druntime=true -- --provider <path>` is how the loaded
  build names the shared object the consumer program loads
  (`consumer/src/main.zig`'s `providerRequest`), and the `smoke` step already
  hands `b.args` to the example program the same way. This helper passed all of
  its own bookkeeping to the nested build and dropped the one thing the caller
  typed: the run ends its own option parsing at `--` and puts the rest in
  `b.args` (`lib/compiler/build_runner.zig:428-430`, field at
  `lib/std/Build.zig:60`), so the child received an empty argument list and an
  outer build reported a narrower check than the one it was asked for. The
  `--` is emitted only when there are arguments, and it follows every
  forwarded option because that is what ends the nested runner's parsing.
  `s2geometry`'s nested helper is this repository's landed form of the same
  four lines.
* **The other end of that handover now exists, in the consumer package.**
  `consumer/build.zig`'s `run` step depended on
  `b.addRunArtifact(exe)` and never handed `b.args` to it, so the arguments
  the outer step now forwards would have stopped in the *nested* build's
  `b.args` and never reached `providerRequest` in `consumer/src/main.zig`. One
  line closes it:
  `if (b.args) |args| run_exe.addArgs(args);` — the shape `../build.zig`'s
  `smoke` step already uses for the example program. With both ends present
  the route `README.md` §4 documents for this package on its own
  (`zig build run -- --provider /abs/path/to/libbox2d.so.3.1.1`) and the same
  route reached from the SDK (`zig build consumer -Druntime=true -- --provider
  <path>`) are one handover rather than two, and the doc comment at `:18-28`
  now says which side the arguments belong to. Nothing about the dependency
  edge moved: `b.dependency("box2d", .{ ... })`, `use_llvm` and the
  `dep.module("box2d")`-only rule are as they were. No test was added for the
  forwarding — a forwarding test is what `AGENTS.md:95-96` rules out, and the
  proof is a run that names a provider.

* **Bounded driver observation: nine cases, nine as expected.** The driver's
  nested-delivery proof ran nine cases against this package on 2026-10-04 and
  recorded every one of them
  (`nested-delivery-proof/evidence/20261004T220323250122Z-515d06adcbbf/index.json`):
  the four routes, a static and a dynamic delivery each with the linked and the
  runtime-loaded dispatch, each of them twice, once with the caller's `-Dtarget`
  and `-Dcpu` omitted and once with them named, plus a ninth case that hands
  the loaded route no provider at all. Eight exited 0, each after
  `Build Summary: 6/6 steps succeeded`, with the consumer program reporting that
  every value matched the expectation derived for it. The ninth compiled
  without a diagnostic and stopped at `Build Summary: 4/6 steps succeeded
  (1 failed)`: its failing step is the run, and the program itself exited 1 and
  printed the missing-provider refusal `consumer/src/main.zig` declares, which
  is the outcome that case was written to observe.
* **Every case recorded the nested command line this helper emits.** `-j8`,
  `--summary all`, the local cache under the caller's cache root, the caller's
  global cache and the caller's `--prefix` were present in all nine, the
  propagated prefix resolved outside this repository in all nine, and no case
  recorded a failed nested command check. The loaded cases carried `--provider`
  after `--`, with every provider variable absent from the child environment,
  so each loaded route came from the command line and not from a variable.
* **Three bounds on those two bullets.** The run built the published path
  dependency from this tree, so it is evidence for the consumer route and not
  for a filtered fetched package, and no filtered fetch has been run. The
  receipt's own top-level `status_note` is an erratum in the driver rather than
  a fact about this SDK: it still carries the template sentence "SOURCE ONLY:
  this driver has never been executed", while every case record carries
  `plan_only: false`, a start and a finish timestamp, an exit code and the
  program's own output, and a new driver is expected to drop the sentence. And
  the run is `Debug` on one host, with one explicitly named `x86_64-linux-gnu`
  and `baseline` as the only non-default target, so it establishes nothing about
  the other three optimize modes, about any other target, about `check` in
  either linkage, about `cross-test` or about the devenv entries. The same
  receipt lists 27 non-pass rows, and each of them is box3d, spglib or tzdata
  rather than box2d.

## [11] — 2026-10-04 — the four-mode native matrix, recorded from its own run

* `README.md`, `README.zig.md`, `FORK-NOTES.md`, `CHANGELOG.md`. No native
  source, header, upstream test, algorithm, exported symbol, struct layout,
  public ABI, declaration, signature, option, step or target changed; no
  upstream byte changed; no option was added or removed; no test was added.
* **This package's eight cells, all passing.** The native final matrix
  (`native-final-evidence/contract-final-after-20261004/run.json`, 2026-10-04,
  176 cells over 22 SDKs, 144 pass and 32 not passed) gave box2d eight cells:
  `zig build test smoke install` in each of the four optimize modes and both
  linkages, each with `-Druntime=false`, because that run's policy is native and
  linked only and nothing was opened through the platform loader. The four
  static cells each printed `Build Summary: 27/27 steps succeeded; 14/14 tests
  passed` and the four dynamic cells `29/29 steps succeeded; 14/14 tests
  passed`, and every cell carried `test success`, `smoke success` and 77 lines
  of program output.
* **What each cell installed.** Fifteen files in a static cell and seventeen in
  a dynamic one, into a prefix fresh per cell: the six public headers,
  `lib/pkgconfig/box2d.pc`, six licence and upstream files, and
  `lib/libbox2d.a` in the static case or `lib/libbox2d.so`,
  `lib/libbox2d.so.3` and `lib/libbox2d.so.3.1.1` in the dynamic one. The run
  also recorded the whole tree's compiled-input closure at 6070 files before
  and after with one digest, so no source moved while it ran. The 32 cells
  that did not pass belong to geographiclib-c, libunibreak, predicates and ryu,
  and none of them to this SDK.
* **What moved in the documentation, and nothing else.** `README.md` §3 now
  carries the four-mode result in its install, shared-install and behavioural
  rows for every mode column, and `README.zig.md` §8 carries it as a second
  bullet. Two claims that the run made false were corrected rather than left:
  both documents said the other three optimize modes were unrun, and the
  `Fetched Zig consumer` row stays `pending` because a filtered fetched package
  has not been materialised by any run. The `Consumer package` row names the
  SDK route `zig build consumer` and states that a direct `cd consumer` entry
  has not been run. `FORK-NOTES.md` §10 carries the same bound. This role ran
  no build, no test, no compiler probe and no formatter.

## [9] — 2026-10-04 — contract-review round: four documentation corrections, one withdrawn finding, `CreateError` kept as the shared vocabulary

* `build.zig` (module documentation and the `llvm_required` comment only),
  `zig/root.zig` (documentation comments only), `README.md`, `README.zig.md`,
  `FORK-NOTES.md`, `CHANGELOG.md`. No native source, header, upstream test,
  algorithm, exported symbol, struct layout, public ABI, declaration,
  signature, step, option or target changed; no upstream byte changed; no test
  was added and no caller needed to change. Every change below is
  `PENDING-VERIFICATION`: the driver has re-run no box2d gate since it landed,
  and this role ran none.
* **`load` guard: finding withdrawn, nothing changed.** A reviewer read
  `zig/root.zig:275-285` as analysing `return c.load(source);` in a linked
  build, where the translated `c` declares no `load`, and predicted that a
  linked consumer's `try box2d.load(...)` would not compile. The premise is
  `SOURCE-CONFIRMED` and the prediction is not: the approved cache's generated
  linked module declares no `load` while the generated dispatch does, and the
  driver's linked-load probe
  (`/home/tmp2/gertullj/scratch/foundation-libs/review-contract-probes/evidence/before-20261004T195312Z/index.json`)
  compiled such a consumer and reached the documented panic, exit 1.
  `loadedSource` answered `null`. `zig/root.zig` is untouched here and no other
  SDK's guard was touched.
* **`CreateError` stays one set; the width is now stated.** `computeHull`
  returns the whole set while producing only `HullNotConvex`, exactly as
  `createWorld` produces only `WorldLimitReached` and the body, shape and chain
  creators produce only `WorldLocked`. Narrowing one function would have made
  it the only call outside the shared vocabulary and would have forced a second
  public error set, so no signature moved. `CreateError`'s own comment claimed
  "one error per null handle upstream can return", which was already wrong of
  `HullNotConvex` — `b2ComputeHull` returns a `b2Hull` by value and reports
  `count == 0` (`src/hull.c:89-96`). The module documentation, that comment,
  `computeHull`'s comment and `README.zig.md` §4 now say what is true: one
  shared vocabulary, and each call reaches only its own tags inside it.
* **`README.zig.md` §5 no longer documents a field that does not exist.** It
  said "`b2WorldDef.allocator` may own a per-world allocation whose lifetime is
  the world's". `include/box2d/types.h:81-143` has seventeen members and no
  allocator, and the generated `translate.zig` in the approved cache has the
  same seventeen. The clause is gone and the statement that memory crossing
  into `b2SetAllocator` belongs to the C allocator stands.
* **`b2CreateWorld` is corrected from by-value to pointer** in `build.zig`'s
  `llvm_required` comment and in `FORK-NOTES.md` §8.2, which had repeated it,
  and entry [7] above no longer calls the crashing parameter a by-value
  `b2WorldDef`. `include/box2d/box2d.h:27` and `src/world.c:100` both take
  `const b2WorldDef*`, which is why `zig/root.zig:1914` declares
  `createWorld(def: *const WorldDef)`. The by-value claims that are correct —
  `b2WorldId`, `b2MakeBox`, `b2GetVersion` — stand, and the observation the
  note rests on is unchanged.
* **The package-dependency examples compile now.** `README.md` §4 and
  `README.zig.md` §2 passed `defaultWorldDef()` and `defaultBodyDef()` by value
  to `createWorld` and `createBody`, which take `*const WorldDef` and
  `*const BodyDef`, and dropped the `CreateError!` without `try`. Both now use
  the form `zig/root.zig:29-45` already used, and both still create a world,
  create a body and step it.
* **`zig build test` is described as what it does.** `build.zig`'s entry-point
  list said the step ran the example program. `run_example` is attached to
  `smoke` (`build.zig:1925`); `test_step` depends on the Zig tests and
  upstream's own `test/main.c`, or on the explicit no-threads failure
  (`build.zig:1944-1966`). The step's own description, `README.md` §3 and
  `README.zig.md` §8 already said the narrower thing.
* **The devenv matrix body's concurrency is now stated** in the three places
  that describe what `box2d:matrix` passes. `devenv.nix` runs
  `cross-test --jobs 8 --build-jobs 8` from this package's own directory; the
  two path flags it still refuses are still refused, and
  `README.zig.md` §8's bare `"$HOME/.local/bin/cross-test"` line carries the
  same two concurrency flags the task now names.

## [8] — 2026-10-04 — `devenv.yaml` stops suppressing its nixpkgs flake; every devenv body starts from this tree's own directory

* `devenv.yaml`, `devenv.nix`. No native source, header, upstream test,
  algorithm, exported symbol, struct layout, public ABI, API, test or target
  changed; no upstream byte changed; `flake.nix`, `flake.lock`, `package.nix`,
  `build.zig`, `build.zig.zon` and `cross-test.profile.sh` are untouched.
  Everything in this entry is `PENDING-VERIFICATION`: the driver has re-run no
  box2d gate since the change landed.
* **What was observed, and what it was not.** In the driver run
  `nix-acceptance-20261004T175328Z` (2026-10-04), box2d's `nix:build` gate
  **passed** — `nix build --no-write-lock-file --no-link --json --cores 8
  --max-jobs 2 path:<sdk>#static path:<sdk>#shared`, exit 0, two `drvPath`s and
  two realised store outputs (`box2d-nix-build.log`). `repo:untouched` passed in
  the same run: 363 entries before and after, identical listing digest. The
  other seven gates **failed**: `devenv:info`, `devenv:tasks-list`,
  `devenv:canonical-integrity-mapping`, `devenv:shell-zig-version`,
  `devenv:shell-zig-env`, `devenv:consumer` and `devenv:integrity`, each exit 1
  and each carrying the same text — `Failed to get attribute
  'config.cachix.enable'`, then `.devenv/bootstrap/bootstrapLib.nix:54:13` at
  `lib = nixpkgs.lib`, then `error: attribute 'lib' missing`.
* **`devenv.yaml`: `flake: false` deleted, revision untouched.** That key makes
  devenv's nixpkgs a plain source tree, and a plain source tree has no `lib`, so
  devenv's own bootstrap cannot evaluate and no subcommand starts.
  `inputs.nixpkgs.url` keeps the exact pin
  `github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737`. The
  closing comment claimed `devenv shell` "resolves the revision below directly";
  that is replaced, because the revision is now resolved *through its flake*,
  and the reason the key must stay gone is written where the key used to be.
* **`devenv.nix`: every task and every script self-locates.** devenv runs both
  with the *caller's* working directory, and under the canonical
  `devenv --from path:<sdk>` invocation that directory is a scratch project
  holding no `build.zig`, no `UPSTREAM.sha256` and no `consumer/`. Each body now
  opens with `cd ${sdkRootArg}`, where `sdkRoot = builtins.toString ./.` and
  `sdkRootArg = lib.escapeShellArg sdkRoot`. `builtins.toString`, not
  `"${./.}"`: interpolating a path copies it into the read-only Nix store,
  which here would be a frozen second copy of the whole SDK rather than the
  working tree an integrity record, an edit and the consumer's own
  `.box2d = .{ .path = ".." }` are about. `$PWD` and `$DEVENV_ROOT` appear
  nowhere in the file.
* **What each body now runs.** `box2d:build` and `box2d:install` are the two
  steps that install anything — bare `zig build` defaults to the install step —
  and both now pass `--prefix "$ZIG_LOCAL_CACHE_DIR/box2d-prefix"`. Every
  `zig build` task and script also passes
  `--cache-dir "$ZIG_LOCAL_CACHE_DIR/box2d"` and `-j8`, so a run writes neither
  `zig-out/` nor `.zig-cache/` into this repository. `ZIG_LOCAL_CACHE_DIR` is
  the location `enterShell` already exported from the caller's `TMPDIR`; a body
  run without it fails with the message rather than choosing a second one.
  `box2d:matrix` passes neither path flag, because `cross-test.profile.sh`
  refuses to name a compiler cache or an output directory and owns every path
  it uses; it does name the harness's own concurrency, `--jobs 8 --build-jobs
  8`, because neither this package nor `cross-test.profile.sh` sets
  `CROSS_JOBS` or `CROSS_BUILD_JOBS` and the harness defaults are `--jobs 2
  --build-jobs 1`.
  `box2d:package-static` and `box2d:package-shared` name `path:${sdkRoot}`
  instead of `path:$PWD` and keep their `"$@"`.
* **No name changed.** The tasks `box2d:build`, `box2d:test`, `box2d:smoke`,
  `box2d:check`, `box2d:install`, `box2d:runtime`, `box2d:matrix` and the
  scripts `box2d:integrity`, `box2d:consumer`, `box2d:package-static`,
  `box2d:package-shared` are spelled exactly as before. Two descriptions grew:
  `box2d:install` now names its prefix, and the `enterShell` banner now points
  at the task and script names instead of at bare `zig build` lines that no
  longer describe what a caller has to type.
* **Not claimed.** No devenv gate in that run reached a task or a script, so
  none of them is evidence about the bodies above: the wrong-directory failure
  was observed on sibling SDKs, not on box2d. `devenv build outputs.static` and
  `outputs.shared` remain unrun here, and `README.md` §3 keeps its `devenv
  outputs` row pending.

## [7] — 2026-10-04 — four cross-log groups mapped to build fixes; three boundaries left standing

* `build.zig`, `consumer/build.zig`. No native source, header, upstream test,
  algorithm, exported symbol, struct layout or public ABI changed, no
  declaration moved, no caller required a change, no test was added and no
  target or suite was dropped. Everything in this entry is
  `PENDING-VERIFICATION`: no gate was run for it.
* **Group 1 — the Zig half of the boundary, aggregate ABI.** `x86-linux`,
  `hexagon-linux`, `riscv32-linux`, `s390x-linux`, `powerpc-linux`,
  `powerpc64le-linux`, `mips64el-linux` and `loongarch64-linux` crash inside
  `b2CreateBody` on `B2_CHECK_DEF( def )` (`src/body.c:179`) holding a
  misaligned or null `def`, and `powerpc-linux` crashes the same way in
  `b2CreateWorld` on the `const b2WorldDef*` it is handed
  (`include/box2d/box2d.h:27`); `riscv32-linux` gets a null
  `b2Polygon` back from `b2MakeBox`, and `mips64-linux`/`powerpc64-linux` read
  `b2GetVersion`'s `b2Version` as `1.0.-2080380932` / `1.21555064.21555064` and
  then see `error.WorldLimitReached` from `createWorld`. Every one of those
  targets compiled the C archive, and on six of them — `x86-linux`,
  `hexagon-linux`, `riscv32-linux`, `powerpc64le-linux`, `mips64el-linux`,
  `loongarch64-linux` — upstream's own unmodified `test/main.c` ran to
  `All Box2D tests passed!` in the same run while the Zig tests on the same
  targets died; `powerpc-linux` and `s390x-linux` compiled the archive too and
  reached their own upstream determinism-hash boundary described below. The
  library is therefore correct on these targets and the defect is in how the
  Zig code passes and returns aggregates across the C boundary.
  `llvm_required` (`build.zig`) is now stated on all four
  Zig compilation roots: `box2d-tests`, `box2d-smoke`,
  `box2d-tests-<triple>` and `box2d-smoke-<triple>`. The public ABI is
  untouched; this is only which code generator compiles the Zig half of a link
  that already mixes two languages.
* **The dependent-root requirement is now part of the interface.**
  `use_llvm` is a property of a compilation (`std/Build/Step/Compile.zig:284`),
  not of a module, so `zig/root.zig` and the published `box2d` module cannot
  carry it for whoever imports them. `consumer/build.zig` states it on its own
  executable and its module documentation says so in terms; any other dependent
  building a Zig root on this module needs the same one line.
* **Group 2 — NetBSD translation.** `x86_64-netbsd`, `x86-netbsd`,
  `arm-netbsd`, `armeb-netbsd`, `aarch64-netbsd`, `aarch64_be-netbsd`,
  `mips-netbsd`, `mipsel-netbsd` and `powerpc-netbsd` fail at `translate-c`
  with five `unknown type name 'pragma'` errors at
  `generic-netbsd/math.h:607`, from `_Pragma("GCC visibility pop")` reached
  through `generic-netbsd/sys/cdefs.h:413,432`. `build.zig` now selects the
  front end per target: Aro preprocesses and parses `zig/translate.h` itself on
  every target but NetBSD, and on NetBSD the target's own C preprocessor
  (`b.graph.zig_exe cc -E -dD`, same include path, same target, `-MD`/`-MF` for
  the six headers' dependency edges) expands the same header first and Aro
  parses what came out. No declaration is dropped, renamed or stubbed, and the
  translated set is byte-identical in content to the other route's.
* **Group 3 — `arm-openbsd` NEON.** `src/core.h:72-74` selects `B2_SIMD_NEON`
  for every ARM target and `src/contact_solver.c:518-523` includes
  `<arm_neon.h>`; Zig's copy includes `<arm_bf16.h>` unconditionally
  (`lib/include/arm_neon.h:35`) and Clang rejects its `__bf16` on that triple,
  so the core archive does not compile at all. `build.zig` now adds upstream's
  own `BOX2D_DISABLE_SIMD` for a 32-bit ARM-family target on OpenBSD and for no
  other target: `armNeonNeedsScalar` is the single place that decides, and
  `scalarMath` is the single place that answers for both the compile line and
  the configure line. `-Ddisable-simd` keeps every value it had, `-Davx2` is
  untouched, and the configure line prints the resolved triple and says when
  the scalar path was the target's need rather than the caller's request.
  `aarch64` keeps its NEON path, and `arm-netbsd`/`armeb-netbsd` keep theirs
  because `compile lib box2d` succeeded for both in the same run.
* **Three boundaries left standing, deliberately.**
  * `mips-linux`, `mips64-linux`, `powerpc-linux`, `powerpc64-linux` and
    `s390x-linux` fail upstream's own `test_determinism.c:125`
    (`ENSURE( data.hash == EXPECTED_HASH )`). That is an upstream test on an
    upstream hash; it is not skipped, not weakened and not excluded, and it is
    not attributed here to the build.
  * `wasm32-wasi` builds the core, the facade, `tests.zig` and `smoke.zig` and
    then fails `test` on the explicit no-C++-threads boundary
    (`extern/enkiTS/src/TaskScheduler.h:21-24` reaches `<thread>`). That
    boundary is unchanged and upstream's suite is still not omitted to make it
    green.
  * `aarch64_be-linux`, `armeb-linux` and `thumbeb-linux` hit the 3600 s
    per-target build deadline with no cause identified. Recorded as a symptom;
    nothing is changed on the strength of it.
* **Not claimed by this entry:** no `README.md` §3 cell, and no statement that
  any of the above fixes anything until a gate runs. The exact probes are in
  `FORK-NOTES.md` §8.

## [6] — 2026-10-04 — two false claims in the facade documentation corrected

* `zig/root.zig`, documentation only. No exported signature, no error set, no
  ABI, no native source, header, upstream test or algorithm changed, and no
  caller required a change: `CreateError` still has the same three variants and
  every wrapper still has the same parameters.
* A null query callback is not a supported path, and the docs did not say so.
  Eight entry points take one — `dynamicTreeQuery`, `dynamicTreeRayCast`,
  `dynamicTreeShapeCast`, `worldOverlapAabb`, `worldOverlapShape`,
  `worldCastRay`, `worldCastShape`, `worldCollideMover`. Each is `?*const`
  because that is the shape of the C parameter, not because null carries a
  meaning, and upstream calls it with no null test at `src/dynamic_tree.c:1146`,
  `:1245` and `:1375` or through its own wrapper at `src/world.c:2067`, `:2143`,
  `:2208`, `:2336` and `:2505`. Passing null is a call through a null function
  pointer at the first leaf or overlapping shape the query reaches. The
  optional pointer type is unchanged; null is now stated as a caller
  precondition. `worldSetFrictionCallback` and `worldSetRestitutionCallback` are
  explicitly excluded, because upstream reads null there as "restore the
  default" (`src/world.c:1913-1919`, `:1931-1937`) and they already said so.
* A degenerate segment is refused, not degraded to a circle. The doc claimed
  the degradation; `src/shape.c:219-224` computes the squared length and, at or
  below `B2_LINEAR_SLOP * B2_LINEAR_SLOP`, does `B2_ASSERT( false )` and returns
  `b2_nullShapeId`, creating no shape. Only `b2CreateCapsuleShape` degrades
  (`src/shape.c:201-206`), so the "As for a segment" cross-reference above it
  inherited a false premise and is corrected.
* Which of the two things the caller sees is now stated, because the previous
  wording would have been wrong in half the modes. The trap depends on more
  than `NDEBUG`: `B2_ASSERT` calls `b2InternalAssertFcn` first and reaches
  `B2_BREAKPOINT` only if that returns non-zero
  (`include/box2d/base.h:103-109`); `b2InternalAssertFcn` returns whatever the
  installed handler returns (`src/core.c:63-66`); and the default handler
  returns 1 (`src/core.c:46-52`). So `Debug` and `ReleaseSafe` end in
  `B2_BREAKPOINT` (`include/box2d/base.h:91-99`) before the null id exists,
  `ReleaseFast` and `ReleaseSmall` compile the assert out
  (`include/box2d/base.h:111`) and report `error.WorldLocked`, and a handler
  installed through `setAssertFcn` (`src/core.c:56-60`) that returns zero makes
  the refusal an `error.WorldLocked` in either pair of modes. That error
  covers two upstream refusals the wrapper cannot distinguish — a locked world
  (`src/shape.c:172-176`) and a refused segment — and the documentation now
  says so instead of leaving the conflation implicit. No error variant was
  added to resolve it.
* Observed, driver-run: all four optimize modes of a disposable reproducer
  outside this tree (`api-repros/box2d`, not package content) exited 0 with all
  eleven cases correct — `bg763` Debug, `bg768` ReleaseSafe, `bg760` ReleaseFast,
  `bg770` ReleaseSmall. The eight null-callback cases and the default-assert
  segment case all terminated inside the native call, and every control passed:
  the capsule degraded to a circle, and the zero-returning assert handler turned
  the segment refusal into `error.WorldLocked` in every mode.
* The contract the reproducer asserts on is a fault, not one particular signal.
  The null-callback cases arrive as `SIGSEGV`, and the default-assert segment
  case as `SIGABRT` where the program's own fault handler catches the signal and
  aborts on re-entry, and as the raw `SIGSEGV`/`SIGILL` where it is not. An
  earlier run of the same reproducer accepted only `SIGSEGV`/`SIGILL` and so
  reported `Debug` and `ReleaseSafe` as wrong-signal failures; that was the
  harness's contract, not a change in what the library does, and the
  classification was corrected before these four runs. Nothing here changed SDK
  behaviour, and no `README.md` §3 cell is claimed by this entry.

## [5] — 2026-10-04 — the flake lock ships with the flake, and the consumer proof carries the switches the library has

* `build.zig.zon`: `.paths` now names `flake.lock` between `flake.nix` and
  `devenv.nix` (`:102-107`). `zig fetch` hashes a packaged file, so a manifest
  that shipped the flake without its resolution would describe a package nobody
  resolved. `devenv.lock` stays unnamed because it does not exist in this tree,
  and a named absent path is one `zig fetch` would have to hash. The lock is
  fork-authored rather than upstream's, so it is deliberately not in
  `UPSTREAM.sha256` and does not change that record's count: `sha256sum -c`
  checks the lines the record names and never walks `.paths`.
* `build.zig` `runConsumer`: the nested consumer build forwards `-Dcpu`
  beside the `-Dtarget` and `-Doptimize` it already passed, so the consumer
  compiles for the CPU model the outer build resolved instead of whichever one
  the nested build would default to.
* `consumer/build.zig`: `validate`, `disable-simd` and `avx2` are declared as
  nullable `b.option(bool, ...)` and forwarded through
  `b.dependency("box2d", ...)`, so a nested build cannot compile a different
  Box2D than the caller asked to be proven. `disable-simd` is a quoted struct
  field because `std.Build` registers a dependency argument by field name.
* `consumer/build.zig`: `-Druntime` is no longer defaulted. Its declaration
  ended `) orelse false;` and now ends `);`, so an unset option is not recorded
  at all and the library's own default decides. Answering it in the consumer as
  well would put two defaults for one option in the tree, and the consumer's
  would be the one that is wrong the day the library moves.
* `consumer/build.zig`: a false `.fingerprint` claim is corrected. The build
  script said "The library manifest deliberately carries no `.fingerprint`, so
  there is no hash to pin here and this build must not invent one"; the library
  manifest does carry one (`../build.zig.zon:12`). Both packages carry their own
  because they are different packages with different names, and a path
  dependency's fingerprint is not restated.
* `.github/workflows/verify.yml`: the two gates "scalar math only" and "AVX2
  vector width" each gained a second line, `zig build consumer` carrying the
  same switch. `zig build test` alone cannot see a dropped forward — a
  dependency that ignored one of them would still compile the default library
  and exit zero. No other gate was added and none depends on a host CPU
  feature.
* `package.nix`: `licenseFiles` gained `FORK-NOTES.md`, so the list is six and
  matches what `build.zig` installs: `licence_records` (`build.zig:559-565`) is
  five, and `installLicenceRecords` adds the vendored `enkiTS-License.txt`.
  Naming five under-checked the sixth instead of failing on it, which is the
  worse failure for a gate whose only job is to notice a licence text that did
  not install. The list drives both `meta.licenseFiles` and the
  `installCheckPhase` licence assertion.
* `flake.nix`, `devenv.nix` and `FORK-NOTES.md`: three phrasings that described
  `flake.lock` as absent, or as not yet in `.paths`, now record that it is in the
  tree and travels. `FORK-NOTES.md` also records why the lock is fork-authored
  and therefore outside `UPSTREAM.sha256`.
* `PENDING-VERIFICATION`: nothing in this entry has been run. No build, test,
  Nix, devenv, fetch, lint, formatter or git command was executed, no receipt
  is named, and no cell of the `README.md` §3 matrix is claimed — in particular
  neither "Consumer package" nor "Fetched Zig consumer", which remain pending
  in all four optimize modes. No native source, header, upstream test,
  algorithm, facade declaration or error set changed.

## [4] — 2026-10-04 — the four red loaded gates are a provider-mode pairing, and the refusal now names the symbol

* Four loaded gates — `box2d-current-loaded-dynamic-Debug`,
  `box2d-current-loaded-dynamic-ReleaseSafe`, `box2d-current-loaded-static-Debug`
  and `box2d-current-loaded-static-ReleaseSafe` — were all offered one
  source-built provider through `BOX2D_TEST_PROVIDER` and every test in each
  stopped at `tests.zig:93` with `MissingSymbol`
  (`local://foundation-current-failures-box2d.json`, receipts named in
  `local://foundation-current-native-index.json`). The four `ReleaseFast` and
  `ReleaseSmall` loaded gates were offered the same path in the same
  environment and exited 0, so the provider was the constant in that
  comparison and `-Doptimize` the variable.
* Cause, read from the sources and from the provider's own dynamic symbol
  table rather than from the failure text: a `Debug` or `ReleaseSafe`
  consumer's translation declares `b2InternalAssertFcn`
  (`include/box2d/base.h:101-102`), the dispatch requires it, and that
  provider was built with `NDEBUG` and does not define it
  (`src/core.c:62-67`). Reading the provider gives 422 exported names against
  422 `B2_API` declarations in the six public headers; the set difference is
  `b2InternalAssertFcn` declared and not exported, and `b2MakeAABB` exported
  and not declared, which is this fork's inline bridge
  (`build_support/box2d_inline_bridge.c`). No ABI was redesigned, no required
  symbol became optional, and no fallback was added.
* `runtime/loader.zig`: a `MissingSymbol` refusal now prints the library name
  and the symbol it wanted before the candidate is closed, the way `validate`
  prints its own refusal. The required table, the error, the closed candidate
  and the nothing-published rule are unchanged, and the print names the SDK's
  own `library_name` so the shared core still holds no per-SDK name.
* `runtime/library.zig` and `README.zig.md` §3 carry the per-mode provider
  recipe: install with `-Dlinkage=dynamic -Doptimize=<the consumer's mode>`
  into a prefix of that mode and point `BOX2D_TEST_PROVIDER` at that prefix's
  `lib/libbox2d.so`. A `-Dlinkage=static -Druntime=true` gate installs an
  archive and still has to be handed a shared object, and a `ReleaseFast` or
  `ReleaseSmall` consumer accepts any provider this package builds.
* `PENDING-VERIFICATION`: neither the loader print nor the recipe has been run;
  the driver owns that re-run. No native source, header, upstream test,
  algorithm, facade declaration or test expectation changed.

## [3] — 2026-10-04 — runtime-loaded dispatch observed, documents brought onto the sources

* Observed `zig build smoke -Druntime=true -Dlinkage=static -- --provider <path>`
  on the host in `Debug`: 6/6 build steps, and the smoke program ran through the
  generated dispatch against a Box2D shared object that an earlier
  `-Dlinkage=dynamic` build of this tree had installed into a scratch prefix
  outside the repository and that the command named explicitly
  (`local://foundation-contract-box2d-current-canonical-runtime-static-real-provider-smoke.log`).
  That command builds neither the delivered artifact nor the provider, and it
  says nothing about the same branch with a shared delivery, which has not been
  run.
* Documentation corrections, each read out of a current source rather than out
  of an earlier draft of this file:
  * `README.md` §3 no longer says that no cell of the matrix has been observed.
    It records the `Debug` results that exist and leaves every other cell unrun.
  * `README.md` §2 carries the inline bridge as native-build deviation 13;
    `README.zig.md` §6 states the same facts for the reader of the interface.
  * `README.md` §4 and `README.zig.md` §2 give the four `-Dlinkage` ×
    `-Druntime` combinations, and the claim that a runtime build can load a
    static-provider library is gone: the loader opens a shared object.
  * `README.zig.md` §6 drops the per-header extern counts, which no longer
    match the headers, and says what each header contributes instead.
  * `README.zig.md` §4 lists `TreeQueryCallbackFn` and the other sixteen
    callback aliases, corrects `makeAABB` to `makeAabb`, drops a `makeTransform`
    that no upstream header declares, and adds the math entry points the list
    had left out.
  * `README.zig.md` §3 states the loader's own rules — idempotence, provider
    mismatch, no automatic retry, the waiter drain, reentrancy — and the one
    requirement a provider inherits from the consumer's optimize mode.
  * `README.zig.md` §5 states the C library math classification as the separate
    decision it is, with the asymmetry that decides whether a load succeeds.

## [2] — 2026-10-04 — native inline bridge and physical consumers

* Compile `build_support/box2d_inline_bridge.c` into static and shared libraries.
  The bridge calls the unchanged `b2MakeAABB` inline body when Zig cannot translate its assertion.
* Make sensor visitors opt into native sensor events.
* Check conservative shape bounds and dynamic-tree result membership, not padding or traversal order.
* Check free fall against the continuous trajectory and the time-step error envelope.
* `zig build smoke test` on the host in `Debug`: the 14 SDK tests and the full upstream
  Box2D suite passed, and the smoke program held every value it derives for itself —
  the hull's area, the disc's mass and inertia, the 3-4-5 triangle, the ray's hit point
  and fraction, the ten-step free fall, the borrowed move events, a destroyed shape id,
  and the refusal of world 129 of 128. The sensor begin/end overlap is in `tests.zig`
  and in `consumer/src/main.zig`; `smoke.zig` runs no sensor.

## [1] — 2026-10-04 — first import as a standalone SDK

Box2D enters this workspace as a new SDK. `PENDING-VERIFICATION`.

### Upstream

* Imported official `erincatto/box2d` at tag **v3.1.1**, commit
  `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`: 232 files, 2 999 775 bytes.
  No Git history is carried; the pin is a recorded fact, not something this
  working copy can verify on its own.
* Preserved upstream's `README.md` byte for byte as **`README.upstream.md`** and
  took the canonical `README.md` path for this fork's own README.
* Carried upstream's `LICENSE` unmodified, and every source, header, test, doc,
  sample, benchmark fixture and vendored `extern/` file byte for byte.
* Extended upstream's `.gitignore` so upstream's own ignore patterns keep working
  beside the fork's build, devenv and Nix outputs. This is the only upstream file
  the fork changes; its pristine digest is recorded in `UPSTREAM.md`.

### Vendored dependency

* Added **`extern/enkiTS/`**: 35 files, revision
  `404a3bf8f855039dfff2052184d6308655286c07`, archive SHA-256
  `21cc50750166c3e6f69ed4a67dbf9a015526fb35a1291e91d0dc31148ad89d9b`, zlib,
  `Copyright (c) 2013 Doug Binks`. Upstream fetches this at build time with an
  unpinned `GIT_TAG master` (`CMakeLists.txt:88-95`); the SDK downloads nothing,
  so it is vendored at an exact revision instead. `test/test_determinism.c:4` and
  `benchmark/main.c:8` need it; the library does not.
* Recorded enkiTS's three licence conditions in `NOTICE.md` and
  `FORK-LICENSE.md`, including that its notice may not be removed from a source
  distribution, and required its notice to be installed with the output.

### Build

* Added a Zig build of the complete upstream core closure: 35 `.c` and 22 `.h`
  files from `src/`, the six public headers, upstream's own unit tests, the
  shared test support and the benchmark driver. No CMake, Make or autotools
  target is invoked and nothing is downloaded.
* `-Dlinkage=static|dynamic`, default `static`, this SDK's policy and upstream's
  own CMake default (`BUILD_SHARED_LIBS` unset).
* `-Druntime=true`, default `false`, orthogonal to `-Dlinkage`.
* `-Dvalidate`, `-Ddisable-simd` and `-Davx2` carry upstream's own defaults
  (`BOX2D_VALIDATE` on, `BOX2D_DISABLE_SIMD` off, `BOX2D_AVX2` off).
* A real shared library with upstream's VERSION 3.1.1 and SOVERSION 3, PIC
  throughout, upstream's export and visibility macros, and the Windows DLL
  import/export distinction.
* Installs the library, the six public headers, `lib/pkgconfig/box2d.pc`, the
  non-graphical `bin/box2d-benchmark` tool and the licence material under
  `share/licenses/box2d/`.
* Upstream's `install(EXPORT ...)` CMake package is deliberately **not**
  installed (`src/CMakeLists.txt:202-223`); pkg-config metadata is installed
  instead. Recorded as a native-build deviation.
* Upstream's Debug postfix is deliberately not reproduced: a CMake Debug build
  emits `libbox2dd.a` (`src/CMakeLists.txt:88`, `:97`), this one emits
  `libbox2d.a` in Debug too. Reproducing the postfix would make the installed
  Debug tree unlinkable by the `-lbox2d` its own `box2d.pc` names.
* Upstream's `B2_ENABLE_ASSERT` public define under `RelWithDebInfo`
  (`src/CMakeLists.txt:140`) has no counterpart: Zig has no such configuration
  and this package never targets the MSVC ABI. `NDEBUG` reaches
  `include/box2d/base.h:101` and `src/core.c:62-67` from the optimize mode alone,
  so the optimize mode alone selects whether `b2InternalAssertFcn` is compiled.
* `-ffp-contract=off` reaches the same files upstream's guard covers — the core,
  `shared/`, `test/` and `benchmark/main.c` — but unconditionally instead of
  under `CMakeLists.txt:37-41`'s `MINGW OR APPLE OR UNIX` test. The two OS tags
  that test excludes, MSVC and Emscripten, are targets this build graph cannot
  produce, so no target in the matrix can tell the two apart.
  `test/test_determinism.c` is the fixture that would notice, and that becomes a
  result only when `zig build upstream-test` runs.
* `box2d.pc` is fork-authored: upstream ships no `.pc.in` at this pin. It records
  `-lm` on the targets whose core system libraries include libm, because
  `include/box2d/math_functions.h:9` includes `<math.h>` and the scalar paths
  call `sinf`, `cosf` and `atan2f`; there is no `Libs.private`, because the same
  file has to describe the static install too.
* `bin/box2d-benchmark` is installed in every linkage and optimize mode on
  every target except `wasm32-wasi`, where
  `extern/enkiTS/src/TaskScheduler.h:22` includes `<thread>` and Zig 0.16's WASI
  C++ library has none. The build graph prints that on its configure line.
* A requested `-Dlinkage` is never substituted. A `-Dtarget` that cannot carry
  the requested linkage is refused at configure time (`build.zig:1477-1480`):
  a printed `error:` and an exit, no artifact. `zig build check` under
  `-Dlinkage=dynamic` covers five targets and names the sixth it leaves out
  (`box2d: check: <triple> is NOT covered by this run.`); the default static
  linkage still walks all six, `wasm32-wasi` included.
  `cross-test.profile.sh` reports the WASI refusal under
  `CROSS_BUILD_ARGS=(-Dlinkage=dynamic)` as a platform failure, not coverage.
* `UPSTREAM.sha256` is not installed: it is a repository integrity record, not
  material that ships with a library.

### API

* Typed Zig surface over the whole public API: world lifecycle and stepping,
  bodies, all shape kinds, chains, all eight joint types, queries and casts,
  event slices, the dynamic tree, geometry, math, collision manifolds, the
  character mover, allocator and assert hooks. Naming is mechanical: the C name
  minus `b2`, camelCase.
* The raw translated route stays complete on the same module as `c`.
* A runtime-loading route: one immutable process-lifetime table per configured
  module, explicit `load(.{.path=...})` or `load(.{.system=...})`, no fallback,
  no owning handle, no unload, no automatic retry, ordinary panic before a
  successful load in every optimize mode. Synchronisation prefix `box2d_rt`.
* Tests are independent known answers and behavioural boundaries. No presence,
  default, version, forwarding or source-text assertions.

### Packaging

* `package.nix`: one uncurried derivation of `{lib, stdenv, zig, pkg-config,
  linkage ? "static"}`, source-only, no fetch, no sibling import, no host path,
  no `builtins.getEnv`, no `builtins.currentSystem`. It calls
  `zig build install` with `-Dcpu=baseline`, one `-Doptimize`, one `-Dlinkage`,
  `-j $NIX_BUILD_CORES` and `--prefix "$out"`, with both Zig caches under
  `$TMPDIR`, and asserts the installed closure.
* `flake.nix`: `packages.<system>.static`, `.shared` and `.default` (static),
  plus a tools-only `devShells.default`. One pinned nixpkgs input.
* `devenv.nix`: tools only, lazy `outputs.static`, `outputs.shared` and
  `outputs.default` over the same `package.nix`, namespaced `box2d:*` tasks with
  real `exec` commands. `devenv.yaml` pins its own nixpkgs input; `.envrc`
  hands the directory to devenv and applies the host scratch policy at load
  time.
* Neither entry point writes a lock. Both locks are the driver's.

### Provenance

* `UPSTREAM.md`: the pin, the complete per-area inventory, and the licence of
  every carried area including the vendored trees.
* `NOTICE.md`: the per-file inventory. 119 files carry
  `SPDX-License-Identifier: MIT`; the four exception groups are named with the
  file and line that carries each grant.
* `FORK-LICENSE.md`: the owner's direct authorisation of 2026-10-04 for the
  fork-authored files under MIT, matching upstream's primary term, with the
  covered file list and the travel obligations.
* `UPSTREAM.sha256`: 267 digest records. `sha256sum -c UPSTREAM.sha256` was
  observed passing 267/267 with 0 failures on 2026-10-04. `.gitignore` is
  excluded on purpose, with the reason in the record's own header.
* `README.md` in the canonical order: native-source deviations (none),
  native-build deviations, the build/run/test matrix, consumption.
* `README.zig.md`: the Zig interface, the options, both routes, the typed
  surface, the raw route, and the external ABI boundaries — scalar, layout,
  config, allocator and lifetime — stated as boundaries rather than as a version
  string.

### Not claimed at this entry

At the time of this entry no build, test, smoke, cross-target, matrix or Nix
gate had been run against the tree. That was the state of this import; the
gates that have since run, and the ones that have not, are in `README.md` §3.