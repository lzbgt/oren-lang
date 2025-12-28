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
- **Stack:** `AvmValue[]` stack inside the VM (`lib/avm/avm_vm.c`).
- **Heap:** Currently plain `malloc` allocations for strings/lists/maps (no GC yet).

## Bytecode Format (.obc)
**Current on-disk format (as implemented today):**

- **Header:** Magic (`0x0ECD`) only.
- **Const count:** `u16` (little-endian).
- **Constant Pool:** a sequence of tagged constants.
- **Code:** stream of 8-bit opcodes and operands (immediately after constants).

**Notes (implementation reality):**

- The bootstrap encoder/decoder currently does **not** write/read an explicit bytecode version field.
- The bootstrap constant pool currently supports (tagged constants, tag is `u8`):
  - `0`: `NIL` (no payload)
  - `1`: `INT` (`u64` payload, little-endian)
  - `2`: `BOOL` (`u8` payload, `0|1`)
  - `3`: `FLOAT` (`u64` payload, little-endian) — IEEE-754 `float64` bit pattern
  - `4`: `STRING` (`u16` length + bytes, little-endian length)
- `8`: `BYTES` (`u32` length + raw bytes, little-endian length)
- Rolling convention: the compiler currently appends an **unused** `BYTES` constant containing metadata:
  - payload prefix: ASCII `"OREN_META\n1\n"`
  - remainder: UTF-8 JSON metadata (same structure as native `--metadata` output)
  - this constant is intentionally not referenced by bytecode, so it does not affect execution semantics.
- Rolling convention: the compiler may also append an **unused** `BYTES` constant containing “OBX” module metadata:
  - payload prefix: ASCII `"OREN_OBX\n1\n"`
  - payload is a binary table of exports + relocations used by a linker
  - this constant is also intentionally not referenced by bytecode
  - see `docs/OBC_MODULE_LINKING.md`
- Rolling convention: `.obc` may include an **unused** `BYTES` constant containing an “OREN_SIG” signature payload:
  - payload prefix: ASCII `"OREN_SIG\n1\n"`
  - payload contains an ed25519 signature over a canonical `.obc` hash (excluding OREN_SIG constants)
  - AVM can optionally require this signature before executing bytecode
  - see `docs/APPSTORE_ROOTCA_AND_UPDATES.md`
- `FLOAT` constants are wired end-to-end (rolling): the bytecode backend emits float64 bit-pattern constants and the VM decodes them as `AVM_VAL_FLOAT`.

## Instruction Set (Rolling Bootstrap v0.1)

**Byte order:** all multi-byte operands are little-endian on disk (`u16_le`, `i16_le`, `u32_le`, `i32_le`).

