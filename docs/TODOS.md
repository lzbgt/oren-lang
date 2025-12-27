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
   - Status: documented AVM startup anti-tamper limits + practical trust anchors in `docs/AVM_ANTITAMPER.md`.
   - Status: AVM now supports multiple trusted root pubkeys (root rotation) via a packed key list (repeatable `--trusted-pubkey-hex` / comma-separated `AVM_TRUSTED_PUBKEY_HEX`) and a configurable embedded root-key set.
   - Status: `make avm` now supports build-time embedding of trusted root **public keys** without editing repo files (generates `build/avm_root_pubkey.inc` via `tools/gen_avm_root_pubkeys_inc.sh`, sourcing keys from `AVM_EMBED_ROOT_PUBKEY_HEX` or `../oren-ca/avm_root_pubkeys.hex`).
   - Status: added `OREN_CERT\n2\n` with `allow_domains_mask` constraints (inherit-by-default) and AVM enforcement against bytecode `used_domains_mask` (prevents issuer policy bypass even if host allowlist is broader); added oretest regression.
   - Next: decide release root-pubkey distribution (what ships embedded vs passed via deployment), then expand cert constraints (namespace/import allowlists), and port ed25519 verify to pure Oren to reduce host-crypto dependency.
   - Next (security hardening): add an optional AVM “diagnostic self-hash” mode (corruption detection / telemetry, not a security promise) and explore codesigned release builds for AVM.

2) **Native backend x86_64 (Linux ELF + Windows PE)** (L) (Tier 1 target)
   - Status: added x64 native backend foundation (`--backend native --arch x64`) that can compile small programs end-to-end.
   - Status: aligned x64 naming with Tier‑1 intent (removed `_min` module naming; now `lib/compiler/codegen_x64.oren` + `lib/compiler/x64_native_program.oren`).
   - Status: added x64 comparison coverage for `<, <=, >, >=` (build fixtures + opt-in remote-run exit code).
   - Status: added x64 coverage for `else if` chains, `while <` loops, and negative signed comparisons (fixtures + build checks).
   - Status: added Linux x86_64 ELF emitter (`lib/compiler/x64_elf.oren`) and Windows PE32+ emitter with import table for `kernel32!ExitProcess` (`lib/compiler/x64_pe.oren`).
   - Status: Linux x64 now supports `print("...")` (string literal only) via direct `SYS_write` + RIP-relative string data; oretest asserts the string is embedded in the ELF output.
   - Status: Windows x64 now supports `print("...")` (string literal only) via `kernel32!GetStdHandle` + `kernel32!WriteFile`; oretest asserts the string is embedded in the PE output.
   - Status: x64 lowering supports local `var x = <int>` and `return x` (stack slot via RBP-relative addressing); oretest ensures it builds for both ELF+PE targets.
   - Status: x64 lowering supports `+` / `-` on i32 (`return x + 2`, `return 40 - x` style); oretest ensures it builds for both targets.
   - Status: x64 lowering supports `if <id|int> (==|!=) <id|int> { ... } else { ... }` with early returns; oretest ensures it builds for both targets.
   - Status: x64 lowering supports `while <id|int> (==|!=) <id|int> { ... }` plus assignment (`x = x + 1`) with local vars; oretest ensures it builds for both targets.
   - Status: x64 lowering supports `break` / `continue` inside `while` loops; oretest ensures it builds for both targets, and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Status: x64 lowering supports `for var i = 0; i < N; i = i + 1 { ... }` with correct `continue` semantics (continue jumps to post); oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit code on real x86_64.
   - Status: x64 lowering supports `*` (imul) for `i32` when RHS is an integer literal (`return x * 7`); `OREN_REMOTE_RUN=1` validates exit code on real x86_64.
   - Status: x64 entry stub now aligns stack to 16 bytes to reduce ABI fragility as we add more calls/control flow.
   - Status: x64 lowering supports multiple functions and calls in expressions; oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit code on real x86_64.
   - Status: x64 lowering supports first-class function values (named function identifier in expression position → pointer to a `{code_ptr, env_ptr}` callable record; env=0 for now) and indirect calls (call through a local/param by loading `code_ptr`), including passing function pointers through parameters; oretest builds both targets and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Status: x64 lowering now supports fixed i32 params/args via ABI registers:
     - Windows x64: up to 4 (`ecx, edx, r8d, r9d`)
     - Linux SysV: up to 6 (`edi, esi, edx, ecx, r8d, r9d`)
     Oretest builds both targets (cross-target fixtures use ≤4 because Win64 has only 4 integer arg registers), and `OREN_REMOTE_RUN=1` validates exit codes on real x86_64.
   - Next: varargs (`...rest`) lowering + call wrappers (needs list packing/runtime parity).
   - Next: refactor native backend for code reuse via a shared NativeIR + per-target ABI tables (see `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`).
   - Status: started factoring ABI details into `lib/compiler/native_abi*.oren` (arg registers + Win64 shadow/call-area), consumed by x64 codegen.
   - Status: extracted callable semantics helpers (lambda capture + fnwrap/lambda wrappers) into `lib/compiler/native_callable.oren` (used by arm64 now; x64 can converge on it as runtime/list support lands).
   - Next: x64 Tier-1 parity for full first-class callables: converge from raw code pointers to the uniform callable object ABI (code_ptr + env_ptr, args_list-based) by compiling/injecting the native runtime callable layer (`lib/runtime_native/120_first_class_fn.oren`) and aligning with `native_callable.oren` wrappers (enables closures + varargs/spread + safe indirect calls).
   - Status: added oretest fixtures validating produced artifact formats via `file` (`native_x64_linux_format`, `native_x64_windows_format`).
   - Status: added an opt-in remote-run oretest smoke (Win11 cmd.exe + WSL2) behind `OREN_REMOTE_RUN=1` to validate actual stdout + exit code on real x86_64.
   - Status: documented the remote x86_64 dev environment access (Win11 cmd.exe + WSL2) in `docs/REMOTE_X64_ENV.md` (includes the exact `ssh -o 'proxycommand socat ...'` command and run/copy workflows).
   - Next: implement full x64 statement/expression lowering parity with arm64 backend (loops, locals, calls, ptr ops, lists, floats/SIMD).
   - Next: expand the remote-run gate (more fixtures; maybe include `capsule` mode on Linux x64) while keeping it opt-in.

