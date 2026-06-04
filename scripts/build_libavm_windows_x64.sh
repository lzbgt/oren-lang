#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_ROOT="${OUT_ROOT:-build/libavm/windows-x64}"
ZIG="${ZIG:-zig}"
TARGET="${LIBAVM_WINDOWS_X64_TARGET:-x86_64-windows-gnu}"
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
  mkdir -p "$include_dir" "$OUT_ROOT/lib/$TARGET"
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

main() {
  command -v "$ZIG" >/dev/null || {
    echo "ERROR: zig is required for Windows x64 LibAVM cross build" >&2
    exit 2
  }

  mkdir -p build
  tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc

  rm -rf "$OUT_ROOT/obj" "$OUT_ROOT/lib/$TARGET"
  mkdir -p "$OUT_ROOT/obj" "$OUT_ROOT/lib/$TARGET"
  stage_headers

  local objs=()
  local src base obj
  for src in "${AVM_SOURCES[@]}"; do
    base="$(echo "$src" | sed 's#[/.]#_#g')"
    obj="$OUT_ROOT/obj/${base}.o"
    "$ZIG" cc -target "$TARGET" "${CFLAGS_COMMON[@]}" -c "$src" -o "$obj"
    objs+=("$obj")
  done

  "$ZIG" ar rcs "$OUT_ROOT/lib/$TARGET/libavm.a" "${objs[@]}"
  echo "Built $OUT_ROOT/lib/$TARGET/libavm.a"
}

main "$@"
