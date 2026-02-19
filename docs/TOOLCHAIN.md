# Toolchain and Verification (Rolling)

This document consolidates build, test, and self-hosting workflows.

## Building and Verifying Oren

This guide documents the complete process of building the Oren compiler from source (bootstrapping), using it to build applications, and validating Tier‑1 targets in rolling mode (including remote x86_64 workflows where needed).

For a concise “what is Tier‑1 and how do I prove it” index, see `docs/PLATFORMS.md`.

## 1. Bootstrapping Oren (Stage 0 to Self-Hosting)

Oren is a self-hosted language. The repository contains a "Stage 0" compiler written in Go, which is used to compile the "Stage 1" compiler (written in Oren). Stage 1 can then compile itself to produce Stage 2, proving self-hosting capability.

### Prerequisites
- **Go 1.20+**: To build the Stage 0 bootstrap compiler.
- **C Compiler**: Required by the C backend (used for stage0 -> stage1 bootstrapping).
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
  - The Makefile passes `--cc` via `OREN_BOOTSTRAP_CC` (defaults to `cl.exe` on Windows hosts).
  - The Makefile also passes an explicit `--target` via `OREN_BOOTSTRAP_TARGET` (defaults to the host OS) so stage0 behavior is predictable on non-macOS hosts.
  - Rolling note: Windows host detection in the Makefile does not rely solely on `OS=Windows_NT` or `uname` output; it also treats `SystemRoot`/`WINDIR`/`COMSPEC`/`PATHEXT`/`PROCESSOR_ARCHITECTURE` as Windows host hints (useful in minimal shells / CI / some SSH environments).
- For MSVC-only helper builds outside the compiler (example: building the Win32 GUI shim DLL), prefer:
  - `scripts/win_msvc_cmd.cmd <cmd> ...`
  - This runs one command under a VS/MSVC environment without requiring a VS Developer Prompt.
- If invoking stage0 directly on Windows, the canonical form is:

```bash
oren_bootstrap.exe build oren.oren --target windows --cc cl -o oren.exe
```

- When `--cc cl` is selected, stage0 attempts to auto-configure the MSVC environment by locating
  VS2022 via `vswhere.exe` and running `VsDevCmd.bat` / `vcvars64.bat` in a child `cmd.exe` session.
  - If your Windows environment is non-standard (custom VS install paths, CI images, minimal shells), you can override:
    - `OREN_MSVC_VSWHERE=<full\\path\\to\\vswhere.exe>` (skip default probing)
    - `OREN_MSVC_INSTALL_PATH=<full\\path\\to\\Visual Studio\\...>` (skip `vswhere.exe` entirely)
    - `OREN_MSVC_DEV_CMD=<full\\path\\to\\VsDevCmd.bat|vcvars64.bat>` (force the devcmd script directly)

- Rolling (2026-01-09+): the self-hosted compilers (`oren.exe`, `oren_stage2.exe`) also use the same MSVC auto-configuration path
  when building **C backend** outputs on Windows:
  - Windows default: if `--cc` is not specified, C-backend builds default to `cl.exe` (instead of `cc`).
  - When `--cc` is `cl`/`cl.exe`/`clang-cl`, the compiler emits a temporary `.cmd` wrapper that:
    - resolves VS via `vswhere.exe` (or `OREN_MSVC_INSTALL_PATH`),
    - calls `VsDevCmd.bat` / `vcvars64.bat`,
    - invokes `cl.exe` with a minimal `/std:c11` compile+link arg set.
  - Optional override: `OREN_MSVC_DEV_CMD=<full\\path\\to\\VsDevCmd.bat|vcvars64.bat>` (force the devcmd script directly).
  - Cross-compile note (rolling): building **C backend** outputs that target `windows` from a non-Windows host is not a first-class path.
    - If you are not on Windows and you pass `--platform x64-windows --backend c`, you must also pass an explicit `--cc` that is a Windows cross toolchain (e.g. MinGW) to opt in intentionally.
    - The default Windows `cl.exe` auto-detection only applies when the compiler is running on a Windows host.

Windows native backend notes (x64, rolling; 2026-01-09+):

- Native backend filesystem syscalls on Windows normalize portable `'/'` separators to Win32 `'\\'` at the intrinsic boundary
  (CreateFileA/DeleteFileA/MoveFileExA/CreateDirectoryA), so compiler/runtime code can keep using POSIX-style paths.
- `oren_system(...)` on Windows executes `cmd.exe /C <cmd>` and must preserve *shell* semantics (quoting + redirection).
  The native runtime therefore passes the command string through to `cmd.exe` without CRT-style argv re-escaping (needed for `>nul 2>nul`).
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
    - On Windows hosts, the Makefile defaults the stage2 C-backend toolchain to MSVC `cl.exe` (because `cc` often does not exist).
      - Override: `make stage2 OREN_STAGE2_BACKEND=c OREN_STAGE2_CC=clang` (or another gcc/clang-style toolchain in MSYS2).
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

- Default (unset / `auto`): the compiler selects the injected runtime profile automatically:
  - **core** for typical programs (smaller runtime; bounded cold rtobj misses)
  - **full** when the program imports `std:net/*` (needs runtime TCP/UDP/etc primitives)
- `OREN_NATIVE_RUNTIME_PROFILE=core` (or `minimal`) forces the reduced runtime entry file (`lib/runtime_native_core.oren`).
- `OREN_NATIVE_RUNTIME_PROFILE=full` forces the full runtime (`lib/runtime_native.oren`).
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

