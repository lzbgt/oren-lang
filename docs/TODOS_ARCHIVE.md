# Archived TODOs

This file preserves the previous long-form rolling TODO list (history + detailed status).

- Archived on: 2025-12-18
- Current prioritized TODOs live in: `docs/TODOS.md`

## Archived (2026-01-04) — Native: Tier‑1 stack traces (x64) + varargs wrapper recursion fix (arm64)

- x86_64 native (Win11 Tier‑1 / rtobj cache mode):
  - Added an embedded debug-info table (function-range map) emitted into the program `.data` blob.
  - x64 entry stub now calls `oren_set_debug_info(table_ptr, table_ptr)` (fixed-base v0 emitters) so runtime symbolication can use it.
  - Runtime `stack_trace()` now prefers `oren_resolve_symbol(pc)` (debug-info) and falls back to the best-effort backend intrinsic when missing.
  - Tier‑1 fixture now asserts symbolication by checking `oren_resolve_symbol(lr) != "???"`.
- arm64 native:
  - Fixed a correctness bug where varargs named functions could recurse indefinitely:
    - call lowering for varargs named functions lowered through `__oren_fnwrap_*` wrappers,
    - but wrapper bodies call the real varargs function, which previously re-entered varargs lowering.
  - Added `ctx["cur_fn_name"]` tracking during function codegen and skipped varargs “callable-object” lowering when `cur_fn_name == "__oren_fnwrap_" + fn_name`.
  - Also recorded synthesized type constructors in `ctx["func_arity"]` / `ctx["func_decl_order"]` so constructor values are first-class (`var U = User`).
- Verified:
  - `make test`
  - local: `./oren build tests/fixtures/tier1_native_smoke_main.oren --backend native --platform arm64-macos --debug ...` (runs OK)
  - remote: `./scripts/verify_native_matrix.sh --targets x64-win-tier1` (stage1 + stage2)

## Archived (2026-01-04) — Native: x64-linux Tier‑1 spawn/join unblocked (WSL2) + matrix script hardening

- Symptom (remote WSL2 x86_64, Tier‑1 fixture):
  - Output stopped at `tier1 spawn begin` / `tier1 lock before spawn ...` and returned early.
  - `scripts/verify_native_matrix.sh` previously printed `EXIT=...` but still returned success because the remote wrappers did not propagate the program exit code.
- Root cause:
  - The historical x86_64 `sys_pipe` intrinsic widened the two 32-bit fds in-place and (rolling bug) could clobber the syscall rc register with a non-zero scratch value, triggering false failures.
  - This could be masked locally by the runtime object cache: even after codegen was fixed, an old cached runtime object could keep the buggy machine code alive.
- Fix (backend + cache hygiene):
  - Keep strict runtime checks (`sys_pipe(...) != 0` fails) and invalidate cached runtime objects by bumping the x64 runtime-object backend signature.
- Fix (verification script hardening):
  - `scripts/verify_native_matrix.sh` now preserves true remote exit codes:
    - Win11: uses `set RC=!ERRORLEVEL! ... exit /b !RC!`
    - WSL2: captures `rc=$?` and `exit $rc` after printing `EXIT=$rc`
  - WSL2 Tier‑1 runs additionally require output markers (prevents “exit 0 but incomplete output” false positives):
    - `tier1 spawn join ok`
    - `tier1 proc ok`
- Verified:
  - `./scripts/verify_native_matrix.sh --targets x64-wsl-tier1` (stage1 + stage2) passes and prints full Tier‑1 progress through spawn/join and proc.

## Archived (2026-01-04) — Native: pruned runtime astbin cache stability (g_target_os) + v2 encode guardrails

- Runtime OS pruning became meaningfully effective (native backend throughput):
  - Fixed platform pruning to handle runtime top-level shapes and control-flow-as-expression:
    - runtime-tagged `ExprStmt` wrapping `Function`
    - `ExprStmt` wrapping expression `If`
  - Added bounded tracer:
    - `OREN_TRACE_RUNTIME_OS_PRUNE=1` prints one summary line (`[pprune] ... before=... after=...`).
- Runtime bundle cache policy tightened (avoid “cache hit but still unpruned”):
  - Pruning now records a cheap marker on the program:
    - `__oren_pruned_target_os_id`
    - `__oren_pruned_target_os_kind="g_target_os"`
  - The runtime bundle loader skips redundant pruning when the marker matches the target.
  - If the cache file is supposed to be pruned (`*_pruned2.astbin`) but is missing the marker or still contains prunable branches,
    the loader does a best-effort rewrite once (decode → prune → re-encode) so subsequent runs decode less.
- astbin v2 encoder guardrail (large ASTs):
  - Added a heuristic pre-sizing step for the v2 string pool index map when encoding large Program ASTs (based on statement count).
  - Purpose: avoid repeated hash-table rebuilds inside `oren_map_set_str_unchecked` during string pool collection (can dominate stage2-native cache writes).
- String literals vs GC (native runtime correctness/perf):
  - `oren_intern_cstr` now returns already-classified string literals unchanged (does not copy literals into the GC heap).
  - Rooted `g_intern_cstr_cache` (map) so it cannot be reclaimed by a collection (native GC scans stacks, not arbitrary globals yet).
- Evidence (arm64-macos, stage2 compiler, `./scripts/bench_native_compile_one_file.sh --no-debug`):
  - runtime bundle cache decode (pruned2): ~`2.8s` after cache rewrite/marker is present
  - rtobj miss: ~`13s`
  - rtobj hit: ~`3.6s` (still under the `<4s` gate)

## Archived (2026-01-04) — Tooling: bounded build timing summary (no huge logs)

- Compiler:
  - Added a bounded build-phase timing summary for diagnosing “native build took >10s” regressions without dumping huge trace logs:
    - `OREN_TRACE_BUILD_SUMMARY=1` prints a single `[build] summary ...` line per `oren build` (native backend path).
    - `OREN_TRACE_BUILD_SLOW_MS=<n>` only prints the summary if the total build time is at least `<n>` ms.
- Docs:
  - `docs/BUILD_AND_VERIFY.md` documents the knobs.

## Archived (2026-01-04) — Tooling: build cache key compute bounded (native stage2)

- Problem:
  - Stage2-native `oren build` can appear “hung” before compilation if build-cache key computation is slow.
  - Root cause was injected runtime hashing (`lib/runtime_native.oren` include-closure) being re-walked every run, and scan-cache writes using O(n²) string concatenation.
- Fixes (rolling):
  - Build cache now persists the scan cache **after** injected-runtime hashing, so subsequent builds reuse `build/cache/scan_cache_v3.txt` records.
  - Scan cache serialization now writes via a `u8_buf` builder + `oren_write_bytes`, avoiding O(n²) `out = out + ...` concatenation in hot tooling paths.
  - Rolling build-cache compiler signature is now stat-based (path+size+mtime) to avoid hashing the full `./oren_stage2` binary on every build.
  - Native runtime `oren_file_stat_size_mtime_ns` now uses a bounded scratch stat buffer and avoids allocating a resolve-pair in non-capsule mode.
- Evidence (arm64-macos, stage2 compiler):
  - With `OREN_TRACE_BUILD=1`, `[build] cache key compute` drops from multi-second to ~O(100ms) on a warm scan cache, and `[cache] injected_runtime_hash` becomes ~O(10ms).

## Archived (2026-01-04) — Native: rtobj seed fallback (fast first-run builds)

- Problem:
  - Even with caching, a true rtobj miss (empty cache dir) can cost ~20s on arm64-macos because it has to decode the runtime astbin and compile hundreds of runtime decls.
  - This is especially painful in ephemeral environments (CI) or when users isolate cache dirs.
- Fix (rolling, sysroot-like behavior):
  - Added an **optional rtobj seed directory** (`build/cache/native_runtime_obj_seed/` by default).
  - On rtobj cache miss, the compiler attempts to load a matching seed entry and (if found) copies the raw bytes into the active cache dir (without re-encoding meta).
  - Added tooling to generate/update the seed from an existing cache entry:
    - `make rtobj-seed`
    - `./scripts/build_rtobj_seed.sh`
- Notes:
  - The benchmark script disables the seed fallback so it still measures true miss→hit.

## Archived (2026-01-04) — Native: stage2 hot-path perf (byte emit + astbin decode)

- Native backend emit (arm64 + x86_64):
  - Added bulk little-endian append helpers in `lib/compiler/bytes_builder.oren`:
    - `bytes_push_u16_le`, `bytes_push_u32_le`, `bytes_push_u64_le` (single growth check + raw byte stores).
  - Switched the native emitters to use the shared builder fast paths:
    - `lib/compiler/arm64_core.oren`: `push_u32_le`, `push_u64_le`
    - `lib/compiler/x64_core.oren`: `push_u16_le`, `push_u32_le`, `push_u64_le`
  - arm64 Mach-O emission:
    - `lib/compiler/arm64_macho.oren` now extends zero-filled regions with a bounded bulk helper (`bytes_extend_zeros`) instead of per-byte loops.
    - avoids `oren_bytes_from_string(name)` allocations while building the string table by reading string bytes directly.
- astbin decode (stage2-native runtime injection):
  - Reworked hot decode loops in `lib/compiler/compiler/015_astbin.oren` to use intrinsic integer addition (`iadd`) instead of overloaded `+` in tight loops.
  - Also added a u8_buf fast path that reads from a pre-materialized `data_ptr` via `ptr_get_byte(iadd(data_ptr, off))` to avoid repeated header loads.
- Evidence (arm64-macos, stage2 compiler; isolated rtobj cache dir; `examples/hello.oren`, `--no-cache --no-debug`):
  - runtime bundle astbin decode (`~3.2MB`): ~`10.6s` → ~`6.1s` (still too high for cold-path timeouts)
  - rtobj meta decode (cache hit): ~`720ms` → ~`405ms`
  - “compile one file” total:
    - rtobj hit: ~`3.1–3.4s` (meets the `<4s` gate)
    - rtobj miss: ~`21s` (active work item; see `docs/TODOS.md`)

## Archived (2026-01-03) — Native: OrenStatV0 time fields + stat-aware scan cache v3

- Native backends:
  - `sys_stat/sys_lstat/sys_fstat` now populate the Oren-owned cross-platform `OrenStatV0` time fields:
    - `atime_ns`, `mtime_ns`, `ctime_ns` (ns since Unix epoch; best-effort per OS).
  - Offsets for host `struct stat` time fields are recorded as **repo-owned ABI constants**:
    - macOS arm64: `docs/refs/darwin_arm64_abi.md` + `lib/compiler/arm64_abi_macos.oren`
    - Linux arm64: `docs/refs/linux_arm64_abi.md` + `lib/compiler/arm64_abi_linux.oren`
    - Linux x86_64: `docs/refs/linux_x86_64_abi.md` + `lib/compiler/x64_abi_linux.oren`
- Runtimes:
  - Added `oren_file_stat_size_mtime_ns(path)` for build tooling:
    - native runtime: implemented via `sys_stat` + OrenStatV0 decode
    - C backend runtime: implemented via libc `stat(2)`
- Compiler build cache (performance):
  - Scan cache bumped to **v3** (`build/cache/scan_cache_v3.txt`), storing per file:
    - `(mtime_ns, size)` for validation
    - file content hash (`raw`)
    - include edges (`includes`)
    - direct imports (`imports_self`)
    - derived closure hash + merged imports (`hash`, `imports`)
  - Include-closure hashing in rolling mode is now **stat-aware**, so unchanged sources do not get re-read during build-cache key computation.
- Evidence (arm64-macos, stage2 compiler):
  - `./oren_stage2 build examples/hello.oren --backend native --platform arm64-macos --debug ...` completes in ~`261ms` (two consecutive runs with `OREN_TRACE_BUILD=1`).
- Verified:
  - `make verify-native-quick`
  - `./scripts/verify_native_matrix.sh --targets arm64-linux`
  - `make verify-native-x64-compile`

## Archived (2026-01-03) — Native: runtime object cache (arm64 throughput)

- Compiler (arm64 native backend):
  - Added a backend-specific compiled runtime cache (“runtime object”) so “compile one file” can skip recompiling `lib/runtime_native.oren` on cache hit.
  - Cache stores:
    - `meta.astbin` (function offsets, fixups, globals, cstr0 offsets, and function metadata)
    - `code.u8` and `data_tail.u8` (runtime machine code and `.data` tail after the shared prefix slot)
  - Env knobs:
    - disable: `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`
    - override dir: `OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR=...`
    - trace: `OREN_TRACE_RUNTIME_OBJ_CACHE=1`
