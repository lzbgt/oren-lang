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
- See `docs/OBC_DISTRIBUTION.md`.

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
- `docs/LANGUAGE_APPENDICES.md` (language-level concurrency surface)
- `docs/AVM_ROADMAP.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly` (deterministic concurrency inside AVM; different goal)

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

AVM concurrency (`docs/AVM_ROADMAP.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`) is about:

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
**Last updated:** 2026-01-12

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

Treat this document (`docs/STDLIB_AND_RUNTIME.md`) as the current source of truth for GUI design, shim bring-up, and the
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

See `docs/AVM_SPEC.md` (bootstrap spec) and `docs/AVM_ROADMAP.md` (Next-Gen plan) for the domain/op model and governance direction.

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
