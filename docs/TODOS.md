## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Native backend x86_64 (Linux ELF + Windows PE)** (L) (Tier 1 target)
   - Status: added x64 native backend foundation (`--backend native --arch x64`) that can compile small programs end-to-end.
   - Status: aligned x64 naming with Tier‑1 intent (removed `_min` module naming; now `lib/compiler/codegen_x64.oren` + `lib/compiler/x64_native_program.oren`).
   - Status: added x64 comparison coverage for `<, <=, >, >=` (build fixtures + opt-in remote-run exit code).
   - Status: x64 comparisons now support non-trivial RHS expressions (not only identifiers/integers) via a dedicated spill slot (`x64_cmp_expr_rhs_main.oren`).
   - Status: x64 now supports compare-as-expression (returns `0/1`) and prefix `!` as an expression via `cmp` + `setcc` lowering (`x64_cmp_expr_value_main.oren`, `x64_not_expr_value_main.oren`).
   - Status: x64 now supports short-circuit `&&` / `||` (RHS is not evaluated when not needed), returning normalized `0/1` (`x64_and_or_short_circuit_main.oren`).
   - Status: added x64 coverage for `else if` chains, `while <` loops, and negative signed comparisons (fixtures + build checks + opt-in remote-run exit codes).
   - Status: x64 lowering now supports Prefix unary `-` and `~` for integer expressions (fixtures + build checks + opt-in remote-run exit code).
   - Status: added Linux x86_64 ELF emitter (`lib/compiler/x64_elf.oren`) and Windows PE32+ emitter with import table for `kernel32!ExitProcess` (`lib/compiler/x64_pe.oren`).
   - Status: Linux x64 now supports `print("...")` (string literal only) via direct `SYS_write` + RIP-relative string data; oretest asserts the string is embedded in the ELF output.
   - Status: Windows x64 now supports `print("...")` (string literal only) via `kernel32!GetStdHandle` + `kernel32!WriteFile`; oretest asserts the string is embedded in the PE output.
   - Status: x64 lowering supports local `var x = <int>` and `return x` (stack slot via RBP-relative addressing); oretest ensures it builds for both ELF+PE targets.
   - Status: x64 lowering supports `+` / `-` on i32 (`return x + 2`, `return 40 - x` style); oretest ensures it builds for both targets.
   - Status: x64 lowering supports `if <id|int> (==|!=) <id|int> { ... } else { ... }` with early returns; oretest ensures it builds for both targets.
   - Status: x64 lowering supports truthy conditions (`if <expr> { ... }`, `while <expr> { ... }`, `if !x { ... }`, `if !(a < b) { ... }`, plus `if true/false { ... }`) by lowering to `cmp` + Jcc; oretest builds both targets (`x64_if_truthy_main.oren`, `x64_while_truthy_main.oren`, `x64_if_not_truthy_main.oren`, `x64_if_not_cmp_main.oren`, `x64_if_bool_lit_main.oren`).
   - Status: x64 lowering supports `while <id|int> (==|!=) <id|int> { ... }` plus assignment (`x = x + 1`) with local vars; oretest ensures it builds for both targets.
   - Status: x64 lowering supports `break` / `continue` inside `while` loops; oretest ensures it builds for both targets, and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Status: x64 lowering supports `for var i = 0; i < N; i = i + 1 { ... }` with correct `continue` semantics (continue jumps to post); oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit code on real x86_64.
   - Status: x64 lowering supports `*` (imul) for `i32` with non-trivial RHS expressions (identifiers/calls/infix), not just integer literals; `OREN_REMOTE_RUN=1` validates exit code on real x86_64 (`x64_mul_expr_main.oren`).
   - Status: x64 lowering supports bitwise ops and shifts for `int`: `& | ^ << >>` (with `>>` as logical shift) (`x64_bit_shift_main.oren`).
   - Status: x64 lowering supports integer division and modulo: `/` and `%` (including negative cases; trunc-toward-zero) (`x64_div_mod_main.oren`, `x64_div_mod_neg_main.oren`).
   - Status: x64 fixtures now exercise variable shift counts (CL path) and computed divisors (non-trivial RHS) while keeping stable exit codes (helps catch encoder/lowering regressions early).
   - Status: x64 entry stub now aligns stack to 16 bytes to reduce ABI fragility as we add more calls/control flow.
   - Status: x64 lowering supports multiple functions and calls in expressions; oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit code on real x86_64.
   - Status: x64 lowering supports first-class function values (named function identifier in expression position → pointer to a `{code_ptr, env_ptr}` callable record; env=0 for now) and indirect calls (call through a local/param by loading `code_ptr`), including passing function pointers through parameters; oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Status: x64 lowering supports fixed i32 params/args via ABI registers (Win64: 4, SysV: 6) **and** stack args beyond the register limit (Win64: arg5+ on stack; SysV: arg7+ on stack). Oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Status: x64 stack-frame addressing now supports `disp32` for locals/temps/params (no 128-byte frame ceiling), enabling larger functions without fragile refactors.
   - Next: varargs (`...rest`) lowering + call wrappers (needs list packing/runtime parity).
   - Next: refactor native backend for code reuse via a shared NativeIR + per-target ABI tables (see `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`).
   - Status: started factoring ABI details into `lib/compiler/native_abi*.oren` (arg registers + Win64 shadow/call-area), consumed by x64 codegen.
   - Status: extracted callable semantics helpers (lambda capture + fnwrap/lambda wrappers) into `lib/compiler/native_callable.oren` (used by arm64 now; x64 can converge on it as runtime/list support lands).
   - Next: x64 Tier-1 parity for full first-class callables: converge from raw code pointers to the uniform callable object ABI (code_ptr + env_ptr, args_list-based) by compiling/injecting the native runtime callable layer (`lib/runtime_native/120_first_class_fn.oren`) and aligning with `native_callable.oren` wrappers (enables closures + varargs/spread + safe indirect calls).
   - Status: added oretest fixtures validating produced artifact formats via `file` (`native_x64_linux_format`, `native_x64_windows_format`).
   - Status: added an opt-in remote-run oretest smoke (Win11 cmd.exe + WSL2) behind `OREN_REMOTE_RUN=1` to validate actual stdout + exit code on real x86_64 (includes `div/mod`, `bit/shift`, `&&/||` short-circuit, compare-as-expression, `!` as expression, and stack-arg calling exitcode checks).
   - Status: remote-run harness now uses per-fixture remote subdirectories (safe to parallelize), captures Win `ERRORLEVEL` via delayed expansion (`cmd.exe /v:on` + `!ERRORLEVEL!`), and PE emitter now patches `rip_data_lea` (fixes first-class function value indirection crashes on Windows x64).
   - Status: documented the remote x86_64 dev environment access (Win11 cmd.exe + WSL2) in `docs/REMOTE_X64_ENV.md` (includes the exact `ssh -o 'proxycommand socat ...'` command and run/copy workflows).
   - Next: implement full x64 statement/expression lowering parity with arm64 backend (loops, locals, calls, ptr ops, lists, floats/SIMD).
   - Next: expand the remote-run gate (more fixtures; maybe include `capsule` mode on Linux x64) while keeping it opt-in.

