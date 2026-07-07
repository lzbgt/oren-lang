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
if ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$host_write_bytes_impl" ||
  ! grep -Fq 'chunk[i] = (uint8_t)(list->items[off + (int)i].as.i & 255)' <<<"$host_write_bytes_impl" ||
  ! grep -Fq 'chunk[i] = (uint8_t)(list_int->items[off + (int)i] & 255)' <<<"$host_write_bytes_impl" ||
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
if ! grep -Fq 'uint8_t chunk[64 * 1024]' <<<"$c_runtime_write_bytes_impl" ||
  ! grep -Fq 'chunk[i] = (uint8_t)(bytes.as.list_val->items[off + (int)i].as.int_val & 255)' <<<"$c_runtime_write_bytes_impl" ||
  ! grep -Fq 'size_t nw = fwrite(chunk, 1, want, f)' <<<"$c_runtime_write_bytes_impl" ||
  ! grep -Fq 'FILE *f = fopen(path.as.string_val, "wb");' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'uint8_t* tmp = (uint8_t*)malloc((size_t)nbytes)' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'tmp[i] = (uint8_t)b' <<<"$c_runtime_write_bytes_impl" ||
  grep -Fq 'fwrite(tmp, 1, (size_t)nbytes, f)' <<<"$c_runtime_write_bytes_impl"; then
  echo "ERROR: legacy C runtime write_bytes must validate list input then write bounded stack chunks, not allocate a full-file temp buffer" >&2
  exit 1
fi
if ! grep -Fq 'invalid write clobbered existing file' tests/modules/test_read_bytes.oren; then
  echo "ERROR: legacy C runtime write_bytes must keep fixture coverage proving invalid byte lists do not clobber existing files" >&2
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

if ! grep -Fq 'assert_eq(oren_bytes_set_u8(li, 0, 170), 170)' tests/avm/test_bytes_set_endian.oren ||
  ! grep -Fq 'assert_eq(oren_bytes_set_i64_le(li, 0, -2), -2)' tests/avm/test_bytes_set_endian.oren; then
  echo "ERROR: AVM byte setter fixtures must cover direct LIST_INT mutation paths" >&2
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
if ! grep -Fq 'native_bytes_copy_span(bytes, start, len, out)' <<<"$native_string_slice_impl" ||
  ! grep -Fq 'native_bytes_copy_span(bytes, start, len, dst)' <<<"$native_u8_slice_impl" ||
  ! grep -Fq 'native_bytes_copy_span_to_int_list(bytes, 0, n, out)' <<<"$native_pack_unpack_impl" ||
  ! grep -Fq 'native_bytes_copy_span(xs, 0, n, outp)' <<<"$native_pack_unpack_impl" ||
  grep -Fq 'ptr_get(list_buf + (start + i) * 8)' <<<"$native_string_slice_impl$native_u8_slice_impl" ||
  grep -Fq 'ptr_get(list_buf + j * 8)' <<<"$native_pack_unpack_impl" ||
  grep -Fq 'ptr_get(in_buf + i * 8)' <<<"$native_pack_unpack_impl"; then
  echo "ERROR: native byte slice/pack/unpack helpers must route through shared copy-span helpers instead of duplicating list/LIST_INT loops" >&2
  exit 1
fi

c_runtime_copy_helper="$(sed -n '/static int runtime_bytes_copy_span(OrenValue bytes/,/^}/p' lib/runtime/040_lists_maps.inc)"
c_runtime_copy_list_helper="$(sed -n '/static int runtime_bytes_copy_span_to_list(OrenValue bytes/,/^}/p' lib/runtime/040_lists_maps.inc)"
c_runtime_unpack_impl="$(sed -n '/OrenValue oren_bytes_unpack/,/OrenValue oren_bytes_get_u16_be/p' lib/runtime/040_lists_maps.inc)"
c_runtime_pack_impl="$(sed -n '/OrenValue oren_bytes_pack/,/^}/p' lib/runtime/045_bytes_helpers.inc)"
c_runtime_string_slice_impl="$(sed -n '/OrenValue oren_string_from_bytes_slice/,/OrenValue oren_u8_buf_from_bytes_slice/p' lib/runtime/050_io_misc.inc)"
c_runtime_u8_slice_impl="$(sed -n '/OrenValue oren_u8_buf_from_bytes_slice/,/OrenValue oren_string_join/p' lib/runtime/050_io_misc.inc)"
if ! grep -Fq 'memcpy(dst, b->data + start, n)' <<<"$c_runtime_copy_helper" ||
  ! grep -Fq 'dst[i] = (uint8_t)it.as.int_val' <<<"$c_runtime_copy_helper"; then
  echo "ERROR: C runtime byte slice/pack helpers must share one checked list/u8_buf copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'dst->items[i] = oren_int((int64_t)b->data[start + i])' <<<"$c_runtime_copy_list_helper" ||
  ! grep -Fq 'dst->items[i] = oren_int(it.as.int_val)' <<<"$c_runtime_copy_list_helper"; then
  echo "ERROR: C runtime bytes_unpack must share one checked list/u8_buf to list copy-span helper" >&2
  exit 1
fi
if ! grep -Fq 'runtime_bytes_copy_span_to_list(bytes, 0u, count_size, list' <<<"$c_runtime_unpack_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(xs, 0u, (size_t)list->count, out->data' <<<"$c_runtime_pack_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out' <<<"$c_runtime_string_slice_impl" ||
  ! grep -Fq 'runtime_bytes_copy_span(bytes, s, n, (uint8_t*)out->data' <<<"$c_runtime_u8_slice_impl" ||
  grep -Fq 'OrenValue it = list->items[s + i]' <<<"$c_runtime_string_slice_impl$c_runtime_u8_slice_impl" ||
  grep -Fq 'OrenValue v = src->items[i]' <<<"$c_runtime_unpack_impl" ||
  grep -Fq 'OrenValue v = list->items[i]' <<<"$c_runtime_pack_impl"; then
  echo "ERROR: C runtime byte slice/pack/unpack helpers must route through shared copy-span helpers instead of duplicating list/u8_buf loops" >&2
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
  ! grep -Fq 'ok = avm_vfs_put_list_int(vm, path ? path : "", args[1].as.li)' <<<"$vfs_write_bytes_domain_impl"; then
  echo "ERROR: AVM VFS write_bytes must accept LIST_INT carriers directly" >&2
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
