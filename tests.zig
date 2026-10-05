// SPDX-License-Identifier: MIT
//
//! Behavioural tests for the Box2D facade.
//!
//! Nothing here asks whether a declaration exists, whether a default equals a
//! constant, or whether a wrapper forwards: those are the tests AGENTS.md §7
//! removes. Every test below asks a question whose answer is known without
//! running the library, and compares that answer with what the library produced.
//!
//! ## The fixture, and why it is not upstream's HelloWorld
//!
//! The fixture is a world with gravity `(0, -10)`, one static floor whose top
//! surface is at `y = -0.5`, and one dynamic box with half-extents `(0.5, 0.5)`
//! released at `(0, 1)` with no velocity and nothing touching it. The box's
//! bottom face starts at `y = 0.5`, so it hangs a full metre above that floor.
//! Upstream's own `samples/hello.c` drops a half-extents `(1, 1)` box from
//! `y = 4` onto a floor centred at `y = -10`, for 60 steps, and prints positions;
//! it never compares anything. The numbers here are different, and more to the
//! point they are chosen so that the answer for the first ten steps is the
//! answer physics gives.
//!
//! ## The oracle
//!
//! For the first ten steps nothing touches anything: the box starts a metre above
//! the floor, the broad phase pairs proxies only inside a fat-AABB margin
//! (`src/constants.h`), and the solver therefore moves one body under gravity
//! alone -- no contact, no damping, no torque.
//!
//! A body released from rest under a constant downward acceleration `g` passes
//! through `y0 - g t^2 / 2` after `t` seconds. That trajectory is the oracle,
//! and it is a property of the motion rather than of any stepper: a stepper
//! that adds `g h` to the velocity and `v h` to the position over sub-steps of
//! `h` trails it by at most one sub-step's worth of velocity, `g h t / 2`.
//! `fallEnvelope` is that term plus a margin for `f32` rounding, and the fall is
//! asserted against it rather than against a value -- how a solver subdivides a
//! step is the library's business, and pinning it would make this file a copy
//! of one integrator rather than a check of the motion.
//!
//! The velocity is not bounded: constant acceleration from rest gives `-g t`
//! whatever the step size, so after `n` world steps the downward speed is
//! `gravity * n * time_step` outright.
//!
//! Nothing in this file was produced by running the library.
//!
//! ## Tolerance, and what it still catches
//!
//! The envelope is the tolerance for the fall, and it is far narrower than any
//! wrong answer. After ten steps the height must be within 3.5e-3 m of 0.861 m,
//! where a body that was never stepped is at 1 and one under half the gravity is
//! at 0.93; the velocity is exact to 1e-4 m/s against `1.67 m/s`.
//!
//! Every other position comparison uses 1e-4 m and every velocity 1e-4 m/s. That
//! is four to six orders of magnitude above the `f32` rounding, and the values
//! being compared are geometry the library reports exactly -- a ray's hit point
//! on a plane, a hull's area, a disc's mass. The tolerance is there for
//! `f32` arithmetic and not to accept any answer.
//!
//! ## Runtime-loading builds
//!
//! In a linked build the fixture works immediately. In a `-Druntime` build every
//! call goes through a table that one explicit `load` fills, so `nativeReady`
//! below is where that happens, and a build that was not told which file to load
//! stops with the variable's name rather than reporting a failure that says
//! nothing about the reason.

const std = @import("std");
const box2d = @import("box2d");
const testing = std.testing;

/// A shared object exporting Box2D's declared entry points, named by the
/// environment in a runtime-loading build.
const provider_variable = "BOX2D_TEST_PROVIDER";

/// Make the native library usable, once, before a test calls the facade.
///
/// Safe to call from every test: the loader's contract makes the same request
/// idempotent and keeps the handle to the end of the process.
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

// ---------------------------------------------------------------------------
// The fixture
// ---------------------------------------------------------------------------

/// Gravity magnitude of the fixture world, m/s^2. Upstream's default is exactly
/// this (`src/types.c:13`), and it is set explicitly rather than inherited so a
/// change to that default cannot quietly move every number in this file.
const gravity: f32 = 10.0;

/// The world's time step, seconds. 1/60 s.
const time_step: f32 = 1.0 / 60.0;

