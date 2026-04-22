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
summary. The C loop extractor is label-agnostic now: it chooses the vector loops by `smlal*`
blocks and the scalar tail by `smaddl`, so Clang basic-block renumbering no longer breaks the
diagnostic. The latest artifact,
`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260422_002728_90700.log`, shows the kept Oren
generic `dot_product` path as a 20-instruction traced range. The updated Oren extractor also
separates the skipped cold GC-call block on the current tree: the range-without-cold-tick count is
12 instructions, with 8 instructions in the cold block. The host C reference still uses a NEON
vector loop (`ldp q*`, `smlal.2d`, `smlal2.2d`), vector mid loop, and scalar `smaddl` tail
(`28` / `12` / `6` instructions in the extracted blocks). That is the right current baseline when
judging future arm64 dot work: the remaining gap is versus a vectorized C loop and a measured slot64
scalar ceiling, not just the cold safepoint save/restore block in the traced range.
For the explicit `list<int>` counterpart, use
`make perf-probe-arm64-dot-vs-c-loop-compare-list-int`; latest artifact
`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-20260411_165935_82064.log` shows the same
21-instruction Oren traced range, 14-instruction range without the cold GC-call block, and the same
host C vector/mid/tail shape, with labels selected by instruction pattern rather than assumed
`LBB0_*` numbers.

The probe also now parses comma-separated `OREN_BENCH_ENV_BUILD_OREN` correctly, so multi-var build
env overrides reach the traced Oren build instead of being collapsed into one invalid token.

The 2026-04-11 scalar-post follow-up confirms that matching the host slot64 scalar loop's visible
post-index load plus `madd` shape is not sufficient by itself. With
`OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1`, the
explicit `dot_product_int` traced Oren range shrinks to 18 instructions, or 11 after excluding the
skipped 7-instruction cold GC-call block, but the decision probe still rejects the branch on the
read-split plus order-balanced gate surface.

To quantify how much of the remaining gap is still scalar-codegen debt versus the missing NEON path,
use:

```bash
make perf-probe-arm64-dot-vs-c-scalar-ceiling
make perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int
```

This builds [dot_product.c](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product/dot_product.c)
twice with the host `cc`: once with default `-O2`, and once with vectorization disabled
(`-O2 -fno-vectorize -fno-slp-vectorize` on the current clang host). It then times both C binaries
against the exact Oren native benchmark binary on the same `n/reps` workload. The `list<int>`
target uses [dot_product_int.c](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product_int/dot_product_int.c)
and [dot_product_int.oren](/Users/zongbaolu/work/compiler-mini/benchmarks/dot_product_int/dot_product_int.oren)
through the same runner.

The current precise-label artifacts,
`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log` and
`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int-20260411_164309_41086.log`, show:

- generic `dot_product`: vectorized C `~0.000253s`, scalar C `~0.000741s`, Oren native `~0.001368s`
  per rep; scalar/vector `~2.9275x`, Oren/scalar `~1.8452x`, Oren/vector `~5.4018x`
- explicit `dot_product_int`: vectorized C `~0.000250s`, scalar C `~0.000759s`, Oren native
  `~0.001301s` per rep; scalar/vector `~3.0352x`, Oren/scalar `~1.7130x`, Oren/vector `~5.1992x`
- both C sources extract the same precise inner-loop shapes: 28 instructions for the host NEON
  vector loop and 6 instructions for the de-vectorized scalar `smaddl` loop

That refresh changes the scalar-ceiling attribution: the current Oren loop still has material scalar
debt versus de-vectorized C, but the host C vector body is another roughly 3x faster than scalar C.
The next dot-parity work should therefore stay focused on vector/slot64 parity while keeping scalar
loop scheduling visible, not on generic-list specialization guesses.

The current generic scalar-core acceptance matrix,
`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`, keeps the
shipped baseline over the older scalar-only toggles on today’s tree: disabling
`OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS` regresses steady/gate native medians
`+3.76%` / `+4.67%`, `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` regresses
`+0.50%` / `+2.97%`, and the combined row regresses `+2.90%` / `+2.96%`. Treat that as a current
decision boundary: the next arm64 `dot_product` move should be a new vector/slot64-quality path,
not another cursor/scalar promotion from the older branch family.

And the exact canonical whole-list helper shortcut is now closed on the generic benchmark too. Use:

```bash
make perf-probe-arm64-fast-dot-whole-list-helper-decision
```

Latest artifact,
`build/logs/perf-probe-arm64-fast-dot-whole-list-helper-decision-20260422_004934_99469.log`,
shows `OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER=1` is materially worse than the shipped
generic baseline on the current tree:

- read-split `dot_product` `long_per_rep`: baseline `~0.002664s`, helper `~0.006172s`
  (`+131.68%`, `3.5494x C` -> `8.0141x C`)
- read-split repeated-work delta: `+270.80%`
- order-balanced perf gate native median: baseline `~0.015886s`, helper `~0.019043s`
  (`+20.08%`, `wins=0/4`)
- order-balanced native/C ratio median: baseline `~2.9800x`, helper `~3.5403x`
  (`+19.38%`, `wins=0/4`)

So the current generic `dot_product` blocker is no longer “maybe the whole-list helper should ship.”
That branch is closed on today’s shipped surface; the remaining credible W5 direction is a new
vector/slot64-quality path.

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

The current precise-label artifact, `build/logs/perf-probe-list-int-slot-abi-ceiling-20260411_181606_60508.log`,
shows:

- packed-i32 C vector: `~0.000250s` per rep
- packed-i32 C scalar: `~0.000747s` per rep
- slot64 C “vector”: `~0.000728s` per rep
- slot64 C scalar: `~0.000759s` per rep
- Oren native canonical: `~0.001305s` per rep
- Oren native slot-direct helper: `~0.003599s` per rep

The ratio view is the important part:

- slot64-vector / packed-vector: `~2.9086x`
- slot64-scalar / packed-scalar: `~1.0165x`
- Oren canonical / slot64-vector: `~1.7932x`
- Oren canonical / slot64-scalar: `~1.7195x`
- Oren slot-direct helper / slot64-vector: `~4.9453x`

And the assembly snippet matters too: the host compiler does not generate a NEON packed-lane loop
for the slot64 source. Its best `-O2` slot64 loop is still a paired-scalar `ldp` + `madd` shape,
not the packed `smlal/smlal2` loop seen in the packed-i32 benchmark. The corrected extractor now
reports 28 instructions for the packed-i32 NEON loop, 12 for the slot64 paired-scalar loop, and 6
for the slot64 scalar tail. That is the current ceiling fact to use for next-step planning: the
64-bit slot ABI itself largely erases the auto-vectorization gain, but the shipped Oren canonical
loop still has a material `~1.8x` gap against the slot64 host-C ceiling.

For the broader whole-operation picture across both `array_sum_int` and `dot_product_int`, use:

```bash
make perf-probe-list-int-c-ceiling
```

This builds and times eight binaries on the same `n/reps` workload:

- packed32 C `array_sum`
- slot64 C `array_sum`
- Oren native canonical `array_sum_int`
- packed32 C `dot_product`
- slot64 C `dot_product`
- Oren native canonical `dot_product_int`

Each C shape is timed both with default `-O2` and with vectorization disabled. The latest current-tree
artifact, `build/logs/perf-probe-list-int-c-ceiling-20260411_181614_60702.log`, shows:

- `array_sum_int`
  - packed32 C vector: `~0.000134s` per rep
  - packed32 C scalar: `~0.000731s` per rep
  - slot64 C vector: `~0.000246s` per rep
  - slot64 C scalar: `~0.000774s` per rep
  - Oren native canonical: `~0.000561s` per rep
- `dot_product_int`
  - packed32 C vector: `~0.000250s` per rep
  - packed32 C scalar: `~0.000737s` per rep
  - slot64 C vector: `~0.000738s` per rep
  - slot64 C scalar: `~0.000778s` per rep
  - Oren native canonical: `~0.001326s` per rep

The decisive ratios are:

- `array_slot64_vector / array_packed32_vector`: `~1.8365x`
- `oren_array_sum_int / array_slot64_vector`: `~2.2778x`
- `oren_array_sum_int / array_slot64_scalar`: `~0.7256x`
- `dot_slot64_vector / dot_packed32_vector`: `~2.9502x`
- `dot_slot64_scalar / dot_packed32_scalar`: `~1.0562x`
- `oren_dot_product_int / dot_slot64_vector`: `~1.7959x`

That is the current whole-operation ceiling fact on arm64 `master` after the explicit get-sum
unroll2 promotion: the helper/public-slot ranking question is no longer the main blocker, and the
shipped canonical `array_sum_int` path is no longer stuck around the earlier `~5.8x` slot64-vector
gap. `array_sum_int` still leaves a meaningful repeated-read gap to a competitive slot64 host-C
vector path, while `dot_product_int` remains materially above even the slot64 host-C ceiling after
the current 64-bit slot ABI has already erased most of the packed-vector gain.

For the current route-level decision surface that ties those facts to the helper/public/packed
alternatives, use:

```bash
make perf-probe-list-int-dot-route-decision
```

This wrapper reruns `perf-probe-list-int-slot-abi-ceiling`, `perf-probe-list-int-c-ceiling`, and
`perf-probe-list-int-dot-ceiling-stability`, then emits one decision summary. Current artifact:
`build/logs/perf-probe-list-int-dot-route-decision-20260411_181606_60502.log`.

- slot64 still loses packed-NEON headroom: `slot64_vector / packed_vector ~2.9086x` while
  `slot64_scalar / packed_scalar ~1.0165x`
- whole-operation gaps remain: `oren_dot_product_int / dot_slot64_vector ~1.7959x` and
  `oren_array_sum_int / array_slot64_vector ~2.2778x`
- route stability rejects all reroutes as default candidates:
  - hidden direct-slot wins dot on this rerun (`3/5`, median `-10.83%` vs baseline) but loses array
    badly (`1/5`, median `+18.24%`)
  - public-slot is mixed (`1/5` array wins, `1/5` dot wins)
  - packed bridge was far behind on that route artifact (`packed_simd` dot median `+301.76%` vs
    baseline), and the 2026-04-11 pointer-i32 pack-store improvement narrows but does not change that
    decision: `build/logs/perf-probe-list-int-dot-ceiling-stability-20260411_204859_99207.log` gives
    packed-SIMD `0/5` wins on both array and dot, with median deltas `+269.38%` array and `+134.27%`
    dot versus canonical baseline.

Verdict: keep shipped canonical lowering. The next dot route work should target a representation or
direct-lowering change for slot64, or a safe packed view, rather than re-routing through the current
helper/public/packed bridge surfaces or reopening scalar-tail scheduling toggles.

For the narrower slot-direct helper fast-tick experiment, use:

```bash
make perf-probe-list-int-slot-direct-fast-tick-decision
```

This wrapper serializes current default vs `OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1`, forcing the
shared read-split benchmark artifacts to rebuild for each side. Current artifact:
`build/logs/perf-probe-list-int-slot-direct-fast-tick-decision-20260411_194036_96087.log`.

- slot-ABI ceiling: direct helper regressed from `~0.001870s` to `~0.001874s` per rep
  (`+0.21%`), and the fast-tick helper still trailed canonical `~0.001296s` and host slot64 C
  `~0.000735s`
- read-split `array_sum_int`: slot-direct native/C moved from `~1.0010x` to `~1.1249x`
  (`+12.38%`)
- read-split `dot_product_int`: slot-direct native/C moved from `~1.2931x` to `~1.3051x`
  (`+0.93%`)

Verdict: keep the reduced slot-helper safepoint spill / 4095-tick-mask branch opt-in. It is useful as
a bounded direct-lowering probe, but it does not change the next W5 direction: the remaining work is
still a real representation/direct-lowering path, not a tick/spill shortcut inside the current helper
loop.

For the counted 2-wide raw-slot helper pair-loop experiment, use:

```bash
make perf-probe-list-int-slot-direct-pair-loop-decision
```

