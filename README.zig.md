# README.zig.md — the Zig interface

Box2D as a Zig SDK: how to consume it, what the module exposes, and where its
real boundaries are.

What follows about the interface is `SOURCE-CONFIRMED`: it is read out of
`build.zig`, `runtime/`, `zig/`, `tests.zig`, `smoke.zig` and the upstream
sources in this repository, not inferred from what those files might plausibly
do.

The gates are a separate question and the two are not in step. On this host,
`zig build smoke test` has run on the linked branch — upstream's full C suite,
this package's 14 SDK tests and the smoke program — and
`zig build smoke -Druntime=true -Dlinkage=static` has run on the
runtime-loaded branch, against a shared provider supplied from outside this
tree. A later run covered `zig build test smoke install` in all four optimize
modes and both linkages, and a nested-delivery proof covered nine cases of
`zig build consumer`. Section 8 lists all three and section 3 of `README.md`
carries them as rows. What has not been run is named there too: the `smoke`
runtime-loaded branch with a shared delivery, a direct `cd consumer` entry, a
filtered fetched package, a standalone `zig build upstream-test`, the two
compile matrices and the devenv entries, and this file claims none of them.

---

## 1. Build options

| Option | Values | Default | What it selects |
| --- | --- | --- | --- |
| `-Dlinkage` | `static`, `dynamic` | `static` | the native library form. Static is this SDK's policy and upstream's CMake default (`BUILD_SHARED_LIBS` unset) |
| `-Druntime` | `true`, `false` | `false` | dispatch through a loaded table instead of a linked archive. Orthogonal to `-Dlinkage` |
| `-Dvalidate` | `true`, `false` | `true` | upstream's `BOX2D_VALIDATE` (`CMakeLists.txt:66`) |
| `-Ddisable-simd` | `true`, `false` | `false` | upstream's `BOX2D_DISABLE_SIMD` (`CMakeLists.txt:43`) |
| `-Davx2` | `true`, `false` | `false` | upstream's `BOX2D_AVX2` (`CMakeLists.txt:47`), applied only on x86/x86_64 and reported when ignored elsewhere |
| `-Doptimize`, `-Dtarget`, `-Dcpu` | standard | — | Zig's own |

`-Dtarget`, `-Dcpu` and `-Doptimize` come from `b.standardTargetOptions(.{})` and
`b.standardOptimizeOption(.{})` in the build graph, so `-Dcpu=baseline` — which
`package.nix` passes — is a real option here, not an unrecognised one.

A requested linkage is never substituted. When a selected `-Dtarget` cannot
carry the requested linkage, the build graph refuses at configure time —
`build.zig:1946-1949` prints `error: <reason>` and exits — rather than
producing a static archive and warning. `check` then leaves that one matrix
target out of the run and names it: `box2d: check: <triple> is NOT covered by
this run.`, followed by the reason. Under the default static linkage all six
matrix targets are still walked, including `wasm32-wasi`.

Options deliberately **not** offered, and why:

* **System mode.** There is none. It is not applicable to this SDK, not a
  satisfied gate.
* **`-Dprofile`.** Upstream's `BOX2D_PROFILE` links TracyClient, fetched from
  the network (`src/CMakeLists.txt:106-117`). This SDK downloads nothing.
* **`-Dsamples`.** The samples are graphical and fetch GLFW 3.4 and imgui
  v1.91.3 at build time (`samples/CMakeLists.txt:20-51`). They are carried for
  audit and are not built.
* **`-Dunit-tests`.** Upstream builds its unit tests by default; so does this
  SDK, unconditionally.

---

## 2. Two routes, one module

The public module is named **`box2d`**. Consumers write:

```zig
const box2d = @import("box2d");
```

Both routes expose the same nominal types. They are not two typesystems that get
cast between each other.

### Linked (default)

`c` is the translated module and calls go straight to the archive, so a linked
build needs no provider, no table and no `load` call. `rt` is imported beside it
for exactly two declarations — `LoadSource` and `LoadError` — so those are the
same types a caller names in either configuration. Calling `load` on a linked
build is a panic that says so: there is no library to load.

### Runtime-loaded (`-Druntime=true`)

`c` comes from `runtime/graph.zig`'s `createModule`, which owns the per-library
generated dispatch and descriptor. This branch links **no** archive and no
system library into the module, so the library has to exist somewhere at run
time and be named explicitly.

```zig
const box2d = @import("box2d");

pub fn main() !void {
    try box2d.load(.{ .path = "/absolute/path/to/libbox2d.so.3.1.1" });

    var world_def = box2d.defaultWorldDef();
    const ground = try box2d.createWorld(&world_def);

    // The fields are the translated b2BodyDef fields and the values are
    // upstream's own b2DefaultBodyDef ones.
    var body_def = box2d.defaultBodyDef();
    const body = try box2d.createBody(ground, &body_def);
    _ = body;
}
```

`-Druntime` selects the dispatch; `-Dlinkage` selects what this tree delivers
and installs, and keeps doing so in the row where the module links nothing:

| `-Dlinkage` | `-Druntime` | What the module calls | What the caller supplies |
| --- | --- | --- | --- |
| `static` | `false` | the compiled-in `libbox2d.a` | nothing |
| `dynamic` | `false` | the compiled-in `libbox2d.so.3` | nothing |
| `static` | `true` | the generated dispatch table | a loadable shared object; this build installs the archive and builds no provider for it |
| `dynamic` | `true` | the generated dispatch table | a loadable shared object; the one this build installs will do |

The third row is a configuration, not a degraded one. A provider is opened by
the platform loader — `dlopen` on the Unix family, `LoadLibraryExW` on Windows
— so it has to be a loadable object, and a static archive is not one. A
runtime-loaded build that delivers the static archive therefore needs a shared
object from somewhere else, and the graph neither builds one for that row nor
refuses it.

---

## 3. The runtime route

### What you call

| Declaration | Meaning |
| --- | --- |
| `pub fn load(source: LoadSource) LoadError!void` | The only way to obtain the table. On a linked build it panics, because there is nothing to load |
| `pub fn loadedSource() ?LoadSource` | The request that was loaded, or `null` before readiness |
| `pub const LoadSource` | `union(enum) { path: []const u8, system: []const u8 }` |
| `pub const LoadError` | `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad` |
| `pub const runtime_loaded: bool` | `true` in a `-Druntime` build, so a caller can branch at comptime |

In a linked build `LoadSource` and `LoadError` resolve to the `rt` core's own
types, so the same consumer source compiles against either configuration.

