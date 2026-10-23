// SPDX-License-Identifier: MIT
//
//! Behavioral tests for the Box2D facade.
//!
//! Tests compare results with independent kinematic and geometric expectations.
//! Runtime-loading builds use `BOX2D_TEST_PROVIDER`.

const std = @import("std");
const box2d = @import("box2d");
const testing = std.testing;

const provider_variable = "BOX2D_TEST_PROVIDER";

/// Loads the configured native library once before facade calls.
fn nativeReady() void {
    if (comptime !box2d.runtime_loaded) return;
    if (box2d.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(testing.allocator, provider_variable) catch
        missingProvider();
    defer testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    box2d.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting Box2D's entry " ++
            "points, for example the one `zig build -Dlinkage=dynamic " ++
            "-Doptimize=Debug` installs, and export it for the whole `zig build` " ++
            "invocation: the build cannot inject a path into a run step's " ++
            "environment.",
    );
}

const gravity: f32 = 10.0;

const time_step: f32 = 1.0 / 60.0;

const sub_steps: c_int = 4;

const box_half: f32 = 0.5;

const release_height: f32 = 1.0;

const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

const rounding: f32 = 1e-5;

const height_tolerance: f32 = 1e-4;

const speed_tolerance: f32 = 1e-4;

/// Continuous free-fall height after `n` steps.
/// This is independent of Box2D's integration method.
fn ballisticHeight(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return release_height - 0.5 * gravity * t * t;
}

fn ballisticSpeed(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return -gravity * t;
}

/// Bound on integration error around `ballisticHeight(n)`.
/// Allows one sub-step of velocity lag plus `rounding`.
fn fallEnvelope(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return 0.5 * gravity * sub_step * t + rounding;
}

fn expectHeight(got: f32, want: f32) !void {
    if (@abs(got - want) <= height_tolerance) return;
    std.debug.print("height: expected {d}, computed {d} (difference {e})\n", .{
        want, got, @abs(got - want),
    });
    return error.UnexpectedHeight;
}

fn expectFallHeight(got: f32, n: u32) !void {
    const want = ballisticHeight(n);
    const bound = fallEnvelope(n);
    if (!std.math.isFinite(got)) {
        std.debug.print("height after {d} steps is {d}, which is not a number\n", .{
            n, got,
        });
        return error.UnexpectedHeight;
    }
    if (@abs(got - want) <= bound) return;
    std.debug.print(
        "height after {d} steps: expected {d} within {e}, computed {d}\n",
        .{ n, want, bound, got },
    );
    return error.UnexpectedHeight;
}

fn expectSpeed(got: f32, want: f32) !void {
    if (@abs(got - want) <= speed_tolerance) return;
    std.debug.print("speed: expected {d}, computed {d} (difference {e})\n", .{
        want, got, @abs(got - want),
    });
    return error.UnexpectedSpeed;
}

/// `destroy` releases all world-owned allocations.
const Fixture = struct {
    world: box2d.WorldId,
    floor: box2d.BodyId,
    body: box2d.BodyId,

    fn destroy(self: Fixture) void {
        box2d.destroyWorld(self.world);
    }
};

/// Sleeping is disabled for current-position checks.
fn makeFixture() !Fixture {
    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    world_def.enableSleep = false;
    const world = try box2d.createWorld(&world_def);
    errdefer box2d.destroyWorld(world);

    // The box starts one metre above the floor.
    var floor_def = box2d.defaultBodyDef();
    floor_def.position = box2d.vec2(0, -1);
    const floor = try box2d.createBody(world, &floor_def);
    {
        const shape_def = box2d.defaultShapeDef();
        const slab = box2d.makeBox(10, 0.5);
        _ = try box2d.createPolygonShape(floor, &shape_def, &slab);
    }

    var body_def = box2d.defaultBodyDef();
    body_def.type = box2d.c.b2_dynamicBody;
    body_def.position = box2d.vec2(0, release_height);
    const body = try box2d.createBody(world, &body_def);
    {
        var shape_def = box2d.defaultShapeDef();
        shape_def.enableSensorEvents = true;
        const unit_box = box2d.makeBox(box_half, box_half);
        _ = try box2d.createPolygonShape(body, &shape_def, &unit_box);
    }

    return .{ .world = world, .floor = floor, .body = body };
}

fn makeEmptyWorld() !box2d.WorldId {
    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    return box2d.createWorld(&world_def);
}

