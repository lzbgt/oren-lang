# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-15

## P0 (Emergency / Blocking Safety)

### AVM (agentic execution substrate)

1) **Memory budget enforcement (heap + buffers)**
   - Add hard limit env: `AVM_MEM_BYTES=<n>` (and child `cfg.mem_bytes` for AVM-in-AVM).
   - Enforce on all heap objects (`String/List/Map/Bytes`) and log buffers.
   - Add a deterministic failure: `AVM_ERR_BUDGET` with message like `budget exceeded (mem)`.

2) **I/O budgets and accounting (FS first)**
   - Add `AVM_IO_BYTES=<n>` for bytes read/written and record/replay log growth.
   - Enforce in FS domain (`CALL_NATIVE2 domain=1`) and record/replay serializers.

3) **Structured error contract (stable fields + codes)**
   - Document stable error fields and codes (`code`, `msg`, optional `domain/op`).
   - Ensure budgets/capability denials always produce consistent errors.

4) **Policy scanner precision**
   - Extend `--print-policy` to output domain+op usage (not just a domain bitmask).

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.

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
- `avm` tooling: disasm/trace/breakpoints + mem-stats + `--repeat` + `--print-rss`.
