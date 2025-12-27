## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total).
Older details live in `docs/TODOS_ARCHIVE.md` (and in git history).

### P0 (Now)

1) **Native backend Tier‑1: x86_64 (Linux ELF + Windows PE)** (L)
   - Goal: x86_64 (Linux+Windows) is Tier‑1 alongside arm64 (macOS/Linux) with consistent semantics across native/C/bytecode backends.
   - Next: converge callable ABI on the canonical `{code_ptr, env_ptr}` + `args_list` model (closures + safe indirect calls) across arm64/x64.
   - Next: varargs (`...rest`) lowering + spread semantics, including efficient list packing and tail-call-safe wrapper stubs.
   - Next: add native fixtures for invalid arithmetic aborts (`/0`, `i64_min/-1`, `1<<64`) so regressions are caught outside AVM.
   - Next: expand x64 parity for containers, pointers, floats/SIMD (keep fixtures small + deterministic; keep remote-run opt-in).
   - References: `docs/NATIVE_BACKEND.md`, `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`, `docs/REMOTE_X64_ENV.md`.

2) **Container ops modernization (generic + dyn)** (M)
   - Goal: ergonomic container operations (push/pop/len/get/set/slice) without stdlib call overhead in hot paths.
   - Direction: 3 layers — kernel intrinsics (`oren_*`) → std wrappers (`std:list`) → language-level sugar/operators.
   - Next: finish deterministic dispatch rules for generics + `dyn` and document the exact lowering contract.
   - References: `docs/DESIGN_CONTAINER_OPS.md`, `docs/STDLIB_LAYERS.md`.

3) **Backend architecture unification (CoreIR boundary + canonical runtime ABI)** (L)
   - Goal: “one semantics, many backends”: move shared lowering (closures/varargs/container ops) into a shared CoreIR so bytecode/C/native stay consistent.
   - Next: define CoreIR schema + stability rules; migrate backends incrementally (start with callables + varargs).
   - References: `docs/BACKEND_ARCHITECTURE.md`.

4) **Stdlib modernization audit (grammar + intrinsics)** (S)
   - Goal: no legacy grammar in `lib/std/**` (if/else/match/for-in syntax, legacy helper names) and no direct `oren_list_*` usage outside `std:list`.
   - Next: add/extend repo-wide audits in `oretest` to keep this enforced as the grammar evolves.

5) **Runtime native modularization (avoid “single huge file”)** (M)
   - Goal: keep native runtime sources reviewable and module-scoped (prevents context/merge pain).
   - Next: follow `docs/RUNTIME_NATIVE_LAYOUT.md` and split large runtime layers into cohesive modules with minimal cross-imports.

### P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)
   - Next: nail down root-pubkey distribution/rotation and cert constraints (namespace/import allowlists).
   - References: `docs/APPSTORE_ROOTCA_AND_UPDATES.md`, `docs/CERT_CHAIN_FORMAT.md`, `docs/CODESIGN.md`.

2) **Precompiled stdlib `.obc` linking (OBX) for AVM** (M)
   - Next: multi-package linking via a formal search path (`OREN_PATH` / `--module-path`) and strip policy for release builds.
   - References: `docs/OBC_MODULE_LINKING.md`.

3) **HPC server performance + math/linalg maturation** (M)
   - Next: expand correctness coverage for SIMD kernels (NaN/Inf/sign-bit edges), add stable perf harness reporting.
   - References: `docs/HPC_SERVER_PLAN.md`, `docs/AVM_NEON_MAPPING_PLAN.md`.

### Recently Completed (Rolling)

- **Compiler int literals unified**: `lib/compiler/int_lit.oren` is the single source of truth for int literal parsing across optimizer/transpiler/native backends, including u64 bit-pattern literals (e.g. `9223372036854775808` → `i64_min`).
- **x64 backend modularized for reviewability**: `lib/compiler/x64_native_program.oren` now uses `// @include` chunks under `lib/compiler/x64_native_program/` to avoid large-file context overflow while keeping namespace stability.
- **ARM64 `/` semantics fixed for Tier‑1 parity**: `int / int` now lowers to `SDIV` (signed trunc-toward-zero) in the arm64 native backend; integration suite adds signed division asserts.
- **Arithmetic invalid cases standardized**: native backends now deterministically abort on div-by-zero / `i64_min / -1` and shift counts outside `0..63`, matching AVM and the C backend runtime.
