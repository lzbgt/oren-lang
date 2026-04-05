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

This emits both the raw benchmark log and a lightweight summary log under
`build/logs/perf-gate-native-*.summary.log`. The summary now warns when the one-program gate is too
noisy (`cov >= 0.10`) to support a strong perf conclusion.

For a small distribution of canonical-gate results instead of one run, use:

```bash
make perf-probe-native-gate-stability
```

This reruns `make perf-gate-native` a few times (`OREN_NATIVE_GATE_STABILITY_SWEEPS`, default `3`)
and summarizes the ratio range plus how often each program triggered the high-variance warning.

The shared stage1/stage2 compiler rebuild now runs behind a repo-local build lock
(`build/locks/compiler-build.lock`), so parallel `make perf-*` invocations queue on compiler
rebuilds instead of racing on `oren` / `oren_stage2` and macOS codesign.

For a focused machine-code view of the canonical arm64 hot loops, use:

```bash
make perf-probe-arm64-native-hot-loop-disasm
```

This builds `array_sum` and `dot_product` with `--disasm`, `--no-cache`, and
`OREN_TRACE_ARM64_LOOP_RANGES=1`, then extracts just the traced
`fast_list_int_get_sum_while*` / `fast_list_int_dot_while*` windows into a compact summary log.
`--no-cache` is intentional: the summary depends on compile-time trace lines, and a native cache hit
can otherwise skip lowering and leave only the raw disassembly text. The summary also reports
instruction counts plus a mnemonic histogram for the traced hot-loop window, so future arm64
dot-core changes can compare static loop shape without diffing whole-binary disassembly by hand.
The probe now exits non-zero if either traced loop window is missing, so cache-hit or lowering drift
cannot silently degrade the summary into a best-effort note.

For a focused comparison between the shipped arm64 native `dot_product` loop and the host C
compiler's `-O2` lowering of [benchmarks/dot_product/dot_product.c](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product/dot_product.c),
use:

```bash
make perf-probe-arm64-dot-vs-c-loop-compare
```

This reuses the traced arm64 hot-loop disasm probe, compiles the C benchmark to assembly, and
extracts the Oren dot window plus the host C vector loop, mid loop, and scalar tail into one
summary. The latest artifact,
`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260405_030630_69117.log`, shows the kept Oren
path as a 70-instruction scalar loop, while the host C reference uses a 57-instruction NEON vector
loop (`ldp q*`, `smlal.2d`, `smlal2.2d`), a 22-instruction vector mid loop, and a 6-instruction
scalar `smaddl` tail. That is the right current baseline when judging future arm64 dot work: the
remaining gap is versus a vectorized C loop, not just a better scalar schedule.

The probe also now parses comma-separated `OREN_BENCH_ENV_BUILD_OREN` correctly, so multi-var build
env overrides reach the traced Oren build instead of being collapsed into one invalid token.

To quantify how much of the remaining gap is still scalar-codegen debt versus the missing NEON path,
use:

```bash
make perf-probe-arm64-dot-vs-c-scalar-ceiling
```

This builds [dot_product.c](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product/dot_product.c)
twice with the host `cc`: once with default `-O2`, and once with vectorization disabled
(`-O2 -fno-vectorize -fno-slp-vectorize` on the current clang host). It then times both C binaries
against the exact Oren native benchmark binary on the same `n/reps` workload.

The latest artifact, `build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260405_030703_69836.log`,
shows:

- vectorized C per-rep: `~0.000264s`
- scalar C per-rep: `~0.000743s`
- Oren native per-rep: `~0.000781s`
- scalar/vector ratio: `~2.8153x`
- Oren/scalar ratio: `~1.0517x`
- Oren/vector ratio: `~2.9609x`

That is the current arm64 ceiling fact: the kept Oren scalar loop is already within about 5% of
scalar C on this host, so the remaining large gap to the default C baseline is overwhelmingly the
missing NEON/vector path rather than another round of scalar cleanup.

To measure how much of that remaining gap comes from the current `list<int>` 64-bit slot ABI itself,
use:

```bash
make perf-probe-list-int-slot-abi-ceiling
```

This builds and times six binaries on the same `n/reps` workload:

- packed-i32 C with default `-O2`
- packed-i32 C with vectorization disabled
- 64-bit-slot C (`int64_t[]`, same value stream) with default `-O2`
- 64-bit-slot C with vectorization disabled
- the shipped Oren native `dot_product_int` benchmark
- the native-only Oren `dot_product_int_slot_direct` benchmark

