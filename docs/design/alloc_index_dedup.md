# Alloc Index De-dup for `track_alloc_new` — Design Note

**Date:** 2026-02-26

## Goal

Avoid duplicate tracking nodes when `oren_track_alloc_new(ptr, size, kind)` is called on
an already-tracked pointer (reuse or stale index scenarios). This reduces alloc-index
skew, lowers probe pressure, and prevents container headers from being temporarily
"untracked" due to index drift.

## Non-goals

- No redesign of reuse lists or GC marking logic.
- No changes to list/map header layouts or container semantics.
- No new tracing hooks (unless needed for correctness diagnostics).

## Approach

1) In `oren_track_alloc_new`, after initializing the alloc-index and acquiring the
   lock, probe the alloc-index for `ptr`.
2) If a live node exists:
   - Update size/kind if provided.
   - Clear freed/marked flags.
   - Reinsert the node into the alloc index to refresh hashing.
   - Preserve auto-GC accounting behavior.
   - Return early (do not allocate a second node).
3) If no node exists, follow the existing `track_alloc_new` path.

## Rationale

`oren_track_alloc_new` is emitted directly by native backend codegen after allocation.
In reuse or churn-heavy scenarios, the same pointer can reappear while the alloc-index
still holds a live node. Creating a duplicate node wastes memory and can desynchronize
index lookups, causing false "untracked" detections in container checks.

## Validation

- `make test`
- GC-stress quick integration (see `test-native-quick-gc-stress-stage2` target).

## Operational guidance (caps)

`OREN_TRACE_ALLOC_INDEX_DEDUP_CAP` is a **trace-only** guardrail. Choose a cap
based on observed dedup behavior in your current workload rather than a fixed
hard-coded number:

1) Run a representative stress test with tracing enabled:
   - `OREN_TRACE_ALLOC_INDEX=1` (optionally with `make test-native-quick-gc-stress-stage2`).
2) Record `dedup_hits` from the `[alloc_index]` line in the log.
3) Set `DEDUP_CAP` to a safe multiple of the observed peak (e.g., 2–4×) so normal
   churn does not trip the guardrail, while true regressions still surface quickly.

Helper:

- `scripts/suggest_alloc_index_dedup_cap.sh [--run] [log_path]`
  - Runs GC-stress (optional) and suggests a cap from `dedup_hits` with a configurable
    multiplier (`DEDUP_CAP_MULT`, default 4).