- Evidence (arm64-macos, stage2 compiler, `tests/native/test_quick_integration_native.oren`, `--no-cache --no-debug`):
  - cache miss (build runtime object): `real ~2.04s`
  - cache hit: `real ~0.58s`
- Verified:
  - `make verify-native-quick`
  - `./scripts/verify_native_matrix.sh --targets arm64-linux`

## Archived (2026-01-03) — Native: runtime object cache (x64 throughput)

- Compiler (x86_64 native backend):
  - Extended the compiled runtime object cache to x64 so x64-linux/x64-windows builds do not recompile the full injected runtime on every build (cache hit splices precompiled runtime code/data).
- Verification:
  - Added a local compile-only gate: `make verify-native-x64-compile`
    - stage1+stage2 emit x64-linux ELF and x64-windows PE32+ (no remote/WSL required).

## Archived (2026-01-03) — Native: runtime object cache (debug builds enabled)

- Compiler (arm64 + x86_64 native backends):
  - Enabled the compiled runtime object cache for **debug** builds (non-capsule), so debug builds can also skip recompiling the full injected native runtime on cache hit.
  - Fixed debug symbolization plumbing to work in runtime-object-splice mode:
    - arm64: derive resolve-symbol entries from `ctx["functions"]` rather than scanning an in-memory `runtime_prog` AST that does not exist when rtobj is used.
    - x86_64: ensure runtime symbols are included in the debug symbol table list when rtobj is used.
  - Fixed a stage2 C-backend bootstrap failure caused by an unused/optimized-away `runtime_prog` declaration mismatch.
- Verified:
  - `make verify-native-quick`
  - `./scripts/verify_native_matrix.sh --targets arm64-linux`
  - `make verify-native-x64-compile`

## Archived (2026-01-03) — Native: stage2-native correctness + hot-path fixes (rtobj + debug)

- Correctness (native runtime + compiler):
  - Fixed a native runtime iteration bug where `oren_iter_next_entry(m, idx, out_pair)` treated `idx==0` as “nil” (native v0 represents `nil` as integer 0).
    - Impact: map iteration starting at index 0 returned “no entries”, which broke runtime-object metadata application (e.g. merging `meta["globals"]`), leading to missing runtime globals like `g_target_os`.
- Throughput (stage2-native compiler):
  - Runtime object cache selection now uses a fast non-cryptographic fingerprint (schema v2) instead of SHA-256 of the full expanded runtime source, avoiding multi-second hashing in native self-host workloads.
  - arm64 debug symbol resolver generation no longer uses quadratic string concatenation; it now builds parts and joins once.

## Archived (2026-01-03) — Native self-host runtime: Mach-O emit throughput + debug build bounds

- Compiler core bytes builder (`u8_buf`-backed) now copies via raw pointer operations in 8-byte chunks for:
  - buffer growth (`_bytes_ensure_capacity`)
  - splicing (`bytes_extend`, `bytes_extend_u8_buf`)
  - finalization (`bytes_finalize`)
  - Result: native-runtime stage2 compiler can now emit Mach-O outputs within Tier‑1 timeout budgets (previously could stall >30s in large per-byte copy loops).
- arm64 native backend no longer generates a giant parsed `resolve_symbol` function by default:
  - Debug builds rely on the embedded `g_debug_info` table for accurate symbolication; `resolve_symbol` remains a stub unless `OREN_NATIVE_RESOLVE_SYMBOL=1`.
- Build cache policy (rolling):
  - Debug builds default to cache-disabled to avoid expensive content-hash key computation under the native runtime.
  - Opt-in: `OREN_CACHE_DEBUG=1`.

## Archived (2026-01-03) — Native runtime: GC should not “root” string literals

- Native runtime model:
  - Embedded string literals are represented as pointers into the native binary’s data segment and tracked as **static-kind** nodes (size=0) for classification only.
  - Static-kind nodes are **not GC-managed heap allocations** and should not be pinned/registered as GC roots.
- Implementation:
  - `oren_gc_pin(v)` now only roots values whose tracking node has a non-zero `size` (heap-managed); static string literals are skipped.
  - `oren_set_result(v)` now applies the same rule so setting the result to a string literal does not allocate a pointless GC root node.
  - `oren_mark_value(v)` fast-skips static-kind STRING nodes (size=0, kind=STRING) so they do not participate in mark/sweep.
- Verified:
  - `make verify-native-quick`
  - `./scripts/verify_native_matrix.sh --targets arm64-linux`
  - `make verify-native-x64-compile`

## Archived (2026-01-03) — Native: pooled static string literals (no per-use tracking)

- Native runtime:
  - String literals are treated as **static-kind** (not GC-managed heap allocations).
  - Added a startup init hook `oren_init_static_cstr0_table(table_ptr)` so `oren_find_node(ptr)` can classify literals as kind=STRING without per-use `oren_ensure_tracked` calls.
  - Optimized startup: `oren_init_static_cstr0_table` allocates literal tracking nodes from a single contiguous block (avoids N tiny allocations on large binaries).
- Native backends:
  - arm64: embedded cstr0 literal pool is now deduped (matches x86_64 behavior).
  - arm64: member/struct field-name keys now use the same pooled cstr0 path (no ad-hoc duplicated cstr emission per access).
  - Entry stubs (arm64 + x86_64) call `oren_init_static_cstr0_table` immediately after `native_runtime_init` so later runtime init helpers can safely use string literals as map keys.
- Verified:
  - `make verify-native-quick` (stage1 + stage2 local smoke)
  - `./scripts/verify_native_matrix.sh --targets arm64-linux` (linux/arm64 docker run for both stage1 + stage2 native outputs)

## Archived (2026-01-03) — Native: runtime bundle AST cache + astbin decode hot-path win

- Compiler:
  - Added a default runtime astbin cache for native runtime injection:
    - caches under `build/cache/native_runtime_astbin/` keyed by SHA-256 of expanded `lib/runtime_native.oren`
    - disable via `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0` (or override dir via `OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR=...`)
    - kept troubleshooting overrides: `OREN_NATIVE_RUNTIME_EXPANDED` / `OREN_NATIVE_RUNTIME_ASTBIN`
- Native backends:
  - Inlined `oren_buf_load_u8_unchecked(buf, idx)` in both arm64 and x86_64 emit to avoid per-byte function-call overhead in compiler hot paths (notably astbin decode).
  - Evidence (arm64-macos, stage2-native compiler, quick integration build):
    - runtime astbin decode dropped from ~11–12s → ~7–8s (`OREN_TRACE_RUNTIME_BUNDLE=1 OREN_TRACE_ASTBIN=1`).
- Native runtime:
  - Lists/maps allocate header + initial backing buffer in a single tracked block (reduces allocation+tracking volume for AST-heavy workloads).

- Verified:
  - `make verify-native-quick`
  - `./scripts/verify_native_matrix.sh --targets arm64-linux`

## Archived (2026-01-03) — x64-linux: WSL exit code + ELF sections + runtime pruning

- Linux x86_64 native now terminates via `exit_group(2)` (process-wide) for:
  - entry stub (`main` return → process exit), and
  - `sys_exit` lowering (`exit(code)` / `oren_exit(code)`).
- ELF emitter now writes a minimal section header table (SHT) so `readelf/objdump` show sane `.text`/`.data` sections.
- Runtime pruning for targeted builds:
  - prunes runtime-tagged `if g_target_os == ...` / `!= ...` branches at compile time to avoid compiling dead platform code.
- Code size win:
  - compiler-generated panics now call a shared helper instead of inlining a full panic+trace sequence at every site (debug builds keep the trace).

## Archived (2025-12-31) — macOS Mach-O signing rule simplified (external `codesign`)

- Removed the custom embedded ad-hoc code signature generator from `lib/compiler/arm64_macho.oren` (it did not produce a signature accepted by macOS tooling).
- Tier‑1 macOS reliability relies on external signing (`codesign -s - --force`) in the build pipeline when available.
- Docs: `docs/CODESIGN.md`

## Archived (2025-12-31) — Native entry semantics unified (`__top_level__` + optional `main`)

- Standardized the native entry contract across arm64 + x86_64:
  - User top-level statements and non-constant global initializers compile into a synthesized `fn __top_level__(){...}`.
  - The runtime entrypoint executes `__top_level__` first, then calls `main` if it exists.
  - `fn main()` is optional; programs with only top-level code exit 0 deterministically.
- Updated the native test suite to match the contract by removing accidental `main()` calls at top-level (tests should define `fn main()` only).
- Added a Tier‑1 remote x64 fixture covering language-level concurrency on both Linux x86_64 (WSL2) and Windows x64:
  - `tests/fixtures/tier1_native_spawn_join_main.oren` (run via `OREN_REMOTE_RUN=1 make test`).

## Archived (2025-12-29) — OBC portability gate hardened (timeouts + WSL progress)

- Confirmed the `.obc` portability contract with an integration gate that compares `RESULT_HASH` and `TRACE_HASH` across:
  - macOS arm64 (host)
  - linux/arm64 (docker container)
  - linux/x86_64 (WSL2 on remote Win11 host)
- Hardened the portability script so it can’t hang silently in rolling workflows:
  - Added configurable timeouts (`OREN_REMOTE_WSL_TIMEOUT_SECS`, `OREN_REMOTE_TIMEOUT_SECS`, `OREN_DOCKER_TIMEOUT_SECS`).
  - Added minimal progress markers for the WSL step (`[wsl] unpack/build/run`) while keeping build output quiet.
- References:
  - Script: `tools/verify_obc_portability.sh`
  - Docs: `docs/OBC_PORTABILITY.md`
  - Make target: `make obc-portability`

## Archived (2025-12-21) — Native SIMD scale/axpy + matmul scratch reuse (HPC)

- Native backend:
  - Added NEON intrinsics for `simd_scale_{i32,f32}_ptr` and `simd_axpy_{i32,f32}_ptr`.
  - Fixed `arm64_core.insn_dup_4s` encoding (was emitting the wrong instruction, corrupting scalar SIMD kernels).
- Native runtime:
  - Enabled SIMD fast paths for `oren_buf_scale_{i32,f32}_into` and `oren_buf_axpy_{i32,f32}_into`.
  - f32 axpy semantics: float32 boundary + mul-then-add (no FMA), matching C runtime + AVM determinism.
- Stdlib linalg:
  - Reduced allocation pressure by reusing the 1×4 dot scratch buffer in `matmul_f32_buf` and `matmul_i32_buf` (avoid per-row scratch allocation).
- Verified: `make stage1` + `previous test runner --target macos` pass.

## Archived (2025-12-21) — Explicit fixed-width types + cast sugar (HPC/FFI baseline)

- Language + compiler:
  - Fixed-width numeric types are first-class reserved tokens (`u8/i8/u16/i16/u32/i32/u64/i64/u128/i128/f32/f64`, plus endian forms like `u16be`).
  - Cast sugar (`u8(x)`, `i32(x)`, `f32(x)`, endian spellings) is lowered by `type_ann_lowering.oren` into deterministic wrap/truncate/bitcast ops.
  - Float→int cast semantics are C-like (truncate toward zero), with `round/floor/ceil` being separate math ops.
  - Integer-only cast sites skip the float truncation helper when provably-int (avoid overhead in tight loops).
- Stdlib:
  - `std/ints` and `std/casts` accept float inputs consistently (truncate toward zero).
  - `casts.f32(int)` accepts integer input (coerce int->f64->f32 boundary deterministically).
- Coverage:
  - `tests/modules/test_integration_suite.oren` exercises wrap/truncate, endian casts, and f32 rounding boundary.
- Verified: `make stage1` + `previous test runner --target macos` pass at the time this was moved out of the active TODO list.

## Archived (2025-12-28) — Active TODO list compacted (x64/CoreIR focus)

- Compressed `docs/TODOS.md` back to a short “top items only” tracker (rolling rule: 5–10 items).
- The detailed x86_64 bring-up notes remain in git history and in the dedicated design docs:
  - `docs/NATIVE_BACKEND.md`
  - `docs/NATIVE_BACKEND_CODE_REUSE_PLAN.md`
  - `docs/BACKEND_ARCHITECTURE.md`
  - `docs/REMOTE_X64_ENV.md`

## Archived (2025-12-28) — Map key-kind determinism + typed map ops parity (native/C)

- Native runtime map storage (int keys vs string keys) is explicitly kinded to keep `strcmp` safe and deterministic:
  - `lib/runtime_native/130_printing.oren`
- Added typed map helpers to the C runtime surface for cross-backend parity:
  - `oren_map_get_str/int`, `oren_map_set_str/int`, plus `oren_map_set` wrapper in `lib/runtime/040_lists_maps.inc` and `lib/runtime.h`.
