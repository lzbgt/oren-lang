# AVM UI Render Performance Contract

**Date:** 2026-05-31

## Decision

The Oren UI stack must be designed for high-refresh, high-resolution hosts and
game-like interactive workloads before the command set grows. JSON/QML-like
documents may be useful as an authoring and layout format, but the AVM-host
runtime boundary must remain compact binary, frame-paced, and resource-oriented.

The production contract is:

```text
Oren UI/layout source
  -> validated std:ui/std:gfx scene or command buffer
  -> compact binary frame/event streams
  -> libavm capability and budget checks
  -> host renderer adapter driven by the platform display loop
```

Oren owns portable UI/game semantics. The host owns display links, drawable
sizes, threads, GPU resources, OS lifecycle, and presentation.

Release target: an iOS app should be able to run OBC packages that behave like
small game/app experiences, not only static forms. That implies bounded low-latency
input, predictable frame pacing, retained GPU resources, high-resolution drawable
mapping, and conformance tests that catch regressions before app integration.

Bidirectional UI is a hard requirement, not an optional add-on. The OBC program
must be able to publish render intent every frame and consume host-originated
input/events in the same virtual UI contract. The host SDK may use UIKit,
CoreGraphics, Metal, keyboard/touch/game-controller APIs, or platform event loops,
but OBC must only see portable virtual frame/event records with sequence numbers,
timestamps, capabilities, and budgets.

## Source Facts

- Apple `CADisplayLink.preferredFrameRateRange` reference was captured at
  `project-doc/web/apple-ios-display-20260531/apple-cadisplaylink-preferredframeraterange.html`.
  It defines the API as a range of callback frequencies and notes that the system
  also accounts for hardware, policy, and workload.
- Apple ProMotion guidance was captured at
  `project-doc/web/apple-ios-display-20260531/apple-promotion-displays.html`.
  It says custom content should provide frame-rate hints and should be prepared to
  operate at any refresh rate the system provides.
- Apple `MTKView.drawableSize` reference was captured at
  `project-doc/web/apple-ios-display-20260531/apple-mtkview-drawablesize.html`.
  It describes drawable textures in native pixels and automatic resize behavior.
- Apple `MTKView.preferredFramesPerSecond` reference was captured at
  `project-doc/web/apple-ios-display-20260531/apple-mtkview-preferredframespersecond.html`.
  It describes view redraw rate selection based on screen capability.

## Current Baseline

Implemented as of 2026-05-31:

- `OGF0` binary frame mailbox with latest-frame semantics and v1 frame metadata
  for sequence, logical size, native drawable size, scale, and target refresh hint.
- `OGE0` binary input-event mailbox.
- `std:ui/avm.present_frame(...)` publishes current `std:ui` command buffers.
- `std:ui/avm.pull_event_bytes()` pulls host-injected input; `poll_event_bytes()`
  remains only as a compatibility alias during rolling development.
- `std:ui/avm.next_event()` decodes `OGE0` pointer/resize/key/text records into
  Oren maps so OBC programs do not have to parse bytes manually.
- iOS `OrenAVMGraphicsView` renders the current CoreGraphics fallback subset:
  `fill_rect`, `text`, `stroke_line`, and `circle`.
- Host helpers can enqueue pointer, resize, key, and UTF-8 text input events.
- Host helpers can publish persistent screen/media state and can enqueue
  media-query change events so OBC can adapt to logical size, native drawable
  size, device scale, target refresh rate, and host flags at runtime without
  calling platform APIs directly.
- AVM validates `OGF0` frame headers/op records and `OGE0` input event
  headers/payload lengths at the mailbox boundary before accepting them.
- Curated gates cover malformed-frame rejection, op-count cap rejection, frame
  I/O-budget rejection, the host input queue depth cap, non-1000 resize scale
  propagation, latest-frame replacement/clear semantics, and FIFO pointer
  down/move/up ordering before mixed key/text events.
- The iOS verification chain now also compiles and runs a stdlib OBC surface smoke
  that imports buffer/bytes/CBOR/YAML/regex/base64/PEM/X509/SHA-1/SHA-256/json/
  linalg/math/strings/time/UI AVM modules, so GUI app dependencies fail in the
  repo gate instead of later in app integration.

This baseline proves bidirectional transport for the current 2D subset. It is not
yet game-complete: richer input such as multitouch gestures, focus, IME composition,
gamepad/controller events, and high-rate motion data still need compact event
records and iOS SDK helpers before game OBC packages should rely on them.

Runtime media query must be host-populated state, not a consumed event only.
OBC should not query `UIScreen`, `MTKView`, or any host object directly. The host
publishes persistent screen state with logical width/height, `scale_milli`,
native drawable width/height, and `target_hz_milli`; OBC reads it through
`std:ui/avm.screen(0)` / `screen0()`. The host may also enqueue a compact
media-query event when those attributes change, so event loops can react without
polling the persistent state every tick.

This is a correct bootstrap, not the final game-grade renderer contract.

## High-Refresh Contract

The VM must not assume one Oren tick per display refresh. A 120 Hz screen gives an
8.33 ms frame interval, and a 60 Hz screen gives 16.67 ms. AVM execution, layout,
network, and scientific calculation cannot be allowed to block the host display
loop.

Required behavior:

- Host renderer owns `CADisplayLink`/`MTKView` timing and presents on the UI/render
  thread.
