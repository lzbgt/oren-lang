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
- `std:ui/avm.next_event()` decodes `OGE0`
  pointer/resize/key/text/gamepad/motion/focus/composition records into Oren maps
  so OBC programs do not have to parse bytes manually.
- `OGE0` also carries `frame_tick` records with sequence, host tick time,
  delta time, target refresh, and flags. Host renderers such as `OrenAVMMetalView`
  emit these records from the display draw loop so OBC game loops can pace
  simulation from virtual display events, not raw OS handles. `frame_tick`
  is coalesced by AVM so a slow or paused OBC consumer keeps only the newest
  tick and cannot starve pointer/key/text events by filling the FIFO with stale
  timing records.
- High-rate `motion` records carry source id, sequence, host timestamp, and
  signed milli-unit accelerometer/gyroscope samples. AVM coalesces pending motion
  records by source so sensor updates cannot flood the FIFO.
- `focus` records carry gained/lost phase plus focus id and flags so OBC menus
  and input routers can respond to host focus changes without raw UIKit objects.
- `composition` records carry update/commit/cancel phase, marked text, and
  selection range so IME state remains host-driven while OBC can render/edit
  composition UI through virtual input events.
- iOS `OrenAVMGraphicsView` renders the current CoreGraphics fallback subset:
  `fill_rect`, `push_clip_rect`/`pop_clip`, `push_translate`/`pop_transform`,
  `push_opacity`/`pop_opacity`, `text`/`text_bytes`, `stroke_line`,
  `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`,
  `text_resource`, `draw_text`, `destroy_text`, `image_rgba`, `draw_image`,
  `destroy_image`, `draw_image_rect`, and `draw_image_rects`.
- iOS `OrenAVMMetalView` is the first Metal/`MTKView` path: it owns the Metal draw
  loop, publishes host-populated screen state, forwards touch input into `OGE0`,
  and renders current `OGF0` `fill_rect`/`push_clip_rect`/`pop_clip`/`push_translate`/`pop_transform`/`push_opacity`/`pop_opacity`/`stroke_line`/`stroke_rect`/`round_rect`/`circle`/`ellipse`/`polyline`/`fill_triangle` geometry, retained RGBA image draws/sub-rect and batched atlas draws, plus byte-native and retained text
  through Metal pipelines. Its `targetHzMilli` setting drives
  `MTKView.preferredFramesPerSecond` so hosts can request 60/90/120 Hz pacing
  without exposing UIKit/Metal objects to OBC. Current text rendering uses a bounded
  SDK-side LRU texture cache for repeated labels; host apps can clear the cache on
  memory pressure. The view exposes frame metrics for rendered frame count, CPU
  encode time, target frame budget, budget-usage permille, over-budget status,
  geometry vertex count, and text-run count so host apps and verifiers can observe
  and gate pacing cost. `text_bytes` lets OBC publish UTF-8 bytes directly on the
  frame hot path. `image_rgba`/`draw_image`/`destroy_image`/`draw_image_rect`/`draw_image_rects` is the first
  OBC-visible retained sprite resource lifetime, atlas sub-rect, and packed batch path. Oren-side
  validation can gate per-frame image upload bytes/count, and SDK renderers expose
  retained image count/pixel limits and counters. Retained text records avoid
  resending repeated UTF-8 labels every frame; richer glyph atlas batching and
  mesh resources remain the next performance steps.
- Host helpers can enqueue pointer, resize, key, UTF-8 text, compact
  gamepad/controller state, coalesced motion, focus, and IME/composition input
  events.
- iOS UIKit/CoreGraphics and Metal views forward all touches in each UIKit touch
  set, assign stable compact pointer IDs for active touches, release IDs on
  end/cancel, and expose batch pointer-event helpers, so multi-finger input maps
  to multiple virtual pointer events rather than a single selected touch.
- Host helpers can enqueue frame-tick events for display-paced game loops.
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
- The iOS verification chain now also runs a manifest-driven stdlib OBC surface
  gate. It checks every module imported by `lib/std/stdlib_avm.oren`, rejects
  host-only exclusion leaks, generates an OBC smoke from the manifest, and runs
  it in AVM, so GUI app dependencies fail in the repo gate instead of later in
  app integration.

This baseline proves bidirectional transport for the current 2D subset. It is not
yet game-complete: richer input such as multitouch gestures still needs compact
event records and iOS SDK helpers before game OBC packages should rely on it.

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
- first retained image records: `image_rgba {id,w,h,data}` uploads RGBA bytes and
  `draw_image {id,x,y,w,h}` draws the retained resource;
- retained image lifetime record: `destroy_image {id}` releases the host-side
  cached resource for the virtual image handle;
- atlas sub-rect record: `draw_image_rect {id,sx,sy,sw,sh,x,y,w,h}` draws part of a
  retained image into a destination rect for sprite-atlas use;
- batched atlas record: `draw_image_rects {id,rects}` draws many atlas sub-rects
  from one retained image using packed little-endian `sx,sy,sw,sh,x,y,w,h`
  records, reducing per-sprite opcode/header overhead;
- explicit budgets: `std:ui/commands` accepts `max_image_bytes` and
  `max_image_count`, and iOS CoreGraphics/Metal renderers expose retained image
  count/pixel limits plus current counters;
- retained text records: `text_resource {id,data,color}` uploads UTF-8 bytes once,
  `draw_text {id,x,y}` draws the virtual text handle, and `destroy_text {id}`
  releases the host-side retained label;
