# Active Tracker (Rolling)

**Last updated:** 2026-02-19

This file tracks the **highest‑leverage work** to make Oren mature and performance‑competitive with C
across the C, native, and OBC/AVM backends. Keep it short and action‑oriented.

## How to use this tracker

- Start at **P0 (Now)** and take the first unfinished item that blocks Tier‑1 parity/perf.
- Keep tasks tied to a **regression gate** (benchmark or test) so work stays measurable.
- If a task is “done enough” in rolling mode, summarize the result and move on (don’t archive here).

Legend:

- Priority: **P0 (Now)** > **P1 (Soon)** > **P2 (Later)**
- Weight: **W5 (highest impact)** → **W1 (lowest impact)**
- Size: **(S/M/L)** = expected scope

## Maturity definition (rolling, measurable)

Oren is “mature” when all are reliably true on Tier‑1 targets (`arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`):

- **Buildability:** stage0→stage1→stage2 works with minimal manual setup.
- **Semantic parity:** native/C/bytecode behavior matches the language spec (fixtures prove it).
- **Performance budgets:** hot‑loop and allocation benchmarks are within target ratios vs C.
- **Docs fidelity:** manuals/spec/status reflect real behavior (fixtures are the living spec).
- **Stdlib quality:** NET/TLS/HTTP/WS are correct and bounded under loopback tests.

## Regression gates (run first when touching compiler/runtime)

Local (fast):

- `make test`
- `make verify-native-quick`
- `./scripts/verify_x64_linux_qemu_smoke.sh`

Tier‑1 cross‑arch:

- `./scripts/verify_native_matrix.sh` (use `--skip-remote` if remote is down)
- `./scripts/verify_native_net_matrix.sh`
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
- `./scripts/verify_stage0_windows_bootstrap.sh`

## Performance parity tracker (weighted, 2026‑02‑19 baseline)

Baseline reference: `benchmarks/RESULTS_LATEST.md` (M2 Pro, 2026‑02‑19).
Weights reflect expected impact on C parity + breadth of affected code.

1) **W5 — Native integer hot‑loop parity (loop_sum, dot_product)** (L)
   - Expand `inty` propagation + arithmetic fast paths to avoid runtime helpers in tight loops.
   - Ensure native fastmod handles constant RHS and known‑literal mod vars.
   - Gate: native `loop_sum` and `dot_product` ≤ 2× C on arm64 + x64.

2) **W5 — Allocation/GC overhead reduction (alloc_churn/alloc_drop)** (L)
   - Fix and enable reuse paths (`OREN_GC_REUSE_BLOCKS`) when correct.
   - Reduce per‑alloc metadata overhead; add slabs for hot small objects.
   - Gate: native `alloc_churn` ≤ 8× C; native `alloc_drop` ≤ 5× C; Oren C `alloc_churn` ≤ 5× C.

3) **W4 — List reserve + fast push** (M)
   - Reserve insertion works for literal bounds (list<int> wired in C/native); extend to computed bounds.
   - Route compiler‑proven lists to unchecked push when safe.
   - Gate: native `array_sum` and `multi_list_push_int` ≤ 2× C.

4) **W4 — Tagged value representation convergence (native/C/AVM)** (L)
   - Converge on a canonical tagged representation (no heuristic tagging).
   - This unlocks faster comparisons + removes many fallback paths.
   - Gate: no semantic regressions in `make test` + cross‑backend fixtures.

5) **W3 — SIMD/typed‑buffer parity on native (x64 + arm64)** (M)
   - Ensure list<int>/typed buffers lower to SIMD kernels.
   - Bring up x64 SIMD baseline (SSE2) with scalar‑equivalence gates.
   - Gate: native `dot_product_int` ≤ 2× C.

6) **W3 — AVM allocation fast paths + typed buffers** (M)
   - Arena/slab alloc for short‑lived lists/structs.
   - Ensure typed buffers + vector ops are available without JIT.
   - Gate: OBC `alloc_churn` ≤ 10× C; AVM SIMD test suite passes.

7) **W3 — AVM unboxed list<int> payload + opcode lowering** (M)
   - Implement list<int> payload + compiler lowering for OBC (see collections design).
   - Gate: `list_int` fixtures + OBC perf parity for dot/sum loops.

## P0 (Now)

1) **Native scheduler / GMP M:N groundwork** (L, W4)
   - Keep syscall‑first, no‑libc/pthreads constraints.
   - Ensure green scheduling correctness across sleep/IO waits.
   - Gate: `make test` + `verify_native_matrix.sh` (all Tier‑1).

2) **Perf parity W5 items** (L, W5)
   - Execute items 1–2 in the weighted tracker above.

3) **Tagged value convergence plan** (L, W4)
   - Define the canonical tagged layout + staged migration plan.
   - Gate: fixtures + backends converge without heuristic fallbacks.

## P1 (Soon)

1) **Reserve + unchecked push generalization** (M, W4)
2) **SIMD/typed buffer bring‑up on x64** (M, W3)
3) **AVM allocation slabs + list<int> lowering** (M, W3)
4) **Tooling reliability: SSH/scp timeouts in verify scripts** (S, W2)

## P2 (Later)

1) **Allow non‑macOS hosts for partial targets** (S, W2)
2) **Package manager / signed module workflow** (M, W2)
