# Remote x86_64 Dev Environment (Win11 + WSL2) — Access + Workflow (Rolling)

This repo now has an x86_64 native backend bring-up path (Linux ELF + Windows PE).
To test it on real x86_64 machines, we use a remote Win11 host with WSL2 enabled.

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
ssh -o "ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002" lzbgt@pc.work 'cmd.exe /c "C:\\Users\\lzbgt\\tmp_oren\\x64_format_win.exe & echo EXIT=%ERRORLEVEL%"'
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
- Never copy root CA private keys or other secrets into the repo or remote host unless explicitly designed for secure storage (`../oren-ca/` remains the secret boundary).
