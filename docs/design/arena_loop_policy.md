# Loop Arena Policy + GC Reuse Safety (Design)

**Last updated:** 2026-02-24

This design defines the loop-arena policy needed to close the allocation/GC
performance gap while keeping correctness and determinism intact.

---

## Goals

- Reduce per-iteration allocation cost in hot loops (`alloc_churn`, `alloc_drop`).
- Keep GC reuse safe and deterministic (no reuse of arena-owned memory).
- Preserve cross-backend semantics and existing fixtures.
- Make the policy observable and debuggable with existing trace flags.

## Non-goals

- ABI/opcode stabilization (still rolling).
- Rewriting the allocator or GC from scratch.
- Changing list semantics or value layout beyond the policy below.

## Current facts (rolling)

- Auto loop arenas exist and can be disabled at runtime with
  `OREN_ARENA_AUTO_LOOP=0` via `oren_arena_new_list_auto`.
- List headers are arena-backed by default in benchmark builds; list-track
  traces confirm `arena_alloc` events in `alloc_churn`.
- Per-iteration loop scopes now use `oren_arena_iter_push/pop` and can apply
  a per-iteration cap via `OREN_ARENA_ITER_CAP_BYTES` (rolling).
- `OREN_TRACE_ARENA=1` now reports per-iter counters (`iter_push/pop`, `iter_spills`,
  `iter_spill_bytes`) to diagnose cap behavior (rolling).
- GC reuse and list header integrity are still rolling; reuse is guarded and
  tracing is available (`OREN_TRACE_GC_REUSE`, `OREN_TRACE_LIST_TRACK`, etc.).

(See `docs/STATUS.md` for the latest perf baselines and trace knobs.)

---

## Policy: per-iteration loop arenas

### Core idea

Treat each hot loop iteration as a short-lived arena frame. The arena frame:

1) Allocates list/list_int headers and buffers for that iteration.
2) Spills to GC only when the arena frame exhausts its quota.
3) Resets at iteration boundary (epoch), making most allocations O(1) to reclaim.

### Ownership rules

- **Arena-owned memory**: not visible to GC reuse; freed by arena reset only.
- **GC-owned memory**: eligible for reuse, guarded by existing GC reuse checks.
- **Spilled allocations**: go to GC when arena capacity is exceeded.

### Determinism constraints

- Arena reset happens at deterministic loop boundaries.
- Spill behavior is deterministic given the same inputs and thresholds.

---

## Proposed architecture (incremental)

### Phase 0: observability (already in place)

- Keep `OREN_TRACE_LIST_TRACK=1` and `OREN_TRACE_GC_REUSE=1` available.
- Ensure benchmarks can force GC-tracked list headers with
  `OREN_ARENA_AUTO_LOOP=0`.

### Phase 1: explicit per-iteration arenas (rolling)

- Introduce a loop-iteration arena frame with:
  - a fixed byte budget per iteration,
  - a spill counter,
  - an epoch id.
- Reset the frame at the end of each loop iteration.
- Ensure list/list_int reserve/push use arena-backed buffers when the header
  is arena-owned.

### Phase 2: spill + reuse interaction

- When the arena frame spills, allocate via GC and record a spill marker.
- GC reuse must ignore arena-owned blocks entirely.
- Reuse can operate on spilled allocations with existing guards.

### Phase 3: steady-state tuning

- Calibrate arena budget and spill thresholds using `alloc_churn` and
  `alloc_drop` baselines.
- Target: `alloc_churn` <= 8x C, `alloc_drop` <= 5x C on Tier-1.

---

## Invariants and checks

- List headers from arenas must be tagged as arena-owned for tracing.
- GC reuse must never accept arena-owned blocks.
- Any list header integrity guard failure must emit trace context
  (alloc site + header snapshot).

---

## Tests and gates

- `make test` must remain green.
- Perf gates from `docs/STATUS.md` (alloc_churn/alloc_drop).
- Add a targeted fixture when a deterministic repro for list header corruption
  is available (currently rolling investigation).

---

## Open questions

- Arena budget heuristic: fixed size vs adaptive per-loop feedback.
- Spill threshold for large buffers (list reserve growth).
- Whether to introduce a separate arena for list buffers vs headers.

---

## Next steps

1) Validate per-iteration cap behavior under `alloc_churn`/`alloc_drop`.
2) Add per-loop spill accounting if the global counters are too coarse.
3) Re-run `alloc_churn`/`alloc_drop` with arena auto on/off to confirm deltas.