This wrapper serializes default, fast-tick, pair-loop, and pair-loop+fast-tick builds, then restores
the default shared slot-direct artifacts. Current artifact:
`build/logs/perf-probe-list-int-slot-direct-pair-loop-decision-20260411_195615_19255.log`.

- `OREN_ARM64_LIST_INT_SLOT_DIRECT_PAIR_LOOP=1` is not promotable: slot-ABI direct-helper time
  regressed `+3.15%`, read-split `array_sum_int` slot-direct native/C regressed `+9.88%`, and
  only `dot_product_int` improved (`-3.31%`).
- Pair-loop plus fast-tick is also not promotable: slot-ABI direct-helper time regressed `+3.42%`,
  read-split `array_sum_int` regressed `+7.70%`, and `dot_product_int` improved `-7.55%`.

Verdict: keep the counted raw-slot helper pair-loop opt-in. It closes the cheap scalar helper
scheduling branch; W5 still needs a real representation/direct-lowering path such as a safe packed
view or stronger slot64 direct lowering.

For the direct `array_sum_int` slot64 SIMD-add experiment, use:

```bash
make perf-probe-arm64-fast-get-sum-vector-2d-decision
```

This wrapper structurally checks the emitted loop, compares default vs
`OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1` on the local arm64 acceptance surface, then runs an
order-balanced same-tree C-ceiling surface. Current widened artifact:
`build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`.

- Structural shape is the intended 64-bit slot SIMD-add body: the traced `array_sum_int` range is
  `51` instructions, `41` after subtracting two cold GC tick blocks, with `ldr q` loads (`3` in the
  snippet), `add.2d=1`, and `addp.2d=2`.
- Local acceptance preferred enabled on native medians (`steady -7.95%`, `gate -1.62%`), but the
  same-tree C-ceiling decision surface rejected promotion: `array_default_wins: 4/5`,
  default median `oren_array_sum_int / array_slot64_vector ~2.2140x`, enabled median `~2.2967x`
  (`+3.74%`).
- The `dot_product_int` control moved toward enabled (`~1.8505x -> ~1.7878x`, `4/5` wins), which is
  noise/control context here because this knob only changes the get-sum emitter.

Verdict: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D` opt-in. This confirms that simply using
AdvSIMD pairwise add on the current 64-bit slot stream is not a stable shipped `array_sum_int` fix;
the W5 representation work still needs either a stronger slot64 direct lowering or a safe packed view.

For the arm64 SIMD ISA feasibility check behind that reweighting, use:

```bash
make verify-native-arm64-slot64-simd-isa
```

Current artifact: `build/logs/verify_arm64_slot64_simd_isa_20260411_202346_64385.log`. The host
assembler accepts 64-bit slot vector add/reduce (`ldr q`, `add.2d`, `addp.2d`) and packed-i32
widening dot (`smull.2d`, `smull2.2d`), but rejects true 64-bit-lane vector multiply
(`mul v*.2d`). This keeps the dot-side representation question precise: packed i32 can use the
existing widening multiply path, but the current slot64 ABI cannot become a true 64-bit SIMD dot by
only swapping the scalar multiply instruction.

To separate one-time setup from the repeated `array_sum_int` read loop directly, use:

```bash
make perf-probe-list-int-array-sum-c-breakdown
```

This runs the same workload at `short_reps=1` and `long_reps=100` for packed32 C, slot64 C, and
the shipped native `array_sum_int`, then derives a coarse `setup_est_s` and `steady_per_rep_s`.
Current final-tree artifact:
`build/logs/perf-probe-list-int-array-sum-c-breakdown-20260409_143718_76549.log`

- Oren canonical setup estimate: `~0.009496s`
- slot64 C vector setup estimate: `~0.004273s`
- Oren canonical steady per-rep: `~0.001311s`
- slot64 C vector steady per-rep: `~0.000204s`
- Oren/slot64-vector steady ratio: `~6.4228x`

The short-run setup estimate is still noisy enough that it should not be used alone for default
shipping decisions. The stable fact from this probe is narrower: the repeated `array_sum_int`
read/accumulate kernel is still far above the slot64 C vector path on the same workload.

To pin the adjacent list-build side on the same shipped tree, use:

```bash
make perf-probe-list-int-fill-share-decision
```

This adds a hidden single-list `list<int>` fill-only benchmark (`benchmarks/fill_list_int`) and
pairs it with the exact `array_sum_int` breakdown surface above. Current artifact
`build/logs/perf-probe-list-int-fill-share-decision-20260409_181428_58993.log` says the fill side
is no longer small enough to ignore:

- fill-only Oren `list<int>`: `per_rep_s ~0.005037`
- fill-only slot64 C vector: `per_rep_s ~0.001044`
- fill-only slot64 C scalar: `per_rep_s ~0.001462`
- exact `array_sum_int` breakdown on the same tree:
  - Oren setup estimate: `~0.008520s`
  - Oren steady per-rep: `~0.000490s`
  - slot64 C vector steady per-rep: `~0.000194s`
- derived:
  - `oren_fill_list_int / c_fill_slot64_vector ~4.8260x`
  - `oren_fill_list_int / oren_array_sum_setup_est ~0.5912x`
  - `oren_fill_list_int / oren_array_sum_steady_per_rep ~10.2796x`

That reweighted the current blocker correctly. The repeated-read `array_sum_int` loop is still
above the slot64 C vector ceiling, but a single allocation+fill pass is materially larger in
absolute time than the current shipped steady read kernel.

One follow-up question on the same tree is now settled too: the large `fill_list_int` constructor is
already arena-backed on the shipped path, so constructor routing itself is not the remaining fill
blocker. A targeted native trace rerun
(`build/logs/run_fill_list_int_ctor_probe_final_20260409.log`) shows the benchmark-sized allocation as
`[list_new_cap] kind=8 cap=2000000 total=16000032 mode=2`, with matching constructor stages for the
same pointer. `mode=2` is the arena-backed constructor path
([`lib/runtime_native/095_arena.oren`](/Users/zongbaolu/work/compiler-mini/lib/runtime_native/095_arena.oren)),
not the plain `oren_new_list_int` malloc path in
([`lib/runtime_native/170_lists_core.oren`](/Users/zongbaolu/work/compiler-mini/lib/runtime_native/170_lists_core.oren)).
Reweight accordingly: keep attacking fill-loop bookkeeping/lifetime cost below the constructor
rather than adding another broad constructor rewrite.

The next shipped fill-side follow-up on that same tree is:

```bash
make perf-probe-arm64-fast-push-idx-expr-decision
```

This measures the new default-on arm64 compiler fast path gated by
`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR`, which keeps pure index-only integer push expressions on
the explicit `fast_list_int_push_while` lowering instead of routing them through generic
`native_compile_expr(...)`. Current widened rerun
`build/logs/perf-probe-arm64-fast-push-idx-expr-decision-20260409_183650_90548.log` says the
shipped default now wins on both relevant surfaces:

- fill/share surface:
  - default `oren_fill_list_int / c_fill_slot64_vector ~4.4912x`
  - disabled `~5.0143x`
  - `fill_pref: default`
- exact same-tree whole-operation C ceiling:
  - `default_array_ratio_median ~2.2989x` vs disabled `~2.3437x` (`array_default_wins: 3/5`)
  - `default_dot_ratio_median ~1.8313x` vs disabled `~1.8546x` (`dot_default_wins: 4/5`)
  - `decision_surface_alignment: agree`

That is the current production-quality fill-side result: keep
`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR` shipped on, and keep chasing the larger list build/fill
lifetime cost from this new baseline instead of going back to rejected get-sum-local branches.

For the narrower preserved-cursor follow-up on top of that same shipped fill-side baseline, use:

```bash
make perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision
```

This compares the shipped default against explicit disable
`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS=0`, which keeps the single-list
idx-expression cursor and loop bounds live in preserved regs instead of round-tripping them through
stack slots each iteration. The current-tree promoted-default decision artifact
`build/logs/perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision-20260423_025433_17194.log`
now keeps that cursor-reg path shipped on:

- fill/share surface preferred the shipped default
  - default `oren_fill_list_int / c_fill_slot64_vector ~1.7572x`
  - disabled `~2.3562x`
  - `fill_pref: default`
- exact same-tree whole-operation C ceiling also preferred the shipped default
  - `default_array_ratio_median ~2.2127x` vs disabled `~2.2219x` (`array_default_wins: 2/3`)
  - `default_dot_ratio_median ~1.3770x` vs disabled `~1.5110x`
  - `decision_surface_alignment: agree`

Reweight accordingly: `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS` now ships on by default.
The branch is no longer just a local fill/setup win; on the current tree it also survives the exact
same-tree whole-operation ranking surface.

For the next fill-side lowering on that same shipped baseline, use:

```bash
make perf-probe-arm64-fast-push-nonneg-linear-decision
```

This compares the shipped default against `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=0` after
teaching the arm64 explicit `fast_list_int_push_while` lowering to recognize nonnegative
affine/mod index expressions with a proven safe loop-bound ceiling. The current-tree widened
decision artifact `build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_034811_37016.log`
still keeps that branch shipped on by default:

- fill/share surface strongly preferred the shipped default
  - default `oren_fill_list_int / c_fill_slot64_vector ~2.4026x`
  - disabled `~5.0016x`
  - `fill_pref: default`
- exact same-tree whole-operation C ceiling also preferred the shipped default
  - `default_array_ratio_median ~2.2189x` vs disabled `~2.2980x` (`exact_array_pref: default`)
  - `default_dot_ratio_median ~1.5522x` vs disabled `~1.6406x` (`exact_dot_pref: default`)
  - `decision_surface_alignment: agree`

Keep `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR` shipped on. This is the next current-tree
fill-side improvement after `PUSH_IDX_EXPR` that wins on both the fill attribution surface and the
exact same-tree whole-operation surface instead of only one of them.

The emitted-code contract under that shipped branch is now guarded too. Disassembly of the real
`array_sum_int` push loop showed `_arm64_emit_fast_loop_nonneg_linear_to_x0(...)` was reusing `x9`
for mul/add/mod immediates even though inline GC countdown uses `x9` as the tick register. The
helper now keeps `x9` reserved and uses `x11`/`x10` scratch instead, push loops now publish
`[arm64_loop_range]` traces, and `make verify-native-list-int-fast-lowering`
(`build/logs/verify_native_list_int_fast_lowering_20260423_034642_36487.log`) now disassembles the
`array_sum_int` push loop and rejects any hot-loop `x9` use other than `subs x9, x9, #0x1`.

For the remaining emitted-code work below that branch, use:

```bash
make perf-probe-arm64-list-int-fill-hot-loop-disasm
```

This disassembles the current shipped `fast_list_int_push_while*` loop for both `fill_list_int`
and `array_sum_int`, excludes the cold GC tick block, and summarizes the hot-body mnemonic mix.
Current shipped artifact `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_042356_51281.log`
shows the fill loop at 25 total instructions / 17 hot instructions with the same hot mix on both
benchmarks: one slot write, two `mul`, one `udiv`, one `sub`, three `add`, one `subs` tick, and no
count/cursor writeback inside the hot body beyond the final cursor increment.

