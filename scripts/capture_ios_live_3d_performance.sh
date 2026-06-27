#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/ios}"
TMP_DIR="${OREN_IOS_LIVE_TMP_DIR:-build/tmp/ios_live_3d_capture}"
RESULT_DIR="${OREN_IOS_LIVE_RESULT_DIR:-build/ios-live-3d}"
LOG_DIR="build/logs"
DEVICE="${OREN_IOS_LIVE_DEVICE:-blu-ip}"
BUNDLE_ID="${OREN_IOS_LIVE_BUNDLE_ID:-cn.hubstack.orenlive3d}"
APP_NAME="${OREN_IOS_LIVE_APP_NAME:-OrenLive3D}"
FRAME_COUNT="${OREN_IOS_LIVE_FRAME_COUNT:-120}"
INSTALL="${OREN_IOS_LIVE_INSTALL:-0}"
SNAPSHOT="${OREN_IOS_LIVE_SNAPSHOT:-1}"
TEAM_ID="${OREN_IOS_LIVE_TEAM_ID:-}"
SIGN_IDENTITY="${OREN_IOS_LIVE_SIGN_IDENTITY:-}"
PROFILE="${OREN_IOS_LIVE_PROVISIONING_PROFILE:-}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-13.0}"

mkdir -p "$TMP_DIR" "$RESULT_DIR" "$LOG_DIR"

case "$FRAME_COUNT" in
  ''|*[!0-9]*)
    echo "ERROR: OREN_IOS_LIVE_FRAME_COUNT must be a positive integer" >&2
    exit 2
    ;;
esac
if [[ "$FRAME_COUNT" -le 0 || "$FRAME_COUNT" -ge 100000 ]]; then
  echo "ERROR: OREN_IOS_LIVE_FRAME_COUNT must be in 1..99999" >&2
  exit 2
fi

DEVICE_JSON="$RESULT_DIR/devicectl-devices.json"
DEVICE_LOG="$RESULT_DIR/devicectl-devices.log"
SIGNING_PREFLIGHT_JSON="$RESULT_DIR/signing-preflight.json"
xcrun devicectl list devices --json-output "$DEVICE_JSON" --log-output "$DEVICE_LOG" >/dev/null 2>&1 || true
xcrun xctrace list devices > "$RESULT_DIR/xctrace-devices.txt" 2>&1 || true

