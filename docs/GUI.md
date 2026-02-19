# GUI / UI Design for Oren (Rolling)

**Status:** Design + headless core implemented; bring-up shims exist for macOS + Windows + Linux/X11 (rolling)  
**Last updated:** 2026-01-12

This document proposes a **production-oriented** GUI story for Oren that is consistent with:

- Oren’s “one language, three execution modes”: `native`, `c`, `bytecode (.obc/AVM)`.
- AVM’s capability-domain model (`CALL_NATIVE2(domain, op, nargs)`).
- Rolling constraints: fast iteration, deterministic tooling, and cross-platform targets.

Tier‑1 OS/arch intent (today): `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

Bring-up gates (headful, opt-in):

- macOS: `make verify-ui-smoke-macos`
- Windows: `make verify-ui-smoke-windows`
- Linux/X11: `make verify-ui-smoke-linux` (requires X11 dev + GUI session)

## 0) Goals and constraints

### Goals

1) **Cross-platform desktop GUI** with a stable userland API.
2) **Portable “UI core”**: the bulk of UI logic (tree/layout/diff/state) should run on *all* Tier‑1 platforms with minimal conditional code.
3) **Capability-scoped host effects**: windowing, GPU, clipboard, etc. are effects and must be routed through explicit capability domains (for sandboxing, auditability, and later record/replay).
4) **Tool-friendly packaging**: easy to ship an “app bundle” where UI code is portable and the platform shell is thin.
5) **Future-proof**: do not lock the project into a single rendering backend (Metal vs D3D vs Vulkan).

### Non-goals (v0)

- Full CSS compliance.
- Full HTML layout engine.
- A “toy” GUI that ignores input, text, DPI, etc.
- “GUI purely via syscalls”. Real GUI requires platform APIs; we should encapsulate them cleanly.

## 0.1) About `ui-idea.md`

Some earlier discussions referenced a `ui-idea.md` scratch file.

To avoid stale pointers, `ui-idea.md` now exists as a **short redirect** to the current design docs.

Treat this document (`docs/GUI.md`) as the current source of truth for GUI design, shim bring-up, and the
optional ImGui shell.

## 0.2) Where Dear ImGui fits (and where it doesn't)

Oren’s long-term UI API should remain **retained-mode** and portable (`std:ui/*`), with deterministic headless tests.

Dear ImGui (immediate-mode) is still highly relevant to Oren, but in a *non-conflicting* role:

- as an **optional devtools overlay / inspector** (best fit),
- or as an **optional bring-up shell** on platforms where its upstream backends are mature,
  without turning ImGui into the *application UI API*.

Design note (fact-based):

- ImGui’s upstream docs emphasize “bloat-free”, portable, backend-oriented integration and explicitly
  position the library toward programmer tools rather than full end-user UI.
- This matches Oren’s rolling need for reliable “window + input + present” loops on Tier‑1, while still
  keeping Oren’s UI semantics in `std:ui`.

See the “Optional bring-up shell: Dear ImGui” section below for the concrete integration shape and
the in-repo upstream snapshots.

## 1) Recommended architecture: UI bytecode + native shell + UI capability domain

Oren’s best leverage is not “build a monolithic widget toolkit in native Oren first”.
The best path is a split similar to Flutter/ReactNative, but with one language end-to-end:

1) **UI logic runs as `.obc` bytecode** in AVM (portable, deterministic, policy-scannable).
2) A tiny **native shell** (Oren native or host app) provides platform integration:
   - window creation
   - event pump
   - rendering backend (software blit v0; GPU v1)
   - text measurement/shaping (later)
3) The VM calls host effects via a dedicated **UI capability domain** (new domain ID).

This is consistent with the existing AVM design direction:

- capability domains define *what effect is requested*
- the backend defines *where the effect is executed*

See `docs/AVM_AND_OBC.md` (bootstrap spec + Next-Gen AVM Plan section) for the domain/op model and governance direction.

### Why this is the best “first production” choice

- **Portability:** the UI core is the hardest part to stabilize; running it in AVM makes it cross-arch/OS by construction.
- **Security:** untrusted UI bundles can be restricted to UI-only (and optionally TIME) domains.
- **Testing:** UI core becomes testable in a headless deterministic runner (no OS windows required).
- **Backends:** the same UI core can later be reused for:
  - all-native mode (Oren native backend)
  - “C backend host” mode (portable host bring-up)

## 2) Programming model: declarative tree + diff + command buffer

The recommended UI programming model is **pure-functional view** + **explicit state**, producing a tree:

- `view(model) -> Node`
- A runtime loop:
  - receives events
  - updates model
  - re-renders (`view(model)`)
  - diffs old/new trees
  - emits a command buffer for the host renderer

This model is:

- deterministic (given event stream)
- easy to serialize/replay
- easy to test headlessly
- compatible with AVM sandboxing

### Node representation (v0)

Oren currently has dynamic values (maps/lists/strings/ints) and is rolling toward reflective types.
For v0, represent nodes as explicit maps (like `std:json` / `std:yaml` tagged shapes):

- Node map:
  - `{"t":"Text","k":"title","p":{...},"c":[...]}`
    - `t`: node type tag (string)
    - `k`: stable key (string) for diffing
    - `p`: props (map)
    - `c`: children (list of nodes)

This is intentionally “boring data”. It’s portable across backends and easy to serialize.

Later (v1+), if/when reflective types stabilize, nodes can become typed structs with stable metadata
without changing the model.

### Layout and styling (v0)

Start with a small layout model that composes:

- `Row`, `Column`, `Stack`
- fixed sizes + padding
- simple alignment
- scroll container (later)

Styles are maps:

- `{"font_size":16, "color":"#RRGGBB", "bg":"#RRGGBB", "padding":8, ...}`

This avoids committing to CSS parsing or cascade rules prematurely.

Rolling v0 implementation note:

- `std:ui/layout` supports:
  - padding: `pad` / `pad_x` / `pad_y` / `pad_{l,r,t,b}`
  - gap: `gap` (Row/Column)
  - alignment:
    - Row: `align_y` ("start"/"center"/"end")
    - Column: `align_x` ("start"/"center"/"end")

### Markup formats (XML / CSS?) — do we need them?

We do **not** need XML (or full CSS) to ship a production-quality GUI.

Fact-based constraints:

- Oren already has a strong *code as configuration* story: UI trees can be created as maps/lists in Oren
  code, and this works in all three execution modes (`native`, `c`, `bytecode`).
- Introducing an XML/CSS layer too early tends to create:
  - a second semantics surface (parser, escaping rules, tooling formats),
  - a cascade/layout complexity cliff (CSS compliance is not a v0 goal),
  - and more portability obligations (all parsers must behave identically across Tier‑1 and AVM).

Recommended direction (rolling):

1) **Primary authoring format:** Oren code (`Node` maps + helper constructors).
2) **Tooling/serialization formats:** add small “data interchange” options for editor tooling:
   - JSON (already aligned with the map/list/value model),
   - optional YAML/TOML only if we have a clear need.
3) **XML/HTML/CSS:** treat as optional ecosystem experiments, not as core UI dependencies.
   - If we later want a declarative markup, prefer a minimal schema that lowers to the node-map form,
     keeping `std:ui` as the semantic source of truth.

## 3) Host bridge: UI capability domain API (v0)

Define a single UI domain (example ID: `9`) with a narrow set of ops.
The UI core emits commands; the host executes them.

### 3.0 Render command buffer schema (headless contract)

Even before a platform shim exists, Oren needs a stable “render intent” contract so we can:

- regression test UI behavior deterministically (headless),
- build multiple render backends later (software blit v0, GPU v1),
- keep the UI core portable across platforms/backends.

Current v0 schema is implemented (and regression-tested in AVM) by:

- `std:ui/render` (`lib/std/ui/render.oren`) — tree → command list
- `std:ui/raster` (`lib/std/ui/raster.oren`) — command list → RGBA bytes (headless reference)

**Coordinate system (v0):**

- integer pixel coordinates
- origin `(0,0)` at **top-left**
- +x right, +y down
- rectangles are inclusive of `(x,y)` and cover `w*h` pixels

**Command list:**

- a list of maps; each map has an `"op"` string and required fields per op
- commands are emitted in deterministic order (preorder traversal)

Supported ops today:

- `fill_rect`:
  - `{"op":"fill_rect","x":int,"y":int,"w":int,"h":int,"color":string}`
- `text` (marker-only in v0 raster):
  - `{"op":"text","x":int,"y":int,"text":string,"color":string}`

**Color encoding (v0):**

- `"#RRGGBB"` or `"#RRGGBBAA"` (hex; case-insensitive)

**Validation (recommended):**

- `std:ui/commands.validate(cmds, w, h, opts)` validates a command buffer against the schema.
- `std:ui/raster.rasterize(...)` validates by default; disable with `opts["validate"]=0`.
- `opts["strict_bounds"]=1` rejects out-of-frame ops (useful in tests); default is permissive clipping.

Rolling note:

- `text` rasterization is intentionally not “real font rendering” in v0. The headless rasterizer draws
  one pixel per character to provide a deterministic test marker. A real platform text renderer belongs
  in the platform shim (or a later font subsystem).

### Minimal required ops

**Window**

- `open_window(title, w, h) -> win_id`
- `close_window(win_id) -> nil`
- `begin_frame(win_id) -> {w,h,scale}`
- `present(win_id) -> nil`

**Events**

- `poll_event(win_id, timeout_ms) -> event | nil`
  - Repo v0 shim ABI returns events via a flat out buffer (`int64[5]`), not a map:
    - `orenui_poll_event(win_id, timeout_ms, out5_i64_ptr) -> 0/1/<0`
    - `out[0] = type`, `out[1..4] = payload` (see `native/orenui/orenui.h`)
  - A higher-level Oren wrapper exists: `std:ui/host`
    - `std:ui/host.poll_event(win_id, timeout_ms, ev_buf)` converts the flat `int64[5]` payload into an
      event map (`{"t": "...", ...}`), which is the recommended form for portability and testability.

**Rendering**

For v0, pick one of:

1) **Software command buffer:** host exposes `fill_rect`, `draw_text`, `draw_image`, etc.
2) **Pixel buffer blit:** host exposes `get_framebuffer(win_id) -> bytes/typedbuf` and UI draws into it.

Pixel buffer blit is usually the fastest bring-up:

- deterministic (pure buffer writes)
- no GPU API surface in v0
- easy to debug (dump RGBA to PNG later)

### Platform shim boundary

The “host UI domain implementation” should be a small platform shim compiled with the platform toolchain:

- macOS: Cocoa/Quartz/Metal (event pump, window, blit)
- Windows: Win32 + GDI (DIBSection + BitBlt) or D3D11 later
- Linux: X11/Wayland (start with X11 for reach; later Wayland)

Oren’s native backend should interact with this shim via FFI:

- Windows: `@ffi.dll("orenui_win.dll")` style
- Linux: `@ffi.link("liborenui_linux.so")` style
- macOS: `@ffi.link("liborenui_macos.dylib")` style

This keeps the core repo syscall-first while acknowledging that GUI requires platform frameworks.

### 3.1) Platform shim bring-up plan (OrenUI v0)

Current repo state (fact):

- In-tree shim header: `native/orenui/orenui.h`
- macOS shim implementation exists: `native/orenui/cocoa/orenui_cocoa.m`
- Windows shim bring-up exists: `native/orenui/win32/orenui_win32.c` (v0 skeleton; window + present + pump)
- Linux/X11 shim bring-up exists: `native/orenui/x11/orenui_x11.c` (v0 skeleton; window + present + pump)
- Smoke gate (macOS-only; requires GUI session): `scripts/verify_ui_smoke_macos.sh` (`make verify-ui-smoke-macos`)
- Smoke gate (Windows; requires GUI session): `scripts/verify_ui_smoke_windows.sh` (`make verify-ui-smoke-windows`)
  - MSVC environment is auto-configured via `scripts/win_msvc_cmd.cmd` (no VS Developer Prompt required).
- Smoke gate (Linux; requires X11 GUI session + dev libs): `scripts/verify_ui_smoke_linux.sh` (`make verify-ui-smoke-linux`)
  - Build detail: links with `-pthread` + `libX11` (some distros still require explicit pthread linkage).
- Missing today (still true):
  - Stable input/event schema (v0 currently only supports close/pump reliably).
  - DPI/scale reporting beyond “best-effort scale=1”.
  - Wayland support (future; X11 is the v0 target).

v0 must do:

1) Create a window with a pixel surface (RGBA).
2) Pump OS events (mouse, keyboard, resize, close).
3) Present a provided RGBA framebuffer to the window at interactive rates.
4) Provide DPI scale (or at least a stable “scale=1” until implemented).

v0 must not do:

- Implement layout/widgets/state (belongs in `std:ui/*`).
- Expose platform APIs directly to user Oren code (avoid Win32/X11/Cocoa leakage).
- Require a GPU API just to show pixels.

Recommended v0 boundary: “RGBA blit shell”

- UI core:
  - `std:ui/render`: tree → deterministic command buffer
  - `std:ui/raster`: commands → RGBA bytes
- Shim:
  - `present_rgba(win_id, w, h, rgba_bytes, stride)` → display
  - `poll_event(win_id, timeout_ms)` → return next event

This matches the existing headless rasterizer, so platform shims can start by “just blitting pixels”
without committing to a GPU backend.

ABI surface options (choose one for implementation):

Option A (preferred): C ABI + flat POD (no structs in v0)

- Repo fact (today): the v0 ABI in `native/orenui/orenui.h` intentionally avoids `struct`/`union` parameters.
- Events are returned via an `int64[5]` out buffer (`orenui_poll_event(..., out5_i64_ptr)`).

Event payloads (v0, implemented):

- `ORENUI_EV_CLOSE`:
  - `out[0]=1`, rest `0`
- `ORENUI_EV_RESIZE`:
  - `out[0]=2`, `out[1]=w`, `out[2]=h`
- `ORENUI_EV_MOUSE_MOVE`:
  - `out[0]=3`, `out[1]=x`, `out[2]=y`, `out[3]=mods`
- `ORENUI_EV_MOUSE_DOWN` / `ORENUI_EV_MOUSE_UP`:
  - `out[0]=4/5`, `out[1]=btn (1=left,2=middle,3=right)`, `out[2]=x`, `out[3]=y`, `out[4]=mods`
- `ORENUI_EV_KEY_DOWN` / `ORENUI_EV_KEY_UP`:
  - `out[0]=6/7`, `out[1]=key (platform raw)`, `out[2]=mods`
- `ORENUI_EV_TEXT`:
  - `out[0]=8`, `out[1]=codepoint (best-effort)`, `out[2]=mods`

Notes:

- `mods` bitmask (v0): `1=shift`, `2=ctrl`, `4=alt`, `8=super` (best-effort across OSes).
- Key codes are currently platform-raw; a stable cross-platform key enum is a future layer.
- Unicode text is best-effort in v0; full IME and surrogate pairing are future work.

Suggested C ABI (v0):

- Window lifecycle:
  - `int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h);`
  - `void orenui_close_window(int32_t win_id);`
  - `void orenui_set_title(int32_t win_id, const char* title_utf8);` (optional)
- Frame:
  - `int32_t orenui_begin_frame(int32_t win_id, struct OrenUIFrameInfo* out);`
  - `int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, const uint8_t* rgba, int32_t stride);`
- Events:
  - Implemented (repo): `int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, int64_t out5_i64_ptr);`
    - returns: `0 = none`, `1 = event`, `<0 = error`
    - `out[0] = type`, `out[1..4] = payload` (see `native/orenui/orenui.h`)

Future (v1+):

- Switch to explicit `struct OrenUIEvent` / `struct OrenUIFrameInfo` once Oren FFI has a stable
  “struct by pointer” story.

Option B: C ABI returning “event maps” (slower, but closer to Oren values)

- Pros: matches the event map examples in this doc directly.
- Cons: requires JSON parsing in the event loop (extra allocations + latency), harder to keep stable across backends.

Unless we absolutely need this for AVM-first integration, prefer Option A.

Per-platform v0 implementation notes (RGBA blit):

Windows (`x64-windows`)

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

Linux (`arm64-linux`, `x64-linux`)

- Start with X11 for reach; Wayland can be added later.
- Window creation: Xlib (`XOpenDisplay`, `XCreateSimpleWindow`, `XMapWindow`)
- Event pump: `XPending`/`XNextEvent`
- Blit strategy (v0):
  - `XPutImage` with an `XImage` that wraps the RGBA buffer (conversion may be required)
  - later: XShm for performance
- DPI:
  - v0: `scale=1`
  - later: derive from Xft/DPI settings or per-monitor info

macOS (`arm64-macos`)

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

Concrete v0 deliverables (what to build next):

1) Finalize the shim ABI (`native/orenui/orenui.h`):
   - lock a minimal set of v0 calls (open/close/poll/begin_frame/present_rgba)
   - lock the `OrenUIEvent` tagged union layout
2) macOS (`arm64-macos`):
   - keep iterating `native/orenui/cocoa/orenui_cocoa.m` until the v0 ABI is fully implemented
   - keep `scripts/verify_ui_smoke_macos.sh` green (headful; opt-in)
3) Windows (`x64-windows`):
   - add `native/orenui/win32/*` implementing the same ABI using Win32 + GDI (RGBA blit)
   - keep `scripts/verify_ui_smoke_windows.sh` green (headful; opt-in)
4) Linux (`x64-linux`, `arm64-linux`):
   - add `native/orenui/x11/*` implementing the same ABI using Xlib + XPutImage (v0)
   - keep `scripts/verify_ui_smoke_linux.sh` green (headful; opt-in; WSL2 is not a GUI target by default)
5) Oren-side integration:
   - done: `std:ui/host` bindings exist (`lib/std/ui/host.oren`) and convert the flat `int64[5]` payload into an event map
   - done: `examples/ui_hello.oren` opens a window and draws a `std:ui` frame (uses `std:ui/host`)

## 4) Packaging model

Recommended app structure:

- `app_shell` (native Oren binary)
  - loads UI bytecode `app_ui.obc`
  - creates AVM instance
  - allows only UI domain ops (and optionally TIME/RNG)
  - runs the VM event loop
- `app_ui.obc` (bytecode compiled from Oren UI sources)

Benefits:

- update UI without replacing the whole native app
- potential “AppStore/multiverse updates” story aligns with signed `.obc`
- capability allowlist is explicit and auditable

## 5) Declarative UI formats: do we need XML and CSS?

### Do we need XML?

Not for v0.

Oren already has deterministic `std:yaml` and `std:json` (`lib/std/yaml.oren`, `lib/std/json.oren`).
If we want “non-code” UI declarations early, YAML is the lowest-friction choice:

- stable parser already exists
- good for trees and configs
- deterministic encoding rules already documented/implemented

XML becomes valuable when we need:

- compatibility with existing XML UI ecosystems, or
- strict schemas/DTDs, or
- complex mixed-content text layouts.

Those are not required to build a production GUI core. XML can be added later as `std:encoding/xml`
and used by `std:ui/markup_xml` without changing the UI core.

### Do we need CSS?

Not for v0.

CSS is large (cascade, selectors, specificity, inheritance, media queries, etc).
The project can still have a “CSS-like” styling story without adopting CSS the standard:

- v0: style maps + explicit composition (`merge_style(base, override)`)
- v1: a small CSS subset parser in `std:ui/css` (selectors limited to type + id + class)
- v2+: optional cascade rules if/when needed

The key is to avoid entangling layout correctness with CSS semantics early.

## 6) Testing strategy (non-negotiable)

We want GUI bring-up without “manual clicking” being the only test.

### Headless deterministic tests (fast, CI-friendly)

- UI tree diff correctness (pure functions)
- layout engine invariants (golden sizes/positions)
- style merge correctness
- command buffer generation (golden command streams)

These should run under AVM without host windows.

### Platform smoke tests (Tier‑1, opt-in)

- “open window, draw frame, close” smoke per OS
- input pump sanity (“mousemove generates event”)

These are still valuable but should not be the only correctness story.

### Optional bring-up shell: Dear ImGui (integration candidate)

Oren’s planned UI stack is retained-mode and portable at the `std:ui/*` level.
Dear ImGui is immediate-mode and does **not** replace the Oren app UI API.

Non-conflicting roles:

1) **Devtools / inspector overlay** (recommended)
   - layout inspector / widget tree explorer
   - perf overlays (layout/raster timing, allocations, GC stats)
   - debug consoles / REPL surfaces
2) **Bring-up shell shortcut** (optional, non-blocking)
   - provides “window + input + GPU present” earlier on platforms with mature ImGui backends
   - keeps `std:ui` as the portable user API

Why ImGui does not replace `std:ui`:

- ImGui is immediate-mode (great for tooling, not a declarative retained-mode widget system).
- Oren UI must be deterministic for AVM/headless tests.
- Long-term Oren UI needs stable reflection + data binding; ImGui is intentionally minimal.

Practical integration shape (recommended):

- Keep ImGui out of the language core and out of `std:ui` semantics.
- `std:ui/*` stays the stable API (layout/render/raster + event model).
- Platform shims (`native/orenui/*`) remain the thin “window + event pump + present” layer.
- An ImGui path can exist as an **optional shell**:
  - `native/orenui/imgui_shell/*` (or `native/orenshell_imgui/*`) compiled as a shared library
  - provides the same C ABI as other platform shims (or a superset ABI for devtools only)
  - can host an ImGui overlay and/or drive presentation through an existing renderer backend

Why ImGui is a good fit for Oren’s “no-bloat” philosophy (facts):

- **Bloat-free core + no external deps:** self-contained and renderer-agnostic (see upstream README).
- **Decoupled rendering:** outputs draw lists / vertex buffers for your pipeline.
- **Small surface area:** immediate-mode API with minimal “state synchronization” overhead.
- **Mature cross-platform backend ecosystem:** upstream maintains multiple platform/render backends.
- **License:** MIT (see upstream license).

Known limitations (fact; important for Oren UI long-term):

- Upstream explicitly targets programmer tools (not full end-user UI), and does not aim to solve
  full i18n text shaping or accessibility out of the box. This is why it remains optional.

Backend audit (sources in-repo):

- `project-doc/web/github.com/ocornut/imgui/20260113/docs_BACKENDS.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/docs_README.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/docs_FAQ.md`
- `project-doc/web/github.com/ocornut/imgui/20260113/root_index.json` / `docs_index.json` (GitHub API snapshots)

Tier‑1 constraints (Oren):

- Tier‑1 targets (rolling): `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`.
- The repo’s Tier‑1 x64 Linux environment is currently validated via **WSL2** for CI-like bring-up.
  WSL2 is not a reliable GUI target by default. Treat Linux GUI as a real Linux desktop session target,
  not as part of remote WSL2 smoke gates.

Next actions (non-blocking):

- Keep bringing up `native/orenui/*` per-platform shims (RGBA present + input pump).
- Once one shim is stable, add an opt-in ImGui overlay build that can:
  - attach to the same window
  - show Oren UI debug state (frame timings, command buffer stats)
- Defer any “use ImGui to render Oren UI widgets” until Oren’s retained-mode UI API is stable.

Suggested backend choices (Tier‑1 oriented; not commitments):

- **Windows x64:** Win32 window + D3D11 renderer backend.
- **macOS arm64:** Cocoa window + Metal backend (avoid OpenGL as the primary path).
- **Linux x64:** X11 window + OpenGL backend (widest reach; Wayland can come later).

## 6.1) Current implementation status (v0)

Implemented (headless, portable):

- `std:ui/core` (`lib/std/ui/core.oren`): node constructors + keyed `diff()` + `apply_patch()` (actionable patches)
- `std:ui/layout` (`lib/std/ui/layout.oren`): deterministic layout v0 (`Row`/`Column`/`Stack`, fixed-size leaves)
- `std:ui/style` (`lib/std/ui/style.oren`): deterministic style merge (no CSS yet)
- `std:ui/render` (`lib/std/ui/render.oren`): render → deterministic command buffer (no platform drawing yet)
- `std:ui/raster` (`lib/std/ui/raster.oren`): deterministic software rasterization into RGBA bytes (headless reference)
- `std:ui/ppm` (`lib/std/ui/ppm.oren`): minimal PPM encoder for debugging and golden byte tests
- `std:ui/color` (`lib/std/ui/color.oren`): shared hex color parsing/validation (`#RRGGBB` / `#RRGGBBAA`)

Regression gates (headless):

- `make test-avm`
  - `tests/avm/test_ui_layout_v0.oren`
  - `tests/avm/test_ui_render_v0.oren`
  - `tests/avm/test_ui_raster_v0.oren`
  - `tests/avm/test_ui_ppm_v0.oren`
  - `tests/avm/test_ui_patch_v0.oren`
  - `tests/avm/test_ui_color_v0.oren`

## 7) Roadmap tasks (tracked in `docs/TODOS.md`)

This document defines the intended design; implementation tasks are tracked in `docs/TODOS.md`.
The recommended progression is:

1) `std:ui` portable core (node model + diff + layout + style)
2) UI domain v0 contract (domain/op table + minimal shims)
3) software framebuffer renderer v0 (cross-platform shim per OS)
4) text measurement/shaping + font loading (incremental; can be stubbed initially)
5) richer widgets and accessibility (later)
