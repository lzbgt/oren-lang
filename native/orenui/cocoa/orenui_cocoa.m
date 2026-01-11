// OrenUI Cocoa shim (arm64-macos) — v0 RGBA blit shell
//
// This is a minimal platform shim:
// - opens an NSWindow
// - blits an RGBA framebuffer (software) into the window via CoreGraphics
// - pumps the event queue so the window stays responsive
//
// It intentionally avoids:
// - text shaping, fonts, input method editors
// - GPU APIs (Metal)
// - any widget/layout/state logic (handled by `std:ui/*`)

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include "../orenui.h"

static void orenui__ensure_app(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // Minimal menubar so the app becomes “real” (otherwise some events can be odd).
    NSMenu* menubar = [[NSMenu alloc] init];
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];

    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@""];
    NSString* appName = [[NSProcessInfo processInfo] processName];
    NSMenuItem* quitItem =
        [[NSMenuItem alloc] initWithTitle:[@"Quit " stringByAppendingString:appName]
                                   action:@selector(terminate:)
                            keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    [NSApp finishLaunching];
  });
}

@interface OrenUICocoaWindowState : NSObject <NSWindowDelegate> {
  pthread_mutex_t _rgbaMu;
  int _ev_r;
  int _ev_w;
  int64_t _ev_q[64][5];
}
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) NSView* view;
@property(nonatomic, assign) BOOL shouldClose;
@property(nonatomic, assign) BOOL closeReported;
@property(nonatomic, assign) int32_t lastReportedW;
@property(nonatomic, assign) int32_t lastReportedH;
@property(nonatomic, assign) uint8_t* rgba;
@property(nonatomic, assign) int32_t w;
@property(nonatomic, assign) int32_t h;
@property(nonatomic, assign) int32_t stride;
@property(nonatomic, assign) size_t cap;
- (void)evPushType:(int64_t)ty a0:(int64_t)a0 a1:(int64_t)a1 a2:(int64_t)a2 a3:(int64_t)a3;
- (int)evPopOut:(int64_t*)out5;
@end

@implementation OrenUICocoaWindowState
- (pthread_mutex_t*)rgbaMuPtr {
  return &_rgbaMu;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    pthread_mutex_init(&_rgbaMu, NULL);
    _rgba = NULL;
    _cap = 0;
    _shouldClose = NO;
    _closeReported = NO;
    _lastReportedW = 0;
    _lastReportedH = 0;
    _ev_r = 0;
    _ev_w = 0;
  }
  return self;
}

- (void)dealloc {
  if (_rgba) {
    free(_rgba);
    _rgba = NULL;
    _cap = 0;
  }
  pthread_mutex_destroy(&_rgbaMu);
}

- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  self.shouldClose = YES;
}

- (void)evPushType:(int64_t)ty a0:(int64_t)a0 a1:(int64_t)a1 a2:(int64_t)a2 a3:(int64_t)a3 {
  int next_w = (_ev_w + 1) % 64;
  if (next_w == _ev_r) {
    return;
  }
  _ev_q[_ev_w][0] = ty;
  _ev_q[_ev_w][1] = a0;
  _ev_q[_ev_w][2] = a1;
  _ev_q[_ev_w][3] = a2;
  _ev_q[_ev_w][4] = a3;
  _ev_w = next_w;
}

- (int)evPopOut:(int64_t*)out5 {
  if (!out5) {
    return 0;
  }
  if (_ev_r == _ev_w) {
    return 0;
  }
  for (int i = 0; i < 5; i++) {
    out5[i] = _ev_q[_ev_r][i];
  }
  _ev_r = (_ev_r + 1) % 64;
  return 1;
}
@end

@interface OrenUICocoaRGBAView : NSView
@property(nonatomic, weak) OrenUICocoaWindowState* state;
@end

@implementation OrenUICocoaRGBAView
- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea* ta in [self trackingAreas]) {
    [self removeTrackingArea:ta];
  }
  NSTrackingAreaOptions opts = NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
  NSTrackingArea* area = [[NSTrackingArea alloc] initWithRect:self.bounds options:opts owner:self userInfo:nil];
  [self addTrackingArea:area];
}