fn step(world: box2d.WorldId) void {
    box2d.worldStep(world, time_step, sub_steps);
}

test "a released box follows the ballistic trajectory after each step" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    var n: u32 = 0;
    while (n < 10) : (n += 1) {
        step(fixture.world);
        const position = box2d.bodyPosition(fixture.body);
        try expectFallHeight(position.y, n + 1);
        try expectHeight(position.x, 0);

        const velocity = box2d.bodyLinearVelocity(fixture.body);
        try expectSpeed(velocity.y, ballisticSpeed(n + 1));
        try expectSpeed(velocity.x, 0);

        // Confirm that no contacts disturb free fall.
        if (box2d.bodyContactCapacity(fixture.body) != 0) return error.UnexpectedEarlyContact;
    }
}

test "a body is untouched until it is stepped, and gravity scale zero leaves it there" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    try expectHeight(box2d.bodyPosition(fixture.body).y, release_height);
    try expectSpeed(box2d.bodyLinearVelocity(fixture.body).y, 0);

    step(fixture.world);
    try expectFallHeight(box2d.bodyPosition(fixture.body).y, 1);
    try expectSpeed(box2d.bodyLinearVelocity(fixture.body).y, ballisticSpeed(1));

    // Zero gravity scale cancels world gravity.
    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    world_def.enableSleep = false;
    const world = try box2d.createWorld(&world_def);
    defer box2d.destroyWorld(world);

    var body_def = box2d.defaultBodyDef();
    body_def.type = box2d.c.b2_dynamicBody;
    body_def.position = box2d.vec2(0, release_height);
    body_def.gravityScale = 0;
    const hovering = try box2d.createBody(world, &body_def);
    {
        const shape_def = box2d.defaultShapeDef();
        const unit_box = box2d.makeBox(box_half, box_half);
        _ = try box2d.createPolygonShape(hovering, &shape_def, &unit_box);
    }

    var n: u32 = 0;
    while (n < 10) : (n += 1) step(world);
    try expectHeight(box2d.bodyPosition(hovering).y, release_height);
    try expectSpeed(box2d.bodyLinearVelocity(hovering).y, 0);
}

test "a ray through the box hits its exact top surface" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // The ray hits the top face at y=1.5 and fraction=0.425.
    const hit = box2d.worldCastRayClosest(
        fixture.world,
        box2d.vec2(0, 10),
        box2d.vec2(0, -20),
        box2d.defaultQueryFilter(),
    );
    if (!hit.hit) return error.MissedRay;
    try expectHeight(hit.point.y, 1.5);
    try expectHeight(hit.point.x, 0);
    try expectHeight(hit.normal.y, 1);
    try expectHeight(hit.fraction, 0.425);

    const miss = box2d.worldCastRayClosest(
        fixture.world,
        box2d.vec2(11, 10),
        box2d.vec2(0, -20),
        box2d.defaultQueryFilter(),
    );
    if (miss.hit) return error.UnexpectedRayHit;
}

test "point queries agree with the box's own geometry" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    var shape_ids: [8]box2d.ShapeId = undefined;
    const shape_count = shapeCountInto(fixture.body, &shape_ids);
    if (shape_count != 1) return error.UnexpectedShapeCount;
    const shape = shape_ids[0];

    if (!box2d.shapeTestPoint(shape, box2d.vec2(0.25, release_height))) {
        return error.PointInsideRejected;
    }
    if (box2d.shapeTestPoint(shape, box2d.vec2(0.75, release_height))) {
        return error.PointOutsideAccepted;
    }

    // The reported AABB is conservative; check only containment.
    const polygon = box2d.shapePolygon(shape);
    if (polygon.count != 4) return error.UnexpectedVertexCount;
    const aabb = box2d.shapeAabb(shape);
    try std.testing.expect(aabb.lowerBound.x <= -box_half);
    try std.testing.expect(aabb.lowerBound.y <= release_height - box_half);
    try std.testing.expect(aabb.upperBound.x >= box_half);
    try std.testing.expect(aabb.upperBound.y >= release_height + box_half);
}