- Stdlib codecs and option parsing now use explicit `oren_map_*_str` helpers when the key is dynamically produced as a string:
  - `lib/std/json.oren`, `lib/std/yaml.oren`, `lib/std/cbor.oren`, `lib/std/argparse.oren`
- Rolling contract alignment:
  - `oren_map_set_*` returns the written value (consistent with `oren_list_set` / `xs[i]=v` semantics).

## Archived (2025-12-21) — Trig for huge |x|: Payne–Hanek range reduction

- Stdlib math:
  - Implemented deterministic `sin/cos` range reduction for huge |x| using a Payne–Hanek-style reducer adapted from fdlibm.
  - Removed the previous conservative “|x| too large” error for trig.
  - Added reference sources under `docs/refs/fdlibm/` (`e_rem_pio2.c`, `k_rem_pio2.c`) to keep the implementation anchored to an audited algorithm.
- Tests:
  - Added `tests/modules/test_math_trig_huge.oren` and wired it into `previous test runner --full` (not in the fast suite).
- Verified:
  - `previous test runner --target macos` pass.
  - `previous test runner --full --target macos` pass.

## Archived (2025-12-21) — Unify `struct` semantics (map-shaped, mutable) across backends

- Decision: in rolling v0, `struct` values are **map-shaped** (string-keyed) across **C + AVM bytecode + native** backends.
  - `x.field` lowers to `x["field"]` semantics (map key lookup).
  - `x.field = v` mutates the field (map key set).
  - Layout-stable use-cases remain `@pack` (byte views) and `@abi` (layout-only), not v0 structs.
- Compiler/linker: removed the global “field name → index must match across all types” constraint (was a v0 hack for positional struct layouts).
- Bytecode backend:
  - type constructors emit `NEW_MAP` with string keys (not `NEW_LIST`)
  - member read/write compile to `GET_INDEX`/`SET_INDEX` with string keys
- Native backend:
  - type constructors now build maps via `oren_new_map` + `oren_map_set` (no raw `oren_alloc_struct` field buffers)
  - member reads use `oren_map_get` (no field-offset fast path in v0)
- Tests:
  - added `tests/avm/test_struct_member_set.oren`
  - added `tests/native/test_struct_member_set.oren`
- Verified: `make test` on macOS passes.

## Archived (2025-12-21) — AVM snapshot v7: scheduler pause/resume

- AVM snapshots: added **AVMSNAP7** with full scheduler snapshot/restore (tasks + channels + ready/select queues).
  - `--snapshot-out` now works even when `spawn`/channels are active (pause/resume of non-trivial scheduler).
  - Updated AVM test from “forbidden” to “resume” (`tests/avm/test_snapshot_tasks_resume.oren`) and previous test runner wiring.
- Internal refactor: moved scheduler structs (`AvmTask`, `AvmChan`, `AvmSched`) into `lib/avm/avm_internal.h` so snapshot code can serialize them.
- Bytecode backend fix: `oren_yield()` now returns a canonical `nil` value (stack-balanced as an expression), preventing verifier stack-height mismatches in real programs.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-21) — Allocator control for large typed buffers (HPC)

- Implemented env-configurable allocation policy for large numeric payloads (bootstrap-friendly, rolling):
  - `OREN_RAW_MMAP_THRESHOLD` (0 disables) for raw typed-buffer payload mmap threshold (C + native).
  - `OREN_BUF_ALIGN=8|16|32|64` (default 64) for typed-buffer alignment (NEON/cacheline-friendly).
  - `OREN_BUF_FORCE_MMAP=1` (native) to force typed buffers to mmap (debug/benchmark).
  - `OREN_BUF_PAYLOAD_LIMIT_BYTES` to bound payload size deterministically and fail with a budget error.
- Test runner hardening:
  - `cmd/previous test runner` sanitizes allocator env vars (prevents user shell env from changing test behavior).
- Tests:
  - Added churn-style fragmentation stress: `tests/modules/test_buffer_alloc_stress.oren`.
  - Added payload-budget regression: `tests/modules/test_buffer_payload_limit.oren`.
- Verified: `make test` on macOS passes.

## Archived (2025-12-21) — Compiler-in-AVM v1 (VirtualFS + argv-as-data)

- Extended AVM nested-universe interface `avm.run_obc_bytes` (Domain 8, op 0):
  - Accepts `cfg["argv"]` as `LIST<string>` and injects it into the child VM (`argc/argv`).
  - Returns `vfs_snapshot` as AVMVFS01 bytes so the parent can read files produced in the child’s VirtualFS.
- Added integration harness `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren`:
  - Runs the compiler `.obc` in a nested universe with VirtualFS fixtures (no host effects).
  - Extracts `out.obc` from returned `vfs_snapshot` and runs it in another nested universe.
- Wired into `previous test runner --full` as fixture `compiler_in_avm_smoke` (host FS read restricted to `build/` only).
- Verified: `previous test runner --full --target macos` passes.

## Archived (2025-12-21) — Typed buffer slice/strided views + iteration semantics

- Standardized portable view encodings in `std/buffer`:
  - slice view: `[buf, off, len]`
  - strided view: `[buf, off, len, stride]`
  - matrix view (existing): `[buf, off, rows, cols, row_stride]`
- Added view helpers:
  - `buffer.slice_slice(...)` (slice-of-slice)
  - `buffer.strided_new(...)` plus load/store helpers per element kind
- Made `for x in view` iterate *values*, not metadata, by teaching `oren_iter_next` to recognize these view lists:
  - C runtime: `lib/runtime.c`
  - AVM runtime: `lib/avm/avm_native.inc`
  - Native runtime: `lib/runtime_native.oren`
- Extended integration coverage in `tests/modules/test_buffer_views.oren`:
  - slice, slice-of-slice, strided view, `for-in` over views
  - `std/linalg` view helpers (`dot_*_view`) and strided matrix-view matmul (`matmul_f32_mat_view`)
- Verified: `previous test runner --target macos` and `previous test runner --full --target macos` pass.

## Archived (2025-12-21) — Iteration model v1: `Iterable` trait extension (static-first, no vtables)

- Kept the v0 iteration ABI/hook intact:
  - `for x in it { ... }` still relies on the `oren_iter_next(container, idx, out_pair)` contract.
- Added a v1 extension point for **custom deterministic iterables** without runtime vtables:
  - If the iterable is a **bare identifier** and has a known type annotation, the compiler may rewrite:
    - `oren_iter_next(it, idx, out_pair)` → `__oren_impl__Iterable__<Type>__iter_next(it, idx, out_pair)` when an impl exists.
  - This is implemented as a whole-program lowering rule (impl lowering pass), so it works across modules.
- For-loop desugaring optimization:
  - For identifier iterables, the compiler no longer stashes the container inside the internal `@forin_*` state list,
    preserving the identifier in the call site so type-based rewriting is possible.
- Added integration coverage to ensure it works end-to-end:
  - `tests/modules/test_integration_suite.oren` adds `MyRange` + `Iterable.iter_next` and sums values via `for-in`.
- Verified: `make stage1` then `previous test runner --target macos` passes.

## Archived (2025-12-21) — Typecheck v0: reject non-numeric cast inputs (HPC signal)

- Strengthened `--typecheck` to catch obvious invalid casts when the input category is statically known:
  - numeric casts (`u8/i32/f32/...`) reject `string`, `bytes`, `list`, `map`, and typed buffers (`[]T`) as inputs.
  - `bool(...)` rejects `string/bytes/list/map` (still permits numeric/bool/nil/unknown).
  - `as` casts are desugared to cast sugar calls and follow the same rules.
- Extended the existing `tests/fixtures/typecheck_bad_cast.oren` to cover:
  - `f32("...")`, `u8("...")`, `bool("...")`
  - `bytes` annotated value cast via `i32(b)` and `b as i32`
- Verified: `make stage1` then `previous test runner --target macos` passes.

## Archived (2025-12-21) — Type namespacing v1: `alias.Type` annotations resolve across modules

- Extended the module renamer so it also rewrites *type annotation strings*:
  - local type annotations like `MyType` become `M<N>_MyType` inside imported modules (keeps annotations consistent with prefixed symbols).
  - import-alias type annotations like `buffer.MyType` become `<alias_ns>.MyType` (e.g. `M5_buffer.MyType` or `R_buffer.MyType`).
  - impl-block metadata `impl_type` is renamed too (prevents cross-module impl collisions).
- Added a dedicated linked-program pass that resolves alias-qualified annotations:
  - `<alias_ns>.Type` → `<dep_prefix>Type` using `linked["aliases"]`.
  - validates the resolved type exists in `linked["type_ns"]` and errors early if not.
  - this enables annotation-driven dispatch decisions (method sugar, `Iterable` for-in hook) across modules.
- Added cross-module integration coverage:
  - `tests/modules/iterable_mod.oren` defines `struct MyRange` + `impl Iterable for MyRange`.
  - `tests/modules/test_integration_suite.oren` imports it and iterates `for x in r3` where `r3: itmod.MyRange`.
- Verified: `make stage1` then `previous test runner --target macos` passes.

## Archived (2025-12-21) — Generic trait constraints (static-first)

- Generic type parameters now support trait constraints:
  - single: `fn plus_one[T: Add1](x: T): T { ... }`
  - multiple: `fn f[T: Mul1 + Add1](x: T): T { ... }`
- Enforcement is done at monomorphization time (compile-time):
  - instantiations require `impl Trait for <Type>` to exist (or `impl Trait for any` as a fallback)
  - missing impls are surfaced as a deterministic compiler error: `missing impl for trait ...`
- Tests:
  - Added module coverage: `tests/modules/test_generic_trait_constraints.oren`
  - Added compile-fail fixture (full suite only): `tests/fixtures/generic_constraint_missing_impl.oren`
- Verified: `previous test runner --full --target macos` passes.

## Archived (2025-12-21) — Typed `for x:T in ...` iterator variable annotations

- Hardened the typed iterator-variable form:
  - `for x: i32 in buf { ... }`
  - `for b: u8 in bytes_list_or_u8_buf { ... }`
  - `for y: f32 in f32_buf { ... }`
- Coverage:
  - Updated typed-buffer iteration module test: `tests/modules/test_iter_buffers.oren`.
  - Added integration test for bytes/strings + typed annotation: `tests/modules/test_for_in_bytes_typed.oren`.
- Verified: `previous test runner --full --target macos` passes.

## Archived (2025-12-19) — Previously in `docs/TODOS.md` “Recently Completed”

- Native backend spawn intrinsic: removed remaining hardcoded `svc #0`/`svc #0x80` + numeric syscall IDs; now uses `arm64_abi_{macos,linux}.oren` tables.
- Mach-O minimal exit stub (`macho_emit_exit_arm64`): now uses `arm64_abi_macos.oren` syscall ABI constants (no embedded MOVK/SVC magic).
- FS mounts semantics hardened: longest-prefix + boundary checks in native runtime; AVM host mounts match (incl. host-path allow-as-is under enrolled host prefixes); added overlapping-mount regression tests.
- FS allow-prefix policy hardened: require boundary when a prefix does not end with `/` (prevents `build` matching `build2`); applied to native capsule + AVM host allow-prefix checks.
- ABI tables expanded: centralized NET-related syscalls (socket/connect/bind/listen/accept/sendto/recvfrom) and other process/syscall staples (execve/wait4/kill/gettimeofday/fcntl, sockopt/shutdown, peer/sockname) for macOS+Linux; removed more numeric `sysno=` literals from syscall lowering.
- Native string propagation: fixed `+` stringiness to require both operands, added `oren_list_get` string propagation and array-of-strings list inference; added `tests/native/test_string_list_eq.oren`.
- ABI constants: moved remaining Darwin `kevent` syscall number and Linux `AT_*` syscall-arg flags (AT_SYMLINK_NOFOLLOW/AT_REMOVEDIR) into repo-owned ABI tables; removed the last hardcoded `sysno=363` from syscall lowering.
- ABI constants: centralized Linux `AT_FDCWD=-100` into `arm64_abi_linux.oren` and added a signed-immediate loader helper (removes remaining `MOVN imm=99` magic from syscall lowering).
- Native string comparisons: added regression coverage for `string == nil` / `nil == string` (must not lower to `strcmp`).
- Mach-O emitter: replaced key numeric header/load-command/bind-opcode literals with repo-owned named constants (keeps ABI knowledge local without SDK headers).
- Mach-O emitter: removed remaining layout magic numbers (segment alignment, codesign page size, exit-stub header sizing, section flags) by centralizing them as named constants.
- Mach-O emitter: replaced raw segname/sectname byte sequences with a fixed-16 string helper (less brittle, clearer).
- Mach-O emitter: centralized remaining structural constants (prot flags, build-version packing, codesign lengths) and removed more remaining magic numbers.
- Refs: vendored Mach-O headers (`loader.h`, `nlist.h`) into `docs/refs/macho/` pinned to an Apple OSS `cctools` commit for audit-only reference (no build dependency).
- Refs: refreshed vendored Linux/Darwin syscall references under `docs/refs/` and recorded pinned upstream commits in `docs/refs/SOURCES.md` (audit-only).
- Native backend docs: corrected `+` string concatenation note to match native lowering (`oren_add`) and current test coverage.

