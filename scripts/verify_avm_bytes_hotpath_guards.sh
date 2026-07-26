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

bytecode_emit_u64_impl="$(sed -n '/fn emit_u64_le/,/fn emit_u32_le/p' lib/compiler/codegen_bytecode/030_tail.oren)"
astbin_u64_impl="$(sed -n '/fn _astbin_write_u64_le_ptr/,/fn _astbin_write_string_ptr/p;/fn _astbin_write_u64_le_v1_ptr/,/Growable v1 writer/p;/fn _astbin_dyn_push_u64_le/,/fn _astbin_dyn_push_string/p;/fn _astbin_read_u64_le/,/fn _astbin_unzigzag/p;/fn _astbin_g_read_u64_le/,/^}/p' lib/compiler/compiler/015_astbin.oren)"
astbin_module_u64_impl="$(sed -n '/fn _astbin_module_dyn_push_u64_le/,/fn _astbin_module_dyn_push_string_raw/p' lib/compiler/compiler/016_astbin_module.oren)"
astbin_string_impl="$(sed -n '/fn _astbin_dyn_push_string/,/fn _astbin_dyn_extend_u8_buf/p' lib/compiler/compiler/015_astbin.oren)"
astbin_module_string_impl="$(sed -n '/fn _astbin_module_dyn_push_string_raw/,/fn _astbin_module_dyn_extend_u8_buf/p' lib/compiler/compiler/016_astbin_module.oren)"
scan_cache_string_impl="$(sed -n '/fn _scan_cache_bytes_push_str/,/fn _scan_cache_bytes_finalize/p' lib/compiler/compiler/012_build_cache.oren)"
if ! grep -Fq 'bytes.bytes_push(out, (n >> 56) & 255)' <<<"$bytecode_emit_u64_impl" ||
  grep -Fq 'while i < 8' <<<"$bytecode_emit_u64_impl" ||
  ! grep -Fq 'off = _astbin_write_u8_ptr(data_ptr, off, (x0 >> 56) & 255)' <<<"$astbin_u64_impl" ||
  ! grep -Fq 'return (b0 & 255) | ((b1 & 255) << 8)' <<<"$astbin_u64_impl" ||
  grep -Fq 'while i < 8' <<<"$astbin_u64_impl" ||
  ! grep -Fq '_astbin_module_dyn_push_u8(b, (x0 >> 56) & 255)' <<<"$astbin_module_u64_impl" ||
  grep -Fq 'while i < 8' <<<"$astbin_module_u64_impl"; then
  echo "ERROR: compiler bytecode/ASTBIN u64 helpers must use straight-line little-endian byte operations, not fixed Oren loops" >&2
  exit 1
fi

if ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(b["buf"], used, s, 0, n)' <<<"$astbin_string_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(b["buf"], used, s, 0, n)' <<<"$astbin_module_string_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(b["buf"], used, s, 0, n)' <<<"$scan_cache_string_impl" ||
  grep -Fq 'ptr_set_byte(iadd(dstp, used + i), oren_string_byte_at_unchecked(s, i) & 255)' <<<"$astbin_string_impl" ||
  grep -Fq 'ptr_set_byte(iadd(dstp, used + i), oren_string_byte_at_unchecked(s, i) & 255)' <<<"$astbin_module_string_impl" ||
  grep -Fq 'ptr_set_byte(iadd(dstp, used + i), oren_string_byte_at_unchecked(s, i) & 255)' <<<"$scan_cache_string_impl"; then
  echo "ERROR: compiler ASTBIN/scan-cache string append helpers must bulk-copy validated string spans, not loop per byte" >&2
  exit 1
fi

bytecode_const_string_impl="$(sed -n '/if c\["type"\] == "String" {/,/if c\["type"\] == "Bytes" {/p' lib/compiler/codegen_bytecode/030_tail.oren)"
bytecode_const_nil_impl="$(sed -n '/if c\["type"\] == "Nil" {/,/if c\["type"\] == "Integer" {/p' lib/compiler/codegen_bytecode/030_tail.oren)"
obc_link_constant_impl="$(sed -n '/fn _emit_constant/,/fn obc_encode_bytes/p' lib/compiler/obc_link.oren)"
if ! grep -Fq 'bytes.bytes_push_u16_le(out, len)' <<<"$bytecode_const_string_impl" ||
  ! grep -Fq 'bytes.bytes_extend_string(out, s)' <<<"$bytecode_const_string_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(s, si)' <<<"$bytecode_const_string_impl"; then
  echo "ERROR: bytecode constant string emission must use byte-builder string extension, not a per-byte string loop" >&2
  exit 1
fi

if ! grep -Fq 'bytes.bytes_extend_zeros(out, 1) // Type NIL' <<<"$bytecode_const_nil_impl" ||
  grep -Fq 'bytes.bytes_push(out, 0) // Type NIL' <<<"$bytecode_const_nil_impl"; then
  echo "ERROR: bytecode NIL constant tags must use byte-builder zero extension, not single zero-byte pushes" >&2
  exit 1
fi

if ! grep -Fq 'bytes_builder.bytes_extend_zeros(out, 1)' lib/compiler/obc_link.oren ||
  ! grep -Fq '_push_zero_byte(out)' <<<"$obc_link_constant_impl" ||
  grep -Fq 'bytes_builder.bytes_push(out, 0)' <<<"$obc_link_constant_impl"; then
  echo "ERROR: OBC linker NIL constant tags must use byte-builder zero extension, not single zero-byte pushes" >&2
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
scene3d_binary_impl="$(cat lib/std/ui/scene3d_binary.oren)"
scene3d_impl="$(cat lib/std/ui/scene3d.oren)"
if ! grep -Fq 'var bin_data = _bin_data(bv)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'var bin_ptr = _bin_ptr(bv)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_u32_le_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_i32_le_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_u8_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(' <<<"$scene3d_binary_impl"; then
  echo "ERROR: std:ui/scene3d_binary must hoist byte-view backing storage for .os3d reads" >&2
  exit 1
fi
if ! grep -Fq 'var out = raw.u8_new_uninit(9)' <<<"$scene3d_impl" ||
  ! grep -Fq 'ptr_set_byte(p, 35)' <<<"$scene3d_impl" ||
  ! grep -Fq 'return oren_string_from_bytes_slice(out, 0, 9)' <<<"$scene3d_impl" ||
  ! grep -Fq 'var out = raw.u8_new_uninit(9)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'return oren_string_from_bytes_slice(out, 0, 9)' <<<"$scene3d_binary_impl" ||
  grep -Fq 'oren_string_slice("0123456789abcdef"' <<<"$scene3d_impl$scene3d_binary_impl" ||
  grep -Fq 'return "#" + _hex_byte' <<<"$scene3d_impl$scene3d_binary_impl"; then
  echo "ERROR: std:ui/scene3d color hex emission must write exact-size u8_buf output, not compose tiny digit strings" >&2
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
ppm_encode_impl="$(sed -n '/fn encode_rgba(rgba, w, h)/,/fn write_rgba_ppm/p' lib/std/ui/ppm.oren)"
ppm_header_impl="$(sed -n '/fn _push_ascii_str/,/fn _digits/p' lib/std/ui/ppm.oren)"
if ! grep -Fq 'var rgba_data = bytes.view_bytes(rgba_view)' <<<"$ppm_encode_impl" ||
  ! grep -Fq 'var rgba_ptr = bytes.view_ptr(rgba_view)' <<<"$ppm_encode_impl" ||
  ! grep -Fq 'var r = bytes.view_get_u8_from(rgba_data, rgba_ptr, rgba_off + 0)' <<<"$ppm_encode_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out["buf"], out["pos"], s, 0, n)' <<<"$ppm_header_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(s, i)' <<<"$ppm_header_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(rgba_view' <<<"$ppm_encode_impl"; then
  echo "ERROR: PPM encoding must bulk-copy header strings, hoist byte-view backing storage, and avoid per-channel view metadata reads" >&2
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

if grep -q 'oren_read_bytes(path)\|oren_list_len(out)\|out\[[0-9]\]' tests/native/test_integration_suite.oren; then
  echo "ERROR: native integration FS smoke must validate byte-native oren_read_u8_buf output" >&2
  exit 1
fi

read_bytes_impl="$(sed -n '/fn oren_read_bytes(path)/,/^}/p' lib/runtime_native/230_binary_io.oren)"
if ! grep -q 'var out = oren_new_list_int(size)' <<<"$read_bytes_impl" ||
  ! grep -q 'ptr_set(iadd(out_buf, (off + i) \* 8), ptr_get_byte(buf + i))' <<<"$read_bytes_impl" ||
  grep -Eq 'malloc\(4096\)|sys_read\(fd, buf, 4096\)|var out = oren_new_list\(0\)|oren_list_push\(out' <<<"$read_bytes_impl"; then
  echo "ERROR: legacy native read_bytes fallback must directly fill a stat-sized LIST_INT, not push through zero-capacity/4KiB/list growth" >&2
  exit 1
fi

write_bytes_impl="$(sed -n '/fn oren_write_bytes(path, bytes)/,/^}/p' lib/runtime_native/230_binary_io.oren)"
if ! grep -Fq 'if list_chunk_len > 65536 { list_chunk_len = 65536 }' <<<"$write_bytes_impl" ||
  ! grep -Fq 'ptr_set_byte(list_chunk + j, bytes[off2 + j])' <<<"$write_bytes_impl" ||
  ! grep -Fq 'var fd = sys_open(rpath, flags, 420)' <<<"$write_bytes_impl" ||
  grep -Fq 'buf = malloc(n)' <<<"$write_bytes_impl" ||
  grep -Fq 'ptr_set_byte(buf + i, v)' <<<"$write_bytes_impl"; then
  echo "ERROR: legacy native write_bytes must validate list input before open and write bounded chunks, not allocate a full-list byte mirror" >&2
  exit 1
fi

host_read_bytes_impl="$(sed -n '/case 18:.*oren_read_bytes/,/case 19:/p' lib/avm/avm_native.inc)"
if ! grep -Fq 'AvmValue out = avm_list_int_new((int)len)' <<<"$host_read_bytes_impl" ||
  ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$host_read_bytes_impl" ||
  ! grep -Fq 'list->items[off + (long)i] = (int64_t)chunk[i]' <<<"$host_read_bytes_impl" ||
  grep -Fq 'buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES)' <<<"$host_read_bytes_impl" ||
  grep -Fq 'list->items[i] = (int64_t)(unsigned char)buf[i]' <<<"$host_read_bytes_impl" ||
  grep -Fq 'AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList)' <<<"$host_read_bytes_impl" ||
  grep -Fq 'list->items[i].type = AVM_VAL_INT' <<<"$host_read_bytes_impl"; then
  echo "ERROR: legacy AVM host read_bytes must fill a directly returned LIST_INT from bounded chunks, not boxed AvmValue list entries or full-file temp buffers" >&2
  exit 1
fi

host_write_bytes_impl="$(sed -n '/case 17:.*oren_write_bytes/,/case 18:/p' lib/avm/avm_native.inc)"
host_write_bytes_helper="$(sed -n '/static int avm_native_bytes_fwrite_span/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
host_write_bytes_validate_helper="$(sed -n '/static int avm_native_bytes_validate_span/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'avm_native_bytes_validate_span(args[1], 0, len' <<<"$host_write_bytes_impl" ||
  ! grep -Fq 'avm_native_bytes_fwrite_span(f, args[1], 0, len' <<<"$host_write_bytes_impl" ||
  ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$host_write_bytes_helper" ||
  ! grep -Fq 'avm_native_bytes_copy_span(bytes, start + off, want, chunk' <<<"$host_write_bytes_helper" ||
  ! grep -Fq 'fwrite(bytes.as.b->data + (size_t)start, 1, (size_t)n, f)' <<<"$host_write_bytes_helper" ||
  ! grep -Fq 'bytes.type == AVM_VAL_LIST_INT' <<<"$host_write_bytes_validate_helper" ||
  ! grep -Fq 'args[1].type == AVM_VAL_LIST_INT' <<<"$host_write_bytes_impl" ||
  ! grep -Fq 'write_bytes: expected list<int 0..255>' <<<"$host_write_bytes_impl" ||
  grep -Fq 'buf = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_BYTES)' <<<"$host_write_bytes_impl" ||
  grep -Fq 'owns_buf' <<<"$host_write_bytes_impl" ||
  grep -Fq 'buf[i] = (uint8_t)list->items[i].as.i' <<<"$host_write_bytes_impl"; then
  echo "ERROR: legacy AVM host write_bytes must validate list input then write bounded stack chunks, not allocate a full-file temp buffer" >&2
  exit 1
fi

c_runtime_read_bytes_impl="$(sed -n '/OrenValue oren_read_bytes(OrenValue path)/,/OrenValue oren_read_u8_buf/p' lib/runtime/050_io_misc.inc)"
if ! grep -Fq 'unsigned char chunk[64 * 1024]' <<<"$c_runtime_read_bytes_impl" ||
  ! grep -Fq 'list->items[off + (int)i] = oren_int((unsigned char)chunk[i])' <<<"$c_runtime_read_bytes_impl" ||
  grep -Fq 'unsigned char* buf = NULL' <<<"$c_runtime_read_bytes_impl" ||
  grep -Fq 'buf = (unsigned char*)malloc((size_t)size)' <<<"$c_runtime_read_bytes_impl" ||
  grep -Fq 'list->items[i] = oren_int((unsigned char)buf[i])' <<<"$c_runtime_read_bytes_impl" ||
  grep -Fq 'oren_list_push' <<<"$c_runtime_read_bytes_impl"; then
  echo "ERROR: legacy C runtime read_bytes must fill boxed compatibility lists from bounded chunks, not full-file temp buffers or list pushes" >&2
  exit 1
fi

c_runtime_write_bytes_impl="$(sed -n '/OrenValue oren_write_bytes(OrenValue path, OrenValue bytes)/,/OrenValue oren_rename/p' lib/runtime/050_io_misc.inc)"
c_runtime_fwrite_helper="$(sed -n '/static int runtime_bytes_fwrite_span(FILE\* f/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
c_runtime_validate_helper="$(sed -n '/static int runtime_bytes_validate_span(OrenValue bytes/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
if ! grep -Fq 'runtime_bytes_validate_span(bytes, 0u, nbytes' <<<"$c_runtime_write_bytes_impl" ||
  ! grep -Fq 'runtime_bytes_fwrite_span(f, bytes, 0u, nbytes' <<<"$c_runtime_write_bytes_impl" ||
  ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$c_runtime_fwrite_helper" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, start + off, want, chunk' <<<"$c_runtime_fwrite_helper" ||
  ! grep -Fq 'fwrite(b->data + start, 1, n, f)' <<<"$c_runtime_fwrite_helper" ||
  ! grep -Fq 'OrenValue it = list->items[start + i]' <<<"$c_runtime_validate_helper" ||
  ! grep -Fq 'FILE *f = fopen(path.as.string_val, "wb");' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'uint8_t* tmp = (uint8_t*)malloc((size_t)nbytes)' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'tmp[i] = (uint8_t)b' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'fwrite(tmp, 1, (size_t)nbytes, f)' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'bytes.as.list_val->items' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'bytes.as.buf_val' <<<"$c_runtime_write_bytes_impl"; then
  echo "ERROR: legacy C runtime write_bytes must validate before open and stream through shared byte-span helpers" >&2
  exit 1
fi
if ! grep -Fq 'invalid write clobbered existing file' tests/modules/test_read_bytes.oren; then
  echo "ERROR: legacy C runtime write_bytes must keep fixture coverage proving invalid byte lists do not clobber existing files" >&2
  exit 1
fi

c_runtime_bytes_len_impl="$(sed -n '/OrenValue oren_bytes_len(OrenValue bytes)/,/OrenValue oren_bytes_from_hex/p' lib/runtime/045_bytes_helpers.inc)"
if ! grep -Fq 'runtime_bytes_len_checked(bytes, &n, &err_msg)' <<<"$c_runtime_bytes_len_impl" ||
  grep -Fq 'OrenList* list = bytes.as.list_val' <<<"$c_runtime_bytes_len_impl" ||
  grep -Fq 'OrenBuf* b = bytes.as.buf_val' <<<"$c_runtime_bytes_len_impl" ||
  ! grep -Fq 'if oren_bytes_len(boxed_len_ok) != 3' tests/modules/test_bytes_set_endian.oren; then
  echo "ERROR: legacy C runtime bytes_len must use the shared byte-carrier length helper with boxed-list fixture coverage" >&2
  exit 1
fi

native_string_slice_impl="$(sed -n '/fn oren_string_from_bytes_slice/,/var g_untracked_strings/p' lib/runtime_native/180_bytes_helpers.oren)"
native_u8_slice_impl="$(sed -n '/fn oren_u8_buf_from_bytes_slice/,/fn oren_bytes_to_string/p' lib/runtime_native/180_bytes_helpers.oren)"
native_string_from_bytes_impl="$(sed -n '/fn oren_string_from_bytes(bytes)/,/fn string_concat/p' lib/runtime_native/160_iteration.oren)"
if ! grep -Fq 'if native_bytes_is_u8_buf(bytes) == true {' <<<"$native_string_slice_impl" ||
  ! grep -Fq 'var count = ptr_get(bytes + 0)' <<<"$native_string_slice_impl" ||
  ! grep -Fq 'if len > 0 { oren_memcpy(out_direct, src + start, len) }' <<<"$native_string_slice_impl" ||
  ! grep -Fq 'if native_bytes_is_u8_buf(bytes) == true {' <<<"$native_u8_slice_impl" ||
  ! grep -Fq 'oren_memcpy(dst, src + start, len)' <<<"$native_u8_slice_impl" ||
  ! grep -Fq 'return oren_string_from_bytes_slice(bytes, 0, ptr_get(bytes + 0))' <<<"$native_string_from_bytes_impl" ||
  ! grep -Fq 'var ub_text = oren_string_from_bytes_slice(ub_ascii, 1, 3)' tests/native/test_bytes_set_endian.oren ||
  ! grep -Fq 'var ub_slice = oren_u8_buf_from_bytes_slice(ub_ascii, 2, 2)' tests/native/test_bytes_set_endian.oren; then
  echo "ERROR: native bytes/string slice helpers must copy u8_buf carriers directly after one span check" >&2
  exit 1
fi

byte_setter_helper="$(sed -n '/static int avm_native_bytes_write_span/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'bytes.type == AVM_VAL_LIST_INT' <<<"$byte_setter_helper" ||
  ! grep -Fq 'list->items[(int)idx + i] = (int64_t)src[i]' <<<"$byte_setter_helper"; then
  echo "ERROR: AVM byte setters must mutate LIST_INT carriers directly through the shared write-span helper" >&2
  exit 1
fi

byte_setter_call_count="$(grep -F 'avm_native_bytes_write_span(args[0], idx, out' lib/avm/avm_native.inc | wc -l | tr -d ' ')"
if [ "${byte_setter_call_count:-0}" -lt 10 ]; then
  echo "ERROR: AVM byte endian setters must route through the shared write-span helper instead of boxed-list-only branches" >&2
  exit 1
fi

byte_reader_helper="$(sed -n '/static int avm_native_bytes_read_u64_span/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'avm_native_bytes_len_checked(bytes, &total, err_msg' <<<"$byte_reader_helper" ||
  ! grep -Fq 'avm_native_byte_span_ok(total, idx, width)' <<<"$byte_reader_helper" ||
  grep -Fq '!list || !avm_native_byte_span_ok((int64_t)list->count, idx, width)' <<<"$byte_reader_helper" ||
  ! grep -Fq 'assert_eq(oren_bytes_get_u64_be(li, 0), 72623859790382856)' tests/avm/test_bytes_set_endian.oren; then
  echo "ERROR: AVM byte endian readers must share bytes/list/LIST_INT length validation before direct carrier reads" >&2
  exit 1
fi

if ! grep -Fq 'assert_eq(oren_bytes_set_u8(li, 0, 170), 170)' tests/avm/test_bytes_set_endian.oren ||
  ! grep -Fq 'assert_eq(oren_bytes_set_i64_le(li, 0, -2), -2)' tests/avm/test_bytes_set_endian.oren; then
  echo "ERROR: AVM byte setter fixtures must cover direct LIST_INT mutation paths" >&2
  exit 1
fi

bytes_len_impl="$(sed -n '/case 32:.*oren_bytes_len/,/case 33:/p' lib/avm/avm_native.inc)"
if ! grep -Fq 'avm_native_bytes_len_checked(args[0], &n, &err_msg' <<<"$bytes_len_impl" ||
  grep -Fq 'AvmList* list = args[0].as.l' <<<"$bytes_len_impl" ||
  grep -Fq 'AvmListInt* list = args[0].as.li' <<<"$bytes_len_impl" ||
  ! grep -Fq 'if oren_bytes_len(from_s_xs) != 2' tests/avm/test_bytes_basic.oren ||
  ! grep -Fq 'if oren_bytes_len(boxed_ok) != 2' tests/avm/test_bytes_basic.oren; then
  echo "ERROR: AVM bytes_len must use the shared bytes/list/LIST_INT length helper and fixture coverage" >&2
  exit 1
fi

std_bytes_impl="$(sed -n '/fn _u16_be_from_ptr/,/fn set_u16_be/p' lib/std/bytes.oren)"
std_u64_le_ptr_impl="$(sed -n '/fn _u64_le_from_ptr/,/fn _u64_be_from_ptr/p' lib/std/bytes.oren)"
std_u64_be_ptr_impl="$(sed -n '/fn _u64_be_from_ptr/,/fn _i16_from_u16/p' lib/std/bytes.oren)"
if ! grep -Fq 'fn _u16_le_from_ptr' <<<"$std_bytes_impl" ||
  ! grep -Fq 'fn _copy_u8_ptr_nonoverlap(dstp, srcp, n)' <<<"$std_bytes_impl" ||
  ! grep -Fq 'return oren_memcpy(dstp, srcp, n)' <<<"$std_bytes_impl" ||
  ! grep -Fq '_copy_u8_ptr_nonoverlap(outp, oren_buf_data_ptr_unchecked(a), na)' <<<"$std_bytes_impl" ||
  ! grep -Fq '_copy_u8_ptr_nonoverlap(outp + na, oren_buf_data_ptr_unchecked(b), nb)' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { srcp = oren_buf_data_ptr_unchecked(bytes) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'b = ptr_get_byte(srcp + i) & 255' <<<"$std_bytes_impl" ||
  ! grep -Fq '_copy_u8_ptr_nonoverlap(dstp + dst_off, srcp + src_off, n)' <<<"$std_bytes_impl" ||
  ! grep -Fq 'fn _u64_le_from_ptr' <<<"$std_bytes_impl" ||
  ! grep -Fq 'fn _u64_be_from_ptr' <<<"$std_bytes_impl" ||
  ! grep -Fq 'fn _i16_from_u16' <<<"$std_bytes_impl" ||
  ! grep -Fq 'fn _i32_from_u32' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u16_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u16_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _i16_from_u16(_u16_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx)) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _i16_from_u16(_u16_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx)) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u32_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u32_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _i32_from_u32(_u32_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx)) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _i32_from_u32(_u32_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx)) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u64_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u64_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$std_bytes_impl" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u64_be_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$(sed -n '/fn get_i64_be/,/fn set_u16_be/p' lib/std/bytes.oren)" ||
  ! grep -Fq 'if oren_is_u8_buf(bytes) == true { return _u64_le_from_ptr(oren_buf_data_ptr_unchecked(bytes), idx) }' <<<"$(sed -n '/fn get_i64_be/,/fn set_u16_be/p' lib/std/bytes.oren)"; then
  echo "ERROR: std:bytes public endian getters, including signed 64-bit getters, must read u8_buf carriers directly after public span validation" >&2
  exit 1
fi

if ! grep -Fq 'ptr_get_byte(p + off + 7) & 255' <<<"$std_u64_be_ptr_impl" ||
  grep -Fq 'while i < 8' <<<"$std_u64_be_ptr_impl"; then
  echo "ERROR: std:bytes big-endian 64-bit pointer reads must be unrolled direct byte loads, not Oren loops" >&2
  exit 1
fi

if ! grep -Fq 'ptr_get_byte(p + off + 7) & 255) << 56' <<<"$std_u64_le_ptr_impl" ||
  grep -Fq 'while i < 8' <<<"$std_u64_le_ptr_impl" ||
  grep -Fq '_u32_le_from_ptr' <<<"$std_u64_le_ptr_impl"; then
  echo "ERROR: std:bytes little-endian 64-bit pointer reads must be unrolled direct byte loads, not Oren loops/helper calls" >&2
  exit 1
