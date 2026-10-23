// SPDX-License-Identifier: MIT
//
//! Deterministic demonstration of the Box2D facade.
//! Checks motion and geometry against independent expectations.
//! Runtime-loaded builds require `--provider <path>` or `BOX2D_TEST_PROVIDER`.

const std = @import("std");
const box2d = @import("box2d");

/// Error returned when a runtime-loading build has no provider.
const ConfigurationError = error{NoProviderConfigured};

const gravity: f32 = 10.0;

const time_step: f32 = 1.0 / 60.0;

const sub_steps: c_int = 4;

/// World steps simulated; ten stays within the free-fall interval.
const steps: u32 = 10;

const box_half: f32 = 0.5;

const release_height: f32 = 1.0;

const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

const rounding: f32 = 1e-5;

const tolerance: f32 = 1e-4;

/// Continuous free-fall height after `n` steps.
/// Independent of the solver's integration method.
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

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime box2d.runtime_loaded) {
        try box2d.load(.{ .path = try providerRequest(init) });
    }

    try w.print("box2d smoke\n", .{});
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
    try check(w, "hull vertices", @floatFromInt(polygon.count), 4);
    try check(w, "shoelace area", shoelaceArea(&polygon), 1.0);

    const disc = box2d.circle(box2d.vec2_zero, 1);
    const disc_mass = box2d.computeCircleMass(&disc, 1);
    try check(w, "unit circle mass", disc_mass.mass, std.math.pi);
    try check(w, "unit circle inertia", disc_mass.rotationalInertia, std.math.pi / 2.0);

    const forty_five = box2d.getLengthAndNormalize(box2d.vec2(3, 4));
    try check(w, "length of (3, 4)", forty_five.length, 5);
    try check(w, "unit x of (3, 4)", forty_five.direction.x, 0.6);
    try check(w, "unit y of (3, 4)", forty_five.direction.y, 0.8);

    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    world_def.enableSleep = false;
    const world = box2d.createWorld(&world_def) catch |err| {
        try w.print("could not create a world: {t}\n", .{err});
        return err;
    };
    defer box2d.destroyWorld(world);

    // The box begins one metre above the floor.
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
        const shape_def = box2d.defaultShapeDef();
        const unit_box = box2d.makeBox(box_half, box_half);
        _ = box2d.createPolygonShape(body, &shape_def, &unit_box) catch |err| {
            try w.print("could not give the box a shape: {t}\n", .{err});
            return err;
        };
    }

    try w.print("body name round-trip: \"{s}\"\n", .{box2d.bodyName(body)});

    // The vertical ray hits at y=1.5; the offset ray misses.
    const hit = box2d.worldCastRayClosest(
        world,
        box2d.vec2(0, 10),
        box2d.vec2(0, -20),
        box2d.defaultQueryFilter(),
    );
    if (!hit.hit) {
        try w.print("the downward ray missed a box directly below it\n", .{});
        return error.SmokeCheckFailed;
    }
    try check(w, "ray hit point y", hit.point.y, 1.5);
    try check(w, "ray fraction", hit.fraction, 0.425);
    try check(w, "ray normal y", hit.normal.y, 1);
    const miss = box2d.worldCastRayClosest(
        world,
        box2d.vec2(11, 10),
        box2d.vec2(0, -20),
        box2d.defaultQueryFilter(),
    );
    try check(w, "offset ray hit", if (miss.hit) 1 else 0, 0);

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

    // The last step's move event names the dynamic body, not the static floor.
    const moves = box2d.bodyMoveEvents(world);
    try check(w, "move events", @floatFromInt(moves.len), 1);
    try w.print("the only body that moved is \"{s}\"\n", .{box2d.bodyName(moves[0].bodyId)});

    // Destroying the shape invalidates its handle.
    var shapes: [4]box2d.ShapeId = undefined;
    if (box2d.bodyShapes(body, &shapes) != 1) return error.WrongShapeCount;
    const shape = shapes[0];
    try check(w, "shape valid before destroy", if (box2d.shapeIsValid(shape)) 1 else 0, 1);
    box2d.destroyShape(shape, true);
    try check(w, "shape valid after destroy", if (box2d.shapeIsValid(shape)) 1 else 0, 0);

    // The fixture occupies one slot; fill the other 127 before testing the limit.
    try w.print("refusing world 129 of 128\n", .{});
    const remaining = 127;
    var worlds: [remaining]box2d.WorldId = undefined;
    const plain_def = box2d.defaultWorldDef();
    var made: usize = 0;
    while (made < worlds.len) : (made += 1) {
        worlds[made] = box2d.createWorld(&plain_def) catch |err| {
            for (worlds[0..made]) |world_id| box2d.destroyWorld(world_id);
            try w.print("  world {d} was refused early: {t}\n", .{ made, err });
            return err;
        };
    }
    if (box2d.createWorld(&plain_def)) |_| {
        for (worlds) |world_id| box2d.destroyWorld(world_id);
        try w.print("  a 129th world was created, so the limit is not enforced\n", .{});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("  the 129th world was refused with {t}\n", .{err});
    }
    for (worlds) |world_id| box2d.destroyWorld(world_id);

    try w.print("every value matched the expectation derived for it\n", .{});
    try w.flush();
}

/// Computes area from the polygon vertices using the shoelace formula.
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

/// Prints the value and fails for non-finite or out-of-bound results.
fn checkWithin(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32, bound: f32) !void {
    try w.print("{s: <24}{d:.6}\n", .{ what, got });
    if (std.math.isFinite(got) and @abs(got - expected) <= bound) return;
    std.debug.print("{s}: expected {d} within {e}, computed {d}\n", .{
        what, expected, bound, got,
    });
    return error.SmokeCheckFailed;
}

fn check(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32) !void {
    return checkWithin(w, what, got, expected, tolerance);
}

/// Returns the provider path from `--provider <path>` or `BOX2D_TEST_PROVIDER`.
/// Runtime loading has no default provider or linked-copy fallback.
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

fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export BOX2D_TEST_PROVIDER with a shared object exporting Box2D's " ++
            "entry points. Nothing is loaded by default and no other file is " ++
            "tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
