# Oren Status

**Last updated:** 2026-06-01

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
  app-facing modules such as `std:time`, `std:ui/avm`, `std:linalg`,
  `std:cbor`, `std:yaml`, `std:regex`, `std:encoding/base64`,
  `std:crypto/pem`, `std:crypto/sha1`, `std:crypto/sha256`, and
  `std:crypto/x509`.
  Broader pure-stdlib expansion should be manifest-gated so bundle build time stays
  inside the repo iteration budget.
- The embedder API can now parse, verify, load, and run `.obc` bytes from memory.
  The iOS gate compiles a tiny Oren source to `.obc`, embeds those bytes into a C
  smoke, links that smoke for iPhoneOS and simulator, and runs the same bytes
  through the host libavm embed API with argv, VFS read/write roundtrip,
  deterministic TIME, VirtualNET fixture lookup, VirtualPROC fixture/default exits,
  and captured stdout retrieval/clear.
- `make verify-libavm-ios` also builds `build/plugins/stdlib_bundle.obc` and
  `build/plugins/oren.obc`, runs the compiler `.obc` inside a child AVM universe
  with VirtualFS stdlib resources, extracts `out.obc`, and runs that bytecode.
- `make verify-libavm-ios` now also runs
  `scripts/verify_avm_stdlib_obc_surface.sh`: it rebuilds
  `build/plugins/stdlib_bundle.obc`, checks
  `tests/fixtures/avm_stdlib_obc_surface_manifest.json` against every import in
  `lib/std/stdlib_avm.oren`, rejects listed host-only modules if they leak into
  the AVM bundle, generates an Oren smoke from the manifest, compiles it with
  `--stdlib-mode obc --stdlib-obc build/plugins/stdlib_bundle.obc`, and runs the
  result in AVM. This makes bundle drift and missing app-facing exports such as
  `STD_linalg_dot_f64` fail in the repo gate.
- OBC distribution design is documented in
  `project-doc/obc_store_distribution_design_20260529.md`: after the GUI bridge
  release gate, `store.hubstack.cn` should act as the public PyPI-like OBC
  store site for app experiences that the iOS app downloads, verifies, and runs
  through `libavm`.
- Curated first-party OBC store demos are now source-controlled under
  `examples/obc_store_demos/`. `make verify-obc-store-demos` builds
  `oren-labs/science-calculator@0.1.0` and `oren-labs/ui-card-demo@0.1.0` into
  `build/obc-store-demos`, writes package manifests/index metadata, emits
  deterministic `.obc.zip` release bundles, bundles official demo source under
  `assets/source/main.oren`, and runs the generated OBC under AVM capability
  policies. The release bundle spec is documented in
  `project-doc/obc_release_bundle_spec_20260601.md`.
- The first `OrenAVMPackageStore` SDK slices are implemented. It loads a local
  `oren.obc.package.v0` directory, validates manifest shape and AVM ABI floor,
  verifies `program.obc` SHA-256, derives runtime capabilities/budgets/time mode,
  mounts read-only package assets into VirtualFS, and runs the package OBC. It can
  also fetch a store `index.json`, verify the indexed manifest SHA-256, download
  the manifest, OBC, and declared assets into an app-owned install directory,
  verify asset SHA-256 values, then reuse the local
  verifier/runner path. The iOS verifier now proves local package install/asset/run
  plus HTTP index download/install/asset/run. Signature/cert enforcement is host
  policy: apps may require trusted metadata by default, or explicitly let users run
  unsigned/untrusted OBC after confirmation. A signed-index download overload
  verifies `index.json.sig` with a trusted P-256 store key, then verifies
  trusted-publisher `p256-sha256-der` signatures over manifest hashes before
  package install; the iOS verifier proves valid signatures plus bad-index-key,
  bad-asset-hash, and bad-package-signature paths. The package store now has
  persisted app-directory lifecycle helpers for list, load, and remove installed
  packages; remote installs stage into a temporary package directory before replacing
  the final install path. Explicit install policy is implemented for signed-index
  downloads: replace, keep-existing, and fail-if-installed are SDK-visible, and the
  iOS verifier proves same-version keep/fail behavior plus a signed `0.2.0` update.
