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
| array_sum | 0.004047 | 0.007922 (1.96×) | 0.008590 (2.12×) | 0.283780 (70.13×) | `benchmarks/results/array_sum_darwin_arm64_20260226_042835.md` |
| array_sum_int | 0.004201 | 0.008025 (1.91×) | 0.008884 (2.11×) | 0.278792 (66.36×) | `benchmarks/results/array_sum_int_darwin_arm64_20260226_041613.md` |
| dot_product | 0.005037 | 0.013096 (2.60×) | 0.012924 (2.57×) | 0.412298 (81.86×) | `benchmarks/results/dot_product_darwin_arm64_20260226_042830.md` |
| dot_product_int | 0.005420 | 0.012842 (2.37×) | 0.013794 (2.55×) | 0.421071 (77.69×) | `benchmarks/results/dot_product_int_darwin_arm64_20260226_041608.md` |
| loop_sum | 0.066490 | 0.061305 (0.92×) | 0.225870 (3.40×) | 0.094050 (1.41×) | `benchmarks/results/loop_sum_darwin_arm64_20260226_043520.md` |
| multi_list_push_int | 0.008423 | 0.037022 (4.40×) | 0.028302 (3.36×) | 0.533589 (63.35×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260226_023828.md` |
| multi_list_sum | 0.008222 | 0.037745 (4.59×) | 0.019307 (2.35×) | 0.575606 (70.01×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260226_042839.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
