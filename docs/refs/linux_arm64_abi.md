# Linux arm64 ABI notes (curated)

This file is a **repo-owned** reference for the syscall-first native backend and
for defining OS ABI structs in `.oren` without depending on host headers.

Goal:
- keep the native backend **independent of host headers**
- stay **fact-based** by recording exact constants and how they were verified

## `struct stat` layout (Linux, arm64)

Used by syscall-first helpers that interpret `stat` buffers (`fstat`, `newfstatat`).

Verified inside the repo’s linux/arm64 docker environment by compiling and running
a tiny audit C program (audit-only, not shipped / not required at runtime):

- `sizeof(struct stat)` == **128**
- `offsetof(st_mode)` == **16**, `sizeof(st_mode)` == **4**
- `offsetof(st_size)` == **48**, `sizeof(st_size)` == **8**

Repro (manual audit):

```c
#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>
int main(){
  printf("%zu\n", sizeof(struct stat));
  printf("%zu %zu\n", offsetof(struct stat, st_mode), sizeof(((struct stat*)0)->st_mode));
  printf("%zu %zu\n", offsetof(struct stat, st_size), sizeof(((struct stat*)0)->st_size));
}
```