- OBC store trust/key tooling is available as `scripts/issue_obc_store_trust.sh`
  and `make issue-obc-store-trust`. It writes private P-256 keys outside the repo
  by default under `../oren-ca/private`, exports SDK-ready public key bytes and
  `trust/obc_store_trust.json`, and self-checks signing/verification.
  `OrenAVMOBCTrustBundle.loadTrustBundleAtURL(...)` now loads that JSON into
  validated SDK key material, and the package store has signed-index overloads
  that accept the bundle directly.
- The first `store.hubstack.cn` Go service slice is implemented in
  `cmd/obc-store-server` and `internal/obcstore`. It supports admin-authenticated
  publisher/package/release publish, public list/search/index/download endpoints,
  browser browse/detail/operator pages, asset serving, deterministic `.obc.zip`
  bundle upload/download/index metadata, public-by-default package visibility with
  publisher/admin private toggle, yanking, and dynamic `index.json.sig` generation
  from an external
  P-256 key path. Write endpoints now accept a deploy-safe admin bearer token
  verified by external `OBC_STORE_ADMIN_TOKEN_SHA256_HEX`, while Basic Auth
  remains for local bring-up. Publisher package/version/release writes also
  accept publisher-scoped bearer tokens limited to that publisher id, with JSON
  APIs for token rotation and revocation.
  `make verify-libavm-ios` starts this Go service, publishes a signed package via
  the service API using publisher-scoped auth, and proves iOS SDK signed-index
  install and package run from that endpoint. The release bundle format is
  specified as deterministic `.obc.zip`; the iOS SDK now prefers verified bundles
  when `bundle`/`bundle_sha256` are present in `index.json`, rejects unsafe ZIP
  paths, and falls back to expanded manifest/OBC/assets otherwise. It is not
  deployed yet.
- The sibling Note repo handoff/verifier has been updated to consume this SDK
  surface (`../note` commit `35995ee`): its AVM engine checks now require
  signed-index download APIs, install policies, trusted index/publisher key
  inputs, and the external trust issue tool. Further Note app UI work should be
  handled by the Note-side agent through that handoff.
- iOS SDK design is documented in `project-doc/ios_avm_sdk_design_20260531.md`:
  Oren should ship host-adapter SDK components so Note can use default
  app-policy-controlled FS/NET/PROC/TIME/GFX implementations instead of
  hand-writing each bridge.
  The same virtual-resource SDK pattern should later be applied to macOS, Linux,
  and Windows: platform SDKs own native providers while OBC sees only portable
  virtual handles, mailboxes, capabilities, and budgets.
- First SDK implementation slice: `scripts/build_libavm_ios.sh` now also builds
  `OrenAVMKit.xcframework`. The Objective-C API provides deterministic defaults,
  interactive app defaults for wall-clock `time.sleep_ms`, VirtualFS file helpers,
  explicit app file/directory mount and export helpers, live host-backed FS
  directory mounts, VirtualNET fixtures, VirtualPROC fixtures/defaults, OBC run,
  stdout capture, and a module map for app imports. `make verify-libavm-ios`
  compiles iOS device/simulator SDK smokes and runs a host SDK smoke that proves
  interactive sleep has real elapsed-time effect, host files can flow into/out of
  OBC through VirtualFS, and OBC can read/write real app-owned host files during
  execution through virtual FS mount paths.
- The SDK now includes an allowlisted `URLSession` prefetch helper that maps real
  host network responses into VirtualNET. `make verify-libavm-ios` starts a local
  HTTP server, fetches it through the SDK, injects the body under the requested URL,
  then runs OBC that reads it with byte-native `std:net/avm.try_get_bytes(url)`.
  The raw `oren_net_get*` intrinsics remain the AVM substrate, not the app-facing API.
  AVM still does not expose raw host networking to bytecode.
- Interactive `OrenAVMRuntimeConfig` now enables the live host-backed VNET provider
  by default, while deterministic defaults stay fixture/replay oriented. OBC still
  only sees `std:net/avm.try_get_bytes(url)` or explicit text-boundary helpers and
  the AVM NET domain; the SDK owns
  real `URLSession` access. Apps can dynamically enable, restrict, or disable live
  NET with `enableLiveNetworkWithAllowedHosts:timeoutSeconds:` and
  `disableLiveNetworkWithError:`, so user permission prompts and settings changes
  do not need hardcoded OBC builds. The SDK reuses its ephemeral `NSURLSession` for
  prefetch and live fetches instead of constructing one per OBC-triggered request.
  `make verify-libavm-ios` proves fixture, prefetch, explicit live, and interactive-
  default live fetch modes against a local HTTP server, including dynamic disable
  and re-enable through the SDK.