### The rules, stated because they are real

* **Explicit selection, no fallback.** `.path` is an absolute file path;
  `.system` is an explicit basename such as `"libbox2d.so.3"`, with no path
  component in it. A relative path, a system name carrying a separator, or a
  request containing a NUL byte is `InvalidSource`, refused before the platform
  is called at all. A `.path` that cannot be opened does **not** fall back to
  `.system`.
* **No owning handle.** There is no library object, no API view and no unload.
  The table is one immutable, process-lifetime table per configured module
  instance; a candidate that fails at any step is closed and leaves nothing
  published, so a partial table is never reachable.
* **Idempotent.** The same request twice succeeds and changes nothing. A
  *different* request after a successful load is `ProviderMismatch`, and the
  provider already chosen stays chosen.
* **No automatic retry.** A failed candidate leaves the module in its
  not-loaded state, and a retry is something you ask for by calling `load`
  again. A finished attempt is not discarded while other threads are still
  attached to it, so a failed attempt's waiters drain before a retry can begin.
* **Waiters observe their own attempt.** A call arriving while an attempt is in
  flight for the same request becomes a waiter on that attempt and returns
  *that* attempt's result, success or failure, never a later attempt's. A call
  for a different request while an attempt is in flight is `ProviderMismatch`:
  that attempt is committed to its provider, so there is nothing to wait for.
* **Same-thread reentry fails.** `load` called from a thread already inside an
  attempt returns `ReentrantLoad` rather than waiting for itself.
* **Panic before success.** Calling any ordinary Box2D function before a
  successful `load` panics in all four optimize modes, ReleaseFast and
  ReleaseSmall included, and the message names the function.
* **The loader trusts the native code.** It looks symbols up and releases them;
  that is not an ABI check. See section 5.

### One requirement a provider inherits from the consumer's optimize mode

`b2InternalAssertFcn` is declared under `#if !defined( NDEBUG ) || defined(
B2_ENABLE_ASSERT )` (`include/box2d/base.h:101-102`) and defined under the same
condition (`src/core.c:62-67`), so a `Debug` or `ReleaseSafe` consumer declares
it, the dispatch requires it, and a provider built with `NDEBUG` defined is
refused at load. A `ReleaseFast` or `ReleaseSmall` consumer does not declare it
and needs nothing of its provider beyond the rest.

That is a pairing requirement rather than a missing optional entry point, and
the difference is worth keeping: under `-Druntime` nothing is linked, so an
`extern` left direct would be an undefined symbol at link time instead of an
answer at load time. `runtime/graph.zig` therefore routes it and records the
pairing; the refusal at load is the honest outcome of a consumer asking for an
entry point its provider was not built with.

### One provider per consumer optimize mode

The pairing above is a build requirement on the provider, so the recipe is one
shared provider per consumer mode, each in its own prefix:

```sh
zig build install -Dlinkage=dynamic -Doptimize=Debug       --prefix <scratch>/box2d-shared-Debug
zig build install -Dlinkage=dynamic -Doptimize=ReleaseSafe --prefix <scratch>/box2d-shared-ReleaseSafe

BOX2D_TEST_PROVIDER=<scratch>/box2d-shared-Debug/lib/libbox2d.so \
  zig build test smoke -Druntime=true -Dlinkage=dynamic -Doptimize=Debug
```

`-Dlinkage=dynamic` is what makes an install produce something loadable: the
same install with `-Dlinkage=static` writes `libbox2d.a`, and a `-Druntime`
build links no library, so it still has to be handed a shared object. That is
why a `-Dlinkage=static -Druntime=true` gate needs a provider from a
`-Dlinkage=dynamic` build. `BOX2D_TEST_PROVIDER` is the one variable both the
tests and the smoke program read; the smoke program also accepts
`--provider <path>` on its own command line.

A `ReleaseFast` or `ReleaseSmall` consumer needs no provider of its own mode:
its table does not carry `b2InternalAssertFcn`, so a `Debug` or `ReleaseSafe`
provider loads for it as well. The reverse does not hold: a `Debug` or
`ReleaseSafe` consumer cannot use a provider built with `NDEBUG`, and every
`ReleaseFast` and `ReleaseSmall` build defines it.

When the pairing is wrong, `load` returns `MissingSymbol` and the loader prints
the library name and the symbol it wanted before closing the candidate:

```
box2d: this provider does not export b2InternalAssertFcn
```

That one line is the whole diagnosis: it means the provider was built with
`NDEBUG` and this consumer was not. Naming it weakens nothing — the symbol
stays a required table entry, the candidate is closed, and nothing is
published.

### Validation and the table

`runtime/library.zig`'s `Config(dispatch)` exposes `library_name = "box2d"`, the
`table`, the `symbols` and `optional_symbols` lists, the `sync` binding,
`tablePtr()`, `ready()`, `assign()`, `assignOptional()`, `assignMissing()` and
`validate(dst) ?[]const u8`. The optional list is empty in this SDK, and that is
a decision recorded in section 6 rather than an omission.

`validate` checks what can be checked without lying:

* `b2GetVersion().major == 3` — the major line, not a string comparison
* `b2GetLengthUnitsPerMeter() > 0` — the compiled-in unit scale is real

Synchronisation uses the unique prefix **`box2d_rt`**, declared in
`runtime/graph.zig`. It must stay unique per SDK: two SDKs sharing a prefix
would share a lock.

`runtime/graph.zig` declares `createModule(b, translate, target, optimize)` and
`createCoreModule(b, target, optimize)`. The delivery role calls
`createModule` **only** for `-Druntime`, and `createCoreModule` **only** for the
linked branch's `rt` import. Never both.

`runtime/loader.zig`, `generate.zig`, `sync.c` and `sync.h` are the driver's
shared core and are not the API role's files.

---

## 4. Typed surface

The facade renames upstream's C names by one rule:

> drop the `b2` prefix, convert to camelCase; the entity's `id` is the first
> parameter; parameters are `snake_case`.

`b2CreateBody` becomes `createBody(world_id, body_def)`. `b2Body_SetLinearVelocity`
becomes `bodySetLinearVelocity(body_id, linear_velocity)`. Every declaration
below is documented at its definition in `zig/root.zig`.

### Errors

```zig
pub const CreateError = error{ WorldLimitReached, WorldLocked, HullNotConvex };
```

