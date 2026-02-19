# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.066337 | 1.048363 (15.80×) | 0.422936 (6.38×) | 5.854739 (88.26×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_103439.md` |
| array_sum | 0.003835 | 0.073876 (19.27×) | 0.019664 (5.13×) | 0.623274 (162.54×) | `benchmarks/results/array_sum_darwin_arm64_20260219_080150.md` |
| array_sum_int | 0.004399 | 0.011875 (2.70×) | 0.021051 (4.79×) | 0.005241 (1.19×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_123739.md` |
| multi_list_sum | 0.008527 | 0.026208 (3.07×) | 0.031299 (3.67×) | 0.783350 (91.87×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260219_114309.md` |
| multi_list_push_int | 0.008529 | 0.083179 (9.75×) | 0.032209 (3.78×) | 0.011110 (1.30×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260219_123742.md` |
| dot_product | 0.004780 | 0.017754 (3.71×) | 0.024412 (5.11×) | 0.547356 (114.51×) | `benchmarks/results/dot_product_darwin_arm64_20260219_094136.md` |
| dot_product_int | 0.005468 | 0.019166 (3.51×) | 0.026497 (4.85×) | 0.010319 (1.89×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_123740.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- array_sum (boxed list) now lands near ~5.1× C on native after fast-path fixes; biggest gaps remain alloc_churn/alloc_drop and boxed dot_product.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~3.1× C while native is ~3.7× C. OBC improved to ~0.78s (~92×) after LIST_SUM3_INT_LOOP but remains far from C.
- array_sum_int OBC holds at ~0.0052s (~1.19× C); dot_product_int and multi_list_push_int now also land near C after multi-list push loop opcodes (~1.89× and ~1.30×, respectively).
- dot_product (boxed) now ~3.6× C on Oren C and ~5.1× C on native; OBC is ~115× after LIST_DOT fast path and remains the largest gap.
