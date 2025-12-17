# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short: it is the execution order for the next engineering work.

- Detailed history / completed items: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Fast curated suite (quiet output): `make test`
- Verbose (prints each test command): `make test TEST_QUIET=0`
- Full AVM suite: `make test AVM_TESTS="tests/avm/*.oren"`
- Full native glob: `make test-native-all`

## P0 — Emergency / Blocks Rolling Progress

1) **AVM deterministic cooperative concurrency MVP (single-threaded)**
   - Deliverables:
     - `task.spawn(fn, args)` / `task.join(id)` (deterministic ordering).
     - channels + `select` (deterministic ready selection).
     - integrate with TIME (virtual time), budgets (gas/deadlines), and snapshot/resume.
   - Acceptance:
     - A small agent loop (message passing + sleep/backoff) snapshots and resumes deterministically.

2) **“No hangs” guarantee (tests + tools)**
   - Deliverables:
     - Per-test timeouts for anything that can block (PROC/NET/TIME).
     - CLI-level AVM wall-time timeout remains supported (`--timeout-ms` / `AVM_TIMEOUT_MS`).
   - Acceptance:
     - A bug cannot deadlock CI/iteration indefinitely; timeouts fail fast with logs in `build/logs/`.

3) **Syscall-first native OS substrate: correctness before features**
   - Deliverables:
     - FS + PROC + ENV + TIME + NET are stable enough to build `.oren` stdlib without libc shims.
     - cancellable patterns (deadline/timeout) exist for PROC and NET wrappers.
   - Acceptance:
     - native smoke covers: spawn/system, getenv/envp forwarding, sleep/time, TCP loopback.

4) **Memory hygiene: “production hardening” baseline**
   - Deliverables:
     - zero known leaks in native runtime + AVM teardown for curated tests.
     - add deterministic, failure-only diagnostics surfaces (trace-bytes / alloc profile).
   - Acceptance:
     - `make test` runs repeatedly without monotonic memory growth (spot-check via local tooling).

## P1 — High Leverage Toward Final Product

1) **Packed struct views over bytes (network parsing; zero allocation)**
   - PV1: schema via attributes (metadata-only)
   - PV2: `pack_view(TypeName, bytes, offset)` intrinsic
   - PV3: lower `view.field` reads to endian-safe `bytes_get_u{N}_{be|le}` with bounds checks

2) **Fixed-width scalar types + explicit casts**
   - Add `i8/i16/i32/i64/u8/u16/u32/u64` (+ `u128` later) and `f32/f64`.
   - Endian-aware casts for packet parsing (optional `be/le`).

3) **Attributes/meta system: embed into `.obc`**
   - Preserve function/type/field/param attributes end-to-end for tooling and governance.

4) **`libavm` embedding API + “AVM as Oren stdlib”**
   - C API: run program bytes, return result + hashes + trace/record/snapshot as BYTES.
   - Oren bindings so `.oren` can spawn child universes without shelling out.

5) **Compiler-in-AVM MVP (close the loop)**
   - Compile a small `.oren` subset to `.obc` inside a deterministic capsule (VirtualFS IO).

6) **Tooling: `.obc` disassembler + non-interactive debugger hooks**
   - Disasm first (“otool-like”), then debugger primitives (breakpoints/step/stack dump), then interactive UI.

## P2 — Later / Performance / Expansion

1) **Typed buffers + SIMD kernels (no-JIT-first)**
2) **Native concurrency roadmap: N:1 greenlets → N:M GMP**
3) **Linux arm64 parity + continuous smoke**
4) **AVM host NET (record/replay)**
5) **Interactive debugger UI**

## Recently Completed

- AVM: bytecode supports first-class function values + closures (capture-by-value v0) with `PUSH_FUNC`, `MAKE_CLOSURE`, `LOAD_ENV`, `CALL_INDIRECT` and a regression `tests/avm/test_closure_fn_values.oren`.
