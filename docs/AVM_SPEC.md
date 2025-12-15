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

## Implementation Strategy
1. `libavm` (C Library): Core VM loop, stack management, loader.
2. `oren avm` (CLI): Command to run `.obc` files using `libavm`.
3. `codegen_bytecode.oren`: Compiler backend to emit `.obc`.

## Known Limitations (Bootstrap v0.1)

- **Capability model is still evolving:** host calls support both a flat numeric ID table (`CALL_NATIVE`) and a domain/op model (`CALL_NATIVE2`); next-gen direction is specified in `docs/AVM_SPEC_V1.md`.
- **Verifier is rolling (now function-aware):** `avm` performs a bytecode verification pass (operand bounds, jump target bounds, const/global bounds, stack underflow/overflow, and stack-height consistency at CFG joins) and will reject malformed `.obc` early. Calls are verified interprocedurally by discovering reachable function entrypoints and verifying each region with **arity enforcement** (all `CALL addr` sites must agree on `nargs`). This verifier is still not a full formal proof of correctness.
- **Policy scanning is safe (rolling):** `avm --print-policy <file.obc>` (or `--print-policy-json`) scans capabilities used by a program **without executing bytecode**. This supports “scan before execute” governance workflows.
- **Hashing is rolling:** `avm` can compute deterministic `STATE_HASH` and `RESULT_HASH` (SHA-256) for swarm-style k-of-n validation; these are not yet stability-promised formats.
- **Deterministic record/replay is partial:** `avm` can record/replay FS-domain native calls via `AVM_RECORD_LOG` / `AVM_REPLAY_LOG`, but other effectful domains (NET/PROC/TIME/RNG) are not virtualized yet.
- **In-memory logs exist (rolling):** `AVM_RECORD_MEM=1` records to an in-memory bytes buffer (printed via `--print-record-log-hex`), and `AVM_REPLAY_LOG_HEX=...` replays without touching the filesystem.
- **Logs are budgeted (rolling):** `AVM_LOG_BYTES` limits bytes appended to record logs (file or in-memory), including the `AVMLOG01` header. This is enforced **before** executing record-mode side effects where possible (to avoid “did the effect but couldn't log it”).
- **TIME/RNG can be virtualized (rolling):** `AVM_DETERMINISTIC=1` enables a virtual monotonic clock and deterministic PRNG. In deterministic mode, `oren_time_now_ns()` is derived (no “advance on read”) from:
  - `AVM_TIME_START_NS` (virtual origin)
  - accumulated `oren_sleep_ms(ms)` (`+ ms * 1e6`)
  - executed “gas” count (`+ gas_executed * AVM_TIME_STEP_NS`, bootstrap: 1 gas per opcode dispatch)
  RNG is controlled by `AVM_RNG_SEED`.
- **Nested universes are emerging (rolling):** AVM exposes an `AVM` capability domain (domain 8) to run a child `.obc` from `BYTES` under a restricted capability/budget config (caps + gas/deadline/mem/io/log), returning hashes and a produced in-memory replay log.
- **Capability domains are the direction:** effectful calls should route through `CALL_NATIVE2` domains (e.g., `PROC` for `oren_system`) so they can be denied/recorded/replayed independently of CORE.
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
