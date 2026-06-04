# iOS AVM SDK Design

## Decision

Yes: Oren should provide an iOS host-adapter SDK on top of `libavm` and the
compiler-in-AVM package. The SDK should make the Note app integration small and
boring: the app should configure policy, attach views/resources, and receive
results, while Oren/libavm define portable semantics and enforce capability
budgets.

The SDK must not make OBC programs native iOS plugins. OBC remains untrusted data
executed by AVM. The SDK supplies default iOS implementations for approved host
surfaces.

All platform effects follow the same rule: the host implementation may be real
and high-performance, but OBC only sees AVM virtual protocols. That means virtual
paths for FS, virtual responses/session handles for NET, virtual app commands for
PROC, virtual clocks/sleeps for TIME, and binary frame/input mailboxes or resource
handles for UI/GFX. No UIKit/Metal object, native socket, file descriptor, process
handle, or raw host pointer should become bytecode-visible state.

```text
Oren source / OBC
  -> std:fs / std:net / std:proc / std:time / future std:gfx/std:input
  -> libavm capability gates, budgets, VFS/VNET/VPROC/TIME/GFX mailboxes
  -> OrenAVMKit iOS adapters
  -> Note app UI, sandbox, URLSession, Metal/MTKView, app lifecycle
```

## Implementation Status

Retained SDK slices on 2026-05-31:

- `scripts/build_libavm_ios.sh` builds `OrenAVMKit.xcframework` next to
  `LibAVM.xcframework`.
- `sdk/ios/OrenAVMKit/OrenAVMKit.h` plus focused `.m` implementation files
  provide an Objective-C API usable from Swift/Objective-C apps. Runtime
  configuration/result value types live in `OrenAVMRuntimeTypes.m`, and the
  UIKit/CoreGraphics renderer lives in `OrenAVMGraphicsView.m`, so the core
  runtime file stays below the source-size guardrail as providers grow.
- `OrenAVMRuntimeConfig deterministicDefaults` keeps deterministic virtual TIME
  and virtual FS/NET/PROC.
- `OrenAVMRuntimeConfig interactiveAppDefaults` keeps virtual FS/NET/PROC, switches
  TIME to wall-clock mode so `std:time.sleep_ms` delays the AVM worker, and enables
  the live host-backed VNET provider by default.
- `OrenAVMRuntime` exposes argv, VirtualFS put/get, VirtualNET fixture put,
  VirtualPROC fixture/default puts, OBC byte execution, and stdout capture.
- `OrenAVMRuntime` also exposes app file/directory mount helpers, VFS export
  back to a host file URL, and live host-backed directory mounts. The verifier
  mounts a host asset directory into VirtualFS, exports a VFS output back to the
  host filesystem, and separately mounts a real app-owned directory so OBC
  `oren_read_file`/`oren_write_file` access host files during execution through
  virtual paths.
- `make verify-libavm-ios` compiles iOS device/simulator SDK smokes and runs a
  host SDK smoke proving interactive `time.sleep_ms(25)` has real elapsed-time
  effect.
- `OrenAVMRuntime fetchURLIntoVirtualNet:allowedHosts:timeoutSeconds:error:`
  provides the first app-usable NetworkProvider slice. The SDK owns the host
  `URLSession` request, enforces an allowlisted host and timeout, then injects
  the response bytes into VirtualNET under the original URL. OBC code uses the
  portable object-style `std:net/avm/http.get(url).bytes()` /
  `std:net/avm/http.get(url).text()` response methods; raw `oren_net_get*` calls
  and older root helpers are only the AVM substrate and never grant host
  networking authority.
- `OrenAVMRuntime enableLiveNetworkWithAllowedHosts:timeoutSeconds:error:` installs
  or updates the embedder NET callback, and `disableLiveNetworkWithError:` removes
  it. This lets the host app prompt users, grant/restrict/deny network policy, and
  change that policy later while the same OBC program remains portable. When OBC
  asks `std:net/avm/http.get(url).bytes()` for a URL not already in VirtualNET, the
  SDK can synchronously perform an allowlisted `URLSession` fetch on the AVM worker
  and return the body to bytecode. This is a convenience bridge for app integration,
  not raw socket authority.