| Opcode | Name | Operands | Stack (Before -> After) | Description |
|---|---|---|---|---|
| 0x00 | NOP | - | - | No operation. |
| 0x01 | HALT | - | - | Stop the current task; for task 0, halts the VM. |
| 0x02 | PUSH_CONST | `u16_le const_idx` | `[] -> [val]` | Push constant from pool. |
| 0x03 | POP | - | `[val] -> []` | Discard top of stack. |
| 0x04 | LOAD_LOCAL | `u8 idx` | `[] -> [val]` | Push local value at `fp+idx`. |
| 0x05 | STORE_LOCAL | `u8 idx` | `[val] -> []` | Pop value and store to `fp+idx`. |
| 0x06 | LOAD_GLOBAL | `u16_le idx` | `[] -> [val]` | Push global value at `globals[idx]`. |
| 0x07 | STORE_GLOBAL | `u16_le idx` | `[val] -> []` | Pop value and store to `globals[idx]`. |
| 0x10 | ADD | - | `[a, b] -> [a+b]` | Add (ints wrap on overflow; floats supported; also string concat for string+string). |
| 0x11 | SUB | - | `[a, b] -> [a-b]` | Subtract (ints wrap on overflow; floats supported). |
| 0x1D | MUL | - | `[a, b] -> [a*b]` | Multiply (ints wrap on overflow; floats supported). |
| 0x1E | DIV | - | `[a, b] -> [a/b]` | Divide (errors on division by zero and `INT64_MIN / -1`). |
| 0x1F | MOD | - | `[a, b] -> [a%b]` | Modulo (errors on modulo by zero and `INT64_MIN % -1`). |
| 0x12 | LT | - | `[a, b] -> [bool]` | Less-than comparison (int/float/string supported). |
| 0x13 | EQ | - | `[a, b] -> [bool]` | Equality comparison (type-aware). |
| 0x14 | NEQ | - | `[a, b] -> [bool]` | Not-equal comparison (type-aware). |
| 0x15 | GT | - | `[a, b] -> [bool]` | Greater-than comparison (int/float/string supported). |
| 0x16 | LE | - | `[a, b] -> [bool]` | Less-than-or-equal comparison (int/float/string supported). |
| 0x17 | GE | - | `[a, b] -> [bool]` | Greater-than-or-equal comparison (int/float/string supported). |
| 0x18 | AND | - | `[a, b] -> [int]` | Bitwise AND (int only; otherwise yields `nil`). |
| 0x19 | OR | - | `[a, b] -> [int]` | Bitwise OR (int only; otherwise yields `nil`). |
| 0x1A | XOR | - | `[a, b] -> [int]` | Bitwise XOR (int only; otherwise yields `nil`). |
| 0x1B | SHL | - | `[a, b] -> [int]` | Logical shift-left (int only; errors if shift count not in `0..63`). |
| 0x1C | SHR | - | `[a, b] -> [int]` | Logical shift-right (int only; errors if shift count not in `0..63`). |
| 0x20 | PRINT | - | `[val] -> []` | Print a value (debug). |
| 0x21 | PRINT_LIST | - | `[list] -> []` | Print list items separated by spaces (debug). |
| 0x30 | JMP | `i16_le off` | - | Relative jump (`pc := pc + off`) after decoding operands. |
| 0x31 | JMP_IF | `i16_le off` | `[cond] -> []` | Pop condition; if truthy, relative jump. |
| 0x4E | JMP32 | `i32_le off` | - | Relative jump with 32-bit offset. |
| 0x4F | JMP_IF32 | `i32_le off` | `[cond] -> []` | Pop condition; if truthy, relative jump with 32-bit offset. |
| 0x38 | CALL | `u16_le addr, u8 nargs` | `[args...] -> [ret]` | Call function at `addr` (abstract stack effect; see `RET` convention below). |
| 0x50 | CALL32 | `u32_le addr, u8 nargs` | `[args...] -> [ret]` | Call function at `addr` (32-bit address). |
| 0x39 | RET | - | `[ret] -> [ret]` | Return: pop callee return, discard callee frame, then push return for caller. |
| 0x3A | CALL_NATIVE | `u16_le id, u8 nargs` | `[args...] -> [ret]` | Call legacy native ID (internally remapped to `CALL_NATIVE2` domain/op). |
| 0x3B | CALL_NATIVE2 | `u8 domain, u16_le op, u8 nargs` | `[args...] -> [ret]` | Call a native capability `(domain, op)` (rolling ABI). |
| 0x3C | PUSH_FUNC | `u16_le addr` | `[] -> [fn]` | Push a function value `{addr, env=nil}`. |
| 0x51 | PUSH_FUNC32 | `u32_le addr` | `[] -> [fn]` | Push a function value `{addr, env=nil}` (32-bit address). |
| 0x3D | CALL_INDIRECT | `u8 nargs` | `[fn, args...] -> [ret]` | Indirect call through function value/closure. |
| 0x44 | CALL_INDIRECT_SPREAD | `u8 fixed` | `[fn, fixed_args..., spread_list] -> [ret]` | Indirect call with a spread list appended to fixed args. |
| 0x3E | MAKE_CLOSURE | `u8 ncap` | `[cap0..cap(n-1), fn] -> [fn]` | Create closure by capturing `ncap` values into `fn.env` (a list). |
| 0x3F | LOAD_ENV | `u8 idx` | `[] -> [val]` | Push captured value `env[idx]`. |
| 0x40 | NEW_LIST | `u16_le len` | `[v0..v(n-1)] -> [list]` | Pop `len` values and build a list preserving push order. |
| 0x56 | NEW_LIST_SPREAD | `u16_le fixed` | `[fixed_values..., spread_list] -> [list]` | Build list from fixed stack values plus a spread list. |
| 0x41 | NEW_MAP | `u16_le pairs` | `[k0,v0..k(p-1),v(p-1)] -> [map]` | Pop `pairs` key/value pairs and build a map (sorted key storage). |
| 0x55 | TYPE_CTOR_MAP_SPREAD | `u16_le fixed` | `[keys_list, fixed_args..., spread_list] -> [map]` | Construct a map for typed-ctor calls using `keys_list` + fixed args + spread args (arity must match). |
| 0x42 | GET_INDEX | - | `[obj, key] -> [val]` | Index list/map; returns `nil` for missing/out-of-range. |
| 0x43 | SET_INDEX | - | `[obj, key, val] -> []` | Mutate list/map; list also supports append when `key == len`. |
| 0x45 | SPAWN_CALL_LIST | - | `[fn, args_list] -> [handle_int]` | Spawn a task calling `fn(args_list...)` (handle is `tid+1`). |
| 0x54 | SPAWN_CALL_SPREAD | `u16_le fixed` | `[fn, fixed_args..., spread_list] -> [handle_int]` | Spawn a task calling `fn(fixed..., spread...)`. |
| 0x46 | JOIN | - | `[handle_int] -> [ret]` | Join task by handle; blocks until complete. |
| 0x4C | JOIN_TIMEOUT | - | `[handle_int, timeout_ms] -> [ret_or_errno]` | Join with timeout; returns `-60` on timeout (BSD `ETIMEDOUT`, rolling). |
| 0x47 | CHAN_NEW | - | `[] -> [chan_int]` | Create a new channel. |
| 0x48 | CHAN_SEND | - | `[chan_int, val] -> [1]` | Send a value to a channel (may wake select waiters). |
| 0x49 | CHAN_RECV | - | `[chan_int] -> [val]` | Receive from a channel; blocks if empty. |
| 0x4A | SELECT_RECV | - | `[channels_list] -> [pair_list]` | Select-first-ready receive: returns `[idx, msg]` for a list of channels; blocks otherwise. |
| 0x4D | SELECT | - | `[cases_list] -> [pair_list]` | General select over recv/send cases (returns `[idx, msg_or_1]`); blocks otherwise. |
| 0x4B | YIELD | - | - | Yield to scheduler if another task is runnable. |
| 0x52 | LOAD_LOCAL16 | `u16_le idx` | `[] -> [val]` | Push local value at `fp+idx` (16-bit index). |
| 0x53 | STORE_LOCAL16 | `u16_le idx` | `[val] -> []` | Pop value and store to `fp+idx` (16-bit index). |

