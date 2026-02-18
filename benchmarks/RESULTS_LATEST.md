# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.065908 | 1.036931 (15.73×) | 0.416340 (6.32×) | 5.663661 (85.93×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_055656.md` |
| array_sum | 0.006021 | 0.116454 (19.34×) | 0.145107 (24.10×) | 0.626310 (104.02×) | `benchmarks/results/array_sum_darwin_arm64_20260219_050804.md` |
| array_sum_int | 0.004008 | 0.057246 (14.28×) | 0.020166 (5.03×) | 0.622126 (155.22×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_060418.md` |
| dot_product | 0.006472 | 0.209131 (32.31×) | 0.221092 (34.16×) | 0.896550 (138.53×) | `benchmarks/results/dot_product_darwin_arm64_20260219_050816.md` |
| dot_product_int | 0.004800 | 0.113551 (23.66×) | 0.024767 (5.16×) | 0.888789 (185.16×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_060427.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- array_sum (boxed list) remains the biggest gap; list<int> fast paths help `dot_product_int`.
