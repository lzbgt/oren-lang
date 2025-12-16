# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-16

## P0 (Emergency / Blocking Safety)

### Native backend (syscall-first runtime; macOS-first)

1) **Syscall-first PROC + ENV correctness (no libc; macOS arm64)**
   - This is the “independent runtime” foundation: if PROC/ENV is wrong, `spawn`, `oren_join`, and `oren_system` can hang or misbehave.
   - Requirements:
     - `oren_system()` must pass the intended `argv` (`["sh","-c",cmd]`) and must not accidentally launch an interactive shell.
     - Preserve/forward parent environment to `execve` without libc (capture `envp` at entry, fallback derivation from `argv/argc` only as backup).
     - `oren_getenv(key)` must be safe (bounded scan; never hang on malformed envp).
   - Add regression tests:
     - `oren_system("echo ...")` must complete quickly (guard with timeout in the test runner).
     - `oren_getenv("CODEX_LOG_LEVEL")` (or another known CI env var) returns non-zero when set; returns 0 quickly when absent.

2) **ABI hygiene for rolling native runtime globals**
   - The injected runtime uses a small “globals storage” block as a rolling ABI.
   - Rules (must be enforced/documented):
     - Never reuse a slot for two unrelated purposes (e.g. lock recursion count vs envp).
     - Prefer named getters/setters (`global_get_*`) over raw offsets.
     - In native runtime code, use `iadd(ptr, off)` for pointer arithmetic; avoid `ptr + off` when `ptr` is a pointer value.

### AVM (agentic execution substrate)

3) **Capsule must be “no host effects” by default**
   - Goal: when running `avm --capsule` (untrusted), **do not touch the host** even if the bytecode requests FS/PROC/NET and you choose to allow those domains.
   - Enforce by defaulting capsule runs to Virtual* backends unless explicitly overridden:
     - `fs_backend=vfs`
     - `proc_backend=vproc`
     - `net_backend=vnet` (host NET remains not implemented in bootstrap)
   - This prevents accidental “allowed FS means host FS” mistakes in governance workflows.

4) **Virtual backends (no-host effects) for safety + multiverse**
   - Goal: allow AVM programs (and nested universes) to use FS/PROC/NET-like APIs **without touching the host** (even in “record” runs).
   - This is required for:
     - safe “Matrix” simulation (thousands of sandboxes)
     - deterministic replay across swarm nodes
     - running untrusted plugins without giving host FS/PROC
   - Minimal order:
     - VirtualFS (in-memory) for FS domain (read/write string + bytes), with IO/log budgeting and deterministic behavior
     - VirtualPROC fixture backend (no real subprocesses; deterministic fixture responses) for PROC domain
     - VirtualNET fixture backend (scripted request/response) for NET domain
     - Nested-universe fixture injection as data (`cfg.vfs_fixtures`, `cfg.proc_fixtures`, `cfg.net_fixtures`)
   - Must bind the chosen backend mode + fixtures into `exec_hash_sha256` / job objects (so consensus sees “what environment was used”).

5) **Governance-ready job object (bind to program + inputs + exec context)**
   - `--print-policy*` is scan-before-execute (no bytecode execution) and now outputs a stable `policy_hash_sha256` (`schema: avm.policy.v1`).
   - Added `--print-job` / `--print-job-json` (schema `avm.job.v1`) which computes `job_hash_sha256 = H(program_hash, policy_hash, input_hash)` without executing bytecode.
   - Updated `--print-job*` to schema `avm.job.v2`: `job_hash_sha256 = H(program_hash, policy_hash, input_hash, exec_hash)` where `exec_hash` binds effective allowlists + fs prefixes + budgets + deterministic knobs.
   - Updated `--print-job*` to schema `avm.job.v4`: `exec_hash` also binds requested output surfaces (trace bytes/hash, record-log hex, snapshot-out enablement, trace limits) plus FS backend selection (`host|vfs`).
   - Updated `--print-job*` to schema `avm.job.v5`: `exec_hash` also binds PROC backend selection (`host|vproc`) and `proc_exit_code` when `vproc` is selected.
   - Updated `--print-job*` to schema `avm.job.v6`: `exec_hash` also binds NET backend selection (`host|vnet`) and `net_fixtures_hash_sha256` when fixtures are provided.
   - Updated `--print-job*` to schema `avm.job.v7`: `exec_hash` also binds VirtualPROC fixtures (`proc_fixtures_hash_sha256`) when fixtures are provided.
   - Next: treat `job_hash` as the swarm consensus key (signatures/attestations are a later layer; don’t block bootstrap).

6) **Diagnostics must not affect semantics**
   - Tracing/profiling must be best-effort and must not change VM outcome.
   - In particular: trace-bytes capture should truncate/disable on budget exhaustion (do not abort the VM).
   - Also: trace-bytes capture must not consume `AVM_MEM_BYTES` (program heap budget); it should be governed by `AVM_TRACE_BYTES` instead.

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.
   - Bootstrap status:
     - `avm --print-trace-hash` exists.
     - `avm --print-trace-bytes-hex` exists (hex transport).
   - Next: extend event categories (alloc/error object metadata/spans) and add a BYTES return channel (not only hex dump).

2) **Deterministic cooperative tasks (AVM concurrency model)**
   - Define/implement a deterministic scheduler (single-threaded baseline first).
   - Add a minimal `TASK` surface (spawn/join + channels/select) that composes with:
     - snapshot/restore
     - nested universes (child runs as a task)
     - budgets and capability gating
   - Design doc: `docs/AVM_CONCURRENCY.md`.

3) **Snapshot/restore “capsule” hardening**
   - Move toward capsule-friendly formats (hashable, resumable, policy-bound).

4) **Tooling: disassembler + debugger + profiler**
   - Disassembler: stable “otool-like” `.obc` inspector (sections, consts, policy, hashes).
   - Debugger: minimal “lldb-like” stepping + breakpoints + trace correlation (pc/op/stack depth).
   - Profiler: memory/time attribution surfaces that are deterministic / loggable (must not change semantics).
     - Bootstrap progress: trace stream now includes bytes-only `ALLOC/FREE/REALLOC` events (not included in `TRACE_HASH`) and `tools/avm_trace_profile.py` can decode `TRACE_BYTES_HEX` into an allocation profile JSON.

5) **Native backend: syscall-first thread/coroutine transition plan (post-v0)**
   - Keep native backend free of libc/pthreads shims for core runtime services.
   - Current v0 `spawn` uses `fork + pipe` (process-based) for correctness.
   - Next: transition to OS threads and/or coroutines once the syscall-first thread boundary is stable (see `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`).

## P2 (Next-Gen AVM Performance + Features)

1) **Typed buffers + SIMD kernels (no-JIT-first path)**
   - Implement `F32_BUF` + minimal vector ops (`dot/add/mul/reduce`) with scalar fallback.

2) **VirtualNET / VirtualPROC backends (fixtures)**
   - Enable “Matrix sandbox” simulation and deterministic replay of realistic workflows.

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
