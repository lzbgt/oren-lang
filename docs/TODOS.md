# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (about 5–10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims / no libc dependency** `[arch]`
   - Native backend output must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - Runtime must be implemented via `sys_*` primitives + `.oren` code.

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - Canonical curated suite (preferred): `./oretest --target macos`
   - Wrapper (same suite): `make test`

6) **Keep this file actionable** `[maint]`
   - Each P0/P1 item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list 5–10 items total; merge and delete aggressively.

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.

## Tasks (Next, Highest Priority First)

1) **P0 [safety] Capsule OS-substrate: close remaining bypass surfaces** *(native backend)*
   - DoD: for each raw `sys_*` that can cause host effects (FS/NET/PROC/ENV/TIME), there is a capsule pre hook and tests cover allow+deny paths.
   - Status: added `oretest` static audit that scans syscall lowering and asserts a capsule `*_pre` hook exists for host-effect syscalls (with explicit exemptions for internal runtime primitives).
   - Next deliverable: extend audit to cover any syscall lowering modules beyond `arm64_native_expr_syscalls.oren` if/when new syscall lowering files are introduced.

2) **P0 [maint] Linux arm64 syscall parity for the curated native suite**
   - DoD: `./oretest --target linux` passes on a Linux arm64 environment (QEMU host or Docker/VM), for the curated native list.
   - Status: `make test` now auto-selects `--target linux` when run on a Linux host.
   - Status (Docker): `tools/linux_native_smoke_docker.sh` passes on Docker Desktop linux/arm64 (persistent container).
   - Next deliverable: run `SSH_DEST=blu@qemu-blu.local ./scripts/oretest_remote_linux_arm64.sh` and fix any ABI-table gaps discovered.

3) **P1 [lang] Explicit numeric types: v1 semantics + casts**
   - DoD: decide whether `u8/i32/f64/...` are:
     - v0 annotation-only (metadata), vs
     - v1 static types (checked), with a staged rollout that does not block self-hosting.
   - Next deliverable: define cast semantics (checked vs truncating), and document endian-aware cast syntax for packed/network parsing.

4) **P1 [correctness] String equality semantics + propagation** *(native backend)*
   - DoD: all string `==` cases in tests/stdlib are safe (including `nil`) and consistent across backends.

5) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - DoD: deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

6) **P2 [ux] Tooling**
   - `.obc` disassembler (“otool-like”) + metadata extractor (reads embedded `OREN_META\n1\n` bytes convention).

7) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (AVM/codegen) once behavior is covered by tests.

## Recently Completed (high signal)

- Test orchestration SOLID: `make test` now runs through `./oretest` (Go), not `lib/compiler/compiler.oren`.
- Test speed P0: module + AVM tests run in parallel with isolated per-test workdirs (`OREN_TEST_JOBS`).
- Fixed-width scalar names + universal `name: Type` annotation sugar is implemented (v0 metadata) and documented (including list heterogeneity).
- Packed struct views: migrated from `@oren.u16be` field attributes to `field: u16be` annotations (rolling).
- Native codegen ABI: treat X27/X28 as reserved global heap registers; preserve heap regs around every `svc`.
- Syscall-first policy guard: forbids direct `darwin_sys_*` / `linux_sys_*` usage outside approved lowering modules, and bounds direct `insn_svc` emission.
- Capsule P0: added a fast static “capsule syscall prehook audit” in `./oretest` to prevent bypass regressions.
- OS ABI tables: repo-owned constants for `open` flags, `fcntl` cmds, `mmap` prot/flags (Darwin/Linux), with audit refs in `docs/refs/*` (incl. `darwin_sys_socket.h`, `darwin_sys_fcntl.h`).
- NET: translated Oren-level `getsockopt/setsockopt` IDs to OS ABI values safely (no cascading translation).
- Linux arm64 execution baseline: removed dependence on LSE atomics (CAS/LDADD) by lowering `atomic_add/atomic_cas` via LL/SC loops (LDAXR/STLXR).
- Linux ELF debug builds: emit + patch debug info so `--debug` linux binaries no longer crash (ELF `adr_data` fixup + 8-byte aligned debug blob parsing).
