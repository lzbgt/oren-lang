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
   - Next: mounts UX polish + virtual mount mirroring (native/AVM) + more FS syscalls as needed.

2) **P0 [maint] Centralize OS ABI constants in repo-owned tables (no SDK header dependency)**
   - Keep syscall numbers / struct offsets in repo code + `docs/refs/*`.
   - Treat system headers as audit-only.
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

- Native backend spawn intrinsic: removed remaining hardcoded `svc #0`/`svc #0x80` + numeric syscall IDs; now uses `arm64_abi_{macos,linux}.oren` tables.
- Mach-O minimal exit stub (`macho_emit_exit_arm64`): now uses `arm64_abi_macos.oren` syscall ABI constants (no embedded MOVK/SVC magic).
- FS mounts semantics hardened: longest-prefix + boundary checks in native runtime; AVM host mounts match (incl. host-path allow-as-is under enrolled host prefixes); added overlapping-mount regression tests.
- FS allow-prefix policy hardened: require boundary when a prefix does not end with `/` (prevents `build` matching `build2`); applied to native capsule + AVM host allow-prefix checks.
- ABI tables expanded: centralized NET-related syscalls (socket/connect/bind/listen/accept/sendto/recvfrom) and other process/syscall staples (execve/wait4/kill/gettimeofday/fcntl, sockopt/shutdown, peer/sockname) for macOS+Linux; removed more numeric `sysno=` literals from syscall lowering.
- Native string propagation: fixed `+` stringiness to require both operands, added `oren_list_get` string propagation and array-of-strings list inference; added `tests/native/test_string_list_eq.oren`.
- ABI constants: moved remaining Darwin `kevent` syscall number and Linux `AT_*` syscall-arg flags (AT_SYMLINK_NOFOLLOW/AT_REMOVEDIR) into repo-owned ABI tables; removed the last hardcoded `sysno=363` from syscall lowering.
- ABI constants: centralized Linux `AT_FDCWD=-100` into `arm64_abi_linux.oren` and added a signed-immediate loader helper (removes remaining `MOVN imm=99` magic from syscall lowering).
- Native string comparisons: added regression coverage for `string == nil` / `nil == string` (must not lower to `strcmp`).
