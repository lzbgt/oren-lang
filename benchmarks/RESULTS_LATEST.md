# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002713 | 0.012436 (4.58×) | 0.019613 (7.23×) | 0.161827 (59.64×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_190747.md` |
| alloc_drop | 0.002962 | 0.002495 (0.84×) | 0.006860 (2.32×) | 0.003884 (1.31×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_190750.md` |
| array_sum | 0.004043 | 0.007865 (1.95×) | 0.016664 (4.12×) | 0.255961 (63.31×) | `benchmarks/results/array_sum_darwin_arm64_20260225_190752.md` |
| array_sum_int | 0.004099 | 0.007589 (1.85×) | 0.016575 (4.04×) | 0.253680 (61.90×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_190756.md` |
| dot_product | 0.005063 | 0.012267 (2.42×) | 0.021772 (4.30×) | 0.378822 (74.82×) | `benchmarks/results/dot_product_darwin_arm64_20260225_190800.md` |
| dot_product_int | 0.005270 | 0.012725 (2.41×) | 0.021602 (4.10×) | 0.374764 (71.11×) | `benchmarks/results/dot_product_int_darwin_arm64_20260225_190805.md` |
| loop_sum | 0.066414 | 0.061959 (0.93×) | 0.227022 (3.42×) | 0.094341 (1.42×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_190809.md` |
| multi_list_push_int | 0.008086 | 0.036685 (4.54×) | 0.027417 (3.39×) | 0.520932 (64.42×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_190814.md` |
| multi_list_sum | 0.008515 | 0.036903 (4.33×) | 0.027307 (3.21×) | 0.523693 (61.51×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_190820.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
