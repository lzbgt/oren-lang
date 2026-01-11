# Native Backend Performance Playbook (Rolling)

This document is a **practical guardrail** for keeping Oren’s **self-hosted stage2 native compiler** fast and diagnosable.

It is written for “I changed something and now `oren build` took >10s” incidents.

## 1) Non-negotiable performance gates (primary dev host)

These are rolling “red line” bounds used to catch fundamental regressions early:

- **Stage2 native backend: compile-one-file (rtobj hit)** must stay **< 4s** wall time.
  - Measured with: `./scripts/bench_native_compile_one_file.sh` (second run is the hit).
  - Regression tripwire (recommended): `./scripts/perf_guard_native_compile_one_file_hit.sh`
- **Tier‑1 debug builds** used by fixtures should stay **< 10s** per `oren build ... --backend native --debug` step.
  - Default bounded timeout is enforced by the verification scripts (`OREN_NATIVE_BUILD_TIMEOUT_SECS`, default `10`).
- **Self-host compiler build** (`make stage2` / `make verify`) must stay **< 3 minutes** wall time on the primary dev host.

If any of these regress, treat it as a **fundamental hot-path flaw**, not something to “tune with flags”.

## 2) First response: reproduce with bounded tools

Use these first because they are bounded and don’t produce huge logs.

### 2.1 Quick throughput check: compile one file (miss → hit)

```bash
# Uses an isolated runtime-object cache dir so you see a miss then a hit.
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 ./scripts/bench_native_compile_one_file.sh --no-debug
```

Note:

- The benchmark script disables the rtobj “seed” fallback (`OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0`) so it measures a true miss → hit.
  - For real user experience, it is recommended to keep a seed available (see `make rtobj-seed`).
  - For cross-target x86_64 sanity on arm64 hosts, generate seeds with `make rtobj-seed-x64` so compile-only gates stay bounded on a clean cache.

Optional (rolling): reduced runtime profile for bounded cold misses

If you are diagnosing the **cold miss** cost (rtobj build) and want a smaller baseline that more closely matches
“typical programs”, you can use the reduced runtime profile:

```bash
OREN_NATIVE_RUNTIME_PROFILE=core \
  OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0 \
  OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
  ./scripts/bench_native_compile_one_file.sh --no-debug
```

Note (rolling default): when `OREN_NATIVE_RUNTIME_PROFILE` is unset (or `auto`), the compiler already prefers the
core runtime for programs that do not import `std:net/*`, and escalates to the full runtime for networking programs.

Optional bounded tracing:

```bash
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
  OREN_TRACE_RUNTIME_BUNDLE=1 \
  OREN_TRACE_RUNTIME_OS_PRUNE=1 \
  OREN_TRACE_RUNTIME_OBJ_CACHE=1 \
		  OREN_TRACE_ASTBIN=1 \
		  OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1 \
		  OREN_TRACE_X64_RT_OBJ_SUMMARY=1 \
		  ./scripts/bench_native_compile_one_file.sh --no-debug
```

### 2.1.1 Bounded phase timing: `read_ms/parse_ms/link_ms/emit_ms`

When a build is “slow”, the first question is: **which phase is slow**?

Use the build-summary tracer (it prints a single line per build):

```bash
OREN_TRACE_BUILD_SUMMARY=1 OREN_TRACE_BUILD_SLOW_MS=0 \
  ./oren_stage2 build tests/native/test_http2_headers_loopback.oren \
  --backend native --platform arm64-macos --no-debug -o build/tmp/http2_headers
```

Interpretation (rolling):

- `read_ms`: reading the entry source + trivial scaffolding
- `parse_ms`: parsing the entry file itself (not the full module closure)
- `link_ms`: `link_program(...)` (module discovery + import scanning + module parsing + type passes)
- `emit_ms`: backend emission (native assembler/linker + artifact write)
- `codesign_ms`: macOS codesign (usually tiny unless keys/cert prompts misbehave)

If `link_ms` dominates and you are using the **native runtime** (stage2 backend), keep in mind:

- Native runtime `spawn` is fork-based today, so “parse workers” cannot return pointer-heavy ASTs.
- By default, the compiler disables fork-parallel module parsing because the ASTBIN bounce is I/O-heavy.
- For large stdlib graphs (TLS/HTTP/2/HPACK), **forcing fork-parallel parsing** is often still a net win.

Enable it explicitly:

```bash
OREN_PARSE_JOBS=8 OREN_PARSE_FORK_PARALLEL=1 \
  OREN_TRACE_BUILD_SUMMARY=1 OREN_TRACE_BUILD_SLOW_MS=0 \
  ./oren_stage2 build tests/native/test_http2_headers_loopback.oren \
  --backend native --platform arm64-macos --no-debug -o build/tmp/http2_headers
```

Notes:

- This uses `build/tmp/parse_modules/` as a deterministic temp directory for worker-produced ASTBIN blobs.
- On Windows hosts, the compiler forces parse jobs to `1` because `spawn` is thread-based and the runtime GC is not thread-safe yet for parallel parsing.

Notes on the tracers:

- `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` prints a **single-line breakdown** of the rtobj build (parse/decode, decl compile, finalize, counts/bytes).
  - Use it to decide whether to optimize astbin decode vs runtime decl compilation.
- `OREN_TRACE_X64_RT_OBJ_SUMMARY=1` provides the same style of breakdown for x86_64 (useful for cross-target misses).
- `OREN_TRACE_{ARM64,X64}_RT_OBJ_TOP_DECLS=1` prints a **bounded** “top decls” list (slowest N decls by compile time).

### 2.2 Cross-arch sanity (native backend)

- Local + container + remote matrix:
  - `./scripts/verify_native_matrix.sh`
- Local compile-only x64 sanity (stage1 + stage2 emit):
  - `./scripts/verify_native_x64_compile_only.sh`

### 2.2.1 Local x64-linux “run” sanity via qemu (no remote/WSL required)

When bringing up x86_64 runtime behavior from an arm64-macos dev host, you can run the emitted x64-linux ELF under qemu in the existing Ubuntu toolchain container:

```bash
# Build x64-linux ELF (host compiler is still arm64-macos).
./oren_stage2 build tests/native/print.oren \
  --backend native --platform x64-linux --no-cache --no-debug \
  -o build/tmp/print_x64_linux

# Copy + run under qemu inside the already-running toolchain container.
#
# If the container is currently stopped (Exited), restore it with:
#   docker start c7e5f7bd9f5c
docker cp build/tmp/print_x64_linux c7e5f7bd9f5c:/tmp/hostbins/
docker exec c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && chmod +x print_x64_linux && qemu-x86_64 ./print_x64_linux'
```

Debugging with gdb stub (bounded, no huge logs):

```bash
docker exec c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && qemu-x86_64 -g 1234 ./print_x64_linux'
# In another terminal:
docker exec -it c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && gdb-multiarch -q ./print_x64_linux'
```

### 2.2.2 x64 self-host compiler “run” gate (remote Win11 + WSL2)

Once basic x64 binaries run, Tier‑1 parity still requires the **compiler binary itself** to run on x86_64:

- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`

If the gate fails with an early exit and no diagnostics, treat it as a “tooling contract” issue first:

- The compiler’s build cache probes optional files; missing files must be surfaced as **error maps** (via `oren_err(...)`), not process exit.
  - A common regression is `oren_read_file(...)` / `oren_read_u8_buf(...)` hard-exiting on ENOENT.
- For “silent” failures on x64-linux, prefer a bounded syscall trace to find the last OS call:
  - `qemu-x86_64 -strace ./oren_selfhost_x64_linux ...` (then inspect only the last ~50 lines).

## 3) What “slow” usually means (native backend)

In practice, “compile one file is slow” is almost always one of:

1) **Runtime bundle overhead** (native backend injects `lib/runtime_native.oren` into every program):
   - runtime expansion (`// @include`) and parsing
   - runtime astbin decode (multi-megabyte blobs)
   - runtime OS pruning (`if g_target_os == ...`) and cache hygiene
2) **Runtime object miss** (cold path):
   - compiling hundreds of runtime decls + fixups
3) **Emitter hot loops**:
   - per-byte pushes into code/data buffers
   - fixup patching patterns that do O(N) tiny writes

The bounded tracing knobs in `docs/BUILD_AND_VERIFY.md` are designed to tell you *which bucket* you’re in without spamming.

## 4) The biggest performance footguns we hit (and how to avoid them)

### 4.0 Runtime astbin cache hygiene (pruned runtime)

The compiler caches the expanded+parsed native runtime under `build/cache/native_runtime_astbin/`.

Rolling policy:

- Per-target-OS cache files use suffixes like:
  - `*_os_macos_pruned3.astbin`
  - `*_os_linux_pruned3.astbin`
- These are expected to already have dead `g_target_os` branches pruned.
  - The pruned program is marked with:
    - `__oren_pruned_target_os_id`
    - `__oren_pruned_target_os_kind="g_target_os"`
    - `__oren_pruned_target_os_cache_gen` (bump when pruning behavior changes)
- If you see runtime OS pruning happening on an astbin cache hit (`OREN_TRACE_RUNTIME_OS_PRUNE=1`),
  treat it as a stale/unpruned cache file. The compiler will attempt a best-effort rewrite, which can
  be expensive once. After rewrite, runtime astbin decode should be materially faster.
- Cache robustness (rolling):
  - The runtime astbin cache decode path performs a best-effort structural sanity check on decoded blobs.
    If the decoded program looks corrupted/stale (common symptom: later crashes like “string_len expects string”),
    the compiler treats it as a cache miss and falls back to seeds or runtime source parsing.
  - If you see repeated “miss (sanity check failed)” behavior, clear caches with `./oren clean` (or delete
    `build/cache/native_runtime_astbin/` if you’re iterating on compiler internals).

Seed (rolling, optional):

- A runtime-astbin seed dir can avoid stage2-native “cold parse” costs when the astbin cache is empty:
  - env: `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=<dir>` (default: `build/cache/native_runtime_astbin_seed/`; disable with `0`/`false`)
  - generator: `make astbin-seed` (uses stage1 `./oren` to pre-warm and copy seed files)
  - cross-target seeds: `make astbin-seed-x64` (generates `x64-linux`/`x64-windows` pruned astbins so cross-target verification stays bounded when runtime hashes change)
- Seed correctness note (rolling):
  - The runtime astbin cache basename uses a fingerprint of the **expanded runtime source** (`_rt_bundle_runtime_fingerprint_v2(expanded_runtime_src)`), which is intentionally distinct from the runtime-object cache hash (`rtobj_runtime_hash(...)`).
  - To avoid “seed dir exists but stage2 still cold-parses”, `scripts/build_runtime_astbin_seed.sh` writes a per-OS meta file (`.runtime_astbin_seed_meta_os_<os>.txt`) that invalidates the seed when either:
    - runtime source inputs change (hash of `lib/runtime_native*.oren` + `lib/runtime_native/**/*.oren`), or
    - the chosen seed compiler binary changes (sha256 of `--compiler`).

Runtime OS pruning note (rolling):

- The runtime pruner can also splice away **top-level** `if g_target_os == ... { ... }` blocks, but only when the condition is provably constant for the target platform.
  - This is intended for large OS-specific helper suites (e.g., Windows CreateProcessA helpers) so non-target builds do not pay for compiling dead runtime decls.
  - Constraint: after pruning, the top-level must still contain **only** `Function` / `ExprStmt(Function)` / `Var` / `Type` / `FFI` statements.
    - If a top-level OS-guard cannot be proven constant, the runtime bundle validator will still reject it as “top-level executable code”.

### 4.0.1 Don’t use `nil` as a tri-state sentinel in compiler passes (native backend)

Some compiler passes want a tri-state “true / false / unknown”.

In the native backend, **do not** use `nil` to mean “unknown” if the result is later compared with
`== false` / `!= true`-style checks: under the current native value model, `nil` can collapse into
the same immediate as `false`/`0`, which can silently flip pruning decisions.

Preferred pattern: return an explicit integer state (`1=true`, `-1=false`, `0=unknown`) and compare
it with exact integer tests.

### 4.0.2 rtobj cache meta must be stable across stage1 and stage2

The runtime-object cache (`build/cache/native_runtime_obj/`) is shared across:

- **stage1** compiler runs (C runtime)
- **stage2** compiler runs (native runtime)

Rolling rule:

- Any validation of rtobj meta against the cache key must be **runtime-agnostic**.
  - Avoid relying on subtle runtime differences like “string equality” semantics or substring allocation behavior.
  - Prefer byte-wise key parsing and byte-wise string comparisons in the rtobj cache module when correctness matters.
 - rtobj fixups must preserve enough information to be relocatable safely.
   - Example hazard: arm64 `adr_data` fixups that target a non-`x0` register (e.g. `x9` scratch) must carry the destination register through the rtobj meta.
     - If the reg is dropped, the final fixup applier defaults to `x0` and the resulting runtime code can dereference an uninitialized register (common symptom: startup `EXC_BAD_ACCESS` at address `0x1000`).
   - Rolling rule: if you change rtobj meta encoding/decoding, bump the rtobj backend signature so stale cache entries are not reused.

