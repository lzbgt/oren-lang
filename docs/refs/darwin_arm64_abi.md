# Darwin/macOS arm64 ABI notes (curated)

This file is a **repo-owned** reference for the syscall-first native backend.

Goal:
- keep the native backend **independent of host SDK headers**
- still be **fact-based** by recording the exact constants and how they were verified

Primary source for syscall numbering:
- `docs/refs/darwin_xnu_syscalls.master`

## Syscall numbers (macOS arm64)

Used by the native backend syscall lowering:

- `stat64(path, buf)`  -> syscall **338**
- `fstat64(fd, buf)`   -> syscall **339**
- `lstat64(path, buf)` -> syscall **340**
- `getdirentries64(fd, buf, bufsize, pos_ptr)` -> syscall **344**

Code location:
- `lib/compiler/arm64_abi_macos.oren`
- `lib/compiler/arm64_native_expr_syscalls.oren`

## Syscall ABI (arm64 Darwin)

- Instruction: `svc #0x80`
- Syscall number register: **X16**
- Syscall number value: the kernel accepts the **raw syscall number** (e.g. `getpid` = 20)

Note on encoding:
- Some platforms (notably x86_64 macOS) use `0x2000000 | n` encoding.
- On arm64 macOS, **both** raw `n` and encoded `0x2000000 | n` appear to work (kernel masks/ignores upper bits).
- For simplicity + fewer instructions, the native backend standardizes on **raw `n`**.

Verification (on-machine audit, not a runtime dependency):
- Disassembly: `/usr/lib/system/libsystem_kernel.dylib` shows `mov x16, #<n>; svc #0x80` style stubs.
- Repro program: `tools/audit/darwin_arm64_syscall_encoding.{c,S}` (builds `build/_audit_darwin_syscall_encoding`).

## fcntl constants

Used by `oren_getcwd()` in **host mode** (native runtime):

- `F_GETPATH` -> **50**

Rationale:
- avoids calling libc `getcwd(3)`
- can be denied in capsule mode to prevent leaking host absolute paths

## `struct stat` layout (Darwin)

The native runtime needs stable offsets when interpreting `stat` buffers.

Verified on macOS arm64 by building and running a tiny audit program (not shipped / not required at runtime):

- `sizeof(struct stat)` == **144**
- `offsetof(st_mode)` == **4**
- `offsetof(st_size)` == **96**
- `offsetof(st_atimespec.tv_sec)` == **32**
- `offsetof(st_atimespec.tv_nsec)` == **40**
- `offsetof(st_mtimespec.tv_sec)` == **48**
- `offsetof(st_mtimespec.tv_nsec)` == **56**
- `offsetof(st_ctimespec.tv_sec)` == **64**
- `offsetof(st_ctimespec.tv_nsec)` == **72**

Code location:
- `lib/compiler/arm64_abi_macos.oren`

Repro (manual audit):

```c
#include <stddef.h>
#include <sys/stat.h>
#include <stdio.h>
#include <time.h>
int main(){
  printf("%zu %zu %zu\n", sizeof(struct stat), offsetof(struct stat, st_mode), offsetof(struct stat, st_size));
  printf("%zu %zu\n", offsetof(struct stat, st_atimespec) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_atimespec) + offsetof(struct timespec, tv_nsec));
  printf("%zu %zu\n", offsetof(struct stat, st_mtimespec) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_mtimespec) + offsetof(struct timespec, tv_nsec));
  printf("%zu %zu\n", offsetof(struct stat, st_ctimespec) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_ctimespec) + offsetof(struct timespec, tv_nsec));
}
```
