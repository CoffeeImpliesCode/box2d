// SPDX-License-Identifier: MIT
//
//! Consumes the `box2d` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("box2d")` here. No path reaches into the library's
//! own tree, so if this builds and produces the answers below, the module
//! contract is real.
//!
//! ## Why these answers and not others
//!
//! This is not a version print and not a round trip through the same code. Each
//! expected value is worked out on paper and compared with what the library
//! returned:
//!
//!   * **Free fall.** A box released at rest at `y = 1` under gravity `(0, -10)`,
//!     stepped ten times at 1/60 s in four sub-steps, is inside the
//!     discretisation envelope around `y0 - g t^2 / 2` with downward speed
//!     `g t`. The height is a bound rather than an equality because subdividing a
//!     step is the solver's business: any stepper that adds `g h` to the velocity
//!     and `v h` to the position trails the continuous trajectory by at most
//!     `g h t / 2`. A body that were never stepped must still be at `1`, which is
//!     the other half of the same claim.
//!   * **A stale handle.** Destroying a body invalidates its id, and the next
//!     body takes the same index with a different generation. An
//!     implementation that compared only the index would report the stale handle
//!     as live.
//!   * **The creation boundary.** The 129th world is refused with
//!     `WorldLimitReached`; freeing a slot makes room again.
//!   * **A borrowed event slice.** One sensor overlapping one visitor produces
//!     exactly one begin event naming both, and moving the sensor produces exactly
//!     one end event.
//!   * **Geometry and mass.** A unit circle of unit density has mass `pi` and
//!     rotational inertia `pi/2`; the hull of a unit square encloses area 1 by the
//!     shoelace formula, computed here from the vertices the library returned; the
//!     vector `(3, 4)` has length 5 and unit direction `(0.6, 0.8)`.
//!
//! Any mismatch exits non-zero. The raw route is used for exactly one thing: the
//! version line, so it names the C library this build actually reached rather
//! than a constant compiled into this program.
//!
//! ## Two configurations
//!
//! The same source builds against a linked package and against a runtime-loaded
//! one. `box2d.runtime_loaded` is a comptime constant, so the difference is one
//! branch and no duplicated program: in the runtime-loaded build the provider is
//! named on the command line (`--provider <path>`) or in `BOX2D_TEST_PROVIDER`,
//! loaded once, and the same answers follow.

const std = @import("std");
const box2d = @import("box2d");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

const gravity: f32 = 10.0;
const time_step: f32 = 1.0 / 60.0;
const sub_steps: c_int = 4;
const steps: u32 = 10;
const box_half: f32 = 0.5;
const release_height: f32 = 1.0;

/// How far two ordinary numbers may differ and still be the same answer. Four to
/// six orders of magnitude above the `f32` rounding this accumulates over ten
/// steps, and orders of magnitude below any wrong answer.
const tolerance: f32 = 1e-4;

/// The `f32` slack `fallEnvelope` carries on top of its discretisation term,
/// metres. Ten steps accumulate a handful of roundings near 1 m, so this is
/// several times what they can add without being wide enough to accept a wrong
/// answer.
const rounding: f32 = 1e-5;

/// The sub-step the solver integrates over, seconds: the world time step split
/// into `sub_steps` equal parts.
const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

/// The height the released box passes through after `n` world steps, metres.
///
/// `y0 - g t^2 / 2` with `t = n * time_step`: the continuous trajectory of a body
/// released from rest under `gravity`, and a property of the motion rather than
/// of any stepper.
fn ballisticHeight(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return release_height - 0.5 * gravity * t * t;
}

/// The downward speed the released box has after `n` world steps, m/s.
///
/// `-g t`. Constant acceleration from rest gives this velocity at every step
/// size, so it is checked outright rather than within a bound.
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

