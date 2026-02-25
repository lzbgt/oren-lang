# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-25  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002789 | 0.012676 (4.55×) | 0.019003 (6.81×) | 0.161193 (57.80×) | `benchmarks/results/alloc_churn_darwin_arm64_20260225_175355.md` |
| alloc_drop | 0.002982 | 0.002605 (0.87×) | 0.006855 (2.30×) | 0.003891 (1.30×) | `benchmarks/results/alloc_drop_darwin_arm64_20260225_175358.md` |
| array_sum | 0.003928 | 0.008314 (2.12×) | 0.015737 (4.01×) | 0.144631 (36.82×) | `benchmarks/results/array_sum_darwin_arm64_20260220_162853.md` |
| array_sum_int | 0.003865 | 0.007937 (2.05×) | 0.015926 (4.12×) | 0.004629 (1.20×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_104956.md` |
| dot_product | 0.005383 | 0.014659 (2.72×) | 0.022324 (4.15×) | 0.386750 (71.85×) | `benchmarks/results/dot_product_darwin_arm64_20260225_175656.md` |
| dot_product_int | 0.004929 | 0.013228 (2.68×) | 0.021600 (4.38×) | 0.009287 (1.88×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_105040.md` |
| loop_sum | 0.067356 | 0.061897 (0.92×) | 0.228706 (3.40×) | 0.094036 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260225_175621.md` |
| multi_list_push_int | 0.008798 | 0.038419 (4.37×) | 0.027695 (3.15×) | 0.011052 (1.26×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_105047.md` |
| multi_list_sum | 0.008649 | 0.038789 (4.48×) | 0.026920 (3.11×) | 0.305721 (35.35×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_162900.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; Oren C can edge out C on this microbench, while native still trails (see table). The remaining gap is likely runtime init + per-process overhead; quantify init cost for pure-int benchmarks.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~3–4× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- list<int> benches (array_sum_int, dot_product_int, multi_list_push_int) stay closest to parity on OBC; native dot_product_int remains above target.