test "a body's shape list truncates at the slice the caller supplied" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // A short slice silently truncates to its capacity.
    const extra_def = box2d.defaultShapeDef();
    const unit_box = box2d.makeBox(box_half, box_half);
    const at_one = box2d.makeOffsetBox(box_half, box_half, box2d.vec2(2, 0), box2d.rot_identity);
    const at_two = box2d.makeOffsetBox(box_half, box_half, box2d.vec2(4, 0), box2d.rot_identity);
    _ = try box2d.createPolygonShape(fixture.body, &extra_def, &unit_box);
    _ = try box2d.createPolygonShape(fixture.body, &extra_def, &at_one);
    _ = try box2d.createPolygonShape(fixture.body, &extra_def, &at_two);

    const total = box2d.bodyShapeCount(fixture.body);
    if (total != 4) return error.UnexpectedShapeCount;

    var short: [2]box2d.ShapeId = undefined;
    const written_short = box2d.bodyShapes(fixture.body, &short);
    if (written_short != 2) return error.ShortFillDidNotTruncate;

    var complete: [4]box2d.ShapeId = undefined;
    const written_complete = box2d.bodyShapes(fixture.body, &complete);
    if (written_complete != 4) return error.CompleteFillWasShort;

    // The shorter result must be a prefix of the full list.
    for (complete[0..written_short], short) |have, got| {
        if (!box2d.idsEqual(have, got)) return error.ShapeOrderChanged;
    }

    var floor_ids: [8]box2d.ShapeId = undefined;
    const floor_shapes = try countShapes(fixture.floor, &floor_ids);
    if (floor_shapes != 1) return error.UnexpectedFloorShapeCount;
}

test "a destroyed handle stays invalid even when its index is reused" {
    nativeReady();
    const world = try makeEmptyWorld();
    defer box2d.destroyWorld(world);

    var body_def = box2d.defaultBodyDef();
    body_def.type = box2d.c.b2_dynamicBody;
    body_def.position = box2d.vec2(0, release_height);
    const first = try box2d.createBody(world, &body_def);
    if (!box2d.bodyIsValid(first)) return error.FreshBodyRejected;

    const shape_def = box2d.defaultShapeDef();
    const unit_box = box2d.makeBox(box_half, box_half);
    const shape = try box2d.createPolygonShape(first, &shape_def, &unit_box);
    if (!box2d.shapeIsValid(shape)) return error.FreshShapeRejected;
    if (!box2d.idsEqual(box2d.shapeBody(shape), first)) return error.ShapeWrongBody;

    box2d.destroyShape(shape, true);
    if (box2d.shapeIsValid(shape)) return error.DestroyedShapeAccepted;

    box2d.destroyBody(first);
    if (box2d.bodyIsValid(first)) return error.DestroyedBodyAccepted;

    // Reuse the same index with a new generation.
    const second = try box2d.createBody(world, &body_def);
    if (second.index1 != first.index1) return error.IndexWasNotReused;
    if (box2d.idsEqual(first, second)) return error.GenerationWasNotBumped;
    if (box2d.bodyIsValid(first)) return error.StaleGenerationAccepted;
    if (!box2d.bodyIsValid(second)) return error.ReusedBodyRejected;

    // The packed id must preserve the full handle.
    const stored = box2d.storeBodyId(second);
    if (!box2d.idsEqual(box2d.loadBodyId(stored), second)) {
        return error.BodyIdRoundTripFailed;
    }

    if (box2d.bodyIsValid(box2d.null_body_id)) return error.NullBodyAccepted;
    if (!box2d.isNullId(box2d.null_body_id)) return error.NullBodyNotNull;
    if (box2d.isNullId(second)) return error.LiveBodyReportedNull;
}

test "destroying a world invalidates every handle it handed out" {
    nativeReady();
    const fixture = try makeFixture();
    const world = fixture.world;
    const body = fixture.body;
    const floor = fixture.floor;

    var shapes: [4]box2d.ShapeId = undefined;
    if (box2d.bodyShapes(body, &shapes) != 1) return error.WrongShapeCount;
    const shape = shapes[0];

    box2d.destroyWorld(world);

    if (box2d.worldIsValid(world)) return error.DestroyedWorldAccepted;
    if (box2d.bodyIsValid(body)) return error.BodySurvivedWorld;
    if (box2d.bodyIsValid(floor)) return error.FloorSurvivedWorld;
    if (box2d.shapeIsValid(shape)) return error.ShapeSurvivedWorld;

    // Reusing a world slot must not revive its old generation.
    const replacement = try makeEmptyWorld();
    defer box2d.destroyWorld(replacement);
    if (replacement.index1 != world.index1) return error.WorldIndexWasNotReused;
    if (box2d.worldIsValid(world)) return error.StaleWorldGenerationAccepted;
    if (!box2d.worldIsValid(replacement)) return error.ReusedWorldRejected;
}

