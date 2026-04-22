# Yield / Coroutine Lowering Notes (2026-04-22)

This note records the current `yield` implementation boundary after the shared-front-end syntax and
backend-shared value-helper slices landed.

## Current shipped state

- Bare statement `yield` is now shared-front-end sugar that lowers directly to `oren_yield_stmt()`.
- `yield <value>` and expression/result-position `yield` now lower to `oren_yield_value(v)`.
- The shipped value contract is intentionally local and backend-shared:
  - `yield` statement resumes as `nil`
  - `(yield)` resumes as `nil`
  - `(yield expr)` resumes as the local value of `expr`
  - there is still no caller-supplied resume value or distinct outward yielded-value channel
- Function metadata now exposes `yield_lowering` with explicit entry/resume state ids for
  source-level bare-`yield` functions, plus conservative `locals_across_yield` frame-slot
  candidates for variables and parameters that stay in scope across a `yield` and are used later.
- Function metadata now also exposes `yield_lowering.lowering_v0`, which marks the first safe
  executable target explicitly: `bare_yield_dispatch_v0`, including top-level bare `yield`,
  multiple top-level yield sites, branch/block/loop-nested bare `yield`, and functions that also
  contain nested function literals, plus live top-level locals/parameters across the suspension
  point.
- For `lowering_v0.ready` functions, metadata now also emits `yield_lowering.prepared_v0`, a
  compiler-generated prepared shape: split-dispatch with explicit entry/resume segments when
  top-level yields exist, or direct-passthrough for ready branch/block control-flow cases.
- `dump linked` now surfaces that same `yield_lowering` object in per-function summaries, and the
  bytecode verifier now extracts `OREN_META` back out of the built `.obc` artifact so the
  compiler-prepared shape is observable both before and after bytecode emission.
- `--strict-yield-lowering-v0` now enforces that gate across the full parsed source program for
  `build`, `meta`, and `dump`. That is intentionally stricter than post-link reachability:
  unreachable top-level yielding functions still block strict builds, and strict mode disables
  artifact-cache restore so cached non-strict outputs cannot bypass the policy.
- The AVM bytecode backend now consumes `prepared_v0` for the exact `lowering_v0.ready` subset and
  lowers it into either an explicit in-function split-dispatch state machine or a direct prepared
  passthrough around `oren_yield_stmt()`. This is the first real execution consumer of the
  coroutine plan, and it now covers the current ready subset: multiple top-level bare `yield`
  sites, plus branch/block/loop-nested bare `yield`, including top-level locals/parameters that
  remain live across them and functions that also contain nested function literals.
- That same ready bare-yield subset is now parity-verified under bytecode, C, and native builds.
  Only AVM currently consumes `prepared_v0` as an explicit lowering path; C/native execute the same
  shipped subset through ordinary `oren_yield_stmt()` calls on their existing runtime surfaces.
- Value-carrying `yield` is now parity-verified under bytecode, C, and native too, but it uses the
  normalized helper path directly instead of `yield_lowering.prepared_v0`. Metadata remains focused
  on the rolling bare-statement coroutine plan rather than pretending to describe generator-like
  value flow it does not yet model.
- `oren meta`, `dump linked`, and embedded OBC metadata now expose that value-yield helper surface
  separately via `contains_yield_value`, `yield_value_count`, `yield_value_sites`, and
  `yield_value_surface`. The encoded surface is intentionally narrow and factual:
  `local_value_resume_v0` with implicit-nil + explicit-value support, but no caller resume value and
  no distinct generator channel. It now also records `consumer_kinds` plus per-point `context`, so
  the metadata shows where resumed local values are consumed without pretending there is already a
  caller-visible resume channel.
- `oren meta`, `dump linked`, and embedded OBC metadata now also expose the explicit caller-visible
  helper separately via `contains_yield_exchange`, `yield_exchange_count`, `yield_exchange_sites`,
  and `yield_exchange_surface`. That surface records the shipped `channel_resume_v0` contract:
  yielded values are observed through explicit `yield_ch`, resumed values are supplied through
  explicit `resume_ch`, and the metadata names those argument positions directly.
- Fresh probe / landing (2026-04-22): that same explicit channel contract now also has shared-front-end
  source syntax:
  - `yield expr in (yield_ch, resume_ch)`
  - `yield in (yield_ch, resume_ch)` for implicit `nil`
  The lowering still routes through `oren_yield_exchange(...)`, but source attribution now stays on
  the original `yield` token and metadata records whether each exchange point came from raw helper
  calls or source syntax via `syntax_kinds`, `exchange_points[*].syntax`, and
  `exchange_points[*].explicit_value`.
- Fresh probe (2026-04-22): strict bytecode/C/native builds also execute a bare `yield` inside a
  nested function-literal body successfully. Parent-function metadata still intentionally ignores
  nested bodies when summarizing `contains_yield` / `yield_stmt_sites`; that probe result is about
  execution support, not about attributing the nested body to the enclosing function.
- Fresh probe (2026-04-22): strict bytecode/C/native builds also execute
  `oren_yield_exchange(yield_ch, resume_ch, v)` successfully on the default native runtime too.
  Native host threads with green runtime already active and no background workers now use
  `oren_yield()` to drive one cooperative green scheduling step, so the verifier no longer needs an
  `OREN_NO_GREEN=1` escape hatch for this helper path.
- Fresh probe (2026-04-22): direct standalone `./scripts/run_native_quick_integration.sh ./oren_stage2`
  no longer needs a manually refreshed runtime seed after runtime-hash changes. The quick script
  now auto-prewarms runtime astbin + rtobj seeds for the current hash before the stage2 build,
  so empty seed dirs do not fall back to a cold self-hosted `rtobj.miss.build.start` path. The
  bundled verifier now proves that path with a dedicated tiny native fixture instead of the full
  quick-integration source, which keeps the structural seed-hit guard cheaper in default `make test`.
  Measured on the primary arm64-macos host from the phase logs:
  - old full quick-integration fixture span: about `151837.9 ms`
  - new tiny autoseed fixture span: about `1073.2 ms`
