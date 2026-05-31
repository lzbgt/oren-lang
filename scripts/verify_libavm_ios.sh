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
  _avm_embed_fs_mount_read \
  _avm_embed_fs_mount_write \
  _avm_embed_fs_mount \
  _avm_embed_vnet_put \
  _avm_embed_set_net_fetch_callback \
  _avm_embed_set_net_session_callbacks \
  _avm_embed_set_net_resolve_callback \
  _avm_embed_vproc_put \
  _avm_embed_vproc_set_default_exit \
  _avm_embed_set_output_capture \
  _avm_embed_output_get \
  _avm_embed_output_clear \
  _avm_embed_gfx_frame_get \
  _avm_embed_gfx_frame_clear \
  _avm_embed_gfx_input_put \
  _avm_embed_permission_request_get \
  _avm_embed_permission_request_clear \
  _avm_embed_cancel \
  _avm_embed_clear_cancel \
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
CANCEL_SRC="$TMP_DIR/cancel_spin.oren"
CANCEL_OBC_OUT="$TMP_DIR/cancel_spin.obc"
CANCEL_OBC_HEADER="$TMP_DIR/cancel_spin_obc.h"
HOST_FS_SRC="$TMP_DIR/host_fs_chain.oren"
HOST_FS_OBC_OUT="$TMP_DIR/host_fs_chain.obc"
HOST_FS_OBC_HEADER="$TMP_DIR/host_fs_chain_obc.h"
cat > "$OREN_SRC" <<'OREN'
import time "std:time"
import net_avm "std:net/avm"
import net_dns "std:net/avm/dns"
import net_tcp "std:net/avm/tcp"
import net_udp "std:net/avm/udp"
import avm_events "std:avm/events"
import ui_avm "std:ui/avm"
import perm "std:avm/permission"
import bytes "std:bytes"

