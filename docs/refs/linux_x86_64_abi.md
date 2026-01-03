# Linux x86_64 ABI notes (curated)

This file is a **repo-owned** reference for the syscall-first native backend and
for defining OS ABI structs in `.oren` without depending on host headers.

Goal:
- keep the native backend **independent of host headers**
- stay **fact-based** by recording exact constants and how they were verified

## `struct stat` layout (Linux, x86_64)

Used by syscall-first helpers that interpret `stat` buffers (`fstat`, `newfstatat`).

Verified on the Tier‑1 remote x86_64 Linux environment (WSL2) by compiling and running
a tiny audit C program (audit-only, not shipped / not required at runtime):

- `sizeof(struct stat)` == **144**
- `offsetof(st_mode)` == **24**, `sizeof(st_mode)` == **4**
- `offsetof(st_size)` == **48**, `sizeof(st_size)` == **8**
- `offsetof(st_atim.tv_sec)` == **72**
- `offsetof(st_atim.tv_nsec)` == **80**
- `offsetof(st_mtim.tv_sec)` == **88**
- `offsetof(st_mtim.tv_nsec)` == **96**
- `offsetof(st_ctim.tv_sec)` == **104**
- `offsetof(st_ctim.tv_nsec)` == **112**

Code location:
- `lib/compiler/x64_abi_linux.oren`

Repro (manual audit):

```c
#define _GNU_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
int main(){
  printf("%zu\n", sizeof(struct stat));
  printf("%zu %zu\n", offsetof(struct stat, st_mode), sizeof(((struct stat*)0)->st_mode));
  printf("%zu %zu\n", offsetof(struct stat, st_size), sizeof(((struct stat*)0)->st_size));
  printf("%zu %zu\n", offsetof(struct stat, st_atim) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_atim) + offsetof(struct timespec, tv_nsec));
  printf("%zu %zu\n", offsetof(struct stat, st_mtim) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_mtim) + offsetof(struct timespec, tv_nsec));
  printf("%zu %zu\n", offsetof(struct stat, st_ctim) + offsetof(struct timespec, tv_sec),
                      offsetof(struct stat, st_ctim) + offsetof(struct timespec, tv_nsec));
}
```

