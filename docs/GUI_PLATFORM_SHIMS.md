# GUI Platform Shims (OrenUI) — v0 Bring-up Plan

**Status:** macOS Cocoa shim exists; Windows shim bring-up exists; Linux/X11 shim bring-up exists  
**Last updated:** 2026-01-12

This document turns `docs/GUI.md` into an actionable engineering plan for **Tier‑1 platform shims**.
The guiding principle is:

- Keep `std:ui/*` **portable and deterministic** (runs in AVM + native).
- Keep all OS/UI effects (windowing, input, drawing, clipboard) behind a **small shim ABI**.
- Prefer a **software RGBA framebuffer** for v0 (fastest bring-up, smallest surface area).
- Allow optional “shells” (e.g. Dear ImGui) without changing the portable core.

Tier‑1 OS/arch intent (today): `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

---

## 0) Current repo state (fact)

- In-tree shim header: `native/orenui/orenui.h`
- macOS shim implementation exists: `native/orenui/cocoa/orenui_cocoa.m`
- Windows shim bring-up exists: `native/orenui/win32/orenui_win32.c` (v0 skeleton; window + present + pump)
- Linux/X11 shim bring-up exists: `native/orenui/x11/orenui_x11.c` (v0 skeleton; window + present + pump)
- Smoke gate (macOS-only; requires GUI session): `scripts/verify_ui_smoke_macos.sh` (wired via `make verify-ui-smoke-macos`)
- Smoke gate (Windows; requires GUI session + VS Developer Prompt): `scripts/verify_ui_smoke_windows.sh` (wired via `make verify-ui-smoke-windows`)
- Smoke gate (Linux; requires X11 GUI session + dev libs): `scripts/verify_ui_smoke_linux.sh` (wired via `make verify-ui-smoke-linux`)
- Missing today (still true):
  - stable input/event schema (v0 currently only supports close/pump reliably)
  - DPI/scale reporting beyond “best-effort scale=1”
  - Wayland support (future; X11 is the v0 target)

## 1) What the v0 shim must do (and what it must not)

### Must do (v0)

1) Create a window with a pixel surface (RGBA).
2) Pump OS events (mouse, keyboard, resize, close).
3) Present a provided RGBA framebuffer to the window at interactive rates.
4) Provide DPI scale (or at least a stable “scale=1” until implemented).

### Must not do (v0)

- Implement layout/widgets/state. That belongs in `std:ui/*`.
- Expose a platform-specific API directly to user Oren code (avoid Win32/X11/Cocoa leakage).
- Require a GPU API (Metal/D3D/Vulkan) just to show pixels.

---

## 2) Recommended v0 boundary: “RGBA blit shell”

The v0 shim boundary should treat the UI core as producing an RGBA framebuffer:

- UI core:
  - `std:ui/render`: tree → deterministic command buffer
  - `std:ui/raster`: commands → RGBA bytes
- Shim:
  - `present_rgba(win_id, w, h, rgba_bytes, stride)` → display
  - `poll_event(win_id, timeout_ms)` → return next event

This matches the existing headless rasterizer, so platform shims can start by “just blitting pixels”
without committing to a GPU backend.

---

## 3) ABI surface options (choose one for implementation)

Oren has multiple execution modes. The shim boundary must be usable from:

- a native Oren shell (via `ffi`)
- later: an AVM capability domain implementation (`CALL_NATIVE2(UI, op, nargs)`)

There are two viable ABI strategies.

### Option A (preferred): C ABI + typed structs (fastest + safest)

Expose a tiny `extern "C"` ABI with plain POD structs.

Pros:
- Easy to bind from Oren native backend.
- Easy to implement in C/C++/ObjC across platforms.
- No JSON/YAML parsing in the shim.

Cons:
- Requires an “event decoding” layer in Oren runtime/stdlib.

**Suggested C ABI (v0):**

- Window lifecycle:
  - `int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h);`
  - `void orenui_close_window(int32_t win_id);`
  - `void orenui_set_title(int32_t win_id, const char* title_utf8);` (optional)

- Frame:
  - `int32_t orenui_begin_frame(int32_t win_id, struct OrenUIFrameInfo* out);`
  - `int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, const uint8_t* rgba, int32_t stride);`

- Events:
  - `int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, struct OrenUIEvent* out);`
    - returns: `0 = none`, `1 = event`, `<0 = error`

Where:

- `OrenUIFrameInfo` contains: `{w,h,scale_x1000}` or `{w,h,scale_num,scale_den}`.
- `OrenUIEvent` is a tagged union:
  - `type = MOUSE_MOVE | MOUSE_DOWN | MOUSE_UP | KEY_DOWN | KEY_UP | TEXT | RESIZE | CLOSE`
  - `mods` bitmask (shift/ctrl/alt/super)
  - payload fields depend on type.

### Option B: C ABI returning “event maps” (slower, but closer to Oren values)

Expose a shim ABI that returns a serialized map form (e.g. JSON) for events.

Pros:
- Matches `docs/GUI.md` event examples directly.

Cons:
- Requires JSON parsing in the event loop (extra allocations + latency).
- Harder to keep stable across backends and versions.

Unless we absolutely need this for AVM-first integration, prefer Option A.

---

## 4) Per‑platform v0 implementation notes (RGBA blit)

These are **implementation constraints**, not user-visible APIs.

### Windows (`x64-windows`)

Use Win32 windowing and GDI blit.

- Window creation: `CreateWindowExW` + message loop (`PeekMessageW` / `GetMessageW`)
- Blit strategy (v0):
  - `StretchDIBits` (simple) or
  - `CreateDIBSection` + `BitBlt` (often faster)
- Events:
  - mouse: `WM_MOUSEMOVE`, `WM_LBUTTONDOWN`/`UP`, `WM_RBUTTONDOWN`/`UP`, etc.
  - keyboard: `WM_KEYDOWN`/`UP`, `WM_CHAR`
  - resize: `WM_SIZE`
  - close: `WM_CLOSE`
- DPI:
  - start with `scale=1` unless `WM_DPICHANGED`/`GetDpiForWindow` is used.

### Linux (`arm64-linux`, `x64-linux`)

Start with X11 for reach; Wayland can be added later.

- Window creation: Xlib (`XOpenDisplay`, `XCreateSimpleWindow`, `XMapWindow`)
- Event pump: `XPending`/`XNextEvent`
- Blit strategy (v0):
  - `XPutImage` with an `XImage` that wraps the RGBA buffer (conversion may be required)
  - later: XShm for performance
- DPI:
  - v0: `scale=1`
  - later: derive from Xft/DPI settings or per-monitor info

### macOS (`arm64-macos`)

Use Cocoa for windowing, CoreGraphics for software blit.

- Window creation: `NSApplication` + `NSWindow` + `NSView`
- Event pump: `-[NSApp nextEventMatchingMask:untilDate:inMode:dequeue:]`
- Blit strategy (v0):
  - create `CGImage`/`CGBitmapContext` from RGBA bytes and draw in `drawRect`
  - later: Metal texture upload path (v1)
- DPI:
  - `backingScaleFactor` on the window/screen

Bring-up hazard (observed):

- If the host program is not a traditional Cocoa `main()` that calls `-[NSApplication run]`,
  “per-call” `@autoreleasepool { ... }` blocks inside a shim can crash under repeated use.
  Prefer a single long-lived pool owned by the shell (or reintroduce pools only after the
  run loop ownership model is settled).

---

## 5) Where Dear ImGui fits (and where it does not)

Dear ImGui is valuable to Oren in two non-conflicting ways:

1) **Tooling/inspector overlay**: once Oren has a window + render backend, ImGui can provide
   an immediate-mode debug UI (metrics, inspectors, profilers) without polluting `std:ui`.
2) **Optional shell shortcut**: an ImGui-based shell can provide window + input + GPU present
   on platforms where ImGui has mature backends, while we keep `std:ui` as the portable user API.

However:

- ImGui is not a retained-mode widget system; it is not the long-term *app UI* API for Oren.
- Using ImGui’s portable backends often implies adopting SDL/GLFW (or writing our own platform backend),
  which conflicts with the “no large deps” goal unless we vendor carefully.

So the recommended default is:

- Implement OrenUI v0 shims as minimal RGBA-blit shims per platform.
- Keep an ImGui shell as an optional path or devtools overlay.

---

## 6) Concrete v0 deliverables (what to build next)

1) **Finalize the shim ABI** (`native/orenui/orenui.h`):
   - lock a minimal set of v0 calls (open/close/poll/begin_frame/present_rgba)
   - lock the `OrenUIEvent` tagged union layout
2) **macOS (`arm64-macos`)**:
   - keep iterating `native/orenui/cocoa/orenui_cocoa.m` until the v0 ABI is fully implemented
   - keep `scripts/verify_ui_smoke_macos.sh` green (headful; opt-in)
3) **Windows (`x64-windows`)**:
   - add `native/orenui/win32/*` implementing the same ABI using Win32 + GDI (RGBA blit)
   - done: `scripts/verify_ui_smoke_windows.sh` builds the shim and runs a bounded “open window → present N frames → close” test
4) **Linux (`x64-linux`, `arm64-linux`)**:
   - add `native/orenui/x11/*` implementing the same ABI using Xlib + XPutImage (v0)
   - add a headful `scripts/verify_ui_smoke_linux.sh` (note: WSL2 is not a reliable GUI target by default)
5) **Oren-side integration**:
   - add `std:ui/host` bindings (FFI) that call the shim, convert `OrenUIEvent` into the map form used by `std:ui/*`
   - add `examples/ui_hello.oren` that opens a window and draws a `std:ui` frame