`CreateError` is the complete set of failures the creation calls can return, and
each call reaches only the tags its own check can produce: `createWorld` only
`WorldLimitReached`, `createBody`, the four `create*Shape` functions and
`createChain` only `WorldLocked`, and `computeHull` only `HullNotConvex`. The
one shared set is the vocabulary this module speaks in; it is not a claim that
one call has three ways to fail. `b2CreateWorld` returns the null world id
rather than failing.

`WorldLocked` is what a shape-creation call reports for a null upstream return,
and for a segment upstream returns null in two distinct cases: a locked world
(`src/shape.c:172-176`), and a degenerate segment whose two points are at or
below `B2_LINEAR_SLOP * B2_LINEAR_SLOP` apart (`src/shape.c:217-227`,
`src/constants.h:23`). The facade cannot tell those two apart and reports one
error for both.

Which of the two a caller actually sees depends on the optimize mode, because
the degenerate case asserts on its way out. `B2_ASSERT( false )` is live
wherever `NDEBUG` is undefined (`include/box2d/base.h:101-109`), the default
assert handler returns non-zero (`src/core.c:46-52`), and `B2_BREAKPOINT` is
`__builtin_trap()` (`include/box2d/base.h:91-99`): in `Debug` and `ReleaseSafe`
the process traps on `SIGILL` and no error is returned at all. In
`ReleaseFast` and `ReleaseSmall` the assert is compiled out
(`include/box2d/base.h:111`), the null id comes back, and this facade reports
`error.WorldLocked`. A caller that wants the refusal to be an error in every
mode installs an assert hook that returns zero (`b2SetAssertFcn`,
`src/core.c:56-60`) — the hook's return value is what decides whether
`B2_BREAKPOINT` runs (`include/box2d/base.h:106-107`) — and then all four modes
report `error.WorldLocked`.

`createCapsuleShape` is the constructor that degrades instead of refusing:
coincident centres become a circle (`src/shape.c:199-209`), so a capsule never
reaches the segment refusal.

### Constants

`max_polygon_vertices`, `default_category_bits`, `default_mask_bits`, `pi`,
`hash_init`, `vec2_zero`, `rot_identity`, `transform_identity`

### IDs

`WorldId`, `BodyId`, `ShapeId`, `ChainId`, `JointId`; the null handles
`null_world_id`, `null_body_id`, `null_shape_id`, `null_chain_id`,
`null_joint_id`; `isNullId`, `idsEqual`, and the pack/unpack pairs
`storeWorldId`/`loadWorldId`, `storeBodyId`/`loadBodyId`,
`storeShapeId`/`loadShapeId`, `storeChainId`/`loadChainId`,
`storeJointId`/`loadJointId`.

The null handles keep upstream's snake_case spelling because they are values
rather than calls, and `idsEqual` carries upstream's own limitation rather than
fixing it: `include/box2d/id.h:89` says the comparison does not work for
`b2WorldId`, and this facade does not paper over that. `isNullId` is the one
question that is safe across all five kinds.

### Base

`getVersion`, `setAllocator`, `getByteCount`, `setAssertFcn`, `getTicks`,
`getMilliseconds`, `getMillisecondsAndReset`, `yield`, `hash`

### Defaults

`defaultWorldDef`, `defaultBodyDef`, `defaultFilter`, `defaultQueryFilter`,
`defaultSurfaceMaterial`, `defaultShapeDef`, `defaultChainDef`,
`defaultDistanceJointDef`, `defaultMotorJointDef`, `defaultMouseJointDef`,
`defaultFilterJointDef`, `defaultPrismaticJointDef`, `defaultRevoluteJointDef`,
`defaultWeldJointDef`, `defaultWheelJointDef`, `defaultExplosionDef`,
`defaultDebugDraw`

### Math

`vec2`, `circle`, `makeRot`, `computeCosSin`, `atan2`, `computeAngularVelocity`,
`computeRotationBetweenUnitVectors`, `dot`, `cross`, `crossVS`, `crossSV`, `add`,
`sub`, `neg`, `mul`, `mulSV`, `mulAdd`, `mulSub`, `absVec`, `minVec`, `maxVec`,
`clampVec`, `lerpVec`, `length`, `lengthSquared`, `distance`, `distanceSquared`,
`normalize`, `isNormalized`, `getLengthAndNormalize`, `leftPerp`, `rightPerp`,
`rotateVector`, `invRotateVector`, `rotAngle`, `rotXAxis`, `rotYAxis`,
`relativeAngle`, `normalizeRot`, `nLerp`, `mulRot`, `invMulRot`, `unwindAngle`,
`integrateRotation`, `transformPoint`, `invTransformPoint`, `mulTransforms`,
`invMulTransforms`, `mulMV`, `getInverse22`, `solve22`, `aabbContains`,
`aabbCenter`, `aabbExtents`, `aabbUnion`, `aabbOverlaps`, `makeAabb`,
`planeSeparation`, `springDamper`, `clampFloat`, `maxFloat`, `minFloat`,
`absFloat`, `clampInt`, `maxInt`, `minInt`, `absInt`, `setLengthUnitsPerMeter`,
`getLengthUnitsPerMeter`, `isValidFloat`, `isValidVec2`, `isValidRotation`,
`isValidAabb`, `isValidPlane`

There is no `makeTransform`: no `B2_API` or `B2_INLINE` function of that name
exists in any of the six public headers at this pin, so there is nothing here to
wrap. `makeAabb` is `b2MakeAABB`, the one inline reached through the bridge
described in section 6.

### Geometry

`makePolygon`, `makeOffsetPolygon`, `makeOffsetRoundedPolygon`, `makeSquare`,
`makeBox`, `makeRoundedBox`, `makeOffsetBox`, `makeOffsetRoundedBox`,
`transformPolygon`, `makeProxy`, `makeOffsetProxy`, `computeHull`, `validateHull`,
`computeCircleMass`, `computeCapsuleMass`, `computePolygonMass`,
`computeCircleAabb`, `computeCapsuleAabb`, `computePolygonAabb`,
`computeSegmentAabb`, `pointInCircle`, `pointInCapsule`, `pointInPolygon`,
`rayCastCircle`, `rayCastCapsule`, `rayCastSegment`, `rayCastPolygon`,
`shapeCastCircle`, `shapeCastCapsule`, `shapeCastSegment`, `shapeCastPolygon`,
`isValidRay`, `segmentDistance`, `shapeDistance`, `shapeCast`, `timeOfImpact`,
`getSweepTransform`

### Collision manifolds

