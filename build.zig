// SPDX-License-Identifier: MIT

//! Zig 0.16 build for the Box2D 2D physics engine.

const std = @import("std");

/// Runtime and linked builds share one core module to preserve LoadSource and LoadError identity.
const runtime_graph = @import("runtime/graph.zig");

const manifest = @import("build.zig.zon");

const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

const module_name = "box2d";
const lib_name = "box2d";

const facade_source = "zig/root.zig";

const translate_header = "zig/translate.h";

/// Test root; the test blocks are declared in tests.zig.
const test_source = "tests.zig";

const example_source = "smoke.zig";

/// Upstream's own version, read out of `CMakeLists.txt:6`
/// (`project(box2d VERSION 3.1.1 ...)`) and out of `src/core.c:69-77`, where
/// `b2GetVersion` returns `{3, 1, 1}`.
const upstream_version: std.SemanticVersion = .{ .major = 3, .minor = 1, .patch = 1 };

/// Upstream VERSION 3.1.1 and SOVERSION 3 (src/CMakeLists.txt:95-97).
const soversion: std.SemanticVersion = .{ .major = 3, .minor = 1, .patch = 1 };

/// Explicit translation-unit list from upstream's BOX2D_SOURCE_FILES.
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

/// Upstream's six installed public headers (src/CMakeLists.txt:63-70).
const public_headers = [_][]const u8{
    "include/box2d/base.h",
    "include/box2d/box2d.h",
    "include/box2d/collision.h",
    "include/box2d/id.h",
    "include/box2d/math_functions.h",
    "include/box2d/types.h",
};

/// Include root for the installed <box2d/...> headers.
const include_dir = "include";

const source_dir = "src";

/// Provides b2MakeAABB; translate-c emits its B2_INLINE definition as extern.
const bridge_dir = "build_support";

const bridge_sources = [_][]const u8{
    "box2d_inline_bridge.c",
};

const support_sources = [_][]const u8{
    "benchmarks.c",
    "determinism.c",
    "human.c",
    "random.c",
};
const support_dir = "shared";

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

const benchmark_source = "benchmark/main.c";

/// enkiTS compile closure, built with -std=c++11.
const enki_source_dir = "extern/enkiTS/src";
const enki_sources = [_][]const u8{
    "TaskScheduler.cpp",
    "TaskScheduler_c.cpp",
};

const licence_records = [_][]const u8{
    "LICENSE",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "FORK-NOTES.md",
};

const enki_licence = "extern/enkiTS/License.txt";
const enki_licence_dest = "enkiTS-License.txt";

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Graph = struct {
    c_lib: *std.Build.Step.Compile,
    static_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
    c_module: *std.Build.Module,
};

const Tools = struct {
    enki: ?*std.Build.Step.Compile,
    support: *std.Build.Step.Compile,
};

const Options = struct {
    requested_linkage: std.builtin.LinkMode,
    validate: bool,
    disable_simd: bool,
    avx2: bool,
    runtime_loaded: bool,
};

/// Adds the target triple to private artifact names.
fn artifactName(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    public: bool,
) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Reject dynamic linkage when the target has no dynamic loader.
fn targetCanCarry(
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) bool {
    return requested == .static or target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

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

/// Zig 0.16's wasm32-wasi C++ runtime has no threads.
fn targetHasCxxThreads(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag != .wasi;
}

/// OpenBSD 32-bit ARM needs scalar math because this toolchain rejects __bf16 in arm_neon.h.
fn armNeonNeedsScalar(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag != .openbsd) return false;
    return switch (target.result.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => true,
        else => false,
    };
}

fn scalarMath(target: std.Build.ResolvedTarget, options: Options) bool {
    return options.disable_simd or armNeonNeedsScalar(target);
}

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
        // Upstream enables AVX2 only on x86_64 with SIMD enabled.
        out_flags.append(b.allocator, "-DBOX2D_AVX2") catch @panic("OOM");
        out_flags.append(b.allocator, "-mavx2") catch @panic("OOM");
    }
}

/// Core and test C standards match upstream: gnu17 and c17.
/// -ffp-contract=off preserves upstream's deterministic math behavior (CMakeLists.txt:37-41).
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

/// glibc and musl require libm; Darwin provides these symbols in libSystem.
fn coreSystemLibraries(target: std.Build.ResolvedTarget) []const []const u8 {
    const os_tag = target.result.os.tag;
    return switch (os_tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .windows => &.{},
        else => &.{"m"},
    };
}