- `docs/BACKENDS.md#native-backend-performance-playbook`

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
#   build/targets/<arch>-windows/<backend>/<basename>.exe   (native/c, Windows target)
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

- A Linux/Windows native artifact may not be runnable on a macOS host. Use a Linux machine or the Win11 (WSL2 optional) remote workflow (`docs/PLATFORMS.md`) to execute x86_64 outputs.
- The x86_64 native backend is Tier‑1 intent but still in bring-up; `docs/TODOS.md` tracks what is implemented today.
- Native builds embed best-effort debug info for stack traces by default (rolling ergonomics). Disable with `--no-debug` or `OREN_NATIVE_NO_DEBUG=1`.

### C Backend (Portable)
Transpiles Oren to C, then compiles with the system C compiler (`cc`). Best for stability and platform compatibility (x86_64, etc.).
By default, the build pipeline passes **-O2** (or **/O2** for MSVC) for C-backend performance.

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

# x86_64 self-host: run the compiler binary on remote Win11 (WSL2 optional) and compile+run a tiny program
./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win

# Remote host note (rolling):
# - current reachable host: pc2.work via proxy
# - remote staging should use G:\work (C: is full on the host)
# - set env overrides as documented in docs/PLATFORMS.md

# Optional: stage0->stage1 bootstrap on native Windows using MSVC cl.exe (VS2022)
./scripts/verify_stage0_windows_bootstrap.sh

# Optional: stage0->stage1->stage2 self-host build on native Windows (stage1 builds stage2 via native backend)
./scripts/verify_windows_stage2_from_stage1.sh

# Notes:
# - When this gate fails, it stores bounded diagnostics under:
#   - `project-doc/remote/<timestamp>/stage1_build_stage2.log` (full remote build log, best-effort download)
#   - `project-doc/remote/<timestamp>/stage2_windows_env.log` (small environment snapshot: cl.exe/link.exe/vswhere.exe presence)

# Local sanity gate: compile-only for x64-linux + x64-windows (stage1 + stage2)
make verify-native-x64-compile

# Higher-signal local gate: compile the compiler program for x64 targets (compile-only)
# - defaults to `oren_x64.oren` (x64-focused; avoids compiling arm64 native backends into x64 artifacts)
# - override with `OREN_SELFHOST_SRC=oren.oren` to force the full multi-target compiler graph
make verify-native-x64-selfhost-compile

# Compile-only shared-library emission on all Tier‑1 targets (no foreign execution):
# - builds `examples/libmath.oren --lib` for arm64-linux + x64-linux + x64-windows
# - validates the generated header, `oren scan` output, and `file` kind checks
make examples-cross-compile-smoke
```

## Local x64-linux execution (QEMU in the Linux container)

For a higher-signal local gate (without remote WSL2), run a small x64-linux runtime smoke under `qemu-x86_64`
in the persistent Linux container:

```bash
make verify-x64-linux-qemu
```

This runs a small curated set of fixtures (stage1 + stage2) to catch x64-linux runtime/codegen regressions
that compile-only checks cannot detect.

### Optional: local x64-linux NET loopback execution (QEMU)

To also cover the loopback networking surface (TCP/UDP/DNS/HTTP/WS) under QEMU:

```bash
# One-time setup to install an amd64 glibc loader in the persistent container:
make setup-x64-linux-qemu

# Then run the NET loopback fixtures (stage1 + stage2):
make verify-x64-linux-qemu-net
```

### Optional: local x64-linux TLS/HTTPS/WSS loopback execution (QEMU)

TLS/HTTPS/WSS fixtures need an OpenSSL runtime in the container (amd64). Install it once:

```bash
OREN_X64_LINUX_QEMU_INSTALL_OPENSSL=1 make setup-x64-linux-qemu
```

Then run the loopback TLS/HTTPS/WSS fixtures (stage1 + stage2) under `qemu-x86_64`:

```bash
make verify-x64-linux-qemu-tls
```

Makefile shortcuts (rolling):

```bash
make verify-native-matrix
make verify-native-net
make verify-selfhost-x64
make verify-stage0-win
make verify-stage2-win
make verify-tier1
```

Notes (host assumptions, rolling):

- `scripts/verify_native_matrix.sh` is written for the primary dev workflow: **arm64 macOS host** + persistent Linux container + remote Win11/WSL2 for x86_64 execution.
  - The entrypoint is host-agnostic (Makefile → script), but the *default workflow* still assumes those prerequisites.
- If you are not on arm64 macOS, prefer:
  - `make verify-native-quick` (host-native smoke)
  - `make verify-native-x64-compile` (x86_64 compile-only sanity)
  - and run x86_64 outputs on their actual target hosts.

Rolling hang guard:

- `scripts/verify_native_matrix.sh` and the x64 compile-only gate apply a per-build timeout
  (`OREN_NATIVE_BUILD_TIMEOUT_SECS`, default `10`) to keep regressions actionable.

Rolling perf guard (recommended before merging hot-path changes):

```bash
# Ensure stage2-native compile-one-file (rtobj hit) stays under threshold.
make perf-guard-native-hit
```

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
- **macOS (Mach-O):** uses dyld binding opcodes and GOT stubs; this enables basic FFI against `libSystem` and any dylibs you load via `--link` / `@ffi.link(...)`.
- **Windows x64 (PE):** uses lazy `LoadLibraryA`/`GetProcAddress` stubs; `--link` / `@ffi.link(...)` adds DLLs to the resolver search list (kernel32 is searched by default). For convenience, `@ffi.dll("name.dll")` can attach a DLL directly to an `ffi` declaration.
- **Linux (ELF):**
  - **x64-linux:** dynamic linking is enabled when at least one link dependency exists (via `--link` or `@ffi.link(...)`), and `ffi` works via a lazy `dlsym` resolver (see `docs/BACKENDS.md#native-backend-overview`).
  - **arm64-linux:** same as x64-linux (see `docs/BACKENDS.md#native-backend-overview`).

