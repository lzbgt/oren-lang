# Networking and IO (Rolling)

This document consolidates async IO, network stacks, and platform-specific netpoll notes.

## Async IO Readiness + `select` in Oren (Rolling Design + Current Reality)

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
- `docs/AVM_ROADMAP.md#avm-in-avm-multiverse-design-nested-virtual-universes` (nested universes / host service constraints)

### 3.3 Current native status: `spawn` is rolling toward green tasks + N:M

In the native backend today, `spawn` is a rolling surface with OS-specific behavior:

- **macOS/Linux (POSIX rolling):** `spawn` **prefers in-process green tasks** (shared heap + shared GC model) and falls back to fork+pipe when
  green tasks are disabled/unavailable.
  - Escape hatch: `OREN_NO_GREEN=1` forces legacy fork+pipe for bring-up/debugging.
- **Windows x64 Tier‑1 (rolling):** `spawn` now **prefers in-process green tasks** (shared heap + shared GC model), matching POSIX.
  - Escape hatch: `OREN_NO_GREEN=1` disables green tasks; Windows then falls back to a runtime-owned OS-thread `spawn`.

This is why the design direction here emphasizes “channel-based select” + “netpoller wakes channels”:
it composes with both a future native scheduler and AVM determinism, without baking OS fd/HANDLE details into the language surface.

---

## 4) Proposed future language syntax: `select { case ... }` (planned)

Once CoreIR + scheduler are stable, we want a language-level `select` statement for readability:

- It is **syntax sugar** over `oren_select(...)`.
- It does not directly expose OS-level fd readiness.

The exact surface syntax is intentionally deferred until:

- CoreIR is the canonical semantics owner (`docs/COMPILER.md`)
- native scheduler exists (`docs/STDLIB_AND_RUNTIME.md`)

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
  - Wake (best-effort): non-capsule builds create a loopback UDP wake socket so `native_netpoll_wake()` can break a blocking select immediately.
    - Watch-table updates also call `native_netpoll_wake()` when the wake socket exists, so new registrations are observed promptly even with longer select timeouts.
    - In capsule mode, the wake socket is only created if loopback is explicitly allowed; otherwise waits remain bounded by short timeouts (polling fallback; correctness-first).
  - STW GC integration: stop-the-world now calls `native_netpoll_wake()` so OS threads blocked in select can observe STW promptly (no 10ms global clamp requirement).

---

## 6) Tracking (what to implement next)

This doc is not the tracker; the tracker is `docs/TODOS.md`.

The relevant near-term items are:

- Tier‑1 native parity (x86_64 + arm64; macOS/Linux/Windows) — see `docs/TODOS.md` P0.1
- Backend architecture unification (CoreIR boundary) — see `docs/TODOS.md` P0.3
- After that: native scheduler + channels/select maturity and IO integration — see `docs/LANGUAGE_APPENDICES.md` / `docs/STDLIB_AND_RUNTIME.md`
  - Windows IOCP design notes (rolling): `docs/NETWORKING_IO.md`

## Windows IOCP Netpoller (Native Runtime) — Design Notes (Rolling)

**Last updated:** 2026-02-13  
**Scope:** Windows x64 native runtime netpoller (future replacement for select-v0)  
**Non-goal:** shipping a full Windows async FS layer in the same step

This doc is a *design + implementation checklist* for upgrading Windows readiness in the native runtime from:

- current: WinSock `select()` watch-table batching (`lib/runtime_native/246_netpoll.oren`, `FD_SETSIZE=64` per call), to
- target: **IOCP** (I/O Completion Ports) for scalable, wake-driven async socket I/O.

The repo is rolling; this design may evolve, but it must remain **fact-based** and anchored in primary docs and tests.

## Primary reference snapshots (verbatim HTML)

The authoritative source content is stored in-tree under:

- `project-doc/web/learn.microsoft.com/iocp/20260117/`
  - `SOURCES.txt` lists all downloaded URLs.
- `project-doc/web/learn.microsoft.com/winsock/20260213/`
  - `SOURCES.txt` lists all downloaded URLs.

## Current repo status (fact)

- 2026-01-17: runtime recognizes IOCP and has an **IOCP poll core + wake** substrate (when IOCP backend is selected):
  - Init: `native_netpoll_init_once` creates an IOCP via `CreateIoCompletionPort(INVALID_HANDLE_VALUE, ...)`
  - Poll: `native_netpoll_poll_many_scratch` calls `GetQueuedCompletionStatusEx` (allocation-free scratch)
  - Wake: `native_netpoll_wake()` uses `PostQueuedCompletionStatus` (no loopback dependency)
  - Token selection (rolling): IOCP poll now returns the **OVERLAPPED pointer** when present (`ov!=0`),
    falling back to the completion key only when `ov==0`. Wake packets use `key==0, ov==0` and are ignored.
  - IOCP wait node layout (rolling): a small struct embeds the Win64 `OVERLAPPED` header (32 bytes) and then
    appends netpoll metadata (magic, `G*`, epoch, ready) plus a `bytes` slot. Poll captures `dwNumberOfBytesTransferred`
    into the wait node when the magic matches.
  - Implementation: `lib/runtime_native/246_netpoll.oren`
  - Rolling limitation: IOCP readiness was initially absent; as of 2026‑02‑13 a bridge exists for
    `oren_fd_wait_readable/…_writable` using zero‑byte overlapped `WSARecv/WSASend`, but it is not yet
    reliable for UDP readiness (see below). Completion‑driven socket ops remain the preferred end‑state
    (Strategy B).
