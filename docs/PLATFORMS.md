# Platforms and Portability (Rolling)

This document consolidates platform support, portability notes, and remote validation workflows.

## Portability Guide (Rolling): when to use `@cfg`

Oren’s goal is **portable source code** across Tier‑1 targets:

- `arm64-macos`
- `arm64-linux`
- `x64-linux`
- `x64-windows`

The language provides `@cfg(...)` conditional compilation (see `docs/LANGUAGE_MANUAL.md` and
`docs/LANGUAGE_SPEC.md`), but in a production language it should be treated as a **boundary tool**:

- good: isolate unavoidable OS differences behind a stable API
- bad: sprinkle `@cfg` throughout application logic

This document gives concrete rules for *where `@cfg` belongs* in Oren code and tests.

## 1) Rule of thumb

Use `@cfg(...)` only when **the surface you must call does not exist** on another Tier‑1 OS/arch, or
when the ABI/layout is truly platform-specific.

If the code is “regular logic” (parsing, maps/lists, formatting, protocol logic), do **not** use `@cfg`:
push the OS differences into stdlib or into a tiny shim module.

## 2) Prefer stdlib portability over per-file `@cfg`

### Prefer portable APIs

Examples of portable APIs (Tier‑1 intent):

- `std:net/tcp`, `std:net/udp`, `std:net/dns` (network sockets + resolver)
- `std:net/tls` (TLS over sockets)
- `std:crypto/*` (PEM, rand, TLS core helpers)
- `std:ui/*` (retained-mode UI core: layout/render/raster; OS integration is a shim)

If you need to `@cfg` around a commonly-used concept, that is usually a signal that the stdlib is
missing a “portable core + per-platform backend” split.

### Example pattern: portable API + `@cfg` backend selection

The recommended shape is:

- one portable module exports the public API
- per-platform modules implement the OS-specific pieces and are `@cfg`-gated
- consumers import only the portable module

Sketch:

```oren
// std:crypto/tls_provider (portable surface)
fn tls_client_connect(...) {
    return _tls_client_connect_impl(...)
}

@cfg(os="windows") fn _tls_client_connect_impl(...) { return schannel_connect(...) }
@cfg(os="macos")   fn _tls_client_connect_impl(...) { return securetransport_connect(...) }
@cfg(os="linux")   fn _tls_client_connect_impl(...) { return openssl_connect(...) }
```

The key constraint is: the public API should remain stable; only the private implementation changes.

## 3) FFI: avoid `@cfg` by using portable aliases when available

If the intent is “call libc”, do not write three variants:

```oren
@cfg(os="linux")  @ffi.link("libc.so.6") ffi { ... }
@cfg(os="macos")  @ffi.link("libSystem.B.dylib") ffi { ... }
@cfg(os="windows") @ffi.dll("msvcrt.dll") ffi { ... }
```

Prefer:

```oren
@ffi.libc
ffi { /* ... */ }
```

Notes:

- `@ffi.libc` is the portability mechanism; it keeps library naming out of user code.
- Use `@cfg` for FFI only when there is **no** portable alias and the ABI truly differs.

## 4) Tests/fixtures: keep `@cfg` at the boundary

Tier‑1 fixtures are part of the “living spec”. They should be:

- small
- deterministic
- **portable**

If a fixture needs platform glue, the preferred approach is:

1) keep the core test logic portable (protocol logic, state machines, invariants)
2) gate only the platform-specific declarations:
   - FFI imports / DLL names (if no alias exists)
   - syscall struct layouts
   - OS-only behavior knobs required to run the test safely

Bad pattern (hard to maintain):

- `@cfg` inside core logic branches for “how the algorithm works”.

Good pattern:

- `@cfg` is used only to select *how to access the same abstract capability* on each platform.

### Why fixtures sometimes still use `@cfg`

Some subsystems legitimately have different host constraints:

- TLS providers differ per OS (SChannel / SecureTransport / OpenSSL)
- process spawning APIs differ (Win32 CreateProcess vs POSIX fork/exec)
- UI needs OS windowing APIs (Win32/X11/Cocoa)

The correctness requirement is: those differences must be hidden behind a stable userland API, and the
portable logic (including protocol semantics) should not fork into per-OS variants.

## 5) When `@cfg` is unavoidable

Use `@cfg` when:

- you are writing a thin OS bridge (syscalls, windowing, IOCP/epoll/kqueue)
- the ABI layout or calling convention differs (FFI return kinds, struct packing)
- you are binding to an OS-owned subsystem where “portable emulation” would be incorrect or unsafe

In those cases:

- keep the `@cfg` module small
- keep the stable API above it strict and well-tested
- add a Tier‑1 gate so regressions are caught early


## Tier‑1 Support Matrix (Rolling)

This document is a *fact-based* index of what Oren intends to support as “Tier‑1”, and **how to verify it**.
It is not a promise that every cell is currently green; the goal is to make gaps explicit and to keep the
verification commands easy to run.

If this file disagrees with reality, treat the verification commands (and their results) as the source of truth,
then update this doc in the same change.

## Tier‑1 targets (goal)

Tier‑1 is defined as:

- `arm64-macos` (primary dev host)
- `arm64-linux` (Linux/aarch64 via the pinned toolchain container)
- `x64-linux` (Linux/x86_64)
- `x64-windows` (Windows 11 + MSVC/VS2022; remote host)

## Backends (compiler outputs)

Oren can emit three “families” of artifacts:

- **Native backend**: target-native machine code + runtime capsule (intended: Tier‑1 across all targets).
- **C backend**: C code + host C toolchain (used by stage0 bootstrap; also supported as a backend).
- **AVM bytecode**: portable `.obc` intended to be platform-neutral (still treated as rolling until fully proven).

FFI portability note (rolling):

- When importing from the platform C library, prefer `@ffi.libc` (portable alias) instead of per‑OS library names.
  - Tier‑1 mapping: Windows=`msvcrt.dll`, Linux=`libc.so.6`, macOS=`libSystem.B.dylib`.
  - See: `docs/LANGUAGE_APPENDICES.md` (`@ffi.libc`) and fixture `tests/native/ffi_libc_portable.oren`.

## Stage pipeline (self-host)

Definitions:

- **stage0**: `./oren_bootstrap` (Go; uses C backend)
- **stage1**: `./oren` (self-hosted)
- **stage2**: `./oren_stage2` (self-hosted; default rolling compiler)

### What “Tier‑1 self-host” means

For a target `<arch>-<os>`, the Tier‑1 goal is:

1) Stage0 can build stage1 for that OS (bootstrap path)
2) Stage1 can build stage2 (native backend)
3) Stage2 can compile and run representative programs (native + runtime), including sensitive surfaces:
   - FFI ABI correctness
   - GC + allocator safety
   - Threads/tasks/async runtime surfaces (as they evolve)
   - NET/TLS/HTTP/WS loopback where applicable

## Verification commands (how to prove it)

The Makefile and `scripts/` define the *supported* verification entrypoints. Prefer these over ad-hoc commands.

### Local (host)

The primary development host is `arm64-macos`, but the Makefile verification entrypoints are intentionally
host-agnostic (they delegate to `scripts/` which enforce prerequisites and/or select the right execution mode).
When a command is host-specific (e.g. “remote Windows”), it is called out explicitly.

- Build stage1 + stage2 (native backend): `make stage2`
- Fast stage1 + stage2 smoke (native): `make verify-native-quick`
- Perf tripwire (rtobj-hit compile-one-file bound): `make perf-guard-native-hit`
- Compile-only cross x64 targets (native backend): `make verify-native-x64-compile`
  - This compile-only gate also covers native shared-library emission (`--lib`):
    - `x64-linux`: ELF `.so` + generated header
    - `x64-windows`: PE `.dll` + generated header
- Compile-only shared-lib emission across all Tier‑1 targets (no foreign execution): `make examples-cross-compile-smoke`
- Execute x64-linux artifacts (QEMU): `make verify-x64-linux-qemu`
- Execute x64-linux NET fixtures (QEMU): `make verify-x64-linux-qemu-net`
- Execute x64-linux TLS fixtures (QEMU): `make verify-x64-linux-qemu-tls`

### Cross-host matrix (local + container + remote)

These scripts are the intended long-run gate for Tier‑1 parity:

- Native quick integration matrix (stage1 + stage2): `./scripts/verify_native_matrix.sh`
- NET/TLS/HTTP/WS loopback matrix (stage1 + stage2): `./scripts/verify_native_net_matrix.sh`
- x64 self-host parity (stage2 correctness on real x86_64): `./scripts/verify_selfhost_x64_compiler.sh`

