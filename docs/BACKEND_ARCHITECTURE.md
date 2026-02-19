# Backend Architecture & Design

This document consolidates the backend design, ABI, and performance guidance for the C, native, and bytecode backends. It merges the prior backend design docs into a single source of truth to reduce drift while Oren is in rolling mode.

This repo targets Oren as a **modern, efficient, technically solid, future‑proof language** with:

- **3 compiler backends**: `c`, `native`, `bytecode` (`.obc`)
- **AVM** (Agent Virtual Machine) as a first‑class execution target for `.obc`
- “compiler in AVM” and nested universes (“AVM in AVM”) as a core agentic capability
- Tier‑1 **arm64** and **x86_64** support across **macOS / Linux / Windows** (rolling)

This document describes the architecture needed to keep those components:

- **consistent** (same language semantics everywhere),
- **reusable** (no N×M duplication across backends and targets),
- **provable** (fixtures and differential tests catch regressions),
- **SOLID** (clear module boundaries and stable interfaces).

## Non‑Negotiable Invariants

1) **Semantic parity is the product.**
   - If a language feature behaves differently across backends, that is a bug (unless explicitly documented as a rolling limitation).

2) **Determinism is a first‑class constraint.**
   - For AVM/multiverse, we need deterministic execution under budgets and virtualized backends (see `docs/AVM_SPEC.md`).
   - For native, we need deterministic build outputs when requested (`--deterministic`).

3) **Capabilities are explicit.**
   - Effectful operations must be expressible in a capability-domain model (FS/NET/PROC/ENV/TIME/…).
   - AVM enforces this directly; native and C backends must converge on the same logical model.

4) **Tier‑1 means “real validation,” not “best effort.”**
   - Tier‑1 targets must be validated on real machines (or equivalent trusted infrastructure), not only “builds on my laptop”.
   - See `docs/REMOTE_X64_ENV.md` for x86_64 validation, and existing arm64 fixtures.

## The Unification Strategy: One Frontend, One Canonical IR, Thin Backends

Today the repo already has:

- A production‑oriented **C backend** (architecture neutral via the host C toolchain): `docs/BACKEND_ARCHITECTURE.md#c-backend-design-and-abi`
- A high‑performance **native backend** (arm64 rich; x86_64 bring‑up): `docs/BACKEND_ARCHITECTURE.md#native-backend-overview`
- A portable **bytecode backend** emitting `.obc`, executed by **AVM**: `docs/AVM_SPEC.md`

To keep this scalable, we need a structure that avoids re‑implementing semantics per backend.

### Recommended pipeline

**Stage A — Frontend (shared)**

1) Parse → AST
2) Resolve imports → linked module graph
3) Typecheck / monomorphize / lower high-level sugar
4) Produce a canonical, backend-independent IR

Call this canonical IR **CoreIR**:

- It must represent *language semantics* precisely:
  - evaluation order
  - short‑circuiting rules
  - loop `break/continue` rules
  - varargs/spread lowering decisions
  - closure capture layout rules
- It must be deterministic (stable ordering, no map iteration dependence).

Rolling implementation status (today):

- CoreIR is being introduced incrementally. The first in-repo scaffold is:
  - `lib/compiler/coreir.oren`
  - currently: deterministic extraction of top-level function metadata (decl order, arity, varargs)
  - initial consumer: x86_64 native backend prepass (Tier‑1 bring-up)
- Next steps (tracked in `docs/TODOS.md`): migrate call canonicalization (callables + varargs + spread) into CoreIR so backends stop re-deciding semantics.

**Stage B — Backend adapters (thin)**

Each backend implements:

- `CoreIR -> BackendIR` (mechanical lowering, no language semantics)
- `BackendIR -> output` (encoding / emission / linking)

Concrete mapping:

- **Bytecode backend**: `CoreIR -> BytecodeIR -> .obc`
- **C backend**: `CoreIR -> C-IR (or C AST) -> C source -> toolchain`
- **Native backend**: `CoreIR -> NativeIR -> ISA selection + ABI -> object format`

`NativeIR` here matches the direction in `docs/BACKEND_ARCHITECTURE.md#native-backend-code-reuse-plan`.

Key rule: **only Stage A decides semantics**. Stage B should never decide what “`for` means” or how `...rest` is represented.

## Canonical Runtime ABI: Make “Callables” the Spine

The single biggest cross-backend semantic surface is **callables**:

- named functions used as values
- lambdas/closures with captured environments
- varargs (`...rest`) and spread (`xs...`)
- indirect calls and spawn/join

The repo already has a strong direction:

- C backend: uniform callable ABI via `oren_call_obj(...)` / `oren_call_obj_list(...)` (`docs/BACKEND_ARCHITECTURE.md#c-backend-design-and-abi`)
- AVM: explicit `PUSH_FUNC`, `MAKE_CLOSURE`, `CALL_INDIRECT` (see `docs/AVM_SPEC.md`)
- Native (arm64): runtime helpers exist (`lib/runtime_native/120_first_class_fn.oren`) and callable lowering is being centralized (`lib/compiler/native_callable.oren`)

### Canonical callable model (recommended)

Define a single logical callable value model:

- `FuncValue = { code_ptr, env_ptr }`
- Call ABI: `call(FuncValue, args_list) -> value`

Notes:

- `args_list` is a *real* list object in each backend/runtime, not an ad-hoc stack convention.
- Direct calls can still be optimized (no list allocation) by wrappers, but the semantic model stays the same.

This model makes:

- **varargs** natural (`...rest` is a list; spread concatenates lists)
- **closures** natural (`env_ptr` points at a list/struct of captures)
- **AVM/native/C** alignment straightforward (all can implement `call_obj_list`)

### Rolling reality (today)

Some backends are still “mid-convergence”:

- x86_64 native now uses the **uniform callable ABI** for *function values + indirect calls*:
  - `FuncValue = { code_ptr, env_ptr }` stored in a small “fnobj” record
  - indirect calls build an `args_list` and call `code_ptr(env_ptr, args_list)`
  - named function values point at synthesized wrappers `__oren_fnwrap_*`
  - lambda literals lower to heap fnobj records where `env_ptr` points at a capture-by-value list (or `0` for capture-free lambdas), and `code_ptr` points at `__oren_lambda_*` wrappers
- x86_64 native now has a **best-effort panic trace** (RBP chain) and a minimal **addr→fn+offset** symbolication path (embedded symtab, fixed-base emitters) so Tier‑1 bring-up failures are diagnosable without AVM.
- Remaining Tier‑1 gaps: symbolic stack traces (addr→fn/line mapping), richer `OREN_DIAG` parity with runtime-native diagnostics, and performance work (avoid per-call `args_list` allocations for common cases).

Implementation note (rolling):

- Fixed-base constants for x64 ELF/PE are centralized in `lib/compiler/native_abi.oren` (`x64_v0_*` helpers) so the emitters and the panic symbolication logic cannot drift.

This is acceptable in rolling mode as long as:

- the direction is explicit,
- fixtures guard what is implemented today,
- the ABI surface is not painted into a corner.

## Capabilities + IO: Keep the Effect Model Consistent

AVM has a capability-domain model baked in (domains + ops, policy scanning, strict verification).

For consistency:

- **CoreIR** should encode effectful operations in a domain/op form (conceptually).
- C/native backends should lower those to:
  - syscall-first runtime helpers (native),
  - runtime C functions / libc bridging where applicable (C backend),
  - `CALL_NATIVE2` (AVM).

This is how “AVM as stdlib” stays feasible:

- stdlib can be compiled into `.obc` and run in a sandbox with VirtualFS/NET/PROC
- native/server deployments can run the same stdlib logic with host syscalls (subject to runtime capsule policy)

## SOLID Backend Boundaries (Practical Rules)

To keep the codebase maintainable as targets grow:

- **Single Responsibility**
  - frontend passes decide semantics
  - backend passes decide representation/encoding
  - emitters decide file formats (Mach‑O/ELF/PE)
- **Open/Closed**
  - adding a new target should be mostly “implement a new ABI table + emitter”, not “edit 20 existing files”
- **Liskov**
  - a backend is a drop-in implementation of the same CoreIR contract (same tests should apply)
- **Interface Segregation**
  - `NativeABI` should expose small queries (arg regs, alignment, shadow space), not leak instruction encoders
- **Dependency Inversion**
  - shared lowering depends on abstract `ABI`/`Emitter` interfaces; ISA-specific code depends on shared lowering, not the reverse

## Test Strategy (How We Prevent Semantic Drift)

1) **Curated cross-backend tests** for semantics:
   - same `.oren` source compiled under `--backend c`, `--backend native`, `--backend bytecode`
   - compare exit codes and (where deterministic) stdout

2) **Targeted fixtures** for ABI-sensitive behavior:
   - x86_64 Win64 shadow space and arg regs
   - SysV vs Win64 arg register count differences
   - stack alignment-sensitive calls

3) **Opt-in remote Tier‑1 smoke**:
   - validate x86_64 on real Windows + WSL2 by copying the built artifact(s) to an x86_64 host and executing them

## C Backend Design and ABI

Oren’s current “production” backend is a **transpiler to C** plus a small C runtime in `lib/runtime.[ch]`.

### What Happens When You Build
Given `hello.oren`, both the stage0 (`oren_bootstrap`) and the self-hosted compiler (`oren`) do:
1) Read and parse `hello.oren` into an AST
2) Transpile the AST into a single C translation unit `hello.oren.c`
3) Invoke a C toolchain to compile and link:
   - the generated `hello.oren.c`
   - `lib/runtime.c`

The default compiler driver is:

- macOS/Linux: `cc` (typically `clang`/`gcc`)
- Windows hosts (x64, rolling): if `--cc` is omitted, the compiler defaults to **MSVC `cl.exe`** and will
  attempt to auto-configure the VS environment (via `vswhere.exe` + `VsDevCmd.bat` / `vcvars64.bat`).

You can override it with `--cc` (and stage0 also accepts `$CC`).

### Output Files
- `hello.oren.c`: generated C source (use `--emit-c` to stop here)
- `hello`: the final native executable built by `cc`

### How Oren Maps to C
The generated C program:
- includes `lib/runtime.h`
- lowers Oren operations into calls like `oren_add`, `oren_print`, `oren_list_get`, `oren_new_map`, …
- defines `main()` which calls `oren_init(argc, argv)` then runs the top-level statements

### First-class Functions and Lambdas (C Backend)

The C backend supports **first-class function values** and **closure lambdas** via a uniform callable ABI:

- Runtime value type: `OREN_TYPE_FUNC` (in `lib/runtime.h`).
- Callable ABI: `OrenFn fn(void* env, int argc, OrenValue* argv)`.
  - `env` is reserved for closure environments (captured values).
  - Named functions and constructors get an auto-generated wrapper entrypoint:
    - `name__oren_fnwrap(void* env, int argc, OrenValue* argv)`
- Lambdas compile to compiler-generated wrapper functions like:
  - `__oren_lambda_<unit>_<n>(void* env, int argc, OrenValue* argv)`
  - and construct a closure value with capture-by-value using `oren_closure(...)`.

#### Calling and Spawning Callables

- Indirect calls (function values / closures) go through `oren_call_obj(...)` / `oren_call_obj_list(...)`.
- `spawn` lowers to `oren_spawn_call_list(fn_value, args_list)` so it can spawn:
  - direct named functions,
  - function values stored in variables,
  - lambdas/closures with captured environments.

See `docs/SELF_HOSTING.md` for more details on the lowering rules.

### Working With Your Own C Source Files
Oren does not have a stable C FFI surface yet, but you can still link extra C code by compiling the generated C yourself:
```sh
./oren --emit-c hello.oren
cc -o hello hello.oren.c lib/runtime.c -Ilib path/to/your.c
```

This is useful for experiments, but the long-term goal is “Option B” (native backend) where Oren produces executables directly without emitting or compiling C.

## Native Backend Overview

The native backend emits machine code directly for:

For “do not regress” invariants (and the regression gates that enforce them), see `docs/BACKEND_ARCHITECTURE.md#native-backend-guardrails`.

- **ARM64** (primary): macOS (Mach-O) and Linux (ELF)
- **x86_64** (Tier 1; rolling evolution): Linux (ELF) and Windows (PE32+)

The x86_64 backend is a Tier-1 target, but is still in rolling evolution; `docs/TODOS.md` tracks what is implemented today and what is next.

### ABI Notes (x86_64 SysV vs Win64)

Oren the language supports first-class functions and varargs; any “arg count” limits you see in
bring-up fixtures are **ABI facts**, not language constraints.

- **Linux x86_64 SysV ABI** (ELF):
  - integer args in registers: `rdi, rsi, rdx, rcx, r8, r9` (6 regs)
  - return value: `rax`
  - stack: 16-byte aligned at call boundaries
- **Windows x64 (Win64 ABI)** (PE32+):
  - integer args in registers: `rcx, rdx, r8, r9` (4 regs)
  - return value: `rax`
  - caller must reserve **32 bytes of shadow space** for every call
  - stack: 16-byte aligned at call boundaries

### Supported Features

- **Executable Formats**:
  - **macOS**: Mach-O 64-bit, PIE. Supports dynamic linking with `libSystem` (FFI) via `LC_DYLD_INFO_ONLY` binding opcodes and GOT stubs. The CLI signs the finished binary with your Developer ID by default.
  - **Linux**: ELF 64-bit (`ET_EXEC`) with **two PT_LOAD segments** (W^X):
    - RX: headers + code
    - RW: data blob (mutable globals like call-depth counters, plus string literals / fnobjs / symtab)

    Rolling dynamic-link status:
    - **x64-linux:** when `--link` is used, the ELF emitter produces a dynamically-linked executable with `PT_INTERP` + `PT_DYNAMIC` and a minimal `DT_NEEDED` + `.rela.dyn` relocation set (enough to support `ffi` via a `dlsym` resolver).
    - **arm64-linux:** when `--link` is used, the ELF emitter produces a dynamically-linked executable with `PT_INTERP` + `PT_DYNAMIC` and a minimal `DT_NEEDED` + `.rela.dyn` relocation set (enough to support `ffi` via a `dlsym` resolver).
  - **Windows (x86_64 bring-up)**: PE32+ with a minimal import table for `kernel32` and a **3-section layout**:
    - `.text` (RX) code
    - `.rdata` (R) import table / constant metadata
    - `.data` (RW) user data blob (mutable globals, string literals, fnobjs, symtab)
    - **FFI (x64-windows, rolling):** `ffi name` is implemented via lazy `LoadLibraryA`/`GetProcAddress` stubs.
      - `--link <dll>` adds DLL names/paths to the resolver search list.
      - `kernel32.dll` is searched by default (so simple WinAPI `ffi` can work without `--link`).

- **Language Features**:
  - **Control Flow**: `if/else`, `while`, `Block`, `Return`.
  - **Functions**: Definitions, direct calls, and first-class function values (callable pointers) with indirect calls (rolling; x86_64 bring-up). Stack frames (`FP`/`LR` on arm64; `RBP` on x86_64). Entry trampolines align the stack for ABI-correct calls and terminate via syscall (Linux) or imported `ExitProcess` (Windows).
  - **Variables**: Local (stack-allocated) with block-scoped cleanup to prevent loop leaks.
  - **Structs**: Constructors generate `Map` objects (Duck Typing). Access via `obj.field`. Nested struct offsets are honoured in native layout.
  - **Lists / Maps (Tier‑1; runtime-defined semantics)**:
    - Both arm64 and x86_64 lower container ops to the **shared injected native runtime** (same source bundle).
    - List and map literals lower through runtime helpers (`oren_new_list` + `oren_list_push`, `oren_new_map` + `oren_map_set_*`) so container semantics do not diverge between architectures.
    - Indexing is polymorphic: `xs[i]` / `m[k]` dispatches based on **tracked allocation metadata** (see `docs/BACKEND_ARCHITECTURE.md#native-runtime-layout`).
  - **Modules**: `import` loads code (merged).

- **Memory & Concurrency**:
  - **Allocation**: Bump-pointer heap with on-demand growth:
    - arm64: `X28` = heap_ptr, `X27` = heap_limit
    - x86_64: `R15` = heap_ptr, `R14` = heap_limit
    Stack slots in inner blocks are released automatically to keep frames bounded across loops.
  - **GC**: Conservative mark/sweep GC lives in the injected native runtime:
    - default (non-capsule): `lib/runtime_native.oren`
    - capsule builds: `lib/runtime_native_capsule.oren`
    (both expanded from smaller parts under `lib/runtime_native/*.oren`) and can be triggered manually via `native_gc_collect()`.
  - **Access**: `ptr_get`, `ptr_set`, `ptr_get_byte`, `ptr_set_byte`.
  - **Lists**: `oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` (list-aware), plus array literal lowering in codegen.
- **Atomics**: `atomic_add` (LDADD), `atomic_cas` (CAS).
- **SIMD**: 128-bit NEON intrinsics (`simd_add_2d`, `mul_4s`, etc.).
- **Spawn/Join (Tier‑1; OS-specific substrate)**:
  - **macOS + Linux (POSIX)**: `spawn` is currently implemented as **fork + pipe** (process-based) and `oren_join` reads the returned value from the pipe and reaps the child via `wait4`.
  - **Windows x86_64**: `spawn` is lowered to `CreateThread` by the x64 backend; `oren_join(_timeout)` waits via `WaitForSingleObject` (see `lib/runtime_native/120_first_class_fn.oren` + `lib/runtime_native/260_threads.oren`).
  - This is a deliberate syscall-first compatibility choice to avoid depending on unstable host threading ABIs until a robust OS-thread + GC safepoint design lands.

- **Runtime**:
  - **ARM64**: automatically injects the native runtime entry file (expanded from `lib/runtime_native/*.oren` via `// @include "..."`) which implements `String` comparison and `Map` logic.
  - **x86_64 (Tier‑1; rolling)**: injects the **same native runtime source bundle** by default (matching arm64), and keeps only a small set of true “bootstrap intrinsics” in the backend:
    - bump allocator state (`malloc`/`malloc_raw`) and raw memory ops (`ptr_get`/`ptr_set` + byte variants),
    - syscall/WinAPI ABI surfaces needed for entry + IO + capsule gating.
    - Tier‑1 rule: x86_64 always injects the shared native runtime bundle (no bring-up toggle).
- Startup order (Tier-1): entry stub -> `native_runtime_init` -> `__top_level__` (user global init + top-level stmts) -> `main` (optional).
  - Runtime globals are allocated as zero and are owned/initialized by `native_runtime_init`; runtime `var` initializers are not executed in `__top_level__`.
  - Compiler guardrail: constant-like runtime globals with non-zero initializers must be assigned in `native_runtime_init` (so x64/arm64 do not drift by init-order accidents).
- Includes `oren_readdir(path)` built on syscall-first `sys_getdirentries64`.
- `oren_net_get(url)` is implemented on native (full runtime profile) as a minimal HTTP/1.0 GET over syscall-first TCP:
  - supported form: `http://<ipv4>[:port][/path]`
  - no TLS/HTTPS, no DNS, no chunked decoding (v0).
  - Rolling guidance: prefer `std:net/http.get(url)` (imports `std:net/*` and thus selects the full runtime profile automatically).

### Syscall Notes (macOS arm64)

- The native backend emits syscalls as **inline `svc`** instructions (Darwin arm64 uses `X16` as the syscall register) and does **not** call libc’s `syscall(2)` wrapper.
- Syscall numbers are taken from Darwin/XNU references (see `docs/refs/darwin_xnu_syscalls.master`).
- Repo-owned ABI constants (syscalls + offsets) live in `lib/compiler/arm64_abi_macos.oren` (see `docs/refs/darwin_arm64_abi.md`).
- `sys_stat(path, st_ptr)` uses **`stat64` (macOS)** / **`newfstatat` (Linux)** into a private host `struct stat` buffer, then translates into an **Oren-owned stable layout** (OrenStatV0) at `st_ptr` (no host `struct stat` layout exposed to user code).
- `sys_lstat(path, st_ptr)` uses **`lstat64` (macOS)** / **`newfstatat(..., AT_SYMLINK_NOFOLLOW)` (Linux)** into a private host buffer, then translates into OrenStatV0.
- `sys_fstat(fd, st_ptr)` uses **`fstat64` (macOS)** / **`fstat` (Linux)** into a private host buffer, then translates into OrenStatV0.
- `sys_getdirentries64(fd, buf, bufsize, pos_ptr)` on macOS uses **`getdirentries64` (syscall 344)**; on Linux it maps to `getdents64` (61) and ignores `pos_ptr` (v0).
### Notes / Limitations
- **String concatenation:** on the native backend, `+` lowers to the runtime helper `oren_add` and supports:
  - integer addition
  - string concatenation when *both* operands are strings (content-based), matching native `strcmp` semantics for comparisons.

  Rolling guidance:
  - Prefer `+` everywhere.
  - `string_concat(a, b)` exists as a low-level native runtime helper but is treated as an internal primitive; the repo’s curated tests and audits intentionally avoid using it in higher-level code.
