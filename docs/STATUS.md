# Oren Status

**Last updated:** 2026-05-31

This is the current implementation status. It replaces the former rolling log with a
small source-of-truth snapshot. Use code, fixtures, and build logs for raw evidence.

## Overall Verdict

Oren is not yet production-stable at the level of industrial compilers such as
LLVM/rustc/GCC/zig/go. It is a rolling self-hosted compiler with meaningful working
surfaces, but the following blockers remain:

- native tagged-value convergence is incomplete;
- allocator/GC/runtime robustness is still a W5 gate;
- Tier-1 platform breadth is uneven;
- AVM now has an iOS xcframework packaging gate, embedder C API with argv,
  VirtualFS, VirtualNET, VirtualPROC, and stdout-capture helpers, plus a full
  compiler-in-AVM smoke gate, but still needs app-host lifecycle coverage before
  it should be called a complete production iOS package.

## Backend Readiness

| Backend | Current state | Production posture |
| --- | --- | --- |
| C | Portable bootstrap path through host C toolchain. | Useful baseline, not a stabilized external ABI promise. |
| Native arm64 macOS | Most mature native path; broadest profile and fixture history. | Rolling Tier-1 intent. |
| Native x64 Linux/Windows | Active bring-up with compile/runtime gates. | Not fully mature. |
| Bytecode / AVM | Deterministic VM with capability gates, budgets, snapshots, VFS/VPROC/VNET fixtures, coroutine/generator surfaces. | Experimental for production embedding. |

## AVM and iOS Readiness

Current verdict: **production-chain smoke ready, not fully app-production mature**.

Facts from the 2026-05-28 implementation pass:

- `make verify-libavm-ios` builds `build/libavm/ios/LibAVM.xcframework` for
  `iphoneos-arm64` and `iphonesimulator-arm64`, exports public AVM headers, and
  links a tiny iOS embedder smoke for both SDKs.
- `lib/avm/avm_embed.h` exposes an opaque-handle C embedder API with
  deterministic config, budgets, virtual FS/PROC/NET defaults, structured result
  fields, captured stdout, explicit lifecycle calls, and public app-backend helpers:
  `avm_embed_config_interactive_default`, `avm_embed_set_argv`,
  `avm_embed_vfs_put`, `avm_embed_vfs_get`,
  `avm_embed_vfs_snapshot`, `avm_embed_vnet_put`, `avm_embed_vproc_put`,
  `avm_embed_vproc_set_default_exit`, `avm_embed_set_output_capture`,
  `avm_embed_output_get`, `avm_embed_output_clear`, `avm_embed_gfx_frame_get`,
  `avm_embed_gfx_frame_clear`, `avm_embed_gfx_input_put`, and
  `avm_embed_free_bytes`.
- Default embed configs allow deterministic TIME alongside CORE/FS/NET/PROC/EXIT,
  so `std:time.now_ns`, `std:time.mono_raw`, `std:time.now_unix_ns`, and
  `std:time.sleep_ms` work from AVM bytecode without extra app-side capability
  wiring. Deterministic mode maps all three clocks to virtual time; non-deterministic
  app mode is available through `avm_embed_config_interactive_default(...)`, where
  `sleep_ms` blocks the AVM worker on wall-clock time and `now_unix_ns` uses host
  realtime. Hosts must run this off the UI thread.
- The AVM stdlib bundle root includes the compiler/app-critical portable subset plus
  `std:time`; broader pure-stdlib expansion should be manifest-gated so bundle build
  time stays inside the repo iteration budget.
- The embedder API can now parse, verify, load, and run `.obc` bytes from memory.
  The iOS gate compiles a tiny Oren source to `.obc`, embeds those bytes into a C
  smoke, links that smoke for iPhoneOS and simulator, and runs the same bytes
  through the host libavm embed API with argv, VFS read/write roundtrip,
  deterministic TIME, VirtualNET fixture lookup, VirtualPROC fixture/default exits,
  and captured stdout retrieval/clear.
- `make verify-libavm-ios` also builds `build/plugins/stdlib_bundle.obc` and
  `build/plugins/oren.obc`, runs the compiler `.obc` inside a child AVM universe
  with VirtualFS stdlib resources, extracts `out.obc`, and runs that bytecode.
