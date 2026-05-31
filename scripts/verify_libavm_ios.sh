#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/ios}"
TMP_DIR="build/tmp/libavm_ios_verify"
LOG_DIR="build/logs"
mkdir -p "$TMP_DIR" "$LOG_DIR"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$OREN_COMPILER" ]]; then
  make oren > "$LOG_DIR/make_oren_for_libavm_ios_verify.log" 2>&1
fi

./scripts/build_libavm_ios.sh > "$LOG_DIR/build_libavm_ios.log" 2>&1

test -f "$OUT_ROOT/iphoneos-arm64/libavm.a"
test -f "$OUT_ROOT/iphonesimulator-arm64/libavm.a"
test -f "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a"
test -f "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a"
test -d "$OUT_ROOT/LibAVM.xcframework"
test -d "$OUT_ROOT/OrenAVMKit.xcframework"
test -f "$OUT_ROOT/include/avm_embed.h"
test -f "$OUT_ROOT/include/module.modulemap"
test -f "$OUT_ROOT/include/OrenAVMKit/OrenAVMKit.h"

nm -gU "$OUT_ROOT/iphoneos-arm64/libavm.a" | grep -q '_avm_embed_open'
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libavm.a" | grep -q '_avm_embed_open'
for sym in \
  _avm_embed_set_argv \
  _avm_embed_config_interactive_default \
  _avm_embed_vfs_put \
  _avm_embed_vfs_get \
  _avm_embed_vfs_snapshot \
  _avm_embed_vnet_put \
  _avm_embed_vproc_put \
  _avm_embed_vproc_set_default_exit \
  _avm_embed_set_output_capture \
  _avm_embed_output_get \
  _avm_embed_output_clear \
  _avm_embed_gfx_frame_get \
  _avm_embed_gfx_frame_clear \
  _avm_embed_gfx_input_put \
  _avm_embed_free_bytes; do
  nm -gU "$OUT_ROOT/iphoneos-arm64/libavm.a" | grep -q "$sym"
  nm -gU "$OUT_ROOT/iphonesimulator-arm64/libavm.a" | grep -q "$sym"
done

nm -gU "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" | grep -q '_OBJC_CLASS_$_OrenAVMRuntime'
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" | grep -q '_OBJC_CLASS_$_OrenAVMRuntime'
nm -gU "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" | grep -q '_OBJC_CLASS_$_OrenAVMGraphicsView'
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" | grep -q '_OBJC_CLASS_$_OrenAVMGraphicsView'

OREN_SRC="$TMP_DIR/embed_chain.oren"
OBC_OUT="$TMP_DIR/embed_chain.obc"
OBC_HEADER="$TMP_DIR/embed_chain_obc.h"
cat > "$OREN_SRC" <<'OREN'
import time "std:time"
import ui_avm "std:ui/avm"

fn main() {
    var args = oren_args()
    if oren_list_len(args) != 4 { oren_exit(10) }
    var s = oren_read_file("input.txt")
    if oren_is_err(s) { oren_exit(11) }
    if s != "abc" { oren_exit(12) }
    var w = oren_write_file("out.txt", args[1] + ":" + s)
    if oren_is_err(w) { oren_exit(13) }
    var body = oren_net_get(args[2])
    if body != "net-ok" { oren_exit(14) }
    print("stdout:" + body)
    var cmds = [{"op": "fill_rect", "x": 0, "y": 0, "w": 4, "h": 2, "color": "#102030"}]
    var gr = ui_avm.present_frame(cmds, 4, 2, {"strict_bounds": true})
    if gr != 0 { oren_exit(19) }
    var ev = ui_avm.poll_event_bytes()
    if oren_bytes_len(ev) != 24 { oren_exit(33) }
    if oren_bytes_get_u8(ev, 0) != 79 || oren_bytes_get_u8(ev, 1) != 71 || oren_bytes_get_u8(ev, 2) != 69 || oren_bytes_get_u8(ev, 3) != 48 { oren_exit(34) }
    if oren_bytes_get_u8(ev, 8) != 1 { oren_exit(35) }
    if oren_bytes_get_u32_le(ev, 12) != 1 { oren_exit(36) }
    if oren_bytes_get_u32_le(ev, 16) != 2 { oren_exit(37) }
    if oren_bytes_get_u32_le(ev, 20) != 7 { oren_exit(38) }
    var rc1 = oren_system("probe-ok")
    if rc1 != 21 { oren_exit(15) }
    var rc2 = oren_system("missing-proc")
    if rc2 != 44 { oren_exit(16) }
    var t0 = time.now_ns()
    var sr = time.sleep_ms(25)
    if sr != 0 { oren_exit(17) }
    if time.now_unix_ns() < t0 { oren_exit(18) }
    oren_exit(9)
}
main()
OREN
"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" > "$LOG_DIR/libavm_ios_embed_chain_obc_build.log" 2>&1

