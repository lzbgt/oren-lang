# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode.

This file is the *single source of truth* for what to do next.

Priority model:

- **Order = priority.** The first unfinished item is the most urgent.
- We intentionally avoid fixed labels like “P0/P1”: the list is continuously reordered as reality changes.
- Completed items are moved to `docs/TODOS_ARCHIVE.md` to keep this file readable.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).
- Roadmap driver: production **server-side HPC** requirements (Eigen/BLAS-like workloads), see `docs/HPC_SERVER_PLAN.md`.

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims for the native backend** `[arch]`
   - **Native backend output** must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - The **C backend / C AVM** may use `libc` during bootstrap (like a normal C program), until the Oren-native runtime is complete.
   - Native runtime primitives must be implemented via `sys_*` + repo-owned ABI tables + `.oren` code (no host SDK dependence).

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - If code changes: run the canonical suite (preferred) `./oretest --target macos` (or `make test`).
   - If **docs-only** changes (only documentation files modified): tests are not required.
     - Allowed docs-only set: `docs/*`, `README.md`, `LICENSE`.

6) **Keep this file actionable** `[maint]`
   - Each item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list *short and top-down prioritized* (target ~10–20 items max); merge and archive aggressively.
   - Repo must build from a clean clone: ignore build outputs only (do not accidentally ignore source dirs like `cmd/oren/` or `cmd/oretest/`).

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.
   - Do not wipe the container workspace by default; incremental builds must be possible (use an explicit clean flag when required).
   - Prefer syncing **tracked sources only** (git index) into `/work/repo` so host-built binaries never pollute the container workspace.
   - If you add new files, you must `git add`/commit them before running the docker suite (otherwise the container won't see them).
   - Forward feature flags via env (e.g. `OREN_TEST_FULL=1`) so Linux matches macOS runner behavior.
   - Remove stale build outputs (`oren`, `oretest`, `avm`) before running `make` to avoid timestamp skew from tar sync.

8) **Never generate `*.oren.c` next to sources** `[maint]`
   - `./oren_bootstrap build path/to/file.oren` writes `file.oren.c` next to sources; Make may then treat the source as a build target via implicit C rules.
   - Avoid running bootstrap builds on in-tree modules/tests/tools; prefer `./oren build ... -o build/...` or the curated runners (`make test`, `./oretest`).
   - If you *did* create `*.oren.c` artifacts, delete them before running `make test` (keep `oren.oren.c` only).

9) ** Refactor in rolling **
  - when a file is over 2000 lines, refacotor to be SOLID principles applied modules

10) **Tests must target public tool surfaces** `[maint]`
   - Avoid importing `lib/compiler/*` inside `.oren` tests (couples tests to compiler internals).
   - Prefer using `./oren` subcommands (`build`, `meta`, etc.) and checking outputs via `cmd/oretest` fixtures.

## Tasks (Priority Order: Top = Next)

### A) Language + Compiler (primary focus)

1) **[lang][perf] Generics + monomorphization (HPC enabler)**
   - DoD:
     - Parse + lower generic function definitions (syntax TBD, but must be unambiguous)
     - Monomorphize at compile time (no runtime overhead in hot loops)
     - Allow simple constraints via `trait` (compile-time only v0)
     - Add a small integration test that compiles a generic `dot<T>` for `i32` + `f32`

2) **[lang][perf] Allocator control for large numeric buffers**
   - DoD:
     - Add an explicit “unscanned / raw bytes” allocation mode for typed buffers (avoid GC scanning and pointer false-positives)
     - Support aligned allocation (arm64 NEON-friendly)
     - Expose as `std/buffer` API (portable across C/native/AVM where feasible)

3) **[lang][perf] SIMD surface + dispatch boundary (arm64 NEON first)**
   - DoD:
     - Define a stable intrinsic boundary (compiler-known names) for vector kernels
     - Add feature gating + scalar fallback (deterministic)
     - Expand `std/linalg` kernels safely (keep reference implementations)

### B) AVM (evolves alongside language/compiler)

1) **[vm][safety] Snapshot/restore format hardening + stability knobs**
   - DoD:
     - snapshot includes full VM state and validates on load
     - hash-friendly, chunkable layout (for swarm consensus + dedupe)
     - clear “rolling vs stable” policy for snapshots (separate from `.obc`)
     - include record/replay-bytes state + log budget counters so pause/resume does not lose determinism data (**done**)
     - include VM configuration + virtual backend state (e.g. `fs_backend_kind` + VirtualFS contents) so resume does not accidentally touch host (**done**)
     - tasks/channels:
       - **v0:** explicitly forbid snapshot when `vm->sched != NULL` (**done**, exit code becomes `3` when `--snapshot-out` is requested on a paused run)
       - **v1:** add full scheduler snapshot support (tasks + channels) so spawned workloads can be paused/resumed

