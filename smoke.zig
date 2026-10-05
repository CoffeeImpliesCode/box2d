// SPDX-License-Identifier: MIT
//
//! A runnable, deterministic demonstration of the Box2D facade.
//!
//! `zig build smoke` runs this. There is no input, no clock, no random seed and
//! no host-dependent value anywhere in the output, so the same lines come out
//! every time.
//!
//! ## What it is a check of, not a demo of
//!
//! Every expectation below is derived on paper, not a value this program
//! computed and printed for comparison:
//!
//!   * the released box's height after `n` steps lies inside the discretisation
//!     envelope around the free-fall trajectory `y0 - g t^2 / 2`, and its
//!     downward speed is exactly `g t`. The height is a bound rather than an
//!     equality because how a solver subdivides a step is not this program's
//!     business; `tests.zig` derives the envelope and states what it rejects;
//!   * the ray's hit point is the box's top face at `y = 1.5`, and the fraction
//!     `(10 - 1.5) / 20 = 0.425`;
//!   * a unit circle of unit density has mass `pi` and rotational inertia
//!     `pi / 2`;
//!   * the 3-4-5 triangle has length 5 and unit direction `(0.6, 0.8)`;
//!   * a hull of the four corners of a unit square encloses area 1 by the
//!     shoelace formula, computed here from the vertices the library returned.
//!
//! A mismatch prints both sides and exits non-zero, so this is a gate and not a
//! demonstration. Where `f32` arithmetic requires one, a tolerance is used. The
//! free fall is checked against the envelope rather than against a value: after
//! ten steps the height must be within 3.5e-3 m of 0.861 m, where a body that
//! was never stepped is at 1 and one under half the gravity is at 0.93.
//!
//! ## Two configurations
//!
//! In a linked build the world is usable immediately. In a `-Druntime` build the
//! provider is named on the command line (`--provider <path>`) or in
//! `BOX2D_TEST_PROVIDER`, and the program says which configuration it is in the
//! first two lines. Nothing is loaded by default and no other file is tried.

const std = @import("std");
const box2d = @import("box2d");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Gravity magnitude, m/s^2. Set explicitly rather than inherited so this
/// program's expected values cannot move if upstream's default changes.
const gravity: f32 = 10.0;

/// The world time step, seconds.
const time_step: f32 = 1.0 / 60.0;

/// Solver sub-steps per world step, four at 60 Hz as upstream recommends
/// (`include/box2d/box2d.h:35-38`).
const sub_steps: c_int = 4;

/// How many world steps to simulate. Ten is inside the free-fall regime: the box
/// falls under fifteen centimetres of the metre it starts above the floor, so no
/// contact exists and gravity alone is the whole story.
const steps: u32 = 10;

/// Half-extents of the dynamic box: a unit square.
const box_half: f32 = 0.5;

/// Where the box starts.
const release_height: f32 = 1.0;

/// The sub-step the solver integrates over, seconds: the world time step split
/// into `sub_steps` equal parts.
const sub_step: f32 = time_step / @as(f32, @floatFromInt(sub_steps));

/// The `f32` slack the fall envelope carries on top of its discretisation term,
/// metres. Ten steps accumulate a handful of `f32` roundings near 1 m, so this
/// is several times what they can add without being wide enough to accept a
/// wrong answer.
const rounding: f32 = 1e-5;

/// How far two ordinary values may differ and still be the same answer.
const tolerance: f32 = 1e-4;

/// The height a body released from rest at `release_height` passes through after
/// `n` world steps under `gravity`, metres.
///
/// `y0 - g t^2 / 2` with `t = n * time_step`. This is the continuous trajectory,
/// and it is a property of the motion rather than of any particular stepper: see
/// `fallEnvelope` for what the library is allowed to differ from it by.
fn ballisticHeight(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return release_height - 0.5 * gravity * t * t;
}

/// The downward speed after `n` world steps, m/s.
///
/// `-g t`. Constant acceleration from rest has this velocity whatever the step
/// size, so it is checked outright rather than within a bound.
fn ballisticSpeed(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return -gravity * t;
}