find_profile() {
  python3 - "$BUNDLE_ID" "$DEVICE" "$DEVICE_JSON" "$PROFILE" "$SIGNING_PREFLIGHT_JSON" <<'PY'
import json
import pathlib
import plistlib
import subprocess
import sys

bundle, requested_device, device_json, requested_profile, out_json = sys.argv[1:6]

def load_device():
    try:
        devices = json.loads(pathlib.Path(device_json).read_text()).get("result", {}).get("devices", [])
    except Exception:
        devices = []
    for dev in devices:
        props = dev.get("deviceProperties", {})
        hw = dev.get("hardwareProperties", {})
        names = {
            dev.get("identifier", ""),
            props.get("name", ""),
            hw.get("udid", ""),
            *(dev.get("connectionProperties", {}).get("potentialHostnames", []) or []),
        }
        if requested_device in names:
            return {
                "identifier": dev.get("identifier", ""),
                "name": props.get("name", ""),
                "udid": hw.get("udid", ""),
                "productType": hw.get("productType", ""),
                "osVersionNumber": props.get("osVersionNumber", ""),
                "pairingState": dev.get("connectionProperties", {}).get("pairingState", ""),
                "ddiServicesAvailable": props.get("ddiServicesAvailable", None),
                "developerModeStatus": props.get("developerModeStatus", ""),
            }
    return {}

def profile_paths():
    if requested_profile:
        return [pathlib.Path(requested_profile)]
    roots = [
        pathlib.Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ]
    paths = []
    for root in roots:
        if not root.is_dir():
            continue
        paths.extend(sorted(root.glob("*.mobileprovision")))
        paths.extend(sorted(root.glob("*.provisionprofile")))
    return paths

def decode_profile(path):
    data = subprocess.check_output(["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL)
    plist = plistlib.loads(data)
    ent = plist.get("Entitlements", {})
    app_id = ent.get("application-identifier") or ent.get("com.apple.application-identifier") or ""
    teams = plist.get("TeamIdentifier", [])
    suffix = app_id.split(".", 1)[1] if "." in app_id else ""
    return {
        "path": str(path),
        "name": plist.get("Name", ""),
        "team": teams[0] if teams else "",
        "app_id": app_id,
        "suffix": suffix,
        "get_task_allow": bool(ent.get("get-task-allow", False)),
        "provisions_all_devices": bool(plist.get("ProvisionsAllDevices", False)),
        "provisioned_devices": plist.get("ProvisionedDevices", []) or [],
        "expiration": plist.get("ExpirationDate").isoformat() if plist.get("ExpirationDate") else "",
    }

def matches_bundle(profile):
    suffix = profile["suffix"]
    return suffix == "*" or suffix == bundle or (suffix.endswith(".*") and bundle.startswith(suffix[:-1]))

def match_score(profile):
    suffix = profile["suffix"]
    if suffix == bundle:
        return 3
    if suffix.endswith(".*") and bundle.startswith(suffix[:-1]):
        return 2
    if suffix == "*":
        return 1
    return 0

device = load_device()
profiles = []
for path in profile_paths():
    try:
        profile = decode_profile(path)
    except Exception:
        continue
    if matches_bundle(profile):
        profile["match_score"] = match_score(profile)
        profiles.append(profile)

device_udid = device.get("udid", "")

def device_allowed_by(profile):
    explicit_device_match = bool(device_udid and device_udid in profile["provisioned_devices"])
    development_all_devices = profile["provisions_all_devices"] and profile["get_task_allow"]
    return explicit_device_match or development_all_devices

profiles.sort(key=lambda p: (device_allowed_by(p), p["get_task_allow"], p["match_score"], p["expiration"], p["name"]), reverse=True)
selected = profiles[0] if profiles else {}
device_allowed = False
device_reason = "no matching profile"
if selected:
    explicit_device_match = bool(device_udid and device_udid in selected["provisioned_devices"])
    development_all_devices = selected["provisions_all_devices"] and selected["get_task_allow"]
    device_allowed = explicit_device_match or development_all_devices
    if explicit_device_match:
        device_reason = "device udid is listed in ProvisionedDevices"
    elif development_all_devices:
        device_reason = "profile provisions all devices and allows development debugging"
    elif selected["provisions_all_devices"]:
        device_reason = "profile provisions all devices but does not allow development debugging"
    else:
        device_reason = "target device udid is not listed in profile"

report = {
    "requested_bundle_id": bundle,
    "requested_device": requested_device,
    "device": device,
    "profile": {k: v for k, v in selected.items() if k != "provisioned_devices"},
    "profile_device_count": len(selected.get("provisioned_devices", [])) if selected else 0,
    "device_allowed_by_profile": device_allowed,
    "device_allowed_reason": device_reason,
    "matching_profile_count": len(profiles),
}
pathlib.Path(out_json).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if not selected:
    raise SystemExit(1)
print(selected["path"])
print(selected["team"])
print(selected["app_id"])
print("true" if selected["get_task_allow"] else "false")
print("true" if device_allowed else "false")
PY
}

if [[ -z "$PROFILE" || -z "$TEAM_ID" ]]; then
  profile_info="$(find_profile || true)"
  if [[ -n "$profile_info" ]]; then
    PROFILE="${PROFILE:-$(printf '%s\n' "$profile_info" | sed -n '1p')}"
    TEAM_ID="${TEAM_ID:-$(printf '%s\n' "$profile_info" | sed -n '2p')}"
    PROFILE_DEVICE_ALLOWED="$(printf '%s\n' "$profile_info" | sed -n '5p')"
  else
    PROFILE_DEVICE_ALLOWED="false"
  fi
else
  profile_info="$(find_profile || true)"
  PROFILE_DEVICE_ALLOWED="$(printf '%s\n' "$profile_info" | sed -n '5p')"
fi

if [[ "$INSTALL" == "1" ]]; then
  if [[ -z "$PROFILE" || -z "$TEAM_ID" ]]; then
    echo "ERROR: OREN_IOS_LIVE_INSTALL=1 requires a provisioning profile matching $BUNDLE_ID" >&2
    echo "Signing preflight: $SIGNING_PREFLIGHT_JSON" >&2
    exit 2
  fi
  if [[ "$PROFILE_DEVICE_ALLOWED" != "true" ]]; then
    echo "ERROR: provisioning profile is not installable for target device $DEVICE for $BUNDLE_ID" >&2
    echo "Signing preflight: $SIGNING_PREFLIGHT_JSON" >&2
    exit 2
  fi
fi

if [[ ! -x ./oren ]]; then
  make oren > "$LOG_DIR/make_oren_for_ios_live_3d.log" 2>&1
fi

./scripts/build_libavm_ios.sh > "$LOG_DIR/build_libavm_ios_live_3d.log" 2>&1
test -f "$OUT_ROOT/iphoneos-arm64/libavm.a"
test -f "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a"
test -f "$OUT_ROOT/include/OrenAVMKit/OrenAVMKit.h"

cat > "$TMP_DIR/live3d.oren" <<OREN
import events "std:avm/events"
import raw "std:buffer/raw"
import ui_avm "std:ui/avm"

fn store_u32(out, off, v) {
    raw._store_u8_buf_unchecked_direct(out, off + 0, v % 256)
    raw._store_u8_buf_unchecked_direct(out, off + 1, (v / 256) % 256)
    raw._store_u8_buf_unchecked_direct(out, off + 2, (v / 65536) % 256)
    raw._store_u8_buf_unchecked_direct(out, off + 3, (v / 16777216) % 256)
    return 0
}

fn store_i32(out, off, v) {
    var u = v
    if u < 0 { u = u + 4294967296 }
    return store_u32(out, off, u)
}

fn store_xyz(out, off, p) {
    store_i32(out, off + 0, p[0])
    store_i32(out, off + 4, p[1])
    store_i32(out, off + 8, p[2])
    return 0
}

fn store_tri_rgba(out, ti, a, b, c, r, g, bb) {
    var off = ti * 40
    store_xyz(out, off + 0, a)
    store_xyz(out, off + 12, b)
    store_xyz(out, off + 24, c)
    raw._store_u8_buf_unchecked_direct(out, off + 36, r)
    raw._store_u8_buf_unchecked_direct(out, off + 37, g)
    raw._store_u8_buf_unchecked_direct(out, off + 38, bb)
    raw._store_u8_buf_unchecked_direct(out, off + 39, 255)
    return 0
}

fn rot_yaw(seq) {
    var phase = ((seq / 2) + 9) % 32
    if phase == 0 { return [1000, 0] }
    if phase == 1 { return [981, 195] }
    if phase == 2 { return [924, 383] }
    if phase == 3 { return [831, 556] }
    if phase == 4 { return [707, 707] }
    if phase == 5 { return [556, 831] }
    if phase == 6 { return [383, 924] }
    if phase == 7 { return [195, 981] }
    if phase == 8 { return [0, 1000] }
    if phase == 9 { return [-195, 981] }
    if phase == 10 { return [-383, 924] }
    if phase == 11 { return [-556, 831] }
    if phase == 12 { return [-707, 707] }
    if phase == 13 { return [-831, 556] }
    if phase == 14 { return [-924, 383] }
    if phase == 15 { return [-981, 195] }
    if phase == 16 { return [-1000, 0] }
    if phase == 17 { return [-981, -195] }
    if phase == 18 { return [-924, -383] }
    if phase == 19 { return [-831, -556] }
    if phase == 20 { return [-707, -707] }
    if phase == 21 { return [-556, -831] }
    if phase == 22 { return [-383, -924] }
    if phase == 23 { return [-195, -981] }
    if phase == 24 { return [0, -1000] }
    if phase == 25 { return [195, -981] }
    if phase == 26 { return [383, -924] }
    if phase == 27 { return [556, -831] }
    if phase == 28 { return [707, -707] }
    if phase == 29 { return [831, -556] }
    if phase == 30 { return [924, -383] }
    return [981, -195]
}

fn cube_vertex(seq, x, y, z) {
    var r = rotate_dir(seq, x, y, z)
    return [32 + (r[0] * 15) / 1000, 32 - (r[1] * 15) / 1000, 24 + (r[2] * 15) / 1000]
}

fn rotate_dir(seq, x, y, z) {
    var yaw = rot_yaw(seq)
    var cy = yaw[0]
    var sy = yaw[1]
    var x1 = (x * cy + z * sy) / 1000
    var z1 = (0 - x * sy + z * cy) / 1000
    var y1 = y
    var pitch_c = 924
    var pitch_s = 383
    var y2 = (y1 * pitch_c - z1 * pitch_s) / 1000
    var z2 = (y1 * pitch_s + z1 * pitch_c) / 1000
    return [x1, y2, z2]
}

fn edge_line(a, b) {
    return {"op": "stroke_line", "x1": a[0], "y1": a[1], "x2": b[0], "y2": b[1], "width": 1, "color": "#0f172a"}
}

fn face_rgb(seq, nx, ny, nz) {
    var n = rotate_dir(seq, nx, ny, nz)
    var dot = (n[0] * -250 + n[1] * -450 + n[2] * 850) / 1000
    if dot < 0 { dot = 0 }
    var shade = 80 + dot / 8
    if shade > 220 { shade = 220 }
    return [20 + shade / 7, 76 + shade / 2, 112 + shade / 2]
}

fn store_face(out, ti, a, b, c, d, color) {
    store_tri_rgba(out, ti, a, b, c, color[0], color[1], color[2])
    store_tri_rgba(out, ti + 1, a, c, d, color[0], color[1], color[2])
    return 0
}

fn cube_points(seq) {
    return [
        cube_vertex(seq, -1000, -1000, -1000),
        cube_vertex(seq, 1000, -1000, -1000),
        cube_vertex(seq, 1000, 1000, -1000),
        cube_vertex(seq, -1000, 1000, -1000),
        cube_vertex(seq, -1000, -1000, 1000),
        cube_vertex(seq, 1000, -1000, 1000),
        cube_vertex(seq, 1000, 1000, 1000),
        cube_vertex(seq, -1000, 1000, 1000)
    ]
}

fn cube_mesh(seq) {
    var p = cube_points(seq)
    var out = raw.u8_new_uninit(480)
    store_face(out, 0, p[4], p[5], p[6], p[7], face_rgb(seq, 0, 0, 1000))
    store_face(out, 2, p[1], p[0], p[3], p[2], face_rgb(seq, 0, 0, -1000))
    store_face(out, 4, p[1], p[2], p[6], p[5], face_rgb(seq, 1000, 0, 0))
    store_face(out, 6, p[0], p[4], p[7], p[3], face_rgb(seq, -1000, 0, 0))
    store_face(out, 8, p[0], p[1], p[5], p[4], face_rgb(seq, 0, -1000, 0))
    store_face(out, 10, p[3], p[7], p[6], p[2], face_rgb(seq, 0, 1000, 0))
    return out
}

fn cube_frame_commands(seq) {
    var p = cube_points(seq)
    return [
        {"op": "fill_rect", "x": 0, "y": 0, "w": 64, "h": 64, "color": "#f8fafc"},
        {"op": "fill_rect", "x": 17, "y": 49, "w": 30, "h": 3, "color": "#cbd5e1"},
        {"op": "push_camera_ortho", "near_z": 0, "far_z": 64},
        {"op": "mesh3d_rgba", "id": 1, "triangles": cube_mesh(seq)},
        {"op": "draw_mesh3d", "id": 1},
        {"op": "destroy_mesh3d", "id": 1},
        {"op": "pop_camera"},
        edge_line(p[4], p[5]), edge_line(p[5], p[6]), edge_line(p[6], p[7]), edge_line(p[7], p[4]),
        edge_line(p[0], p[1]), edge_line(p[1], p[2]), edge_line(p[2], p[3]), edge_line(p[3], p[0]),
        edge_line(p[0], p[4]), edge_line(p[1], p[5]), edge_line(p[2], p[6]), edge_line(p[3], p[7])
    ]
}

fn present_live_frame(seq) {
    var cmds = cube_frame_commands(seq)
    var r = ui_avm.present_frame(cmds, 64, 64, {
        "strict_bounds": true,
        "scale_milli": 3000,
        "sequence": seq,
        "drawable_w": 192,
        "drawable_h": 192,
        "target_hz_milli": 120000
    })
    return r
}

fn main() {
    var first = present_live_frame(0)
    if oren_is_err(first) {
        print(oren_err_msg(first))
        oren_exit(2)
    }
    var frame_limit = $FRAME_COUNT
    var frames = 0
    while frames < frame_limit {
        var ready = events.select([{"kind": "ui", "id": "frame"}], 1000)
        if oren_is_err(ready) {
            print(oren_err_msg(ready))
            oren_exit(3)
        }
        if ready != nil && ready["event"]["kind"] == "frame_tick" {
            var ev = ready["event"]
            var r = present_live_frame(ev["sequence"])
            if oren_is_err(r) {
                print(oren_err_msg(r))
                oren_exit(4)
            }
            frames = frames + 1
        }
    }
    print("live3d:frames-ok")
    oren_exit(0)
}

main()
OREN

OBC_OUT="$TMP_DIR/live3d.obc"
OBC_HEADER="$TMP_DIR/live3d_obc.h"
./oren build "$TMP_DIR/live3d.oren" --backend bytecode -o "$OBC_OUT" > "$LOG_DIR/ios_live_3d_obc_build.log" 2>&1

python3 - "$OBC_OUT" "$OBC_HEADER" <<'PY'
import pathlib
import sys
data = pathlib.Path(sys.argv[1]).read_bytes()
chunks = []
for i in range(0, len(data), 12):
    chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
pathlib.Path(sys.argv[2]).write_text(
    "#include <stddef.h>\n"
    "static const unsigned char kLive3DObc[] = {\n"
    + ",\n".join("    " + chunk for chunk in chunks)
    + "\n};\n"
    + f"static const size_t kLive3DObcLen = {len(data)}u;\n",
    encoding="utf-8",
)
PY

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'\"' '/Apple Development:/ {print $2; exit}')"
fi

APP_DIR="$TMP_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

cat > "$APP_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>$MIN_IOS_VERSION</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
  </dict>
</dict>
</plist>
PLIST

cat > "$TMP_DIR/main.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OrenAVMKit/OrenAVMKit.h>
#include "live3d_obc.h"

@interface OrenLive3DAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@property(nonatomic, strong) OrenAVMRuntime* runtime;
@property(nonatomic, strong) OrenAVMMetalView* metalView;
@property(nonatomic) BOOL runtimeFinished;
@property(nonatomic) NSInteger runtimeStatus;
@property(nonatomic) NSInteger runtimeExitCode;
@property(nonatomic, copy) NSString* runtimeErrorMessage;
@end

@implementation OrenLive3DAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    (void)application;
    (void)launchOptions;
    NSError* error = nil;
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
    cfg.gasLimit = 0;
    self.runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController* controller = [[UIViewController alloc] init];
    UIView* rootView = [[UIView alloc] initWithFrame:bounds];
    rootView.backgroundColor = UIColor.whiteColor;
    self.metalView = [[OrenAVMMetalView alloc] initWithRuntime:self.runtime];
    CGFloat side = MIN(MIN(bounds.size.width, bounds.size.height), 240.0);
    self.metalView.frame = CGRectMake((bounds.size.width - side) * 0.5,
                                      MAX(32.0, (bounds.size.height - side) * 0.22),
                                      side,
                                      side);
    self.metalView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                      UIViewAutoresizingFlexibleRightMargin |
                                      UIViewAutoresizingFlexibleTopMargin |
                                      UIViewAutoresizingFlexibleBottomMargin;
    self.metalView.targetHzMilli = 120000;
    [rootView addSubview:self.metalView];
    controller.view = rootView;
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    [self.metalView publishScreenStateWithError:&error];
    [self.metalView sendMediaEventWithError:&error];
    NSData* obc = [NSData dataWithBytes:kLive3DObc length:kLive3DObcLen];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError* runError = nil;
        OrenAVMRunResult* result = [self.runtime runOBCData:obc error:&runError];
        @synchronized (self) {
            self.runtimeFinished = YES;
            self.runtimeStatus = result ? result.status : -1;
            self.runtimeExitCode = result ? result.exitCode : -1;
            self.runtimeErrorMessage = runError.localizedDescription ?: @"";
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self runCapture];
    });
    return YES;
}

