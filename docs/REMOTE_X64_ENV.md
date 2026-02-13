# Remote x86_64 Dev Environment (Win11 + WSL2) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host with WSL2 enabled.

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
# Runs x64-linux under WSL2 and x64-windows under cmd.exe on the remote Win11 host.
# Also builds the artifacts locally (stage1 + stage2) before copying/running them remotely.
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win
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

Notes:

- Keep the three roots in sync:
  - `OREN_REMOTE_X64_WIN_ROOT` is the Windows path used by `cmd.exe`.
  - `OREN_REMOTE_X64_WSL_ROOT` is the WSL path for the same directory.
  - `OREN_REMOTE_X64_SSH_ROOT` is the scp/sftp path (Windows OpenSSH).
- If you only set `OREN_REMOTE_X64_WIN_ROOT`, the scripts attempt to derive `SSH_ROOT` and `WSL_ROOT`.

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

Rolling IOCP note:

- `OREN_NETPOLL_WIN_IOCP=1` enables the IOCP **wake** substrate.
- Socket readiness stays on select‑v0 unless `OREN_NETPOLL_WIN_IOCP_READY=1` is also set.

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

- The remote host is Win11 (SSH provided by the environment) and also has WSL2 available.
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
