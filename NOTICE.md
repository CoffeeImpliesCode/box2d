# Notices

## Box2D

`LICENSE` is upstream Box2D's MIT text, © 2022 Erin Catto. It is installed at `share/licenses/box2d/LICENSE`.

| Path | Files | SPDX copyright |
| --- | ---: | --- |
| `include/box2d/*.h` | 6 | 2023 Erin Catto |
| `src/*.c`, `src/*.h` | 57 | 2023 Erin Catto |
| `test/*.c`, `test/*.h` | 11 | 2023 Erin Catto |
| `shared/*.c`, `shared/*.h` | 8 | 2023 Erin Catto |
| `benchmark/main.c` | 1 | 2024 Erin Catto |
| `samples/*.cpp`, `samples/*.h` | 26 | 2023 Erin Catto |
| `samples/data/*.fs`, `samples/data/*.vs` | 10 | 2024 Erin Catto |

These 119 files carry `SPDX-License-Identifier: MIT`. The upstream files without an SPDX identifier are:

| Path | Scope |
| --- | --- |
| `LICENSE` | MIT grant text |
| `CMakeLists.txt` outside `extern/enkiTS/` | Upstream build files |
| `build.sh`, `build_emscripten.sh`, `create_sln.bat`, `deploy_docs.sh` | Upstream helper scripts |
| `.clang-format`, `.gitattributes`, `.gitignore` | Upstream conventions; `.gitignore` has a fork block |
| `src/box2d.natvis` | Visual Studio debugger visualisers |
| `benchmark/**/*.csv` | Benchmark scenario data |
| `docs/**` | Manual sources and figures |
| `.github/**` | Issue, pull-request and funding metadata |
| `README.upstream.md` | Upstream README, preserved byte for byte |
| `extern/glad/**`, `extern/jsmn/**` | Third-party files; see exceptions |
| `extern/enkiTS/**` | zlib-licensed third-party tree |
| `samples/data/*.svg` | Upstream sample artwork |
| `samples/data/droid_sans.ttf` | Apache-2.0; see exceptions |

The no-SPDX upstream files are covered by `LICENSE` except for the terms listed below.

## Exceptions

- `extern/jsmn/jsmn.h`: MIT, © 2010 Serge Zaitsev; its notice travels with the file.
- `extern/glad/include/KHR/khrplatform.h`: MIT-style Khronos grant, © 2008–2018 The Khronos Group; its notice travels with the file.
- `extern/glad/include/glad/glad.h` and `extern/glad/src/glad.c`: generator banners, no separate grant; covered by `LICENSE`, not the Khronos grant.
- `extern/enkiTS/`: zlib, © 2013 Doug Binks. `License.txt` and all four files under `src/` carry the grant. enkiTS is used by the determinism test and benchmarks, not by `libbox2d` or its installed headers. Keep its notice with any copy of the tree; its licence bars removing or altering the notice in a source distribution.
- `samples/data/droid_sans.ttf`: Apache-2.0, © 2007 Google Corporation. Carry its terms with the font; retain attribution and the licence, mark changes, and include a `NOTICE` if one exists. The SDK does not compile or install the font.

## Fork-authored files

Fork-authored files are MIT under `FORK-LICENSE.md`. These files carry an SPDX header: `build.zig`, `build.zig.zon`, `build_support/box2d_inline_bridge.c`, `zig/root.zig`, `zig/translate.h`, `runtime/*`, `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/src/main.zig`, `consumer/.gitignore`, `devenv.yaml`, and `.envrc`.

These fork-authored files have no SPDX header:

| Path | Reason |
| --- | --- |
| `package.nix`, `flake.nix`, `devenv.nix` | Nix expressions |
| `flake.lock` | Generated JSON |
| `cross-test.profile.sh` | Shell profile |
| `consumer/build.zig.zon` | Consumer manifest |
| `UPSTREAM.sha256` | Digest record |
| `.gitignore` fork block | Appended to an upstream file |
| `README.md`, `README.zig.md`, `NOTICE.md`, `FORK-LICENSE.md`, `FORK-NOTES.md`, `CHANGELOG.md`, `UPSTREAM.md` | Prose and licence records |

The MIT grant covers only fork-authored material. Upstream files and third-party material keep their terms; only the appended `.gitignore` block is fork-authored.

## Redistribution

- Keep `LICENSE` with every copy of the Box2D core. Keep the jsmn and Khronos notices with copies containing those files, enkiTS's notices with copies containing that tree, and the font's Apache-2.0 terms with the font.
- Install `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `FORK-NOTES.md`, and `enkiTS-License.txt` under `share/licenses/box2d/`. The last file is enkiTS's zlib notice.
- Do not use upstream names to endorse a derived product without permission.
- No patent grant is claimed; the MIT, zlib and Khronos-style terms here contain no explicit patent clause.
