# TODOs

This file is a concise pointer for active reweighted work. Detailed historical status remains in `docs/STATUS.md`, and focused evidence notes live under `project-doc/`.

## P1 / W4 - AVM iOS Production Readiness

- Keep the new `make verify-libavm-ios` gate green. It now builds `LibAVM.xcframework`, exports the embedder headers, compiles a tiny Oren source to `.obc`, links that bytecode into iOS device/simulator smoke binaries, and runs the same `.obc` through the host embed API.
- Add a Swift/Objective-C iOS smoke host that opens `AvmEmbedHandle`, loads bundled `.obc` resources, runs with virtual FS/PROC/NET, and reports `AvmEmbedResult`.
- Add an AVM fixture manifest runner: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- Promote compiler-in-AVM packaging from fixture-only to release gate: stable `oren_compiler.obc` target, nested-AVM compile/run smoke in the default AVM gate, and iOS resource-loading coverage. Current blocker: `build/plugins/stdlib_bundle.obc` builds, but the full compiler `.obc` probe segfaults while building `build/plugins/oren.obc`.
- Finish embedder lifecycle hardening: make allocator ownership reentrant or explicitly single-VM guarded, define app-level failure policy for teardown leaks, and keep host-only subprocess paths unavailable in iOS builds.

Evidence and verdict: `project-doc/ios_avm_readiness_20260507.md`.
