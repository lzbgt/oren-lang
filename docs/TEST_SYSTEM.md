# Test System (Direct, No Runner)

This repo is intentionally in **rolling ABI** mode. The testing constraint is:

- iteration must be **fast**
- tests must **never hang forever**
- failures must be **actionable** (logs, minimal noise)

The current approach is **direct compilation + direct execution** using the compiler binaries
(`./oren` and `./oren_stage2`) rather than a separate repo test runner.

## What “tests” mean in this repo

`tests/` contains multiple categories:

- `tests/native/*.oren`: programs intended to be compiled with `--backend native` and executed on the host OS
- `tests/modules/*.oren`: module-/stdlib-heavy programs (some are written without a `main()` and execute via top-level statements)
- `tests/avm/*.oren`: programs intended for the AVM workflow (`--backend bytecode` + `./avm`)
- `tests/fixtures/*.oren`: fixtures for compile-time contracts (many are expected failures under specific flags)

Rolling rule: **Oren source should be backend-universal** when the program is within the supported feature set of that backend.
When a source file is intended to be backend-specific (e.g. AVM domain tests), it should be documented as such in-file.

## Fast native verification (macOS/Linux host)

These targets are intended to be runnable without additional tooling:

```bash
# Build stage1 compiler
make stage1

# Fast, single-file native integration smoke (stage1)
make test-native-quick

# Build stage2 compiler
make stage2

# Fast, single-file native integration smoke (stage2)
make test-native-quick-stage2

# Convenience: stage1 + stage2
make verify-native-quick
```

For broader native coverage:

```bash
make test-native-all
```

## Cross-arch native verification (Tier‑1 matrix)

When you need confidence that the **native backend** output works across the practical Tier‑1 matrix
(without relying on a separate test runner), use the purpose-built scripts under `scripts/`:

	```bash
	# Local (arm64-macos): stage1 + stage2 build+run
	./scripts/verify_native_matrix.sh --targets local

# Linux/arm64 via the persistent container (stage1 + stage2 artifacts)
./scripts/verify_native_matrix.sh --targets arm64-linux

	# Full matrix: local + linux/arm64 container + remote x64 Win11 + remote x64 WSL2
	./scripts/verify_native_matrix.sh

	# Opt-in: run the larger Tier‑1 native smoke fixture on remote x64 hosts
	./scripts/verify_native_matrix.sh --targets x64-win-tier1
	./scripts/verify_native_matrix.sh --targets x64-wsl-tier1

	# Local gate: compile-only for x64-linux + x64-windows (stage1 + stage2)
	make verify-native-x64-compile
	```

Rolling guardrails:

- The matrix script uses short timeouts to avoid hangs.
- It does **not** start containers; it expects the existing linux container to be running.
- Per-build timeout can be tuned via `OREN_NATIVE_BUILD_TIMEOUT_SECS` (default: `10`).

## Quick perf check (compile-one-file)

When investigating “why did `oren build` take >10s?” regressions, use the bounded benchmark helper:

```bash
./scripts/bench_native_compile_one_file.sh
./scripts/bench_native_compile_one_file.sh --debug --trace
```

For a deeper “what regressed and how do we keep it bounded” playbook (rolling):

- `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`

## Logs and artifacts

- Logs:
  - `build/logs/*`
- Native test artifacts created by the quick smoke:
  - `build/tmp/*_native_quick_integration`

The goal is that any failure leaves a single stable log file that can be inspected directly.
