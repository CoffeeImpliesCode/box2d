// SPDX-License-Identifier: MIT
//
//! Zig facade over Box2D's canonical C implementation.
//!
//! No part of the simulation is reimplemented here. Every number this module
//! returns is produced by the C under `src/`, reached through `pub const c`, the
//! module `b.addTranslateC` produces from `zig/translate.h` and the six public
//! headers it includes. What the facade adds is the part a C header cannot
//! express: a slice the compiler bounds instead of a `capacity` the caller can
//! get wrong, a creation that can be *refused* rather than silently answered
//! with a null handle, an out-parameter pair returned as a value, and one
//! documented statement about who owns what.
//!
//! ## Import routes
//!
//! One Zig route is published: `dep.module("box2d")` in the dependent's
//! `build.zig`, which is `@import("box2d")` in source. The raw translated header
//! is `c` on that same module and is not published as a module of its own, so
//! the declarations and the library that satisfies them arrive through one
//! route. A C consumer takes the installed header and archive instead;
//! `README.zig.md` names that layout.
//!
//! The shortest sequence that uses this module:
//!
//! ```zig
//! const std = @import("std");
//! const box2d = @import("box2d");
//!
//! pub fn main() void {
//!     var world_def = box2d.defaultWorldDef();
//!     world_def.gravity = box2d.vec2(0, -10);
//!     const world = box2d.createWorld(&world_def) catch unreachable;
//!
//!     var ground_def = box2d.defaultBodyDef();
//!     ground_def.position = box2d.vec2(0, -1);
//!     const ground = box2d.createBody(world, &ground_def) catch unreachable;
//!
//!     var ground_shape_def = box2d.defaultShapeDef();
//!     const ground_box = box2d.makeBox(10, 1);
//!     _ = box2d.createPolygonShape(ground, &ground_shape_def, &ground_box) catch unreachable;
//!
//!     var step: u32 = 0;
//!     while (step < 60) : (step += 1) box2d.worldStep(world, 1.0 / 60.0, 4);
//!     box2d.destroyWorld(world);
//! }
//! ```
//!
//! This package is developed and gated against Zig 0.16.0, which is the floor
//! `build.zig.zon` records.
//!
//! ## Names, and how to find the header for one
//!
//! Every function here is the C entry point with the `b2` prefix removed and the
//! rest camel-cased, so `bodyGetPosition` is `b2Body_GetPosition`
//! (`include/box2d/box2d.h:239`) and `worldCastRayClosest` is
//! `b2World_CastRayClosest` (`include/box2d/box2d.h:76`). Every doc comment
//! names the header line it came from. Nothing is renamed beyond that rule, so
//! the raw route and this one can be read side by side.
//!
//! ## What this module does not do
//!
//! It allocates nothing and owns nothing. There is no `World` type here that
//! hides upstream's state and no `deinit` to forget: a world is a `WorldId`,
//! which is a `b2WorldId` (`include/box2d/id.h:37`), and it is destroyed by
//! `destroyWorld`. Every struct this module names is upstream's own type, reached
//! through an alias, so a value produced here can be handed to `c` directly and
//! vice versa.
//!
//! It also does not wrap Box2D's pointers in Zig types. Upstream's own ids are
//! the handle, upstream's own structs are the payload, and a wrapper that hid
//! them would hide the generation checks that make stale-handle bugs
//! *detectable* rather than silent.
//!
//! ## Ownership, copying, and invalidation
//!
//! These are the rules a caller has to know, and they are upstream's, restated
//! where a header cannot:
//!
//!   * **Definitions are copied, never retained.** `createWorld`, `createBody`,
//!     `createChain` and the joint creators all take `*const b2*Def` and read it
//!     during the call; upstream stores values out of it, never the pointer
//!     (`include/box2d/box2d.h:203-208`). `createChain` is the one that *copies
//!     an array*: `b2ChainDef.points` is read and cloned
//!     (`include/box2d/types.h:434`), so the slice may be a temporary.
//!   * **Geometry is copied.** `b2CreateCircleShape` and friends copy the
//!     `b2Circle`/`b2Capsule`/`b2Polygon` they are given
//!     (`src/shape.c:163-192`), so the caller's value is free afterwards.
//!   * **Event arrays are borrowed and short-lived.** Every `*Events` function
//!     returns a slice into memory the *world* owns. It is valid until the next
//!     `worldStep` of that world or until that world is destroyed, and a
//!     destroy inside the loop makes individual entries name handles that are
//!     already stale, which is why upstream documents the shape ids in an
//!     end-touch event as possibly destroyed
//!     (`include/box2d/types.h:1015-1016`). `bodyMoveEvents` and friends
//!     document this per function and return `[]const T`, never a copy.
//!   * **Destroying a world destroys its bodies, shapes and joints.** There is
//!     no order to respect and nothing to release afterwards: `b2DestroyWorld`
//!     frees every pool the world owns (`src/world.c:263`). After it, every id
//!     that world handed out fails its `*IsValid` check.
//!   * **A destroyed handle is never reused as the same handle.** Freeing a
//!     body or shape bumps that slot's generation (`src/body.c:297`,
//!     `src/shape.c:123`) and destroying a world bumps the world's
//!     (`src/world.c:354`), so a stale id stays invalid even when the index it
//!     names is handed out again. That is what `*IsValid` is for, and it is the
//!     only safe way to ask about a handle you are not sure of.
//!   * **A query callback is never null, and never may be.** Eight entry points
//!     take one — `dynamicTreeQuery`, `dynamicTreeRayCast`,
//!     `dynamicTreeShapeCast`, `worldOverlapAabb`, `worldOverlapShape`,
//!     `worldCastRay`, `worldCastShape` and `worldCollideMover`. Each is
//!     `?*const` because that is the shape of the C parameter
//!     (`include/box2d/collision.h:697`, `:720`, `:741`;
//!     `include/box2d/box2d.h:54`, `:58`, `:71`, `:80`, `:89`), not because
//!     null carries a meaning. Upstream calls it with no null test at
//!     `src/dynamic_tree.c:1146`, `:1245` and `:1375`, and through its own
//!     wrapper at `src/world.c:2067`, `:2143`, `:2208`, `:2336` and `:2505`,
//!     so a null callback is a call through a null function pointer at the
//!     first leaf or overlapping shape the query reaches, and the process does
//!     not survive it. It is a caller precondition, not a way to ask for the
//!     `TreeStats` counters alone. Two callbacks here are genuinely optional
//!     and are documented where they are declared:
//!     `worldSetFrictionCallback` and `worldSetRestitutionCallback`, where
//!     upstream reads null as "restore the default" (`src/world.c:1913-1919`,
//!     `:1931-1937`).
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//!
//! *Runtime-loaded* is opt-in. The library is not linked; `c` is a dispatch
//! generated from the same translation step's output, and the Box2D entry points
//! are resolved through the platform loader when the caller calls
//!
//! ```zig
//! try box2d.load(.{ .path = "/usr/lib/libbox2d.so.3" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! header declares, a request that cannot be honoured because a different
//! provider already won, or a reentrant call, as errors rather than as a
//! different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! there is no unload and no reset, and the handle and its own copy of the
//! request live to the end of the process. What a provider must be is stated in
//! `runtime/library.zig`.
//!
//! ## Errors
//!
//! This module returns one error set, `CreateError`, and it is deliberately
//! small. It is exactly the ways one of these calls declines — a null handle
//! upstream returns, or the zero-count hull `computeHull` reports — and
//! nothing else:
//!
//!   * `createWorld` reports `WorldLimitReached` for upstream's
//!     `(b2WorldId){ 0 }` return, which `src/world.c:115-118` produces when all
//!     `B2_MAX_WORLDS` slots are in use.
//!   * `createBody`, the four `create*Shape` functions and `createChain` report
//!     `WorldLocked` for the null id they return when the world is locked, which
//!     is the case while a step or a callback is running (`src/body.c:192-195`,
//!     `src/shape.c:172-176`). `createSegmentShape` reports the same error for a
//!     second upstream refusal, a segment at or below the linear slop
//!     (`src/shape.c:219-224`), which this wrapper cannot tell apart from a lock.
//!   * `computeHull` reports `HullNotConvex` for the hull whose `count` is zero,
//!     which `src/hull.c:89-96` returns when the points cannot form one.
//!
//! One set, and each call reaches only its own tags inside it: `createWorld`
//! only `WorldLimitReached`, the body, shape and chain creators only
//! `WorldLocked`, and `computeHull` only `HullNotConvex`. The shared set is the
//! vocabulary this module speaks in, not a claim that one call has three ways
//! to fail.
//!
//! Upstream's *assertions* are not errors and are not wrapped. A bad definition,
//! a NaN coordinate or a stale handle trips a `B2_ASSERT`, which aborts in the
//! library; there is no honest way to turn "you passed something upstream
//! documents as illegal" into a recoverable Zig error without inventing a
//! condition upstream does not have. The `*IsValid` functions are the supported
//! way to ask about a handle, and this module does not wrap them into something
//! that pretends the answer can be anything else.
//!
//! ## Threading
//!
//! A world is not thread-safe and belongs to one thread at a time. Upstream does
//! create no threads (`include/box2d/types.h:120-127`), so `worldStep`'s
//! `worker_count` in a `WorldDef` is the number of threads *the caller* has
//! allocated to it, and the task callbacks the world calls back through must be
//! safe to call from each of those. Different worlds are independent and may be
//! simulated in parallel (`include/box2d/box2d.h:24-26`).

const std = @import("std");

/// The translated Box2D header, i.e. upstream's ABI exactly as published.
///
/// This is the escape hatch for a caller that needs a declaration this facade
/// does not name and for the struct fields themselves. It is the same module the
/// facade calls, on the same library, so importing the facade is all a dependent
/// needs to reach it; it is not published under a name of its own.
///
/// The declarations are for whichever header this build selected, and the whole
/// of it: every `B2_API` entry point in `base.h`, `box2d.h`, `collision.h`,
/// `id.h`, `math_functions.h` and `types.h` is here, whether or not a function
/// below wraps it. A caller that reaches past the facade gets upstream behaviour
/// and inherits every obligation upstream declares.
///
/// In a runtime-loading build this module is a generated dispatch instead of the
/// translation step's own output. It publishes the same namespace: every type and
/// constant is re-exported from the translated header rather than restated, so
/// `WorldId` is the same nominal type either way and nothing here needs a cast.
/// What differs is how a name reaches the library. In the linked configuration it
/// is a direct call; in the runtime-loaded one it is a call through a table that
/// `load` fills, and a call before that fill stops the program with a message
/// naming the function. `runtime_loaded` says which configuration this is, at
/// comptime.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module is
/// never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit fallback
/// of any kind; a request that cannot be honoured is an error, not a different
/// library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then use
/// this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use. A
/// failed attempt publishes nothing and can be retried explicitly, by calling
/// this again: there is no automatic retry, and no implicit second source.
///
/// It keeps the process handle and its own copy of the request to the end of the
/// process. There is no unload and no reset, because the table is process-global
/// state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result, whatever
/// it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly succeeding.
/// `runtime_loaded` is false there, so a consumer that supports both
/// configurations can tell the two apart at comptime instead of meeting this at
/// run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "box2d: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Every way a creation in this module declines.
///
/// One error per way a creation call here declines — a null handle upstream
/// returns, or the zero-count hull `computeHull` reports — and nothing else.
/// This is the one vocabulary every creation call speaks in; each call reaches
/// only the tags its own check can produce. See the module documentation for
/// where each one comes from.
pub const CreateError = error{
    /// All `B2_MAX_WORLDS` world slots are in use. Upstream returns a null
    /// `b2WorldId` rather than failing visibly (`src/world.c:115-118`).
    WorldLimitReached,
    /// The world is locked, which is what a world is while a step or a callback
    /// is running. Upstream returns a null body, shape or chain id
    /// (`src/body.c:192-195`, `src/shape.c:172-176`, `src/shape.c:345-349`).
    /// `createSegmentShape` also returns this for a segment upstream refuses as
    /// degenerate (`src/shape.c:219-224`), which is a second null id the
    /// wrapper cannot distinguish from the locked case.
    WorldLocked,
    /// `computeHull` could not build a convex hull from the points, which it
    /// reports as a hull whose `count` is zero (`src/hull.c:89-96`).
    HullNotConvex,
};

// ---------------------------------------------------------------------------
// Constants read out of the headers
// ---------------------------------------------------------------------------

/// The maximum number of vertices on a convex polygon, `B2_MAX_POLYGON_VERTICES`
/// (`include/box2d/collision.h:24`). Changing it changes `Polygon`'s two vertex
/// arrays and `ShapeProxy`'s point array, so it is a build-time choice upstream
/// makes and this build reports rather than one a caller makes.
pub const max_polygon_vertices: usize = c.B2_MAX_POLYGON_VERTICES;

/// The default collision category bits, `B2_DEFAULT_CATEGORY_BITS`
/// (`include/box2d/types.h:14`): category one.
pub const default_category_bits: u64 = c.B2_DEFAULT_CATEGORY_BITS;

/// The default collision mask bits, `B2_DEFAULT_MASK_BITS`
/// (`include/box2d/types.h:15`): every category.
pub const default_mask_bits: u64 = c.B2_DEFAULT_MASK_BITS;

/// Pi as Box2D spells it, `B2_PI` (`include/box2d/math_functions.h:79`).
///
/// This is upstream's constant, which is deliberately shorter than a `f64` pi:
/// Box2D only ever uses it to build angular frequencies, and a longer literal
/// would make two builds disagree about the last bit of a hertz value.
pub const pi: f32 = c.B2_PI;

/// The seed upstream's own determinism hash starts from, `B2_HASH_INIT`
/// (`include/box2d/base.h:128`).
pub const hash_init: u32 = c.B2_HASH_INIT;

/// `b2Vec2_zero` (`include/box2d/math_functions.h:81`).
pub const vec2_zero: Vec2 = c.b2Vec2_zero;

/// `b2Rot_identity` (`include/box2d/math_functions.h:82`).
pub const rot_identity: Rot = c.b2Rot_identity;

/// `b2Transform_identity` (`include/box2d/math_functions.h:83`).
pub const transform_identity: Transform = c.b2Transform_identity;

// ---------------------------------------------------------------------------
// Handles
// ---------------------------------------------------------------------------

/// A world handle, `b2WorldId` (`include/box2d/id.h:37`).
///
/// Upstream's comment is the whole contract: "World id references a world
/// instance. This should be treated as an opaque handle." The two fields are
/// reachable in Zig, and reaching them is how a caller gets in trouble; treat a
/// `WorldId` as a value to pass back, not a struct to edit. `worldIsValid` is the
/// supported question to ask about one.
pub const WorldId = c.b2WorldId;

/// A body handle, `b2BodyId` (`include/box2d/id.h:44`).
pub const BodyId = c.b2BodyId;

/// A shape handle, `b2ShapeId` (`include/box2d/id.h:52`).
pub const ShapeId = c.b2ShapeId;

/// A chain handle, `b2ChainId` (`include/box2d/id.h:60`).
pub const ChainId = c.b2ChainId;

/// A joint handle, `b2JointId` (`include/box2d/id.h:68`).
pub const JointId = c.b2JointId;

/// `b2_nullWorldId` (`include/box2d/id.h:77`).
pub const null_world_id: WorldId = c.b2_nullWorldId;

/// `b2_nullBodyId` (`include/box2d/id.h:78`).
pub const null_body_id: BodyId = c.b2_nullBodyId;

/// `b2_nullShapeId` (`include/box2d/id.h:79`).
pub const null_shape_id: ShapeId = c.b2_nullShapeId;

/// `b2_nullChainId` (`include/box2d/id.h:80`).
pub const null_chain_id: ChainId = c.b2_nullChainId;

/// `b2_nullJointId` (`include/box2d/id.h:81`).
pub const null_joint_id: JointId = c.b2_nullJointId;

/// Whether any handle is null, `B2_IS_NULL` (`include/box2d/id.h:84`).
///
/// An all-zero handle of any of the five kinds. `createWorld` and friends return
/// exactly this when they decline, which is why `CreateError` exists rather than
/// a null test at every call site.
pub fn isNullId(id: anytype) bool {
    return id.index1 == 0;
}

/// Whether two handles of the same kind are the same handle, `B2_ID_EQUALS`
/// (`include/box2d/id.h:90`).
///
/// Upstream's comment says this does not work for `b2WorldId`, and it does not
/// work here either: a world id's fields are the slot index and the world
/// generation, while a body id's are the body index, the world slot and the body
/// generation. Comparing two body ids field by field is right; comparing two
/// world ids with it is not, and neither is comparing handles of different
/// kinds. `isNullId` is the only kind-agnostic question here.
pub fn idsEqual(a: anytype, b: anytype) bool {
    return a.index1 == b.index1 and a.world0 == b.world0 and a.generation == b.generation;
}

/// `b2StoreWorldId` (`include/box2d/id.h:93`).
pub fn storeWorldId(id: WorldId) u32 {
    return c.b2StoreWorldId(id);
}

/// `b2LoadWorldId` (`include/box2d/id.h:99`).
pub fn loadWorldId(x: u32) WorldId {
    return c.b2LoadWorldId(x);
}

/// `b2StoreBodyId` (`include/box2d/id.h:106`).
pub fn storeBodyId(id: BodyId) u64 {
    return c.b2StoreBodyId(id);
}

/// `b2LoadBodyId` (`include/box2d/id.h:112`).
pub fn loadBodyId(x: u64) BodyId {
    return c.b2LoadBodyId(x);
}

/// `b2StoreShapeId` (`include/box2d/id.h:119`).
pub fn storeShapeId(id: ShapeId) u64 {
    return c.b2StoreShapeId(id);
}

/// `b2LoadShapeId` (`include/box2d/id.h:125`).
pub fn loadShapeId(x: u64) ShapeId {
    return c.b2LoadShapeId(x);
}

/// `b2StoreChainId` (`include/box2d/id.h:132`).
pub fn storeChainId(id: ChainId) u64 {
    return c.b2StoreChainId(id);
}

/// `b2LoadChainId` (`include/box2d/id.h:138`).
pub fn loadChainId(x: u64) ChainId {
    return c.b2LoadChainId(x);
}

/// `b2StoreJointId` (`include/box2d/id.h:145`).
pub fn storeJointId(id: JointId) u64 {
    return c.b2StoreJointId(id);
}

/// `b2LoadJointId` (`include/box2d/id.h:151`).
pub fn loadJointId(x: u64) JointId {
    return c.b2LoadJointId(x);
}

// ---------------------------------------------------------------------------
// Value types, exactly as upstream declares them
// ---------------------------------------------------------------------------

/// `b2Vec2` (`include/box2d/math_functions.h:20`). Two `f32`, so its layout is
/// the platform's scalar width and nothing else.
pub const Vec2 = c.b2Vec2;

/// `b2CosSin` (`include/box2d/math_functions.h:28`).
pub const CosSin = c.b2CosSin;

/// `b2Rot` (`include/box2d/math_functions.h:37`): a cosine and a sine, not an
/// angle. This is what makes rotation arithmetic a complex multiply and what
/// makes Box2D's rotation bit-for-bit reproducible.
pub const Rot = c.b2Rot;

/// `b2Transform` (`include/box2d/math_functions.h:44`).
pub const Transform = c.b2Transform;

/// `b2Mat22` (`include/box2d/math_functions.h:51`), stored as two columns.
pub const Mat22 = c.b2Mat22;

/// `b2AABB` (`include/box2d/math_functions.h:58`).
pub const Aabb = c.b2AABB;

/// `b2Plane` (`include/box2d/math_functions.h:65`).
pub const Plane = c.b2Plane;

/// `b2Version` (`include/box2d/base.h:71`).
pub const Version = c.b2Version;

/// `b2RayCastInput` (`include/box2d/collision.h:27`).
pub const RayCastInput = c.b2RayCastInput;

/// `b2ShapeProxy` (`include/box2d/collision.h:41`).
pub const ShapeProxy = c.b2ShapeProxy;

/// `b2ShapeCastInput` (`include/box2d/collision.h:56`).
pub const ShapeCastInput = c.b2ShapeCastInput;

/// `b2CastOutput` (`include/box2d/collision.h:72`).
pub const CastOutput = c.b2CastOutput;

/// `b2MassData` (`include/box2d/collision.h:91`).
pub const MassData = c.b2MassData;

/// `b2Circle` (`include/box2d/collision.h:104`).
pub const Circle = c.b2Circle;

/// `b2Capsule` (`include/box2d/collision.h:115`).
pub const Capsule = c.b2Capsule;

/// `b2Polygon` (`include/box2d/collision.h:133`).
///
/// Upstream warns against filling this out by hand: the `normals` array and the
/// `centroid` are derived, and a polygon whose fields disagree is not a polygon
/// any of these functions can use. Build one with `makeBox`, `makePolygon`,
/// `makeSquare`, `makeRoundedBox`, `makeOffsetBox` or `transformPolygon`.
pub const Polygon = c.b2Polygon;

