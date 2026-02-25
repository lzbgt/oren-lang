# Runtime GC Alloc Split — Design Note

**Date:** 2026-02-25

## Goals

- Reduce `lib/runtime_native/100_time_gc_alloc.oren` below ~2000 lines by splitting into focused modules.
- Preserve existing GC/alloc behavior and tracing hooks.
- Keep include order deterministic for runtime initialization.

## Non-goals

- No behavioral changes to GC/alloc/reuse logic.
- No new tracing or diagnostics.

## Proposed module layout

1) `lib/runtime_native/100_time_gc_alloc_trace.oren`
   - Alloc-site counters, list/header tracking, alloc-index timing.

2) `lib/runtime_native/100_time_gc_alloc_index.oren`
   - Alloc index table + static-kind tracking + cstr0 literal membership.

3) `lib/runtime_native/100_time_gc_alloc_core.oren`
   - Locks, tracking, reuse, roots, pinning, and `oren_find_node`.

4) `lib/runtime_native/100_time_gc_alloc.oren`
   - Wrapper include file (orders the above modules).

## Validation

- Run `make test` (default <3 min gate).
- No fixture changes expected.
