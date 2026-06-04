# AVM iOS Graphics Design

**Date:** 2026-05-29

## Verdict

For iOS, Oren programs running inside AVM should not call OpenGL, UIKit, or Metal
directly. AVM should produce deterministic graphics commands and the Note app should
own screen presentation through native iOS views. The production path should target
Metal/MetalKit on iOS, not OpenGL ES: Apple marks OpenGL ES deprecated on iOS 12 and
points high-performance GPU work to Metal. `MTKView` is the correct host view shape for
GPU-backed rendering because it is a Metal-aware `UIView` on iOS and provides render
pass/drawable management.

The right split is:

- **Oren/AVM:** compute scientific results, construct scene/frame command buffers,
  validate them, and publish them through a deterministic embedder channel.
- **Note iOS host:** run AVM ticks, receive frame commands, translate them to
  UIKit/CoreGraphics/Metal draw calls, present on the main UI thread, and inject input
  events back into AVM.

## Current Implementation Slice

The first retained implementation slices exist as of 2026-05-31:

- `lib/avm` has a GFX capability domain, a latest-frame mailbox, and a FIFO
  input-event mailbox.
- `lib/avm/avm_embed.h` exposes `avm_embed_set_gfx_frame_callback(...)` for
  event-driven host wakeups, `avm_embed_gfx_frame_info(...)` /
  `avm_embed_gfx_frame_get(...)` / `avm_embed_gfx_frame_clear(...)` for
  accepted-frame metadata and retrieval, plus `avm_embed_gfx_input_put(...)` for
  host-to-OBC input events.
- `lib/std/ui/avm.oren` serializes validated `std:ui` v0 command buffers into
  compact `oren.gfx.frame.bin1` bytes and publishes them with
  `oren_gfx_present_frame(...)`.
- `sdk/ios/OrenAVMKit` exposes `graphicsFrameHandler`,
  `getGraphicsFrameDataWithError:`, and `clearGraphicsFrameWithError:`, plus
  low-level input-byte enqueue and binary input-event helpers.
- `sdk/ios/OrenAVMKit` also exposes `OrenAVMGraphicsView`, a default
  UIKit/CoreGraphics `UIView` renderer for the current `OGF0` `fill_rect`/
  `push_clip_rect`/`pop_clip`/`push_translate`/`pop_transform`/
  `push_opacity`/`pop_opacity`/`push_camera_ortho`/`pop_camera`/`text`/`text_bytes`/`stroke_line`/
  `stroke_rect`/`round_rect`/`circle`/`ellipse`/`polyline`/`fill_triangle`/`fill_triangles`/`mesh2d`/`draw_mesh2d`/`destroy_mesh2d`/`mesh3d`/`mesh3d_rgba`/`mesh3d_indexed`/`material3d`/`model3d`/`draw_mesh3d`/`draw_mesh3d_at`/`draw_mesh3d_material`/`draw_mesh3d_at_material`/`draw_model3d`/`destroy_mesh3d`/`destroy_material3d`/`destroy_model3d` plus pure OBC-side `std:ui/scene3d` retained-scene builders/`image_rgba`/
  `draw_image`/`destroy_image`/`draw_image_rect`/`draw_image_rects` plus retained
  `text_resource`/`draw_text`/`draw_texts`/`destroy_text` subset. It decodes frame bytes on the host side
  and enqueues pointer events back into AVM.
- `OrenAVMKit` now has binary helper encoders for pointer, resize, media-query,
  key, and UTF-8 text input events, plus host-populated persistent screen state.
  The Oren side still receives raw `OGE0` bytes via
  `std:ui/avm.pull_event_bytes()`, or decoded maps via
  `std:ui/avm.next_event()`.
- `make verify-libavm-ios` proves the chain by running OBC that publishes a frame,
  retrieving/clearing that frame through the host SDK smoke, injecting a pointer
  event, consuming that event from OBC, and compiling the UIKit renderer adapter for
  device/simulator targets.

Still pending: game-grade render protocol hardening beyond the current Metal adapter,
IME/composition helpers, 2D geometry expansion beyond the retained v0 shape
subset, and 3D mesh commands. The high-refresh/high-resolution contract is now
tracked in `project-doc/avm_ui_render_performance_design_20260531.md`; follow it
before growing the command set.

## Source Facts

- Apple OpenGL ES archive: `project-doc/web/apple-ios-graphics-20260529/apple-opengles-introduction.html`.
  It states that OpenGL ES was deprecated in iOS 12 and recommends Metal for
  high-performance GPU code.
- Apple Metal sample markdown: `project-doc/web/apple-ios-graphics-20260529/apple-metal-draw-view.md`.
  It describes using MetalKit to create a view and render pass for drawing view contents.
