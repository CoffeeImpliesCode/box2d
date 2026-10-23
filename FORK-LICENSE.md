# Licence of the fork-authored additions

## The grant

* **Authorized by:** the owner of this repository, directly, on **2026-10-04**. This is a direct authorization recorded here. It is not derived from any upstream permission.
* **Terms:** the MIT licence, matching the primary upstream terms of this project. The authoritative text is `LICENSE`, the same text upstream ships.
* **SPDX identifier for fork-authored files:** `MIT`. Every fork-authored source and build-graph file carries `SPDX-License-Identifier: MIT` on its first line. Nix expressions, the JSON lock, the consumer package's `build.zig.zon`, the shell profile, the digest record, and prose and licence records have no header; `NOTICE.md` lists each and why, because the absence of a header is not the absence of this grant.
* **Copyright holder:** not asserted here as an individual. The holder is the party that made the authorization above. Upstream authors named in `LICENSE` and source SPDX headers are **not** claimed to own anything this fork wrote.

## Files this grant covers

* `build.zig`, `build.zig.zon`, `build_support/`, `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc`;
* `zig/root.zig`, `zig/*.zig`, `zig/translate.h`, `runtime/`;
* `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig`;
* `cross-test.profile.sh`, `UPSTREAM.sha256`;
* `README.md`, `README.zig.md`, `NOTICE.md`, `UPSTREAM.md`, `FORK-LICENSE.md`, `FORK-NOTES.md`, `CHANGELOG.md`;
* the fork block in `.gitignore`: `.zig-cache/`, `zig-cache/`, `zig-out/`, `zig-pkg/`, `.devenv/`, `.direnv/` and `result*`. Upstream's patterns are excluded.

## Upstream content and exceptions

The grant does not cover upstream's C core, public headers, tests, shared test support, docs, or vendored `extern/` trees; their terms are in `NOTICE.md`.

* `README.upstream.md` is a byte-for-byte copy of upstream's `README.md` at commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`. It is under `LICENSE`, not this grant; `UPSTREAM.sha256` pins its bytes.
* `.gitignore` has ten unchanged upstream lines; `UPSTREAM.md` records their pristine digest. The fork additions are listed above.
* `extern/` is not fork material: `extern/jsmn/jsmn.h` has a separate MIT grant; `extern/glad/include/KHR/khrplatform.h` has a Khronos grant; the two generated glad files carry no licence of their own; `extern/enkiTS/` is a vendored zlib tree under its own notice. See `NOTICE.md`.
* `samples/data/droid_sans.ttf` is Apache-2.0, © 2007 Google Corporation, under its embedded name-table terms. See `NOTICE.md`.

Of 149 files without SPDX, 148 are pinned in `UPSTREAM.sha256`; `.gitignore` is not. `NOTICE.md` lists their terms and the vendor, enkiTS and font exceptions.

No terms are claimed for absent build-time GLFW, imgui, Tracy downloads.

This grant gives nothing about a downstream's own use and is **not a patent grant**. Neither MIT nor the zlib grant recorded here contains an explicit patent clause.

## Obligations

1. Source and binary redistributions must keep the copyright, permission and warranty notices in `LICENSE`.
2. Every installed copy carries `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, `FORK-NOTES.md` and `enkiTS-License.txt` under `share/licenses/box2d/`, in every linkage and optimize mode (`enkiTS-License.txt` is enkiTS's zlib grant).
3. Keep the SPDX headers on the 119 upstream sources that carry them; `UPSTREAM.sha256` pins each one.
4. Copies containing these files carry the in-file notices in `extern/jsmn/jsmn.h` and `extern/glad/include/KHR/khrplatform.h`, the licence and source notices in `extern/enkiTS/`, and the Apache-2.0 terms for `samples/data/droid_sans.ttf`.
5. Do not use upstream's names to endorse a derived product without permission. This is the third MIT condition and applies to this fork's redistribution.
