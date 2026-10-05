// SPDX-License-Identifier: MIT

/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation
 * becomes the `c` module the Zig facade in zig/root.zig imports. Its whole job
 * is to name the six headers upstream declares as its public interface.
 *
 * Which headers those are, and why this file is a list and not a copy
 * --------------------------------------------------------------------
 * `src/CMakeLists.txt:63-70` names them: `BOX2D_API_FILES` is
 * `../include/box2d/base.h`, `box2d.h`, `collision.h`, `id.h`,
 * `math_functions.h` and `types.h`, and `src/CMakeLists.txt:208-211` is what
 * installs them, into `${CMAKE_INSTALL_INCLUDEDIR}/box2d`. All six are listed
 * below rather than only the umbrella `box2d/box2d.h`, because `box2d.h` is a
 * C++-style umbrella whose own `#include` lines happen to pull in the other
 * five today (`include/box2d/box2d.h:6-9`); naming them explicitly makes the
 * translated set the installed set rather than a fact about one header's
 * current include list, and it makes the count checkable against
 * `BOX2D_API_FILES`.
 *
 * No declaration is restated here. Each header is included whole, with its own
 * `#pragma once`, so translating this wrapper cannot disagree with a header by
 * omission, addition or drift. That includes the anonymous unions and the
 * `_Static_assert` uses that C17 is required for here: they arrive as upstream
 * wrote them.
 *
 * Why the angle-bracket form
 * -------------------------
 * `#include <box2d/base.h>` is a plain search: quoted includes resolve against
 * this file's own directory first, then against `-I` paths, then against the
 * system directories. There is no `box2d/` directory beside this file, so the
 * only thing that can satisfy these six lines is a `-I` path. `build.zig`
 * adds exactly one, `include/`, and adds it unconditionally, so the six lines
 * below resolve to this repository's headers in every configuration and mode.
 *
 * That matters because this package has no system-library mode. There is no
 * `-lbox2d` fallback here and no installed header to translate against, so a
 * system `box2d/` could only ever win if this build forgot its own include
 * path — and `WISDOM.md` W14 is about the opposite failure, a bundled header
 * translated against a system library. Stating it here keeps the one search
 * path this package has on the record.
 *
 * What the export macros are, and where they come from
 * ---------------------------------------------------
 * `include/box2d/base.h:11-23` is the only reader of `box2d_EXPORTS` (lowercase
 * — CMake's per-target define symbol for a target called `box2d`) and of
 * `BOX2D_DLL`:
 *
 *     _MSC_VER && box2d_EXPORTS  ->  __declspec(dllexport)
 *     _MSC_VER && BOX2D_DLL      ->  __declspec(dllimport)
 *     box2d_EXPORTS alone         ->  __attribute__((visibility("default")))
 *     neither                     ->  empty
 *
 * They are *not* defined here, and nothing in this header should define them:
 * upstream puts them on the compiler command line, not in the header, because
 * they describe how this particular library was linked rather than what the
 * interface is.
 *
 *   * `zig build -Dlinkage=static` (the default) defines neither. That is how
 *     a static archive is consumed on every platform, and it is what upstream's
 *     own CMake does, because CMake only adds `<target>_EXPORTS` for a shared
 *     library.
 *   * `zig build -Dlinkage=dynamic` defines `box2d_EXPORTS` on the library's own
 *     compile line, and `BOX2D_DLL` alone on this translation, and only for a
 *     Windows target. That is upstream's own `PRIVATE`/`INTERFACE` split:
 *     `target_compile_definitions(box2d INTERFACE BOX2D_DLL)` under
 *     `if (MSVC AND BUILD_SHARED_LIBS)` (`src/CMakeLists.txt:131-133`). The
 *     first branch above needs `_MSC_VER`, which MinGW does not define, so a
 *     MinGW shared build correctly takes the visibility attribute — which is
 *     also what upstream's MinGW shared build does.
 *   * The installed `box2d.pc` carries `-DBOX2D_DLL` in `Cflags` for a shared
 *     install, so a C consumer of this package gets the same answer from
 *     pkg-config without repeating the flag.
 *
 * On anything that is not MSVC both macros are unread and `B2_API` is the
 * visibility attribute instead, so the declarations below are identical in
 * every configuration. That is why `build.zig` defines `BOX2D_DLL` for Windows
 * only, and why this file stays silent about all of it.
 *
 * What is deliberately not here
 * -----------------------------
 * The internal headers. `src/*.h` is on the compile line of the library, the
 * upstream test suite and the benchmark tool — `test/CMakeLists.txt:29-30` adds
 * `${CMAKE_SOURCE_DIR}/src` to the test target for exactly that reason — but
 * upstream installs none of them (`src/CMakeLists.txt:208-211` lists only
 * `BOX2D_API_FILES`), so they are not part of this package's installed header
 * set and translating them would describe an interface no consumer of this
 * install can see.
 *
 * There is no generated or configuration header to name either.
 * `BOX2D_VALIDATE`, `BOX2D_DISABLE_SIMD` and `BOX2D_AVX2` are private defines
 * on the library's own compile line (`src/CMakeLists.txt:119-127`), they are
 * read only from `src/core.h:59,65`, and no public header's shape depends on
 * any of them. `NDEBUG` and `B2_ENABLE_ASSERT` at `include/box2d/base.h:101`
 * belong to the caller's own `-DNDEBUG`, which is what the optimize mode
 * supplies; this header neither sets nor unsets them.
 */

#ifndef B2_TRANSLATE_H
#define B2_TRANSLATE_H

#include <box2d/base.h>
#include <box2d/box2d.h>
#include <box2d/collision.h>
#include <box2d/id.h>
#include <box2d/math_functions.h>
#include <box2d/types.h>

#endif /* B2_TRANSLATE_H */