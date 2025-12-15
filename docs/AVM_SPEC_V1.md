# AVM Spec (Next-Gen, AI/ML-Focused, No-JIT-First)

**Status:** Draft (guidance + work plan)  
**Last updated:** 2025-12-15  
**Scope:** AVM bytecode format (`.obc`) + interpreter contract + host capability model

This document defines the **next evolutionary step** beyond `docs/AVM_SPEC.md` (bootstrap VM).

## 0) Design Goals (Non-Negotiables)

### G0.1 No-JIT-first

- Default execution is **interpreter-only** (compatible with iOS/App Store “no JIT” constraints).
- Optional **server-side JIT/AOT** may exist later, but must execute the *same* `.obc` semantics.

### G0.2 AI/ML-oriented primitives

- Efficient numeric compute is a first-class goal:
  - vector ops, reductions, dot products
  - typed buffers
  - predictable performance (avoid dynamic per-element overhead)

### G0.3 Self-healable execution model

- AVM must support robust failure boundaries:
  - deterministic error reporting
  - resumability via snapshotting (planned)
  - strict capability boundaries for host effects

Additionally:

- AVM must be “repair-friendly”: agents can replay failures, patch code, and rerun deterministically.

### G0.4 SOLID-governed “stdlib” boundaries

- Host functionality must be split into small, composable modules (interfaces), avoiding a monolithic “god module”.
- VM core stays minimal; “services” live behind capability-scoped native calls.

## 1) Versioning & Compatibility

### 1.1 Rolling ABI (current repo mode)

This repo is currently in **rolling ABI** mode:

- `.obc` is not version-gated today.
- Bytecode format and opcode set may change as the compiler and AVM evolve together.

When AVM reaches a “stability-promised” milestone, we can introduce explicit `.obc` versioning (major/minor + feature flags). Until then, treat the format as unstable.

### 1.2 Deterministic semantics first

All ops must define:

- integer overflow behavior (wrap vs trap) — pick one and freeze it
- float behavior (IEEE754 as platform provides) with documented corner cases
- string encoding assumptions (byte strings vs UTF-8 semantics)

Additionally required for agent-grade determinism:

- define truthiness rules precisely (what values are falsey)
- define map iteration order requirements (or explicitly declare maps unordered)
- define scheduler determinism policy for tasks (when coroutines land)

## 2) Value Model (Next-Gen)

The v0 model (`Nil/Int/Float/Bool/String/List/Map`) is not sufficient for ML-ish workloads.

### 2.1 Add `BYTES` (packed byte buffer)

Add value type:

- `BYTES`: `{ ptr, len }`, mutable or immutable (decide per op)

Rationale:

- avoids list-of-int overhead
- supports binary IO, bytecode parsing, hashing, and model artifact loading

Minimum ops:

- `BYTES_LEN`
- `BYTES_GET_U8`
- `BYTES_SET_U8` (optional if BYTES mutable)
- `BYTES_SLICE` (optional)

Bootstrap status (rolling, implemented in `lib/avm`):

- AVM now has a `BYTES` value type (`AVM_VAL_BYTES`) in addition to `String/List/Map`.
- Current bootstrap intrinsics are minimal and intentionally utilitarian:
  - `oren_bytes_from_hex(s)` / `oren_bytes_to_hex(bytes)` for binary-safe embedding via text
  - `oren_bytes_len(bytes)`, `oren_bytes_get_u8(bytes, i)`, `oren_bytes_set_u8(bytes, i, v)`
  - `oren_bytes_pack(list<int>)` / `oren_bytes_unpack(bytes)` to interop with existing list-based byte APIs
- Constant pool support exists (rolling): const tag `8` encodes `BYTES` as `u32_len + raw bytes`.

### 2.2 Add typed numeric buffers (core for ML)

Add value types for typed, packed numeric arrays:

- `I32_BUF`, `I64_BUF`
- `F32_BUF`, `F64_BUF`

Each buffer is `{ ptr, len }` where `len` is element-count.

Minimum ops:

- `BUF_LEN`
- `BUF_LOAD_{I32,I64,F32,F64}`
- `BUF_STORE_{I32,I64,F32,F64}`

Notes:

- `F32` buffers are the default for ML-ish compute (good perf/memory tradeoff).
- `F64` buffers remain useful for numerically sensitive reductions.

### 2.3 Keep `List/Map` for dynamic control/data

Lists/maps remain for:

- scripting
- JSON-like objects
- compiler metadata
- orchestration logic

