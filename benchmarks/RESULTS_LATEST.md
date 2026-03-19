# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| array_sum_int | 0.004377 | 0.008585 (1.96×) | 0.008865 (2.03×) | 0.283616 (64.80×) |
| dot_product_int | 0.005361 | 0.013608 (2.54×) | 0.013571 (2.53×) | 0.416331 (77.65×) |
| multi_list_push_int | 0.008932 | 0.038378 (4.30×) | 0.019790 (2.22×) | 0.583399 (65.32×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` clean rerun (2026-03-20) puts `array_sum_int` at 2.03× C, `dot_product_int` at 2.53× C, and `multi_list_push_int` at 2.22× C natively; this still keeps the open gap centered on the shared read-heavy list<int> path, not just boxed-dot lowering.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest clean rerun the native variants stayed low-variance (`array_sum_int` cov ~1.44%, `dot_product_int` cov ~1.02%, `multi_list_push_int` cov ~1.96%).
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native `dot_product_int` remains above target but is now in the same band as `dot_product`.