test "world creation is refused once all the slots are in use" {
    nativeReady();

    const world_limit = 128;

    var worlds: [world_limit]box2d.WorldId = undefined;
    var made: usize = 0;
    while (made < world_limit) : (made += 1) {
        worlds[made] = makeEmptyWorld() catch |err| {
            std.debug.print("world {d} of {d} was refused early: {t}\n", .{ made, world_limit, err });
            return err;
        };
        if (!box2d.worldIsValid(worlds[made])) return error.CreatedWorldRejected;
    }

    if (makeEmptyWorld()) |_| {
        for (worlds) |w| box2d.destroyWorld(w);
        return error.LimitNotEnforced;
    } else |err| {
        if (err != error.WorldLimitReached) {
            for (worlds) |w| box2d.destroyWorld(w);
            return err;
        }
    }

    // Freeing a slot makes room without reviving its old handle.
    const freed = worlds[world_limit - 1];
    box2d.destroyWorld(freed);
    if (box2d.worldIsValid(freed)) return error.FreedWorldAccepted;

    const reopened = makeEmptyWorld() catch |err| {
        for (worlds[0 .. world_limit - 1]) |w| box2d.destroyWorld(w);
        return err;
    };
    if (reopened.index1 != freed.index1) return error.FreedSlotWasNotReused;
    if (box2d.worldIsValid(freed)) return error.StaleWorldAcceptedAfterReuse;
    box2d.destroyWorld(reopened);

    for (worlds[0 .. world_limit - 1]) |w| box2d.destroyWorld(w);
}

test "a sensor reports exactly one begin event per overlapping shape" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // The sensor overlaps the falling box before it reaches the floor.
    var sensor_body_def = box2d.defaultBodyDef();
    sensor_body_def.position = box2d.vec2(0, 0.25);
    const sensor_body = try box2d.createBody(fixture.world, &sensor_body_def);
    var sensor_shape_def = box2d.defaultShapeDef();
    sensor_shape_def.isSensor = true;
    sensor_shape_def.enableSensorEvents = true;
    const sensor_box = box2d.makeBox(2, 0.125);
    const sensor = try box2d.createPolygonShape(sensor_body, &sensor_shape_def, &sensor_box);

    // No overlap exists before the first sensor event.
    step(fixture.world);
    if (box2d.sensorBeginEvents(fixture.world).len != 0) return error.BeginEventBeforeOverlap;

    // Sensor events belong to the step that produces them.
    var begin_count: usize = 0;
    var begin_sensor: box2d.ShapeId = box2d.null_shape_id;
    var begin_visitor: box2d.ShapeId = box2d.null_shape_id;
    var steps_taken: u32 = 0;
    while (steps_taken < 200) : (steps_taken += 1) {
        step(fixture.world);
        const begin = box2d.sensorBeginEvents(fixture.world);
        if (begin.len == 0) continue;
        begin_count = begin.len;
        begin_sensor = begin[0].sensorShapeId;
        begin_visitor = begin[0].visitorShapeId;
        break;
    }
    if (begin_count != 1) {
        std.debug.print("expected one begin event after {d} steps, saw {d}\n", .{
            steps_taken, begin_count,
        });
        return error.WrongBeginEventCount;
    }
    if (!box2d.idsEqual(begin_sensor, sensor)) return error.BeginEventWrongSensor;
    if (!box2d.shapeIsValid(begin_visitor)) return error.BeginEventStaleVisitor;

    // Moving the sensor away produces one end event on the next step.
    box2d.bodySetTransform(sensor_body, box2d.vec2(50, 0.25), box2d.rot_identity);
    step(fixture.world);
    const end = box2d.sensorEndEvents(fixture.world);
    if (end.len != 1) {
        std.debug.print("expected one end event, saw {d}\n", .{end.len});
        return error.WrongEndEventCount;
    }
    if (!box2d.idsEqual(end[0].sensorShapeId, sensor)) return error.EndEventWrongSensor;
}