/// `b2Segment` (`include/box2d/collision.h:152`): a two-sided line segment.
pub const Segment = c.b2Segment;

/// `b2ChainSegment` (`include/box2d/collision.h:164`): a one-sided segment
/// owned by a chain shape, with the two ghost vertices that make the chain
/// continuous.
pub const ChainSegment = c.b2ChainSegment;

/// `b2Hull` (`include/box2d/collision.h:284`). Only `computeHull` may build one;
/// `makePolygon` asserts if it is handed something else.
pub const Hull = c.b2Hull;

/// `b2SegmentDistanceResult` (`include/box2d/collision.h:322`).
pub const SegmentDistanceResult = c.b2SegmentDistanceResult;

/// `b2SimplexCache` (`include/box2d/collision.h:347`).
pub const SimplexCache = c.b2SimplexCache;

/// `b2DistanceInput` (`include/box2d/collision.h:362`).
pub const DistanceInput = c.b2DistanceInput;

/// `b2DistanceOutput` (`include/box2d/collision.h:381`).
pub const DistanceOutput = c.b2DistanceOutput;

/// `b2SimplexVertex` (`include/box2d/collision.h:392`).
pub const SimplexVertex = c.b2SimplexVertex;

/// `b2Simplex` (`include/box2d/collision.h:403`).
pub const Simplex = c.b2Simplex;

/// `b2ShapeCastPairInput` (`include/box2d/collision.h:416`).
pub const ShapeCastPairInput = c.b2ShapeCastPairInput;

/// `b2Sweep` (`include/box2d/collision.h:440`).
pub const Sweep = c.b2Sweep;

/// `b2TOIInput` (`include/box2d/collision.h:453`).
pub const TOIInput = c.b2TOIInput;

/// `b2TOIState` (`include/box2d/collision.h:463`).
pub const TOIState = c.b2TOIState;

/// `b2TOIOutput` (`include/box2d/collision.h:473`).
pub const TOIOutput = c.b2TOIOutput;

/// `b2ManifoldPoint` (`include/box2d/collision.h:498`).
pub const ManifoldPoint = c.b2ManifoldPoint;

/// `b2Manifold` (`include/box2d/collision.h:538`).
pub const Manifold = c.b2Manifold;

/// `b2DynamicTree` (`include/box2d/collision.h:621`).
///
/// Upstream calls this "private data ... placed here for performance reasons",
/// and that is a real constraint rather than modesty: it holds pointers to
/// upstream's own node pool and its five rebuild scratch arrays. Create one with
/// `dynamicTreeCreate` and destroy it with `dynamicTreeDestroy`; nothing else in
/// the header allocates or frees the memory it points at.
pub const DynamicTree = c.b2DynamicTree;

/// `b2TreeStats` (`include/box2d/collision.h:658`).
pub const TreeStats = c.b2TreeStats;

/// `b2PlaneResult` (`include/box2d/collision.h:783`).
pub const PlaneResult = c.b2PlaneResult;

/// `b2CollisionPlane` (`include/box2d/collision.h:797`).
pub const CollisionPlane = c.b2CollisionPlane;

/// `b2PlaneSolverResult` (`include/box2d/collision.h:814`).
pub const PlaneSolverResult = c.b2PlaneSolverResult;

/// `b2WorldDef` (`include/box2d/types.h:81`).
///
/// The `internalValue` field is upstream's own validity stamp
/// (`include/box2d/types.h:141-142`): `b2DefaultWorldDef` sets it and
/// `B2_CHECK_DEF` asserts on it, which is why a definition must come from
/// `defaultWorldDef` rather than from a zeroed struct.
pub const WorldDef = c.b2WorldDef;

/// `b2BodyType` (`include/box2d/types.h:152`).
pub const BodyType = c.b2BodyType;

/// `b2BodyDef` (`include/box2d/types.h:172`).
pub const BodyDef = c.b2BodyDef;

/// `b2Filter` (`include/box2d/types.h:249`).
pub const Filter = c.b2Filter;

/// `b2QueryFilter` (`include/box2d/types.h:291`).
pub const QueryFilter = c.b2QueryFilter;

/// `b2ShapeType` (`include/box2d/types.h:307`).
pub const ShapeType = c.b2ShapeType;

/// `b2SurfaceMaterial` (`include/box2d/types.h:330`).
pub const SurfaceMaterial = c.b2SurfaceMaterial;

/// `b2ShapeDef` (`include/box2d/types.h:362`).
pub const ShapeDef = c.b2ShapeDef;

/// `b2ChainDef` (`include/box2d/types.h:429`).
///
/// `points` and `materials` are cloned by `createChain`, so they may be
/// temporaries. `count` must be at least four and `material_count` must be one or
/// `count`; both are asserted, not checked.
pub const ChainDef = c.b2ChainDef;

/// `b2Profile` (`include/box2d/types.h:466`): per-stage timings in
/// milliseconds, for this step only.
pub const Profile = c.b2Profile;

/// `b2Counters` (`include/box2d/types.h:493`): sizes of the world's pools.
pub const Counters = c.b2Counters;

/// `b2JointType` (`include/box2d/types.h:514`).
pub const JointType = c.b2JointType;

/// `b2DistanceJointDef` (`include/box2d/types.h:533`).
pub const DistanceJointDef = c.b2DistanceJointDef;

/// `b2MotorJointDef` (`include/box2d/types.h:596`).
pub const MotorJointDef = c.b2MotorJointDef;

/// `b2MouseJointDef` (`include/box2d/types.h:638`).
pub const MouseJointDef = c.b2MouseJointDef;

/// `b2FilterJointDef` (`include/box2d/types.h:675`).
pub const FilterJointDef = c.b2FilterJointDef;

/// `b2PrismaticJointDef` (`include/box2d/types.h:701`).
pub const PrismaticJointDef = c.b2PrismaticJointDef;

/// `b2RevoluteJointDef` (`include/box2d/types.h:778`).
pub const RevoluteJointDef = c.b2RevoluteJointDef;

/// `b2WeldJointDef` (`include/box2d/types.h:850`).
pub const WeldJointDef = c.b2WeldJointDef;

/// `b2WheelJointDef` (`include/box2d/types.h:901`).
pub const WheelJointDef = c.b2WheelJointDef;

/// `b2ExplosionDef` (`include/box2d/types.h:962`).
pub const ExplosionDef = c.b2ExplosionDef;

/// `b2SensorBeginTouchEvent` (`include/box2d/types.h:1004`).
pub const SensorBeginTouchEvent = c.b2SensorBeginTouchEvent;

/// `b2SensorEndTouchEvent` (`include/box2d/types.h:1017`).
///
/// Both shape ids here may already name destroyed shapes: upstream says so at
/// `include/box2d/types.h:1015-1016` and says to confirm with
/// `b2Shape_IsValid`. That is the whole reason the event slices below are
/// borrowed rather than copied into something that looks permanent.
pub const SensorEndTouchEvent = c.b2SensorEndTouchEvent;

/// `b2SensorEvents` (`include/box2d/types.h:1034`).
pub const SensorEvents = c.b2SensorEvents;

/// `b2ContactBeginTouchEvent` (`include/box2d/types.h:1050`).
pub const ContactBeginTouchEvent = c.b2ContactBeginTouchEvent;

/// `b2ContactEndTouchEvent` (`include/box2d/types.h:1067`).
///
/// As for a sensor end event, either shape may already be destroyed.
pub const ContactEndTouchEvent = c.b2ContactEndTouchEvent;

/// `b2ContactHitEvent` (`include/box2d/types.h:1082`).
pub const ContactHitEvent = c.b2ContactHitEvent;

/// `b2ContactEvents` (`include/box2d/types.h:1105`).
pub const ContactEvents = c.b2ContactEvents;

/// `b2BodyMoveEvent` (`include/box2d/types.h:1136`).
pub const BodyMoveEvent = c.b2BodyMoveEvent;

/// `b2BodyEvents` (`include/box2d/types.h:1147`).
pub const BodyEvents = c.b2BodyEvents;

/// `b2ContactData` (`include/box2d/types.h:1159`).
pub const ContactData = c.b2ContactData;

/// `b2DebugDraw` (`include/box2d/types.h:1383`).
///
/// A struct of function pointers the *caller* fills, which Box2D calls back
/// through from `worldDraw`. Upstream says it "should be zero initialized", and
/// `defaultDebugDraw` is how: it sets the drawing bounds and leaves every
/// callback null, so `worldDraw` draws nothing until a callback is installed.
pub const DebugDraw = c.b2DebugDraw;

/// `b2RayResult` (`include/box2d/types.h:67`).
pub const RayResult = c.b2RayResult;

/// `b2HexColor` (`include/box2d/types.h:1230`).
pub const HexColor = c.b2HexColor;

// ---------------------------------------------------------------------------
// Callbacks, aliased rather than restated
// ---------------------------------------------------------------------------

/// `b2AllocFcn` (`include/box2d/base.h:49`).
pub const AllocFcn = c.b2AllocFcn;

/// `b2FreeFcn` (`include/box2d/base.h:53`).
pub const FreeFcn = c.b2FreeFcn;

/// `b2AssertFcn` (`include/box2d/base.h:56`).
pub const AssertFcn = c.b2AssertFcn;

/// `b2TaskCallback` (`include/box2d/types.h:33`).
pub const TaskCallback = c.b2TaskCallback;

/// `b2EnqueueTaskCallback` (`include/box2d/types.h:46`).
pub const EnqueueTaskCallback = c.b2EnqueueTaskCallback;

/// `b2FinishTaskCallback` (`include/box2d/types.h:50`).
pub const FinishTaskCallback = c.b2FinishTaskCallback;

/// `b2FrictionCallback` (`include/box2d/types.h:56`).
///
/// Called from a worker thread during the solve, so it must not touch Box2D or
/// application state (`include/box2d/types.h:53-55`).
pub const FrictionCallback = c.b2FrictionCallback;

/// `b2RestitutionCallback` (`include/box2d/types.h:62`).
pub const RestitutionCallback = c.b2RestitutionCallback;

/// `b2CustomFilterFcn` (`include/box2d/types.h:1180`). Return false to refuse
/// the collision.
pub const CustomFilterFn = c.b2CustomFilterFcn;

/// `b2PreSolveFcn` (`include/box2d/types.h:1195`). Return false to skip the
/// contact this step. Not called for sensors, and called only for shapes with
/// pre-solve events enabled.
pub const PreSolveFn = c.b2PreSolveFcn;

/// `b2OverlapResultFcn` (`include/box2d/types.h:1202`). Return false to stop
/// the query.
pub const OverlapResultFn = c.b2OverlapResultFcn;

/// `b2CastResultFcn` (`include/box2d/types.h:1220`). Return `-1` to ignore the
/// shape, `0` to stop, a fraction to clip the ray there, `1` to continue
/// unclipped.
pub const CastResultFn = c.b2CastResultFcn;

/// `b2PlaneResultFcn` (`include/box2d/types.h:1224`).
pub const PlaneResultFn = c.b2PlaneResultFcn;

/// `b2TreeQueryCallbackFcn` (`include/box2d/collision.h:693`). Return false to
/// stop the query.
pub const TreeQueryCallbackFn = c.b2TreeQueryCallbackFcn;

/// `b2TreeRayCastCallbackFcn` (`include/box2d/collision.h:705`). The returned
/// float clips the ray exactly as `CastResultFn`'s does.
pub const TreeRayCastCallbackFn = c.b2TreeRayCastCallbackFcn;

/// `b2TreeShapeCastCallbackFcn` (`include/box2d/collision.h:728`).
pub const TreeShapeCastCallbackFn = c.b2TreeShapeCastCallbackFcn;

// ---------------------------------------------------------------------------
// Base: version, allocation, timing, hashing
// ---------------------------------------------------------------------------

/// `b2GetVersion` (`include/box2d/base.h:84`).
///
/// The library that got linked, not a constant compiled into a program: in a
/// runtime-loading build this is the provider's own answer.
pub fn getVersion() Version {
    return c.b2GetVersion();
}

/// `b2SetAllocator` (`include/box2d/base.h:60`).
///
/// Upstream says these should be set during application startup. Both are
/// borrowed, not retained: `setAllocator` stores the pair and every later
/// allocation goes through it, so the two functions must stay valid for the life
/// of the process. Passing null restores upstream's own allocator.
pub fn setAllocator(alloc: ?*const AllocFcn, free: ?*const FreeFcn) void {
    c.b2SetAllocator(alloc, free);
}

/// `b2GetByteCount` (`include/box2d/base.h:63`).
///
/// Bytes Box2D has allocated, over the whole process. Useful for a leak check;
/// not a count of anything a caller owns.
pub fn getByteCount() c_int {
    return c.b2GetByteCount();
}

/// `b2SetAssertFcn` (`include/box2d/base.h:67`).
///
/// Upstream wants a non-null callback. The callback runs inside a `B2_ASSERT`
/// and must not return; return zero to skip the debugger break
/// (`include/box2d/base.h:55`).
pub fn setAssertFcn(fcn: ?*const AssertFcn) void {
    c.b2SetAssertFcn(fcn);
}

/// `b2GetTicks` (`include/box2d/base.h:115`). Platform specific, and not
/// comparable with another platform's value.
pub fn getTicks() u64 {
    return c.b2GetTicks();
}

/// `b2GetMilliseconds` (`include/box2d/base.h:118`).
pub fn getMilliseconds(ticks: u64) f32 {
    return c.b2GetMilliseconds(ticks);
}

/// `b2GetMillisecondsAndReset` (`include/box2d/base.h:122`).
///
/// `ticks` is updated to the current tick value, so the same slot can be reused
/// for the next interval.
pub fn getMillisecondsAndReset(ticks: *u64) f32 {
    return c.b2GetMillisecondsAndReset(ticks);
}

/// `b2Yield` (`include/box2d/base.h:125`). For a busy loop that must not starve
/// the rest of the process.
pub fn yield() void {
    c.b2Yield();
}

/// `b2Hash` (`include/box2d/base.h:130`).
///
/// Upstream's djb2, for determinism testing (`include/box2d/base.h:127`). It is
/// a rolling hash: the result of one call is the seed for the next, which is how
/// upstream detects that two runs of the same input produced different bytes.
pub fn hash(seed: u32, data: []const u8) u32 {
    return c.b2Hash(seed, data.ptr, @intCast(data.len));
}

// ---------------------------------------------------------------------------
// Upstream's default definitions
// ---------------------------------------------------------------------------

/// `b2DefaultWorldDef` (`include/box2d/types.h:147`).
///
/// Every definition in this group must come from its `b2Default*` function:
/// each one carries an `internalValue` stamp that upstream's `B2_CHECK_DEF`
/// checks, so a zeroed or hand-written definition trips an assert rather than
/// being rejected with an error.
pub fn defaultWorldDef() WorldDef {
    return c.b2DefaultWorldDef();
}

/// `b2DefaultBodyDef` (`include/box2d/types.h:244`).
pub fn defaultBodyDef() BodyDef {
    return c.b2DefaultBodyDef();
}

/// `b2DefaultFilter` (`include/box2d/types.h:285`).
pub fn defaultFilter() Filter {
    return c.b2DefaultFilter();
}

/// `b2DefaultQueryFilter` (`include/box2d/types.h:303`).
pub fn defaultQueryFilter() QueryFilter {
    return c.b2DefaultQueryFilter();
}

/// `b2DefaultSurfaceMaterial` (`include/box2d/types.h:355`).
pub fn defaultSurfaceMaterial() SurfaceMaterial {
    return c.b2DefaultSurfaceMaterial();
}

/// `b2DefaultShapeDef` (`include/box2d/types.h:412`).
pub fn defaultShapeDef() ShapeDef {
    return c.b2DefaultShapeDef();
}

/// `b2DefaultChainDef` (`include/box2d/types.h:462`).
pub fn defaultChainDef() ChainDef {
    return c.b2DefaultChainDef();
}

/// `b2DefaultDistanceJointDef` (`include/box2d/types.h:590`).
pub fn defaultDistanceJointDef() DistanceJointDef {
    return c.b2DefaultDistanceJointDef();
}

/// `b2DefaultMotorJointDef` (`include/box2d/types.h:631`).
pub fn defaultMotorJointDef() MotorJointDef {
    return c.b2DefaultMotorJointDef();
}

/// `b2DefaultMouseJointDef` (`include/box2d/types.h:670`).
pub fn defaultMouseJointDef() MouseJointDef {
    return c.b2DefaultMouseJointDef();
}

/// `b2DefaultFilterJointDef` (`include/box2d/types.h:692`).
pub fn defaultFilterJointDef() FilterJointDef {
    return c.b2DefaultFilterJointDef();
}

/// `b2DefaultPrismaticJointDef` (`include/box2d/types.h:764`).
pub fn defaultPrismaticJointDef() PrismaticJointDef {
    return c.b2DefaultPrismaticJointDef();
}

/// `b2DefaultRevoluteJointDef` (`include/box2d/types.h:842`).
pub fn defaultRevoluteJointDef() RevoluteJointDef {
    return c.b2DefaultRevoluteJointDef();
}

/// `b2DefaultWeldJointDef` (`include/box2d/types.h:892`).
pub fn defaultWeldJointDef() WeldJointDef {
    return c.b2DefaultWeldJointDef();
}

/// `b2DefaultWheelJointDef` (`include/box2d/types.h:957`).
pub fn defaultWheelJointDef() WheelJointDef {
    return c.b2DefaultWheelJointDef();
}

/// `b2DefaultExplosionDef` (`include/box2d/types.h:984`).
pub fn defaultExplosionDef() ExplosionDef {
    return c.b2DefaultExplosionDef();
}

/// `b2DefaultDebugDraw` (`include/box2d/types.h:1464`).
pub fn defaultDebugDraw() DebugDraw {
    return c.b2DefaultDebugDraw();
}

// ---------------------------------------------------------------------------
// Math
// ---------------------------------------------------------------------------

/// A vector literal, for the `b2Vec2` field a definition asks for.
///
/// This is the struct's own construction and not a call: `Vec2` is two `f32`
/// (`include/box2d/math_functions.h:20`) and this writes them. Upstream's own
/// equivalent spelling is the compound literal `(b2Vec2){ x, y }` that
/// `include/box2d/base.h:34-35` exists to support in C.
pub fn vec2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

/// `b2MakeRot` (`include/box2d/math_functions.h:370`).
///
/// Upstream computes this with its own deterministic trigonometric pair rather
/// than the platform's `sinf`/`cosf`, which is why this forwards to it instead
/// of writing `@sin` and `@cos` here: a rotation built any other way can differ
/// in the last bit, and that difference becomes a different simulation.
pub fn makeRot(radians: f32) Rot {
    return c.b2MakeRot(radians);
}

/// `b2ComputeCosSin` (`include/box2d/math_functions.h:157`).
pub fn computeCosSin(radians: f32) CosSin {
    return c.b2ComputeCosSin(radians);
}

/// `b2Atan2` (`include/box2d/math_functions.h:153`).
pub fn atan2(y: f32, x: f32) f32 {
    return c.b2Atan2(y, x);
}

/// `b2ComputeRotationBetweenUnitVectors` (`include/box2d/math_functions.h:377`).
pub fn computeRotationBetweenUnitVectors(v1: Vec2, v2: Vec2) Rot {
    return c.b2ComputeRotationBetweenUnitVectors(v1, v2);
}

/// `b2Dot` (`include/box2d/math_functions.h:160`).
pub fn dot(a: Vec2, b: Vec2) f32 {
    return c.b2Dot(a, b);
}

/// `b2Cross` (`include/box2d/math_functions.h:166`).
pub fn cross(a: Vec2, b: Vec2) f32 {
    return c.b2Cross(a, b);
}

/// `b2CrossVS` (`include/box2d/math_functions.h:172`).
pub fn crossVS(v: Vec2, s: f32) Vec2 {
    return c.b2CrossVS(v, s);
}

/// `b2CrossSV` (`include/box2d/math_functions.h:178`).
pub fn crossSV(s: f32, v: Vec2) Vec2 {
    return c.b2CrossSV(s, v);
}

/// `b2LeftPerp` (`include/box2d/math_functions.h:184`).
pub fn leftPerp(v: Vec2) Vec2 {
    return c.b2LeftPerp(v);
}

/// `b2RightPerp` (`include/box2d/math_functions.h:190`).
pub fn rightPerp(v: Vec2) Vec2 {
    return c.b2RightPerp(v);
}

/// `b2Add` (`include/box2d/math_functions.h:196`).
pub fn add(a: Vec2, b: Vec2) Vec2 {
    return c.b2Add(a, b);
}

/// `b2Sub` (`include/box2d/math_functions.h:202`).
pub fn sub(a: Vec2, b: Vec2) Vec2 {
    return c.b2Sub(a, b);
}

