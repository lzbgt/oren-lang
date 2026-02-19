# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.2-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002697 | 0.032815 (12.17×) | 0.075680 (28.06×) | 0.170757 (63.31×) | `benchmarks/results/alloc_churn_darwin_arm64_20260220_064546.md` |
| alloc_drop | 0.002913 | 0.004688 (1.61×) | 0.097200 (33.37×) | 0.007191 (2.47×) | `benchmarks/results/alloc_drop_darwin_arm64_20260220_064550.md` |
| array_sum | 0.004218 | 0.008191 (1.94×) | 0.016020 (3.80×) | 0.009304 (2.21×) | `benchmarks/results/array_sum_darwin_arm64_20260220_042051.md` |
| array_sum_int | 0.004181 | 0.008147 (1.95×) | 0.017639 (4.22×) | 0.004821 (1.15×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_042054.md` |
| dot_product | 0.005059 | 0.049907 (9.87×) | 0.054673 (10.81×) | 0.248005 (49.02×) | `benchmarks/results/dot_product_darwin_arm64_20260220_055840.md` |
| dot_product_int | 0.005082 | 0.012445 (2.45×) | 0.022297 (4.39×) | 0.009167 (1.80×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_042058.md` |
| loop_sum | 0.067115 | 0.061314 (0.91×) | 0.226793 (3.38×) | 0.093213 (1.39×) | `benchmarks/results/loop_sum_darwin_arm64_20260220_055835.md` |
| multi_list_push_int | 0.009168 | 0.037586 (4.10×) | 0.028363 (3.09×) | 0.011138 (1.21×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_042103.md` |
| multi_list_sum | 0.008371 | 0.017091 (2.04×) | 0.026359 (3.15×) | 0.015274 (1.82×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_042106.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- dot_product (boxed) remains far from parity across backends; LIST_DOT covers the inner loop, but boxed list access + init overhead still dominate. See the table for current ratios.
- array_sum/multi_list_sum are still boxed-list bound on native; OBC benefits from list.push loop opcodes.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