python3 - "$OBC_OUT" "$OBC_HEADER" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
chunks = []
for i in range(0, len(data), 12):
    chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
out.write_text(
    "#include <stddef.h>\n"
    "static const unsigned char kEmbedChainObc[] = {\n"
    + ",\n".join("    " + chunk for chunk in chunks)
    + "\n};\n"
    + f"static const size_t kEmbedChainObcLen = {len(data)}u;\n",
    encoding="utf-8",
)
PY

cat > "$TMP_DIR/embed_smoke.c" <<'SMOKE'
#include "avm_embed.h"
#include "embed_chain_obc.h"

#include <stdint.h>
#include <string.h>
#include <time.h>

static uint64_t host_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

int main(void) {
    AvmEmbedConfig cfg;
    AvmEmbedResult result;
    static const uint8_t input_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 1, 0, 12, 0,
        1, 0, 0, 0, 2, 0, 0, 0, 7, 0, 0, 0
    };
    avm_embed_config_default(&cfg);
    AvmEmbedHandle* handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 2;
    const char* argv[] = {"oren", "ios", "https://note.local/probe", "probe"};
    if (avm_embed_set_argv(handle, 4, argv, &result) != AVM_EMBED_OK) return 3;
    static const uint8_t input[] = {'a', 'b', 'c'};
    if (avm_embed_vfs_put(handle, "input.txt", input, sizeof(input), &result) != AVM_EMBED_OK) return 4;
    static const uint8_t body[] = {'n', 'e', 't', '-', 'o', 'k'};
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 5;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 6;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 7;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_set_output_capture(handle, 1, &result) != AVM_EMBED_OK) return 8;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 8;
    if (result.status != AVM_EMBED_OK || result.exit_code != 9) return 9;
    uint8_t* out = 0;
    size_t out_len = 0;
    if (avm_embed_vfs_get(handle, "out.txt", &out, &out_len, &result) != AVM_EMBED_OK) return 10;
    if (out_len != 7 || memcmp(out, "ios:abc", 7) != 0) return 11;
    avm_embed_free_bytes(out);
    uint8_t* snap = 0;
    size_t snap_len = 0;
    if (avm_embed_vfs_snapshot(handle, &snap, &snap_len, &result) != AVM_EMBED_OK) return 12;
    if (snap_len < 12 || memcmp(snap, "AVMVFS01", 8) != 0) return 13;
    avm_embed_free_bytes(snap);
    uint8_t* stdout_data = 0;
    size_t stdout_len = 0;
    if (avm_embed_output_get(handle, &stdout_data, &stdout_len, &result) != AVM_EMBED_OK) return 14;
    if (stdout_len != 14 || memcmp(stdout_data, "stdout:net-ok\n", 14) != 0) return 15;
    avm_embed_free_bytes(stdout_data);
    uint8_t* frame = 0;
    size_t frame_len = 0;
    if (avm_embed_gfx_frame_get(handle, &frame, &frame_len, &result) != AVM_EMBED_OK) return 28;
    if (frame_len != 48 || memcmp(frame, "OGF0", 4) != 0) return 29;
    if (frame[24] != 1) return 30;
    avm_embed_free_bytes(frame);
    if (avm_embed_gfx_frame_clear(handle, &result) != AVM_EMBED_OK) return 31;
    if (avm_embed_gfx_frame_get(handle, &frame, &frame_len, &result) == AVM_EMBED_OK) return 32;
    if (avm_embed_output_clear(handle, &result) != AVM_EMBED_OK) return 16;
    stdout_data = 0;
    stdout_len = 99;
    if (avm_embed_output_get(handle, &stdout_data, &stdout_len, &result) != AVM_EMBED_OK) return 17;
    if (stdout_len != 0) return 18;
    avm_embed_free_bytes(stdout_data);
    avm_embed_close(handle);

    avm_embed_config_interactive_default(&cfg);
    uint64_t wall0 = host_now_ns();
    handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 19;
    if (avm_embed_set_argv(handle, 4, argv, &result) != AVM_EMBED_OK) return 20;
    if (avm_embed_vfs_put(handle, "input.txt", input, sizeof(input), &result) != AVM_EMBED_OK) return 21;
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 22;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 23;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 24;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 25;
    uint64_t wall1 = host_now_ns();
    if (result.status != AVM_EMBED_OK || result.exit_code != 9) return 26;
    if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 27;
    uint8_t* frame2 = 0;
    size_t frame2_len = 0;
    if (avm_embed_gfx_frame_get(handle, &frame2, &frame2_len, &result) != AVM_EMBED_OK) return 28;
    if (frame2_len != 48 || memcmp(frame2, "OGF0", 4) != 0) return 29;
    avm_embed_free_bytes(frame2);
    avm_embed_close(handle);
    return 0;
}
SMOKE

