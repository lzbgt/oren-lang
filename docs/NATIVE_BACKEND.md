# Native Backend (ARM64)

The native backend emits machine code directly for macOS (Mach-O) and Linux (ELF) on ARM64 architectures.

## Supported Features

- **Executable Formats**:
  - **macOS**: Mach-O 64-bit, PIE. Supports dynamic linking with `libSystem` (FFI) via `LC_DYLD_INFO_ONLY` binding opcodes and GOT stubs. The CLI signs the finished binary with your Developer ID by default.
  - **Linux**: ELF 64-bit (`ET_EXEC`) with a minimal single `PT_LOAD` image (no dynamic section / no dynamic linker integration yet).

- **Language Features**:
  - **Control Flow**: `if/else`, `while`, `Block`, `Return`.
  - **Functions**: Definitions, Calls (stack passing), Stack frames (`FP`/`LR`). Entry trampoline aligns to 4-byte boundaries and calls `main` before exiting via syscall.
  - **Variables**: Local (stack-allocated) with block-scoped cleanup to prevent loop leaks.
  - **Structs**: Constructors generate `Map` objects (Duck Typing). Access via `obj.field`. Nested struct offsets are honoured in native layout.
  - **Lists (WIP)**: Minimal list runtime (`oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` for lists) for future native feature parity.
  - **Modules**: `import` loads code (merged).

- **Memory & Concurrency**:
  - **Allocation**: Bump-pointer heap (X28/X27) with on-demand `mmap` growth (max of request or 64KB) and a runtime hook `oren_alloc_struct` for struct buffers. Stack slots in inner blocks are released automatically to keep frames bounded across loops.
  - **GC**: Conservative mark/sweep GC is implemented in `lib/runtime_native.oren` and can be triggered manually via `native_gc_collect()`.
  - **Access**: `ptr_get`, `ptr_set`, `ptr_get_byte`, `ptr_set_byte`.
  - **Lists**: `oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` (list-aware), plus array literal lowering in codegen.
- **Atomics**: `atomic_add` (LDADD), `atomic_cas` (CAS).
- **SIMD**: 128-bit NEON intrinsics (`simd_add_2d`, `mul_4s`, etc.).
- **Spawn/Join (macOS v0)**: `spawn` is currently implemented as **fork + pipe** (process-based) and `oren_join` reads the returned value from the pipe and reaps the child via `wait4`.
  - This is a deliberate syscall-first compatibility choice to avoid depending on `pthread_*` / `bsdthread_*` ABIs until a robust OS-thread design lands.

- **Runtime**:
  - Automatically injects `lib/runtime_native.oren` which implements `String` comparison and `Map` logic.
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
  Use `string_concat(a, b)` when you want explicit string concatenation semantics (useful while the type system is still rolling).
- **Linux FFI/linking:** the ELF emitter currently stubs unresolved imports (no `DT_NEEDED`/PLT/GOT relocation support yet).

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