If this regresses, it typically shows up as:

- `make verify-native-x64-compile` timing out because stage2 treats a valid stage1-generated cache entry as a miss and rebuilds the runtime object.

### 4.0.3 Varargs must be packed exactly once (`__oren_fnwrap_*` recursion hazard)

The native backends use synthesized wrapper functions (`__oren_fnwrap_*`) so a named function can be passed as
a uniform callable object.

Key contract:

- A wrapper already receives a pre-packed `rest_list` for varargs calls.
- The wrapper should forward that list directly (it must not “re-pack” varargs inside the wrapper body).

If call lowering tries to pack varargs again inside a wrapper, you can get:

- infinite recursion through the callable ABI (often reported as `call depth exceeded`), or
- subtle arg shape corruption (nested rest lists).

### 4.0.4 Embedded string literals must stay untracked (cstr0 pool)

Native backend model (rolling):

- String literals (e.g. `"hello"`) are emitted into a single constant/data-section byte pool (`cstr0`).
- Those pointers are valid “string values” but they are **not GC-managed heap allocations**.
- The runtime recognizes literal pointers via a startup-built membership set:
  - `oren_init_static_cstr0_table` populates the set
  - `native_is_string_ptr` / `oren_is_string` consult it

Why this matters for performance:

- If literals become tracked as alloc nodes, GC conservative scans start treating “every literal pointer” as an object:
  - mark work explodes (compiler workloads have many literal keys),
  - startup costs can spike (tracking metadata nodes per literal),
  - and regressions can manifest as “compile one file took seconds/minutes”.

Guardrails + regressions:

- The runtime treats attempts to track cstr0 literals as a no-op:
  - `oren_track_alloc(lit, ..., kind=STRING)` must not create a node
  - `oren_track_static(lit, kind=STRING)` must not create a node
- `make test` includes a regression that asserts:
  - identical literals are pointer-equal (`lit0 - lit1 == 0`),
  - and `oren_find_node(lit) == 0` (no tracking metadata for literals).

If you see a perf regression around GC/marking:

- First, re-run the bounded compile-one-file check:
  - `./scripts/bench_native_compile_one_file.sh --no-debug`
  - `./scripts/perf_guard_native_compile_one_file_hit.sh`
- Then, treat “literals being tracked” as a prime suspect and confirm the invariant via the quick integration binary
  (it prints bounded failure logs on mismatch).

Rolling guardrail (implementation):

- The fnwrap synthesis marks the internal call as “already packed”:
  - `packed_call["__oren_varargs_packed"] = 1`
- The x86_64 call emitter skips varargs packing when that marker is present.

Regression gate:

- `make verify-tier1` (or `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1`) runs a Tier‑1 fixture that exercises varargs + spread across stage1+stage2 on real x86_64.

### 4.1 Per-byte helper calls in tight loops

Stage2-native compiler workloads can decode or emit **millions of bytes**. If the code does:

- one function call per byte (`load_u8`, `push_u8`, etc), or
- repeated “header lookups” inside a byte loop,

then a “normal” 1–3MB operation can become **multiple seconds**.

Preferred patterns:

- When decoding from a `u8_buf`, materialize a raw pointer once:
  - `data_ptr = oren_buf_data_ptr_unchecked(buf)`
  - read bytes with `ptr_get_byte(iadd(data_ptr, off))`
- When emitting bytes, prefer bulk little-endian push helpers that do:
  - **one capacity check**, then raw stores (`ptr_set_byte`) for the N bytes.

See:
- `lib/compiler/compiler/015_astbin.oren` (decoder hot path)
- `lib/compiler/bytes_builder.oren` (shared byte builder)
- `lib/compiler/x64_core.oren` (x86_64 instruction encoder; uses a reusable scratch pool to avoid per-instruction allocations)

Rolling rule (x64 encoder):

- Do not allocate a fresh byte builder (or `list<int>`) per instruction.
  - Prefer `_insn_pool_get()` inside `insn_*` helpers and avoid `bytes_lit([..])` list literals in hot paths.
  - Symptom: x64 rtobj cold miss becomes tens of seconds on stage2-native cross-target builds.

