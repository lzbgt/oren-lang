#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/ios}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-13.0}"
CFLAGS_COMMON=(
  -std=c11
  -O3
  -fno-fast-math
  -ffp-contract=off
  -fvisibility=hidden
  -DAVM_EMBED_NO_ABORT_ON_LEAK=1
  -DAVM_IOS_EMBED=1
  -Ilib/avm
  -Ibuild
)

AVM_SOURCES=()
while IFS= read -r src; do
  AVM_SOURCES+=("$src")
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

OREN_AVM_KIT_SOURCES=(
  sdk/ios/OrenAVMKit/OrenAVMKit.m
  sdk/ios/OrenAVMKit/OrenAVMPackageStore.m
  sdk/ios/OrenAVMKit/OrenAVMPermissionGrantStore.m
)

stage_headers() {
  local include_dir="$OUT_ROOT/include"
  mkdir -p "$include_dir"
  cp lib/avm/avm.h "$include_dir/"
  cp lib/avm/avm_embed.h "$include_dir/"
  cp lib/avm/avm_sig.h "$include_dir/"
  cp lib/avm/avm_cert.h "$include_dir/"
  cp lib/avm/sha256.h "$include_dir/"
  cp sdk/ios/OrenAVMKit/module.modulemap "$include_dir/"
  mkdir -p "$include_dir/OrenAVMKit"
  cp sdk/ios/OrenAVMKit/OrenAVMKit.h "$include_dir/OrenAVMKit/"
}

compile_one_platform() {
  local sdk="$1"
  local target="$2"
  local min_flag="$3"
  local out_dir="$4"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local cc
  cc="$(xcrun --sdk "$sdk" --find clang)"
  local libtool
  libtool="$(xcrun --find libtool)"

  rm -rf "$out_dir"
  mkdir -p "$out_dir/obj"

  local objs=()
  local src base obj
  for src in "${AVM_SOURCES[@]}"; do
    base="$(echo "$src" | sed 's#[/.]#_#g')"
    obj="$out_dir/obj/${base}.o"
    "$cc" -target "$target" "$min_flag" -isysroot "$sdk_path" "${CFLAGS_COMMON[@]}" -c "$src" -o "$obj"
    objs+=("$obj")
  done

  "$libtool" -static -o "$out_dir/libavm.a" "${objs[@]}"
}

compile_kit_one_platform() {
  local sdk="$1"
  local target="$2"
  local min_flag="$3"
  local out_dir="$4"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local cc
  cc="$(xcrun --sdk "$sdk" --find clang)"
  local libtool
  libtool="$(xcrun --find libtool)"

  mkdir -p "$out_dir/obj"

  local objs=()
  local src base obj
  for src in "${OREN_AVM_KIT_SOURCES[@]}"; do
    base="$(echo "$src" | sed 's#[/.]#_#g')"
    obj="$out_dir/obj/${base}.o"
    "$cc" -target "$target" "$min_flag" -isysroot "$sdk_path" \
      -fobjc-arc -fvisibility=hidden \
      -I"$OUT_ROOT/include" -I"$OUT_ROOT/include/OrenAVMKit" \
      -c "$src" -o "$obj"
    objs+=("$obj")
  done

  "$libtool" -static -o "$out_dir/libOrenAVMKit.a" "${objs[@]}"
}

main() {
  mkdir -p build
  tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc

  stage_headers
  compile_one_platform iphoneos "arm64-apple-ios${MIN_IOS_VERSION}" "-miphoneos-version-min=${MIN_IOS_VERSION}" "$OUT_ROOT/iphoneos-arm64"
  compile_one_platform iphonesimulator "arm64-apple-ios${MIN_IOS_VERSION}-simulator" "-mios-simulator-version-min=${MIN_IOS_VERSION}" "$OUT_ROOT/iphonesimulator-arm64"
  compile_kit_one_platform iphoneos "arm64-apple-ios${MIN_IOS_VERSION}" "-miphoneos-version-min=${MIN_IOS_VERSION}" "$OUT_ROOT/iphoneos-arm64"
  compile_kit_one_platform iphonesimulator "arm64-apple-ios${MIN_IOS_VERSION}-simulator" "-mios-simulator-version-min=${MIN_IOS_VERSION}" "$OUT_ROOT/iphonesimulator-arm64"

  rm -rf "$OUT_ROOT/LibAVM.xcframework"
  rm -rf "$OUT_ROOT/OrenAVMKit.xcframework"
  xcodebuild -create-xcframework \
    -library "$OUT_ROOT/iphoneos-arm64/libavm.a" -headers "$OUT_ROOT/include" \
    -library "$OUT_ROOT/iphonesimulator-arm64/libavm.a" -headers "$OUT_ROOT/include" \
    -output "$OUT_ROOT/LibAVM.xcframework" >/dev/null
  xcodebuild -create-xcframework \
    -library "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" -headers "$OUT_ROOT/include" \
    -library "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" -headers "$OUT_ROOT/include" \
    -output "$OUT_ROOT/OrenAVMKit.xcframework" >/dev/null

  echo "Built $OUT_ROOT/LibAVM.xcframework"
  echo "Built $OUT_ROOT/OrenAVMKit.xcframework"
}

main "$@"