/// Solver sub-steps per world step. Upstream recommends four at 60 Hz
/// (`include/box2d/box2d.h:35-38`).
const sub_steps: c_int = 4;

/// Half-extents of the dynamic box: a unit square.
const box_half: f32 = 0.5;

/// Where the box starts: its centre. Its bottom face is at `release_height -
/// box_half = 0.5`, which is a full metre above the floor's top surface, so
/// nothing is touching and no contact exists for the first ten steps.
const release_height: f32 = 1.0;

/// The sub-step the solver integrates over, seconds: the world time step split
/// into `sub_steps` equal parts.
const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

/// The `f32` slack `fallEnvelope` carries on top of its discretisation term,
/// metres. Ten steps accumulate a handful of roundings near 1 m, so this is
/// several times what they can add without being wide enough to accept a wrong
/// answer.
const rounding: f32 = 1e-5;

/// How far two heights may differ and still be the same answer, metres.
const height_tolerance: f32 = 1e-4;

/// How far two speeds may differ and still be the same answer, m/s.
const speed_tolerance: f32 = 1e-4;

/// The height the fixture box passes through after `n` world steps, metres.
///
/// `y0 - g t^2 / 2` with `t = n * time_step`: the continuous trajectory of a body
/// released from rest under `gravity`. It is a property of the motion, so
/// nothing here says how the solver subdivides a step -- see `fallEnvelope` for
/// what the library is allowed to differ from it by.
fn ballisticHeight(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return release_height - 0.5 * gravity * t * t;
}

/// The downward speed the fixture box has after `n` world steps, m/s.
///
/// `-g t`. Constant acceleration from rest gives this velocity at every step
/// size, so it is asserted outright rather than within a bound.
fn ballisticSpeed(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return -gravity * t;
}

/// How far an integration over sub-steps of `sub_step` may sit from
/// `ballisticHeight(n)`, metres.
///
/// A stepper that adds `gravity * sub_step` to the velocity and `v * sub_step`
/// to the position each sub-step trails the continuous trajectory by at most one
/// sub-step's worth of velocity, `gravity * sub_step * t / 2`. That is the whole
/// discretisation term; `rounding` is the `f32` slack underneath it.
///
/// It stays twenty times narrower than the nearest wrong answer: at ten steps a
/// body that was never stepped is 0.14 m away and one under half the gravity is
/// 0.07 m away.
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

/// Assert the fixture box is inside the fall envelope for `n` world steps.
///
/// The finiteness test comes first and separately so that a NaN reports itself as
/// one instead of as a difference that quietly compares false.
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

/// The fixture, as three handles and nothing else.
///
/// There is no `deinit`: Box2D owns every allocation behind a world and
/// `destroyWorld` frees all of it in one call, which is the whole ownership
/// contract `zig/root.zig` states. The fixture exists so a test cannot forget the
/// floor's half-extents or the release height.
const Fixture = struct {
    world: box2d.WorldId,
    floor: box2d.BodyId,
    /// The dynamic box, released at `release_height`.
    body: box2d.BodyId,

    fn destroy(self: Fixture) void {
        box2d.destroyWorld(self.world);
    }
};