- 2026-02-13: IOCP backend selection + readiness bridge (Strategy A) for green‑task socket waits is **gated**:
  - IOCP backend selection currently requires **both** `OREN_NETPOLL_WIN_IOCP=1` **and** `OREN_NETPOLL_WIN_IOCP_READY=1`.
  - Without `OREN_NETPOLL_WIN_IOCP_READY=1`, the runtime keeps select‑v0 for Tier‑1 correctness.
  - Motivation (fact): Win11 IOCP readiness is still unreliable today:
    - UDP: `WSARecvFrom` reports `WSAEFAULT (10014)` under the readiness bridge.
    - TCP: HTTP loopback can time out under IOCP readiness (headers never fully read).
  - Implementation: `lib/runtime_native/246_netpoll.oren` (backend selection + readiness fallback).
- 2026-01-17: x64-windows now has syscall/intrinsic plumbing + PE imports for the IOCP core APIs:
  - Runtime stubs: `lib/runtime_native/000_prelude_sys.oren`
  - x64 syscall lowering (Win64 ABI, kernel32 IAT): `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net.oren`
  - PE imports (KERNEL32.dll): `lib/compiler/x64_pe.oren` (appended imports; existing IAT offsets preserved)
  - Non-Windows fallback: these syscalls lower to `-ENOSYS` on x64/arm64 so runtime-gated code keeps compiling.
- 2026-01-17: x64-windows also has WinSock overlapped syscall plumbing needed for IOCP completion-based NET ops:
  - `sys_wsarecv` / `sys_wsasend` lower to `WSARecv` / `WSASend` (treats `WSA_IO_PENDING` as success).
  - PE imports (WS2_32.dll) appended: `WSARecv`, `WSASend`.
  - Capsule boundary hooks exist (NET capability required): `lib/runtime_native/070_capsule_net_hooks.oren`.

## Why IOCP (vs select-v0)

The current Windows netpoll v0 exists to unblock Tier‑1 bring-up (green tasks can wait on socket readability/writability),
but it is fundamentally limited:

- `select()` is socket-only and constrained by `FD_SETSIZE` per call (we batch watches; still inefficient).
- Waking a blocking `select()` requires a wake socket; in capsule mode loopback wake is not always allowed.
- Readiness-based polling is not the long-term shape on Windows; completion-based overlapped I/O is.

IOCP provides:

- scalable completion queue semantics (no `FD_SETSIZE` cap)
- an explicit wake primitive (`PostQueuedCompletionStatus`) that does not require loopback
- a natural path to a future “HANDLE story” if we later extend beyond sockets

## Architectural constraint: readiness vs completion

Oren’s POSIX netpoller is currently **readiness** oriented:

- `native_netpoll_arm_fd(fd, want_write, token)`
- `native_netpoll_poll_many_scratch(timeout_ms, ...)` returns tokens

IOCP is **completion** oriented:

- you post an overlapped I/O operation (e.g. `WSARecv`) and later you receive a completion record that includes:
  - the completion key (per-handle association)
  - an `OVERLAPPED*` pointer (per-operation identity)
  - bytes transferred + status

Therefore the Windows IOCP implementation must pick one of two strategies:

### Strategy A (bridge): emulate “readiness” by posting zero-byte operations

Concept:

- To wait for readability, post a 0-byte `WSARecv` (or a peek) with an `OVERLAPPED` that represents “wait readable”.
- Completion means “socket became readable” (or closed/error).

Pros:

- keeps the current `oren_fd_wait_readable/writable` surface mostly intact
- allows the scheduler netpoller to remain “token-driven”

Cons:

- cancellation and correct interpretation are subtle (need `CancelIoEx` / socket close semantics)
- not obviously lower-overhead than just doing the real read/write

### Strategy B (preferred end state): make Windows NET operations overlapped-first

Concept:

- Replace blocking/non-blocking `sys_recv/sys_send` wait loops on Windows with overlapped ops:
  - `oren_tcp_recv` issues `WSARecv(..., OVERLAPPED*)` and yields the current `G`
  - completion wakes the `G` and provides bytes/result directly

Pros:

- aligns with how IOCP is meant to be used (completion, not readiness polling)
- avoids duplicated syscalls: no “wait readable then recv”; the recv is the wait

Cons:

- larger refactor (touches the NET stack implementation, buffer ownership, and cancellation story)

Rolling decision:

- Implement **Strategy A** only if it meaningfully reduces short-term risk for Tier‑1 parity.
- Otherwise proceed directly with Strategy B for sockets, keeping the language-level surface unchanged (channels/select remain the surface).

## Required primitives (Windows)

These are the minimum kernel/user APIs we need, per the primary docs snapshot folder:

IOCP core:

- `CreateIoCompletionPort`
- `GetQueuedCompletionStatusEx` (preferred) or `GetQueuedCompletionStatus`
- `PostQueuedCompletionStatus` (wake/nudge mechanism for the scheduler)
- `CancelIoEx` (best-effort cancellation of pending ops; required for timeouts)

WinSock overlapped I/O:

- `WSARecv`, `WSASend`
- `WSAGetOverlappedResult` (optional; mostly for debugging/verification)
- `WSAIoctl` to query extension functions:
  - `AcceptEx` / `ConnectEx` pointers (via `SIO_GET_EXTENSION_FUNCTION_POINTER`)

Data structures:

- `OVERLAPPED` / `WSAOVERLAPPED`

## Proposed runtime data model (v1)

### 1) One global IOCP for the process (initially)

- `g_netpoll_iocp` is a process-global handle (similar to `g_netpoll_fd` on POSIX).
- Sockets that will be used by the async runtime are associated via `CreateIoCompletionPort(sock, g_netpoll_iocp, completion_key, 0)`.

### 2) Per-operation objects (“IO wait nodes”)

We need a stable, long-lived object to represent a pending overlapped I/O operation so the completion callback can map back to a `G`.

Minimum fields:

- `OVERLAPPED` storage (must be embedded or address-stable)
- `G*` pointer
- operation kind (read/write/connect/accept/wake)
- deadline / timeout bookkeeping (so timeouts can cancel + resume)
- result slots (rc, bytes) to return to the resumed code path