2) **[boot][arch] Compiler-in-AVM (close the loop)**
   - DoD:
     - AVM ingests `.oren` (BYTES/VirtualFS), compiles to `.obc`, executes in a child universe
     - sandboxed module loader rules + governance hooks
     - produced `.obc` is hash-addressable for swarm validation

### C) Libraries + Ecosystem (important, but not blocking core correctness)

## Recently Completed (high signal)

- See `docs/TODOS_ARCHIVE.md` for detailed history.
- C backend: added `u8_buf` type and made `oren_bytes_get_*` / `oren_bytes_set_*` accept both `list<int>` and `u8_buf`; added module coverage (`test_u8_buf_bytes_helpers`) and verified on macOS + Linux docker.
- Numeric literals: added `_` separators and `0x`/`0b`/`0o` base-prefixed int literals across lexer + optimizer + bytecode + native backend + C backend; added module + AVM coverage; verified on macOS + Linux docker.
- `std/buffer` views: switched slice/matrix views from map-based records to fixed-position lists to reduce hot-loop overhead; verified on macOS + Linux docker.
- Generic-call specialization sugar v0: added `f[T](...) -> f__T(...)` lowering (conservative: only for declared functions) with module + AVM coverage; verified on macOS + Linux docker.
- AVM: added `test_map_iter_deterministic` to pin deterministic map key iteration under deny-by-default mode.
- Casting overflow semantics: made `oren_trunc_int` deterministic clamp (`NaN→0`, `+inf/overflow→INT64_MAX`, `-inf/overflow→INT64_MIN`) across C runtime + AVM native intrinsics; updated docs and added module coverage.
- Iteration: added `for x in <typed_buf>` support for `i32/i64/f32/f64` buffers in C runtime + native runtime; added module coverage and wired it into oretest curated lists.
- Attributes v1: allow `@pack`/`@abi` and canonicalize `@json.*` to `serde.*`; preserve unknown attrs; support attrs + doc comments on vars; accept attrs inside blocks; `oren meta` now exports `globals[]` with attrs; covered by oretest meta fixture + native integration suite; verified on macOS + Linux docker.
- `bitcast[T](x)` v0: added lowering + runtime helpers for `u32/f32/u64/f64` bit reinterpretation; fixed unary `-` lowering to preserve float `-0.0`; covered by a module test; verified on macOS + Linux docker.
- `std/math` rounding v0: added deterministic `floor/ceil/round` (half-away-from-zero, NaN->Err); covered by a module test including `-0.0` bit preservation.
- `std/time` v0: added `lib/std/time.oren` (UTC ISO-8601 parse/format, epoch conversions, monotonic/unix clocks, sleep); added runtime TIME primitives and a module test; verified on macOS.
- AVM record/replay v1: portable log format with file + in-memory logs; effectful domains replay from logs (no host effects); deterministic TIME/RNG supported; covered by AVM tests.
- AVM deterministic cooperative tasks: task scheduler + `yield`/spawn/join/select primitives; deterministic step-quantum via `AVM_TASK_QUANTUM`; covered by AVM tests.
- AVM snapshots v5: snapshot now preserves in-memory record/replay logs + budget counters; snapshot explicitly rejects tasks/channels state (until scheduler snapshot is implemented); covered by AVM tests.
- AVM state hash: `STATE_HASH` now incorporates policy/config + virtual backend fixtures (VFS/VPROC/VNET) so host vs virtual execution cannot collide; covered by an AVM test and an oretest assertion; verified on macOS + Linux docker.
- Casting: allow float→int cast sugar (`u8(1.9)`) via `oren_trunc_int`; allow `f32(16777217)` via numeric coercion; updated typecheck + tests; verified on macOS + Linux docker.
- Typed buffers + views: C backend runtime primitives in `lib/runtime_buf.c`, `std/buffer`, and an integration module test; fixed top-level var init ordering in the C backend; verified on macOS + Linux docker.
- `std/linalg` v0.2: added typed-buffer APIs + runtime AXPY intrinsics; arm64 NEON fast paths for i32 dot/reduce; fixed signed-overflow UB in i32 dot/reduce; verified on macOS + Linux docker.
- GC registry scaling: replaced linear `oren_find_node()` lookup with a pointer-indexed hash table and added a GC stress module test; verified on macOS + Linux docker.
- Iteration (stream-like): added `lib/std/iter.oren` (`range` / `range3`) implemented via an “iterable map” protocol in `oren_iter_next` across C runtime, native runtime, and AVM native; covered by module + AVM tests; verified on macOS + Linux docker.
- Bytecode correctness: fixed negative integer constant parsing in the bytecode backend; restored optimizer folding for `-` and added an oretest fixture to assert `-4`/`-3` appear in `.obc` constants.
