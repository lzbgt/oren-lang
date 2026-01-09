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