- Fresh landing (2026-04-22): the first reusable source-level generator abstraction now ships as
  `std:generator`. It does not introduce new compiler-only coroutine objects; instead it
  standardizes a library contract on top of the existing explicit exchange surface:
  - worker shape: `worker(co, args_list)`
  - worker-facing exchange: `yield [expr] in co`
  - handle operations: `start`, `next`, `send`, `is_done`, `return_value`, `collect`
  The cross-backend generator verifier now also runs a raw channel-select smoke first, because that
  surfaced a real missing piece: the C runtime had channels but no shared `oren_select(...)`.
- Fresh landing (2026-04-22): the C runtime now exposes a POSIX `oren_select` /
  `oren_select_recv` surface over the existing pipe-backed channels with the same visible case
  encoding as AVM/native:
  - recv: channel object `[rfd, wfd]` or descriptor `[0, ch]`
  - send: descriptor `[1, ch, value]`
  - success result: `[idx, payload]` where send returns `[idx, 1]`
  - rolling fairness: deterministic round-robin cursor like the native surface
  This closes the concrete C-backend gap that blocked `std:generator` parity on the current POSIX
  host path. It is still not the same thing as a compiler-managed coroutine/generator object model.
- Fresh landing (2026-04-22): `@oren.generator fn ...` now ships as parser-level declaration sugar on
  top of that same contract. The front-end lowers
  `@oren.generator fn counter(seed) { var r = yield (seed + 1); return r + 5 }`
  to:
  - a wrapper function `counter(seed)` that returns `oren_generator_start(worker, [])`
  - a hidden worker body where plain `yield` / `yield expr` are rewritten to
    `yield [expr] in co`
  - metadata markers `is_generator_decl=true` plus `generator_decl_surface` so tool surfaces can
  distinguish the wrapper form from raw helper calls or manual `oren_generator_start(...)`
  That surface is now verified for both top-level and block-local declarations because the parser
  also lowers block-local named functions through the shared first-class callable form
  `fn name(...) { ... } -> var name = fn (...) { ... }`, and the closure analyzers for bytecode, C,
  and native now propagate nested-lambda free vars outward so local generator wrappers can capture
  enclosing locals correctly.
  The same sugar now also applies to function-valued `var` bindings:
  - `@oren.generator var counter = fn(seed) { ... }`
  - `@oren.generator var counter = |seed| { ... }`
  Those bindings lower in place to generator-returning function values and surface through
  metadata/dump/OBC under the variable name instead of being hidden as anonymous wrappers.

- Fresh landing (2026-04-22): the “replace the stdlib-map wrapper” slice is now done. The parser
  injects a hidden generator core into only the modules that need it, exposing:
  - `oren_generator_start(worker, args_list)`
  - `oren_generator_next(gen)`
  - `oren_generator_send(gen, value)`
  - `oren_generator_is_done(gen)`
  - `oren_generator_return_value(gen)`
  - `oren_generator_collect(gen)`
  The handle now reports `oren_type_name(gen) == "generator"` across bytecode, C, and native.
  `std:generator` is now a thin facade over those helpers instead of owning the state layout itself.

