#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/ios}"
TMP_DIR="build/tmp/libavm_ios_verify"
LOG_DIR="build/logs"
FIXTURE_DIR="tests/fixtures/ios_avm"
mkdir -p "$TMP_DIR" "$LOG_DIR"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$OREN_COMPILER" ]]; then
  make oren > "$LOG_DIR/make_oren_for_libavm_ios_verify.log" 2>&1
fi

reserve_tcp_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

reserve_udp_port() {
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

stop_pid() {
  local pid="${1:-}"
  if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

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

./scripts/verify_libavm_ios_symbols.sh "$OUT_ROOT"

OREN_SRC="$TMP_DIR/embed_chain.oren"
OBC_OUT="$TMP_DIR/embed_chain.obc"
OBC_HEADER="$TMP_DIR/embed_chain_obc.h"
CANCEL_SRC="$TMP_DIR/cancel_spin.oren"
CANCEL_OBC_OUT="$TMP_DIR/cancel_spin.obc"
CANCEL_OBC_HEADER="$TMP_DIR/cancel_spin_obc.h"
CANCEL_WATCH_SRC="$TMP_DIR/cancel_watch.oren"
CANCEL_WATCH_OBC_OUT="$TMP_DIR/cancel_watch.obc"
CANCEL_WATCH_OBC_HEADER="$TMP_DIR/cancel_watch_obc.h"
HOST_FS_SRC="$TMP_DIR/host_fs_chain.oren"
HOST_FS_OBC_OUT="$TMP_DIR/host_fs_chain.obc"
HOST_FS_OBC_HEADER="$TMP_DIR/host_fs_chain_obc.h"
PACKAGE_SRC="$TMP_DIR/package_chain.oren"
PACKAGE_OBC_OUT="$TMP_DIR/package_chain.obc"
PACKAGE_V2_SRC="$TMP_DIR/package_chain_v2.oren"
PACKAGE_V2_OBC_OUT="$TMP_DIR/package_chain_v2.obc"
PACKAGE_SCENE_SRC="$TMP_DIR/package_scene3d.oren"
PACKAGE_SCENE_OBC_OUT="$TMP_DIR/package_scene3d.obc"
cp "$FIXTURE_DIR/embed_chain.oren" "$OREN_SRC"
"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" > "$LOG_DIR/libavm_ios_embed_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/cancel_spin.oren" "$CANCEL_SRC"
"$OREN_COMPILER" build "$CANCEL_SRC" --backend bytecode -o "$CANCEL_OBC_OUT" > "$LOG_DIR/libavm_ios_cancel_spin_obc_build.log" 2>&1

cp "$FIXTURE_DIR/cancel_watch.oren" "$CANCEL_WATCH_SRC"
"$OREN_COMPILER" build "$CANCEL_WATCH_SRC" --backend bytecode -o "$CANCEL_WATCH_OBC_OUT" > "$LOG_DIR/libavm_ios_cancel_watch_obc_build.log" 2>&1

cp "$FIXTURE_DIR/host_fs_chain.oren" "$HOST_FS_SRC"
"$OREN_COMPILER" build "$HOST_FS_SRC" --backend bytecode -o "$HOST_FS_OBC_OUT" > "$LOG_DIR/libavm_ios_host_fs_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_chain.oren" "$PACKAGE_SRC"
"$OREN_COMPILER" build "$PACKAGE_SRC" --backend bytecode -o "$PACKAGE_OBC_OUT" > "$LOG_DIR/libavm_ios_package_chain_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_chain_v2.oren" "$PACKAGE_V2_SRC"
"$OREN_COMPILER" build "$PACKAGE_V2_SRC" --backend bytecode -o "$PACKAGE_V2_OBC_OUT" > "$LOG_DIR/libavm_ios_package_chain_v2_obc_build.log" 2>&1

cp "$FIXTURE_DIR/package_scene3d.oren" "$PACKAGE_SCENE_SRC"
"$OREN_COMPILER" build "$PACKAGE_SCENE_SRC" --backend bytecode -o "$PACKAGE_SCENE_OBC_OUT" > "$LOG_DIR/libavm_ios_package_scene3d_obc_build.log" 2>&1

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

python3 - "$CANCEL_WATCH_OBC_OUT" "$CANCEL_WATCH_OBC_HEADER" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
chunks = []
for i in range(0, len(data), 12):
    chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
out.write_text(
    "#include <stddef.h>\n"
    "static const unsigned char kCancelWatchObc[] = {\n"
    + ",\n".join("    " + chunk for chunk in chunks)
    + "\n};\n"
    + f"static const size_t kCancelWatchObcLen = {len(data)}u;\n",
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
#include "cancel_watch_obc.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
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

static void* cancel_watch_run_main(void* arg) {
    CancelRunCtx* ctx = (CancelRunCtx*)arg;
    ctx->rc = avm_embed_run_obc_bytes(ctx->handle, kCancelWatchObc, kCancelWatchObcLen, &ctx->result);
    return NULL;
}

static int run_cancel_watch_smoke(void) {
    AvmEmbedConfig cfg;
    AvmEmbedResult result;
    avm_embed_config_interactive_default(&cfg);
    cfg.gas_limit = 0;
    AvmEmbedHandle* handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 86;
    CancelRunCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.handle = handle;
    pthread_t thread;
    if (pthread_create(&thread, NULL, cancel_watch_run_main, &ctx) != 0) {
        avm_embed_close(handle);
        return 87;
    }
    usleep(10000);
    if (avm_embed_cancel(handle, &result) != AVM_EMBED_OK) return 88;
    if (pthread_join(thread, NULL) != 0) return 89;
    if (ctx.rc != AVM_EMBED_OK || ctx.result.status != AVM_EMBED_OK || ctx.result.exit_code != 9) return 90;
    avm_embed_close(handle);
    return 0;
}

static int g_gfx_frame_callback_count = 0;
static uint32_t g_gfx_frame_callback_sequence = 0;
static size_t g_gfx_frame_callback_len = 0;

static void gfx_frame_callback(void* user_data, uint32_t sequence, size_t len) {
    (void)user_data;
    g_gfx_frame_callback_count++;
    g_gfx_frame_callback_sequence = sequence;
    g_gfx_frame_callback_len = len;
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
    static const uint8_t media_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 17, 0, 28, 0,
        4, 0, 0, 0, 3, 0, 0, 0, 184, 11, 0, 0,
        12, 0, 0, 0, 9, 0, 0, 0, 192, 212, 1, 0,
        5, 0, 0, 0
    };
    static const uint8_t frame_tick_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 18, 0, 28, 0,
        9, 0, 0, 0,
        232, 3, 0, 0, 0, 0, 0, 0,
        16, 0, 0, 0, 0, 0, 0, 0,
        192, 212, 1, 0,
        5, 0, 0, 0
    };
    static const uint8_t stale_frame_tick_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 18, 0, 28, 0,
        8, 0, 0, 0,
        132, 3, 0, 0, 0, 0, 0, 0,
        15, 0, 0, 0, 0, 0, 0, 0,
        96, 234, 0, 0,
        4, 0, 0, 0
    };
    static const uint8_t key_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 32, 0, 8, 0,
        65, 0, 0, 0, 1, 0, 0, 0
    };
    static const uint8_t text_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 48, 0, 6, 0,
        2, 0, 0, 0, 104, 105
    };
    static const uint8_t gamepad_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 64, 0, 24, 0,
        3, 0, 0, 0, 5, 0, 0, 0,
        24, 252, 255, 255, 232, 3, 0, 0,
        0, 0, 0, 0, 6, 255, 255, 255
    };
    static const uint8_t motion_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 96, 0, 40, 0,
        2, 0, 0, 0, 7, 0, 0, 0, 210, 4, 0, 0, 0, 0, 0, 0,
        246, 255, 255, 255, 20, 0, 0, 0, 226, 255, 255, 255,
        40, 0, 0, 0, 206, 255, 255, 255, 60, 0, 0, 0
    };
    static const uint8_t stale_motion_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 96, 0, 40, 0,
        2, 0, 0, 0, 6, 0, 0, 0, 111, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0,
        1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0
    };
    static const uint8_t focus_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 112, 0, 8, 0,
        4, 0, 0, 0, 1, 0, 0, 0
    };
    static const uint8_t composition_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 128, 0, 15, 0,
        3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 97, 98, 99
    };
    static const uint8_t bad_event[] = {
        79, 71, 69, 48, 0, 0, 0, 0, 1, 0, 8, 0,
        1, 0, 0, 0, 2, 0, 0, 0
    };
    int cancel_rc = run_cancel_smoke();
    if (cancel_rc != 0) return cancel_rc;
    int cancel_watch_rc = run_cancel_watch_smoke();
    if (cancel_watch_rc != 0) return cancel_watch_rc;
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
    const char* argv[] = {"oren", "ios", "https://note.local/probe", "session-none", "listen-none"};
    if (avm_embed_set_argv(handle, 5, argv, &result) != AVM_EMBED_OK) return 3;
    static const uint8_t input[] = {'a', 'b', 'c'};
    if (avm_embed_vfs_put(handle, "input.txt", input, sizeof(input), &result) != AVM_EMBED_OK) return 4;
    static const uint8_t mounted_input[] = {'m', 'o', 'u', 'n', 't', '-', 'o', 'k'};
    if (avm_embed_vfs_put(handle, "assets/config.txt", mounted_input, sizeof(mounted_input), &result) != AVM_EMBED_OK) return 60;
    static const uint8_t body[] = {'n', 'e', 't', '-', 'o', 'k'};
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 5;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 6;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 7;
    if (avm_embed_set_gfx_frame_callback(handle, gfx_frame_callback, 0, &result) != AVM_EMBED_OK) return 91;
    if (avm_embed_gfx_screen_set(handle, 0, 4, 3, 3000, 12, 9, 120000, 5, &result) != AVM_EMBED_OK) return 61;
    if (avm_embed_gfx_input_put(handle, bad_event, sizeof(bad_event), &result) == AVM_EMBED_OK) return 37;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_gfx_input_put(handle, pointer_move_event, sizeof(pointer_move_event), &result) != AVM_EMBED_OK) return 42;
    if (avm_embed_gfx_input_put(handle, pointer_up_event, sizeof(pointer_up_event), &result) != AVM_EMBED_OK) return 43;
    if (avm_embed_gfx_input_put(handle, resize_event, sizeof(resize_event), &result) != AVM_EMBED_OK) return 34;
    if (avm_embed_gfx_input_put(handle, stale_frame_tick_event, sizeof(stale_frame_tick_event), &result) != AVM_EMBED_OK) return 46;
    if (avm_embed_gfx_input_put(handle, media_event, sizeof(media_event), &result) != AVM_EMBED_OK) return 44;
    if (avm_embed_gfx_input_put(handle, frame_tick_event, sizeof(frame_tick_event), &result) != AVM_EMBED_OK) return 45;
    if (avm_embed_gfx_input_put(handle, key_event, sizeof(key_event), &result) != AVM_EMBED_OK) return 35;
    if (avm_embed_gfx_input_put(handle, text_event, sizeof(text_event), &result) != AVM_EMBED_OK) return 36;
    if (avm_embed_gfx_input_put(handle, gamepad_event, sizeof(gamepad_event), &result) != AVM_EMBED_OK) return 70;
    if (avm_embed_gfx_input_put(handle, stale_motion_event, sizeof(stale_motion_event), &result) != AVM_EMBED_OK) return 72;
    if (avm_embed_gfx_input_put(handle, motion_event, sizeof(motion_event), &result) != AVM_EMBED_OK) return 71;
    if (avm_embed_gfx_input_put(handle, focus_event, sizeof(focus_event), &result) != AVM_EMBED_OK) return 73;
    if (avm_embed_gfx_input_put(handle, composition_event, sizeof(composition_event), &result) != AVM_EMBED_OK) return 74;
    if (avm_embed_event_put(handle, "fs", "write", "host/out.txt", 7, &result) != AVM_EMBED_OK) return 68;
    if (avm_embed_event_put(handle, "package", "installed", "oren-labs/sdk-package-smoke/0.1.0", 0, &result) != AVM_EMBED_OK) return 69;
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
    size_t stdout_info_len = 0;
    if (avm_embed_output_info(handle, &stdout_info_len, &result) != AVM_EMBED_OK) return 79;
    if (stdout_info_len != stdout_len) return 80;
    if (stdout_len != 14 || memcmp(stdout_data, "stdout:net-ok\n", 14) != 0) return 15;
    avm_embed_free_bytes(stdout_data);
    uint8_t* frame = 0;
    size_t frame_len = 0;
    if (avm_embed_gfx_frame_get(handle, &frame, &frame_len, &result) != AVM_EMBED_OK) return 28;
    size_t frame_info_len = 0;
    uint32_t frame_info_sequence = 0;
    if (avm_embed_gfx_frame_info(handle, &frame_info_len, &frame_info_sequence, &result) != AVM_EMBED_OK) return 75;
    if (frame_info_len != frame_len) return 76;
    if (frame_info_sequence != 8) return 92;
    if (g_gfx_frame_callback_count < 1 || g_gfx_frame_callback_sequence != frame_info_sequence || g_gfx_frame_callback_len != frame_len) return 93;
    if (frame_len != 1102 || memcmp(frame, "OGF0", 4) != 0) return 29;
    if (frame[4] != 1 || frame[6] != 40 || frame[16] != 160 || frame[17] != 15 || frame[20] != 48) return 30;
    if (frame[24] != 8 || frame[28] != 16 || frame[32] != 12 || frame[36] != 144 || frame[37] != 95 || frame[38] != 1) return 30;
    if (frame[40] != 1 || frame[64] != 18 || frame[76] != 1 || frame[100] != 19 || frame[104] != 20 || frame[112] != 1 || frame[136] != 21 || frame[140] != 16 || frame[160] != 6 || frame[188] != 9 || frame[224] != 3 || frame[252] != 4 || frame[276] != 7 || frame[308] != 8 || frame[348] != 5 || frame[380] != 10 || frame[440] != 80 || frame[504] != 81 || frame[512] != 82 || frame[520] != 83 || frame[572] != 84 || frame[580] != 85 || frame[588] != 88 || frame[656] != 84 || frame[664] != 89 || frame[676] != 90 || frame[688] != 91 || frame[716] != 93 || frame[748] != 94 || frame[756] != 95 || frame[764] != 92 || frame[772] != 85 || frame[780] != 22 || frame[792] != 86 || frame[844] != 84 || frame[852] != 87 || frame[876] != 23 || frame[880] != 85 || frame[888] != 17 || frame[892] != 68 || frame[910] != 69 || frame[926] != 72 || frame[954] != 70 || frame[962] != 64 || frame[986] != 65 || frame[1010] != 67 || frame[1050] != 71 || frame[1094] != 66) return 30;
    avm_embed_free_bytes(frame);
    if (avm_embed_gfx_frame_clear(handle, &result) != AVM_EMBED_OK) return 31;
    frame_info_len = 99;
    frame_info_sequence = 99;
    if (avm_embed_gfx_frame_info(handle, &frame_info_len, &frame_info_sequence, &result) != AVM_EMBED_OK) return 77;
    if (frame_info_len != 0 || frame_info_sequence != 0) return 78;
    if (avm_embed_gfx_frame_get(handle, &frame, &frame_len, &result) == AVM_EMBED_OK) return 32;
    if (avm_embed_output_clear(handle, &result) != AVM_EMBED_OK) return 16;
    stdout_data = 0;
    stdout_len = 99;
    stdout_info_len = 99;
    if (avm_embed_output_info(handle, &stdout_info_len, &result) != AVM_EMBED_OK) return 81;
    if (stdout_info_len != 0) return 82;
    if (avm_embed_output_get(handle, &stdout_data, &stdout_len, &result) != AVM_EMBED_OK) return 17;
    if (stdout_len != 0) return 18;
    avm_embed_free_bytes(stdout_data);
    avm_embed_close(handle);

    avm_embed_config_interactive_default(&cfg);
    uint64_t wall0 = host_now_ns();
    handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 19;
    if (avm_embed_set_argv(handle, 5, argv, &result) != AVM_EMBED_OK) return 20;
    if (avm_embed_vfs_put(handle, "input.txt", input, sizeof(input), &result) != AVM_EMBED_OK) return 21;
    if (avm_embed_vfs_put(handle, "assets/config.txt", mounted_input, sizeof(mounted_input), &result) != AVM_EMBED_OK) return 60;
    if (avm_embed_vnet_put(handle, "https://note.local/probe", body, sizeof(body), &result) != AVM_EMBED_OK) return 22;
    if (avm_embed_vproc_put(handle, "probe-ok", 21, &result) != AVM_EMBED_OK) return 23;
    if (avm_embed_vproc_set_default_exit(handle, 44, &result) != AVM_EMBED_OK) return 24;
    if (avm_embed_gfx_screen_set(handle, 0, 4, 3, 3000, 12, 9, 120000, 5, &result) != AVM_EMBED_OK) return 61;
    if (avm_embed_gfx_input_put(handle, bad_event, sizeof(bad_event), &result) == AVM_EMBED_OK) return 37;
    if (avm_embed_gfx_input_put(handle, input_event, sizeof(input_event), &result) != AVM_EMBED_OK) return 33;
    if (avm_embed_gfx_input_put(handle, pointer_move_event, sizeof(pointer_move_event), &result) != AVM_EMBED_OK) return 42;
    if (avm_embed_gfx_input_put(handle, pointer_up_event, sizeof(pointer_up_event), &result) != AVM_EMBED_OK) return 43;
    if (avm_embed_gfx_input_put(handle, resize_event, sizeof(resize_event), &result) != AVM_EMBED_OK) return 34;
    if (avm_embed_gfx_input_put(handle, stale_frame_tick_event, sizeof(stale_frame_tick_event), &result) != AVM_EMBED_OK) return 46;
    if (avm_embed_gfx_input_put(handle, media_event, sizeof(media_event), &result) != AVM_EMBED_OK) return 44;
    if (avm_embed_gfx_input_put(handle, frame_tick_event, sizeof(frame_tick_event), &result) != AVM_EMBED_OK) return 45;
    if (avm_embed_gfx_input_put(handle, key_event, sizeof(key_event), &result) != AVM_EMBED_OK) return 35;
    if (avm_embed_gfx_input_put(handle, text_event, sizeof(text_event), &result) != AVM_EMBED_OK) return 36;
    if (avm_embed_gfx_input_put(handle, gamepad_event, sizeof(gamepad_event), &result) != AVM_EMBED_OK) return 70;
    if (avm_embed_gfx_input_put(handle, stale_motion_event, sizeof(stale_motion_event), &result) != AVM_EMBED_OK) return 72;
    if (avm_embed_gfx_input_put(handle, motion_event, sizeof(motion_event), &result) != AVM_EMBED_OK) return 71;
    if (avm_embed_gfx_input_put(handle, focus_event, sizeof(focus_event), &result) != AVM_EMBED_OK) return 73;
    if (avm_embed_gfx_input_put(handle, composition_event, sizeof(composition_event), &result) != AVM_EMBED_OK) return 74;
    if (avm_embed_event_put(handle, "fs", "write", "host/out.txt", 7, &result) != AVM_EMBED_OK) return 68;
    if (avm_embed_event_put(handle, "package", "installed", "oren-labs/sdk-package-smoke/0.1.0", 0, &result) != AVM_EMBED_OK) return 69;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 25;
    uint64_t wall1 = host_now_ns();
    if (result.status != AVM_EMBED_OK || result.exit_code != 9) return 26;
    if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 27;
    uint8_t* frame2 = 0;
    size_t frame2_len = 0;
    if (avm_embed_gfx_frame_get(handle, &frame2, &frame2_len, &result) != AVM_EMBED_OK) return 28;
    if (frame2_len != 1102 || memcmp(frame2, "OGF0", 4) != 0) return 29;
    if (frame2[4] != 1 || frame2[6] != 40 || frame2[16] != 160 || frame2[17] != 15 || frame2[20] != 48) return 30;
    if (frame2[24] != 8 || frame2[28] != 16 || frame2[32] != 12 || frame2[36] != 144 || frame2[37] != 95 || frame2[38] != 1) return 30;
    if (frame2[40] != 1 || frame2[64] != 18 || frame2[76] != 1 || frame2[100] != 19 || frame2[104] != 20 || frame2[112] != 1 || frame2[136] != 21 || frame2[140] != 16 || frame2[160] != 6 || frame2[188] != 9 || frame2[224] != 3 || frame2[252] != 4 || frame2[276] != 7 || frame2[308] != 8 || frame2[348] != 5 || frame2[380] != 10 || frame2[440] != 80 || frame2[504] != 81 || frame2[512] != 82 || frame2[520] != 83 || frame2[572] != 84 || frame2[580] != 85 || frame2[588] != 88 || frame2[656] != 84 || frame2[664] != 89 || frame2[676] != 90 || frame2[688] != 91 || frame2[716] != 93 || frame2[748] != 94 || frame2[756] != 95 || frame2[764] != 92 || frame2[772] != 85 || frame2[780] != 22 || frame2[792] != 86 || frame2[844] != 84 || frame2[852] != 87 || frame2[876] != 23 || frame2[880] != 85 || frame2[888] != 17 || frame2[892] != 68 || frame2[910] != 69 || frame2[926] != 72 || frame2[954] != 70 || frame2[962] != 64 || frame2[986] != 65 || frame2[1010] != 67 || frame2[1050] != 71 || frame2[1094] != 66) return 30;
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
#include "cancel_spin_obc.h"
#include "host_fs_chain_obc.h"

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