`collideCircles`, `collideCapsuleAndCircle`, `collideSegmentAndCircle`,
`collidePolygonAndCircle`, `collideCapsules`, `collideSegmentAndCapsule`,
`collidePolygonAndCapsule`, `collidePolygons`, `collideSegmentAndPolygon`,
`collideChainSegmentAndCircle`, `collideChainSegmentAndCapsule`,
`collideChainSegmentAndPolygon`

### Character mover

`solvePlanes`, `clipVector`

### Dynamic tree

`dynamicTreeCreate`, `dynamicTreeDestroy`, `dynamicTreeCreateProxy`,
`dynamicTreeDestroyProxy`, `dynamicTreeMoveProxy`, `dynamicTreeEnlargeProxy`,
`dynamicTreeSetCategoryBits`, `dynamicTreeGetCategoryBits`, `dynamicTreeQuery`,
`dynamicTreeRayCast`, `dynamicTreeShapeCast`, `dynamicTreeHeight`,
`dynamicTreeAreaRatio`, `dynamicTreeRootBounds`, `dynamicTreeProxyCount`,
`dynamicTreeRebuild`, `dynamicTreeByteCount`, `dynamicTreeUserData`,
`dynamicTreeAabb`, `dynamicTreeValidate`, `dynamicTreeValidateNoEnlarged`

### World

`createWorld`, `destroyWorld`, `worldIsValid`, `worldStep`, `worldDraw`,
`worldBodyEvents`, `worldSensorEvents`, `worldContactEvents`, `worldOverlapAabb`,
`worldOverlapShape`, `worldCastRay`, `worldCastRayClosest`, `worldCastShape`,
`worldCastMover`, `worldCollideMover`, `worldEnableSleeping`,
`worldIsSleepingEnabled`, `worldEnableContinuous`, `worldIsContinuousEnabled`,
`worldSetRestitutionThreshold`, `worldGetRestitutionThreshold`,
`worldSetHitEventThreshold`, `worldGetHitEventThreshold`,
`worldSetCustomFilterCallback`, `worldSetPreSolveCallback`, `worldSetGravity`,
`worldGetGravity`, `worldExplode`, `worldSetContactTuning`,
`worldSetMaximumLinearSpeed`, `worldGetMaximumLinearSpeed`,
`worldEnableWarmStarting`, `worldIsWarmStartingEnabled`,
`worldGetAwakeBodyCount`, `worldGetProfile`, `worldGetCounters`,
`worldSetUserData`, `worldGetUserData`, `worldSetFrictionCallback`,
`worldSetRestitutionCallback`, `worldDumpMemoryStats`,
`worldRebuildStaticTree`, `worldEnableSpeculative`

### Borrowed event slices

`bodyMoveEvents`, `sensorBeginEvents`, `sensorEndEvents`,
`contactBeginEvents`, `contactEndEvents`, `contactHitEvents`

These are **zero-copy slices into the world's event buffers**, valid until the
next `worldStep` on that world. Copy anything you need to keep.

Events are opt-in per shape, and upstream's default is off:
`b2ShapeDef.enableSensorEvents` is "False by default, even for sensors"
(`include/box2d/types.h:385-386`), and `src/sensor.c:65-67` skips an overlap
whose *other* shape has not opted in. A sensor visitor therefore has to set the
flag on its own shape as well as on the sensor's, or the overlap is never
reported — `tests.zig` and `consumer/src/main.zig` both do. `b2ChainDef` carries
the same flag for chains (`types.h:453-454`), and contact, pre-solve and hit
events have their own `enable*Events` fields on the same struct. Body move
events are not gated this way: `src/solver.c:1249-1250` sizes the array to the
awake body count of the step that just ran.

### Body

`createBody`, `destroyBody`, `bodyIsValid`, `bodyType`, `bodySetType`,
`bodySetName`, `bodyName`, `bodySetUserData`, `bodyGetUserData`, `bodyPosition`,
`bodyRotation`, `bodyTransform`, `bodySetTransform`, `bodyLocalPoint`,
`bodyWorldPoint`, `bodyLocalVector`, `bodyWorldVector`, `bodyLinearVelocity`,
`bodySetLinearVelocity`, `bodyAngularVelocity`, `bodySetAngularVelocity`,
`bodySetTargetTransform`, `bodyLocalPointVelocity`, `bodyWorldPointVelocity`,
`bodyApplyForce`, `bodyApplyForceToCenter`, `bodyApplyTorque`,
`bodyApplyLinearImpulse`, `bodyApplyLinearImpulseToCenter`,
`bodyApplyAngularImpulse`, `bodyMass`, `bodyRotationalInertia`,
`bodyLocalCenterOfMass`, `bodyWorldCenterOfMass`, `bodySetMassData`,
`bodyMassData`, `bodyApplyMassFromShapes`, `bodySetLinearDamping`,
`bodyGetLinearDamping`, `bodySetAngularDamping`, `bodyGetAngularDamping`,
`bodySetGravityScale`, `bodyGetGravityScale`, `bodyIsAwake`, `bodySetAwake`,
`bodyEnableSleep`, `bodyIsSleepEnabled`, `bodySetSleepThreshold`,
`bodyGetSleepThreshold`, `bodyIsEnabled`, `bodyDisable`, `bodyEnable`,
`bodySetFixedRotation`, `bodyIsFixedRotation`, `bodySetBullet`, `bodyIsBullet`,
`bodyEnableContactEvents`, `bodyEnableHitEvents`, `bodyWorld`, `bodyShapeCount`,
`bodyShapes`, `bodyJointCount`, `bodyJoints`, `bodyContactCapacity`,
`bodyContactData`, `bodyComputeAabb`

### Shape

`createCircleShape`, `createCapsuleShape`, `createPolygonShape`,
`createSegmentShape`, `destroyShape`, `shapeIsValid`, `shapeType`, `shapeBody`,
`shapeWorld`, `shapeIsSensor`, `shapeSetUserData`, `shapeGetUserData`,
`shapeSetDensity`, `shapeDensity`, `shapeSetFriction`, `shapeFriction`,
`shapeSetRestitution`, `shapeRestitution`, `shapeSetMaterial`, `shapeMaterial`,
`shapeSetSurfaceMaterial`, `shapeSurfaceMaterial`, `shapeFilter`,
`shapeSetFilter`, `shapeEnableSensorEvents`, `shapeAreSensorEventsEnabled`,
`shapeEnableContactEvents`, `shapeAreContactEventsEnabled`,
`shapeEnablePreSolveEvents`, `shapeArePreSolveEventsEnabled`,
`shapeEnableHitEvents`, `shapeAreHitEventsEnabled`, `shapeTestPoint`,
`shapeRayCast`, `shapeCircle`, `shapeSegment`, `shapeChainSegment`, `shapeCapsule`,
`shapePolygon`, `shapeSetCircle`, `shapeSetCapsule`, `shapeSetSegment`,
`shapeSetPolygon`, `shapeParentChain`, `shapeContactCapacity`, `shapeContactData`,
`shapeSensorCapacity`, `shapeSensorOverlaps`, `shapeAabb`, `shapeMassData`,
`shapeClosestPoint`