- **Linux FFI/linking (rolling):**
  - **x64-linux:** `--link` enables dynamic linking; `ffi` is implemented via a lazy `dlsym(RTLD_DEFAULT, "...")` resolver (the ELF emitter emits `DT_NEEDED` and relocates a small GOT slot for `dlsym`).
  - **arm64-linux:** `--link` enables dynamic linking; `ffi` is implemented via a lazy `dlsym(RTLD_DEFAULT, "...")` resolver (the ELF emitter emits `DT_NEEDED` and relocates a small GOT slot for `dlsym`).
- **Windows FFI/linking:** no general user import-table mapping yet; `ffi` uses lazy runtime resolution (LoadLibrary/GetProcAddress) instead.
- **W^X (Linux):**
  - Linux ELF uses **separate PT_LOAD segments**: RX (headers+code) + RW (data blob). No RWX pages.
  - Windows PE now uses a **3-section layout**: `.text` (RX) + `.rdata` (R) + `.data` (RW). Mutable globals
    (e.g. call depth counters) live in `.data`.

### CLI Usage
```bash
make verify # Run full self-hosting test
./oren build file.oren --backend native -o out
./oren build file.oren --backend native -o out --target linux
./oren build file.oren --backend native --disasm
./oren build file.oren --backend native --no-debug # Disable stack-trace debug info (or: OREN_NATIVE_NO_DEBUG=1)
./oren build file.oren --analyze # Static analysis
```

### New Features (Dec 2025)

- **Shared Libraries**: Build `.dylib` (macOS) using `--lib`. Exports defined functions.
  ```bash
  ./oren build mylib.oren --backend native --lib -o mylib.dylib
  ```
  Notes (rolling):
  - This is implemented for:
    - **arm64-macos (Mach-O)**: `.dylib`
    - **x64-linux (ELF)**: `.so` (ET_DYN + `.init_array` + metadata/header)
    - **x64-windows (PE)**: `.dll` (native DllMain entrypoint + export table + generated C header)
    - **arm64-linux (ELF)**: `.so` (ET_DYN + `.init_array` + metadata/header; no section header)
  - Linux notes:
    - **x64-linux `.so`** uses `.init_array` to run the compiled entry stub at load time (runtime init + `__top_level__`), and uses RELA `R_X86_64_RELATIVE` relocations for internal function pointers embedded in `.data`.
    - **Linux executables** (arm64-linux + x64-linux) can export selected symbols for callback interop via `@ffi.export` (see `docs/ATTRIBUTES.md`).
  - **Windows x64 executables** can also export selected symbols via `@ffi.export` (PE Export Directory) so `GetProcAddress(GetModuleHandle(NULL), ...)` can locate callback entry points.
  - ABI note (x64 native): exported symbols are routed through small wrappers that preserve the platform ABI’s non-volatile registers while still allowing Oren’s internal heap registers to remain persistent.
- **Linking**: Link external dynamic libraries using `--link <lib>` or `-l <lib>`.
  ```bash
  ./oren build app.oren --backend native --link /usr/lib/libsqlite3.dylib
  ```
- **API Scanning**: Generate API docs from C libraries.
  ```bash
  ./oren scan /usr/lib/libSystem.B.dylib
  ```
  Notes (rolling):
  - `oren scan` prefers parsing an adjacent generated header when scanning an **Oren-produced** native `--lib` artifact.
    - Example: `build/libmath.dylib` → `build/libmath.h`
    - This keeps `scan` useful cross-platform even when the host `nm` cannot read foreign formats (PE/ELF on macOS) or when the shared object is stripped.
  - When parsing an Oren-generated header, `scan` prints a signature column derived from the C prototype (no address info).

### Internal Architecture
- **Single-Pass Compilation**: Code is emitted sequentially.
- **Fixups**: Forward jumps (Branches) and Data references (ADR) are patched after emission.
- **rtobj cache note (Tier‑1 x86_64):** the runtime-object cache splices precompiled runtime machine code into the final program. The cached runtime may include fixups to compiler-emitted helper symbols (e.g. `__oren_panic_helper`), so the program compile must carry forward any “helper needed” state when applying rtobj (otherwise small programs can fail at emit/patch time even though the runtime cache hit succeeded).
- **Stack Machine**: Expression evaluation pushes operands to stack, operations pop them into registers.
- **Register Usage**:
  - `X0-X7`: Arguments / Scratch.
  - `X16`: Syscall scratch (macOS).
  - `X28`: Heap Pointer (Global).
  - `X27`: Heap Limit (Global).
  - `FP (X29)`, `LR (X30)`, `SP`: Standard usage.

### Why some x86_64 helpers use 32-bit ops (e.g. `eax`) even though the arch is 64-bit

On x86_64, writing a 32-bit subregister (like `eax`) has two important properties:

1) **Encoding size / immediates**: many instructions have a smaller encoding for imm32 forms.
2) **Architectural behavior**: writes to a 32-bit register zero-extend into the full 64-bit register.

When Oren wants a *signed* i32 value in `rax`, a common safe sequence is:

- `mov eax, imm32` (loads 32-bit value)
- `cdqe` (sign-extend `eax` → `rax`)

This is not a type-system statement (“int is i32”), it’s an emitter optimization/detail. The language-level
`int` is still treated as a 64-bit two’s-complement value in the compiler/runtime model; the emitter just
chooses compact encodings when they are provably correct.

## Native Runtime Layout

The native backend injects a “runtime” into every native build. Historically this lived in one large file.
In rolling mode we keep it **split into small modules** to avoid review/context overflow.

### Where to edit

- Include-root (default, non-capsule): `lib/runtime_native.oren`
  - For capsule builds, the runtime entry file is `lib/runtime_native_capsule.oren`.
  - This file is intentionally tiny.
  - It contains a list of `// @include "runtime_native/NNN_name.oren"` directives.
- Real implementation: `lib/runtime_native/*.oren`
  - Each file is a cohesive “slice” (time, tcp, byte order, capsule hooks, etc).

The compiler expands `// @include` directives at compile time, so the injected runtime behaves like a single
translation unit, but stays maintainable in source form.

### Why this avoids context overflow

- Each chunk stays small (hundreds of lines, not thousands).
- You can review/edit one subsystem at a time without loading the entire runtime.
- Repo audits should enforce include-chunk coherence so we don’t accidentally regress back into a monolith.

### How to add a new runtime module

1) Create a new chunk file under `lib/runtime_native/`:
   - Use a numeric prefix to keep ordering obvious (e.g. `270_crypto.oren`).
   - Keep it focused; if a chunk grows too large, split it again.
2) Add a corresponding include line to the appropriate runtime entry file:
   - default (non-capsule): `lib/runtime_native.oren`
   - capsule builds: `lib/runtime_native_capsule.oren`
3) Run `make test-native-all` (or at least `make test-native-quick`) to ensure include expansion and runtime behavior stay green.

### Early-init guardrails (must stay robust cross‑OS)

The native runtime runs during **program entry** before any user code. In rolling mode, assume:

- global initializers may not reliably run before `native_runtime_init`
- some “fast path” intrinsics may temporarily be buggy on new targets

Hard rule: early-init code must not segfault just because a raw allocator returns garbage.

Implementation guardrail:

- `lib/runtime_native/015_raw_alloc.oren` defines `native_malloc_raw_or_mmap(size)`.
  - It validates the native-backend `malloc_raw` intrinsic result.
  - If invalid, it falls back to `sys_mmap_private_anon`.
  - `native_runtime_init` and envp construction use this helper so `scripts/verify_native_matrix.sh --targets arm64-linux`
    can compile+run artifacts in the Linux container reliably.

### Oren-owned stable ABIs (recommended)

Some low-level “syscall-first” APIs expose raw buffers for performance. In rolling mode we prefer an
**Oren-owned stable layout** rather than mirroring host C structs, so tests and libraries remain
OS/arch neutral.

Current example:

- **OrenStatV0** (used by `sys_stat/sys_lstat/sys_fstat`):
  - Compiler-side layout source: `lib/compiler/native_stat_abi.oren`
  - Runtime-side helpers: `lib/runtime_native/215_stat.oren`

### Notes / Footguns

- Prefer modern surface syntax in higher-level helpers:
  - string concatenation: use `+` rather than `string_concat(...)` chains
  - list operations: use container method sugar where possible
- Do not edit generated `.c` artifacts (they are build outputs / debug aids).

### Embedded string literals (constant pool)

Native-backend string literals are intentionally treated as **static data**, not GC heap objects:

- The code generator de-duplicates string-literal bytes into a `cstr0` pool in the appended data blob.
- The program entry stub calls `oren_init_static_cstr0_table(table_ptr)` once at startup to build a dedicated
  **literal membership set** (pointer hash set) for the embedded `cstr0` pool.
  - `oren_find_node(lit_ptr)` returns `0` for string literals (they are not tracked alloc nodes).
  - Runtime classification uses `native_is_string_ptr(ptr)` / `oren_is_string(ptr)` which recognize:
    - tracked heap strings (`kind=1`), and
    - embedded `cstr0` literal pointers (via the membership set).
- Because literals are not tracked heap allocations, GC conservative scans do not “see” them as heap nodes and do not
  spend mark work on them.

The quick native integration fixture asserts these properties:
- `tests/native/test_quick_integration_native.oren` (`test_string_literals_static`).

## Native Tagged Value Representation

This document is **design guidance** for converging the **native backend** (arm64 + x86_64) onto a production‑grade **tagged value** model that is consistent with:

- the **C backend** value model (`lib/runtime.h`: `OrenValue { type, union }`)
- the **AVM** value model (tagged value types + tagged constants; see `docs/AVM_SPEC.md`)
- the language semantics in `docs/LANGUAGE_SPEC.md` (type‑strict equality, `nil` distinct from `false`, etc.)

### 0) Why this is urgent (current mismatch)

#### Current state by backend

1) **C backend** (today): values are structurally tagged
   - `lib/runtime.h` defines `OrenValue` as `{ OrenType type; union {...} }`.
   - This can represent `nil`, `bool`, `int`, `float`, `string`, list/map/function, typed buffers, etc.

