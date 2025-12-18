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

Code location:
- `lib/compiler/arm64_abi_macos.oren`

Repro (manual audit):

```c
#include <stddef.h>
#include <sys/stat.h>
#include <stdio.h>
int main(){printf("%zu %zu %zu\n", sizeof(struct stat), offsetof(struct stat, st_mode), offsetof(struct stat, st_size));}
```
