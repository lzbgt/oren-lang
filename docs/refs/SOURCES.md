# `docs/refs/` Sources (Audit-Only)

Files under `docs/refs/` are **vendored for audit/reference only** to keep the compiler/runtime:

- independent of host SDK headers at build time
- still grounded in authoritative upstream definitions (syscall numbers, Mach-O constants, etc.)

These files are not “dependencies”; they are pinned snapshots used to validate repo-owned ABI tables and encodings.

Fetched on **2025-12-19**.

## Darwin / XNU syscall master

- Upstream repo: `apple-oss-distributions/xnu`
- Commit (HEAD at fetch time): `f6217f891ac0bb64f3d375211650a4c1ff8ca1ea`
- Path: `bsd/kern/syscalls.master`
- Vendored as: `docs/refs/darwin_xnu_syscalls.master`

## Darwin / Xcode SDK headers (audit)

Some Darwin ABI constants are easiest to verify from the shipped macOS SDK headers.
These are **audit-only** (we do not include them as build dependencies).

Environment at fetch time:
- Xcode: `Xcode 26.2 (Build version 17C52)`
- SDK path: `MacOSX26.2.sdk` (`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk`)

Vendored:
- `usr/include/sys/socket.h` → `docs/refs/darwin_sys_socket.h`
- `usr/include/sys/fcntl.h` → `docs/refs/darwin_sys_fcntl.h`

## Linux syscall numbers (audit)

Note: We intentionally vendor the canonical UAPI headers rather than relying on system headers.

- Upstream repo: `torvalds/linux`
- Commit (HEAD at fetch time): `dd9b004b7ff3289fb7bae35130c0a5c0537266af`
- Paths:
  - `include/uapi/asm-generic/unistd.h` → `docs/refs/linux_asm_generic_unistd.h`
  - `arch/arm64/include/uapi/asm/unistd.h` → `docs/refs/linux_arm64_unistd.h` (wrapper include; points at `asm/unistd_64.h` which may be generated during header export)

Fetch method:
- GitHub raw endpoints may rate-limit; we fetched via `cdn.jsdelivr.net` when needed.

## Linux man-pages (behavior reference)

- Upstream repo: `mkerrisk/man-pages`
- Commit (HEAD at fetch time): `ae6b221882ce71ba82fcdbe02419a225111502f0`
- Paths:
  - `man2/clone.2` → `docs/refs/linux_man_clone.2`
  - `man2/fork.2` → `docs/refs/linux_man_fork.2`

## Mach-O headers

See `docs/refs/macho/SOURCES.md` (pinned from Apple OSS `cctools`).

## Windows x64 calling convention (audit)

Vendored from Microsoft Learn (audit/reference only).

Fetched on **2026-01-01**.

- `docs/refs/windows/msvc_x64_calling_convention.html`