/// Build the fixture world: gravity `(0, -10)`, a static floor, and one dynamic
/// unit box released at rest.
///
/// Sleeping is disabled so that a test reading a position after ten steps is not
/// reading a sleeping body's last recorded one, and continuous collision is left
/// at upstream's default because nothing is close enough for it to matter.
fn makeFixture() !Fixture {
    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    world_def.enableSleep = false;
    const world = try box2d.createWorld(&world_def);
    errdefer box2d.destroyWorld(world);

    // The floor's top surface is at `-0.5`: the body is centred at `-1` and its
    // half-height is `0.5`, so the box, whose bottom face starts at `0.5`, is a
    // full metre clear of it.
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

/// A world with nothing in it, for the tests about creation and validity.
fn makeEmptyWorld() !box2d.WorldId {
    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    return box2d.createWorld(&world_def);
}

/// One world step, in this fixture's terms.
fn step(world: box2d.WorldId) void {
    box2d.worldStep(world, time_step, sub_steps);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a released box follows the ballistic trajectory after each step" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // Ten steps is well inside the free-fall regime: the box has fallen about
    // fourteen centimetres of the metre it starts above the floor, so the broad
    // phase has paired nothing and the solver has moved one free body.
    var n: u32 = 0;
    while (n < 10) : (n += 1) {
        step(fixture.world);
        const position = box2d.bodyPosition(fixture.body);
        try expectFallHeight(position.y, n + 1);
        try expectHeight(position.x, 0);

        const velocity = box2d.bodyLinearVelocity(fixture.body);
        try expectSpeed(velocity.y, ballisticSpeed(n + 1));
        try expectSpeed(velocity.x, 0);

        // Nothing has fallen far enough to touch, and no contact exists, so this
        // is the check that the trajectory is being applied to a regime where
        // gravity is the whole story rather than one term of it.
        if (box2d.bodyContactCapacity(fixture.body) != 0) return error.UnexpectedEarlyContact;
    }
}

test "a body is untouched until it is stepped, and gravity scale zero leaves it there" {
    nativeReady();
    const fixture = try makeFixture();
    defer fixture.destroy();

    // The first world step on its own, so that the two facts the fall rests on
    // are stated separately: creation leaves the body exactly where it was
    // released, and a single step moves it by gravity alone.
    try expectHeight(box2d.bodyPosition(fixture.body).y, release_height);
    try expectSpeed(box2d.bodyLinearVelocity(fixture.body).y, 0);

    step(fixture.world);
    try expectFallHeight(box2d.bodyPosition(fixture.body).y, 1);
    try expectSpeed(box2d.bodyLinearVelocity(fixture.body).y, ballisticSpeed(1));

    // A body with gravity scale zero is not moved by gravity at all: the exact
    // boundary of `gravityScale` (`include/box2d/types.h:205`), and one that a
    // free-fall oracle alone would not notice.
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

    // The box is at (0, 1) with half-height 0.5, so its top face is the plane
    // y = 1.5 exactly. A ray from (0, 10) translated by (0, -20) reaches that
    // plane after (10 - 1.5)/20 = 0.425 of its length, and nowhere else on the
    // way down can it meet the box's surface.
    const hit = box2d.worldCastRayClosest(
        fixture.world,
        box2d.vec2(0, 10),
        box2d.vec2(0, -20),
        box2d.defaultQueryFilter(),
    );
    if (!hit.hit) return error.MissedRay;
    try expectHeight(hit.point.y, 1.5);
    try expectHeight(hit.point.x, 0);
    // The top face's outward normal points along +y.
    try expectHeight(hit.normal.y, 1);
    try expectHeight(hit.fraction, 0.425);

    // A ray eleven metres to the side of the box passes it entirely. The box's
    // half-width is 0.5, so this clears its face by ten and a half metres rather
    // than grazing it.
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

    // Inside, exactly on the centre line and half a box-width in from the face.
    if (!box2d.shapeTestPoint(shape, box2d.vec2(0.25, release_height))) {
        return error.PointInsideRejected;
    }
    // Outside, on the same line: one and a half half-extents from the centre.
    if (box2d.shapeTestPoint(shape, box2d.vec2(0.75, release_height))) {
        return error.PointOutsideAccepted;
    }

    // The reported AABB is conservative. It must contain the square without
    // fixing Box2D's speculative-contact margin.
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

    // Three shapes on one body, so the slice length is the only thing that decides
    // how many come back. This is the documented silent truncation of
    // `bodyShapes`, tested at its boundary: the answer is the capacity, not the
    // count, and not an error.
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

    // The same ids in the same order, because the shorter buffer is a prefix of
    // the longer one. Comparing the ids is what makes this a test of truncation
    // rather than of counting.
    for (complete[0..written_short], short) |have, got| {
        if (!box2d.idsEqual(have, got)) return error.ShapeOrderChanged;
    }

    // The floor carries exactly one shape, and the accessor writes exactly that
    // many ids into a buffer sized from the reported count.
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

    // The next body lands in the freed slot, so the index is the same and only the
    // generation differs. That is what makes the stale handle above a real test
    // rather than an index-range check.
    const second = try box2d.createBody(world, &body_def);
    if (second.index1 != first.index1) return error.IndexWasNotReused;
    if (box2d.idsEqual(first, second)) return error.GenerationWasNotBumped;
    if (box2d.bodyIsValid(first)) return error.StaleGenerationAccepted;
    if (!box2d.bodyIsValid(second)) return error.ReusedBodyRejected;

    // Storing and loading a handle round-trips through the upstream bit packing,
    // which is a different representation from the struct and so can lose a
    // generation the struct kept.
    const stored = box2d.storeBodyId(second);
    if (!box2d.idsEqual(box2d.loadBodyId(stored), second)) {
        return error.BodyIdRoundTripFailed;
    }

    // The null handle is invalid, which is the answer `createBody` would have
    // given if it had declined.
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

    // A fresh world takes the freed slot, and the old handles stay invalid across
    // the reuse because the world generation was bumped when it was destroyed
    // (`src/world.c:354`).
    const replacement = try makeEmptyWorld();
    defer box2d.destroyWorld(replacement);
    if (replacement.index1 != world.index1) return error.WorldIndexWasNotReused;
    if (box2d.worldIsValid(world)) return error.StaleWorldGenerationAccepted;
    if (!box2d.worldIsValid(replacement)) return error.ReusedWorldRejected;
}

test "world creation is refused once all the slots are in use" {
    nativeReady();

    // `B2_MAX_WORLDS` is 128 (`src/constants.h:27`). The limit is a native-source
    // fact rather than a header constant, which is why it is written down here
    // with its source line instead of being read from the module.
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

    // The next request is the refusal, and it is the same null `b2WorldId`
    // upstream returns at `src/world.c:115-118`, mapped to one error.
    if (makeEmptyWorld()) |_| {
        for (worlds) |w| box2d.destroyWorld(w);
        return error.LimitNotEnforced;
    } else |err| {
        if (err != error.WorldLimitReached) {
            for (worlds) |w| box2d.destroyWorld(w);
            return err;
        }
    }

    // Freeing one slot makes room again, and the reused slot's new generation is
    // what keeps the destroyed handle from coming back.
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

    // A sensor straddling `y = 0.25`, a quarter of a metre thick, so its top face
    // is at `y = 0.375`. The released box starts with its bottom face at
    // `y = 0.5`, so nothing overlaps at first and the box has to fall 0.125 m
    // before it reaches the sensor. The floor's top surface is another 0.875 m
    // further down, so the box is still in free fall when it does.
    var sensor_body_def = box2d.defaultBodyDef();
    sensor_body_def.position = box2d.vec2(0, 0.25);
    const sensor_body = try box2d.createBody(fixture.world, &sensor_body_def);
    var sensor_shape_def = box2d.defaultShapeDef();
    sensor_shape_def.isSensor = true;
    sensor_shape_def.enableSensorEvents = true;
    const sensor_box = box2d.makeBox(2, 0.125);
    const sensor = try box2d.createPolygonShape(sensor_body, &sensor_shape_def, &sensor_box);

    // Nothing overlaps yet, so there is nothing to report. The box is 0.125 m
    // clear of the sensor and one step moves it under two millimetres.
    step(fixture.world);
    if (box2d.sensorBeginEvents(fixture.world).len != 0) return error.BeginEventBeforeOverlap;

    // Step until the overlap is reported rather than for a fixed count. The event
    // array belongs to one step (`include/box2d/types.h:1031-1033`), so a fixed
    // count would be reading a step that may be long past the one that produced
    // it. The bound is generous: falling the 0.125 m to the sensor takes about
    // ten steps and the remaining 0.875 m to the floor about seventeen more.
    var begin_count: usize = 0;
    var begin_sensor: box2d.ShapeId = box2d.null_shape_id;
    var begin_visitor: box2d.ShapeId = box2d.null_shape_id;
    var steps_taken: u32 = 0;
    while (steps_taken < 200) : (steps_taken += 1) {
        step(fixture.world);
        const begin = box2d.sensorBeginEvents(fixture.world);
        if (begin.len == 0) continue;
        // One visitor, one sensor: the event names both, and they are the pair
        // this fixture created.
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

    // Moving the sensor away ends the overlap, and the next step reports exactly
    // one end event naming it.
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

    // Before any step there is no move event array at all, so the answer is the
    // empty slice rather than a count of zero over an unread buffer.
    if (box2d.bodyMoveEvents(fixture.world).len != 0) return error.MoveEventBeforeStep;

    step(fixture.world);
    const moves = box2d.bodyMoveEvents(fixture.world);
    if (moves.len != 1) {
        std.debug.print("expected one move event, saw {d}\n", .{moves.len});
        return error.WrongMoveEventCount;
    }
    if (!box2d.idsEqual(moves[0].bodyId, fixture.body)) return error.MoveEventWrongBody;
    if (moves[0].fellAsleep) return error.FellAsleepWithSleepDisabled;
    // The event carries the transform the body reached, which is the one the
    // accessor reports afterwards.
    const reported = box2d.bodyTransform(fixture.body);
    try expectHeight(moves[0].transform.p.y, reported.p.y);

    // A second step moves the same body and produces the same one event, so the
    // array is not accumulating across steps: it is this step's, read before the
    // next one.
    step(fixture.world);
    const again = box2d.bodyMoveEvents(fixture.world);
    if (again.len != 1) return error.MoveEventAccumulated;
    try expectFallHeight(again[0].transform.p.y, 2);
}

/// Shape count for a body, read through the truncating accessor so that the two
/// are checked against each other.
///
/// `ids` is the caller's buffer because the accessor writes into it; a caller that
/// sized the buffer from `bodyShapeCount` gets the answer twice over, once as a
/// count and once as what the accessor wrote.
fn countShapes(body: box2d.BodyId, ids: []box2d.ShapeId) !c_int {
    const capacity = box2d.bodyShapeCount(body);
    if (capacity < 0 or ids.len < @as(usize, @intCast(capacity))) {
        return error.ImplausibleShapeCount;
    }
    const written = box2d.bodyShapes(body, ids[0..@intCast(capacity)]);
    if (written != @as(usize, @intCast(capacity))) return error.ShapeListShort;
    return capacity;
}

/// The body's shape ids, as a slice the caller supplied.
fn shapeCountInto(body: box2d.BodyId, out: []box2d.ShapeId) c_int {
    return @intCast(box2d.bodyShapes(body, out));
}

// ---------------------------------------------------------------------------
// Geometry and mass, checked against closed forms
// ---------------------------------------------------------------------------

test "a convex hull built from a square has unit area" {
    nativeReady();

    // The shoelace formula is the oracle here, and it is independent of
    // Box2D's hull algorithm: a polygon is the shape the hull produces, and the
    // area is a property of the vertices alone.
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

    // Fewer than three points cannot bound a hull, which is upstream's zero-count
    // return at `src/hull.c:92-96` and the only reason `HullNotConvex` exists.
    const two_points = [_]box2d.Vec2{ box2d.vec2(0, 0), box2d.vec2(1, 1) };
    if (box2d.computeHull(&two_points)) |_| {
        return error.DegenerateHullAccepted;
    } else |err| {
        if (err != error.HullNotConvex) return err;
    }
}

test "circle mass and length-and-normalize are their closed forms" {
    nativeReady();

    // A unit circle of unit density: area pi, mass pi, and for a disc the
    // rotational inertia about its centre is m r^2 / 2.
    const disc = box2d.circle(box2d.vec2_zero, 1);
    const mass = box2d.computeCircleMass(&disc, 1);
    try expectHeight(mass.mass, std.math.pi);
    try expectHeight(mass.rotationalInertia, std.math.pi / 2.0);
    try expectHeight(mass.center.x, 0);
    try expectHeight(mass.center.y, 0);

    // The 3-4-5 triangle: length 5, and the unit direction is (0.6, 0.8). This is
    // the one out-parameter pair upstream splits across a return value and a
    // pointer, so the answer is exactly one thing and has to be exact.
    const answer = box2d.getLengthAndNormalize(box2d.vec2(3, 4));
    try expectHeight(answer.length, 5);
    try expectHeight(answer.direction.x, 0.6);
    try expectHeight(answer.direction.y, 0.8);

    // A zero vector has no direction, and upstream returns the zero vector rather
    // than a NaN, which is what makes this safe to call without a length test.
    const degenerate = box2d.getLengthAndNormalize(box2d.vec2_zero);
    try expectHeight(degenerate.length, 0);
    try expectHeight(degenerate.direction.x, 0);
    try expectHeight(degenerate.direction.y, 0);

    // A unit rotation is one at every angle, and rotating the x axis by a quarter
    // turn gives the y axis exactly.
    const quarter = box2d.makeRot(std.math.pi / 2.0);
    const rotated = box2d.rotateVector(quarter, box2d.vec2(1, 0));
    try expectHeight(rotated.x, 0);
    try expectHeight(rotated.y, 1);
}

test "the dynamic tree returns exactly the proxies inside the query box" {
    nativeReady();

    var tree = box2d.dynamicTreeCreate();
    defer box2d.dynamicTreeDestroy(&tree);

    // Three disjoint unit boxes on a line, three metres apart.
    const a = box2d.dynamicTreeCreateProxy(&tree, unitAabb(0), 1, 100);
    const b = box2d.dynamicTreeCreateProxy(&tree, unitAabb(3), 1, 200);
    const c = box2d.dynamicTreeCreateProxy(&tree, unitAabb(6), 1, 300);
    if (a < 0 or b < 0 or c < 0) return error.ProxyCreationFailed;
    if (box2d.dynamicTreeProxyCount(&tree) != 3) return error.WrongProxyCount;

    // A convex query spanning the end proxies also contains the middle one.
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

    // A box around the middle proxy alone returns it and nothing else.
    var single = QueryLog{};
    _ = box2d.dynamicTreeQuery(
        &tree,
        box2d.makeAabb(&[_]box2d.Vec2{ box2d.vec2(2.5, -1), box2d.vec2(3.5, 1) }, 0),
        ~@as(u64, 0),
        @as(*const box2d.TreeQueryCallbackFn, &QueryLog.callback),
        &single,
    );
    if (single.count != 1 or single.saw[0] != 200) return error.WrongNarrowQueryResult;

    // Moving the third proxy outside leaves the first two in the query.
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

    // Destroying a proxy removes it from the count as well.
    box2d.dynamicTreeDestroyProxy(&tree, b);
    if (box2d.dynamicTreeProxyCount(&tree) != 2) return error.ProxyNotDestroyed;

    // The tree's own invariants hold after all of that.
    box2d.dynamicTreeValidate(&tree);
    box2d.dynamicTreeValidateNoEnlarged(&tree);
}

fn unitAabb(center_x: f32) box2d.Aabb {
    return .{
        .lowerBound = box2d.vec2(center_x - 0.5, -0.5),
        .upperBound = box2d.vec2(center_x + 0.5, 0.5),
    };
}

/// What the dynamic tree query callback records, through the `void *` context
/// Box2D passes it.
///
/// The callback has the C signature `bool (int, uint64_t, void *)`, so the
/// context is the only way to get an answer out. This is that answer.
const QueryLog = struct {
    /// How many proxies the tree handed to `callback`. This is the caller's own
    /// count and not Box2D's, so it is a `usize` even though the proxy id in the
    /// callback is an `int`.
    count: usize = 0,
    /// The user data of each proxy seen, in the order the tree visited them.
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

    // No version pin here. The generation this build compiled against is not a
    // fact a test in this tree re-establishes: it is fixed by `build.zig`'s
    // `upstream_version` and by the headers that were translated against it.
    // The one place a *provider* can disagree about it is already closed at load
    // time, where `runtime/library.zig`'s `Config.validate` refuses a
    // `b2GetVersion()` that is not major 3. What is left to check is process
    // state: globals another run or another test could have moved.

    // The length scale is a process global this build's translation declared, and
    // upstream initialises it to 1 (`src/math_functions.c`). A value other than 1
    // would mean something already called `setLengthUnitsPerMeter`, which is the
    // one process-wide effect a test must not have.
    const units = box2d.getLengthUnitsPerMeter();
    if (@abs(units - 1.0) > 1e-6) {
        std.debug.print("length units per meter is {d}, expected 1\n", .{units});
        return error.UnexpectedLengthUnits;
    }

    // The library allocates through its own arena, and the count only ever grows.
    // A negative answer would be the null-return shape of an `int`, so the
    // boundary is checked here rather than a value.
    if (box2d.getByteCount() < 0) return error.NegativeByteCount;
}
