# Oren Implementation Notes (Agent Cache)

This document is a **succinct, rolling “cache”** of important implementation details that are easy to forget and expensive to rediscover by re-reading code.

It is intended for:

- AI agents working on the compiler/runtime/stdlib (to avoid context overflow),
- maintainers reviewing changes across backends,
- power users debugging “why did this lower that way?”

This file is **non-normative**:

- For formal semantics: `docs/LANGUAGE_SPEC.md`
- For practical usage: `docs/LANGUAGE_MANUAL.md`
- For feature maturity + gaps: `docs/LANGUAGE_FEATURE_MATRIX.md`, `docs/TODOS.md`

---

## 1) Naming + module aliasing: `std:*` → `STD_*` (stable)

### 1.1 Stable stdlib prefix

The module linker uses a **stable prefix** for stdlib modules:

- `std:list` → `STD_list_`
- `std:net/http` → `STD_net_http_`

Implementation:

- `lib/compiler/compiler/020_modules_linking.oren` → `_stable_std_prefix(path)`

### 1.2 Why “alias names” look weird (`M5_list`)

Within a module, an import like:

```oren
import list "std:list"
list.push(xs, 1)
```

is rewritten so the alias is **namespaced by the importing module prefix**:

- `list` becomes `M5_list` (example)
- The call becomes `M5_list.push(xs, 1)` in the merged program AST

This prevents collisions when all modules are merged into one program.

Implementation:

- `lib/compiler/compiler/020_modules_linking.oren` (import alias namespace + `renamer.rename_program_in_place`)

### 1.3 Global alias map: “module-local alias” → “target module prefix”

After linking/merging, the compiler has a global alias map:

- `linked["aliases"]` is a map from `alias_ns` to `dep_prefix`
- Example mapping:
  - `M5_list` → `STD_list_`

This map is used by multiple passes (capsule scanning, impl lowering, bytecode codegen) to resolve
expressions like `M5_list.push` into a **fully-qualified symbol** string.

---

## 2) Namespace expression resolution: `M5_list.push` → `STD_list_push`

Many passes work on AST nodes like:

```json
{"type":"Member","left":...,"prop":...}
```

To resolve imported-module member calls, the compiler uses a helper that:

1) resolves the left side through `linked["aliases"]`, then
2) joins names with underscores to build a **symbol string**.

Example:

- `M5_list.push`
- `aliases["M5_list"] = "STD_list_"`
- result: `STD_list_push`

Implementation:

- `lib/compiler/impl_lowering.oren` → `resolve_ns_name(aliases, expr)`

Note:

- This function trims trailing `_` on prefixes and always joins with `_` so it’s robust across prefix forms.

---

## 3) Container ops: what lowers to what (today)

### 3.1 Method sugar (`xs.push(v)`) is a lowering, not a type system

In rolling v0, builtin container method sugar is implemented as a deterministic rewrite when the
compiler can infer the receiver “kind” from syntax/local flow:

- `xs.push(v)` → `oren_list_push(xs, v)`
- `xs.len()` → `oren_list_len(xs)`

Implementation:

- `lib/compiler/impl_lowering.oren` → builtin container method sugar (`rewrite_expr_in_place` path)

### 3.2 Hot stdlib wrapper inlining (`std:list.push`)

Stdlib exports ergonomic wrappers:

- `std:list.push(xs, v)` returns `nil`
- `std:list.len(xs)` returns int

But in hot loops we want **no wrapper call overhead**. The impl lowering pass recognizes these wrapper calls
via the linked alias map and rewrites:

- `STD_list_push(xs, v)` → `oren_list_push(xs, v)`
- `STD_list_len(xs)` → `oren_list_len(xs)`

Implementation:

- `lib/compiler/impl_lowering.oren` → `rewrite_call_expr(...)` (“Inline stdlib thin wrappers”)

---

## 4) `oren_list_push` return value contract (IMPORTANT)

**Contract (rolling):** `oren_list_push(list, value) -> nil`

Rationale:

- `push` is a statement-like container operation in the language surface (and stdlib wrapper returns `nil`).
- Returning the list header pointer is not needed (the list object identity is stable).
- Keeping a single contract across backends avoids subtle portability bugs when backends inline it differently.

