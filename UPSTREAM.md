# UPSTREAM.md — what this SDK is built from

## What this file is

The pin, the licence, the complete per-area inventory and the integrity record
for the upstream material this SDK carries. Everything here was read out of the
files in this directory; nothing here was executed. `UPSTREAM.sha256` holds the
digest of every file named in the inventory.

## The pin

| Field | Value |
| --- | --- |
| Project | Box2D, a 2D physics engine for games |
| Upstream | `erincatto/box2d` (official) |
| Tag | `v3.1.1` |
| Commit | `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3` |
| Homepage | <https://box2d.org> |
| Acquired by | the driver, as a source tree placed directly in this directory |

**No Git history is carried here.** `git log` in this directory reports no
commits on `main` and no tags, so the pin above is a recorded fact about what
was acquired, not something this working copy can verify on its own. A later
re-sync has to re-fetch `v3.1.1`, re-run `sha256sum -c UPSTREAM.sha256` against
the pinned digests, and update this table, `UPSTREAM.sha256`, `NOTICE.md` and
`CHANGELOG.md` together.

### Version evidence in the tree

Three independent places in the carried sources say 3.1.1:

* `CMakeLists.txt:6` — `project(box2d VERSION 3.1.1 ...)`
* `src/core.c:69-76` — `b2GetVersion()` returns `{ .major = 3, .minor = 1, .revision = 1 }`
* `src/CMakeLists.txt:96-97` — library `VERSION ${PROJECT_VERSION}`, `SOVERSION ${PROJECT_VERSION_MAJOR}`, i.e. soname 3

## Licence of the carried material

Upstream Box2D is MIT. `LICENSE` is upstream's own text, 1067 bytes, 20 lines,
`Copyright (c) 2022 Erin Catto`, carried byte for byte and installed unmodified
by the build graph at `share/licenses/box2d/LICENSE`.

Every one of the six public headers and all 57 `src/*.c` and `src/*.h` files
also carry `SPDX-License-Identifier: MIT`, with `SPDX-FileCopyrightText:` naming
Erin Catto (`2023` in the headers and `src/`, `2024` in `benchmark/main.c`).
Upstream's per-file terms are collected in `NOTICE.md`. Three vendored
third-party trees and one sample asset travel with the source and are **not**
covered by `LICENSE`; the table below names each one.


## Complete inventory

267 carried files, 3 278 764 bytes. Every digest is in `UPSTREAM.sha256`;
`sha256sum -c UPSTREAM.sha256` was observed passing 267/267 with 0 failures
when the record was written.


| Area | Files | Bytes | What it is |
| --- | --- | --- | --- |
| `include/box2d/` | 6 | 162 479 | The public headers the installed ABI is declared in |
| `src/` | 59 | 862 984 | The native core: 35 `.c`, 22 `.h`, `box2d.natvis`, `CMakeLists.txt` |
| `test/` | 12 | 39 752 | Upstream's unit-test suite, byte for byte |
| `shared/` | 9 | 43 928 | Code upstream shares between its samples, benchmarks and tests |
| `extern/glad/`, `extern/jsmn/` | 4 | 459 572 | The vendored glad loader and jsmn parser, for upstream's graphical samples |
| `extern/enkiTS/` | 35 | 278 989 | The vendored enkiTS task scheduler, for upstream's determinism test and benchmarks |
| `benchmark/` | 44 | 14 727 | Upstream's benchmark driver and its scenario CSVs |
| `samples/` | 42 | 822 533 | Upstream's C++ sample program and its data assets |
| `docs/` | 43 | 576 858 | Upstream's manual sources and 28 figures |
| `.github/` | 4 | 6 017 | Issue, PR and funding metadata, plus upstream's own CI workflow |
| `LICENSE` | 1 | 1 067 | Upstream's MIT text |
| `README.upstream.md` | 1 | 3 382 | Upstream's README, preserved byte for byte |
| `CMakeLists.txt`, `build.sh`, `build_emscripten.sh`, `create_sln.bat`, `deploy_docs.sh` | 5 | 5 457 | Upstream's own build system, carried for audit, never invoked |
| `.clang-format`, `.gitattributes` | 2 | 1 019 | Upstream's own repository conventions |

### The public headers

`include/box2d/base.h`, `box2d.h`, `collision.h`, `id.h`, `math_functions.h`,
`types.h` — exactly upstream's `BOX2D_API_FILES`
(`src/CMakeLists.txt:63-70`), which upstream installs into `include/box2d/`
(`src/CMakeLists.txt:208-211`). The build graph installs the same six files.

There is **no generated or configuration header**. `BOX2D_VALIDATE`,
`BOX2D_DISABLE_SIMD`, `BOX2D_AVX2`, `box2d_EXPORTS` and `BOX2D_DLL` are all
compile-line macros, and `B2_ASSERT`/`b2InternalAssertFcn` depend only on
`NDEBUG` or `B2_ENABLE_ASSERT` (`include/box2d/base.h:101`), which is the
caller's own `-DNDEBUG`. `src/*.h` are private: upstream installs none of them.

### The vendored `extern/` trees

Three third-party trees are vendored in this repository, each under its own
terms. None of them is Box2D, and none of them is this fork's work.

