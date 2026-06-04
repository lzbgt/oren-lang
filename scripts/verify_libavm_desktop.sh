#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/desktop}"
TMP_DIR="build/tmp/libavm_desktop_verify"
LOG_DIR="build/logs"
mkdir -p "$TMP_DIR" "$LOG_DIR"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$OREN_COMPILER" ]]; then
  make oren > "$LOG_DIR/make_oren_for_libavm_desktop_verify.log" 2>&1
fi

./scripts/build_libavm_desktop.sh > "$LOG_DIR/build_libavm_desktop.log" 2>&1

test -f "$OUT_ROOT/macos-arm64/libavm.a"
test -f "$OUT_ROOT/macos-x86_64/libavm.a"
test -f "$OUT_ROOT/macos-universal/libavm.a"
test -d "$OUT_ROOT/LibAVM.xcframework"
test -f "$OUT_ROOT/include/avm_embed.h"
test -f "$OUT_ROOT/include/module.modulemap"

lipo -info "$OUT_ROOT/macos-arm64/libavm.a" | grep -F arm64 >/dev/null
lipo -info "$OUT_ROOT/macos-x86_64/libavm.a" | grep -F x86_64 >/dev/null
lipo -info "$OUT_ROOT/macos-universal/libavm.a" | grep -F arm64 >/dev/null
lipo -info "$OUT_ROOT/macos-universal/libavm.a" | grep -F x86_64 >/dev/null
nm -g "$OUT_ROOT/macos-arm64/libavm.a" | grep -F _avm_embed_run_obc_bytes >/dev/null
nm -g "$OUT_ROOT/macos-x86_64/libavm.a" | grep -F _avm_embed_run_obc_bytes >/dev/null
find "$OUT_ROOT/LibAVM.xcframework" -name libavm.a -print | grep -q .

OREN_SRC="$TMP_DIR/desktop_embed_smoke.oren"
BLOCKING_OREN_SRC="$TMP_DIR/desktop_embed_blocking_net.oren"
OBC_OUT="$TMP_DIR/desktop_embed_smoke.obc"
BLOCKING_OBC_OUT="$TMP_DIR/desktop_embed_blocking_net.obc"
SMOKE_C="$TMP_DIR/desktop_embed_smoke.c"
SMOKE_BIN="$TMP_DIR/desktop_embed_smoke"
SWIFT_SRC="$TMP_DIR/desktop_embed_smoke.swift"
SWIFT_BIN="$TMP_DIR/desktop_embed_swift_smoke"
SMOKE_LOG="$LOG_DIR/libavm_desktop_embed_smoke.log"
SWIFT_LOG="$LOG_DIR/libavm_desktop_swift_smoke.log"

cat > "$OREN_SRC" <<'OREN'
fn main() {
    print("desktop-libavm-ok")
    oren_exit(0)
}

main()
OREN

"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" \
  > "$LOG_DIR/libavm_desktop_obc_build.log" 2>&1

cat > "$BLOCKING_OREN_SRC" <<'OREN'
import http "std:net/avm/http"

fn main() {
    var resp = http.get("https://example.local/block")
    if oren_is_err(resp) { oren_exit(10) }
    var text = resp.text()
    if oren_is_err(text) { oren_exit(11) }
    if text != "blocked-ok" { oren_exit(12) }
    print(text)
    oren_exit(0)
}

main()
OREN

"$OREN_COMPILER" build "$BLOCKING_OREN_SRC" --backend bytecode -o "$BLOCKING_OBC_OUT" \
  > "$LOG_DIR/libavm_desktop_blocking_net_obc_build.log" 2>&1

cat > "$SMOKE_C" <<'SMOKE'
#include "avm_embed.h"

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_file(const char* path, uint8_t** out_data, size_t* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        return 1;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return 1;
    }
    long len = ftell(f);
    if (len < 0) {
        fclose(f);
        return 1;
    }
    rewind(f);
    uint8_t* data = (uint8_t*)malloc((size_t)len);
    if (!data && len > 0) {
        fclose(f);
        return 1;
    }
    size_t got = fread(data, 1, (size_t)len, f);
    fclose(f);
    if (got != (size_t)len) {
        free(data);
        return 1;
    }
    *out_data = data;
    *out_len = (size_t)len;
    return 0;
}

