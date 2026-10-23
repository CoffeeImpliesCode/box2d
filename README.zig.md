# Zig facade API

The typed facade drops the `b2` prefix and converts function names to camelCase. Parameters keep upstream's `snake_case`; an entity ID comes first. The translated C API remains available under `c` with upstream names.

## Runtime loading

- `LoadSource = union(enum) { path: []const u8, system: []const u8 }`. Use an absolute path or a library basename without separators. A path does not fall back to a system lookup.
- `LoadError`: `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad`.
- `load(source: LoadSource) LoadError!void` loads the provider. `loadedSource() ?LoadSource` returns the selected request or `null`; `runtime_loaded: bool` identifies runtime-dispatch builds.
- The same request is idempotent. A different request after success returns `ProviderMismatch`; same-thread reentry returns `ReentrantLoad`. Call `load` again to retry after failure.
- A loaded provider is process-lifetime; there is no unload. Calling a Box2D function before loading, or calling `load` in a linked build, panics.
- The loader checks `b2GetVersion().major == 3` and `b2GetLengthUnitsPerMeter() > 0`. `Debug` and `ReleaseSafe` runtime consumers require a provider exporting `b2InternalAssertFcn`.
- These checks do not prove ABI compatibility. The provider and consumer must use matching C layouts and the target's C ABI.

## Errors

`CreateError` is `{ WorldLimitReached, WorldLocked, HullNotConvex }`.

- `createWorld` can return `WorldLimitReached` and returns `null_world_id` if upstream returns a null ID.
- `createBody`, `create*Shape`, and `createChain` can return `WorldLocked`; `computeHull` can return `HullNotConvex`.
- A degenerate segment triggers an upstream assertion in `Debug` and `ReleaseSafe`; in `ReleaseFast` and `ReleaseSmall`, its null return maps to `WorldLocked`. `createCapsuleShape` turns coincident endpoints into a circle.

## Constants and IDs

Constants: `max_polygon_vertices`, `default_category_bits`, `default_mask_bits`, `pi`, `hash_init`, `vec2_zero`, `rot_identity`, `transform_identity`.

IDs: `WorldId`, `BodyId`, `ShapeId`, `ChainId`, `JointId`; `null_world_id`, `null_body_id`, `null_shape_id`, `null_chain_id`, `null_joint_id`; `isNullId`, `idsEqual`, `storeWorldId`/`loadWorldId`, `storeBodyId`/`loadBodyId`, `storeShapeId`/`loadShapeId`, `storeChainId`/`loadChainId`, `storeJointId`/`loadJointId`. Upstream documents that `idsEqual` does not work for `WorldId`.

## Functions

- Base: `getVersion`, `setAllocator`, `getByteCount`, `setAssertFcn`, `getTicks`, `getMilliseconds`, `getMillisecondsAndReset`, `yield`, `hash`.
- Defaults: `defaultWorldDef`, `defaultBodyDef`, `defaultFilter`, `defaultQueryFilter`, `defaultSurfaceMaterial`, `defaultShapeDef`, `defaultChainDef`,
  `defaultDistanceJointDef`, `defaultMotorJointDef`, `defaultMouseJointDef`, `defaultFilterJointDef`, `defaultPrismaticJointDef`,
  `defaultRevoluteJointDef`, `defaultWeldJointDef`, `defaultWheelJointDef`, `defaultExplosionDef`, `defaultDebugDraw`.