## Archived (2025-12-20) — Doc alignment + tracker cleanup

- Tracker: clarified docs-only verification scope to include `README.md` + `LICENSE`; reweighted TODO list to focus on attribute-driven serde as the next major language ergonomics step.
- Docs: added `docs/ATTRIBUTES.md` as the attribute cookbook and documented the emitted metadata shape.
- Docs: updated `docs/LANGUAGE_SPEC.md` to reflect current type-annotation semantics (value-level casts + `bool` normalization + `f32` rounding) and to mark `i128/u128` as ABI/layout-only until runtime semantics stabilize.
- Docs: updated `docs/SELF_HOSTING.md` to match the current multi-backend reality and to defer to `docs/BUILD_AND_VERIFY.md` for the authoritative bootstrap steps.
- Docs: updated `docs/STDLIB_LAYERS.md` to point at the refactored parser modules and to document strict attribute mode flags.

## Archived (2025-12-20) — Casting model + type plan + linalg foundation

- Casting: removed strict-casts mode (language semantics are deterministic by default).
- Casting: compiler lowers builtin cast sugar (`u8(x)`, `i32(x)`, `f32(x)`, `bool(x)`, endian spellings like `u16be(x)`) into deterministic rewrites (no dynamic call overhead).
- Casting: added `lib/std/casts.oren` as an optional clarity layer matching annotation lowering.
- Tests: added regression module test `tests/modules/test_cast_sugar.oren` and wired it into `cmd/previous test runner`.
- Docs: added `docs/TYPE_SYSTEM_PLAN.md` to guide gradual typing → generics/traits.
- Stdlib: added `lib/std/linalg.oren` (scalar-first `dot_*`, `axpy_*`, `matmul_*`) with module test `tests/modules/test_linalg.oren` and previous test runner wiring.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Numeric cast semantics (float→int truncation)

- Casting: defined and implemented float→int cast semantics: truncate toward zero, then wrap/truncate to target width.
  - Added `oren_trunc_int` intrinsic (C runtime + AVM native + native backend inline).
  - Updated cast sugar lowering to apply `oren_trunc_int` before integer masks and to allow `f32(int)` via `x + 0.0` coercion.
- Typecheck v0: relaxed numeric cast rules so `u8(1.0)` is valid; string/bool/nil remain rejected for numeric casts.
- Tests: expanded `tests/modules/test_cast_sugar.oren` to cover float→int and `f32(int)`; kept `tests/fixtures/typecheck_bad_cast.oren` rejecting `f32("...")`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — `as` cast operator + typecheck v0 scaffolding

- Language: added `as` cast operator (`expr as u8`) desugared to builtin cast sugar.
- Language: added opt-in `--typecheck` pass to reject obvious invalid casts and mismatched annotated boundaries.
- Tests: added `tests/modules/test_as_cast.oren` and fixture `tests/fixtures/typecheck_bad_cast.oren` wired into `cmd/previous test runner`.

## Archived (2025-12-20) — Test system evolution spec (no rewrite)

- Documented a minimal Oren-native test manifest shape and runner CLI/output contract in `docs/TEST_SYSTEM.md`.
- The design keeps `cmd/previous test runner` as the current orchestrator (Go), enforcing SOLID by keeping test orchestration out of `lib/compiler/*.oren`.

## Archived (2025-12-20) — Serde JSON v1 (attribute-driven, no reflection)

- Implemented attribute-driven JSON serde helper generation (opt-in) in `lib/compiler/serde_json_lowering.oren`.
  - `@json.derive("json")` / canonical `@serde.derive("json")` on a struct triggers codegen.
  - Generates:
    - `<Type>__json_encode(x)` → JsonValue
    - `<Type>__json_decode(jv)` → `{ok, err?, v?}`
  - Supports field options:
    - `@json.rename("wire")`
    - `@json.skip()` + `@json.default(<literal>)` (skip requires default for decode determinism)
    - `@json.tag("TypeTag")` (adds `"t"` tag field, validated on decode)
- Parser: allowed `default` keyword token in attribute dotted names (`@json.default(...)`) without making `default` a general identifier.
- Tests:
  - Added `tests/modules/test_json_serde_attrs.oren` (integration: encode + decode + ordering + defaults).
  - Updated curated runner list (`cmd/previous test runner/main.go`) to include it.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Serde attribute ergonomics v1 (format-first)

- Upgraded the preferred surface syntax to remove redundancy and be multi-format friendly:
  - Struct opt-in: `@serde(format="json", tag="User")` (also supports positional `@serde("json")`).
  - Field options: `@serde(rename="wire")`, `@serde(skip=true, default=0)`.
- Kept rolling back-compat:
  - `@json.*` aliases still canonicalize to `serde.*`.
  - legacy dotted: `@json.derive("json")`, `@json.tag("User")`, `@json.rename("x")`, `@json.skip()`, `@json.default(0)`.
  - previous compact: `@serde(derive="json")` still works.
- Parser: fixed keyword-arg parsing to accept keyword tokens as keys (e.g. `default=0` where `default` is tokenized as a keyword).
- Tests: strengthened `tests/modules/test_json_serde_attrs.oren` to cover both compact `@serde(...)` and legacy dotted forms.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Serde schema metadata v1 (`oren meta`)

- Implemented a normalized serde schema under `structs[*].serde` in metadata output (deterministic, versioned).
  - Includes: `version`, `format`, optional `tag`, and normalized fields:
    - `name`, `ann_type`, `wire`, `skip`, `default`
- Added previous test runner coverage to ensure `oren meta` contains the serde schema for the JSON fixture.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — CBOR v1 (RFC 8949 subset) + `@serde(format="cbor")`

- Added `lib/std/cbor.oren`:
  - deterministic CBOR encode/decode for a small portable tagged representation (`CborValue`)
  - canonical map key ordering (length then bytewise) for stable bytes
- Extended serde lowering to support `@serde(format="cbor")`:
  - generates `<Type>__cbor_encode` / `<Type>__cbor_decode` (tagged value; binary encoding is via std/cbor)
- Added integration test `tests/modules/test_cbor_serde_attrs.oren` and wired it into `cmd/previous test runner`.
- Vendored RFC 8949 text into `docs/refs/cbor/rfc8949.txt` for audit reference.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — CBOR streaming (CBOR Sequences, RFC 8742)

- Vendored RFC 8742 text into `docs/refs/cbor/rfc8742.txt` for audit reference.
- Added streaming-friendly API in `lib/std/cbor.oren`:
  - `cbor.decode_next(bytes, pos)` for incremental parsing (one item)
  - `cbor.decode_sequence(bytes)` for whole-buffer sequences
  - `cbor.encode_sequence(items)` for emitting sequences

## Archived (2025-12-21) — Typed buffers + views + C backend ordering fix

- **Typed buffers** (C backend runtime primitives):
  - Added `OREN_TYPE_{I32,I64,F32,F64}_BUF` + `OrenBuf` header in `lib/runtime.h`.
  - Implemented buffer ops in `lib/runtime_buf.c` (alloc, load/store, fill, add/mul/scale, dot, reduce_sum; `_into` variants for out-params).
  - Linked C backend builds against both `lib/runtime.c` and `lib/runtime_buf.c` (see `lib/compiler/compiler.oren`).
  - Added `lib/std/buffer.oren` (zero-copy slice + matrix-stride views using map-based view objects in v0).
  - Added `tests/modules/test_buffer_views.oren` and wired it into `cmd/previous test runner`.

- **Language ergonomics / parsing**:
  - Parser: added `[]T` prefix type annotation parsing (stored as `"[]T"` string) in `lib/compiler/parser_core.oren`.
  - Parser: removed the compile-time error that blocked `obj.field = v` (struct fields are now assignable; semantics are backend-defined in rolling mode) in `lib/compiler/parser_parse.oren`.

- **Correctness fix (high impact)**:
  - C backend: fixed a semantic bug where top-level `var` initializers were hoisted ahead of other top-level statements.
    - `var` now declares a global symbol but executes its initializer in source order by lowering to an `Assign` statement in `main_body`.
    - Implemented in `lib/compiler/transpiler.oren` by changing `collect_parts()` and removing the global-initializer hoist block.

- **Quality-of-life**:
  - C runtime: `print_value_no_newline` now prints buffer values as `<i32_buf len=N>` (etc) and no longer triggers missing-switch warnings.

- Verified:
  - `previous test runner` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)

## Archived (2025-12-21) — `std/linalg` v0.2 (buffers + safe NEON) + i32 overflow hardening

- Runtime (C backend buffers):
  - Defined wrap-safe semantics for i32 `dot` / `reduce_sum` by accumulating modulo 2^64 (avoids signed overflow UB).
  - Added arm64 NEON fast paths for i32 `dot` / `reduce_sum` (little-endian only; deterministic).
  - Added AXPY intrinsics:
    - `oren_buf_axpy_f32_{into,in_place}` (per-element float32 mul+add; avoids fused multiply-add)
    - `oren_buf_axpy_i32_{into,in_place}` (per-element wrap math)

- Stdlib:
  - `lib/std/linalg.oren` gained typed-buffer APIs (`*_buf`) and delegates to runtime buffer kernels for performance.

- Tests:
  - Extended `tests/modules/test_linalg.oren` to cover typed-buffer dot/axpy.

- Verified:
  - `previous test runner` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)

## Archived (2025-12-21) — GC allocation registry indexing (hash table) + stress test

- Runtime (C backend GC registry):
  - Replaced `oren_find_node()` linear scan over `g_allocs` with an open-addressing hash index (`g_alloc_index`) keyed by allocation pointer.
  - Kept `g_allocs` as the canonical sweep list; the index is only for O(1) lookup during mark/free.
  - Hardened explicit frees (`oren_free`, `oren_free_struct`) to remove registry nodes so the alloc registry does not grow without bound under manual frees.
  - Sweep now removes freed nodes from the index as well.

- Tests:
  - Added `tests/modules/test_alloc_gc_scale.oren` (allocation churn + periodic `oren_gc_collect()`) and wired it into `cmd/previous test runner`.

- Verified:
  - `previous test runner` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)
- Added tests: `tests/modules/test_cbor_sequence.oren` and wired into `cmd/previous test runner`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — `std/time` v0 (UTC-only ISO8601 + epoch conversions)

- Runtime (C backend):
  - Added TIME primitives to `lib/runtime.c` / `lib/runtime.h`:
    - `oren_sleep_ns` / `oren_sleep_ms`
    - `oren_time_unix_ns`
    - `oren_time_mono_raw`
    - `oren_time_now_ns` (stable alias for stdlib + AVM parity)
- Runtime (native):
  - Added `oren_time_now_ns` alias in `lib/runtime_native.oren` (maps to unix time for now).
- Stdlib:
  - Added `lib/std/time.oren`:
    - `Duration`, `Instant`, `DateTime`
    - UTC ISO-8601 `parse_iso8601_utc` / `format_iso8601_utc`
    - `datetime_to_unix_ns` / `datetime_from_unix_ns`
    - `sleep_ms`, `now_unix_ns`, `now_ns`, `mono_raw`, `instant_now`
  - Design: UTC-only v0; fractional seconds (1..9 digits) supported; format trims trailing zeros.
- Tests:
  - Added `tests/modules/test_time_std.oren` and wired into `cmd/previous test runner`.
- Verified:
  - `make test` on macOS.

## Archived (2025-12-20) — `%` modulo operator (C backend + AVM + native backend)

- Language:
  - Added `%` operator tokenization + parsing with `PRODUCT_P` precedence.
  - Updated typecheck v0 category inference so `%` is int-only.
- Backends:
  - C backend lowers `a % b` to `oren_mod(a, b)` with deterministic checks (div0, i64_min%-1).
  - AVM bytecode adds opcode `MOD` (0x1F) with deterministic error semantics for div0/overflow.
  - Native backend lowers `%` to the native runtime helper `oren_mod` so semantics stay deterministic.
- Tests:
  - Added `tests/modules/test_mod.oren` and wired it into `cmd/previous test runner`.
- Tooling:
  - Fixed `tools/oretest_linux_docker.sh` quoting hazard by removing backticks inside docker `bash -lc` heredoc.
