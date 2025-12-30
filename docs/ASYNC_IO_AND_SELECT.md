# Async IO Readiness + `select` in Oren (Rolling Design + Current Reality)

**Last updated:** 2025-12-30

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
- Native runtime implementation (macOS/Linux only, rolling):
  - `lib/runtime_native/245_select.oren`
  - native channels are currently pipe pairs `[rfd, wfd]` from `oren_new_channel()` in `lib/runtime_native/010_channels_globals_consts.oren`

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
- They are **not a language keyword** and they are not yet integrated with a scheduler (they block the calling OS thread).

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

---

## 6) Tracking (what to implement next)

This doc is not the tracker; the tracker is `docs/TODOS.md`.

The relevant near-term items are:

- Tier‑1 native parity (x86_64 + arm64; macOS/Linux/Windows) — see `docs/TODOS.md` P0.1
- Backend architecture unification (CoreIR boundary) — see `docs/TODOS.md` P0.3
- After that: native scheduler + channels/select maturity and IO integration — see `docs/CONCURRENCY_MODEL.md` / `docs/NATIVE_GMP_SCHEDULER.md`