2) **AVM** (today): values are tagged (VM tag + payload)
   - The VM needs a tag for determinism and serialization.

3) **Native backend** (today):
   - values are still mostly treated as **untagged `i64` carriers** in registers/stack.
   - rolling mitigation already landed for the most dangerous falsey collisions:
     - `nil`, `false`, and `true` are represented as **runtime singleton values** (distinct non-zero pointers stored in the runtime globals storage).
   - heap objects (lists/maps) are recognized via **magic words** at fixed offsets (e.g. `'LIST'`, `'MAP\0'` in x64 bring‑up).
   - **Rolling status (arm64 + x86_64):** maps still need to distinguish key kinds (`int` vs `string`) because the native runtime stores a `key_kind` per entry.
     - Current interim strategy avoids “magic numeric range” semantics by using **tracked-allocation metadata**:
       - string keys are tracked heap strings (`oren_track_alloc(..., kind=STRING)`),
       - dynamic `oren_map_get(m, key)` can consult `oren_find_node(key)` to detect `STRING` vs “untracked” (treat as `int`).
     - Rolling update: the numeric-range map key heuristic has been removed; key-kind inference now relies on tracked-allocation metadata only (deterministic, semantics-safe).
     - The compiler still performs best-effort key-kind inference from syntax and local assignments so hot code can avoid runtime dispatch where possible.
     - This remains a stopgap until the native backend adopts an explicit tagged value representation where the key kind is carried in the value itself.

#### Why a tagged representation is required

The language semantics require:

- `nil` distinct from `false`
- type‑strict `==` / `!=` (e.g. `1 == 1.0` is false)
- maps where keys can be `int` or `string` (and eventually other types) without “magic numeric ranges”
- predictable serialization and determinism (AVM + replay)

So the native backend must not depend on “is it < 4096?” or “does it look like a pointer?”.
Even “compiler-inferred key kind” is only a stopgap — production requires a principled tagged value model.

**Concrete semantic hazards observed in rolling (native backend):**

- The native backend is not yet a fully tagged value machine.
  - Some numeric immediates (notably `int` vs `float`) can still be indistinguishable in native-mode reflection paths (`oren_type_tag` is best-effort there).
- Even with singleton `nil/false/true`, a raw “i64 carrier” model can still collide if user code intentionally constructs scalars equal to those singleton addresses (e.g. via unsafe pointer/FFI surfaces).
  - This is one reason full tagged values remain a hard requirement for production semantics and security hardening.

### 1) Design goals (production constraints)

Non‑negotiable goals:

1) **Cross‑backend semantic convergence**
   - a program’s results must match across native / C / AVM (modulo performance).

2) **Determinism**
   - representation must not depend on host allocator pointer patterns.

3) **Performance on 64‑bit CPUs**
   - values should stay “register‑friendly” for hot loops and syscall‑first servers.

4) **Staged rollout**
   - rolling mode allows refactors, but we must avoid “big bang” changes that stall progress.

### 2) Representation options (with tradeoffs)

#### Option A — Box everything (pointer to heap object with an explicit type tag)

**Idea:**
- Every value is a pointer to a heap object with a header `{tag, payload...}`.

**Pros:**
- simplest semantics
- no bit‑level tricks; full range for ints/floats

**Cons:**
- too slow / too GC‑heavy for HPC + server hot paths
- complicates FFI and syscall boundaries

This is not recommended as the long‑term default.

#### Option B — Low‑bit pointer tagging (immediates + heap pointers)

**Idea:**
- Represent some values as immediates (e.g. `nil`, `bool`, small `int`) using a tag in low bits.
- Represent heap objects as aligned pointers.

**Pros:**
- common systems‑VM technique; fast branches for small ints / bool / nil
- keeps heap objects as pointers (good for lists/maps/strings/bufs)

**Cons:**
- “small int” immediate cannot represent all `i64` values if low bits are used for tags.
  - therefore large ints require boxing (or a separate representation rule)
- requires **all strings to be heap objects** (string literals cannot be raw `char*` without a header/type)

This is a strong candidate if we accept “small int immediate + boxed big int” as the dynamic `int` runtime model.

#### Option C — NaN-boxing (float + non-float values share one 64-bit word)

**Idea:**
- Use IEEE‑754 `f64` bit patterns:
  - non‑NaN values represent floats
  - a chosen NaN range encodes `nil/bool/int/pointer` payloads

**Pros:**
- efficient `float` path (no boxing for floats)

**Cons:**
- highest implementation complexity
- requires careful, explicit decisions about NaN payload canonicalization for determinism
- requires precise documentation and cross‑backend conversion rules

This is viable for a production VM, but should be staged in after a simpler “pointer tagging + boxed float” path if needed.

### 3) Recommended staged plan (rolling)

#### Phase 1 — Remove “heuristics” by introducing explicit key tagging

Goal: remove remaining map key-kind inference stopgaps and make key type checks explicit.

Minimal work required:

1) **Strings become heap objects** in native mode (including literals)
   - string values must carry a type identity (`STRING`) that is not “pointer range dependent”.
   - string comparisons and `len/slice` can then dispatch by type.

2) **Map entries store a typed key representation**
   - use a canonical key tag (`INT`, `STRING`, later `BOOL/NIL`, etc.)
   - do not infer key type from the numeric value.

This phase can be implemented without committing to a final universal 64‑bit value layout, as long as maps can reliably distinguish key types.

#### Phase 2 — Converge native values to a canonical tagged model

Goal: a single value model for native backend codegen that matches language semantics:

- `nil`, `bool`, `int`, `float`, heap/object, function, typed buffers.

Recommended direction:

- adopt **pointer tagging** for `nil/bool/small-int` + heap pointers
- box “big int” values outside the small‑int range
- initially box floats (or treat floats as a separate heap object), then consider NaN‑boxing later if float perf becomes a bottleneck

#### Phase 3 — Align C backend + AVM conversions explicitly

Goal: deterministic conversions between:

- C backend `OrenValue` (struct tagged)
- AVM `AvmValue` (VM tagged)
- native backend “word” (tagged/boxed)

This requires:

- a canonical set of runtime tags (shared enum in docs + tooling)
- explicit boundary conversion helpers

### 4) Immediate next engineering tasks (what to implement next)

1) Decide and document a **canonical runtime tag set** for: `nil/bool/int/float/string/list/map/func/buf`.
2) Define the native string object layout (header + length + bytes pointer / inline bytes policy).
3) Replace runtime key-kind inference with explicit tagging:
   - store key tag in each entry
   - compare keys by `(tag, value)` not by “value range”
4) Add fixtures:
   - map key cases that currently break the heuristic (e.g. integer key `50000`)
   - `nil` vs `false` equality semantics (native must match C/AVM)

### 5) Notes on correctness vs performance

- For production server workloads, **correctness + determinism** are non‑negotiable.
- Performance can be recovered incrementally:
  - inline fast paths for small ints
  - typed buffers for HPC avoid dynamic boxing entirely

## Native Backend Code Reuse Plan

Goal: treat **arm64** and **x86_64** as Tier-1 native targets while maximizing code reuse and keeping ABI correctness provable via fixtures.

This repo already has:

- A C backend that is architecture-neutral by construction (the host C compiler owns the ISA details).
- A native backend that emits machine code directly (arm64 is feature-rich; x86_64 is being brought up with fixtures).

To make native backends scale (and avoid duplicating semantics between arm64/x64), we need a shared structure:

### 1) Split responsibilities into three layers

#### Layer A — Frontend lowering (shared)

Input: typed/linked AST.

Output: an architecture-neutral **NativeIR** (not bytecode; it stays close to “machine-like” ops).

Examples of NativeIR ops:

- `LoadLocal(slot)` / `StoreLocal(slot)`
- `ConstI32(n)`
- `AddI32`, `SubI32`, `MulI32`, `CmpI32(op)`
- `Jump(label)` / `JumpIfFalse(label)` / `Label(label)`
- `CallSym(name, argc)` (later: `CallIndirect`, closures)
- `Return`
- Runtime ops as explicit calls (`CallRuntime("oren_list_push", ...)`)

Key property: NativeIR encodes **semantics** (evaluation order, short-circuit rules, loop semantics), so backend authors don’t re-encode language rules per ISA.

Rolling implementation status (today):

- We are introducing the “shared frontend” incrementally.
- The first shared native-facing piece is a CoreIR scaffold:
  - `lib/compiler/coreir.oren` (top-level function list + arity/varargs metadata)
  - consumed by the x86_64 backend prepass (Tier‑1 bring-up)
- Next: expand the shared IR boundary to include call canonicalization and container ops so arm64 and x86_64 stop diverging as new features land.

#### Layer B — ABI description (per target, shared interface)

Define a `NativeABI` interface with data tables + helpers:

- Register order for integer args
  - Linux x86_64 SysV: `edi, esi, edx, ecx, r8d, r9d` (ints)
  - Windows x64: `ecx, edx, r8d, r9d` + 32B shadow space
  - AArch64 (AAPCS64): `w0..w7` (ints)
- Stack alignment rules and prologue/epilogue requirements
- Caller/callee-saved registers
- Where return values live (typically `eax` / `w0`)

Codegen asks the ABI layer “where does arg i go?” instead of hardcoding per file.

#### Layer C — Instruction selection + encoding (per ISA)

Take NativeIR + ABI and emit machine code:

- x86_64: use `lib/compiler/x64_core.oren` encoders + fixups
- arm64: use `lib/compiler/arm64_core.oren` encoders + fixups

This is where register allocation lives (even a simple stack-machine allocator can be shared at the IR level).

### 2) Win64 has 4 int arg registers (not a language limitation)

Oren supports **first-class functions** and **varargs** (`fn f(...rest)` + `f(xs...)`) at the language level.

The *native backend* still must map those semantics to platform ABIs:

- **Linux x86_64 SysV**: 6 integer arg registers (`rdi, rsi, rdx, rcx, r8, r9`)
- **Windows x64 (Win64 ABI)**: 4 integer arg registers (`rcx, rdx, r8, r9`) + mandatory 32B shadow space

So the “4 args” constraint is a *cross-target bring-up constraint* (Win64 is the smallest Tier‑1 integer-reg arg set), not something “special” about Oren or varargs.

For a future-proof design, varargs/closures/indirect calls should be implemented via a **uniform callable ABI** (typically `args_list` based, plus `env_ptr` for closures) so higher-level features do not depend on the fixed-arg register limit of any single OS ABI.

### 3) Near-term work items

