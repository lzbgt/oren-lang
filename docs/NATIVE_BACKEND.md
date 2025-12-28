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
  - **Linux**: ELF 64-bit (`ET_EXEC`) with a minimal single `PT_LOAD` image (no dynamic section / no dynamic linker integration yet).
  - **Windows (x86_64 bring-up)**: PE32+ with a minimal import table for `kernel32` and a small `.rdata` blob for string literals.

- **Language Features**:
  - **Control Flow**: `if/else`, `while`, `Block`, `Return`.
  - **Functions**: Definitions, direct calls, and first-class function values (callable pointers) with indirect calls (rolling; x86_64 bring-up). Stack frames (`FP`/`LR` on arm64; `RBP` on x86_64). Entry trampolines align the stack for ABI-correct calls and terminate via syscall (Linux) or imported `ExitProcess` (Windows).
  - **Variables**: Local (stack-allocated) with block-scoped cleanup to prevent loop leaks.
  - **Structs**: Constructors generate `Map` objects (Duck Typing). Access via `obj.field`. Nested struct offsets are honoured in native layout.
  - **Lists (WIP)**: Minimal list runtime/intrinsics for bring-up (`oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_list_set`, plus `oren_index_set` for list-aware index assignment) for future native feature parity.
  - **Modules**: `import` loads code (merged).

- **Memory & Concurrency**:
  - **Allocation**: Bump-pointer heap (X28/X27) with on-demand `mmap` growth (max of request or 64KB) and a runtime hook `oren_alloc_struct` for struct buffers. Stack slots in inner blocks are released automatically to keep frames bounded across loops.
  - **GC**: Conservative mark/sweep GC lives in `lib/runtime_native.oren` (expanded from smaller parts under `lib/runtime_native/*.oren`) and can be triggered manually via `native_gc_collect()`.
  - **Access**: `ptr_get`, `ptr_set`, `ptr_get_byte`, `ptr_set_byte`.
  - **Lists**: `oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` (list-aware), plus array literal lowering in codegen.
- **Atomics**: `atomic_add` (LDADD), `atomic_cas` (CAS).
- **SIMD**: 128-bit NEON intrinsics (`simd_add_2d`, `mul_4s`, etc.).
- **Spawn/Join (macOS v0)**: `spawn` is currently implemented as **fork + pipe** (process-based) and `oren_join` reads the returned value from the pipe and reaps the child via `wait4`.
  - This is a deliberate syscall-first compatibility choice to avoid depending on `pthread_*` / `bsdthread_*` ABIs until a robust OS-thread design lands.

- **Runtime**:
  - **ARM64**: automatically injects `lib/runtime_native.oren` (expanded from `lib/runtime_native/*.oren` via `// @include "..."`) which implements `String` comparison and `Map` logic.
  - **x86_64 bring-up**: does not yet inject the full native runtime, but it now includes syscall/WinAPI-backed intrinsics for core primitives (`malloc`/`malloc_raw` bump allocator state and `ptr_get`/`ptr_set` qword+byte access), plus small target-specific helpers for I/O and process exit. The Tier-1 roadmap is to converge on the same injected runtime surface for callables/closures, lists/maps/strings, and capsule gating.
  - Includes `oren_readdir(path)` built on syscall-first `sys_getdirentries64`.
  - `oren_net_get(url)` is implemented on native as a minimal HTTP/1.0 GET over syscall-first TCP:
    - supported form: `http://<ipv4>[:port][/path]`
    - no TLS/HTTPS, no DNS, no chunked decoding (v0).

## Syscall Notes (macOS arm64)

- The native backend emits syscalls as **inline `svc`** instructions (Darwin arm64 uses `X16` as the syscall register) and does **not** call libc’s `syscall(2)` wrapper.
- Syscall numbers are taken from Darwin/XNU references (see `docs/refs/darwin_xnu_syscalls.master`).
- Repo-owned ABI constants (syscalls + offsets) live in `lib/compiler/arm64_abi_macos.oren` (see `docs/refs/darwin_arm64_abi.md`).
- `sys_stat(path, st_ptr)` on macOS uses **`stat64` (syscall 338)** for correct 64-bit `struct stat` behavior on arm64.
- `sys_lstat(path, st_ptr)` on macOS uses **`lstat64` (syscall 340)** (no-follow symlink metadata).
- `sys_fstat(fd, st_ptr)` on macOS uses **`fstat64` (syscall 339)**.
- `sys_getdirentries64(fd, buf, bufsize, pos_ptr)` on macOS uses **`getdirentries64` (syscall 344)**; on Linux it maps to `getdents64` (61) and ignores `pos_ptr` (v0).
## Notes / Limitations
- **String concatenation:** on the native backend, `+` lowers to the runtime helper `oren_add` and supports:
  - integer addition
  - string concatenation when *both* operands are strings (content-based), matching native `strcmp` semantics for comparisons.

  Rolling guidance:
  - Prefer `+` everywhere.
  - `string_concat(a, b)` exists as a low-level native runtime helper but is treated as an internal primitive; the repo’s curated tests and audits intentionally avoid using it in higher-level code.
- **Linux FFI/linking:** the ELF emitter currently stubs unresolved imports (no `DT_NEEDED`/PLT/GOT relocation support yet).
- **W^X (x86_64 bring-up):** the minimal x64 ELF/PE emitters currently map the “data blob” writable to support
  Tier‑1 bring-up features like a deterministic recursion guard (call depth counter). The production direction is:
  - ELF: RX text PT_LOAD + RW data PT_LOAD
  - PE: `.text` (RX) + `.rdata` (R) + `.data` (RW)

## CLI Usage
```bash
make verify # Run full self-hosting test
./oren build file.oren --backend native -o out
./oren build file.oren --backend native -o out --target linux
./oren build file.oren --backend native --disasm
./oren build file.oren --analyze # Static analysis
```

## New Features (Dec 2025)

- **Shared Libraries**: Build `.dylib` (macOS) using `--lib`. Exports defined functions.
  ```bash
  ./oren build mylib.oren --backend native --lib -o mylib.dylib
  ```
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
