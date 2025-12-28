## Active Tracker (Succinct)

This file tracks the highest-priority active items in execution order.
Keep it succinct and actionable (typically ~10–20 items in total).
Older details live in `docs/TODOS_ARCHIVE.md` (and in git history).

### P0 (Now)

1) **Tier‑1 native backend: x86_64 (Linux ELF + Windows PE)** (L)
   - Converge x64 native with arm64 on **callables** (canonical `{code_ptr, env_ptr}` + `args_list`), runtime injection surface (strings/lists/maps), and deterministic failure contracts.
   - Remove all “key kind” heuristics (tagged values or explicit key typing at IR/runtime boundary).
   - Keep validation **integration-first**: local build smoke + opt-in remote run on Win11+WSL2 (`docs/REMOTE_X64_ENV.md`).
   - Status (rolling):
     - ✅ named function values + indirect calls now use `__oren_fnwrap_*` wrappers and an `args_list` call ABI (env is 0 in x64 v0)
     - ✅ x64 lambdas/closures now lower to heap fnobj `{code_ptr, env_ptr}` where `env_ptr` is a capture-by-value list (when captures exist)
     - ✅ `oren_panic(msg)` now emits a stable `OREN_DIAG kind=panic ...` line (best-effort) before aborting
     - ✅ `oren_panic(msg)` now emits a best-effort `STACK_TRACE` (RBP chain, up to 16 return addrs) on Linux+Win64 before aborting
     - ✅ x64 `STACK_TRACE` now symbolicates to best-effort function names **and offsets** via an embedded symtab (fixed-base emitters)
     - ✅ x64 map key-kind selection centralized in shared lowering: `known_key_kind` is inferred conservatively and required for map paths; x64 codegen does not re-infer from syntax (tagged values remain the full fix)
     - ✅ x64 `Index` / `oren_index_set` now honor `recv_kind` hints from shared lowering to avoid dynamic LIST/MAP dispatch (still validates runtime magic; inferred-map requires deterministic `known_key_kind`)
     - ✅ x64 deterministic call depth guard (rolling): function prologues/epilogues increment/decrement a counter and abort via `oren_panic("call depth exceeded")` when depth > max
     - ✅ x64 Linux ELF now uses RX text + RW data PT_LOAD segments (no RWX pages)
     - ✅ x64 Windows PE now uses `.text` (RX) + `.rdata` (R) + `.data` (RW) so mutable globals no longer force `.rdata` writable
     - ✅ x64 call depth max is configurable at build time via `oren build --call-depth-max <n>` (default 8192)
     - ⏭️ next: optionally support runtime env override (`OREN_CALL_DEPTH_MAX`) in the x64 entry stub (Linux + Windows) once env access is implemented
     - ⏭️ next: fn+line mapping / source file mapping, fully remove remaining key-kind heuristics (tagged values or explicit key typing), richer `OREN_DIAG` parity with `lib/runtime_native/110_mem_diag.oren`, and closure perf (avoid per-call `args_list` allocations for common cases)

2) **Backend architecture unification (CoreIR boundary)** (L)
   - Define a canonical CoreIR that owns semantics (closures/varargs/container ops/short-circuit), and make backends thin adapters (ABI + emit only).
   - Start migration with “callables + varargs + spread” because they span C/native/bytecode.
   - Unify “program termination” semantics across backends (what does `main` return mean vs `exit(code)`); keep deterministic contract for tooling/agents.
   - Decide and document a stable **evaluation order** (or an effect model) so optimizations are semantics-preserving across backends.
   - Reference: `docs/BACKEND_ARCHITECTURE.md`.

3) **Container ops as operations (no hot-path stdlib overhead)** (M)
   - Make `xs[i]` / `xs[i]=v` / `len` / `push` lower to intrinsics for built-ins; keep generic + `dyn` story deterministic.
   - Define `clone`, `slice_copy`, and `slice_view` semantics and error conventions.
   - Reference: `docs/DESIGN_CONTAINER_OPS.md`, `docs/STDLIB_LAYERS.md`.

4) **Stack safety parity (deterministic recursion failure)** (M)
   - Keep one contract across AVM/C/native: deterministic abort under a configured depth budget (`--call-depth-max` / `OREN_CALL_DEPTH_MAX`).
   - Remaining work: mirror the same contract in x64 native as runtime injection lands.
   - Reference: `docs/STACK_SAFETY.md`.

5) **Tail-call optimization (stackless recursion)** (S)
   - Direct self tail recursion lowers to a loop (no host stack growth); fixture enforces it.
   - Tail recursion modulo constant (`return f(..) + 1`) also lowers to a loop for a conservative subset; fixture enforces it.
   - Next: mutual tail recursion trampoline + varargs/spread tail calls once CoreIR callables converge.
   - Reference: `docs/STACK_SAFETY.md`.