/// `b2Neg` (`include/box2d/math_functions.h:208`).
pub fn neg(a: Vec2) Vec2 {
    return c.b2Neg(a);
}

/// `b2Lerp` (`include/box2d/math_functions.h:215`).
pub fn lerpVec(a: Vec2, b: Vec2, t: f32) Vec2 {
    return c.b2Lerp(a, b, t);
}

/// `b2Mul` (`include/box2d/math_functions.h:221`).
pub fn mul(a: Vec2, b: Vec2) Vec2 {
    return c.b2Mul(a, b);
}

/// `b2MulSV` (`include/box2d/math_functions.h:227`).
pub fn mulSV(s: f32, v: Vec2) Vec2 {
    return c.b2MulSV(s, v);
}

/// `b2MulAdd` (`include/box2d/math_functions.h:233`).
pub fn mulAdd(a: Vec2, s: f32, b: Vec2) Vec2 {
    return c.b2MulAdd(a, s, b);
}

/// `b2MulSub` (`include/box2d/math_functions.h:239`).
pub fn mulSub(a: Vec2, s: f32, b: Vec2) Vec2 {
    return c.b2MulSub(a, s, b);
}

/// `b2Abs` (`include/box2d/math_functions.h:245`).
pub fn absVec(a: Vec2) Vec2 {
    return c.b2Abs(a);
}

/// `b2Min` (`include/box2d/math_functions.h:254`).
pub fn minVec(a: Vec2, b: Vec2) Vec2 {
    return c.b2Min(a, b);
}

/// `b2Max` (`include/box2d/math_functions.h:263`).
pub fn maxVec(a: Vec2, b: Vec2) Vec2 {
    return c.b2Max(a, b);
}

/// `b2Clamp` (`include/box2d/math_functions.h:272`).
pub fn clampVec(v: Vec2, lower: Vec2, upper: Vec2) Vec2 {
    return c.b2Clamp(v, lower, upper);
}

/// `b2Length` (`include/box2d/math_functions.h:281`).
pub fn length(v: Vec2) f32 {
    return c.b2Length(v);
}

/// `b2LengthSquared` (`include/box2d/math_functions.h:357`).
pub fn lengthSquared(v: Vec2) f32 {
    return c.b2LengthSquared(v);
}

/// `b2Distance` (`include/box2d/math_functions.h:287`).
pub fn distance(a: Vec2, b: Vec2) f32 {
    return c.b2Distance(a, b);
}

/// `b2DistanceSquared` (`include/box2d/math_functions.h:363`).
pub fn distanceSquared(a: Vec2, b: Vec2) f32 {
    return c.b2DistanceSquared(a, b);
}

/// `b2Normalize` (`include/box2d/math_functions.h:296`).
///
/// Returns the zero vector for a zero-length input rather than a NaN, which is
/// what makes it safe to call on a computed direction without a length test
/// first.
pub fn normalize(v: Vec2) Vec2 {
    return c.b2Normalize(v);
}

/// `b2IsNormalized` (`include/box2d/math_functions.h:310`).
pub fn isNormalized(a: Vec2) bool {
    return c.b2IsNormalized(a);
}

/// `b2GetLengthAndNormalize` (`include/box2d/math_functions.h:318`).
///
/// Upstream takes an out-parameter for the length and returns the direction, so
/// one call does both. That pair is what a caller almost always wants, and this
/// returns it as a value; `length` is the original length and `direction` is
/// `v` scaled to unit length, or zero when `v` was zero.
pub fn getLengthAndNormalize(v: Vec2) LengthAndDirection {
    var magnitude: f32 = 0;
    const direction = c.b2GetLengthAndNormalize(&magnitude, v);
    return .{ .length = magnitude, .direction = direction };
}

/// What `getLengthAndNormalize` answers: the original length and the unit
/// direction, from the one out-parameter pair upstream splits.
pub const LengthAndDirection = struct {
    /// The length `v` had before it was scaled.
    length: f32,
    /// `v` scaled to unit length, or `b2Vec2_zero` when `v` was zero.
    direction: Vec2,
};

/// `b2NormalizeRot` (`include/box2d/math_functions.h:332`).
pub fn normalizeRot(q: Rot) Rot {
    return c.b2NormalizeRot(q);
}

/// `b2IntegrateRotation` (`include/box2d/math_functions.h:343`).
pub fn integrateRotation(q: Rot, delta_angle: f32) Rot {
    return c.b2IntegrateRotation(q, delta_angle);
}

/// `b2NLerp` (`include/box2d/math_functions.h:390`).
pub fn nLerp(q1: Rot, q2: Rot, t: f32) Rot {
    return c.b2NLerp(q1, q2, t);
}

/// `b2ComputeAngularVelocity` (`include/box2d/math_functions.h:408`).
pub fn computeAngularVelocity(q1: Rot, q2: Rot, inv_h: f32) f32 {
    return c.b2ComputeAngularVelocity(q1, q2, inv_h);
}

/// `b2Rot_GetAngle` (`include/box2d/math_functions.h:425`). Unwrapped to
/// `[-pi, pi]`.
pub fn rotAngle(q: Rot) f32 {
    return c.b2Rot_GetAngle(q);
}

/// `b2Rot_GetXAxis` (`include/box2d/math_functions.h:431`).
pub fn rotXAxis(q: Rot) Vec2 {
    return c.b2Rot_GetXAxis(q);
}

/// `b2Rot_GetYAxis` (`include/box2d/math_functions.h:438`).
pub fn rotYAxis(q: Rot) Vec2 {
    return c.b2Rot_GetYAxis(q);
}

/// `b2MulRot` (`include/box2d/math_functions.h:445`).
pub fn mulRot(q: Rot, r: Rot) Rot {
    return c.b2MulRot(q, r);
}

/// `b2InvMulRot` (`include/box2d/math_functions.h:458`).
pub fn invMulRot(q: Rot, r: Rot) Rot {
    return c.b2InvMulRot(q, r);
}

/// `b2RelativeAngle` (`include/box2d/math_functions.h:471`).
pub fn relativeAngle(b: Rot, a: Rot) f32 {
    return c.b2RelativeAngle(b, a);
}

/// `b2UnwindAngle` (`include/box2d/math_functions.h:481`).
pub fn unwindAngle(radians: f32) f32 {
    return c.b2UnwindAngle(radians);
}

/// `b2RotateVector` (`include/box2d/math_functions.h:488`).
pub fn rotateVector(q: Rot, v: Vec2) Vec2 {
    return c.b2RotateVector(q, v);
}

/// `b2InvRotateVector` (`include/box2d/math_functions.h:494`).
pub fn invRotateVector(q: Rot, v: Vec2) Vec2 {
    return c.b2InvRotateVector(q, v);
}

/// `b2TransformPoint` (`include/box2d/math_functions.h:500`).
pub fn transformPoint(t: Transform, p: Vec2) Vec2 {
    return c.b2TransformPoint(t, p);
}

/// `b2InvTransformPoint` (`include/box2d/math_functions.h:509`).
pub fn invTransformPoint(t: Transform, p: Vec2) Vec2 {
    return c.b2InvTransformPoint(t, p);
}

/// `b2MulTransforms` (`include/box2d/math_functions.h:521`).
pub fn mulTransforms(a: Transform, b: Transform) Transform {
    return c.b2MulTransforms(a, b);
}

/// `b2InvMulTransforms` (`include/box2d/math_functions.h:532`).
pub fn invMulTransforms(a: Transform, b: Transform) Transform {
    return c.b2InvMulTransforms(a, b);
}

/// `b2MulMV` (`include/box2d/math_functions.h:541`).
pub fn mulMV(a: Mat22, v: Vec2) Vec2 {
    return c.b2MulMV(a, v);
}

/// `b2GetInverse22` (`include/box2d/math_functions.h:551`).
pub fn getInverse22(a: Mat22) Mat22 {
    return c.b2GetInverse22(a);
}

/// `b2Solve22` (`include/box2d/math_functions.h:569`).
pub fn solve22(a: Mat22, b: Vec2) Vec2 {
    return c.b2Solve22(a, b);
}

/// `b2AABB_Contains` (`include/box2d/math_functions.h:582`).
pub fn aabbContains(a: Aabb, b: Aabb) bool {
    return c.b2AABB_Contains(a, b);
}

/// `b2AABB_Center` (`include/box2d/math_functions.h:593`).
pub fn aabbCenter(a: Aabb) Vec2 {
    return c.b2AABB_Center(a);
}

/// `b2AABB_Extents` (`include/box2d/math_functions.h:600`).
pub fn aabbExtents(a: Aabb) Vec2 {
    return c.b2AABB_Extents(a);
}

/// `b2AABB_Union` (`include/box2d/math_functions.h:607`).
pub fn aabbUnion(a: Aabb, b: Aabb) Aabb {
    return c.b2AABB_Union(a, b);
}

/// `b2AABB_Overlaps` (`include/box2d/math_functions.h:618`).
pub fn aabbOverlaps(a: Aabb, b: Aabb) bool {
    return c.b2AABB_Overlaps(a, b);
}

/// `b2MakeAABB` (`include/box2d/math_functions.h:625`).
///
/// The bounding box of `points`, grown by `radius` on every side.
///
/// `points` must not be empty, and that is a precondition this module neither
/// checks nor turns into an error. The native body opens with
/// `B2_ASSERT( count > 0 )` (`include/box2d/math_functions.h:627`), which says
/// the caller's state is valid, and the line after it reads `points[0]`
/// unconditionally. So `count == 0` has no answer to return -- inverted box or
/// otherwise -- and this module adds no second, quieter contract to stand in
/// for one the header does not make. An empty slice is the caller's mistake
/// rather than a value the library can be asked about, and upstream's
/// assertion is where that is said.
///
/// This is the one function on the translated surface declared `B2_INLINE`
/// rather than `B2_API` (`include/box2d/base.h:33` makes that `static inline`
/// in C), so the header emits no symbol for it. The C definition this call
/// resolves to is `build_support/box2d_inline_bridge.c`, which compiles that
/// same header body rather than restating it, so `c.b2MakeAABB` and this
/// function are one ABI reached through one symbol: calling either lands on
/// the same code. Under `-Druntime=true` that symbol is the loaded provider's
/// export rather than the archive's, and nothing else about the call changes.
pub fn makeAabb(points: []const Vec2, radius: f32) Aabb {
    return c.b2MakeAABB(points.ptr, @intCast(points.len), radius);
}

/// `b2PlaneSeparation` (`include/box2d/math_functions.h:643`).
pub fn planeSeparation(plane: Plane, point: Vec2) f32 {
    return c.b2PlaneSeparation(plane, point);
}

/// `b2SpringDamper` (`include/box2d/math_functions.h:653`).
///
/// The new velocity for a one-dimensional mass-spring-damper, to be followed by
/// `position += time_step * new_velocity`. This is the function every joint's
/// spring runs through, which is why it is exposed rather than left inside the
/// solver.
pub fn springDamper(hertz: f32, damping_ratio: f32, position: f32, velocity: f32, time_step: f32) f32 {
    return c.b2SpringDamper(hertz, damping_ratio, position, velocity, time_step);
}

/// `b2MinInt` (`include/box2d/math_functions.h:102`).
pub fn minInt(a: c_int, b: c_int) c_int {
    return c.b2MinInt(a, b);
}

/// `b2MaxInt` (`include/box2d/math_functions.h:108`).
pub fn maxInt(a: c_int, b: c_int) c_int {
    return c.b2MaxInt(a, b);
}

/// `b2AbsInt` (`include/box2d/math_functions.h:114`).
pub fn absInt(a: c_int) c_int {
    return c.b2AbsInt(a);
}

/// `b2ClampInt` (`include/box2d/math_functions.h:120`).
pub fn clampInt(a: c_int, lower: c_int, upper: c_int) c_int {
    return c.b2ClampInt(a, lower, upper);
}

/// `b2MinFloat` (`include/box2d/math_functions.h:126`).
pub fn minFloat(a: f32, b: f32) f32 {
    return c.b2MinFloat(a, b);
}

/// `b2MaxFloat` (`include/box2d/math_functions.h:132`).
pub fn maxFloat(a: f32, b: f32) f32 {
    return c.b2MaxFloat(a, b);
}

/// `b2AbsFloat` (`include/box2d/math_functions.h:138`).
pub fn absFloat(a: f32) f32 {
    return c.b2AbsFloat(a);
}

/// `b2ClampFloat` (`include/box2d/math_functions.h:144`).
pub fn clampFloat(a: f32, lower: f32, upper: f32) f32 {
    return c.b2ClampFloat(a, lower, upper);
}

/// `b2SetLengthUnitsPerMeter` (`include/box2d/math_functions.h:674`).
///
/// Upstream warns this must be called before any other Box2D call and only once:
/// it scales internal tolerances, so a world created before it and stepped after
/// it is tuned for the wrong units. Box2D does no scaling of its own, so every
/// length a caller sends and every length it gets back is in the units set here.
pub fn setLengthUnitsPerMeter(length_units: f32) void {
    c.b2SetLengthUnitsPerMeter(length_units);
}

/// `b2GetLengthUnitsPerMeter` (`include/box2d/math_functions.h:677`).
pub fn getLengthUnitsPerMeter() f32 {
    return c.b2GetLengthUnitsPerMeter();
}

/// `b2IsValidFloat` (`include/box2d/math_functions.h:87`): false for NaN and
/// infinity.
pub fn isValidFloat(a: f32) bool {
    return c.b2IsValidFloat(a);
}

/// `b2IsValidVec2` (`include/box2d/math_functions.h:90`).
pub fn isValidVec2(v: Vec2) bool {
    return c.b2IsValidVec2(v);
}

/// `b2IsValidRotation` (`include/box2d/math_functions.h:93`): the cosine and
/// sine are both finite and the pair is unit length.
pub fn isValidRotation(q: Rot) bool {
    return c.b2IsValidRotation(q);
}

/// `b2IsValidAABB` (`include/box2d/math_functions.h:96`): finite, and the lower
/// bound is not above the upper one.
pub fn isValidAabb(a: Aabb) bool {
    return c.b2IsValidAABB(a);
}

