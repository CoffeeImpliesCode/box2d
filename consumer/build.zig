// SPDX-License-Identifier: MIT

//! Build wiring for the separate consumer package.
//!
//! This package exists to prove one thing: that a dependent needs only
//! `dep.module("box2d")` and gets a working, correctly linked Box2D. If the
//! facade module stopped carrying its C artifact, or the translated headers
//! stopped matching the C sources, this would stop building or stop producing
//! the answers below, and nothing inside the library would notice.
//!
//! It deliberately asks for `dep.module("box2d")` and nothing else — no
//! `dep.artifact`, no `dep.header`, no include path of its own and no
//! `link_libcpp`. Every one of those would be a second way in, and a proof that
//! used one of them would not be a proof about the published module. The
//! library module carries `link_libc`, the translated headers as `c` and the
//! archive behind them, so a dependent states nothing and gets everything.
//!
//! Run it with `zig build run`, or with `zig build install` for a target this
//! host cannot execute, which is what `../build.zig`'s `runConsumer` asks for
//! then. `src/main.zig` exits non-zero if a value disagrees with an answer
//! derived independently of this build, so this is a check and not a demo.
//!
//! Arguments after `--` belong to the program, not to this package:
//! `zig build run -- --provider <path>` is how a `-Druntime=true` build names
//! the shared object `src/main.zig` then loads, and this package's `run` step
//! is the one place those arguments become the program's. The SDK's own route
//! reaches them by emitting `--` and handing its own `b.args` on
//! (`../build.zig`, `runConsumer`), so the two ends are one handover and not
//! two independent choices.
//!
//! Seven options are forwarded rather than invented:
//!
//!   -Dtarget=<triple>      `standardTargetOptions`, forwarded to the
//!                           dependency so both builds agree about the target.
//!   -Doptimize=<mode>      `standardOptimizeOption`, same reason.
//!   -Dlinkage=static|dynamic
//!                           the library's own delivery option, forwarded
//!                           verbatim. This package has no opinion about it:
//!                           an option left unset here is not passed on at all,
//!                           so the library's own default decides and a caller
//!                           who passes nothing changes nothing. Forwarding it
//!                           is what lets one consumer package exercise both
//!                           the static archive and the shared object route of
//!                           the same published module.
//!   -Druntime=true         the library's own dispatch option, forwarded
//!                           verbatim and independently of `-Dlinkage`: it
//!                           says how the facade reaches the library, not
//!                           which artifact the library delivers and installs.
//!                           `src/main.zig` is written for both shapes, so
//!                           every combination is a real program and not a
//!                           compile-only configuration.
//!
//!   -Dvalidate=true|false
//!                           Box2D's own `BOX2D_VALIDATE` switch, forwarded
//!                           verbatim. It is private to the library's compile
//!                           line and moves no declaration, so every value is a
//!                           real program here rather than a compile-only
//!                           configuration.
//!   -Ddisable-simd=true|false
//!                           upstream's `BOX2D_DISABLE_SIMD`, forwarded
//!                           verbatim for the same reason.
//!   -Davx2=true|false       upstream's `BOX2D_AVX2`, forwarded verbatim. The
//!                           library applies it on x86_64 only and not while
//!                           `-Ddisable-simd` is on, and its own configure
//!                           line reports a request it did not apply.
//!
//! The library manifest carries its own `.fingerprint`
//! (`../build.zig.zon:12`), and this package carries a different one of its own
//! (`build.zig.zon:12`) because it is a different package with a different
//! name. A path dependency's fingerprint is not restated anywhere below, and
//! this build must not invent or edit one.
//!
//! ## A Zig root has to choose its own code generator
//!
//! `b.addExecutable` takes `use_llvm` (`std/Build/Step/Compile.zig:284`) and a
//! module does not: the library module this package imports cannot carry the
//! choice for the program that imports it, and `b.dependency` has no field for
//! it. So this root states it for itself.
//!
//! It matters because the failure it prevents is on the Zig side of the C
//! boundary, not the C side: `compile lib box2d` succeeds and upstream's own
//! `test/main.c` prints `All Box2D tests passed!` on targets where the Zig half
//! hands `b2CreateBody` a pointer it cannot dereference. The cause is an
//! aggregate ABI one — `b2WorldId` is a four-byte struct passed by value and
//! `b2MakeBox` returns `b2Polygon` by value — and `../build.zig`'s
//! `llvm_required` records the evidence, the reasoning and the bound. Nothing
//! about the public ABI depends on it: no declaration, layout or exported
//! symbol moves with the code generator.
//!
//! `zig/root.zig`, `../tests.zig` and `../smoke.zig` are roots in the same
//! sense and are configured in `../build.zig`; any other dependent needs the
//! same one line.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Every option the library owns is declared here rather than accepted and
    // dropped: `b.option` is what makes an unknown `-D` a configuration error
    // instead of a silently ignored flag, so passing one of these to this
    // package and not forwarding it would be a lie the build system could have
    // caught.
    //
    // None of them carries a default here, and that is the load-bearing part.
    // `std.Build` records a dependency argument only when it carries a value --
    // `addUserInputOptionFromArg` is documented "if null, the value won't be
    // added, but `T` will still be type-checked" (`lib/std/Build.zig:435`) and
    // an optional is unwrapped ahead of the switch that skips it (`:569-581`)
    // -- so a null here is not forwarded at all and the library's own default
    // stays in charge. Answering the question in this package as well would
    // put two defaults for one option in the tree, and this one would be the
    // one that is wrong the day the library moves.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Forwarded to the box2d dependency unchanged. It selects which artifact " ++
            "the library module links; it does not change anything in this " ++
            "package. Left unset, the option is not passed on and the library's " ++
            "own default decides.",
    );
    const runtime = b.option(
        bool,
        "runtime",
        "Forwarded to the box2d dependency unchanged. The facade then reaches " ++
            "the native entry points through one process-lifetime table an " ++
            "explicit load(source) fills instead of through a link line, and " ++
            "the module links no archive. The library is still built and " ++
            "installed. Left unset, the option is not passed on and the " ++
            "library's own default decides.",
    );

    // Box2D's three private compile-line defines, on exactly the terms
    // `-Dlinkage` is on. None of them is a value this package hands to its own
    // program; each one configures the dependency, and a nested build that
    // chose its own answer would compile a different Box2D than the one the
    // caller asked to be proven. They are private (`src/CMakeLists.txt:119-122`
    // for validation, `src/core.h:59` and `:65` for the two vector-width
    // switches) and move no declaration in any of the six public headers, so
    // `src/main.zig` is one program for every combination of them.
    const validate = b.option(
        bool,
        "validate",
        "Forwarded to the box2d dependency unchanged: upstream's BOX2D_VALIDATE, " ++
            "on by default at CMakeLists.txt:66. Private to the library's own " ++
            "compile line, so it changes behaviour and not the translated headers.",
    );
    const disable_simd = b.option(
        bool,
        "disable-simd",
        "Forwarded to the box2d dependency unchanged: upstream's " ++
            "BOX2D_DISABLE_SIMD, off by default at CMakeLists.txt:43.",
    );
    const avx2 = b.option(
        bool,
        "avx2",
        "Forwarded to the box2d dependency unchanged: upstream's BOX2D_AVX2, " ++
            "off by default at CMakeLists.txt:47. The library applies it on " ++
            "x86_64 only and not while -Ddisable-simd is on, and its configure " ++
            "line says so when a request is not applied.",
    );

    // `b.dependency`'s second argument is `anytype` in Zig 0.16 and is turned
    // into user input options by `Build.userInputOptionsFromArgs`, so this is an
    // anonymous struct literal rather than a named options type. Every key in
    // it must be a `-D` option the dependency's own `build.zig` declares, which
    // is why all five are declared there before they are forwarded here. That
    // is also why `disable-simd` is a quoted field: `std.Build` registers a
    // dependency argument under its *field name* — the `Target` case at
    // `lib/std/Build.zig:440` and the scalar case at `:504` — so a field
    // spelled `disable_simd` would hand the library an option it never asks
    // for, which is then reported as an unused flag (`:1644-1651`).
    const dep = b.dependency("box2d", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        .validate = validate,
        .@"disable-simd" = disable_simd,
        .avx2 = avx2,
    });

    // No `link_libc` here on purpose either. The C requirement belongs to the
    // library module, which carries it; a dependent states its own, and this
    // program needs nothing beyond what the library already brings. Adding it
    // here would hide a library that forgot to declare it.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("box2d", dep.module("box2d"));

    const exe = b.addExecutable(.{
        .name = "box2d-consumer",
        .use_llvm = true,
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // The caller's own arguments, behind `--`. This is the other end of the
    // handover `../build.zig`'s `runConsumer` opens: `b.args` here is the
    // *nested* build's, and nothing else turns it into the program's argv.
    if (b.args) |args| run_exe.addArgs(args);
    run_exe.has_side_effects = true;
    b.step("run", "Build and run the consumer program").dependOn(&run_exe.step);
}