### 4.2 Overloaded arithmetic in hot loops (`+` vs `iadd`)

In Oren, `+` is a language-level operator that may involve dynamic dispatch/boxing depending on value kinds.

In very hot compiler-internal loops (decode/emit), prefer intrinsic integer add:

- `iadd(a, b)` instead of `a + b`

This is especially important when the loop variable or offsets are updated per-iteration.

### 4.2.1 Avoid string-aware compare recursion in alloc-index internals (`==/!=`)

Some native backends lower `==/!=` to a **string-aware compare** that consults tracking metadata
(so `"a" == "b"` compares contents, not pointer identity).

This becomes a correctness hazard inside the runtime alloc-index itself, because:

- string-aware compare consults tracking via `native_alloc_index_get(...)`, and
- alloc-index internals also need to compare pointers/slots/tombstones.

If alloc-index code uses `==/!=` between non-constant values (e.g. `slot != tomb`, `ptr_get(node) == ptr`),
it can **indirectly recurse back into `native_alloc_index_get(...)`** and stack overflow during early init.

Guardrail patterns (Tier‑1):

- Prefer compare-to-0 arithmetic:
  - equality: `if (a - b) == 0 { ... }`
  - inequality: `if (a - b) != 0 { ... }`
- Keep tombstone sentinels small and non-zero:
  - `g_alloc_index_tomb` must be non-zero and `< 4096`, and should be set in `native_runtime_init`
    (do not rely on global initializers).

Reference implementation:

- `lib/runtime_native/100_time.oren` (alloc-index internals use arithmetic compares)
- `lib/runtime_native/020_fork_runtime_init.oren` (init sets `g_alloc_index_tomb`)

### 4.3 Avoid huge logs (they hide the signal)

When diagnosing perf regressions:

- Prefer single-line summaries (`OREN_TRACE_BUILD_SUMMARY=1`)
- Prefer targeted tracers for the suspected subsystem:
  - runtime bundle: `OREN_TRACE_RUNTIME_BUNDLE=1`
  - astbin: `OREN_TRACE_ASTBIN=1`
  - rtobj cache: `OREN_TRACE_RUNTIME_OBJ_CACHE=1`

If you need deeper info, add **bounded** counters/phase timings rather than printing every event.

### 4.4 Build cache key computation (don’t let it dominate builds)

`oren build` computes a content-addressed **build cache key** *before* doing any expensive compilation work.

If `cache key compute` is taking seconds, the compiler will feel “hung” even though the backend is fine.

Practical workflow:

- Run with bounded tracing:
  - `OREN_TRACE_BUILD=1 oren build ...`
- Look for:
  - `[build] cache key compute +...ms`
  - `[cache] injected_runtime_hash +...ms ...`

Typical root cause:

- The native backend injects `lib/runtime_native.oren` into every program, and the build cache key includes a hash of the injected runtime include-closure.
- If the scan cache is not persisted (or is persisted via an O(n²) string concat path), the compiler ends up re-walking that closure on every `oren build` invocation.

Policy (rolling):

- The runtime include-closure hash should be **milliseconds** on a warm cache (`build/cache/scan_cache_v3.txt`).
- If you need an emergency bypass while diagnosing, use `--no-cache` (but treat a multi-second cache-key as a bug to fix, not a “flag to keep”).

### 4.5 Compiler code must remain cross-runtime portable (stage1 vs stage2)

The compiler implementation is executed in multiple runtime modes:

- **Stage1** typically runs under the **C backend runtime**.
- **Stage2** runs under the **native runtime**.

Rolling rule:

- Avoid assuming a specific low-level value layout in compiler-side helpers (especially for strings).
  - Example footgun: using `ptr_get_byte(...)` directly on a “string” value inside compiler code can work under the native runtime but break under stage1 if the C backend’s string representation differs.
  - Prefer portable helpers (`oren_string_len`, `strcmp`, etc.) unless the code is explicitly guarded to run only under one runtime model.

### 4.6 Intrinsic temp spill slots: never materialize `$tmp_intrN` identifiers in hot paths

The x64 native backend uses an **intrinsic temp pool** to safely spill values while lowering nested intrinsic calls.

Perf + robustness rule (rolling):

- Do **not** construct `{"type":"Identifier","value":"$tmp_intrN"}` AST nodes inside lowering helpers.
  - It causes:
    - per-use string allocation churn (`"$tmp_intr" + int_to_string(n)`), and
    - per-function locals-map inserts for every intrinsic temp slot.

