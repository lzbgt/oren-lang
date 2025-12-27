## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total).
Older details live in `docs/TODOS_ARCHIVE.md` (and in git history).

### P0 (Now)

1) **Native backend Tier‑1: x86_64 (Linux ELF + Windows PE)** (L)
   - Goal: x86_64 (Linux+Windows) is Tier‑1 alongside arm64 (macOS/Linux) with consistent semantics across native/C/bytecode backends.
   - Next: converge callable ABI on the canonical `{code_ptr, env_ptr}` + `args_list` model (closures + safe indirect calls) across arm64/x64.
   - Next: varargs (`...rest`) lowering + spread semantics, including efficient list packing and tail-call-safe wrapper stubs.
   - Next: expand x64 parity for containers, pointers, floats/SIMD (keep fixtures small + deterministic; keep remote-run opt-in).
   - Next: implement x64 native runtime injection (allocator + strings + lists/maps) so x64 can run non-trivial stdlib code without host libc dependencies.
   - References: `docs/NATIVE_BACKEND.md`, `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`, `docs/REMOTE_X64_ENV.md`.

2) **Container ops modernization (generic + dyn)** (M)
   - Goal: ergonomic container operations (push/pop/len/get/set/slice) without stdlib call overhead in hot paths.
   - Direction: 3 layers — kernel intrinsics (`oren_*`) → std wrappers (`std:list`) → language-level sugar/operators.
   - Next: finish deterministic dispatch rules for generics + `dyn` and document the exact lowering contract.
   - Next: expand the native inlining fast-path beyond `xs[i]` / `xs[i]=v` (e.g. `len`, `push`) and port parity to the x64 native backend.
   - Next: treat `std:list` calls (`list.len`, `list.push`) as intrinsics too so idiomatic stdlib usage stays zero-overhead in native mode.
   - References: `docs/DESIGN_CONTAINER_OPS.md`, `docs/STDLIB_LAYERS.md`.

3) **Backend architecture unification (CoreIR boundary + canonical runtime ABI)** (L)
   - Goal: “one semantics, many backends”: move shared lowering (closures/varargs/container ops) into a shared CoreIR so bytecode/C/native stay consistent.
   - Next: define CoreIR schema + stability rules; migrate backends incrementally (start with callables + varargs).
   - References: `docs/BACKEND_ARCHITECTURE.md`.

4) **Stdlib modernization audit (grammar + intrinsics)** (S)
   - Goal: no legacy grammar in `lib/std/**` (if/else/match/for-in syntax, legacy helper names) and no direct `oren_list_*` usage outside `std:list`.
   - Status: `oretest` now enforces “no `oren_list_*` outside `lib/std/list.oren`” and “no `string_concat(...)` in stdlib”; expand checks cautiously as grammar evolves.

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
- **Invalid arithmetic fixtures added**: `oretest` now exercises div0 / overflow / shift-oob panic behavior in the local native+C backends and ensures x64 ELF/PE builds exist for the same cases.
- **Container ops first milestone (arm64 native)**: list indexing `xs[i]` and index assignment `xs[i]=v` now lower to native code directly (no `oren_list_get` / `oren_index_set` call), with a deterministic fallback to `oren_map_get` / `oren_map_set` for non-list containers; `oren_index_set` runtime semantics now match the spec (lists do not auto-grow).
- **Container ops second milestone (arm64 native)**: `oren_list_len(xs)` and `oren_list_push(xs, v)` now use native fast-paths (len is fully inlined; push is inlined when `count < cap`, otherwise falls back to runtime growth).
- **Container ops third milestone (arm64 native)**: `std:list` namespace calls `list.len(xs)` / `list.push(xs, v)` now lower to the same intrinsics (no wrapper call overhead); `list.push` preserves std semantics by returning `nil`.
- **Test throughput**: `oretest` now runs runtime diagnostic fixtures in parallel (bounded by `--fixture-jobs`) to reduce wall time during rolling development.
- **HPC iteration performance**: `for x in iterable` no longer allocates a fresh `[ok, value]` pair on every iteration; the loop reuses a preallocated `out_pair` via `oren_iter_next(container, idx, out_pair)` across native/C/AVM, and the `Iterable` trait extension signature is updated to match.
- **Docs coverage**: `docs/LANGUAGE_MANUAL.md` now includes a “fixtures as living spec” index pointing at key `tests/native/fixtures` and x64 bring-up fixtures.