- Apple `MTKView` markdown: `project-doc/web/apple-ios-graphics-20260529/apple-metalkit-mtkview.md`.
  It describes `MTKView` as a Metal-aware view that creates, configures, and displays
  Metal objects, backed by `CAMetalLayer`.
- Current AVM embed API: `lib/avm/avm_embed.h` exposes argv, VFS, VNET, VPROC,
  stdout capture, OBC load/run helpers, and GFX frame/input mailboxes. The iOS SDK
  now includes UIKit/CoreGraphics and Metal renderer adapters; atlas/mesh resource
  protocols remain future work.
- Current Oren UI stdlib: `lib/std/ui/` already uses the right architectural pattern:
  headless node/render command buffers plus a deterministic software rasterizer and a
  separate host shim. That pattern should be generalized for AVM app graphics.

## Non-Goals

- Do not embed a raw OpenGL ES context in AVM as the iOS production path. It is deprecated
  and creates the wrong ownership model: AVM bytecode would need host GPU context access,
  lifecycle coupling, and background/foreground handling.
- Do not let bytecode call UIKit or Metal directly. UIKit/Metal object lifetimes and thread
  rules belong to the app host.
- Do not make drawing depend on stdout text parsing. stdout remains diagnostics; graphics
  needs a typed frame/event channel.

## Proposed Architecture

### 0. Host Burden Boundary

The host app is the OS translator, but Oren should reduce host burden by making that
translation narrow and data-driven. The portable contract should be:

```text
Oren program -> std:gfx/std:ui/std:input APIs -> libavm validated mailboxes -> host adapters
```

Oren owns the meaning of portable operations such as `plot`, `line`, `mesh`, `text`,
`pointer_down`, and `resize`. `libavm` owns capability checks, budgets, schema/version
validation, deterministic storage, and typed frame/input queues. The host owns only
device-specific adapters: iOS maps frames to Metal/`MTKView`, macOS to Metal/AppKit,
Windows to Direct3D or CPU fallback, Android to Vulkan/OpenGL ES/Canvas, and so on.

This means each host app should not reimplement Oren semantics. It should implement a
small conformance-targeted adapter for stable command/event schemas, plus lifecycle and
permission handling required by the OS.

To make that practical, ship host conformance assets with the feature:

- schema files for frame and input payloads;
- golden AVM fixtures that publish known frames and consume known events;
- a reference CPU rasterizer for 2D geometry-only verification;
- sample Swift/Objective-C iOS, macOS, and Windows adapters;
- capability and budget tests for oversized frames, unsupported schema versions, and
  missing graphics permission.

### 0.1. Authoring Format vs Runtime Transport

UI layout and event semantics may be specified with a high-level declarative format
later, including JSON-like documents or a QML-like layer. That format is for authoring,
inspection, package manifests, and tooling.

The AVM-host transport should not use JSON as its production protocol. High-frequency
frames and input events must cross the bridge as compact binary streams:

- versioned magic headers (`OGF0` for frame stream v0, `OGE0` for event stream v0);
- little-endian fixed-width integers;
- small opcodes plus payload lengths;
- bounded byte payloads for future text, image, mesh, and shader/material records;
- no host platform object pointers and no UIKit/Metal/OpenGL handles.

This keeps the low-level bridge bit-level efficient and easy to validate. If a future
`std:ui/layout` accepts JSON/QML-like source, its compiler/lowerer should produce the
same binary `std:ui/avm` frame/event streams before calling `oren_gfx_present_frame`.

Oren should also ship optional host-side extension SDK components, not just schemas.
These SDKs are platform-specific packages maintained with the Oren/libavm contract:

- `OrenAVMGraphicsKit` for iOS/macOS: Swift/Objective-C wrapper around `libavm`,
  the retained UIKit/CoreGraphics fallback renderer, a future `MTKView` renderer,
  frame mailbox polling, input-event encoding, lifecycle hooks, and fixture-driven
  conformance tests.
- `oren-avm-gfx-win` for Windows: C/C++ wrapper around `libavm`, a Direct3D or CPU
  fallback renderer, input-event encoding, and the same frame-schema conformance tests.
- `oren-avm-gfx-headless`: portable C reference adapter that validates frames and can
  rasterize 2D geometry for CI without a GPU.

The host app can then call the SDK at a high level, for example "attach this AVM handle
to this view", rather than manually translating every Oren graphics command. The SDK
still remains outside AVM's deterministic core: it owns OS objects, GPU resources, view
lifecycle, and platform permissions, while AVM owns the portable command/event contract.

