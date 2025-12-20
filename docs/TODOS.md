# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode.

This file is the *single source of truth* for what to do next.

Priority model:

- **Order = priority.** The first unfinished item is the most urgent.
- We intentionally avoid fixed labels like “P0/P1”: the list is continuously reordered as reality changes.
- Completed items are moved to `docs/TODOS_ARCHIVE.md` to keep this file readable.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims / no libc dependency** `[arch]`
   - Native backend output must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - Runtime must be implemented via `sys_*` primitives + `.oren` code.

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - If code changes: run the canonical suite (preferred) `./oretest --target macos` (or `make test`).
   - If **docs-only** changes (only `docs/*` modified): tests are not required.

6) **Keep this file actionable** `[maint]`
   - Each P0/P1 item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list 5–10 items total; merge and delete aggressively.
   - Repo must build from a clean clone: ignore build outputs only (do not accidentally ignore source dirs like `cmd/oren/` or `cmd/oretest/`).

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.
   - Do not wipe the container workspace by default; incremental builds must be possible (use an explicit clean flag when required).
   - Prefer syncing **tracked sources only** (git index) into `/work/repo` so host-built binaries never pollute the container workspace.
   - Forward feature flags via env (e.g. `OREN_TEST_FULL=1`) so Linux matches macOS runner behavior.
   - Remove stale build outputs (`oren`, `oretest`, `avm`) before running `make` to avoid timestamp skew from tar sync.

8) **Never generate `*.oren.c` next to sources** `[maint]`
   - `./oren_bootstrap build path/to/file.oren` writes `file.oren.c` next to sources; Make may then treat the source as a build target via implicit C rules.
   - Avoid running bootstrap builds on in-tree modules/tests/tools; prefer `./oren build ... -o build/...` or the curated runners (`make test`, `./oretest`).
   - If you *did* create `*.oren.c` artifacts, delete them before running `make test` (keep `oren.oren.c` only).

9) ** Refactor in rolling **
  - when a file is over 2000 lines, refacotor to be SOLID principles applied modules

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[lang][quality] Doc comments (`///`) end-to-end (parse → metadata → tooling)**
   - DoD:
     - lexer/parser accept `///` doc comments and attach them deterministically to the next declaration (fn/struct/trait/impl/enum)
     - metadata JSON includes `doc` fields for public symbols
     - oretest has at least one integration test proving doc export works and is stable

2) **[lang][arch] Traits/protocols: coherence + generic impl templates (no runtime vtables in v0)**
   - DoD:
     - define coherence/overlap rules (deterministic selection; no spooky action at distance)
     - implement “blanket impls” / generic impl templates with non-overlap enforcement
     - optional explicit disambiguation syntax (when multiple impls are in scope)

3) **[lang][perf] Native backend optimizer baseline (no huge rewrite)**
   - DoD:
     - define a minimal IR boundary (or reuse current representation) that enables at least:
       - constant folding for numeric ops
       - dead-code elimination for unused locals/temporaries
       - peephole cleanup for redundant moves/loads
     - add a small microbenchmark `.oren` program in `examples/` + measure before/after in `docs/`

4) **[lang][safety] “Production panic” diagnostics: spans + stable backtrace mapping**
   - DoD:
     - panics/errors include function + source span where available
     - metadata provides enough PC→span mapping for AVM traces and native panics (rolling schema OK)
     - oretest enforces machine-readable one-line `OREN_DIAG ...` + stable fields

5) **[lang][arch] Module graph + reproducible builds (compiler surface)**
   - DoD:
     - stable module dependency graph export (JSON) for a build target
     - deterministic build ordering and deterministic artifact hashes in “deterministic mode”

6) **[lang][ux] Oren-native test runner direction (reduce Makefile coupling)**
   - DoD:
     - define minimal `.oren`-level test runner spec (output format, filters, JSON output)
     - keep `cmd/oretest` as orchestration for now, but document staged migration path

### B) AVM (evolves alongside language/compiler)

7) **[vm][safety] Record/Replay v1 for all effectful domains**
   - DoD:
     - record/replay for FS + NET + PROC + ENV + TIME + RNG
     - replay runs must not touch the host (even if the recorded run did)
     - replay logs are budgeted and portable (in-memory and file-backed)

8) **[vm][safety] Deterministic concurrency substrate (AVM tasks)**
   - DoD:
     - introduce `yield`/tasks with a deterministic scheduler mode (single-thread baseline)
     - define scheduling determinism (either deterministic policy or record/replay scheduling)
     - budgets propagate through task trees (structured concurrency)

9) **[vm][safety] Snapshot/restore format hardening + stability knobs**
   - DoD:
     - snapshot includes full VM state and validates on load
     - hash-friendly, chunkable layout (for swarm consensus + dedupe)
     - clear “rolling vs stable” policy for snapshots (separate from `.obc`)

10) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

11) **[stdlib][ux] API docs via attributes (FastAPI-style ergonomics, OpenAPI export)**
   - DoD:
     - `oredoc openapi <module.meta.json>` emits a valid OpenAPI 3.1 document
     - no runtime dependency; purely compiler metadata → spec

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- AVM SIMD: expanded NEON coverage to i32 typed-buffer kernels (add/mul/scale/reduce) with determinism guard (scalar vs SIMD result+trace hash) via `test_smoke_suite`.
- Verification loop: `oretest` is parallel + timeout-safe by default; it no longer requires GNU `timeout`/`gtimeout` on macOS (internal process-group kill).
- Varargs: implemented `fn f(a, ...rest)` end-to-end across parser + C backend + native backend + AVM bytecode, with spawn/join coverage and linux/arm64 docker verification.
- Runtime diagnostics: failures/panics now emit a stable `OREN_DIAG kind=... code=... msg=...` one-liner, enforced by `oretest` fixtures (AI-friendly, no lldb/otool needed).
- Fixed-width type tokens + annotations: `u8/i32/f64/...` are language-level types (not attributes) with cross-backend tests (e.g. typed struct fields and fn boundary normalization).
- Attribute ergonomics: added alias canonicalization so `@pack` → `@oren.packed`, `@abi` → `@oren.abi`, and `@json.*` → `@serde.*` (metadata stays canonical; pack-view tests use `@pack`).
- Metadata: trait declarations are preserved in module metadata JSON (`traits`, methods, and return annotations), enabling doc/serde tooling without runtime vtables yet.
- AVM determinism: integer arithmetic in the VM is now defined as i64 two’s-complement wraparound (no C signed-overflow UB), and invalid ops (div0, shift out of range) abort deterministically (covered by `tests/avm/test_smoke_suite.oren` + expected-failure `tests/avm/test_arith_invalid.oren`).
- AVM determinism guard: `oretest` reruns `test_smoke_suite` in scalar mode and requires `RESULT_HASH`/`TRACE_HASH` to match (catches uninitialized/pointer-order hash issues).
- Native NET wait (v6): added syscall-first Linux `epoll_*` support + a shared readiness wait (`kqueue` on macOS, `epoll` on Linux) and removed busy retry loops from TCP connect/accept/read/write.
- Stdlib errno wrappers (v7): added `lib/std/result.oren` helpers to convert `-errno` syscall-style returns into structured errors.