fn main() {
    var args = oren_args()
    if oren_list_len(args) != 4 { oren_exit(10) }
    var s = oren_read_file("input.txt")
    if oren_is_err(s) { oren_exit(11) }
    if s != "abc" { oren_exit(12) }
    var mounted = oren_read_file("assets/config.txt")
    if oren_is_err(mounted) { oren_exit(54) }
    if mounted != "mount-ok" { oren_exit(55) }
    var w = oren_write_file("out.txt", args[1] + ":" + s)
    if oren_is_err(w) { oren_exit(13) }
    if oren_is_err(oren_write_file("export.txt", "export:" + mounted)) { oren_exit(56) }
    var body = net_avm.try_get_text(args[2])
    if oren_is_err(body) { oren_exit(14) }
    if body != "net-ok" { oren_exit(14) }
    if args[3] != "session-none" {
        var is_udp = false
        if oren_string_len(args[3]) >= 6 && oren_string_slice(args[3], 0, 6) == "udp://" { is_udp = true }
        var sid = nil
        if is_udp {
            sid = net_udp.connect_spec(args[3], 5000)
        } else {
            sid = net_tcp.connect_spec(args[3], 5000)
        }
        if oren_is_err(sid) { oren_exit(57) }
        var first_ip = net_dns.resolve_first("localhost", 5000)
        if oren_is_err(first_ip) || oren_string_len(first_ip) <= 0 { oren_exit(65) }
        var pw = nil
        if is_udp {
            pw = net_udp.select(sid, net_udp.event_write(), 5000)
        } else {
            pw = net_tcp.select(sid, net_tcp.event_write(), 5000)
        }
        if oren_is_err(pw) || pw == nil || pw["kind"] != "net" || (pw["ready"] & 2) == 0 { oren_exit(63) }
        var wn = nil
        if is_udp { wn = net_udp.send(sid, "ping", 5000) } else { wn = net_tcp.write(sid, "ping", 5000) }
        if oren_is_err(wn) || wn != 4 { oren_exit(58) }
        var pr = nil
        if is_udp {
            pr = net_udp.select(sid, net_udp.event_read(), 5000)
        } else {
            pr = net_tcp.select(sid, net_tcp.event_read(), 5000)
        }
        if oren_is_err(pr) || pr == nil || pr["kind"] != "net" || (pr["ready"] & 1) == 0 { oren_exit(64) }
        var rb = nil
        if is_udp { rb = net_udp.recv(sid, 4, 5000) } else { rb = net_tcp.read(sid, 4, 5000) }
        if oren_is_err(rb) { oren_exit(59) }
        if bytes.to_string(rb) != "pong" { oren_exit(60) }
        var cr = nil
        if is_udp { cr = net_udp.close(sid) } else { cr = net_tcp.close(sid) }
        if oren_is_err(cr) || cr != 0 { oren_exit(61) }
    }
    print("stdout:" + body)
    var cmds = [
        {"op": "fill_rect", "x": 0, "y": 0, "w": 4, "h": 2, "color": "#102030"},
        {"op": "stroke_line", "x1": 0, "y1": 0, "x2": 3, "y2": 2, "width": 1, "color": "#ff0000"},
        {"op": "circle", "cx": 2, "cy": 1, "r": 1, "fill": true, "color": "#00ff00"}
    ]
    var gr = ui_avm.present_frame(cmds, 4, 3, {
        "strict_bounds": true,
        "scale_milli": 3000,
        "sequence": 7,
        "drawable_w": 12,
        "drawable_h": 9,
        "target_hz_milli": 120000
    })
    if gr != 0 { oren_exit(19) }
    var ev_ready = avm_events.select_once([{"kind": "ui", "id": "input"}])
    if oren_is_err(ev_ready) || ev_ready == nil || ev_ready["kind"] != "ui" || ev_ready["id"] != "input" { oren_exit(32) }
    var ev = ev_ready["event"]
    if ev["kind"] != "pointer" || ev["phase"] != "down" { oren_exit(33) }
    if ev["x"] != 1 || ev["y"] != 2 || ev["pointer_id"] != 7 { oren_exit(34) }
    var ev2 = ui_avm.next_event()
    if ev2["kind"] != "pointer" || ev2["phase"] != "move" { oren_exit(35) }
    if ev2["x"] != 2 || ev2["y"] != 3 || ev2["pointer_id"] != 7 { oren_exit(36) }
    var ev3 = ui_avm.next_event()
    if ev3["kind"] != "pointer" || ev3["phase"] != "up" { oren_exit(37) }
    if ev3["x"] != 3 || ev3["y"] != 4 || ev3["pointer_id"] != 7 { oren_exit(38) }
    var ev4 = ui_avm.next_event()
    if ev4["kind"] != "resize" { oren_exit(39) }
    if ev4["width"] != 4 || ev4["height"] != 3 || ev4["scale_milli"] != 3000 { oren_exit(40) }
    var ev5 = ui_avm.next_event()
    if ev5["kind"] != "key" || ev5["phase"] != "down" { oren_exit(44) }
    if ev5["key_code"] != 65 || ev5["modifiers"] != 1 { oren_exit(45) }
    var ev6 = ui_avm.next_event()
    if ev6["kind"] != "text" || ev6["text"] != "hi" { oren_exit(48) }
    if ui_avm.next_event() != nil { oren_exit(52) }
    var gr2 = ui_avm.present_frame(cmds, 4, 3, {
        "strict_bounds": true,
        "scale_milli": 4000,
        "sequence": 8,
        "drawable_w": 16,
        "drawable_h": 12,
        "target_hz_milli": 90000
    })
    if gr2 != 0 { oren_exit(53) }
    var rc1 = oren_system("probe-ok")
    if rc1 != 21 { oren_exit(15) }
    var rc2 = oren_system("missing-proc")
    if rc2 != 44 { oren_exit(16) }
    var t0 = time.now_ns()
    var sr = time.sleep_ms(25)
    if sr != 0 { oren_exit(17) }
    if time.now_unix_ns() < t0 { oren_exit(18) }
    var pr = perm.request_net("connect", args[3])
    if oren_is_err(pr) || pr <= 0 { oren_exit(62) }
    oren_exit(9)
}
main()
OREN
"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" > "$LOG_DIR/libavm_ios_embed_chain_obc_build.log" 2>&1

