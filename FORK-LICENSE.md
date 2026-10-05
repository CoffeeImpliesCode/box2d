# Licence of the fork-authored additions

## What this file is

Upstream Box2D is MIT; its authoritative text is `LICENSE`, carried in this
repository unmodified and installed by the build graph with every copy of the
library. That text governs the upstream material inventoried in `NOTICE.md`.

Upstream terms do not, by themselves, grant anyone anything about files this
fork authored. This file records the separate grant for those files: what was
authorized, on what date, under which terms, and exactly which files it covers.

## The grant

* **Authorized by:** the owner of this repository, directly, on **2026-10-04**, as
  part of the contract-migration wave that adds Box2D as a standalone SDK. This
  is a direct authorization recorded here. It is not derived from any upstream
  permission, and no service query, ticket or publication receipt is claimed.
* **Terms:** the MIT licence, matching the primary upstream terms of this
  project. The authoritative text is `LICENSE`, the same text upstream ships; it
  is not restated here so that there is exactly one copy to keep current.
* **SPDX identifier for fork-authored files:** `MIT`. Every fork-authored
  source and build-graph file in this tree carries
  `SPDX-License-Identifier: MIT` on its first line. The Nix expressions, the
  JSON lock, the consumer package's own `build.zig.zon`, the shell profile, the
  digest record and the prose and licence records do not carry one; `NOTICE.md`
  lists exactly which files those are and why, because the absence of a header
  is not the absence of this grant.
* **Copyright holder:** not asserted here as an individual. The holder is the
  party that made the authorization above. No personal name is invented, and the
  upstream authors named in `LICENSE` and in the source SPDX headers are **not**
  claimed to own anything this fork wrote.

MIT is permissive, so this grant reaches nothing upstream did not already
license. The C core, the public headers, the upstream tests, the shared test
support, the docs and the vendored `extern/` trees keep the terms recorded in
`NOTICE.md`, and any modification this fork makes to an upstream file is recorded
there and in `CHANGELOG.md`.

## Files this grant covers

| Path | What it is |
| --- | --- |
| `build.zig`, `build.zig.zon` | The Zig build of the upstream C core, and the build options |
| `build_support/` | Fork-only build helpers, if the build graph needs any |
| `zig/root.zig`, `zig/*.zig` | The typed Zig facade and its `c` escape hatch |
| `zig/translate.h` | The fork's translation aggregate header |
| `runtime/` | The runtime-loading dispatch, descriptor and library module |
| `tests.zig` | The fork's behavioural tests |
| `smoke.zig` | The deterministic example smoke program |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` | The separate consumer package |
| `cross-test.profile.sh` | This fork's cross-target profile |
| `.github/workflows/verify.yml` | This fork's CI workflow, including the `sha256sum -c UPSTREAM.sha256` provenance job |
| `UPSTREAM.sha256` | The integrity record of the carried upstream bytes |
| `package.nix` | The one source-only derivation |
| `flake.nix` | The `static`, `shared` and `default` package attributes |
| `flake.lock` | The flake's resolved input pin: `nixpkgs` locked to revision `c7def046b9a883d46974757852106483d741586f` with a `narHash`, which is the revision `flake.nix` names. It is generated from that input and is reviewed like the rest. There is no `devenv.lock` in this tree; `devenv.yaml:31` pins its own input directly, evaluated as a flake |
| `devenv.nix`, `devenv.yaml`, `.envrc` | The canonical development environment |
| `README.md` | This fork's canonical README |
| `README.zig.md` | This fork's Zig interface documentation |
| `NOTICE.md` | The per-file licence and copyright inventory |
| `UPSTREAM.md` | The pin and the source inventory |
| `FORK-LICENSE.md`, `FORK-NOTES.md` | This file, and the fork's work record |
| `CHANGELOG.md` | The numbered change history |
| `.gitignore` fork block | The appended `.zig-cache/`, `zig-cache/`, `zig-out/`, `zig-pkg/`, `.devenv/`, `.direnv/` and `result*` entries; upstream's own patterns above them stay upstream content |

Four paths need their own sentence, because a filename alone does not say whose
content is in it:

* **`README.upstream.md` is upstream content.** It is a byte-for-byte copy of
  upstream's `README.md` at commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`,
  preserved unmodified so this fork's README could take the canonical path. It is
  MIT under `LICENSE`, not under this grant, and `UPSTREAM.sha256` proves its
  bytes still match.
* **`.gitignore` is upstream content plus a fork block.** Upstream's ten lines
  are unmodified; the fork's additions are the entries listed in the table above.
  The pristine upstream digest is in `UPSTREAM.md`.
* **`extern/` is not this fork's material.** `extern/jsmn/jsmn.h` carries its own
  MIT grant from a different holder, `extern/glad/include/KHR/khrplatform.h`
  carries a Khronos grant, the two generated glad files carry none of their own,
  and `extern/enkiTS/` is a vendored zlib tree under its own notice. See
  `NOTICE.md`.

* **`samples/data/droid_sans.ttf` is Apache-2.0**, © 2007 Google Corporation, by
  the terms in its own embedded name table. See `NOTICE.md`.

## What this grant does not do

* It does not relabel the tree as one thing. A reader must still be able to tell
  upstream material from fork additions, which is what `UPSTREAM.md`,
  `NOTICE.md`, `CHANGELOG.md` and this file are for.
* It does not cover per-file exceptions. The 149 carried files with no SPDX
  identifier — the 148 pinned in `UPSTREAM.sha256` that carry none, plus
  `.gitignore`, which that record deliberately does not pin — the vendored
  grants, the zlib enkiTS tree and the Apache-2.0 sample font keep their own
  terms; `NOTICE.md` names every one of them row by row.
* It does not reach upstream's build-time downloads that are still absent: GLFW,
  imgui and Tracy are not in this tree and no terms are claimed for them. enkiTS
  used to be in that position and is not any more; it is vendored under its own
  licence and this grant does not reach it.

* It grants nothing about a downstream's own use, and it is **not a patent
  grant**. Neither MIT nor the zlib grant recorded here contains an explicit
  patent clause, so nothing here should be read as one.

## Obligations that travel with the library

1. Redistributions, in source or binary form, keep `LICENSE`'s copyright notice,
   its permission notice and its warranty disclaimer.
2. Every installed copy carries the licence and provenance material under
   `share/licenses/box2d/`: the six files the build graph writes there, in every
   linkage and optimize mode — `LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`,
   `UPSTREAM.md`, `FORK-NOTES.md` and `enkiTS-License.txt`
   (`build.zig:549-578`, `build.zig:1426-1463`). The last of those is enkiTS's
   own zlib grant, not a second copy of this project's terms.
3. The per-file SPDX headers are not removed from the 119 upstream sources that
   carry them; `sha256sum -c UPSTREAM.sha256` pins every one of them.
4. The in-file notices of `extern/jsmn/jsmn.h` and
   `extern/glad/include/KHR/khrplatform.h` travel with any copy that carries
   those files, `extern/enkiTS/License.txt` and the notice in each enkiTS source
   file travel with any copy that carries that tree, and the Apache-2.0 terms
   travel with `samples/data/droid_sans.ttf`.
5. Upstream's names are not used to endorse a derived product without
   permission. That is the third MIT condition, and it applies to this fork's
   redistribution as much as to upstream's.