- (void)runCapture {
    NSError* error = nil;
    NSUInteger frames = 120;
    NSString* raw = [NSProcessInfo.processInfo.environment objectForKey:@"OREN_IOS_LIVE_FRAME_COUNT"];
    if (raw.length > 0) {
        NSInteger parsed = raw.integerValue;
        if (parsed > 0 && parsed < 100000) frames = (NSUInteger)parsed;
    }
    uint64_t minNs = UINT64_MAX;
    uint64_t maxNs = 0;
    uint64_t sumNs = 0;
    uint32_t overBudget = 0;
    for (NSUInteger wait = 0; wait < 200 && !self.metalView.hasValidFrameData; wait++) {
        [self.metalView reloadFrameWithError:nil];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    if (!self.metalView.hasValidFrameData) {
        fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR frame_missing_after_start\n");
        exit(3);
    }
    for (NSUInteger i = 0; i < frames; i++) {
        @autoreleasepool {
            [self.metalView draw];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
            [self.metalView reloadFrameWithError:nil];
            if (![self.metalView prepareFrameResourcesWithError:&error]) {
                fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR prepare_failed frame=%lu message=%s\n",
                        (unsigned long)i,
                        error.localizedDescription.UTF8String ?: "");
                exit(4);
            }
            uint64_t ns = self.metalView.lastFrameCPUNs;
            if (ns < minNs) minNs = ns;
            if (ns > maxNs) maxNs = ns;
            sumNs += ns;
            if (self.metalView.lastFrameOverBudget) overBudget++;
        }
    }
    [self.metalView draw];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (![self writeSnapshotWithError:&error]) {
        fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR snapshot_failed message=%s\n",
                error.localizedDescription.UTF8String ?: "");
        exit(6);
    }
    for (NSUInteger wait = 0; wait < 500; wait++) {
        @synchronized (self) {
            if (self.runtimeFinished) break;
        }
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    @synchronized (self) {
        if (!self.runtimeFinished) {
            [self.runtime requestCancelWithError:nil];
            fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR run_timeout\n");
            exit(5);
        }
        if (self.runtimeStatus != 0 || self.runtimeExitCode != 0) {
            fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR run_failed status=%ld exit=%ld message=%s\n",
                    (long)self.runtimeStatus,
                    (long)self.runtimeExitCode,
                    self.runtimeErrorMessage.UTF8String ?: "");
            exit(2);
        }
    }
    uint64_t avgNs = frames > 0 ? sumNs / frames : 0;
    printf("OREN_IOS_LIVE_3D_METRICS frames=%lu avg_cpu_ns=%llu min_cpu_ns=%llu max_cpu_ns=%llu target_budget_ns=%llu over_budget=%u vertices=%u text_runs=%u image_runs=%u rendered=%llu\n",
           (unsigned long)frames,
           (unsigned long long)avgNs,
           (unsigned long long)(minNs == UINT64_MAX ? 0 : minNs),
           (unsigned long long)maxNs,
           (unsigned long long)self.metalView.lastFrameTargetBudgetNs,
           overBudget,
           self.metalView.lastFrameVertexCount,
           self.metalView.lastFrameTextRunCount,
           self.metalView.lastFrameImageRunCount,
           (unsigned long long)self.metalView.renderedFrameCount);
    fflush(stdout);
    exit(0);
}

