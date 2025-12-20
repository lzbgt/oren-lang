# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (about 5–10 items): it is the execution order for the next engineering work.

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
   - Canonical curated suite (preferred): `./oretest --target macos`
   - Wrapper (same suite): `make test`

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

## Tasks (Next, Highest Priority First)

1) **P1 [vm] AVM v1 foundation: capability-governed host interface + determinism** `[safety]`
   - DoD: AVM supports the v1 direction (see `docs/AVM_SPEC_V1.md`) in a way that enables agentic execution:
     - capability domains (FS/NET/PROC/ENV/TIME) as explicit ops
     - deterministic TIME/RNG, snapshot/resume, multiverse

2) **P1 [arch] Traits/protocols: move from syntax to meaning** `[lang]`
   - DoD: trait/impl has real compile-time meaning without runtime vtables.
   - Next deliverables (in order):
     - compile-time ambiguity diagnostics for multiple impls of the same `Type.method` ✅
     - export trait declarations into module metadata JSON (`traits` section) ✅
     - (design) optional explicit qualification syntax for disambiguation (keep deterministic)
     - (design) blanket impls / generic impl templates + coherence rules (no overlap, deterministic selection)

3) **P1 [stdlib] Oren-native AVM as builtin syslib component** `[arch]`
   - DoD: AVM can be built (later: rewritten) in `.oren` as part of the toolchain stdlib (`docs/STDLIB_LAYERS.md`).
   - Next deliverable: define the minimal “AVM-in-Oren” surface area (hosted by C AVM first).

4) **P1 [boot] Oren compiler as an AVM feature** `[arch]`
   - DoD: AVM can ingest `.oren`, compile to `.obc`, and run it in a child universe (no JIT; service-side JIT later).
   - Next deliverable: design the in-memory compilation pipeline + sandboxed module loader rules.

5) **P2 [maint] Capsule safety hardening (keep, but don't derail roadmap)** `[safety]`
   - DoD: syscall-first capsule enforcement stays airtight while language/AVM evolve.
   - Next deliverable: keep static audits + a small curated runtime fixture suite for each domain.

6) **P2 [ux] API docs via attributes (FastAPI-style ergonomics, OpenAPI export)** `[lang]`
   - Goal: enable ergonomic HTTP libs (FastAPI-like) that can auto-export a modern API contract.
   - Direction:
     - use attributes as the source of truth (already in metadata JSON)
     - recommend `@get("/path")`, `@post("/path")`, `@tag("...")`, `@summary("...")`, `@deprecated()` etc.
     - export format: **OpenAPI 3.1** (sufficiently contemporary + tooling ecosystem)
   - DoD (later):
     - `oredoc openapi <module.meta.json>` emits a valid OpenAPI 3.1 document (even if schemas are “opaque” until v1 types stabilize)
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
- Native NET wait (v6): added syscall-first Linux `epoll_*` support + a shared readiness wait (`kqueue` on macOS, `epoll` on Linux) and removed busy retry loops from TCP connect/accept/read/write.
- Stdlib errno wrappers (v7): added `lib/std/result.oren` helpers to convert `-errno` syscall-style returns into structured errors.
