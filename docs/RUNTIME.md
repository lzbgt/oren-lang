# Runtime + Stdlib + Networking

**Last updated:** 2026-02-19

This file merges stdlib/runtime design with networking/IO architecture. Use it as the
canonical reference for runtime layers, module resolution, collections, scheduler, and the
network stack (TLS/HTTP/WS/netpoll).

---

# Stdlib and Runtime Libraries (Rolling)

This document consolidates stdlib layering, module distribution, runtime scheduler design, collections, and GUI direction.

## Oren Stdlib Layers (Builtin vs Shipped)

**Status:** Rolling (macOS-first, avoid blocking Linux)  
**Goal:** keep Oren syscall-first and libc-independent while still enabling a modern, batteries-included ecosystem.

This document defines the separation of concerns between:

1) **Compiler/runtime intrinsics** (compiler-known primitives)
2) **Builtin syslib** (shipped with the toolchain, minimal + stable)
3) **Shipped stdlib** (source modules, optional compiled artifacts)
4) **Third-party libraries** (user code)

The key constraint is that Oren is designed to:

- remain **independent of libc shims** for the native backend runtime
- support **AVM multiverse determinism** (replay, snapshot, governance)
- evolve in **rolling ABI** mode until a stabilized v1

## 1) Layer 0 — Intrinsics (compiler-known)

**Definition:** operations that the compiler and/or runtime implement directly and that are not “just a library function”.

Examples (current / expected direction):

- `oren_string_len`, `oren_string_slice`, `oren_string_char_at`
- `oren_list_len`, `oren_list_push`
- core allocation hooks used by the native backend runtime
- AVM bytecode ops (TIME/RNG/task/etc in `.obc`)

**Rules:**

- Intrinsics are small and carefully governed; they are the “machine model”.
- Intrinsics must have stable, deterministic semantics once v1 stabilizes.
- For AVM: intrinsic-effect domains (FS/NET/PROC/ENV/TIME) must be explicit and capability-governed.

## 2) Layer 1 — Builtin Syslib (shipped with toolchain)

**Definition:** a small set of `.oren` modules shipped with the compiler/AVM that:

- are required by the toolchain itself, and/or
- are required to bootstrap higher-level libs,
- and are kept intentionally minimal to avoid “everything becomes builtin”.

**Examples (intended):**

- `std/strings` (basic string helpers)
- `std/bytes` (byte helpers, endian reads/writes; used by packet parsing)
- `std/result` (small error/value helpers used across stdlib)
- `std/argparse` (used by `./oren` and `./avm` CLIs)
- `std/casts` (canonical explicit casts matching annotation lowering; clarity layer)
- `std/math` (portable helpers: abs/min/max/clamp + `is_nan`)
- `std/linalg` (scalar-first dot/axpy/matmul; SIMD-ready hooks later)
- `std/regex` (deterministic Thompson NFA; no catastrophic backtracking)
- `std/json` (portable explicit `JsonValue`; tolerant decode for config text)
- `std/yaml` (deterministic subset; tolerant decode for common config text)
- `std/cbor` (deterministic subset + CBOR Sequences streaming helpers)
- `std/ffi/*` (OS/library boundary wrappers for native providers)
  - Purpose: centralize `@cfg` + `@ffi.link`/`@ffi.dll` + ABI return-kind details in one place.
  - Used by: OS-specific provider implementations (TLS, DNS, etc).
  - Not intended for general application logic; prefer higher-level stdlib APIs (`std:net/*`, `std:crypto/*`).

**Rules:**

- Syslib should not silently take host effects.
- Syslib should accept explicit capability objects for host effects (or remain pure).
- Syslib must remain usable by both:
  - native backend (syscall-first substrate)
  - AVM backend (virtualized domains)

### `std:ffi/*` boundary modules (rolling)

Oren’s stdlib includes a small set of `std:ffi/*` wrapper modules that exist specifically to:

- keep platform-specific library names and ABI quirks out of higher-level code,
- avoid scattering raw `ffi` declarations across many files,
- make Tier‑1 portability gates higher-signal (a wrapper module becomes the single place to fix).

Examples in-tree (non-exhaustive):

- Windows:
  - `std:ffi/kernel32` (basic Win32 calls)
  - `std:ffi/secur32` + `std:ffi/crypt32` (Schannel/SSPI + cert store; used by `std:net/tls_windows_schannel`)
  - `std:ffi/iphlpapi` (network config; used by `std:net/dns` default resolver selection)
- Linux:
  - `std:ffi/libdl` (dynamic loader; used by `std:net/tls_linux_openssl`)
- macOS:
  - `std:ffi/macos_security` + `std:ffi/macos_corefoundation` (framework wrappers; used by `std:net/tls_macos_securetransport`)
  - `std:ffi/macos_dlfcn` (dlsym; used by `std:net/tls_macos_securetransport` exported callback resolver)

Policy (rolling):

- `std:ffi/*` modules may use `@cfg`, `@ffi.link`, `@ffi.dll`, and `@ffi.ret(...)`.
- Higher-level modules should import the wrapper instead of repeating FFI declarations.

## 3) Layer 2 — Shipped Stdlib (source modules)

**Definition:** “batteries included” libraries that are shipped as source and imported normally, but are not required for bootstrapping the compiler.

Examples:

- HTTP/WebSocket libraries on top of `NET`
- higher-level filesystem path libraries on top of `FS`
- JSON schema tooling (if not required by the compiler itself)
- TLS/HTTPS/WSS transport wrappers on top of `NET` + `CRYPTO` providers
  - Current reality (rolling): the implementation is in `std:net/tls` (socket-oriented).
  - Convenience facade: `std:crypto/tls` exists as an alias-layer over `std:net/tls` so call sites that
    conceptually want “TLS is crypto” have a stable import path while the deeper split is implemented.

**Rules:**

- Can evolve faster than syslib.
- Should be kept modular (SOLID): avoid monolith “mega stdlib”.
- Still must respect capability-driven IO for governance and nested universes.

## 4) Layer 3 — Third-party libraries

**Definition:** user modules (source or compiled) distributed outside the repo.

Design goal:

- unknown attributes in user code must remain inert by default (determinism),
  but preserved for tooling/policy scan and future governance rules.

## 5) Attributes & Stdlib (why attributes are “syslib-adjacent”)

Attributes are compile-time metadata (not runtime decorators). They matter for stdlib because:

- JSON serde wants field-level rename/skip/default
- networking wants packed struct “views” over bytes
- governance wants capability declarations and policy scanning

### Determinism + “config ergonomics”

Oren accepts some common config conveniences while keeping output canonical and deterministic:

- `std/json.decode(...)` tolerates C-style comments (`// ...` and `/* ... */`) for config compatibility.
- `std/yaml.decode(...)` tolerates:
  - YAML `# ...` comments, and
  - C/JSON `// ...` and `/* ... */` comments,
  using a whitespace/start rule to avoid breaking values like `http://example.com`.

Encoders remain canonical and deterministic (they do not emit comments).

### Determinism rules (v0, current implementation)

- Attribute arguments are restricted to literals: `int`, `float`, `bool`, `string`, `nil`.
- Unknown attributes are allowed and inert in rolling mode.
- A strict mode exists for enforcing allowlists (for governance and controlled builds).

Current implementation locations:

- parser parses `@attr(...)` into `Attr` nodes with literal args (`lib/compiler/parser_core.oren` + `lib/compiler/parser_parse.oren`).
  - Rolling note: large compiler sources may be split into smaller files and composed via `// @include "..."`; the top-level `.oren` file remains the stable entrypoint for tooling/docs.
- native backend supports `--metadata` output (`<out>.meta.json`) for tooling
- strict attribute mode is implemented and enforced at parse-time (`--strict-attrs` + `--attr-allow-prefixes`, see `./oren build --help`)

Ergonomics (rolling):

- reserved compiler directives:
  - `@pack` (canonical in metadata: `oren.packed`)
  - `@abi` (canonical in metadata: `oren.abi`)
- serde namespace (canonical for tooling/codegen):
  - accept `@json.*` as a frontend alias, canonicalize to `@serde.*`

## 6) Recommended placement guide (quick reference)

Put it in:

- **Intrinsic**: if the compiler must understand it to compile programs at all.
- **Syslib**: if it’s required by the compiler/AVM tooling, or required for bootstrapping core libs.
- **Stdlib**: if it’s useful for apps but not required for toolchain correctness.
- **Third-party**: if it’s domain-specific or rapidly evolving.

Example calls:

- `print`: syslib (tooling depends on it)
- JSON: syslib or stdlib (depends on whether the compiler/AVM need it)
- HTTP/WebSocket: stdlib (built atop NET)
- SHA-256 / RNG primitives: syslib (used by NET + AVM determinism)
- PEM/X.509 helpers: syslib-adjacent (used by TLS, signing fixtures, and tooling)

## Stdlib Resolution & Distribution (Compiler + AVM)

This document proposes a **user-friendly stdlib import model** (no `../../lib/std/...` prefixes)
and a distribution story that works for:

- native and C backends (`oren build ...`)
- bytecode backend (`.obc`)
- AVM execution (running `.obc`)
- future “compiler inside AVM” (compile source to `.obc` inside a sandboxed universe)

It is written against the **current** compiler behavior in this repo:

- `import name "path"` stores a string path (parser: `lib/compiler/parser_parse/030_tail.oren`).
- module loading currently resolves paths relative to importing file (linker: `lib/compiler/compiler/020_modules_linking.oren`).

---

## 1) Problem statement

Today, end-user code typically imports stdlib like:

```oren
import math "../../lib/std/math.oren"
```

This is:

- not user-friendly,
- not stable under project layout changes,
- hard to distribute (the path assumes the repo layout),
- awkward for AVM/capsule environments where host paths should be irrelevant.

We want:

- stable logical imports: `import math "std:math"` or `import json "std/json"`,
- predictable deterministic resolution,
- a packaging story for shipping the stdlib to end users.

---

## 2) Design goals

1) **Ergonomics**
   - Users should never need `../../...` to import the stdlib.

2) **Deterministic builds**
   - Given a source tree + stdlib content, import resolution should be stable.

3) **No silent name collisions**
   - Local modules should not accidentally shadow stdlib modules without an explicit choice.

4) **AVM compatibility**
   - The same source should compile outside AVM and inside AVM if the stdlib is present in the universe.

5) **Rolling evolution**
   - This repo is rolling; we can change the import resolver and docs without preserving old behavior forever.

---

## 3) Proposed import specifiers

Oren keeps the existing grammar:

```
import_stmt = "import" ident string_lit [ ";" ] ;
```

We interpret the string literal as a **module specifier** (not necessarily a filesystem path).

### 3.1 Stdlib specifiers (recommended)

Two equivalent forms:

- `std:` scheme form:
  - `import math "std:math"`
  - `import common "std:linalg/common"`
- `std/` path form:
  - `import math "std/math"`
  - `import common "std/linalg/common"`

