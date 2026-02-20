# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.2-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.003726 | 0.036602 (9.82×) | 0.078430 (21.05×) | 0.181752 (48.78×) | `benchmarks/results/alloc_churn_darwin_arm64_20260220_075918.md` |
| alloc_drop | 0.003226 | 0.005474 (1.70×) | 0.108412 (33.60×) | 0.008235 (2.55×) | `benchmarks/results/alloc_drop_darwin_arm64_20260220_075920.md` |
| array_sum | 0.006063 | 0.036111 (5.96×) | 0.031073 (5.12×) | 0.160097 (26.40×) | `benchmarks/results/array_sum_darwin_arm64_20260220_075921.md` |
| array_sum_int | 0.005526 | 0.011131 (2.01×) | 0.019862 (3.59×) | 0.006532 (1.18×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_075923.md` |
| dot_product | 0.006335 | 0.058914 (9.30×) | 0.063138 (9.97×) | 0.288174 (45.49×) | `benchmarks/results/dot_product_darwin_arm64_20260220_075924.md` |
| dot_product_int | 0.007476 | 0.019818 (2.65×) | 0.026845 (3.59×) | 0.012192 (1.63×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_075927.md` |
| loop_sum | 0.072508 | 0.066659 (0.92×) | 0.248179 (3.42×) | 0.099799 (1.38×) | `benchmarks/results/loop_sum_darwin_arm64_20260220_075927.md` |
| multi_list_push_int | 0.012639 | 0.049279 (3.90×) | 0.032413 (2.56×) | 0.014850 (1.17×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_075931.md` |
| multi_list_sum | 0.011053 | 0.085765 (7.76×) | 0.077992 (7.06×) | 0.340814 (30.84×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_075932.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- dot_product (boxed) remains far from parity across backends; LIST_DOT covers the inner loop, but boxed list access + init overhead still dominate. See the table for current ratios.
- array_sum/multi_list_sum are still boxed-list bound on native; OBC benefits from list.push loop opcodes.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
