## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Split `lib/compiler/arm64_native_expr_syscalls.oren` via `// @include`** (L)
   - Why P0: it’s ~4k lines and the syscall/capsule policy “center of gravity”.
   - DoD: move to `lib/compiler/arm64_native_expr_syscalls/*.oren` parts + manifest, with `make test` green.

2) **Refactor remaining huge compiler files via `// @include`** (M)
   - DoD: split remaining >2000-line compiler modules into `lib/compiler/<name>/...` parts while keeping builds + `make test` green.
   - Next files: `lib/compiler/codegen_bytecode.oren`, `lib/compiler/parser_parse.oren`, `lib/compiler/compiler.oren`.

3) **SIMD correctness unblock** (M)
   - DoD: make `simd_dot_f32_4_ptr` / `simd_gemm_f32_4x4_ptr` pass correctness suites (or keep them disabled but add an explicit tracked failing test with a minimal reproducer).

### P1 (Soon)

4) **Native networking hardening** (M)
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

5) **Docs parity pass** (S)
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
