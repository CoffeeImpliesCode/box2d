// SPDX-License-Identifier: MIT
//
//! Box2D's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! Box2D's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every `B2_API` declaration in the six public headers this package
//! translates: `include/box2d/base.h`, `box2d.h`, `collision.h`, `id.h`,
//! `math_functions.h` and `types.h`. That is the whole declared library surface,
//! not the subset the typed facade in `zig/root.zig` happens to call, because a
//! caller that reaches `box2d.c` must find the same library behind every name
//! it can see.
//!
//! ## One configuration-dependent symbol, and what it costs
//!
//! `b2InternalAssertFcn` is declared under `#if !defined( NDEBUG ) || defined(
//! B2_ENABLE_ASSERT )` (`include/box2d/base.h:101-102`) and defined under the
//! same condition (`src/core.c:62-67`). Both sides of the same test means it
//! appears in this build's translation, and in a provider's export table, or in
//! neither.
//!
//! That is a real pairing requirement for the loaded route and this file does not
//! pretend otherwise:
//!
//!   * A **Debug or ReleaseSafe** consumer does not define `NDEBUG`, so its
//!     translation declares the symbol, so the dispatch requires it, so the load
//!     refuses a provider that was built with `NDEBUG` defined.
//!   * A **ReleaseFast or ReleaseSmall** consumer does define `NDEBUG`, so the
//!     symbol is absent from its translation, absent from the table, and irrelevant
//!     to the load. Any provider works.
//!
//! So a loaded provider for a Debug or ReleaseSafe consumer has to be built
//! without `NDEBUG`, or with `B2_ENABLE_ASSERT` defined. It is not an *optional*
//! entry point, and that is deliberate: in this configuration nothing is linked
//! for the C library to supply it from, so an `extern` left direct would be an
//! undefined symbol at link time rather than a load-time answer. `runtime/graph.zig`
//! therefore leaves it routed and records the pairing here.
//!
//! In terms of this package's own commands:
//!
//! ```sh
//! zig build -Dlinkage=dynamic -Doptimize=Debug         # exports b2InternalAssertFcn
//! zig build -Dlinkage=dynamic -Doptimize=ReleaseSafe   # exports it
//! zig build -Dlinkage=dynamic -Doptimize=ReleaseFast   # does not export it
//! zig build -Dlinkage=dynamic -Doptimize=ReleaseSmall  # does not export it
//! ```
//!
//! The rule that follows is one provider per consumer mode, and it is a rule
//! about the provider's build rather than its source: a `Debug` or
//! `ReleaseSafe` consumer is offered a provider built in that same mode, and a
//! `ReleaseFast` or `ReleaseSmall` consumer is offered any provider this
//! package builds, because its table does not carry the symbol at all.
//!
//! ```sh
//! zig build install -Dlinkage=dynamic -Doptimize=Debug       --prefix <scratch>/box2d-shared-Debug
//! zig build install -Dlinkage=dynamic -Doptimize=ReleaseSafe --prefix <scratch>/box2d-shared-ReleaseSafe
//!
//! BOX2D_TEST_PROVIDER=<scratch>/box2d-shared-Debug/lib/libbox2d.so \
//!   zig build test smoke -Druntime=true -Dlinkage=dynamic -Doptimize=Debug
//! ```
//!
//! `-Dlinkage=dynamic` is what makes the install produce a loadable object at
//! all: the same install with `-Dlinkage=static` writes `libbox2d.a`, and a
//! `-Druntime` gate never links that archive, so it still has to be offered a
//! shared object. `BOX2D_TEST_PROVIDER` is the one variable both the tests and
//! the smoke program read (`tests.zig:72`, `smoke.zig:344-354`); the smoke
//! program also takes `--provider <path>` directly. One provider per mode, and
//! every loaded gate of that mode names it.
//!
//! What a mismatch looks like at run time: the load returns `MissingSymbol`,
//! and `runtime/loader.zig` prints the library name and the symbol it wanted
//! before closing the candidate. `b2InternalAssertFcn` in that line means the
//! consumer is `Debug` or `ReleaseSafe` and the provider was built with
//! `NDEBUG`; there is no other symbol in this table a correct provider of this
//! pin lacks.
//!
//! The build graph defines neither `NDEBUG` nor `B2_ENABLE_ASSERT`; `NDEBUG`
//! arrives from the optimize mode alone, on the library's compile line and on
//! every translation alike, which is what makes the pairing predictable. (The
//! one upstream rule with no counterpart here is `src/CMakeLists.txt:140`, which
//! adds `B2_ENABLE_ASSERT` under MSVC's RelWithDebInfo. This package never
//! targets the MSVC ABI, and inventing a substitute would change upstream's
//! compiled behaviour; `FORK-NOTES.md` records it as a native-build deviation.)
//!
//! So a ReleaseFast or ReleaseSmall provider offered to a Debug or ReleaseSafe
//! consumer is refused at load. That is the correct outcome and not a defect in
//! either file: the consumer's translation asked for an entry point that provider
//! does not have, and a load-time refusal says so instead of letting the program
//! die on the first `B2_ASSERT`.
//!
//! Every other `B2_API` declaration in the six headers is unconditional at this
//! pin, and every one of them is a function: there is no exported data symbol in
//! the public surface, so no table entry has to keep a provider address live.
//!
//! ## The ABI boundary, stated honestly
//!
//! A provider must be Box2D 3.x built from a header this build's translation
//! read. The reasons are structural rather than stylistic, and they are what the
//! checks below are really about:
//!
//!   * Every public entry point takes a `b2Vec2`, `b2Rot`, `b2Transform`,
//!     `b2AABB`, `b2Circle`, `b2Capsule`, `b2Polygon` or `b2WorldDef` **by
//!     value**. Their layouts are two `float`s, two `float`s, a `b2Vec2` plus a
//!     `b2Rot`, and so on, so the platform's scalar widths *are* the ABI.
//!   * The definitions (`b2WorldDef`, `b2BodyDef`, `b2ShapeDef`, `b2ChainDef`,
//!     `b2DebugDraw`, the event structs) are passed **by pointer** and are
//!     larger than one register. Their field order and padding are the ABI, and
//!     the `internalValue` field upstream reserves in each of them
//!     (`include/box2d/types.h:142,239,407,457`) is what upstream's own
//!     `B2_CHECK_DEF` reads to reject a definition this build did not produce.
//!   * The ids (`b2WorldId`, `b2BodyId`, `b2ShapeId`, `b2ChainId`,
//!     `b2JointId`, `include/box2d/id.h`) are small structs of `u16`/`i32`
//!     passed by value, and the index in them is 1-based
//!     (`src/world.c:260`), so a provider whose ids are 0-based would answer
//!     every `*_IsValid` question wrongly.
//!
//! Callbacks are the fourth family: `b2FrictionCallback`, `b2RestitutionCallback`,
//! `b2CustomFilterFcn`, `b2PreSolveFcn`, `b2OverlapResultFcn`, `b2CastResultFcn`
//! and `b2PlaneResultFcn` are `void*`-context C function pointers the *provider*
//! calls back through. The caller passes them in a `b2WorldDef` or through
//! `b2World_Set*`, so the convention on both sides has to be the C one.
//!
//! ## What is checked at load time, and what is not
//!
//! Resolving a symbol and translating a header are the boundary. They are not
//! proof that a provider is compatible, and this file does not pretend to add
//! one. Two entry points are called after every symbol resolved and before
//! anything is published:
//!
//!   * `b2GetVersion()` must report `major == 3`. Major 3 is the generation
//!     that replaced the `b2World*` pointer API with ids and moved every
//!     definition to the `b2*Def` structs read here, so a provider reporting
//!     anything else has a different ABI, not merely a different release.
//!   * `b2GetLengthUnitsPerMeter()` must be greater than zero. It reads a
//!     process global the library initialises to `1.0f` when it is loaded
//!     (`src/core.c:33`) and whose setter upstream asserts is finite and positive
//!     (`src/core.c:35-39`), so a zero, negative or NaN answer means the entry
//!     point resolved but did not run.
//!
//! Both are checks that the entry points *behave*, on a library that is
//! already fully resolved. Neither inspects a struct layout, and no load-time
//! check can: the caller is the only party that knows what it built. A caller
//! that cares about layout has to compile the same headers, which is what this
//! package does.

