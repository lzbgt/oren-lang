# Yield / Generator / Coroutine Current State

**Updated:** 2026-05-26

This note keeps only the current implementation boundary. Historical probe logs were
removed from this file; use git history and `build/logs/` for raw evidence.

## Shipped Surface

- Bare statement `yield`.
- Value yield: `yield <value>`.
- Explicit exchange syntax:
  - `yield expr in (yield_ch, resume_ch)`
  - `yield in (yield_ch, resume_ch)` for implicit `nil`.
- `std:generator` facade over compiler-managed generator handles/contexts.
- `std:coroutine` facade over the same handle/context contract.

## Compiler Metadata

`oren meta`, `dump linked`, and embedded OBC metadata expose the current yield surface:

- `contains_yield`
- `yield_lowering`
- `yield_lowering.lowering_v0`
- `yield_lowering.prepared_v0` for the ready bare-yield subset
- `contains_yield_value`
- `yield_value_surface`
- `contains_yield_exchange`
- `yield_exchange_surface`

The metadata is intentionally factual. It does not claim a full caller-visible resume
channel unless the explicit exchange helper/syntax is used.

## Backend Behavior

- The bytecode backend consumes `prepared_v0` for the ready bare-yield subset.
- C and native currently execute the same shipped helper surface rather than the explicit
  bytecode lowering path.
- Cross-backend verifier coverage exists for the current bare-yield, value-yield, and
  exchange helper surfaces.

## Generator Facade

`std:generator` standardizes the worker shape:

```text
worker(co, args_list)
```

Worker-facing exchange uses `yield [expr] in co`. Handle operations include `start`,
`next`, `send`, `is_started`, `is_done`, `current_step`, `return_value`, and `collect`.

## Coroutine Facade

`std:coroutine` exposes the matching coroutine-oriented operations: `start`, `resume`,
`next`, `send`, `on_finalize`, `on_close`, `close`, `cancel`, `request_cancel`,
`delegate`, `delegate_step`, state queries, terminal result/error access, and collection.

## Cancellation Contract

- `request_cancel(target, reason)` records a sticky request.
- `cancel(target, reason)` records that request and then forces deterministic close.
- `is_cancel_requested(target)` and `cancel_reason(target)` expose state.
- The first request wins and propagates down the active delegated child chain.

## Current Blockers

- The generator/coroutine ABI is still rolling.
- Task-group policy factoring is blocked by a bytecode latency-sensitive live-runtime
  preflight issue; do not route task-group runtime validation through `std:task` helpers
  until that latency issue is removed.
- Future work should keep verifier coverage focused on observable backend parity rather
  than adding large rolling-history docs.
