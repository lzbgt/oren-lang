# AVM + OBC Design (Rolling)

This document consolidates the AVM specification, OBC format/linking, signature model, and AVM design notes into a single source of truth while the repo is in rolling mode. The content below is merged from the prior standalone docs to reduce drift and keep links stable.

Merged sources (legacy paths; removed after merge):
- docs/AVM_SPEC.md
- docs/OBC.md
- docs/APPSTORE_ROOTCA_AND_UPDATES.md
- docs/AVM_DESIGN.md

## Contents
- Agent Virtual Machine (AVM) Specification
- OBC (Oren Bytecode) — Portability + Module Linking (Rolling)
- AVM App-Store Model: Root CA, Signed OBC, and Multiverse Updates (Rolling)
- AVM Design (Rolling)


## Agent Virtual Machine (AVM) Specification

**Note:** This document describes the **v0.1 bootstrap** AVM (minimal instruction set).
For the next step (no-JIT-first, ML-focused typed buffers/SIMD, capability-scoped natives), see:

- the **Next-Gen AVM Plan (V1, Draft)** section in this document
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
- **List<int> fast-path (rolling):** `LIST_INT` is an unboxed int64 list optimized for tight loops; created via `NEW_LIST_INT` and interoperates with list ops that accept int-only lists.

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
  - see `docs/AVM_AND_OBC.md`
- Rolling convention: `.obc` may include an **unused** `BYTES` constant containing an “OREN_SIG” signature payload:
  - payload prefix: ASCII `"OREN_SIG\n1\n"`
  - payload contains an ed25519 signature over a canonical `.obc` hash (excluding OREN_SIG constants)
  - AVM can optionally require this signature before executing bytecode
  - see `docs/AVM_AND_OBC.md`
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
| 0x57 | GET_INDEX_LIST | - | `[list, idx] -> [val]` | List-only index; returns `nil` for out-of-range or non-int index. |
| 0x58 | LIST_DOT | - | `[list_a, list_b, idx, n, sum] -> [idx, sum]` | Fused dot-product loop (int fast-path with fallback). |
| 0x59 | LIST_PUSH_INT | - | `[list, int] -> [nil_or_err]` | Push int into list; errors if list/value invalid. |
| 0x5A | LIST_PUSH | - | `[list, val] -> [nil_or_err]` | Push value into list; errors if list invalid. |
| 0x5B | LIST_PUSH_INT_LOOP | - | `[list, idx, end, mul, add, mod] -> [idx]` | Fused int push loop: `list.push((i*mul+add)%mod)` from idx..end. |
| 0x5C | LIST_SUM_INT_LOOP | - | `[list, idx, n, sum] -> [idx, sum]` | Fused int sum loop: `sum += list[i]` from idx..n. |
| 0x5D | LIST_SUM3_INT_LOOP | - | `[list_a, list_b, list_c, idx, n, sum] -> [idx, sum]` | Fused int sum loop: `sum += list_a[i] + list_b[i] + list_c[i]` from idx..n. |
| 0x5E | NEW_LIST_INT | - | `[cap] -> [list_int_or_err]` | Allocate an unboxed `list<int>` with initial capacity `cap` (int); returns error value on invalid cap. |
| 0x5F | LIST_PUSH2_INT_LOOP | - | `[list_a, list_b, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b] -> [idx]` | Fused int push loop for two lists: `list_a.push((i*mul_a+add_a)%mod_a)` and `list_b.push((i*mul_b+add_b)%mod_b)` from idx..end. |
| 0x60 | LIST_PUSH3_INT_LOOP | - | `[list_a, list_b, list_c, idx, end, mul_a, add_a, mod_a, mul_b, add_b, mod_b, mul_c, add_c, mod_c] -> [idx]` | Fused int push loop for three lists (per-list linear RHS) from idx..end. |
| 0x61 | INT_LCG_SUM_LOOP | - | `[x, sum, idx, end, mul, add, mod, mod_x, mod_i] -> [idx, sum, x]` | Fused int loop: `x=(x*mul+add)%mod; sum=(sum+(x%mod_x)+(idx%mod_i))%mod` from idx..end. |
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
17. oren_write_bytes (list<int 0..255> or u8_buf)
18. oren_read_bytes
19. oren_err(code, msg)
20. oren_is_err(v) -> bool
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

- **Capability model is still evolving:** host calls support both a flat numeric ID table (`CALL_NATIVE`) and a domain/op model (`CALL_NATIVE2`); next-gen direction is specified in the **Next-Gen AVM Plan (V1, Draft)** section below.
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

## Next-Gen AVM Plan (V1, Draft)

**Status:** Draft (guidance + work plan)  
**Last updated:** 2025-12-15  
**Scope:** AVM bytecode format (`.obc`) + interpreter contract + host capability model

This section defines the **next evolutionary step** beyond the bootstrap VM described above.

### 1) Design Goals (Non-Negotiables)

#### 1.1 No-JIT-first

- Default execution is **interpreter-only** (compatible with iOS/App Store “no JIT” constraints).
- Optional **server-side JIT/AOT** may exist later, but must execute the *same* `.obc` semantics.

#### 1.2 AI/ML-oriented primitives

- Efficient numeric compute is a first-class goal:
  - vector ops, reductions, dot products
  - typed buffers
  - predictable performance (avoid dynamic per-element overhead)

#### 1.3 Self-healable execution model

- AVM must support robust failure boundaries:
  - deterministic error reporting
  - resumability via snapshotting (planned)
  - strict capability boundaries for host effects
- AVM must be “repair-friendly”: agents can replay failures, patch code, and rerun deterministically.

#### 1.4 SOLID-governed “stdlib” boundaries

- Host functionality must be split into small, composable modules (interfaces), avoiding a monolithic “god module”.
- VM core stays minimal; “services” live behind capability-scoped native calls.

### 2) Versioning & Compatibility

#### 2.1 Rolling ABI (current repo mode)

This repo is currently in **rolling ABI** mode:

- `.obc` is not version-gated today.
- Bytecode format and opcode set may change as the compiler and AVM evolve together.

When AVM reaches a “stability-promised” milestone, we can introduce explicit `.obc` versioning (major/minor + feature flags). Until then, treat the format as unstable.

#### 2.2 Deterministic semantics first

All ops must define:

- integer overflow behavior (wrap vs trap) — pick one and freeze it
- float behavior (IEEE-754 as platform provides) with documented corner cases
- string encoding assumptions (byte strings vs UTF-8 semantics)

Additionally required for agent-grade determinism:

- define truthiness rules precisely (what values are falsey)
- define map iteration order requirements (or explicitly declare maps unordered)
- define scheduler determinism policy for tasks (when coroutines land)

**Rolling decisions (repo-enforced):**

- **Integer overflow behavior:** `int` arithmetic in the VM is **i64 two’s-complement wraparound** for `ADD/SUB/MUL/SHL/SHR` (mod 2^64 on bit patterns).
  - Rationale: C signed overflow is UB; wrap semantics keep consensus deterministic across compilers/flags.
  - Note: `SHR` is a **logical** right shift (operates on bit patterns), not an arithmetic sign-extending shift.
- **Division errors:** `int / int` aborts deterministically on:
  - division by zero
  - `i64_min / -1` overflow

### 3) Value Model (Next-Gen)

The v0 model (`Nil/Int/Float/Bool/String/List/Map`) is not sufficient for ML-ish workloads.

#### 3.1 Add `BYTES` (packed byte buffer)

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

#### 3.2 Add typed numeric buffers (core for ML)

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

Bootstrap status (rolling, implemented in `lib/avm`):

- New value types: `AVM_VAL_I32_BUF/AVM_VAL_I64_BUF/AVM_VAL_F32_BUF/AVM_VAL_F64_BUF`.
- Minimal bootstrap intrinsics (CORE domain legacy ids):
  - `oren_i32_buf_new(n)`, `oren_i64_buf_new(n)`, `oren_f32_buf_new(n)`, `oren_f64_buf_new(n)`
  - `oren_buf_len(buf)`
  - `oren_buf_load_i32/oren_buf_store_i32`, `..._i64`, `..._f32`, `..._f64`
- Minimal bootstrap “kernel ops” (CORE domain legacy ids; scalar fallback; deterministic encoding):
  - fills: `oren_buf_fill_{i32,i64,f32,f64}(buf, scalar)`
  - elementwise: `oren_buf_add_{i32,f32}(a, b) -> new_buf`
  - dot (convenience scalar return): `oren_buf_dot_{i32,f32}(a, b) -> scalar`
  - dot (allocation-free pipeline): `oren_buf_dot_i32_into(out:i64_buf, a:i32_buf, b:i32_buf) -> out`, `oren_buf_dot_f32_into(out:f64_buf, a:f32_buf, b:f32_buf) -> out` (stores result at `out[0]`)
  - in-place: `oren_buf_add_{i32,f32}_into(dst, a, b) -> dst`
  - scale/reduce (convenience scalar return): `oren_buf_scale_f32(buf, scalar)`, `oren_buf_reduce_sum_f32(buf) -> scalar`
  - reduce (allocation-free pipeline): `oren_buf_reduce_sum_f32_into(out:f64_buf, a:f32_buf) -> out`, `oren_buf_reduce_sum_i32_into(out:i64_buf, a:i32_buf) -> out` (stores result at `out[0]`)
  - mul: `oren_buf_mul_f32_into(dst, a, b) -> dst`, `oren_buf_mul_f32(a, b) -> new_buf`
  - integer mul/reduce: `oren_buf_mul_i32_into(dst, a, b) -> dst`, `oren_buf_mul_i32(a, b) -> new_buf`, `oren_buf_reduce_sum_i32(buf) -> int`
  - scale into: `oren_buf_scale_f32_into(dst, a, scalar) -> dst`, `oren_buf_scale_i32_into(dst, a, scalar) -> dst`
- Determinism rule: buffer payload is a byte array whose element encoding is **canonical little-endian**:
  - `i32/i64` are two's-complement integers encoded little-endian
  - `f32/f64` are IEEE-754 bit patterns encoded little-endian
  - This makes snapshot/resume, record/replay, and hashing independent of host endianness.

SIMD note (rolling, arm64):

- SIMD kernel implementations are an **optimization** only, and must never change semantics.
- Runtime opt-in: `AVM_ENABLE_SIMD=1` (default off; scalar fallback remains authoritative).

#### 3.3 Keep `List/Map` for dynamic control/data

Lists/maps remain for:

- scripting
- JSON-like objects
- compiler metadata
- orchestration logic

Compute kernels should use typed buffers, not lists.

### 4) Cooperative Concurrency (Rolling, Deterministic)

This repo currently implements a **minimal cooperative concurrency** substrate inside the C AVM interpreter:

- single-threaded, deterministic (no host syscalls)
- tasks are VM-internal (green-thread style), sharing the VM heap and globals
- blocking ops yield to other runnable tasks

