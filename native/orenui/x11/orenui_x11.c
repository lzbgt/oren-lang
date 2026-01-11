// OrenUI X11 shim (arm64-linux / x64-linux) — v0 RGBA blit shell
//
// Minimal platform shim:
// - opens an X11 window
// - blits a software framebuffer via XPutImage
// - pumps the event queue so the window stays responsive
//
// ABI: `native/orenui/orenui.h`
//
// Rolling notes:
// - This is a bring-up shim for Linux desktop sessions with X11.
// - It is not a reliable target for WSL2 by default (typically no DISPLAY).
// - Pixel format handling is best-effort and targets common TrueColor visuals.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <pthread.h>
#include <unistd.h>
#include <sys/select.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "../orenui.h"

typedef struct OrenUIX11State {
  int32_t id;
  Display* dpy;
  int screen;
  Window win;
  GC gc;
  Atom wm_delete;

  pthread_t owner;
  int32_t should_close;
  int close_reported;

  uint8_t* pixels;  // packed pixels suitable for XPutImage (see present_rgba)
  int32_t w;
  int32_t h;
  int32_t stride;
  size_t cap;

  int ev_r;
  int ev_w;
  int64_t ev_q[64][5];
} OrenUIX11State;

static OrenUIX11State* g_states[64];
static int32_t g_next_id = 1;

static OrenUIX11State* orenui__get(int32_t win_id) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    OrenUIX11State* st = g_states[i];
    if (st && st->id == win_id) {
      return st;
    }
  }
  return NULL;
}

static void orenui__drop(int32_t win_id) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    OrenUIX11State* st = g_states[i];
    if (st && st->id == win_id) {
      g_states[i] = NULL;
      if (st->pixels) {
        free(st->pixels);
        st->pixels = NULL;
        st->cap = 0;
      }
      if (st->dpy) {
        // Best-effort teardown: these calls tolerate already-destroyed windows.
        if (st->win) {
          XDestroyWindow(st->dpy, st->win);
        }
        XCloseDisplay(st->dpy);
        st->dpy = NULL;
      }
      free(st);
      return;
    }
  }
}

static int orenui__slot_put(OrenUIX11State* st) {
  for (int i = 0; i < (int)(sizeof(g_states) / sizeof(g_states[0])); i++) {
    if (g_states[i] == NULL) {
      g_states[i] = st;
      return 1;
    }
  }
  return 0;
}

static int orenui__require_owner(OrenUIX11State* st) {
  if (!st) {
    return 0;
  }
  return pthread_equal(st->owner, pthread_self()) ? 1 : 0;
}

static void orenui__ev_push(OrenUIX11State* st, int64_t ty, int64_t a0, int64_t a1, int64_t a2, int64_t a3) {
  if (!st) {
    return;
  }
  int next_w = (st->ev_w + 1) % 64;
  if (next_w == st->ev_r) {
    return;
  }
  st->ev_q[st->ev_w][0] = ty;
  st->ev_q[st->ev_w][1] = a0;
  st->ev_q[st->ev_w][2] = a1;
  st->ev_q[st->ev_w][3] = a2;
  st->ev_q[st->ev_w][4] = a3;
  st->ev_w = next_w;
}

static int orenui__ev_pop(OrenUIX11State* st, int64_t out5_i64_ptr) {
  if (!st || out5_i64_ptr == 0) {
    return 0;
  }
  if (st->ev_r == st->ev_w) {
    return 0;
  }
  int64_t* out = (int64_t*)(uintptr_t)out5_i64_ptr;
  for (int i = 0; i < 5; i++) {
    out[i] = st->ev_q[st->ev_r][i];
  }
  st->ev_r = (st->ev_r + 1) % 64;
  return 1;
}

static void orenui__pump_once(OrenUIX11State* st) {
  if (!st || !st->dpy) {
    return;
  }
  while (XPending(st->dpy) > 0) {
    XEvent ev;
    XNextEvent(st->dpy, &ev);
    switch (ev.type) {
      case ClientMessage: {
        if ((Atom)ev.xclient.data.l[0] == st->wm_delete) {
          st->should_close = 1;
          orenui__ev_push(st, ORENUI_EV_CLOSE, 0, 0, 0, 0);
        }
        break;
      }
      case ConfigureNotify: {
        // Window resized.
        int32_t nw = (int32_t)ev.xconfigure.width;
        int32_t nh = (int32_t)ev.xconfigure.height;
        if (nw > 0 && nh > 0) {
          orenui__ev_push(st, ORENUI_EV_RESIZE, (int64_t)nw, (int64_t)nh, 0, 0);
        }
        break;
      }
      case DestroyNotify: {
        st->should_close = 1;
        orenui__ev_push(st, ORENUI_EV_CLOSE, 0, 0, 0, 0);
        break;
      }
      default:
        break;
    }
  }
}

