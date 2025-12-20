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

## Tasks (Next, Highest Priority First)

1) **P0 [lang] Exact-size layouts for fixed-width types (beyond packed views)** `[perf]`
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
     - next slice (real layouts v4): add `usize/isize`, `*void`/opaque ptr conventions, and a small curated ABI structs set for OS syscalls (stat, sockaddr, kevent, epoll) in `.oren` with tests.

2) **P1 [vm] AVM SIMD: determinism-safe NEON baseline + guardrails** `[perf]`
   - DoD: `AVM_ENABLE_SIMD=1` is safe to enable for kernels without changing semantics.
   - Next deliverables (in order):
     - (optional) add i32 elementwise NEON kernels if profiling shows it matters

3) **P1 [vm] AVM v1 foundation: capability-governed host interface + determinism** `[safety]`
   - DoD: AVM supports the v1 direction (see `docs/AVM_SPEC_V1.md`) in a way that enables agentic execution:
     - capability domains (FS/NET/PROC/ENV/TIME) as explicit ops
     - deterministic TIME/RNG, snapshot/resume, multiverse

4) **P1 [arch] Traits/protocols: move from syntax to meaning** `[lang]`
   - DoD: trait/impl has real compile-time meaning without runtime vtables.
   - Next deliverables (in order):
     - compile-time ambiguity diagnostics for multiple impls of the same `Type.method` ✅
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
- Test wall-time + stability: `./oretest` now runs module+avm suites concurrently under a shared job budget, and the Linux docker runner reuses `/work/repo` by default while syncing tracked sources only (prevents host-built binaries from polluting the container).
- ABI layouts (end-to-end usable): added pointer allocation (`oren_ptr_alloc`/`oren_ptr_free`) plus endian-aware pointer accessors in the C runtime (`oren_ptr_get/set_*_{be,le}`) and a module regression (`tests/modules/test_abi_ptr_access.oren`).
- ABI layouts (nested v2): `@oren.abi` now supports nested ABI structs, pointers (`*T`), and fixed arrays (`T[N]`), plus a regression test `tests/modules/test_abi_nested_arrays.oren`.
- ABI layouts (v3): added u128/i128 layout support and threaded `--arch` into the compiler config (currently `arm64` only) + regression `tests/modules/test_abi_u128_layout.oren`.
- Tooling hardening: `oren build <missing.oren>` now exits non-zero and `oretest` has a regression fixture to prevent silently-successful builds on missing input files.
- AVM SIMD determinism guard: `./oretest` now runs `test_smoke_suite` with `--print-result-hash --print-trace-hash` and compares scalar vs `AVM_ENABLE_SIMD=1` hashes (arm64 only).
- Endian helpers: added `oren_bytes_{get,set}_{u64,i64}_{be,le}` for C runtime, native runtime, and AVM bytecode (native IDs `90..105`), and extended tests to cover 64-bit cases.
- Packed views: `pack_view` lowering now uses the endian helpers (fewer runtime calls, smaller AST) instead of per-byte shifts for 16/32/64-bit fields.
- Bytecode backend: `TypeName(...)` constructor calls now compile to `NEW_LIST` (portable struct representation), removing the need for implicit runtime functions for types.
- f32 semantics: deterministic float32 rounding boundary implemented as `oren_f32_round(x)` across backends (C runtime helper, AVM native id `106`, arm64 native intrinsic).
- Native runtime: typed buffers implemented for the syscall-first native backend (i32/i64/f32/f64) including scalar bulk ops; f32 load/store uses `oren_f32_to_u32_bits` / `oren_u32_bits_to_f32` intrinsics.
- Native runtime: endian-aware pointer helpers (`oren_ptr_get/set_{u16,u32,u64,i16,i32,i64}_{be,le}`) for syscall-first packet parsing directly from malloc buffers.
- Native runtime safety: made `oren_is_err(v)` safe for large ints by probing only tracked heap pointers (prevents accidental segfaults when checking `oren_is_err(16909060)` etc).
- Native runtime safety: hardened `oren_bytes_get_u8/oren_bytes_set_u8` to avoid unsafe pointer probes on non-pointers; added regression in `test_integration_suite`.
- Native runtime: made `u8_buf` iterable (`for x in bytes`) and added native bytes hex/pack/unpack coverage.
- Native runtime: added `oren_u8_buf_wrap_ptr` to wrap malloc buffers as bytes without copying (enables `pack_view` directly over syscall read buffers).
- Type annotations: `bool` normalization is now explicit (`oren_bool_norm`) so annotated params/locals/returns have consistent numeric semantics across backends.
- ABI layouts: added opt-in `@oren.abi` + compile-time `oren_abi_{sizeof,alignof,offsetof}` (no host headers) and a module test.