2) **Container ops modernization (generic + dyn)** (S)
   - Status: documented the design in `docs/DESIGN_CONTAINER_OPS.md` (3-layer model: kernel `oren_*` intrinsics → std wrappers → language-level ops) including deterministic dispatch rules for generics + `dyn`.
   - Status: introduced `lib/std/list.oren` wrapper module (and kept it bytecode-safe by implementing `get/set/last` via indexing rather than `oren_list_get/set`).
   - Status: migrated several stdlib modules to `list.*` wrappers (`argparse`, `strings`, `json`, `cbor`, `buffer`, `math`, plus `std/linalg` list helpers).
   - Status: migrated remaining `lib/std/yaml.oren`, `lib/std/regex.oren`, and `lib/std/crypto/sha256.oren` off direct `oren_list_*` usage (now uses `std/list` wrappers: `list.push`, `list.len`).
   - Status: added an `oretest` audit to forbid direct `oren_list_*` usage in `lib/std/` (allowlist: `lib/std/list.oren` only).
   - Status: improved compiler-side kind inference for builtin container method sugar to treat `oren_bytes_from_string` / `oren_bytes_unpack` results as list-like (helps user code and small local patterns).
   - Status: standardized stdlib-internal imports to use the `std:` scheme (`import list "std:list"`, etc.) so prefixes are stable and separate compilation/linking stays deterministic.
   - Status: compiler now inlines hot `std:list` wrappers (`list.push`, `list.len`) directly to `oren_list_*` via the linker alias map (removes wrapper call overhead in tight loops without relying on best-effort `.push/.len` receiver inference).
   - Status: compiler recognizes rolling container-kind annotations (`: list|map|buf|string`) as hints for deterministic lowering of builtin container method sugar in native backends.
   - Status: added list cloning + slice APIs to `std:list` (`clone`, `slice_copy`, `slice_view`) and implemented `list_slice` iterable-map support in `oren_iter_next` across native/C/AVM backends.
   - Next: make container method sugar robust for non-local flows (params, map-derived values) without relying on best-effort local inference (or keep stdlib on wrappers and document the rule clearly); then extend surface (pop/clear/extend?).

