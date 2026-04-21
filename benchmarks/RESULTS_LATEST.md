# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-04-22  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| alloc_churn | 0.002945 | n/a | 0.016951 (5.76×) | n/a |
| alloc_drop | 0.002961 | n/a | 0.005433 (1.83×) | n/a |
| dot_product | 0.005423 | n/a | 0.015320 (2.83×) | n/a |
| loop_sum | 0.066952 | n/a | 0.073464 (1.10×) | n/a |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead. The latest focused native gate refresh on 2026-04-22 keeps both within the current W5 thresholds: alloc_churn 5.76x C and alloc_drop 1.83x C (`build/logs/perf-gate-native-20260422_003657_93539.summary.log`).
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is still close to C on this microbench (latest focused native gate: 1.10x C on 2026-04-22). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Refresh (2026-04-22): the generic `dot_product` blocker is still live on the shipped arm64 surface. The latest focused native gate measures 2.83x C, the read-split long-per-rep view is 3.47x C, and the fresh scalar-ceiling probe still has Oren/scalar host C at 1.8452x (`build/logs/perf-gate-native-20260422_003657_93539.summary.log`, `build/logs/perf-gate-native-read-split-20260422_002728_90701.log`, `build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log`). The matching scalar-core acceptance matrix keeps baseline over the older cursor/scalar toggles, so the next arm64 dot-parity move should be a new vector/slot64-quality path rather than another scalar-toggle promotion (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`).
- Latest focused `list<int>` rerun (2026-04-04) now puts `array_sum_int` at 2.07× C, `dot_product_int` at 2.59× C, and `multi_list_push_int` at 2.24× C natively. The one-shot view remains useful for quick smoke checks, but steady-state tracker updates should still prefer the dedicated steady runner.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest focused rerun the native variants stayed reasonably low-variance (`array_sum_int` cov ~2.98%, `dot_product_int` cov ~1.24%, `multi_list_push_int` cov ~2.98%).
- Refresh (2026-04-04): the exact arm64 single-list `list<int>` get-sum shape still benefits from the reduced dependency chain, and the current steady runner (`make perf-gate-list-int-steady`, `reps=100`) now measures `array_sum_int` at ~2.43× native/C and `dot_product_int` at ~2.78× native/C. That is better than the older ~3.09× steady dot reading, but `dot_product_int` remains the clear steady-state blocker.
- New guardrail: `make perf-smoke-list-int` now builds the native `array_sum_int` / `dot_product_int` binaries once and checks both tiny scalar-tail outputs (`205` and `6590`) and >16-element hot-path outputs (`710` and `54380`) before heavier timing sweeps. This grew out of two wrong-code probes on 2026-03-20: the earlier exact-dot dual-accumulator experiment failed even on the tiny dot smoke (`4621`), while a later direct NEON dot-chunk experiment stayed correct at `10 3` but failed the wider hot-path case because `list<int>` slots are 64-bit values, not packed i32 lanes.
- The read split (`make perf-gate-list-int-read-split`) is now an auxiliary debugging view, not the canonical steady-state baseline. It reports both delta-based and long-run-per-rep estimates and warns when they drift materially; for example, the latest `array_sum_int` split drifted by about 30%, so tracker updates should prefer the steady runner or the split long-per-rep estimate over the naive delta subtraction.
- New packed-bridge boundary (2026-03-20): the safe `list<int> -> []i32` bridge now lives in stdlib, but the default native benchmark profile remains `core`, not `full`. Dedicated hidden packed-bridge benchmarks and probes exist for that ceiling, while the canonical `array_sum_int` / `dot_product_int` rows above remain on the default core-runtime path.
- Packed-bridge preflight note: the hidden packed-bridge smoke now defaults to Oren C rather than full-runtime native because the native full-runtime build cost is high enough that it distorts the feedback loop. The actual packed-bridge perf ceiling still lives in the explicit native probe path.
- Latest packed-bridge probe baseline leg still matters mainly as tooling context, not as the canonical tracker source. The current dedicated steady runner on 2026-04-04 measures the canonical baseline at `array_sum_int` ~2.43× C and `dot_product_int` ~2.78× C before any hidden packed-bridge warm build begins, so the remaining packed-bridge iteration cost is still concentrated in that first full-runtime native build rather than in repeated rebuilds across probe cases.