- balanced clipping records: `push_clip_rect {x,y,w,h}` and `pop_clip`
  express a virtual scissor stack for nested game UI panels while the host maps
  it to CoreGraphics state or Metal scissor rectangles;
- balanced translation records: `push_translate {dx,dy}` and `pop_transform`
  express nested coordinate spaces for game UI nodes while the host maps them to
  CoreGraphics CTM state or Metal vertex/scissor offsets;
- balanced opacity records: `push_opacity {alpha_milli}` and `pop_opacity`
  express nested UI transparency while the host maps them to CoreGraphics alpha
  state or Metal geometry/texture fragment opacity;
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
5. 60/90/120 Hz host pacing and frame-metrics smoke in the iOS SDK or Note app;
6. large text/geometry frames that stay within budget and render without JSON;
7. retained resource upload/update/destroy smoke;
8. low-latency input ordering smoke across multiple pointer events;
9. Metal/`MTKView` renderer smoke for retained sprite/mesh resources once the
   resource protocol exists;
10. docs-site page and conformance fixtures for the binary protocol.
11. whole-frame 2D raster conformance hash that covers retained image/text,
    atlas sub-rects, batched sprites, geometry, and draw ordering together.

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
6. Done: add first SDK Metal/`MTKView` adapter for the current low-level
   `OGF0` fill-rect/stroke-line/circle/ellipse/polyline/text records, touch forwarding, host screen
   state, and target-refresh pacing through `MTKView.preferredFramesPerSecond`.
7. Done: add compact coalesced `OGE0` `frame_tick` events and OBC decoding so
   display-paced loops can consume host timing through the virtual event stream.
8. Done: expose SDK-side Metal frame metrics for frame count, CPU encode time,
   target budget, geometry vertices, and text-run count.
9. Done: forward multi-touch sets with stable compact pointer IDs and expose SDK
   batch pointer-event helpers for UIKit/CoreGraphics and Metal views.
10. Done: add `fill_triangle` as a compact 2D geometry record across validation,
    binary frames, AVM protocol checks, deterministic raster, CoreGraphics fallback,
    Metal, and iOS verifier coverage.
11. Done: add SDK-side measured frame-budget helpers for Metal views:
    configurable warning threshold, budget usage permille, over-budget status, and
    verifier coverage for 60/90/120 Hz budget math.
12. Add Note/iOS display-link smoke for measured high-refresh pacing behavior.
13. Done: add first retained RGBA image resource records (`image_rgba`,
    `draw_image`, `destroy_image`, `draw_image_rect`) across validation, binary frames, AVM protocol
    checks, deterministic raster, CoreGraphics fallback, Metal texture cache, and
    iOS verifier coverage.
14. Done: add explicit retained image budgets: Oren-side image upload byte/count
    validation plus iOS SDK retained image count/pixel limits and counters.
15. Done: add first retained text resource records (`text_resource`,
    `draw_text`, `destroy_text`) across validation, binary frames, AVM protocol
    checks, deterministic raster, CoreGraphics fallback, Metal text cache, and
    iOS verifier coverage.
16. Done: add batched sprite-atlas draw records (`draw_image_rects`) across
    validation, binary frames, AVM protocol checks, deterministic raster,
    CoreGraphics fallback, Metal texture draws, and iOS verifier coverage.
17. Done: add a release-manifest 2D conformance fixture that hashes one
    deterministic raster scene covering retained text, retained images, atlas
    sub-rects, batched sprites, geometry, and draw ordering.
18. Done: add `stroke_rect` across validation, binary frames, AVM protocol
    checks, deterministic raster, CoreGraphics fallback, Metal, iOS verifier,
    and the 2D conformance scene.
19. Done: add `ellipse {x,y,w,h,fill,width,color}` across validation, binary
    frames, AVM protocol checks, deterministic raster, CoreGraphics fallback,
    Metal, iOS verifier, and the 2D conformance scene.
20. Done: add byte-native `polyline {points,width,color}` across validation,
    binary frames, AVM protocol checks, deterministic raster, CoreGraphics
    fallback, Metal, iOS verifier, and the 2D conformance scene.
21. Done: add balanced `push_clip_rect` / `pop_clip` clipping across validation,
    binary frames, AVM protocol checks, deterministic raster, CoreGraphics
    fallback, Metal scissor rectangles, iOS verifier, and the 2D conformance
    scene.
22. Done: add balanced `push_translate` / `pop_transform` translation across
    validation, binary frames, AVM protocol checks, deterministic raster,
    CoreGraphics CTM state, Metal vertex/scissor offsets, iOS verifier, and the
    2D conformance scene.
23. Done: add balanced `push_opacity` / `pop_opacity` alpha state across
    validation, binary frames, AVM protocol checks, deterministic raster,
    CoreGraphics alpha state, Metal geometry/image/text opacity, iOS verifier,
    and the 2D conformance scene.
24. Add richer text atlas batching and mesh rendering on the Metal path.
25. Done: add `round_rect {x,y,w,h,r,fill,width,color}` across validation,
    binary frames, AVM protocol validation, deterministic raster, CoreGraphics
    fallback, Metal, iOS verifier, and the 2D conformance scene.
26. Add richer 2D and 3D command sets.
26. Add game/app package smoke in the Note host or iOS SDK harness.
