# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.2-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002837 | 0.030867 (10.88×) | 3.887075 (1370.26×) | 0.168796 (59.50×) | `benchmarks/results/alloc_churn_darwin_arm64_20260220_153502.md` |
| alloc_drop | 0.002921 | 0.004492 (1.54×) | 0.175062 (59.94×) | 0.006840 (2.34×) | `benchmarks/results/alloc_drop_darwin_arm64_20260220_153459.md` |
| array_sum | 0.004031 | 0.030207 (7.49×) | 3.114184 (772.52×) | 0.143692 (35.64×) | `benchmarks/results/array_sum_darwin_arm64_20260220_104935.md` |
| array_sum_int | 0.003865 | 0.007937 (2.05×) | 0.015926 (4.12×) | 0.004629 (1.20×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_104956.md` |
| dot_product | 0.004948 | 0.048653 (9.83×) | 6.228725 (1258.73×) | 0.244564 (49.42×) | `benchmarks/results/dot_product_darwin_arm64_20260220_104959.md` |
| dot_product_int | 0.004929 | 0.013228 (2.68×) | 0.021600 (4.38×) | 0.009287 (1.88×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_105040.md` |
| loop_sum | 0.065636 | 0.060110 (0.92×) | 0.224186 (3.42×) | 0.091977 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260220_105042.md` |
| multi_list_push_int | 0.008798 | 0.038419 (4.37×) | 0.027695 (3.15×) | 0.011052 (1.26×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_105047.md` |
| multi_list_sum | 0.008487 | 0.068362 (8.05×) | 9.308602 (1096.76×) | 0.312384 (36.81×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_105049.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- dot_product (boxed) remains far from parity across backends; LIST_DOT covers the inner loop, but boxed list access + init overhead still dominate. See the table for current ratios.
- array_sum/multi_list_sum are still boxed-list bound on native; OBC benefits from list.push loop opcodes.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