That probe also closes the obvious “just fuse the remainder pair” branch. A narrow rerun replaced
the shipped `udiv; mul; sub` remainder sequence with `udiv; msub`, which reduced the emitted hot
body from 17 to 16 instructions (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_041825_49207.log`)
but still regressed on the actual shipped decision surface
(`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_041844_49343.log`):

- fill/share moved the wrong way
  - shipped default with `msub` `oren_fill_list_int / c_fill_slot64_vector ~2.4590x`
  - reverted shipped baseline `~2.4026x`
- exact same-tree whole-operation medians also worsened
  - `default_array_ratio_median ~2.2222x` vs reverted shipped baseline `~2.2189x`
  - `default_dot_ratio_median ~1.6367x` vs reverted shipped baseline `~1.5522x`

So the shipped path stays with the simpler `mul; sub` remainder pair for now. The next emitted-code
work should use the fill-hot-loop probe to target the surviving slot-write, cursor/count finalization,
or safepoint-reset structure rather than assuming a one-instruction arithmetic fusion will help.

One narrower follow-up under that same family was tested and then pruned immediately instead of
being left behind as another dead branch. The recurrence variant tried to replace the per-iteration
`udiv`-based `%` recomputation with a carried modulo recurrence for the single-list cursor case, but
the widened cached decision artifact
`build/logs/perf-probe-arm64-fast-push-nonneg-linear-recurrence-decision-20260410_001827_33770.log`
did not support shipping it:

- fill/share still preferred the shipped default
  - default `oren_fill_list_int / c_fill_slot64_vector ~4.7537x`
  - disabled `~4.8312x`
  - `fill_pref: default`
- exact same-tree whole-operation C ceiling preferred the disabled branch on both tracked programs
  - `default_array_ratio_median ~2.3187x` vs disabled `~2.2727x` (`exact_array_pref: disabled`)
  - `default_dot_ratio_median ~1.7935x` vs disabled `~1.7737x` (`exact_dot_pref: disabled`)
  - `decision_surface_alignment: disagree`

So the shipped nonnegative-linear path stays the simpler direct mul/add/(u)div lowering. The
recurrence subpath was removed from the tree rather than kept as another speculative opt-in.

For explicit `fast_list_int_push_while` safepoint tick-mask follow-up work, use:

```bash
make perf-probe-arm64-fast-push-tick-mask-decision
```

This compares the shipped `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=4095` behavior against
`16383` and `65535` on both the fill/share attribution surface and same-tree whole-operation
`array_sum_int` / `dot_product_int` C-ceiling reruns. Treat it as a decision surface for the
explicit push loop only; higher masks need agreement across both surfaces before changing the
shipped default.

The current-tree refresh split into a tempting candidate and a rejected promoted-default rerun:

- candidate rerun
  (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032104_29410.log`)
  looked good enough to try: fill/share preferred `65535` (`default_fill_vs_c_vector ~1.8155x`,
  `mask_16383 ~1.8369x`, `mask_65535 ~1.7173x`), exact `array_sum_int` median also preferred
  `65535` (`default ~2.2131x`, `mask_16383 ~2.1760x`, `mask_65535 ~2.1398x`), exact
  `dot_product_int` median preferred `65535` too (`default ~1.4062x`, `mask_16383 ~1.4727x`,
  `mask_65535 ~1.3362x`), and `decision_surface_alignment: agree`