Important:

- This should reuse the existing scheduler “token” pattern where possible:
  - netpoll returns an opaque pointer token
  - scheduler treats token either as a `G*` (legacy) or a structured wait token (like netpoll v2 `native_netpoll_wait_*`)

### 3) Wake path integration

On POSIX, wake is “write 1 byte to wake pipe”.

On IOCP, wake should be:

- `PostQueuedCompletionStatus(iocp, 0, key=WAKETOKEN, overlapped=NULL)` or a dedicated overlapped pointer.

This must be allocation-free and safe from any OS thread (mirrors the constraints on `native_netpoll_wake()` today).

## Test gates (must be added as we implement)

As IOCP work lands, add/extend Tier‑1 guards:

- Prove the netpoll wake path breaks a blocked `GetQueuedCompletionStatusEx` without loopback:
  - Fixture: `tests/fixtures/windows_iocp_wake_smoke.oren`
    - Run with: `OREN_NETPOLL_WIN_IOCP=1`
    - Wired into: `scripts/verify_native_matrix.sh --targets x64-win-tier1` (stage1 + stage2; remote Win11)
  - Smoke: IOCP poll returns the OVERLAPPED pointer token when `PostQueuedCompletionStatus` sets `ov!=0`,
    and captures `dwNumberOfBytesTransferred` into the wait node’s `bytes` slot.
  - add a Windows-only fixture analogous to `test_gc_stw_wakes_netpoll_blocked_threads`
- Prove timeouts do not leak:
  - bounded IO operation with timeout that cancels successfully and does not leave “stuck overlapped” state
- Keep `make test` bounded (no 1s sleeps in hot path on real Windows host)

Tracker link:

- `docs/TODOS.md` item “Native scheduler + netpoller”

## TLS / HTTPS / WSS (stdlib, native backend) — rolling

This doc defines the **stdlib contract** for TLS in Oren and the implementation strategy needed to support:

- `https://` in `std:net/http`
- `wss://` in `std:net/ws`
- “secure TCP” primitives in `std:net/tcp` (via a TLS wrapper)

Related crypto modules (shared, not NET-specific):

- `std:crypto/pem` (decode PEM blocks)
- `std:crypto/x509` (small certificate helpers; rolling v0)

Tier‑1 targets (rolling intent):

- `arm64-macos`
- `arm64-linux` (docker container)
- `x64-windows` (remote Win11)
- `x64-linux` (remote WSL2)

Last verification (fact):

- 2026-01-10: `make verify-native-net-skip-remote` passed on:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container `c7e5f7bd9f5c`)
- 2026-01-12: `make verify-native-net` passed on remote x64 hosts (stage1 + stage2), covering:
  - `x64-windows` (remote Win11)
  - `x64-linux` (remote WSL2)
- 2026-01-10: `make verify-x64-linux-qemu-tls` passed on:
  - `x64-linux` under QEMU in docker container `c7e5f7bd9f5c` (stage1 + stage2; TLS/HTTPS/WSS loopbacks, plus HTTP/2/HPACK smokes)
- `x64-linux` / `x64-windows` runs require the remote Win11 (WSL2 optional) host; see `docs/PLATFORMS.md` if the proxy/hostname is unavailable.

## 1) Constraints (why this design exists)

### 1.1 No external connectivity in regression

Tier‑1 NET gates are loopback-only (`scripts/verify_native_net_matrix.sh`). TLS must be testable offline:

- the test suite should not contact public hosts
- results must be deterministic (bounded timeouts, no flaky DNS/CA store dependencies)

### 1.2 Stdlib must be self-contained (no Makefile flags)

For portability, stdlib must not require consumers to pass `--link ...` manually.

Rolling rule:

- OS bindings that require dynamic libraries should declare them on the `ffi` statement itself via:
  - `@ffi.link("...")` (portable; maps to `--link ...`)
  - `@ffi.dll("...")` (Windows x64 convenience; treated as `--link` in the build pipeline too)

See:

- `docs/TODOS.md` (native FFI parity)
- `docs/BACKENDS.md#native-backend-overview` (native dynamic linking model)

## 2) Stdlib API (`std:net/tls`)

Goal: a **small, syscall-first shaped** API that can wrap a TCP socket and provide a stable surface for HTTPS/WSS.

### 2.1 Types / shapes (v0)

We model a TLS connection as an **opaque map**:

- `{"fd": int, "impl": string, "state": ...}`

The `state` field is backend-specific (pointer/handle integers), and is not accessed by user code.

### 2.2 Client connect / wrap

Functions (rolling v0):