/// Run every check and exit non-zero on the first answer that does not match the
/// expectation derived for it.
pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime box2d.runtime_loaded) {
        try box2d.load(.{ .path = try providerRequest(init) });
    }

    try w.print("box2d consumer\n", .{});
    // The raw route, for the one value that must come from the C library itself.
    {
        const version = box2d.getVersion();
        try w.print("{s} C library reports version {d}.{d}.{d}\n", .{
            if (box2d.runtime_loaded) "loaded" else "linked",
            version.major,
            version.minor,
            version.revision,
        });
    }

    // --- geometry and mass, with no world in existence ----------------------

    const corners = [_]box2d.Vec2{
        box2d.vec2(0, 0),
        box2d.vec2(1, 0),
        box2d.vec2(1, 1),
        box2d.vec2(0, 1),
    };
    const hull = box2d.computeHull(&corners) catch |err| {
        try w.print("a unit square is not a convex hull: {t}\n", .{err});
        return err;
    };
    const polygon = box2d.makePolygon(&hull, 0);
    try check(w, "shoelace area of the hull", shoelaceArea(&polygon), 1.0);

    const disc = box2d.circle(box2d.vec2_zero, 1);
    const disc_mass = box2d.computeCircleMass(&disc, 1);
    try check(w, "unit circle mass", disc_mass.mass, std.math.pi);
    try check(w, "unit circle inertia", disc_mass.rotationalInertia, std.math.pi / 2.0);

    const forty_five = box2d.getLengthAndNormalize(box2d.vec2(3, 4));
    try check(w, "length of (3, 4)", forty_five.length, 5);
    try check(w, "unit direction x of (3, 4)", forty_five.direction.x, 0.6);
    try check(w, "unit direction y of (3, 4)", forty_five.direction.y, 0.8);

    // Two points do not bound a hull, which is the boundary of the one error this
    // package can raise about geometry.
    const two_points = [_]box2d.Vec2{ box2d.vec2(0, 0), box2d.vec2(1, 1) };
    if (box2d.computeHull(&two_points)) |_| {
        try w.print("two points produced a hull\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        try w.print("two points refused with {t}\n", .{err});
    }

    // The fixture world lives in its own block so that it is destroyed before the
    // creation-boundary check below, which needs every world slot to itself.
    {
        var world_def = box2d.defaultWorldDef();
        world_def.gravity = box2d.vec2(0, -gravity);
        world_def.enableSleep = false;
        const world = box2d.createWorld(&world_def) catch |err| {
            try w.print("could not create a world: {t}\n", .{err});
            return err;
        };
        defer box2d.destroyWorld(world);

        try fixtureRun(w, world);
    }

    // --- the creation boundary ---------------------------------------------

    try w.print("refusing world 129 of 128\n", .{});
    const remaining = 128;
    var worlds: [remaining]box2d.WorldId = undefined;
    const plain_def = box2d.defaultWorldDef();
    var made: usize = 0;
    while (made < worlds.len) : (made += 1) {
        worlds[made] = box2d.createWorld(&plain_def) catch |err| {
            for (worlds[0..made]) |other| box2d.destroyWorld(other);
            try w.print("  world {d} was refused early: {t}\n", .{ made, err });
            return err;
        };
    }
    if (box2d.createWorld(&plain_def)) |_| {
        for (worlds) |other| box2d.destroyWorld(other);
        try w.print("  a 129th world was created, so the limit is not enforced\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        try w.print("  the 129th world was refused with {t}\n", .{err});
    }

    // Freeing one slot makes room again, and the reused slot carries a new
    // generation so the destroyed handle cannot come back.
    const freed = worlds[remaining - 1];
    box2d.destroyWorld(freed);
    if (box2d.worldIsValid(freed)) {
        try w.print("  a destroyed world is still valid\n", .{});
        return error.ConsumerCheckFailed;
    }
    const reopened = box2d.createWorld(&plain_def) catch |err| {
        for (worlds[0 .. remaining - 1]) |other| box2d.destroyWorld(other);
        try w.print("  the freed slot was not reusable: {t}\n", .{err});
        return err;
    };
    if (reopened.index1 != freed.index1) {
        try w.print("  the freed slot was taken by a different index\n", .{});
        return error.ConsumerCheckFailed;
    }
    if (box2d.worldIsValid(freed)) {
        try w.print("  a stale world generation is still valid\n", .{});
        return error.ConsumerCheckFailed;
    }
    box2d.destroyWorld(reopened);
    for (worlds[0 .. remaining - 1]) |other| box2d.destroyWorld(other);

    try w.print("every value matched the expectation derived for it\n", .{});
    try w.flush();
}

/// Everything that needs a live world: the fall, the borrowed event slices, and
/// the handle transitions.
///
/// Split out of `main` so that `main` reads as the package's story and this reads
/// as the fixture's.
fn fixtureRun(w: *std.Io.Writer, world: box2d.WorldId) !void {

    // A static floor centred at y = -1 with a half-height of 0.5, so its top
    // surface is at y = -0.5 and the released box, whose bottom face starts at
    // y = 0.5, is a full metre clear of it: nothing touches.
    var floor_def = box2d.defaultBodyDef();
    floor_def.position = box2d.vec2(0, -1);
    const floor = box2d.createBody(world, &floor_def) catch |err| {
        try w.print("could not create the floor: {t}\n", .{err});
        return err;
    };
    {
        const shape_def = box2d.defaultShapeDef();
        const slab = box2d.makeBox(10, 0.5);
        _ = box2d.createPolygonShape(floor, &shape_def, &slab) catch |err| {
            try w.print("could not give the floor a shape: {t}\n", .{err});
            return err;
        };
    }

    var body_def = box2d.defaultBodyDef();
    body_def.type = box2d.c.b2_dynamicBody;
    body_def.position = box2d.vec2(0, release_height);
    body_def.name = "released-box";
    const body = box2d.createBody(world, &body_def) catch |err| {
        try w.print("could not create the box: {t}\n", .{err});
        return err;
    };
    {
        var shape_def = box2d.defaultShapeDef();
        shape_def.enableSensorEvents = true;
        const unit_box = box2d.makeBox(box_half, box_half);
        _ = box2d.createPolygonShape(body, &shape_def, &unit_box) catch |err| {
            try w.print("could not give the box a shape: {t}\n", .{err});
            return err;
        };
    }

    // Nothing has been stepped, so the box is exactly where it was released. A
    // half-applied creation would show up here as a different height.
    try check(w, "released height before stepping", box2d.bodyPosition(body).y, release_height);
    try check(w, "release speed before stepping", box2d.bodyLinearVelocity(body).y, 0);

    var n: u32 = 0;
    while (n < steps) : (n += 1) {
        box2d.worldStep(world, time_step, sub_steps);
        const position = box2d.bodyPosition(body);
        const velocity = box2d.bodyLinearVelocity(body);
        try checkWithin(
            w,
            "free fall height",
            position.y,
            ballisticHeight(n + 1),
            fallEnvelope(n + 1),
        );
        try check(w, "free fall speed", velocity.y, ballisticSpeed(n + 1));
    }

    // --- a borrowed event slice, read before the next step ------------------

    // A sensor whose top face is at y = -0.125, below where the ten free-fall
    // steps above left the box's bottom face, so nothing overlaps at first and
    // the box has to fall 0.625 m to reach it. The floor's top surface is at
    // y = -0.5, another 0.375 m further down.
    var sensor_body_def = box2d.defaultBodyDef();
    sensor_body_def.position = box2d.vec2(0, -0.25);
    const sensor_body = box2d.createBody(world, &sensor_body_def) catch |err| {
        try w.print("could not create the sensor body: {t}\n", .{err});
        return err;
    };
    var sensor_shape_def = box2d.defaultShapeDef();
    sensor_shape_def.isSensor = true;
    sensor_shape_def.enableSensorEvents = true;
    const sensor_box = box2d.makeBox(2, 0.125);
    const sensor = box2d.createPolygonShape(sensor_body, &sensor_shape_def, &sensor_box) catch |err| {
        try w.print("could not create the sensor: {t}\n", .{err});
        return err;
    };

    box2d.worldStep(world, time_step, sub_steps);
    if (box2d.sensorBeginEvents(world).len != 0) {
        try w.print("a sensor reported an overlap before anything reached it\n", .{});
        return error.ConsumerCheckFailed;
    }

    // Step until the overlap is reported. The event array belongs to one step, so
    // a fixed step count would be reading a step that may be long past the one
    // that produced it. Two hundred is far beyond what the box needs: it reaches
    // the sensor about eleven steps from here and would reach the floor about six
    // steps after that.
    var begin_count: usize = 0;
    var begin_sensor: box2d.ShapeId = box2d.null_shape_id;
    n = 0;
    while (n < 200) : (n += 1) {
        box2d.worldStep(world, time_step, sub_steps);
        const begin = box2d.sensorBeginEvents(world);
        if (begin.len == 0) continue;
        begin_count = begin.len;
        begin_sensor = begin[0].sensorShapeId;
        break;
    }
    try check(w, "sensor begin events", @floatFromInt(begin_count), 1);
    if (!box2d.idsEqual(begin_sensor, sensor)) {
        try w.print("the begin event named a different sensor\n", .{});
        return error.ConsumerCheckFailed;
    }

    box2d.bodySetTransform(sensor_body, box2d.vec2(50, -0.25), box2d.rot_identity);
    box2d.worldStep(world, time_step, sub_steps);
    try check(w, "sensor end events", @floatFromInt(box2d.sensorEndEvents(world).len), 1);

    // --- the handle transitions --------------------------------------------

    // `bodyShapes` returns how many ids it wrote into the caller's slice, so
    // the first id sits at index zero: `src/body.c:1817` ends the walk at
    // `capacity` and `src/body.c:1827` returns that count, which is a count of
    // writes and not a position. The released box has carried the same single
    // polygon since it was created, so the returned count says which id this is
    // and says that nothing was truncated.
    var shapes: [4]box2d.ShapeId = undefined;
    const written = box2d.bodyShapes(body, &shapes);
    if (written != 1) {
        try w.print("the released box reported {d} shapes, not the one it was given\n", .{written});
        return error.ConsumerCheckFailed;
    }
    const shape = shapes[0];
    if (!box2d.shapeIsValid(shape)) {
        try w.print("a freshly created shape is not valid\n", .{});
        return error.ConsumerCheckFailed;
    }
    box2d.destroyShape(shape, true);
    if (box2d.shapeIsValid(shape)) {
        try w.print("a destroyed shape is still valid\n", .{});
        return error.ConsumerCheckFailed;
    }

    const index_before = body.index1;
    box2d.destroyBody(body);
    if (box2d.bodyIsValid(body)) {
        try w.print("a destroyed body is still valid\n", .{});
        return error.ConsumerCheckFailed;
    }
    const reused = box2d.createBody(world, &body_def) catch |err| {
        try w.print("could not create the replacement body: {t}\n", .{err});
        return err;
    };
    if (reused.index1 != index_before) {
        try w.print("the freed slot was not reused, so this run proved less than it claims\n", .{});
        return error.ConsumerCheckFailed;
    }
    if (box2d.bodyIsValid(body)) {
        try w.print("a stale generation is still valid\n", .{});
        return error.ConsumerCheckFailed;
    }
    try w.print("stale handle refused after the slot was reused\n", .{});
}

/// The area a polygon encloses, from its vertices alone.
///
/// The shoelace formula, so this is a property of the points rather than of
/// anything Box2D computed, which is what makes it an independent answer.
fn shoelaceArea(polygon: *const box2d.Polygon) f32 {
    const count: usize = @intCast(polygon.count);
    var twice_area: f32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const a = polygon.vertices[i];
        const b = polygon.vertices[(i + 1) % count];
        twice_area += a.x * b.y - b.x * a.y;
    }
    return @abs(twice_area) / 2;
}

/// Print one value and fail if it is not within `bound` of the expected one.
///
/// The finiteness test comes first and separately so that a NaN reports itself as
/// one instead of as a difference that quietly compares false.
fn checkWithin(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32, bound: f32) !void {
    try w.print("{s: <34}{d:.6}\n", .{ what, got });
    if (std.math.isFinite(got) and @abs(got - expected) <= bound) return;
    std.debug.print("{s}: expected {d} within {e}, computed {d}\n", .{
        what, expected, bound, got,
    });
    return error.ConsumerCheckFailed;
}

/// Print one value and fail if it is not within `tolerance` of the expected one.
fn check(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32) !void {
    return checkWithin(w, what, got, expected, tolerance);
}

/// The provider this run should load, from `--provider <path>` or from
/// `BOX2D_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build that
/// was not told which file to load says so rather than loading something else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("BOX2D_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export BOX2D_TEST_PROVIDER with a shared object exporting Box2D's " ++
            "entry points. Nothing is loaded by default and no other file is " ++
            "tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}