### Chain

`createChain`, `destroyChain`, `chainWorld`, `chainSegmentCount`,
`chainSegments`, `chainSetFriction`, `chainFriction`, `chainSetRestitution`,
`chainRestitution`, `chainSetMaterial`, `chainMaterial`, `chainIsValid`

### Joints

Base: `destroyJoint`, `jointIsValid`, `jointType`, `jointBodyA`, `jointBodyB`,
`jointWorld`, `jointSetLocalAnchorA`, `jointLocalAnchorA`,
`jointSetLocalAnchorB`, `jointLocalAnchorB`, `jointReferenceAngle`,
`jointSetReferenceAngle`, `jointSetLocalAxisA`, `jointLocalAxisA`,
`jointSetCollideConnected`, `jointCollideConnected`, `jointSetUserData`,
`jointGetUserData`, `jointWakeBodies`, `jointConstraintForce`,
`jointConstraintTorque`, `jointLinearSeparation`, `jointAngularSeparation`,
`jointConstraintTuning`, `jointSetConstraintTuning`, `ConstraintTuning`.

Creation: `createDistanceJoint`, `createMotorJoint`, `createMouseJoint`,
`createFilterJoint`, `createPrismaticJoint`, `createRevoluteJoint`,
`createWeldJoint`, `createWheelJoint`, plus every
`b2<Type>Joint_{Set,Get,Is,Enable,Are}…` declared in `include/box2d/box2d.h`
under the same naming rule.

### Callbacks

`AllocFcn`, `FreeFcn`, `AssertFcn`, `TaskCallback`, `EnqueueTaskCallback`,
`FinishTaskCallback`, `FrictionCallback`, `RestitutionCallback`, `CustomFilterFn`,
`PreSolveFn`, `OverlapResultFn`, `CastResultFn`, `PlaneResultFn`,
`TreeQueryCallbackFn`, `TreeRayCastCallbackFn`, `TreeShapeCastCallbackFn`

All sixteen are aliases of the translated typedefs, not re-declared shapes. A
callback that upstream declares `B2_INLINE` and never stores stays a plain
function pointer; nothing is wrapped in a struct behind your back.

Nullability is not uniform across them. The `?*const` on the eight query entry
points is not an invitation to pass null: upstream dereferences every one of
them unguarded (`src/dynamic_tree.c:1146`, `:1245`, `:1375`;
`src/world.c:2067`, `:2143`, `:2208`, `:2336`, `:2505`), so a null query
callback is a caller precondition rather than a counters-only mode.
`worldSetFrictionCallback` and `worldSetRestitutionCallback` are the two that do
accept null, because upstream reads null there as "restore the default"
(`src/world.c:1913-1919`, `:1931-1937`).

### Value types

`Vec2`, `CosSin`, `Rot`, `Transform`, `Mat22`, `Aabb`, `Plane`, `Version`,
`RayCastInput`, `ShapeProxy`, `ShapeCastInput`, `CastOutput`, `MassData`,
`Circle`, `Capsule`, `Polygon`, `Segment`, `ChainSegment`, `Hull`,
`SegmentDistanceResult`, `SimplexCache`, `DistanceInput`, `DistanceOutput`,
`SimplexVertex`, `Simplex`, `ShapeCastPairInput`, `Sweep`, `TOIInput`,
`TOIState`, `TOIOutput`, `ManifoldPoint`, `Manifold`, `DynamicTree`, `TreeStats`,
`PlaneResult`, `CollisionPlane`, `PlaneSolverResult`, `WorldDef`, `BodyType`,
`BodyDef`, `Filter`, `QueryFilter`, `ShapeType`, `SurfaceMaterial`, `ShapeDef`,
`ChainDef`, `Profile`, `Counters`, `JointType`, `DistanceJointDef`,
`MotorJointDef`, `MouseJointDef`, `FilterJointDef`, `PrismaticJointDef`,
`RevoluteJointDef`, `WeldJointDef`, `WheelJointDef`, `ExplosionDef`,
`SensorBeginTouchEvent`, `SensorEndTouchEvent`, `SensorEvents`,
`ContactBeginTouchEvent`, `ContactEndTouchEvent`, `ContactHitEvent`,
`ContactEvents`, `BodyMoveEvent`, `BodyEvents`, `ContactData`, `DebugDraw`,
`RayResult`, `HexColor`

---

## 5. External ABI: what actually has to match

Symbol presence and a version string are **not** compatibility proof. These are
the boundaries a provider has to satisfy.

**Scalar and layout.** Every value type above is the translated C struct,
returned and passed by value under the platform C ABI. `b2GetVersion` returns
`b2Version` by value (three `int`s, `base.h:69-84`). `b2Vec2` and friends are
two-float aggregates passed by value. `b2Transform`/`b2Mat22` likewise. A
consumer and a provider must agree on the C ABI for the target — SysV on
x86-64, the Darwin variant on arm64, the Microsoft variant on x86-64 Windows.

**Callbacks.** Sixteen function-pointer types cross the boundary. They are
called back from inside the library, on the thread that called the Box2D
function.

**Config.** `BOX2D_VALIDATE`, `BOX2D_DISABLE_SIMD`, `BOX2D_AVX2`,
`box2d_EXPORTS` and `BOX2D_DLL` are compile-line macros. Reading the six public
headers shows **no struct field and no function signature inside them is
conditional on any of these macros** — the only conditional declarations in the
whole public surface are the export macros themselves (`base.h:11-23`),
`B2_BREAKPOINT` (`base.h:91-99`) and `b2InternalAssertFcn`/`B2_ASSERT`
(`base.h:101-112`). So `-Dvalidate` and `-Ddisable-simd` change behaviour and
performance, not layout.