- `tls.connect(host_or_ip, port, timeout_ms, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Dial TCP + do TLS handshake.
  - DNS behavior:
    - if `host_or_ip` looks like an IPv4 literal, no DNS is performed
    - otherwise, the host is resolved via DNS A query
      - if `opts["resolver"]` is provided, it is used
      - else `dns.default_resolver(timeout_ms)` is used internally
- `tls.wrap_client(fd, server_name, timeout_ms, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Wrap an already-connected TCP `fd` (useful for proxies).

`opts` (rolling v0):

- `opts["alpn"]`: list of strings (e.g. `["h2", "http/1.1"]`) (optional)
- `opts["verify"]`: `1|0` (default: `1`) (planned; provider-dependent)
- `opts["insecure_skip_verify"]`: `1|0` (default: `0`) (implemented on macOS + Linux + Windows providers; see §5)
  - Intended for **offline loopback fixtures** only; callers should pin the peer cert (see §3).
- `opts["server_name"]`: override SNI/server name when dialing by IP (used by loopback fixtures and proxies)
  - Note: `tls.connect` does not send IPv4 literals as SNI by default; use `opts["server_name"]` when needed.
- `opts["resolver"]`: optional DNS resolver config (`dns.resolver(...)`) used by `tls.connect` for hostname lookups.
- `opts["pin_cert_sha256_hex"]`: optional pinned leaf certificate hash (SHA-256 of DER; hex string)
  - Enforced by `tls.wrap_client` post-handshake (so higher layers don’t duplicate pinning logic).

### 2.3 IO

- `tls.read_into(conn, buf, cap, timeout_ms)` → `n` or `-errno`
- `tls.write_from(conn, ptr, len, timeout_ms)` → `n` or `-errno`
- `tls.close(conn)` → `0` or `-errno`
- `tls.win_cleanup()` → `0` (rolling)
  - No-op on non-Windows.
  - On Windows/Schannel: releases cached credential material; intended for shutdown / test harness cleanup.

Note:

- The IO functions must be timeout-bounded and should follow the existing NET policy:
  - treat readiness waits as advisory
  - retry until deadline expires

### 2.4 Introspection (rolling v0)

- `tls.peer_cert_sha256_hex(conn)` → `{"ok":1,"v":string}` or `{"ok":0,"err":string}`
  - Returns the **leaf** certificate hash (SHA‑256 of DER) for deterministic pinning in loopback fixtures.
- `tls.negotiated_alpn(conn)` → `{"ok":1,"v":string|nil}` or `{"ok":0,"err":string}`
  - Returns the negotiated ALPN protocol (e.g. `"h2"`) if ALPN was negotiated.
  - Loopback fixtures pass `opts["alpn"]` to exercise ALPN plumbing. Current behavior is provider-dependent:
    - Windows (Schannel): server-side ALPN selection is wired; loopback asserts `"http/1.1"` is negotiated.
    - Linux (OpenSSL): server-side ALPN selection is wired; loopback asserts `"http/1.1"` is negotiated.
    - macOS (SecureTransport): treated as best-effort; loopback does not assert a negotiated protocol yet.

## 3) Testing strategy (offline + deterministic)

TLS needs a loopback server fixture that is consistent across OS.

Planned approach:

1) Embed a deterministic self-signed certificate + private key in the test fixture (PEM or raw DER bytes).
2) Use a fixed hostname (e.g. `oren.test`) and rely on:
   - explicit loopback DNS resolver injection (already done for HTTP/WS tests), or
   - direct `127.0.0.1` connect and SNI override via `server_name`.
3) Verify by **pinning**:
   - `opts["pin_sha256"]` = SHA-256 of SPKI or full cert DER

This avoids relying on host CA stores (which vary by OS and are not deterministic in tests).

Implementation note (macOS provider bring-up):

- Oren’s syscall-first native runtime currently implements language-level `spawn` as **fork-based** (process boundary).
- Apple Security/CoreFoundation APIs are not guaranteed to be safe when called in a post-fork child without `exec`.
- The Tier‑1 TLS loopback fixture therefore uses a **fork+exec** server mode (single binary with `server` argv) instead of `spawn`.

## 4) Implementation plan (providers)

TLS is implemented via **OS providers** (FFI) per Tier‑1 OS:

- `arm64-macos`: Security.framework (SecureTransport / TLS APIs)
- `x64-windows`: SChannel / SSPI (`secur32.dll`, `crypt32.dll`)
- `arm64-linux` + `x64-linux`: OpenSSL 3 (loaded lazily at runtime via `dlopen(..., RTLD_GLOBAL)`)

Rationale:

- Native backend already supports dynamic linking (`--link`) on all Tier‑1 targets.
- Provider APIs handle modern TLS versions/ciphersuites, and can be validated incrementally.

## 5) Current status

- `std:net/tls` exists (rolling v0):
  - macOS provider (SecureTransport) is implemented for:
    - `tls.wrap_client`
    - `tls.wrap_server_pkcs12`
    - `tls.read_into` / `tls.write_from` / `tls.close`
    - `tls.peer_cert_sha256_hex` (leaf certificate SHA-256 of DER)
  - Client verification behavior:
    - default: platform verification (may reject loopback self-signed fixtures)
    - `opts["insecure_skip_verify"]=1`: disables platform verification so deterministic fixtures can rely on pinning
  - macOS provider requires a small toolchain bridge:
    - SecureTransport IO callbacks must be passed as **raw function pointers**
    - Oren marks these callbacks with `@ffi.export` and resolves them via `dlsym(RTLD_DEFAULT, ...)`
    - SecureTransport has two distinct IO APIs:
      - IO callbacks (`SSLSetIOFuncs`) use 3-arg `SSLReadFunc`/`SSLWriteFunc` signatures
      - application IO (`SSLRead`/`SSLWrite`) use 4 args (`data`, `dataLength`, `processed*`)
    - SecureTransport APIs return `OSStatus` (signed 32-bit). `ffi` declarations that return `OSStatus`
      are annotated with `@ffi.ret("i32")` so the native backend sign-extends return values correctly.
- Regression gate:
  - `tests/native/test_tls_loopback.oren` is integrated into `scripts/verify_native_net_matrix.sh` (stage1 + stage2; local loopback).
- Higher-level integrations (rolling):
  - `std:net/http` supports `https://` via `http.get_response_resolver_opts` / `http.get_response_opts` (uses `tls.wrap_client`).
    - Regression gate: `tests/native/test_https_get_loopback.oren` (loopback-only; deterministic; uses pinning).
  - `std:net/ws` supports `wss://` via `ws.connect_resolver_opts` (uses `tls.wrap_client`).
    - Server helper: `ws.accept_tls_pkcs12` (wraps `tcp.accept` + `tls.wrap_server_pkcs12` + WS handshake).
    - Regression gate: `tests/native/test_wss_echo_loopback.oren`.
- Note: TLS provider availability is still OS-dependent; on non-macOS/non-Linux/non-Windows targets these fixtures compile but exit(0) until providers land.

