# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-16

Focus statement (to avoid roadmap thrash):

- AVM is an **agent execution substrate** (deterministic, capability-governed, multiverse-friendly), not a near-term “general runtime for other languages”.
- Native backend is **syscall-first** (no libc/pthreads shims) so Oren can build real production libraries in `.oren`.

## P0 (Emergency / Blocking Safety)

### Cross-cutting (prevents hangs / makes rolling safe)

1) **Hard timeouts in test runner + CLI**
   - Any test that can block on PROC/NET must run under a timeout.
   - This is non-negotiable in rolling mode: a single hang kills iteration velocity.
   - Baseline:
     - `make test` uses `timeout` for native/AVM invocations where a hang is possible.
     - add a short per-test timeout for spawn/system and a longer global suite timeout.

### Native backend (syscall-first runtime; macOS-first; production-critical)

2) **Syscall-first OS boundary must be complete enough for “real programs”**
   - Goal: native Oren can build production libraries without libc shims:
     - FS + PROC + ENV + TIME + NET are the minimum “OS substrate”.
   - Enforce via tests and by keeping everything behind `sys_*`/`oren_*` boundaries.

3) **Syscall-first PROC + ENV correctness (no libc; macOS arm64)**
   - Blocking: if PROC/ENV is wrong, `spawn`, `oren_join`, and `oren_system` can hang or misbehave.
   - Requirements:
     - `oren_system()` must pass the intended child argv (`["sh","-c",cmd]`) and must never accidentally launch an interactive shell.
     - Preserve/forward parent environment to `execve` without libc:
       - capture `envp` at entry (preferred)
       - fallback derivation from `argv/argc` is allowed only as backup
     - `oren_getenv(key)` must be bounded (never hangs if envp is malformed/unterminated).
   - Regression tests:
     - `oren_system("echo ...")` completes quickly (guard with timeout).
     - `oren_getenv(...)` returns quickly for missing keys and returns non-zero for a known-set key (when present).

4) **Native TCP/IP syscalls (macOS arm64) — minimal, correct, cancellable**
   - Mandatory for the final product: native Oren needs real TCP/IP without libc wrappers.
   - Minimal syscall-first surface (exact naming can evolve, but keep the boundary small):
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_send`, `sys_recv`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`, `sys_getsockname`, `sys_getpeername`
     - `sys_poll`/`sys_select` or `sys_kevent` for timeouts/cancellation (macOS-friendly: `kqueue/kevent`)
   - Runtime-level API (so `.oren` stdlib can build on it):
     - `oren_tcp_connect(ip, port, timeout_ms)` (v0 can start with IPv4 dotted quad only; DNS can come later)
     - `oren_tcp_read(fd, n, timeout_ms)` / `oren_tcp_write(fd, bytes, timeout_ms)` / `oren_tcp_close(fd)`
   - Must integrate with deadlines/timeouts (no “block forever”).
   - Status (macOS): implemented syscall-first TCP core + kqueue/kevent timeouts, plus a loopback regression test:
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_sendto`, `sys_recvfrom`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`
     - `sys_kqueue`, `sys_kevent`, `sys_fcntl`
     - `.oren` helpers: `oren_tcp_connect`, `oren_tcp_listen_local`, `oren_tcp_accept`, `oren_tcp_read_into`, `oren_tcp_write_from`, `oren_tcp_close`
     - test: `tests/native/test_tcp_loopback.oren`
   - Remaining (still required by the “real stdlib NET” goal):
     - add `sys_getsockname` + `sys_getpeername` (useful for debugging/introspection)
     - add `sys_send`/`sys_recv` aliases (can be thin wrappers over sendto/recvfrom)
     - add Linux syscall lowering for the same surface (see P0.6)

