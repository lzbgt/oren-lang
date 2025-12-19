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
   - Canonical curated suite (preferred): `./oren test --target macos`
   - Wrapper (same suite): `make test`

6) **Keep this file actionable** `[maint]`
   - Each P0/P1 item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list 5–10 items total; merge and delete aggressively.

## Tasks (Next, Highest Priority First)

1) **P0 [perf] Test suite speed: integration-first + parallel module tests**
   - Problem: too many small overlapping tests cause slow compile+run cycles.
   - DoD: `make test` stays fast; module tests run in parallel; output is failure-only.
   - Status: `make test` uses `./oretest` (Go runner) and module tests run with `--jobs` / `OREN_TEST_JOBS`.
   - Follow-up: make AVM tests parallel-safe by removing hardcoded `build/` assumptions (inject per-test base dir).

2) **P0 [lang] Fixed-width scalar tokens + packed struct field type annotations**
   - DoD: packed structs use `field: u8/u16be/...` (not `@oren.u16be`), and the syntax is documented as the network parsing story.
   - Follow-up: decide whether `u8/i32/f64` become true static types (v1 type system) vs v0 “annotation-only” sugar used by lowering passes.

3) **P0 [safety] Capsule OS-substrate: close remaining bypass surfaces** *(native backend)*
   - DoD: for each raw `sys_*` that can cause host effects (FS/NET/PROC/ENV/TIME), there is a capsule pre hook and tests cover allow+deny paths.
   - Next deliverable: add a single “capability audit test” that enumerates syscall intrinsics used by the native backend and asserts each has a pre hook.

4) **P0 [maint] Linux arm64 syscall parity for the curated native suite**
   - DoD: `./oren test --target linux` passes on a Linux arm64 environment (QEMU host or Docker/VM), for the curated native list.
   - Next deliverable: wire a minimal remote runner script (optional) + fix any ABI-table gaps discovered by the tests.

5) **P1 [correctness] String equality semantics + propagation** *(native backend)*
   - DoD: all string `==` cases in tests/stdlib are safe (including `nil`) and consistent across backends.

6) **P1 [prod] Floats + explicit casts** *(network + scientific code)*
   - DoD: defined semantics for casts (truncate vs checked), `f32/f64` support, and endian-aware helpers for packed parsing.

7) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - DoD: deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

8) **P2 [ux] Tooling**
   - `.obc` disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` bytes convention).

9) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (AVM/codegen) once behavior is covered by tests.

## Recently Completed (high signal)

- Test orchestration SOLID: `make test` now runs through `./oretest` (Go), not `lib/compiler/compiler.oren`.
- Packed struct views: migrated from `@oren.u16be` field attributes to `field: u16be` annotations (rolling).
- Native codegen ABI: treat X27/X28 as reserved global heap registers; preserve heap regs around every `svc`.
- Syscall-first policy guard: forbids direct `darwin_sys_*` / `linux_sys_*` usage outside approved lowering modules, and bounds direct `insn_svc` emission.
- OS ABI tables: repo-owned constants for `open` flags, `fcntl` cmds, `mmap` prot/flags (Darwin/Linux), with audit refs in `docs/refs/*` (incl. `darwin_sys_socket.h`, `darwin_sys_fcntl.h`).
- NET: translated Oren-level `getsockopt/setsockopt` IDs to OS ABI values safely (no cascading translation).
