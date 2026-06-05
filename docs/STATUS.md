# Oren Status

**Last updated:** 2026-06-04

This is the current implementation status. It replaces the former rolling log with a
small source-of-truth snapshot. Use code, fixtures, and build logs for raw evidence.

## Overall Verdict

Oren is not yet production-stable at the level of industrial compilers such as
LLVM/rustc/GCC/zig/go. It is a rolling self-hosted compiler with meaningful working
surfaces, but the following blockers remain:

- native tagged-value convergence is incomplete;
- allocator/GC/runtime robustness is still a W5 gate;
- Tier-1 platform breadth is uneven;
- AVM now has iOS, macOS desktop, Linux x64, and Windows x64 SDK packaging gates,
  an embedder C API with argv, VirtualFS, VirtualNET, VirtualPROC, and
  stdout-capture helpers, plus a full compiler-in-AVM smoke gate, but still needs
  app-host lifecycle coverage before it should be called a complete production
  app package.

## Backend Readiness

| Backend | Current state | Production posture |
| --- | --- | --- |
| C | Portable bootstrap path through host C toolchain. | Useful baseline, not a stabilized external ABI promise. |
| Native arm64 macOS | Most mature native path; broadest profile and fixture history. | Rolling Tier-1 intent. |
| Native x64 Linux/Windows | Active bring-up with compile/runtime gates. | Not fully mature. |
| Bytecode / AVM | Deterministic VM with capability gates, budgets, snapshots, VFS/VPROC/VNET fixtures, coroutine/generator surfaces. | Experimental for production embedding. |

## AVM SDK Readiness

Current verdict: **production-chain smoke ready, not fully app-production mature**.

Facts from the 2026-05-28 implementation pass:

- `make verify-libavm-ios` builds `build/libavm/ios/LibAVM.xcframework` for
  `iphoneos-arm64` and `iphonesimulator-arm64`, exports public AVM headers, and
  links a tiny iOS embedder smoke for both SDKs.
- `make verify-libavm-desktop` builds `build/libavm/desktop/LibAVM.xcframework`
  for macOS arm64 and x86_64, exports the same public C embedder headers/module
  map, symbol-checks both static-library slices, and runs host C and Swift
  embedder smokes against OBC bytes on the local macOS architecture.
- `make verify-libavm-linux-x64` uses Zig to build
  `build/libavm/linux-x64/lib/x86_64-linux-gnu/libavm.a`, exports headers,
  a module map, and `libavm.pc`, checks the x86_64 ELF objects and embedder
  symbols, then compiles a Linux x64 C host embedder smoke. It executes that
  smoke only when `qemu-x86_64` is available or `VERIFY_LIBAVM_LINUX_X64_REQUIRE_RUN=1`
  is set.
- `make verify-libavm-windows-x64` uses Zig to build
  `build/libavm/windows-x64/lib/x86_64-windows-gnu/libavm.a`, exports headers
  and a module map, checks amd64 COFF objects and embedder symbols, then compiles
  a Windows x64 PE host embedder smoke. It executes that smoke only when Wine is
  available or `VERIFY_LIBAVM_WINDOWS_X64_REQUIRE_RUN=1` is set.
- `make verify-native-x64-compile` prewarms Linux/Windows x64 runtime-object
  seeds through the helper's explicit bounded cross-compiler compatibility probe.
  This keeps the default compile-only platform gate from looking hung on slow
  stage2 cross-target cold builds while still checking stage2 x64 fixture output.
  Host `rtobj-seed` uses the same bounded stage1 build-compiler fallback for
  missing stage2 runtime-hash seeds, keeping local NET/native matrix prewarm from
  spending minutes in repeated stage2 cold seed probes. The ARM64 Linux Docker
  leg of the native NET matrix keeps the 10s stage1 hang guard but uses a 900s
  stage2 cross-build floor because active cross-target self-hosted NET/HTTP2
  fixture compiles exceeded both the generic 120s stage2 floor and a 300s trial
  on the primary dev host.
- The default stage1 native quick gate treats any timeout-triggered retry as a
  failure and enables `OREN_QI_TRACE=1` on the diagnostic retry, so intermittent
  low-output hangs leave fixture-boundary evidence instead of being hidden by the
  broad-suite retry.
- `lib/avm/avm_embed.h` exposes an opaque-handle C embedder API with
  deterministic config, budgets, virtual FS/PROC/NET defaults, structured result
  fields, captured stdout, explicit lifecycle calls, and public app-backend helpers:
  `avm_embed_config_interactive_default`, `avm_embed_set_argv`,
  `avm_embed_vfs_put`, `avm_embed_vfs_get`,
  `avm_embed_vfs_snapshot`, `avm_embed_vnet_put`, `avm_embed_vproc_put`,
  `avm_embed_vproc_set_default_exit`, `avm_embed_set_output_capture`,
  `avm_embed_output_info`, `avm_embed_output_get`, `avm_embed_output_clear`,
  `avm_embed_set_gfx_frame_callback`, `avm_embed_gfx_frame_info`,
  `avm_embed_gfx_frame_get`, `avm_embed_gfx_frame_clear`,
  `avm_embed_gfx_input_put`, `avm_embed_permission_request_info`, and
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
  `oren-labs/science-calculator@0.1.0`, `oren-labs/ui-card-demo@0.1.0`, and
  `oren-labs/scene3d-asset-demo@0.1.0` into `build/obc-store-demos`, writes
  package manifests/index metadata, emits deterministic `.obc.zip` release
  bundles, bundles official demo source under `assets/source/main.oren`, writes
  portal-only deterministic `screenshots/preview.png` images for store
  thumbnails outside package manifests/bundles, and runs the generated OBC under
  AVM capability policies. The release bundle spec is documented in
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
  `OrenAVMPackageUpdateStatus` lets host apps query the store update endpoint from
  either an installed package or an explicit update URL before choosing an install
  policy, and remote installs persist their source index URL so later app launches
  can check updates without a separate host-side mapping table. The SDK can now
  install the latest trusted update for a reloaded package from that persisted
  source metadata, and successful installed-package checks persist a compact
  last-known update status with check time for offline host UI recovery.
