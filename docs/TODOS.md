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

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.

## Tasks (Next, Highest Priority First)

1) **P0 [lang] Explicit fixed-width numeric types + type annotations** `[perf]`
   - DoD: Oren can express deterministic, hardware-level layouts without abusing attributes:
     - built-in type tokens: `u8/i8/u16/i16/u32/i32/u64/i64/u128/i128/f32/f64/bool`
     - type annotation syntax works for locals, params, returns, and struct fields
   - Next deliverables (in order):
     - codegen: exact-size memory layout for those types (esp. `packed` structs and endian casts)
     - keep attrs for metadata (`@json.name`, `@oren.packed`, etc.), not the type system

2) **P1 [vm] AVM SIMD: determinism-safe NEON baseline + guardrails** `[perf]`
   - DoD: `AVM_ENABLE_SIMD=1` is safe to enable for kernels without changing semantics.
   - Next deliverables (in order):
     - add a determinism guard test that runs the same `.obc` with SIMD off/on and compares output + trace hash
     - (optional) add i32 elementwise NEON kernels if profiling shows it matters

3) **P1 [vm] AVM v1 foundation: capability-governed host interface + determinism** `[safety]`
   - DoD: AVM supports the v1 direction (see `docs/AVM_SPEC_V1.md`) in a way that enables agentic execution:
     - capability domains (FS/NET/PROC/ENV/TIME) as explicit ops
     - deterministic TIME/RNG, snapshot/resume, multiverse

4) **P1 [arch] Traits/protocols: move from syntax to meaning** `[lang]`
   - DoD: trait/impl has real compile-time meaning without runtime vtables.
   - Next deliverables (in order):
     - compile-time ambiguity diagnostics for multiple impls of the same `Type.method`
     - (design) optional explicit qualification syntax for disambiguation (keep deterministic)

5) **P1 [stdlib] Oren-native AVM as builtin syslib component** `[arch]`
   - DoD: AVM can be built (later: rewritten) in `.oren` as part of the toolchain stdlib (`docs/STDLIB_LAYERS.md`).
   - Next deliverable: define the minimal “AVM-in-Oren” surface area (hosted by C AVM first).

6) **P1 [boot] Oren compiler as an AVM feature** `[arch]`
   - DoD: AVM can ingest `.oren`, compile to `.obc`, and run it in a child universe (no JIT; service-side JIT later).
   - Next deliverable: design the in-memory compilation pipeline + sandboxed module loader rules.

7) **P2 [maint] Capsule safety hardening (keep, but don't derail roadmap)** `[safety]`
   - DoD: syscall-first capsule enforcement stays airtight while language/AVM evolve.
   - Next deliverable: keep static audits + a small curated runtime fixture suite for each domain.

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- Endian helpers: added `oren_bytes_{get,set}_{u64,i64}_{be,le}` for C runtime, native runtime, and AVM bytecode (native IDs `90..105`), and extended tests to cover 64-bit cases.
- Packed views: `pack_view` lowering now uses the endian helpers (fewer runtime calls, smaller AST) instead of per-byte shifts for 16/32/64-bit fields.
- Native runtime safety: made `oren_is_err(v)` safe for large ints by probing only tracked heap pointers (prevents accidental segfaults when checking `oren_is_err(16909060)` etc).
- Native runtime safety: hardened `oren_bytes_get_u8/oren_bytes_set_u8` to avoid unsafe pointer probes on non-pointers; added regression in `test_integration_suite`.