5) **ABI hygiene for rolling native runtime globals + pointer arithmetic**
   - Blocking: silent ABI slot collisions can deadlock/hang (hard to debug).
   - Rules (must be enforced/documented):
     - Never reuse a globals slot for two unrelated purposes.
     - Prefer named getters/setters (`global_get_*`) over raw offsets.
     - In native runtime `.oren`, use `iadd(ptr, off)` for pointer arithmetic; avoid `ptr + off` when `ptr` is a pointer value.
     - Entry stub must preserve its own state across runtime calls until native codegen preserves callee-saved regs (AAPCS).

6) **Linux arm64 native backend parity (mandatory; avoid divergence)**
   - The production goal includes Linux; verify early to avoid “macOS-only drift”.
   - Deliverables:
     - implement Linux syscall lowering for the same `sys_*` surface (FS/PROC/ENV/TIME + NET sockets)
     - add a script to run a Linux native smoke subset on the trusted QEMU host (`blu@qemu-blu.localc`)
     - keep a short “Linux native smoke list” of tests that cover spawn/system/env/net basics

### AVM (agentic execution substrate; safety + multiverse)

7) **Capsule must be “no host effects” by default**
   - Goal: when running `avm --capsule` (untrusted), **do not touch the host** even if the bytecode requests FS/PROC/NET and you choose to allow those domains.
   - Enforce by defaulting capsule runs to Virtual* backends unless explicitly overridden:
     - `fs_backend=vfs`
     - `proc_backend=vproc`
     - `net_backend=vnet` (host NET remains not implemented in bootstrap)
   - This prevents accidental “allowed FS means host FS” mistakes in governance workflows.

8) **Virtual backends (no-host effects) for safety + multiverse**
   - Goal: allow AVM programs (and nested universes) to use FS/PROC/NET-like APIs **without touching the host** (even in “record” runs).
   - This is required for:
     - safe “Matrix” simulation (thousands of sandboxes)
     - deterministic replay across swarm nodes
     - running untrusted plugins without giving host FS/PROC
   - Clarify contract (domains vs backends):
     - capability domains define *what effect is requested* (FS/NET/PROC)
     - backends define *where it executes* (virtual vs host)
     - “virtual by default” is a policy choice (capsule/simulation), not a redefinition of the domains
   - Minimal order:
     - VirtualFS (in-memory) for FS domain (read/write string + bytes), with IO/log budgeting and deterministic behavior
     - VirtualPROC fixture backend (no real subprocesses; deterministic fixture responses) for PROC domain
     - VirtualNET fixture backend (scripted request/response) for NET domain
     - Nested-universe fixture injection as data (`cfg.vfs_fixtures`, `cfg.proc_fixtures`, `cfg.net_fixtures`)
   - Must bind the chosen backend mode + fixtures into `exec_hash_sha256` / job objects (so consensus sees “what environment was used”).
   - Nested universes must support two modes cleanly:
     - **simulation mode:** virtual backends only (default; deterministic; snapshot-friendly)
     - **live mode:** allow explicit `*_backend=host` (direct host mapping; no relay) under strict subset rules (caps/allowlists/budgets), bound into `exec_hash`

9) **Governance-ready job object (bind to program + inputs + exec context)**
   - `--print-policy*` is scan-before-execute (no bytecode execution) and now outputs a stable `policy_hash_sha256` (`schema: avm.policy.v1`).
   - Added `--print-job` / `--print-job-json` (schema `avm.job.v1`) which computes `job_hash_sha256 = H(program_hash, policy_hash, input_hash)` without executing bytecode.
   - Updated `--print-job*` to schema `avm.job.v2`: `job_hash_sha256 = H(program_hash, policy_hash, input_hash, exec_hash)` where `exec_hash` binds effective allowlists + fs prefixes + budgets + deterministic knobs.
   - Updated `--print-job*` to schema `avm.job.v4`: `exec_hash` also binds requested output surfaces (trace bytes/hash, record-log hex, snapshot-out enablement, trace limits) plus FS backend selection (`host|vfs`).
   - Updated `--print-job*` to schema `avm.job.v5`: `exec_hash` also binds PROC backend selection (`host|vproc`) and `proc_exit_code` when `vproc` is selected.
   - Updated `--print-job*` to schema `avm.job.v6`: `exec_hash` also binds NET backend selection (`host|vnet`) and `net_fixtures_hash_sha256` when fixtures are provided.
   - Updated `--print-job*` to schema `avm.job.v7`: `exec_hash` also binds VirtualPROC fixtures (`proc_fixtures_hash_sha256`) when fixtures are provided.
   - Next: treat `job_hash` as the swarm consensus key (signatures/attestations are a later layer; don’t block bootstrap).

