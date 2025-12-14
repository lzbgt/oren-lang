# Memory Model

Oren currently ships with a simple managed heap for runtime values and an opt-out build flag for bare-metal/embedded work.

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
- Native backend struct/stack allocations are not yet wired into the managed heap; only C-backend objects participate in GC today.
- Collection locking is coarse; per-object locking or lock-free structures plus concurrent-friendly GC are still needed.
- The collector is stop-the-world and must be invoked explicitly; automatic triggers and per-frame root tracking are planned.
