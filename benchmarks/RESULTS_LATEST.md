# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.003553 | 0.015366 (4.32×) | 0.021318 (6.00×) | 0.169609 (47.73×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_185700.md` |
| alloc_drop | 0.003010 | 0.002485 (0.83×) | 0.006927 (2.30×) | 0.004161 (1.38×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_185704.md` |
| array_sum | 0.004552 | 0.009409 (2.07×) | 0.017886 (3.93×) | 0.272239 (59.80×) | `benchmarks/results/array_sum_darwin_arm64_20260225_185706.md` |
| array_sum_int | 0.004684 | 0.009492 (2.03×) | 0.017554 (3.75×) | 0.264535 (56.47×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_185710.md` |
| dot_product | 0.005840 | 0.015681 (2.68×) | 0.024167 (4.14×) | 0.397054 (67.99×) | `benchmarks/results/dot_product_darwin_arm64_20260225_185715.md` |
| dot_product_int | 0.005808 | 0.015907 (2.74×) | 0.024248 (4.17×) | 0.392346 (67.55×) | `benchmarks/results/dot_product_int_darwin_arm64_20260225_185720.md` |
| loop_sum | 0.069279 | 0.063825 (0.92×) | 0.236250 (3.41×) | 0.096718 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_185725.md` |
| multi_list_push_int | 0.010196 | 0.044209 (4.34×) | 0.030857 (3.03×) | 0.546791 (53.63×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_185730.md` |
| multi_list_sum | 0.010114 | 0.043653 (4.32×) | 0.030782 (3.04×) | 0.553216 (54.70×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_185736.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
