# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-26  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002931 | 0.012568 (4.29×) | 0.018404 (6.28×) | 0.167005 (56.97×) | `benchmarks/results/alloc_churn_darwin_arm64_20260226_023800.md` |
| alloc_drop | 0.002957 | 0.002527 (0.85×) | 0.006985 (2.36×) | 0.003942 (1.33×) | `benchmarks/results/alloc_drop_darwin_arm64_20260226_023803.md` |
| array_sum | 0.004559 | 0.009189 (2.02×) | 0.016502 (3.62×) | 0.256702 (56.31×) | `benchmarks/results/array_sum_darwin_arm64_20260226_025516.md` |
| array_sum_int | 0.004350 | 0.009034 (2.08×) | 0.016525 (3.80×) | 0.253592 (58.29×) | `benchmarks/results/array_sum_int_darwin_arm64_20260226_025143.md` |
| dot_product | 0.005299 | 0.014907 (2.81×) | 0.022779 (4.30×) | 0.385132 (72.69×) | `benchmarks/results/dot_product_darwin_arm64_20260226_025518.md` |
| dot_product_int | 0.005296 | 0.015252 (2.88×) | 0.021807 (4.12×) | 0.379132 (71.58×) | `benchmarks/results/dot_product_int_darwin_arm64_20260226_025027.md` |
| loop_sum | 0.066705 | 0.062789 (0.94×) | 0.225979 (3.39×) | 0.095437 (1.43×) | `benchmarks/results/loop_sum_darwin_arm64_20260226_040304.md` |
| multi_list_push_int | 0.008423 | 0.037022 (4.40×) | 0.028302 (3.36×) | 0.533589 (63.35×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260226_023828.md` |
| multi_list_sum | 0.008727 | 0.040382 (4.63×) | 0.027744 (3.18×) | 0.531214 (60.87×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260226_025146.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