- Fresh landing (2026-04-22): the compiler-managed generator substrate is now intentionally opaque at the
  language contract level instead of merely “not documented”. The injected core now targets dedicated
  generator object kinds (`dedicated_generator_object_kind_v1`) and validates both generator handles and
  generator contexts before `next/send/collect` or `yield ... in co` proceed.
  Concretely:
  - the generator substrate no longer depends on map semantics at all; both `generator` handles and
    `generator_context` now live on compiler/runtime-managed dedicated object kinds recognized by
    `oren_type_name(...)`
  - old public lifecycle fields like `yield_ch`, `resume_ch`, `done_ch`, `worker`, `args_list`,
    `task`, `started`, `done`, and `return` are no longer part of the supported generator surface
  - worker bodies should treat `co` purely as a `generator_context`; `yield ... in co` is the only
    supported worker-facing exchange API
  - raw positional slot numbers are now isolated to named injected accessors/constructors inside
    `lib/compiler/parser_parse/005_generator_core.oren`
  - metadata now reports this as `compiler_generator_object_v3` with
    `helper_api=oren_generator_start_v2`, `caller_api=generator_handle_v2`,
    `state_layout=dedicated_generator_object_kind_v1`, `worker_context_type=generator_context`,
    `iter_surface=for_in_v0`, `iter_api=oren_iter_next_v0`, `iter_resume=implicit_nil_v0`, and
    `decl_forms=["named_function_decl","function_valued_var"]`
  - the C runtime cleanup above that substrate is now split too: numeric pointer accessors live in
    `lib/runtime/061_ptr_load_store.inc`, print/iter/string reflection helpers live in
    `lib/runtime/043_print_iter_string.inc`, and both `lib/runtime/010_prelude.inc` and
    `lib/runtime/040_lists_maps.inc` are back under the repo's 2000-line red line
  - the immediate structural cleanup above that substrate is now materially deeper:
    - generator-specific AVM helper logic is split into dedicated includes instead of living only as
      inline islands inside `lib/avm/avm_native.inc` / `lib/avm/avm_state.inc`
    - generator-specific C runtime GC/printing/type-name glue is centralized in
      `lib/runtime/042_generator_objects.inc`
    - `lib/avm/avm_state.inc` is back under the repo’s 2000-line red line after moving its
      record/replay and snapshot/restore clusters into `lib/avm/avm_state_rr.inc` and
      `lib/avm/avm_state_snapshot.inc`
    - `lib/avm/avm_native.inc` is back under the repo’s 2000-line red line too after splitting its
      universe/VFS helper cluster into `lib/avm/avm_native_fs_universe_helpers.inc`, its
      clone/value helper cluster into `lib/avm/avm_native_clone_helpers.inc`, its mid-body
      object/buffer switch islands into `lib/avm/avm_native_object_buffer_cases_a.inc`,
      `lib/avm/avm_native_buffer_cases_b.inc`, `lib/avm/avm_native_buffer_cases_c.inc`, and
      `lib/avm/avm_native_buffer_cases_d.inc`, and its capability-domain dispatcher body into
      `lib/avm/avm_native_capability_domain_fs.inc` and
      `lib/avm/avm_native_capability_domains_misc.inc`
    - `lib/runtime/010_prelude.inc` and `lib/runtime/040_lists_maps.inc` stay back under the red
      line, and the next coupled ARM64 stmt split is landed too:
      `lib/compiler/arm64_native_stmt.oren` is back under the red line, the old list-loop emitter
      body now lives in `lib/compiler/arm64_native_stmt_loops_list_emit_prefix_reduce.oren`,
      `lib/compiler/arm64_native_stmt_loops_list_emit_int_reduce_dot.oren`, and
      `lib/compiler/arm64_native_stmt_loops_list_emit_dot_push.oren`, and the set-lowering tail now
      lives in `lib/compiler/arm64_native_stmt_set.oren`. The remaining oversized debt was then
      fully cleared too:
      `lib/compiler/compiler/040_build_pipeline/010_main.oren` now delegates its
      completion/sym/scan/dump/meta introspection block through
      `lib/compiler/compiler/040_build_pipeline/008_introspection_commands.oren`,
      `lib/avm/main.c` now keeps its effect-ledger/report helper block in
      `lib/avm/avm_main_effect_ledger.inc`, and `tests/native/qi/100_tests_basic.oren` is now a
      thin include facade over four focused shards. The rolling tracked source scan is back under
      the 2000-line threshold across compiler/runtime code and Tier-1 test bundles
  - the default repo verification lane stays green by using the stage1 `./oren` tool path for
    generator finalize `meta` / `dump linked` parity, matching the broader generator surface verifier
  - the remaining stage2 tooling seam above that verifier is now fixed too:
    `dump linked` / `dump graph` / `meta` skip hidden generator-core injection on the
    introspection path, which both cleans the metadata surface and drops
    `./oren_stage2 dump linked tests/fixtures/generator_finalize_surface_v0.oren`
    from about `1.53s` to `0.18s`
  - the adjacent arm64 `list<int>` fill-side shipped-surface decision seam is now closed again too:
    `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR` is back to default-on after the current-tree
    shipped-vs-disabled rerun
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_011353_91759.log`)
    kept the formal decision rule aligned and the shipped default also passed
    `make verify-native-quick`
    (`build/logs/make_verify_native_quick_20260423_011547_default_on_promote_v1.log`)
    plus the full repo lane
    (`build/logs/make_test_20260423_012704_default_on_promote_v2.log`)
  - the narrower arm64 preserved-cursor fill-side follow-up is now promoted too:
    `OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS` ships on by default after the current-tree
    shipped-vs-disabled rerun
    (`build/logs/perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision-20260423_025433_17194.log`)
    kept the decision surface aligned and preferred the shipped default on both fill/share
    (`default_fill_vs_c_vector ~1.7572×` vs disabled `~2.3562×`) and exact `array_sum_int`
    (`default_array_ratio_median ~2.2127×` vs disabled `~2.2219×`), with exact
    `dot_product_int` median lower on the shipped default too
  - emitted-code inspection then found a real correctness seam under that same shipped push family:
    `_arm64_emit_fast_loop_nonneg_linear_to_x0(...)` was reusing `x9` for mul/add/mod immediates
    even though inline GC countdown uses `x9` as the tick register inside
    `fast_list_int_push_while`. The helper now keeps `x9` reserved and uses `x11`/`x10` scratch
    instead, both push emitters now publish `[arm64_loop_range]` traces, and
    `build/logs/verify_native_list_int_fast_lowering_20260423_051622_70950.log` now disassembles
    `array_sum_int`, rejects any hot-loop `x9` use beyond the shipped countdown forms
    (`subs x9, x9, #0x1` / `#0x4`), and requires the four-wide slot-store body to stay present. The
    refreshed shipped-vs-disabled rerun
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_034811_37016.log`)
    still keeps the broad nonnegative-linear branch shipped on, with fill/share strongly preferring
    default (`default_fill_vs_c_vector ~2.4026×` vs disabled `~5.0016×`) and exact medians also
    lower on the shipped default (`array ~2.2189×` vs `~2.2980×`, `dot ~1.5522×` vs `~1.6406×`).
    The widened safety lanes stayed green too:
    `build/logs/make_verify_native_quick_20260423_tick_reg_fix_v1.log` and
    `build/logs/make_test_20260423_tick_reg_fix_v1.log`
  - a new emitted-code probe now keeps that fill-side work grounded in the actual hot loop:
    `make perf-probe-arm64-list-int-fill-hot-loop-disasm` summarizes the shipped
    `fill_list_int` / `array_sum_int` `fast_list_int_push_while` body while excluding the cold GC
    tick side block. The reverted current-tree artifact
    (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_042356_51281.log`)
    shows the shipped loop at `25` total instructions / `17` hot instructions with no
    per-iteration final count/cursor writeback in the hot body. A temporary `% 1000` fuse to
    `udiv; msub` reduced the hot body to `16` instructions in
    (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_041825_49207.log`) but
    still regressed the real shipped decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-decision-20260423_041844_49343.log`),
    so the broad branch keeps the shipped `udiv; mul; sub` remainder path and the remaining
    open surface is the slot-store/arithmetic/safepoint-reset shape, not generic final
    count/cursor writeback
  - that fill-side open surface then turned into the next shipped improvement too. The corrected
    direct Oren-vs-C compare
    (`build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_045541_59142.log`) now reports
    the landed wide body at `35` hot instructions for `4` output elements (`8.75` per element)
    versus the host C four-wide recurrence block `LBB0_15` at `27` instructions for four elements
    (`6.75` per element) plus a `9`-instruction scalar tail in `LBB0_18`. The decision surface for
    that experiment is now closed positive and promoted:
    `build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_045547_59235.log`
    keeps `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4` shipped on by default because the
    promoted tree wins on fill/share (`default_fill_vs_c_vector ~2.2247×` vs disabled `~2.4860×`),
    exact `array_sum_int` (`default_array_ratio_median ~2.1889×` vs `~2.2154×`), and exact
    `dot_product_int` median (`default_dot_ratio_median ~1.7420×` vs `~1.7574×`). That shifts the
    remaining backend work away from “add width” and toward the arithmetic / store / tail /
    safepoint cost inside the now-landed four-wide body
  - the next narrower store-shape follow-up under that shipped four-wide body is now closed
    negative too. A temporary rerun replaced the four scalar stores plus pointer bump with two
    post-index `stp` stores. The emitted loop did improve:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_053204_75573.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_053209_75659.log` show the wide
    main iteration dropping from `35` hot instructions for `4` outputs (`8.75` per element) to
    `32` (`8.00` per element). But the actual shipped-vs-enabled decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-stp-decision-20260423_053014_74064.log`)
    still rejected promotion: fill/share preferred the shipped default
    (`default_fill_vs_c_vector ~2.0548×` vs enabled `~2.1867×`), exact `array_sum_int` median
    also slightly preferred default (`~2.1822×` vs `~2.1860×`), and only exact
    `dot_product_int` median moved toward the pair-store branch
    (`default_dot_ratio_median ~1.7285×` vs enabled `~1.6796×`). That narrows the remaining
    backend work further: the open gap is no longer mainly the slot-store shape, but the carried
    recurrence arithmetic and compare/branch density inside the shipped wide body
  - the next mov-chain follow-up under that same shipped four-wide body is now closed negative too.
    A temporary rerun removed the cloned register chain around the carried values. The emitted loop
    improved again:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_054624_80049.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_054629_80110.log` show the wide
    main iteration dropping to `30` hot instructions for `4` outputs (`7.50` per element). But the
    actual same-tree decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-direct-regs-decision-20260423_054458_78631.log`)
    still rejected promotion: fill/share improved (`default_fill_vs_c_vector ~2.2174×` vs enabled
    `~2.1132×`), but both exact medians regressed (`default_array_ratio_median ~2.2164×` vs
    enabled `~2.2298×`, `default_dot_ratio_median ~1.5550×` vs enabled `~1.6600×`,
    `decision_surface_alignment: disagree`). That narrows the remaining backend work further: the
    open gap is no longer mainly the mov-chain either, but the recurrence arithmetic itself and the
    compare/branch structure inside the shipped wide body
  - the next true four-stream recurrence follow-up under that same shipped four-wide body is now
    also closed negative. A temporary rerun kept four carried lanes live in preserved regs and
    advanced each by a precomputed `4*step mod` delta across main iterations. The emitted loop
    still improved:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_061011_87026.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_061011_87005.log` show the wide
    main iteration dropping to `32` hot instructions for `4` outputs (`8.00` per element). But the
    same emitted-code pass also shows the cold GC-tick side blocks growing from `16` to `24`
    instructions because the helper had to spill and restore four preserved pairs instead of two.
    The actual same-tree decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-multi-stream-decision-20260423_060858_85589.log`)
    still rejected promotion cleanly: fill/share preferred the shipped default
    (`default_fill_vs_c_vector ~2.1459×` vs enabled `~2.1862×`), exact `array_sum_int` median also
    preferred default (`default_array_ratio_median ~2.1979×` vs enabled `~2.2283×`), and exact
    `dot_product_int` median preferred default too (`default_dot_ratio_median ~1.5145×` vs enabled
    `~1.6533×`, `decision_surface_alignment: agree`). That narrows the remaining backend work
    further again: any future multi-stream retry has to avoid paying a wider safepoint spill/reset
    tax at the same time
  - the next branchless wrap-control follow-up under that same shipped four-wide body is now also
    closed negative. A temporary rerun replaced the carried wrap `cmp` / `b.lt` pairs with `sub`
    + `csel` recurrence steps. The emitted loop still improved:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_055647_83223.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_055652_83291.log` show the wide
    main iteration dropping to `31` hot instructions for `4` outputs (`7.75` per element). But the
    actual same-tree decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-csel-decision-20260423_055520_81868.log`)
    still rejected promotion decisively: fill/share preferred the shipped default
    (`default_fill_vs_c_vector ~2.1457×` vs enabled `~3.2438×`), exact `array_sum_int` median also
    preferred default (`default_array_ratio_median ~2.2018×` vs enabled `~2.2386×`), and only
    exact `dot_product_int` median moved toward the branchless path
    (`default_dot_ratio_median ~1.7842×` vs enabled `~1.5692×`,
    `decision_surface_alignment: agree`). That narrows the remaining backend work further again:
    the open gap is no longer mainly the branchy wrap-control form either, but the serial carried
    recurrence itself versus the host C loop's four independent streams
  - the next narrower precise-safepoint-spill follow-up under that same shipped four-wide body is
    now also closed negative. A temporary rerun changed only the inline GC tick helper, replacing
    the conservative two-pair cursor spill with the exact live-pointer spill `[x19]` through
    `stp x19, xzr` / `ldp x19, xzr`. The emitted hot loop did not change:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_062415_90653.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_062415_90632.log` still show
    `35` hot instructions for `4` outputs (`8.75` per element), but the cold GC-tick side blocks
    shrink from `16` instructions on the clean shipped baseline
    (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_061450_87903.log`,
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_061450_87882.log`) to `12`.
    That cleaner side path still does not hold on the actual shipped surface: compared with the
    clean baseline decision probe
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_045547_59235.log`),
    the precise-spill rerun
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision-20260423_062307_89324.log`)
    improves fill/share (`default_fill_vs_c_vector ~2.2247× -> ~2.1355×`) but regresses both exact
    same-tree medians (`default_array_ratio_median ~2.1889× -> ~2.2115×`,
    `default_dot_ratio_median ~1.7420× -> ~1.7738×`). That narrows the remaining backend work
    further again: exact live-pointer conservative spills are cleaner, but not enough to keep as a
    standalone perf move on the shipped tree.
  - the next spill-neutral two-stream recurrence follow-up under that same shipped four-wide body
    is now also closed negative. A temporary rerun kept the shipped safepoint spill width
    unchanged and only split the carried values into two live streams (`x24/x25`) plus a shared
    `2*step mod` delta in `x26`. The emitted loop still improved slightly:
    `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_063816_94224.log` and
    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_063815_94203.log` show the wide
    main iteration dropping from `35` hot instructions for `4` outputs (`8.75` per element) to
    `34` (`8.50` per element), while the cold GC-tick side blocks stay at the shipped `16`. The
    actual same-tree decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-two-stream-decision-20260423_063427_92506.log`)
    still rejected promotion cleanly on every tracked metric: fill/share preferred the shipped
    default (`default_fill_vs_c_vector ~2.1431×` vs enabled `~2.2392×`), exact `array_sum_int`
    median also preferred default (`default_array_ratio_median ~2.2033×` vs enabled `~2.2142×`),
    and exact `dot_product_int` median preferred default too (`default_dot_ratio_median ~1.5928×`
    vs enabled `~1.6949×`, `decision_surface_alignment: agree`). That narrows the remaining backend
    work further again: the open gap is no longer just “multi-stream without a wider safepoint
    spill tax”; even that narrower recurrence split loses to the shipped serial four-wide body.
	  - the explicit push-loop safepoint-frequency follow-up looked promotable, but the actual
	    promoted-default rerun closed it back to probe-only: the candidate rerun on the shipped `4095`
	    tree (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032104_29410.log`)
    aligned in favor of `65535`, but the immediate promoted-default rerun
    (`build/logs/perf-probe-arm64-fast-push-tick-mask-decision-20260423_032751_32000.log`) did not
    hold, flipping fill/share toward the lower masks and exact `array_sum_int` /
    `dot_product_int` medians toward `16383`; `OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK` therefore
    stays shipped at `4095` for now
  - the next runtime constructor micro-hypothesis on that same shipped fill surface is now also
    settled negative: compared with the current baseline
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`,
    fill `per_rep_s ~0.003096`, `fill_vs_c_vector ~2.3103×`), a rerun that gated constructor
    trace/index bookkeeping behind active ctor tracing
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015415_6018.log`) regressed to
    `~0.003145` / `~2.3671×`, and the follow-up that also bypassed the immediate arena retag table
    lookup (`build/logs/perf-probe-list-int-fill-share-decision-20260423_015936_6969.log`)
    regressed again to `~0.003188` / `~2.3970×`
  - the first narrower compiler-side reload/spill trim under that same constructor boundary is now
    settled negative too: compared with the same baseline
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`), a rerun that
    stopped spilling the generic `idx` local on the nonnegative-linear path and tried to keep `i`
    live across the direct arithmetic helper path
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_021057_8800.log`) regressed hard
    to `fill per_rep_s ~0.005534` / `fill_vs_c_vector ~4.2125×`, so the next work should look
    below that narrow `X20` live-range assumption rather than reopening this trim branch
  - the next safepoint-side loop-state trim on that same shipped fill surface is now settled
    negative too: compared with the same baseline
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`), a rerun that
    replaced the generic inline-tick preserved-reg spill set with the narrower explicit-pairs path
    for `fast_list_int_push_while`
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_022302_10735.log`) still
    regressed slightly to `fill per_rep_s ~0.003107` / `fill_vs_c_vector ~2.3697×`, so the next
    work should not reopen that safepoint-pair branch without stronger emitted-code evidence
  - the next reciprocal-fastmod follow-up on that same shipped fill surface is now settled
    negative too: compared with the same baseline
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_011353_91782.log`), a narrower
    rerun hoisted the shared `% 1000` divisor and reciprocal into preheader regs and kept the
    reciprocal lowering only on the shipped nonnegative-linear `fast_list_int_push_while` surface,
    but the exact same-tree probe
    (`build/logs/perf-probe-list-int-fill-share-decision-20260423_024106_13895.log`) still
    regressed hard to `fill per_rep_s ~0.003746` / `fill_vs_c_vector ~2.8408×`
  - emitted-code follow-up confirms that the hoist itself worked mechanically:
    `build/logs/otool_fill_list_int_oren_inspect_fastmod_hoist_full_20260423_v1.log` preloads
    `x24=#1000` and `x25=<reciprocal>` before the hot loop and then uses `umulh` inside the loop,
    so the remaining blocker is now below that earlier “reciprocal literal materialized each
    iteration” explanation