- immediate promoted-default rerun
  (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032751_32000.log`) did not
  hold: fill/share flipped toward the lower masks (`default_fill_vs_c_vector ~1.8792x`,
  `mask_4095 ~1.7483x`, `mask_16383 ~1.7535x`), while exact `array_sum_int` and
  `dot_product_int` medians both preferred `16383` (`default_array_ratio_median ~2.1792x`,
  `mask_4095 ~2.1950x`, `mask_16383 ~2.1736x`; `default_dot_ratio_median ~1.7445x`,
  `mask_4095 ~1.7506x`, `mask_16383 ~1.7229x`), leaving `decision_surface_alignment: disagree`

Keep `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=4095` shipped for now; the higher masks are still
probe-only because the promoted-default rerun was not stable enough to keep.

One more narrower fast-loop follow-up on the same shipped fill surface is now also closed. The exact
same-tree baseline remains
`build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`
(`oren_fill_list_int / c_fill_slot64_vector ~2.3103x`, fill `per_rep_s ~0.003096`). A focused
rerun that replaced the generic inline-tick preserved-reg spill set with the narrower explicit-pairs
path for `fast_list_int_push_while`
(`build/logs/perf-probe-list-int-fill-share-decision-20260423_022302_10735.log`) still moved the
wrong way (`~2.3697x`, fill `per_rep_s ~0.003107`). Reweight again: the remaining shipped fill-side
cost is not solved by just narrowing the safepoint spill pairs on the explicit push loop, so the
next pass should stay below that branch too.

One more emitted-code-grounded follow-up on that same baseline is now closed too. The first naive
reciprocal-fastmod rewrite lost because it replaced the `udiv` with an `umulh` path but also
materialized the 64-bit reciprocal constant inside the hot loop each iteration; the disassembly in
`build/logs/otool_fill_list_int_oren_inspect_fastmod_full_20260423_v1.log` shows that four-instruction
`movz/movk` literal sequence immediately before the loop `umulh`. A narrower rerun then hoisted the
shared `% 1000` divisor and reciprocal into preheader regs and kept the reciprocal path only on the
shipped nonnegative-linear `fast_list_int_push_while` surface. That mechanical fix was real, but it
still lost on the actual shipped decision surface:

- exact same-tree rerun
  (`build/logs/perf-probe-list-int-fill-share-decision-20260423_024106_13895.log`) regressed from
  baseline `~2.3103x` / `~0.003096` to `~2.8408x` / `~0.003746`
- emitted code after the hoist
  (`build/logs/otool_fill_list_int_oren_inspect_fastmod_hoist_full_20260423_v1.log`) shows
  `x24=#1000` and `x25=<reciprocal>` loaded once in the preheader and the hot loop using
  `umulh x10, x0, x25`, so the loss is no longer explained by reciprocal literal materialization
  alone

Reweight again: the remaining shipped fill-side blocker is now below both the safepoint-pair trim
and the reciprocal-hoist explanation. The next emitted-code pass should inspect the surviving loop
body around slot writes, count/cursor updates, and safepoint reset scaffolding instead of reopening
either rejected reciprocal branch.

One more aggressive follow-up on that same baseline was tested and then removed from the tree: a
single-list whole-fill runtime helper that replaced the explicit push loop with one
`native_list_int_try_fill_nonneg_linear_exact(...)` call. It did trigger on
`benchmarks/fill_list_int/fill_list_int.oren`, but the decision artifact
`build/logs/perf-probe-arm64-fast-push-fill-helper-decision-20260409_223410_5754.log` made the
result decisive enough to prune immediately:

- fill/share surface collapsed from default `~2.3500x` to enabled `~98.8846x`
- exact `array_sum_int` median regressed from default `~2.1732x` to enabled `~6.0964x`
- exact `dot_product_int` median improved slightly (`~1.8157x` -> `~1.7652x`), but not enough to
  offset the fill/array loss

Reweight again: the next fill/setup lifetime pass should stay on safer allocation/fill lowering, not
on whole-list runtime helper rerouting for the explicit `list<int>` push loop.

For the native fast-loop list header trace default on that same shipped baseline, use:

```bash
make perf-probe-arm64-fast-push-native-list-hdr-decision
```

This compares the shipped default against `OREN_TRACE_NATIVE_LIST_HDR=1` after aligning explicit
`fast_list_int_push_while` with the existing compile-time native list-header trace knob instead of
emitting loop-exit `oren_trace_list_header(...)` calls unconditionally for `list<int>` fast push
loops.

Current widened cached reruns keep native fast-loop list-header tracing opt-in only:

- first rerun
  (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_213946_33097.log`)
  slightly preferred `OREN_TRACE_NATIVE_LIST_HDR=1` on fill/share and exact `array_sum_int`
  (`trace_enabled_fill_vs_c_vector ~2.9109x` vs default `~3.0188x`,
  `trace_enabled_array_ratio_median ~2.1585x` vs default `~2.2058x`), but exact
  `dot_product_int` still preferred the shipped default (`default_dot_ratio_median ~1.7299x`
  vs `trace_enabled ~1.7855x`).
- second rerun
  (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_214130_36680.log`)
  kept fill/share narrowly in favor of `OREN_TRACE_NATIVE_LIST_HDR=1`
  (`~2.8810x` vs default `~2.9011x`) but flipped exact `array_sum_int` back to the shipped
  default by median (`default_array_ratio_median ~2.1640x` vs `trace_enabled ~2.1655x`) and
  kept exact `dot_product_int` strongly with the shipped default (`default_dot_ratio_median
  ~1.7383x` vs `trace_enabled ~1.7840x`, `dot_default_wins: 5/5`).
- final cached rerun on the finished scripts
  (`build/logs/perf-probe-arm64-fast-push-native-list-hdr-decision-20260409_220014_61301.log`)
  still did not settle the exact whole-operation ranking:
  - fill/share again preferred `OREN_TRACE_NATIVE_LIST_HDR=1`
    (`trace_enabled_fill_vs_c_vector ~2.8173x` vs default `~3.1008x`)
  - exact `array_sum_int` preferred the shipped default
    (`default_array_ratio_median ~2.1390x` vs `trace_enabled ~2.1702x`)
  - exact `dot_product_int` flipped the other way and narrowly preferred
    `OREN_TRACE_NATIVE_LIST_HDR=1`
    (`trace_enabled_dot_ratio_median ~1.7830x` vs default `~1.8028x`)
  - `decision_surface_alignment: disagree`

Reweight accordingly: the compiler/runtime fix is correct and shipped, but native fast-loop list
header tracing remains a debug-only opt-in path. Across three widened cached reruns, the exact
same-tree whole-operation surface never produced a stable production-quality winner.

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

Arm64-only acceptance bundle for the explicit `list<int>` hot benchmarks. This mirrors the generic
`array_sum` / `dot_product` acceptance tool, but packages the exact `array_sum_int` /
`dot_product_int` smoke, traced disasm, steady gate, whole-operation gate, and exact-binary debug
rerun into one comparable artifact:

```bash
make perf-probe-arm64-list-int-acceptance
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

That smoke now validates both hidden helper-entry benchmarks
(`array_sum_int_slot_direct` / `dot_product_int_slot_direct`) and the hidden public-stdlib
slot-surface benchmarks (`array_sum_int_slot_public` / `dot_product_int_slot_public`), plus the
unchecked helper edge-contract fixture.

Explicit native prebuild for the hidden packed-bridge benchmarks:

```bash
make perf-prebuild-list-int-packed-bridge
```

Explicit native prebuild for the slot-surface benchmarks:

```bash
make perf-prebuild-list-int-slot-direct
```

That warm step now builds the hidden helper-entry benchmarks and the hidden public-stdlib
slot-surface benchmarks together, so later helper-vs-public comparisons reuse the same native/C
artifact set.

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

That helper surface is no longer benchmark-only. `std:linalg` now exposes
`reduce_sum_i64_list_int_slots(...)` and `dot_i64_list_int_slots(...)` on the shared C/native/AVM
surface. Those entrypoints fast-path through `oren_is_list_int(...)` plus the direct-slot helpers
when the backend can prove an all-int list and fall back to a portable scalar list walk otherwise,
so `make verify-backend-parity-list-int` now covers the public slot-direct API as well as the hidden
ceiling benchmarks.

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

That verifier now inherits the widened slot-surface smoke, so it also checks the public
`array_sum_int_slot_public` / `dot_product_int_slot_public` numerics alongside the hidden helper
benchmarks, the checked-helper `invalid_arg` contract, and the unchecked-helper panic contracts.

For one ranked view of the current `list<int>` `dot_product` alternatives, use:

```bash
make perf-probe-list-int-dot-ceiling
```

This runs a deliberately small fast-profile steady comparison across the canonical `list<int>` fast
loop, the unchecked direct-slot helper path, and the packed-bridge scalar/SIMD paths. The default
profile is `runs=2`, `warmups=0`, `n=20000`, `reps=2`; override it with
`OREN_LIST_INT_DOT_CEILING_{RUNS,WARMUPS,N,REPS}` when you want a different scale.

One representative earlier light artifact,
`build/logs/perf-probe-list-int-dot-ceiling-20260409_113946_99659.log`, kept the public
`std:linalg` slot surface in the same steady ranking:

- baseline canonical `dot_product_int`: `~1.3221x C`
- direct-slot helper `dot_product_int_slot_direct`: `~1.0920x C`
- public-slot `dot_product_int_slot_public`: `~1.2079x C`
- packed bridge SIMD `dot_product_int_packed_bridge`: `~5.3266x C`
- packed bridge scalar `dot_product_int_packed_bridge`: `~17.1611x C`

On the same run, `array_sum_int` came back as canonical `~1.4110x C`, hidden direct-slot helper
`~1.0019x C`, and public-slot `~1.0800x C`. The follow-up that produced those numbers was not just
measurement churn:

- native checked raw helpers now match AVM/C parity by returning structured `invalid_arg` errors on
  bad input instead of panicking
- the public fast path still uses the unchecked raw helper once `oren_is_list_int(...)` has already
  proven the input, but it now uses `oren_list_int_len_unchecked(...)` for the typed mismatch guard
  instead of paying the safer `list.int_len(...)` probe again
- the new internal `oren_list_int_*_slots_try_fast(...)` helpers remain unshipped for the public
  `std:linalg` routing because the candidate reroute regressed badly on the same steady probe
  (`build/logs/perf-probe-list-int-dot-ceiling-20260409_113108_86448.log`:
  public-slot `dot_product_int` `~3.2619x C`, public-slot `array_sum_int` `~2.1178x C`)

That earlier light probe showed why the public `std:linalg` slot surface kept looking like a serious
candidate relative to the shipped canonical path, but the light surface is too swingy to use alone.
Keep using this quick ceiling probe as the cheap sanity surface; the remaining gap is still narrow,
but it is no longer large enough to justify packed-bridge detours.

For order-sensitive ranking decisions, use:

```bash
make perf-probe-list-int-dot-ceiling-stability
```

This runs the same five cases as the quick ceiling probe, but does it in an order-balanced
round-robin across five sweeps so each case appears in each starting position once. The default
profile is still intentionally moderate (`sweeps=5`, `runs=3`, `warmups=1`, `n=20000`, `reps=4`);
override it with `OREN_LIST_INT_DOT_CEILING_STABILITY_{SWEEPS,RUNS,WARMUPS,N,REPS,COV_WARN}` when
you want a different scale. Use this target when you need to decide whether canonical, public-slot,
or hidden direct-slot is actually winning on the current tree.

The latest artifact, `build/logs/perf-probe-list-int-dot-ceiling-stability-20260409_123207_90132.log`,
comes back as:

- `array_sum_rank_counts`: canonical won `2/5` sweeps, direct-slot `2/5`, public-slot `1/5`
- `dot_product_rank_counts`: canonical won `3/5` sweeps, public-slot `2/5`, direct-slot `0/5`
- median `array_sum_int` ratios: canonical `~1.1887x C`, direct-slot `~1.2329x C`, public-slot
  `~1.2729x C`
- median `dot_product_int` ratios: canonical `~1.2177x C`, public-slot `~1.2231x C`, direct-slot
  `~1.3097x C`

That is the calmer ranking fact to use on current arm64 `master`: the shipped canonical path is now
the best repeated whole-operation median on this stronger probe, public-slot stays close enough to
win some `dot_product_int` sweeps, and the hidden direct-slot helper is no longer a stable
whole-operation winner. Reweight accordingly: use the stability probe for ordering decisions, keep
the quick ceiling probe for fast sanity checks, and do not assume more public/helper lowering will
automatically beat the current canonical arm64 path.

For the same short/long split surface, but comparing canonical against the hidden direct-slot helper
instead of the packed bridge, use:

```bash
make perf-probe-list-int-slot-direct-read-split
```

This warms the hidden direct-slot artifacts once and then reruns canonical `array_sum_int` /
`dot_product_int` against `array_sum_int_slot_direct` / `dot_product_int_slot_direct` on the same
small read-split harness. The default profile matches the packed-bridge split probe:
`runs=2`, `warmups=0`, `n=20000`, `short_reps=1`, `long_reps=2`; override it with
`OREN_LIST_INT_SLOT_DIRECT_SPLIT_{RUNS,WARMUPS,N,SHORT_REPS,LONG_REPS}` if needed.

The latest no-smoke artifact, `build/logs/perf-probe-list-int-slot-direct-read-split-20260408_235243_30345.log`,
comes back as:

- canonical `array_sum_int`: `~1.3410x C` long-per-rep
- direct-slot `array_sum_int_slot_direct`: `~1.0383x C` long-per-rep
- canonical `dot_product_int`: `~1.2680x C` long-per-rep
- direct-slot `dot_product_int_slot_direct`: `~1.1637x C` long-per-rep

The same rerun also produced unstable split deltas on `dot_product_int` (canonical `~-0.0273x C`,
direct-slot `~7.6465x C`), so use the `long_per_rep` side for tracker updates. That is the current
decision-quality result: the hidden direct-slot helper is now a better whole-operation ceiling than
the shipped canonical loop on this split, which makes canonical/direct-slot convergence the higher
value next step than more packed-bridge tuning.

A later exact whole-list shortcut follow-up on 2026-04-09 showed that this does **not** mean the
canonical loop should just call the unchecked helper by default. Use
`make perf-probe-arm64-whole-list-get-sum-helper-decision` for the current shipped-tree decision
surface.

The latest artifact,
`build/logs/perf-probe-arm64-whole-list-get-sum-helper-decision-20260409_173112_97220.log`,
comes back as:

- exact current-tree `array_sum_int`: shipped default `~1.9974x` vs helper-enabled `~13.6272x`
  (`exact_array_winner: default`, helper/default `~6.8225x`)
- exact current-tree `dot_product_int`: shipped default `~1.7628x` vs helper-enabled `~1.8728x`
- small read-split hidden helper ceiling stays decent: `slot_direct_array_long_per_rep ~1.0113x`,
  `slot_direct_vs_canonical_array_long_per_rep ~0.7866x`

That is the important split: the hidden direct helper ceiling can still be useful context on the
small split surface, but the canonical whole-list helper shortcut is still the wrong production
move on the exact current tree. Keep
`OREN_NATIVE_FAST_LIST_INT_GET_SUM_WHOLE_LIST_HELPER=1` /
`OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER=1` opt-in only.

Also: do not run enabled-vs-disabled comparisons for this target in parallel. The benchmark build
artifacts are shared, so causal A/B runs need to be serialized.

For the same short/long split surface, but comparing the public `std:linalg` slot wrappers against
both the shipped canonical loops and the hidden direct-slot helper ceiling, use:

```bash
make perf-probe-list-int-slot-surface-read-split
```

This warms the slot-surface artifacts once and then reruns canonical `array_sum_int` /
`dot_product_int` against both `*_slot_direct` and `*_slot_public` on the same read-split harness.
The default profile matches the helper-only split probe:
`runs=2`, `warmups=0`, `n=20000`, `short_reps=1`, `long_reps=2`; override it with
`OREN_LIST_INT_SLOT_SURFACE_SPLIT_{RUNS,WARMUPS,N,SHORT_REPS,LONG_REPS}` when needed.

The latest no-smoke artifact, `build/logs/perf-probe-list-int-slot-surface-read-split-20260409_101010_63997.log`,
comes back as:

- canonical `array_sum_int`: `~1.2800x C` long-per-rep
- direct-slot `array_sum_int_slot_direct`: `~1.0584x C` long-per-rep
- public-slot `array_sum_int_slot_public`: `~1.2717x C` long-per-rep
- canonical `dot_product_int`: `~1.2829x C` long-per-rep
- direct-slot `dot_product_int_slot_direct`: `~1.1687x C` long-per-rep
- public-slot `dot_product_int_slot_public`: `~1.1927x C` long-per-rep

This surface is still noisy enough that you should not use it alone to rank public-slot vs
hidden-helper ordering. A smoke-on rerun earlier the same day (`build/logs/perf-probe-list-int-slot-surface-read-split-20260409_050248_17126.log`)
actually flipped the `dot_product_int` public/helper ordering. Treat the split probe as a sanity
check that the public surface stays in the same ballpark, but use the steady
`make perf-probe-list-int-dot-ceiling` ranking above for the current decision-quality ordering.

On 2026-04-09, the arm64 compiler-side list fast-loop validation was also converged onto the same
alloc-index lookup x64 already uses (`native_alloc_index_get` instead of the older
`oren_find_node` path in `lib/compiler/arm64_native_stmt_loops_list_emit.oren`). Two serialized
steady ceiling reruns after that change both improved the shipped canonical baseline relative to
the earlier `build/logs/perf-probe-list-int-dot-ceiling-20260409_113946_99659.log` snapshot:

- `build/logs/perf-probe-list-int-dot-ceiling-20260409_115936_33151.log`
  - canonical `array_sum_int`: `~1.2173x C`
  - canonical `dot_product_int`: `~1.3071x C`
- `build/logs/perf-probe-list-int-dot-ceiling-20260409_120228_38413.log`
  - canonical `array_sum_int`: `~1.2781x C`
  - canonical `dot_product_int`: `~1.2155x C`

The direct-slot/public ordering still flipped between those light reruns, so do not rewrite the
ranking story from this batch alone. The later order-balanced stability probe above is now the
decision-grade surface; the stable claim from the alloc-index batch is narrower: the arm64
alloc-index convergence improved the shipped canonical path on repeated serial reruns and stayed
correctness clean.

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

The latest artifact, `build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log`,
was run with `build_env: OREN_NATIVE_RUNTIME_PROFILE=core` and came back as:

- baseline canonical `dot_product_int`: `~1.3778x C` long-per-rep
- packed bridge scalar `dot_product_int_packed_bridge`: `~13.5584x C` long-per-rep
- packed bridge SIMD `dot_product_int_packed_bridge`: `~4.1480x C` long-per-rep,
  `~0.4993x C` delta

That changes the main attribution for the current bridge. After the new runtime-backed pack fast
path, the repeated packed-SIMD kernel work is no longer the blocker; on this split it is already
below C on the `delta` metric. The remaining gap is the one-shot `list<int> -> []i32`
materialization/setup cost, so future bridge work should target export elimination, reuse, or
prepacking rather than more inner-kernel tuning.

The current shared stdlib also exposes explicit caller-managed workspace reuse:

- `linalg.dot_i32_list_int_packed_reuse(packed_a, packed_b, a, b)`
- `linalg.reduce_sum_i32_list_int_packed_reuse(packed_a, a)`

Those repack into caller-provided `[]i32` work buffers via `buffer.i32_pack_list_int_into(...)`
instead of allocating fresh packed buffers inside every call. The latest read-split rerun,
`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log`, shows why
that is useful but not sufficient:

- baseline canonical `dot_product_int`: `~1.2915x C` long-per-rep
- fresh-pack SIMD (`OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_ENABLE_SIMD=1`): `~7.3906x C`
- reuse-work SIMD (`OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1,OREN_ENABLE_SIMD=1`): `~7.2240x C`
- pack-once SIMD (`OREN_ENABLE_SIMD=1`): `~4.4566x C`

So destination-buffer reuse trims only a small slice of the fresh-pack cost and still loses badly
to the existing pack-once bridge. The next bridge move should therefore target eliminating or
hoisting the repeated materialization/copy itself, not just reusing the output buffer.

The 2026-04-11 native pointer-i32 follow-up changes the cost floor, but not the shipping decision.
`oren_ptr_get_i32_le` and `oren_ptr_set_i32_le` now have arm64/x64 native intrinsics, and the
runtime `list<int> -> []i32` pack loop uses the 32-bit store helper instead of four byte stores per
element. The current artifact,
`build/logs/perf-probe-list-int-packed-bridge-read-split-20260411_203510_80313.log`, was run at the
same small read-split profile (`runs=2`, `warmups=0`, `n=20000`, `short_reps=1`, `long_reps=2`) and
comes back as:

- baseline canonical `dot_product_int`: `~1.2150x C` long-per-rep
- fresh-pack SIMD: `~4.6037x C` long-per-rep
- reuse-work SIMD: `~4.0130x C` long-per-rep
- pack-once SIMD: `~2.3687x C` long-per-rep, `~2.4378x C` delta
- pack-once SIMD / baseline long-per-rep: `~1.9495x`

A bounded steady cross-check,
`build/logs/perf-probe-list-int-packed-bridge-20260411_204441_93198.log`, used `runs=2`,
`warmups=0`, `n=20000`, and `reps=2`; it reports packed-SIMD `array_sum_int_packed_bridge`
`~2.9643x C` and `dot_product_int_packed_bridge` `~2.1500x C` versus canonical `array_sum_int`
`~1.2482x C` and `dot_product_int` `~1.2109x C`. This is a real bridge-materialization improvement
relative to the prior `20260408_234329` read-split, but it still leaves the packed bridge behind the
canonical fast loop. The same conclusion holds on the route-stability rerun
`build/logs/perf-probe-list-int-dot-ceiling-stability-20260411_204859_99207.log`: packed-SIMD had
`0/5` wins for both array and dot, with median deltas `+269.38%` and `+134.27%` versus baseline.
Keep treating a safe packed view as a representation/ownership problem that must avoid or hoist the
copy, not as another per-byte-store tuning branch.

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

The same rule now also covers the adjacent shared byte-constructor surfaces that allocate a fresh
`[]u8` and deterministically overwrite it before returning:

- `bytes.from_hex`
- `bytes.pack`
- `base64.decode_bytes`
- `read_u8_buf`

Again, this is a scope/safety update rather than a new kept benchmark claim. The important point is
that the shared/runtime byte constructors no longer stand out as the one remaining `u8` family that
still paid eager zero-fill before a proven full overwrite.

The same proof now covers the fresh-output typed-buffer linear algebra kernels too. Shared
`std:linalg` constructors that allocate a fresh numeric buffer and then fully overwrite it through a
checked `*_into` kernel or an explicit pack/transpose loop now also use `*_new_uninit(...)`:

- `axpy_i32_buf`
- `axpy_f32_buf`
- `matmul_i32_buf`
- `matmul_i32_buf_wide`
- `matmul_f32_buf`
- `matmul_f64_buf`

Their internal fully-overwritten scratch and pack/transpose buffers (`bp`, `bt`, `tmp4`, and
`tmp16`) now follow the same rule too. This is intentionally a scope/safety cleanup, not a new kept
perf claim; the fact-backed point is that the earlier overwrite-proof fast path is now applied
consistently to the adjacent linalg fresh-output family instead of stopping at conversion helpers.

That same proof now covers a few remaining shared byte serialization helpers that also allocated a
fresh `[]u8` and then deterministically filled every byte before any successful return:

- `http2.settings_payload_from_list`
- `http2_client._u8_concat2`
- `http2_client._read_frame`
- `http2_client._send_headers_fragmented`
- `hpack._huff_decode_bytes` final output buffer
- `ppm.encode_rgba`

This is again a scope/safety cleanup rather than a new kept performance claim. The adjacent runtime
coverage now includes a focused module assertion for the HTTP/2 SETTINGS payload encoder/decoder, so
the new allocation path is exercised by more than compile-only fixtures.

The next shared-byte cleanup after constructor/allocation work is helper-boundary removal. A few
portable `std:bytes` and `std:ui` helpers no longer bounce through intermediate `list<int>`
materialization when the shared runtime already exposes direct byte-slice/string bridges:

- `bytes.try_to_string`
- `bytes.try_slice`
- `bytes.try_concat`
- `bytes.try_from_u8_buf`
- `bytes.try_to_string_slice`
- `ppm.write_rgba_ppm`

This is also a scope/safety update rather than a new kept benchmark claim. The important point is
that common byte helpers now compose directly through `oren_string_from_bytes_slice(...)`,
`oren_u8_buf_from_bytes_slice(...)`, unchecked direct `u8` writes, and direct `u8_buf ->
oren_write_bytes(...)` handoff instead of re-materializing temporary byte lists first.

The next adjacent compiler-side byte-path cleanup is now also done: OBC file reads and deterministic
metadata hashing in the build pipeline no longer force `oren_read_bytes(...)` list payloads first.
`lib/compiler/obc_link.oren` now parses `.obc` / `OBX` payloads through the generic
`oren_bytes_len(...)`, `oren_bytes_get_u8(...)`, and `oren_string_from_bytes_slice(...)` surface and
reads the file via `oren_read_u8_buf(...)`, while the two metadata hashing legs in
`lib/compiler/compiler/040_build_pipeline/010_main.oren` now hash `u8_buf` reads directly. That
keeps the compiler on one byte representation end-to-end for these artifact paths instead of
reboxing into legacy byte lists.

The adjacent AVM harness/test `.obc` path is now aligned too. The multiverse/map-key/compiler-in-AVM
fixtures that immediately fed `.obc` files into `oren_avm_run_obc_bytes(...)` or VirtualFS fixtures
now read them via `oren_read_u8_buf(...)` directly, and the local AVM VFS fixture builders in the
same tests now append generic bytes through `oren_bytes_len(...)` / `oren_bytes_get_u8(...)` instead
of assuming `list<int>` bodies. The intentional `read_bytes` roundtrip tests stay unchanged; only the
stale `.obc` bridge paths moved.

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

For the same generic-vs-specialized comparison focused specifically on the arm64
`OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` experiment, use:

```bash
make perf-probe-arm64-fast-dot-prefix-zero-specialization
```

This keeps the comparison on just `dot_product` vs `dot_product_int`, runs both the steady and
read-split specialization probes on the shipped default and on the enabled prefix-zero build env,
and bundles the specialization trace alongside them. Current host rerun
(`build/logs/perf-probe-arm64-fast-dot-prefix-zero-specialization-20260409_011654_49934.log`):

- default steady: generic `~1.3947x C`, specialized `~1.6008x C` (`generic_vs_specialized ~0.8713x`)
- enabled steady: generic `~1.3992x C`, specialized `~1.5518x C` (`generic_vs_specialized ~0.9017x`)
- default read-split long-per-rep: generic `~1.6788x C`, specialized `~1.7004x C` (`~0.9873x`)
- enabled read-split long-per-rep: generic `~1.6392x C`, specialized `~1.5860x C` (`~1.0335x`)

That is the current attribution fact for the prefix-zero dot work: the generic/explicit gap still
stays small, and the parsed-bound reserve fix improved both whole-operation surfaces materially.
The remaining blocker is not missing typed fill setup on these benchmarks anymore.

And to confirm that the generic benchmarks still compile through the intended `list<int>` rewrite
path instead of silently falling back to boxed-list behavior, use:

```bash
make perf-probe-list-int-specialization-trace
```

The latest trace artifact, `build/logs/perf-probe-list-int-specialization-trace-20260409_011625_49062.log`,
shows the full fill-path rewrite:

- generic `array_sum`: `rewrite_init=1`, `list_int_reserve=1`, `list_int_push_unchecked=1`
- generic `dot_product`: `rewrite_init=2`, `list_int_reserve=2`, `list_int_push_unchecked=2`
- explicit `array_sum_int`: `list_int_reserve=1`, `list_int_push_unchecked=1`
- explicit `dot_product_int`: `list_int_reserve=2`, `list_int_push_unchecked=2`

The same summary still reports one boxed `list_reserve` plus one boxed `list_push_unchecked` per
program from shared helper functions; those are not the benchmark fill loops under study.
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

Update the canonical snapshot table after a canonical native-gate rerun:

```bash
make perf-gate-native-refresh-latest
```

That target refreshes `benchmarks/RESULTS_LATEST.md` from the exact JSONs emitted by the focused
native gate run. For wider or ad-hoc benchmark batches, `python3 benchmarks/update_latest.py ...`
still works when you pass the specific result JSON paths you want reflected in the snapshot.

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
  `make perf-probe-arm64-fast-dot-single-pair-cursor-regs` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int` for explicit
  `dot_product_int`. The shipped default still keeps the cursor-reg scalar path enabled, and both
  wrappers preserve raw native medians/covariance while comparing that baseline against
  `OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0`.
- Current same-tree reruns keep the cursor-reg path enabled by default. Generic
  `dot_product` (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-20260411_170046_96599.log`)
  regressed when cursor regs were disabled on raw native time (`steady 0.130047s -> 0.133221s`,
  `gate 0.010926s -> 0.011969s`; `+2.44%` / `+9.55%`). Explicit `dot_product_int`
  (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int-20260411_170108_97730.log`)
  stayed mixed: disabled slightly improved raw native medians (`0.131784s -> 0.130060s`,
  `0.010440s -> 0.010435s`; `-1.31%` / `-0.05%`), but the gate ratio worsened
  (`~1.8254x` -> `~2.0207x`) because the paired C median also shifted. Do not flip the shipped
  default based on that tiny explicit-only raw delta.
- For the arm64 explicit `fast_list_int_get_sum_while` single-list cursor-reg recheck, use
  `make perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int`. This compares the shipped
  explicit-`array_sum_int` baseline against
  `OREN_ARM64_FAST_LIST_INT_GET_SUM_SINGLE_LIST_CURSOR_REGS=0` through the serialized
  `make perf-probe-arm64-list-int-acceptance` bundle.
- Current rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int-20260409_130055_41301.log`)
  keeps that new explicit cursor-reg path enabled by default: steady native median moved from
  disabled `0.134232s` to default `0.133314s` (`-0.69%`), gate native stayed effectively flat
  (`0.010003s` disabled vs `0.010044s` default) while the disabled leg raised
  `warning_gate_array_sum_int_high_variance`, and both legs kept the same 16-instruction traced
  loop. The follow-up whole-operation rerun
  (`build/logs/perf-probe-list-int-c-ceiling-20260409_132256_79494.log`) still left canonical
  `oren_array_sum_int / array_slot64_vector` at `~5.3848x`, so this is a worthwhile hot-loop
  cleanup, not the missing whole-operation `array_sum_int` fix.
- For the arm64 explicit `fast_list_int_get_sum_while` tick-mask sweep, use
  `make perf-probe-arm64-fast-get-sum-tick-mask-list-int`. This reuses the serialized
  `make perf-probe-arm64-list-int-acceptance` bundle and compares the shipped get-sum default
  against explicit mask overrides on the exact `array_sum_int` surface.
- Current final-tree rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-list-int-20260409_143632_74801.log`)
  keeps the shipped default at `OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK=4095` for now. The
  rerun is intentionally not over-claimed: explicit `16383` improved steady native median from
  `0.141901s` to `0.137232s` (`-3.29%`) and `65535` improved it further to `0.131635s`
  (`-7.23%`), but the gate view stayed too noisy to trust (`c_cov=0.6421` at default,
  `0.2631` at `16383`, `0.1270` at `65535`). The production-quality conclusion is therefore
  conservative: keep `4095` shipped and use this new probe as the decision surface for a later,
  stronger stability-style rerun before changing the default.
