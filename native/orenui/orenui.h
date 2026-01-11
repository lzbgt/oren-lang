// OrenUI platform shim C ABI (v0, rolling)
//
// This header defines the *minimal* ABI used by native Oren shells to open a window,
// blit an RGBA framebuffer, and pump events.
//
// v0 design choice:
// - avoid structs/unions in the first implementation so Oren FFI can call it with
//   plain integer arguments (including raw pointers as ints).
// - the “real” event schema can be added later once FFI has a stable struct story.
//
// Tier‑1 intent:
// - arm64-macos: Cocoa/CoreGraphics implementation (`orenui_cocoa`)
// - x64-windows: Win32/GDI implementation (`orenui_win32`)
// - arm64-linux + x64-linux: X11 implementation (`orenui_x11`)
//
// NOTE: The API is intentionally tiny and is *not* a public user-facing Oren stdlib API.
// It is a platform shim boundary used by higher-level Oren UI libraries.

#pragma once

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

// Open a window. Returns a positive window id on success, negative on error.
int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h);

// Close the window. It is valid to call this multiple times.
void orenui_close_window(int32_t win_id);

// Present an RGBA framebuffer into the window.
//
// - `rgba_ptr` is a raw pointer to `h * stride` bytes (R,G,B,A interleaved).
// - `stride` is bytes per row (typically `w * 4`).
//
// Return:
// - 0 on success
// - negative on error
int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, int64_t rgba_ptr, int32_t stride);

// Pump the platform event queue once (or for up to timeout_ms).
//
// Return:
// - 1 if the window is closing / should exit
// - 0 otherwise
int32_t orenui_pump(int32_t win_id, int32_t timeout_ms);

#if defined(__cplusplus)
} // extern "C"
#endif