The latest artifact, `build/logs/perf-probe-list-int-slot-abi-ceiling-20260405_033149_3497.log`,
shows:

- packed-i32 C vector: `~0.000252s` per rep
- packed-i32 C scalar: `~0.000731s` per rep
- slot64 C “vector”: `~0.000725s` per rep
- slot64 C scalar: `~0.000741s` per rep
- Oren native canonical: `~0.000762s` per rep
- Oren native slot-direct helper: `~0.003228s` per rep

The ratio view is the important part:

- slot64-vector / packed-vector: `~2.8712x`
- slot64-scalar / packed-scalar: `~1.0135x`
- Oren canonical / slot64-vector: `~1.0514x`
- Oren slot-direct helper / slot64-vector: `~4.4514x`

And the assembly snippet matters too: the host compiler does not generate a NEON packed-lane loop
for the slot64 source. Its best `-O2` slot64 loop is still a paired-scalar `ldp` + `madd` shape,
not the packed `smlal/smlal2` loop seen in the packed-i32 benchmark. That is the current ceiling
fact to use for next-step planning: the 64-bit slot ABI itself largely erases the auto-vectorization
gain, and the shipped Oren canonical loop is already within about 5% of that slot64 host-C ceiling.

For the serial arm64 dot-core acceptance bundle that matches the recent manual workflow, use:

```bash
make perf-probe-arm64-dot-acceptance
```

This runs, in order:

- `make perf-smoke-native-fast-loops`
- `make perf-probe-arm64-native-hot-loop-disasm`
- `env OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0 OREN_BENCH_PROGRAMS=array_sum,dot_product make perf-gate-native-steady`
- `env OREN_BENCH_PROGRAMS=array_sum,dot_product make perf-gate-native`
- `make perf-debug-native-benchmark`
- `make test` by default

The acceptance summary records the wrapper logs, the underlying summary artifacts, the current
steady/canonical ratios, the disasm instruction counts, and the exact-binary debug status in one
place. If any leg fails, it still emits a partial summary with `exit_status`, `failed_step`, and
whatever artifacts completed before the failure, so unsafe arm64 experiments stop failing as a
black box. Set `OREN_ARM64_DOT_ACCEPT_RUN_TEST=0` only when you intentionally want to skip the
final `make test` leg during local iteration.

Focused native read split (`array_sum`, `dot_product`; estimate one-time fill/setup vs steady
repeated read-loop cost with `reps=1` and `reps=10`). Use this to determine whether a canonical
hot-loop regression is dominated by the fill/push half or by the steady read loop itself:

```bash
make perf-gate-native-read-split
```

When `OREN_BENCH_ENV_BUILD_OREN` is set, this summary now records `build_env:` so probe data from
environment-gated compiler variants does not look like baseline output.

Focused native steady-state sweep (`array_sum`, `dot_product`; use a high `reps` count and report
per-rep medians directly so tracker updates do not depend on noisy setup subtraction):

```bash
make perf-gate-native-steady
```

Shared compiler rebuilds behind the perf targets are serialized with the repo-local build lock at
`build/locks/compiler-build.lock`. If you intentionally want a shorter or longer queue timeout, set
`OREN_BUILD_LOCK_WAIT_SECS` (`0` means wait forever); the lock metadata now records holder start
time and age for easier diagnosis when a queued perf run waits behind a long stage2 build.

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
Like the canonical native smoke, it now rebuilds with `--no-cache` so compiler-env experiments
cannot silently pass against an older cached native benchmark binary.

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

This smoke now rebuilds its native benchmark binaries with `--no-cache`. That is intentional:
compiler-env experiments like `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` must certify the exact
current build, not a stale cached baseline artifact.

Exact native benchmark repro/debug runner (uses the same native benchmark build path;
defaults to `benchmarks/dot_product/dot_product.oren` with args `10 3`):

```bash
make perf-debug-native-benchmark
```

Useful overrides:

- `OREN_BENCH_DEBUG_PROGRAM=benchmarks/array_sum/array_sum.oren`
- `OREN_BENCH_DEBUG_ARGS="20 3"`
- `OREN_BENCH_DEBUG_COMPILER=./oren_stage2`
- `OREN_BENCH_DEBUG_PLATFORM=arm64-macos`

