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

- Fresh landing (2026-04-22): the first compiler-managed handle is now intentionally opaque at the
  language contract level instead of merely “not documented”. The injected core now uses hidden
  list capsules (`hidden_list_capsule_v2`) and validates both generator handles and generator
  contexts before `next/send/collect` or `yield ... in co` proceed.
  Concretely:
  - the generator substrate no longer depends on map semantics at all; both `generator` handles and
    `generator_context` now live on hidden list capsules recognized by `oren_type_name(...)`
  - old public lifecycle fields like `yield_ch`, `resume_ch`, `done_ch`, `worker`, `args_list`,
    `task`, `started`, `done`, and `return` are no longer part of the supported generator surface
  - worker bodies should treat `co` purely as a `generator_context`; `yield ... in co` is the only
    supported worker-facing exchange API
  - metadata now reports this as `compiler_generator_object_v2` with
    `helper_api=oren_generator_start_v2`, `caller_api=generator_handle_v2`,
    `state_layout=hidden_list_capsule_v2`, `worker_context_type=generator_context`,
    `iter_surface=for_in_v0`, `iter_api=oren_iter_next_v0`, `iter_resume=implicit_nil_v0`, and
    `decl_forms=["named_function_decl","function_valued_var"]`

- Fresh landing (2026-04-22): generator handles now participate in generic `for x in iterable`
  sugar too, without changing the public handle layout again. The compiler-generated bridge:
  - recognizes `generator` handles before normal `oren_iter_next(...)` fallback
  - advances them through `oren_generator_next(...)`
  - adapts generator steps to the iteration pair contract `[ok, value]`
  - resumes every step with implicit `nil`
  This means the current surface is good for plain producer-style generators that do not require
  non-`nil` caller input between yields, while `gen.send(...)` remains the richer manual protocol.

- Reverted landing (2026-04-22): attempted richer generator composition through
  `oren_generator_delegate(...)` is not shipped after stage2 repro reduction exposed a self-hosted
  bytecode compile regression. Facts from the reduced probes:
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
  This remains the next real resume/composition task above the shipped `for-in` / `next` / `send`
  surface, but it is intentionally not documented as available until the compiler path is fixed.

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
