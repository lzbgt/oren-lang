#!/usr/bin/env bash
set -euo pipefail

OUT_ROOT="${1:?usage: verify_libavm_ios_symbols.sh OUT_ROOT}"

TMP_DIR="${TMPDIR:-/tmp}/oren-ios-symbols.$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

AVM_DEVICE="$TMP_DIR/libavm-iphoneos-arm64.nm"
AVM_SIM="$TMP_DIR/libavm-iphonesimulator-arm64.nm"
KIT_DEVICE="$TMP_DIR/libOrenAVMKit-iphoneos-arm64.nm"
KIT_SIM="$TMP_DIR/libOrenAVMKit-iphonesimulator-arm64.nm"

nm -gU "$OUT_ROOT/iphoneos-arm64/libavm.a" > "$AVM_DEVICE"
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libavm.a" > "$AVM_SIM"
nm -gU "$OUT_ROOT/iphoneos-arm64/libOrenAVMKit.a" > "$KIT_DEVICE"
nm -gU "$OUT_ROOT/iphonesimulator-arm64/libOrenAVMKit.a" > "$KIT_SIM"

grep -q -- '_avm_embed_open' "$AVM_DEVICE"
grep -q -- '_avm_embed_open' "$AVM_SIM"
for sym in \
  _avm_embed_set_argv \
  _avm_embed_config_interactive_default \
  _avm_embed_vfs_put \
  _avm_embed_vfs_get \
  _avm_embed_vfs_snapshot \
  _avm_embed_fs_mount_read \
  _avm_embed_fs_mount_write \
  _avm_embed_fs_mount \
  _avm_embed_vnet_put \
  _avm_embed_set_net_fetch_callback \
  _avm_embed_set_net_session_callbacks \
  _avm_embed_set_net_session_write_typed_callback \
  _avm_embed_set_net_resolve_callback \
  _avm_embed_vproc_put \
  _avm_embed_vproc_set_default_exit \
  _avm_embed_set_output_capture \
  _avm_embed_output_info \
  _avm_embed_output_get \
  _avm_embed_output_clear \
  _avm_embed_set_gfx_frame_callback \
  _avm_embed_gfx_frame_info \
  _avm_embed_gfx_frame_get \
  _avm_embed_gfx_frame_clear \
  _avm_embed_gfx_input_put \
  _avm_embed_gfx_screen_set \
  _avm_embed_permission_request_info \
  _avm_embed_permission_request_get \
  _avm_embed_permission_request_clear \
  _avm_embed_cancel \
  _avm_embed_clear_cancel \
  _avm_embed_free_bytes \
  _avm_runner_config_default \
  _avm_runner_result_clear \
  _avm_runner_result_free \
  _avm_runner_run_obc_bytes; do
  grep -q -- "$sym" "$AVM_DEVICE"
  grep -q -- "$sym" "$AVM_SIM"
done

for cls in \
  OrenAVMRuntime \
  OrenAVMCompilerKit \
  OrenAVMPackageStore \
  OrenAVMPermissionGrantStore \
  OrenAVMGraphicsView \
  OrenAVMMetalView; do
  grep -q -- '_OBJC_CLASS_$_'"$cls" "$KIT_DEVICE"
  grep -q -- '_OBJC_CLASS_$_'"$cls" "$KIT_SIM"
done