See `docs/PLATFORMS.md` for how the remote Windows host (WSL2 optional) is configured and how logs are fetched.

HTTP/2 note (rolling but verified):

- HTTP/2 is implemented as a deterministic framing + HPACK bring-up layer and is verified by the NET matrix
  (ALPN `h2`, preface, SETTINGS/ACK, PING/ACK, HEADERS/CONTINUATION/DATA loopback).
  - Source: `lib/std/net/http2.oren`, `lib/std/net/hpack.oren`
  - Evidence: `tests/native/test_http2_*_loopback.oren` (see `docs/STATUS_AND_ROADMAP.md`)

### Remote connectivity (fact-based)

Some networks/proxies do not resolve the default remote hostname (`pc.work`). When remote access is unavailable,
prefer keeping local gates green (`make verify-native-x64-compile`, QEMU x64-linux), and collect logs when
the host becomes reachable again.

Remote override knobs:

- `OREN_REMOTE_X64_HOST=<user@IP>` (recommended when `pc.work` is not resolvable)
- `OREN_REMOTE_X64_PROXY=` (empty to disable the proxy if you have direct SSH access)

## Windows toolchain policy (MSVC bring-up)

For Tier‑1 Windows, the intended C toolchain is **MSVC (VS2022) `cl.exe`**.

- Stage0 (`oren_bootstrap.exe`) supports `--cc cl` and will auto-configure the MSVC environment by locating
  VS via `vswhere.exe` and calling `VsDevCmd.bat` / `vcvars64.bat` before invoking `cl.exe`.
- Stage1/stage2 (self-hosted compilers) default `--cc` to `cl.exe` **only on Windows hosts** when targeting
  the Windows C backend, and use a similar “temporary `.cmd` wrapper” technique to avoid quoting pitfalls.
- Cross-compiling C-backend outputs to Windows from a non-Windows host is intentionally *not* implicit; it
  requires an explicit `--cc` cross toolchain (opt-in, e.g. MinGW).

## Current high-leverage gaps (keep this short)

When something is not green, record the *smallest actionable next step* and the verification that must be made green.

- x64-windows: stage2 native backend still needs continuous “compile + run” proof on a real Windows host
  (not just compile-only from macOS).
  - Primary gates:
    - `./scripts/verify_selfhost_x64_compiler.sh --targets x64-win` (compiler runs on Win11 and compiles+runs a tiny native program)
    - `./scripts/verify_windows_stage2_from_stage1.sh` (stage0→stage1→stage2 on Win11)
  - Last known green (fact): 2026-01-13 (see `docs/TODOS.md`).
- Remote reliability: keep remote log capture bounded and reproducible; use
  `scripts/fetch_remote_file.sh --analyze` + `scripts/analyze_stage2_failure_log.sh` for triage.
  - If the build appears to hang, enable bounded parse progress for include-aggregators:
    - `OREN_REMOTE_PROGRESS=1 make verify-stage2-win` (rate-limited; avoids huge logs).

## Cross-platform path robustness

- Oren accepts Windows-style `\` separators in CLI paths across hosts (macOS/Linux/Windows). This is a
  correctness requirement because remote Win11 logs/scripts often contain backslash paths.
  - Gate: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` includes a Windows backslash-path compile+run step.

## Remote x86_64 Dev Environment (Win11, WSL2 optional) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host (WSL2 optional).

Rolling note (2026-02-13):

- The current reachable host is `pc2.work` (Win11 online via proxy).
- WSL2 is **not installed/enabled** on that host yet, so x64-linux run gates are currently blocked there.
- Direct SSH (key auth, no password prompt):
  - `ssh -o 'ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' xue@pc2.work`

## Terminology: platform, target, and the remote x64 gate

- For direct compilation, prefer the unified platform flag on the compiler:
  - `./oren build ... --platform <arch>-<os>`
  - env fallback: `OREN_PLATFORM=<arch>-<os>` is used when `--platform` is not provided.
  - if neither is provided, the compiler defaults to the **runtime host platform** (Windows uses env vars; POSIX uses `uname`).
  - `--target`/`--arch` are legacy (still supported).

## Keeping the remote checkout + binaries in sync (common pitfall)

