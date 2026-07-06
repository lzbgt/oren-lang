#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 OUT_ROOT TMP_DIR HOST_BIN HOST_SDK_BIN" >&2
  exit 2
fi

OUT_ROOT="$1"
TMP_DIR="$2"
HOST_BIN="$3"
HOST_SDK_BIN="$4"

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
  -framework Security \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -lz \
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
  -framework Security \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -lz \
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
  -framework Security \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -lz \
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
  -framework Security \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Metal \
  -framework MetalKit \
  -framework QuartzCore \
  -lz \
  -o "$TMP_DIR/sdk_module_smoke_device"

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

clang -std=c11 -O3 -fno-fast-math -ffp-contract=off -DAVM_EMBED_NO_ABORT_ON_LEAK=1 \
  -Ilib/avm -Ibuild -I"$TMP_DIR" -I"$OUT_ROOT/include" \
  "$TMP_DIR/sdk_smoke.m" sdk/ios/OrenAVMKit/OrenAVMKit.m "${HOST_SOURCES[@]}" \
  sdk/ios/OrenAVMKit/OrenAVMCompilerKit.m \
  sdk/ios/OrenAVMKit/OrenAVMGFXInput.m \
  sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m \
  sdk/ios/OrenAVMKit/OrenAVMMetalGeometry.m \
  sdk/ios/OrenAVMKit/OrenAVMMetalPipeline.m \
  sdk/ios/OrenAVMKit/OrenAVMMetalResources.m \
  sdk/ios/OrenAVMKit/OrenAVMPackageStore.m \
  sdk/ios/OrenAVMKit/OrenAVMPermissionGrantStore.m \
  sdk/ios/OrenAVMKit/OrenAVMRuntimeTypes.m \
  -fobjc-arc -framework Foundation -framework Security -lz -o "$HOST_SDK_BIN"
