# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.2-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002886 | 0.032089 (11.12×) | 0.071286 (24.70×) | 0.169706 (58.79×) | `benchmarks/results/alloc_churn_darwin_arm64_20260220_072626.md` |
| alloc_drop | 0.003082 | 0.005033 (1.63×) | 0.097255 (31.56×) | 0.007602 (2.47×) | `benchmarks/results/alloc_drop_darwin_arm64_20260220_072630.md` |
| array_sum | 0.004369 | 0.031628 (7.24×) | 0.028946 (6.63×) | 0.148625 (34.02×) | `benchmarks/results/array_sum_darwin_arm64_20260220_072632.md` |
| array_sum_int | 0.004350 | 0.008333 (1.92×) | 0.016766 (3.85×) | 0.005135 (1.18×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_072636.md` |
| dot_product | 0.005621 | 0.050342 (8.96×) | 0.056961 (10.13×) | 0.252915 (45.00×) | `benchmarks/results/dot_product_darwin_arm64_20260220_072638.md` |
| dot_product_int | 0.005494 | 0.013494 (2.46×) | 0.022900 (4.17×) | 0.009878 (1.80×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_072642.md` |
| loop_sum | 0.067659 | 0.062680 (0.93×) | 0.228625 (3.38×) | 0.094200 (1.39×) | `benchmarks/results/loop_sum_darwin_arm64_20260220_072644.md` |
| multi_list_push_int | 0.008929 | 0.038942 (4.36×) | 0.028508 (3.19×) | 0.011714 (1.31×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_072649.md` |
| multi_list_sum | 0.008901 | 0.070321 (7.90×) | 0.072441 (8.14×) | 0.322278 (36.21×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_072651.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- dot_product (boxed) remains far from parity across backends; LIST_DOT covers the inner loop, but boxed list access + init overhead still dominate. See the table for current ratios.
- array_sum/multi_list_sum are still boxed-list bound on native; OBC benefits from list.push loop opcodes.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
