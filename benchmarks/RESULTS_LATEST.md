# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002798 | 0.013054 (4.67×) | 0.019063 (6.81×) | 0.162268 (58.00×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_180916.md` |
| alloc_drop | 0.003031 | 0.002483 (0.82×) | 0.007076 (2.33×) | 0.004004 (1.32×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_180920.md` |
| array_sum | 0.003928 | 0.009107 (2.32×) | 0.016459 (4.19×) | 0.257807 (65.64×) | `benchmarks/results/array_sum_darwin_arm64_20260225_180922.md` |
| array_sum_int | 0.004485 | 0.009067 (2.02×) | 0.016057 (3.58×) | 0.255912 (57.06×) | `benchmarks/results/array_sum_int_darwin_arm64_20260225_180926.md` |
| dot_product | 0.005124 | 0.015817 (3.09×) | 0.023575 (4.60×) | 0.383419 (74.83×) | `benchmarks/results/dot_product_darwin_arm64_20260225_180930.md` |
| dot_product_int | 0.005379 | 0.015720 (2.92×) | 0.023234 (4.32×) | 0.378933 (70.45×) | `benchmarks/results/dot_product_int_darwin_arm64_20260225_180935.md` |
| loop_sum | 0.067371 | 0.062576 (0.93×) | 0.230209 (3.42×) | 0.095090 (1.41×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_180940.md` |
| multi_list_push_int | 0.009892 | 0.041094 (4.15×) | 0.029105 (2.94×) | 0.525091 (53.08×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260225_180945.md` |
| multi_list_sum | 0.009698 | 0.041096 (4.24×) | 0.029739 (3.07×) | 0.531616 (54.82×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260225_180951.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