The Tier‑1 scripts in `scripts/` do **not** require a working compiler checkout on the remote Win11 host:
they compile artifacts locally and upload binaries to the remote machine for execution.

However, when debugging by **logging into the remote machine** and running `oren.exe` / `oren_stage2.exe` directly
from a repo clone (example path: `E:\\work\\oren-lang`), it is easy to hit a mismatch:

- the remote repo is behind `origin/master`, and/or
- the remote `oren_stage2.exe` was built from older sources (pulling new commits does **not** rebuild the binary).

Symptom class (example):

- `x64 pe: failed to write: build/targets/x64-windows/native/...` (older logs may omit `.exe`; current default outputs on Windows targets include `.exe`)
- `write_bytes: sys_open failed`
  - On current `origin/master`, Windows `sys_open` maps `GetLastError()` to a POSIX-like `-errno`,
    so the compiler should also print a meaningful `write error code=<n>` (e.g. `2` for ENOENT, `13` for EACCES).

If you see this kind of failure, first do the “sync + rebuild” sequence:

```bat
cd /d E:\work\oren-lang
git fetch --all --prune
git reset --hard origin/master
make stage2
```

Then re-run the failing `oren_stage2.exe build ...` invocation.

## Preferred workflow: use the repo’s x64 matrix script (stage1 + stage2)

If your local host is macOS arm64 (Tier‑1 dev path), the recommended way to validate x86_64 targets is:

```bash
# Runs x64-linux under WSL2 (if available) and x64-windows under cmd.exe on the remote Win11 host.
# Also builds the artifacts locally (stage1 + stage2) before copying/running them remotely.
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win

# If WSL2 is not available, run Windows-only:
./scripts/verify_native_matrix.sh --targets x64-win
```

Host/proxy overrides (rolling ergonomics):

```bash
# If the default hostname (pc.work) is not resolvable from your current network,
# set the host to a reachable IP or DNS name.
export OREN_REMOTE_X64_HOST='lzbgt@203.0.113.10'

# Alternate host (2026-02-13): pc2.work is online via the same proxy.
# No password needed (SSH key already installed on the host).
export OREN_REMOTE_X64_HOST='xue@pc2.work'
export OREN_REMOTE_X64_PROXY='ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002'

# If you have direct SSH access (no ProxyCommand), disable the proxy.
# (Most scripts also accept `--no-proxy` explicitly.)
export OREN_REMOTE_X64_PROXY=''

# If the default hostname (pc.work) is not resolvable from your current network,
# override the host explicitly (IP or resolvable DNS).
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win --host 'lzbgt@203.0.113.10'

# If you have direct SSH access (no ProxyCommand), disable the proxy (socat not required).
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win --host 'lzbgt@203.0.113.10' --no-proxy
```

Remote staging root overrides (useful when `C:` is full):

```bash
# Example: move remote staging to G:\work\tmp_oren on pc2.work.
export OREN_REMOTE_X64_HOST='xue@pc2.work'
export OREN_REMOTE_X64_PROXY='ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002'
export OREN_REMOTE_X64_WIN_ROOT='G:\\work\\tmp_oren'
export OREN_REMOTE_X64_WSL_ROOT='/mnt/g/work/tmp_oren'
export OREN_REMOTE_X64_SSH_ROOT='G:/work/tmp_oren'
```

Rolling note (2026-02-13):

- The pc2.work Win11 host has a full `C:` drive; use the `G:\work\...` roots above.
- WSL2 is currently not installed/enabled on pc2.work, so `x64-wsl` targets are blocked there.

Notes:

- Keep the three roots in sync:
  - `OREN_REMOTE_X64_WIN_ROOT` is the Windows path used by `cmd.exe`.
  - `OREN_REMOTE_X64_WSL_ROOT` is the WSL path for the same directory.
  - `OREN_REMOTE_X64_SSH_ROOT` is the scp/sftp path (Windows OpenSSH).
- If you only set `OREN_REMOTE_X64_WIN_ROOT`, the scripts attempt to derive `SSH_ROOT` and `WSL_ROOT`.

## NET loopback matrix (TCP/UDP + HTTP GET loopback)

The Tier‑1 matrix script focuses on a broad native smoke (containers, strings, maps, proc, etc),
but it does not exercise TCP/UDP/HTTP.