- The iOS verifier runs a local HTTP server, prefetches that URL through the SDK,
  and then runs the same `.obc` program against `std:net/avm/http.get(url).bytes()`,
  proving the real host-fetch-to-OBC-read chain. It also runs live callback mode
  against the same local server.
- The first GFX bridge slices are implemented. `std:ui/avm` serializes validated
  `std:ui` v0 command buffers into compact `oren.gfx.frame.bin1` bytes,
  bytecode publishes them through `oren_gfx_present_frame`, `libavm` stores the
  latest frame in a GFX mailbox, and `OrenAVMKit` exposes frame get/clear
  helpers. The frame header now carries sequence, native drawable size, and target
  refresh hint metadata needed by high-refresh/high-resolution hosts.
- The low-level GUI transport is binary by design. JSON/QML-like documents may be
  used later as a high-level declarative UI/layout authoring format, but they must
  compile to the binary frame/event mailbox protocol before crossing the AVM-host
  boundary. This avoids making high-frequency drawing and input depend on JSON
  parsing or string allocation.
- The iOS verifier compiles device/simulator SDK smokes and runs a host SDK smoke
  that executes OBC, publishes a frame, retrieves it with
  `getGraphicsFrameDataWithError:`, validates the binary magic/opcode, injects a
  binary pointer event through the SDK, and clears the frame.
