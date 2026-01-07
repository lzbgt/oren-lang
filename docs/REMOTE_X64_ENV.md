# Remote x86_64 Dev Environment (Win11 + WSL2) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host with WSL2 enabled.

## Terminology: platform, target, and the remote x64 gate

- For direct compilation, prefer the unified platform flag on the compiler:
  - `./oren build ... --platform <arch>-<os>`
  - env fallback: `OREN_PLATFORM=<arch>-<os>` is used when `--platform` is not provided.
  - `--target`/`--arch` are legacy (still supported).

## Preferred workflow: use the repo’s x64 matrix script (stage1 + stage2)

If your local host is macOS arm64 (Tier‑1 dev path), the recommended way to validate x86_64 targets is:

```bash
# Runs x64-linux under WSL2 and x64-windows under cmd.exe on the remote Win11 host.
# Also builds the artifacts locally (stage1 + stage2) before copying/running them remotely.
./scripts/verify_native_matrix.sh --targets x64-wsl,x64-win
```

## Optional: x64 self-host compiler gate (compiler runs on x86_64)

`verify_native_matrix.sh` focuses on **running native programs** built by the compiler.

To close the remaining “x64 gap”, we also need the **compiler binary itself** (`oren_stage2` built for x64)
to run on x86_64 hosts and compile+run a tiny native program.

This is intentionally **opt-in** because building the compiler for x64 can be slow on cold caches.

Rolling status:

- As of 2026-01-07, the x64 self-host compiler run gate passes again on the remote Win11+WSL2 host.
  - Root-cause + fix notes live in `docs/TODOS_ARCHIVE.md`.

```bash
# Builds x64-linux and x64-windows compiler binaries (native backend),
# copies them + a minimal runtime source bundle to the remote Win11 machine,
# then runs:
#   - x64-linux compiler under WSL2
#   - x64-windows compiler under cmd.exe
# to compile+run a tiny `print.oren`.
./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win
```

Tuning knobs (env):

- `OREN_SELFHOST_COMPILER_BUILD_TIMEOUT_SECS` (default `1200`)
- `OREN_SELFHOST_REMOTE_COMPILE_TIMEOUT_SECS` (default `120`)
- `OREN_SELFHOST_REMOTE_RUN_TIMEOUT_SECS` (default `30`)

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
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /v:on /c "C:\\Users\\lzbgt\\tmp_oren\\x64_format_win.exe & echo EXIT=!ERRORLEVEL!"'
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
scp -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" build/x64_format_win.exe lzbgt@pc.work:/Users/lzbgt/tmp_oren/x64_format_win.exe
scp -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" build/x64_format_linux   lzbgt@pc.work:/Users/lzbgt/tmp_oren/x64_format_linux
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