But compute kernels should use typed buffers, not lists.

## 3) Instruction Set Direction (Next-Gen)

### 3.1 Keep the interpreter lean (no “feature explosion”)

Core VM opcodes remain small and stable:

- control flow
- locals/globals
- calls/returns
- minimal value construction

Performance comes from:

- typed buffer operations
- vector ops implemented as single opcodes (SIMD in host / optimized interpreter loops)

### 3.2 Split numeric ops into typed variants

The v0 design has `ADD/SUB` etc. without explicit typing. For ML, we need typed ops to avoid per-op type checks.

Introduce:

- `IADD`, `ISUB`, `IMUL` (and maybe `IDIV`)
- `FADD`, `FSUB`, `FMUL` (and maybe `FDIV`)

Also:

- `I2F`, `F2I` conversions

### 3.3 SIMD / vector kernel ops (ML-ish set)

Introduce a minimal set of vector ops on typed buffers:

- `VADD_F32(dst, a, b, n)`
- `VMUL_F32(dst, a, b, n)`
- `VDOT_F32(a, b, n) -> f32/f64`
- `VSCALE_F32(dst, a, scalar, n)`
- `VREDUCE_SUM_F32(a, n) -> f32/f64`

Execution strategy:

- interpreter provides a correct scalar fallback
- platforms with NEON/SIMD provide optimized loops
- server-side JIT/AOT (future) can fuse these

## 4) Host Interface: Capability-Scoped Native Calls

### 4.1 Replace “flat CALL_NATIVE” with capability domains

The bootstrap VM has a flat ID table (0..N). For SOLID governance and security, the next-gen plan defines:

- `CALL_NATIVE(domain, op, nargs)` (implemented today as `CALL_NATIVE2(domain, op, nargs)` in the rolling ABI)

Where:

- `domain` is a small integer selecting a capability module
- `op` selects the operation within that module

Examples of domains:

- `FS` (filesystem)
- `NET` (HTTP/DNS/etc.)
- `PROC` (subprocess)
- `ENV` (environment variables)
- `TIME` (clock, sleep)
- `CRYPTO` (hashing, random)
- `SIMD` (vector kernels)

### 4.2 Capability tokens

Host effects must be governed by explicit capability tokens:

- VM receives a capability set at startup
- each native call checks required capability
- denied calls return an error value (no undefined behavior)

This is a prerequisite for “self-healable” agents: failures are controlled, inspectable, and recoverable.

## 4.3 Resource metering (required for production safety)

AVM must support enforceable budgets:

- instruction count (“gas”) budget
- wall-time budget (with periodic preemption points)
- memory budget (heap + typed buffers)
- I/O budget (bytes read/written; network calls)

Metering is required for:

- running multiple agents safely
- preventing runaway scripts in constrained devices

## 4.4 Execution context (timeouts + cancellation)

The VM must run with an explicit execution context:

- `deadline_ns` (optional)
- `cancelled` flag / token (optional)
- budgets (gas/memory/io)

All effectful native calls (FS/NET/PROC/TIME/RNG) must either:

- accept an explicit timeout parameter, or
- consult the VM execution context for deadline/cancellation.

## 4.5 Capability domains (rolling assignments) + SOLID governance

The capability surface is split into **domains** to avoid a monolithic “god” native table and to enable least-privilege enforcement.

Current rolling assignments (subject to change):

- `0`: CORE (pure utilities, no external side effects; always allowed)
- `1`: FS (filesystem)
- `2`: TIME
- `3`: RNG / CRYPTO
- `4`: NET
- `5`: PROC
- `6`: SIMD (side-effect free vector kernels)
- `7`: ENV

Bootstrap status (rolling, implementation reality):

- `oren_system(cmd)` is treated as a **PROC** operation (domain `5`, op `0`) in the bytecode backend.
- `oren_exit(code)` is treated as a **PROC** operation (domain `5`, op `1`) in the bytecode backend.
- `oren_env(name)` is treated as an **ENV** operation (domain `7`, op `0`) in the bytecode backend.
- Legacy flat native IDs still exist for bootstrap compatibility, but effectful calls should move behind capability domains (PROC/FS/…).

Governance rules (SOLID-like):

- each domain has a single responsibility
- cross-domain dependencies are forbidden unless explicitly layered
- keep domain surfaces minimal; prefer composable primitives over “do everything” calls

### 4.5.1 Call encoding (bytecode ABI)

Rolling ABI encoding (implemented today):

