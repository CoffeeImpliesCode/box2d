# NOTICE.md — per-file licence and copyright inventory

## What this file is

Every licence term and copyright notice that travels with the material this SDK
carries, file by file. It exists because the tree is **not** one licence: the
compiled core and nearly all of the sources are MIT, a vendored task scheduler
is zlib, three vendored files carry their own grants, and one sample asset is
Apache-2.0. A reader who takes the word "MIT" from the repository root and
applies it to `samples/data/` or `extern/` would be wrong about all of them.

Everything below was read out of the files themselves. No licence text is
restated here; each one is carried in this repository at the path named, and the
digests of all of them are in `UPSTREAM.sha256`.

## The primary term: MIT

| Field | Value |
| --- | --- |
| Authoritative text | `LICENSE`, 1067 bytes, 20 lines, carried byte for byte |
| Copyright | `Copyright (c) 2022 Erin Catto` |
| Grant | the MIT licence text verbatim, unmodified |
| Installed at | `share/licenses/box2d/LICENSE`, by the build graph |
| Per-file SPDX in the sources | `SPDX-License-Identifier: MIT` |
| Per-file copyright in the sources | `SPDX-FileCopyrightText:` naming Erin Catto |

`README.upstream.md:92-93` states the same thing in upstream's words ("Box2D is
developed by Erin Catto and uses the MIT license"), and `docs/FAQ.md:7` repeats
it. Those are corroboration, not the licence: `LICENSE` is.

## Inventory: the MIT term covers

119 carried files carry an explicit `SPDX-License-Identifier: MIT` header. They
are, in full:

| Path | Files | `SPDX-FileCopyrightText` |
| --- | --- | --- |
| `include/box2d/*.h` | 6 | `2023 Erin Catto` |
| `src/*.c`, `src/*.h` | 57 | `2023 Erin Catto` |
| `test/*.c`, `test/*.h` | 11 | `2023 Erin Catto` |
| `shared/*.c`, `shared/*.h` | 8 | `2023 Erin Catto` |
| `benchmark/main.c` | 1 | `2024 Erin Catto` |
| `samples/*.cpp`, `samples/*.h` | 26 | `2023 Erin Catto` |
| `samples/data/*.fs`, `samples/data/*.vs` | 10 | `2024 Erin Catto` |

The compiled library, the installed headers, the upstream test suite and the
shared test support all sit inside the MIT set. The MIT notice and permission
text travel with every binary.

## Inventory: files with no SPDX identifier

These carried files carry **no** `SPDX-License-Identifier` line. Their absence is
recorded here rather than filled in, because adding one would be asserting a
term upstream did not state. Each is covered by `LICENSE` on the ordinary
reading of the repository, except where this file says otherwise.

| Path | Files | Why it is listed |
| --- | --- | --- |
| `LICENSE` | 1 | upstream's own MIT text: the grant itself, not a file that carries an identifier about itself |
| `CMakeLists.txt` outside `extern/enkiTS/` | 7 | upstream build system, carried for audit, never invoked; enkiTS's own is counted in its row |
| `build.sh`, `build_emscripten.sh`, `create_sln.bat`, `deploy_docs.sh` | 4 | upstream helper scripts, same |
| `.clang-format`, `.gitattributes`, `.gitignore` | 3 | upstream repository conventions; `.gitignore` is fork-extended |
| `src/box2d.natvis` | 1 | Visual Studio debugger visualisers |
| `benchmark/**/*.csv` | 42 | recorded benchmark scenario input data |
| `docs/**` | 43 | the manual: 12 markdown files, `CMakeLists.txt`, `extra.css`, `layout.xml`, and 28 SVG figures |
| `.github/**` | 4 | issue, PR and funding metadata, upstream's own CI workflow |
| `README.upstream.md` | 1 | upstream's README, preserved byte for byte |
| `extern/glad/**`, `extern/jsmn/**` | 4 | see below — **not** covered by `LICENSE` alone |
| `extern/enkiTS/**` | 35 | **zlib**, see below — a vendored third-party tree |
| `samples/data/*.svg` | 4 | upstream-authored level artwork for the samples |
| `samples/data/droid_sans.ttf` | 1 | **Apache-2.0**, see below |

