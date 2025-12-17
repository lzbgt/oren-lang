# Building and Verifying Oren

This guide documents the complete process of building the Oren compiler from source (bootstrapping), using it to build applications, and verifying cross-compiled Linux binaries from a macOS development machine.

## 1. Bootstrapping Oren (Stage 0 to Self-Hosting)

Oren is a self-hosted language. The repository contains a "Stage 0" compiler written in Go, which is used to compile the "Stage 1" compiler (written in Oren). Stage 1 can then compile itself to produce Stage 2, proving self-hosting capability.

### Prerequisites
- **Go 1.20+**: To build the Stage 0 bootstrap compiler.
- **C Compiler (clang/gcc)**: Required by the C backend (used for self-hosting).
- **Make**: For build automation.

### Step 1: Build Stage 0 (Go Bootstrap)
Compile the Go implementation of the compiler. This version is slow but stable.

```bash
# In the project root
go build -o oren_bootstrap ./cmd/oren
```

### Step 2: Build Stage 1 (The "Oren" Compiler)
Use the bootstrap compiler to compile the self-hosted Oren source (`oren.oren`) into a native executable. This produces the production compiler.

```bash
# Syntax: ./oren_bootstrap build <source> [flags]
./oren_bootstrap build oren.oren
```
*Output:* An executable named `oren`.

### Step 3: Verify Self-Hosting (Stage 2)
Use the Stage 1 compiler (`oren`) to compile the Oren source code again. The resulting binary should be identical in function to Stage 1.

```bash
./oren build oren.oren -o oren_stage2
```

---

## 2. Building Applications

Once you have the `oren` executable (Stage 1), you can compile user applications.

### Native Backend (macOS/Linux ARM64)
Compiles directly to machine code (Mach-O or ELF). Fast and dependency-free.

```bash
# Build for the host OS
./oren build examples/hello.oren --backend native -o hello

# Cross-compile for Linux (from macOS)
./oren build examples/hello.oren --backend native --target linux -o hello_linux
```

### C Backend (Portable)
Transpiles Oren to C, then compiles with the system C compiler (`cc`). Best for stability and platform compatibility (x86_64, etc.).

```bash
./oren build examples/hello.oren --backend c -o hello
```

---

## 2.1 Test Runner Timeouts (Rolling Safety)

This repo runs in **rolling ABI** mode, so the priority is fast iteration and avoiding hangs.
The `make test` runner enforces **hard wall-time timeouts** for both “build steps” and “run steps”.

In addition, the compiler now includes a repo-runner:

```bash
./oren test
```

`./oren test` follows the same principles (curated, timeout-protected, failure-only logs), but it lives inside the Oren toolchain and is the first step toward an **Oren-native** build/test system. See `docs/TEST_SYSTEM.md` for the evolution plan.

Environment knobs:

- `TEST_TIMEOUT_SECS` (default `10`): maximum seconds allowed for executing a built test binary or running `avm`.
- `BUILD_TIMEOUT_SECS` (default `120`): maximum seconds allowed for compilation steps during tests (notably when the C backend invokes `cc`, `ld`, and codesign).
- `TIMEOUT_KILL_SECS` (default `2`): grace period before force-kill after the timeout expires.

If `timeout` is not available, `make test` will fail with a clear message (install coreutils on macOS: `brew install coreutils`).

## 3. Using FFI (Foreign Function Interface)

Oren can call external C symbols via `ffi <name>` when using the **native backend**.

Current status:
- **macOS (Mach-O):** uses dyld binding opcodes and GOT stubs; this enables basic FFI against `libSystem` and any dylibs you load via `--link`.
- **Linux (ELF):** the ELF emitter does not implement dynamic linking yet; unresolved imports are currently stubbed (so FFI is not functional on Linux native builds).

### Usage
Declare the external symbol using the `ffi` keyword, then call it like a regular function.

**Example (`examples/ffi_test.oren`):**
```oren
ffi puts

fn main() {
    puts("Hello from C FFI!")
}
```