This is a stepping stone toward v1 “agentic execution”: nested universes, deterministic replay, and consensus-friendly scheduling.

#### 4.1 Tasks

Core operations (rolling; not yet stabilized as a permanent `.obc` ABI):

- `spawn f(args...) -> handle:int`
  - spawns a new VM task running `f`
  - returns an integer handle (`tid+1`, so `0` remains a reserved invalid/nil-ish sentinel)
- `oren_join(handle) -> value`
  - blocks until the task completes and returns its return value
- `oren_join_timeout(handle, timeout_ms) -> value_or_errno`
  - deterministic timeout based on AVM TIME (virtual time in deterministic mode)
  - returns `-60` (BSD `ETIMEDOUT`) on timeout
  - `timeout_ms < 0` behaves like `oren_join` (blocks)
  - `timeout_ms == 0` is a non-blocking probe (returns `ETIMEDOUT` if not done)
  - Note: this `timeout_ms < 0` rule is specific to AVM task join; native NET wait helpers intentionally treat `timeout_ms < 0` as **no wait** (0ms) in rolling mode to avoid accidental hangs.
- `oren_yield()`
  - yields to another runnable task (no-op if none)

Deterministic scheduling rule (rolling):

- Tasks are time-sliced cooperatively by a **task quantum** (semantic steps / gas units).
- If another task is runnable, the current task yields when its quantum is exhausted.
- Quantum is a deterministic VM config value (`AVM_TASK_QUANTUM*`) and is part of the execution-context hash for swarm jobs.

#### 4.2 Channels

Minimal in-VM channels exist to support structured concurrency without host effects:

- `oren_new_channel() -> ch:int`
- `oren_chan_send(ch, val) -> ok:int`
- `oren_chan_recv(ch) -> val` (blocks if empty)

#### 4.3 Select

Two select APIs exist in rolling mode:

1) `oren_select_recv([ch1, ch2, ...]) -> [idx, val]`
   - recv-only select; blocks until any channel has a queued value

2) `oren_select(cases) -> [idx, payload]`
   - general select supporting both recv and send cases
   - `cases` is a list of *case descriptors* (data), encoded as:
     - recv case: `[0, ch]`
     - send case: `[1, ch, val]`
   - return value:
     - `idx` is the selected case index
     - `payload` is:
       - the received value for recv cases
       - `1` for send cases (rolling “ok” marker)

Determinism + fairness rule (rolling):

- Selection scans cases starting at a per-task **round-robin cursor** and updates the cursor to `(idx+1)%n` after a successful selection.
- This is deterministic and avoids “always pick case 0” starvation when multiple cases are ready.

### 5) Instruction Set Direction (Next-Gen)

#### 5.1 Keep the interpreter lean (no “feature explosion”)

Core VM opcodes remain small and stable:

- control flow
- locals/globals
- calls/returns
- minimal value construction

Performance comes from:

- typed buffer operations
- vector ops implemented as single opcodes (SIMD in host / optimized interpreter loops)

#### 5.2 Split numeric ops into typed variants

The v0 design has `ADD/SUB` etc. without explicit typing. For ML, we need typed ops to avoid per-op type checks.

Introduce:

- `IADD`, `ISUB`, `IMUL` (and maybe `IDIV`)
- `FADD`, `FSUB`, `FMUL` (and maybe `FDIV`)

Also:

- `I2F`, `F2I` conversions

#### 5.3 SIMD / vector kernel ops (ML-ish set)

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

Implementation notes (arm64 NEON, no-JIT-first):

- See `docs/AVM_AND_OBC.md#avm-neon-mapping-plan-arm64-no-jit-first` for the concrete mapping plan and determinism constraints.

#### 5.4 Float determinism policy (consensus safety)

Consensus requires float behavior to be **repeatable** across:

- macOS + Linux
- clang + gcc
- arm64 + x86_64 (later)

Rolling policy (enforced in the repo today):

- **No fast-math**: AVM is compiled without `-ffast-math`.
- **No FP contraction / no FMA drift**: AVM is compiled with FP contraction disabled (build flags + TU pragmas).
- **Fixed evaluation order for reductions**: buffer reductions (`dot`, `reduce_sum`) use fixed loop order and accumulate in `double`.
- **Canonical byte encoding**: typed buffer payload bytes are little-endian canonical encodings (already required for snapshot/hash).

This policy is intentionally conservative. If we later introduce a JIT, it must preserve these semantics (or explicitly switch the VM out of consensus mode).

### 6) Host Interface: Capability-Scoped Native Calls

#### 6.1 Replace “flat CALL_NATIVE” with capability domains

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

#### 6.2 Capability tokens

Host effects must be governed by explicit capability tokens:

- VM receives a capability set at startup
- each native call checks required capability
- denied calls return an error value (no undefined behavior)

This is a prerequisite for “self-healable” agents: failures are controlled, inspectable, and recoverable.

#### 6.3 Resource metering (required for production safety)

AVM must support enforceable budgets:

- instruction count (“gas”) budget
- wall-time budget (with periodic preemption points)
- memory budget (heap + typed buffers)
- I/O budget (bytes read/written; network calls)
- record/replay log growth budget (bytes appended to deterministic logs)

Metering is required for:

- running multiple agents safely
- preventing runaway scripts in constrained devices

#### 6.4 Execution context (timeouts + cancellation)

The VM must run with an explicit execution context:

- `deadline_ns` (optional)
- `cancelled` flag / token (optional)
- budgets (gas/memory/io)

All effectful native calls (FS/NET/PROC/TIME/RNG) must either:

- accept an explicit timeout parameter, or
- consult the VM execution context for deadline/cancellation.

#### 6.5 Capability domains (rolling assignments) + SOLID governance

The capability surface is split into **domains** to avoid a monolithic “god” native table and to enable least-privilege enforcement.

Current rolling assignments (subject to change):

- `0`: CORE (pure utilities, no external side effects; always allowed)
- `1`: FS (filesystem)
- `2`: TIME
- `3`: RNG / CRYPTO
- `4`: NET
- `5`: PROC (subprocess / shell)
- `6`: EXIT (terminate the VM)
- `7`: ENV
- `9`: SIMD (side-effect free vector kernels) (planned)

Bootstrap status (rolling, implementation reality):

- `oren_system(cmd)` is treated as a **PROC** operation (domain `5`, op `0`) in the bytecode backend.
- `oren_exit(code)` is treated as an **EXIT** operation (domain `6`, op `0`) in the bytecode backend.
- `oren_env(name)` is treated as an **ENV** operation (domain `7`, op `0`) in the bytecode backend.
- Legacy flat native IDs still exist for bootstrap compatibility, but effectful calls should move behind capability domains (PROC/FS/…).

Governance rules (SOLID-like):

- each domain has a single responsibility
- cross-domain dependencies are forbidden unless explicitly layered
- keep domain surfaces minimal; prefer composable primitives over “do everything” calls

##### 6.5.1 Call encoding (bytecode ABI)

Rolling ABI encoding (implemented today):

- opcode: `CALL_NATIVE2`
- operands: `u8 domain`, `u16 op`, `u8 nargs`

##### 6.5.2 Error contract (self-healing requirement)

Native calls must not hard-crash the VM for expected failures (permission denied, file not found, timeout).

Pick one representation and standardize it when a stability milestone is declared:

- dedicated `ERR` value type (preferred), or
- `nil` + error code, or
- a tagged map like `{ "ok": false, "code": ..., "msg": ... }`

##### 6.5.3 Virtualization (“Matrix sandbox”) + record/replay

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
    - `now_ns = AVM_TIME_START_NS + sleep_accum_ns + gas_executed * AVM_TIME_STEP_NS` (where `gas_executed` is the sum of semantic `gas_cost(op)`)
    - `oren_sleep_ms(ms)` increases `sleep_accum_ns` by `ms * 1e6`
  - `AVM_RNG_SEED` seeds the deterministic PRNG
- This is intentionally minimal and is meant to evolve into full multi-domain virtualization (FS/NET/PROC/TIME/RNG) plus replay-log hashing.

### 7) Self-Healing Features (Planned)

#### 7.1 Snapshot / restore (VM state)

Define a serialization format for:

- VM stack
- locals/globals
- heap objects (strings/bytes/buffers/lists/maps)
- program counter and call frames

Bootstrap status (rolling):

- `avm` supports a minimal snapshot/restore for `Nil/Int/Float/Bool/String/List/Map` to enable “pause and resume” workflows and future agent mobility.
- Snapshot files are intentionally marked rolling/unstable until a stability milestone is declared.

#### 7.2 Deterministic execution mode

Add an optional “deterministic mode” to:

- control randomness (seeded RNG capability)
- control time access (virtual clock)
- control host side effects (record/replay)

This enables:

- reproducible agent behavior
- easier debugging and healing after failure

#### 7.3 Bytecode verification + policy scanning (before execute)

Before execution, AVM should run a verifier pass:

- stack discipline validation (no underflow/overflow)
- constant pool bounds validation
- jump target validation
- native call operand decoding validation

Separately, a policy scanner should be able to answer:

- which capability domains are used by this program
- whether any forbidden domain/op appears

This is essential for safely executing LLM-generated or untrusted scripts.

### 8) Work Plan (Incremental, Test-Driven)

#### Phase 1: Binary-safe IO baseline (DONE)

- `oren_read_bytes` implemented in C runtime and AVM host.

#### Phase 2: Introduce `BYTES` value type

- Extend AVM C runtime:
  - `AVM_VAL_BYTES`
  - bytes construction + indexing
- Extend bytecode format:
  - bytes constant pool entry OR bytecode instruction to create bytes from const
- Add tests:
  - load `.obc`, verify bytes operations correctness

#### Phase 3: Typed buffers + vector ops

- Add buffer types (`F32_BUF` first)
- Add `SIMD` domain ops (or opcodes) for vector math
- Add scalar fallback semantics and NEON-optimized implementation (macOS/Linux arm64)

#### Phase 4: Capability domains split

- Replace v0 flat mapping with `(domain, op)` while keeping a compatibility mode for v0 programs (optional).

#### Phase 5: Snapshotting (self-healable)

- Implement snapshot/restore for core types and execution state.

#### Phase 6: Verifier + policy scanner

- Implement bytecode verification and “capability usage” scanning.
- Add tests:
  - invalid stack programs rejected
  - forbidden domain rejected under restricted capability set

### 9) Related Docs

- Agentic requirements (language + compiler + AVM): `docs/AGENTIC_REQUIREMENTS.md`
- System evolution context: `docs/EVOLUTION_AND_ROADMAP.md`
- Roadmap: `docs/EVOLUTION_AND_ROADMAP.md`

## OBC (Oren Bytecode) — Portability + Module Linking (Rolling)

Oren `.obc` bytecode is designed as an **AVM universal artifact**:

- `.obc` should have **no platform meaning** (no “macOS vs Linux”, no “arm64 vs x64” semantics).
- AVM itself is a native program that depends on the host OS/arch for syscalls and memory mapping.
- The **contract** is: the same `.obc` executes with the same observable results across AVM builds.

