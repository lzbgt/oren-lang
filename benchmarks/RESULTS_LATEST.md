# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-04-04
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| alloc_churn | 0.003716 | n/a | 0.020157 (5.42×) | n/a |
| alloc_drop | 0.003441 | n/a | 0.006068 (1.76×) | n/a |
| array_sum_int | 0.004591 | 0.009424 (2.05×) | 0.009492 (2.07×) | 0.127424 (27.76×) |
| dot_product | 0.005108 | n/a | 0.014420 (2.82×) | n/a |
| dot_product_int | 0.005619 | 0.016419 (2.92×) | 0.014543 (2.59×) | 0.157375 (28.01×) |
| loop_sum | 0.069604 | n/a | 0.075902 (1.09×) | n/a |
| multi_list_push_int | 0.009662 | 0.046519 (4.81×) | 0.021643 (2.24×) | 0.588497 (60.91×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` rerun (2026-04-04) now puts `array_sum_int` at 2.07× C, `dot_product_int` at 2.59× C, and `multi_list_push_int` at 2.24× C natively. The one-shot view remains useful for quick smoke checks, but steady-state tracker updates should still prefer the dedicated steady runner.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest focused rerun the native variants stayed reasonably low-variance (`array_sum_int` cov ~2.98%, `dot_product_int` cov ~1.24%, `multi_list_push_int` cov ~2.98%).
- Refresh (2026-04-04): the exact arm64 single-list `list<int>` get-sum shape still benefits from the reduced dependency chain, and the current steady runner (`make perf-gate-list-int-steady`, `reps=100`) now measures `array_sum_int` at ~2.43× native/C and `dot_product_int` at ~2.78× native/C. That is better than the older ~3.09× steady dot reading, but `dot_product_int` remains the clear steady-state blocker.
- New guardrail: `make perf-smoke-list-int` now builds the native `array_sum_int` / `dot_product_int` binaries once and checks both tiny scalar-tail outputs (`205` and `6590`) and >16-element hot-path outputs (`710` and `54380`) before heavier timing sweeps. This grew out of two wrong-code probes on 2026-03-20: the earlier exact-dot dual-accumulator experiment failed even on the tiny dot smoke (`4621`), while a later direct NEON dot-chunk experiment stayed correct at `10 3` but failed the wider hot-path case because `list<int>` slots are 64-bit values, not packed i32 lanes.
- The read split (`make perf-gate-list-int-read-split`) is now an auxiliary debugging view, not the canonical steady-state baseline. It reports both delta-based and long-run-per-rep estimates and warns when they drift materially; for example, the latest `array_sum_int` split drifted by about 30%, so tracker updates should prefer the steady runner or the split long-per-rep estimate over the naive delta subtraction.
- New packed-bridge boundary (2026-03-20): the safe `list<int> -> []i32` bridge now lives in stdlib, but the default native benchmark profile remains `core`, not `full`. Dedicated hidden packed-bridge benchmarks and probes exist for that ceiling, while the canonical `array_sum_int` / `dot_product_int` rows above remain on the default core-runtime path.
- Packed-bridge preflight note: the hidden packed-bridge smoke now defaults to Oren C rather than full-runtime native because the native full-runtime build cost is high enough that it distorts the feedback loop. The actual packed-bridge perf ceiling still lives in the explicit native probe path.
- Latest packed-bridge probe baseline leg still matters mainly as tooling context, not as the canonical tracker source. The current dedicated steady runner on 2026-04-04 measures the canonical baseline at `array_sum_int` ~2.43× C and `dot_product_int` ~2.78× C before any hidden packed-bridge warm build begins, so the remaining packed-bridge iteration cost is still concentrated in that first full-runtime native build rather than in repeated rebuilds across probe cases.
