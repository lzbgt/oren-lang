# Oren Concurrency & IPC Model (Rolling)

This doc describes:

- what exists today (facts, grounded in code), and
- what the intended direction is (design, tracked in `docs/TODOS.md`).

Oren is rolling; compatibility is not the priority. Accuracy is.

**Last updated:** 2026-01-02

## 1) Core primitives (current reality)

### 1. `spawn` + `join` (today: platform-specific substrate)

`spawn` exists in the language surface today, but it is **not yet** a unified “lightweight task” abstraction.

Current native backend behavior:

- **macOS/Linux (POSIX v0):** `spawn` is implemented as **fork + pipe** (process-based).
  - The child computes the return value, writes 8 bytes to the pipe, and exits.
  - The parent joins by reading those 8 bytes and reaping the child.
  - This is syscall-first and libc-free, but it is **not** threads and there is **no shared memory**.
- **Windows x64 Tier‑1:** `spawn` is implemented as **CreateThread** (OS threads).
  - The join handle wraps a thread HANDLE and a result pointer.

Implications:

- There is no M:N scheduler in native yet.
- A “mutex” cannot coordinate across `spawn` on POSIX v0, because forked processes do not share the address space.

Source of truth:

- POSIX fork+pipe join handle: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`
- Windows CreateThread path: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`

### 2. Channels + `oren_select` (today: data-driven, backend-shared)

Channels exist today, but their implementation is currently a bring-up substrate:

- Native channels are pipe pairs `[rfd, wfd]` (`oren_new_channel()`).
- AVM has proper channels as VM objects.
- `oren_select_recv` / `oren_select` exist as **functions** (not syntax) and have a shared encoding across AVM and native.

Source of truth:

- Native: `lib/runtime_native/010_channels_globals_consts.oren`, `lib/runtime_native/245_select.oren`
- AVM: `lib/avm/avm_vm.c` opcodes `SELECT_RECV` / `SELECT`
- Docs: `docs/ASYNC_IO_AND_SELECT.md`

### 3. Atomics (native)

Atomics exist as native intrinsics and are the right “foundation layer” for future shared-memory concurrency:

- `atomic_add`
- `atomic_cas`

These are necessary (but not sufficient) for:

- a real native thread scheduler
- mutex/condvar/channel implementations that do not require host libc

## 2) Synchronization primitives (what is *not* true yet)

The following are *design goals* but are not implemented today as stable primitives:

- “green threads” / coroutines
- a portable, shared-memory `mutex`/`lock` that works across macOS/Linux/Windows without libc
- structured concurrency (`task_group`, cancellation propagation)
- pub/sub or multicast channels
- data-parallel iterators (`par_map`, `par_reduce`)

## 3) Roadmap (high-level)

Implementation plan is tracked in `docs/TODOS.md` and the deeper design docs:

- `docs/NATIVE_GMP_SCHEDULER.md`
- `docs/ASYNC_IO_AND_SELECT.md`
- `docs/AVM_CONCURRENCY.md`

## 4) AVM notes

For AVM execution (interpreter-only environments), concurrency primitives must:

- support cancellation/timeouts (to stop work when a better plan exists)
- be compatible with snapshot/restore (pause and resume tasks)
- be compatible with capability gating (NET/PROC may be disabled)

See:

- `docs/AVM_SPEC_V1.md`
- `docs/AGENTIC_REQUIREMENTS.md`