This document consolidates the rolling rules for portability gates and for module linking (OBX metadata).

## 1) Portability contract and gate (implemented)

### What is compared

`./avm` supports printing deterministic hashes:

- `RESULT_HASH` — hash of program-visible outputs (logical results)
- `TRACE_HASH` — hash of trace/events (execution trace surface)

Portability means **both hashes match** across platforms.

### Current portability gate

Use the script:

- `tools/verify_obc_portability.sh`

Or via Make:

- `make obc-portability`

It verifies the same `.obc` (`tests/avm/test_smoke_suite.oren`) runs identically on:

- macOS arm64 (host)
- linux/arm64 (persistent docker container)
- linux/x86_64 (WSL2 when available on remote Win11 host)

Outputs are stored under:

- `build/tmp/obc_portability/`

### Requirements

1) Local host

- `./oren` and `./avm` built (normal `make test` already builds them).

2) Linux docker container (arm64)

This repo uses an **already-running** persistent Ubuntu toolchain container (it must exist and be
running; the scripts do **not** create a container for you).

- container id/name default: `c7e5f7bd9f5c` (override via `OREN_LINUX_DOCKER_ID=...`)

The portability gate syncs **tracked** sources into `/work/repo`, rebuilds AVM inside the
container, then executes the host-built `.obc`.

3) Remote x64 host (Win11, WSL2 optional)

The script uses the existing ssh proxy workflow (see `docs/REMOTE_X64_ENV.md`) and runs AVM inside
WSL2 (Linux x86_64) when available. If WSL2 is unavailable, skip the remote Linux leg and keep the
Windows leg for native gates.

Environment variables (defaults match the repo’s existing conventions):