### 1. Graphics Domain and Frame Mailbox

Add an AVM graphics capability domain, separate from FS/NET/PROC. The VM may create a
bounded frame command buffer only when that domain is enabled.

Embedder API shape:

```c
int avm_embed_gfx_frame_get(AvmEmbedHandle* h, uint8_t** out_data, size_t* out_len,
                            AvmEmbedResult* r);
int avm_embed_gfx_frame_info(AvmEmbedHandle* h, size_t* out_len,
                             uint32_t* out_sequence, AvmEmbedResult* r);
int avm_embed_set_gfx_frame_callback(AvmEmbedHandle* h, AvmGfxFrameFn frame_fn,
                                     void* user_data, AvmEmbedResult* r);
int avm_embed_gfx_frame_clear(AvmEmbedHandle* h, AvmEmbedResult* r);
int avm_embed_gfx_input_put(AvmEmbedHandle* h, const uint8_t* event_data, size_t event_len,
                            AvmEmbedResult* r);
```

All three functions are implemented. Current frame payloads use
`oren.gfx.frame.bin1`: magic `OGF0`, version/flags/header length, logical width,
logical height, `scale_milli`, op-count, sequence, native drawable width, native
drawable height, target refresh milli-Hz, then opcode records. Current input payloads use `oren.gfx.event.bin0`:
magic `OGE0`, version/flags/reserved, then opcode records. The retained v0 opcodes
cover `fill_rect`, `text`/`text_bytes`, `stroke_line`, `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`,
	`mesh2d`, `draw_mesh2d`, `destroy_mesh2d`, `push_camera_ortho`, `pop_camera`, `mesh3d`, `mesh3d_rgba`, `mesh3d_indexed`, `material3d`, `model3d`, `draw_mesh3d`, `draw_mesh3d_at`, `draw_mesh3d_material`, `draw_mesh3d_at_material`, `draw_model3d`, `destroy_mesh3d`, `destroy_material3d`, `destroy_model3d`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`, `image_rgba`, `draw_image`,
`destroy_image`, `draw_image_rect`, `draw_image_rects`, pointer, resize, media-query, key, and text
input events; later geometry, mesh, image, material, and IME/composition opcodes
should extend the same binary stream.

AVM validates `OGF0` headers/op records before accepting OBC-published frames and
validates `OGE0` headers/payload lengths before accepting host input. This keeps
host adapters from having to defensively parse arbitrary byte strings from the VM.
Frame callbacks report only sequence and byte length; hosts then fetch/copy on
their UI/render thread. That makes the default transport event-driven without
exporting VM-owned frame memory across language or process boundaries. The
no-copy info API remains useful for diagnostics and constrained hosts that cannot
install callbacks, but polling it is not the default path for iOS/macOS/desktop
SDKs.

The retained implementation uses the explicit graphics mailbox, not VFS or stdout.
Frame publication is charged against AVM I/O budget so graphics output cannot grow
unbounded.

Input direction is deliberately asymmetric:

- Host adapters enqueue binary events with `avm_embed_gfx_input_put(...)` or
  `OrenAVMKit` convenience helpers.
- Host adapters populate persistent screen state with `avm_embed_gfx_screen_set(...)`
  or SDK helpers before OBC reads `std:ui/avm.screen(0)`.
- Oren/OBC pulls one event at a time with `std:ui/avm.pull_event_bytes()` for raw
  protocol bytes or `std:ui/avm.next_event()` for decoded pointer/resize/media/key/text
  maps.
- The VM does not callback into Oren from the host UI thread; this keeps device
  lifecycles, threading, and permissions owned by the host app.

### 2. Oren Stdlib Surface

Add `std:gfx` as data-first APIs. It should not expose platform objects.

Initial modules:

- `std:gfx/frame`: frame envelope, viewport, clear, command-buffer validation.
- `std:gfx/canvas2d`: rectangles, lines, polylines, paths, circles, text labels,
  image/bitmap references, charts/plots.
- `std:gfx/mesh3d`: camera, transform, material, vertex/index buffers, draw calls.
- `std:gfx/input`: pointer, keyboard, gesture, resize, frame-tick events.

The scientific app use case should start with 2D plotting and simple 3D meshes:

```oren
import gfx "std:gfx/canvas2d"