typedef struct {
    const char* obc_path;
    int worker_id;
} WorkerArg;

typedef struct {
    pthread_mutex_t mu;
    pthread_cond_t cv;
    int entered;
    int release;
} BlockingFetch;

typedef struct {
    AvmEmbedHandle* handle;
    AvmProgram* program;
    AvmEmbedResult result;
    int rc;
} SharedRunArg;

static int blocking_fetch(void* user_data, const char* url, uint8_t** out_data, size_t* out_len) {
    (void)url;
    BlockingFetch* state = (BlockingFetch*)user_data;
    pthread_mutex_lock(&state->mu);
    state->entered = 1;
    pthread_cond_broadcast(&state->cv);
    while (!state->release) {
        pthread_cond_wait(&state->cv, &state->mu);
    }
    pthread_mutex_unlock(&state->mu);

    const char* body = "blocked-ok";
    size_t len = strlen(body);
    uint8_t* copy = (uint8_t*)malloc(len);
    if (!copy) return 1;
    memcpy(copy, body, len);
    *out_data = copy;
    *out_len = len;
    return 0;
}

static void* shared_run_main(void* arg_ptr) {
    SharedRunArg* arg = (SharedRunArg*)arg_ptr;
    arg->rc = avm_embed_run_program(arg->handle, arg->program, &arg->result);
    return NULL;
}

static int run_embed_smoke_once(const char* obc_path, int worker_id) {
    uint8_t* obc = NULL;
    size_t obc_len = 0;
    if (read_file(obc_path, &obc, &obc_len) != 0) return 1;

    AvmEmbedConfig config;
    AvmEmbedResult result;
    avm_embed_config_default(&config);
    avm_embed_result_clear(&result);
    AvmEmbedHandle* handle = avm_embed_open(&config, &result);
    if (!handle) {
        free(obc);
        return 2;
    }
    if (avm_embed_set_output_capture(handle, 1, &result) != AVM_EMBED_OK) {
        avm_embed_close(handle);
        free(obc);
        return 3;
    }
    char vfs_path[64];
    char vfs_body[64];
    snprintf(vfs_path, sizeof(vfs_path), "/thread/%d.txt", worker_id);
    snprintf(vfs_body, sizeof(vfs_body), "worker-%d", worker_id);
    if (avm_embed_vfs_put(handle, vfs_path, (const uint8_t*)vfs_body, strlen(vfs_body), &result) != AVM_EMBED_OK) {
        avm_embed_close(handle);
        free(obc);
        return 4;
    }
    if (avm_embed_run_obc_bytes(handle, obc, obc_len, &result) != AVM_EMBED_OK || result.exit_code != 0) {
        avm_embed_close(handle);
        free(obc);
        return 5;
    }
    uint8_t* out = NULL;
    size_t out_len = 0;
    if (avm_embed_output_get(handle, &out, &out_len, &result) != AVM_EMBED_OK) {
        avm_embed_close(handle);
        free(obc);
        return 6;
    }
    int ok = out && out_len >= strlen("desktop-libavm-ok") &&
             memmem(out, out_len, "desktop-libavm-ok", strlen("desktop-libavm-ok")) != NULL;
    avm_embed_free_bytes(out);
    avm_embed_close(handle);
    free(obc);
    return ok ? 0 : 7;
}