- `OREN_REMOTE_X64_HOST` (default: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY` (default: `ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002`)
- `OREN_REMOTE_X64_UNIX_ROOT` (default: `/Users/lzbgt/tmp_oren`)

## 2) Module linking: OBX metadata inside `.obc`

This repo currently treats `.obc` as a **single self-contained program** (AVM bytecode).
For production-grade distribution (especially “compiler-in-AVM”), we also need a way to ship
**precompiled bytecode libraries** (e.g. stdlib) and link them into a final program `.obc`.

The rolling v0 approach is:

- `.obc` execution semantics stay unchanged (AVM ignores module metadata).
- The compiler optionally appends an **unused** `BYTES` constant containing an “OBX payload”.
- Tooling/linker reads OBX metadata to rebase code + resolve symbols.

### Goals

- Allow Oren/AVM to compile user source **without shipping stdlib sources**.
- Keep `.obc` execution semantics unchanged (AVM ignores module metadata).
- Keep the format simple enough to implement in Oren itself (compiler-in-AVM).

### Non-goals (v0)

- Runtime dynamic module loading (`import` at runtime).
- Stable ABI guarantees across releases (rolling mode).
- Exporting “globals as data symbols” (v0 focuses on function symbols).

### OBX payload format (binary)

The OBX payload is a byte blob stored inside a `BYTES` constant:

- prefix: ASCII `OREN_OBX\n1\n`
- `u16` `module_name_len`, followed by `module_name` UTF-8 bytes
- `u16` `export_count`
  - repeated `export_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `addr` (**0-based** byte offset into this module’s code section)
- `u16` `reloc_count`
  - repeated `reloc_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `pos` (**0-based** byte offset into this module’s code where a `u32` address must be patched)
    - `u8`  `kind`:
      - `0` = `CALL32` target relocation
      - `1` = `PUSH_FUNC32` target relocation

The linker rebases `addr` and `pos` as it concatenates modules.

### Stable symbol names for `std:` imports

To make separate compilation feasible, stdlib modules use a stable, deterministic prefix:

- `std:math` uses prefix `STD_math_`
- `std:net/http` uses prefix `STD_net_http_`

Then `fn sqrt(x)` inside `std:math` becomes an exported symbol:

- `STD_math_sqrt`

This stable naming is required so user code compiled in “extern stdlib” mode calls the same
symbol names that exist in the precompiled stdlib bundle.

### Compiler flags (rolling)

Build a library/bundle with exports:

```
./oren build lib/std/stdlib_avm.oren --backend bytecode -o build/stdlib_bundle.obc --obc-lib
```

This emits a normal runnable `.obc` plus an OBX payload containing exported function symbols.

Rolling helper scripts:

- Build stdlib bundle and (optionally) a compiler `.obc`: `scripts/build_avm_plugins.sh`
  - Override bundle root via env `OREN_STDLIB_BUNDLE_ROOT=...`
- Build+run a host `avm` smoke (proves OBX linking works end-to-end):
  `scripts/verify_avm_bytecode_link_smoke.sh`

Build an app linking against a precompiled stdlib:

```
./oren build app.oren --backend bytecode -o app.obc --stdlib-mode obc --stdlib-obc build/stdlib_bundle.obc
```

This mode:

- keeps unresolved calls as relocations (instead of hard compile errors)
- links the stdlib bundle `.obc` into the final output `.obc`
- patches relocations using OBX exports

### Implementation notes

- The linker patches:
  - `PUSH_CONST` indices (const pool concatenation)
  - `LOAD_GLOBAL` / `STORE_GLOBAL` indices (global index rebasing)
  - `CALL32` / `PUSH_FUNC32` absolute code addresses (code section rebasing)
  - OBX relocations (symbol resolution)
- Relative jump offsets (`JMP32`/`JMP_IF32`) remain valid under concatenation.
- To keep execution correct when concatenating multiple modules, the linker strips a trailing
  `HALT` opcode from each **non-final** module during concatenation. This prevents linked libraries
  from terminating the pc=0 “skip function bodies” chain before reaching the main program’s entry.

### Files

- Linker implementation: `lib/compiler/obc_link.oren`
- Stdlib bundle root (AVM-safe subset): `lib/std/stdlib_avm.oren`
- Stdlib bundle root (full, rolling, may include native-only helpers): `lib/std/stdlib.oren`
- Module prefixing + extern stdlib mode: `lib/compiler/compiler/020_modules_linking.oren`

## 3) Known gaps / next steps

1) **Native Windows AVM**
   - Today, AVM is a POSIX-style program (`unistd.h`, `sys/mman.h`, etc.).
   - Running `.obc` directly on Windows (without WSL2) requires a Windows AVM port (Win32 / NT syscalls).

2) **Compiler bytecode invariants**
   - The compiler currently forces a single bytecode ABI profile (`target=avm`, `arch=avm64`) to prevent
     host-specific lowering from leaking into `.obc`.
   - This should converge to “bytecode compilation ignores host target entirely” as the IR and lowering
     become fully portable.

## AVM App-Store Model: Root CA, Signed OBC, and Multiverse Updates (Rolling)

This document defines a **production-direction** security model for:

- distributing `.obc` “binary components” (stdlib bundle, compiler bundle, tools)
- allowing a parent AVM universe to **fetch updates** and “patch” child universes safely
- ensuring any node can verify the provenance of an artifact **offline** (no network trust)

This is intentionally “app store–like”: there is a *root trust anchor*, signed artifacts, and policy gating.

## Threat Model (What we defend against)

We assume:

- the network is hostile (MITM, replay, tampering)
- storage is hostile (cache poisoning, corrupted artifacts)
- child universes are untrusted and must not escalate privileges

We want:

- a parent node can retrieve/update components safely
- nested universes verify child `.obc` before execution (already required by the verifier)
- reproducibility + auditability via hashes (already part of AVM job model)

## Root of Trust

We maintain an offline **root signing key** (Root CA).

- The **root private key must never be committed** into this repo.
- The **root public key** is safe to embed into AVM builds (it is not secret).

Operational requirement:

- Root secrets live in a sibling directory **outside the repo**: `../oren-ca/`

Build-time embedding (rolling):

- AVM can embed a set of trusted root **public keys** in release builds (for “no flags needed” verification).
- The build reads root pubkeys from either:
  - `AVM_EMBED_ROOT_PUBKEY_HEX` (comma-separated 64-hex strings), or
  - `../oren-ca/avm_root_pubkeys.hex` (one 64-hex pubkey per line)
- Implementation detail: `make avm` generates `build/avm_root_pubkey.inc` via `tools/gen_avm_root_pubkeys_inc.sh`.

## Artifact Signature Model (Rolling v0)

We define a signature payload stored inside `.obc` as an unused `BYTES` constant:

- prefix: `OREN_SIG\n1\n`
- payload: algorithm id + key id + signature bytes

The signature covers a canonical hash of the `.obc` **excluding** signature/metadata constants:

- `OREN_SIG\n1\n` (signature payload)
- `OREN_CERTS\n1\n` (delegation chain payload)

Rationale:

- `.obc` can embed metadata constants (OREN_META, OREN_OBX). We must avoid circular signing.
- The AVM must be able to verify with only `.obc` bytes (self-contained distribution).

## Delegated Signing (Org / Developer Certificates)

Root-signing every artifact does not scale operationally. Rolling mode supports a minimal
delegation chain:

- root → organization (may issue)
- organization → developer (leaf signing key)

The `.obc` embeds the cert chain inside an unused BYTES constant:

- `OREN_CERTS\n1\n` (leaf-first chain)

Important detail: `OREN_CERTS` is treated as **verification metadata** and is excluded from the
canonical signature hash (along with `OREN_SIG`). This allows:

- updating/repacking cert chains without re-signing the `.obc` payload bytes
- keeping the leaf signature stable while rotating intermediate cert packaging

The AVM verifies:

1) chain signatures back to the trusted root pubkey
2) issuer `can_issue` enforcement for intermediate certs
3) `.obc` signature key id matches the leaf cert key id
4) `.obc` signature verifies under the leaf pubkey

Rolling extension (cert constraints):

- Certs may carry an issuer-defined capability ceiling (`allow_domains_mask` in `OREN_CERT\n2\n`).
- AVM enforces that the artifact’s bytecode only uses native domains within the delegated mask,
  independent of host/user allowlists.

Spec: `docs/CERT_CHAIN_FORMAT.md`.

## Verification Policy in AVM

Two independent “verify” layers exist:

1) **Bytecode verifier** (structural safety): prevents malformed programs from crashing/hanging the VM.
2) **Signature verifier** (provenance): prevents executing untrusted binaries.

Rolling policy:

- For **nested universes** (`avm.run_obc_bytes`), signature verification should be enabled by default once stable.
- For **host CLI** (`./avm file.obc`), signature verification is opt-in via flags/env until the ecosystem migrates.

## Update / Patch Model for Multiverse

We treat “patching a child universe” as:

- parent obtains a new signed `.obc` (full artifact or delta patch)
- parent verifies signature locally
- parent passes verified `.obc` bytes to child execution (`avm.run_obc_bytes`)
- child (or host service) re-verifies signature before running

Important: the parent must never be able to bypass child verification by “already verified on host”.
Verification must happen at the enforcement boundary.

## App Store Service (Future)

The “store” is just a distribution service for:

- signed artifacts (`.obc`)
- manifests (JSON): names, versions, hashes, dependencies, policy requirements

The security property is not “TLS” but “signatures”:

- even if transport is compromised, signatures prevent tampering.

Planned directions:

- a simple HTTP(S) endpoint for manifests + artifacts
- optional websocket for streaming updates
- compatibility with VirtualNET fixtures for deterministic simulation runs

## Running crypto inside AVM vs host crypto

Two viable designs exist in rolling mode:

1) **Host-side crypto (current implementation)**
   - AVM binary (C) verifies `OREN_SIG` using a vendored ed25519 verifier.
   - Pros: fast, small amount of bytecode changes.
   - Cons: trust is anchored in the AVM binary (still acceptable for many deployments).

2) **Bytecode crypto (planned)**
   - Implement SHA-256 / ed25519 verification in pure Oren (no FFI), compile to `.obc`, and link it.
   - Pros: the same verification logic can run inside nested universes (no libc/FFI dependency).
   - Cons: slower and more work; must be carefully tested for correctness/determinism.

Rolling recommendation:

- Keep host crypto as the enforcement boundary for `avm.run_obc_bytes`.
- Build bytecode crypto in parallel for portability/testing and to support more advanced “store logic as `.obc`” workflows.

Bootstrapping note:

- You can ship crypto code as `.obc` (pure Oren, no libc/FFI) and load it in AVM *after* the loader verifies its signature.
- You cannot eliminate a small trusted verifier in the AVM binary if you want signature enforcement at the boundary; otherwise you have a “who verifies the verifier?” loop.

## Key Handling

- Root private key: stored in `../oren-ca/` only (never in-repo).
- Root public key: embedded in AVM builds or passed explicitly for verification.
- Key rotation: supported by “key id” in the signature payload; AVM can accept a set of trusted pubkeys.

## Related Docs

- Multiverse requirements: `docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes`
- `.obc` portability + module linking (OBX): `docs/AVM_AND_OBC.md`
- `.obc` format and metadata conventions: `docs/AVM_AND_OBC.md`
- Delegated signing cert chains: `docs/CERT_CHAIN_FORMAT.md`

## AVM Design (Rolling)

This document consolidates the rolling AVM design notes into a single reference. It preserves the original content but organizes it into a coherent sequence so links and updates stay consistent.

## Contents
- [AVM Anti-Tamper / Anti-Hack at Startup (Rolling)](#avm-anti-tamper-anti-hack-at-startup-rolling)
- [AVM Concurrency Model (Deterministic, Syscall-First-Aligned, Multiverse-Friendly)](#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly)
- [AVM-in-AVM (“Multiverse”) Design: Nested Virtual Universes](#avm-in-avm-multiverse-design-nested-virtual-universes)
- [AVM Plugins + Nesting (OBC-First, iOS-Safe) (Rolling)](#avm-plugins-nesting-obc-first-ios-safe-rolling)
- [AVM Swarm Consensus + Agent Mobility (Design Validation)](#avm-swarm-consensus-agent-mobility-design-validation)
- [AVM NEON Mapping Plan (arm64, No-JIT-First)](#avm-neon-mapping-plan-arm64-no-jit-first)
- [AVM Time Calibration (Host Convenience)](#avm-time-calibration-host-convenience)

## AVM Anti-Tamper / Anti-Hack at Startup (Rolling)

This doc discusses whether AVM should verify its own integrity at startup (anti-tamper), and what it can
and cannot realistically defend against.

The key question:

> “What if a hacker replaced the AVM binary and also replaced the embedded root public key / verification code?”

### Threat levels (be explicit)

There are multiple “attacker strengths”:

1) **Artifact tampering in transit / at rest**
   - attacker can modify downloaded `.obc` / `.obx` / manifests
   - attacker cannot replace the AVM binary installed on the machine

2) **Local filesystem tampering (no kernel/root)**
   - attacker can modify files in user-writable directories
   - attacker cannot modify system-protected binaries or bypass OS protections

3) **Local machine compromise (root / kernel / debugger)**
   - attacker can replace `/path/to/avm`, patch it on disk, inject code at runtime,
     hook syscalls, change environment, etc.

The AVM signature model (Root CA → org → dev cert chain) is designed primarily for (1) and (2).
For (3), “self-checking” is fundamentally limited (see below).

### What AVM already defends (and how)

- **`.obc` provenance**: AVM verifies `OREN_SIG\n1\n` and optionally `OREN_CERTS\n1\n` before running artifacts.
  - The trust anchor is the **trusted root public key** (embedded or provided externally).
  - If the root public key is trustworthy, tampered artifacts are rejected.

### The hard truth: self-checking cannot create trust from nothing

If the attacker can replace the AVM binary, they can replace:

- the embedded root public key
- the signature verifier implementation
- the startup “self-check” routine itself

So AVM **cannot** “prove its own correctness” to itself if the attacker controls the executable.

This is a classical bootstrapping problem:

- A program cannot securely verify itself without an external trusted anchor.

Therefore, anti-tamper at startup is only meaningful when combined with an *external* trust boundary:

- OS code signing / notarization (macOS)
- secure boot + measured boot (TPM) (Linux/Windows)
- hardware attestation / enclave / TPM quotes
- reproducible build + external hash pinning

### Recommended trust anchors (practical)

#### A) OS code signing (macOS-first)

You already use codesigning for `oren` builds. Extending that mindset to AVM:

- distribute AVM as a codesigned binary
- optionally require notarization for “production distribution” builds

If AVM is codesigned and installed into a protected location, a simple “replace avm” attack becomes harder.

AVM startup “self-check” can then become:

- “verify that the binary is codesigned by expected team id” (platform API check)
- “verify we are not running under a debugger” (anti-debug; mostly a speed bump)

This provides “tamper evidence” under attacker levels (1) and (2), but does not defeat root compromise.

#### B) External root pubkey pinning

For deployments that want maximum control:

- do not embed a root pubkey in AVM
- instead pass `--trusted-pubkey` (or a set) via a deployment mechanism the attacker cannot change
  - system policy file in a protected directory
  - mobile/desktop MDM configuration
  - container image digest / Kubernetes secret (still has its own trust chain)

Then “replace AVM and also replace embedded pubkey” is less meaningful because the trust anchor is outside the binary.

#### C) Measured boot / attestation (future)

To defend against attacker level (3), you need attestation:

- boot measures AVM binary hash into TPM PCRs
- a remote verifier checks PCR quote + policy
- only then is AVM trusted to run sensitive workloads

This is bigger than rolling-mode AVM right now, but is the “correct” direction if you want production-grade anti-tamper.

### What AVM can do at startup (useful, limited)

#### 1) “Self-hash” (weak but cheap)

AVM can compute a hash of its own on-disk image and log it, or compare to an expected hash.

Limitation:

- if the attacker can patch the binary, they can patch the expected hash or the hashing code.

Still useful as:

- diagnostics / telemetry (“what exact AVM build is running?”)
- accidental corruption detection

#### 2) Verify embedded root pubkey is non-zero and matches a build-time constant

This is only meaningful when combined with external constraints (codesign / immutable deployment).
Otherwise the attacker replaces both.

#### 3) Anti-debug / anti-hook checks (speed bumps)

Examples:

- detect debugger attach
- detect LD_PRELOAD / DYLD injection patterns
- detect writable+executable memory mappings

Limitations:

- easy to bypass for a motivated attacker
- can cause false positives and harm developer UX

These are generally not recommended as default policy in rolling mode; they can exist behind a “hardened mode”.

### Answer to “what if hacker replaced the certs and sig?”

#### If they only replace the `.obc`’s certs/sig (OREN_CERTS/OREN_SIG)

AVM rejects it because:

- signature check fails, unless attacker has a valid delegated signing key.

#### If they replace the AVM binary to trust their own key

Then all bets are off unless you have an external trust boundary:

- OS code signing / secure boot / attestation / protected config pinning

This is not unique to Oren: it is the same for basically all verifiers (package managers, runtimes, etc).

### Rolling roadmap recommendation

P0 (now):

- keep artifact signature verification as the primary enforcement boundary
- document the bootstrapping limitation clearly (this doc)
- add optional “diagnostic self-hash” mode (not a security promise)

P1 (soon):

- ship codesigned AVM builds; consider a “release” build pipeline step that signs AVM
- allow a trusted pubkey *set* provided externally (rotation story)

P2 (later):

- measured boot / attestation integration for production deployments that require it


## AVM Concurrency Model (Deterministic, Syscall-First-Aligned, Multiverse-Friendly)

**Status:** Draft (design guidance + priorities)  
**Last updated:** 2025-12-15  
**Scope:** AVM execution semantics (bytecode VM), not the native backend runtime

This document defines what “concurrency” should mean for **AVM** in the AI/agent era, especially given:

- AVM supports **nested universes** (AVM-in-AVM) (`docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes`)
- AVM targets restricted environments (iOS/Web/Edge) and must stay **no-JIT-first**
- Oren’s native runtime roadmap is **syscall-first** and avoids libc/pthreads (`docs/CORE_SYSTEM_PLANS.md`)

The key requirement is not raw throughput; it is **deterministic, governable concurrency** that composes with:

- capability gating and virtualization
- snapshot/restore and “agent mobility”
- record/replay auditing
- swarm consensus (`docs/AVM_AND_OBC.md#avm-swarm-consensus-agent-mobility-design-validation`)

### 0) Non-negotiables

1) **Deterministic baseline**
   - AVM must have a single-thread deterministic execution mode that is stable enough for consensus.
2) **No host-thread nondeterminism in the core VM**
   - AVM must not depend on OS thread scheduling to define semantics.
3) **Blocking is always explicit and budgeted**
   - Any “wait” must be representable as a deterministic state transition (for snapshot/replay), and be subject to gas/time budgets.

### 1) Model: Cooperative, deterministic “tasks” (green threads)

AVM concurrency should be **cooperative** and **deterministic**:

- A VM instance contains N lightweight tasks (“fibers”, “coroutines”, “green threads”).
- At any point, exactly one task is “running” in the interpreter.
- Tasks yield only at explicit yield points:
  - `sleep_ms`
  - blocking channel operations
  - `await` on a syscall-like host op (VirtualFS/VirtualNET/VirtualPROC)
  - explicit `yield` (when syntax lands)

This is aligned with:

- **snapshot/restore**: the scheduler state and task stacks are data
- **nested universes**: each child universe can be modeled as a task that runs under a separate budget allocation
- **syscall-first thinking**: “blocking” means “park until an event”, not “spin”

#### 1.1 Deterministic scheduler rule

Scheduler determinism rule (recommended v0):

- Maintain a FIFO ready queue of runnable task IDs.
- On yield/block, the current task is moved to:
  - ready queue tail (voluntary yield), or
  - a wait queue keyed by (channel/time/event)