typedef struct {
    __unsafe_unretained OrenAVMRuntime* runtime;
    __unsafe_unretained NSData* obc;
    int saw_result;
    NSInteger status;
} SDKConcurrentRunCtx;

static void* sdk_concurrent_run_main(void* arg) {
    @autoreleasepool {
        SDKConcurrentRunCtx* ctx = (SDKConcurrentRunCtx*)arg;
        NSError* error = nil;
        OrenAVMRunResult* result = [ctx->runtime runOBCData:ctx->obc error:&error];
        ctx->saw_result = result != nil;
        ctx->status = result ? result.status : (error ? error.code : -1);
    }
    return NULL;
}

static int run_sdk_concurrent_run_guard_smoke(void) {
    OrenAVMRuntimeConfig* cfg = [OrenAVMRuntimeConfig deterministicDefaults];
    cfg.gasLimit = 0;
    OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
    if (!runtime) return 170;
    NSData* spinObc = [NSData dataWithBytes:kCancelSpinObc length:kCancelSpinObcLen];
    SDKConcurrentRunCtx ctx = { runtime, spinObc, 0, 0 };
    pthread_t thread;
    if (pthread_create(&thread, NULL, sdk_concurrent_run_main, &ctx) != 0) return 171;
    usleep(10000);
    NSError* error = nil;
    OrenAVMRunResult* second = [runtime runOBCData:spinObc error:&error];
    if (second != nil) return 172;
    if (!error || error.code != AVM_EMBED_ERR_INVALID_ARG) return 173;
    NSString* message = error.userInfo[NSLocalizedDescriptionKey];
    if (![message containsString:@"already running"]) return 174;
    if (![runtime requestCancelWithError:&error]) return 175;
    if (pthread_join(thread, NULL) != 0) return 176;
    if (ctx.saw_result || ctx.status != AVM_EMBED_ERR_VM) return 177;
    if (![runtime clearCancelWithError:&error]) return 178;
    return 0;
}