3) **Backend architecture unification (CoreIR + canonical runtime ABI)** (L)
   - Status: added `docs/BACKEND_ARCHITECTURE.md` to define the SOLID layering and “one semantics, many backends” direction.
   - Status: updated `docs/ROADMAP.md` to treat x86_64 as Tier‑1 alongside arm64 (rolling), so platform goals match implementation reality.
   - Next: define a canonical **CoreIR** boundary and migrate closure/varargs/container-op lowering into it so C/native/bytecode all share semantics.
   - Next: converge all backends on the same callable model (`code_ptr + env_ptr`, `args_list` calling) and use wrappers only as an optimization layer.
   - Next: close parity gaps exposed by fixtures (keep deterministic bytecode codegen diagnostics stable; e.g. constructor arity mismatch via `tests/native/fixtures/bytecode_codegen_error.oren`).

4) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: intrinsic-level tail determinism tests added for `simd_dot_f32_ptr`, `simd_dot_f32_4_ptr`, and `simd_gemm_f32_4x4_ptr`; runtime now uses the single-pass microkernels.
   - DoD: broaden coverage (NaN/Inf/sign-bit edge cases, large `n`) and keep macOS+Linux parity for these intrinsics.

5) **HPC perf harness + linalg/math maturation** (M)
   - Status: initial matmul f32 benchmark harness exists under `tools/bench/` and now uses modern CLI forms.
   - DoD: expand bench coverage (dot/axpy/gemm variants), add result reporting, and validate SIMD kernels against a scalar reference for correctness + determinism.

6) **Self-hosting hardening (rolling stability gates)** (S)
   - Status: Stage0→Stage1→Stage2 pipeline exists and is exercised by `make test` (see `docs/SELF_HOSTING.md`).
   - Status: `oretest` parallelizes fixtures/native tests, logs the executed shell command into each fixture/test log, and preserves fixture artifacts on failure for debugging.
   - Next: define and freeze a “bootstrap subset” (syntax + stdlib surface) that Stage0 must support; treat changes as high-risk and gate them.

### P1 (Soon)

1) **Signed `.obc` + Root Trust (multiverse updates / “app store”)** (M)
   - Status: added rolling design doc `docs/APPSTORE_ROOTCA_AND_UPDATES.md`.
   - Status: added delegated signing cert-chain spec `docs/CERT_CHAIN_FORMAT.md` (`root → org → dev`).
   - Status: added `orensign` tool (`cmd/orensign/main.go`) for ed25519 keygen + `.obc` signing/verifying (keys live outside repo, recommended `../oren-ca/`).
   - Status: AVM supports signature verification (`--require-sig`, trusted root pubkeys) and cert-chain enforcement (`--require-cert-chain`).
   - Next: decide root-pubkey distribution/rotation strategy; then extend cert constraints (namespace/import allowlists), and port ed25519 verify to pure Oren where practical.

2) **Precompiled stdlib `.obc` linking (OBX) for AVM** (M)
   - Status: implemented OBX module metadata (exports + relocations) embedded as an unused `BYTES` constant in `.obc` (`docs/OBC_MODULE_LINKING.md`, `docs/AVM_SPEC.md`).
   - Status: added `--stdlib-mode obc --stdlib-obc <bundle>` to compile with extern `std:` imports and link a stdlib bundle into one output program.
   - Next: add multi-package linking via a formal search path (`OREN_PATH` / `--module-path`) and decide size/strip policy for OBX metadata in release builds.

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

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
- Maintenance / done-but-important:
  - Grammar modernization: repo-wide audit forbids legacy paren-forms like `if (...)` / `for (...)` in `.oren`.
  - Docs parity: keep `docs/LANGUAGE_SPEC.md` and `docs/LANGUAGE_MANUAL.md` aligned with `tests/**` and fixtures (rolling).
  - Include chunk coherence: keep large `.oren` and runtime hotspots split so files remain reviewable without context overflow (`docs/RUNTIME_NATIVE_LAYOUT.md`).
  - Compiler CLI/argparse: click-style behavior and shell completion exist; refine completions opportunistically (`docs/CLI_COMPLETION.md`).
  - ARM64 encoder audit: keep adding small clang-verified golden cases as new encoders are introduced.
