# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short: it is the execution order for the next engineering work.

- Detailed history / completed items: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Fast curated suite (quiet output, preferred): `./oren test`
- Larger curated suite (quiet output): `make test`
- Verbose (prints each test command): `make test TEST_QUIET=0`
- Full AVM suite: `make test AVM_TESTS="tests/avm/*.oren"`
- Full native glob: `make test-native-all`

## P0 — Emergency / Blocks Rolling Progress

1) **Syscall-first native OS substrate: correctness before features**
   - Deliverables:
     - FS + PROC + ENV + TIME + NET are stable enough to build `.oren` stdlib without libc shims.
     - cancellable patterns (deadline/timeout) exist for PROC and NET wrappers.
     - native NET supports loopback TCP with explicit timeouts (no implicit hangs).
   - Acceptance:
     - native smoke covers: spawn/system, getenv/envp forwarding, sleep/time, TCP loopback.

2) **Oren-native build/test driver (reduce Makefile dependency)**
   - Deliverables:
     - `./oren test` is canonical and stays in sync with the curated suite.
     - Makefile is a thin wrapper (or optional) rather than the source of truth.
     - failure-only output + stable logs under `build/logs/`.
   - Acceptance:
     - contributors can iterate using only `./oren test` on macOS.

3) **“No hangs” guarantee (tests + tools)**
   - Deliverables:
     - Per-test timeouts for anything that can block (PROC/NET/TIME).
     - CLI-level AVM wall-time timeout remains supported (`--timeout-ms` / `AVM_TIMEOUT_MS`).
   - Acceptance:
     - A bug cannot deadlock CI/iteration indefinitely; timeouts fail fast with logs in `build/logs/`.

4) **Attributes/meta system: end-to-end preservation (serde + governance enabler)**
   - Deliverables:
     - Attributes preserved through parsing/linking/metadata (`--metadata`) and into `.obc` (for tooling/disasm).
     - Unknown attrs remain inert by default (determinism), strict mode exists for governance builds.
   - Acceptance:
     - Tests assert function/type/field/param attrs are preserved in emitted metadata.

5) **AVM deterministic cooperative concurrency MVP (single-threaded)**
   - Deliverables:
     - `task.spawn(fn, args)` / `task.join(id)` (deterministic ordering).
     - channels + `select` (deterministic ready selection).
     - integrate with TIME (virtual time), budgets (gas/deadlines), and snapshot/resume.
   - Acceptance:
     - A small agent loop (message passing + sleep/backoff) snapshots and resumes deterministically.

6) **Memory hygiene: “production hardening” baseline**
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
   - (Note: P0 covers preservation to `--metadata`; this item is specifically about `.obc` packaging.)
   - Follow-on: expose embedded metadata to `.oren` code via a safe AVM query primitive (so stdlib can implement attribute-driven serde without host effects).

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
- Compiler: native `--metadata` now preserves function/type/field/param attributes in `<out>.meta.json` (tooling surface for serde/governance).
- Compiler/AVM: `.obc` now embeds an unused `BYTES` constant with `"OREN_META\\n1\\n"` + JSON metadata so tools can discover attrs without sidecar files.
- Core runtime: `oren_string_from_bytes(list<int>)` exists across C backend + AVM + native backend (enables portable JSON parsing/building).
- Syslib: added `lib/std/json.oren` (explicit JsonValue representation, deterministic object key ordering).
