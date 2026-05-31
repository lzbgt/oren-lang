# iOS AVM Readiness Inspection (current through 2026-05-28)

## Verdict

`libavm` is now buildable as an iOS xcframework with an embedder C API, public
argv/VFS/VNET/VPROC virtual-backend helpers, stdout capture, an
Oren-source-to-bytecode-to-libavm run gate, and a compiler-in-AVM stdlib-OBC
compile/run smoke gate. It is ready for a Note-side integration pass, but still
not fully production-ready for an iOS app until app-bundle resource loading,
Swift/ObjC host integration, and lifecycle policy are gated.

The 2026-05-28 implementation closes the first packaging/API gap and the later
virtual-backend bridge gap reported by the Note app. It proves
host-compile-to-OBC, embedded-libavm-run, compiler-OBC packaging, and nested
compiler-in-AVM smoke chain. Remaining production blockers are app-host
integration, iOS resource loading from an app bundle, broader compiler/stdlib coverage, and
allocator/lifecycle hardening.

## Evidence

- iOS integration scan on 2026-05-07 found no iOS app target or libavm embedding tree in this repo.
- Build shape after 2026-05-28: `make avm` still builds the host CLI, while
  `make verify-libavm-ios` builds `build/libavm/ios/LibAVM.xcframework` from the
  non-CLI AVM sources for `iphoneos-arm64` and `iphonesimulator-arm64`.
- Embedder API after 2026-05-28: `lib/avm/avm_embed.h` provides an opaque
  `AvmEmbedHandle`, `AvmEmbedConfig`, and `AvmEmbedResult`; defaults are
  deterministic, set budgets, allow CORE/FS/TIME/NET/PROC/EXIT with the default
  virtual FS/PROC/NET backends, and avoid host filesystem/network/process effects.
  TIME is virtual by default for `std:time.now_ns`, `std:time.mono_raw`,
  `std:time.now_unix_ns`, and `std:time.sleep_ms`.
- Interactive app mode after 2026-05-29: call
  `avm_embed_config_interactive_default(...)` before `avm_embed_open(...)` when
  user-visible delays should use wall-clock time. This keeps virtual FS/PROC/NET
  defaults but makes `std:time.sleep_ms` block the AVM worker; do not run it on
  the iOS main thread.
- AVM stdlib bundle after 2026-05-29: the bundle root includes `std:time` alongside
  the existing compiler/app-critical portable subset. Broader pure-stdlib expansion
  should be manifest-gated so bundle build time remains acceptable.
- App bridge API after 2026-05-28: `avm_embed_set_argv(...)` copies program argv
  into the VM, `avm_embed_vfs_put(...)` injects VirtualFS file bytes,
  `avm_embed_vfs_get(...)` copies VirtualFS output bytes back to the app,
  `avm_embed_vfs_snapshot(...)` exports the `AVMVFS01` snapshot format,
  `avm_embed_vnet_put(...)` injects deterministic network fixture bodies,
  `avm_embed_vproc_put(...)` injects per-command process fixture exit codes,
  `avm_embed_vproc_set_default_exit(...)` sets the default VirtualPROC exit code,
  `avm_embed_set_output_capture(...)` controls stdout capture,
  `avm_embed_output_get(...)` copies stdout bytes back to the app,
  `avm_embed_output_clear(...)` clears the captured stdout buffer,
  `avm_embed_gfx_frame_get(...)` copies the latest GFX frame mailbox payload,
  `avm_embed_gfx_frame_clear(...)` clears that payload,
  `avm_embed_gfx_input_put(...)` enqueues host input-event bytes for OBC polling,
  and `avm_embed_free_bytes(...)` releases returned app-owned buffers.
- iOS SDK slice after 2026-05-31: `OrenAVMKit.xcframework` builds beside
  `LibAVM.xcframework` and exposes Objective-C/Swift-callable defaults for
  deterministic AVM runs and interactive app runs. The verifier proves the SDK can
  run OBC with VirtualFS, VirtualNET, VirtualPROC, stdout capture, wall-clock
  `std:time.sleep_ms` in interactive mode, allowlisted URLSession prefetch into
  VirtualNET, binary GFX frame mailbox retrieval/clear, and host-injected binary
  pointer events consumed by OBC.
- OBC resource API after 2026-05-28: `avm_embed_run_obc_bytes(...)` parses,
  verifies, loads, and runs `.obc` bytes owned by the embedder handle.
- Compile/run chain after 2026-05-28: `make verify-libavm-ios` compiles a tiny
  Oren source to `.obc`, embeds those bytes into a C smoke, links that smoke for
  iPhoneOS and simulator, and runs the same `.obc` through the host libavm embed
  API with `exit_code=9`, argv injection, VFS input, VFS output extraction,
  VFS snapshot verification, deterministic TIME, VirtualNET `oren_net_get(...)`,
  VirtualPROC `oren_system(...)`, binary GFX frame publication/retrieval,
  binary GFX input-event polling, and captured stdout retrieval/clear.
- Compiler-in-AVM chain after 2026-05-28: `make verify-libavm-ios` also calls
  `scripts/verify_compiler_in_avm_ios_chain.sh`, which builds
  `build/plugins/stdlib_bundle.obc` and `build/plugins/oren.obc`, injects them
  into a nested VirtualFS harness, compiles a small `std:list` program inside AVM,
  extracts `out.obc`, and runs that output with `exit_code=7`.
