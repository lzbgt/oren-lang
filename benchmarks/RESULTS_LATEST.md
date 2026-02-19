# Latest Benchmark Snapshot (Apple M2 Pro, macOS-26.2-arm64-arm-64bit-Mach-O, arm64)

**Date:** 2026-02-20  
**Host:** Bruce-Mac, Apple M2 Pro (10 cores, 17179869184 bytes)

This snapshot summarizes the **latest** benchmark artifacts under `benchmarks/results/`.
Use the linked result files for full run details (runs, warmups, RSS, checksums).
Repo policy: only the files referenced here are retained; older result files are pruned.

Legend: `x` = slowdown relative to C median.

| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) | result file |
| --- | --- | --- | --- | --- | --- |
| alloc_churn | 0.002660 | 0.030967 (11.64×) | 0.070210 (26.39×) | 0.164351 (61.78×) | `benchmarks/results/alloc_churn_darwin_arm64_20260220_042046.md` |
| alloc_drop | 0.002843 | 0.004388 (1.54×) | 0.097563 (34.32×) | 0.007365 (2.59×) | `benchmarks/results/alloc_drop_darwin_arm64_20260220_042049.md` |
| array_sum | 0.004218 | 0.008191 (1.94×) | 0.016020 (3.80×) | 0.009304 (2.21×) | `benchmarks/results/array_sum_darwin_arm64_20260220_042051.md` |
| array_sum_int | 0.004181 | 0.008147 (1.95×) | 0.017639 (4.22×) | 0.004821 (1.15×) | `benchmarks/results/array_sum_int_darwin_arm64_20260220_042054.md` |
| dot_product | 0.005163 | 0.012716 (2.46×) | 0.027416 (5.31×) | 0.012794 (2.48×) | `benchmarks/results/dot_product_darwin_arm64_20260220_042056.md` |
| dot_product_int | 0.005082 | 0.012445 (2.45×) | 0.022297 (4.39×) | 0.009167 (1.80×) | `benchmarks/results/dot_product_int_darwin_arm64_20260220_042058.md` |
| loop_sum | 0.066782 | 0.061884 (0.93×) | 0.228336 (3.42×) | 0.093593 (1.40×) | `benchmarks/results/loop_sum_darwin_arm64_20260220_042100.md` |
| multi_list_push_int | 0.009168 | 0.037586 (4.10×) | 0.028363 (3.09×) | 0.011138 (1.21×) | `benchmarks/results/multi_list_push_int_darwin_arm64_20260220_042103.md` |
| multi_list_sum | 0.008371 | 0.017091 (2.04×) | 0.026359 (3.15×) | 0.015274 (1.82×) | `benchmarks/results/multi_list_sum_darwin_arm64_20260220_042106.md` |

Notes:

- alloc_churn/alloc_drop are allocation-heavy; they highlight tracking and GC overhead.
- loop_sum OBC lands at ~1.40× C after emitting a fused AVM `INT_LCG_SUM_LOOP` opcode for the LCG+sum loop (now using a fast sum-mod reduction when safe).
- loop_sum Oren C can edge out C on this microbench after LCG fast-path parity fixes; treat this as a narrow win until revalidated on more hosts.
- loop_sum now has fast-path lowering for C/native backends (LCG+sum loop); Oren C lands at ~0.91×
  (a narrow microbench win) while native is still ~3.38×. The fast path triggers; remaining gap
  appears dominated by runtime init + per-process overhead rather than the loop body. Next:
  quantify init cost and explore a fast-init path for pure-int benchmarks (capture via a targeted run).
- array_sum (boxed list) now lands near ~3.80× C on native; Oren C is ~2.20× C and OBC ~2.35× after list.push loop opcodes were emitted for boxed fill loops.
- multi_list_sum highlights boxed list access across multiple arrays; Oren C is now ~2.17× C while native is ~2.99× C. OBC is ~0.0164s (~1.92×) after emitting list_int push loops for list.push (boxed) in the fill loop.
- array_sum_int OBC holds at ~0.0047s (~1.18× C); dot_product_int and multi_list_push_int now also land near C after multi-list push loop opcodes (~1.94× and ~1.36×, respectively). C-backend multi_list_push_int improved to ~4.51× after enabling -O2 by default.
- dot_product (boxed) now ~2.68× C on Oren C and ~5.06× C on native; OBC is ~2.62× after list.push loop opcodes removed the fill-loop overhead (LIST_DOT already handles the inner loop).