Those rows name every carried file without an SPDX line: 150 entries over 149
distinct files, because `docs/CMakeLists.txt` is counted in its own row and in
the `docs/**` row. Of the 149, 148 are pinned in `UPSTREAM.sha256` — the 267
digests less the 119 that carry the identifier — and the 149th is `.gitignore`,
which that record deliberately does not pin. No pinned file is missing from
this inventory.

## Per-file exceptions

### 1. `extern/jsmn/jsmn.h` — MIT, a different holder

```
extern/jsmn/jsmn.h:1-21
 * MIT License
 * Copyright (c) 2010 Serge Zaitsev
```

jsmn is a vendored third-party parser with its own MIT grant and a **different
copyright holder**. That notice travels with the file and is reproduced here in
substance: the MIT permission and warranty disclaimer apply to jsmn as well.

```
extern/glad/include/KHR/khrplatform.h:4-28
 ** Copyright (c) 2008-2018 The Khronos Group Inc.
 ** Permission is hereby granted, free of charge, ... ("Materials")
```

The grant is MIT's permission and disclaimer wording with "Software" replaced by
"Materials", held by The Khronos Group Inc. It is permissive and requires the
notice to travel with copies. The header is not compiled by this SDK; it exists
because the vendored glad loader includes it.

### 3. `extern/glad/include/glad/glad.h` and `extern/glad/src/glad.c` — no grant of their own

```
OpenGL loader generated by glad 0.1.34 on Sat Jul  8 18:48:45 2023.
Language/Generator: C/C++   Specification: gl   APIs: gl=4.6
Profile: compatibility
```

Both files carry a generator banner and no licence grant. Nothing in either file
asserts terms of its own, so they are covered by the repository's `LICENSE` like
the rest of upstream's tree — **not** by the Khronos grant, which belongs to
`khrplatform.h`, and not by a licence this fork could choose. They are not
compiled or installed by this SDK; they exist so the vendored tree matches
upstream and so the Khronos notice beside them travels with it.

### 4. `samples/data/droid_sans.ttf` — Apache-2.0

The font carries its own terms in its embedded name table, quoted here from the
file's bytes:

```
Digitized data copyright 2007, Google Corporation.
Droid Sans is a humanist sans serif typeface designed for user interfaces
and electronic communication.
Licensed under the Apache License, Version 2.0
http://www.apache.org/licenses/LICENSE-2.0
```

So: **Droid Sans is Apache-2.0, © 2007 Google Corporation**, inside an otherwise
MIT repository. Upstream ships no separate licence file or NOTICE for it. The
Apache-2.0 obligations that apply to any redistribution of this file are: keep
the attribution, keep a copy of the licence, mark changed files, and carry a
NOTICE if one exists. This file is not compiled, not installed and not
redistributed by this SDK's Nix outputs; it is carried in the source tree, is
pinned by `UPSTREAM.sha256`, and travels with the upstream sample program. This
entry exists so that nobody reads it as MIT.

### 5. `extern/enkiTS/` — zlib

```
extern/enkiTS/License.txt
Copyright (c) 2013 Doug Binks
Permission is granted to anyone to use this software for any purpose, including
commercial applications, and to alter it and redistribute it freely, subject to
the following restrictions:
1. The origin of this software must not be misrepresented ...
2. Altered source versions must be plainly marked as such ...
3. This notice may not be removed or altered from any source distribution.
```

That is the zlib licence. It is not MIT, not Box2D's grant, and not covered by
`LICENSE`. The same grant is repeated as an in-file comment header in all four
files under `extern/enkiTS/src/`, so the notice travels with the sources
themselves as well as in `License.txt`.

**The library does not depend on it.** enkiTS is used by upstream's determinism
test (`test/test_determinism.c:4`) and benchmark driver (`benchmark/main.c:8`),
which include `TaskScheduler_c.h`. It is never compiled into `libbox2d`, never
installed as part of it, and never referenced by an installed header. It is
vendored at revision `404a3bf8f855039dfff2052184d6308655286c07` because this SDK
downloads nothing and upstream fetches it from an unpinned `GIT_TAG master`.

### 6. Material this SDK does not carry

