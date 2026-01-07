# Native Backend (ARM64 + x86_64 Tier 1)

The native backend emits machine code directly for:

- **ARM64** (primary): macOS (Mach-O) and Linux (ELF)
- **x86_64** (Tier 1; rolling evolution): Linux (ELF) and Windows (PE32+)

The x86_64 backend is a Tier-1 target, but is still in rolling evolution; `docs/TODOS.md` tracks what is implemented today and what is next.

## ABI Notes (x86_64 SysV vs Win64)

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

## Supported Features

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
    - Indexing is polymorphic: `xs[i]` / `m[k]` dispatches based on **tracked allocation metadata** (see `docs/RUNTIME_NATIVE_LAYOUT.md`).
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
  - `oren_net_get(url)` is implemented on native as a minimal HTTP/1.0 GET over syscall-first TCP:
    - supported form: `http://<ipv4>[:port][/path]`
    - no TLS/HTTPS, no DNS, no chunked decoding (v0).

## Syscall Notes (macOS arm64)

- The native backend emits syscalls as **inline `svc`** instructions (Darwin arm64 uses `X16` as the syscall register) and does **not** call libc’s `syscall(2)` wrapper.
- Syscall numbers are taken from Darwin/XNU references (see `docs/refs/darwin_xnu_syscalls.master`).
- Repo-owned ABI constants (syscalls + offsets) live in `lib/compiler/arm64_abi_macos.oren` (see `docs/refs/darwin_arm64_abi.md`).
- `sys_stat(path, st_ptr)` uses **`stat64` (macOS)** / **`newfstatat` (Linux)** into a private host `struct stat` buffer, then translates into an **Oren-owned stable layout** (OrenStatV0) at `st_ptr` (no host `struct stat` layout exposed to user code).
- `sys_lstat(path, st_ptr)` uses **`lstat64` (macOS)** / **`newfstatat(..., AT_SYMLINK_NOFOLLOW)` (Linux)** into a private host buffer, then translates into OrenStatV0.
- `sys_fstat(fd, st_ptr)` uses **`fstat64` (macOS)** / **`fstat` (Linux)** into a private host buffer, then translates into OrenStatV0.
- `sys_getdirentries64(fd, buf, bufsize, pos_ptr)` on macOS uses **`getdirentries64` (syscall 344)**; on Linux it maps to `getdents64` (61) and ignores `pos_ptr` (v0).
## Notes / Limitations
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

## CLI Usage
```bash
make verify # Run full self-hosting test
./oren build file.oren --backend native -o out
./oren build file.oren --backend native -o out --target linux
./oren build file.oren --backend native --disasm
./oren build file.oren --backend native --no-debug # Disable stack-trace debug info (or: OREN_NATIVE_NO_DEBUG=1)
./oren build file.oren --analyze # Static analysis
```

## New Features (Dec 2025)

- **Shared Libraries**: Build `.dylib` (macOS) using `--lib`. Exports defined functions.
  ```bash
  ./oren build mylib.oren --backend native --lib -o mylib.dylib
  ```
  Notes (rolling):
  - This is implemented for **arm64-macos (Mach-O)** today.
  - x86_64 native backends currently reject `--lib/--shared` (ELF `.so` / PE `.dll` export tables are not implemented yet).
- **Linking**: Link external dynamic libraries using `--link <lib>` or `-l <lib>`.
  ```bash
  ./oren build app.oren --backend native --link /usr/lib/libsqlite3.dylib
  ```
- **API Scanning**: Generate API docs from C libraries.
  ```bash
  ./oren scan /usr/lib/libSystem.B.dylib
  ```

## Internal Architecture
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

## Why some x86_64 helpers use 32-bit ops (e.g. `eax`) even though the arch is 64-bit

On x86_64, writing a 32-bit subregister (like `eax`) has two important properties:

1) **Encoding size / immediates**: many instructions have a smaller encoding for imm32 forms.
2) **Architectural behavior**: writes to a 32-bit register zero-extend into the full 64-bit register.

When Oren wants a *signed* i32 value in `rax`, a common safe sequence is:

- `mov eax, imm32` (loads 32-bit value)
- `cdqe` (sign-extend `eax` → `rax`)

This is not a type-system statement (“int is i32”), it’s an emitter optimization/detail. The language-level
`int` is still treated as a 64-bit two’s-complement value in the compiler/runtime model; the emitter just
chooses compact encodings when they are provably correct.
