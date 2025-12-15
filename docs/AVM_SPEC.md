# Agent Virtual Machine (AVM) Specification

## Architecture
AVM is a lightweight, stack-based virtual machine designed for executing Oren code in restricted environments (iOS, Edge, Web). It prioritizes safety, resumability, and simplicity.

### Data Model
- **Values:** `AvmValue` (`type` tag + union), see `lib/avm/avm.h`.
- **Stack:** `AvmValue[]` stack inside the VM (`lib/avm/avm.c`).
- **Heap:** Currently plain `malloc` allocations for strings/lists/maps (no GC yet).

## Bytecode Format (.obc)
- **Header:** Magic (`0x0ECD`), Version.
- **Constant Pool:** List of integers, floats, strings.
- **Code:** Stream of 8-bit opcodes and operands.

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

## Implementation Strategy
1. `libavm` (C Library): Core VM loop, stack management, loader.
2. `oren avm` (CLI): Command to run `.obc` files using `libavm`.
3. `codegen_bytecode.oren`: Compiler backend to emit `.obc`.