- AVM NET now also has virtual session handles for performance-oriented TCP/UDP/WebSocket
  networking: `std:net/avm.session_open/write/read/close` map to AVM NET ops 1-4,
  while `std:net/avm.session_select*` / `session_poll*` maps to NET op 5 for read/write readiness,
  virtual DNS maps to NET op 6, and `session_accept` maps to NET op 7,
  and embedders can install host callbacks with
  `avm_embed_set_net_session_callbacks`. The iOS SDK implements the first reviewed
  provider for `tcp://host:port`, `tcp-listen://host:port`,
  `udp://host:port`, and `ws://host:port/path` using host-owned sockets plus `select()` behind the same
  allowlist/dynamic live-NET controls. OBC receives only integer virtual session
  IDs and bytes; it never receives a socket or file descriptor. `make
  verify-libavm-ios` proves local TCP, UDP, WebSocket, and TCP listen/accept
  ping/pong plus select-before-write/read through this path.
- `std:net/avm/tcp`, `std:net/avm/udp`, and `std:net/avm/ws` now provide OBC-safe app-facing TCP/UDP/WebSocket
  convenience wrappers over virtual sessions. The iOS verifier exercises all
  three modules through live host-backed virtual sockets, so app code does not need to
  call the lowest-level `session_*` functions directly for common client/server flows.
- `std:net/avm/dns` now provides an OBC-safe DNS facade over AVM NET op 6.
  Embedders install `avm_embed_set_net_resolve_callback`; the iOS SDK maps that
  virtual DNS request to `getaddrinfo` under the same dynamic live-NET allowlist
  and timeout policy. OBC receives only address strings, not resolver handles or
  native socket descriptors.
- iOS `OrenAVMKit` now enforces live VNET session limits in the host-backed
  provider: `liveNetworkMaxSessions` caps open virtual TCP/UDP sessions, and
  `liveNetworkSessionByteLimitBytes` caps total bytes read/written per session.
  Apps can update those limits at runtime with
  `configureLiveNetworkSessionLimitsWithMaxSessions:byteLimitBytes:error:`.
  The iOS verifier proves an intentional byte-budget failure path.
- Embedders can now request or clear VM cancellation through
  `avm_embed_cancel` / `avm_embed_clear_cancel`, and iOS exposes the same
  through `requestCancelWithError:` / `clearCancelWithError:`. The iOS verifier
  proves a host thread cancels a spinning OBC program and observes AVM cancelled
  error code `6`.
- OBC packages can now publish runtime permission intent through
  `std:avm/permission.request*`, which maps to a separate `PERMISSION` capability
  domain rather than the broader nested-AVM domain. AVM stores the latest request
  as a compact `OPR0` binary mailbox; embedders read/clear it with
  `avm_embed_permission_request_get/clear`, and iOS `OrenAVMKit` exposes raw and
  decoded helpers. `OrenAVMPermissionGrantStore` now persists host decisions in
  app-owned JSON, can explicitly apply package `permission_defaults` after
  host/user policy accepts them, and can reapply NET connect grants/revocations to
  a runtime by enabling, restricting, or disabling live VNET allowed hosts. This
  lets host apps show user permission UI and then update provider policy without
  recompiling OBC.
- Performance work for virtual resources should continue as host-backed virtual
  providers, not raw OS object access from bytecode. FS follows this rule through
  host-backed directory mounts: the SDK owns app `file://` URLs and OBC sees only
  virtual paths. Remaining WebSocket fixture/replay, richer cancellation lifecycle,
  and richer lifecycle support should extend the VNET session protocol while the
  iOS SDK owns Network.framework or socket backends. UI/GFX follows the same rule:
  the SDK may use UIKit/CoreGraphics/Metal/`MTKView`, but OBC sees binary
  frame/event mailboxes and virtual resource handles only.