Why the loopback TLS fixture uses `@cfg(...)`:

- `tests/native/test_tls_loopback.oren` is **one source file** intended to validate the same TLS contract on Tier‑1 OS targets (macOS, Linux, Windows).
- A small amount of `@cfg(os=...)` glue is required because the spawn/runtime boundary differs:
  - On Windows, the spawn runtime is thread-based; spawned workers must **return** an exit code and must not call `exit(...)` (that would terminate the whole process).
  - On POSIX targets, spawn/fork-based helpers can use process-exit semantics, but the fixture still keeps the worker portable by returning a code.
- The *behavior under test* stays the same across OS (loopback TLS handshake + read/write echo + pinning); `@cfg` exists only to select the appropriate entrypoints and OS-specific plumbing.

### 5.1 Linux provider (OpenSSL)

As of **2026-01-08 (rolling)**, `std:net/tls` has a Linux provider implemented in `lib/std/net/tls_linux_openssl.oren` (facade: `lib/std/net/tls.oren`):

- Dynamic linking:
  - OpenSSL libraries are **not** added to DT_NEEDED by default.
  - `std:net/tls` loads `libcrypto.so.3` + `libssl.so.3` lazily via `dlopen(..., RTLD_GLOBAL)` during `_openssl_init()`.
    - This avoids forcing non-TLS binaries that merely import `std:net/http` / `std:net/ws` to have OpenSSL present at program load time.
    - If OpenSSL is not present, TLS functions return a structured error instead of the whole binary failing to load.
- Implemented surface:
  - `wrap_client`, `wrap_server_pkcs12`
  - `read_into`, `write_from`, `close`
  - `peer_cert_sha256_hex` (leaf certificate SHA-256 of DER; via `SSL_get1_peer_certificate` + `i2d_X509`)
  - `negotiated_alpn` (best-effort; via `SSL_get0_alpn_selected`)
- Regression gate:
  - `scripts/verify_native_net_matrix.sh --targets arm64-linux,x64-wsl` runs:
    - `tests/native/test_tls_loopback.oren`
    - `tests/native/test_https_get_loopback.oren`
    - `tests/native/test_wss_echo_loopback.oren`

Implementation notes (Linux):

- **SIGPIPE is ignored** (`signal(SIGPIPE, SIG_IGN)`) so failed socket writes return `-EPIPE` instead of killing the process.
- **FFI `int` return lowering is explicit** (compiler-level):
  - Many OpenSSL APIs return `int` (signed 32-bit). Native ABIs do not require the upper 32 bits of the return register to be sign-extended.
  - Oren uses 64-bit value carriers, so the `ffi` declaration must specify the ABI return width, e.g. `@ffi.ret("i32")`, and the native backend sign-extends the return after the call.
- **SNI is wired** on Linux (client):
  - `SSL_set_tlsext_host_name` is a macro in OpenSSL (not a linkable symbol), so we wire SNI via `SSL_ctrl(...)`.
  - Oren uses numeric constants taken from the Tier‑1 Linux headers (`libssl-dev`, Ubuntu noble):
    - `SSL_CTRL_SET_TLSEXT_HOSTNAME = 55` (`/usr/include/openssl/ssl.h`)
    - `TLSEXT_NAMETYPE_host_name = 0` (`/usr/include/openssl/tls1.h`)
  - `std:net/tls` chooses the server-name as:
    - prefer explicit `wrap_client(..., server_name, ...)`
    - fallback to `opts["server_name"]` if the argument is missing (useful for already-connected sockets / proxies)
- **ALPN is wired** on Linux (client offer):
  - `opts["alpn"]` is interpreted as a list of protocol strings (e.g. `["h2","http/1.1"]`).
  - The OpenSSL provider builds the wire-format protocol list and calls `SSL_set_alpn_protos`.
  - Note: `SSL_set_alpn_protos` returns **0 on success** (reversed convention); see sources below.
  - Server-side selection is wired as well:
    - The provider uses `SSL_CTX_set_alpn_select_cb` to select the first server-preferred protocol that appears in the client offer.
    - This relies on `@ffi.export` being supported for Linux native executables (ELF) so the callback symbol is visible to `dlsym(RTLD_DEFAULT, ...)`.

Sources captured for audit/reference:

- `project-doc/web/openssl/SSL_connect.html`
- `project-doc/web/openssl/SSL_read.html`
- `project-doc/web/openssl/SSL_get_error.html`
- `project-doc/web/openssl/PKCS12_parse.html`
- `project-doc/web/openssl/d2i_X509.html`
- `project-doc/web/openssl/SSL_CTX_ctrl.html` (covers `SSL_ctrl` return semantics)
- `project-doc/web/openssl/SSL_CTX_set_alpn_select_cb.html` (covers `SSL_set_alpn_protos` return semantics)

### 5.2 Windows provider (Schannel / SSPI)

As of **2026-01-10 (rolling)**, `std:net/tls` has a Windows provider implemented in `lib/std/net/tls_windows_schannel.oren` (facade: `lib/std/net/tls.oren`):

- Dynamic linking:
  - `@ffi.dll("secur32.dll")` (SSPI)
  - `@ffi.dll("crypt32.dll")` (PFX import + cert hash)
- Implemented surface:
  - `wrap_client`, `wrap_server_pkcs12`
  - `read_into`, `write_from`, `close`
  - `peer_cert_sha256_hex` (leaf hash via `SECPKG_ATTR_REMOTE_CERT_CONTEXT` + `CERT_SHA256_HASH_PROP_ID`)
  - `negotiated_alpn` (best-effort; via `SECPKG_ATTR_APPLICATION_PROTOCOL`)