| Tree | Project | Pin | Licence |
| --- | --- | --- | --- |
| `extern/glad/`, `extern/jsmn/` | upstream's own vendored copies, carried unchanged | as upstream at v3.1.1 | mixed — see below |
| `extern/enkiTS/` | enkiTS, Doug Binks | master `404a3bf8f855039dfff2052184d6308655286c07`, dated 2026-09-29T09:52:56Z | zlib |

#### glad and jsmn — for the graphical samples

| Path | Grant | Evidence |
| --- | --- | --- |
| `extern/jsmn/jsmn.h` | MIT, Copyright (c) 2010 Serge Zaitsev | In-file notice, lines 1-21 |
| `extern/glad/include/KHR/khrplatform.h` | MIT-style Khronos grant, Copyright (c) 2008-2018 The Khronos Group Inc. | In-file notice, lines 4-28 |
| `extern/glad/include/glad/glad.h` | no in-file grant; a `glad 0.1.34` generator banner only | Lines 1-22 |
| `extern/glad/src/glad.c` | no in-file grant; the same generator banner only | Lines 1-22 |

These four files serve upstream's **graphical samples**, which this SDK does not
build. They are carried so the tree matches upstream and so the vendored grants
travel with it.

#### enkiTS — for the determinism test and the benchmarks

`extern/enkiTS/` is a full, pristine enkiTS checkout, 35 files, in its original
layout. It exists because two carried Box2D files include `TaskScheduler_c.h`:

* `test/test_determinism.c:4`
* `benchmark/main.c:8`

Upstream obtains it from the network with an **unpinned** `GIT_TAG master`
(`CMakeLists.txt:88-95`). This SDK downloads nothing, so the tree is vendored at
an exact revision instead:

| Field | Value |
| --- | --- |
| Upstream | enkiTS, Doug Binks (<https://github.com/dougbinks/enkiTS>) |
| Revision | `404a3bf8f855039dfff2052184d6308655286c07` |
| Commit date | 2026-09-29T09:52:56Z |
| Archive SHA-256 | `21cc50750166c3e6f69ed4a67dbf9a015526fb35a1291e91d0dc31148ad89d9b` |
| Acquired by | the driver; receipt `local://foundation-contract-enkits-import.json` |
| Version in its own `build.zig.zon` | `1.11.0` |
| Licence | zlib — `extern/enkiTS/License.txt`, `Copyright (c) 2013 Doug Binks` |

The notice is not only in `License.txt`: all four files under
`extern/enkiTS/src/` carry the identical grant as an in-file comment header.

**The library does not depend on enkiTS.** It is used by upstream's determinism
test and benchmark driver only, never by `src/`, never by the installed library
and never by the installed headers. It is vendored to build those two programs,
not to link into `libbox2d`.

`extern/enkiTS/` carries enkiTS's **own** `build.zig` and `build.zig.zon`. They
are pinned in `UPSTREAM.sha256` because they are carried bytes, and they are
never invoked: this SDK compiles enkiTS through its own build graph. Do not
confuse them with this SDK's `build.zig` at the root.

### What this tree does not contain

Upstream's build system downloads three dependencies at build time. This SDK
downloads nothing, and invokes no CMake, Make or autotools target, so the two
that are still missing are not here:

| Missing dependency | Upstream reference | What needs it |
| --- | --- | --- |
| GLFW 3.4 | `samples/CMakeLists.txt:20-27` | the graphical samples, which are not built |
| imgui v1.91.3 | `samples/CMakeLists.txt:32-35`, a release zip | the graphical samples, which are not built |

enkiTS used to be on this list and is not any more: it is vendored, at the pin
above. Tracy v0.11.1 for `BOX2D_PROFILE` (`src/CMakeLists.txt:106-117`) is not
needed either, because this SDK does not offer a profiling option.

Upstream also generates a CMake package export
(`lib/cmake/box2d/box2dConfig.cmake`, `box2dConfigVersion.cmake`) through
`install(EXPORT ...)` (`src/CMakeLists.txt:202-223`). The SDK installs
pkg-config metadata instead; that omission is recorded as a native-build
deviation in `README.md`.

## The pristine upstream `.gitignore`

Upstream's `.gitignore` is 96 bytes with SHA-256

```
a97a05abdbf7d23471cfe693895fc4da9263831b16c17cd75581700dec54b3f4
```

It is deliberately **not** in `UPSTREAM.sha256`. It is an upstream file the fork
has to extend — upstream's own patterns (`build/`, `.cache/`, `.idea/`,
`.vscode/`, `.vs/`) must keep working — so pinning it would fail the instant
that extension was made and would report an ordinary review edit as an
integrity failure. The pristine digest above is the record; a change to the file
is a deliberate, visible edit in the same change that updates this line.

## Integrity record

`UPSTREAM.sha256` — 267 `<hex>  <path>` lines in `sha256sum` format, LC_ALL=C
path order, with a header explaining what it pins and what it deliberately does
not, including the enkiTS files and the reason `.gitignore` is not among them.
Check it from the repository root:

```sh
sha256sum -c UPSTREAM.sha256
```

The same command is the provenance job in
`.github/workflows/verify.yml` and the `box2d-integrity` script in `devenv.nix`.