1. Introduce `lib/compiler/native_abi.oren` interface + per-target implementations:
   - `lib/compiler/native_abi_x64_sysv.oren`
   - `lib/compiler/native_abi_x64_win64.oren`
   - `lib/compiler/native_abi_arm64_aapcs.oren`
2. Move current x64 ABI hardcoding to those tables (arg regs, shadow space, alignment).
3. Start extracting common lowering logic (statements/expressions) into a shared pass producing NativeIR, then hook it up to arm64 and x64 emitters.
4. Add fixtures that validate ABI-sensitive behavior (multi-arg, nested calls, spill correctness, alignment-sensitive calls).

## Native Backend Guardrails

This document is a short “do not regress” checklist for Oren’s **native backend** and **native runtime**.
It is intentionally practical:

- each item states the invariant (what must stay true),
- why it exists (failure mode),
- and the regression gate that should catch it.

If you change an invariant, update this file *and* the gate.

### How to verify quickly

- Local fast gate (arm64-macos): `make test`
- Local + container (no remote required): `make verify-native-net-skip-remote`
- Cross-target buildability (no remote required): `make verify-native-x64-compile`
- Local x64-linux runtime (no remote required): `make verify-x64-linux-qemu`
- Full Tier‑1 matrix (requires remote Win11/WSL2): `make verify-tier1`

### 1) Never call string ops on untagged non-strings

Invariant:

- Native values are not fully tagged yet. Runtime helpers must not call `strcmp` / string scanning on a value
  unless it is proven to be a valid string pointer.

Why:

- On native backends, integers can look like pointers (and vice versa). Calling `strcmp` on an integer value
  can segfault or run off into unmapped memory.

Rule of thumb:

- Use `oren_is_string(v)` (backed by `native_is_string_ptr`) before `strcmp`.

Regression:

- `make test` (native quick integration exercises iterable-map protocol tags and other map/string flows).

### 2) Iterable-map protocol tags must be byte-matched (not pointer-identity)

Invariant:

- The iterable-map protocol uses a marker key `__iter` and a tag string such as `"range"` / `"list_slice"`.
- The runtime must treat tags as strings **by bytes**, guarded by `oren_is_string(__iter)`.
- Literal pointer equality may be used as a fast path, but must not be required for correctness.

Why:

- Depending on build caches/rtobj merges/linking, “equal string” values can be represented by different pointers.
- A user can also construct an equal heap string (`"ra"+"nge"`) that is not pointer-equal to the literal `"range"`.

Regression:

- `make test` includes a regression where `{"__iter": "ra"+"nge", ...}` must iterate correctly.

### 3) Embedded string literals are constant-section data, not GC allocations

Invariant:

- String literals in native output are emitted into a single `cstr0` pool in the binary’s data segment.
- They must not be tracked as GC allocations (no alloc nodes).
- The runtime builds a **literal membership set** at entry (`oren_init_static_cstr0_table`) so `oren_is_string`
  can recognize literal pointers safely.
- Even if compiler/codegen mistakenly attempts to track a literal, the runtime must treat it as a no-op:
  - `oren_track_alloc(lit, ..., kind=STRING)` must not create a node.
  - `oren_track_static(lit, kind=STRING)` must not create a node.

Why:

- Tracking literals as alloc nodes makes GC work explode in compiler workloads (many literal keys in maps).
- Allocating tracking metadata per literal is a startup hotspot for large binaries.

Regression:

- `make test`
- `make verify-native-net-skip-remote` (stresses compiler runtime + NET/TLS loops)

### 4) Alloc-index internals must avoid `==`/`!=` pointer comparisons

Invariant:

- The alloc-index (`oren_find_node` / `native_alloc_index_get`) must not use `==/!=` between non-constant values
  when those operators can lower to string-aware comparisons.
- Prefer arithmetic compares (`(a - b) == 0`) for pointer identity checks.

Why:

- If a string-aware compare re-enters the alloc-index, it can recurse and crash during early init.

Regression:

- `make test` (compiler workloads drive alloc-index usage)

### 5) Windows bring-up: stage0 + stage1/2 C backend should prefer MSVC `cl.exe`

Invariant:

- On Windows hosts, the default C toolchain for stage0->stage1 bring-up is **MSVC `cl.exe`**.
- Toolchain setup is auto-configured via `vswhere.exe` → `VsDevCmd.bat` / `vcvars64.bat` when `--cc cl` is selected.
- Do not default to `cl.exe` when *cross-compiling* Windows from non-Windows hosts; require explicit `--cc`.

Why:

- Tier‑1 Windows users should be able to build without MSYS2/MinGW assumptions.
- Cross-compiling Windows C outputs from macOS/Linux is a separate (explicit) path.

Regression:

- Remote: `make verify-stage0-win` and `make verify-stage2-win` (requires reachable Win11 host).

### 6) Keep scripts bounded and log output small

Invariant:

- CI/rolling development must not hang indefinitely:
  - per-build and per-test timeouts are enforced,
  - scripts print bounded tails/snippets (avoid dumping megabytes).
  - macOS: scripts may use a bash-native watchdog instead of GNU coreutils `timeout` if the host `timeout` is unstable.

Why:

- The fastest way to lose velocity is “hung build with no signal”.

Regression:

- `make test` should stay fast by default (and the scripts should always have bounded output).

### 7) x64-windows: validate exports via PE Export Directory (not string search)

Invariant:

- When the native backend is expected to export symbols on **x64-windows** (both):
  - `--lib` outputs (`.dll` exports like `add`, `mul`), and
  - `@ffi.export` callback-style exports on `.exe`,
  the symbol names must appear in the **PE Export Directory**.

Why:

- A byte/string search is not proof of export correctness:
  - the name could appear in debug strings, metadata, or pooled literals,
  - while the export table is missing or malformed.
- Real consumers (`GetProcAddress`) consult the export table, not random bytes.

Regression:

- `make verify-native-x64-compile` (compile-only gate)
  - Uses `scripts/pe_exports_check.py` to parse the PE export directory (no external deps).
- `make examples-cross-compile-smoke` (compile-only `--lib` API sanity)

### 8) x64-linux: shared library + FFI resolution must run under QEMU

Invariant:

- On **x64-linux**, the native backend must be able to:
  - emit a shared library via `--lib` (`.so`), and
  - emit an executable that links/resolves symbols from that `.so` via `--link`,
  and the result must run correctly (not just compile).

Why:

- “Compile-only” checks miss runtime/linker/FFI resolution failures (e.g. missing export table, wrong resolver behavior, wrong calling convention).
- This is a high-signal parity gate for the x64 backend without requiring a remote WSL2 host.

Regression:

- `make verify-x64-linux-qemu` runs `examples/libmath.oren --lib` + `examples/ffi_from_libmath.oren` under `qemu-x86_64` in the persistent Linux container.

### 9) FFI bindings must remain module-exportable (internal name ≠ external symbol)

Invariant:

- A module may declare `ffi foo`, and callers may access it as a module member:
  - `import m "std:ffi/libc"` then `m.strlen("oren")`
- Module namespacing/prefixing may rewrite the **internal** function label (e.g. `STD_ffi_libc_strlen`),
  but the **external** symbol name used for loader lookup must remain the source identifier (`strlen`).

Why:

- Without this split, module prefixing breaks FFI (call sites reference the prefixed label, but the resolver/binder searches for the prefixed external symbol which does not exist).
- Stdlib needs this to hide `@cfg` + `@ffi.link/@ffi.dll` boilerplate behind a stable API surface.

Regression:

- `scripts/verify_native_matrix.sh` executes `tests/native/test_std_ffi_libc_smoke.oren` on Tier‑1 targets (stage1 + stage2).
- `make verify-x64-linux-qemu` also builds/runs the same fixture under `qemu-x86_64` (local, no remote required).

### 10) Debug-info symbolication must never crash (debug builds)

Invariant:

- Debug-info tables and symbol resolvers (`oren_set_debug_info`, `oren_resolve_symbol`) are **best-effort diagnostics**.
- Malformed/corrupted tables must not crash the process (bail out / return `"???"`), even in debug mode.

Why:

- Many Tier‑1 smokes compile with `--debug` (including `make test`), so a debug-info parsing crash blocks iteration.
- Diagnostics must not turn a recoverable bug into a hard segfault.

Regression:

- `make test` (native quick integration is built with `--debug` and installs debug info at entry)

### 11) Green ctx-switch must preserve long-lived locals across yields

Invariant:

- A local pointer kept live across many `oren_green_yield()` points must remain valid and stable.

Why:

- If ctx-switch lowering or backend stack/register discipline is wrong, locals can collapse to small/misaligned integers
  and later crash in `ptr_get`/`ptr_set`.

Regression:

- `make test` via `tests/native/test_quick_integration_native.oren`:
  - `test_green_local_ptr_survives_yields`
  - `test_green_workers_local_ptr_survives_yields`

### 12) Stop emitting statements after terminators in blocks (stack accounting)

Invariant:

- In native backend statement codegen, a `Block` must stop emitting code after a direct terminator statement:
  - `break`, `continue`, `return`

Why:

- The native backends use a rolling SP-relative stack model (`ctx["stack_size"]`) for **temporaries** and dynamic
  spill areas.
- On arm64, **locals** are FP-relative (X29) for stability, but stack accounting can still be perturbed by emitting
  unreachable code after terminators (SP-relative temporaries still exist and must be balanced on fallthrough paths).

Regression:

- `make test` (native quick integration exercises loops + break/continue patterns in stdlib/runtime code)

## Native Backend Performance Playbook

This document is a **practical guardrail** for keeping Oren’s **self-hosted stage2 native compiler** fast and diagnosable.

It is written for “I changed something and now `oren build` took >10s” incidents.

### 1) Non-negotiable performance gates (primary dev host)

These are rolling “red line” bounds used to catch fundamental regressions early:

- **Stage2 native backend: compile-one-file (rtobj hit)** must stay **< 4s** wall time.
  - Measured with: `./scripts/bench_native_compile_one_file.sh` (second run is the hit).
  - Regression tripwire (recommended): `./scripts/perf_guard_native_compile_one_file_hit.sh`
- **Tier‑1 debug builds** used by fixtures should stay **< 10s** per `oren build ... --backend native --debug` step.
  - Default bounded timeout is enforced by the verification scripts (`OREN_NATIVE_BUILD_TIMEOUT_SECS`, default `10`).
- **Self-host compiler build** (`make stage2` / `make verify`) must stay **< 3 minutes** wall time on the primary dev host.

