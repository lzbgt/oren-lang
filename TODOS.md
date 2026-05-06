# TODOs

This file is a concise pointer for active reweighted work. Detailed historical status remains in `docs/STATUS.md`, and focused evidence notes live under `project-doc/`.

## P1 / W4 - AVM iOS Production Readiness

- Add an iOS libavm embeddability gate: iOS simulator/device static library or xcframework, stable C embedder API, Swift/Objective-C smoke host, deterministic lifecycle/error handling, and CI coverage.
- Add an AVM fixture manifest runner: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- Promote compiler-in-AVM packaging from fixture-only to release gate: stable `oren_compiler.obc` target, stdlib OBC resource packaging, nested-AVM compile/run smoke in the default AVM gate, and iOS resource-loading coverage.
- Harden libavm embedder lifecycle: remove CLI-only assumptions from the library path, make allocator ownership reentrant or explicitly single-VM guarded, and return structured errors instead of aborting on teardown leaks in production mode.

Evidence and verdict: `project-doc/ios_avm_readiness_20260507.md`.
