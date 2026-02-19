# Agent Virtual Machine (AVM) Specification

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
  - see `docs/OBC.md`
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

- See `docs/AVM_DESIGN.md#avm-neon-mapping-plan-arm64-no-jit-first` for the concrete mapping plan and determinism constraints.

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
- System evolution context: `docs/OREN_EVOLUTION.md`
- Roadmap: `docs/ROADMAP.md`