/// Adds the bridge source to the core module so its symbol uses the same flags.
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
        .link_libc = true,
        .pic = if (shared) true else null,
    });
    c_mod.addIncludePath(b.path(include_dir));
    c_mod.addIncludePath(b.path(source_dir));
    for (coreSystemLibraries(target)) |lib| {
        c_mod.linkSystemLibrary(lib, .{});
    }
    if (shared) {
        // Shared builds export Box2D symbols through this macro.
        c_mod.addCMacro("box2d_EXPORTS", "1");
    }
    c_mod.addCSourceFiles(.{
        .root = b.path(source_dir),
        .files = &core_sources,
        .flags = flags,
        .language = .c,
    });

    c_mod.addCSourceFiles(.{
        .root = b.path(bridge_dir),
        .files = &bridge_sources,
        .flags = flags,
        .language = .c,
    });

    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = options.requested_linkage,
        // Upstream SONAME 3 and VERSION 3.1.1 (src/CMakeLists.txt:95-97).
        .version = if (shared) soversion else null,
        .root_module = c_mod,
    });

    for (public_headers) |header| {
        c_lib.installHeader(b.path(header), b.fmt("box2d/{s}", .{std.fs.path.basename(header)}));
    }

    return c_lib;
}

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
        // enkiTS uses C++ standard-library headers, so link libc++.
        .link_libcpp = true,
    });
    enki_mod.addIncludePath(b.path(enki_source_dir));
    for (posixThreadLibraries(target)) |lib| {
        enki_mod.linkSystemLibrary(lib, .{});
    }
    enki_mod.addCSourceFiles(.{
        .root = b.path(enki_source_dir),
        .files = &enki_sources,
        .flags = &.{"-std=c++11"},
        .language = .cpp,
    });

    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = enki_mod,
    });
}

fn posixThreadLibraries(target: std.Build.ResolvedTarget) []const []const u8 {
    return switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly, .illumos => &.{"pthread"},
        else => &.{},
    };
}

/// Upstream tests link the static core because they call private functions.
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

/// NetBSD __END_DECLS expands to a pragma Aro cannot parse; preprocess those headers first.
const TranslateRoute = enum {
    aro,
    preprocessed,
};

fn translateRoute(target: std.Build.ResolvedTarget) TranslateRoute {
    return if (target.result.os.tag == .netbsd) .preprocessed else .aro;
}

/// The depfile tracks included headers so cached translations follow their changes.
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
    run.addPrefixedDirectoryArg("-I", b.path(include_dir));
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("box2d-translate.c");
    run.addArg("-MD");
    _ = run.addPrefixedDepFileOutputArg("-MF", "box2d-translate.d");
    run.addFileArg(b.path(translate_header));
    return preprocessed;
}

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
    // Dynamic delivery needs a second static core for upstream's tests.
    const static_lib = if (!shared)
        c_lib
    else
        addCoreLibrary(b, target, optimize, static_options, b.fmt("{s}-static", .{
            artifactName(b, target, public),
        }));

    const translate = b.addTranslateC(.{
        .root_source_file = switch (translateRoute(target)) {
            .aro => b.path(translate_header),
            .preprocessed => preprocessedTranslateHeader(b, target),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate.addIncludePath(b.path(include_dir));
    if (shared and target.result.os.tag == .windows) {
        // Upstream's interface define; the library compile adds box2d_EXPORTS.
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
    module.addIncludePath(b.path(include_dir));
    if (shared and target.result.os.tag == .windows) {
        module.addCMacro("BOX2D_DLL", "1");
    }

    if (options.runtime_loaded) {
        // Loaded dispatch links no archive; the built artifact remains installable.
        module.addImport("c", runtime_graph.createModule(b, translate, target, optimize));
    } else {
        // Keep the translated module private; the facade import links its library.
        module.addImport("c", c_module);
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

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

/// Dependent Zig roots must set .use_llvm for the facade's aggregate C ABI.
const llvm_required = true;

/// Each root sets its own libc requirement; the facade links the archive.
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

fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");

    // Dynamic targets without loaders are reported as uncovered.
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
        std.debug.print("box2d: check: {s} has no C++ threads; upstream's own test suite and the benchmark tool are not compiled for it\n", .{triple});
    }

    if (addBenchmark(b, cross_target, optimize, built.graph, built.tools, b.fmt("box2d-benchmark-{s}", .{triple}))) |tool| {
        step.dependOn(&tool.step);
    }
}

/// Writes relocatable pkg-config metadata.
/// Adds libm for glibc/musl and BOX2D_DLL for shared Windows builds.
fn addPkgConfig(b: *std.Build, target: std.Build.ResolvedTarget, linkage: std.builtin.LinkMode) void {
    var libs: std.ArrayList([]const u8) = .empty;
    libs.appendSlice(b.allocator, &.{ "-L\"${libdir}\"", "-lbox2d" }) catch @panic("OOM");
    for (coreSystemLibraries(target)) |lib| {
        libs.append(b.allocator, b.fmt("-l{s}", .{lib})) catch @panic("OOM");
    }
    const files = b.addWriteFiles();
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
        if (linkage == .dynamic) " -DBOX2D_DLL" else "",
    })), .lib, "pkgconfig/box2d.pc");
    b.getInstallStep().dependOn(&install_pc.step);
}