To validate Oren’s **native NET substrate** on real x86_64 hosts (Win11, WSL2 optional), run:

```bash
# Builds stage1 + stage2, compiles the NET suites for x64-windows and x64-linux,
# uploads to the remote Win11 host, then runs:
#   - tests/native/test_net_suite.oren
#   - tests/native/test_http_get_loopback.oren
./scripts/verify_native_net_matrix.sh --targets x64-wsl,x64-win

# If WSL2 is not available, run Windows-only:
./scripts/verify_native_net_matrix.sh --targets x64-win
```

Rolling IOCP note:

- `OREN_NETPOLL_WIN_IOCP=1` enables the IOCP **wake** substrate.
- Socket readiness stays on select‑v0 unless `OREN_NETPOLL_WIN_IOCP_READY=1` is also set.

## Optional: x64 self-host compiler gate (compiler runs on x86_64)

`verify_native_matrix.sh` focuses on **running native programs** built by the compiler.

To close the remaining “x64 gap”, we also need the **compiler binary itself** (`oren_stage2` built for x64)
to run on x86_64 hosts and compile+run a tiny native program.

This is intentionally **opt-in** because building the compiler for x64 can be slow on cold caches.

Rolling status:

- As of 2026-01-08, the x64 self-host compiler run gate passes on the remote Win11 (WSL2 optional) host (when WSL2 is available).

```bash
# Builds x64-linux and x64-windows compiler binaries (native backend),
# copies them + a minimal runtime source bundle to the remote Win11 machine,
# then runs:
#   - x64-linux compiler under WSL2
#   - x64-windows compiler under cmd.exe
# to compile+run a tiny `print.oren`.
#
# Important: the remote `oren_selfhost_*` invocations intentionally omit `--platform` so this gate also
# proves the compiler’s host auto-detection works correctly on WSL2 and native Windows.
./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win

# If WSL2 is not available, run Windows-only:
./scripts/verify_selfhost_x64_compiler.sh --targets x64-win

# Note: this gate defaults to building `oren_x64.oren` (x64-focused compiler source) so the build stays bounded.
# Override to force the full compiler graph:
#   OREN_SELFHOST_SRC=oren.oren ./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win
```

## Optional: stage0 -> stage1 bootstrap on Windows (MSVC)

This repo still relies on the Go bootstrap compiler (stage0) to build the stage1 compiler via the **C backend**.
To support native Windows bring-up, we also keep a small regression gate that proves:

- stage0 (Go) can build stage1 on **x64-windows** using VS2022 `cl.exe` (auto-configured via `vswhere.exe` + `VsDevCmd.bat` / `vcvars64.bat`)
- the resulting stage1 executable can run on Windows and compile+run a tiny native program

Notes (MSVC bootstrap overrides):

- `OREN_MSVC_VSWHERE=<path>` can pin the `vswhere.exe` location if it isn't in a standard install directory / PATH.
- `OREN_MSVC_INSTALL_PATH=<path>` can bypass `vswhere.exe` entirely (useful for custom CI images).

```bash
./scripts/verify_stage0_windows_bootstrap.sh
```

Makefile shortcut (arm64 macOS host workflow):

```bash
make verify-stage0-win
```

## Optional: stage1 builds stage2 on native Windows (self-host build)

To fully close the Windows native-backend parity gap, we also keep an opt-in gate that proves:

- stage0 builds stage1 on Windows (MSVC `cl.exe`)
- stage1 builds stage2 on Windows (native backend)
- stage2 compiles+runs a tiny native program on Windows (with `OREN_CANON_I32_ABORT=1` guard enabled)

```bash
./scripts/verify_windows_stage2_from_stage1.sh
```

Log capture (rolling):

- On failure, the script prints only a tail of the remote build log to keep output bounded.
- It also attempts to download the **full** remote stage1->stage2 build log into:
  - `project-doc/remote/<timestamp>/stage1_build_stage2.log`

- It also captures a small **Windows environment snapshot** (best-effort) into:
  - `project-doc/remote/<timestamp>/stage2_windows_env.log`
  - This is intentionally bounded and helps diagnose “not in PATH” issues (`cl.exe`, `link.exe`, `vswhere.exe`)
    when the remote host is not a full VS Developer Prompt environment.
  - This is best-effort (SSH/SCP path semantics can vary across Win11 OpenSSH environments).