- Math: `vec2`, `circle`, `makeRot`, `computeCosSin`, `atan2`, `computeAngularVelocity`, `computeRotationBetweenUnitVectors`, `dot`, `cross`,
  `crossVS`, `crossSV`, `add`, `sub`, `neg`, `mul`, `mulSV`, `mulAdd`, `mulSub`, `absVec`, `minVec`, `maxVec`, `clampVec`, `lerpVec`,
  `length`, `lengthSquared`, `distance`, `distanceSquared`, `normalize`, `isNormalized`, `getLengthAndNormalize`, `leftPerp`, `rightPerp`,
  `rotateVector`, `invRotateVector`, `rotAngle`, `rotXAxis`, `rotYAxis`, `relativeAngle`, `normalizeRot`, `nLerp`, `mulRot`, `invMulRot`,
  `unwindAngle`, `integrateRotation`, `transformPoint`, `invTransformPoint`, `mulTransforms`, `invMulTransforms`, `mulMV`, `getInverse22`,
  `solve22`, `aabbContains`, `aabbCenter`, `aabbExtents`, `aabbUnion`, `aabbOverlaps`, `makeAabb`, `planeSeparation`, `springDamper`,
  `clampFloat`, `maxFloat`, `minFloat`, `absFloat`, `clampInt`, `maxInt`, `minInt`, `absInt`, `setLengthUnitsPerMeter`,
  `getLengthUnitsPerMeter`, `isValidFloat`, `isValidVec2`, `isValidRotation`, `isValidAabb`, `isValidPlane`.
- Geometry: `makePolygon`, `makeOffsetPolygon`, `makeOffsetRoundedPolygon`, `makeSquare`, `makeBox`, `makeRoundedBox`, `makeOffsetBox`,
  `makeOffsetRoundedBox`, `transformPolygon`, `makeProxy`, `makeOffsetProxy`, `computeHull`, `validateHull`, `computeCircleMass`,
  `computeCapsuleMass`, `computePolygonMass`, `computeCircleAabb`, `computeCapsuleAabb`, `computePolygonAabb`, `computeSegmentAabb`,
  `pointInCircle`, `pointInCapsule`, `pointInPolygon`, `rayCastCircle`, `rayCastCapsule`, `rayCastSegment`, `rayCastPolygon`,
  `shapeCastCircle`, `shapeCastCapsule`, `shapeCastSegment`, `shapeCastPolygon`, `isValidRay`, `segmentDistance`, `shapeDistance`, `shapeCast`,
  `timeOfImpact`, `getSweepTransform`.
- Collision: `collideCircles`, `collideCapsuleAndCircle`, `collideSegmentAndCircle`, `collidePolygonAndCircle`, `collideCapsules`,
  `collideSegmentAndCapsule`, `collidePolygonAndCapsule`, `collidePolygons`, `collideSegmentAndPolygon`, `collideChainSegmentAndCircle`,
  `collideChainSegmentAndCapsule`, `collideChainSegmentAndPolygon`. Character mover: `solvePlanes`, `clipVector`.
- Dynamic tree: `dynamicTreeCreate`, `dynamicTreeDestroy`, `dynamicTreeCreateProxy`, `dynamicTreeDestroyProxy`, `dynamicTreeMoveProxy`,
  `dynamicTreeEnlargeProxy`, `dynamicTreeSetCategoryBits`, `dynamicTreeGetCategoryBits`, `dynamicTreeQuery`, `dynamicTreeRayCast`,
  `dynamicTreeShapeCast`, `dynamicTreeHeight`, `dynamicTreeAreaRatio`, `dynamicTreeRootBounds`, `dynamicTreeProxyCount`, `dynamicTreeRebuild`,
  `dynamicTreeByteCount`, `dynamicTreeUserData`, `dynamicTreeAabb`, `dynamicTreeValidate`, `dynamicTreeValidateNoEnlarged`.
- World: `createWorld`, `destroyWorld`, `worldIsValid`, `worldStep`, `worldDraw`, `worldBodyEvents`, `worldSensorEvents`, `worldContactEvents`,
  `worldOverlapAabb`, `worldOverlapShape`, `worldCastRay`, `worldCastRayClosest`, `worldCastShape`, `worldCastMover`, `worldCollideMover`,
  `worldEnableSleeping`, `worldIsSleepingEnabled`, `worldEnableContinuous`, `worldIsContinuousEnabled`, `worldSetRestitutionThreshold`,
  `worldGetRestitutionThreshold`, `worldSetHitEventThreshold`, `worldGetHitEventThreshold`, `worldSetCustomFilterCallback`,
  `worldSetPreSolveCallback`, `worldSetGravity`, `worldGetGravity`, `worldExplode`, `worldSetContactTuning`, `worldSetMaximumLinearSpeed`,
  `worldGetMaximumLinearSpeed`, `worldEnableWarmStarting`, `worldIsWarmStartingEnabled`, `worldGetAwakeBodyCount`, `worldGetProfile`,
  `worldGetCounters`, `worldSetUserData`, `worldGetUserData`, `worldSetFrictionCallback`, `worldSetRestitutionCallback`,
  `worldDumpMemoryStats`, `worldRebuildStaticTree`, `worldEnableSpeculative`.