3) **Container ops modernization (generic + dyn)** (S)
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

4) **Precompiled stdlib `.obc` linking (OBX) for AVM** (M)
   - Status: implemented OBX module metadata (exports + relocations) embedded as an unused `BYTES` constant in `.obc` (`docs/OBC_MODULE_LINKING.md`, `docs/AVM_SPEC.md`).
   - Status: added `--obc-lib` to emit exports, and `--stdlib-mode obc --stdlib-obc <bundle>` to compile with extern `std:` imports and link the bundle into a single output program.
   - Status: added stdlib bundle root `lib/std/stdlib.oren` and stable std module prefixes (`STD_<path>_`) so symbols are deterministic for separate compilation.
   - Status: updated stdlib modules to import each other via `std:` so stable prefixes apply in practice (and not only when imported from outside stdlib).
   - Status: added a full-suite AVM smoke that compiles with `std:math` using only a stdlib bundle `.obc` (no std sources inside the child universe).
   - Next: add support for linking multiple non-stdlib packages via a formal search path (`OREN_PATH` / `--module-path`), and decide whether final `.obc` should strip OBX constants to reduce size.

5) **Include chunk coherence (overflow-proofing)** (M)
   - Status: large `.oren` and C runtime hotspots are split into include-chunks/modules; `oretest` enforces 2000-line caps and include-chunk coherence for `// @include` roots.
   - Status: documented the native runtime chunk layout and editing workflow in `docs/RUNTIME_NATIVE_LAYOUT.md`.
   - Next: keep new refactors chunk-safe (top-level boundaries only) so files stay reviewable without context overflow.

6) **Compiler CLI + argparse modernization (click-style)** (M)
   - Status: upgraded `lib/std/argparse.oren` to support `--opt=value`, `-abc` chained short flags, `-ovalue` short-value forms, interspersed options/positionals, and global options before subcommand.
   - Status: compiler driver now uses argparse to normalize argv, so the legacy driver logic accepts modern forms like `oren build --backend=native --out=... file.oren` without breaking existing `file first` invocations.
   - Status: added oretest regression to ensure equals-form flags + options-before-file keep working.
   - Status: removed remaining manual argv scanning in the compiler driver; options for `build/meta/dump` now come directly from parsed argparse results (less duplication, fewer edge cases).
   - Status: removed the remaining “normalize to legacy argv” layer; compiler now dispatches directly from argparse parse results (single source of truth).
   - Status: added click-style extras: `--no-<flag>` negation for bool flags, counted flags (`cmd_flag_count`, supports `-vvv`), required options (`cmd_option_required`), and `all_opts` merged view (`root_opts + opts`).
   - Status: added machine-readable `--help=json` output (also supports `-h=json` / `-hjson`) and oretest regressions.
   - Status: added global `--version` / `-V` (deterministic string) and oretest regression.
   - Status: added `oren completion bash|zsh` to emit minimal deterministic shell completion scripts (commands + option names) and oretest regressions.
   - Status: completion now suggests enum-like option values for key flags (`--backend`, `--target`, `--arch`, `--stdlib-mode`, plus `--help=json`).
   - Status: documented installation and scope in `docs/CLI_COMPLETION.md`.
   - Status: completion now suggests positional enums for `oren dump <kind>` and does basic file completion for common positionals (`build`/`emit-c`/`meta`/`dump`/`scan`).
   - Next: improve completion precision (filter to `*.oren`, complete `dump kind` only when it is the next positional even with interspersed options) without making the scripts brittle across shells.

