# Async IO Readiness + `select` in Oren (Rolling Design + Current Reality)

**Last updated:** 2026-01-16

This doc answers a recurring question:

> “What is Oren’s `select` story for async network/file readiness across macOS/Linux/Windows (kqueue/epoll/Win32)… and how does it relate to goroutine-like concurrency?”

This repo is rolling. The goals are:

- Oren is a modern, efficient language that supports AI agents and swarm computing.
- AVM is a deterministic VM with multiverse/snapshot/swarm constraints.
- The compiler has multiple backends (native / C / AVM bytecode) and must keep semantics aligned.

This document separates:

- **What exists today** (grounded in code), vs
- **What we plan** (design direction, tracked in `docs/TODOS.md`).

---

## 1) What exists today (facts)

### 1.1 There is no language-level `select` keyword (yet)

`select` is **not** a keyword in the Stage1 language grammar today. The language surface has `spawn`,
but not `select` as a statement form.

Source of truth:

- `docs/LANGUAGE_SPEC.md` keyword list + grammar (no `select`).

### 1.2 There *is* an Oren-level `oren_select` API (data-driven)

Both AVM and native runtime expose low-level, data-driven primitives (functions, not syntax):

- `oren_select_recv([ch1, ch2, ...]) -> [idx, val]`
- `oren_select(cases) -> [idx, payload]`
  - recv case encoding: `[0, ch]`
  - send case encoding: `[1, ch, val]`
  - payload: recv value or `1` for send (rolling ok marker)

Sources of truth:

- AVM: opcodes `SELECT_RECV` / `SELECT`:
  - `lib/avm/avm_vm.c` (`AVM_OP_SELECT_RECV=0x4A`, `AVM_OP_SELECT=0x4D`)
  - select case encoding: `select_case_parse` in `lib/avm/avm_vm.c`
  - bytecode lowering recognizes the symbol names:
    - `lib/compiler/codegen_bytecode/010_codegen_a.oren` (`oren_select_recv`, `oren_select`)
- Native runtime implementation (rolling):
  - `lib/runtime_native/245_select.oren`
  - native channels:
    - macOS/Linux: pipe pairs `[rfd, wfd]` from `oren_new_channel()` in `lib/runtime_native/010_channels_globals_consts.oren`
    - Windows: in-memory channels from `oren_new_channel()` in `lib/runtime_native/011_channels_mem.oren`

Important consequence:

- The name `oren_select` is already a **cross-backend semantic surface** (AVM and native agree on the data encoding).
- It is the natural lowering target for any future language-level `select { ... }` syntax.

### 1.3 IO readiness wait helpers exist today (runtime functions)

The native runtime already provides fd readiness waits (currently under the NET subsystem):

- `oren_fd_wait_readable(fd, timeout_ms)`
- `oren_fd_wait_writable(fd, timeout_ms)`
- `oren_fd_wait_any_readable([fd...], timeout_ms, out_fd_ptr)`
- `oren_fd_wait_any_writable([fd...], timeout_ms, out_fd_ptr)`

OS implementations (facts from `lib/runtime_native/240_tcp.oren`):

- **macOS**: kqueue/kevent
- **Linux**: epoll
- **Windows**: WinSock `select()` (socket-only, default `FD_SETSIZE` constraints; rolling v0 keeps an explicit `nfds<=64` cap)

Notes:

- These are currently annotated `@cap.requires(domain="NET")` and call `native_capsule_require(CAP_NET, "NET")`,
  because they were introduced as part of the NET substrate.
- Readiness is treated as **advisory** (not an infallible contract):
  - All sockets are configured non-blocking.
  - Higher-level NET helpers (`oren_tcp_read_into` / `oren_tcp_write_from` / `oren_udp_sendto` / `oren_udp_recvfrom_into`) try `recv`/`send` first and tolerate occasional false timeouts from readiness waits by retrying until the caller deadline is exhausted.
  - Rolling x86_64 note: some NET entrypoints canonicalize i32-ish args (`timeout_ms`, `len`, `port`) to guard against non-canonical upper bits during Tier‑1 x64 native bring-up. Enable `OREN_DEBUG_CANON_I32=1` to emit a single warning when this guard triggers.
