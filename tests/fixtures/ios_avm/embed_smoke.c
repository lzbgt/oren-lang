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