- The first default iOS renderer is implemented as `OrenAVMGraphicsView`, a
	  UIKit/CoreGraphics `UIView` that decodes the current `OGF0` binary frame subset
			  (`fill_rect`, `text`/`text_bytes`, `stroke_line`, `stroke_rect`, `circle`,
				  `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`, `push_camera_ortho`, `pop_camera`, `mesh2d`, `draw_mesh2d`, `destroy_mesh2d`, `mesh3d`, `mesh3d_rgba`, `mesh3d_indexed`, `material3d`, `model3d`, `draw_mesh3d`, `draw_mesh3d_at`, `draw_mesh3d_material`, `draw_mesh3d_at_material`, `draw_model3d`, `destroy_mesh3d`, `destroy_material3d`, `destroy_model3d`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`,
		  `image_rgba`, `draw_image`, `destroy_image`, and
		  `draw_image_rect`/`draw_image_rects`) and enqueues pointer events back through the `OGE0` input
  mailbox. This is the default 2D fallback.
- The first high-volume renderer is implemented as `OrenAVMMetalView`, an
		  `MTKView` adapter that owns the Metal draw loop, publishes host screen/media
			  state, forwards touch events to OBC, and renders current `OGF0` fill-rect,
								  stroke-line, stroke-rect, circle, ellipse, polyline, fill-triangle/fill-triangles, retained 2D mesh records, retained 3D triangle and indexed mesh records using orthographic XY default projection, byte-native per-triangle RGBA payloads, retained 3D material resources, retained 3D model resources, pure OBC-side `std:ui/scene3d` retained-scene builders with JSON and byte-native `.os3d` package-asset loading plus scene-level camera depth windows, named JSON references, model templates/instances, human-readable `position_xyz` or nested `transform` records, coordinate-array meshes, per-triangle `triangles_xyz_rgba` colors, richer material fields, and sampled transform keyframes lowered to numeric `.os3d`, iOS SDK package-store conformance for mounted `.os3d` scene assets, material override draws, deterministic painter-depth ordering, per-draw and retained model translation/uniform scale, and camera depth-window culling with dedicated release-manifest 3D conformance, retained RGBA image upload/draw/destroy/sub-rect and batched-atlas records, and byte-native/retained/batched text payloads through Metal
		  pipelines. It exposes measured CPU frame-budget helpers so host apps can detect
		  over-budget frames without reading raw Metal timing APIs. It also exposes
		  `prepareFrameResourcesWithError:` for drawable-independent frame preparation,
		  so host apps and CI can parse retained 3D/resource frames and inspect vertex,
		  text-run, and image-run counts without requiring a live drawable. CoreGraphics and Metal
	  renderers also expose retained image count/pixel limits and counters so host apps
		  can bound sprite/atlas memory. Retained text records now avoid resending
		  repeated UTF-8 labels every frame; richer glyph atlas batching remains pending.
- The binary input helper set now covers pointer events, resize events,
  media-query events, key events, UTF-8 text-input events, and compact
  gamepad/controller state plus coalesced motion, focus, and IME/composition
  events. These are still mailbox records, not UIKit, CoreMotion, GameController,
  or `UITextInput` objects.
- The SDK also exposes host-populated persistent screen state. `OrenAVMGraphicsView`
  updates screen `0` during layout, and OBC reads it through `std:ui/avm.screen(0)`
  without consuming an input event.
  Host code enqueues them; Oren/OBC pulls them with
  `std:ui/avm.pull_event_bytes()` or decodes them with
  `std:ui/avm.next_event()`.

Not implemented yet: compiler helper Swift/Objective-C package, OBC store helper,
Metal/3D rendering, and richer 2D drawing ops. GUI follow-up must be
game-grade, not widget-only: the next protocol work is display-link pacing,
retained resource handles, strict budgets, low-latency input ordering, and
Metal/`MTKView` gates as defined in
`project-doc/avm_ui_render_performance_design_20260531.md`.

## SDK Components

### OrenAVMKit

Core Swift/Objective-C wrapper around `LibAVM.xcframework`.

- Opens and closes `AvmEmbedHandle`.
- Loads bundled or downloaded `.obc` bytes.
- Provides default deterministic config and interactive config.
- Runs AVM on a worker queue, never the iOS main thread.
- Surfaces `AvmEmbedResult`, stdout, diagnostics, and package metadata.
- Owns lifecycle rules for cancellation, teardown, and app backgrounding.

### OrenAVMCompilerKit

Compiler-in-AVM helper package.

- `OrenAVMCompilerKit` accepts the app-bundled `oren.obc` and
  `stdlib_bundle.obc` resources as `NSData` or file URLs.
- It mounts source and stdlib resources into an AVM VirtualFS runtime, sets the
  compiler argv (`build`, bytecode backend, deterministic, stdlib OBC mode), and
  runs the compiler OBC without exposing host files to bytecode.
- It returns `OrenAVMCompileResult` with output OBC bytes, compiler stdout
  diagnostics, and the underlying `OrenAVMRunResult`.
- Keeps the host app from manually recreating the current compiler-in-AVM harness.

### OrenAVMFileProvider

Default FS adapter.

- Default mode: VirtualFS with explicit host file/directory copy-in and export
  helpers.
- App-sandbox mode: host code passes concrete `file://` URLs from the app
  container or bundle, and the SDK copies bytes into VirtualFS. OBC never sees
  arbitrary host paths.
- Live host-backed mode: host code passes an app-owned directory URL and VFS root
  to `mountHostDirectoryURL:atVFSRoot:readable:writable:error:`. The SDK enrolls
  read/write mount policy through `avm_embed_fs_mount*`; OBC uses normal virtual
  paths such as `host/out.txt`, and AVM maps only matching virtual paths to the
  host directory.
- Asset/package mounts should be treated as read-only by policy; writable
  scratch/output paths are exported explicitly after the run.

### OrenAVMNetworkProvider

Default NET adapter.

- Deterministic mode: VirtualNET fixtures/no host network.
- Interactive default mode: allowlisted host-backed VNET provider enabled by
  default, with SDK controls to restrict or disable it at runtime.
- Package manifest declares network domains before launch.
- The SDK maps responses back into the AVM NET surface with size/time budgets.
- Current implementation is prefetch-oriented: host code fetches allowlisted URLs
  before or between AVM runs, then OBC reads the materialized response through
  `std:net/avm/http.get(url).text()` or `.bytes()`. This preserves deterministic
  AVM execution and keeps iOS networking policy in the host SDK.
- Live callback mode is enabled by the interactive app defaults so useful OBC app
  programs can reach the network through VNET without extra boilerplate. It remains
  synchronous and must run on an AVM worker queue, not the UI thread. Apps can
  disable it by clearing `liveNetworkEnabled` before runtime creation or by calling
  `disableLiveNetworkWithError:` at runtime; apps can restrict/re-enable it with
  `liveNetworkAllowedHosts` or `enableLiveNetworkWithAllowedHosts:timeoutSeconds:`.
  OBC still has no raw host network authority.
- The first VNET session protocol is implemented for TCP, UDP, WebSocket client
  flows, and TCP listener/accept server flows. OBC imports scoped modules and uses
  receiver methods such as `std:net/avm/tcp.connect(host, port, timeout_ms)`,
  `std:net/avm/tcp.listen(host, port, timeout_ms)`, `session.write(...)`,
  `session.read(...)`, `session.select(...)`, `listener.accept(...)`,
  `std:net/avm/udp.connect(...).send(...)`, and
  `std:net/avm/ws.connect(...).recv_text(...)`. These map to AVM NET ops and
  embedder callbacks. The iOS SDK backs those virtual session IDs
  with host-owned POSIX sockets and `select()` readiness polling under the
  live-NET allowlist and runtime enable/disable controls. For `ws://`, the SDK
  owns the HTTP upgrade and WebSocket masking/framing so OBC still sees only a
  virtual session and payload bytes/text helpers. OBC sees only integer virtual
  session IDs, readiness masks, and byte buffers, never native sockets or
  descriptors.
- `std:net/avm/tcp`, `std:net/avm/udp`, and `std:net/avm/ws` provide app-facing convenience wrappers
  over those virtual sessions for common client flows. They are included in
  `stdlib_bundle.obc`, covered by the AVM stdlib OBC surface gate, and exercised
  in the iOS verifier through live host-backed TCP, UDP, WebSocket, and TCP
  listen/accept virtual sockets.
- `std:net/avm/dns` provides explicit OBC-safe virtual DNS. It maps to AVM NET
  op 6 and `avm_embed_set_net_resolve_callback`; the iOS SDK backs it with
  `getaddrinfo` under the same dynamic live-NET allowlist and timeout policy.
  OBC receives a bounded list of address strings only, never native resolver
  handles, sockets, or OS descriptors.
- iOS `OrenAVMKit` enforces live VNET lifecycle limits in the host provider.
  `liveNetworkMaxSessions` caps open virtual sessions and
  `liveNetworkSessionByteLimitBytes` caps cumulative read/write bytes per
  session. Hosts can adjust both at runtime with
  `configureLiveNetworkSessionLimitsWithMaxSessions:byteLimitBytes:error:`,
  so user settings or package permissions can tighten policy without rebuilding
  OBC.
- Embedder-level cancellation is exposed as `avm_embed_cancel` /
  `avm_embed_clear_cancel`, with iOS wrappers `requestCancelWithError:` and
  `clearCancelWithError:`. This lets a host app stop long-running OBC work from
  UI lifecycle, user action, or package policy without exposing thread handles
  or native cancellation primitives to OBC. If an OBC event loop explicitly watches
  `{"kind":"cancel"}`, native `std:avm/events` can consume the pending host cancel
  and return `{kind:"cancel", source:"host"}`; without that watch, the same host
  cancel remains a hard VM cancellation.
- Naming note: Oren native/runtime code already has raw `sys_select` for OS file
  descriptors. AVM uses virtual-session readiness; receiver-style
  `session.select(...)` / `session.select_read(...)` is the preferred app-facing
  shape and `poll*` remains the low-level single-session VNET alias. Neither
  exposes `fd_set`, file descriptors, or host sockets to OBC.
- The broader target is an AVM virtual-resource event bus: a `select`/`kqueue`-
  like reactor over virtual handles and mailboxes, not over OS descriptors. The
  bus multiplexes VNET sessions, GFX/input events, timers, cancellation, and
  host-enqueued FS/package lifecycle events. iOS can implement the provider side
  with `select()`, `kqueue`, dispatch sources, Network.framework callbacks, and
  display-link ticks, while OBC sees only stable virtual handles, event masks,
  sequence numbers, and bounded event payloads.
- `std:avm/events` now offers `select`/`select_once` over timer, UI/GFX input,
  VNET session-readiness, cooperative host-cancel watches, and FS/package watches
  through a native AVM `EVENT` capability domain. The iOS SDK backs VNET
  multi-watch selection with one host `select()` over app-owned sockets and can
  enqueue FS/package lifecycle events with
  `putVirtualEventWithKind:action:detail:flags:`. OBC still sees only stable
  virtual watch maps, event masks, and bounded event maps.
- The current HTTP body provider keeps a reusable ephemeral `NSURLSession` per
  `OrenAVMRuntime` so capability-enabled prefetch/live fetches use the fast SDK
  provider path by default instead of rebuilding a session for each OBC request.
- Performance mode should still be VNET, not raw host networking. The SDK may back
  VNET with `URLSession`, Network.framework, or platform sockets, but OBC must only
  see virtual responses or virtual session handles that AVM can budget, close,
  snapshot/test, and deny by capability.
- Full OBC network capability is still the target. The next NET layers should add
  WebSocket fixture/replay, broader lifecycle handling, deterministic
  fixture/replay support, and any compatibility aliases needed for non-AVM
  `std:net/tcp` / `std:net/udp` callers.
- Hot app-facing network paths should remain byte-first. Text convenience helpers
  may exist, but conversions should stay explicit at API boundaries. Current
  cleanup includes byte-native `std:net/avm/http.get(...).bytes()`, UI `text_bytes`, and
  direct `std:bytes.to_string` byte-slice conversion plus SHA-1/SHA-256 indexed
  byte processing instead of legacy whole-buffer list materialization.

### OrenAVMProcessProvider

Default PROC adapter.

- iOS default: VirtualPROC only.
- No arbitrary `system()` or subprocess execution on iOS.
- Package tests can register command fixtures and default exit codes.
- If future app actions are needed, expose them as reviewed app commands, not raw
  process execution.
- If OBC needs host-side concurrency or background work, add a separate
  host-backed virtual job/thread provider with capability checks, cancellation,
  lifecycle limits, and result mailboxes. Do not map `VPROC` to arbitrary host
  process/thread creation by default.

### OrenAVMTimeProvider

Default TIME adapter.

- Default mode: deterministic virtual time, matching `avm_embed_config_default`.
- Interactive mode: wall-clock time via `avm_embed_config_interactive_default`.
- `time.sleep_ms` in interactive mode blocks only the AVM worker queue.
- The SDK should make the time mode explicit in package/app config so UI packages
  do not accidentally appear to ignore delays.

### OrenAVMGraphicsKit

Current GUI adapter boundary.

- Receives validated frame command buffers from the AVM graphics mailbox.
- Renders the current 2D fallback through `OrenAVMGraphicsView` using
  UIKit/CoreGraphics.
- Future high-volume 2D/3D paths should use Metal/`MTKView`.
- Encodes pointer/keyboard/resize/media/input events back into AVM and publishes
  persistent screen state.
- Does not expose UIKit or Metal objects directly to Oren code.
- Current SDK implementation retrieves and clears binary frame payloads, enqueues
  binary pointer events, and renders the current `fill_rect`/`text`/
  `stroke_line`/`stroke_rect`/`circle`/`ellipse`/`polyline` subset. Resize/media/key/text,
  IME/composition, and Metal helpers are implemented; richer drawing ops remain
  the next slices.

### OrenAVMPackageStore

Public OBC store helper.

- Current implemented slices load local package directories with
  `package.json` + `program.obc`, validates `oren.obc.package.v0`, rejects
  unsupported AVM ABI floors, verifies the OBC SHA-256, derives an
  `OrenAVMRuntimeConfig` from capabilities/budgets/time mode, mounts read-only
  package assets into VirtualFS, and runs the OBC through `OrenAVMRuntime`.
- The SDK can also download a store `index.json`, find a package/version, verify
  the indexed manifest SHA-256, then install through the same local verifier path.
  When the index entry includes `bundle` and `bundle_sha256`, the SDK prefers the
  deterministic `.obc.zip` release bundle, verifies the bundle hash, extracts only
  safe rootless ZIP entries, verifies the extracted manifest hash, and then loads
  the package. If no bundle is listed, it falls back to fetching the manifest,
  OBC, and declared assets individually with SHA-256 verification.
  Host apps linking the static `OrenAVMKit` archive must also link `libz` because
  the SDK accepts deflated ZIP entries.
- A signed download overload accepts trusted publisher P-256 public keys and
  verifies `p256-sha256-der` signatures over the manifest hash before install.
- A signed-index overload fetches `index.json.sig`, verifies it with a trusted
  P-256 store key before trusting package entries, then applies publisher
  signature checks. The retained gate proves valid signatures plus bad-index-key,
  bad-package-signature, and bad-asset-hash rejection.
- Persisted app-directory lifecycle helpers are implemented for list, load, and
  remove installed packages. Remote package installs write to a temporary package
  directory first, verify through the local package path, then replace the final
  install path so partially downloaded packages are not treated as installed.
- Signed-index downloads accept an explicit install policy: replace, keep an
  already-installed same-version package, or fail if the target version is already
  installed. The retained gate proves same-version keep/fail behavior and installing
  a signed `0.2.0` package alongside `0.1.0`.
- `OrenAVMPackageUpdateStatus` lets host apps query the store update endpoint from
  either an installed package plus store base/index URL or an explicit update URL.
  The SDK parses publisher/name/current/latest version fields, exposes
  `updateAvailable`, and keeps update discovery separate from install so apps can
  present user or policy decisions before applying an install policy. Remote SDK
  installs write `.oren-install.json` with the source `index.json` URL and package
  identity, so later app launches can query update status for a loaded installed
  package without rebuilding a host-side package-to-store mapping table. The SDK
  can then install the latest trusted update for that package through the same
  signed-index and publisher-signature policy.
- Signature/cert enforcement is host policy. The SDK provides strict signed
  verification for safe defaults, but a host app may deliberately use the unsigned
  download/local load path after user confirmation, equivalent to a platform letting
  users run non-store software while owning the risk.
- `OrenAVMOBCTrustBundle.loadTrustBundleAtURL(...)` loads the external
  `obc_store_trust.json` generated under `../oren-ca/trust/`, validates the
  `oren.obc.trust.v0` schema and P-256 X9.63 public keys, and feeds signed-index
  package downloads through `trustBundle:` overloads. This keeps trust parsing in
  the SDK instead of duplicating it in every host app.
- The sibling Note repo now has a handoff/verifier update at commit `99b5a52`
  that checks the staged SDK for signed-index package downloads, install policies,
  trusted key inputs, trusted persisted package updates, and the external trust
  issue tool. The Note package manager exposes a visible trusted Update action
  for installed OBC packages.
- Store-side root trust rotation now has active key-id publication and
  rotation-capable trust-bundle serving; next slices should add richer visible
  update-status UX and operator lifecycle workflow.
- Applies package capabilities, budgets, assets, and time mode. GUI requirements
  remain host/app policy until the Metal/GFX release gate is stronger.

The same model should be replicated for macOS, Linux, and Windows after iOS
matures: keep OBC on portable virtual resources and ship platform SDK providers
for native FS/NET/TIME/PROC/UI implementations.

Private package signing keys and root CA material should stay outside this repo,
recommended at `../oren-ca/` for local bring-up. `OrenAVMKit` should consume
public publisher keys/trust bundles from app configuration; sibling apps such as
`../note` can share the same external CA location without committing secrets.

## Default Policy

| Surface | Default iOS implementation | Escalation |
| --- | --- | --- |
| FS | VirtualFS copy/export plus live host-backed app-directory mounts | Richer mount policy/manifest wiring |
| NET | VirtualNET/no host network | SDK `URLSession` prefetch/live fetch plus TCP/UDP/WebSocket/listen-accept virtual sessions with allowlist |
| PROC | VirtualPROC | Reviewed app commands or future virtual jobs only |
| TIME | Deterministic virtual time | Interactive wall-clock on worker queue |
| GUI | Binary GFX mailboxes plus UIKit/CoreGraphics `OrenAVMGraphicsView` fallback | Metal/3D renderer |
| INPUT | Explicit binary event queue/mailbox plus pointer/resize/media/key/text events | IME/composition helper encoders |
| STDOUT | Captured stdout | App-controlled log/result UI |

Default iOS providers are intended to do real app work, not only test fixtures.
The boundary is that OBC uses portable stdlib APIs and AVM capability domains;
the SDK owns the platform translation. TIME may use deterministic or wall-clock
worker-thread mode. FS can copy concrete app-owned file URLs into VirtualFS,
export selected VFS outputs back to app-owned file URLs, or use live host-backed
directory mounts for app-owned read/write paths. NET may prefetch through
allowlisted `URLSession` into VirtualNET or perform synchronous live fetches on the
AVM worker through the interactive default provider. Network permission is a
runtime host policy: an OBC app can request network capability, the host app can
raise UI, and the SDK can then enable/restrict/disable the live provider without
changing OBC. The current implementation exposes that request path as
`std:avm/permission.request*` over a separate AVM `PERMISSION` domain. AVM stores
the latest request in a compact `OPR0` binary mailbox; embedders can retrieve and
clear it through `avm_embed_permission_request_get/clear`, and `OrenAVMKit`
provides raw and decoded helpers plus `OrenAVMPermissionPrompt`, a Foundation-only
handoff object with stable title/message/risk metadata for host-native UI.
`OrenAVMPermissionGrantStore` persists decoded host decisions in an app-owned JSON
file, can record decisions from prompts, can explicitly apply package
`permission_defaults` after host/user policy accepts them, and can reapply NET
connect grants or revocations to a runtime by updating live VNET allowed hosts.
The sibling Note app now has a thin ObjC/Swift prompt DTO bridge, live
source/imported-OBC prompt presentation, explicit Allow/Deny persistence through
`OrenAVMPermissionGrantStore`, and grant-store application before future live
runs. App-specific wording and retry timing remain host policy.
High-performance networking should be implemented
as a host-backed VNET provider with virtual session handles, not as
bytecode-visible native sockets. TCP client streams, UDP connected datagrams, and
WebSocket client sessions and TCP listener/accept server flows now use that
reviewed session protocol. PROC on iOS should remain VirtualPROC,
reviewed app-command dispatch, or a future virtual job provider, not arbitrary
host subprocess/thread creation.
UI/GFX follows the same policy: the SDK may use CoreGraphics, Metal, `MTKView`,
retained GPU resources, and display-link pacing, but OBC sees only compact binary
frames/events and virtual resource handles. UIKit/Metal objects never enter OBC
memory.

## App Integration Shape

Desired Note-side API:

```swift
let runtime = OrenAVMRuntime(.interactiveAppDefaults)
runtime.mountAssetBundle("/assets/", bundle: .main)
runtime.network.allowHosts(["api.example.com"])
runtime.stdoutCapture = true

let program = try OrenOBCProgram(bytes: obcBytes, manifest: manifest)
let session = try runtime.start(program)
graphicsView.attach(session.graphics)
```

For pure calculation packages, the app can omit graphics and run one-shot:

```swift
let result = try runtime.run(program, argv: ["oren", "calc"])
```

## Release Gates

The SDK should not be called production-ready until these gates exist:

1. Swift/Objective-C smoke app loads a bundled OBC and runs it through
   `LibAVM.xcframework`.
2. CompilerKit compiles source to OBC inside AVM using bundled compiler/stdlib
   resources.
3. FileProvider proves VirtualFS and explicit app-sandbox mounts.
4. NetworkProvider proves VirtualNET and deny-by-default host network.
5. ProcessProvider proves iOS VirtualPROC and no host subprocess path.
6. TimeProvider proves deterministic virtual time and interactive wall-clock sleep.
7. GraphicsKit proves one rendered frame through UIKit/Metal and one input event
   through the AVM input mailbox.
8. PackageStore proves signed fixture download, verification, install, and run.

## Relationship To Existing Designs

- `project-doc/avm_ios_graphics_design_20260529.md` defines the graphics mailbox
  and rendering boundary.
- `project-doc/obc_store_distribution_design_20260529.md` defines the public OBC
  store package/index model.
- This note defines the host-side iOS SDK that makes those features easy for the
  Note app to consume.