fn main() {
    var f = gfx.frame(800, 600)
    gfx.clear(f, "#0b1020")
    gfx.polyline(f, [[0, 0], [1, 2], [2, 1]], {"color":"#55ccff", "width":2})
    gfx.present(f)
}
```

`gfx.present(frame)` writes the frame to the AVM graphics mailbox. In bytecode tests it
can be read and validated without any iOS UI.

### 3. iOS Host Rendering

The Note app should create one graphics host view per AVM canvas:

- Use UIKit/SwiftUI only for app composition, layout, and input ownership.
- Use `MTKView` for GPU rendering when frames contain 3D meshes, many 2D primitives,
  or animated charts.
- Use the retained `OrenAVMGraphicsView` UIKit/CoreGraphics path as the simple v0
  fallback where the host rasterizes a small 2D command list.
- Keep all UIKit view mutation on the main actor/main dispatch queue.
- Run AVM compute/tick work off the main thread, then hand frame payloads back to the main
  actor for presentation.

Host loop:

1. User edits/runs Oren code in Note.
2. Note compiles source to OBC through the compiler-in-AVM or host compile path.
3. Note opens `AvmEmbedHandle` with graphics domain enabled and deterministic budgets.
4. Note installs a frame callback, then runs one VM tick or run-to-pause interval.
5. The callback wakes the host render path with the accepted frame sequence/length;
   Note calls `avm_embed_gfx_frame_get` on the render-safe path.
6. Note validates schema/version/limits, renders simple v0 frames through
   `OrenAVMGraphicsView`, or translates richer ops to Metal buffers/pipelines and
   presents through `MTKView`.
7. Note captures touch/keyboard/resize events and calls `avm_embed_gfx_input_put` before
   the next VM tick.

### 4. 2D Command Set v0

Keep v0 small and deterministic:

- `clear {color}`
- `fill_rect {x,y,w,h,color}`
- `push_clip_rect {x,y,w,h}` and `pop_clip` for a balanced virtual scissor stack
- `push_translate {dx,dy}` and `pop_transform` for a balanced virtual translation stack
- `push_opacity {alpha_milli}` and `pop_opacity` for a balanced virtual alpha stack
- `stroke_line {x1,y1,x2,y2,color,width}`
- `stroke_rect {x,y,w,h,color,width}`
- `round_rect {x,y,w,h,r,fill,color,width}`
- `ellipse {x,y,w,h,fill,color,width}`
- `fill_triangle {x1,y1,x2,y2,x3,y3,color}`
- `polyline {points,color,width}` where `points` is packed little-endian `u32 x,y` pairs
- `path {verbs,coords,fill,stroke,width}`
- `circle {cx,cy,r,fill,color}`
- `text {x,y,text,color,size,align}` with host-font caveat
- `image {id,x,y,w,h}` where image bytes are supplied through VFS or a future asset API

Text is the only non-deterministic visual area because fonts differ by platform and OS
version. For scientific correctness tests, use geometry/text metadata checks rather than
pixel-perfect host text rendering.

### 5. 3D Command Set v0

Keep 3D scene commands explicit and bounded:

- `camera {projection, view}`
- `mesh {id, vertex_format, vertices, indices}`
- `material {id, base_color, roughness, metallic}`
- `draw_mesh {mesh, material, transform}`
- `line3d {points,color,width}` for scientific visualization

The host should compile/cache Metal pipeline state. AVM should not own shader compilation
in v0. If programmable shaders are needed later, use a restricted material/shader DSL with
offline validation, not arbitrary Metal Shading Language strings from bytecode.

### 6. Budgets and Safety

Add explicit limits:

- max frame bytes;
- max op count;
- max vertex/index bytes;
- max texture bytes;
- max frames per run/tick;
- max input queue bytes;
- allowed graphics schema versions.

Frame publication should fail with an AVM graphics budget error, not crash or silently drop.
Curated AVM/iOS gates now cover malformed `OGF0` rejection, op-count cap rejection,
frame I/O-budget rejection, malformed `OGE0` rejection, and the host input queue
depth cap. The iOS verifier also covers non-1000 resize scale propagation,
persistent screen-state reads, runtime media-query propagation, latest-frame
replacement/clear semantics, and FIFO pointer down/move/up ordering before mixed
key/text events.
The same iOS verification chain now includes a manifest-driven stdlib OBC
surface gate. It checks every module imported by `lib/std/stdlib_avm.oren`,
rejects host-only exclusion leaks, generates an OBC smoke from the manifest, and
runs it through AVM so graphics apps do not reach Note with missing bundle
exports such as `STD_linalg_dot_f64`.

### 7. Verification Plan

Required gates before Note integration should be called production-ready:

1. AVM bytecode fixture creates a 2D binary frame and host test reads it from the graphics mailbox. Done for frame get/clear.
2. Host-side C embed smoke validates `avm_embed_gfx_frame_get` and `avm_embed_gfx_input_put`.
3. iOS simulator/device link smoke proves the new graphics API exports from
   `LibAVM.xcframework`.
4. iOS SDK smoke compiles a UIKit/CoreGraphics `OrenAVMGraphicsView` adapter for
   device/simulator targets. Done for compile/link coverage.
5. Note-side Swift smoke mounts `OrenAVMGraphicsView` or `MTKView`, runs a bundled
   OBC, renders one 2D frame, and injects one touch event.
6. Deterministic headless raster test compares software raster output for geometry-only ops.
   Done: `test_ui_2d_conformance_v0.oren` now hashes one combined retained
   image/text/atlas/geometry scene in the AVM release manifest.
7. 3D conformance hashes camera depth windows, model translation/scale/Z,
   per-triangle RGBA depth ordering, indexed shared-vertex meshes, and material
   override draws.
   Done: `test_ui_3d_conformance_v0.oren` is included in the AVM release
   manifest.

## Implementation Order

1. Done: define `oren.gfx.frame.bin1` for existing `std:ui` v0 commands and add AVM-side mailbox storage plus C embed getter/clearer.
2. Done: add `std:ui/avm` and AVM/iOS verifier coverage that publishes a binary `fill_rect` frame.
3. Done: add iOS C/SDK smoke to `make verify-libavm-ios` for exported graphics symbols and frame retrieval.
4. Done: add binary input-event mailbox and pointer-event SDK helper.
5. Done: add default UIKit/CoreGraphics `OrenAVMGraphicsView` for the current `fill_rect`/`text` subset and compile it in the iOS verifier.
6. Done: extend the binary frame protocol, deterministic rasterizer, and iOS fallback renderer to `stroke_line`, `circle`, and `fill_triangle`.
7. Done: add SDK binary helper encoders for resize, media-query, key, and UTF-8 text input events and verifier coverage that OBC consumes them.
8. Done: add frame sequence, native drawable-size metadata, and target refresh hint to the `OGF0` header for high-refresh/high-resolution hosts.
9. Done: add protocol/budget gates for malformed frames/events, op-count caps,
   frame I/O budget, and host input queue depth.
10. Done: add high-resolution resize scale, latest-frame replacement/clear, and
    FIFO pointer down/move/up ordering gates.
11. Done: add event-driven GFX frame callbacks, no-copy frame info fallback, and
    SDK renderer no-op reload semantics for empty mailboxes, so host views can
    keep the last valid `OGF0` frame while awaiting the next AVM publication.
12. Done: add first SDK Metal/`MTKView` adapter (`OrenAVMMetalView`) that owns the
    Metal draw loop, publishes screen state, forwards touch input, and renders the
    current `fill_rect`/`push_clip_rect`/`pop_clip`/`push_translate`/`pop_transform`/`push_opacity`/`pop_opacity`/`stroke_line`/`stroke_rect`/`round_rect`/`circle`/`ellipse`/`polyline`/`fill_triangle` geometry records plus
    retained image upload/draw/destroy/sub-rect/batched-atlas records and retained text
    upload/draw/destroy records.
13. Next: add Note Swift/ObjC bridge smoke that mounts `OrenAVMGraphicsView` or
    `OrenAVMMetalView`, runs a bundled OBC, renders one frame, and injects one touch.
14. Add IME/composition helpers.
15. Done: add Oren-side image upload budgets plus iOS SDK retained image count/pixel
    limits and counters.
16. Done: add a balanced OBC-visible `push_clip_rect` / `pop_clip` scissor stack
    across validation, `OGF0`, AVM protocol checks, deterministic raster,
    CoreGraphics, Metal scissor rectangles, and iOS verifier coverage.
17. Done: add a balanced OBC-visible `push_translate` / `pop_transform`
    translation stack across validation, `OGF0`, AVM protocol checks,
    deterministic raster, CoreGraphics CTM state, Metal vertex/scissor offsets,
    and iOS verifier coverage.
17. Done: add a balanced OBC-visible `push_opacity` / `pop_opacity`
    alpha stack across validation, `OGF0`, AVM protocol checks, deterministic
    raster alpha multiplication, CoreGraphics global alpha state, Metal geometry
    alpha, texture/text fragment opacity, and iOS verifier coverage.
18. Done: add `round_rect {x,y,w,h,r,fill,width,color}` across validation,
    `OGF0`, AVM protocol checks, deterministic raster, CoreGraphics, Metal,
    iOS verifier coverage, and the 2D conformance scene.
19. Add `std:gfx/canvas2d` / `std:gfx/mesh3d` records for sprite/text/mesh rendering
    on the Metal path.

This keeps Oren useful for scientific calculation and visualization while preserving the
right app boundary: AVM computes and describes frames; iOS renders them.