fi

std_store_u64_be_impl="$(sed -n '/fn _store_u64_be/,/fn _store_u64_le/p' lib/std/bytes.oren)"
std_store_u64_le_impl="$(sed -n '/fn _store_u64_le/,/fn get_u8/p' lib/std/bytes.oren)"
if ! grep -Fq 'ptr_set_byte(p + 0, (v >> 56) & 255)' <<<"$std_store_u64_be_impl" ||
  ! grep -Fq 'ptr_set_byte(p + 7, v & 255)' <<<"$std_store_u64_be_impl" ||
  ! grep -Fq 'ptr_set_byte(p + 0, v & 255)' <<<"$std_store_u64_le_impl" ||
  ! grep -Fq 'ptr_set_byte(p + 7, (v >> 56) & 255)' <<<"$std_store_u64_le_impl" ||
  grep -Fq 'while i < 8' <<<"$std_store_u64_be_impl" ||
  grep -Fq 'while i < 8' <<<"$std_store_u64_le_impl"; then
  echo "ERROR: std:bytes u8_buf 64-bit endian stores must be unrolled direct byte writes, not Oren loops" >&2
  exit 1
fi

buffer_raw_i64_store_impl="$(sed -n '/fn _store_i64_unchecked_direct/,/fn _store_f32_unchecked_direct/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'ptr_set_byte(data + off + 0, v & 255)' <<<"$buffer_raw_i64_store_impl" ||
  ! grep -Fq 'ptr_set_byte(data + off + 7, (v >> 56) & 255)' <<<"$buffer_raw_i64_store_impl" ||
  grep -Fq 'while i < 8' <<<"$buffer_raw_i64_store_impl"; then
  echo "ERROR: std:buffer raw i64 stores must be unrolled direct byte writes, not Oren loops" >&2
  exit 1
fi

bytecode_codegen_impl="$(sed -n '/if name == "ptr_get"/,/Reflection-ish helpers/p' lib/compiler/codegen_bytecode/010_codegen_a.oren)"
avm_ptr_helper_impl="$(sed -n '/static AvmValue avm_ptr_memcpy_value/,/^}/p' lib/avm/avm_native_ptr_helpers.inc)"
c_runtime_ptr_impl="$(sed -n '/OrenValue oren_memcpy/,/^}/p' lib/runtime/060_ptr_unsafe.inc)"
if ! grep -Fq 'if name == "oren_memcpy" { native_id = 230 }' <<<"$bytecode_codegen_impl" ||
  ! grep -Fq 'static AvmValue avm_ptr_memcpy_value' <<<"$avm_ptr_helper_impl" ||
  ! grep -Fq 'memcpy(dst->data + dst_off, src->data + src_off, (size_t)len)' <<<"$avm_ptr_helper_impl" ||
  ! grep -Fq 'if (dst->readonly)' <<<"$avm_ptr_helper_impl" ||
  ! grep -Fq 'case 230: { // oren_memcpy(dst_ptr, src_ptr, len) -> int' lib/avm/avm_native_compiler_cases.inc ||
  ! grep -Fq 'OrenValue oren_memcpy(OrenValue dst, OrenValue src, OrenValue len);' lib/runtime.h ||
  ! grep -Fq 'memcpy((void*)dst_addr, (const void*)src_addr, (size_t)len.as.int_val)' <<<"$c_runtime_ptr_impl"; then
  echo "ERROR: oren_memcpy must be mapped across bytecode/AVM and C runtime for std:bytes hot paths" >&2
  exit 1
fi

native_byte_order_impl="$(sed -n '/fn oren_bytes_set_u8/,/fn oren_bytes_get_u16_be/p' lib/runtime_native/190_byte_order.oren)"
if ! grep -Fq 'if native_bytes_is_list_int(bytes) == true' <<<"$native_byte_order_impl" ||
  ! grep -Fq 'ptr_set(bufi + idx * 8, v)' <<<"$native_byte_order_impl" ||
  ! grep -Fq 'ptr_set(bufi + (idx + 7) * 8, b7 & 255)' <<<"$native_byte_order_impl"; then
  echo "ERROR: native byte setters must mutate LIST_INT carriers directly like native byte getters" >&2
  exit 1
fi
if ! grep -Fq 'var list_int_overlap = listm.int_new(0)' tests/avm/test_std_bytes_portable.oren ||
  ! grep -Fq 'var overlap_forward = bufferm.u8_from_string("abcdef")' tests/avm/test_std_bytes_portable.oren ||
  ! grep -Fq 'var list_overlap = [97, 98, 99, 100, 101, 102]' tests/avm/test_std_bytes_portable.oren ||
  ! grep -Fq 'assert_streq(bytesm.to_string(overlap_forward), "cdefef", 8797)' tests/native/qi/110_tests_basic_smoke_a.oren ||
  ! grep -Fq 'assert_eq(oren_bytes_set_u16_le(list_int_overlap, 0, 4660), 4660, 8794)' tests/native/qi/110_tests_basic_smoke_a.oren; then
  echo "ERROR: std:bytes copy_into fixtures must cover boxed-list/LIST_INT self-overlap and native LIST_INT setter parity" >&2
  exit 1
fi

bytes_to_hex_impl="$(sed -n '/case 36:.*oren_bytes_to_hex/,/case 40:/p' lib/avm/avm_native_byte_iter_cases.inc)"
bytes_to_hex_helper="$(sed -n '/static AvmValue avm_native_bytes_to_hex_value/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'res = avm_native_bytes_to_hex_value(vm, args[0])' <<<"$bytes_to_hex_impl" ||
  ! grep -Fq 'bytes_to_hex: expected list<int 0..255>' <<<"$bytes_to_hex_helper" ||
  ! grep -Fq 'bytes_to_hex: expected list_int bytes 0..255' <<<"$bytes_to_hex_helper" ||
  grep -Fq 'AvmValue it = list->items[i]' <<<"$bytes_to_hex_impl" ||
  grep -Fq 'int64_t it = list_int->items[i]' <<<"$bytes_to_hex_impl" ||
  ! grep -Fq 'if oren_bytes_to_hex(from_s_xs) != "6f6b"' tests/avm/test_bytes_basic.oren ||
  ! grep -Fq 'if oren_is_err(oren_bytes_to_hex(bad_li)) == false' tests/avm/test_bytes_basic.oren; then
  echo "ERROR: AVM bytes_to_hex must use the shared checked bytes/list/LIST_INT helper and fixture coverage" >&2
  exit 1
fi

string_from_bytes_impl="$(sed -n '/case 44:.*oren_string_from_bytes/,/case 161:/p' lib/avm/avm_native_byte_iter_cases.inc)"
byte_copy_helper="$(sed -n '/static int avm_native_bytes_copy_span/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'bytes.type == AVM_VAL_LIST_INT' <<<"$byte_copy_helper" ||
  ! grep -Fq 'memcpy(dst, bytes.as.b->data + (size_t)start, (size_t)n)' <<<"$byte_copy_helper" ||
  ! grep -Fq 'dst[(size_t)i] = (uint8_t)it' <<<"$byte_copy_helper"; then
  echo "ERROR: AVM byte slice/string helpers must share one checked bytes/list/LIST_INT copy-span helper" >&2
  exit 1
fi

byte_copy_list_int_helper="$(sed -n '/static int avm_native_bytes_copy_span_to_list_int/,/^}/p' lib/avm/avm_native_core_helpers.inc)"
if ! grep -Fq 'bytes.type == AVM_VAL_LIST_INT' <<<"$byte_copy_list_int_helper" ||
  ! grep -Fq 'dst->items[(int)i] = (int64_t)b->data[(int)(start + i)]' <<<"$byte_copy_list_int_helper" ||
  ! grep -Fq 'dst->items[(int)i] = it' <<<"$byte_copy_list_int_helper"; then
  echo "ERROR: AVM bytes_unpack must share one checked bytes/list/LIST_INT to LIST_INT copy-span helper" >&2
  exit 1
fi

bytes_pack_impl="$(sed -n '/case 30:.*oren_bytes_pack/,/case 31:/p' lib/avm/avm_native.inc)"
bytes_unpack_impl="$(sed -n '/case 31:.*oren_bytes_unpack/,/case 32:/p' lib/avm/avm_native.inc)"
if ! grep -Fq 'avm_native_bytes_copy_span(args[0], 0, count, bv.as.b->data' <<<"$bytes_pack_impl" ||
  grep -Fq 'list->items[i]' <<<"$bytes_pack_impl"; then
  echo "ERROR: AVM bytes_pack must route list/LIST_INT carriers through the shared byte copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'avm_native_bytes_copy_span_to_list_int(args[0], 0, count, list' <<<"$bytes_unpack_impl" ||
  grep -Fq 'src_list->items[i]' <<<"$bytes_unpack_impl" ||
  grep -Fq 'src_list_int->items[i]' <<<"$bytes_unpack_impl" ||
  grep -Fq 'b->data[i]' <<<"$bytes_unpack_impl"; then
  echo "ERROR: AVM bytes_unpack must route bytes/list/LIST_INT carriers through the shared LIST_INT copy-span helper" >&2
  exit 1
fi

if ! grep -Fq 'args[0].type == AVM_VAL_LIST_INT' <<<"$string_from_bytes_impl" ||
  ! grep -Fq 'string_from_bytes: expected list_int bytes 0..255' <<<"$string_from_bytes_impl" ||
  ! grep -Fq 'avm_native_bytes_copy_span(args[0], 0, n, (uint8_t*)out' <<<"$string_from_bytes_impl" ||
  ! grep -Fq 'if oren_string_from_bytes(from_s_xs) != "ok"' tests/avm/test_bytes_basic.oren; then
  echo "ERROR: AVM string_from_bytes must accept optimized LIST_INT byte carriers without boxed-list reconstruction" >&2
  exit 1
fi

string_from_bytes_slice_impl="$(sed -n '/case 161:.*oren_string_from_bytes_slice/,/case 162:/p' lib/avm/avm_native_byte_iter_cases.inc)"
u8_buf_from_bytes_slice_impl="$(sed -n '/case 162:.*oren_u8_buf_from_bytes_slice/,/case 163:/p' lib/avm/avm_native_byte_iter_cases.inc)"
if ! grep -Fq 'avm_native_bytes_copy_span(args[0], start, n, (uint8_t*)out' <<<"$string_from_bytes_slice_impl" ||
  ! grep -Fq 'avm_native_bytes_copy_span(args[0], start, n, bv.as.b->data' <<<"$u8_buf_from_bytes_slice_impl" ||
  grep -Fq 'args[0].as.li->items[(int)(start + i)]' <<<"$string_from_bytes_slice_impl$u8_buf_from_bytes_slice_impl" ||
  grep -Fq 'args[0].as.l->items[(int)(start + i)]' <<<"$string_from_bytes_slice_impl$u8_buf_from_bytes_slice_impl"; then
  echo "ERROR: AVM byte slice natives must use the shared copy-span helper instead of duplicating list/LIST_INT copy loops" >&2
  exit 1
fi

native_byte_helpers="lib/runtime_native/180_bytes_helpers.oren"
std_strings_to_bytes_impl="$(sed -n '/fn to_bytes(s)/,/fn from_bytes(bs)/p' lib/std/strings.oren)"
std_bytes_from_string_impl="$(sed -n '/fn from_string(s): bytes/,/fn to_hex(bytes)/p' lib/std/bytes.oren)"
std_bytes_from_hex_impl="$(sed -n '/fn from_hex(s): bytes/,/fn from_string(s): bytes/p' lib/std/bytes.oren)"
std_bytes_to_hex_impl="$(sed -n '/fn to_hex(bytes)/,/fn to_string(bytes)/p' lib/std/bytes.oren)"
buffer_raw_u8_from_string_impl="$(sed -n '/fn u8_from_string(s)/,/fn u8_to_string/p' lib/std/buffer/raw.oren)"
native_string_impl="$(sed -n '/fn oren_string_from_bytes(bytes)/,/fn string_concat/p' lib/runtime_native/160_iteration.oren)"
native_copy_helper="$(sed -n '/fn native_bytes_copy_span(bytes/,/^}/p' "$native_byte_helpers")"
native_copy_list_helper="$(sed -n '/fn native_bytes_copy_span_to_int_list(bytes/,/^}/p' "$native_byte_helpers")"
native_string_slice_impl="$(sed -n '/fn oren_string_from_bytes_slice/,/fn bytes_untracked_strings_enabled/p' "$native_byte_helpers")"
native_u8_slice_impl="$(sed -n '/fn oren_u8_buf_from_bytes_slice/,/fn bytes_hex_nibble/p' "$native_byte_helpers")"
native_pack_unpack_impl="$(sed -n '/fn oren_bytes_unpack/,/fn oren_bool_norm/p' "$native_byte_helpers")"
if ! grep -Fq 'native_bytes_is_u8_buf(bytes) == true' <<<"$native_copy_helper" ||
  ! grep -Fq 'oren_memcpy(dst, data + start, len)' <<<"$native_copy_helper" ||
  ! grep -Fq 'ptr_set_byte(dst + i, b & 255)' <<<"$native_copy_helper"; then
  echo "ERROR: native byte slice/pack helpers must share one checked bytes/list/LIST_INT copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'native_bytes_is_u8_buf(bytes) == true' <<<"$native_copy_list_helper" ||
  ! grep -Fq 'ptr_set(out_buf + i * 8, ptr_get_byte(data + start + i) & 255)' <<<"$native_copy_list_helper" ||
  ! grep -Fq 'ptr_set(out_buf + j * 8, b)' <<<"$native_copy_list_helper"; then
  echo "ERROR: native bytes_unpack must share one checked bytes/list/LIST_INT to int-list copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'oren_string_from_bytes_slice(bytes, 0, total)' <<<"$native_string_impl" ||
  grep -Fq 'native_bytes_is_list(bytes) == true' <<<"$native_string_impl" ||
  grep -Fq 'ptr_get(buf + (i << 3))' <<<"$native_string_impl" ||
  grep -Fq 'ptr_set_byte(out + i, b)' <<<"$native_string_impl" ||
  ! grep -Fq 'native_bytes_copy_span(bytes, start, len, out)' <<<"$native_string_slice_impl" ||
  ! grep -Fq 'native_bytes_copy_span(bytes, start, len, dst)' <<<"$native_u8_slice_impl" ||
  ! grep -Fq 'native_bytes_copy_span_to_int_list(bytes, 0, n, out)' <<<"$native_pack_unpack_impl" ||
  ! grep -Fq 'native_bytes_copy_span(xs, 0, n, outp)' <<<"$native_pack_unpack_impl" ||
  grep -Fq 'ptr_get(list_buf + (start + i) * 8)' <<<"$native_string_slice_impl$native_u8_slice_impl" ||
  grep -Fq 'ptr_get(list_buf + j * 8)' <<<"$native_pack_unpack_impl" ||
  grep -Fq 'ptr_get(in_buf + i * 8)' <<<"$native_pack_unpack_impl"; then
  echo "ERROR: native string/slice/pack/unpack helpers must route through shared copy-span helpers instead of duplicating list/LIST_INT loops" >&2
  exit 1
fi
if ! grep -Fq 'return oren_bytes_from_string(s)' <<<"$std_strings_to_bytes_impl" ||
  grep -Fq 'while i < n' <<<"$std_strings_to_bytes_impl" ||
  grep -Fq '_byte_at_raw(s, i)' <<<"$std_strings_to_bytes_impl"; then
  echo "ERROR: std:strings.to_bytes must route validated strings through byte-native runtime conversion, not a per-byte stdlib loop" >&2
  exit 1
fi
if ! grep -Fq 'return oren_bytes_from_string(s)' <<<"$std_bytes_from_string_impl" ||
  grep -Fq 'return raw.u8_from_string(s)' <<<"$std_bytes_from_string_impl"; then
  echo "ERROR: std:bytes.from_string must route validated strings through byte-native runtime conversion, not an extra stdlib wrapper" >&2
  exit 1
fi
if ! grep -Fq 'var c0 = oren_string_byte_at_unchecked(s, i * 2) & 255' <<<"$std_bytes_from_hex_impl" ||
  ! grep -Fq 'var c1 = oren_string_byte_at_unchecked(s, i * 2 + 1) & 255' <<<"$std_bytes_from_hex_impl" ||
  ! grep -Fq 'ptr_set_byte(p + i, ((hi << 4) | lo) & 255)' <<<"$std_bytes_from_hex_impl" ||
  grep -Fq '_hex_digit_value' <<<"$std_bytes_from_hex_impl"; then
  echo "ERROR: std:bytes.from_hex must parse nibbles inline and write exact-size output bytes directly" >&2
  exit 1
fi
if ! grep -Fq '_hex_digit_lower((b >> 4) & 15)' <<<"$std_bytes_to_hex_impl" ||
  ! grep -Fq '_hex_digit_lower(b & 15)' <<<"$std_bytes_to_hex_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(digits' <<<"$std_bytes_to_hex_impl"; then
  echo "ERROR: std:bytes.to_hex must emit lowercase hex digits arithmetically, not index a digit string per byte" >&2
  exit 1
fi
if ! grep -Fq 'return oren_bytes_from_string(s)' <<<"$buffer_raw_u8_from_string_impl" ||
  grep -Fq 'ptr_set_byte(data + i, oren_string_byte_at_unchecked(s, i) & 255)' <<<"$buffer_raw_u8_from_string_impl"; then
  echo "ERROR: std:buffer whole-string u8 creation must route through byte-native runtime conversion, not a per-byte stdlib loop" >&2
  exit 1
fi
buffer_raw_u8_from_string_slice_impl="$(sed -n '/fn u8_from_string_slice(s, off, n)/,/fn u8_from_bytes_slice/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'return oren_u8_buf_from_string_slice(s, off, n)' <<<"$buffer_raw_u8_from_string_slice_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(s, off + i)' <<<"$buffer_raw_u8_from_string_slice_impl"; then
  echo "ERROR: std:buffer string-slice u8 creation must route through byte-native runtime conversion, not a per-byte stdlib loop" >&2
  exit 1
fi
buffer_raw_u8_copy_from_string_range_impl="$(sed -n '/fn _u8_copy_from_string_range/,/fn u8_copy_from_string(out/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'return oren_u8_buf_copy_from_string_slice(out, s, off, n)' <<<"$buffer_raw_u8_copy_from_string_range_impl" ||
  grep -Fq 'ptr_set_byte(data + j, oren_string_byte_at_unchecked(s, off + j) & 255)' <<<"$buffer_raw_u8_copy_from_string_range_impl"; then
  echo "ERROR: std:buffer contiguous u8 string-slice copies must route through byte-native runtime conversion, not a per-byte stdlib loop" >&2
  exit 1
fi

c_runtime_copy_helper="$(sed -n '/static int runtime_bytes_copy_span(OrenValue bytes/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
c_runtime_write_helper="$(sed -n '/static int runtime_bytes_write_span(OrenValue bytes/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
c_runtime_copy_list_helper="$(sed -n '/static int runtime_bytes_copy_span_to_list(OrenValue bytes/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
c_runtime_hex_helper="$(sed -n '/static int runtime_bytes_write_hex(OrenValue bytes/,/^}/p' lib/runtime/039_byte_copy_helpers.inc)"
c_runtime_byte_order_impl="$(sed -n '/static int bytes_get_u8_checked/,/OrenValue oren_bytes_get_u8/p' lib/runtime/044_byte_access.inc)"
c_runtime_to_hex_impl="$(sed -n '/OrenValue oren_bytes_to_hex/,/OrenValue oren_bytes_pack/p' lib/runtime/045_bytes_helpers.inc)"
c_runtime_unpack_impl="$(sed -n '/OrenValue oren_bytes_unpack/,/OrenValue oren_bytes_get_u16_be/p' lib/runtime/044_byte_access.inc)"
c_runtime_pack_impl="$(sed -n '/OrenValue oren_bytes_pack/,/^}/p' lib/runtime/045_bytes_helpers.inc)"
c_runtime_string_impl="$(sed -n '/OrenValue oren_string_from_bytes(OrenValue bytes)/,/OrenValue oren_string_from_bytes_slice/p' lib/runtime/050_io_misc.inc)"
c_runtime_string_slice_impl="$(sed -n '/OrenValue oren_string_from_bytes_slice/,/OrenValue oren_u8_buf_from_bytes_slice/p' lib/runtime/050_io_misc.inc)"
c_runtime_u8_slice_impl="$(sed -n '/OrenValue oren_u8_buf_from_bytes_slice/,/OrenValue oren_string_join/p' lib/runtime/050_io_misc.inc)"
if ! grep -Fq 'memcpy(dst, b->data + start, n)' <<<"$c_runtime_copy_helper" ||
  ! grep -Fq 'dst[i] = (uint8_t)it.as.int_val' <<<"$c_runtime_copy_helper"; then
  echo "ERROR: C runtime byte slice/pack helpers must share one checked list/u8_buf copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'memcpy(b->data + start, src, n)' <<<"$c_runtime_write_helper" ||
  ! grep -Fq 'list->items[start + i] = oren_int((int64_t)src[i])' <<<"$c_runtime_write_helper" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, (size_t)idx, 1u, out' <<<"$c_runtime_byte_order_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, (size_t)idx, (size_t)width, out' <<<"$c_runtime_byte_order_impl" ||
  ! grep -Fq 'runtime_bytes_write_span(bytes, (size_t)idx, &val, 1u' <<<"$c_runtime_byte_order_impl" ||
  ! grep -Fq 'runtime_bytes_write_span(bytes, (size_t)idx, src, (size_t)width' <<<"$c_runtime_byte_order_impl" ||
  grep -Fq 'OrenValue v = list->items[idx + i]' <<<"$c_runtime_byte_order_impl" ||
  grep -Fq 'list->items[idx + i] = oren_int' <<<"$c_runtime_byte_order_impl" ||
  grep -Fq 'memcpy(out, b->data + (uint32_t)idx' <<<"$c_runtime_byte_order_impl" ||
  grep -Fq 'memcpy(b->data + (uint32_t)idx' <<<"$c_runtime_byte_order_impl"; then
  echo "ERROR: C runtime byte/endian get/set helpers must route through shared checked byte copy/write-span helpers" >&2
  exit 1
fi
if ! grep -Fq 'dst->items[i] = oren_int((int64_t)b->data[start + i])' <<<"$c_runtime_copy_list_helper" ||
  ! grep -Fq 'dst->items[i] = oren_int(it.as.int_val)' <<<"$c_runtime_copy_list_helper"; then
  echo "ERROR: C runtime bytes_unpack must share one checked list/u8_buf to list copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'runtime_bytes_write_hex(bytes, out' <<<"$c_runtime_to_hex_impl" ||
  ! grep -Fq 'dst[i * 2u + 0u] = runtime_bytes_hex_char' <<<"$c_runtime_hex_helper" ||
  ! grep -Fq 'OrenValue it = list->items[i]' <<<"$c_runtime_hex_helper" ||
  grep -Fq 'bytes_hex_char' <<<"$c_runtime_to_hex_impl" ||
  grep -Fq 'b->data[i]' <<<"$c_runtime_to_hex_impl" ||
  grep -Fq 'list->items[i]' <<<"$c_runtime_to_hex_impl"; then
  echo "ERROR: C runtime bytes_to_hex must route list/u8_buf carriers through the shared checked hex helper" >&2
  exit 1
fi
if ! grep -Fq 'runtime_bytes_copy_span_to_list(bytes, 0u, count_size, list' <<<"$c_runtime_unpack_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(xs, 0u, (size_t)list->count, out->data' <<<"$c_runtime_pack_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, 0u, n, (uint8_t*)buf' <<<"$c_runtime_string_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out' <<<"$c_runtime_string_slice_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out->data' <<<"$c_runtime_u8_slice_impl" ||
  grep -Fq 'OrenValue it = list->items[i]' <<<"$c_runtime_string_impl" ||
  grep -Fq 'OrenValue it = list->items[s + i]' <<<"$c_runtime_string_slice_impl$c_runtime_u8_slice_impl" ||
  grep -Fq 'OrenValue v = src->items[i]' <<<"$c_runtime_unpack_impl" ||
  grep -Fq 'OrenValue v = list->items[i]' <<<"$c_runtime_pack_impl" ||
  ! grep -Fq 'string_from_bytes long boxed list' tests/modules/test_string_from_bytes.oren; then
  echo "ERROR: C runtime byte string/slice/pack/unpack helpers must route through shared copy-span helpers instead of duplicating list/u8_buf loops" >&2
  exit 1