- Body: `createBody`, `destroyBody`, `bodyIsValid`, `bodyType`, `bodySetType`, `bodySetName`, `bodyName`, `bodySetUserData`,
  `bodyGetUserData`, `bodyPosition`, `bodyRotation`, `bodyTransform`, `bodySetTransform`, `bodyLocalPoint`, `bodyWorldPoint`, `bodyLocalVector`,
  `bodyWorldVector`, `bodyLinearVelocity`, `bodySetLinearVelocity`, `bodyAngularVelocity`, `bodySetAngularVelocity`, `bodySetTargetTransform`,
  `bodyLocalPointVelocity`, `bodyWorldPointVelocity`, `bodyApplyForce`, `bodyApplyForceToCenter`, `bodyApplyTorque`, `bodyApplyLinearImpulse`,
  `bodyApplyLinearImpulseToCenter`, `bodyApplyAngularImpulse`, `bodyMass`, `bodyRotationalInertia`, `bodyLocalCenterOfMass`,
  `bodyWorldCenterOfMass`, `bodySetMassData`, `bodyMassData`, `bodyApplyMassFromShapes`, `bodySetLinearDamping`, `bodyGetLinearDamping`,
  `bodySetAngularDamping`, `bodyGetAngularDamping`, `bodySetGravityScale`, `bodyGetGravityScale`, `bodyIsAwake`, `bodySetAwake`,
  `bodyEnableSleep`, `bodyIsSleepEnabled`, `bodySetSleepThreshold`, `bodyGetSleepThreshold`, `bodyIsEnabled`, `bodyDisable`, `bodyEnable`,
  `bodySetFixedRotation`, `bodyIsFixedRotation`, `bodySetBullet`, `bodyIsBullet`, `bodyEnableContactEvents`, `bodyEnableHitEvents`, `bodyWorld`,
  `bodyShapeCount`, `bodyShapes`, `bodyJointCount`, `bodyJoints`, `bodyContactCapacity`, `bodyContactData`, `bodyComputeAabb`.
- Shape: `createCircleShape`, `createCapsuleShape`, `createPolygonShape`, `createSegmentShape`, `destroyShape`, `shapeIsValid`, `shapeType`,
  `shapeBody`, `shapeWorld`, `shapeIsSensor`, `shapeSetUserData`, `shapeGetUserData`, `shapeSetDensity`, `shapeDensity`, `shapeSetFriction`,
  `shapeFriction`, `shapeSetRestitution`, `shapeRestitution`, `shapeSetMaterial`, `shapeMaterial`, `shapeSetSurfaceMaterial`,
  `shapeSurfaceMaterial`, `shapeFilter`, `shapeSetFilter`, `shapeEnableSensorEvents`, `shapeAreSensorEventsEnabled`,
  `shapeEnableContactEvents`, `shapeAreContactEventsEnabled`, `shapeEnablePreSolveEvents`, `shapeArePreSolveEventsEnabled`,
  `shapeEnableHitEvents`, `shapeAreHitEventsEnabled`, `shapeTestPoint`, `shapeRayCast`, `shapeCircle`, `shapeSegment`, `shapeChainSegment`,
  `shapeCapsule`, `shapePolygon`, `shapeSetCircle`, `shapeSetCapsule`, `shapeSetSegment`, `shapeSetPolygon`, `shapeParentChain`,
  `shapeContactCapacity`, `shapeContactData`, `shapeSensorCapacity`, `shapeSensorOverlaps`, `shapeAabb`, `shapeMassData`, `shapeClosestPoint`.
- Chain: `createChain`, `destroyChain`, `chainWorld`, `chainSegmentCount`, `chainSegments`, `chainSetFriction`, `chainFriction`,
  `chainSetRestitution`, `chainRestitution`, `chainSetMaterial`, `chainMaterial`, `chainIsValid`.
