# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| alloc_churn | 0.002815 | n/a | 0.019792 (7.03×) | n/a |
| alloc_drop | 0.005001 | n/a | 0.009269 (1.85×) | n/a |
| array_sum | 0.004047 | 0.007922 (1.96×) | 0.008590 (2.12×) | 0.283780 (70.13×) |
| array_sum_int | 0.004146 | 0.007526 (1.82×) | 0.008943 (2.16×) | 0.124069 (29.92×) |
| dot_product | 0.005253 | n/a | 0.014905 (2.84×) | n/a |
| dot_product_int | 0.005356 | 0.012845 (2.40×) | 0.013766 (2.57×) | 0.156750 (29.26×) |
| loop_sum | 0.068905 | n/a | 0.074446 (1.08×) | n/a |
| multi_list_push_int | 0.008095 | 0.037220 (4.60×) | 0.019023 (2.35×) | 0.603634 (74.57×) |
| multi_list_sum | 0.008222 | 0.037745 (4.59×) | 0.019307 (2.35×) | 0.575606 (70.01×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` clean rerun (2026-03-20) now puts `array_sum_int` at 2.16× C, `dot_product_int` at 2.57× C, and `multi_list_push_int` at 2.35× C natively. The one-shot view remains useful for quick smoke checks, but steady-state tracker updates should still prefer the dedicated steady runner.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest clean rerun the native variants stayed reasonably low-variance (`array_sum_int` cov ~1.94%, `dot_product_int` cov ~1.71%, `multi_list_push_int` cov ~1.00%).
- New: the exact arm64 single-list `list<int>` get-sum shape now pairwise-reduces the 4-wide and 2-wide hot bodies instead of feeding every loaded lane straight into one running sum dependency chain. On the steady runner (`make perf-gate-list-int-steady`, `reps=100`) that moved `array_sum_int` from the earlier ~2.87× steady baseline to ~2.43× native/C. On the same rerun, the unchanged exact-pair dot path measured ~3.09× native/C, so `dot_product_int` remains the clear steady-state blocker.
- New guardrail: `make perf-smoke-list-int` now builds the native `array_sum_int` / `dot_product_int` binaries once and checks both tiny scalar-tail outputs (`205` and `6590`) and >16-element hot-path outputs (`710` and `54380`) before heavier timing sweeps. This grew out of two wrong-code probes on 2026-03-20: the earlier exact-dot dual-accumulator experiment failed even on the tiny dot smoke (`4621`), while a later direct NEON dot-chunk experiment stayed correct at `10 3` but failed the wider hot-path case because `list<int>` slots are 64-bit values, not packed i32 lanes.
- The read split (`make perf-gate-list-int-read-split`) is now an auxiliary debugging view, not the canonical steady-state baseline. It reports both delta-based and long-run-per-rep estimates and warns when they drift materially; for example, the latest `array_sum_int` split drifted by about 30%, so tracker updates should prefer the steady runner or the split long-per-rep estimate over the naive delta subtraction.
- New packed-bridge boundary (2026-03-20): the safe `list<int> -> []i32` bridge now lives in stdlib, but the default native benchmark profile remains `core`, not `full`. Dedicated hidden packed-bridge benchmarks and probes exist for that ceiling, while the canonical `array_sum_int` / `dot_product_int` rows above remain on the default core-runtime path.