static void orenui__wait_events(OrenUIX11State* st, int32_t timeout_ms) {
  if (!st || !st->dpy || timeout_ms <= 0) {
    return;
  }
  int fd = ConnectionNumber(st->dpy);
  if (fd < 0) {
    return;
  }

  fd_set rfds;
  FD_ZERO(&rfds);
  FD_SET(fd, &rfds);
  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;

  // Wait for X11 socket readability. We ignore errors/timeouts; caller will pump best-effort.
  select(fd + 1, &rfds, NULL, NULL, &tv);
}

static int32_t orenui__ensure_pixels(OrenUIX11State* st, int32_t w, int32_t h) {
  if (!st || w <= 0 || h <= 0) {
    return -4;
  }
  size_t need = (size_t)w * (size_t)h * 4u;
  if (need > st->cap) {
    size_t new_cap = need;
    uint8_t* p = (uint8_t*)realloc(st->pixels, new_cap);
    if (!p) {
      return -12;
    }
    st->pixels = p;
    st->cap = new_cap;
  }
  st->w = w;
  st->h = h;
  st->stride = w * 4;
  return 0;
}

int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h) {
  if (w <= 0 || h <= 0) {
    return -4;
  }

  OrenUIX11State* st = (OrenUIX11State*)calloc(1, sizeof(OrenUIX11State));
  if (!st) {
    return -12;
  }
  st->id = g_next_id++;
  st->owner = pthread_self();
  st->should_close = 0;
  st->close_reported = 0;
  st->pixels = NULL;
  st->cap = 0;
  st->w = w;
  st->h = h;
  st->stride = w * 4;
  st->ev_r = 0;
  st->ev_w = 0;

  if (!orenui__slot_put(st)) {
    free(st);
    return -28;
  }

  Display* dpy = XOpenDisplay(NULL);
  if (!dpy) {
    int32_t id = st->id;
    orenui__drop(id);
    return -8;
  }
  st->dpy = dpy;
  st->screen = DefaultScreen(dpy);

  Window root = RootWindow(dpy, st->screen);
  unsigned long black = BlackPixel(dpy, st->screen);
  unsigned long white = WhitePixel(dpy, st->screen);

  st->win = XCreateSimpleWindow(dpy, root, 80, 80, (unsigned int)w, (unsigned int)h, 1, black, white);
  if (!st->win) {
    int32_t id = st->id;
    orenui__drop(id);
    return -8;
  }

  // Basic input + close support.
  XSelectInput(dpy, st->win, ExposureMask | KeyPressMask | KeyReleaseMask | ButtonPressMask | ButtonReleaseMask |
                            PointerMotionMask | StructureNotifyMask);
  st->wm_delete = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
  if (st->wm_delete) {
    XSetWMProtocols(dpy, st->win, &st->wm_delete, 1);
  }

  if (title_utf8 && title_utf8[0] != 0) {
    XStoreName(dpy, st->win, title_utf8);
  } else {
    XStoreName(dpy, st->win, "OrenUI");
  }

  st->gc = XCreateGC(dpy, st->win, 0, NULL);
  XMapWindow(dpy, st->win);
  XFlush(dpy);

  // Pre-allocate pixel buffer (best-effort).
  (void)orenui__ensure_pixels(st, w, h);

  return st->id;
}

void orenui_close_window(int32_t win_id) {
  OrenUIX11State* st = orenui__get(win_id);
  if (!st) {
    return;
  }
  if (!orenui__require_owner(st)) {
    return;
  }
  orenui__drop(win_id);
}

