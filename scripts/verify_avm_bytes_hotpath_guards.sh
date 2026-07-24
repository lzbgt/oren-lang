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
scene3d_binary_impl="$(cat lib/std/ui/scene3d_binary.oren)"
if ! grep -Fq 'var bin_data = _bin_data(bv)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'var bin_ptr = _bin_ptr(bv)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_u32_le_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_i32_le_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  ! grep -Fq 'bytes.view_get_u8_from(bin_data, bin_ptr, off)' <<<"$scene3d_binary_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(' <<<"$scene3d_binary_impl"; then
  echo "ERROR: std:ui/scene3d_binary must hoist byte-view backing storage for .os3d reads" >&2
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
if ! grep -Fq 'var rgba_data = bytes.view_bytes(rgba_view)' <<<"$ppm_encode_impl" ||
  ! grep -Fq 'var rgba_ptr = bytes.view_ptr(rgba_view)' <<<"$ppm_encode_impl" ||
  ! grep -Fq 'var r = bytes.view_get_u8_from(rgba_data, rgba_ptr, rgba_off + 0)' <<<"$ppm_encode_impl" ||
  grep -Fq 'bytes.view_get_u8_unchecked(rgba_view' <<<"$ppm_encode_impl"; then
  echo "ERROR: PPM RGBA encoding must hoist byte-view backing storage and avoid per-channel view metadata reads" >&2
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
ws_ping_impl="$(sed -n '/fn _send_frame_control_str/,/fn _send_frame_text/p' lib/std/net/ws.oren)"
if ! grep -Fq 'fn _send_frame_control_bytes(conn, opcode, bytes, timeout_ms, masked)' lib/std/net/ws.oren ||
  ! grep -Fq 'if n > 125 { return 0 - 22 }' <<<"$ws_ping_impl" ||
  ! grep -Fq 'return _send_frame_raw(conn, opcode, p, n, timeout_ms, masked)' <<<"$ws_ping_impl" ||
  ! grep -Fq 'fn send_ping_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_ping_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_pong_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_pong_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_control_bytes(conn, 10, payload, timeout_ms, 1)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_control_bytes(conn, 10, payload, timeout_ms, 0)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn _send_frame_close_bytes(conn, bytes, timeout_ms, masked)' lib/std/net/ws.oren ||
  ! grep -Fq 'if oren_bytes_len(bytes) == 1 { return 0 - 22 }' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_close_bytes_client(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'fn send_close_bytes_server(conn, payload, timeout_ms)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_close_bytes(conn, payload, timeout_ms, 1)' lib/std/net/ws.oren ||
  ! grep -Fq 'return _send_frame_close_bytes(conn, payload, timeout_ms, 0)' lib/std/net/ws.oren ||
  grep -Fq 'oren_string_from_bytes' <<<"$ws_ping_impl" ||
  grep -Fq 'oren_bytes_unpack' <<<"$ws_ping_impl"; then
  echo "ERROR: native WebSocket binary ping/pong/close must send u8_buf control payloads directly without byte-list or string conversion" >&2
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
if ! grep -Fq 'if opcode != 2 or payload != b"bin!"' scripts/libavm_ios_verify_net_helpers.py ||
  ! grep -Fq 'conn.sendall(b"\x81\x04text")' scripts/libavm_ios_verify_net_helpers.py ||
  ! grep -Fq 'net_ws.send(sid, bin, 5000)' tests/fixtures/ios_avm/embed_chain.oren ||
  ! grep -Fq 'net_ws.recv(sid, 4, 5000)' tests/fixtures/ios_avm/embed_chain.oren ||
  ! grep -Fq 'if oren_is_err(wrong) != true' tests/fixtures/ios_avm/embed_chain.oren; then
  echo "ERROR: iOS AVM WebSocket verifier must exercise byte-native binary frame opcodes" >&2
  exit 1
fi

if ! grep -Fq 'var table = _b64_table_ptr()' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var table = _b64url_table_ptr()' lib/std/encoding/base64.oren ||
  ! grep -Fq 'fn _input_byte_direct(input_bytes, input_ptr, idx)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'if input_ptr != nil { return ptr_get_byte(input_ptr + idx) & 255 }' lib/std/encoding/base64.oren ||
  ! grep -Fq 'var input_ptr = bytesm.view_ptr(input_view)' lib/std/encoding/base64.oren ||
  grep -Fq '_b64_char(' lib/std/encoding/base64.oren ||
  grep -Fq '_b64url_char(' lib/std/encoding/base64.oren ||
  grep -Fq 'fn _input_byte(input_view, idx)' lib/std/encoding/base64.oren ||
  ! grep -Fq 'encode list_int value' tests/modules/test_base64.oren ||
  ! grep -Fq 'base64url list_int alphabet' tests/modules/test_base64.oren; then
  echo "ERROR: Base64 encode must cache alphabet/input pointers and cover LIST_INT byte carriers" >&2
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
  ! grep -Fq '_encode_string_write_known_len(dst, pos, value, use_huffman, _next_literal_len(literal_meta))' <<<"$hpack_write_impl" ||
  ! grep -Fq 'lr["literal_lens"]' lib/std/net/hpack.oren ||
  grep -Fq 'list.push(literal_lens, n)' lib/std/net/hpack.oren; then
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
  ! grep -Fq 'ptr_set_byte(data + s[1] + i, oren_string_byte_at_unchecked(text, off + i) & 255)' <<<"$buffer_view_impl" ||
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
  echo "ERROR: std:buffer contiguous/strided u8 copies and strided exports must hoist byte-view inputs and use direct byte writes before fallback stores" >&2
  exit 1
fi

buffer_raw_string_impl="$(sed -n '/fn _u8_copy_from_string_range/,/fn u8_copy_from_string/p' lib/std/buffer/raw.oren)"
if ! grep -Fq 'ptr_set_byte(data + j, oren_string_byte_at_unchecked(s, off + j) & 255)' <<<"$buffer_raw_string_impl" ||
  ! grep -Fq 'var rc = _store_u8_direct(out, i, oren_string_byte_at_unchecked(s, off + i) & 255)' <<<"$buffer_raw_string_impl"; then
  echo "ERROR: std:buffer raw u8 string copies must use direct byte writes before falling back to checked stores" >&2
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
  ! grep -Fq 'ptr_set_byte(data + i, oren_string_byte_at_unchecked(row, c) & 255)' <<<"$buffer_u8_mat_pack_impl" ||
  grep -Fq 'raw._store_u8_buf_unchecked_direct(out, i' <<<"$buffer_u8_mat_pack_impl"; then
  echo "ERROR: std:buffer u8 matrix pack helpers must write fresh dense u8_buf matrices directly" >&2
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
if ! grep -Fq 'ptr_set_byte(data + m[1] + i, oren_string_byte_at_unchecked(text, off + i) & 255)' <<<"$buffer_u8_mat_string_impl" ||
  ! grep -Fq 'var rc = view.slice_store_u8(row, c, oren_string_byte_at_unchecked(text, idx) & 255)' <<<"$buffer_u8_mat_string_impl"; then
  echo "ERROR: std:buffer dense u8 matrix copies from strings must use direct byte writes before falling back to checked row stores" >&2
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
