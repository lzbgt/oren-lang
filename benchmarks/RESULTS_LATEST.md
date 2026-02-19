# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.070953 | 0.360361 (5.08×) | 0.448654 (6.32×) | 0.103690 (1.46×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_144327.md` |
| array_sum | 0.004190 | 0.007941 (1.90×) | 0.020951 (5.00×) | 0.010095 (2.41×) | `benchmarks/results/array_sum_darwin_arm64_20260219_130446.md` |
| array_sum_int | 0.004914 | 0.010160 (2.07×) | 0.022312 (4.54×) | 0.005768 (1.17×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_144341.md` |
| multi_list_sum | 0.008349 | 0.017322 (2.07×) | 0.030751 (3.68×) | 0.015799 (1.89×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260219_130703.md` |
| multi_list_push_int | 0.008171 | 0.037124 (4.54×) | 0.030914 (3.78×) | 0.011365 (1.39×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260219_130710.md` |
| dot_product | 0.005407 | 0.012672 (2.34×) | 0.025681 (4.75×) | 0.012785 (2.36×) | `benchmarks/results/dot_product_darwin_arm64_20260219_130440.md` |
| dot_product_int | 0.005468 | 0.019166 (3.51×) | 0.026497 (4.85×) | 0.010319 (1.89×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_123740.md` |
| alloc_churn | 0.004082 | 0.069660 (17.07×) | 0.162040 (39.70×) | 0.388069 (95.07×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_045329.md` |
| alloc_drop | 0.004179 | 0.006641 (1.59×) | 0.103303 (24.72×) | 0.011457 (2.74×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_045323.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum OBC lands at ~1.46× C after emitting a fused AVM `INT_LCG_SUM_LOOP` opcode for the LCG+sum loop.
- loop_sum now has fast-path lowering for C/native backends (LCG+sum loop), but the M2 baseline is still
  ~5.08× (Oren C) and ~6.32× (native). The fast path triggers; remaining gap appears dominated by
  runtime init + per-process overhead rather than the loop body. Next: quantify init cost and
  explore a fast-init path for pure-int benchmarks.
- loop_sum init-only (args `0 1`, n=0 reps=1): C 0.002128s, Oren C 0.002437s (~1.15×), native 0.002609s (~1.23×), OBC 0.002730s (~1.28×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_144914.md`
- loop_sum steady-state (args `2000000 10`, 20M total iters): C 0.068589s, Oren C 0.355774s (~5.19×), native 0.434835s (~6.34×), OBC 0.103215s (~1.50×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_144919.md`
- array_sum (boxed list) now lands near ~5.0× C on native; Oren C is ~1.90× C and OBC ~2.41× after list.push loop opcodes were emitted for boxed fill loops.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~2.1× C while native is ~3.7× C. OBC is ~0.0158s (~1.89×) after emitting list_int push loops for list.push (boxed) in the fill loop.
- array_sum_int OBC holds at ~0.0058s (~1.17× C); dot_product_int and multi_list_push_int now also land near C after multi-list push loop opcodes (~1.89× and ~1.39×, respectively). C-backend multi_list_push_int improved to ~4.54× after enabling -O2 by default.
- dot_product (boxed) now ~2.34× C on Oren C and ~4.75× C on native; OBC is ~2.36× after list.push loop opcodes removed the fill-loop overhead (LIST_DOT already handles the inner loop).