- Linux syscall ABI footgun (native, libc-free):
  - `epoll_event` layout differs by arch (`x86_64` packed 12 bytes vs `arm64` 16 bytes).
  - The native runtime probes this once at startup (`native_runtime_init`) and fills `OREN_EPOLL_EVENT_*`,
    which are then used by `oren_select` and the `oren_fd_wait_*` epoll helpers.
- They are **not a language keyword** (they are runtime helpers).
- Scheduler integration status (native, rolling):
  - The green-task scheduler exists (`lib/runtime_native/263_green_tasks.oren`).
  - 2026-01-16: native waits are green-aware (rolling, correctness-first):
    - `oren_select` / `oren_select_recv` (pipe-based channels): when called from a green task, waits via the shared scheduler netpoller (**netpoll v2**) and preserves deterministic selection without per-wake probe polling.
      - Guards: `tests/native/test_quick_integration_native.oren` (`test_select_in_green_workers`, `test_select_multi_case_in_green_workers`)
      - Rolling note: duplicate case fds are rejected (`EINVAL`) to keep semantics deterministic across the legacy per-call epoll/kqueue path and the shared netpoll v2 path.
    - `oren_fd_wait_*` (fd readiness): when called from a green task, parks the G and lets the scheduler drive readiness waits (no host-thread blocking).
      - POSIX: `lib/runtime_native/246_netpoll.oren` (kqueue/epoll + wake pipe)
      - Windows (rolling v0): `lib/runtime_native/246_netpoll.oren` uses WinSock `select()` over a watched set (`FD_SETSIZE=64` per call) and batches watches beyond 64.
        - Wake: best-effort loopback UDP wake socket in non-capsule builds; in capsule builds it is only created if loopback endpoints are explicitly allowed (no policy bypass). Without it, waits remain timeout-bounded.
        - IOCP is still the intended long-term “real netpoller” path (scalable readiness + HANDLE story).
      - Runtime: `lib/runtime_native/263_green_tasks.oren` (scheduler drains netpoll tokens)
      - Escape hatch (rolling): `OREN_NO_NETPOLL=1` disables netpoll bring-up for debugging.
      - Guard: `tests/native/test_net_suite.oren` (`test_fd_wait_socket_readable_in_green_workers`)

### 1.4 File readiness is not yet a stable cross-OS language primitive

Today, Oren does not specify a unified “readiness for any file descriptor/handle” abstraction across:

- macOS (kqueue can watch many fd types)
- Linux (epoll has limits; regular files don’t behave like sockets)
- Windows (sockets use WinSock; general HANDLE readiness is typically IOCP/overlapped I/O)

Current direction in the repo is:

- keep syscall-first primitives in the runtime (`sys_*`)
- introduce a scheduler + netpoller later, then expose a higher-level API

---

## 2) Design decision: `select` should be channel-based, not fd-based

We intentionally do **not** want a language keyword that directly expresses “wait on fd readiness”:

- fd readiness is OS-specific and hard to make portable (especially Windows).
- AVM needs determinism + snapshot portability; host fd readiness is inherently effectful.
- The language-level concurrency primitive should be **structured and composable**.

Instead, the design direction is:

1) Oren exposes **channels** as the core blocking primitive.
2) Oren exposes **`select` over channels** as the main multiplexer (Go-like conceptually).
3) “Async IO readiness” is represented by the runtime as **channel events** (netpoller → channel wakeups).

This matches the architecture used by modern runtimes (including Go’s runtime model), but must be adapted
to Oren’s deterministic AVM constraints.

---

## 3) How async IO readiness maps into channels (planned model)

### 3.1 Netpoller produces channel events

Introduce a runtime component (native + AVM-hosted variants) that:

- registers “interest” in fd readiness (readable/writable),
- blocks in the OS readiness API,
- wakes tasks and/or sends notifications into channels.

Conceptual API (design sketch; not implemented):

- `netpoll.readable(fd) -> ch<bool or fd>`
- `netpoll.writable(fd) -> ch<bool or fd>`

Then user code can do:

```oren
select {
  case _ = recv(netpoll.readable(fd)): { ... }
  case _ = recv(netpoll.writable(fd)): { ... }
  default: { ... } // optional
}
```

### 3.2 AVM determinism boundary

