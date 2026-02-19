# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.065908 | 1.036931 (15.73×) | 0.416340 (6.32×) | 5.663661 (85.93×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_055656.md` |
| array_sum | 0.003835 | 0.073876 (19.26×) | 0.019664 (5.13×) | 0.623274 (162.52×) | `benchmarks/results/array_sum_darwin_arm64_20260219_080150.md` |
| array_sum_int | 0.003855 | 0.011250 (2.92×) | 0.020406 (5.29×) | 0.622709 (161.53×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_064250.md` |
| multi_list_sum | 0.008383 | 0.025794 (3.08×) | 0.030489 (3.64×) | 1.228532 (146.55×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260219_083044.md` |
| dot_product | 0.004739 | 0.017374 (3.67×) | 0.024605 (5.19×) | 0.574263 (121.18×) | `benchmarks/results/dot_product_darwin_arm64_20260219_092143.md` |
| dot_product_int | 0.004823 | 0.017694 (3.67×) | 0.025182 (5.22×) | 0.892456 (185.04×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_064258.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- array_sum (boxed list) now lands near ~5.1× C on native after fast-path fixes; biggest gaps remain alloc_churn/alloc_drop and boxed dot_product.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~3.1× C while native is ~3.6× C.
- dot_product (boxed) now ~3.7× C on Oren C and ~5.2× C on native; OBC is ~121× after LIST_DOT fast path and remains the largest gap.