/// `b2IsValidPlane` (`include/box2d/math_functions.h:99`).
pub fn isValidPlane(a: Plane) bool {
    return c.b2IsValidPlane(a);
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// `b2MakePolygon` (`include/box2d/collision.h:184`).
///
/// `hull` must come from `computeHull`: upstream asserts on anything else
/// (`include/box2d/collision.h:182`).
pub fn makePolygon(hull: *const Hull, radius: f32) Polygon {
    return c.b2MakePolygon(hull, radius);
}

/// `b2MakeOffsetPolygon` (`include/box2d/collision.h:188`).
pub fn makeOffsetPolygon(hull: *const Hull, position: Vec2, rotation: Rot) Polygon {
    return c.b2MakeOffsetPolygon(hull, position, rotation);
}

/// `b2MakeOffsetRoundedPolygon` (`include/box2d/collision.h:192`).
pub fn makeOffsetRoundedPolygon(hull: *const Hull, position: Vec2, rotation: Rot, radius: f32) Polygon {
    return c.b2MakeOffsetRoundedPolygon(hull, position, rotation, radius);
}

/// `b2MakeSquare` (`include/box2d/collision.h:196`).
pub fn makeSquare(half_width: f32) Polygon {
    return c.b2MakeSquare(half_width);
}

/// `b2MakeBox` (`include/box2d/collision.h:201`).
pub fn makeBox(half_width: f32, half_height: f32) Polygon {
    return c.b2MakeBox(half_width, half_height);
}

/// `b2MakeRoundedBox` (`include/box2d/collision.h:207`).
pub fn makeRoundedBox(half_width: f32, half_height: f32, radius: f32) Polygon {
    return c.b2MakeRoundedBox(half_width, half_height, radius);
}

/// `b2MakeOffsetBox` (`include/box2d/collision.h:214`).
///
/// A box that is already where it belongs, so a caller does not have to create
/// a body at the origin and move it afterwards, which upstream says nearly
/// doubles the cost of body creation (`include/box2d/types.h:178-179`).
pub fn makeOffsetBox(half_width: f32, half_height: f32, center: Vec2, rotation: Rot) Polygon {
    return c.b2MakeOffsetBox(half_width, half_height, center, rotation);
}

/// `b2MakeOffsetRoundedBox` (`include/box2d/collision.h:222`).
pub fn makeOffsetRoundedBox(
    half_width: f32,
    half_height: f32,
    center: Vec2,
    rotation: Rot,
    radius: f32,
) Polygon {
    return c.b2MakeOffsetRoundedBox(half_width, half_height, center, rotation, radius);
}

/// `b2TransformPolygon` (`include/box2d/collision.h:225`).
pub fn transformPolygon(transform: Transform, polygon: *const Polygon) Polygon {
    return c.b2TransformPolygon(transform, polygon);
}

/// `b2MakeProxy` (`include/box2d/collision.h:432`).
///
/// A deep copy of at most `max_polygon_vertices` points, for the query and shape
/// cast entry points that take a proxy.
pub fn makeProxy(points: []const Vec2, radius: f32) ShapeProxy {
    return c.b2MakeProxy(points.ptr, @intCast(points.len), radius);
}

/// `b2MakeOffsetProxy` (`include/box2d/collision.h:435`).
pub fn makeOffsetProxy(points: []const Vec2, radius: f32, position: Vec2, rotation: Rot) ShapeProxy {
    return c.b2MakeOffsetProxy(points.ptr, @intCast(points.len), radius, position, rotation);
}

/// `b2ComputeHull` (`include/box2d/collision.h:301`).
///
/// Upstream returns a hull whose `count` is zero rather than failing visibly,
/// which is what `HullNotConvex` reports. Fewer than three points or more than
/// `max_polygon_vertices`, and any set that is not convex with distinct points,
/// all land there (`src/hull.c:92-96`).
///
/// `HullNotConvex` is the only tag in `CreateError` this function can reach:
/// `b2ComputeHull` returns a `b2Hull` by value and has no null handle to
/// refuse with, so the wider set is the shared vocabulary and not three ways
/// this one call can fail.
pub fn computeHull(points: []const Vec2) CreateError!Hull {
    const hull = c.b2ComputeHull(points.ptr, @intCast(points.len));
    if (hull.count == 0) return error.HullNotConvex;
    return hull;
}

/// `b2ValidateHull` (`include/box2d/collision.h:307`): whether a hull is one
/// `b2MakePolygon` would accept, for a caller that built one by other means.
pub fn validateHull(hull: *const Hull) bool {
    return c.b2ValidateHull(hull);
}

/// `b2ComputeCircleMass` (`include/box2d/collision.h:228`).
pub fn computeCircleMass(shape: *const Circle, density: f32) MassData {
    return c.b2ComputeCircleMass(shape, density);
}

/// `b2ComputeCapsuleMass` (`include/box2d/collision.h:231`).
pub fn computeCapsuleMass(shape: *const Capsule, density: f32) MassData {
    return c.b2ComputeCapsuleMass(shape, density);
}

/// `b2ComputePolygonMass` (`include/box2d/collision.h:234`).
pub fn computePolygonMass(shape: *const Polygon, density: f32) MassData {
    return c.b2ComputePolygonMass(shape, density);
}

/// `b2ComputeCircleAABB` (`include/box2d/collision.h:237`).
pub fn computeCircleAabb(shape: *const Circle, transform: Transform) Aabb {
    return c.b2ComputeCircleAABB(shape, transform);
}

/// `b2ComputeCapsuleAABB` (`include/box2d/collision.h:240`).
pub fn computeCapsuleAabb(shape: *const Capsule, transform: Transform) Aabb {
    return c.b2ComputeCapsuleAABB(shape, transform);
}

/// `b2ComputePolygonAABB` (`include/box2d/collision.h:243`).
pub fn computePolygonAabb(shape: *const Polygon, transform: Transform) Aabb {
    return c.b2ComputePolygonAABB(shape, transform);
}

/// `b2ComputeSegmentAABB` (`include/box2d/collision.h:246`).
pub fn computeSegmentAabb(shape: *const Segment, transform: Transform) Aabb {
    return c.b2ComputeSegmentAABB(shape, transform);
}

/// `b2PointInCircle` (`include/box2d/collision.h:249`).
pub fn pointInCircle(point: Vec2, shape: *const Circle) bool {
    return c.b2PointInCircle(point, shape);
}

/// `b2PointInCapsule` (`include/box2d/collision.h:252`).
pub fn pointInCapsule(point: Vec2, shape: *const Capsule) bool {
    return c.b2PointInCapsule(point, shape);
}

/// `b2PointInPolygon` (`include/box2d/collision.h:255`).
pub fn pointInPolygon(point: Vec2, shape: *const Polygon) bool {
    return c.b2PointInPolygon(point, shape);
}

/// `b2IsValidRay` (`include/box2d/collision.h:180`): rejects NaN input.
pub fn isValidRay(input: *const RayCastInput) bool {
    return c.b2IsValidRay(input);
}

/// `b2RayCastCircle` (`include/box2d/collision.h:258`).
pub fn rayCastCircle(input: *const RayCastInput, shape: *const Circle) CastOutput {
    return c.b2RayCastCircle(input, shape);
}

/// `b2RayCastCapsule` (`include/box2d/collision.h:261`).
pub fn rayCastCapsule(input: *const RayCastInput, shape: *const Capsule) CastOutput {
    return c.b2RayCastCapsule(input, shape);
}

/// `b2RayCastSegment` (`include/box2d/collision.h:265`).
///
/// `one_sided` matches a chain segment's collision behaviour: only the right
/// side of `p1 -> p2` is solid.
pub fn rayCastSegment(input: *const RayCastInput, shape: *const Segment, one_sided: bool) CastOutput {
    return c.b2RayCastSegment(input, shape, one_sided);
}

/// `b2RayCastPolygon` (`include/box2d/collision.h:268`).
pub fn rayCastPolygon(input: *const RayCastInput, shape: *const Polygon) CastOutput {
    return c.b2RayCastPolygon(input, shape);
}

/// `b2ShapeCastCircle` (`include/box2d/collision.h:271`).
pub fn shapeCastCircle(input: *const ShapeCastInput, shape: *const Circle) CastOutput {
    return c.b2ShapeCastCircle(input, shape);
}

/// `b2ShapeCastCapsule` (`include/box2d/collision.h:274`).
pub fn shapeCastCapsule(input: *const ShapeCastInput, shape: *const Capsule) CastOutput {
    return c.b2ShapeCastCapsule(input, shape);
}

/// `b2ShapeCastSegment` (`include/box2d/collision.h:277`).
pub fn shapeCastSegment(input: *const ShapeCastInput, shape: *const Segment) CastOutput {
    return c.b2ShapeCastSegment(input, shape);
}

/// `b2ShapeCastPolygon` (`include/box2d/collision.h:280`).
pub fn shapeCastPolygon(input: *const ShapeCastInput, shape: *const Polygon) CastOutput {
    return c.b2ShapeCastPolygon(input, shape);
}

/// `b2SegmentDistance` (`include/box2d/collision.h:341`): the closest points
/// between two line segments.
pub fn segmentDistance(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) SegmentDistanceResult {
    return c.b2SegmentDistance(p1, q1, p2, q2);
}

/// `b2ShapeDistance` (`include/box2d/collision.h:412`).
///
/// GJK. `cache` is both input and output: upstream says to zero its `count` on
/// the first call (`include/box2d/collision.h:410`). `simplexes` and
/// `simplex_capacity` are for debugging and may be an empty slice with a zero
/// capacity.
pub fn shapeDistance(
    input: *const DistanceInput,
    cache: *SimplexCache,
    simplexes: []Simplex,
) DistanceOutput {
    return c.b2ShapeDistance(input, cache, simplexes.ptr, @intCast(simplexes.len));
}

/// `b2ShapeCast` (`include/box2d/collision.h:429`): a linear shape cast of B
/// against a fixed A. Initially touching shapes are reported as a miss.
pub fn shapeCast(input: *const ShapeCastPairInput) CastOutput {
    return c.b2ShapeCast(input);
}

/// `b2GetSweepTransform` (`include/box2d/collision.h:450`).
pub fn getSweepTransform(sweep: *const Sweep, time: f32) Transform {
    return c.b2GetSweepTransform(sweep, time);
}

/// `b2TimeOfImpact` (`include/box2d/collision.h:483`).
///
/// An upper bound on the time before two swept shapes penetrate, as a fraction
/// of `input.maxFraction`. Upstream warns it may miss intermediate
/// non-tunnelling collisions and that the answer is only valid for the interval
/// it was given (`include/box2d/collision.h:479-482`).
pub fn timeOfImpact(input: *const TOIInput) TOIOutput {
    return c.b2TimeOfImpact(input);
}

/// `b2CollideCircles` (`include/box2d/collision.h:555`).
pub fn collideCircles(a: *const Circle, xf_a: Transform, b: *const Circle, xf_b: Transform) Manifold {
    return c.b2CollideCircles(a, xf_a, b, xf_b);
}

/// `b2CollideCapsuleAndCircle` (`include/box2d/collision.h:558`).
pub fn collideCapsuleAndCircle(
    a: *const Capsule,
    xf_a: Transform,
    b: *const Circle,
    xf_b: Transform,
) Manifold {
    return c.b2CollideCapsuleAndCircle(a, xf_a, b, xf_b);
}

/// `b2CollideSegmentAndCircle` (`include/box2d/collision.h:562`).
pub fn collideSegmentAndCircle(
    a: *const Segment,
    xf_a: Transform,
    b: *const Circle,
    xf_b: Transform,
) Manifold {
    return c.b2CollideSegmentAndCircle(a, xf_a, b, xf_b);
}

/// `b2CollidePolygonAndCircle` (`include/box2d/collision.h:566`).
pub fn collidePolygonAndCircle(
    a: *const Polygon,
    xf_a: Transform,
    b: *const Circle,
    xf_b: Transform,
) Manifold {
    return c.b2CollidePolygonAndCircle(a, xf_a, b, xf_b);
}

/// `b2CollideCapsules` (`include/box2d/collision.h:570`).
pub fn collideCapsules(a: *const Capsule, xf_a: Transform, b: *const Capsule, xf_b: Transform) Manifold {
    return c.b2CollideCapsules(a, xf_a, b, xf_b);
}

/// `b2CollideSegmentAndCapsule` (`include/box2d/collision.h:573`).
pub fn collideSegmentAndCapsule(
    a: *const Segment,
    xf_a: Transform,
    b: *const Capsule,
    xf_b: Transform,
) Manifold {
    return c.b2CollideSegmentAndCapsule(a, xf_a, b, xf_b);
}

/// `b2CollidePolygonAndCapsule` (`include/box2d/collision.h:577`).
pub fn collidePolygonAndCapsule(
    a: *const Polygon,
    xf_a: Transform,
    b: *const Capsule,
    xf_b: Transform,
) Manifold {
    return c.b2CollidePolygonAndCapsule(a, xf_a, b, xf_b);
}

/// `b2CollidePolygons` (`include/box2d/collision.h:581`).
pub fn collidePolygons(a: *const Polygon, xf_a: Transform, b: *const Polygon, xf_b: Transform) Manifold {
    return c.b2CollidePolygons(a, xf_a, b, xf_b);
}

/// `b2CollideSegmentAndPolygon` (`include/box2d/collision.h:584`).
pub fn collideSegmentAndPolygon(
    a: *const Segment,
    xf_a: Transform,
    b: *const Polygon,
    xf_b: Transform,
) Manifold {
    return c.b2CollideSegmentAndPolygon(a, xf_a, b, xf_b);
}

/// `b2CollideChainSegmentAndCircle` (`include/box2d/collision.h:588`).
pub fn collideChainSegmentAndCircle(
    a: *const ChainSegment,
    xf_a: Transform,
    b: *const Circle,
    xf_b: Transform,
) Manifold {
    return c.b2CollideChainSegmentAndCircle(a, xf_a, b, xf_b);
}

/// `b2CollideChainSegmentAndCapsule` (`include/box2d/collision.h:592`).
///
/// Upstream's fifth argument is the caller's `b2SimplexCache*`, which its GJK
/// solve fills and reads back on the next call for the same pair
/// (`src/manifold.c:1385`). Upstream says a caller should generally
/// zero-initialize that structure for each call
/// (`include/box2d/collision.h:346`), which is what this does: the manifold is
/// the same answer, without the warm start a cache carried across calls would
/// give. `shapeDistance` hands the cache to the caller instead, because there
/// the caller owns the whole sequence.
pub fn collideChainSegmentAndCapsule(
    a: *const ChainSegment,
    xf_a: Transform,
    b: *const Capsule,
    xf_b: Transform,
) Manifold {
    var cache = std.mem.zeroes(SimplexCache);
    return c.b2CollideChainSegmentAndCapsule(a, xf_a, b, xf_b, &cache);
}

/// `b2CollideChainSegmentAndPolygon` (`include/box2d/collision.h:596`).
///
/// The caller-owned `b2SimplexCache*` upstream takes here is zero-initialized
/// for each call, as `include/box2d/collision.h:346` directs and
/// `collideChainSegmentAndCapsule` above explains.
pub fn collideChainSegmentAndPolygon(
    a: *const ChainSegment,
    xf_a: Transform,
    b: *const Polygon,
    xf_b: Transform,
) Manifold {
    var cache = std.mem.zeroes(SimplexCache);
    return c.b2CollideChainSegmentAndPolygon(a, xf_a, b, xf_b, &cache);
}

/// `b2SolvePlanes` (`include/box2d/collision.h:827`).
///
/// Solves for the translation of a character mover that satisfies every plane.
/// `planes` is **mutated**: upstream writes each plane's `push`, so the same
/// buffer is the input and part of the output.
pub fn solvePlanes(target_delta: Vec2, planes: []CollisionPlane) PlaneSolverResult {
    return c.b2SolvePlanes(target_delta, planes.ptr, @intCast(planes.len));
}

/// `b2ClipVector` (`include/box2d/collision.h:831`).
///
/// Clips a velocity against planes whose `push` is non-zero and whose
/// `clipVelocity` is set.
pub fn clipVector(vector: Vec2, planes: []const CollisionPlane) Vec2 {
    return c.b2ClipVector(vector, planes.ptr, @intCast(planes.len));
}

// ---------------------------------------------------------------------------
// Dynamic tree
// ---------------------------------------------------------------------------

/// `b2DynamicTree_Create` (`include/box2d/collision.h:668`).
///
/// Returns the tree **by value**. It owns a node pool that `dynamicTreeDestroy`
/// frees, so a tree must be destroyed exactly once and not copied after use:
/// the copy and the original would both free the same pool.
pub fn dynamicTreeCreate() DynamicTree {
    return c.b2DynamicTree_Create();
}

/// `b2DynamicTree_Destroy` (`include/box2d/collision.h:671`).
///
/// Frees the node pool. Every proxy id this tree handed out is stale afterwards,
/// and the tree itself must not be used again.
pub fn dynamicTreeDestroy(tree: *DynamicTree) void {
    c.b2DynamicTree_Destroy(tree);
}

/// `b2DynamicTree_CreateProxy` (`include/box2d/collision.h:674`).
pub fn dynamicTreeCreateProxy(tree: *DynamicTree, aabb: Aabb, category_bits: u64, user_data: u64) c_int {
    return c.b2DynamicTree_CreateProxy(tree, aabb, category_bits, user_data);
}

/// `b2DynamicTree_DestroyProxy` (`include/box2d/collision.h:677`). Asserts on an
/// invalid id.
pub fn dynamicTreeDestroyProxy(tree: *DynamicTree, proxy_id: c_int) void {
    c.b2DynamicTree_DestroyProxy(tree, proxy_id);
}

/// `b2DynamicTree_MoveProxy` (`include/box2d/collision.h:680`).
pub fn dynamicTreeMoveProxy(tree: *DynamicTree, proxy_id: c_int, aabb: Aabb) void {
    c.b2DynamicTree_MoveProxy(tree, proxy_id, aabb);
}

/// `b2DynamicTree_EnlargeProxy` (`include/box2d/collision.h:683`).
///
/// Grows the proxy's box and its ancestors' as needed. Useful for a fast-moving
/// object that must not be reinserted every step.
pub fn dynamicTreeEnlargeProxy(tree: *DynamicTree, proxy_id: c_int, aabb: Aabb) void {
    c.b2DynamicTree_EnlargeProxy(tree, proxy_id, aabb);
}

/// `b2DynamicTree_SetCategoryBits` (`include/box2d/collision.h:686`). Upstream
/// notes this is expensive: it reinserts the proxy.
pub fn dynamicTreeSetCategoryBits(tree: *DynamicTree, proxy_id: c_int, category_bits: u64) void {
    c.b2DynamicTree_SetCategoryBits(tree, proxy_id, category_bits);
}

/// `b2DynamicTree_GetCategoryBits` (`include/box2d/collision.h:689`).
pub fn dynamicTreeGetCategoryBits(tree: *const DynamicTree, proxy_id: c_int) u64 {
    return c.b2DynamicTree_GetCategoryBits(tree, proxy_id);
}

/// `b2DynamicTree_Query` (`include/box2d/collision.h:697`).
/// `callback` must not be null; see the module documentation.
pub fn dynamicTreeQuery(
    tree: *const DynamicTree,
    aabb: Aabb,
    mask_bits: u64,
    callback: ?*const TreeQueryCallbackFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2DynamicTree_Query(tree, aabb, mask_bits, callback, context);
}

/// `b2DynamicTree_RayCast` (`include/box2d/collision.h:720`).
/// `callback` must not be null; see the module documentation.
///
/// The callback performs the exact cast for the proxy it is handed; the tree only
/// narrows the search. Upstream warns that mask-bit filtering here is
/// approximate and the caller should still filter (`include/box2d/collision.h:712-713`).
pub fn dynamicTreeRayCast(
    tree: *const DynamicTree,
    input: *const RayCastInput,
    mask_bits: u64,
    callback: ?*const TreeRayCastCallbackFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2DynamicTree_RayCast(tree, input, mask_bits, callback, context);
}

/// `b2DynamicTree_ShapeCast` (`include/box2d/collision.h:741`).
/// `callback` must not be null; see the module documentation.
pub fn dynamicTreeShapeCast(
    tree: *const DynamicTree,
    input: *const ShapeCastInput,
    mask_bits: u64,
    callback: ?*const TreeShapeCastCallbackFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2DynamicTree_ShapeCast(tree, input, mask_bits, callback, context);
}

/// `b2DynamicTree_GetHeight` (`include/box2d/collision.h:745`).
pub fn dynamicTreeHeight(tree: *const DynamicTree) c_int {
    return c.b2DynamicTree_GetHeight(tree);
}

/// `b2DynamicTree_GetAreaRatio` (`include/box2d/collision.h:748`).
pub fn dynamicTreeAreaRatio(tree: *const DynamicTree) f32 {
    return c.b2DynamicTree_GetAreaRatio(tree);
}

/// `b2DynamicTree_GetRootBounds` (`include/box2d/collision.h:751`).
pub fn dynamicTreeRootBounds(tree: *const DynamicTree) Aabb {
    return c.b2DynamicTree_GetRootBounds(tree);
}

/// `b2DynamicTree_GetProxyCount` (`include/box2d/collision.h:754`).
pub fn dynamicTreeProxyCount(tree: *const DynamicTree) c_int {
    return c.b2DynamicTree_GetProxyCount(tree);
}

/// `b2DynamicTree_Rebuild` (`include/box2d/collision.h:757`).
///
/// Retains unchanged subtrees and returns the number of boxes sorted.
pub fn dynamicTreeRebuild(tree: *DynamicTree, full_build: bool) c_int {
    return c.b2DynamicTree_Rebuild(tree, full_build);
}

/// `b2DynamicTree_GetByteCount` (`include/box2d/collision.h:760`).
pub fn dynamicTreeByteCount(tree: *const DynamicTree) c_int {
    return c.b2DynamicTree_GetByteCount(tree);
}

/// `b2DynamicTree_GetUserData` (`include/box2d/collision.h:763`).
pub fn dynamicTreeUserData(tree: *const DynamicTree, proxy_id: c_int) u64 {
    return c.b2DynamicTree_GetUserData(tree, proxy_id);
}

/// `b2DynamicTree_GetAABB` (`include/box2d/collision.h:766`).
pub fn dynamicTreeAabb(tree: *const DynamicTree, proxy_id: c_int) Aabb {
    return c.b2DynamicTree_GetAABB(tree, proxy_id);
}

/// `b2DynamicTree_Validate` (`include/box2d/collision.h:769`). For testing.
pub fn dynamicTreeValidate(tree: *const DynamicTree) void {
    c.b2DynamicTree_Validate(tree);
}

/// `b2DynamicTree_ValidateNoEnlarged` (`include/box2d/collision.h:772`). For
/// testing.
pub fn dynamicTreeValidateNoEnlarged(tree: *const DynamicTree) void {
    c.b2DynamicTree_ValidateNoEnlarged(tree);
}

// ---------------------------------------------------------------------------
// World
// ---------------------------------------------------------------------------

/// `b2CreateWorld` (`include/box2d/box2d.h:27`).
///
/// `def` is read during the call and not retained, so it may be a temporary
/// after this returns. Upstream allows 128 worlds (`src/constants.h:27`); a
/// request beyond that is `WorldLimitReached`, which is upstream's null return
/// (`src/world.c:115-118`) and not an allocation failure.
pub fn createWorld(def: *const WorldDef) CreateError!WorldId {
    const id = c.b2CreateWorld(def);
    if (isNullId(id)) return error.WorldLimitReached;
    return id;
}

/// `b2DestroyWorld` (`include/box2d/box2d.h:30`).
///
/// Destroys every body, shape, chain, joint and contact the world owns, in one
/// call, and frees the world's pools (`src/world.c:263`). There is nothing to
/// destroy individually afterwards and nothing to release: the world is the only
/// owner. Every id this world handed out, including the `WorldId` passed in here,
/// fails its `*IsValid` check afterwards.
pub fn destroyWorld(self: WorldId) void {
    c.b2DestroyWorld(self);
}

/// `b2World_IsValid` (`include/box2d/box2d.h:33`).
///
/// The only safe question to ask about a world handle. Every other world
/// entry point resolves the handle through `b2GetWorldFromId`, which *asserts*
/// on a mismatched index or generation (`src/world.c:45-52`), so a stale handle
/// passed to one of them aborts rather than answering.
pub fn worldIsValid(id: WorldId) bool {
    return c.b2World_IsValid(id);
}

/// `b2World_Step` (`include/box2d/box2d.h:39`).
///
/// Advances the simulation by `time_step` seconds, split into `sub_step_count`
/// solver sub-steps. Upstream recommends four sub-steps at 60 Hz
/// (`include/box2d/box2d.h:35-38`).
///
/// This is where events are produced. Read them after the step and before the
/// next one; see `bodyMoveEvents` for the lifetime that gives.
///
/// While this runs the world is locked: `createBody`, the `create*Shape`
/// functions and `createChain` return `WorldLocked` rather than half-applying
/// themselves.
pub fn worldStep(self: WorldId, time_step: f32, sub_step_count: c_int) void {
    c.b2World_Step(self, time_step, sub_step_count);
}

/// `b2World_Draw` (`include/box2d/box2d.h:42`).
///
/// Calls the function pointers in `draw` back, from inside Box2D. `draw` is
/// borrowed for the call and the callback function addresses and the context
/// pointer it carries are retained by the caller, not copied.
pub fn worldDraw(self: WorldId, draw: *DebugDraw) void {
    c.b2World_Draw(self, draw);
}

/// `b2World_GetBodyEvents` (`include/box2d/box2d.h:45`).
///
/// The raw form of `bodyMoveEvents`: a borrowed pointer and a count. Prefer the
/// slice, which is this read through a bounded length.
pub fn worldBodyEvents(self: WorldId) BodyEvents {
    return c.b2World_GetBodyEvents(self);
}

/// The body move events this world buffered during the last step.
///
/// **Borrowed.** The slice points into the world's own array and is valid until
/// this world's next `worldStep` or until it is destroyed. Nothing is copied, and
/// a caller that needs the data to outlive that must copy it itself.
///
/// Upstream populates it only for bodies that moved
/// (`include/box2d/types.h:1126-1135`), so an empty slice is the normal answer
/// for a world in which nothing moved.
pub fn bodyMoveEvents(self: WorldId) []const BodyMoveEvent {
    const events = c.b2World_GetBodyEvents(self);
    return events.moveEvents[0..bounded(events.moveCount)];
}

/// `b2World_GetSensorEvents` (`include/box2d/box2d.h:48`).
pub fn worldSensorEvents(self: WorldId) SensorEvents {
    return c.b2World_GetSensorEvents(self);
}

/// The sensor begin-touch events this world buffered during the last step.
///
/// **Borrowed**, until this world's next `worldStep` or until it is destroyed.
/// See `bodyMoveEvents` for the whole rule.
pub fn sensorBeginEvents(self: WorldId) []const SensorBeginTouchEvent {
    const events = c.b2World_GetSensorEvents(self);
    return events.beginEvents[0..bounded(events.beginCount)];
}

/// The sensor end-touch events this world buffered during the last step.
///
/// **Borrowed**, until this world's next `worldStep` or until it is destroyed.
/// Either shape in an entry may already have been destroyed
/// (`include/box2d/types.h:1015-1016`), so confirm with `shapeIsValid` before
/// calling anything on the ids.
pub fn sensorEndEvents(self: WorldId) []const SensorEndTouchEvent {
    const events = c.b2World_GetSensorEvents(self);
    return events.endEvents[0..bounded(events.endCount)];
}

/// `b2World_GetContactEvents` (`include/box2d/box2d.h:51`).
pub fn worldContactEvents(self: WorldId) ContactEvents {
    return c.b2World_GetContactEvents(self);
}

/// The contact begin-touch events this world buffered during the last step.
///
/// **Borrowed**, until this world's next `worldStep` or until it is destroyed.
/// Each entry carries the initial manifold, recorded before the solver runs, so
/// its impulses are all zero (`include/box2d/types.h:1058-1060`).
pub fn contactBeginEvents(self: WorldId) []const ContactBeginTouchEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.beginEvents[0..bounded(events.beginCount)];
}

