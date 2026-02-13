# Windows IOCP Netpoller (Native Runtime) — Design Notes (Rolling)

**Last updated:** 2026-01-17  
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

## Current repo status (fact)

- 2026-01-17: runtime recognizes `OREN_NETPOLL_WIN_IOCP=1` and now has an **IOCP poll core + wake** substrate:
  - Init: `native_netpoll_init_once` creates an IOCP via `CreateIoCompletionPort(INVALID_HANDLE_VALUE, ...)`
  - Poll: `native_netpoll_poll_many_scratch` calls `GetQueuedCompletionStatusEx` (allocation-free scratch)
  - Wake: `native_netpoll_wake()` uses `PostQueuedCompletionStatus` (no loopback dependency)
  - Token selection (rolling): IOCP poll now returns the **OVERLAPPED pointer** when present (`ov!=0`),
    falling back to the completion key only when `ov==0`. Wake packets use `key==0, ov==0` and are ignored.
  - Implementation: `lib/runtime_native/246_netpoll.oren`
  - Rolling limitation: IOCP readiness watches are **not implemented yet** (`native_netpoll_arm_fd` returns `-ENOSYS` in IOCP mode),
    so Windows still defaults to select-v0 for NET readiness parity.
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
  - Smoke: IOCP poll returns the OVERLAPPED pointer token when `PostQueuedCompletionStatus` sets `ov!=0`.
  - add a Windows-only fixture analogous to `test_gc_stw_wakes_netpoll_blocked_threads`
- Prove timeouts do not leak:
  - bounded IO operation with timeout that cancels successfully and does not leave “stuck overlapped” state
- Keep `make test` bounded (no 1s sleeps in hot path on real Windows host)

Tracker link:

- `docs/TODOS.md` item “Native scheduler + netpoller”