static int64_t orenui__mods_from_event(NSEvent* ev) {
  NSEventModifierFlags f = [ev modifierFlags];
  int64_t mods = 0;
  if (f & NSEventModifierFlagShift) mods |= 1;
  if (f & NSEventModifierFlagControl) mods |= 2;
  if (f & NSEventModifierFlagOption) mods |= 4;
  if (f & NSEventModifierFlagCommand) mods |= 8;
  return mods;
}

- (void)mouseMoved:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  int64_t mods = orenui__mods_from_event(event);
  [st evPushType:ORENUI_EV_MOUSE_MOVE a0:(int64_t)(p.x + 0.5) a1:(int64_t)(p.y + 0.5) a2:mods a3:0];
}

- (void)mouseDown:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  int64_t mods = orenui__mods_from_event(event);
  [st evPushType:ORENUI_EV_MOUSE_DOWN a0:1 a1:(int64_t)(p.x + 0.5) a2:(int64_t)(p.y + 0.5) a3:mods];
}

- (void)mouseUp:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  int64_t mods = orenui__mods_from_event(event);
  [st evPushType:ORENUI_EV_MOUSE_UP a0:1 a1:(int64_t)(p.x + 0.5) a2:(int64_t)(p.y + 0.5) a3:mods];
}

- (void)rightMouseDown:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  int64_t mods = orenui__mods_from_event(event);
  [st evPushType:ORENUI_EV_MOUSE_DOWN a0:3 a1:(int64_t)(p.x + 0.5) a2:(int64_t)(p.y + 0.5) a3:mods];
}

- (void)rightMouseUp:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  int64_t mods = orenui__mods_from_event(event);
  [st evPushType:ORENUI_EV_MOUSE_UP a0:3 a1:(int64_t)(p.x + 0.5) a2:(int64_t)(p.y + 0.5) a3:mods];
}

- (void)keyDown:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  int64_t mods = orenui__mods_from_event(event);
  // Raw keyCode is hardware-dependent; keep as platform-raw for v0.
  int64_t key = (int64_t)[event keyCode];
  [st evPushType:ORENUI_EV_KEY_DOWN a0:key a1:mods a2:0 a3:0];

  NSString* s = [event characters];
  if (s && [s length] > 0) {
    unichar c0 = [s characterAtIndex:0];
    // Best-effort: UTF-16 code unit, no surrogate pairing in v0.
    if (c0 != 0) {
      [st evPushType:ORENUI_EV_TEXT a0:(int64_t)c0 a1:mods a2:0 a3:0];
    }
  }
}

- (void)keyUp:(NSEvent*)event {
  OrenUICocoaWindowState* st = self.state;
  if (!st) return;
  int64_t mods = orenui__mods_from_event(event);
  int64_t key = (int64_t)[event keyCode];
  [st evPushType:ORENUI_EV_KEY_UP a0:key a1:mods a2:0 a3:0];
}

- (BOOL)isFlipped {
  // Match Oren's UI coordinate system (0,0 at top-left).
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;

  OrenUICocoaWindowState* st = self.state;
  if (!st) {
    return;
  }

  pthread_mutex_lock([st rgbaMuPtr]);
  if (!st.rgba || st.w <= 0 || st.h <= 0 || st.stride <= 0) {
    pthread_mutex_unlock([st rgbaMuPtr]);
    return;
  }
  const int32_t w = st.w;
  const int32_t h = st.h;
  const int32_t stride = st.stride;
  const size_t len = (size_t)h * (size_t)stride;
  uint8_t* bytes = st.rgba;

  CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
  if (!ctx) {
    pthread_mutex_unlock([st rgbaMuPtr]);
    return;
  }

  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  if (!cs) {
    pthread_mutex_unlock([st rgbaMuPtr]);
    return;
  }

  // We store BGRA premultiplied-first (little-endian), matching the common macOS
  // bitmap layout for CoreGraphics.
  const CGBitmapInfo bi = (CGBitmapInfo)(kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
  CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, bytes, len, NULL);
  if (!prov) {
    CGColorSpaceRelease(cs);
    pthread_mutex_unlock([st rgbaMuPtr]);
    return;
  }
  CGImageRef img = CGImageCreate((size_t)w,
                                (size_t)h,
                                8,
                                32,
                                (size_t)stride,
                                cs,
                                bi,
                                prov,
                                NULL,
                                false,
                                kCGRenderingIntentDefault);
  if (!img) {
    CGDataProviderRelease(prov);
    CGColorSpaceRelease(cs);
    pthread_mutex_unlock([st rgbaMuPtr]);
    return;
  }

  // `isFlipped` makes our view coordinate system top-left origin, which matches how
  // `std:ui/raster` addresses pixels. With a flipped NSView, CGContextDrawImage uses
  // that coordinate system directly (no extra Y-flip needed).
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), img);

  CGImageRelease(img);
  CGDataProviderRelease(prov);
  CGColorSpaceRelease(cs);
  pthread_mutex_unlock([st rgbaMuPtr]);
}
@end