int main(void) {
    @autoreleasepool {
        NSDictionary<NSString*, NSString*>* env = [[NSProcessInfo processInfo] environment];
        NSString* netURL = env[@"OREN_AVM_SDK_NET_URL"] ?: @"https://note.local/probe";
        NSString* tcpURL = env[@"OREN_AVM_SDK_TCP_URL"] ?: @"session-none";
        NSString* tcpListenURL = env[@"OREN_AVM_SDK_TCP_LISTEN_URL"] ?: @"listen-none";
        NSString* packageDir = env[@"OREN_AVM_SDK_PACKAGE_DIR"];
        NSString* scenePackageDir = env[@"OREN_AVM_SDK_SCENE_PACKAGE_DIR"];
        NSString* packageIndexURL = env[@"OREN_AVM_SDK_PACKAGE_INDEX_URL"];
        NSString* servicePackageIndexURL = env[@"OREN_AVM_SDK_SERVICE_PACKAGE_INDEX_URL"];
        NSString* packageDownloadDir = env[@"OREN_AVM_SDK_PACKAGE_DOWNLOAD_DIR"];
        NSString* servicePackageDownloadDir = env[@"OREN_AVM_SDK_SERVICE_PACKAGE_DOWNLOAD_DIR"];
        NSString* storeIndexKeyB64 = env[@"OREN_AVM_SDK_STORE_INDEX_KEY_B64"];
        NSString* badStoreIndexKeyB64 = env[@"OREN_AVM_SDK_BAD_STORE_INDEX_KEY_B64"];
        NSString* packagePublisherKeyB64 = env[@"OREN_AVM_SDK_PACKAGE_PUBLISHER_KEY_B64"];
        NSString* trustBundlePath = env[@"OREN_AVM_SDK_TRUST_BUNDLE_PATH"];
        NSString* allowedHost = env[@"OREN_AVM_SDK_NET_ALLOWED_HOST"] ?: @"note.local";
        NSString* allowedHostList = env[@"OREN_AVM_SDK_NET_ALLOWED_HOSTS"];
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
        int concurrentGuard = run_sdk_concurrent_run_guard_smoke();
        if (concurrentGuard != 0) return concurrentGuard;

        OrenAVMRuntime* runtime = [[OrenAVMRuntime alloc] initWithConfig:cfg];
        if (!runtime) return 35;
        NSError* error = nil;
        __block NSUInteger graphicsFrameHandlerCount = 0;
        __block uint32_t graphicsFrameHandlerFirstSequence = 0;
        __block NSUInteger graphicsFrameHandlerFirstLength = 0;
        __block uint32_t graphicsFrameHandlerSequence = 0;
        __block NSUInteger graphicsFrameHandlerLength = 0;
        __block NSUInteger graphicsFrameObserverCount = 0;
        id observerToken = [runtime addGraphicsFrameHandler:^(uint32_t sequence, NSUInteger byteLength) {
            (void)sequence;
            (void)byteLength;
            graphicsFrameObserverCount += 1;
        }];
        if (!observerToken) return 190;
        runtime.graphicsFrameHandler = ^(uint32_t sequence, NSUInteger byteLength) {
            if (graphicsFrameHandlerCount == 0) {
                graphicsFrameHandlerFirstSequence = sequence;
                graphicsFrameHandlerFirstLength = byteLength;
            }
            graphicsFrameHandlerCount += 1;
            graphicsFrameHandlerSequence = sequence;
            graphicsFrameHandlerLength = byteLength;
        };
        if (defaultLiveNetwork) {
            if (![runtime disableLiveNetworkWithError:&error]) return 70;
            NSSet<NSString*>* allowedHosts = allowedHostList.length > 0
                ? [NSSet setWithArray:[allowedHostList componentsSeparatedByString:@","]]
                : nil;
            if (![runtime enableLiveNetworkWithAllowedHosts:allowedHosts timeoutSeconds:5.0 error:&error]) return 71;
        }
        if (![runtime configureLiveNetworkSessionLimitsWithMaxSessions:cfg.liveNetworkMaxSessions
                                                        byteLimitBytes:cfg.liveNetworkSessionByteLimitBytes
                                                                 error:&error]) return 82;
        if (![runtime setArgv:@[@"oren", @"ios", netURL, tcpURL, tcpListenURL] error:&error]) return 36;
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
            if (![runtime enableLiveNetworkWithAllowedHosts:[NSSet setWithObject:allowedHost] timeoutSeconds:5.0 error:&error]) return 68;
        } else if (prefetchNetwork) {
            NSURL* url = [NSURL URLWithString:netURL];
            if (url.port) {
                NSString* wrongOrigin = [NSString stringWithFormat:@"%@://%@:%ld", url.scheme.lowercaseString, url.host.lowercaseString, (long)url.port.integerValue + 1];
                NSError* deniedError = nil;
                if ([runtime fetchURLIntoVirtualNet:url allowedHosts:[NSSet setWithObject:wrongOrigin] timeoutSeconds:5.0 error:&deniedError]) return 182;
                if (!deniedError) return 183;
            }
            if (![runtime fetchURLIntoVirtualNet:url allowedHosts:[NSSet setWithObject:allowedHost] timeoutSeconds:5.0 error:&error]) return 38;
        } else if (!defaultLiveNetwork && ![runtime putVirtualNetResponseForURL:netURL data:body error:&error]) {
            return 38;
        }
        if (![runtime putVirtualProcExitForCommand:@"probe-ok" exitCode:21 error:&error]) return 39;
        if (![runtime setVirtualProcDefaultExitCode:44 error:&error]) return 40;
        if (![runtime putGraphicsPointerEventWithKind:1 x:1 y:2 pointerId:7 error:&error]) return 51;
        if (![runtime putGraphicsPointerEventWithKind:2 x:2 y:3 pointerId:7 error:&error]) return 58;
        if (![runtime putGraphicsPointerEventWithKind:3 x:3 y:4 pointerId:7 error:&error]) return 59;
        if (![runtime putGraphicsResizeEventWithWidth:4 height:3 scaleMilli:3000 error:&error]) return 54;
        if (![runtime setGraphicsScreenWithID:0 width:4 height:3 scaleMilli:3000 drawableWidth:12 drawableHeight:9 targetHzMilli:120000 flags:5 error:&error]) return 62;
        if (![runtime putGraphicsMediaEventWithWidth:4 height:3 scaleMilli:3000 drawableWidth:12 drawableHeight:9 targetHzMilli:120000 flags:5 error:&error]) return 60;
        if (![runtime putGraphicsFrameTickEventWithSequence:9 nowNs:1000 deltaNs:16 targetHzMilli:120000 flags:5 error:&error]) return 67;
        if (![runtime putGraphicsKeyEventWithKind:32 keyCode:65 modifiers:1 error:&error]) return 55;
        if (![runtime putGraphicsTextInputString:@"hi" error:&error]) return 56;
        if (![runtime putGraphicsGamepadEventWithControllerID:3 buttons:5 lxMilli:-1000 lyMilli:1000 rxMilli:0 ryMilli:-250 error:&error]) return 153;
        if (![runtime putGraphicsMotionEventWithSourceID:2 sequence:7 timestampNs:1234 accelXMilli:-10 accelYMilli:20 accelZMilli:-30 gyroXMilli:40 gyroYMilli:-50 gyroZMilli:60 error:&error]) return 154;
        if (![runtime putGraphicsFocusEventWithKind:112 focusID:4 flags:1 error:&error]) return 155;
        if (![runtime putGraphicsCompositionEventWithKind:128 text:@"abc" selectionStart:1 selectionEnd:2 error:&error]) return 156;
        if (![runtime putVirtualEventWithKind:@"fs" action:@"write" detail:@"host/out.txt" flags:7 error:&error]) return 151;
        if (![runtime putVirtualEventWithKind:@"package" action:@"installed" detail:@"oren-labs/sdk-package-smoke/0.1.0" flags:0 error:&error]) return 152;

#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* eventDrivenGraphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        OrenAVMMetalView* eventDrivenMetalView = [[OrenAVMMetalView alloc] initWithRuntime:runtime];
        if (!eventDrivenGraphicsView || !eventDrivenMetalView) return 191;
#endif
        NSData* obc = [NSData dataWithBytes:kEmbedChainObc length:kEmbedChainObcLen];
        uint64_t wall0 = host_now_ns();
        OrenAVMRunResult* result = [runtime runOBCData:obc error:&error];
        uint64_t wall1 = host_now_ns();
        if (!result) return 41;
        if (result.exitCode != expectedExit) {
            fprintf(stderr, "sdk_smoke: expected OBC exit %ld got %ld status %ld avm_error %ld\n",
                    (long)expectedExit,
                    (long)result.exitCode,
                    (long)result.status,
                    (long)result.avmErrorCode);
            return 42;
        }
        if (expectedExit != 9) return 0;
        if (wall1 <= wall0 || wall1 - wall0 < 10000000ull) return 43;
        if (graphicsFrameHandlerCount != 2) return 183;
        if (graphicsFrameObserverCount != 2) return 192;
        if (graphicsFrameHandlerFirstSequence != 7u || graphicsFrameHandlerFirstLength != 1102u) return 184;
        if (graphicsFrameHandlerSequence != 8u || graphicsFrameHandlerLength != 1102u) return 184;
#if TARGET_OS_IPHONE
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!eventDrivenGraphicsView.hasValidFrameData || !eventDrivenMetalView.hasValidFrameData) return 193;
#endif
        if ([runtime capturedOutputLengthWithError:&error] != 14) return 180;
        if (![runtime hasPermissionRequestWithError:&error]) return 181;
        NSNumber* permissionSequence = [runtime permissionRequestSequenceWithError:&error];
        if (!permissionSequence || permissionSequence.unsignedIntValue != 1u) return 182;
        NSDictionary<NSString*, id>* permission = [runtime getPermissionRequestWithError:&error];
        if (!permission) return 72;
        if (![permission[@"domain"] isEqual:@"NET"]) return 73;
        if (![permission[@"action"] isEqual:@"connect"]) return 74;
        if (![permission[@"detail"] isEqual:tcpURL]) return 75;
        if (![permission[@"sequence"] isEqual:@1]) return 76;
        NSData* permissionData = [runtime getPermissionRequestDataWithError:&error];
        if (!permissionData || permissionData.length < 20) return 77;
        OrenAVMPermissionPrompt* prompt = [OrenAVMPermissionPrompt promptWithPermissionRequest:permission error:&error];
        if (!prompt) return 162;
        if (![prompt.domain isEqual:@"NET"]) return 163;
        if (![prompt.action isEqual:@"connect"]) return 164;
        if (![prompt.detail isEqual:tcpURL]) return 165;
        if (prompt.sequence != 1) return 166;
        NSString* expectedPromptHost = [tcpURL containsString:@"://"] ? @"127.0.0.1" : tcpURL;
        if (![prompt.networkHost isEqual:expectedPromptHost]) return 167;
        if (![prompt.riskLevel isEqual:@"network"]) return 168;
        if (prompt.title.length == 0 || prompt.message.length == 0) return 169;
        NSURL* grantsURL = [tempRoot URLByAppendingPathComponent:@"permission-grants.json" isDirectory:NO];
        OrenAVMPermissionGrantStore* grantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:grantsURL];
        if (![grantStore loadWithError:&error]) return 116;
        if (![grantStore recordDecisionForPermissionPrompt:prompt
                                                   granted:YES
                                                   runtime:runtime
                                            timeoutSeconds:5.0
                                                      error:&error]) return 117;
        if (![grantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 118;
        if (![grantStore isGrantedForPermissionPrompt:prompt]) return 170;
        if (grantStore.allowedNetworkHosts.count != 1) return 119;
        OrenAVMPermissionGrantStore* reloadedGrantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:grantsURL];
        if (![reloadedGrantStore loadWithError:&error]) return 120;
        if (![reloadedGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 121;
        if (![reloadedGrantStore recordDecisionForPermissionPrompt:prompt
                                                          granted:NO
                                                          runtime:runtime
                                                   timeoutSeconds:5.0
                                                             error:&error]) return 122;
        if ([reloadedGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:tcpURL]) return 123;
        if ([reloadedGrantStore isGrantedForPermissionPrompt:prompt]) return 171;
        if (reloadedGrantStore.allowedNetworkHosts.count != 0) return 124;
        if (![runtime clearPermissionRequestWithError:&error]) return 78;
        if ([runtime hasPermissionRequestWithError:&error]) return 183;
        if ([runtime permissionRequestSequenceWithError:&error] != nil) return 184;
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
        if (packageDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMPackage* package = [store loadPackageAtDirectoryURL:[NSURL fileURLWithPath:packageDir isDirectory:YES]
                                                                  error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-smoke/0.1.0"]) return 89;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0 || (packageCfg.allowedDomains & OrenAVMDomainNet) == 0) return 90;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 91;
            NSURL* packageGrantsURL = [tempRoot URLByAppendingPathComponent:@"package-permission-grants.json" isDirectory:NO];
            OrenAVMPermissionGrantStore* packageGrantStore = [[OrenAVMPermissionGrantStore alloc] initWithStoreURL:packageGrantsURL];
            if (![packageGrantStore loadWithError:&error]) return 147;
            if (![packageGrantStore applyPackagePermissionDefaults:package runtime:packageRuntime timeoutSeconds:5.0 error:&error]) return 148;
            if (![packageGrantStore isGrantedForDomain:@"NET" action:@"connect" detail:@"tcp://package.example:443"]) return 149;
            if (![packageGrantStore.allowedNetworkHosts containsObject:@"package.example"]) return 150;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 92;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 93;
        }
        if (scenePackageDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMPackage* package = [store loadPackageAtDirectoryURL:[NSURL fileURLWithPath:scenePackageDir isDirectory:YES]
                                                                  error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-scene3d-package/0.1.0"]) return 157;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 158;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 159;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 160;
            if (![packageResult.stdoutData isEqualToData:[@"scene3d:ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 161;
        }
        if (packageIndexURL.length > 0 && packageDownloadDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            NSData* indexKey = [[NSData alloc] initWithBase64EncodedString:(storeIndexKeyB64 ?: @"") options:0];
            NSData* badIndexKey = [[NSData alloc] initWithBase64EncodedString:(badStoreIndexKeyB64 ?: @"") options:0];
            NSData* publisherKey = [[NSData alloc] initWithBase64EncodedString:(packagePublisherKeyB64 ?: @"") options:0];
            NSDictionary<NSString*, NSData*>* trustedKeys = publisherKey ? @{@"oren-labs": publisherKey} : nil;
            OrenAVMOBCTrustBundle* trustBundle = trustBundlePath.length > 0
                ? [OrenAVMOBCTrustBundle loadTrustBundleAtURL:[NSURL fileURLWithPath:trustBundlePath isDirectory:NO] error:&error]
                : nil;
            if (!trustBundle) return 112;
            if (![trustBundle.defaultStoreKeyID isEqual:@"oren-store-dev"]) return 113;
            if (![trustBundle.defaultStorePublicKey isEqualToData:indexKey]) return 114;
            if (![trustBundle.publisherPublicKeys[@"oren-labs"] isEqualToData:publisherKey]) return 115;
            NSURL* packageIndexNSURL = [NSURL URLWithString:packageIndexURL];
            if (!packageIndexNSURL || !packageIndexNSURL.port) return 184;
            NSString* packageOrigin = [NSString stringWithFormat:@"%@://%@:%@", packageIndexNSURL.scheme.lowercaseString, packageIndexNSURL.host.lowercaseString, packageIndexNSURL.port];
            NSString* wrongPackageOrigin = [NSString stringWithFormat:@"%@://%@:%ld", packageIndexNSURL.scheme.lowercaseString, packageIndexNSURL.host.lowercaseString, (long)packageIndexNSURL.port.integerValue + 1];
            error = nil;
            OrenAVMPackage* wrongOriginPackage = [store downloadPackageFromSignedIndexURL:packageIndexNSURL packageID:@"oren-labs/sdk-package-remote" version:@"0.1.0" destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES] allowedHosts:[NSSet setWithObject:wrongPackageOrigin] timeoutSeconds:5.0 trustBundle:trustBundle error:&error];
            if (wrongOriginPackage || !error) return 185;
            error = nil;
            OrenAVMPackage* package = [store downloadPackageFromSignedIndexURL:packageIndexNSURL
                                                                      packageID:@"oren-labs/sdk-package-remote"
                                                                        version:@"0.1.0"
                                                        destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                   allowedHosts:[NSSet setWithObject:packageOrigin]
                                                                 timeoutSeconds:5.0
                                                                   trustBundle:trustBundle
                                                                          error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 94;
            NSData* bundleOnlySource = [NSData dataWithContentsOfURL:[package.directoryURL URLByAppendingPathComponent:@"assets/source/main.oren" isDirectory:NO]
                                                              options:0
                                                                error:nil];
            if (![bundleOnlySource isEqualToData:[@"print(\"bundle-source\")\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 125;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 95;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 96;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 97;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 98;
            NSURL* installRootURL = [NSURL fileURLWithPath:packageDownloadDir isDirectory:YES];
            NSArray<NSString*>* installed = [store listInstalledPackageIDsInDirectoryURL:installRootURL error:&error];
            if (![installed containsObject:@"oren-labs/sdk-package-remote/0.1.0"]) return 101;
            OrenAVMPackage* loadedPackage = [store loadInstalledPackageInDirectoryURL:installRootURL
                                                                            packageID:@"oren-labs/sdk-package-remote"
                                                                              version:@"0.1.0"
                                                                                error:&error];
            if (!loadedPackage || ![loadedPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 102;
            error = nil;
            OrenAVMPackage* keepPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                         packageID:@"oren-labs/sdk-package-remote"
                                                                           version:@"0.1.0"
                                                           destinationDirectoryURL:installRootURL
                                                                      allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                    timeoutSeconds:5.0
                                                             trustedIndexPublicKey:indexKey
                                                        trustedPublisherPublicKeys:trustedKeys
                                                                     installPolicy:OrenAVMPackageInstallPolicyKeepExisting
                                                                             error:&error];
            if (!keepPackage || ![keepPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.1.0"]) return 106;
            error = nil;
            OrenAVMPackage* duplicatePackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                              packageID:@"oren-labs/sdk-package-remote"
                                                                                version:@"0.1.0"
                                                                destinationDirectoryURL:installRootURL
                                                                           allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                         timeoutSeconds:5.0
                                                                  trustedIndexPublicKey:indexKey
                                                             trustedPublisherPublicKeys:trustedKeys
                                                                          installPolicy:OrenAVMPackageInstallPolicyFailIfInstalled
                                                                                  error:&error];
            if (duplicatePackage || !error) return 107;
            error = nil;
            OrenAVMPackage* updatedPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                            packageID:@"oren-labs/sdk-package-remote"
                                                                              version:@"0.2.0"
                                                              destinationDirectoryURL:installRootURL
                                                                         allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                       timeoutSeconds:5.0
                                                                trustedIndexPublicKey:indexKey
                                                           trustedPublisherPublicKeys:trustedKeys
                                                                        installPolicy:OrenAVMPackageInstallPolicyFailIfInstalled
                                                                                error:&error];
            if (!updatedPackage || ![updatedPackage.packageID isEqual:@"oren-labs/sdk-package-remote/0.2.0"]) return 108;
            OrenAVMRuntimeConfig* updatedCfg = [store runtimeConfigForPackage:updatedPackage error:&error];
            OrenAVMRuntime* updatedRuntime = updatedCfg ? [[OrenAVMRuntime alloc] initWithConfig:updatedCfg] : nil;
            OrenAVMRunResult* updatedResult = updatedRuntime ? [store runPackage:updatedPackage runtime:updatedRuntime error:&error] : nil;
            if (!updatedResult || ![updatedResult.stdoutData isEqualToData:[@"pkg:pkg-asset-v2\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 109;
            error = nil;
            OrenAVMPackage* badAssetPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                             packageID:@"oren-labs/sdk-package-bad-asset"
                                                                               version:@"0.1.0"
                                                               destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                          allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                        timeoutSeconds:5.0
                                                                 trustedIndexPublicKey:indexKey
                                                            trustedPublisherPublicKeys:trustedKeys
                                                                                 error:&error];
            if (badAssetPackage || !error) return 99;
            error = nil;
            OrenAVMPackage* badSignaturePackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                                 packageID:@"oren-labs/sdk-package-bad-signature"
                                                                                   version:@"0.1.0"
                                                                   destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                              allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                            timeoutSeconds:5.0
                                                                     trustedIndexPublicKey:indexKey
                                                                trustedPublisherPublicKeys:trustedKeys
                                                                                     error:&error];
            if (badSignaturePackage || !error) return 100;
            error = nil;
            OrenAVMPackage* badIndexPackage = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:packageIndexURL]
                                                                             packageID:@"oren-labs/sdk-package-remote"
                                                                               version:@"0.1.0"
                                                               destinationDirectoryURL:[NSURL fileURLWithPath:packageDownloadDir isDirectory:YES]
                                                                          allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                        timeoutSeconds:5.0
                                                                 trustedIndexPublicKey:badIndexKey
                                                            trustedPublisherPublicKeys:trustedKeys
                                                                                 error:&error];
            if (badIndexPackage || !error) return 105;
            error = nil;
            if (![store removeInstalledPackageInDirectoryURL:installRootURL
                                                   packageID:@"oren-labs/sdk-package-remote"
                                                     version:@"0.1.0"
                                                       error:&error]) return 103;
            if (![store removeInstalledPackageInDirectoryURL:installRootURL
                                                   packageID:@"oren-labs/sdk-package-remote"
                                                     version:@"0.2.0"
                                                       error:&error]) return 110;
            NSArray<NSString*>* afterRemove = [store listInstalledPackageIDsInDirectoryURL:installRootURL error:&error];
            if ([afterRemove containsObject:@"oren-labs/sdk-package-remote/0.1.0"]) return 104;
            if ([afterRemove containsObject:@"oren-labs/sdk-package-remote/0.2.0"]) return 111;
        }
        if (servicePackageIndexURL.length > 0 && servicePackageDownloadDir.length > 0) {
            OrenAVMPackageStore* store = [[OrenAVMPackageStore alloc] init];
            OrenAVMOBCTrustBundle* trustBundle = trustBundlePath.length > 0
                ? [OrenAVMOBCTrustBundle loadTrustBundleAtURL:[NSURL fileURLWithPath:trustBundlePath isDirectory:NO] error:&error]
                : nil;
            if (!trustBundle) return 116;
            OrenAVMPackage* package = [store downloadPackageFromSignedIndexURL:[NSURL URLWithString:servicePackageIndexURL]
                                                                      packageID:@"oren-labs/sdk-package-service"
                                                                        version:@"0.1.0"
                                                        destinationDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                                                   allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                 timeoutSeconds:5.0
                                                                   trustBundle:trustBundle
                                                                          error:&error];
            if (!package || ![package.packageID isEqual:@"oren-labs/sdk-package-service/0.1.0"]) return 117;
            NSData* serviceBundleOnlySource = [NSData dataWithContentsOfURL:[package.directoryURL URLByAppendingPathComponent:@"assets/source/main.oren" isDirectory:NO]
                                                                     options:0
                                                                       error:nil];
            if (![serviceBundleOnlySource isEqualToData:[@"print(\"service-bundle-source\")\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 126;
            OrenAVMPackageUpdateStatus* updateStatus = [store packageUpdateStatusForPackage:package
                                                                                storeBaseURL:[NSURL URLWithString:servicePackageIndexURL]
                                                                                allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                              timeoutSeconds:5.0
                                                                                       error:&error];
            if (!updateStatus || !updateStatus.updateAvailable) return 162;
            if (![updateStatus.publisher isEqual:@"oren-labs"] ||
                ![updateStatus.name isEqual:@"sdk-package-service"] ||
                ![updateStatus.currentVersion isEqual:@"0.1.0"] ||
                ![updateStatus.latestVersion isEqual:@"0.2.0"]) return 163;
            if (![updateStatus.latestRelease[@"version"] isEqual:@"0.2.0"]) return 164;
            NSURLComponents* updateURL = [NSURLComponents componentsWithURL:[NSURL URLWithString:servicePackageIndexURL]
                                                      resolvingAgainstBaseURL:NO];
            updateURL.path = @"/api/v0/packages/oren-labs/sdk-package-service/update";
            updateURL.queryItems = @[[NSURLQueryItem queryItemWithName:@"current_version" value:@"0.2.0"]];
            OrenAVMPackageUpdateStatus* currentStatus = [store packageUpdateStatusFromURL:updateURL.URL
                                                                             allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                                           timeoutSeconds:5.0
                                                                                    error:&error];
            if (!currentStatus || currentStatus.updateAvailable ||
                ![currentStatus.latestVersion isEqual:@"0.2.0"]) return 165;
            OrenAVMPackage* reloadedServicePackage = [store loadInstalledPackageInDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                                                                     packageID:@"oren-labs/sdk-package-service"
                                                                                       version:@"0.1.0"
                                                                                         error:&error];
            OrenAVMPackageUpdateStatus* persistedStatus = reloadedServicePackage
                ? [store packageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                   allowedHosts:[NSSet setWithObject:@"127.0.0.1"]
                                                 timeoutSeconds:5.0
                                                          error:&error]
                : nil;
            if (!persistedStatus || !persistedStatus.updateAvailable ||
                ![persistedStatus.latestVersion isEqual:@"0.2.0"]) return 166;
            if (persistedStatus.checkedAtUnixMillis <= 0) return 169;
            OrenAVMPackageUpdateStatus* cachedStatus = [store lastKnownPackageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                                                                        error:&error];
            if (!cachedStatus || !cachedStatus.updateAvailable ||
                ![cachedStatus.latestVersion isEqual:@"0.2.0"] ||
                cachedStatus.checkedAtUnixMillis != persistedStatus.checkedAtUnixMillis) return 170;
            OrenAVMPackage* serviceUpdatedPackage = reloadedServicePackage
                ? [store downloadUpdateForInstalledPackage:reloadedServicePackage
                                   destinationDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES]
                                              allowedHosts:nil
                                            timeoutSeconds:5.0
                                               trustBundle:trustBundle
                                                     error:&error]
                : nil;
            if (!serviceUpdatedPackage || ![serviceUpdatedPackage.packageID isEqual:@"oren-labs/sdk-package-service/0.2.0"]) {
                fprintf(stderr, "OBC package update install failed: %s\n", error.localizedDescription.UTF8String ?: "");
                return 167;
            }
            OrenAVMPackageUpdateStatus* cachedAfterInstall = [store lastKnownPackageUpdateStatusForInstalledPackage:reloadedServicePackage
                                                                                                             error:&error];
            if (!cachedAfterInstall || !cachedAfterInstall.updateAvailable ||
                ![cachedAfterInstall.latestVersion isEqual:@"0.2.0"]) return 171;
            OrenAVMRuntimeConfig* packageCfg = [store runtimeConfigForPackage:package error:&error];
            if (!packageCfg || (packageCfg.allowedDomains & OrenAVMDomainFS) == 0) return 118;
            OrenAVMRuntime* packageRuntime = [[OrenAVMRuntime alloc] initWithConfig:packageCfg];
            if (!packageRuntime) return 119;
            OrenAVMRunResult* packageResult = [store runPackage:package runtime:packageRuntime error:&error];
            if (!packageResult || packageResult.exitCode != 9) return 120;
            if (![packageResult.stdoutData isEqualToData:[@"pkg:pkg-asset\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 121;
            NSArray<NSString*>* installed = [store listInstalledPackageIDsInDirectoryURL:[NSURL fileURLWithPath:servicePackageDownloadDir isDirectory:YES] error:&error];
            if (![installed containsObject:@"oren-labs/sdk-package-service/0.1.0"]) return 122;
            if (![installed containsObject:@"oren-labs/sdk-package-service/0.2.0"]) return 168;
        }
        if (![result.stdoutData isEqualToData:[@"stdout:net-ok\n" dataUsingEncoding:NSUTF8StringEncoding]]) return 45;
        if (![runtime hasGraphicsFrameWithError:&error]) return 172;
        NSData* frame = [runtime getGraphicsFrameDataWithError:&error];
        if (!frame) return 46;
        if (frame.length != 1102) return 47;
        const uint8_t* frameBytes = frame.bytes;
        if (memcmp(frameBytes, "OGF0", 4) != 0 || frameBytes[4] != 1 || frameBytes[6] != 40) return 48;
        if (frameBytes[20] != 48 || frameBytes[24] != 8 || frameBytes[28] != 16 || frameBytes[32] != 12) return 48;
        if (frameBytes[40] != 1 || frameBytes[64] != 18 || frameBytes[76] != 1 || frameBytes[100] != 19 || frameBytes[104] != 20 || frameBytes[112] != 1 || frameBytes[136] != 21 || frameBytes[140] != 16 || frameBytes[160] != 6 || frameBytes[188] != 9 || frameBytes[224] != 3 || frameBytes[252] != 4 || frameBytes[276] != 7 || frameBytes[308] != 8 || frameBytes[348] != 5 || frameBytes[380] != 10 || frameBytes[440] != 80 || frameBytes[504] != 81 || frameBytes[512] != 82 || frameBytes[520] != 83 || frameBytes[572] != 84 || frameBytes[580] != 85 || frameBytes[588] != 88 || frameBytes[656] != 84 || frameBytes[664] != 89 || frameBytes[676] != 90 || frameBytes[688] != 91 || frameBytes[716] != 93 || frameBytes[748] != 94 || frameBytes[756] != 95 || frameBytes[764] != 92 || frameBytes[772] != 85 || frameBytes[780] != 22 || frameBytes[792] != 86 || frameBytes[844] != 84 || frameBytes[852] != 87 || frameBytes[876] != 23 || frameBytes[880] != 85 || frameBytes[888] != 17 || frameBytes[892] != 68 || frameBytes[910] != 69 || frameBytes[926] != 72 || frameBytes[954] != 70 || frameBytes[962] != 64 || frameBytes[986] != 65 || frameBytes[1010] != 67 || frameBytes[1050] != 71 || frameBytes[1094] != 66) return 48;
#if TARGET_OS_IPHONE
        OrenAVMGraphicsView* graphicsView = [[OrenAVMGraphicsView alloc] initWithRuntime:runtime];
        if (!graphicsView) return 52;
        graphicsView.frameData = frame;
        if (!graphicsView.hasValidFrameData) return 173;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 3.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 3.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 142;
        uint8_t imageOnlyFrameBytes[] = {
            79, 71, 70, 48, 1, 0, 40, 0,
            1, 0, 0, 0, 1, 0, 0, 0, 232, 3, 0, 0, 1, 0, 0, 0,
            0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
            64, 0, 20, 0,
            1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0,
            255, 0, 0, 255
        };
        graphicsView.frameData = [NSData dataWithBytes:imageOnlyFrameBytes length:sizeof(imageOnlyFrameBytes)];
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0, 1.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 1.0, 1.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 1 || graphicsView.retainedImagePixelCount != 1) return 145;
        [graphicsView clearImageCache];
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 146;
        graphicsView.retainedImageCountLimit = 0;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0, 3.0), NO, 1.0);
        [graphicsView drawRect:CGRectMake(0.0, 0.0, 4.0, 3.0)];
        UIGraphicsEndImageContext();
        if (graphicsView.retainedImageCount != 0 || graphicsView.retainedImagePixelCount != 0) return 143;
        graphicsView.retainedImageCountLimit = 1024;
        if (![graphicsView sendPointerEventWithKind:2 point:CGPointMake(2.0, 1.0) pointerId:8 error:&error]) return 53;
        if (![graphicsView sendPointerEventsWithKind:2 points:@[[NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)],
                                                                 [NSValue valueWithCGPoint:CGPointMake(3.0, 2.0)]]
                                           pointerIDs:@[@(8u), @(9u)]
                                                error:&error]) return 134;
        if (![graphicsView sendResizeEventWithScaleMilli:1000 error:&error]) return 57;
        if (![graphicsView publishScreenStateWithTargetHzMilli:120000 flags:5 error:&error]) return 123;
        if (![graphicsView sendMediaEventWithTargetHzMilli:120000 flags:5 error:&error]) return 124;
        OrenAVMMetalView* metalView = [[OrenAVMMetalView alloc] initWithRuntime:runtime];
        if (!metalView) return 127;
        metalView.frameData = frame;
        if (!metalView.hasValidFrameData) return 174;
        if (![metalView prepareFrameResourcesWithError:&error]) return 162;
        if (metalView.lastFrameVertexCount < 140u) return 163;
        if (metalView.lastFrameTextRunCount != 2u) return 164;
        if (metalView.lastFrameImageRunCount != 3u) return 165;
        if (metalView.retainedImageCount != 0 || metalView.retainedImagePixelCount != 0) return 166;
        metalView.targetHzMilli = 120000;
        metalView.mediaFlags = 5;
        if (metalView.preferredFramesPerSecond != 120) return 129;
        if (metalView.lastFrameTargetBudgetNs != 8333333ull) return 131;
        if (metalView.frameBudgetWarningPermille != 1000u) return 136;
        if ([metalView frameCPUNsExceedsBudget:8333333ull]) return 137;
        if (![metalView frameCPUNsExceedsBudget:8333334ull]) return 138;
        metalView.frameBudgetWarningPermille = 500u;
        if ([metalView frameCPUNsExceedsBudget:4166666ull]) return 139;
        if (![metalView frameCPUNsExceedsBudget:4166667ull]) return 140;
        metalView.frameBudgetWarningPermille = 1000u;
        metalView.targetHzMilli = 90000;
        if (metalView.preferredFramesPerSecond != 90) return 130;
        if (metalView.lastFrameTargetBudgetNs != 11111111ull) return 132;
        metalView.targetHzMilli = 120000;
        metalView.frameData = [NSData dataWithBytes:imageOnlyFrameBytes length:sizeof(imageOnlyFrameBytes)];
        if (!metalView.hasValidFrameData) return 185;
        if (![metalView prepareFrameResourcesWithError:&error]) return 186;
        if (metalView.retainedImageCount != 1 || metalView.retainedImagePixelCount != 1) return 187;
        metalView.frameData = frame;
        if (![metalView prepareFrameResourcesWithError:&error]) return 188;
        if (metalView.lastFrameTextRunCount != 2u || metalView.lastFrameImageRunCount != 3u) return 189;
        [metalView resetFrameMetrics];
        if (metalView.renderedFrameCount != 0 || metalView.lastFrameCPUNs != 0) return 133;
        if (metalView.lastFrameBudgetUsagePermille != 0 || metalView.lastFrameOverBudget || metalView.lastFrameImageRunCount != 0) return 141;
        metalView.retainedImageCountLimit = 0;
        [metalView clearImageTextureCache];
        if (metalView.retainedImageCount != 0 || metalView.retainedImagePixelCount != 0) return 144;
        metalView.retainedImageCountLimit = 1024;
        if (![metalView sendPointerEventsWithKind:2 points:@[[NSValue valueWithCGPoint:CGPointMake(1.0, 1.0)],
                                                             [NSValue valueWithCGPoint:CGPointMake(3.0, 2.0)]]
                                       pointerIDs:@[@(10u), @(11u)]
                                            error:&error]) return 135;
        [metalView clearTextTextureCache];
        if (![metalView publishScreenStateWithError:&error]) return 128;
#endif
        if (![runtime clearGraphicsFrameWithError:&error]) return 49;
        if ([runtime hasGraphicsFrameWithError:&error]) return 175;
#if TARGET_OS_IPHONE
        NSData* graphicsFrameAfterClear = graphicsView.frameData;
        if (![graphicsView reloadFrameWithError:&error]) return 176;
        if (![graphicsView.frameData isEqualToData:graphicsFrameAfterClear] || !graphicsView.hasValidFrameData) return 177;
        NSData* metalFrameAfterClear = metalView.frameData;
        if (![metalView reloadFrameWithError:&error]) return 178;
        if (![metalView.frameData isEqualToData:metalFrameAfterClear] || !metalView.hasValidFrameData) return 179;
#endif
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

HOST_BIN="$TMP_DIR/embed_smoke_host"
HOST_SDK_BIN="$TMP_DIR/sdk_smoke_host"
./scripts/verify_libavm_ios_compile_smokes.sh "$OUT_ROOT" "$TMP_DIR" "$HOST_BIN" "$HOST_SDK_BIN"
NET_DIR="$TMP_DIR/net_server"
rm -rf "$NET_DIR"
mkdir -p "$NET_DIR"
printf 'net-ok' > "$NET_DIR/net.txt"
NET_READY="$TMP_DIR/net_server.ready"
rm -f "$NET_READY"
NET_PORT="$(reserve_tcp_port)"
TCP_READY="$TMP_DIR/tcp_server.ready"
rm -f "$TCP_READY"
TCP_PORT="$(reserve_tcp_port)"
TCP_LISTEN_PORT="$(reserve_tcp_port)"
UDP_READY="$TMP_DIR/udp_server.ready"
rm -f "$UDP_READY"
UDP_PORT="$(reserve_udp_port)"
WS_READY="$TMP_DIR/ws_server.ready"
rm -f "$WS_READY"
WS_PORT="$(reserve_tcp_port)"
PKG_READY="$TMP_DIR/package_http.ready"
rm -f "$PKG_READY"
PKG_PORT="$(reserve_tcp_port)"
GO_STORE_PORT="$(reserve_tcp_port)"
PACKAGE_DIR="$TMP_DIR/package_store/oren-labs/sdk-package-smoke/0.1.0"
SCENE_PACKAGE_DIR="$TMP_DIR/package_store/oren-labs/sdk-scene3d-package/0.1.0"
REMOTE_STORE_DIR="$TMP_DIR/remote_obc_store"
GO_STORE_DIR="$TMP_DIR/go_obc_store"
REMOTE_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-remote/0.1.0"
REMOTE_PACKAGE_V2_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-remote/0.2.0"
REMOTE_BAD_ASSET_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-bad-asset/0.1.0"
REMOTE_BAD_SIGNATURE_PACKAGE_DIR="$REMOTE_STORE_DIR/packages/oren-labs/sdk-package-bad-signature/0.1.0"
rm -rf "$TMP_DIR/package_store" "$TMP_DIR/downloaded_packages" "$TMP_DIR/downloaded_service_packages" "$REMOTE_STORE_DIR" "$GO_STORE_DIR"
mkdir -p "$PACKAGE_DIR/assets" "$SCENE_PACKAGE_DIR/assets" "$REMOTE_PACKAGE_DIR/assets" "$REMOTE_PACKAGE_V2_DIR/assets" "$REMOTE_BAD_ASSET_PACKAGE_DIR/assets" "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/assets"
cp "$PACKAGE_OBC_OUT" "$PACKAGE_DIR/program.obc"
cp "$PACKAGE_SCENE_OBC_OUT" "$SCENE_PACKAGE_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_PACKAGE_DIR/program.obc"
cp "$PACKAGE_V2_OBC_OUT" "$REMOTE_PACKAGE_V2_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_BAD_ASSET_PACKAGE_DIR/program.obc"
cp "$PACKAGE_OBC_OUT" "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/program.obc"
printf 'pkg-asset' > "$PACKAGE_DIR/assets/config.txt"
python3 scripts/make_scene3d_bin_v0.py \
  examples/obc_store_demos/assets/scene3d_card.json \
  "$SCENE_PACKAGE_DIR/assets/scene3d_card.os3d"
printf 'pkg-asset' > "$REMOTE_PACKAGE_DIR/assets/config.txt"
printf 'pkg-asset-v2' > "$REMOTE_PACKAGE_V2_DIR/assets/config.txt"
printf 'pkg-asset' > "$REMOTE_BAD_ASSET_PACKAGE_DIR/assets/config.txt"
printf 'pkg-asset' > "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/assets/config.txt"
PACKAGE_HASH="$(shasum -a 256 "$PACKAGE_DIR/program.obc" | awk '{print $1}')"
SCENE_PACKAGE_HASH="$(shasum -a 256 "$SCENE_PACKAGE_DIR/program.obc" | awk '{print $1}')"
SCENE_ASSET_HASH="$(shasum -a 256 "$SCENE_PACKAGE_DIR/assets/scene3d_card.os3d" | awk '{print $1}')"
REMOTE_PACKAGE_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/program.obc" | awk '{print $1}')"
REMOTE_PACKAGE_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/program.obc" | awk '{print $1}')"
REMOTE_ASSET_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/assets/config.txt" | awk '{print $1}')"
REMOTE_ASSET_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/assets/config.txt" | awk '{print $1}')"
cat > "$PACKAGE_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-package-smoke",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "SDK Package Smoke",
  "summary": "Verifies OrenAVMPackageStore local package loading.",
  "entry_obc": "program.obc",
  "obc_sha256": "$PACKAGE_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "NET", "EXIT"],
  "permission_defaults": [
    { "domain": "NET", "action": "connect", "detail": "tcp://package.example:443", "granted": true }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
cat > "$SCENE_PACKAGE_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-scene3d-package",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "SDK Scene3D Package",
  "summary": "Verifies OrenAVMPackageStore mounts byte-native Scene3D assets.",
  "entry_obc": "program.obc",
  "obc_sha256": "$SCENE_PACKAGE_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "EXIT"],
  "assets": [
    {
      "path": "assets/scene3d_card.os3d",
      "sha256": "$SCENE_ASSET_HASH",
      "media_type": "application/vnd.oren.ui.scene3d.bin.v0"
    }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 10000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
cat > "$REMOTE_PACKAGE_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-package-remote",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "SDK Remote Package Smoke",
  "summary": "Verifies OrenAVMPackageStore index download.",
  "entry_obc": "program.obc",
  "obc_sha256": "$REMOTE_PACKAGE_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "EXIT"],
  "assets": [
    { "path": "assets/config.txt", "sha256": "$REMOTE_ASSET_HASH" }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
cat > "$REMOTE_BAD_ASSET_PACKAGE_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-package-bad-asset",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "SDK Bad Asset Package Smoke",
  "summary": "Verifies asset hash mismatch rejection.",
  "entry_obc": "program.obc",
  "obc_sha256": "$REMOTE_PACKAGE_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "EXIT"],
  "assets": [
    { "path": "assets/config.txt", "sha256": "0000000000000000000000000000000000000000000000000000000000000000" }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
cat > "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-package-bad-signature",
  "publisher": "oren-labs",
  "version": "0.1.0",
  "title": "SDK Bad Signature Package Smoke",
  "summary": "Verifies manifest signature rejection.",
  "entry_obc": "program.obc",
  "obc_sha256": "$REMOTE_PACKAGE_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "EXIT"],
  "assets": [
    { "path": "assets/config.txt", "sha256": "$REMOTE_ASSET_HASH" }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
cat > "$REMOTE_PACKAGE_V2_DIR/package.json" <<JSON
{
  "schema": "oren.obc.package.v0",
  "name": "sdk-package-remote",
  "publisher": "oren-labs",
  "version": "0.2.0",
  "title": "SDK Remote Package Smoke v2",
  "summary": "Verifies OrenAVMPackageStore update policy.",
  "entry_obc": "program.obc",
  "obc_sha256": "$REMOTE_PACKAGE_V2_HASH",
  "oren_min": "0.0.rolling",
  "avm_abi_min": 8,
  "capabilities": ["CORE", "FS", "EXIT"],
  "assets": [
    { "path": "assets/config.txt", "sha256": "$REMOTE_ASSET_V2_HASH" }
  ],
  "time_mode": "deterministic",
  "budgets": {
    "gas": 5000000,
    "heap_bytes": 33554432,
    "io_bytes": 1048576,
    "frame_commands": 1024
  },
  "vfs_mounts": [
    { "virtual": "assets", "package_path": "assets", "read_only": true }
  ]
}
JSON
REMOTE_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/package.json" | awk '{print $1}')"
REMOTE_MANIFEST_V2_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_V2_DIR/package.json" | awk '{print $1}')"
REMOTE_BAD_ASSET_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_BAD_ASSET_PACKAGE_DIR/package.json" | awk '{print $1}')"
REMOTE_BAD_SIGNATURE_MANIFEST_HASH="$(shasum -a 256 "$REMOTE_BAD_SIGNATURE_PACKAGE_DIR/package.json" | awk '{print $1}')"
python3 - "$REMOTE_PACKAGE_DIR" "$REMOTE_PACKAGE_DIR/bundle.obc.zip" <<'PY'
import pathlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name in ["package.json", "program.obc", "assets/config.txt"]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, (root / name).read_bytes())
    info = zipfile.ZipInfo("assets/source/main.oren")
    info.date_time = (2026, 1, 1, 0, 0, 0)
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, b"print(\"bundle-source\")\n")
PY
REMOTE_BUNDLE_HASH="$(shasum -a 256 "$REMOTE_PACKAGE_DIR/bundle.obc.zip" | awk '{print $1}')"
PACKAGE_SIGN_KEY="$TMP_DIR/package_store_p256.pem"
BAD_STORE_INDEX_KEY="$TMP_DIR/package_store_bad_index_p256.pem"
REMOTE_MANIFEST_HASH_MSG="$TMP_DIR/remote_manifest_hash.txt"
REMOTE_MANIFEST_V2_HASH_MSG="$TMP_DIR/remote_manifest_v2_hash.txt"
REMOTE_BAD_ASSET_HASH_MSG="$TMP_DIR/remote_bad_asset_manifest_hash.txt"
extract_p256_pubkey_b64() {
  python3 - "$1" <<'PY'
import base64
import subprocess
import sys
der = subprocess.check_output(["openssl", "ec", "-in", sys.argv[1], "-pubout", "-outform", "DER"], stderr=subprocess.DEVNULL)
idx = der.rfind(b"\x03\x42\x00\x04")
if idx < 0:
    raise SystemExit("missing P-256 public key bit string")
pub = der[idx + 3:idx + 68]
if len(pub) != 65 or pub[0] != 4:
    raise SystemExit("invalid P-256 public key length")
print(base64.b64encode(pub).decode("ascii"))
PY
}
openssl ecparam -name prime256v1 -genkey -noout -out "$PACKAGE_SIGN_KEY"
openssl ecparam -name prime256v1 -genkey -noout -out "$BAD_STORE_INDEX_KEY"
printf '%s' "$REMOTE_MANIFEST_HASH" > "$REMOTE_MANIFEST_HASH_MSG"
printf '%s' "$REMOTE_MANIFEST_V2_HASH" > "$REMOTE_MANIFEST_V2_HASH_MSG"
printf '%s' "$REMOTE_BAD_ASSET_MANIFEST_HASH" > "$REMOTE_BAD_ASSET_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_manifest.sig" "$REMOTE_MANIFEST_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_manifest_v2.sig" "$REMOTE_MANIFEST_V2_HASH_MSG"
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$TMP_DIR/remote_bad_asset_manifest.sig" "$REMOTE_BAD_ASSET_HASH_MSG"
REMOTE_SIGNATURE_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_manifest.sig" | tr -d '\n')"
REMOTE_SIGNATURE_V2_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_manifest_v2.sig" | tr -d '\n')"
REMOTE_BAD_ASSET_SIGNATURE_HEX="$(xxd -p -c 256 "$TMP_DIR/remote_bad_asset_manifest.sig" | tr -d '\n')"
PACKAGE_PUBLISHER_KEY_B64="$(extract_p256_pubkey_b64 "$PACKAGE_SIGN_KEY")"
BAD_STORE_INDEX_KEY_B64="$(extract_p256_pubkey_b64 "$BAD_STORE_INDEX_KEY")"
GO_STORE_SERVER_BIN="$TMP_DIR/obc-store-server"
go build -o "$GO_STORE_SERVER_BIN" ./cmd/obc-store-server
TRUST_BUNDLE_JSON="$TMP_DIR/obc_store_trust.json"
cat > "$TRUST_BUNDLE_JSON" <<JSON
{
  "schema": "oren.obc.trust.v0",
  "generated_at": "2026-06-01T00:00:00Z",
  "store_keys": [
    {
      "id": "oren-store-dev",
      "alg": "p256-sha256-der",
      "public_key_x963_b64": "$PACKAGE_PUBLISHER_KEY_B64"
    }
  ],
  "publisher_keys": {
    "oren-labs": {
      "alg": "p256-sha256-der",
      "public_key_x963_b64": "$PACKAGE_PUBLISHER_KEY_B64"
    }
  }
}
JSON
cat > "$REMOTE_STORE_DIR/index.json" <<JSON
{
  "schema": "oren.obc.store.index.v0",
  "generated_at": "2026-06-01T00:00:00Z",
  "packages": [
    {
      "id": "oren-labs/sdk-package-remote",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-remote/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_MANIFEST_HASH",
      "bundle": "packages/oren-labs/sdk-package-remote/0.1.0/bundle.obc.zip",
      "bundle_sha256": "$REMOTE_BUNDLE_HASH",
      "bundle_media_type": "application/vnd.oren.obc.release+zip",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_SIGNATURE_HEX",
      "tags": ["sdk", "smoke"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-remote",
      "version": "0.2.0",
      "manifest": "packages/oren-labs/sdk-package-remote/0.2.0/package.json",
      "manifest_sha256": "$REMOTE_MANIFEST_V2_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_SIGNATURE_V2_HEX",
      "tags": ["sdk", "smoke", "update"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-bad-asset",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-bad-asset/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_BAD_ASSET_MANIFEST_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "$REMOTE_BAD_ASSET_SIGNATURE_HEX",
      "tags": ["sdk", "negative"],
      "min_app": "0.1.0"
    },
    {
      "id": "oren-labs/sdk-package-bad-signature",
      "version": "0.1.0",
      "manifest": "packages/oren-labs/sdk-package-bad-signature/0.1.0/package.json",
      "manifest_sha256": "$REMOTE_BAD_SIGNATURE_MANIFEST_HASH",
      "signature_alg": "p256-sha256-der",
      "signature_p256_sha256_der_hex": "00",
      "tags": ["sdk", "negative"],
      "min_app": "0.1.0"
    }
  ]
}
JSON
openssl dgst -sha256 -sign "$PACKAGE_SIGN_KEY" -out "$REMOTE_STORE_DIR/index.json.sig" "$REMOTE_STORE_DIR/index.json"
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
for _ in range(8):
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
python3 - "$WS_PORT" "$WS_READY" > "$LOG_DIR/libavm_ios_sdk_ws_server.log" 2>&1 <<'PY' &
import base64
import hashlib
import pathlib
import socket
import sys

port = int(sys.argv[1])
ready = pathlib.Path(sys.argv[2])

def recv_exact(conn, n):
    out = bytearray()
    while len(out) < n:
        chunk = conn.recv(n - len(out))
        if not chunk:
            raise RuntimeError("short read")
        out.extend(chunk)
    return bytes(out)

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port))
srv.listen(1)
ready.write_text("ready\n", encoding="utf-8")
conn, _addr = srv.accept()
try:
    header = bytearray()
    while b"\r\n\r\n" not in header:
        chunk = conn.recv(1024)
        if not chunk:
            raise RuntimeError("closed before handshake")
        header.extend(chunk)
    key = None
    for line in header.decode("ascii", "strict").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
            break
    if not key:
        raise RuntimeError("missing websocket key")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()).decode("ascii")
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
    )
    conn.sendall(response.encode("ascii"))
    h = recv_exact(conn, 2)
    opcode = h[0] & 0x0f
    length = h[1] & 0x7f
    if length == 126:
        ext = recv_exact(conn, 2)
        length = (ext[0] << 8) | ext[1]
    elif length == 127:
        raise RuntimeError("64-bit websocket length unsupported in verifier")
    mask = recv_exact(conn, 4) if (h[1] & 0x80) else b"\x00\x00\x00\x00"
    payload = bytearray(recv_exact(conn, length))
    for i in range(len(payload)):
        payload[i] ^= mask[i & 3]
    if opcode != 1 or bytes(payload) != b"ping":
        raise RuntimeError("unexpected websocket payload")
    conn.sendall(b"\x81\x04pong")
finally:
    conn.close()
    srv.close()
PY
WS_SERVER_PID=$!
python3 - "$PKG_PORT" "$REMOTE_STORE_DIR" "$PKG_READY" > "$LOG_DIR/libavm_ios_sdk_package_http_server.log" 2>&1 <<'PY' &
import functools
import http.server
import pathlib
import socketserver
import sys

port = int(sys.argv[1])
root = pathlib.Path(sys.argv[2])
ready = pathlib.Path(sys.argv[3])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
with socketserver.TCPServer(("127.0.0.1", port), handler) as srv:
    ready.write_text("ready\n", encoding="utf-8")
    srv.serve_forever()
PY
PKG_SERVER_PID=$!
OBC_STORE_ADMIN_USERNAME=admin \
OBC_STORE_ADMIN_PASSWORD=secret \
OBC_STORE_INDEX_SIGN_KEY_PEM="$PACKAGE_SIGN_KEY" \
  "$GO_STORE_SERVER_BIN" -addr "127.0.0.1:${GO_STORE_PORT}" -data-dir "$GO_STORE_DIR" > "$LOG_DIR/libavm_ios_sdk_obc_store_server.log" 2>&1 &
GO_STORE_PID=$!
python3 - "$GO_STORE_PORT" "$GO_STORE_DIR" "$PACKAGE_OBC_OUT" "$PACKAGE_SIGN_KEY" > "$LOG_DIR/libavm_ios_sdk_obc_store_publish.log" 2>&1 <<'PY'
import base64
import hashlib
import http.client
import io
import json
import pathlib
import subprocess
import sys
import time
import urllib.request
import zipfile

port = int(sys.argv[1])
data_dir = pathlib.Path(sys.argv[2])
obc_path = pathlib.Path(sys.argv[3])
sign_key = pathlib.Path(sys.argv[4])
base = f"http://127.0.0.1:{port}"

for _ in range(100):
    try:
        with urllib.request.urlopen(base + "/api/v0/health", timeout=0.2) as resp:
            if resp.status == 200:
                break
    except Exception:
        time.sleep(0.05)
else:
    raise SystemExit("obc-store service did not become ready")

def post(path, payload, authorization):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(base + path, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", authorization)
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

admin_auth = "Basic " + base64.b64encode(b"admin:secret").decode("ascii")
publisher_token = "sdk-service-publisher-token"
publisher_auth = "Bearer " + publisher_token

pub = subprocess.check_output(
    [
        "python3",
        "-",
        str(sign_key),
    ],
    input=b"""import base64, subprocess, sys
der = subprocess.check_output(["openssl", "ec", "-in", sys.argv[1], "-pubout", "-outform", "DER"], stderr=subprocess.DEVNULL)
idx = der.rfind(b"\\x03\\x42\\x00\\x04")
pub = der[idx + 3:idx + 68]
print(base64.b64encode(pub).decode("ascii"))
""",
).decode("ascii").strip()

post("/api/v0/publishers", {"id": "oren-labs", "display_name": "Oren Labs", "public_keys": [pub], "token_sha256_hex": hashlib.sha256(publisher_token.encode("utf-8")).hexdigest()}, admin_auth)
post("/api/v0/packages", {"publisher": "oren-labs", "name": "sdk-package-service", "title": "SDK Service Package Smoke", "summary": "Verifies SDK install from obc-store-server", "tags": ["sdk", "service"]}, publisher_auth)
manifest_for_bundle = {
    "schema": "oren.obc.package.v0",
    "name": "sdk-package-service",
    "publisher": "oren-labs",
    "version": "0.1.0",
    "title": "SDK Service Package Smoke",
    "summary": "Verifies SDK install from obc-store-server",
    "entry_obc": "program.obc",
    "obc_sha256": hashlib.sha256(obc_path.read_bytes()).hexdigest(),
    "oren_min": "0.0.rolling",
    "avm_abi_min": 8,
    "capabilities": ["CORE", "FS", "EXIT"],
    "time_mode": "deterministic",
    "budgets": {
        "gas": 5000000,
        "heap_bytes": 33554432,
        "io_bytes": 1048576,
        "frame_commands": 1024,
    },
    "vfs_mounts": [
        {"virtual": "assets", "package_path": "assets", "read_only": True}
    ],
    "assets": [
        {
            "path": "assets/config.txt",
            "sha256": hashlib.sha256(b"pkg-asset").hexdigest(),
            "size": len(b"pkg-asset"),
            "media_type": "text/plain",
        }
    ],
}
bundle_io = io.BytesIO()
with zipfile.ZipFile(bundle_io, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name, body in [
        ("package.json", (json.dumps(manifest_for_bundle, indent=2, sort_keys=True) + "\n").encode("utf-8")),
        ("program.obc", obc_path.read_bytes()),
        ("assets/config.txt", b"pkg-asset"),
        ("assets/source/main.oren", b"print(\"service-bundle-source\")\n"),
    ]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, body)
release = post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions",
    {
        "version": "0.1.0",
        "program_obc_base64": base64.b64encode(obc_path.read_bytes()).decode("ascii"),
        "release_bundle_base64": base64.b64encode(bundle_io.getvalue()).decode("ascii"),
        "tags": ["sdk", "service"],
        "min_app": "0.1.0",
        "manifest": {
            "title": "SDK Service Package Smoke",
            "summary": "Verifies SDK install from obc-store-server",
            "oren_min": "0.0.rolling",
            "avm_abi_min": 8,
            "capabilities": ["CORE", "FS", "EXIT"],
            "time_mode": "deterministic",
            "budgets": {
                "gas": 5000000,
                "heap_bytes": 33554432,
                "io_bytes": 1048576,
                "frame_commands": 1024,
            },
            "vfs_mounts": [
                {"virtual": "assets", "package_path": "assets", "read_only": True}
            ],
        },
        "assets": [
            {
                "path": "assets/config.txt",
                "media_type": "text/plain",
                "content_base64": base64.b64encode(b"pkg-asset").decode("ascii"),
            }
        ],
    },
    publisher_auth,
)
msg = data_dir / "manifest_hash.txt"
sig = data_dir / "manifest_hash.sig"
msg.write_text(release["manifest_sha256"], encoding="utf-8")
subprocess.check_call(["openssl", "dgst", "-sha256", "-sign", str(sign_key), "-out", str(sig), str(msg)], stdout=subprocess.DEVNULL)
post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions/0.1.0/publish",
    {
        "signature_alg": "p256-sha256-der",
        "signature_p256_sha256_der_hex": sig.read_bytes().hex(),
    },
    publisher_auth,
)
manifest_for_bundle_v2 = dict(manifest_for_bundle)
manifest_for_bundle_v2["version"] = "0.2.0"
manifest_for_bundle_v2["title"] = "SDK Service Package Smoke v2"
manifest_for_bundle_v2["summary"] = "Verifies SDK update status from obc-store-server"
bundle_io_v2 = io.BytesIO()
with zipfile.ZipFile(bundle_io_v2, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for name, body in [
        ("package.json", (json.dumps(manifest_for_bundle_v2, indent=2, sort_keys=True) + "\n").encode("utf-8")),
        ("program.obc", obc_path.read_bytes()),
        ("assets/config.txt", b"pkg-asset"),
        ("assets/source/main.oren", b"print(\"service-bundle-source\")\n"),
    ]:
        info = zipfile.ZipInfo(name)
        info.date_time = (2026, 1, 1, 0, 0, 0)
        info.compress_type = zipfile.ZIP_DEFLATED
        zf.writestr(info, body)
release_v2 = post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions",
    {
        "version": "0.2.0",
        "program_obc_base64": base64.b64encode(obc_path.read_bytes()).decode("ascii"),
        "release_bundle_base64": base64.b64encode(bundle_io_v2.getvalue()).decode("ascii"),
        "tags": ["sdk", "service", "update"],
        "min_app": "0.1.0",
        "manifest": {
            "title": "SDK Service Package Smoke v2",
            "summary": "Verifies SDK update status from obc-store-server",
            "oren_min": "0.0.rolling",
            "avm_abi_min": 8,
            "capabilities": ["CORE", "FS", "EXIT"],
            "time_mode": "deterministic",
            "budgets": {
                "gas": 5000000,
                "heap_bytes": 33554432,
                "io_bytes": 1048576,
                "frame_commands": 1024,
            },
            "vfs_mounts": [
                {"virtual": "assets", "package_path": "assets", "read_only": True}
            ],
        },
        "assets": [
            {
                "path": "assets/config.txt",
                "media_type": "text/plain",
                "content_base64": base64.b64encode(b"pkg-asset").decode("ascii"),
            }
        ],
    },
    publisher_auth,
)
msg.write_text(release_v2["manifest_sha256"], encoding="utf-8")
subprocess.check_call(["openssl", "dgst", "-sha256", "-sign", str(sign_key), "-out", str(sig), str(msg)], stdout=subprocess.DEVNULL)
post(
    "/api/v0/packages/oren-labs/sdk-package-service/versions/0.2.0/publish",
    {
        "signature_alg": "p256-sha256-der",
        "signature_p256_sha256_der_hex": sig.read_bytes().hex(),
    },
    publisher_auth,
)
PY
cleanup_net_server() {
  stop_pid "${NET_SERVER_PID:-}"
  stop_pid "${TCP_SERVER_PID:-}"
  stop_pid "${UDP_SERVER_PID:-}"
  stop_pid "${WS_SERVER_PID:-}"
  stop_pid "${PKG_SERVER_PID:-}"
  stop_pid "${GO_STORE_PID:-}"
}
trap cleanup_net_server EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -f "$NET_READY" && -f "$TCP_READY" && -f "$UDP_READY" && -f "$WS_READY" && -f "$PKG_READY" ]]; then
    break
  fi
  sleep 0.1
done
OREN_AVM_SDK_NET_PREFETCH=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="http://127.0.0.1:${NET_PORT}" \
OREN_AVM_SDK_PACKAGE_DIR="$PACKAGE_DIR" \
OREN_AVM_SDK_SCENE_PACKAGE_DIR="$SCENE_PACKAGE_DIR" \
OREN_AVM_SDK_PACKAGE_INDEX_URL="http://127.0.0.1:${PKG_PORT}/index.json" \
OREN_AVM_SDK_PACKAGE_DOWNLOAD_DIR="$TMP_DIR/downloaded_packages" \
OREN_AVM_SDK_SERVICE_PACKAGE_INDEX_URL="http://127.0.0.1:${GO_STORE_PORT}/api/v0/index.json" \
OREN_AVM_SDK_SERVICE_PACKAGE_DOWNLOAD_DIR="$TMP_DIR/downloaded_service_packages" \
OREN_AVM_SDK_STORE_INDEX_KEY_B64="$PACKAGE_PUBLISHER_KEY_B64" \
OREN_AVM_SDK_BAD_STORE_INDEX_KEY_B64="$BAD_STORE_INDEX_KEY_B64" \
OREN_AVM_SDK_PACKAGE_PUBLISHER_KEY_B64="$PACKAGE_PUBLISHER_KEY_B64" \
OREN_AVM_SDK_TRUST_BUNDLE_PATH="$TRUST_BUNDLE_JSON" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOST="http://127.0.0.1:${NET_PORT}" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:${TCP_PORT}" OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:$((TCP_PORT + 1))" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" OREN_AVM_SDK_EXPECT_EXIT=57 "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp://127.0.0.1:${TCP_PORT}" \
OREN_AVM_SDK_TCP_URL="tcp://127.0.0.1:${TCP_PORT}" \
OREN_AVM_SDK_SESSION_BYTE_LIMIT=7 \
OREN_AVM_SDK_EXPECT_EXIT=60 \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},udp://127.0.0.1:${UDP_PORT}" \
OREN_AVM_SDK_TCP_URL="udp://127.0.0.1:${UDP_PORT}" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},ws://127.0.0.1:${WS_PORT}" \
OREN_AVM_SDK_TCP_URL="ws://127.0.0.1:${WS_PORT}/echo" \
  "$HOST_SDK_BIN"
OREN_AVM_SDK_NET_DEFAULT_LIVE=1 \
OREN_AVM_SDK_NET_URL="http://127.0.0.1:${NET_PORT}/net.txt" \
OREN_AVM_SDK_NET_ALLOWED_HOSTS="http://127.0.0.1:${NET_PORT},tcp-listen://127.0.0.1:${TCP_LISTEN_PORT}" \
OREN_AVM_SDK_TCP_LISTEN_URL="tcp-listen://127.0.0.1:${TCP_LISTEN_PORT}" \
  "$HOST_SDK_BIN" > "$LOG_DIR/libavm_ios_sdk_tcp_listen_host.log" 2>&1 &
TCP_LISTEN_HOST_PID=$!
python3 - "$TCP_LISTEN_PORT" > "$LOG_DIR/libavm_ios_sdk_tcp_listen_client.log" 2>&1 <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
last = None
for _ in range(100):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2) as s:
            s.sendall(b"ping")
            data = s.recv(4)
            if data != b"pong":
                raise RuntimeError(f"unexpected response: {data!r}")
            sys.exit(0)
    except Exception as exc:
        last = exc
        time.sleep(0.05)
raise SystemExit(f"tcp listen verifier client failed: {last}")
PY
wait "$TCP_LISTEN_HOST_PID"
cleanup_net_server
trap - EXIT

echo "libavm iOS verify OK"
