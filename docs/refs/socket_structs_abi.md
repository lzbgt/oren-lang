# Socket structs ABI notes (curated)

This file records **fact-based** layouts of common socket structs used by the
syscall-first networking path. These layouts are used to define `.oren` ABI
structs (`@oren.abi`) without depending on host headers at build time.

## `struct sockaddr_in6` (macOS arm64 / Linux arm64)

Verified via tiny audit C programs:

- macOS arm64:
  - `sizeof(struct sockaddr_in6)` == **28**
  - offsets:
    - `sin6_len` == 0
    - `sin6_family` == 1
    - `sin6_port` == 2
    - `sin6_flowinfo` == 4
    - `sin6_addr` == 8 (size 16)
    - `sin6_scope_id` == 24

- Linux arm64:
  - `sizeof(struct sockaddr_in6)` == **28**
  - offsets:
    - `sin6_family` == 0 (size 2)
    - `sin6_port` == 2
    - `sin6_flowinfo` == 4
    - `sin6_addr` == 8 (size 16)
    - `sin6_scope_id` == 24

## `struct sockaddr_un` (macOS arm64 / Linux arm64)

- macOS arm64:
  - `sizeof(struct sockaddr_un)` == **106**
  - offsets:
    - `sun_len` == 0
    - `sun_family` == 1
    - `sun_path` == 2 (size 104)

- Linux arm64:
  - `sizeof(struct sockaddr_un)` == **110**
  - offsets:
    - `sun_family` == 0 (size 2)
    - `sun_path` == 2 (size 108)

## `struct pollfd` (macOS arm64 / Linux arm64)

- macOS arm64:
  - `sizeof(struct pollfd)` == **8**
  - offsets:
    - `fd` == 0 (size 4)
    - `events` == 4 (size 2)
    - `revents` == 6 (size 2)

- Linux arm64:
  - `sizeof(struct pollfd)` == **8**
  - offsets:
    - `fd` == 0 (size 4)
    - `events` == 4 (size 2)
    - `revents` == 6 (size 2)

