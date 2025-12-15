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

## Implementation Strategy
1. `libavm` (C Library): Core VM loop, stack management, loader.
2. `oren avm` (CLI): Command to run `.obc` files using `libavm`.
3. `codegen_bytecode.oren`: Compiler backend to emit `.obc`.

## Known Limitations (Bootstrap v0.1)

- **Capability model is still evolving:** host calls support both a flat numeric ID table (`CALL_NATIVE`) and a domain/op model (`CALL_NATIVE2`); next-gen direction is specified in `docs/AVM_SPEC_V1.md`.
- **Verifier is minimal (rolling):** `avm` performs a basic bytecode verification pass (operand bounds, jump target bounds, stack underflow checks) and will reject malformed `.obc` early. This verifier is not yet a full formal proof of correctness.
- **Hashing is rolling:** `avm` can compute deterministic `STATE_HASH` and `RESULT_HASH` (SHA-256) for swarm-style k-of-n validation; these are not yet stability-promised formats.
- **Metering is partial:** instruction “gas” and wall-time deadlines are enforced, but memory and IO budgets are not yet implemented.
- **Snapshot format is rolling:** AVM supports snapshot/restore for core types, but the file format is intentionally unstable while the repo is rolling.
- **Heap is malloc-based:** no tracing GC; long-running programs can leak unless the host reclaims per-run.
- **Numeric model is minimal:** only a subset of operators/constant types are encoded today.