static int verify_same_handle_busy_guard(const char* obc_path) {
    uint8_t* obc = NULL;
    size_t obc_len = 0;
    if (read_file(obc_path, &obc, &obc_len) != 0) return 20;

    AvmEmbedResult result;
    AvmEmbedProgram* program = NULL;
    avm_embed_result_clear(&result);
    if (avm_embed_program_from_obc_bytes(obc, obc_len, 1, &program, &result) != AVM_EMBED_OK) {
        free(obc);
        return 21;
    }

    AvmEmbedConfig config;
    avm_embed_config_default(&config);
    AvmEmbedHandle* handle = avm_embed_open(&config, &result);
    if (!handle) {
        avm_embed_program_free(program);
        free(obc);
        return 22;
    }

    BlockingFetch fetch_state;
    memset(&fetch_state, 0, sizeof(fetch_state));
    pthread_mutex_init(&fetch_state.mu, NULL);
    pthread_cond_init(&fetch_state.cv, NULL);
    if (avm_embed_set_net_fetch_callback(handle, blocking_fetch, &fetch_state, &result) != AVM_EMBED_OK) {
        avm_embed_close(handle);
        avm_embed_program_free(program);
        free(obc);
        return 23;
    }

    SharedRunArg run_arg;
    memset(&run_arg, 0, sizeof(run_arg));
    run_arg.handle = handle;
    run_arg.program = avm_embed_program_view(program);
    pthread_t thread;
    if (pthread_create(&thread, NULL, shared_run_main, &run_arg) != 0) {
        avm_embed_close(handle);
        avm_embed_program_free(program);
        free(obc);
        return 24;
    }

    pthread_mutex_lock(&fetch_state.mu);
    while (!fetch_state.entered) {
        pthread_cond_wait(&fetch_state.cv, &fetch_state.mu);
    }
    pthread_mutex_unlock(&fetch_state.mu);

    AvmEmbedResult busy_result;
    avm_embed_result_clear(&busy_result);
    int busy_rc = avm_embed_run_program(handle, avm_embed_program_view(program), &busy_result);
    int busy_ok = busy_rc == AVM_EMBED_ERR_BUSY &&
                  busy_result.status == AVM_EMBED_ERR_BUSY &&
                  strstr(busy_result.message, "already running") != NULL;

    pthread_mutex_lock(&fetch_state.mu);
    fetch_state.release = 1;
    pthread_cond_broadcast(&fetch_state.cv);
    pthread_mutex_unlock(&fetch_state.mu);

    if (pthread_join(thread, NULL) != 0) {
        avm_embed_close(handle);
        avm_embed_program_free(program);
        free(obc);
        return 25;
    }
    int run_ok = run_arg.rc == AVM_EMBED_OK && run_arg.result.exit_code == 0;

    avm_embed_close(handle);
    avm_embed_program_free(program);
    free(obc);
    pthread_cond_destroy(&fetch_state.cv);
    pthread_mutex_destroy(&fetch_state.mu);
    if (!busy_ok) return 26;
    if (!run_ok) return 27;
    return 0;
}

static void* worker_main(void* arg_ptr) {
    WorkerArg* arg = (WorkerArg*)arg_ptr;
    for (int i = 0; i < 16; i++) {
        int rc = run_embed_smoke_once(arg->obc_path, arg->worker_id * 1000 + i);
        if (rc != 0) return (void*)(intptr_t)rc;
    }
    return (void*)0;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s program.obc blocking-net.obc\n", argv[0]);
        return 2;
    }
    uint8_t* obc = NULL;
    size_t obc_len = 0;
    if (read_file(argv[1], &obc, &obc_len) != 0) {
        fprintf(stderr, "failed to read obc\n");
        return 3;
    }

    AvmEmbedConfig config;
    AvmEmbedResult result;
    avm_embed_config_default(&config);
    avm_embed_result_clear(&result);
    AvmEmbedHandle* handle = avm_embed_open(&config, &result);
    if (!handle) {
        fprintf(stderr, "open failed: %s\n", result.message);
        free(obc);
        return 4;
    }
    if (avm_embed_set_output_capture(handle, 1, &result) != AVM_EMBED_OK) {
        fprintf(stderr, "capture failed: %s\n", result.message);
        avm_embed_close(handle);
        free(obc);
        return 5;
    }
    if (avm_embed_run_obc_bytes(handle, obc, obc_len, &result) != AVM_EMBED_OK ||
        result.exit_code != 0) {
        fprintf(stderr, "run failed: status=%d exit=%d message=%s\n",
                result.status, result.exit_code, result.message);
        avm_embed_close(handle);
        free(obc);
        return 6;
    }
    uint8_t* out = NULL;
    size_t out_len = 0;
    if (avm_embed_output_get(handle, &out, &out_len, &result) != AVM_EMBED_OK) {
        fprintf(stderr, "output failed: %s\n", result.message);
        avm_embed_close(handle);
        free(obc);
        return 7;
    }
    int ok = out && out_len >= strlen("desktop-libavm-ok") &&
             memmem(out, out_len, "desktop-libavm-ok", strlen("desktop-libavm-ok")) != NULL;
    avm_embed_free_bytes(out);
    avm_embed_close(handle);
    free(obc);
    if (!ok) {
        fprintf(stderr, "missing captured output\n");
        return 8;
    }
    WorkerArg args[2] = {
        { argv[1], 1 },
        { argv[1], 2 },
    };
    pthread_t threads[2];
    for (int i = 0; i < 2; i++) {
        if (pthread_create(&threads[i], NULL, worker_main, &args[i]) != 0) {
            fprintf(stderr, "thread create failed\n");
            return 9;
        }
    }
    for (int i = 0; i < 2; i++) {
        void* thread_status = NULL;
        if (pthread_join(threads[i], &thread_status) != 0) {
            fprintf(stderr, "thread join failed\n");
            return 10;
        }
        int thread_rc = (int)(intptr_t)thread_status;
        if (thread_rc != 0) {
            fprintf(stderr, "thread embed smoke failed: %d\n", thread_rc);
            return 11;
        }
    }
    int busy_rc = verify_same_handle_busy_guard(argv[2]);
    if (busy_rc != 0) {
        fprintf(stderr, "same-handle busy guard failed: %d\n", busy_rc);
        return 12;
    }
    puts("OK: desktop LibAVM C embed smoke passed");
    return 0;
}
SMOKE

