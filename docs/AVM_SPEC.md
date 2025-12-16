# Agent Virtual Machine (AVM) Specification

**Note:** This document describes the **v0.1 bootstrap** AVM (minimal instruction set).
For the next step (no-JIT-first, ML-focused typed buffers/SIMD, capability-scoped natives), see:

- `docs/AVM_SPEC_V1.md`
- `docs/AGENTIC_REQUIREMENTS.md`

Compatibility policy:

- This repo is currently in **rolling ABI** mode: `.obc` format and opcodes may change.
- When an explicit “stability milestone” is declared later, AVM can introduce `.obc` versioning and a compatibility policy at that time.

## Architecture
AVM is a lightweight, stack-based virtual machine designed for executing Oren code in restricted environments (iOS, Edge, Web). It prioritizes safety, resumability, and simplicity.

### Data Model
- **Values:** `AvmValue` (`type` tag + union), see `lib/avm/avm.h`.
- **Stack:** `AvmValue[]` stack inside the VM (`lib/avm/avm.c`).
- **Heap:** Currently plain `malloc` allocations for strings/lists/maps (no GC yet).

## Bytecode Format (.obc)
**Current on-disk format (as implemented today):**

- **Header:** Magic (`0x0ECD`) only.
- **Const count:** `u16` (little-endian).
- **Constant Pool:** a sequence of tagged constants.
- **Code:** stream of 8-bit opcodes and operands (immediately after constants).

**Notes (implementation reality):**

- The bootstrap encoder/decoder currently does **not** write/read an explicit bytecode version field.
- The bootstrap constant pool currently supports:
  - `NIL`
  - `INT` (u64 payload)
  - `STRING` (u16 length + bytes)
  - `BYTES` (u32 length + bytes) (rolling; used for embedding binary blobs)
- `FLOAT` constants exist in the v0.1 instruction table but are not yet fully wired through the current bytecode backend.

## Instruction Set (Version 0.1)

| Opcode | Name | Operands | Stack (Before -> After) | Description |
|---|---|---|---|---|
| 0x00 | NOP | - | - | No operation. |
| 0x01 | HALT | - | - | Stop execution. |
| 0x02 | PUSH_CONST | `u16_idx` | `[] -> [val]` | Push constant from pool. |
| 0x03 | POP | - | `[val] -> []` | Discard top of stack. |
| 0x04 | LOAD_LOCAL | `u8_idx` | `[] -> [val]` | Load local variable. |
| 0x05 | STORE_LOCAL | `u8_idx` | `[val] -> []` | Store local variable. |
| 0x06 | LOAD_GLOBAL | `u16_idx` | `[] -> [val]` | Load global variable. |
| 0x07 | STORE_GLOBAL | `u16_idx` | `[val] -> []` | Store global variable. |
| 0x10 | ADD | - | `[a, b] -> [a+b]` | Add top two values. |
| 0x11 | SUB | - | `[a, b] -> [a-b]` | Subtract. |
| 0x12 | LT | - | `[a, b] -> [bool]` | Less than. |
| 0x13 | EQ | - | `[a, b] -> [bool]` | Equal. |
| 0x14 | NEQ | - | `[a, b] -> [bool]` | Not equal. |
| 0x15 | GT | - | `[a, b] -> [bool]` | Greater than. |
| 0x16 | LTE | - | `[a, b] -> [bool]` | Less than or equal. |
| 0x17 | GTE | - | `[a, b] -> [bool]` | Greater than or equal. |
| 0x18 | BITAND | - | `[a, b] -> [int]` | Bitwise AND. |
| 0x19 | BITOR | - | `[a, b] -> [int]` | Bitwise OR. |
| 0x1A | BITXOR | - | `[a, b] -> [int]` | Bitwise XOR. |
| 0x1B | SHL | - | `[a, b] -> [int]` | Shift Left. |
| 0x1C | SHR | - | `[a, b] -> [int]` | Shift Right. |
| 0x20 | PRINT | - | `[val] -> []` | Print top value to stdout. |
| 0x30 | JMP | `i16_off` | - | Unconditional jump. |
| 0x31 | JMP_IF | `i16_off` | `[cond] -> []` | Jump if truthy. |
| 0x38 | CALL | `u16_addr`, `u8_nargs` | `[args] -> []` | Call function. |
| 0x39 | RET | - | `[ret] -> []` | Return from function. |
| 0x3A | CALL_NATIVE | `u16_id`, `u8_nargs` | `[args] -> [ret]` | Call host function. |
| 0x3B | CALL_NATIVE2 | `u8_domain`, `u16_op`, `u8_nargs` | `[args] -> [ret]` | Call host function within a capability domain (rolling ABI). |
| 0x40 | NEW_LIST | `u16_count` | `[v1..vn] -> [list]` | Create list from n items. |
| 0x41 | NEW_MAP | `u16_count` | `[k1,v1..] -> [map]` | Create map from n pairs. |
| 0x42 | GET_INDEX | - | `[obj, key] -> [val]` | Get item from list/map. |
| 0x43 | SET_INDEX | - | `[obj, key, val] -> []` | Set item in list/map. |

