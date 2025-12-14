# Memory Model

Oren’s default stance is automatic management on desktop/server targets, with a deterministic/manual lane for embedded/bare-metal.

## Modes
- **Auto-managed (default)**: desktop/server builds keep the current tracked heap + mark/sweep collector. GC triggering is manual today (`oren_gc_collect`), but the plan is to make it opportunistic (safepoints) once the native backend hooks are in place.
- **Deterministic/Manual**: set `--no-gc` / `OREN_NO_GC` to disable scanning. You keep ownership explicit (`oren_free`) and still get shutdown cleanup. This is the intended path for STM32-style targets where pauses aren’t acceptable.

## What is managed
- Strings, lists, and maps created by the C backend (`lib/runtime.c`) are registered in an allocation table. They are freed automatically on `oren_shutdown()` and can be reclaimed eagerly with `oren_gc_collect()` (mark/sweep from registered roots).
- Manual reclamation is available through `oren_free(value)`; this is useful for large temporaries or deterministic teardown.
- Command-line arguments are stored in a tracked list so they are cleaned up with the rest of the runtime.

## Roots & collection
- Roots are any `OrenValue*` slots passed to `oren_register_root(slot)`; they are unregistered via `oren_unregister_root(slot)`. Globals emitted by the transpilers register automatically.
- The collector is cooperative: call `oren_gc_collect()` at safe points to reclaim unreachable tracked allocations. If you never call it, shutdown will still free tracked blocks.

## Disabling GC
- Builds can disable GC scanning by defining `OREN_NO_GC` (or passing `--no-gc` to the CLI). Roots/mark-sweep become no-ops, but the runtime still tracks allocations so `oren_free` and shutdown cleanup continue to work.
- This is the recommended configuration for constrained/embedded targets (e.g., STM32) where you want deterministic ownership without a runtime collector pause.

## Thread Safety
- List/map operations in the C runtime take a coarse mutex, so concurrent reads/writes across threads are serialized. This is a stopgap; per-object or lock-free structures plus GC safepoints are planned for the full concurrency story.

## Limitations & next steps
- Native backend allocations currently use `mmap` directly and sit outside the managed heap; only C-backend objects participate in GC today. Block-scoped stack cleanup is in place to avoid frame leaks inside loops, but native heap accounting + GC integration still need to land.
- Native backend now uses a bump-pointer heap with `mmap` growth (64KB granularity) but still lacks tracing/roots; GC hooks are stubbed and reclaiming native allocations remains a future milestone.
- Collection locking is coarse; per-object locking or lock-free structures plus concurrent-friendly GC are still needed.
- The collector is stop-the-world and must be invoked explicitly; automatic triggers and per-frame root tracking are planned.
