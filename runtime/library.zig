// SPDX-License-Identifier: MIT
//
//! Box2D-specific runtime-loader bindings and provider validation.
//! The generic loader is in `runtime/loader.zig`.

const std = @import("std");
const rt = @import("rt");

/// Namespaced synchronization functions called by the loader.
/// The prefix must match `sync.c`'s `RT_SYNC_PREFIX` in `runtime/graph.zig`.
pub const Sync = struct {
    extern fn box2d_rt_lock() void;
    extern fn box2d_rt_unlock() void;
    extern fn box2d_rt_wait() void;
    extern fn box2d_rt_broadcast() void;
    // C `unsigned long long` is 64 bits on x86_64, aarch64, riscv64, and wasm32.
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

/// Loader descriptor for the generated dispatch.
/// Passing the dispatch type avoids an import cycle.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name printed in the pre-load panic.
        pub const library_name = "box2d";

        /// Generated table and its load-time symbol lists.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// Namespaced synchronization binding used by the loader.
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

        /// Check the provider's major version and positive length scale.
        /// Returns a refusal message when either check fails.
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

/// Scratch buffer for load-time validation messages.
/// Load attempts are serialized per configured module.
var message_buffer: [256]u8 = undefined;

/// Format a numeric validation refusal into the shared buffer.
fn validationMessage(comptime format: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(&message_buffer, format, args) catch
        "box2d: a load-time check failed and its value could not be printed";
}