- OBC store trust/key tooling is available as `scripts/issue_obc_store_trust.sh`
  and `make issue-obc-store-trust`. It writes private P-256 keys outside the repo
  by default under `../oren-ca/private`, exports SDK-ready public key bytes and
  `trust/obc_store_trust.json`, supports rotation bundles with previous store
  public keys, and self-checks signing/verification.
  `OrenAVMOBCTrustBundle.loadTrustBundleAtURL(...)` now loads that JSON into
  validated SDK key material, and the package store has signed-index overloads
  that accept the bundle directly.
- The first `store.hubstack.cn` Go service slice is implemented in
  `cmd/obc-store-server` and `internal/obcstore`. It supports admin-authenticated
  publisher/package/release publish, public list/search/index/download endpoints,
  browser browse/detail/publisher/operator pages, package detail release
  capability/source/permission/update metadata, public health build metadata, authenticated operator status page/API
  for build commit/time, registry counts, aggregate release-ready/incomplete counts, missing
  bundle/source/signature/permission readiness counts, and data-dir writable/storage
  byte totals by metadata/payload class, authenticated
	  operator release lifecycle page/API with status/visibility/readiness filters,
	  visibility, readiness, latest-published state, publish/yank/visibility action URLs,
	  and authenticated no-JS browser
  forms for publishing, yanking, and package visibility changes, authenticated
		  filterable operator update inventory page/API for latest/superseded package
		  versions by publisher/package/visibility/superseded state with total/filtered
		  counts, authenticated filterable operator audit page/API by action/actor/target with
	  append-only mutation JSONL, total/filtered counts, and deployment
  gates including active index key id, whether that key is trusted by the served
  bundle, and trust-bundle store-key count, asset serving, deterministic `.obc.zip`
  bundle upload/download/index metadata, public-by-default package visibility with
  publisher/admin private toggle, yanking, and dynamic `index.json.sig` generation
  from an external P-256 key path. Signature responses include
  `X-Oren-Signing-Key-ID` and `X-Oren-Signature-Alg` when dynamic signing is
  enabled. Write endpoints now accept a deploy-safe admin bearer token
  verified by external `OBC_STORE_ADMIN_TOKEN_SHA256_HEX`, while Basic Auth
  remains for local bring-up. Publisher package/version/release writes also
  accept publisher-scoped bearer tokens limited to that publisher id, with JSON
  APIs for token rotation and revocation. Host apps and the iOS package-store SDK
  can call
  `/api/v0/packages/{publisher}/{name}/update?current_version=...` to get
  semver-aware latest published release metadata and an `update_available` flag.
  `scripts/deploy_obc_store_service.sh` now supports `OBC_STORE_ADMIN_HOST`
  fallback from the external admin env, optional `sshpass -e` password auth via
  `OBC_STORE_SSH_PASSWORD`, an opt-in systemd service
  install/restart path, configurable listen address for Traefik, generated
  Traefik dynamic route YAML, build commit/time stamping for deployed binaries,
  an optional remote `/api/v0/health` probe, and an
  optional authenticated remote `/api/v0/ops/status` storage/readiness probe.
  The live cloud host currently runs
  `oren-obc-store.service` on `172.20.0.1:18080` and Dockerized Traefik routes
  `https://store.hubstack.cn/` to that backend; `/healthz` and `/api/v0/health`
  are public smoke endpoints for browser/API reachability. `make
  verify-obc-store-live-route` checks the public HTTPS route, public index, and
  first-party demo package visibility, while
	  `OBC_STORE_LIVE_REQUIRE_RELEASE_READY=1` upgrades missing build metadata
	  plus signed-index/trust/update endpoint warnings into deployment failures, and live-route credentials enable
	  authenticated operator-status storage/readiness validation. The current local
	  deploy attempt reaches the configured `OBC_STORE_ADMIN_HOST` but SSH rejects
	  both public-key batch mode and the available password, so live replacement
	  requires corrected host credentials before strict readiness can pass. `make
	  verify-obc-store-backup-restore` publishes a fixture package, copies the
	  file-backed store data directory, and proves a restored service preserves
	  index metadata plus program, bundle, and asset bytes. The live store is
  populated with first-party `oren-labs` `science-calculator`, `ui-card-demo`,
  and `scene3d-asset-demo` `.obc.zip` releases with screenshot previews from
  `examples/obc_store_demos/`.
  Package detail pages render declared Oren source assets through a server-side
  syntax/AST-outline viewer, while raw API asset downloads remain available for
  install tooling.
  `make verify-libavm-ios` starts this Go service, publishes a signed package via
  the service API using publisher-scoped auth, and proves iOS SDK signed-index
  install and package run from that endpoint. The release bundle format is
  specified as deterministic `.obc.zip`; the iOS SDK now prefers verified bundles
  when `bundle`/`bundle_sha256` are present in `index.json`, rejects unsafe ZIP
  paths, and falls back to expanded manifest/OBC/assets otherwise.
