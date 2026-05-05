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
- Fresh landing (2026-04-23): `verify_yield_backend_parity_v0` now also emits a backend-neutral
  `[yield_lowering_v0]` trace for bytecode, C, and native, so parity is guarded against the same
  prepared-plan summary on every backend instead of relying only on the older AVM-only lowering trace.
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
- Fresh probe / landing (2026-04-22 / 2026-04-23): strict bytecode/C/native builds also execute
  `oren_yield_exchange(yield_ch, resume_ch, v)` successfully on the default native runtime too.
  Native host threads with green runtime already active and no background workers now do both parts
  needed for the shipped helper path: `oren_yield()` drives one cooperative green scheduling step,
  and the final wait for `resume_ch` now routes through `oren_select_recv([resume_ch])` instead of a
  raw blocking `oren_chan_recv(resume_ch)`. The verifier therefore no longer needs an
  `OREN_NO_GREEN=1` escape hatch for this helper path, and responder green tasks may yield before
  replying without wedging the host thread.
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
  - handle operations: `start`, `next`, `send`, `is_started`, `is_done`, `current_step`,
    `return_value`, `collect`
  The cross-backend generator verifier now also runs a raw channel-select smoke first, because that
  surfaced a real missing piece: the C runtime had channels but no shared `oren_select(...)`.
- Fresh landing (2026-04-23): `std:coroutine` now ships as the matching coroutine-oriented facade
  over that same compiler-managed generator handle/context contract:
  - same worker shape: `worker(co, args_list)`
  - same worker-facing exchange: `yield [expr] in co`
  - runtime-facing operations: `start`, `resume`, `next`, `send`, `on_finalize`, `on_close`,
    `close`, `cancel`, `request_cancel`, `delegate`, `delegate_step`, `is_started`, `is_done`,
    `is_closed`, `current_step`, `return_value`, `terminal_error`, `is_cancel_requested`,
    `cancel_reason`, `collect`
  - `std:reflect.is_coroutine(v)` / `std:reflect.is_coroutine_context(v)` are now the matching
    handle/context tag tests for that shipped facade
- Fresh landing (2026-04-23): the same shipped generator/coroutine handle now also carries a
  two-layer cancellation contract:
  - `request_cancel(target, reason)` records a sticky cancel request on a generator handle or
    `generator_context`
  - `cancel(target, reason)` records that sticky request and then forces the deterministic `close()`
    path
  - `is_cancel_requested(target)` / `cancel_reason(target)` expose that state
  - the first request wins, the reason survives natural completion or explicit `close()`, and the
    request propagates down the currently active delegated child chain
  - `request_cancel(...)` remains cooperative state; user code must still observe it cooperatively
  - `cancel(...)` is the shipped hard-stop layer for the current helper path
