# Benchmarks (Local perf comparisons)

This folder contains **local, reproducible** microbenchmarks intended to compare:

- pure C baseline
- Oren (C backend)
- Oren (native backend)
- Oren bytecode running on AVM (`.obc`)

Benchmarks:

- `loop_sum` (tight integer loop with simple arithmetic)
- `array_sum` (list/array fill + sum; stresses element access and loop overhead)
- `array_sum_int` (list<int> fill + sum; evaluates unboxed list<int> path)
- `dot_product` (two-array dot product; stresses loads, multiply, and loop)
- `dot_product_int` (list<int> dot product; evaluates unboxed list<int> path)
- `multi_list_push_int` (three list<int> pushes per loop + sum; stresses unboxed list<int> push throughput)
- `multi_list_sum` (three boxed list reads per loop + sum; stresses boxed list access + add lowering)
- `alloc_churn` (allocation churn with periodic GC to surface leaks)
- `alloc_drop` (allocation churn with periodic drops to surface GC/root leaks; respects `OREN_BENCH_ITERS`)

## Latest snapshot

See `benchmarks/RESULTS_LATEST.md` for the latest M2 baseline summary (medians + C-relative ratios).
The per-run variance now lives in the derived result artifacts under `build/benchmarks/results/`:
JSON keeps raw timing vectors plus `stdev_s` / `cov`, and markdown includes the same summary.

## Run

```bash
python3 benchmarks/run_benchmarks.py
```

Full sweep (all benchmarks + snapshot update + pruning):

```bash
make benchmarks
```

Focused W5 perf gate sweep (just `loop_sum`, `dot_product`, `alloc_churn`, `alloc_drop`;
native vs C by default):

```bash
make perf-gate-native
```

Focused native read split (`array_sum`, `dot_product`; estimate one-time fill/setup vs steady
repeated read-loop cost with `reps=1` and `reps=10`). Use this to determine whether a canonical
hot-loop regression is dominated by the fill/push half or by the steady read loop itself:

```bash
make perf-gate-native-read-split
```

Focused native steady-state sweep (`array_sum`, `dot_product`; use a high `reps` count and report
per-rep medians directly so tracker updates do not depend on noisy setup subtraction):

```bash
make perf-gate-native-steady
```

Focused `list<int>` core-path sweep (`array_sum_int`, `dot_product_int`, `multi_list_push_int`;
C, Oren C, native, and OBC by default):

```bash
make perf-gate-list-int
```

Focused `list<int>` read split (`array_sum_int`, `dot_product_int`; estimate one-time fill/setup
vs steady repeated read-loop cost with `reps=1` and `reps=10`). This is still useful for
directional debugging, but tracker updates should prefer the dedicated steady-state sweep below
when the delta-vs-long estimates drift materially:

```bash
make perf-gate-list-int-read-split
```

Focused `list<int>` steady-state sweep (`array_sum_int`, `dot_product_int`; use a high `reps`
count and report per-rep medians directly so tracker updates do not depend on noisy setup
subtraction). This is the preferred source for steady-state tracker updates on the shared
read-heavy `list<int>` path:

```bash
make perf-gate-list-int-steady
```

Fast native correctness smoke for the exact `list<int>` hot benchmark binaries:

```bash
make perf-smoke-list-int
```

This builds `array_sum_int` and `dot_product_int` through `./oren_stage2` once and checks
both a tiny scalar-tail case (`205`, `6590`) and a >16-element hot-path case (`710`, `54380`)
before running the heavier timing sweeps. Use it first when changing the exact arm64 `list<int>`
hot paths so wrong-code experiments fail fast even when the bug only appears in the wider steady-state body.

This smoke now also runs automatically before:
- `make perf-gate-native-read-split`
- `make perf-gate-native-steady`
- `make perf-gate-list-int`
- `make perf-gate-list-int-read-split`
- `make perf-gate-list-int-steady`
- `make perf-probe-list-int-unsafe`

Set `OREN_PERF_SMOKE_LIST_INT=0` only when you intentionally want to skip that preflight
for local iteration.