static NSMutableDictionary<NSNumber*, OrenUICocoaWindowState*>* g_windows;
static int32_t g_next_win_id = 1;

static OrenUICocoaWindowState* orenui__get(int32_t win_id) {
  if (!g_windows) {
    g_windows = [[NSMutableDictionary alloc] init];
  }
  return [g_windows objectForKey:@(win_id)];
}

static void orenui__drop(int32_t win_id) {
  if (!g_windows) {
    return;
  }
  [g_windows removeObjectForKey:@(win_id)];
}

static bool orenui__require_main_thread(void) {
  // AppKit is not thread-safe; keep the v0 shim strict to avoid heisenbugs/crashes.
  return [NSThread isMainThread] ? true : false;
}

int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h) {
  if (!orenui__require_main_thread()) {
    return -16;
  }
  orenui__ensure_app();

  if (w <= 0 || h <= 0) {
    return -4;
  }

  NSString* title = @"OrenUI";
  if (title_utf8 && title_utf8[0] != 0) {
    title = [NSString stringWithUTF8String:title_utf8];
  }

  NSRect r = NSMakeRect(100, 100, (CGFloat)w, (CGFloat)h);
  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
  NSWindow* win = [[NSWindow alloc] initWithContentRect:r styleMask:style backing:NSBackingStoreBuffered defer:NO];
  if (!win) {
    return -8;
  }

  OrenUICocoaWindowState* st = [[OrenUICocoaWindowState alloc] init];
  st.window = win;
  st.shouldClose = NO;
  st.closeReported = NO;
  st.lastReportedW = w;
  st.lastReportedH = h;
  st.rgba = NULL;
  st.cap = 0;
  st.w = w;
  st.h = h;
  st.stride = w * 4;

  OrenUICocoaRGBAView* view = [[OrenUICocoaRGBAView alloc] initWithFrame:r];
  view.state = st;
  st.view = view;

  [win setTitle:title];
  [win setDelegate:st];
  [win setContentView:view];
  [win makeFirstResponder:view];
  [win makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];

  int32_t win_id = g_next_win_id++;
  if (!g_windows) {
    g_windows = [[NSMutableDictionary alloc] init];
  }
  [g_windows setObject:st forKey:@(win_id)];
  return win_id;
}

void orenui_close_window(int32_t win_id) {
  if (!orenui__require_main_thread()) {
    return;
  }
  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st) {
    return;
  }
  if (st.window) {
    [st.window close];
  }
  // `st` owns its rgba buffer and frees it in -dealloc; keep close idempotent.
  orenui__drop(win_id);
}

