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

## Tasks (Next, Highest Priority First)

1) **P0 [maint] Fast, low-noise verification loop** `[perf]`
   - Problem: verification is still too slow/noisy to iterate aggressively.
   - DoD:
     - `make test` prints a compact summary by default (only failed test details).
     - A single integration “smoke suite” exercises the core feature set (lang + native + avm) so we can delete/merge redundant micro-tests.
     - Keep `--full`/`--verbose` modes for deep debugging (but not the default).
   - Current state:
     - `oretest` defaults to a “fast curated suite”; enable full suite via `OREN_TEST_FULL=1`.
     - Per-test progress is available via `OREN_TEST_VERBOSE=1`.
     - Linux docker runner supports the same flags and avoids stale build artifacts.

2) **P0 [lang] Exact-size layouts for fixed-width types (beyond packed views)** `[perf]`
   - Context: type tokens + annotation syntax already exist; now they must meaningfully affect layout/FFI.
   - DoD: Oren can express deterministic, hardware-level layouts without abusing attributes:
     - built-in type tokens: `u8/i8/u16/i16/u32/i32/u64/i64/u128/i128/f32/f64/bool`
     - type annotation syntax works for locals, params, returns, and struct fields
     - codegen honors exact widths when the programmer asks for it (esp. FFI + packet parsing + HPC kernels)
   - Keep attrs for metadata (`@json.name`, `@oren.packed`, etc.), not the type system.
   - Next deliverables (finishable slices):
     - v0 value-level semantics for annotated locals/params/returns/fields (cross-backend) ✅
     - syscall-first packet parsing story (native): typed buffers + endian ptr helpers + `u8_buf` bytes APIs ✅
     - opt-in `@oren.abi` layouts + `oren_abi_{sizeof,alignof,offsetof}` (no host headers) ✅
     - next slice (real layouts): make ABI layouts usable end-to-end for FFI structs (allocation + ptr accessors) without changing v0 struct/map semantics. ✅
     - next slice (real layouts v2): extend `@oren.abi` to cover nested ABI structs + pointers + fixed arrays (enables real OS structs + syscalls without host headers). ✅
     - next slice (real layouts v3): add u128/i128 layouts + fixed-array ptr helpers where needed, and thread target/arch ABI parameters through (no host headers). ✅
     - next slice (real layouts v4): add `usize/isize`, `*void`/opaque ptr conventions, and a small curated ABI structs set for OS syscalls (stat, sockaddr, kevent, epoll) in `.oren` with tests. ✅
     - next slice (real layouts v5): extend curated OS structs (sockaddr_in6, sockaddr_un, pollfd) + wire syscall wrappers in native stdlib (still no host headers). ✅
     - next slice (real layouts v6): nonblocking NET wait abstraction (kqueue vs epoll) with deterministic timeouts. ✅
     - next slice (real layouts v7): `errno`-typed result wrappers (stop manually threading `-errno` ints everywhere). ✅

3) **P1 [vm] AVM SIMD: determinism-safe NEON baseline + guardrails** `[perf]`
   - DoD: `AVM_ENABLE_SIMD=1` is safe to enable for kernels without changing semantics.
   - Next deliverables (in order):
     - (optional) add i32 elementwise NEON kernels if profiling shows it matters

4) **P1 [vm] AVM v1 foundation: capability-governed host interface + determinism** `[safety]`
   - DoD: AVM supports the v1 direction (see `docs/AVM_SPEC_V1.md`) in a way that enables agentic execution:
     - capability domains (FS/NET/PROC/ENV/TIME) as explicit ops
     - deterministic TIME/RNG, snapshot/resume, multiverse

5) **P1 [arch] Traits/protocols: move from syntax to meaning** `[lang]`
   - DoD: trait/impl has real compile-time meaning without runtime vtables.
   - Next deliverables (in order):
     - compile-time ambiguity diagnostics for multiple impls of the same `Type.method` ✅
     - (design) optional explicit qualification syntax for disambiguation (keep deterministic)

6) **P1 [stdlib] Oren-native AVM as builtin syslib component** `[arch]`
   - DoD: AVM can be built (later: rewritten) in `.oren` as part of the toolchain stdlib (`docs/STDLIB_LAYERS.md`).
   - Next deliverable: define the minimal “AVM-in-Oren” surface area (hosted by C AVM first).

7) **P1 [boot] Oren compiler as an AVM feature** `[arch]`
   - DoD: AVM can ingest `.oren`, compile to `.obc`, and run it in a child universe (no JIT; service-side JIT later).
   - Next deliverable: design the in-memory compilation pipeline + sandboxed module loader rules.

8) **P2 [maint] Capsule safety hardening (keep, but don't derail roadmap)** `[safety]`
   - DoD: syscall-first capsule enforcement stays airtight while language/AVM evolve.
   - Next deliverable: keep static audits + a small curated runtime fixture suite for each domain.

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Native NET wait (v6): added syscall-first Linux `epoll_*` support + a shared readiness wait (`kqueue` on macOS, `epoll` on Linux) and removed busy retry loops from TCP connect/accept/read/write.
- Stdlib errno wrappers (v7): added `lib/std/result.oren` helpers to convert `-errno` syscall-style returns into structured errors.