### Compilation
When you build this with `--backend native`, the compiler generates:
1.  **Binding Info**: Bytecode in `__LINKEDIT` instructing the dynamic linker (`dyld`) to bind the symbol `_puts` to a Global Offset Table (GOT) entry.
2.  **Stubs**: A small trampoline that jumps to the address stored in the GOT.

```bash
./oren build examples/ffi_test.oren --backend native -o ffi_test
./ffi_test
# Output: Hello from C FFI!
```

*Note: Currently, arguments are passed as raw 64-bit values. String literals are passed as `char*` (pointers to null-terminated C strings).*

### Linking Third-Party Libraries
The native backend always loads `libSystem` on macOS. To load additional dylibs:

```bash
./oren build examples/ffi_test.oren --backend native --link /usr/lib/libsqlite3.dylib -o ffi_sqlite
```

To link arbitrary libraries portably (or on Linux today), use the C backend:

1.  **Use the C Backend**: The C backend allows you to pass arbitrary linker flags.
    ```bash
    # Generate C code
    ./oren build examples/myapp.oren --backend c --emit-c
    
    # Compile manually with your libraries
    cc -o myapp examples/myapp.oren.c lib/runtime.c -Ilib -pthread -lcurl
    ```

    **On Windows (MSVC/CL):**
    ```powershell
    # Compile generated C code with CL.exe
    # Ensure you are in a Developer Command Prompt
    cl /Fe:myapp.exe examples/myapp.oren.c lib/runtime.c /Ilib user32.lib kernel32.lib
    ```

2.  **Linux Native Backend Support**: ELF dynamic linking (`DT_NEEDED` / PLT/GOT relocations) is not implemented yet.

---

## 4. Verifying Linux Binaries (macOS → Linux ARM64)

If you are developing on macOS and need to verify the Linux ARM64 binaries generated by `--target linux`, you have two practical options:

1) **Preferred (trusted remote host):** run Linux ARM64 on a trusted QEMU machine and copy binaries over SSH.
2) **Optional (local):** run a Linux VM locally via QEMU on macOS.

### Option A (preferred): trusted remote Linux ARM64 host

Trusted validation host (repo convention):

- SSH: `blu@qemu-blu.localc`

Workflow:

1) Cross-compile on macOS (produces an ELF ARM64 binary):

```bash
./oren build tests/native/linux_hello.oren --backend native --target linux -o build/linux_hello
```

2) Copy to the Linux host:

```bash
scp build/linux_hello blu@qemu-blu.localc:/home/blu/
```

3) Run it:

```bash
ssh blu@qemu-blu.localc "chmod +x linux_hello && ./linux_hello"
```

This avoids maintaining local VM images, and it matches the project direction: **Linux parity early** without slowing down macOS iteration.

### Option B (optional): local QEMU VM on macOS

If you prefer local verification, install QEMU:

```bash
brew install qemu
```

### Troubleshooting
*   **SSH permissions**: If `scp`/`ssh` fails with "Permission denied", ensure your SSH key is installed (or the host allows password auth) and that you are using the correct user/host.
*   **Architecture**: Ensure you built with `--target linux`. Run `file build/linux_hello` on macOS to confirm it says `ELF 64-bit LSB executable, ARM aarch64`.

---

## 5. AVM Tooling (Disasm + Trace)

When debugging `.obc` bytecode (the AVM backend), two primitives are essential:

1) **Disassembly** (like `otool -tV`): inspect decoded opcodes, operands, branch targets, and constants.
2) **Execution trace** (like a minimal debugger log): print executed instructions with `pc/sp/fp/depth` for quick diagnosis.

### 5.0 CLI help is generated

The `./avm --help` text is generated from an Oren CLI spec:

- Generator: `tools/gen_avm_help.oren`
- Output (checked in): `lib/avm/avm_help.inc`

If AVM CLI flags change, regenerate the include by running:

```bash
./oren build tools/gen_avm_help.oren --backend native -o build/gen_avm_help
./build/gen_avm_help > lib/avm/avm_help.inc
make avm
```

