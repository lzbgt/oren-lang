## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total).
Older details live in `docs/TODOS_ARCHIVE.md` (and in git history).

### P0 (Now)

1) **Native backend Tier‑1: x86_64 (Linux ELF + Windows PE)** (L)
   - Goal: x86_64 (Linux+Windows) is Tier‑1 alongside arm64 (macOS/Linux) with consistent semantics across native/C/bytecode backends.
   - Status: x64 bring-up now includes syscall/WinAPI-backed `malloc`/`malloc_raw` + `ptr_get`/`ptr_set` (qword + byte) intrinsics, minimal list intrinsics (`oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_list_set`), list literal `[a,b,c]` (lowered via direct buffer fill so nested literals like `[0,1,[0,0]]` are correct), list index sugar (`xs[i]`, `xs[i]=v` via `oren_index_set`), `for x in xs {}` via `oren_iter_next(container, idx, out_pair) -> [ok, value]`, stdlib-style namespace calls (`import list "std:list"; list.len/list.push`), `"string literal"` values as raw pointers (usable with `ptr_get_byte`/`iadd`), plus native-layout-compatible map intrinsics (`oren_new_map`, `oren_map_len`, `oren_map_get`, `oren_map_set`), map literal `{ "k": v }` and nested map literal `{ "a": {"b": 7} }`, map indexing `m[key]`, and map index assignment `m[key]=v` with literal key-kind emission (Integer/String literals set kind explicitly; dynamic keys still fall back to the v0 heuristic `key < 4096 => int`, else C-string pointer). x64 arg spilling is now re-entrant (intrinsics + nested call args) via a per-function `$tmp_intr*` temp pool, guarded by fixtures including `tests/fixtures/x64_nested_map_literal_main.oren`, `tests/fixtures/x64_intr_reentrancy_main.oren`, and `tests/fixtures/x64_nested_call_args_main.oren` (remote-run on Win11+WSL2).
   - Next: converge callable ABI on the canonical `{code_ptr, env_ptr}` + `args_list` model (closures + safe indirect calls) across arm64/x64.
   - Next: enable the native self-hosting gate on Linux x86_64 CI (build+run stage2 via x64 backend) once the syscall-first runtime surface is sufficient.
   - Next: varargs (`...rest`) + spread semantics convergence across backends (x64 now supports named varargs calls and fixed-arity call-site spread with runtime length checks; see `tests/fixtures/x64_varargs_main.oren` and `tests/fixtures/x64_spread_fixed_arity_main.oren`; still missing varargs+spread and indirect-call spread).
   - Next: expand x64 parity for containers, pointers, floats/SIMD (keep fixtures small + deterministic; keep remote-run opt-in).
   - Next: implement tagged value representation (or boxed ints) so x64 supports full-range int keys/values (remove the `<4096` heuristic) and can align map key types with AVM (nil/bool/int/string) safely.
     - Design: `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md` (staged plan; remove heuristics first, then converge native value model).
   - Next: implement x64 native runtime injection (allocator + strings + lists/maps) so x64 can run non-trivial stdlib code without host libc dependencies.
   - References: `docs/NATIVE_BACKEND.md`, `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`, `docs/REMOTE_X64_ENV.md` (includes the canonical SSH ProxyCommand snippet).

2) **Container ops modernization (generic + dyn)** (M)
   - Goal: ergonomic container operations (push/pop/len/get/set/slice) without stdlib call overhead in hot paths.
   - Direction: 3 layers — kernel intrinsics (`oren_*`) → std wrappers (`std:list`) → language-level sugar/operators.
   - Next: finish deterministic dispatch rules for generics + `dyn` and document the exact lowering contract.
   - Status: x64 Tier‑1 now supports list literals (`[a,b,c]`), list indexing (`xs[i]`), index assignment (`xs[i]=v`), builtin container method sugar (`xs.len()`, `xs.push(v)`, `xs.get(i)`), and stdlib namespace wrappers (`list.len(xs)`, `list.push(xs, v)`) lowering to intrinsics.
   - Next: expand the native inlining fast-path beyond `xs[i]` / `xs[i]=v` (e.g. `len`, `push`) and port parity to the x64 native backend.
   - Next: define `slice_view` and error-return conventions so slice helpers can remain usable in native mode without forcing backends to support full map/string literal semantics on day 1.
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
- **x64 re-entrant temp spilling**: x64 native v0 now sizes the `$tmp_intr*` spill pool per-function based on AST analysis (avoids large fixed stack frames while keeping nested calls/intrinsics correct).
- **ARM64 `/` semantics fixed for Tier‑1 parity**: `int / int` now lowers to `SDIV` (signed trunc-toward-zero) in the arm64 native backend; integration suite adds signed division asserts.
- **Arithmetic invalid cases standardized**: native backends now deterministically abort on div-by-zero / `i64_min / -1` and shift counts outside `0..63`, matching AVM and the C backend runtime.
- **Invalid arithmetic fixtures added**: `oretest` now exercises div0 / overflow / shift-oob panic behavior in the local native+C backends and ensures x64 ELF/PE builds exist for the same cases.
- **Container ops first milestone (arm64 native)**: list indexing `xs[i]` and index assignment `xs[i]=v` now lower to native code directly (no `oren_list_get` / `oren_index_set` call), with a deterministic fallback to `oren_map_get` / `oren_map_set` for non-list containers; `oren_index_set` runtime semantics now match the spec (lists do not auto-grow).
- **Container ops second milestone (arm64 native)**: `oren_list_len(xs)` and `oren_list_push(xs, v)` now use native fast-paths (len is fully inlined; push is inlined when `count < cap`, otherwise falls back to runtime growth).
- **Container ops third milestone (arm64 native)**: `std:list` namespace calls `list.len(xs)` / `list.push(xs, v)` now lower to the same intrinsics (no wrapper call overhead); `list.push` preserves std semantics by returning `nil`.
- **Whole-program function DCE (linker)**: module linking now prunes unreachable top-level functions for executable builds, so importing stdlib modules no longer forces tier‑1 native v0 backends to codegen unused helpers (e.g. `std:list.slice_view` string/map literals).
- **Test throughput**: `oretest` now runs runtime diagnostic fixtures in parallel (bounded by `--fixture-jobs`) to reduce wall time during rolling development.
- **HPC iteration performance**: `for x in iterable` no longer allocates a fresh `[ok, value]` pair on every iteration; the loop reuses a preallocated `out_pair` via `oren_iter_next(container, idx, out_pair)` across native/C/AVM, and the `Iterable` trait extension signature is updated to match.
- **Docs coverage**: `docs/LANGUAGE_MANUAL.md` now includes a “fixtures as living spec” index pointing at key `tests/native/fixtures` and x64 bring-up fixtures.