Rules:
- `.oren` extension is optional: `"std/json"` resolves to `std/json.oren`.
- Nested modules map to subdirectories: `"std/linalg/common"` resolves to `lib/std/linalg/common.oren` in the repo layout.

### 3.2 Filesystem specifiers (existing behavior)

- Relative paths: resolved relative to the importing file directory.
- Absolute paths: allowed.

We also support extensionless filesystem imports for convenience:
- `"foo/bar"` resolves to `"foo/bar.oren"` if the last segment has no `.`.

---

## 4) Resolution algorithm (compiler)

### 4.1 Stdlib root discovery

The compiler needs a stable way to find the stdlib source root (`STDLIB_ROOT`).

Current implementation (rolling, pragmatic):

Priority order:

1) `OREN_STDLIB_ROOT` environment variable
   - If it points directly at the stdlib directory, use it.
   - If it points at an install/repo root, accept `<root>/lib/std`.

2) Walk up from the importing file directory looking for `lib/std/argparse.oren`
   - Works for repo development and for projects vendoring the compiler tree.

3) Fallback: `lib/std` relative to the current working directory

This makes development “just work”, and gives packagers a single knob (`OREN_STDLIB_ROOT`)
for installed distributions.

### 4.2 Import resolution

Given `(base_dir, specifier)`:

- If `specifier` starts with `std:` or `std/`:
  - resolve to `STDLIB_ROOT/<specifier_rest>`
  - append `.oren` if needed
- Else:
  - resolve to `<base_dir>/<specifier>`
  - append `.oren` if needed

---

## 5) Distribution models (end users)

There are two realistic distribution strategies. Both can coexist.

### Model A: Ship stdlib sources alongside the compiler (recommended now)

Installer layout (example):

```
<install_root>/
  bin/oren
  lib/std/...
```

Then:
- set `OREN_STDLIB_ROOT=<install_root>/lib/std` in the wrapper script / environment.

Pros:
- simple,
- transparent (users can inspect stdlib),
- easy to patch/override for rolling development.

Cons:
- requires a multi-file install.

### Model B: Embed stdlib sources into the compiler (future)

The compiler binary (native or `.obc`) contains a “stdlib pack” (e.g. a compressed blob).
At compile time it can:

- mount the pack as a virtual filesystem, or
- unpack it into a temporary directory, or
- serve sources from memory to the parser.

Pros:
- single-file distribution,
- perfect for “compiler inside AVM” (no host FS dependency).

Cons:
- more engineering: packaging, compression, versioning, potential size concerns.

### Model C: Precompile stdlib to `.obc` (bytecode stdlib)

This model targets the **AVM + bytecode** ecosystem track.

Instead of distributing stdlib as `.oren` sources, distribute it as a set of precompiled
bytecode modules (or a single bundled module graph), for example:

- `std/strings.obc`, `std/json.obc`, ...
- or one pack: `stdlib.obc` (containing multiple modules, see notes below)

Key observation:

- The AVM can execute `.obc` directly.
- So the stdlib can be shipped as bytecode and used without shipping sources.

Rolling implementation note (current repo):

- This repo implements compile-time linking via an “OBX” metadata payload embedded as an
  unused `BYTES` constant in `.obc` (exports + relocations), then concatenates/patches
  bytecode to produce a single self-contained program.
- See `docs/AVM.md`.

However, this requires a concrete “linking/loading” story:

1) **Compile-time linking (simpler, recommended first)**
   - The compiler (outside or inside AVM) resolves `std:` imports to stdlib sources or to
     “precompiled module artifacts” and produces a single output program.
   - Result: the final `.obc` is self-contained (no runtime module loading needed).

2) **Runtime module loading (more powerful, future)**
   - The AVM supports importing/loading `.obc` modules at runtime.
   - This enables smaller user artifacts, shared caches, and dynamic plugin loading.
   - But it requires:
     - a stable module identity scheme,
     - a bytecode linking ABI (symbol export/import),
     - capability policy decisions (what modules are allowed).

For rolling mode, start with (1) and evolve toward (2) only when the module ABI is stable.

### Model D: Native stdlib as a shared library (`.so`/`.dylib`)

This model is relevant for **native backend builds**, where performance and binary size
often motivate linking against shared libraries.

- The stdlib (or parts of it) can be compiled to a shared library.
- User programs link against it.

Important constraints:

- This does **not** automatically help AVM: the AVM executes bytecode and does not
  load native `.so`/`.dylib` unless the AVM host explicitly implements a native extension
  mechanism (which is a security/capability design problem).

So: native shared-libraries are a valid distribution story for native builds, but are not the
same thing as “stdlib usable by AVM”.

---

## 6) AVM interaction (important clarification)

### Running `.obc` programs in AVM

If a user program is already compiled to `.obc`, the AVM does **not** need the stdlib sources.
All imports are resolved at compile time and linked into the output program/module graph.

### Compiling inside AVM (future “inception” track)

If we want “source → `.obc` inside AVM”, the compiler running in AVM needs access to stdlib sources.
That can be provided by:

- mounting the stdlib tree into the AVM VirtualFS at a known location,
- setting `OREN_STDLIB_ROOT` inside the universe environment,
- or using Model B (embedded stdlib pack).

This integrates cleanly with capability-based constraints:
- stdlib reads come from VirtualFS (not host FS),
- deterministic snapshots can hash the stdlib pack + user source.

### FFI and AVM: what is and is not possible

Oren has `ffi`, but the key question is **where the code runs**:

- **Native backend**: `ffi` can map to C/OS symbols as part of native linking.
- **Bytecode/AVM**: there is no implicit access to host symbols.

So for AVM:

- A “native stdlib library” (`.dylib`/`.so`) cannot be used directly by pure AVM bytecode.
- The only safe way for AVM bytecode to interact with the outside world is via
  explicit **host-provided domains** (VirtualFS/VirtualNET/VirtualPROC/…).

If the AVM host later exposes an extension mechanism (a controlled “FFI bridge”), it must:

- be capability-scoped (opt-in per domain),
- be deterministic or explicitly marked non-deterministic,
- be auditable (hashes/signatures),
- preserve the security model (no ambient authority).

Given Oren’s “agent-safe VM” goals, treat this as an advanced feature, not the baseline.

---

## 7) Open questions / next steps

1) Add a formal “module search path” list (like `OREN_PATH`) for non-stdlib packages.
2) Add a standard “vendor” directory layout (`vendor/<pkg>/...`) for reproducible builds.
3) Decide whether stdlib is versioned with the compiler or independently.
4) Add repo audits ensuring docs/examples do not regress to `../../lib/std/...`.
5) Decide stdlib artifact format(s):
   - source tree (`.oren`) for transparency + patchability
   - precompiled `.obc` for AVM distribution
   - optional native `.so`/`.dylib` for native backend deployments

## Native Backend: G-M-P (Greenlet) Scheduler Design (Syscall-First, No libc/pthreads)

**Status:** Draft (design + staged plan)  
**Scope:** native backend runtime (AArch64), not AVM bytecode scheduling  
**Non-goals (for now):** JIT, cross-language ABI stability, “perfect” determinism under OS threads

This document defines how Oren’s **native backend** evolves from the early bootstrap `spawn`
(historically macOS/Linux: `fork + pipe`) into a production-grade **N:M** (a.k.a. **G-M-P**) greenlet
runtime **without relying on libc/pthreads shims**.

Related:

- `docs/STATUS_AND_ROADMAP.md` (syscall-first runtime boundary)
- `docs/LANGUAGE.md` (language-level concurrency surface)
- `docs/AVM.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly` (deterministic concurrency inside AVM; different goal)

## 0) Terminology

We use the Go-style naming because it maps cleanly to the target architecture:

- **G** (“greenlet” / “goroutine”): a lightweight task that runs Oren code.
- **M** (“machine”): an OS thread that executes code on a CPU core.
- **P** (“processor”): a scheduler context holding run queues, timers, and local caches. At any instant, an `M` runs code *only while holding a `P`*.

Target end state:

- Many `G` run on fewer `M` (N:M).
- `P` count (often) equals the number of OS threads allowed to run Oren code concurrently (similar to `GOMAXPROCS`).

## 1) Non-negotiables (syscall-first and “no shims”)

1) **No libc / no libpthread dependency in the core runtime**
   - The runtime may call kernel syscalls directly.
   - The runtime must not link against libc/pthreads to “get threads”.

2) **Blocking must not block the entire runtime**
   - A single blocked operation (NET/PROC/FS) must not stall all runnable `G`.
   - For the N:1 phase, this implies “event-loop style” non-blocking syscalls.
   - For N:M, it implies “park the `G`” and let the `M` run other work.

3) **Rolling ABI friendly**
   - Data structures and calling conventions can evolve (repo is rolling ABI).
   - But we must avoid a “do shims now, rewrite later” trap: build the correct syscall-first shape early.

## 2) Why AVM and native concurrency are different problems

AVM concurrency (`docs/AVM.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`) is about:

- determinism (consensus/replay)
- snapshot/restore of scheduler state as data
- capability-governed effects (VirtualFS/VirtualNET/VirtualPROC)

Native backend concurrency is about:

- production throughput and real OS integration (real sockets, real processes)
- efficient multiplexing (kevent/kqueue on macOS; epoll on Linux)
- low overhead tasks (millions of `G`), with OS threads used as an execution resource

So:

- **AVM:** single-thread semantics first, deterministic scheduler.
- **Native:** N:1 greenlets first (event loop), then N:M once syscall-first threads are in place.

## 3) Staged plan (no huge rewrite)

### Stage N0 (historical baseline): process-based `spawn` (fork+pipe) on POSIX

Historical bootstrap behavior (macOS/Linux native):

- `spawn` implemented as `fork + pipe` (process-based) to avoid relying on libpthread’s `bsdthread_*` APIs.

Current (rolling) behavior:

- `spawn` on macOS/Linux now **prefers in-process green tasks** (Stage N1) and falls back to fork+pipe
  when green tasks are disabled/unavailable.
  - Escape hatch: `OREN_NO_GREEN=1` forces fork+pipe for bring-up/debugging.

Pros:

- correct, syscall-first, debuggable
- avoids “thread init” complexity early

Cons:

- heavy (process cost)
- not a greenlet model
- not suitable for large-scale concurrency

### Stage N1: N:1 cooperative greenlets (single OS thread)

Goal:

- Introduce **real lightweight concurrency** without needing OS thread creation yet.

Core idea:

- One OS thread runs an event loop and a cooperative scheduler.
- Each `G` yields explicitly at safe points.

Requirements:

1) **A context switch primitive**
   - Implemented as **native backend intrinsics** (inlined at call sites; no external asm objects or libc):
     - `oren_ctx_init(ctx_ptr, sp, pc)` initializes a context blob for first entry
     - `oren_ctx_switch(old_ctx, new_ctx)` saves CPU state into `old_ctx` and resumes `new_ctx`
   - Preservation contract (rolling, required for green scheduling correctness):
     - Save/restore all non-reserved GPRs + `SP` + resume `PC`.
     - Save/restore SIMD regs too (arm64: `Q0..Q31`, x64: `XMM0..XMM15`).
     - Do **not** save/restore the native bump allocator registers (arm64: `X27/X28`, x64: `R14/R15`), because allocator state must be shared per OS thread.