- On wake, tasks are enqueued in deterministic order:
  - time events ordered by `(wake_time, task_id)`
  - channel wakeups ordered by `(channel_id, enqueue_order)`

This ensures:

- given the same program + inputs + virtual time + replay logs, scheduling is deterministic
- `TRACE_HASH` can validate schedule decisions without recording them separately

### 2) Syscall-first alignment: AVM “syscalls” are capability-scoped host services

The native runtime’s syscall-first plan (`sys_*`) is about **native backend** independence from libc.

For AVM, “syscall-first alignment” means something analogous:

- all effectful / potentially blocking operations are modeled as explicit **capability-scoped calls**
- such calls must be:
  - denyable (capabilities)
  - budgeted (gas/time/io/log)
  - virtualizable / replayable (Virtual* backends)

Conceptually:

> AVM concurrency is an event loop that multiplexes capability-scoped “syscalls”.

Examples:

- `FS.read_file` may be instantaneous in “real host mode”, but in VirtualFS it is a deterministic lookup.
- `NET.http_request` (future) should always be modeled as an async op with replay logs providing responses in deterministic mode.

### 3) Nested universes as concurrent tasks (multiverse scheduling)

Nested universes (domain `AVM`, run child `.obc`) should integrate with the scheduler as:

- **spawn child universe** → create a child task whose execution is the child VM run
- **join** → parent task blocks until the child finishes (or budget aborts)

Important design choice:

- Child universes should not share mutable memory with the parent.
- Parent/child communicate via explicit data:
  - returned `MAP` (exit_code, hashes, logs)
  - `BYTES` replay log blobs (already supported)

This keeps universes composable and governable.

### 4) No OS threads in AVM semantics (but parallelism is a host optimization)

AVM semantics should be defined as **single-threaded**.

Implementations may:

- run multiple AVM instances in parallel at the host layer (outside semantics)
- use SIMD kernels for pure compute domains

But:

- bytecode-visible concurrency semantics must remain deterministic.

This is crucial for:

- consensus verification
- reproducible agent debugging
- stable snapshot/resume behavior

### 5) What we need before true concurrency lands (prerequisites)

To add task scheduling without breaking determinism, AVM needs:

1) A deterministic trace stream and `TRACE_HASH` (agent debugging + schedule validation)
2) A stable “blocking primitive” model in the VM:
   - “blocked on channel”
   - “blocked until virtual time >= t”
   - “blocked on event id”
3) Snapshot/restore that includes scheduler state
4) Virtualized TIME and record/replay for effectful domains (already partially present)

### 6) Priorities (derived from repo TODOs)

Near-term “must-have” tasks to unlock deterministic concurrency:

- Implement deterministic `TRACE_HASH` and a canonical trace encoding (see `docs/TODOS.md` P1).
- Define the `TASK` domain surface (design first):
  - spawn task (pure)
  - join task (blocking)
  - channel ops + select (blocking)
- Extend snapshot/restore to include tasks + wait queues (once tasks exist).


## AVM-in-AVM (“Multiverse”) Design: Nested Virtual Universes

**Status:** Draft (design + feasibility + priorities)  
**Last updated:** 2025-12-15  
**Scope:** AVM running *child AVM instances* as a capability-governed service (nested deterministic “universes”)

This document extends the swarm/agentic vision with a specific idea:

> An AVM program can spawn a child AVM, creating nested virtual “universes”.  
> Universes can be deterministic, record/replay-effectful, capability-bounded, and resumable.

The target outcome is not “cool recursion”; it is a **practical agent substrate**:

- run thousands of safe simulations (“Matrix”) *inside* a larger agent
- sandbox untrusted plugins as child universes
- enable hierarchical governance and validation (“outer world validates inner worlds”)
- support “agent mobility” even across nested computations (snapshot capsules)

### 0) Is it attractive?

Yes, if (and only if) the following constraints are met:

1) **Deterministic semantics + deterministic serialization** exist (or are explicitly enabled as a mode).
2) **Effect virtualization** exists so that “universe A” can be replayed identically on another node.
3) **Hierarchical budgeting** exists so parents can cap child universes and avoid denial-of-service.
4) **Capsule-able state** exists (snapshot/restore) so universes can migrate or suspend cheaply.

Without these, “VM-in-VM” becomes either:

- a slow novelty (pure interpreter inside interpreter), or
- an unsafe escape hatch (child can still touch host).

### 1) What “nested universes” means (precise model)

We define a **Universe** as an execution instance:

- **program**: `.obc` bytecode (or a code pointer in the future)
- **policy**: capability set + allowlists + budgets + deterministic mode flags
- **inputs**: args + injected fixtures (files/env/net fixtures) + optional initial snapshot
- **effects**: either forbidden, or mediated via record/replay / Virtual* backends
- **outputs**: result value, structured error, optional snapshot, and hashes

The key property:

> A universe is a *function of* `(program, policy, inputs, replay_log)` producing `(result, produced_log, snapshot, hashes)`.

That makes a child universe composable inside a parent agent workflow.

### 2) Two implementation strategies (feasibility)

#### 2.1 Strategy A (high feasibility, high value): “Nested universes via host service”

Add a capability domain (conceptually `AVM`) that lets a parent program request:

- spawn a child AVM instance
- run it under specified budgets and capability subset
- return child `RESULT_HASH`/`STATE_HASH` (and optionally the produced replay log)

This does **not** require writing an interpreter in Oren. It requires implementing a host service in `lib/avm` that:

- creates a new `AvmVM`
- loads child program bytes
- enforces budgets/capabilities (subset of parent)
- uses deterministic record/replay or Virtual* backends

Why this is attractive:

- gives “multi-universe” without performance collapse
- keeps enforcement at the AVM boundary (still capability-governed)
- allows strict hierarchy: child can never exceed parent budgets/caps

This is the recommended first approach.

#### 2.2 Strategy B (possible but low value): “AVM interpreter written in Oren”

Write a bytecode interpreter in `.oren`, compile it to `.obc`, and run it on AVM.

Feasible in principle, but:

- performance is much worse (interpreter-in-interpreter)
- it increases attack surface in user space
- it doesn’t magically solve effect virtualization; it still needs the same host boundary

This can be a later “proof of bootstrapping” demo, not the core architecture.

### 3) The “Capsule” abstraction (what moves between nodes/universes)

A **Universe Capsule** is the unit that can be:

- hashed (for consensus),
- stored (for persistence),
- transferred (for mobility),
- resumed (for continuation).

Minimum capsule fields (conceptual):

- `program_hash` (hash of `.obc` bytes)
- `policy_hash` (caps, allowlists, budgets, deterministic flags)
- `input_hash` (args + any injected fixtures + initial snapshot hash)
- `replay_log_hash` (if record/replay is used)
- `result_hash` (after run)
- `snapshot_hash` (optional, if paused or persisted)

Design rule:

> A swarm node should be able to verify a capsule without trusting the producer, by rerunning deterministically.

### 4) Determinism boundary: what must be replayed/virtualized

For nested universes to be meaningful, effectful domains must be either:

1) **forbidden** in consensus mode, or
2) **recorded** and replayed exactly.

Effectful domains include:

- FS (filesystem)
- PROC (subprocess)
- ENV (environment)
- TIME (clock, sleep)
- RNG/CRYPTO (randomness, entropy)
- NET (network)

Bootstrap status (repo reality as of 2025-12-15):

- FS/PROC/ENV now support minimal record/replay logs in `avm` (rolling), including in-memory “log as data” (`BYTES`).
- TIME/RNG are virtualized in deterministic mode (derived virtual clock + deterministic PRNG).
- NET is virtualized in bootstrap via **VirtualNET fixtures** (no host network; deterministic fixture responses).

Nested universes become dramatically more attractive once TIME and RNG are virtualized, because agents often depend on them even when “no external I/O” is intended.

### 4.1) Virtual by default, host by explicit enrollment (recommended)

In this repo’s design, capability **domains** (FS/NET/PROC/…) define *what effect is being requested*.
Separately, each domain is bound at runtime to a **backend**:

- **virtual backend**: no host effects, deterministic fixtures, snapshot-friendly
- **host backend**: touches real host resources, not inherently deterministic or snapshot-portable

Recommended rule (matches capsule safety goals):

1) **Capsule / simulation / nested universes default to virtual backends** (VirtualFS/VirtualNET/VirtualPROC).
2) Host backends are allowed only by **explicit enrollment** in the execution context (and therefore bound into `EXEC_HASH_SHA256` / job objects).

This keeps governance honest: a verifier can distinguish “safe simulation” vs “live host effects”.

### 4.2) Direct host mapping (no relay) vs proxying through the parent

There are two ways a child universe can touch real resources:

#### Option A: direct host mapping (no relay; simplest)

The child universe runs with `*_backend=host` and directly executes host calls in-process.

This is attractive because:

- no “relay protocol” between universes is required
- performance is better (no marshaling or forwarding)
- semantics are simple (“child is just another VM instance in the same host process”)

Safety requirement (must hold):

- child effective policy must be a strict subset of the parent:
  - capabilities subset
  - allowlists subset (FS prefixes / NET allowlist / PROC allowlist)
  - budgets subset (gas/mem/io/log/timeouts)
- backend selection must be bound into `exec_hash` so it is audit-visible

Tradeoff:

- determinism is reduced unless effects are recorded/replayed
- snapshot/mobility is reduced because host resources cannot be serialized directly

#### Option B: proxying/relaying via the parent (more control; more complexity)

The child universe requests effects, but the parent (or host) performs them on its behalf.

This can add control points (e.g., interactive approvals, extra auditing), but it introduces:

- an IPC/protocol design problem
- performance overhead
- new failure modes (relay bugs break determinism)

Recommendation:

- Use Option A (direct host mapping) for trusted “live” workflows.
- Use Virtual backends + record/replay for deterministic/governed workflows.

### 4.3) Handle delegation (fd/socket passing) — later, explicit mode only

A tempting extension is to allow the parent universe to pass already-open host resources to a child:

- open file descriptors
- sockets
- process handles

This is powerful, but it has sharp edges for the core niche (determinism + mobility):

- raw host handles are not snapshot-portable
- replay on another node cannot reproduce the same handle identity
- policy must define who owns closing the handle and how budgets are charged

Recommended v0 stance:

- **Name-based access only** in nested universes (paths/URLs/commands) under allowlists.
- Do **not** allow passing raw host handles between universes in capsule/deterministic mode.

If/when handle delegation is added later:

- make it an explicit opt-in execution flag (e.g., `host_handles_allowed=1`)
- bind it into `exec_hash` (so governance sees that the run is non-portable)
- define snapshot restrictions clearly (either “cannot snapshot” or “snapshot does not preserve handles”)

### 5) Hierarchical budgets (must-have for safety)

Parent/child budgeting must be **hierarchical**:

