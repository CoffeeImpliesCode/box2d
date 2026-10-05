/* SPDX-License-Identifier: MIT
 *
 * The one C translation unit this package authors that upstream does not ship.
 * It gives the translated header surface a linkable `b2MakeAABB` without
 * restating the algorithm.
 *
 * Why it exists
 * -------------
 * The six public headers declare 73 `B2_INLINE` functions between them: 63 in
 * `include/box2d/math_functions.h` and 10 in `include/box2d/id.h`, none in
 * `base.h`, `box2d.h`, `collision.h` or `types.h`. `include/box2d/base.h:33`
 * makes `B2_INLINE` `static inline` in C, so each of those is a private copy
 * in every translation unit that includes the header, and none of them puts a
 * name in the archive. Upstream needs nothing more than that: `src/world.c:2159`
 * is `b2MakeAABB`'s only caller, and it is reached through the header.
 *
 * This package needs one thing more. `zig build` runs `translate-c` over
 * `zig/translate.h`, which includes the six public headers whole, and the
 * result is the `c` module that `zig/root.zig` and every dependent import. It
 * compiles 72 of those 73 inline bodies into Zig. It cannot compile the
 * remaining one, because that body opens with `B2_ASSERT( count > 0 )`
 * (`math_functions.h:627`) and `B2_ASSERT` (`base.h:103-109`) calls
 * `B2_BREAKPOINT`, which is `__builtin_trap()` at `base.h:94`. The translation
 * reports
 *
 *     base.h:94:23: warning: TODO implement function '__builtin_trap' in
 *                                std.zig.c_builtins
 *     math_functions.h:625:18: warning: unable to translate function,
 *                                     demoted to extern
 *
 * and emits, in place of the body,
 *
 *     pub extern fn b2MakeAABB(arg_points: [*c]const b2Vec2, arg_count: c_int,
 *                               arg_radius: f32) callconv(.c) b2AABB;
 *
 * which is a declaration of a C symbol the archive does not contain. That is
 * not a warning to be tolerated but a hole: every Zig caller of
 * `box2d.c.b2MakeAABB`, including this package's own `box2d.makeAabb`, is an
 * undefined symbol at link time. This file is what fills it, and it is the
 * whole of it. One demoted extern is the complete list for `zig/translate.h`
 * at this pin, and every other `extern` in the translation is a `B2_API`
 * declaration that one of the 35 upstream translation units already defines --
 * which is why the linker names this function and no other.
 *
 * How it fills it
 * ---------------
 * A macro rename around the one `#include`, not a second implementation. The
 * name is defined, the header is included, the name is undefined, and the
 * exported definition below calls what the header's own text defined. The
 * assertion, the seed from `points[0]`, the loop, the `b2Min` and `b2Max` calls
 * and the `b2Sub`/`b2Add` growth by `radius` are upstream's bytes at upstream's
 * line numbers, compiled by the same compiler with the same `-std=gnu17`,
 * `-ffp-contract=off` and warning flags (`src/CMakeLists.txt:172-174`) as
 * `src/world.c`'s copy of them. Writing the body out here instead would create
 * a second algorithm free to drift from the header, which is the exact failure
 * this file exists to remove; and a weak or stub definition would let a caller
 * pass `count <= 0` and receive a box built by whatever the stub chose,
 * where the native assertion says the caller's state is not valid.
 *
 * The rename is undone immediately, so the private name is invisible to
 * everything below and no later `#include` can see it. It is also `static
 * inline`, so it occupies no symbol-table entry at all: the archive's exported
 * set is unchanged apart from the one name added here, which is Box2D's own and
 * is declared in a public header that this package already installs.
 *
 * Configuration and linkage
 * -------------------------
 * `build.zig` compiles this file into the core module itself, beside the 35
 * upstream translation units, so the same `-D` set, the same `libm`, the same
 * `-std=gnu17` and the same `-fvisibility=hidden` apply, and one definition
 * serves the static archive, the shared object and the second static archive a
 * dynamic build makes for upstream's own test suite. There is no bridge
 * archive and no per-mode build.
 *
 * `B2_API` is upstream's own export spelling, so it is the correct decoration
 * and no fork-specific one is invented. `include/box2d/base.h:11-23` gives it
 * `__declspec( dllexport )` under MSVC when `box2d_EXPORTS` is defined and
 * `__attribute__( ( visibility( "default" ) ) )` when `box2d_EXPORTS` is defined
 * without MSVC, and an empty expansion otherwise (`base.h:22-23`).
 * `build.zig` puts `box2d_EXPORTS` on this compile line exactly as it puts it
 * on `src/*.c` -- only for `-Dlinkage=dynamic`, which is upstream's own
 * `target_compile_definitions` split at `src/CMakeLists.txt:104-132` -- so a
 * shared build exports `b2MakeAABB` and a static build leaves it as an ordinary
 * archive member, which is how every other `B2_API` function in the archive is
 * delivered in both linkages.
 *
 * The Windows consumer half, `BOX2D_DLL` and therefore a `dllimport`
 * decoration, belongs to the consumer's compile line and to nothing here:
 * `src/CMakeLists.txt:131-133` sets it `INTERFACE`, and `zig/translate.h:44-79`
 * explains where this build puts it. Defining it in this file would make the
 * library import its own export from itself.
 */

/* Rename, include, unrename. The function this names is upstream's
 * `math_functions.h:625`, defined `static inline` by `base.h:33` under the name
 * below. `b2MakeAABB` is spelled exactly once in the six public headers, at
 * that definition, so the substitution reaches it and nothing around it. */
#define b2MakeAABB b2br_make_aabb_inline
#include <box2d/math_functions.h>
#undef b2MakeAABB

/* The prototype, ahead of the definition so the core's `-Wmissing-prototypes`
 * (`src/CMakeLists.txt:172-174`, `standard_flags` in `build.zig`) sees a
 * declaration for this non-static function rather than a bare one. Upstream's
 * headers give `b2MakeAABB` no `B2_API` declaration because it never needed a
 * linkable one; this is that declaration, and it is what lets the definition
 * compile clean under the same warning flags as the 35 sources beside it. */
B2_API b2AABB b2MakeAABB( const b2Vec2* points, int count, float radius );

/* The one definition, and it does nothing but call upstream's body. */
B2_API b2AABB b2MakeAABB( const b2Vec2* points, int count, float radius )
{
	return b2br_make_aabb_inline( points, count, radius );
}