cat > "$CANCEL_SRC" <<'OREN'
fn main() {
    var x = 0
    while true {
        x = x + 1
        if x > 1000000 { x = 0 }
    }
}
main()
OREN
"$OREN_COMPILER" build "$CANCEL_SRC" --backend bytecode -o "$CANCEL_OBC_OUT" > "$LOG_DIR/libavm_ios_cancel_spin_obc_build.log" 2>&1

cat > "$HOST_FS_SRC" <<'OREN'
fn main() {
    var s = oren_read_file("host/input.txt")
    if oren_is_err(s) { oren_exit(70) }
    if s != "host-in" { oren_exit(71) }
    var w = oren_write_file("host/out.txt", "host-out:" + s)
    if oren_is_err(w) { oren_exit(72) }
    var b = oren_read_bytes("host/input.txt")
    if oren_is_err(b) || oren_list_len(b) != 7 { oren_exit(73) }
    oren_exit(9)
}
main()
OREN
"$OREN_COMPILER" build "$HOST_FS_SRC" --backend bytecode -o "$HOST_FS_OBC_OUT" > "$LOG_DIR/libavm_ios_host_fs_chain_obc_build.log" 2>&1

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

python3 - "$CANCEL_OBC_OUT" "$CANCEL_OBC_HEADER" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
chunks = []
for i in range(0, len(data), 12):
    chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
out.write_text(
    "#include <stddef.h>\n"
    "static const unsigned char kCancelSpinObc[] = {\n"
    + ",\n".join("    " + chunk for chunk in chunks)
    + "\n};\n"
    + f"static const size_t kCancelSpinObcLen = {len(data)}u;\n",
    encoding="utf-8",
)
PY

python3 - "$HOST_FS_OBC_OUT" "$HOST_FS_OBC_HEADER" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
chunks = []
for i in range(0, len(data), 12):
    chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
out.write_text(
    "#include <stddef.h>\n"
    "static const unsigned char kHostFSChainObc[] = {\n"
    + ",\n".join("    " + chunk for chunk in chunks)
    + "\n};\n"
    + f"static const size_t kHostFSChainObcLen = {len(data)}u;\n",
    encoding="utf-8",
)
PY

cat > "$TMP_DIR/embed_smoke.c" <<'SMOKE'
#include "avm_embed.h"
#include "embed_chain_obc.h"
#include "cancel_spin_obc.h"

#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint64_t host_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint16_t read_u16_le(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_u32_le(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

typedef struct {
    AvmEmbedHandle* handle;
    AvmEmbedResult result;
    int rc;
} CancelRunCtx;

static void* cancel_run_main(void* arg) {
    CancelRunCtx* ctx = (CancelRunCtx*)arg;
    ctx->rc = avm_embed_run_obc_bytes(ctx->handle, kCancelSpinObc, kCancelSpinObcLen, &ctx->result);
    return NULL;
}

static int run_cancel_smoke(void) {
    AvmEmbedConfig cfg;
    AvmEmbedResult result;
    avm_embed_config_default(&cfg);
    cfg.gas_limit = 0;
    AvmEmbedHandle* handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 80;
    CancelRunCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.handle = handle;
    pthread_t thread;
    if (pthread_create(&thread, NULL, cancel_run_main, &ctx) != 0) {
        avm_embed_close(handle);
        return 81;
    }
    usleep(10000);
    if (avm_embed_cancel(handle, &result) != AVM_EMBED_OK) return 82;
    if (pthread_join(thread, NULL) != 0) return 83;
    if (ctx.rc != AVM_EMBED_ERR_VM || ctx.result.avm_error_code != 6) return 84;
    if (avm_embed_clear_cancel(handle, &result) != AVM_EMBED_OK) return 85;
    avm_embed_close(handle);
    return 0;
}

