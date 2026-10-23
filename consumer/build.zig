// SPDX-License-Identifier: MIT

//! Downstream consumer wired through the public `box2d` module.
//! Exercises the linked and runtime-loaded package configurations.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Declare forwarded options without defaults, preserving the dependency's defaults.
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

    // Forward the dependency's private compile-line defines unchanged.
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

    // Dependency option keys must match its field names; quote `disable-simd`.
    const dep = b.dependency("box2d", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        .validate = validate,
        .@"disable-simd" = disable_simd,
        .avx2 = avx2,
    });

    // The dependency module carries its `link_libc` requirement.
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
    // Forward the caller's arguments after `--`.
    if (b.args) |args| run_exe.addArgs(args);
    run_exe.has_side_effects = true;
    b.step("run", "Build and run the consumer program").dependOn(&run_exe.step);
}