10) **Diagnostics must not affect semantics**
   - Tracing/profiling must be best-effort and must not change VM outcome.
   - In particular: trace-bytes capture should truncate/disable on budget exhaustion (do not abort the VM).
   - Also: trace-bytes capture must not consume `AVM_MEM_BYTES` (program heap budget); it should be governed by `AVM_TRACE_BYTES` instead.

11) **Native backend control-flow correctness (break/continue)**
   - Blocking: missing `break`/`continue` causes infinite loops and can manifest as “hangs” in syscall-first runtime code (e.g. parsers, scanners).
   - Implement in native backend codegen with correct stack hygiene and loop nesting support.
   - Status (macOS native + bytecode backend):
     - native backend: `while` and `for` support `break`/`continue` with proper nesting; `continue` in `for` runs `post`.
     - bytecode backend: `while` and `for` support `break`/`continue`, and function locals are pre-allocated so var-decls inside loops don’t grow the VM stack.

12) **Deterministic maps: key-ordered storage**
   - For consensus and replayability, maps must not rely on insertion order (which can vary by compilation/lowering) or pointer-based ordering.
   - Contract (v0):
     - Map keys are restricted to `nil/bool/int/string` (reject other key types).
     - Maps store keys in deterministic ascending order: `nil < bool < int < string`, with strings ordered by bytewise compare (`strcmp`).
     - Duplicate key behavior: last assignment wins.
   - Enforced in:
     - AVM map construction (`NEW_MAP`) + map set (`SET_INDEX`)
     - AVM map get (`GET_INDEX`) uses the same key contract (binary search over ordered keys; rejects unsupported key types)
     - Native runtime `oren_map_set` (string keys)
     - C runtime `oren_new_map` + map set via `oren_index_set`
   - Regression: `tests/avm/test_map_key_order.oren` compares nested-universe `state_hash` across different insertion orders.
   - Regression: `tests/avm/test_map_key_types.oren` covers `nil/bool/int/string` keys, checks `result_hash` + `state_hash` across different insertion orders.

13) **`for x in ...` must be generic (rolling iterator hook)**
   - Goal: `for <name> in <iterable> { ... }` works uniformly across backends and container types needed for stdlib work.
   - Current implementation (rolling):
     - parser desugars to a `for init; cond; post { ... }` that calls `oren_iter_next(container, idx) -> [ok:int, value]`.
     - Implemented across:
       - native backend runtime (`lib/runtime_native.oren`): list/map/string
       - C backend runtime (`lib/runtime.c`): list/map/string
       - AVM core natives (`lib/avm/avm_native.inc` id 43): list/map/string/bytes
   - Current semantics:
     - `list`: yields elements in index order
     - `map`: yields keys in deterministic key order
     - `string`: yields byte codepoints (`0..255`)
     - `bytes` (AVM): yields u8 values (`0..255`)
   - Next (still required for the “streams everywhere” goal):
     - define an iterator/stream protocol beyond built-in containers (e.g. `Stream` type, channel receive iteration, and/or a `__iter_next` callable contract) and bind it into determinism/capabilities.

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **AVM deterministic cooperative tasks (concurrency model; mandatory for agents)**
   - This is the production “agent loop” primitive: structured concurrency without OS-thread nondeterminism.
   - Implement a single-threaded deterministic scheduler first (FIFO ready queue + deterministic wake ordering).
   - Minimal surface (design in `docs/AVM_CONCURRENCY.md`):
     - spawn/join tasks
     - channels + select
     - integration with budgets + deterministic TIME + snapshot/restore

2) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.
   - Bootstrap status:
     - `avm --print-trace-hash` exists.
     - `avm --print-trace-bytes-hex` exists (hex transport).
   - Next: extend event categories (alloc/error object metadata/spans) and add a BYTES return channel (not only hex dump).

3) **NET domain contract + replay/fixture story (AVM)**
   - Keep NET semantics virtualizable and deterministic by design:
     - VirtualNET fixtures remain the default for capsules and nested universes.
     - define a canonical request shape (recommended: HTTP-ish request/response rather than raw sockets).
   - Add record/replay for NET domain (so “real host net” can be audited where allowed).
   - Ensure task scheduler integrates NET as an async/blocking op (no blocking forever).

4) **Handle delegation (fd/socket passing) — later explicit mode**
   - Do not attempt this in v0 capsule/deterministic mode.
   - If added later, it must be an explicit opt-in flag (e.g. `host_handles_allowed=1`) bound into `exec_hash`, with clear snapshot portability limits.

4) **Snapshot/restore “capsule” hardening**
   - Move toward capsule-friendly formats (hashable, resumable, policy-bound).

5) **“AVM as Oren built-in library” (libavm embedding)**
   - Mandatory for the “embed libavm + oren.obc on iOS/edge” story (`docs/OREN_EVOLUTION.md`).
   - Minimal no-rewrite path:
     - stabilize a small `libavm` C API: `avm_run_bytes(...) -> {result, hashes, record_log_bytes, snapshot_bytes}`
     - provide Oren bindings in a standard module (so Oren programs can spawn child universes without shelling out)
     - start with C-backend integration (link `libavm` into `lib/runtime.c`) and keep native-backend integration as a follow-up.

6) **Compiler-in-AVM (“source -> .obc inside a child universe”)**
   - Mandatory for closing the loop (multiverse + in-memory compilation) without a host toolchain.
   - Break into minimal milestones to avoid massive rewrites:
     - M1: get a small “compiler capsule MVP” that compiles a single-file `.oren` subset to `.obc`, using VirtualFS for IO.
     - M2: extend to imports/modules, deterministic compilation mode, and returning `.obc` as `BYTES`.
     - M3: use this path to compile AVM-facing stdlib modules inside the sandbox.

7) **Tooling: disassembler + debugger + profiler**
   - Disassembler: stable “otool-like” `.obc` inspector (sections, consts, policy, hashes).
   - Debugger: minimal “lldb-like” stepping + breakpoints + trace correlation (pc/op/stack depth).
   - Profiler: memory/time attribution surfaces that are deterministic / loggable (must not change semantics).
     - Bootstrap progress: trace stream now includes bytes-only `ALLOC/FREE/REALLOC` events (not included in `TRACE_HASH`) and `tools/avm_trace_profile.py` can decode `TRACE_BYTES_HEX` into an allocation profile JSON.

8) **Native backend: syscall-first threads + coroutines (post-v0)**
   - Keep native backend free of libc/pthreads shims for core runtime services.
   - Current v0 `spawn` uses `fork + pipe` (process-based) for correctness.
   - Next: transition to OS threads and/or coroutines once the syscall-first thread boundary is stable (see `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`).

9) **Compile-time evaluation (“comptime”) — pure-only first**
   - Goal: make compilation deterministic and agent-friendly without a huge rewrite.
   - Stage C0: constant evaluation for pure expressions only (no FS/NET/PROC/ENV/TIME, no nondeterministic RNG), with explicit budgets to prevent compiler hangs.
   - Later stages (pure comptime functions, bounded reflection) can follow once C0 is stable.

## P2 (Next-Gen AVM Performance + Features)

1) **Typed buffers + SIMD kernels (no-JIT-first path)**
   - Implement `F32_BUF` + minimal vector ops (`dot/add/mul/reduce`) with scalar fallback.
   - This is also the recommended path for **float32** support in v0 without adding a second scalar float tag to the dynamic value model.
   - Follow-up: define fixed-width numeric types (`i32/u32/u128`, `f32/f64`) primarily as typed-buffer element types and serialization/FFI boundary types.

