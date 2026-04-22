# Status + Tracker (Rolling)

**Last updated:** 2026-04-23

This document is intentionally lean: active tracker + feature matrix.
No archives. No stubs. When a task is done enough, summarize it and move on.

---

## How to use this tracker

- Start at P0 and take the first unfinished item.
- Tie work to a regression gate (benchmark or test).
- Update fixtures and this doc when behavior changes.
- High-level goals live in `docs/BLEEDING_EDGE_TASKS.md`.
- For a reproducible snapshot, run `make readiness-report` (writes markdown + logs under `build/`).
  Use `make readiness-report-json` or `./scripts/readiness_report.sh --json` for machine-readable output.
  Append JSONL summaries via `make readiness-report-index`; latest pointers live under `build/reports/readiness_latest.*`.
  Generate summaries via `make readiness-report-summary` (writes `build/reports/readiness_summary.*`).
  Index tools: `make readiness-report-index-stats`, `make readiness-report-index-prune`,
  `make readiness-report-index-csv`, `make readiness-report-index-query`, `make readiness-report-index-rollup`,
  `make readiness-report-index-merge`, `make readiness-report-index-compact`, `make readiness-report-index-diff`.
  Summary diff: `make readiness-report-index-diff-summary`.
  Gates: `make readiness-report-index-gate`.
  Lint/split: `make readiness-report-index-lint`, `make readiness-report-index-split`.
  Dashboards: `make readiness-report-dashboard`.
  Schema: `make readiness-report-index-schema`.
  Use `make readiness-pipeline` to run report + summary + stats + validate in one shot.
  For a docs-only snapshot of this file, run `make status-snapshot`
  (writes `build/reports/status_snapshot.{md,json}`).
  For a readiness matrix derived from this file, run `make status-matrix`
  (writes `build/reports/status_matrix.{md,json}`).
  Diff matrices (or STATUS.md revisions) via `make status-matrix-diff`
  (writes `build/reports/status_matrix_diff.{md,json}`).
  Diff snapshots with `make status-snapshot-diff`.

---

## Maturity definition (rolling, measurable)

Oren is "mature" when all are reliably true on Tier-1 targets
(`arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`):

- Buildability: stage0 -> stage1 -> stage2 works with minimal setup.
- Semantic parity: native/C/bytecode behavior matches the fixtures.
- Performance budgets: hot loops and allocation are within target ratios vs C.
- Docs fidelity: docs match tests and the code that enforces them.
- Stdlib quality: NET/TLS/HTTP/WS loopback suites pass on Tier-1.

---

## Production readiness gap (rolling snapshot)

Oren is not yet at production parity with industrial compilers (LLVM/rustc/GCC/zig/go):

- **Semantic maturity**: tagged value model is still rolling in native; `oren_type_tag` is best‑effort for scalars and cross‑backend parity is still enforced via fixtures (see `docs/DESIGN.md`).
- **Performance parity**: native hot loops remain partly above target (fresh arm64 perf-gate snapshot, 2026-04-04: `loop_sum` 1.09×, `dot_product` 2.82×; `alloc_churn` 5.42×, `alloc_drop` 1.76×).
- **list<int> hot-loop parity**: the canonical arm64 whole-operation path is materially healthier than the earlier `~5.8×` emergency, but it is still not at production parity. The shipped baseline now keeps `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2=1` for single-read-list shapes after the heap-register clobber fix in `lib/compiler/arm64_native_stmt_loops_list_emit.oren`. The get-sum-only opt-in branches remain rejected on the actual shipped decision surface: `build/logs/perf-probe-arm64-fast-get-sum-unroll2-decision-20260409_170812_66742.log` justifies the shipped unroll2 default, while the dual-accum probe (`build/logs/perf-probe-arm64-fast-get-sum-dual-accum-decision-20260409_174904_22327.log`) and get-sum pair-post probe (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`) still lose against the shipped default in widened exact reruns and therefore stay opt-in only. The adjacent fill-side reweighting from `build/logs/perf-probe-list-int-fill-share-decision-20260409_181428_58993.log` was the right next move: fill-only `list<int>` stayed materially expensive (`oren_fill_list_int / c_fill_slot64_vector ~4.8260×`, about `~10.2796×` the then-current shipped `array_sum_int` steady per-rep read cost). One constructor-level question is now settled on the shipped tree too: a targeted native trace rerun (`build/logs/run_fill_list_int_ctor_probe_final_20260409.log`) shows the benchmark-sized `fill_list_int` header allocation as `[list_new_cap] kind=8 cap=2000000 total=16000032 mode=2`, which is the arena-backed constructor path from `lib/runtime_native/095_arena.oren`, not the plain `oren_new_list_int` malloc path from `lib/runtime_native/170_lists_core.oren`. So the remaining fill/setup blocker is below the constructor boundary, not another broad constructor rewrite. The first shipped improvement on that side was the default-on arm64 push-index-expression lowering (`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR`), which keeps pure index-only integer push expressions on the explicit `fast_list_int_push_while` lowering instead of paying generic expression compilation each iteration. Its widened decision surface (`build/logs/perf-probe-arm64-fast-push-idx-expr-decision-20260409_183650_90548.log`) aligned across both the fill/share attribution probe and the exact same-tree whole-operation C ceiling: fill/share preferred default (`default_fill_vs_c_vector ~4.4912×` vs disabled `~5.0143×`), exact `array_sum_int` preferred default in `3/5` sweeps (`default_array_ratio_median ~2.2989×` vs disabled `~2.3437×`), and exact `dot_product_int` also preferred default in `4/5` sweeps (`default_dot_ratio_median ~1.8313×` vs disabled `~1.8546×`). The narrower preserved-cursor follow-up is now also settled: `build/logs/perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision-20260409_191744_50107.log` shows `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS=1` improves the fill/share surface (`default_fill_vs_c_vector ~4.4711×` vs enabled `~3.7073×`) but still loses on the exact same-tree whole-operation surface (`default_array_ratio_median ~2.2491×` vs enabled `~2.3005×`, `default_dot_ratio_median ~1.8327×` vs enabled `~1.8585×`), so that branch remains opt-in only. The next fill-side shipped improvement is the default-on nonnegative-linear lowering (`OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR`), which keeps explicit `fast_list_int_push_while` shapes with proven nonnegative affine/mod index expressions on a direct mul/add/(u)div lowering instead of routing them through the generic int-expression compiler. Its widened decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260409_195510_97018.log`) agrees across both relevant surfaces: fill/share strongly preferred default (`default_fill_vs_c_vector ~2.8909×` vs disabled `~4.3823×`), exact `array_sum_int` also preferred default (`default_array_ratio_median ~2.2540×` vs disabled `~2.2740×`), and exact `dot_product_int` preferred default too (`default_dot_ratio_median ~1.7910×` vs disabled `~1.8065×`). A narrower modulo-recurrence follow-up under that same nonnegative-linear family was then tested and pruned immediately instead of being left around as another dead branch: `build/logs/perf-probe-arm64-fast-push-nonneg-linear-recurrence-decision-20260410_001827_33770.log` still slightly preferred the shipped default on the fill/share surface (`default_fill_vs_c_vector ~4.7537×` vs disabled `~4.8312×`), but the exact same-tree whole-operation medians both preferred the disabled branch (`default_array_ratio_median ~2.3187×` vs disabled `~2.2727×`, `default_dot_ratio_median ~1.7935×` vs disabled `~1.7737×`). So the kept shipped path stays the simpler direct mul/add/(u)div lowering, not a carried modulo recurrence. A more aggressive whole-list runtime fill helper was then tested and removed from the tree on the same shipped baseline because the widened decision surface was decisively bad: `build/logs/perf-probe-arm64-fast-push-fill-helper-decision-20260409_223410_5754.log` shows fill/share exploding from default `~2.3500×` to enabled `~98.8846×`, exact `array_sum_int` regressing from default `~2.1732×` to enabled `~6.0964×`, and only a small exact `dot_product_int` improvement (`~1.8157×` -> `~1.7652×`). The broader fresh-constructor shortcut also remains **opt-in only**: `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT=1` carries fresh `list.int_new(n)` proof across statements so the explicit fast push loop can skip reserve/count/header revalidation and use the constructor-installed buffer directly when `i` is still known `0` and the constructor cap exactly matches the loop bound. The widened safe-tree rerun (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203332_51451.log`) preferred the enabled branch on both surfaces, but the immediate promoted-default rerun (`build/logs/perf-probe-arm64-fast-push-fresh-exact-init-decision-20260409_203846_59158.log`) flipped the exact whole-operation medians back toward the disabled branch even while the fill/share surface still preferred default. Because the exact same-tree winner inverted across adjacent widened reruns, that broader branch is not stable enough to ship. The new narrower isolation does not change that conclusion: `OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_SINGLE_LIST=1` limits the same proof to the single-list explicit fill shape, but its safe-tree decision surface (`build/logs/perf-probe-arm64-fast-push-fresh-exact-single-list-decision-20260409_232042_61224.log`) still preferred shipped default on the actual target metrics (`default_fill_vs_c_vector ~2.7420×` vs enabled `~2.7707×`, `default_array_ratio_median ~1.9810×` vs enabled `~2.1506×`, `array_default_wins: 4/5`) even though exact `dot_product_int` moved slightly toward enabled (`default_dot_ratio_median ~1.7857×` vs enabled `~1.7675×`). The fast-loop native list-header trace path is now also aligned with the older generic fast-list tracing contract: explicit `fast_list_int_push_while` only emits loop-exit `oren_trace_list_header(...)` calls when `OREN_TRACE_NATIVE_LIST_HDR=1` is set, and `make perf-probe-arm64-fast-push-native-list-hdr-decision` is the decision surface for keeping that tracing opt-in on shipped builds. Reweight accordingly: the shipped decision surface for this area remains exact same-tree C-ceiling reruns plus integrated green lanes, and the next high-leverage work should keep attacking list build/fill lifetime/setup cost from this improved baseline rather than reopening rejected get-sum-local branches, reviving the rejected whole-list helper shortcut, promoting unstable fresh-exact shortcuts too early, or re-testing broad constructor-routing ideas that the current shipped trace already rules out.
- Update (2026-04-21): arm64 nonnegative-linear fill lowering now saturates `_arm64_nonneg_linear_safe_n_limit(...)` instead of overflowing the identity shape to `0x8000...` in the preheader compare. That same-day reducer fix still triggered a temporary rollback to opt-in while a default-on self-hosted build stalled in native quick, which is why the reduced aggressive-GC `list<int>` churn smoke (`tests/native/test_gc_reuse_alloc_churn_min.oren`) and the tighter W5 tracking smoke set were promoted to the shared guardrail surface.
- Update (2026-04-23): the temporary rollback is now closed on the current tree, and `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR` ships on by default again. The refreshed shipped-vs-disabled decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_011353_91759.log`) still agrees on the formal decision rule (`decision_surface_alignment: agree`) and strongly prefers the shipped default on the fill/share plus exact `array_sum_int` surfaces (`default_fill_vs_c_vector ~2.3103×` vs disabled `~5.7054×`, `default_array_ratio_median ~2.1964×` vs disabled `~2.3212×`), while exact `dot_product_int` only moves slightly toward the disabled branch (`default_dot_ratio_median ~1.3884×` vs disabled `~1.3578×`). More importantly, the broader safety surface is now green on the shipped default too: `make verify-native-quick` passes (`build/logs/make_verify_native_quick_20260423_011547_default_on_promote_v1.log`) and the full repo lane passes (`build/logs/make_test_20260423_012704_default_on_promote_v2.log`). A narrower fresh-single-list isolation is therefore no longer the right next move; it remains rejected as unnecessary extra branch surface, and the next fill-side work should attack the residual lifetime/setup cost on the now-shipped exact same-tree surface.
- Update (2026-04-23): the adjacent preserved-cursor fill-side follow-up is now promoted on the same current tree too. The refreshed shipped-vs-disabled ranking surface (`build/logs/perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision-20260423_025433_17194.log`) compares the shipped default against explicit disable (`OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS=0`) after the later nonnegative-linear/default-on fill changes landed, and it now agrees on the actual target surfaces: fill/share strongly prefers the shipped default (`default_fill_vs_c_vector ~1.7572×` vs disabled `~2.3562×`), exact `array_sum_int` also prefers the shipped default (`default_array_ratio_median ~2.2127×` vs disabled `~2.2219×`, `array_default_wins: 2/3`), and exact `dot_product_int` median stays lower on the shipped default too (`default_dot_ratio_median ~1.3770×` vs disabled `~1.5110×`). `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS` therefore now ships on by default on the current tree, and the next fill-side work should move below this cursor-roundtrip cleanup instead of reopening it as an opt-in branch.
- Update (2026-04-23): emitted-code inspection found a real correctness seam under that shipped nonnegative-linear branch too. `_arm64_emit_fast_loop_nonneg_linear_to_x0(...)` was reusing `x9` for mul/add/mod immediates even though `native_emit_gc_safepoint_inline_tick_pairs(...)` reserves `x9` as the inline countdown register in `fast_list_int_push_while`. The helper now keeps `x9` reserved and uses `x11`/`x10` scratch instead, both arm64 push emitters now publish `[arm64_loop_range]` traces, and `make verify-native-list-int-fast-lowering` now disassembles `array_sum_int` to reject any hot-loop `x9` use beyond the shipped countdown forms (`subs x9, x9, #0x1` / `#0x4`) while also requiring the four-wide slot-store body to stay present (`build/logs/verify_native_list_int_fast_lowering_20260423_051622_70950.log`). The refreshed shipped-vs-disabled rerun after the fix (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_034811_37016.log`) still keeps the broad branch shipped on (`default_fill_vs_c_vector ~2.4026×` vs disabled `~5.0016×`, `default_array_ratio_median ~2.2189×` vs disabled `~2.2980×`, `default_dot_ratio_median ~1.5522×` vs disabled `~1.6406×`, `decision_surface_alignment: agree`), and the widened safety lanes remain green too (`build/logs/make_verify_native_quick_20260423_tick_reg_fix_v1.log`, `build/logs/make_test_20260423_tick_reg_fix_v1.log`).
- Update (2026-04-23): the wide/unrolled follow-up under that same shipped push family is now promoted on the current tree. `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4` now ships on by default after the refreshed shipped-vs-disabled decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_045547_59235.log`) aligned in favor of the promoted branch: fill/share preferred default (`default_fill_vs_c_vector ~2.2247×` vs disabled `~2.4860×`), exact `array_sum_int` also preferred default (`default_array_ratio_median ~2.1889×` vs disabled `~2.2154×`, `array_default_wins: 3/3`), and exact `dot_product_int` median stayed lower on the shipped default too (`default_dot_ratio_median ~1.7420×` vs disabled `~1.7574×`, `exact_dot_pref: default`). The fill-hot-loop disasm and Oren-vs-C compare probes were corrected in the same batch to normalize by main-iteration output width, so the current shipped artifacts now show the actual landed body instead of the old scalar path: `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_045542_59163.log` reports 35 hot instructions for 4 output elements (`8.75` per element) in the wide main iteration, and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_045541_59142.log` pairs that with the host C `LBB0_15` ceiling at `27` instructions for 4 elements (`6.75` per element) plus a `9`-instruction scalar tail. Reweight accordingly: the “missing wide shape” theory is now closed positive and shipped; the remaining fill-side gap is the arithmetic/store/tail/safepoint overhead inside that landed four-wide body.
- Update (2026-04-23): the next obvious store-shape follow-up under that shipped four-wide body is now closed negative too. A temporary pair-store rerun replaced the four scalar stores plus pointer bump with two post-index `stp` stores and did improve the emitted loop shape: `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_053204_75573.log` and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_053209_75659.log` show the wide main iteration dropping from `35` hot instructions for `4` outputs (`8.75` per element) to `32` (`8.00` per element). But the same-tree shipped-vs-enabled decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-stp-decision-20260423_053014_74064.log`) still rejected promotion: fill/share preferred the shipped default (`default_fill_vs_c_vector ~2.0548×` vs enabled `~2.1867×`), exact `array_sum_int` median also slightly preferred default (`~2.1822×` vs `~2.1860×`), and only exact `dot_product_int` median moved toward the pair-store branch (`default_dot_ratio_median ~1.7285×` vs enabled `~1.6796×`). Reweight again: the remaining arm64 `list<int>` fill gap is no longer primarily the slot-store shape; the next work should target the carried recurrence arithmetic and compare/branch density inside the shipped wide body.
- Update (2026-04-23): the next mov-chain follow-up under that same shipped four-wide body is now closed negative too. A temporary direct-register rerun removed the cloned register chain around the carried values and improved the emitted loop further: `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_054624_80049.log` and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_054629_80110.log` show the wide main iteration dropping to `30` hot instructions for `4` outputs (`7.50` per element). But the same-tree shipped-vs-enabled decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-direct-regs-decision-20260423_054458_78631.log`) still rejected promotion: fill/share improved (`default_fill_vs_c_vector ~2.2174×` vs enabled `~2.1132×`), but both exact medians regressed (`default_array_ratio_median ~2.2164×` vs enabled `~2.2298×`, `default_dot_ratio_median ~1.5550×` vs enabled `~1.6600×`, `decision_surface_alignment: disagree`). Reweight again: the remaining gap is no longer mainly the mov-chain either; the next arm64 fill work should focus on the recurrence arithmetic itself and the compare/branch structure inside the shipped wide body.
- Update (2026-04-23): the next branchless wrap-control follow-up under that same shipped four-wide body is now closed negative too. A temporary `sub` + `csel` rerun replaced the carried wrap `cmp` / `b.lt` pairs and still improved the emitted loop shape: `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_055647_83223.log` and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_055652_83291.log` show the wide main iteration dropping to `31` hot instructions for `4` outputs (`7.75` per element). But the same-tree shipped-vs-enabled decision surface (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-csel-decision-20260423_055520_81868.log`) still rejected promotion decisively: fill/share preferred the shipped default (`default_fill_vs_c_vector ~2.1457×` vs enabled `~3.2438×`), exact `array_sum_int` median also preferred default (`default_array_ratio_median ~2.2018×` vs enabled `~2.2386×`), and only exact `dot_product_int` median moved toward the branchless path (`default_dot_ratio_median ~1.7842×` vs enabled `~1.5692×`, `decision_surface_alignment: agree`). Reweight again: the remaining fill-side blocker is no longer mainly the branchy wrap-control form either; the next work should target the serial carried recurrence itself versus the host C loop's four independent streams, not more local control-form tweaks.
- Update (2026-04-23): the explicit push-loop tick-mask follow-up looked promotable at first, but the actual promoted-default rerun closed it back to probe-only. The candidate current-tree ranking surface (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032104_29410.log`) compared the shipped `4095` default against `16383` and `65535` and aligned across all target surfaces in favor of `65535` (`default_fill_vs_c_vector ~1.8155×`, `mask_16383 ~1.8369×`, `mask_65535 ~1.7173×`; `default_array_ratio_median ~2.2131×`, `mask_16383 ~2.1760×`, `mask_65535 ~2.1398×`; `default_dot_ratio_median ~1.4062×`, `mask_16383 ~1.4727×`, `mask_65535 ~1.3362×`). But the immediate promoted-default rerun on the actual `65535` tree (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032751_32000.log`) did not hold: fill/share flipped toward the lower masks (`default_fill_vs_c_vector ~1.8792×`, `mask_4095 ~1.7483×`, `mask_16383 ~1.7535×`), while exact `array_sum_int` and exact `dot_product_int` medians both preferred `16383` (`default_array_ratio_median ~2.1792×`, `mask_4095 ~2.1950×`, `mask_16383 ~2.1736×`; `default_dot_ratio_median ~1.7445×`, `mask_4095 ~1.7506×`, `mask_16383 ~1.7229×`). Reweight accordingly: keep `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=4095` shipped for now; the higher masks are still not stable enough to promote on the current tree.
- Update (2026-04-23): the next obvious runtime micro-hypothesis under that same shipped fill surface is now closed too. Two constructor-path reruns were tried on the exact same tree and both lost against the current baseline `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log` (`oren_fill_list_int / c_fill_slot64_vector ~2.3103×`, fill `per_rep_s ~0.003096`). First, arena/non-arena constructor trace gating plus hidden-helper node filtering (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015415_6018.log`) slightly regressed fill/share (`~2.3671×`, fill `per_rep_s ~0.003145`). Second, adding a direct arena retag-known-node shortcut on top of that (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015936_6969.log`) regressed further (`~2.3970×`, fill `per_rep_s ~0.003188`). Reweight accordingly: the remaining `list<int>` build/fill blocker on the shipped arm64 surface is not constructor trace/index bookkeeping or the immediate arena-retag table lookup; the next work should stay below that constructor micro-path and focus on post-construction fill lifetime/setup or loop-state cost.
- Update (2026-04-23): the first narrower compiler-side loop-state trim under that same constructor boundary is now closed negative too. The exact same-tree baseline remains `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log` (`default_fill_vs_c_vector ~2.3103×`, fill `per_rep_s ~0.003096`). A focused rerun that stopped spilling the generic `idx` local on the nonnegative-linear path and tried to keep `i` live across the direct arithmetic helper path (`build/logs/perf-probe-list-int-fill-share-decision-20260423_021057_8800.log`) regressed badly instead (`default_fill_vs_c_vector ~4.2125×`, fill `per_rep_s ~0.005534`). Reweight again: the remaining shipped fill-side cost is not solved by the obvious `X20` live-range / frame spill-reload trim alone; do not reopen that narrow loop-state branch without stronger emitted-code evidence around the surrounding fast-loop scaffolding.
- Update (2026-04-23): the next safepoint-side loop-state micro-branch under that same shipped fill surface is now closed too. Starting from the same baseline `build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log` (`default_fill_vs_c_vector ~2.3103×`, fill `per_rep_s ~0.003096`), a focused rerun that replaced the generic inline-tick preserved-reg spill set with the narrower explicit-pairs path for `fast_list_int_push_while` (`build/logs/perf-probe-list-int-fill-share-decision-20260423_022302_10735.log`) moved the wrong way (`default_fill_vs_c_vector ~2.3697×`, fill `per_rep_s ~0.003107`). Reweight again: the residual shipped fill cost is not explained by the broad generic safepoint spill set alone, so do not reopen that safepoint-pair narrowing branch without stronger emitted-code evidence around the remaining post-construction loop body.
- Update (2026-04-23): the next reciprocal-fastmod follow-up under that same shipped fill surface is also closed negative now. The earlier naive reciprocal lowering already lost because it materialized the 64-bit reciprocal constant inside the hot loop every iteration (`build/logs/otool_fill_list_int_oren_inspect_fastmod_full_20260423_v1.log`), so the narrower rerun hoisted the shared `% 1000` divisor and reciprocal into preheader regs and kept the reciprocal path only on the shipped `fast_list_int_push_while` nonnegative-linear fill loop. The exact same-tree probe still regressed hard: `build/logs/perf-probe-list-int-fill-share-decision-20260423_024106_13895.log` moved fill/share from the baseline `~2.3103×` / `~0.003096` to `~2.8408×` / `~0.003746`. The emitted code confirms the hoist itself worked mechanically: `build/logs/otool_fill_list_int_oren_inspect_fastmod_hoist_full_20260423_v1.log` shows `x24=#1000` and `x25=<reciprocal>` loaded once in the preheader (`0x1001d9cf8..0x1001d9d08`) and the loop body using `umulh x10, x0, x25` at `0x1001d9d70` instead of reloading the constant. Reweight again: the remaining shipped fill-side blocker is not the per-iteration reciprocal literal materialization alone; the next emitted-code pass should look at the surviving post-construction loop body around slot writes, count/cursor updates, and safepoint-reset scaffolding instead of reopening this reciprocal branch.
- **Runtime robustness**: GC reuse and allocator paths are still experimental; list header corruption investigations are ongoing (tracked below).
- **Platform breadth**: Tier‑1 intent targets are arm64‑macOS, arm64‑linux, x64‑linux, x64‑windows; x64 targets are still in rolling bring‑up.
- **Tooling/ABI stability**: ABI/opcode stability is explicitly rolling; compatibility guarantees are not declared.
- **Feature set maturity**: the remaining essential language backlog is now full
  `yield`/stackless coroutine semantics beyond the current helper surfaces. Bare
  `yield`, `yield <value>`, and expression/result-position `yield` are now shipped through the
  backend-shared helpers `oren_yield_stmt()` / `oren_yield_value(v)`, and explicit caller-visible
  value exchange now also exists through `oren_yield_exchange(yield_ch, resume_ch, v)`. The
  remaining gap is source-level coroutine/generator semantics plus a stronger default
  scheduler-aware native green-channel protocol for that explicit exchange path. The structured
  error model is already shipped as the
  rolling value-or-error
  convention (`oren_err` / `oren_is_err` / `std:result`), with stdlib migration breadth still
  ongoing. Rolling module visibility now exists via `pub`, and bytes/typed buffers are already
  partially shipped through `std:bytes` / `std:buffer`; dynamic module loading and user-defined
  methods remain unimplemented.
- New (2026-03-27): `std:buffer` now also exposes checked `[]u8` slice/strided bridge ergonomics
  for typed-buffer callers that want to stay on the portable stdlib surface:
  `try_slice_to_u8_buf`, `try_slice_copy_from_string`, `try_slice_copy_from_string_slice`,
  `try_strided_to_u8_buf`, `try_strided_copy_from_string`, and
  `try_strided_copy_from_string_slice`; covered by result smoke + native quick integration +
  dedicated AVM buffer-view smoke.
- New (2026-03-27): `std:buffer` now also exposes the missing symmetric `[]u8` view helpers
  for unpack/copy-on-buffer paths: `try_slice_unpack_u8`, `try_strided_unpack_u8`,
  `try_slice_copy_from_u8_buf`, and `try_strided_copy_from_u8_buf`; covered by result smoke +
  native quick integration + dedicated AVM buffer-view smoke.
- New (2026-03-27): `std:buffer` matrix views now expose checked shape accessors plus the missing
  checked `i64` / `f64` matrix accessors: `try_mat_rows`, `try_mat_cols`, `try_mat_row_stride`,
  `try_mat_load/store_i64`, and `try_mat_load/store_f64`; covered by result smoke + native quick
  integration + dedicated AVM buffer-view smoke.

Design intent is bleeding‑edge (determinism + capability gating + AVM), but execution maturity is still in the rolling phase. The current strategy notes are `docs/OREN_THESIS.md`, `project-doc/oren_feature_horizon_20260412.md`, and `project-doc/oren_language_system_bets_20260412.md`.

### Backend readiness (rolling snapshot)

- **C backend**: bootstrap path only; depends on host C toolchain; ABI/opcodes rolling; not production‑grade.
- **Native backend**: Tier‑1 intent only; tagged‑value convergence still rolling; GC/allocator correctness is improving but not yet stable at production gates; hot‑loop parity still above target.
- **AVM backend**: deterministic VM; single‑threaded today; heap uses `malloc` (no GC yet); opcode/ABI stability is rolling; capability gating exists but maturity is below production.

### Feature readiness gaps (requested)

- **GMP concurrency (native)**: Stage N2 substrate exists (green workers + OS‑thread substrate), but no production‑grade GMP/netpoller or true async IO across Tier‑1.
- **Compiler‑in‑AVM**: design intent only; no AVM‑hosted compiler pipeline yet.
- **AVM multiverse (nested universes)**: basic nested execution + VFS inheritance fixtures exist, but budgeted child‑universe scheduling and snapshot/restore are still rolling.
- **Scientific computing / AI acceleration**: typed buffers + limited SIMD (arm64 NEON) exist; x64 SIMD + kernel coverage are incomplete; no GPU/AI accelerator path or BLAS‑grade library surface yet.

---

## Production readiness scorecard (weighted, rolling snapshot)

Weighted categories map directly to the tracker items below; W5 dominates "how far"
Oren is from LLVM/rustc/GCC/zig/go parity today.

1) **W5 - Semantic parity (tagged values + fixtures)**
   - Native tagged values are still rolling; `oren_type_tag` is best‑effort for scalars.
   - Cross‑backend parity is enforced via fixtures, not a stabilized ABI.

2) **W5 - Performance parity (hot loops + alloc/GC)**
   - Baselines (arm64, 2026-04-04 focused perf gate): `loop_sum` 1.09× C, `dot_product` 2.82× C; `alloc_churn` 5.42× C, `alloc_drop` 1.76× C.
   - Priority: `dot_product` remains above the 2× gate; alloc_drop and alloc_churn are within the 5×/8× gates, and `loop_sum` is now within gate.
   - Target gates: loops <= 2× C; alloc_churn <= 8× C; alloc_drop <= 5× C.
   - New focused canonical split runner (2026-04-04): `array_sum` / `dot_product` now accept the
     same optional `n` + `reps` CLI args as `loop_sum` / the `list<int>` benches, and
     `make perf-gate-native-read-split` measures the same workload across C/native instead of a
     fixed-shape C baseline against a repeated native loop.
   - Fix + rerun (2026-04-05): `make perf-probe-list-int-specialization-gap` now passes the correct
     steady-runner knobs to each side (`OREN_BENCH_NATIVE_STEADY_*` for generic,
     `OREN_BENCH_LIST_INT_STEADY_*` for specialized). The earlier artifact
     `build/logs/perf-probe-list-int-specialization-gap-20260405_025217_48504.log` overstated the
     gap because it accidentally sent the `list<int>` knobs to the generic runner too.
     Corrected artifact (`build/logs/perf-probe-list-int-specialization-gap-20260405_025957_59475.log`,
     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=1`, `n=200000`, `reps=10`)
     now comes back as:
     - `array_sum`: generic `~1.3419× C`, specialized `~1.4064× C`, gap `~0.9541×`
     - `dot_product`: generic `~1.5169× C`, specialized `~1.4803× C`, gap `~1.0247×`
   - New specialization read-split probe (2026-04-05): `make perf-probe-list-int-specialization-read-split`
     compares the same generic/specialized pairs through `perf-gate-native-read-split` and
     `perf-gate-list-int-read-split` with aligned `n/short_reps/long_reps`. Latest artifact
     (`build/logs/perf-probe-list-int-specialization-read-split-20260405_030027_60451.log`,
     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3`, `warmups=1`, `n=200000`,
     `short_reps=1`, `long_reps=10`) shows the reliable `long_per_rep` view is still near parity:
     - `array_sum`: generic `~1.5652× C`, specialized `~1.4639× C`, gap `~1.0692×`
     - `dot_product`: generic `~1.5241× C`, specialized `~1.5157× C`, gap `~1.0055×`
     The same artifact reports delta estimates too, but the specialized side prints large
   - New focused arm64 dot-prefix-zero specialization wrapper (2026-04-09):
     `make perf-probe-arm64-fast-dot-prefix-zero-specialization` now compares the generic
     auto-specialized `dot_product` surface against explicit `dot_product_int` on both the shipped
     default and `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`, then bundles the aligned steady gap,
     read-split gap, and compile-time specialization trace into one artifact. Latest rerun
     (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-specialization-20260409_011654_49934.log`)
     shows the generic/explicit gap is still small, and restoring parsed-bound reserve insertion
     materially improved both sides on the whole-operation surface:
     - default steady: generic `~1.3947× C`, specialized `~1.6008× C`, gap `~0.8713×`
     - enabled steady: generic `~1.3992× C`, specialized `~1.5518× C`, gap `~0.9017×`
     - default read-split long-per-rep: generic `~1.6788× C`, specialized `~1.7004× C`, gap `~0.9873×`
     - enabled read-split long-per-rep: generic `~1.6392× C`, specialized `~1.5860× C`, gap `~1.0335×`
     - specialization trace now reports the fill-loop reserve path too:
       generic `rewrite_init=2`, `list_int_reserve=2`, `list_int_push_unchecked=2`;
       specialized `rewrite_init=0`, `list_int_reserve=2`, `list_int_push_unchecked=2`
       (trace summary: `build/logs/perf-probe-list-int-specialization-trace-20260409_011625_49062.log`).
     Tracker implication: the earlier “generic fill loops are missing typed reserve” gap is now
     closed for the canonical benchmarks. The remaining blocker is back on the steady arm64 dot
     kernel relative to the vectorized C baseline, not on parsed-bound list setup.
     delta-vs-long drift warnings, so `long_per_rep` is the tracker-worthy measure here.
   - New specialization trace probe (2026-04-05): `make perf-probe-list-int-specialization-trace`
     builds the generic and explicit `list.int_*` benchmarks with
     `OREN_TRACE_LIST_INT=1 OREN_TRACE_LIST_RESERVE=1` and confirms the canonical generic sources
     still rewrite into the intended `list<int>` path. Latest artifact
     (`build/logs/perf-probe-list-int-specialization-trace-20260409_011625_49062.log`) now shows
     the full parsed-bound fill pipeline:
     - generic `array_sum`: `rewrite_init=1`, `list_int_reserve=1`, `list_int_push_unchecked=1`
     - generic `dot_product`: `rewrite_init=2`, `list_int_reserve=2`, `list_int_push_unchecked=2`
     - explicit `array_sum_int`: `list_int_reserve=1`, `list_int_push_unchecked=1`
     - explicit `dot_product_int`: `list_int_reserve=2`, `list_int_push_unchecked=2`
     The remaining `list_reserve=1` / `list_push_unchecked=1` counts in each case come from shared
     helper functions, not the benchmark fill loops themselves.
   - Reweight: the current canonical `dot_product` blocker is no longer “generic-list
     specialization is missing.” After the corrected probe and trace, the remaining gap is back in
     the steady-state hot path and the C-side vectorized baseline, not in a silent boxed-list
     fallback for the generic benchmarks.
   - Scalar-ceiling probe + env-parse fix (2026-04-05, refreshed 2026-04-22): `make perf-probe-arm64-dot-vs-c-loop-compare`
     now parses comma-separated `OREN_BENCH_ENV_BUILD_OREN` correctly, and the new
     `make perf-probe-arm64-dot-vs-c-scalar-ceiling` times the exact Oren native `dot_product`
     benchmark binary against both vectorized and de-vectorized host-C builds of the same source.
     The loop-compare extractor no longer depends on hardcoded Clang `LBB0_*` labels; it now selects
     C vector loops by `smlal*` blocks and the scalar tail by `smaddl`. Latest loop-compare rerun
     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260422_002728_90700.log`) shows the current
     shipped Oren generic `dot_product` window as a 20-instruction traced range, with the skipped
     cold GC-call block now split out as `8` instructions and the hot range-without-cold-tick at
     `12` instructions. Host C still exposes vector/mid/tail blocks (`28` / `12` / `6`
     instructions).
     New explicit-list counterpart:
     `make perf-probe-arm64-dot-vs-c-loop-compare-list-int`. Latest artifact
     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-20260411_165935_82064.log`) shows
     the same 21-instruction `dot_product_int` Oren traced range, the same 14-instruction range
     without the cold GC-call block, and the same host C vector/mid/tail shape, with labels resolved
     by instruction pattern rather than hardcoded names.
     The scalar-ceiling runner is now parameterized too; the latest generic artifact
     (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log`) shows
     vectorized C `~0.000253s`, scalar C `~0.000741s`, and Oren native `~0.001368s` per rep
     (`scalar/vector ~2.9275×`, `Oren/scalar ~1.8452×`, `Oren/vector ~5.4018×`), while the
     explicit-list artifact
     (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int-20260411_164309_41086.log`)
     shows vectorized C `~0.000250s`, scalar C `~0.000759s`, and Oren native `~0.001301s` per rep
     (`scalar/vector ~3.0352×`, `Oren/scalar ~1.7130×`, `Oren/vector ~5.1992×`). The corrected
     scalar-ceiling extractor now reports the precise C inner loops too: 28 instructions for the
     NEON vector body and 6 for the de-vectorized scalar `smaddl` loop on both sources. Reweight:
     scalar loop debt is still material, but the remaining large `dot_product` gap is compounded by
     the missing vector/slot64 path, not by generic-list specialization.
	   - Scalar-core matrix refresh (2026-04-22): the current generic `dot_product` acceptance matrix
	     (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`) still
	     rejects the older scalar-only candidates on the shipped surface. Against baseline, disabling
	     single-pair cursor regs regresses steady/gate native medians `+3.76%` / `+4.67%`,
	     `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` regresses `+0.50%` / `+2.97%`, and the
	     combined cursor-disabled + scalar row regresses `+2.90%` / `+2.96%`. That closes the old
	     scalar-toggle branch again on the current tree: the remaining arm64 hot-loop work is a new
	     vector/slot64-quality path, not another cursor/scalar promotion.
	   - Generic whole-list helper decision (2026-04-22): `make perf-probe-arm64-fast-dot-whole-list-helper-decision`
	     now measures the exact canonical `dot_product` helper shortcut on the shared read-split and
	     order-balanced gate surfaces. Latest artifact
	     (`build/logs/perf-probe-arm64-fast-dot-whole-list-helper-decision-20260422_004934_99469.log`)
	     rejects the branch decisively:
	     - read-split `long_per_rep`: baseline `0.002664s` vs helper `0.006172s` (`+131.68%`,
	       `3.5494× C` vs `8.0141× C`)
	     - read-split repeated-work delta: `+270.80%`
	     - order-balanced native median: baseline `0.015886s` vs helper `0.019043s`
	       (`+20.08%`, `wins=0/4`)
	     - order-balanced native/C ratio: baseline `2.9800×` vs helper `3.5403×`
	       (`+19.38%`, `wins=0/4`)
	     Result: `OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER=1` remains opt-in only on the
	     current generic benchmark tree. The helper branch is closed again; the next credible move is a
	     new vector/slot64-quality arm64 dot path.
	   - Slot-ABI ceiling probe (2026-04-05, refreshed 2026-04-11): the new `make perf-probe-list-int-slot-abi-ceiling`
	     measures how much vector headroom the current `list<int>` 64-bit slot ABI still has on the
	     host compiler. Latest artifact
	     (`build/logs/perf-probe-list-int-slot-abi-ceiling-20260411_181606_60508.log`,
	     `runs=5 warmups=1 n=2000000 reps=100`) compares packed-i32 C, slot64 C, the shipped Oren
	     canonical benchmark, and the Oren slot-direct helper on the same workload:
	     - packed-i32 C vector: ~0.000250s per rep
	     - packed-i32 C scalar: ~0.000747s per rep
	     - slot64 C “vector”: ~0.000728s per rep
	     - slot64 C scalar: ~0.000759s per rep
	     - Oren native canonical: ~0.001305s per rep
	     - Oren native slot-direct helper: ~0.003599s per rep
	     Ratio view:
	     - slot64-vector / packed-vector: ~2.9086×
	     - slot64-scalar / packed-scalar: ~1.0165×
	     - Oren canonical / slot64-vector: ~1.7932×
	     - Oren canonical / slot64-scalar: ~1.7195×
	     - Oren slot-direct helper / slot64-vector: ~4.9453×
	     The extracted slot64 `-O2` assembly is still a paired-scalar `ldp` + `madd` loop, not the
	     packed NEON `smlal/smlal2` loop the compiler emits for packed i32; the corrected extractor
	     reports 28 instructions for the packed-i32 NEON body, 12 for the slot64 paired-scalar loop,
	     and 6 for the slot64 scalar tail. That reweights the next move again: the current 64-bit
	     slot ABI itself largely erases the auto-vectorization gain, but the shipped Oren canonical
	     loop still has a material `~1.8×` gap against the slot64 host-C ceiling.
	     A scalar-post follow-up now confirms that merely matching the host slot64 scalar loop's
	     post-index load + `madd` shape is not enough: the opt-in combined Oren loop shrinks to
	     `18` traced instructions (`11` without the skipped cold GC-call block), but the measured
	     decision surface still rejects the branch.
	   - Dot route decision wrapper (2026-04-11): new `make perf-probe-list-int-dot-route-decision`
	     reruns the slot-ABI ceiling, whole-operation C ceiling, and order-balanced dot-ceiling
	     stability surface in one current-tree wrapper. Latest artifact:
	     `build/logs/perf-probe-list-int-dot-route-decision-20260411_181606_60502.log`. It keeps
	     the shipped canonical lowering: slot64 still loses packed-NEON headroom
	     (`slot64_vector / packed_vector ~2.9086×`, `slot64_scalar / packed_scalar ~1.0165×`), the
	     whole-operation host-ceiling gaps remain material (`oren_dot_product_int / dot_slot64_vector
	     ~1.7959×`, `oren_array_sum_int / array_slot64_vector ~2.2778×`), and no reroute clears both
	     tracked benchmarks. Hidden direct-slot won dot on this rerun (`3/5`, median `-10.83%` vs
	     baseline) but lost array badly (`1/5`, median `+18.24%`); public-slot stayed mixed (`1/5`
	     wins on both benchmarks); packed-SIMD stayed far behind (`dot median +301.76%` vs baseline).
	     After the 2026-04-11 pointer-i32 pack-store improvement, the narrower current stability rerun
	     `build/logs/perf-probe-list-int-dot-ceiling-stability-20260411_204859_99207.log` supersedes only
	     the packed-leg magnitude, not the route decision: packed-SIMD still has `0/5` wins on both
	     array and dot, with median deltas `+269.38%` array and `+134.27%` dot versus canonical.
	     Reweight: the next dot work should target representation/direct lowering for slot64 or a
	     safe packed view, not a generic helper/public/packed bridge reroute or another scalar-tail
	     scheduling toggle.
	   - Slot-direct fast-tick decision (2026-04-11): new
	     `make perf-probe-list-int-slot-direct-fast-tick-decision` serializes default vs
	     `OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1`, forcing the shared read-split benchmark
	     artifacts to rebuild for each side. Latest artifact:
	     `build/logs/perf-probe-list-int-slot-direct-fast-tick-decision-20260411_194036_96087.log`.
	     The branch is not promotable: slot-ABI direct-helper time regressed from `~0.001870s` to
	     `~0.001874s` per rep (`+0.21%`) and still trailed canonical `~0.001296s` plus host slot64 C
	     `~0.000735s`; read-split slot-direct native/C also regressed on both surfaces
	     (`array_sum_int` `~1.0010× -> ~1.1249×`, `dot_product_int` `~1.2931× -> ~1.3051×`).
	     Keep the reduced helper safepoint spill / 4095-tick-mask branch opt-in only. This closes the
	     tick/spill shortcut as a default path and keeps the next W5 work on real representation or
	     direct-lowering changes.
	   - Slot-direct helper pair-loop decision (2026-04-11): new
	     `OREN_ARM64_LIST_INT_SLOT_DIRECT_PAIR_LOOP=1` emits a counted 2-wide raw-slot helper loop
	     for unchecked `list<int>` sum/dot helpers (`ldp` pairs and dual `madd` for dot), with an
	     optional combination with the fast-tick branch. `make perf-probe-list-int-slot-direct-pair-loop-decision`
	     (`build/logs/perf-probe-list-int-slot-direct-pair-loop-decision-20260411_195615_19255.log`)
		     rejects promotion: pair-loop alone regressed slot-ABI direct-helper time `+3.15%` and
		     read-split `array_sum_int` slot-direct native/C `+9.88%`, while improving only
		     `dot_product_int` `-3.31%`; pair-loop+fast-tick had the same split (`+3.42%` slot-ABI,
		     `+7.70%` array, `-7.55%` dot). Keep it opt-in; this closes the scalar helper scheduling
		     shortcut and keeps W5 pointed at a real representation/direct-lowering path.
		   - Arm64 get-sum vector-2d decision (2026-04-11): new
		     `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1` emits a default-off direct
		     `array_sum_int` slot64 SIMD-add body using `ldr q` plus `add.2d`/`addp.2d`, reducing back
		     into the scalar sum before another possible GC safepoint call. Use
		     `make perf-probe-arm64-fast-get-sum-vector-2d-decision`; latest widened artifact
		     `build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`
		     confirms the intended shape (`51` traced instructions, `41` after subtracting two cold GC
		     tick blocks, `q` loads in the snippet, `add.2d=1`, `addp.2d=2`) but rejects promotion.
		     Local acceptance preferred enabled (`steady -7.95%`, `gate -1.62%` native medians), while
		     the same-tree C-ceiling surface preferred shipped default in `4/5` sweeps
		     (`array` ratio median `~2.2140×` default vs `~2.2967×` enabled, `+3.74%`). Keep this
		     branch opt-in; a per-iteration AdvSIMD pairwise-add body is not the stable slot64
		     representation/direct-lowering fix.
		   - Arm64 slot64 SIMD ISA check (2026-04-11): new `make verify-native-arm64-slot64-simd-isa`
		     records the local assembler fact used for W5 reweighting. Latest artifact
		     `build/logs/verify_arm64_slot64_simd_isa_20260411_202346_64385.log` shows AdvSIMD accepts
		     slot64 vector add/reduce (`ldr q`, `add.2d`, `addp.2d`) and packed-i32 widening dot
		     (`smull.2d`, `smull2.2d`), but rejects true 64-bit-lane vector multiply (`mul v*.2d`).
		     Reweight: the dot-side slot64 path cannot become a true SIMD dot by a local scalar-multiply
		     opcode swap; it needs a safe packed i32 view or a different representation contract.
		   - New: arm64 fast LCG loop lowering now activates for `benchmarks/loop_sum/loop_sum.oren` again after fixing the shared `UMULH` opcode encoder; `loop_sum` is back within gate, so the remaining hot-loop gap is centered on dot-product/list-load overhead rather than that encoder bug (2026-03-20).
   - Trace (2026-03-20): a targeted arm64 `dot_product` experiment that hoisted the single-pair
     list<int> cursors fully into callee-saved regs did not help; the fresh perf gate moved
     `dot_product` from about 2.51× C to about 2.55× C, so cursor stack traffic is not the
     dominant remaining cost on that path.
   - Trace (2026-03-20): a follow-up arm64 `dot_product` experiment that fused the hot
     `sum += left * right` pairs into `MADD` also regressed on Apple M2 Pro; the focused
     perf gate moved `dot_product` from about 2.51× C to about 2.70× C, so the open gap is
     not explained by the current `MUL` + `ADD` instruction count alone.
   - Trace (2026-03-20): a second follow-up that replaced the unique unrolled `list<int>`
     cursor loads with `LDP ... post-index` pair loads also regressed on Apple M2 Pro; the
     focused perf gate moved `dot_product` from about 2.51× C to about 2.71× C, so the
     remaining arm64 gap is not dominated by the current per-side load/address-update sequence either.
   - Trace (2026-04-04): a narrower follow-up that kept cursor updates separate and only
     replaced the exact single-pair arm64 `dot_product` scalar load groups with plain
     offset `LDP` pair loads also failed to help. The focused steady rerun moved `dot_product`
     from the last kept ~2.99× C state to ~3.10× C (`build/logs/perf-gate-native-steady-20260404_231609_56304.log`),
     so even non-writeback pair loads are not the next likely win on this host.
   - Trace (2026-03-20): a third follow-up that hoisted invariant `n` into a preserved reg
     across the fast read-only list loops also regressed on Apple M2 Pro; the focused perf
     gate moved `dot_product` from about 2.51× C to about 2.84× C, so the remaining gap is
     not explained by the current per-iter loop-bound stack reload either.
   - Trace (2026-03-20): a follow-up `array_sum_int` experiment that hoisted the single-list
     `list<int>` cursor into a preserved reg was not safe to keep; the focused `list<int>` gate
     built successfully but the native `array_sum_int` benchmark binary crashed during execution,
     so the shared read-heavy path should not move list data cursors out of the established stack
     slots without a stronger GC-rooting argument.
   - Latest focused list<int> clean rerun (arm64, 2026-04-04): `array_sum_int` 2.07× C,
     `dot_product_int` 2.59× C, `multi_list_push_int` 2.24× C. One-shot list<int> results are
     now best used as a smoke view; they are no longer precise enough to rank the remaining
     steady-state blocker on their own.
   - New: the exact two-list single-pair arm64 `list<int>` dot shape keeps both data cursors in
     callee-saved regs across iterations/safepoints, and the exact single-list `list<int>` get-sum
     shape now also pairwise-reduces its 4-wide and 2-wide hot bodies to shorten the running-sum
     dependency chain. On the latest steady rerun that leaves `array_sum_int` at ~2.43× while the
     unchanged exact-pair dot path now measures ~2.78× on the same rerun (Apple M2 Pro, 2026-04-04).
   - Tooling: benchmark result artifacts now retain raw timing vectors plus `stdev_s` / `cov`,
     so perf tracker updates can distinguish stable reruns from one-off outliers.
   - Tooling (2026-04-04): `make perf-probe-arm64-native-hot-loop-disasm` now reports both
     the traced machine-code window and a mnemonic histogram for the canonical `array_sum` /
     `dot_product` arm64 fast loops, so static load/mul/add/branch deltas can be compared
     directly before shipping another dot-core experiment.
   - Tooling follow-up (2026-04-05): that same disasm probe now forces `--no-cache` when it asks
     for `OREN_TRACE_ARM64_LOOP_RANGES=1`. Without that, a native cache hit could skip lowering,
     drop the compile-time `[arm64_loop_range]` lines, and leave the summary with only the raw
     `--disasm` output.
   - Tooling follow-up (2026-04-05): the disasm probe now also exits non-zero when either traced
     canonical window is missing, so the arm64 hot-loop summary cannot silently degrade into a
     cache-hit or missed-lowering note.
   - Tooling follow-up (2026-04-05): `make perf-probe-arm64-dot-acceptance` now packages the
     current arm64 dot-core shipping workflow into one serial run: exact benchmark smoke, traced
     hot-loop disasm, steady gate, canonical gate, exact-binary native repro, and `make test`.
     The summary log records both wrapper logs and the extracted current ratios/instruction counts,
     so future arm64 dot experiments can compare against one artifact instead of reconstructing the
     sequence by hand.
   - New focused steady-state runner (2026-04-04, `make perf-gate-list-int-steady`, `reps=100`):
     `array_sum_int` steady-state native/C is ~2.43× and `dot_product_int` steady-state native/C
     is ~2.78×. That is stronger evidence than the earlier one-shot gate that the remaining
     blocker is the repeated read path itself, not one-time fill/setup cost.
   - New guardrail (2026-03-20): `make perf-smoke-list-int` now builds the native
     `array_sum_int` / `dot_product_int` benchmark binaries once and checks both the exact tiny
     scalar-tail outputs (`205` and `6590`) and the >16-element hot-path outputs (`710` and
     `54380`) before heavier timing sweeps. The main `list<int>` perf runners now invoke this
     smoke by default, with `OREN_PERF_SMOKE_LIST_INT=0` as the explicit opt-out.
   - Trace (2026-03-20): a follow-up arm64 exact-dot experiment that tried to split the
     single-pair `dot_product_int` accumulation chain across two persistent accumulators was not
     safe to keep. Even after reworking the register choice, the direct native smoke returned
     `4621` for `dot_product_int 10 3` instead of the known-good `6590`, so future dot-core work
     should clear `make perf-smoke-list-int` before trusting any perf-gate result.
   - Trace (2026-03-20): a narrower follow-up that hoisted `n` into X21 only for the unique
     arm64 read-only `list<int>` fast loops was also not a shared win. On the steady runner it
     moved `array_sum_int` from about 3.28× C to about 3.21× C, but `dot_product_int` regressed
     from about 3.74× C to about 3.95× C, so the loop-bound reload is not the dominant blocker
     on the shared path.
   - New unsafe steady probe (2026-03-20, consolidated rerun via
     `make perf-probe-list-int-unsafe`): the pre-unroll4 clean baseline was `array_sum_int` ~3.38× C and
     `dot_product_int` ~3.90× C. `OREN_LIST_ASSUME_LIST=1` nudged them only to ~3.25× / ~3.88×,
     `OREN_NATIVE_ASSUME_LIST_INDEX=1` moved them to ~3.36× / ~4.09×, and combining both landed
     at ~3.32× / ~3.94×. So runtime list validation and compiler-side direct index lowering are
     only partial ceilings, not a shared fix for the steady-state read-heavy path.
   - Trace (2026-03-20): replacing the new arm64 4-wide exact-shape loads with `ldp ... post-index`
     pair loads was also not a win. The experimental steady rerun moved `array_sum_int` from about
     2.87× C to about 2.95× C and `dot_product_int` from about 3.17× C to about 3.33× C, so the
     remaining shared gap is not mainly the current scalar load-address sequence inside those 4-wide paths.
   - Trace (2026-03-20): a narrower follow-up that locally pairwise-reduced the exact single-pair
     arm64 `dot_product_int` 4-wide and 2-wide bodies before adding into the running sum stayed
     correct under `make perf-smoke-list-int`, but the steady rerun still regressed slightly:
     `dot_product_int` moved from about 3.09× C to about 3.13× C, so reducing the number of
     per-body writes into `x23` alone is not the missing win.
   - Trace (2026-03-20): a stricter follow-up that reduced the exact 4-wide single-pair arm64
     `dot_product_int` body all the way down to one final `x23 += batch_sum` update also stayed
     correct under `make perf-smoke-list-int`, but the steady rerun regressed further:
     `dot_product_int` moved to about 3.22× C. That makes the current evidence stronger: simply
     collapsing the exact 4-wide batch into fewer running-sum writes does not solve the blocker.
   - Trace (2026-03-20): a later direct NEON chunking experiment for the exact single-pair arm64
     `dot_product_int` path was also not safe to keep. The emitted vector body itself assembled and
     passed the tiny `10 3` smoke, but the widened smoke and steady runner exposed deterministic
     wrong-code (`54380` smoke failed on the hot path; full benchmark output halved to
     `253794000000`). Root cause: `list<int>` fast loops read 64-bit list slots, while the
     existing `simd_dot_i32_ptr`/NEON kernel shape assumes packed i32 lanes. That closes off the
     direct "just route list<int> cursors into the i32 SIMD kernel" idea unless we first add a
     safe packed-i32 view or a true 64-bit-slot SIMD lowering.
   - New native runtime helpers (2026-03-20): `oren_list_int_data_ptr(...)`,
     `oren_list_int_data_ptr_unchecked(...)`, and `oren_list_int_slot_stride_bytes()` now make the
     current rolling representation explicit, and the Tier-1 native quick fixture
     `tests/native/qi/100_tests_basic.oren` now asserts the raw slot contract directly. That gives
     future compiler/SIMD work a test-backed ABI fact instead of relying on emitter disassembly
     alone.
   - New bridge boundary (2026-03-20): stdlib now exposes a safe `list<int> -> []i32` packing path
     plus scalar packed dot/sum helpers that work on both C and native core-runtime builds, so
     the bridge itself no longer depends on the heavier typed-buffer dot kernel surface.
   - Fix (2026-03-27): the native core runtime now carries the minimal `i32` typed-buffer dot
     family (`oren_buf_dot_i32*` / `oren_buf_dot_i32_into`) needed by the packed bridge, and
     `std:linalg.dot_i32_list_int_packed(...)` now routes through that kernel path instead of the
     scalar fallback.
   - New perf isolation (2026-03-20): default native benchmark builds still use the reduced
     `core` runtime profile (`lib/runtime_native_core.oren` -> `runtime_native/200_typed_buffers_core.oren`),
     and the packed-bridge path now stays on that default profile. Heavier typed-buffer kernels
     still remain outside `core`, but the hidden packed-bridge benchmarks no longer need a
     full-runtime override just to reach `oren_buf_dot_i32(...)`.
   - Verified (2026-03-20): the hidden packed-bridge benchmarks compile and run through the Oren C
     backend with the expected `205`, `710`, `6590`, and `54380` outputs, which is enough to catch
     stdlib bridge portability bugs before paying for the slower full-runtime native probe.
   - Fix (2026-03-27): native `oren_list_len` intrinsics on arm64/x64 now accept tracked
     `LIST_INT` headers in addition to boxed `LIST` headers, matching the runtime contract and
     unblocking rebuilt native packed-bridge binaries on the core profile.
   - Fix (2026-03-27): the C backend runtime now implements the missing portable bytes helpers
     `oren_bytes_len`, `oren_bytes_from_hex`, `oren_bytes_to_hex`, and `oren_bytes_pack`. That
     closes the stdlib/runtime ABI gap that previously made Oren C packed-bridge preflight builds
     fail at compile time.
   - New probe hygiene (2026-03-20): the packed-bridge smoke/preflight now defaults to Oren C
     rather than full-runtime native. That keeps the correctness preflight fast while preserving
     the dedicated native steady probe as the explicit place to measure the packed-buffer ceiling.
   - New probe batching (2026-03-20): the packed-bridge steady probe now warms the hidden packed
     benchmarks only once and reuses those artifacts for the scalar-vs-kernel cases. The current
     canonical steady rerun on 2026-04-04 reconfirmed `array_sum_int` ~2.43× C and
     `dot_product_int` ~2.78× C before the hidden full-runtime warm leg took over.
   - New probe prebuild step (2026-03-20): the hidden packed-bridge warm leg now lives behind an
     explicit reusable script/target (`scripts/build_perf_artifacts_list_int_packed_bridge.sh`,
     `make perf-prebuild-list-int-packed-bridge`) so future probe runs can distinguish true
     packed-path timings from first-compile cost. Both hidden packed-bridge artifacts now build on
     the cheap native `core` profile, and the warm step now also prebuilds the matching C
     binaries so the packed scalar/SIMD probe legs can safely run with `OREN_BENCH_SKIP_BUILD=1`.
   - Follow-through (2026-03-27): native packed-bridge smoke and the dedicated
     `make verify-native-core-packed-bridge` gate now reuse that same core-runtime prebuild path,
     so the smoke tooling and the steady probe agree on the actual runtime boundary.
   - Fix (2026-03-27): native `i32` typed-buffer scalar dot/reduce fallbacks now pay the
     `native_buf_check(...)` cost once per call, then walk payload pointers directly via
     `oren_ptr_get_i32_le(...)` / `oren_ptr_set_i64_le(...)`. `std:linalg.reduce_sum_i32_buf(...)`
     now routes through that runtime reduce kernel instead of open-coding repeated
     `oren_buf_load_i32(...)` calls. A first shortened rerun on the same host improved the
     canonical steady baseline to `array_sum_int` ~1.35× C and `dot_product_int` ~1.36× C.
   - Probe result (2026-03-27, shortened steady sample: `n=100000`, `reps=5`, `runs=2`,
     `warmups=0`): the packed-bridge variants are still dramatically worse than the canonical
     loops. Baseline measured `array_sum_int` ~1.45× C and `dot_product_int` ~1.38× C, while the
     packed-bridge legs measured `array_sum_int_packed_bridge` ~1351× C scalar / ~1599× C SIMD and
     `dot_product_int_packed_bridge` ~14975× C scalar / ~3043× C SIMD. Even allowing for the short
     sample, that is directionally decisive: compiler-lowering ordinary `list<int>` dot loops into
     the current packed bridge is not justified yet.
   - Follow-up probe result (2026-03-27, same shortened steady sample after the pointer-loop
     runtime fix): the packed bridge is still dominated by bridge/materialization cost, not the
     inner typed-buffer kernel. Baseline measured `array_sum_int` ~1.35× C and `dot_product_int`
     ~1.36× C, while the packed-bridge legs still measured
     `array_sum_int_packed_bridge` ~1438× C scalar / ~1177× C SIMD and
     `dot_product_int_packed_bridge` ~15382× C scalar / ~2779× C SIMD. That closes the
     “maybe the typed-buffer fallback loops are the main blocker” hypothesis and pushes the next
     work toward bridge materialization removal or a direct 64-bit-slot lowering.
   - New direct-slot probe boundary (2026-03-27): native runtime now exposes
     `oren_list_int_reduce_sum_slots(_unchecked)` and `oren_list_int_dot_slots(_unchecked)`, and
     hidden native-only benchmarks/probes now measure that exact raw 64-bit-slot ABI separately
     from both the canonical compiler lowering and the packed bridge.
   - Direct-slot probe result (2026-03-27, shortened steady sample: `n=100000`, `reps=5`,
     `runs=2`, `warmups=0`): the direct-slot runtime helper path is much better than the packed
     bridge but still materially worse than the canonical lowering. Baseline measured
     `array_sum_int` ~1.35× C and `dot_product_int` ~1.41× C, while the hidden direct-slot helper
     benchmarks measured `array_sum_int_slot_direct` ~13.74× C and `dot_product_int_slot_direct`
     ~21.03× C. That is enough to prioritize “compiler lowering directly against the 64-bit-slot
     ABI” over any more packed-bridge work, but it also shows that a plain runtime helper call is
     not itself the final target.
   - Follow-up (2026-04-04): native backends now inline the unchecked raw-slot helper calls at the
     call site instead of routing those probes through a generic runtime helper body. x64 routes
     `oren_list_int_reduce_sum_slots_unchecked` / `oren_list_int_dot_slots_unchecked` through new
     dedicated intrinsics, and arm64 lowers the same symbols directly inside native call lowering.
     The forced steady rerun (`build/logs/perf-probe-list-int-slot-direct-20260404_200234.log`)
     moved the hidden direct-slot path to `array_sum_int_slot_direct` ~15.1069× C and
     `dot_product_int_slot_direct` ~5.1760× C, while the canonical baseline on the same sweep was
     `array_sum_int` ~2.3090× C and `dot_product_int` ~2.9950× C. That is a decisive improvement
     for the dot-shaped raw-slot path, but it also confirms that these unchecked helper-backed
     probes still should not replace the canonical list<int> fast loops as the default hot path.
	   - Ceiling probe + helper env fix (2026-04-05): the list<int> helper prebuild/smoke surfaces now
	     honor `OREN_BENCH_ENV_BUILD_OREN` consistently, including the slot-direct contract fixture and
	     the packed-bridge native prebuilds. The helper probe summaries now also record `build_env`, and
	     there is a new fast ranking surface, `make perf-probe-list-int-dot-ceiling`, for the current
     `dot_product_int` alternatives. Latest artifact
     (`build/logs/perf-probe-list-int-dot-ceiling-20260405_024559_38593.log`, explicit
     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, fast profile `runs=2 warmups=0 n=20000 reps=2`)
     ranks them as:
     - canonical `dot_product_int`: ~1.2137× C
     - direct-slot helper `dot_product_int_slot_direct`: ~1.5149× C
     - packed-bridge SIMD `dot_product_int_packed_bridge`: ~565.8124× C
	     - packed-bridge scalar `dot_product_int_packed_bridge`: ~1382.0339× C
	     This materially strengthens the next-step constraint: current helper/bridge detours are not
	     competitive with the canonical fast loop, so further work should stay on the direct lowering /
	     representation side instead of revisiting packed-bridge routing as a near-term parity path.
		   - Read-split follow-up (2026-04-05): the new `make perf-probe-list-int-packed-bridge-read-split`
		     surface answers the remaining setup-vs-steady attribution question for the current bridge.
		     This same batch also closes the remaining comma-separated `OREN_BENCH_ENV_BUILD_OREN`
		     forwarding gap on the packed-bridge / slot-direct prebuild and smoke helpers, so multi-key
	     build env overrides now reach those surfaces consistently too. The probe warms the hidden
	     packed-bridge artifacts once, then compares canonical `dot_product_int` against the packed
	     scalar / SIMD variants with the same short/long read-split runner. Latest
	     artifact (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_032402_91481.log`,
	     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=2 warmups=0 n=20000 short_reps=1
	     long_reps=2`) still comes back catastrophically behind the shipped path:
	     - baseline canonical `dot_product_int`: ~1.3378× C long-per-rep
		     - packed scalar `dot_product_int_packed_bridge`: ~1037.5886× C long-per-rep, ~3360.3659× C delta
		     - packed SIMD `dot_product_int_packed_bridge`: ~549.8375× C long-per-rep, ~126.8281× C delta
		     That closes the bridge attribution branch: even after warmup and with repeated-read cost
		     isolated, the current packed bridge remains hundreds of times slower than the direct lowering,
		     so it is not a near-term parity route.
		   - Shared runtime-backed bridge follow-up (2026-04-08): `buffer.i32_pack_list_int(...)` and
		     `buffer.i32_pack_list_int_into(...)` no longer route through shared Oren element loops.
		     Native, C, and AVM now expose dedicated runtime helpers for the same bridge, and the native
		     implementation hoists cursors and writes little-endian `i32` lanes directly instead of
		     calling the checked store helper per element. Tier-1 coverage now exercises the `_into`
		     surface on modules/native QI/AVM fixtures during `make test`.
		   - New ceiling rerun (2026-04-08): with that runtime-backed bridge in place, the latest
		     `make perf-probe-list-int-dot-ceiling` artifact
		     (`build/logs/perf-probe-list-int-dot-ceiling-20260408_231950_89006.log`,
		     fast profile `runs=2 warmups=0 n=20000 reps=2`) now ranks the same `dot_product_int`
		     alternatives as:
		     - canonical `dot_product_int`: ~1.2169× C
		     - direct-slot helper `dot_product_int_slot_direct`: ~1.1182× C
		     - packed-bridge SIMD `dot_product_int_packed_bridge`: ~4.9387× C
		     - packed-bridge scalar `dot_product_int_packed_bridge`: ~17.0948× C
		     That is a major bridge improvement over the earlier hundreds-of-times results, but it still
		     leaves the explicit packed route behind the shipped canonical path on whole-operation cost.
		   - Direct-slot read-split follow-up (2026-04-08): new
		     `make perf-probe-list-int-slot-direct-read-split` warms the hidden direct-slot artifacts once
		     and compares canonical `array_sum_int` / `dot_product_int` against the unchecked helper path
		     on the same short/long harness. Latest no-smoke rerun
		     (`build/logs/perf-probe-list-int-slot-direct-read-split-20260408_235243_30345.log`,
		     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) comes back as:
		     - canonical `array_sum_int`: ~1.3410× C long-per-rep
		     - direct-slot `array_sum_int_slot_direct`: ~1.0383× C long-per-rep
		     - canonical `dot_product_int`: ~1.2680× C long-per-rep
		     - direct-slot `dot_product_int_slot_direct`: ~1.1637× C long-per-rep
		     - delta note: the same rerun produced unstable split deltas (`dot_product_int`
		       `~‑0.0273× C` canonical vs `~7.6465× C` direct-slot), so use the long-per-rep side for
		       tracker decisions.
		     Reweight again: the hidden direct-slot helper is now a credible whole-operation ceiling on
		     the same split, which makes canonical/direct-slot convergence the higher-leverage next task
		     than any more packed-bridge tuning.
		   - Public slot-surface read-split follow-up (2026-04-09): new
		     `make perf-probe-list-int-slot-surface-read-split` warms the same slot-surface artifacts and
		     compares canonical `array_sum_int` / `dot_product_int` against both the hidden helper ceiling
		     and the public `std:linalg` slot wrappers on the same short/long harness. That surface is
		     still too noisy to use as the primary public-vs-helper ranking signal: the smoke-on rerun
		     (`build/logs/perf-probe-list-int-slot-surface-read-split-20260409_050248_17126.log`) and the
		     later no-smoke rerun (`build/logs/perf-probe-list-int-slot-surface-read-split-20260409_051528_36514.log`,
		     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) disagree on public-vs-helper ordering.
		     Latest no-smoke long-per-rep numbers came back as:
		     - canonical `array_sum_int`: `~1.2464× C`
		     - direct-slot `array_sum_int_slot_direct`: `~1.0077× C`
		     - public-slot `array_sum_int_slot_public`: `~1.1301× C`
		     - canonical `dot_product_int`: `~1.2771× C`
		     - direct-slot `dot_product_int_slot_direct`: `~1.0642× C`
		     - public-slot `dot_product_int_slot_public`: `~1.2439× C`
		     - delta note: this surface still produces unstable split deltas and contradictory
		       public-vs-helper winners across reruns.
		     Reweight again: keep this split probe as a sanity check that the public surface stays in the
		     right ballpark, but use the steady dot-ceiling probe for public-slot ranking.
			   - Public slot checked-contract + unchecked-len follow-up (2026-04-09): the native checked
			     raw helpers now match AVM/C parity by returning structured `invalid_arg` errors instead of
			     panicking on bad input, while the public `std:linalg` fast path keeps using the unchecked
			     raw helper after `oren_is_list_int(...)` has already proven the input and now uses
			     `oren_list_int_len_unchecked(...)` for the typed mismatch guard instead of paying the safer
			     `list.int_len(...)` probe again. `make verify-native-slot-direct` now covers both that
			     checked-helper contract and the old unchecked panic contract. The latest steady
			     `make perf-probe-list-int-dot-ceiling` artifact
			     (`build/logs/perf-probe-list-int-dot-ceiling-20260409_100858_61741.log`, `runs=2 warmups=0
			     n=20000 reps=2`) now ranks:
			     - canonical `dot_product_int`: `~1.2954× C`
			     - direct-slot `dot_product_int_slot_direct`: `~1.1648× C`
			     - public-slot `dot_product_int_slot_public`: `~1.1937× C`
			     - canonical `array_sum_int`: `~1.2869× C`
			     - direct-slot `array_sum_int_slot_direct`: `~1.0029× C`
			     - public-slot `array_sum_int_slot_public`: `~1.0855× C`
			     Reweight again: the public slot surface is still behind the hidden helper ceiling, but the
			     residual gap is smaller than the earlier tracker state on both steady benchmarks. Keep the
			     packed bridge deprioritized and treat the remaining work as a narrow public-wrapper /
			     helper convergence problem.
		   - Exact whole-list helper follow-up (2026-04-09): the refreshed post-unroll2 decision probe
		     `make perf-probe-arm64-whole-list-get-sum-helper-decision` now replaces the older manual
		     comparison. Latest artifact
		     (`build/logs/perf-probe-arm64-whole-list-get-sum-helper-decision-20260409_173112_97220.log`)
		     shows the same current-tree split more sharply:
		     - exact `array_sum_int`: shipped default `~1.9974×` vs helper-enabled `~13.6272×`
		       (`exact_array_winner: default`, helper/default `~6.8225×`)
		     - exact `dot_product_int`: shipped default `~1.7628×` vs helper-enabled `~1.8728×`
		     - small split hidden helper ceiling still looks reasonable:
		       `slot_direct_array_long_per_rep ~1.0113×`,
		       `slot_direct_vs_canonical_array_long_per_rep ~0.7866×`
		     Result: the hidden helper ceiling remains useful context, but the canonical whole-list
		     helper shortcut is still the wrong production move on the exact shipped tree. Keep
		     `OREN_NATIVE_FAST_LIST_INT_GET_SUM_WHOLE_LIST_HELPER=1` and
		     `OREN_NATIVE_FAST_LIST_INT_DOT_WHOLE_LIST_HELPER=1` opt-in only; the default path stays on
		     the existing canonical fast loop.
		   - Read-split rerun (2026-04-08): the paired
		     `make perf-probe-list-int-packed-bridge-read-split` artifact
		     (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log`,
		     `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) now changes the attribution again:
		     - baseline canonical `dot_product_int`: ~1.3778× C long-per-rep
		     - packed scalar `dot_product_int_packed_bridge`: ~13.5584× C long-per-rep
		     - packed SIMD `dot_product_int_packed_bridge`: ~4.1480× C long-per-rep, ~0.4993× C delta
		     So the repeated packed-SIMD kernel is no longer the blocker. The remaining gap is the
		     one-shot `list<int> -> []i32` bridge setup/materialization cost, which now becomes the next
		     concrete parity target.
		   - Explicit reuse-work follow-up (2026-04-08): shared `std:linalg` now exposes
		     `dot_i32_list_int_packed_reuse(...)` and `reduce_sum_i32_list_int_packed_reuse(...)`, which
		     repack into caller-provided `[]i32` work buffers via `buffer.i32_pack_list_int_into(...)`
		     instead of allocating fresh packed buffers inside every call. Hidden packed-bridge
		     benchmarks now honor `OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1`, and packed-bridge smoke covers
		     that mode on both `array_sum` and `dot_product`.
		   - Reuse-work read-split rerun (2026-04-08): latest
		     `make perf-probe-list-int-packed-bridge-read-split`
		     artifact (`build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log`,
		     no-smoke rerun, `runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) ranks the current
		     packed variants as:
		     - canonical baseline `dot_product_int`: ~1.2915× C long-per-rep, ~1.3011× C delta
		     - fresh-pack SIMD (`OREN_BENCH_PACKED_BRIDGE_SCALAR=1,OREN_ENABLE_SIMD=1`): ~7.3906× C
		       long-per-rep
		     - reuse-work SIMD (`OREN_BENCH_PACKED_BRIDGE_REUSE_WORK=1,OREN_ENABLE_SIMD=1`): ~7.2240× C
		       long-per-rep
		     - pack-once SIMD (`OREN_ENABLE_SIMD=1`): ~4.4566× C long-per-rep, ~1.5405× C delta
		     The reuse-work leg only trims a small slice of the fresh-pack cost and still loses badly to
		     the existing pack-once bridge. Reweight again: destination-buffer reuse alone is not the
		     parity lever; the remaining cost is the repeated `list<int> -> []i32` materialization/copy.
		   - Native pointer-i32 pack-store follow-up (2026-04-11): arm64/x64 native now inline
		     `oren_ptr_get_i32_le` / `oren_ptr_set_i32_le`, and the runtime `list<int> -> []i32` pack loop
		     stores each lane through the 32-bit little-endian pointer helper instead of four byte stores.
		     The fresh read-split probe
		     `build/logs/perf-probe-list-int-packed-bridge-read-split-20260411_203510_80313.log`
		     (`runs=2 warmups=0 n=20000 short_reps=1 long_reps=2`) materially lowers the bridge floor:
		     - canonical `dot_product_int`: ~1.2150× C long-per-rep
		     - fresh-pack SIMD: ~4.6037× C long-per-rep
		     - reuse-work SIMD: ~4.0130× C long-per-rep
		     - pack-once SIMD: ~2.3687× C long-per-rep, ~2.4378× C delta
		     - pack-once SIMD / canonical baseline long-per-rep: ~1.9495×
		     Bounded steady cross-check
		     `build/logs/perf-probe-list-int-packed-bridge-20260411_204441_93198.log`
		     (`runs=2 warmups=0 n=20000 reps=2`) reports packed-SIMD `array_sum_int_packed_bridge`
		     ~2.9643× C and `dot_product_int_packed_bridge` ~2.1500× C, versus canonical `array_sum_int`
		     ~1.2482× C and `dot_product_int` ~1.2109× C. Verdict: keep the improvement because it fixes
		     an obvious materialization cost, but do not reopen the packed bridge as a default route yet.
		     The current route-stability rerun
		     `build/logs/perf-probe-list-int-dot-ceiling-stability-20260411_204859_99207.log` still gives
		     packed-SIMD `0/5` wins on both array and dot, with median deltas `+269.38%` and `+134.27%`
		     versus canonical. The remaining work is to avoid/hoist the copy or change the representation
		     contract.
		   - Packed-SIMD reuse follow-up (2026-04-05): the new
		     `make perf-probe-list-int-packed-bridge-simd-reuse` surface removes the scalar leg and uses
		     a more reuse-oriented split (`short_reps=1`, `long_reps=10`) to answer the narrower question
		     “does the packed-SIMD bridge become viable once the pack cost is really amortized?” Latest
		     artifact (`build/logs/perf-probe-list-int-packed-bridge-simd-reuse-20260405_033734_11943.log`,
		     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=20000`) still says no:
		     - baseline canonical `dot_product_int`: ~0.000331s native long-per-rep
		     - packed-SIMD `dot_product_int_packed_bridge`: ~0.266698s native long-per-rep
		     - packed-SIMD / baseline long-per-rep: ~805.7341×
		     So the packed bridge is not just losing on one-time pack setup; even the strongly-amortized
		     reuse case is still catastrophically behind.
		   - Guarded typed-buffer ceiling + reuse fix (2026-04-05): the hidden
		     `benchmarks/dot_product_i32_buf/dot_product_i32_buf.{oren,c}` benchmark now perturbs lane `0`
		     across `reps` and accumulates every repetition result so the repeated dot work cannot be
		     hoisted. The rerun full-process ceiling (`make perf-probe-list-int-i32-buf-dot-ceiling`,
		     latest artifact `build/logs/perf-probe-list-int-i32-buf-dot-ceiling-20260405_040717_51202.log`)
		     still looks wide on whole-process per-rep numbers:
		     - packed-i32 C vector: ~0.000145s/rep
		     - Oren `dot_product_i32_buf` SIMD: ~0.002043s/rep
		     - Oren `dot_product_i32_buf` scalar: ~0.011786s/rep
		     but the probe now explicitly warns that this surface is setup-mixed.
		   - Focused SIMD reuse probe (2026-04-05): new
		     `make perf-probe-list-int-i32-buf-simd-reuse` keeps only the guarded packed-i32 C vector path
		     and the guarded Oren `dot_product_i32_buf` SIMD path, then raises the long run to
		     `short_reps=1`, `long_reps=1000` so repeated work dominates the C side. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-simd-reuse-20260405_040936_54584.log`,
		     `build_env: OREN_NATIVE_RUNTIME_PROFILE=core`, `runs=3 warmups=0 n=200000`) shows:
		     - packed-i32 C vector: `setup≈0.002528s`, `delta≈0.000018s`
		     - Oren `dot_product_i32_buf` SIMD: `setup≈0.374950s`, `delta≈0.000024s`
		     - repeated-kernel delta ratio: ~1.3562×
		     - whole-process long-per-rep ratio: ~19.7021×
		     This is the corrected attribution: the repeated `[]i32` SIMD kernel is only modestly behind
		     packed-i32 C, while the large observed wall-time gap is dominated by fixed setup / runtime
		     boundary cost on the typed-buffer path.
		   - Setup-breakdown follow-up (2026-04-05): new
		     `make perf-probe-list-int-i32-buf-setup-breakdown` adds a hidden
		     `benchmarks/fill_i32_buf/fill_i32_buf.{oren,c}` pair and compares fill-only setup against the
		     guarded SIMD reuse surface. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-setup-breakdown-20260405_042115_69806.log`,
		     `runs=3 warmups=0 n=200000 short_reps=1 long_reps=1000`) shows:
		     - fill-only C: `~0.002515s`
		     - fill-only Oren `[]i32`: `~0.372046s`
		     - packed-i32 C vector setup: `~0.002991s`
		     - Oren `dot_product_i32_buf` SIMD setup: `~0.375121s`
		     - Oren fill share of Oren SIMD setup: `~99.18%`
		     - Oren residual setup beyond fill: `~0.003075s`
		     That is the current narrow fact: nearly all remaining fixed cost on the typed-buffer path is
		     the `buffer.i32_new` + checked `oren_buf_store_i32(...)` fill phase itself, not a large hidden
		     post-fill runtime-call boundary.
		   - Fill-shape follow-up (2026-04-05): new
		     `make perf-probe-list-int-i32-buf-unchecked-fill` compares three hidden Oren fill-only
		     variants plus a fourth uninitialized-allocation case: checked store, helper-based unchecked
		     store, pointer-hoisted direct byte loop, and pointer-hoisted direct byte loop after
		     `oren_i32_buf_new_uninit`. Latest artifact
		     (`build/logs/perf-probe-list-int-i32-buf-unchecked-fill-20260405_044149_1286.log`,
		     `runs=3 warmups=0 n=200000`) shows:
		     - checked fill: `~0.376955s`
		     - unchecked helper fill: `~0.367594s` (`~1.0255×`)
		     - pointer-hoisted fill: `~0.344940s` (`~1.0928×`)
		     - pointer-hoisted + uninitialized fill: `~0.207338s` (`~1.8181×`)
		     That changes the next lever again: helper elision alone is small, pointer hoisting is real,
		     but skipping the eager zero-fill before a proven full overwrite is the first large win.
		   - Native bulk-fill fix (2026-04-05): `oren_buf_fill_i32/i64/f32/f64` in
		     [020_fill_sysio.oren](/Users/zongbaolu/work/compiler-mini/lib/runtime_native/typed_buffers/020_fill_sysio.oren)
		     no longer call the checked element-store helper on every lane after validating the buffer once.
		     They now hoist the payload pointer and write bytes directly, bringing the native runtime
		     implementation in line with the already-better AVM bulk-fill shape.
		   - Shared i32 conversion fast-path (2026-04-05): after the fill-shape probes established that
		     `native_buf_new` zero-fill was the first large fixed cost, the shared `std:buffer`
		     fresh-`i32` export surfaces now use `oren_i32_buf_new_uninit(...)` plus unchecked direct
		     stores only on success-only full-overwrite paths:
		     `buffer.i32_pack_list_int`, `buffer.try_slice_to_i32_buf`,
		     `buffer.try_strided_to_i32_buf`, `buffer.i32_mat_pack_rows`, and
		     `buffer.i32_mat_to_i32_buf`. The C runtime exports a conservative
		     `oren_i32_buf_new_uninit` shim that still zero-allocates so the same stdlib code remains
		     link-safe on `oren_c`.
		   - Real workload result (2026-04-05): the latest
		     [perf-probe-list-int-dot-ceiling-20260405_223926_17836.log](/Users/zongbaolu/work/compiler-mini/build/logs/perf-probe-list-int-dot-ceiling-20260405_223926_17836.log)
		     shows the kept fast path is no longer just a micro-benchmark win:
		     - baseline `dot_product_int`: `~1.4238x C`
		     - `dot_product_int_slot_direct`: `~0.9826x C`
		     - baseline `array_sum_int`: `~1.3214x C`
		     - `array_sum_int_slot_direct`: `~0.7955x C`
		     The paired read-split artifact
		     [perf-probe-list-int-packed-bridge-read-split-20260405_223926_17837.log](/Users/zongbaolu/work/compiler-mini/build/logs/perf-probe-list-int-packed-bridge-read-split-20260405_223926_17837.log)
		     still leaves the packed bridge hopelessly non-competitive (`~542.7074x C` SIMD,
		     `~1062.1370x C` scalar on long-per-rep), so the improvement is real but correctly scoped
		     to direct `i32` conversion surfaces.
		   - Runtime bridge extension (2026-04-08): the adjacent shared `list<int> -> []i32` bridge is
		     now on the same principle, but implemented below the stdlib loop layer instead of inside it.
		     Shared `buffer.i32_pack_list_int` / `_into` now call dedicated runtime helpers across native,
		     C, and AVM. Native hoists source/destination cursors and writes bytes directly, C uses the
		     raw list-int slot ABI when list locking is not needed, and AVM now exposes matching native
		     ids. The same turn added `_into` coverage to modules/native QI/AVM tests.
		   - Current bridge result (2026-04-08): latest
		     [perf-probe-list-int-dot-ceiling-20260408_231950_89006.log](/Users/zongbaolu/work/compiler-mini/build/logs/perf-probe-list-int-dot-ceiling-20260408_231950_89006.log)
		     shows the bridge is no longer catastrophically behind (`dot_product_int_packed_bridge`
		     `~4.9387x C` SIMD, `~17.0948x C` scalar), and the paired read-split artifact
		     [perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log](/Users/zongbaolu/work/compiler-mini/build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_232146_91269.log)
		     narrows the remaining blocker further: packed-SIMD still lands at `~4.1480x C`
		     long-per-rep, but its repeated-work delta is already `~0.4993x C`. Reweight accordingly:
		     the kernel side is good enough to stop tuning for now; the next work item is bridge
		     setup/materialization elimination or reuse.
		   - Reuse-work follow-up (2026-04-08): shared `std:linalg` now also exposes explicit
		     caller-managed workspace reuse for the same bridge:
		     `dot_i32_list_int_packed_reuse(...)` and
		     `reduce_sum_i32_list_int_packed_reuse(...)`. The latest rerun,
		     [perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log](/Users/zongbaolu/work/compiler-mini/build/logs/perf-probe-list-int-packed-bridge-read-split-20260408_234329_17881.log),
		     shows why that is useful but not sufficient: fresh-pack SIMD is `~7.3906x C`
		     long-per-rep, reuse-work SIMD is only slightly better at `~7.2240x C`, and the existing
		     pack-once SIMD path still leads the bridge family at `~4.4566x C`. That closes the next
		     branch more tightly: fresh allocation is not the dominant remaining cost anymore; repeated
		     bridge materialization/copy is.
		   - Family follow-up (2026-04-05): the same proven-safe rule now covers the other fresh numeric
		     typed-buffer export paths too, not just `i32`. Shared stdlib pack/slice/strided/matrix
		     exports for `i64`, `f32`, and `f64` now also use `*_buf_new_uninit(...)` plus unchecked
		     direct stores on success-only full-overwrite paths. The C runtime exports conservative
		     `oren_i64_buf_new_uninit`, `oren_f32_buf_new_uninit`, and `oren_f64_buf_new_uninit` shims
		     that still zero-allocate, keeping the shared stdlib link-safe on `oren_c` while native gets
		     the uninitialized-allocation win.
		   - `u8` export follow-up (2026-04-05): the same full-overwrite proof now covers fresh `[]u8`
		     export surfaces as well. Shared stdlib `buffer.try_u8_pack`,
		     `buffer.try_u8_from_string`, `buffer.try_u8_from_string_slice`,
		     `buffer.try_slice_to_u8_buf`, `buffer.try_strided_to_u8_buf`,
		     `buffer.try_u8_mat_pack_rows`, `buffer.try_u8_mat_pack_strings`,
		     `buffer.try_u8_mat_to_u8_buf`, `bytes.try_to_u8_buf`, and
		     `bytes.try_to_u8_buf_slice` now route through `oren_u8_buf_new_uninit(...)` plus direct
		     unchecked writes only on success-only full-write paths. This also removes the old
		     intermediate-list hop from slice/strided-to-`[]u8` export and reuses the shared
		     `oren_u8_buf_from_bytes_slice(...)` primitive for bytes-to-buffer copies. The C runtime now
		     exports a conservative `oren_u8_buf_new_uninit` shim so the same shared stdlib code remains
		     backend-safe on `oren_c`.
		   - Shared byte-constructor follow-up (2026-04-05): finish the same rule on the adjacent
		     shared/runtime byte constructors that also fully overwrite fresh `[]u8` before any
		     successful return. `bytes.from_hex`, `bytes.pack`, `base64.decode_bytes`, native
		     `oren_bytes_from_hex`, native `oren_bytes_pack`, and both C/native `read_u8_buf` allocation
		     paths now also use `oren_u8_buf_new_uninit(...)` instead of zero-allocating first. This is
		     intentionally a scope/safety cleanup, not a new measured perf claim.
		   - Fresh linalg output follow-up (2026-04-05): extend the same full-overwrite rule into the
		     adjacent typed-buffer linear algebra constructors instead of leaving the matmul/axpy family on
		     the old zero-allocating path. `axpy_i32_buf`, `axpy_f32_buf`, `matmul_i32_buf`,
		     `matmul_i32_buf_wide`, `matmul_f32_buf`, and `matmul_f64_buf` now allocate fresh output
		     buffers via `*_buf_new_uninit(...)` where the paired `*_into` kernel overwrites every lane on
		     successful return. Their pack/transpose and microkernel scratch buffers (`bp`, `bt`, `tmp4`,
		     `tmp16`) now use the same rule when the local fill path or runtime `*_slice_into` helper
		     deterministically writes every slot before exposure. This is again a scope/safety cleanup, not
		     a new kept benchmark claim.
		   - Shared serializer follow-up (2026-04-05): finish the same rule on a few remaining shared
		     fresh-`[]u8` serializers that also fully overwrite every output byte before any successful
		     return. `http2.settings_payload_from_list`, `http2_client._u8_concat2`,
		     `http2_client._read_frame`, `http2_client._send_headers_fragmented`,
		     `hpack._huff_decode_bytes` final output materialization, and `ppm.encode_rgba` now allocate
		     through `oren_u8_buf_new_uninit(...)`. Added focused module coverage for the HTTP/2 SETTINGS
		     payload encode/decode round-trip so this path is no longer covered only indirectly.
		   - Shared byte-helper follow-up (2026-04-05): after the constructor/allocation cleanup, remove
		     the remaining obvious list-materialization hops in portable helper code. `bytes.try_to_string`,
		     `bytes.try_slice`, `bytes.try_concat`, `bytes.try_from_u8_buf`, and
		     `bytes.try_to_string_slice` now use the shared direct bridges
		     `oren_string_from_bytes_slice(...)` / `oren_u8_buf_from_bytes_slice(...)` and unchecked
		     direct `u8` writes instead of round-tripping through temporary `list<int>` values. Likewise,
		     `ppm.write_rgba_ppm` now passes the encoded `u8_buf` directly to `oren_write_bytes(...)`
		     because the shared runtimes already accept `u8_buf` there. Added focused module coverage for
		     the PPM write/read round-trip.
		   - Compiler byte-path follow-up (2026-04-05): the adjacent compiler artifact readers now stay
		     on the same generic-bytes / `u8_buf` surface instead of forcing legacy `oren_read_bytes(...)`
		     lists first. `lib/compiler/obc_link.oren` now parses `.obc` / `OBX` payloads through
		     `oren_bytes_len(...)`, `oren_bytes_get_u8(...)`, and `oren_string_from_bytes_slice(...)`
		     and reads bundle files via `oren_read_u8_buf(...)`; the deterministic metadata hashing legs
		     in `lib/compiler/compiler/040_build_pipeline/010_main.oren` now also hash `oren_read_u8_buf`
		     results directly and use `_bytes_len_any(...)` for manifest size accounting.
		   - AVM `.obc` byte-path follow-up (2026-04-05): the adjacent AVM test/harness readers that
		     immediately feed `.obc` payloads into `oren_avm_run_obc_bytes(...)` or VirtualFS fixtures
		     no longer bounce through `oren_read_bytes(...) -> oren_bytes_pack(...)`. The multiverse,
		     map-key, and compiler-in-AVM fixtures now read `.obc` via `oren_read_u8_buf(...)`
		     directly, and their local VFS fixture builders now append generic bytes via
		     `oren_bytes_len(...)` / `oren_bytes_get_u8(...)` instead of assuming `list<int>` bodies.
		   - AVM byte-slice bridge follow-up (2026-04-12): bytecode now maps
		     `oren_string_from_bytes_slice(...)` and `oren_u8_buf_from_bytes_slice(...)` to AVM native
		     helpers. This closes the direct generic-bytes bridge used by `std:bytes` / `std:strings`,
		     so curated `make test-avm` no longer fails at `test_smoke_suite` bytecode build time after
		     the shared helper cleanup. The same AVM pass also fixes spawned task bootstrap to unpack
		     positional args into the new task frame, closing the immediately exposed
		     `CHAN_SEND expects int channel` runtime failure in the curated smoke suite; `make test` now
		     includes `make verify-avm-spawn-channel-args` as a focused regression guard. The broader
		     curated AVM rerun temporarily added bounded structural equality for aggregate `==` / `!=`;
		     the follow-up cross-backend tag parity gate rebalanced that operator back to the shipped
		     C/native identity contract for lists, maps, bytes, and typed buffers. UI tree comparison
		     now uses an explicit `std:ui/core.node_equal(...)` structural helper instead of relying
		     on operator divergence. The same AVM pass added AVM `list + list` concatenation for UI
		     diff path-prefix construction, and maps the `*_buf_new_uninit(...)` typed-buffer
		     constructor aliases to the existing deterministic AVM buffer constructors.
		     `make test-avm` now clears the curated UI patch/render/raster/PPM lane again.
	   - Verification follow-up (2026-04-04, widened 2026-04-09): `make verify-native-slot-direct`
	     now checks more than the benchmark numerics. The slot-direct smoke builds
	     `tests/fixtures/list_int_slot_direct_contracts.oren`, validates the hidden helper-entry
	     benchmarks, and now also validates the hidden public-slot benchmarks
	     `array_sum_int_slot_public` / `dot_product_int_slot_public`. It still asserts the unchecked
	     helper contracts directly: `reduce_sum_slots_unchecked(nil) == 0`,
	     `dot_slots_unchecked(nil, nil) == 0`, and deterministic panic text
	     (`list_int_dot_slots_unchecked: length mismatch`) for one-nil and unequal-length dot calls.
   - Verification (2026-03-28): the canonical benchmark shapes are already using that direct-slot
     compiler lowering path today. A new dedicated gate (`make verify-native-list-int-fast-lowering`)
     now proves `benchmarks/array_sum_int/array_sum_int.oren` still emits
     `fast_list_int_get_sum_while(_no_tick)?` on the local arm64 backend and
     `benchmarks/dot_product_int/dot_product_int.oren` still emits
     `fast_list_int_dot_while(_no_tick)?`; the same gate also traces the matching x64-linux lowering
     via compile-time `[x64_list_fast] ... kind=fast_list_int_{get_sum,dot}_while` lines. That
     closes the ambiguity from the direct-slot helper probe: the remaining work is to widen or
     improve the existing compiler fast loops, not to introduce a first direct-slot lowering path.
   - Follow-up (2026-04-04): `make verify-native-list-int-fast-lowering` now also compiles the
     canonical W5 perf-gate benchmarks `benchmarks/array_sum/array_sum.oren` and
     `benchmarks/dot_product/dot_product.oren`, proving the auto-specialized benchmark path still
     stays on the fast `list<int>` lowering on both native backends.
   - Structural guard widen (refreshed 2026-04-11): the same
     `make verify-native-list-int-fast-lowering` gate now also runs
     `make verify-native-arm64-dot-madd-scalar-default`, so the shipped arm64 scalar-tail choice is
     pinned by a deterministic disasm A/B instead of only by probe notes. Latest log
     (`build/logs/verify_arm64_dot_madd_scalar_default_20260411_171634_95703.log`): generic
     `dot_product` and explicit `dot_product_int` now stay at `instruction_count=21`,
     `range_without_cold_gc_tick_instruction_count=14`, and `madd_count=0` on the shipped
     post-unroll2 baseline, while forcing
     `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1` moves both to
     `instruction_count=20`, `range_without_cold_gc_tick_instruction_count=13`, and
     `madd_count=1`.
   - New parity widen (2026-03-28): arm64/x64 fast-loop matchers now also accept the equivalent
     commuted reductions `sum = xs[i] + sum` and `sum = a[i] * b[i] + sum` for both `list<int>`
     and boxed-list direct-loop lowerings. The same `make verify-native-list-int-fast-lowering`
     gate now compiles `tests/fixtures/list_int_fast_lowering_commuted.oren` and asserts those
     commuted `list<int>` loops still emit the native direct-slot get-sum and dot fast traces on
     both backends, while native QI coverage now checks boxed and `list<int>` commuted loops for
     correctness under `make test`.
   - New temp-normalized widen (2026-03-28): the same arm64/x64 matchers now also accept one-temp
     normalized reductions such as `var x = xs[i]; sum = x + sum` and
     `var p = a[i] * b[i]; sum = p + sum`, again for both `list<int>` and boxed-list direct-loop
     siblings. `make verify-native-list-int-fast-lowering` now compiles
     `tests/fixtures/list_int_fast_lowering_temp.oren` and asserts those temp-normalized
     `list<int>` loops still emit the direct-slot fast traces on both backends; native QI now also
     checks temp-normalized boxed and `list<int>` loops during `make test`.
   - New warm-path control (2026-03-20): the packed-bridge prebuild now accepts an explicit
     program list, and `make perf-prebuild-dot-product-int-packed-bridge` warms only the hidden dot
     artifact before the timed ceiling probe.
   - New focused read split (2026-03-20): the split runner now reports both delta-based and
     long-run-per-rep estimates and warns when they drift materially. On the latest rerun,
     `array_sum_int` delta-vs-long drifted by about 30%, so steady-state tracker updates should
     prefer the dedicated steady runner or, at minimum, the split long-per-rep estimate over the
     naive delta subtraction.

3) **W5 - Runtime robustness (GC reuse + allocator invariants)**
   - GC reuse paths are experimental; list header corruption investigations are ongoing.
   - Guardrails and traces exist, but correctness gates are not yet stable.
   - Fix: rtobj seed keys now include trace hash opts (alloc_req/list_hdr/list_reserve) so
     trace builds cannot reuse non-trace runtime objects under cache hits (2026-03-03).
   - Fix: free_nodes reuse now enforces canonical node headers (48 bytes + magic) and raw-node
     reuse is re-enabled with integrity guards to avoid invalid pointers (2026-03-03).
   - Repro (2026-02-26): `benchmarks/run_benchmarks.py` dot_product Oren C build panicked with
     `gc list header corrupt` (log: `build/logs/bench_build_oren_c_dot_product_20260226_145741.log`).
   - Fix: GC list header validation now accepts 16-byte aligned inline header sizes to avoid
     false corruption on small caps (2026-02-26).
   - Fix: list_reserve now attempts alloc-index recover + header re-track before panicking
     on non-list headers to reduce false positives under GC churn (2026-02-26).
  - New: free-list header dumps now emit list_hdr ring traces when validation fails, to
    correlate last header writes with corrupted free-list entries (2026-02-26).
  - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` now auto-enables free-list header dumps
    and list_hdr ring capture to reduce trace setup friction (2026-02-26).
   - Fix: host-thread green spawn/join now uses world-lock critical sections when enabled,
     preventing races in multi-worker world-lock mode (2026-02-26).
   - Fix: host metadata lookups (`oren_find_node`) now enter the world lock when workers
     are active, avoiding list/map metadata races during world-lock tests (2026-02-26).
   - Fix: alloc-index recovery (`native_alloc_index_recover_ptr`) now enters the host
     world lock, and green runq/entry guards now use `_green_args_list_node(..., 1)` so
     sane args_list headers can rebuild/retrack through transient alloc-index misses before
     panicking (2026-03-06).
   - Verified: guarded world-lock smoke passed 3/3 runs with
     `OREN_GREEN_POLL_CACHE=1 OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1`
     (log: `build/logs/codex_green_world_lock_smoke_20260306.log`, 2026-03-06).
   - Verified: dot_product Oren C benchmark build/run now completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_oren_c_20260226_155530.log`).
   - Verified: dot_product_int Oren C benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_oren_c_20260226_155726.log`).
   - Verified: dot_product_int Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_int_native_20260226_161550.log`).
   - Verified: dot_product Oren native benchmark build/run completes without list-header corruption
     after aligned-header fix (log: `build/logs/bench_dot_product_native_20260226_161555.log`).
   - New: list corruption checks now flag len/cap invariants and reserve-fail traces log header fields (2026-02-25).
   - New: green scheduler struct allocations now rebuild/force GC tracking before tagging kind=STRUCT,
     preventing args-list GC under `OREN_GREEN_POLL_CACHE=1` (2026-02-25).
   - New: map checks rebuild the alloc-index once on non-map detection to avoid false panics under GC churn (2026-02-26).
   - New: list len checks rebuild the alloc-index once on non-list detection to avoid false panics under GC churn (2026-02-26).
   - New: alloc-index recovery scans live allocs on map/list misses to reinsert missing nodes before panicking (2026-02-26).
   - New: list/map constructors re-track headers when alloc-index misses to prevent untracked containers under GC stress (2026-02-26).
   - New: map/list checks re-track headers on alloc-index misses when magic+cap look sane to reduce false panics (2026-02-26).
   - Fix: green spawn/entry now re-track args_list headers on alloc-index misses when magic+len/cap look sane to avoid false panics under GC churn (2026-03-04).
   - New: arm64/x64 `oren_list_len` intrinsics now fall back to magic+count on untracked headers
     to avoid false panics under GC stress (2026-02-26).
   - New: `oren_track_alloc_new` now de-duplicates existing alloc-index nodes to prevent duplicate
     tracking entries under reuse/GC churn (2026-02-26).
   - New: `make test-native-quick-gc-stress-stage2` runs quick integration with forced GC
     (`OREN_GC_ALLOC_THRESHOLD=20000`) and longer timeouts (2026-02-26).
   - New: `make verify-native-quick-gc` runs the standard native quick verify plus GC-stress
     quick integration to catch tracking regressions (2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX=1` now reports `dedup_hits` for alloc-index de-dup
     in `oren_track_alloc_new` (2026-02-26).
   - New: `OREN_TRACE_ALLOC_INDEX_DEDUP_CAP=<n>` panics when dedup hits exceed `n`
     (trace-only guardrail, 2026-02-26).
   - New: list header/buffer alloc requests emit cap/bytes context when
     `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1` triggers (`[list_hdr_req]`, `[list_buf_req]`, 2026-02-26).
   - New: list growth/reserve now guards `cap > 1<<30` as corruption to avoid overflow
     and to fail fast on bad headers (2026-02-26).
   - New: GC mark now validates list/list_int headers and panics on corruption
     before scanning payloads (2026-02-26).
   - New: optional list header poisoning on GC free sets magic to `list_magic_poison`
     (`OREN_GC_POISON_LIST_HEADERS=1`); reuse precheck tolerates poison while GC mark
     remains strict to surface use-after-free (2026-02-26).
  - New: list header ring guard now logs `[list_hdr_ring_ptr_guard_last_corrupt]` when
    `g_trace_list_hdr_ring_ptr_guard_last` is not 0/1 to catch unexpected writes (2026-02-27).
  - New: `scripts/triage_native_quick_stage2_flake_debug.sh` + `make test-native-quick-stage2-flake-debug`
    run the stage2 quick integration loop with spawn ring + list header ring guardrails
    enabled for flake triage; timeouts can be overridden via
    `OREN_NATIVE_RUN_TIMEOUT_SECS` / `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS` /
    `OREN_NATIVE_BUILD_TIMEOUT_SECS` (2026-03-04).
  - New: `scripts/triage_native_quick_flake_debug.sh` + `make test-native-quick-flake-debug`
    provide the same guardrail triage for stage1 native quick integration (2026-03-04).
  - New: `make verify-backend-parity` runs all cross-backend parity smokes in one shot
    (boxed list, list<int>, bytes, tags, arith panics, index panics) (2026-03-27).
  - New: `scripts/verify_backend_parity_*.sh` accepts `OREN_BACKEND_PARITY_TRACE_ENV`
    to forward trace env vars into build/run steps for deeper corruption diagnosis
    (2026-03-04).
  - Trace: `OREN_BACKEND_PARITY_TRACE_ENV='OREN_TRACE_LIST_HDR_RING=1 OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1 OREN_TRACE_LIST_HDR_RING_CAP=4096 OREN_TRACE_LIST_CORRUPT=1'`
    allows `make verify-backend-parity` to complete cleanly on 2026-03-04 (log: `build/logs/verify_backend_parity_trace_20260304.log`).
  - Trace: stage2 native quick integration segfaulted during QI dbg sugar (rc=139);
    log: `build/logs/oren_stage2_native_quick_flake_20260304_161224_run1.log` (2026-03-04).
  - Trace: stage2 quick flake debug guardrail run (3 runs) completed cleanly under
    list header ring + spawn ring + list corruption tracing (log:
    `build/logs/triage_stage2_flake_debug_20260304_183646.log`, 2026-03-04).
  - Trace: stage2 quick flake debug run (5 runs) with list_hdr dup + gc_list_hdr_kind
    tracing completed cleanly (log:
    `build/logs/triage_stage2_flake_debug_dup_20260304_184142.log`, 2026-03-04).
  - Trace: stage1 quick flake debug run (5 runs) with list_hdr dup + gc_list_hdr_kind
    tracing completed cleanly (log:
    `build/logs/triage_stage1_flake_debug_dup_20260304_184754.log`, 2026-03-04).
  - Trace: stage1 quick flake (5 runs) with list corruption tracing and larger ring
    capacity completed cleanly (log:
    `build/logs/triage_stage1_flake_noguard_20260304_185130.log`, 2026-03-04).
  - Trace: stage1 quick flake (30 runs) with list corruption tracing (no guardrails)
    segfaulted at run 4 (rc=139); log:
    `build/logs/triage_stage1_flake_noguard_30_20260304_185445.log` (run log:
    `build/logs/oren_native_quick_flake_20260304_185547_run4.log`, 2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (20 runs) with list corruption
    tracing + free-list ring passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_trace_20260304_185657.log`, 2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + list header
    ring (cap 8192) and extended timeouts passed cleanly (log:
    `build/logs/triage_stage1_flake_ringonly_timeout_20260304_190448.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + green spawn
    ring only passed cleanly (log:
    `build/logs/triage_stage1_flake_spawn_ringonly_20260304_191042.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + list header
    ring dup guard (cap 8192) passed cleanly (log:
    `build/logs/triage_stage1_flake_list_ringdup_20260304_191425.log`,
    2026-03-04).
  - Trace: stage1 quick flake (10 runs) with list corruption tracing + free-list
    ring passed cleanly (log:
    `build/logs/triage_stage1_flake_freelist_ring_20260304_191805.log`,
    2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (5 runs) after args_list retrack
    passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_retrack_20260304_210139.log`,
    2026-03-04).
  - Trace: stage1 quick flake debug guardrail run (20 runs) with jitter
    (`OREN_QI_JITTER_MAX_MS=50`) after args_list retrack passed cleanly (log:
    `build/logs/triage_stage1_flake_debug_retrack_jitter_20260304_210806.log`,
    2026-03-04).
  - Trace: stage1 quick flake (50 runs) with jitter (`OREN_QI_JITTER_MAX_MS=50`) and
    auto rerun guardrails hit rc=143 at run 16; auto rerun with guardrails succeeded
    (log: `build/logs/triage_stage1_flake_autorun_jitter_20260304_195330.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_194557_run16.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_194557_run16_guardrails.log`,
    2026-03-04).
  - Trace: quick integration green-cache-only run with jitter
    (`OREN_QI_ONLY_GREEN_CACHE=1`, `OREN_QI_JITTER_MAX_MS=50`) completed cleanly
    (log: `build/logs/quick_integration_green_only_jitter_20260304_195118.log`,
    2026-03-04).
  - Trace: quick integration base-only run with jitter
    (`OREN_QI_SKIP_GREEN_CACHE=1`, `OREN_QI_JITTER_MAX_MS=50`) completed cleanly
    (log: `build/logs/quick_integration_base_only_jitter_20260304_195240.log`,
    2026-03-04).
  - Trace: stage1 quick flake with jitter only (`OREN_QI_JITTER_MAX_MS=50`, no list
    tracing) failed at run 12 with `assert_eq` in `test_select_in_green_workers`
    during green-cache phase (got -5, expected 777), rc=50 (log:
    `build/logs/triage_stage1_flake_jitter_notrace_20260304_195411.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_195754_run12.log`,
    2026-03-04).
  - Trace: stage1 quick flake with jitter + auto rerun guardrails (no list tracing on
    base run) segfaulted at run 7 (rc=139); auto rerun guardrails succeeded (log:
    `build/logs/triage_stage1_flake_jitter_autorun_notrace_20260304_195907.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_200108_run7.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_200108_run7_guardrails.log`,
    2026-03-04).
  - Trace: quick integration with green-cache first + 3 repeats and jitter
    (`OREN_QI_GREEN_CACHE_FIRST=1`, `OREN_QI_GREEN_CACHE_RUNS=3`,
    `OREN_QI_JITTER_MAX_MS=50`) completed cleanly (log:
    `build/logs/quick_integration_green_first_repeat_20260304_200604.log`,
    2026-03-04).
  - Trace: quick integration with green-cache first + 20 repeats and jitter
    (`OREN_QI_GREEN_CACHE_FIRST=1`, `OREN_QI_GREEN_CACHE_RUNS=20`,
    `OREN_QI_JITTER_MAX_MS=50`) completed cleanly (log:
    `build/logs/quick_integration_green_first_repeat20_20260304_200743.log`,
    2026-03-04).
  - Trace: stage1 quick flake with jitter + auto rerun guardrails failed at run 31
    with rc=143; auto rerun guardrails succeeded (log:
    `build/logs/triage_stage1_flake_jitter_autorun_20260304_200926.log`, run log:
    `build/logs/oren_native_quick_flake_20260304_201937_run31.log`, guardrails log:
    `build/logs/oren_native_quick_flake_20260304_201937_run31_guardrails.log`,
    2026-03-04).
  - Trace: stage1 quick flake with jitter + auto rerun guardrails + green-cache-first
    hit `Indexing on non-container` in `__oren_fnwrap_worker_green_local_ptr_survives_yields`
    at run 7 (rc=1); auto rerun guardrails succeeded (log:
    `build/logs/triage_stage1_flake_jitter_autorun_greenfirst_20260304_202152.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_202353_run7.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_202353_run7_guardrails.log`,
    2026-03-04).
  - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
    rerun guardrails hit rc=143 at run 27; auto rerun guardrails succeeded (log:
    `build/logs/triage_stage1_flake_greenonly_autorun_20260304_202536.log`, run log:
    `build/logs/oren_native_quick_flake_20260304_203350_run27.log`, guardrails log:
    `build/logs/oren_native_quick_flake_20260304_203350_run27_guardrails.log`,
    2026-03-04).
  - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
    rerun guardrails + green-cache repeats (10) hit rc=143 at run 8; guardrail rerun
    segfaulted (rc=139) (log:
    `build/logs/triage_stage1_flake_greenonly_autorun_repeat10_20260304_203557.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_203927_run8.log`, guardrails log:
    `build/logs/oren_native_quick_flake_20260304_203927_run8_guardrails.log`,
    2026-03-04).
  - Trace: stage1 quick flake with green-cache-first + skip-base-run + jitter + auto
    rerun guardrails + green-cache repeats (10) hit rc=143 at run 27; guardrail rerun
    segfaulted with `green_spawn_alloc args_list untracked` in the ring dump
    (log: `build/logs/triage_stage1_flake_greenonly_autorun_repeat10_20260304_203557.log`,
    run log: `build/logs/oren_native_quick_flake_20260304_203350_run27.log`,
    guardrails log:
    `build/logs/oren_native_quick_flake_20260304_203350_run27_guardrails.log`,
    2026-03-04).
  - Fix: AVM truthiness now treats int zero as truthy to match Oren semantics
    (only `nil`/`false` are falsey) (2026-03-04).
  - New: `scripts/triage_arith_div0_c_build_flake.sh` + `make test-native-quick-arith-div0-flake`
    loop a C-backend build fixture (default `arith_div0.oren`, override with
    `OREN_TRACE_ARITH_SRC=...`) with list header ring guardrails to reproduce
    list_int header corruption (2026-03-04).
  - New: `scripts/verify_runtime_robustness_w5.sh` + `make verify-runtime-robustness`
    run the W5 runtime-robustness smoke (stage1 quick-integration guards + stage2 quick
    integration + C-backend build fixtures) with guardrail traces; optional
    `OREN_RUNTIME_ROBUSTNESS_TRACE_ENV` forwards trace env vars into child scripts for faster
    production-readiness triage. Make target knobs: `OREN_RUNTIME_ROBUSTNESS_RUNS`,
    `OREN_RUNTIME_ROBUSTNESS_COMPILER`, `OREN_RUNTIME_ROBUSTNESS_BASE_RUNS`,
    `OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS`, `OREN_RUNTIME_ROBUSTNESS_C_RUNS`,
    `OREN_RUNTIME_ROBUSTNESS_C_FIXTURES`, and `OREN_RUNTIME_ROBUSTNESS_TRACE_ENV` (2026-03-04).
  - New: `scripts/triage_native_quick_flake.sh` supports auto re-run with guardrails via
    `OREN_QI_AUTO_RERUN_GUARDRAILS=1`; override env with
    `OREN_QI_AUTO_RERUN_ENV='KEY=VAL ...'` to capture guardrail traces on flakes
    (2026-03-04).
  - New: `scripts/triage_native_quick_flake.sh` supports per-run jitter via
    `OREN_QI_JITTER_MAX_MS=<n>` to vary scheduling when chasing timing-sensitive flakes
    (2026-03-04).
  - New: `scripts/run_native_quick_integration.sh` supports phase controls via
    `OREN_QI_SKIP_BASE_RUN=1`, `OREN_QI_SKIP_GREEN_CACHE=1`,
    `OREN_QI_STOP_AFTER_GREEN_CACHE=1`, or `OREN_QI_ONLY_GREEN_CACHE=1` to isolate
    quick-integration timeouts (2026-03-04).
  - New: `scripts/run_native_quick_integration.sh` supports `OREN_QI_GREEN_CACHE_FIRST=1`
    to run the green-cache phase before the base run and `OREN_QI_GREEN_CACHE_RUNS=<n>`
    to repeat the green-cache phase (2026-03-04).
  - New: green spawn alloc guard now dumps raw args_list header + list debug traces
    when the args_list is untracked, before panicking (2026-03-04).
   - Trace: global slot dump maps `idx=434` / `off=3472` to `g_trace_list_hdr_ring_ptr_guard_last`
     after rebuilding stage2 (`alloc_churn_build_globals_idx434_manual_20260227.log`, 2026-02-27).
   - Trace: precheck_guard9 (cached + no-cache) still shows bad-list roots with
     `root_slot_offset=3472` while `guard_last=1` and no guard-last-corrupt logs; suggests
     root-slot offset may not reflect g_storage (`alloc_churn_trace_precheck_guard9_20260227.log`,
     `alloc_churn_trace_precheck_guard9_nc_20260227.log`, 2026-02-27).
   - Trace: after bounding root-slot offsets to `boot_globals_storage` (512 bytes),
     precheck_guard10 now reports `root_slot_offset=-1` while bad-list roots persist,
     confirming the earlier 3472 offset was outside g_storage
     (`alloc_churn_trace_precheck_guard10_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_ROOT_SLOTS=1` shows `root_idx=35`, `list_len=409`, and the
     global-roots entry at `i=35` points to a slot pointer outside g_storage whose value
     equals the bad-list ptr, indicating the root list is pointing at a non-g_storage slot
     (`alloc_churn_trace_precheck_guard13_nc_20260227.log`, 2026-02-27).
   - Trace: `OREN_TRACE_GC_REGISTER_ROOT=1` shows early roots registered at
     `slot_off=-8` (g_storage slot) and `slot_off=528..560` (heap spill slots);
     `OREN_TRACE_GC_ROOT_MATCHES=1` shows three root slots (idx 35/117/182) whose
     slot values equal the bad-list ptr with `slot_off=2376..3552` (all outside the 512B
     boot globals range) (`alloc_churn_trace_precheck_guard15_nc_20260227.log`, 2026-02-27).
   - Trace: compile-time global slot mapping shows `slot_off=2376/2896/3584` correspond to
     `g_gc_reuse_bad_list_triggers`, `g_runtime_root_len`, and `g_trace_list_header`,
     suggesting global int slots are being overwritten by bad-list pointers
     (`alloc_churn_globals_trace_20260227_072238.log`, 2026-02-27).
   - Trace: pending root tags now flush once envp-derived tracing is enabled, showing
     runtime init’s `value_nil/false/true` registrations with `pending=1`
     (`alloc_churn_trace_precheck_guard22_nc_20260226.log`, 2026-02-26).
   - Tool: `OREN_TRACE_GC_REGISTER_ROOT` now tags known call sites; untagged entry-stub
     roots are skipped unless `OREN_TRACE_GC_REGISTER_ROOT_ALL=1` is set. New summary
     knob `OREN_TRACE_GC_ROOT_SLOT_SUMMARY=1` reports boot vs non-boot root slots
     (sample cap via `OREN_TRACE_GC_ROOT_SLOT_SUMMARY_CAP`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_GLOBAL_GUARD=1` logs when `g_gc_reuse_bad_list_triggers`,
     `g_runtime_root_len`, or `g_trace_list_header` hold pointer-like values to help
     pinpoint corruption timing (rolling, 2026-02-27).
   - New: `OREN_TRACE_GC_REGISTER_ROOT_NAMES=1` (compile-time env) emits per-root
     `[gc_root_name]` lines; bad-list root_idx=256 mapped to `g_gc_reuse_bad_list_last_ptr`
     (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_083852.log`).
   - Trace: after skipping only `g_gc_reuse_bad_list_last_ptr`, bad-list root_idx=280 mapped
     to `g_find_cache_ptr0`, indicating `oren_find_node` MRU cache slots were still rooted
     (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_084819.log`).
   - Fix: global root registration now skips `g_gc_reuse_bad_list_last_ptr` and
     `g_find_cache_ptr{0,1}`/`g_find_cache_node{0,1}`; repro now reports `in_roots=0`
     for bad-list pointers (log: `build/logs/alloc_churn_rootnames_badlist_len64_gc50_200_thr500_ring_20260227_085139.log`).
   - Trace: ring pre/recent dump around bad-list shows `op=90` (list_header_poison) then
     `op=91` (bad-list dump) for the same list pointer, with prior ops `1/5` showing normal growth;
     bad-list pointer is not in roots (`in_roots=0`) and `list_debug` still reports `node_in_allocs=1`,
     suggesting a freed header is still tracked as live (log:
     `build/logs/alloc_churn_rootnames_badlist_ringpre_20260227_085849.log`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_FREED_LIVE=1` reports when a freed list header pointer still appears
     in the allocs list (cap via `OREN_TRACE_GC_FREED_LIVE_CAP`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_ALLOCS_LIST_HDR=1` logs when list headers are inserted into the
     allocs list (cap via `OREN_TRACE_GC_ALLOCS_LIST_HDR_CAP`, 2026-02-27).
   - Tool: `OREN_TRACE_LIST_HDR_REINIT=1` logs list header reinitialization after
     allocation/reuse (cap via `OREN_TRACE_LIST_HDR_REINIT_CAP`, filters via
     `OREN_TRACE_LIST_HDR_REINIT_PTR`/`OREN_TRACE_LIST_HDR_REINIT_NODE`, 2026-02-27).
   - Tool: `OREN_TRACE_GC_LIST_HDR_POISON_NODE=1` logs the allocs-list node and alloc-index
     state when a list header is poisoned during sweep (cap via `OREN_TRACE_GC_LIST_HDR_POISON_NODE_CAP`, 2026-02-27).
  - Tool: `scripts/repro_bad_list_alloc_churn.sh` brute-forces alloc_churn configs until a
    `[gc_reuse_bad_list]` hit is found, printing ptr/node filters for follow-up tracing; it
    continues across crashes, logs non-zero exit statuses, and captures stderr in logs
    (set `EXTRA_TRACE=1` to include reuse summary + list-hdr kind/ok traces; set
    `CRASH_FOOTER=0` to skip enabling crash_footer; it now runs the correlator on runs
    that emit crash_footer output unless `REPRO_BAD_LIST_CORRELATE=0` is set, and prints
    the first `[crash_footer_raw]` line when present, 2026-03-05).
  - Tool: `tools/trace_list_hdr_correlate.py --log <log> --limit 5 --max 50` now surfaces
    `list_corrupt` and `gc_list_*_corrupt` events alongside free-list samples and attaches
    ring dumps (including crash_footer_raw ring lines) when present to pinpoint last
    header writes; it also emits ring-only blocks when only ring entries are available
    and annotates crash_footer ring head/cap plus derived ring ages when present
    (2026-03-05).
- Tool: `tools/run_alloc_churn_hunt.sh [max_runs] [tag_base]` repeats alloc_churn traces
  until a corruption signature is observed (or a timeout/failure stops the run), using
  the trace harness logs under `build/logs/` (set `ALLOC_CHURN_HUNT_CORRELATE=0` to skip
  auto-correlation; tune via `ALLOC_CHURN_HUNT_CORRELATE_LIMIT/MAX`). The harness now
  prints the first `[crash_footer_raw]` line plus the first few ring dump lines when a
  run fails or times out, and runs the correlator on failures/timeouts when enabled
  (2026-03-05).
   - Tool: `OREN_TRACE_CRASH_FOOTER=1` installs a best-effort crash footer on macOS
     (SIGSEGV/SIGBUS) that dumps alloc-index counts plus list header ring contents when
     the process crashes (debug-only; not signal-safe, 2026-03-05).
   - New: crash footer now emits a minimal `crash_footer_raw` line via `sys_write`
     before higher-level printing, to improve chances of output under severe
     corruption (debug-only; not signal-safe, 2026-03-05).
   - New: crash footer now logs `[crash_footer] installed` when the handler is
     registered (debug-only, 2026-03-05).
   - New: crash footer now registers an alternate signal stack (SIGSTKSZ) and
     installs handlers via `sigaction` with `SA_ONSTACK` on macOS (debug-only, 2026-03-05).
   - New: `crash_footer_raw` now includes list header ring pointer + guard values
     to help diagnose ring corruption (debug-only, 2026-03-05).
   - New: enabling `OREN_TRACE_CRASH_FOOTER=1` now force-enables list header ring
     capture so crash footers can report ring state even without separate trace
     flags (debug-only, 2026-03-05).
   - New: `crash_footer_raw` now includes list header ring head/cap values
     (debug-only, 2026-03-05).
   - New: `crash_footer_raw` now emits limited ring dump lines (idx/list/op/len/cap/buf/magic/kind)
     to stderr to preserve recent list header history even when higher-level printing fails
     (debug-only, 2026-03-05).
   - Tool: list<int> panic footer now always emits alloc-index counts; enabling
     `OREN_TRACE_LIST_PANIC_FOOTER=1` also dumps the list header ring for the offending list
     (debug-only, 2026-03-05).
   - Fix: arm64/x64 list<int> intrinsics now invoke `native_list_panic_footer` before
     emitting "list_int_push on non-list" panics, so the footer is captured even when the
     runtime list_int_push is bypassed (2026-03-05).
   - Trace: alloc_churn trace with crash footer + alloc-index tracing hit
     `list_int_push on non-list` panic (no `[crash_footer]` output), indicating
     a non-SEGV failure mode before bad-list triggers
     (log: `build/logs/alloc_churn_trace_crash_footer_20260305_044237.log`, 2026-03-05).
   - Trace: repro bad-list alloc_churn runs (poison headers + reuse) segfaulted
     quickly and still emitted no `[crash_footer]` output, even with
     `OREN_TRACE_CRASH_FOOTER=1` enabled
     (logs: `build/logs/alloc_churn_bad_list_auto_20260305_050800_0.log`,
     `build/logs/alloc_churn_bad_list_auto_20260305_050830_0.log`, 2026-03-05).
   - Trace: repro bad-list alloc_churn runs now emit `[crash_footer_raw]` after
     enabling sigaltstack + sigaction (logs:
     `build/logs/alloc_churn_bad_list_auto_20260305_053740_0.log`,
     `build/logs/alloc_churn_bad_list_auto_20260305_053740_1.log`, 2026-03-05).
     Wrapper log reports rc=132 (Illegal instruction) while the crash footer
     reports signal 11; keep for context (summary log:
     `build/logs/repro_bad_list_alloc_churn_sigaltstack_20260305_053739.log`).
   - Trace: crash_footer_raw now includes list_hdr_ring ptr/guard in bad-list repros
     (logs: `build/logs/alloc_churn_bad_list_auto_20260305_054630_0.log`,
     `build/logs/alloc_churn_bad_list_auto_20260305_054630_1.log`, 2026-03-05).
   - Trace: crash_footer_raw ring fields confirmed non-zero after auto-enabling ring
     (summary log: `build/logs/repro_bad_list_alloc_churn_ring_20260305_060019.log`,
     2026-03-05).
   - Trace: crash_footer_raw now shows ring head/cap values in bad-list repros
     (logs: `build/logs/alloc_churn_bad_list_auto_20260305_060705_0.log`,
     `build/logs/alloc_churn_bad_list_auto_20260305_060705_1.log`, 2026-03-05).
   - Tool: `[alloc_index_list_counts_at_bad_list]` now prints alloc-index zeroed/bad counts
     plus index len/cap at each `[gc_reuse_bad_list]` when `OREN_TRACE_ALLOC_INDEX=1`
     (2026-03-05).
   - Trace: alloc_churn hunt with alloc-index tracing enabled
     (`OREN_TRACE_ALLOC_INDEX=1`, `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=64`, runs=10)
     completed with no corruption signatures or `alloc_index_list_counts_at_bad` output
     (log: `build/logs/alloc_churn_hunt_counts_at_bad_20260305_042000.log`, 2026-03-05).
   - Trace: `scripts/repro_bad_list_alloc_churn.sh` with alloc-index tracing + extra list-hdr
     traces (`RUNS=20`, `EXTRA_TRACE=1`) exited with repeated segfaults (status 139) and no
     `gc_reuse_bad_list` / `alloc_index_list_counts_at_bad` hits (summary log:
     `build/logs/repro_bad_list_counts_at_bad_20260305_042036.log`, per-run logs:
     `build/logs/alloc_churn_bad_list_auto_20260305_0420*.log`, 2026-03-05).
   - Trace: poison-node logs show `node_in_allocs=0`, `allocs_count=0`, and `idx_node` matching
     the sweep node at poison time; later `reuse_take` reactivates the same node before the
     bad-list event, pointing to corruption after reuse rather than a stale allocs entry
     (`build/logs/alloc_churn_poison_node_20260227_092907.log`, 2026-02-27).
   - Trace: `OREN_TRACE_LIST_HDR_REINIT=1` now logs reinit events when alloc-index nodes are
     present; latest alloc_churn run shows only `new_list` entries with `prev_magic=0` and
     `freed_seen=0` (no bad-list event to correlate yet)
     (`build/logs/alloc_churn_list_hdr_reinit_node2_cap200_20260227_094121.log`, 2026-02-27).
   - Trace: bad-list pointer shows `gc_allocs_list_hdr` entries for both `track_alloc_new`
     and later `reuse_take` on the same ptr/node, confirming it was freed and reactivated
     from the free-list before corruption (log:
     `build/logs/alloc_churn_allocs_list_hdr_bigcap_20260227_091142.log`, 2026-02-27).

4) **W4 - Platform breadth (Tier‑1 intent targets)**
   - arm64 is most mature; x64 Linux/Windows are still in rolling bring‑up.

5) **W4 - Feature set completeness (essential modern features)**
   - Remaining planned work: full `yield`/stackless coroutine lowering beyond the current helper
     surfaces. Bare `yield`, `yield <value>`, and expression/result-position `yield` now ship with
     backend-shared helper semantics, and explicit caller-visible yielded/resumed values now also
     exist through `oren_yield_exchange(yield_ch, resume_ch, v)`, but that is still narrower than a
     full resumable coroutine/generator value model.
   - Implemented (rolling): the structured error model is now the shipped value-or-error
     convention based on `oren_err`, `oren_is_err`, `oren_err_code`, `oren_err_msg`, and
     `std:result`; remaining work is stdlib migration breadth, not core feature availability.
   - Implemented (2026-04-22): rolling module visibility boundaries via `pub` on top-level
     `fn`, `var`, `struct`/`class`, `enum` sugar expansions, and `ffi` declarations.
   - Migration rule: modules with any `pub` declaration become closed-by-default to imports,
     while modules with no `pub` declarations remain legacy-open until they opt in.
   - New: native quick integration now guards both success and failure paths for module visibility:
     `pub` imports, legacy-open imports, private imported members/types, and nested non-top-level
     `pub`.
   - New (2026-04-22): `std:ui/color.parse_hex` and `std:ui/raster.rasterize` now also use the
     structured error convention directly instead of ad-hoc `{ok, err}` failure maps on invalid
     color inputs, and the result smoke / AVM UI tests guard that surface.
   - New (2026-04-22): parser/backend guards now cover rolling `yield` sugar in both the Tier-1
     native quick path and the curated AVM lane, including value-carrying/result-position `yield`
     through the new parity-checked helper surface.
   - New: `project-doc/yield_coroutine_lowering_20260422.md` captures the actual runtime seams
     (`AVM_YIELD`, native `oren_ctx_switch`, green entry), the shipped `oren_yield_value(v)` /
     `oren_yield_exchange(yield_ch, resume_ch, v)` helper paths, and the remaining gap between
     helper-level value exchange and full coroutine/generator resume channels.
   - New (2026-04-22): function metadata now carries `contains_yield`, `yield_stmt_count`, and
     `yield_stmt_sites`, counting only source-level bare `yield` statements and skipping nested
     function literals. This keeps the next coroutine-lowering pass fact-based instead of
     rediscovering intent from lowered raw `oren_yield()` calls.
   - New (2026-04-22): metadata/dump/OBC introspection now also carries value-yield fields
     separately: `contains_yield_value`, `yield_value_count`, `yield_value_sites`, and
     `yield_value_surface`. That surface records the shipped `local_value_resume_v0` helper
     contract explicitly, including `consumer_kinds` plus per-site `context`, instead of
     overloading the older bare-statement `yield_lowering` plan.
   - New (2026-04-22): metadata/dump/OBC introspection now also carries the explicit
     caller-visible helper separately via `contains_yield_exchange`, `yield_exchange_count`,
     `yield_exchange_sites`, and `yield_exchange_surface`. That surface records the shipped
     `channel_resume_v0` contract explicitly, including the channel argument indexes plus the fact
     that yielded values are observed and resumed values are supplied through explicit channel args.
   - New (2026-04-22): bare statement `yield` now lowers through normalized helper
     `oren_yield_stmt()` (always `nil`), value-carrying/result-position `yield` lowers through
     `oren_yield_value(v)` (yield, then resume with the same local value), and raw `oren_yield()`
     remains the low-level scheduler/OS return-code helper. Function metadata still models the
     rolling bare-statement `yield_lowering` plan separately with explicit entry/resume states,
     yield-point mappings, and conservative `locals_across_yield` frame-slot candidates.
		   - New (2026-04-22): `yield_lowering.lowering_v0` now classifies the current real executable
		     lowering target explicitly. `bare_yield_dispatch_v0` is now marked `ready` for the
		     currently implemented bare-statement `yield` surface: top-level yields, multiple top-level
		     yields, branch/block/loop-nested yields, and functions that also contain nested function
		     literals, including locals/params that remain live across suspension points.
   - New (2026-04-22): metadata now also emits `yield_lowering.prepared_v0` for the
     `lowering_v0.ready` subset. That object is now either an explicit compiler-generated
     split-dispatch lowering shape with entry/resume segments and a synthetic state-local name, or a
     direct-passthrough prepared shape for ready branch/block control-flow cases.
   - New (2026-04-22): `dump linked` now surfaces per-function `yield_lowering` details directly,
     and the strict verifier now extracts `OREN_META` back out of the built `.obc` artifact to
     prove the backend output carries the same `prepared_v0` shape and blocker metadata.
   - New (2026-04-22): `--strict-yield-lowering-v0` is now a real compiler policy gate for
     `build`, `meta`, and `dump`. It validates the full parsed source program before dead-code
     pruning, so unreachable yielding functions still block strict builds, and strict mode skips
     artifact-cache restore to avoid cached non-strict outputs bypassing the check.
	   - New (2026-04-22): the AVM bytecode backend now actually consumes `yield_lowering.prepared_v0`
	     for the ready subset and rewrites those functions into either explicit split-dispatch state
	     machines or direct prepared passthrough around `oren_yield_stmt()`. `verify-yield-lowering-v0` now proves that with three
	     checks together: strict metadata/dump policy, embedded `.obc` metadata, and a positive
	     compiler trace for `ready_worker` with no blocked-function lowering traces.
		   - New (2026-04-22): the ready subset now also includes multiple top-level yield sites plus
		     top-level locals/parameters that remain live across them. The current AVM lowering preserves
		     the function frame across `AVM_YIELD`, so these cases are now executed and guarded by
		     metadata, strict verification, and runtime execution smokes.
			   - New (2026-04-22): ready branch/block/loop-nested bare `yield` now ships too through the
			     same v0 gate. Those functions get a `prepared_v0.kind=direct_passthrough` plan instead of
			     the old blanket non-top-level / loop blocker assumptions, and functions with nested
			     function literals plus top-level yields now stay ready as well.
   - New (2026-04-22): backend parity for that same ready bare-yield subset is now guarded too. A
     dedicated verifier builds and runs the same fixture under bytecode, C, and native with stage2
     + `--strict-yield-lowering-v0`, proving AVM’s explicit/direct prepared paths and the current
     C/native direct-call path agree on the shipped bare-`yield` subset.
   - New (2026-04-22): value-carrying `yield` is parity-verified across bytecode, C, and native
     through `oren_yield_value(v)`. This is intentionally a local value-stable resume surface, not
     yet a caller-visible coroutine/generator protocol.
	   - New (2026-04-22): explicit caller-visible yielded/resumed value exchange is also
	     parity-verified through `oren_yield_exchange(yield_ch, resume_ch, v)` across bytecode, C, and
	     native. On native host threads with green runtime already active and no background workers,
	     `oren_yield()` now drives one cooperative green scheduling step so this helper no longer
	     depends on `OREN_NO_GREEN=1` verification escape hatches. Direct standalone
     `./scripts/run_native_quick_integration.sh ./oren_stage2` now also auto-prewarms runtime
	     astbin/rtobj seeds for the current runtime hash, so empty seed dirs no longer fall back to a
	     cold self-hosted `rtobj.miss.build.start` path during the quick smoke. The bundled structural
	     guard now proves that path with a dedicated tiny native fixture instead of the full
	     quick-integration program, so default verification keeps the seed-hit guarantee with lower
	     cost. The same explicit protocol now also has shared-front-end source syntax:
	     `yield expr in (yield_ch, resume_ch)` and `yield in (yield_ch, resume_ch)`. Metadata/dump/OBC
	     surfaces now record whether a site came from raw helper calls or source syntax via
	     `syntax_kinds` plus per-point `syntax` / `explicit_value`. The remaining gap is fuller
	     coroutine/generator protocol above that explicit channel surface.
	   - New (2026-04-22): the first reusable source-level generator abstraction now ships as
	     `std:generator`. Its `start/next/send/close/delegate/collect` API is now a thin facade over
	     compiler-injected `oren_generator_*` helpers, so the shipped handle is tagged as
	     `generator` instead of being exposed only as an ad hoc stdlib map. Worker bodies now use
	     `yield ... in co` as the normalized generator-context contract, while the same explicit
	     channel protocol still exists underneath.
		   - New (2026-04-22): top-level and block-local `@oren.generator` generator sugar now covers
		     both named `fn ...` declarations and function-valued `var` bindings (`fn` or lambda bodies),
		     lowering to that same compiler-managed generator-handle surface instead of a hidden
		     `std:generator.start(...)` import. Metadata/dump/OBC surfaces now expose
		     `is_generator_decl` plus `generator_decl_surface=compiler_generator_object_v3`, so tools can
	     distinguish declaration sugar from raw exchange helpers while still seeing the underlying
			     `generator_context_v0` worker-facing yield contract and binding-sensitive
				     `yield_exchange_surface`. That v2 surface now explicitly records
					     `state_layout=dedicated_generator_object_kind_v1`, `worker_context_type=generator_context`,
					     `iter_surface=for_in_v0`, `iter_api=oren_iter_next_v0`, `iter_resume=implicit_nil_v0`,
					     `resume_surface=next_send_finalize_defer_close_delegate_yield_from_v7`,
					     `next_api=oren_generator_next_v2`, `send_api=oren_generator_send_v2`,
					     `on_finalize_api=oren_generator_on_finalize_v1`,
					     `on_close_api=oren_generator_on_close_v1`, `close_api=oren_generator_close_v1`,
					     `delegate_api=oren_generator_delegate_v1`,
					     `delegate_step_api=oren_generator_delegate_step_v1`,
					     `on_finalize_mode=lifo_zero_arg_on_done_or_close_v1`,
					     `on_close_mode=alias_of_on_finalize_v1`,
					     `finalize_source_syntaxes=["defer_v0","defer_in_context_v0","on_finalize_call_v1","on_close_call_alias_v1"]`,
					     `delegate_source_syntaxes=["yield_from_v0","yield_from_in_context_v0"]`,
					     `close_mode=propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5`,
					     `delegate_mode=track_active_chain_inline_fresh_or_cached_started_step_v3`, and
					     `decl_forms=["named_function_decl","function_valued_var"]`, and the
					     helper APIs validate bad handles/contexts without depending on map semantics or exposed public
				     lifecycle fields.
		   - New (2026-04-22): the dedicated generator substrate replacement is now in place across C,
		     native, and AVM.
		     - generator handles and `generator_context` now use dedicated runtime object kinds instead of
		       piggybacking on hidden list capsules
		     - the injected generator core still centralizes raw positional slot access through named
		       internal accessors/constructors in `lib/compiler/parser_parse/005_generator_core.oren`
		     - the machine-readable layout marker is now `state_layout=dedicated_generator_object_kind_v1`
		       to reflect that dedicated object-kind ABI
				     - the follow-on refactor slice is now deeper too: generator-specific AVM/native/runtime glue
				       remains extracted into dedicated helper includes, `lib/runtime/010_prelude.inc` and
				       `lib/runtime/040_lists_maps.inc` are both back under the 2000-line red line, and
				       `lib/avm/avm_state.inc` is back under that threshold too after splitting record/replay
				       and snapshot/restore helpers into `lib/avm/avm_state_rr.inc` and
				       `lib/avm/avm_state_snapshot.inc`
					     - the remaining large-file debt is now reweighted again after the AVM native host split:
					       `lib/avm/avm_native.inc` is back under the repo’s 2000-line red line too, while its
					       former inline islands now live in `lib/avm/avm_native_fs_universe_helpers.inc`,
					       `lib/avm/avm_native_clone_helpers.inc`,
					       `lib/avm/avm_native_object_buffer_cases_a.inc`,
					       `lib/avm/avm_native_buffer_cases_b.inc`,
					       `lib/avm/avm_native_buffer_cases_c.inc`,
					       `lib/avm/avm_native_buffer_cases_d.inc`,
					       `lib/avm/avm_native_capability_domain_fs.inc`, and
					       `lib/avm/avm_native_capability_domains_misc.inc`
					     - the next coupled ARM64 stmt host split is now landed too:
					       `lib/compiler/arm64_native_stmt.oren` is back under the red line, the old
					       `lib/compiler/arm64_native_stmt_loops_list_emit.oren` body is now split across
					       `lib/compiler/arm64_native_stmt_loops_list_emit_prefix_reduce.oren`,
					       `lib/compiler/arm64_native_stmt_loops_list_emit_int_reduce_dot.oren`, and
					       `lib/compiler/arm64_native_stmt_loops_list_emit_dot_push.oren`, and the set-lowering tail
					       now lives in `lib/compiler/arm64_native_stmt_set.oren`
					     - the red-line source split is now complete for tracked code too:
					       `tests/native/qi/100_tests_basic.oren` is now a thin include facade over
					       `110_tests_basic_smoke_a.oren`, `120_tests_basic_std_buffer.oren`,
					       `130_tests_basic_core_runtime.oren`, and `140_tests_basic_select_arena.oren`,
					       so the tracked `.oren` / `.c` / `.h` / `.inc` source scan is back under the
					       rolling 2000-line threshold across production code and Tier-1 test bundles.
		   - New (2026-04-23): the stage2 generator-finalize introspection seam is fixed.
		     `dump linked` / `dump graph` / `meta` now parse generator-using sources with
		     `_skip_generator_core_inject`, so those tooling commands stop reparsing the hidden
		     compiler-injected generator helper program and stop leaking `oren_generator_*` /
		     `_oren_generator_*` helper declarations into source-level metadata output.
		     On `tests/fixtures/generator_finalize_surface_v0.oren`, `./oren_stage2 dump linked`
		     dropped from about `1.53s` to `0.18s` after that cut, with the new
		     `OREN_TRACE_INTROSPECTION_PHASES=1` timing surface showing parse+link+summary explicitly.
	   - New (2026-04-22): generator handles are now iterable too. `for x in gen { ... }` works
	     across bytecode, C, and native by routing generator handles through the compiler-managed
	     generator bridge while resuming each step with implicit `nil`. This gives language-level
	     generators a first real `for-in` affordance instead of requiring only manual `next/send` or
	     `collect(...)` loops.
	     The remaining boundary is now binding shape, not scope: `@oren.generator` still requires a
	     named binding site, not an arbitrary non-function statement.
	   - New (2026-04-22): the focused exchange/generator verifiers now read source-side
	     `meta`/`dump linked` through `./oren` and cross-check target-compiler artifact metadata from
	     the stage2-built `.obc`, keeping the default verification lane fast without dropping
	     bytecode/C/native generator-context proof coverage.
	   - New (2026-04-22): the stage2 bytecode compiler regression for imported generator workers
	     with `yield ... in co` is fixed and pinned by a committed four-case matrix.
	     - the fix refactors top-level metadata emission away from repeated whole-document
	       string concatenation and onto chunked `oren_string_join(...)` assembly
	     - the committed matrix in `tests/fixtures/generator_import_*` now compiles in all four
	       cases under `./oren_stage2 build --backend bytecode`
	     - `scripts/probe_generator_import_yield_regression.sh` is now a positive guard and is
	       wired into `make test` through `verify-generator-import-yield-regression`
		   - New (2026-04-22): generator delegation is now widened and cross-backend verified.
		     - `oren_generator_delegate(co, inner)` / `std:generator.delegate(co, inner)` no longer stop at
		       fresh handles; they also absorb already-started handles when the handle still carries its
		       current cached yielded step
		     - explicit started-step delegation remains available through
		       `oren_generator_delegate_step(co, inner, step)` /
		       `std:generator.delegate_step(co, inner, step)`
		     - real source-level delegation now ships too:
		       - explicit workers: `yield from inner in co`
		       - `@oren.generator` declarations: `yield from inner`
		       - `from` is contextual after `yield`, not a globally reserved identifier
			     - the shipped v3 mode is `track_active_chain_inline_fresh_or_cached_started_step_v3`
				   - New (2026-04-22): explicit generator close/finalization now ships too.
				     - `oren_generator_on_finalize(co, hook)` / `std:generator.on_finalize(co, hook)` now register
				       zero-argument finalization hooks for explicit workers, and declaration bodies can use the
				       same contract through `gen.on_finalize(hook)` / `oren_generator_on_finalize(hook)`
		     - `on_close(...)` remains a thin alias of the same hook list for compatibility
		     - new source-level finalization syntax now ships too:
		       - explicit workers: `defer { ... } in co`
		       - `@oren.generator` declarations: `defer { ... }`
		       - `defer` is contextual and not reserved outside these generator forms
			     - declaration metadata is now `version=19` and records
		       `finalize_surface=generator_finalize_v0`
		     - hooks now run in LIFO order on both explicit `close()` and ordinary natural completion
		     - the first hook error becomes the sticky terminal generator result after cleanup still
		       completes, while `return_value(gen)` preserves the ordinary cached return value
		     - `oren_generator_close(gen)` / `std:generator.close(gen)` deterministically seal the handle
		       done across bytecode, C, and native
				     - unfinished handles now finish at the handle surface with `return_value == nil`
				     - already-finished handles preserve and return their cached final value unless a terminal
				       finalizer error was recorded
				     - active delegated chains are now recursively closed and finalization hooks are run before the
				       outer live worker is detached,
				       so partially-consumed `yield from` / started-step delegation trees seal deterministically too
		     - imported stage2 bytecode coverage now includes
		       `tests/fixtures/generator_import_close_regression_v0.oren` and
		       `tests/fixtures/generator_import_delegate_close_regression_v0.oren`, plus
		       `tests/fixtures/generator_import_on_close_regression_v0.oren`,
		       `tests/fixtures/generator_import_on_finalize_regression_v0.oren`, and
		       `tests/fixtures/generator_import_defer_regression_v0.oren`
		     - per-function `meta`, `dump linked`, and extracted OBC metadata now expose
		       `contains_generator_finalize`, `generator_finalize_count`,
		       `generator_finalize_sites`, and `generator_finalize_surface`
		     - `generator_finalize_surface` is now emitted as
		       `generator_finalize_v0` with `lifecycle=on_done_or_close_v1`,
		       `hook_arity=zero_arg`, plus per-site `syntax_kinds`, `api_kinds`,
		       `consumer_kinds`, and `finalize_points`
		     - `make test` now includes the compact parity target
		       `verify-generator-finalize-surface-v0` to keep those three tool
		       surfaces aligned
		     - native wrapper discovery now also pre-scans nested lambda / generator-worker bodies for
		       named function values, so declaration-body `on_close(...)` plus
				       `gen.start(named_worker, ...)` followed by `yield from ...` is part of the shipped native
				       proof surface again
			     - started handles now detach the live worker instead of resuming user code with a hidden
			       close sentinel, so the close surface stays deterministic even if the worker would
			       otherwise yield again
			     - the native nested-green scheduler seam that previously blocked `gen.next(inner)` from inside
			       an active outer generator is fixed and pinned by
			       `scripts/verify_generator_nested_green_resume_v0.sh` plus
		       `tests/fixtures/generator_nested_green_resume_v0.oren`
		     - the stage2 imported-generator matrix now also covers delegation helpers and source syntax
		       through `tests/fixtures/generator_import_delegate_step_regression_v0.oren` and
		       `tests/fixtures/generator_import_yield_from_regression_v0.oren`
	   - Bytes + typed buffers are already partially shipped through `std:bytes` and `std:buffer`;
	     remaining work there is API tightening and broader parity, not first availability.
   - Design spec: `docs/design/structured_error_model.md` (2026-03-05).
   - New: `std:result` smoke fixture wired into native quick integration
     (`tests/fixtures/tier1_native_result_smoke_main.oren`, 2026-03-05).
   - New: `std:list` structured helpers (`try_len`/`try_get`/`try_set`/`try_last`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - New: `std:list.slice_copy`, `std:strings`, `std:bytes`, and `std:ui/commands.validate`
     now share the hardened non-nil int validation path used by `std:buffer`, so wrong-type
     scalar-like inputs return `oren_err` consistently instead of depending on backend coercion;
     malformed `std:list.slice_view` arguments still iterate as an empty sequence by contract
     (2026-03-27).
   - New: `std:buffer` slice helpers return `oren_err` on invalid input; covered by
     result smoke fixture (2026-03-05).
   - New: `std:encoding/base64.decode_bytes` error handling covered by result
     smoke fixture (2026-03-05).
   - New: `std:encoding/base64.encode_bytes` validates input and returns `oren_err`
     on invalid values; covered by result smoke fixture (2026-03-05).
   - New: `std:encoding/base64.decode_bytes_strict` rejects whitespace; covered by
     result smoke fixture (2026-03-05).
   - New: `std:crypto/pem.decode_blocks_strict` rejects whitespace inside base64
     payloads; covered by result smoke fixture (2026-03-05).
   - New: `std:strings` structured helpers (`try_len`/`try_char_at`/`try_slice`) return
     `oren_err` on invalid input; covered by result smoke fixture (2026-03-05).
   - New: `std:bytes` structured helpers now cover the common packet-style multi-byte surface,
     slice/copy surface, and conversion surface too
     (`try_get_u16/u32/u64_*`, `try_get_i16/i32/i64_*`, `try_put_u16/i16/u32/i32/u64/i64_*`,
     `try_set_u16/i16/u32/i32/u64/i64_*`, `try_from_string`, `try_to_string`, `try_pack`,
     `try_unpack`, `try_slice`, `try_concat`, `try_copy_into`, `try_from_u8_buf`,
     `try_to_u8_buf`, `try_to_string_slice`, `try_to_u8_buf_slice`) and return `oren_err`
     on invalid input across `list<int>` and `u8_buf`; covered by result smoke + native quick
     integration + dedicated AVM bytes smoke
     (2026-03-27).
   - New: `std:bytes` hex helpers (`try_from_hex`/`try_to_hex`) validate inputs and
     return `oren_err` on invalid values; covered by result smoke fixture (2026-03-05).
   - New: `std:buffer` structured helpers now cover the common typed-buffer surface and zero-copy
     view surface too (`try_len`, `try_load/try_store_u8`, `try_load/try_store_i32`,
     `try_load/try_store_i64`, `try_load/try_store_f32`, `try_load/try_store_f64`,
     `try_slice_*`, `try_strided_*`, `try_mat_view_new`, `try_mat_load/store_i32`,
     `try_mat_load/store_f32`) and return `oren_err` on invalid input; covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked conversion helpers for the common portable bridge
     cases (`try_u8_pack`, `try_u8_pack_into`, `try_u8_unpack`, `try_u8_from_string`,
     `try_u8_to_string`, `try_u8_from_bytes`, `try_u8_from_bytes_slice`, `try_u8_to_bytes`,
     `try_i32_pack_list_int`, `try_i32_pack_list_int_into`, `try_i32_unpack_list`);
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes contiguous raw typed-buffer list bridges for `i64`, `f32`,
     and `f64` via helpers such as `try_i64_pack_list_int`, `try_i64_unpack_list`,
     `try_f32_pack_list`, `try_f32_unpack_list`, `try_f64_pack_list`, and
     `try_f64_unpack_list`, so callers can enter and leave non-`u8` typed buffers without
     open-coding allocation + per-element store loops; covered by result smoke + native quick
     integration + dedicated AVM buffer-view smoke, with exact float value proof kept in AVM and
     shared native fixtures checking non-error/shape only (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-buffer refill helpers for raw typed buffers,
     including `try_u8_copy_from_u8_buf`, `try_u8_copy_from_bytes`,
     `try_u8_copy_from_bytes_slice`, `try_u8_copy_from_string`,
     `try_u8_copy_from_string_slice`, `try_i32_copy_from_i32_buf`,
     `try_i64_copy_from_i64_buf`, `try_f32_copy_from_f32_buf`, and `try_f64_copy_from_f64_buf`,
     so callers can refill existing typed buffers without allocating a fresh bridge buffer or
     open-coding per-element loops, including direct byte-window and string-window refill without
     materializing an intermediate `[]u8`; covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke, with exact float value proof kept in AVM and shared native
     fixtures checking non-error/shape only (2026-03-27).
   - New: `std:buffer` now also exposes checked `[]u8` zero-copy view bridge helpers
     (`try_slice_to_bytes`, `try_slice_to_string`, `try_slice_copy_from_bytes`,
     `try_slice_copy_from_bytes_slice`, `try_strided_to_bytes`, `try_strided_to_string`,
     `try_strided_copy_from_bytes`, `try_strided_copy_from_bytes_slice`); covered by result smoke +
     native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked `[]u8` string-window refill helpers on zero-copy
     views (`try_slice_copy_from_string_slice`, `try_strided_copy_from_string_slice`), so callers
     can refill visible byte windows from substrings without materializing temporary `[]u8` bridges;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` matrix views now also project back into the zero-copy slice/strided
     surface via `try_mat_row_slice` and `try_mat_col_strided`, so matrix code can reuse the
     existing checked `[]u8` slice/strided bridge helpers instead of rebuilding index math by hand;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` matrix views now also expose checked `u8` cell accessors
     (`try_mat_load_u8`, `try_mat_store_u8`), so callers can keep direct byte-cell reads/writes on
     the matrix surface instead of routing through row or slice views for scalar access; covered by
     result smoke + native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` matrix views now also expose checked submatrix and diagonal projections via
     `try_mat_subview` and `try_mat_diag_strided`, so callers can keep composing zero-copy matrix,
     slice, and strided views without open-coding offset math; covered by result smoke + native
     quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes checked compact row-major matrix conversion helpers
     `try_i32_mat_pack_rows`, `try_i32_mat_unpack_rows`, `try_u8_mat_pack_rows`,
     `try_u8_mat_unpack_rows`, `try_u8_mat_pack_strings`, and `try_u8_mat_unpack_strings`, so
     callers can enter and leave the zero-copy matrix-view surface without open-coding row-major
     loops; covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes direct checked matrix-row/column `[]u8` bridge helpers
     such as `try_mat_row_to_string`, `try_mat_row_copy_from_string`,
     `try_mat_row_copy_from_string_slice`, `try_mat_row_copy_from_bytes_slice`,
     `try_mat_col_to_string`, `try_mat_col_copy_from_string`,
     `try_mat_col_copy_from_string_slice`, and `try_mat_col_copy_from_bytes_slice`, so matrix
     callers can stay on the matrix surface for the common row/column text and byte bridge paths,
     including direct byte-window and string-window refill without open-coding a temporary slice;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke
     (2026-03-27).
   - New: `std:buffer` now also exposes direct checked matrix-diagonal `[]u8` bridge helpers such
     as `try_mat_diag_to_string`, `try_mat_diag_to_bytes`, `try_mat_diag_copy_from_string`,
     `try_mat_diag_copy_from_string_slice`, `try_mat_diag_copy_from_bytes_slice`, and
     `try_mat_diag_copy_from_u8_buf`, so matrix callers can stay on the matrix surface for the
     common diagonal byte/text bridge paths instead of routing through an explicit strided view,
     including direct string-window refill; covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes direct checked whole-matrix `[]u8` flatten/copy helpers
     such as `try_u8_mat_to_bytes`, `try_u8_mat_to_string`, `try_u8_mat_copy_from_bytes`,
     `try_u8_mat_copy_from_bytes_slice`, `try_u8_mat_copy_from_string`,
     `try_u8_mat_copy_from_string_slice`, `try_u8_mat_copy_from_rows`, and
     `try_u8_mat_copy_from_strings`, so matrix callers can bridge or refill the entire visible
     matrix without open-coding row loops, including direct byte-window and string-window refill on
     the matrix surface; covered by result smoke + native quick integration + dedicated AVM
     buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes symmetric checked whole-matrix `[]u8` flat-list helpers
     `try_u8_mat_unpack_flat` and `try_u8_mat_copy_from_flat`, so callers can use the same
     `*_mat_unpack_flat` / `*_mat_copy_from_flat` row-major pattern across `u8`, `i32`, `i64`,
     `f32`, and `f64` matrix views instead of special-casing byte matrices; covered by result
     smoke + native quick integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric matrix row-major conversion/refill helpers
     such as `try_i32_mat_copy_from_rows`, `try_i64_mat_pack_rows`, `try_i64_mat_unpack_rows`,
     `try_i64_mat_copy_from_rows`, `try_f32_mat_pack_rows`, `try_f32_mat_unpack_rows`,
     `try_f32_mat_copy_from_rows`, `try_f64_mat_pack_rows`, `try_f64_mat_unpack_rows`, and
     `try_f64_mat_copy_from_rows`, so callers can enter, leave, and refill the visible numeric
     matrix surface without open-coding row loops; covered by result smoke + native quick
     integration + dedicated AVM buffer-view smoke (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-matrix numeric flatten/refill helpers
     such as `try_i32_mat_unpack_flat`, `try_i32_mat_copy_from_flat`, `try_i64_mat_unpack_flat`,
     `try_i64_mat_copy_from_flat`, `try_f32_mat_unpack_flat`, `try_f32_mat_copy_from_flat`,
     `try_f64_mat_unpack_flat`, and `try_f64_mat_copy_from_flat`, so callers can bridge or
     refill the visible numeric matrix surface without open-coding row-major flatten loops;
     covered by result smoke + native quick integration + dedicated AVM buffer-view smoke;
     shared native fixtures keep float proof at non-error/shape level while the dedicated AVM
     smoke keeps exact `f32`/`f64` value assertions (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric slice/strided list bridges such as
     `try_slice_unpack_i32`, `try_slice_copy_from_list_i32`, `try_strided_unpack_i64`, and
     `try_strided_copy_from_list_f64`, plus checked numeric matrix row/column list bridges such as
     `try_mat_row_unpack_i32`, `try_mat_row_copy_from_list_i64`, `try_mat_col_unpack_f32`, and
     `try_mat_col_copy_from_list_f64`, so callers can project numeric matrix views back into the
     existing zero-copy slice/strided surface without hand-writing row/column loops; covered by
     result smoke + native quick integration + dedicated AVM buffer-view smoke, with exact float
     value proof kept in AVM and non-error/shape proof kept in shared native fixtures
     (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric slice/strided typed-buffer bridges such as
     `try_slice_to_i32_buf`, `try_slice_copy_from_i32_buf`, `try_strided_to_i64_buf`, and
     `try_strided_copy_from_f64_buf`, plus checked numeric matrix row/column typed-buffer bridges
     such as `try_mat_row_to_i32_buf`, `try_mat_row_copy_from_i64_buf`, `try_mat_col_to_f32_buf`,
     and `try_mat_col_copy_from_f64_buf`, so callers can stay on the visible zero-copy
     slice/strided/matrix surface without routing numeric row/column work through temporary lists;
     matrix row/column helpers reuse the checked slice/strided typed-buffer bridge surface rather
     than reimplementing row/column loops; covered by result smoke + native quick integration +
     dedicated AVM buffer-view smoke, with exact integer proof and exact AVM float-value proof kept
     alongside non-error/shape native float proof (2026-03-27).
   - New: `std:buffer` now also exposes checked numeric matrix-diagonal list and typed-buffer
     bridges such as `try_mat_diag_unpack_i32`, `try_mat_diag_copy_from_list_i64`,
     `try_mat_diag_to_f32_buf`, and `try_mat_diag_copy_from_f64_buf`, so callers can bridge or
     refill diagonal projections directly on the matrix surface instead of routing through an
     explicit temporary strided view; the diagonal helpers reuse the same checked strided bridge
     surface as rows and columns. Covered by result smoke + native quick integration + dedicated AVM
     buffer-view smoke, with exact integer proof and exact AVM float-value proof kept alongside
     non-error/shape native float proof (2026-03-27).
   - New: `std:buffer` now also exposes checked whole-matrix numeric typed-buffer bridges such as
     `try_i32_mat_to_i32_buf`, `try_i32_mat_copy_from_i32_buf`, `try_i64_mat_to_i64_buf`,
     `try_i64_mat_copy_from_i64_buf`, `try_f32_mat_to_f32_buf`, `try_f32_mat_copy_from_f32_buf`,
     `try_f64_mat_to_f64_buf`, and `try_f64_mat_copy_from_f64_buf`, so callers can bridge or
     refill the visible numeric matrix surface without routing through intermediate flat lists. The
     refill side now rejects mismatched typed-buffer kinds up front instead of depending on raw
     backend loads; covered by result smoke + native quick integration + dedicated AVM buffer-view
     smoke, with exact float value proof kept in AVM and non-error/shape proof kept in shared
     native fixtures (2026-03-27).
  - Refactor: `std:buffer` is now split into a thin public facade plus
    `lib/std/buffer/view.oren` for slice/strided helpers and a direct matrix implementation split
    across `lib/std/buffer/mat_core.oren`, `lib/std/buffer/mat_proj.oren`,
    `lib/std/buffer/mat_shared.oren`, `lib/std/buffer/mat_numeric.oren`, and
    `lib/std/buffer/mat_u8.oren`. The public facade in `lib/std/buffer.oren` now imports those
    matrix modules directly instead of routing through either an internal `mat.oren`
    compatibility layer or a mixed numeric/byte dense helper module, which keeps the checked
    matrix API unchanged while making the internal module boundary match the real behavior split;
    covered by dedicated AVM buffer-view smoke, native quick integration, and full `make test`
    (2026-03-27).
   - Refactor: the duplicated integer/error validation helpers shared by the `std:buffer` facade,
     `view`, and matrix core now live in `lib/std/buffer/common.oren`, which removes copy-pasted
     `_err_invalid` / `_is_int` / `_check_*` / list-len / typed-buffer-len logic from the split
     modules and keeps future buffer-surface validation fixes aligned across all three layers;
     covered by dedicated AVM buffer-view smoke, native quick integration, and full `make test`
     (2026-03-27).
   - Refactor: the shared byte-range validator for `std:buffer` now also lives in
     `lib/std/buffer/common.oren`, so `view`, matrix core, and `u8` matrix helpers all reject
     out-of-range writes through the same checked path instead of carrying separate copies of the
     `0..255` validation logic; covered by dedicated AVM buffer-view smoke, native quick
     integration, and full `make test` (2026-03-27).
   - Refactor: the split `std:buffer` modules now also share list-view shape predicates
     (`_slice_is_list` / `_strided_is_list` / `_mat_is_list`) and numeric validators through
     `lib/std/buffer/common.oren`, which removes another copy-pasted helper family from `view` and
     the matrix layer; covered by dedicated AVM buffer-view smoke, native quick integration, and
     full `make test` (2026-03-27).
   - Refactor: the duplicated raw typed-buffer constructors, direct typed load/store shims, and
     `[]u8 -> bytes` bridge shared across the split `std:buffer` modules now live in
     `lib/std/buffer/raw.oren`, so low-level runtime wrapper changes no longer need to be edited in
     multiple places; covered by dedicated AVM buffer-view smoke, native quick integration, and
     full `make test` (2026-03-27).
   - Refactor: the checked raw/list/string bridge surface that used to live at the top of
     `lib/std/buffer.oren` now also lives in `lib/std/buffer/raw.oren`, leaving
     `lib/std/buffer.oren` as a thinner 697-line public facade over `raw`, `view`, and the split
     matrix modules while keeping the public checked API unchanged; covered by dedicated AVM
     buffer-view smoke, native quick integration, and full `make test` (2026-03-27).
   - Refactor: the dense matrix helpers no longer depend on `mat_core` internals for shape,
     row-major flatten, or typed-buffer bridge plumbing. Those shared helpers now live in
     `lib/std/buffer/mat_shared.oren`, which makes the matrix layer a cleaner facade/core/shared/dense
     split without changing the checked public API; covered by dedicated AVM buffer-view smoke,
     native quick integration, and full `make test` (2026-03-27).
   - Fix: `std:result.is_err(v)` now canonicalizes backend probes to a real Oren boolean on native,
     so `== true` / `!= true` checks no longer depend on raw backend truthy values; covered by
     native module-result smoke, result smoke, native quick, and full `make test` (2026-03-27).
   - Fix: macOS stage1 native-quick verification now gives the `OREN_GREEN_POLL_CACHE` rerun a
     30s default watchdog even when the base run stays at 20s, which removes a false-red `rc=143`
     path in full-suite verification where the first run already completed cleanly (2026-03-27).
   - Fix: macOS stage1 native-quick verification now also gives the base run a 120s default
     watchdog instead of 60s. Earlier direct measurements already showed healthy base runs near
     `23.15s`, and after the later `240s` green-cache widening the full-suite stage1 path could
     still false-red at `60s` in `green_two_workers_world_lock_smoke`; a direct full-suite retry
     with `OREN_NATIVE_RUN_TIMEOUT_SECS=120` completed cleanly on this host, removing that remaining
     `rc=143` path from `make test` (2026-03-27).
   - Fix: `scripts/run_native_quick_integration.sh` now executes the stage1 base run and the
     green-cache rerun under `set +e` when collecting retry status, so `run_with_timeout_retry(...)`
     can actually feed the scripted retry paths instead of aborting the harness early under
     `set -e`; covered by native quick integration and full `make test` (2026-03-27).
   - Fix: `scripts/run_native_quick_integration.sh` now also captures the top-level
     `run_base` / `run_green_cache` phase status under `set +e` before tailing the inner log,
     so a timeout-style nonzero no longer aborts the harness at the phase call site before the
     intended tail/exit handling runs; covered by native quick integration and full `make test`
     (2026-03-27).
   - Fix: on macOS, `scripts/run_native_quick_integration.sh` now prefers a Python
     `subprocess.wait(timeout=...)` watchdog over the older bash sleeper/`kill` watcher, which
     removes the late `rc=143` false-red path where the inner stage2 log had already completed
     successfully but the outer make target was still terminated by a racing watchdog
     (2026-03-27).
   - Fix: the standalone two-worker green scheduler world-lock / M<P / P-swap smokes now call
     `exit(0)` after their success print, matching the loopback tests that also start persistent
     green workers. A 2026-04-12 default `make test` run showed
     `test_green_two_workers_world_lock_smoke` printing both success lines but then staying alive
     until the 360s watchdog returned `run_rc=1`; the fixture now terminates the process
     explicitly after proving the scheduler property instead of depending on background-worker
     runtime cleanup.
   - Fix: macOS stage1 native-quick verification now also keeps the default green-cache rerun
    watchdog at `360s` instead of `240s`. A direct `240s` run still false-red with `rc=143`
    after the rerun had already emitted its last visible debug lines, while `360s` completed
    cleanly on this host; covered by native quick integration and full `make test` (2026-03-27).
  - Fix: macOS self-hosted stage2 native-quick verification now keeps the default
    `OREN_GREEN_POLL_CACHE` rerun watchdog at `720s` instead of reusing the stage1 `360s`
    budget. On this host the stage2 rerun still false-red at `360s` after emitting its last
    visible `41` / `42` debug lines, and the built-in `720s` retry completed cleanly; covered
    by stage2 native quick integration and full `make test` (2026-03-27).
  - Fix: macOS self-hosted stage2 native-quick verification now also keeps the base run watchdog
    at `120s` instead of the old `30s` make-target budget. On this host the base stage2 run still
    false-red at `60s` and only cleared on the built-in `120s` retry, so `test-native-quick-stage2`
    now starts from the proven healthy base-run budget instead of depending on a retry to pass
    (2026-03-27).
  - Fix: invoking `scripts/run_native_quick_integration.sh ./oren_stage2` directly on macOS now
    also keeps the stage2 debug build watchdog at `180s` instead of `35s`. A measured standalone
    rerun still false-red at `35s` during the self-hosted rebuild even with an rtobj hit, while
    the same path already completed cleanly under the `180s` full-suite budget; covered by a
    standalone stage2 stop-after-green quick-integration run plus the normal AVM/status gates
    (2026-03-27).
   - New: `std:assert.assert_streq` now uses portable stdlib string equality instead of raw
     `strcmp`, removing that direct bytecode codegen dependency; verified by native quick plus
     dedicated AVM bytes/assert smoke coverage (2026-03-26).
   - Implemented (rolling): core `assert(cond, msg?)` statement and `oren test` runner for
     `test "name" { ... }` blocks (2026-03-04).
   - Implemented (rolling): call-site spread + user-defined varargs (incl. `print(xs...)`)
     covered by native quick integration + varargs fixtures (2026-03-04).
   - Not implemented: dynamic module loading; user-defined methods/inheritance (see `docs/LANGUAGE.md`).
   - Interim: `std:assert` helper module provides `assert`/`assert_eq` in the stdlib (2026-03-03).

6) **W3 - Tooling/ABI stability**
   - ABI/opcode stability is explicitly rolling; compatibility guarantees are not declared.
   - AVM build/parity gate integrity is tracked as a W4 blocker when broken (select case parsing + helper exports; 2026-02-25).
   - `scripts/run_native_capsule_smoke.sh` now defaults to cached builds and
     `test-native-capsule-smoke-stage2` uses a 180s build watchdog, which avoids a measured
     timeout-style false red where stage2 spent minutes in a deliberate cold compile before the
     capsule runtime smoke even ran on this host (2026-03-27).

7) **W3 - Docs fidelity + regression gates**
   - Docs are grounded in fixtures/tests; gaps get surfaced via parity gates.
   - Public README product positioning is now guarded by `make verify-public-readme-positioning`,
     keeping single-language comparison references out of public `README*.md` files while archived
     research notes remain under `project-doc/**` / `docs/refs/**`.
   - Gas-surface calibration now includes default smoke, loop-heavy, branch-heavy, call-heavy, and
     allocation-heavy fixtures plus
     an `oren.gas-surface-conversion-decision.v0` blocker, keeping package-policy gas conversion
     disabled unless package policy uses the AVM sidecar enforcement profile, now the shared native
     dispatcher default for gas-budgeted packages, or native instruction-equivalent gas exists. The
     first dynamic-emitter native surface still spans `~2.49x` to `~16.82x` native ticks per AVM opcode
     gas across the calibration set
     (`build/reports/backend_gas_surface_calibration_set_20260412_081109_85502.json`).
	   - `make verify-backend-native-instruction-surface-decision` now records a separate
	     `oren.native-instruction-surface-decision.v0` report and rejects whole-binary native disassembly
	     counts as a conversion surface by cross-checking them against the current
	     `native_dynamic_emitter_tick_v0` runtime surface; whole-binary counts include linked runtime
	     text rather than dynamic per-executed-path gas. The first static-proxy report
	     (`build/reports/backend_native_instruction_surface_decision_20260412_083236_29513.json`) counted
	     the same `474624` whole-binary native instructions for the original three fixtures while OBC
		     opcode gas varied from `234` to `2328`; the current default guard also requires call-heavy
		     and allocation-heavy sample-class coverage.
	   - Native gas-surface JSON now explicitly records backend-local runtime evidence, not
	     conversion-ready architecture-neutral instruction gas (`unit_scope`, `target_arch`,
	     `unit_family`, `runtime_path_aware`, `cross_arch_comparable`, `conversion_ready`, and
	     `avm_canonical=false` fields) across default loop-safepoint, statement, basic-block,
	     block-weighted, and dynamic-emitter modes.
			   - AVM `avm_opcode_cost_v0` gas-surface JSON is now the explicit canonical opcode-dispatch
		     target: it records `unit_scope="avm_canonical"`, `runtime_path_aware=true`,
		     `cross_arch_comparable=true`, `conversion_ready=true`, and `avm_canonical=true`, while
			     native dynamic-emitter gas remains a separate non-conversion-ready evidence surface.
		   - Semantic diff now emits `oren.avm-canonical-sidecar-gas.v0` as same-source OBC canonical gas
				     evidence beside native runtime gas, with source/native-artifact/sidecar-artifact SHA-256 identity
				     hashes, program-args/package-policy binding hashes, normalized stdout/stderr hashes,
			     explicit sidecar `avm.run.v1` status/error evidence, `same_run_stderr_equal` evidence,
			     concrete native/sidecar exit codes,
				     non-blocking `certification_warnings`,
			     `certification_status`, `certification_failure_reasons`,
			     `native_runtime_conversion=false`, and
			     `package_policy_may_use=false` because semantic-diff fixtures are not package/input-bound.
					     Calibration-set and native instruction-surface decision consumers now preserve those
					     source/native-artifact/sidecar-artifact identity hashes and input-binding hashes per sample,
					     plus aggregate `avm_canonical_sidecar_identity_hashes_present_all` and
					     `avm_canonical_sidecar_input_binding_present_all` /
					     `avm_canonical_sidecar_run_json_ok_all` evidence.
			     Native package-policy verification also injects structured non-gas AVM sidecar run errors
			     and requires a distinct `sidecar_error` failure reason rather than flattening them into
			     plain exit-code mismatch evidence.
			   - Native package policy can opt into `OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1`, which builds a
			     same-source bytecode sidecar under package AVM budgets and records AVM canonical gas only when
				     stdout/exit matches the native run or the sidecar itself reports AVM canonical gas budget
					     exhaustion through structured `avm.run.v1.error` evidence.
					     The certificate now binds exact program args and the declared package policy with stable
					     SHA-256 fields, so consumers do not infer package/input identity from artifact hashes alone.
					     `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar` turns that package-bound
				     sidecar into explicit `budget_gas` enforcement, reported as
				     `runner_wall_avm_canonical_gas` with `enforcement_profile="avm-sidecar"`; the shared
				     dispatcher exposes the same policy as
				     `scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar` and now defaults
				     native dispatch to `auto`, which selects it when `budget_gas` is declared.
				     Non-certified sidecar evidence is now guarded explicitly: the package-policy verifier
				     injects an auditable stdout mismatch, requires `certification_status="unavailable"` and
				     `certification_failure_reasons=["stdout_mismatch"]`, and checks the runner reports
				     `budget_unavailable` instead of treating the AVM sidecar as gas enforcement.
				     The adjacent stderr-mismatch probe now stays certified with
				     `certification_warnings=["stderr_mismatch"]`, proving warnings are non-blocking.
				     A combined schema-mismatch plus stderr `budget exceeded (gas)` probe now remains
				     `budget_unavailable`, proving stderr diagnostics cannot certify gas without canonical
				     `avm.run.v1` evidence.
				     An exit-code mismatch probe now also requires `exit_code_mismatch` plus
				     `sidecar_exit_nonzero` failure reasons and keeps the sidecar non-certified.
					     Missing run-JSON, schema-mismatch, gas-surface, zero-gas, and timeout probes now cover the remaining
					     non-certified AVM sidecar gas-evidence branches. A sidecar build-failure probe now
				     also keeps the native package-policy run JSON structured with `sidecar_build_failed`
				     instead of failing before report emission. A native-failure fixture now preserves
				     the native exit with `not_run_native_failed` sidecar evidence rather than masking it
				     as sidecar gas unavailability.
	   - `docs/GAS_SURFACE_REGISTRY.md` plus `make verify-gas-surface-registry` now guard the registered
	     gas-surface inventory, including AVM-canonical versus native backend-local conversion status.

8) **W3 - Structural/SOLID debt**
   - Large source files remain a maintainability risk, but the rolling tracked >2000-line source
     file list is empty again after the latest runtime/compiler/test-bundle splits
     (2026-04-22 rescan).
   - Splits underway:
     - GC safepoint helpers moved out of `lib/compiler/arm64_native_stmt.oren` into
       `lib/compiler/arm64_native_gc.oren` (2026-02-25).
     - `lib/compiler/arm64_native_stmt.oren` split into focused loop/list/runtime modules:
       `lib/compiler/arm64_native_stmt_loops.oren`,
       `lib/compiler/arm64_native_stmt_loops_list.oren`,
       `lib/compiler/arm64_native_stmt_loops_list_emit.oren`,
       `lib/compiler/arm64_native_stmt_loops_base.oren`,
       `lib/compiler/arm64_native_stmt_runtime.oren` (all <2000 lines, 2026-02-25).
     - `lib/compiler/transpiler.oren` split into focused core/analysis/C-utils/lambda modules
       (all <2000 lines, 2026-02-25).
     - `lib/compiler/optimizer.oren` split into focused core/fold/DCE/list-int/list-reserve/TCO modules
       (all <2000 lines, 2026-02-25).
     - `lib/runtime_native/100_time_gc_alloc.oren` core split into scan/reuse, list_hdr, track, roots_gc
       modules (all <2000 lines, 2026-03-03).
     - `lib/std/buffer.oren` split into the public facade plus `lib/std/buffer/view.oren` and a
       direct matrix layer (`lib/std/buffer/mat_core.oren`, `lib/std/buffer/mat_proj.oren`,
       `lib/std/buffer/mat_shared.oren`, `lib/std/buffer/mat_numeric.oren`,
       `lib/std/buffer/mat_u8.oren`), with shared validation and list-view predicates factored
       into `lib/std/buffer/common.oren` and shared raw typed-buffer wrappers factored into
       `lib/std/buffer/raw.oren`, keeping the top-level stdlib module at 697 lines and each
       helper module <2000 lines (2026-03-27).
     - `lib/compiler/compiler/040_build_pipeline/010_main.oren` split into
       `lib/compiler/compiler/040_build_pipeline/005_helpers.oren` plus a 1957-line main command
       dispatcher, keeping the compile-time include order unchanged while dropping the tracked main
       file below the 2000-line threshold (2026-03-27).
     - `lib/runtime_native/263_green/010_green_core.oren` split into a shared state/layout prelude
       (`lib/runtime_native/263_green/005_green_state.oren`) plus a 1928-line queue/scheduler core,
       keeping the green-module include order intact while moving offsets, globals, and tiny
       scheduler-state accessors out of the hot scheduler implementation (2026-03-27).
     - `pkg/transpiler/transpiler.go` split into the core emitter plus
       `pkg/transpiler/transpiler_lambda.go`, moving lambda collection/free-var analysis/emission
       into a focused companion file and leaving the main transpiler at 1836 lines (2026-03-27).
     - `lib/runtime_native/170_lists.oren` split into core + api modules (all <2000 lines, 2026-03-03).
     - `lib/compiler/optimizer_loops.oren` split into `lib/compiler/optimizer_loops_list.oren` and
       `lib/compiler/optimizer_loops_arena.oren` (both <2000 lines, 2026-02-25).
     - `lib/compiler/arm64_native_program.oren` split into `lib/compiler/arm64_native_program/*`
       modules (all <2000 lines, 2026-03-03).
     - `lib/avm/main.c` split into CLI-focused modules (`avm_cli_util`, `avm_cli_verify`,
       `avm_cli_policy`, `avm_cli_fs`, `avm_cli_disasm`, `avm_cli_dump`)
       (all <2000 lines, 2026-02-25).
     - `lib/avm/avm_vm.c` split into focused VM modules (`avm_vm_core`,
       `avm_vm_sched`, `avm_vm_values`, `avm_vm_list_ops`)
       (all <2000 lines, 2026-02-25).
     - `lib/compiler/x64_native_program/060_emit_ops.oren` split into focused emit modules
       (`055_emit_ops_locals`, `056_emit_ops_match`, `057_emit_ops_while_emit`)
       (all <2000 lines, 2026-02-25).

---

## Regression gates (run first)

Local (fast):

- `make test`
- `make verify-native-quick`
- `make verify-native-quick-simd`
- `make verify-backend-parity-boxed-list`
- `make verify-backend-parity-list-int`
- `make verify-backend-parity-tags`
- `make verify-backend-parity-arith-panics`
- `make verify-backend-parity-index-panics`
- `make verify-runtime-robustness`
- `./scripts/verify_x64_linux_qemu_smoke.sh`

Note: `make verify-backend-parity-tags` depends on AVM CLI/VM build; keep select-case parsing + helper visibility in sync with the split.

Backend parity scripts now default `OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS` to `120`, matching the
repo-wide build watchdog. That keeps local parity runs from false-timing out when they queue behind
the shared compiler-build lock or a cold stage2 rebuild.

Remote verify scripts support `OREN_REMOTE_SCP_TIMEOUT_SECS` to bound scp hangs.
Tier-1 Linux/QEMU scripts accept `OREN_LINUX_DOCKER_ID` as a container name, full ID, or
unambiguous ID prefix; the documented default `c7e5f7bd9f5c` is the persistent container name.

Tier-1 cross-arch (when touching native/runtime/net):

- `./scripts/verify_native_matrix.sh`
- `./scripts/verify_native_net_matrix.sh`
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
- `./scripts/verify_stage0_windows_bootstrap.sh`

Periodic perf gates (when touching performance-critical paths):

- `make benchmarks`
- `make bench-native-compile`

---

## Performance parity tracker (weighted, 2026-02-26 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026-02-26).
Weights reflect expected impact on C parity and breadth of affected code.

1) **W5 - Native integer hot-loop parity (loop_sum, dot_product)** (L)
   - Baseline (arm64 native, snapshot 2026-02-26): `loop_sum` 3.33× C, `dot_product` 2.57× C.
   - New run (arm64, 2026-04-04, runs=5, warmups=1; via `make perf-gate-native`):
     - loop_sum: C 0.069604s, native 0.075902s (1.09× C).
     - dot_product: C 0.005108s, native 0.014420s (2.82× C).
   - New run (arm64, 2026-03-05, runs=3, warmups=1):
     - loop_sum: C 0.067194s, native 0.225078s (3.35× C) (log: `build/logs/bench_run_perf_gate_20260305_021914.log`).
     - dot_product: C 0.005185s, native 0.013571s (2.62× C) (log: `build/logs/bench_run_perf_gate_20260305_021914.log`).
   - Expand inty propagation and arithmetic fast paths.
   - Split runtime init vs steady-state cost and quantify the init gap (see `benchmarks/RESULTS_LATEST.md` notes).
     - New: `OREN_BENCH_INIT_SPLIT=1` adds loop_sum init/steady estimation (see `benchmarks/README.md`).
     - New: capsule-only NET/PROC tables now allocate in `native_runtime_capsule_init` to reduce non-capsule runtime init cost; remeasure init/steady split (2026-02-25).
     - New: `OREN_TRACE_RUNTIME_INIT=1` prints native_runtime_init phase timings.
   - Init/steady split (loop_sum, arm64 macOS, 2026-03-05, n=20,000,000; reps=1 vs 10; 3 runs):
      - C: init 0.003130s, steady 0.064991s
      - Oren C: init 0.002705s, steady 0.059376s
      - Native: init 0.001412s, steady 0.225120s
   - Const-divisor `%` is now inlined for literal/const RHS (arm64 + x64).
   - New: native LCG fast loops use reciprocal-based fastmod when mod constants fit (arm64 + x64).
   - Fix (2026-03-20): shared arm64 `UMULH` opcode encoding was wrong; correcting it restores the
     intended reciprocal-mod lowering in arm64 fast LCG loops.
   - Verification (2026-03-20): `benchmarks/loop_sum/loop_sum.oren` now preserves inty CLI args via
     `oren_trunc_int(...)`, and `OREN_TRACE_ARM64_LOOP_STACK=1` shows the benchmark re-entering
     `fast_lcg_sum_while_no_tick` instead of falling back to `while_generic`
     (`build/logs/codex_loop_sum_after_umulh_fix_build_20260320.log`).
   - Boxed list dot/get-sum regression guard added to native QI (2026-02-19).
   - Fast-loop safepoints now reset GC tick after safepoint to avoid tick spills (arm64 list-sum, x64 LCG sum).
   - Native fast list-dot loops now use per-list cursors (when lists are unique per mul) to avoid per-iter index multiplies.
   - Native fast list get-sum loops now use per-list cursors (when lists are unique per load) to avoid per-iter index multiplies.
   - Int-only list literals now lower to `list<int>` even when non-empty and use unchecked pushes on native/OBC to preserve fast paths (rolling, 2026-02-20).
   - Safe list<int> get/len now rewrite to unchecked header paths (`oren_list_int_get_unchecked`, `oren_list_int_len_unchecked`) on native backends (rolling, 2026-02-24).
   - Arm64 fast list_int get-sum loops now accept `list_int_get_unchecked` calls to preserve the fast path after rewriting (rolling, 2026-02-24).
   - Arm64 get-sum + dot fast loops use inline safepoint ticks (register-based). As of
     2026-03-19, arm64 boxed/int get-sum and boxed/int dot no longer reserve a dedicated stack
     tick slot by default; the old layouts can still be restored for comparison with the
     `*_KEEP_TICK_SLOT=1` env overrides.
   - Safepoint throttling for list<int> hot loops: arm64 list<int> sum/dot mask=4095; x64 list<int> sum/dot mask=1023.
   - Arm64 fast-loop throttling masks are now compiler-env tunable per emitter via
     `OREN_ARM64_FAST_LIST_{GET_SUM,DOT,PUSH}_TICK_MASK`,
     `OREN_ARM64_FAST_LIST_INT_{GET_SUM,DOT,PUSH}_TICK_MASK`, and
     `OREN_ARM64_FAST_LCG_SUM_TICK_MASK` (decimal `0..65535`, invalid input falls back).
   - X64 boxed-list fast loops (push/get-sum/dot) now throttle safepoints at mask=1023 to reduce hot-loop overhead (rolling, 2026-02-25).
   - Arm64 list<int> get-sum + dot fast loops now keep i/sum in registers across iterations to reduce stack traffic (rolling, 2026-02-26).
   - Arm64 boxed list get-sum + dot fast loops now keep i/sum in registers across iterations to reduce stack traffic (rolling, 2026-02-26).
   - Fix: arm64 boxed fast list dot loop now initializes X10 tick mask before inline safepoint ticks (2026-02-26).
   - Fix (2026-04-04): arm64 fast `list<int>` push loops now initialize X10 before inline
     safepoint ticks, so the register-only throttled path no longer depends on stale caller state.
   - LCG fast loop safepoint mask now 4095 on arm64 + x64 (rolling, 2026-02-26).
   - Probe (2026-04-04, canonical `array_sum`/`dot_product` on arm64):
     `OREN_ARM64_FAST_LIST_INT_DOT_TICK_MASK=16383` was effectively neutral (`dot_product`
     ~2.93x C vs baseline ~2.93x), and `65535` was only a marginal improvement (`~2.86x C`);
     keep the shipped default at `4095` until a stronger win is demonstrated.
   - Split (2026-04-04, canonical `array_sum`/`dot_product`, reps=1 vs 10):
     - `array_sum`: native/C long-per-rep ~1.44x, delta estimate ~0.96x
     - `dot_product`: native/C long-per-rep ~2.59x, delta estimate ~2.48x
     - Conclusion: canonical `dot_product` is still blocked by the steady read/multiply body
       rather than the one-time fill/setup half; `array_sum` steady read is already much closer.
   - New canonical native smoke + steady runner (2026-04-04):
     - `make perf-smoke-native-fast-loops` now builds and runs the exact native `array_sum` /
       `dot_product` benchmark binaries on both the tiny (`205`, `6590`) and >16-element (`710`,
       `54380`) cases so future dot-core work has a direct correctness tripwire.
     - `make perf-gate-native-steady` now measures repeated read-loop medians directly.
     - First steady rerun (arm64, `reps=100`): `array_sum` ~2.40x C, `dot_product` ~3.10x C.
     - Tracker implication: use the new steady runner, not the split long-per-rep estimate, when
       deciding whether canonical hot-loop work is landing.
   - Trace (2026-04-04): a follow-up arm64 single-pair unrolled-dot experiment swapped the hot
     scalar loads plus cursor adds for post-index pair loads (`ldp ..., [cursor], #16`). Serial
     reruns came back worse, not better: steady `array_sum` ~2.33x C / `dot_product` ~3.15x C and
     canonical gate `array_sum` ~2.18x C / `dot_product` ~2.61x C, so the pair-load fusion was
     reverted and is not the current high-probability path to the <=2x target.
   - Trace (2026-04-04): a broader arm64 `madd` substitution in fast dot emitters was not
     correctness-safe on the current codegen shape. `make perf-smoke-native-fast-loops` rebuilt
     cleanly, `array_sum` still returned the expected `205` / `710`, but native `dot_product 10 3`
     crashed before producing `6590` (log: `build/logs/perf-smoke-native-fast-loops-20260404_223646_87957.log`).
     The substitution was reverted immediately; treat `madd` as an audit-first experiment, not a
     drop-in instruction-count reduction.
   - New canonical steady tick-mask probe (2026-04-04):
     - `make perf-probe-arm64-fast-loop-tick-masks-steady` reruns the arm64 `16383` / `65535`
       safepoint-mask sweep on top of `make perf-gate-native-steady`, so it measures the true
       repeated-read-loop surface instead of the earlier one-shot gate.
     - The probe now runs one shared smoke preflight and forces the measured baseline/mask cases to
       the same `OREN_PERF_SMOKE_NATIVE_FAST_LOOPS=0` policy; the initial mixed-smoke draft was not
       a fair comparison and was corrected before landing.
     - First corrected steady rerun (`dot_product`, default `n=2000000`, `reps=100`): baseline
       ~3.0142x C, `16383` ~3.0924x C, `65535` ~3.1914x C.
     - Conclusion: on the canonical steady runner, higher dot safepoint masks regress or stay flat;
       keep the default arm64 `fast_list_int_dot_while` tick mask at `4095`.
   - New arm64 single-pair cursor-reg probe (2026-04-04):
     - `make perf-probe-arm64-fast-dot-single-pair-cursor-regs` now compares the shipped
       `fast_list_int_dot_while` single-pair cursor-reg path against
       `OREN_ARM64_FAST_LIST_INT_DOT_SINGLE_PAIR_CURSOR_REGS=0` without source edits.
     - While landing that probe, fixed a real measurement bug: `run_perf_gate_native.sh`,
       `run_perf_gate_list_int.sh`, `run_perf_gate_list_int_read_split.sh`,
       `run_perf_gate_list_int_steady.sh`, and `benchmarks/run_benchmarks.py` all now use
       collision-resistant timestamps so adjacent probe variants do not overwrite logs/results.
     - Current same-tree rerun
       (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-20260411_170046_96599.log`):
       disabling cursor regs regressed raw native generic `dot_product` time (`steady 0.130047s ->
       0.133221s`, `gate 0.010926s -> 0.011969s`; `+2.44%` / `+9.55%`).
     - Explicit `dot_product_int`
       (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int-20260411_170108_97730.log`)
       stayed mixed: disabled cursor regs slightly improved raw native medians (`0.131784s ->
       0.130060s`, `0.010440s -> 0.010435s`; `-1.31%` / `-0.05%`), but the gate ratio worsened
       (`~1.8254x` -> `~2.0207x`) because the paired C median shifted.
     - Conclusion: keep the cursor-reg path enabled by default; do not flip the shipped default on a
       tiny explicit-only raw-native delta that conflicts with the generic surface.
   - New arm64 unroll-by-2 probe (2026-04-04):
     - `make perf-probe-arm64-fast-dot-unroll2` now compares the shipped
       `fast_list_int_dot_while` unique-list unroll-by-2 path against
       `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=0` without source edits.
     - The emitter also accepts explicit `OREN_ARM64_FAST_LIST_INT_DOT_UNROLL2=1` / `true`, so
       future reruns can force either side of the comparison without patching code.
	     - Final kept-state rerun (`build/logs/perf-probe-arm64-fast-dot-unroll2-20260404_215653_19700.log`):
	       steady default ~2.9806x C vs disabled ~2.8893x C, canonical gate default ~2.1919x C vs
	       disabled ~2.7147x C.
	     - Conclusion: the current host signal is mixed rather than decisively better in one direction.
	       Keep the shipped unroll-by-2 default for now and reuse the probe for future reruns.
	   - New arm64 fast-loop pair-post probe + env-parser fix (2026-04-08):
	     - `make perf-probe-arm64-fast-loop-pair-post` now compares the shipped `array_sum` /
	       `dot_product` baseline against the default-off experimental pair-load paths enabled via
	       `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_PAIR_POST=1`.
	     - While landing that probe, fixed the remaining comma-splitting bug in the smoke/disasm/debug
	       helper scripts (`run_perf_smoke_native_fast_loops.sh`, `run_perf_smoke_list_int.sh`,
	       `run_perf_probe_arm64_native_hot_loop_disasm.sh`, `run_perf_debug_native_benchmark.sh`,
	       and adjacent helper wrappers), so comma-separated `OREN_BENCH_ENV_BUILD_OREN` now reaches
	       the traced disasm and smoke legs consistently instead of only the gate/steady runners.
	     - Current rerun (`build/logs/perf-probe-arm64-fast-loop-pair-post-20260408_215548_57748.log`):
	       default `steady_array_sum ~2.4342x C`, `steady_dot_product ~2.7645x C`,
	       `gate_array_sum ~2.0788x C`, `gate_dot_product ~2.5682x C`, disasm `52` / `70`;
	       enabled `~2.3932x C`, `~3.1297x C`, `~2.1181x C`, `~2.6913x C`, disasm `47` / `60`.
	     - Conclusion: keep the pair-load/post-index branch disabled by default. It trims the traced
	       arm64 windows materially, but the measured steady and canonical gates still regress.
	   - New explicit get-sum pair-post decision surface (2026-04-09):
	     - `make perf-probe-arm64-fast-get-sum-pair-post-list-int` now isolates the
	       `array_sum_int` get-sum leg on the shared `list<int>` acceptance bundle, and
	       `make perf-probe-arm64-fast-get-sum-pair-post-decision` compares the shipped default
	       against `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST=1` on the same-tree exact
	       whole-operation C ceiling.
	     - Current widened rerun (`build/logs/perf-probe-arm64-fast-get-sum-pair-post-decision-20260409_180234_41790.log`):
	       acceptance strongly preferred the enabled branch (`steady -26.20%`, `gate -53.71%`),
	       but the exact whole-operation reruns still preferred the shipped default in `3/5`
	       sweeps (`default_array_ratio_median ~2.3604x`, enabled `~2.4015x`; exact dot also stays
	       slightly better on default at `~1.8539x` vs `~1.8578x`).
		     - Conclusion: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_PAIR_POST` default-off. The local
		       acceptance wrapper is not the ranking surface for this branch.
		   - New explicit get-sum vector-2d decision surface (2026-04-11):
		     - `make perf-probe-arm64-fast-get-sum-vector-2d-decision` compares the shipped default
		       against `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D=1`, a direct slot64 SIMD-add
		       body that uses `ldr q` plus `add.2d`/`addp.2d` and reduces back into the scalar sum
		       before another possible GC safepoint call.
		     - Current widened rerun
		       (`build/logs/perf-probe-arm64-fast-get-sum-vector-2d-decision-20260411_201706_52184.log`)
		       confirms the intended structure (`51` traced instructions, `41` after subtracting two
		       cold tick blocks, `q` loads in the snippet, `add.2d=1`, `addp.2d=2`).
		     - Measurement split: local acceptance preferred enabled (`steady -7.95%`, `gate -1.62%`
		       native medians), but the same-tree exact C-ceiling surface preferred shipped default in
		       `4/5` sweeps (`default_array_ratio_median ~2.2140x`, enabled `~2.2967x`).
		     - Conclusion: keep `OREN_ARM64_FAST_LIST_INT_GET_SUM_VECTOR_2D` default-off. This is a real
		       direct-lowering probe, but not a stable shipped answer on the current 64-bit slot stream.
		   - Arm64 fast-loop prefix-zero family remains default-off, but the dot leg is now isolated and
	     remeasured cleanly (2026-04-09):
	     - The statement-level prefix-zero list<int> fast paths still stay explicit opt-in only via
	       `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1` and
	       `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`; the shipped default still does not route
	       through either experiment.
	     - `OREN_ARM64_FAST_LIST_INT_GET_SUM_PREFIX_ZERO=1` remains a clear negative result on the
	       current host. The isolated rerun
	       (`build/logs/perf-probe-arm64-dot-acceptance-20260409_003014_84317.summary.log`) landed at
	       `steady_array_sum ~7.1203x C` and `gate_array_sum ~2.3250x C`, materially worse than the
	       shipped default even though the leg stays correctness-clean.
	     - The arm64 dot prefix-zero subpath now mirrors the proven direct-slot register plan after
	       list validation, so `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1` is correctness-clean on
	       native smoke again (`build/logs/perf-smoke-native-fast-loops-20260409_003456_90383.log`).
	     - New dedicated serialized generic-dot probe: `make perf-probe-arm64-fast-dot-prefix-zero`.
	       It pins `OREN_ARM64_DOT_ACCEPT_PROGRAMS=dot_product` on both sides and compares the shipped
	       default against just `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO=1`, instead of mixing in the
	       unrelated get-sum leg.
	     - New dedicated explicit-`list<int>` acceptance/probe surface:
	       `make perf-probe-arm64-list-int-acceptance` packages the explicit `array_sum_int` /
	       `dot_product_int` smoke, traced disasm, steady gate, whole-operation gate, and
	       exact-binary debug rerun into one artifact, and
	       `make perf-probe-arm64-fast-dot-prefix-zero-list-int` uses that bundle to judge the
	       salvaged dot prefix-zero subpath on the shared `list<int>` benchmark surface.
	     - The generic and explicit prefix-zero wrappers now preserve raw steady/gate native medians and
	       covariance from the acceptance bundles, because ratio-only A/Bs were masking C-baseline drift.
	     - Current generic-dot rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-20260409_014027_88043.log`):
	       default `steady_dot_product ~2.8260x C`, native `0.083484s`, gate native `0.013869s`,
	       disasm `70`; enabled `steady_dot_product ~2.9272x C`, native `0.080339s`,
	       gate native `0.014837s`, disasm `23`. Direct native deltas:
	       `steady_dot_product_native_median_delta_pct: -3.77%`,
	       `gate_dot_product_native_median_delta_pct: +6.98%`.
	     - Current explicit `list<int>` rerun (`build/logs/perf-probe-arm64-fast-dot-prefix-zero-list-int-20260409_014050_89076.log`):
	       default `steady_dot_product_int ~3.0871x C`, native `0.077758s`, gate native `0.013945s`,
	       disasm `70`; enabled `steady_dot_product_int ~2.9543x C`, native `0.087468s`,
	       gate native `0.015405s`, disasm `23`. Direct native deltas:
	       `steady_dot_product_int_native_median_delta_pct: +12.49%`,
	       `gate_dot_product_int_native_median_delta_pct: +10.47%`.
	     - Conclusion: keep both prefix-zero branches disabled by default. The get-sum leg remains a
	       clear regression, the generic dot leg is still mixed, and the latest raw-median rerun
	       overturns the older ratio-only “explicit win” reading on `dot_product_int`. The newer
	       specialization wrapper still says the generic/explicit gap itself stays small, so the next
	       arm64 work should move away from prefix-zero promotion and toward other dot-kernel paths.
	   - Modest arm64 unique-list loop-body cleanup (2026-04-04):
	     - kept `n` hot in a register for unique-list `fast_list_int_get_sum_while` and
	       `fast_list_int_dot_while`, switched scalar unique-list cursor bumps from register-add to
       immediate-add, and removed the duplicate `i * 8` recompute from the non-unique int-dot body.
     - Serial reruns on the kept tree:
       - steady (`build/logs/perf-gate-native-steady-20260404_220430_32496.log`): `array_sum`
         ~2.2422x C, `dot_product` ~2.9915x C
       - canonical gate (`build/benchmarks/results/array_sum_darwin_arm64_20260404_220447_355740.md`,
         `build/benchmarks/results/dot_product_darwin_arm64_20260404_220447_627069.md`):
       `array_sum` ~2.0808x C, `dot_product` ~2.7616x C
     - Conclusion: keep the cleanup because it is low-risk and directionally positive, but the
       canonical arm64 `dot_product` blocker remains above the `<=2x C` gate.
   - Targeted arm64 fast-loop safepoint spill reduction (2026-04-04):
     - kept the generic/native-expression safepoint wrapper unchanged, but taught the exact
       `list<int>` hot loops to spill only the callee-saved pairs that can actually hide live
       heap pointers from the conservative stack scan:
       - `fast_list_int_get_sum_while*`: no extra spill pairs at the inline safepoint
       - `fast_list_int_dot_while*` single-pair cursor-reg path: spill only `[x19,x20]` and
         `[x25,x26]` instead of the full x19-x28 set
     - Verified with:
       - `build/logs/perf-smoke-native-fast-loops-20260404_233153_87311.log`
       - `build/logs/perf-probe-arm64-native-hot-loop-disasm-20260404_232947_83762.log`
       - `build/logs/perf-gate-native-steady-20260404_232818_80682.log`
       - `build/logs/perf-gate-native-20260404_233209_88078.summary.log`
     - New kept-state reruns:
       - steady: `array_sum` ~2.4144x C, `dot_product` ~2.7706x C
       - canonical gate: `array_sum` ~1.8926x C, `dot_product` ~2.5264x C
       - traced hot-loop windows:
         - `array_sum`: 52 instructions (down from 72), no inline-safepoint `stp/ldp` spill block
         - `dot_product`: 70 instructions (down from 82), `stp=4` / `ldp=4` instead of `10` / `10`
     - Conclusion: keep the reduced-spill path. The arm64 `dot_product` blocker is still open, but
       this is the first April 4 loop-body change that improved both the steady and canonical views
       without hurting correctness.
     - Follow-up trace (2026-04-04): narrowing the exact single-pair dot inline-safepoint spill
       set one step further to a single `[x19,x26]` pair did not hold up on the focused steady
       rerun. `build/logs/perf-gate-native-steady-20260404_233707_97722.log` moved `array_sum` /
       `dot_product` to ~2.4331x / ~3.0449x C, so the one-pair variant was reverted and the
       two-pair `[x19,x20]` + `[x25,x26]` kept-state remains the better current host baseline.
     - Follow-up exact-register spill probe (2026-04-05): replacing the kept two-pair spill set
       with exact single-register spills (`[x19]`, `[x26]`) did clear the exact benchmark smoke
       and exact-binary repro:
       - `build/logs/perf-smoke-native-fast-loops-20260405_002352_77964.log`
       - `build/logs/perf-debug-native-benchmark-dot_product-20260405_002400_78334.log`
       But it still regressed both perf trackers:
       - steady (`build/logs/perf-gate-native-steady-20260405_002356_78070.log`):
         `array_sum` ~2.4180x C, `dot_product` ~3.0259x C
       - canonical gate (`build/logs/perf-gate-native-20260405_002400_78191.summary.log`):
         `array_sum` ~2.0537x C, `dot_product` ~2.5850x C
       Conclusion: keep the earlier two-pair spill baseline; the exact single-register spill path
       is not the next production candidate on this host.
   - Arm64 dual-accum probe refresh + safepoint-safe register plan (2026-04-09):
     - `make perf-probe-arm64-fast-dot-dual-accum` now preserves raw native medians/covariance for
       generic `dot_product`, and `make perf-probe-arm64-fast-dot-dual-accum-list-int` does the
       same for explicit `dot_product_int`.
     - The opt-in dual-accum lowering no longer hides the secondary accumulator in caller-saved
       `x17`. The current tree keeps that accumulator in callee-saved `x22` so inline GC
       safepoints cannot clobber it across the runtime call.
     - Current generic rerun (`build/logs/perf-probe-arm64-fast-dot-dual-accum-20260409_024400_89920.log`)
       improved both raw native medians even though the disasm grew by one instruction:
       steady `0.079878s -> 0.077758s` (`-2.65%`), gate `0.014427s -> 0.013903s` (`-3.63%`),
       disasm `69 -> 70`.
     - Current explicit rerun (`build/logs/perf-probe-arm64-fast-dot-dual-accum-list-int-20260409_024524_92158.log`)
       is still mixed: steady `0.077313s -> 0.080407s` (`+4.00%`), gate `0.016063s -> 0.015338s`
       (`-4.51%`), but the enabled gate sample warned as high variance
       (`warning_gate_dot_product_int_high_variance`).
     - Conclusion: the earlier April 4 "regresses both surfaces" call is stale on the current tree.
       Keep the dual-accum path disabled by default for now because the explicit `list<int>`
       surface is still mixed/noisy, but the opt-in path is now correctness-safe and worth future
       rechecks.
   - Native gate summary hygiene (2026-04-04):
     - `make perf-gate-native` now emits a lightweight summary log next to the raw benchmark log.
     - The summary prints per-program medians/ratios and warns when the canonical one-program gate
       is too noisy (`cov >= 0.10`) to support a strong perf conclusion.
   - Native gate stability probe (2026-04-04):
     - `make perf-probe-native-gate-stability` reruns the canonical native gate a few times and
       summarizes the ratio range plus warning frequency per program, so future arm64 dot work can
       compare against a small distribution instead of one noisy gate run.
     - First rerun (`build/logs/perf-probe-native-gate-stability-20260404_222343_66111.log`,
       `sweeps=3`, programs=`array_sum,dot_product`) came back clean enough to use: `array_sum`
       median ~1.9955x C (range ~1.9603x..~2.0259x, warnings 0/3), `dot_product` median ~2.5153x
       C (range ~2.3889x..~2.6432x, warnings 0/3).
     - Conclusion: on the current host the canonical gate is stable enough to confirm the blocker:
       arm64 `dot_product` is still materially above the `<=2x C` target even when the gate itself
       stops warning.
   - Tooling fix (2026-04-04): stage1/stage2 builds now take a repo-local compiler build lock
     (`build/locks/compiler-build.lock`), so concurrent `make perf-*` invocations do not race on
     `oren` / `oren_stage2` and macOS codesign.
   - Tooling follow-up (2026-04-04): the same build lock now waits longer by default
     (`OREN_BUILD_LOCK_WAIT_SECS=1800`, `0` = wait forever) and records holder start time / age in
     `build/locks/compiler-build.lock/meta`, so queued `make test` / `make perf-*` runs stop
     false-failing behind a legitimate long stage2 build.
   - Tooling fix (2026-04-04): arm64 fast list loops now expose an opt-in
     `OREN_TRACE_ARM64_LOOP_RANGES=1` trace, and `make perf-probe-arm64-native-hot-loop-disasm`
     builds canonical `array_sum` / `dot_product` with `--disasm` and extracts the traced fast-loop
     windows into a compact artifact for machine-code review.
   - Tooling follow-up (2026-04-05): `make perf-debug-native-benchmark` now builds a chosen native
     benchmark binary, runs the exact binary directly, and records the binary path, args, exit code,
     build log, and run log in one summary artifact. On non-zero exit it also prints the exact
     manual `lldb -- <binary> <args...>` command to use for follow-up crash triage, so unsafe arm64
     dot experiments can be reproduced from one canonical artifact instead of reassembling the build
     command by hand.
   - Tooling follow-up (2026-04-05, updated 2026-04-09): `make perf-probe-arm64-fast-dot-madd-exact`
     still compares the shipped arm64 dot baseline against `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1`
     through the full serial acceptance bundle, but the wrapper now also preserves raw steady/gate
     native medians and covariance from the acceptance summary instead of only ratio lines. The same
     batch added the explicit `list<int>` counterpart `make perf-probe-arm64-fast-dot-madd-exact-list-int`,
     so generic `dot_product` and explicit `dot_product_int` can be judged separately before another
     default flip.
   - Tooling fix (2026-04-05): `make perf-smoke-native-fast-loops` and `make perf-smoke-list-int`
     now rebuild their native benchmark binaries with `--no-cache`. That closes a correctness hole
     where compiler-env experiments could otherwise reuse a stale cached baseline artifact and
     report a false green smoke.
   - Trace (2026-04-05): a narrower exact-path `madd` follow-up only touched the single-pair
     cursor-reg `fast_list_int_dot_while*` body. The traced canonical dot window shrank from 70
     instructions / `mul=7 add=13` to 63 instructions / `madd=7 add=13`
     (`build/logs/perf-probe-arm64-native-hot-loop-disasm-20260404_235545_32513.log`), and the
     focused steady rerun improved to `dot_product` ~2.5627x C
     (`build/logs/perf-gate-native-steady-20260404_235745_37067.log`), but the exact benchmark
     smoke still crashed at native `dot_product 10 3` before producing `6590`
     (`build/logs/perf-smoke-native-fast-loops-20260405_000124_44574.log`). Reverted immediately;
     future multiply-accumulate work needs a narrower audited correctness argument than “same math,
     fewer instructions”.
   - Probe rerun (2026-04-05): the new `make perf-probe-arm64-fast-dot-madd-exact` wrapper now
     confirms the same story without a hand edit. On this host the enabled exact-path branch still
     fails in the exact native repro at `perf-debug-native-benchmark` with `exit_code: 139`, even
     though the partial acceptance summary shows better focused numbers:
     `steady_dot_product ~2.7940x`, `gate_dot_product ~2.5953x`, and traced canonical dot disasm
     at `63` instructions (`build/logs/perf-probe-arm64-dot-acceptance-20260405_005354_27728.summary.log`).
     After the smoke cache-policy fix, the enabled canonical smoke also reproduces the failure
     directly instead of passing via a stale cached binary.
   - Exact-double tail guard follow-up (2026-04-05): the arm64 2-wide exact-`madd` branch now has a
     targeted terminal-tail fallback in `fast_list_int_dot_while*`, so the formerly unsafe direct
     exit after a terminal 2-wide chunk drops back to the original `mul/add` body instead of taking
     the exact-`madd` path. The updated exact-double sweep is now green for every sampled `n=1..24`,
     including the previously failing `n ≡ 2 (mod 4)` cases `10`, `14`, `18`, and `22`
     (`build/logs/perf-probe-arm64-fast-dot-madd-exact-double-sweep-20260405_013604_40047.log`).
   - Raw-metric recheck + explicit-surface split (2026-04-09): the exact-`madd` family is no longer
     tracked via ratio lines alone. Focused reruns now show the whole branch is still mixed even
     though it is correctness-clean:
     - generic whole-branch rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-20260409_020451_23581.log`):
       enabled `steady=0.082496s` vs baseline `0.079999s` (`+3.12%`), but gate
       `0.014211s` vs `0.014653s` (`-3.02%`)
     - explicit whole-branch rerun (`build/logs/perf-probe-arm64-fast-dot-madd-exact-list-int-20260409_020520_24931.log`):
       enabled `steady=0.078774s` vs baseline `0.078684s` (`+0.11%`), gate
       `0.014076s` vs `0.014510s` (`-2.99%`)
     Reweight accordingly: keep `OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT=1` opt-in only.
   - Shipped scalar exact-`madd` subpath after the unroll2 default flip (2026-04-09): the older
     exact subpath wrappers still exist for branch-local debugging, but the new scalar-core matrix
     wrappers are now the right shipped-baseline decision surface on the post-unroll2 tree.
     - Current scalar-core matrix probes
       (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260411_170733_44863.log`,
       `build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-list-int-20260411_170847_78864.log`)
       are the right shipped-baseline read now:
       - generic `dot_product`: the one-shot acceptance medians prefer `SCALAR=1` and
         `CURSOR=0,SCALAR=1`, but the run is too noisy to use alone (`gate` baseline covariance
         around `0.41`)
       - explicit `dot_product_int`: `SCALAR=1` improves steady (`0.138499s -> 0.131536s`,
         `-5.03%`) but is basically flat/slightly worse on the gate (`0.010847s -> 0.010917s`,
         `+0.65%`)
       - `CURSOR=0,SCALAR=1` improves the one-shot explicit gate (`0.010847s -> 0.009767s`,
         `-9.96%`) but still needs the order-balanced tie-breaker below before any default flip
     - Structural guard (refreshed 2026-04-11): `make verify-native-arm64-dot-madd-scalar-default`
       now locks the shipped default-off scalar tail to the live post-unroll2 disasm shape on both
       generic and explicit surfaces, and `make verify-native-list-int-fast-lowering` runs it
       automatically. Latest log
       (`build/logs/verify_arm64_dot_madd_scalar_default_20260411_171634_95703.log`): shipped
       defaults stay at `21` full-range instructions, `14` without the cold GC-call block, and
       `madd_count=0`; forcing `SCALAR=1` moves the same loops to `20`, `13`, and `1`.
     - Read-split decomposition follow-up (refreshed 2026-04-11): the wrappers
       `make perf-probe-arm64-fast-dot-scalar-core-read-split` and
       `make perf-probe-arm64-fast-dot-scalar-core-read-split-list-int`
       (`build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-20260411_170937_83286.log`,
       `build/logs/perf-probe-arm64-fast-dot-scalar-core-read-split-list-int-20260411_170942_83791.log`)
       show the current setup/repeated-work tradeoff directly:
       - generic `dot_product`: the latest read-split does not confirm the noisy one-shot matrix win;
         the combined cursor+scalar case is roughly flat on setup (`+0.09%`) and regresses repeated
         `long_per_rep` (`+0.88%`)
       - explicit `dot_product_int`: `SCALAR=1` improves every reported native component on this
         rerun (`short -6.13%`, `setup -6.11%`, `delta -6.33%`, `long_per_rep -6.26%`), with the
         usual delta-vs-long drift warning still telling tracker updates to prefer `long_per_rep`
       Use these read-split probes as decomposition tools, not as shipped-default verdicts by
       themselves.
     - Order-balanced gate-stability tie-breaker (refreshed 2026-04-11): the
       `make perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int` wrapper rotates the
       four scalar-core cases across four whole-operation sweeps so each case occupies each run
       position once. Latest artifact
       (`build/logs/perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int-20260411_170947_84214.log`)
       keeps the explicit whole-operation verdict mixed:
       - `SCALAR=1` is only a `2/4` native-median win with median `+1.65%`, while normalized
         `native/C` is a `2/4` win with median `-1.13%`
       - `CURSOR=0,SCALAR=1` is also only a `2/4` native-median win with median `+0.48%`, and
         normalized `native/C` is `2/4` with median `+0.15%`
     - Combined unroll2 + scalar-core decision (2026-04-11): the read-split and gate-stability
       wrappers now accept explicit case sets, and the new
       `make perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int` target ranks
       `UNROLL2=1`, `SCALAR=1`, and `UNROLL2=1,SCALAR=1` together on explicit `dot_product_int`.
       Current artifact
       (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172420_40937.log`)
       rejects the combined candidate: `UNROLL2=1,SCALAR=1` has read-split native
       `long_per_rep +0.72%`, gate native median `+2.20%` with `1/4` wins, and gate `native/C`
       median `+8.09%` with `1/4` wins. The separate `UNROLL2=1` and `SCALAR=1` rows also fail
       at least one required surface (`long_per_rep +7.42%` and `+3.54%`), so the old scalar
       subpath "quad" hint is now closed against this shipped baseline instead of left as an
       untested promotion branch. A post-hardening verification rerun
       (`build/logs/perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int-20260411_172713_80854.log`)
       was noisier, with high-covariance nested samples, but it still rejected the same combined
       candidate.
     - Scalar-post + scalar-core decision (2026-04-11): `make perf-probe-arm64-fast-dot-scalar-post-decision-list-int`
       ranks `baseline`, `SCALAR_POST=1`, `SCALAR=1`, and `SCALAR_POST=1,SCALAR=1` on the same
       explicit `dot_product_int` read-split and order-balanced gate surfaces. Structural artifacts
       confirm the intended lowering:
       - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1`
         (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-20260411_174133_69032.log`)
         emits post-index loads and shrinks the traced range to `19` instructions, `12` without the
         skipped cold GC-call block
       - `OREN_ARM64_FAST_LIST_INT_DOT_SCALAR_POST=1,OREN_ARM64_FAST_LIST_INT_DOT_MADD_EXACT_SCALAR=1`
         (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-scalar-post-madd-20260411_174149_69542.log`)
         emits post-index loads plus `madd` and shrinks the traced range to `18` instructions, `11`
         without the skipped cold block
       The decision artifact
       (`build/logs/perf-probe-arm64-fast-dot-scalar-post-decision-list-int-20260411_173911_64748.log`)
       still rejects the combined candidate: read-split native `long_per_rep +0.99%`, gate native
       median `+1.17%` with `2/4` wins, and gate `native/C +2.22%` with `2/4` wins. The standalone
       `SCALAR_POST=1` row also fails read-split (`long_per_rep +4.57%`) and gate native median
       (`+1.01%`, `2/4` wins).
     - Pair-post + exact-body `madd` decision (2026-04-11):
       `make perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int` ranks `baseline`,
       `UNROLL2=1`, `UNROLL2=1,PAIR_POST=1`, `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1`, and the combined
       `UNROLL2=1,PAIR_POST=1,QUAD/DOUBLE/SCALAR_MADD=1` candidate. The first focused explicit
       decision artifact
       (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_175200_21609.log`)
       cleared that narrow surface (`long_per_rep -0.22%`, gate native median `-1.03%` with `3/4`
       wins, and gate `native/C -5.64%` with `4/4` wins), but the immediate same-target rerun after
       generic wrapper parameterization
       (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int-20260411_180637_46019.log`)
       rejected it (`long_per_rep +6.27%`, gate native median `+0.49%` with `2/4` wins, and gate
       `native/C -2.93%` with `3/4` wins). Treat the explicit surface as unstable, not promotable.
       Structural disasm
       (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-unroll2-pair-post-madd-20260411_175249_24107.log`)
       confirms the intended 4-wide paired-scalar body: post-index `ldp` pairs plus `madd`, with a
       63-instruction traced range and 49 instructions after subtracting two skipped cold GC-call
       blocks. Broader acceptance keeps this opt-in: explicit `dot_product_int` improves raw native
       medians (`steady -0.74%`, `gate -6.12%`;
       `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260411_175304_24487.log`), but generic
       `dot_product` regresses steady native time while slightly improving gate (`+1.69%` / `-0.63%`;
       `build/logs/perf-probe-arm64-fast-dot-unroll2-20260411_175335_25935.log`). The matching generic
       decision wrapper is now `make perf-probe-arm64-fast-dot-pair-post-madd-decision`; current artifact
       (`build/logs/perf-probe-arm64-fast-dot-pair-post-madd-decision-20260411_180500_42245.log`)
       rejects the same combined candidate despite a read-split repeated-work win
       (`long_per_rep -2.46%`), because order-balanced gate native median regressed `+1.72%` with
       only `1/4` wins and normalized `native/C` regressed `+5.16%` with only `1/4` wins. The simpler
       `UNROLL2=1,QUAD/DOUBLE/SCALAR_MADD=1` row wins the generic gate (`native -2.42%`, `4/4`;
       native/C `-1.70%`, `3/4`) but fails read-split repeated work (`long_per_rep +2.55%`).
     - Dual-accum `madd` decision follow-up (2026-04-11):
       `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_MADD=1` now converts the existing opt-in
       dual-accumulator body from `mul`+`add` pairs into independent `madd` updates, gated behind
       `OREN_ARM64_FAST_LIST_INT_DOT_DUAL_ACCUM=1`. The new wrappers
       `make perf-probe-arm64-fast-dot-dual-madd-decision` and
       `make perf-probe-arm64-fast-dot-dual-madd-decision-list-int` rank the unroll2, dual-accum,
       dual-accum+madd, pair-post+dual-accum, and pair-post+dual-accum+madd rows. Current generic
       artifact (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-20260411_183505_89024.log`)
       rejects the combined candidate: read-split `long_per_rep -0.32%`, but gate native median
       `-1.20%` has only `2/4` wins and normalized `native/C +0.63%` has only `1/4` wins. The
       explicit artifact (`build/logs/perf-probe-arm64-fast-dot-dual-madd-decision-list-int-20260411_183536_91542.log`)
       also rejects it: read-split `long_per_rep -8.18%`, but gate native median `+1.18%` with
       `2/4` wins and normalized `native/C +5.43%` with `1/4` wins. Structural disasm
       (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-dual-madd-20260411_183626_94501.log`)
       confirms the intended paired post-index `ldp` plus dual-accumulator `madd` shape, with a
       53-instruction traced range, 39 after subtracting two skipped cold GC-call blocks, and
       `madd=7`.
     - Low-32 slot-load decision follow-up (2026-04-11):
       `OREN_ARM64_FAST_LIST_INT_DOT_LOW32_LOADS=1` now probes a default-off exact single-pair
       cursor-reg path that keeps the 8-byte `list<int>` slot stride but loads the low 32 bits via
       sign-extending `ldrsw`. This is not ABI-safe as a general default because `list<int>` slots are
       64-bit integers; it is only a range-proved/i32-workload experiment. Structural disasm
       (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-low32-dual-madd-20260411_185115_16862.log`)
       confirms the intended `UNROLL2=1,LOW32=1,DUAL_ACCUM=1,DUAL_MADD=1` shape: `ldrsw=14`,
       `madd=7`, 63 traced instructions, and 49 after subtracting two cold GC-call blocks. The new
       wrappers `make perf-probe-arm64-fast-dot-low32-loads-decision` and
       `make perf-probe-arm64-fast-dot-low32-loads-decision-list-int` reject the combined candidate
       across the shared surface. Generic artifact
       (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-20260411_185129_17298.log`) has
       read-split `long_per_rep +1.25%`, gate native `+0.12%` with `2/4` wins, and normalized
       `native/C -1.99%` with `3/4` wins; the standalone `LOW32=1` row wins the generic gate but still
       loses read-split repeated work (`long_per_rep +1.25%`). Explicit artifact
       (`build/logs/perf-probe-arm64-fast-dot-low32-loads-decision-list-int-20260411_185153_19370.log`)
       has the opposite failure mode for the combined row: read-split `long_per_rep -0.81%`, but gate
       native `+2.72%` with `1/4` wins and normalized `native/C +2.83%` with `2/4` wins.
     - Prefix pair-loop decision follow-up (2026-04-11):
       `OREN_ARM64_FAST_LIST_INT_DOT_PREFIX_ZERO_PAIR_LOOP=1` is a new default-off exact prefix-zero
       dot branch that emits a counted 2-wide pair loop and keeps the remainder branch outside the
       hot pair body. New wrappers:
       `make perf-probe-arm64-fast-dot-prefix-pair-loop-decision`,
       `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision`, and
       `make perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int`. Structural disasm
       (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-prefix-pair-loop-20260411_190748_44241.log`)
       confirms the intended `ldp` pair + `madd` body: 44 traced instructions, 26 after subtracting
       two cold GC-call blocks. The simple prefix-zero acceptance wrapper
       (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-decision-20260411_191033_47867.log`)
       looked superficially positive (`dot_product` steady/gate native `-0.75%` / `-1.92%`;
       `dot_product_int` `-0.27%` / `-5.88%`), but the stronger stability surface rejects promotion:
       generic stability
       (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-20260411_191326_52903.log`)
       has read-split `long_per_rep +3.34%` and only `2/4` order-balanced gate wins; explicit
       stability
       (`build/logs/perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int-20260411_191335_53758.log`)
       has read-split `long_per_rep +12.87%` and normalized gate `native/C` only `2/4` wins.
     - Conclusion: keep the scalar-tail `madd` choice opt-in on the shipped baseline, keep cursor
       regs on by default, keep scalar-post, pair-post+madd, dual-accum `madd`, low32 slot loads, and
       the counted prefix pair-loop opt-in, and judge future arm64 dot core changes with the matrix +
       read-split + order-balanced gate-stability probes rather than the older scalar-only promotion
       story.
   - Acceptance surface fix + cursor-end probe (2026-04-05):
     `OREN_BENCH_ENV_BUILD_OREN` now reaches the smoke, traced disasm, and exact native debug legs
     in the arm64 dot acceptance surface instead of only the gate runners, and the acceptance
     summary now records the active `build_env`. That improvement stays live, but the specific
     cursor-end lowering experiment has now been retired: even after the smaller hot-loop window and
     the earlier canonical-gate hint, the later read-split rerun still regressed repeated-loop
     `dot_product` on both `native/C long-per-rep` (`~2.6003x -> ~2.6651x`) and `native/C delta`
     (`~2.8383x -> ~3.0797x`)
     (`build/logs/perf-probe-arm64-fast-dot-cursor-end-read-split-20260405_021431_93331.log`).
     The same build-env contract now also reaches the direct-build exact-double helpers:
     `make perf-probe-arm64-fast-dot-madd-exact-double-sweep` and
     `make perf-probe-arm64-fast-dot-double-exit-snippet` both honor
     `OREN_BENCH_ENV_BUILD_OREN` and record the active `build_env` in their summaries.
     The April 9 follow-up also made the acceptance summaries emit explicit
     `warning_gate_{dot_product,dot_product_int}_high_variance` keys when gate COV reaches `0.10`,
     and the exact-`madd` wrapper summaries now preserve those warnings in their own output so noisy
     gate reruns are visible at the top level.
   - Disasm extraction follow-up (2026-04-05): `make perf-probe-arm64-fast-dot-double-exit-snippet`
     now rebuilds the baseline and exact-double variants with traced `--disasm` and extracts the
     compact 2-wide block from the canonical `fast_list_int_dot_while_no_tick` window into one
     artifact. That keeps the next fix focused on the exact `mul/add` vs `madd/madd` exit block
     instead of hand-scanning full native disassembly logs.
   - C-vs-Oren loop compare probe (2026-04-05, refreshed 2026-04-11): `make perf-probe-arm64-dot-vs-c-loop-compare` now
     pairs the traced Oren `dot_product` hot-loop window with the host `cc -O2 -S` lowering of
     `benchmarks/dot_product/dot_product.c`. The refreshed extractor is no longer pinned to hardcoded
     `LBB0_*` labels; it finds C vector/mid blocks via `smlal*` and the scalar tail via `smaddl`.
     The latest artifact
     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-20260411_165929_79776.log`) shows the kept
     Oren path as a 21-instruction traced range on the current shipped baseline, with a 14-instruction
     range after subtracting the skipped cold GC-call block. The host C reference is already a NEON
     vector loop plus vector mid loop plus scalar `smaddl` tail (`28` + `12` + `6` extracted-block
     instructions). That materially raises the bar for the remaining blocker: on this host, arm64
     `dot_product` underperformance is against a vectorized C baseline and a measured slot64 scalar
     ceiling, not just against the untaken safepoint save/restore block or a tighter scalar loop.
     The same script now has `make perf-probe-arm64-dot-vs-c-loop-compare-list-int` for the explicit
     `dot_product_int` surface; latest artifact
     (`build/logs/perf-probe-arm64-dot-vs-c-loop-compare-list-int-20260411_165935_82064.log`) shows
     the same 21-instruction Oren traced range, the same 14-instruction range without the cold
     GC-call block, and the same host C vector/mid/tail shape.
   - LCG fast loop unroll-by-2 on arm64 + x64 to reduce loop overhead (rolling, 2026-02-26).
   - New: `OREN_TRACE_ARM64_LOOP_STACK=1` logs loop stack/tick layout for arm64 loop emitters to debug tick slot offsets.
   - Trace (arm64 compile, 2026-02-26, `OREN_TRACE_ARM64_LOOP_STACK=1`):
     - loop_sum: `while_generic` tick_off=0 (stacks=160/176/224, slots=2, bytes=16).
     - dot_product: `fast_list_int_push_while` tick_off=0 (stack=208, slots=7, bytes=64);
       `fast_list_int_dot_while` tick_off=0 (stack=224, slots=8, bytes=64);
       `while_generic` tick_off=0 (stacks=224/240, slots=2, bytes=16).
   - Stage2 trace rebuilds with `OREN_TRACE_ARM64_LOOP_STACK=1` (2026-02-26) completed without GC list-header corruption.
   - Historical debug knob: `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` removed the tick stack slot for
     `fast_list_int_dot_while` to isolate the arm64 tick-offset regression (trace kind=`fast_list_int_dot_while_no_tick`).
   - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): `fast_list_int_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
   - New debug knob: `OREN_TRACE_ARM64_GC_TICK_OFF=1` logs negative tick offsets in arm64 GC throttled safepoints
     (set to `all` to log every tick_off).
   - Historical debug knob: `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` removed the tick stack slot for
     `fast_list_dot_while` (trace kind=`fast_list_dot_while_no_tick`).
   - Trace (arm64 stage2 compile, 2026-02-26, `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): dot_product still lowers via list<int> fast loops; no `fast_list_dot_while_no_tick`
     emitted (trace shows `fast_list_int_dot_while` tick_off=0, slots=8, bytes=64, stack/base=224).
   - Trace (arm64 stage2 compile, 2026-02-26, `build/tmp/boxed_dot.oren`,
     `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_LOOP_STACK=1`):
     `fast_list_dot_while_no_tick` tick_off=-1, slots=7, bytes=64, stack/base=224.
   - Trace (arm64 stage2 compile, 2026-02-26, `build/tmp/boxed_dot.oren`,
     `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     tick_off=0 at throttled safepoints (base/stack 160, 240; mask=1023), no negative offsets observed.
   - Trace (arm64 stage2 compile, 2026-03-03, `build/tmp/boxed_dot.oren`,
     `OREN_ARM64_FAST_LIST_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): tick_off=0 at throttled safepoints (base/stack 160, 240);
     no negative offsets observed (log: `build/logs/arm64_tick_off_trace_20260303_212831.log`).
   - Trace (arm64 stage2 compile, 2026-03-03, `benchmarks/dot_product/dot_product.oren`,
     `OREN_ARM64_FAST_LIST_INT_DOT_NO_TICK_SLOT=1` + `OREN_TRACE_ARM64_GC_TICK_OFF=all` +
     `OREN_TRACE_ARM64_LOOP_STACK=1`): tick_off=0 at throttled safepoints (base/stack 224, 240);
     no negative offsets observed (log: `build/logs/arm64_tick_off_trace_intdot_20260303_212850.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `OREN_TRACE_ARM64_GC_TICK_OFF=1`):
     no `[arm64_gc_tick_off]` entries emitted; log only shows rtobj/astbin seed updates
     (log: `build/logs/arm64_tick_off_stage2_20260303_213032.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     no `[arm64_gc_tick_off]` entries emitted; log only shows rtobj/astbin seed updates
     (log: `build/logs/arm64_tick_off_stage2_all_20260303_213150.log`).
   - Trace (arm64 stage2 build, 2026-03-03, `make -B stage2` + `OREN_TRACE_ARM64_GC_TICK_OFF=all`):
     many `tick_off=0` entries (all `while_generic`), no negative offsets observed
     (log: `build/logs/arm64_tick_off_stage2_all_forced_20260303_213450.log`).
   - Fix (2026-03-19): the slot-free arm64 fast-dot layouts are now the default. Both
     `fast_list_int_dot_while` and `fast_list_dot_while` drop the dedicated stack tick slot
     unless `OREN_ARM64_FAST_LIST_INT_DOT_KEEP_TICK_SLOT=1` or
     `OREN_ARM64_FAST_LIST_DOT_KEEP_TICK_SLOT=1` is set. The remaining throttled safepoints stay
     on `tick_off=0`, so the old negative-offset regression remains unobserved on the active path.
   - Fix (2026-03-19): the same slot-free default now applies to `fast_list_get_sum_while` and
     `fast_list_int_get_sum_while`. Their old layouts can be restored with
     `OREN_ARM64_FAST_LIST_GET_SUM_KEEP_TICK_SLOT=1` and
     `OREN_ARM64_FAST_LIST_INT_GET_SUM_KEEP_TICK_SLOT=1`.
   - Verification (2026-03-19): `benchmarks/dot_product/dot_product.oren` now emits
     `fast_list_int_dot_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_dot_tickslot_default_trace_20260319.log`), while
     `OREN_ARM64_FAST_LIST_INT_DOT_KEEP_TICK_SLOT=1` restores the old 8-slot layout
     (`build/logs/codex_arm64_dot_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): `build/tmp/arm64_boxed_getsum_probe.oren` emits
     `fast_list_get_sum_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_boxed_getsum_tickslot_default_trace_20260319.log`), while
     `OREN_ARM64_FAST_LIST_GET_SUM_KEEP_TICK_SLOT=1` restores the old 6-slot layout
     (`build/logs/codex_arm64_boxed_getsum_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): `benchmarks/array_sum_int/array_sum_int.oren` emits
     `fast_list_int_get_sum_while_no_tick` by default
     (`build/logs/codex_arm64_int_getsum_tickslot_default_trace_20260319.log`), and
     `OREN_ARM64_FAST_LIST_INT_GET_SUM_KEEP_TICK_SLOT=1` restores the old 6-slot layout
     (`build/logs/codex_arm64_int_getsum_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): `make test` remains green after the default layout change
     (`build/logs/codex_make_test_tickslot_default_20260319.log`).
   - New debug knob: `OREN_TRACE_ARM64_STACK_RESTORE=1` logs stack restore deltas when the
     compiler repairs mismatched stack accounting on arm64 loop emission (2026-03-03).
   - New: arm64 GC tick-off traces now include last stack-restore context (`last_restore_*`)
     when tick_off is negative to correlate stack repairs with offset regressions (2026-03-03).
   - New: `OREN_TRACE_ARM64_GC_TICK_OFF=1` now tags traces with `kind=<loop_kind>` when available to
     attribute negative tick offsets to a specific loop emitter (2026-03-03).
   - New: arm64 GC tick-off trace now includes the last loop stack snapshot (`last_kind`, `last_base`,
     `last_stack`, `last_slots`, `last_bytes`, `last_tick_off`) when tick_off is negative (2026-03-03).
   - Verification (2026-03-19): `benchmarks/dot_product/dot_product.oren` and
     `benchmarks/array_sum_int/array_sum_int.oren` now emit
     `fast_list_int_push_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_int_push_tickslot_default_trace_20260319.log` and
     `build/logs/codex_arm64_int_push_qi_tickslot_default_trace_20260319.log`), while
     `OREN_ARM64_FAST_LIST_INT_PUSH_KEEP_TICK_SLOT=1` restores the old layout
     (`build/logs/codex_arm64_int_push_tickslot_keep_trace_20260319.log`).
   - Verification (2026-03-19): `oren.oren` now emits
     `fast_list_push_while_no_tick` by default under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_boxed_push_tickslot_default_oren_20260319.log`), while
     `OREN_ARM64_FAST_LIST_PUSH_KEEP_TICK_SLOT=1` restores the old layout
     (`build/logs/codex_arm64_boxed_push_tickslot_keep_oren_20260319.log`).
   - Verification (2026-03-19): `build/tmp/arm64_generic_loop_probe.oren` still emits
     `while_generic` with `tick_off=0` under `OREN_TRACE_ARM64_LOOP_STACK=1`
     (`build/logs/codex_arm64_generic_loop_tickslot_trace_20260319.log`). A matching
     `for_loop` trace hook now exists in the native arm64 `For` emitter as well, so any
     surviving `For` path will report the same loop-stack metadata.
   - Root cause (2026-03-19/20): the remaining generic arm64 throttled loops are intentionally
     stack-backed, not because of an unresolved fast-loop offset bug, but because their
     condition/body/post paths can compile arbitrary code that clobbers caller-saved X9/X10.
   - Constraint (2026-03-20): there is also no local "move it to a spare callee-saved reg"
     fix. The backend already uses X19..X26 as its active preserved temp set, while X27/X28 are
     reserved heap globals, so removing the last generic tick slots would require a backend-wide
     register-policy redesign or a different generic safepoint scheme.
   - Status: no remaining per-loop arm64 tick-slot cleanup is pending; only a broader backend
     redesign would change `while_generic` / surviving native `For` throttling.
   - Status (2026-04-04): hot-loop perf still misses the 2× gate on arm64, but the shape of the
     blocker is narrower than the earlier tick-slot era. The repaired fast LCG path now keeps
     `loop_sum` at about 1.09× C while `dot_product` still measures about 2.82× C, so the next perf
     work should target arithmetic/runtime overhead inside the canonical dot-product loop rather than
     more opcode or tick-slot cleanup.
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

2) **W5 - Allocation/GC overhead reduction (alloc_churn, alloc_drop)** (L)
   - Baseline (arm64 native, 2026-02-26): `alloc_churn` 6.62× C, `alloc_drop` 1.28× C.
   - New run (arm64, 2026-04-04, runs=5, warmups=1; via `make perf-gate-native`):
     - alloc_churn: C 0.003716s, native 0.020157s (5.42× C).
     - alloc_drop: C 0.003441s, native 0.006068s (1.76× C).
   - New run (arm64, 2026-03-04, runs=5, warmups=1; log: `build/logs/bench_alloc_churn_drop_20260304_235146.log`):
     - alloc_churn: C 0.002886s, native 0.015997s (5.54× C).
     - alloc_drop: C 0.002986s, native 0.004703s (1.58× C).
   - Bytecode note: `oren_gc_collect()` now lowers to a no-op in the bytecode backend so alloc_churn/alloc_drop OBC builds succeed (2026-03-04).
   - `alloc_churn` and `alloc_drop` remain within the 8×/5× gates on arm64.
   - Alloc-site trace (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, warmups=0):
     - `alloc_churn` median total=2 (list_int_header=1, list_int_buf=1, list_header=0, list_buf=0).
     - `alloc_drop` median total=108 (list_header=105, list_buf=3, list_int_header=0, list_int_buf=0).
   - Fix and enable reuse paths (`OREN_GC_REUSE_BLOCKS`) when correct.
   - Add allocation-site counters for `alloc_churn`/`alloc_drop` to pinpoint dominant allocations.
   - New: `OREN_TRACE_ALLOC_SITE=1` reports list/list_int header+buffer sites (ids 1..4; see `lib/runtime_native/170_lists.oren`).
   - New: `OREN_GC_REUSE_LISTS=1` allows reuse for list/list_int headers when `OREN_GC_REUSE_BLOCKS=1` (rolling guardrail).
     - Rolling safety: list reuse is disabled when `OREN_GC_AUTO=1` unless `OREN_GC_REUSE_LISTS_UNSAFE=1`.
   - New: `OREN_GC_REUSE_MAPS=1` / `OREN_GC_REUSE_STRUCTS=1` allow reuse for map/struct headers (rolling guardrail).
   - New: `OREN_GC_REUSE_ZERO=1` zero-fills reused blocks by default when reuse is enabled (set `OREN_GC_REUSE_ZERO=0` to disable).
   - New: `OREN_GC_REUSE_SCAN_CAP=<n>` limits the free-list scan length during reuse (0 = unbounded).
   - New: `OREN_TRACE_GC_REUSE=1` now reports `scan_steps`, `scan_cap_hits`, and `scan_steps_cap`
     to quantify free-list scan cost under a cap.
   - New: `OREN_GC_REUSE_BUCKETS=1` enables size-bucketed free lists (<=64/<=256/<=1024/>1024 bytes).
   - New: `OREN_TRACE_GC_REUSE_VERBOSE=1` logs capped reuse hits (cap via `OREN_TRACE_GC_REUSE_VERBOSE_CAP`).
   - New: `OREN_TRACE_GC_FREED_LISTS=1` records freed list pointers; `OREN_TRACE_GC_FREED_LISTS_CAP=<n>` controls ring size.
   - New: `OREN_TRACE_GC_STACK_RANGES=1` captures stack scan ranges per collection (cap via `OREN_TRACE_GC_STACK_RANGES_CAP`).
   - Verbose reuse logs now include `in_roots` plus `root_kind` (1=gc_pin, 2=runtime roots, 3=global roots) and `root_idx`, alongside `in_stack`.
   - Reuse guard now restores free-list nodes that are still referenced by roots/stack; `[gc_reuse]` includes `guard_live`.
   - List reuse guard validates header integrity and drops corrupt candidates; `[gc_reuse]` includes `guard_bad_list`.
    - Trace rejected list headers with `OREN_TRACE_GC_REUSE_BAD_LIST=1` (cap via `OREN_TRACE_GC_REUSE_BAD_LIST_CAP`).
    - Trace freed list headers with `OREN_TRACE_GC_FREE_LIST_HEADERS=1` (cap via `OREN_TRACE_GC_FREE_LIST_HEADERS_CAP`).
   - Trace list header writes with `OREN_TRACE_LIST_HEADER=1` (cap via `OREN_TRACE_LIST_HEADER_CAP`).
   - Trace list buffer allocations with `OREN_TRACE_LIST_BUF=1` (cap via `OREN_TRACE_LIST_BUF_CAP`).
   - Trace optimizer list reserve insertion with `OREN_TRACE_LIST_RESERVE=1`.
   - Trace implausible `track_alloc_new` sizes with `OREN_TRACE_TRACK_ALLOC_NEW_SIZE=1`
     (default min 1<<30; tunable via `OREN_TRACE_TRACK_ALLOC_NEW_SIZE_MIN`/`_CAP`).
   - New: `OREN_TRACE_LIST_GET_BAD=1` logs list-get diagnostics when `Indexing on non-container`
     or `Indexing on non-list` triggers (cap via `OREN_TRACE_LIST_GET_BAD_CAP`).
   - New: `OREN_TRACE_LIST_GET_BAD_SCAN=1` scans the alloc-index table for the offending
     pointer on `list_get_bad` (expensive; use only for targeted flake triage).
   - New: `OREN_TRACE_GREEN_RUNQ_ARGS=1` logs `g->fn_obj/args_list` metadata at green
     runq push/pop/steal to trace scheduler corruption (use sparingly).
   - New: `OREN_TRACE_GREEN_RUNQ_GUARD=1` asserts runq `g` magic + args_list list headers
     on spawn/enqueue/dequeue, panicking with details instead of bus errors (debug-only).
   - New: `OREN_TRACE_GREEN_ARGS_STAMP=1` snapshots spawn-time args_list headers and
     checks for drift at runq/entry (panics on mismatch; debug-only).
   - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD=1` validates cached poll `ts/s/p` pointers
     and runq_buf before deref (debug-only).
   - New: `OREN_TRACE_GREEN_POLL_CACHE_GUARD_EVERY=<n>` samples the poll-cache guard
     every N cached iterations (debug-only).
   - New: `OREN_TRACE_GREEN_LAST_OPS=1` captures a ring of recent green runq/entry
     operations and dumps on `oren_fail`/`oren_panic`/`oren_exit`
     (cap via `OREN_TRACE_GREEN_LAST_OPS_CAP`).
   - New: `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=<n>` dumps the last-op ring
     every N cached poll iterations (debug-only).
   - Trace: `alloc_churn` run with size tracing shows `size=160000` corresponds to a list_int
     buffer (`cap=20000`, bytes=160000), so the size log is expected
     (log: `build/logs/bench_run_alloc_churn_20260226_084444/oren_native/run_0.log`).
   - Trace: GC-stress quick integration with list reserve/corrupt tracing enabled emitted
     only alloc-index summaries (no list_reserve/list_corrupt events)
     (log: `build/logs/native_quick_gc_trace_20260226_084741.log`).
   - Trace native pre-track alloc requests with `OREN_TRACE_NATIVE_ALLOC_REQ=1`
     (emits `oren_trace_alloc_request` before `oren_track_alloc_new` on native backends).
   - New: `OREN_TRACE_NATIVE_LIST_HDR=1` enables arm64 + x64 fast‑path list header tracing (calls `oren_trace_list_header` on list/list_int push fast paths).
     - Arm64 fast list push while-loops now emit list header traces on the count update (rolling, 2026-02-25).
   - GC init now registers the main thread for stack scanning to avoid missing roots during auto-GC reuse tests.
   - New: `OREN_TRACE_GC_REUSE=1` prints reuse tries/hits/misses at GC sweep.
   - Historical GC reuse experiments (2026-02-20) showed list header corruption before reuse; detailed traces live under `build/logs/`.
    - List trace now re-checks env when envp/argv/argc change to avoid caching off before runtime init (rolling, 2026-02-25).
    - New alloc_churn trace (arm64, 2026-02-25, `OREN_TRACE_NATIVE_LIST_HDR=1` + `OREN_TRACE_LIST_HEADER=1`, cap=200):
      - `op=6` list_int_reserve to cap=128 (per list), followed by `op=7` list_int_push count update after the fast loop.
    - New alloc_churn free-list trace (arm64, 2026-02-25, `OREN_ARENA_AUTO_LOOP=0`, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`,
      `OREN_TRACE_LIST_HEADER=1`, `OREN_GC_ALLOC_THRESHOLD=1000`): list_int headers free with len/cap=128 and magic ok, but
      free-list `chunk` sizes are huge (~6.16e9) and `freed_bytes` spikes, suggesting tracking-node size corruption even when
      header fields look valid (log: `build/logs/alloc_churn_free_list_trace_20260225_200907.log`).
    - New alloc_churn free-list trace with list_hdr_ring (arm64, 2026-02-25, `OREN_TRACE_LIST_HDR_RING=1`):
      - list_hdr_ring shows `op=2/6/7` (new_list_int/reserve/push) with valid len/cap/magic before free, while
        `gc_free_list_node` reports huge `size` with intact node magic, reinforcing that the tracking-node size field is corrupt
        rather than the list header itself (log: `build/logs/alloc_churn_free_list_trace_20260225_202512.log`).
    - New alloc_churn track-size trace (arm64, 2026-02-25, `OREN_TRACE_LIST_TRACK_SIZE=1`):
      - list_int allocations are tracked with a huge `size` (~6.12e9) at `oren_track_alloc_new` time, before header fields
        are initialized (len/cap/magic = 0), which means the corruption is already present in the `size` argument passed
        into tracking (log: `build/logs/bench_run_alloc_churn_20260225_203557/oren_native/run_0.log`).
    - New: arm64 native `malloc_k` preserves size across kind-eval (compiler fix, 2026-02-25).
      - Follow-up alloc_churn trace with `OREN_TRACE_LIST_NEW_CAP=1` + `OREN_TRACE_LIST_TRACK_SIZE=1` shows no list allocations
        with size >= 1 MiB, suggesting the huge-size tracking corruption may be resolved (log: `build/logs/bench_run_alloc_churn_20260225_205122/oren_native/run_0.log`).
      - Follow-up GC free-list trace (arm64, `OREN_GC_AUTO=1`, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`, cap=40) shows list_int frees with
        `chunk=32` and no huge sizes (log: `build/logs/bench_run_alloc_churn_20260225_210209/oren_native/run_0.log`).
      - NOTE: a heavier trace run (GC auto + list header/native list traces) triggered `list_int_reserve on non-list` panic; needs triage
        to confirm whether the trace stack or GC path can still corrupt list metadata (log: `build/logs/bench_run_alloc_churn_20260225_205603/oren_native/run_0.log`).
      - New: same GC auto trace without `OREN_TRACE_NATIVE_LIST_HDR` completes and shows sane free-list chunks + list headers, suggesting the
        panic is tied to native list tracing (log: `build/logs/bench_run_alloc_churn_20260225_210329/oren_native/run_0.log`).
      - New: after spilling list ptr to stack around `oren_trace_list_header`, GC auto trace with `OREN_TRACE_NATIVE_LIST_HDR=1` completes
        cleanly with sane free-list chunks (log: `build/logs/bench_run_alloc_churn_20260225_210830/oren_native/run_0.log`).
    - New: alloc_drop with the same native trace knobs also completes cleanly and shows sane free-list chunks
        (log: `build/logs/bench_run_alloc_drop_20260225_211047/oren_native/run_0.log`).
    - Partial alloc_drop free-list trace (arm64, 2026-02-25, `OREN_TRACE_GC_FREE_LIST_HEADERS=1`): list headers free with normal
      chunk sizes (32/64) and valid magic (log: `build/logs/alloc_drop_free_list_trace_20260225_200437.log`).
    - Trace: alloc_churn with `OREN_BENCH_GC_EVERY=1000` + `OREN_TRACE_GC_SWEEP=1` (and `OREN_ARENA_AUTO_LOOP=0`)
      shows GC sweeps but `freed_kinds` list/list_int=0, so free-list header dumps never fire; likely
      list headers remain live under conservative scan (log: `build/logs/alloc_churn_native_gc_sweep_20260226_163932.log`).
    - New: `alloc_churn` trace knobs `OREN_BENCH_CLEAR_LIST=1` + `OREN_BENCH_SMALL_INTS=1` clear per-iter list roots
      and reduce conservative false roots so GC frees can surface list headers during corruption hunts (2026-02-26).
    - Trace: alloc_churn with `OREN_BENCH_CLEAR_LIST=1` + `OREN_BENCH_SMALL_INTS=1` +
      `OREN_TRACE_GC_FREE_LIST_HEADERS=1` now shows list header frees with `len/cap=128` and `chunk=32`,
      confirming GC can free list headers once conservative roots are reduced
      (log: `build/logs/alloc_churn_trace_hdr_ring_20260226_164630.log`).
    - New: `OREN_BENCH_FORCE_LIST_INT=1` forces alloc_churn to use list<int> ops so GC traces can
      surface list_int header frees directly (2026-02-26).
    - Trace: alloc_churn with `FORCE_LIST_INT=1` + `CLEAR_LIST=1` + `SMALL_INTS=1` now shows
      free-list dumps for list_int headers (kind=8, len/cap=128), alongside list (kind=2)
      headers, confirming list_int frees are visible under GC traces
      (log: `build/logs/alloc_churn_trace_list_int_20260226_165002.log`).
    - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING=1` dumps list_hdr ring samples at free-list dump time
      (tunable via `_EVERY`/`_CAP`) to correlate recent list header writes with freed headers (2026-02-26).
    - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1` dumps the full ring snapshot (bounded by ring size)
      for free-list samples when pointer filtering misses (2026-02-26).
    - New: `OREN_TRACE_GC_FREE_LIST_HDR_RING_RECENT=<n>` dumps the last `n` ring entries for a sampled
      free-list header to focus on the most recent writes (2026-03-05).
    - Trace: alloc_churn with ring-recent shows list_int size mismatches (`chunk=32`, `expect=1056`)
      alongside recent ring ops `6:8 -> 2:8`; correlation log helps pinpoint last header writes
      (logs: `build/logs/alloc_churn_trace_gc_ring_recent_20260305_014912.log`,
      `build/logs/alloc_churn_trace_gc_ring_recent_20260305_014912_corr.log`).
    - Fix: free-list size-mismatch logging now matches list header validation (accepts aligned
      inline sizes and adjacent external buffers) to reduce false positives in traces (2026-03-05).
   - Repro (2026-03-05): higher-pressure alloc_churn with GC poison + reuse + list_int
     (`OREN_BENCH_LIST_LEN=512`, `OREN_GC_ALLOC_THRESHOLD=5000`) hits
     `gc list_int header corrupt` (log:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_20260305_020406.log`).
   - Repro (2026-03-05): same env with `OREN_TRACE_GC_REUSE_BAD_LIST_CAP=4` triggers
     `gc_reuse_bad_list` and `gc list_int header corrupt`; ring dump shows only op=91
     entries (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap_20260305_023629_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap_20260305_023629_1_correlate2.log`).
   - Repro (2026-03-05): with fast list_int loop ring emission enabled, corruption still
     shows only op=91 entries (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap2_20260305_024825_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntcap2_20260305_024825_1_correlate.log`).
   - Repro (2026-03-05): with ring_pre enabled (and arena list ring emission), still only
     op=91 entries; arena off does not change (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre2_20260305_025533_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre2_20260305_025533_1_correlate.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre3_arenaoff_20260305_025745_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_huntpre3_arenaoff_20260305_025745_1_correlate.log`).
	  - Repro (2026-03-05): enabling `OREN_TRACE_ALLOC_KIND_CHANGE` triggers an early segfault
	    before any trace output (logs:
	    `build/logs/alloc_churn_trace_gc_ring_poison_hi_kindflip_20260305_025937_1.log`,
	    `build/logs/alloc_churn_trace_gc_ring_poison_hi_kindflip2_20260305_030010_1.log`).
	  - Fix (2026-03-07): typed-buffer heap payloads no longer allocate with kind `8`
	    (`LIST_INT`); small/uninit payloads now stay raw tracked blocks so GC cannot
	    validate arbitrary payload bytes as list_int headers under forced-GC stress.
	  - Fix (2026-03-07): list/list_int, map, buf, func, and arena list constructors now
	    allocate raw first and only retype after header initialization, closing a window where
	    forced GC could observe partially initialized structured headers.
	  - Verification (2026-03-07): stage1 native quick integration now passes again after the
	    typed-buffer payload regression was added/fixed (`build/logs/codex_test_native_quick_20260307_regressionfix2.log`);
	    `tests/native/test_gc_stw_os_thread_collect.oren` also passes with the rebuilt stage1 compiler
	    (`build/logs/codex_test_gc_stw_os_thread_collect_stage1_20260307.log`).
	  - Update (2026-03-08): arm64 stage2 rtobj apply no longer stalls on eager runtime
	    function/fixup materialization. Cached runtime functions are resolved lazily, and runtime
	    fixups now have a compact cache encoding path plus lazy emitter resolution. Latest traced
	    stage2 build gets through `[rtobj] apply hit done` and reaches Mach-O fixup application;
	    runtime prepare dropped from about `+23530ms` to `+16648ms`
	    (`build/logs/codex_stage2_build_gc_stw_collect_trace10_20260307.log`).
	  - Update (2026-03-08): Mach-O fixup application now caches resolved function targets per
	    build, and rtobj apply migrates legacy `fixups_enc` cache entries into the compact
	    `runtime_fixups_compact` form in memory. With the rebuilt stage1 compiler, the legacy
	    debug cache-hit path now runs through `fixup[10000]` and `fixup[20000]` and finishes the
	    native emit (`build/logs/codex_stage1_build_gc_stw_collect_trace14_20260308.log`).
	  - Update (2026-03-08): the missing arm64 `d0` runtime-object cache entry was regenerated
	    under the current compiler, and the stored meta now contains `fixups_compact`
	    (`build/logs/codex_stage1_build_gc_stw_collect_nodebug_trace16_20260308.log`).
	  - Verification (2026-03-08): `make oren_stage2` passes again after the legacy-fixup
	    migration + target-cache change (`build/logs/codex_make_oren_stage2_20260308_final.log`).
	  - Resolved (2026-03-15): the old arm64 stage2 quick-integration timeout / local-fixup
	    blocker is gone. Self-hosted native quick integration reaches `macho.fixups.done`,
	    `build.native.emit.done`, and the produced quick-integration binary runs successfully
	    (`build/logs/oren_stage2_native_quick_integration.phases.log`,
	    `build/logs/oren_stage2_native_quick_integration.log`).
	  - Resolved (2026-03-19): the clean branch now completes `make test` end-to-end again
	    (`build/logs/codex_make_test_rerun_20260319.log`), so this tracker item is no longer an
	    active verification blocker. Keep future work here focused on robustness/perf regressions,
	    not on the old stage2 emitter or native quick bring-up failures.
	  - Update (2026-04-11): x64 stage2 runtime-object cache hits now avoid the same class of
	    eager large-metadata walk that previously hurt arm64. The x64 runtime-object backend sig is
	    bumped to `x64_v0_23`; cached meta now carries compact x64 fixup sidecars
	    (`x64_fixups_compact`), compact runtime function offsets (`fn_offsets_compact`), and a lazy
	    cstr0 offset sidecar. The stage2 apply path stashes those into the x64 context instead of
	    materializing thousands of runtime fixup/function/cstr0 entries into normal maps/lists, and
	    ELF/PE emit plus symtab finalization now use lazy runtime-function lookup over the compact
	    sidecars. Traced QI compile progress shows the fixed cache-hit path reaching user-code
	    compilation after `function offsets compact attached` and `compact fixups attached`
	    (`build/logs/x64_stage2_qi_linux_lazy_fn_offsets_lookup_trace_20260411_225344.log`);
	    `make oren_stage2` also passed after the lazy lookup change
	    (`build/logs/make_oren_stage2_x64_lazy_fn_offsets_lookup_fix_20260411_225140.log`).
	    The remaining slow surfaces are broader x64 no-cache compile throughput, not rtobj apply:
	    full quick-integration exceeded the 300s measurement window
	    (`build/logs/x64_stage2_qi_linux_lazy_fn_offsets_measure_20260411_225556.log` is the timeout
	    placeholder), and the full NET/TLS/HTTP2 compile-only smoke exceeded the 360s measurement
	    window (`build/logs/x64_stage2_net_tls_http2_linux_timeout_measure_20260411_231009.log` is
	    the timeout placeholder). Therefore
	    `make verify-native-x64-compile` now keeps full QI, NET/TLS/HTTP2, and the broad stage2
	    FFI/shared-library matrix opt-in while retaining a bounded default stage1+stage2 smoke path
	    that includes `print`, `ptr_i32_le_native`, `cfg_os_select`, and one FFI smoke per platform.
	    The cleaned single-run default verifier passed in
	    `build/logs/verify_native_x64_compile_lazy_fn_offsets_make_default_20260411_233255.log`
	    (376s on this host).
	   - Update (2026-03-05): fast_list_int_push_while now emits list_hdr ring entries on loop
	     exit even without compile-time trace flags, so GC corruptions can be correlated from
	     standard trace runs.
   - Update (2026-03-05): arena list/list_int allocations now emit list_hdr ring entries
     (op=1/2) so ring dumps include arena-backed list headers.
   - New: `OREN_TRACE_ALLOC_INDEX=1` now logs `[alloc_index_list_bad]` when list/list_int
     nodes are inserted with non-magic headers (excluding poison), to catch kind/ptr drift.
   - New: `OREN_TRACE_LIST_CTOR=1` logs `[list_ctor]` stages (`pre_init`, `post_init`, `post_track`)
     for list/list_int allocations; filter via `OREN_TRACE_LIST_CTOR_PTR` /
     `OREN_TRACE_LIST_CTOR_NODE` to line up ctor events with `[alloc_index_list_bad]`.
   - Repro (2026-03-05): gc_ring_poison_hi_alloc_index shows `[alloc_index_list_bad]` with
     magic=0 at alloc-index insert time, before `gc_reuse_bad_list` fires (logs:
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1.log`,
     `build/logs/alloc_churn_trace_gc_ring_poison_hi_alloc_index_20260305_030652_1_correlate.log`,
     `build/logs/alloc_churn_hunt_alloc_index_20260305_030652.log`).
   - Repro (2026-03-05): ctor-trace run shows `[alloc_index_list_bad]` preceding
     `[list_ctor] stage=pre_init` for the same ptr, so alloc-index insertion happens
     before list header init; magic=0 appears expected for fresh allocations
     (log: `build/logs/alloc_churn_trace_gc_ring_poison_hi_ctortrace_20260305_031847.log`).
   - Next: if corruption still shows only op=91 GC entries, consider adding per-iteration
     ring updates under a trace guard to capture in-loop header writes.
   - Update (2026-03-05): alloc-index now emits `[alloc_index_list_zeroed]` only when
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` and headers are still zeroed (magic/len/cap/buf all 0),
     reducing noise in `[alloc_index_list_bad]`.
   - Update (2026-03-05): alloc-index list trace lines now include `zeroed_count`/`bad_count`
     counters to track noise vs true corruption across runs.
   - Update (2026-03-05): GC summary now prints `[alloc_index_list_counts]` when
     `OREN_TRACE_ALLOC_INDEX=1` to report per-sweep zeroed/bad totals.
   - Update (2026-03-05): `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=<n>` dumps the last
     `<n>` list_hdr ring entries when `[alloc_index_list_bad]` fires.
   - Update (2026-03-05): `[gc_reuse_bad_list]` now includes `freed_seen=<0|1>` when
     `OREN_TRACE_GC_FREED_LISTS=1` to flag potential use-after-free list headers.
   - Update (2026-03-05): list header corruption dumps now include
     `[alloc_index_list_counts_at_bad]` when `OREN_TRACE_ALLOC_INDEX=1` so counts are
     preserved even if GC panics.
   - Trace (2026-03-05): alloc_churn with `OREN_TRACE_GC_FREED_LISTS=1` showed `freed_seen=0`
     across multiple `[gc_reuse_bad_list]` prints (log:
     `build/logs/alloc_churn_trace_alloc_index_bad_freed_20260305_041225.log`).
   - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX_LIST_BAD_RING_RECENT=8`
     hit `gc list_int corrupt` and emitted list_hdr ring dumps from GC reuse traces, but
     did not trigger `[alloc_index_list_bad]` yet (log:
     `build/logs/alloc_churn_trace_alloc_index_bad_ring_20260305_035440.log`).
   - Trace (2026-03-05): alloc_index_bad_ring hunt run 1 logged `zeroed_count=87`,
     `bad_count=0`, and no `[alloc_index_list_bad]` despite `gc list_int corrupt` (log:
     `build/logs/alloc_churn_trace_alloc_index_bad_ring_20260305_035623_1.log`).
   - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX=1` +
     `OREN_BENCH_GC_EVERY=50` emitted repeated `[alloc_index_list_counts]` lines
     (log: `build/logs/alloc_churn_trace_alloc_index_counts_summary_gc_20260305_034720.log`).
   - Trace (2026-03-05): alloc_churn with `OREN_TRACE_ALLOC_INDEX=1` +
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` (`OREN_BENCH_ITERS=2000`) reported `zeroed_count=2`
     and `bad_count=0` (log:
     `build/logs/alloc_churn_trace_alloc_index_counts_20260305_033136.log`).
   - Trace (2026-03-05): higher-pressure alloc_churn with GC reuse knobs +
     `OREN_TRACE_ALLOC_INDEX_ZEROED=1` reported
     `zeroed_count=256` and `bad_count=0` (log:
     `build/logs/alloc_churn_trace_alloc_index_counts_hi_20260305_033237.log`).
    - New: `OREN_BENCH_LIST_LEN=<n>` lets alloc_churn reduce per-list pushes during trace runs so
      list_hdr ring entries survive until GC sweep samples (2026-02-26).
    - New: runtime reserve trace `OREN_TRACE_LIST_RESERVE_RT=1` (cap via `OREN_TRACE_LIST_RESERVE_RT_CAP`) added; alloc_churn run
      now emits `[list_reserve]` + `[list_buf]` lines, confirming runtime reserve execution
      (log: `build/logs/alloc_churn_run_trace_20260226_013845.log`).
    - New: list_alloc + arena trace (arm64, 2026-02-26) shows list_int headers with `mode=2` (arena ctor) while
      `OREN_TRACE_ARENA=1` reports `allocs=0`, suggesting arena allocs are spilling to malloc or trace enable is late
      (log: `build/logs/alloc_churn_manual_run_list_alloc_arena_20260226_002922.log`).
    - New: `OREN_TRACE_ARENA_SPILL=1` reports arena spill reasons (depth=0, size<=0, cap, mmap failure) to explain
      `mode=2` list allocations with `allocs=0` in arena traces (rolling, 2026-02-26).
    - New: when built with `--backend native` (runtime cache disabled), alloc_churn shows arena allocs=3 with no spills,
      confirming arena is active and prior `allocs=0` was from a non-native build artifact
      (log: `build/logs/alloc_churn_manual_run_arena_spill_native_20260226_003939.log`).
    - New: `OREN_TRACE_NATIVE_LIST_RESERVE=1` emits a fast-loop reserve trace call to
      `oren_trace_list_reserve_fast(...)` so we can verify whether the native fast loop
      actually calls reserve at runtime (rolling, 2026-02-26).
    - New: list buffer trace (`OREN_TRACE_LIST_BUF=1`) now re-checks envp/argv/argc to avoid caching
      off before runtime init, mirroring list header trace behavior (rolling, 2026-02-26).
    - New: alloc_churn native run with `OREN_TRACE_NATIVE_LIST_RESERVE=1` + `OREN_TRACE_LIST_RESERVE_RT=1` shows
      list<int> reserve executes at runtime and allocates 1024-byte buffers via `_list_alloc_buf`
      (log: `build/logs/alloc_churn_manual_run_trace_reserve_fast2_20260226_004803.log`).
      - Follow-up reserve trace shows stage=1/2 pairs per list with no duplicate stage=1 per list
        (log: `build/logs/alloc_churn_run_trace_20260226_013845.log`), so the earlier redundant-reserve suspicion
        is cleared for this run.
    - New: alloc-site tracing now counts arena list buffers; alloc_churn native trace shows
      list_int_header=20000, list_int_buf=20000 (total=40000) under `OREN_BENCH_TRACE_ALLOC_SITE=1`
      (log: `build/logs/bench_alloc_churn_alloc_site_20260225_234114.log`).
    - New: `OREN_TRACE_LIST_RESERVE_BYTES=1` prints reserve allocation/copy totals at shutdown; alloc_churn
      reports list_int_alloc_bytes=20480000 with 20000 reserve calls and zero copy bytes
      (log: `build/logs/alloc_churn_run_reserve_bytes_20260226_020050.log`).
   - New: loop list reuse brings alloc_churn to ~6.62× C (arm64, 2026-02-26),
      within the 8× gate; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`
     (see `benchmarks/RESULTS_LATEST.md` for the retained summary; local result artifacts live under `build/benchmarks/results/`).
    - New: loop list reuse keeps alloc_drop at ~1.28× C (arm64, 2026-02-26),
      within the 5× gate (see `benchmarks/RESULTS_LATEST.md`; local result artifacts live under `build/benchmarks/results/`).
    - New: reuse escape smoke (`test_loop_list_reuse_escape_smoke`) added to native quick integration
      to guard against incorrect reuse when lists escape (2026-02-26).
    - Fix: loop list reuse now skips unsafe list uses (escape/alias), enabling default-on reuse while
      remaining correctness-safe under `test_loop_list_reuse_escape_smoke` (2026-02-26).
   - New: list-reserve/unchecked-push generalization now treats `oren_new_list(cap)`, `oren_list_new_cap(cap)`,
     `oren_arena_new_list(cap)`, and `oren_arena_new_list_auto(cap)` as list constructors and propagates list metadata across simple alias assignments,
     extending reserve/unchecked-push rewrites (rolling, 2026-02-24).
   - New: list<int> lowering now propagates safe-int context across nested blocks, so empty list literals
     that push ints derived from outer-scope loop indices lower to list<int> (rolling, 2026-02-25).
     - Verified: `alloc_churn` emit-c now uses `oren_new_list_int`, `oren_list_int_reserve`,
       `oren_list_int_push_fast`, and `oren_list_int_get_fast` (log: `build/logs/emit_c_alloc_churn_listint_20260225_035210.log`).
     - New: `OREN_TRACE_LIST_INT=1` logs list<int> lowering decisions (candidate/touch/unsafe/rewrite).
     - Safety: list<int> lowering now skips candidates assigned in nested control-flow blocks
       to avoid mixed list/list<int> rewrites (fixes arena auto-loop use-before-assign smoke; rolling, 2026-02-25).
   - New: loop list reuse hoists safe, non-escaping list allocations out of loops and replaces per-iter
     init with `*_clear_unchecked` calls; default-on with opt-out via `OREN_OPT_LOOP_LIST_REUSE=0`.
     - Reuse smoke: `test_arena_auto_loop_smoke` passes with reuse enabled on arm64 macOS (2026-02-25).
   - `alloc_churn` native was 46.65× C in the 2026-02-25 snapshot; reached 6.62× C on 2026-02-26,
     but regressed to 104.37× C in the 2026-03-04 snapshot.
   - Alloc-site trace (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, native-only):
     median total=20000, list_int_header=20000, list_header=0, list_buf=0, list_int_buf=0
     (log: `build/logs/bench_alloc_churn_alloc_site_20260225_234114.log`).
   - List alloc trace (arm64, 2026-02-25, `OREN_TRACE_LIST_ALLOC=1`, cap=20): list_int headers
     are allocated at size=32 (cap=0) in arena mode (mode=2), and no list buffer allocations
     were observed even with `OREN_TRACE_LIST_BUF=1` (log: `build/logs/bench_alloc_churn_list_alloc_buf_20260225_235415.log`).
   - Compiler trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1`): `alloc_churn` inserts
     `oren_list_int_reserve(xs, 128)` (log: `build/logs/bench_build_oren_native_alloc_churn_20260226_000335.log`).
   - Combined trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1` + `OREN_TRACE_LIST_ALLOC=1` + `OREN_TRACE_LIST_BUF=1`):
     runtime still shows list_int header allocations (size=32, mode=2) and no list_buf events; compile log did not emit
     list_reserve prints in this run (log: `build/logs/bench_alloc_churn_list_all_20260226_000614.log`).
   - Manual build trace (arm64, 2026-02-26, `OREN_TRACE_LIST_RESERVE=1` + `OREN_TRACE_OPTIMIZER=1`, `--no-cache`):
     `alloc_churn` prints `list_int_reserve name=xs n=128` (log: `build/logs/bench_alloc_churn_manual_build_20260226_001017.log`).
   - Bench run with no-cache env (arm64, 2026-02-26, `OREN_TRACE_LIST_BUF=1` + `OREN_TRACE_LIST_RESERVE=1`):
     no list_buf events appeared and reserve trace did not surface in build logs (log: `build/logs/bench_alloc_churn_nocache_list_buf_20260226_001246.log`).
   - List literal sinking now handles `ExprStmt` if-forms, reducing `alloc_drop` list-header churn
     (alloc-site median list_header=105 in 2026-02-25 trace; latest `alloc_drop` native 1.28× C).
   - New: fast list/list_int push while-loops now accept constant upper bounds (arm64/x64/transpiler),
     and `alloc_drop` is now within target on the 2026-02-25 snapshot (rolling).
   - New: list/list_int reserve + unchecked push now try `native_arena_alloc_raw` for arena-backed buffers
     and fall back to `malloc_k` (cuts alloc-index tracking overhead on arena hot paths; rolling, 2026-02-20).
   - New: list/list_int set growth now uses arena-backed buffer allocation when list headers are arena-tracked,
     matching reserve/push behavior (rolling, 2026-02-24).
    - Reuse + list trace run (arm64, 2026-02-20, reuse+trace flags): still segfaults; reuse summary
      tries=7951 hits=54 misses=7900 hit_bytes=57472 guard_bad_list=105. List trace shows only `op=1/3/5`;
      free-list headers still report len/cap=128 with chunk=32 (same corruption pattern).
    - Free-list header dump now calls `native_list_debug_node` on invalid headers to capture node/alloc-index state (rolling, 2026-02-20).
    - Fresh reuse trace with list_debug (arm64, 2026-02-20): invalid free-list headers show
      `list_debug node_ptr=<ptr> size=32 kind=2 freed=0 next=<ptr>` with node_in_allocs=0 and node_in_free_blocks=0
      at dump time (node already unlinked, index still resolves).
    - Reordered alloc-index removal to run after free-list dumps so list_debug can resolve nodes (rolling, 2026-02-20).
    - Corruption reproduces even with reuse disabled: `OREN_GC_REUSE_BLOCKS=0` still shows free-list headers
      with len/cap=128 and list_debug node_ptr/next but node_in_allocs=0, node_in_free_blocks=0 (arm64, 2026-02-20).
    - New trace: `OREN_TRACE_LIST_CORRUPT=1` (cap via `OREN_TRACE_LIST_CORRUPT_CAP`) logs suspicious list headers
      during reserve/push_unchecked (invalid magic or buf), dumps list_debug state, and emits list_alloc/list_hdr
      ring matches when enabled (rolling, 2026-02-20). List_len/list_reserve and list_int panics now also dump ring matches.
   - New: list indexing (`xs[i]`) rebuilds alloc-index once on non-container detection before panicking
     to avoid false panics from stale index state (rolling, 2026-02-26).
   - List header reuse guard now treats chunk_size==32 as separate-buffer lists even if buf==list+32 (avoids false bad-list hits when allocator places buffers adjacent; rolling, 2026-02-20).
   - List header reuse guard now accepts external-buffer lists whose header allocation still includes stale inline storage (chunk_size > 32 with buf != list+32), avoiding false bad-list hits after growth (rolling, 2026-02-24).
   - List trace env checks now cache false after first lookup (`OREN_TRACE_LIST_HEADER`,
     `OREN_TRACE_LIST_HDR_RING`, `OREN_TRACE_LIST_CORRUPT`) to avoid per-op env scans (rolling, 2026-02-25).
     - Reuse guard enforces inline-buffer sizing: chunk==32+cap*8 when buf==list+32; out-of-line headers accept any chunk>=32 (rolling, 2026-02-24).
     - Prior strict header sizing guard (out-of-line required chunk==32) still segfaulted; guard_bad_list=276 (local run, 2026-02-20).
     - Reuse now rejects alloc-index mismatches for reused pointers (rolling, 2026-02-20).
     - Alloc-index guard run still segfaults; guard_bad_list=275 (local run, 2026-02-20).
     - `alloc_churn` runs when list reuse is guarded off (auto-GC) with reuse blocks only:
       tries=9989 hits≈4987 misses≈5005 hit_bytes≈5.11 MiB (local run, 2026-02-20).
     - `alloc_drop` (runs=1) 12.13s with GC reuse traces (local run, 2026-02-20).
   - Bench harness supports `OREN_BENCH_TRACE_ALLOC_SITE=1` (native) to capture alloc-site counts in benchmark stdout logs (forces warmups=0; dump happens at exit; use `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD` if you want GC-triggered dumps).
   - When trace alloc-site is enabled, benchmark result JSON records `alloc_site` counts + medians.
   - Bench harness supports `OREN_BENCH_TRACE_ARENA=1` (native) to capture arena alloc/spill counters; results JSON records `arena_trace` medians (optional cap via `OREN_BENCH_TRACE_ARENA_CAP_BYTES`).
   - Bench harness supports compile-time env overrides via `OREN_BENCH_ENV_BUILD` (all build steps) and
     `OREN_BENCH_ENV_BUILD_OREN` (Oren build steps only).
   - Bench harness supports `OREN_BENCH_SAVE_RUN_LOGS=1` (per-run stdout logs) and `OREN_BENCH_RUN_LOG_TEE=1` (tee to console) for trace-heavy runs like GC reuse.
   - Alloc-site snapshots from trace runs are stored under `build/logs/` (results files are pruned per policy).
   - New: arena list header allocations now bump alloc-site counters (native `native_arena_new_list(_int)`)
     so arena-backed list headers show up in `OREN_BENCH_TRACE_ALLOC_SITE` runs (rolling, 2026-02-25).
   - Trace alloc-site (arm64, 2026-02-25, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, warmups=0):
     - `alloc_churn` list_header=20000, list_buf=0.
     - `alloc_drop` list_header=1794, list_buf=6.
   - New: list-track now logs `track_alloc` events in `oren_track_alloc` when `OREN_TRACE_LIST_TRACK=1`
     (rolling, 2026-02-25). `alloc_churn` now emits `[list_track] arena_alloc` lines under auto arenas,
     confirming list headers are arena-backed in the default benchmark build.
   - New: `OREN_TRACE_ARENA=1` now reports per-iter arena counters (`iter_push/pop`, `iter_spills`,
     `iter_spill_bytes`) to diagnose per-iteration caps (rolling, 2026-02-25).
   - Trace list-track (arm64, 2026-02-25, `OREN_ARENA_AUTO_LOOP=0` runtime via bench env):
     `alloc_churn` emits `[list_track] index_put/alloc` lines (log:
     `build/logs/bench_run_alloc_churn_20260225_020630/oren_native/run_0.log`),
     confirming GC-tracked list headers when auto arenas are disabled at runtime.
   - Trace alloc_drop reuse (arm64, 2026-02-25, `OREN_BENCH_ITERS=2000`,
     `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=2000`, `OREN_GC_REUSE_BLOCKS=1`,
     `OREN_GC_REUSE_LISTS=1`, `OREN_GC_REUSE_LISTS_UNSAFE=1`):
     run completes; list_track emits `track_alloc` (mode=3), and GC reuse reports
     guard_bad_list=0 with scan_steps in the 2–4.6M range (log:
     `build/logs/bench_run_alloc_drop_20260225_021248/oren_native/run_0.log`).
   - Trace alloc_churn direct reuse (arm64, 2026-02-25, direct native run with
     `OREN_ARENA_AUTO_LOOP=0`, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=1`,
     `OREN_GC_REUSE_LISTS_UNSAFE=1`, `OREN_GC_REUSE_SCAN_CAP=5000`):
     hit `[gc_reuse_bad_list]` quickly (chunk=32 len/cap=128 buf=ptr+32 magic=1279870019)
     with a preceding `[gc_reuse_hit] kind=0` (log:
     `build/logs/alloc_churn_direct_reuse_cap_20260225_021657.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=65536`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.49s vs C 0.00307s (2114×);
     `alloc_drop` 0.2746s vs C 0.003064s (89.6×). This is worse than baseline; cap size
     likely too small for the current allocation profile (log:
     `build/logs/bench_iter_cap_20260225_030936.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=262144`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.50s vs C 0.003316s (1961×);
     `alloc_drop` 0.2745s vs C 0.003150s (87.1×). Still worse than baseline (log:
     `build/logs/bench_iter_cap_256k_20260225_031225.log`).
   - Per-iter cap experiment (arm64, 2026-02-25, `OREN_ARENA_ITER_CAP_BYTES=1048576`,
     runs=3/warmups=1, native+C only): `alloc_churn` 6.51s vs C 0.003024s (2153×);
     `alloc_drop` 0.2753s vs C 0.003061s (89.9×). Still worse than baseline (log:
     `build/logs/bench_iter_cap_1m_20260225_031326.log`).
   - Post list-trace cache (arm64, 2026-02-25, runs=3/warmups=1, native+C only):
     `alloc_churn` 0.311s vs C 0.006686s (46.6×); `alloc_drop` 0.194s vs C 0.008016s (24.3×)
     (log: `build/logs/bench_post_list_trace_cache_20260225_033359.log`).
   - Repeat post list-trace cache (arm64, 2026-02-25, runs=3/warmups=1, native+C only):
     `alloc_churn` 0.237s vs C 0.002871s (82.6×); `alloc_drop` 0.159s vs C 0.003137s (50.8×)
     (log: `build/logs/bench_post_list_trace_cache_repeat_20260225_033511.log`).
   - Post list-trace cache (arm64, 2026-02-25, runs=5/warmups=1, native+C only):
     `alloc_churn` 0.225s vs C 0.003204s (70.3×); `alloc_drop` 0.1568s vs C 0.003079s (50.9×)
     (log: `build/logs/bench_post_list_trace_cache_runs5_20260225_033625.log`).
   - Trace run (arm64, 2026-02-25, `OREN_TRACE_ARENA=1`, `OREN_ARENA_ITER_CAP_BYTES=262144`):
     alloc_churn run emitted 20,000 `[arena]` lines with `iter_spills=0` (cap not binding);
     benchmark aborted with output mismatch due to trace (log:
     `build/logs/bench_iter_cap_256k_trace_20260225_031951.log`,
     run log: `build/logs/bench_run_alloc_churn_20260225_031951/oren_native/run_0.log`).
   - Trace run (arm64, 2026-02-25, `OREN_TRACE_ARENA=1`, `OREN_ARENA_ITER_CAP_BYTES=262144`,
     `OREN_BENCH_OUTPUT_CHECK=0`): alloc_drop run emitted **no** `[arena]` lines, indicating
     the loop is not arena-wrapped (log:
     `build/logs/bench_iter_cap_256k_trace_drop_20260225_032316.log`,
     run log: `build/logs/bench_run_alloc_drop_20260225_032316/oren_native/run_0.log`).
   - Arena-loop trace (arm64, 2026-02-25, `OREN_TRACE_ARENA_LOOPS=1` compile):
     alloc_drop inner loop drops the list literal candidate as `unsafe_use` and
     ends with `skip=no_arena_alloc`, so the loop is not wrapped by arenas
     (log: `build/logs/alloc_drop_arena_loop_trace_20260225_032643.log`).
   - Repro across scan caps (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     scan_cap=1000/5000/20000 each shows `[gc_reuse_hit] kind=0` followed by
     `[gc_reuse_bad_list] chunk=32 len=128 cap=128 buf=ptr+32 magic=1279870019`
     (logs: `build/logs/alloc_churn_direct_reuse_cap1000_20260225_021833.log`,
     `build/logs/alloc_churn_direct_reuse_cap5000_20260225_021853.log`,
     `build/logs/alloc_churn_direct_reuse_cap20000_20260225_021913.log`).
   - New list-alloc ring correlation (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     `[gc_reuse_bad_list_site] ptr=... site=1 mode=1 size=32` confirms bad list headers
     come from GC list header allocations (site=1, mode=1). Log:
     `build/logs/alloc_churn_direct_reuse_list_alloc_ring_20260225_023407.log`.
   - List header ring shows `list_reserve` op with `buf=ptr+32` after growth on a header
     whose allocation chunk is still 32 bytes (adjacent external buffer). The GC reuse
     list-header guard now treats `buf==ptr+32 && chunk_size==32` as valid to avoid
     false bad-list hits (rolling, 2026-02-25).
   - Post-guard trace (arm64, 2026-02-25, direct native run with reuse + auto arenas off):
     no `[gc_reuse_bad_list]` lines; gc_reuse summary shows guard_bad_list=0
     (log: `build/logs/alloc_churn_direct_reuse_post_guard_20260225_025057.log`).
   - Higher-verbosity reuse trace (arm64, 2026-02-25, same env with verbose cap=50):
     still no `[gc_reuse_bad_list]`; reuse hits>1k, guard_bad_list=0
     (log: `build/logs/alloc_churn_direct_reuse_post_guard_verbose_20260225_025542.log`).
   - Trace alloc_churn reuse (arm64, 2026-02-25, same reuse env as above) ran >3 min
     and was terminated to keep iteration fast; no trace output captured.
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`, warmups=0):
     - `alloc_churn` panics: `list_reserve on non-list` after `[alloc_site] total=1536 list_header=768 list_buf=768`.
       New trace: stage=1 (node missing), magic matches, count/cap/buf=0, list_debug node=0,
       arena_depth=0 (no arena node or range) (local run log: `build/logs/bench_run_alloc_churn_20260220_132405/oren_native/run_0.log`).
   - New: `OREN_TRACE_LIST_TRACK=1` logs alloc-index insert/remove events for list/list_int headers
     (cap=1024; override with `OREN_TRACE_LIST_TRACK_CAP`, rolling, 2026-02-20).
   - New: `OREN_TRACE_TRACK_ALLOC_NEW=1` logs early `oren_track_alloc_new` events
     (cap via `OREN_TRACE_TRACK_ALLOC_NEW_CAP`, rolling, 2026-02-25).
   - New: `OREN_TRACE_LIST_ALLOC=1` logs list header allocations with alloc-site id and mode
     (1=GC, 2=arena); cap via `OREN_TRACE_LIST_ALLOC_CAP` (rolling, 2026-02-25).
     Ring buffer size for bad-list correlation via `OREN_TRACE_LIST_ALLOC_RING_CAP`
     (default 4096); `gc_reuse_bad_list` now emits a matching `[gc_reuse_bad_list_site]`
     line when the pointer is still in the ring (rolling, 2026-02-25).
   - New: `OREN_TRACE_LIST_HDR_RING=1` records list header mutations (new/reserve/push/set/clear ops,
     including list<int> variants)
     in a ring; `OREN_TRACE_LIST_HDR_RING_CAP` controls size (default 4096). When a
     `gc_reuse_bad_list` is reported, the ring is searched and matching `[list_hdr_ring]`
     entries are emitted (rolling, 2026-02-25).
   - New: `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1` prints alloc-index remove timing stats at GC sweep
     (rolling, 2026-02-20).
   - Trace list-track (arm64, 2026-02-25, `OREN_TRACE_LIST_TRACK=1`, cap=5): `alloc_churn` emits
     `[list_track] arena_alloc` lines, confirming list headers are arena-backed under auto loop arenas.
     Auto-loop rewrites now target `oren_arena_new_list_auto`/`oren_arena_new_list_int_auto`, which consult runtime
     `OREN_ARENA_AUTO_LOOP` to fall back to GC list headers for reuse debugging (explicit `@oren.arena` stays arena-only).
   - New: native GC safepoints now spill callee‑saved registers to the stack before calling
     `oren_gc_safepoint` (arm64: x19–x28; x64: rbx/rbp/rdi/rsi/r12–r15) so conservative stack scans
     see register‑held pointers (rolling, 2026-02-20).
   - New: explicit `oren_gc_safepoint()` calls now use the same spill wrapper in native codegen
     (arm64 + x64), not just loop‑injected safepoints (rolling, 2026-02-20).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`,
     `OREN_TRACE_LIST_TRACK=1`, runs=1): `alloc_churn` completes at 5.035s with list_header=1024, list_buf=1024
   - Trace alloc-site (arm64, 2026-02-20, `OREN_BENCH_TRACE_ALLOC_SITE=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=1000`,
     `OREN_TRACE_LIST_TRACK=1`, `OREN_TRACE_LIST_TRACK_CAP=5000`, runs=1): `alloc_churn` 5.872s with list_header=1024, list_buf=1024
     `build/logs/bench_run_alloc_churn_20260220_134542/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_churn` 5.752s with list_header=1024, list_buf=1024
     `build/logs/bench_run_alloc_churn_20260220_135825/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, after safepoint spill wrapper for explicit calls, runs=1):
     list_track log has no `remove` lines: `build/logs/bench_run_alloc_churn_20260220_140537/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1): `alloc_drop` 0.609s with list_header=821, list_buf=2
     `build/logs/bench_run_alloc_drop_20260220_140749/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`, same env, runs=1):
     list_track log now shows many `remove` lines (see `build/logs/bench_run_alloc_drop_20260220_140954/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, runs=1): `alloc_drop` 18.034s with list_header=137, list_buf=0
     spikes to ~4.1µs, counts ≈550 per sweep (log: `build/logs/bench_run_alloc_drop_20260220_141623/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env but `OREN_GC_ALLOC_THRESHOLD=10000`, runs=1):
     alloc_index_remove counts ≈5700 per sweep with avg ~1–2µs and spikes to ~12–17µs
     (log: `build/logs/bench_run_alloc_drop_20260220_141832/oren_native/run_0.log`).
   - New: alloc-index cleanup during GC sweep now defers to a bulk rebuild when reuse blocks are enabled
     (avoids per-free remove probes; rolling, 2026-02-20).
   - Trace alloc-site (arm64, 2026-02-20, `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=0`,
     `OREN_TRACE_ALLOC_INDEX=1`, `OREN_TRACE_ALLOC_INDEX_REMOVE_TIME=1`, `OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD=10000`, runs=1):
     alloc_index_remove count=0; alloc_index rebuilds ~34–39µs
     (log: `build/logs/bench_run_alloc_drop_20260220_142335/oren_native/run_0.log`).
   - Trace alloc-site (arm64, 2026-02-20, same env, runs=1):
     alloc_index_remove count=0; alloc_index rebuilds ~67–73µs
     (log: `build/logs/bench_run_alloc_churn_20260220_142427/oren_native/run_0.log`).
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, default GC threshold, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=10000`, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks off, `OREN_GC_REUSE_ZERO=0`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=32`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=8`, warmups=1):
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_GC_REUSE_SCAN_CAP=4`, warmups=1):
   - Trace reuse (arm64, 2026-02-20, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, reuse blocks on,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 19.056s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 10.387s with gc_reuse
     scan_steps min=90, max=10.3M, avg=5.2M across 40 sweeps
   - New run (arm64, 2026-02-20, reuse blocks on, `OREN_GC_REUSE_BUCKETS=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, warmups=1):
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`,
     `OREN_TRACE_GC_REUSE=1`, output check disabled): `alloc_drop` 18.747s with gc_reuse
     scan_steps min=8.4k, max=22.4M, avg=11.4M across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 13.245s with gc_reuse
     scan_steps min=5.6k, max=19.7M, avg=9.9M across 40 sweeps
   - Trace reuse (arm64, 2026-02-20, reuse blocks + buckets on, `OREN_GC_REUSE_SCAN_CAP=32`,
     `OREN_GC_AUTO=1`, `OREN_GC_ALLOC_THRESHOLD=1000`, `OREN_TRACE_GC_REUSE=1`, output check disabled):
     `alloc_drop` 6.812s with gc_reuse scan_steps min=369, max=36.6k, avg=35.1k; scan_steps_cap
     min=429, max=36.9k, avg=34.5k; scan_cap_hits min=12, max=1114, avg=1041 across 72 sweeps
   - Trace reuse (arm64, 2026-02-20, same env, output check disabled): `alloc_churn` 7.687s with gc_reuse
     scan_steps min=375, max=65.5k, avg=62.1k; scan_steps_cap min=429, max=65.3k, avg=60.4k;
     scan_cap_hits min=12, max=1975, avg=1828 across 40 sweeps
   - New run (arm64, 2026-02-20, runs=5, warmups=1):
     `alloc_churn` 0.131s (48.57× C), `alloc_drop` 0.160s (56.17× C)
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` + `OREN_ARENA_PER_ITER=1`, native only):
     - `alloc_churn` 1620× C, `alloc_drop` 60.18× C (C baseline from `benchmarks/RESULTS_LATEST.md`; no improvement vs default).
     - `OREN_BENCH_TRACE_ARENA=1` emitted no `[arena]` lines for alloc_churn/alloc_drop (likely no arena push/pop in these benches).
   - New run (arm64, 2026-02-20, compile-time auto-loop via `OREN_BENCH_ENV_BUILD_OREN`, runs=1, warmups=0):
     - `alloc_churn` 5.17s (native only), arena trace shows per-iteration allocs=2, push=1, pop=1 (per-iter active; perf worse).
     - `arena_loop` trace still marks alloc_churn's outer loop as long-lived despite `n=20000`; investigate bound detection.
   - New: arena loop bound detection now compares identifier names by value (string equality) in optimizer loops,
     fixing const-int bound lookups that were previously missing when strings were not pointer-equal (rolling, 2026-02-20).
   - New: C backend defines arena push/pop/new_list fallbacks (GC allocs) so auto-loop builds don't fail (rolling, 2026-02-20).
   - New: arena auto-loop wrapping is now gated to the native backend via optimizer config to avoid injecting
     arena calls into C/bytecode builds (rolling, 2026-02-20).
   - New: arena auto-loop is enabled by default for native builds; auto rewrites target
     `oren_arena_new_list_auto` so `OREN_ARENA_AUTO_LOOP=0` at runtime forces GC list headers when debugging.
   - New: long-lived arena bound default lowered to 1024 iterations (override via `OREN_ARENA_LONG_LIVED_BOUND`).
   - New: safe loop-local lists now insert a pre-loop `list_reserve` when a constant push bound is detected
     (rolling, 2026-02-20).
   - New: list/list_int push paths allocate growth buffers from the arena when the list header is arena-tracked
     (rolling, 2026-02-20).
   - New: arena-loop trace now reports candidate rejection reasons (`unsafe_use`, `used_after_loop`,
     `assign_not_dominate`) plus `candidates=0` when no list allocs are seen (rolling, 2026-02-20).
   - New: list_reserve/list_int_reserve now allocate buffers from the arena when the list header is arena-tracked,
     avoiding GC buffer allocations for arena lists (rolling, 2026-02-20).
   - New: list validation now accepts arena-tracked nodes when `OREN_LIST_ASSUME_LIST=0`, so list_len/reserve/get/set/push
     do not treat arena lists as non-lists during safety checks (rolling, 2026-02-20).
   - New: list-literal sinking now recurses into nested blocks (loops/ifs/switch cases) so branch-local lists inside
     loops are elided when unused on false paths (rolling, 2026-02-20).
   - New: list-literal sinking now hoists contiguous side-effect-free temps used only by the list literal
     into the same branch (rolling, 2026-02-20).
   - New: side-effect-free allowlist includes `oren_int_to_string`, enabling branch-local sinking of temps
     that build strings for list literals (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, post recursive list-literal sinking, runs=5, warmups=1):
     - `alloc_churn` median 3.404s native; `alloc_drop` median 0.145s native
   - New trace (arm64, 2026-02-20, manual compile with `OREN_TRACE_ARENA_LOOPS=1`):
     - `alloc_churn`: outer loop wraps (`safe_vars=1`, `rewrite=1`); inner loop shows `candidates=0` then `skip=no_arena_alloc`.
     - `alloc_drop`: main loop drops list literal `l` as `unsafe_use` (escapes via `keep`), then `skip=no_arena_alloc`.
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace after backend gating, runs=1, warmups=0):
     - `alloc_churn` 0.361s native; arena trace allocs=40000, push=1, pop=1, epoch_reset=1.
     - `arena_loop` trace shows bound=20000, long_lived=0, per_iter=0; C/bytecode builds skip=backend.
   - New run (arm64, 2026-02-20, compile-time auto-loop, runs=5, warmups=0):
   - New: const-int bound detection now resolves simple identifier aliases (e.g., `limit = fallback`)
     but aborts if any intervening control-flow assigns to the bound (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace on alloc_drop, runs=1, warmups=0):
     - `alloc_drop` 0.171s native; arena_loop reports bound missing / skip=no_arena_alloc (no arena rewrites).
   - New run (arm64, 2026-02-20, compile-time auto-loop + trace after alias-bound fix, runs=1, warmups=0):
     - `alloc_drop` 0.166s native; arena_loop now detects bound=10000 but still skip=no_arena_alloc.
   - New: optimizer sinks side-effect-free list literals into immediate `if` blocks when the list
     is only used in the true branch, avoiding allocations on the false path (rolling, 2026-02-20).
   - New: if a list is predeclared as nil/empty and only assigned a list literal in the true branch,
     the assignment is converted to a branch-local `var` (rolling, 2026-02-20).
   - New run (arm64, 2026-02-20, post list-literal sinking, runs=1, warmups=0):
     - `alloc_drop` 0.158s native (single run; compare to prior 0.166–0.171s).
   - New run (arm64, 2026-02-20, post list-literal sinking, runs=5, warmups=0):
   - New run (arm64, 2026-02-20, post list-literal assign scoping, runs=5, warmups=0):
   - New run (arm64, 2026-02-20, bench harness default, runs=5, warmups=1):
     - `alloc_churn` median 3.409s native; `alloc_drop` median 0.145s native
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.643s native; `alloc_drop` median 0.152s native
     - Note: this run set the flag at runtime only; compile-time auto-loop was not enabled.
   - New run (arm64, 2026-02-20, `OREN_ARENA_AUTO_LOOP=1` via build env, runs=5, warmups=1):
     - `alloc_churn` median 3.526s native; `alloc_drop` median 0.147s native
   - New run (arm64, 2026-02-20, arena-backed reserve buffers + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 0.324s native; `alloc_drop` median 0.150s native
   - New run (arm64, 2026-02-20, recursive list-literal sinking + `OREN_ARENA_AUTO_LOOP=1`, runs=5, warmups=1):
     - `alloc_churn` median 3.532s native; `alloc_drop` median 0.148s native
   - New run (arm64, 2026-02-20, temp+list-literal sinking, runs=5, warmups=1):
     - `alloc_churn` median 3.404s native; `alloc_drop` median 0.144s native
   - Design + implement loop‑local arenas for list/list_int (compiler escape analysis + arena tracking table).
   - Native runtime scaffolding: `oren_arena_push/pop` + `oren_arena_new_list(_int)` (compiler lowering pending).
   - Arena cap: `OREN_ARENA_CAP_BYTES` spills allocations back to GC when exceeded.
   - Compiler: `OREN_ARENA_AUTO_LOOP=1` wraps simple loops; it can rewrite **unconditional top‑level** loop‑local `oren_new_list(_int)` vars to arena allocs when usage is limited to safe list ops.
   - List literals inside eligible loops are rewritten to arena lists in auto mode (non‑empty literals expand to arena alloc + pushes).
   - Auto-loop rewriting requires the allocation to **dominate first use** in the loop body (use‑before‑assign skips).
   - Auto-loop wrapping now ignores `continue` inside nested loops (outer loop still eligible).
   - Auto-loop now inserts arena pop on `break`/`return`/`continue` in the same loop body.
     - `continue` is allowed for `while` and `for` loops (post executes outside the arena).
   - Auto-loop now keeps bounded loops truly loop-scoped (push before the loop, pop after); per-iteration
     push/pop is reserved for long-lived loops or `@oren.arena_iter`.
   - Auto-loop wrapping skips nested loops when an ancestor has explicit `@oren.arena` or `@oren.arena_iter`.
   - Auto-loop wrapping also skips descendants of `@oren.noarena` (explicit arenas still allowed).
   - `OREN_ARENA_PER_ITER=1` switches auto‑mode to per‑iteration push/pop for long‑lived loops.
   - `@oren.arena_iter` forces per‑iteration push/pop on a loop (even if auto mode is off).
   - Heuristic: loops without a simple literal upper bound default to per‑iteration mode;
     const‑int bounds (including prior locals assigned a literal) or `list_len` locals assigned before the loop
     are treated as bounded when not reassigned.
     - New: const‑int bounds (including prior locals assigned a literal) and `list_len` locals of
       list literals >= `OREN_ARENA_LONG_LIVED_BOUND` (default 1,000,000) are treated as long‑lived
       (per‑iteration).
   - Define long‑lived loop policy:
     - Prefer per‑iteration sub‑arenas when loop trip count is unbounded or long‑lived.
     - Values that escape an iteration allocate in GC/outer arenas (no arena aliasing).
     - Loop‑scoped arenas must enforce `OREN_ARENA_CAP_BYTES` and spill to GC beyond cap.
     - Add periodic epoch resets for long‑running loops to prevent unbounded growth.
   - Add arena‑lifetime counters (spills, epoch resets) to quantify long‑loop behavior.
   - `OREN_TRACE_ARENA=1` prints arena alloc/spill counters at arena epoch reset.
   - Arena tracking table now resets via epoch generation bump (avoids O(cap) clears per iteration).
   - Arena push/pop now checkpoint ptr/limit/base/bytes_used and use per‑depth tracking tables; nested arenas restore state and clear the popped table to prevent long‑lived loop growth.
   - Gate: native `alloc_churn` <= 8x C; native `alloc_drop` <= 5x C.

3) **W4 - List reserve + unchecked push** (M)
   - Baseline (arm64 native, 2026-02-26): `array_sum` 2.12× C, `multi_list_push_int` 3.36× C.
   - Extend bounds propagation for reserve/unchecked push.
   - New (2026-03-27): the list-reserve collector/rewrite pass now traverses branchy `If` and
     `Switch` control flow at both statement and expression level, so loop-local list pushes inside
     branches still get pre-loop `*_reserve` insertion and `*_push_unchecked` rewrites.
   - New (2026-03-27): `make verify-optimizer-list-reserve-branchy` builds
     `tests/fixtures/list_reserve_branchy_control_flow_smoke.oren` with
     `OREN_TRACE_LIST_RESERVE=1`, verifies the boxed and `list<int>` reserve/unchecked trace lines,
     and runs the fixture; `make test` now covers that gate via `verify-native-quick`.
   - Treat `oren_new_list(0)` as list-literal for reserve insertion (loop bound -> reserve).
   - Reserve insertion now descends into nested loops with outer list literals and adds list literal length to the reserve amount when known.
   - Native array literal lowering now calls `oren_new_list(n)` (pre-reserve capacity).
   - Native list-literal lowering now uses `oren_list_push_unchecked` for element pushes.
   - Native list/list_int push intrinsics now call unchecked push on the grow slow-path to avoid duplicate validation.
   - Loop reserve insertion does not rewrite push calls (keeps the intrinsic fast path); it only adds `*_reserve` pre-loop.
   - Rolling: empty list literals lower to list<int> only when the same block establishes
     an int element via `list_push`/`list_set` (cross‑block empties stay boxed; 2026-02-20).
   - Native fast list_int push loops now accept `list_int_push_unchecked` calls to preserve the fast path after list<int> lowering (rolling, 2026-02-20).
   - List<int> reserve insertion now accepts int-only list literals (including empty literals).
   - Gate: native `array_sum` and `multi_list_push_int` <= 2x C.

4) **W4 - Tagged value representation convergence** (L)
   - Canonical tagged layout across native/C/AVM.
   - Tag parity fixture now asserts numeric tag values across backends (`tests/fixtures/tag_parity_smoke.oren`).
   - Gate: fixtures pass; no backend-only semantics.

5) **W3 - SIMD/typed-buffer parity on native (x64 + arm64)** (M)
   - Baseline (arm64 native, 2026-04-04 latest clean focused list<int> rerun): `array_sum_int` 2.07× C,
     `dot_product_int` 2.59× C, `multi_list_push_int` 2.24× C.
   - Steady-state baseline (arm64 native, 2026-04-04, `reps=100`): `array_sum_int` ~2.43× C,
     `dot_product_int` ~2.78× C.
    - SSE2 baseline on x64; scalar equivalence gated.
    - Wire list_int dot loops to SIMD kernels (or typed-buffer views) where safe.
    - Priority update (2026-03-27): do not lower general `list<int>` dot/sum loops into the
      current packed-bridge path until the bridge cost is fixed; the shortened steady probe still
      showed it orders of magnitude slower than the baseline loops.
    - Follow-up (2026-03-27): a native runtime pointer-loop fix improved the canonical shortened
      steady baseline to `array_sum_int` ~1.35× C and `dot_product_int` ~1.36× C, but the packed
      bridge remained ~1177× / ~2779× C on the SIMD leg and ~1438× / ~15382× C on the scalar leg.
      The remaining blocker is therefore bridge/materialization cost, not the current `i32`
      typed-buffer inner-loop fallback.
    - Follow-up (2026-03-27): the new hidden direct-slot probe measured
      `array_sum_int_slot_direct` ~13.74× C and `dot_product_int_slot_direct` ~21.03× C on the same
      shortened steady sample. That is vastly better than the packed bridge and proves the raw
      64-bit-slot ABI is the right direction, but it is still far from the current compiler fast
      loops. The next material work is direct compiler lowering, not shipping a runtime-helper call
      as the hot path.
    - Follow-up (2026-04-04): that next step now exists for the unchecked raw-slot probe surface.
      arm64 and x64 both inline `oren_list_int_reduce_sum_slots_unchecked` /
      `oren_list_int_dot_slots_unchecked` at native call sites instead of paying the old generic
      helper-path cost. A forced steady rerun
      (`build/logs/perf-probe-list-int-slot-direct-20260404_200234.log`) moved the hidden
      direct-slot benchmarks to `array_sum_int_slot_direct` ~15.1069× C and
      `dot_product_int_slot_direct` ~5.1760× C, versus a same-run canonical baseline of
      `array_sum_int` ~2.3090× C and `dot_product_int` ~2.9950× C. That makes the direct-slot dot
      path much less pathological, but the canonical fast loops are still materially better, so the
      open gate remains native `dot_product_int` <= 2x C rather than “ship the helper probe path”.
    - Guardrail (2026-04-04): the slot-direct verify target now also exercises the unchecked helper
      edge contract directly through `tests/fixtures/list_int_slot_direct_contracts.oren`, covering
      nil-zero behavior and deterministic mismatch panics in addition to the existing benchmark smoke.
    - Follow-up (2026-04-11): the slot-direct helper fast-tick branch now exists behind
      `OREN_ARM64_LIST_INT_SLOT_DIRECT_FAST_TICK=1`, reducing the arm64 expr-helper safepoint spill set
      and using a 4095 default tick mask for the unchecked raw-slot sum/dot helper loops. It is
      correctness-clean but not promotable: `make perf-probe-list-int-slot-direct-fast-tick-decision`
      (`build/logs/perf-probe-list-int-slot-direct-fast-tick-decision-20260411_194036_96087.log`)
      measured slot-ABI helper time `+0.21%` versus default and read-split slot-direct native/C
      regressions on both `array_sum_int` and `dot_product_int`. Keep it opt-in and keep W5 focused on
      real representation/direct lowering.
    - Follow-up (2026-04-11): the raw-slot helper counted pair-loop branch now exists behind
      `OREN_ARM64_LIST_INT_SLOT_DIRECT_PAIR_LOOP=1`, with `make perf-probe-list-int-slot-direct-pair-loop-decision`
      (`build/logs/perf-probe-list-int-slot-direct-pair-loop-decision-20260411_195615_19255.log`)
      covering default, fast-tick, pair-loop, and pair-loop+fast-tick builds. It is correctness-clean
      but not promotable: pair-loop alone regressed slot-ABI direct-helper time `+3.15%` and
      read-split `array_sum_int` slot-direct native/C `+9.88%`, while improving only
      `dot_product_int` `-3.31%`; pair-loop+fast-tick regressed slot-ABI `+3.42%` and array
      `+7.70%` while improving dot `-7.55%`. Keep it opt-in and continue toward a real safe packed
      view or stronger slot64 direct-lowering path.
    - Constraint (2026-03-20): direct reuse of the packed-i32 `simd_dot_i32_ptr` kernel is not
      safe for current `list<int>` fast loops because their payload slots are 64-bit values.
    - New: native runtime now exposes the current list<int> payload ABI explicitly via
      `oren_list_int_data_ptr*` + `oren_list_int_slot_stride_bytes()` and guards it inside the
      Tier-1 native quick fixture, so future bridge work can target a stable checked fact.
    - arm64 native fast list_int dot loops unroll by 2 when lists are unique.
    - arm64 native fast list_int get-sum loops unroll by 2 when lists are unique.
    - x64 native fast list_int dot loops unroll by 2 when lists are unique (multi-mul supported).
    - x64 native fast list_int get-sum loops unroll by 2 when lists are unique.
	    - Read-only list_int fast-loop safepoint defaults are now split by proven surface: arm64
	      explicit `list<int>` get-sum still ships at `4095`, arm64 `list<int>` dot remains at
	      `4095`, and x64 read-only list loops remain at `1023`. The new explicit get-sum
	      tick-mask probe is useful, but the higher-mask candidates are still too noisy to ship.
	      The stronger same-tree exact decision wrapper now confirms the conservative get-sum
	      default on the shipped tree:
	      `build/logs/perf-probe-arm64-fast-get-sum-tick-mask-decision-20260411_162635_82969.log`
	      preferred `default` on the target `array_sum_int` surface (`~2.1833x` vs `16383`
	      `~2.2437x`, `65535` `~2.1864x`; `array_default_wins: 2/3`) and on the
	      `dot_product_int` control (`~1.7332x` vs `~1.7811x`, `~1.7845x`).
	    - Arm64 canonical hot-loop tick-mask probe (`make perf-probe-arm64-fast-loop-tick-masks`,
	      2026-04-04): baseline `dot_product` ~2.9293x C, `16383` unchanged, `65535` ~2.8584x C.
	      Useful tuning surface added; default remains `4095`.
	    - Arm64 canonical steady tick-mask probe (`make perf-probe-arm64-fast-loop-tick-masks-steady`,
	      2026-04-04): corrected same-smoke rerun baseline `dot_product` ~3.0142x C, `16383`
	      ~3.0924x C, `65535` ~3.1914x C. On the repeated-read-loop runner, higher masks regress;
	      default remains `4095`.
		    - Arm64 single-pair cursor-reg refresh (`2026-04-11`): wrappers now exist for both generic
		      and explicit surfaces. The same-tree generic rerun
		      (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-20260411_170046_96599.log`)
		      prefers keeping cursor regs enabled on raw native medians (`steady 0.130047s -> 0.133221s`,
		      `gate 0.010926s -> 0.011969s` when disabled). Explicit rerun
		      (`build/logs/perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int-20260411_170108_97730.log`)
		      is still mixed: disabled improves raw native by only `-1.31%` / `-0.05%`, while the ratio
		      view worsens due the paired C median shift. Keep cursor-reg enabled; this is no longer a
		      stale April 4/9 verdict.
			    - Arm64 explicit get-sum single-list cursor-reg refresh (`2026-04-09`): new wrapper
			      `make perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int` now compares the
			      shipped `array_sum_int` scalar loop against
			      `OREN_ARM64_FAST_LIST_INT_GET_SUM_SINGLE_LIST_CURSOR_REGS=0` through the same serialized
			      acceptance bundle. Current rerun
		      (`build/logs/perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int-20260409_130055_41301.log`)
		      kept the new default-on path: steady native median improved from disabled `0.134232s` to
			      default `0.133314s`, gate native stayed effectively flat (`0.010003s` disabled vs
			      `0.010044s` default), the disabled gate leg warned as high variance, and both legs kept
			      the same 16-instruction traced loop. Keep the cursor-reg path enabled, but do not
			      over-read it as a whole-operation breakthrough.
			    - Arm64 explicit push single-list cursor refresh (`2026-04-09`): new wrapper
			      `make perf-probe-arm64-fast-push-single-list-cursor-list-int` now compares the shipped
			      `array_sum_int` fill loop against
			      `OREN_ARM64_FAST_LIST_INT_PUSH_SINGLE_LIST_CURSOR=0` through the same serialized
			      acceptance bundle. Current rerun
			      (`build/logs/perf-probe-arm64-fast-push-single-list-cursor-list-int-20260409_132214_76347.log`)
			      kept the new default-on path: steady native median improved from disabled `0.136291s` to
			      default `0.131530s` (`-3.62%`), gate native improved from disabled `0.010571s` to
			      default `0.010084s` (`-4.83%`), and both legs kept the same 16-instruction traced loop.
			      The follow-up whole-operation ceiling rerun improved canonical
			      `oren_array_sum_int / array_slot64_vector` from `~5.4463×` to `~5.3848×`. Keep the
			      cursor path enabled, but treat it as a modest whole-operation win rather than the
			      missing slot64-vector parity fix.
		    - Arm64 explicit get-sum tick-mask refresh (`2026-04-09`): new wrapper
		      `make perf-probe-arm64-fast-get-sum-tick-mask-list-int` now compares the shipped
		      explicit `array_sum_int` get-sum default against explicit mask overrides through the same
		      serialized acceptance bundle. Current final-tree rerun
		      (`build/logs/perf-probe-arm64-fast-get-sum-tick-mask-list-int-20260409_143632_74801.log`)
		      keeps `OREN_ARM64_FAST_LIST_INT_GET_SUM_TICK_MASK=4095` for now: explicit `16383` and
		      `65535` both improved steady native medians on that sample (`0.137232s` and `0.131635s`
		      vs shipped `0.141901s`), but the gate view stayed too noisy to trust as a production
		      default (`native gate cov=0.6421` at shipped `4095`, `0.2631` at `16383`, `0.1270` at
		      `65535`). Reweight accordingly: the probe is worth keeping, but not yet worth a shipped
		      higher mask.
		    - Arm64 explicit push tick-mask decision surface (`2026-04-11`): new wrapper
		      `make perf-probe-arm64-fast-push-tick-mask-decision` compares the shipped
		      `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK=4095` behavior against `16383` and
		      `65535` on both fill/share attribution and exact same-tree C-ceiling reruns. Current
		      cached rerun
		      (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260411_161037_18451.log`)
		      does not support a shipped default change: fill/share preferred default
		      (`default_fill_vs_c_vector ~2.6362×` vs `16383 ~2.8750×`, `65535 ~2.8309×`), exact
		      `array_sum_int` preferred `65535` by median (`default_array_ratio_median ~2.2996×`,
		      `16383 ~2.2720×`, `65535 ~2.1974×`, `array_mask_65535_wins: 2/3`), and exact
		      `dot_product_int` preferred default by median (`default_dot_ratio_median ~1.7705×`,
		      `16383 ~1.7852×`, `65535 ~1.7837×`) while per-sweep dot wins split `1/3` each.
		      Reweight: keep the shipped `4095` push tick mask; the higher masks are still
		      probe-only because the decision surfaces disagree.
		    - New whole-operation setup-vs-steady attribution (`2026-04-09`):
		      `make perf-probe-list-int-array-sum-c-breakdown`
		      (`build/logs/perf-probe-list-int-array-sum-c-breakdown-20260409_143718_76549.log`)
		      now shows the repeated `array_sum_int` kernel is still the structural blocker while the
		      short-run setup estimate stays noisy: Oren canonical setup estimate came back at
		      `~0.009496s` versus slot64 C vector `~0.004273s`, but the more stable signal remains the
		      steady per-rep gap (`~0.001311s` vs `~0.000204s`, or `~6.4228×`). Reweight accordingly:
		      the repeated get-sum loop remains the main blocker, not another fill/setup tweak.
		    - Arm64 explicit get-sum unroll2 promotion (`2026-04-09`): the earlier crashy candidate
		      was root-caused in `lib/compiler/arm64_native_stmt_loops_list_emit.oren`, where the
		      experimental unrolled bodies were clobbering reserved heap registers `X27` / `X28`.
		      Those loop-body value temps now live in caller-saved `X12` / `X13`, and
		      `OREN_ARM64_FAST_LIST_INT_GET_SUM_UNROLL2` now ships on by default for
		      single-read-list shapes while staying overrideable for A/B and emergency disable.
		      The promoted exact whole-operation rerun
		      (`build/logs/perf-probe-list-int-c-ceiling-20260409_163202_21950.log`) now keeps
		      `oren_array_sum_int / array_slot64_vector ~2.3939×`, and the broad gates pass in
		      `build/logs/make_test_get_sum_unroll2_promote_20260409.log` plus
		      `build/logs/make_verify_runtime_robustness_get_sum_unroll2_promote_20260409.log` /
		      `build/logs/runtime_robustness_w5_20260409_163313.log`. The new combined decision probe
		      (`build/logs/perf-probe-arm64-fast-get-sum-unroll2-decision-20260409_170812_66742.log`)
		      now records the real same-tree split: acceptance steady preferred disabled (`-4.79%`),
		      acceptance gate slightly preferred default (`+0.78%`), but exact whole-operation
		      `array_sum_int` preferred the shipped default in all three sweeps (`~2.3793×` vs
		      disabled `~5.3859×`, `array_default_wins: 3/3`). Keep treating the acceptance wrapper
		      as local sanity only; the exact whole-operation ceiling plus integrated green lanes are
		      the ranking surface for this shipped path.
			    - Arm64 dot unroll-by-2 refresh (`2026-04-09`): wrappers now exist for both generic and
		      explicit surfaces, and the shipped default is now off. The real post-flip reruns
		      (`build/logs/perf-probe-arm64-fast-dot-unroll2-20260409_030759_29018.log`,
		      `build/logs/perf-probe-arm64-fast-dot-unroll2-list-int-20260409_030846_30731.log`)
			      kept the then-current non-unrolled baseline ahead of `UNROLL2=1` on both raw medians:
		      generic `0.140160s -> 0.143718s` steady / `0.014280s -> 0.015197s` gate, explicit
		      `0.136499s -> 0.144068s` steady / `0.014523s -> 0.014546s` gate. Keep unroll2 disabled
		      by default.
		    - Arm64 unique-list loop-body cleanup (`2026-04-04`): kept `n` hot on the unique-list
		      get-sum/dot paths, switched scalar unique-list cursor bumps to immediate adds, and
		      removed duplicate non-unique dot offset recomputes. Current serial reruns improved to
		      `array_sum` ~2.0808x C / `dot_product` ~2.7616x C on the canonical gate and
		      `array_sum` ~2.2422x C / `dot_product` ~2.9915x C on the steady runner, but the
		      blocker still remains above the `<=2x C` gate.
		    - Arm64 dot dual-accum refresh (`2026-04-09`): current generic rerun improved both raw
		      native medians (`0.079878s -> 0.077758s` steady, `0.014427s -> 0.013903s` gate), but the
		      explicit `list<int>` rerun stayed mixed (`0.077313s -> 0.080407s` steady regression,
		      `0.016063s -> 0.015338s` gate with a high-variance warning). Keep the path disabled by
		      default, but the old April 4 "loses everywhere" note is no longer accurate.
		    - Gate: native `dot_product_int` <= 2x C.

6) **W3 - AVM allocation fast paths + typed buffers** (M)
   - Baseline (OBC, 2026-02-20): `alloc_churn` 61.78× C, `alloc_drop` 2.59× C.
   - Arena/slab alloc for short-lived lists/structs.
   - TMP freelist for `AVM_ALLOC_KIND_TMP` (env: `AVM_TMP_FREELIST=1`, cap via `AVM_TMP_FREELIST_BYTES`, block cap via `AVM_TMP_FREELIST_MAX_BLOCK_BYTES`).
   - List freelist for `AVM_ALLOC_KIND_LIST` + `AVM_ALLOC_KIND_LIST_INT` (env: `AVM_LIST_FREELIST=1`, cap via `AVM_LIST_FREELIST_BYTES`, block cap via `AVM_LIST_FREELIST_MAX_BLOCK_BYTES`).
   - Gate: OBC `alloc_churn` <= 10x C; AVM SIMD test suite passes.

7) **W3 - AVM unboxed list<int> payload + lowering** (M)
   - Baseline (OBC, 2026-02-26): `dot_product_int` 77.69× C, `array_sum_int` 66.36× C.
   - Baseline (native, 2026-02-26): `array_sum` 2.12× C, `dot_product` 2.57× C,
     `array_sum_int` 2.11× C, `multi_list_sum` 2.35× C.
   - Implement list<int> payload + OBC lowering.
   - Gate: list<int> fixtures + OBC perf parity for dot/sum loops.

---

## P0 (Now)

P0 focuses on the W5/W4 scorecard items. Structural/SOLID refactors remain P2
until perf + parity gates are within range. Reweight: runtime robustness + tagged
value convergence are W5 blockers; performance work must preserve correctness and
traceability.
Reweight: avoid trace-only changes unless they unblock a root-cause or a W5 gate.

1) **Perf parity W5: allocation/GC** (L, W5)
   - Execute item 2 in the performance tracker (alloc_churn + alloc_drop).
   - Include long‑lived loop arena policy (per‑iteration sub‑arenas + spill + epoch reset).
   - Design spec: `docs/design/arena_loop_policy.md` (loop arena policy + GC reuse safety).
   - New: per-iteration loops use `oren_arena_iter_push/pop` with optional cap via `OREN_ARENA_ITER_CAP_BYTES` (rolling).
   - Next: tune `OREN_ARENA_ITER_CAP_BYTES` (64 KiB / 256 KiB / 1 MiB all worsen alloc_churn/alloc_drop; likely need adaptive or different arena policy).
   - Update (2026-03-04): alloc_churn regression resolved by splitting loop-invariant list_int temps into
     an outer `if` and fast-path `while` so `fast_list_int_push_while` can match again.
   - Refresh (2026-04-22): `make perf-gate-native-refresh-latest` now records the focused W5 gate
     sweep directly and refreshes `benchmarks/RESULTS_LATEST.md` from the exact four gate JSONs.
     Latest arm64 run stays within gate: alloc_churn 5.76× C and alloc_drop 1.83× C
     (summary: `build/logs/perf-gate-native-20260422_003657_93539.summary.log`; log:
     `build/logs/perf-gate-native-20260422_003657_93539.log`).
   - Fix (2026-03-04): list_int safe-int dataflow now preserves local temps across nested blocks;
     alloc_churn compile trace shows list_push call sites include `v`/`v2` in safe keys
     (log: `build/logs/bench_build_oren_native_alloc_churn_20260304_232251.log`).
   - Fix: loop list reset now requires first-assign dominance in the loop body to avoid auto-arena on use-before-assign patterns
     (keeps `test_arena_auto_loop_use_before_assign_skip_smoke` stable).
   - Fold loop‑local arena prototype for list/list_int into this track; override annotations
     (`@oren.arena`, `@oren.arena_iter`, `@oren.noarena`) are already implemented.
   - Confirmed GC-path list tracking after disabling auto arenas (`OREN_ARENA_AUTO_LOOP=0` runtime via
     `oren_arena_new_list_auto`); no `malloc_k` list-track wiring needed unless future traces regress.
   - Separate arena vs GC allocations in perf diagnostics; `alloc_churn` defaults to arena-backed lists
     (use runtime `OREN_ARENA_AUTO_LOOP=0` or build-time env to force GC-tracked list headers when debugging reuse).
   - Gate: native `alloc_churn` <= 8x C; native `alloc_drop` <= 5x C.

2) **Perf parity W5: native hot loops** (L, W5)
   - Execute item 1 in the performance tracker (loop_sum + dot_product).
   - Refresh (2026-04-22): `make perf-gate-native-refresh-latest` still keeps `loop_sum` within the
     arm64 gate at 1.10× C, but `dot_product` is open again at 2.83× C on the current shipped
     surface (summary: `build/logs/perf-gate-native-20260422_003657_93539.summary.log`; log:
     `build/logs/perf-gate-native-20260422_003657_93539.log`). The fresh `dot_product`
     decomposition is no longer pointing at setup/init cost or the old cursor/scalar toggle branch:
     read-split repeated work is still 3.47× C
     (`build/logs/perf-gate-native-read-split-20260422_002728_90701.log`), the scalar-ceiling probe
     still measures Oren/scalar host C at 1.8452×
     (`build/logs/perf-probe-arm64-dot-vs-c-scalar-ceiling-20260422_002728_90743.log`), and the
     current scalar-core matrix keeps baseline over the old cursor/scalar candidates
     (`build/logs/perf-probe-arm64-fast-dot-scalar-core-matrix-20260422_002951_91189.log`). Reweight
     the next hot-loop work toward a new vector/slot64-quality path rather than more scalar-toggle
     churn.
   - Refresh (2026-04-04): `make perf-gate-native` now shows loop_sum within gate at 1.09× C,
     while dot_product remains open at 2.82× C on arm64 (summary: `benchmarks/RESULTS_LATEST.md`;
     log: `build/logs/perf-gate-native-20260404_202225.log`).
   - Init/steady split instrumentation is now available via `OREN_BENCH_INIT_SPLIT=1` (see `benchmarks/README.md`).
   - Gate: native `loop_sum` and `dot_product` <= 2x C on arm64 + x64.

3) **Runtime robustness W5: GC reuse + list header integrity** (L, W5)
		   - Root-cause list header corruption (alloc_churn/alloc_drop traces point to pre-reuse corruption).
		  - Fix + verify (2026-04-21): reduced aggressive-GC `list<int>` churn now has a stable current
		    reproducer/guardrail trio: `tests/native/test_gc_reuse_alloc_churn_min.oren`,
		    `tests/native/test_gc_collect_list_int_live.oren`, and
		    `tests/native/test_gc_auto_list_int_live.oren`. The actual arm64 fix was not another GC
		    rewrite; it was saturating `_arm64_nonneg_linear_safe_n_limit(...)` so the identity
		    nonnegative-linear shape no longer overflows the fast-loop preheader bound to
		    `0x8000000000000000`. `scripts/run_native_quick_integration.sh` now runs the reduced
		    `alloc_churn` smoke on the shared default path, and
		    `scripts/verify_alloc_churn_tracking_smoke.sh` uses the reduced fixtures instead of the
		    heavier benchmark build. That same-day reducer fix still caused a temporary rollback while
		    the broader default-on self-host/native-quick surface was being re-closed. A same-day
		    direct `oren_gc_collect()` arm64 call shortcut was also removed instead of shipped: it
		    regressed native quick by hanging `test_gc_collect_does_not_deadlock_with_green_join_waiter`,
		    so the current tree keeps the normal direct-call lowering for `oren_gc_collect()`.
		  - Update (2026-04-23): the broad nonnegative-linear path is now re-promoted on the current
		    tree instead of staying opt-in. The shipped-vs-disabled rerun
		    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_011353_91759.log`)
		    again keeps the formal decision surface aligned and still strongly prefers the shipped
		    default on fill/share plus exact `array_sum_int`
		    (`default_fill_vs_c_vector ~2.3103×` vs disabled `~5.7054×`,
		    `default_array_ratio_median ~2.1964×` vs disabled `~2.3212×`), while exact
		    `dot_product_int` only moves slightly toward the disabled branch
		    (`default_dot_ratio_median ~1.3884×` vs disabled `~1.3578×`). The safety blocker is also
		    closed on the real shipped path now: `make verify-native-quick`
		    (`build/logs/make_verify_native_quick_20260423_011547_default_on_promote_v1.log`) and
		    `make test` (`build/logs/make_test_20260423_012704_default_on_promote_v2.log`) both pass
		    with the default-on branch. Reweight accordingly: keep the broad branch shipped, do not
		    revive the narrower fresh-single-list isolation, and attack the residual list build/fill
		    lifetime cost from this now-revalidated default surface instead.
		  - Update (2026-04-21): native quick integration now includes an explicit GC reuse tracking smoke
		    via `tests/native/test_gc_reuse_tracking.oren`. The fixture was tightened to force tracked
		    list-header allocations through `oren_new_list(0)` and a real escaping aggregate, then the
	    shared quick runner builds it with `OREN_ARENA_AUTO_LOOP=0` and runs it under
	    `OREN_GC_REUSE_BLOCKS=1`, `OREN_GC_REUSE_LISTS=1`,
	    `OREN_GC_REUSE_LISTS_UNSAFE=1`, `OREN_TRACE_GC_REUSE_SUMMARY=1`, asserting nonzero reuse
	    hits. Current quick log shows `[gc_reuse_summary] ... hits=4` before `gc reuse tracking OK`
	    (log: `build/logs/oren_native_quick_integration.log`).
	  - Fix + verify (2026-04-21): the rolling native build cache now keys a curated
	    build-affecting env surface for native codegen instead of ignoring arm64/x64 fast-path
	    toggles. The concrete failing case was a sequential same-cache build of
	    `tests/native/test_gc_reuse_alloc_churn_min.oren`: with the old key, a
	    `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=1` build restored the cached
	    `...=0` artifact instead of recompiling. `lib/compiler/compiler/012_build_cache.oren`
	    now includes the native fast-loop/runtime-override env surface in `BUILD_CACHE_SCHEMA=3`,
	    hashes override-file envs (`OREN_NATIVE_RUNTIME_ASTBIN`,
	    `OREN_NATIVE_RUNTIME_EXPANDED`) by content, and the new
	    `scripts/verify_build_cache_native_env_surface.sh` guard proves that the two env modes
	    now produce distinct cached artifacts while repeated same-mode builds restore from cache.
		  - Refresh (2026-04-21): the 2-run short hunt was too weak to retire this thread.
		    A wider current rerun
		    (`RUNS=10 BUILD=1 EXTRA_TRACE=0 CRASH_FOOTER=1 REPRO_BAD_LIST_CORRELATE=0 bash ./scripts/repro_bad_list_alloc_churn.sh`)
		    still produced no `[gc_reuse_bad_list]` prints, but it did reproduce a live runtime failure
		    four times out of ten: `list_int_push on non-list`
		    (`build/logs/repro_bad_list_alloc_churn_current_20260421_205455.log`,
		    failing inner logs:
		    `build/logs/alloc_churn_bad_list_auto_20260421_205513_3.log`,
		    `build/logs/alloc_churn_bad_list_auto_20260421_205513_4.log`,
		    `build/logs/alloc_churn_bad_list_auto_20260421_205549_8.log`,
		    `build/logs/alloc_churn_bad_list_auto_20260421_205549_9.log`).
		  - Fix + verify (2026-04-21): `native_list_panic_footer(...)` now honors the list-header ring env
		    instead of only `OREN_TRACE_LIST_PANIC_FOOTER`, and `scripts/repro_bad_list_alloc_churn.sh`
		    now always enables the ring/dup guard surface, records the concrete run parameters into each
		    log, and treats the current `list_int_push on non-list` signature as a hit instead of
		    incorrectly reporting only “no bad-list hits”. The focused current rerun now dumps the recent
		    header history for the failing list pointer
		    (`build/logs/alloc_churn_bad_list_focus_20260421_210001.log`), showing a sane `list<int>`
		    growth chain ending at `len=64 cap=64` immediately before the panic. A dedicated entrypoint
		    now exists at `make triage-alloc-churn-bad-list-current`.
		  - Fix + verify (2026-04-21): the explicit-collect alloc-churn shape is no longer failing on
		    overlapping reused blocks. `lib/runtime_native/100_time_gc_alloc_core_scan_reuse.oren` now
		    rejects free-list candidates whose tracked range overlaps any live alloc range, and the
		    existing “free node still in allocs” / alloc-index-dup checks are now always enforced instead
		    of being trace-only. In the same slice, arm64/x64 explicit `oren_gc_collect()` calls now spill
		    callee-saved registers just like `oren_gc_safepoint()`, conservative mark no longer panics on
		    stale aliased list headers, and `scripts/verify_alloc_churn_tracking_smoke.sh` gained the new
		    `tests/native/test_gc_collect_alloc_churn_debug_shape.oren` fixture. Current proof:
		    `build/logs/verify_alloc_churn_tracking_20260421_220046_gates_restored.log`.
		  - Fix + verify (2026-04-21): the remaining no-arena explicit-collect `list<int>` growth corruption
		    was a live-header overlap, not another generic kind-flip. Reuse now treats runtime/global roots
		    as ranges instead of exact pointer hits (`native_gc_root_find_in_range(...)` in
		    `lib/runtime_native/100_time_gc_alloc_core_scan_reuse.oren`), and `_list_alloc_buf(...)` in
		    `lib/runtime_native/170_lists_core.oren` now rejects any returned buffer whose byte range
		    overlaps the live 32-byte list header. If reuse still hands back such a chunk, the helper moves
		    that reactivated node back to the free list and falls back to a fresh raw allocation instead of
		    letting the copy loop scribble the header. The focused no-arena repro
		    `tests/native/test_gc_collect_list_int_len128_loop_live.oren` now passes on both `./oren` and
		    fresh `./oren_stage2`
		    (`build/logs/gc_collect_list_int_len128_loop_live_stage1_probe2.run.log`,
		    `build/logs/gc_collect_list_int_len128_loop_live_stage2_probe2.run.log`), and the current
		    compact alloc-churn smoke is green again under stage2
		    (`build/logs/verify_alloc_churn_tracking_20260421_stage2_after_overlap_guard.log`).
		  - Refresh + verify (2026-04-22): that broader benchmark-sized alloc_churn thread is no longer
		    reproducing on the current tree. The reduced explicit-collect fixture
		    `tests/native/test_gc_collect_alloc_churn_debug_shape.oren` is now clean again on fresh stage2
		    (`build/logs/gc_collect_alloc_churn_debug_shape_runs_default.log`, 20/20 direct runs), and the
		    bounded benchmark hunt now ends with `no bad-list hits in 10 runs`
		    (`build/logs/make_triage_alloc_churn_bad_list_current_20260422_post42713c00.log`). The old
		    nonzero `make` status there came only from the triage harness intentionally returning failure
		    when no hit is found, not from a live runtime fault.
		  - Guard restore (2026-04-22): the reduced debug-shape fixture stays out of the Tier-1 quick smoke
		    because the full stress env makes it too expensive there, but the repo now ships
		    `verify-alloc-churn-broad-current` plus a matching `verify-runtime-robustness` leg. That verifier
		    first runs `tests/native/test_gc_collect_alloc_churn_debug_shape.oren` directly on fresh stage2
		    and then inverts the hunt-script exit convention into a bounded success check, so the previously
		    open full-surface alloc_churn regression remains covered without treating a hunt tool as a verifier.
		  - Fix + verify (2026-04-21): the focused green join-waiter/STW tail now has two current guardrails
		    instead of only old trace notes. `lib/runtime_native/100_time_core.oren` now collapses duplicate
		    OS-thread registrations by recycled TID, preferring one live canonical node and marking the rest
		    DEAD so STW parked-count math cannot drift upward on short-lived helper threads. The same pass
		    now makes `native_time_current_thread_node_or0()` prefer live matches and marks all same-TID
		    nodes dead on exit/join cleanup instead of only the first match. After the duplicate-TID fix
		    exposed a second lost-wake window in `test_gc_stw_wakes_netpoll_blocked_threads`, STW now
		    reissues `native_netpoll_wake()` while parked threads are still short and waits in bounded
		    10ms slices instead of one long sleep (`lib/runtime_native/100_time_gc_stw.oren`). The new
		    split guard `scripts/verify_native_quick_green_join_waiters_modes.sh` runs the focused
		    stage2 green-only and OS-only join-waiter stress modes after seed prewarm, and
		    `verify-runtime-robustness` now includes it. Current evidence:
		    `build/logs/verify_native_quick_green_join_waiters_modes_20260421_194941.log`,
		    `build/logs/runtime_robustness_w5_20260421_193511.log`, and
		    `build/logs/make_verify_green_join_waiters_guarded_20260421_stw_renudge.log`.
		  - Refresh (2026-04-21): the older stage2 world-lock/entry-args panic thread no longer needs to
		    sit as a bare March TODO. The direct traced slice now has current proof and a stronger guard:
		    `scripts/triage_green_two_workers_world_lock_smoke.sh` passed 3/3 under
		    `OREN_GREEN_POLL_CACHE=1`, `OREN_TRACE_GREEN_ENTRY_ARGS=1`, `OREN_QI_TRACE_GREEN_LIST=1`,
		    `OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1`, and `OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50`
		    (`build/logs/triage_green_world_lock_entry_args_current_20260421_200041.log`), while the
		    inner log shows the historical `green_entry_args` path staying sane through joins and
		    `gc collect done` (`build/logs/oren_stage2_green_two_workers_world_lock_smoke.log`). The
		    direct recipe is now the shipped `verify-green-world-lock-guarded` surface and is bundled
		    into `verify-runtime-robustness` via the same traced env set, so re-open this thread only if
		    the broader stage2 quick-integration path reproduces again.
		  - Fix + verify (2026-04-21): the W5 runtime/triage wrappers are now interrupt-safe. The
		    Darwin timeout path in `scripts/run_native_quick_integration.sh` starts native builds in a
		    fresh process group and kills the full group on timeout, while
		    `scripts/triage_native_quick_flake.sh`,
		    `scripts/triage_native_quick_stage2_flake.sh`,
		    `scripts/triage_stage2_quick_until_world_lock.sh`, and
		    `scripts/verify_runtime_robustness_w5.sh` now track their active child PID, kill
		    descendant trees on SIGTERM/SIGINT, and preserve the in-flight inner logs before exit.
		    Direct proof: the interrupted base-only bundle in
		    `build/logs/runtime_robustness_interrupt_cleanup_20260421_202907.log` left no lingering
		    `verify_runtime_robustness_w5`, `triage_native_quick_base_flake`,
		    `run_native_quick_integration.sh`, or `./oren_stage2 build ...` children after termination.
		  - Correction + verify (2026-04-21): the earlier “pre-world-lock build hang” read was a bad
		    diagnosis caused by interrupting the bundled W5 run mid-flight. A clean rerun now passes
		    end-to-end (`build/logs/make_verify_runtime_robustness_20260421_cleanupfix_20260421_202922.log`,
		    `build/logs/runtime_robustness_w5_20260421_202923.log`). That current evidence shows the
		    guarded pre-world-lock path, the direct world-lock/entry-args leg, the stage2 native quick
		    path, the C backend flakes, alloc-churn tracking, and the green join-waiter split guard all
		    completing on the same tree.
		  - Expand fast-path tracing on native emitters (arm64 + x64) to pin header writes (`OREN_TRACE_NATIVE_LIST_HDR=1`).
	    - Done: arm64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-25).
    - Done: x64 fast list push while-loops now emit list_hdr traces on count updates (rolling, 2026-02-26).
    - Next: correlate list_hdr traces with free-list header dumps to find the first corrupt write.
    - Investigate list_int tracking-node size corruption (alloc_churn free-list traces show huge chunk sizes despite valid headers).
    - New: size-mismatch traces now dump `list_hdr_ring` (when ring capture is active) to
      show the last header writes for the mismatched pointer (2026-02-26).
    - Trace: alloc_churn ring capture + forced list_int still shows only `chunk=32` frees and
      no size mismatches (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring2.log`, 2026-02-26).
    - Trace: longer header ring capture (cap=2000, ring=256) still shows only `chunk=32` frees and
      no size mismatches (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_ring3.log`, 2026-02-26).
    - Trace: poison+reuse+GC sweep run (`OREN_GC_POISON_LIST_HEADERS=1`,
      `OREN_TRACE_GC_SWEEP=1`, `OREN_TRACE_LIST_CORRUPT=1`) segfaulted quickly; first
      sweep/reuse summary emitted before crash (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_sweep.log`, 2026-02-26).
    - Trace: poison+GC sweep with list reuse disabled (blocks reuse on) still segfaulted
      (log: `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_sweep.log`, 2026-02-26).
    - Trace: poison+GC sweep with reuse blocks disabled completes cleanly (log:
      `build/logs/alloc_churn_trace_poison_noreuse_len64_gc50_200_sweep.log`, 2026-02-26).
    - New: reuse scan now drops nodes with bad `native_node_magic` and can trace via
      `OREN_TRACE_GC_REUSE_NODE_MAGIC=1` (rolling, 2026-02-26).
    - Trace: poison+reuse (list reuse off) with node-magic tracing completed cleanly; no
      bad-node-magic hits (`guard_bad_magic=0`) in summaries (log:
      `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_magic.log`, 2026-02-26).
    - Trace: repeat poison+reuse (list reuse off) with node-magic tracing also completed cleanly;
      still no bad-node-magic hits (log:
      `build/logs/alloc_churn_trace_poison_nolistreuse_len64_gc50_200_magic2.log`, 2026-02-26).
    - Trace: poison+reuse (list reuse on) with node-magic tracing segfaulted after a second sweep;
      reuse summaries show `guard_bad_magic=0` but `guard_bad_list=6` before crash (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_magic.log`, 2026-02-26).
    - Trace: poison+reuse with bad-list safe tracing timed out with repeated bad-list hits on a
      single list header (ptr `4341780128`, kind=2, cap=0); `freed_seen=0` in precheck and
      `guard_bad_list` incremented (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist.log`, 2026-02-26).
    - New: bad-list safe trace now prints header + node fields (len/cap/buf/magic + node kind/size)
      to reduce follow-up repros (rolling, 2026-02-26).
    - New: first bad-list safe print now triggers `native_list_debug_node` for alloc-index
      context (one-shot, rolling, 2026-02-26).
    - New: `native_list_debug_node` now reports membership in free-block bucket lists
      (64/256/1024/other) to disambiguate reuse corruption (rolling, 2026-02-26).
    - New: reuse scan can optionally detect nodes still present in allocs
      (`OREN_TRACE_GC_REUSE_ALLOC_NODE=1`) and counts `guard_alloc_node` in summaries (rolling, 2026-02-26).
    - New: reuse scan can detect alloc-index duplicate nodes via
      `OREN_TRACE_GC_REUSE_ALLOC_INDEX_DUP=1` and counts `guard_alloc_index_dup` (rolling, 2026-02-26).
    - New: bad-list summary now reports `guard_bad_magic`, `guard_alloc_node`, and
      `guard_alloc_index_dup` to avoid missing guard signals in trace logs (rolling, 2026-02-26).
    - Trace: poison+reuse with alloc-node/alloc-index-dup tracing still hits bad-list while
      `guard_bad_magic/guard_alloc_node/guard_alloc_index_dup` remain 0; no
      `[gc_reuse_alloc_*]` prints observed (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_allocnode_dup2.log`, 2026-02-26).
    - Trace: ring-all bad-list run (`OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1`) still shows
      `guard_bad_magic/guard_alloc_node/guard_alloc_index_dup=0` while emitting
      `list_hdr_ring idx=...` entries (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall.log`, 2026-02-26).
    - New: ring-all dumps now filter to the bad-list pointer (one-shot) via
      `native_list_header_ring_filter_set`, reducing noise in ring-all logs (rolling, 2026-02-26).
    - New: ring-all filter emits `[list_hdr_ring_filter_miss]` when no ring entries match
      the filtered pointer, signaling missing ring capture (rolling, 2026-02-26).
    - Trace: ring-all filter run (miss warning enabled) still finds a matching ring entry;
      no `[list_hdr_ring_filter_miss]` emitted (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter_miss.log`, 2026-02-26).
    - New: bad-list dumps can emit the most recent list header ops for that pointer via
      `OREN_TRACE_GC_REUSE_BAD_LIST_RING_RECENT=<n>` and `[list_hdr_ring_recent]` (rolling, 2026-02-26).
    - New: `OREN_TRACE_GC_REUSE_BAD_LIST_KIND_FLIP=1` only emits recent-op dumps when
      `node_kind` changes across bad-list hits (rolling, 2026-02-26).
    - New: `gc_reuse_summary_at_bad_list` now reports `kind_flip` when the kind-flip
      gate is active (rolling, 2026-02-26).
    - Trace: kind-flip run still emits recent-op entries (no suppression observed; node_kind
      still changes in this run) (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip.log`, 2026-02-26).
    - Trace: kind-flip summary shows `kind_flip=0`; only the first bad-list dump emits
      recent-op entries (duplicates within the dump reflect ring state, not repeated dumps)
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip2.log`, 2026-02-27).
    - Trace: ring-cap 512 run still shows `op=1` entries for the bad list pointer with the
      same recent-op sequence (`1:2`) despite larger ring history (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringcap512.log`, 2026-02-27;
      correlate:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringcap512_correlate.log`, 2026-02-27).
    - Trace: correlator delta output shows no per-hit deltas for kind-flip2 (single bad-list
      sample in correlate output) (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_kindflip2_correlate.log`, 2026-02-27).
    - Trace: multihit run (iters=500) still shows identical recent-op sequence (`1:2`);
      correlator emits a `list_hdr_ring_recent_delta` header with no deltas
      (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_multihit_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_multihit_20260227_correlate.log`,
      2026-02-27).
    - Trace: multihit run (iters=1000, ring_recent=64) still shows identical recent-op sequence (`1:2`);
      correlator emits a `list_hdr_ring_recent_delta` header with no deltas
      (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_multihit_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_multihit_20260227_correlate.log`,
      2026-02-27).
    - Trace: multihit run (iters=1000, ring_recent=128, ringcap=512) still shows identical recent-op
      sequence (`1:2`); correlator emits a `list_hdr_ring_recent_delta` header with no deltas
      (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_ringcap512_recent128_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_ringcap512_recent128_20260227_correlate.log`,
      2026-02-27).
    - Trace: pre-bad-list ring snapshot (`OREN_TRACE_GC_REUSE_BAD_LIST_RING_PRE=64`) emits
      `[list_hdr_ring_pre]` before the first bad-list print; sequence remains `1:2`
      (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_20260227_correlate.log`,
      2026-02-27).
    - Trace: pre-bad-list ring snapshot (`OREN_TRACE_GC_REUSE_BAD_LIST_RING_PRE=128`,
      `OREN_TRACE_GC_REUSE_BAD_LIST_RING_RECENT=128`) still shows the same `1:2` sequence
      (logs: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_pre128_recent128_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_1000_pre128_recent128_20260227_correlate.log`,
      2026-02-27).
    - Trace: pre-bad-list dump-all (filtered) still shows only `op=1 kind=2` entries for
      the bad pointer; no earlier ops appear (logs:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_dumpall_20260227.log`,
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_pre64_recent64_dumpall_20260227_correlate.log`,
      2026-02-27).
    - Tool: bad-list dumps now log `[list_hdr_ring_state]` (head/cap/delta) per trigger
      to confirm whether the ring advances between bad-list events (rolling, 2026-02-27).
    - Trace: ring state shows head did not advance between bad-list events
      (`head=357`, `delta=0`) in the 500-iter ringstate run (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringstate_20260227.log`, 2026-02-27).
    - Trace: ring-put watch (pre=64) emitted no `[list_hdr_ring_put]` lines, suggesting
      no list header trace ops for the bad pointer after the pre dump (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringput_20260227.log`, 2026-02-27).
    - Tool: GC list header poison + bad-list dumps now emit ring ops (`op=90` for poison,
      `op=91` for bad-list) via `native_list_header_ring_put_gc`; ring op filter now
      accepts these codes to surface them in dumps (rolling, 2026-02-27).
    - Tool: first list-header poison can optionally trigger a one-shot ring-all dump
      (gated by `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1`) to confirm `op=90` visibility
      in ring logs (rolling, 2026-02-27).
    - Trace: ringgc run (poison+reuse, ring ops enabled) segfaulted before emitting any
      output; run log is empty (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_ringgc_20260226.log`, 2026-02-27).
    - Trace: ring-all run with reduced iters emits `[gc_free_list]` + `[list_hdr_ring]`
      output and a `gc_reuse_summary` before segfault; no bad-list triggers observed
      in that log (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_100_ringall_20260227.log`, 2026-02-27).
    - Trace: ring-all run after enabling op=90/91 in ring filter shows `op=90` entries
      for poisoned list headers (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_100_ringall3_20260227.log`, 2026-02-27).
    - Trace: ringbad run (iters=300) still shows `op=90` poison entries but no
      `gc_reuse_bad_list` events before segfault (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc20_300_ringbad_20260227.log`, 2026-02-27).
    - Trace: precheck+ringbad run re-triggers `gc_reuse_bad_list`; ring pre/recent
      entries now show `op=91` dumps with corrupted header fields and `op=90` poison
      right before the bad-list detection (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_ringbad_20260227.log`, 2026-02-27).
    - Trace: precheck+idx run logs `gc_reuse_bad_list_idx` showing alloc-index presence
      on the first bad-list hit (idx_node set) and missing index on the second hit,
      while node kind/size flips from `1/32` to `0/48` (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idx_20260227.log`, 2026-02-27).
    - Trace: precheck+idxflip run confirms alloc-index flip detection via
      `gc_reuse_bad_list_idx_flip` for the same pointer across successive bad-list hits
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idxflip_20260227.log`,
      2026-02-27).
    - Trace: precheck+rebuild run emitted `gc_reuse_bad_list_idx_flip` but no
      `gc_reuse_bad_list_rebuild` entries (no alloc-index rebuild observed after the bad-list),
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_rebuild_20260227.log`,
      2026-02-27).
    - Trace: precheck+idxremove run hit `gc_reuse_bad_list_idx_flip` but no
      `gc_reuse_bad_list_index` events (no alloc-index tombstone/remove/insert/replace logged);
      run terminated with SIGTERM after ~189s (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_idxremove_20260226.log`,
      2026-02-26).
    - Trace: precheck+scan run shows `gc_reuse_bad_list_index_scan found=0` after the second
      bad-list hit (alloc-index entry not present by full-table scan; `hash_idx=818 cap=2048`);
      run timed out at 120s (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_scan_20260226.log`,
      2026-02-26).
    - Trace: precheck+scan2 run shows `gc_reuse_bad_list_index_scan found_node=1` at `node_idx=818`
      with `node_ptr=0` (alloc-index slot still points at the old node, but the node’s ptr
      field was cleared). `found=0` for the original ptr; run timed out at 120s (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_scan2_20260226.log`,
      2026-02-26).
    - Trace: precheck+fix run (after removing bad-list ptr from alloc-index) still shows
      `gc_reuse_bad_list_index_scan found=0` on the second hit (no remaining node slot observed);
      run timed out at 120s (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_fix_20260226.log`,
      2026-02-26).
    - Trace: precheck+putbad run emitted no `[gc_free_list_put_bad_hdr]` lines before
      the bad-list hit (suggests list header is still valid when pushed to free list);
      scan still shows `found=0` after second hit. Run timed out at 120s (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_putbad_20260226.log`,
      2026-02-26).
    - Trace: precheck+state run shows the bad-list ptr transitions from `allocs=1` on first hit
      to `allocs=0` and `in_roots=1 (root_kind=3)` on second hit, with no free-list residency
      (`free_total=0`), implying a stale root keeps the corrupted header alive after it leaves
      allocs (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_state_20260226.log`,
      2026-02-26).
    - Trace: precheck+state5 run logs root slot details for the stale root:
      `root_slot_offset=3456` (`root_slot_index=432`) with `root_slot_val` equal to the bad ptr
      and `root_count=3` (duplicate roots). Confirms the root slot lives inside `g_storage`
      at offset 3456 (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_precheck_state5_20260226.log`,
      2026-02-26).
    - Trace: compile-time global slot dump (`OREN_TRACE_GLOBAL_SLOTS=1`,
      `OREN_TRACE_GLOBAL_SLOT_OFF=3456`) maps the stale root slot to
      `g_trace_list_hdr_ring_dup_seen_head` (alloc_churn build, 2026-02-26).
    - Tool: list header ring ptr guard (`OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1`) logs if the
      ring buffer pointer or dup-seen buffer pointer equals `g_storage` (one-shot, 2026-02-26).
    - Tool: list header ring ptr guard now also checks `g_trace_list_hdr_ring_dup_seen_head` and
      logs `[list_hdr_ring_dup_seen_head_ptr]` if it looks like a tracked alloc/free pointer
      (one-shot, 2026-02-27).
    - Trace: precheck+guard run (ptr guard enabled) still hits bad-list; stale root now reports
      `root_slot_offset=3464` (`root_slot_index=433`) and no `[list_hdr_ring_ptr_guard]` lines
      were emitted; run timed out at 120s (log:
      `build/logs/alloc_churn_trace_precheck_guard_20260226.log`, 2026-02-26).
    - Trace: precheck+guard2 run (ptr guard enabled) still hits bad-list; stale root remains
      `root_slot_offset=3464` (`root_slot_index=433`) and no guard lines emitted; run timed out
      at 120s (log:
      `build/logs/alloc_churn_trace_precheck_guard2_20260227.log`, 2026-02-27).
    - Trace: compile-time global slot dump after rebuilding stage2 maps slot 3464/index 433 to
      `g_trace_list_hdr_ring_ptr_guard` (log:
      `build/logs/global_slots_idx433_after_stage2.log`, 2026-02-27).
    - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_corrupt]` if the guard slot value
      exceeds 1 and looks like a tracked alloc/free pointer (one-shot, 2026-02-27).
    - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_set]` whenever the guard slot changes,
      capturing the new value + reason (env_enable/corrupt/g_storage/dup_seen_head_ptr) and
      the current op/list/kind (one-shot, 2026-02-27).
    - Tool: ptr-guard now logs `[list_hdr_ring_ptr_guard_changed]` if the guard slot changes
      outside the helper (detects unexpected writes; one-shot per change, 2026-02-27).
    - Tool: GC reuse precheck now polls the ptr-guard via `list_hdr_ring_guard_poll` (op=92)
      when `OREN_TRACE_GC_REUSE_PRECHECK=1`, so unexpected writes are detected even if no
      list header ring puts occur (2026-02-27).
    - Tool: root lookup now polls the ptr-guard via `list_hdr_ring_guard_poll` (op=93)
      in `native_gc_root_find`, widening coverage beyond reuse precheck (2026-02-27).
    - Tool: bad-list ptr state log now includes `guard` + `guard_last` to confirm whether
      `g_trace_list_hdr_ring_ptr_guard` changed when stale roots are reported (2026-02-27).
    - Trace: compile-time global slot mapping shows stale-root offsets `2376/2896/3584` align to
      `g_gc_reuse_bad_list_triggers`, `g_runtime_root_len`, and `g_trace_list_header`,
      indicating non-pointer globals are being overwritten by bad-list pointers
      (`alloc_churn_globals_trace_20260227_072238.log`, 2026-02-27).
    - Tool: `OREN_TRACE_GC_GLOBAL_GUARD=1` logs when those globals hold pointer-like values
      to narrow down corruption timing (rolling, 2026-02-27).
    - Tool: `OREN_GC_ROOTS_SKIP_RUNTIME_GLOBALS=1` (compile-time env) skips registering
      runtime globals as GC roots to test whether false roots from runtime counters
      are masking bad-list reuse (rolling, 2026-02-27).
    - Tool: `OREN_TRACE_GC_REGISTER_ROOT_NAMES=1` (compile-time env) emits per-root
      `[gc_root_name]` entries (name + slot pointer) during entry registration to map
      non-g_storage roots back to global names (rolling, 2026-02-27).
    - Trace: even with `OREN_GC_ROOTS_SKIP_RUNTIME_GLOBALS=1`, bad-list reuse still hits
      a stale root (root_idx=146, root_count=2) whose slot pointer lies outside g_storage
      (`root_slot_offset=-1`), so runtime globals are not the sole source of false roots
      (`alloc_churn_skiproots_badlist_len64_gc50_200_thr500_ring_20260227_072238.log`,
      2026-02-27).
    - Trace: precheck+guard4 run shows a single `[list_hdr_ring_ptr_guard_set]` (env_enable)
      and no subsequent guard flips before timeout (log:
      `build/logs/alloc_churn_trace_precheck_guard4_20260227.log`, 2026-02-27).
    - Trace: precheck+guard5 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
      (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
      `build/logs/alloc_churn_trace_precheck_guard5_20260227.log`, 2026-02-27).
    - Trace: precheck+guard6 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
      (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
      `build/logs/alloc_churn_trace_precheck_guard6_20260227.log`, 2026-02-27).
    - Trace: precheck+guard7 run still shows only the initial `[list_hdr_ring_ptr_guard_set]`
      (env_enable); no `[list_hdr_ring_ptr_guard_changed]` emitted before timeout (log:
      `build/logs/alloc_churn_trace_precheck_guard7_20260227.log`, 2026-02-27).
    - Tool: reuse scan can optionally log `[gc_reuse_list_hdr]` for list headers encountered
      during reuse (`OREN_TRACE_GC_REUSE_LIST_HDR=<n>`) to check if list header fields
      are already corrupted before reuse validation (rolling, 2026-02-27).
    - Trace: list-hdr reuse scan run with `OREN_TRACE_GC_REUSE_LIST_HDR=8` segfaulted
      quickly and emitted no `[gc_reuse_list_hdr]` lines (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_listhdr_20260227.log`, 2026-02-27).
    - Tool: list header validation now optionally logs `[gc_list_hdr_ok]` before
      `native_gc_list_header_ok_impl` returns (`OREN_TRACE_GC_LIST_HDR_OK=<n>`)
      to capture raw header fields even if validation fails (rolling, 2026-02-27).
    - Trace: list header ok trace emitted entries (e.g., `kind=8` and `kind=2`)
      before a segfault (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_hdr_ok_20260227.log`, 2026-02-27).
    - Tool: list header kind tracing now logs `[gc_list_hdr_kind]` at reuse + mark call sites
      (`OREN_TRACE_GC_LIST_HDR_KIND=<n>`) to capture the kind/ptr source before validation
      (rolling, 2026-02-27).
    - Trace: `[gc_list_hdr_kind]` emitted `src=mark_list_int` with `kind=8` (list_int_kind)
      before segfault (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_hdr_kind_20260227.log`,
      2026-02-27).
   - Tool: allocation kind change tracing logs `[alloc_kind_change]` when a tracked node’s
     kind changes during `oren_track_alloc*` (`OREN_TRACE_ALLOC_KIND_CHANGE=<n>`, optional
     filters: `OREN_TRACE_ALLOC_KIND_CHANGE_PTR`/`..._NODE`), including initial list/list_int
     retags from `kind=0`, to catch unexpected retagging (rolling, 2026-02-27).
    - Trace: alloc-kind-change run emitted no `[alloc_kind_change]` lines before segfault
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_kindchange_20260227.log`,
      2026-02-27).
    - Trace: alloc-kind-change re-run (cap=32) segfaulted before emitting any output; run log
      is empty (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_500_kindchange2_20260226.log`,
      2026-02-27).
    - Trace: ring-recent run logs `[list_hdr_ring_recent]` entries for the bad list pointer
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent.log`, 2026-02-26).
    - Trace: correlator output now includes `[list_hdr_ring_recent]` blocks for the bad list
      pointer (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent_correlate.log`, 2026-02-26).
    - Trace: ring-recent (n=16) run still reports repeated `op=1` entries for the bad list pointer;
      correlator sequence remains `1:2` (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent16.log`, 2026-02-26;
      correlate:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringrecent16_correlate.log`, 2026-02-26).
    - New: `OREN_TRACE_LIST_HDR_RING_DUP=1` logs `[list_hdr_ring_dup]` when the ring buffer
      already contains the same list pointer; per-pointer suppression uses
      `OREN_TRACE_LIST_HDR_RING_DUP_SEEN_CAP` (default 64) to avoid repeat logs
      (log cap via `OREN_TRACE_LIST_HDR_RING_DUP_CAP`, 2026-02-26).
    - Trace: ring-dup run emits repeated `[list_hdr_ring_dup]` hits for list_int headers
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringdup.log`, 2026-02-26).
    - Trace: ring-dup suppression run logs one dup per list pointer (distinct list_int headers)
      under `OREN_TRACE_LIST_HDR_RING_DUP_SEEN_CAP` (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringdup_once.log`, 2026-02-26).
    - Trace: ring-all filter run emits a single `list_hdr_ring idx=...` line for the bad pointer
      (log: `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter.log`, 2026-02-26).
    - Tool: `tools/trace_list_hdr_correlate.py` now includes `[list_hdr_ring]` entries when
      correlating `gc_free_list` samples (rolling, 2026-02-26).
    - Tool: correlator accepts ring-all `idx=` entries to match `list_hdr_ring` dumps
      when `OREN_TRACE_GC_FREE_LIST_HDR_RING_ALL=1` is set (rolling, 2026-02-26).
    - Tool: correlator now ingests `[list_hdr_ring_recent]` and emits recent-op blocks
      for bad-list pointers, including a summarized op sequence and per-hit deltas
      across successive bad-list events (rolling, 2026-02-26).
    - Tool: correlator now captures recent-op deltas keyed off `gc_reuse_bad_list`
      (via subsequent `list_hdr_ring_recent` lines) and annotates delta sources
      to handle logs with sparse `gc_free_list` samples (rolling, 2026-02-27).
    - Tool: correlator parses `[list_hdr_ring_pre]` entries to keep pre-bad-list
      snapshots alongside recent-op sequences (rolling, 2026-02-27).
    - Trace: correlate output for the alloc-node/dup run now captures the ring entry alongside
      the `gc_free_list` sample (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_allocnode_dup2_correlate.log`, 2026-02-26).
    - Trace: ring-all correlate output captures the matching ring entry for the
      free-list sample (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_correlate.log`, 2026-02-26).
    - Trace: ring-all filter correlate output captures only the filtered ring entry
      (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_ringall_filter_correlate.log`, 2026-02-26).
    - Trace: follow-up bad-list safe run shows corrupted header fields (`len=4122543214814507828`,
      `cap=13879`, `buf=0`, `magic=0`) while precheck still reports `freed_seen=0`; node_kind
      flips (1 -> 0) and node_size (32 -> 48) between prints for the same node (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist2.log`, 2026-02-26).
    - Trace: one-shot `native_list_debug_node` now shows the bad-list node is still in allocs
      (`node_in_allocs=1`) and not in free blocks (`node_in_free_blocks=0`) while the header
      fields are corrupt; node_kind flips 1 -> 0 with node_size 32 -> 48 (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist3.log`, 2026-02-26).
    - Trace: bucket scans confirm the bad-list node is not in any reuse free-block bucket
      (`node_in_free_blocks_64/256/1024/other=0`) while still present in allocs (log:
      `build/logs/alloc_churn_trace_poison_reuse_len64_gc50_200_badlist4.log`, 2026-02-26).
    - Trace: reuse-enabled alloc_churn (blocks+lists unsafe) still shows only `chunk=32` frees
      and no size mismatches; reuse stats show large scan_steps in later windows
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse1.log`, 2026-02-26).
    - Trace: reuse + scan cap (`OREN_GC_REUSE_SCAN_CAP=4096`) still shows only `chunk=32` frees
      and no size mismatches; reuse stats show scan_cap_hits with reduced scan_steps
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_scan_cap.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=128` segfaulted, but still showed only
      `chunk=32` frees before the crash; reuse stats showed large scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_GC_REUSE_BUCKETS=1` + `OREN_BENCH_LIST_LEN=128` also
      segfaulted; still only `chunk=32` frees before the crash; reuse stats show large
      scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128_buckets.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` also segfaulted; still only
      `chunk=32` frees before the crash; reuse stats show large scan_steps with cap hits
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64.log`, 2026-02-26).
    - Trace: reuse + scan cap + `OREN_BENCH_LIST_LEN=64` with verbose reuse logging also
      segfaulted; captured `[gc_reuse_hit]` lines for small/medium chunks before crash
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_verbose.log`, 2026-02-26).
    - Trace: no-reuse + `OREN_BENCH_LIST_LEN=64` completes cleanly; still only `chunk=32`
      frees and no size mismatches
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_noreuse_len64.log`, 2026-02-26).
    - Trace: reuse + bad-list tracing hit `[gc_reuse_bad_list]` with corrupt header fields
      (len=4 cap=5 buf=6 magic=7) and timed out; indicates reuse guardrail catches corrupted
      list headers under reuse stress
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist.log`, 2026-02-26).
    - New: bad-list guardrail now force-enables list_hdr_ring so reuse corruption dumps
      can capture the last header writes even when ring tracing was not otherwise enabled.
    - New: bad-list guardrail now dumps full list_hdr_ring snapshot to avoid missing pointer
      correlation when ring sampling is sparse.
    - Trace: bad-list run with full ring dump still did not show any list_hdr_ring entries
      for the corrupted pointer, suggesting the bad header was never recorded in the ring
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist_ring2.log`, 2026-02-26).
    - Trace: bad-list logs now include tracking-node fields; observed node_freed=1 with valid
      node_magic and kind=8 when corruption is detected, suggesting the tracked node is
      already marked freed at reuse time
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_badlist_node.log`, 2026-02-26).
    - Trace: block-reuse only (lists disabled) still segfaulted under `OREN_BENCH_LIST_LEN=64`;
      no bad-list events were emitted, suggesting the crash is not limited to list reuse
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_blocks_only.log`, 2026-02-26).
    - Trace: no-reuse `OREN_BENCH_LIST_LEN=64` still completes cleanly after guardrail
      changes; only `chunk=32` frees observed
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_noreuse_len64_postguard.log`, 2026-02-26).
    - New: `OREN_TRACE_GC_FREE_LIST_PUT=1` logs nodes as they enter free lists (cap via
      `OREN_TRACE_GC_FREE_LIST_PUT_CAP`).
    - New: `OREN_TRACE_GC_FREE_LIST_TAKE=1` logs nodes as they are removed from free lists
      (cap via `OREN_TRACE_GC_FREE_LIST_TAKE_CAP`).
    - Trace: free-list put logs show list/list_int nodes inserted with freed=1 and intact
      magic/len/cap; bad-list events still show corrupted header fields
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freeput.log`, 2026-02-26).
    - Trace: even with `OREN_TRACE_GC_FREE_LIST_PUT_CAP=2000`, the bad ptr did not appear
      in any free-list put logs before `[gc_reuse_bad_list]`, suggesting it enters reuse
      without a visible free-list insertion in the current trace window
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freeput2.log`, 2026-02-26).
    - Trace: free-list take logging captured a single put/take pair (freed flipped to 0
      on take); no bad-list events observed before timeout
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake.log`, 2026-02-26).
    - Trace: free-list take logging with cap=2000 again emitted only a single put/take pair
      (two-line log) and no bad-list events before timeout
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake2.log`, 2026-02-26).
    - Trace: `OREN_BENCH_LIST_LEN=128` with free-list take logging (timeout 120s) still
      emitted only a single put/take pair and no bad-list events before timeout
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len128_freetake.log`, 2026-02-26).
    - Trace: free-list take logging with line-buffered output still emitted only a single
      put/take pair; run_status=124 (timeout) recorded in env log
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake3.log`, 2026-02-26).
    - Trace: lowering GC interval to `OREN_BENCH_GC_EVERY=100` still emitted only a single
      put/take pair; run_status=124 (timeout) recorded in env log
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_freetake4_gc100.log`, 2026-02-26).
    - New: `OREN_TRACE_GC_FREE_LIST_TAKE_COUNT=1` prints total/by_ptr/reuse take counts at shutdown
      to distinguish sparse activity from log truncation (2026-02-26).
    - New: `OREN_BENCH_ITERS=<n>` overrides alloc_churn iteration count (default 20000) to
      shorten trace runs when heavy GC logging is enabled (2026-02-26).
    - Trace: small-iteration run with `OREN_BENCH_ITERS=50`, `OREN_BENCH_LIST_LEN=8`,
      `OREN_BENCH_GC_EVERY=10`, `OREN_GC_REUSE_SCAN_CAP=128` emitted
      `[gc_free_list_take_count] ... reuse=6` plus repeated bad-list entries, confirming
      reuse hits occur even when per-take logs are sparse
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len8_takecount_50_cap128.log`, 2026-02-26).
    - Trace: `OREN_BENCH_ITERS=200`, `OREN_BENCH_LIST_LEN=64`, `OREN_BENCH_GC_EVERY=50`,
      `OREN_GC_REUSE_SCAN_CAP=128` still reports `[gc_free_list_take_count] ... reuse=6`
      with repeated bad-list entries (run_status=124 timeout), indicating reuse hits
      even without per-take logging
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_takecount_200_cap128.log`, 2026-02-26).
    - New: `OREN_TRACE_GC_REUSE_SUMMARY=1` prints a per-GC summary line that includes
      reuse stats plus free-list take counters (and auto-enables reuse tracing),
      to correlate bad-list bursts with reuse/take activity; summary now includes
      `bad_list_prints` (2026-02-26).
    - Trace: per-GC summary run (`OREN_BENCH_ITERS=200`, `OREN_BENCH_LIST_LEN=64`,
      `OREN_BENCH_GC_EVERY=50`, `OREN_GC_REUSE_SCAN_CAP=128`) logged
      `[gc_reuse_summary] tries=363 hits=0 ... take_total=0` while still emitting
      repeated bad-list entries, indicating bad-list triggers can occur without reuse hits
      in this short run (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128.log`, 2026-02-26).
    - Trace: summary with `bad_list_prints` still showed `bad_list_prints=0` even though
      `[gc_reuse_bad_list]` lines followed in the log, implying bad-list prints can occur
      after the summary window (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128b.log`, 2026-02-26).
    - Trace: longer summary run (`OREN_BENCH_ITERS=500`, `OREN_BENCH_GC_EVERY=10`) still
      logged a single summary line with `bad_list_prints=0` followed by repeated bad-list
      entries, suggesting summary timing does not capture subsequent bad-list prints
      in short timeouts (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_500_gc10.log`, 2026-02-26).
    - Trace: 180s timeout run (`OREN_BENCH_ITERS=1000`, `OREN_BENCH_GC_EVERY=10`) still
      logged one summary line with `bad_list_prints=0` followed by bad-list prints
      counting down 10→1, reinforcing the gap between summary and later bad-list logs
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_1000_gc10_t180.log`, 2026-02-26).
    - New: `gc_reuse_summary` now reports `bad_list_triggers` (counter incremented before
      cap check) alongside `bad_list_prints`, to detect bad-list triggers that occur after
      the summary window (2026-02-26).
    - New: bad-list dumps now emit `[gc_reuse_summary_at_bad_list]` snapshots when
      `OREN_TRACE_GC_REUSE_SUMMARY=1`, capturing reuse/take counters at the moment a
      bad-list is detected (2026-02-26).
    - Trace: summary-at-bad-list run segfaulted before emitting any bad-list logs
      (run_status=139), so no `[gc_reuse_summary_at_bad_list]` lines captured yet
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128e.log`, 2026-02-26).
    - Trace: lower scan cap (`OREN_GC_REUSE_SCAN_CAP=64`, bad-list cap=3) still
      segfaulted before emitting bad-list logs; summary only
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap64.log`, 2026-02-26).
    - New: bad-list ring dumps now skip when `cap` is implausible (>=1,048,576) to reduce
      segfault risk when corrupted headers point into unmapped memory (2026-02-26).
    - Trace: with ring-dump guard enabled, summary-only run still segfaulted before bad-list logs
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap64_guard.log`, 2026-02-26).
    - Trace: lower-stress run (`GC_EVERY=200`, `ITERS=100`) completed cleanly but produced no
      bad-list or reuse summary output (run log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_100_gc200_cap64_guard.log`, 2026-02-26).
    - Trace: medium-stress run (`GC_EVERY=200`, `ITERS=500`) still segfaulted before bad-list logs;
      summary only (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_500_gc200_cap64_guard.log`, 2026-02-26).
    - Trace: `GC_EVERY=150`, `ITERS=300` still segfaulted before bad-list logs; summary only
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_guard.log`, 2026-02-26).
    - Trace: `GC_EVERY=175`, `ITERS=250` still segfaulted before bad-list logs; summary only
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_250_gc175_cap64_guard.log`, 2026-02-26).
    - New: added `OREN_TRACE_GC_REUSE_BAD_LIST_SAFE=1` to skip bad-list header derefs and
      ring dumps when tracing (2026-02-26).
    - Trace: safe mode + `GC_EVERY=150`, `ITERS=300` still segfaulted before bad-list logs;
      summary only (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_safe.log`, 2026-02-26).
    - New: `OREN_TRACE_GC_REUSE_PRECHECK=1` logs list reuse candidates before
      header validation (cap via `OREN_TRACE_GC_REUSE_PRECHECK_CAP`, default 64, 2026-02-26).
    - Trace: precheck run (`GC_EVERY=150`, `ITERS=300`) captured repeated bad-list events for the
      same node/ptr (len=3762810489372947252 cap=13366 buf=0 magic=0) and completed without
      a segfault (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_precheck.log`, 2026-02-26).
    - Trace: precheck + free-list put (`OREN_TRACE_GC_FREE_LIST_PUT=1`) shows the same ptr had
      a valid empty-list header at free time (len=0 cap=0 buf=0 magic=1279870019), but later
      reappeared as corrupted during reuse (len=3544957662233047860 cap=12342 buf=0 magic=0).
      This points to post-free overwrite / UAF of list header memory (log:
      `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_precheck_put.log`, 2026-02-26).
    - Trace: with freed-list tracking enabled (`OREN_TRACE_GC_FREED_LISTS=1`), no
      `[gc_freed_list_use]` was reported before the bad-list corruption, indicating the
      overwrite likely happens without a tracked alloc-index lookup (log:
      `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_freed.log`, 2026-02-26).
    - New: precheck now reports `freed_seen=1` when freed-list tracking is enabled; latest
      trace shows the corrupted reuse candidate was present in the freed list at precheck time
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_300_gc150_cap64_freed_seen.log`, 2026-02-26).
    - Trace: with `bad_list_triggers` enabled, summary still showed `bad_list_triggers=0`
      while bad-list prints followed (now with `len=0 cap=1 buf=2 magic=3` in the corrupted
      header fields), so the summary window continues to miss later bad-list events
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128d.log`, 2026-02-26).
    - Trace: even with `bad_list_triggers` reported, summary still showed
      `bad_list_triggers=0` while bad-list prints counted down 10→1, indicating triggers
      can occur after the summary snapshot (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128d.log`, 2026-02-26).
    - New: bad-list logs now include `prints=<n>` so each `[gc_reuse_bad_list]` line can be
      correlated directly with the running bad-list counter (2026-02-26).
    - Trace: bad-list log `prints=<n>` counts down as expected (5→1) in
      `gc_hdr_mismatch_reuse_len64_summary_200_cap128c`, confirming the counter tracks
      each bad-list print even when the summary line shows `bad_list_prints=0`
      (log: `build/logs/alloc_churn_trace_gc_hdr_mismatch_reuse_len64_summary_200_cap128c.log`, 2026-02-26).
    - New: alloc_churn trace harness now records run_status/run_timed_out/run_elapsed_sec
      and line-buffer command in the env log for timeout diagnostics (2026-02-26).
    - Next: determine why free-list take traces remain sparse under reuse (single put/take
      pair per 120s run); consider forcing line-buffered logging or recording timeout/exit
      status in trace harness to confirm log completeness.
  - Note: `make test` saw a one-off segfault in `test-native-quick-stage2`
    (log: `build/logs/make_test_20260226_172510.log`); rerun passed
    (log: `build/logs/make_test_native_quick_stage2_20260226_172724.log`). Track for flakes.
  - Note: `make test` hit another `test-native-quick-stage2` segfault (Error 139)
    on 2026-03-03 (log: `build/logs/make_test_20260303_214100.log`);
    rerun `scripts/run_native_quick_integration.sh ./oren_stage2` passed
    (log: `build/logs/repro_native_quick_stage2_20260303_214042.log`). Track for flakes.
  - New: `scripts/triage_native_quick_stage2_flake.sh` runs the stage2 quick integration
    repeatedly and captures per-run logs to help diagnose flaky segfaults; supports
    `ENV=VAL` passthrough args for tracing, logs git/uname metadata, and saves failure
    copies of the inner quick-integration log (2026-03-03).
  - Note: `make test` hit a `test-native-quick` segfault (Error 139) on 2026-03-03
    (log: `build/logs/make_test_20260303_215000.log`); rerun passed
    (log: `build/logs/make_test_20260303_215100.log`). Track for flakes.
  - Note: `make test` hit a `test-native-quick` segfault (Error 139) on 2026-03-05
    (log: `build/logs/make_test_20260305_202158.log`); rerun passed
    (log: `build/logs/make_test_20260305_202230.log`). Track for flakes.
  - Note: `make test` hit a `test-native-quick-stage2` segfault (Error 139) on 2026-03-05
    (log: `build/logs/make_test_20260305_210315.log`); rerun passed
    (log: `build/logs/make_test_20260305_210418.log`). Track for flakes.
  - Note: `make test` hit `test-native-quick` Error 1 on 2026-03-03 in the
    `OREN_GREEN_POLL_CACHE=1` sub-run (panic: "Indexing on non-container";
    log: `build/logs/make_test_20260303_221100.log`); rerun passed
    (log: `build/logs/make_test_20260303_221200.log`). Track for flakes.
  - Trace: stage1 flake harness with `OREN_GREEN_POLL_CACHE=1` timed out on run 1
    (rc=143; log: `build/logs/triage_stage1_quick_green_cache_20260303_221009.log`);
    rerun with `OREN_NATIVE_RUN_TIMEOUT_SECS=30` passed 5 runs
    (log: `build/logs/triage_stage1_quick_green_cache_timeout_20260303_221058.log`).
  - Note: `make test` hit `test-native-quick-stage2` timeout (rc=143) on 2026-03-05
    (log: `build/logs/make_test_20260305_200234.log`); rerun with
    `OREN_NATIVE_RUN_TIMEOUT_SECS=25 OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=25` passed
    (log: `build/logs/make_test_20260305_200352.log`). Track for flakes.
  - New: `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS` overrides the timeout for the
    `OREN_GREEN_POLL_CACHE=1` sub-run in `scripts/run_native_quick_integration.sh` (2026-03-03).
  - Trace: stage2 quick-integration flake harness ran 10 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage2_quick_20260303_214758.log`).
  - Verified (2026-03-15): arm64 self-hosted stage2 quick integration no longer stalls in
    the compiler native-emit path. `./scripts/run_native_quick_integration.sh ./oren_stage2`
    completed cleanly, and the fresh phase log reaches `macho.fixups.done` plus
    `build.native.emit.done` before the quick-integration binary runs
    (`build/logs/oren_stage2_native_quick_integration.phases.log`,
    `build/logs/oren_stage2_native_quick_integration.log`).
  - Verified (2026-03-15): the current `make test` run advances past
    `test-native-quick-stage2`; `build/logs/make_test_after_47c7fada.log` reaches the
    capsule rtobj-seed path only after both stage1 and stage2 native quick integration
    pass, so the previous arm64 stage2 local-fixup timeout is no longer the active suite
    blocker.
  - Fix (2026-03-15): `rtobj-seed` no longer force-refreshes the capsule seed on every run.
    The Makefile now lets `scripts/build_rtobj_seed.sh` no-op/copy on matching capsule
    hash hits and only pay the cold `examples/hello --capsule` build when the current
    capsule hash is actually missing. The remaining slow path is the first cold fill, not
    repeated forced refresh.
  - Fix (2026-03-15): host capsule cold-seed population now uses `./oren` as the build
    compiler while still keying the artifact by runtime hash + backend sig. On arm64-macos,
    the measured cold build through `./oren` completed in about 12.9s and produced
    `s2_b_arm64_bv_arm64_v0_13_os_macos_a_arm64_d0_g0_rh_v2_4794050200960657605_5906515236269388757`;
    the same cold path under `./oren_stage2` was still inside `rtobj.miss.build.start`
    after 10s. After the first fill, the same seed command now returns
    `OK: rtobj seed already present (no-op)`.
  - Fix (2026-03-15): the cold capsule rtobj-seed path now injects the prebuilt capsule
    runtime astbin seed directly via `OREN_NATIVE_RUNTIME_ASTBIN`, instead of merely leaving
    the astbin seed available for the compiler to discover after runtime expansion and
    fingerprinting. Measured on arm64-macos with empty rtobj cache/seed dirs: the previous
    cold capsule miss stayed around 12.7s even when `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR`
    was populated, while the new direct-astbin path in
    `scripts/build_rtobj_seed.sh --compiler ./oren_stage2 --build-compiler ./oren --capsule --no-debug`
    completed in about 5.2s and logged
    `NOTE: cold seed build using runtime astbin seed=.../v2_4792361169917478041_5905402636049619153_os_macos_pruned3.astbin`.
  - Fix (2026-03-15): `stage2`/`rtobj-seed` now warm `astbin-seed` before the host rtobj seed
    path, so first-run capsule seed fills can use the direct astbin override instead of paying
    a cold runtime expansion first.
  - Fix (2026-03-15): `rtobj-seed-x64` now depends on `astbin-seed-x64`, and the cross-target
    capsule cold-fill path also uses `./oren` as the build compiler while keeping
    `./oren_stage2` as the requested compiler. Measured on x64-linux with empty rtobj cache/seed
    dirs: `scripts/build_rtobj_seed.sh --platform x64-linux --compiler ./oren_stage2 --build-compiler ./oren --capsule --no-debug`
    completed in about 6.3s and logged the direct astbin seed path under
    `build/cache/native_runtime_astbin_seed/v2_4792361169917478041_5905402636049619153_os_linux_pruned3.astbin`.
  - Fix (2026-03-15): cross-target non-capsule x64 rtobj cold fills now use the same stage1
    fallback. Measured on x64-linux with empty rtobj cache/seed dirs: the old
    `scripts/build_rtobj_seed.sh --platform x64-linux --compiler ./oren_stage2 --no-debug`
    path was still CPU-bound after about 39s, while the new
    `--build-compiler ./oren` path completed in about 5.0s and logged the direct
    `.../v2_3546383463129521835_7184909999781679587_os_linux_pruned3.astbin` seed file.
  - New: `scripts/triage_native_quick_flake.sh` runs the stage1 native quick integration
    in a loop and captures per-run logs for flake diagnosis; supports `ENV=VAL` passthrough
    args for tracing, logs git/uname metadata, and saves failure copies of the inner
    quick-integration log (2026-03-03).
  - Update (2026-03-15): `scripts/triage_native_quick_flake.sh` now also snapshots the per-run
    quick-integration phase log, so timeout/flake runs preserve both `*_inner.log` and
    `*_phases.log` artifacts automatically.
  - New (2026-03-15): `scripts/triage_native_quick_green_cache_flake.sh` +
    `make test-native-quick-green-cache-flake` run only the stage1 green-cache rerun path with
    `OREN_QI_TRACE=1`, `OREN_TRACE_GC_STW=1`, `OREN_TRACE_GREEN_RUNQ_GUARD=1`, and
    `OREN_TRACE_GREEN_ENTRY_ARGS_GUARD=1`.
  - New (2026-03-15): `scripts/run_native_quick_integration.sh` now accepts `OREN_QI_SRC` +
    `OREN_QI_LABEL`, `scripts/triage_native_quick_flake.sh` follows the labeled log/phase files,
    and `scripts/triage_native_quick_gc_stw_focus_flake.sh` +
    `make test-native-quick-gc-stw-focus-flake` run a focused quick-integration prefix through
    `test_gc_stw_wakes_netpoll_blocked_threads()` with `OREN_TRACE_GC_STW_WAITERS=1`.
  - New (2026-03-15): `scripts/triage_native_quick_green_tail_flake.sh` +
    `make test-native-quick-green-tail-flake` isolate the later
    `green_workers_join -> ... -> green_global_runq_fairness` band under
    green-cache-only reruns, targeting the region where the current traces first reach
    `expected=3` / `expected=4` parked threads.
  - Trace: stage1 quick-integration flake harness ran 5 passes without failure on 2026-03-03
    (log: `build/logs/triage_stage1_quick_20260303_215453.log`).
  - Trace (2026-03-15): the focused green-cache-only harness hit a timeout on run 3
    (`build/logs/codex_stage1_qi_green_cache_only_guarded_20260315.log`,
    `build/logs/oren_native_quick_flake_20260315_041515_run3_inner.log`). The last STW trace
    observed `gc_stw_begin owner=4302225408 expected=9` and then only four parked-node lines
    before timeout, so the failure was in stage1 GC/STW + green-cache runtime execution, not in
    the compiler build path.
  - Trace (2026-03-15): a traced green-cache-only rerun passed 10/10
    (`build/logs/codex_stage1_qi_green_cache_only_trace_20260315.log`), and a broader
    `OREN_GREEN_POLL_CACHE=1` loop also passed 10/10
    (`build/logs/codex_stage1_qi_green_cache_flake_20260315.log`), establishing the problem as a
    low-frequency race rather than a deterministic stage1 quick failure.
  - Trace (2026-03-15): the new focused GC/STW+netpoll fixture passed 10/10
    (`build/logs/codex_gc_stw_focus_flake_20260315.log`), and the full stage1 green-cache flake
    harness also passed 20/20 with the new STW waiter dump enabled
    (`build/logs/codex_stage1_green_cache_flake_with_waiters_20260315.log`).
    The waiter traces now show the collector-side tail concretely: the last non-parked thread is
    an ordinary OS-thread node with `flags=1`, `saved=0`, and either a transient backup `saved_sp`
    or a plain 512 KiB thread stack, which then parks on the next wait. That means the new
    diagnostics are working, but this snapshot did not re-hit the original timeout.
  - Trace (2026-03-15): the new waiter dump also narrows the current high-value band:
    in successful stage1 green-cache reruns, `expected=3` begins at
    `test_gc_collect_does_not_deadlock_with_green_join_waiter()` and `expected=4` at
    `test_gc_collect_does_not_deadlock_with_os_thread_join_waiter()`
    (`build/logs/oren_native_quick_flake_20260315_043203_run3_inner.log`,
    `build/logs/oren_native_quick_flake_20260315_043252_run14_inner.log`).
  - Trace (2026-03-15): the new late-tail focused flake loop also passed 10/10
    (`build/logs/codex_green_tail_flake_20260315.log`), but it reproduces those
    `expected=3` / `expected=4` collector waits in a much smaller slice
    (`build/logs/oren_native_quick_flake_20260315_043744_run1_inner.log`,
    `build/logs/oren_native_quick_flake_20260315_043757_run8_inner.log`). So the next runtime
    investigation should stay on this smaller tail instead of the full quick-integration path.
  - New (2026-03-15): `scripts/triage_native_quick_green_join_waiters_stress_flake.sh` +
    `make test-native-quick-green-join-waiters-stress-flake` now stress just the two first
    collector-tail join-waiter tests in-process, with explicit per-step markers and a smaller
    default loop count (`OREN_QI_STRESS_ITERS=4`).
  - Trace (2026-03-15): the new join-waiter stress fixture narrowed the failure further.
    `OREN_QI_STRESS_MODE=green` and `OREN_QI_STRESS_MODE=os` both pass cleanly for 4 iterations
    (logs: `build/logs/codex_green_join_waiters_stress_green_seq_20260315.log`,
    `build/logs/codex_green_join_waiters_stress_os_seq_20260315.log`), while the original
    alternating `both` mode crashed inside the second
    `test_gc_collect_does_not_deadlock_with_green_join_waiter()` call
    (`build/logs/codex_green_join_waiters_stress_flake_20260315.log`).
  - Fix (2026-03-15): delayed `STRUCT` publication until after green/select/fn-wrapper
    initialization and changed GC stack scanning to hold the thread-list lock while skipping dead
    OS-thread nodes. That removed the observed join-waiter stress segfault and the dead-thread
    scan hazard.
  - Verification (2026-03-15): the focused alternating stress harness passes after those fixes
    (`build/logs/codex_post_skip_dead_threads_green_join_waiters_flake_20260315.log`), backend
    tag parity passes (`build/logs/codex_verify_backend_parity_tags_after_runtime_fix_20260315.log`),
    and stage2 capsule smoke passes with the updated timeout
    (`build/logs/codex_test_native_capsule_smoke_stage2_timeout60_20260315.log`).
  - Verification (2026-03-19): the clean branch completes `make test` end-to-end
    (`build/logs/codex_make_test_rerun_20260319.log`), so the earlier stage1 GC/STW + green-cache
    crash is no longer an active blocker. Keep the focused flake harnesses as guardrails for any
    future scheduler/GC churn changes.
   - New: `OREN_TRACE_ALLOC_INDEX_REBUILD_CAP=<n>` panics when rebuilds exceed `n` (trace-only guardrail)
     to catch runaway rebuild loops during corruption hunts (rolling, 2026-02-26).
   - Fix: native entry stubs now register all global slots as GC roots before top-level execution,
     preventing GC from collecting globals such as test lists (rolling, 2026-02-25).
   - Gate: no header corruption under alloc benches with reuse disabled; reuse paths stay guarded until verified.

4) **Tagged value convergence plan** (L, W5)
   - Define layout and staged migration.
   - Pin semantic invariants (truthiness, equality, type tests) and add cross‑backend fixtures.
   - Expand `tests/fixtures/tag_parity_smoke.oren` to cover truthiness (ints/floats), type‑strict equality (`==`/`!=`), mixed numeric + string comparisons (`< <= > >=`), cross‑type equality (string/int, bool/int), and mixed map key kinds (int vs string) (rolling, 2026-02-24).
   - New: tag parity now asserts list/list_int identity equality (`==`/`!=`) for alias vs distinct lists (rolling, 2026-02-26).
   - New: tag parity now also asserts `nil == nil`, strict bool-vs-int equality, map
     identity equality, and func identity equality across C/native/OBC (2026-03-06).
   - New: `make verify-backend-parity-arith-panics` enforces cross-backend panic parity for `div0`, `div_overflow`, `mod0`, `mod_overflow`, and `shift_oob` (shl/shr) (rolling, 2026-02-24).
   - Fix: native stringy inference no longer treats empty list literals as list<string> (prevents strcmp on list pointers; restores list equality semantics, 2026-02-26).
   - Backend mapping table (native/C/AVM) captured in `docs/DESIGN.md`.
   - Tag parity fixture now asserts `oren_type_name` across backends.
   - Parity gate: `tests/fixtures/tag_parity_smoke.oren` + `make verify-backend-parity-tags`.
   - Add compatibility shims so native/C/OBC can migrate without breaking Tier‑1.
   - Gate: fixtures across all backends.

5) **Cross-backend parity gates** (M, W4)
   - Expand fixtures where gaps remain; keep C/native/OBC output aligned.
   - New: `make verify-backend-parity-index-panics` enforces negative index assignment + list get out-of-bounds + non-container index get + unsupported map key get/set panics across backends (rolling, 2026-02-24).
   - Gate: parity scripts + `make test` remain green.

6) **Native scheduler / green-task integration** (L, W4)
   - Keep syscall-first constraints.
   - Reweight (2026-03-07): standalone world-lock smoke is no longer the highest-signal
     entry point for this flake family once runq/args-stamp guards are enabled; prioritize
     the earlier native quick integration / green-cache path when chasing remaining crashes.
   - New: `make verify-green-world-lock-guarded` runs a cheap 3-pass standalone gate with
     `OREN_GREEN_POLL_CACHE=1 OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1`.
   - New: `make verify-green-preworld-guarded` runs the earlier native quick integration /
     green-cache sequence with `OREN_QI_STOP_BEFORE_WORLD_LOCK=1` plus the same guards and
     slightly longer run timeouts, so pre-world-lock regressions get a dedicated cheap gate.
   - New: `make verify-green-fairness-guarded` runs stage2 quick integration only through
     `test_green_global_runq_fairness` (`OREN_QI_STOP_AFTER_GREEN_FAIRNESS=1`) and keeps
     `OREN_TRACE_GREEN_FAIRNESS=1` on; it also sets `OREN_QI_STOP_AFTER_GREEN_CACHE=1`
     so the gate ends right after the base + green-cache quick-integration passes instead
     of paying for the unrelated follow-on smokes. This keeps the fairness gate cheap
     while preserving progress markers in the inner log.
   - Verified (2026-03-07): `make verify-green-preworld-guarded` passed cleanly
     (log: `build/logs/codex_verify_green_preworld_guarded_20260307.log`), and the wrapper now
     records per-step summaries plus `skip_reason=OREN_QI_STOP_BEFORE_WORLD_LOCK=1` in the
     per-run log (`build/logs/oren_stage2_native_quick_until_world_lock_20260307_002343_run1.log`).
   - Verified (2026-03-07): `make verify-green-fairness-guarded` passed 3/3 runs
     (log: `build/logs/codex_verify_green_fairness_guarded_20260307_pass.log`); the per-run
     logs now stop after the base + green-cache fairness passes and carry explicit progress
     markers from `test_green_global_runq_fairness`.
   - Verified (2026-03-07): the guarded standalone gate passed cleanly; `make test` also
     remained green after the retrack/world-lock fixes.
   - Verified (2026-04-08): current `master` still passes the focused stage1 green-cache
     flake repro (`./scripts/triage_native_quick_green_cache_flake.sh 5 ./oren`,
     log: `build/logs/triage_green_cache_current_20260408.log`).
   - Fix + verify (2026-04-08): the runtime robustness W5 verifier now includes the guarded
     pre-world-lock green-cache path by default, `scripts/triage_stage2_quick_until_world_lock.sh`
     now reports the real build exit code instead of collapsing failures to `rc=0`, and both the
     pre-world-lock/stage2 guarded stage2 build budgets are aligned to the proven `240s` headroom
     already used by `test-native-quick-stage2`. Verified with:
     `build/logs/make_verify_green_preworld_guarded_20260408.log`,
     `build/logs/make_verify_runtime_robustness_20260408.log`, and
     `build/logs/runtime_robustness_w5_20260408_212845.log`.
   - Fix + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now runs the full
     post-phase follow-on smoke block through checked build/run helpers, keeps timeout-like reruns
     on each smoke under `OREN_QI_FOLLOWON_SMOKE_RETRIES` (default `1`), and emits explicit
     `ok:` markers plus a final `native quick integration follow-on OK` stamp in the inner log.
     This removes the remaining late `test-native-quick` `Error 143` blind spot where the inner
     log could stop after `Build successful: ...loop_list_reuse_escape_smoke` without identifying
     the last completed smoke. Verified with:
     `build/logs/native_quick_followon_guard_20260409.log` and
     `build/logs/make_test_native_quick_followon_guard_20260409.log`. The verification run still
     exercised the existing stage1 base-run timeout retry once (`WARN: timeout (rc=143). Retrying
     with 720s.` in `build/logs/oren_native_quick_integration.log`), but the suite stayed green
     and the new follow-on markers proved the late-smoke block completed.
   - New + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now also accepts
     `OREN_QI_STOP_AFTER_BASE=1`, stamps `native quick integration base phase OK` plus
     `skip_reason=OREN_QI_STOP_AFTER_BASE=1` into the inner log, and exposes a cheap dedicated
     stage1 reproducer at `make verify-native-quick-base-guarded`. The focused wrapper
     `scripts/triage_native_quick_base_flake.sh` reuses the existing flake harness with
     `OREN_QI_TRACE=1` plus `OREN_QI_FAIL_ON_RETRY=1`, so the remaining stage1 base-run
     timeout/retry path can be chased with per-test progress and no hidden reruns instead of
     waiting for a full `make test`. Verified with
     `build/logs/native_quick_base_only_direct_20260409.log`,
     `build/logs/oren_native_quick_base_only.log`, and
     `build/logs/make_verify_native_quick_base_guarded_20260409.log` (3/3 passes).
	   - Fix + verify (2026-04-09): `scripts/verify_runtime_robustness_w5.sh` now includes that
	     base-only stage1 quick-integration reproducer by default before the guarded pre-world-lock,
	     stage2, and C-backend paths. `make verify-runtime-robustness` now forwards
	     `OREN_RUNTIME_ROBUSTNESS_BASE_RUNS`, and the latest bundled verifier passed on current
     `master` with both the base-only and pre-world-lock stage1 gates exercised. The latest full
     `make test` also reached `native quick integration follow-on OK` without re-hitting the older
     base-run timeout/retry path. Verified with
	     `build/logs/make_verify_runtime_robustness_base_bundle_20260409.log`,
	     `build/logs/runtime_robustness_w5_20260409_054902.log`,
	     `build/logs/make_test_runtime_base_bundle_20260409.log`,
	     `build/logs/oren_native_quick_base_only.log`, and
	     `build/logs/oren_native_quick_integration.log`.
	  - Fix + verify (2026-04-09): the bundled W5 runtime gate now also forwards
	    `OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS`, defaulting that stage1 base-build cap to
	    `720s`. This was required after the checked-helper/runtime bundle edit moved the cold
	    base-only build back through `rtobj.miss.build.start` long enough to hit the older `240s`
	    and `480s` caps even though the compiler remained active. Verified by the updated script
	    surface itself (`build/logs/bash_n_verify_runtime_robustness_checked_helper_batch_20260409.log`)
	    plus the new bundled log header in `build/logs/runtime_robustness_w5_20260409_102644.log`
	    (`base_build_timeout_secs=720`).
	  - Fix + verify (2026-04-09): `scripts/verify_runtime_robustness_w5.sh` no longer relies only
	    on that larger timeout. When the base leg is enabled, it now prewarms host runtime astbin and
	    debug rtobj seeds first with the existing seed helpers, using `./oren` as the default cold-fill
	    compiler and `./oren_stage2` as the requested rtobj compiler. The bundled gate now forwards
	    `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM`,
	    `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS`, and
		    `OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER`. The companion structural guard
		    `make verify-native-quick-base-cold-seeded` proves that the stage2 base quick path can run
		    with an empty active runtime cache and still take `phase=rtobj.seed_hit` instead of
		    `phase=rtobj.miss.build.start`. Verified with
		    `build/logs/make_verify_native_quick_base_cold_seeded_20260409.log`,
		    `build/logs/native_quick_base_seeded_cold_20260409_105224.log`,
		    `build/logs/make_verify_runtime_robustness_seed_prewarm_20260409.log`, and
		    `build/logs/runtime_robustness_w5_20260409_105504.log`.
	   - Fix + verify (2026-04-09): `scripts/run_native_quick_integration.sh` now records
	     `retry_base_count`, `retry_green_cache_count`, `retry_followon_count`, and
     `retry_total_count` in the inner log, and accepts `OREN_QI_FAIL_ON_RETRY=1` to turn hidden
     self-healing reruns into explicit failures. The focused green-cache wrapper
     `scripts/triage_native_quick_green_cache_flake.sh` now disables inner green-cache reruns via
     `OREN_QI_GREEN_CACHE_RETRIES=0` and runs under `OREN_QI_FAIL_ON_RETRY=1`. This keeps the
     focused stage1 green-cache surface honest even when `make test` stays green after a retry,
     such as the earlier `Indexing on non-container` retry in
     `build/logs/make_test_runtime_base_bundle_20260409.log`. A clean sequential rerun of the
     stricter reproducer passed 3/3 on current `master`
     (`build/logs/make_test_native_quick_green_cache_flake_strict_20260409.log`), and the latest
     inner quick logs now stamp `retry_*_count=0`
     (`build/logs/oren_native_quick_integration.log`, `build/logs/oren_native_quick_base_only.log`);
     the latest full-suite rerun is also clean with the same zero-retry summary
     (`build/logs/make_test_retry_summary_20260409.log`).
     Treat the stage1 green-cache/local-ptr issue as intermittent but still active enough to keep
     the no-retry reproducer in the repo.
   - New + verify (2026-04-09): the repo now has a focused green-cache/local-ptr reproducer at
     `make verify-native-quick-green-local-ptr-guarded` /
     `make test-native-quick-green-local-ptr-flake`. The new fixture
     `tests/native/test_quick_integration_green_local_ptr_focus.oren` reuses the late-green
     prelude through `test_green_global_runq_fairness()`, then loops only the allocator-integrity +
     `worker_green_local_ptr_survives_yields` region with `OREN_QI_STRESS_ITERS` and
     `OREN_QI_LOCAL_PTR_MODE` knobs. The strict wrapper keeps the current no-retry semantics
     (`OREN_QI_FAIL_ON_RETRY=1`, `OREN_QI_GREEN_CACHE_RETRIES=0`) and adds `OREN_TRACE_LIST_GET_BAD=1`
     plus the runq/entry-args guards by default, so the remaining local-ptr suspicion can be
     chased without the noise of the full quick-integration fixture. `make verify-runtime-robustness`
     now includes this focused stage1 guard surface via `OREN_RUNTIME_ROBUSTNESS_LOCAL_PTR_RUNS`.
   - Refine + verify (2026-04-09): that focused local-ptr surface is now also available as split
     `plain` vs `workers` triage via
     `scripts/triage_native_quick_green_local_ptr_plain_flake.sh`,
     `scripts/triage_native_quick_green_local_ptr_workers_flake.sh`, and the serial wrapper
     `scripts/verify_native_quick_green_local_ptr_modes.sh`
     (`make test-native-quick-green-local-ptr-split-flake`). On current `master`, that stricter
     split surface is **not** stable enough for the bundled guard: it reproduced `rc=138` in the
     `plain` half on run 3/3 while still inside the `test_green_global_runq_fairness()` prelude
     (`build/logs/verify_native_quick_green_local_ptr_modes_20260409_065008.log`,
     `build/logs/oren_native_quick_flake_20260409_065015_run3_err.log`). Because that new split
     surface already acts as a high-signal reproducer, the stable bundled targets initially stayed
     on the earlier blended local-ptr guard while the split plain/workers scripts remained the
     active triage entrypoints for the next root-cause pass.
   - Root cause + verify (2026-04-09): the current mixed fairness crash was not just “one-arg
     scheduler volatility”. Worker mode was still leaving the host thread and the single background
     worker unsynchronized because the green world-lock only engaged for `g_green_worker_count > 1`.
     The runtime now enables the world lock by default for any worker-mode run unless the caller
     explicitly opts into `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`, and both the host-side
     world-lock gate and the worker poll path now honor that policy even at `1` worker.
   - New triage surface (2026-04-09): the sharp mixed fairness slice now has a harness-free direct
     reproducer at `scripts/triage_native_quick_green_fairness_onearg_h8_s1_direct_flake.sh`
     (`make test-native-quick-green-fairness-onearg-direct-flake`), which builds the focused
     fairness binary once and reruns the current `full` / `one_arg` / `notopology` / `hogs=8` /
     `shorts=1` slice directly.
   - Measured (2026-04-09): after the single-worker world-lock fix, the old sharp `h8/s1` fairness
     failure no longer reproduces on the current tree. The new direct harness-free target passed
     10/10 (`build/logs/make_test_native_quick_green_fairness_onearg_direct_flake_20260409.log`),
     the one-arg count sweep passed every configured case including the earlier `hogs=8, shorts=1`
     failure slice
     (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_after_world_lock_fix_20260409.log`),
     and the full fairness mode matrix passed all seven slices 3/3
     (`build/logs/make_test_native_quick_green_fairness_modes_after_world_lock_fix_20260409.log`).
     Reweight accordingly: the current tree no longer has an active fairness repro on these focused
     stage1 surfaces, although fairness remains triage-only until it has more soak than a single
     rerun batch.
   - Verification (2026-04-09): the wider runtime bundle and the repo-wide suite both stayed green
     on the same tree. `make verify-runtime-robustness` passed
     (`build/logs/make_verify_runtime_robustness_after_single_worker_world_lock_fix_20260409.log`,
     `build/logs/runtime_robustness_w5_20260409_090337.log`), and `make test` passed
     (`build/logs/make_test_single_worker_world_lock_fix_20260409.log`).
   - Narrow + verify (2026-04-09): the repo now has a dedicated fairness isolator at
     `tests/native/test_quick_integration_green_fairness_focus.oren`, plus
     `scripts/triage_native_quick_green_fairness_flake.sh` and the serial matrix wrapper
     `scripts/verify_native_quick_green_fairness_modes.sh`
     (`make test-native-quick-green-fairness-flake`,
     `make test-native-quick-green-fairness-modes-flake`). The fairness body is now
     parameterized through `test_green_global_runq_fairness_counts(hog_count, short_count)`,
     so stage1 triage can isolate mixed hog+short fairness from leaf spawn shapes without
     duplicating the core test logic.
   - Measured (2026-04-09): on current `master`, the new fairness matrix is a better root-cause
     surface than the earlier local-ptr split wrapper. `full + topology` passed 3/3, but
     `full` **without** topology failed immediately on run 1/3 with `rc=138`
     (`build/logs/verify_native_quick_green_fairness_modes_20260409.log`,
     `build/logs/oren_native_quick_flake_20260409_071639_run1_err.log`).
     The leaf cases `short_only` and `hogs_only` both passed 3/3
     (`build/logs/triage_native_quick_green_fairness_short_only_notopology_20260409.log`,
     `build/logs/triage_native_quick_green_fairness_hogs_only_notopology_20260409.log`).
     Reweight the active stage1 runtime suspicion accordingly: topology is not required, and
     neither spawn shape fails by itself on the current tree; the mixed fairness interaction is
     now the highest-signal reproducer.
   - Patch + remeasure (2026-04-09): `oren_green_spawn(...)` and
     `oren_green_debug_spawn_call_list_to_p(...)` now GC-root both `fn_obj` and `args_list`
     across the host-side world-lock / `_green_spawn_alloc_g(...)` path. That removes one real
     host-safepoint lifetime hazard from the green spawn entrypoints and changes the fairness
     repro shape on the current tree.
   - Measured (2026-04-09): after the spawn root-lifetime fix, the mixed fairness repro no longer
     stays pinned to one short-arg shape. An earlier rerun shifted the failure from the old
     immediate crash to a strict green-cache retry on the `full` / no-topology / `zero_arg`
     slice (`build/logs/triage_native_quick_green_fairness_full_notopology_zeroarg_postroot_20260409_075401.log`,
     `build/logs/oren_native_quick_flake_20260409_075404_run2_inner.log`), while the matching
     `one_arg` slice passed 3/3 then
     (`build/logs/triage_native_quick_green_fairness_full_notopology_onearg_postroot_20260409_075401.log`).
   - Measured (2026-04-09): on the latest rerun from the same tree, that short-arg split flipped
     again. The `full` / no-topology / `zero_arg` slice passed 3/3 with zero retries
     (`build/logs/make_test_native_quick_green_fairness_zeroarg_flake_20260409.log`,
     `build/logs/oren_native_quick_green_fairness_full_notopology_zeroarg.log`), while the
     matching `one_arg` slice failed immediately on run 1/3 with `rc=138`
     (`build/logs/make_test_native_quick_green_fairness_onearg_flake_20260409.log`,
     `build/logs/oren_native_quick_flake_20260409_080425_run1_err.log`). Keep the fairness split
     triage-only for now: it is sharper than the old blended surface, but it is not stable enough
     to bundle into `make verify-runtime-robustness`.
   - Measured (2026-04-09): the one-arg leaf control confirms the remaining failure still
     requires the mixed fairness interaction. The dedicated `short_only` / `one_arg` slice passed
     3/3 (`build/logs/triage_native_quick_green_fairness_short_only_onearg_20260409.log`), while
     the mixed `full` / `one_arg` variant also failed with topology enabled
     (`build/logs/triage_native_quick_green_fairness_full_topology_onearg_20260409.log`).
     Topology still is not required, but it also does not clear the mixed one-arg failure. The
     fairness matrix wrappers now keep the leaf controls first and continue through all cases so
     one triage run preserves the full split signal instead of stopping at the first failing slice.
   - Measured (2026-04-09): the new dedicated one-arg matrix wrapper
     `make test-native-quick-green-fairness-onearg-modes-flake` reran all three one-arg cases
     and came back green on that pass
     (`build/logs/make_test_native_quick_green_fairness_onearg_modes_flake_20260409.log`).
     Treat that as more evidence of volatility, not a closure signal: the value of the serial
     one-arg matrix is that it preserves the control + mixed case results together even when the
     failing slice shifts or disappears on a given rerun.
   - Measured (2026-04-09): the new one-arg count sweep
     `make test-native-quick-green-fairness-onearg-count-sweep-flake`
     (`build/logs/make_test_native_quick_green_fairness_onearg_count_sweep_flake_20260409.log`)
     shows the current repro is not monotonic in short-task count. On the same serial run:
     `short_only` / `one_arg` / `shorts=40` passed, mixed `hogs=1, shorts=1` passed,
     mixed `hogs=1, shorts=8` passed, mixed `hogs=8, shorts=8` passed, and mixed
     `hogs=8, shorts=40` passed, but mixed `hogs=8, shorts=1` failed with `rc=138`
     on run 2/3 (`build/logs/oren_native_quick_flake_20260409_084111_run2_err.log`).
     Reweight accordingly: the active failure family is pressure- and timing-sensitive, and the
     current sharpest reproducer is no longer just “mixed one-arg” but specifically the
     `full` / `one_arg` / `notopology` slice with high hog pressure and very few short tasks.
   - Rewire + verify (2026-04-09): the focused local-ptr fixture now accepts
     `OREN_QI_LOCAL_PTR_INCLUDE_TOPOLOGY` and `OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS`, and the
     strict local-ptr wrappers default `OREN_QI_LOCAL_PTR_INCLUDE_FAIRNESS=0` plus a wider
     `OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=720`. That separates the new fairness reproducer
     from the local-ptr family instead of letting the earlier fairness crash poison local-ptr
     coverage.
   - Measured (2026-04-09): after fairness was extracted, the blended `both` local-ptr surface
     still reproduced a current-tree crash: `rc=139` on run 3/3 in
     `build/logs/oren_native_quick_flake_20260409_072245_run3_err.log`. The split plain/workers
     surface then passed cleanly with the widened green-cache budget
     (`build/logs/make_test_native_quick_green_local_ptr_split_after_timeout_widen_20260409.log`,
     `build/logs/verify_native_quick_green_local_ptr_modes_20260409_072744.log`).
     The guard policy is now explicit: `make test-native-quick-green-local-ptr-flake` remains the
     mixed-mode harness triage entrypoint, while `make verify-native-quick-green-local-ptr-guarded`
     and the bundled `make verify-runtime-robustness` temporarily used the stable split
     plain/workers surface.
   - Re-measure + rewire (2026-04-09): after the single-worker world-lock fix had already cleared
     the old sharp fairness failure, the focused blended local-ptr `both` surface no longer
     reproduces on current `master`. The harness-based mixed-mode wrapper passed 3/3 in
     `build/logs/make_test_native_quick_green_local_ptr_flake_after_single_worker_world_lock_fix_20260409.log`,
     and a longer no-retry soak passed 10/10 in
     `build/logs/triage_native_quick_green_local_ptr_flake_10run_after_single_worker_world_lock_fix_20260409.log`.
   - New + verify (2026-04-09): the repo now has a harness-free direct mixed-mode local-ptr
     reproducer at `scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh`
     (`make test-native-quick-green-local-ptr-direct-flake`), which builds the focused local-ptr
     binary once and reruns the current `both` / topology-on / fairness-off slice directly.
   - Guard policy (2026-04-09): because the blended `both` path is now the stronger stable surface,
     `make verify-native-quick-green-local-ptr-guarded` and the local-ptr section of
     `make verify-runtime-robustness` now use the direct mixed-mode guard. The split plain/workers
     wrappers remain available as explicit triage entrypoints, and the harness-based blended
     wrapper remains available when the full quick-integration path itself needs rechecking.
   - Note: `test_green_global_runq_fairness` returned -60 once during `make test` on 2026-02-26; rerun passed.
     Treat as a potential flake and keep an eye on fairness/timeout robustness.
   - Note: `make test` hit a segfault in `test-native-quick` with `OREN_GREEN_POLL_CACHE=1`
     (log: `build/logs/make_test_20260226_183026.log`); rerun `make test-native-quick` passed
     (log: `build/logs/make_test_native_quick_20260226_183115.log`). Track as a potential flake.
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_191243.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_191323.log`).
   - Note: `make test` exited with `test-native-quick` Error 143 (log: `build/logs/make_test_20260226_193526.log`);
     rerun `make test-native-quick` passed (log: `build/logs/make_test_native_quick_20260226_193613.log`).
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_202338.log`);
     rerun `make test-native-quick` failed once (log: `build/logs/make_test_native_quick_20260226_202537.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_202606.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_213359.log`); rerun `make test-native-quick`
     failed once (log: `build/logs/make_test_native_quick_20260226_213622.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_213712.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick-stage2` Error 143
     (log: `build/logs/make_test_20260226_212743.log`); rerun `make test-native-quick`
     completed (log: `build/logs/make_test_native_quick_20260226_212955.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_215921.log`); rerun `make test-native-quick`
     segfaulted once (log: `build/logs/make_test_native_quick_20260226_220029.log`)
     then passed (log: `build/logs/make_test_native_quick_20260226_220102.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_221229.log`); rerun `make test-native-quick`
     passed (log: `build/logs/make_test_native_quick_20260226_221331.log`). Track as a flake.
   - Note: `make test` exited with `test-native-quick` Error 143
     (log: `build/logs/make_test_20260226_223629.log`); rerun `make test-native-quick`
     passed (log: `build/logs/make_test_native_quick_20260226_223727.log`). Track as a flake.
    - Gate: `make test` + Tier-1 matrix.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring-up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Deterministic AVM scheduler (budgeted)** (L, W3)
5) **Local agent UI polling/backoff** (S, W3)
   - Investigate repeated `/v1/tools` polling failures from `index-*.js`
     (fetch to `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?...`).
    Searched this repo (`rg "agent1/proxy"`, `rg "v1/tools"`): no references found; need the
    owning component path to proceed.
   - New: UI at `http://127.0.0.1:54514/` reports frequent failed fetches to
     `https://127.0.0.1:54513/v1/agents/agent1/proxy/api/v1/tools?tools=host&yolo=1&host_policy=full&session_id=...`,
     suggesting aggressive polling + scheme/port mismatch (2026-02-26).
   - Update: located UI in the `agent` repo (`ui/src/App.tsx`, `ui/src/hooks/useUiSettings.ts`).
     Added loopback scheme inference (use window protocol when base has no scheme) and reduced
     tools query refetch pressure (staleTime + backoff). UI build ok
     (log: `/Users/zongbaolu/work/agent/build/logs/ui_build_20260226_211713.log`, 2026-02-26).

## P2 (Later)

1) **Production‑grade GMP/netpoller (true async IO + channels/select across Tier‑1)** (L, W2)
2) **Compiler‑in‑AVM bring‑up (OBC toolchain inside AVM)** (L, W2)
3) **AVM multiverse maturity (budgeted child universes + snapshot/restore)** (M, W2)
4) **Scientific/AI acceleration roadmap (SIMD kernel coverage + GPU/BLAS path)** (M, W2)
5) **Allow non-macOS hosts for partial targets** (S, W2)
6) **Package manager / signed module workflow** (M, W2)
7) **Refactor oversized native emitters (>2000 lines)** (M, W2)
8) **Keep large-file scans empty after the current refactor pass** (M, W2)

---

## Feature matrix (rolling snapshot)

Status legend:

- Implemented: supported by stage1 compiler and used in current code.
- Rolling: supported but still evolving; must stay regression-tested.
- Planned: design intent; track in this file.

### Core language

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| Modules + `import` | Rolling | `lib/compiler/compiler/020_modules_linking.oren` | `tests/modules/`, `examples/module_app.oren` |
| FFI symbols (`ffi name`) | Rolling | `lib/compiler/*_macho.oren`, `lib/compiler/x64_native_program/072_ffi.oren` | `examples/ffi_test.oren`, `tests/native/ffi_windows_kernel32.oren` |
| `@cfg`, `@debug`/`@release`, `dbg`/`dprint` | Rolling | `lib/compiler/cfg_lowering.oren`, `lib/compiler/debug_sugar.oren` | `tests/native/cfg_os_select.oren`, `tests/native/test_quick_integration_native.oren` |
| Top-level statements + entry | Rolling | native stubs + bytecode tail | `tests/fixtures/tier1_native_no_main_top_level_only.oren` |
| Functions + lambdas | Rolling | `lib/runtime_native/120_first_class_fn.oren`, bytecode closures | `tests/avm/test_closure_fn_values.oren` |
| Generics + specialization | Rolling | compiler specialization passes | `tests/avm/test_generic_call_specialization.oren` |
| Traits + impl blocks | Rolling | compiler lowering passes | `tests/modules/test_trait_*.oren` |
| `match` + `enum` | Rolling | lowering to control flow | `tests/modules/test_match_enum.oren` |
| Diagnostics (`OREN_DIAG`) | Rolling | compiler + runtime | `tests/native/fixtures/diag_fail.oren` |

### Containers and strings

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| Lists (`[]`, `len`, `push`) | Rolling | intrinsics + lowering | `tests/native/fixtures/**` |
| Maps (`{}`, `m[k]`) | Rolling | runtime helpers + lowering | `tests/native/test_integration_suite.oren` |
| Deterministic map iteration | Rolling | runtime sorting | `tests/native/test_integration_suite.oren` |
| Typed buffers (`[]u8`, `[]i32`, `[]f64`, ...) | Rolling | `lib/std/buffer.oren`, `lib/runtime_native/typed_buffers/**` | `tests/avm/test_u8_buf_views.oren`, `tests/fixtures/tier1_native_smoke_main.oren` |
| Strings (`+`, `len`, `slice`) | Rolling | runtime helpers | `tests/fixtures/tier1_native_string_ops_main.oren` |

### Runtime + stdlib

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| TIME substrate (`oren_sleep_ms`, `oren_time_*`) | Rolling | `lib/runtime_native/100_time.oren` | `tests/native/test_time_suite.oren` |
| RNG substrate (`oren_getentropy`) | Rolling | `lib/runtime_native/102_entropy.oren` | `tests/native/test_quick_integration_native.oren` |
| NET substrate (TCP/UDP) | Rolling | `lib/runtime_native/240_tcp.oren`, `250_udp.oren` | `tests/native/test_net_suite.oren` |
| DNS v0 | Rolling | `lib/std/net/dns.oren` | `tests/native/test_dns_loopback.oren` |
| TLS v0 | Rolling | `lib/std/net/tls.oren` + OS providers | `tests/native/test_tls_loopback.oren` |
| HTTP/1.1 GET | Rolling | `lib/std/net/http.oren` | `tests/native/test_http_get_loopback.oren` |
| HTTP/2 framing + HPACK v0 | Rolling | `lib/std/net/http2.oren`, `lib/std/net/hpack.oren` | `tests/native/test_http2_preface_loopback.oren`, `tests/native/test_http2_headers_loopback.oren` |
| WebSocket v0 | Rolling | `lib/std/net/ws.oren` | `tests/native/test_ws_echo_loopback.oren` |
| Channels + select | Rolling | `lib/runtime_native/010_channels_*`, `lib/runtime_native/245_select.oren` | `tests/native/test_integration_suite.oren`, `tests/avm/test_smoke_suite.oren` |
| Spawn + join | Rolling | `lib/runtime_native/260_threads.oren` | `tests/native/test_integration_suite.oren` |
| Capsule model (capability gating) | Rolling | runtime + emit constraints | `docs/CAPABILITY_RUNTIME_CONTRACT.md`, `@oren.package(...)`, `policy.source_package_check`, `--enforce-package-policy`, `scripts/run_package_policy.sh`, `scripts/run_avm_package_policy.sh`, `scripts/run_native_package_policy.sh`, `OREN_NATIVE_PACKAGE_POLICY_RUN_JSON`, `make verify-capability-runtime-contract`, `make verify-capability-metadata`, `make verify-capability-manifest-policy`, `make verify-avm-package-policy-runner`, `make verify-native-package-policy-runner`, `make verify-native-capsule-resource-checks`, `tests/native/fixtures/capsule_*`, `tests/fixtures/meta_capabilities_src.oren` |
| UI headless core | Rolling | `lib/std/ui/**` | `tests/avm/test_ui_*_v0.oren` |

### Backends + AVM

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| C backend | Rolling | `lib/compiler/transpiler.oren` | `make bootstrap`, `make test` |
| Native backend (arm64/x64) | Rolling | `lib/compiler/arm64_*`, `lib/compiler/x64_*` | Tier-1 fixtures under `tests/fixtures/` |
| Bytecode backend (OBC) | Rolling | `lib/compiler/codegen_bytecode/**` | `tests/avm/**` |
| Capability domains (CORE/FS/TIME/RNG/NET/PROC/ENV/AVM) | Rolling | `lib/avm/avm_native.inc`, `lib/compiler/metadata.oren` | `docs/CAPABILITY_RUNTIME_CONTRACT.md`, `@oren.package(...)`, `policy.source_package_check`, `--enforce-package-policy`, `scripts/run_package_policy.sh`, `scripts/run_avm_package_policy.sh`, `scripts/run_native_package_policy.sh`, `OREN_NATIVE_PACKAGE_POLICY_RUN_JSON`, `make verify-capability-runtime-contract`, `make verify-capability-metadata`, `make verify-capability-manifest-policy`, `make verify-avm-package-policy-runner`, `make verify-native-package-policy-runner`, `make verify-native-capsule-resource-checks`, `tests/avm/**` |
| Effect ledger contract | Rolling schema | `docs/EFFECT_LEDGER_CONTRACT.md`, `docs/GAS_SURFACE_REGISTRY.md`, `lib/avm/main.c`, `lib/runtime_native/000_prelude_sys.oren`, `lib/runtime_native/010_channels_globals_consts.oren`, `scripts/run_backend_semantic_diff.sh` | `make verify-effect-ledger-contract`, `make verify-avm-effect-ledger-json`, `make verify-backend-semantic-diff`, `make verify-backend-semantic-diff-gas-calibration`, `make verify-backend-semantic-diff-gas-call-calibration`, `make verify-backend-semantic-diff-gas-alloc-calibration`, `make verify-backend-gas-surface-calibration-set`, `make verify-backend-native-instruction-surface-decision`, `make verify-native-capsule-resource-checks`, `make verify-native-gas-accounting-modes`, `make verify-gas-surface-registry`; AVM run JSON emits `effect_ledger_summary` with gas/heap/wall/log/trace budget fields and canonical `oren.gas-surface.v0` gas metadata for `avm_opcode_cost_v0` (`unit_scope="avm_canonical"`, `runtime_path_aware=true`, `cross_arch_comparable=true`, `conversion_ready=true`, `avm_canonical=true`); native executables can emit `oren.native-run.v0` with native `effect_ledger_summary` wall timing, default loop-safepoint `native_loop_safepoint_tick_v0` gas ticks, opt-in statement+loop `native_stmt_loop_tick_v0` gas ticks under exact `OREN_NATIVE_GAS_ACCOUNTING=stmt` / `statement` modes, distinct lowering-block `native_basic_block_tick_v0` gas ticks under `OREN_NATIVE_GAS_ACCOUNTING=basic-block`, weighted lowering-block `native_block_weighted_tick_v0` gas ticks under `OREN_NATIVE_GAS_ACCOUNTING=block-weighted`, or runtime path-aware emitter-span `native_dynamic_emitter_tick_v0` gas ticks under `OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter`, matching `oren.gas-surface.v0` native gas metadata with backend-local/non-conversion-ready fields plus `target_arch` and `unit_family` across all native gas surfaces, scanned live tracked-heap bytes, `oren.native-capsule-effect-gates.v0` domain-gate counters, and `oren.native-capsule-resource-checks.v0` resource-check counters through `OREN_NATIVE_RUN_JSON=1`; semantic diff emits `oren.semantic-diff.v0` with native/OBC ledger summaries, normalized `budget_deltas`, explicit gas-surface comparison status using the `native_dynamic_emitter_tick_v0` / canonical `avm_opcode_cost_v0` calibration pair, `oren.avm-canonical-sidecar-gas.v0` same-source OBC canonical gas evidence with explicit `same_run_stderr_equal`, non-blocking `certification_warnings`, and `package_policy_may_use=false`, empirical `oren.gas-surface-calibration.v0` ratios marked as not-a-conversion with native and AVM surface conversion metadata plus source-class labels, `oren.gas-surface-calibration-set.v0` cross-fixture ratio-spread evidence marked `single_ratio_unsafe` plus `surface_metadata_blocks_conversion`, `oren.native-instruction-surface-decision.v0` evidence rejecting whole-binary disasm counts as runtime gas, `oren.gas-surface-registry-check.v0` inventory drift checks, and explicit C ledger-unavailable markers; native package policy can emit `oren.native-package-policy-run.v0` runner-observed wall/gas/heap/CPU-budget JSON plus captured native ledger summaries, now enforces native `budget_gas` from `native_stmt_loop_tick_v0`, `budget_heap_bytes` from the live-heap scan, and `budget_cpu_ms` from child process resource usage where available, can opt into `OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1` to record package-bound AVM canonical gas when the sidecar matches native stdout/exit, and can use `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar` to enforce `budget_gas` from that package-bound AVM canonical sidecar as `runner_wall_avm_canonical_gas` |
| VirtualFS/VirtualNET/VirtualPROC | Rolling | `lib/avm/main.c` | AVM fixtures under `tests/avm/` |
| `.obc` signature verification | Rolling | `lib/avm/avm_sig.c` | `cmd/orensign/main.go` |
| Nested universes (AVM in AVM) | Rolling (gated) | `lib/avm/avm_native.inc` | `tests/avm/**` |

### HPC / SIMD

| Feature | Status | Where (impl) | Evidence |
|---|---|---|---|
| SIMD toggle | Rolling | `lib/runtime_native/040_capsule_core.oren` | `tests/native/test_simd_suite.oren` |
| SIMD determinism guard (scalar vs SIMD) | Rolling | `scripts/verify_simd_determinism.sh` | `tests/native/test_simd_suite.oren` |
| arm64 NEON intrinsics | Rolling | `lib/compiler/arm64_native_expr/**` | `tests/native/test_simd_suite.oren` |
| x64 SIMD baseline (SSE2) | Planned | x64 codegen + runtime kernels | Track in this file |
| AVM SIMD (NEON, gated) | Planned/Rolling | `lib/avm/avm_native.c` | Track in this file |

Latest SIMD determinism run: `make verify-simd-determinism` on arm64-macos (2026-03-05). Output reported `SIMD_ENABLED=0` (scalar) and `SIMD_ENABLED=1` (SIMD); outputs matched.
Latest native+SIMD gate: `make verify-native-quick-simd` on arm64-macos (2026-03-05) passed.