- Fresh landing (2026-04-23): timeout-aware watcher helpers now ship above that same
  cancel/request-cancel surface:
  - `request_cancel_after(target, timeout_ms, reason)` starts a joinable watcher task that sleeps
    for `timeout_ms` and then records the same sticky cooperative request state
  - `cancel_after(target, timeout_ms, reason)` starts a joinable watcher task that sleeps and then
    applies the same first-write-wins hard-stop `cancel(...)` protocol
  - `request_cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` /
    `cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` are the synchronous stdlib
    forms above those watcher helpers: immediate cases apply synchronously, while delayed cases
    spawn the same watcher and then wait through the shipped `oren_join_timeout(...)` contract
  - Update (2026-05-04): zero-delay or already-expired generator/coroutine async helpers now apply
    before returning and then hand back a joinable completed-result watcher. That preserves the
    public watcher-shaped API while reducing the native green-scheduler over-wait exposed by
    immediate generator stop/cancel verification.
  - Verification hardening (2026-05-04): surface verifiers that build native artifacts now bound
    native build steps through `OREN_VERIFY_NATIVE_BUILD_TIMEOUT_SECS` (default `180`) and kill
    the compiler process group on timeout. Generator/coroutine surface fixtures also use shorter
    watcher join budgets for already-short watcher checks, keeping the contract covered without
    multiplying known native green bounded-join over-wait into long verifier wall time.
  - Follow-up hardening (2026-05-04): the same native surface verifiers now prewarm the runtime
    astbin seed with stage1 and pass it directly as `OREN_NATIVE_RUNTIME_ASTBIN` for stage2 native
    builds. This avoids the cold runtime include-expansion/parsing path while iterating on
    `lib/runtime_native/**`. They now also prewarm a non-debug core runtime-object seed with
    stage1 before launching stage2 native surface builds. The prewarm no-op path validates the
    runtime hash cache against recorded source file size/mtime metadata, so repeated verifier runs
    avoid forced cold seed probes while edited scheduler runtime files still refresh the seed before
    fixture verification. The shared `scripts/build_rtobj_seed.sh` cold-fill path is also bounded by
    `OREN_RT_OBJ_SEED_BUILD_TIMEOUT_SECS` (default `180`) and kills the full child process group on
    timeout, so `make stage2` no longer has an unbounded rtobj seed probe outside verifier wrappers.
  - Bytecode verifier performance work (2026-05-04): direct bytecode builds now keep the finalized
    u8 buffer as the primary artifact and only materialize the legacy code list for OBC linking.
    Scalar bytecode constant interning reduced the generator surface constant pool from 5355 entries
    to 781 entries and direct OBC bytes from 312315 to 289646. The AVM bytecode-link smoke now uses
    a bounded tiny OBX link/run default plus an unresolved `--obc-lib` reloc guard; full stdlib OBC
    bundle probing remains opt-in with `OREN_VERIFY_FULL_STDLIB_OBC=1`.
  - Bytecode codegen profiling (2026-05-04): `OREN_TRACE_BYTECODE_CODEGEN=1` and
    `scripts/profile_bytecode_codegen.sh` now report section/function timing. The generator surface
    probe shows the remaining bytecode codegen wall time is dominated by the final call-fixup pass
    (`call_fixups`: about 41s for 1228 sites), not function-body compilation (about 3.9s summed
    across 321 functions). Oren-level cache and patch variants did not improve this path, and a
    direct-address experiment moved the same cost into per-call `ctx["functions"][name]` lookups.
    The next credible performance fix is a runtime-safe hot map lookup improvement or a bytecode
    emission model that avoids thousands of name-keyed post-pass patches.
  - Bytecode grouped call fixups (2026-05-04): unresolved call positions are now grouped by callee
    name during emission, so the final fixup pass resolves each unique callee once and patches all
    positions in that group. The generator surface profile dropped `call_fixups` from about 41s to
    about 6.7s for `1228` call sites across `231` unique callees while keeping `compile_stmts`
    around 4.0s. The profile summary now preserves extra section metrics such as `names=...`.
  - Native build phase profiling (2026-05-04): `make profile-native-build-phases` wraps a native
    fixture build with the verifier's direct astbin seed, rtobj seed prewarm, and timeout wrapper,
    then summarizes adjacent `OREN_TRACE_BUILD_PHASES_PATH` deltas. The generator-surface profile
    attributes the largest native costs to user declaration emission (~22.5s), link/prep (~14.5s),
    first-class wrapper emission (~12.8s), and global-root registration codegen (~7.3s for 626
    roots). `arm64.codegen.global_roots.done` now makes that root-registration span explicit.
  - ARM64 global-root initializer compaction (2026-05-04): root registration now uses a compact
    root-offset table plus one generated loop instead of emitting per-root ADR-data and BL fixups.
    The generator profile reduced local fixups from 20271 to 19021 and code bytes from 2592520 to
    2585100 while preserving `OREN_TRACE_GC_REGISTER_ROOT_NAMES` on its explicit diagnostic path.
    Root metadata is now recorded when globals are allocated or imported from rtobj seeds, preserving
    the 626-root generator profile count while cutting `arm64.codegen.global_roots.done` from about
    6.8s to about 120ms by avoiding an emission-time globals-map walk. A map-backed Mach-O
    target-cache experiment was rejected after hitting the 180s native profile timeout.
  - ARM64 rtobj globals adoption (2026-05-04): runtime-object application now emits `rtobj.apply.*`
    sub-phase profile rows, and schema-3 rtobj metadata carries the runtime global/root metadata needed
    for direct adoption on cache hits. The generator profile cut the 613-entry runtime globals replay
    from about 12.26s to about 0.55ms (`rtobj.apply.globals.done adopted=1`) by avoiding ordinary Oren
    map mutation before user globals are appended.
  - ARM64 wrapper profile split (2026-05-04): statement compilation now initializes compile hooks
    once per codegen context instead of resetting module globals on every statement, and native
    phase profiling splits first-class wrapper emission into scan/fnwrap/lambda buckets. The
    generator profile shows scan is only ~29ms, named function wrappers are ~4.2s, and lambda
    wrappers are ~8.4s, so the next native build optimization should target direct wrapper emission
    or wrapper codegen batching rather than more AST scanning.
  - ARM64 function-body profiling (2026-05-04): `OREN_TRACE_ARM64_FUNCTIONS_PATH` now records
    generated function codegen rows, and `make profile-native-build-phases` summarizes phase totals
    plus the hottest functions. The generator-surface profile shows the largest user-decl cost is
    the generated fixture `main` body (~13.2s / 300888 bytes), while wrapper cost is distributed
    across many generated wrappers (`lambda_wrap` ~8.5s across 52 funcs, `fnwrap` ~4.4s across 37).
    The same run exposes a separate Mach-O local BL target-resolution spike (~2.6s in the first
    4096 local BL fixups); because a map-backed target-cache experiment already hit the profile
    timeout, the next safe native optimization should reduce monolithic statement/function codegen
    overhead or change wrapper emission shape.
  - Mach-O local resolver metadata cleanup (2026-05-04): the local target resolver now keeps
    byte-content equality but stores unique-target string length and first byte with the existing
    linear cache. The refreshed generator profile improved the later BL resolve buckets
    (`~107ms + ~146ms` to `~36ms + ~88ms`), but the first bucket remains about `~3.37s`; keep the
    next native build work focused on user-declaration/wrapper codegen or a stronger first-bucket
    resolver design.
  - Local BL resolve counter follow-up (2026-05-04): phase logs now include `prefilled` and
    `resolved` target counts. The generator profile reports `prefilled=0 resolved=11285`; an
    eager-target experiment therefore does not help this surface, and a recent-first scan-order
    experiment also regressed. Keep the next resolver pass fact-based rather than reopening those
    two rejected hypotheses.
  - Local BL target metadata follow-up (2026-05-04): the resolver now records each unique target
    name's last byte in addition to length and first byte before full byte-content comparison. The
    refreshed generator profile reports `~2386ms + ~25ms + ~62ms` local BL resolve buckets for
    `n=11174`, so this is only a small later-scan cleanup; the first bucket and wrapper/user
    declaration codegen remain the real backend-performance boundary.
  - Local resolver scan diagnostics (2026-05-04): opt-in
    `OREN_PROFILE_MACHO_RESOLVE_STATS=1 make profile-native-build-phases` records unique target count,
    lookup count, linear scan steps, metadata candidates, byte comparisons, appended targets, and misses
    at progress and completion points. The generator profile reports
    `11398` BL lookups over `332` unique targets, `790088` scan steps, and only `12567` full byte
    comparisons; by `i=4096`, `269` unique targets have already been appended and `252115` scan steps
    have been paid. Detailed counters are gated so the default native profile stays phase/function
    oriented. Hoisting stable list lengths out of those loops trims only a few later-span milliseconds,
    so the next first-bucket resolver design must reduce linear traversal itself rather than
    byte-comparison cost.
  - Local resolver metadata-key cleanup (2026-05-04): the resolver now stores one combined
    `(length, first-byte, last-byte)` integer key per unique target instead of three separate metadata
    vectors. The generator profile remains behavior-compatible and keeps the same `790088` BL scan
    steps / `12567` byte comparisons, with the first bucket still about `~2.40s`; this is a
    constant-factor simplification rather than the final traversal fix.
  - Local resolver dead-vector cleanup (2026-05-05): the combined metadata-key resolver no longer
    needs the separate per-target length vector, so the local BL/ADR-code target cache stopped
    allocating/pushing that unused lane. The refreshed opt-in profile still reports the same class of
    traversal boundary (`11423` BL lookups, `336` unique targets, ~`801512` scan steps, first bucket
    ~`2.47s`), so the next material resolver win still needs fewer target-cache entries visited.
  - Rejected metadata-bucket resolver follow-up (2026-05-04): both a map-backed metadata-key bucket and
    a lean parallel-list metadata bucket reduced detailed BL scan accounting from `790088` entries to
    the candidate count (`12567`), but the measured first BL resolve bucket stayed flat/slightly worse
    (`~2.40s` to `~2.43-2.45s`). Do not retry bucket discovery that only moves the traversal cost into
    per-lookup map/list overhead.
  - Named-function wrapper cleanup (2026-05-04): synthesized `__oren_fnwrap_*` functions now skip
    native call-depth enter/exit instrumentation on ARM64 and x64 because the real target function
    still carries the guard. Lambda wrappers remain guarded because they own their body. The measured
    generator profile moves `fnwrap` from the prior ~5.8s / 29700 bytes / 37 funcs to ~3.9s / 28516
    bytes / 37 funcs, with local BL fixups down to 11174. Remaining backend work should still target
    user-declaration codegen, lambda-wrapper codegen, or the first BL resolve bucket.
  - Direct fixed-fnwrap body emission (2026-05-04): fixed-arity `__oren_fnwrap_*` functions now keep
    their synthesized AST body for non-ARM64 backends but carry metadata so ARM64 emits the wrapper's
    env/arity checks and target call directly inside the normal function frame. The refreshed generator
    profile moves `fnwrap` to ~0.95s / 19932 bytes / 37 funcs, so named-function wrappers are no
    longer the dominant wrapper boundary; `lambda_wrap`, `user_decls`, and the first BL resolve bucket
    remain.
  - Direct fixed-lambdawrap prefix emission (2026-05-04): fixed-arity `__oren_lambda_*` wrappers keep
    their synthesized AST body for fallback and non-ARM64 paths, but ARM64 now emits the generated
    env/arity checks plus capture/parameter binding prefix directly and then compiles the original
    lambda body normally. The refreshed generator profile moves `lambda_wrap` to ~1.7s / 54968 bytes /
    52 funcs, so wrapper codegen is no longer the dominant native-build boundary; large user bodies and
    the first local BL resolve bucket remain.
  - Wrapper emitter split (2026-05-04): the ARM64 direct fnwrap/lambdawrap emitters now live in
    `lib/compiler/arm64_native_stmt_wrappers.oren` and call back into the statement compiler explicitly.
    This preserves the shipped wrapper fast paths while keeping `arm64_native_stmt.oren` under the
    2000-line guardrail for the next user-declaration lowering work.
  - Direct non-string comparison branches (2026-05-04): ARM64 `if` conditions whose condition is a
    non-string comparison now branch directly from integer/float compare flags instead of materializing
    a runtime boolean singleton and immediately normalizing it for truthiness. The refreshed generator
    profile keeps `user_decls` time roughly neutral but cuts user-declaration code size from ~505KB to
    ~461KB and local fixup volume from 18719 to 17691.
  - Stackless literal/singleton branch follow-up (2026-05-04): direct ARM64 `if` comparisons now avoid
    the temporary left-operand stack spill for `true` / `false` / `nil` singleton checks and integer
    literal checks; wider and negative integer literals use a scratch-register compare. The same slice
    fixes ARM64 `oren_bool_norm(float)` so `bool(-0.0)` compares as `-0.0 != 0.0` and returns the false
    singleton instead of treating the raw IEEE sign bit as an integer. The generator profile reduces
    total code bytes from 2514200 to 2505768 and `user_decls` code bytes from 460696 to 452472, while
    leaving the main `user_decls` wall-time boundary intact.
  - Direct logical-if branch follow-up (2026-05-04): generated `if` guards that use `||` / `&&`
    short-circuit chains now carry patchable false-branch lists directly through ARM64 statement lowering
    instead of emitting a runtime boolean singleton and then re-normalizing it. The focused native quick
    fixture verifies side-effect short-circuit behavior. The generator profile keeps `user_decls` wall
    time roughly neutral (~20.9s) but cuts user-declaration code bytes from 452472 to 379528.
  - Direct string-comparison-if follow-up (2026-05-04): direct ARM64 `if` branch lowering now covers
    string/string-literal comparisons with the same guarded `strcmp` semantics and native small-value
    fallback as expression lowering. The generator profile keeps `user_decls` wall time roughly neutral
    but cuts `user_decls` bytes from `340360` to `325368` and local ADR-data fixups from `4665` to
    `4303`, so this is a guard-heavy code-size/fixup-volume cleanup rather than the final wall-time fix.
  - Literal branch trait-probe hoist (2026-05-04): direct ARM64 `if` comparisons against `true`,
    `false`, `nil`, and integer literals now run the stackless singleton/literal branch path before
    broad string/float trait probes, while known-float non-literal sides stay on the generic numeric
    path. The sequential generator profile keeps `user_decls` wall time in the same band (~21.0s) but
    trims `user_decls` bytes from `325368` to `323804`; a follow-up also reuses already-known string-trait
    results inside the guarded `strcmp` decision instead of walking both operands again. Treat this as
    constant-factor guard cleanup, not the final wall-time fix.
  - Rejected string-literal register branch follow-up (2026-05-04): a narrower ARM64 string-if branch
    experiment avoided the temporary stack spill for literal operands by loading literal pointers directly
    into compare registers. It passed focused branch/string smokes and trimmed generator `user_decls` bytes
    only from `325368` to `324612`, but repeated profiles regressed `user_decls` wall time to about
    `25.6s`; it was reverted. Do not retry that path without a lower-cost design.
  - Shared function epilogue follow-up (2026-05-04): ARM64 `return` statements now restore SP to FP and
    branch to one function-local epilogue after any required call-depth exit, instead of duplicating the
    callee-saved restore/ret sequence per return site. The generator profile keeps `user_decls` wall time
    roughly neutral (~20.8s) while cutting user-declaration bytes from 379528 to 340360.
  - Rejected literal-return fast path (2026-05-04): a direct ARM64 emitter for `return nil` / singleton /
    integer-literal values built and passed focused native smokes, but the generator profile stayed
    neutral-to-worse (`user_decls` still about `20.9s` and `340360` bytes), so it was reverted. Do not
    retry this narrow path without new profile evidence.
  - ARM64 statement profiling (2026-05-04): `OREN_PROFILE_NATIVE_STMTS=1 make
    profile-native-build-phases` now enables `OREN_TRACE_ARM64_STMTS_PATH` and summarizes inclusive
    statement buckets by phase/function/type. The default profile path remains phase/function-only to
    avoid per-statement aggregation overhead. The first generator run shows large user bodies spend
    most inclusive statement time in `ExprStmt(If)` (~16.5s / 854 stmts), with `Var` (~2.7s / 579) and
    `Return` (~2.4s / 1088) behind it; wrapper cost is dominated by the synthesized function/body
    envelope. A body-scope skip experiment regressed the profile, so the next implementation work
    should target direct lambda-wrapper/body emission or broad conditional-lowering cost instead.
    Follow-up probes rejected a narrow `if { return }` block-skip matcher because it left output size
    unchanged and was neutral-to-worse on phase timings; an exclusive statement-profiler variant using
    per-depth child counters also exceeded the 180s statement-profile budget before `user_decls`
    completed, so exclusive attribution needs a cheaper design before it is useful.
  - Condition-shaped statement profile follow-up (2026-05-04): the same gated profile now splits
    `ExprStmt(If)` buckets by condition shape. The refreshed generator profile ranks inclusive
    `user_decls` buckets as `Infix(||,Infix(!=),Infix(!=))` (~6.4s / 179 stmts),
    `Infix(||,Infix(||),Infix(!=))` (~4.4s / 58 stmts), `Infix(!=,Call,String)` (~1.8s / 46 stmts),
    and `Infix(!=,Call,Boolean)` (~1.6s / 121 stmts). Treat these as ranking data, not exclusive
    condition-lowering attribution.
  - Logical-branch flattening follow-up (2026-05-04): ARM64 direct `if` lowering now flattens
    same-operator `&&` / `||` chains before emitting branch lists, preserving short-circuit evaluation while
    avoiding recursive same-shape lowering. The first probe exposed that the helper has to use bytewise
    compiler string comparison for operator matching; direct string equality can fail to flatten and
    recursively re-enter the same condition until call-depth overflow. After the fix, focused smokes pass
    and the latest profile moves `user_decls` from the prior noisy ~25.1s sample to ~21.7s, with unchanged
    code bytes and only small condition-bucket movement. This is structural cleanup, not the final
    wall-time fix.
  - OR-branch single-jump inversion follow-up (2026-05-04): ARM64 direct `if` lowering now skips the
    unconditional true bridge for non-last `||` terms only when the term produces one false-branch
    placeholder; that placeholder is inverted into a direct then-block branch and the false path falls
    through to the next OR term. A full inversion probe was rejected on correctness after native
    integration failed through the `dot_f64_view` validation shape (`a && b || c && d`): each false exit
    from a conjunction means "the whole conjunction is false", and inverting them independently changes
    the term to disjunction semantics. The fixture now guards that mixed `&&`/`||` shape explicitly. The
    refreshed generator profile trims `user_decls` bytes from `323804` to `322472` while wall time remains
    in the same band, so this is a guarded code-size cleanup rather than the final `user_decls` fix.
  - Singleton-compare trait cleanup (2026-05-04): direct `if` comparisons against runtime singletons now
    bypass the long float-trait classifier when the other side is syntactically non-float, an annotated
    non-float direct call, or a known direct boolean helper (`oren_is_err`, `oren_generator_is_done`, and
    the injected generator state predicates). This does not change emitted bytes, but the refreshed default
    generator profile keeps `user_decls` around ~21.1s instead of the prior ~21.2s sample and wrapper
    buckets also move slightly lower. Keep this classified as compiler-side constant-factor cleanup.
  - Statement loop length-hoist follow-up (2026-05-04): ARM64 block statement iteration, branch false-jump
    patching, return-jump patching, and logical branch helper loops now hoist stable `oren_list_len(...)`
    values out of hot compiler loops. This does not change emitted code; the refreshed generator profile
    keeps `user_decls` in the previous band (~20.9s / 323804 bytes), with `lambda_wrap` ~1.7s and `fnwrap`
    ~0.95s. A declaration-free block scope-frame skip was rejected after profiling because it regressed
    `user_decls` to ~22.1s and wrapper phases too; the new block/shadow/`for var` smoke guards future
    block-scope work in native quick.
  - Fresh-cap tracker fast path (2026-05-04): the ARM64 list-int reserve-skip tracker now avoids cloning and
    recursively scanning fresh-cap maps when no tracked cap exists, and the remaining expression scanner
    hoists stable child-list lengths. Emitted code is unchanged. The default generator profile remains in the
    previous band (~20.9s / 323804 bytes), while the gated statement profile moves `user_decls Var` from
    ~2.85s to ~2.76s and statement-profiled `user_decls` from ~23.0s to ~22.2s. This is compiler-loop
    constant-factor cleanup, not the full `user_decls` wall-time fix.
  - Statement shape/callee profile follow-up (2026-05-04): gated ARM64 statement profiling moved into
    `arm64_native_stmt_profile.oren` and now breaks `Var`, `Assign`, and `Return` buckets down by value/callee
    shape. The refreshed generator statement profile points to generator error-return helpers
    (`STD_generator__generator_cancel_target_err`, `_oren_generator_err`), generator policy member calls
    (`stop_policy_wait`, `stop_policy`), and lambda-wrapper `oren_list_get` capture loads as the largest
    non-conditional buckets. Treat that as ranking data, not permission for generator-specific native
    shortcuts without separate semantic/performance proof. A direct lambda-wrapper local-binding probe
    removed the `lambda_wrap Var(Call(Id:oren_list_get,2))` statement bucket, but default profiles stayed
    neutral-to-worse (`lambda_wrap` ~1.7-1.9s with identical emitted bytes), so the generic synthetic-`Var`
    binding path remains shipped.
  - Binding statement split (2026-05-05): ARM64 `Var`/`Assign` lowering moved into
    `arm64_native_stmt_bindings.oren`. It keeps FP-relative local/global slots and static trait propagation
    unchanged while pulling `arm64_native_stmt.oren` down from the line-count guardrail edge to 1761 lines.
    This is maintainability groundwork for future `user_decls` work, not a measured wall-time fix.
  - Terminator statement split (2026-05-05): ARM64 `break`, `continue`, shared return-jump patching, and
    `Return` lowering moved into `arm64_native_stmt_terminators.oren`. The same cleanup hoists stable list
    lengths in the loop matcher identifier-use scanners. It preserves generated-code behavior while reducing
    `arm64_native_stmt.oren` to 1659 lines; this is maintainability and compiler-loop constant-factor work,
    not a material `user_decls` wall-time fix.
  - ARM64 dynamic string equality fix (2026-05-05): native `test_generator_std.oren` exposed that generic
    `assert_eq(a, b)` could compare two dynamic strings by pointer when neither parameter retained static
    string traits. Expression and direct-`if` equality lowering now try safe `oren_string_eq(...)` only for
    operands that are neither statically stringy nor provably non-string, then fall back to raw pointer/int
    comparison. This fixes `assert_eq(oren_type_name(g), "generator")` and keeps common generated guard
    comparisons off the runtime string helper path; the uncontended generator profile stays near the prior
    band (`user_decls` ~21.0s / 323192 bytes).
  - ARM64 guard-comparison trait cleanup (2026-05-05): direct `if` singleton/int-literal comparisons now share
    the known-nonfloat classifier before falling back to expensive float-trait walks, and direct string
    branches skip float classification entirely. Emitted bytes stay unchanged and the uncontended profile
    remains in the noisy prior band (`user_decls` ~21.9s / 323172 bytes), so the main backend target remains
    broader generated-body lowering.
  - Generator fixture split (2026-05-04): the surface fixture now preserves the same assertions and
    return codes while splitting the giant native `main` into four top-level chunks plus a tiny
    dispatcher. The hottest generated function dropped from ~13.2s / 300888 bytes to chunks around
    ~1.0s, ~4.1s, ~3.0s, and ~4.2s; the measured native profile improved `user_decls` from ~22.0s to
    ~20.7s and link/prep from ~14.6s to ~8.4s.
  - Generator fixture re-split (2026-05-05): the same surface fixture is now split into seven focused
    chunks plus the dispatcher, preserving return codes and coverage while cutting the largest fixture
    chunk to ~2.8s in the refreshed native profile. `user_decls` remains in the same broad band but
    nudges to ~20.6s / 323172 bytes / 276 funcs, so this is fixture-shape/codegen-scaling cleanup; the
    first Mach-O local BL resolve bucket remains ~2.4s.
  - Generator fixture second re-split (2026-05-05): the remaining hottest generator fixture chunks were
    split along independent assertion groups (`timeout_policy_*`, `decl/local_generators`, and
    `iteration_*`). Return codes and coverage are preserved. The uncontended native profile reports
    `user_decls` around ~20.4s / 323632 bytes / 282 funcs, with the largest generator fixture body now
    ~1.73s. Keep this classified as verifier-shape/codegen-scaling cleanup, not the backend wall-time fix.
  - ARM64 function-declaration subphase profiling (2026-05-05): the gated
    `OREN_PROFILE_NATIVE_STMTS=1 make profile-native-build-phases` path now records named-function
    `FunctionDecl(register/context/prologue/params/enter/body/epilogue)` rows and the script summarizes
    those subphases separately. The refreshed generator profile shows `user_decls FunctionDecl(body)`
    accounts for ~22.5s / 289KB of the ~22.7s inclusive function-declaration bucket, while prologue,
    params, enter, and epilogue are byte-visible but sub-millisecond. This rules out function setup as
    the next wall-time lever; continue targeting generated body/conditional lowering, especially the
    large `ExprStmt(If:Infix(||,...))` buckets.
  - ARM64 if-statement subphase profiling (2026-05-05): the same gated statement profile now records
    `IfStmt(cond:<shape>)`, `IfStmt(consq)`, `IfStmt(alt)`, and patch rows, and the profile script
    summarizes them separately. The refreshed generator statement profile shows the hot generated
    guard buckets are condition lowering itself: `IfStmt(cond:Infix(||,Infix(!=),Infix(!=)))` at
    ~6.8s / 179 stmts and nested-`||` at ~4.7s / 58 stmts, while all consequence lowering is ~2.3s
    across 860 statements and else/patch work is negligible. This narrows the next backend slice to
    direct logical-condition lowering, not return-body/block cleanup.
  - ARM64 condition-term profiling (2026-05-05): the gated statement profile now records
    `CondTerm(<route>:<shape>)` rows from recursive logical-condition lowering and the profile script
    summarizes them separately. The first refreshed generator profile shows the dominant terms are
    literal comparisons against `Index` results: `CondTerm(singleton:Infix(!=,Index,Boolean))` at
    ~6.0s / 130 terms and `CondTerm(int_lit:Infix(!=,Index,Integer))` at ~5.2s / 157 terms. A scalar
    OR true-branch patch-list experiment passed stage2 and focused logical/integration checks, but kept
    the hot `IfStmt(cond:||)` buckets unchanged/slightly worse, so the source was reverted. The next
    credible throughput slice should reduce term/index lowering work rather than changing patch-list
    representation.
  - ARM64 known-map index cleanup (2026-05-05): `Index` lowering now skips the dead list fast-path block
    for receivers already annotated `recv_kind="map"`, while preserving dynamic/list lowering and the
    existing tracked-node plus map-magic validation before map gets. Focused typed-struct/map fixtures
    pass. The generator profile is unchanged because the hot generated guard terms are not statically
    map-marked, so this is bounded map-index code-size cleanup rather than the generator `user_decls`
    wall-time lever.
  - Generator step-result map inference (2026-05-05): impl lowering now marks known generator step-result
    calls (`gen.next`, `gen.send`, `current_step`, and linked/runtime equivalents) as map-returning without
    changing the original callee expression shape, so the kind hint survives local binding inference while
    C/native/bytecode lowering keep their backend-specific call handling. The refreshed generator profile drops
    `user_decls` bytes from `323172` to `302592`
    and local BL fixups from `11423` to `10920`; wall time remains in the same noisy ~20s band. The gated
    statement profile now labels the hot condition-term buckets as `Index(map,str_lit)`, so the remaining
    target is typed map index term lowering itself rather than missing receiver-kind propagation.
  - ARM64 map string-literal index fast path (2026-05-05): `Index(map,str-literal)` expression lowering now
    preserves nil/tracked-node/map-kind/map-magic validation but emits the string-key `oren_map_get_str` path
    directly instead of using the generic container/key stack shuffle. The refreshed uncontended generator
    profile reports `user_decls` at about `20.3s / 292072 bytes / 282 funcs`; statement-profiled
    `Index(map,str_lit)` condition terms shrink but remain the dominant conditional cost, so the next credible
    lever is reducing the validation/get sequence itself.
  - ARM64 map-key C-string MRU (2026-05-05): the direct `Index(map,"literal")` emitter now keeps a small
    compiler-side MRU for map-key C-string data offsets, and statement profiling now breaks this fast path into
    `MapStrIndex(eval_recv/validate/load_key/call)` subphases. The profile showed the prior cost was repeated
    `native_data_add_cstr0` lookup for generator keys rather than validation emission: `MapStrIndex(load_key)`
    moves from ~11.9s / 263 expressions to ~0.17s / 263 expressions, and default generator `user_decls` moves
    to ~11.1s / 292072 bytes / 282 funcs. A broader shared `native_data_add_cstr0` MRU was tested and rejected
    because unrelated string literals polluted it and left the same load-key bucket near ~13.1s.
  - `std:generator` primitive type-tag guards (2026-05-05): generator policy helpers now use
    `oren_type_tag(...)` for primitive `int`/`string` argument checks, while preserving `oren_type_name(...)`
    for generator handle/context and map checks. Focused generator checks pass, and default generator
    `user_decls` moves from ~11.1s / 292072 bytes / 282 funcs to ~10.2s / 292144 bytes / 284 funcs. A broader
    raw-tag rewrite for generator handles/contexts was rejected because native `test_generator_std.oren`
    failed at `gen.terminal_result(g)`, so keep that boundary closed without a runtime-layout proof.
  - Primitive guard follow-up (2026-05-05): `std:task` and `std:task_group` now use the same tag-only rule
    for `int`/`string` policy arguments, and generated generator close-hook validation checks the stable
    `FUNC` tag (`8`) instead of reflecting `oren_type_name(hook)`. Map/list/generator handle/context checks
    intentionally remain name-based. The task/task-group and generator finalize/surface verifiers pass; the
    refreshed default generator profile remains in-band at ~10.0s / 292000 bytes / 284 funcs, so this is
    cross-surface guard cleanup rather than the next large `user_decls` lever.
  - Rejected container-tag broadening (2026-05-05): replacing remaining stdlib map/list facade checks in
    `std:generator`, `std:task`, and `std:task_group` with raw `MAP=7` / `LIST=6` tags built and passed
    focused generator/task surfaces, but the default profile stayed flat/slightly worse (`user_decls`
    ~10.05s, bytes 292176, funcs 285) and removed only one `Call,String` condition bucket. The probe was
    reverted; keep those facade checks name-based unless a new semantic/runtime-layout proof also produces
    a profile win.
  - Rejected small direct named-call lowering (2026-05-05): a zero/one-argument ARM64 direct named-call fast
    path passed stage2 and generator/task/coroutine surface verifiers and reduced generated `user_decls`
    bytes to ~271652, but the uncontended default profile regressed `user_decls` wall time to ~49.5s. The
    source probe was reverted; do not pursue this generic call-marshalling byte cut without a different
    compiler-throughput profile.
  - Rejected helper path (2026-05-05): a new kept `oren_map_get_str_checked` runtime helper was tested to move
    the validation sequence out of each ARM64 map string-literal index site. It built, but native map/generator
    fixtures exited `11`; adding the helper name to the native-op spill surface did not fix the direct-call
    ABI/entry failure. Keep this path closed until ABI parity with `oren_map_get_str` is proven.
  - Rejected global integer assignment path (2026-05-05): a narrow ARM64 fast path for top-level/global
    `Assign(Integer)` built and passed focused generator/type-boundary checks, but profiles stayed flat:
    default `top` remained about ~2.33s, `user_decls` about ~11.2s, and statement `Assign(Integer)` stayed
    about ~2.4s / 16 statements with identical bytes. The source probe was reverted; global integer-literal
    lowering is not the next wall-time lever.
  - ARM64 call-expression profiling (2026-05-05): the gated statement profile now records
    `CallExpr(<route>:<callee>,<argc>)` rows and the profile script prints a call-expression table. The
    refreshed default profile remains in the current band at ~12.25s / 292000 bytes / 284 funcs for
    `user_decls`, while the gated profile shows the next generated-body target is specific generic generator
    helper calls rather than map string-key lookup: `_oren_generator_trace` is ~1.5s / 21 calls,
    `STD_generator__generator_cancel_target_err` is ~1.3s / 27 calls, `_oren_generator_err` is
    ~1.2s / 10 calls, and `oren_is_err` is ~1.0s / 318 calls. Runtime trace/env semantics still matter, so
    do not remove `_oren_generator_trace` calls or resurrect the rejected generic small-call fast path without
    a narrower semantic proof.
  - ARM64 generic call ABI cache (2026-05-05): direct call marshalling now caches stable ABI metadata on the
    native context and reuses the raw integer-argument register vector instead of asking `native_abi` for the
    same facts at every generated helper call. Emitted code remains unchanged, and the fallback ABI diagnostic
    path stays intact. The refreshed default profile moves generator `user_decls` from ~12.25s / 292000 bytes /
    284 funcs to ~10.06s / 292000 bytes / 284 funcs; remaining call rows still point at specific generator
    helper semantics rather than a broad direct-call byte-size shortcut.
  - Rejected `oren_is_err` inline path (2026-05-05): an ARM64 direct lowering for `oren_is_err(v)` kept the
    structured-error semantics intact by checking tracked-node membership, map kind, map magic, and the
    `"__err"` marker before returning boolean singletons. Focused generator native/bytecode probes passed, but
    the duplicated predicate inflated default `user_decls` to ~17.9s / 337792 bytes / 284 funcs from the
    post-ABI-cache ~10.06s / 292000 bytes, so the source probe was reverted. The next `oren_is_err` attempt
    needs a branch-only use-site or smaller runtime representation, not full call-site inlining.
  - ARM64 generic call subphase profiling + string-literal C-string MRU (2026-05-05): the gated statement
    profile now records `CallGenericSub(arg_eval|abi_meta|stack_args|reg_args|bl_retfix|cleanup:<callee>,argc)`
    rows, proving the remaining hot generic helper rows are dominated by argument expression lowering rather
    than ABI metadata or BL/fixup emission. A separate ordinary string-literal C-string MRU now feeds the
    `String` expression path without sharing or polluting the already-measured map-key MRU. Repeated default
    profiles move generator `user_decls` from the post-ABI-cache ~10.06s / 292000 bytes / 284 funcs to
    ~4.26s / 292000 bytes / 284 funcs, while the statement profile collapses `oren_is_err` arg-eval from
    ~1.3s / 318 calls to ~0.17s and `STD_generator__generator_cancel_target_err` arg-eval from ~1.7s /
    27 calls to ~0.12s. `_oren_generator_trace` remains a visible call row because its runtime env/trace
    semantics are observable; do not remove it without preserving `OREN_TRACE_GENERATOR_CORE`.
  - ARM64 top-level integer-global preinit (2026-05-05): the backend now writes plain integer-literal user
    globals directly into their `.data` slots and omits those side-effect-free assignments from the synthesized
    `__top_level__` function on ordinary non-gas builds. This is not the earlier rejected in-place
    `Assign(Integer)` fast path: runtime globals, negative prefix/non-literal initializers, and
    `OREN_NATIVE_GAS_ACCOUNTING=stmt` / `basic-block` / `block-weighted` / `dynamic-emitter` builds still emit
    the ordered assignment statements so gas accounting and source-order side effects stay observable.
  - Native link/profile split (2026-05-05): `make profile-native-build-phases` now records link-program
    subphases inside the standard phase log, and package metadata/policy assembly reuses the already-computed
    package attr plus capability-domain facts instead of rescanning statements for each JSON/status view. The
    measured generator profile shows metadata substeps are sub-5ms and not the wall-time lever; the actual link
    boundary is now visible as optimizer pass cost (~3.64s after `abi_layout`) and module parse (~2.55s). Keep
    follow-up work on optimizer/link-program internals or the still-separate Mach-O local BL resolver boundary.
  - Optimizer subprofile and list prefilter (2026-05-05): the optimizer now emits a gated
    `optimizer.summary` phase row with aggregate subpass timing when build-phase logging is enabled. The retained
    compiler-side list-touch prefilter runs the list-int and list-reserve passes only on function bodies that may
    touch lists; the refreshed profile reports `119/470` list candidates, list scan overhead ~20ms, optimizer time
    moving from ~3.76s to ~3.31s, `list_int` from ~1.81s to ~1.46s, and reserve from ~0.64s to ~0.53s. A
    narrower list-int-only prefilter probe reduced candidates to `86/470`, but it raised list-scan overhead to ~53ms,
    left `list_int` around ~1.44s, and worsened optimizer total to ~3.42s, so the source probe was reverted.
    A fold-pass stable-list-length hoist also passed stage2 and focused optimizer/generator gates, but repeated
    profiles left `fold_ms` around ~0.97-1.02s and optimizer total around ~3.40-3.43s, so that source probe was
    reverted as neutral-to-worse.
    A DCE-before-optimizer pass-order probe passed stage2 plus focused generator/coroutine verifiers but regressed the default
    profile (`optimizer` ~5.1s, `user_decls` ~7.2s), so global DCE stays after the optimizer.
  - Rtobj seed durability (2026-05-05): `scripts/build_rtobj_seed.sh` now matches schema-versioned runtime-object
    cache directories (`sN_b_*`) instead of only legacy `s2_b_*` names, and `make rtobj-seed` warms both core and
    full runtime profiles for no-debug/debug host seeds. This prevents full-runtime fixtures such as
    `std:linalg` list-int parity from missing the no-debug seed and falling back to a slow `rtobj.miss.build.start`
    path after schema-3 cache entries already exist. Isolated seed dirs can now be filled from the persistent
    fallback seed dir before attempting a cold build, and the helper refuses cross-compiler cold rtobj seed builds
    by default; the existing cache key proves runtime/backend compatibility, not that a stage1-emitted runtime
    object is safe to link into a stage2-emitted user binary.
  - Module parse profiling (2026-05-05): the serial module parse path now emits `link.parse_module.done` rows
    into the standard phase log, and `scripts/profile_native_build_phases.sh` summarizes them by module path with
    read/cache/parse/lexer/parser/merge/prepare sub-buckets. The refreshed generator profile identifies
    `lib/std/generator.oren` as the dominant parse module (~1.43s / 137 stmts) with ~1.32s in
    `parser.parse_program` and lexer setup rounding to 0ms, followed by `lib/std/task_group.oren`
    (~502ms / 62 stmts, ~317ms parser) and `lib/std/task.oren` (~321ms / 52 stmts, ~211ms parser).
    Reweight module-parse follow-up toward parser-level generator/task shape or a non-serial-write cache design,
    not file-read/cache/prepare work or the small `reflect/result/list` tail. An opt-in serial module-cache write
    probe timed out before completing the profile: it wrote only the first two ASTBIN cache entries and charged
    ~114.5s to `lib/std/time.oren` including encode/write cost, so serial cache seeding was reverted as the wrong
    persistence strategy.
  - Coroutine fixture split (2026-05-04): the coroutine surface fixture now mirrors that structure
    with four focused chunks plus a dispatcher. The largest coroutine fixture chunk in the measured
    native profile is now ~2.0s, while the profile still leaves real compiler/backend work visible:
    `user_decls` ~12.0s, global roots ~6.3s, link/prep ~9.1s, and Mach-O local BL target resolution
    ~1.8s for the first 4096 local calls. ARM64 trait propagation also now reuses already-known
    float traits when computing integer traits for `var`, assignment, and global propagation; this is
    a small redundant-walk cleanup rather than the main native build-time fix.
  - Runtime fix (2026-05-04): native green host-thread `oren_green_join_timeout(g, timeout_ms)`
    no longer hands the full positive timeout to the generic scheduler poll in one shot. It polls
    in short bounded slices and re-checks the joined target between slices, preventing unrelated
    parked sleepers from making a completed watcher wait until the caller's timeout expires.
  - `timeout_ms == nil` defaults to `0`, negative timeouts clamp to `0`, and invalid non-`int`
    timeout arguments return an immediate `err`
  - the watcher join result is `nil` for live-target request/hard-cancel flows; if
    `cancel_after(...)` runs after the target is already done, the watcher returns the cached
    terminal result instead of rewriting cancellation state
  - `join_timeout_ms == nil` or any negative `join_timeout_ms` value now uses a derived wait
    budget instead of a raw infinite join: relative helpers wait for `timeout_ms + 2000`,
    absolute helpers wait for the computed deadline delay plus `2000`, and stop helpers add
    `grace_ms` into that same default budget; invalid non-`int` join-timeout arguments return an
    immediate `err`
  - the restored clean native green/runtime route carries started generator handles through these
    watcher tasks correctly, so the remaining protocol gap is now richer scheduler/deadline policy
    above the shipped helper layer rather than missing timeout-helper availability
