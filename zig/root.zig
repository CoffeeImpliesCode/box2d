// SPDX-License-Identifier: MIT
//
//! Zig facade for Box2D's C API; simulation and native types remain upstream's.
//!
//! Import as `@import("box2d")`; `c` exposes the translated header.
//! Definitions and geometry are borrowed for each call; event slices borrow
//! world storage until its next step or destruction.
//! Creation errors use `CreateError`; upstream assertions still abort.
//! See `README.zig.md` for configuration details.

const std = @import("std");

/// The translated Box2D API, or a dispatch with the same declarations in runtime-loaded builds.
/// Calls follow upstream behavior; declarations not wrapped below remain accessible here.
pub const c = @import("c");

/// Loader definitions used by the linked configuration.
const rt = @import("rt");

/// Whether symbols resolve through the platform loader at runtime.
/// Comptime false means linked; true means `load` must run before other calls.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Selects an explicit file path or platform library name for `load`.
/// Neither source falls back to the other.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned while loading the native library.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the selected provider once and retains its handle until process exit.
/// Returns `LoadError` on failure or provider mismatch; same-request calls wait, reentrant calls fail, and linked builds panic.
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

/// Returns the successful request, or null before loading and in linked builds.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// Errors returned by creation helpers when upstream refuses a request.
/// Each helper can return only the tag produced by its own refusal check.
pub const CreateError = error{
    /// No world slots remain (`B2_MAX_WORLDS`).
    WorldLimitReached,
    /// The world is locked or a segment is degenerate; upstream returns a null id for either.
    WorldLocked,
    /// The points do not form a convex hull.
    HullNotConvex,
};

/// Maximum vertices in a convex polygon, fixed by upstream's `B2_MAX_POLYGON_VERTICES`.
pub const max_polygon_vertices: usize = c.B2_MAX_POLYGON_VERTICES;

/// The default collision category bits, `B2_DEFAULT_CATEGORY_BITS`
/// (`include/box2d/types.h:14`): category one.
pub const default_category_bits: u64 = c.B2_DEFAULT_CATEGORY_BITS;

/// The default collision mask bits, `B2_DEFAULT_MASK_BITS`
/// (`include/box2d/types.h:15`): every category.
pub const default_mask_bits: u64 = c.B2_DEFAULT_MASK_BITS;

/// Box2D's `B2_PI` constant.
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

/// Opaque handle to a world. Pass it back unchanged; use `worldIsValid` to check it.
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

/// Tests whether a handle is null.
pub fn isNullId(id: anytype) bool {
    return id.index1 == 0;
}

/// Compares handle fields. Use only with body, shape, chain or joint ids, not world ids.
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

/// `b2Vec2` (`include/box2d/math_functions.h:20`). Two `f32`, so its layout is
/// the platform's scalar width and nothing else.
pub const Vec2 = c.b2Vec2;

/// `b2CosSin` (`include/box2d/math_functions.h:28`).
pub const CosSin = c.b2CosSin;

/// A rotation stored as cosine and sine, `b2Rot`.
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

/// `b2Polygon`; build valid values with the polygon helpers.
pub const Polygon = c.b2Polygon;

/// `b2Segment` (`include/box2d/collision.h:152`): a two-sided line segment.
pub const Segment = c.b2Segment;

/// One-sided segment with ghost vertices, owned by a chain shape.
pub const ChainSegment = c.b2ChainSegment;

/// Convex hull built by `computeHull`; `makePolygon` asserts on invalid hulls.
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

/// Dynamic-tree storage. Create with `dynamicTreeCreate` and destroy once with `dynamicTreeDestroy`.
pub const DynamicTree = c.b2DynamicTree;

/// `b2TreeStats` (`include/box2d/collision.h:658`).
pub const TreeStats = c.b2TreeStats;

/// `b2PlaneResult` (`include/box2d/collision.h:783`).
pub const PlaneResult = c.b2PlaneResult;

