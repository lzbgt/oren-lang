# Latest Benchmark Snapshot (M2 Pro, darwin/arm64)

**Date:** 2026-02-19  
**Host:** Bruce-Mac (Apple M2 Pro, 10 cores, 16GB)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| loop_sum | 0.065730 | 0.060062 (0.91×) | 0.221878 (3.38×) | 0.092120 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260219_223720.md` |
| array_sum | 0.003892 | 0.008553 (2.20×) | 0.014779 (3.80×) | 0.009161 (2.35×) | `benchmarks/results/array_sum_darwin_arm64_20260219_223724.md` |
| array_sum_int | 0.003928 | 0.008030 (2.04×) | 0.016140 (4.11×) | 0.004650 (1.18×) | `benchmarks/results/array_sum_int_darwin_arm64_20260219_223726.md` |
| multi_list_sum | 0.008512 | 0.018449 (2.17×) | 0.025475 (2.99×) | 0.016364 (1.92×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260219_223728.md` |
| multi_list_push_int | 0.008462 | 0.038182 (4.51×) | 0.026836 (3.17×) | 0.011507 (1.36×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260219_223731.md` |
| dot_product | 0.004967 | 0.013336 (2.68×) | 0.025120 (5.06×) | 0.013010 (2.62×) | `benchmarks/results/dot_product_darwin_arm64_20260219_223733.md` |
| dot_product_int | 0.004893 | 0.013196 (2.70×) | 0.021647 (4.42×) | 0.009513 (1.94×) | `benchmarks/results/dot_product_int_darwin_arm64_20260219_223735.md` |
| alloc_churn | 0.002586 | 0.036300 (14.04×) | 0.163014 (63.04×) | 0.163026 (63.04×) | `benchmarks/results/alloc_churn_darwin_arm64_20260219_223737.md` |
| alloc_drop | 0.002722 | 0.004360 (1.60×) | 0.102530 (37.66×) | 0.006801 (2.50×) | `benchmarks/results/alloc_drop_darwin_arm64_20260219_223741.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum OBC lands at ~1.40× C after emitting a fused AVM `INT_LCG_SUM_LOOP` opcode for the LCG+sum loop (now using a fast sum-mod reduction when safe).
- loop_sum Oren C can edge out C on this microbench after LCG fast-path parity fixes; treat this as a narrow win until revalidated on more hosts.
- loop_sum now has fast-path lowering for C/native backends (LCG+sum loop); Oren C lands at ~0.91×
  (a narrow microbench win) while native is still ~3.38×. The fast path triggers; remaining gap
  appears dominated by runtime init + per-process overhead rather than the loop body. Next:
  quantify init cost and explore a fast-init path for pure-int benchmarks.
- loop_sum init-only (args `0 1`, n=0 reps=1): C 0.002027s, Oren C 0.002278s (~1.12×), native 0.002368s (~1.17×), OBC 0.002109s (~1.04×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_161557.md`
- loop_sum steady-state (args `2000000 10`, 20M total iters): C 0.065753s, Oren C 0.060181s (~0.92×), native 0.423776s (~6.44×), OBC 0.097867s (~1.49×).
  - Result: `benchmarks/results/loop_sum_darwin_arm64_20260219_161607.md`
- array_sum (boxed list) now lands near ~3.80× C on native; Oren C is ~2.20× C and OBC ~2.35× after list.push loop opcodes were emitted for boxed fill loops.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~2.17× C while native is ~2.99× C. OBC is ~0.0164s (~1.92×) after emitting list_int push loops for list.push (boxed) in the fill loop.
- array_sum_int OBC holds at ~0.0047s (~1.18× C); dot_product_int and multi_list_push_int now also land near C after multi-list push loop opcodes (~1.94× and ~1.36×, respectively). C-backend multi_list_push_int improved to ~4.51× after enabling -O2 by default.
- dot_product (boxed) now ~2.68× C on Oren C and ~5.06× C on native; OBC is ~2.62× after list.push loop opcodes removed the fill-loop overhead (LIST_DOT already handles the inner loop).