/// The contact end-touch events this world buffered during the last step.
///
/// **Borrowed**, until this world's next `worldStep` or until it is destroyed.
/// Either shape may already have been destroyed
/// (`include/box2d/types.h:1070-1074`).
pub fn contactEndEvents(self: WorldId) []const ContactEndTouchEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.endEvents[0..bounded(events.endCount)];
}

/// The contact hit events this world buffered during the last step.
///
/// **Borrowed**, until this world's next `worldStep` or until it is destroyed.
/// A hit needs both shapes to have hit events enabled and the approach speed to
/// exceed the world's hit-event threshold.
pub fn contactHitEvents(self: WorldId) []const ContactHitEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.hitEvents[0..bounded(events.hitCount)];
}

/// Turn an upstream `int` event count into a `usize` without trusting it.
///
/// The count is upstream's own and is never negative, but a slice length is not
/// a place to carry a negative number: clamping here keeps a malformed count from
/// turning into a slice whose end precedes its start.
fn bounded(count: c_int) usize {
    return @intCast(@max(count, 0));
}

/// `b2World_OverlapAABB` (`include/box2d/box2d.h:54`).
/// `fcn` must not be null; see the module documentation.
///
/// Calls `fcn` once per shape whose AABB overlaps `aabb`. The callback and its
/// `context` are borrowed for the call and not retained: the context must stay
/// valid until `fcn` has returned, which is inside this call.
pub fn worldOverlapAabb(
    self: WorldId,
    aabb: Aabb,
    filter: QueryFilter,
    fcn: ?*const OverlapResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_OverlapAABB(self, aabb, filter, fcn, context);
}

/// `b2World_OverlapShape` (`include/box2d/box2d.h:58`).
/// `fcn` must not be null; see the module documentation.
pub fn worldOverlapShape(
    self: WorldId,
    proxy: *const ShapeProxy,
    filter: QueryFilter,
    fcn: ?*const OverlapResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_OverlapShape(self, proxy, filter, fcn, context);
}

/// `b2World_CastRay` (`include/box2d/box2d.h:71`).
/// `fcn` must not be null; see the module documentation.
///
/// `fcn` decides what "found" means: `-1` to ignore a shape and continue, `0` to
/// stop, a fraction to clip the ray there, `1` to continue unclipped
/// (`include/box2d/types.h:1207-1217`). Shapes arrive in any order.
pub fn worldCastRay(
    self: WorldId,
    origin: Vec2,
    translation: Vec2,
    filter: QueryFilter,
    fcn: ?*const CastResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_CastRay(self, origin, translation, filter, fcn, context);
}

/// `b2World_CastRayClosest` (`include/box2d/box2d.h:76`).
///
/// The closest hit, with no callback to write. Upstream notes it ignores initial
/// overlap and allows no custom filtering beyond `filter`. An initial overlap
/// gives a zero fraction and a zero normal with an arbitrary point
/// (`include/box2d/types.h:65`), which is why `hit` is the field to branch on.
pub fn worldCastRayClosest(self: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter) RayResult {
    return c.b2World_CastRayClosest(self, origin, translation, filter);
}

/// `b2World_CastShape` (`include/box2d/box2d.h:80`).
/// `fcn` must not be null; see the module documentation.
pub fn worldCastShape(
    self: WorldId,
    proxy: *const ShapeProxy,
    translation: Vec2,
    filter: QueryFilter,
    fcn: ?*const CastResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_CastShape(self, proxy, translation, filter, fcn, context);
}

/// `b2World_CastMover` (`include/box2d/box2d.h:85`).
///
/// The single-answer form of a capsule character mover cast: the fraction of
/// `translation` the mover may travel. Upstream says this is a special shape
/// cast that slides along other shapes while reducing clipping
/// (`include/box2d/box2d.h:82-84`).
pub fn worldCastMover(self: WorldId, mover: *const Capsule, translation: Vec2, filter: QueryFilter) f32 {
    return c.b2World_CastMover(self, mover, translation, filter);
}

/// `b2World_CollideMover` (`include/box2d/box2d.h:89`).
/// `fcn` must not be null; see the module documentation.
///
/// Gathers the collision planes a mover touches, which the caller assembles into
/// `CollisionPlane`s for `solvePlanes`. Each plane is reported through `fcn`,
/// which returns false to stop gathering.
pub fn worldCollideMover(
    self: WorldId,
    mover: *const Capsule,
    filter: QueryFilter,
    fcn: ?*const PlaneResultFn,
    context: ?*anyopaque,
) void {
    c.b2World_CollideMover(self, mover, filter, fcn, context);
}

/// `b2World_EnableSleeping` (`include/box2d/box2d.h:95`).
pub fn worldEnableSleeping(self: WorldId, flag: bool) void {
    c.b2World_EnableSleeping(self, flag);
}

/// `b2World_IsSleepingEnabled` (`include/box2d/box2d.h:98`).
pub fn worldIsSleepingEnabled(self: WorldId) bool {
    return c.b2World_IsSleepingEnabled(self);
}

/// `b2World_EnableContinuous` (`include/box2d/box2d.h:104`).
pub fn worldEnableContinuous(self: WorldId, flag: bool) void {
    c.b2World_EnableContinuous(self, flag);
}

/// `b2World_IsContinuousEnabled` (`include/box2d/box2d.h:107`).
pub fn worldIsContinuousEnabled(self: WorldId) bool {
    return c.b2World_IsContinuousEnabled(self);
}

/// `b2World_SetRestitutionThreshold` (`include/box2d/box2d.h:112`). Collisions
/// slower than this do not bounce.
pub fn worldSetRestitutionThreshold(self: WorldId, value: f32) void {
    c.b2World_SetRestitutionThreshold(self, value);
}

/// `b2World_GetRestitutionThreshold` (`include/box2d/box2d.h:115`).
pub fn worldGetRestitutionThreshold(self: WorldId) f32 {
    return c.b2World_GetRestitutionThreshold(self);
}

/// `b2World_SetHitEventThreshold` (`include/box2d/box2d.h:120`).
pub fn worldSetHitEventThreshold(self: WorldId, value: f32) void {
    c.b2World_SetHitEventThreshold(self, value);
}

/// `b2World_GetHitEventThreshold` (`include/box2d/box2d.h:123`).
pub fn worldGetHitEventThreshold(self: WorldId) f32 {
    return c.b2World_GetHitEventThreshold(self);
}

/// `b2World_SetCustomFilterCallback` (`include/box2d/box2d.h:126`).
///
/// The callback and its context are retained, not copied, so both must outlive
/// the world or be cleared before it is destroyed. It runs on worker threads
/// during the step and must not modify the world
/// (`include/box2d/types.h:1173-1178`).
pub fn worldSetCustomFilterCallback(self: WorldId, fcn: ?*const CustomFilterFn, context: ?*anyopaque) void {
    c.b2World_SetCustomFilterCallback(self, fcn, context);
}

/// `b2World_SetPreSolveCallback` (`include/box2d/box2d.h:129`).
///
/// Retained like a custom filter callback, and with the same threading rule.
pub fn worldSetPreSolveCallback(self: WorldId, fcn: ?*const PreSolveFn, context: ?*anyopaque) void {
    c.b2World_SetPreSolveCallback(self, fcn, context);
}

/// `b2World_SetGravity` (`include/box2d/box2d.h:134`). Box2D has no up vector, so
/// gravity is whatever the caller says.
pub fn worldSetGravity(self: WorldId, gravity: Vec2) void {
    c.b2World_SetGravity(self, gravity);
}

/// `b2World_GetGravity` (`include/box2d/box2d.h:137`).
pub fn worldGetGravity(self: WorldId) Vec2 {
    return c.b2World_GetGravity(self);
}

/// `b2World_Explode` (`include/box2d/box2d.h:142`). Applies an impulse per unit
/// length of the facing shape perimeter; `def` is read during the call.
pub fn worldExplode(self: WorldId, explosion_def: *const ExplosionDef) void {
    c.b2World_Explode(self, explosion_def);
}

/// `b2World_SetContactTuning` (`include/box2d/box2d.h:150`).
pub fn worldSetContactTuning(self: WorldId, hertz: f32, damping_ratio: f32, push_speed: f32) void {
    c.b2World_SetContactTuning(self, hertz, damping_ratio, push_speed);
}

/// `b2World_SetMaximumLinearSpeed` (`include/box2d/box2d.h:153`).
pub fn worldSetMaximumLinearSpeed(self: WorldId, maximum_linear_speed: f32) void {
    c.b2World_SetMaximumLinearSpeed(self, maximum_linear_speed);
}

/// `b2World_GetMaximumLinearSpeed` (`include/box2d/box2d.h:156`).
pub fn worldGetMaximumLinearSpeed(self: WorldId) f32 {
    return c.b2World_GetMaximumLinearSpeed(self);
}

/// `b2World_EnableWarmStarting` (`include/box2d/box2d.h:160`).
pub fn worldEnableWarmStarting(self: WorldId, flag: bool) void {
    c.b2World_EnableWarmStarting(self, flag);
}

/// `b2World_IsWarmStartingEnabled` (`include/box2d/box2d.h:163`).
pub fn worldIsWarmStartingEnabled(self: WorldId) bool {
    return c.b2World_IsWarmStartingEnabled(self);
}

/// `b2World_GetAwakeBodyCount` (`include/box2d/box2d.h:166`).
pub fn worldGetAwakeBodyCount(self: WorldId) c_int {
    return c.b2World_GetAwakeBodyCount(self);
}

/// `b2World_GetProfile` (`include/box2d/box2d.h:169`).
///
/// Per-stage timings in milliseconds for the last step. Upstream hides the struct
/// from its documentation (`include/box2d/types.h:464-507`), so read it as a
/// diagnostic and not as a contract.
pub fn worldGetProfile(self: WorldId) Profile {
    return c.b2World_GetProfile(self);
}

/// `b2World_GetCounters` (`include/box2d/box2d.h:172`).
pub fn worldGetCounters(self: WorldId) Counters {
    return c.b2World_GetCounters(self);
}

/// `b2World_SetUserData` (`include/box2d/box2d.h:175`). The pointer is stored,
/// not copied, so whatever it points at must outlive the world.
pub fn worldSetUserData(self: WorldId, user_data: ?*anyopaque) void {
    c.b2World_SetUserData(self, user_data);
}

/// `b2World_GetUserData` (`include/box2d/box2d.h:178`).
pub fn worldGetUserData(self: WorldId) ?*anyopaque {
    return c.b2World_GetUserData(self);
}

/// `b2World_SetFrictionCallback` (`include/box2d/box2d.h:181`). Passing null
/// restores the default `sqrt(frictionA * frictionB)`.
pub fn worldSetFrictionCallback(self: WorldId, callback: ?*const FrictionCallback) void {
    c.b2World_SetFrictionCallback(self, callback);
}

/// `b2World_SetRestitutionCallback` (`include/box2d/box2d.h:184`). Passing null
/// restores the default `max(restitutionA, restitutionB)`.
pub fn worldSetRestitutionCallback(self: WorldId, callback: ?*const RestitutionCallback) void {
    c.b2World_SetRestitutionCallback(self, callback);
}

/// `b2World_DumpMemoryStats` (`include/box2d/box2d.h:187`). Writes
/// `box2d_memory.txt` in the process's working directory.
pub fn worldDumpMemoryStats(self: WorldId) void {
    c.b2World_DumpMemoryStats(self);
}

/// `b2World_RebuildStaticTree` (`include/box2d/box2d.h:190`). For upstream's own
/// testing.
pub fn worldRebuildStaticTree(self: WorldId) void {
    c.b2World_RebuildStaticTree(self);
}

