# Building and Verifying Oren

This guide documents the complete process of building the Oren compiler from source (bootstrapping), using it to build applications, and validating Tier‑1 targets in rolling mode (including remote x86_64 workflows where needed).

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
make stage2
```

Notes (rolling, important):

- `make stage2` is the repo-supported entrypoint because the bootstrap backend can vary by host architecture.
  - On `arm64` hosts (macOS arm64 + Linux arm64 container), Stage 2 is currently bootstrapped via the **C backend** because native self-hosting on arm64 is still rolling/unstable.
  - On other hosts, Stage 2 may be bootstrapped via the native backend.
- This does **not** mean Stage 2 “doesn’t have the C backend”: Stage 2 is built from the same compiler sources and supports `--backend {c|native|bytecode}` (check `./oren_stage2 --help`).

---

## 2. Building Applications

Once you have the `oren` executable (Stage 1), you can compile user applications.

### Build Cache (Default On)

`oren build` uses a **default-enabled build cache** (content-addressed) to make repeated builds fast (Go/make-like iteration):

- enabled by default
- default cache location: `./build/cache` (override via `OREN_CACHE_DIR` or `--cache-dir`)
- cache key includes:
  - compiler executable hash (so cache invalidates when `./oren` changes)
  - build flags/target/backend that affect output
  - transitive source closure (imports + `// @include` expansion)
- disable per-invocation: `./oren build --no-cache ...` (or env `OREN_NO_CACHE=1`)
- override cache location: `--cache-dir <dir>` or env `OREN_CACHE_DIR`
- clear cache: `./oren clean` (or `./oren clean --cache-dir <dir>`)

### Native Backend (Tier‑1 intent: arm64 + x86_64)
Compiles directly to machine code (Mach-O / ELF / PE). Fast and dependency-free for the emitted artifact (no libc shims for native output).

```bash
# If you omit `-o/--out`, artifacts default under:
#   build/targets/<arch>-<os>/<backend>/<basename>          (native/c)
#   build/targets/avm/bytecode/<basename>.obc               (bytecode, platform-neutral intent)
#
# Build for macOS arm64 (primary development path today)
./oren build examples/hello.oren --backend native --target macos --arch arm64 -o hello

# Build a Linux ELF (arm64 or x64 depending on your use case)
./oren build examples/hello.oren --backend native --target linux --arch arm64 -o hello_linux_arm64
./oren build examples/hello.oren --backend native --target linux --arch x64   -o hello_linux_x64

# Build a Windows PE32+ executable (x64 bring-up)
./oren build examples/hello.oren --backend native --target windows --arch x64 -o hello_win_x64.exe
```

Notes (rolling):

- A Linux/Windows native artifact may not be runnable on a macOS host. Use a Linux machine or the Win11+WSL2 remote workflow (`docs/REMOTE_X64_ENV.md`) to execute x86_64 outputs.
- The x86_64 native backend is Tier‑1 intent but still in bring-up; `docs/TODOS.md` tracks what is implemented today.
- Native builds embed best-effort debug info for stack traces by default (rolling ergonomics). Disable with `--no-debug` or `OREN_NATIVE_NO_DEBUG=1`.

### C Backend (Portable)
Transpiles Oren to C, then compiles with the system C compiler (`cc`). Best for stability and platform compatibility (x86_64, etc.).

```bash
./oren build examples/hello.oren --backend c -o hello
```

---

## 2.1 Test Runner Timeouts (Rolling Safety)

This repo runs in **rolling ABI** mode, so the priority is fast iteration and avoiding hangs.
The canonical curated runner is:

```bash
./oretest --platform arm64-macos
```

`make test` is a thin wrapper over `./oretest`.
The legacy Makefile-driven suite is still available as `make test-legacy` (broader coverage, slower).

`./oretest` follows the same principles (curated, timeout-protected, failure-only logs), while keeping repo test orchestration out of the self-hosted compiler sources. See `docs/TEST_SYSTEM.md` for the evolution plan.