- (BOOL)writeSnapshotWithError:(NSError**)error {
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    CGSize size = CGSizeMake(192.0, 192.0);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage* image = [renderer imageWithActions:^(UIGraphicsImageRendererContext* context) {
        BOOL captured = [self.metalView drawViewHierarchyInRect:CGRectMake(0, 0, size.width, size.height) afterScreenUpdates:YES];
        if (!captured) {
            CGContextSaveGState(context.CGContext);
            CGFloat sx = size.width / MAX(self.metalView.bounds.size.width, 1.0);
            CGFloat sy = size.height / MAX(self.metalView.bounds.size.height, 1.0);
            CGContextScaleCTM(context.CGContext, sx, sy);
            [self.metalView.layer renderInContext:context.CGContext];
            CGContextRestoreGState(context.CGContext);
        }
    }];
    NSData* png = UIImagePNGRepresentation(image);
    if (!png) return NO;
    NSURL* docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* out = [docs URLByAppendingPathComponent:@"oren-live-3d-snapshot.png"];
    BOOL ok = [png writeToURL:out options:NSDataWritingAtomic error:error];
    if (ok) {
        printf("OREN_IOS_LIVE_3D_SNAPSHOT path=%s bytes=%llu\n",
               out.path.UTF8String ?: "",
               (unsigned long long)png.length);
        fflush(stdout);
    }
    return ok;
}