/// `b2CollisionPlane` (`include/box2d/collision.h:797`).
pub const CollisionPlane = c.b2CollisionPlane;

/// `b2PlaneSolverResult` (`include/box2d/collision.h:814`).
pub const PlaneSolverResult = c.b2PlaneSolverResult;

/// World definition. Obtain a valid value from `defaultWorldDef`; zeroed values fail upstream checks.
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

/// Chain definition. `createChain` clones `points` and `materials`; invalid counts assert.
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

/// Sensor end event; either shape id may already be invalid.
pub const SensorEndTouchEvent = c.b2SensorEndTouchEvent;

/// `b2SensorEvents` (`include/box2d/types.h:1034`).
pub const SensorEvents = c.b2SensorEvents;

/// `b2ContactBeginTouchEvent` (`include/box2d/types.h:1050`).
pub const ContactBeginTouchEvent = c.b2ContactBeginTouchEvent;

/// Contact end event; either shape id may already be invalid.
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

/// Callback table used by `worldDraw`; initialize with `defaultDebugDraw`.
pub const DebugDraw = c.b2DebugDraw;

/// `b2RayResult` (`include/box2d/types.h:67`).
pub const RayResult = c.b2RayResult;

/// `b2HexColor` (`include/box2d/types.h:1230`).
pub const HexColor = c.b2HexColor;

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

/// Called during solving on worker threads; avoid accessing Box2D or application state.
pub const FrictionCallback = c.b2FrictionCallback;

/// `b2RestitutionCallback` (`include/box2d/types.h:62`).
pub const RestitutionCallback = c.b2RestitutionCallback;

/// `b2CustomFilterFcn` (`include/box2d/types.h:1180`). Return false to refuse
/// the collision.
pub const CustomFilterFn = c.b2CustomFilterFcn;

/// Pre-solve callback; return false to skip this step's contact. Sensors are excluded.
pub const PreSolveFn = c.b2PreSolveFcn;

/// `b2OverlapResultFcn` (`include/box2d/types.h:1202`). Return false to stop
/// the query.
pub const OverlapResultFn = c.b2OverlapResultFcn;

/// `b2CastResultFcn` (`include/box2d/types.h:1220`): return `-1` to ignore, `0` to stop,
/// `1` to continue, or a fraction to clip the ray.
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

/// `b2GetVersion` (`include/box2d/base.h:84`) returns the active native library's version.
pub fn getVersion() Version {
    return c.b2GetVersion();
}

/// Sets process-wide allocator callbacks; both pointers are retained and must remain valid for process lifetime.
/// Passing null restores Box2D's allocator.
pub fn setAllocator(alloc: ?*const AllocFcn, free: ?*const FreeFcn) void {
    c.b2SetAllocator(alloc, free);
}

/// Returns the process-wide number of bytes allocated by Box2D.
pub fn getByteCount() c_int {
    return c.b2GetByteCount();
}

/// Sets the assertion callback; upstream requires it to be non-null and not return.
/// Return zero to skip the debugger break.
pub fn setAssertFcn(fcn: ?*const AssertFcn) void {
    c.b2SetAssertFcn(fcn);
}

/// Returns platform-specific ticks, which are not portable across platforms.
pub fn getTicks() u64 {
    return c.b2GetTicks();
}

/// `b2GetMilliseconds` (`include/box2d/base.h:118`).
pub fn getMilliseconds(ticks: u64) f32 {
    return c.b2GetMilliseconds(ticks);
}

/// Converts ticks to milliseconds and updates `ticks` to the current tick value.
pub fn getMillisecondsAndReset(ticks: *u64) f32 {
    return c.b2GetMillisecondsAndReset(ticks);
}

/// Yields to avoid starving the process in a busy loop.
pub fn yield() void {
    c.b2Yield();
}

/// Computes Box2D's rolling djb2 hash; pass each result as the next seed.
pub fn hash(seed: u32, data: []const u8) u32 {
    return c.b2Hash(seed, data.ptr, @intCast(data.len));
}