## Native Intrinsics (ID map)
0. oren_read_file
1. oren_write_file
2. oren_system
3. oren_args
4. oren_env
5. oren_exit
6. oren_string_len
7. oren_string_char_at
8. oren_string_slice
9. oren_string_char_code_at
10. oren_int_to_string
11. (reserved)
12. oren_list_len
13. oren_list_push
14. oren_index_set
15. int_mod
16. oren_bytes_from_string
17. oren_write_bytes
18. oren_read_bytes
19. oren_err
20. oren_is_err
21. oren_err_code
22. oren_err_msg
23. oren_set_result
24. oren_get_result
30. oren_bytes_pack
31. oren_bytes_unpack
32. oren_bytes_len
33. oren_bytes_get_u8
34. oren_bytes_set_u8
35. oren_bytes_from_hex
36. oren_bytes_to_hex
43. oren_iter_next

## Implementation Strategy
1. `libavm` (C Library): Core VM loop, stack management, loader.
2. `oren avm` (CLI): Command to run `.obc` files using `libavm`.
3. `codegen_bytecode.oren`: Compiler backend to emit `.obc`.

## Known Limitations (Bootstrap v0.1)

- **Capability model is still evolving:** host calls support both a flat numeric ID table (`CALL_NATIVE`) and a domain/op model (`CALL_NATIVE2`); next-gen direction is specified in `docs/AVM_SPEC_V1.md`.
- **Verifier is rolling (now function-aware):** `avm` performs a bytecode verification pass (operand bounds, jump target bounds, const/global bounds, stack underflow/overflow, and stack-height consistency at CFG joins) and will reject malformed `.obc` early. Calls are verified interprocedurally by discovering reachable function entrypoints and verifying each region with **arity enforcement** (all `CALL addr` sites must agree on `nargs`). This verifier is still not a full formal proof of correctness.
- **Policy scanning is safe (rolling):** `avm --print-policy <file.obc>` (or `--print-policy-json`) scans capabilities used by a program **without executing bytecode**. This supports “scan before execute” governance workflows.
- **OBC inspection is safe (rolling):** `avm --inspect <file.obc>` (or `--inspect-json`) prints `.obc` metadata (file length, const count, code length, program hash, and the same capability policy view) **without executing bytecode**.
- **OBC disassembly can be machine-readable (rolling):** `avm --disasm-json <file.obc>` (or `--disasm-consts-json`) prints decoded bytecode in a JSON schema intended for debugger/profiler tooling.
- **Policy output is hashable (rolling):** policy scan outputs include `POLICY_HASH_SHA256 <hex>` (text) and `policy_hash_sha256` (JSON). This hash is computed from the *required* capability set discovered in bytecode (not from host allowlists). Current policy hash v1 is SHA-256 over:
  - tag bytes `AVMPOL01`
  - `used_domains_mask` as `u64_le`
  - `ops_len` as `u32_le`
  - each sorted `(domain, op)` pair as `u8` + `u16_le`
  JSON includes `{"schema":"avm.policy.v1", ...}`.
- **Job scanning is safe (rolling):** `avm --print-job <file.obc>` (or `--print-job-json`) prints a governance “job object” **without executing bytecode**. This binds:
  - `program_hash_sha256`: hash of `.obc` bytes (SHA-256)
  - `policy_hash_sha256`: required capability set (from policy scan)
  - `input_hash_sha256`: hash of explicit inputs (args after `--`, snapshot input file if any, replay log if any)
  - `exec_hash_sha256`: hash of execution context (capsule flags, effective allowlist, fs prefixes, budgets, deterministic knobs, **requested output surfaces**, and selected virtual backends/fixtures such as `fs_backend`, `proc_backend`, `proc_fixtures_hash_sha256`, `net_backend`, `net_fixtures_hash_sha256`)
  - `job_hash_sha256`: stable v7 hash over (`program_hash`, `policy_hash`, `input_hash`, `exec_hash`)