**One genuine declaration/definition mismatch.** `b2InternalAssertFcn` is
*declared* only when `NDEBUG` is undefined or `B2_ENABLE_ASSERT` is defined
(`base.h:101`), but `src/core.c:62-67` defines it whenever either is true. With
`NDEBUG` defined and no `B2_ENABLE_ASSERT`, the library exports a symbol the
header does not declare. It is harmless for a consumer that never calls it; it
matters to any tool that diffs the header's declared externs against the
library's exports.

**Allocator.** `b2SetAllocator` installs a paired `b2AllocFcn`/`b2FreeFcn` for
the whole library, process-wide (`base.h:60`, `core.c:78-88`). `b2GetByteCount`
reports the running total. Memory that crosses into either of those belongs
to the C allocator, **not** to a Zig allocator, and the test framework cannot
supply a leak oracle for it. `b2WorldDef` carries no allocator of its own: its
members are the seventeen of `types.h:81-143`, and the per-world allocation
whose lifetime is the world's is upstream's own arena, created and destroyed
inside `b2CreateWorld`/`b2DestroyWorld` (`src/world.c:131`, `:348`) and drawn
from the process-wide pair above.

**Lifetime.** `b2DestroyWorld` destroys the world; `b2DestroyBody`, shapes,
chains and joints must be reached while their world is alive. Event slices are
borrowed until the next step. Nothing in Box2D is reference-counted and nothing
is freed for you.

**Exported data.** There is none. Every `B2_API` entity in the six public headers
is a function. The two file-scope globals in the core, `b2AssertHandler`
(`src/core.c:54`) and `b2_byteCount` (`src/core.c:81`), carry no export
declaration and upstream compiles with `CMAKE_C_VISIBILITY_PRESET hidden`
(`src/CMakeLists.txt:74`), so they are library-internal. A runtime table for this
SDK therefore has no data entries whose address must stay live in the provider.

**Libc.** Box2D's headers pull in `stdint.h`, `stddef.h`, `stdbool.h`,
`float.h` and `<math.h>` (`include/box2d/math_functions.h:9`). Zig 0.16's
`translate-c` emits the C library declarations those headers carry;
`runtime/graph.zig` classifies those as libc noise and leaves them direct rather
than routing them through the table. Box2D itself calls only libc — including its
math part: `include/box2d/math_functions.h:9` includes `<math.h>` and the scalar
paths call `sinf`, `cosf` and `atan2f`, which live in libm on glibc and musl.
That is why the installed `box2d.pc` carries `-lm` on the targets whose core
system libraries include it — Linux and the BSD/illumos/Solaris family — and
not on macOS, the iOS family or Windows. A static consumer's link line is the
only place libm can come from, which is also why there is no `Libs.private`.

That classification is a decision of its own, separate from the library's own
declarations, and it is made against the names the translation actually
produced rather than the subset the typed facade happens to call.
`runtime/graph.zig` spells the C library math surface as bases — the C23 and
C99 `<math.h>` clause, the legacy Bessel, gamma and scaling names glibc still
declares, the classification macros, the C23 `nextup`/`getpayload` family, and
the leading-underscore spellings the Microsoft C runtime declares — and expands
each base over the empty and `__` prefixes and the empty, `f`, `l`, `f16`,
`f32`, `f64`, `f128`, `f16x`, `f32x`, `f64x`, `f128x` and `ieee128` suffixes,
with the `_r` re-entrant spelling kept after the suffix.

The direction of the error is asymmetric, and it is what decides whether a load
succeeds:

* **Over-listing costs nothing.** A name no header declares is never looked up,
  so a superset is inert.
* **Under-listing breaks the load.** An `extern` the generator does not
  recognise is routed, which makes the *provider* responsible for exporting it —
  and a `.so` that did not export `sinf` fails `dlsym`.

No Box2D name is in that space: every one begins `b2` or `B2`, and no base does.
So no provider built from these headers has to export a single C library
function to satisfy a load.

---

## 6. The raw `c` route

The complete translated surface stays reachable, and it is the same module:

```zig
const box2d = @import("box2d");

const world = box2d.c.b2CreateWorld(&def);
```

In a `-Druntime` build `c` is the generated dispatch: it re-exports the
translated type and constant namespace unchanged and additionally carries
`c.load`, `c.loadedSource`, `c.LoadSource`, `c.LoadError` and
`c.runtime_loaded`. Nothing is lost by using the typed facade, and nothing is
lost by not using it.

### Where the extern surface comes from

All six public headers, nothing else. They are the six `BOX2D_API_FILES`
entries of `src/CMakeLists.txt:63-70`, and `zig/translate.h` includes each whole
instead of restating a declaration, so the translated set is the installed set:

| Header | What it contributes |
| --- | --- |
| `include/box2d/base.h` | the allocator, version, tick, assert-hook and hash entry points, plus the one conditional declaration, `b2InternalAssertFcn` |
| `include/box2d/id.h` | no externs: every `b2Store*`/`b2Load*` function is `B2_INLINE` |
| `include/box2d/collision.h` | the geometry, cast, manifold and dynamic-tree `B2_API` groups, the tree callbacks among them |
| `include/box2d/math_functions.h` | the scalar-math `B2_API` functions, and 63 of the 73 `B2_INLINE` bodies |
| `include/box2d/types.h` | the `b2Default*` definitions and the definition structs |
| `include/box2d/box2d.h` | the world, body, shape, chain and joint groups |

Nothing is `provider_optional` and nothing is `provider_excluded`: every
`B2_API` declaration in those six headers has a definition in `src/`, so an
absent one is a refused provider rather than a half-used one. The one
conditional declaration is `b2InternalAssertFcn`, described in section 5 and,
as a provider requirement, in section 3.

### The one inline Zig cannot translate

The six headers declare 73 `B2_INLINE` functions between them: 63 in
`math_functions.h`, 10 in `id.h`, and none in `base.h`, `box2d.h`,
`collision.h` or `types.h`. `include/box2d/base.h:33` makes `B2_INLINE` `static
inline` in C, so upstream never needs a symbol for any of them: each is a
private copy in every translation unit that includes the header, and
`src/world.c:2159` is `b2MakeAABB`'s only caller.

Zig 0.16's `translate-c` compiles 72 of those 73 bodies into the `c` module.
The one it cannot is `b2MakeAABB` (`math_functions.h:625`): its first statement
is `B2_ASSERT( count > 0 )` (`:627`), `B2_ASSERT` calls `B2_BREAKPOINT`
(`base.h:103-109`), and `B2_BREAKPOINT` is `__builtin_trap()` (`base.h:94`). The
translation reports the trap as unimplemented and demotes the whole function to
an `extern` declaration — a declaration of a C symbol no archive in this package
contains, which is a link-time hole for every Zig caller of it, including this
package's own `makeAabb`.

