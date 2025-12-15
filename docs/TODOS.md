# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-15

## P0 (Emergency / Blocking Safety)

### AVM (agentic execution substrate)

1) **Capsule hardening follow-ups**
   - `--capsule` / `--untrusted` now exists and implies `--verify-strict`, deny-by-default, and conservative budgets.
   - Added a capsule-friendly allowlist UX: `--allow-domains ...` and `--fs-allow-prefixes ...` (env vars still supported).
   - Next: make capsule allowlists part of a signed/hashed “job object” (bind policy/budgets to program + input hashes).

2) **Governance-ready policy object (bind to program + inputs)**
   - `--print-policy*` is scan-before-execute (no bytecode execution) and now outputs a stable `policy_hash_sha256` (`schema: avm.policy.v1`).
   - Added `--print-job` / `--print-job-json` (schema `avm.job.v1`) which computes `job_hash_sha256 = H(program_hash, policy_hash, input_hash)` without executing bytecode.
   - Updated `--print-job*` to schema `avm.job.v2`: `job_hash_sha256 = H(program_hash, policy_hash, input_hash, exec_hash)` where `exec_hash` binds effective allowlists + fs prefixes + budgets + deterministic knobs.
   - Next: bind output channels too (VirtualFS/VirtualPROC fixtures), then treat `job_hash` as the swarm consensus key.

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.
   - Bootstrap status: `avm --print-trace-hash` exists; next is “trace as BYTES” (export + budget) and richer event categories.

2) **Deterministic cooperative tasks (AVM concurrency model)**
   - Define/implement a deterministic scheduler (single-threaded baseline first).
   - Add a minimal `TASK` surface (spawn/join + channels/select) that composes with:
     - snapshot/restore
     - nested universes (child runs as a task)
     - budgets and capability gating
   - Design doc: `docs/AVM_CONCURRENCY.md`.

2) **Snapshot/restore “capsule” hardening**
   - Move toward capsule-friendly formats (hashable, resumable, policy-bound).

## P2 (Next-Gen AVM Performance + Features)

1) **Typed buffers + SIMD kernels (no-JIT-first path)**
   - Implement `F32_BUF` + minimal vector ops (`dot/add/mul/reduce`) with scalar fallback.

2) **VirtualNET / VirtualPROC backends (fixtures)**
   - Enable “Matrix sandbox” simulation and deterministic replay of realistic workflows.

## Recently Completed (for context)

- Deterministic TIME derived from executed gas (no “advance on now()”).
- Function-aware bytecode verifier (removes spurious stack-join rejects).
- AVM-in-AVM domain (nested universes) with determinism tests.
- Memory budget (`AVM_MEM_BYTES`) + AVM-in-AVM `cfg.mem_bytes` subset enforcement.
- FS I/O budget (`AVM_IO_BYTES`) + AVM-in-AVM `cfg.io_bytes` subset enforcement.
- Structured error contract: stable `__err/code/msg` with optional `domain/op` metadata for policy/budget failures.
- Policy scan: `--print-policy` outputs domain bitmask plus `(domain, op)` pairs and does not execute bytecode.
- Policy JSON: `--print-policy-json` outputs `schema: avm.policy.v1` plus `policy_hash_sha256` and does not execute bytecode.
- Strict verifier mode: `--verify-strict` / `AVM_VERIFY_STRICT=1` rejects legacy capability encodings (`CALL_NATIVE`, and CORE-domain `CALL_NATIVE2` that remaps to effectful domains).
- Capsule mode: `--capsule` / `AVM_CAPSULE=1` implies strict verify + deny-by-default + conservative default budgets.
- Leak-free teardown: VM frees remaining unreachable heap allocations at `avm_free()` (no tracing GC during run yet).
- Record/replay log budget (`AVM_LOG_BYTES`) + child `cfg.log_bytes` subset enforcement (preflight prevents un-loggable side effects in record mode).
- `avm` tooling: disasm/trace/breakpoints + mem-stats + `--repeat` + `--print-rss`.