@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([OrenLive3DAppDelegate class]));
    }
}
OBJC

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
"$CC" \
  -target arm64-apple-ios"$MIN_IOS_VERSION" \
  -miphoneos-version-min="$MIN_IOS_VERSION" \
  -isysroot "$SDK_PATH" \
  -fobjc-arc -fmodules \
  -I"$OUT_ROOT/include" \
  -I"$TMP_DIR" \
  "$TMP_DIR/main.m" \
  "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" \
  "$OUT_ROOT/iphoneos-arm64/libavm.a" \
  -ObjC \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -framework Security \
  -lz \
  -o "$APP_DIR/$APP_NAME" > "$LOG_DIR/ios_live_3d_app_compile.log" 2>&1

if [[ -n "$PROFILE" && -n "$TEAM_ID" ]]; then
  cp "$PROFILE" "$APP_DIR/embedded.mobileprovision"
  cat > "$TMP_DIR/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>$TEAM_ID.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM_ID</string>
  <key>get-task-allow</key><true/>
</dict>
</plist>
PLIST
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "ERROR: no Apple Development signing identity found" >&2
    exit 2
  fi
  codesign --force --sign "$SIGN_IDENTITY" --entitlements "$TMP_DIR/entitlements.plist" "$APP_DIR" > "$LOG_DIR/ios_live_3d_codesign.log" 2>&1
