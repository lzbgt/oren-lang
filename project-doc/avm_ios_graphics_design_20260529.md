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
  stdout capture, OBC load, and run helpers. It has no frame mailbox, input-event queue,
  texture/buffer handoff, or graphics capability domain yet.
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

### 1. Graphics Domain and Frame Mailbox

Add an AVM graphics capability domain, separate from FS/NET/PROC. The VM may create a
bounded frame command buffer only when that domain is enabled.

Embedder API shape:

```c
int avm_embed_gfx_frame_get(AvmEmbedHandle* h, uint8_t** out_data, size_t* out_len,
                            AvmEmbedResult* r);
int avm_embed_gfx_frame_clear(AvmEmbedHandle* h, AvmEmbedResult* r);
int avm_embed_gfx_input_put(AvmEmbedHandle* h, const uint8_t* event_data, size_t event_len,
                            AvmEmbedResult* r);
```

The payload should be a versioned binary or canonical JSON envelope in v0:

```json
{
  "schema": "oren.gfx.frame.v0",
  "w": 1179,
  "h": 2556,
  "scale": 3,
  "ops": []
}
```

Use VFS as a temporary proof path if needed (`/out/frame.gfx.json`), but the production
bridge should use an explicit graphics mailbox so the Note app does not poll arbitrary
files and so graphics budgets can be accounted separately from filesystem IO.

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
- Use CoreGraphics/UIKit image presentation only for a simple v0 fallback where AVM emits
  a software RGBA buffer or the host rasterizes a small 2D command list.
- Keep all UIKit view mutation on the main actor/main dispatch queue.
- Run AVM compute/tick work off the main thread, then hand frame payloads back to the main
  actor for presentation.

Host loop:

1. User edits/runs Oren code in Note.
2. Note compiles source to OBC through the compiler-in-AVM or host compile path.
3. Note opens `AvmEmbedHandle` with graphics domain enabled and deterministic budgets.
4. Note runs one VM tick or run-to-pause interval.
5. Note calls `avm_embed_gfx_frame_get`.
6. Note validates schema/version/limits, translates ops to Metal buffers/pipelines, and
   presents through `MTKView`.
7. Note captures touch/keyboard/resize events and calls `avm_embed_gfx_input_put` before
   the next VM tick.

### 4. 2D Command Set v0

Keep v0 small and deterministic:

- `clear {color}`
- `fill_rect {x,y,w,h,color}`
- `stroke_line {x1,y1,x2,y2,color,width}`
- `polyline {points,color,width}`
- `path {verbs,coords,fill,stroke,width}`
- `circle {cx,cy,r,fill,stroke,width}`
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

### 7. Verification Plan

Required gates before Note integration should be called production-ready:

1. AVM bytecode fixture creates a 2D frame and host test reads it from the graphics mailbox.
2. Host-side C embed smoke validates `avm_embed_gfx_frame_get` and input injection.
3. iOS simulator/device link smoke proves the new graphics API exports from
   `LibAVM.xcframework`.
4. Note-side Swift smoke mounts `MTKView`, runs a bundled OBC, renders one 2D frame, and
   injects one touch event.
5. Deterministic headless raster test compares software raster output for geometry-only ops.
6. 3D smoke renders a single indexed triangle/mesh through the host Metal renderer.

## Implementation Order

1. Define `oren.gfx.frame.v0` and add AVM-side mailbox storage plus C embed getter/clearer.
2. Add `std:gfx/frame` and `std:gfx/canvas2d` with validator-only bytecode fixtures.
3. Add iOS C smoke to `make verify-libavm-ios` for exported graphics symbols.
4. Add Note Swift/ObjC bridge smoke using `MTKView` and one frame.
5. Add `std:gfx/mesh3d` after the 2D path is proven.

This keeps Oren useful for scientific calculation and visualization while preserving the
right app boundary: AVM computes and describes frames; iOS renders them.