- Joint base: `destroyJoint`, `jointIsValid`, `jointType`, `jointBodyA`, `jointBodyB`, `jointWorld`, `jointSetLocalAnchorA`, `jointLocalAnchorA`,
  `jointSetLocalAnchorB`, `jointLocalAnchorB`, `jointReferenceAngle`, `jointSetReferenceAngle`, `jointSetLocalAxisA`, `jointLocalAxisA`,
  `jointSetCollideConnected`, `jointCollideConnected`, `jointSetUserData`, `jointGetUserData`, `jointWakeBodies`, `jointConstraintForce`,
  `jointConstraintTorque`, `jointLinearSeparation`, `jointAngularSeparation`, `jointConstraintTuning`, `jointSetConstraintTuning`,
  `ConstraintTuning`.
- Joint creation: `createDistanceJoint`, `createMotorJoint`, `createMouseJoint`, `createFilterJoint`, `createPrismaticJoint`,
  `createRevoluteJoint`, `createWeldJoint`, `createWheelJoint`, plus typed forms of each `b2<Type>Joint_{Set,Get,Is,Enable,Are}…` declaration.

## Events and callbacks

`bodyMoveEvents`, `sensorBeginEvents`, `sensorEndEvents`, `contactBeginEvents`, `contactEndEvents`, and `contactHitEvents` return borrowed slices valid until the next `worldStep` on that world. Copy data that must outlive the step. Sensor events are off by default; enable them on both overlapping shapes. Chains expose the same sensor-event option; body-move events are not gated.

`setAllocator` installs a process-wide `AllocFcn`/`FreeFcn` pair. Box2D allocations belong to that pair, not a Zig allocator. Worlds own their bodies, shapes, chains and joints; destroy them while the world is alive. Values are not reference-counted.

Callback aliases: `AllocFcn`, `FreeFcn`, `AssertFcn`, `TaskCallback`, `EnqueueTaskCallback`, `FinishTaskCallback`, `FrictionCallback`, `RestitutionCallback`, `CustomFilterFn`, `PreSolveFn`, `OverlapResultFn`, `CastResultFn`, `PlaneResultFn`, `TreeQueryCallbackFn`, `TreeRayCastCallbackFn`, `TreeShapeCastCallbackFn`. These alias translated C callback types, called on the thread that calls Box2D. Nullable pointers on query entry points must not be null; `worldSetFrictionCallback` and `worldSetRestitutionCallback` accept null to restore upstream defaults.

## Value types

`Vec2`, `CosSin`, `Rot`, `Transform`, `Mat22`, `Aabb`, `Plane`, `Version`, `RayCastInput`, `ShapeProxy`, `ShapeCastInput`, `CastOutput`,
`MassData`, `Circle`, `Capsule`, `Polygon`, `Segment`, `ChainSegment`, `Hull`, `SegmentDistanceResult`, `SimplexCache`, `DistanceInput`,
`DistanceOutput`, `SimplexVertex`, `Simplex`, `ShapeCastPairInput`, `Sweep`, `TOIInput`, `TOIState`, `TOIOutput`, `ManifoldPoint`, `Manifold`,
`DynamicTree`, `TreeStats`, `PlaneResult`, `CollisionPlane`, `PlaneSolverResult`, `WorldDef`, `BodyType`, `BodyDef`, `Filter`, `QueryFilter`,
`ShapeType`, `SurfaceMaterial`, `ShapeDef`, `ChainDef`, `Profile`, `Counters`, `JointType`, `DistanceJointDef`, `MotorJointDef`, `MouseJointDef`,
`FilterJointDef`, `PrismaticJointDef`, `RevoluteJointDef`, `WeldJointDef`, `WheelJointDef`, `ExplosionDef`, `SensorBeginTouchEvent`,
`SensorEndTouchEvent`, `SensorEvents`, `ContactBeginTouchEvent`, `ContactEndTouchEvent`, `ContactHitEvent`, `ContactEvents`, `BodyMoveEvent`,
`BodyEvents`, `ContactData`, `DebugDraw`, `RayResult`, `HexColor`.
