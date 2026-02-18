# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.068195 | 1.190155 (17.45×) | 0.429771 (6.30×) | 5.720071 (83.88×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_010934.md` |
| array_sum | 0.006021 | 0.116454 (19.34×) | 0.145107 (24.10×) | 0.626310 (104.02×) | `benchmarks/results/array_sum_darwin_arm64_20260219_050804.md` |
| array_sum_int | 0.003825 | 0.082009 (21.44×) | 0.019824 (5.18×) | 0.622686 (162.79×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_054300.md` |
| dot_product | 0.006472 | 0.209131 (32.31×) | 0.221092 (34.16×) | 0.896550 (138.53×) | `benchmarks/results/dot_product_darwin_arm64_20260219_050816.md` |
| dot_product_int | 0.004745 | 0.126416 (26.64×) | 0.024336 (5.13×) | 0.892373 (188.07×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_054926.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- array_sum (boxed list) remains the biggest gap; list<int> fast paths help `dot_product_int`.
