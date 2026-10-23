# Changelog

- Port to Zig 0.17.0.
- `zig build consumer` runs native targets; cross-target builds try an enabled executor and install the artifact in the caller's prefix.
- Nested consumer builds inherit the SDK build's target, CPU, optimize mode, linkage, runtime, validation, SIMD settings, and command-line arguments.
- Nested consumer builds use the caller's local and global caches, prefix, job count, and summary setting.
- NetBSD builds preprocess the translation header with the target C preprocessor before Zig translation.
- 32-bit ARM OpenBSD builds use scalar math when the target's NEON headers do not compile.
- Zig test and smoke roots use LLVM for aggregate calls across the C ABI.
- Runtime load errors for missing symbols identify the library and symbol.
- The library includes an inline bridge for `b2MakeAABB`.
- Installs include a static or versioned shared library, six public headers, pkg-config metadata, the benchmark where supported, and licence records.
- The `box2d` module provides a typed Zig facade and raw translated C API; its optional runtime module loads a provider by path or system name.
- Build options select linkage, runtime loading, validation, SIMD, and AVX2 behavior.
- Added the Box2D v3.1.1 SDK with Zig and C builds, a consumer package, tests, smoke program, and benchmark.