Makefile shortcut (arm64 macOS host workflow):

```bash
make verify-stage2-win
```

Tuning knobs (env):

- `OREN_STAGE2_BUILD_TIMEOUT_SECS` (default `240`, rolling guard for stage1->stage2 self-host build on Windows)

Local Windows note (rolling):

- If you run `make` on a Windows host under MSYS2/Git Bash/Cygwin, the Makefile emits `*.exe` outputs (`oren.exe`, `oren_stage2.exe`) and the local smoke scripts under `scripts/` will also suffix temporary artifacts with `.exe`.

Tuning knobs (env):

- `OREN_SELFHOST_COMPILER_BUILD_TIMEOUT_SECS` (default `1200`)
- `OREN_SELFHOST_REMOTE_COMPILE_TIMEOUT_SECS` (default `120`)
- `OREN_SELFHOST_REMOTE_RUN_TIMEOUT_SECS` (default `30`)
- `OREN_REMOTE_SELFHOST_DIR_NAME` (default `tmp_oren_selfhost`)
- `OREN_REMOTE_SCP_RETRIES` (default `3`, used by Tier‑1 scripts to harden flaky proxy uploads)

Common env overrides (match `scripts/verify_native_matrix.sh` defaults):

- `OREN_REMOTE_X64_HOST` (example: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY` (example: `ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002`)
- `OREN_REMOTE_X64_WIN_ROOT` (example: `G:\\work\\tmp_oren`)
- `OREN_REMOTE_X64_WSL_ROOT` (example: `/mnt/g/work/tmp_oren`)
- `OREN_REMOTE_X64_SSH_ROOT` (example: `G:/work/tmp_oren`)
- `OREN_NATIVE_BUILD_TIMEOUT_SECS` (rolling hang guard; default `10`)

## Prerequisites (local machine)

- `socat` available in `PATH` (required only when using a `ProxyCommand` that includes `socat`).
  - macOS (Homebrew): `brew install socat`
  - Linux: `apt-get install socat` / `dnf install socat` / etc.

## Connect to the remote host

Use this command to open the remote terminal session:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work
```

Notes:

- The remote host is Win11 (SSH provided by the environment).
- WSL2 may be unavailable depending on the host (pc2.work currently lacks WSL2).
- Keys/certs are already provisioned (no password prompt expected).
- If you see a proxy error like `socat ... CONNECT <host>:22: Not Found`, the proxy cannot resolve the hostname you passed.
  - Fix: set `OREN_REMOTE_X64_HOST` to an IP address (or a resolvable DNS name), or override `OREN_REMOTE_X64_PROXY` to connect directly (no proxy).

Direct SSH (no proxy) example:

```bash
ssh lzbgt@203.0.113.10
```

## Run commands on Windows (cmd.exe)

From your local machine, run a single Windows command like this:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /c ver'
```

Run a compiled Windows PE executable and see its exit code:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /v:on /c "%USERPROFILE%\\tmp_oren\\x64_format_win.exe & echo EXIT=!ERRORLEVEL!"'
```

## Windows toolchain (VS2022 + Windows Kits)

The remote Win11 x64 machine has a full MSVC toolchain installed, useful for:

- checking ABI details / header layouts (authoritative platform headers)
- quickly compiling “golden” reference snippets for instruction encodings (e.g., `cl.exe` + `dumpbin` / `llvm-objdump`)
- validating PE emit details and linking behavior as we expand Oren’s x64 backend

Installed locations (remote host):

- Visual Studio 2022 Community:
  - `C:\Program Files\Microsoft Visual Studio\2022\Community\`
- Windows SDK / Windows Kits:
  - `C:\Program Files (x86)\Windows Kits\`

Practical note:

- Prefer launching a “Developer Command Prompt” environment before running `cl.exe` so the right `INCLUDE`, `LIB`, and `PATH` are set.
  - The most direct non-interactive way is to call `VsDevCmd.bat` / `vcvars64.bat` and then run your command in the same `cmd.exe /c` invocation.

## Run commands on Linux (WSL2)

Run a Linux command inside WSL2:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'wsl.exe -e uname -a'
```

If WSL2 is not installed/enabled on the remote host, `wsl.exe` may emit a garbled
UTF‑16 message that mentions `wsl.exe --list --online` / `wsl.exe --install`.
In that case:

- Install WSL (admin shell on the remote host):
  - `wsl.exe --install`
- Or run only Windows targets (example):
  - `./scripts/verify_native_matrix.sh --targets x64-win-tier1`

Run a Linux x86_64 ELF executable from the Windows filesystem path:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'wsl.exe -e bash -lc "chmod +x /mnt/c/Users/lzbgt/tmp_oren/x64_format_linux && /mnt/c/Users/lzbgt/tmp_oren/x64_format_linux; echo EXIT=$?"'
```

## Copy artifacts to the remote host

Create a staging directory on the remote machine (Windows user profile):

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /c "mkdir %USERPROFILE%\\tmp_oren"'
```

If you use a custom staging root (example: G:\work\tmp_oren), run:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" xue@pc2.work 'cmd.exe /c "mkdir G:\\work\\tmp_oren"'
```

Copy artifacts:

```bash
# Prefer a home-relative scp destination (Windows OpenSSH path translation can be inconsistent for `/Users/<name>/...`).
scp -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" build/x64_format_win.exe lzbgt@pc.work:tmp_oren/x64_format_win.exe
scp -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" build/x64_format_linux   lzbgt@pc.work:tmp_oren/x64_format_linux
```

## Rolling guidance

- Keep remote execution **opt-in** in automated workflows so CI remains deterministic/offline by default.
- Never copy root CA private keys or other secrets into the repo or remote host unless explicitly designed for secure storage (`../oren-ca/` remains the secret boundary).

## Troubleshooting

### `socat ... CONNECT pc.work:22: Not Found`

This indicates the HTTP proxy at `hubstack.cn:6002` is not currently able to proxy the requested host/port.

What to do:

- The Tier‑1 scripts now run a fast SSH preflight before doing large cross-target builds. If it fails, check the bounded probe log under:
  - `build/logs/*remote_probe*.log`
- Re-try later (this has been observed as intermittent).
- Verify `socat` is installed and that the command is exactly:
  - `ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work ...`
- If the proxy stays unavailable, use a different reachable x86_64 host (or disable the proxy and connect directly).

## Fetching remote logs into the repo (recommended)

When a remote gate fails (stage2 hang, ABI warning spam, etc.), avoid pasting large logs into chat.
Instead, fetch the full original log into the repo under `project-doc/remote/`:

```bash
./scripts/fetch_remote_file.sh --win-path 'E:\work\oren-lang\s2_build_failure.log'
```

Notes:

- This script is bounded (does not print the whole file).
- It stages a copy under `%USERPROFILE%\tmp_oren\remote_fetch\` on the remote host, then downloads it.
- If ssh/proxy is broken, it fails fast and prints the path to the bounded probe logs under `build/logs/`.
- If the proxy can’t resolve `pc.work`, pass a reachable `--host user@IP` (and optionally `--no-proxy` if you have direct SSH access).
- Optional: add `--analyze` to run a bounded local summary after download:

```bash
./scripts/fetch_remote_file.sh --win-path 'E:\work\oren-lang\s2_build_failure.log' --analyze
```

If ssh/proxy is unavailable but you can transfer the log by other means (RDP copy, cloud drive, SMB, etc.),
import it locally (also stores the full original content) and run the same bounded analyzer:

```bash
./scripts/import_stage2_failure_log.sh --src /path/to/s2_build_failure.log --analyze
```

Helper (bounded analysis after fetch):

```bash
./scripts/analyze_stage2_failure_log.sh project-doc/remote/.../s2_build_failure.log
```

- Prints a short tail plus a few greps for `OREN_DIAG`, crashes, known x64 ABI warnings, output write failures, and timing breadcrumbs.
- Designed to avoid dumping thousands of lines.

### Optional: bounded include-aggregator progress (hang triage)

If a remote stage1->stage2 build looks stuck with no useful output, enable a **rate-limited**
progress log for include‑aggregator parsing. This helps distinguish “stuck in parsing” from “stuck later”.

- Remote Windows bootstrap gate:
  - `OREN_REMOTE_PROGRESS=1 make verify-stage2-win`
- Under the hood, this sets:
  - `OREN_PARSE_PROGRESS=1` on the remote host for the stage1->stage2 build step only.
