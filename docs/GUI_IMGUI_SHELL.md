# Dear ImGui as an optional shell/overlay for Oren UI (rolling)

Oren’s planned UI stack is **retained-mode**, deterministic, and portable at the `std:ui/*` level.
Dear ImGui is **immediate-mode** and is not a long-term replacement for Oren’s app UI API.

However, ImGui has mature platform+renderer backends and can be valuable in two non-conflicting roles:

1. **Devtools / inspector overlay** (recommended)
   - Once Oren has a window + input pump + pixel/GPU present on at least one platform, ImGui can provide:
     - layout inspector / widget tree explorer
     - perf overlays (raster + layout timing, allocations, GC stats)
     - debug consoles / REPL surfaces

2. **Bring-up shell shortcut** (optional, non-blocking)
   - An ImGui-based shell can provide “window + input + GPU present” sooner on platforms where the
     ImGui backend ecosystem is mature, while keeping `std:ui` as the portable user API.
   - This is a *temporary acceleration tool* (not a language/library design dependency).

## Why ImGui does not replace `std:ui`

- **ImGui is immediate-mode**: great for tooling, but not a declarative retained-mode widget system.
- **Oren UI must be deterministic** for AVM/headless tests (layout/render/raster already exists in `std:ui/*`).
- **Long-term Oren UI needs stable reflection + data binding**; ImGui is intentionally minimal and not a full app framework.

## Practical integration shape (recommended)

Keep ImGui out of the language core and out of `std:ui` semantics:

- `std:ui/*` stays the stable API (layout/render/raster + event model).
- Platform shims (`native/orenui/*`) remain the thin “window + event pump + present” layer.
- An ImGui path is introduced as an **optional shell**:
  - `native/orenui/imgui_shell/*` (or `native/orenshell_imgui/*`) compiled as a shared library
  - provides the same C ABI as other platform shims (or a superset ABI for devtools only)
  - can host an ImGui overlay and/or drive presentation through an existing renderer backend

This ensures:
- no lock-in to SDL/GLFW/Metal/D3D in the core language/runtime
- no requirement that user apps depend on ImGui
- we can drop/replace the shell without breaking `std:ui`

## Backend audit (sources in-repo)

Upstream reference materials are stored (verbatim) under:

- `project-doc/web/github.com/ocornut/imgui/20260111/docs_BACKENDS.md`
- `project-doc/web/github.com/ocornut/imgui/20260111/docs_README.md`
- `project-doc/web/github.com/ocornut/imgui/20260111/docs_FAQ.md`

When selecting a “shell shortcut” backend for Tier‑1, treat these as input, not as design authority.

## Tier‑1 constraints (Oren)

Oren’s Tier‑1 targets (rolling) are:
- `arm64-macos`
- `arm64-linux`
- `x64-windows`
- `x64-linux` (via WSL2 and/or Linux host)

For Oren, the primary requirement is not “GPU rendering quality” at v0 — it is:
- reliable window creation
- reliable input pump
- bounded frame present
- a stable ABI for `std:ui` to talk to the host

ImGui can help, but only after the v0 “software RGBA blit shim” path is stable (so we have a fallback that does not depend on third-party event loops or renderers).

## Next actions (non-blocking)

- Keep bringing up `native/orenui/*` per-platform shims (RGBA present + input pump).
- Once one shim is stable, add an opt-in ImGui overlay build that can:
  - attach to the same window
  - show Oren UI debug state (frame timings, command buffer stats)
- Defer any “use ImGui to render Oren UI widgets” until Oren’s retained-mode UI API is stable.