- OBC distribution design is documented in
  `project-doc/obc_store_distribution_design_20260529.md`: after the GUI bridge
  release gate, a public signed OBC store repo can distribute app experiences
  that the iOS app downloads, verifies, and runs through `libavm`.
- iOS SDK design is documented in `project-doc/ios_avm_sdk_design_20260531.md`:
  Oren should ship host-adapter SDK components so Note can use default
  app-policy-controlled FS/NET/PROC/TIME/GFX implementations instead of
  hand-writing each bridge.
- First SDK implementation slice: `scripts/build_libavm_ios.sh` now also builds
  `OrenAVMKit.xcframework`. The Objective-C API provides deterministic defaults,
  interactive app defaults for wall-clock `time.sleep_ms`, VirtualFS file helpers,
  VirtualNET fixtures, VirtualPROC fixtures/defaults, OBC run, stdout capture, and
  a module map for app imports. `make verify-libavm-ios` compiles iOS
  device/simulator SDK smokes and runs a host SDK smoke that proves interactive
  sleep has real elapsed-time effect.
- The SDK now includes an allowlisted `URLSession` prefetch helper that maps real
  host network responses into VirtualNET. `make verify-libavm-ios` starts a local
  HTTP server, fetches it through the SDK, injects the body under the requested URL,
  then runs OBC that reads it with `oren_net_get(url)`. This is the current
  app-facing NET bridge; AVM still does not expose raw host networking to bytecode.
- The first GUI bridge slices now exist as binary GFX mailboxes. Bytecode can
  publish a validated `std:ui` v0 frame through `std:ui/avm` /
  `oren_gfx_present_frame`; embedders can read and clear it with
  `avm_embed_gfx_frame_get` and `avm_embed_gfx_frame_clear`. Hosts enqueue
  binary input events with `avm_embed_gfx_input_put`; OBC pulls them through
  `std:ui/avm.pull_event_bytes()`. `poll_event_bytes()` remains a thin alias.
  `OrenAVMKit` exposes matching Objective-C
  helpers including a convenience binary pointer-event encoder. The iOS verifier
  checks exported symbols, device/simulator SDK linkage, and a host OBC run that
  publishes a binary frame, retrieves it through the SDK, injects a binary pointer
  event, and consumes it from OBC. `OrenAVMGraphicsView` is now the default
  UIKit/CoreGraphics 2D renderer for the current `OGF0` `fill_rect`/`text`/
  `stroke_line`/`circle` frame subset and can enqueue pointer, resize, key, and
  text events. Metal rendering, IME/composition helpers, and richer 2D/3D command
  sets remain pending. The next GUI contract is game-grade rather than widget-only:
  high-refresh/high-resolution pacing, latest-frame/drop-stale behavior, retained
  resource handles, strict budgets, low-latency input ordering, and Metal/`MTKView`
  conformance gates are documented in
  `project-doc/avm_ui_render_performance_design_20260531.md`.
- `avm_new()` now returns `NULL` on VM/stack allocation failure instead of
  dereferencing failed allocations.
- iOS embed builds define `AVM_EMBED_NO_ABORT_ON_LEAK` and `AVM_IOS_EMBED`;
  teardown leak aborts stay enabled for normal development builds, while iOS
  packaging avoids an app-process abort path.
- Host subprocess execution is compiled out of iOS embed builds; PROC must use
  the virtual backend path there.
- `lib/avm/avm.h` still exposes fixed global/frame/stack limits and rolling
  capability/budget fields.
- `lib/avm/avm_alloc.c` uses global allocation-owner state, which is not a polished
  reentrant embedder story.
- Curated `make avm && make test-avm` passes.
- Wildcard `AVM_TESTS="tests/avm/*.oren"` is not a valid release gate today because
  fixture-specific env/expected-error policy is encoded only in selected Makefile cases.
- A direct `AVM_IO_BYTES=128` run of `test_budget_io_fs` returns the expected
  `AVM_ERR_BUDGET`, proving that specific runtime behavior while exposing harness debt.

Detailed note: `project-doc/ios_avm_readiness_20260507.md`.

## Compiler-in-AVM

Current verdict: **release-gated smoke path is green**.

Working evidence:

- `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren` loads
  `build/oren_compiler.obc` into a nested AVM universe and compiles a small program
  through VFS.
- `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren` additionally
  passes `build/stdlib_bundle.obc` as a stdlib OBC resource.