The runner builds the chosen benchmark, executes the exact native binary directly, and writes a
summary log with the binary path, args, exit code, build log, and run log. On non-zero exit it also
prints the exact manual `lldb -- <binary> <args...>` command to use for follow-up crash triage.

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

For one ranked view of the current `list<int>` `dot_product` alternatives, use:

```bash
make perf-probe-list-int-dot-ceiling
```

This runs a deliberately small fast-profile steady comparison across the canonical `list<int>` fast
loop, the unchecked direct-slot helper path, and the packed-bridge scalar/SIMD paths. The default
profile is `runs=2`, `warmups=0`, `n=20000`, `reps=2`; override it with
`OREN_LIST_INT_DOT_CEILING_{RUNS,WARMUPS,N,REPS}` when you want a different scale.

The latest artifact, `build/logs/perf-probe-list-int-dot-ceiling-20260405_024559_38593.log`,
shows the current ranking on this host:

- baseline canonical `dot_product_int`: `~1.2137x C`
- direct-slot helper `dot_product_int_slot_direct`: `~1.5149x C`
- packed bridge SIMD `dot_product_int_packed_bridge`: `~565.8124x C`
- packed bridge scalar `dot_product_int_packed_bridge`: `~1382.0339x C`

That is the current ceiling fact to use when choosing the next implementation move: the canonical
compiler fast loop still beats the helper/bridge alternatives decisively, so further hot-loop work
should stay on the direct lowering / representation side instead of detouring back through packing
or runtime helper boundaries.

For a direct answer to “is the packed bridge only losing because of one-time setup cost?”, use:

```bash
make perf-probe-list-int-packed-bridge-read-split
```

This runs the canonical `dot_product_int` path and the hidden packed-bridge scalar/SIMD variants
through the same short/long read-split runner after an explicit packed-bridge warm step. The
default profile is intentionally small enough to stay usable in normal turns:
`runs=2`, `warmups=0`, `n=20000`, `short_reps=1`, `long_reps=2`; override it with
`OREN_LIST_INT_PACKED_BRIDGE_SPLIT_{RUNS,WARMUPS,N,SHORT_REPS,LONG_REPS}` when you want a
different scale. The underlying packed-bridge / slot-direct prebuild and smoke helpers now also
forward comma-separated `OREN_BENCH_ENV_BUILD_OREN` values correctly, so this probe can be combined
with multi-key compiler/runtime build env overrides without silently dropping them.

The latest artifact, `build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_032402_91481.log`,
was run with `build_env: OREN_NATIVE_RUNTIME_PROFILE=core` and came back as:

- baseline canonical `dot_product_int`: `~1.3378x C` long-per-rep
- packed bridge scalar `dot_product_int_packed_bridge`: `~1037.5886x C` long-per-rep,
  `~3360.3659x C` delta
- packed bridge SIMD `dot_product_int_packed_bridge`: `~549.8375x C` long-per-rep,
  `~126.8281x C` delta

That closes the main attribution question for the existing bridge: even after warmup and with the
short/long split isolating repeated reads, the packed-bridge path is still hundreds of times slower
than the canonical direct lowering. The blocker is not just first-build or one-time pack setup
cost, so near-term parity work should not go back through the current bridge shape.

To answer the narrower question “does the packed SIMD path become viable if we really amortize the
pack step?”, use:

```bash
make perf-probe-list-int-packed-bridge-simd-reuse
```

This keeps only the canonical `dot_product_int` baseline and the packed-SIMD bridge path, but raises
the default long run to `10` reps so the result is less setup-dominated than the earlier mixed
read-split probe. The latest artifact,
`build/logs/perf-probe-list-int-packed-bridge-simd-reuse-20260405_033734_11943.log`, was run with
`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=0`, `n=20000`,
`short_reps=1`, `long_reps=10` and came back as:

- baseline canonical `dot_product_int`: `~0.000331s` native long-per-rep
- packed-SIMD `dot_product_int_packed_bridge`: `~0.266698s` native long-per-rep
- packed-SIMD / baseline long-per-rep: `~805.7341x`

So even after a much stronger reuse-oriented split, the packed-SIMD bridge is still nowhere near the
canonical fast loop. That makes the previous packed-bridge conclusion stronger, not weaker: a safe
packed-i32 view alone is not enough if it still feeds the current bridge/kernel stack.

To isolate the current `[]i32` dot kernel itself from any list packing step, use:

```bash
make perf-probe-list-int-i32-buf-dot-ceiling
```

This builds a hidden [dot_product_i32_buf.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product_i32_buf/dot_product_i32_buf.oren)
benchmark that allocates/fills typed `[]i32` buffers directly, then compares:

- packed-i32 C with default `-O2`
- packed-i32 C with vectorization disabled
- Oren native `dot_product_i32_buf` with `OREN_NO_SIMD=1`
- Oren native `dot_product_i32_buf` with `OREN_ENABLE_SIMD=1`
- shipped Oren native `dot_product_int`

The hidden benchmark now perturbs lane `0` across `reps` and accumulates every repetition result so
the repeated dot work cannot be trivially hoisted. The latest full-process artifact,
`build/logs/perf-probe-list-int-i32-buf-dot-ceiling-20260405_040717_51202.log`, shows:

- packed-i32 C vector: `~0.000145s` per rep
- packed-i32 C scalar: `~0.000126s` per rep
- Oren `dot_product_i32_buf` scalar: `~0.011786s` per rep
- Oren `dot_product_i32_buf` SIMD: `~0.002043s` per rep
- shipped Oren canonical `dot_product_int`: `~0.000169s` per rep

That full-process view is still setup-mixed. The probe now prints an explicit warning when packed C
vector/scalar stay too close and points at the stronger reuse surface below instead of treating this
as a clean repeated-kernel ratio.

For repeated-kernel attribution on the fast typed-buffer path, use:

```bash
make perf-probe-list-int-i32-buf-simd-reuse
```

This keeps only the guarded packed-i32 C vector binary and the guarded Oren `dot_product_i32_buf`
SIMD binary, then raises the long run high enough that the repeated dot work finally dominates for
the C side. The latest artifact,
`build/logs/perf-probe-list-int-i32-buf-simd-reuse-20260405_040936_54584.log`, was run with
`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=0`, `n=200000`,
`short_reps=1`, `long_reps=1000` and came back as:

- packed-i32 C vector: `setup≈0.002528s`, `delta≈0.000018s`, `long/reps≈0.000020s`
- Oren `dot_product_i32_buf` SIMD: `setup≈0.374950s`, `delta≈0.000024s`, `long/reps≈0.000399s`
- repeated-kernel ratio (`delta`): `~1.3562x`
- whole-process long-per-rep ratio: `~19.7021x`

That is the corrected interpretation: the repeated `[]i32` SIMD dot kernel is much closer to
packed-i32 C than the old setup-mixed probe implied, but the typed-buffer path still pays a very
large fixed setup cost before the repeated kernel even starts.

To break that fixed setup cost into `alloc+fill` versus everything else, use:

```bash
make perf-probe-list-int-i32-buf-setup-breakdown
```

This adds a hidden [fill_i32_buf.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/fill_i32_buf/fill_i32_buf.oren)
benchmark and matching C twin, then compares:

- fill-only C (`malloc` + fill)
- fill-only Oren `[]i32` (`buffer.i32_new` + `oren_buf_store_i32`)
- the existing guarded packed-i32 C vector dot setup from the reuse probe
- the existing guarded Oren `dot_product_i32_buf` SIMD setup from the reuse probe

The latest artifact, `build/logs/perf-probe-list-int-i32-buf-setup-breakdown-20260405_042115_69806.log`,
was run with `runs=3`, `warmups=0`, `n=200000`, `short_reps=1`, `long_reps=1000` and came back as:

- fill-only C: `~0.002515s`
- fill-only Oren `[]i32`: `~0.372046s`
- packed-i32 C vector setup: `~0.002991s`
- Oren `dot_product_i32_buf` SIMD setup: `~0.375121s`
- Oren fill share of Oren SIMD setup: `~99.18%`
- Oren residual setup beyond fill: `~0.003075s`

That closes the next attribution layer too: the large fixed cost on the typed-buffer path is now
overwhelmingly the `buffer.i32_new` + checked per-element fill loop itself, not the repeated SIMD
dot kernel and not a large hidden post-fill runtime-call boundary.

To separate “skip the checked store helper” from “hoist the raw data pointer and write directly in
the fill loop”, use:

```bash
make perf-probe-list-int-i32-buf-unchecked-fill
```

This builds three hidden Oren fill-only benchmarks:

