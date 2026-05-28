# iOS AVM Readiness Inspection (current through 2026-05-28)

## Verdict

`libavm` is now buildable as an iOS xcframework with an embedder C API and an
Oren-source-to-bytecode-to-libavm run gate, but the full compiler-in-AVM package
is still not production-ready for an iOS app.

The 2026-05-28 implementation closes the first packaging/API gap and proves the
host-compile-to-OBC plus embedded-libavm-run chain. Remaining production blockers
are app-host integration, compiler-in-AVM resource packaging, and allocator/lifecycle
hardening.

## Evidence

- iOS integration scan on 2026-05-07 found no iOS app target or libavm embedding tree in this repo.
- Build shape after 2026-05-28: `make avm` still builds the host CLI, while
  `make verify-libavm-ios` builds `build/libavm/ios/LibAVM.xcframework` from the
  non-CLI AVM sources for `iphoneos-arm64` and `iphonesimulator-arm64`.
- Embedder API after 2026-05-28: `lib/avm/avm_embed.h` provides an opaque
  `AvmEmbedHandle`, `AvmEmbedConfig`, and `AvmEmbedResult`; defaults are
  deterministic, deny host effects except CORE/EXIT, set budgets, and use
  virtual FS/PROC/NET backends.
- OBC resource API after 2026-05-28: `avm_embed_run_obc_bytes(...)` parses,
  verifies, loads, and runs `.obc` bytes owned by the embedder handle.
- Compile/run chain after 2026-05-28: `make verify-libavm-ios` compiles a tiny
  Oren source to `.obc`, embeds those bytes into a C smoke, links that smoke for
  iPhoneOS and simulator, and runs the same `.obc` through the host libavm embed
  API with `exit_code=7`.
- Lifecycle hardening after 2026-05-28: `avm_new()` returns `NULL` on VM/stack
  allocation failure, and iOS embed builds define `AVM_EMBED_NO_ABORT_ON_LEAK`
  so production packaging does not hard-abort on teardown leak diagnostics.
- iOS host-effect hardening after 2026-05-28: `AVM_IOS_EMBED` compiles out the
  unavailable `system()` path; PROC must use virtual fixtures/defaults in iOS
  embed builds.
- Runtime maturity: `docs/STATUS.md` and `docs/DESIGN.md` already mark the AVM backend as rolling: single-threaded, `malloc` heap, no GC, rolling opcode/ABI stability, rolling capability/budget fields, and deterministic scheduling still in progress.
- Remaining API/embedding risks: `lib/avm/avm.h` has fixed `MAX_GLOBALS`,
  `MAX_FRAMES`, and `AVM_STACK_SIZE`; allocator ownership in `lib/avm/avm_alloc.c`
  is held in global state; no Swift/Objective-C app-host gate exists yet.
- Curated AVM gate: `make avm && make test-avm` passes in `build/logs/make_test_avm_20260507_ios_avm_readiness_v1.log`.
- Current AVM gate: `make test-avm` passes in `build/logs/make_test_avm_20260528_libavm_ios_embed_v1.log`.
- Current iOS library gate: `make verify-libavm-ios` passes in `build/logs/make_verify_libavm_ios_20260528_embed_v2.log`.
- Full wildcard fixture gate: `make test-avm AVM_TESTS="tests/avm/*.oren"` fails at `test_budget_io_fs` in `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`. The fixture expects a small `AVM_IO_BYTES` budget, but the generic wildcard harness does not attach that per-fixture policy.
- Runtime budget behavior: a direct run with `AVM_IO_BYTES=128` returns `AVM error: code=9 msg=budget exceeded (io)` in `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`, so the immediate gap is harness/release manifest maturity, not this specific runtime budget check.
- Compiler-in-AVM status: `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren` and `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren` load `build/oren_compiler.obc` and optional `build/stdlib_bundle.obc` into nested AVM VFS fixtures, but they are not a default iOS release gate or packaged compiler-in-AVM product path. A 2026-05-28 packaging probe built `build/plugins/stdlib_bundle.obc` and then segfaulted while building `build/plugins/oren.obc`, so compiler-in-AVM packaging remains blocked.

## Reweighted TODOs

- Done 2026-05-28: Add an iOS libavm embeddability gate and stable C embedder entry surface. Output: `LibAVM.xcframework`, public embedder headers, simulator/device link smoke, and `make verify-libavm-ios`.
- Done 2026-05-28: Add an OBC bytes embedder path. `make verify-libavm-ios` now proves host Oren source compilation to `.obc`, iOS smoke linkage with those bytes, and host libavm embedder execution of those bytes.
- P1/W4: Add a Swift/ObjC iOS smoke host. Required proof: bundled `.obc` load, virtual FS/PROC/NET config, run result surfaced through `AvmEmbedResult`, and app-style lifecycle teardown.
- P1/W4: Add an AVM fixture manifest runner. Required fields: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- P1/W4: Promote compiler-in-AVM packaging. Required outputs: stable `oren_compiler.obc` build target, nested-AVM compile/run smoke in the default AVM release gate, and iOS resource-loading coverage. Current blocker: full compiler `.obc` build segfaults after stdlib OBC packaging succeeds.
- P1/W4: Finish embedder lifecycle. Make allocator ownership reentrant or explicitly single-VM guarded, document the app failure model, and keep host-only paths unavailable in iOS builds.
- P1/W3/W4 dependency: Continue AVM allocation/scheduler maturity, but do not treat those as sufficient for iOS production readiness until the packaging/API/harness gates above exist.

## Verification Artifacts

- Curated AVM build/test: `build/logs/make_avm_20260507_ios_avm_readiness_v1.log`, `build/logs/make_test_avm_20260507_ios_avm_readiness_v1.log`.
- Current iOS xcframework gate: `build/logs/make_verify_libavm_ios_20260528_embed_v2.log`, nested build log `build/logs/build_libavm_ios.log`.
- Current OBC embed chain gate: `build/logs/make_verify_libavm_ios_20260528_obc_chain_v2.log`, OBC build log `build/logs/libavm_ios_embed_chain_obc_build.log`.
- Compiler-OBC packaging blocker: `build/logs/build_avm_plugins_compiler_obc_20260528_probe_v1.log`, compiler build log `build/logs/build_oren_obc.log`.
- Current curated AVM gate: `build/logs/make_test_avm_20260528_libavm_ios_embed_v1.log`.
- Wildcard fixture failure: `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`.
- Direct IO-budget run: `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`.
