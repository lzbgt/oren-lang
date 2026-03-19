# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| array_sum_int | 0.006016 | 0.009030 (1.50×) | 0.008819 (1.47×) | 0.122570 (20.37×) |
| dot_product_int | 0.004948 | 0.013852 (2.80×) | 0.014050 (2.84×) | 0.153258 (30.97×) |
| multi_list_push_int | 0.008864 | 0.038645 (4.36×) | 0.019289 (2.18×) | 0.569368 (64.23×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` clean rerun (2026-03-20) puts `array_sum_int` at 1.47× C, `dot_product_int` at 2.84× C, and `multi_list_push_int` at 2.18× C natively; this narrows the open gap further to `dot_product_int`, not the whole list<int> family.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest clean rerun the native variants stayed acceptably low-variance (`array_sum_int` cov ~1.43%, `dot_product_int` cov ~2.65%, `multi_list_push_int` cov ~0.61%).
- A new focused read split (`make perf-gate-list-int-read-split`) shows the steady read-loop cost is the real blocker: `array_sum_int` native/C steady ratio is ~3.16×, while `dot_product_int` native/C steady ratio is ~4.48×.