- The stronger same-tree whole-operation decision surface now exists too:
  `make perf-probe-arm64-fast-get-sum-tick-mask-decision`. It rotates default, `16383`, and
  `65535` across exact `perf-probe-list-int-c-ceiling` sweeps and treats `array_sum_int` as the
  target get-sum surface while reporting `dot_product_int` as a control.
- Current cached rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-decision-20260411_162635_82969.log`)
  keeps the shipped default at `4095`: exact `array_sum_int` preferred default by median
  (`default_array_ratio_median ~2.1833x`, `16383 ~2.2437x`, `65535 ~2.1864x`,
  `array_default_wins: 2/3`), and the dot control also preferred default
  (`default_dot_ratio_median ~1.7332x`, `16383 ~1.7811x`, `65535 ~1.7845x`).
- For the arm64 explicit `fast_list_int_push_while` single-list cursor follow-up, use
  `make perf-probe-arm64-fast-push-single-list-cursor-list-int`. This compares the shipped
  explicit-`array_sum_int` fill loop against
  `OREN_ARM64_FAST_LIST_INT_PUSH_SINGLE_LIST_CURSOR=0` through the same serialized acceptance
  bundle.
- Current rerun
  (`build/logs/perf-probe-arm64-fast-push-single-list-cursor-list-int-20260409_132214_76347.log`)
  keeps that new default-on path enabled: steady native median improved from disabled `0.136291s`
  to default `0.131530s` (`-3.62%`), gate native improved from disabled `0.010571s` to default
  `0.010084s` (`-4.83%`), and both legs kept the same 16-instruction traced loop. The follow-up
  whole-operation rerun (`build/logs/perf-probe-list-int-c-ceiling-20260409_132256_79494.log`)
  improved canonical `oren_array_sum_int / array_slot64_vector` from `~5.4463x` to `~5.3848x`.
  Keep the cursor path enabled, but treat it as a modest whole-operation improvement, not the
  missing slot64-vector parity fix.
- The next fill-side shipped change is narrower and stronger: arm64 explicit
  `fast_list_int_push_while` now also keeps pure index-only integer push expressions on the fast
  lowering through the new default-on `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR` path instead of
  paying generic `native_compile_expr(...)` each iteration.
- Use `make perf-probe-arm64-fast-push-idx-expr-decision` as the current ranking surface for that
  shipped change. It combines the `list<int>` fill-share attribution probe with same-tree exact
  `perf-probe-list-int-c-ceiling` reruns on the current tree.
- Current widened rerun
  (`build/logs/perf-probe-arm64-fast-push-idx-expr-decision-20260409_183650_90548.log`) keeps that
  new push-expression path enabled by default:
  - fill/share surface preferred default (`default_fill_vs_c_vector ~4.4912x`, disabled `~5.0143x`)
  - exact same-tree whole-operation reruns also preferred default on both programs
    (`default_array_ratio_median ~2.2989x` vs disabled `~2.3437x`, `array_default_wins: 3/5`;
    `default_dot_ratio_median ~1.8313x` vs disabled `~1.8546x`, `dot_default_wins: 4/5`)
  - `decision_surface_alignment: agree`
- Keep `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR` shipped on. This is the first current-tree fill-side
  branch after the fill-share reweighting that improved both the fill attribution surface and the
  exact whole-operation ceiling instead of only the local acceptance wrapper.
- The next explicit fill-side follow-up is available behind the opt-in gate
  `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT=1`. This branch carries a conservative
  same-block proof for fresh `list<int>` constructors into explicit `fast_list_int_push_while`:
  when a list was just created as `list.int_new(n)`, `i` is still known `0`, and the constructor
  cap exactly matches the fast-loop bound, the emitter skips reserve/count/header revalidation and
  writes through the constructor-installed buffer directly.
- Use `make perf-probe-arm64-fast-push-fresh-exact-init-decision` as the ranking surface for that
  branch. Current widened reruns disagree on the exact whole-operation winner:
  - safe-tree opt-in rerun
    (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203332_51451.log`)
    preferred enabled on both surfaces (`enabled_fill_vs_c_vector ~2.6204x` vs default `~2.8017x`,
    `enabled_array_ratio_median ~2.1902x` vs default `~2.3434x`,
    `enabled_dot_ratio_median ~1.7876x` vs default `~1.8040x`)
  - immediate promoted-default rerun
    (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203846_59158.log`)
    still preferred default on fill/share (`~2.8342x` vs disabled `~2.8957x`) but flipped the
    exact whole-operation medians back toward the disabled branch
    (`default_array_ratio_median ~2.2081x` vs disabled `~2.2036x`,
    `default_dot_ratio_median ~1.7928x` vs disabled `~1.7478x`)
- Because the exact same-tree winner inverted across adjacent widened reruns, keep
  `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT` opt-in only for now. The final safe tree still
  passed `build/logs/make_verify_native_list_int_fast_lowering_push_fresh_exact_init_optin_final_20260409.log`,
  `build/logs/make_test_push_fresh_exact_init_optin_batch_20260409.log`,
  `build/logs/make_verify_runtime_robustness_push_fresh_exact_init_optin_rerun_20260409.log`, and
  `build/logs/runtime_robustness_w5_20260409_205346.log`.
- The narrower single-list follow-up is now also isolated behind
  `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_SINGLE_LIST=1`. This branch keeps the same
  fresh-constructor proof, but only for the single-list explicit fill shape that the fill/share
  probe actually measures.
- Use `make perf-probe-arm64-fast-push-fresh-exact-single-list-decision` as the ranking surface for
  that narrower branch. The current safe-tree widened rerun
  (`build/logs/perf-probe-arm64-fast-push-fresh-exact-single-list-decision-20260409_232042_61224.log`)
  still rejects promotion:
  - fill/share preferred shipped default (`default_fill_vs_c_vector ~2.7420x`, enabled `~2.7707x`)
  - exact `array_sum_int` also preferred shipped default (`default_array_ratio_median ~1.9810x` vs
    enabled `~2.1506x`, `array_default_wins: 4/5`)
  - exact `dot_product_int` did move slightly toward enabled (`default_dot_ratio_median ~1.7857x`
    vs enabled `~1.7675x`, `dot_enabled_wins: 4/5`)
  - `decision_surface_alignment: agree` for the actual target surface because both fill/share and
    exact `array_sum_int` still prefer the shipped default
- Reweight again: do not ship `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_SINGLE_LIST` by default.
  The narrower isolation answered the question cleanly and still points away from more
  fresh-constructor shortcut tuning and toward a different fill/setup lifetime optimization class.
- For the arm64 explicit `fast_list_int_get_sum_while` unroll-by-2 follow-up, use
  `make perf-probe-arm64-fast-get-sum-unroll2-list-int` for the local acceptance A/B and
  `make perf-probe-arm64-fast-get-sum-unroll2-decision` for the actual shipped decision surface.
  After the root-cause fix in `lib/compiler/arm64_native_stmt_loops_list_emit.oren`, the shipped
  tree now keeps `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2` on by default for single-read-list
  shapes and compares that live default against `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2=0`.
- The earlier crashy candidate was not a vague runtime flake. The experimental unrolled arm64
  bodies were reusing reserved heap registers `X27` / `X28` as loop value temporaries; those temps
  now live in caller-saved `X12` / `X13`, which keeps the heap globals intact across the exact
  whole-operation path.
- After that fix, the promoted exact whole-operation rerun
  (`build/logs/perf-probe-list-int-c-ceiling-20260409_163202_21950.log`) brought
  `oren_array_sum_int / array_slot64_vector` down to `~2.3939x`; the narrower earlier promoted
  candidate rerun (`build/logs/perf-probe-list-int-c-ceiling-20260409_151055_21212.log`) had
  already shown the same shape at `~2.3353x`.
- The broad gates that previously rejected the candidate now pass on the promoted tree:
  `build/logs/make_test_get_sum_unroll2_promote_20260409.log`,
  `build/logs/make_verify_runtime_robustness_get_sum_unroll2_promote_20260409.log`, and
  `build/logs/runtime_robustness_w5_20260409_163313.log`.
- The old paired acceptance rerun on the same promoted default
  (`build/logs/perf-probe-arm64-fast-get-sum-unroll2-list-int-20260409_163132_20811.log`) stayed
  noisy and locally favored the disabled branch (`0.067315s` default vs `0.058718s` disabled
  steady native median, with default native `cov=0.1658`).
- The new combined decision probe
  (`build/logs/perf-probe-arm64-fast-get-sum-unroll2-decision-20260409_170812_66742.log`) makes
  that disagreement explicit on the same current tree:
  - acceptance steady still preferred disabled (`disabled_steady_array_sum_int_native_median_delta_pct: -4.79%`)
  - acceptance gate slightly preferred default (`disabled_gate_array_sum_int_native_median_delta_pct: +0.78%`)
  - exact whole-operation `array_sum_int` strongly preferred the shipped default in all three
    same-tree sweeps (`array_default_wins: 3/3`), with default median
    `oren_array_sum_int / array_slot64_vector ~2.3793x` vs disabled median `~5.3859x`
  - exact whole-operation `dot_product_int` stayed mixed (`default ~1.8343x`, disabled `~1.8138x`,
    disabled wins `2/3`), which is consistent with this knob being an `array_sum_int` get-sum
    decision, not a general dot-path optimization
- Treat the acceptance wrapper as a local sanity surface only. For shipped decisions on this path,
  the reusable source of truth is now the combined decision probe plus integrated green lanes, with
  the exact whole-operation `array_sum_int` C ceiling carrying the ranking weight.
- The next current-tree follow-up on the same explicit get-sum path is
  `make perf-probe-arm64-fast-get-sum-dual-accum-decision`. It compares the shipped default
  against `OREN_ARM64_FAST_LIST_INT_GET_SUM_DUAL_ACCUM=1` on both the local acceptance wrapper and
  the same-tree exact whole-operation C ceiling. The fresh widened rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-dual-accum-decision-20260409_174904_22327.log`)
  settled that experiment as another current-tree loser: acceptance locally preferred the enabled
  branch (`steady -19.53%`, `gate -52.65%`), but the exact whole-operation surface still preferred
  the shipped default in `4/5` sweeps, with default median
  `oren_array_sum_int / array_slot64_vector ~2.2506x` vs enabled median `~2.2797x`.
