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

Some earlier discussions referenced a `ui-idea.md` scratch file. That file does not exist in this repo today.
Treat this document (`docs/GUI.md`) and the shim plan (`docs/GUI_PLATFORM_SHIMS.md`) as the current source of truth.

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

See `docs/AVM_SPEC.md` and `docs/AVM_SPEC_V1.md` for the domain/op model and the governance direction.

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
  - Event maps (examples):
    - `{"t":"mouse_move","x":123,"y":456,"mods":0}`
    - `{"t":"mouse_down","btn":1,"x":...,"y":...}`
    - `{"t":"key_down","key":...,"codepoint":...}`
    - `{"t":"resize","w":...,"h":...,"scale":...}`
    - `{"t":"close"}`

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

For an actionable v0 bring-up plan (RGBA framebuffer shims per OS, minimal ABI), see:

- `docs/GUI_PLATFORM_SHIMS.md`

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

Dear ImGui is a widely used, “bloat-free” immediate-mode C++ UI library with many platform/render backends.
For Oren, the most promising use is **not** “replace the planned portable UI core with ImGui”, but:

- use ImGui as a **cross-platform shell layer** (window + input pump + GPU backend)
- keep Oren’s **portable UI core** (`std:ui/*`) as the source of truth (tree/layout/diff/render/raster)

Concretely, a minimal bring-up path is:

1) Oren UI core renders into an RGBA framebuffer (already implemented: `std:ui/raster`)
2) A tiny native shell uploads the buffer as a texture and displays it each frame
3) Input events are translated into the Oren event schema and fed back into the VM/UI core

This is attractive because it reduces the “platform shim” surface area early:

- we don’t need to commit to Metal vs D3D vs Vulkan immediately (ImGui backends already exist)
- we can bring up “window + present” quickly while preserving deterministic headless testing

Tradeoffs (why this stays optional):

- ImGui is immediate-mode: great for tools/debug UIs, but it is not a declarative retained-mode widget system.
- The long-run production API for Oren apps should still be the stable, portable `std:ui` model, not a C++-FFI-heavy surface.

Upstream reference material (downloaded into this repo for auditing): `project-doc/web/github.com/ocornut/imgui/`.

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