/// Returns an initialized world definition; use the matching helper for other definitions.
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

/// Constructs a vector from its components.
pub fn vec2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

/// Constructs a rotation from radians using Box2D's deterministic trigonometry.
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

/// Normalizes a vector, returning zero for zero-length input.
pub fn normalize(v: Vec2) Vec2 {
    return c.b2Normalize(v);
}

/// `b2IsNormalized` (`include/box2d/math_functions.h:310`).
pub fn isNormalized(a: Vec2) bool {
    return c.b2IsNormalized(a);
}

/// Returns the original length and normalized direction; zero input yields zero direction.
pub fn getLengthAndNormalize(v: Vec2) LengthAndDirection {
    var magnitude: f32 = 0;
    const direction = c.b2GetLengthAndNormalize(&magnitude, v);
    return .{ .length = magnitude, .direction = direction };
}

/// Length and direction returned by `getLengthAndNormalize`.
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

/// Returns the wrapped angle in `[-pi, pi]`.
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

/// Returns the bounds of `points`, expanded by `radius`; `points` must be non-empty.
/// Upstream asserts on an empty slice.
pub fn makeAabb(points: []const Vec2, radius: f32) Aabb {
    return c.b2MakeAABB(points.ptr, @intCast(points.len), radius);
}

/// `b2PlaneSeparation` (`include/box2d/math_functions.h:643`).
pub fn planeSeparation(plane: Plane, point: Vec2) f32 {
    return c.b2PlaneSeparation(plane, point);
}

/// Computes the next velocity for a one-dimensional mass-spring-damper.
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

/// Sets Box2D's length units per meter; call once before any other Box2D function.
/// The selected unit applies to every input and output length.
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

/// Builds a polygon from a hull returned by `computeHull`; upstream asserts on invalid hulls.
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

/// Builds a box at `center` with the given rotation, avoiding a later body move.
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

/// Copies up to `max_polygon_vertices` points into a query or shape-cast proxy.
pub fn makeProxy(points: []const Vec2, radius: f32) ShapeProxy {
    return c.b2MakeProxy(points.ptr, @intCast(points.len), radius);
}

/// `b2MakeOffsetProxy` (`include/box2d/collision.h:435`).
pub fn makeOffsetProxy(points: []const Vec2, radius: f32, position: Vec2, rotation: Rot) ShapeProxy {
    return c.b2MakeOffsetProxy(points.ptr, @intCast(points.len), radius, position, rotation);
}

/// Computes a convex hull.
/// Returns `HullNotConvex` when the points cannot form one.
pub fn computeHull(points: []const Vec2) CreateError!Hull {
    const hull = c.b2ComputeHull(points.ptr, @intCast(points.len));
    if (hull.count == 0) return error.HullNotConvex;
    return hull;
}

/// Checks whether `hull` is valid for `makePolygon`.
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

/// Casts a ray against a segment; `one_sided` makes only the right side solid.
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

/// Computes GJK distance; zero `cache.count` before the first call.
/// `cache` is updated; `simplexes` is optional debug output.
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

/// Estimates the first impact fraction within `maxFraction`; intermediate non-tunneling collisions may be missed.
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

/// Collides a chain segment and capsule, using a zero-initialized simplex cache.
pub fn collideChainSegmentAndCapsule(
    a: *const ChainSegment,
    xf_a: Transform,
    b: *const Capsule,
    xf_b: Transform,
) Manifold {
    var cache = std.mem.zeroes(SimplexCache);
    return c.b2CollideChainSegmentAndCapsule(a, xf_a, b, xf_b, &cache);
}

/// Collides a chain segment and polygon, using a zero-initialized simplex cache.
pub fn collideChainSegmentAndPolygon(
    a: *const ChainSegment,
    xf_a: Transform,
    b: *const Polygon,
    xf_b: Transform,
) Manifold {
    var cache = std.mem.zeroes(SimplexCache);
    return c.b2CollideChainSegmentAndPolygon(a, xf_a, b, xf_b, &cache);
}