/// addInstallFileWithDir returns unattached steps; dependOn schedules each record.
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

fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    // The target triple omits CPU features; forward the serialized CPU query too.
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    // Run the same Zig executable that configured this build.
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(options.requested_linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (options.runtime_loaded) "true" else "false"}));
    run.addArg(b.fmt("-Dvalidate={s}", .{if (options.validate) "true" else "false"}));
    run.addArg(b.fmt("-Ddisable-simd={s}", .{if (options.disable_simd) "true" else "false"}));
    run.addArg(b.fmt("-Davx2={s}", .{if (options.avx2) "true" else "false"}));
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    // Match this build's job width and summary in the nested build.
    run.addArg("-j8");
    run.addArgs(&.{ "--summary", "all" });
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    // Share the global package store; keep the local cache separate.
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArgs(&.{ "--global-cache-dir", global_cache });
    }
    // Forward an absolute prefix because the nested build runs in consumer/.
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        // QEMU needs libc runtimes to load foreign glibc executables.
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta => true,
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

    // Upstream defaults to static, which also enables its test target.
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
        // Dispatch is independent of which artifact the package delivers.
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

    if (!targetCanCarry(target, options.requested_linkage)) {
        std.debug.print("error: {s}\n", .{unsupportedLinkageReason(b, target)});
        std.process.exit(1);
    }

    // Keep the manifest version aligned with CMakeLists.txt and b2GetVersion.
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of CMakeLists.txt and src/core.c; see UPSTREAM.md");
    }

    const built = addGraph(b, target, optimize, options, true);
    const graph = built.graph;

    b.installArtifact(graph.c_lib);

    addPkgConfig(b, target, options.requested_linkage);
    installLicenceRecords(b);

    const benchmark = addBenchmark(b, target, optimize, graph, built.tools, "box2d-benchmark");

    // The example exercises the facade but is not installed.
    const example = b.addExecutable(.{
        .name = "box2d-smoke",
        .use_llvm = llvm_required,
        .root_module = programModule(b, target, optimize, graph.module, example_source),
    });
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    // tests.zig declares the test blocks; re-exports alone discover none.
    const unit_tests = b.addTest(.{
        .name = "box2d-tests",
        .use_llvm = llvm_required,
        .root_module = programModule(b, target, optimize, graph.module, test_source),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;

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
        const no_threads_reason =
            "box2d: upstream's own test/main.c suite needs extern/enkiTS, whose " ++
            "TaskScheduler.h includes <thread>; this target's C++ library has " ++
            "no threads. The core library, the facade, tests.zig and smoke.zig " ++
            "are still built for it.";
        test_step.dependOn(&b.addFail(no_threads_reason).step);
        b.step("upstream-test", "Build and run upstream's own unmodified test/main.c suite on its own")
            .dependOn(&b.addFail(no_threads_reason).step);
    }

    if (benchmark) |tool| {
        b.getInstallStep().dependOn(&tool.step);
        b.installArtifact(tool);
        b.step("benchmark", "Build upstream's benchmark/main.c tool").dependOn(&tool.step);
    }

    b.step("consumer", "Build the consumer/ package for the selected target, and run it when this host can execute it")
        .dependOn(&runConsumer(b, target, optimize, options).step);

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
