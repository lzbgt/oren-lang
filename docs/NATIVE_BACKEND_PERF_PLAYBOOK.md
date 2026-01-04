# Native Backend Performance Playbook (Rolling)

This document is a **practical guardrail** for keeping Oren’s **self-hosted stage2 native compiler** fast and diagnosable.

It is written for “I changed something and now `oren build` took >10s” incidents.

## 1) Non-negotiable performance gates (primary dev host)

These are rolling “red line” bounds used to catch fundamental regressions early:

- **Stage2 native backend: compile-one-file (rtobj hit)** must stay **< 4s** wall time.
  - Measured with: `./scripts/bench_native_compile_one_file.sh` (second run is the hit).
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

Optional bounded tracing:

```bash
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
  OREN_TRACE_RUNTIME_BUNDLE=1 \
  OREN_TRACE_RUNTIME_OS_PRUNE=1 \
  OREN_TRACE_RUNTIME_OBJ_CACHE=1 \
	  OREN_TRACE_ASTBIN=1 \
	  OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1 \
	  ./scripts/bench_native_compile_one_file.sh --no-debug
```

Notes on the tracers:

- `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` prints a **single-line breakdown** of the rtobj build (parse/decode, decl compile, finalize, counts/bytes).
  - Use it to decide whether to optimize astbin decode vs runtime decl compilation.

### 2.2 Cross-arch sanity (native backend)

- Local + container + remote matrix:
  - `./scripts/verify_native_matrix.sh`
- Local compile-only x64 sanity (stage1 + stage2 emit):
  - `./scripts/verify_native_x64_compile_only.sh`

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
  - `*_os_macos_pruned2.astbin`
  - `*_os_linux_pruned2.astbin`
- These are expected to already have dead `g_target_os` branches pruned.
  - The pruned program is marked with:
    - `__oren_pruned_target_os_id`
    - `__oren_pruned_target_os_kind="g_target_os"`
- If you see runtime OS pruning happening on an astbin cache hit (`OREN_TRACE_RUNTIME_OS_PRUNE=1`),
  treat it as a stale/unpruned cache file. The compiler will attempt a best-effort rewrite, which can
  be expensive once. After rewrite, runtime astbin decode should be materially faster.

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

### 4.2 Overloaded arithmetic in hot loops (`+` vs `iadd`)

In Oren, `+` is a language-level operator that may involve dynamic dispatch/boxing depending on value kinds.

In very hot compiler-internal loops (decode/emit), prefer intrinsic integer add:

- `iadd(a, b)` instead of `a + b`

This is especially important when the loop variable or offsets are updated per-iteration.

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

## 5) GC + string literal policy (perf + correctness)

String literals in native output are **pooled and embedded** in the binary’s data segment (cstr0 pool).

Key properties (rolling contract):

- identical literals should be pointer-deduped in the embedded pool
- the runtime registers all embedded literals once at startup (`oren_init_static_cstr0_table`)
- literals are **not GC-managed heap allocations**
  - they are tracked as **static-kind nodes (size=0)** for classification only (safe container ops)
  - GC root operations should not “root” them or allocate tracking nodes per use

This is tested in the native quick integration suite (`tests/native/test_quick_integration_native.oren`).

## 6) How to keep regressions from coming back

If you touch compiler hot paths (astbin decode, native emit, runtime injection), do this before merging:

1) Run:
   - `make verify-native-quick`
   - `./scripts/verify_native_x64_compile_only.sh`
2) Run the bounded perf check:
   - `OREN_NATIVE_BUILD_TIMEOUT_SECS=60 ./scripts/bench_native_compile_one_file.sh --no-debug`
3) If you see “rtobj miss” > 10s, re-run with tracing and identify the dominant bucket:
   - `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` (arm64) prints one `[arm64_rtobj] ...` line with parse/decl/finalize timings.
   - `OREN_TRACE_ASTBIN=1` prints `[astbin] decode done +...ms` for the runtime bundle decode.
   - runtime expand/parse
   - astbin decode
   - runtime decl compilation
   - emit/fixups

Healthy reference (arm64-macos stage2, rolling as of 2026-01-04; isolated rtobj dir, seed disabled):
- runtime astbin v2 decode: ~`1.3s` (`pool_n=2571`)
- rtobj miss compile-one-file: ~`15s` (still being pushed toward `<10s`)

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