- Verified:
  - `previous test runner --target macos`
  - `tools/oretest_linux_docker.sh`

## Archived (2025-12-21) — `oredoc openapi` (OpenAPI 3.1 export from metadata)

- Tooling:
  - Added `cmd/oredoc` (Go) to export OpenAPI 3.1 documents from `oren meta` output.
  - CLI: `./oredoc openapi <meta.json> -o out.json -title ... -version ... -format json`
  - Accepts both `-flag` and `--flag` forms for convenience.
- OpenAPI mapping (v0):
  - Exports minimal valid OpenAPI 3.1 document with `components.schemas` derived from `structs[*].serde`.
  - Maps Oren scalar annotations (`i32`, `u64`, `f32`, `bool`, `string`, `[]T`, etc.) to OpenAPI schema shapes.
- Tests:
  - Added an previous test runner fixture `oredoc_openapi_export` that roundtrips `oren meta` → `oredoc openapi` and validates key fields.

## Archived (2025-12-21) — C-backend build hygiene + GC stack-scan hardening

- C backend build hygiene:
  - `oren build --backend c` no longer writes generated `*.oren.c` next to sources.
  - C output is emitted alongside the output artifact (`out_path + ".c"`) and deleted on success.
- GC correctness:
  - Hardened `oren_mark_value` to validate allocation-kind before traversing list/map/buffer payloads.
  - Fixes a real crash where conservative stack scanning could misclassify a pointer and dereference a non-list/non-map allocation.

## Archived (2025-12-20) — CBOR serde streaming helpers (typed sequences)

- Added serde-friendly typed streaming helpers to `lib/std/cbor.oren`:
  - `cbor.encode_sequence_typed(items, Type__cbor_encode)`
  - `cbor.decode_next_typed(bytes, pos, Type__cbor_decode)`
  - `cbor.decode_sequence_typed(bytes, Type__cbor_decode)`
- Added integration test: `tests/modules/test_cbor_serde_streaming.oren`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — YAML serde adaptor v1 (deterministic subset)

- Added `lib/std/yaml.oren`:
  - deterministic YAML emitter (block style, sorted keys, 2-space indent)
  - deterministic subset decoder (mappings + sequences + scalar types), plus JSON-text fallback (YAML 1.2 JSON subset)
  - audit reference: `docs/refs/yaml/yaml-1.2.2.html`
- Extended serde lowering to support `@serde(format="yaml")`:
  - generates `<Type>__yaml_encode` / `<Type>__yaml_decode`
  - representation matches JSON tagged value shape (`YamlValue` == `JsonValue` shape)
- Added integration test `tests/modules/test_yaml_serde_attrs.oren` and wired it into `cmd/previous test runner`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Stdlib math + regex v1 (portable, deterministic)

- Added `lib/std/math.oren`:
  - int helpers: `abs_i`, `min_i`, `max_i`, `clamp_i`
  - float helpers: `abs_f`, `min_f`, `max_f`, `clamp_f`, `is_nan`
- Added `lib/std/regex.oren`:
  - deterministic Thompson NFA engine (no backtracking blowups)
  - syntax v1: literals, `.`, `?`, `*`, `+`, `|`, grouping `( )`, anchors `^` `$`, classes `[a-z]` / `[^...]`, escapes via `\\`
- Tests:
  - added `tests/modules/test_math.oren` + `tests/modules/test_regex.oren`
  - wired into `cmd/previous test runner/main.go`
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-17

Focus statement (to avoid roadmap thrash):

- AVM is an **agent execution substrate** (deterministic, capability-governed, multiverse-friendly), not a near-term “general runtime for other languages”.
- Native backend is **syscall-first** (no libc/pthreads shims) so Oren can build real production libraries in `.oren`.

## P0 (Emergency / Blocking Safety)

### Cross-cutting (prevents hangs / makes rolling safe)

1) **Hard timeouts in test runner + CLI**
   - Any test that can block on PROC/NET must run under a timeout.
   - This is non-negotiable in rolling mode: a single hang kills iteration velocity.
   - Baseline:
     - `make test` uses `timeout` for native/AVM invocations where a hang is possible.
     - `avm` also supports an in-process wall-time budget: `--timeout-ms N` (or `AVM_TIMEOUT_MS`) so tooling/users don’t rely only on external `timeout`.
     - add a short per-test timeout for spawn/system and a longer global suite timeout (done; see `SUITE_TIMEOUT_SECS` in `Makefile`).

2) **SOLID refactors for “debuggable production”**
   - Goal: keep compiler/runtime modules small enough that invariants (stack/heap/scope/ABI) are auditable.
   - Refactor trigger: any single compiler module > ~2000 LOC must be split by responsibility (SOLID).
   - Status (compiler):
     - `lib/compiler/codegen_arm64.oren` refactor completed into focused modules (SOLID split):
       - `lib/compiler/arm64_core.oren` (byte utils, scope helpers, insn encodings, emit helpers) (~549 LOC)
       - `lib/compiler/arm64_native_expr.oren` (expression lowering; delegates syscall lowering) (~1308 LOC)
       - `lib/compiler/arm64_native_expr_syscalls.oren` (syscall lowering; helper used by `arm64_native_expr.oren`) (~1903 LOC)
       - `lib/compiler/arm64_native_stmt.oren` (statement lowering) (~782 LOC)
       - `lib/compiler/arm64_native_program.oren` (program entry lowering + symbol table generation) (~260 LOC)
       - `lib/compiler/codegen_arm64.oren` is now a thin facade for legacy imports
       - `lib/compiler/renamer.oren` (module rename pass)
       - `lib/compiler/arm64_macho.oren` (Mach-O emit + codesign blob builder)
       - `lib/compiler/arm64_elf.oren` (ELF emit)
     - Next watch item (SOLID): if `lib/compiler/arm64_native_expr_syscalls.oren` grows past ~2000 LOC, split by syscall domain (FS vs NET vs PROC vs TIME) so invariants remain auditable.

3) **First-class functions: function values + lambdas (must)**
   - Why it is P0:
     - required for real library design (callbacks, iterators, schedulers, async/concurrency)
     - required for compiler modularity (passing `compile_expr` callbacks avoids cyclic imports cleanly)
   - Status (bootstrap/C backend):
     - runtime supports `OREN_TYPE_FUNC` + `oren_func(...)` + `oren_call_obj(...)` dispatch
     - both transpilers (Go bootstrap + self-hosted `lib/compiler/transpiler.oren`) emit wrapper entrypoints `__oren_fnwrap` and wrap known functions into first-class values
     - parser supports lambda syntax: `|params| expr_or_block` and `|| expr_or_block` (empty params)
     - closures (lambdas) are fully executable on the C backend:
       - auto free-var capture, **capture-by-value** (v0)
       - runtime helper `oren_closure(...)` builds a GC-managed env list
       - `spawn` lowers to `oren_spawn_call_list(...)` so closures/function-values can be spawned (not just direct symbols)
   - Remaining (still mandatory):
     - bytecode backend: represent function values + closures and implement indirect call op
     - closure capture rules + determinism (captured values, env layout) must be part of the spec
   - Status (native backend):
     - runtime supports first-class callable objects (`oren_func(code_ptr, env_ptr)`, tracked kind=6; GC marks `env_ptr`)
     - compiler collects lambdas and emits wrappers:
       - `__oren_lambda_<N>(__env, __args)` for lambda bodies + capture binding
       - `__oren_fnwrap_<name>(__env, __args)` for named functions
     - indirect calls are implemented via `blr` to the wrapper code pointer
     - `spawn` lowers to `oren_spawn_call_list(fn_obj, args_list)` so closures/function-values can be spawned
     - regression: `tests/native/test_lambda_closure_native.oren`

### Native backend (syscall-first runtime; macOS-first; production-critical)

2) **Syscall-first OS boundary must be complete enough for “real programs”**
   - Goal: native Oren can build production libraries without libc shims:
     - FS + PROC + ENV + TIME + NET are the minimum “OS substrate”.
   - Enforce via tests and by keeping everything behind `sys_*`/`oren_*` boundaries.

3) **Syscall-first PROC + ENV correctness (no libc; macOS arm64)**
   - Blocking: if PROC/ENV is wrong, `spawn`, `oren_join`, and `oren_system` can hang or misbehave.
   - Requirements:
     - `oren_system()` must pass the intended child argv (`["sh","-c",cmd]`) and must never accidentally launch an interactive shell.
     - Preserve/forward parent environment to `execve` without libc:
       - capture `envp` at entry (preferred)
       - fallback derivation from `argv/argc` is allowed only as backup
     - `oren_getenv(key)` must be bounded (never hangs if envp is malformed/unterminated).
   - Regression tests:
     - `oren_system("echo ...")` completes quickly (guard with timeout).
     - `oren_getenv(...)` returns quickly for missing keys and returns non-zero for a known-set key (when present).
     - malformed key must not hang `oren_getenv` (unterminated string pointer regression: `tests/native/test_getenv_malformed_key.oren`).
     - `sys_execve(..., envp)` overrides env and `oren_system(...)` inherits it (regression: `tests/native/test_env_execve_getenv.oren`).
     - cancellable `system` wrapper kills + reaps on timeout: `tests/native/test_system_timeout.oren`.

4) **Syscall-first TIME substrate (native; no libc)**
   - Needed for production libraries to be self-contained (retries, backoff, polling loops) and to avoid “block forever” in higher-level PROC/NET wrappers.
   - “Best option” for native (host) time is:
     - monotonic for deadlines/backoff logic
     - wall/unix time only for logging/telemetry (not for correctness)
   - Minimal v0 surface (OS boundary):
     - `sys_nanosleep(ns) -> 0_or_neg_errno`
       - macOS implementation uses `kqueue + kevent(timeout)` (no libc shim).
       - Linux implementation uses `__NR_nanosleep` (aarch64).
     - `sys_gettimeofday(tv_ptr, tz_ptr, abs_ptr) -> 0_or_neg_errno`
       - macOS syscall provides a 3rd out-param `mach_absolute_time` (used as monotonic “raw” time).
       - Linux syscall provides `gettimeofday(tv, tz)` (no abs time); pass abs_ptr=0.
   - Runtime helpers:
     - `oren_sleep_ns(ns)` / `oren_sleep_ms(ms)`
     - `oren_time_unix_ns() -> int` (wall time)
     - `oren_time_mono_raw() -> int` (monotonic raw ticks; compare-only)
   - Status: implemented + regression:
     - `tests/native/test_sleep_ms.oren` (smoke)
     - `tests/native/test_time_now.oren` (unix wall time)
     - `tests/native/test_time_mono_raw.oren` (monotonic raw; compare-only)
     - `tests/native/test_system_timeout.oren` (wait4 WNOHANG + sleep + kill + reap)

5) **Native TCP/IP syscalls (macOS arm64) — minimal, correct, cancellable**
   - Mandatory for the final product: native Oren needs real TCP/IP without libc wrappers.
   - Minimal syscall-first surface (exact naming can evolve, but keep the boundary small):
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_send`, `sys_recv`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`, `sys_getsockname`, `sys_getpeername`
     - `sys_poll`/`sys_select` or `sys_kevent` for timeouts/cancellation (macOS-friendly: `kqueue/kevent`)
   - Runtime-level API (so `.oren` stdlib can build on it):
     - `oren_tcp_connect(ip, port, timeout_ms)` (v0 can start with IPv4 dotted quad only; DNS can come later)
     - `oren_tcp_read(fd, n, timeout_ms)` / `oren_tcp_write(fd, bytes, timeout_ms)` / `oren_tcp_close(fd)`
   - Must integrate with deadlines/timeouts (no “block forever”).
   - Status (macOS): implemented syscall-first TCP core + kqueue/kevent timeouts, plus a loopback regression test:
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_sendto`, `sys_recvfrom`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`
     - `sys_kqueue`, `sys_kevent`, `sys_fcntl`
     - `.oren` helpers: `oren_tcp_connect`, `oren_tcp_listen_local`, `oren_tcp_accept`, `oren_tcp_read_into`, `oren_tcp_write_from`, `oren_tcp_close`
     - test: `tests/native/test_tcp_loopback.oren`
     - minimal HTTP GET helper built on top of TCP syscalls:
       - `oren_net_get("http://<ipv4>[:port][/path]")` (v0; no TLS/DNS/chunked)
       - regression: `tests/native/test_http_get_loopback.oren`
   - Remaining (still required by the “real stdlib NET” goal):
     - add `sys_getsockname` + `sys_getpeername` (useful for debugging/introspection) (done; regression: `tests/native/test_tcp_sockname_peername.oren`)
     - add `sys_send`/`sys_recv` first-class intrinsics (may lower to sendto/recvfrom with NULL addr) (done; regression: `tests/native/test_tcp_send_recv.oren`)
     - add Linux syscall lowering for the same surface (see P0.6)