else
  codesign --force --sign - "$APP_DIR" > "$LOG_DIR/ios_live_3d_adhoc_codesign.log" 2>&1
fi

echo "Built live-device 3D capture app: $APP_DIR"
echo "Device preflight: devicectl JSON=$DEVICE_JSON xctrace=$RESULT_DIR/xctrace-devices.txt"

if [[ "$INSTALL" != "1" ]]; then
  echo "Install/launch skipped. Set OREN_IOS_LIVE_INSTALL=1 and provide a matching provisioning profile for $BUNDLE_ID to run capture."
  exit 0
fi

if [[ -z "$PROFILE" || -z "$TEAM_ID" ]]; then
  echo "ERROR: OREN_IOS_LIVE_INSTALL=1 requires a provisioning profile matching $BUNDLE_ID" >&2
  exit 2
fi

INSTALL_JSON="$RESULT_DIR/install.json"
INSTALL_LOG="$RESULT_DIR/install.log"
LAUNCH_JSON="$RESULT_DIR/launch.json"
LAUNCH_LOG="$RESULT_DIR/launch.log"
CONSOLE_LOG="$RESULT_DIR/console.log"
SNAPSHOT_PNG="$RESULT_DIR/snapshot.png"
SNAPSHOT_JSON="$RESULT_DIR/snapshot-copy.json"
SNAPSHOT_LOG="$RESULT_DIR/snapshot-copy.log"