Backends/runtime behavior (source of truth locations):

- Native runtime (native backends): `lib/runtime_native/170_lists.oren`
- C runtime (C backend): `lib/runtime/040_lists_maps.inc`
- AVM: `lib/avm/avm_native.inc` (native id `13` leaves default `nil`)
- Native arm64 inliner: `lib/compiler/arm64_native_expr/030_lowering_c.oren`
- Native x64 inliner: `lib/compiler/x64_native_program/040_emit_expr.oren`

Naming note:

- Stable stdlib symbols use the `STD_*` prefix (`STD_list_push`, `STD_list_len`).
- Legacy lowercase `std_list_*` spellings are not part of the current linking scheme and should not be relied on.

Docs that reference this contract:

- `docs/LANGUAGE_SPEC.md` (builtin container sugar section)
- `docs/AVM_SPEC.md` (native id map)

---

## 5) Native `STACK_TRACE` debug info (arm64 + x64)

### 5.1 What “debug info” means in rolling native

Native backends do not yet emit DWARF/PDB. Instead they embed **best-effort tables** so panics can print readable stack traces.

Current Tier‑1 behavior:

- `oren_panic(msg)` prints a stable `OREN_DIAG ...` line, then prints `STACK_TRACE`, then aborts.
- `STACK_TRACE` is based on a frame-pointer chain (`FP`/`LR` on arm64; `RBP` on x86_64).
- Symbolication uses embedded tables (best-effort; fixed-base emitters on x64).

Implementation (x86_64 native v0 bring-up):

- Stack trace printing: `lib/compiler/x64_native_program/071_panic.oren`
- Symtab storage/fill: `lib/compiler/x64_native_program/010_data_io.oren` (`_data_reserve_symtab`, `_data_finalize_symtab`)
- Call-site linetab storage/fill (debug builds): `lib/compiler/x64_native_program/010_data_io.oren` (`_data_reserve_linetab`, `_data_finalize_linetab`)
- Call-site linetab resolve + printing: `lib/compiler/x64_native_program/071_panic.oren` (`_emit_resolve_loc_ptr_best_effort` + stack-trace loop)

### 5.2 How to enable/disable native debug info

Rolling compiler UX policy:

- Native builds embed stack-trace debug info **by default**.
- Disable with `--no-debug` (or env `OREN_NATIVE_NO_DEBUG=1`).
- Use `--debug` to force-enable (but `--debug` and `--no-debug` together is an error).

Note:

- x64 call-site `@file:line` mapping depends on embedding the linetab (debug mode).
- Function definition locations (`fn@file:line`) come from tokens on function nodes during symtab display synthesis.

### 5.3 Native integer canonicalization (goal + current guard)

**Goal (Tier‑1 invariant):** treat Oren “int” values as **canonical i64** in both registers and stack slots.

- **Registers**: carry full 64-bit values (no “upper bits undefined” model).
- **Stack locals / spills**: use **8-byte slots**; any store must fully initialize all 8 bytes.

Why this matters:

- Many host ABIs and syscalls use 32-bit ints (Windows `DWORD`/`BOOL`, POSIX `int`, socket `socklen_t`, etc).
- Partial-width stores (or reading 8 bytes back from a 4-byte out-param) can create “high 32-bit garbage” values.
- These show up first as **timeout/length/port** corruption and can cause hangs or flaky timeouts on x86_64.

**Current state (rolling):**

- The native runtime includes an i32 canonicalization guard (`native_canon_i32_arg` / `native_canon_timeout_ms_arg`) on some syscall-first NET and thread-timeout entrypoints.
- Debug hook: set `OREN_DEBUG_CANON_I32=1` to emit a single warning when the guard sees a non-canonical i32-ish value (helps catch regressions without dumping huge logs).

**Policy:**

- Treat any guard-trigger as a **native backend correctness bug** to fix at the root.
- Keep the high-signal regression gate green across the matrix:
  - `scripts/verify_native_net_matrix.sh` (NET + loopback services)
  - `scripts/verify_selfhost_x64_compiler.sh` (x86_64 self-host)

