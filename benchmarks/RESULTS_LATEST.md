# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.066354 | 0.060809 (0.92×) | 0.261186 (3.94×) | 0.092152 (1.39×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_181444.md` |
| array_sum | 0.004373 | 0.008249 (1.89×) | 0.015323 (3.50×) | 0.009476 (2.17×) | `benchmarks/results/array_sum_darwin_arm64_20260219_182542.md` |
| array_sum_int | 0.004536 | 0.008206 (1.81×) | 0.020735 (4.57×) | 0.005258 (1.16×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_182544.md` |
| multi_list_sum | 0.008349 | 0.017322 (2.07×) | 0.030751 (3.68×) | 0.015799 (1.89×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260219_130703.md` |
| multi_list_push_int | 0.008171 | 0.037124 (4.54×) | 0.030914 (3.78×) | 0.011365 (1.39×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260219_130710.md` |
| dot_product | 0.005504 | 0.012386 (2.25×) | 0.025312 (4.60×) | 0.012369 (2.25×) | `benchmarks/results/dot_product_darwin_arm64_20260219_182538.md` |
| dot_product_int | 0.005216 | 0.012870 (2.47×) | 0.025346 (4.86×) | 0.009547 (1.83×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_182540.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum OBC lands at ~1.39× C after emitting a fused AVM `INT_LCG_SUM_LOOP` opcode for the LCG+sum loop (now using a fast sum-mod reduction when safe).
- loop_sum Oren C can edge out C on this microbench after LCG fast-path parity fixes; treat this as a narrow win until revalidated on more hosts.
- loop_sum now has fast-path lowering for C/native backends (LCG+sum loop); Oren C lands at ~0.92×
  (a narrow microbench win) while native is still ~3.94×. The fast path triggers; remaining gap
  appears dominated by runtime init + per-process overhead rather than the loop body. Next:
  quantify init cost and explore a fast-init path for pure-int benchmarks.
- loop_sum init-only (args `0 1`, n=0 reps=1): C 0.002027s, Oren C 0.002278s (~1.12×), native 0.002368s (~1.17×), OBC 0.002109s (~1.04×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_161557.md`
- loop_sum steady-state (args `2000000 10`, 20M total iters): C 0.065753s, Oren C 0.060181s (~0.92×), native 0.423776s (~6.44×), OBC 0.097867s (~1.49×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_161607.md`
- array_sum (boxed list) now lands near ~3.50× C on native; Oren C is ~1.89× C and OBC ~2.17× after list.push loop opcodes were emitted for boxed fill loops.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~2.1× C while native is ~3.7× C. OBC is ~0.0158s (~1.89×) after emitting list_int push loops for list.push (boxed) in the fill loop.
- array_sum_int OBC holds at ~0.0053s (~1.16× C); dot_product_int and multi_list_push_int now also land near C after multi-list push loop opcodes (~1.83× and ~1.39×, respectively). C-backend multi_list_push_int improved to ~4.54× after enabling -O2 by default.
- dot_product (boxed) now ~2.25× C on Oren C and ~4.60× C on native; OBC is ~2.25× after list.push loop opcodes removed the fill-loop overhead (LIST_DOT already handles the inner loop).
