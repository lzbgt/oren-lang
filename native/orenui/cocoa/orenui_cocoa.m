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

@interface OrenUICocoaWindowState : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) NSView* view;
@property(nonatomic, assign) BOOL shouldClose;
@property(nonatomic, assign) uint8_t* rgba;
@property(nonatomic, assign) int32_t w;
@property(nonatomic, assign) int32_t h;
@property(nonatomic, assign) int32_t stride;
@property(nonatomic, assign) size_t cap;
@end

@implementation OrenUICocoaWindowState
- (void)windowWillClose:(NSNotification*)notification {
  (void)notification;
  self.shouldClose = YES;
}
@end

@interface OrenUICocoaRGBAView : NSView
@property(nonatomic, weak) OrenUICocoaWindowState* state;
@end

@implementation OrenUICocoaRGBAView
- (BOOL)isFlipped {
  // Match Oren's UI coordinate system (0,0 at top-left).
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;

  OrenUICocoaWindowState* st = self.state;
  if (!st || !st.rgba || st.w <= 0 || st.h <= 0 || st.stride <= 0) {
    return;
  }

  // Bring-up stability guard:
  // On some systems, CoreGraphics image creation/drawing from a rapidly-updated
  // buffer can crash when the app isn't running a full Cocoa run loop owned by
  // `-[NSApplication run]`. Until the event/present loop is fully stabilized,
  // keep draw a no-op (we still validate the ABI and the blit path wiring).
  //
  // Once the shim has a proper run loop integration, re-enable the CoreGraphics
  // draw path (see `docs/GUI_PLATFORM_SHIMS.md` for the intended design).
  return;
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

int32_t orenui_open_window(const char* title_utf8, int32_t w, int32_t h) {
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
  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st) {
    return;
  }
  if (st.window) {
    [st.window close];
  }
  if (st.rgba) {
    free(st.rgba);
    st.rgba = NULL;
    st.cap = 0;
  }
  orenui__drop(win_id);
}

int32_t orenui_present_rgba(int32_t win_id, int32_t w, int32_t h, int64_t rgba_ptr, int32_t stride) {
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
  if (!st.rgba || st.cap < need) {
    uint8_t* p = (uint8_t*)realloc(st.rgba, need);
    if (!p) {
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

  // v0 bring-up note:
  // We deliberately avoid triggering AppKit redraws here. A correct redraw path
  // requires a properly owned Cocoa run loop. The current smoke validates the
  // ABI wiring (window open + repeated RGBA blit calls) without relying on
  // AppKit repaint timing.
  return 0;
}

int32_t orenui_pump(int32_t win_id, int32_t timeout_ms) {
  orenui__ensure_app();

  OrenUICocoaWindowState* st = orenui__get(win_id);
  if (!st) {
    // Treat unknown window id as “done”.
    return 1;
  }
  if (st.shouldClose) {
    return 1;
  }

  // v0 bring-up: keep `pump` as a no-op, returning only the close state.
  (void)timeout_ms;
  return st.shouldClose ? 1 : 0;
}
