# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.003074 | 0.012725 (4.14×) | 0.018938 (6.16×) | 0.162352 (52.81×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_182536.md` |
| alloc_drop | 0.003218 | 0.002600 (0.81×) | 0.007466 (2.32×) | 0.003987 (1.24×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_182538.md` |
| array_sum | 0.004206 | 0.008016 (1.91×) | 0.015934 (3.79×) | 0.255487 (60.74×) | `benchmarks/results/array_sum_darwin_arm64_20260225_182539.md` |
| array_sum_int | 0.004187 | 0.008287 (1.98×) | 0.015893 (3.80×) | 0.253903 (60.64×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_182541.md` |
| dot_product | 0.005291 | 0.013147 (2.48×) | 0.022359 (4.23×) | 0.381411 (72.08×) | `benchmarks/results/dot_product_darwin_arm64_20260225_182543.md` |
| dot_product_int | 0.005591 | 0.013092 (2.34×) | 0.022287 (3.99×) | 0.375942 (67.24×) | `benchmarks/results/dot_product_int_darwin_arm64_20260225_182546.md` |
| loop_sum | 0.067339 | 0.061788 (0.92×) | 0.226665 (3.37×) | 0.094545 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_182549.md` |
| multi_list_push_int | 0.008680 | 0.040001 (4.61×) | 0.028074 (3.23×) | 0.524103 (60.38×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_182552.md` |
| multi_list_sum | 0.008818 | 0.038444 (4.36×) | 0.028035 (3.18×) | 0.525113 (59.55×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_182556.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
