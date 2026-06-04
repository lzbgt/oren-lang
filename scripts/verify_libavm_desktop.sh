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
OBC_OUT="$TMP_DIR/desktop_embed_smoke.obc"
SMOKE_C="$TMP_DIR/desktop_embed_smoke.c"
SMOKE_BIN="$TMP_DIR/desktop_embed_smoke"
SMOKE_LOG="$LOG_DIR/libavm_desktop_embed_smoke.log"

cat > "$OREN_SRC" <<'OREN'
fn main() {
    print("desktop-libavm-ok")
    oren_exit(0)
}

main()
OREN

"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" \
  > "$LOG_DIR/libavm_desktop_obc_build.log" 2>&1

cat > "$SMOKE_C" <<'SMOKE'
#include "avm_embed.h"

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

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s program.obc\n", argv[0]);
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
"$SMOKE_BIN" "$OBC_OUT" > "$SMOKE_LOG" 2>&1
grep -F "OK: desktop LibAVM C embed smoke passed" "$SMOKE_LOG" >/dev/null

echo "OK: desktop LibAVM SDK verification passed"
