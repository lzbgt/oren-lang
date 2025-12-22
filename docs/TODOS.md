## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **ARM64 instruction encoder audit** (S)
   - Status: added native golden-encoding coverage for key `arm64_core.oren` encoders (loads/stores, prologue/epilogue, add/sub imm+reg, B/BL/B.cond/BR/BLR, ADR/ADRP, broadcast/moves, basic SIMD ops, widening + pairwise ops).
   - Status: migrated native `adr_{data,code}` + Mach-O GOT stubs from ADR (±1MB) to ADRP+ADD (±4GB) and added `oretest` audits to enforce 2-slot reservation (compiler fixups + debug hook + Mach-O GOT stubs).
   - Next: add more golden cases for pair loads/stores and keep them small/deterministic.

2) **Include chunk coherence (overflow-proofing)** (M)
   - Status: large `.oren` and C runtime hotspots are split into include-chunks/modules; `oretest` enforces 2000-line caps and include-chunk coherence for `// @include` roots.
   - Next: keep new refactors chunk-safe (top-level boundaries only) so files stay reviewable without context overflow.

### P1 (Soon)

1) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: intrinsic-level tail determinism tests added for `simd_dot_f32_ptr`, `simd_dot_f32_4_ptr`, and `simd_gemm_f32_4x4_ptr`; runtime now uses the single-pass microkernels.
   - Status: added NaN/Inf edge-case coverage for `simd_dot_f32_ptr` (native) ensuring Inf stays Inf (bit-stable) and NaN propagates as NaN (checked by NaN-ness, not payload).
   - Status: added NaN/Inf edge-case coverage for `simd_dot_f32_4_ptr` (native) to ensure lane-local Inf and NaN propagate deterministically.
   - Status: added large-`n` intrinsic determinism coverage for `simd_dot_f32_ptr` (`n=4097`) to exercise long accumulation paths + tail handling.
   - Status: added large-`n` intrinsic determinism coverage for `simd_dot_f32_4_ptr` (`n=4097`) to exercise multi-output dot paths + tail handling.
   - Status: added large-`n` intrinsic determinism coverage for `simd_gemm_f32_4x4_ptr` (`n=1025`) to exercise long 4x4 GEMM accumulation paths + tail handling.
   - Status: added NaN/Inf edge-case coverage for `simd_gemm_f32_4x4_ptr` (native) to ensure per-row NaN propagation and Inf stability are deterministic.
   - DoD: broaden coverage (NaN/Inf/sign-bit edge cases, large `n`) and keep macOS+Linux parity for these intrinsics.

2) **Repo-wide grammar modernization + audits** (L)
   - Status: repo scans show no remaining `.oren` uses of legacy paren-forms (`if (...)`, `while (...)`, `for (...)`, `match (...)`, `switch (...)`); `oretest` blocks regressions.
   - Next: keep the allowlist tiny and explicit; add a targeted rule only when a new legacy pattern is discovered in `docs/` or via a regression.

3) **Native networking hardening** (M)
   - Status: added deterministic timeout coverage to the curated native integration suite:
     - TCP: `oren_tcp_accept(..., 10)` returns `-ETIMEDOUT` when no clients connect.
     - UDP: `oren_udp_recvfrom_into(..., 10)` returns `-ETIMEDOUT` when no datagrams arrive.
   - Status: added UDP loopback send/recv coverage (bind ephemeral port, `sendto` to 127.0.0.1:<port>, then `recvfrom`).
   - Status: added deterministic arg-validation coverage for `oren_fd_wait_any_{readable,writable}` (empty list / nil => `-EINVAL`), preventing hangs/crashes from bad inputs.
   - Status: added deterministic timeout coverage for `oren_fd_wait_any_readable([fd], 10, out)` returning `0` when no fd becomes ready (prevents hangs and enforces consistent semantics).
   - Status: extended arg-validation coverage for `oren_fd_wait_any_{readable,writable}` to require `out_fd_ptr != 0` (null out pointer => `-EINVAL`).
   - Status: made negative `timeout_ms` non-blocking across kqueue+epoll wait paths (`timeout_ms < 0` treated as 0ms) to avoid backend-dependent hangs; added regression coverage in native integration suite.
   - Status: normalized kqueue wait failure return to `-ENOSYS` instead of `-1` (keeps errno-style consistency across wait helpers).
   - Status: added regression coverage ensuring single-fd waits (`oren_fd_wait_readable(fd, -1)`) also treat negative timeouts as 0ms (no wait).
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

4) **Docs parity pass** (S)
   - Status: fixed `docs/LANGUAGE_SPEC.md` to include `%` (modulo) in the infix operator grammar + precedence list (matches the compiler’s token set).
   - Status: updated `docs/LANGUAGE_SPEC.md` EBNF to include `for <name>[:Type] in <expr> { ... }` iterator sugar (matches the parser implementation).
   - Status: updated `docs/LANGUAGE_MANUAL.md` examples to avoid legacy `if (...)` statement form.
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