### Usage
Declare the external symbol using the `ffi` keyword, then call it like a regular function.

**Example (`examples/ffi_test.oren`):**
```oren
// Cross-platform FFI example: call C `puts`.

@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi puts

@cfg(os="linux")
@ffi.link("libc.so.6")
ffi puts

@cfg(os="macos")
ffi puts

fn main() {
    puts("Hello from C FFI!")
}
```

Portable linking note (stdlib-style):

- You can attach link dependencies directly to an `ffi` declaration:
  - `@ffi.link("...")` (maps to native `--link ...`)
  - `@ffi.dll("...")` (Windows-only convenience; prefer `@ffi.link` for cross-platform code)

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

To link arbitrary libraries portably, use the C backend:

1.  **Use the C Backend**: The C backend allows you to pass arbitrary linker flags.
    ```bash
    # Generate C code
    ./oren build examples/myapp.oren --backend c --emit-c
    
    # Compile manually with your libraries
    cc -O2 -o myapp examples/myapp.oren.c lib/runtime.c -Ilib -pthread -lcurl
    ```

    **On Windows (MSVC/CL):**
    ```powershell
    # Compile generated C code with CL.exe
    # Ensure you are in a Developer Command Prompt
    cl /O2 /Fe:myapp.exe examples/myapp.oren.c lib/runtime.c /Ilib user32.lib kernel32.lib
    ```

2.  **Linux Native Backend Support (rolling)**:
    - **x64-linux:** dynamic linking is implemented for `ffi` (via `dlsym`), and native shared libraries are implemented (`--lib` → ELF `.so`).
    - **arm64-linux:** dynamic linking is implemented for `ffi` (via `dlsym`), and native shared libraries are implemented (`--lib` → ELF `.so`).

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

Notes (toolchain):

- On macOS/Linux, `make avm` uses `AVM_CC` (default: `cc`) and should work out of the box if a C compiler is installed.
- On Windows hosts, stage0/stage1 bring-up prefers MSVC `cl.exe`, but **AVM is built with a gcc/clang-style compiler**.
  - If `make avm` fails due to missing `cc`, install MSYS2 clang (or llvm-mingw) and run: `make avm AVM_CC=clang`.

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

## Test System (Direct, No Runner)

This repo is intentionally in **rolling ABI** mode. The testing constraint is:

- iteration must be **fast**
- tests must **never hang forever**
- failures must be **actionable** (logs, minimal noise)

The current approach is **direct compilation + direct execution** using the compiler binaries
(`./oren` and `./oren_stage2`) rather than a separate repo test runner.

Rolling note:

- There is no external “`oretest`” runner in this repo anymore; the supported entrypoints are the Makefile targets
  (`make test`, `make verify-*`) and the scripts under `scripts/`.

## What “tests” mean in this repo

`tests/` contains multiple categories:

- `tests/native/*.oren`: programs intended to be compiled with `--backend native` and executed on the host OS
- `tests/modules/*.oren`: module-/stdlib-heavy programs (some are written without a `main()` and execute via top-level statements)
- `tests/avm/*.oren`: programs intended for the AVM workflow (`--backend bytecode` + `./avm`)
- `tests/fixtures/*.oren`: fixtures for compile-time contracts (many are expected failures under specific flags)

Rolling note (fixtures vs ABI):

- Some Tier‑1 fixtures use **test-only runtime hooks** (example: `oren_green_debug_*`) to make scheduling regressions deterministic while the native scheduler is still evolving.
  - Those hooks are not stable ABI and should not be used in stdlib or user-facing examples.
  - Reference: `docs/STDLIB_AND_RUNTIME.md` (“Test-only debug API: `oren_green_debug_*`”).

Rolling rule: **Oren source should be backend-universal** when the program is within the supported feature set of that backend.
When a source file is intended to be backend-specific (e.g. AVM domain tests), it should be documented as such in-file.

Import hygiene (rolling):

- Prefer `import x "std:..."` in tests (e.g. `import http "std:net/http"`).
  - This exercises the stdlib module resolver directly and prevents drift where tests accidentally depend on repo-relative paths that real user code would not use.
- Repo-relative imports are still valid when you are intentionally importing a local fixture module (example: `import fixture "./fixture_tls_p12.oren"`).

## Platform portability (and why `@cfg` appears in tests)

Goal: a large fraction of Oren source should be **portable across Tier‑1 OS/arch** (and ideally across backends), and the test suite should reinforce that.

However, some tests (especially `tests/native/*.oren`) necessarily touch **OS-specific primitives**:

- process lifecycle details (how to exit from a worker thread vs the main thread),
- socket API differences (WinSock vs BSD sockets),
- platform TLS providers (macOS Security.framework vs Windows Schannel vs Linux OpenSSL),
- filesystem and path quirks (drive letters, `\` vs `/`),
- availability of syscalls and ABI details.

In rolling mode, those differences are expected. The practical question is: how do we keep the tests **portable in intent** without writing four entirely separate copies?

### The recommended pattern: “shared core + tiny `@cfg` glue”

Use `@cfg(...)` to keep the majority of the logic shared, and isolate the OS-specific differences into small wrappers.

Why this is safe:

- `@cfg(...)` is evaluated at compile time for the selected `--platform`.
- When a declaration does not match its `@cfg`, it is **removed from the program** before later compiler passes (so it should not affect typechecking/lowering on other platforms).
  - Reference: `docs/LANGUAGE_APPENDICES.md` (“Conditional compilation”).

Example pattern (schematic):

```oren
fn server_impl() { /* shared logic */ return 0 }

@cfg(os="windows")
fn main_server() { return server_impl() } // Windows: returning from main is fine.

@cfg(os="linux,macos")
fn main_server() { return server_impl() } // POSIX: return value becomes main exit status.
```

The TLS/HTTPS/WSS loopback fixtures follow this pattern: core server/client logic is shared, and only the “how do we start/stop the server” glue varies by OS.

Concrete examples from current fixtures (why the glue is necessary):

- Windows: `spawn` is thread-based. A loopback server can run in-process on a worker thread, and the client can `join` it.
- macOS: the TLS provider is built on Apple Security/CoreFoundation APIs. Calling those APIs in a post-`fork()` child without `exec` is not guaranteed to be safe, so the TLS loopback server uses a **fork+exec** pattern (single binary invoked with a `server` argv) instead of a pure in-process thread/server model.
- Linux: uses a normal `spawn` server path for loopback fixtures (process boundary via the current native runtime model), but still shares the same protocol-level assertions (pinning, echo, ALPN wiring where supported).

The goal is: same test intent (protocol behavior) across Tier‑1 targets, with only the minimum OS glue necessary to make that intent deterministic.

## Fast native verification (macOS/Linux host)

These targets are intended to be runnable without additional tooling:

```bash
# Build stage1 compiler
make stage1

# Default fast gate: stage1 + stage2 + capsule (native-only)
make test

# Build stage2 compiler
make stage2

# Fast native integration smoke (stage2; single entry file with includes)
make test-native-quick-stage2

# Convenience alias (same as `make test`)
make verify-native-quick
```

For broader native coverage:

```bash
make test-native-all
```

Operational note (rolling):

- When running a compiled native test binary directly (outside the Makefile targets), wrap it with `timeout`/`gtimeout` to keep the “tests must never hang forever” rule true for ad-hoc repros too (and to avoid leaving long-lived `build/tmp/test_*` processes behind if a regression hangs).
- Emulated/slow environments (example: `qemu-x86_64` under the persistent Linux container) can legitimately need larger join deadlines for heavy scheduler fixtures.
  - Opt-in knob: set `OREN_TEST_SLOW=1` to scale a small set of timeouts inside `tests/native/test_quick_integration_native.oren` while keeping defaults strict on Tier‑1 hosts.
- The quick integration fixture is a single entry file that expands compile-time includes:
  - Entry: `tests/native/test_quick_integration_native.oren`
  - Segments: `tests/native/qi/*.oren` (kept <2k LOC per file)

Perf tripwire (rolling):

```bash
# Ensure “compile one file” rtobj-hit stays under the configured threshold.
make perf-guard-native-hit
```

Note (rolling):

- `tests/native/*.oren` includes a few **platform-specific** fixtures used by the Tier‑1 scripts (example: `ffi_windows_*`, `ffi_linux_*`).
- `make test-native-all` skips those by filename prefix so it remains runnable on the current host OS.

## AVM verification (bytecode)

The default `make test` target is intentionally **native-only and bounded**.
For AVM/bytecode regression coverage, use:

```bash
make test-avm
```

Notes:

- `test-avm` compiles each selected `tests/avm/*.oren` into `.obc` and runs it under `./avm`.
- By default it runs a curated list (`AVM_TESTS` in `Makefile`) for iteration velocity.
  - Override for full coverage: `make test-avm AVM_TESTS="tests/avm/*.oren"`.

## Cross-arch native verification (Tier‑1 matrix)

When you need confidence that the **native backend** output works across the practical Tier‑1 matrix
(without relying on a separate test runner), use the purpose-built scripts under `scripts/`:

```bash
# Local (arm64-macos): stage1 + stage2 build+run
./scripts/verify_native_matrix.sh --targets local

# Linux/arm64 via the persistent container (stage1 + stage2 artifacts)
./scripts/verify_native_matrix.sh --targets arm64-linux

# Full matrix: local + linux/arm64 container + remote x64 Win11 (+ WSL2 when available)
./scripts/verify_native_matrix.sh

# Dev convenience: keep local + docker arm64-linux, but skip remote Win11/WSL2 (explicit opt-in)
./scripts/verify_native_matrix.sh --skip-remote

# Opt-in: run the larger Tier‑1 native smoke fixture on remote x64 hosts
./scripts/verify_native_matrix.sh --targets x64-win-tier1
./scripts/verify_native_matrix.sh --targets x64-wsl-tier1
  # Note: Tier‑1 matrix targets also run a small set of green-worker (GMP) fixtures when using the default
  # Tier‑1 source (`tests/fixtures/tier1_native_smoke_main.oren`). This keeps cross-arch coverage aligned with
  # the current scheduler focus without making the default `all` target slower.
  # Use `--tier1-src <path>` to override the Tier‑1 program and skip the extra green-worker fixture set.

# Loopback NET matrix (TCP/UDP + HTTP GET loopback + WebSocket echo) across Tier‑1 hosts
./scripts/verify_native_net_matrix.sh

# Dev convenience: run local + docker arm64-linux, but skip remote Win11/WSL2 (explicit opt-in)
./scripts/verify_native_net_matrix.sh --targets local,arm64-linux --skip-remote

# x86_64 self-host: the compiler binary itself runs on Win11 (and WSL2 when available) and can compile+run a tiny program
./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win
# If WSL2 is unavailable, use:
# ./scripts/verify_selfhost_x64_compiler.sh --targets x64-win

# Optional: stage0->stage1 bootstrap on native Windows using MSVC cl.exe (VS2022)
./scripts/verify_stage0_windows_bootstrap.sh

# Local gate: compile-only for x64-linux + x64-windows (stage1 + stage2)
make verify-native-x64-compile
```

Makefile shortcuts (rolling):

```bash
make verify-native-matrix
make verify-native-matrix-skip-remote
make verify-native-net
make verify-native-net-skip-remote
make verify-selfhost-x64
make verify-stage0-win
make verify-tier1
```

Rolling guardrails:

- The matrix script uses short timeouts to avoid hangs.
- It does **not** start containers; it expects the existing linux container to be running.
- The scripts intentionally avoid requiring `rg` / ripgrep on minimal environments (remote Win11/WSL2, containers); they use `grep`/`findstr` and keep logs bounded.
  - Note: the compiler/runtime do not shell out to `rg`; this is purely a developer convenience tool.
- Per-build timeout can be tuned via `OREN_NATIVE_BUILD_TIMEOUT_SECS` (default: `10`).
- x86_64 correctness tripwire: set `OREN_CANON_I32_ABORT=1` to hard-fail on “non-canonical i32” values
  (a common symptom of partial-width stores / ABI mismatches in the x64 native backend).

## Why some fixtures use `@cfg(...)`

Oren’s goal is that most Tier‑1 fixtures are **platform-neutral** and exercise the same logic on
`arm64-macos`, `arm64-linux`, `x64-windows`, and `x64-linux`.

However, a small amount of `@cfg(os=...)` glue is still sometimes necessary at the **platform boundary**:

- FFI library naming / attachment (`@ffi.link("...")` vs `@ffi.dll("...")`).
- OS-specific process semantics (e.g. TLS loopback servers may use `fork+exec` on macOS to avoid
  fork-unsafety around Security/CoreFoundation; see `docs/NETWORKING_IO.md`).
- Temporary bring-up gaps (e.g. POSIX pipe-fd readiness is not supported on Windows yet; Windows has a rolling select-v0 socket netpoll path,
  but IOCP integration is still pending for production-grade readiness and for any future HANDLE-based readiness story).

Rule of thumb (rolling):

- Keep the *core test logic* shared; put `@cfg` only around the smallest OS-specific hook needed.
- Avoid `exit(...)` inside spawned workers; return values are the portable join contract (see
  `docs/LANGUAGE_MANUAL.md` spawn notes).

## Quick perf check (compile-one-file)

When investigating “why did `oren build` take >10s?” regressions, use the bounded benchmark helper:

```bash
./scripts/bench_native_compile_one_file.sh
./scripts/bench_native_compile_one_file.sh --debug --trace
```

For a deeper “what regressed and how do we keep it bounded” playbook (rolling):

- `docs/BACKENDS.md#native-backend-performance-playbook`

## Logs and artifacts

- Logs:
  - `build/logs/*`
- Native test artifacts created by the quick smoke:
  - `build/tmp/*_native_quick_integration`

The goal is that any failure leaves a single stable log file that can be inspected directly.

## Toolchain Self‑Hosting (Status + Gate Plan)

This doc answers a recurring question in rolling mode:

> “Is the Oren compiler mature enough to self-host the entire tool system (tests, fmt, LSP, package manager, source + `.obc` distribution)?”

## Current state (facts in this repo)

Oren is already **partially self-hosting**:

- **Stage 1 compiler** `./oren` is built by the **Go bootstrap** `./oren_bootstrap` (`make stage1`).
- **Stage 2 compiler** `./oren_stage2` is built by **Stage 1** (`make stage2`).
  - Rolling default: `make stage2` bootstraps stage2 via the **native backend** on arm64‑macOS.
  - Bring‑up fallback: `make stage2 OREN_STAGE2_BACKEND=c`.
- The **metadata tool** is **Go**: `./oredoc` (`cmd/oredoc`).
- The **signing tool** is **Go**: `./orensign` (`cmd/orensign`).
- The **AVM interpreter** is **C**: `./avm` (sources under `lib/avm/`).

So today, the compiler can compile itself (stage2), but the repo toolchain is still a **mixed bootstrap stack**:

```
Go: oren_bootstrap / oredoc / orensign
Oren: oren / oren_stage2 (compiler)
C: avm (VM)
```

This is consistent with the roadmap stance in `docs/STATUS_AND_ROADMAP.md`: keep bootstrapping practical until language + runtime contracts stabilize.

## What “full self-hosted toolchain” actually requires

Self-hosting the compiler *itself* is a narrower bar than self-hosting “tooling”:

### A) `oren fmt` (formatter)

Minimum requirements:

- A stable **parser** that can round-trip with enough syntax metadata to preserve intent (comments, whitespace, string literal forms, etc), or a deliberate “canonical formatting” policy.
- A stable **AST** representation (internal is fine) and output printer with deterministic emission.

Formatter is usually the **first** tool worth self-hosting because it can be:

- offline
- deterministic
- not latency-sensitive like an LSP

### B) `oren lsp` (language server)

LSP is the hardest to self-host early because it benefits from:

- **error recovery** parsing (must build partial ASTs on invalid code)
- **incremental** analysis (document edits, file watchers, caches)
- semantic indexing (symbol tables across modules)
- stable JSON-RPC IO and concurrency primitives

Today we can build an LSP sooner by:

1) keeping the server in Go (fast iteration) and invoking `./oren` as a library/process, or
2) exporting a stable machine interface (`oren --emit-json ast|diag|symbols`) and writing the LSP around that.

Self-hosting the LSP in Oren becomes realistic once:

- module resolution rules are stable
- compiler diagnostics are stable and machine-readable
- stdlib has robust FS/process/JSON IO on macOS/Linux/Windows

### C) Oren-native test runner (future)

Right now the repo runs tests via **direct compilation + direct execution** of test programs using `./oren` and `./oren_stage2` (see `docs/TOOLCHAIN.md`).
There is no external test runner binary in-tree; the canonical flows are `Makefile` targets and `scripts/` helpers (for example `scripts/verify_native_matrix.sh` for remote x86_64 verification).

A self-hosted replacement would require:

- a stable `tests/manifest` format (or `tests/*.oren` conventions)
- stable process spawning + timeouts + log capture
- cross-platform file operations

This is very achievable later, but it should be **gated** (see below) so we don’t regress reliability during rolling refactors.

### D) Package manager (source + `.obc`)

A real package manager requires more than “downloading some files”:

- **Module identity**: name, version, and provenance (git URL or registry ID)
- **Reproducibility**: lockfile pinned revisions + hashes
- **Caching**: build cache keyed by (compiler version, target, flags, package hash)
- **Distribution**:
  - source distribution (build locally)
  - `.obc` distribution (precompiled bytecode for AVM execution)
  - optionally native artifacts (per-OS/arch)

If the end-goal includes AVM multiverse updates and signed modules, the package manager needs to integrate with the trust model in:

- `docs/AVM_ROADMAP.md`
- `docs/OBC_DISTRIBUTION.md`
- `docs/TOOLCHAIN.md`

In other words: the package manager is also a **supply chain system**, not just a convenience.

## Is Oren “mature enough” today?

### Compiler self-hosting: **yes, gated**

We already build Stage 2 from Stage 1, which is the key “compiler can compile itself” milestone.

But “no Go anywhere” is **not** true today, because Stage 0 and key tools are still Go.

### Toolchain self-hosting: **not yet (but can start in slices)**

The fastest way to reach a production-grade toolchain without stalling compiler work is:

1) Keep the current Go tools as “production runners” (stable, cross-platform),
2) Add **Oren-native prototypes** behind explicit gates,
3) Promote them only when they meet strict reliability/perf criteria.

## Gate plan (recommended)

Treat self-hosting as a staged migration with explicit acceptance tests:

1) **Gate 0 (today)**: Go bootstrap + Go repo tooling is canonical; Oren compiler evolves quickly.
2) **Gate 1 (fmt)**: add `oren fmt` (even if it only supports a stable subset first).
3) **Gate 2 (pkg)**: add `oren pkg` with:
   - local path deps + git deps (pinned)
   - lockfile
   - cache dir conventions
   - optional signing hooks (`orensign`) for `.obc`
4) **Gate 3 (test runner)**: Oren-native runner that can execute a curated manifest, with hard timeouts.
5) **Gate 4 (LSP)**: only after error-recovery parsing + stable diagnostics + module graph caching exist.

Each gate should include:

- correctness suite (native backend + AVM + cross-platform where applicable)
- determinism checks (stable outputs)
- cross-platform checks (macOS + Linux + Windows, x64+arm64 where applicable)

## Connection to `oren-packages`

Even if a “packages repo” exists, a package manager needs a **spec**:

- package manifest format (name/version/deps/targets)
- dependency resolution rules
- build artifact layout and caching keys
- signature and verification metadata for `.obc`/OBX (if used)

Until those are specified, a packages repo is useful mainly as:

- a place to host canonical libraries
- a testbed for module resolution rules

Once the spec exists, the repo can become a real registry mirror or a git-based index.

## Self-Hosting (Stage0 -> Stage1 -> Stage2)

Oren is a self-hosted language:

- **Stage0**: a small compiler written in Go (`./cmd/oren`) used only for bootstrapping.
- **Stage1**: the compiler written in Oren (`oren.oren`), built by Stage0.
- **Stage2+**: Stage1 rebuilds itself, proving self-hosting.

This repo intentionally supports multiple backends (C / native / bytecode). Self-hosting uses whichever backend is practical for the platform and phase.

Authoritative end-to-end instructions live in `docs/TOOLCHAIN.md` (this file is a conceptual overview).

## Backends (context)

### C backend (portable bootstrapping path)
The C backend transpiles Oren to C, then relies on the host C toolchain to compile/link. This is still the “most portable” path and remains useful as a fallback.

For details, see `docs/BACKENDS.md#c-backend-design-and-abi`.

### Native backend (syscall-first, no host SDK headers)
The native backend emits Mach-O (macOS arm64) or ELF (Linux arm64) directly.

Design constraints and ABI tables are documented in `docs/BACKENDS.md#native-backend-overview`.

### Bytecode backend (AVM)
The bytecode backend emits `.obc` for the AVM prototype.

## How the C backend targets C (historical + still relevant)
- **Boxed values**: every Oren value is an `OrenValue` (ints/floats/bools/strings, lists, maps, and optionally wrapped Python objects).
- **Generated C shape**:
  - `#include "runtime.h"`
  - `OrenValue` globals for top-level `var` declarations
  - forward declarations for named `fn`s
  - constructor functions for `struct`/`class` declarations (`Type__new`)
  - C functions for each named `fn` (each returns `OrenValue`)
  - `int main(int argc, char **argv)` which calls `oren_init(argc, argv);`, initializes globals, then runs top-level statements
- **Example lowering**:
  - Oren: `var x = 1 + 2; print(x)`
  - C (roughly): `x = oren_add(oren_int(1), oren_int(2)); oren_print(x);`
- **Lowering strategy**: expressions become calls to runtime helpers:
  - arithmetic/comparisons: `oren_add`, `oren_eq`, `oren_lt`, …
  - literals: `oren_int(...)`, `oren_float(...)`, `oren_string(...)`, `OREN_TRUE/OREN_FALSE/OREN_NIL`
  - list/map literals: `oren_new_list(n, ...)`, `oren_new_map(n, k1, v1, ...)`
  - indexing: `oren_list_get(container, index)`
  - index assignment: `oren_index_set(container, index, value)`
  - member access: `oren_get_attr(obj, "name")`
  - member assignment: `oren_set_attr(obj, "name", value)`
- **Optional Python FFI** (disabled by default):
  - build with `--python` (or compile with `-DOREN_ENABLE_PYTHON` and link libpython via `python3-config`)
  - `py_import("module")` becomes `oren_py_import(...)`
  - calls on Python objects route through `oren_call_obj(...)`
  - `py_release(obj)` decrements the Python refcount for a wrapped `py_obj` (returns `nil`)

## Modules (`import`) at Compile Time
Oren modules are file-based and resolved at compile time:
- `import math "path/to/math.oren"` loads and transpiles that file, binding `math` as a **namespace**.
- All imported modules (and the entry file) are merged into **one** emitted C translation unit (`<entry>.oren.c`).
- To avoid global symbol collisions, each imported module is assigned a unique prefix (`m0`, `m1`, …) and its top-level symbols are renamed:
  - `var pi` in module `math.oren` might become `m0__pi` in C
  - `fn add(a,b)` might become `m0__add`
- Namespace member access lowers to the renamed symbol:
  - `math.pi` → `m0__pi`
  - `math.add(1, 2)` → `m0__add(oren_int(1), oren_int(2))`
- Import paths are resolved relative to the importing file’s directory; cyclic imports are rejected.

## Structs / Classes
`struct` and `class` are currently “data-only” and compile down to runtime maps:
- A declaration like `struct Point { x, y }` generates a constructor `Point__new(x, y)` that returns `oren_new_map(2, "x", x, "y", y)`.
- `Point(1, 2)` is shorthand for calling the constructor (`Point__new(1, 2)`).
- Field access uses the runtime attribute helpers:
  - `p.x` → `oren_get_attr(p, "x")`
  - `p.x = v` → `oren_set_attr(p, "x", v)`

## Self-Hosting Pipeline (Go only for stage0)
The intended flow is “stage0 builds stage1; stage1 rebuilds itself” (similar to Zig).

### One-command bootstrap
```sh
make bootstrap
```

### Manual bootstrap
1) Build the stage0 compiler (Go) as `oren_bootstrap`:
```sh
go build -o oren_bootstrap ./cmd/oren
```
2) Use stage0 to build the stage1 compiler (Oren) from `oren.oren`:
```sh
./oren_bootstrap build oren.oren   # produces ./oren
```
3) Use stage1 to rebuild itself (stage2) without Go:
```sh
make stage2
```

Rolling note (important):

- Stage1 (`./oren`) and Stage2 (`./oren_stage2`) are **separate binaries**.
- If you change compiler sources (parser/AST/lowering/backends) and then start using new syntax in stdlib/tests,
  you must rebuild Stage2 (`make stage2`) before running any workflow that invokes `./oren_stage2`.
  Otherwise Stage2 may reject the new syntax even if Stage1 accepts it.

Native backend option (syscall-first Mach-O/ELF emitter):
```sh
./oren build oren.oren --backend native --platform arm64-macos -o build/oren_stage2_native
```

Notes:
- The native backend path depends on a small “compiler subset” of the native runtime being present (e.g. `oren_string_to_float_bits`, `oren_sha256_range`, `oren_chmod`, `oren_env`). This repo treats that subset as a self-hosting stability gate.
- `make stage2` is the repo-supported entrypoint because the bootstrap backend can vary by host architecture:
  - Default (2026-01-04+): Stage 2 is bootstrapped via the **native backend** on Tier‑1 hosts (including macOS arm64).
  - Fallback (bring-up): `make stage2 OREN_STAGE2_BACKEND=c`.
  - Stage 2 still supports `--backend {c|native|bytecode}`; it is built from the same compiler sources as Stage 1 (check `./oren_stage2 --help`).

4) From here on, you can keep rebuilding without Go:
```sh
./oren_stage2 build oren.oren -o oren_stage3
```

## Using the Self-Hosted Compiler
Use `./oren build ...` explicitly. The default backend is intentionally configurable and may change during rolling development.

Recommended:

- C backend: `./oren build hello.oren --backend c -o hello`
- native backend: `./oren build hello.oren --backend native -o hello`
- bytecode backend: `./oren build hello.oren --backend bytecode -o hello.obc`

To emit C only (C backend):
```sh
./oren build hello.oren --backend c --emit-c
```

## How `oren` Builds a Binary
The high-level pipeline is:

1) Read `.oren` sources
2) Lex/parse into an AST
3) Resolve imports and link into a program model
4) Run lowering passes (attributes, ABI layout, packed-byte views, etc.)
5) Emit:
   - C (`--backend c`)
   - native Mach-O/ELF (`--backend native`)
   - AVM bytecode (`--backend bytecode`)

For the C backend, the toolchain invocation is explicit and overrideable (see `docs/BACKENDS.md#c-backend-design-and-abi`).

If you prefer to compile the generated C yourself, use `--emit-c` and then run the compile/link step manually.

## Runtime Helpers Used By The Compiler
- `oren_args()` returns CLI args as a list of strings.
- `oren_read_file(path)` / `oren_write_file(path, content)` are used to implement a “compiler reads source, writes C” workflow.
- `oren_system(cmd)` is used to invoke the C compiler.
- `oren_exit(code)` is used to exit with a non-zero status on build failure.

## Notes on build artifacts (`*.oren.c`)
The C backend can write `*.oren.c` files (when `--emit-c` is used).

This repo’s canonical test runners avoid generating `*.oren.c` in-tree by default to prevent accidental Makefile implicit-rule coupling.
See `docs/TODOS.md` rule “Never generate `*.oren.c` next to sources” and `docs/TOOLCHAIN.md` for the migration plan.

## CLI Completion (bash / zsh)

Oren ships a built-in completion generator:

- `oren completion bash`
- `oren completion zsh`

The generated scripts are intentionally minimal and deterministic:

- Completes subcommands (`build`, `meta`, `dump`, …)
- Completes option *names* (e.g. `--backend`, `--target`)
- Completes a small set of enum-like option *values*:
  - `--backend={c|native|bytecode}`
  - `--target={macos|linux|windows}` (rolling)
  - `--arch={arm64|x64}` (rolling)
  - `--stdlib-mode={source|obc}`
  - `--help=json` / `-h=json`
- Completes `oren dump <kind>` where `<kind>` is one of `tokens|linked|graph`
- Does basic file completion for common positionals (e.g. `oren build <file>`, `oren meta <file>`, `oren dump <kind> <file>`, `oren scan <lib>`)

It does **not** currently validate combinations or suggest paths with type filters (e.g. only `*.oren`).

## Bash

One-shot for the current shell session:

```bash
source <(oren completion bash)
```

To enable permanently, add to `~/.bashrc`:

```bash
source <(oren completion bash)
```

## Zsh

One-shot for the current shell session:

```zsh
source <(oren completion zsh)
```

To enable permanently, add to `~/.zshrc`:

```zsh
source <(oren completion zsh)
```

## Notes

- Because the completion scripts are generated from the compiler’s current CLI spec, upgrading Oren automatically upgrades completion.
- If you package Oren as a release artifact, you can also ship the completion scripts by capturing them at build time:
  - `oren completion bash > oren.bash`
  - `oren completion zsh > _oren`

## macOS Codesigning & Notarization

On macOS, the OS security model can reject/kill unsigned executables (especially newly-built binaries in developer workflows). To keep local iteration smooth, Oren uses **ad-hoc signing** by default for macOS native outputs.

## Defaults (rolling)

- For `--backend native --target macos`, `oren build` defaults to **ad-hoc signing**:

```bash
codesign -s - --force <output>
```

- To sign for distribution, pass a Developer ID identity:
  - `--codesign "Developer ID Application: ..."`
  - or env `OREN_CODESIGN_ID="Developer ID Application: ..."`

- Oren’s macOS-native outputs are expected to be signed for local execution. Disabling signing is not supported because the OS may kill the process at runtime.

- `OREN_SKIP_CODESIGN=1` is rejected on macOS (the Makefile and both compiler frontends error out).

- Deterministic builds (`--deterministic`) are defined as “minimize post-processing that mutates the emitted artifact bytes”.
  On macOS this means the compiler intentionally does **not** automatically run `codesign` for deterministic outputs (because signing mutates the file).

  You still must sign native outputs to run them locally; a deterministic output is therefore **not guaranteed runnable** on macOS until you sign it (for local use, ad-hoc signing is typically sufficient). If you need both:
  - keep an unsigned deterministic artifact for reproducibility, and
  - sign a separate copy for local execution.

```bash
codesign -s - --force <output>
```

Important nuance: signing after the fact can make the file no longer byte-for-byte identical to the deterministic pre-sign output. The deterministic flag is intended for reproducible build artifacts, not for “runnable without signing”.

## Embedded signatures (compiler)

- The Mach-O emitters do **not** attempt to embed a custom code signature blob.
- For reliable local execution on macOS, the build pipeline signs outputs externally via `codesign` (ad-hoc by default).

## Notarization

- `--notarize [--notary-profile name]` submits via `xcrun notarytool` and staples the ticket.
- Notarization requires a **Developer ID** identity; it is rejected when:
  - `--codesign` is missing
  - or `--codesign -` (ad-hoc)

## Installing a signing identity

1. Open Xcode → Settings → Accounts, sign in with your Apple Developer account.
2. Select your team → **Manage Certificates…** → press `+` and create **Developer ID Application**.
3. Confirm the cert exists in your login keychain:

```bash
security find-identity -v -p codesigning
```

## Distribution notes

- End users **do not** need your certificate installed. A Developer ID–signed, notarized binary satisfies Gatekeeper.
- For local experiments/testing, ad-hoc signing is sufficient.