- Fresh landing (2026-04-23): absolute-deadline cancellation now ships on top of that watcher
  layer:
  - `request_cancel_at(target, deadline_ns, reason)` / `cancel_at(target, deadline_ns, reason)`
    use the same watcher protocol but against an absolute `deadline_ns` in the `time.now_ns()`
    domain
  - `request_cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` /
    `cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` are the matching synchronous
    absolute-deadline forms
  - `deadline_ns <= time.now_ns()` fires immediately
  - `deadline_ns == nil` defaults to immediate
  - invalid non-`int` deadlines return an immediate argument `err`
- Fresh landing (2026-04-23): the first explicit soft-then-hard stop policy now ships above that
  helper layer:
  - `stop_after(target, timeout_ms, grace_ms, reason)` records the cooperative sticky cancel
    request after `timeout_ms` and then escalates to the shipped hard-stop `cancel(...)` path after
    `grace_ms`
  - `stop_at(target, deadline_ns, grace_ms, reason)` applies that same soft-then-hard policy
    against an absolute `deadline_ns` in the `time.now_ns()` domain
  - `stop_after_wait(target, timeout_ms, grace_ms, reason, join_timeout_ms)` /
  `stop_at_wait(target, deadline_ns, grace_ms, reason, join_timeout_ms)` are the synchronous
  stdlib forms above that watcher layer: they apply the same policy and then wait through
  `oren_join_timeout(...)`, using either the explicit `join_timeout_ms` budget or the derived
  operation window plus `2000`
  - `timeout_ms == nil`, `grace_ms == nil`, and `deadline_ns == nil` all default to immediate
    scheduling points
  - negative timeout / grace values clamp to `0`
  - invalid non-`int` timeout / grace / deadline arguments return an immediate `err`
  - `cancel(target, reason)` now consistently accepts either a generator handle or an active
    generator context, matching the target-oriented watcher/stop surface
  - `terminal_result(handle)` now exposes the final done-handle result directly as terminal error
    or return value, and rejects invalid / still-live handles with `err`
