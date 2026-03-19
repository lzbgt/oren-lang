# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.3-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-03-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the latest benchmark results generated from local artifacts under
`build/benchmarks/results/`.
Benchmark JSON/markdown outputs are derived artifacts and are not part of the repository.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |
| --- | --- | --- | --- | --- |
| alloc_churn | 0.002815 | n/a | 0.019792 (7.03×) | n/a |
| alloc_drop | 0.005001 | n/a | 0.009269 (1.85×) | n/a |
| array_sum | 0.004047 | 0.007922 (1.96×) | 0.008590 (2.12×) | 0.283780 (70.13×) |
| array_sum_int | 0.004052 | 0.008237 (2.03×) | 0.008851 (2.18×) | 0.125240 (30.91×) |
| dot_product | 0.005253 | n/a | 0.014905 (2.84×) | n/a |
| dot_product_int | 0.005001 | 0.012141 (2.43×) | 0.013374 (2.67×) | 0.156292 (31.25×) |
| loop_sum | 0.068905 | n/a | 0.074446 (1.08×) | n/a |
| multi_list_push_int | 0.008602 | 0.036729 (4.27×) | 0.018802 (2.19×) | 0.582787 (67.75×) |
| multi_list_sum | 0.008222 | 0.037745 (4.59×) | 0.019307 (2.35×) | 0.575606 (70.01×) |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum uses a fused AVM `INT_LCG_SUM_LOOP` fast path and a native/C lowering; with the repaired arm64 fast LCG path, native is now close to C on this microbench (see table). Keep tracking init vs steady-state cost for pure-int loops, but the remaining W5 hot-loop gap is no longer loop_sum on arm64.
- array_sum/dot_product/multi_list_sum are now auto-lowered to list<int> when lists are int-only and do not escape; native parity is within ~2–3× for these cases.
- Boxed-list parity remains open for workloads that require mixed types or list escape; those still need dedicated fast paths.
- Latest focused `list<int>` clean rerun (2026-03-20) now puts `array_sum_int` at 2.18× C, `dot_product_int` at 2.67× C, and `multi_list_push_int` at 2.19× C natively. The one-shot view stayed roughly flat even after the latest arm64 loop work, which is another reason to prefer the steady-state runner for read-heavy tracker updates.
- The derived result artifacts now retain raw timing vectors plus `stdev_s` / `cov`; on the latest clean rerun the native variants stayed low-variance (`array_sum_int` cov ~1.41%, `dot_product_int` cov ~1.65%, `multi_list_push_int` cov ~1.22%).
- New: the exact arm64 single-list `list<int>` get-sum shape and exact two-list single-pair `list<int>` dot shape now unroll by 4 on the hot path. On the steady runner (`make perf-gate-list-int-steady`, `reps=100`) that moved `array_sum_int` from the earlier ~3.38× baseline to ~2.87× and `dot_product_int` from ~3.90× to ~3.17× native/C. The repeated read/mul/accumulate loop is still above the 2× target, but materially closer than before.
- The read split (`make perf-gate-list-int-read-split`) is now an auxiliary debugging view, not the canonical steady-state baseline. It reports both delta-based and long-run-per-rep estimates and warns when they drift materially; for example, the latest `array_sum_int` split drifted by about 30%, so tracker updates should prefer the steady runner or the split long-per-rep estimate over the naive delta subtraction.
