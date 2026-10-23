# Box2D

Box2D 3.1.1 is a 2D physics engine for games from `erincatto/box2d`.
This package builds its C library with Zig and provides a typed Zig module.

## Source deviations

- The upstream Box2D trees are unchanged: `include/`, `src/`, `test/`, `shared/`, `benchmark/`, `samples/`, `docs/`, `extern/glad/` and `extern/jsmn/`.
- The fork extends upstream's `.gitignore` with its own ignore patterns.
- `build_support/box2d_inline_bridge.c` exports `b2MakeAABB`, which Zig 0.16 cannot translate from its inline definition.

## Build deviations

- `build.zig` replaces upstream's CMake build. The Zig build graph downloads no build dependencies.
- enkiTS is vendored for upstream's determinism test and benchmark. The library itself does not use it.
- The graphical samples are not built. They require GLFW and imgui downloads in upstream's build.
- The build installs `lib/pkgconfig/box2d.pc` instead of a CMake package export. Upstream's C unit tests are available through `zig build test`.

## Support matrix

Zig 0.16.0 is the minimum version. `zig build check` uses this six-target compile/link matrix; it does not describe runtime test coverage:

| Target | Static | Dynamic |
| --- | --- | --- |
| `x86_64-linux-gnu` | yes | yes |
| `aarch64-linux-gnu` | yes | yes |
| `aarch64-macos` | yes | yes |
| `x86_64-windows-gnu` | yes | yes |
| `riscv64-linux-gnu` | yes | yes |
| `wasm32-wasi` | yes | no |

WASI has no dynamic linker. Its Zig 0.16 C++ library also has no threads, so the benchmark is not built for that target.

## Consumption

### Zig dependency

```zon
.dependencies = .{
    .box2d = .{ .path = "../box2d" },
};
```

```zig
const dep = b.dependency("box2d", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("box2d", dep.module("box2d"));
```

The package and module are both named `box2d`. Import the module with `@import("box2d")`.

### Linkage and installed artifacts

`-Dlinkage=static` is the default and installs `lib/libbox2d.a`. `-Dlinkage=dynamic` installs a shared library: ELF uses `libbox2d.so.3.1.1` with `.so.3` and `.so` links, macOS uses `libbox2d.3.1.1.dylib` and `libbox2d.dylib`, and Windows GNU uses `bin/box2d.dll` with `lib/box2d.lib`. Public headers install under `include/box2d/`; C consumers use `lib/pkgconfig/box2d.pc`.

`-Druntime=true` builds a module that loads a shared provider at runtime. The delivery selected by `-Dlinkage` is unchanged; a static delivery therefore needs a shared provider from elsewhere. The loader API is in `README.zig.md`.

### Build options

| Option | Values | Default | Effect |
| --- | --- | --- | --- |
| `-Dlinkage` | `static`, `dynamic` | `static` | Selects the installed library form. |
| `-Druntime` | `true`, `false` | `false` | Selects runtime dispatch instead of linked calls. |
| `-Dvalidate` | `true`, `false` | `true` | Enables upstream validation. |
| `-Ddisable-simd` | `true`, `false` | `false` | Disables SIMD. |
| `-Davx2` | `true`, `false` | `false` | Enables AVX2 on x86_64; ignored elsewhere. |
| `-Dtarget`, `-Dcpu`, `-Doptimize` | Zig standard options | — | Select the target, CPU and optimization mode. |

### C and pkg-config

```sh
zig build install --prefix "$PREFIX"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags --libs box2d
```

`box2d.pc` supplies `-lbox2d` and adds `-lm` on targets that need libm.

Licensing and the upstream file inventory are documented in `NOTICE.md` and `UPSTREAM.md`.