2) **Per-greenlet stack**
   - Allocate stacks from the runtime allocator (eventually with guard pages).
   - Store stack pointer + entry function pointer in `G`.

3) **Yield points**
   - Minimal: `yield()` builtin (or `oren_yield()` runtime call) that enqueues current `G` and switches to scheduler.
   - Also: `sleep_ms`, channel ops, and capability-scoped “syscalls” become yield points.
     - Fact (2026-01-17): TIME sleep is green-aware on the native backend: `oren_sleep_ns/ms` route to `oren_green_sleep_ns` when called from inside a green task (so sleep does not block the scheduler OS thread).
     - Fact (2026-01-17): in-green wait-on-address must not deadlock or stall the scheduler OS thread:
       - `oren_wait_on_addr(..., timeout_us=0)` parks the `G` on a scheduler-owned “word wait” list and is woken via `oren_wake_all_addr(addr)` (wake-driven; no polling).
       - `oren_wait_on_addr(..., timeout_us>0)` uses the same wait list + scheduler deadlines and returns portable `-60` on timeout.
       - Guards:
         - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_in_green_does_not_block_scheduler`)
         - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_timeout_in_green_does_not_block_scheduler`)

4) **Non-blocking OS integration**
   - On macOS, `kqueue/kevent` is the syscall-first friendly multiplexer.
   - NET reads/writes use non-blocking sockets + kevent timeouts.
   - PROC waits can use `wait4` with polling/timeouts (or a signal + kevent integration later).

This stage gives:

- a true coroutine runtime
- cancellable/timeout-capable IO (essential for agent systems)
- minimal architectural debt (the `G`/scheduler model remains the same in N:M)

Status (fact, code):

- Green task runtime is implemented in `lib/runtime_native/263_green_tasks.oren`.
- `spawn` prefers green tasks on Tier‑1 (POSIX + Windows) via `oren_green_spawn` (`lib/runtime_native/120_first_class_fn.oren`).
  - Escape hatch: `OREN_NO_GREEN=1` disables green tasks; POSIX falls back to fork+pipe, Windows falls back to a runtime-owned OS thread.
- Context switch intrinsics are defined as native backend intrinsics (`oren_ctx_init`, `oren_ctx_switch` in
  `lib/runtime_native/000_prelude_sys.oren`).
- 2026-01-16: native `oren_select` / `oren_select_recv` are green-aware and do not block the scheduler OS thread:
  - Green path uses the shared scheduler netpoller directly (**netpoll v2**): per-case tokens mark a full ready-set so deterministic cursor selection does not require per-wake probe polling.
  - Runtime: `lib/runtime_native/245_select.oren` (green `oren_select` waits on netpoll v2; non-green still uses a per-call kqueue/epoll wait)
  - Runtime: `lib/runtime_native/246_netpoll.oren`
    - POSIX: kqueue/epoll + wake pipe; allocation-free `native_netpoll_poll_many_scratch`
    - Windows (rolling v0): WinSock `select()` (`FD_SETSIZE=64` per call) with a watch table that can exceed 64 (polled in batches).
      - Wake: best-effort loopback UDP wake socket in non-capsule builds; in capsule builds it is only created if loopback endpoints are explicitly allowed.
      - When the wake socket exists:
        - watch-table updates call `native_netpoll_wake()` to break a blocking select and rebuild the `fd_set` promptly
        - worker-mode idle waits can use longer timeouts (bounded by the scheduler), instead of a fixed 10ms polling clamp
      - When wake is unavailable (capsule policy or failure), select waits remain bounded by short timeouts (polling fallback; correctness-first).
      - IOCP is still the intended long-term implementation (scalability + true wake + future HANDLE story).
      - Rolling IOCP token support: the scheduler recognizes IOCP wait nodes whose `OVERLAPPED*` is returned by the poller (magic after the OVERLAPPED header).
        - 2026-02-13: IOCP wait tokens are handled in both the ready-drain path and the blocking netpoll path (no drop on idle polls).
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (scheduler drains netpoll tokens and marks G/wait nodes ready)
  - Runtime: `lib/runtime_native/240_tcp.oren` (`oren_fd_wait_*` park the G and rely on the scheduler netpoller instead of poll+sleep)
  - Escape hatch (rolling): `OREN_NO_NETPOLL=1` disables netpoll bring-up for debugging (in-green select returns ENOSYS; avoids busy loops).
  - Guards:
    - `tests/native/test_quick_integration_native.oren` (`test_select_in_green_workers`, `test_select_multi_case_in_green_workers`)
    - `tests/native/test_net_suite.oren` (`test_fd_wait_socket_readable_in_green_workers`)

- 2026-01-16: scheduler netpoll waiting is allocation-free in steady-state:
  - the green scheduler uses a per-OS-thread scratch region for `native_netpoll_poll_many_scratch(...)` so worker idle waits do not allocate and do not drop additional ready tokens
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (per-thread scratch in `green_t`)

- 2026-01-17: scheduler-lock reentrancy hazard (fixed):
  - Fact: the native runtime global lock `release_lock()` wakes waiters via `oren_wake_all_addr(lock_ptr)` (runtime: `lib/runtime_native/100_time_gc_alloc.oren`).
  - Fact: `oren_wake_all_addr` also wakes green tasks parked on the scheduler’s word-wait list (runtime: `lib/runtime_native/267_wait_on_addr.oren` → `oren_green_wake_all_addr`).
  - Therefore: green scheduler lock acquire MUST avoid allocating thread-local green state via `oren_register_thread`, otherwise it can recurse:
    `release_lock -> oren_wake_all_addr -> oren_green_wake_all_addr -> _green_lock_acquire -> (register thread) -> release_lock -> ...` (stack overflow).
  - Implementation note: `_green_lock_acquire` uses a no-alloc best-effort “in-green” probe (`_green_in_green_best_effort_noalloc`) that inspects the current stack node flags (source of truth: `lib/runtime_native/100_time_core.oren`).

### Stage N2: N:M GMP (multiple OS threads, multiple Ps)

Goal:

- scale compute across cores while keeping `G` lightweight.

Primary references (verbatim snapshots, for scheduler topology + netpoll design):

- Go runtime scheduler (`proc.go`): `project-doc/web/go.dev/20260117/runtime_proc_go.html`
- Go runtime netpoll (`netpoll.go`): `project-doc/web/go.dev/20260117/runtime_netpoll_go.html`
- Go runtime hacking notes: `project-doc/web/go.dev/20260117/runtime_hack_go.html`

Key additions:

1) **Syscall-first OS thread creation**
   - Implement OS thread creation via kernel interfaces directly (no libpthread).
   - Keep the boundary narrow: a single `sys_thread_create(entry, arg, stack_top, ctid_ptr)` (Linux),
     or `sys_win_createthread(entry, arg)` (Windows), plus minimal TLS/registration.
   - macOS note (rolling): true syscall-first OS-thread creation requires the `bsdthread_*` syscall boundary
     (or another kernel-exposed thread API) and correct thread-local storage + threadstart stub installation.

Status (rolling groundwork):

- **Linux + Windows:** a runtime-owned OS-thread handle exists and is used by tests:
  - Runtime: `lib/runtime_native/269_os_thread_m.oren` (`oren_os_thread_spawn`, `oren_os_thread_join_timeout`, `oren_os_thread_destroy`)
  - Linux thread creation uses the syscall-first clone wrapper: `lib/runtime_native/266_linux_os_threads.oren` (`sys_thread_create`)
  - Parking uses wait-on-address: `lib/runtime_native/267_wait_on_addr.oren` (`oren_wait_on_addr`, `oren_wake_all_addr`)
  - Smokes:
    - `tests/native/test_os_thread_park_unpark_smoke.oren`
    - `tests/native/test_os_thread_spawn_many_smoke.oren`
- **macOS arm64:** syscall-first `bsdthread_register/create/terminate` lowering exists, and the native backend
  attempts to install runtime-owned threadstart stubs at process init (non-dylib builds):
  - Compiler emit + init call: `lib/compiler/arm64_native_program.oren`
  - Threadstart stubs + fallback implementation: `lib/runtime_native/264_darwin_os_threads.oren`
  - Runtime init helper: `lib/runtime_native/020_fork_runtime_init.oren` (`native_runtime_threading_init`)
  - Reality note (rolling): many macOS processes are already registered by dyld/libpthread, so the runtime
    uses a **pthread_create fallback** for `oren_os_thread_spawn` unless our runtime-owned registration succeeds.
    The long-term target remains syscall-first threads (no libpthread dependency).

