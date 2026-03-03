# Runtime GC Alloc Split — Design Note

**Date:** 2026-03-03

## Goals

- Reduce `lib/runtime_native/100_time_gc_alloc.oren` below ~2000 lines by splitting into focused modules,
  including a smaller core split for reviewability.
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
   - Wrapper for focused core submodules:
     - `100_time_gc_alloc_core_scan_reuse.oren` — stack scan + reuse + root helpers
     - `100_time_gc_alloc_core_list_hdr.oren` — list header validation + ring dumps
     - `100_time_gc_alloc_core_track.oren` — locking + alloc tracking fast paths
     - `100_time_gc_alloc_core_roots_gc.oren` — root registration + find + GC collect

4) `lib/runtime_native/100_time_gc_alloc.oren`
   - Wrapper include file (orders the above modules).

## Validation

- Run `make test` (default <3 min gate).
- No fixture changes expected.
