# Native Backend (ARM64)

The native backend emits machine code directly for macOS (Mach-O) and Linux (ELF) on ARM64 architectures.

## Supported Features

- **Executable Formats**:
  - **macOS**: Mach-O 64-bit, PIE. Supports dynamic linking with `libSystem` (FFI) via `LC_DYLD_INFO_ONLY` binding opcodes and GOT stubs. The CLI signs the finished binary with your Developer ID by default.
  - **Linux**: ELF 64-bit, PIE (`ET_DYN`), System V ABI.

- **Language Features**:
  - **Control Flow**: `if/else`, `while`, `Block`, `Return`.
  - **Functions**: Definitions, Calls (stack passing), Stack frames (`FP`/`LR`). Entry trampoline aligns to 4-byte boundaries and calls `main` before exiting via syscall.
  - **Variables**: Local (stack-allocated) with block-scoped cleanup to prevent loop leaks.
  - **Structs**: Constructors generate `Map` objects (Duck Typing). Access via `obj.field`. Nested struct offsets are honoured in native layout.
  - **Lists (WIP)**: Minimal list runtime (`oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` for lists) for future native feature parity.
  - **Modules**: `import` loads code (merged).

- **Memory & Concurrency**:
  - **Allocation**: Bump-pointer heap (X28/X27) with on-demand `mmap` growth (max of request or 64KB) and a runtime hook `oren_alloc_struct` for struct buffers. Stack slots in inner blocks are released automatically to keep frames bounded across loops. GC hooks exist but are currently no-ops; native allocations are still arena-style.
  - **Access**: `ptr_get`, `ptr_set`, `ptr_get_byte`, `ptr_set_byte`.
  - **Lists**: `oren_new_list`, `oren_list_len`, `oren_list_push`, `oren_list_get`, `oren_index_set` (list-aware), plus array literal lowering in codegen.
  - **Atomics**: `atomic_add` (LDADD), `atomic_cas` (CAS).
  - **SIMD**: 128-bit NEON intrinsics (`simd_add_2d`, `mul_4s`, etc.).

- **Runtime**:
  - Automatically injects `lib/runtime_native.oren` which implements `String` comparison and `Map` logic.

## CLI Usage
```bash
make verify # Run full self-hosting test
./oren build file.oren --backend native -o out
./oren build file.oren --backend native -o out --target linux
./oren build file.oren --backend native --disasm
./oren build file.oren --analyze # Static analysis
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
