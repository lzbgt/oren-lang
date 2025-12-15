# Agentic VM “Killer Features” (Requirements)

**Status:** Draft requirements list (guidance)  
**Last updated:** 2025-12-15  
**Applies to:** next-gen AVM and any sandboxed Oren execution mode

This document lists *essential* VM-level features for agentic execution. These are not all implemented today; they are the target capabilities that make the VM uniquely valuable for AI agents.

See also:

- `docs/AGENTIC_AI_TOP_FEATURES.md` (end-to-end language + compiler + AVM requirements)

## 1) Snapshot / Restore (Resumability)

The VM must be able to checkpoint and resume execution reliably:

- snapshot includes: program counter, call stack, operand stack, globals, and heap objects
- restore must resume deterministically (modulo allowed capabilities)

Why it matters:

- “self-healing” agents can recover after crash, timeout, or host restarts
- enables pause/continue across devices or sandbox boundaries

## 2) Deterministic Mode + Record/Replay

Provide a deterministic execution mode:

- time is virtualized (or explicitly provided)
- randomness is seeded and audited
- host calls are recorded (inputs/outputs) for replay

Why it matters:

- reproducible debugging
- safe “retry with fix” loops for agents

## 3) Capability-Based Host Calls (Least Privilege)

All host effects must be gated by explicit capabilities:

- capability domains (FS/NET/PROC/TIME/CRYPTO/…)
- allow-lists for filesystem prefixes and network targets
- “deny by default” in restricted environments

Why it matters:

- safe-by-construction execution for untrusted agent output
- easier governance of what code is allowed to do

See also:

- `docs/AVM_CAPABILITIES.md`

## 4) Resource Metering (Time / Memory / I/O)

To be production-safe, AVM needs enforceable budgets:

- instruction count (or “gas”)
- wall time budget (with preemption points)
- memory budget (heap + buffers)
- I/O budget (bytes read/written; network requests)

Why it matters:

- prevents runaway scripts
- makes scheduling multiple agents feasible

## 5) ML-Oriented Compute Primitives (No-JIT Friendly)

Interpreter-only performance must still be acceptable for ML-ish workloads:

- typed buffers (`F32`/`I32`) and bulk ops
- vector kernels (`dot`, `add`, `mul`, `reduce`) with NEON acceleration on ARM64
- scalar fallbacks with identical semantics

Why it matters:

- agents often need embedding math, scoring, vector search helpers
- “no-JIT-first” environments still need compute throughput

See:

- `docs/AVM_SPEC_V1.md`

## 6) Bytecode Verification + Policy Scanning (Before Execute)

Agents frequently execute dynamically generated code. The VM must reject unsafe/invalid programs early.

Requirements:

- bytecode verifier:
  - stack depth validation
  - jump target validation
  - constant pool bounds validation
  - native call operand decoding validation
- policy scanner (static):
  - detect “this program uses NET” / “this program uses PROC”
  - detect illegal domain/op usage for a given capability set

Why it matters:

- avoids running malformed bytecode
- prevents “capability bypass” via interpreter bugs

## 7) Structured Diagnostics (Self-Healing Support)

VM must emit structured, machine-readable diagnostics:

- stack traces with function names and source mapping (when available)
- error objects with codes + messages + context
- event log hooks (for observability and replay)

Why it matters:

- agents can automatically triage and propose fixes

## 8) Structured Concurrency Support (Cancellation + Deadlines)

Even with a “no-JIT-first” interpreter, agents need reliable cancellation.

Requirements:

- cancellation token in VM execution context
- explicit deadlines/timeouts on effectful calls (FS/NET/PROC) and on `sleep`
- safe abort that produces a structured error (`ERR_TIMEOUT` / `ERR_CANCELLED`) instead of undefined behavior

Why it matters:

- prevents hangs and resource leaks
- enables “best-first search” where losers are cancelled quickly

## 9) Hot Patching / Safe Reload (Optional, High Value)

Support “update code while keeping state”:

- load new code blob
- migrate state if compatible
- resume execution

Why it matters:

- enables repair loops without losing long-lived agent context