int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, int64_t rgba_ptr, int32_t stride) {
  if (!orenui__require_main_thread()) {
    return -16;
  }
  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st || !st.window || !st.view) {
    return -4;
  }
  if (w <= 0 || h <= 0 || stride <= 0 || rgba_ptr == 0) {
    return -4;
  }

  size_t need = (size_t)h * (size_t)stride;
  if (need == 0) {
    return -4;
  }

  // Protect the backing buffer from concurrent reads in drawRect.
  pthread_mutex_lock([st rgbaMuPtr]);
  if (!st.rgba || st.cap < need) {
    uint8_t* p = (uint8_t*)realloc(st.rgba, need);
    if (!p) {
      pthread_mutex_unlock([st rgbaMuPtr]);
      return -8;
    }
    st.rgba = p;
    st.cap = need;
  }

  // Convert RGBA (unassociated alpha) -> BGRA (premultiplied-first).
  const uint8_t* src = (const uint8_t*)(uintptr_t)rgba_ptr;
  uint8_t* dst = st.rgba;
  // stride is bytes per row for both src and dst.
  for (int32_t y = 0; y < h; y++) {
    const uint8_t* srow = src + (size_t)y * (size_t)stride;
    uint8_t* drow = dst + (size_t)y * (size_t)stride;
    for (int32_t x = 0; x < w; x++) {
      size_t off = (size_t)x * 4u;
      uint32_t r = srow[off + 0];
      uint32_t g = srow[off + 1];
      uint32_t b = srow[off + 2];
      uint32_t a = srow[off + 3];
      // Premultiply into 0..255 with rounding.
      uint32_t pr = (r * a + 127u) / 255u;
      uint32_t pg = (g * a + 127u) / 255u;
      uint32_t pb = (b * a + 127u) / 255u;
      drow[off + 0] = (uint8_t)pb; // B
      drow[off + 1] = (uint8_t)pg; // G
      drow[off + 2] = (uint8_t)pr; // R
      drow[off + 3] = (uint8_t)a;  // A
    }
  }
  st.w = w;
  st.h = h;
  st.stride = stride;
  pthread_mutex_unlock([st rgbaMuPtr]);

  // Trigger a redraw; actual painting happens in drawRect on the same thread.
  [st.view setNeedsDisplay:YES];
  return 0;
}

int32_t orenui_pump(int32_t win_id, int32_t timeout_ms) {
  if (!orenui__require_main_thread()) {
    return 1;
  }
  orenui__ensure_app();

  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st) {
    // Treat unknown window id as “done”.
    return 1;
  }
  if (st.shouldClose) {
    return 1;
  }

  NSDate* until = [NSDate dateWithTimeIntervalSinceNow:0];
  if (timeout_ms > 0) {
    until = [NSDate dateWithTimeIntervalSinceNow:(double)timeout_ms / 1000.0];
  }

  for (;;) {
    NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                    untilDate:until
                                       inMode:NSDefaultRunLoopMode
                                      dequeue:YES];
    if (!ev) {
      break;
    }
    [NSApp sendEvent:ev];
    [NSApp updateWindows];
    if (st.shouldClose) {
      break;
    }
    // After the first event, switch to poll mode so we don't block after handling input.
    until = [NSDate dateWithTimeIntervalSinceNow:0];
  }

  // Ensure pending draws are performed within the pump boundary (keeps v0 deterministic enough
  // for smoke scripts: present -> pump -> draw).
  [st.view displayIfNeeded];
  return st.shouldClose ? 1 : 0;
}

int32_t orenui_poll_event(int32_t win_id, int32_t timeout_ms, int64_t out5_i64_ptr) {
  if (!orenui__require_main_thread()) {
    return -16;
  }
  if (out5_i64_ptr == 0) {
    return -4;
  }
  orenui__ensure_app();

  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st || !st.window || !st.view) {
    return -4;
  }

  int64_t* out = (int64_t*)(uintptr_t)out5_i64_ptr;

  // First: any already-queued input events.
  if ([st evPopOut:out]) {
    return 1;
  }

  // Pump once to ingest pending OS events, bounded by timeout.
  (void)orenui_pump(win_id, timeout_ms);
  if ([st evPopOut:out]) {
    return 1;
  }

  if (st.shouldClose && !st.closeReported) {
    st.closeReported = YES;
    out[0] = ORENUI_EV_CLOSE;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;
    out[4] = 0;
    return 1;
  }

  // Best-effort resize report (content view size).
  NSRect b = [st.view bounds];
  int32_t cw = (int32_t)(b.size.width + 0.5);
  int32_t ch = (int32_t)(b.size.height + 0.5);
  if (cw > 0 && ch > 0 && (cw != st.lastReportedW || ch != st.lastReportedH)) {
    st.lastReportedW = cw;
    st.lastReportedH = ch;
    out[0] = ORENUI_EV_RESIZE;
    out[1] = (int64_t)cw;
    out[2] = (int64_t)ch;
    out[3] = 0;
    out[4] = 0;
    return 1;
  }

  // No event (v0 only reports close/resize).
  return 0;
}