- Parent has a total budget (gas/time/memory/IO/log).
- Parent allocates sub-budgets to each child universe.
- Child cannot exceed allocated budget.
- Parent cannot exceed its own budget due to child overhead.

This prevents:

- “fork bomb” universes
- slow replay log amplification attacks
- memory blowups from nested simulation
- log amplification attacks (producing huge record/replay logs as “data capsules”)

### 6) Why this is an “AI-era” killer feature (not a traditional VM feature)

Nested universes enable a common agent loop pattern:

1) Outer agent proposes N candidate plans.
2) For each plan, it spawns a child universe with a VirtualFS/VirtualNET fixture set.
3) Each child runs the plan code deterministically with strict budgets.
4) Outer agent compares child `RESULT_HASH`/trace summaries and selects the best plan.
5) Outer agent optionally replays the winning child universe on multiple swarm nodes (k-of-n).

This is “best-first search with safe simulation” as a first-class runtime capability.

### 6.1) Closing the loop: compiler-in-AVM (source → `.obc` inside the sandbox)

This repo’s “agent-native” ambition becomes dramatically more powerful once AVM can **ingest Oren source** and **emit `.obc`** *without a host toolchain*.

At a systems level, this does **not** require AVM to implement a full compiler in C.
Instead, AVM can run the compiler itself as a deterministic capsule:

- `oren.obc` (the Oren compiler compiled to bytecode)
- optional compiler snapshot (warm-start)
- strict governance: caps + budgets (gas/mem/io/log) + deterministic TIME/RNG

#### Why this is attractive (agentic / swarm reasons)

- **Compilation becomes reproducible** (hashable) when the compiler capsule + inputs are fixed.
- A swarm can validate:
  1) the compiler capsule hash, and
  2) the produced `.obc` hash,
  before trusting the result.
- “Self-healing toolchains”: an agent can ship source, compile in-sandbox, and iterate without ever requiring `cc`/`ld`/`codesign`.

#### What is required (practical prerequisites)

To make “source → `.obc` inside AVM” useful (not just theoretical), we need:

1) **VirtualFS fixture** for nested universes:
   - parent provides a virtual filesystem tree (as data)
   - child compiler reads `main.oren` and writes `out.obc` into VirtualFS
2) **A stable input channel**:
   - either a VirtualFS file, or explicit `stdin_bytes` / `input_bytes` provided by policy
3) **A result retrieval channel**:
   - either VirtualFS file read-back, or returning `BYTES` directly
4) **Deterministic compilation mode**:
   - deterministic TIME/RNG already exist; compilation must avoid host nondeterminism (env, clocks)
5) **Budgeted logs**:
   - record/replay logs and capsule outputs must be budgeted to prevent amplification.

This design composes naturally with “AVM-in-AVM”: compilation is “just another universe”.

### 6.2) Current bootstrap cfg keys for nested universes (implementation reality)

When calling `oren_avm_run_obc_bytes(child_obc_bytes, cfg_map)`, the following `cfg` keys exist today (rolling, unstable):

- Capabilities/budgets/determinism:
  - `allowed_domains: int` (bitmask)
  - `gas_limit: int`, `deadline_ns: int`, `mem_bytes: int`, `io_bytes: int`, `log_bytes: int`
  - `deterministic: bool`, `time_start_ns: int`, `time_step_ns: int`, `rng_seed: int`