Canonical native hot-loop correctness smoke:

```bash
make perf-smoke-native-fast-loops
```

Unsafe `list<int>` steady-state ceiling probe (baseline vs `OREN_LIST_ASSUME_LIST=1`,
`OREN_NATIVE_ASSUME_LIST_INDEX=1`, and both combined):

```bash
make perf-probe-list-int-unsafe
```

Packed-bridge `list<int>` ceiling probe (baseline shared read path vs hidden packed-bridge
benchmarks, with both hidden programs now built on the default core native profile):

```bash
make perf-probe-list-int-packed-bridge
```

Direct-slot `list<int>` ceiling probe (baseline shared read path vs hidden native-only
benchmarks that operate directly on the explicit 64-bit payload ABI):

```bash
make perf-probe-list-int-slot-direct
```

Hidden packed-bridge correctness smoke:

```bash
make perf-smoke-list-int-packed-bridge
```

Hidden direct-slot correctness smoke:

```bash
make perf-smoke-list-int-slot-direct
```

Explicit native prebuild for the hidden packed-bridge benchmarks:

```bash
make perf-prebuild-list-int-packed-bridge
```

Explicit native prebuild for the hidden direct-slot benchmarks:

```bash
make perf-prebuild-list-int-slot-direct
```

Dot-only native prebuild for the hidden dot artifact:

```bash
make perf-prebuild-dot-product-int-packed-bridge
```

Dot-only native prebuild for the hidden direct-slot dot artifact:

```bash
make perf-prebuild-dot-product-int-slot-direct
```

These packed-bridge benchmarks are intentionally excluded from `OREN_BENCH_PROGRAM=all` via
`.bench-hidden`. They measure the explicit `list<int> -> []i32` bridge without changing the
canonical `array_sum_int` / `dot_product_int` gates. This matters because the default native
benchmark profile is `core` (`lib/runtime_native_core.oren`), which includes only
`runtime_native/200_typed_buffers_core.oren`. That core surface now includes the minimal `i32`
dot family needed by the packed bridge, while heavier typed-buffer kernels remain on the full
runtime profile.

The direct-slot benchmarks are also hidden. They bypass the packed bridge entirely and call
native-only runtime helpers that operate on the explicit `list<int>` 64-bit slot ABI
(`oren_list_int_*_slots_unchecked`). That gives a ceiling measurement for “lower directly against
the current raw payload contract” without touching the canonical loop lowerings yet.

The packed-bridge smoke now defaults to the faster Oren C backend. That preflight still exercises
the hidden benchmark sources and scalar-vs-kernel bridge toggles, but it avoids paying the
full-runtime native build cost twice before the actual steady-state probe. Opt into a native smoke
explicitly with `OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND=native`.

When you do opt into native smoke, it reuses the same core-runtime prebuild path as the
steady probe instead of forcing a separate full-runtime rebuild.

The packed-bridge steady probe now also warms the hidden packed-bridge artifacts only once and
reuses them for the scalar-vs-kernel cases (`OREN_BENCH_SKIP_BUILD=1` on those follow-up legs).
That warm step is now the same reusable C+native prebuild exposed by
`make perf-prebuild-list-int-packed-bridge`. It keeps both hidden packed-bridge artifacts on the
cheap core native profile while also prebuilding the matching benchmark C binaries that the later
native/C ratio legs require.

For local iteration, the prebuild script also accepts `OREN_PERF_PREBUILD_PROGRAMS=name1,name2`.
The bundled `make perf-prebuild-dot-product-int-packed-bridge` target uses that to warm only the
`dot_product_int_packed_bridge` artifact outside the timed probe path.

There is also a dedicated native regression gate for this path:

```bash
make verify-native-core-packed-bridge
```

And a dedicated native regression gate for the direct-slot path:

```bash
make verify-native-slot-direct
```