7) **ARM64 instruction encoder audit** (S)
    - Status: added native golden-encoding coverage for key `arm64_core.oren` encoders (loads/stores, prologue/epilogue, add/sub imm+reg, B/BL/B.cond/BR/BLR, ADR/ADRP, broadcast/moves, basic SIMD ops, widening + pairwise ops).
    - Status: migrated native `adr_{data,code}` + Mach-O GOT stubs from ADR (±1MB) to ADRP+ADD (±4GB) and added `oretest` audits to enforce 2-slot reservation (compiler fixups + debug hook + Mach-O GOT stubs).
    - Status: expanded golden coverage to include basic atomic encoders (LDAXR/STLXR/CLREX/LDADD/CAS/STRB) with clang-verified constants.
    - Status: added clang-verified goldens for basic integer loads/stores (LDR/STR X, LDRB W).
    - Status: included `tests/native/test_arm64_encoding.oren` in the curated native suite so these goldens run on every `make test`.
    - Status: expanded goldens to cover SP-relative scaled loads/stores (LDR/STR [SP,#imm12<<3]).
    - Status: added parameterized pair load/store encoders (STP pre-index, LDP post-index) with clang-verified goldens for stack save/restore patterns.
    - Next: add more golden cases for pair loads/stores and keep them small/deterministic (use clang/otool to confirm encodings).

### P1 (Soon)

1) **Backend architecture unification (CoreIR + canonical runtime ABI)** (L)
   - Status: added `docs/BACKEND_ARCHITECTURE.md` to define the SOLID layering and “one semantics, many backends” direction.
   - Status: updated `docs/ROADMAP.md` to treat x86_64 as Tier‑1 alongside arm64 (rolling), so platform goals match implementation reality.
   - Status: updated `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md` to clarify Win64’s 4 integer arg registers is a platform ABI fact (not an Oren limitation).
   - Next: define a canonical **CoreIR** boundary and migrate closure/varargs/container-op lowering into it so C/native/bytecode all share semantics.
   - Next: converge all backends on the same callable model (`code_ptr + env_ptr`, `args_list` calling) and use wrappers only as an optimization layer.

2) **SIMD intrinsic tail + microkernel correctness** (M)
   - Status: intrinsic-level tail determinism tests added for `simd_dot_f32_ptr`, `simd_dot_f32_4_ptr`, and `simd_gemm_f32_4x4_ptr`; runtime now uses the single-pass microkernels.
   - Status: added NaN/Inf edge-case coverage for `simd_dot_f32_ptr` (native) ensuring Inf stays Inf (bit-stable) and NaN propagates as NaN (checked by NaN-ness, not payload).
   - Status: added NaN/Inf edge-case coverage for `simd_dot_f32_4_ptr` (native) to ensure lane-local Inf and NaN propagate deterministically.
   - Status: added large-`n` intrinsic determinism coverage for `simd_dot_f32_ptr` (`n=4097`) to exercise long accumulation paths + tail handling.
   - Status: added large-`n` intrinsic determinism coverage for `simd_dot_f32_4_ptr` (`n=4097`) to exercise multi-output dot paths + tail handling.
   - Status: added large-`n` intrinsic determinism coverage for `simd_gemm_f32_4x4_ptr` (`n=1025`) to exercise long 4x4 GEMM accumulation paths + tail handling.
   - Status: added NaN/Inf edge-case coverage for `simd_gemm_f32_4x4_ptr` (native) to ensure per-row NaN propagation and Inf stability are deterministic.
   - DoD: broaden coverage (NaN/Inf/sign-bit edge cases, large `n`) and keep macOS+Linux parity for these intrinsics.

3) **Repo-wide grammar modernization + audits** (L)
   - Status: repo scans show no remaining `.oren` uses of legacy paren-forms (`if (...)`, `while (...)`, `for (...)`, `match (...)`, `switch (...)`); `oretest` blocks regressions.
   - Next: keep the allowlist tiny and explicit; add a targeted rule only when a new legacy pattern is discovered in `docs/` or via a regression.

4) **Native networking hardening** (M)
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