`build_support/box2d_inline_bridge.c` is what fills it, and it is the whole of
it: that file and no other is the complete list for `zig/translate.h` at this
pin. It renames `b2MakeAABB` to a private name around one `#include` of the
header, undoes the rename immediately, and exports one `B2_API` definition that
calls what the header's own text defined. The private name is `static inline`,
so it occupies no symbol-table entry, and the body is upstream's bytes at
upstream's line numbers — not a second algorithm free to drift from the header,
which is the failure this file exists to remove.

`build.zig` compiles it into the core module itself, beside the 35 upstream
translation units, so the same `-D` set, the same libm, the same `-std=gnu17`
and `-ffp-contract=off` apply, and one definition serves all three artifacts:
the static archive, the shared object, and the second static archive a
`-Dlinkage=dynamic` build compiles for upstream's own test suite. It is
fork-authored, it lives outside every upstream tree, and it is the only C
translation unit in this package that upstream does not ship.

---

## 7. The consumer package

`consumer/` is a separate Zig package with its own `build.zig` and
`build.zig.zon`. It takes a path dependency on the SDK root and consumes
`dep.module("box2d")`:

```zig
const box2d = @import("box2d");
```

```sh
cd consumer && zig build run          # linked build
cd consumer && zig build run -- --provider /abs/path/to/libbox2d.so.3.1.1
BOX2D_TEST_PROVIDER=/abs/path/to/libbox2d.so.3.1.1 zig build run
```

A runtime consumer needs a provider; a linked one does not.

It declares every option the SDK owns and forwards each one to the dependency,
so passing one to the consumer configures the library rather than being
accepted and dropped: `-Dtarget`, `-Dcpu`, `-Doptimize` (`standardTargetOptions`
and `standardOptimizeOption`), `-Dlinkage`, `-Druntime`, `-Dvalidate`,
`-Ddisable-simd` and `-Davx2` (each declared in `consumer/build.zig` with
`b.option`). `-Dcpu` is a real option there for the reason section 1 gives:
`standardTargetOptions` reads the CPU model from its own `-D`
(`lib/std/Build.zig:1473-1491`), and the model is
what `package.nix:117` passes. None of the five Box2D options carries a default
in `consumer/`: an option left unset is not recorded as a dependency argument at
all (`lib/std/Build.zig:435`, `:569-581`), so the library's own default stays in
charge and the tree holds one answer per option rather than two. That is what
makes `zig build consumer -Ddisable-simd=true` and
`zig build consumer -Davx2=true` proofs of a non-default Box2D rather than
re-runs of the default one. From the SDK root, `zig build consumer` reaches the
same package and forwards the same five, plus `-Dtarget` and `-Dcpu`, from
`runConsumer` in `build.zig`. That helper also hands the nested build each of
the five executor switches that is on, `-j8`, `--summary all`, the local cache
under a `consumer` subdirectory, and the global cache the caller chose. A
`--prefix` other than this build's default `zig-out` goes across as well, made
absolute first, so the nested build writes outside the package instead of into
`consumer/zig-out`. The caller's own arguments follow behind `--`, and the
`run` step in `consumer/build.zig` hands them to the program, so
`zig build consumer -Druntime=true -- --provider <path>` reaches
`consumer/src/main.zig`.

The nested sub-command is `run` when an enabled executor can execute the
resolved target and `install` when none can, and an installed consumer is
`<prefix>/bin/box2d-consumer`: build-only evidence, not a run.

---

## 8. Exact commands the driver runs

From the SDK root, with the host scratch policy sourced:

```sh
. "$HOME/.local/lib/host-scratch.sh" || exit 1
CACHE="$HOST_SCRATCH_ROOT/cache/foundation-libs/box2d"
FLAGS="-j8 --summary all --cache-dir $CACHE/host"

# linked, all four optimize modes
zig build $FLAGS
for mode in Debug ReleaseSafe ReleaseFast ReleaseSmall; do
  zig build test -Doptimize=$mode $FLAGS
done
zig build smoke $FLAGS
zig build upstream-test $FLAGS

# shared
zig build -Dlinkage=dynamic --prefix "$HOST_SCRATCH_ROOT/scratch/box2d-install" $FLAGS
zig build test -Dlinkage=dynamic $FLAGS

# optional native settings, both at upstream's own defaults' opposites
zig build -Ddisable-simd=true $FLAGS
zig build -Davx2=true $FLAGS

# compile-only target matrices
zig build check $FLAGS
zig build check -Dlinkage=dynamic $FLAGS   # five targets; the sixth is named, not silently dropped

# runtime-loading branch (its own gates belong to the API role; the build graph
# only switches the module wiring)
zig build smoke -Druntime=true $FLAGS
zig build -Dlinkage=dynamic -Druntime=true $FLAGS

# consumer, upstream test entry on its own, integrity, matrix
zig build consumer $FLAGS
zig build consumer -Ddisable-simd=true $FLAGS   # the same proof, non-default Box2D
zig build consumer -Davx2=true $FLAGS
sha256sum -c UPSTREAM.sha256
"$HOME/.local/bin/cross-test" --jobs 8 --build-jobs 8
```

`zig build test` runs this fork's `tests.zig` **and** upstream's own
`test/main.c`. `zig build upstream-test` runs upstream's entry alone, which is
what tells the two apart. `cross-test` reads `cross-test.profile.sh` with
`CROSS_BUILD_STEP=test`.

### What has actually been run

Four runs against this tree's own build graph, on this host, and nothing else
before the packaging block below:

* `zig build smoke test` on the linked branch. Upstream's full C suite passed,
  this package's 14 SDK tests passed, and the smoke program ran and held every
  value it derives for itself.
* `zig build test smoke install`, eight cells in the native final matrix on
  2026-10-04: each of the four optimize modes in both linkages, every one with
  `-Druntime=false` because that run is native and linked only and nothing was
  opened through the platform loader. All eight passed. The four static cells
  printed `Build Summary: 27/27 steps succeeded; 14/14 tests passed` and the
  four dynamic cells `29/29 steps succeeded; 14/14 tests passed`, each with
  `test success`, `smoke success` and 77 lines of program output. Each static
  cell installed 15 files and each dynamic cell 17, both with the six public
  headers, `box2d.pc` and the six licence and upstream files, and with
  `lib/libbox2d.a` or `lib/libbox2d.so`, `lib/libbox2d.so.3` and
  `lib/libbox2d.so.3.1.1` respectively.