- checked [fill_i32_buf.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/fill_i32_buf/fill_i32_buf.oren)
- helper-based unchecked [fill_i32_buf_unchecked.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/fill_i32_buf_unchecked/fill_i32_buf_unchecked.oren)
- pointer-hoisted [fill_i32_buf_ptr.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/fill_i32_buf_ptr/fill_i32_buf_ptr.oren)
- pointer-hoisted + uninitialized [fill_i32_buf_ptr_uninit.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/fill_i32_buf_ptr_uninit/fill_i32_buf_ptr_uninit.oren)

The latest artifact, `build/logs/perf-probe-list-int-i32-buf-unchecked-fill-20260405_044149_1286.log`,
was run with `runs=3`, `warmups=0`, `n=200000` and came back as:

- checked fill: `~0.376955s`
- unchecked helper fill: `~0.367594s` (`~1.0255x` speedup)
- pointer-hoisted fill: `~0.344940s` (`~1.0928x` speedup)
- pointer-hoisted + uninitialized fill: `~0.207338s` (`~1.8181x` speedup)

That narrows the next implementation target further. Removing the per-call check alone is only a
modest win, and hoisting the raw payload pointer helps more, but the first genuinely large reduction
appears only when the caller can skip the `native_buf_new` zero-fill and then overwrite every lane
through the hoisted pointer loop. The next serious optimization needs a bulk/pointer-aware fill
surface plus an uninitialized-allocation path that is only used when full initialization is proven
before exposure.

That measured lever is now kept in the shared `i32` conversion surface. The latest
`make perf-probe-list-int-dot-ceiling` artifact,
`build/logs/perf-probe-list-int-dot-ceiling-20260405_223926_17836.log`, shows the
real workload effect after switching fresh `i32` list/slice/strided/matrix exports to
`oren_i32_buf_new_uninit(...)` plus unchecked direct stores on success-only full-overwrite paths:

- baseline `dot_product_int`: `~1.4238x C`
- `dot_product_int_slot_direct`: `~0.9826x C`
- baseline `array_sum_int`: `~1.3214x C`
- `array_sum_int_slot_direct`: `~0.7955x C`

That is the first production-path result that reaches near-parity with the host C baseline on this
fast profile. The same change does not rescue the packed bridge: the paired
`build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_223926_17837.log`
still reports `dot_product_int_packed_bridge` at `~542.7074x C` SIMD and `~1062.1370x C`
scalar on long-per-rep, so the packed bridge remains closed as a serious candidate.

That full-overwrite fast path is now applied consistently across the rest of the fresh numeric typed
buffer export family as well: `i64_pack_list_int`, `f32_pack_list`, `f64_pack_list`,
slice/strided-to-`i64`/`f32`/`f64` buffer exports, and the corresponding whole-matrix pack/export
helpers now use the same `*_new_uninit + unchecked direct store` rule on success-only full-write
paths. The C runtime exports conservative `*_buf_new_uninit` shims for those element types too, so
the shared stdlib remains backend-safe even though only native gets the uninitialized-allocation win.

That same proof now covers the fresh `u8` export family too. Shared `std:buffer`/`std:bytes`
surfaces that allocate a fresh `[]u8` and fully overwrite it before any successful return now use the
same conservative rule:

- `buffer.try_u8_pack`
- `buffer.try_u8_from_string`
- `buffer.try_u8_from_string_slice`
- `buffer.try_slice_to_u8_buf`
- `buffer.try_strided_to_u8_buf`
- `buffer.try_u8_mat_pack_rows`
- `buffer.try_u8_mat_pack_strings`
- `buffer.try_u8_mat_to_u8_buf`
- `bytes.try_to_u8_buf`
- `bytes.try_to_u8_buf_slice`

There is no separate kept `u8` performance artifact yet; the fact-backed claim here is scope and
safety, not a new benchmark number. The same native/C backend split still applies: native can skip
the eager zero-fill through `oren_u8_buf_new_uninit(...)`, while `oren_c` keeps a conservative shim
that zero-allocates and preserves correctness.

For a direct attribution read on how much of the remaining gap is still “generic benchmark shape”
versus the explicit `list.int_*` path, use:

```bash
make perf-probe-list-int-specialization-gap
```

