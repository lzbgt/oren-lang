# TODOs

This file is a concise pointer for active reweighted work. Detailed historical status remains in `docs/STATUS.md`, and focused evidence notes live under `project-doc/`.

## P1 / W4 - AVM iOS Production Readiness

- Keep the new `make verify-libavm-ios` gate green. It now builds `LibAVM.xcframework`, exports the embedder headers, compiles a tiny Oren source to `.obc`, links that bytecode into iOS device/simulator smoke binaries, and runs the same `.obc` through the host embed API with argv plus VirtualFS input/output, VirtualNET fixtures, and VirtualPROC fixtures/default exits.
- Keep `make verify-compiler-in-avm-ios-chain` green. It now builds `stdlib_bundle.obc` and `oren.obc`, runs the compiler `.obc` inside AVM with VirtualFS stdlib resources, extracts `out.obc`, and runs the compiled output.
- Add a Swift/Objective-C iOS smoke host that opens `AvmEmbedHandle`, loads bundled `.obc` resources, feeds source/stdlib files through `avm_embed_vfs_put`, extracts `out.obc` through `avm_embed_vfs_get`, injects optional deterministic network/process fixtures with `avm_embed_vnet_put` and `avm_embed_vproc_put`, runs with virtual FS/PROC/NET, and reports `AvmEmbedResult`.
- Add an AVM fixture manifest runner: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- Expand compiler-in-AVM packaging from the current smoke gate to app-bundle resource loading and broader compiler/stdlib surface coverage.
- Finish embedder lifecycle hardening: make allocator ownership reentrant or explicitly single-VM guarded, define app-level failure policy for teardown leaks, and keep host-only subprocess paths unavailable in iOS builds.

Evidence and verdict: `project-doc/ios_avm_readiness_20260507.md`.
