// OrenUI Win32 shim (x64-windows) — v0 RGBA blit shell
//
// Minimal platform shim:
// - creates a Win32 window
// - blits a software framebuffer into the window via GDI (StretchDIBits)
// - pumps the message queue so the window stays responsive
//
// Pixel contract:
// - input is RGBA (R,G,B,A) with unassociated alpha (matches `std:ui/raster`)
// - internal storage is BGRA with premultiplied alpha (common for Win32 DIB/GDI paths)
//
// Notes (rolling):
// - This is not part of `make test` because it requires a GUI session.
// - The ABI is intentionally tiny (see `native/orenui/orenui.h`).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../orenui.h"

typedef struct OrenUIWin32State {
  int32_t id;
  HWND hwnd;
  DWORD owner_tid;
  volatile LONG should_close;

  uint8_t* bgra;   // premultiplied BGRA, row-major, top-to-bottom
  int32_t w;
  int32_t h;
  int32_t stride;  // bytes per row (w*4)
  size_t cap;      // bytes allocated in bgra
} OrenUIWin32State;

static OrenUIWin32State* g_states[64];
static int32_t g_next_id = 1;

static OrenUIWin32State* orenui__get(int32_t win_id) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    OrenUIWin32State* st = g_states[i];
    if (st && st->id == win_id) {
      return st;
    }
  }
  return NULL;
}

static void orenui__drop(int32_t win_id) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    OrenUIWin32State* st = g_states[i];
    if (st && st->id == win_id) {
      g_states[i] = NULL;
      if (st->bgra) {
        free(st->bgra);
        st->bgra = NULL;
        st->cap = 0;
      }
      free(st);
      return;
    }
  }
}

static int orenui__slot_put(OrenUIWin32State* st) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    if (g_states[i] == NULL) {
      g_states[i] = st;
      return 1;
    }
  }
  return 0;
}

static int32_t orenui__utf8_to_wide_best_effort(const char* s_utf8, wchar_t* out, int out_cap) {
  if (!out || out_cap <= 0) {
    return 0;
  }
  out[0] = L'\0';
  if (!s_utf8 || s_utf8[0] == 0) {
    return 0;
  }
  int n = MultiByteToWideChar(CP_UTF8, 0, s_utf8, -1, out, out_cap);
  if (n <= 0) {
    out[0] = L'\0';
    return 0;
  }
  // n includes NUL
  return (int32_t)(n - 1);
}

static void orenui__convert_rgba_to_premul_bgra(OrenUIWin32State* st, const uint8_t* src, int32_t src_stride) {
  if (!st || !st->bgra || !src) {
    return;
  }
  const int32_t w = st->w;
  const int32_t h = st->h;
  const int32_t dst_stride = st->stride;
  if (w <= 0 || h <= 0 || dst_stride <= 0 || src_stride <= 0) {
    return;
  }

  for (int32_t y = 0; y < h; y++) {
    const uint8_t* srow = src + (size_t)y * (size_t)src_stride;
    uint8_t* drow = st->bgra + (size_t)y * (size_t)dst_stride;
    for (int32_t x = 0; x < w; x++) {
      size_t so = (size_t)x * 4u;
      uint32_t r = srow[so + 0];
      uint32_t g = srow[so + 1];
      uint32_t b = srow[so + 2];
      uint32_t a = srow[so + 3];

      uint32_t pr = (r * a + 127u) / 255u;
      uint32_t pg = (g * a + 127u) / 255u;
      uint32_t pb = (b * a + 127u) / 255u;

      size_t doff = (size_t)x * 4u;
      drow[doff + 0] = (uint8_t)pb;
      drow[doff + 1] = (uint8_t)pg;
      drow[doff + 2] = (uint8_t)pr;
      drow[doff + 3] = (uint8_t)a;
    }
  }
}