- AVM fixes retained for the chain: child-owned OBC string/bytes constants for
  nested universes with an explicit VM-owned constant-root flag, float constants in
  the nested OBC parser, explicit global-index failures plus a `MAX_GLOBALS=1024`
  cap for compiler OBC, VM-local pointer handles for compiler helper shims, VFS
  `write_bytes` support for BYTES values, and current embedded compiler CLI args
  (`--platform arm64-macos`, `--no-cache`).
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
- Current iOS full-chain gate: `make verify-libavm-ios` passes in
  `build/logs/make_verify_libavm_ios_20260528_embed_virtual_backends_v1.log`.
- Full wildcard fixture gate: `make test-avm AVM_TESTS="tests/avm/*.oren"` fails at `test_budget_io_fs` in `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`. The fixture expects a small `AVM_IO_BYTES` budget, but the generic wildcard harness does not attach that per-fixture policy.
- Runtime budget behavior: a direct run with `AVM_IO_BYTES=128` returns `AVM error: code=9 msg=budget exceeded (io)` in `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`, so the immediate gap is harness/release manifest maturity, not this specific runtime budget check.
- Compiler-in-AVM status: `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren`
  is now a release smoke through `make verify-libavm-ios`. It proves compiler OBC
  packaging and nested VFS compile/run, but not a full app-bundle packaging product
  or broad compiler conformance matrix.

## Reweighted TODOs

- Done 2026-05-28: Add an iOS libavm embeddability gate and stable C embedder entry surface. Output: `LibAVM.xcframework`, public embedder headers, simulator/device link smoke, and `make verify-libavm-ios`.
- Done 2026-05-28: Add an OBC bytes embedder path. `make verify-libavm-ios` now proves host Oren source compilation to `.obc`, iOS smoke linkage with those bytes, and host libavm embedder execution of those bytes.
- Done 2026-05-28: Add the app-facing virtual-backend bridge API missing from
  `avm_embed.h`. The iOS verifier now requires exported symbols and a host smoke
  that calls `avm_embed_set_argv`, `avm_embed_vfs_put`,
  `avm_embed_vfs_get`, `avm_embed_vfs_snapshot`, `avm_embed_vnet_put`,
  `avm_embed_vproc_put`, and `avm_embed_vproc_set_default_exit`.
- Done 2026-05-28: Add app-visible stdout capture to the public embed API. The
  iOS verifier now requires `avm_embed_set_output_capture`,
  `avm_embed_output_get`, and `avm_embed_output_clear`, and checks that Oren
  `print(...)` output is returned to the host instead of disappearing into
  process stdout.
- P1/W4: Add a Swift/ObjC iOS smoke host. Required proof: bundled `.obc` load, virtual FS/PROC/NET config, run result and stdout surfaced through the Note bridge, and app-style lifecycle teardown.
- P1/W4: Add an AVM fixture manifest runner. Required fields: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- Done 2026-05-28: Promote compiler-in-AVM smoke packaging into
  `make verify-libavm-ios` through `scripts/verify_compiler_in_avm_ios_chain.sh`.
- P1/W4: Expand compiler-in-AVM from smoke to app packaging. Required proof:
  Swift/ObjC host loads bundled `oren.obc` and `stdlib_bundle.obc`, feeds VFS
  resources through the embedder API, and surfaces deterministic result/error data.
- P1/W4: Finish embedder lifecycle. Make allocator ownership reentrant or explicitly single-VM guarded, document the app failure model, and keep host-only paths unavailable in iOS builds.
- P1/W3/W4 dependency: Continue AVM allocation/scheduler maturity, but do not treat those as sufficient for iOS production readiness until the packaging/API/harness gates above exist.

## Verification Artifacts

- Curated AVM build/test: `build/logs/make_avm_20260507_ios_avm_readiness_v1.log`, `build/logs/make_test_avm_20260507_ios_avm_readiness_v1.log`.
- Current iOS xcframework gate: `build/logs/make_verify_libavm_ios_20260528_embed_v2.log`, nested build log `build/logs/build_libavm_ios.log`.
- Current OBC embed chain gate: `build/logs/make_verify_libavm_ios_20260528_obc_chain_v2.log`, OBC build log `build/logs/libavm_ios_embed_chain_obc_build.log`.
- Current virtual-backend embed API gate: `build/logs/make_verify_libavm_ios_20260528_embed_output_capture_v1.log`.
- Compiler-in-AVM chain gate: `build/logs/make_verify_compiler_in_avm_ios_chain_20260528_full_chain_v1.log`,
  nested logs `build/logs/build_avm_plugins_compiler_obc_20260528_full_chain_v1.log`
  and `build/logs/run_compiler_in_avm_vfs_stdlib_obc_harness_20260528_full_chain_v1.log`.
- Current curated AVM gate: `build/logs/make_test_avm_20260528_libavm_ios_embed_v1.log`.
- Wildcard fixture failure: `build/logs/make_test_avm_full_20260507_ios_avm_readiness_v1.log`.
- Direct IO-budget run: `build/logs/avm_test_budget_io_fs_direct_20260507_ios_avm_readiness_v1.log`.