/// Solves for a mover translation satisfying all planes.
/// Mutates `planes` by writing each plane's `push` value.
pub fn solvePlanes(target_delta: Vec2, planes: []CollisionPlane) PlaneSolverResult {
    return c.b2SolvePlanes(target_delta, planes.ptr, @intCast(planes.len));
}

/// Clips a vector against planes with non-zero `push` and `clipVelocity`.
pub fn clipVector(vector: Vec2, planes: []const CollisionPlane) Vec2 {
    return c.b2ClipVector(vector, planes.ptr, @intCast(planes.len));
}

/// Creates a tree that owns a node pool; destroy it exactly once.
/// Do not copy a tree after use.
pub fn dynamicTreeCreate() DynamicTree {
    return c.b2DynamicTree_Create();
}

/// Frees the node pool; proxy ids and the tree are invalid afterwards.
pub fn dynamicTreeDestroy(tree: *DynamicTree) void {
    c.b2DynamicTree_Destroy(tree);
}

/// `b2DynamicTree_CreateProxy` (`include/box2d/collision.h:674`).
pub fn dynamicTreeCreateProxy(tree: *DynamicTree, aabb: Aabb, category_bits: u64, user_data: u64) c_int {
    return c.b2DynamicTree_CreateProxy(tree, aabb, category_bits, user_data);
}

/// Destroys a proxy; upstream asserts on an invalid id.
pub fn dynamicTreeDestroyProxy(tree: *DynamicTree, proxy_id: c_int) void {
    c.b2DynamicTree_DestroyProxy(tree, proxy_id);
}

/// `b2DynamicTree_MoveProxy` (`include/box2d/collision.h:680`).
pub fn dynamicTreeMoveProxy(tree: *DynamicTree, proxy_id: c_int, aabb: Aabb) void {
    c.b2DynamicTree_MoveProxy(tree, proxy_id, aabb);
}

/// Enlarges the proxy and ancestor boxes without reinserting the proxy.
pub fn dynamicTreeEnlargeProxy(tree: *DynamicTree, proxy_id: c_int, aabb: Aabb) void {
    c.b2DynamicTree_EnlargeProxy(tree, proxy_id, aabb);
}

/// Sets category bits; upstream reinserts the proxy.
pub fn dynamicTreeSetCategoryBits(tree: *DynamicTree, proxy_id: c_int, category_bits: u64) void {
    c.b2DynamicTree_SetCategoryBits(tree, proxy_id, category_bits);
}

/// `b2DynamicTree_GetCategoryBits` (`include/box2d/collision.h:689`).
pub fn dynamicTreeGetCategoryBits(tree: *const DynamicTree, proxy_id: c_int) u64 {
    return c.b2DynamicTree_GetCategoryBits(tree, proxy_id);
}

/// Queries overlapping proxies; callback must be non-null and context valid for the call.
pub fn dynamicTreeQuery(
    tree: *const DynamicTree,
    aabb: Aabb,
    mask_bits: u64,
    callback: ?*const TreeQueryCallbackFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2DynamicTree_Query(tree, aabb, mask_bits, callback, context);
}

/// Ray-casts candidate proxies; callback must be non-null and perform exact filtering.
/// Tree mask filtering is approximate.
pub fn dynamicTreeRayCast(
    tree: *const DynamicTree,
    input: *const RayCastInput,
    mask_bits: u64,
    callback: ?*const TreeRayCastCallbackFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2DynamicTree_RayCast(tree, input, mask_bits, callback, context);
}

/// Shape-casts candidate proxies; callback must be non-null.
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

/// Rebuilds the tree and returns the number of boxes sorted.
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

/// Creates a world; reads `def` without retaining it.
/// Returns `WorldLimitReached` when all world slots are in use.
pub fn createWorld(def: *const WorldDef) CreateError!WorldId {
    const id = c.b2CreateWorld(def);
    if (isNullId(id)) return error.WorldLimitReached;
    return id;
}

