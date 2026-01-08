# Remote x86_64 Dev Environment (Win11 + WSL2) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host with WSL2 enabled.

## Terminology: platform, target, and the remote x64 gate

- For direct compilation, prefer the unified platform flag on the compiler:
  - `./oren build ... --platform <arch>-<os>`
  - env fallback: `OREN_PLATFORM=<arch>-<os>` is used when `--platform` is not provided.
  - if neither is provided, the compiler defaults to the **runtime host platform** (Windows uses env vars; POSIX uses `uname`).
  - `--target`/`--arch` are legacy (still supported).

## Preferred workflow: use the repo’s x64 matrix script (stage1 + stage2)

If your local host is macOS arm64 (Tier‑1 dev path), the recommended way to validate x86_64 targets is:

```bash
# Runs x64-linux under WSL2 and x64-windows under cmd.exe on the remote Win11 host.
# Also builds the artifacts locally (stage1 + stage2) before copying/running them remotely.
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win
```

## NET loopback matrix (TCP/UDP + HTTP GET loopback)

The Tier‑1 matrix script focuses on a broad native smoke (containers, strings, maps, proc, etc),
but it does not exercise TCP/UDP/HTTP.

To validate Oren’s **native NET substrate** on real x86_64 hosts (Win11 + WSL2), run:

```bash
# Builds stage1 + stage2, compiles the NET suites for x64-windows and x64-linux,
# uploads to the remote Win11 host, then runs:
#   - tests/native/test_net_suite.oren
#   - tests/native/test_http_get_loopback.oren
./scripts/verify_native_net_matrix.sh --targets x64-wsl,x64-win
```

## Optional: x64 self-host compiler gate (compiler runs on x86_64)

`verify_native_matrix.sh` focuses on **running native programs** built by the compiler.

To close the remaining “x64 gap”, we also need the **compiler binary itself** (`oren_stage2` built for x64)
to run on x86_64 hosts and compile+run a tiny native program.

This is intentionally **opt-in** because building the compiler for x64 can be slow on cold caches.

Rolling status:

- As of 2026-01-08, the x64 self-host compiler run gate passes again on the remote Win11+WSL2 host.
  - Root-cause + fix notes live in `docs/TODOS_ARCHIVE.md`.

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
```

## Optional: stage0 → stage1 bootstrap on Windows (MSVC)

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

Makefile shortcut (arm64 macOS host workflow):

```bash
make verify-stage2-win
```

Tuning knobs (env):

- `OREN_STAGE2_BUILD_TIMEOUT_SECS` (default `240`, rolling guard for stage1→stage2 self-host build on Windows)

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
- `OREN_NATIVE_BUILD_TIMEOUT_SECS` (rolling hang guard; default `10`)

## Prerequisites (local machine)

- `socat` available in `PATH` (required for `ProxyCommand`).
  - macOS (Homebrew): `brew install socat`
  - Linux: `apt-get install socat` / `dnf install socat` / etc.

## Connect to the remote host

Use this command to open the remote terminal session:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work
```

Notes:

- The remote host is Win11 (SSH provided by the environment) and also has WSL2 available.
- Keys/certs are already provisioned (no password prompt expected).

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

Run a Linux x86_64 ELF executable from the Windows filesystem path:

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'wsl.exe -e bash -lc "chmod +x /mnt/c/Users/lzbgt/tmp_oren/x64_format_linux && /mnt/c/Users/lzbgt/tmp_oren/x64_format_linux; echo EXIT=$?"'
```

## Copy artifacts to the remote host

Create a staging directory on the remote machine (Windows user profile):

```bash
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /c "mkdir %USERPROFILE%\\tmp_oren"'
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

- Re-try later (this has been observed as intermittent).
- Verify `socat` is installed and that the command is exactly:
  - `ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work ...`
- If the proxy stays unavailable, use a different reachable x86_64 host (or disable the proxy and connect directly).