For AVM, “fd readiness” cannot be a direct host effect in consensus mode.

The model is:

- use `vnet` / `vfs` / `vproc` backends for deterministic testing/snapshots
- host readiness is only allowed under explicit capability + recording/replay constraints

References:

- `docs/AVM_SPEC.md` (VirtualFS/VirtualNET/VirtualPROC backends)
- `docs/AVM_MULTIVERSE.md` (nested universes / host service constraints)

### 3.3 Current native status: `spawn` is rolling toward green tasks + N:M

In the native backend today, `spawn` is a rolling surface with OS-specific behavior:

- **macOS/Linux (POSIX rolling):** `spawn` **prefers in-process green tasks** (shared heap + shared GC model) and falls back to fork+pipe when
  green tasks are disabled/unavailable.
  - Escape hatch: `OREN_NO_GREEN=1` forces legacy fork+pipe for bring-up/debugging.
- **Windows x64 Tier‑1 (rolling):** `spawn` uses **CreateThread** (OS threads) via the native runtime helper (`oren_spawn_call_list`),
  and `oren_join(_timeout)` uses Win32 synchronization.
  - Note: the green-task runtime exists (and Windows has a rolling socket netpoll path for in-green fd waits), but language-level `spawn`
    remains OS-thread based on Windows until the default scheduler topology can safely guarantee forward progress under host-thread blocking syscalls.

This is why the design direction here emphasizes “channel-based select” + “netpoller wakes channels”:
it composes with both a future native scheduler and AVM determinism, without baking OS fd/HANDLE details into the language surface.

---

## 4) Proposed future language syntax: `select { case ... }` (planned)

Once CoreIR + scheduler are stable, we want a language-level `select` statement for readability:

- It is **syntax sugar** over `oren_select(...)`.
- It does not directly expose OS-level fd readiness.

The exact surface syntax is intentionally deferred until:

- CoreIR is the canonical semantics owner (`docs/BACKEND_ARCHITECTURE.md`)
- native scheduler exists (`docs/NATIVE_GMP_SCHEDULER.md`)

But the semantic target is already stable:

- `oren_select_recv([ch...])`
- `oren_select([[0,ch], [1,ch,val], ...])`

---

## 5) OS-specific implementation plan (when we do scheduler + netpoll)

### 5.1 macOS

- readiness backend: kqueue/kevent
- task parking/unparking: ulock-based (rolling plan)

### 5.2 Linux

- readiness backend: epoll (or io_uring later if needed)
- task parking/unparking: futex-like primitives (rolling plan)

### 5.3 Windows

Windows is the main reason we do not want an fd-based language `select`:

- WinSock `select()` covers sockets only.
- general file HANDLE readiness is typically IOCP/overlapped I/O and doesn’t map 1:1 to POSIX fds.

Planned direction:

- a Windows netpoller using IOCP for sockets
- a separate FS async layer (thread pool or overlapped IO) if needed
- channels/select remain the language surface

Current (rolling, correctness-first):

- `oren_select` works for **in-memory channels** on Windows (not pipe fds).
- In-green `oren_select` on Windows is currently channel-only:
  - In-memory channels park the G on runtime wait lists and are woken explicitly on channel send/recv (no 1ms polling loop).
  - Pipe-fd readiness is still POSIX-only.
- In-green IO readiness on Windows (rolling v0):
  - `oren_fd_wait_readable` / `oren_fd_wait_writable` can park a green task and rely on the scheduler netpoller.
  - Implementation is WinSock `select()` over a small watched set (`FD_SETSIZE=64` cap); it is not IOCP yet.
  - The scheduler keeps kernel waits bounded in worker mode (STW safety), so the lack of a wake FD is acceptable for now.

---

## 6) Tracking (what to implement next)

This doc is not the tracker; the tracker is `docs/TODOS.md`.

The relevant near-term items are:

- Tier‑1 native parity (x86_64 + arm64; macOS/Linux/Windows) — see `docs/TODOS.md` P0.1
- Backend architecture unification (CoreIR boundary) — see `docs/TODOS.md` P0.3
- After that: native scheduler + channels/select maturity and IO integration — see `docs/CONCURRENCY_MODEL.md` / `docs/NATIVE_GMP_SCHEDULER.md`