/// Destroys a world and all its owned objects, invalidating every id it issued.
/// Frees the world's pools.
pub fn destroyWorld(self: WorldId) void {
    c.b2DestroyWorld(self);
}

/// Checks whether `id` is a live world handle; use before other world calls.
pub fn worldIsValid(id: WorldId) bool {
    return c.b2World_IsValid(id);
}

/// Advances the simulation by `time_step`, split into solver sub-steps.
/// Events last until the next step or destruction; creation helpers return `WorldLocked` during a step.
pub fn worldStep(self: WorldId, time_step: f32, sub_step_count: c_int) void {
    c.b2World_Step(self, time_step, sub_step_count);
}

/// Calls the drawing callbacks; `draw` and its contents are borrowed for the call.
pub fn worldDraw(self: WorldId, draw: *DebugDraw) void {
    c.b2World_Draw(self, draw);
}

/// Returns the raw body event pointers and counts; prefer the bounded slice helpers.
pub fn worldBodyEvents(self: WorldId) BodyEvents {
    return c.b2World_GetBodyEvents(self);
}

/// Returns body move events borrowed from the world until its next step or destruction.
/// The slice is empty when no bodies moved.
pub fn bodyMoveEvents(self: WorldId) []const BodyMoveEvent {
    const events = c.b2World_GetBodyEvents(self);
    return events.moveEvents[0..bounded(events.moveCount)];
}

/// `b2World_GetSensorEvents` (`include/box2d/box2d.h:48`).
pub fn worldSensorEvents(self: WorldId) SensorEvents {
    return c.b2World_GetSensorEvents(self);
}

/// Returns sensor begin events borrowed until the next step or world destruction.
pub fn sensorBeginEvents(self: WorldId) []const SensorBeginTouchEvent {
    const events = c.b2World_GetSensorEvents(self);
    return events.beginEvents[0..bounded(events.beginCount)];
}

/// Returns sensor end events borrowed until the next step or world destruction.
/// Either shape id may be invalid; check it with `shapeIsValid`.
pub fn sensorEndEvents(self: WorldId) []const SensorEndTouchEvent {
    const events = c.b2World_GetSensorEvents(self);
    return events.endEvents[0..bounded(events.endCount)];
}

/// `b2World_GetContactEvents` (`include/box2d/box2d.h:51`).
pub fn worldContactEvents(self: WorldId) ContactEvents {
    return c.b2World_GetContactEvents(self);
}

/// Returns contact begin events borrowed until the next step or world destruction.
/// The initial manifold has zero impulses.
pub fn contactBeginEvents(self: WorldId) []const ContactBeginTouchEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.beginEvents[0..bounded(events.beginCount)];
}

/// Returns contact end events borrowed until the next step or world destruction.
/// Either shape may already be destroyed.
pub fn contactEndEvents(self: WorldId) []const ContactEndTouchEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.endEvents[0..bounded(events.endCount)];
}

/// Returns contact hit events borrowed until the next step or world destruction.
/// Both shapes must enable hit events and exceed the world threshold.
pub fn contactHitEvents(self: WorldId) []const ContactHitEvent {
    const events = c.b2World_GetContactEvents(self);
    return events.hitEvents[0..bounded(events.hitCount)];
}

fn bounded(count: c_int) usize {
    return @intCast(@max(count, 0));
}

/// Calls `fcn` for each shape overlapping `aabb`; the callback must be non-null.
/// The callback and context are borrowed until the call returns.
pub fn worldOverlapAabb(
    self: WorldId,
    aabb: Aabb,
    filter: QueryFilter,
    fcn: ?*const OverlapResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_OverlapAABB(self, aabb, filter, fcn, context);
}

