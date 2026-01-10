# Compiler Gotchas (Rolling)

This doc captures **non-obvious invariants** that have caused regressions during self-host bring-up.
Keep it short and actionable; link to the deeper design docs when needed.

## Windows: `oren_system(...)` must preserve cmd.exe semantics

On Windows, `oren_system(cmd)` is implemented as `cmd.exe /C <cmd>`.

Important:

- Do **not** reconstruct `cmd` via `argv[]` → “MSVC quoting rules” → CreateProcess command line.
  `cmd.exe` frequently re-parses the **raw** command line and CRT-style escaping (notably `\"`)
  can break quoted paths and redirections (`>nul 2>nul`).
- The native runtime therefore passes the `cmd` string through to `cmd.exe` **without** re-escaping.

Implementation reference: `lib/runtime_native/260_threads.oren` (`oren_system_timeout`, Windows branch).

Regression gate: `make verify-stage2-win` (ensures `ensure_dir(...)` works for default `build/targets/...` outputs).

## Windows: native backend must accept portable `'/'` paths

Oren compiler/runtime code is allowed to use POSIX-style paths (`build/targets/...`) even on Windows.
The x64-windows native backend normalizes `'/'` → `'\\'` at the syscall intrinsic boundary for Win32 APIs:

- `sys_open` (CreateFileA)
- `sys_stat`/`sys_lstat` (CreateFileA-based probe)
- `sys_unlink`/`sys_rmdir` (DeleteFileA/RemoveDirectoryA)
- `sys_rename` (MoveFileExA)
- `sys_mkdir` (CreateDirectoryA)

Implementation reference:

- `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren`
- `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren`

## Windows: do not rely on `OS=Windows_NT` for path parsing

In rolling mode, scripts and shells can execute the compiler in environments where `OS=Windows_NT`
is missing or overridden (PowerShell/SSH sessions, minimal envs, etc.).

Hard rule:

- Path helper functions used for output naming (`basename`, `dirname`) must treat both `/` and `\\`
  as separators, regardless of `OS` env var presence.

## Windows: MSVC wrapper batch scripts and variable expansion

When generating `.cmd` wrappers for MSVC (`VsDevCmd.bat` / `vcvars64.bat`), avoid this pitfall:

- In `cmd.exe`, `%VAR%` expansions inside a parenthesized block are evaluated when the block is parsed,
  so “set then use” within the same `(...)` block can silently read the old value.

Prefer linear `if ...`/`goto` flow, or use delayed expansion (`!VAR!`) carefully.

Implementation reference: `lib/compiler/compiler/040_build_pipeline.oren` (Windows `--backend c` MSVC path).

## arm64: rtobj fixups must preserve `reg` (or you can crash at startup)

The arm64 runtime-object cache (rtobj) stores precompiled runtime machine code plus a list of relocation fixups.

Non-obvious invariant:

- For `adr_data` fixups (ADRP+ADD), the destination register matters.
  - Some hot runtime helpers load `g_storage` into scratch registers like `x9`.
  - If the rtobj meta drops `reg`, the final fixup applier defaults to `x0` and the emitted code can end up as:
    - `adrp x0, ...; add x0, x0, ...; ldr x9, [x9]`
    - which dereferences an uninitialized register and typically crashes at startup (`EXC_BAD_ACCESS`, often at `0x1000`).

Rolling rules:

- If you change rtobj fixup encoding/decoding, bump the arm64 rtobj backend signature in `lib/compiler/native_runtime_obj_cache.oren` so stale cache entries are not reused.
- Keep a fast regression check: `./scripts/bench_native_compile_one_file.sh --no-debug` should show a working miss→hit sequence (isolated rtobj dir; seed disabled).

## x64: stale rtobj can mask (or preserve) codegen bugs

The x64 runtime-object cache stores precompiled runtime machine code. If x64 codegen changes in a way that affects runtime correctness, but the x64 rtobj backend signature is not bumped, old cached runtime machine code can keep a fixed bug “alive” (or reintroduce it) even though the source was corrected.

Rolling rules:

- If you change x64 native codegen that can affect emitted runtime code/data bytes, bump `RUNTIME_OBJ_BACKEND_SIG_X64` in `lib/compiler/native_runtime_obj_cache.oren`.
- For debugging, you can force a clean comparison between “rtobj hit” and “no rtobj” builds by setting `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`.
- Diagnostic hygiene: x64 native codegen errors are deduplicated by message (still fatal) to avoid huge logs from repeated sites; if you see one, treat it as a real correctness failure and fix it at the source.

## Native value semantics: never rely on `scalar == nil`

Rolling invariant (until `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md` lands):

- The native backend is still rolling toward a fully tagged value model; do not treat scalars as “optionals” via `nil`.
- Native mode now uses **runtime singleton values** for `nil/false/true` (distinct non-zero pointers stored in globals), which removes the worst historical `0/nil/false` aliasing footguns.
- Guardrail (2026-01-10): the compiler rejects `bool/int/float == nil` comparisons when the scalar side is:
  - statically known (literals, casts, or locally-proven scalars), **or**
  - later proven scalar by best-effort scan (e.g. `var t = cfg["x"]; if t == nil { ... }; i64(t)`).
  - Regression fixtures: `tests/fixtures/typecheck_bad_numeric_nil.oren`, `tests/fixtures/typecheck_bad_bool_nil.oren`, `tests/fixtures/nil_guard_bad_late_scalar_nil_compare.oren`, `tests/fixtures/nil_guard_bad_late_scalar_nil_compare_top_level.oren`
  - Fast gate: `make test`

Concrete rule (treat as a correctness bug in rolling native builds):

- Do **not** write `if x == nil { ... }` when `x` is numeric/bool (or you *expect* it to be).
  - Example footgun: `var x = cfg["timeout_ms"]; if x == nil { x = 1000 }`
  - If you intentionally accept `nil` as “missing” for a numeric/bool parameter (optional arg style), prefer a tag-based check on truly dynamic values:
    - `if oren_type_tag(x) == 0 { x = 0 }`
  - Prefer explicit “optional” shapes instead (e.g. return `{"ok":1,"v":...}` / `{"ok":0}`), or keep the value as `nil`/non-`nil` reference types and avoid using `0`/`false` as “missing” sentinels.

Practical compiler-internal corollary (x64 emitters):

- If you store a **byte offset** (where `0` is a valid payload) inside a map/dict (e.g. fixup records, offset caches), you must protect `0` from “missing” ambiguity.
  - Preferred: store `off+1` and decode via `off = enc-1`.
  - This is still a good habit even with singleton `nil`: it avoids “value vs missing” ambiguity and keeps code robust during rolling refactors.

## Native strings: embedded literal pool must not hit GC tracking

The self-hosted compiler contains **many** string literals. In native mode, tracking each literal as a heap object (or even creating per-literal metadata nodes) can become a real startup and GC hotspot.

Rolling invariants:

- Native codegen de-duplicates `"literal"` bytes into a single NUL-terminated pool (`cstr0`) embedded in the binary data blob.
- The native entry stub calls `oren_init_static_cstr0_table(...)` once at startup to build a membership set for the literal start pointers.
  - This makes `native_is_string_ptr(...)` safe and fast **without** heap-copying literals.
- String literals must **not** be treated as GC-managed heap allocations:
  - Do not root them (`native_gc_register_root`) and do not “intern” them into heap strings.
  - When you need an owned, tracked string, copy into a heap string explicitly (example helper: `oren_intern_cstr`).

Implementation references:

- cstr0 membership set + init: `lib/runtime_native/100_time.oren` (`oren_init_static_cstr0_table`, `native_cstr0_set_has`)
- string helpers + intern cache: `lib/runtime_native/150_strings.oren`
- safety guard for tracking: `lib/runtime_native/110_mem_diag.oren` (`oren_ensure_tracked`, string kind branch)

Engineering note (self-hosting hygiene):

- Avoid adding new dependencies on external host tools (e.g. `rg`/ripgrep) inside the compiler runtime path.
  - If you need pattern matching for compiler tooling, prefer Oren stdlib modules (regex/tokenization) so the compiler remains self-contained on Tier‑1 targets.
