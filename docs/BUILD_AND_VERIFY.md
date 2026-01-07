# Building and Verifying Oren

This guide documents the complete process of building the Oren compiler from source (bootstrapping), using it to build applications, and validating Tier‑1 targets in rolling mode (including remote x86_64 workflows where needed).

## 1. Bootstrapping Oren (Stage 0 to Self-Hosting)

Oren is a self-hosted language. The repository contains a "Stage 0" compiler written in Go, which is used to compile the "Stage 1" compiler (written in Oren). Stage 1 can then compile itself to produce Stage 2, proving self-hosting capability.

### Prerequisites
- **Go 1.20+**: To build the Stage 0 bootstrap compiler.
- **C Compiler**: Required by the C backend (used for stage0 → stage1 bootstrapping).
  - macOS/Linux: `clang`/`gcc`
  - Windows x64: Visual Studio 2022 Build Tools (`cl.exe`) is the preferred Tier‑1 bring-up path.
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

Windows notes (x64, rolling):

- Prefer `make stage1` / `make oren` rather than calling the bootstrap directly.
  - The Makefile passes `--cc` via `OREN_BOOTSTRAP_CC` (defaults to `cl` on Windows hosts).
- If invoking stage0 directly on Windows, the canonical form is:

```bash
oren_bootstrap.exe build oren.oren --target windows --cc cl -o oren.exe
```

- When `--cc cl` is selected, stage0 attempts to auto-configure the MSVC environment by locating
  VS2022 via `vswhere.exe` and running `VsDevCmd.bat` / `vcvars64.bat` in a child `cmd.exe` session.
- C-backend outputs run the program entrypoint on a fresh OS thread with a larger stack by default
  (to avoid stack overflow in self-hosted compiler workloads). Override via:
  - `OREN_MAIN_STACK_SIZE` (decimal bytes; default: 64 MiB; min: 1 MiB)

### Step 3: Verify Self-Hosting (Stage 2)
Use the Stage 1 compiler (`oren`) to compile the Oren source code again. The resulting binary should be identical in function to Stage 1.

```bash
make stage2
```

Notes (rolling, important):

- `make stage2` is the repo-supported entrypoint because the bootstrap backend can vary by host architecture.
  - Default (2026-01-04+): Stage 2 is bootstrapped via the **native backend** on Tier‑1 hosts (including macOS arm64).
  - If you need the legacy C-backend bootstrap for bring-up, use: `make stage2 OREN_STAGE2_BACKEND=c`.
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

### Native Runtime Bundle Cache (Native Backend)

The native backend injects the native runtime bundle into every native build:
- default (non-capsule): `lib/runtime_native.oren` (expanded from `lib/runtime_native/**`)
- capsule builds: `lib/runtime_native_capsule.oren` (expanded from `lib/runtime_native/**`)
On stage2-native compilers this can dominate build time, so the compiler maintains a separate (non-artifact) cache for the runtime **AST**:

- default cache dir: `build/cache/native_runtime_astbin/`
- key: rolling v2 fast fingerprint of the fully expanded runtime source (legacy SHA-256 cache files are still supported and auto-migrated)
- disable: `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0`
- override cache dir: `OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR=<dir>`
- optional seed dir (fast cold-cache; esp. capsule): `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=<dir>` (default: `build/cache/native_runtime_astbin_seed/`; disable with `0`/`false`)
  - generator: `make astbin-seed` (uses stage1 `./oren` to pre-warm)
  - `make astbin-seed` is best-effort and skips work if the seed already exists; force refresh with `OREN_FORCE_RUNTIME_ASTBIN_SEED=1`

Troubleshooting overrides (force a specific input, bypassing default behavior):

- `OREN_NATIVE_RUNTIME_EXPANDED=<path>`: use a pre-expanded runtime file (skips include expansion)
- `OREN_NATIVE_RUNTIME_ASTBIN=<path>`: force loading a specific runtime astbin file
- `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=<dir>`: runtime-astbin seed dir used as a fallback on astbin cache misses
  - default: `build/cache/native_runtime_astbin_seed/`
  - disable with `0` / `false`
  - generate/update with:
    - `make astbin-seed` (host platform; runs as part of `make stage2`)
    - `make astbin-seed-x64` (cross-target seeds for `x64-linux`/`x64-windows`; used by `make verify-native-x64-compile`)

Runtime profile (rolling, perf-oriented):

- `OREN_NATIVE_RUNTIME_PROFILE=core` (or `minimal`) uses a reduced runtime entry file (`lib/runtime_native_core.oren`)
  for non-capsule builds, intended to keep **cold rtobj misses bounded** on stage2-native compilers.
- Default (unset / `full`) keeps the full runtime (`lib/runtime_native.oren`).
- Seed tooling: `make astbin-seed` now also generates a seed astbin for the core runtime profile (in addition to full + capsule).

Stage0 bootstrap constraint (keep stage1 buildable):

- Avoid nested named function declarations (`fn name(...) { ... }` inside another function) in compiler sources; stage0 transpilation treats them as unsupported.

Tracing knobs (bounded output; prints timing summaries):