/// `b2World_EnableSpeculative` (`include/box2d/box2d.h:193`). For upstream's own
/// testing.
pub fn worldEnableSpeculative(self: WorldId, flag: bool) void {
    c.b2World_EnableSpeculative(self, flag);
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

/// `b2CreateBody` (`include/box2d/box2d.h:210`).
///
/// `def` is read during the call and not retained. A body is created **without**
/// shapes: it has no mass, no bounding box and no contacts until one is added, and
/// upstream says creating it at the origin and moving it afterwards nearly
/// doubles the cost (`include/box2d/types.h:178-179`), so create it where it
/// belongs.
///
/// `WorldLocked` is the null return for a world locked by a step or a callback
/// (`src/body.c:192-195`).
pub fn createBody(world: WorldId, def: *const BodyDef) CreateError!BodyId {
    const id = c.b2CreateBody(world, def);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2DestroyBody` (`include/box2d/box2d.h:214`).
///
/// Destroys the body, every shape on it, every joint attached to it, and its
/// contacts, in one call. Nothing else refers to those handles afterwards, and
/// the body slot's generation is bumped so the old `BodyId` stays invalid even if
/// the index is reused (`src/body.c:297`).
pub fn destroyBody(self: BodyId) void {
    c.b2DestroyBody(self);
}

/// `b2Body_IsValid` (`include/box2d/box2d.h:217`).
///
/// False for a null id, a freed body, a mismatched generation, and every handle
/// from a world that is gone. Safe to call on any body-shaped value; the other
/// body entry points are not.
pub fn bodyIsValid(id: BodyId) bool {
    return c.b2Body_IsValid(id);
}

/// `b2Body_GetType` (`include/box2d/box2d.h:220`).
pub fn bodyType(self: BodyId) BodyType {
    return c.b2Body_GetType(self);
}

/// `b2Body_SetType` (`include/box2d/box2d.h:224`).
///
/// Changing the type ends every contact the body had, which the next step turns
/// into end-touch events for whatever had contact events enabled.
pub fn bodySetType(self: BodyId, body_type: BodyType) void {
    c.b2Body_SetType(self, body_type);
}

/// `b2Body_SetName` (`include/box2d/box2d.h:227`).
///
/// The name is **copied** into the body's own 32-byte field, so `name` may be a
/// temporary. Upstream keeps at most 31 characters and NUL-terminates
/// (`src/body.c:270-279`), so a longer name is truncated rather than rejected.
///
/// `name` is the `const char *` the header declares, so a string literal and any
/// sentinel-terminated slice both work with no conversion step.
pub fn bodySetName(self: BodyId, name: [*:0]const u8) void {
    c.b2Body_SetName(self, name);
}

/// `b2Body_GetName` (`include/box2d/box2d.h:230`).
///
/// A pointer to the body's **own** storage, which lives as long as the body does
/// and is overwritten by the next `bodySetName`. Upstream default-initialises it
/// to an empty string, so it is never null and always NUL-terminated.
pub fn bodyName(self: BodyId) [:0]const u8 {
    return std.mem.span(c.b2Body_GetName(self));
}

/// `b2Body_SetUserData` (`include/box2d/box2d.h:233`). Stored, not copied.
pub fn bodySetUserData(self: BodyId, user_data: ?*anyopaque) void {
    c.b2Body_SetUserData(self, user_data);
}

/// `b2Body_GetUserData` (`include/box2d/box2d.h:236`).
pub fn bodyGetUserData(self: BodyId) ?*anyopaque {
    return c.b2Body_GetUserData(self);
}

/// `b2Body_GetPosition` (`include/box2d/box2d.h:239`).
pub fn bodyPosition(self: BodyId) Vec2 {
    return c.b2Body_GetPosition(self);
}

/// `b2Body_GetRotation` (`include/box2d/box2d.h:242`).
pub fn bodyRotation(self: BodyId) Rot {
    return c.b2Body_GetRotation(self);
}

/// `b2Body_GetTransform` (`include/box2d/box2d.h:245`).
pub fn bodyTransform(self: BodyId) Transform {
    return c.b2Body_GetTransform(self);
}

/// `b2Body_SetTransform` (`include/box2d/box2d.h:250`).
///
/// Teleports the body. The sweep is not updated, so contacts can be created or
/// destroyed by the move; that is what produces end-touch events.
pub fn bodySetTransform(self: BodyId, position: Vec2, rotation: Rot) void {
    c.b2Body_SetTransform(self, position, rotation);
}

/// `b2Body_GetLocalPoint` (`include/box2d/box2d.h:253`).
pub fn bodyLocalPoint(self: BodyId, world_point: Vec2) Vec2 {
    return c.b2Body_GetLocalPoint(self, world_point);
}

/// `b2Body_GetWorldPoint` (`include/box2d/box2d.h:256`).
pub fn bodyWorldPoint(self: BodyId, local_point: Vec2) Vec2 {
    return c.b2Body_GetWorldPoint(self, local_point);
}

/// `b2Body_GetLocalVector` (`include/box2d/box2d.h:259`).
pub fn bodyLocalVector(self: BodyId, world_vector: Vec2) Vec2 {
    return c.b2Body_GetLocalVector(self, world_vector);
}

/// `b2Body_GetWorldVector` (`include/box2d/box2d.h:262`).
pub fn bodyWorldVector(self: BodyId, local_vector: Vec2) Vec2 {
    return c.b2Body_GetWorldVector(self, local_vector);
}

/// `b2Body_GetLinearVelocity` (`include/box2d/box2d.h:265`).
pub fn bodyLinearVelocity(self: BodyId) Vec2 {
    return c.b2Body_GetLinearVelocity(self);
}

/// `b2Body_GetAngularVelocity` (`include/box2d/box2d.h:268`).
pub fn bodyAngularVelocity(self: BodyId) f32 {
    return c.b2Body_GetAngularVelocity(self);
}

/// `b2Body_SetLinearVelocity` (`include/box2d/box2d.h:271`).
pub fn bodySetLinearVelocity(self: BodyId, linear_velocity: Vec2) void {
    c.b2Body_SetLinearVelocity(self, linear_velocity);
}

/// `b2Body_SetAngularVelocity` (`include/box2d/box2d.h:274`).
pub fn bodySetAngularVelocity(self: BodyId, angular_velocity: f32) void {
    c.b2Body_SetAngularVelocity(self, angular_velocity);
}

/// `b2Body_SetTargetTransform` (`include/box2d/box2d.h:280`).
///
/// Asks the body to reach `target` in `time_step` seconds, interpolating rather
/// than teleporting. Upstream recommends this over `bodySetTransform` for
/// moving a body without artefacts (`include/box2d/box2d.h:277-279`).
pub fn bodySetTargetTransform(self: BodyId, target: Transform, time_step: f32) void {
    c.b2Body_SetTargetTransform(self, target, time_step);
}

/// `b2Body_GetLocalPointVelocity` (`include/box2d/box2d.h:283`).
pub fn bodyLocalPointVelocity(self: BodyId, local_point: Vec2) Vec2 {
    return c.b2Body_GetLocalPointVelocity(self, local_point);
}

/// `b2Body_GetWorldPointVelocity` (`include/box2d/box2d.h:286`).
pub fn bodyWorldPointVelocity(self: BodyId, world_point: Vec2) Vec2 {
    return c.b2Body_GetWorldPointVelocity(self, world_point);
}

/// `b2Body_ApplyForce` (`include/box2d/box2d.h:295`).
///
/// One call per step: a force is not a state, so a caller that wants a
/// continuous push applies it again after every `worldStep`. `point` is in world
/// coordinates, and `wake` decides whether a sleeping body is woken for it.
pub fn bodyApplyForce(self: BodyId, force: Vec2, point: Vec2, wake: bool) void {
    c.b2Body_ApplyForce(self, force, point, wake);
}

/// `b2Body_ApplyForceToCenter` (`include/box2d/box2d.h:302`).
pub fn bodyApplyForceToCenter(self: BodyId, force: Vec2, wake: bool) void {
    c.b2Body_ApplyForceToCenter(self, force, wake);
}

/// `b2Body_ApplyTorque` (`include/box2d/box2d.h:309`).
pub fn bodyApplyTorque(self: BodyId, torque: f32, wake: bool) void {
    c.b2Body_ApplyTorque(self, torque, wake);
}

/// `b2Body_ApplyLinearImpulse` (`include/box2d/box2d.h:321`).
///
/// Unlike a force, an impulse is applied once and changes the velocity
/// immediately.
pub fn bodyApplyLinearImpulse(self: BodyId, impulse: Vec2, point: Vec2, wake: bool) void {
    c.b2Body_ApplyLinearImpulse(self, impulse, point, wake);
}

/// `b2Body_ApplyLinearImpulseToCenter` (`include/box2d/box2d.h:330`).
pub fn bodyApplyLinearImpulseToCenter(self: BodyId, impulse: Vec2, wake: bool) void {
    c.b2Body_ApplyLinearImpulseToCenter(self, impulse, wake);
}

/// `b2Body_ApplyAngularImpulse` (`include/box2d/box2d.h:339`).
pub fn bodyApplyAngularImpulse(self: BodyId, impulse: f32, wake: bool) void {
    c.b2Body_ApplyAngularImpulse(self, impulse, wake);
}

/// `b2Body_GetMass` (`include/box2d/box2d.h:342`). Zero for a static or
/// kinematic body and for a dynamic body with no shapes.
pub fn bodyMass(self: BodyId) f32 {
    return c.b2Body_GetMass(self);
}

/// `b2Body_GetRotationalInertia` (`include/box2d/box2d.h:345`).
pub fn bodyRotationalInertia(self: BodyId) f32 {
    return c.b2Body_GetRotationalInertia(self);
}

/// `b2Body_GetLocalCenterOfMass` (`include/box2d/box2d.h:348`).
pub fn bodyLocalCenterOfMass(self: BodyId) Vec2 {
    return c.b2Body_GetLocalCenterOfMass(self);
}

/// `b2Body_GetWorldCenterOfMass` (`include/box2d/box2d.h:351`).
pub fn bodyWorldCenterOfMass(self: BodyId) Vec2 {
    return c.b2Body_GetWorldCenterOfMass(self);
}

/// `b2Body_SetMassData` (`include/box2d/box2d.h:356`).
///
/// Overrides what the shapes imply. It is a snapshot: adding or destroying a shape
/// afterwards recomputes the mass from the shapes and discards this.
pub fn bodySetMassData(self: BodyId, mass_data: MassData) void {
    c.b2Body_SetMassData(self, mass_data);
}

/// `b2Body_GetMassData` (`include/box2d/box2d.h:359`).
pub fn bodyMassData(self: BodyId) MassData {
    return c.b2Body_GetMassData(self);
}

/// `b2Body_ApplyMassFromShapes` (`include/box2d/box2d.h:367`).
///
/// Discards a `bodySetMassData` override and recomputes from the shapes.
pub fn bodyApplyMassFromShapes(self: BodyId) void {
    c.b2Body_ApplyMassFromShapes(self);
}

/// `b2Body_SetLinearDamping` (`include/box2d/box2d.h:370`).
pub fn bodySetLinearDamping(self: BodyId, linear_damping: f32) void {
    c.b2Body_SetLinearDamping(self, linear_damping);
}

/// `b2Body_GetLinearDamping` (`include/box2d/box2d.h:373`).
pub fn bodyGetLinearDamping(self: BodyId) f32 {
    return c.b2Body_GetLinearDamping(self);
}

/// `b2Body_SetAngularDamping` (`include/box2d/box2d.h:376`).
pub fn bodySetAngularDamping(self: BodyId, angular_damping: f32) void {
    c.b2Body_SetAngularDamping(self, angular_damping);
}

/// `b2Body_GetAngularDamping` (`include/box2d/box2d.h:379`).
pub fn bodyGetAngularDamping(self: BodyId) f32 {
    return c.b2Body_GetAngularDamping(self);
}

/// `b2Body_SetGravityScale` (`include/box2d/box2d.h:383`). Non-dimensional, so
/// zero cancels gravity for this body.
pub fn bodySetGravityScale(self: BodyId, gravity_scale: f32) void {
    c.b2Body_SetGravityScale(self, gravity_scale);
}

/// `b2Body_GetGravityScale` (`include/box2d/box2d.h:386`).
pub fn bodyGetGravityScale(self: BodyId) f32 {
    return c.b2Body_GetGravityScale(self);
}

/// `b2Body_IsAwake` (`include/box2d/box2d.h:389`).
pub fn bodyIsAwake(self: BodyId) bool {
    return c.b2Body_IsAwake(self);
}

/// `b2Body_SetAwake` (`include/box2d/box2d.h:394`).
pub fn bodySetAwake(self: BodyId, awake: bool) void {
    c.b2Body_SetAwake(self, awake);
}

/// `b2Body_EnableSleep` (`include/box2d/box2d.h:397`).
pub fn bodyEnableSleep(self: BodyId, enable_sleep: bool) void {
    c.b2Body_EnableSleep(self, enable_sleep);
}

/// `b2Body_IsSleepEnabled` (`include/box2d/box2d.h:400`).
pub fn bodyIsSleepEnabled(self: BodyId) bool {
    return c.b2Body_IsSleepEnabled(self);
}

/// `b2Body_SetSleepThreshold` (`include/box2d/box2d.h:403`). The speed below
/// which a body may fall asleep.
pub fn bodySetSleepThreshold(self: BodyId, sleep_threshold: f32) void {
    c.b2Body_SetSleepThreshold(self, sleep_threshold);
}

/// `b2Body_GetSleepThreshold` (`include/box2d/box2d.h:406`).
pub fn bodyGetSleepThreshold(self: BodyId) f32 {
    return c.b2Body_GetSleepThreshold(self);
}

/// `b2Body_IsEnabled` (`include/box2d/box2d.h:409`).
pub fn bodyIsEnabled(self: BodyId) bool {
    return c.b2Body_IsEnabled(self);
}

/// `b2Body_Disable` (`include/box2d/box2d.h:412`). A disabled body neither moves
/// nor collides.
pub fn bodyDisable(self: BodyId) void {
    c.b2Body_Disable(self);
}

/// `b2Body_Enable` (`include/box2d/box2d.h:415`).
pub fn bodyEnable(self: BodyId) void {
    c.b2Body_Enable(self);
}

/// `b2Body_SetFixedRotation` (`include/box2d/box2d.h:418`).
pub fn bodySetFixedRotation(self: BodyId, flag: bool) void {
    c.b2Body_SetFixedRotation(self, flag);
}

/// `b2Body_IsFixedRotation` (`include/box2d/box2d.h:421`).
pub fn bodyIsFixedRotation(self: BodyId) bool {
    return c.b2Body_IsFixedRotation(self);
}

/// `b2Body_SetBullet` (`include/box2d/box2d.h:425`).
///
/// Upstream warns bullets are not a general answer to fast dynamic-versus-dynamic
/// collision and can interfere with joint constraints
/// (`include/box2d/types.h:227-228`).
pub fn bodySetBullet(self: BodyId, flag: bool) void {
    c.b2Body_SetBullet(self, flag);
}

/// `b2Body_IsBullet` (`include/box2d/box2d.h:428`).
pub fn bodyIsBullet(self: BodyId) bool {
    return c.b2Body_IsBullet(self);
}

/// `b2Body_EnableContactEvents` (`include/box2d/box2d.h:433`).
pub fn bodyEnableContactEvents(self: BodyId, flag: bool) void {
    c.b2Body_EnableContactEvents(self, flag);
}

/// `b2Body_EnableHitEvents` (`include/box2d/box2d.h:437`).
pub fn bodyEnableHitEvents(self: BodyId, flag: bool) void {
    c.b2Body_EnableHitEvents(self, flag);
}

/// `b2Body_GetWorld` (`include/box2d/box2d.h:440`).
pub fn bodyWorld(self: BodyId) WorldId {
    return c.b2Body_GetWorld(self);
}

/// `b2Body_GetShapeCount` (`include/box2d/box2d.h:443`).
///
/// Size a slice for `bodyShapes` with this rather than with a guess.
pub fn bodyShapeCount(self: BodyId) c_int {
    return c.b2Body_GetShapeCount(self);
}

/// `b2Body_GetShapes` (`include/box2d/box2d.h:447`).
///
/// Writes shape ids into `out` and returns how many it wrote, up to `out.len`.
/// **It truncates silently**: a body with more shapes than `out` has room for
/// returns `out.len`, not an error and not the real count. Upstream's loop stops
/// at `capacity` (`src/body.c:1817`), so comparing the answer with `bodyShapeCount`
/// is the caller's way to notice.
pub fn bodyShapes(self: BodyId, out: []ShapeId) usize {
    return @intCast(c.b2Body_GetShapes(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_GetJointCount` (`include/box2d/box2d.h:450`).
pub fn bodyJointCount(self: BodyId) c_int {
    return c.b2Body_GetJointCount(self);
}

/// `b2Body_GetJoints` (`include/box2d/box2d.h:454`). Truncates like
/// `bodyShapes`.
pub fn bodyJoints(self: BodyId, out: []JointId) usize {
    return @intCast(c.b2Body_GetJoints(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_GetContactCapacity` (`include/box2d/box2d.h:457`).
pub fn bodyContactCapacity(self: BodyId) c_int {
    return c.b2Body_GetContactCapacity(self);
}

/// `b2Body_GetContactData` (`include/box2d/box2d.h:463`). Truncates like
/// `bodyShapes`, and each entry's manifold is live solver state that the next
/// step overwrites.
pub fn bodyContactData(self: BodyId, out: []ContactData) usize {
    return @intCast(c.b2Body_GetContactData(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_ComputeAABB` (`include/box2d/box2d.h:467`).
pub fn bodyComputeAabb(self: BodyId) Aabb {
    return c.b2Body_ComputeAABB(self);
}

/// A ready-made circle shape literal.
///
/// `b2Circle` is a center and a radius (`include/box2d/collision.h:104`), so this
/// is the struct's own construction and not a call, for the same reason `vec2`
/// is.
pub fn circle(center: Vec2, radius: f32) Circle {
    return .{ .center = center, .radius = radius };
}

/// `b2CreateCircleShape` (`include/box2d/box2d.h:481`).
///
/// `circle` is **copied**, not retained (`src/shape.c:163-192`), so it may be a
/// temporary. `def` is read and not retained either. Attaching a shape updates
/// the body's mass when `def.update_body_mass` is set, which is upstream's
/// default.
///
/// `WorldLocked` is upstream's null return for a locked world
/// (`src/shape.c:172-176`).
pub fn createCircleShape(body: BodyId, def: *const ShapeDef, geometry: *const Circle) CreateError!ShapeId {
    const id = c.b2CreateCircleShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2CreateSegmentShape` (`include/box2d/box2d.h:486`).
///
/// Upstream **refuses** a degenerate segment rather than degrading it. When the
/// squared length from `point1` to `point2` is at or below
/// `B2_LINEAR_SLOP * B2_LINEAR_SLOP` (`src/constants.h:23`) it does
/// `B2_ASSERT( false )` and returns `b2_nullShapeId`
/// (`src/shape.c:219-224`): no shape is created, and nothing is quietly turned
/// into a circle instead.
///
/// Which of the two things a caller sees depends on the build, and on one more
/// thing besides `NDEBUG`. `B2_ASSERT` calls `b2InternalAssertFcn` first and
/// reaches `B2_BREAKPOINT` only if that returns non-zero
/// (`include/box2d/base.h:103-109`); `b2InternalAssertFcn` returns whatever the
/// installed handler returns (`src/core.c:63-66`); and the default handler
/// prints and returns 1 (`src/core.c:46-52`). So:
///
///   * `Debug` and `ReleaseSafe`, with the default handler, end in
///     `B2_BREAKPOINT` (`include/box2d/base.h:91-99`) before the null id
///     exists. The process does not return and this error is never reached.
///   * `ReleaseFast` and `ReleaseSmall` compile `B2_ASSERT` out
///     (`include/box2d/base.h:111`), the null id is returned, and this
///     function reports `error.WorldLocked`.
///   * Either mode, with a handler installed through `setAssertFcn`
///     (`src/core.c:56-60`) that returns zero, the trap is skipped and the
///     refusal arrives as `error.WorldLocked`.
///
/// `error.WorldLocked` therefore covers two upstream refusals this wrapper
/// cannot tell apart: a locked world (`src/shape.c:172-176`) and this one.
pub fn createSegmentShape(body: BodyId, def: *const ShapeDef, geometry: *const Segment) CreateError!ShapeId {
    const id = c.b2CreateSegmentShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2CreateCapsuleShape` (`include/box2d/box2d.h:491`).
///
/// This is the one shape constructor that degrades rather than refuses: centres
/// that coincide, at or below `B2_LINEAR_SLOP * B2_LINEAR_SLOP`, become a
/// circle centred on their midpoint (`src/shape.c:201-206`), which is
/// observable through `shapeType`. A segment given coincident points is refused
/// instead; see `createSegmentShape`.
pub fn createCapsuleShape(body: BodyId, def: *const ShapeDef, geometry: *const Capsule) CreateError!ShapeId {
    const id = c.b2CreateCapsuleShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2CreatePolygonShape` (`include/box2d/box2d.h:496`).
pub fn createPolygonShape(body: BodyId, def: *const ShapeDef, geometry: *const Polygon) CreateError!ShapeId {
    const id = c.b2CreatePolygonShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2DestroyShape` (`include/box2d/box2d.h:501`).
///
/// `update_body_mass` recomputes the owning body's mass; pass false to keep the
/// mass as it is. Destroying a shape destroys its contacts and sensor overlaps,
/// and the next step reports end-touch events for them. The shape slot's
/// generation is bumped, so this `ShapeId` stays invalid
/// (`src/shape.c:123`).
pub fn destroyShape(self: ShapeId, update_body_mass: bool) void {
    c.b2DestroyShape(self, update_body_mass);
}

/// `b2Shape_IsValid` (`include/box2d/box2d.h:504`).
pub fn shapeIsValid(id: ShapeId) bool {
    return c.b2Shape_IsValid(id);
}

/// `b2Shape_GetType` (`include/box2d/box2d.h:507`).
pub fn shapeType(self: ShapeId) ShapeType {
    return c.b2Shape_GetType(self);
}

/// `b2Shape_GetBody` (`include/box2d/box2d.h:510`).
pub fn shapeBody(self: ShapeId) BodyId {
    return c.b2Shape_GetBody(self);
}

/// `b2Shape_GetWorld` (`include/box2d/box2d.h:513`).
pub fn shapeWorld(self: ShapeId) WorldId {
    return c.b2Shape_GetWorld(self);
}

/// `b2Shape_IsSensor` (`include/box2d/box2d.h:518`).
pub fn shapeIsSensor(self: ShapeId) bool {
    return c.b2Shape_IsSensor(self);
}

/// `b2Shape_SetUserData` (`include/box2d/box2d.h:521`). Stored, not copied.
pub fn shapeSetUserData(self: ShapeId, user_data: ?*anyopaque) void {
    c.b2Shape_SetUserData(self, user_data);
}

/// `b2Shape_GetUserData` (`include/box2d/box2d.h:525`).
pub fn shapeGetUserData(self: ShapeId) ?*anyopaque {
    return c.b2Shape_GetUserData(self);
}

/// `b2Shape_SetDensity` (`include/box2d/box2d.h:530`). `update_body_mass` has the
/// same meaning as in `destroyShape`.
pub fn shapeSetDensity(self: ShapeId, density: f32, update_body_mass: bool) void {
    c.b2Shape_SetDensity(self, density, update_body_mass);
}

/// `b2Shape_GetDensity` (`include/box2d/box2d.h:533`).
pub fn shapeDensity(self: ShapeId) f32 {
    return c.b2Shape_GetDensity(self);
}

/// `b2Shape_SetFriction` (`include/box2d/box2d.h:537`).
pub fn shapeSetFriction(self: ShapeId, friction: f32) void {
    c.b2Shape_SetFriction(self, friction);
}

/// `b2Shape_GetFriction` (`include/box2d/box2d.h:540`).
pub fn shapeFriction(self: ShapeId) f32 {
    return c.b2Shape_GetFriction(self);
}

/// `b2Shape_SetRestitution` (`include/box2d/box2d.h:544`).
pub fn shapeSetRestitution(self: ShapeId, restitution: f32) void {
    c.b2Shape_SetRestitution(self, restitution);
}

/// `b2Shape_GetRestitution` (`include/box2d/box2d.h:547`).
pub fn shapeRestitution(self: ShapeId) f32 {
    return c.b2Shape_GetRestitution(self);
}

/// `b2Shape_SetMaterial` (`include/box2d/box2d.h:551`). The user material id
/// passed to the mixing callbacks and to query results; upstream does not use it
/// internally (`include/box2d/types.h:345-347`).
pub fn shapeSetMaterial(self: ShapeId, material: c_int) void {
    c.b2Shape_SetMaterial(self, material);
}

/// `b2Shape_GetMaterial` (`include/box2d/box2d.h:554`).
pub fn shapeMaterial(self: ShapeId) c_int {
    return c.b2Shape_GetMaterial(self);
}

/// `b2Shape_SetSurfaceMaterial` (`include/box2d/box2d.h:557`). Sets friction,
/// restitution, rolling resistance and tangent speed together.
pub fn shapeSetSurfaceMaterial(self: ShapeId, surface_material: SurfaceMaterial) void {
    c.b2Shape_SetSurfaceMaterial(self, surface_material);
}

/// `b2Shape_GetSurfaceMaterial` (`include/box2d/box2d.h:560`).
pub fn shapeSurfaceMaterial(self: ShapeId) SurfaceMaterial {
    return c.b2Shape_GetSurfaceMaterial(self);
}

/// `b2Shape_GetFilter` (`include/box2d/box2d.h:563`).
pub fn shapeFilter(self: ShapeId) Filter {
    return c.b2Shape_GetFilter(self);
}

/// `b2Shape_SetFilter` (`include/box2d/box2d.h:569`).
///
/// Changing a filter ends every contact the shape had, which the next step
/// reports as end-touch events.
pub fn shapeSetFilter(self: ShapeId, filter: Filter) void {
    c.b2Shape_SetFilter(self, filter);
}

/// `b2Shape_EnableSensorEvents` (`include/box2d/box2d.h:573`). Applies to
/// sensors and to non-sensors alike, and is false by default even for a sensor.
pub fn shapeEnableSensorEvents(self: ShapeId, flag: bool) void {
    c.b2Shape_EnableSensorEvents(self, flag);
}

/// `b2Shape_AreSensorEventsEnabled` (`include/box2d/box2d.h:576`).
pub fn shapeAreSensorEventsEnabled(self: ShapeId) bool {
    return c.b2Shape_AreSensorEventsEnabled(self);
}

/// `b2Shape_EnableContactEvents` (`include/box2d/box2d.h:581`). Ignored for
/// sensors.
pub fn shapeEnableContactEvents(self: ShapeId, flag: bool) void {
    c.b2Shape_EnableContactEvents(self, flag);
}

/// `b2Shape_AreContactEventsEnabled` (`include/box2d/box2d.h:584`).
pub fn shapeAreContactEventsEnabled(self: ShapeId) bool {
    return c.b2Shape_AreContactEventsEnabled(self);
}

/// `b2Shape_EnablePreSolveEvents` (`include/box2d/box2d.h:589`). Dynamic bodies
/// only, and upstream calls these expensive because of the threading
/// (`include/box2d/types.h:394-396`).
pub fn shapeEnablePreSolveEvents(self: ShapeId, flag: bool) void {
    c.b2Shape_EnablePreSolveEvents(self, flag);
}

/// `b2Shape_ArePreSolveEventsEnabled` (`include/box2d/box2d.h:592`).
pub fn shapeArePreSolveEventsEnabled(self: ShapeId) bool {
    return c.b2Shape_ArePreSolveEventsEnabled(self);
}

/// `b2Shape_EnableHitEvents` (`include/box2d/box2d.h:596`).
pub fn shapeEnableHitEvents(self: ShapeId, flag: bool) void {
    c.b2Shape_EnableHitEvents(self, flag);
}

/// `b2Shape_AreHitEventsEnabled` (`include/box2d/box2d.h:599`).
pub fn shapeAreHitEventsEnabled(self: ShapeId) bool {
    return c.b2Shape_AreHitEventsEnabled(self);
}

/// `b2Shape_TestPoint` (`include/box2d/box2d.h:602`).
pub fn shapeTestPoint(self: ShapeId, point: Vec2) bool {
    return c.b2Shape_TestPoint(self, point);
}

/// `b2Shape_RayCast` (`include/box2d/box2d.h:605`). `input` is read during the
/// call and not retained.
pub fn shapeRayCast(self: ShapeId, input: *const RayCastInput) CastOutput {
    return c.b2Shape_RayCast(self, input);
}

/// `b2Shape_GetCircle` (`include/box2d/box2d.h:608`).
pub fn shapeCircle(self: ShapeId) Circle {
    return c.b2Shape_GetCircle(self);
}

/// `b2Shape_GetSegment` (`include/box2d/box2d.h:611`).
pub fn shapeSegment(self: ShapeId) Segment {
    return c.b2Shape_GetSegment(self);
}

/// `b2Shape_GetChainSegment` (`include/box2d/box2d.h:615`). Only meaningful for a
/// `b2_chainSegmentShape`.
pub fn shapeChainSegment(self: ShapeId) ChainSegment {
    return c.b2Shape_GetChainSegment(self);
}

/// `b2Shape_GetCapsule` (`include/box2d/box2d.h:618`).
pub fn shapeCapsule(self: ShapeId) Capsule {
    return c.b2Shape_GetCapsule(self);
}

/// `b2Shape_GetPolygon` (`include/box2d/box2d.h:621`).
pub fn shapePolygon(self: ShapeId) Polygon {
    return c.b2Shape_GetPolygon(self);
}

/// `b2Shape_SetCircle` (`include/box2d/box2d.h:626`). Moves the shape and resets
/// its contacts; `geometry` is copied.
pub fn shapeSetCircle(self: ShapeId, geometry: *const Circle) void {
    c.b2Shape_SetCircle(self, geometry);
}

/// `b2Shape_SetCapsule` (`include/box2d/box2d.h:631`).
pub fn shapeSetCapsule(self: ShapeId, geometry: *const Capsule) void {
    c.b2Shape_SetCapsule(self, geometry);
}

/// `b2Shape_SetSegment` (`include/box2d/box2d.h:634`).
pub fn shapeSetSegment(self: ShapeId, geometry: *const Segment) void {
    c.b2Shape_SetSegment(self, geometry);
}

/// `b2Shape_SetPolygon` (`include/box2d/box2d.h:639`).
pub fn shapeSetPolygon(self: ShapeId, geometry: *const Polygon) void {
    c.b2Shape_SetPolygon(self, geometry);
}

/// `b2Shape_GetParentChain` (`include/box2d/box2d.h:643`). The null chain id for
/// a shape that is not one of a chain's segments.
pub fn shapeParentChain(self: ShapeId) ChainId {
    return c.b2Shape_GetParentChain(self);
}

/// `b2Shape_GetContactCapacity` (`include/box2d/box2d.h:646`).
pub fn shapeContactCapacity(self: ShapeId) c_int {
    return c.b2Shape_GetContactCapacity(self);
}

/// `b2Shape_GetContactData` (`include/box2d/box2d.h:652`). Truncates like
/// `bodyShapes`.
pub fn shapeContactData(self: ShapeId, out: []ContactData) usize {
    return @intCast(c.b2Shape_GetContactData(self, out.ptr, @intCast(out.len)));
}

/// `b2Shape_GetSensorCapacity` (`include/box2d/box2d.h:658`).
pub fn shapeSensorCapacity(self: ShapeId) c_int {
    return c.b2Shape_GetSensorCapacity(self);
}

/// `b2Shape_GetSensorOverlaps` (`include/box2d/box2d.h:667`). Truncates like
/// `bodyShapes`.
pub fn shapeSensorOverlaps(self: ShapeId, out: []ShapeId) usize {
    return @intCast(c.b2Shape_GetSensorOverlaps(self, out.ptr, @intCast(out.len)));
}

/// `b2Shape_GetAABB` (`include/box2d/box2d.h:670`).
pub fn shapeAabb(self: ShapeId) Aabb {
    return c.b2Shape_GetAABB(self);
}

/// `b2Shape_GetMassData` (`include/box2d/box2d.h:673`).
pub fn shapeMassData(self: ShapeId) MassData {
    return c.b2Shape_GetMassData(self);
}

/// `b2Shape_GetClosestPoint` (`include/box2d/box2d.h:677`).
pub fn shapeClosestPoint(self: ShapeId, target: Vec2) Vec2 {
    return c.b2Shape_GetClosestPoint(self, target);
}

/// `b2CreateChain` (`include/box2d/box2d.h:683`).
///
/// `def.points` and `def.materials` are **cloned**, so both may be temporaries
/// (`include/box2d/types.h:434,440`). The chain's own `ChainId` is separate from
/// the `ShapeId`s of the segment shapes it creates, which `chainSegments` returns.
///
/// Upstream's warning at `include/box2d/types.h:414-425` is the contract: a chain
/// is one-sided, has no mass, wants a static body, needs at least four points
/// wound counter-clockwise, and has no collision on its first and last edge.
pub fn createChain(body: BodyId, def: *const ChainDef) CreateError!ChainId {
    const id = c.b2CreateChain(body, def);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// `b2DestroyChain` (`include/box2d/box2d.h:686`).
///
/// Destroys the chain and every segment shape it created
/// (`include/box2d/types.h:424`), so the segment ids from `chainSegments` are
/// stale afterwards too.
pub fn destroyChain(self: ChainId) void {
    c.b2DestroyChain(self);
}

/// `b2Chain_GetWorld` (`include/box2d/box2d.h:689`).
pub fn chainWorld(self: ChainId) WorldId {
    return c.b2Chain_GetWorld(self);
}

/// `b2Chain_GetSegmentCount` (`include/box2d/box2d.h:692`).
pub fn chainSegmentCount(self: ChainId) c_int {
    return c.b2Chain_GetSegmentCount(self);
}

/// `b2Chain_GetSegments` (`include/box2d/box2d.h:696`). Truncates like
/// `bodyShapes`.
pub fn chainSegments(self: ChainId, out: []ShapeId) usize {
    return @intCast(c.b2Chain_GetSegments(self, out.ptr, @intCast(out.len)));
}

/// `b2Chain_SetFriction` (`include/box2d/box2d.h:700`). Applies to every segment.
pub fn chainSetFriction(self: ChainId, friction: f32) void {
    c.b2Chain_SetFriction(self, friction);
}

/// `b2Chain_GetFriction` (`include/box2d/box2d.h:703`).
pub fn chainFriction(self: ChainId) f32 {
    return c.b2Chain_GetFriction(self);
}

/// `b2Chain_SetRestitution` (`include/box2d/box2d.h:707`).
pub fn chainSetRestitution(self: ChainId, restitution: f32) void {
    c.b2Chain_SetRestitution(self, restitution);
}

/// `b2Chain_GetRestitution` (`include/box2d/box2d.h:710`).
pub fn chainRestitution(self: ChainId) f32 {
    return c.b2Chain_GetRestitution(self);
}

/// `b2Chain_SetMaterial` (`include/box2d/box2d.h:714`).
pub fn chainSetMaterial(self: ChainId, material: c_int) void {
    c.b2Chain_SetMaterial(self, material);
}

/// `b2Chain_GetMaterial` (`include/box2d/box2d.h:717`).
pub fn chainMaterial(self: ChainId) c_int {
    return c.b2Chain_GetMaterial(self);
}

/// `b2Chain_IsValid` (`include/box2d/box2d.h:720`).
pub fn chainIsValid(id: ChainId) bool {
    return c.b2Chain_IsValid(id);
}

// ---------------------------------------------------------------------------
// Joints
//
// Every joint type shares the accessors below; the per-type tuning functions
// follow, one group per joint, and every one of them is reachable through `c`
// even where it is not named here.
// ---------------------------------------------------------------------------

/// `b2DestroyJoint` (`include/box2d/box2d.h:731`). Removing a joint wakes the
/// bodies it joined.
pub fn destroyJoint(self: JointId) void {
    c.b2DestroyJoint(self);
}

/// `b2Joint_IsValid` (`include/box2d/box2d.h:734`).
pub fn jointIsValid(id: JointId) bool {
    return c.b2Joint_IsValid(id);
}

/// `b2Joint_GetType` (`include/box2d/box2d.h:737`).
pub fn jointType(self: JointId) JointType {
    return c.b2Joint_GetType(self);
}

/// `b2Joint_GetBodyA` (`include/box2d/box2d.h:740`).
pub fn jointBodyA(self: JointId) BodyId {
    return c.b2Joint_GetBodyA(self);
}

/// `b2Joint_GetBodyB` (`include/box2d/box2d.h:743`).
pub fn jointBodyB(self: JointId) BodyId {
    return c.b2Joint_GetBodyB(self);
}

/// `b2Joint_GetWorld` (`include/box2d/box2d.h:746`).
pub fn jointWorld(self: JointId) WorldId {
    return c.b2Joint_GetWorld(self);
}

/// `b2Joint_SetLocalAnchorA` (`include/box2d/box2d.h:749`).
pub fn jointSetLocalAnchorA(self: JointId, local_anchor: Vec2) void {
    c.b2Joint_SetLocalAnchorA(self, local_anchor);
}

/// `b2Joint_GetLocalAnchorA` (`include/box2d/box2d.h:752`).
pub fn jointLocalAnchorA(self: JointId) Vec2 {
    return c.b2Joint_GetLocalAnchorA(self);
}

/// `b2Joint_SetLocalAnchorB` (`include/box2d/box2d.h:755`).
pub fn jointSetLocalAnchorB(self: JointId, local_anchor: Vec2) void {
    c.b2Joint_SetLocalAnchorB(self, local_anchor);
}

/// `b2Joint_GetLocalAnchorB` (`include/box2d/box2d.h:758`).
pub fn jointLocalAnchorB(self: JointId) Vec2 {
    return c.b2Joint_GetLocalAnchorB(self);
}

/// `b2Joint_GetReferenceAngle` (`include/box2d/box2d.h:761`).
pub fn jointReferenceAngle(self: JointId) f32 {
    return c.b2Joint_GetReferenceAngle(self);
}

/// `b2Joint_SetReferenceAngle` (`include/box2d/box2d.h:764`).
pub fn jointSetReferenceAngle(self: JointId, angle_in_radians: f32) void {
    c.b2Joint_SetReferenceAngle(self, angle_in_radians);
}

/// `b2Joint_SetLocalAxisA` (`include/box2d/box2d.h:767`).
pub fn jointSetLocalAxisA(self: JointId, local_axis: Vec2) void {
    c.b2Joint_SetLocalAxisA(self, local_axis);
}

/// `b2Joint_GetLocalAxisA` (`include/box2d/box2d.h:770`).
pub fn jointLocalAxisA(self: JointId) Vec2 {
    return c.b2Joint_GetLocalAxisA(self);
}

/// `b2Joint_SetCollideConnected` (`include/box2d/box2d.h:773`).
pub fn jointSetCollideConnected(self: JointId, should_collide: bool) void {
    c.b2Joint_SetCollideConnected(self, should_collide);
}

/// `b2Joint_GetCollideConnected` (`include/box2d/box2d.h:776`).
pub fn jointCollideConnected(self: JointId) bool {
    return c.b2Joint_GetCollideConnected(self);
}

/// `b2Joint_SetUserData` (`include/box2d/box2d.h:779`). Stored, not copied.
pub fn jointSetUserData(self: JointId, user_data: ?*anyopaque) void {
    c.b2Joint_SetUserData(self, user_data);
}

/// `b2Joint_GetUserData` (`include/box2d/box2d.h:782`).
pub fn jointGetUserData(self: JointId) ?*anyopaque {
    return c.b2Joint_GetUserData(self);
}

/// `b2Joint_WakeBodies` (`include/box2d/box2d.h:785`).
pub fn jointWakeBodies(self: JointId) void {
    c.b2Joint_WakeBodies(self);
}

/// `b2Joint_GetConstraintForce` (`include/box2d/box2d.h:788`).
pub fn jointConstraintForce(self: JointId) Vec2 {
    return c.b2Joint_GetConstraintForce(self);
}

/// `b2Joint_GetConstraintTorque` (`include/box2d/box2d.h:791`).
pub fn jointConstraintTorque(self: JointId) f32 {
    return c.b2Joint_GetConstraintTorque(self);
}

/// `b2Joint_GetLinearSeparation` (`include/box2d/box2d.h:794`).
pub fn jointLinearSeparation(self: JointId) f32 {
    return c.b2Joint_GetLinearSeparation(self);
}

/// `b2Joint_GetAngularSeparation` (`include/box2d/box2d.h:797`).
pub fn jointAngularSeparation(self: JointId) f32 {
    return c.b2Joint_GetAngularSeparation(self);
}

/// `b2Joint_GetConstraintTuning` (`include/box2d/box2d.h:800`).
///
/// Upstream fills two `float` out-parameters; a caller almost always wants them
/// together, so they come back as one value here. Read them before stepping: they
/// describe the last solve.
pub fn jointConstraintTuning(self: JointId) ConstraintTuning {
    var hertz: f32 = 0;
    var damping_ratio: f32 = 0;
    c.b2Joint_GetConstraintTuning(self, &hertz, &damping_ratio);
    return .{ .hertz = hertz, .damping_ratio = damping_ratio };
}

/// What `jointConstraintTuning` answers, and what `jointSetConstraintTuning`
/// takes: the constraint's frequency and damping ratio.
pub const ConstraintTuning = struct {
    /// The constraint stiffness in cycles per second.
    hertz: f32,
    /// The constraint's non-dimensional damping ratio.
    damping_ratio: f32,
};

/// `b2Joint_SetConstraintTuning` (`include/box2d/box2d.h:806`).
pub fn jointSetConstraintTuning(self: JointId, hertz: f32, damping_ratio: f32) void {
    c.b2Joint_SetConstraintTuning(self, hertz, damping_ratio);
}

/// `b2CreateDistanceJoint` (`include/box2d/box2d.h:816`). `def` is read and not
/// retained.
pub fn createDistanceJoint(world: WorldId, def: *const DistanceJointDef) JointId {
    return c.b2CreateDistanceJoint(world, def);
}

/// `b2DistanceJoint_SetLength` (`include/box2d/box2d.h:821`).
pub fn distanceJointSetLength(self: JointId, rest_length: f32) void {
    c.b2DistanceJoint_SetLength(self, rest_length);
}

/// `b2DistanceJoint_GetLength` (`include/box2d/box2d.h:824`).
pub fn distanceJointLength(self: JointId) f32 {
    return c.b2DistanceJoint_GetLength(self);
}

/// `b2DistanceJoint_EnableSpring` (`include/box2d/box2d.h:827`).
pub fn distanceJointEnableSpring(self: JointId, enable_spring: bool) void {
    c.b2DistanceJoint_EnableSpring(self, enable_spring);
}

/// `b2DistanceJoint_IsSpringEnabled` (`include/box2d/box2d.h:830`).
pub fn distanceJointIsSpringEnabled(self: JointId) bool {
    return c.b2DistanceJoint_IsSpringEnabled(self);
}

/// `b2DistanceJoint_SetSpringHertz` (`include/box2d/box2d.h:833`).
pub fn distanceJointSetSpringHertz(self: JointId, hertz: f32) void {
    c.b2DistanceJoint_SetSpringHertz(self, hertz);
}

/// `b2DistanceJoint_GetSpringHertz` (`include/box2d/box2d.h:836`).
pub fn distanceJointGetSpringHertz(self: JointId) f32 {
    return c.b2DistanceJoint_GetSpringHertz(self);
}

/// `b2DistanceJoint_SetSpringDampingRatio` (`include/box2d/box2d.h:839`).
pub fn distanceJointSetSpringDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2DistanceJoint_SetSpringDampingRatio(self, damping_ratio);
}

/// `b2DistanceJoint_GetSpringDampingRatio` (`include/box2d/box2d.h:842`).
pub fn distanceJointGetSpringDampingRatio(self: JointId) f32 {
    return c.b2DistanceJoint_GetSpringDampingRatio(self);
}

/// `b2DistanceJoint_EnableLimit` (`include/box2d/box2d.h:846`).
pub fn distanceJointEnableLimit(self: JointId, enable_limit: bool) void {
    c.b2DistanceJoint_EnableLimit(self, enable_limit);
}

/// `b2DistanceJoint_IsLimitEnabled` (`include/box2d/box2d.h:849`).
pub fn distanceJointIsLimitEnabled(self: JointId) bool {
    return c.b2DistanceJoint_IsLimitEnabled(self);
}

/// `b2DistanceJoint_SetLengthRange` (`include/box2d/box2d.h:852`).
pub fn distanceJointSetLengthRange(self: JointId, min_length: f32, max_length: f32) void {
    c.b2DistanceJoint_SetLengthRange(self, min_length, max_length);
}

/// `b2DistanceJoint_GetMinLength` (`include/box2d/box2d.h:855`).
pub fn distanceJointMinLength(self: JointId) f32 {
    return c.b2DistanceJoint_GetMinLength(self);
}

/// `b2DistanceJoint_GetMaxLength` (`include/box2d/box2d.h:858`).
pub fn distanceJointMaxLength(self: JointId) f32 {
    return c.b2DistanceJoint_GetMaxLength(self);
}

/// `b2DistanceJoint_GetCurrentLength` (`include/box2d/box2d.h:861`).
pub fn distanceJointCurrentLength(self: JointId) f32 {
    return c.b2DistanceJoint_GetCurrentLength(self);
}

/// `b2DistanceJoint_EnableMotor` (`include/box2d/box2d.h:864`).
pub fn distanceJointEnableMotor(self: JointId, enable_motor: bool) void {
    c.b2DistanceJoint_EnableMotor(self, enable_motor);
}

/// `b2DistanceJoint_IsMotorEnabled` (`include/box2d/box2d.h:867`).
pub fn distanceJointIsMotorEnabled(self: JointId) bool {
    return c.b2DistanceJoint_IsMotorEnabled(self);
}

/// `b2DistanceJoint_SetMotorSpeed` (`include/box2d/box2d.h:870`).
pub fn distanceJointSetMotorSpeed(self: JointId, motor_speed: f32) void {
    c.b2DistanceJoint_SetMotorSpeed(self, motor_speed);
}

/// `b2DistanceJoint_GetMotorSpeed` (`include/box2d/box2d.h:873`).
pub fn distanceJointMotorSpeed(self: JointId) f32 {
    return c.b2DistanceJoint_GetMotorSpeed(self);
}

/// `b2DistanceJoint_SetMaxMotorForce` (`include/box2d/box2d.h:876`).
pub fn distanceJointSetMaxMotorForce(self: JointId, force: f32) void {
    c.b2DistanceJoint_SetMaxMotorForce(self, force);
}

/// `b2DistanceJoint_GetMaxMotorForce` (`include/box2d/box2d.h:879`).
pub fn distanceJointMaxMotorForce(self: JointId) f32 {
    return c.b2DistanceJoint_GetMaxMotorForce(self);
}

/// `b2DistanceJoint_GetMotorForce` (`include/box2d/box2d.h:882`). The force the
/// last solve actually used, which is at most the maximum above.
pub fn distanceJointMotorForce(self: JointId) f32 {
    return c.b2DistanceJoint_GetMotorForce(self);
}

/// `b2CreateMotorJoint` (`include/box2d/box2d.h:898`).
pub fn createMotorJoint(world: WorldId, def: *const MotorJointDef) JointId {
    return c.b2CreateMotorJoint(world, def);
}

/// `b2MotorJoint_SetLinearOffset` (`include/box2d/box2d.h:901`).
pub fn motorJointSetLinearOffset(self: JointId, linear_offset: Vec2) void {
    c.b2MotorJoint_SetLinearOffset(self, linear_offset);
}

/// `b2MotorJoint_GetLinearOffset` (`include/box2d/box2d.h:904`).
pub fn motorJointLinearOffset(self: JointId) Vec2 {
    return c.b2MotorJoint_GetLinearOffset(self);
}

/// `b2MotorJoint_SetAngularOffset` (`include/box2d/box2d.h:908`).
pub fn motorJointSetAngularOffset(self: JointId, angular_offset: f32) void {
    c.b2MotorJoint_SetAngularOffset(self, angular_offset);
}

/// `b2MotorJoint_GetAngularOffset` (`include/box2d/box2d.h:911`).
pub fn motorJointAngularOffset(self: JointId) f32 {
    return c.b2MotorJoint_GetAngularOffset(self);
}

/// `b2MotorJoint_SetMaxForce` (`include/box2d/box2d.h:914`).
pub fn motorJointSetMaxForce(self: JointId, max_force: f32) void {
    c.b2MotorJoint_SetMaxForce(self, max_force);
}

/// `b2MotorJoint_GetMaxForce` (`include/box2d/box2d.h:917`).
pub fn motorJointMaxForce(self: JointId) f32 {
    return c.b2MotorJoint_GetMaxForce(self);
}

/// `b2MotorJoint_SetMaxTorque` (`include/box2d/box2d.h:920`).
pub fn motorJointSetMaxTorque(self: JointId, max_torque: f32) void {
    c.b2MotorJoint_SetMaxTorque(self, max_torque);
}

/// `b2MotorJoint_GetMaxTorque` (`include/box2d/box2d.h:923`).
pub fn motorJointMaxTorque(self: JointId) f32 {
    return c.b2MotorJoint_GetMaxTorque(self);
}

/// `b2MotorJoint_SetCorrectionFactor` (`include/box2d/box2d.h:926`).
pub fn motorJointSetCorrectionFactor(self: JointId, correction_factor: f32) void {
    c.b2MotorJoint_SetCorrectionFactor(self, correction_factor);
}

/// `b2MotorJoint_GetCorrectionFactor` (`include/box2d/box2d.h:929`).
pub fn motorJointCorrectionFactor(self: JointId) f32 {
    return c.b2MotorJoint_GetCorrectionFactor(self);
}

/// `b2CreateMouseJoint` (`include/box2d/box2d.h:944`).
pub fn createMouseJoint(world: WorldId, def: *const MouseJointDef) JointId {
    return c.b2CreateMouseJoint(world, def);
}

/// `b2MouseJoint_SetTarget` (`include/box2d/box2d.h:947`).
pub fn mouseJointSetTarget(self: JointId, target: Vec2) void {
    c.b2MouseJoint_SetTarget(self, target);
}

/// `b2MouseJoint_GetTarget` (`include/box2d/box2d.h:950`).
pub fn mouseJointTarget(self: JointId) Vec2 {
    return c.b2MouseJoint_GetTarget(self);
}

/// `b2MouseJoint_SetSpringHertz` (`include/box2d/box2d.h:953`).
pub fn mouseJointSetSpringHertz(self: JointId, hertz: f32) void {
    c.b2MouseJoint_SetSpringHertz(self, hertz);
}

/// `b2MouseJoint_GetSpringHertz` (`include/box2d/box2d.h:956`).
pub fn mouseJointGetSpringHertz(self: JointId) f32 {
    return c.b2MouseJoint_GetSpringHertz(self);
}

/// `b2MouseJoint_SetSpringDampingRatio` (`include/box2d/box2d.h:959`).
pub fn mouseJointSetSpringDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2MouseJoint_SetSpringDampingRatio(self, damping_ratio);
}

/// `b2MouseJoint_GetSpringDampingRatio` (`include/box2d/box2d.h:962`).
pub fn mouseJointGetSpringDampingRatio(self: JointId) f32 {
    return c.b2MouseJoint_GetSpringDampingRatio(self);
}

/// `b2MouseJoint_SetMaxForce` (`include/box2d/box2d.h:965`).
pub fn mouseJointSetMaxForce(self: JointId, max_force: f32) void {
    c.b2MouseJoint_SetMaxForce(self, max_force);
}

/// `b2MouseJoint_GetMaxForce` (`include/box2d/box2d.h:968`).
pub fn mouseJointMaxForce(self: JointId) f32 {
    return c.b2MouseJoint_GetMaxForce(self);
}

/// `b2CreateFilterJoint` (`include/box2d/box2d.h:983`).
///
/// A joint whose only job is to carry a collision filter between two bodies: it
/// suppresses contact between them while they are connected.
pub fn createFilterJoint(world: WorldId, def: *const FilterJointDef) JointId {
    return c.b2CreateFilterJoint(world, def);
}

/// `b2CreatePrismaticJoint` (`include/box2d/box2d.h:998`).
pub fn createPrismaticJoint(world: WorldId, def: *const PrismaticJointDef) JointId {
    return c.b2CreatePrismaticJoint(world, def);
}

/// `b2PrismaticJoint_EnableSpring` (`include/box2d/box2d.h:1001`).
pub fn prismaticJointEnableSpring(self: JointId, enable_spring: bool) void {
    c.b2PrismaticJoint_EnableSpring(self, enable_spring);
}

/// `b2PrismaticJoint_IsSpringEnabled` (`include/box2d/box2d.h:1004`).
pub fn prismaticJointIsSpringEnabled(self: JointId) bool {
    return c.b2PrismaticJoint_IsSpringEnabled(self);
}

/// `b2PrismaticJoint_SetSpringHertz` (`include/box2d/box2d.h:1009`).
pub fn prismaticJointSetSpringHertz(self: JointId, hertz: f32) void {
    c.b2PrismaticJoint_SetSpringHertz(self, hertz);
}

/// `b2PrismaticJoint_GetSpringHertz` (`include/box2d/box2d.h:1012`).
pub fn prismaticJointSpringHertz(self: JointId) f32 {
    return c.b2PrismaticJoint_GetSpringHertz(self);
}

/// `b2PrismaticJoint_SetSpringDampingRatio` (`include/box2d/box2d.h:1015`).
pub fn prismaticJointSetSpringDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2PrismaticJoint_SetSpringDampingRatio(self, damping_ratio);
}

/// `b2PrismaticJoint_GetSpringDampingRatio` (`include/box2d/box2d.h:1018`).
pub fn prismaticJointGetSpringDampingRatio(self: JointId) f32 {
    return c.b2PrismaticJoint_GetSpringDampingRatio(self);
}

/// `b2PrismaticJoint_SetTargetTranslation` (`include/box2d/box2d.h:1021`).
pub fn prismaticJointSetTargetTranslation(self: JointId, translation: f32) void {
    c.b2PrismaticJoint_SetTargetTranslation(self, translation);
}

/// `b2PrismaticJoint_GetTargetTranslation` (`include/box2d/box2d.h:1024`).
pub fn prismaticJointTargetTranslation(self: JointId) f32 {
    return c.b2PrismaticJoint_GetTargetTranslation(self);
}

/// `b2PrismaticJoint_EnableLimit` (`include/box2d/box2d.h:1027`).
pub fn prismaticJointEnableLimit(self: JointId, enable_limit: bool) void {
    c.b2PrismaticJoint_EnableLimit(self, enable_limit);
}

/// `b2PrismaticJoint_IsLimitEnabled` (`include/box2d/box2d.h:1030`).
pub fn prismaticJointIsLimitEnabled(self: JointId) bool {
    return c.b2PrismaticJoint_IsLimitEnabled(self);
}

/// `b2PrismaticJoint_GetLowerLimit` (`include/box2d/box2d.h:1033`).
pub fn prismaticJointLowerLimit(self: JointId) f32 {
    return c.b2PrismaticJoint_GetLowerLimit(self);
}

/// `b2PrismaticJoint_GetUpperLimit` (`include/box2d/box2d.h:1036`).
pub fn prismaticJointUpperLimit(self: JointId) f32 {
    return c.b2PrismaticJoint_GetUpperLimit(self);
}

/// `b2PrismaticJoint_SetLimits` (`include/box2d/box2d.h:1039`).
pub fn prismaticJointSetLimits(self: JointId, lower: f32, upper: f32) void {
    c.b2PrismaticJoint_SetLimits(self, lower, upper);
}

/// `b2PrismaticJoint_EnableMotor` (`include/box2d/box2d.h:1042`).
pub fn prismaticJointEnableMotor(self: JointId, enable_motor: bool) void {
    c.b2PrismaticJoint_EnableMotor(self, enable_motor);
}

/// `b2PrismaticJoint_IsMotorEnabled` (`include/box2d/box2d.h:1045`).
pub fn prismaticJointIsMotorEnabled(self: JointId) bool {
    return c.b2PrismaticJoint_IsMotorEnabled(self);
}

/// `b2PrismaticJoint_SetMotorSpeed` (`include/box2d/box2d.h:1048`).
pub fn prismaticJointSetMotorSpeed(self: JointId, motor_speed: f32) void {
    c.b2PrismaticJoint_SetMotorSpeed(self, motor_speed);
}

/// `b2PrismaticJoint_GetMotorSpeed` (`include/box2d/box2d.h:1051`).
pub fn prismaticJointMotorSpeed(self: JointId) f32 {
    return c.b2PrismaticJoint_GetMotorSpeed(self);
}

/// `b2PrismaticJoint_SetMaxMotorForce` (`include/box2d/box2d.h:1054`).
pub fn prismaticJointSetMaxMotorForce(self: JointId, max_motor_force: f32) void {
    c.b2PrismaticJoint_SetMaxMotorForce(self, max_motor_force);
}

/// `b2PrismaticJoint_GetMaxMotorForce` (`include/box2d/box2d.h:1057`).
pub fn prismaticJointMaxMotorForce(self: JointId) f32 {
    return c.b2PrismaticJoint_GetMaxMotorForce(self);
}

/// `b2PrismaticJoint_GetMotorForce` (`include/box2d/box2d.h:1060`).
pub fn prismaticJointMotorForce(self: JointId) f32 {
    return c.b2PrismaticJoint_GetMotorForce(self);
}

/// `b2PrismaticJoint_GetTranslation` (`include/box2d/box2d.h:1063`).
pub fn prismaticJointTranslation(self: JointId) f32 {
    return c.b2PrismaticJoint_GetTranslation(self);
}

/// `b2PrismaticJoint_GetSpeed` (`include/box2d/box2d.h:1066`).
pub fn prismaticJointSpeed(self: JointId) f32 {
    return c.b2PrismaticJoint_GetSpeed(self);
}

/// `b2CreateRevoluteJoint` (`include/box2d/box2d.h:1081`).
pub fn createRevoluteJoint(world: WorldId, def: *const RevoluteJointDef) JointId {
    return c.b2CreateRevoluteJoint(world, def);
}

/// `b2RevoluteJoint_EnableSpring` (`include/box2d/box2d.h:1084`).
pub fn revoluteJointEnableSpring(self: JointId, enable_spring: bool) void {
    c.b2RevoluteJoint_EnableSpring(self, enable_spring);
}

/// `b2RevoluteJoint_IsSpringEnabled` (`include/box2d/box2d.h:1087`).
pub fn revoluteJointIsSpringEnabled(self: JointId) bool {
    return c.b2RevoluteJoint_IsSpringEnabled(self);
}

/// `b2RevoluteJoint_SetSpringHertz` (`include/box2d/box2d.h:1090`).
pub fn revoluteJointSetSpringHertz(self: JointId, hertz: f32) void {
    c.b2RevoluteJoint_SetSpringHertz(self, hertz);
}

/// `b2RevoluteJoint_GetSpringHertz` (`include/box2d/box2d.h:1093`).
pub fn revoluteJointSpringHertz(self: JointId) f32 {
    return c.b2RevoluteJoint_GetSpringHertz(self);
}

/// `b2RevoluteJoint_SetSpringDampingRatio` (`include/box2d/box2d.h:1096`).
pub fn revoluteJointSetSpringDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2RevoluteJoint_SetSpringDampingRatio(self, damping_ratio);
}

/// `b2RevoluteJoint_GetSpringDampingRatio` (`include/box2d/box2d.h:1099`).
pub fn revoluteJointGetSpringDampingRatio(self: JointId) f32 {
    return c.b2RevoluteJoint_GetSpringDampingRatio(self);
}

/// `b2RevoluteJoint_SetTargetAngle` (`include/box2d/box2d.h:1102`).
pub fn revoluteJointSetTargetAngle(self: JointId, angle: f32) void {
    c.b2RevoluteJoint_SetTargetAngle(self, angle);
}

/// `b2RevoluteJoint_GetTargetAngle` (`include/box2d/box2d.h:1105`).
pub fn revoluteJointTargetAngle(self: JointId) f32 {
    return c.b2RevoluteJoint_GetTargetAngle(self);
}

/// `b2RevoluteJoint_GetAngle` (`include/box2d/box2d.h:1109`).
pub fn revoluteJointAngle(self: JointId) f32 {
    return c.b2RevoluteJoint_GetAngle(self);
}

/// `b2RevoluteJoint_EnableLimit` (`include/box2d/box2d.h:1112`).
pub fn revoluteJointEnableLimit(self: JointId, enable_limit: bool) void {
    c.b2RevoluteJoint_EnableLimit(self, enable_limit);
}

/// `b2RevoluteJoint_IsLimitEnabled` (`include/box2d/box2d.h:1115`).
pub fn revoluteJointIsLimitEnabled(self: JointId) bool {
    return c.b2RevoluteJoint_IsLimitEnabled(self);
}

/// `b2RevoluteJoint_GetLowerLimit` (`include/box2d/box2d.h:1118`).
pub fn revoluteJointLowerLimit(self: JointId) f32 {
    return c.b2RevoluteJoint_GetLowerLimit(self);
}

/// `b2RevoluteJoint_GetUpperLimit` (`include/box2d/box2d.h:1121`).
pub fn revoluteJointUpperLimit(self: JointId) f32 {
    return c.b2RevoluteJoint_GetUpperLimit(self);
}

/// `b2RevoluteJoint_SetLimits` (`include/box2d/box2d.h:1125`).
pub fn revoluteJointSetLimits(self: JointId, lower: f32, upper: f32) void {
    c.b2RevoluteJoint_SetLimits(self, lower, upper);
}

/// `b2RevoluteJoint_EnableMotor` (`include/box2d/box2d.h:1128`).
pub fn revoluteJointEnableMotor(self: JointId, enable_motor: bool) void {
    c.b2RevoluteJoint_EnableMotor(self, enable_motor);
}

/// `b2RevoluteJoint_IsMotorEnabled` (`include/box2d/box2d.h:1131`).
pub fn revoluteJointIsMotorEnabled(self: JointId) bool {
    return c.b2RevoluteJoint_IsMotorEnabled(self);
}

/// `b2RevoluteJoint_SetMotorSpeed` (`include/box2d/box2d.h:1134`).
pub fn revoluteJointSetMotorSpeed(self: JointId, motor_speed: f32) void {
    c.b2RevoluteJoint_SetMotorSpeed(self, motor_speed);
}

/// `b2RevoluteJoint_GetMotorSpeed` (`include/box2d/box2d.h:1137`).
pub fn revoluteJointMotorSpeed(self: JointId) f32 {
    return c.b2RevoluteJoint_GetMotorSpeed(self);
}

/// `b2RevoluteJoint_GetMotorTorque` (`include/box2d/box2d.h:1140`).
pub fn revoluteJointMotorTorque(self: JointId) f32 {
    return c.b2RevoluteJoint_GetMotorTorque(self);
}

/// `b2RevoluteJoint_SetMaxMotorTorque` (`include/box2d/box2d.h:1143`).
pub fn revoluteJointSetMaxMotorTorque(self: JointId, torque: f32) void {
    c.b2RevoluteJoint_SetMaxMotorTorque(self, torque);
}

/// `b2RevoluteJoint_GetMaxMotorTorque` (`include/box2d/box2d.h:1146`).
pub fn revoluteJointMaxMotorTorque(self: JointId) f32 {
    return c.b2RevoluteJoint_GetMaxMotorTorque(self);
}

/// `b2CreateWeldJoint` (`include/box2d/box2d.h:1163`).
pub fn createWeldJoint(world: WorldId, def: *const WeldJointDef) JointId {
    return c.b2CreateWeldJoint(world, def);
}

/// `b2WeldJoint_SetLinearHertz` (`include/box2d/box2d.h:1166`).
pub fn weldJointSetLinearHertz(self: JointId, hertz: f32) void {
    c.b2WeldJoint_SetLinearHertz(self, hertz);
}

/// `b2WeldJoint_GetLinearHertz` (`include/box2d/box2d.h:1169`).
pub fn weldJointLinearHertz(self: JointId) f32 {
    return c.b2WeldJoint_GetLinearHertz(self);
}

/// `b2WeldJoint_SetLinearDampingRatio` (`include/box2d/box2d.h:1172`).
pub fn weldJointSetLinearDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2WeldJoint_SetLinearDampingRatio(self, damping_ratio);
}

/// `b2WeldJoint_GetLinearDampingRatio` (`include/box2d/box2d.h:1175`).
pub fn weldJointLinearDampingRatio(self: JointId) f32 {
    return c.b2WeldJoint_GetLinearDampingRatio(self);
}

/// `b2WeldJoint_SetAngularHertz` (`include/box2d/box2d.h:1178`).
pub fn weldJointSetAngularHertz(self: JointId, hertz: f32) void {
    c.b2WeldJoint_SetAngularHertz(self, hertz);
}

/// `b2WeldJoint_GetAngularHertz` (`include/box2d/box2d.h:1181`).
pub fn weldJointAngularHertz(self: JointId) f32 {
    return c.b2WeldJoint_GetAngularHertz(self);
}

/// `b2WeldJoint_SetAngularDampingRatio` (`include/box2d/box2d.h:1184`).
pub fn weldJointSetAngularDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2WeldJoint_SetAngularDampingRatio(self, damping_ratio);
}

/// `b2WeldJoint_GetAngularDampingRatio` (`include/box2d/box2d.h:1187`).
pub fn weldJointAngularDampingRatio(self: JointId) f32 {
    return c.b2WeldJoint_GetAngularDampingRatio(self);
}

/// `b2CreateWheelJoint` (`include/box2d/box2d.h:1203`).
pub fn createWheelJoint(world: WorldId, def: *const WheelJointDef) JointId {
    return c.b2CreateWheelJoint(world, def);
}

/// `b2WheelJoint_EnableSpring` (`include/box2d/box2d.h:1206`).
pub fn wheelJointEnableSpring(self: JointId, enable_spring: bool) void {
    c.b2WheelJoint_EnableSpring(self, enable_spring);
}

/// `b2WheelJoint_IsSpringEnabled` (`include/box2d/box2d.h:1209`).
pub fn wheelJointIsSpringEnabled(self: JointId) bool {
    return c.b2WheelJoint_IsSpringEnabled(self);
}

/// `b2WheelJoint_SetSpringHertz` (`include/box2d/box2d.h:1212`).
pub fn wheelJointSetSpringHertz(self: JointId, hertz: f32) void {
    c.b2WheelJoint_SetSpringHertz(self, hertz);
}

/// `b2WheelJoint_GetSpringHertz` (`include/box2d/box2d.h:1215`).
pub fn wheelJointSpringHertz(self: JointId) f32 {
    return c.b2WheelJoint_GetSpringHertz(self);
}

/// `b2WheelJoint_SetSpringDampingRatio` (`include/box2d/box2d.h:1218`).
pub fn wheelJointSetSpringDampingRatio(self: JointId, damping_ratio: f32) void {
    c.b2WheelJoint_SetSpringDampingRatio(self, damping_ratio);
}

/// `b2WheelJoint_GetSpringDampingRatio` (`include/box2d/box2d.h:1221`).
pub fn wheelJointGetSpringDampingRatio(self: JointId) f32 {
    return c.b2WheelJoint_GetSpringDampingRatio(self);
}

/// `b2WheelJoint_EnableLimit` (`include/box2d/box2d.h:1224`).
pub fn wheelJointEnableLimit(self: JointId, enable_limit: bool) void {
    c.b2WheelJoint_EnableLimit(self, enable_limit);
}

/// `b2WheelJoint_IsLimitEnabled` (`include/box2d/box2d.h:1227`).
pub fn wheelJointIsLimitEnabled(self: JointId) bool {
    return c.b2WheelJoint_IsLimitEnabled(self);
}

/// `b2WheelJoint_GetLowerLimit` (`include/box2d/box2d.h:1230`).
pub fn wheelJointLowerLimit(self: JointId) f32 {
    return c.b2WheelJoint_GetLowerLimit(self);
}

/// `b2WheelJoint_GetUpperLimit` (`include/box2d/box2d.h:1233`).
pub fn wheelJointUpperLimit(self: JointId) f32 {
    return c.b2WheelJoint_GetUpperLimit(self);
}

/// `b2WheelJoint_SetLimits` (`include/box2d/box2d.h:1236`).
pub fn wheelJointSetLimits(self: JointId, lower: f32, upper: f32) void {
    c.b2WheelJoint_SetLimits(self, lower, upper);
}

/// `b2WheelJoint_EnableMotor` (`include/box2d/box2d.h:1239`).
pub fn wheelJointEnableMotor(self: JointId, enable_motor: bool) void {
    c.b2WheelJoint_EnableMotor(self, enable_motor);
}

/// `b2WheelJoint_IsMotorEnabled` (`include/box2d/box2d.h:1242`).
pub fn wheelJointIsMotorEnabled(self: JointId) bool {
    return c.b2WheelJoint_IsMotorEnabled(self);
}

/// `b2WheelJoint_SetMotorSpeed` (`include/box2d/box2d.h:1245`).
pub fn wheelJointSetMotorSpeed(self: JointId, motor_speed: f32) void {
    c.b2WheelJoint_SetMotorSpeed(self, motor_speed);
}

/// `b2WheelJoint_GetMotorSpeed` (`include/box2d/box2d.h:1248`).
pub fn wheelJointMotorSpeed(self: JointId) f32 {
    return c.b2WheelJoint_GetMotorSpeed(self);
}

/// `b2WheelJoint_SetMaxMotorTorque` (`include/box2d/box2d.h:1251`).
pub fn wheelJointSetMaxMotorTorque(self: JointId, max_motor_torque: f32) void {
    c.b2WheelJoint_SetMaxMotorTorque(self, max_motor_torque);
}

/// `b2WheelJoint_GetMaxMotorTorque` (`include/box2d/box2d.h:1254`).
pub fn wheelJointMaxMotorTorque(self: JointId) f32 {
    return c.b2WheelJoint_GetMaxMotorTorque(self);
}

/// `b2WheelJoint_GetMotorTorque` (`include/box2d/box2d.h:1257`).
pub fn wheelJointMotorTorque(self: JointId) f32 {
    return c.b2WheelJoint_GetMotorTorque(self);
}