5) **Docs parity pass** (S)
   - Status: fixed `docs/LANGUAGE_SPEC.md` to include `%` (modulo) in the infix operator grammar + precedence list (matches the compiler’s token set).
   - Status: updated `docs/LANGUAGE_SPEC.md` EBNF to include `for <name>[:Type] in <expr> { ... }` iterator sugar (matches the parser implementation).
   - Status: updated `docs/LANGUAGE_MANUAL.md` examples to avoid legacy `if (...)` statement form.
   - Status: documented capsule runtime policy env vars (FS/NET/PROC/ENV gates and mount lists) in `docs/LANGUAGE_MANUAL.md` so fixture-driven behavior is discoverable.
   - Status: expanded `docs/LANGUAGE_MANUAL.md` with rolling features exercised by fixtures/tests: generics (`fn f[T]` + explicit specialization), trait method sugar + qualified calls, blanket `impl ... for any`, strict attributes mode, and capsule mode (`@cap.requires` + `--capsule`).
   - Status: documented `switch` and `enum` sugar in `docs/LANGUAGE_MANUAL.md` (both are exercised by `tests/modules/test_switch.oren`, `tests/modules/test_enum.oren`, and `tests/modules/test_match_enum.oren`).
   - Status: documented varargs (`fn f(...rest)`) and call-site spread (`f(xs...)`), plus `oren_join`/`oren_join_timeout`, in `docs/LANGUAGE_MANUAL.md` (exercised by `tests/modules/test_varargs.oren`, `tests/native/test_integration_suite.oren`, and `tests/modules/test_spawn_join_timeout.oren`).
   - Status: documented `break`/`continue` loop semantics, `ffi symbol` declarations, and `class` (rolling legacy) in `docs/LANGUAGE_MANUAL.md` (exercised by `tests/native/test_for_break_continue.oren`, `tests/avm/test_for_break_continue.oren`, `tests/native/ffi.oren`, and `tests/modules/shapes.oren`).
   - Status: refreshed repo `AGENTS.md` with clearer rolling workflow rules (verification policy, large-file strategy, web research capture, secret handling).
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

6) **HPC perf harness + linalg/math maturation** (M)
   - Status: initial matmul f32 benchmark harness exists under `tools/bench/` and now uses modern CLI forms.
   - DoD: expand bench coverage (dot/axpy/gemm variants), add result reporting, and validate SIMD kernels against a scalar reference for correctness + determinism.

7) **Self-hosting hardening (rolling stability gates)** (S)
   - Status: Stage0→Stage1→Stage2 pipeline exists and is exercised by `make test` (see `docs/SELF_HOSTING.md`).
   - Status: Stage0 bootstrap transpiler now resolves `std:` imports (keeps the language/compiler evolution path unblocked).
   - Status: Stage0 bootstrap lexer now supports modern numeric literals (`0x`/`0b`/`0o`, `_` separators, scientific notation) to avoid bootstrap breakage when Stage1 sources use them.
   - Status: Stage0 bootstrap parser now supports `else if` chains (lowered to `else { if ... }` internally); oretest covers it via a `./oren_bootstrap` fixture.
   - Status: `oretest` has a deterministic self-hosting gate (enabled via `--full` or `--selfhost`): Stage1 emits Stage2 compiler as `.obc`, then Stage2 reproduces Stage1 `dump graph` + `meta --deterministic` outputs (hash-checked).
   - Status: `oretest` now parallelizes fixtures (`--fixture-jobs`) and native tests (`--native-jobs`) to reduce `make test` wall time.
   - Status: `make test-native-all` now supports parallel builds via `NATIVE_TEST_JOBS=...` and per-test logs (`build/logs/native_all_*.log`).
   - Status: `make selfhost` target added; `OREN_TEST_SELFHOST=1 make test` now passes `--selfhost` through to `oretest`.
   - Status: native backend can now build the compiler itself: `./oren build oren.oren --backend native --target macos -o build/oren_stage2_native` (required native runtime subset filled: `oren_string_to_float_bits`, `oren_sha256_range`, `oren_chmod`, `oren_env`).
   - Status: native self-host gate validates that the Stage2 native compiler binary is buildable + runs `selftest-native` (fast runtime surface check; no compiler pipelines), because Stage2(native) `dump graph` / `meta` are still too slow to be a reliable CI gate.
   - Status: bytecode backend now rejects assignment to undeclared vars deterministically (aligns native/bytecode semantics; prevents AVM verifier stack mismatches).
    - Next: define and freeze a “bootstrap subset” (syntax + stdlib surface) that Stage0 must support; treat changes as high-risk and gate them.
    - Next: fix Stage1→Stage2 C-backend rebuild OOM risk (clang compiling a giant single-TU generated C file can be SIGKILL on dev machines); likely needs multi-TU emission or smaller generated C.
   - Next: expand `oren selftest-native` coverage (map/string/sha256/env/args) as runtime primitives stabilize; then re-enable `meta --deterministic` (and eventually `dump graph`) behind env toggles once performance is acceptable.
   - Next: optimize `oren_sha256_range` hot path (it can dominate wall time during native builds); consider a typed-buffer implementation and/or a microkernel-assisted path while preserving determinism.

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