This runs the canonical generic-list benchmarks (`array_sum`, `dot_product`) and the explicit
`list.int_*` benchmarks (`array_sum_int`, `dot_product_int`) through the same steady runner with the
same `n/reps/runs/warmups`, then prints the generic-vs-specialized gap directly. The probe now
passes the correct steady-runner knobs to each side: the generic side uses
`OREN_BENCH_NATIVE_STEADY_{N,REPS}` and the specialized side uses
`OREN_BENCH_LIST_INT_STEADY_{N,REPS}`. The earlier artifact
`build/logs/perf-probe-list-int-specialization-gap-20260405_025217_48504.log` is superseded because
it accidentally passed the `list<int>` knobs into the generic runner. The latest corrected artifact,
`build/logs/perf-probe-list-int-specialization-gap-20260405_025957_59475.log`, was run with
`build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=1`, `n=200000`, `reps=10` and came
back as:

- `array_sum`: generic `~1.3419x C` vs specialized `~1.4064x C` (`generic_vs_specialized ~0.9541x`)
- `dot_product`: generic `~1.5169x C` vs specialized `~1.4803x C` (`generic_vs_specialized ~1.0247x`)

That is the current steady-state attribution fact: once the workloads are aligned correctly, the
canonical generic-list benchmarks are already near parity with the explicit `list.int_*` variants on
this host. The earlier large gap was a probe bug, not a compiler/runtime fact.

For the same comparison with fill/setup and repeated-loop costs separated, use:

```bash
make perf-probe-list-int-specialization-read-split
```

The latest artifact, `build/logs/perf-probe-list-int-specialization-read-split-20260405_030027_60451.log`,
shows that the reliable long-per-rep view is also near parity under the same
`build_env: OREN_NATIVE_RUNTIME_PROFILE=core` profile:

- `array_sum`: generic `~1.5652x C`, specialized `~1.4639x C` (`generic_vs_specialized_long_per_rep ~1.0692x`)
- `dot_product`: generic `~1.5241x C`, specialized `~1.5157x C` (`generic_vs_specialized_long_per_rep ~1.0055x`)

That artifact also reports the short-vs-long delta estimate, but on this host the specialized
`list<int>` short runs are dominated by setup noise and print the same warning as the underlying
read-split gate: prefer `long_per_rep` over `delta` for tracker updates.

And to confirm that the generic benchmarks still compile through the intended `list<int>` rewrite
path instead of silently falling back to boxed-list behavior, use:

```bash
make perf-probe-list-int-specialization-trace
```

The latest trace artifact, `build/logs/perf-probe-list-int-specialization-trace-20260405_025957_59477.log`,
shows:

- generic `array_sum`: `list_int rewrite init name=xs`
- generic `dot_product`: `list_int rewrite init name=a` and `name=b`
- explicit `array_sum_int` / `dot_product_int`: start as `oren_new_list_int` candidates and therefore
  do not need rewrite-init events

So the current canonical `dot_product` blocker should no longer be framed as “generic-list
specialization is missing.” The remaining gap is back in the steady-state hot path and the C-side
NEON/vector advantage, not in a silent boxed-list fallback.

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
- For the arm64 `fast_list_int_dot_while` unroll-by-2 recheck, use
  `make perf-probe-arm64-fast-dot-unroll2`. The shipped default keeps the unique-list
  unroll-by-2 path enabled, and the probe compares that default against
  `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=0`. The emitter also accepts explicit `0/1`
  (`false/true`) overrides so future reruns can force either side without source edits.
- For the arm64 single-pair `fast_list_int_dot_while` dual-accumulator recheck, use
  `make perf-probe-arm64-fast-dot-dual-accum`. The shipped default keeps the dual-accumulator
  path disabled, and the probe compares that default against
  `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1`.
