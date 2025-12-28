# Stack Safety (Recursion, Call Depth, and Deterministic Failure)

Oren targets **Tier‑1** `arm64` and `x86_64` on **macOS / Linux / Windows** with consistent
semantics across:

- native backend (Mach‑O/ELF/PE),
- C backend,
- bytecode backend + AVM.

Stack safety is part of that contract: programs must fail **deterministically** when they
exceed a configured budget, rather than crashing the host process with an OS stack overflow.

This document describes:

1) what exists today (facts),
2) what “stack safe” means for Oren,
3) the staged plan to make native/C match AVM behavior.

## Current State (Facts)

### AVM

AVM enforces a **call depth limit**:

- configured via `AVM_CALL_DEPTH_MAX` or `--call-depth-max`
- exercised by:
  - `tests/avm/test_call_depth_limit.oren`
  - `tests/avm/test_call_stack_discipline.oren`

This prevents recursion from consuming unbounded host stack (AVM is an interpreter with its
own call stack model).

### Native + C backends

Native and C binaries execute on the host’s call stack.

Today, recursion safety is primarily “best effort”:

- some tests exercise recursion (e.g. `tests/native/test_integration_suite.oren` contains
  recursion cases), but
- there is no unified “call depth max” knob for native/C that is guaranteed to produce a
  deterministic diagnostic instead of triggering an OS stack overflow.

## What “Stack Safe” Means for Oren

For production maturity, we want:

1) **Deterministic failure mode**
   - Exceeding the configured call depth should produce a stable, machine-readable
     diagnostic (consistent with the `OREN_DIAG` contracts used elsewhere).

2) **Backend parity**
   - The same program + same call-depth budget should behave the same on:
     - AVM (bytecode),
     - C backend,
     - native backend (arm64/x64).

3) **Low overhead by default**
   - The default configuration should be safe for development, but production builds should
     be able to choose a budget appropriate to their service.

4) **No secrets / no “security theater”**
   - Stack safety is about correctness and reliability (preventing host crashes),
     not anti-tamper.

## Design Options

### Option A — Compiler-inserted call depth counter (recommended v0)

Mechanism:

- Add a per-thread (or per-capsule) `call_depth` counter and `call_depth_max` limit.
- On function entry:
  - `call_depth += 1`
  - if `call_depth > call_depth_max`: abort with deterministic `OREN_DIAG`.
- On function exit:
  - `call_depth -= 1`

Where the counter lives (tiered):

- **AVM:** already exists in the VM implementation.
- **Native runtime:** store in runtime state (or TLS if/when we have threads).
- **C backend runtime:** store in a runtime global / TLS.

Key properties:

- deterministic across OS/arch (it does not depend on host stack size)
- easy to test and fuzz

Costs:

- adds a few instructions per function call (can be optimized later)

### Option B — OS stack probing / guard pages (not enough alone)

Relying on OS stack overflow behavior is not acceptable for parity:

- stack sizes differ across platforms (Windows vs Linux vs macOS),
- failures are not guaranteed to be catchable,
- behavior is not deterministic and can corrupt host state.

OS stack probing still matters for correctness in some ABIs (notably Windows), but it is a
separate problem from deterministic recursion limits.

### Option C — Tail call optimization (TCO) for tail recursion (v1+)

TCO can make many recursive functions stack-safe by converting tail calls into loops.

This is valuable but should not be the only guard because:

- not all recursion is tail-recursive,
- indirect calls + closures make TCO harder,
- it does not address deep mutual recursion unless we do more advanced transforms.

## Staged Plan (Rolling, Production-Oriented)

### P0 — Parity knob and deterministic diagnostic

1) Add `--call-depth-max` (compiler flag) for native and C backends.
2) Lower `--call-depth-max` into a runtime-visible limit.
3) Implement entry/exit instrumentation in shared lowering (CoreIR boundary), so all
   backends inherit the same semantics.
4) Add a cross-backend fixture:
   - same source compiled under `--backend bytecode`, `--backend c`, `--backend native`
   - proves consistent failure once depth exceeds budget.

### P1 — Reduce overhead (safe optimizations)

- elide instrumentation for known-leaf functions (no calls)
- allow “no depth checks” for internal runtime helpers that cannot recurse

### P2 — Tail-call optimization (optional, but valuable)

- implement TCO for direct tail calls first
- then extend to closure tail calls once callables converge on the canonical `{code_ptr, env_ptr}` ABI

## Related Work / Constraints

- Backend unification direction: `docs/BACKEND_ARCHITECTURE.md`
- AVM semantics + determinism: `docs/AVM_SPEC.md`