6) **ABI hygiene for rolling native runtime globals + pointer arithmetic**
   - Blocking: silent ABI slot collisions can deadlock/hang (hard to debug).
   - Rules (must be enforced/documented):
     - Never reuse a globals slot for two unrelated purposes.
     - Prefer named getters/setters (`global_get_*`) over raw offsets.
     - In native runtime `.oren`, use `iadd(ptr, off)` for pointer arithmetic; avoid `ptr + off` when `ptr` is a pointer value.
     - Entry stub must preserve its own state across runtime calls until native codegen preserves callee-saved regs (AAPCS).
   - Status (macOS native runtime): globals layout is centralized (named offsets + reserved slack), and allocator/thread tracking uses `iadd(...)` for struct offsets (`lib/runtime_native.oren`).
   - Status (native backend ABI):
     - native backend generic calls now follow AAPCS64 arg passing: X0..X7 + stack args for arg8+, and function prologues correctly load arg8+ from caller stack.
     - regression: `tests/native/test_call_stack_args.oren` (also in Docker Linux smoke list).

7) **Native memory hygiene: libc-free allocator + no leaks**
   - Native backend must remain libc-free (no `libc malloc/free`).
   - The compiler intrinsic `malloc(...)` is an internal runtime primitive (implemented on top of syscalls); user/library code should migrate toward type-driven allocation (constructors/literals) and avoid raw `malloc` calls.
   - Enforce correctness:
     - de-duplicate tracking records (no two GC nodes may point at the same ptr)
     - keep runtime metadata (globals/thread bookkeeping) out of GC-managed allocations
     - ensure `free(ptr)` works even when GC scanning is disabled (`--no-gc`)
   - Regression: `tests/native/test_gc_reuse_tracking.oren`

7) **Linux arm64 native backend parity (mandatory; avoid divergence)**
   - The production goal includes Linux; verify early to avoid “macOS-only drift”.
   - Deliverables:
     - implement Linux syscall lowering for the same `sys_*` surface (FS/PROC/ENV/TIME + NET sockets)
     - add a script to run a Linux native smoke subset on the trusted QEMU host (`blu@qemu-blu.localc`)
     - keep a short “Linux native smoke list” of tests that cover spawn/system/env/net basics
   - Status (rolling):
     - Linux syscall lowering is started for NET socket syscalls (socket/connect/bind/listen/accept/sendto/recvfrom/getsockopt/setsockopt/getpeername/getsockname/shutdown) + `fcntl` in `lib/compiler/arm64_native_expr.oren` (numbers referenced from `docs/refs/linux_asm_generic_unistd.h`).
     - Linux PROC syscall lowering is started for fork/exec/wait: `sys_fork` uses `clone(SIGCHLD, stack=NULL)`, `sys_execve` uses `__NR_execve`, `sys_wait4` uses `__NR_wait4` (refs: `docs/refs/linux_man_clone.2`, `docs/refs/linux_asm_generic_unistd.h`).
     - Linux TIME/PROC hygiene (rolling):
       - `sys_nanosleep` uses `__NR_nanosleep` (enables `oren_sleep_ms` and polling-based timeouts).
       - `sys_kill` uses `__NR_kill` (enables “timeout => kill + reap” patterns).
     - Linux smoke runner exists (preferred on macOS): `tools/linux_native_smoke_docker.sh` (Ubuntu 24.04 `linux/arm64`, per-binary `timeout`, container reuse via `OREN_DOCKER_KEEP=1`).
     - Linux smoke runner (optional / unstable): `tools/linux_native_smoke_qemu.sh` (trusted host, but may flap; keep as backup).
     - Regression coverage (Docker smoke):
       - PROC spawn/join works: `tests/native/test_spawn_simple.oren`, `tests/native/test_spawn_args.oren`
       - TIME+PROC timeout works: `tests/native/test_sleep_ms.oren`, `tests/native/test_system_timeout.oren`
       - TCP loopback with fork works: `tools/bench/test_linux_tcp_loopback_fork.oren`

### AVM (agentic execution substrate; safety + multiverse)

7) **Capsule must be “no host effects” by default**
   - Goal: when running `avm --capsule` (untrusted), **do not touch the host** even if the bytecode requests FS/PROC/NET and you choose to allow those domains.
   - Enforce by defaulting capsule runs to Virtual* backends unless explicitly overridden:
     - `fs_backend=vfs`
     - `proc_backend=vproc`
     - `net_backend=vnet` (host NET remains not implemented in bootstrap)
   - This prevents accidental “allowed FS means host FS” mistakes in governance workflows.

8) **Virtual backends (no-host effects) for safety + multiverse**
   - Goal: allow AVM programs (and nested universes) to use FS/PROC/NET-like APIs **without touching the host** (even in “record” runs).
   - This is required for:
     - safe “Matrix” simulation (thousands of sandboxes)
     - deterministic replay across swarm nodes
     - running untrusted plugins without giving host FS/PROC
   - Clarify contract (domains vs backends):
     - capability domains define *what effect is requested* (FS/NET/PROC)
     - backends define *where it executes* (virtual vs host)
     - “virtual by default” is a policy choice (capsule/simulation), not a redefinition of the domains
   - Minimal order:
     - VirtualFS (in-memory) for FS domain (read/write string + bytes), with IO/log budgeting and deterministic behavior
     - VirtualPROC fixture backend (no real subprocesses; deterministic fixture responses) for PROC domain
     - VirtualNET fixture backend (scripted request/response) for NET domain
     - Nested-universe fixture injection as data (`cfg.vfs_fixtures`, `cfg.proc_fixtures`, `cfg.net_fixtures`)
   - Must bind the chosen backend mode + fixtures into `exec_hash_sha256` / job objects (so consensus sees “what environment was used”).
   - Nested universes must support two modes cleanly:
     - **simulation mode:** virtual backends only (default; deterministic; snapshot-friendly)
     - **live mode:** allow explicit `*_backend=host` (direct host mapping; no relay) under strict subset rules (caps/allowlists/budgets), bound into `exec_hash`

9) **Governance-ready job object (bind to program + inputs + exec context)**
   - `--print-policy*` is scan-before-execute (no bytecode execution) and now outputs a stable `policy_hash_sha256` (`schema: avm.policy.v1`).
   - Added `--print-job` / `--print-job-json` (schema `avm.job.v1`) which computes `job_hash_sha256 = H(program_hash, policy_hash, input_hash)` without executing bytecode.
   - Updated `--print-job*` to schema `avm.job.v2`: `job_hash_sha256 = H(program_hash, policy_hash, input_hash, exec_hash)` where `exec_hash` binds effective allowlists + fs prefixes + budgets + deterministic knobs.
   - Updated `--print-job*` to schema `avm.job.v4`: `exec_hash` also binds requested output surfaces (trace bytes/hash, record-log hex, snapshot-out enablement, trace limits) plus FS backend selection (`host|vfs`).
   - Updated `--print-job*` to schema `avm.job.v5`: `exec_hash` also binds PROC backend selection (`host|vproc`) and `proc_exit_code` when `vproc` is selected.
   - Updated `--print-job*` to schema `avm.job.v6`: `exec_hash` also binds NET backend selection (`host|vnet`) and `net_fixtures_hash_sha256` when fixtures are provided.
   - Updated `--print-job*` to schema `avm.job.v7`: `exec_hash` also binds VirtualPROC fixtures (`proc_fixtures_hash_sha256`) when fixtures are provided.
   - Next: treat `job_hash` as the swarm consensus key (signatures/attestations are a later layer; don’t block bootstrap).

10) **Diagnostics must not affect semantics**
   - Tracing/profiling must be best-effort and must not change VM outcome.
   - In particular: trace-bytes capture should truncate/disable on budget exhaustion (do not abort the VM).
   - Also: trace-bytes capture must not consume `AVM_MEM_BYTES` (program heap budget); it should be governed by `AVM_TRACE_BYTES` instead.

11) **Native backend control-flow correctness (break/continue)**
   - Blocking: missing `break`/`continue` causes infinite loops and can manifest as “hangs” in syscall-first runtime code (e.g. parsers, scanners).
   - Implement in native backend codegen with correct stack hygiene and loop nesting support.
   - Status (macOS native + bytecode backend):
     - native backend: `while` and `for` support `break`/`continue` with proper nesting; `continue` in `for` runs `post`.
     - bytecode backend: `while` and `for` support `break`/`continue`, and function locals are pre-allocated so var-decls inside loops don’t grow the VM stack.
   - Status (native backend locals hygiene):
     - native backend now enforces lexical block scoping for locals in codegen (restores locals bindings when leaving a block), preventing stale SP-relative offsets from aliasing later locals (critical for `if pid==0 { ... }` patterns in syscall-first code).

12) **Deterministic maps: key-ordered storage**
   - For consensus and replayability, maps must not rely on insertion order (which can vary by compilation/lowering) or pointer-based ordering.
   - Contract (v0):
     - Map keys are restricted to `nil/bool/int/string` (reject other key types).
     - Maps store keys in deterministic ascending order: `nil < bool < int < string`, with strings ordered by bytewise compare (`strcmp`).
     - Duplicate key behavior: last assignment wins.
   - Enforced in:
     - AVM map construction (`NEW_MAP`) + map set (`SET_INDEX`)
     - AVM map get (`GET_INDEX`) uses the same key contract (binary search over ordered keys; rejects unsupported key types)
     - Native runtime `oren_map_set` (string keys)
     - C runtime `oren_new_map` + map set via `oren_index_set`
   - Regression: `tests/avm/test_map_key_order.oren` compares nested-universe `state_hash` across different insertion orders.
   - Regression: `tests/avm/test_map_key_types.oren` covers `nil/bool/int/string` keys, checks `result_hash` + `state_hash` across different insertion orders.

13) **`for x in ...` must be generic (rolling iterator hook)**
   - Goal: `for <name> in <iterable> { ... }` works uniformly across backends and container types needed for stdlib work.
   - Current implementation (rolling):
     - parser desugars to a `for init; cond; post { ... }` that calls `oren_iter_next(container, idx, out_pair) -> [ok:int, value]`.
     - Implemented across:
       - native backend runtime (`lib/runtime_native.oren`): list/map/string
       - C backend runtime (`lib/runtime.c`): list/map/string
       - AVM core natives (`lib/avm/avm_native.inc` id 43): list/map/string/bytes
   - Current semantics:
     - `list`: yields elements in index order
     - `map`: yields keys in deterministic key order
     - `string`: yields byte codepoints (`0..255`)
     - `bytes` (AVM): yields u8 values (`0..255`)
   - Next (still required for the “streams everywhere” goal):
     - define an iterator/stream protocol beyond built-in containers (e.g. `Stream` type, channel receive iteration, and/or a `__iter_next` callable contract) and bind it into determinism/capabilities.

14) **Struct field immutability (portable semantics)**
   - Why it matters:
     - backends currently differ in struct representation (maps vs contiguous buffers)
     - allowing `obj.field = v` makes semantics ambiguous and risks backend-specific behavior
   - Contract (rolling):
     - `obj.field` is **read-only** field access
     - `obj.field = v` is a **compile-time error**
     - use `xs[i] = v` / `m[key] = v` for mutation (lists/maps), and construct a new struct value instead of mutating
   - Status: implemented as a parser error (fixture: `tests/native/fixtures/struct_field_assign_bad.oren`).
   - Next (design; no rewrite path):
     - introduce a persistent “update” form for structs (e.g. `p2 = p with { x=..., y=... }` or `p2 = Point(p.x, newy)`), after traits/enums stabilize.

15) **AVM call stack discipline (CALL/RET must not leak stack)**
   - Production-blocking correctness: without proper stack restoration on `RET`, even trivial function calls corrupt stack state and can grow without bound.
   - Contract (rolling):
     - `CALL addr,nargs` consumes `nargs` arguments and (on return) leaves **exactly one** value on the caller stack.
     - `RET` discards the entire callee frame (args/locals/temps) and pushes the return value for the caller.
   - Status: implemented in the AVM interpreter (`lib/avm/avm_vm.c`) with a regression `tests/avm/test_call_stack_discipline.oren`.

