# Tier‑1 Support Matrix (Rolling)

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

### Local (arm64-macos host)

- Build stage1 + stage2 (native backend): `make stage2`
- Fast stage1 + stage2 smoke (native): `make verify-native-quick`
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

See `docs/REMOTE_X64_ENV.md` for how the remote Windows + WSL2 hosts are configured and how logs are fetched.

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
  (not just compile-only from macOS). Primary gate: `make verify-stage2-win` (remote).
- Remote reliability: keep remote log capture bounded and reproducible; use
  `scripts/fetch_remote_file.sh --analyze` + `scripts/analyze_stage2_failure_log.sh` for triage.
  - If the build appears to hang, enable bounded parse progress for include-aggregators:
    - `OREN_REMOTE_PROGRESS=1 make verify-stage2-win` (rate-limited; avoids huge logs).

## Cross-platform path robustness

- Oren accepts Windows-style `\` separators in CLI paths across hosts (macOS/Linux/Windows). This is a
  correctness requirement because remote Win11 logs/scripts often contain backslash paths.
