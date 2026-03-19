# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| alloc_churn | 0.003101 | n/a | 0.019992 (6.45×) | n/a |
| alloc_drop | 0.003491 | n/a | 0.005689 (1.63×) | n/a |
| array_sum | 0.004047 | 0.007922 (1.96×) | 0.008590 (2.12×) | 0.283780 (70.13×) |
| array_sum_int | 0.004555 | 0.010800 (2.37×) | 0.010270 (2.25×) | 0.288562 (63.36×) |
| dot_product | 0.005626 | n/a | 0.014134 (2.51×) | n/a |
| dot_product_int | 0.006493 | 0.016120 (2.48×) | 0.015004 (2.31×) | 0.425633 (65.55×) |
| loop_sum | 0.069202 | n/a | 0.074757 (1.08×) | n/a |
| multi_list_push_int | 0.009374 | 0.039553 (4.22×) | 0.019655 (2.10×) | 0.599834 (63.99×) |
| multi_list_sum | 0.008222 | 0.037745 (4.59×) | 0.019307 (2.35×) | 0.575606 (70.01×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Fresh focused `list<int>` sweep (2026-03-20) puts `array_sum_int` at 2.25× C, `dot_product_int` at 2.31× C, and `multi_list_push_int` at 2.10× C natively; this keeps the open gap centered on the shared read-heavy list<int> path, not just boxed-dot lowering.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native `dot_product_int` remains above target but is now in the same band as `dot_product`.
