# Linux epoll ABI notes (curated)

This file is a **repo-owned** reference for defining Linux epoll structs in `.oren`
without depending on host headers at build time.

Goal:
- keep syscall-first tooling **independent of host headers**
- stay **fact-based** by recording exact layouts and how they were verified

## `struct epoll_event` layout (Linux, arm64)

Verified inside the repo’s linux/arm64 docker environment by compiling and running
a tiny audit C program (audit-only, not shipped / not required at runtime):

- `sizeof(struct epoll_event)` == **16**
- `offsetof(events)` == **0**, `sizeof(events)` == **4**
- `offsetof(data)` == **8**, `sizeof(data)` == **8**

Repro (manual audit):

```c
#include <stddef.h>
#include <stdio.h>
#include <sys/epoll.h>
int main(){
  printf("%zu\n", sizeof(struct epoll_event));
  printf("%zu %zu\n", offsetof(struct epoll_event, events), sizeof(((struct epoll_event*)0)->events));
  printf("%zu %zu\n", offsetof(struct epoll_event, data), sizeof(((struct epoll_event*)0)->data));
}
```

