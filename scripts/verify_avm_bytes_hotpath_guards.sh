#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin grep

if grep -q 'oren_bytes_unpack(out_buf)\|Fallback to list<int> for AVM runtimes without u8_buf write support' lib/compiler/codegen_bytecode/030_tail.oren; then
  echo "ERROR: bytecode final write path must not unpack the u8_buf artifact into a legacy list<int> fallback" >&2
  exit 1
fi

if grep -q 'avm_call_native2(vm, 1, 3' lib/avm/avm_native_compiler_cases.inc; then
  echo "ERROR: AVM read_u8_buf compiler shim must route to byte-native FS.read_u8_buf, not legacy read_bytes" >&2
  exit 1
fi

if ! grep -q 'legacy_id == 217.*op = 8' lib/avm/avm.h; then
  echo "ERROR: legacy oren_read_u8_buf must map to byte-native FS.read_u8_buf op 8" >&2
  exit 1
fi

if ! grep -q 'if name == "oren_read_u8_buf" { native_domain = AVM_DOMAIN_FS; native_op = 8 }' lib/compiler/codegen_bytecode/010_codegen_a.oren; then
  echo "ERROR: bytecode lowering must emit oren_read_u8_buf as FS.read_u8_buf op 8, not CORE legacy id 217" >&2
  exit 1
fi

if grep -q 'if name == "oren_read_u8_buf" { native_id = 217 }' lib/compiler/codegen_bytecode/010_codegen_a.oren; then
  echo "ERROR: bytecode lowering must not emit oren_read_u8_buf as CORE legacy id 217" >&2
  exit 1
fi

if ! grep -q 'case 8:.*read_u8_buf' lib/avm/avm_native_capability_domain_fs.inc; then
  echo "ERROR: FS capability domain must keep byte-native read_u8_buf op 8" >&2
  exit 1
fi

if grep -q 'var data = oren_read_bytes(path)' lib/std/ui/scene3d.oren; then
  echo "ERROR: std:ui/scene3d binary file loading must use byte-native oren_read_u8_buf" >&2
  exit 1
fi

if grep -q 'oren_read_bytes("build/ex_multiverse_child_net.obc")\|oren_bytes_pack(child_' examples/avm_multiverse_net_demo.oren; then
  echo "ERROR: AVM multiverse demo must load child OBC through byte-native oren_read_u8_buf" >&2
  exit 1
fi

if grep -q 'oren_read_bytes(path)\|oren_list_len(out)' examples/avm_vfs_demo.oren; then
  echo "ERROR: AVM VFS demo must validate byte-native read_u8_buf output directly" >&2
  exit 1
fi

if grep -q 'oren_read_bytes("host/input.txt")\|oren_list_len(b)' tests/fixtures/ios_avm/host_fs_chain.oren; then
  echo "ERROR: iOS host-FS chain fixture must read binary payloads through byte-native oren_read_u8_buf" >&2
  exit 1
fi

if grep -q 'oren_read_bytes(path)\|byte_len(roundtrip)\|byte_get(roundtrip' tests/modules/test_ui_ppm_write.oren; then
  echo "ERROR: PPM write roundtrip fixture must read binary output through byte-native oren_read_u8_buf" >&2
  exit 1
fi

if grep -q 'oren_read_bytes(path)\|oren_list_len(out)\|out\[[0-9]\]' tests/avm/test_vfs_no_host_fs.oren; then
  echo "ERROR: AVM VFS no-host-FS fixture must use byte-native oren_read_u8_buf output" >&2
  exit 1
fi

if grep -q 'oren_read_bytes(\|oren_list_len(b)' \
  tests/native/fixtures/capsule_runtime_fs_read_prog.oren \
  tests/native/fixtures/capsule_runtime_fs_mount_read_prog.oren \
  tests/native/fixtures/capsule_runtime_fs_mount_longest_prog.oren; then
  echo "ERROR: native capsule FS read fixtures must use byte-native oren_read_u8_buf output" >&2
  exit 1
fi

if ! grep -q 'fn read_u8_buf(path)' lib/std/fs.oren || grep -q 'var rb = fs.read_bytes\|var rb2 = fs.read_bytes_under' \
  tests/modules/test_fs_std.oren \
  tests/avm/test_std_fs_vfs.oren; then
  echo "ERROR: std:fs byte-buffer fixtures must use the explicit read_u8_buf facade" >&2
  exit 1
fi

if grep -q 'fn _rtobj_u8_at\|fn _rtobj_read_u32_le\|fn _rtobj_read_u64_le' lib/compiler/native_runtime_obj_cache.oren; then
  echo "ERROR: runtime-object metadata hot path must use shared compiler byte_view readers" >&2
  exit 1
fi

if grep -q 'fn _byte_view\|fn _read_u32_le\|fn _read_i32_le' lib/std/ui/commands.oren; then
  echo "ERROR: std:ui/commands validation must use shared std:bytes views directly" >&2
  exit 1
fi

if grep -q 'fn _read_byte\|fn _read_u32_le\|fn _read_i32_le' lib/std/ui/raster.oren; then
  echo "ERROR: std:ui/raster hot loops must use shared std:bytes view readers directly" >&2
  exit 1
fi

if grep -q 'fn _read_event_u8\|fn _read_u16_le\|fn _read_u32_le\|fn _read_u64_le' lib/std/ui/avm.oren; then
  echo "ERROR: std:ui/avm event decode must use shared std:bytes view readers directly" >&2
  exit 1
fi

if grep -q 'fn _read_u16be\|fn _read_u32be\|fn _read_u64be' lib/std/cbor.oren; then
  echo "ERROR: std:cbor decode must use shared std:bytes big-endian byte-view readers directly" >&2
  exit 1
fi

echo "OK: AVM bytes hotpath source guards passed"