test "body move events name only the bodies that moved" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // No move events exist before the first step.
    if (box2d.bodyMoveEvents(fixture.world).len != 0) return error.MoveEventBeforeStep;

    step(fixture.world);
    const moves = box2d.bodyMoveEvents(fixture.world);
    if (moves.len != 1) {
        std.debug.print("expected one move event, saw {d}\n", .{moves.len});
        return error.WrongMoveEventCount;
    }
    if (!box2d.idsEqual(moves[0].bodyId, fixture.body)) return error.MoveEventWrongBody;
    if (moves[0].fellAsleep) return error.FellAsleepWithSleepDisabled;
    // The event transform matches the body's current transform.
    const reported = box2d.bodyTransform(fixture.body);
    try expectHeight(moves[0].transform.p.y, reported.p.y);

    // Events are replaced on each step, not accumulated.
    step(fixture.world);
    const again = box2d.bodyMoveEvents(fixture.world);
    if (again.len != 1) return error.MoveEventAccumulated;
    try expectFallHeight(again[0].transform.p.y, 2);
}

fn countShapes(body: box2d.BodyId, ids: []box2d.ShapeId) !c_int {
    const capacity = box2d.bodyShapeCount(body);
    if (capacity < 0 or ids.len < @as(usize, @intCast(capacity))) {
        return error.ImplausibleShapeCount;
    }
    const written = box2d.bodyShapes(body, ids[0..@intCast(capacity)]);
    if (written != @as(usize, @intCast(capacity))) return error.ShapeListShort;
    return capacity;
}

fn shapeCountInto(body: box2d.BodyId, out: []box2d.ShapeId) c_int {
    return @intCast(box2d.bodyShapes(body, out));
}

test "a convex hull built from a square has unit area" {
    nativeReady();

    // The shoelace formula measures the returned vertices independently.
    const corners = [_]box2d.Vec2{
        box2d.vec2(0, 0),
        box2d.vec2(1, 0),
        box2d.vec2(1, 1),
        box2d.vec2(0, 1),
    };
    const hull = box2d.computeHull(&corners) catch return error.UnitSquareRejected;
    if (hull.count != 4) return error.WrongHullVertexCount;
    if (!box2d.validateHull(&hull)) return error.HullRejectedByUpstream;

    const polygon = box2d.makePolygon(&hull, 0);
    if (polygon.count != 4) return error.WrongPolygonVertexCount;

    var twice_area: f32 = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(polygon.count))) : (i += 1) {
        const a = polygon.vertices[i];
        const b = polygon.vertices[(i + 1) % @as(usize, @intCast(polygon.count))];
        twice_area += a.x * b.y - b.x * a.y;
    }
    try expectHeight(@abs(twice_area) / 2, 1.0);

    const two_points = [_]box2d.Vec2{ box2d.vec2(0, 0), box2d.vec2(1, 1) };
    if (box2d.computeHull(&two_points)) |_| {
        return error.DegenerateHullAccepted;
    } else |err| {
        if (err != error.HullNotConvex) return err;
    }
}

test "circle mass and length-and-normalize are their closed forms" {
    nativeReady();

    // A unit circle has mass pi and inertia pi/2.
    const disc = box2d.circle(box2d.vec2_zero, 1);
    const mass = box2d.computeCircleMass(&disc, 1);
    try expectHeight(mass.mass, std.math.pi);
    try expectHeight(mass.rotationalInertia, std.math.pi / 2.0);
    try expectHeight(mass.center.x, 0);
    try expectHeight(mass.center.y, 0);

    // The result combines upstream's length out-parameter and direction return.
    const answer = box2d.getLengthAndNormalize(box2d.vec2(3, 4));
    try expectHeight(answer.length, 5);
    try expectHeight(answer.direction.x, 0.6);
    try expectHeight(answer.direction.y, 0.8);

    const degenerate = box2d.getLengthAndNormalize(box2d.vec2_zero);
    try expectHeight(degenerate.length, 0);
    try expectHeight(degenerate.direction.x, 0);
    try expectHeight(degenerate.direction.y, 0);

    const quarter = box2d.makeRot(std.math.pi / 2.0);
    const rotated = box2d.rotateVector(quarter, box2d.vec2(1, 0));
    try expectHeight(rotated.x, 0);
    try expectHeight(rotated.y, 1);
}