Current contract (x64 native v0):

- Intrinsic temp references must use the compiler-internal node:
  - `{"type":"IntrTmp","idx": <int>}`
- The function prologue reserves a contiguous spill region and records:
  - `ctx["intr_tmp_base_off"]` (RBP-relative base offset, slot 0)
  - Slot 0 is reserved; intrinsic temp indices start at **1**.
- `_intr_tmp_off(ctx, locals, idx)` computes:
  - `off = intr_tmp_base_off + idx*8`
  - using `iadd` only (stage1-safe; avoids slow generic `*` / `<<` lowering in the C runtime).

If you see compiler-side errors like `missing intrinsic temp slot $tmp_intr...`, it usually means:

- some lowering path reintroduced `$tmp_intrN` identifiers (regression), or
- a function codegen path forgot to set `intr_tmp_base_off` before lowering.

### 4.7 Native runtime value semantics: never use `0` as an “optional” sentinel

Rolling rule (stage2-native robustness):

- The native backend has historically used an untagged “i64 carrier” model where `nil/false/0` can alias in compare paths, so `0` is *not a safe sentinel* for “missing/absent” in compiler-side structures.
  - Mitigation (2026-01-09): the optimizer folds type-mismatched `==`/`!=` on literals and folds `id == nil` for locals proven non-nil, but this does **not** make `0` a safe “optional” sentinel in general (values flowing through maps/fields/params still carry the raw value).
- If a helper uses a pattern like `if x == nil { ... }` or `if x != nil { ... }`, and some caller legitimately sets `x = 0`, it can still skip or take work incorrectly in native mode.
- Related footgun: **do not encode booleans as `0/1` ints.**
  - In Oren, `0` is truthy; only `nil` and `false` are falsey.
  - Predicate helpers must return `false`/`true` (e.g. `oren_is_err(v) -> bool`, `oren_is_done(handle) -> bool`), and callers must not write `== 0` / `!= 0` checks against boolean results.

Two concrete pitfalls we’ve hit in the x86_64 backend:

- **x86_64 ModRM/SIB encoding requires `disp8=0` bytes.**
  - `[rbp]` / `[r13]` addressing needs `mod=01` + `disp8=0`.
  - If an encoder returns `{ "disp8": 0 }` as an “optional byte”, and later code checks `if disp8 != nil`, the byte can be omitted (because `0` aliases `nil`), shifting the instruction stream and producing a binary that crashes at entry.
  - Fix pattern: encode `disp8` as `disp8+1` in the returned dict, and decode at emission time (`enc["disp8"] - 1`).
- **Intrinsic temp spill allocator must not return base index `0`.**
  - Use 1-based indices (reserve slot 0) so `base==0` never aliases “no base”.

Regression gates:

- `./scripts/verify_native_x64_compile_only.sh` checks:
  - Windows PE prologue bytes include the required `disp8=0` byte (and rejects the known-bad omission pattern)
  - Windows PE Export Directory contains expected exported symbol names (for `--lib` DLL outputs and `@ffi.export` on EXE)
    - Rationale: `strings`/byte searches are insufficient; exports must be present in the PE export table.
    - Implementation: `scripts/pe_exports_check.py` (no external deps; parses PE32+ export directory)
  - stage1 + stage2 compilation of `tests/native/print.oren` embeds `hello from native` into the output binary for `x64-linux` and `x64-windows` (guard against call/arg evaluation regressions).

### 4.8 x86_64 self-host compiler builds: avoid per-call string allocation in hot paths

Symptom:

- Cross-target builds of the compiler itself can look “hung” when building x86_64 compiler binaries:
  - `./oren_stage2 build oren.oren --backend native --platform x64-linux ...`
  - `./oren_stage2 build oren.oren --backend native --platform x64-windows ...`
- The usual failure mode is **one pathological function** dominating codegen time.
  - This can appear as “stuck at 100% CPU” with no output for minutes.

Diagnosis (bounded; do not dump the world):

- Use the x64 compile progress tracer:
  - `OREN_TRACE_X64_COMPILE_PROGRESS=1`
  - `OREN_TRACE_X64_COMPILE_STRIDE=1000` (print every 1000 functions)
  - `OREN_TRACE_X64_COMPILE_FOCUS_FROM=<i> OREN_TRACE_X64_COMPILE_FOCUS_TO=<j>` (only print a narrow range; useful when you already know the bad region)
  - `OREN_TRACE_X64_SLOW_FN_MS=2000` (prints `slow_fn` lines)