- The longer-term virtual-resource model should be an AVM event bus, similar in
  purpose to `select`/`kqueue`/`epoll` but over virtual handles and mailbox events:
  VNET readiness, GFX/input events, timers, cancellation, and future FS/package
  events. Host SDKs may implement that bus with platform reactors, but OBC must
  not receive raw fd sets, kqueue descriptors, native pointers, or OS handles.
- `std:avm/events` now uses a native AVM `EVENT` capability domain for timer
  watches, GFX input watches, VNET session readiness, cooperative host-cancel
  watches, and host-enqueued FS/package lifecycle events. If OBC includes a
  `cancel` watch, a host `avm_embed_cancel` request wakes the event loop as a
  `{kind:"cancel"}` event and is consumed; without a cancel watch, the same
  request remains a hard VM cancellation. The iOS SDK backs VNET multi-watch
  selection with one host `select()` over app-owned sockets and exposes
  `putVirtualEventWithKind:action:detail:flags:` for FS/package events, while OBC
  still sees only virtual watch maps and event maps.
- The first GUI bridge slices now exist as binary GFX mailboxes. Bytecode can
  publish a validated `std:ui` v0 frame through `std:ui/avm` /
  `oren_gfx_present_frame`; embedders can read and clear it with
  `avm_embed_gfx_frame_get` and `avm_embed_gfx_frame_clear`. The current `OGF0`
  frame header includes sequence, logical size, native drawable size, scale, and
  target refresh hint metadata for high-refresh/high-resolution hosts. AVM now
  validates `OGF0` frame headers/op records before accepting a frame. Hosts enqueue
  binary input events with `avm_embed_gfx_input_put`; AVM validates `OGE0` event
  headers/payload lengths before queuing them, and OBC pulls raw bytes through
  `std:ui/avm.pull_event_bytes()` or structured maps through
  `std:ui/avm.next_event()`. `poll_event_bytes()` remains a thin alias. Curated
  gates now cover malformed-frame rejection, op-count cap rejection, frame
  I/O-budget rejection, the host input queue depth cap, non-1000 resize scale
  propagation, latest-frame replacement/clear semantics, and FIFO pointer
  down/move/up ordering before mixed key/text events.
  `OrenAVMKit` exposes matching Objective-C
  helpers including a convenience binary pointer-event encoder. The iOS verifier
  checks exported symbols, device/simulator SDK linkage, and a host OBC run that
  publishes a binary frame, retrieves it through the SDK, injects a binary pointer
  event, and consumes it from OBC. `OrenAVMGraphicsView` is now the default
  UIKit/CoreGraphics 2D renderer for the current `OGF0` `fill_rect`/
  `push_clip_rect`/`pop_clip`/`push_translate`/`pop_transform`/
  `push_opacity`/`pop_opacity`/`text`/`text_bytes`/`text_resource`/
  `draw_text`/`destroy_text`/`stroke_line`/`stroke_rect`/`circle`/`ellipse`/
  `polyline`/`fill_triangle`/`image_rgba`/`draw_image`/`destroy_image`/
  `draw_image_rect`/`draw_image_rects` frame subset and can enqueue pointer, resize, key, and
  text events plus host-populated persistent screen state and runtime media-query
  events with logical size, native drawable size, device scale, target refresh,
  and host flags. OBC reads screen attributes with `std:ui/avm.screen(0)` without
  consuming an input event. `OrenAVMMetalView` is now the first Metal/`MTKView`
  adapter: it owns the Metal draw loop, publishes host screen state, forwards touch
  events into the `OGE0` mailbox, and renders current `OGF0` fill-rect/
  clip-stack/translation-stack/opacity-stack/stroke-line/stroke-rect/circle/
  ellipse/polyline/fill-triangle geometry, retained RGBA image upload/draw/
  destroy/sub-rect and batched atlas records, and byte-native/retained text
  payloads through Metal pipelines. Its `targetHzMilli` setting
  drives `MTKView.preferredFramesPerSecond`. Current text rendering uses a bounded
  SDK-side LRU texture cache for repeated labels, and host apps can clear that cache
  on memory pressure. The UI input stream now also carries validated `frame_tick`
  records so OBC game loops can receive host display timing through the same virtual
  event path instead of polling raw platform clocks. Frame ticks are coalesced so
  stale timing records cannot fill the input FIFO and starve real input. The Metal
	  view exposes SDK-side frame metrics for rendered frame count, CPU encode time,
				  target frame budget, budget-usage permille, over-budget status, geometry vertex count, and text-run count. Retained image resources are now available for sprite-like upload/draw/destroy/sub-rect and packed batched-atlas lifetimes, with Oren-side image upload budgets and SDK retained image count/pixel budgets; retained text upload/draw/destroy records now avoid resending repeated UTF-8 labels every frame, while richer glyph atlas batching remains next. UIKit/CoreGraphics
  and Metal views now forward every touch in a UIKit touch set, assign stable compact
  pointer IDs for each active touch, release IDs on end/cancel, and expose batch
  pointer-event helpers, so multi-finger input reaches OBC as multiple virtual
  pointer events instead of dropping all but one touch. The `OGE0` stream also has
  compact gamepad/controller state records, coalesced high-rate motion records,
  focus gained/lost records, and IME/composition update/commit/cancel records,
  with iOS SDK helpers for controller id, button bitmask, signed milli-normalized
  analog axes, accelerometer/gyroscope samples, focus routing, and marked-text
  selection.
  Bidirectional UI is a hard requirement for
  game-level OBC packages: OBC must publish frames and consume host-originated input
  through the same virtual protocol, while the host owns platform event APIs and
		  rendering devices. Remaining game-grade work is text atlas/sprite/mesh
			  records and richer 2D/3D command sets. The next GUI contract is
  game-grade rather than widget-only: display-link pacing, latest-frame/drop-stale
  behavior, retained resource handles, strict budgets, low-latency input ordering,
  and Metal/`MTKView` conformance gates are documented in
  `project-doc/avm_ui_render_performance_design_20260531.md`.
  The AVM release manifest also includes a whole-frame 2D raster conformance hash
	  covering geometry including `stroke_rect`, `ellipse`, `polyline`, clip and translation stacks, retained text, retained images, atlas sub-rects, batched
  sprites, and draw ordering in one scene.