int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, int64_t rgba_ptr, int32_t stride) {
  OrenUIX11State* st = orenui__get(win_id);
  if (!st || !st->dpy || !st->win) {
    return -2;
  }
  if (!orenui__require_owner(st)) {
    return -16;
  }
  if (st->should_close) {
    return -1;
  }
  if (w <= 0 || h <= 0 || stride <= 0 || rgba_ptr == 0) {
    return -4;
  }
  if (stride < w * 4) {
    return -4;
  }

  int32_t rc = orenui__ensure_pixels(st, w, h);
  if (rc != 0) {
    return rc;
  }

  const uint8_t* src = (const uint8_t*)(uintptr_t)rgba_ptr;
  uint32_t* dst = (uint32_t*)(void*)st->pixels;

  // Best-effort TrueColor packing based on the default visual masks.
  Visual* vis = DefaultVisual(st->dpy, st->screen);
  unsigned long rm = vis ? vis->red_mask : 0x00ff0000ul;
  unsigned long gm = vis ? vis->green_mask : 0x0000ff00ul;
  unsigned long bm = vis ? vis->blue_mask : 0x000000fful;

  // Compute shift counts for contiguous masks (common case).
  int rshift = 0;
  int gshift = 0;
  int bshift = 0;
  int rbits = 0;
  int gbits = 0;
  int bbits = 0;
  {
    unsigned long x = rm;
    while (x && ((x & 1ul) == 0ul)) {
      rshift++;
      x >>= 1;
    }
    x = gm;
    while (x && ((x & 1ul) == 0ul)) {
      gshift++;
      x >>= 1;
    }
    x = bm;
    while (x && ((x & 1ul) == 0ul)) {
      bshift++;
      x >>= 1;
    }
    x = rm;
    while (x) {
      rbits += (int)(x & 1ul);
      x >>= 1;
    }
    x = gm;
    while (x) {
      gbits += (int)(x & 1ul);
      x >>= 1;
    }
    x = bm;
    while (x) {
      bbits += (int)(x & 1ul);
      x >>= 1;
    }
  }

  // Avoid divide-by-zero if masks are weird.
  if (rbits <= 0 || gbits <= 0 || bbits <= 0) {
    rbits = gbits = bbits = 8;
    rshift = 16;
    gshift = 8;
    bshift = 0;
    rm = 0x00ff0000ul;
    gm = 0x0000ff00ul;
    bm = 0x000000fful;
  }

  for (int32_t y = 0; y < h; y++) {
    const uint8_t* srow = src + (size_t)y * (size_t)stride;
    uint32_t* drow = dst + (size_t)y * (size_t)w;
    for (int32_t x = 0; x < w; x++) {
      size_t so = (size_t)x * 4u;
      uint32_t r8 = srow[so + 0];
      uint32_t g8 = srow[so + 1];
      uint32_t b8 = srow[so + 2];

      // Scale 8-bit to mask width.
      uint32_t r = (rbits >= 8) ? (r8 << (rbits - 8)) : (r8 >> (8 - rbits));
      uint32_t g = (gbits >= 8) ? (g8 << (gbits - 8)) : (g8 >> (8 - gbits));
      uint32_t b = (bbits >= 8) ? (b8 << (bbits - 8)) : (b8 >> (8 - bbits));

      unsigned long px = ((unsigned long)(r) << rshift) & rm;
      px |= ((unsigned long)(g) << gshift) & gm;
      px |= ((unsigned long)(b) << bshift) & bm;
      drow[x] = (uint32_t)px;
    }
  }

  int depth = DefaultDepth(st->dpy, st->screen);
  XImage* img = XCreateImage(st->dpy,
                            DefaultVisual(st->dpy, st->screen),
                            (unsigned int)depth,
                            ZPixmap,
                            0,
                            (char*)st->pixels,
                            (unsigned int)w,
                            (unsigned int)h,
                            32,
                            st->stride);
  if (!img) {
    return -8;
  }

  XPutImage(st->dpy, st->win, st->gc, img, 0, 0, 0, 0, (unsigned int)w, (unsigned int)h);
  XFlush(st->dpy);

  // Avoid XDestroyImage freeing st->pixels; the state owns it.
  img->data = NULL;
  XDestroyImage(img);

  return 0;
}

int32_t orenui_pump(int32_t win_id, int32_t timeout_ms) {
  OrenUIX11State* st = orenui__get(win_id);
  if (!st || !st->dpy) {
    return 1;
  }
  if (!orenui__require_owner(st)) {
    return 1;
  }
  if (st->should_close) {
    return 1;
  }

  if (XPending(st->dpy) == 0) {
    orenui__wait_events(st, timeout_ms);
  }
  orenui__pump_once(st);
  return st->should_close ? 1 : 0;
}

int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, int64_t out5_i64_ptr) {
  OrenUIX11State* st = orenui__get(win_id);
  if (!st || !st->dpy) {
    return -4;
  }
  if (!orenui__require_owner(st)) {
    return -16;
  }
  if (out5_i64_ptr == 0) {
    return -4;
  }

  if (orenui__ev_pop(st, out5_i64_ptr)) {
    return 1;
  }

  if (XPending(st->dpy) == 0) {
    orenui__wait_events(st, timeout_ms);
  }
  orenui__pump_once(st);
  if (orenui__ev_pop(st, out5_i64_ptr)) {
    return 1;
  }

  if (st->should_close && !st->close_reported) {
    st->close_reported = 1;
    int64_t* out = (int64_t*)(uintptr_t)out5_i64_ptr;
    out[0] = ORENUI_EV_CLOSE;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;
    out[4] = 0;
    return 1;
  }

  return 0;
}
