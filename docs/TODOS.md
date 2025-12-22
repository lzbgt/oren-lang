## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Signed `.obc` + Root Trust (multiverse updates / “app store”)** (M)
   - Status: added rolling design doc `docs/APPSTORE_ROOTCA_AND_UPDATES.md`.
   - Status: added delegated signing cert-chain spec `docs/CERT_CHAIN_FORMAT.md` (`root → org → dev`).
   - Status: added `orensign` tool (`cmd/orensign/main.go`) for ed25519 keygen + `.obc` signing/verifying (keys live outside repo, recommended `../oren-ca/`).
   - Status: `orensign issue-cert ...` issues delegated certs; `sign-obc --cert ...` embeds `OREN_CERTS` (repeatable, leaf-first).
   - Status: added AVM signature verification gate (`--require-sig`, `--trusted-pubkey`, nested cfg `require_sig` + `trusted_pubkey`), using `OREN_SIG\n1\n` BYTES constant.
   - Status: added AVM cert-chain enforcement (`--require-cert-chain`, nested cfg `require_cert_chain`) verifying `OREN_CERTS\n1\n` and leaf signing.
   - Status: added oretest fixture to ensure signed `.obc` runs and unsigned fails under `--require-sig`.
   - Status: added oretest fixture for org→dev delegated signing chain and negative cases under `--require-cert-chain`.
   - Status: added pure-Oren SHA-256 (`std:crypto/sha256`) and AVM test vectors as the first step toward “bytecode crypto” (no libc/FFI).
   - Next: embed a real root pubkey in AVM builds (public only), add root rotation support (trusted pubkey set), add cert constraints (namespace/policy allowlists), and port ed25519 verify to pure Oren to reduce host-crypto dependency.

2) **Container ops modernization (generic + dyn)** (S)
   - Status: documented the design in `docs/DESIGN_CONTAINER_OPS.md` (3-layer model: kernel `oren_*` intrinsics → std wrappers → language-level ops) including deterministic dispatch rules for generics + `dyn`.
   - Status: introduced `lib/std/list.oren` wrapper module (and kept it bytecode-safe by implementing `get/set/last` via indexing rather than `oren_list_get/set`).
   - Status: migrated several stdlib modules to `list.*` wrappers (`argparse`, `strings`, `json`, `cbor`, `buffer`, `math`, plus `std/linalg` list helpers).
   - Next: migrate remaining `lib/std/yaml.oren` + `lib/std/regex.oren`, then add an `oretest` audit to forbid direct `oren_list_*` usage in `lib/std/` (except a tight allowlist like `lib/std/list.oren`).

3) **Precompiled stdlib `.obc` linking (OBX) for AVM** (M)
   - Status: implemented OBX module metadata (exports + relocations) embedded as an unused `BYTES` constant in `.obc` (`docs/OBC_MODULE_LINKING.md`, `docs/AVM_SPEC.md`).
   - Status: added `--obc-lib` to emit exports, and `--stdlib-mode obc --stdlib-obc <bundle>` to compile with extern `std:` imports and link the bundle into a single output program.
   - Status: added stdlib bundle root `lib/std/stdlib.oren` and stable std module prefixes (`STD_<path>_`) so symbols are deterministic for separate compilation.
   - Status: added a full-suite AVM smoke that compiles with `std:math` using only a stdlib bundle `.obc` (no std sources inside the child universe).
   - Next: add support for linking multiple non-stdlib packages via a formal search path (`OREN_PATH` / `--module-path`), and decide whether final `.obc` should strip OBX constants to reduce size.

4) **Include chunk coherence (overflow-proofing)** (M)
   - Status: large `.oren` and C runtime hotspots are split into include-chunks/modules; `oretest` enforces 2000-line caps and include-chunk coherence for `// @include` roots.
   - Next: keep new refactors chunk-safe (top-level boundaries only) so files stay reviewable without context overflow.

5) **Compiler CLI + argparse modernization (click-style)** (M)
   - Status: upgraded `lib/std/argparse.oren` to support `--opt=value`, `-abc` chained short flags, `-ovalue` short-value forms, interspersed options/positionals, and global options before subcommand.
   - Status: compiler driver now uses argparse to normalize argv, so the legacy driver logic accepts modern forms like `oren build --backend=native --out=... file.oren` without breaking existing `file first` invocations.
   - Status: added oretest regression to ensure equals-form flags + options-before-file keep working.
   - Next: remove the remaining legacy manual parsing in the compiler driver and dispatch directly from argparse results (less duplication, fewer edge cases).

6) **ARM64 instruction encoder audit** (S)
    - Status: added native golden-encoding coverage for key `arm64_core.oren` encoders (loads/stores, prologue/epilogue, add/sub imm+reg, B/BL/B.cond/BR/BLR, ADR/ADRP, broadcast/moves, basic SIMD ops, widening + pairwise ops).
    - Status: migrated native `adr_{data,code}` + Mach-O GOT stubs from ADR (±1MB) to ADRP+ADD (±4GB) and added `oretest` audits to enforce 2-slot reservation (compiler fixups + debug hook + Mach-O GOT stubs).
    - Status: expanded golden coverage to include basic atomic encoders (LDAXR/STLXR/CLREX/LDADD/CAS/STRB) with clang-verified constants.
    - Status: added clang-verified goldens for basic integer loads/stores (LDR/STR X, LDRB W).
    - Status: included `tests/native/test_arm64_encoding.oren` in the curated native suite so these goldens run on every `make test`.
    - Status: expanded goldens to cover SP-relative scaled loads/stores (LDR/STR [SP,#imm12<<3]).
    - Status: added parameterized pair load/store encoders (STP pre-index, LDP post-index) with clang-verified goldens for stack save/restore patterns.
    - Next: add more golden cases for pair loads/stores and keep them small/deterministic (use clang/otool to confirm encodings).

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

5) **HPC perf harness + linalg/math maturation** (M)
   - Status: initial matmul f32 benchmark harness exists under `tools/bench/` and now uses modern CLI forms.
   - DoD: expand bench coverage (dot/axpy/gemm variants), add result reporting, and validate SIMD kernels against a scalar reference for correctness + determinism.

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