- Reweight accordingly: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_DUAL_ACCUM` as an explicit opt-in
  experiment only. It is not the missing repeated-read `array_sum_int` fix on the current
  post-unroll2 tree.
- The next exact-path follow-up on the same explicit get-sum branch is now
  `make perf-probe-arm64-fast-get-sum-pair-post-decision`. It isolates
  `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1` on the same current-tree decision surface instead
  of the older mixed `array_sum` + `dot_product` family probe. Current widened rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`)
  landed with the now-familiar split: the local acceptance wrapper strongly preferred the enabled
  branch (`enabled_steady_array_sum_int_native_median_delta_pct: -26.20%`,
  `enabled_gate_array_sum_int_native_median_delta_pct: -53.71%`), but the exact same-tree
  whole-operation C ceiling still preferred the shipped default in `3/5` sweeps
  (`default_array_ratio_median: ~2.3604x`, `enabled_array_ratio_median: ~2.4015x`). Exact
  `dot_product_int` also stayed slightly better on the default (`~1.8539x` vs `~1.8578x`).
- Reweight again: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST` opt-in only. The older family
  probe is still useful when judging the combined get-sum + dot pair-load experiment, but the
  shipped get-sum decision surface is now the dedicated pair-post decision probe plus integrated
  green lanes, not the acceptance wrapper alone.
- For the arm64 explicit `fast_list_int_get_sum_while` slot64 SIMD-add follow-up, use
  `make perf-probe-arm64-fast-get-sum-vector-2d-decision`. This tests the new default-off
  `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1` path, which uses `ldr q` plus `add.2d`/`addp.2d`
  within one tick-protected iteration and reduces back to the scalar sum before another possible GC
  call. The widened rerun
  (`build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`) confirms
  the intended shape (`51` traced instructions, `41` without two cold tick blocks, `q` loads in the
  snippet, `add.2d=1`, `addp.2d=2`) but rejects promotion: local acceptance preferred enabled
  (`steady -7.95%`, `gate -1.62%`), while the same-tree whole-operation C-ceiling surface preferred
  shipped default in `4/5` sweeps (`default_array_ratio_median ~2.2140x`, enabled `~2.2967x`).
- Reweight accordingly: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D` opt-in only. The residual
  get-sum gap is not solved by a per-iteration slot64 pairwise-add body; next W5 work should still
  target a stronger representation/direct-lowering path rather than another local acceptance-only
  get-sum scheduling branch.
