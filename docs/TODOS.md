# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-15

## P0 (Emergency / Blocking Safety)

### AVM (agentic execution substrate)

1) **Account replay/record log growth under budgets**
   - Count record/replay log growth under a budget (either extend `AVM_IO_BYTES` or add `AVM_LOG_BYTES`).
   - Enforce for:
     - file-based logs (`AVM_RECORD_LOG`)
     - in-memory logs (`AVM_RECORD_MEM=1` / `--print-record-log-hex`)
     - AVM-in-AVM (`domain=8` returning `record_log` as data)

2) **Policy output stabilization (hashable + governance-ready)**
   - Keep `--print-policy` “no execute” invariant.
   - Add a stable, machine-friendly output mode (e.g. JSON) once semantics stabilize.

3) **Legacy opcode deprecation path**
   - Keep `CALL_NATIVE` mapped into `(domain, op)` (done), then phase out legacy opcode when compiler emits `CALL_NATIVE2` everywhere.

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
- Memory budget (`AVM_MEM_BYTES`) + AVM-in-AVM `cfg.mem_bytes` subset enforcement.
- FS I/O budget (`AVM_IO_BYTES`) + AVM-in-AVM `cfg.io_bytes` subset enforcement.
- Structured error contract: stable `__err/code/msg` with optional `domain/op` metadata for policy/budget failures.
- Policy scan: `--print-policy` outputs domain bitmask plus `(domain, op)` pairs and does not execute bytecode.
- Leak-free teardown: VM frees remaining unreachable heap allocations at `avm_free()` (no tracing GC during run yet).
- `avm` tooling: disasm/trace/breakpoints + mem-stats + `--repeat` + `--print-rss`.
