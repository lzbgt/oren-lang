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
   - Status: split `lib/std/linalg.oren` into smaller modules under `lib/std/linalg/*.oren` with a stable facade to avoid crossing the 2000-line refactor threshold.
   - Status: split `lib/runtime_buf.c` into smaller include chunks under `lib/runtime_buf/*.inc` (single translation unit) to avoid >2000-line C hotspots.
   - Status: split `lib/runtime.c` into smaller include chunks under `lib/runtime/*.inc` (single translation unit) to avoid >2000-line C hotspots.
   - Status: added an `oretest` repo-style audit to prevent `.oren` files from growing past 2000 lines (forces module splits before context overflow).
   - Status: added an `oretest` repo-style audit to prevent C runtime include chunks (`lib/runtime/*.inc`, `lib/runtime_buf/*.inc`) from growing past 2000 lines.
   - Status: added an `oretest` include-chunk coherence audit for `// @include` roots (missing include detection + per-chunk brace-balance sanity, ignoring `//` comments and `"..."` strings).
   - Status: strengthened the audit with a “chunk start looks top-level” heuristic to catch mid-block splits that still have balanced braces (e.g. a chunk starting with `if`/`return`/`x = ...`).
   - DoD: keep all `// @include`-split sources chunk-safe (no mid-block splits) so each included file stays reviewable without context overflow.
   - Next: keep applying overflow-proofing to any single-file hotspots before they cross the 2000-line refactor threshold (use `wc -l` to track growth).

2) **Repo-wide grammar modernization + audits** (L)
   - Status: removed legacy `if (...)` forms across `.oren` sources (compiler/runtime/tests) by rewriting conditions to modern `if cond { ... }` (introduced temporaries where operator precedence required).
   - Status: added an `oretest` repo-style audit to prevent regressions back to `if (...)` / `else if (...)` legacy syntax.
   - Status: removed legacy `while (...)` forms (compiler lexer + native runtime) and added an `oretest` repo-style audit to prevent regressions back to `while (...)`.
   - DoD: update remaining `.oren` sources (especially `lib/std/*.oren`) to the current grammar/idioms (e.g. `for x in ...`, modern `if`/`else`, `match` where applicable), removing known legacy syntax.
   - Guardrails: extend `cmd/oretest` audits to ban additional legacy constructs once confirmed from `docs/` (keep the allowlist tiny and explicit).
   - Keep the modernization rolling: new code must not regress into legacy syntax.

### P1 (Soon)

1) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: intrinsic-level tail determinism tests added for `simd_dot_f32_ptr`, `simd_dot_f32_4_ptr`, and `simd_gemm_f32_4x4_ptr`; runtime now uses the single-pass microkernels.
   - Status: added NaN/Inf edge-case coverage for `simd_dot_f32_ptr` (native) ensuring Inf stays Inf (bit-stable) and NaN propagates as NaN (checked by NaN-ness, not payload).
   - Status: added large-`n` intrinsic determinism coverage for `simd_dot_f32_ptr` (`n=4097`) to exercise long accumulation paths + tail handling.
   - DoD: broaden coverage (NaN/Inf/sign-bit edge cases, large `n`) and keep macOS+Linux parity for these intrinsics.

2) **ARM64 instruction encoder audit** (S)
   - Status: replaced `LSLV` uses in SIMD tail math (constant scale factors) with add-doubling to reduce sensitivity to variable-shift encoding.
   - DoD: spot-check the most-used instruction encoders (especially loads/stores) against clang/objdump golden encodings to prevent silent mis-encodes from regressing correctness.

3) **Native networking hardening** (M)
   - Status: added deterministic timeout coverage to the curated native integration suite:
     - TCP: `oren_tcp_accept(..., 10)` returns `-ETIMEDOUT` when no clients connect.
     - UDP: `oren_udp_recvfrom_into(..., 10)` returns `-ETIMEDOUT` when no datagrams arrive.
   - Status: added UDP loopback send/recv coverage (bind ephemeral port, `sendto` to 127.0.0.1:<port>, then `recvfrom`).
   - Status: added deterministic arg-validation coverage for `oren_fd_wait_any_{readable,writable}` (empty list / nil => `-EINVAL`), preventing hangs/crashes from bad inputs.
   - Status: added deterministic timeout coverage for `oren_fd_wait_any_readable([fd], 10, out)` returning `0` when no fd becomes ready (prevents hangs and enforces consistent semantics).
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

4) **Docs parity pass** (S)
   - Status: fixed `docs/LANGUAGE_SPEC.md` to include `%` (modulo) in the infix operator grammar + precedence list (matches the compiler’s token set).
   - Status: updated `docs/LANGUAGE_SPEC.md` EBNF to include `for <name>[:Type] in <expr> { ... }` iterator sugar (matches the parser implementation).
   - Status: updated `docs/LANGUAGE_MANUAL.md` examples to avoid legacy `if (...)` statement form.
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