### 5.1 Disassemble `.obc`

Build a bytecode artifact:

```bash
./oren build tests/avm/test_time_rng_deterministic.oren --backend bytecode -o build/tmp.obc
```

Disassemble code only:

```bash
./avm --disasm build/tmp.obc
```

Disassemble with constants:

```bash
./avm --disasm-consts build/tmp.obc
```

Machine-readable disassembly (JSON):

```bash
./avm --disasm-json build/tmp.obc
```

Machine-readable disassembly including constants:

```bash
./avm --disasm-consts-json build/tmp.obc
```

Inspect `.obc` metadata (otool-like header/policy scan) without executing bytecode:

```bash
./avm --inspect build/tmp.obc
```

Machine-readable JSON form (scan-only):

```bash
./avm --inspect-json build/tmp.obc
```

### 5.2 Trace execution

Trace all executed instructions (prints to stderr):

```bash
./avm --trace build/tmp.obc
```

Trace only the first N executed steps (helps avoid huge logs):

```bash
./avm --trace-limit 2000 build/tmp.obc
```

Notes:

- Trace is best-effort and rolling; it is intended as a foundation for a real interactive bytecode debugger (breakpoints/step/inspect).
- For deterministic workflows, pair trace with `--print-result-hash` and/or record/replay logs for reproducible diagnosis.

### 5.3 Breakpoints + stack inspection (debugger baseline)

Pause before executing the instruction at a given bytecode `pc`:

```bash
./avm --breakpc 74 --print-stack build/tmp.obc
```

Notes:

- When a breakpoint triggers, AVM uses the existing “paused” exit code (`2`) so it composes with snapshot/resume.
- `--step-limit 1` can be used as a crude “single-step” mode (pause after 1 executed opcode).
- For machine-readable pause state (for building an external debugger loop), use `--print-pause-json`:

```bash
./avm --step-limit 1 --print-pause-json build/tmp.obc
```

### 5.4 Heap/memory stats (leak profiling helper)

Print a best-effort summary of reachable heap objects:

```bash
./avm --print-mem-stats build/tmp.obc
```

This is not a replacement for Instruments/leaks, but it is a fast way to see:

- how many strings/bytes/lists/maps are reachable
- approximate total heap footprint from VM roots + constant pool

### 5.5 macOS leak workflow (Instruments / `leaks`)

For “real” leak hunting on macOS, use system tools in addition to `--print-mem-stats`.

1) **Fast check** (leaks at exit):

```bash
./oren build tests/avm/test_time_rng_deterministic.oren --backend bytecode -o build/tmp.obc
leaks --atExit -- ./avm build/tmp.obc
```

If you want to amplify leaks in-process (more realistic for “long-running agent host” scenarios), use the built-in repeat loop:

```bash
./avm --repeat 200 --print-mem-stats --print-rss build/tmp.obc
```

If you want a **deterministic allocation profile** (no Instruments, machine-readable), capture trace bytes and decode them:

```bash
AVM_TRACE_BYTES=$((4*1024*1024)) ./avm --print-trace-bytes-hex build/tmp.obc | ./tools/avm_trace_profile.py --from-stdin
```

Notes:

- `--print-rss` reports the current process resident size (best-effort; `RSS_BYTES_ERROR` if unavailable).
- `--repeat` is intentionally not compatible with `AVM_RECORD_LOG` / `AVM_REPLAY_LOG` (use `AVM_RECORD_MEM` / `AVM_REPLAY_LOG_HEX` instead).

2) **Instrumented profiling** (GUI):

- Open Instruments → “Leaks” / “Allocations”
- Run `./avm build/tmp.obc`
- Look for growth across repeated runs; consider adding a loop in the `.oren` test to amplify leaks

Notes:

- The AVM heap is currently manual (malloc/free). Any missing frees will show up quickly under nested universes or record/replay-heavy tests.
- Prefer fixing ownership/clone rules at capability boundaries (e.g., AVM-in-AVM) rather than adding ad-hoc frees.
