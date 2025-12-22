## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Repo-wide grammar modernization + audits** (L)
   - DoD: update remaining `.oren` sources (especially `lib/std/*.oren`) to the current grammar/idioms (e.g. `for x in ...`, modern `if`/`else`, `match` where applicable), removing known legacy syntax.
   - Guardrails: extend `cmd/oretest` audits to ban additional legacy constructs once confirmed from `docs/` (keep the allowlist tiny and explicit).
   - Keep the modernization rolling: new code must not regress into legacy syntax.

### P1 (Soon)

2) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: `simd_dot_f32_ptr` tail path fixed + directly regression-tested.
   - DoD: make `simd_dot_f32_4_ptr` and `simd_gemm_f32_4x4_ptr` bit-exact for odd `n` and fractional f32 inputs, so runtime can switch to single-pass microkernels without scalar cleanup.

3) **ARM64 instruction encoder audit** (S)
   - DoD: spot-check the most-used instruction encoders (especially loads/stores) against clang/objdump golden encodings to prevent silent mis-encodes from regressing correctness.

4) **Native networking hardening** (M)
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

5) **Docs parity pass** (S)
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