- Virtual backends (avoid host effects):
  - `fs_backend: int` (`1` = VirtualFS, `0` = host FS)
  - `proc_backend: int` (`1` = VirtualPROC, `0` = host PROC)
  - `net_backend: int` (`1` = VirtualNET, `0` = host NET (not implemented in bootstrap)`)
- Fixture injection as data (for nested universes):
  - `vfs_fixtures: bytes` with magic `AVMVFS01` (path→bytes table)
  - `proc_fixtures: bytes` with magic `AVMPRC01` (cmd→exit_code table)
  - `net_fixtures: bytes` with magic `AVMNET01` (url→body table)

Notes (important, implementation reality):

- **Capability nesting is enforced:** if the parent universe is restricted (deny-by-default with an allowlist),
  the child’s requested `allowed_domains` must be a **subset** of the parent’s allow mask.
  - Example: if the child needs `NET` (domain 4), the parent must also allow domain 4 (otherwise the parent cannot delegate it).
- **Input type matters:** `oren_avm_run_obc_bytes` requires `child_obc_bytes` to be true `BYTES`.
  - `oren_read_bytes(path)` in AVM is legacy and returns `list<int 0..255>`; pack it with `oren_bytes_pack(...)` before calling `oren_avm_run_obc_bytes`.

#### Return shape (today)

On success, `oren_avm_run_obc_bytes(...)` returns a `map` with these keys:

- `exit_code: int`
- `result_hash: bytes` (32 bytes)
- `state_hash: bytes` (32 bytes)
- `record_log: bytes` (magic `AVMLOG01`)
- `last_error: err | nil`
- `vfs_snapshot: bytes | nil` (magic `AVMVFS01` when present)
- `result: any | nil` (child `oren_set_result(...)` value)

### 7) Top emergency tasks (prioritized)

These are the most urgent tasks to make “multiverse” real (not speculative).

#### P0 (blocking): make deterministic universes self-contained

0) **Make the bytecode verifier reliably accept valid code** (no false rejects).
   - Nested universes require verifying *child* `.obc` before running it.
   - Verifier must handle interprocedural calls without spurious “stack height mismatch at join”.
   - Baseline approach (bootstrap): treat callee entry stack depth as `nargs` (relative-to-fp), not caller `sp`.

1) **Introduce `BYTES` as a first-class value type** (packed buffers).
   - Required to carry replay logs *in-memory* (not via host filesystem).
   - Required to embed `.obc` blobs and fixtures as data.
2) **Move record/replay logs from “file paths” to “bytes blobs”** (or support both):
   - `record_log_bytes` and `replay_log_bytes` should be representable as `BYTES`.
   - prefer “log as data” so child universes can be spawned and replayed without host FS.
3) **Virtualize TIME and RNG** (deterministic clock + deterministic RNG).
   - Without this, “deterministic” universes still diverge in common workloads.
4) **Add memory budget enforcement** (heap + buffers).
   - Nested universes without memory caps are unsafe.

#### P1 (high leverage): child-universe service surface

5) **Add an `AVM` capability domain** (host service) to spawn/run child universes.
   - Input: program bytes + caps + budgets + replay log bytes + optional initial snapshot.
   - Output: child result + child result hash + produced log bytes + optional snapshot.
6) **Hash the replay log and print `REPLAY_LOG_HASH`** (and include it in job objects).

#### P2 (scale): traces, verification, governance

7) **Deterministic trace hashing** (optional but high value).
8) **Policy scanner becomes “domain/op” precise** (deny specific ops, not just domains).
9) **VirtualNET / VirtualPROC** backends (fixtures) so simulations can cover real workflows safely.

### 8) Related docs

- Swarm consensus + mobility: `docs/AVM_AND_OBC.md#avm-swarm-consensus-agent-mobility-design-validation`
- Next-gen AVM plan (see “Next-Gen AVM Plan” section): `docs/AVM_AND_OBC.md`
- Agentic requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`

## AVM Plugins + Nesting (OBC-First, iOS-Safe) (Rolling)

Oren’s “restricted environment” track (iOS/App Store, Web, Edge) requires:

- **no JIT** (interpreter-first AVM),
- **capability gating** (no ambient FS/PROC/NET),
- **determinism + budgets** (replayable, composable sandboxes),
- and a distribution story where **stdlib and compiler can run as bytecode**.

This doc is a fact-first bridge between:

- multiverse execution (`docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes`),
- bytecode module linking (`docs/AVM_AND_OBC.md`),
- stdlib distribution/resolution (`docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`),
- and the repo-wide roadmap (`docs/TODOS.md`, `docs/LANGUAGE_STATUS_AND_GAPS.md`).

**Last updated:** 2026-01-16

---

### 1) Terminology (concrete)

- **OBC**: an `.obc` bytecode program executed by the AVM interpreter.
- **OBX**: linker metadata embedded as an unused `BYTES` constant inside `.obc` (exports + relocs). AVM ignores it at runtime. See `docs/AVM_AND_OBC.md`.
- **Universe**: one AVM instance with its own budgets, deterministic TIME/RNG, and capability allow mask.
- **Child universe / nesting**: running one `.obc` inside another via a governance boundary (caps + budgets + virtual backends).

This repo uses “plugin” in two different senses. Keeping them separate avoids design drift.

---

### 2) Plugin Model A (works with iOS constraints): plugin = child universe

#### Why this is the default “plugin” model for AVM

On iOS/App Store, a “plugin” must not:

- require `dlopen` of arbitrary native code,
- require JIT,
- share ambient host effects (FS/NET/PROC) unless explicitly delegated.

So the most robust plugin shape is:

1) Outer program (host or AVM) selects a plugin `.obc` (as `BYTES`).
2) Outer runs it as a **child universe** with an explicit config map:
   - `allowed_domains` subset,
   - budgets (`gas_limit`, `mem_bytes`, `deadline_ns`, `io_bytes`, `log_bytes`),
   - virtual backends + fixtures (VirtualFS/VirtualPROC/VirtualNET),
   - deterministic TIME/RNG.
3) Child returns:
   - `exit_code`, `result`, `result_hash`, `state_hash`,
   - optional `record_log` + `vfs_snapshot`.

Status (fact, today):

- Nested-universe execution is described (and partially implemented) via `oren_avm_run_obc_bytes(child_obc_bytes, cfg_map)`:
  - Interface + cfg keys: `docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes` section “6.2 Current bootstrap cfg keys”.
  - Determinism/fixtures intent: `docs/AVM_AND_OBC.md` (Next-Gen plan section), `docs/AGENTIC_REQUIREMENTS.md`.

This model is already “plugin-friendly” because:

- it composes with budgets (prevents “plugin fork bombs”),
- it composes with determinism (replay log is data),
- it composes with capability delegation (parent can only delegate what it has).

#### What “stdlib and compiler as plugins” means under Model A

- **stdlib**: ship a precompiled `stdlib_bundle.obc` and link it at compile-time (preferred) or run it in a child universe for isolated tooling tasks.
- **compiler**: ship `oren.obc` and run it in a child universe to compile source → output `.obc` inside VirtualFS.

This is “compiler-in-AVM” without requiring a C compiler inside the sandbox.

---

### 3) Plugin Model B (future, more complex): runtime module loading inside one universe

This is the classic dynamic language “plugin” model: load modules at runtime and call their functions *in the same VM instance*.

What it enables:

- shared caches (one copy of stdlib across multiple apps),
- smaller app artifacts (load-on-demand modules),
- “true plugin” APIs: trait objects + dynamic dispatch to code discovered at runtime.

What it requires (not fully implemented today):

1) **Runtime module identity and policy**
   - stable module naming / hashing scheme,
   - allow/deny rules: which modules may be loaded.

2) **A bytecode linking ABI usable at runtime**
   - exported symbol table
   - relocation / import resolution
   - global storage model: “per module” vs “shared globals”.

3) **Loader surface**
   - load module bytes, verify, link into current universe, return a module handle.

Current repo status (fact):

- Compile-time linking exists via OBX (`docs/AVM_AND_OBC.md`).
- Runtime dynamic module loading is explicitly a **non-goal** of the current OBX v0 format.

Therefore, treat Model B as a later step once the module ABI is stable and the security model is precise.

---

### 4) Practical milestone: compiler-in-AVM (source → `.obc` as data)

The “iOS-safe” end state is:

- Ship `libavm` + `oren.obc` in the app bundle.
- Provide a VirtualFS tree containing:
  - user sources,
  - stdlib sources OR precompiled stdlib bundle (depending on mode),
  - output path.
- Run `oren.obc` in a restricted universe to produce `out.obc` into VirtualFS.
- Optionally verify and run the produced `out.obc` as a second child universe (or as a sibling universe).

Key supporting docs:

- `docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes` (compiler-in-AVM section)
- `docs/AVM_AND_OBC.md` (precompiled stdlib bundle + relocations)
- `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` (stdlib specifiers + distribution models)

---

### 5) Recommended tracker items (so we don’t drift)

When updating `docs/TODOS.md`, keep these as separate deliverables:

1) **Model A hardening (child-universe plugins)**
   - stable `cfg` schema for `oren_avm_run_obc_bytes`
   - record/replay logs as `BYTES` (not paths)
   - deterministic TIME/RNG + budgets enforcement

2) **Compiler-in-AVM packaging**
   - produce and ship `oren.obc`
   - produce and ship `stdlib_bundle.obc` (or stdlib pack)

3) **Model B runtime module loading (optional later)**
   - only after module ABI + policy model is mature
   - likely built on top of OBX, but not the same as compile-time OBX linking

---

### 6) Local workflow (build + run smoke)

This repo includes a small “bytecode linking actually works” smoke that is useful before
attempting full compiler-in-AVM.

Build the stdlib bundle (exports via OBX) and run a tiny linked program under the host `avm`:

```
./scripts/verify_avm_bytecode_link_smoke.sh
```

Notes (rolling):

- `scripts/build_avm_plugins.sh` defaults to `lib/std/stdlib_avm.oren` (AVM-safe subset).
- Override the bundle root via `OREN_STDLIB_BUNDLE_ROOT=...` when experimenting.

Outputs (rolling):

- stdlib bundle: `build/plugins/stdlib_bundle.obc`
- linked app: `build/tmp/avm_obc_link_smoke.obc`
- logs: `build/logs/*avm_obc_link_smoke*`

Optional (heavier, rolling):

```
OREN_BUILD_COMPILER_OBC=1 ./scripts/build_avm_plugins.sh
```

This attempts to build a self-contained `build/plugins/oren.obc` by linking against `stdlib_bundle.obc`.

## AVM Swarm Consensus + Agent Mobility (Design Validation)

**Status:** Draft (design + feasibility analysis)  
**Last updated:** 2025-12-15  
**Scope:** “Swarms of agentic AI” running Oren bytecode (`.obc`) on AVM across many nodes

This document validates and extends the idea:

> Many AVM nodes form a swarm. They can reach consensus on outcomes. An AI agent can “flow everywhere” across the swarm, migrate between nodes, validate work, and extend capabilities safely.

The goal is to turn this into a **practical, testable architecture** that is attractive for AI-era workloads, without pretending away distributed-systems realities.

Related design extension:

- Nested universes (“AVM in AVM”): `docs/AVM_AND_OBC.md#avm-in-avm-multiverse-design-nested-virtual-universes`

### 0) What problem this solves (and what it does not)

#### Solves

- **Deterministic validation at scale:** many nodes independently run the same `.obc` and agree on outputs/state hashes.
- **Safe untrusted code execution:** capability-gated side effects mean “agent code” can be evaluated without giving it arbitrary host control.
- **Agent mobility:** an agent’s execution state can be snapshotted and resumed on another node (or after a crash).
- **Self-healing workflows:** deterministic record/replay enables “retry with fix” across nodes.

#### Does not solve automatically

- **Sybil resistance / identity:** you still need identities, attestation, or membership controls.
- **Network truth:** consensus can’t fix “the external world changed” unless effects are virtualized or recorded.
- **Byzantine faults:** if nodes lie, you need a BFT-style protocol and signatures.
- **Privacy:** you must design what state can be shared and what must be encrypted/redacted.

### 1) Core primitives (must exist to make the idea real)

The swarm vision is only practicable if these primitives are defined and enforced.

#### 1.1 Deterministic execution and deterministic serialization

Requirement:

- same `.obc` + same inputs + same deterministic mode + same capability replay log
  → same **result** and same **state hash**.

Implications for AVM:

- define core semantics precisely (ints, floats policy, string encoding)
- define map ordering policy (either ordered maps, or “unordered but canonicalized” when hashing/serializing)
- define deterministic scheduling policy for concurrency (or forbid concurrency in deterministic consensus runs)

#### 1.2 Verifier + policy scanner (before execute)

Before any node runs a job, it must be able to verify:

- bytecode validity (stack discipline, jump targets, constant bounds)
- capability usage: which domains are used (`FS/NET/PROC/TIME/RNG/…`)

This enables “trustless-ish” execution:

- nodes can refuse bytecode that requests forbidden capability domains
- nodes can enforce budgets and avoid hangs

#### 1.3 Capability-gated host effects + virtualization

Effectful domains (FS/NET/PROC/TIME/RNG) must be:

- capability-scoped
- deny-by-default in restricted modes
- virtualizable (VirtualFS/VirtualNET/VirtualPROC) for simulation and replay

This turns “consensus on a computation” into something meaningful, because:

- external effects are either banned, virtualized, or recorded/replayed

#### 1.4 Snapshot / restore (“agent mobility”)

An “agent flowing across the swarm” means:

- node A can snapshot the VM state
- node B can restore and continue execution

This requires:

- a stable snapshot format (ideally content-addressed / chunked)
- well-defined “safe points” for snapshotting (e.g., at instruction boundaries, not mid-native-call)

### 2) Two swarm modes (separate them explicitly)

The swarm idea becomes practical when you distinguish:

#### Mode A: Deterministic consensus jobs (“compute consensus”)

Goal:

- many nodes run the same job and agree on the output/state hash.

Typical usage:

- verify a proposed patch
- verify that a plan produces expected outputs
- verify a model-scoring routine produces stable results

Constraints:

- deterministic mode on
- external effects disabled or replayed
- strict budgets

#### Mode B: Distributed agent execution (“service consensus”)

Goal:

- agents do real work (I/O, network, subprocess) and coordinate.

Typical usage:

- web research agent, build agent, deployment agent

Constraints:

- consensus applies to *records of effects* and *auditable traces*, not “truth”
- you still want capability gating and budgets, but determinism is partial

Practical approach:

- run Mode B as “best effort” with auditing
- use Mode A for verification and governance (“does this change match policy?”)

### 3) Minimal protocol sketch (practicable, not hand-wavy)

This is an intentionally minimal design that can be implemented incrementally.

#### 3.1 Job object (what the swarm agrees on)

A “consensus job” is:

- `program_hash`: hash of `.obc`
- `policy_hash`: hash of allowed capabilities + budgets
- `input_hash`: hash of explicit inputs (args, provided files, initial snapshot)
- `replay_log_hash` (optional): if effects are replayed

The job result is:

- `exit_status` (success/error)
- `result_hash` (hash of returned value or final state)
- `trace_hash` (optional: hash of deterministic execution trace)

Practical bootstrap approach:

- start with **state hashing** (hash heap + globals + stack + control state) because it is easy to compute and hard to fake accidentally
- add **result-only hashing** when the VM has an explicit result contract (so it’s not “whatever happens to be on the operand stack”)

Bootstrap status (rolling, as implemented today):

- `avm --print-state-hash <file.obc>` prints `STATE_HASH ...`
- `avm --print-result-hash <file.obc>` prints `RESULT_HASH ...`
- result selection is explicit via `oren_set_result(v)` (if not called, the result is treated as `nil`)

Job scanning (rolling, no-execute tooling):

- `avm --print-job <file.obc>` prints a text form with:
  - `JOB_HASH_SHA256 <hex>`
  - `PROGRAM_HASH_SHA256 <hex>`
  - `INPUT_HASH_SHA256 <hex>`
  - `EXEC_HASH_SHA256 <hex>`
  - policy lines (`POLICY_*`)
- `avm --print-job-json <file.obc>` prints `{"schema":"avm.job.v7", ...}`

Current `job_hash_sha256` (v7) definition:

- `job_hash_sha256 = SHA256( "AVMJOB07" || program_hash_sha256_bytes || policy_hash_sha256_bytes || input_hash_sha256_bytes || exec_hash_sha256_bytes )`

Current `input_hash_sha256` (v1) definition:

- `input_hash_sha256 = SHA256( "AVMINP01" || args || snapshot_hash? || replay_log_hash? )`
  - `args` are the CLI args passed after `--` (count + length-prefixed strings)
  - `snapshot_hash` is `SHA256("AVMSNAP1" || snapshot_bytes)` if `--snapshot-in` is provided
  - `replay_log_hash` is `SHA256("AVMRLOG1" || replay_log_bytes)` if `AVM_REPLAY_LOG` or `AVM_REPLAY_LOG_HEX` is provided

Current `exec_hash_sha256` (v7) definition:

- `exec_hash_sha256 = SHA256( "AVMCTX07" || flags || outputs || trace_limits || fs_backend || proc_backend || proc_fixtures || net_backend || effective_allow_domains_mask || fs_allow_prefixes || budgets || deterministic_knobs )`
  - flags include: `capsule`, `verify_strict`, `deny_by_default`, `record_enabled`, `replay_enabled`
  - outputs include:
    - record sink kind (`none|file|mem`) and `snapshot_out_enabled` (paths are intentionally not hashed)
    - requested output surfaces: `state_hash`, `result_hash`, `trace_hash`, `trace_bytes`, `record_log_hex`
  - `trace_limits` include the effective trace step limit (`--trace-limit`) and `AVM_TRACE_BYTES` (when trace bytes output is requested)
  - `fs_backend` selects whether FS domain uses host filesystem or VirtualFS (`host|vfs`)
  - `proc_backend` selects whether PROC domain uses host subprocess or VirtualPROC (`host|vproc`) and binds `proc_exit_code` when `vproc` is selected
  - `net_backend` selects whether NET domain uses host network or VirtualNET (`host|vnet`) and binds `net_fixtures_hash_sha256` when fixtures are provided
  - `effective_allow_domains_mask` is what AVM will actually enforce (e.g. capsule default CORE+EXIT when deny-by-default and no allowlist provided)
  - `fs_allow_prefixes` is the normalized comma-separated list (count + length-prefixed strings)
  - budgets include: `gas`, `timeout_ms`, `mem_bytes`, `io_bytes`, `log_bytes`, `trace_bytes` (with capsule defaults applied if env unset)

#### 3.2 Node execution and attestation (minimum viable)

Each node returns:

- `(job_id, result_hash, exit_status)` signed by node identity (or at least tagged with node ID)

Consensus rule (non-Byzantine baseline):

- accept the result if `k-of-n` nodes agree on `result_hash` (k configurable)

If you need Byzantine tolerance:

- require signatures + membership + BFT (out of scope for v0, but the design must not prevent it)

#### 3.3 Agent mobility protocol (snapshot routing)

“Flow everywhere” becomes concrete as:

- a snapshot blob `snap` + `snap_hash`
- a “resume ticket”: `(snap_hash, job_id, pc, budgets, capabilities)`
- any node can resume by fetching `snap` and continuing

Important:

- resuming must preserve the same deterministic constraints if the goal is consensus

### 4) Why this is attractive (if the requirements are met)

Compared with “just run Python on many machines”, this design can offer:

1) **Verifiable computation**: bytecode verifier + deterministic mode + replay logs
2) **Safety**: capability gating at the VM boundary, not “library convention”
3) **Fast simulation**: VirtualFS/VirtualNET turns agents into “simulated worlds” at scale
4) **Operational resilience**: snapshot/restore enables “immortal agents” (pause/resume)
5) **Governance**: policies are explicit inputs (policy hash), and results are reproducible

### 5) Feasibility constraints (what must be implemented first)

This idea is **attractive** and **practicable** only if the system provides:

1) Deterministic mode definition (including map order / numeric corner cases)
2) Bytecode verifier + capability scanner
3) Stable structured errors (machine-readable) instead of crashes
4) Budgets/timeouts and cancellation
5) Snapshot/restore with canonical serialization and hashing

Without (5), “agent mobility” is limited to “restart from scratch”.
Without (2) and (4), swarms become fragile and unsafe (hangs, malicious bytecode).

### 6) Concrete next steps (aligned with current repo)

These are staged to avoid huge rewrites:

1) **Finish error contract** and standardize error representation (today: map-based `{"__err":...}`).
2) **Finalize budgets** (gas + deadlines) across host calls, not just interpreter loop.
3) **Implement verifier + capability scanner** for `.obc`.
4) **Define canonical snapshot format** and implement snapshot/restore for core types.
5) Add a minimal “swarm harness” (future):
   - multiple AVM runs on the same machine to simulate k-of-n consensus
   - compare `result_hash` outputs

Bootstrap status (rolling):

- AVM supports `--print-state-hash` / `--print-result-hash` and a local “k-of-n” harness to validate determinism on one machine:
  - `tools/avm_swarm_local.sh`
  - hash is SHA-256 over a canonicalized serialization (maps hashed in canonical key order)

### 7) Related Docs

- Canonical requirements: `docs/AGENTIC_REQUIREMENTS.md`
- Advanced scenarios: `docs/ADVANCED_SCENARIOS.md`
- AVM spec (bootstrap + Next-Gen plan section): `docs/AVM_AND_OBC.md`

## AVM NEON Mapping Plan (arm64, No-JIT-First)

This document defines how the current **typed-buffer kernel ABI** in the C AVM (scalar fallback) evolves into **NEON-accelerated** kernels on arm64 while preserving:

- determinism (consensus safety)
- snapshot/hash stability
- rolling ABI friendliness (we can add kernels, but stable kernels must not change semantics)

Scope: macOS arm64 first, but the plan is written to also apply to Linux arm64.

### 1) Goals

1) **Keep semantics stable**: NEON is an optimization, not a semantic change.
2) **No JIT required**: acceleration is in the interpreter/runtime (C code) using intrinsics.
3) **Determinism-first**: consensus mode must not become “depends on compiler flags”.
4) **Minimal surface**: small set of kernels that unlock most ML-ish workloads.

### 2) Kernel ABI nucleus (what we freeze)

The “ABI nucleus” is the set of kernels whose **names + argument order + return convention** are intended to become stable.

Rule: in-place kernels end with `_into` and always have:

- `dst` first
- inputs next
- scalar last (if any)
- return value is `dst` (for fluent `.oren` style, but still in-place)

Examples:

- `oren_buf_add_f32_into(dst, a, b) -> dst`
- `oren_buf_mul_f32_into(dst, a, b) -> dst`
- `oren_buf_scale_f32_into(dst, a, scalar) -> dst`

Scalar reductions are *not* `_into`:

- `oren_buf_dot_f32(a, b) -> float`
- `oren_buf_reduce_sum_f32(a) -> float`

We also provide allocation-free reduction forms (for pipeline style code and for SIMD kernels that want a “dst first” convention):

- `oren_buf_dot_f32_into(out:f64_buf, a:f32_buf, b:f32_buf) -> out` (stores at `out[0]`)
- `oren_buf_reduce_sum_f32_into(out:f64_buf, a:f32_buf) -> out` (stores at `out[0]`)
- `oren_buf_dot_i32_into(out:i64_buf, a:i32_buf, b:i32_buf) -> out` (stores at `out[0]`)
- `oren_buf_reduce_sum_i32_into(out:i64_buf, a:i32_buf) -> out` (stores at `out[0]`)

### 3) Data layout and loads/stores (must not change)

- Typed buffers are byte arrays with canonical little-endian element encoding:
  - `i32/i64`: two’s complement little-endian
  - `f32/f64`: IEEE-754 bit pattern little-endian
- NEON paths must interpret memory the same way.

Practical requirement:

- Use `memcpy` loads/stores (or unaligned-safe intrinsics) so behavior does not depend on alignment.
- Do not reinterpret pointers into `float*` / `int32_t*` unless alignment is guaranteed and verified.

### 4) Determinism rules for NEON kernels

Determinism constraints (consensus safety) apply even when NEON is enabled:

1) **No fast-math** (`-fno-fast-math`).
2) **No FP contraction / no FMA drift** (`-ffp-contract=off` + TU pragmas).
3) **Fixed evaluation order** for reductions.

Important nuance:

- Elementwise ops (`add`, `mul`, `scale`) are naturally deterministic given IEEE-754 and fixed per-element order.
- Reductions (`dot`, `reduce_sum`) are sensitive to reassociation. Even if SIMD is used, the reduction order must be fixed.

### 5) Recommended NEON strategies per kernel

#### 5.1 Elementwise kernels

These are safe to SIMD as “map” operations:

- `*_add_*_into`
- `*_mul_*_into`
- `*_scale_*_into`

Strategy:

- Process `N` elements in chunks of 4 (for f32) with `float32x4_t`.
- Use a scalar tail loop for `N % 4`.
- Writes must be exact element-by-element results (no reordering).

#### 5.2 Reduction kernels (dot/sum)

These are more delicate.

Strategy for `f32` reductions:

- Compute per-lane partial sums in vector registers (`float32x4_t`).
- Reduce lanes in a **fixed, explicit order** (pairwise in a deterministic sequence).
- Accumulate into a `double` scalar accumulator (already the scalar fallback policy).
- Use a scalar tail loop for remaining elements.

This yields a deterministic order that is stable across compilers and platforms *as long as* fast-math and FP contraction are disabled.

Implementation note (current repo):

- The NEON reductions preserve the scalar semantics by converting `f32 -> f64` and accumulating into a scalar `double` in a fixed element order.
- We intentionally avoid fused multiply-add intrinsics for reductions (no `vmlaq_f64`) to prevent FMA drift.

### 6) Feature gating: runtime + build-time

Runtime:

- Runtime opt-in flag: `AVM_ENABLE_SIMD=1` (default off until validated).
- AVM must remain correct without SIMD; SIMD is an optimization only.
- Consensus mode (deterministic) can force SIMD on/off depending on policy, but it must be explicit and stable.

Build-time:

- Keep AVM built with determinism flags by default.
- Add optional `AVM_SIMD_CFLAGS` when we introduce NEON intrinsics.

### 7) Testing strategy (high signal)

1) Keep a scalar reference implementation (the current code).
2) Add a SIMD-enabled build mode and run the same test suite:
   - smoke suite covers elementwise and reduction kernels
   - state-hash / snapshot-resume tests ensure determinism invariants stay true
3) For float kernels:
   - use exactly representable test constants where possible (e.g. 1.5, 0.25)
   - ensure reductions are tested (dot + reduce_sum)

### 8) What we do next (repo tasks)

1) Freeze the ABI nucleus list in `docs/AVM_AND_OBC.md` (names + arg order + return convention).
2) Implement NEON versions behind a build flag and runtime flag.
3) Validate:
   - macOS arm64 first
   - linux/arm64 in docker/qemu later

## AVM Time Calibration (Host Convenience)

AVM supports a deterministic virtual clock for consensus and nested universes:

- In deterministic mode (`AVM_DETERMINISTIC=1`), `oren_time_now_ns()` is **derived** from:
  - `AVM_TIME_START_NS` (virtual origin)
  - accumulated `oren_sleep_ms(ms)` (`+ ms * 1e6`)
  - executed “gas” count (`+ gas_executed * AVM_TIME_STEP_NS`)

This is a *logical clock*. It is **not** intended to match the host wall clock.

### What `AVM_TIME_STEP_NS` means

`AVM_TIME_STEP_NS` is:

- “virtual nanoseconds per gas unit”

It is **not**:

- “nanoseconds of CPU time per instruction”
- “cycles”
- “a real-time guarantee”

Consensus semantics depend on **gas** being deterministic and semantic. `AVM_TIME_STEP_NS` is just a scale factor mapping gas units into a monotonic virtual time value.

### Why calibrate it anyway?

Sometimes you want virtual timeouts/backoffs to “feel” roughly like real time on your development machine (especially when you haven’t stabilized gas costs or implemented more realistic domain costs yet).

For that, you can measure how many gas units per second your host executes and pick a convenient `AVM_TIME_STEP_NS`.

### macOS benchmark script

This repo includes a small “pure compute” benchmark that:

- runs an infinite loop (stopped safely by `AVM_GAS=...`)
- measures host wall elapsed time
- reports `ns_per_gas` and suggests `AVM_TIME_STEP_NS`

Run:

```sh
bash tools/bench/bench_time_scale.sh
```

Or override the benchmark gas budget:

```sh
AVM_GAS_BENCH=200000000 bash tools/bench/bench_time_scale.sh
```

The script prints a JSON line from:

- `./avm --print-run-json build/bench_gas.obc`

and computes:

- `ns_per_gas = wall_elapsed_ns / gas_executed`

### Important limitations

- The benchmark result is **host- and build-dependent** (CPU, OS, compiler flags, etc.).
- This does **not** make deterministic virtual time “more correct”; it only makes it more intuitive for interactive use.
- For consensus jobs, treat virtual time as a *simulation time* derived from work, not as a wall-clock substitute.