And a compile-time guard that proves the canonical `array_sum_int` / `dot_product_int`
benchmark loops, the commuted-equivalent `sum = xs[i] + sum` /
`sum = a[i] * b[i] + sum` forms, and the one-temp normalized
`var x = xs[i]; sum = x + sum` / `var p = a[i] * b[i]; sum = p + sum` forms still lower
through the intended native direct-slot fast loops on both the local arm64 target and the
x64-linux backend:

```bash
make verify-native-list-int-fast-lowering
```

Update the snapshot from existing local result files:

```bash
make benchmarks-update
```

Optional knobs:

- `OREN_BENCH_RUNS=<n>` (default: 5)
- `OREN_BENCH_WARMUPS=<n>` (default: 1)
- `OREN_BENCH_RSS=1` (capture per-run max RSS via `/usr/bin/time`)
- `OREN_BENCH_OUTPUT_CHECK=0` (skip stdout consistency check; useful for trace/instrumentation)
- `OREN_BENCH_SKIP_BUILD=1` (reuse existing artifacts; fail if missing)
- `OREN_BENCH_SAVE_STDOUT=1` (save per-variant stdout under `build/logs/bench_stdout_*`)
- `OREN_BENCH_SAVE_RUN_LOGS=1` (save per-run stdout under `build/logs/bench_run_<program>_<ts>/<variant>/run_<idx>.log`)
- `OREN_BENCH_RUN_LOG_TEE=1` (print per-run stdout to the console while saving run logs)
- `OREN_BENCH_TRACE_ALLOC_SITE=1` (native-only; forces stdout capture, disables output checks, and sets warmups to 0 to preserve `[alloc_site]` trace lines dumped at exit)
- `OREN_BENCH_TRACE_ALLOC_SITE_CAP=<n>` (optional cap for native alloc-site table; forwarded to `OREN_TRACE_ALLOC_SITE_CAP`)
- `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=<n>` (optional; forces `OREN_GC_AUTO=1` and sets `OREN_GC_ALLOC_THRESHOLD` for alloc-site dumps)
- `OREN_BENCH_PROGRAM=<name|all|name1,name2>` (default: `loop_sum`)
- `OREN_BENCH_PROGRAMS=name1,name2` (explicit list; overrides `OREN_BENCH_PROGRAM`)
- `OREN_BENCH_UPDATE_LATEST=1` (update `benchmarks/RESULTS_LATEST.md` after run)
- `OREN_BENCH_UPDATE_LATEST_PRUNE=1` (with UPDATE_LATEST, prune stale result files)
- `OREN_BENCH_LIST_INT_SPLIT_N=<n>` (used by `perf-gate-list-int-read-split`; default: 2000000)
- `OREN_BENCH_LIST_INT_SPLIT_SHORT_REPS=<n>` (used by `perf-gate-list-int-read-split`; default: 1)
- `OREN_BENCH_LIST_INT_SPLIT_LONG_REPS=<n>` (used by `perf-gate-list-int-read-split`; default: 10)
- `OREN_BENCH_NATIVE_SPLIT_N=<n>` (used by `perf-gate-native-read-split`; default: 2000000)
- `OREN_BENCH_NATIVE_SPLIT_SHORT_REPS=<n>` (used by `perf-gate-native-read-split`; default: 1)
- `OREN_BENCH_NATIVE_SPLIT_LONG_REPS=<n>` (used by `perf-gate-native-read-split`; default: 10)
- `OREN_BENCH_NATIVE_STEADY_N=<n>` (used by `perf-gate-native-steady`; default: 2000000)
- `OREN_BENCH_NATIVE_STEADY_REPS=<n>` (used by `perf-gate-native-steady`; default: 100)
- `OREN_BENCH_LIST_INT_STEADY_N=<n>` (used by `perf-gate-list-int-steady`; default: 2000000)
- `OREN_BENCH_LIST_INT_STEADY_REPS=<n>` (used by `perf-gate-list-int-steady`; default: 100)
- `OREN_BENCH_CC=<compiler>` (override C compiler; auto-detects `cc/clang/gcc` otherwise)
- `OREN_BENCH_ENV_ALL=K=V,...` (apply env overrides to all variants)
- `OREN_BENCH_ENV_C=K=V,...`
- `OREN_BENCH_ENV_OREN_C=K=V,...`
- `OREN_BENCH_ENV_OREN_NATIVE=K=V,...`
- `OREN_BENCH_ENV_OREN_OBC=K=V,...`
- `OREN_BENCH_ENV_BUILD=K=V,...` (apply env overrides to all build steps)
- `OREN_BENCH_ENV_BUILD_OREN=K=V,...` (apply env overrides to Oren build steps)
- `OREN_BENCH_ARGS="arg1 arg2 ..."` (extra CLI args passed to all variants)
- `OREN_BENCH_INIT_SPLIT=1` (loop_sum only; run extra reps=1 + reps=N passes to estimate init vs steady-state)
- `OREN_BENCH_INIT_SPLIT_REPS=<n>` (loop_sum only; default: 10, used as the long-run reps value)
- `OREN_BENCH_INIT_SPLIT_N=<n>` (loop_sum only; override n for init split; default: first arg in `OREN_BENCH_ARGS` or loop_sum default)
- `OREN_BENCH_ITERS=<n>` (used by `alloc_drop`; default: 10000)
- `OREN_BENCH_GC_EVERY=<n>` (used by `alloc_churn`; when >0, call `oren_gc_collect()` every n iterations)
- `OREN_BENCH_CLEAR_LIST=1` (used by `alloc_churn`; when set, clear the per-iter list to reduce GC roots during traces)
- `OREN_BENCH_SMALL_INTS=1` (used by `alloc_churn`; use small integers to reduce conservative GC false roots)
- `OREN_BENCH_FORCE_LIST_INT=1` (used by `alloc_churn`; build lists via `oren_new_list_int` + list_int ops to force list_int frees)
- `OREN_BENCH_LIST_LEN=<n>` (used by `alloc_churn`; override per-iter list length; default 128)
- `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` (native-only; enables free-list header dumps and list_hdr ring capture for GC samples)
- `OREN_TRACE_GC_FREE_LIST_HDR_RING_EVERY=<n>` (emit a ring dump every n free-list samples; default 1)
- `OREN_TRACE_GC_FREE_LIST_HDR_RING_CAP=<n>` (max ring dumps to emit; default 16)
- `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1` (dump the full ring instead of filtering by list pointer; cap via ring size + `_CAP`)
- `OREN_BENCH_SKIP_OBC=1` (skip AVM/OBC build+run; useful on Windows if `avm.exe` is unavailable)
- `OREN_BENCH_SKIP_C=1` (skip the pure C baseline build+run)
- `OREN_BENCH_SKIP_OREN_C=1` (skip the Oren C-backend build+run; useful if no C compiler is installed)
- `OREN_BENCH_SKIP_NATIVE=1` (skip native backend build+run)
- `OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0|1` (used by `perf-gate-native-read-split` and `perf-gate-native-steady`; default: 1; runs `make perf-smoke-native-fast-loops` first)
- Arm64 fast-loop compiler tick masks can be overridden at build time via
  `OREN_BENCH_ENV_BUILD_OREN=...` with decimal `0..65535` values. Current knobs:
  `OREN_ARM64_FAST_LIST_GET_SUM_TICK_MASK`,
  `OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK`,
  `OREN_ARM64_FAST_LIST_DOT_TICK_MASK`,
  `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK`,
  `OREN_ARM64_FAST_LIST_PUSH_TICK_MASK`,
  `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK`,
  `OREN_ARM64_FAST_LCG_SUM_TICK_MASK`.
