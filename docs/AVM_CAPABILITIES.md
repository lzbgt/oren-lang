# AVM Capability Model (CALL_NATIVE Domains)

**Status:** Draft (guidance + design constraints)  
**Last updated:** 2025-12-15

This document defines how AVM host calls are split into capability-scoped domains to support:

- security (sandboxing)
- SOLID governance (small modules, clear boundaries)
- self-healing (recoverable failures instead of undefined behavior)

## 0) Core Idea

All host effects are invoked via a **capability-scoped** API:

- VM bytecode encodes: `(domain, op, nargs)`
- VM runtime checks: “is this call allowed by the capability set?”
- Denied calls return a structured error value (or `nil` + error code) rather than crashing.

This avoids a monolithic, ever-growing “god” `CALL_NATIVE` table.

Related top-level requirements:

- `docs/AGENTIC_AI_TOP_FEATURES.md`

## 1) Domains (Proposed)

Domains are small integers (encoded in bytecode). The precise numbering is part of the ABI; reserve ranges for expansion.

Current rolling assignments (subject to change):

- `0`: CORE
- `1`: FS

### D0: CORE (pure utilities, no external side effects)

Examples:

- string length/slice/char ops
- int formatting
- list length/push/index_set

Notes:

- CORE is allowed in all sandboxes.
- CORE must remain deterministic given the same inputs.

### D1: FS (filesystem)

Examples:

- read bytes/text
- write bytes/text
- stat
- directory listing

Capability policy:

- allow-list by path prefix (recommended)
- explicit read-only vs read-write caps

### D2: TIME

Examples:

- monotonic time
- wall clock (optional)
- sleep

Determinism policy:

- in deterministic mode, TIME can be virtualized.

### D3: RNG / CRYPTO

Examples:

- secure random
- hash primitives (sha256)
- HMAC (optional)

### D4: NET (network)

Examples:

- HTTP GET/POST
- DNS resolution

Capability policy:

- allow-list by host/domain
- explicit “no network” mode

### D5: PROC (process)

Examples:

- spawn subprocess
- capture stdout/stderr

Policy:

- often disabled in restricted environments.
- in “agentic vm” this must be tightly controlled.

### D6: SIMD (vector kernels)

Examples:

- vector add/mul/dot/reduce on typed buffers

Policy:

- deterministic and side-effect free; safe to allow broadly.

## 2) Call Encoding (Bytecode ABI)

Recommended encoding:

- opcode: `CALL_NATIVE2`
- operands:
  - `u8 domain`
  - `u16 op`
  - `u8 nargs`

Current rolling FS ops (domain=1):

- `op=0`: `oren_read_file(path) -> string`
- `op=1`: `oren_write_file(path, content) -> nil`
- `op=2`: `oren_write_bytes(path, bytes) -> nil`
- `op=3`: `oren_read_bytes(path) -> list<int>`

Rationale:

- domain is small and frequently checked
- op expands per-domain without bloating global namespace

## 3) Error Contract (Self-Healing Requirement)

Native calls must not hard-crash the VM for normal failures (permission denied, file not found, network timeout).

Instead return:

- `ERR` value type, or
- `nil` + error code, or
- a tagged map like `{ "ok": false, "code": ..., "msg": ... }`

Pick one representation and freeze it when a stability milestone is declared.

## 3.1 Timeouts and cancellation

All effectful domains (FS/NET/PROC) should support:

- explicit timeouts (passed as args or provided by VM execution context)
- cancellation (VM-level cancellation token or “budget exceeded” abort)

Rationale:

- agents must be able to stop work when a better plan is found
- prevents resource leaks and unbounded waiting

## 3.2 Virtualization (“Matrix sandbox”)

For testing/simulation and for executing untrusted scripts safely, host services should be virtualizable:

- FS calls can be backed by a `VirtualFS` (in-memory, snapshot-friendly)
- NET calls can be backed by a `VirtualNET` (recorded responses / fixtures)
- PROC calls can be disabled entirely or simulated

In deterministic record/replay mode, the host can:

- record all native call I/O
- replay without touching the real host

This is a key enabler for large-scale agent simulation and safe debugging.

## 4) SOLID Governance Rules

To avoid module bloat:

- Each domain must have a single responsibility.
- Cross-domain dependencies are forbidden unless explicitly layered (e.g., NET must not depend on PROC).
- Keep domain surfaces minimal:
  - avoid “do everything” convenience calls
  - prefer composable primitives

## 5) Migration from v0
`docs/AVM_SPEC.md` currently defines a legacy flat `CALL_NATIVE` (numeric IDs).

Current repo policy (rolling mode):

- Prefer `CALL_NATIVE2(domain, op, nargs)` for new work.
- Keep legacy `CALL_NATIVE(id, nargs)` working for now to avoid breaking existing bytecode/tests.
- There is **no `.obc` version field** today; the compiler + AVM in this repo are expected to move together.

## 6) Rolling ABI Note (Current Repo Mode)

This repo is currently in **rolling ABI** mode:

- `.obc` is not version-gated today.
- Adding a new opcode (like `CALL_NATIVE2`) is allowed and may break older AVM binaries.
- The compiler and AVM in this repo are expected to move together.