- Fresh landing (2026-04-22): generator handles now participate in generic `for x in iterable`
  sugar too, without changing the public handle layout again. The compiler-generated bridge:
  - recognizes `generator` handles before normal `oren_iter_next(...)` fallback
  - advances them through `oren_generator_next(...)`
  - adapts generator steps to the iteration pair contract `[ok, value]`
  - resumes every step with implicit `nil`
  This means the current surface is good for plain producer-style generators that do not require
  non-`nil` caller input between yields, while `gen.send(...)` remains the richer manual protocol.

- Reverted landing (2026-04-22): attempted richer generator composition through
  `oren_generator_delegate(...)` was temporarily unshipped after stage2 repro reduction exposed a
  self-hosted bytecode compile regression. Facts from the reduced probes were:
  - no-import declaration-only composition compiled under stage2
  - importing `std:generator` in the same module as delegated generator composition triggered the
    stage2 bytecode build regression again, even after removing the worker-style `gen.delegate(...)`
    facade
  - the most reliable reduced shape is now committed and narrower than the original delegation
    attempt: a module that imports `std:generator`, starts an inner generator, and whose worker
    contains any `yield ... in co` currently times out under stage2 after
    `[phase] pass global_dce` and `[trace] link: done`, before bytecode emission
  - the nearby controls still compile:
    - no import + value-resume worker + `oren_generator_start(...)`
    - import + no-yield worker + `gen.start(...)`
  - the blocked fixtures are:
    - `tests/fixtures/generator_import_yield_regression_stmt_v0.oren`
    - `tests/fixtures/generator_import_resume_regression_v0.oren`
    and the nearby controls are:
    - `tests/fixtures/generator_import_resume_control_no_import_v0.oren`
    - `tests/fixtures/generator_import_yield_control_import_no_yield_v0.oren`
    verified by `scripts/probe_generator_import_yield_regression.sh`
  - conditional exclusion of `oren_generator_delegate(...)` from non-using modules was confirmed
    separately through metadata inspection, but that did not remove the import-side compile stall
  - because the surface was not robust under the self-hosted compiler, the public delegation syntax
    and metadata claims were rolled back in this turn
  This was the next real resume/composition task above the shipped `for-in` / `next` / `send`
  surface, but it was intentionally not documented as available until the compiler path was fixed.

