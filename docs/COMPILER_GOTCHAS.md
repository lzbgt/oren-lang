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

## Native value semantics: never rely on `scalar == nil`

Rolling invariant (until `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md` lands):

- The native backend historically used an untagged “i64 carrier” value model where `nil/false/0` could alias in some compare paths.
- The optimizer mitigates common accidents (`0 == nil`, `false == nil`, and some trivially-provable locals), but values flowing through maps/fields/params can still observe the raw carrier.
- Guardrail for annotated code: `--typecheck` rejects `bool/int/float == nil` comparisons.
  - Regression fixtures: `tests/fixtures/typecheck_bad_numeric_nil.oren`, `tests/fixtures/typecheck_bad_bool_nil.oren`
  - Fast gate: `make test` (runs the `--typecheck` smoke inside `scripts/run_native_quick_integration.sh`)