- Regression gate:
  - `scripts/verify_native_net_matrix.sh --targets x64-win` runs (stage1 + stage2):
    - `tests/native/test_tls_loopback.oren`
    - `tests/native/test_https_get_loopback.oren`
    - `tests/native/test_wss_echo_loopback.oren`
- Rolling status (2026-02-14): Win11 TLS loopbacks now run on green tasks by default.
  - Fallback: set `OREN_TLS_USE_OS_THREAD=1` to force OS-thread spawn for server/client.
  - Verified via `scripts/verify_native_net_matrix.sh --targets x64-win` (TLS/HTTPS/WSS/HTTP2 loopbacks).

Implementation notes (Windows):

- **Credential lifetime is process-cached (rolling)**:
  - Some Win11 x64 environments are sensitive to the lifetime of the `SCHANNEL_CRED` (and its `paCred` array)
    passed into `AcquireCredentialsHandleA`, even after `FreeCredentialsHandle` returns.
  - To keep TLS/HTTPS/WSS stable across long code paths, the provider caches Schannel credentials per-process and
    keeps the `SCHANNEL_CRED` memory alive for the lifetime of the process:
    - client: cached by `insecure_skip_verify` (0/1)
    - server: cached by `(pkcs12_bytes, passphrase)` (hash key is `sha256(pkcs12_bytes) + ":" + sha256(passphrase_bytes)`)
  - `tls.win_cleanup()` exists (rolling):
    - Releases cached Schannel credential material (client + server).
    - Must only be called when no active TLS connections exist (intended for shutdown / test harness cleanup).
    - Rolling caveat: server credentials are treated as “one certificate per process”; the provider does not replace cached server credentials in-process.
- **Server handshake must start with input**:
  - `AcceptSecurityContext` is not guaranteed to establish a context handle when called with a zero-length input token.
  - The server handshake loop therefore reads the initial ClientHello bytes before the first `AcceptSecurityContext` call.
- **ALPN is wired** (client offer):
  - `opts["alpn"]` is interpreted as a list of protocol strings (e.g. `["h2","http/1.1"]`).
  - The Schannel provider builds a `SEC_APPLICATION_PROTOCOLS` blob and passes it via a
    `SecBuffer` of type `SECBUFFER_APPLICATION_PROTOCOLS` into `InitializeSecurityContextA`.
  - Sources captured: `project-doc/web/microsoft/sspi/` (SecBuffer + SEC_APPLICATION_PROTOCOLS docs).
  - Server-side ALPN selection is wired as well:
    - The same `SECBUFFER_APPLICATION_PROTOCOLS` buffer is supplied on the first `AcceptSecurityContext` call.
    - When ALPN is present, Schannel does not guarantee which input buffer slot receives `SECBUFFER_EXTRA`, so the implementation scans all input buffers for EXTRA.
- **Schannel `DecryptMessage` buffer semantics**:
  - The plaintext DATA buffer can be a pointer into the encrypted buffer.
  - Copy plaintext out before shifting the EXTRA encrypted tail, and use overlap-safe moves when shifting tails.

### 5.3 macOS provider (SecureTransport)

As of **2026-01-09 (rolling)**, `std:net/tls` has a macOS provider implemented in `lib/std/net/tls_macos_securetransport.oren` (facade: `lib/std/net/tls.oren`):

- Dynamic linking:
  - `@ffi.link("/System/Library/Frameworks/Security.framework/.../Security")`
  - `@ffi.link("/System/Library/Frameworks/CoreFoundation.framework/.../CoreFoundation")`
- Implemented surface:
  - `wrap_client`, `wrap_server_pkcs12`
  - `read_into`, `write_from`, `close`
  - `peer_cert_sha256_hex` (leaf hash via `SSLCopyPeerTrust` + `SecCertificateCopyData`)
  - `negotiated_alpn` (best-effort; via `SSLCopyALPNProtocols`)
- Regression gate:
  - `scripts/verify_native_net_matrix.sh --targets arm64-macos` runs:
    - `tests/native/test_tls_loopback.oren`
    - `tests/native/test_https_get_loopback.oren`
    - `tests/native/test_wss_echo_loopback.oren`

Implementation notes (macOS):

- **SNI is wired** (client):
  - `wrap_client(..., server_name, ...)` calls `SSLSetPeerDomainName`.
- **ALPN is wired** (client offer):
  - `opts["alpn"]` is interpreted as a list of protocol strings (e.g. `["h2","http/1.1"]`).
  - The SecureTransport provider converts the list into `CFArrayRef` of `CFStringRef` and calls `SSLSetALPNProtocols` (client + server contexts).
  - `tls.negotiated_alpn` remains best-effort on SecureTransport; the loopback fixture currently does not assert a negotiated protocol on macOS.

## HTTP/2 in Oren (Rolling Status)

This document captures the current (rolling) state of Oren’s HTTP/2 support in the stdlib, and the concrete regression fixtures that keep it stable across Tier‑1 targets.

Tier‑1 targets (current policy):

- `arm64-macos` (local)
- `arm64-linux` (persistent docker container)
- `x64-linux` (remote WSL2)
- `x64-windows` (remote Win11)

Last verification (fact):

- 2026-01-11: `make verify-native-net-skip-remote` passed (stage1 + stage2), covering:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container `c7e5f7bd9f5c`)
- 2026-01-12: `make verify-native-net` passed on remote x64 hosts (stage1 + stage2), covering:
  - `x64-windows` (remote Win11)
  - `x64-linux` (remote WSL2)

Notes (rolling):

- When the remote Win11/WSL2 host is reachable, use `make verify-native-net` (or `--skip-remote` when unavailable).

Additional verification (fact):

- 2026-01-11: `make verify-x64-linux-qemu-tls` passed (stage1 + stage2 under QEMU in container `c7e5f7bd9f5c`), including:
  - TLS loopback
  - HTTPS loopback
  - WSS loopback
  - HTTP/2 preface loopback
  - HPACK smoke
  - HTTP/2 headers loopback