If any of these regress, treat it as a **fundamental hot-path flaw**, not something to “tune with flags”.

### 2) First response: reproduce with bounded tools

Use these first because they are bounded and don’t produce huge logs.

#### 2.1 Quick throughput check: compile one file (miss → hit)

```bash
## Uses an isolated runtime-object cache dir so you see a miss then a hit.
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 ./scripts/bench_native_compile_one_file.sh --no-debug
```

Note:

- The benchmark script disables the rtobj “seed” fallback (`OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0`) so it measures a true miss → hit.
  - For real user experience, it is recommended to keep a seed available (see `make rtobj-seed`).
    - Rolling note: `make rtobj-seed` defaults to the compiler’s “auto” profile, which seeds the **core** runtime entry (`lib/runtime_native_core.oren`) unless you explicitly set `OREN_NATIVE_RUNTIME_PROFILE=full`.
    - For NET/TLS-heavy programs, you can pre-seed the full runtime object with: `OREN_NATIVE_RUNTIME_PROFILE=full make rtobj-seed`.
  - For cross-target x86_64 sanity on arm64 hosts, generate seeds with `make rtobj-seed-x64` so compile-only gates stay bounded on a clean cache.

Optional (rolling): reduced runtime profile for bounded cold misses

If you are diagnosing the **cold miss** cost (rtobj build) and want a smaller baseline that more closely matches
“typical programs”, you can use the reduced runtime profile:

```bash
OREN_NATIVE_RUNTIME_PROFILE=core \
  OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0 \
  OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
  ./scripts/bench_native_compile_one_file.sh --no-debug
```

Note (rolling default): when `OREN_NATIVE_RUNTIME_PROFILE` is unset (or `auto`), the compiler already prefers the
core runtime for programs that do not import `std:net/*`, and escalates to the full runtime for networking programs.

Optional bounded tracing:

```bash
OREN_NATIVE_BUILD_TIMEOUT_SECS=60 \
  OREN_TRACE_RUNTIME_BUNDLE=1 \
  OREN_TRACE_RUNTIME_OS_PRUNE=1 \
  OREN_TRACE_RUNTIME_OBJ_CACHE=1 \
		  OREN_TRACE_ASTBIN=1 \
		  OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1 \
		  OREN_TRACE_X64_RT_OBJ_SUMMARY=1 \
		  ./scripts/bench_native_compile_one_file.sh --no-debug
```

#### 2.1.1 Bounded phase timing: `read_ms/parse_ms/link_ms/emit_ms`

When a build is “slow”, the first question is: **which phase is slow**?

Use the build-summary tracer (it prints a single line per build):

```bash
OREN_TRACE_BUILD_SUMMARY=1 OREN_TRACE_BUILD_SLOW_MS=0 \
  ./oren_stage2 build tests/native/test_http2_headers_loopback.oren \
  --backend native --platform arm64-macos --no-debug -o build/tmp/http2_headers
```

Interpretation (rolling):

- `read_ms`: reading the entry source + trivial scaffolding
- `parse_ms`: parsing the entry file itself (not the full module closure)
- `link_ms`: `link_program(...)` (module discovery + import scanning + module parsing + type passes)
- `emit_ms`: backend emission (native assembler/linker + artifact write)
- `codesign_ms`: macOS codesign (usually tiny unless keys/cert prompts misbehave)

If `link_ms` dominates and you are using the **native runtime** (stage2 backend), keep in mind:

- Native runtime `spawn` is fork-based today, so “parse workers” cannot return pointer-heavy ASTs.
- By default, the compiler disables fork-parallel module parsing because the ASTBIN bounce is I/O-heavy.
- For large stdlib graphs (TLS/HTTP/2/HPACK), **forcing fork-parallel parsing** is often still a net win.

Enable it explicitly:

```bash
OREN_PARSE_JOBS=8 OREN_PARSE_FORK_PARALLEL=1 \
  OREN_TRACE_BUILD_SUMMARY=1 OREN_TRACE_BUILD_SLOW_MS=0 \
  ./oren_stage2 build tests/native/test_http2_headers_loopback.oren \
  --backend native --platform arm64-macos --no-debug -o build/tmp/http2_headers
```

Notes:

- This uses `build/tmp/parse_modules/` as a deterministic temp directory for worker-produced ASTBIN blobs.
- On Windows hosts, the compiler forces parse jobs to `1` because `spawn` is thread-based and the runtime GC is not thread-safe yet for parallel parsing.

#### 2.1.2 Persistent module ASTBIN cache (cross-invocation speed)

The NET and Tier‑1 verification scripts invoke the compiler **many times** (separate processes),
often compiling overlapping stdlib graphs (TLS/HTTP/2/HPACK). Re-parsing those modules every time
is wasted work.

Stage2 now includes a **persistent module ASTBIN cache**:

- Cache is stored under `build/cache/module_astbin/<compiler_sig>/...` by default.
- It is enabled by default; disable with `OREN_MODULE_ASTBIN_CACHE=0`.
- It is keyed by module path + expanded source fingerprint + platform (so cross-target builds do not collide).
- Module prefixes are **stable per module path**, so cached ASTBIN blobs can be reused across different entrypoints.

For debugging (bounded output):

- `OREN_TRACE_MODULE_ASTBIN_CACHE=1` prints up to ~5 cache events in **non-fork** parsing mode.
- `OREN_TRACE_MODULE_ASTBIN_CACHE=workers` allows worker-side prints (use only when isolating a cache bug).

Notes on the tracers:

- `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` prints a **single-line breakdown** of the rtobj build (parse/decode, decl compile, finalize, counts/bytes).
  - Use it to decide whether to optimize astbin decode vs runtime decl compilation.
- `OREN_TRACE_X64_RT_OBJ_SUMMARY=1` provides the same style of breakdown for x86_64 (useful for cross-target misses).
- `OREN_TRACE_{ARM64,X64}_RT_OBJ_TOP_DECLS=1` prints a **bounded** “top decls” list (slowest N decls by compile time).

#### 2.2 Cross-arch sanity (native backend)

- Local + container + remote matrix:
  - `./scripts/verify_native_matrix.sh`
- Local compile-only x64 sanity (stage1 + stage2 emit):
  - `./scripts/verify_native_x64_compile_only.sh`

#### 2.2.1 Local x64-linux “run” sanity via qemu (no remote/WSL required)

When bringing up x86_64 runtime behavior from an arm64-macos dev host, you can run the emitted x64-linux ELF under qemu in the existing Ubuntu toolchain container:

```bash
## Build x64-linux ELF (host compiler is still arm64-macos).
./oren_stage2 build tests/native/print.oren \
  --backend native --platform x64-linux --no-cache --no-debug \
  -o build/tmp/print_x64_linux

## Copy + run under qemu inside the already-running toolchain container.
#
## If the container is currently stopped (Exited), restore it with:
##   docker start c7e5f7bd9f5c
docker cp build/tmp/print_x64_linux c7e5f7bd9f5c:/tmp/hostbins/
docker exec c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && chmod +x print_x64_linux && qemu-x86_64 ./print_x64_linux'
```

Debugging with gdb stub (bounded, no huge logs):

```bash
docker exec c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && qemu-x86_64 -g 1234 ./print_x64_linux'
## In another terminal:
docker exec -it c7e5f7bd9f5c bash -lc 'cd /tmp/hostbins && gdb-multiarch -q ./print_x64_linux'
```

#### 2.2.2 x64 self-host compiler “run” gate (remote Win11 (WSL2 optional))

Once basic x64 binaries run, Tier‑1 parity still requires the **compiler binary itself** to run on x86_64:

- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`

If the gate fails with an early exit and no diagnostics, treat it as a “tooling contract” issue first:

- The compiler’s build cache probes optional files; missing files must be surfaced as **error maps** (via `oren_err(...)`), not process exit.
  - A common regression is `oren_read_file(...)` / `oren_read_u8_buf(...)` hard-exiting on ENOENT.
- For “silent” failures on x64-linux, prefer a bounded syscall trace to find the last OS call:
  - `qemu-x86_64 -strace ./oren_selfhost_x64_linux ...` (then inspect only the last ~50 lines).

### 3) What “slow” usually means (native backend)

In practice, “compile one file is slow” is almost always one of:

1) **Runtime bundle overhead** (native backend injects `lib/runtime_native.oren` into every program):
   - runtime expansion (`// @include`) and parsing
   - runtime astbin decode (multi-megabyte blobs)
   - runtime OS pruning (`if g_target_os == ...`) and cache hygiene
2) **Runtime object miss** (cold path):
   - compiling hundreds of runtime decls + fixups
3) **Emitter hot loops**:
   - per-byte pushes into code/data buffers
   - fixup patching patterns that do O(N) tiny writes

The bounded tracing knobs in `docs/BUILD_AND_VERIFY.md` are designed to tell you *which bucket* you’re in without spamming.

### 4) The biggest performance footguns we hit (and how to avoid them)

#### 4.0 Runtime astbin cache hygiene (pruned runtime)

The compiler caches the expanded+parsed native runtime under `build/cache/native_runtime_astbin/`.

Rolling policy:

- Per-target-OS cache files use suffixes like:
  - `*_os_macos_pruned3.astbin`
  - `*_os_linux_pruned3.astbin`
- These are expected to already have dead `g_target_os` branches pruned.
  - The pruned program is marked with:
    - `__oren_pruned_target_os_id`
    - `__oren_pruned_target_os_kind="g_target_os"`
    - `__oren_pruned_target_os_cache_gen` (bump when pruning behavior changes)
- If you see runtime OS pruning happening on an astbin cache hit (`OREN_TRACE_RUNTIME_OS_PRUNE=1`),
  treat it as a stale/unpruned cache file. The compiler will attempt a best-effort rewrite, which can
  be expensive once. After rewrite, runtime astbin decode should be materially faster.
- Cache robustness (rolling):
  - The runtime astbin cache decode path performs a best-effort structural sanity check on decoded blobs.
    If the decoded program looks corrupted/stale (common symptom: later crashes like “string_len expects string”),
    the compiler treats it as a cache miss and falls back to seeds or runtime source parsing.
  - Important invariant: `@cfg` lowering must be applied even on **decoded** runtime astbins (cache hit / seed hit),
    not only on the “parse runtime source” path. Otherwise, a cache hit can preserve mutually-exclusive variants or
    wrong-platform stubs and reintroduce both correctness and performance regressions.
  - If you see repeated “miss (sanity check failed)” behavior, clear caches with `./oren clean` (or delete
    `build/cache/native_runtime_astbin/` if you’re iterating on compiler internals).

