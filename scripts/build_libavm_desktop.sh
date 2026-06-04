#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/desktop}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-11.0}"
CFLAGS_COMMON=(
  -std=c11
  -O3
  -fno-fast-math
  -ffp-contract=off
  -fvisibility=hidden
  -DAVM_EMBED_NO_ABORT_ON_LEAK=1
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

stage_headers() {
  local include_dir="$OUT_ROOT/include"
  mkdir -p "$include_dir"
  cp lib/avm/avm.h "$include_dir/"
  cp lib/avm/avm_embed.h "$include_dir/"
  cp lib/avm/avm_sig.h "$include_dir/"
  cp lib/avm/avm_cert.h "$include_dir/"
  cp lib/avm/sha256.h "$include_dir/"
  cat > "$include_dir/module.modulemap" <<'MODULEMAP'
module LibAVM [extern_c] {
  header "avm.h"
  header "avm_embed.h"
  header "avm_sig.h"
  header "avm_cert.h"
  header "sha256.h"
  export *
}
MODULEMAP
}

compile_one_arch() {
  local arch="$1"
  local target="$2"
  local out_dir="$3"
  local sdk_path
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  local cc
  cc="$(xcrun --sdk macosx --find clang)"
  local libtool
  libtool="$(xcrun --find libtool)"

  rm -rf "$out_dir"
  mkdir -p "$out_dir/obj"

  local objs=()
  local src base obj
  for src in "${AVM_SOURCES[@]}"; do
    base="$(echo "$src" | sed 's#[/.]#_#g')"
    obj="$out_dir/obj/${base}.o"
    "$cc" -target "$target" "-mmacosx-version-min=${MIN_MACOS_VERSION}" \
      -isysroot "$sdk_path" "${CFLAGS_COMMON[@]}" -c "$src" -o "$obj"
    objs+=("$obj")
  done

  "$libtool" -static -o "$out_dir/libavm.a" "${objs[@]}"
  lipo -info "$out_dir/libavm.a" | grep -F "$arch" >/dev/null
}

main() {
  mkdir -p build
  tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc

  stage_headers
  compile_one_arch arm64 "arm64-apple-macos${MIN_MACOS_VERSION}" "$OUT_ROOT/macos-arm64"
  compile_one_arch x86_64 "x86_64-apple-macos${MIN_MACOS_VERSION}" "$OUT_ROOT/macos-x86_64"
  rm -rf "$OUT_ROOT/macos-universal"
  mkdir -p "$OUT_ROOT/macos-universal"
  lipo -create \
    "$OUT_ROOT/macos-arm64/libavm.a" \
    "$OUT_ROOT/macos-x86_64/libavm.a" \
    -output "$OUT_ROOT/macos-universal/libavm.a"
  lipo -info "$OUT_ROOT/macos-universal/libavm.a" | grep -F arm64 >/dev/null
  lipo -info "$OUT_ROOT/macos-universal/libavm.a" | grep -F x86_64 >/dev/null

  rm -rf "$OUT_ROOT/LibAVM.xcframework"
  xcodebuild -create-xcframework \
    -library "$OUT_ROOT/macos-universal/libavm.a" -headers "$OUT_ROOT/include" \
    -output "$OUT_ROOT/LibAVM.xcframework" >/dev/null

  echo "Built $OUT_ROOT/LibAVM.xcframework"
}

main "$@"