- Follow-up fix (2026-04-22): the reduced stage2 bytecode regression above is now fixed.
  Facts from the successful re-run:
  - `tests/fixtures/generator_import_yield_regression_stmt_v0.oren`
    now compiles under `./oren_stage2 build --backend bytecode`
  - `tests/fixtures/generator_import_resume_regression_v0.oren`
    now compiles under `./oren_stage2 build --backend bytecode`
  - the nearby controls still compile, so the committed four-case matrix remains the right guard
  - the fix was a metadata-emitter refactor: `generate_metadata(...)` now assembles the top-level
    JSON through chunked `oren_string_join(...)` output instead of repeated whole-document
    concatenation, which clears the self-hosted stage2 timeout after `global_dce` / `link: done`
  - trace hooks were kept for future compiler debugging:
    - `OREN_TRACE_BUILD_PHASES_PATH` around bytecode build stages
    - `OREN_TRACE_METADATA_FUNCTIONS` around per-function metadata generation
  - `scripts/probe_generator_import_yield_regression.sh` is now a positive guard, and
    `make test` pins it through `verify-generator-import-yield-regression`
  This cleared the compiler blocker for reopening richer generator delegation/resume work.

- Fresh landing (2026-04-22): manual generator delegation is now re-landed on top of the fixed
  stage2 path.
  - the compiler-injected generator core now exposes `oren_generator_delegate(co, inner)`
  - `std:generator` now exposes `delegate(co, inner)` as a thin facade over that helper
  - the first shipped mode was `inline_fresh_handle_v0`
  - the helper validates both `co` and `inner`, inlines a fresh inner generator handle directly into
  the current outer `generator_context`, returns the inner generator’s final return value when
  delegation completes, and rejects partially-started inner handles
  - already-completed inner handles are treated as stable values and return their cached final value
  - this means imported delegated composition is now a real shipped surface again, not only a note:
    explicit workers can compose generators without re-exposing channel fields or depending on map
    semantics
  - the stage2 compile probe now includes delegated imported composition in
    `tests/fixtures/generator_import_delegate_regression_v0.oren`
  - runtime coverage lives in:
    - `tests/fixtures/generator_surface_v0.oren`
    - `tests/modules/test_generator_std.oren`
    - `tests/avm/test_generator_v0.oren`
  - metadata for `@oren.generator` declarations now records the widened manual resume surface as:
    - `resume_surface = "next_send_delegate_step_v1"`
    - `next_api = "oren_generator_next_v2"`
    - `send_api = "oren_generator_send_v2"`
    - `delegate_api = "oren_generator_delegate_v0"`
    - `delegate_step_api = "oren_generator_delegate_step_v1"`
    - `delegate_mode = "inline_fresh_handle_or_started_step_v1"`
  Delegation syntax itself is still not reintroduced in this turn; the shipped surface is helper and
  stdlib based, with the regression floor preserved by the committed stage2 matrix.

