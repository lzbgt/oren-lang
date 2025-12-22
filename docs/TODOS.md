## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Include chunk coherence (overflow-proofing)** (M)
   - Status: parser + bytecode backend include chunks are now split on top-level brace boundaries (no more mid-block splits): `lib/compiler/parser_parse/*.oren`, `lib/compiler/codegen_bytecode/*.oren`.
   - Status: native runtime typed buffers split further (`lib/runtime_native/200_typed_buffers.oren` now includes smaller parts under `lib/runtime_native/typed_buffers/`) to avoid context overflow.
   - Status: ARM64 native backend include chunks are now coherent per-file:
     - `native_compile_expr()` is a small dispatcher; per-chunk helpers live in `lib/compiler/arm64_native_expr/*`.
     - `native_compile_syscall_call()` is a small dispatcher; per-chunk helpers live in `lib/compiler/arm64_native_expr_syscalls/*`.
   - Status: added capsule prehook hooks + lowering calls for `sys_mmap_private_anon` / `sys_munmap` so AVM capsule audit passes.
   - DoD: ensure `// @include`-split sources don’t break mid-block (each included file should start/end on a coherent boundary), to keep per-file reviewable without context overflow.
   - Next: split the remaining large native runtime entrypoints (`lib/runtime_native/*.oren`, especially `runtime_native.oren`) into smaller included modules guided by `docs/` (breaking changes OK while rolling).

2) **Repo-wide grammar modernization + audits** (L)
   - Status: removed legacy `if (...)` forms across `.oren` sources (compiler/runtime/tests) by rewriting conditions to modern `if cond { ... }` (introduced temporaries where operator precedence required).
   - Status: added an `oretest` repo-style audit to prevent regressions back to `if (...)` / `else if (...)` legacy syntax.
   - DoD: update remaining `.oren` sources (especially `lib/std/*.oren`) to the current grammar/idioms (e.g. `for x in ...`, modern `if`/`else`, `match` where applicable), removing known legacy syntax.
   - Guardrails: extend `cmd/oretest` audits to ban additional legacy constructs once confirmed from `docs/` (keep the allowlist tiny and explicit).
   - Keep the modernization rolling: new code must not regress into legacy syntax.

### P1 (Soon)

1) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: intrinsic-level tail determinism tests added for `simd_dot_f32_ptr`, `simd_dot_f32_4_ptr`, and `simd_gemm_f32_4x4_ptr`; runtime now uses the single-pass microkernels.
   - DoD: broaden coverage (NaN/Inf/sign-bit edge cases, large `n`) and keep macOS+Linux parity for these intrinsics.

2) **ARM64 instruction encoder audit** (S)
   - Status: replaced `LSLV` uses in SIMD tail math (constant scale factors) with add-doubling to reduce sensitivity to variable-shift encoding.
   - DoD: spot-check the most-used instruction encoders (especially loads/stores) against clang/objdump golden encodings to prevent silent mis-encodes from regressing correctness.

3) **Native networking hardening** (M)
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

4) **Docs parity pass** (S)
   - Status: fixed `docs/LANGUAGE_SPEC.md` to include `%` (modulo) in the infix operator grammar + precedence list (matches the compiler’s token set).
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
