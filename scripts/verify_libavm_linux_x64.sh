#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/linux-x64}"
TMP_DIR="build/tmp/libavm_linux_x64_verify"
LOG_DIR="build/logs"
ZIG="${ZIG:-zig}"
TARGET="${LIBAVM_LINUX_X64_TARGET:-x86_64-linux-gnu}"
REQUIRE_RUN="${VERIFY_LIBAVM_LINUX_X64_REQUIRE_RUN:-0}"
mkdir -p "$TMP_DIR" "$LOG_DIR"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
if [[ ! -x "$OREN_COMPILER" ]]; then
  make oren > "$LOG_DIR/make_oren_for_libavm_linux_x64_verify.log" 2>&1
fi

./scripts/build_libavm_linux_x64.sh > "$LOG_DIR/build_libavm_linux_x64.log" 2>&1

LIB="$OUT_ROOT/lib/$TARGET/libavm.a"
OBJ="$OUT_ROOT/obj/lib_avm_avm_embed_c.o"
test -f "$LIB"
test -f "$OBJ"
test -f "$OUT_ROOT/include/avm_embed.h"
test -f "$OUT_ROOT/include/avm_runner.h"
test -f "$OUT_ROOT/include/module.modulemap"
test -f "$OUT_ROOT/lib/pkgconfig/libavm.pc"

file "$OBJ" | grep -E 'ELF 64-bit.*(x86-64|x86_64)' >/dev/null
strings "$LIB" | grep -F avm_embed_open >/dev/null
strings "$LIB" | grep -F avm_embed_run_obc_bytes >/dev/null
strings "$LIB" | grep -F avm_runner_run_obc_bytes >/dev/null

OREN_SRC="$TMP_DIR/linux_x64_embed_smoke.oren"
OBC_OUT="$TMP_DIR/linux_x64_embed_smoke.obc"
SMOKE_C="$TMP_DIR/linux_x64_embed_smoke.c"
SMOKE_BIN="$TMP_DIR/linux_x64_embed_smoke"
SMOKE_LOG="$LOG_DIR/libavm_linux_x64_embed_smoke.log"

cat > "$OREN_SRC" <<'OREN'
fn main() {
    print("linux-x64-libavm-ok")
    oren_exit(0)
}

main()
OREN

"$OREN_COMPILER" build "$OREN_SRC" --backend bytecode -o "$OBC_OUT" \
  > "$LOG_DIR/libavm_linux_x64_obc_build.log" 2>&1

cat > "$SMOKE_C" <<'SMOKE'
#include "avm_runner.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_file(const char* path, uint8_t** out_data, size_t* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) return 1;
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

static int contains_bytes(const uint8_t* hay, size_t hay_len, const char* needle) {
    size_t needle_len = strlen(needle);
    if (needle_len == 0 || hay_len < needle_len) return 0;
    for (size_t i = 0; i <= hay_len - needle_len; i++) {
        if (memcmp(hay + i, needle, needle_len) == 0) return 1;
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    uint8_t* obc = NULL;
    size_t obc_len = 0;
    if (read_file(argv[1], &obc, &obc_len) != 0) return 3;

    const char* avm_argv[] = {"linux-x64-runner"};
    AvmRunnerConfig config;
    AvmRunnerResult result;
    avm_runner_config_default(&config);
    config.argc = 1;
    config.argv = avm_argv;
    int rc = avm_runner_run_obc_bytes(obc, obc_len, &config, &result);
    free(obc);
    if (rc != AVM_EMBED_OK || result.embed_result.exit_code != 0) {
        avm_runner_result_free(&result);
        return 6;
    }
    int ok = result.output_data && contains_bytes(result.output_data, result.output_len, "linux-x64-libavm-ok");
    avm_runner_result_free(&result);
    if (!ok) return 8;
    puts("OK: Linux x64 LibAVM C embed smoke passed");
    return 0;
}
SMOKE

"$ZIG" cc -target "$TARGET" -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200112L -I"$OUT_ROOT/include" "$SMOKE_C" "$LIB" \
  -o "$SMOKE_BIN" > "$LOG_DIR/libavm_linux_x64_host_compile.log" 2>&1
file "$SMOKE_BIN" | grep -E 'ELF 64-bit.*(x86-64|x86_64)' >/dev/null

if command -v qemu-x86_64 >/dev/null; then
  qemu-x86_64 "$SMOKE_BIN" "$OBC_OUT" > "$SMOKE_LOG" 2>&1
  grep -F "OK: Linux x64 LibAVM C embed smoke passed" "$SMOKE_LOG" >/dev/null
elif [[ "$REQUIRE_RUN" == "1" ]]; then
  echo "ERROR: qemu-x86_64 is required for Linux x64 runtime smoke" >&2
  exit 2
else
  echo "note: qemu-x86_64 not found; Linux x64 runtime smoke skipped" > "$SMOKE_LOG"
fi

echo "OK: Linux x64 LibAVM SDK verification passed"
