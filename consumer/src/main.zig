// SPDX-License-Identifier: MIT
//
//! Example consumer of the public `box2d` module.
//! Checks representative physics, handle, sensor, and geometry results.

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

/// Absolute tolerance for floating-point comparisons.
const tolerance: f32 = 1e-4;

/// Additional floating-point slack, in metres.
const rounding: f32 = 1e-5;

/// Duration of one solver sub-step, in seconds.
const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

/// Continuous free-fall height after `n` world steps.
fn ballisticHeight(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return release_height - 0.5 * gravity * t * t;
}

/// Downward speed after `n` world steps.
fn ballisticSpeed(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return -gravity * t;
}

/// Height error bound after `n` semi-implicit steps, including rounding slack.
fn fallEnvelope(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return 0.5 * gravity * sub_step * t + rounding;
}

/// Run every check and fail on the first mismatch.
pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime box2d.runtime_loaded) {
        try box2d.load(.{ .path = try providerRequest(init) });
    }

    try w.print("box2d consumer\n", .{});
    // Read the version from the native library.
    {
        const version = box2d.getVersion();
        try w.print("{s} C library reports version {d}.{d}.{d}\n", .{
            if (box2d.runtime_loaded) "loaded" else "linked",
            version.major,
            version.minor,
            version.revision,
        });
    }

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

    // Two points cannot form a hull.
    const two_points = [_]box2d.Vec2{ box2d.vec2(0, 0), box2d.vec2(1, 1) };
    if (box2d.computeHull(&two_points)) |_| {
        try w.print("two points produced a hull\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        try w.print("two points refused with {t}\n", .{err});
    }

    // Destroy the fixture world before checking the world limit.
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

    // Reused slots must carry a different generation.
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

/// Runs world-dependent fall, sensor, and handle checks.
fn fixtureRun(w: *std.Io.Writer, world: box2d.WorldId) !void {

    // Keep the floor below the box during the initial fall check.
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

    // Check the initial transform before stepping.
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

    // The sensor starts below the box's current free-fall position.
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

    // Read events after each step; the event slice belongs to that step.
    // The bound exceeds the steps needed for the box to reach the sensor.
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

    // `bodyShapes` returns a count, so the first written ID is at index zero.
    // One expected shape fits in the four-entry buffer without truncation.
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

/// Independent polygon area from its vertices using the shoelace formula.
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

/// Print a value and fail when it is outside `bound`.
/// Check finiteness first so NaN cannot pass the comparison.
fn checkWithin(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32, bound: f32) !void {
    try w.print("{s: <34}{d:.6}\n", .{ what, got });
    if (std.math.isFinite(got) and @abs(got - expected) <= bound) return;
    std.debug.print("{s}: expected {d} within {e}, computed {d}\n", .{
        what, expected, bound, got,
    });
    return error.ConsumerCheckFailed;
}

/// Check a value against the shared tolerance.
fn check(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32) !void {
    return checkWithin(w, what, got, expected, tolerance);
}

/// Get the provider from `--provider` or `BOX2D_TEST_PROVIDER`.
/// No default location is searched.
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

/// Report the missing runtime provider configuration.
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