- The sibling Note repo handoff/verifier has been updated to consume this SDK
  surface (`../note` commit `86efc55`): its AVM engine checks now require
  signed-index download APIs, install policies, trusted index/publisher key
  inputs, trusted persisted update installs, visible update-status checks, and
  the external trust issue tool. The package manager exposes Check/Recheck status
  actions and a trusted Update action for installed OBC packages.
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
  then runs OBC that reads it as `http.get(url).bytes()` through
  `std:net/avm/http`.
  The raw `oren_net_get*` intrinsics remain the AVM substrate, not the app-facing API.
  AVM still does not expose raw host networking to bytecode.
- Interactive `OrenAVMRuntimeConfig` now enables the live host-backed VNET provider
  by default, while deterministic defaults stay fixture/replay oriented. OBC still
  only sees `std:net/avm/http` request/response helpers and the AVM NET domain; the SDK owns
  real `URLSession` access. Apps can dynamically enable, restrict, or disable live
  NET with `enableLiveNetworkWithAllowedHosts:timeoutSeconds:` and
  `disableLiveNetworkWithError:`, so user permission prompts and settings changes
  do not need hardcoded OBC builds. The SDK reuses its ephemeral `NSURLSession` for
  prefetch and live fetches instead of constructing one per OBC-triggered request.
  `make verify-libavm-ios` proves fixture, prefetch, explicit live, and interactive-
  default live fetch modes against a local HTTP server, including dynamic disable
  and re-enable through the SDK.
- AVM NET now also has virtual socket/session handles for performance-oriented TCP/UDP/WebSocket
  networking: `std:net/avm/socket.open/write/read/close` map to AVM NET ops 1-4,
  while `std:net/avm/socket.select*` / `poll*` maps to NET op 5 for read/write readiness,
  virtual DNS maps to NET op 6, and `std:net/avm/socket.accept` maps to NET op 7,
  and embedders can install host callbacks with
  `avm_embed_set_net_session_callbacks`. The iOS SDK implements the first reviewed
  provider for `tcp://host:port`, `tcp-listen://host:port`,
  `udp://host:port`, and `ws://host:port/path` using host-owned sockets plus `select()` behind the same
  allowlist/dynamic live-NET controls. OBC receives only integer virtual session
  IDs and bytes; it never receives a socket or file descriptor. `make
  verify-libavm-ios` proves local TCP, UDP, WebSocket, and TCP listen/accept
  ping/pong plus select-before-write/read through this path.
