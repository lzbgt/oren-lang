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
- `sdk/ios/OrenAVMKit/OrenAVMKit.h` and `.m` provide an Objective-C API usable
  from Swift/Objective-C apps.
- `OrenAVMRuntimeConfig deterministicDefaults` keeps deterministic virtual TIME
  and virtual FS/NET/PROC.
- `OrenAVMRuntimeConfig interactiveAppDefaults` keeps virtual FS/NET/PROC but
  switches TIME to wall-clock mode so `std:time.sleep_ms` delays the AVM worker.
- `OrenAVMRuntime` exposes argv, VirtualFS put/get, VirtualNET fixture put,
  VirtualPROC fixture/default puts, OBC byte execution, and stdout capture.
- `make verify-libavm-ios` compiles iOS device/simulator SDK smokes and runs a
  host SDK smoke proving interactive `time.sleep_ms(25)` has real elapsed-time
  effect.
- `OrenAVMRuntime fetchURLIntoVirtualNet:allowedHosts:timeoutSeconds:error:`
  provides the first app-usable NetworkProvider slice. The SDK owns the host
  `URLSession` request, enforces an allowlisted host and timeout, then injects
  the response bytes into VirtualNET under the original URL. OBC code still uses
  the portable `oren_net_get(url)` surface and never receives raw host networking
  authority.
- The iOS verifier runs a local HTTP server, prefetches that URL through the SDK,
  and then runs the same `.obc` program against `oren_net_get(url)`, proving the
  real host-fetch-to-OBC-read chain.
- The first GFX bridge slices are implemented. `std:ui/avm` serializes validated
  `std:ui` v0 command buffers into compact `oren.gfx.frame.bin0` bytes,
  bytecode publishes them through `oren_gfx_present_frame`, `libavm` stores the
  latest frame in a GFX mailbox, and `OrenAVMKit` exposes frame get/clear
  helpers.
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
  (`fill_rect`, `text`, `stroke_line`, and `circle`) and enqueues pointer events
  back through the `OGE0` input mailbox. This is the default 2D fallback; it is
  not the future high-volume Metal path.
- The binary input helper set now covers pointer events, resize events, key events,
  and UTF-8 text-input events. These are still mailbox records, not UIKit objects.
  Host code enqueues them; Oren/OBC pulls them with
  `std:ui/avm.pull_event_bytes()`.

Not implemented yet: app-sandbox file mounts, live/asynchronous network sessions,
compiler helper Swift/Objective-C package, OBC store helper, Metal/3D rendering,
richer 2D drawing ops, and IME/composition input helpers. GUI follow-up must be
game-grade, not widget-only: the next protocol work is high-refresh/high-resolution
pacing, retained resource handles, strict budgets, low-latency input ordering, and
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

- Bundles `oren.obc` and `stdlib_bundle.obc` as app resources.
- Mounts source and stdlib resources into VirtualFS.
- Runs the compiler OBC to produce output OBC.
- Returns compile diagnostics and `out.obc` bytes to the app.
- Keeps the host app from manually recreating the current compiler-in-AVM harness.

### OrenAVMFileProvider

Default FS adapter.

- Default mode: VirtualFS only.
- Optional app-sandbox mode: explicit read-only/read-write mounts into app
  Documents, temporary directories, or bundled resources.
- No arbitrary absolute host paths.
- Every mount is declared before launch and visible to package policy.

### OrenAVMNetworkProvider

Default NET adapter.

- Default mode: VirtualNET fixtures/no host network.
- Optional reviewed mode: allowlisted `URLSession` requests.
- Package manifest declares network domains before launch.
- The SDK maps responses back into the AVM NET surface with size/time budgets.
- Current implementation is prefetch-oriented: host code fetches allowlisted URLs
  before or between AVM runs, then OBC reads the materialized body through
  `oren_net_get(url)`. This preserves deterministic AVM execution and keeps iOS
  networking policy in the host SDK.

### OrenAVMProcessProvider

Default PROC adapter.

- iOS default: VirtualPROC only.
- No arbitrary `system()` or subprocess execution on iOS.
- Package tests can register command fixtures and default exit codes.
- If future app actions are needed, expose them as reviewed app commands, not raw
  process execution.

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
- Encodes pointer/keyboard/resize/input events back into AVM.
- Does not expose UIKit or Metal objects directly to Oren code.
- Current SDK implementation retrieves and clears binary frame payloads, enqueues
  binary pointer events, and renders the current `fill_rect`/`text`/
  `stroke_line`/`circle` subset. Resize/key/text event helpers are implemented;
  IME/composition helpers, richer drawing ops, and Metal are the next slices.

### OrenAVMPackageStore

Public OBC store helper.

- Downloads signed store indexes and package manifests.
- Verifies hashes/signatures before execution.
- Applies package capabilities, budgets, assets, time mode, and GUI requirements.
- Rejects unknown schema versions or unsupported AVM ABI requirements.

## Default Policy

| Surface | Default iOS implementation | Escalation |
| --- | --- | --- |
| FS | VirtualFS | Explicit app-sandbox mounts |
| NET | VirtualNET/no host network | SDK `URLSession` prefetch into VirtualNET with allowlist |
| PROC | VirtualPROC | Reviewed app commands only |
| TIME | Deterministic virtual time | Interactive wall-clock on worker queue |
| GUI | Binary GFX mailboxes plus UIKit/CoreGraphics `OrenAVMGraphicsView` fallback | Metal/3D renderer |
| INPUT | Explicit binary event queue/mailbox plus pointer/resize/key/text events | IME/composition helper encoders |
| STDOUT | Captured stdout | App-controlled log/result UI |

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
