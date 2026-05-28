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
test -d "$OUT_ROOT/LibAVM.xcframework"
test -f "$OUT_ROOT/include/avm_embed.h"

nm -gU "$OUT_ROOT/iphoneos-arm64/libavm.a" | grep -q '_avm_embed_open'
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libavm.a" | grep -q '_avm_embed_open'

OREN_SRC="$TMP_DIR/embed_chain.oren"
OBC_OUT="$TMP_DIR/embed_chain.obc"
OBC_HEADER="$TMP_DIR/embed_chain_obc.h"
cat > "$OREN_SRC" <<'OREN'
fn main() {
    oren_exit(7)
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

int main(void) {
    AvmEmbedConfig cfg;
    AvmEmbedResult result;
    avm_embed_config_default(&cfg);
    AvmEmbedHandle* handle = avm_embed_open(&cfg, &result);
    if (!handle || result.status != AVM_EMBED_OK) return 2;
    if (avm_embed_run_obc_bytes(handle, kEmbedChainObc, kEmbedChainObcLen, &result) != AVM_EMBED_OK) return 3;
    if (result.status != AVM_EMBED_OK || result.exit_code != 7) return 4;
    avm_embed_close(handle);
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

echo "libavm iOS verify OK"