- `std:net/avm/http`, `std:net/avm/socket`, `std:net/avm/tcp`, `std:net/avm/udp`,
  and `std:net/avm/ws` now follow the same split as Python/Go network libraries:
  request/response HTTP helpers are separate from socket/session primitives, and
  protocol facades wrap the lower-level virtual socket module. Virtual socket/TCP/UDP
  sessions expose receiver methods (`session.read(...)`, `session.write(...)`,
  `listener.accept(...)`, `session.send(...)`, `session.recv(...)`, readiness waits,
  and `session.close()`) while retaining raw integer session ids as the OBC ABI for
  low memory overhead. The iOS verifier exercises TCP/UDP/WebSocket through live
  host-backed virtual sockets, so app code does not need to call `std:net/avm/socket`
  directly for common client/server flows.
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
  decoded helpers plus `OrenAVMPermissionPrompt`, a Foundation-only prompt model
  with stable title/message/risk metadata for host-native UI. `OrenAVMPermissionGrantStore`
  now persists host decisions in app-owned JSON, records decisions from prompts,
  can explicitly apply package `permission_defaults` after host/user policy accepts
  them, and can reapply NET connect grants/revocations to a runtime by enabling,
  restricting, or disabling live VNET allowed hosts. This lets host apps show user
  permission UI and then update provider policy without recompiling OBC. The Note
  app handoff now also has an ObjC bridge wrapper, Swift DTO, source/imported-OBC
  live-run prompt presentation, and explicit Allow/Deny decisions persisted through
  `OrenAVMPermissionGrantStore`; future live runs apply that grant store before
  execution so approved NET hosts become runtime policy.
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
	  `oren_gfx_present_frame`; embedders register `avm_embed_set_gfx_frame_callback`
	  for event-driven frame wakeups and then read/clear accepted frames with
	  `avm_embed_gfx_frame_get` and `avm_embed_gfx_frame_clear`. The sequence-aware
	  `avm_embed_gfx_frame_info` call is a no-copy fallback/diagnostic path for
	  constrained hosts, not the default render-loop transport. The current `OGF0`
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
	  publishes multiple binary frames through the event callback path, verifies the
	  first and final callback sequence/length metadata, retrieves the retained
	  frame through the SDK, feeds multiple distinct frames through the same SDK
	  renderer objects, injects a binary pointer event, and consumes it from OBC.
	  The nested compiler-in-AVM phases in the iOS verifier emit periodic PID/CPU
	  progress diagnostics and fail through a bounded watchdog, so silent long
	  runs are handled as hang symptoms rather than assumed-normal delays.
	  `OrenAVMGraphicsView` is now the default
  UIKit/CoreGraphics 2D renderer for the current `OGF0` `fill_rect`/
  `push_clip_rect`/`pop_clip`/`push_translate`/`pop_transform`/
  `push_opacity`/`pop_opacity`/`push_camera_ortho`/`pop_camera`/`text`/`text_bytes`/`text_resource`/
  `draw_text`/`draw_texts`/`destroy_text`/`stroke_line`/`stroke_rect`/`round_rect`/`circle`/`ellipse`/
  `polyline`/`fill_triangle`/`fill_triangles`/`mesh2d`/`draw_mesh2d`/`destroy_mesh2d`/
  `mesh3d`/`mesh3d_rgba`/`mesh3d_indexed`/`material3d`/`model3d`/`draw_mesh3d`/`draw_mesh3d_at`/`draw_mesh3d_material`/`draw_mesh3d_at_material`/`draw_model3d`/`destroy_mesh3d`/`destroy_material3d`/`destroy_model3d`/`image_rgba`/`draw_image`/`destroy_image`/
  `draw_image_rect`/`draw_image_rects` frame subset and can enqueue pointer, resize, key, and
  text events plus host-populated persistent screen state and runtime media-query
	  events with logical size, native drawable size, device scale, target refresh,
	  and host flags. OBC reads screen attributes with `std:ui/avm.screen(0)` without
		  consuming an input event. `OrenAVMRuntime.graphicsFrameHandler` bridges the
		  C frame callback to iOS hosts, `addGraphicsFrameHandler:` provides multicast
		  frame wakeups so renderers and host diagnostics do not steal callbacks from
		  each other, the native GFX mailbox is mutex-protected for worker-thread
		  publication plus main-thread rendering, both SDK renderers expose
		  `hasValidFrameData`, and `reloadFrameWithError:` is no-op success when the
		  runtime mailbox is empty, so event-driven render loops can keep the last
		  valid `OGF0` frame instead of surfacing stale no-frame reloads as renderer
		  failures. `OrenAVMMetalView` is now the first Metal/`MTKView`
  adapter: it owns the Metal draw loop, publishes host screen state, forwards touch
  events into the `OGE0` mailbox, and renders current `OGF0` fill-rect/
  clip-stack/translation-stack/opacity-stack/camera-depth-window/stroke-line/stroke-rect/round-rect/circle/
  ellipse/polyline/fill-triangle/fill-triangles geometry, retained 2D mesh resources, retained 3D mesh resources with orthographic XY default projection, per-triangle RGBA payloads, indexed shared-vertex meshes, retained material resources, retained model resources, deterministic painter-depth ordering, per-draw and retained model translation/uniform scale, material override draws, and explicit orthographic camera depth windows, retained RGBA image upload/draw/
  destroy/sub-rect and batched atlas records, and byte-native/retained text
  payloads through Metal pipelines. Its `targetHzMilli` setting
  drives `MTKView.preferredFramesPerSecond`. Current text rendering uses a bounded
  SDK-side LRU texture cache for repeated labels, and host apps can clear that cache
  on memory pressure. The UI input stream now also carries validated `frame_tick`
	  records so OBC game loops can receive host display timing through the same virtual
	  event path instead of polling raw platform clocks. Frame ticks are coalesced so
	  stale timing records cannot fill the input FIFO and starve real input, and SDK
	  renderer frame-wakeup callbacks coalesce pending main-queue reloads so a fast
	  publisher consumes the latest retained frame without building an unbounded UI
	  task backlog. The Metal
  view exposes SDK-side frame metrics for rendered frame count, CPU encode time,
	  target frame budget, budget-usage permille, over-budget status, geometry vertex count, and text-run count. Retained image resources are now available for sprite-like upload/draw/destroy/sub-rect and packed batched-atlas lifetimes, retained 2D and first retained 3D mesh resources avoid resending repeated triangle geometry, and Oren-side image upload budgets plus SDK retained image count/pixel budgets bound sprite memory; retained text upload/draw/destroy and packed retained text batching now avoid resending repeated UTF-8 labels, while Metal packs rendered labels into bounded atlas textures and coalesces adjacent same-atlas/scissor/opacity runs to reduce text draw calls. UIKit/CoreGraphics
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
  rendering devices. `std:ui/scene3d` now provides pure OBC-side builders for
  retained mesh/material/model scene command lists and can load JSON or
  byte-native `.os3d` scene assets from package-mounted VirtualFS paths,
  including scene-level camera depth windows. Reviewable JSON scene assets can
  now use named mesh/material/model references plus model templates,
  instances, grouped instances with parent transform composition, and per-draw
  model/material/transform override objects that lower to generated retained
  models, human-readable `position_xyz` or nested `transform` records,
  human-readable `vertices_xyz` / `faces` or `quads` coordinate arrays,
  builder-side glTF 2.0 JSON/GLB `gltf_source` plus inline JSON `gltf_json` with URI or GLB BIN buffers, sparse accessors, static `POSITION` and `COLOR_0` morph target weights, baked skinning through `JOINTS_n`/`WEIGHTS_n` and inverse bind matrices, sampled `gltf_animation` / `gltf_sample_time_milli` node translation/rotation/scale/morph-weight animations, material base colors multiplied by `COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix hierarchy selection, Wavefront OBJ `obj_source` / `obj_text`, binary-or-ASCII STL `stl_source`, inline ASCII STL `stl_text`, binary-or-ASCII PLY `ply_source`, inline ASCII PLY `ply_text`, PLY face/vertex colors lowered to `mesh3d_rgba`, and core 3MF `3mf_source` ZIP mesh/build plus basematerial `displaycolor` lowering and optional `3mf_triangle_set` subgroup selection,
  `triangles_xyz` or `quads_xyz` direct meshes, compact `boxes_xyz`
  cuboid primitives, `prisms_xy` extruded polygon solids, bounded
  `cylinders_z`, `cones_z`, `spheres_xyz`, `ellipsoids_xyz`, `toruses_xyz`, and `capsules_z` primitives, and per-triangle
  `triangles_xyz_rgba` colors. Curved solid packers now live in the
  dedicated `std:ui/scene3d_shapes` helper module, keeping the retained-scene
  orchestration file small enough for continued package-format expansion
  without changing the public JSON schema or renderer ABI.
  Material authoring accepts `color` or
  `base_color` plus optional `opacity_milli`, `roughness_milli`, and
  `metallic_milli`, lowering the v0 renderer-visible output to deterministic
  `material3d` colors. JSON loaders can sample transform keyframes via
  `commands_from_*_at(..., time_milli)`, while the package builder uses
  `sample_time_milli` to lower animated authoring assets into static numeric
  `.os3d` records for the hot runtime path. The iOS SDK verifier now also
  runs an `OrenAVMPackageStore` package that mounts a bundled `.os3d` scene
  asset and raster-checks it through OBC. `OrenAVMMetalView` now exposes
  drawable-independent `prepareFrameResourcesWithError:` so host apps and
  headless verifiers can parse retained 3D/resource frames and inspect vertex,
  text-run, and image-run metrics even when no `CAMetalDrawable` is available.
  `make capture-ios-live-3d-performance` now builds a generated iPhoneOS app
  harness that runs a 3D OBC frame through `OrenAVMMetalView`, records device
  preflight data, and can install/launch through `devicectl` to write live
  CPU/vertex/run metrics when a matching provisioning profile and device
  developer services are available. The 2026-06-05 preflight saw `blu-ip`
  paired in `devicectl`, but `xctrace` still listed it offline and CoreDevice
  reported `ddiServicesAvailable=false`, so the actual live run remains blocked
  by device/developer-service state rather than renderer code.
  Remaining game-grade work is completing a signed live-device 3D capture run
  and broader package scene formats. The next GUI contract is
  game-grade rather than widget-only: display-link pacing, latest-frame/drop-stale
  behavior, retained resource handles, strict budgets, low-latency input ordering,
  and Metal/`MTKView` conformance gates are documented in
  `project-doc/avm_ui_render_performance_design_20260531.md`.
  The AVM release manifest also includes a whole-frame 2D/3D-projection raster conformance hash
	  covering geometry including `stroke_rect`, `round_rect`, `ellipse`, `polyline`, clip and translation stacks, retained text, retained images, atlas sub-rects, batched
	  sprites, retained 2D meshes, retained 3D triangle and indexed meshes through orthographic projection, painter-depth ordering, camera depth-window culling, and draw ordering in one scene. A dedicated 3D conformance fixture separately hashes retained 3D resource behavior across camera depth windows, model translation/scale/Z, per-triangle RGBA depth ordering, indexed shared-vertex meshes, material override draws, and retained model-resource draws.
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
  `text_bytes`, direct text/composition event payload string slicing, and
  exact-size `u8_buf` OGF0 frame encoding with direct string-byte writes for
  plain `text` commands instead of final list-to-byte packing,
  `std:ui/color` parses hex colors directly from ASCII string bytes,
  `std:ui/scene3d` lowers coordinate/face/quad/color package assets through
  exact-size `u8_buf` builders and emits color hex digits through string slices,
  `std:net/avm/http` has request/response helpers,
  native `std:net/http` caches typed response body bytes for `.bytes()` on
  content-length and chunked responses, `std:bytes.to_string` now uses direct
  byte-slice conversion instead of list materialization, `std:bytes.from_string`
  and `from_hex` plus `std:strings` byte roundtrips now use byte-native u8 buffers,
  `std:bytes` get/unpack/concat/copy sources read u8-buffer carriers directly,
  while u8/endian writes and `copy_into` keep list-backed compatibility
  while raw u8-buffer loads/stores plus u8 slice/strided/matrix view
  loads/stores use raw pointer access after public validation, contiguous u8
  concat/copy spans use raw pointer byte copies, and overlapping in-place u8
  `copy_into` copies backward when needed, `std:buffer` view/matrix
  `copy_from_bytes` helpers read byte carriers directly and route contiguous
  slice/dense-matrix u8 destinations through `bytes.copy_into`, while
  contiguous slice/dense-matrix byte and text exports use direct byte-slice
  conversion,
  JSON full decode, scalar parse, tag equality, and escape paths
  use direct source-string byte reads or exact-size `u8_buf` output, CBOR canonical
  key ordering/text encoding plus u8-backed decode byte carriers, full regex
  pattern/text matching, and public `std:strings`
  prefix/suffix/search/equality/trim helpers use direct string byte reads and
  slices, YAML comment stripping, quoted-scalar parse/escape, line/trim/key
  split, key sort, bare-identifier, prefix, and suffix helpers avoid
  list-of-byte reconstruction, and XML/HTML parser literal matching,
  class-selector scans, DOM parsing, and streaming readers use direct
  source-string byte reads instead of repeated input byte-list materialization.
  WebSocket accept hashing now feeds SHA-1 directly from UTF-8 string bytes,
  and native WebSocket header slices plus unmasked frame payloads copy with
  `oren_memcpy`; DNS QNAME labels and capsule NET IPv4 sockaddr reads/rewrites
  copy through `oren_memcpy` after validation;
  Base64 decode/encode writes exact-size output buffers directly, PPM header/body
  output and software raster clear/pixel writes now use raw exact-size buffer stores, and
  native `oren_write_file` writes strings directly through syscalls without a
  transient byte list. SHA-1/SHA-256 can now hash UTF-8 strings directly, and Windows
  Schannel passphrase cache keys use that path instead of materializing a
  byte list, SHA-1/SHA-256 digest buffers finalize through direct unchecked
  u8 stores after exact-size allocation, and native SHA-256 contiguous input
  remainders copy with `oren_memcpy`. Compiler source-policy scans, scan-cache line/number parsing and delimiter writes, C-runtime
  include scanning, compiler manifest JSON escaping, bytecode metadata payloads,
	  bytecode string constants, OBX string/prefix encoding, AST binary v1 full-value raw
	  writes, native Mach-O/ELF object string payloads, runtime-object debug-name
	  blobs, x64 native debug-table names, ARM64 native panic-message payloads,
	  native capsule mount path resolution, realpath segment output, readdir names,
	  and UNIX-socket path copies through `oren_memcpy`, shared compiler
	  byte-builder append/list/string/set stores, C identifier
  escaping with raw exact-size output writes, and raw u8/view/u8-matrix string copy
  helpers now do the same.
  `std:buffer`
  `[]u8`, u8 slice/strided view, and u8 matrix string/byte conversions now lower
  through `u8_buf` byte slices instead of unpacking to Oren lists first, and
  direct byte slice helpers reject out-of-bounds spans before native conversion.
  Codec and byte APIs now expose trait-backed method surfaces for the rolling
  stdlib style: `"{}".json().text()`, `"a: 1\n".yaml().text()`,
  `cbor.cint(7).bytes().cbor()`, `"hi".bytes().text()`,
  `"hi".bytes().base64()`, `"aGk=".base64_bytes().text()`, and
  `bytes.from_string("abc").sha256_hex()` work through source and
  stdlib-OBC metadata paths without explicit local annotations.
  The module renamer now preserves builtin annotation names such as `bytes`
	  even when an import alias uses the same spelling, so trait impls for builtin
	  types stay available to chained method lowering instead of becoming
	  accidental module-local alias types.
	  `std:xml` / `std:html` add deterministic DOM/query APIs plus streaming
	  readers for memory-budgeted payloads. Native `std:net/http` composes
	  response objects with `.html()`, `.xml()`, `.html_reader()`, and
	  `.xml_reader()`; AVM/OBC keeps the default bundle lean and composes through
	  explicit codec imports such as `http.get(url).text().html_reader()` when a
	  package opts into HTML/XML parsing.
	  Pure Oren SHA-1/SHA-256 now validate bytes in place, expose canonical
	  `digest` / `hex` / receiver-method APIs, and process virtual padding via
	  indexed byte access instead of unpacking the whole message to a list, and
	  write fixed-size digest `u8_buf` outputs directly instead of packing
	  result byte lists. Native crypto RNG now fills its result `u8_buf`
	  directly. HPACK plain literal decode now slices the header block directly,
	  while Huffman string encode/decode, decoded-string boundaries, and full
	  header-block encoding use exact-size `u8_buf` payloads or byte-slice
	  conversion instead of building intermediate Oren byte lists; TLS ALPN
	  decoded-byte strings also convert through byte slices. HTTP/2 client
	  continuation/header-block buffers now copy through native `oren_memcpy`,
	  and native WebSocket header slices/unmasked frame payloads plus DNS QNAME
	  labels use the same native copy path. PEM relaxed decode passes body slices
	  to Base64 directly, and strict decode concatenates body lines through raw
	  exact-size `u8_buf` writes instead of a byte list. JSON, YAML, CBOR,
	  Base64, regex, PEM/X509, `std:time` ISO-8601 UTC parsing, native string
	  concat/intern/slice copies, native byte-order writes, crypto RNG, HPACK,
	  HTTP/2 parser records, UI color parsing/hex emission, PPM encoding, public
	  `std:bytes` helpers, public `std:buffer` facade plus importable
	  `std:buffer` raw/view/core/numeric/u8-matrix helpers including u8 view
	  stores, public `std:buffer` root/view/matrix helpers including matrix
	  projection helpers, public `std:strings` / `std:list` helpers, public
	  `std:linalg` root helpers, public `std:iter` range helpers, public
	  SHA-1/SHA-256 digest helpers, UI validate/raster/PPM helpers, and checked
	  `std:ints` / `std:casts` helpers now use canonical fallible verbs or
		  `{ok,...}` records (`parse`, `encode`, `decode_bytes`, `compile`,
		  `bytes`, `bytes.pack`, `bytes.get_u32_le`, `load_i32`, `mat_row_to_bytes`,
			  `strings.slice`, `list.get`, `linalg.dot_f64_buf`, `iter.range`,
			  `sha256.hex`, `ui_cmds.validate`, `ui_raster.rasterize`,
			  `ppm.write_rgba_ppm`, `ints.checked_u8`, etc.) instead of public
		  `try_*` names, while raw errno-style or low-level implementation
		  internals are explicit `*_raw` or private module helpers. Base64 encoding now writes exact-size `u8_buf` output instead of materializing an
		  intermediate Oren list. NET cleanup now covers native and AVM session
		  objects: native TCP/UDP/TLS handles expose `.read_into(...)`,
		  `.write_from(...)`, `.send_to(...)`, `.recv_from_into(...)`,
		  TLS certificate/ALPN methods, and `.close()`, native WebSocket records
		  expose `.recv_text(...)` / `.send_text_client(...)`, and AVM virtual
		  socket/TCP/UDP/WebSocket sessions expose read/write/send/recv, readiness
			  waits, accept, and close receiver methods. Native HTTP/2 client state now
				  uses a typed `Client` receiver with `client.request(...).text()` /
				  `.bytes()` response methods. Public fallible NET APIs now use normal
				  verbs returning `value | oren_err` or explicit `{ok,...}` records;
				  DNS/host resolution exposes `query_a`, `resolve_a`, and
				  `resolve_host_ipv4` records, while syscall-style errno contracts are
				  explicit `*_raw` primitives.
  buffer pass fixed unchecked f64 typed-buffer stores to write IEEE-754 bits
  instead of truncating fractional values through integer byte writes. Further
  cleanup should keep text helpers explicit at API boundaries.
- `lib/avm/avm.h` still exposes fixed global/frame/stack limits and rolling
  capability/budget fields.
- `lib/avm/avm_alloc.c` keeps allocation-owner, unbudgeted-allocation, and
  last-allocation-error context thread-local. Separate `LibAVM` handles may run
  on separate host threads. A single VM/handle remains host-thread-confined for
  mutation/teardown, but concurrent same-handle run attempts now fail fast with
  `AVM_EMBED_ERR_BUSY` instead of racing VM program state.
- Curated `make avm && make test-avm` passes through
  `tests/avm/release_manifest.json`, not Makefile case arms.
- The manifest records fixture path, release-gate inclusion, expected exit/error,
  environment budgets, backend policy, deterministic mode, setup builds,
  multi-phase record/replay or snapshot/resume runs, line-prefix captures,
  cross-phase assertions, and host-effect checks.
  `AVM_TESTS="..."` overrides still work; paths not present in the manifest run with
  default zero-exit virtual-backend policy.
- The default AVM release gate now also covers portable stdlib bytes/buffer view
  APIs, bytes/endian helpers, u8 buffer iteration, checked and wrapping integer
  casts, call-stack discipline, explicit result/state hashing, attributes,
	  bool/float ops, for/for-in lowering over lists/maps/strings/bytes, generic
	  call specialization, varargs call/spread and spawn/spread packing, literal bases,
	  container mutation/iteration, map key ordering/type hashes, pack views,
	  task/group surfaces, deterministic join
	  timeout, gas/timeout/IO/log/heap budget aborts, bounded trace diagnostics,
	  trace-byte heap-budget exemption, capsule/default-deny FS policy, VFS helpers,
	  host FS mounts, nested multiverse AVM/VNET/VPROC/VFS fixtures, VFS inheritance
	  plus host-prefix inheritance, record/replay env/exit/FS/proc flows,
	  snapshot/resume tasks/VFS/record-log flows, state-hash VFS inclusion,
	  trace-byte repeat/native-event coverage, deterministic math core/rounding, exp/log,
	  trig/inverse-trig/atan vectors, float diagnostic formatting, crypto hash vectors, iterator
	  ranges, retained-3D draw-only frame republishing, and Scene3D package-asset authoring rather than leaving those as
	  ad-hoc focused fixtures.

Detailed note: `project-doc/ios_avm_readiness_20260507.md`.

## Compiler-in-AVM

Current verdict: **release-gated smoke path is green**.

Working evidence:

- `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren` loads
  `build/oren_compiler.obc` into a nested AVM universe and compiles a small program
  through VFS.
- `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren` additionally
  passes `build/stdlib_bundle.obc` as a stdlib OBC resource and compiles/runs
  the shared `tests/fixtures/ios_avm/compilerkit_app_scale.oren` program. The
  child program covers generic-constrained trait receiver methods, struct field chains,
  Base64/SHA/JSON/YAML/CBOR method chains, checked integer casts, iterator
  ranges, zero-copy buffer slice/matrix receiver chains, linalg fallible APIs,
  Scene3D package authoring, and time.
- `scripts/verify_compiler_in_avm_ios_chain.sh` builds both OBC resources with
  `./oren`, runs the stdlib-OBC nested compiler harness through `./avm`, and is
  called by `make verify-libavm-ios`.
- The iOS SDK implementation is split so `OrenAVMRuntimeConfig` and
  `OrenAVMRunResult` live in `OrenAVMRuntimeTypes.m`, while
  `OrenAVMGraphicsView` lives in its own UIKit/CoreGraphics implementation file;
  this keeps the core runtime file below the 2000-line source guardrail while
  GUI/NET/FS providers continue to grow. `make verify-source-line-guard` now
  checks tracked first-party source files against that limit while excluding
  generated site, archived web research, vendor, and build artifacts.
- The retained fixes include child-owned OBC constant parsing with explicit VM
  ownership flags, a larger explicit AVM global table cap for the compiler OBC,
  VFS `write_bytes` support for BYTES, current CLI args (`--platform`,
  `--no-cache`) for embedded compiler runs, and SDK-visible CompilerKit compile
  budgets so host apps can size full-stdlib OBC compilation deliberately.
- Generic monomorphization now reruns impl/method lowering after specialization,
  so methods inside generated generic function clones constrained by a trait
  lower to concrete impl functions instead of falling back to runtime member lookup. The dedicated
  AVM regression is `tests/avm/test_generic_trait_constraints.oren`.

Missing for production:

- Note-side Swift integration of `OrenAVMCompilerKit` and the package-store
  install/run APIs into the app UX, including diagnostics display and permission
  prompts;
- continued manifest promotion for non-curated AVM fixtures where runtime cost is
  justified;
- broader multi-file compiler-in-AVM app suites, richer diagnostics capture, and
  CI coverage beyond the current curated app-scale fixture.

## Scientific Stdlib Math

Current verdict: **portable deterministic foundation, still expanding toward C/C++
mathlib breadth**.

Working evidence:

- `std:math` avoids host `libm` so bytecode/AVM, C, and native backends share the
  same source-level semantics.
- Current core includes integer/float abs/min/max/clamp, IEEE-ish predicates and
  bit helpers, normal/subnormal classification, rounding, `fmod`, nearest-even
  `remainder`, `modf`, public ties-to-even rounding aliases, degree/radian
  conversion, `ilogb` / `logb`, `fdim`, `nextafter` / `nexttoward`, `sqrt`,
  `cbrt`, `powi`, `pow`, `power`, `pow2i`,
  `ldexp`, `frexp`, `scalbn`, `scalbln`, `exp2`, `exp`, `expm1`, `exp10`, `log1p`, `log2`, `ln`,
  `log10`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `sin`, `cos`,
  `tan`, `atan`, `atan2`, `asin`, `acos`, `erf`, and `erfc`.
- `pow` / `power` cover the app-visible cases `power(2,-1)` and
  `power(2,4.3)` through deterministic integer-exponent and
  `exp2(y * log2(x))` paths. Negative bases accept integer exponents and reject
  fractional exponents as real-domain errors.
- `tests/avm/test_std_math_core.oren`, `tests/avm/test_std_math_pow.oren`,
  `tests/avm/test_std_math_decompose.oren`,
  `tests/avm/test_std_math_exp_log.oren`, and
  `tests/avm/test_std_math_trig.oren` are now in the curated `make test-avm`
  set, so the iOS AVM path proves core predicates/rounding/fmod/remainder/sign
  helpers, public ties-to-even rounding aliases, degree/radian conversion,
  normal/subnormal classification,
  `ilogb`/`logb`, `fdim`, `nextafter`/`nexttoward`,
  pow, `modf`, `frexp`/`ldexp`/`scalbn` decomposition and scaling, `cbrt`, `hypot`,
  exp/log/log2/log10, cancellation-aware `expm1`/`log1p`, hyperbolic
  `sinh`/`cosh`/`tanh`, and inverse hyperbolic `asinh`/`acosh`/`atanh`,
  approximate real-valued error functions `erf`/`erfc`, finite sin/cos/tan reduction, quadrant `atan2`,
  inverse-trig `asin`/`acos`, and
  non-finite error behavior in bytecode.
- The huge-trig Payne-Hanek fixture now uses a meaningful 2^40 periodicity
  vector and is release-gated in AVM. The earlier 2^53 assertion was invalid:
  at that magnitude `x + tau` rounds to `x + 6`, not `x + 2pi`, so it tested
  floating-point addition granularity rather than trig periodicity.

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
   - Preserve allocator thread-local owner isolation, same-handle run guardrails,
     explicit resource loading, and app-level failure policy as SDK wrappers grow.
   - Keep expanding compiler/stdlib OBC coverage beyond the shared app-scale
     fixture toward multi-file app suites and CI-hosted lifecycle checks.

2. **AVM fixture manifest coverage**
   - Existing `tests/avm/test_*.oren` fixtures now carry manifest metadata.
   - Keep adding explicit manifest policy when new AVM fixtures or host-effect
     surfaces are introduced.

3. **Cross-backend parity**
   - Expand only around real gaps; keep C/native/OBC fixtures aligned.
   - 2026-06-02: native helper-wrapped numeric casts now use shared CoreIR
     direct-call parameter trait inference. Monomorphic float/int evidence marks
     native params for correct carrier lowering; mixed or unknown generic evidence
     remains explicit instead of guessing from untagged runtime bits.
   - 2026-06-05: native top-level global initializers now preserve precomputed
     float-return carrier traits through the synthesized startup assignment path,
     so unannotated `std:math` float results compare correctly on arm64 native and
     x64 native compile metadata stays aligned.

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