The shaders, the level artwork and the benchmark CSVs are part of the compiled or
installed closure of nothing: they belong to upstream's samples and benchmarks,
which are carried for audit. Upstream's build also fetches GLFW 3.4 and imgui
v1.91.3 for those samples, and Tracy v0.11.1 for `BOX2D_PROFILE`, which this SDK
does not offer; **none of those is in this tree**, so no terms are recorded for
them.

## This fork's own files

Everything this fork authored is dedicated by the owner under the **MIT
licence**, matching the primary upstream term. `FORK-LICENSE.md` carries the
grant, the authorization and the file list, and `MIT` is the SPDX identifier of
every one of them.

The identifier is a header in the files that carry one. These fork-authored
files begin with `SPDX-License-Identifier: MIT` on their first line:
`build.zig`, `build.zig.zon`, `build_support/box2d_inline_bridge.c`,
`zig/root.zig`, `zig/translate.h`, all six files under `runtime/`, `tests.zig`,
`smoke.zig`, `consumer/build.zig`, `consumer/src/main.zig`,
`consumer/.gitignore`, `devenv.yaml`, `.envrc` and
`.github/workflows/verify.yml`.

These fork-authored files carry the grant of `FORK-LICENSE.md` and no header:

| Path | Why there is no header |
| --- | --- |
| `package.nix`, `flake.nix`, `devenv.nix` | Nix expressions, reviewed as source like the rest |
| `flake.lock` | a Nix-generated JSON input record, with nowhere in its format to put a comment |
| `cross-test.profile.sh` | a shell profile |
| `consumer/build.zig.zon` | the consumer package's manifest |
| `UPSTREAM.sha256` | a digest record whose every line is `#` or a sha256 line |
| the `.gitignore` fork block | an appended block inside an upstream file |
| `README.md`, `README.zig.md`, `NOTICE.md`, `FORK-LICENSE.md`, `FORK-NOTES.md`, `CHANGELOG.md`, `UPSTREAM.md` | prose and licence records |

None of them is outside the grant and none of them carries a different term. The
header is absent, not the permission.

That grant covers fork-authored files only. It does not relabel upstream's
material, it does not claim Erin Catto, Serge Zaitsev, Doug Binks, The Khronos
Group Inc. or Google Corporation authored anything here, and it does not reach
the vendored, zlib or Apache-2.0 material above.

### The runtime route, in the same terms

`-Druntime=true` changes none of this. `runtime/` is fork-authored and MIT like
the rest of the fork's files, and because that branch links no archive and no
system library into the module it introduces no third-party material into the
tree: the installed library itself carries none, and the only vendored
third-party code the build graph compiles is enkiTS, which reaches
`bin/box2d-benchmark` and nothing else. The object a runtime consumer opens is
one that consumer supplies — built from this tree or from elsewhere — and the
terms of that object are its own. The records installed beside this tree's own
artifact say nothing about a file this tree does not ship, which is why the
provider requirements are stated in `README.zig.md` §3 rather than licensed
here.

## Obligations that travel with a redistributed copy

1. Keep `LICENSE` — the MIT copyright notice, permission notice and warranty
   disclaimer — with every copy of the Box2D core, in source or binary form.
2. Keep the in-file notices of `extern/jsmn/jsmn.h` and
   `extern/glad/include/KHR/khrplatform.h` with any copy that carries those
   files, keep `extern/enkiTS/License.txt` — and the notice in every enkiTS
   source file — with any copy that carries that tree, and keep the Apache-2.0
   terms with `samples/data/droid_sans.ttf`. enkiTS's third condition is that
   its notice may not be removed or altered from a source distribution.

3. Ship the licence and provenance material under `share/licenses/box2d/`. The
   build graph writes six files there, in every linkage and optimize mode:
   `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `FORK-NOTES.md` and
   `enkiTS-License.txt` (`build.zig:549-578`, `build.zig:1426-1463`). The last
   is enkiTS's own zlib notice renamed on the way, not a second copy of
   Box2D's.
4. Do not use upstream's names to endorse a derived product. That is the third
   MIT condition and it applies to this fork's own redistribution.
5. Do not remove the SPDX headers from the sources. `UPSTREAM.sha256` pins all
   119 of them, so a removed header fails
   `sha256sum -c UPSTREAM.sha256` rather than passing quietly.

No patent grant is claimed for any term recorded here. MIT, the zlib licence
and the Khronos-style grant in this tree contain no explicit patent clause.