- **Green-task scheduler worker mode (Stage N2 groundwork):** the Stage N1 green-task runtime now supports:
  - per-OS-thread scheduler state (scheduler context + current-G are no longer globals), including a thread-local **current P** pointer, and
  - optional background scheduler workers (`oren_green_start_workers(n)`) that drain:
    - their bound `P` local runq/sleepq (locality), and
    - a scheduler-level **global run queue** for cross-P injection / fairness (spawns from outside green context).
  - Scheduler topology (rolling; Stage N3 plumbing):
    - `P` count is now a real runtime parameter:
      - `oren_green_set_p_count(n)` grows the number of `P` objects before workers start (no shrink; returns `-1` once workers started).
      - `oren_green_p_count()` reports the current `P` count.
      - `oren_green_bind_p(p_id)` binds the current OS thread to a specific `P` (bring-up/testing; rejected in-green and once workers started).
      - `oren_green_current_p_id()` reports the current OS thread’s bound `P` id.
      - Host-thread ownership helpers (bring-up/testing; rejected in-green and once workers started):
        - `oren_green_acquire_p(p_id)` binds the OS thread to `p_id` and sets `P.owner_tid = sys_gettid()`
        - `oren_green_release_p()` releases the currently bound `P` and clears the thread binding
      - low-level scheduler drive hooks (host-thread only; bring-up/tests):
        - `oren_green_poll_until(deadline_ns)` drives until idle or deadline (monotonic ns).
        - `oren_green_poll_steps(n)` drives at most `n` context switches (used to seed multi-P queues deterministically).
      - Single-thread multi-`P` bring-up regression (no unsafe worker parallelism):
        - `tests/native/test_quick_integration_native.oren` (`test_green_multi_p_single_thread_poll_steal`)
          - binds to `P2`, seeds `P2` local runq from a green task, then rebinds to `P0` and proves the scheduler steals work from `P2`,
            including waking a sleeper parked under `P2` while driving `P0`.
    - The scheduler wakes sleepers **across all Ps**, not just the current thread’s bound `P`.
      - This is future-proofing for `M < P` and for global timeout-driven services (netpoller/timers) without requiring every `P` to be actively driven.
  - Worker sleeping behavior (rolling, but important for responsiveness):
    - when only sleepers exist, the worker parks on the shared park word with a timeout (so new runnable work wakes it immediately)
    - inserting new sleepers wakes workers so the “next wake” deadline is re-evaluated promptly
    - sleeper deadlines use a **monotonic** clock (`oren_time_mono_ns`) so wall-clock jumps do not break wake behavior:
      - Linux: fills `sys_gettimeofday(..., abs_ptr)` via `clock_gettime(CLOCK_MONOTONIC)` in ns
        - x64-linux note (fixed 2026-01-16): ensure the `timespec` scratch used by `clock_gettime` does not overlap the spilled `abs_ptr`
          (otherwise `abs_ptr` can be clobbered with `tv_nsec` and cause deterministic SIGSEGV under qemu and on real hosts).
          - Gate: `make verify-x64-linux-qemu`
      - macOS: converts gettimeofday’s `mach_absolute_time` out-arg using `mach_timebase_info` (num/den)
      - Windows: converts QPC ticks using `QueryPerformanceFrequency`
  - Join behavior: when workers are enabled, `oren_green_join_timeout` waits on the green task's state word via the portable
    wait-on-address primitive (instead of driving the scheduler on the joining thread).
  - P ownership (rolling correctness guard): when workers are enabled, `_green_poll_until` enforces `P.owner_tid == sys_gettid()`.
    Worker bring-up reserves each worker `P` with a negative sentinel during `oren_green_start_workers`, then the worker claims its bound `P`
    to a positive tid before entering the scheduler loop (hard-fails on mismatches).
    - Rolling safety: `oren_green_start_workers` rejects if any `P.owner_tid != 0` on entry (prevents subtle “worker aborts because P was already claimed” failures).
    - Stage N3 evolution: a worker may temporarily set `P.owner_tid = 0` while blocked (park/kevent/epoll), then re-acquire before running Oren code.
    - Stage N3 evolution: `oren_green_start_workers(n)` reserves only the first `n` Ps; extra Ps must remain free (`owner_tid==0`) for future `M < P` operation.
    - Stage N3 evolution: an explicit **idle-P pool** now exists (under the scheduler lock) so “owner_tid==0” Ps can be acquired/released without rescanning the full P list.
      - Test-only host hook: `oren_green_acquire_any_p()` (pre-workers only) for M<P bring-up and fixtures.
      - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_idle_p_pool_acquire_any`)
    - Stage N3 evolution (toward real `M < P`): workers now clear their **thread-local P binding** while parked/blocked, and on wake attempt to
      acquire **any** idle P before running Oren code (still under the scheduler lock; world-lock may further serialize execution).
      - Implementation note (important): in worker mode, `_green_poll_until` must **not** auto-rebind `P0` when the thread-local binding is cleared; it must acquire from the idle-P pool to enable `M < P` and fairness.
    - Stage N3 evolution (determinism): idle-P pool now uses a **FIFO queue** so idle Ps are acquired fairly (prevents “P2 starves forever” during M<P bring-up).
      - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` (2 workers, 3 Ps, world-lock; deterministic P swap + P2 acquisition)
	    - Stage N3 evolution (determinism): worker parking now uses **per-worker wake slots** so fixtures can wake a specific worker deterministically (instead of relying on wake-all ordering).
	      - Guard: `tests/native/test_green_two_workers_m_less_p_deterministic_smoke.oren` (same fixture; also covers P swap deterministically)
	    - Stage N3 evolution (STW safety): worker idle waits must be bounded and/or include `oren_gc_safepoint()` polling so `oren_gc_collect()` cannot deadlock while a worker is parked (includes park-word and netpoll waits).
	    - Stage N3 evolution (STW safety): host-thread joiners must also remain safepoint-friendly in worker mode:
	      - `oren_green_join_timeout(..., timeout_ms<0)` now avoids infinite kernel sleeps and polls `oren_gc_safepoint()` while waiting.
	      - POSIX fork+pipe `oren_join/oren_join_timeout` also avoids infinite kernel blocking (polls `oren_is_done` + `wait4(WNOHANG)` under `oren_gc_safepoint()`).
	        - This matters because the POSIX fork+pipe fallback is still exercised in Tier‑1 gates under `OREN_NO_GREEN=1` to prevent bitrot.
	      - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_green_join_waiter`)

### Test-only debug API: `oren_green_debug_*` (rolling)

The native green runtime intentionally exposes a small **test/fixture-only** surface (via `@oren.keep`) under the `oren_green_debug_*` namespace.

This exists to keep Tier‑1 scheduler regressions **deterministic** (no probabilistic wake ordering) while the scheduler is still evolving.

Hard rule (rolling): these functions are **not stable ABI**. They may change/remove without compatibility promises.

**Availability / safety**

- These helpers are intended for `tests/native/*.oren` and for developer debugging only.
- Do not use them in stdlib or “user-facing” examples.
- Many helpers are meaningful only in worker mode (`oren_green_start_workers`) or only on the host thread (not in-green).
- Return codes follow the runtime convention: `0` success; negative values are “-errno style” (example: `-16` = busy); some helpers return `-1` for “unsupported/invalid”.

**Determinism helpers (fixtures)**

- `oren_green_debug_wake_worker(worker_id)` / `oren_green_debug_clear_worker_wake(worker_id)`:
  - posts (or clears) a wake token for a specific worker’s park word.
  - enables “wake worker0 only” / “wake worker1 only” style fixtures.
- `oren_green_debug_worker_tid(worker_id)`:
  - best-effort: returns the OS tid for a specific worker (indexed by the worker’s reserved `P` id).
- `oren_green_debug_idle_p_requeue(p_id)`:
  - moves an **idle** `P` to the tail of the idle‑P FIFO, to deterministically control which `P` is acquired next.
  - returns `-16` if the `P` is not idle (`owner_tid != 0`).
- `oren_green_debug_spawn_call_list_to_p(p_id, fn_obj, args_list)`:
  - allocates a runnable task and enqueues it into a specific `P`’s local runq (does not auto-wake workers).
  - used by deterministic multi-worker fixtures (P swap, `M < P` acquisition).

**Observability helpers**

- `oren_green_debug_p_owner_tid(p_id)` observes `P.owner_tid` (0=idle, negative=reserved sentinel, positive=tid).
- `oren_green_debug_worker_count()` and `oren_green_debug_workers_ready_count()` help stabilize bring-up sequencing.
- `oren_green_debug_p_acquire_seen_mask()` returns a bitset of `P` ids that were acquired since the last `oren_green_debug_reset()` (durable “did P2 ever get acquired?” signal).
- `oren_green_debug_last_p_acquire_tid()` / `oren_green_debug_last_p_release_tid()` expose the tid recorded for the most recent acquire/release event (best-effort, can be overwritten by later events).
- The remaining counter helpers (`oren_green_debug_idle_iters`, `*_steal_*`, `*_p_acquire_*`, `oren_green_debug_reset`) exist for lightweight regression assertions.
  - Runtime: `lib/runtime_native/263_green_tasks.oren` (split modules: `lib/runtime_native/263_green/*.oren`)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_join`)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_start_workers_does_not_reserve_extra_ps`) (includes worker-ready counter check)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_worker_wake_while_sleepers`) (prevents “sleepers stall runnable work” regressions)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_many_tasks_bounded`) (many short tasks must complete; no hangs)
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_time_mono_ns_monotonic`) (`oren_time_mono_ns` must advance)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_ctx_switch_alloc_integrity`) (worker-mode ctx-switch must not corrupt scheduler locals / allocator state)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_local_ptr_survives_yields`) (ctx-switch must preserve long-lived locals across yields)
- Guard: `tests/native/test_quick_integration_native.oren` (`test_green_workers_local_ptr_survives_yields`) (same contract under worker-mode scheduling)
- Rolling limitation (important): `_green_poll_until` defaults to the conservative mode (re-fetch per-thread scheduler state `ts`/`P` each poll iteration).
  - Cached mode exists but is opt-in only (env `OREN_GREEN_POLL_CACHE=1` / `oren_green_set_poll_cache_mode(1)`).
  - Worker mode refreshes cached `P` bindings using a per-thread epoch so ownership transitions (M<P) cannot reuse stale `P` pointers.
  - Rationale: until native backend/local preservation invariants are fully tightened across ctx switches and syscalls, caching `ts`/`P` as long-lived locals
    can surface backend bugs as corrupted pointers later dereferenced via `ptr_get` / `ptr_get_byte`.
  - Fixed flake (2026-01-16): `OREN_GREEN_POLL_CACHE=1` could SIGSEGV (rc=139) due to a join/cleanup race where a joining thread could observe DONE
    (via ulock/futex mismatch wakeups) and `munmap` the green stack while the task was still executing on it.
    - Fix: introduce an internal EXITING state so tasks switch back to the scheduler before DONE is published and joiners are woken.
    - Runtime: `lib/runtime_native/263_green_tasks.oren` (`__oren_green_entry`, `_green_poll_until_budget`)
  - Rolling limitation (important): worker parallelism is currently clamped to 1 by default, because the native allocator/GC
  are not concurrency-correct yet. Opt-in for experimentation only: `OREN_GREEN_WORKERS_UNSAFE_PARALLEL=1`.
- Safer experimentation mode (rolling): enable a world-lock so `oren_green_start_workers(n>1)` can run while still enforcing
  “only one OS thread executes Oren code at a time”:
    - runtime knob: `oren_green_set_world_lock_mode(1)` (must be called before workers start)
    - env knob (alternative): `OREN_GREEN_WORKERS_WORLD_LOCK=1`
    - guard: `tests/native/test_green_two_workers_world_lock_smoke.oren`
    - Implementation note (fact, rolling): the world lock is held in `_green_poll_until_budget` across the scheduler loop + one green task execution,
      and is released before blocking waits (kevent/epoll, park-word wait, nanosleep) so other workers can still drive netpoll/timers while this worker blocks.
      - Lock ordering invariant: scheduler lock (`_green_lock_*`) is acquired before the world lock to avoid deadlocks.

Fixture guidance (fact; Tier‑1 stability):

- Prefer asserting ownership by observing `P.owner_tid` via `oren_green_debug_p_owner_tid(p_id)` and waiting with a monotonic-time spin (`oren_time_mono_ns` + `oren_yield`) rather than relying on “last acquire” debug markers.
  - Rationale: in multi-worker mode, unrelated reacquisitions can overwrite global “last event” counters before a fixture observes them.

Correctness gotchas (fact; Tier‑1 regression-driven):

- **Linux clone trampoline must initialize “reserved registers” for the child OS thread.**
  - The native bump allocator state lives in reserved callee-saved registers:
    - arm64: `X28` = heap_ptr, `X27` = heap_limit
    - x64: `R15` = heap_ptr, `R14` = heap_limit
  - Linux `clone(2)` threads inherit the parent register contents; if the child keeps those heap registers,
    the parent and child can allocate from the same bump region and corrupt heap objects/metadata under worker-mode scheduling.
  - Fix (2026-01-16): the `sys_thread_create` child path now resets the heap registers to `0` before calling the start routine,
    forcing the first allocation in the new OS thread to take the slow path (mmap a fresh chunk) and seed per-thread bump state.

- **Process exit on Linux must use `exit_group(2)` once OS threads exist.**
  - `exit(2)` terminates only the calling thread; if background workers exist, `exit(0)` can leave the process alive and look “hung”.
  - Fix (2026-01-16): arm64 native lowering routes source-level `exit(...)` to `exit_group` via `sys_exit_group`;
    `sys_exit` remains “terminate this thread” and is used by thread trampolines.

2) **Parking/unparking**
   - When an `M` has no work, it must block efficiently without busy looping.
   - Implement via a syscall-level wait primitive (platform-specific):
     - macOS candidates include kernel wait/wake interfaces used by system runtimes.
     - Linux uses `futex`.
   - The exact primitive is an implementation detail, but “sleep until work” is mandatory for production.

Status (rolling groundwork):

- The portable wait-on-address layer exists and is verified:
  - `lib/runtime_native/267_wait_on_addr.oren`
  - `tests/native/test_ulock_timeout_portable.oren`
  - `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_mismatch_is_success`) (locks in “wait while equal” semantics)
- The scheduler-oriented “park word” exists (token + wait-on-address) and is verified:
  - `lib/runtime_native/269_os_thread_m.oren` (`oren_m_park_word_wait`, `oren_m_park_word_wake`)
  - `tests/native/test_os_thread_park_unpark_smoke.oren`

3) **Run queues**
   - Each `P` has a local run queue for `G`.
   - There is a global queue for overflow and fairness.
   - Add work stealing between `P` (to balance load).
   - Requires atomics (already present: `atomic_add`, `atomic_cas`).

Rolling status (native runtime bring-up):

- The native green scheduler now models `P` local run queues as a **ring buffer** (monotonic head/tail + mask),
  with overflow to a scheduler-level **global run queue**. The local queue is treated as a **work-stealing deque**:
  - the owning `M` pops from the *tail* (LIFO locality), and
  - stealing `M` takes from the *head* (FIFO fairness).
  This keeps the shape aligned with an eventual atomics-based implementation while keeping the current bring-up lock model simple.

4) **Syscall blocking strategy**
   - Prefer non-blocking + event loop for IO-bound `G` (best scalability).
   - For truly blocking operations, detach the `G` from the `M` and let the `M` continue running other `G`.

5) **GC and stack scanning implications**
   - Oren’s current GC strategy must eventually become “stop-the-world at safepoints” or another well-defined scheme.
   - For N:M, you need:
     - a way to stop all `M` at safepoints, or
     - a conservative stack scanning strategy with coordination
   - This is a major reason to do N:1 first: it validates `G` stacks + yield points before introducing cross-thread coordination.

Status (rolling, fact):

- 2026-01-15: a minimal **stop-the-world at safepoints** protocol exists in the native runtime to make `oren_gc_collect()` safe when more than one OS thread exists:
  - Runtime impl: `lib/runtime_native/100_time.oren` (`native_gc_stw_begin/native_gc_stw_poll_and_park/native_gc_stw_end`)
  - Coordination words live in globals storage (wait-on-address): offsets `424/432/440` (see `lib/runtime_native/010_channels_globals_consts.oren`)
  - Guard: `tests/native/test_gc_stw_os_thread_collect.oren`
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_stw_os_thread_collect_scans_parked_stack`)
  - Limitation: cooperative only (threads must reach `oren_gc_safepoint()`); this is foundational plumbing for a future preemptive/stw design and for M:N.
- 2026-01-17: STW now **wakes blocked netpoll waits** to keep GC pauses bounded without 10ms polling:
  - Runtime: STW begin/end call `native_netpoll_wake()` (breaks kevent/epoll/select waits so threads can observe STW and park).
  - Scheduler: worker-mode netpoll waits can block up to 1s when the backend has a working wake mechanism; otherwise they fall back to a short bound.
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_stw_wakes_netpoll_blocked_threads`)
- 2026-01-16: compiler backends now insert **throttled cooperative safepoints** into loop headers (every 256 iterations) so OS threads can reliably reach `oren_gc_safepoint()`:
  - C backend transpiler: `lib/compiler/transpiler.oren`
  - arm64 native backend: `lib/compiler/arm64_native_stmt.oren` (`native_emit_gc_safepoint_throttled`)
  - x64 native backend: `lib/compiler/x64_native_program/060_emit_ops.oren` (`_emit_gc_safepoint_throttled_x64`)
  - Limitation: this is still loop-based cooperative polling; long-running non-loop code still needs a bounded safepoint strategy, and there is no preemption yet.
- 2026-01-16: native call-depth hook now also performs a **throttled STW poll** (every 1024 function entries) in multi-OS-thread mode:
  - Runtime: `lib/runtime_native/105_call_depth.oren` (`native_call_depth_safepoint_poll_throttled`)
  - This complements loop-header polling for call-heavy non-loop paths (visitors/recursion), but is still cooperative (no preemption).

## 4) Minimal language surface to support this

To avoid a spec rewrite while still enabling modern concurrency:

- Keep `spawn f(args...)` as the surface syntax, but redefine its semantics over time:
  - v0 (today): `spawn` is process-based (macOS bootstrap)
  - N:1: `spawn` creates a `G`
  - N:M: `spawn` creates a `G` scheduled over `M` threads

Add (recommended) explicit primitives:

- `yield()` (or `yield expr` later if it becomes an expression-level feature)
- `sleep_ms(ms)` (already exists; must be cancellable/timeout-safe)
- channels (`chan`, `send`, `recv`, `select`) for structured concurrency

## 5) Deliverables checklist (engineering milestones)

N:1 (must land before N:M to avoid massive debugging complexity):

- `Context` struct + `oren_ctx_switch` intrinsic (AArch64)
- `Context` blob + `oren_ctx_switch` intrinsic (x86_64)
- `G` struct (stack, context, status, id)
- scheduler loop in runtime (ready queue + timers)
- `yield()` intrinsic and at least one regression test that proves it yields
- non-blocking `sleep_ms` integration (scheduler timer)

N:M (after N:1 is stable):

- syscall-first `sys_thread_create` on macOS arm64
- `P` struct + per-P run queue
- `M` worker loop + parking/unparking
- work stealing
- GC coordination plan (even if “stop the world” at first)

## 6) Relationship to AVM “multiverse”

Native GMP enables “real world” libraries and services written in `.oren`.

AVM multiverse enables:

- deterministic simulation of agents
- policy scanning and governance
- portable snapshots

Both are mandatory long-term, but they solve different operational tiers.

## Design: Collections & Container Operations

This document merges the prior container-ops and unboxed `list<int>` design notes into
one coherent plan. It covers:

- **Container operations** (`push`, `len`, `get`, `set`, iteration) across generics and `dyn`.
- **Performance-first specialization** for integer-heavy lists (`list<int>` unboxed payload).
- **Lowering rules** that keep the compiler/backends stable in rolling mode.

---

## 0) Goals and Non-goals

### Goals

1) **Modern, ergonomic surface syntax**
   - Support `push(xs, v)` and future `xs.push(v)` sugar without backend penalties.
2) **Extensibility**
   - User-defined containers can participate via traits.
3) **`dyn`-friendly**
   - `push(&mut dyn Push[T], v)` dispatches through a vtable.
4) **Performance predictability**
   - Built-ins lower to intrinsics; generic code monomorphizes; dynamic uses vtables.
5) **Backends remain stable**
   - Kernel `oren_*` intrinsics stay in place to keep bootstrapping safe.
6) **Concrete perf win for integer-heavy loops**
   - `list<int>` has an unboxed representation in the native runtime.

### Non-goals (first slice)

- Full trait-object ABI design if not already stable.
- Operator overloading syntax (e.g. `<<` / `+=`) in the first implementation slice.
- Breaking legacy list semantics without explicit opt-in.

---

## 1) Three-layer model for container ops

### Layer A — Kernel intrinsics (`oren_*`)

Examples: `oren_list_push`, `oren_list_len`, `oren_string_len`, `oren_buf_len`, …

Properties:
- **Reserved namespace**: not user-idiomatic.
- **Compiler/runtime coupling**: lowering and runtime may depend on exact names.
- **Stability**: keep stable and avoid renaming during rolling mode.

### Layer B — Stdlib wrappers (safe now)

Provide thin wrappers (e.g. `std:list`) that call `oren_*` intrinsics.

Properties:
- Zero ABI risk.
- Enables gradual migration away from raw intrinsics.
- Standardizes naming and semantics.

### Layer C — Language-level “operations” (future)

Treat `push`, `len`, etc. as **language operations**:
- Lower to intrinsic fast paths for built-ins.
- Lower to trait impls for known types.
- Lower to vtable calls for `dyn`.

This yields modern syntax with deterministic, low-overhead lowering.

---

## 2) Semantics: `push` is an operation

Define `push(container, value)` as a single semantic operation with deterministic lowering.

Lowering rules (ordered):

1) **Intrinsic fast path**
   - If the container type is a built-in list (or other built-in container), lower to
     `oren_list_push` / `oren_*` intrinsic.
2) **Static trait dispatch**
   - If `Push[T] for C` is known, lower to the resolved method (monomorphized).
3) **Dynamic dispatch**
   - If the container is `dyn Push[T]`, lower to a vtable call.
4) **Otherwise: type error**

This keeps ergonomics without runtime penalties for built-ins.

### Infallible vs fallible push

- `push(&mut C, T) -> nil` (infallible, may abort on OOM depending on policy)
- `try_push(&mut C, T) -> bool` or `Result` for long-lived server/HPC usage

Recommendation: expose both for production-grade ergonomics.

---

## 3) Index operations remain index-based

`get`/`set` for lists remain index syntax:

- `x = xs[i]`
- `xs[i] = v`

Reasons:
- Already optimal across backends.
- Avoids naming drift (`get` vs `at` vs `index`).
- Supports aggressive lowering and bounds-check hoisting.

---

## 4) Unboxed `list<int>` (native runtime)

### Context

Benchmarks show native backend is far behind the C backend for array-heavy workloads
(e.g. `array_sum`, `dot_product`). Disabling bounds checks does not close the gap,
which implies the dominant costs are boxing/unboxing and GC scanning.

### Goals

- Provide a fast list for integer-heavy workloads.
- Eliminate per-element boxing and GC scanning.
- Enable native lowering to direct load/store of int64 values.

### Non-goals

- Full generic specialization or JIT.
- Implicit global changes to list semantics.
- Silent behavior changes without opt-in.

### Proposed representation

Introduce a **new tracked allocation kind** for `list<int>` in the native runtime
(e.g. `LIST_INT_KIND = 7`), leaving the current list kind unchanged.

Header layout is unchanged:

```
[count][capacity][buffer_ptr][magic]
```

For `list<int>`:
- `buffer_ptr` points to a contiguous array of **unboxed int64**.
- GC **does not** scan the elements.
- `list_magic()` remains unchanged so the header stays recognizable.

### Runtime API surface

Provide opt-in helpers:

- `oren_new_list_int(cap)`
- `oren_list_int_push(list, value)`
- `oren_list_int_get(list, idx)`
- `oren_list_int_set(list, idx, value)`
- `oren_list_int_reserve(list, cap)`

Generic list ops accept both list kinds, but specialized ops require list<int>.

### Compiler lowering

Minimal, explicit opt-in:

- Introduce an AST marker or constructor that yields `recv_kind = "list_int"`.
- Attach `recv_kind` to index expressions (`xs[i]`), enabling specialized lowering.

Native backend lowering:
- For `recv_kind == "list_int"`, emit direct int64 loads/stores.
- Keep bounds checks for correctness (hoist later if safe).

### Safety & compatibility

- Existing list behavior is unchanged.
- `list<int>` is explicit, not automatic.
- Generic list ops can detect `LIST_INT_KIND` and use specialized helpers.

---

## 4B) Unboxed `list<int>` in AVM / OBC (rolling)

### Context

OBC/AVM remains far from C on list-heavy benchmarks because list payloads are boxed
as `AvmValue[]`. Fused opcodes reduce dispatch overhead, but each iteration still
loads boxed values and pays memory bandwidth + tag overhead.

### Goals

- Unbox AVM `list<int>` payloads to reduce per-element overhead.
- Preserve deterministic execution and snapshot/restore correctness.
- Keep the change explicit and opt-in for rolling safety.

### Non-goals

- Generalize to all list element types.
- Replace boxed lists across the board.
- Add JIT/host-specific SIMD in the interpreter.

### Proposed representation (rolling)

Introduce a dedicated list-int payload in AVM rather than overloading boxed lists:

Option A (explicit value type):
- Add `AVM_VAL_LIST_INT` and `AvmListInt`:
  - `count`, `capacity`, `int64_t* items`
- Update `GET_INDEX` / `SET_INDEX` and list ops to accept both list kinds.

Option B (dual payload in AvmList):
- Extend `AvmList` with `int64_t* int_items` + `int has_int_items`.
- `oren_new_list_int` allocates `int_items` and sets `all_int = 1`.
- Non-int writes drop `int_items` and fall back to boxed semantics.

Option A is clearer and avoids dual-payload edge cases, but requires a new value
type and broader VM handling. Option B minimizes value-type churn but is trickier
to keep correct under mixed list operations.

### Bytecode lowering (preferred)

- Lower `oren_new_list_int(cap)` to a new opcode (e.g. `NEW_LIST_INT`) that returns
  the unboxed list-int value.
- Lower `oren_list_int_push` / `oren_list_int_get` / `oren_list_int_set` to dedicated
  opcodes that operate on list-int payloads.
- Extend `LIST_SUM_INT_LOOP` / `LIST_DOT` / `LIST_SUM3_INT_LOOP` to fast-path list-int
  payloads using `int64_t*` directly.

### Snapshot + determinism

- Snapshot encoder/decoder must handle the new list-int value type or payload.
- Hashing and trace output must be identical across hosts (no platform-specific
  float behavior; int64 only).

### Rollout (AVM)

1) Add list-int payload (Option A or B) + serialization support.
2) Add bytecode opcodes + lowering for list-int new/push/get/set.
3) Update fused loop ops to use `int64_t*` payload when available.
4) Add AVM-focused benchmarks for list-int loops and integrate into `RESULTS_LATEST.md`.

---

## 5) Interaction between container ops and `list<int>`

- `push(xs, v)` on a `list<int>` should lower to `oren_list_int_push` once the
  compiler knows `xs` is `list<int>`.
- Index ops (`xs[i]`, `xs[i] = v`) lower directly to unboxed loads/stores.
- This design preserves the same surface syntax while enabling fast paths.

---

## 6) Tests, benchmarks, rollout

### Tests (native)

- `tests/native/test_list_int_basic.oren`
- `tests/native/test_list_int_bounds.oren`
- `tests/native/test_list_int_mixed_reject.oren`

### Benchmarks

- Re-run `array_sum` and `dot_product` with `list<int>`; expect large reduction
  in native overhead relative to C.

### Rollout plan

1) Runtime kind + helpers.
2) Compiler surface (explicit constructor/marker) + lowering.
3) Tests + benchmarks.
4) Optional conversions (e.g. `list.to_int_list`).

---

## 7) Open questions

- Syntax choice: `list.int_new`, annotation, or new literal form.
- Standard library surface for dual dispatch (`list` vs `list<int>`).
- Behavior for `nil` in `list<int>` (likely disallow).

## GUI / UI Design for Oren (Rolling)

**Status:** Design + headless core implemented; bring-up shims exist for macOS + Windows + Linux/X11 (rolling)  

This document proposes a **production-oriented** GUI story for Oren that is consistent with:

- Oren’s “one language, three execution modes”: `native`, `c`, `bytecode (.obc/AVM)`.
- AVM’s capability-domain model (`CALL_NATIVE2(domain, op, nargs)`).
- Rolling constraints: fast iteration, deterministic tooling, and cross-platform targets.

Tier‑1 OS/arch intent (today): `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

Bring-up gates (headful, opt-in):

- macOS: `make verify-ui-smoke-macos`
- Windows: `make verify-ui-smoke-windows`
- Linux/X11: `make verify-ui-smoke-linux` (requires X11 dev + GUI session)

## 0) Goals and constraints

### Goals

1) **Cross-platform desktop GUI** with a stable userland API.
2) **Portable “UI core”**: the bulk of UI logic (tree/layout/diff/state) should run on *all* Tier‑1 platforms with minimal conditional code.
3) **Capability-scoped host effects**: windowing, GPU, clipboard, etc. are effects and must be routed through explicit capability domains (for sandboxing, auditability, and later record/replay).
4) **Tool-friendly packaging**: easy to ship an “app bundle” where UI code is portable and the platform shell is thin.
5) **Future-proof**: do not lock the project into a single rendering backend (Metal vs D3D vs Vulkan).

### Non-goals (v0)

- Full CSS compliance.
- Full HTML layout engine.
- A “toy” GUI that ignores input, text, DPI, etc.
- “GUI purely via syscalls”. Real GUI requires platform APIs; we should encapsulate them cleanly.

## 0.1) About `ui-idea.md`

Some earlier discussions referenced a `ui-idea.md` scratch file.

To avoid stale pointers, `ui-idea.md` now exists as a **short redirect** to the current design docs.

Treat this document (`docs/RUNTIME.md`) as the current source of truth for GUI design, shim bring-up, and the
optional ImGui shell.

## 0.2) Where Dear ImGui fits (and where it doesn't)

Oren’s long-term UI API should remain **retained-mode** and portable (`std:ui/*`), with deterministic headless tests.

Dear ImGui (immediate-mode) is still highly relevant to Oren, but in a *non-conflicting* role:

- as an **optional devtools overlay / inspector** (best fit),
- or as an **optional bring-up shell** on platforms where its upstream backends are mature,
  without turning ImGui into the *application UI API*.

Design note (fact-based):

- ImGui’s upstream docs emphasize “bloat-free”, portable, backend-oriented integration and explicitly
  position the library toward programmer tools rather than full end-user UI.
- This matches Oren’s rolling need for reliable “window + input + present” loops on Tier‑1, while still
  keeping Oren’s UI semantics in `std:ui`.

See the “Optional bring-up shell: Dear ImGui” section below for the concrete integration shape and
the in-repo upstream snapshots.

## 1) Recommended architecture: UI bytecode + native shell + UI capability domain

Oren’s best leverage is not “build a monolithic widget toolkit in native Oren first”.
The best path is a split similar to Flutter/ReactNative, but with one language end-to-end:

1) **UI logic runs as `.obc` bytecode** in AVM (portable, deterministic, policy-scannable).
2) A tiny **native shell** (Oren native or host app) provides platform integration:
   - window creation
   - event pump
   - rendering backend (software blit v0; GPU v1)
   - text measurement/shaping (later)
3) The VM calls host effects via a dedicated **UI capability domain** (new domain ID).

This is consistent with the existing AVM design direction:

- capability domains define *what effect is requested*
- the backend defines *where the effect is executed*

See `docs/AVM.md` (bootstrap spec) and `docs/AVM.md` (Next-Gen plan) for the domain/op model and governance direction.

### Why this is the best “first production” choice

- **Portability:** the UI core is the hardest part to stabilize; running it in AVM makes it cross-arch/OS by construction.
- **Security:** untrusted UI bundles can be restricted to UI-only (and optionally TIME) domains.
- **Testing:** UI core becomes testable in a headless deterministic runner (no OS windows required).
- **Backends:** the same UI core can later be reused for:
  - all-native mode (Oren native backend)
  - “C backend host” mode (portable host bring-up)

## 2) Programming model: declarative tree + diff + command buffer

The recommended UI programming model is **pure-functional view** + **explicit state**, producing a tree:

- `view(model) -> Node`
- A runtime loop:
  - receives events
  - updates model
  - re-renders (`view(model)`)
  - diffs old/new trees
  - emits a command buffer for the host renderer

This model is:

- deterministic (given event stream)
- easy to serialize/replay
- easy to test headlessly
- compatible with AVM sandboxing

### Node representation (v0)

Oren currently has dynamic values (maps/lists/strings/ints) and is rolling toward reflective types.
For v0, represent nodes as explicit maps (like `std:json` / `std:yaml` tagged shapes):

- Node map:
  - `{"t":"Text","k":"title","p":{...},"c":[...]}`
    - `t`: node type tag (string)
    - `k`: stable key (string) for diffing
    - `p`: props (map)
    - `c`: children (list of nodes)

This is intentionally “boring data”. It’s portable across backends and easy to serialize.

Later (v1+), if/when reflective types stabilize, nodes can become typed structs with stable metadata
without changing the model.

### Layout and styling (v0)

Start with a small layout model that composes:

- `Row`, `Column`, `Stack`
- fixed sizes + padding
- simple alignment
- scroll container (later)

Styles are maps:

- `{"font_size":16, "color":"#RRGGBB", "bg":"#RRGGBB", "padding":8, ...}`

This avoids committing to CSS parsing or cascade rules prematurely.

Rolling v0 implementation note:

- `std:ui/layout` supports:
  - padding: `pad` / `pad_x` / `pad_y` / `pad_{l,r,t,b}`
  - gap: `gap` (Row/Column)
  - alignment:
    - Row: `align_y` ("start"/"center"/"end")
    - Column: `align_x` ("start"/"center"/"end")

### Markup formats (XML / CSS?) — do we need them?

We do **not** need XML (or full CSS) to ship a production-quality GUI.

Fact-based constraints:

- Oren already has a strong *code as configuration* story: UI trees can be created as maps/lists in Oren
  code, and this works in all three execution modes (`native`, `c`, `bytecode`).
- Introducing an XML/CSS layer too early tends to create:
  - a second semantics surface (parser, escaping rules, tooling formats),
  - a cascade/layout complexity cliff (CSS compliance is not a v0 goal),
  - and more portability obligations (all parsers must behave identically across Tier‑1 and AVM).

Recommended direction (rolling):

1) **Primary authoring format:** Oren code (`Node` maps + helper constructors).
2) **Tooling/serialization formats:** add small “data interchange” options for editor tooling:
   - JSON (already aligned with the map/list/value model),
   - optional YAML/TOML only if we have a clear need.
3) **XML/HTML/CSS:** treat as optional ecosystem experiments, not as core UI dependencies.
   - If we later want a declarative markup, prefer a minimal schema that lowers to the node-map form,
     keeping `std:ui` as the semantic source of truth.

## 3) Host bridge: UI capability domain API (v0)

Define a single UI domain (example ID: `9`) with a narrow set of ops.
The UI core emits commands; the host executes them.

### 3.0 Render command buffer schema (headless contract)

Even before a platform shim exists, Oren needs a stable “render intent” contract so we can:

- regression test UI behavior deterministically (headless),
- build multiple render backends later (software blit v0, GPU v1),
- keep the UI core portable across platforms/backends.

Current v0 schema is implemented (and regression-tested in AVM) by:

- `std:ui/render` (`lib/std/ui/render.oren`) — tree → command list
- `std:ui/raster` (`lib/std/ui/raster.oren`) — command list → RGBA bytes (headless reference)

**Coordinate system (v0):**

- integer pixel coordinates
- origin `(0,0)` at **top-left**
- +x right, +y down
- rectangles are inclusive of `(x,y)` and cover `w*h` pixels

**Command list:**

- a list of maps; each map has an `"op"` string and required fields per op
- commands are emitted in deterministic order (preorder traversal)

Supported ops today:

- `fill_rect`:
  - `{"op":"fill_rect","x":int,"y":int,"w":int,"h":int,"color":string}`
- `text` (marker-only in v0 raster):
  - `{"op":"text","x":int,"y":int,"text":string,"color":string}`

**Color encoding (v0):**

- `"#RRGGBB"` or `"#RRGGBBAA"` (hex; case-insensitive)

**Validation (recommended):**

- `std:ui/commands.validate(cmds, w, h, opts)` validates a command buffer against the schema.
- `std:ui/raster.rasterize(...)` validates by default; disable with `opts["validate"]=0`.
- `opts["strict_bounds"]=1` rejects out-of-frame ops (useful in tests); default is permissive clipping.

Rolling note:

- `text` rasterization is intentionally not “real font rendering” in v0. The headless rasterizer draws
  one pixel per character to provide a deterministic test marker. A real platform text renderer belongs
  in the platform shim (or a later font subsystem).

### Minimal required ops

**Window**

- `open_window(title, w, h) -> win_id`
- `close_window(win_id) -> nil`
- `begin_frame(win_id) -> {w,h,scale}`
- `present(win_id) -> nil`

**Events**

- `poll_event(win_id, timeout_ms) -> event | nil`
  - Repo v0 shim ABI returns events via a flat out buffer (`int64[5]`), not a map:
    - `orenui_poll_event(win_id, timeout_ms, out5_i64_ptr) -> 0/1/<0`
    - `out[0] = type`, `out[1..4] = payload` (see `native/orenui/orenui.h`)
  - A higher-level Oren wrapper exists: `std:ui/host`
    - `std:ui/host.poll_event(win_id, timeout_ms, ev_buf)` converts the flat `int64[5]` payload into an
      event map (`{"t": "...", ...}`), which is the recommended form for portability and testability.

**Rendering**

For v0, pick one of:

1) **Software command buffer:** host exposes `fill_rect`, `draw_text`, `draw_image`, etc.
2) **Pixel buffer blit:** host exposes `get_framebuffer(win_id) -> bytes/typedbuf` and UI draws into it.

Pixel buffer blit is usually the fastest bring-up:

- deterministic (pure buffer writes)
- no GPU API surface in v0
- easy to debug (dump RGBA to PNG later)

### Platform shim boundary

The “host UI domain implementation” should be a small platform shim compiled with the platform toolchain:

- macOS: Cocoa/Quartz/Metal (event pump, window, blit)
- Windows: Win32 + GDI (DIBSection + BitBlt) or D3D11 later
- Linux: X11/Wayland (start with X11 for reach; later Wayland)

Oren’s native backend should interact with this shim via FFI:

- Windows: `@ffi.dll("orenui_win.dll")` style
- Linux: `@ffi.link("liborenui_linux.so")` style
- macOS: `@ffi.link("liborenui_macos.dylib")` style

This keeps the core repo syscall-first while acknowledging that GUI requires platform frameworks.

### 3.1) Platform shim bring-up plan (OrenUI v0)

Current repo state (fact):

- In-tree shim header: `native/orenui/orenui.h`
- macOS shim implementation exists: `native/orenui/cocoa/orenui_cocoa.m`
- Windows shim bring-up exists: `native/orenui/win32/orenui_win32.c` (v0 skeleton; window + present + pump)
- Linux/X11 shim bring-up exists: `native/orenui/x11/orenui_x11.c` (v0 skeleton; window + present + pump)
- Smoke gate (macOS-only; requires GUI session): `scripts/verify_ui_smoke_macos.sh` (`make verify-ui-smoke-macos`)
- Smoke gate (Windows; requires GUI session): `scripts/verify_ui_smoke_windows.sh` (`make verify-ui-smoke-windows`)
  - MSVC environment is auto-configured via `scripts/win_msvc_cmd.cmd` (no VS Developer Prompt required).
- Smoke gate (Linux; requires X11 GUI session + dev libs): `scripts/verify_ui_smoke_linux.sh` (`make verify-ui-smoke-linux`)
  - Build detail: links with `-pthread` + `libX11` (some distros still require explicit pthread linkage).
- Missing today (still true):
  - Stable input/event schema (v0 currently only supports close/pump reliably).
  - DPI/scale reporting beyond “best-effort scale=1”.
  - Wayland support (future; X11 is the v0 target).

v0 must do:

1) Create a window with a pixel surface (RGBA).
2) Pump OS events (mouse, keyboard, resize, close).
3) Present a provided RGBA framebuffer to the window at interactive rates.
4) Provide DPI scale (or at least a stable “scale=1” until implemented).

v0 must not do:

- Implement layout/widgets/state (belongs in `std:ui/*`).
- Expose platform APIs directly to user Oren code (avoid Win32/X11/Cocoa leakage).
- Require a GPU API just to show pixels.

Recommended v0 boundary: “RGBA blit shell”

- UI core:
  - `std:ui/render`: tree → deterministic command buffer
  - `std:ui/raster`: commands → RGBA bytes
- Shim:
  - `present_rgba(win_id, w, h, rgba_bytes, stride)` → display
  - `poll_event(win_id, timeout_ms)` → return next event

This matches the existing headless rasterizer, so platform shims can start by “just blitting pixels”
without committing to a GPU backend.

ABI surface options (choose one for implementation):

Option A (preferred): C ABI + flat POD (no structs in v0)

- Repo fact (today): the v0 ABI in `native/orenui/orenui.h` intentionally avoids `struct`/`union` parameters.
- Events are returned via an `int64[5]` out buffer (`orenui_poll_event(..., out5_i64_ptr)`).

Event payloads (v0, implemented):

- `ORENUI_EV_CLOSE`:
  - `out[0]=1`, rest `0`
- `ORENUI_EV_RESIZE`:
  - `out[0]=2`, `out[1]=w`, `out[2]=h`
- `ORENUI_EV_MOUSE_MOVE`:
  - `out[0]=3`, `out[1]=x`, `out[2]=y`, `out[3]=mods`
- `ORENUI_EV_MOUSE_DOWN` / `ORENUI_EV_MOUSE_UP`:
  - `out[0]=4/5`, `out[1]=btn (1=left,2=middle,3=right)`, `out[2]=x`, `out[3]=y`, `out[4]=mods`
- `ORENUI_EV_KEY_DOWN` / `ORENUI_EV_KEY_UP`:
  - `out[0]=6/7`, `out[1]=key (platform raw)`, `out[2]=mods`
- `ORENUI_EV_TEXT`:
  - `out[0]=8`, `out[1]=codepoint (best-effort)`, `out[2]=mods`

Notes:

- `mods` bitmask (v0): `1=shift`, `2=ctrl`, `4=alt`, `8=super` (best-effort across OSes).
- Key codes are currently platform-raw; a stable cross-platform key enum is a future layer.
- Unicode text is best-effort in v0; full IME and surrogate pairing are future work.

Suggested C ABI (v0):

- Window lifecycle:
  - `int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h);`
  - `void orenui_close_window(int32_t win_id);`
  - `void orenui_set_title(int32_t win_id, const char* title_utf8);` (optional)
- Frame:
  - `int32_t orenui_begin_frame(int32_t win_id, struct OrenUIFrameInfo* out);`
  - `int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, const uint8_t* rgba, int32_t stride);`
- Events:
  - Implemented (repo): `int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, int64_t out5_i64_ptr);`
    - returns: `0 = none`, `1 = event`, `<0 = error`
    - `out[0] = type`, `out[1..4] = payload` (see `native/orenui/orenui.h`)

Future (v1+):

- Switch to explicit `struct OrenUIEvent` / `struct OrenUIFrameInfo` once Oren FFI has a stable
  “struct by pointer” story.

Option B: C ABI returning “event maps” (slower, but closer to Oren values)

- Pros: matches the event map examples in this doc directly.
- Cons: requires JSON parsing in the event loop (extra allocations + latency), harder to keep stable across backends.

Unless we absolutely need this for AVM-first integration, prefer Option A.

Per-platform v0 implementation notes (RGBA blit):

Windows (`x64-windows`)

- Window creation: `CreateWindowExW` + message loop (`PeekMessageW` / `GetMessageW`)
- Blit strategy (v0):
  - `StretchDIBits` (simple) or
  - `CreateDIBSection` + `BitBlt` (often faster)
- Events:
  - mouse: `WM_MOUSEMOVE`, `WM_LBUTTONDOWN`/`UP`, `WM_RBUTTONDOWN`/`UP`, etc.
  - keyboard: `WM_KEYDOWN`/`UP`, `WM_CHAR`
  - resize: `WM_SIZE`
  - close: `WM_CLOSE`
- DPI:
  - start with `scale=1` unless `WM_DPICHANGED`/`GetDpiForWindow` is used.

Linux (`arm64-linux`, `x64-linux`)

- Start with X11 for reach; Wayland can be added later.
- Window creation: Xlib (`XOpenDisplay`, `XCreateSimpleWindow`, `XMapWindow`)
- Event pump: `XPending`/`XNextEvent`
- Blit strategy (v0):
  - `XPutImage` with an `XImage` that wraps the RGBA buffer (conversion may be required)
  - later: XShm for performance
- DPI:
  - v0: `scale=1`
  - later: derive from Xft/DPI settings or per-monitor info

macOS (`arm64-macos`)

- Window creation: `NSApplication` + `NSWindow` + `NSView`
- Event pump: `-[NSApp nextEventMatchingMask:untilDate:inMode:dequeue:]`
- Blit strategy (v0):
  - create `CGImage`/`CGBitmapContext` from RGBA bytes and draw in `drawRect`
  - later: Metal texture upload path (v1)
- DPI:
  - `backingScaleFactor` on the window/screen

Bring-up hazard (observed):

- If the host program is not a traditional Cocoa `main()` that calls `-[NSApplication run]`,
  “per-call” `@autoreleasepool { ... }` blocks inside a shim can crash under repeated use.
  Prefer a single long-lived pool owned by the shell (or reintroduce pools only after the
  run loop ownership model is settled).

Concrete v0 deliverables (what to build next):

1) Finalize the shim ABI (`native/orenui/orenui.h`):
   - lock a minimal set of v0 calls (open/close/poll/begin_frame/present_rgba)
   - lock the `OrenUIEvent` tagged union layout
2) macOS (`arm64-macos`):
   - keep iterating `native/orenui/cocoa/orenui_cocoa.m` until the v0 ABI is fully implemented
   - keep `scripts/verify_ui_smoke_macos.sh` green (headful; opt-in)
3) Windows (`x64-windows`):
   - add `native/orenui/win32/*` implementing the same ABI using Win32 + GDI (RGBA blit)
   - keep `scripts/verify_ui_smoke_windows.sh` green (headful; opt-in)
4) Linux (`x64-linux`, `arm64-linux`):
   - add `native/orenui/x11/*` implementing the same ABI using Xlib + XPutImage (v0)
   - keep `scripts/verify_ui_smoke_linux.sh` green (headful; opt-in; WSL2 is not a GUI target by default)
5) Oren-side integration:
   - done: `std:ui/host` bindings exist (`lib/std/ui/host.oren`) and convert the flat `int64[5]` payload into an event map
   - done: `examples/ui_hello.oren` opens a window and draws a `std:ui` frame (uses `std:ui/host`)

## 4) Packaging model

Recommended app structure:

- `app_shell` (native Oren binary)
  - loads UI bytecode `app_ui.obc`
  - creates AVM instance
  - allows only UI domain ops (and optionally TIME/RNG)
  - runs the VM event loop
- `app_ui.obc` (bytecode compiled from Oren UI sources)

Benefits:

- update UI without replacing the whole native app
- potential “AppStore/multiverse updates” story aligns with signed `.obc`
- capability allowlist is explicit and auditable

## 5) Declarative UI formats: do we need XML and CSS?

### Do we need XML?

Not for v0.

Oren already has deterministic `std:yaml` and `std:json` (`lib/std/yaml.oren`, `lib/std/json.oren`).
If we want “non-code” UI declarations early, YAML is the lowest-friction choice:

- stable parser already exists
- good for trees and configs
- deterministic encoding rules already documented/implemented

XML becomes valuable when we need:

- compatibility with existing XML UI ecosystems, or
- strict schemas/DTDs, or
- complex mixed-content text layouts.

Those are not required to build a production GUI core. XML can be added later as `std:encoding/xml`
and used by `std:ui/markup_xml` without changing the UI core.

### Do we need CSS?

Not for v0.

CSS is large (cascade, selectors, specificity, inheritance, media queries, etc).
The project can still have a “CSS-like” styling story without adopting CSS the standard:

- v0: style maps + explicit composition (`merge_style(base, override)`)
- v1: a small CSS subset parser in `std:ui/css` (selectors limited to type + id + class)
- v2+: optional cascade rules if/when needed

The key is to avoid entangling layout correctness with CSS semantics early.

## 6) Testing strategy (non-negotiable)

We want GUI bring-up without “manual clicking” being the only test.

### Headless deterministic tests (fast, CI-friendly)

- UI tree diff correctness (pure functions)
- layout engine invariants (golden sizes/positions)
- style merge correctness
- command buffer generation (golden command streams)

These should run under AVM without host windows.

### Platform smoke tests (Tier‑1, opt-in)

- “open window, draw frame, close” smoke per OS
- input pump sanity (“mousemove generates event”)

These are still valuable but should not be the only correctness story.

### Optional bring-up shell: Dear ImGui (integration candidate)

Oren’s planned UI stack is retained-mode and portable at the `std:ui/*` level.
Dear ImGui is immediate-mode and does **not** replace the Oren app UI API.

Non-conflicting roles:

1) **Devtools / inspector overlay** (recommended)
   - layout inspector / widget tree explorer
   - perf overlays (layout/raster timing, allocations, GC stats)
   - debug consoles / REPL surfaces
2) **Bring-up shell shortcut** (optional, non-blocking)
   - provides “window + input + GPU present” earlier on platforms with mature ImGui backends
   - keeps `std:ui` as the portable user API

Why ImGui does not replace `std:ui`:

- ImGui is immediate-mode (great for tooling, not a declarative retained-mode widget system).
- Oren UI must be deterministic for AVM/headless tests.
- Long-term Oren UI needs stable reflection + data binding; ImGui is intentionally minimal.

Practical integration shape (recommended):

- Keep ImGui out of the language core and out of `std:ui` semantics.
- `std:ui/*` stays the stable API (layout/render/raster + event model).
- Platform shims (`native/orenui/*`) remain the thin “window + event pump + present” layer.
- An ImGui path can exist as an **optional shell**:
  - `native/orenui/imgui_shell/*` (or `native/orenshell_imgui/*`) compiled as a shared library
  - provides the same C ABI as other platform shims (or a superset ABI for devtools only)
  - can host an ImGui overlay and/or drive presentation through an existing renderer backend

Why ImGui is a good fit for Oren’s “no-bloat” philosophy (facts):

- **Bloat-free core + no external deps:** self-contained and renderer-agnostic (see upstream README).
- **Decoupled rendering:** outputs draw lists / vertex buffers for your pipeline.
- **Small surface area:** immediate-mode API with minimal “state synchronization” overhead.
- **Mature cross-platform backend ecosystem:** upstream maintains multiple platform/render backends.
- **License:** MIT (see upstream license).

Known limitations (fact; important for Oren UI long-term):

- Upstream explicitly targets programmer tools (not full end-user UI), and does not aim to solve
  full i18n text shaping or accessibility out of the box. This is why it remains optional.

Backend audit (sources in-repo):

- `project-doc/web/github.com/ocornut/imgui/20260113/docs_BACKENDS.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/docs_README.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/docs_FAQ.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/root_index.json` / `docs_index.json` (GitHub API snapshots)

Tier‑1 constraints (Oren):

- Tier‑1 targets (rolling): `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`.
- The repo’s Tier‑1 x64 Linux environment is currently validated via **WSL2** for CI-like bring-up.
  WSL2 is not a reliable GUI target by default. Treat Linux GUI as a real Linux desktop session target,
  not as part of remote WSL2 smoke gates.

Next actions (non-blocking):

- Keep bringing up `native/orenui/*` per-platform shims (RGBA present + input pump).
- Once one shim is stable, add an opt-in ImGui overlay build that can:
  - attach to the same window
  - show Oren UI debug state (frame timings, command buffer stats)
- Defer any “use ImGui to render Oren UI widgets” until Oren’s retained-mode UI API is stable.

Suggested backend choices (Tier‑1 oriented; not commitments):

- **Windows x64:** Win32 window + D3D11 renderer backend.
- **macOS arm64:** Cocoa window + Metal backend (avoid OpenGL as the primary path).
- **Linux x64:** X11 window + OpenGL backend (widest reach; Wayland can come later).

## 6.1) Current implementation status (v0)

Implemented (headless, portable):

- `std:ui/core` (`lib/std/ui/core.oren`): node constructors + keyed `diff()` + `apply_patch()` (actionable patches)
- `std:ui/layout` (`lib/std/ui/layout.oren`): deterministic layout v0 (`Row`/`Column`/`Stack`, fixed-size leaves)
- `std:ui/style` (`lib/std/ui/style.oren`): deterministic style merge (no CSS yet)
- `std:ui/render` (`lib/std/ui/render.oren`): render → deterministic command buffer (no platform drawing yet)
- `std:ui/raster` (`lib/std/ui/raster.oren`): deterministic software rasterization into RGBA bytes (headless reference)
- `std:ui/ppm` (`lib/std/ui/ppm.oren`): minimal PPM encoder for debugging and golden byte tests
- `std:ui/color` (`lib/std/ui/color.oren`): shared hex color parsing/validation (`#RRGGBB` / `#RRGGBBAA`)

Regression gates (headless):

- `make test-avm`
  - `tests/avm/test_ui_layout_v0.oren`
  - `tests/avm/test_ui_render_v0.oren`
  - `tests/avm/test_ui_raster_v0.oren`
  - `tests/avm/test_ui_ppm_v0.oren`
  - `tests/avm/test_ui_patch_v0.oren`
  - `tests/avm/test_ui_color_v0.oren`

## 7) Roadmap tasks (tracked in `docs/TODOS.md`)

This document defines the intended design; implementation tasks are tracked in `docs/TODOS.md`.
The recommended progression is:

1) `std:ui` portable core (node model + diff + layout + style)
2) UI domain v0 contract (domain/op table + minimal shims)
3) software framebuffer renderer v0 (cross-platform shim per OS)
4) text measurement/shaping + font loading (incremental; can be stubbed initially)
5) richer widgets and accessibility (later)


---

# Networking and IO (Rolling)

This document consolidates async IO, network stacks, and platform-specific netpoll notes.

## Async IO Readiness + `select` in Oren (Rolling Design + Current Reality)


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

- `docs/LANGUAGE.md` keyword list + grammar (no `select`).

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

- `docs/AVM.md` (VirtualFS/VirtualNET/VirtualPROC backends)
- `docs/AVM.md#avm-in-avm-multiverse-design-nested-virtual-universes` (nested universes / host service constraints)

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

- CoreIR is the canonical semantics owner (`docs/COMPILER_BACKENDS.md`)
- native scheduler exists (`docs/RUNTIME.md`)

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
- After that: native scheduler + channels/select maturity and IO integration — see `docs/LANGUAGE.md` / `docs/RUNTIME.md`
  - Windows IOCP design notes (rolling): `docs/RUNTIME.md`

## Windows IOCP Netpoller (Native Runtime) — Design Notes (Rolling)

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
- `x64-linux` / `x64-windows` runs require the remote Win11 (WSL2 optional) host; see `docs/TOOLCHAIN_PLATFORMS.md` if the proxy/hostname is unavailable.

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
- `docs/COMPILER_BACKENDS.md#native-backend-overview` (native dynamic linking model)

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

- Full semantic parity still requires the tagged value model described in `docs/COMPILER_BACKENDS.md#native-tagged-value-representation` (notably: robust `int` vs `float` tagging in native mode).

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
- `x64-linux` / `x64-windows` runs require the remote Win11 (WSL2 optional) host; see `docs/TOOLCHAIN_PLATFORMS.md` if the proxy/hostname is unavailable.

## API (v0)

All functions are timeout‑bounded to avoid hangs.

- `ws.connect(url, timeout_ms)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver(url, timeout_ms, resolver)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver_opts(url, timeout_ms, resolver, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - `opts["tls"]` is passed to `tls.wrap_client` for `wss://` URLs (see `docs/RUNTIME.md`).
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
  - TLS provider availability is OS-dependent; see `docs/RUNTIME.md`
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