test "the dynamic tree returns exactly the proxies inside the query box" {
    nativeReady();

    var tree = box2d.dynamicTreeCreate();
    defer box2d.dynamicTreeDestroy(&tree);

    // Three disjoint unit boxes on a line.
    const a = box2d.dynamicTreeCreateProxy(&tree, unitAabb(0), 1, 100);
    const b = box2d.dynamicTreeCreateProxy(&tree, unitAabb(3), 1, 200);
    const c = box2d.dynamicTreeCreateProxy(&tree, unitAabb(6), 1, 300);
    if (a < 0 or b < 0 or c < 0) return error.ProxyCreationFailed;
    if (box2d.dynamicTreeProxyCount(&tree) != 3) return error.WrongProxyCount;

    // A query spanning both end proxies includes the middle proxy.
    var found = QueryLog{};
    _ = box2d.dynamicTreeQuery(
        &tree,
        box2d.makeAabb(&[_]box2d.Vec2{ box2d.vec2(-1, -1), box2d.vec2(7, 1) }, 0),
        ~@as(u64, 0),
        @as(*const box2d.TreeQueryCallbackFn, &QueryLog.callback),
        &found,
    );
    if (found.count != 3) return error.WrongQueryResultCount;
    for ([_]u64{ 100, 200, 300 }) |value| {
        if (std.mem.indexOfScalar(u64, found.saw[0..found.count], value) == null) return error.WrongQueryResults;
    }

    // A query around the middle proxy returns only that proxy.
    var single = QueryLog{};
    _ = box2d.dynamicTreeQuery(
        &tree,
        box2d.makeAabb(&[_]box2d.Vec2{ box2d.vec2(2.5, -1), box2d.vec2(3.5, 1) }, 0),
        ~@as(u64, 0),
        @as(*const box2d.TreeQueryCallbackFn, &QueryLog.callback),
        &single,
    );
    if (single.count != 1 or single.saw[0] != 200) return error.WrongNarrowQueryResult;

    // Moving the third proxy outside removes it from the query.
    box2d.dynamicTreeMoveProxy(&tree, c, unitAabb(20));
    var after_move = QueryLog{};
    _ = box2d.dynamicTreeQuery(
        &tree,
        box2d.makeAabb(&[_]box2d.Vec2{ box2d.vec2(-1, -1), box2d.vec2(7, 1) }, 0),
        ~@as(u64, 0),
        @as(*const box2d.TreeQueryCallbackFn, &QueryLog.callback),
        &after_move,
    );
    if (after_move.count != 2) return error.MoveNotObserved;
    for ([_]u64{ 100, 200 }) |value| {
        if (std.mem.indexOfScalar(u64, after_move.saw[0..after_move.count], value) == null) return error.MoveNotObserved;
    }

    // Destroying a proxy decrements the count.
    box2d.dynamicTreeDestroyProxy(&tree, b);
    if (box2d.dynamicTreeProxyCount(&tree) != 2) return error.ProxyNotDestroyed;

    box2d.dynamicTreeValidate(&tree);
    box2d.dynamicTreeValidateNoEnlarged(&tree);
}

fn unitAabb(center_x: f32) box2d.Aabb {
    return .{
        .lowerBound = box2d.vec2(center_x - 0.5, -0.5),
        .upperBound = box2d.vec2(center_x + 0.5, 0.5),
    };
}

/// Data passed through Box2D's dynamic-tree query callback context.
const QueryLog = struct {
    /// Number of proxies visited.
    count: usize = 0,
    /// User data values in visitation order.
    saw: [4]u64 = .{ 0, 0, 0, 0 },

    fn callback(proxy_id: c_int, user_data: u64, context: ?*anyopaque) callconv(.c) bool {
        _ = proxy_id;
        const self: *QueryLog = @ptrCast(@alignCast(context.?));
        if (self.count < self.saw.len) {
            self.saw[self.count] = user_data;
        }
        self.count += 1;
        return true;
    }
};

test "the library this build reached still holds the process globals it was given" {
    nativeReady();

    // Check process globals without pinning the provider's version.

    // Length units start at one; the test checks no call changed them.
    const units = box2d.getLengthUnitsPerMeter();
    if (@abs(units - 1.0) > 1e-6) {
        std.debug.print("length units per meter is {d}, expected 1\n", .{units});
        return error.UnexpectedLengthUnits;
    }

    // The allocated byte count is non-negative.
    if (box2d.getByteCount() < 0) return error.NegativeByteCount;
}
