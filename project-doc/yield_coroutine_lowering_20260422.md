# Yield / Coroutine Lowering Notes (2026-04-22)

This note records the current `yield` implementation boundary after the first shared-front-end
syntax slice landed.

## Current shipped state

- Bare statement `yield` is now shared-front-end sugar that lowers directly to `oren_yield()`.
- `yield <value>` is intentionally rejected.
- Expression-position `yield` is also intentionally rejected.

That boundary is deliberate, not accidental.

## Existing runtime / backend seams

### 1. AVM already has a dedicated yield opcode

Source: [lib/compiler/codegen_bytecode/010_codegen_a.oren](../lib/compiler/codegen_bytecode/010_codegen_a.oren)

- `oren_yield()` lowers to `AVM_YIELD`.
- Bytecode codegen then pushes canonical `nil` so expression contexts stay stack-balanced.

Implication:

- In AVM, `oren_yield()` behaves like a statement-like primitive whose value surface is `nil`.

### 2. Native `oren_yield()` is a runtime helper, not a normalized language value surface

Source: [lib/runtime_native/262_yield.oren](../lib/runtime_native/262_yield.oren)

- Native `oren_yield()` routes to `oren_green_yield()` when inside a green task.
- Otherwise it falls back to `sys_sched_yield()`.
- Native tests currently treat the low-level helper as returning `0` on success.

Implication:

- Raw `oren_yield()` is not currently cross-backend value-stable:
  - AVM view: `nil`
  - native view: scheduler/OS return code (`0` on success in current tests)

This is the main reason expression-position `yield` should not be silently lowered to raw
`oren_yield()` today.

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

## Why expression `yield` is not the next safe step

Without further work, lowering:

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

That is worse than a loud parser error because it looks portable while being silently divergent.

## Credible next implementation options

### Option A: normalize a backend-shared helper first

Introduce a helper whose language-visible value is always `nil` after yielding, then lower
expression-position `yield` to that helper.

Pros:

- small step
- keeps parser/user surface moving

Cons:

- still does **not** solve resumable/value-yield semantics
- risks spending time on sugar that gets replaced once real coroutine lowering lands

### Option B: add an explicit lowering pass for resumable functions

Treat `yield` as a lowering trigger and rewrite a function into:

- a frame/state record
- a state discriminator / resume switch
- explicit storage for locals that live across yield points

Pros:

- matches the documented long-term direction
- solves `yield <value>` and resume semantics at the right layer

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

For the language feature backlog, the best next slice is **Option B**, starting with compiler
infrastructure instead of more parser sugar:

1. detect functions that contain `yield`
2. define an explicit internal frame/state representation
3. lower one narrow subset first:
   - no closures
   - no `defer`
   - no `yield <value>`
   - only bare `yield`
4. keep expression/result-yield rejected until the frame model exists

That path keeps the current repo state honest:

- `yield` statement sugar is shipped
- raw `oren_yield()` remains available as a low-level helper
- full coroutine semantics are still backlog, but the next work can start from the actual runtime
  seams above instead of rediscovering them in chat
