# Upstream

| Field | Value |
| --- | --- |
| Project | Box2D, a 2D physics engine for games |
| Upstream | `erincatto/box2d` — <https://github.com/erincatto/box2d> |
| Release | `v3.1.1` |
| Commit | `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3` |
| Acquired | Upstream source tree placed in this directory; no Git history carried |
| Imported files | 267: 232 Box2D files and 35 enkiTS files |
| Removed upstream files | `.github/workflows/build.yml` |

## Carried inventory

| Area | Files | Contents |
| --- | ---: | --- |
| `include/box2d/` | 6 | Public headers |
| `src/` | 59 | Native core, private headers, debugger visualiser, and CMake file |
| `test/` | 12 | Upstream unit tests |
| `shared/` | 9 | Test, sample, and benchmark support |
| `extern/glad/`, `extern/jsmn/` | 4 | Vendored graphics loader and JSON parser |
| `extern/enkiTS/` | 35 | Vendored task scheduler |
| `benchmark/` | 44 | Benchmark driver and scenario CSVs |
| `samples/` | 42 | C++ samples and assets |
| `docs/` | 43 | Manual and 28 figures |
| `.github/` | 3 | Issue, pull-request, and funding metadata |
| `LICENSE` | 1 | Upstream MIT licence |
| `README.upstream.md` | 1 | Upstream README, preserved byte for byte |
| `CMakeLists.txt`, build scripts | 5 | Upstream build files, carried for audit |
| `.clang-format`, `.gitattributes` | 2 | Upstream repository conventions |
| `.gitignore` | 1 | Upstream patterns plus the fork's build-output rules |

## Third-party source

| Tree | Identity | Licence |
| --- | --- | --- |
| `extern/glad/`, `extern/jsmn/` | Upstream's vendored copies at `v3.1.1` | Mixed; see `NOTICE.md` |
| `extern/enkiTS/` | enkiTS by Doug Binks; revision `404a3bf8f855039dfff2052184d6308655286c07`, commit date `2026-09-29T09:52:56Z`; archive SHA-256 `21cc50750166c3e6f69ed4a67dbf9a015526fb35a1291e91d0dc31148ad89d9b`; version `1.11.0` | zlib; see `NOTICE.md` |

`UPSTREAM.sha256` records source digests. The fork-extended `.gitignore` is excluded; its pristine upstream file was 96 bytes with SHA-256 `a97a05abdbf7d23471cfe693895fc4da9263831b16c17cd75581700dec54b3f4`.