- Runtime fix + widened delegation (2026-04-22): partially-started delegation is now shippable too.
  - the native green runtime bug was in host-side `oren_select(...)`: when green was active without
    background workers, the host could block in an external select wait without continuing the
    scheduler, so nested `gen.next(inner)` from inside an active outer generator never let `inner`
    run
  - the native runtime now keeps host-side select cooperative in that mode by polling green work
    between short external waits, which makes the previously blocked reduced case complete
  - the old blocked repro is replaced by a positive verifier:
    - `scripts/verify_generator_nested_green_resume_v0.sh`
    - fixture: `tests/fixtures/generator_nested_green_resume_v0.oren`
  - the verified trace shape now includes:
    - `main:before_next`
    - `outer:start`
    - `outer:before_next`
    - `inner:start`
    - `outer:after_next`
    - `main:after_next`
  - with that seam fixed, the generator core now also exposes:
    - `oren_generator_delegate_step(co, inner, step)`
    - stdlib facade: `std:generator.delegate_step(co, inner, step)`
  - semantics:
    - `delegate(co, inner)` still handles fresh inner generators
    - `delegate_step(co, inner, step)` delegates the remaining sequence from a partially-started
      generator, where `step` is the currently yielded step already observed from `inner`
    - the mode name is now `inline_fresh_handle_or_started_step_v1`
  - the stage2 import/yield matrix now also pins started-step imported composition through
    `tests/fixtures/generator_import_delegate_step_regression_v0.oren`

- Fresh landing (2026-04-22): source-level delegation now ships on top of the helper/runtime seam,
  and plain delegation no longer forces manual step maps for already-started handles.
  - `oren_generator_delegate(co, inner)` now keeps the current yielded step cached on the handle, so
    it can absorb:
    - fresh inner handles
    - already-started handles whose current yielded step is still cached on the handle
    - already-completed handles (stable cached return value)
  - explicit step-driven control is still available through
    `oren_generator_delegate_step(co, inner, step)`
  - new source syntax:
    - explicit workers: `yield from inner in co`
    - `@oren.generator` declarations: `yield from inner`
  - important parser constraint:
    - `from` is contextual after `yield`; it was intentionally *not* added as a reserved keyword,
      because repo/runtime code already uses identifiers named `from`
  - new metadata surface for generator declarations:
    - `version = 14`
    - `resume_surface = "next_send_close_delegate_yield_from_v5"`
    - `delegate_api = "oren_generator_delegate_v1"`
    - `delegate_step_api = "oren_generator_delegate_step_v1"`
    - `delegate_source_syntaxes = ["yield_from_v0", "yield_from_in_context_v0"]`
    - `close_api = "oren_generator_close_v1"`
    - `close_mode = "propagate_active_delegate_chain_detach_live_task_v3"`
    - `delegate_mode = "track_active_chain_inline_fresh_or_cached_started_step_v3"`
  - new positive coverage:
    - runtime/source surface:
      - `tests/fixtures/generator_surface_v0.oren`
      - `tests/modules/test_generator_std.oren`
      - `tests/avm/test_generator_v0.oren`
    - imported stage2 bytecode compile matrix:
      - `tests/fixtures/generator_import_yield_from_regression_v0.oren`
    - negative parser boundary:
      - `tests/fixtures/generator_yield_from_blocked_missing_context_v0.oren`