## Native Intrinsics (Legacy `CALL_NATIVE` ID map)

Source of truth (rolling): `lib/avm/avm_native.inc` `avm_call_native(...)`.

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
12. oren_list_len(list) -> int
13. oren_list_push(list, value) -> nil
14. oren_index_set(container, index, value) -> nil
15. int_mod
16. oren_bytes_from_string
17. oren_write_bytes
18. oren_read_bytes
19. oren_err(code, msg)
20. oren_is_err(v)
21. oren_err_code(v)
22. oren_err_msg(v)
23. oren_set_result(v)
24. oren_get_result()
25. (reserved)
26. (reserved)
27. (reserved)
28. (reserved)
29. (reserved)
30. oren_bytes_pack(list<int 0..255>) -> bytes
31. oren_bytes_unpack(bytes) -> list<int>
32. oren_bytes_len(bytes) -> int
33. oren_bytes_get_u8(bytes, idx) -> int
34. oren_bytes_set_u8(bytes, idx, val) -> bytes
35. oren_bytes_from_hex(string) -> bytes
36. oren_bytes_to_hex(bytes) -> string
37. (reserved)
38. (reserved)
39. (reserved)
40. oren_avm_record_to_bytes() -> nil
41. oren_avm_get_record_bytes() -> bytes|nil
42. oren_avm_set_replay_bytes(bytes) -> nil
43. oren_iter_next(container, idx:int) -> [ok:int, value]
44. oren_string_from_bytes(list<int 0..255>) -> string
45. oren_bytes_set_u16_be(bytes|list<int>, idx, val) -> int (0..65535)
46. oren_bytes_set_u16_le(bytes|list<int>, idx, val) -> int (0..65535)
47. oren_bytes_set_i16_be(bytes|list<int>, idx, val) -> int (-32768..32767)
48. oren_bytes_set_i16_le(bytes|list<int>, idx, val) -> int (-32768..32767)
49. oren_bytes_set_u32_be(bytes|list<int>, idx, val) -> int (0..2^32-1)
50. oren_bytes_set_u32_le(bytes|list<int>, idx, val) -> int (0..2^32-1)
51. oren_bytes_set_i32_be(bytes|list<int>, idx, val) -> int (-2^31..2^31-1)
52. oren_bytes_set_i32_le(bytes|list<int>, idx, val) -> int (-2^31..2^31-1)
53. oren_realpath(path:string) -> string (pure lexical normalization)
54. oren_i32_buf_new(len:int) -> I32_BUF
55. oren_i64_buf_new(len:int) -> I64_BUF
56. oren_f32_buf_new(len:int) -> F32_BUF
57. oren_f64_buf_new(len:int) -> F64_BUF
58. oren_buf_len(buf) -> int
59. oren_buf_load_i32(i32_buf, idx) -> int
60. oren_buf_store_i32(i32_buf, idx, val) -> i32_buf
61. oren_buf_load_i64(i64_buf, idx) -> int
62. oren_buf_store_i64(i64_buf, idx, val) -> i64_buf
63. oren_buf_load_f32(f32_buf, idx) -> float
64. oren_buf_store_f32(f32_buf, idx, val) -> f32_buf
65. oren_buf_load_f64(f64_buf, idx) -> float
66. oren_buf_store_f64(f64_buf, idx, val) -> f64_buf
67. oren_buf_fill_i32(i32_buf, val:int) -> i32_buf
68. oren_buf_fill_i64(i64_buf, val:int) -> i64_buf
69. oren_buf_fill_f32(f32_buf, val:float) -> f32_buf
70. oren_buf_fill_f64(f64_buf, val:float) -> f64_buf
71. oren_buf_add_i32(a:i32_buf, b:i32_buf) -> i32_buf
72. oren_buf_add_f32(a:f32_buf, b:f32_buf) -> f32_buf
73. oren_buf_dot_i32(a:i32_buf, b:i32_buf) -> int
74. oren_buf_dot_f32(a:f32_buf, b:f32_buf) -> float
75. oren_buf_add_i32_into(dst:i32_buf, a:i32_buf, b:i32_buf) -> i32_buf
76. oren_buf_add_f32_into(dst:f32_buf, a:f32_buf, b:f32_buf) -> f32_buf
77. oren_buf_scale_f32(buf:f32_buf, scalar:float) -> f32_buf
78. oren_buf_reduce_sum_f32(buf:f32_buf) -> float
79. oren_buf_mul_f32_into(dst:f32_buf, a:f32_buf, b:f32_buf) -> f32_buf
80. oren_buf_mul_f32(a:f32_buf, b:f32_buf) -> f32_buf
81. oren_buf_mul_i32_into(dst:i32_buf, a:i32_buf, b:i32_buf) -> i32_buf
82. oren_buf_mul_i32(a:i32_buf, b:i32_buf) -> i32_buf
83. oren_buf_reduce_sum_i32(buf:i32_buf) -> int
84. oren_buf_scale_f32_into(dst:f32_buf, a:f32_buf, scalar:float) -> f32_buf
85. oren_buf_scale_i32_into(dst:i32_buf, a:i32_buf, scalar:int) -> i32_buf
86. oren_buf_dot_f32_into(out:f64_buf, a:f32_buf, b:f32_buf) -> f64_buf
87. oren_buf_reduce_sum_f32_into(out:f64_buf, a:f32_buf) -> f64_buf
88. oren_buf_dot_i32_into(out:i64_buf, a:i32_buf, b:i32_buf) -> i64_buf
89. oren_buf_reduce_sum_i32_into(out:i64_buf, a:i32_buf) -> i64_buf
90. oren_bytes_get_u16_be(bytes|list<int>, idx) -> int (0..65535)
91. oren_bytes_get_u16_le(bytes|list<int>, idx) -> int (0..65535)
92. oren_bytes_get_i16_be(bytes|list<int>, idx) -> int (-32768..32767)
93. oren_bytes_get_i16_le(bytes|list<int>, idx) -> int (-32768..32767)
94. oren_bytes_get_u32_be(bytes|list<int>, idx) -> int (0..2^32-1)
95. oren_bytes_get_u32_le(bytes|list<int>, idx) -> int (0..2^32-1)
96. oren_bytes_get_i32_be(bytes|list<int>, idx) -> int (-2^31..2^31-1)
97. oren_bytes_get_i32_le(bytes|list<int>, idx) -> int (-2^31..2^31-1)
98. oren_bytes_get_u64_be(bytes|list<int>, idx) -> int (signed int64 bits)
99. oren_bytes_get_u64_le(bytes|list<int>, idx) -> int (signed int64 bits)
100. oren_bytes_get_i64_be(bytes|list<int>, idx) -> int (signed int64)
101. oren_bytes_get_i64_le(bytes|list<int>, idx) -> int (signed int64)
102. oren_bytes_set_u64_be(bytes|list<int>, idx, val) -> int (signed int64 bits)
103. oren_bytes_set_u64_le(bytes|list<int>, idx, val) -> int (signed int64 bits)
104. oren_bytes_set_i64_be(bytes|list<int>, idx, val) -> int (signed int64)
105. oren_bytes_set_i64_le(bytes|list<int>, idx, val) -> int (signed int64)
106. oren_f32_round(x: float) -> float
107. oren_bool_norm(x) -> bool
108. oren_trunc_int(x: int|float) -> int
109. oren_f32_to_u32_bits(x: float) -> int
110. oren_u32_bits_to_f32(x: int) -> float
111. oren_f64_to_u64_bits(x: float) -> int
112. oren_u64_bits_to_f64(x: int) -> float
113. oren_map_len(map) -> int
114. oren_buf_dot_i32_slice(a:i32_buf, a_off:int, b:i32_buf, b_off:int, n:int) -> int
115. oren_buf_dot_f32_slice(a:f32_buf, a_off:int, b:f32_buf, b_off:int, n:int) -> float
116. oren_buf_dot_i32_strided(a:i32_buf, a_off:int, a_stride:int, b:i32_buf, b_off:int, b_stride:int, n:int) -> int
117. oren_buf_dot_f32_strided(a:f32_buf, a_off:int, a_stride:int, b:f32_buf, b_off:int, b_stride:int, n:int) -> float
118. oren_char(code:int) -> string(1)
119. oren_string_to_float_bits(s:string) -> int (u64 bits stored in i64 container)
120. oren_sha256_range(bytes:list<int>, start:int, len:int) -> list<int 32>
121. oren_fail(code:int, msg:string) -> abort VM run
122. oren_buf_dot_i32_4_slice_into(out:i64_buf, out_off:int, a:i32_buf, a_off:int, b:i32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> i64_buf
123. oren_buf_axpy_i32_into(dst:i32_buf, alpha:int, x:i32_buf, y:i32_buf) -> i32_buf
124. oren_buf_axpy_i32_in_place(alpha:int, x:i32_buf, y:i32_buf) -> i32_buf
125. oren_buf_axpy_f32_into(dst:f32_buf, alpha:float, x:f32_buf, y:f32_buf) -> f32_buf
126. oren_buf_axpy_f32_in_place(alpha:float, x:f32_buf, y:f32_buf) -> f32_buf
127. oren_buf_dot_f32_4_slice_into(out:f64_buf, out_off:int, a:f32_buf, a_off:int, b:f32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
128. oren_buf_gemm_f32_4x4_slice_into(out:f64_buf, out_off:int, a:f32_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:f32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
129. oren_buf_gemm_i32_4x4_slice_into(out:i64_buf, out_off:int, a:i32_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:i32_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> i64_buf
130. oren_buf_dot_f64_4_slice_into(out:f64_buf, out_off:int, a:f64_buf, a_off:int, b:f64_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
131. oren_buf_gemm_f64_4x4_slice_into(out:f64_buf, out_off:int, a:f64_buf, a0_off:int, a1_off:int, a2_off:int, a3_off:int, b:f64_buf, b0_off:int, b1_off:int, b2_off:int, b3_off:int, n:int) -> f64_buf
132. oren_buf_dot_f64(a:f64_buf, b:f64_buf) -> float
133. oren_buf_dot_f64_slice(a:f64_buf, a_off:int, b:f64_buf, b_off:int, n:int) -> float
134. oren_buf_dot_f64_strided(a:f64_buf, a_off:int, a_stride:int, b:f64_buf, b_off:int, b_stride:int, n:int) -> float
135. oren_buf_reduce_sum_f64(a:f64_buf) -> float
136. oren_buf_dot_f64_into(out:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
137. oren_buf_reduce_sum_f64_into(out:f64_buf, a:f64_buf) -> f64_buf
138. oren_buf_add_f64(a:f64_buf, b:f64_buf) -> f64_buf
139. oren_buf_add_f64_into(dst:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
140. oren_buf_mul_f64_into(dst:f64_buf, a:f64_buf, b:f64_buf) -> f64_buf
141. oren_buf_mul_f64(a:f64_buf, b:f64_buf) -> f64_buf

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
  - applies conservative default budgets unless overridden by env (`AVM_GAS`, `AVM_TIMEOUT_MS`, `AVM_MEM_BYTES`, `AVM_IO_BYTES`, `AVM_LOG_BYTES`, `AVM_CALL_DEPTH_MAX`)
  - to allow a small approved set without env vars, use:
    - `--allow-domains "0,1,6"` (or `AVM_ALLOW_DOMAINS=...`) to explicitly allow domains
    - `--fs-allow-prefixes "build/"` (or `AVM_FS_ALLOW_PREFIXES=...`) to restrict FS paths
- **Metering is rolling (implemented, not yet stability-promised):**
  - instruction “gas” (`AVM_GAS`)
  - wall-time deadline (`AVM_TIMEOUT_MS`)
  - heap memory budget for VM heap objects (`AVM_MEM_BYTES`)
  - FS I/O byte budget (`AVM_IO_BYTES`)
  - record/replay log growth budget (`AVM_LOG_BYTES`)
  - call depth limit (`AVM_CALL_DEPTH_MAX` or `--call-depth-max`)
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
