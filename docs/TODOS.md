## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Stdlib modernization pass** (M)
   - DoD: standardize on current grammar idioms across `lib/std/*.oren` (prefer `for x in ...` where semantics match; prefer string `+` over `string_concat`).
   - Guardrails: keep `cmd/oretest` audits updated (e.g. `auditStdlibModernStyle`) to prevent regressions (reintroducing `string_concat`, legacy `@forin_*`, etc.).

### P1 (Soon)

2) **SIMD intrinsic tail correctness** (M)
   - DoD: make the direct intrinsic tail path(s) (`simd_dot_f32_ptr`, and then `simd_dot_f32_4_ptr` / `simd_gemm_f32_4x4_ptr`) bit-exact for odd `n` and fractional f32 inputs, so runtime wrappers can stop doing scalar tail cleanup.

3) **Native networking hardening** (M)
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

4) **Docs parity pass** (S)
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