- For the arm64 `fast_list_int_dot_while` unroll-by-2 recheck, use
  `make perf-probe-arm64-fast-dot-unroll2` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-unroll2-list-int` for explicit `dot_product_int`. The shipped
  default now keeps unroll2 off and the wrappers compare that live baseline against
  `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1`.
- Current post-flip reruns justify that shipped change directly:
  generic rerun (`build/logs/perf-probe-arm64-fast-dot-unroll2-20260409_030759_29018.log`) kept
  the then-current non-unrolled scalar loop at native `steady=0.140160s`, `gate=0.014280s`; re-enabling
  unroll2 moved those to `0.143718s` (`+2.54%`) and `0.015197s` (`+6.42%`) while growing the
  traced loop back to `69` instructions. Explicit rerun
  (`build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260409_030846_30731.log`) showed the
  same direction: `0.136499s -> 0.144068s` steady (`+5.55%`) and `0.014523s -> 0.014546s` gate
  (`+0.16%`). That is why unroll2 is no longer shipped by default.
- To check whether the old unroll2 family becomes useful only when paired with the scalar exact-`madd`
  tail, use `make perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int`. It reuses the
  explicit read-split and order-balanced gate wrappers with an expanded case set:
  `baseline`, `UNROLL2=1`, `SCALAR=1`, and `UNROLL2=1,SCALAR=1`. Current rerun
  (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172420_40937.log`)
  rejects the combined candidate too: `UNROLL2=1,SCALAR=1` regressed read-split native
  `long_per_rep` by `+0.72%`, then lost the whole-operation gate view by native median `+2.20%`
  (`1/4` wins) and normalized `native/C` median `+8.09%` (`1/4` wins). The separate `UNROLL2=1`
  and `SCALAR=1` rows also failed at least one required surface (`long_per_rep +7.42%` and
  `+3.54%`, respectively), so this combined family stays opt-in only.
  A post-hardening verification rerun
  (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172713_80854.log`)
  was noisier, with high-covariance nested samples, but it still rejected the same combined candidate.
- For the arm64 single-pair `fast_list_int_dot_while` dual-accumulator recheck, use
  `make perf-probe-arm64-fast-dot-dual-accum` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-dual-accum-list-int` for explicit `dot_product_int`.
  Both wrappers keep the shipped default-off path on one side, compare it against
  `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1`, preserve raw native medians/covariance, and surface
  any gate high-variance warning directly in the top-level summary.
- Current 2026-04-09 reruns say the old April 4 "dual-accum loses everywhere" read is stale, but
  the path still does not qualify for promotion: generic raw medians improved modestly while the
  explicit `list<int>` steady median regressed about `+4.00%` and the gate-side improvement came
  from a high-variance sample. The dual-accum path stays disabled by default.
- For the arm64 contiguous-list pair-load/post-index recheck, use
  `make perf-probe-arm64-fast-loop-pair-post`. This keeps the shipped baseline on one side and
  compares it against the default-off experimental pair-load paths enabled together via
  `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1`
  through the full `array_sum` / `dot_product` acceptance bundle. The probe is only trustworthy
  after the April 8 comma-splitting fix in the smoke/disasm/debug helpers, which now honor the
  same comma-separated `OREN_BENCH_ENV_BUILD_OREN` contract as the steady/gate runners. Current
  host rerun (`build/logs/perf-probe-arm64-fast-loop-pair-post-20260408_215548_57748.log`):
  default `steady_array_sum ~2.4342x`, `steady_dot_product ~2.7645x`, `gate_array_sum ~2.0788x`,
  `gate_dot_product ~2.5682x`, disasm `52` / `70`; enabled `~2.3932x`, `~3.1297x`, `~2.1181x`,
  `~2.6913x`, disasm `47` / `60`. Conclusion: keep the pair-load path disabled by default; the
  lower instruction counts still lose on the measured hot-loop trackers.
- For the explicit `list<int>` get-sum pair-post branch alone, use
  `make perf-probe-arm64-fast-get-sum-pair-post-list-int` for the local acceptance A/B and
  `make perf-probe-arm64-fast-get-sum-pair-post-decision` for the shipped ranking surface. Current
  decision rerun (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`)
  says the acceptance wrapper is misleading here too: enabled looked much faster locally, but the
  exact same-tree whole-operation reruns still preferred the shipped default on both
  `array_sum_int` and `dot_product_int`. So the get-sum pair-post knob also stays default-off.
- For the arm64 compile-time-zero prefix-loop family, keep both branches default-off and split the
  measurements by leg. `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1` is still a clear negative
  result on the current host: the isolated rerun
  (`build/logs/perf-probe-arm64-dot-acceptance-20260409_003014_84317.summary.log`) landed at
  `steady_array_sum ~7.1203x` and `gate_array_sum ~2.3250x`, materially worse than the shipped
  baseline. The old combined probe `make perf-probe-arm64-fast-loop-prefix-zero` is still useful
  when you want the whole family in one failure-aware artifact, but the dot leg now has its own
  dedicated serialized probe: `make perf-probe-arm64-fast-dot-prefix-zero`.
- The dot-only prefix-zero branch is correctness-clean again after the April 9 register-plan fix,
  so the right comparison is now default vs
  `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` on `OREN_ARM64_DOT_ACCEPT_PROGRAMS=dot_product`.
  The wrapper now also preserves raw native/C medians plus covariance from the underlying acceptance
  bundles, because ratio-only A/Bs were too easy to misread when the C baseline drifted across
  reruns. Current kept rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-20260409_014027_88043.log`):
  default `steady_dot_product ~2.8260x`, native `0.083484s`, cov `0.0452`, gate native `0.013869s`,
  cov `0.0163`, disasm `70`; enabled `~2.9272x`, native `0.080339s`, cov `0.0339`, gate native
  `0.014837s`, cov `0.0145`, disasm `23`. The wrapper also prints the direct native deltas:
  `steady_dot_product_native_median_delta_pct: -3.77%`, `gate_dot_product_native_median_delta_pct:
  +6.98%`. So the generic surface is still mixed on the current host: the hot steady kernel gets a
  little better, but the whole-operation gate gets worse, so keep the branch default-off.
- To judge the same experiment on the explicit `list<int>` surface instead of the generic
  auto-specialized benchmark, use `make perf-probe-arm64-fast-dot-prefix-zero-list-int`. This keeps
  the shipped baseline on one side and compares it against
  `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` through the new
  `make perf-probe-arm64-list-int-acceptance` bundle. Current kept rerun
  (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-list-int-20260409_014050_89076.log`): default
  `steady_dot_product_int ~3.0871x`, native `0.077758s`, cov `0.0475`, gate native `0.013945s`,
  cov `0.0397`, disasm `70`; enabled `~2.9543x`, native `0.087468s`, cov `0.0873`, gate native
  `0.015405s`, cov `0.0440`, disasm `23`. The raw native deltas are the decisive part:
  `steady_dot_product_int_native_median_delta_pct: +12.49%`,
  `gate_dot_product_int_native_median_delta_pct: +10.47%`. That overturns the older ratio-only
  “explicit win” reading: the salvaged dot prefix-zero subpath is not promotable on the current host
  and should stay default-off. The newer specialization wrapper above still shows the
  generic/explicit gap itself stays small, so this is not a broad source-shape story anymore.
- For the arm64 exact-path `madd` recheck, use
  `make perf-probe-arm64-fast-dot-madd-exact`. This still compares the shipped baseline against the
  full opt-in branch `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1`, but the wrapper now also preserves
  raw steady/gate native medians and covariance from the acceptance summary instead of only ratio
  lines. That matters because the full exact branch is still mixed on the current host even though
  it is correctness-clean after the exact-double tail guard. Latest focused `dot_product` rerun
  (`build/logs/perf-probe-arm64-fast-dot-madd-exact-20260409_020451_23581.log`): baseline native
  `steady=0.079999s`, `gate=0.014653s`, disasm `70`; enabled
  `steady=0.082496s`, `gate=0.014211s`, disasm `77`, so the direct native deltas are
  `steady_dot_product_native_median_delta_pct: +3.12%` and
  `gate_dot_product_native_median_delta_pct: -3.02%`. Keep the whole exact branch opt-in only.
- To judge that same full exact branch on the explicit `list<int>` surface instead of the generic
  auto-specialized benchmark, use `make perf-probe-arm64-fast-dot-madd-exact-list-int`. The current
  `dot_product_int` rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-list-int-20260409_020520_24931.log`)
  is still not a strong default-flip result by itself: enabled native
  `steady=0.078774s` vs baseline `0.078684s` (`+0.11%`), but gate improves modestly
  `0.014076s` vs `0.014510s` (`-2.99%`).
- For the arm64 exact-path `madd` subcase split, use
  `make perf-probe-arm64-fast-dot-madd-exact-subpaths` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-madd-exact-list-int-subpaths` for explicit `dot_product_int`.
  After the shipped unroll2 default moved off, these subpath probes now hang off the non-unrolled
  21-instruction traced baseline (14 instructions after subtracting the skipped cold GC-call block)
  rather than the older 69-insn unrolled loop.
- Current generic rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-subpaths-20260409_031413_41277.log`)
  says the old "scalar-only is the one promotable piece" story is no longer current on this new
  baseline: forcing `SCALAR=0` improved both raw native medians (`0.153122s -> 0.150737s`,
  `0.015751s -> 0.014817s`). The `quad` / `double` rows in that artifact also improve raw medians,
  but with unroll2 now default-off they collapse onto the same 21-instruction non-unrolled family
  and are not a meaningful shipping signal by themselves.
