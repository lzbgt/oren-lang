# TODOs (Prioritized, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (about 5-10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## How to Verify

- Canonical curated suite (preferred): `./oren test --target macos`
- Wrapper (same suite): `make test`
- Legacy (larger, slower): `make test-legacy`

## Next (Highest Priority First)

1) **P0 [safety] Syscall-first OS substrate hardening (native backend)**
   - Keep: PROC cancellation + TIME + ENV + NET loopback correctness; never hang.
   - Capability enrollment model: explicit mapping virtual -> host resources; deny-by-default with capability checks at the raw `sys_*` boundary (no bypass).
   - Next: mounts UX polish + virtual mount mirroring (native/AVM) + remaining ambiguous fd syscalls (e.g. dup/dup2/dup3, ioctl) gated + fd-kind propagation.

2) **P0 [maint] Centralize OS ABI constants in repo-owned tables (no SDK header dependency)**
   - Keep syscall numbers / struct offsets in repo code + `docs/refs/*`.
   - Treat system headers as audit-only.
   - Keep Mach-O / dyld constants repo-owned as well (prefer named constants over scattered numeric literals).
   - Periodically refresh `docs/refs/*` from authoritative upstream sources and record the exact upstream tag/commit used (audit-only; not a build dep).
   - macOS arm64 is largely done via `lib/compiler/arm64_abi_macos.oren` + `docs/refs/darwin_arm64_abi.md` (syscall reg/imm + core syscalls).
   - Linux arm64 baseline table added via `lib/compiler/arm64_abi_linux.oren` (syscall reg/imm + core syscalls).
   - Next: Linux arm64 parity tables + a single shared ABI layer used by native codegen.

3) **P1 [correctness] String equality semantics + propagation (native backend)**
   - Native backend uses compile-time string propagation + runtime `strcmp` (no libc); AVM/C backends use tagged strings.
   - Keep expanding coverage via tests: list literals, `oren_list_get`, FS (`readdir`), ENV, `realpath`, `read_file`, etc.
   - Must keep `s == nil` safe (no accidental `strcmp(s, 0)` lowering).

4) **P1 [prod] Fixed-width scalars + floats + explicit casts (network + scientific code)**
   - Define cast semantics (truncate vs checked) and enforce consistent behavior across native/C/AVM.
   - Extend casts to cover `f32/f64` + endian-aware helpers (`be/le`) for packed parsing.

5) **P1 [determinism] AVM cooperative concurrency MVP (single-threaded)**
   - Deterministic `spawn/join`, channels, deterministic `select`, integrated with TIME + gas + snapshot/resume.

6) **P2 [ux] Tooling**
   - `.obc` disassembler ("otool-like") + metadata extractor (reads embedded `OREN_META\n1\n` bytes convention).

7) **P2 [maint] Refactors without semantic churn**
   - Split oversized modules (AVM/codegen) once behavior is covered by tests.

## Recently Completed (high signal)

- Capsule runtime: improved deny diagnostics (capability domain + FS prefix/mount enrollment hints) and clarified that `sys_*` are native-backend intrinsics (stubs should not execute in correctly built native binaries).
- Capsule hardening: enforced FS domain at raw `sys_read` / `sys_pipe` boundaries (no bypass) and added deterministic tests (stdin redirected to `/dev/null` to guarantee no hangs).
- Capsule hardening: prevented NET bypass by enforcing NET domain when `sys_read`/`sys_write` operate on NET-tagged fds (sockets); also reclassified `sys_pipe` under PROC as IPC for spawn/join.
- Capsule hardening: tagged pipe fds (PROC IPC kind) so `sys_read`/`sys_write` treat them as PROC IPC; fixed Darwin `sys_pipe` to return `-errno` on failure and added a PROC-only spawn/join regression.
- Capsule hardening: enforced TIME domain at raw `sys_gettimeofday` / `sys_nanosleep` boundaries (no bypass) with deterministic fixtures.
- Capsule hardening: enforced enrollment at raw `sys_kqueue` / `sys_kevent` boundaries (no bypass); event-loop syscalls require at least one of NET/PROC/TIME.
- Capsule hardening: enforced fd-domain gating at raw `sys_close` / `sys_fcntl` boundaries (no bypass), including tagging `sys_kqueue` return fds so TIME-only event-loop tests do not require FS.
- Capsule hardening: enforced NET enrollment at raw `sys_getsockopt` / `sys_setsockopt` / `sys_getsockname` / `sys_getpeername` / `sys_shutdown` boundaries (no bypass).
- Mach-O emitter: removed more magic literals by centralizing constants and using fixed-width names, without SDK header build deps.
- Refs: refreshed vendored syscall/Mach-O sources pinned in `docs/refs/` (audit-only; not build deps).