Environment knobs:

- `OREN_TEST_JOBS` (default `4`): parallelism for module + AVM tests.
- `OREN_NO_GC=1`: disable GC scanning for stress/debug (also available as `./oretest --no-gc`).

Timeout behavior (rolling):

- `./oretest` has internal timeouts and will warn (not fail) if `timeout`/`gtimeout` is missing.
- The Makefile will use `timeout`/`gtimeout` as an extra *outer* failsafe when available.
- Installing coreutils on macOS is still recommended for a stronger outer guard:
  - `brew install coreutils`

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

- SSH: `blu@qemu-blu.local` (or `blu@192.168.66.212`)

Workflow:

1) Cross-compile on macOS (produces an ELF ARM64 binary):

```bash
./oren build tests/native/linux_hello.oren --backend native --target linux -o build/linux_hello
```

2) Copy to the Linux host:

```bash
scp build/linux_hello blu@qemu-blu.local:/home/blu/
```

3) Run it:

```bash
ssh blu@qemu-blu.local "chmod +x linux_hello && ./linux_hello"
```

This avoids maintaining local VM images, and it matches the project direction: **Linux parity early** without slowing down macOS iteration.

#### Running the full curated suite on the remote host

For Linux parity work, it’s more useful to run the curated suite (`./oretest --target linux`) on the Linux ARM64 host.

This repo provides a helper script:

```bash
SSH_DEST=blu@qemu-blu.local ./scripts/oretest_remote_linux_arm64.sh
```

This script does not store credentials; it relies on your SSH config/key and copies the current repo state to the remote host under `/tmp/`.

### Option B (optional): local QEMU VM on macOS

If you prefer local verification, install QEMU:

```bash
brew install qemu
```

### Option C (repo standard): persistent Linux toolchain container (Docker)

This repo also supports running the curated suite inside the already-running Ubuntu toolchain container.
This is the fastest way to validate Linux behavior from a macOS dev host without provisioning a VM.

Repo helper:

```bash
tools/oretest_linux_docker.sh
```

This helper also supports running other high-signal targets inside the same container:

```bash
tools/oretest_linux_docker.sh examples-test
tools/oretest_linux_docker.sh verify
```

Notes (rolling, important):

- This is the **only supported** way to run the curated suite on `linux/arm64` from a macOS host.
  - Do **not** `docker exec ... ./oretest` inside the container: the `./oretest` binary in your repo root is a macOS binary and will fail with “Exec format error”.
  - Prefer either:
    - `./oretest --platform arm64-linux` (delegates to `tools/oretest_linux_docker.sh`), or
    - run the script directly.
- The docker runner syncs **tracked** files into `/work/repo` via `git ls-files` (it does not copy your `.git` dir).
- Because it syncs tracked files only, newly created files must be staged (`git add -A`) before the container will see them (or set `OREN_LINUX_DOCKER_ALLOW_DIRTY=1` for local experiments).
- Do not copy host-built binaries into the container (`./oren`, `./oretest`, `./avm`): they are not runnable on Linux and can also cause Make to incorrectly treat targets as up-to-date.

Environment knobs:

- `OREN_LINUX_DOCKER_ID` (default: `c7e5f7bd9f5c`): persistent container id/name
- `OREN_LINUX_DOCKER_JOBS`: forwarded to `OREN_TEST_JOBS` inside the container
- `OREN_LINUX_DOCKER_ALLOW_DIRTY=1`: allow syncing tracked files even when untracked files exist
- `OREN_LINUX_DOCKER_CLEAN=1`: wipe `/work/repo` before syncing (rarely needed)
- `OREN_LINUX_DOCKER_GOPROXY` / `OREN_LINUX_DOCKER_GOSUMDB`: override Go module mirror settings inside the container (only needed on restricted networks)

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