xcrun devicectl device install app --device "$DEVICE" "$APP_DIR" \
  --json-output "$INSTALL_JSON" \
  --log-output "$INSTALL_LOG"

DEVICECTL_CHILD_OREN_IOS_LIVE_FRAME_COUNT="$FRAME_COUNT" \
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$BUNDLE_ID" \
  --json-output "$LAUNCH_JSON" \
  --log-output "$LAUNCH_LOG" | tee "$CONSOLE_LOG"

python3 - "$CONSOLE_LOG" "$RESULT_DIR/metrics.json" "$RESULT_DIR/metrics.csv" <<'PY'
import json
import pathlib
import sys
line = ""
for candidate in pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines():
    if "OREN_IOS_LIVE_3D_METRICS" in candidate:
        line = candidate
if not line:
    raise SystemExit("live 3D metrics line not found")
metrics = {}
for item in line.split()[1:]:
    if "=" not in item:
        continue
    key, value = item.split("=", 1)
    metrics[key] = int(value)
pathlib.Path(sys.argv[2]).write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
keys = sorted(metrics)
pathlib.Path(sys.argv[3]).write_text(",".join(keys) + "\n" + ",".join(str(metrics[k]) for k in keys) + "\n", encoding="utf-8")
PY

if [[ "$SNAPSHOT" == "1" ]]; then
  xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Documents/oren-live-3d-snapshot.png" \
    --destination "$SNAPSHOT_PNG" \
    --json-output "$SNAPSHOT_JSON" \
    --log-output "$SNAPSHOT_LOG"
  echo "Live-device 3D snapshot copied to $SNAPSHOT_PNG"
fi

echo "Live-device 3D metrics written to $RESULT_DIR/metrics.json and $RESULT_DIR/metrics.csv"
