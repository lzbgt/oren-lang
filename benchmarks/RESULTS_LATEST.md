# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.003049 | 0.012431 (4.08×) | 0.018969 (6.22×) | 0.164831 (54.06×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_182158.md` |
| alloc_drop | 0.003085 | 0.002717 (0.88×) | 0.007226 (2.34×) | 0.004256 (1.38×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_182201.md` |
| array_sum | 0.004806 | 0.009595 (2.00×) | 0.017047 (3.55×) | 0.267635 (55.68×) | `benchmarks/results/array_sum_darwin_arm64_20260225_182203.md` |
| array_sum_int | 0.004395 | 0.008997 (2.05×) | 0.016386 (3.73×) | 0.255468 (58.13×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_182208.md` |
| dot_product | 0.006015 | 0.013981 (2.32×) | 0.023907 (3.97×) | 0.416495 (69.25×) | `benchmarks/results/dot_product_darwin_arm64_20260225_182212.md` |
| dot_product_int | 0.005793 | 0.017210 (2.97×) | 0.023404 (4.04×) | 0.388338 (67.03×) | `benchmarks/results/dot_product_int_darwin_arm64_20260225_182217.md` |
| loop_sum | 0.069725 | 0.063343 (0.91×) | 0.234665 (3.37×) | 0.096377 (1.38×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_182222.md` |
| multi_list_push_int | 0.009445 | 0.040652 (4.30×) | 0.028458 (3.01×) | 0.521388 (55.20×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_182227.md` |
| multi_list_sum | 0.009473 | 0.044986 (4.75×) | 0.030610 (3.23×) | 0.526488 (55.58×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_182233.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
