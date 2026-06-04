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
TEAM_ID="${OREN_IOS_LIVE_TEAM_ID:-}"
SIGN_IDENTITY="${OREN_IOS_LIVE_SIGN_IDENTITY:-}"
PROFILE="${OREN_IOS_LIVE_PROVISIONING_PROFILE:-}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-13.0}"

mkdir -p "$TMP_DIR" "$RESULT_DIR" "$LOG_DIR"

if [[ ! -x ./oren ]]; then
  make oren > "$LOG_DIR/make_oren_for_ios_live_3d.log" 2>&1
fi

./scripts/build_libavm_ios.sh > "$LOG_DIR/build_libavm_ios_live_3d.log" 2>&1
test -f "$OUT_ROOT/iphoneos-arm64/libavm.a"
test -f "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a"
test -f "$OUT_ROOT/include/OrenAVMKit/OrenAVMKit.h"

DEVICE_JSON="$RESULT_DIR/devicectl-devices.json"
DEVICE_LOG="$RESULT_DIR/devicectl-devices.log"
xcrun devicectl list devices --json-output "$DEVICE_JSON" --log-output "$DEVICE_LOG" >/dev/null 2>&1 || true
xcrun xctrace list devices > "$RESULT_DIR/xctrace-devices.txt" 2>&1 || true

cat > "$TMP_DIR/live3d.oren" <<'OREN'
import bytes "std:bytes"
import list "std:list"
import ui_avm "std:ui/avm"

fn main() {
    var triangle3d = bytes.pack([
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        16, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0,
        4, 0, 0, 0, 18, 0, 0, 0, 16, 0, 0, 0
    ])
    var triangle3d_rgba = bytes.pack([
        0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0,
        24, 0, 0, 0, 24, 0, 0, 0, 8, 0, 0, 0,
        8, 0, 0, 0, 40, 0, 0, 0, 16, 0, 0, 0,
        255, 96, 32, 255
    ])
    var indices = bytes.pack([0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0])
    var cmds = [
        {"op": "push_camera_ortho", "near_z": 0, "far_z": 64},
        {"op": "mesh3d", "id": 1, "triangles": triangle3d, "color": "#44ccff"},
        {"op": "mesh3d_rgba", "id": 2, "triangles": triangle3d_rgba},
        {"op": "mesh3d_indexed", "id": 3, "vertices": triangle3d, "indices": indices, "color": "#ffee44"},
        {"op": "material3d", "id": 4, "color": "#ff44cc"}
    ]
    var i = 0
    while i < 48 {
        list.push(cmds, {"op": "draw_mesh3d_at", "id": 1, "x": i, "y": i / 2, "z": i % 8, "scale_milli": 1000})
        list.push(cmds, {"op": "draw_mesh3d_at", "id": 2, "x": i / 2, "y": i, "z": (i + 3) % 8, "scale_milli": 1000})
        list.push(cmds, {"op": "draw_mesh3d_at_material", "id": 3, "material_id": 4, "x": (i + 5) / 2, "y": (i + 7) / 2, "z": (i + 5) % 8, "scale_milli": 1000})
        i = i + 1
    }
    list.push(cmds, {"op": "destroy_material3d", "id": 4})
    list.push(cmds, {"op": "destroy_mesh3d", "id": 3})
    list.push(cmds, {"op": "destroy_mesh3d", "id": 2})
    list.push(cmds, {"op": "destroy_mesh3d", "id": 1})
    list.push(cmds, {"op": "pop_camera"})
    var r = ui_avm.present_frame(cmds, 64, 64, {
        "strict_bounds": true,
        "scale_milli": 3000,
        "sequence": 42,
        "drawable_w": 192,
        "drawable_h": 192,
        "target_hz_milli": 120000
    })
    if oren_is_err(r) {
        print(oren_err_msg(r))
        oren_exit(2)
    }
    print("live3d:frame-ok")
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

find_profile() {
  python3 - "$BUNDLE_ID" <<'PY'
import os
import pathlib
import plistlib
import subprocess
import sys

bundle = sys.argv[1]
profile_dir = pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"
if not profile_dir.is_dir():
    raise SystemExit(1)
for profile in sorted(profile_dir.glob("*.provisionprofile")):
    try:
        data = subprocess.check_output(["security", "cms", "-D", "-i", str(profile)], stderr=subprocess.DEVNULL)
        plist = plistlib.loads(data)
    except Exception:
        continue
    ent = plist.get("Entitlements", {})
    app_id = ent.get("application-identifier") or ent.get("com.apple.application-identifier")
    teams = plist.get("TeamIdentifier", [])
    if not app_id or not teams:
        continue
    team = teams[0]
    suffix = app_id.split(".", 1)[1] if "." in app_id else ""
    if suffix == "*" or suffix == bundle or (suffix.endswith(".*") and bundle.startswith(suffix[:-1])):
        print(str(profile))
        print(team)
        print(app_id)
        print("true" if ent.get("get-task-allow", False) else "false")
        raise SystemExit(0)
raise SystemExit(1)
PY
}

if [[ -z "$PROFILE" || -z "$TEAM_ID" ]]; then
  profile_info="$(find_profile || true)"
  if [[ -n "$profile_info" ]]; then
    PROFILE="${PROFILE:-$(printf '%s\n' "$profile_info" | sed -n '1p')}"
    TEAM_ID="${TEAM_ID:-$(printf '%s\n' "$profile_info" | sed -n '2p')}"
  fi
fi

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
#import <OrenAVMKit/OrenAVMKit.h>
#include "live3d_obc.h"

@interface OrenLive3DAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@property(nonatomic, strong) OrenAVMRuntime* runtime;
@property(nonatomic, strong) OrenAVMMetalView* metalView;
@end

@implementation OrenLive3DAppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
    (void)application;
    (void)launchOptions;
    NSError* error = nil;
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
    self.runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
    OrenAVMRunResult* result = [self.runtime runOBCData:[NSData dataWithBytes:kLive3DObc length:kLive3DObcLen] error:&error];
    if (!result || result.exitCode != 0) {
        fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR run_failed status=%ld exit=%ld message=%s\n",
                (long)(result ? result.status : -1),
                (long)(result ? result.exitCode : -1),
                error.localizedDescription.UTF8String ?: "");
        exit(2);
    }
    NSData* frame = [self.runtime getGraphicsFrameDataWithError:&error];
    if (!frame) {
        fprintf(stderr, "OREN_IOS_LIVE_3D_ERROR frame_missing message=%s\n", error.localizedDescription.UTF8String ?: "");
        exit(3);
    }
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController* controller = [[UIViewController alloc] init];
    self.metalView = [[OrenAVMMetalView alloc] initWithRuntime:self.runtime];
    self.metalView.frame = bounds;
    self.metalView.targetHzMilli = 120000;
    self.metalView.frameData = frame;
    controller.view = self.metalView;
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
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
    for (NSUInteger i = 0; i < frames; i++) {
        @autoreleasepool {
            [self.metalView draw];
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

echo "Live-device 3D metrics written to $RESULT_DIR/metrics.json and $RESULT_DIR/metrics.csv"