const std = @import("std");
const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=box2d_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn box2d_rt_lock() void;
    extern fn box2d_rt_unlock() void;
    extern fn box2d_rt_wait() void;
    extern fn box2d_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn box2d_rt_thread_self() u64;

    pub fn lock() void {
        box2d_rt_lock();
    }
    pub fn unlock() void {
        box2d_rt_unlock();
    }
    pub fn wait() void {
        box2d_rt_wait();
    }
    pub fn broadcast() void {
        box2d_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return box2d_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "box2d";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// Both calls are on entry points that take nothing and return a value
        /// by copy, so neither needs a world, a body or a lock. A provider that
        /// cannot answer them is not the library this header describes, and it
        /// is better to say so here than to have the first `b2World_Step` in the
        /// program produce a number.
        pub fn validate(dst: *const table) ?[]const u8 {
            const version = dst.b2GetVersion();
            if (version.major != 3) {
                return validationMessage(
                    "b2GetVersion() reported major {d}, so this provider is not the " ++
                        "Box2D 3.x ABI this header describes: its ids, its definitions " ++
                        "and its by-value structs do not line up with the ones this " ++
                        "build compiled against",
                    .{@as(c_int, version.major)},
                );
            }
            const length_units = dst.b2GetLengthUnitsPerMeter();
            if (!(length_units > 0)) {
                return validationMessage(
                    "b2GetLengthUnitsPerMeter() answered {d}, which is not a positive " ++
                        "length scale, so the entry point resolved but did not run",
                    .{@as(f32, length_units)},
                );
            }
            return null;
        }
    };
}

/// One scratch buffer for the load-time messages that carry a number.
///
/// The loader retains nothing but the table and the request, so a message built
/// here only has to outlive the `load` call that returns it. That call is the
/// only writer: `validate` runs inside a load attempt, and two attempts for one
/// configured module never run at once (`runtime/loader.zig`), so the buffer is
/// written once per load and read by the caller of that load. A second SDK in
/// the same process has its own copy of this file and therefore its own buffer.
var message_buffer: [256]u8 = undefined;

/// Render `format` into `message_buffer`.
///
/// The two callers pass a `c_int` and an `f32`, which always fit: a decimal
/// `int` is at most eleven characters, and a `float` prints as a `nan`/`inf`
/// spelling or as at most fifteen digits with a sign, and the longer of the two
/// messages is 206 characters plus its number. The fallback can therefore only
/// be reached if this file is edited to pass something else, or to use a longer
/// message, and it says what happened rather than dropping the check.
fn validationMessage(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "box2d: a load-time check failed and its value could not be printed";
}