16) **Test suite scalability (reduce redundant compiles; keep coverage)**
   - Problem: `make test` compiles+links each `.oren` file separately; many “atomic” tests overlap and some are implicitly covered by more complex ones.
   - Goal: keep iteration velocity high while preserving correctness coverage.
   - Approach (rolling):
     - keep “atomic” tests as files (debuggable, bisect-friendly)
     - add “suite” tests that cover a whole domain in one binary (NET, TIME, PROC/ENV, etc.)
     - run a curated list by default (`make test`), and keep an escape hatch to run everything (`make test-native-all`)
   - Status:
     - added `tests/native/test_net_suite.oren` (TCP loopback + send/recv intrinsics + sockname/peername + HTTP GET loopback)
     - added `tests/native/test_time_suite.oren` (sleep + unix time + monotonic raw)
     - `make test` now runs a curated native list; `make test-native-all` runs the full glob.
     - `make test` now runs a curated AVM list (see `AVM_TESTS` in `Makefile`); override with `make test AVM_TESTS="tests/avm/*.oren"` for full AVM coverage.

17) **Native stdlib modules (syscall-first; no libc)**
   - Goal: “real code” in `.oren` should import stable modules instead of calling raw `oren_*` helpers directly.
   - Status (rolling, macOS-first):
     - added `lib/std/net/http.oren` with `http.get(url)` backed by `oren_net_get(url)`
     - native backend now supports module namespace resolution for expressions and calls (e.g. `http.get(...)`), matching the C-backend `ns_resolve` flattening convention.

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **AVM deterministic cooperative tasks (concurrency model; mandatory for agents)**
   - This is the production “agent loop” primitive: structured concurrency without OS-thread nondeterminism.
   - Implement a single-threaded deterministic scheduler first (FIFO ready queue + deterministic wake ordering).
   - Minimal surface (design in `docs/AVM_CONCURRENCY.md`):
     - spawn/join tasks
     - channels + select
     - integration with budgets + deterministic TIME + snapshot/restore

2) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.
   - Bootstrap status:
     - `avm --print-trace-hash` exists.
     - `avm --print-trace-bytes-hex` exists (hex transport).
   - Next: extend event categories (alloc/error object metadata/spans) and add a BYTES return channel (not only hex dump).

3) **Language meta-system: unified attributes (decorators + field annotations)**
   - Direction is documented in `docs/LANGUAGE_SPEC.md` (“Meta / Attributes”) and is required for:
     - user- and library-defined metadata (docs/IDE tooling)
     - governance-friendly APIs (`@cap.requires(...)`)
     - future derive-style codegen (`@derive(...)`) without “Python runtime decorator” semantics
     - AVM tooling (disasm/debug/profiling correlation) once metadata is embedded in `.obc`
   - Minimal no-rewrite implementation stages:
     - M1: parse and preserve `@attr(...)` on function/type declarations in the compiler AST (ignored for semantics). (done; regressions: `tests/native/test_attributes_noop.oren`, `tests/avm/test_attributes_noop.oren`)
     - M2: allow field/param attributes (still metadata-only). (done; regressions: `tests/native/test_attributes_fields_params.oren`, `tests/avm/test_attributes_fields_params.oren`)
     - M3: strict mode (`--strict-attrs` / env) where unknown attributes are a compile error unless declared/allowed. (done; regressions: `tests/native/fixtures/strict_attrs_ok.oren`, `tests/native/fixtures/strict_attrs_bad.oren` via `make test`)
     - M4: `.obc` metadata section (attributes + names) plus separate `meta_hash`:
       - `program_hash` remains semantics-only (code + constants), must not include inert metadata.
       - `meta_hash` covers metadata for auditing/debugging.
     - M5: surface attributes in `avm --disasm-json` / `--inspect-json` (tooling must not execute bytecode).

4) **Object model scaffolding: traits/protocols + composition (no inheritance-first)**
   - Direction is documented in `docs/OBJECT_MODEL.md` and `docs/LANGUAGE_SPEC.md` (“Object Model”).
   - Goal: make syscall-first boundaries and AVM virtualization natural:
     - define `FS/NET/PROC/ENV/TIME` as traits and pass explicit capability objects (instead of implicit globals).
   - Minimal no-rewrite implementation stages:
     - T1: `trait` declarations as compile-time contracts (no runtime rep; no dynamic dispatch yet).
     - T2: `impl Trait for Type` + static dispatch where concrete types are known.
     - T3: optional trait objects (explicit opt-in) for dynamic dispatch (plugins).
     - T4: `enum` + `match` for ADTs (agent workflow state machines), later exhaustiveness checks.

5) **NET domain contract + replay/fixture story (AVM)**
   - Keep NET semantics virtualizable and deterministic by design:
     - VirtualNET fixtures remain the default for capsules and nested universes.
     - define a canonical request shape (recommended: HTTP-ish request/response rather than raw sockets).
   - Add record/replay for NET domain (so “real host net” can be audited where allowed).
   - Ensure task scheduler integrates NET as an async/blocking op (no blocking forever).

6) **Handle delegation (fd/socket passing) — later explicit mode**
   - Do not attempt this in v0 capsule/deterministic mode.
   - If added later, it must be an explicit opt-in flag (e.g. `host_handles_allowed=1`) bound into `exec_hash`, with clear snapshot portability limits.

7) **Snapshot/restore “capsule” hardening**
   - Move toward capsule-friendly formats (hashable, resumable, policy-bound).

8) **“AVM as Oren built-in library” (libavm embedding)**
   - Mandatory for the “embed libavm + oren.obc on iOS/edge” story (`docs/OREN_EVOLUTION.md`).
   - Minimal no-rewrite path:
     - stabilize a small `libavm` C API: `avm_run_bytes(...) -> {result, hashes, record_log_bytes, snapshot_bytes}`
     - provide Oren bindings in a standard module (so Oren programs can spawn child universes without shelling out)
     - start with C-backend integration (link `libavm` into `lib/runtime.c`) and keep native-backend integration as a follow-up.

9) **Compiler-in-AVM (“source -> .obc inside a child universe”)**
   - Mandatory for closing the loop (multiverse + in-memory compilation) without a host toolchain.
   - Break into minimal milestones to avoid massive rewrites:
     - M1: get a small “compiler capsule MVP” that compiles a single-file `.oren` subset to `.obc`, using VirtualFS for IO.
     - M2: extend to imports/modules, deterministic compilation mode, and returning `.obc` as `BYTES`.
     - M3: use this path to compile AVM-facing stdlib modules inside the sandbox.

10) **Tooling: disassembler + debugger + profiler**
   - Disassembler: stable “otool-like” `.obc` inspector (sections, consts, policy, hashes).
   - Debugger: minimal “lldb-like” stepping + breakpoints + trace correlation (pc/op/stack depth).
   - Profiler: memory/time attribution surfaces that are deterministic / loggable (must not change semantics).
     - Bootstrap progress: trace stream now includes bytes-only `ALLOC/FREE/REALLOC` events (not included in `TRACE_HASH`) and `tools/avm_trace_profile.py` can decode `TRACE_BYTES_HEX` into an allocation profile JSON.

11) **Native backend concurrency: N:1 greenlets first, then N:M GMP (no shims)**
   - Keep native backend free of libc/pthreads shims for core runtime services.
   - Current v0 `spawn` uses `fork + pipe` (process-based) for correctness.
   - Next (no huge rewrite path, see `docs/NATIVE_GMP_SCHEDULER.md`):
     - N:1 stage: cooperative greenlets + explicit `yield` + non-blocking IO (kqueue/kevent on macOS).
     - N:M stage: syscall-first OS threads + parking/unparking + work stealing + GC coordination.

12) **Compile-time evaluation (“comptime”) — pure-only first**

13) **Packed struct views over bytes (network parsing; zero-allocation)**
   - Goal: parse protocol headers without allocations and without exposing UB.
   - Motivation:
     - syscall-first networking wants low overhead and deterministic semantics
     - “allocation per packet” does not scale; a view is the correct primitive
   - Contract (design target; see `docs/LANGUAGE_SPEC.md`):
     - a packed view value is `{bytes, offset}` (immutable, non-owning)
     - field reads are endian-aware and bounds-checked
     - no host-endianness or unaligned loads; semantics must be stable under interpreter/JIT/native
   - Minimal milestones:
     - PV1: define schema via attributes (metadata-only), ignored by runtime
     - PV2: add a `pack_view(TypeName, bytes, offset)` intrinsic returning a view object
     - PV3: lower `view.field` reads to `oren_bytes_get_u{N}_{be|le}` based on schema metadata
     - PV4: allow nested packed views (e.g. IPv4 header contains options slice)
   - Goal: make compilation deterministic and agent-friendly without a huge rewrite.
   - Stage C0: constant evaluation for pure expressions only (no FS/NET/PROC/ENV/TIME, no nondeterministic RNG), with explicit budgets to prevent compiler hangs.
   - Later stages (pure comptime functions, bounded reflection) can follow once C0 is stable.

13) **Unify struct semantics across backends + plan escape analysis**
   - Production semantics target:
     - pass-by-immutable-value
     - struct value is an immutable handle (pointer-sized), not a stack-cloned blob
     - compiler uses escape analysis to decide stack vs heap placement
   - Unify backend representation:
     - C backend currently lowers `struct` constructors to maps (convenient but not layout-stable).
     - Native backend uses contiguous struct buffers (`oren_alloc_struct(n_fields*8)`).
     - Bytecode backend will need a consistent model as well.
   - Networking motivation:
     - enable “packed struct view over bytes” with explicit `@be/@le` field reads as a future no-allocation parsing path.

## P2 (Next-Gen AVM Performance + Features)

1) **Typed buffers + SIMD kernels (no-JIT-first path)**
   - Implement `F32_BUF` + minimal vector ops (`dot/add/mul/reduce`) with scalar fallback.
   - This is also the recommended path for **float32** support in v0 without adding a second scalar float tag to the dynamic value model.
   - Follow-up: define fixed-width numeric types (`i32/u32/u128`, `f32/f64`) primarily as typed-buffer element types and serialization/FFI boundary types.

2) **VirtualNET / VirtualPROC backends (fixtures)**
   - Enable “Matrix sandbox” simulation and deterministic replay of realistic workflows.

3) **Codebase factoring (do only when it prevents progress)**
   - AVM core has been split into SOLID-ish C modules under `lib/avm/` (e.g. `lib/avm/avm_vm.c`, `lib/avm/avm_native.c`, `lib/avm/avm_state.c`).
   - Future factoring should continue by capability domain (NET/PROC/FS/TIME/RNG) and by deterministic surfaces (hashing/tracing/snapshot), avoiding random churn.
   - Goal: factor by capability domains and by deterministic surfaces (hashing, tracing, snapshot) rather than “random file splitting”.

4) **NET_DIAG diagnostic ops (host-only first; ICMP; later ARP/neighbor table)**
   - Keep these out of the core NET substrate (TCP/UDP/DNS/TLS); they are diagnostics and frequently have privilege / platform constraints.
   - Design direction:
     - add a separate NET diagnostic capability catalog (`NET_DIAG`) (or NET domain ops with an explicit `diag.*` naming convention).
     - expose high-level APIs (not raw packet crafting) first:
       - `ping(ip, timeout_ms) -> {ok:bool, rtt_ms:int, ttl?:int, err?:map}`
       - `traceroute(ip, max_hops, timeout_ms) -> list[...]`
     - in AVM/capsule/multiverse mode: diagnostics must be virtualized (fixtures or record/replay), never “hit the real network” unless explicitly allowed and bound into `exec_hash`.
   - ICMP:
     - include ICMP echo/time-exceeded in the diagnostic catalog (not required for v0/v1 bootstrap).
     - note: raw ICMP often requires privileges; handle permission errors deterministically.
   - ARP / neighbor discovery:
     - defer; platform-specific and often requires link-layer access (BPF-like interfaces) or OS neighbor tables.
     - if implemented later, prefer “inspect neighbor table” capability (read-only) rather than “craft ARP frames”.

## Recently Completed (for context)

- Native panic traces: add pseudo symbols for `__top_level__` (top-level statement lowering) and `__entry_stub__` (arm64 entry shim) so stack traces are readable even without an explicit `fn main()`.

## 2025-12-20 (Recent)

- `previous test runner`: added a repeated-run determinism guard for `tests/avm/test_smoke_suite.oren` (rerun scalar mode, require `RESULT_HASH` + `TRACE_HASH` match).
- Docs: clarified that AVM FLOAT constants are wired end-to-end and documented const tag `3` as float64 bit-pattern in the bootstrap spec (`docs/AVM_SPEC.md`).
- Compiler: added `///` doc comments (lexer/parser) and exported docs in metadata JSON for functions/structs/traits (covered by `tests/modules/test_metadata_attrs.oren`).

## 2025-12-21 (Recent)

- Serde/format integration: added nested arrays+maps deterministic roundtrip coverage for JSON/YAML/CBOR (`tests/modules/test_format_nested_roundtrip.oren`).

