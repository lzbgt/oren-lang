# Remote x86_64 Dev Environment (Win11 + WSL2) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host with WSL2 enabled.

## Terminology: platform, target, and the remote x64 gate

- Prefer `./oretest --platform <arch>-<os>` (or env `OREN_PLATFORM`) for anything Tier‑1:
  - `arm64-macos` runs locally on the Mac host.
  - `arm64-linux` runs via the persistent Docker runner.
  - `x64-windows` / `x64-linux` run via the remote Win11+WSL2 batch gate.

- `./oretest --target <os>` is legacy and only selects the **host** native-backend target (`macos` or `linux`) for tests that run locally (or in the local Linux Docker runner).

- The remote x64 gate can also be controlled directly by env flags and runs **x64-windows + x64-linux (WSL2)** on the remote Win11 machine:
  - enable: `OREN_REMOTE_RUN=1`
  - choose run kind: `OREN_REMOTE_X64_RUN_KIND=both|windows|wsl` (default: `both`)

Examples:

```bash
# Run the full Tier‑1 matrix from the Mac host (includes remote x64 gate)
./oretest --matrix tier1

# Run only the remote Windows PE fixture batch
./oretest --platform x64-windows

# Run only the remote WSL2 Linux x64 fixture batch
./oretest --platform x64-linux
```

## Prerequisites (local machine)

- `socat` available in `PATH` (required for `ProxyCommand`).
  - macOS (Homebrew): `brew install socat`
  - Linux: `apt-get install socat` / `dnf install socat` / etc.

## Optional overrides (for non-default hosts)

`cmd/oretest` has a default Win11+WSL2 host and proxy configuration (documented below), but you can
override the remote connection details without editing source:

- `OREN_REMOTE_X64_HOST` (default: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY_ARG` (default: the `socat` ProxyCommand; set to empty to disable)
- `OREN_REMOTE_X64_UNIX_ROOT` (default: `/Users/lzbgt/tmp_oren`)
- `OREN_REMOTE_X64_WIN_ROOT` (default: `C:\Users\lzbgt\tmp_oren`)
- `OREN_REMOTE_X64_WSL_ROOT` (default: `/mnt/c/Users/lzbgt/tmp_oren`)
- `OREN_REMOTE_X64_RUN_KIND` (default: `both`)
  - `both`: run the batch on Windows + WSL2 (Tier‑1 canonical)
  - `windows`: run only the Windows PE executable(s)
  - `wsl` / `linux`: run only the WSL2 Linux executable(s)
- `OREN_REMOTE_TIER1_TIMEOUT_SECS` (default: `180`) — outer wall-time budget for the remote Tier‑1 fixture batch

Example:

```bash
export OREN_REMOTE_X64_HOST="user@myhost"
export OREN_REMOTE_X64_PROXY_ARG=""
```

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

- Keep the remote-run steps **opt-in** in automated tests (use env flags like `OREN_REMOTE_RUN=1`) so CI remains deterministic/offline by default.
- The remote batch runner uses a SHA-addressed bundle directory on the remote host so repeated runs can reuse the uploaded+extracted bundle when inputs are unchanged (reduces proxy/SCP overhead).
- Never copy root CA private keys or other secrets into the repo or remote host unless explicitly designed for secure storage (`../oren-ca/` remains the secret boundary).

## Troubleshooting

### `socat ... CONNECT pc.work:22: Not Found`

This indicates the HTTP proxy at `hubstack.cn:6002` is not currently able to proxy the requested host/port.

What to do:

- Re-try later (this has been observed as intermittent).
- Verify `socat` is installed and that the command is exactly:
  - `ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work ...`
- If the proxy stays unavailable, use the environment overrides above to point `oretest` at an alternate reachable x86_64 host.