- `scripts/verify_compiler_in_avm_ios_chain.sh` builds both OBC resources with
  `./oren`, runs the stdlib-OBC nested compiler harness through `./avm`, and is
  called by `make verify-libavm-ios`.
- The retained fixes include child-owned OBC constant parsing with explicit VM
  ownership flags, a larger explicit AVM global table cap for the compiler OBC,
  VFS `write_bytes` support for BYTES, and current CLI args (`--platform`,
  `--no-cache`) for embedded compiler runs.

Missing for production:

- Swift/Objective-C app-host smoke that loads bundled `oren.obc` and
  `stdlib_bundle.obc` resources from an app bundle and uses the public virtual
  backend helpers to feed source/resources, extract `out.obc`, and provide
  deterministic network/process fixtures plus captured stdout/stderr UI data;
- allocator ownership/reentrancy hardening or an explicit single-VM embedder policy;
- manifest-driven AVM fixture release runner;
- broader stdlib/compiler surface coverage beyond the current smoke program.

## Scientific Stdlib Math

Current verdict: **portable deterministic foundation, still expanding toward C/C++
mathlib breadth**.

Working evidence:

- `std:math` avoids host `libm` so bytecode/AVM, C, and native backends share the
  same source-level semantics.
- Current core includes integer/float abs/min/max/clamp, IEEE-ish predicates and
  bit helpers, rounding, `sqrt`, `powi`, `pow`, `power`, `pow2i`, `ldexp`,
  `frexp`, `exp2`, `exp`, `log2`, `ln`, `sin`, `cos`, `atan`, and `atan2`.
- `pow` / `power` cover the app-visible cases `power(2,-1)` and
  `power(2,4.3)` through deterministic integer-exponent and
  `exp2(y * log2(x))` paths. Negative bases accept integer exponents and reject
  fractional exponents as real-domain errors.
- `tests/avm/test_std_math_pow.oren` is now in the curated `make test-avm` set,
  so the iOS AVM path proves this surface in bytecode.

## Current P0 / W5 Work

1. **Runtime robustness**
   - Keep allocator, GC/reuse, green runtime, and capability gates trustworthy.
   - 2026-05-29: native quick `Error 139` is fixed; runtime identity checks now avoid recursive string-aware equality.
   - Verification entry: `make verify-runtime-robustness` plus `make test`.

2. **Performance parity**
   - Track hot loop and allocation profiles through existing benchmark/perf scripts.
   - Retain only measured aggregate wins; many narrow codegen probes have been rejected
     because they moved labels without moving wall time.

3. **Tagged value convergence**
   - Preserve cross-backend `oren_type_tag`, equality, truthiness, and panic parity.
   - Fixture gates remain the migration guard.

## Current P1 / W4 Work

1. **AVM iOS embeddability + compiler-in-AVM release gate**
   - Keep `make verify-libavm-ios` green.
   - Add Swift/Objective-C smoke host.
   - Finish lifecycle maturity: allocator ownership/reentrancy, explicit resource
     loading, and app-level failure policy.
   - Expand compiler/stdlib OBC smoke coverage beyond the current release gate.

2. **AVM fixture manifest runner**
   - Replace wildcard `AVM_TESTS` release expectations with manifest-driven per-fixture
     policy: env, expected rc/error, capabilities, deterministic mode, and gate inclusion.

3. **Cross-backend parity**
   - Expand only around real gaps; keep C/native/OBC fixtures aligned.

4. **Native scheduler and green-task maturity**
   - Keep focused runtime gates cheap and deterministic.

## Current P2 / W3 Work

- AVM allocation slabs and list-int lowering.
- Deterministic AVM child-universe scheduling and snapshot/restore maturity.
- Platform breadth for Linux/Windows/x64 paths.
- Documentation and source-file guardrails.

## Key Verification Entrypoints

```bash
./oretest
./oretest --selfhost
make test
make test-curated
make avm
make test-avm
make verify-libavm-ios
make verify-compiler-in-avm-ios-chain
make verify-backend-parity
make verify-runtime-robustness
make docs-site
```

## Documentation Guardrail

Canonical docs should describe current implementation and live blockers only. Do not
paste rolling turn logs into `docs/STATUS.md` or `docs/BLEEDING_EDGE_TASKS.md`; keep raw
evidence in `build/logs/` and short dated conclusions in focused `project-doc/` files.