static LRESULT CALLBACK orenui__wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  OrenUIWin32State* st = (OrenUIWin32State*)(uintptr_t)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
    case WM_CLOSE: {
      if (st) {
        InterlockedExchange(&st->should_close, 1);
      }
      DestroyWindow(hwnd);
      return 0;
    }
    case WM_DESTROY: {
      if (st) {
        InterlockedExchange(&st->should_close, 1);
      }
      return 0;
    }
    case WM_PAINT: {
      if (!st) {
        break;
      }
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      if (dc && st->bgra && st->w > 0 && st->h > 0 && st->stride == st->w * 4) {
        BITMAPINFO bmi;
        ZeroMemory(&bmi, sizeof(bmi));
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = st->w;
        bmi.bmiHeader.biHeight = -st->h;  // top-down
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        // Best-effort blit. Alpha is ignored by classic GDI compositing, but premultiplying
        // now keeps the buffer semantically correct for future GPU paths.
        StretchDIBits(dc,
                      0,
                      0,
                      st->w,
                      st->h,
                      0,
                      0,
                      st->w,
                      st->h,
                      st->bgra,
                      &bmi,
                      DIB_RGB_COLORS,
                      SRCCOPY);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static int orenui__register_class_once(void) {
  static LONG registered = 0;
  if (InterlockedCompareExchange(&registered, 1, 0) != 0) {
    return 1;
  }
  WNDCLASSEXW wc;
  ZeroMemory(&wc, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = orenui__wndproc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  wc.lpszClassName = L"OrenUIWin32WindowClass";
  ATOM a = RegisterClassExW(&wc);
  return (a != 0) ? 1 : 0;
}

int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h) {
  if (w <= 0 || h <= 0) {
    return -4;
  }
  if (!orenui__register_class_once()) {
    return -8;
  }

  OrenUIWin32State* st = (OrenUIWin32State*)calloc(1, sizeof(OrenUIWin32State));
  if (!st) {
    return -12;
  }
  st->id = g_next_id++;
  st->owner_tid = GetCurrentThreadId();
  st->should_close = 0;
  st->w = w;
  st->h = h;
  st->stride = w * 4;
  st->cap = 0;
  st->bgra = NULL;

  if (!orenui__slot_put(st)) {
    free(st);
    return -28;  // ENOSPC-ish (too many windows)
  }

  wchar_t wtitle[256];
  orenui__utf8_to_wide_best_effort(title_utf8, wtitle, (int)(sizeof(wtitle) / sizeof(wtitle[0])));
  const wchar_t* title = (wtitle[0] != L'\0') ? wtitle : L"OrenUI";

  DWORD style = WS_OVERLAPPEDWINDOW;
  RECT r = {0, 0, (LONG)w, (LONG)h};
  AdjustWindowRect(&r, style, FALSE);
  int ww = (int)(r.right - r.left);
  int hh = (int)(r.bottom - r.top);

  HWND hwnd = CreateWindowExW(0,
                             L"OrenUIWin32WindowClass",
                             title,
                             style,
                             CW_USEDEFAULT,
                             CW_USEDEFAULT,
                             ww,
                             hh,
                             NULL,
                             NULL,
                             GetModuleHandleW(NULL),
                             NULL);
  if (!hwnd) {
    int32_t id = st->id;
    orenui__drop(id);
    return -8;
  }
  st->hwnd = hwnd;
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, (LONG_PTR)(uintptr_t)st);
  ShowWindow(hwnd, SW_SHOW);
  UpdateWindow(hwnd);
  return st->id;
}

void orenui_close_window(int32_t win_id) {
  OrenUIWin32State* st = orenui__get(win_id);
  if (!st) {
    return;
  }
  if (st->owner_tid != GetCurrentThreadId()) {
    // Win32 UI is thread-affine; keep v0 strict.
    return;
  }
  if (st->hwnd) {
    DestroyWindow(st->hwnd);
    st->hwnd = NULL;
  }
  orenui__drop(win_id);
}

int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, int64_t rgba_ptr, int32_t stride) {
  OrenUIWin32State* st = orenui__get(win_id);
  if (!st || !st->hwnd) {
    return -4;
  }
  if (st->owner_tid != GetCurrentThreadId()) {
    return -16;
  }
  if (w <= 0 || h <= 0 || stride <= 0 || rgba_ptr == 0) {
    return -4;
  }
  if (w != st->w || h != st->h) {
    st->w = w;
    st->h = h;
    st->stride = w * 4;
  }

  size_t need = (size_t)st->h * (size_t)st->stride;
  if (need == 0) {
    return -4;
  }
  if (!st->bgra || st->cap < need) {
    uint8_t* p = (uint8_t*)realloc(st->bgra, need);
    if (!p) {
      return -12;
    }
    st->bgra = p;
    st->cap = need;
  }

  const uint8_t* src = (const uint8_t*)(uintptr_t)rgba_ptr;
  orenui__convert_rgba_to_premul_bgra(st, src, stride);

  InvalidateRect(st->hwnd, NULL, FALSE);
  return 0;
}

int32_t orenui_pump(int32_t win_id, int32_t timeout_ms) {
  OrenUIWin32State* st = orenui__get(win_id);
  if (!st || !st->hwnd) {
    return 1;
  }
  if (st->owner_tid != GetCurrentThreadId()) {
    return 1;
  }
  if (InterlockedCompareExchange(&st->should_close, 0, 0) != 0) {
    return 1;
  }

  if (timeout_ms > 0) {
    // Wait until there is input to process (or timeout).
    MsgWaitForMultipleObjects(0, NULL, FALSE, (DWORD)timeout_ms, QS_ALLINPUT);
  }

  MSG msg;
  while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  // Force paint flush inside the pump boundary (mirrors Cocoa shim behavior).
  UpdateWindow(st->hwnd);

  return (InterlockedCompareExchange(&st->should_close, 0, 0) != 0) ? 1 : 0;
}