fi

c_runtime_sha256_impl="$(sed -n '/OrenValue oren_sha256_range/,/OrenValue oren_sha256_string/p' lib/runtime/050_io_misc_sha256.inc)"
if ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$c_runtime_sha256_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, (size_t)s + off, want, chunk' <<<"$c_runtime_sha256_impl" ||
  ! grep -Fq 'oren_sha256_update(&ctx, chunk, want)' <<<"$c_runtime_sha256_impl" ||
  grep -Fq 'oren_sha256_update(&ctx, &byte, 1)' <<<"$c_runtime_sha256_impl" ||
  grep -Fq 'bytes.as.list_val->items' <<<"$c_runtime_sha256_impl" ||
  grep -Fq 'bytes.as.buf_val' <<<"$c_runtime_sha256_impl" ||
  ! grep -Fq 'sha256 C long boxed list range' tests/modules/test_crypto_sha256_c_list_chunks.oren; then
  echo "ERROR: C runtime sha256_range list/u8_buf inputs must hash bounded chunks through the shared byte copy-span helper" >&2
  exit 1
fi

native_sha256_impl="$(sed -n '/fn oren_sha256_range/,/fn oren_sha256_string/p' lib/runtime_native/185_sha256.oren)"
if ! grep -Fq 'native_bytes_copy_span(bytes, start + off, 64, data)' <<<"$native_sha256_impl" ||
  ! grep -Fq 'native_bytes_copy_span(bytes, start + off, rem2, data)' <<<"$native_sha256_impl" ||
  grep -Fq 'ptr_get(list_buf + (start + off + j) * 8)' <<<"$native_sha256_impl" ||
  grep -Fq 'ptr_get(list_buf + (start + off + k0) * 8)' <<<"$native_sha256_impl" ||
  ! grep -Fq 'sha256 native long list_int range' tests/modules/test_crypto_sha256_c_list_chunks.oren; then
  echo "ERROR: native sha256_range list/LIST_INT inputs must share checked byte copy-span block fills" >&2
  exit 1
fi

avm_sha256_impl="$(sed -n '/case 120:.*oren_sha256_range/,/case 121:/p' lib/avm/avm_native_core_tail_cases.inc)"
if ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$avm_sha256_impl" ||
  ! grep -Fq 'avm_native_bytes_copy_span(args[0], start + off, want_i64, chunk' <<<"$avm_sha256_impl" ||
  ! grep -Fq 'avm_sha256_update(&ctx, chunk, (size_t)want_i64)' <<<"$avm_sha256_impl" ||
  grep -Fq 'avm_sha256_update(&ctx, &b, 1)' <<<"$avm_sha256_impl" ||
  grep -Fq 'list->items[(int)(start + off' <<<"$avm_sha256_impl" ||
  grep -Fq 'list_int->items[(int)(start + off' <<<"$avm_sha256_impl" ||
  grep -Fq 'bytes->data + (size_t)start' <<<"$avm_sha256_impl" ||
  ! grep -Fq 'sha256 AVM long boxed list range' tests/avm/test_crypto_sha256_vectors.oren ||
  ! grep -Fq 'sha256 AVM long list_int range' tests/avm/test_crypto_sha256_vectors.oren; then
  echo "ERROR: AVM sha256_range bytes/list/LIST_INT inputs must hash bounded chunks through the shared byte copy-span helper" >&2
  exit 1
fi

if ! grep -Fq 'var w = list.int_new(80)' lib/std/crypto/sha1.oren ||
  ! grep -Fq 'var w = list.int_new(64)' lib/std/crypto/sha256.oren ||
  grep -Fq 'var w = []' lib/std/crypto/sha1.oren ||
  grep -Fq 'var w = []' lib/std/crypto/sha256.oren ||
  grep -Fq 'list.push(w' lib/std/crypto/sha1.oren ||
  grep -Fq 'list.push(w' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'sha1 AVM long list_int range' tests/avm/test_crypto_sha256_vectors.oren; then
  echo "ERROR: pure Oren SHA schedules must use fixed-size list_int carriers, not generic per-block list growth" >&2
  exit 1
fi

sha1_input_view_impl="$(sed -n '/fn _input_view_or_err/,/fn _u32/p' lib/std/crypto/sha1.oren)"
sha256_input_view_impl="$(sed -n '/fn _input_view_or_err/,/fn _u32/p' lib/std/crypto/sha256.oren)"
sha1_u32_be_impl="$(sed -n '/fn _u32_be_at(input_view/,/fn _store_u32_be/p' lib/std/crypto/sha1.oren)"
sha256_u32_be_impl="$(sed -n '/fn _u32_be_at(input_view/,/fn _store_u32_be/p' lib/std/crypto/sha256.oren)"
if grep -Fq 'while i < n' <<<"$sha1_input_view_impl$sha256_input_view_impl" ||
  grep -Fq 'view_get_u8_unchecked(v, i)' <<<"$sha1_input_view_impl$sha256_input_view_impl" ||
  ! grep -Fq 'if oren_is_err(word) { return oren_err(4, "sha1.digest: expected list<int 0..255> or u8_buf") }' lib/std/crypto/sha1.oren ||
  ! grep -Fq 'if oren_is_err(word) { return oren_err(4, "sha256.digest: expected list<int 0..255> or u8_buf") }' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'if oren_is_err(b0) { return b0 }' <<<"$sha1_u32_be_impl$sha256_u32_be_impl" ||
  ! grep -Fq 'sha1_bytes bad list should return err' tests/avm/test_crypto_sha256_vectors.oren; then
  echo "ERROR: pure Oren SHA byte inputs must validate during schedule loads, not through a separate full pre-scan" >&2
  exit 1
fi

std_bytes_view_impl="$(sed -n '/fn view_get_u16_be_unchecked/,/fn view_get_u32_be_unchecked/p' lib/std/bytes.oren)"
ui_avm_append_bytes_impl="$(sed -n '/fn _append_bytes/,/fn _string_byte_len/p' lib/std/ui/avm.oren)"
ui_avm_append_string_impl="$(sed -n '/fn _append_string/,/fn _push_frame_header/p' lib/std/ui/avm.oren)"
ui_avm_decode_event_impl="$(sed -n '/fn decode_event_bytes(ev)/,/fn next_event/p' lib/std/ui/avm.oren)"
if ! grep -Fq 'fn view_get_u16_le_unchecked(v, idx)' <<<"$std_bytes_view_impl" ||
  ! grep -Fq 'if p != nil { return _u16_le_from_ptr(p, idx) }' <<<"$std_bytes_view_impl" ||
  ! grep -Fq 'return get_u16_le(view_bytes(v), idx)' <<<"$std_bytes_view_impl" ||
  ! grep -Fq 'fn view_get_u16_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i16_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i16_le_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_u32_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i32_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_u64_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_u32_le_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_u64_le_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i64_be_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i64_le_from(input_bytes, input_ptr, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i16_be_unchecked(v, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i32_be_unchecked(v, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i64_le_unchecked(v, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'fn view_get_i64_be_unchecked(v, idx)' lib/std/bytes.oren ||
  ! grep -Fq 'var input_ptr = bytes.view_ptr(bv)' <<<"$ui_avm_append_bytes_impl" ||
  ! grep -Fq 'raw._copy_u8_ptr_forward(oren_buf_data_ptr_unchecked(wr[0]) + wr[1], input_ptr, n)' <<<"$ui_avm_append_bytes_impl" ||
  ! grep -Fq 'var b = bytes.view_get_u8_from(input_data, input_ptr, i)' <<<"$ui_avm_append_bytes_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(wr[0], wr[1], s, 0, n)' <<<"$ui_avm_append_string_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(s, i)' <<<"$ui_avm_append_string_impl" ||
  ! grep -Fq 'var ev_data = bytes.view_bytes(ev_view)' <<<"$ui_avm_decode_event_impl" ||
  ! grep -Fq 'var ev_ptr = bytes.view_ptr(ev_view)' <<<"$ui_avm_decode_event_impl" ||
  ! grep -Fq 'var payload_len = bytes.view_get_u16_le_from(ev_data, ev_ptr, 10)' <<<"$ui_avm_decode_event_impl" ||
  grep -Fq 'bytes.view_get_u32_le_unchecked(ev_view' <<<"$ui_avm_decode_event_impl" ||
  grep -Fq 'bytes.view_get_u64_le_unchecked(ev_view' <<<"$ui_avm_decode_event_impl" ||
  grep -Fq 'var b = bytes.view_get_u8_unchecked(bv, i)' <<<"$ui_avm_append_bytes_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(ev_view, 10) | (bytes.view_get_u8_unchecked(ev_view, 11) << 8)' lib/std/ui/avm.oren; then
  echo "ERROR: UI/AVM frame/event byte paths must use direct std:bytes view reads" >&2
  exit 1
fi
if grep -Fq '_padded_string_byte_at' lib/std/crypto/sha1.oren ||
  grep -Fq '_padded_string_byte_at' lib/std/crypto/sha256.oren ||
  grep -Fq '_u32_be_string_at' lib/std/crypto/sha1.oren ||
  grep -Fq '_u32_be_string_at' lib/std/crypto/sha256.oren ||
  [[ "$(grep -Fc 'while off < total_len' lib/std/crypto/sha1.oren)" != "1" ]] ||
  [[ "$(grep -Fc 'while off < total_len' lib/std/crypto/sha256.oren)" != "1" ]] ||
  ! grep -Fq 'return _sha1_digest_view(input_view)' lib/std/crypto/sha1.oren ||
  ! grep -Fq 'return _sha256_digest_view(input_view)' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'sha256 string multiblock' tests/avm/test_crypto_sha256_vectors.oren; then
  echo "ERROR: pure Oren SHA string inputs must share the byte-source compression path without duplicate string block loops" >&2
  exit 1
fi

if ! grep -Fq 'var _SHA256_K = nil' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'fn _round_constants()' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'var k = list.int_new(64)' lib/std/crypto/sha256.oren ||
  ! grep -Fq 'list.int_get(K, t)' lib/std/crypto/sha256.oren ||
  grep -Fq 'var K = [' lib/std/crypto/sha256.oren ||
  grep -Fq 'K[t]' lib/std/crypto/sha256.oren; then
  echo "ERROR: pure Oren SHA-256 round constants must use one cached list_int table, not per-call boxed lists" >&2
  exit 1
fi

chunked_http_impl="$(sed -n '/fn _decode_chunked_body/,/fn headers_get/p' lib/std/net/http.oren)"
http_fetch_impl="$(sed -n '/fn _fetch_response_resolver_opts/,/fn request_resolver_opts/p' lib/std/net/http.oren)"
ws_header_impl="$(sed -n '/fn _read_http_header_into_buf/,/fn _ws_accept_for_key/p' lib/std/net/ws.oren)"
if ! grep -Fq 'fn _chunked_decoded_len(body_ptr, body_len)' lib/std/net/http.oren ||
  ! grep -Fq 'var decoded_len = _chunked_decoded_len(body_ptr, body_len)' <<<"$chunked_http_impl" ||
  ! grep -Fq 'var out = malloc(decoded_len + 1)' <<<"$chunked_http_impl" ||
  ! grep -Fq 'var out_bytes = oren_u8_buf_new_uninit(decoded_len)' <<<"$chunked_http_impl" ||
  ! grep -Fq 'out_bytes_ptr = native_buf_data_ptr(out_bytes)' <<<"$chunked_http_impl" ||
  ! grep -Fq 'oren_memcpy(out_bytes_ptr + out_used, body_ptr + i, size)' <<<"$chunked_http_impl" ||
  grep -Fq 'malloc(body_len + 1)' <<<"$chunked_http_impl" ||
  grep -Fq '_u8_buf_from_ptr_range(out, 0, out_used)' <<<"$chunked_http_impl"; then
  echo "ERROR: native HTTP chunked decode must allocate exact decoded text/bytes and fill body_bytes directly, not shrink-copy from framed body storage" >&2
  exit 1
fi

if ! grep -Fq 'tls.read_into_raw(tls_conn, buf + used, read_cap, timeout_ms)' <<<"$http_fetch_impl" ||
  ! grep -Fq 'tcp.read_into_raw(fd, buf + used, read_cap, timeout_ms)' <<<"$http_fetch_impl" ||
  grep -Fq 'var tmp = malloc(2048)' <<<"$http_fetch_impl" ||
  grep -Fq 'oren_memcpy(buf + used, tmp, n)' <<<"$http_fetch_impl"; then
  echo "ERROR: native HTTP receive loop must read directly into reserved response storage without per-read temp buffers" >&2
  exit 1
fi

if ! grep -Fq 'var n = _io_read_into(conn, buf + used, read_cap, rem)' <<<"$ws_header_impl" ||
  ! grep -Fq 'if read_cap > 1024 { read_cap = 1024 }' <<<"$ws_header_impl" ||
  grep -Fq 'var tmp = malloc(1024)' <<<"$ws_header_impl" ||
  grep -Fq '_io_read_into(conn, tmp' <<<"$ws_header_impl" ||
  grep -Fq 'oren_memcpy(buf + used, tmp, n)' <<<"$ws_header_impl"; then
  echo "ERROR: native WebSocket HTTP upgrade header reads must fill reserved header storage directly without scratch-buffer copies" >&2
  exit 1
