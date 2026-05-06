# iOS AVM Readiness Inspection (2026-05-07)

## Verdict

`libavm` and compiler-in-AVM are not production-ready for an iOS app in this repo.

The current tree has useful AVM runtime and compiler-in-AVM fixture work, but it lacks the packaging, embeddability API, release gates, and iOS integration evidence needed for a production claim.

## Evidence

- iOS integration scan: `find . -maxdepth 5` for Xcode projects, Swift, ObjC/ObjC++, and iOS/iPhone names found only `native/orenui/cocoa/orenui_cocoa.m`; there is no iOS app target or libavm embedding tree in this repo.
- Build shape: `make avm` builds the host `avm` executable from `lib/avm/*.c` and `.inc` files. `file avm` reports a Mach-O arm64 executable; this is not a static library, framework, xcframework, Swift package, or Objective-C embedding API target.
- Runtime maturity: `docs/STATUS.md` and `docs/DESIGN.md` already mark the AVM backend as rolling: single-threaded, `malloc` heap, no GC, rolling opcode/ABI stability, rolling capability/budget fields, and deterministic scheduling still in progress.
- API/embedding risks: `lib/avm/avm.h` has fixed `MAX_GLOBALS`, `MAX_FRAMES`, and `AVM_STACK_SIZE`; allocator ownership in `lib/avm/avm_alloc.c` is held in global state; teardown in `lib/avm/avm_vm_core.c` aborts on leaked heap allocations. These are acceptable development guardrails but not a polished iOS embedder failure model.
- Curated AVM gate: `make avm && make test-avm` passes in `build/logs/make_test_avm_20260507_ios_avm_readiness_v1.log`.
- Full wildcard fixture gate: `make test-avm AVM_TESTS="tests/avm/*.oren"` fails at `test_budget_io_fs` in `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`. The fixture expects a small `AVM_IO_BYTES` budget, but the generic wildcard harness does not attach that per-fixture policy.
- Runtime budget behavior: a direct run with `AVM_IO_BYTES=128` returns `AVM error: code=9 msg=budget exceeded (io)` in `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`, so the immediate gap is harness/release manifest maturity, not this specific runtime budget check.
- Compiler-in-AVM status: `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren` and `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren` load `build/oren_compiler.obc` and optional `build/stdlib_bundle.obc` into nested AVM VFS fixtures, but they are not a default iOS release gate or packaged compiler-in-AVM product path.

## Reweighted TODOs

- P1/W4: Add an iOS libavm embeddability gate. Required outputs: iOS simulator/device static library or xcframework, stable C embedder API, Swift/ObjC smoke host, deterministic lifecycle/error handling, and CI coverage.
- P1/W4: Add an AVM fixture manifest runner. Required fields: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- P1/W4: Promote compiler-in-AVM packaging. Required outputs: stable `oren_compiler.obc` build target, stdlib OBC resource packaging, nested-AVM compile/run smoke in the default AVM release gate, and iOS resource-loading coverage.
- P1/W4: Harden embedder lifecycle. Remove CLI-only assumptions from the library path, make allocator ownership reentrant or explicitly single-VM guarded, and return structured errors instead of aborting on teardown leaks in production mode.
- P1/W3/W4 dependency: Continue AVM allocation/scheduler maturity, but do not treat those as sufficient for iOS production readiness until the packaging/API/harness gates above exist.

## Verification Artifacts

- Curated AVM build/test: `build/logs/make_avm_20260507_ios_avm_readiness_v1.log`, `build/logs/make_test_avm_20260507_ios_avm_readiness_v1.log`.
- Wildcard fixture failure: `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`.
- Direct IO-budget run: `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`.