---

## 6) Quick debugging checklist (fast “where is this implemented?”)

Suggested ripgrep pivots:

```bash
# Where do stdlib stable prefixes come from?
rg -n \"_stable_std_prefix\\(\" lib/compiler/compiler/020_modules_linking.oren

# How does alias.member resolve to a symbol string?
rg -n \"fn resolve_ns_name\" lib/compiler/impl_lowering.oren

# Where are container wrappers inlined?
rg -n \"Inline stdlib \\\"thin wrappers\\\"\" lib/compiler/impl_lowering.oren

# Where do backends inline list ops?
rg -n \"oren_list_push\" lib/compiler/arm64_native_expr/030_lowering_c.oren lib/compiler/x64_native_program/040_emit_expr.oren

# AVM native id mapping
rg -n \"case 13\" lib/avm/avm_native.inc
```

Shell note (zsh): if you put backticks in an unquoted command string, zsh treats them as command substitution.
Prefer code fences in docs, or escape backticks when running commands interactively.

---

## 7) Platform selection defaults (host auto-detection)

Rolling policy:

- Prefer `--platform <arch>-<os>` for native backend selection.
- Fallback: env `OREN_PLATFORM=<arch>-<os>`.
- If neither is provided, the compiler defaults to the **runtime host platform** (so the same compiler binary can run on macOS/Linux/Windows and "do the right thing" by default).

Implementation:

- Host detection helper: `lib/compiler/compiler/010_cli_helpers.oren` → `detect_host_platform()`
  - Windows: `OS=Windows_NT` + `PROCESSOR_ARCHITECTURE` (`AMD64`/`ARM64`)
  - POSIX-ish: `uname -s` / `uname -m`
- Effective selection is applied in the build pipeline for `build`/`meta`/`dump`:
  - `lib/compiler/compiler/040_build_pipeline.oren`

Regression gate:

- `scripts/verify_selfhost_x64_compiler.sh` intentionally omits `--platform` when running the x64 compiler binaries on Win11+WSL2, so the gate proves host auto-detection (not just codegen correctness).

---

## 8) Runtime reflection helpers (`oren_type_tag`, `oren_type_name`)

For basic reflection and varargs dispatch, the runtime provides:

- `oren_type_tag(v)` → int tag (matches `lib/runtime.h` `OrenType` enum values)
- `oren_type_name(v)` → stable string name for that tag (logging/branching convenience)

Implementation:

- C runtime: `lib/runtime/040_lists_maps.inc`
- Native runtime: `lib/runtime_native/130_printing.oren`

Rolling note (native backend):

- Native values are not fully tagged yet; numeric immediates (`int`/`bool`/`float`) may be indistinguishable in native mode (so `oren_type_tag` can return `1` for multiple numeric kinds).
- Track the full fix: `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`

Evidence:

- Native quick integration includes a varargs + reflection smoke: `tests/native/test_quick_integration_native.oren` (`test_type_tag_varargs`).

---

## 9) String equality: avoid `==` in compiler passes (stage1 vs stage2)

Oren currently has **multiple runtimes** that execute compiler/tooling code:

- Stage1 compiler: built via the C backend (C runtime semantics)
- Stage2 compiler: built via the native backend (native runtime semantics)

In rolling mode, do **not** assume `==` on strings behaves identically across these runtimes.
In particular, some native-runtime paths rely on **interning / pointer identity** for fast comparisons,
which can break checks that compare:

- a string built via concatenation/slice (non-interned), with
- a string coming from config/env/CLI (often interned), or a literal.

Practical rule (compiler-side code):

- Prefer **byte-wise equality** using `oren_string_len` + `oren_string_byte_at_unchecked` in any pass that must behave the same in stage1 and stage2.

Reference implementations:

- Stable helper used in hot compiler code: `lib/compiler/x64_core.oren` → `string_eq_bytes(a,b)`
- `@cfg(...)` evaluation uses its own byte-wise helper to stay portable: `lib/compiler/cfg_lowering.oren` → `_cfg_str_eq(a,b)`
