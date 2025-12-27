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
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work
```

Notes:

- The remote host is Win11 (SSH provided by the environment) and also has WSL2 available.
- Keys/certs are already provisioned (no password prompt expected).

## Run commands on Windows (cmd.exe)

From your local machine, run a single Windows command like this:

```bash
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work 'cmd.exe /c ver'
```

Run a compiled Windows PE executable and see its exit code:

```bash
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work 'cmd.exe /c "C:\\Users\\lzbgt\\tmp_oren\\x64_min_win.exe & echo EXIT=%ERRORLEVEL%"'
```

## Run commands on Linux (WSL2)

Run a Linux command inside WSL2:

```bash
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work 'wsl.exe -e uname -a'
```

Run a Linux x86_64 ELF executable from the Windows filesystem path:

```bash
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work 'wsl.exe -e bash -lc "chmod +x /mnt/c/Users/lzbgt/tmp_oren/x64_min_linux && /mnt/c/Users/lzbgt/tmp_oren/x64_min_linux; echo EXIT=$?"'
```

## Copy artifacts to the remote host

Create a staging directory on the remote machine (Windows user profile):

```bash
ssh -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' lzbgt@pc.work 'cmd.exe /c "mkdir %USERPROFILE%\\tmp_oren"'
```

Copy artifacts:

```bash
scp -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' build/x64_min_win.exe lzbgt@pc.work:/Users/lzbgt/tmp_oren/x64_min_win.exe
scp -o 'proxycommand socat - PROXY:hubstack.cn:%h:%p,proxyport=6002' build/x64_min_linux   lzbgt@pc.work:/Users/lzbgt/tmp_oren/x64_min_linux
```

## Rolling guidance

- Keep the remote-run steps **opt-in** in automated tests (use env flags like `OREN_REMOTE_RUN=1`) so CI remains deterministic/offline by default.
- Never copy root CA private keys or other secrets into the repo or remote host unless explicitly designed for secure storage (`../oren-ca/` remains the secret boundary).