- Fresh landing (2026-04-22): explicit generator close/finalization now ships on top of the same
  handle/runtime seam.
  - the compiler-injected generator core now also exposes `oren_generator_on_finalize(co, hook)`
  - `std:generator` now exposes `on_finalize(...)` as a thin facade over that helper
  - `oren_generator_on_close(co, hook)` / `std:generator.on_close(...)` remain aliases of the same
    registered hook list
  - the compiler-injected generator core now exposes `oren_generator_close(gen)`
  - `std:generator` now exposes `close(gen)` as a thin facade over that helper
  - current contract:
    - explicit workers register finalization hooks as `gen.on_finalize(co, hook)` /
      `oren_generator_on_finalize(co, hook)`
    - `@oren.generator` declarations register finalization hooks as `gen.on_finalize(hook)` /
      `oren_generator_on_finalize(hook)`
    - source-level finalization syntax now also ships on that same contract:
      - explicit workers: `defer { ... } in co`
      - `@oren.generator` declarations: `defer { ... }`
      - `defer` is contextual and was intentionally not made globally reserved
    - `on_close(...)` remains a source-level alias of the same registration path
    - hooks must be zero-argument callables
    - hooks run in LIFO order
    - hooks now run on both explicit `close()` and natural completion
    - the first hook `err` becomes the sticky terminal generator result, but cleanup still continues
    - already-finished generators preserve and return their cached final value unless a terminal
      finalizer error was recorded
    - unfinished generators first recursively close the currently active delegated child chain, if
      any, then run current-handle finalization hooks, and are then sealed done deterministically at the
      handle surface with `return_value == nil`
    - started generators now detach the live worker handle instead of resuming user code with an
      internal close value; this avoids backend-specific deadlocks when a worker would otherwise
      yield again after `close()`
    - after natural completion with a finalizer error, `next()` / `send()` / `collect()` surface that
      `err`, while `return_value(gen)` still preserves the ordinary cached return value
  - this is intentionally documented as a deterministic handle-sealing contract, not a portable
    hard-kill/finalization guarantee: detached workers may still exist on some substrates until the
    process/runtime exits
  - metadata for `@oren.generator` declarations now records:
    - `version = 18`
    - `resume_surface = "next_send_finalize_defer_close_delegate_yield_from_v7"`
    - `on_finalize_api = "oren_generator_on_finalize_v1"`
    - `on_finalize_mode = "lifo_zero_arg_on_done_or_close_v1"`
    - `on_close_api = "oren_generator_on_close_v1"`
    - `on_close_mode = "alias_of_on_finalize_v1"`
    - `close_api = "oren_generator_close_v1"`
    - `close_mode = "propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5"`
    - `delegate_mode = "track_active_chain_inline_fresh_or_cached_started_step_v3"`
    - `finalize_surface = "generator_finalize_v0"`
    - `finalize_source_syntaxes = ["defer_v0", "defer_in_context_v0", "on_finalize_call_v1", "on_close_call_alias_v1"]`
  - per-function `meta`, `dump linked`, and extracted OBC metadata now also record:
    - `contains_generator_finalize`
    - `generator_finalize_count`
    - `generator_finalize_sites`
    - `generator_finalize_surface`
  - `generator_finalize_surface` currently emits:
    - `version = 1`
    - `surface = "generator_finalize_v0"`
    - `lifecycle = "on_done_or_close_v1"`
    - `hook_arity = "zero_arg"`
    - `syntax_kinds`, `api_kinds`, `consumer_kinds`
    - `finalize_points`
  - new runtime coverage lives in:
    - `tests/fixtures/generator_surface_v0.oren`
    - `tests/modules/test_generator_std.oren`
    - `tests/avm/test_generator_v0.oren`
    - `tests/fixtures/generator_import_close_regression_v0.oren`
    - `tests/fixtures/generator_import_delegate_close_regression_v0.oren`
    - `tests/fixtures/generator_import_on_close_regression_v0.oren`
    - `tests/fixtures/generator_import_on_finalize_regression_v0.oren`
    - `tests/fixtures/generator_import_defer_regression_v0.oren`
    - `tests/fixtures/generator_defer_blocked_missing_context_v0.oren`
    - `tests/fixtures/generator_finalize_surface_v0.oren`
  - the compact cross-surface verifier for that metadata now lives at:
    - `scripts/verify_generator_finalize_surface_v0.sh`
    - wired into `make test` as `verify-generator-finalize-surface-v0`
  - follow-up fix in the same area (2026-04-22): native wrapper discovery now also pre-scans
    nested lambda / generator-worker bodies for named function values before late fnwrap synthesis
    - this closes the previously documented seam where declaration-body `on_close(...)` plus
      `gen.start(named_worker, ...)` followed by `yield from ...` inside the same
      `@oren.generator` declaration could miss `__oren_fnwrap_*` emission on native
    - the reduced import/native proof now builds and runs through
      `tests/fixtures/generator_import_on_close_regression_v0.oren`

- Fresh landing (2026-04-22): generator worker source is now normalized around compiler-managed
  generator context instead of raw channel field spelling. The shared front-end accepts:
  - `yield expr in co`
  - `yield in co`
  and lowers that to `_oren_generator_context_exchange(co, value)`, which validates `co` as a
  `generator_context` and then forwards to the underlying explicit
  `oren_yield_exchange(yield_ch, resume_ch, value)` channel protocol. Metadata now reports that
  distinction through:
  - `yield_exchange_surface.binding_kinds = ["generator_context"]`
  - `yield_exchange_surface.context_arg_index = 0`
  - point-level `binding = "generator_context"`
  - `generator_decl_surface.yield_surface = "generator_context_v0"`

- Fresh landing (2026-04-22): the focused exchange/generator verification scripts now read
  source-side `meta` / `dump linked` through `./oren` and keep `./oren_stage2` on the actual
  build/runtime path. The correctness trade is explicit and favorable:
  - fast source-truth checking from stage1
  - target-compiler artifact truth still checked through embedded OBC metadata from stage2 bytecode
    builds
  - bytecode, C, and native execution proof still runs under stage2
  This keeps the default lane moving while stage2 `meta` latency remains materially higher than
  stage1 on the same fixtures.

The remaining boundary is narrower and still deliberate: `@oren.generator` applies only to named
binding sites (named function declarations or function-valued `var` bindings), not bare anonymous
function literals or arbitrary non-function statements. Above that, the remaining semantic gap is
no longer basic iterability; it is richer caller-visible coroutine/generator resume protocols beyond
the shipped implicit-`nil` `for-in` bridge and explicit `gen.send(...)` / channel-helper surfaces.

## Existing runtime / backend seams

### 1. AVM already has a dedicated yield opcode

Source: [lib/compiler/codegen_bytecode/010_codegen_a.oren](../lib/compiler/codegen_bytecode/010_codegen_a.oren)

- `oren_yield()` lowers to `AVM_YIELD`.
- `oren_yield_stmt()` lowers to `AVM_YIELD` plus canonical `nil`.
- `oren_yield_value(v)` compiles `v`, emits `AVM_YIELD`, and leaves `v` on the stack.
- `AVM_YIELD` itself is stack-neutral (`lib/avm/avm_cli_verify.c`, `lib/avm/avm_vm.c`).