- For one known-hot function, add a per-function breakdown:
  - `OREN_TRACE_X64_FN=<exact function name>`
  - Optional deep emit tracing (still bounded): `OREN_TRACE_X64_FN_EMIT_OPS=1` with `OREN_TRACE_X64_EMIT_OPS_STRIDE=<n>`

Fix pattern (root cause class we’ve hit in self-host builds):

- **Do not allocate strings in per-call classification hot paths.**
  - Example footgun: using `oren_string_slice(...)` to check name prefixes/suffixes inside the x64 call emitter.
  - When compiling the compiler, large backend helper functions contain *many* calls, so tiny per-call allocations become a multi-minute stall.
- Prefer byte-prefix checks via `oren_string_byte_at_unchecked(...)` for:
  - `oren_` detection
  - `oren_buf_` prefix / `_buf_new` suffix checks
- Avoid paying “runtime call classification” chains for non-`oren_*` internal helper names (encoder helpers, backend emitters, etc); route these calls directly through the generic call path when safe.

Measured improvement (arm64-macos host, 2026-01-06):

- Before: `./oren_stage2 build oren.oren --backend native --platform x64-linux --no-debug` was still compiling after ~11m and was manually interrupted.
- After fixing the per-call allocation patterns in x64 call emission, the same build completed successfully in ~7m30s, and previously-pathological compiler functions dropped from “minutes” to “~3s” each (see `docs/TODOS_ARCHIVE.md`).

## 5) GC + string literal policy (perf + correctness)

String literals in native output are **pooled and embedded** in the binary’s data segment (cstr0 pool).

Key properties (rolling contract):

- identical literals should be pointer-deduped in the embedded pool
- the runtime initializes the embedded literal membership set once at startup (`oren_init_static_cstr0_table`)
- literals are **not GC-managed heap allocations** and are not tracked as alloc nodes
  - `oren_find_node(lit_ptr)` returns `0` (no per-literal tracking nodes)
  - string classification uses `native_is_string_ptr` / `oren_is_string` which recognize `cstr0` literals without GC tracking

This is tested in the native quick integration suite (`tests/native/test_quick_integration_native.oren`).

## 6) How to keep regressions from coming back

If you touch compiler hot paths (astbin decode, native emit, runtime injection), do this before merging:

1) Run:
   - `make verify-native-quick`
   - `./scripts/verify_native_x64_compile_only.sh`
   - If the change touches FFI / networking / TLS providers, also run:
     - `./scripts/verify_native_net_matrix.sh`
     - `./scripts/verify_windows_stage2_from_stage1.sh` (catches Win-only stage1->stage2 regressions)
2) Run the bounded perf check:
   - `OREN_NATIVE_BUILD_TIMEOUT_SECS=60 ./scripts/bench_native_compile_one_file.sh --no-debug`
3) If you see “rtobj miss” > 10s, re-run with tracing and identify the dominant bucket:
   - `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` (arm64) prints one `[arm64_rtobj] ...` line with parse/decl/finalize timings.
   - `OREN_TRACE_ARM64_RT_OBJ_TOP_DECLS=1` (arm64) prints a bounded “top decls” list to spot unusually-slow runtime declarations.
   - `OREN_TRACE_ASTBIN=1` prints `[astbin] decode done +...ms` for the runtime bundle decode.
   - runtime expand/parse
   - astbin decode
   - runtime decl compilation
   - emit/fixups

Healthy reference (arm64-macos stage2, rolling as of 2026-01-10; isolated rtobj dir, seed disabled):
- rtobj miss compile-one-file: ~`3.4s`
- rtobj hit compile-one-file: ~`0.5s`

If the slow path is “expected” (cold cache), consider whether we should:

- improve caching, or
- reduce decode/emit overhead, or
- change the representation so the cold path does less work.

## 7) Future direction (high leverage)

The long-term fix for “runtime bundle dominates cold builds” is to reduce the amount of graph materialization:

- decode into a compact representation closer to the backend’s needs (or persist the lowered runtime form)
- keep fast paths **zero-copy** where possible
- avoid pointer-heavy AST graphs crossing boundaries unless necessary

Track active work in `docs/TODOS.md`.
