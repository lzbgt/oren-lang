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

Future GUI adapter.

- Receives validated frame command buffers from the AVM graphics mailbox.
- Renders through UIKit/CoreGraphics for simple 2D or Metal/`MTKView` for GPU
  paths.
- Encodes pointer/keyboard/resize/input events back into AVM.
- Does not expose UIKit or Metal objects directly to Oren code.

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
| NET | VirtualNET/no host network | URLSession allowlist |
| PROC | VirtualPROC | Reviewed app commands only |
| TIME | Deterministic virtual time | Interactive wall-clock on worker queue |
| GUI | No raw host access | GFX mailbox to UIKit/Metal adapter |
| INPUT | No implicit input | Explicit event queue/mailbox |
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
7. GraphicsKit proves one rendered frame and one input event when the GFX mailbox
   exists.
8. PackageStore proves signed fixture download, verification, install, and run.

## Relationship To Existing Designs

- `project-doc/avm_ios_graphics_design_20260529.md` defines the graphics mailbox
  and rendering boundary.
- `project-doc/obc_store_distribution_design_20260529.md` defines the public OBC
  store package/index model.
- This note defines the host-side iOS SDK that makes those features easy for the
  Note app to consume.