6) **Stdlib modernization audit (grammar + intrinsics hygiene)** (S)
   - Keep `lib/std/**` on current grammar; keep `oren_*` calls confined to `std:*` wrappers where possible.
   - Expand `./oretest` audits carefully as grammar stabilizes.

7) **Tests: backend/arch neutral by default (integration-first)** (S)
   - Most `.oren` tests should be backend/arch neutral; keep ABI-specific tests isolated and minimal.
   - Reduce overlapping “atomic” tests in curated lists; prefer integration suites + fixtures as living spec.
   - Reference: `docs/TEST_SYSTEM.md`.
   - Rolling docs hygiene: when fixtures or backends change, update the docs that claim invariants (`docs/LANGUAGE_MANUAL.md`, `docs/NATIVE_BACKEND.md`, `docs/CLI_COMPLETION.md`) in the same change to avoid drift.
   - Spec hygiene (AI-friendly): keep `docs/LANGUAGE_SPEC.md` and `docs/LANGUAGE_MANUAL.md` aligned with actual compiler behavior and mark planned vs implemented explicitly.
   - Feature-index hygiene (AI-friendly): keep `docs/LANGUAGE_FEATURE_MATRIX.md` updated when feature status or implementation locations change.

8) **Compiler UX: “modern argparse” (Click-style subcommands + UX polish)** (M)
   - Keep current subcommand structure, but raise ergonomics to production level:
     - consistent error exit codes, `--json` outputs, stable env/flag precedence, structured diagnostics for tooling.
   - Reference: `docs/CLI_COMPLETION.md`, `docs/TEST_SYSTEM.md` (tool integration expectations).

9) **Stdlib distribution + module resolution (native + AVM)** (M)
   - One coherent story for:
     - `import math "std:math"` resolution for end users,
     - distribution (source vs precompiled `.obc` bundles),
     - AVM consuming the same stdlib (no host fs assumptions).
   - Reference: `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`, `docs/OBC_MODULE_LINKING.md`.

10) **Compiler-in-AVM (“compile inside the sandbox”)** (M)
   - Make `.oren → .obc` compilation runnable inside AVM deterministically with budgets and a locked capability surface.
   - Reference: `docs/AVM_SPEC_V1.md`, `docs/TOOLCHAIN_SELF_HOSTING.md`.

### P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)
   - Formalize cert chain constraints and root pubkey distribution/rotation; keep private keys outside the repo (`../oren-ca/`).
   - References: `docs/APPSTORE_ROOTCA_AND_UPDATES.md`, `docs/CERT_CHAIN_FORMAT.md`, `docs/CODESIGN.md`.

2) **Precompiled stdlib + OBX linking for AVM** (M)
   - Stabilize `.obc` library linking and a formal search path (`OREN_PATH` / `--module-path`) for release builds.
   - Reference: `docs/OBC_MODULE_LINKING.md`.

3) **HPC server performance + math/linalg maturation** (M)
   - Expand SIMD correctness coverage (NaN/Inf/sign-bit edges) + stable perf harness reporting.
   - Tier‑1 SIMD parity roadmap:
     - arm64: keep NEON fast paths deterministic and covered by `tests/native/test_simd_suite.oren`
     - x86_64: implement SIMD kernels with an SSE2 baseline (AVX2 optional) once x64 native reaches full semantic parity (no “fast-math” shortcuts); add a scalar-vs-SIMD parity suite on Linux+Windows.
   - References: `docs/HPC_SERVER_PLAN.md`, `docs/AVM_NEON_MAPPING_PLAN.md`.

4) **Toolchain self-hosting gates (fmt/pkg/test/LSP)** (M)
   - Keep Go bootstrap/tools canonical for now; add Oren-native tools behind explicit gates and promote only with reliability/perf acceptance tests.
   - Reference: `docs/TOOLCHAIN_SELF_HOSTING.md`.

### Recently Completed (Rolling)

- Tier‑1 x86_64 native bring-up: callable wrappers (`__oren_fnwrap_*` + uniform `args_list`) and a deterministic `oren_panic` contract (stable `OREN_DIAG` + best-effort `STACK_TRACE`) on Linux+Win64.
- Native x86_64 emit hygiene: ELF/PE segment permissions (no RWX), and call-depth guard (`--call-depth-max`) for deterministic recursion failure.
- C backend parity: user `fn main()` no longer collides with host `main`, and is auto-called after top-level statements.
- Tooling throughput: `oretest` is integration-first and parallel where safe (fixtures + opt-in remote x64 runs).

Rolling note: we avoid long “completed lists” here. If you need historical detail, use `docs/TODOS_ARCHIVE.md` and `git log`.
