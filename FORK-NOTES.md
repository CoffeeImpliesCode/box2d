# Box2D fork notes

## Source changes

No upstream C implementation or public header is patched. The upstream trees `src/`, `include/`, `test/`, `shared/`, `benchmark/`, `samples/`, `docs/`, `extern/glad/` and `extern/jsmn/` remain unchanged.

| File | Change and reason |
| --- | --- |
| `.gitignore` | Adds fork-specific ignore rules while retaining upstream patterns. |
| `build_support/box2d_inline_bridge.c` | Defines `b2MakeAABB` for the Zig facade because translate-c emits its inline definition as an unresolved external declaration. |

## Build graph differences

- `build.zig` compiles Box2D's 35 C core files directly; it does not invoke CMake, Make, or a build-time download.
- Upstream's tests and benchmark use the vendored enkiTS source instead of fetching upstream's unpinned `master` branch.
- The build installs no CMake package export. It generates relocatable `lib/pkgconfig/box2d.pc` as the C link metadata.
- Static linkage is the default. `-Dlinkage` selects static or shared delivery; `-Druntime` independently selects direct calls or runtime dispatch.
- The graph has no system-library mode. It does not build the graphical samples, Doxygen targets, or Tracy profiling path. Upstream's C tests and benchmark are built where their C++ dependency is available.
- Dynamic builds retain upstream's versioned library identity, position-independent code, and hidden-by-default export surface. The Debug library has no `d` postfix because `box2d.pc` links `-lbox2d` in every mode.
- `-ffp-contract=off` is unconditional. The upstream OS guard excludes only MSVC and Emscripten, which this graph does not target.
- `box2d.pc` adds `-lm` on Linux, BSD, illumos, and Solaris, where the core's math calls use libm; it omits it on macOS, iOS, and Windows.
- Zig 0.17.0 nested consumer builds use `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LIB_DIR`; `--build-file` preserves the caller's cwd for relative environment paths.

## Platform boundaries

- A requested shared library is rejected on targets without a dynamic linker; the graph does not substitute a static archive. `wasm32-wasi` therefore supports only static linkage.
- Zig 0.17.0's `wasm32-wasi` C++ library has no threads. The Box2D core and Zig facade build there, but upstream's C tests and benchmark do not.
- The 32-bit ARM OpenBSD targets use Box2D's scalar math path because this toolchain cannot include the ARM NEON headers there; other ARM targets keep the SIMD path.
- Zig 0.17.0 does not expose `--libc-runtimes` to `build.zig`; nested consumer runs cannot inherit that path.
- Cross-target `consumer` builds install to the caller's prefix after attempting an enabled executor.
- Nix packages are native-only and expose Linux and Darwin systems.