int main(void) {
    AvmEmbedConfig cfg;
    AvmEmbedResult result;
    static const uint8_t input_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 1, 0, 12, 0,
        1, 0, 0, 0, 2, 0, 0, 0, 7, 0, 0, 0
    };
    static const uint8_t pointer_move_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 2, 0, 12, 0,
        2, 0, 0, 0, 3, 0, 0, 0, 7, 0, 0, 0
    };
    static const uint8_t pointer_up_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 3, 0, 12, 0,
        3, 0, 0, 0, 4, 0, 0, 0, 7, 0, 0, 0
    };
    static const uint8_t resize_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 16, 0, 12, 0,
        4, 0, 0, 0, 3, 0, 0, 0, 184, 11, 0, 0
    };
    static const uint8_t key_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 32, 0, 8, 0,
        65, 0, 0, 0, 1, 0, 0, 0
    };
    static const uint8_t text_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 48, 0, 6, 0,
        2, 0, 0, 0, 104, 105
    };
    static const uint8_t bad_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 1, 0, 8, 0,
        1, 0, 0, 0, 2, 0, 0, 0
    };
    int cancel_rc = run_cancel_smoke();
    if (cancel_rc != 0) return cancel_rc;
    avm_embed_config_default(&cfg);

    AvmEmbedHandle* queue_handle = avm_embed_open(&cfg, &result);
    if (!queue_handle || result.status != AVM_EMBED_OK) return 38;
    for (int qi = 0; qi < 1024; qi++) {
        if (avm_embed_gfx_input_put(queue_handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 39;
    }
    if (avm_embed_gfx_input_put(queue_handle, input_event, sizeof(input_event), &result) == AVM_EMBED_OK) return 40;
    if (result.avm_error_code != 9) return 41;
    avm_embed_close(queue_handle);

    AvmEmbedHandle* handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 2;
    const char* argv[] = {"oren", "ios", "https://note.local/probe", "session-none"};
    if (avm_embed_set_argv(handle, 4, argv, &result) != AVM_EMBED_OK) return 3;
    static const uint8_t input[] = {'a', 'b', 'c'};
    if (avm_embed_vfs_put(handle, "input.txt", input, sizeof(input), &result) != AVM_EMBED_OK) return 4;
    static const uint8_t mounted_input[] = {'m', 'o', 'u', 'n', 't', '-', 'o', 'k'};
    if (avm_embed_vfs_put(handle, "assets/config.txt", mounted_input, sizeof(mounted_input), &result) != AVM_EMBED_OK) return 60;
    static const uint8_t body[] = {'n', 'e', 't', '-', 'o', 'k'};
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 5;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 6;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 7;
    if (avm_embed_gfx_input_put(handle, bad_event, sizeof(bad_event), &result) == AVM_EMBED_OK) return 37;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_gfx_input_put(handle, pointer_move_event, sizeof(pointer_move_event), &result) != AVM_EMBED_OK) return 42;
    if (avm_embed_gfx_input_put(handle, pointer_up_event, sizeof(pointer_up_event), &result) != AVM_EMBED_OK) return 43;
    if (avm_embed_gfx_input_put(handle, resize_event, sizeof(resize_event), &result) != AVM_EMBED_OK) return 34;
    if (avm_embed_gfx_input_put(handle, key_event, sizeof(key_event), &result) != AVM_EMBED_OK) return 35;
    if (avm_embed_gfx_input_put(handle, text_event, sizeof(text_event), &result) != AVM_EMBED_OK) return 36;
    if (avm_embed_set_output_capture(handle, 1, &result) != AVM_EMBED_OK) return 8;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 8;
    if (result.status != AVM_EMBED_OK || result.exit_code != 9) return 9;
    uint8_t* perm = 0;
    size_t perm_len = 0;
    if (avm_embed_permission_request_get(handle, &perm, &perm_len, &result) != AVM_EMBED_OK) return 63;
    if (perm_len != 42 || memcmp(perm, "OPR0", 4) != 0) return 64;
    if (read_u16_le(perm + 4) != 1 || read_u16_le(perm + 6) != 20 || read_u32_le(perm + 8) != 1) return 64;
    if (read_u16_le(perm + 12) != 3 || read_u16_le(perm + 14) != 7 || read_u32_le(perm + 16) != 12) return 64;
    if (memcmp(perm + 20, "NETconnect", 10) != 0 || memcmp(perm + 30, "session-none", 12) != 0) return 64;
    avm_embed_free_bytes(perm);
    if (avm_embed_permission_request_clear(handle, &result) != AVM_EMBED_OK) return 65;
    if (avm_embed_permission_request_get(handle, &perm, &perm_len, &result) == AVM_EMBED_OK) return 66;
    uint8_t* out = 0;
    size_t out_len = 0;
    if (avm_embed_vfs_get(handle, "out.txt", &out, &out_len, &result) != AVM_EMBED_OK) return 10;
    if (out_len != 7 || memcmp(out, "ios:abc", 7) != 0) return 11;
    avm_embed_free_bytes(out);
    out = 0;
    out_len = 0;
    if (avm_embed_vfs_get(handle, "export.txt", &out, &out_len, &result) != AVM_EMBED_OK) return 61;
    if (out_len != 15 || memcmp(out, "export:mount-ok", 15) != 0) return 62;
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
    if (frame_len != 116 || memcmp(frame, "OGF0", 4) != 0) return 29;
    if (frame[4] != 1 || frame[6] != 40 || frame[16] != 160 || frame[17] != 15) return 30;
    if (frame[24] != 8 || frame[28] != 16 || frame[32] != 12 || frame[36] != 144 || frame[37] != 95 || frame[38] != 1) return 30;
    if (frame[40] != 1 || frame[64] != 3 || frame[92] != 4) return 30;
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
    if (avm_embed_vfs_put(handle, "assets/config.txt", mounted_input, sizeof(mounted_input), &result) != AVM_EMBED_OK) return 60;
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 22;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 23;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 24;
    if (avm_embed_gfx_input_put(handle, bad_event, sizeof(bad_event), &result) == AVM_EMBED_OK) return 37;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_gfx_input_put(handle, pointer_move_event, sizeof(pointer_move_event), &result) != AVM_EMBED_OK) return 42;
    if (avm_embed_gfx_input_put(handle, pointer_up_event, sizeof(pointer_up_event), &result) != AVM_EMBED_OK) return 43;
    if (avm_embed_gfx_input_put(handle, resize_event, sizeof(resize_event), &result) != AVM_EMBED_OK) return 34;
    if (avm_embed_gfx_input_put(handle, key_event, sizeof(key_event), &result) != AVM_EMBED_OK) return 35;
    if (avm_embed_gfx_input_put(handle, text_event, sizeof(text_event), &result) != AVM_EMBED_OK) return 36;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 25;
    uint64_t wall1 = host_now_ns();
    if (result.status != AVM_EMBED_OK || result.exit_code != 9) return 26;
    if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 27;
    uint8_t* frame2 = 0;
    size_t frame2_len = 0;
    if (avm_embed_gfx_frame_get(handle, &frame2, &frame2_len, &result) != AVM_EMBED_OK) return 28;
    if (frame2_len != 116 || memcmp(frame2, "OGF0", 4) != 0) return 29;
    if (frame2[4] != 1 || frame2[6] != 40 || frame2[16] != 160 || frame2[17] != 15) return 30;
    if (frame2[24] != 8 || frame2[28] != 16 || frame2[32] != 12 || frame2[36] != 144 || frame2[37] != 95 || frame2[38] != 1) return 30;
    if (frame2[40] != 1 || frame2[64] != 3 || frame2[92] != 4) return 30;
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
#include "host_fs_chain_obc.h"

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
        NSString* tcpURL = env[@"OREN_AVM_SDK_TCP_URL"] ?: @"session-none";
        NSString* allowedHost = env[@"OREN_AVM_SDK_NET_ALLOWED_HOST"] ?: @"note.local";
        BOOL prefetchNetwork = env[@"OREN_AVM_SDK_NET_PREFETCH"] != nil;
        BOOL liveNetwork = env[@"OREN_AVM_SDK_NET_LIVE"] != nil;
        BOOL defaultLiveNetwork = env[@"OREN_AVM_SDK_NET_DEFAULT_LIVE"] != nil;
        NSInteger expectedExit = env[@"OREN_AVM_SDK_EXPECT_EXIT"] ? env[@"OREN_AVM_SDK_EXPECT_EXIT"].integerValue : 9;
        NSString* sessionByteLimit = env[@"OREN_AVM_SDK_SESSION_BYTE_LIMIT"];

        OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig interactiveAppDefaults];
        if (cfg.timeMode != OrenAVMTimeModeInteractiveWallClock) return 31;
        if (cfg.fsBackend != OrenAVMVirtualBackendVirtual) return 32;
        if (cfg.netBackend != OrenAVMVirtualBackendVirtual) return 33;
        if (cfg.procBackend != OrenAVMVirtualBackendVirtual) return 34;
        if (!cfg.liveNetworkEnabled) return 69;
        if (cfg.liveNetworkMaxSessions == 0) return 80;
        if (cfg.liveNetworkSessionByteLimitBytes == 0) return 81;
        if (sessionByteLimit) cfg.liveNetworkSessionByteLimitBytes = (uint64_t)sessionByteLimit.longLongValue;

        OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
        if (!runtime) return 35;
        NSError* error = nil;
        if (defaultLiveNetwork) {
            if (![runtime disableLiveNetworkWithError:&error]) return 70;
            if (![runtime enableLiveNetworkWithAllowedHosts:nil timeoutSeconds:5.0 error:&error]) return 71;
        }
        if (![runtime configureLiveNetworkSessionLimitsWithMaxSessions:cfg.liveNetworkMaxSessions
                                                        byteLimitBytes:cfg.liveNetworkSessionByteLimitBytes
                                                                 error:&error]) return 82;
        if (![runtime setArgv:@[@"oren", @"ios", netURL, tcpURL] error:&error]) return 36;
        NSData* input = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        if (![runtime putVFSFileAtPath:@"input.txt" data:input error:&error]) return 37;
        NSURL* tempRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"oren-avmkit-fs-%@", [[NSUUID UUID] UUIDString]]]
                                     isDirectory:YES];
        NSURL* assetDir = [tempRoot URLByAppendingPathComponent:@"assets" isDirectory:YES];
        NSURL* nestedDir = [assetDir URLByAppendingPathComponent:@"nested" isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:nestedDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) return 60;
        NSURL* configURL = [assetDir URLByAppendingPathComponent:@"config.txt" isDirectory:NO];
        NSURL* nestedURL = [nestedDir URLByAppendingPathComponent:@"skip.txt" isDirectory:NO];
        if (![[@"mount-ok" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:configURL options:NSDataWritingAtomic error:&error]) return 61;
        if (![[@"nested-ok" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:nestedURL options:NSDataWritingAtomic error:&error]) return 62;
        if (![runtime mountDirectoryURL:assetDir atVFSRoot:@"assets" error:&error]) return 63;
        if (![runtime mountFileURL:configURL atVFSPath:@"assets/config.txt" error:&error]) return 64;
        NSData* body = [@"net-ok" dataUsingEncoding:NSUTF8StringEncoding];
        if (liveNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            NSSet<NSString*>* allowedHosts = [NSSet setWithObject:(url.host ?: allowedHost)];
            if (![runtime enableLiveNetworkWithAllowedHosts:allowedHosts timeoutSeconds:5.0 error:&error]) return 68;
        } else if (prefetchNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            NSSet<NSString*>* allowedHosts = [NSSet setWithObject:allowedHost];
            if (![runtime fetchURLIntoVirtualNet:url allowedHosts:allowedHosts timeoutSeconds:5.0 error:&error]) return 38;
        } else if (!defaultLiveNetwork && ![runtime putVirtualNetResponseForURL:netURL data:body error:&error]) {
            return 38;
        }
        if (![runtime putVirtualProcExitForCommand:@"probe-ok" exitCode:21 error:&error]) return 39;
        if (![runtime setVirtualProcDefaultExitCode:44 error:&error]) return 40;
        if (![runtime putGraphicsPointerEventWithKind:1 x:1 y:2 pointerId:7 error:&error]) return 51;
        if (![runtime putGraphicsPointerEventWithKind:2 x:2 y:3 pointerId:7 error:&error]) return 58;
        if (![runtime putGraphicsPointerEventWithKind:3 x:3 y:4 pointerId:7 error:&error]) return 59;
        if (![runtime putGraphicsResizeEventWithWidth:4 height:3 scaleMilli:3000 error:&error]) return 54;
        if (![runtime putGraphicsKeyEventWithKind:32 keyCode:65 modifiers:1 error:&error]) return 55;
        if (![runtime putGraphicsTextInputString:@"hi" error:&error]) return 56;

        NSData* obc = [NSData dataWithBytes:kEmbedChainObc length:kEmbedChainObcLen];
        uint64_t wall0 = host_now_ns();
        OrenAVMRunResult* result = [runtime runOBCData:obc error:&error];
        uint64_t wall1 = host_now_ns();
        if (!result) return 41;
        if (result.exitCode != expectedExit) return 42;
        if (expectedExit != 9) return 0;
        if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 43;
        NSDictionary<NSString*, id>* permission = [runtime getPermissionRequestWithError:&error];
        if (!permission) return 72;
        if (![permission[@"domain"] isEqual:@"NET"]) return 73;
        if (![permission[@"action"] isEqual:@"connect"]) return 74;
        if (![permission[@"detail"] isEqual:tcpURL]) return 75;
        if (![permission[@"sequence"] isEqual:@1]) return 76;
        NSData* permissionData = [runtime getPermissionRequestDataWithError:&error];
        if (!permissionData || permissionData.length < 20) return 77;
        if (![runtime clearPermissionRequestWithError:&error]) return 78;
        if ([runtime getPermissionRequestDataWithError:&error] != nil) return 79;
        NSData* out = [runtime getVFSFileAtPath:@"out.txt" error:&error];
        if (![out isEqualToData:[@"ios:abc" dataUsingEncoding:NSUTF8StringEncoding]]) return 44;
        NSData* nested = [runtime getVFSFileAtPath:@"assets/nested/skip.txt" error:&error];
        if (![nested isEqualToData:[@"nested-ok" dataUsingEncoding:NSUTF8StringEncoding]]) return 65;
        NSURL* exportURL = [tempRoot URLByAppendingPathComponent:@"out/export.txt" isDirectory:NO];
        if (![runtime exportVFSFileAtPath:@"export.txt"
                                toFileURL:exportURL
             createIntermediateDirectories:YES
                                    error:&error]) return 66;
        NSData* exported = [NSData dataWithContentsOfURL:exportURL options:0 error:&error];
        if (![exported isEqualToData:[@"export:mount-ok" dataUsingEncoding:NSUTF8StringEncoding]]) return 67;
        NSURL* liveDir = [tempRoot URLByAppendingPathComponent:@"live-host" isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:liveDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) return 83;
        NSURL* liveInputURL = [liveDir URLByAppendingPathComponent:@"input.txt" isDirectory:NO];
        if (![[@"host-in" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:liveInputURL options:NSDataWritingAtomic error:&error]) return 84;
        OrenAVMRuntime* hostFSRuntime = [[OrenAVMRuntime alloc] initWithConfig:[OrenAVMRuntimeConfig interactiveAppDefaults]];
        if (!hostFSRuntime) return 85;
        if (![hostFSRuntime mountHostDirectoryURL:liveDir atVFSRoot:@"host" readable:YES writable:YES error:&error]) return 86;
        NSData* hostFSObc = [NSData dataWithBytes:kHostFSChainObc length:kHostFSChainObcLen];
        OrenAVMRunResult* hostFSResult = [hostFSRuntime runOBCData:hostFSObc error:&error];
        if (!hostFSResult || hostFSResult.exitCode != 9) return 87;
        NSData* liveOut = [NSData dataWithContentsOfURL:[liveDir URLByAppendingPathComponent:@"out.txt" isDirectory:NO]
                                                options:0
                                                  error:&error];
        if (![liveOut isEqualToData:[@"host-out:host-in" dataUsingEncoding:NSUTF8StringEncoding]]) return 88;
        if (![result.stdoutData isEqualToData:[@"stdout:net-ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 45;
        NSData* frame = [runtime getGraphicsFrameDataWithError:&error];
        if (!frame) return 46;
        if (frame.length != 116) return 47;
        const uint8_t* frameBytes = frame.bytes;
        if (memcmp(frameBytes, "OGF0", 4) != 0 || frameBytes[4] != 1 || frameBytes[6] != 40) return 48;
        if (frameBytes[24] != 8 || frameBytes[28] != 16 || frameBytes[32] != 12) return 48;
        if (frameBytes[40] != 1 || frameBytes[64] != 3 || frameBytes[92] != 4) return 48;
#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* graphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        if (!graphicsView) return 52;
        graphicsView.frameData = frame;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 3.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 3.0)];
        UIGraphicsEndImageContext();
        if (![graphicsView sendPointerEventWithKind:2 point:CGPointMake(2.0, 1.0) pointerId:8 error:&error]) return 53;
        if (![graphicsView sendResizeEventWithScaleMilli:1000 error:&error]) return 57;
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
    if (!cfg.liveNetworkEnabled) return 2;
    OrenAVMRuntimeConfig* det = [OrenAVMRuntimeConfig deterministicDefaults];
    if (!det || det.liveNetworkEnabled) return 3;
    OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:det];
    if (!runtime) return 4;
    NSError* error = nil;
    if (![runtime requestCancelWithError:&error]) return 5;
    if (![runtime clearCancelWithError:&error]) return 6;
    NSURL* tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"oren-avmkit-module-hostfs"]
                            isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    if (![runtime mountHostDirectoryURL:tmp atVFSRoot:@"host" readable:YES writable:NO error:&error]) return 7;
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
TCP_READY="$TMP_DIR/tcp_server.ready"
rm -f "$TCP_READY"
TCP_PORT="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
UDP_READY="$TMP_DIR/udp_server.ready"
rm -f "$UDP_READY"
UDP_PORT="$(
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
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
srv.listen(5)
ready.write_text("ready\n", encoding="utf-8")
for _ in range(5):
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
python3 - "$TCP_PORT" "$TCP_READY" > "$LOG_DIR/libavm_ios_sdk_tcp_server.log" 2>&1 <<'PY' &
import pathlib
import socket
import sys

port = int(sys.argv[1])
ready = pathlib.Path(sys.argv[2])
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(2)
ready.write_text("ready\n", encoding="utf-8")
for _ in range(2):
    conn, _addr = srv.accept()
    try:
        data = conn.recv(4)
        if data == b"ping":
            conn.sendall(b"pong")
    finally:
        conn.close()
srv.close()
PY
TCP_SERVER_PID=$!
python3 - "$UDP_PORT" "$UDP_READY" > "$LOG_DIR/libavm_ios_sdk_udp_server.log" 2>&1 <<'PY' &
import pathlib
import socket
import sys

port = int(sys.argv[1])
ready = pathlib.Path(sys.argv[2])
srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
ready.write_text("ready\n", encoding="utf-8")
data, addr = srv.recvfrom(16)
if data == b"ping":
    srv.sendto(b"pong", addr)
srv.close()
PY
UDP_SERVER_PID=$!
cleanup_net_server() {
  if kill -0 "$NET_SERVER_PID" >/dev/null 2>&1; then
    kill "$NET_SERVER_PID" >/dev/null 2>&1 || true
    wait "$NET_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if kill -0 "$TCP_SERVER_PID" >/dev/null 2>&1; then
    kill "$TCP_SERVER_PID" >/dev/null 2>&1 || true
    wait "$TCP_SERVER_PID" >/dev/null 2>&1 || true
  fi
  if kill -0 "$UDP_SERVER_PID" >/dev/null 2>&1; then
    kill "$UDP_SERVER_PID" >/dev/null 2>&1 || true
    wait "$UDP_SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_net_server EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$NET_READY" && -f "$TCP_READY" && -f "$UDP_READY" ]]; then
    break
  fi
  sleep 0.1
done
OREN_AVM_SDK_NET_PREFETCH=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="127.0.0.1" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="127.0.0.1" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" \
OREN_AVM_SDK_SESSION_BYTE_LIMIT=7 \
OREN_AVM_SDK_EXPECT_EXIT=60 \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_TCP_URL="udp://127.0.0.1:${UDP_PORT}" \
  "$HOST_SDK_BIN"
cleanup_net_server
trap - EXIT

echo "libavm iOS verify OK"
