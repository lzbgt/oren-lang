# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-26  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002974 | 0.012214 (4.11×) | 0.017783 (5.98×) | 0.163190 (54.88×) | `benchmarks/results/alloc_churn_darwin_arm64_20260226_022314.md` |
| alloc_drop | 0.002951 | 0.002516 (0.85×) | 0.006713 (2.27×) | 0.003900 (1.32×) | `benchmarks/results/alloc_drop_darwin_arm64_20260226_022316.md` |
| array_sum | 0.004628 | 0.009425 (2.04×) | 0.018602 (4.02×) | 0.260376 (56.26×) | `benchmarks/results/array_sum_darwin_arm64_20260225_233618.md` |
| array_sum_int | 0.004614 | 0.009722 (2.11×) | 0.018277 (3.96×) | 0.257964 (55.91×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_233620.md` |
| dot_product | 0.005792 | 0.014675 (2.53×) | 0.023031 (3.98×) | 0.385035 (66.48×) | `benchmarks/results/dot_product_darwin_arm64_20260226_022915.md` |
| dot_product_int | 0.005613 | 0.014179 (2.53×) | 0.021692 (3.86×) | 0.375954 (66.98×) | `benchmarks/results/dot_product_int_darwin_arm64_20260226_022920.md` |
| loop_sum | 0.067141 | 0.063074 (0.94×) | 0.227686 (3.39×) | 0.094460 (1.41×) | `benchmarks/results/loop_sum_darwin_arm64_20260226_022910.md` |
| multi_list_push_int | 0.009164 | 0.040005 (4.37×) | 0.029287 (3.20×) | 0.526419 (57.45×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_233632.md` |
| multi_list_sum | 0.009747 | 0.041721 (4.28×) | 0.029655 (3.04×) | 0.531158 (54.49×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_233636.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