## Modules

Oren splits HTTP/2 into small layers:

- `std:net/http2` (`lib/std/net/http2.oren`)
  - Framing primitives (client preface bytes, frame header encode/decode).
  - Small payload codecs (currently: SETTINGS payload codec).
  - This module is intentionally “dumb framing”; it is not a full HTTP/2 stack.
- `std:net/hpack` (`lib/std/net/hpack.oren`)
  - HPACK encode/decode v0: static+dynamic tables, Huffman encode/decode, header block encode/decode.
- `std:net/http2_client` (`lib/std/net/http2_client.oren`)
  - Minimal client facade built on top of `std:net/tls` + `std:net/http2` + `std:net/hpack`.
  - Purpose: let Tier‑1 loopback fixtures exercise *stdlib behavior* (not copy/pasted framing logic in tests).

## What Works Today (Evidence-Backed)

### HTTP/2 framing smoke (SETTINGS/ACK + PING/ACK)

- Fixture: `tests/native/test_http2_preface_loopback.oren`
- Coverage:
  - Client preface
  - SETTINGS / SETTINGS+ACK
  - PING / PING+ACK
- Gate: `scripts/verify_native_net_matrix.sh` (stage1 + stage2; all Tier‑1)

### HPACK smoke + encoder regression

- Smokes:
  - `tests/native/test_hpack_smoke.oren` (RFC 7541 Appendix C.2 + C.4.1 decode path)
  - `tests/native/test_hpack_encode_rfc_c41.oren` (RFC 7541 Appendix C.4.1 exact bytes)
- Gate: `make test` includes a fast native integration, but for full NET coverage use `scripts/verify_native_net_matrix.sh`.

### HTTP/2 request/response loopback (single stream, over TLS)

- Fixture: `tests/native/test_http2_headers_loopback.oren`
- Architecture:
  - The **server** side uses `std:net/http2` primitives and verifies the decoded request headers.
  - The **client** side uses `std:net/http2_client` (handshake + request).
- Coverage:
  - TLS ALPN `h2` (best-effort assert on macOS; strict on Linux/Windows where providers expose ALPN)
  - SETTINGS payload decode (expects `ENABLE_PUSH=0`)
  - SETTINGS/ACK handshake
  - HEADERS + CONTINUATION reassembly (forced via deliberate splitting)
  - DATA + END_STREAM response body (`"ok"`)
- Gate: `scripts/verify_native_net_matrix.sh` (stage1 + stage2; all Tier‑1)

## API Notes (Rolling)

### `std:net/http2_client`

Current surface (v0):

- `http2_client.new(conn, timeout_ms, opts)`
  - Writes client preface + client SETTINGS.
  - Expects server SETTINGS + server ACK, then sends ACK for server settings.
  - Returns `{"ok":1,"c":client}` on success.
- `http2_client.request(c, headers, body_bytes, opts)`
  - Sends one request on the next odd stream id:
    - HEADERS (+ optional CONTINUATION)
    - optional DATA (END_STREAM)
  - Reads one response:
    - HEADERS (+ CONTINUATION) then DATA until END_STREAM
  - Returns `{"ok":1,"status":<int>,"headers":<list>,"body":<u8_buf>}` on success.

Options (v0):

- `opts["settings"]`: list of `[id, value]` pairs for the initial SETTINGS frame.
- `opts["split_headers_at"]`: split HEADERS payload at this byte count to force a CONTINUATION frame (fixture coverage).

Non-goals (v0):

- Multiplexing multiple streams
- Full RFC stream state machine
- Flow control / WINDOW_UPDATE
- Server push

## Native Backend Semantics Note (Rolling)

Oren’s language semantics require **type-strict equality** (`nil` distinct from `false`, `int` distinct from `nil`, etc).

Current rolling status (2026-01-10):

- Native mode uses **runtime singleton values** for `nil`, `false`, and `true` (they are distinct non-zero values stored in runtime globals).
  - This ensures `0` (int zero) stays distinct from `nil`/`false` in the common case, which matters for protocols where `0` is meaningful (e.g. SETTINGS values like `ENABLE_PUSH=0`).
- The compiler also includes a correctness guardrail: it rejects `bool/int/float == nil` comparisons when the scalar side is statically known.

Remaining work:

- Full semantic parity still requires the tagged value model described in `docs/BACKENDS.md#native-tagged-value-representation` (notably: robust `int` vs `float` tagging in native mode).

## How To Verify

Fast local checks:

- `make verify-native-quick`
- `./scripts/verify_native_net_matrix.sh --targets local --local-only`

Full Tier‑1 NET matrix:

- `./scripts/verify_native_net_matrix.sh --targets arm64-linux,x64-win,x64-wsl`

Notes:

- The NET matrix script has a rolling hang guard: `OREN_NATIVE_BUILD_TIMEOUT_SECS` (default `10`) per `oren build ...` step.
- Avoid adding fixtures that generate huge logs; prefer concise loopbacks with deterministic asserts.

## WebSocket (stdlib, native backend) — v0

This doc tracks the current “v0” WebSocket support in Oren’s stdlib, implemented on top of the syscall‑first `NET` substrate.

## Status

- **Implementation:** `lib/std/net/ws.oren`
- **Evidence / regression gate:** `tests/native/test_ws_echo_loopback.oren`, executed by `scripts/verify_native_net_matrix.sh` across Tier‑1:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container)
  - `x64-windows` (remote Win11)
  - `x64-linux` (remote WSL2)

Last verification (fact):

- 2026-01-10: `make verify-native-net-skip-remote` passed on:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container `c7e5f7bd9f5c`)
- 2026-01-10: `make verify-x64-linux-qemu-tls` passed on:
  - `x64-linux` under QEMU in docker container `c7e5f7bd9f5c` (stage1 + stage2; includes WSS loopback)
