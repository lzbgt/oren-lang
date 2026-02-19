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

Today, both backends have a **deterministic recursion guard** (rolling):

- **C backend**
  - runtime implements `oren_call_depth_enter/exit()` with a per-thread counter + max
  - configured via env: `OREN_CALL_DEPTH_MAX` (default 8192; `0` disables the guard)
  - validated by `tests/native/fixtures/call_depth_overflow.oren` (compile+run under both backends)

- **Native backend (arm64 + x86_64)**
  - compiler inserts `oren_call_depth_enter()` on user-function entry and `oren_call_depth_exit()` on return
    (injected native runtime sources are intentionally excluded to keep bootstrap stable and low-overhead)
  - configured via env: `OREN_CALL_DEPTH_MAX` (default 8192; `0` disables the guard)
  - validated by the same fixture under `--backend native`
  - call depth is tracked per-thread via the registered native thread nodes (rolling v0:
    thread selection is based on the same SP-vs-top heuristic used by the GC stack scanner)

Practical note:

- Many Tier‑1 Linux environments (including WSL2) have a default `ulimit -s` of **8 MiB**.
  The call-depth hooks must stay extremely lightweight, and the compiler must never instrument
  the injected runtime itself with those hooks (or it can cause stack blowups during bootstrap).
- If you change native call-depth instrumentation rules (or other native codegen that affects the
  injected runtime), you must bump the rtobj backend signature in
  `lib/compiler/native_runtime_obj_cache.oren` so stale cached runtime objects are not reused.
  For debugging you can also force a “no rtobj” build by setting `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`.

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

3b) **Stackless when possible**
   - Direct **tail recursion** should compile to a loop (no host stack growth).
   - This is both a correctness feature (avoid OS stack overflow) and a performance feature
     (avoid call/ret overhead and repeated prologues).

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

Rolling status (today):

- The compiler performs **direct self tail recursion** elimination (conservative):
  - rewrites `return f(args...)` where `f` is the current function into parameter rebinding + loop `continue`
  - only when the tail return is not nested inside another loop (`while`/`for`) because we have no labeled continue
  - only for fixed-arity calls (no spread / varargs yet)
- The compiler can also eliminate a narrow subset of **non-tail** self recursion (tail recursion modulo constant):
  - rewrites `return f(args...) + <int>` and `return f(args...) - <int>` into a loop with an accumulator
  - only for a restrictive function shape (one `if` base return + one recursive return) and only when the base/cond contain no calls
- Fixture: `tests/native/fixtures/tail_recursion_ok.oren` (expected to succeed under low `OREN_CALL_DEPTH_MAX`)
  - Fixture: `tests/native/fixtures/non_tail_modconst_ok.oren`

### Option D — Heap-backed call frames (future; for non-TCO recursion)

Goal:

- For recursive calls that cannot be TCO-optimized, avoid consuming unbounded **host** stack by
  moving the “logical call stack” into heap-managed frames.

High-level approach (Tier‑1 direction):

- **Explicit heap call-frames** (stackless execution):
  - lower calls to a loop over a heap stack of frames (similar to how AVM works)
  - most deterministic across OS/arch, and naturally works with per-capsule budgets
  - requires a well-defined calling convention at the IR boundary (closures/varargs/spread) and
    runtime support for frame allocation and unwinding diagnostics

Status:

- Not implemented yet; tracked as a future production maturity item once CoreIR callables converge and
  the native runtime injection surface stabilizes.

## Staged Plan (Rolling, Production-Oriented)

### P0 — Parity knob and deterministic diagnostic

1) Add a call-depth budget knob across backends:
   - AVM: `--call-depth-max` / `AVM_CALL_DEPTH_MAX` (already exists)
   - C backend: `OREN_CALL_DEPTH_MAX` env (already exists)
   - native backend: `OREN_CALL_DEPTH_MAX` env (runtime override) and `oren build --call-depth-max <n>` (compile-time default)
2) Lower the budget knob into a runtime-visible limit in a single, shared contract (so “default vs override” behaves the same everywhere).
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

- Backend unification direction: `docs/COMPILER_AND_BACKENDS.md`
- AVM semantics + determinism: `docs/AVM_AND_OBC.md`