## 2025-12-21 (Archived Summary Addendum)

### Attribute system v1 + meta tooling (complete)

- Unified attribute model (decorators + field annotations):
  - ergonomic spellings like `@pack` and `@serde(...)` (no `@oren.` prefixes required)
  - dotted namespaces (`@myorg.tag(...)`) and deterministic preservation of unknown attributes in metadata
  - strict attribute mode (`--strict-attrs`, allow-prefixes) for governance/auditing
- Tooling:
  - `./oren meta` emits stable JSON metadata including `attrs` and a normalized `meta.serde` schema for serde-related annotations.
  - Deterministic meta artifact hash (`--deterministic`) is wired into `cmd/previous test runner`.

### YAML + CBOR adaptors (comments + streaming)

- YAML (`std/yaml`) supports a deterministic YAML 1.2 subset suitable for config, including comment tolerance:
  - `# ...` YAML comments (whitespace-start)
  - `// ...` and `/* ... */` (C/JSON-style) with newline preservation for stable line numbers
  - deterministic object key ordering on encode (sorted)
- CBOR (`std/cbor`) supports:
  - arrays/maps and canonical map ordering (RFC 8949 §4.2.1)
  - CBOR sequences for streaming (RFC 8742): `decode_next` / `decode_sequence` (+ typed helpers for serde)
- Tests:
  - `tests/modules/test_yaml_comments.oren`
  - `tests/modules/test_cbor_serde_streaming.oren`


---

## Archived Snapshot (2025-12-22)

This section preserves the previous contents of docs/TODOS.md before it was pruned to a short active tracker.

# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode.

This file is the *single source of truth* for what to do next.

Priority model:

- **Order = priority.** The first unfinished item is the most urgent.
- We intentionally avoid fixed labels like “P0/P1”: the list is continuously reordered as reality changes.
- Completed items are moved to `docs/TODOS_ARCHIVE.md` to keep this file readable.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).
- Roadmap driver: production **server-side HPC** requirements (Eigen/BLAS-like workloads), see `docs/HPC_SERVER_PLAN.md`.

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims for the native backend** `[arch]`
   - **Native backend output** must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - The **C backend / C AVM** may use `libc` during bootstrap (like a normal C program), until the Oren-native runtime is complete.
   - Native runtime primitives must be implemented via `sys_*` + repo-owned ABI tables + `.oren` code (no host SDK dependence).

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - If code changes: run the canonical suite (preferred) `previous test runner --target macos` (or `make test`).
   - If the change touches the **compiler itself** (`oren.oren`, `lib/compiler/*`):
     - rebuild stage1 first: `make stage1`
     - then run: `previous test runner --target macos`
   - If **docs-only** changes (only documentation files modified): tests are not required.
     - Allowed docs-only set: `docs/*`, `README.md`, `LICENSE`.

6) **Keep this file actionable** `[maint]`
   - Each item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list *short and top-down prioritized* (target ~10–20 items max); merge and archive aggressively.
   - Repo must build from a clean clone: ignore build outputs only (do not accidentally ignore source dirs like `cmd/oren/` or `cmd/previous test runner/`).
   - Test policy guard:
     - Default (fast) suite must stay **integration-first** and **small** (goal: ≤ ~3 module tests + ≤ ~8 AVM tests).
     - New fine-grained tests should go to `previous test runner --full` unless they catch a regression that cannot be represented in an integration suite.

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.
   - Do not wipe the container workspace by default; incremental builds must be possible (use an explicit clean flag when required).
   - Prefer syncing **tracked sources only** (git index) into `/work/repo` so host-built binaries never pollute the container workspace.
   - If you add new files, you must `git add`/commit them before running the docker suite (otherwise the container won't see them).
   - Forward feature flags via env (e.g. `OREN_TEST_FULL=1`) so Linux matches macOS runner behavior.
   - Remove stale build outputs (`oren`, `previous test runner`, `avm`) before running `make` to avoid timestamp skew from tar sync.

8) **Never generate `*.oren.c` next to sources** `[maint]`
   - `./oren_bootstrap build path/to/file.oren` writes `file.oren.c` next to sources; Make may then treat the source as a build target via implicit C rules.
   - Avoid running bootstrap builds on in-tree modules/tests/tools; prefer `./oren build ... -o build/...` or the curated runners (`make test`, `previous test runner`).
   - If you *did* create `*.oren.c` artifacts, delete them before running `make test` (keep `oren.oren.c` only).

9) ** Refactor in rolling **
  - when a file is over 3000 lines, refacotor to be SOLID principles applied modules
  - every 20 turns, fix the parity btw code implemented and docuemnents under docs/
  - every 10 turns, favor to prune this document of DONE tasks to TODOS_ARCHIVE.md, keep the todo list succint, if later tasks can be well deduced and tracked with context.

10) **Tests must target public tool surfaces** `[maint]`
   - Avoid importing `lib/compiler/*` inside `.oren` tests (couples tests to compiler internals).
   - Prefer using `./oren` subcommands (`build`, `meta`, etc.) and checking outputs via `cmd/previous test runner` fixtures.

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[stdlib][perf] SIMD + GEMM kernels (arm64 NEON first)**
   - Goal: keep scalar semantics; add NEON behind stable intrinsic/runtime boundaries.
   - DoD:
     - A f32/i32 matmul path that scales beyond “dot per element” while preserving deterministic k-order semantics.
     - C runtime + native runtime + AVM parity for any new kernel boundary.
     - A small correctness-only integration test (no perf thresholds) in the fast suite.
   - Next milestone (suggested):
     - Add **optional C-AVM NEON kernels** (behind build+runtime flags) for the hottest typed-buffer ops:
       - `dot_f64_4` and `gemm_f64_4x4` first (bit-exact vs scalar; preserves strict k-order).
       - then extend to `gemm_f32_4x4` and `gemm_i32_4x4` (still determinism-safe; scalar fallback remains authoritative).
   - Status (rolling, short):
      - SIMD + GEMM baseline is implemented across **native runtime + C runtime + AVM** with determinism-safe NEON fast paths where possible.
      - Bytecode/AVM now also supports f64 reduction ops (`oren_buf_dot_f64*`, `oren_buf_reduce_sum_f64*`) as native ops, so HPC-style `linalg` kernels can run inside AVM without falling back to slow per-element interpreter loops.
      - Bytecode/AVM also supports f64 elementwise ops (`oren_buf_add_f64*`, `oren_buf_mul_f64*`) as native ops for AVM-side vector math building blocks.
      - C runtime: `oren_buf_gemm_f64_4x4_slice_into` now has an optional NEON fast path (still strict-k deterministic; scalar fallback authoritative).
      - C runtime: `oren_buf_gemm_f32_4x4_slice_into` has an optional NEON fast path (vectorizes across columns with f64 lanes; still strict-k deterministic; scalar fallback authoritative).
      - C runtime: `oren_buf_gemm_i32_4x4_slice_into` now has an optional NEON fast path (wrap semantics; scalar fallback authoritative).
      - Native runtime (macOS arm64): `simd_dot_f32_ptr` is validated; `simd_dot_f32_4_ptr` / `simd_gemm_f32_4x4_ptr` are still disabled pending correctness fixes (scalar fallback remains authoritative).
      - For the authoritative implementation details and native_id mapping, see:
        - `docs/AVM_NEON_MAPPING_PLAN.md`
        - `lib/std/linalg.oren`
        - `lib/runtime_buf.c`
        - `lib/avm/avm_native.inc`

2) **[stdlib][net] Native networking foundations**
   - DoD:
     - Minimal syscall-first TCP + UDP surface (connect/listen/accept/read/write, sendto/recvfrom) + readiness wait abstraction (`kqueue` on macOS; `epoll` on Linux).
     - Clear separation between VirtualNET (pure) and HostNET (capability-gated).
   - Current rolling note:
     - Added `std/net/tcp` module (`lib/std/net/tcp.oren`) exposing the syscall-first TCP substrate as a stable stdlib surface.
     - Added `std/net/udp` module (`lib/std/net/udp.oren`) exposing the syscall-first UDP substrate (loopback bind + send/recv with timeouts).
     - `std/net/http` now implements `http.get_text(url, timeout_ms)` on top of `std/net/tcp` (no hidden runtime-only helper).
     - Multi-fd readiness wait is available via `oren_fd_wait_any_{readable,writable}` (kqueue on macOS, epoll on Linux), and wrapped by `tcp.wait_any_{readable,writable}`.

### B) AVM (evolves alongside language/compiler)

1) **[boot][arch] Compiler-in-AVM v2: hash-addressed artifacts + governance hooks**
   - DoD:
     - `.obc` artifacts are content-addressed and verifiable (hash IDs + manifest).
     - Governance hooks exist for module load policies (capsule-style).
     - Still no host FS effects when running compiler in a child universe (VirtualFS only).
   - Current rolling note:
     - `oren build` / `oren meta` now support `--manifest` to emit `<out>.manifest.json` with a stable `sha256` record (use with `--deterministic` for content-addressed builds).
     - When `oren build --backend native --metadata` is used, `--manifest` also emits a manifest for the metadata sidecar (`<out>.meta.json.manifest.json`).
     - `previous test runner` has integration fixtures that assert `--manifest` output exists (and includes `size_bytes`) for bytecode builds, `oren meta`, and native `--metadata` sidecars.
     - Manifests now include `size_bytes` (deterministic) to support artifact caching/GC.

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][serde] Serde adaptors: tighten v1 surfaces**
   - Goal: keep the current JSON/YAML/CBOR v1 useful for real apps without pulling in a heavy toolchain.
   - DoD:
     - JSON/YAML decode: comment tolerance stays deterministic (already supported); improve diagnostics on malformed inputs.
     - CBOR: keep canonical map ordering and RFC 8742 sequence support; add roundtrip fixtures for nested shapes.
     - Ensure serde-generated helpers cover nested arrays/maps and preserve deterministic ordering.

## Snapshot Notes (Rolling)

- 2025-12-28: `docs/TODOS.md` was condensed back to a short “active tracker” (per its own header). The prior expanded tracker remains available via git history (commit `3580ebb` and earlier).
- 2026-01-03: C backend runtime gained unsafe pointer primitives (`ptr_get/ptr_set/ptr_get_byte/ptr_set_byte`) exposed as first-class function values for compiler/tooling hot paths; astbin decode now pins its input via `oren_gc_pin` for GC robustness under the native backend.
- 2026-01-04: Compiler backends now share the growable byte builder implementation (`lib/compiler/bytes_builder.oren`), reducing arm64/x64 drift; native quick integration asserts embedded string literals do not increase GC roots and are pointer-deduped.
- 2026-01-04: `make stage2` now bootstraps `./oren_stage2` via the native backend on macOS arm64 by default (override with `OREN_STAGE2_BACKEND=c` for bring-up).
- 2026-01-04: Native `oren_read_u8_buf` now returns structured errors on ENOENT instead of exiting, so stage2-native runtime-object cache probing no longer terminates the compiler on cold cache misses.
- 2026-01-04: Stage1 C runtime `ptr_get/ptr_set` now use `memcpy` for 64-bit loads/stores to avoid UB on unaligned addresses (arm64 correctness; used by compiler hot paths).
- 2026-01-04: Runtime-object cache load now has a cheap sentinel integrity check (and opt-in full validation) so corrupted/stale rtobj meta becomes a cache miss (rebuild) instead of a stage1 panic during x64 codegen.
- 2026-01-04: x64 PE/ELF fixup patching now uses a fast `bytes_set_u32_le` path (single bounds check + raw stores), bringing `scripts/verify_native_x64_compile_only.sh` stage2 `x64-windows` under the default 10s timeout on the primary dev host.
- 2026-01-04: Fixed a Tier‑1 cross‑arch bring‑up crash: arm64-linux native binaries could segfault during early `native_runtime_init` because the `malloc_raw` intrinsic could return invalid pointers on that target.
  - Added `lib/runtime_native/015_raw_alloc.oren` with `native_malloc_raw_or_mmap(size)` (validates `malloc_raw`, falls back to `sys_mmap_private_anon`).
  - Switched early raw allocations in `native_runtime_init` and Win envp construction to use the validated raw allocator.
  - Result: `scripts/verify_native_matrix.sh --targets local,arm64-linux` now builds and runs stage1 + stage2 artifacts in the Linux/arm64 container without crashing.
- 2026-01-04: Hardened arm64 native `malloc`/`malloc_raw` lowering: after the `mmap` slow path, reject any “pointer” result `< 4096` and fail-fast.
  - This prevents a wrong syscall number / clobbered syscall register from returning a small positive integer (e.g. 15) that would later be treated as a pointer and segfault.