- `x64-linux` / `x64-windows` runs require the remote Win11 (WSL2 optional) host; see `docs/PLATFORMS.md` if the proxy/hostname is unavailable.

## API (v0)

All functions are timeout‑bounded to avoid hangs.

- `ws.connect(url, timeout_ms)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver(url, timeout_ms, resolver)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver_opts(url, timeout_ms, resolver, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - `opts["tls"]` is passed to `tls.wrap_client` for `wss://` URLs (see `docs/NETWORKING_IO.md`).
  - `resolver` is a config map returned by `std:net/dns.resolver(server_ip, server_port, timeout_ms)`
  - Use this to keep hostname behavior deterministic in tests (loopback DNS server), or to avoid relying on `/etc/resolv.conf`.
- `ws.accept(listen_fd, timeout_ms)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.accept_tls_pkcs12(listen_fd, timeout_ms, pkcs12_bytes, passphrase, tls_opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Rolling helper for loopback fixtures and basic WSS servers; wraps `tcp.accept` + `tls.wrap_server_pkcs12` + the WS handshake.
- `ws.close(conn)` → `0` (closes underlying TCP/TLS connection)
- `ws.send_text_client(conn, text, timeout_ms)` → `0` on success, or `-errno`
  - Client frames are **masked** (required by RFC6455).
- `ws.send_text_server(conn, text, timeout_ms)` → `0` on success, or `-errno`
  - Server frames are **unmasked**.
- `ws.send_ping_client(conn, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.send_ping_server(conn, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.recv_text(conn, timeout_ms)` → `{"ok":1,"v":string}` or `{"ok":0,"err":string}`
  - v0.1 behavior: internally handles **ping/pong/close** frames (auto-pong + ignore pongs).

## Scope / limitations (v0)

This is intentionally minimal so we can gate correctness across Tier‑1 first.

- URL: `ws://<host>[:port][/path]`
  - IPv4 literal hosts work without DNS
  - hostname hosts resolve via DNS A:
    - pass an explicit resolver config (`ws.connect_resolver`)
    - or rely on `dns.default_resolver` (env `OREN_DNS_SERVER`, else system DNS on Windows, else `/etc/resolv.conf` on POSIX)
- URL: `wss://<host>[:port][/path]`
  - TLS provider availability is OS-dependent; see `docs/NETWORKING_IO.md`
  - loopback fixtures rely on `opts["tls"]["insecure_skip_verify"]=1` + `opts["tls"]["pin_cert_sha256_hex"]="..."` for deterministic offline behavior (pin enforced by `std:net/tls`)
- Frames:
  - **text frames only** (opcode=1)
  - no fragmentation support
  - payload size is capped (currently 1 MiB) as a rolling safety bound
- Handshake:
  - `Sec-WebSocket-Accept` computed via `SHA1(key + GUID)` then base64
  - client key + masking use OS entropy via `std:crypto/rand` (`oren_getentropy`), not time-seeded toy RNG

## Native runtime caveat: string tracking vs `+`

In the native runtime, string `+` concatenation is **kind‑gated** (implemented by `oren_add`).

- If either operand is not tracked as kind=STRING, `+` behaves like integer add.
- For protocol code, this is dangerous: accidental pointer arithmetic can produce invalid pointers and crash on the next byte load.

Practical rule:

- If you create a string from raw bytes/pointers in stdlib (e.g. header slices), allocate it as a tracked STRING (`malloc_k(..., kind=1)`) or intern it (`oren_intern_cstr(...)`) before using `+`.

## Testing & stress knobs

The Tier‑1 loopback regression is designed to stay bounded and avoid huge logs, while still being able to reproduce intermittent issues.

- `OREN_WS_ECHO_N=<n>`: run the handshake + one text echo **n** times in a single process run of `tests/native/test_ws_echo_loopback.oren` (default: `1`).
  - This is useful for reproducing rare flakes (e.g. WinSock readiness edge cases) without adding verbose tracing.
  - `scripts/verify_native_net_matrix.sh` propagates this env var to the docker container + remote Win11/WSL2 runs when set in the caller environment.

Win11 note:

- WinSock `select()` can occasionally report a timeout even when data becomes readable/writable shortly after (observed during Tier‑1 bring-up).
- The native NET runtime now treats readiness waits as advisory: it tries `recv`/`send` first and, on a reported timeout, retries until the caller deadline is actually exhausted.
- Fixed (2026-01-08): sporadic WS `ETIMEDOUT` flakes under `spawn` were also caused by **TIME scratch buffer races**:
  - `oren_time_unix_ns()` and `oren_time_mono_raw()` used shared global scratch buffers without synchronization.
  - Under concurrent use, that could corrupt timeout math (e.g. compute `rem_ms=0` spuriously), making frame reads “timeout” even when the peer had sent data.
  - The native runtime now keeps TIME scratch buffers **per-thread** (stored in the thread node), with a locked global fallback for early/unknown-thread paths.

### Regression sensitivity (x64-windows)

Even small “semantics‑no‑op” changes can re-surface latent x64‑windows backend/runtime issues and show up first as WebSocket timeouts (while TCP/UDP/HTTP still pass). One concrete root cause was the TIME scratch buffer race fixed on 2026-01-08 (see note above), but WS remains a high-signal end-to-end fixture.

Practical guidance:

- Treat `./scripts/verify_native_net_matrix.sh --targets x64-win` as a **hard gate** for any runtime/backend work, even if the change “shouldn’t affect NET”.
- If you suspect a rare flake, reproduce it **without huge logs** by running:
  - `OREN_WS_ECHO_N=50 ./scripts/verify_native_net_matrix.sh --targets x64-win` (or run `tests/native/test_ws_echo_loopback.oren` directly on Win11/WSL2).