/// Calls `fcn` for each overlapping shape; the callback must be non-null.
pub fn worldOverlapShape(
    self: WorldId,
    proxy: *const ShapeProxy,
    filter: QueryFilter,
    fcn: ?*const OverlapResultFn,
    context: ?*anyopaque,
) TreeStats {
    return c.b2World_OverlapShape(self, proxy, filter, fcn, context);
}

/// Casts a ray and reports hits through a non-null callback.
/// Return -1 to ignore, 0 to stop, a fraction to clip, or 1 to continue.
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

/// Returns the closest ray hit without a callback or custom filtering.
/// Initial overlaps may have zero fraction and normal; check `hit`.
pub fn worldCastRayClosest(self: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter) RayResult {
    return c.b2World_CastRayClosest(self, origin, translation, filter);
}

/// Casts a shape and reports hits through a non-null callback.
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

/// Casts a capsule mover and returns its allowed travel fraction.
pub fn worldCastMover(self: WorldId, mover: *const Capsule, translation: Vec2, filter: QueryFilter) f32 {
    return c.b2World_CastMover(self, mover, translation, filter);
}

/// Reports collision planes for a mover through a non-null callback.
/// Return false from the callback to stop gathering planes.
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

/// Sets the minimum approach speed for a collision to bounce.
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

/// Sets a filter callback retained by the world; it and its context must outlive it.
/// It runs on worker threads and must not modify the world.
pub fn worldSetCustomFilterCallback(self: WorldId, fcn: ?*const CustomFilterFn, context: ?*anyopaque) void {
    c.b2World_SetCustomFilterCallback(self, fcn, context);
}

/// Sets the retained pre-solve callback; it follows the filter callback's lifetime and threading rules.
pub fn worldSetPreSolveCallback(self: WorldId, fcn: ?*const PreSolveFn, context: ?*anyopaque) void {
    c.b2World_SetPreSolveCallback(self, fcn, context);
}

/// Sets world gravity; Box2D has no default up direction.
pub fn worldSetGravity(self: WorldId, gravity: Vec2) void {
    c.b2World_SetGravity(self, gravity);
}

/// `b2World_GetGravity` (`include/box2d/box2d.h:137`).
pub fn worldGetGravity(self: WorldId) Vec2 {
    return c.b2World_GetGravity(self);
}

/// Applies an explosion impulse per unit perimeter; reads `explosion_def` during the call.
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

/// Returns per-stage timings in milliseconds for the last step.
pub fn worldGetProfile(self: WorldId) Profile {
    return c.b2World_GetProfile(self);
}

/// `b2World_GetCounters` (`include/box2d/box2d.h:172`).
pub fn worldGetCounters(self: WorldId) Counters {
    return c.b2World_GetCounters(self);
}

/// Stores `user_data` without copying it; its pointee must outlive the world.
pub fn worldSetUserData(self: WorldId, user_data: ?*anyopaque) void {
    c.b2World_SetUserData(self, user_data);
}

/// `b2World_GetUserData` (`include/box2d/box2d.h:178`).
pub fn worldGetUserData(self: WorldId) ?*anyopaque {
    return c.b2World_GetUserData(self);
}

/// Sets the friction mixer; null restores `sqrt(frictionA * frictionB)`.
pub fn worldSetFrictionCallback(self: WorldId, callback: ?*const FrictionCallback) void {
    c.b2World_SetFrictionCallback(self, callback);
}

/// Sets the restitution mixer; null restores `max(restitutionA, restitutionB)`.
pub fn worldSetRestitutionCallback(self: WorldId, callback: ?*const RestitutionCallback) void {
    c.b2World_SetRestitutionCallback(self, callback);
}

/// Writes `box2d_memory.txt` to the process working directory.
pub fn worldDumpMemoryStats(self: WorldId) void {
    c.b2World_DumpMemoryStats(self);
}

/// Rebuilds the static tree; intended for upstream testing.
pub fn worldRebuildStaticTree(self: WorldId) void {
    c.b2World_RebuildStaticTree(self);
}