Seed (rolling, optional):

- A runtime-astbin seed dir can avoid stage2-native “cold parse” costs when the astbin cache is empty:
  - env: `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=<dir>` (default: `build/cache/native_runtime_astbin_seed/`; disable with `0`/`false`)
  - generator: `make astbin-seed` (uses stage1 `./oren` to pre-warm and copy seed files)
  - cross-target seeds: `make astbin-seed-x64` (generates `x64-linux`/`x64-windows` pruned astbins so cross-target verification stays bounded when runtime hashes change)
- Seed correctness note (rolling):
  - The runtime astbin cache basename uses a fingerprint of the **expanded runtime source** (`_rt_bundle_runtime_fingerprint_v2(expanded_runtime_src)`), which is intentionally distinct from the runtime-object cache hash (`rtobj_runtime_hash(...)`).
  - To avoid “seed dir exists but stage2 still cold-parses”, `scripts/build_runtime_astbin_seed.sh` writes a per-OS meta file (`.runtime_astbin_seed_meta_os_<os>.txt`) that invalidates the seed when either:
    - runtime source inputs change (hash of `lib/runtime_native*.oren` + `lib/runtime_native/**/*.oren`), or
    - the chosen seed compiler binary changes (sha256 of `--compiler`).

Runtime OS pruning note (rolling):

- The runtime pruner can also splice away **top-level** `if g_target_os == ... { ... }` blocks, but only when the condition is provably constant for the target platform.
  - This is intended for large OS-specific helper suites (e.g., Windows CreateProcessA helpers) so non-target builds do not pay for compiling dead runtime decls.
  - Constraint: after pruning, the top-level must still contain **only** `Function` / `ExprStmt(Function)` / `Var` / `Type` / `FFI` statements.
    - If a top-level OS-guard cannot be proven constant, the runtime bundle validator will still reject it as “top-level executable code”.

#### 4.0.1 Don’t use `nil` as a tri-state sentinel in compiler passes (native backend)

Some compiler passes want a tri-state “true / false / unknown”.

In the native backend, **do not** use `nil` to mean “unknown” if the result is later compared with
`== false` / `!= true`-style checks: under the current native value model, `nil` can collapse into
the same immediate as `false`/`0`, which can silently flip pruning decisions.

Preferred pattern: return an explicit integer state (`1=true`, `-1=false`, `0=unknown`) and compare
it with exact integer tests.

#### 4.0.2 rtobj cache meta must be stable across stage1 and stage2

The runtime-object cache (`build/cache/native_runtime_obj/`) is shared across:

- **stage1** compiler runs (C runtime)
- **stage2** compiler runs (native runtime)

Rolling rule:

- Any validation of rtobj meta against the cache key must be **runtime-agnostic**.
  - Avoid relying on subtle runtime differences like “string equality” semantics or substring allocation behavior.
  - Prefer byte-wise key parsing and byte-wise string comparisons in the rtobj cache module when correctness matters.
 - rtobj fixups must preserve enough information to be relocatable safely.
   - Example hazard: arm64 `adr_data` fixups that target a non-`x0` register (e.g. `x9` scratch) must carry the destination register through the rtobj meta.
     - If the reg is dropped, the final fixup applier defaults to `x0` and the resulting runtime code can dereference an uninitialized register (common symptom: startup `EXC_BAD_ACCESS` at address `0x1000`).
   - Rolling rule: if you change rtobj meta encoding/decoding, bump the rtobj backend signature so stale cache entries are not reused.

If this regresses, it typically shows up as:

- `make verify-native-x64-compile` timing out because stage2 treats a valid stage1-generated cache entry as a miss and rebuilds the runtime object.

#### 4.0.3 Varargs must be packed exactly once (`__oren_fnwrap_*` recursion hazard)

The native backends use synthesized wrapper functions (`__oren_fnwrap_*`) so a named function can be passed as
a uniform callable object.

Key contract:

- A wrapper already receives a pre-packed `rest_list` for varargs calls.
- The wrapper should forward that list directly (it must not “re-pack” varargs inside the wrapper body).

If call lowering tries to pack varargs again inside a wrapper, you can get:

- infinite recursion through the callable ABI (often reported as `call depth exceeded`), or
- subtle arg shape corruption (nested rest lists).

#### 4.0.4 Embedded string literals must stay untracked (cstr0 pool)

Native backend model (rolling):

- String literals (e.g. `"hello"`) are emitted into a single constant/data-section byte pool (`cstr0`).
- Those pointers are valid “string values” but they are **not GC-managed heap allocations**.
- The runtime recognizes literal pointers via a startup-built membership set:
  - `oren_init_static_cstr0_table` populates the set
  - `native_is_string_ptr` / `oren_is_string` consult it

Why this matters for performance:

- If literals become tracked as alloc nodes, GC conservative scans start treating “every literal pointer” as an object:
  - mark work explodes (compiler workloads have many literal keys),
  - startup costs can spike (tracking metadata nodes per literal),
  - and regressions can manifest as “compile one file took seconds/minutes”.

Guardrails + regressions:

- The runtime treats attempts to track cstr0 literals as a no-op:
  - `oren_track_alloc(lit, ..., kind=STRING)` must not create a node
  - `oren_track_static(lit, kind=STRING)` must not create a node
- `make test` includes a regression that asserts:
  - identical literals are pointer-equal (`lit0 - lit1 == 0`),
  - and `oren_find_node(lit) == 0` (no tracking metadata for literals).

If you see a perf regression around GC/marking:

- First, re-run the bounded compile-one-file check:
  - `./scripts/bench_native_compile_one_file.sh --no-debug`
  - `./scripts/perf_guard_native_compile_one_file_hit.sh`
- Then, treat “literals being tracked” as a prime suspect and confirm the invariant via the quick integration binary
  (it prints bounded failure logs on mismatch).

Rolling guardrail (implementation):

- The fnwrap synthesis marks the internal call as “already packed”:
  - `packed_call["__oren_varargs_packed"] = 1`
- The x86_64 call emitter skips varargs packing when that marker is present.

Regression gate:

- `make verify-tier1` (or `./scripts/verify_native_matrix.sh --targets x64-win-tier1,x64-wsl-tier1`) runs a Tier‑1 fixture that exercises varargs + spread across stage1+stage2 on real x86_64.

#### 4.1 Per-byte helper calls in tight loops

Stage2-native compiler workloads can decode or emit **millions of bytes**. If the code does:

- one function call per byte (`load_u8`, `push_u8`, etc), or
- repeated “header lookups” inside a byte loop,

then a “normal” 1–3MB operation can become **multiple seconds**.

Preferred patterns:

- When decoding from a `u8_buf`, materialize a raw pointer once:
  - `data_ptr = oren_buf_data_ptr_unchecked(buf)`
  - read bytes with `ptr_get_byte(iadd(data_ptr, off))`
- When emitting bytes, prefer bulk little-endian push helpers that do:
  - **one capacity check**, then raw stores (`ptr_set_byte`) for the N bytes.

See:
- `lib/compiler/compiler/015_astbin.oren` (decoder hot path)
- `lib/compiler/bytes_builder.oren` (shared byte builder)
- `lib/compiler/x64_core.oren` (x86_64 instruction encoder; uses a reusable scratch pool to avoid per-instruction allocations)

Rolling rule (x64 encoder):

- Do not allocate a fresh byte builder (or `list<int>`) per instruction.
  - Prefer `_insn_pool_get()` inside `insn_*` helpers and avoid `bytes_lit([..])` list literals in hot paths.
  - Symptom: x64 rtobj cold miss becomes tens of seconds on stage2-native cross-target builds.

#### 4.2 Overloaded arithmetic in hot loops (`+` vs `iadd`)

In Oren, `+` is a language-level operator that may involve dynamic dispatch/boxing depending on value kinds.

In very hot compiler-internal loops (decode/emit), prefer intrinsic integer add:

- `iadd(a, b)` instead of `a + b`

This is especially important when the loop variable or offsets are updated per-iteration.

#### 4.2.1 Avoid string-aware compare recursion in alloc-index internals (`==/!=`)

Some native backends lower `==/!=` to a **string-aware compare** that consults tracking metadata
(so `"a" == "b"` compares contents, not pointer identity).

This becomes a correctness hazard inside the runtime alloc-index itself, because:

- string-aware compare consults tracking via `native_alloc_index_get(...)`, and
- alloc-index internals also need to compare pointers/slots/tombstones.

If alloc-index code uses `==/!=` between non-constant values (e.g. `slot != tomb`, `ptr_get(node) == ptr`),
it can **indirectly recurse back into `native_alloc_index_get(...)`** and stack overflow during early init.

Guardrail patterns (Tier‑1):

- Prefer compare-to-0 arithmetic:
  - equality: `if (a - b) == 0 { ... }`
  - inequality: `if (a - b) != 0 { ... }`
- Keep tombstone sentinels small and non-zero:
  - `g_alloc_index_tomb` must be non-zero and `< 4096`, and should be set in `native_runtime_init`
    (do not rely on global initializers).

Reference implementation:

- `lib/runtime_native/100_time.oren` (alloc-index internals use arithmetic compares)
- `lib/runtime_native/020_fork_runtime_init.oren` (init sets `g_alloc_index_tomb`)

#### 4.3 Avoid huge logs (they hide the signal)

When diagnosing perf regressions:

- Prefer single-line summaries (`OREN_TRACE_BUILD_SUMMARY=1`)
- Prefer targeted tracers for the suspected subsystem:
  - runtime bundle: `OREN_TRACE_RUNTIME_BUNDLE=1`
  - astbin: `OREN_TRACE_ASTBIN=1`
  - rtobj cache: `OREN_TRACE_RUNTIME_OBJ_CACHE=1`

If you need deeper info, add **bounded** counters/phase timings rather than printing every event.

#### 4.4 Build cache key computation (don’t let it dominate builds)

`oren build` computes a content-addressed **build cache key** *before* doing any expensive compilation work.

If `cache key compute` is taking seconds, the compiler will feel “hung” even though the backend is fine.

Practical workflow:

- Run with bounded tracing:
  - `OREN_TRACE_BUILD=1 oren build ...`
- Look for:
  - `[build] cache key compute +...ms`
  - `[cache] injected_runtime_hash +...ms ...`

Typical root cause:

- The native backend injects `lib/runtime_native.oren` into every program, and the build cache key includes a hash of the injected runtime include-closure.
- If the scan cache is not persisted (or is persisted via an O(n²) string concat path), the compiler ends up re-walking that closure on every `oren build` invocation.

Policy (rolling):

- The runtime include-closure hash should be **milliseconds** on a warm cache (`build/cache/scan_cache_v3.txt`).
- If you need an emergency bypass while diagnosing, use `--no-cache` (but treat a multi-second cache-key as a bug to fix, not a “flag to keep”).

#### 4.5 Compiler code must remain cross-runtime portable (stage1 vs stage2)

The compiler implementation is executed in multiple runtime modes:

- **Stage1** typically runs under the **C backend runtime**.
- **Stage2** runs under the **native runtime**.

Rolling rule:

- Avoid assuming a specific low-level value layout in compiler-side helpers (especially for strings).
  - Example footgun: using `ptr_get_byte(...)` directly on a “string” value inside compiler code can work under the native runtime but break under stage1 if the C backend’s string representation differs.
  - Prefer portable helpers (`oren_string_len`, `strcmp`, etc.) unless the code is explicitly guarded to run only under one runtime model.

#### 4.6 Intrinsic temp spill slots: never materialize `$tmp_intrN` identifiers in hot paths

The x64 native backend uses an **intrinsic temp pool** to safely spill values while lowering nested intrinsic calls.

Perf + robustness rule (rolling):

- Do **not** construct `{"type":"Identifier","value":"$tmp_intrN"}` AST nodes inside lowering helpers.
  - It causes:
    - per-use string allocation churn (`"$tmp_intr" + int_to_string(n)`), and
    - per-function locals-map inserts for every intrinsic temp slot.

Current contract (x64 native v0):

- Intrinsic temp references must use the compiler-internal node:
  - `{"type":"IntrTmp","idx": <int>}`
- The function prologue reserves a contiguous spill region and records:
  - `ctx["intr_tmp_base_off"]` (RBP-relative base offset, slot 0)
  - Slot 0 is reserved; intrinsic temp indices start at **1**.
- `_intr_tmp_off(ctx, locals, idx)` computes:
  - `off = intr_tmp_base_off + idx*8`
  - using `iadd` only (stage1-safe; avoids slow generic `*` / `<<` lowering in the C runtime).

If you see compiler-side errors like `missing intrinsic temp slot $tmp_intr...`, it usually means:

- some lowering path reintroduced `$tmp_intrN` identifiers (regression), or
- a function codegen path forgot to set `intr_tmp_base_off` before lowering.

#### 4.7 Native runtime value semantics: never use `0` as an “optional” sentinel

Rolling rule (stage2-native robustness):

- The native backend is an untagged “i64 carrier” model for many values (pointers + immediates).
  `0` is a valid integer payload **and** the raw null-pointer value used by many low-level/native APIs.
  Therefore `0` is *not a safe sentinel* for “missing/absent” in compiler-side structures.
- Prefer:
  - `nil` as the missing/absent sentinel for metadata in maps/dicts, or
  - `n+1` encodings when call sites decode via `enc-1` and need to represent a real 0 value.
- Avoid writing `x == nil` when `x` is numeric: it is almost always a bug that should be expressed as a type/tag check.
- Related footgun: **do not encode booleans as `0/1` ints.**
  - In Oren, `0` is truthy; only `nil` and `false` are falsey.
  - Predicate helpers must return `false`/`true` (e.g. `oren_is_err(v) -> bool`, `oren_is_done(handle) -> bool`), and callers must not write `== 0` / `!= 0` checks against boolean results.

Two concrete pitfalls we’ve hit in the x86_64 backend:

- **x86_64 ModRM/SIB encoding requires `disp8=0` bytes.**
  - `[rbp]` / `[r13]` addressing needs `mod=01` + `disp8=0`.
  - Fix pattern: represent optional numeric fields as `n+1` so `0` can be reserved for "absent",
    and decode at emission time (`enc["disp8"] - 1`).
- **Intrinsic temp spill allocator must not return base index `0`.**
  - Use 1-based indices (reserve slot 0) so `base==0` never aliases “no base”.

Regression gates:

- `./scripts/verify_native_x64_compile_only.sh` checks:
  - Windows PE prologue bytes include the required `disp8=0` byte (and rejects the known-bad omission pattern)
  - Windows PE Export Directory contains expected exported symbol names (for `--lib` DLL outputs and `@ffi.export` on EXE)
    - Rationale: `strings`/byte searches are insufficient; exports must be present in the PE export table.
    - Implementation: `scripts/pe_exports_check.py` (no external deps; parses PE32+ export directory)
  - stage1 + stage2 compilation of `tests/native/print.oren` embeds `hello from native` into the output binary for `x64-linux` and `x64-windows` (guard against call/arg evaluation regressions).

#### 4.8 x86_64 self-host compiler builds: avoid per-call string allocation in hot paths

Symptom:

- Cross-target builds of the compiler itself can look “hung” when building x86_64 compiler binaries:
  - Preferred (x64-focused compiler graph): `./oren_stage2 build oren_x64.oren --backend native --platform x64-linux ...`
  - Full compiler graph (includes arm64 backends): `./oren_stage2 build oren.oren --backend native --platform x64-linux ...`
  - Windows target: `./oren_stage2 build oren_x64.oren --backend native --platform x64-windows ...`
- The usual failure mode is **one pathological function** dominating codegen time.
  - This can appear as “stuck at 100% CPU” with no output for minutes.

Diagnosis (bounded; do not dump the world):

- Use the x64 compile progress tracer:
  - `OREN_TRACE_X64_COMPILE_PROGRESS=1`
  - `OREN_TRACE_X64_COMPILE_STRIDE=1000` (print every 1000 functions)
  - `OREN_TRACE_X64_COMPILE_FOCUS_FROM=<i> OREN_TRACE_X64_COMPILE_FOCUS_TO=<j>` (only print a narrow range; useful when you already know the bad region)
  - `OREN_TRACE_X64_SLOW_FN_MS=2000` (prints `slow_fn` lines)
  - `OREN_TRACE_X64_TOP_SLOW_FNS=1` (prints a bounded “top N slowest functions” list after codegen)
    - `OREN_TRACE_X64_TOP_SLOW_FNS_N=20` (default: 20)
    - `OREN_TRACE_X64_TOP_SLOW_FNS_MIN_MS=50` (default: 50)
- For one known-hot function, add a per-function breakdown:
  - `OREN_TRACE_X64_FN=<exact function name>`
  - Optional deep emit tracing (still bounded): `OREN_TRACE_X64_FN_EMIT_OPS=1` with `OREN_TRACE_X64_EMIT_OPS_STRIDE=<n>`

Fix pattern (root cause class we’ve hit in self-host builds):

- **Do not allocate strings in per-call classification hot paths.**
  - Example footgun: using `oren_string_slice(...)` to check name prefixes/suffixes inside the x64 call emitter.
  - When compiling the compiler, large backend helper functions contain *many* calls, so tiny per-call allocations become a multi-minute stall.
- Prefer byte-prefix checks via `oren_string_byte_at_unchecked(...)` for:
  - `oren_` detection
  - `oren_buf_` prefix / `_buf_new` suffix checks
- Avoid paying “runtime call classification” chains for non-`oren_*` internal helper names (encoder helpers, backend emitters, etc); route these calls directly through the generic call path when safe.

Measured improvement (arm64-macos host, 2026-01-06):

- Before: `./oren_stage2 build oren.oren --backend native --platform x64-linux --no-debug` was still compiling after ~11m and was manually interrupted.
- After fixing the per-call allocation patterns in x64 call emission, the same build completed successfully in ~7m30s, and previously-pathological compiler functions dropped from “minutes” to “~3s” each (see `docs/TODOS_ARCHIVE.md`).

### 5) GC + string literal policy (perf + correctness)

String literals in native output are **pooled and embedded** in the binary’s data segment (cstr0 pool).

Key properties (rolling contract):

- identical literals should be pointer-deduped in the embedded pool
- the runtime initializes the embedded literal membership set once at startup (`oren_init_static_cstr0_table`)
- literals are **not GC-managed heap allocations** and are not tracked as alloc nodes
  - `oren_find_node(lit_ptr)` returns `0` (no per-literal tracking nodes)
  - string classification uses `native_is_string_ptr` / `oren_is_string` which recognize `cstr0` literals without GC tracking

This is tested in the native quick integration suite (`tests/native/test_quick_integration_native.oren`).

### 6) How to keep regressions from coming back

If you touch compiler hot paths (astbin decode, native emit, runtime injection), do this before merging:

1) Run:
   - `make verify-native-quick`
   - `./scripts/verify_native_x64_compile_only.sh`
   - If the change touches FFI / networking / TLS providers, also run:
     - `./scripts/verify_native_net_matrix.sh`
     - `./scripts/verify_windows_stage2_from_stage1.sh` (catches Win-only stage1->stage2 regressions)
2) Run the bounded perf check:
   - `OREN_NATIVE_BUILD_TIMEOUT_SECS=60 ./scripts/bench_native_compile_one_file.sh --no-debug`
3) If you see “rtobj miss” > 10s, re-run with tracing and identify the dominant bucket:
   - `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1` (arm64) prints one `[arm64_rtobj] ...` line with parse/decl/finalize timings.
   - `OREN_TRACE_ARM64_RT_OBJ_TOP_DECLS=1` (arm64) prints a bounded “top decls” list to spot unusually-slow runtime declarations.
   - `OREN_TRACE_ASTBIN=1` prints `[astbin] decode done +...ms` for the runtime bundle decode.
   - runtime expand/parse
   - astbin decode
   - runtime decl compilation
   - emit/fixups

Healthy reference (arm64-macos stage2, rolling as of 2026-01-10; isolated rtobj dir, seed disabled):
- rtobj miss compile-one-file: ~`3.4s`
- rtobj hit compile-one-file: ~`0.5s`

If the slow path is “expected” (cold cache), consider whether we should:

- improve caching, or
- reduce decode/emit overhead, or
- change the representation so the cold path does less work.

### 7) Future direction (high leverage)

The long-term fix for “runtime bundle dominates cold builds” is to reduce the amount of graph materialization:

- decode into a compact representation closer to the backend’s needs (or persist the lowered runtime form)
- keep fast paths **zero-copy** where possible
- avoid pointer-heavy AST graphs crossing boundaries unless necessary

Track active work in `docs/TODOS.md`.