case "$(uname -m)" in
  arm64) HOST_SLICE="$OUT_ROOT/macos-arm64/libavm.a" ;;
  x86_64) HOST_SLICE="$OUT_ROOT/macos-x86_64/libavm.a" ;;
  *)
    echo "ERROR: unsupported macOS host arch $(uname -m)" >&2
    exit 2
    ;;
esac

cc -std=c11 -D_DARWIN_C_SOURCE -I"$OUT_ROOT/include" "$SMOKE_C" "$HOST_SLICE" \
  -o "$SMOKE_BIN" > "$LOG_DIR/libavm_desktop_host_compile.log" 2>&1
"$SMOKE_BIN" "$OBC_OUT" "$BLOCKING_OBC_OUT" > "$SMOKE_LOG" 2>&1
grep -F "OK: desktop LibAVM C embed smoke passed" "$SMOKE_LOG" >/dev/null

cat > "$SWIFT_SRC" <<'SWIFT'
import Foundation
import LibAVM

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if CommandLine.arguments.count != 2 {
    fail("usage: desktop_embed_swift_smoke program.obc")
}

let obc = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var config = AvmEmbedConfig()
var result = AvmEmbedResult()
avm_embed_config_default(&config)
avm_embed_result_clear(&result)

guard let handle = avm_embed_open(&config, &result) else {
    fail("open failed")
}
defer {
    avm_embed_close(handle)
}

if avm_embed_set_output_capture(handle, 1, &result) != AVM_EMBED_OK {
    fail("capture failed")
}

let runStatus = obc.withUnsafeBytes { rawBuffer -> Int32 in
    let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress
    return avm_embed_run_obc_bytes(handle, ptr, obc.count, &result)
}
if runStatus != AVM_EMBED_OK || result.exit_code != 0 {
    fail("run failed")
}

var outPtr: UnsafeMutablePointer<UInt8>? = nil
var outLen = 0
if avm_embed_output_get(handle, &outPtr, &outLen, &result) != AVM_EMBED_OK {
    fail("output failed")
}
guard let outPtr else {
    fail("missing output")
}
let outData = Data(bytes: outPtr, count: outLen)
avm_embed_free_bytes(outPtr)
let text = String(data: outData, encoding: .utf8) ?? ""
if !text.contains("desktop-libavm-ok") {
    fail("missing captured output")
}

print("OK: desktop LibAVM Swift embed smoke passed")
SWIFT

swiftc -I"$OUT_ROOT/include" "$SWIFT_SRC" "$HOST_SLICE" \
  -o "$SWIFT_BIN" > "$LOG_DIR/libavm_desktop_swift_compile.log" 2>&1
"$SWIFT_BIN" "$OBC_OUT" > "$SWIFT_LOG" 2>&1
grep -F "OK: desktop LibAVM Swift embed smoke passed" "$SWIFT_LOG" >/dev/null

echo "OK: desktop LibAVM SDK verification passed"