- opcode: `CALL_NATIVE2`
- operands: `u8 domain`, `u16 op`, `u8 nargs`

### 4.5.2 Error contract (self-healing requirement)

Native calls must not hard-crash the VM for expected failures (permission denied, file not found, timeout).

Pick one representation and standardize it when a stability milestone is declared:

- dedicated `ERR` value type (preferred), or
- `nil` + error code, or
- a tagged map like `{ "ok": false, "code": ..., "msg": ... }`

### 4.5.3 Virtualization (“Matrix sandbox”) + record/replay

For testing/simulation and deterministic replay, host services should be virtualizable:

- FS can be backed by `VirtualFS` (in-memory, snapshot-friendly)
- NET can be backed by `VirtualNET` (fixtures / recorded responses)
- PROC can be disabled or simulated

In deterministic record/replay mode, the host can record all native call I/O and replay without touching the real host.

Bootstrap status (rolling):

- AVM supports a minimal record/replay log for FS-domain calls:
  - record: `AVM_RECORD_LOG=path ./avm build/program.obc`
  - replay: `AVM_REPLAY_LOG=path ./avm build/program.obc`
- AVM also supports deterministic “virtual” TIME/RNG for nested universes:
  - `AVM_DETERMINISTIC=1` uses a virtual monotonic clock and a deterministic PRNG
  - TIME is derived from VM work (no “advance on read”):
    - `now_ns = AVM_TIME_START_NS + sleep_accum_ns + gas_executed * AVM_TIME_STEP_NS`
    - `oren_sleep_ms(ms)` increases `sleep_accum_ns` by `ms * 1e6`
  - `AVM_RNG_SEED` seeds the deterministic PRNG
- This is intentionally minimal and is meant to evolve into full multi-domain virtualization (FS/NET/PROC/TIME/RNG) plus replay-log hashing.

## 5) Self-Healing Features (Planned)

### 5.1 Snapshot / restore (VM state)

Define a serialization format for:

- VM stack
- locals/globals
- heap objects (strings/bytes/buffers/lists/maps)
- program counter and call frames

Bootstrap status (rolling):

- `avm` supports a minimal snapshot/restore for `Nil/Int/Float/Bool/String/List/Map` to enable “pause and resume” workflows and future agent mobility.
- Snapshot files are intentionally marked rolling/unstable until a stability milestone is declared.

### 5.2 Deterministic execution mode

Add an optional “deterministic mode” to:

- control randomness (seeded RNG capability)
- control time access (virtual clock)
- control host side effects (record/replay)

This enables:

- reproducible agent behavior
- easier debugging and healing after failure

### 5.3 Bytecode verification + policy scanning (before execute)

Before execution, AVM should run a verifier pass:

- stack discipline validation (no underflow/overflow)
- constant pool bounds validation
- jump target validation
- native call operand decoding validation

Separately, a policy scanner should be able to answer:

- which capability domains are used by this program
- whether any forbidden domain/op appears

This is essential for safely executing LLM-generated or untrusted scripts.

## 6) Work Plan (Incremental, Test-Driven)

### Phase 1: Binary-safe IO baseline (DONE)

- `oren_read_bytes` implemented in C runtime and AVM host.

### Phase 2: Introduce `BYTES` value type

- Extend AVM C runtime:
  - `AVM_VAL_BYTES`
  - bytes construction + indexing
- Extend bytecode format:
  - bytes constant pool entry OR bytecode instruction to create bytes from const
- Add tests:
  - load `.obc`, verify bytes operations correctness

### Phase 3: Typed buffers + vector ops

- Add buffer types (`F32_BUF` first)
- Add `SIMD` domain ops (or opcodes) for vector math
- Add scalar fallback semantics and NEON-optimized implementation (macOS/Linux arm64)

### Phase 4: Capability domains split

- Replace v0 flat mapping with `(domain, op)` while keeping a compatibility mode for v0 programs (optional).

### Phase 5: Snapshotting (self-healable)

- Implement snapshot/restore for core types and execution state.

### Phase 6: Verifier + policy scanner

- Implement bytecode verification and “capability usage” scanning.
- Add tests:
  - invalid stack programs rejected
  - forbidden domain rejected under restricted capability set

## 7) Related Docs

- Current bootstrap VM: `docs/AVM_SPEC.md`
- Agentic requirements (language + compiler + AVM): `docs/AGENTIC_REQUIREMENTS.md`
- System evolution context: `docs/OREN_EVOLUTION.md`
- Roadmap: `docs/ROADMAP.md`
