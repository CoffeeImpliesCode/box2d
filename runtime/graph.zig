// SPDX-License-Identifier: MIT
//
//! Builds the runtime-loaded `c` module from the target's translated headers.
//! The facade uses it instead of linking the C library.
const std = @import("std");

/// Prefix shared with `sync.c` and `library.zig`; all three spellings must match.
const sync_prefix = "box2d_rt";

/// C-library names reachable from public headers, with platform and precision variants.
/// Over-listing is inert; an unlisted declaration becomes a provider requirement.
const libc_math_bases =
    \\acos,acosh,asin,asinh,atan,atan2,atanh,
    \\cbrt,copysign,cos,cosh,sin,sinh,tan,tanh,
    \\exp,exp2,expm1,log,log10,log1p,log2,logb,
    \\fabs,fdim,fmax,fmin,fmod,fma,frexp,ldexp,modf,pow,sqrt,remainder,remquo,
    \\hypot,erf,erfc,lgamma,tgamma,
    \\ceil,floor,trunc,rint,round,nearbyint,roundeven,
    \\drem,significand,nan,j0,j1,jn,y0,y1,yn,gamma,lgamma_r,
    \\nextafter,nexttoward,scalbn,ilogb,scalbln,lrint,llrint,lround,llround,scalb,
    \\getpayload,getsign,putpayload,
    \\fegetround,fesetround,fegetenv,fesetenv,feholdexcept,fetestexcept,
    \\feraiseexcept,feupdateenv,fegetmode,fesetmode,
    \\_copysign,_finite,_hypot,_j0,_j1,_jn,_y0,_y1,_yn,
    \\finite,isnan,isinf,isfinite,isnormal,issignaling,signbit,fpclassify,iseqsig,
    \\chgsign,fpclass,signgam,sincos,cospi,sinpi,tanpi,exp10,inf,infinity,
    \\abs,atof,labs,gamma_r,rinttol,roundtol,
    \\__inline_isfinite,__inline_isinf,__inline_isnormal,
    \\_chgsign,_isnan,_logb,_nextafter,_fpclass,_cabs,_scalb,_matherr
;

/// Additional libc spellings outside the base-and-suffix expansion.
const libc_extra_names =
    \\__fpclassifyd,__imp__HUGE,__inline_isfinited,__inline_isinfd,__math_errhandling,
    \\__mingw_get_crt_info,__mingw_raise_matherr,__mingw_setusermatherr,__prefetch,
    \\__setusermatherr,__sincos_stret,__sincosf_stret,__sincospi_stret,__sincospif_stret,_atof_l
;

/// Comptime scratch; its fixed ceiling turns overflow into a build error.
/// A `const` initializer is required for comptime mutation.
const Noise = struct {
    buf: [64 * 1024]u8,
    len: usize,
};

/// Reserve space for a comma-separated name; an oversized write fails at comptime.
fn reserve(storage: *Noise, len: usize) []u8 {
    if (storage.len != 0) {
        storage.buf[storage.len] = ',';
        storage.len += 1;
    }
    const at = storage.len;
    storage.len += len;
    return storage.buf[at..][0..len];
}

const libc_noise_storage: Noise = blk: {
    @setEvalBranchQuota(100_000);
    const prefixes = .{ "", "__" };
    const suffixes = .{
        "",     "f",    "l",    "f16",  "f32",   "f64",
        "f128", "f16x", "f32x", "f64x", "f128x", "ieee128",
    };
    var storage: Noise = .{ .buf = undefined, .len = 0 };
    var bases = std.mem.splitScalar(u8, libc_math_bases, ',');
    while (bases.next()) |part| {
        // Wrapped names carry whitespace; trim it before matching.
        const base = std.mem.trim(u8, part, " \t\r\n");
        if (base.len == 0) continue;
        const reentrant = std.mem.endsWith(u8, base, "_r");
        const stem = if (reentrant) base[0 .. base.len - 2] else base;
        // Precision suffixes precede the reentrant `_r` marker.
        const marker = if (reentrant) "_r" else "";
        for (prefixes) |prefix| {
            for (suffixes) |suffix| {
                const name = reserve(&storage, prefix.len + stem.len + suffix.len + marker.len);
                @memcpy(name[0..prefix.len], prefix);
                @memcpy(name[prefix.len..][0..stem.len], stem);
                @memcpy(name[prefix.len + stem.len ..][0..suffix.len], suffix);
                @memcpy(name[prefix.len + stem.len + suffix.len ..][0..marker.len], marker);
            }
        }
    }
    var extras = std.mem.splitScalar(u8, libc_extra_names, ',');
    while (extras.next()) |part| {
        const name = std.mem.trim(u8, part, " \t\r\n");
        if (name.len == 0) continue;
        @memcpy(reserve(&storage, name.len), name);
    }
    break :blk storage;
};

/// Comma-separated expansion from the base and extra-name lists.
/// No optional exports. `b2InternalAssertFcn` stays routed when declared:
/// runtime mode has no linked archive to satisfy a direct extern.
const libc_noise: []const u8 = libc_noise_storage.buf[0..libc_noise_storage.len];
const provider_optional = "";

/// Provider exports excluded from the required set; currently none.
const provider_excluded = "";

/// Creates the loader module for linked builds to share its public loader types.
/// Runtime dispatches re-export these same `LoadSource` and `LoadError` types.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // The Unix backend calls libc's `dlopen`.
        .link_libc = true,
    });
}

/// Builds a runtime-loaded `c` module from this target's translated headers.
/// The generated dispatch follows the selected target and configuration.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // Re-export translated declarations to preserve their nominal type identity.
    // The patched `__root` resolves nested references to routed wrappers.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Run the host generator on the target's translated output.
/// Each build configuration produces its own dispatch.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("box2d-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("box2d");
    run.addArg("--translate");
    run.addFileArg2(translate.getOutput(), .{});
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg2("native.zig", .{});
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg2("dispatch.zig", .{});
    return .{ .native = native_source, .dispatch = dispatch_source };
}
