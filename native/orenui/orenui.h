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

// Poll one event from the platform queue (v0).
//
// This is the preferred API for portable shells: it makes the “event loop contract”
// explicit, instead of overloading `pump()` with meaning.
//
// `out5_i64_ptr` points to 5 int64 slots written by the shim:
//   out[0] = event type (see ORENUI_EV_*)
//   out[1]..out[4] = event payload (type-specific)
//
// Return:
// - 1 if an event was written to out[]
// - 0 if no event is available (within timeout_ms)
// - negative on error
int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, int64_t out5_i64_ptr);

// v0 event tags (rolling; minimal set only).
// Payload layout:
// - CLOSE:  out[1..4] = 0
// - RESIZE: out[1] = w (i64), out[2] = h (i64)
#define ORENUI_EV_CLOSE  1
#define ORENUI_EV_RESIZE 2

#if defined(__cplusplus)
} // extern "C"
#endif