- `OREN_TRACE_RUNTIME_BUNDLE=1`: runtime expand/parse/cache timings
- `OREN_TRACE_ASTBIN=1`: astbin decode timings (and v2 pool size)
- `OREN_TRACE_BUILD_SUMMARY=1`: prints a single `[build] summary ...` line per `oren build` (native backend path)
- `OREN_TRACE_BUILD_SLOW_MS=<n>`: only print the summary when the build takes at least `<n>` ms (implies summary enabled)
- rtobj build breakdown (bounded):
  - `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1`
  - `OREN_TRACE_X64_RT_OBJ_SUMMARY=1`
  - `OREN_TRACE_{ARM64,X64}_RT_OBJ_TOP_DECLS=1` (prints only a small “top decls” list)

Performance guardrails and “what to do when it gets slow” live in:

- `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`

### Native Runtime Object Cache (Native Backend; Tier‑1 throughput)

For Tier‑1 native backends, injecting *and compiling* the full native runtime can still dominate “compile one file” throughput.
To avoid paying that cost on every invocation, the compiler can cache a backend-specific compiled runtime “object” and splice it into the output.

Rolling notes:

- The cache is **disabled for capsule builds** by default (until it can live inside the capsule boundary).
- Supported today: arm64 + x86_64 native backends.

Environment knobs:

- disable: `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`
- override cache dir: `OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR=<dir>` (default: `build/cache/native_runtime_obj/`)
- optional seed dir (fast first-run): `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=<dir>` (default: `build/cache/native_runtime_obj_seed/`; disable with `0`/`false`)
- tracing (bounded): `OREN_TRACE_RUNTIME_OBJ_CACHE=1`

Seed notes (rolling):

- The seed is a normal rtobj cache entry copied to a stable location and used as a fallback on cache misses.
- Generate/update it with:
  - `make rtobj-seed` (also runs as part of `make stage2`)
  - `make rtobj-seed-x64` (cross-target seeds for `x64-linux`/`x64-windows`; used by `make verify-native-x64-compile`)
  - or `./scripts/build_rtobj_seed.sh --platform <arch-os>`

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
The recommended fast path on macOS is to run native backend tests directly, without an extra repo runner layer:

```bash
# Fast smoke (single integrated test)
make test-native-quick

# Stage1 + Stage2 native smoke
make verify-native-quick

# Broader native coverage (all tests/native/*.oren)
make test-native-all
```

Cross‑arch Tier‑1 matrix (stage1 + stage2):

```bash
# Local arm64-macos + docker arm64-linux (no remote required)
./scripts/verify_native_matrix.sh --targets local,arm64-linux

# Full matrix (requires the persistent linux container + remote x64 host)
./scripts/verify_native_matrix.sh

# Loopback-only NET matrix (TCP/UDP + HTTP GET loopback + WebSocket echo)
./scripts/verify_native_net_matrix.sh

# x86_64 self-host: run the compiler binary on remote Win11 + WSL2 and compile+run a tiny program
./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win

# Local sanity gate: compile-only for x64-linux + x64-windows (stage1 + stage2)
make verify-native-x64-compile
```

Makefile shortcuts (macOS/arm64 host workflow):

```bash
make verify-native-matrix
make verify-native-net
make verify-selfhost-x64
make verify-tier1
```

Notes (host assumptions, rolling):

- `scripts/verify_native_matrix.sh` is written for the primary dev workflow: **arm64 macOS host** + persistent Linux container + remote Win11/WSL2 for x86_64 execution.
- If you are not on arm64 macOS, prefer:
  - `make verify-native-quick` (host-native smoke)
  - `make verify-native-x64-compile` (x86_64 compile-only sanity)
  - and run x86_64 outputs on their actual target hosts.

Rolling hang guard:

- `scripts/verify_native_matrix.sh` and the x64 compile-only gate apply a per-build timeout
  (`OREN_NATIVE_BUILD_TIMEOUT_SECS`, default `10`) to keep regressions actionable.

Environment knobs:

- `OREN_TEST_JOBS` (default `4`): parallelism for module + AVM tests.
- `OREN_NO_GC=1`: disable GC scanning for stress/debug.

Timeout behavior (rolling):

- The Makefile will use `timeout`/`gtimeout` as an extra *outer* failsafe when available.
- Installing coreutils on macOS is still recommended for a stronger outer guard:
  - `brew install coreutils`

## 3. Using FFI (Foreign Function Interface)

Oren can call external C symbols via `ffi <name>` when using the **native backend**.

Current status:
- **macOS (Mach-O):** uses dyld binding opcodes and GOT stubs; this enables basic FFI against `libSystem` and any dylibs you load via `--link`.
- **Windows x64 (PE):** uses lazy `LoadLibraryA`/`GetProcAddress` stubs; `--link` adds DLLs to the resolver search list (kernel32 is searched by default).
- **Linux (ELF):**
  - **x64-linux:** `--link` enables a dynamically-linked ELF, and `ffi` works via a lazy `dlsym` resolver (see `docs/NATIVE_BACKEND.md`).
  - **arm64-linux:** dynamic linking is not implemented yet; calling an `ffi` symbol panics and `--link` is rejected.

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

To link arbitrary libraries portably (or on Linux arm64 today), use the C backend:

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

2.  **Linux Native Backend Support (rolling)**:
    - **x64-linux:** minimal dynamic linking is implemented for `ffi` (via `dlsym`); shared libraries (`--lib`) are still not implemented.
    - **arm64-linux:** ELF dynamic linking is not implemented yet.

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

#### Running the native test suite on the remote host

For Linux parity work, run the native backend suite on a real Linux ARM64 host:

```bash
# On the Linux ARM64 machine (after cloning/copying the repo):
make stage1
make test-native-all
make stage2
make test-native-quick-stage2
```

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