/// How far an integration over sub-steps of `sub_step` may sit from
/// `ballisticHeight(n)`, metres.
///
/// A stepper that adds `g h` to the velocity and `v h` to the position each
/// sub-step lags the continuous trajectory by at most one sub-step's worth of
/// velocity, `g h t / 2`. That is the whole discretisation term; `rounding` is
/// the `f32` slack underneath it.
///
/// It is still twenty times narrower than the nearest wrong answer: at ten steps
/// a body that was never stepped is 0.14 m away and one under half the gravity is
/// 0.07 m away.
fn fallEnvelope(n: u32) f32 {
    const t = @as(f32, @floatFromInt(n)) * time_step;
    return 0.5 * gravity * sub_step * t + rounding;
}

/// Run the demonstration and exit non-zero on the first value that does not match
/// the expectation derived for it.
pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime box2d.runtime_loaded) {
        try box2d.load(.{ .path = try providerRequest(init) });
    }

    try w.print("box2d smoke\n", .{});
    // Through the raw route, so this line names the C library this build reached
    // rather than a constant compiled into this program.
    {
        const version = box2d.getVersion();
        try w.print("{s} C library reports version {d}.{d}.{d}\n", .{
            if (box2d.runtime_loaded) "loaded" else "linked",
            version.major,
            version.minor,
            version.revision,
        });
    }

    // --- geometry and mass, before any world exists ------------------------

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

    // --- the fixture world --------------------------------------------------

    var world_def = box2d.defaultWorldDef();
    world_def.gravity = box2d.vec2(0, -gravity);
    world_def.enableSleep = false;
    const world = box2d.createWorld(&world_def) catch |err| {
        try w.print("could not create a world: {t}\n", .{err});
        return err;
    };
    defer box2d.destroyWorld(world);

    // A static floor centred at y = -1 with a half-height of 0.5, so its top
    // surface is at y = -0.5 and the released box, whose bottom face starts at
    // y = 0.5, is a full metre clear of it: nothing touches for the first ten
    // steps.
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

    // A ray from (0, 10) down by 20 reaches the top face y = 1.5 after 0.425 of
    // its length, and a ray eleven metres to the side misses entirely.
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

    // --- the free fall ------------------------------------------------------

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

    // --- the ownership transitions, stated by their effects -----------------

    // The move events this last step buffered name the body that moved, and the
    // static floor is not among them.
    const moves = box2d.bodyMoveEvents(world);
    try check(w, "move events", @floatFromInt(moves.len), 1);
    try w.print("the only body that moved is \"{s}\"\n", .{box2d.bodyName(moves[0].bodyId)});

    // A destroyed handle stops being valid, and the freed slot's next occupant is
    // a different handle because the generation moved.
    var shapes: [4]box2d.ShapeId = undefined;
    if (box2d.bodyShapes(body, &shapes) != 1) return error.WrongShapeCount;
    const shape = shapes[0];
    try check(w, "shape valid before destroy", if (box2d.shapeIsValid(shape)) 1 else 0, 1);
    box2d.destroyShape(shape, true);
    try check(w, "shape valid after destroy", if (box2d.shapeIsValid(shape)) 1 else 0, 0);

    // A world beyond the 128 slots is refused rather than half built. The fixture
    // world above is still alive, so it occupies one of them and the loop below
    // fills the remaining 127 before the refusal is expected.
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

/// The area a polygon encloses, from its vertices alone.
///
/// The shoelace formula, so the number is a property of the points rather than
/// of anything Box2D computed: this is the independent answer the hull check
/// above compares against.
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
/// The finiteness test comes first and separately so that a NaN reports itself
/// as one instead of as a difference that quietly compares false.
fn checkWithin(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32, bound: f32) !void {
    try w.print("{s: <24}{d:.6}\n", .{ what, got });
    if (std.math.isFinite(got) and @abs(got - expected) <= bound) return;
    std.debug.print("{s}: expected {d} within {e}, computed {d}\n", .{
        what, expected, bound, got,
    });
    return error.SmokeCheckFailed;
}

/// Print one value and fail if it is not within `tolerance` of the expected one.
fn check(w: *std.Io.Writer, what: []const u8, got: f32, expected: f32) !void {
    return checkWithin(w, what, got, expected, tolerance);
}

/// The provider this run should load, from `--provider <path>` or from
/// `BOX2D_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back to
/// a linked copy: a runtime-loading build that was not told which file to load
/// reports that it was not told, rather than loading something else.
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export BOX2D_TEST_PROVIDER with a shared object exporting Box2D's " ++
            "entry points. Nothing is loaded by default and no other file is " ++
            "tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}