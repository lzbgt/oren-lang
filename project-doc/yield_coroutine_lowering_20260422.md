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
- Fresh probe (2026-04-22): strict bytecode/C/native builds also execute a bare `yield` inside a
  nested function-literal body successfully. Parent-function metadata still intentionally ignores
  nested bodies when summarizing `contains_yield` / `yield_stmt_sites`; that probe result is about
  execution support, not about attributing the nested body to the enclosing function.

That boundary is deliberate, not accidental.

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

## Recommended next step

For the remaining language feature backlog, the best next slice is still **Option B**, but now on
top of the shipped helper surface instead of in place of it:

1. detect functions that contain `yield`
2. define an explicit internal frame/state representation
3. lower caller-visible resumable value flow next:
   - distinguish local `oren_yield_value(v)` helper semantics from true yielded-value channels
   - define where a resumed function receives caller-supplied values, if the language wants them
   - keep the backend-shared rule explicit instead of inheriting raw helper return codes
4. extend metadata/introspection only when it can honestly model value-carrying sites too

The first lowering pass already executes the current AVM bare-statement subset end-to-end, and
backend parity for the same subset is guarded across bytecode/C/native. The helper-based value
surface is also now parity-guarded. The next pass should stop widening syntax and instead tackle
the real remaining boundary: true caller-visible coroutine/generator semantics beyond “yield, then
resume with the same local value”.

That path keeps the current repo state honest:

- `yield` statement sugar is shipped
- local value-stable `yield <value>` / expression `yield` is shipped
- raw `oren_yield()` remains available as a low-level helper
- full coroutine/generator semantics are still backlog, but the next work can start from the actual
  runtime seams and the now-proven helper surface above instead of rediscovering them in chat