- **Hashing is rolling:** `avm` can compute deterministic `STATE_HASH` and `RESULT_HASH` (SHA-256) for swarm-style k-of-n validation; these are not yet stability-promised formats.
- **Deterministic trace hashing is available (rolling):** `avm --print-trace-hash <file.obc>` prints `TRACE_HASH ...` over a canonical trace-event stream (for agentic diffing).
- **Deterministic trace as data is available (rolling, best-effort):** `avm --print-trace-bytes-hex <file.obc>` prints:
  - `TRACE_TRUNCATED <0|1>` to indicate whether trace capture was cut short due to budget/alloc failure
  - `TRACE_BYTES_HEX ...` which is the trace-event stream encoded as `BYTES` and hex-encoded for transport
  Trace capture **must not** change program semantics: if trace bytes hit budget, AVM truncates (disables further capture) rather than aborting execution.
  Trace capture is also isolated from `AVM_MEM_BYTES`: trace bytes storage is governed by `AVM_TRACE_BYTES`, not by the VM heap budget for program values.

  Trace stream shape (rolling):
  - `TRACE_HASH` covers only *semantic* events: `STEP`, `CALL_NATIVE2`, `ABORT` (stable enough for k-of-n validation in rolling mode).
  - `TRACE_BYTES_HEX` may additionally include **bytes-only** diagnostic events like `ALLOC`/`FREE`/`REALLOC` to enable leak/memory profiling without perturbing consensus hashes.
- **Domains vs backends (important):** capability **domains** (FS/NET/PROC/…) define *what effect is being requested*; **backends** define *where that effect is executed*.
  - In “capsule / simulation” workflows, backends should default to **virtual** (no host effects).
  - In “trusted / live” workflows, a domain may still be allowed while using a **host** backend, but that must be an explicit choice bound into the execution context (`EXEC_HASH_SHA256`) so governance can tell “virtual run” vs “host run”.
  - Nested universes may select host backends only under strict subset rules (caps/allowlists/budgets), and doing so changes determinism/snapshot portability unless effects are recorded/replayed.

- **Deterministic record/replay is partial:** `avm` can record/replay FS-domain native calls via `AVM_RECORD_LOG` / `AVM_REPLAY_LOG`, but other effectful domains (NET/PROC/TIME/RNG) are not fully record/replayed yet (VirtualNET/VirtualPROC exist via fixtures).
- **VirtualFS backend exists (rolling):** set `--fs-backend vfs` (or `AVM_FS_BACKEND=vfs`) to route FS domain operations to an in-memory VirtualFS instead of the host filesystem. This enables “no host effects by default” workflows (still subject to capability gating, allow-prefixes, and IO/log budgets).
- **VirtualPROC backend exists (rolling):** set `--proc-backend vproc` (or `AVM_PROC_BACKEND=vproc`) to route `PROC.system` to a deterministic stub/fixture backend that performs no host subprocess effects. It returns:
  - `AVM_PROC_EXIT_CODE` (or `--proc-exit-code`) when no fixture matches
  - fixture exit codes when fixtures are provided via `--proc-fixtures-hex HEX` (or `AVM_PROC_FIXTURES_HEX=...`)