/// Enables speculative contacts; intended for upstream testing.
pub fn worldEnableSpeculative(self: WorldId, flag: bool) void {
    c.b2World_EnableSpeculative(self, flag);
}

/// Creates a body from a definition read only during the call; it starts without shapes.
/// Returns `WorldLocked` if the world is locked.
pub fn createBody(world: WorldId, def: *const BodyDef) CreateError!BodyId {
    const id = c.b2CreateBody(world, def);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Destroys a body and its shapes, joints and contacts, invalidating their handles.
pub fn destroyBody(self: BodyId) void {
    c.b2DestroyBody(self);
}

/// Checks whether a body handle is live; safe for null, stale or destroyed-world ids.
pub fn bodyIsValid(id: BodyId) bool {
    return c.b2Body_IsValid(id);
}

/// `b2Body_GetType` (`include/box2d/box2d.h:220`).
pub fn bodyType(self: BodyId) BodyType {
    return c.b2Body_GetType(self);
}

/// Changes body type and ends its contacts, producing end-touch events next step.
pub fn bodySetType(self: BodyId, body_type: BodyType) void {
    c.b2Body_SetType(self, body_type);
}

/// Copies a sentinel-terminated name into the body, truncating to 31 bytes.
/// The body owns it until the next `bodySetName` or body destruction.
pub fn bodySetName(self: BodyId, name: [*:0]const u8) void {
    c.b2Body_SetName(self, name);
}

/// Returns a NUL-terminated view into body-owned storage, valid until replaced or destroyed.
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

/// Teleports the body; changed contacts produce end-touch events.
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

/// Moves the body to `target` over `time_step` without teleporting.
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

/// `b2Body_ApplyForce` (`include/box2d/box2d.h:295`) applies force at world-space `point`; `wake` controls wake-up.
/// Reapply each step for a continuous force.
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

/// `b2Body_ApplyLinearImpulse` (`include/box2d/box2d.h:321`) applies one impulse at world-space `point`; `wake` controls wake-up.
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

/// Overrides shape-derived mass until a shape is added or destroyed.
pub fn bodySetMassData(self: BodyId, mass_data: MassData) void {
    c.b2Body_SetMassData(self, mass_data);
}

/// `b2Body_GetMassData` (`include/box2d/box2d.h:359`).
pub fn bodyMassData(self: BodyId) MassData {
    return c.b2Body_GetMassData(self);
}

/// Recomputes mass from the body's shapes and discards any override.
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

/// Enables bullet mode; bullets are not a general fast-collision solution and can affect joints.
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

/// Returns the shape count; use it to size `bodyShapes` output.
pub fn bodyShapeCount(self: BodyId) c_int {
    return c.b2Body_GetShapeCount(self);
}

/// Writes up to `out.len` shape ids and returns the number written.
/// Truncates silently; compare with `bodyShapeCount` to detect an undersized slice.
pub fn bodyShapes(self: BodyId, out: []ShapeId) usize {
    return @intCast(c.b2Body_GetShapes(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_GetJointCount` (`include/box2d/box2d.h:450`).
pub fn bodyJointCount(self: BodyId) c_int {
    return c.b2Body_GetJointCount(self);
}

/// Writes up to `out.len` joint ids and returns the number written.
pub fn bodyJoints(self: BodyId, out: []JointId) usize {
    return @intCast(c.b2Body_GetJoints(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_GetContactCapacity` (`include/box2d/box2d.h:457`).
pub fn bodyContactCapacity(self: BodyId) c_int {
    return c.b2Body_GetContactCapacity(self);
}

/// Writes up to `out.len` contact records; truncates, and manifolds are overwritten next step.
pub fn bodyContactData(self: BodyId, out: []ContactData) usize {
    return @intCast(c.b2Body_GetContactData(self, out.ptr, @intCast(out.len)));
}

/// `b2Body_ComputeAABB` (`include/box2d/box2d.h:467`).
pub fn bodyComputeAabb(self: BodyId) Aabb {
    return c.b2Body_ComputeAABB(self);
}

/// Constructs a circle from its center and radius.
pub fn circle(center: Vec2, radius: f32) Circle {
    return .{ .center = center, .radius = radius };
}

/// Creates a circle shape; geometry is copied and `def` is read only during the call.
/// Returns `WorldLocked` when the world is locked.
pub fn createCircleShape(body: BodyId, def: *const ShapeDef, geometry: *const Circle) CreateError!ShapeId {
    const id = c.b2CreateCircleShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Refuses degenerate segments with an upstream assertion; if execution returns, the error is `WorldLocked`.
pub fn createSegmentShape(body: BodyId, def: *const ShapeDef, geometry: *const Segment) CreateError!ShapeId {
    const id = c.b2CreateSegmentShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Creates a capsule shape; coincident centers within linear slop produce a circle.
/// Returns `WorldLocked` if the world is locked.
pub fn createCapsuleShape(body: BodyId, def: *const ShapeDef, geometry: *const Capsule) CreateError!ShapeId {
    const id = c.b2CreateCapsuleShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Creates a polygon shape; geometry is copied and a locked world returns `WorldLocked`.
pub fn createPolygonShape(body: BodyId, def: *const ShapeDef, geometry: *const Polygon) CreateError!ShapeId {
    const id = c.b2CreatePolygonShape(body, def, geometry);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Destroys a shape and its contacts and overlaps, invalidating its id.
/// `update_body_mass` controls whether the owning body's mass is recomputed.
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

/// Sets density; `update_body_mass` controls whether the body's mass is recomputed.
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

/// Sets the user material id passed to mixing callbacks and query results.
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

/// `b2Shape_SetFilter` (`include/box2d/box2d.h:569`) ends the shape's contacts; the next step emits end-touch events.
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

/// `b2Shape_EnablePreSolveEvents` (`include/box2d/box2d.h:589`) is dynamic-body-only and incurs threading cost (`include/box2d/types.h:394-396`).
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

/// Casts the shape using `input`, which is read only during the call.
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

/// Returns chain-segment geometry; valid only for chain-segment shapes.
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

/// Copies the geometry, moves the shape and resets its contacts.
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

/// Returns the parent chain id, or a null id for a non-chain shape.
pub fn shapeParentChain(self: ShapeId) ChainId {
    return c.b2Shape_GetParentChain(self);
}

/// `b2Shape_GetContactCapacity` (`include/box2d/box2d.h:646`).
pub fn shapeContactCapacity(self: ShapeId) c_int {
    return c.b2Shape_GetContactCapacity(self);
}

/// Writes up to `out.len` contact records and truncates like `bodyShapes`.
pub fn shapeContactData(self: ShapeId, out: []ContactData) usize {
    return @intCast(c.b2Shape_GetContactData(self, out.ptr, @intCast(out.len)));
}

/// `b2Shape_GetSensorCapacity` (`include/box2d/box2d.h:658`).
pub fn shapeSensorCapacity(self: ShapeId) c_int {
    return c.b2Shape_GetSensorCapacity(self);
}

/// Writes up to `out.len` overlapping shape ids and truncates like `bodyShapes`.
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

/// Clones points and materials; requires a static body and at least four counter-clockwise points.
/// Chains are one-sided, have no mass, and create separate segment shape ids.
pub fn createChain(body: BodyId, def: *const ChainDef) CreateError!ChainId {
    const id = c.b2CreateChain(body, def);
    if (isNullId(id)) return error.WorldLocked;
    return id;
}

/// Destroys the chain and every segment shape it created.
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

/// Writes up to `out.len` segment shape ids and truncates like `bodyShapes`.
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

/// Destroys a joint and wakes the bodies it joined.
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

/// Returns frequency and damping ratio from the last solve.
/// Combines upstream's two out-parameters into `ConstraintTuning`.
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

/// Creates a distance joint; reads `def` without retaining it.
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

/// Creates a joint that suppresses contact between its two bodies while connected.
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