- `avm_new()` now returns `NULL` on VM/stack allocation failure instead of
  dereferencing failed allocations.
- iOS embed builds define `AVM_EMBED_NO_ABORT_ON_LEAK` and `AVM_IOS_EMBED`;
  teardown leak aborts stay enabled for normal development builds, while iOS
  packaging avoids an app-process abort path.
- Host subprocess execution is compiled out of iOS embed builds; PROC must use
  the virtual backend path there. Future real work dispatch should be a reviewed
  host-backed virtual job/app-command provider with cancellation and budgets, not
  raw process/thread creation exposed to OBC.
- AVM app-facing stdlib hot paths now prefer raw bytes: `std:ui/avm` has
  `text_bytes`, `std:net/avm` has `try_get_bytes`, and `std:bytes.to_string`
  now uses direct byte-slice conversion instead of list materialization. Further
  cleanup should keep text helpers explicit at API boundaries.
- `lib/avm/avm.h` still exposes fixed global/frame/stack limits and rolling
  capability/budget fields.
- `lib/avm/avm_alloc.c` uses global allocation-owner state, which is not a polished
  reentrant embedder story.
- Curated `make avm && make test-avm` passes through
  `tests/avm/release_manifest.json`, not Makefile case arms.
- The manifest records fixture path, release-gate inclusion, expected exit/error,
  environment budgets, backend policy, deterministic mode, and host-effect checks.
  `AVM_TESTS="..."` overrides still work; paths not present in the manifest run with
  default zero-exit virtual-backend policy.
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

- Note-side Swift integration of `OrenAVMCompilerKit` and the package-store
  install/run APIs into the app UX, including diagnostics display and permission
  prompts;
- allocator ownership/reentrancy hardening or an explicit single-VM embedder policy;
- broader manifest coverage for non-curated AVM fixtures;
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

2. **AVM fixture manifest coverage**
   - Keep expanding `tests/avm/release_manifest.json` beyond the curated release-gate
     set so full-suite AVM fixtures carry explicit env, expected rc/error, backend
     policy, deterministic mode, and host-effect assertions.

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