- AVM runs on a worker thread or queue and publishes the latest complete frame.
- The host may re-present the previous frame when AVM has not produced a new one.
- The host may drop stale frames rather than queue unbounded frame history.
- Frame metadata carries a monotonically increasing sequence number so hosts can
  drop stale frames.
- Frame metadata carries a target refresh hint in milli-Hz, but the host remains
  authoritative because system refresh rates can change.

For game OBC packages, simulation and rendering must be separable. Oren should be
able to run a fixed-step simulation loop, emit a render snapshot, and let the host
present at the display's available cadence. The renderer must tolerate 30/60/90/120
Hz presentation without changing game logic.

## High-Resolution Contract

The Oren UI API should use logical coordinates. The frame header must carry enough
host data for correct mapping to physical pixels:

- logical width and height;
- scale in milli-units as `scale_milli`;
- native drawable width and height for GPU-backed render targets;
- resize events from host to Oren whenever the logical size or scale changes.

Do not hard-code iPhone sizes. The same OBC package must tolerate compact iPhone,
large iPhone, iPad, external display, macOS, and headless test surfaces.

## Binary Protocol Rules

The low-level frame loop must avoid JSON parsing and string-heavy allocation:

- fixed magic headers: `OGF0` and `OGE0`;
- little-endian fixed-width integers;
- opcode plus payload length for forward parsing;
- bounded frame byte length, op count, text bytes, and event queue depth;
- resource handles for future fonts, images, paths, meshes, buffers, and materials;
- no UIKit, Metal, OpenGL, CoreGraphics, or host pointers in bytecode-visible data.

The high-level declarative layer can compile to this binary form. It must not cross
the AVM-host boundary directly as JSON in the render loop.

## Resource and Batching Model

The current immediate-mode frame is acceptable for the v0 CoreGraphics fallback.
High-volume 2D and 3D need retained resources:

- font and text-atlas resources for repeated labels;
- image/texture handles;
- path/shape handles;
- vertex/index buffers for plots and meshes;
- transform, clip, layer, and canvas records;
- dirty-region or damage metadata for partial redraw when applicable.

This keeps large static content from being serialized every frame.

## Game-Grade Capability Set

The GUI path is not release-complete until it can support interactive game/app
packages. Required capability families:

- frame timing: display tick events, fixed-step simulation helpers, frame sequence,
  producer timestamp, and host target-time hints;
- input: pointer/touch, multitouch, key, text, resize, focus, gamepad-like controls
  when the host supports them, and bounded event latency;
- 2D rendering: sprites/images, texture atlas handles, clipping, transforms,
  paths, text atlas/glyph handles, layers, alpha/blend modes, and damage metadata;
- 3D rendering: mesh buffers, vertex/index handles, camera/projection, materials,
  textures, draw calls, depth/stencil mode, and basic lighting data;
- resources: upload/update/destroy records for buffers, images, fonts, shaders or
  material variants, all behind explicit budgets;
- audio later: a separate audio mailbox is likely needed for games, but it should
  not be mixed into the graphics frame protocol.

The CoreGraphics fallback can stay as a conformance/debug renderer. It is not the
performance target for games. The game-grade iOS target should be Metal/`MTKView`
with retained resources and small per-frame command buffers.

## Event Direction

UI input should be a pull API from Oren's perspective:

- host adapters enqueue events into AVM with `avm_embed_gfx_input_put(...)` or SDK
  helpers;
- Oren pulls events at safe points with `std:ui/avm.pull_event_bytes()` or
  `std:ui/avm.next_event()`;
- the host UI thread never calls back into Oren bytecode synchronously.

This keeps UIKit/Metal thread rules outside AVM and avoids reentrant VM execution.

## Required Next Gates

Before expanding to Metal/3D or a much larger command set, add gates for:

1. high-resolution resize frame smoke with non-1000 `scale_milli`;
2. frame byte budget rejection and op-count cap rejection;
3. latest-frame replacement and clear semantics;
4. event queue depth and ordering;
5. 60/90/120 Hz host pacing smoke in the iOS SDK or Note app;
6. large text/geometry frames that stay within budget and render without JSON;
7. retained resource upload/update/destroy smoke;
8. low-latency input ordering smoke across multiple pointer events;
9. Metal/`MTKView` renderer smoke for at least one sprite/mesh-like retained
   resource once the resource protocol exists;
10. docs-site page and conformance fixtures for the binary protocol.

## Reweighted Implementation Order

1. Freeze the performance contract and keep docs/tests aligned.
2. Done: add `OGF0` v1 frame sequence, native drawable-size metadata, and target
   refresh hint while rolling compatibility is cheap.
3. Done: add mailbox-boundary protocol validation for malformed `OGF0` frames and
   `OGE0` host input events.
4. Done: add budget/depth fixtures for oversized frames, op-count caps, and
   input queue depth.
5. Done: add latest-frame replacement/clear, high-resolution resize scale, and
   FIFO pointer down/move/up ordering gates in the iOS embed verifier.
6. Add Note/iOS display-link smoke for high-refresh pacing behavior.
7. Add retained resources, batching, and resource lifetime records.
8. Add Metal/`MTKView` renderer as the game-grade iOS path.
9. Add richer 2D and 3D command sets.
10. Add game/app package smoke in the Note host or iOS SDK harness.