fi
if ! grep -Fq '    var frame_hdr = malloc(14)' lib/std/net/ws.oren ||
  ! grep -Fq 'rc = _read_exact(conn, frame_hdr + 2, ext_len, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'rc = _read_exact(conn, frame_hdr + mask_off, 4, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'var out_is_bytes = 0' lib/std/net/ws.oren ||
  ! grep -Fq 'if want_bytes == 1 && opcode < 8 && opcode != 0 && opcode == want_opcode && frag_active != 1 && fin == 1 {' lib/std/net/ws.oren ||
  ! grep -Fq 'out = oren_u8_buf_new_uninit(plen)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn _frag_acc_append_raw(acc, ptr0, n)' lib/std/net/ws.oren ||
  ! grep -Fq 'if opcode == 0 {' lib/std/net/ws.oren ||
  ! grep -Fq 'if oren_is_err(out) { free(frame_hdr); return {"ok": 0, "err": "ws.recv_bytes: alloc payload"} }' lib/std/net/ws.oren ||
  ! grep -Fq 'if outp == 0 { free(frame_hdr); return {"ok": 0, "err": "ws.recv_bytes: payload data ptr nil"} }' lib/std/net/ws.oren ||
  ! grep -Fq 'if p == 0 { return 0 - 22 } // EINVAL' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_bytes_client(conn, bytes, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn recv_bytes(conn, timeout_ms)' lib/std/net/ws.oren ||
  grep -Fq 'fragmented frames not supported' lib/std/net/ws.oren ||
  grep -Fq '        var frame_hdr = malloc(14)' lib/std/net/ws.oren ||
  grep -Fq 'var hdr2 = malloc(2)' lib/std/net/ws.oren ||
  grep -Fq 'var ex = malloc(2)' lib/std/net/ws.oren ||
  grep -Fq 'var ex8 = malloc(8)' lib/std/net/ws.oren ||
  grep -Fq 'var mk = malloc(4)' lib/std/net/ws.oren; then
  echo "ERROR: native WebSocket receive paths must use one fixed frame-prefix scratch buffer and expose byte-native binary frames" >&2
  exit 1
fi
ws_send_impl="$(sed -n '/fn _send_frame_raw/,/fn _send_frame_str/p' lib/std/net/ws.oren)"
ws_write_u64_impl="$(sed -n '/fn _write_u64_be/,/fn _mask_byte/p' lib/std/net/ws.oren)"
if ! grep -Fq 'if masked != 1 {' <<<"$ws_send_impl" ||
  ! grep -Fq 'var hdr = malloc(14)' <<<"$ws_send_impl" ||
  ! grep -Fq 'var pw = _io_write_from(conn, payload_ptr, payload_len, timeout_ms)' <<<"$ws_send_impl" ||
  ! grep -Fq 'var mask_bytes = 4' <<<"$ws_send_impl" ||
  ! grep -Fq 'var scratch_len = payload_len' <<<"$ws_send_impl" ||
  ! grep -Fq 'if scratch_len > 4096 { scratch_len = 4096 }' <<<"$ws_send_impl" ||
  ! grep -Fq 'while sent < payload_len {' <<<"$ws_send_impl" ||
  ! grep -Fq 'b = b ^ _mask_byte(mask0, mask1, mask2, mask3, sent + i)' <<<"$ws_send_impl" ||
  grep -Fq 'var total = 2 + ext + mask_bytes + payload_len' <<<"$ws_send_impl" ||
  grep -Fq 'var buf = malloc(total)' <<<"$ws_send_impl" ||
  grep -Fq 'if payload_len > 0 { oren_memcpy(buf + payload_off, payload_ptr, payload_len) }' <<<"$ws_send_impl"; then
  echo "ERROR: native WebSocket sends must stream raw unmasked payload spans and fixed-chunk masked payloads instead of copying into full-frame buffers" >&2
  exit 1
fi
if ! grep -Fq 'ptr_set_byte(buf + off + 0, (v >> 56) & 255)' <<<"$ws_write_u64_impl" ||
  ! grep -Fq 'ptr_set_byte(buf + off + 7, v & 255)' <<<"$ws_write_u64_impl" ||
  grep -Fq 'while i < 8' <<<"$ws_write_u64_impl"; then
  echo "ERROR: native WebSocket 64-bit extended-length headers must use straight-line big-endian byte stores" >&2
  exit 1
fi
if ! grep -Fq 'fn _read_u64_be(buf, off)' lib/std/net/ws.oren ||
  ! grep -Fq '((ptr_get_byte(buf + off + 0) & 255) << 56)' <<<"$ws_write_u64_impl" ||
  ! grep -Fq '(ptr_get_byte(buf + off + 7) & 255)' <<<"$ws_write_u64_impl" ||
  ! grep -Fq 'plen = _read_u64_be(frame_hdr, 2)' lib/std/net/ws.oren ||
  ! grep -Fq 'var ext64_bytes = _make_binary_payload(70000)' tests/native/test_ws_echo_loopback.oren; then
  echo "ERROR: native WebSocket 64-bit extended-length receives must use straight-line big-endian byte reads with loopback coverage" >&2
  exit 1
fi
ws_ping_impl="$(sed -n '/fn _send_frame_control_str/,/fn _send_frame_text/p' lib/std/net/ws.oren)"
if ! grep -Fq 'fn _send_frame_control_bytes(conn, opcode, bytes, timeout_ms, masked)' lib/std/net/ws.oren ||
  ! grep -Fq 'var n = oren_buf_len(bytes)' <<<"$ws_ping_impl" ||
  grep -Fq 'oren_bytes_len(bytes)' <<<"$ws_ping_impl" ||
  ! grep -Fq 'if n > 125 { return 0 - 22 }' <<<"$ws_ping_impl" ||
  ! grep -Fq 'return _send_frame_raw(conn, opcode, p, n, timeout_ms, masked)' <<<"$ws_ping_impl" ||
  ! grep -Fq 'fn send_ping_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_ping_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_pong_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_pong_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_control_bytes(conn, 10, payload, timeout_ms, 1)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_control_bytes(conn, 10, payload, timeout_ms, 0)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn _send_frame_close_bytes(conn, bytes, timeout_ms, masked)' lib/std/net/ws.oren ||
  ! grep -Fq 'if oren_is_err(n) || n == 1 { return 0 - 22 }' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_close_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_close_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_close_bytes(conn, payload, timeout_ms, 1)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_close_bytes(conn, payload, timeout_ms, 0)' lib/std/net/ws.oren ||
  grep -Fq 'oren_string_from_bytes' <<<"$ws_ping_impl" ||
  grep -Fq 'oren_bytes_unpack' <<<"$ws_ping_impl"; then
  echo "ERROR: native WebSocket binary ping/pong/close must send u8_buf control payloads directly without byte-list or string conversion" >&2
  exit 1
fi
ws_binary_send_impl="$(sed -n '/fn _send_frame_bytes/,/fn send_text_client/p' lib/std/net/ws.oren)"
if ! grep -Fq 'var n = oren_buf_len(bytes)' <<<"$ws_binary_send_impl" ||
  grep -Fq 'oren_bytes_len(bytes)' <<<"$ws_binary_send_impl"; then
  echo "ERROR: native WebSocket binary sends must use direct u8_buf length after the u8_buf type check" >&2
  exit 1
fi
if ! grep -Fq 'text = _make_text_payload(5003)' tests/native/test_ws_echo_loopback.oren; then
  echo "ERROR: native WebSocket loopback must exercise masked sends larger than the fixed 4096-byte chunk" >&2
  exit 1
fi
if ! grep -Fq 'fn _send_fragmented_text_client(conn, text, n, timeout_ms)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'fn _send_fragmented_bytes_client(conn, bytes, timeout_ms)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'bytes = _make_binary_payload(4101)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'var bprc = ws.send_ping_client(conn, "bytes", 5000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'var pbprc = ws.send_ping_bytes_client(conn, ping_bytes, 5000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'var poprc = conn.send_pong_bytes_client(pong_bytes, 5000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'var clrc = conn.send_close_bytes_client(close_payload, 5000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'var cr = conn.recv_text(10000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'conn.send_bytes_client(bytes, 5000)' tests/native/test_ws_echo_loopback.oren ||
  ! grep -Fq 'conn.recv_bytes(10000)' tests/native/test_ws_echo_loopback.oren; then
  echo "ERROR: native WebSocket loopback must exercise byte-native binary frames larger than the fixed 4096-byte masked chunk" >&2
  exit 1
fi
if ! grep -Fq 'fn _client_exchange(conn)' tests/native/test_wss_echo_loopback.oren ||
  ! grep -Fq 'var pbrc = ws.send_ping_bytes_client(conn, ping_bytes, 5000)' tests/native/test_wss_echo_loopback.oren ||
  ! grep -Fq 'var porrc = ws.send_pong_bytes_client(conn, pong_bytes, 5000)' tests/native/test_wss_echo_loopback.oren; then
  echo "ERROR: native WSS loopback must exercise byte-native ping/pong control payloads over TLS" >&2
  exit 1
fi
ios_ws_impl="$(sed -n '/static int OrenAVMRuntimeWebSocketWriteFrame/,/static int OrenAVMRuntimeWebSocketReadPayload/p' sdk/ios/OrenAVMKit/OrenAVMKit.m)"
if ! grep -Fq 'avm_embed_set_net_session_write_typed_callback(_handle, OrenAVMRuntimeNetSessionWriteTyped' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'uint8_t opcode = payloadKind == AVM_NET_SESSION_PAYLOAD_BYTES ? 2u : 1u' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'frame[off++] = 0x80u | opcode' <<<"$ios_ws_impl" ||
  grep -Fq 'OrenAVMRuntimeWebSocketWriteText' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  grep -Fq 'frame[off++] = 0x81u' <<<"$ios_ws_impl"; then
  echo "ERROR: iOS host-backed AVM WebSocket writes must preserve string-vs-bytes payload kinds as text-vs-binary frame opcodes" >&2
  exit 1
fi
if ! grep -Fq 'avm_embed_set_net_session_read_typed_callback(_handle, OrenAVMRuntimeNetSessionReadTyped' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'OrenAVMRuntimeWebSocketReadPayload(fd, maxLen, payloadKind' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'payloadKind == AVM_NET_SESSION_PAYLOAD_TEXT && opcode != 1u' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'payloadKind == AVM_NET_SESSION_PAYLOAD_BYTES && opcode != 2u' sdk/ios/OrenAVMKit/OrenAVMKit.m ||
  ! grep -Fq 'return socket.read_kind(session_id, max_len, 2, timeout_ms)' lib/std/net/avm/ws.oren ||
  ! grep -Fq 'var data = socket.read_kind(session_id, max_len, 1, timeout_ms)' lib/std/net/avm/ws.oren; then
  echo "ERROR: iOS host-backed AVM WebSocket reads must preserve text-vs-binary frame opcode expectations" >&2
  exit 1
fi
if grep -Fq 'oren_string_from_bytes_slice(body, 0, oren_bytes_len(body))' lib/std/net/avm/http.oren ||
  grep -Fq 'oren_string_from_bytes_slice(data, 0, oren_bytes_len(data))' lib/std/net/avm/ws.oren ||
  ! grep -Fq 'return oren_string_from_bytes(body)' lib/std/net/avm/http.oren ||
  ! grep -Fq 'return oren_string_from_bytes(data)' lib/std/net/avm/ws.oren; then
  echo "ERROR: AVM HTTP/WS text facades must use whole-buffer byte-to-string conversion instead of repeated length+slice conversion" >&2
  exit 1
fi
if ! grep -Fq 'if opcode != 2 or payload != b"bin!"' scripts/libavm_ios_verify_net_helpers.py ||
  ! grep -Fq 'conn.sendall(b"\x81\x04text")' scripts/libavm_ios_verify_net_helpers.py ||
  ! grep -Fq 'net_ws.send(sid, bin, 5000)' tests/fixtures/ios_avm/embed_chain.oren ||
  ! grep -Fq 'net_ws.recv(sid, 4, 5000)' tests/fixtures/ios_avm/embed_chain.oren ||
  ! grep -Fq 'if oren_is_err(wrong) != true' tests/fixtures/ios_avm/embed_chain.oren; then
  echo "ERROR: iOS AVM WebSocket verifier must exercise byte-native binary frame opcodes" >&2
  exit 1
fi

argparse_lower_impl="$(sed -n '/fn _lower_ascii/,/fn _trim_spaces/p' lib/std/argparse.oren)"
if ! grep -Fq 'var out = oren_u8_buf_new_uninit(n)' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'var data = oren_buf_data_ptr_unchecked(out)' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'var b = oren_string_byte_at_unchecked(s, i) & 255' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'if b >= 65 && b <= 90 { b = b + 32 }' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'ptr_set_byte(data + i, b)' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'return oren_string_from_bytes_slice(out, 0, n)' <<<"$argparse_lower_impl" ||
  grep -Fq 'var alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"' <<<"$argparse_lower_impl" ||
  grep -Fq 'oren_string_char_at("abcdefghijklmnopqrstuvwxyz"' <<<"$argparse_lower_impl" ||
  ! grep -Fq 'lower ascii maps uppercase only' tests/modules/test_argparse.oren; then
  echo "ERROR: argparse ASCII lowercasing must use exact-size u8_buf writes and byte arithmetic, not alphabet string scans" >&2
  exit 1
fi
compiler_capsule_ascii_upper_impl="$(sed -n '/fn ascii_upper/,/fn build_allow_set/p' lib/compiler/capsule.oren)"
compiler_metadata_ascii_upper_impl="$(sed -n '/fn ascii_upper/,/fn string_list_has/p' lib/compiler/metadata.oren)"
compiler_ascii_upper_impl="$compiler_capsule_ascii_upper_impl
$compiler_metadata_ascii_upper_impl"
if ! grep -Fq 'var out = oren_u8_buf_new_uninit(n)' <<<"$compiler_capsule_ascii_upper_impl" ||
  ! grep -Fq 'var out = oren_u8_buf_new_uninit(n)' <<<"$compiler_metadata_ascii_upper_impl" ||
  [[ "$(grep -F 'var data = oren_buf_data_ptr_unchecked(out)' <<<"$compiler_ascii_upper_impl" | wc -l | tr -d ' ')" != "2" ]] ||
  [[ "$(grep -F 'var b = oren_string_byte_at_unchecked(s, i) & 255' <<<"$compiler_ascii_upper_impl" | wc -l | tr -d ' ')" != "2" ]] ||
  [[ "$(grep -F 'if b >= 97 && b <= 122 { b = b - 32 }' <<<"$compiler_ascii_upper_impl" | wc -l | tr -d ' ')" != "2" ]] ||
  [[ "$(grep -F 'ptr_set_byte(data + i, b)' <<<"$compiler_ascii_upper_impl" | wc -l | tr -d ' ')" != "2" ]] ||
  [[ "$(grep -F 'return oren_string_from_bytes_slice(out, 0, n)' <<<"$compiler_ascii_upper_impl" | wc -l | tr -d ' ')" != "2" ]] ||
  grep -Fq 'var lower = "abcdefghijklmnopqrstuvwxyz"' <<<"$compiler_ascii_upper_impl" ||
  grep -Fq 'var upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"' <<<"$compiler_ascii_upper_impl" ||
  grep -Fq 'out = out + mapped' <<<"$compiler_ascii_upper_impl"; then
  echo "ERROR: compiler ASCII uppercase helpers must use exact-size u8_buf writes and byte arithmetic, not alphabet scans" >&2
  exit 1
fi
runtime_bundle_upper_name_impl="$(sed -n '/fn _bundle_is_upper_name/,/fn _bundle_is_zero_const_expr/p' lib/compiler/native_runtime_bundle.oren)"
if ! grep -Fq 'var b = oren_string_byte_at_unchecked(name, 0) & 255' <<<"$runtime_bundle_upper_name_impl" ||
  ! grep -Fq 'return b >= 65 && b <= 90' <<<"$runtime_bundle_upper_name_impl" ||
  grep -Fq 'var ups = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"' <<<"$runtime_bundle_upper_name_impl" ||
  grep -Fq 'oren_string_char_at(ups' <<<"$runtime_bundle_upper_name_impl"; then
  echo "ERROR: native runtime bundle uppercase-name classifier must use direct first-byte ASCII range checks" >&2
  exit 1
fi
compiler_string_len_cached_impl="$(sed -n '/fn _split_csv_simple/,/fn _parse_bool_env/p' lib/std/argparse.oren)
$(sed -n '/fn _to_int/,/fn _validate_opt/p' lib/std/argparse.oren)
$(sed -n '/fn _json_escape/,/fn _json_value/p' lib/std/argparse.oren)
$(sed -n '/Chain remaining chars/,/return {\"ok\": true/p' lib/std/argparse.oren)
$(sed -n '/fn diag_escape/,/fn emit_diag/p' lib/compiler/compiler/000_prelude_body.oren)
$(sed -n '/fn _path_to_windows_sep/,/fn host_is_windows/p' lib/compiler/compiler/000_prelude_body.oren)
$(sed -n '/fn _cmd_quote/,/fn _ensure_stage1_exe/p' lib/compiler/compiler/000_prelude_body.oren)
$(sed -n '/fn _rt_bundle_path_to_windows_sep/,/fn _rt_bundle_host_is_windows/p' lib/compiler/native_runtime_bundle.oren)
$(sed -n '/fn _stable_std_prefix/,/fn _ml_modcache_build_tag/p' lib/compiler/compiler/020_modules_linking/000_prelude.oren)
$(sed -n '/fn parse_capability_formats/,/fn json_string_array/p' lib/compiler/metadata.oren)
$(sed -n '/fn c_escape_string/,/fn c_ident/p' lib/compiler/transpiler_c_utils.oren)
$(sed -n '/fn _cfg_split_csv/,/fn _cfg_any_eq/p' lib/compiler/cfg_lowering.oren)
$(sed -n '/fn macho_diag_escape/,/fn _arm64_rewrite_got_loads_if_needed/p' lib/compiler/arm64_macho.oren)
$(sed -n '/fn elf_diag_escape/,/fn arm64_ctx_fixup_got_load/p' lib/compiler/arm64_elf.oren)
$(sed -n '/fn bc_diag_escape/,/fn list_push/p' lib/compiler/codegen_bytecode/000_prelude.oren)"
if ! grep -Fq 'var tail_len = oren_string_len(tail)' <<<"$compiler_string_len_cached_impl" ||
  ! grep -Fq 'var n = oren_string_len(msg)' <<<"$compiler_string_len_cached_impl" ||
  ! grep -Fq 'var n = oren_string_len(s)' <<<"$compiler_string_len_cached_impl" ||
  ! grep -Fq 'var key_len = oren_string_len(key)' <<<"$compiler_string_len_cached_impl" ||
  grep -Fq 'while i < oren_string_len(' <<<"$compiler_string_len_cached_impl" ||
  grep -Fq 'while ci < oren_string_len(' <<<"$compiler_string_len_cached_impl"; then
  echo "ERROR: selected compiler/tooling string loops must cache immutable string lengths before iteration" >&2
  exit 1
fi
if grep -R -n -E --include='*.oren' 'while [[:alnum:]_]+ < oren_string_len\(' lib/compiler lib/std >/dev/null; then
  echo "ERROR: compiler/std index loops must cache immutable string lengths before iteration" >&2
  grep -R -n -E --include='*.oren' 'while [[:alnum:]_]+ < oren_string_len\(' lib/compiler lib/std >&2
  exit 1
fi
arm64_expr_g_storage_impl="$(sed -n '/fn _arm64_expr_name_ends_with_g_storage/,/fn _arm64_expr_emit_load_g_storage_ptr/p' lib/compiler/arm64_native_expr/000_prelude.oren)"
arm64_rt_g_storage_impl="$(sed -n '/fn _arm64_rt_name_ends_with_g_storage/,/fn _arm64_emit_load_g_storage_ptr/p' lib/compiler/arm64_native_stmt_runtime.oren)"
x64_rt_g_storage_impl="$(sed -n '/fn _x64_rt_name_ends_with_g_storage/,/fn _x64_emit_load_g_storage_ptr_to_reg/p' lib/compiler/x64_native_program/040_emit_expr.oren)"
if ! grep -Fq 'fn _arm64_expr_name_ends_with_g_storage(k)' <<<"$arm64_expr_g_storage_impl" ||
  ! grep -Fq 'fn _arm64_rt_name_ends_with_g_storage(k)' <<<"$arm64_rt_g_storage_impl" ||
  ! grep -Fq 'fn _x64_rt_name_ends_with_g_storage(k)' <<<"$x64_rt_g_storage_impl" ||
  [[ "$(grep -F 'oren_string_byte_at_unchecked(k, off + 8) & 255' <<<"$arm64_expr_g_storage_impl"$'\n'"$arm64_rt_g_storage_impl"$'\n'"$x64_rt_g_storage_impl" | wc -l | tr -d ' ')" != "3" ]] ||
  [[ "$(grep -F '_arm64_expr_resolve_g_storage_name(ctx)' lib/compiler/arm64_native_expr/015_lowering_a_noncall.oren lib/compiler/arm64_native_expr/090_tail.oren | wc -l | tr -d ' ')" -lt "10" ]] ||
  grep -Fq 'oren_string_char_at("g_storage"' lib/compiler/arm64_native_expr/000_prelude.oren lib/compiler/arm64_native_expr/015_lowering_a_noncall.oren lib/compiler/arm64_native_expr/090_tail.oren lib/compiler/arm64_native_stmt_runtime.oren lib/compiler/x64_native_program/040_emit_expr.oren ||
  grep -Fq 'oren_string_char_at(k, klen - slen + j)' lib/compiler/arm64_native_expr/000_prelude.oren lib/compiler/arm64_native_stmt_runtime.oren ||
  grep -Fq 'var suf = "g_storage"' lib/compiler/x64_native_program/040_emit_expr.oren ||
  grep -Fq 'match_count_cmp' lib/compiler/arm64_native_expr/015_lowering_a_noncall.oren ||
  grep -Fq 'match_count_sc' lib/compiler/arm64_native_expr/015_lowering_a_noncall.oren; then
  echo "ERROR: native g_storage resolution must use byte-suffix helpers and cached resolver calls, not duplicated char-at suffix scans" >&2
  exit 1
fi
x64_ctx_xmm_impl="$(sed -n '/fn _x64_emit_ctx_switch_save_xmms/,/fn _x64_emit_ctx_switch_restore_gprs/p' lib/compiler/x64_native_program/043_emit_stack_intrinsics.oren)"
if [[ "$(grep -F 'core.insn_movdqu_m128_xmm_disp(0,' <<<"$x64_ctx_xmm_impl" | wc -l | tr -d ' ')" != "16" ]] ||
  [[ "$(grep -F 'core.insn_movdqu_xmm_m128_disp(' <<<"$x64_ctx_xmm_impl" | wc -l | tr -d ' ')" != "16" ]] ||
  ! grep -Fq 'core.insn_movdqu_m128_xmm_disp(0, 368, 15)' <<<"$x64_ctx_xmm_impl" ||
  ! grep -Fq 'core.insn_movdqu_xmm_m128_disp(15, 9, 368)' <<<"$x64_ctx_xmm_impl" ||
  grep -Fq 'while xi < 16' <<<"$x64_ctx_xmm_impl"; then
  echo "ERROR: x64 context-switch XMM save/restore emission must stay straight-line, not fixed compiler loops" >&2
  exit 1
fi
x64_named_call_core_impl="$(sed -n '/fn _x64_emit_named_call_list_int_len_v0/,/fn _x64_emit_named_call_call_obj_list_v0/p' lib/compiler/x64_native_program/044_emit_call_expr.oren)"
if ! grep -Fq 'fn _x64_emit_named_call_index_intrinsic_v0' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq 'fn _x64_emit_named_call_list_intrinsic_v0' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq 'fn _x64_emit_named_call_list_int_len_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq 'fn _x64_emit_named_call_list_int_access_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq 'fn _x64_emit_named_call_list_int_fast_slots_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq 'fn _x64_emit_named_call_core_intrinsic_v0' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq '_x64_emit_named_call_index_intrinsic_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq '_x64_emit_named_call_list_intrinsic_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl" ||
  ! grep -Fq '_x64_emit_named_call_list_int_intrinsic_v0(ctx, expr, locals, nm)' <<<"$x64_named_call_core_impl"; then
  echo "ERROR: x64 named-call core intrinsic dispatch must keep index/list/list-int routing in split helpers" >&2
  exit 1
fi
x64_program_entry_shape_impl="$(cat lib/compiler/x64_native_program/090_program_entry/020_part_b.oren)
$(cat lib/compiler/x64_native_program/090_program_entry/010_part_a.oren)
$(sed -n '/fn _x64_rtobj_symtab_compact_names/,/fn _x64_reserve_debug_symtab/p' lib/compiler/x64_native_program/090_program_entry/089_debug_roots.oren)
$(sed -n '/fn _x64_reserve_debug_symtab/,/fn _x64_setup_program_debug_metadata/p' lib/compiler/x64_native_program/090_program_entry/089_debug_roots.oren)
$(sed -n '/fn _x64_collect_global_root_vector_entry/,/fn _x64_setup_program_debug_metadata/p' lib/compiler/x64_native_program/090_program_entry/089_debug_roots.oren)"
if ! grep -Fq 'fn _x64_slow_fn_top_insert_index' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_merge_cstr0_offs(ctx, offs, trace)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_stash_cstr0_lists(ctx, meta, trace)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_apply_rip_data32_map(ctx, r32, base_code, trace)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_apply_rip_data32_label(ctx, base_code, lab2, xs2)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_log_rip_data32_done(phase_log, labels_n)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_symtab_compact_names(ctx)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_push_rtobj_symtab_name(ctx, sym_seen, sym_names, rnm)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_push_rtobj_symtab_names_list(ctx, sym_seen, sym_names, rt_names)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_push_rtobj_symtab_names_map(ctx, sym_seen, sym_names, enc_map)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_push_debug_function_names(sym_seen, sym_names, fns)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_push_debug_import_names(sym_seen, sym_names, imports0)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_rtobj_meta_fixups(ctx, meta)' <<<"$x64_program_entry_shape_impl" || ! grep -Fq 'fn _x64_rtobj_meta_function_info(ctx, meta)' <<<"$x64_program_entry_shape_impl" || ! grep -Fq 'fn _x64_rtobj_compile_decl_phase(ctx, fns, platform, call_depth_default_enabled, phase_log, trace, trace_state, decl_state)' <<<"$x64_program_entry_shape_impl" || ! grep -Fq 'fn _x64_rtobj_compile_wrapper_phase(ctx, wrappers, platform, call_depth_default_enabled, phase_log, trace, trace_state, decl_state)' <<<"$x64_program_entry_shape_impl" ||
  ! grep -Fq 'fn _x64_collect_global_root_vector_entry(ctx, root_offsets, trace_root_names, root_names_src, root_offsets_src, root_runtime_src, runtime_globals, skip_runtime_globals, gi, arg_reg, name_reg)' <<<"$x64_program_entry_shape_impl" || ! grep -Fq 'fn _x64_collect_global_root_map_entry(ctx, root_offsets, trace_root_names, runtime_globals, skip_runtime_globals, pair, arg_reg, name_reg)' <<<"$x64_program_entry_shape_impl" || ! grep -Fq 'fn _x64_map_global_root_is_runtime(runtime_globals, gname)' <<<"$x64_program_entry_shape_impl"; then
  echo "ERROR: x64 program-entry trace/cstr/debug/global-root helpers must stay split into focused parser bodies" >&2; exit 1
fi
x64_string_batch_input_split_impl="$(sed -n '/fn _x64_string_batch_input_state/,/fn _x64_string_batch_prepare_op/p' lib/compiler/x64_native_program/060_emit_ops_string_batch.oren)"
if ! grep -Fq 'fn _x64_string_batch_input_lists(op)' <<<"$x64_string_batch_input_split_impl" ||
  ! grep -Fq 'fn _x64_string_batch_input_counts(lists)' <<<"$x64_string_batch_input_split_impl"; then
  echo "ERROR: x64 string-batch input state must keep list extraction and count derivation split" >&2; exit 1
fi
x64_string_batch_trace_split_impl="$(sed -n '/fn _x64_string_batch_trace_state/,/fn _x64_string_batch_collect_items/p' lib/compiler/x64_native_program/060_emit_ops_string_batch.oren)"
if ! grep -Fq 'fn _x64_string_batch_trace_phase(ctx)' <<<"$x64_string_batch_trace_split_impl" || ! grep -Fq 'fn _x64_string_batch_trace_progress_enabled(phase_log, phase_name)' <<<"$x64_string_batch_trace_split_impl" || ! grep -Fq 'fn _x64_string_batch_trace_start(phase_log, phase_name, j, batch_n, batch_names_n, batch_items_n, batch_off_encs_n, batch_slot_offs_src_n)' <<<"$x64_string_batch_trace_split_impl" || ! grep -Fq 'fn _x64_string_batch_collect_counts(batch_names, batch_values, batch_off_encs, batch_slot_offs_src)' <<<"$x64_string_batch_trace_split_impl" || ! grep -Fq 'fn _x64_string_batch_collect_one(batch_collect_i, batch_names, batch_values, batch_off_encs, batch_slot_offs_src, counts)' <<<"$x64_string_batch_trace_split_impl"; then
  echo "ERROR: x64 string-batch trace state must keep phase lookup, env gating, and start logging split" >&2; exit 1
fi
x64_assign_i32_split_impl="$(sed -n '/fn _x64_assign_i32_state/,/fn _x64_emit_ops_trace_progress/p' lib/compiler/x64_native_program/060_emit_ops.oren)"
if ! grep -Fq 'fn _x64_assign_i32_state(ctx, op, locals, top_string_fast_stats)' <<<"$x64_assign_i32_split_impl" || ! grep -Fq 'fn _x64_emit_assign_i32_fast_paths(ctx, op, platform, j, op_start_ns, op_slow_ms, top_string_fast_stats, top_string_fast_candidate)' <<<"$x64_assign_i32_split_impl" || ! grep -Fq 'fn _x64_emit_assign_i32_checked_value(ctx, op, locals, top_string_fast_candidate)' <<<"$x64_assign_i32_split_impl" || ! grep -Fq 'fn _x64_emit_assign_i32_result_store(ctx, op, off2)' <<<"$x64_assign_i32_split_impl"; then
  echo "ERROR: x64 assign_i32 lowering must keep state, fast paths, checked value emission, and result store split" >&2; exit 1
fi
x64_envblock_capture_split_impl="$(sed -n '/fn _emit_entry_capture_envblock_windows_x64/,/fn _x64_win_entry_args_state/p' lib/compiler/x64_native_program/090_program_entry/000_prelude.oren)"
if ! grep -Fq 'fn _x64_emit_get_environment_strings_call(ctx)' <<<"$x64_envblock_capture_split_impl" ||
  ! grep -Fq 'fn _x64_store_envblock_in_entry_scratch(ctx, scratch_base)' <<<"$x64_envblock_capture_split_impl"; then
  echo "ERROR: Windows x64 envblock capture must keep GetEnvironmentStringsA call and scratch-store helpers split" >&2; exit 1
fi
x64_windows_errno_impl="$(sed -n '/fn _emit_win32_last_error_file_cases_x64/,/fn _emit_win32_last_error_to_neg_errno_common_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren)
$(sed -n '/fn _emit_wsa_last_error_progress_cases_x64/,/fn _emit_intrinsic_sys_wsa_get_last_error_windows_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net.oren)"
if ! grep -Fq 'fn _emit_win32_last_error_file_cases_x64(ctx, labels, fixups, l_done)' <<<"$x64_windows_errno_impl" ||
  ! grep -Fq 'fn _emit_win32_last_error_fs_state_cases_x64(ctx, labels, fixups, l_done)' <<<"$x64_windows_errno_impl" ||
  ! grep -Fq 'fn _emit_wsa_last_error_progress_cases_x64(ctx, labels, fixups, l_done)' <<<"$x64_windows_errno_impl" ||
  ! grep -Fq 'fn _emit_wsa_last_error_socket_cases_x64(ctx, labels, fixups, l_done)' <<<"$x64_windows_errno_impl"; then
  echo "ERROR: x64 Windows errno mapping must keep Win32/WSA case families split into focused helpers" >&2; exit 1
fi
x64_parser_helper_split_impl="$(sed -n '/fn _intr_tmp_pool_off/,/fn _x64_tmp_intr_name/p' lib/compiler/x64_native_program/035_intr_temps.oren)
$(sed -n '/fn _x64_fast_list_get_sum_abi_regs/,/fn _x64_fast_list_get_sum_emit_sum_flag/p' lib/compiler/x64_native_program/057_emit_ops_while_list_get_sum.oren)
$(sed -n '/fn _x64_win_cp_prepare_tmp_slots/,/fn _x64_win_cp_spill_args_and_zero/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_proc.oren)
$(sed -n '/fn _x64_win_cp_emit_validate_cmd/,/fn _x64_win_cp_emit_create_register_args/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_proc.oren)
$(sed -n '/fn _x64_win_cp_emit_create_register_args/,/fn _x64_win_cp_emit_create_result/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_proc.oren) $(sed -n '/fn _x64_win_cp_emit_wait_dispatch/,/fn _x64_win_cp_emit_wait_timeout/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_proc.oren)
$(sed -n '/fn _x64_call_obj_list_intrinsic_state/,/fn _x64_call_obj_list_abi_regs/p' lib/compiler/x64_native_program/044_emit_call_expr.oren)
$(sed -n '/fn _x64_load_direct_call_reg_arg_v0/,/fn _x64_emit_direct_call_fixup_and_return_v0/p' lib/compiler/x64_native_program/044_emit_call_expr.oren)
$(sed -n '/fn _x64_indirect_call_runtime_ready/,/fn _x64_spawn_spill_explicit_args/p' lib/compiler/x64_native_program/044_emit_call_expr.oren)
$(sed -n '/fn _x64_varargs_named_call_emit_prepared/,/fn _x64_emit_named_call_statement_only_v0/p' lib/compiler/x64_native_program/044_emit_call_expr.oren)
$(sed -n '/fn _x64_member_emit_namespace_value/,/fn _emit_member_expr_v0/p' lib/compiler/x64_native_program/045_emit_member_expr.oren) $(sed -n '/fn _x64_local_var_offset/,/fn _emit_load_var_to_reg_x64/p' lib/compiler/x64_native_program/036_emit_var_helpers.oren) $(sed -n '/fn _x64_fn_value_needs_suffix_lookup/,/fn _emit_named_function_value_to_rax/p' lib/compiler/x64_native_program/040_emit_expr_eval.oren) $(sed -n '/fn _x64_emit_cmp_string_ptr_check_one/,/fn _x64_emit_cmp_string_returns/p' lib/compiler/x64_native_program/050_emit_cmp_labels.oren) $(sed -n '/fn _x64_gc_root_insert_sorted/,/fn _emit_gc_root_push_locals_x64/p' lib/compiler/x64_native_program/055_emit_ops_locals.oren)"
if ! grep -Fq 'fn _intr_tmp_pool_off(ctx, idx)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _intr_tmp_named_off(ctx, locals, idx)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_fast_list_get_sum_abi_regs(ctx)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_fast_list_get_sum_local_offsets(info, locals)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_fast_list_get_sum_info_parts(info)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_prepare_tmp_slots(ctx, locals, base)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_layout_offsets()' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_check_call_area(ctx, base, need_call_area)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_prepare_layout(ctx, base)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_validate_cmd(ctx, st, labels, fixups, l_cleanup)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_startup_info(ctx, st)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_create_zero_stack_args(ctx)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_create_env_arg(ctx, st)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_create_current_dir_arg(ctx)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_win_cp_emit_create_output_args(ctx, st)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_win_cp_emit_poll_wait_once(ctx, st, labels, fixups, l_wait_done, l_cleanup)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_call_obj_list_intrinsic_spill_fn(ctx, locals, fn_obj_expr, st)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_load_direct_call_reg_arg_v0(ctx, i3, tmp_off2)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_check_direct_call_stack_area(ctx, stack_disp2, slot2)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_load_direct_call_stack_arg_v0(ctx, i3, regc2, shadow2, slot2, tmp_off2)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_load_direct_call_arg_v0(ctx, locals, base2, i3, regc2, shadow2, slot2)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_indirect_call_emit_nospread(ctx, locals, fn_obj_expr, args, argc)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_spawn_call_parts(ctx, expr)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_spawn_prepare_state(parts, args, argc, spread, has_spread, base)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_varargs_named_call_emit_prepared(ctx, locals, st)' <<<"$x64_parser_helper_split_impl" ||
  ! grep -Fq 'fn _x64_member_index_expr(ctx, expr)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_local_var_offset(locals, name)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_emit_load_global_to_reg(ctx, name, dst_reg)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_resolve_unique_fn_suffix(ctx, fn_name)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_emit_cmp_string_byte_order(ctx, names, fixups)' <<<"$x64_parser_helper_split_impl" || ! grep -Fq 'fn _x64_gc_root_insert_sorted(offs, seen, off)' <<<"$x64_parser_helper_split_impl"; then
  echo "ERROR: x64 temp, list-sum, Windows process, call-expression, direct-call, member, var-load, function-value, compare, and GC-root preparation must stay split into focused parser helpers" >&2; exit 1
fi
x64_data_lookup_split_impl="$(sed -n '/fn _x64_data_lookup_direct_function_offset/,/fn _data_symtab_state/p' lib/compiler/x64_native_program/010_data_io.oren)"
if ! grep -Fq 'fn _x64_data_lookup_direct_function_offset(ctx, nm)' <<<"$x64_data_lookup_split_impl" || ! grep -Fq 'fn _x64_data_lookup_compact_function_offset(ctx, nm, base)' <<<"$x64_data_lookup_split_impl" || ! grep -Fq 'fn _x64_data_lookup_encoded_function_offset(ctx, nm, base)' <<<"$x64_data_lookup_split_impl"; then
  echo "ERROR: x64 data function-offset lookup must keep direct, compact, and encoded-map paths split" >&2; exit 1
fi
x64_list_int_set_split_impl="$(sed -n '/fn _x64_list_int_set_alloc_spill_state/,/fn _x64_prepare_list_int_reduce_sum_slots_unchecked_intrinsic/p' lib/compiler/x64_native_program/045_emit_list_intrinsics.oren)"
if ! grep -Fq 'fn _x64_list_int_set_eval_spill_arg(ctx, locals, expr, base, off)' <<<"$x64_list_int_set_split_impl" || ! grep -Fq 'fn _x64_emit_list_int_set_slow_path(ctx, locals, state)' <<<"$x64_list_int_set_split_impl" || ! grep -Fq 'fn _x64_emit_list_int_set_fast_path(ctx, state)' <<<"$x64_list_int_set_split_impl"; then
  echo "ERROR: x64 LIST_INT set lowering must keep arg spill, slow path, and fast path helpers split" >&2; exit 1
fi
x64_fast_push_loop_split_impl="$(sed -n '/fn _x64_fast_list_int_push_emit_cap_check/,/fn _x64_fast_list_push_update_counts/p' lib/compiler/x64_native_program/057_emit_ops_while_emit.oren)"
if ! grep -Fq 'fn _x64_fast_list_int_push_emit_cap_check(ctx, prep, local_fixups, slot_list, l_cap_ok)' <<<"$x64_fast_push_loop_split_impl" || ! grep -Fq 'fn _x64_fast_list_int_push_emit_reserve_call(ctx, prep, slot_list)' <<<"$x64_fast_push_loop_split_impl" || ! grep -Fq 'fn _x64_fast_push_emit_loop_entry(ctx, prep, locals, labels, label_names, local_fixups)' <<<"$x64_fast_push_loop_split_impl" || ! grep -Fq 'fn _x64_fast_push_emit_loop_values(ctx, prep, locals)' <<<"$x64_fast_push_loop_split_impl" || ! grep -Fq 'fn _x64_fast_push_emit_loop_common(ctx, prep, locals, labels, label_names, local_fixups)' <<<"$x64_fast_push_loop_split_impl"; then echo "ERROR: x64 LIST/LIST_INT fast-push loops must share split reserve, entry, value, and body helpers" >&2; exit 1; fi
x64_literal_callable_split_impl="$(sed -n '/fn _lit_hash_pairs/,/fn _lit_array_elements/p' lib/compiler/x64_native_program/043_emit_literals.oren)
$(sed -n '/fn _lit_array_depth_state/,/fn _emit_hash_literal_expr/p' lib/compiler/x64_native_program/043_emit_literals.oren)
$(sed -n '/fn _emit_hash_literal_expr/,/fn _lit_hash_prepare_state/p' lib/compiler/x64_native_program/043_emit_literals.oren)
$(sed -n '/fn _x64_collect_lambda_stmt_list/,/fn _x64_debug_print_lambda_collection/p' lib/compiler/x64_native_program/090_program_entry/087_callable_wrappers.oren)
$(sed -n '/fn _x64_synth_lambda_wrapper_expr/,/fn _x64_compile_lambda_wrappers/p' lib/compiler/x64_native_program/090_program_entry/087_callable_wrappers.oren) $(sed -n '/fn _x64_missing_fnwrap_arity_state/,/fn _x64_log_missing_fnwraps_done/p' lib/compiler/x64_native_program/090_program_entry/087_callable_wrappers.oren)"
if ! grep -Fq 'fn _lit_hash_emit_pairs(ctx, locals, hn, pairs, depth_enc0)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _lit_hash_prepare_state(ctx, expr, locals)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _lit_array_prepare_state(ctx, expr, locals)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _x64_collect_lambda_stmt_list(ctx, stmts_all)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _x64_collect_lambda_type_ctors(ctx, type_ctors)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _x64_log_lambda_collection_done(ctx, phase_log, lambda_scan_skipped)' <<<"$x64_literal_callable_split_impl" || ! grep -Fq 'fn _x64_collect_lambda_candidates(ctx, stmts_all, top_info, type_ctors, trace_prog)' <<<"$x64_literal_callable_split_impl" ||
  ! grep -Fq 'fn _x64_build_lambda_wrappers(ctx)' <<<"$x64_literal_callable_split_impl" || ! grep -Fq 'fn _x64_missing_fnwrap_arity_state(ctx, fname)' <<<"$x64_literal_callable_split_impl" || ! grep -Fq 'fn _x64_compile_synthesized_fnwrap(ctx, platform, call_depth_default_enabled, fname, wname, state)' <<<"$x64_literal_callable_split_impl"; then
  echo "ERROR: x64 array/hash literal and callable lambda preparation must stay split into focused parser helpers" >&2; exit 1
fi
x64_sys_data_split_impl="$(sed -n '/fn _x64_fcntl_getfl_translate_nonblock/,/fn _x64_sys_rw_linux_slots/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/000_prelude.oren)
$(sed -n '/fn _x64_emit_sys_write_windows_writefile/,/fn _emit_intrinsic_sys_write_linux_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/000_prelude.oren)
$(sed -n '/fn _x64_emit_fcntl_setfl_windows_prehook/,/fn _x64_iocp_emit_invalid_param_handle_eio/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren)
$(sed -n '/fn _x64_gettimeofday_windows_call_filetime/,/fn _x64_gettimeofday_windows_new_labels/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_gettimeofday_windows_new_labels/,/fn _x64_qpc_frequency_prepare_windows/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_emit_getentropy_windows_rng_args/,/fn _x64_emit_getentropy_windows_finish/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_win_wait_single_object_result_labels/,/fn _emit_intrinsic_sys_win_wait_single_object_windows_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_threads.oren)
$(sed -n '/fn _x64_linux_epoll_create1_state/,/fn _x64_linux_epoll_ctl_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_linux_net.oren)
$(sed -n '/fn _x64_wsa_store_wsabuf_local/,/fn _x64_wsarecv_normalize_result/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren) $(sed -n '/fn _x64_cancel_io_ex_result_labels/,/fn _emit_intrinsic_sys_cancel_io_ex_windows_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren)
$(sed -n '/fn _emit_win64_stat_regular_file_mode_x64/,/fn _x64_windows_stat_finish/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren)
$(sed -n '/fn _x64_windows_fstat_labels/,/fn _x64_unlink_rmdir_windows_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren)
$(sed -n '/fn _emit_nanosleep_timespec_syscall_x64/,/fn _x64_linux_nanosleep_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/090_tail.oren) $(sed -n '/fn _x64_windows_open_alloc_state/,/fn _x64_windows_open_labels/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _emit_windows_write_ptr_len/,/fn _emit_panic_preserve_msg_reg/p' lib/compiler/x64_native_program/071_panic.oren)
$(sed -n '/fn _data_cstr0_normalize_sentinel/,/fn _data_add_fnobj/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_reserve_u64_table_region/,/fn _x64_data_rtobj_decode_enc0/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_store_linetab_reservation/,/fn _data_finalize_linetab/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_dbginfo_entry_offsets/,/fn _data_finalize_linetab_table/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _x64_ffi_resolver_linux_name/,/fn _x64_ffi_stub_linux_dyn_data/p' lib/compiler/x64_native_program/072_ffi.oren)
$(sed -n '/fn _x64_new_ctx_base_buffers/,/fn _x64_new_ctx_aliases/p' lib/compiler/x64_native_program/090_program_entry/000_prelude.oren)
$(sed -n '/fn _x64_new_ctx_runtime_cstr_slot/,/fn _x64_new_ctx_trace_flags/p' lib/compiler/x64_native_program/090_program_entry/000_prelude.oren)"
if ! grep -Fq 'fn _x64_gettimeofday_windows_emit_body(ctx, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_gettimeofday_windows_call_filetime(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_gettimeofday_windows_filetime_to_unix(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_gettimeofday_windows_store_wall_time(ctx, tmp_tv)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_getentropy_windows_rng_len_guard(ctx, state)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_getentropy_windows_rng_call(ctx, state)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_win_wait_single_object_result_labels(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_win_wait_single_object_emit_status_paths(ctx, labels, fixups, wlab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_linux_epoll_create1_state(ctx, locals, args)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_linux_epoll_create1_syscall(ctx, st)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_wsa_store_wsabuf_local(ctx, state)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_wsa_load_common_receive_args(ctx, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_wsa_overlapped_labels(ctx, label_prefix)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_wsa_overlapped_emit_error_path(ctx, lab)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_cancel_io_ex_emit_failure(ctx, labels, fixups, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_sys_windows_zero_len_guard(ctx, tmp_len, local_fixups, l_ret0)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_sys_read_windows_labels(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_sys_read_windows_body(ctx, locals, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_sys_read_windows_finish(ctx, labels, local_fixups, l_ret0, l_done, base)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_sys_write_windows_labels(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_sys_write_windows_body(ctx, locals, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_sys_write_windows_finish(ctx, labels, local_fixups, l_ret0, l_done, base)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_fcntl_setfl_windows_labels()' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_fcntl_setfl_windows_body(ctx, state, capsule, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_finish_fcntl_setfl_windows(ctx, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_win64_stat_file_size_probe_x64(ctx, tmp_st, tmp_handle)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_stat_emit_attr_prepare(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_windows_fstat_labels(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_windows_fstat_emit_body(ctx, locals, state, flab, labels, fixups)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_fstat_emit_done(ctx, labels, fixups, capsule, base, l_done)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_nanosleep_timespec_on_stack_x64(ctx, tmp_ns)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_open_alloc_state(ctx, locals)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_open_spill_args(ctx, locals, args, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _data_cstr0_normalize_sentinel(s)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _data_dbginfo_entry_offsets(entries, i, code_len)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_windows_writefile_stdout_handle(ctx, ptr_reg, len_reg)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_reserve_u64_table_region(ctx, count)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_store_linetab_reservation(ctx, linetab_off, cap_entries)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_emit_cstr0_table(ctx, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_fcntl_getfl_translate_success(ctx, labels, fixups)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_emit_sys_read_windows_stdin_handle(ctx, local_fixups, tmp_fd, l_have_handle)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_emit_dbginfo_table(ctx, platform, entries)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_ffi_resolver_linux_emit_body(ctx, got_dlsym)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_new_ctx_base_functions(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_new_ctx_runtime_boot_globals(ctx, trace_ctx)' <<<"$x64_sys_data_split_impl"; then
  echo "ERROR: x64 system read/write/fcntl/stat/panic/data-table reservation/emission, FFI, and context setup codegen must keep split focused helper bodies" >&2; exit 1
fi
x64_function_frame_split_impl="$(sed -n '/fn _x64_frame_align_unit/,/fn _x64_emit_compiled_function_body/p' lib/compiler/x64_native_program/080_functions_compile.oren)"
if ! grep -Fq 'fn _x64_frame_align_unit(ctx)' <<<"$x64_function_frame_split_impl" ||
  ! grep -Fq 'fn _x64_frame_align_bytes(n, align, step)' <<<"$x64_function_frame_split_impl" ||
  ! grep -Fq 'fn _x64_frame_call_area(ctx, max_call_argc, align)' <<<"$x64_function_frame_split_impl" ||
  ! grep -Fq 'fn _x64_frame_save_state(ctx, align)' <<<"$x64_function_frame_split_impl" ||
  ! grep -Fq 'fn _x64_prepare_function_base_slots(ctx, fn_node, name, ops)' <<<"$x64_function_frame_split_impl" ||
  ! grep -Fq 'fn _x64_prepare_function_temp_slots(ctx, ops, locals, local_next, needs_literal_slots)' <<<"$x64_function_frame_split_impl" || ! grep -Fq 'fn _x64_emit_function_save_regs(ctx, save_regs, save_n, locals_size)' <<<"$x64_function_frame_split_impl" || ! grep -Fq 'fn _x64_emit_function_param_spill(ctx, locals, params, i, regc, shadow)' <<<"$x64_function_frame_split_impl" || ! grep -Fq 'fn _x64_begin_function_phase_start(phase_log, name, phase_this, phase_summary_only)' <<<"$x64_function_frame_split_impl" || ! grep -Fq 'fn _x64_emit_compiled_function_call_depth(ctx, fn_node, name, compile_opts, phase_state)' <<<"$x64_function_frame_split_impl"; then
  echo "ERROR: x64 function-frame layout and local-slot preparation must stay split into focused helpers" >&2; exit 1
fi
x64_ffi_attr_split_impl="$(sed -n '/fn _x64_collect_ffi_dll_attrs/,/fn _x64_ffi_ret_maps_init/p' lib/compiler/x64_native_program/072_ffi.oren)"
if ! grep -Fq 'fn _x64_ffi_dll_outputs(ctx)' <<<"$x64_ffi_attr_split_impl" ||
  ! grep -Fq 'fn _x64_ffi_attr_is_dll(a)' <<<"$x64_ffi_attr_split_impl" ||
  ! grep -Fq 'fn _x64_ffi_dll_attr_value(ctx, nm, a)' <<<"$x64_ffi_attr_split_impl" ||
  ! grep -Fq 'fn _x64_ffi_remember_dll(seen, out, val)' <<<"$x64_ffi_attr_split_impl"; then
  echo "ERROR: x64 FFI DLL attribute collection must keep validation and dedup helpers split" >&2; exit 1
fi
x64_stack_trace_split_impl="$(sed -n '/fn _emit_stack_trace_best_effort/,/fn _emit_stack_trace_release_scratch/p' lib/compiler/x64_native_program/071_panic.oren)"
if ! grep -Fq 'fn _stack_trace_scratch_layout()' <<<"$x64_stack_trace_split_impl" ||
  ! grep -Fq 'fn _emit_stack_trace_prepare_scratch(ctx)' <<<"$x64_stack_trace_split_impl" ||
  ! grep -Fq 'fn _emit_stack_trace_for_platform(ctx, platform, scratch)' <<<"$x64_stack_trace_split_impl" ||
  ! grep -Fq 'fn _emit_stack_trace_release_scratch(ctx)' <<<"$x64_stack_trace_split_impl"; then
  echo "ERROR: x64 stack-trace best-effort emission must keep scratch setup and platform dispatch split" >&2; exit 1
fi
x64_call_fast_path_split_impl="$(sed -n '/fn _x64_call_name_has_oren_buf_prefix/,/fn _x64_emit_internal_fast_core_or_push/p' lib/compiler/x64_native_program/040_emit_call_fast_paths.oren)"
if ! grep -Fq 'fn _x64_call_name_has_oren_buf_prefix(nm)' <<<"$x64_call_fast_path_split_impl" ||
  ! grep -Fq 'fn _x64_call_name_has_buf_new_suffix(nm, nm_len)' <<<"$x64_call_fast_path_split_impl" ||
  ! grep -Fq 'fn _x64_call_name_is_buf_runtime(nm, nm_len)' <<<"$x64_call_fast_path_split_impl"; then
  echo "ERROR: x64 call fast-path runtime-name classification must keep prefix/suffix checks split and allocation-free" >&2; exit 1
fi
x64_index_map_split_impl="$(sed -n '/fn _x64_index_emit_map_path/,/fn _x64_index_dynamic_labels/p' lib/compiler/x64_native_program/045_emit_index_expr.oren)"
if ! grep -Fq 'fn _x64_index_emit_map_magic_if_known(ctx, recv_kind, labels, local_fixups)' <<<"$x64_index_map_split_impl" ||
  ! grep -Fq 'fn _x64_index_emit_map_runtime_get(ctx, locals, known_kk, tmp0, tmp_idx, local_fixups, l_idx_done)' <<<"$x64_index_map_split_impl"; then
  echo "ERROR: x64 map-index lowering must keep magic validation and runtime get dispatch split" >&2
  exit 1
fi
x64_strlen_ptr_split_impl="$(sed -n '/fn _emit_string_len_from_ptr_x64/,/fn _x64_emit_known_int_add_x64/p' lib/compiler/x64_native_program/046_emit_string_helpers.oren)"
if ! grep -Fq 'fn _x64_strlen_ptr_labels(ctx)' <<<"$x64_strlen_ptr_split_impl" ||
  ! grep -Fq 'fn _x64_strlen_ptr_prepare(ctx, ptr_reg, dst_reg, state)' <<<"$x64_strlen_ptr_split_impl" ||
  ! grep -Fq 'fn _x64_strlen_ptr_emit_loop(ctx, dst_reg, state)' <<<"$x64_strlen_ptr_split_impl" ||
  ! grep -Fq 'fn _x64_strlen_ptr_finish(ctx, state)' <<<"$x64_strlen_ptr_split_impl"; then
  echo "ERROR: x64 pointer strlen emission must keep labels, setup, loop, and finish helpers split" >&2
  exit 1
fi
x64_float_cmp_branch_impl="$(sed -n '/fn _x64_float_cmp_emit_two_jcc_then_done/,/fn _emit_float_cmp_to_bool_x64/p' lib/compiler/x64_native_program/047_emit_float_intrinsics.oren)"
if ! grep -Fq 'fn _x64_float_cmp_emit_two_jcc_then_done(ctx, local_fixups, cc0, lab0, cc1, lab1, l_done)' <<<"$x64_float_cmp_branch_impl" ||
  ! grep -Fq 'fn _x64_float_cmp_emit_ordered_true(ctx, local_fixups, cc_true, l_true, l_done)' <<<"$x64_float_cmp_branch_impl" ||
  ! grep -Fq 'return _x64_float_cmp_emit_two_jcc_then_done(ctx, local_fixups, "p", l_true, "ne", l_true, l_done)' <<<"$x64_float_cmp_branch_impl"; then
  echo "ERROR: x64 float compare branching must keep shared ordered/unordered helper emission" >&2
  exit 1
fi
arm64_gemm_store_helper_impl="$(sed -n '/fn arm64_emit_store_d_reg_to_cursor/,/fn native_emit_panic/p' lib/compiler/arm64_native_expr/000_prelude.oren)"
if ! grep -Fq 'fn arm64_emit_store_d_regs_0_15_to_cursor' <<<"$arm64_gemm_store_helper_impl" ||
  ! grep -Fq 'fn arm64_emit_addp_store_d_regs_0_15_to_cursor' <<<"$arm64_gemm_store_helper_impl" ||
  [[ "$(grep -F 'arm64_emit_store_d_reg_to_cursor(ctx, tmp_reg, cursor_reg,' <<<"$arm64_gemm_store_helper_impl" | wc -l | tr -d ' ')" -lt "16" ]] ||
  [[ "$(grep -F 'arm64_emit_addp_store_d_reg_to_cursor(ctx, tmp_reg, cursor_reg,' <<<"$arm64_gemm_store_helper_impl" | wc -l | tr -d ' ')" -lt "16" ]] ||
  grep -Fq 'while storei < 16' lib/compiler/arm64_native_expr/036_lowering_c_simd.oren ||
  grep -Fq 'while rr < 16' lib/compiler/arm64_native_expr/040_lowering_d.oren lib/compiler/arm64_native_expr/060_lowering_f.oren; then
  echo "ERROR: ARM64 GEMM result stores must use shared straight-line V0..V15 store helpers, not fixed compiler loops" >&2
  exit 1
fi

base64_encode_byte_impl="$(sed -n '/fn _b64_encode_byte/,/fn b64_is_ws/p' lib/std/encoding/base64.oren)"
if ! grep -Fq 'fn _b64_encode_byte(v)' <<<"$base64_encode_byte_impl" ||
  ! grep -Fq 'fn _b64url_encode_byte(v)' <<<"$base64_encode_byte_impl" ||
  ! grep -Fq 'if v < 26 { return 65 + v }' <<<"$base64_encode_byte_impl" ||
  ! grep -Fq 'if v < 52 { return 97 + (v - 26) }' <<<"$base64_encode_byte_impl" ||
  ! grep -Fq 'if v < 62 { return 48 + (v - 52) }' <<<"$base64_encode_byte_impl" ||
  ! grep -Fq 'fn _input_byte_direct(input_bytes, input_ptr, idx)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'if input_ptr != nil { return ptr_get_byte(input_ptr + idx) & 255 }' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var input_ptr = bytesm.view_ptr(input_view)' lib/std/encoding/base64.oren ||
  grep -Fq 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' lib/std/encoding/base64.oren ||
  grep -Fq 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_' lib/std/encoding/base64.oren ||
  grep -Fq '_str_byte(table' lib/std/encoding/base64.oren ||
  grep -Fq '_b64_char(' lib/std/encoding/base64.oren ||
  grep -Fq '_b64url_char(' lib/std/encoding/base64.oren ||
  grep -Fq 'fn _input_byte(input_view, idx)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'encode list_int value' tests/modules/test_base64.oren ||
  ! grep -Fq 'encode standard alphabet tail' tests/modules/test_base64.oren ||
  ! grep -Fq 'base64url list_int alphabet' tests/modules/test_base64.oren; then
  echo "ERROR: Base64 encode must use arithmetic alphabet mapping, cached input pointers, and LIST_INT/u8_buf coverage" >&2
  exit 1
fi

if grep -Fq 'while j < core_len' lib/std/encoding/base64.oren ||
  ! grep -Fq 'if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0' lib/std/encoding/base64.oren ||
  ! grep -Fq 'if r0 < 0 || r1 < 0' lib/std/encoding/base64.oren ||
  ! grep -Fq 'if r20 < 0 || r21 < 0 || r22 < 0' lib/std/encoding/base64.oren; then
  echo "ERROR: Base64URL decode must validate sextets inline instead of pre-scanning the full input" >&2
  exit 1
fi

if ! grep -Fq 'var _B64_DECODE = nil' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var _B64URL_DECODE = nil' lib/std/encoding/base64.oren ||
  ! grep -Fq 'fn _new_decode_table(default_value)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'return list.int_get(_b64_decode_table(), c)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'return list.int_get(_b64url_decode_table(), c)' lib/std/encoding/base64.oren ||
  grep -Fq 'if c >= 65 && c <= 90' lib/std/encoding/base64.oren ||
  grep -Fq 'if c >= 97 && c <= 122' lib/std/encoding/base64.oren ||
  grep -Fq 'if c >= 48 && c <= 57' lib/std/encoding/base64.oren; then
  echo "ERROR: Base64 decode value mapping must use cached list_int decode maps, not per-character range branches" >&2
  exit 1
fi

hpack_len_impl="$(sed -n '/fn _encoded_header_block_len/,/fn _encode_header_block_write/p' lib/std/net/hpack.oren)"
hpack_write_impl="$(sed -n '/fn _encode_header_block_write/,/fn encode_header_block/p' lib/std/net/hpack.oren)"
hpack_huffman_impl="$(sed -n '/var _HUFF_INITED/,/fn _static_get/p' lib/std/net/hpack.oren)"
if ! grep -Fq 'var literal_lens = list.int_new(list.len(headers) * 2)' <<<"$hpack_len_impl" ||
  ! grep -Fq 'list.int_push(literal_lens, n)' lib/std/net/hpack.oren ||
  ! grep -Fq 'return list.int_get(lens, i)' lib/std/net/hpack.oren ||
  ! grep -Fq 'return {"ok": 1, "n": out_len, "literal_lens": literal_lens}' <<<"$hpack_len_impl" ||
  ! grep -Fq 'fn _next_literal_len(meta)' lib/std/net/hpack.oren ||
  ! grep -Fq 'var literal_meta = {"lens": literal_lens, "i": 0}' <<<"$hpack_write_impl" ||
  ! grep -Fq '_encode_string_write_known_len(out, dst, pos, value, use_huffman, _next_literal_len(literal_meta))' <<<"$hpack_write_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, pos, s, 0, n)' lib/std/net/hpack.oren ||
  ! grep -Fq 'lr["literal_lens"]' lib/std/net/hpack.oren ||
  grep -Fq 'list.push(literal_lens, n)' lib/std/net/hpack.oren ||
  grep -Fq 'ptr_set_byte(dst + pos, oren_string_byte_at_unchecked(s, i)' lib/std/net/hpack.oren; then
  echo "ERROR: HPACK header encode must reuse sizing-pass string literal lengths through list_int metadata during write, not rescan or box Huffman literals" >&2
  exit 1
fi
if ! grep -Fq '_HUFF_L = list.int_new(1024)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq '_HUFF_R = list.int_new(1024)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq '_HUFF_SYM = list.int_new(1024)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq '_HUFF_EOS_PREFIX_NODE = list.int_new(8)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq 'list.int_push(_HUFF_L, -1)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq 'list.int_set(_HUFF_SYM, node, s)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq 'node = list.int_get(_HUFF_L, node)' <<<"$hpack_huffman_impl" ||
  ! grep -Fq 'var sym = list.int_get(_HUFF_SYM, node)' <<<"$hpack_huffman_impl" ||
  grep -Fq 'oren_list_push(_HUFF_' <<<"$hpack_huffman_impl" ||
  grep -Fq '_HUFF_L[node]' <<<"$hpack_huffman_impl" ||
  grep -Fq '_HUFF_SYM[node]' <<<"$hpack_huffman_impl"; then
  echo "ERROR: HPACK Huffman decode trie storage must use unboxed list_int tables, not boxed Oren lists" >&2
  exit 1
fi

net_url_concat_impl="$(sed -n '/fn _write_string/,/fn _lower_ascii/p' lib/std/net/url.oren)"
if ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, off, s, 0, n)' <<<"$net_url_concat_impl" ||
  grep -Fq 'ptr_set_byte(outp + off + i, _byte_at(s, i))' <<<"$net_url_concat_impl"; then
  echo "ERROR: std:net/url concat helpers must copy plain string spans directly into u8_buf output, not loop per byte" >&2
  exit 1
fi
net_url_encode_impl="$(sed -n '/fn encode_component/,/fn _decode_component/p' lib/std/net/url.oren)"
net_url_decode_impl="$(sed -n '/fn _decode_component/,/fn decode_component/p' lib/std/net/url.oren)"
net_url_write_encoded_impl="$(sed -n '/fn _write_encoded/,/fn build_query/p' lib/std/net/url.oren)"
if ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, j, s, start, run_n)' <<<"$net_url_encode_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, j, s, start, run_n)' <<<"$net_url_decode_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, j, s, start, run_n)' <<<"$net_url_write_encoded_impl" ||
  grep -Fq 'ptr_set_byte(p + j, b)' <<<"$net_url_encode_impl" ||
  grep -Fq 'ptr_set_byte(p + j, b2)' <<<"$net_url_decode_impl" ||
  grep -Fq 'ptr_set_byte(outp + j, b)' <<<"$net_url_write_encoded_impl"; then
  echo "ERROR: std:net/url percent encode/decode must copy unchanged string runs directly, not byte-by-byte" >&2
  exit 1
fi
net_url_hex_digit_impl="$(sed -n '/fn _hex_digit/,/fn _is_unreserved/p' lib/std/net/url.oren)"
if ! grep -Fq 'if d < 10 { return 48 + d }' <<<"$net_url_hex_digit_impl" ||
  ! grep -Fq 'return 55 + d' <<<"$net_url_hex_digit_impl" ||
  grep -Fq '0123456789ABCDEF' <<<"$net_url_hex_digit_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked' <<<"$net_url_hex_digit_impl"; then
  echo "ERROR: std:net/url percent encode must emit uppercase hex digits arithmetically, not index a digit string per nibble" >&2
  exit 1
fi
parser_generator_hex_impl="$(sed -n '/fn _generator_helper_hex_digit_byte/,/fn _generator_helper_file_hash/p' lib/compiler/parser_parse/000_prelude_generator.oren)"
if ! grep -Fq 'if n < 10 { return 48 + n }' <<<"$parser_generator_hex_impl" ||
  ! grep -Fq 'return 87 + n' <<<"$parser_generator_hex_impl" ||
  ! grep -Fq 'var out = oren_u8_buf_new_uninit(2)' <<<"$parser_generator_hex_impl" ||
  ! grep -Fq 'ptr_set_byte(data, _generator_helper_hex_digit_byte(hi))' <<<"$parser_generator_hex_impl" ||
  ! grep -Fq 'ptr_set_byte(data + 1, _generator_helper_hex_digit_byte(lo))' <<<"$parser_generator_hex_impl" ||
  ! grep -Fq 'return oren_string_from_bytes_slice(out, 0, 2)' <<<"$parser_generator_hex_impl" ||
  grep -Fq '0123456789abcdef' <<<"$parser_generator_hex_impl" ||
  grep -Fq '_generator_helper_hex_digit(hi) + _generator_helper_hex_digit(lo)' <<<"$parser_generator_hex_impl"; then
  echo "ERROR: parser generator file-hash hex must emit lowercase digits arithmetically into exact-size buffers" >&2
  exit 1
fi

http2_client_impl="$(sed -n '/fn _parse_content_length_value/,/fn _request_value/p' lib/std/net/http2_client.oren)"
http2_read_header_impl="$(sed -n '/fn _read_header_block/,/fn _send_headers_fragmented/p' lib/std/net/http2_client.oren)"
http2_send_headers_impl="$(sed -n '/fn _send_headers_fragmented/,/fn _new_record/p' lib/std/net/http2_client.oren)"
if ! grep -Fq 'fn _u8_acc_new_exact(capacity)' lib/std/net/http2_client.oren ||
  ! grep -Fq 'fn _headers_content_length(hs)' <<<"$http2_client_impl" ||
  ! grep -Fq 'var body_expected_len = _headers_content_length(hs)' <<<"$http2_client_impl" ||
  ! grep -Fq 'var empty_body = oren_u8_buf_new_uninit(0)' <<<"$http2_client_impl" ||
  ! grep -Fq 'body_acc = _u8_acc_new_exact(body_expected_len)' <<<"$http2_client_impl" ||
  ! grep -Fq 'body_acc["len"] + pn > body_expected_len' <<<"$http2_client_impl" ||
  ! grep -Fq 'body_acc["len"] != body_expected_len' <<<"$http2_client_impl" ||
  ! grep -Fq '_expect_binary_body(rr3.bytes())' tests/native/test_http2_headers_loopback.oren ||
  ! grep -Fq 'if oren_is_err(rr4) != true' tests/native/test_http2_headers_loopback.oren ||
  ! grep -Fq '{"name": "content-length", "value": "5", "index": "no"}' tests/native/test_http2_headers_loopback.oren ||
  grep -Fq 'var body_acc = _u8_acc_new(0)' <<<"$http2_client_impl"; then
  echo "ERROR: HTTP/2 response bodies with content-length must use exact-capacity u8 accumulation and validate DATA length" >&2
  exit 1
fi
http2_empty_body_line="$(printf '%s\n' "$http2_client_impl" | nl -ba | grep -F 'var empty_body = oren_u8_buf_new_uninit(0)' | awk '{print $1}' | head -1)"
http2_body_acc_line="$(printf '%s\n' "$http2_client_impl" | nl -ba | grep -F 'var body_acc = nil' | awk '{print $1}' | head -1)"
if [[ -z "$http2_empty_body_line" || -z "$http2_body_acc_line" || "$http2_empty_body_line" -ge "$http2_body_acc_line" ]]; then
  echo "ERROR: HTTP/2 header-only responses must return empty bodies before allocating DATA accumulators" >&2
  exit 1
fi

if ! grep -Fq 'var exact_acc = _u8_acc_new_exact(hb_len + fr_len)' <<<"$http2_read_header_impl" ||
  ! grep -Fq 'exact_rc = _u8_acc_append(exact_acc, fr["payload"])' <<<"$http2_read_header_impl" ||
  ! grep -Fq 'hb = _u8_acc_finish(exact_acc)' <<<"$http2_read_header_impl" ||
  ! grep -Fq 'var acc = _u8_acc_new(hb_len + fr_len + 64)' <<<"$http2_read_header_impl" ||
  grep -Fq 'fn _u8_concat2_exact(a, b)' lib/std/net/http2_client.oren ||
  grep -Fq 'hb = _u8_concat2_exact(hb, fr["payload"])' <<<"$http2_read_header_impl" ||
  grep -Fq 'var acc = _u8_acc_new(hb_len + 64)' <<<"$http2_read_header_impl"; then
  echo "ERROR: HTTP/2 inbound header blocks must exact-accumulate single CONTINUATION and reserve first continuation length before geometric multi-frame accumulation" >&2
  exit 1
fi

if ! grep -Fq 'fn _send_frame_raw_payload(conn, typ, flags, stream_id, payload_ptr, payload_len, timeout_ms)' lib/std/net/http2_client.oren ||
  ! grep -Fq 'while off < n {' <<<"$http2_send_headers_impl" ||
  ! grep -Fq '_send_frame_raw_payload(conn, h2.FRAME_HEADERS, headers_flags, stream_id, p, split_at, timeout_ms)' <<<"$http2_send_headers_impl" ||
  ! grep -Fq '_send_frame_raw_payload(conn, h2.FRAME_CONTINUATION, cflags, stream_id, p + off, take, timeout_ms)' <<<"$http2_send_headers_impl" ||
  ! grep -Fq '"max_header_frame_size": 1' tests/native/test_http2_headers_loopback.oren ||
  ! grep -Fq 'if hb0["continuations"] < 2' tests/native/test_http2_headers_loopback.oren ||
  grep -Fq 'fn _write_all_bytes(conn, b, timeout_ms)' lib/std/net/http2_client.oren ||
  grep -Fq 'oren_u8_buf_new_uninit(split_at)' <<<"$http2_send_headers_impl" ||
  grep -Fq 'oren_memcpy(p0, p, split_at)' <<<"$http2_send_headers_impl"; then
  echo "ERROR: HTTP/2 fragmented HEADERS must write raw header-block spans across all CONTINUATION frames instead of copied split buffers" >&2
  exit 1
fi

strict_b64_impl="$(sed -n '/fn _decode_bytes_strict_range_impl/,/fn decode_strict/p' lib/std/encoding/base64.oren)"
if ! grep -Fq 'var out = oren_u8_buf_new_uninit(out_len)' <<<"$strict_b64_impl" ||
  ! grep -Fq 'v0 = _b64_val(_str_byte(s, start + si))' <<<"$strict_b64_impl" ||
  ! grep -Fq 'fn decode_bytes_strict_range(s, start, count)' <<<"$strict_b64_impl" ||
  ! grep -Fq 'fn decode_bytes_strict_lines_range(s, start, count)' <<<"$strict_b64_impl" ||
  ! grep -Fq 'if c0 == 10 || c0 == 13 { continue }' <<<"$strict_b64_impl" ||
  ! grep -Fq 'v0 = _b64_val(c0)' <<<"$strict_b64_impl" ||
  ! grep -Fq 'if v0 == -2 || v1 == -2 || v2 == -2 || v3 == -2' <<<"$strict_b64_impl" ||
  ! grep -Fq 'var rc = _store_decoded_triple(out, outi, out_len, triple, count)' <<<"$strict_b64_impl" ||
  grep -Fq 'return decode_bytes(s)' <<<"$strict_b64_impl" ||
  grep -Fq '_next_b64_line_strict_val' lib/std/encoding/base64.oren ||
  grep -Fq 'return {"pos": p, "val": _b64_val(c)}' lib/std/encoding/base64.oren ||
  grep -Fq 'while i < n' <<<"$strict_b64_impl" ||
  ! grep -Fq 'parse_bytes_strict padded groups' tests/modules/test_base64.oren ||
  ! grep -Fq 'parse_bytes_strict rejects nonzero one-byte padding bits' tests/modules/test_base64.oren; then
  echo "ERROR: strict Base64 decode must size exactly and validate/decode inline instead of pre-scanning then delegating to tolerant decode" >&2
  exit 1
fi

tolerant_b64_impl="$(sed -n '/fn _decode_bytes_range_impl/,/fn decode(s): bytes/p' lib/std/encoding/base64.oren)"
if ! grep -Fq 'fn _b64_clean_meta_range(s, start, end)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'fn decode_bytes_range(s, start, count)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var meta = _b64_clean_meta_range(s, start, end)' <<<"$tolerant_b64_impl" ||
  ! grep -Fq 'return clean * 4 + trailing_pad' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var clean = meta / 4' <<<"$tolerant_b64_impl" ||
  ! grep -Fq 'var pad = meta % 4' <<<"$tolerant_b64_impl" ||
  grep -Fq 'var meta = list.int_new(0)' lib/std/encoding/base64.oren ||
  grep -Fq 'fn _b64_count_clean_chars' lib/std/encoding/base64.oren ||
  grep -Fq 'while i >= 0 && seen < 2' <<<"$tolerant_b64_impl" ||
  ! grep -Fq 'parse_bytes whitespace metadata padded' tests/modules/test_base64.oren; then
  echo "ERROR: tolerant Base64 decode must derive clean length and padding from one metadata pass, not a clean-count pass plus backward padding scan" >&2
  exit 1
fi

pem_impl="$(sed -n '/fn decode_blocks(pem_text)/,/^}/p' lib/std/crypto/pem.oren)"
pem_strict_impl="$(sed -n '/fn decode_blocks_strict(pem_text)/,/^}/p' lib/std/crypto/pem.oren)"
if ! grep -Fq 'base64.decode_bytes_range(pem_text, body_start, body_end - body_start)' <<<"$pem_impl" ||
  ! grep -Fq 'base64.decode_bytes_strict_lines_range(pem_text, body_start, body_end - body_start)' <<<"$pem_strict_impl" ||
  ! grep -Fq 'headers are not supported in v0' <<<"$pem_strict_impl" ||
  grep -Fq 'var b64_str = oren_string_slice(pem_text, body_start, body_end)' lib/std/crypto/pem.oren ||
  grep -Fq 'fn _strict_body_string' lib/std/crypto/pem.oren ||
  grep -Fq 'fn _validate_strict_body_lines' lib/std/crypto/pem.oren ||
  grep -Fq 'ptr_set_byte(iadd(outp, oi)' lib/std/crypto/pem.oren ||
  ! grep -Fq 'parse_bytes_strict_lines_range newline span' tests/modules/test_base64.oren ||
  ! grep -Fq 'var wrapped = "prefix' tests/native/test_pem_decode_smoke.oren ||
  ! grep -Fq 'Proc-Type: 4,ENCRYPTED' tests/native/test_pem_decode_smoke.oren; then
  echo "ERROR: PEM body decode must use Base64 range decoders directly, not slice or compact body text into temporary strings" >&2
  exit 1
fi

openssl_alpn_client_impl="$(sed -n '/fn _openssl_set_alpn_if_requested/,/fn __oren_tls_openssl_alpn_select_cb/p' lib/std/net/tls_linux_openssl.oren)"
openssl_alpn_server_impl="$(sed -n '/fn _openssl_set_server_alpn_select_if_requested/,/fn _openssl_ctx_new/p' lib/std/net/tls_linux_openssl.oren)"
schannel_alpn_impl="$(sed -n '/fn _win_build_alpn_secbuffer_if_requested/,/fn wrap_client/p' lib/std/net/tls_windows_schannel.oren)"
tls_alpn_impl="$openssl_alpn_client_impl
$openssl_alpn_server_impl
$schannel_alpn_impl"
if ! grep -Fq 'oren_memcpy(buf + off, p2, l2)' <<<"$openssl_alpn_client_impl" ||
  ! grep -Fq 'oren_memcpy(arg + 4 + off, s, l2)' <<<"$openssl_alpn_server_impl" ||
  ! grep -Fq 'oren_memcpy(buf + off, s, l2)' <<<"$schannel_alpn_impl" ||
  grep -Fq 'ptr_set_byte(buf + off + j, oren_string_byte_at_unchecked' <<<"$tls_alpn_impl" ||
  grep -Fq 'ptr_set_byte(arg + 4 + off + j, oren_string_byte_at_unchecked' <<<"$tls_alpn_impl"; then
  echo "ERROR: TLS ALPN protocol-list encoders must bulk-copy contiguous string protocol IDs, not loop per byte" >&2
  exit 1
fi

vfs_read_bytes_impl="$(sed -n '/static AvmValue avm_vfs_read_bytes_list_value/,/^}/p' lib/avm/avm_native_fs_universe_helpers.inc)"
if ! grep -Fq 'AvmValue res = avm_list_int_new((int)len)' <<<"$vfs_read_bytes_impl" ||
  ! grep -Fq 'list->items[i] = (int64_t)(unsigned char)(data ? data[i] : 0)' <<<"$vfs_read_bytes_impl" ||
  grep -Fq 'AvmList* list = (AvmList*)avm_heap_malloc_k(sizeof(AvmList)' <<<"$vfs_read_bytes_impl" ||
  grep -Fq 'list->items[i].type = AVM_VAL_INT' <<<"$vfs_read_bytes_impl"; then
  echo "ERROR: legacy AVM VFS read_bytes must return a directly filled LIST_INT, not boxed AvmValue list entries" >&2
  exit 1
fi

vfs_write_list_impl="$(sed -n '/static int avm_vfs_put_list/,/^}/p' lib/avm/avm_native_fs_universe_helpers.inc)"
if ! grep -Fq 'new_data = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_VFS)' <<<"$vfs_write_list_impl" ||
  ! grep -Fq 'new_data[i] = (uint8_t)(v & 0xFF)' <<<"$vfs_write_list_impl" ||
  grep -Fq 'AVM_ALLOC_KIND_BYTES' <<<"$vfs_write_list_impl" ||
  grep -Fq 'avm_vfs_put(vm, path, buf, len)' <<<"$vfs_write_list_impl"; then
  echo "ERROR: legacy AVM VFS write_bytes list path must fill final VFS storage directly, not build a full-size temp bytes mirror" >&2
  exit 1
fi

vfs_write_list_int_impl="$(sed -n '/static int avm_vfs_put_list_int/,/^}/p' lib/avm/avm_native_fs_universe_helpers.inc)"
if ! grep -Fq 'new_data = (uint8_t*)avm_heap_malloc_k((size_t)len, AVM_ALLOC_KIND_VFS)' <<<"$vfs_write_list_int_impl" ||
  ! grep -Fq 'new_data[i] = (uint8_t)(v & 0xFF)' <<<"$vfs_write_list_int_impl" ||
  grep -Fq 'AVM_ALLOC_KIND_BYTES' <<<"$vfs_write_list_int_impl" ||
  grep -Fq 'avm_vfs_put(vm, path, buf, len)' <<<"$vfs_write_list_int_impl"; then
  echo "ERROR: legacy AVM VFS write_bytes LIST_INT path must fill final VFS storage directly, not build a full-size temp bytes mirror" >&2
  exit 1
fi

vfs_write_bytes_domain_impl="$(sed -n '/case 2: { \/\/ write_bytes -> NIL/,/case 7:/p' lib/avm/avm_native_capability_domain_fs.inc)"
if ! grep -Fq 'args[1].type == AVM_VAL_LIST_INT' <<<"$vfs_write_bytes_domain_impl" ||
  ! grep -Fq 'ok = avm_vfs_put_list_int(vm, path ? path : "", args[1].as.li)' <<<"$vfs_write_bytes_domain_impl" ||
  ! grep -Fq 'vfs: write_bytes expected list<int 0..255>' <<<"$vfs_write_bytes_domain_impl" ||
  ! grep -Fq 'it.type != AVM_VAL_INT || it.as.i < 0 || it.as.i > 255' <<<"$vfs_write_bytes_domain_impl" ||
  ! grep -Fq 'b < 0 || b > 255' <<<"$vfs_write_bytes_domain_impl"; then
  echo "ERROR: AVM VFS write_bytes must validate list carriers before writing direct final VFS storage" >&2
  exit 1
fi

if ! grep -q 'fn read_u8_buf(path)' lib/std/fs.oren || ! grep -q 'var rb = fs.read_u8_buf' \
  tests/modules/test_fs_std.oren || ! grep -q 'var rb = fs.read_u8_buf' \
  tests/avm/test_std_fs_vfs.oren; then
  echo "ERROR: std:fs byte-buffer fixtures must keep explicit read_u8_buf facade coverage" >&2
  exit 1
fi

std_fs_read_bytes_impl="$(sed -n '/fn read_bytes(path)/,/fn read_bytes_under/p' lib/std/fs.oren)"
std_fs_read_bytes_under_impl="$(sed -n '/fn read_bytes_under(root, parts)/,/fn read_byte_list(path)/p' lib/std/fs.oren)"
if ! grep -Fq 'return read_u8_buf(path)' <<<"$std_fs_read_bytes_impl" ||
  grep -Fq 'return read_byte_list(path)' <<<"$std_fs_read_bytes_impl" ||
  grep -Fq 'return oren_read_bytes(path)' <<<"$std_fs_read_bytes_impl" ||
  ! grep -Fq 'return read_bytes(p)' <<<"$std_fs_read_bytes_under_impl" ||
  grep -Fq 'return read_byte_list(p)' <<<"$std_fs_read_bytes_under_impl" ||
  ! grep -Fq 'var rb_alias = fs.read_bytes(bytes_path)' tests/modules/test_fs_std.oren ||
  ! grep -Fq 'var rb2_alias = fs.read_bytes_under(root, ["std_fs_under.bin"])' tests/modules/test_fs_std.oren ||
  ! grep -Fq 'var rb_alias = fs.read_bytes("v/dir/data.bin")' tests/avm/test_std_fs_vfs.oren ||
  ! grep -Fq 'var rb2_alias = fs.read_bytes_under("v/dir", ["under.bin"])' tests/avm/test_std_fs_vfs.oren; then
  echo "ERROR: std:fs read_bytes aliases must stay byte-native u8_buf wrappers with native and AVM carrier coverage" >&2
  exit 1
fi

if grep -q 'fn _rtobj_u8_at\|fn _rtobj_read_u32_le\|fn _rtobj_read_u64_le' lib/compiler/native_runtime_obj_cache.oren; then
  echo "ERROR: runtime-object metadata hot path must use shared compiler byte_view readers" >&2
  exit 1
fi

rtobj_sidecar_align_impl="$(sed -n '/fn _rtobj_align_bytes_8/,/fn _rtobj_normalize_debug_funcs_enc/p' lib/compiler/native_runtime_obj_cache_sidecars.oren)"
if ! grep -Fq 'if rem != 0 { bytes.bytes_extend_zeros(b, 8 - rem) }' <<<"$rtobj_sidecar_align_impl" ||
  grep -Fq 'bytes.bytes_push(b, 0)' <<<"$rtobj_sidecar_align_impl"; then
  echo "ERROR: runtime-object debug sidecar alignment must use byte-builder zero extension, not a per-byte zero loop" >&2
  exit 1
fi

x64_pe_sections_impl="$(sed -n '/Section headers/,/Pad headers to SizeOfHeaders/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'fn push_pe_section_name(b, b0, b1, b2, b3, b4, b5, b6, b7)' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'push_pe_section_name(out, 46, 116, 101, 120, 116, 0, 0, 0)' <<<"$x64_pe_sections_impl" ||
  ! grep -Fq 'push_pe_section_name(out, 46, 114, 100, 97, 116, 97, 0, 0)' <<<"$x64_pe_sections_impl" ||
  ! grep -Fq 'push_pe_section_name(out, 46, 100, 97, 116, 97, 0, 0, 0)' <<<"$x64_pe_sections_impl" ||
  grep -Fq 'while j < 8' <<<"$x64_pe_sections_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(name_' <<<"$x64_pe_sections_impl"; then
  echo "ERROR: x64 PE section names must be emitted as straight-line bytes, not fixed string-byte loops" >&2
  exit 1
fi

x64_pe_data_dirs_impl="$(sed -n '/DataDirectory\[16\]/,/Pad optional header to 240 bytes/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return codegen.bytes_extend_zeros(b, n) }' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'fn bytes_extend_zeros(b, n) { return core.bytes_extend_zeros(b, n) }' lib/compiler/codegen_x64.oren ||
  ! grep -Fq 'bytes_extend_zeros(out, 14 * 8)' <<<"$x64_pe_data_dirs_impl" ||
  grep -Fq 'while ddi < 14' <<<"$x64_pe_data_dirs_impl"; then
  echo "ERROR: x64 PE zero data directories must use byte-builder zero extension, not a fixed u32 loop" >&2
  exit 1
fi

x64_pe_import_thunks_impl="$(sed -n '/Align to 8 for thunk arrays/,/Hint.Name entries/p' lib/compiler/x64_pe.oren)"
x64_pe_import_names_impl="$(sed -n '/Hint.Name entries/,/var off_dll_k32/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'fn _pe_align(buf, align)' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'fn _pe_reserve_u64_zeros(buf, count)' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'bytes_extend_zeros(buf, count * 8)' lib/compiler/x64_pe.oren ||
  test "$(grep -Fc '_pe_reserve_u64_zeros(rdata,' <<<"$x64_pe_import_thunks_impl")" != "8" ||
  test "$(grep -Fc '_pe_align(rdata, 2)' <<<"$x64_pe_import_names_impl")" != "4" ||
  grep -Fq 'push_u64_le(rdata, 0)' <<<"$x64_pe_import_thunks_impl" ||
  grep -Fq 'while int_mod(bytes_len(rdata), 8) != 0' <<<"$x64_pe_import_thunks_impl" ||
  grep -Fq 'if int_mod(bytes_len(rdata), 2) != 0 { bytes_push(rdata, 0) }' <<<"$x64_pe_import_names_impl"; then
  echo "ERROR: x64 PE import thunk reservations must use byte-builder zero-extension, not fixed u64/alignment loops" >&2
  exit 1
fi

x64_pe_exports_impl="$(sed -n '/Optional PE export table/,/Patch IMAGE_EXPORT_DIRECTORY fields/p' lib/compiler/x64_pe.oren)"
x64_pe_emit_tail_impl="$(sed -n '/DOS header/,/var w = oren_write_bytes/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'bytes_extend_zeros(rdata, n_exp * 4)' <<<"$x64_pe_exports_impl" ||
  test "$(grep -Fc '_pe_align(rdata, 4)' <<<"$x64_pe_exports_impl")" != "3" ||
  ! grep -Fq 'fn _pe_pad_to_len(buf, target_len)' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'if target_len > used { bytes_extend_zeros(buf, target_len - used) }' lib/compiler/x64_pe.oren ||
  ! grep -Fq '_pe_pad_to_len(out, pe_off)' <<<"$x64_pe_emit_tail_impl" ||
  ! grep -Fq 'bytes_push(out, 80); bytes_push(out, 69); bytes_extend_zeros(out, 2) // "PE\0\0"' <<<"$x64_pe_emit_tail_impl" ||
  ! grep -Fq 'bytes_extend_zeros(out, 2) // MajorLinkerVersion, MinorLinkerVersion' <<<"$x64_pe_emit_tail_impl" ||
  ! grep -Fq '_pe_pad_to_len(out, opt_start + 240)' <<<"$x64_pe_emit_tail_impl" ||
  ! grep -Fq '_pe_pad_to_len(out, size_of_headers)' <<<"$x64_pe_emit_tail_impl" ||
  test "$(grep -Fc '_pe_align(out, file_align)' <<<"$x64_pe_emit_tail_impl")" != "3" ||
  grep -Fq 'while ei < n_exp { push_u32_le(rdata, 0); ei = ei + 1 }' <<<"$x64_pe_exports_impl" ||
  grep -Fq 'while int_mod(bytes_len(rdata), 4) != 0' <<<"$x64_pe_exports_impl" ||
  grep -Fq 'while bytes_len(out) < pe_off' <<<"$x64_pe_emit_tail_impl" ||
  grep -Fq 'bytes_push(out, 80); bytes_push(out, 69); bytes_push(out, 0); bytes_push(out, 0)' <<<"$x64_pe_emit_tail_impl" ||
  grep -Fq 'bytes_push(out, 0) // MajorLinkerVersion' <<<"$x64_pe_emit_tail_impl" ||
  grep -Fq 'while bytes_len(out) - opt_start < 240' <<<"$x64_pe_emit_tail_impl" ||
  grep -Fq 'while bytes_len(out) < size_of_headers' <<<"$x64_pe_emit_tail_impl" ||
  grep -Fq 'while int_mod(bytes_len(out), file_align) != 0' <<<"$x64_pe_emit_tail_impl"; then
  echo "ERROR: x64 PE export/header/raw-section padding must use byte-builder zero extension helpers" >&2
  exit 1
fi

arm64_elf_align_impl="$(sed -n '/fn _bytes_align/,/^}/p' lib/compiler/arm64_elf.oren)"
x64_elf_align_impl="$(sed -n '/fn _bytes_align/,/^}/p' lib/compiler/x64_elf.oren)"
arm64_elf_layout_impl="$(sed -n '/Append debug info (Linux ELF)/,/Patch debug static addr constant/p' lib/compiler/arm64_elf.oren)"
x64_elf_page_layout_impl="$(sed -n '/Ensure the data segment begins on a page boundary/,/If `--link` is used/p' lib/compiler/x64_elf.oren)"
x64_elf_build_shstr_impl="$(sed -n '/Build shstrtab/,/Align and append shstrtab/p' lib/compiler/x64_elf.oren)"
x64_elf_shstr_layout_impl="$(sed -n '/Align and append shstrtab/,/Build section header table/p' lib/compiler/x64_elf.oren)"
arm64_elf_dynsym_impl="$(sed -n '/Build dynsym (DT_SYMTAB)/,/Build .rela.dyn/p' lib/compiler/arm64_elf.oren)"
x64_elf_dynsym_impl="$(sed -n '/Build dynsym (DT_SYMTAB)/,/Build .rela.dyn/p' lib/compiler/x64_elf.oren)"
arm64_elf_header_impl="$(sed -n '/ELF Header (64 bytes)/,/Machine: AArch64/p' lib/compiler/arm64_elf.oren)"
x64_elf_header_impl="$(sed -n '/ELF Header (64 bytes)/,/Machine: x86-64/p' lib/compiler/x64_elf.oren)"
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return codegen.bytes_extend_zeros(b, n) }' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_zeros(b, n) { return codegen.bytes_extend_zeros(b, n) }' lib/compiler/x64_elf.oren ||
  test "$(grep -Fc 'bytes_extend_zeros(dynsym, 1) // st_other' <<<"$arm64_elf_dynsym_impl")" != "2" ||
  test "$(grep -Fc 'bytes_extend_zeros(dynsym, 1) // st_other' <<<"$x64_elf_dynsym_impl")" != "2" ||
  ! grep -Fq 'bytes_extend_zeros(p, 1); // OS ABI: System V' <<<"$arm64_elf_header_impl" ||
  ! grep -Fq 'bytes_extend_zeros(p, 1) // System V' <<<"$x64_elf_header_impl" ||
  ! grep -Fq 'var rem = int_mod(bytes_len(buf), align)' <<<"$arm64_elf_align_impl" ||
  ! grep -Fq 'if rem != 0 { bytes_extend_zeros(buf, align - rem) }' <<<"$arm64_elf_align_impl" ||
  ! grep -Fq 'var rem = int_mod(bytes_len(buf), align)' <<<"$x64_elf_align_impl" ||
  ! grep -Fq 'if rem != 0 { bytes_extend_zeros(buf, align - rem) }' <<<"$x64_elf_align_impl" ||
  ! grep -Fq '_bytes_align(data, 8)' <<<"$arm64_elf_layout_impl" ||
  ! grep -Fq 'bytes_extend_zeros(prefix, pad_len)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'bytes_extend_zeros(prefix, pad_len)' lib/compiler/x64_elf.oren ||
  grep -Fq 'var code_pad = bytes_new()' lib/compiler/arm64_elf.oren ||
  grep -Fq 'var code_pad = bytes_new()' lib/compiler/x64_elf.oren ||
  grep -Fq 'bytes_push(dynsym, 0)  // st_other' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'bytes_push(p, 0); // OS ABI: System V' <<<"$arm64_elf_header_impl" ||
  grep -Fq 'bytes_push(p, 0) // System V' <<<"$x64_elf_header_impl" ||
  test "$(grep -Fc '_bytes_align(prefix, 16)' <<<"$x64_elf_shstr_layout_impl")" != "2" ||
  grep -Fq 'while int_mod(bytes_len(buf), align) != 0' <<<"$arm64_elf_align_impl" ||
  grep -Fq 'while int_mod(bytes_len(buf), align) != 0' <<<"$x64_elf_align_impl" ||
  grep -Fq 'while int_mod(bytes_len(data), 8) != 0' <<<"$arm64_elf_layout_impl" ||
  grep -Fq 'while pi < pad_len' <<<"$arm64_elf_layout_impl" ||
  grep -Fq 'while pi < pad_len' <<<"$x64_elf_page_layout_impl" ||
  grep -Fq 'while int_mod(bytes_len(prefix), 16) != 0' <<<"$x64_elf_shstr_layout_impl"; then
  echo "ERROR: ELF alignment padding must use byte-builder zero extension, not per-byte loops" >&2
  exit 1
fi

arm64_elf_string_impl="$(sed -n '/fn _elf_push_utf8_aligned/,/fn _elf_push_phdr/p; /fn _elf_push_string_bytes/,/fn _bytes_add_str0/p' lib/compiler/arm64_elf.oren)"
arm64_elf_cstr_impl="$(sed -n '/fn _bytes_add_str0/,/fn _elf_push_unique/p' lib/compiler/arm64_elf.oren)"
x64_elf_string_impl="$(sed -n '/fn _elf_push_string_bytes/,/fn _bytes_add_str0/p' lib/compiler/x64_elf.oren)"
x64_elf_cstr_impl="$(sed -n '/fn _bytes_add_str0/,/fn _elf_push_unique/p' lib/compiler/x64_elf.oren)"
arm64_elf_dynamic_impl="$(sed -n '/PT_INTERP payload/,/var needed =/p' lib/compiler/arm64_elf.oren)"
x64_elf_dynamic_impl="$(sed -n '/PT_INTERP payload/,/var needed =/p' lib/compiler/x64_elf.oren)"
arm64_elf_data_cstr_impl="$(sed -n '/fn _data_add_cstr0/,/^}/p' lib/compiler/arm64_elf.oren)"
arm64_macho_bind_impl="$(sed -n '/fn macho_build_bind_opcodes/,/fn macho_build_prefix_arm64/p' lib/compiler/arm64_macho.oren)"
arm64_macho_string_impl="$(sed -n '/fn _macho_push_string_bytes/,/fn push_uleb128/p; /fn _macho_push_utf8_aligned/,/fn emit_debug_info/p' lib/compiler/arm64_macho.oren)"
arm64_macho_file_impl="$(cat lib/compiler/arm64_macho.oren)"
x64_pe_ascii_impl="$(sed -n '/fn push_ascii_z/,/fn _pe_path_basename/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'fn bytes_extend_string_z(b, s) { return codegen.bytes_extend_string_z(b, s) }' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return codegen.bytes_extend_string_z(b, s) }' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_string(b, s) { return codegen.bytes_extend_string(b, s) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return codegen.bytes_extend_string_z(b, s) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return codegen.bytes_extend_string_z(b, s) }' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'bytes_extend_string(p, s)' <<<"$arm64_elf_string_impl" ||
  ! grep -Fq 'bytes_extend_string(buf, s)' <<<"$arm64_elf_string_impl" ||
  ! grep -Fq 'bytes_extend_string_z(buf, s)' <<<"$arm64_elf_cstr_impl" ||
  ! grep -Fq 'bytes_extend_string(buf, s)' <<<"$x64_elf_string_impl" ||
  ! grep -Fq 'bytes_extend_string_z(buf, s)' <<<"$x64_elf_cstr_impl" ||
  ! grep -Fq 'bytes_extend_string_z(data, interp)' <<<"$arm64_elf_dynamic_impl" ||
  ! grep -Fq 'bytes_extend_string_z(data, interp)' <<<"$x64_elf_dynamic_impl" ||
  ! grep -Fq 'bytes_extend_zeros(dynstr, 1)' <<<"$arm64_elf_dynamic_impl" ||
  ! grep -Fq 'bytes_extend_zeros(dynstr, 1)' <<<"$x64_elf_dynamic_impl" ||
  ! grep -Fq 'bytes_extend_string_z(data, s)' <<<"$arm64_elf_data_cstr_impl" ||
  ! grep -Fq 'bytes_extend_zeros(shstr, 1)' <<<"$x64_elf_build_shstr_impl" ||
  test "$(grep -Fc 'bytes_extend_string_z(shstr,' <<<"$x64_elf_build_shstr_impl")" != "3" ||
  ! grep -Fq 'bytes_extend_string(buf, s)' <<<"$arm64_macho_string_impl" ||
  ! grep -Fq 'bytes_extend_string_z(buf, s)' <<<"$arm64_macho_string_impl" ||
  ! grep -Fq 'bytes_extend_string(p, s)' <<<"$arm64_macho_string_impl" ||
  ! grep -Fq '_macho_align(p, 8)' <<<"$arm64_macho_string_impl" ||
  test "$(grep -Fc '_macho_push_string_z(strtab,' <<<"$arm64_macho_file_impl")" != "2" ||
  ! grep -Fq 'bytes_extend_zeros(strtab, 1)' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq 'bytes_extend_zeros(symtab, 1) // n_sect' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq '_macho_push_string_z(p, name)' <<<"$arm64_macho_bind_impl" ||
  ! grep -Fq '_macho_push_string_z(p, dyld_path)' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq '_macho_push_string_z(p, libsys_path)' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq '_macho_push_string_z(p, lib_path2)' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq '_macho_push_string_z(p, id_name)' <<<"$arm64_macho_file_impl" ||
  ! grep -Fq 'bytes_extend_string_z(buf, s)' <<<"$x64_pe_ascii_impl" ||
  grep -Fq 'bytes_push(buf, oren_string_byte_at_unchecked(s, i)' <<<"$arm64_elf_string_impl" ||
  grep -Fq 'bytes_push(buf, oren_string_byte_at_unchecked(s, i)' <<<"$x64_elf_string_impl" ||
  grep -Fq 'bytes_push(buf, oren_string_byte_at_unchecked(s, i)' <<<"$arm64_macho_string_impl" ||
  grep -Fq 'bytes_push(buf, oren_string_byte_at_unchecked(s, i)' <<<"$x64_pe_ascii_impl" ||
  grep -Fq 'bytes_push(p, oren_string_byte_at_unchecked(s, i)' <<<"$arm64_elf_string_impl" ||
  grep -Fq 'bytes_push(p, oren_string_byte_at_unchecked(s, i)' <<<"$arm64_macho_string_impl" ||
  grep -Fq '_macho_push_string_bytes(p, name)' <<<"$arm64_macho_bind_impl" ||
  grep -Fq '_macho_push_string_bytes(p, dyld_path)' <<<"$arm64_macho_file_impl" ||
  grep -Fq '_macho_push_string_bytes(p, libsys_path)' <<<"$arm64_macho_file_impl" ||
  grep -Fq '_macho_push_string_bytes(p, lib_path2)' <<<"$arm64_macho_file_impl" ||
  grep -Fq '_macho_push_string_bytes(p, id_name)' <<<"$arm64_macho_file_impl" ||
  grep -Fq '_macho_push_string_bytes(strtab,' <<<"$arm64_macho_file_impl" ||
  grep -Fq '_elf_push_string_bytes(data, interp)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'bytes_push(data, 0)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl$arm64_elf_data_cstr_impl" ||
  grep -Fq 'bytes_push(dynstr, 0) // leading NUL' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'bytes_push(shstr, 0)' <<<"$x64_elf_build_shstr_impl" ||
  grep -Fq 'bytes_push(strtab, 0)' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'bytes_push(symtab, 0) // n_sect' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(bind_name' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(f_name' <<<"$arm64_macho_file_impl"; then
  echo "ERROR: compiler artifact string append helpers must use byte-builder string extension, not per-byte string loops" >&2
  exit 1
fi

bytes_builder_string_impl="$(sed -n '/fn bytes_extend_string(b, s)/,/fn bytes_set_u8/p' lib/compiler/bytes_builder.oren)"
if ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(b["buf"], used, s, 0, n)' <<<"$bytes_builder_string_impl" ||
  ! grep -Fq 'fn bytes_extend_string_slice(b, s, off, n)' <<<"$bytes_builder_string_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(b["buf"], used, s, off, n)' <<<"$bytes_builder_string_impl" ||
  grep -Fq 'ptr_set_byte(iadd(dstp, used + i), oren_string_byte_at_unchecked(s, i) & 255)' <<<"$bytes_builder_string_impl"; then
  echo "ERROR: compiler byte-builder string extension must copy string spans and slices directly, not loop per byte" >&2
  exit 1
fi

arm64_elf_runtime_debug_impl="$(sed -n '/fn emit_debug_info/,/fn _elf_push_utf8_aligned/p' lib/compiler/arm64_elf.oren)"
arm64_elf_runtime_debug_zero4_calls="$(grep -Fc '_elf_push_u64_zero4(p)' <<<"$arm64_elf_runtime_debug_impl")"
if ! grep -Fq 'fn _elf_push_u64_zero4(p)' lib/compiler/arm64_elf.oren ||
  test "$arm64_elf_runtime_debug_zero4_calls" != "2" ||
  grep -Fq 'push_u64_le(p, 0)' <<<"$arm64_elf_runtime_debug_impl"; then
  echo "ERROR: ARM64 ELF runtime debug reserved u64 fields must use the shared zero-word helper" >&2
  exit 1
fi

arm64_macho_runtime_debug_impl="$(sed -n '/fn emit_debug_info/,/fn macho_inject_debug_info/p' lib/compiler/arm64_macho.oren)"
arm64_macho_runtime_debug_zero4_calls="$(grep -Fc '_macho_push_u64_zero4(p)' <<<"$arm64_macho_runtime_debug_impl")"
if ! grep -Fq 'fn _macho_push_u64_zero4(p)' lib/compiler/arm64_macho.oren ||
  test "$arm64_macho_runtime_debug_zero4_calls" != "2" ||
  grep -Fq 'push_u64_le(p, 0)' <<<"$arm64_macho_runtime_debug_impl"; then
  echo "ERROR: ARM64 Mach-O runtime debug reserved u64 fields must use the shared zero-word helper" >&2
  exit 1
fi

arm64_ctx_impl="$(sed -n '/Reserve a `.data` slot holding the cstr0-literal table offset/,/Bounded debug knob:/p' lib/compiler/arm64_native_program/010_ctx.oren)"
arm64_global_impl="$(sed -n '/fn _arm64_alloc_global_slot/,/return nm/p' lib/compiler/arm64_native_program/030_globals.oren)"
arm64_program_cstr_table_impl="$(sed -n '/arm64.codegen.cstr_table.start/,/Layout: \\[table_off\\]/p' lib/compiler/arm64_native_program/090_program.oren)"
arm64_stmt_binding_impl="$(sed -n '/var data_off = bytes_len(ctx\["data"\])/,/_arm64_emit_store_x0_to_global/p' lib/compiler/arm64_native_stmt_bindings.oren)"
arm64_stmt_function_impl="$(sed -n '/if expr\["type"\] == "Function"/,/var jump_skip_pos = bytes_len(ctx\["code"\])/p' lib/compiler/arm64_native_stmt_inner.oren)"
if ! grep -Fq 'fn _arm64_data_align8(ctx)' lib/compiler/arm64_native_program/010_ctx.oren ||
  ! grep -Fq 'fn bytes_extend_zeros(b, n) { return core.bytes_extend_zeros(b, n) }' lib/compiler/arm64_native_stmt.oren ||
  ! grep -Fq 'if rem != 0 { bytes_extend_zeros(ctx["data"], 8 - rem) }' lib/compiler/arm64_native_program/010_ctx.oren ||
  ! grep -Fq 'if code_rem != 0 { bytes_extend_zeros(ctx["code"], 4 - code_rem) }' <<<"$arm64_stmt_function_impl" ||
  ! grep -Fq 'bytes_extend_zeros(ctx["data"], 512)' <<<"$arm64_ctx_impl" ||
  ! grep -Fq 'bytes_extend_zeros(ctx["data"], 8)' <<<"$arm64_ctx_impl" ||
  ! grep -Fq '_arm64_data_align8(ctx)' <<<"$arm64_global_impl" ||
  ! grep -Fq '_arm64_data_align8(ctx)' <<<"$arm64_program_cstr_table_impl" ||
  ! grep -Fq 'bytes_extend_zeros(ctx["data"], 8)' <<<"$arm64_global_impl" ||
  ! grep -Fq 'bytes_extend_zeros(ctx["data"], 8)' <<<"$arm64_stmt_binding_impl" ||
  grep -Fq 'while int_mod(bytes_len(ctx["data"]), 8) != 0' lib/compiler/arm64_native_program/010_ctx.oren ||
  grep -Fq 'while int_mod(bytes_len(ctx["code"]), 4) != 0' <<<"$arm64_stmt_function_impl" ||
  grep -Fq 'while int_mod(bytes_len(ctx["data"]), 8) != 0' <<<"$arm64_global_impl" ||
  grep -Fq 'while int_mod(bytes_len(ctx["data"]), 8) != 0' <<<"$arm64_program_cstr_table_impl" ||
  grep -Fq 'while z < 8' <<<"$arm64_ctx_impl" ||
  grep -Fq 'while z < 512' <<<"$arm64_ctx_impl" ||
  grep -Fq 'while k < 8' <<<"$arm64_global_impl" ||
  grep -Fq 'while k < 8' <<<"$arm64_stmt_binding_impl"; then
  echo "ERROR: ARM64 compiler 8-byte zero slot reservations must use bytes_extend_zeros, not fixed byte-push loops" >&2
  exit 1
fi

arm64_native_expr_cstr_impl="$(sed -n '/fn native_data_add_cstr0(ctx, s)/,/^}/p' lib/compiler/arm64_native_expr/000_prelude.oren)"
arm64_native_expr_panic_impl="$(sed -n '/fn native_emit_panic(ctx, msg)/,/var data_off = bytes_len(ctx\["data"\])/p' lib/compiler/arm64_native_expr/000_prelude.oren)"
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return core.bytes_extend_zeros(b, n) }' lib/compiler/arm64_native_expr/000_prelude.oren ||
  ! grep -Fq 'fn _native_expr_data_align8(ctx)' lib/compiler/arm64_native_expr/000_prelude.oren ||
  ! grep -Fq 'if rem != 0 { bytes_extend_zeros(ctx["data"], 8 - rem) }' lib/compiler/arm64_native_expr/000_prelude.oren ||
  ! grep -Fq '_native_expr_data_align8(ctx)' <<<"$arm64_native_expr_panic_impl" ||
  ! grep -Fq 'var key_s = s' <<<"$arm64_native_expr_cstr_impl" ||
  ! grep -Fq 's = oren_string_slice(s, 0, 1048576)' <<<"$arm64_native_expr_cstr_impl" ||
  ! grep -Fq 'bytes_extend_string_z(ctx["data"], s)' <<<"$arm64_native_expr_cstr_impl" ||
  ! grep -Fq 'ctx["cstr0_offs"][key_s] = off + 1' <<<"$arm64_native_expr_cstr_impl" ||
  grep -Fq 'while int_mod(bytes_len(ctx["data"]), 8) != 0' <<<"$arm64_native_expr_cstr_impl" ||
  grep -Fq 'while int_mod(bytes_len(ctx["data"]), 8) != 0' <<<"$arm64_native_expr_panic_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(s, i)' <<<"$arm64_native_expr_cstr_impl"; then
  echo "ERROR: ARM64 native expr C-string literals must align and append through byte-builder span helpers" >&2
  exit 1
fi

x64_native_program_impl="$(cat lib/compiler/x64_native_program/*.oren lib/compiler/x64_native_program/090_program_entry/*.oren)"
x64_data_io_impl="$(cat lib/compiler/x64_native_program/010_data_io.oren)"
if ! grep -Fq 'fn _bytes_align8(buf)' <<<"$x64_data_io_impl" ||
  ! grep -Fq 'if rem != 0 { bytes_extend_zeros(buf, 8 - rem) }' <<<"$x64_data_io_impl" ||
  ! grep -Fq 'fn _data_align8(ctx)' <<<"$x64_data_io_impl" ||
  ! grep -Fq 'bytes_extend_zeros(ctx["data"], total)' <<<"$x64_data_io_impl" ||
  ! grep -Fq 'bytes_extend_string_z(ctx["data"], s)' <<<"$x64_data_io_impl" ||
  ! grep -Fq 'bytes_extend_string_z(batch_data_buf, s_b)' <<<"$x64_native_program_impl" ||
  ! grep -Fq '_bytes_align8(batch_data_buf)' <<<"$x64_native_program_impl" ||
  ! grep -Fq '_data_align8(ctx)' <<<"$x64_native_program_impl" ||
  grep -Fq 'while core.int_mod(bytes_len(ctx["data"]), 8) != 0' <<<"$x64_native_program_impl" ||
  grep -Fq 'while core.int_mod(bytes_len(batch_data_buf), 8) != 0' <<<"$x64_native_program_impl" ||
  grep -Fq 'while i < total { bytes_push(ctx["data"], 0)' <<<"$x64_native_program_impl"; then
  echo "ERROR: x64 native data-section alignment and table reservations must use byte-builder zero extension" >&2
  exit 1
fi

arm64_macho_uuid_impl="$(sed -n '/^[[:space:]]*\/\/ LC_UUID/,/^[[:space:]]*\/\/ 8\. LC_MAIN or LC_ID_DYLIB/p' lib/compiler/arm64_macho.oren)"
arm64_macho_uuid_zero_words="$(grep -Fc 'push_u32_le(p, 0)' <<<"$arm64_macho_uuid_impl")"
if ! grep -Fq 'push_u32_le(p, lc_uuid())' <<<"$arm64_macho_uuid_impl" ||
  ! grep -Fq 'push_u32_le(p, cmdsize_uuid())' <<<"$arm64_macho_uuid_impl" ||
  test "$arm64_macho_uuid_zero_words" != "4" ||
  grep -Fq 'while k_uuid < 4' <<<"$arm64_macho_uuid_impl"; then
  echo "ERROR: ARM64 Mach-O LC_UUID zero words must be emitted straight-line, not through a fixed loop" >&2
  exit 1
fi

arm64_macho_fixed16_impl="$(sed -n '/fn push_str_fixed16/,/fn _macho_push_string_bytes/p' lib/compiler/arm64_macho.oren)"
arm64_macho_pagezero_impl="$(sed -n '/LC_SEGMENT_64 (__PAGEZERO)/,/vmaddr/p' lib/compiler/arm64_macho.oren)"
arm64_macho_pad_helper_impl="$(sed -n '/fn _macho_pad_to_len/,/fn push_uleb128/p' lib/compiler/arm64_macho.oren)"
arm64_macho_dylib_id_impl="$(sed -n '/var id_start = bytes_len(p)/,/} else {/p' lib/compiler/arm64_macho.oren)"
arm64_macho_exit_impl="$(sed -n '/fn macho_emit_exit_arm64/,/^}/p' lib/compiler/arm64_macho.oren)"
arm64_macho_codegen_align_impl="$(sed -n '/macho.exports.done/,/if functions\["main"\] == nil/p; /Append debug info/,/var debug_off = bytes_len(data)/p' lib/compiler/arm64_macho.oren)"
arm64_macho_got_impl="$(sed -n '/Append GOT placeholder to Data/,/macho arm64: GOT placeholder done/p' lib/compiler/arm64_macho.oren)"
arm64_macho_load_commands_impl="$(sed -n '/LC_LOAD_DYLINKER/,/LC_BUILD_VERSION/p' lib/compiler/arm64_macho.oren)"
arm64_macho_prefix_impl="$(sed -n '/Pad strtab to 16 bytes/,/LinkEdit content/p' lib/compiler/arm64_macho.oren)"
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return codegen.bytes_extend_zeros(b, n) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'fn bytes_extend_string_slice(b, s, off, n) { return codegen.bytes_extend_string_slice(b, s, off, n) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'if n > 16 { n = 16 }' <<<"$arm64_macho_fixed16_impl" ||
  ! grep -Fq 'bytes_extend_string_slice(buf, s, 0, n)' <<<"$arm64_macho_fixed16_impl" ||
  ! grep -Fq 'if n < 16 { bytes_extend_zeros(buf, 16 - n) }' <<<"$arm64_macho_fixed16_impl" ||
  grep -Fq 'bytes_push(buf, oren_string_byte_at_unchecked(s, i)' <<<"$arm64_macho_fixed16_impl" ||
  grep -Fq 'while i < 16' <<<"$arm64_macho_fixed16_impl" ||
  ! grep -Fq 'bytes_extend_zeros(p, 16)' <<<"$arm64_macho_pagezero_impl" ||
  ! grep -Fq 'fn _macho_pad_to_len(buf, target_len)' <<<"$arm64_macho_pad_helper_impl" ||
  ! grep -Fq 'if target_len > used { bytes_extend_zeros(buf, target_len - used) }' <<<"$arm64_macho_pad_helper_impl" ||
  ! grep -Fq '_macho_pad_to_len(p, id_start + id_size)' <<<"$arm64_macho_dylib_id_impl" ||
  ! grep -Fq '_macho_pad_to_len(prefix, text_size)' <<<"$arm64_macho_exit_impl" ||
  ! grep -Fq '_macho_pad_to_len(p, cmd_start + dyld_cmdsize)' <<<"$arm64_macho_load_commands_impl" ||
  ! grep -Fq '_macho_pad_to_len(p, cmd_start_lib + libsys_cmdsize)' <<<"$arm64_macho_load_commands_impl" ||
  ! grep -Fq '_macho_pad_to_len(p, cmd_start_lib2 + lib_cmdsize2)' <<<"$arm64_macho_load_commands_impl" ||
  ! grep -Fq '_macho_pad_to_len(p, header_size)' lib/compiler/arm64_macho.oren ||
  ! grep -Fq '_macho_align(strtab, 16)' <<<"$arm64_macho_prefix_impl" ||
  ! grep -Fq '_macho_pad_to_len(prefix, text_size)' <<<"$arm64_macho_prefix_impl" ||
  ! grep -Fq '_macho_pad_to_len(prefix, text_size + data_size)' <<<"$arm64_macho_prefix_impl" ||
  ! grep -Fq '_macho_align(code, 4)' <<<"$arm64_macho_codegen_align_impl" ||
  ! grep -Fq '_macho_align(data, 8)' <<<"$arm64_macho_codegen_align_impl" ||
  ! grep -Fq '_macho_align(data, 8)' <<<"$arm64_macho_got_impl" ||
  ! grep -Fq 'codegen.bytes_extend_zeros(data, oren_list_len(imports) * 8)' <<<"$arm64_macho_got_impl" ||
  grep -Fq 'while i < 16 { bytes_push(p, 0); i = i + 1 }' <<<"$arm64_macho_pagezero_impl" ||
  grep -Fq 'while bytes_len(p) < id_start + id_size' <<<"$arm64_macho_dylib_id_impl" ||
  grep -Fq 'while bytes_len(prefix) < text_size' <<<"$arm64_macho_exit_impl" ||
  grep -Fq 'while bytes_len(p) < cmd_start' <<<"$arm64_macho_load_commands_impl" ||
  grep -Fq 'while bytes_len(p) < header_size' <<<"$arm64_macho_load_commands_impl" ||
  grep -Fq 'while int_mod(bytes_len(strtab), 16) != 0' <<<"$arm64_macho_prefix_impl" ||
  grep -Fq 'while bytes_len(prefix) < text_size' <<<"$arm64_macho_prefix_impl" ||
  grep -Fq 'while int_mod(bytes_len(code), 4) != 0' <<<"$arm64_macho_codegen_align_impl" ||
  grep -Fq 'while int_mod(bytes_len(data), 8) != 0' <<<"$arm64_macho_codegen_align_impl" ||
  grep -Fq 'while int_mod(bytes_len(data), 8) != 0' <<<"$arm64_macho_got_impl"; then
  echo "ERROR: ARM64 Mach-O fixed/header/debug padding must use byte-builder zero-extension helpers" >&2
  exit 1
fi

if grep -q 'fn _byte_view\|fn _read_u32_le\|fn _read_i32_le' lib/std/ui/commands.oren; then
    echo "ERROR: std:ui/commands validation must use shared std:bytes views directly" >&2
    exit 1
fi
ui_commands_impl="$(sed -n '/fn validate(cmds, w, h, opts)/,/^}/p' lib/std/ui/commands.oren)"
if ! grep -Fq 'var rects_data = bytes.view_bytes(rects_view)' <<<"$ui_commands_impl" ||
  ! grep -Fq 'var rects_ptr = bytes.view_ptr(rects_view)' <<<"$ui_commands_impl" ||
  ! grep -Fq 'var bsx = bytes.view_get_u32_le_from(rects_data, rects_ptr, roff)' <<<"$ui_commands_impl" ||
  ! grep -Fq 'var m3ix = bytes.view_get_i32_le_from(m3iverts_data, m3iverts_ptr, m3ivoff)' <<<"$ui_commands_impl" ||
  grep -Fq 'bytes.view_get_u32_le_unchecked(' <<<"$ui_commands_impl" ||
  grep -Fq 'bytes.view_get_i32_le_unchecked(' <<<"$ui_commands_impl"; then
    echo "ERROR: std:ui/commands validation must hoist byte-view backing storage for fixed-width payload reads" >&2
    exit 1
fi

if grep -q 'fn _read_byte\|fn _read_u32_le\|fn _read_i32_le' lib/std/ui/raster.oren; then
    echo "ERROR: std:ui/raster hot loops must use shared std:bytes view readers directly" >&2
  exit 1
fi
raster_impl="$(cat lib/std/ui/raster.oren)"
if ! grep -Fq 'var tris_data = bytes.view_bytes(trisp)' <<<"$raster_impl" ||
  ! grep -Fq 'var data_ptr = bytes.view_ptr(datap)' <<<"$raster_impl" ||
  ! grep -Fq 'var rects_ptr = bytes.view_ptr(rectsp)' <<<"$raster_impl" ||
  ! grep -Fq 'var tx1 = bytes.view_get_i32_le_from(tris_data, tris_ptr, off)' <<<"$raster_impl" ||
  ! grep -Fq 'var px = bytes.view_get_u32_le_from(positions_data, positions_ptr, poff)' <<<"$raster_impl" ||
  ! grep -Fq 'var br = bytes.view_get_u8_from(bdata_data, bdata_ptr, bsi)' <<<"$raster_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(' <<<"$raster_impl" ||
  grep -Fq 'bytes.view_get_u32_le_unchecked(' <<<"$raster_impl" ||
  grep -Fq 'bytes.view_get_i32_le_unchecked(' <<<"$raster_impl"; then
    echo "ERROR: std:ui/raster must hoist byte-view backing storage for hot fixed-width and pixel reads" >&2
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

cbor_u64_push_impl="$(sed -n '/fn _push_u64be/,/fn _emit_uint/p' lib/std/cbor.oren)"
if ! grep -Fq '_push_u8(out, (n >> 56) & 255)' <<<"$cbor_u64_push_impl" ||
  ! grep -Fq '_push_u8(out, n & 255)' <<<"$cbor_u64_push_impl" ||
  grep -Fq 'while i >= 0' <<<"$cbor_u64_push_impl" ||
  ! grep -Fq 'assert_bytes_eq(big_uint, [27, 0, 0, 0, 1, 0, 0, 0, 0], "encode uint64 big endian")' tests/modules/test_cbor_sequence.oren ||
  ! grep -Fq 'assert_bytes_eq(big_neg, [59, 0, 0, 0, 1, 0, 0, 0, 0], "encode neg uint64 big endian")' tests/modules/test_cbor_sequence.oren; then
  echo "ERROR: std:cbor 64-bit integer encode must use straight-line big-endian byte emission with focused coverage" >&2
  exit 1
fi

cbor_byte_encode_impl="$(sed -n '/if _streq(t, "bytes") {/,/if _streq(t, "string") {/p' lib/std/cbor.oren)"
if ! grep -Fq 'var input_ptr = bytem.view_ptr(bv)' <<<"$cbor_byte_encode_impl" ||
  ! grep -Fq '_push_u8(out, bytem.view_get_u8_from(input_data, input_ptr, bi) & 255)' <<<"$cbor_byte_encode_impl" ||
  grep -Fq 'bytem.view_get_u8_unchecked(bv, bi)' <<<"$cbor_byte_encode_impl"; then
  echo "ERROR: std:cbor byte-string encode must hoist shared byte-view inputs before byte emission" >&2
  exit 1
fi

cbor_byte_decode_impl="$(sed -n '/if major == 2 {/,/if major == 3 {/p' lib/std/cbor.oren)"
if ! grep -Fq 'var out = oren_u8_buf_from_bytes_slice(input_data, pos, arg)' <<<"$cbor_byte_decode_impl" ||
  ! grep -Fq 'return _ok(cbytes(out), pos + arg)' <<<"$cbor_byte_decode_impl" ||
  grep -Fq 'list.push' <<<"$cbor_byte_decode_impl" ||
  grep -Fq 'var out = []' <<<"$cbor_byte_decode_impl" ||
  ! grep -Fq 'assert(oren_is_u8_buf(v["bs"]) == true, "decode bytes u8 carrier")' tests/modules/test_cbor_sequence.oren; then
  echo "ERROR: std:cbor byte-string decode must keep exact u8_buf slices and fixture carrier coverage, not rebuild byte lists" >&2
  exit 1
fi
cbor_decode_impl="$(sed -n '/fn _read_uint_arg/,/fn _decode_err/p' lib/std/cbor.oren)"
if ! grep -Fq 'var input_ptr = bytem.view_ptr(bv)' lib/std/cbor.oren ||
  ! grep -Fq 'bytem.view_get_u16_be_from(input_data, input_ptr, pos)' <<<"$cbor_decode_impl" ||
  ! grep -Fq 'bytem.view_get_u32_be_from(input_data, input_ptr, pos)' <<<"$cbor_decode_impl" ||
  ! grep -Fq 'bytem.view_get_u64_be_from(input_data, input_ptr, pos)' <<<"$cbor_decode_impl" ||
  ! grep -Fq 'var b = bytem.view_get_u8_from(input_data, input_ptr, pos)' <<<"$cbor_decode_impl" ||
  grep -Fq 'bytem.view_get_u8_unchecked(' <<<"$cbor_decode_impl" ||
  grep -Fq 'bytem.view_get_u16_be_unchecked(' <<<"$cbor_decode_impl" ||
  grep -Fq 'bytem.view_get_u32_be_unchecked(' <<<"$cbor_decode_impl" ||
  grep -Fq 'bytem.view_get_u64_be_unchecked(' <<<"$cbor_decode_impl"; then
  echo "ERROR: std:cbor decode must hoist shared byte-view backing storage for header and argument reads" >&2
  exit 1
fi
buffer_view_impl="$(sed -n '/fn _slice_copy_from_u8_buf_direct/,/fn _strided_load_i32_unchecked/p' lib/std/buffer/view.oren)"
if ! grep -Fq 'bytesm.copy_into(s[0], s[1], src, 0, ns)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'return oren_u8_buf_copy_from_string_slice_at(s[0], s[1], text, off, n)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'var input_ptr = bytesm.view_ptr(bv)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'ptr_set_byte(data + s[1] + i * s[3], bytesm.view_get_u8_from(input_data, input_ptr, off + i) & 255)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'ptr_set_byte(data + s[1] + i * s[3], raw._load_u8_direct(src, i) & 255)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'ptr_set_byte(data + s[1] + i * s[3], oren_string_byte_at_unchecked(text, off + i) & 255)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'ptr_set_byte(dst + i, ptr_get_byte(src + s[1] + i * s[3]) & 255)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'return _u8_view_copy_from_u8_buf(slice_store_u8, s, s[2], src, ctx)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'return _u8_view_copy_from_string_range(slice_store_u8, s, s[2], text, off, n, ctx)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'return _u8_view_copy_from_u8_buf(strided_store_u8, s, s[2], src, ctx)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'return _u8_view_copy_from_string_range(strided_store_u8, s, s[2], text, off, n, ctx)' <<<"$buffer_view_impl" ||
  ! grep -Fq 'fn slice_copy_from_u8_buf(s, src) { return _slice_copy_from_u8_buf_direct' lib/std/buffer/view.oren ||
  ! grep -Fq 'fn strided_to_u8_buf(s) { return _strided_to_u8_buf_direct' lib/std/buffer/view.oren; then
  echo "ERROR: std:buffer contiguous/strided u8 copies and strided exports must hoist byte-view inputs, use bulk contiguous string copies, and keep direct strided byte writes before fallback stores" >&2
  exit 1
fi

if ! grep -Fq 'if name == "oren_u8_buf_copy_from_string_slice_at" { native_id = 233 }' lib/compiler/codegen_bytecode/010_codegen_a.oren ||
  ! grep -Fq 'case 233: { // oren_u8_buf_copy_from_string_slice_at' lib/avm/avm_native_byte_iter_cases.inc ||
  ! grep -Fq 'OrenValue oren_u8_buf_copy_from_string_slice_at' lib/runtime/050_io_misc.inc ||
  ! grep -Fq 'fn oren_u8_buf_copy_from_string_slice_at' lib/runtime_native/160_iteration.oren; then
  echo "ERROR: offset-aware u8_buf string-slice bulk copy must be wired across native, C, bytecode, and AVM" >&2
  exit 1
fi

buffer_raw_string_impl="$(sed -n '/fn _u8_copy_from_string_range/,/fn u8_copy_from_string/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'return oren_u8_buf_copy_from_string_slice(out, s, off, n)' <<<"$buffer_raw_string_impl" ||
  ! grep -Fq 'var rc = _store_u8_direct(out, i, oren_string_byte_at_unchecked(s, off + i) & 255)' <<<"$buffer_raw_string_impl"; then
  echo "ERROR: std:buffer raw u8 string copies must use byte-native runtime copies before falling back to checked stores" >&2
  exit 1
fi

buffer_raw_pack_into_impl="$(sed -n '/fn u8_pack_into/,/fn u8_unpack/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'ptr_set_byte(data + i, xs[i] & 255)' <<<"$buffer_raw_pack_into_impl" ||
  ! grep -Fq 'var rc = _store_u8_direct(out, i, xs[i])' <<<"$buffer_raw_pack_into_impl"; then
  echo "ERROR: std:buffer raw u8 pack_into must use direct byte writes before falling back to checked stores" >&2
  exit 1
fi

buffer_u8_mat_pack_impl="$(sed -n '/fn u8_mat_pack_rows/,/fn u8_mat_unpack_rows/p;/fn u8_mat_pack_strings/,/fn u8_mat_unpack_strings/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'ptr_set_byte(data + i, v & 255)' <<<"$buffer_u8_mat_pack_impl" ||
  ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(out, r * ncols, rows[r], 0, ncols)' <<<"$buffer_u8_mat_pack_impl" ||
  grep -Fq 'ptr_set_byte(data + i, oren_string_byte_at_unchecked(row, c) & 255)' <<<"$buffer_u8_mat_pack_impl" ||
  grep -Fq 'raw._store_u8_buf_unchecked_direct(out, i' <<<"$buffer_u8_mat_pack_impl"; then
  echo "ERROR: std:buffer u8 matrix pack helpers must write row lists directly and bulk-copy string rows" >&2
  exit 1
fi

buffer_u8_mat_export_impl="$(sed -n '/fn _u8_mat_is_dense_u8_buf/,/fn _u8_mat_copy_flat_list/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'ptr_set_byte(dst + i, ptr_get_byte(row_src + c) & 255)' <<<"$buffer_u8_mat_export_impl" ||
  ! grep -Fq 'return _u8_mat_to_u8_buf_direct(m, ctx)' <<<"$buffer_u8_mat_export_impl" ||
  ! grep -Fq 'return mshared._mat_to_typed_buf_with(m, ctx, raw.u8_new_uninit, core.mat_load_u8, raw._store_u8_buf_unchecked_direct)' <<<"$buffer_u8_mat_export_impl"; then
  echo "ERROR: std:buffer non-dense u8 matrix exports must gather u8_buf rows directly before falling back to checked matrix loads" >&2
  exit 1
fi

buffer_u8_mat_impl="$(sed -n '/fn _u8_mat_copy_from_u8_buf/,/fn _u8_mat_copy_from_string_range/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'bytesm.copy_into(m[0], m[1], src, 0, total)' <<<"$buffer_u8_mat_impl" ||
  ! grep -Fq 'var v = raw._load_u8_direct(src, r * m[3] + c)' <<<"$buffer_u8_mat_impl" ||
  ! grep -Fq 'var input_ptr = bytesm.view_ptr(bv)' lib/std/buffer/mat_u8.oren ||
  ! grep -Fq 'var v = bytesm.view_get_u8_from(input_data, input_ptr, r * m[3] + c)' lib/std/buffer/mat_u8.oren ||
  ! grep -Fq 'var v = bytesm.view_get_u8_from(input_data, input_ptr, off + r * m[3] + c)' lib/std/buffer/mat_u8.oren; then
  echo "ERROR: std:buffer dense/non-dense u8 matrix copies must use direct byte-span copy or hoisted byte-view source reads" >&2
  exit 1
fi

buffer_u8_mat_string_impl="$(sed -n '/fn _u8_mat_copy_from_string_range/,/fn u8_mat_copy_from_bytes/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'return oren_u8_buf_copy_from_string_slice_at(m[0], m[1], text, off, total)' <<<"$buffer_u8_mat_string_impl" ||
  ! grep -Fq 'var rc = view.slice_store_u8(row, c, oren_string_byte_at_unchecked(text, idx) & 255)' <<<"$buffer_u8_mat_string_impl"; then
  echo "ERROR: std:buffer dense u8 matrix copies from strings must use offset-aware bulk string copies before falling back to checked row stores" >&2
  exit 1
fi

buffer_u8_mat_strings_impl="$(sed -n '/fn u8_mat_copy_from_strings/,/^}/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'oren_u8_buf_copy_from_string_slice_at(m[0], m[1] + wr * m[4], rows[wr], 0, shape[1])' <<<"$buffer_u8_mat_strings_impl" ||
  ! grep -Fq 'var rc = proj.mat_row_copy_from_string(m, r, rows[r])' <<<"$buffer_u8_mat_strings_impl"; then
  echo "ERROR: std:buffer dense u8 matrix row-string copies must use offset-aware bulk string copies before falling back to row projections" >&2
  exit 1
fi

buffer_u8_mat_list_impl="$(sed -n '/fn _u8_mat_copy_flat_list/,/fn _u8_mat_copy_from_u8_buf/p;/fn u8_mat_copy_from_rows/,/fn u8_mat_copy_from_strings/p' lib/std/buffer/mat_u8.oren)"
if ! grep -Fq 'ptr_set_byte(data + m[1] + i, xs[i] & 255)' <<<"$buffer_u8_mat_list_impl" ||
  ! grep -Fq 'ptr_set_byte(data + m[1] + i, rows[wr][wc] & 255)' <<<"$buffer_u8_mat_list_impl" ||
  ! grep -Fq 'var rc = view.slice_store_u8(row, c, xs[r * m[3] + c])' <<<"$buffer_u8_mat_list_impl" ||
  ! grep -Fq 'var rc = view.slice_store_u8(row, c, v)' <<<"$buffer_u8_mat_list_impl"; then
  echo "ERROR: std:buffer dense u8 matrix copies from flat/row lists must use direct byte writes before falling back to checked row stores" >&2
  exit 1
fi

echo "OK: AVM bytes hotpath source guards passed"