- Example: `OREN_BENCH_ENV_OREN_NATIVE=OREN_LIST_ASSUME_LIST=1` to probe list-validation overhead (unsafe; perf-only).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_LIST_SKIP_LOCKS=1` to skip list/map locks in the C backend (unsafe; perf-only).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_LIST_FORCE_LOCKS=1` to force list/map locks in the C backend (useful for safety baselines).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_TRACE_LIST_LOCKS=1` to print lock gating state once at first list access.
- Compiler env example (affects codegen): `OREN_NATIVE_ASSUME_LIST_INDEX=1 python3 benchmarks/run_benchmarks.py` (unsafe; perf-only).
- Compiler env example (arm64 tick-mask probe): `OREN_BENCH_ENV_BUILD_OREN=OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=65535 make perf-gate-native`.

Results are written to local build output:

- `build/benchmarks/results/<program>_<platform>_<timestamp>.md`
- `build/benchmarks/results/<program>_<platform>_<timestamp>.json`

When `OREN_BENCH_TRACE_ALLOC_SITE=1`, result JSON includes an `alloc_site` section
with per-run counts and median/mean summaries (native-only).

When `OREN_BENCH_INIT_SPLIT=1`, result JSON includes `init_split`, and the result
markdown includes an “Init/steady split” section for loop_sum.

Result JSON/markdown include an `env` snapshot of `OREN_*` variables (filtered to
exclude obvious secret tokens) to aid reproducibility.

Result JSON timing entries now also keep:

- `runs` (raw per-run seconds)
- `stdev_s` (sample standard deviation)
- `cov` (coefficient of variation = `stdev / mean`)

Build logs are stored under `build/logs/` with a `bench_build_*` prefix.

Update the canonical snapshot table after a batch run:

```bash
python3 benchmarks/update_latest.py --prune
```

Repo policy (rolling): benchmark result JSON/markdown are derived artifacts and should not be
committed. Keep them under `build/benchmarks/results/`, and commit only stable summaries such as
`benchmarks/RESULTS_LATEST.md` when the project tracker needs a refreshed baseline.

## Notes

- The Oren sources are compiled with `./oren_stage2` for consistency.
- The direct runner refreshes `./oren_stage2` first when `./oren` is newer, so local benchmark
  runs do not silently use a stale self-hosted compiler after compiler edits.
- Native builds use `--no-debug` to approximate release behavior.
- The default benchmark native profile is the reduced `core` runtime unless you explicitly set
  `OREN_BENCH_ENV_BUILD_OREN=OREN_NATIVE_RUNTIME_PROFILE=full`.
- `array_sum` and `dot_product` now accept the same optional CLI args as `loop_sum` / the
  `list<int>` benchmarks: `n` first, `reps` second.
- For the canonical arm64 hot-loop safepoint sweep, use
  `make perf-probe-arm64-fast-loop-tick-masks` and optionally narrow it with
  `OREN_ARM64_FAST_LOOP_TICK_PROGRAMS=dot_product`.
- For the canonical arm64 steady-state safepoint sweep, use
  `make perf-probe-arm64-fast-loop-tick-masks-steady` and optionally narrow it with
  `OREN_ARM64_FAST_LOOP_TICK_STEADY_PROGRAMS=dot_product`. This reuses
  `perf-gate-native-steady`, runs one shared smoke preflight, and then measures all mask variants
  without extra preflight noise so it answers the actual repeated-read-loop question rather than
  the earlier one-shot gate.
- For the arm64 single-pair `fast_list_int_dot_while` cursor-reg recheck, use
  `make perf-probe-arm64-fast-dot-single-pair-cursor-regs`. The shipped default keeps the
  single-pair cursor-reg path enabled, and the probe compares that default against
  `OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0`.
- Native/list<int> perf-gate, probe, smoke, prebuild, and benchmark result artifacts now use
  collision-resistant timestamps, so back-to-back variants do not overwrite each other’s logs or
  result files.
- The OBC benchmark uses `./avm` and runs without explicit capability restrictions.
  On Windows, the runner looks for `.exe` tool suffixes automatically.

`loop_sum` accepts optional CLI args:

- `n` (first arg after program path; `0` allowed)
- `reps` (second arg; repeat the loop that many times, default 1)

Example:

```bash
OREN_BENCH_PROGRAM=loop_sum OREN_BENCH_ARGS="2000000 10" python3 benchmarks/run_benchmarks.py
```

Run every benchmark:

```bash
OREN_BENCH_PROGRAM=all python3 benchmarks/run_benchmarks.py
```