- Fresh landing (2026-04-23): that same synchronous stop/cancel stack now also exposes a
  map-shaped scheduler/deadline policy API:
  - `stop_policy(target, policy)` always returns the joinable watcher handle for the normalized
    policy
  - `stop_policy_wait(target, policy)` applies that same normalized policy synchronously
  - `policy["mode"]` accepts `request_cancel`, `cancel`, or `stop` (default `stop`; `request`
    aliases `request_cancel`)
  - `policy["timeout_ms"]` and `policy["deadline_ns"]` are mutually exclusive when both are
    non-`nil`
  - `policy["grace_ms"]` is valid only for `mode=stop`; positive grace with the other modes fails
    immediately with `err`
  - `policy["join_timeout_ms"]` is consumed by `stop_policy_wait(...)` and follows the same
    derived wait-budget rules as the existing `*_wait(...)` helpers
  - Fresh landing (2026-04-23): `std:task` now ships as the first safe facade over generic
    `spawn` handles:
    - `task.is_handle(...)` / `is_done(...)` provide the first reflected task predicates across
      AVM, C, and the default native green-task path
    - `task.current()` now returns the current safe task handle inside scheduler-backed spawned work
      and `nil` elsewhere
    - `task.request_cancel(...)`, `task.is_cancel_requested(...)`, and `task.cancel_reason(...)`
      now ship as cooperative sticky cancel-request state for generic task handles
    - a task may observe that sticky request on its first executed step when the request is recorded
      before the task first runs
    - `task.request_cancel_after(...)` / `request_cancel_after_wait(...)` and
      `task.request_cancel_at(...)` / `request_cancel_at_wait(...)` now layer timeout/deadline
      helpers above that cooperative state
    - zero-delay / already-expired `*_wait(...)` calls now apply the request synchronously before
      returning instead of relying on a watcher task to run later
    - `task.join(...)`, `join_timeout(...)`, `detach(...)`, and `join_all(...)` now wrap the raw
      runtime join surface behind safe-handle validation
    - `join_timeout(...) == -60` now preserves the live handle for later join/cancel/detach instead
      of consuming it on timeout
    - `task.cancel(...)`, `cancel_after(...)`, `cancel_after_wait(...)`, `cancel_at(...)`, and
      `cancel_at_wait(...)` now ship as bounded task-cancel helpers: they record the same cooperative
      sticky request first, then use the safe join/detach path instead of an unsafe preemptive worker
      kill
    - `task.stop_after(...)`, `stop_after_wait(...)`, `stop_at(...)`, `stop_at_wait(...)`,
      `stop_policy(...)`, and `stop_policy_wait(...)` now ship as the shared task stop/deadline
      surface for generic `spawn` handles
    - that task stop surface now accepts `mode="request_cancel"`, `mode="cancel"`, and `mode="stop"`
    - `mode="request_cancel"` records cooperative sticky state only
    - `mode="cancel"` records the cooperative request at the timeout/deadline and then immediately
      applies bounded join/detach
    - `mode="stop"` records the cooperative request at the timeout/deadline, then waits the grace
      window before detaching if the task is still live
    - `stop_policy_wait(...)` returns `nil` for `mode="request_cancel"` and returns the
      `{status, result, reason, detach_result}` map for `mode="cancel"` or `mode="stop"`;
      `join_timeout_ms` remains the explicit synchronous wait-budget override
    - legacy native raw fallback handles remain low-level-only for now; the safe reflected surface
      is intentionally limited to scheduler-backed native task handles
  - Fresh landing (2026-04-23): `std:task_group` now ships as the first group-shaped
    structured-concurrency layer above that map policy:
    - `task_group.new(default_policy)` / `from_list(targets, default_policy)` create mutable groups
      over generator/coroutine handles, active contexts, or safe task handles
    - `task_group.stop_policy(group, policy)` merges the group default policy with an override and
      returns a watcher list for the full group; stdlib map-backed groups now also dispatch by
      member kind instead of rejecting task members
    - `task_group.stop_policy_wait(group, policy)` applies that same normalized policy
      synchronously and now routes task members through the shared `std:task`
      stop-policy surface
    - direct group helpers now mirror that policy family for easier use:
      `request_cancel(...)`, `request_cancel_wait(...)`, `cancel(...)`, `cancel_wait(...)`,
      `stop_after(...)`, `stop_after_wait(...)`, `stop_at(...)`, and `stop_at_wait(...)`
    - `task_group.join_all(...)` is now the task-handle-only group join path, while
      `task_group.join_watchers(...)` and `task_group.terminal_results(...)` complete the watcher /
      final-result side of the group surface
  - Fresh landing (2026-04-23): runtime-backed task groups for generic `spawn` work now also ship
    as the first runtime-backed mixed group surface:
    - `task_group.new_runtime()` / `new_runtime_with_policy(default_policy)` create runtime-backed
      groups with the latter attaching a stored default stop-policy map
    - `task_group.from_task_list(targets)` / `from_task_list_with_policy(targets, default_policy)`
      are the task-handle constructors, while `task_group.from_runtime_list(targets,
      default_policy)` creates the same runtime-backed shape from safe task handles plus
      generator/coroutine handles or active contexts
    - runtime-backed groups now also accept those same mixed non-task members through `add(...)` /
      `extend(...)`
    - `task_group.is_runtime_group(...)` distinguishes that runtime-backed shape, while
      `task_group.is_group(...)` and `std:reflect.is_task_group(...)` now accept both runtime and
      stdlib map-backed groups
    - `task_group.default_policy(...)` / `set_default_policy(...)` now also ship for runtime-backed
      groups and round-trip a cloned stored policy map; `snapshot(...)` returns cloned `members`,
      `member_kinds`, and `default_policy`
    - `task_group.member_kinds(group)` now exposes the normalized member-kind vector (`"task"`,
      `"generator"`, or `"generator_context"`), and runtime-backed groups compute it from an atomic
      runtime-owned member snapshot rather than a separate stdlib classification pass
    - runtime-backed mixed membership, stored default policy, and member/kind/policy snapshotting now live
      in the runtime group state itself across C, native, and AVM instead of stdlib sidecar maps; runtime
      stop paths preflight policy and then consume an atomic runtime-owned take-snapshot before dispatching
      per-member policy helpers, so invalid overrides leave runtime groups intact while valid stop
      operations claim and clear participating members up front
    - `task_group.spawn_call_list(...)` spawns directly into the runtime group on AVM, C, and the
      default native green-task scheduler
    - `task_group.stop_policy(group, policy)` / `stop_policy_wait(...)` now dispatch by member kind:
      - stored runtime-group default policy is merged before override validation
      - generator/coroutine members keep the full generator-backed stop-policy semantics
      - task members now use the same shared `std:task` contract, including cooperative
        `mode="request_cancel"`, bounded `mode="cancel"`, `mode="stop"`, and optional
        `join_timeout_ms` override on the synchronous path; immediate zero-budget task cancel/stop
        execution is runtime-owned through `oren_task_cancel_now(...)`
      - `std:task.stop_capabilities()` exposes that runtime boundary as a map:
        immediate cancel-now, cancel-request state, bounded cancel-wait, and delayed synchronous
        cancel-wait are runtime/scheduler-backed across C, native, and AVM; AVM uses dedicated
        scheduler opcodes for the wait paths
    - `task_group.join_all(...)` / `detach_all(...)` remain task-handle-only runtime-group
      operations and reject extra generator/coroutine members
    - `task_group.terminal_results(...)` now works for runtime-backed groups that contain only
      generator/coroutine handles; it still rejects task handles and context-only members
  - the remaining gap is now narrower: runtime-backed groups are already unified and runtime-owned
    for mixed membership, stored default policy, and atomic member/kind/policy snapshot-and-take
    semantics, and generic task cancellation now ships as cooperative request plus bounded stop/detach;
    immediate task stop execution and bounded/delayed synchronous task cancel waits are now
    runtime/scheduler-owned through `oren_task_cancel_now(...)`, `oren_task_cancel_wait(...)`, and
    `oren_task_cancel_after_wait(...)` across C, native, and AVM. Generator/coroutine typed stop execution
    still lives in stdlib rather than wholly in the runtime scheduler itself.