2) **VirtualNET / VirtualPROC backends (fixtures)**
   - Enable “Matrix sandbox” simulation and deterministic replay of realistic workflows.

3) **Codebase factoring (do only when it prevents progress)**
   - `lib/avm/avm.c` is large; split by domain/module only when adding new surfaces (NET record/replay, TASK scheduler, snapshot format v2) to avoid churn.
   - Goal: factor by capability domains and by deterministic surfaces (hashing, tracing, snapshot) rather than “random file splitting”.

## Recently Completed (for context)

- macOS syscall-first: fixed Darwin `fork` ABI handling (child indicated via `X1`) in `sys_fork` and native `spawn`, enabling correct `oren_system` and `spawn`/`oren_join` behavior without libc/pthreads.
- Deterministic TIME derived from executed gas (no “advance on now()”).
- Function-aware bytecode verifier (removes spurious stack-join rejects).
- AVM-in-AVM domain (nested universes) with determinism tests.
- Memory budget (`AVM_MEM_BYTES`) + AVM-in-AVM `cfg.mem_bytes` subset enforcement.
- FS I/O budget (`AVM_IO_BYTES`) + AVM-in-AVM `cfg.io_bytes` subset enforcement.
- Structured error contract: stable `__err/code/msg` with optional `domain/op` metadata for policy/budget failures.
- Policy scan: `--print-policy` outputs domain bitmask plus `(domain, op)` pairs and does not execute bytecode.
- Policy JSON: `--print-policy-json` outputs `schema: avm.policy.v1` plus `policy_hash_sha256` and does not execute bytecode.
- Strict verifier mode: `--verify-strict` / `AVM_VERIFY_STRICT=1` rejects legacy capability encodings (`CALL_NATIVE`, and CORE-domain `CALL_NATIVE2` that remaps to effectful domains).
- Capsule mode: `--capsule` / `AVM_CAPSULE=1` implies strict verify + deny-by-default + conservative default budgets.
- Leak-free teardown: VM frees remaining unreachable heap allocations at `avm_free()` (no tracing GC during run yet).
- Record/replay log budget (`AVM_LOG_BYTES`) + child `cfg.log_bytes` subset enforcement (preflight prevents un-loggable side effects in record mode).
- `avm` tooling: disasm/trace/breakpoints + mem-stats + `--repeat` + `--print-rss`.
- Trace bytes capture is best-effort: if `AVM_TRACE_BYTES` budget is exceeded, AVM truncates trace bytes and prints `TRACE_TRUNCATED 1` (does not abort execution).
- VirtualFS (bootstrap): FS domain can run with `--fs-backend vfs` / `AVM_FS_BACKEND=vfs` to avoid host filesystem effects (useful for multiverse + capsules).
- VirtualPROC (bootstrap): PROC domain can run with `--proc-backend vproc` / `AVM_PROC_BACKEND=vproc` to avoid host subprocesses (returns deterministic `AVM_PROC_EXIT_CODE`).
- VirtualPROC fixtures (bootstrap): PROC domain can run with `--proc-fixtures-hex` / `AVM_PROC_FIXTURES_HEX=...` to return deterministic fixture exit codes for known commands (still never touches host subprocesses).
- VirtualNET (bootstrap): NET domain can run with `--net-backend vnet` / `AVM_NET_BACKEND=vnet` plus `AVM_NET_FIXTURES_HEX=...` to avoid host network (returns deterministic fixture bodies).
- AVM list append growth: `SET_INDEX` on lists now grows capacity when appending at `i == count` (no silent drop); regression in `tests/avm/test_list_append_grow.oren` (also mirrored in native).
- Nested containers smoke tests: added `tests/native/test_nested_containers.oren` and `tests/avm/test_nested_containers.oren` (map/list nesting + alias mutation).
