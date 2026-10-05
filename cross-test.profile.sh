# cross-test profile for the box2d package.
#
# `cross-test` finds this file by itself when it is run from the package root,
# and sources it as trusted Bash. It is configuration, not a test: everything
# below is a setting the harness already has a default for, written out so the
# gate this package is verified by can be read without reading the harness.
#
# The harness keeps everything that decides what actually runs. The command is
# `zig build test -Dtarget=TARGET` over this package's real build graph, the
# matrix is the published Zig 0.16.0 Tier 1/2 platform table, and QEMU-user,
# Wasmtime, Wine and native execution are chosen by the harness. Nothing here
# replaces a build step, names an artifact, or adds a `zig build` option.
#
# Deliberately absent, and why:
#
#   * CROSS_MATRIX and TARGETS. The matrix is the whole published table. A
#     profile that names a subset still exits zero when the subset is green,
#     which is a narrower gate wearing the same exit code.
#   * cross_build_command / cross_artifact. Those switch the harness out of
#     the standard build into an artifact profile with a hand-written command.
#     The point of this gate is that `zig build test` runs this package's own
#     binaries - the Zig tests and upstream's own `test/main.c` - over
#     upstream's own C, for the selected target.
#   * Any -D option. The harness owns -Dtarget and the output/cache/run
#     settings. This profile chooses no -Doptimize override, so its test
#     graph uses Debug; CROSS_BUILD_ARGS=(-Doptimize=ReleaseSafe) is accepted
#     for a separate mode. The six-target compile-only `check` matrix remains
#     a separate command.
#   * ZIG, CROSS_PREFIX, CROSS_CACHE_DIR or any other path. A profile that
#     names one host's compiler cache or output directory is not a package
#     file; it silently stops working on every other machine.
#   * CROSS_REQUIRE_RUNNERS=1. That flag fails a platform for having no runner
#     on this host. A platform whose runner is absent is already reported as
#     explicit `build_only` coverage, which is a fact and not a pass; demanding
#     a runner would report missing runtimes as broken targets.
#
# Top-level code is limited to variable definitions because the harness sources
# this file more than once per run and expects it to be idempotent.

# Linkage. This profile chooses none: the harness owns `-Dtarget`, and no `-D`
# option appears below, so every one of the 53 platforms is built through the
# package's default `static` graph - the linkage upstream's own build produces,
# and the one in which upstream's own `test/main.c` exists at all, because
# `CMakeLists.txt:101` only adds the test target when `NOT BUILD_SHARED_LIBS`.
# A shared-artifact matrix is a separate gate: it is the same `cross-test` run
# with `CROSS_BUILD_ARGS=(-Dlinkage=dynamic)` supplied by whoever runs it, so
# this file does not hard-code one linkage and silently narrow the other out.
# Under that flag a platform whose OS has no dynamic linker - WASI, whose
# `std.Target.DynamicLinker.kind` is `.none` - is refused rather than built:
# `build.zig` exits at configure with a message naming the target and the way
# out. That refusal is the correct result for a run that asked for a shared
# object, and it is reported as a failure of that platform under that flag, not
# as coverage: this build will not hand back a static archive where a shared one
# was requested.
#
# The build step `cross-test` runs: the package's own `test` step, which runs
# this fork's Zig tests and upstream's own unmodified `test/main.c` suite for
# the target the harness selected. Not `check`, which runs nothing.
CROSS_BUILD_STEP=test

# Overall deadline for one target's compile and complete test run.
#
# `zig build test` builds more per target than a single-test-root package does:
# the 35-file core, the four-file `shared` support library, the ten-file upstream
# suite, and the two-file C++ enkiTS closure with libc++ — and then runs both the
# Zig tests and upstream's suite. The first thing that gets close to this budget
# is `DeterminismTest`, which steps five falling-hinge worlds at 1/60 s with four
# substeps until each of them sleeps, and repeats that for `workerCount` 1 through
# 5. Under QEMU-user on an emulated AArch64 or RISC-V that is arithmetic, not
# vectorised, so it is the slowest thing in this package by a wide margin. Keep
# the whole suite: dropping `DeterminismTest` would drop the only test that
# proves multithreaded results are bit-identical to the single-threaded ones.
CROSS_BUILD_TIMEOUT=3600

# Per individual Zig test case, not per binary. Box2D's own suite is one
# executable printing its own progress, so the harness applies this to the
# Zig test binary rather than to `test/main.c`; the figure is kept generous for
# the same reason the whole-target budget is.
CROSS_TIMEOUT=1800