- Current explicit rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-list-int-subpaths-20260409_031505_43502.log`)
  stays mixed in the same way: `SCALAR=0` regresses steady (`0.140619s -> 0.144013s`, `+2.41%`)
  but improves gate (`0.015298s -> 0.014376s`, `-6.03%`). The `quad` row again improves both raw
  medians, but it is still riding the non-unrolled baseline and should not be read as a direct
  promotion candidate until the opt-in unroll2 family is reconsidered as a whole.
- The current shipped arm64 scalar-core decision is better judged by the post-flip matrix wrappers:
  `make perf-probe-arm64-fast-dot-scalar-core-matrix` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-scalar-core-matrix-list-int` for explicit `dot_product_int`.
  The latest current-tree artifacts
  (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260411_170733_44863.log`,
  `build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-list-int-20260411_170847_78864.log`)
  keep the candidate set focused but not yet promotable:
  - generic `dot_product`: the one-shot acceptance medians prefer `SCALAR=1` and
    `CURSOR=0,SCALAR=1` on raw native time, but the run is too noisy to use alone
    (`gate` baseline covariances around `0.41`)
  - explicit `dot_product_int`: `SCALAR=1` improves steady native median
    (`0.138499s -> 0.131536s`, `-5.03%`) but is basically flat/slightly worse on the gate
    (`0.010847s -> 0.010917s`, `+0.65%`); `CURSOR=0,SCALAR=1` improves the same one-shot gate
    (`0.010847s -> 0.009767s`, `-9.96%`), but needs the order-balanced tie-breaker below
  Reweight: keep the shipped scalar exact-`madd` path opt-in for now, keep cursor regs on by
  default, and use the matrix wrappers for future core-path A/Bs instead of the older subpath-only
  story.
- For the same shipped baseline, the new read-split decomposition wrappers make the setup vs
  repeated-work tradeoff explicit:
  `make perf-probe-arm64-fast-dot-scalar-core-read-split` for generic `dot_product` and
  `make perf-probe-arm64-fast-dot-scalar-core-read-split-list-int` for explicit `dot_product_int`.
  Current artifacts
  (`build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-20260411_170937_83286.log`,
  `build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-20260411_170942_83791.log`)
  say:
  - generic `dot_product`: the latest read-split does not confirm the one-shot matrix win; the
    best combined cursor+scalar case is roughly flat on setup (`+0.09%`) and still regresses
    repeated `long_per_rep` (`+0.88%`)
  - explicit `dot_product_int`: `SCALAR=1` now improves every reported native component on this
    rerun (`short -6.13%`, `setup -6.11%`, `delta -6.33%`, `long_per_rep -6.26%`); the probe also
    emits the usual delta-vs-long drift warning, so prefer `long_per_rep` for tracker updates
  Treat those read-split logs as decomposition tools, not as shipped-default verdicts by
  themselves.
- When the explicit whole-operation sign is small, use the order-balanced tie-breaker:
  `make perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int`. It runs four whole-operation
  gate sweeps in rotating case order so each scalar-core variant occupies each run position once.
  Latest artifact
  (`build/logs/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-20260411_170947_84214.log`)
  keeps the explicit shipped verdict mixed:
  - `SCALAR=1` is only a `2/4` native-median win with median `+1.65%`, while normalized
    `native/C` is a `2/4` win with median `-1.13%`
  - `CURSOR=0,SCALAR=1` is also only a `2/4` native-median win with median `+0.48%`, and normalized
    `native/C` is `2/4` with median `+0.15%`
  Reweight: keep scalar exact-`madd` opt-in and keep cursor regs default-on until a candidate wins
  both the decomposition and the whole-operation stability surface together.
- Follow-up combined-family decision (2026-04-11): the scalar read-split and gate-stability wrappers
  now accept explicit case sets, and `make perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int`
  uses that to rank `UNROLL2=1`, `SCALAR=1`, and `UNROLL2=1,SCALAR=1` together on the explicit
  `dot_product_int` surface. The first artifact
  (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172420_40937.log`)
  says the combined candidate is not promotable: read-split native `long_per_rep +0.72%`,
  gate native median `+2.20%` with `1/4` wins, and gate `native/C +8.09%` with `1/4` wins. This is
  the current answer to the older "quad row under unroll2 might be the real scalar-core candidate"
  question: not on this shipped tree. An adjacent post-hardening verification artifact
  (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172713_80854.log`)
  was noisier but reached the same rejection, so the next dot-core work should move away from this
  combined toggle family.
- Scalar-post decision follow-up (2026-04-11): `make perf-probe-arm64-fast-dot-scalar-post-decision-list-int`
  ranks `baseline`, `SCALAR_POST=1`, `SCALAR=1`, and `SCALAR_POST=1,SCALAR=1` on the same explicit
  `dot_product_int` read-split and order-balanced gate surface. The structural disasm checks show
  the expected shape:
  - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1`
    (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-20260411_174133_69032.log`)
    lowers the hot body to post-index loads and moves the traced range to `19` instructions, or `12`
    without the skipped cold GC-call block
  - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1`
    (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-madd-20260411_174149_69542.log`)
    emits post-index loads plus `madd`, moving the traced range to `18`, or `11` without the cold
    block
  The ranking artifact
  (`build/logs/perf-probe-arm64-fast-dot-scalar-post-decision-list-int-20260411_173911_64748.log`)
  still rejects the combined candidate: read-split native `long_per_rep +0.99%`, gate native median
  `+1.17%` with `2/4` wins, and gate `native/C +2.22%` with `2/4` wins. The standalone
  `SCALAR_POST=1` row also fails read-split (`long_per_rep +4.57%`) and the gate median (`+1.01%`,
  `2/4` wins). Reweight: keep scalar-post and scalar exact-`madd` opt-in; this closes the cheap
  "match host scalar post-index+madd" branch and leaves the bigger vector/slot64 representation gap
  as the next high-leverage dot-parity surface.
- Pair-post + exact-body `madd` decision follow-up (2026-04-11):
  `make perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int` ranks `baseline`, `UNROLL2=1`,
  `UNROLL2=1,PAIR_POST=1`, `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1`, and the combined
  `UNROLL2=1,PAIR_POST=1,QUAD/DOUBLE/SCALAR_MADD=1` candidate. The first focused explicit decision
  artifact (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_175200_21609.log`)
  cleared that narrow surface (`long_per_rep -0.22%`, gate native median `-1.03%` with `3/4` wins,
  and gate `native/C -5.64%` with `4/4` wins), but the immediate same-target rerun after generic
  wrapper parameterization
  (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_180637_46019.log`)
  rejected it (`long_per_rep +6.27%`, gate native median `+0.49%` with `2/4` wins, and gate
  `native/C -2.93%` with `3/4` wins). Treat the explicit surface as unstable, not promotable.
  Structural disasm
  (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-unroll2-pair-post-madd-20260411_175249_24107.log`)
  confirms the intended 4-wide paired-scalar body: post-index `ldp` pairs plus `madd`, with a
  63-instruction traced range, 49 after subtracting two skipped cold GC-call blocks. Broader acceptance
  prevents a default flip for now: explicit `dot_product_int` improved raw native medians
  (`steady -0.74%`, `gate -6.12%`;
  `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260411_175304_24487.log`), but generic
  `dot_product` regressed steady native time while slightly improving gate (`+1.69%` / `-0.63%`;
  `build/logs/perf-probe-arm64-fast-dot-unroll2-20260411_175335_25935.log`). The matching generic
  decision wrapper is now `make perf-probe-arm64-fast-dot-pair-post-madd-decision`; current artifact
  (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-20260411_180500_42245.log`)
  rejects the same combined candidate despite a read-split repeated-work win
  (`long_per_rep -2.46%`), because order-balanced gate native median regressed `+1.72%` with only
  `1/4` wins and normalized `native/C` regressed `+5.16%` with only `1/4` wins. The simpler
  `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1` row wins the generic gate (`native -2.42%`, `4/4`; native/C
  `-1.70%`, `3/4`) but fails read-split repeated work (`long_per_rep +2.55%`). Keep both branches
  opt-in until one wins decomposition and order-balanced generic/explicit whole-operation views.
- Dual-accum `madd` decision follow-up (2026-04-11): `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1`
  now turns the existing opt-in dual-accumulator body from `mul`+`add` pairs into independent
  `madd` updates, but only when `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1` is already set. The
  decision wrappers `make perf-probe-arm64-fast-dot-dual-madd-decision` and
  `make perf-probe-arm64-fast-dot-dual-madd-decision-list-int` rank the unroll2, dual-accum,
  dual-accum+madd, pair-post+dual-accum, and pair-post+dual-accum+madd rows against the shipped
  baseline. Current generic artifact
  (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-20260411_183505_89024.log`) rejects the
  combined candidate: read-split repeated work wins only slightly (`long_per_rep -0.32%`), but the
  order-balanced gate is not stable enough (`native -1.20%` with only `2/4` wins, normalized
  `native/C +0.63%` with only `1/4` wins). The explicit list<int> artifact
  (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-list-int-20260411_183536_91542.log`) is
  also not promotable: read-split `long_per_rep -8.18%`, but gate native median `+1.18%` with `2/4`
  wins and normalized `native/C +5.43%` with `1/4` wins. Structural disasm
  (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-dual-madd-20260411_183626_94501.log`)
  confirms the intended paired post-index `ldp` plus dual-accumulator `madd` shape, with a
  53-instruction traced range, 39 after subtracting two skipped cold GC-call blocks, and `madd=7`.
  Keep this branch opt-in; the representation/vector gap is still the higher-leverage target.
- Low-32 slot-load decision follow-up (2026-04-11): `OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1`
  is a new exact single-pair cursor-reg experiment that keeps the existing 8-byte `list<int>` slot
  stride but emits sign-extending `ldrsw` loads from the low 32 bits of each slot. It is intentionally
  default-off because the general `list<int>` ABI stores 64-bit integers; it is only a candidate
  surface for range-proved i32 workloads such as the current dot benchmarks. Structural disasm
  (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-low32-dual-madd-20260411_185115_16862.log`)
  confirms the intended opt-in shape for `UNROLL2=1,LOW32=1,DUAL_ACCUM=1,DUAL_MADD=1`: `ldrsw=14`,
  `madd=7`, a 63-instruction traced range, and 49 instructions after subtracting two skipped cold
  GC-call blocks. The decision wrappers are `make perf-probe-arm64-fast-dot-low32-loads-decision`
  and `make perf-probe-arm64-fast-dot-low32-loads-decision-list-int`. Current generic artifact
  (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-20260411_185129_17298.log`) rejects the
  combined candidate: read-split repeated work regresses (`long_per_rep +1.25%`) and gate native
  median is effectively flat/regressed (`+0.12%`, `2/4` wins), even though normalized gate `native/C`
  improves (`-1.99%`, `3/4` wins). The standalone `LOW32=1` row wins the generic gate
  (`native -2.44%`, `3/4`; `native/C -4.18%`, `3/4`) but still loses read-split repeated work
  (`long_per_rep +1.25%`). The explicit artifact
  (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-list-int-20260411_185153_19370.log`)
  has the opposite split for the combined candidate: read-split wins (`long_per_rep -0.81%`), but
  gate native regresses (`+2.72%`, `1/4`) and normalized `native/C` regresses (`+2.83%`, `2/4`).
  Keep low32 loads opt-in; this rules out the cheap "use i32 loads from 64-bit slots" shortcut as a
  shipped answer to the vector/slot64 representation gap.
- Prefix pair-loop decision follow-up (2026-04-11): `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1`
  is a new default-off exact prefix-zero dot branch that emits a counted 2-wide pair loop with the
  remainder branch outside the hot pair body. The reusable probes are
  `make perf-probe-arm64-fast-dot-prefix-pair-loop-decision` for the simple generic+explicit
  prefix-zero acceptance surface and `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision`
  / `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int` for the broader
  read-split + order-balanced gate surface. Structural disasm
  (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-prefix-pair-loop-20260411_190748_44241.log`)
  confirms the intended pair-loop shape: `ldp=8`, `madd=3`, a 44-instruction traced range, and
  26 instructions after subtracting two skipped cold GC-call blocks. The simple wrapper artifact
  (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-decision-20260411_191033_47867.log`)
  looked superficially positive (`dot_product` steady/gate native `-0.75%` / `-1.92%`;
  `dot_product_int` `-0.27%` / `-5.88%`), but the stronger stability surface rejected the branch.
  Correctness coverage for the new scalar remainder path is `make verify-native-arm64-dot-prefix-pair-loop-tail`,
  which builds generic and explicit dot benchmarks under the pair-loop env and checks `n=0,1,2,3,10,11,20,21`.
  Generic stability artifact
  (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-20260411_191326_52903.log`)
  had read-split `long_per_rep +3.34%` and only `2/4` gate wins even though medians improved. Explicit
  artifact
  (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int-20260411_191335_53758.log`)
  had read-split `long_per_rep +12.87%`, gate native `-0.73%` with `3/4` wins, and normalized
  `native/C -0.94%` with only `2/4` wins. Keep this counted pair-loop branch opt-in.
- The shipped scalar exact-`madd` default state now also has a deterministic structural guard:
  `make verify-native-arm64-dot-madd-scalar-default`. The same check is wired into
  `make verify-native-list-int-fast-lowering`, so the existing fast-lowering gate now also proves the
  live arm64 shipped baseline now emits the non-`madd` scalar tail on both generic `dot_product`
  and explicit `dot_product_int`, while `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` reenables
  the `madd` variant. Latest verify log
  (`build/logs/verify_arm64_dot_madd_scalar_default_20260411_171634_95703.log`): generic and
  explicit shipped defaults both stay at `instruction_count=21`,
  `range_without_cold_gc_tick_instruction_count=14`, and `madd_count=0`; forcing `SCALAR=1` moves
  both to `20`, `13`, and `1`.
- The arm64 dot acceptance summaries now emit explicit
  `warning_gate_{dot_product,dot_product_int}_high_variance` keys when the whole-operation gate COV
  crosses the `0.10` tripwire, and the exact-`madd` wrapper summaries preserve those warning keys in
  their own top-level output. That keeps future noisy gate reruns visible instead of requiring manual
  COV inspection of the nested acceptance summary.
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
- The x64 compile-only verifier now keeps its default matrix bounded after the 2026-04-11
  runtime-object metadata fix. X64 rtobj cache entries use backend sig `x64_v0_23` with compact
  fixup metadata, compact function-offset metadata, and a lazy cstr0 offset sidecar, so stage2
  cache hits no longer eagerly walk the large runtime fixup/function/cstr0 maps before compiling
  user code. The default `make verify-native-x64-compile` path now seeds x64 rtobjs through
  `scripts/build_rtobj_seed.sh --compiler ./oren_stage2 --build-compiler ./oren`, skips full
  quick-integration and NET/TLS/HTTP2 compile-only fixtures unless explicitly requested, and keeps
  the broad no-cache stage2 FFI/shared-library matrix behind `OREN_NATIVE_X64_INCLUDE_STAGE2_FULL=1`.
  The measured full fixture signals stay recorded separately: stage2 x64 full quick-integration
  exceeded the 300s measurement window (`build/logs/x64_stage2_qi_linux_lazy_fn_offsets_measure_20260411_225556.log`
  is the timeout placeholder), and stage2 x64 NET/TLS/HTTP2 exceeded the 360s measurement window
  (`build/logs/x64_stage2_net_tls_http2_linux_timeout_measure_20260411_231009.log` is the timeout
  placeholder). The bounded
  default Make verifier passed in `build/logs/verify_native_x64_compile_lazy_fn_offsets_make_default_20260411_233255.log`
  (376s on this host).
- The remaining direct-build perf probes now share the same parser too. Their
  `OREN_BENCH_ENV_BUILD_OREN` handling is centralized in `scripts/perf_build_env_lib.sh`, so
  comma-separated multi-var build envs no longer depend on per-script `join_build_env` /
  `eval` wrappers.
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