- For the arm64 exact-path `madd` recheck, use
  `make perf-probe-arm64-fast-dot-madd-exact`. This keeps `madd` disabled by default and compares
  the shipped baseline against `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` through the full serial
  arm64 dot acceptance bundle. Use it when revisiting the default-off exact-path `madd` branch so
  disasm, steady-state ratios, canonical gate, and exact-binary repro all land in one comparable
  artifact instead of being reassembled from ad-hoc commands. After the April 5 exact-double tail
  guard, the current host now treats the enabled path as correctness-clean, but still not as a
  shipped optimization: the latest rerun lands at `steady_dot_product ~2.9446x`,
  `gate_dot_product ~2.7220x`, `disasm_dot_product_insns: 77`, and `debug_exit_code: 0` versus the
  shipped baseline at `~3.1670x`, `~2.7194x`, `70`, and `0`
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-20260405_013731_43460.log`).
- For the arm64 exact-path `madd` subcase split, use
  `make perf-probe-arm64-fast-dot-madd-exact-subpaths`. This keeps the shipped baseline on one side
  and compares isolated `quad`, `double`, and `scalar` exact-`madd` substitutions on the other by
  forcing `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=0` and enabling exactly one of:
  `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_QUAD=1`,
  `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_DOUBLE=1`, or
  `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1`. After the April 5 terminal-tail guard, all
  three subpaths are correctness-clean on the current host, but none beats the shipped baseline on
  the full acceptance bundle. The latest rerun shows `quad` at `steady_dot_product ~2.9752x`,
  `gate_dot_product ~2.4771x`, disasm `66`; `double` at `~3.0132x`, `~2.6670x`, disasm `82`; and
  `scalar` at `~2.9798x`, `~2.4631x`, disasm `69`, versus baseline `~2.9142x`, `~2.6790x`,
  disasm `70` (`build/logs/perf-probe-arm64-fast-dot-madd-exact-subpaths-20260405_013631_40642.log`).
- For the arm64 exact-double tail-shape sweep, use
  `make perf-probe-arm64-fast-dot-madd-exact-double-sweep`. It builds the exact-double-only native
  `dot_product` benchmark once and then sweeps `n=1..N` (default `24`) at a fixed `reps` (default
  `1`). The current host now uses this as the correctness confirmation for the exact-double tail
  guard: the latest rerun is green for every sampled `n=1..24`, including the formerly unsafe
  `n ≡ 2 (mod 4)` cases such as `10`, `14`, `18`, and `22`
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-double-sweep-20260405_013604_40047.log`).
- For the exact-double control-flow snippet itself, use
  `make perf-probe-arm64-fast-dot-double-exit-snippet`. It rebuilds both the shipped baseline and
  the exact-double-only variant with `--disasm`, then extracts just the 2-wide block from the
  canonical `fast_list_int_dot_while_no_tick` window into one compact artifact. Use it before
  changing the exit-after-double path so the baseline `mul/add` block and the exact-double `madd`
  block are compared from the same traced loop window instead of hand-grepping full disassembly logs.
- The arm64 cursor-end-bounds dot experiment has been retired. The measured host signal was
  consistent enough to reject it: while the temporary lowering shrank canonical dot disassembly from
  `70` to `66` instructions, the later read-split rerun still regressed repeated-loop `dot_product`
  on both `native/C long-per-rep` (`~2.6003x -> ~2.6651x`) and `native/C delta`
  (`~2.8383x -> ~3.0797x`) (`build/logs/perf-probe-arm64-fast-dot-cursor-end-read-split-20260405_021431_93331.log`).
  The dedicated cursor-end probe scripts were removed after that verdict to keep the live perf
  surface focused on still-viable arm64 dot branches.
- The arm64 dot probe scripts now print a warning when the canonical one-program gate has high
  variance (`cov >= 0.10`) on either the C or native side, so obvious noisy outliers stop reading
  like trustworthy wins.
- Native/list<int> perf-gate, probe, smoke, prebuild, and benchmark result artifacts now use
  collision-resistant timestamps, so back-to-back variants do not overwrite each other’s logs or
  result files.
- The arm64 dot acceptance surface now applies `OREN_BENCH_ENV_BUILD_OREN` consistently to the
  smoke, disasm, steady/gate, and exact native debug legs, and records the active `build_env` in
  the acceptance summary. That closes the old mismatch where environment-gated compiler probes only
  affected part of one “acceptance” run.
- The direct-build exact-double helpers now follow the same rule:
  `make perf-probe-arm64-fast-dot-madd-exact-double-sweep` and
  `make perf-probe-arm64-fast-dot-double-exit-snippet` both honor
  `OREN_BENCH_ENV_BUILD_OREN` and record the active `build_env` in their summaries.
- The list<int> helper prebuild/smoke surfaces now follow the same rule as well:
  `build_perf_artifacts_list_int_{packed_bridge,slot_direct}.sh`,
  `make perf-smoke-list-int-packed-bridge`, and `make perf-smoke-list-int-slot-direct` all honor
  `OREN_BENCH_ENV_BUILD_OREN`, and the hidden steady helper probes now record `build_env` in their
  summaries. That closes the last mixed-baseline gap in the helper-path perf tooling.
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