- **VirtualNET backend exists (rolling):** set `--net-backend vnet` (or `AVM_NET_BACKEND=vnet`) and provide fixtures via `--net-fixtures-hex HEX` (or `AVM_NET_FIXTURES_HEX=...`) to route NET calls to deterministic fixtures (no host network).
- **In-memory logs exist (rolling):** `AVM_RECORD_MEM=1` records to an in-memory bytes buffer (printed via `--print-record-log-hex`), and `AVM_REPLAY_LOG_HEX=...` replays without touching the filesystem.
- **Logs are budgeted (rolling):** `AVM_LOG_BYTES` limits bytes appended to record logs (file or in-memory), including the `AVMLOG01` header. This is enforced **before** executing record-mode side effects where possible (to avoid “did the effect but couldn't log it”).
- **TIME/RNG can be virtualized (rolling):** `AVM_DETERMINISTIC=1` enables a virtual monotonic clock and deterministic PRNG. In deterministic mode, `oren_time_now_ns()` is derived (no “advance on read”) from:
  - `AVM_TIME_START_NS` (virtual origin)
  - accumulated `oren_sleep_ms(ms)` (`+ ms * 1e6`)
  - executed “gas” count (`+ gas_executed * AVM_TIME_STEP_NS`, bootstrap: `gas_cost(op)=1` for every opcode dispatch)
  RNG is controlled by `AVM_RNG_SEED`.
- **Nested universes are emerging (rolling):** AVM exposes an `AVM` capability domain (domain 8) to run a child `.obc` from `BYTES` under a restricted capability/budget config (caps + gas/deadline/mem/io/log), returning hashes and a produced in-memory replay log.
  - Nested-universe `cfg` supports Virtual* backends and fixture injection as data (rolling, unstable):
    - `fs_backend` (0 host, 1 vfs), `vfs_fixtures` (`BYTES`, magic `AVMVFS01`)
    - `proc_backend` (0 host, 1 vproc), `proc_exit_code`, `proc_fixtures` (`BYTES`, magic `AVMPRC01`)
    - `net_backend` (0 host, 1 vnet), `net_fixtures` (`BYTES`, magic `AVMNET01`)
- **Capability domains are the direction:** effectful calls should route through `CALL_NATIVE2` domains (e.g., `PROC` for `oren_system`) so they can be denied/recorded/replayed independently of CORE.
- **Strict verification is available (rolling):** `avm --verify-strict <file.obc>` (or `AVM_VERIFY_STRICT=1`) rejects legacy capability encodings (`CALL_NATIVE`, and CORE-domain `CALL_NATIVE2` uses that remap to effectful domains) so untrusted capsules can require domain/op-only bytecode.
- **Capsule mode is available (rolling):** `avm --capsule <file.obc>` (or `AVM_CAPSULE=1`) enables safe defaults for running untrusted bytecode:
  - implies strict verification (`--verify-strict`)
  - enables deny-by-default capabilities (default allowlist is CORE + EXIT only)
  - defaults to Virtual* backends unless explicitly overridden:
    - FS uses `vfs` (no host filesystem effects) unless `--fs-backend host`
    - PROC uses `vproc` (no host subprocess effects) unless `--proc-backend host`
    - NET uses `vnet` (no host network; host NET is not implemented in bootstrap) unless `--net-backend host`
  - applies conservative default budgets unless overridden by env (`AVM_GAS`, `AVM_TIMEOUT_MS`, `AVM_MEM_BYTES`, `AVM_IO_BYTES`, `AVM_LOG_BYTES`)
  - to allow a small approved set without env vars, use:
    - `--allow-domains "0,1,6"` (or `AVM_ALLOW_DOMAINS=...`) to explicitly allow domains
    - `--fs-allow-prefixes "build/"` (or `AVM_FS_ALLOW_PREFIXES=...`) to restrict FS paths
- **Metering is rolling (implemented, not yet stability-promised):**
  - instruction “gas” (`AVM_GAS`)
  - wall-time deadline (`AVM_TIMEOUT_MS`)
  - heap memory budget for VM heap objects (`AVM_MEM_BYTES`)
  - FS I/O byte budget (`AVM_IO_BYTES`)
  - record/replay log growth budget (`AVM_LOG_BYTES`)
  Budget violations abort execution with a structured error (see below).
- **Snapshot format is rolling:** AVM supports snapshot/restore for core types, but the file format is intentionally unstable while the repo is rolling.
- **Heap is malloc-based:** no tracing GC; long-running programs can grow without bound. On teardown, `avm_free()` releases both reachable heap objects and any remaining VM-owned heap allocations to avoid per-process leak accumulation across runs.
- **Numeric model is minimal:** only a subset of operators/constant types are encoded today.

## Structured Errors (Rolling Contract)

AVM represents errors as a `MAP` with stable base fields:

- `__err: bool` — always `true` for error objects
- `code: int` — numeric error code (rolling)
- `msg: string` — human-oriented message (rolling; not stable for parsing)

For policy/budget related failures, AVM may additionally include:

- `domain: int` — capability domain that triggered the failure (optional)
- `op: int` — capability operation within that domain (optional)
