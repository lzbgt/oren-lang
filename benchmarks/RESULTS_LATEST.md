# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| array_sum_int | 0.004614 | 0.008877 (1.92×) | 0.009025 (1.96×) | 0.125054 (27.10×) |
| dot_product_int | 0.005307 | 0.014079 (2.65×) | 0.014108 (2.66×) | 0.160216 (30.19×) |
| multi_list_push_int | 0.009561 | 0.040887 (4.28×) | 0.020455 (2.14×) | 0.584400 (61.12×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` clean rerun (2026-03-20) puts `array_sum_int` at 1.96× C, `dot_product_int` at 2.66× C, and `multi_list_push_int` at 2.14× C natively; `dot_product_int` remains the clear blocker, but the gap is smaller than the earlier 2.84× snapshot.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest clean rerun the native variants stayed low-variance (`array_sum_int` cov ~0.93%, `dot_product_int` cov ~0.98%, `multi_list_push_int` cov ~1.46%).
- A new focused read split (`make perf-gate-list-int-read-split`) now shows the steady read-loop cost much more directly: after the arm64 single-pair cursor specialization, `dot_product_int` native/C steady ratio is ~2.97×. The remaining blocker is still the repeated read/mul/accumulate loop itself, not one-time fill/setup cost.