* `zig build smoke -Druntime=true -Dlinkage=static -- --provider …` on the
  runtime-loaded branch with a static delivery, against a Box2D shared object
  installed by an earlier `-Dlinkage=dynamic` build of this tree into a scratch
  prefix outside the repository and named explicitly on the command line
  (`local://foundation-contract-box2d-current-canonical-runtime-static-real-provider-smoke.log`,
  6/6 build steps, and the smoke program ran). That command builds neither the
  delivered artifact nor the provider, and it says nothing about the same branch
  with a shared delivery.
* `zig build consumer`, nine cases in the driver's nested-delivery proof on
  2026-10-04. The four routes — a static and a dynamic delivery, each with the
  linked and the runtime-loaded dispatch — ran twice, once with the caller's
  `-Dtarget` and `-Dcpu` omitted and once with them named, and a ninth case
  handed the loaded route no provider. Eight exited 0 with the consumer program
  reporting that every value matched the expectation derived for it; the ninth
  exited 1 and printed the missing-provider refusal `consumer/src/main.zig`
  declares. Every nested command line carried `-j8`, `--summary all`, both
  caches and the caller's `--prefix`, and no case resolved a prefix into this
  repository. The loaded cases named the provider with `--provider` after `--`
  while every provider variable was absent from the child, so each one came
  from the command line and not from a variable. `README.md` §3 carries the same
  nine cases as its `Consumer package` row, and this is the bound of it: `Debug`
  only, the host target and one explicitly named `x86_64-linux-gnu` with
  `baseline` only. As a bound on that run alone it settles nothing about a
  filtered fetched package, `check`, `cross-test` or the devenv entries, which
  are covered by the two runs below and, for the devenv entries, not at all.

Two later gates widened this. `zig build check` over the six declared compile
targets exited 0 on 2026-10-05 with `Build Summary: 61/61 steps succeeded` and
no failing step (`baseline-box2d-check`, run `20261005T014547Z-797a73f2`). It
compiles and links and runs nothing.

`cross-test` over the published 53-target table exited 1 on 2026-10-04 (run
`20261004T221720228710Z-45046`, source stamp `49e9048898…` unchanged across the
run): **6 pass, 31 build-only, 5 build failures, 11 run failures**. Two NetBSD
cells fail in `translate-c` on `__int128_t` from the compiler's own vendored
header; three big-endian Linux cells hit the 3600 s build timeout; five cells
fail inside upstream's own C determinism suite; and six cells fail only on the
Zig-to-C boundary, each after the same log printed `All Box2D tests passed!` for
the pure-C run. `README.md` §3 carries the per-cell names and the exact
diagnostics.

What the block above still has not covered: the `smoke` runtime-loaded branch
with a shared delivery, that same branch in any mode other than `Debug`, a
standalone `zig build upstream-test`, a direct `cd consumer` entry, a filtered
fetched package, and `check` in either linkage. Both runs above hold one source
stamp each, so they are evidence about the tree at that stamp and not about any
build-graph, header or helper edit made after it. `README.md` §3 carries the same
split as a matrix, and neither document claims a cell the other does not.

Packaging, from the same directory:

```sh
nix build --no-link --print-out-paths "path:$PWD#static"
nix build --no-link --print-out-paths "path:$PWD#shared"
# or, inside the canonical shell:
devenv build outputs.static
devenv build outputs.shared
```

The flake's single input is locked: `flake.lock` pins `nixpkgs` to revision
`c7def046b9a883d46974757852106483d741586f` with a `narHash`, the revision
`flake.nix:8-9` names in `inputs.nixpkgs.url`. There is no `devenv.lock` in this
tree, and `devenv.yaml:31` pins its own input directly, because devenv resolves
through a different input from the one the flake names. That input is evaluated
as a flake, so `devenv.yaml` carries no `flake: false`; `README.md` §4 states
where each lock sits in the packaging story and what each task or script runs.

The two `nix build` lines above are the observed ones. The driver ran them as
`nix build --no-write-lock-file --no-link --json --cores 8 --max-jobs 2
path:<sdk>#static path:<sdk>#shared` from a scratch directory rather than from
this one: exit 0, two `drvPath`s and two realised store outputs, 2026-10-04
(`nix-acceptance-20261004T175328Z`, `box2d-nix-build.log`). Both build
`-Doptimize=ReleaseSafe`, which is `package.nix:116`. The two `devenv build`
lines are unrun, and no devenv gate of any kind has been re-run since
`devenv.yaml` changed.

---

## 9. The vendored enkiTS, and what it is not

`test/test_determinism.c:4` and `benchmark/main.c:8` include
`TaskScheduler_c.h`, from enkiTS. Upstream fetches it from the network with an
unpinned `GIT_TAG master` (`CMakeLists.txt:88-95`); this SDK downloads nothing,
so the tree is vendored, pristine and complete, at `extern/enkiTS/` — 35 files,
revision `404a3bf8f855039dfff2052184d6308655286c07`, zlib,
`Copyright (c) 2013 Doug Binks`.

Three things follow, and they are worth stating plainly:

* **The library does not depend on enkiTS.** No file under `src/` includes it,
  no installed header mentions it, and it is never linked into `libbox2d`. It
  is vendored so the determinism test and the benchmark driver can be compiled.
* **It is not part of the runtime table.** The extern surface in section 6 comes
  from the six Box2D public headers. Nothing enkiTS exports is routed through the
  dispatch, and no enkiTS symbol has to exist in a provider.
* **Its own build files are never invoked.** `extern/enkiTS/build.zig` and
  `extern/enkiTS/build.zig.zon` are enkiTS's, carried with it and pinned in
  `UPSTREAM.sha256`. This SDK compiles enkiTS through its own build graph; do not
  confuse them with this SDK's `build.zig` at the root. The enkiTS zon names
  version `1.11.0` and `.minimum_zig_version = "0.16.0"`.

Its zlib notice is installed with the output at
`share/licenses/box2d/enkiTS-License.txt`, because `bin/box2d-benchmark` links
it and enkiTS's third condition is that the notice may not be removed from a
source distribution. `NOTICE.md` carries the attribution; the third condition
also means the notice stays in every enkiTS source file, which
`UPSTREAM.sha256` pins.