cat > "$TMP_DIR/sdk_smoke.m" <<'SMOKE'
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "OrenAVMKit/OrenAVMKit.h"
#include "embed_chain_obc.h"

#include <stdint.h>
#include <string.h>
#include <time.h>

static uint64_t host_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

int main(void) {
    @autoreleasepool {
        NSDictionary<NSString*, NSString*>* env = [[NSProcessInfo processInfo] environment];
        NSString* netURL = env[@"OREN_AVM_SDK_NET_URL"] ?: @"https://note.local/probe";
        NSString* allowedHost = env[@"OREN_AVM_SDK_NET_ALLOWED_HOST"] ?: @"note.local";
        BOOL prefetchNetwork = env[@"OREN_AVM_SDK_NET_PREFETCH"] != nil;

        OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
        if (cfg.timeMode != OrenAVMTimeModeInteractiveWallClock) return 31;
        if (cfg.fsBackend != OrenAVMVirtualBackendVirtual) return 32;
        if (cfg.netBackend != OrenAVMVirtualBackendVirtual) return 33;
        if (cfg.procBackend != OrenAVMVirtualBackendVirtual) return 34;

        OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
        if (!runtime) return 35;
        NSError* error = nil;
        if (![runtime setArgv:@[@"oren", @"ios", netURL, @"probe"] error:&error]) return 36;
        NSData* input = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        if (![runtime putVFSFileAtPath:@"input.txt" data:input error:&error]) return 37;
        NSData* body = [@"net-ok" dataUsingEncoding:NSUTF8StringEncoding];
        if (prefetchNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            NSSet<NSString*>* allowedHosts = [NSSet setWithObject:allowedHost];
            if (![runtime fetchURLIntoVirtualNet:url allowedHosts:allowedHosts timeoutSeconds:5.0 error:&error]) return 38;
        } else if (![runtime putVirtualNetResponseForURL:netURL data:body error:&error]) {
            return 38;
        }
        if (![runtime putVirtualProcExitForCommand:@"probe-ok" exitCode:21 error:&error]) return 39;
        if (![runtime setVirtualProcDefaultExitCode:44 error:&error]) return 40;
        if (![runtime putGraphicsPointerEventWithKind:1 x:1 y:2 pointerId:7 error:&error]) return 51;

        NSData* obc = [NSData dataWithBytes:kEmbedChainObc length:kEmbedChainObcLen];
        uint64_t wall0 = host_now_ns();
        OrenAVMRunResult* result = [runtime runOBCData:obc error:&error];
        uint64_t wall1 = host_now_ns();
        if (!result) return 41;
        if (result.exitCode != 9) return 42;
        if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 43;
        NSData* out = [runtime getVFSFileAtPath:@"out.txt" error:&error];
        if (![out isEqualToData:[@"ios:abc" dataUsingEncoding:NSUTF8StringEncoding]]) return 44;
        if (![result.stdoutData isEqualToData:[@"stdout:net-ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 45;
        NSData* frame = [runtime getGraphicsFrameDataWithError:&error];
        if (!frame) return 46;
        if (frame.length != 48) return 47;
        const uint8_t* frameBytes = frame.bytes;
        if (memcmp(frameBytes, "OGF0", 4) != 0 || frameBytes[24] != 1) return 48;
#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* graphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        if (!graphicsView) return 52;
        graphicsView.frameData = frame;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 2.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 2.0)];
        UIGraphicsEndImageContext();
        if (![graphicsView sendPointerEventWithKind:2 point:CGPointMake(2.0, 1.0) pointerId:8 error:&error]) return 53;
#endif
        if (![runtime clearGraphicsFrameWithError:&error]) return 49;
        if ([runtime getGraphicsFrameDataWithError:&error] != nil) return 50;
    }
    return 0;
}
SMOKE

cat > "$TMP_DIR/sdk_module_smoke.m" <<'SMOKE'
@import Foundation;
@import OrenAVMKit;

int main(void) {
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
    if (!cfg || cfg.timeMode != OrenAVMTimeModeInteractiveWallClock) return 1;
    return 0;
}
SMOKE

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SIM_CC="$(xcrun --sdk iphonesimulator --find clang)"
"$SIM_CC" \
  -target arm64-apple-ios13.0-simulator \
  -mios-simulator-version-min=13.0 \
  -isysroot "$SIM_SDK" \
  -I"$OUT_ROOT/include" \
  -I"$TMP_DIR" \
  "$TMP_DIR/embed_smoke.c" \
  "$OUT_ROOT/iphonesimulator-arm64/libavm.a" \
  -o "$TMP_DIR/embed_smoke_sim"
"$SIM_CC" \
  -target arm64-apple-ios13.0-simulator \
  -mios-simulator-version-min=13.0 \
  -isysroot "$SIM_SDK" \
  -fobjc-arc -fmodules \
  -I"$OUT_ROOT/include" \
  -I"$TMP_DIR" \
  "$TMP_DIR/sdk_smoke.m" \
  "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" \
  "$OUT_ROOT/iphonesimulator-arm64/libavm.a" \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -o "$TMP_DIR/sdk_smoke_sim"
"$SIM_CC" \
  -target arm64-apple-ios13.0-simulator \
  -mios-simulator-version-min=13.0 \
  -isysroot "$SIM_SDK" \
  -fobjc-arc -fmodules \
  -I"$OUT_ROOT/include" \
  "$TMP_DIR/sdk_module_smoke.m" \
  "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" \
  "$OUT_ROOT/iphonesimulator-arm64/libavm.a" \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -o "$TMP_DIR/sdk_module_smoke_sim"

DEV_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
DEV_CC="$(xcrun --sdk iphoneos --find clang)"
"$DEV_CC" \
  -target arm64-apple-ios13.0 \
  -miphoneos-version-min=13.0 \
  -isysroot "$DEV_SDK" \
  -I"$OUT_ROOT/include" \
  -I"$TMP_DIR" \
  "$TMP_DIR/embed_smoke.c" \
  "$OUT_ROOT/iphoneos-arm64/libavm.a" \
  -o "$TMP_DIR/embed_smoke_device"
"$DEV_CC" \
  -target arm64-apple-ios13.0 \
  -miphoneos-version-min=13.0 \
  -isysroot "$DEV_SDK" \
  -fobjc-arc -fmodules \
  -I"$OUT_ROOT/include" \
  -I"$TMP_DIR" \
  "$TMP_DIR/sdk_smoke.m" \
  "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" \
  "$OUT_ROOT/iphoneos-arm64/libavm.a" \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -o "$TMP_DIR/sdk_smoke_device"
"$DEV_CC" \
  -target arm64-apple-ios13.0 \
  -miphoneos-version-min=13.0 \
  -isysroot "$DEV_SDK" \
  -fobjc-arc -fmodules \
  -I"$OUT_ROOT/include" \
  "$TMP_DIR/sdk_module_smoke.m" \
  "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" \
  "$OUT_ROOT/iphoneos-arm64/libavm.a" \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -o "$TMP_DIR/sdk_module_smoke_device"

HOST_BIN="$TMP_DIR/embed_smoke_host"
HOST_SOURCES=()
while IFS= read -r src; do
  HOST_SOURCES+=("$src")
done < <(
  find lib/avm -maxdepth 1 -name '*.c' \
    ! -name 'main.c' \
    ! -name 'avm_cli_disasm.c' \
    ! -name 'avm_cli_dump.c' \
    ! -name 'avm_cli_fs.c' \
    ! -name 'avm_cli_policy.c' \
    ! -name 'avm_cli_util.c' \
    -print | sort
  printf '%s\n' third_party/tweetnacl/tweetnacl.c
)
cc -std=c11 -O3 -fno-fast-math -ffp-contract=off -DAVM_EMBED_NO_ABORT_ON_LEAK=1 -Ilib/avm -Ibuild -I"$TMP_DIR" \
  "$TMP_DIR/embed_smoke.c" "${HOST_SOURCES[@]}" -o "$HOST_BIN"
"$HOST_BIN"

HOST_SDK_BIN="$TMP_DIR/sdk_smoke_host"
clang -std=c11 -O3 -fno-fast-math -ffp-contract=off -DAVM_EMBED_NO_ABORT_ON_LEAK=1 \
  -Ilib/avm -Ibuild -I"$TMP_DIR" -I"$OUT_ROOT/include" \
  "$TMP_DIR/sdk_smoke.m" sdk/ios/OrenAVMKit/OrenAVMKit.m "${HOST_SOURCES[@]}" \
  -fobjc-arc -framework Foundation -o "$HOST_SDK_BIN"
NET_DIR="$TMP_DIR/net_server"
rm -rf "$NET_DIR"
mkdir -p "$NET_DIR"
printf 'net-ok' > "$NET_DIR/net.txt"
NET_READY="$TMP_DIR/net_server.ready"
rm -f "$NET_READY"
NET_PORT="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
python3 - "$NET_PORT" "$NET_DIR/net.txt" "$NET_READY" > "$LOG_DIR/libavm_ios_sdk_net_server.log" 2>&1 <<'PY' &
import pathlib
import socket
import sys

port = int(sys.argv[1])
body = pathlib.Path(sys.argv[2]).read_bytes()
ready = pathlib.Path(sys.argv[3])
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(4)
ready.write_text("ready\n", encoding="utf-8")
for _ in range(4):
    conn, _addr = srv.accept()
    try:
        conn.recv(4096)
        header = (
            b"HTTP/1.1 200 OK\r\n"
            + b"Content-Type: text/plain\r\n"
            + b"Content-Length: "
            + str(len(body)).encode("ascii")
            + b"\r\nConnection: close\r\n\r\n"
        )
        conn.sendall(header + body)
    finally:
        conn.close()
srv.close()
PY
NET_SERVER_PID=$!
cleanup_net_server() {
  if kill -0 "$NET_SERVER_PID" >/dev/null 2>&1; then
    kill "$NET_SERVER_PID" >/dev/null 2>&1 || true
    wait "$NET_SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_net_server EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$NET_READY" ]]; then
    break
  fi
  sleep 0.1
done
OREN_AVM_SDK_NET_PREFETCH=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="127.0.0.1" \
  "$HOST_SDK_BIN"
cleanup_net_server
trap - EXIT

echo "libavm iOS verify OK"