Implication:

- In AVM, the correct normalized language value surfaces are now:
  - `oren_yield_stmt()` -> `nil`
  - `oren_yield_value(v)` -> `v`
  - raw `oren_yield()` stays a low-level helper surface, not the preferred language-visible value
    path

### 2. Native `oren_yield()` is a runtime helper, not the normalized language statement/value surface

Source: [lib/runtime_native/262_yield.oren](../lib/runtime_native/262_yield.oren)

- Native `oren_yield()` routes to `oren_green_yield()` when inside a green task.
- Otherwise it falls back to `sys_sched_yield()`.
- Native tests currently treat the low-level helper as returning `0` on success.
- `oren_yield_stmt()` is the normalized statement helper and always returns `nil`.
- `oren_yield_value(v)` is the normalized value helper and always returns `v` after yielding.

Implication:

- Raw `oren_yield()` is not cross-backend value-stable as a language expression:
  - AVM-special-cased helper path should prefer `nil`/kept-value behavior
  - native view is still scheduler/OS return code (`0` on success in current tests)

This is the main reason the language now lowers visible value surfaces through `oren_yield_stmt()`
and `oren_yield_value(v)` instead of exposing raw `oren_yield()` semantics directly.

### 3. Native already has stackful context-switch intrinsics

Sources:

- [lib/compiler/x64_native_program/043_emit_stack_intrinsics.oren](../lib/compiler/x64_native_program/043_emit_stack_intrinsics.oren)
- [lib/compiler/arm64_native_expr/090_tail.oren](../lib/compiler/arm64_native_expr/090_tail.oren)

Both native backends already inline:

- `oren_ctx_init(ctx, sp, pc)`
- `oren_ctx_switch(old_ctx, new_ctx)`

These are used by the green-task scheduler and save/restore full register state plus resume PC.

Implication:

- Native has a proven **stackful** switching substrate already.
- That substrate is tied to separate task stacks and shared allocator-register constraints.
- It is not a drop-in solution for backend-shared **stackless** function lowering.

### 4. Green entry already executes resumable work on scheduler-managed stacks

Source: [lib/runtime_native/263_green/030_green_entry.oren](../lib/runtime_native/263_green/030_green_entry.oren)

- `__oren_green_entry()` restores the task context, calls `oren_call_obj_list(fn_obj, args_list)`,
  stores the result, marks the task exiting, then switches back to the scheduler context.

Implication:

- There is already a runtime abstraction for resumable task execution.
- It is task-scheduler oriented, not function-local coroutine-frame oriented.

## Why `oren_yield_value(v)` was the next safe step

The bad lowering would have been:

```oren
var x = yield
```

to:

```oren
var x = oren_yield()
```

would create a backend semantic mismatch:

- native: `x == 0` (current low-level helper behavior)
- AVM: `x == nil`

That would have been worse than a loud parser error because it looks portable while being silently
divergent.

The shipped fix was to normalize the surface instead:

```oren
var x = yield expr
```

becomes:

```oren
var x = oren_yield_value(expr)
```

That keeps bytecode/C/native aligned on a simple local rule: yield, then resume with the same local
value.

## Credible next implementation options

### Option A: normalize a backend-shared helper first

Introduce a helper whose language-visible value is normalized across backends, then lower
expression-position/value-carrying `yield` to that helper.

Pros:

- small step
- keeps parser/user surface moving

Cons:

- already landed as `oren_yield_value(v)`
- still does **not** solve caller-visible resume-value or generator semantics

### Option B: add an explicit lowering pass for resumable functions

Treat `yield` as a lowering trigger and rewrite a function into:

- a frame/state record
- a state discriminator / resume switch
- explicit storage for locals that live across yield points

Pros:

- matches the documented long-term direction
- solves caller-visible `yield`/resume semantics at the right layer

Cons:

- materially larger compiler change
- requires cross-backend agreement on frame representation

### Option C: expose stackful coroutines on native first

Build a native-only library abstraction on top of `oren_ctx_init` / `oren_ctx_switch`.

Pros:

- leverages existing native machinery

Cons:

- not cross-backend
- diverges from the documented stackless direction
- risks creating a second coroutine model to unwind later

### Option D: strengthen the explicit channel protocol on the default native green runtime

Keep the shipped helper surface:

- `oren_yield_stmt()`
- `oren_yield_value(v)`
- `oren_yield_exchange(yield_ch, resume_ch, v)`

and make the default native green/runtime orchestration strong enough that the explicit channel
protocol works without special verifier escape hatches.

Pros:

- attacks a real shipped runtime gap instead of inventing new syntax
- keeps bytecode/C/native parity work grounded in the existing helper contract
- reduces the risk that source-level coroutine syntax lands on top of a weak runtime substrate

Cons:

- does not by itself define final generator syntax
- still needs a later language/design decision for caller-owned resume flow

## Recommended next step

With the default native runtime gap closed for the shipped explicit helper, the best next slice is
now back to **Option B** on top of the current helper surfaces:

1. keep the helper contracts explicit and parity-guarded across bytecode/C/native
2. define the explicit internal frame/state representation for source-level coroutine lowering
3. lower caller-visible resumable value flow on top of the shipped helper semantics instead of
   inventing a second value protocol
4. keep extending metadata/introspection only when it can honestly model the new value-flow surface

The first lowering pass already executes the current AVM bare-statement subset end-to-end, and
backend parity for the same subset is guarded across bytecode/C/native. The helper-based value
surface is parity-guarded, and the explicit exchange protocol is now shipped plus introspectable on
the default native runtime too. The next pass should stop widening helper mechanics and instead
tackle the real remaining boundary: true caller-visible coroutine/generator semantics beyond the
current helper contracts.

That path keeps the current repo state honest:

- `yield` statement sugar is shipped
- local value-stable `yield <value>` / expression `yield` is shipped
- explicit caller-visible `oren_yield_exchange(yield_ch, resume_ch, v)` is shipped
- raw `oren_yield()` remains available as a low-level helper
- full coroutine/generator semantics are still backlog, but the next work can start from the actual
  runtime seams and the now-proven helper surfaces above instead of rediscovering them in chat