- Fresh landing (2026-04-23): source-level `@oren.coroutine` now also ships, but only as a narrow
  parser-level alias of `@oren.generator`:
  - named `fn` declarations, function-valued `var` bindings, and lambda-valued `var` bindings now
    accept `@oren.coroutine`
  - inside those declarations, `yield from ...` and `defer { ... }` now ride on the same shipped
    generator delegate/finalize protocol as `@oren.generator`
  - the lowering path is still the same compiler-managed generator wrapper / `oren_generator_start(...)`
  - metadata stays canonical on the generator contract (`generator_decl_surface.syntax=attr_oren.generator`)
  - runtime handle kind still remains `generator`
  - this closes the source-syntax gap without pretending there is already a separate coroutine
    object kind or metadata/runtime protocol
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
  - `oren_generator_cancel(target, reason)`
  - `oren_generator_request_cancel(target, reason)`
  - `oren_generator_is_started(gen)`
  - `oren_generator_is_done(gen)`
  - `oren_generator_is_closed(gen)`
  - `oren_generator_current_step(gen)`
  - `oren_generator_is_cancel_requested(target)`
  - `oren_generator_cancel_reason(target)`
  - `oren_generator_return_value(gen)`
  - `oren_generator_terminal_error(gen)`
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
  - metadata now reports this as `compiler_generator_object_v7` with
    `helper_api=oren_generator_start_v2`, `caller_api=generator_handle_v2`,
    `state_layout=dedicated_generator_object_kind_v1`, `worker_context_type=generator_context`,
    `cancel_api=oren_generator_cancel_v1`,
    `request_cancel_api=oren_generator_request_cancel_v1`,
    `started_api=oren_generator_is_started_v1`, `closed_api=oren_generator_is_closed_v1`,
    `current_step_api=oren_generator_current_step_v1`,
    `cancel_requested_api=oren_generator_is_cancel_requested_v1`,
    `cancel_reason_api=oren_generator_cancel_reason_v1`,
    `terminal_error_api=oren_generator_terminal_error_v1`,
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
  - the fill-vs-C disasm probe now emits per-category counts for the shipped four-wide body
    itself, so the next backend branch can be chosen from actual instruction mix instead of total
    counts alone. `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_064855_96771.log`
    and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_064900_96827.log` still show
    the landed Oren main iteration at `35` hot instructions for `4` outputs (`8.75` per element),
    but now quantify the per-output-element category mix too: Oren spends `stores 1.00`,
    `arith 2.75`, `moves 1.25`, `compare/tick 1.75`, and `branches 2.00`, while the host C vector
    ceiling through `LBB0_15` spends `stores 0.50`, `arith 5.00`, `moves 0.25`,
    `compare/tick 0.50`, and `branches 0.50` at `6.75` instructions per element. That sharpens the
    remaining backend work again: the gap is not “not enough arithmetic” by itself; it is the
    extra control/move/store overhead around Oren's serial recurrence, so future retries should
    only ship if they trade that control-state maintenance for more independent arithmetic work.
	  - the next narrower remaining-count control follow-up under that same shipped four-wide body is
	    now also closed negative. A temporary rerun kept the shipped safepoint spill width and store
	    shape intact, but replaced the carried `i` + recomputed `n - i` loop control with a carried
	    `remaining` count and reconstructed the final idx/count only at loop exit. The emitted loop
    still improved slightly: `build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_070103_440.log`
    and `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_070107_517.log` show the wide
    main iteration dropping from `35` hot instructions for `4` outputs (`8.75` per element) to
    `34` (`8.50` per element), and the per-output-element category mix only changes in arithmetic
    (`2.75 -> 2.50`) while `stores 1.00`, `moves 1.25`, `compare/tick 1.75`, and `branches 2.00`
    stay flat. The actual same-tree decision surface
    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-remaining-decision-20260423_065955_98963.log`)
    still does not justify keeping it: fill/share and exact `array_sum_int` improve slightly
	    (`default_fill_vs_c_vector ~2.2233×` vs enabled `~2.1710×`,
	    `default_array_ratio_median ~2.1913×` vs enabled `~2.1894×`), but exact `dot_product_int`
	    regresses (`default_dot_ratio_median ~1.7179×` vs enabled `~1.7739×`,
	    `decision_surface_alignment: agree`). That sharpens the remaining backend work again: the gap
	    is not an `n - i` bookkeeping issue by itself; future retries need a larger control/store
	    reduction or a stronger whole-program dot win.
	  - the next narrower peeled-tail control follow-up under that same shipped four-wide body is now
	    also closed negative on correctness before it even reaches the normal ranking surface. A
	    temporary rerun enabled
	    `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4_PEELED_TAIL=1` and peeled the scalar
	    remainder out of the wide body so the main iteration no longer paid the per-trip `< 4 left?`
	    check, but the enabled fill-share wrapper log
	    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-peeled-tail-decision-20260423_071903_4101.enabled-fill.log`)
	    failed because the generated `fill_list_int_oren_native` exits nonzero. The dedicated repro log
	    (`build/logs/verify_fill_list_int_repeat_stability_20260423_peeled_tail_repro_v1.log`) shows
	    the branch is repeated-invocation unsafe: `n=2000000 reps=1` still returns `11`, but
	    `n=2000000 reps=2` panics with `Index out of bounds`. That sharpens the remaining backend work
	    again: reject the peeled-tail branch on correctness, not merely on incomplete probe data.
	  - that peeled-tail failure also closed a verifier gap worth fixing permanently. The shipped
	    `make verify-native-list-int-fast-lowering` lane now honors `OREN_BENCH_ENV_BUILD_OREN` for
	    its arm64 builds and also runs the generated `fill_list_int` benchmark binary with
	    `2000000 2` as a repeat-stability runtime guard, so future fast-push experiments have to
	    survive repeated invocation before they can be treated as viable performance candidates.
	  - a spill-budget-neutral unroll4 no-wrap split is now also closed negative. The temporary
	    branch enabled `OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4_NOWRAP_SPLIT=1` and
	    guarded the current wrap-capable wide body behind a single `current < mod - 3*step` check so
	    the dominant no-wrap case stopped paying the shipped per-lane wrap-control sequence. The same
	    tree decision surface
	    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-nowrap-split-decision-20260423_074857_16234.log`)
	    still rejects promotion even though fill/share and exact `array_sum_int` move the right way
	    (`default_fill_vs_c_vector ~2.1517×` vs enabled `~1.7698×`,
	    `default_array_ratio_median ~2.1881×` vs enabled `~2.1519×`): exact `dot_product_int`
	    regresses across every sweep (`default_dot_ratio_median ~1.5254×` vs enabled `~1.7467×`).
	    The targeted verifier
	    (`build/logs/verify_native_list_int_fast_lowering_20260423_075050_17727.log`) passes, so the
	    branch is correct and repeat-stable; it is rejected only because the exact whole-program dot
	    surface still loses.
		  - the fill hot-loop probe itself is sharper now for this class of branch. When a wide loop
		    contains a dominant fast subpath plus a rare fallback block, the disasm/compare tooling now
		    measures the fast subpath instead of treating both as one static iteration body. The refreshed
		    nowrap-split logs
	    (`build/logs/perf-probe-arm64-list-int-fill-hot-loop-disasm-20260423_075358_18627.log`,
	    `build/logs/perf-probe-arm64-fill-vs-c-loop-compare-20260423_075357_18606.log`) now report
		    `main_iter_kind=split_fast_path` at `23` hot instructions for `4` outputs (`5.75` per
		    element), with per-element category mix `stores 1.00`, `arith 2.00`, `moves 0.00`,
		    `compare/tick 1.25`, and `branches 1.50`. That means the common fill-side path can now beat
		    the host C vector loop’s static `6.75` instructions per element and still lose the exact dot
		    surface, so the next retry must keep that dominant-path advantage without enough rare-wrap or
		    control-side cost to flip `dot_product_int` back the wrong way.
		  - the exact-program attribution gap for that same single-list fill family is now closed more
		    cleanly. `make perf-probe-arm64-fast-push-exact-fill-mix` now defaults to the causal
		    single-list set `array_sum_int,array_sum_int_step7` plus the non-causal `dot_product_int`
		    control, and the refreshed log
		    (`build/logs/perf-probe-arm64-fast-push-exact-fill-mix-20260423_081815_23618.log`) shows
		    both sum benchmarks are directly causal here (`fill_pushes_per_iter: 1`,
		    `single_list_unroll4_applicable: yes`) while `dot_product_int` is structurally outside this
		    branch family (`fill_pushes_per_iter: 2`, `single_list_unroll4_applicable: no`,
		    `ineligible_reason: pushes_per_iter!=1 blocks single_list_cursor/unroll4 gate`). Their
		    isolated fill streams are still mostly no-wrap (`array_sum_int 98.8000%`,
		    `array_sum_int_step7 98.0000%`, `dot_product_int` streams `99.2000%` and `98.0000%`), but
		    only the two single-list programs are causal for this family.
		  - the first exact single-list family decision surface is now in-repo too, and it does not
		    align with the fill/share-only story yet. The new target
		    `make perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision` keeps the
		    existing fill/share surface but ranks exact programs as causal single-list benchmarks
		    (`array_sum_int,array_sum_int_step7`) plus the separate non-causal `dot_product_int`
		    control. Its first summary
		    (`build/logs/perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision-20260423_082026_25099.log`)
		    shows fill/share still prefers the shipped default (`default_fill_vs_c_vector ~2.0473×` vs
		    disabled `~2.3812×`), while both causal exact programs slightly prefer `disabled` on steady
		    native/C (`array_sum_int ~2.0855×` vs `~2.0782×`, `array_sum_int_step7 ~2.0855×` vs
		    `~2.0782×`) and the non-causal control also slightly prefers `disabled`
		    (`dot_product_int ~5.1433×` vs `~5.1370×`). That means the next single-list iteration should
		    first reconcile the causal steady surface with the fill/share surface rather than immediately
		    resume narrower control-form tuning.
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
    - `version = 23`
    - `resume_surface = "next_send_finalize_defer_close_cancel_delegate_yield_from_v9"`
    - `on_finalize_api = "oren_generator_on_finalize_v1"`
    - `on_finalize_mode = "lifo_zero_arg_on_done_or_close_v1"`
    - `on_close_api = "oren_generator_on_close_v1"`
    - `on_close_mode = "alias_of_on_finalize_v1"`
    - `close_api = "oren_generator_close_v1"`
    - `cancel_api = "oren_generator_cancel_v1"`
    - `request_cancel_api = "oren_generator_request_cancel_v1"`
    - `cancel_requested_api = "oren_generator_is_cancel_requested_v1"`
    - `cancel_reason_api = "oren_generator_cancel_reason_v1"`
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
the default native runtime too, including scheduler-aware host-green waiting on the final
`resume_ch` receive. The next pass should stop widening helper mechanics and instead tackle the
real remaining boundary: true caller-visible coroutine/generator semantics and stronger
scheduler-aware exchange/cancellation protocol above the current helper contracts.

That path keeps the current repo state honest:

- `yield` statement sugar is shipped
- local value-stable `yield <value>` / expression `yield` is shipped
- explicit caller-visible `oren_yield_exchange(yield_ch, resume_ch, v)` is shipped
- raw `oren_yield()` remains available as a low-level helper
- full coroutine/generator semantics are still backlog, but the next work can start from the actual
  runtime seams and the now-proven helper surfaces above instead of rediscovering them in chat
