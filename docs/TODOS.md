## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total).
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
     - ✅ x64 map key-kind selection no longer relies on `key < 4096` for common non-literal keys (identifier int/string keys are inferred and plumbed)
     - ✅ x64 `Index` / `oren_index_set` now honor `recv_kind` hints from shared lowering to avoid dynamic LIST/MAP dispatch (still validates runtime magic; inferred-map requires deterministic `known_key_kind`)
     - ⏭️ next: fn+line mapping / source file mapping, fully remove remaining key-kind heuristics (tagged values or explicit key typing), richer `OREN_DIAG` parity with `lib/runtime_native/110_mem_diag.oren`, and closure perf (avoid per-call `args_list` allocations for common cases)

2) **Backend architecture unification (CoreIR boundary)** (L)
   - Define a canonical CoreIR that owns semantics (closures/varargs/container ops/short-circuit), and make backends thin adapters (ABI + emit only).
   - Start migration with “callables + varargs + spread” because they span C/native/bytecode.
   - Reference: `docs/BACKEND_ARCHITECTURE.md`.

3) **Container ops as operations (no hot-path stdlib overhead)** (M)
   - Make `xs[i]` / `xs[i]=v` / `len` / `push` lower to intrinsics for built-ins; keep generic + `dyn` story deterministic.
   - Define `clone`, `slice_copy`, and `slice_view` semantics and error conventions.
   - Reference: `docs/DESIGN_CONTAINER_OPS.md`, `docs/STDLIB_LAYERS.md`.

4) **Stack safety parity (deterministic recursion failure)** (M)
   - Keep one contract across AVM/C/native: deterministic abort under a configured depth budget (`--call-depth-max` / `OREN_CALL_DEPTH_MAX`).
   - Remaining work: mirror the same contract in x64 native as runtime injection lands.
   - Reference: `docs/STACK_SAFETY.md`.

5) **Stdlib modernization audit (grammar + intrinsics hygiene)** (S)
   - Keep `lib/std/**` on current grammar; keep `oren_*` calls confined to `std:*` wrappers where possible.
   - Expand `./oretest` audits carefully as grammar stabilizes.

6) **Tests: backend/arch neutral by default (integration-first)** (S)
   - Most `.oren` tests should be backend/arch neutral; keep ABI-specific tests isolated and minimal.
   - Reduce overlapping “atomic” tests in curated lists; prefer integration suites + fixtures as living spec.
   - Reference: `docs/TEST_SYSTEM.md`.

### P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)
   - Formalize cert chain constraints and root pubkey distribution/rotation; keep private keys outside the repo (`../oren-ca/`).
   - References: `docs/APPSTORE_ROOTCA_AND_UPDATES.md`, `docs/CERT_CHAIN_FORMAT.md`, `docs/CODESIGN.md`.

2) **Precompiled stdlib + OBX linking for AVM** (M)
   - Stabilize `.obc` library linking and a formal search path (`OREN_PATH` / `--module-path`) for release builds.
   - Reference: `docs/OBC_MODULE_LINKING.md`.

3) **HPC server performance + math/linalg maturation** (M)
   - Expand SIMD correctness coverage (NaN/Inf/sign-bit edges) + stable perf harness reporting.
   - References: `docs/HPC_SERVER_PLAN.md`, `docs/AVM_NEON_MAPPING_PLAN.md`.

### Recently Completed (Rolling)

- **Compiler int literals unified**: `lib/compiler/int_lit.oren` is the single source of truth for int literal parsing across optimizer/transpiler/native backends, including u64 bit-pattern literals (e.g. `9223372036854775808` → `i64_min`).
- **x86_64 native callables converge**: function values now point at `__oren_fnwrap_*` wrappers and indirect calls lower as `wrapper(env_ptr, args_list)`; `oren_panic` exists as a minimal deterministic abort for wrappers/invariants.
- **x86_64 native lambdas/closures converge**: lambda literals now lower to heap-allocated fnobj records with env capture lists, and lambda wrappers `__oren_lambda_*` implement the uniform call ABI.
- **x86_64 native panic contract converge (best-effort)**: `oren_panic(msg)` now emits a stable `OREN_DIAG kind=panic code=1 msg=<msg>` line (Linux+Win64) before aborting with exit code 1.
- **x86_64 native stack trace converge (best-effort)**: `oren_panic(msg)` now emits `STACK_TRACE` and up to 16 raw return addresses via RBP-walking (Linux+Win64) before aborting.
- **x86_64 native stack trace symbolication (best-effort)**: x64 native now embeds a symtab in the data blob and prints best-effort function names alongside return addresses (fixed-base ELF/PE).
- **x64 backend modularized for reviewability**: `lib/compiler/x64_native_program.oren` now uses `// @include` chunks under `lib/compiler/x64_native_program/` to avoid large-file context overflow while keeping namespace stability.
- **x64 re-entrant temp spilling**: x64 native v0 now sizes the `$tmp_intr*` spill pool per-function based on AST analysis (avoids large fixed stack frames while keeping nested calls/intrinsics correct).
- **ARM64 `/` semantics fixed for Tier‑1 parity**: `int / int` now lowers to `SDIV` (signed trunc-toward-zero) in the arm64 native backend; integration suite adds signed division asserts.
- **Arithmetic invalid cases standardized**: native backends now deterministically abort on div-by-zero / `i64_min / -1` and shift counts outside `0..63`, matching AVM and the C backend runtime.
- **Invalid arithmetic fixtures added**: `oretest` now exercises div0 / overflow / shift-oob panic behavior in the local native+C backends and ensures x64 ELF/PE builds exist for the same cases.
- **Container ops first milestone (arm64 native)**: list indexing `xs[i]` and index assignment `xs[i]=v` now lower to native code directly (no `oren_list_get` / `oren_index_set` call), with a deterministic fallback to `oren_map_get` / `oren_map_set` for non-list containers; `oren_index_set` runtime semantics now match the spec (lists do not auto-grow).
- **Container ops second milestone (arm64 native)**: `oren_list_len(xs)` and `oren_list_push(xs, v)` now use native fast-paths (len is fully inlined; push is inlined when `count < cap`, otherwise falls back to runtime growth).
- **Container ops third milestone (arm64 native)**: `std:list` namespace calls `list.len(xs)` / `list.push(xs, v)` now lower to the same intrinsics (no wrapper call overhead); `list.push` preserves std semantics by returning `nil`.
- **Whole-program function DCE (linker)**: module linking now prunes unreachable top-level functions for executable builds, so importing stdlib modules no longer forces tier‑1 native v0 backends to codegen unused helpers (e.g. `std:list.slice_view` string/map literals).
- **Test throughput**: `oretest` now runs runtime diagnostic fixtures in parallel (bounded by `--fixture-jobs`) to reduce wall time during rolling development.
- **oretest modularized**: the curated runner is split into `cmd/oretest/*.go` modules, and x86_64 validation was consolidated into an integration-first Tier‑1 smoke (local build existence + minimal opt-in remote-run).
- **HPC iteration performance**: `for x in iterable` no longer allocates a fresh `[ok, value]` pair on every iteration; the loop reuses a preallocated `out_pair` via `oren_iter_next(container, idx, out_pair)` across native/C/AVM, and the `Iterable` trait extension signature is updated to match.
- **Docs coverage**: `docs/LANGUAGE_MANUAL.md` now includes a “fixtures as living spec” index pointing at key `tests/native/fixtures` and x64 bring-up fixtures.
