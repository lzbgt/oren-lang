#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for artifact_emitter in lib/compiler/x64_pe.oren lib/compiler/x64_elf.oren lib/compiler/arm64_elf.oren lib/compiler/arm64_macho.oren; do
  if ! grep -Fq 'import artifact "artifact_bytes.oren"' "$artifact_emitter" ||
    grep -Eq 'codegen\.bytes_|codegen\.push_u(16|32|64)_le|codegen\.set_u32_le|codegen\.align_up|codegen\.int_mod' "$artifact_emitter"; then
    echo "ERROR: native artifact emitters must route shared byte-packing helpers through artifact_bytes.oren, not arch codegen facades" >&2
    exit 1
  fi
done

if ! grep -Fq 'import bb "bytes_builder.oren"' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn bytes_extend_zeros(b, n) { return bb.bytes_extend_zeros(b, n) }' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn bytes_extend_u8_buf(b, ubuf) { return bb.bytes_extend_u8_buf(b, ubuf) }' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return bb.bytes_extend_string_z(b, s) }' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn bytes_extend_string_slice(b, s, off, n) { return bb.bytes_extend_string_slice(b, s, off, n) }' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn push_u16_le(buf, n) { return bb.bytes_push_u16_le(buf, n) }' lib/compiler/artifact_bytes.oren ||
  ! grep -Fq 'fn set_u64_le(buf, offset, n) { return bb.bytes_set_u64_le(buf, offset, n) }' lib/compiler/artifact_bytes.oren; then
  echo "ERROR: artifact_bytes.oren must expose shared bytes_builder-backed artifact byte helpers" >&2
  exit 1
fi

if ! grep -Fq 'import artifact "artifact_bytes.oren"' lib/compiler/elf_artifact.oren ||
  ! grep -Fq 'import elfart "elf_artifact.oren"' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'import elfart "elf_artifact.oren"' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'fn _elf_push_phdr(p, p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align) {' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'return elfart.push_phdr(p, p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'fn _elf_push_phdr(p, p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align) {' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'return elfart.push_phdr(p, p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align)' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'return elfart.build_prefix(base, hdr_size, phdrs, entry_off, is_shared_lib, 183, 0, 0)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'return elfart.build_prefix(base, hdr_size, phdrs, entry_off, is_shared_lib, 62, 4, 3)' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'var phdrs = elfart.build_program_headers(base, phnum, dyn, is_shared == true, data_file_off, bytes_len(data), dyn_meta)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'var phdrs = elfart.build_program_headers(base, phnum, dyn, is_shared_lib, data_file_off, bytes_len(data), dyn_meta)' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'return elfart.bytes_align(buf, align)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'return elfart.bytes_align(buf, align)' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'return elfart.bytes_add_str0(buf, s)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'return elfart.bytes_add_str0(buf, s)' lib/compiler/x64_elf.oren; then
  echo "ERROR: x64/ARM64 ELF emitters must share format-level helper bodies through elf_artifact.oren" >&2
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
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return artifact.bytes_extend_zeros(b, n) }' lib/compiler/x64_pe.oren ||
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
arm64_elf_dynmeta_impl="$(sed -n '/fn _elf_arm64_append_dyn_metadata/,/fn elf_build_prefix_arm64/p' lib/compiler/arm64_elf.oren)"
x64_elf_dynmeta_impl="$(sed -n '/fn _elf_x64_append_dyn_metadata/,/fn elf_build_prefix_x64/p' lib/compiler/x64_elf.oren)"
arm64_elf_prefix_impl="$(sed -n '/fn elf_build_prefix_arm64/,/^}/p' lib/compiler/arm64_elf.oren)"
x64_elf_prefix_impl="$(sed -n '/fn elf_build_prefix_x64/,/^}/p' lib/compiler/x64_elf.oren)"
elf_artifact_header_impl="$(sed -n '/fn build_prefix/,/fn bytes_align/p' lib/compiler/elf_artifact.oren)"
elf_artifact_align_impl="$(sed -n '/fn bytes_align/,/^}/p' lib/compiler/elf_artifact.oren)"
elf_artifact_dyn_impl="$(cat lib/compiler/elf_artifact.oren)"
if ! grep -Fq 'fn bytes_extend_zeros(b, n) { return artifact.bytes_extend_zeros(b, n) }' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_zeros(b, n) { return artifact.bytes_extend_zeros(b, n) }' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'fn dyn_needed_libs(user_link_libs)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_unique(out, seen, "libdl.so.2")' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_unique(out, seen, "libc.so.6")' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn push_dynsym_undef_func(dynsym, name_off)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(dynsym, 16) // st_value + st_size' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn push_dynsym_text_func(dynsym, name_off, text_addr)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(dynsym, 8) // unknown size' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn build_dynamic_import_symbols(imports, sym_dynstr_offs)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(dynsym, 24) // STN_UNDEF' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_dynsym_undef_func(dynsym, name_off)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn dynamic_export_offset(functions, export_wrappers, name)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'return export_wrappers[name]' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn push_dynamic_export_symbol(dynsym, sym_dynstr_offs, name, text_addr)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_dynsym_text_func(dynsym, name_off, text_addr)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn append_dynamic_prelude(data, interp, is_shared_lib)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_string_z(data, interp)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.push_u64_le(data, 0)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn build_dynamic_name_tables(needed, imports, exports, missing_import_msg, missing_import_diag)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(dynstr, 1) // leading NUL' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'needed_dynstr_offs[lib] = bytes_add_str0(dynstr, lib)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'sym_dynstr_offs[nm] = bytes_add_str0(dynstr, nm)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'sym_dynstr_offs[nm3] = bytes_add_str0(dynstr, nm3)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn push_rela(rela, r_offset, sym_idx, rela_type, addend)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.push_u64_le(rela, sym_idx * 4294967296 + rela_type)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn build_prefix(base, hdr_size, phdrs, entry_off, is_shared_lib, machine, shnum, shstrndx)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_push(p, 127); artifact.bytes_push(p, 69); artifact.bytes_push(p, 76); artifact.bytes_push(p, 70) // .ELF' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'artifact.push_u16_le(p, machine)' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'artifact.push_u16_le(p, oren_list_len(phdrs))' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'artifact.push_u16_le(p, shnum)' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'artifact.push_u16_le(p, shstrndx)' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'push_phdr(p,' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'fn build_program_headers(base, phnum, dyn, is_shared_lib, data_file_off, data_len, dyn_meta)' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 6, "flags": 4, "offset": 64' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 3, "flags": 4, "offset": interp_off' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 1, "flags": 5, "offset": 0' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 1, "flags": 6, "offset": data_file_off' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 2, "flags": 6, "offset": dynamic_off' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'oren_list_push(phdrs, {"type": 1685382481, "flags": 6' <<<"$elf_artifact_header_impl" ||
  ! grep -Fq 'fn build_sysv_hash(nchain)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(hash, (nbucket + nchain) * 4)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn build_dynamic_hash(imports, exports)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'return build_sysv_hash(1 + import_count + export_count)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn push_dynamic_import_rela(rela, base, data_file_off, got_off, import_index, rela_type)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'var sym_idx = 1 + import_index' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'var r_offset = base + data_file_off + got_off' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_rela(rela, r_offset, sym_idx, rela_type, 0)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn append_dyn_tables(data, hash, dynstr, dynsym, rela)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn build_dynamic_table(needed, needed_dynstr_offs, data_addr, table_offsets, dynstr, rela, init_array_off)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'fn append_dynamic_sections(data, data_addr, hash, dynstr, dynsym, rela, needed, needed_dynstr_offs, init_array_off)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'var table_offsets = append_dyn_tables(data, hash, dynstr, dynsym, rela)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'var dyn = build_dynamic_table(needed, needed_dynstr_offs, data_addr, table_offsets, dynstr, rela, init_array_off)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'artifact.bytes_extend(data, dyn)' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'push_dynamic_entry(dyn, 0, 0) // DT_NULL' <<<"$elf_artifact_dyn_impl" ||
  ! grep -Fq 'return elfart.dyn_needed_libs(user_link_libs)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'return elfart.dyn_needed_libs(user_link_libs)' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'var dyn_prelude = elfart.append_dynamic_prelude(data, "/lib/ld-linux-aarch64.so.1", is_shared_lib)' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dyn_prelude = elfart.append_dynamic_prelude(data, "/lib64/ld-linux-x86-64.so.2", is_shared_lib)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dyn_names = elfart.build_dynamic_name_tables(needed, imports, exports, missing_import, elf_diag_escape(missing_import))' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dyn_names = elfart.build_dynamic_name_tables(needed, imports, exports, "x64 elf: internal: dyn import missing name", nil)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dynsym = elfart.build_dynamic_import_symbols(imports, sym_dynstr_offs)' <<<"$arm64_elf_dynsym_impl" ||
  ! grep -Fq 'var dynsym = elfart.build_dynamic_import_symbols(imports, sym_dynstr_offs)' <<<"$x64_elf_dynsym_impl" ||
  ! grep -Fq 'var fn_off = elfart.dynamic_export_offset(functions, export_wrappers, enm)' <<<"$arm64_elf_dynsym_impl" ||
  ! grep -Fq 'var fn_off = elfart.dynamic_export_offset(functions, export_wrappers, enm)' <<<"$x64_elf_dynsym_impl" ||
  ! grep -Fq 'elfart.push_dynamic_export_symbol(dynsym, sym_dynstr_offs, enm, text_base + fn_off)' <<<"$arm64_elf_dynsym_impl" ||
  ! grep -Fq 'elfart.push_dynamic_export_symbol(dynsym, sym_dynstr_offs, enm, text_base + fn_off)' <<<"$x64_elf_dynsym_impl" ||
  ! grep -Fq 'elfart.push_rela(rela, r_offset0, 0, rela_type_relative, add0)' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_dynamic_import_rela(rela, base, data_file_off, got_off, i_rel, rela_type_glob_dat)' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_rela(rela, r_offset0, 0, rela_type_relative, add0)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_rela(rela, r_offset_rt, 0, rela_type_relative, add_rt)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_rela(rela, r_offset1, 0, rela_type_relative, add1)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_rela(rela, r_offset2, 0, rela_type_relative, add2)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'elfart.push_dynamic_import_rela(rela, base, data_file_off, got_off, i_rel, rela_type_glob_dat)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'var hash = elfart.build_dynamic_hash(imports, exports)' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'var hash = elfart.build_dynamic_hash(imports, exports)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dyn_tail = elfart.append_dynamic_sections(data, data_addr, hash, dynstr, dynsym, rela, needed, needed_dynstr_offs, init_array_off)' <<<"$arm64_elf_dynmeta_impl" ||
  ! grep -Fq 'var dyn_tail = elfart.append_dynamic_sections(data, data_addr, hash, dynstr, dynsym, rela, needed, needed_dynstr_offs, init_array_off)' <<<"$x64_elf_dynmeta_impl" ||
  ! grep -Fq 'var rem = artifact.int_mod(artifact.bytes_len(buf), align)' <<<"$elf_artifact_align_impl" ||
  ! grep -Fq 'if rem != 0 { artifact.bytes_extend_zeros(buf, align - rem) }' <<<"$elf_artifact_align_impl" ||
  ! grep -Fq 'return elfart.bytes_align(buf, align)' <<<"$arm64_elf_align_impl" ||
  ! grep -Fq 'return elfart.bytes_align(buf, align)' <<<"$x64_elf_align_impl" ||
  ! grep -Fq '_bytes_align(data, 8)' <<<"$arm64_elf_layout_impl" ||
  ! grep -Fq 'bytes_extend_zeros(prefix, pad_len)' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'bytes_extend_zeros(prefix, pad_len)' lib/compiler/x64_elf.oren ||
  grep -Fq 'var code_pad = bytes_new()' lib/compiler/arm64_elf.oren ||
  grep -Fq 'var code_pad = bytes_new()' lib/compiler/x64_elf.oren ||
  grep -Fq 'bytes_push(dynsym, 0)  // st_other' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'push_u64_le(dynsym, 0); push_u64_le(dynsym, 0); push_u64_le(dynsym, 0)' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'bytes_extend_zeros(dynsym, 24)' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'elfart.push_dynsym_undef_func(dynsym, name_off)' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'export_wrappers[enm]' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'functions[enm]' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'var name_off2 = sym_dynstr_offs[enm]' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'elfart.push_dynsym_text_func(dynsym, name_off2, text_base + fn_off)' <<<"$arm64_elf_dynsym_impl$x64_elf_dynsym_impl" ||
  grep -Fq 'needed_dynstr_offs[lib] = _bytes_add_str0(dynstr, lib)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'sym_dynstr_offs[nm] = _bytes_add_str0(dynstr, nm)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'sym_dynstr_offs[nm3] = _bytes_add_str0(dynstr, nm3)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'var r_info' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'var sym_idx = 1 + i_rel' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'var r_offset = base + data_file_off + got_off' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'elfart.push_rela(rela, r_offset, sym_idx, rela_type_glob_dat, 0)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'push_u64_le(rela, r_info' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'while ci < nchain' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'var nchain = 1 + oren_list_len(imports) + oren_list_len(exports)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'elfart.build_sysv_hash(nchain)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'push_u64_le(dyn, 1)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'push_u64_le(dyn, 0); push_u64_le(dyn, 0)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'elfart.append_dyn_tables(data, hash, dynstr, dynsym, rela)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'elfart.build_dynamic_table(needed, needed_dynstr_offs, data_addr, table_offsets, dynstr, rela, init_array_off)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'bytes_extend(data, dyn)' <<<"$arm64_elf_dynmeta_impl$x64_elf_dynmeta_impl" ||
  grep -Fq 'bytes_push(p, 127)' <<<"$arm64_elf_prefix_impl$x64_elf_prefix_impl" ||
  grep -Fq 'push_u16_le(p, 183)' <<<"$arm64_elf_prefix_impl" ||
  grep -Fq 'push_u16_le(p, 62)' <<<"$x64_elf_prefix_impl" ||
  grep -Fq 'oren_list_push(phdrs, {"type": 6' lib/compiler/arm64_elf.oren ||
  grep -Fq 'oren_list_push(phdrs, {"type": 6' lib/compiler/x64_elf.oren ||
  grep -Fq 'oren_list_push(phdrs, {"type": 1685382481' lib/compiler/arm64_elf.oren ||
  grep -Fq 'oren_list_push(phdrs, {"type": 1685382481' lib/compiler/x64_elf.oren ||
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
arm64_elf_dynamic_impl="$(sed -n '/Dynamic-link prelude/,/Build dynsym (DT_SYMTAB)/p' lib/compiler/arm64_elf.oren)"
x64_elf_dynamic_impl="$(sed -n '/Dynamic-link prelude/,/Build dynsym (DT_SYMTAB)/p' lib/compiler/x64_elf.oren)"
arm64_elf_data_cstr_impl="$(sed -n '/fn _data_add_cstr0/,/^}/p' lib/compiler/arm64_elf.oren)"
elf_artifact_string_impl="$(sed -n '/fn push_utf8_aligned/,/fn bytes_align/p; /fn push_string_bytes/,/fn push_unique/p' lib/compiler/elf_artifact.oren)"
native_debug_artifact_string_impl="$(sed -n '/fn push_utf8_aligned/,/fn push_u64_zero4/p; /fn emit_user_func_records/,/^}/p' lib/compiler/native_debug_artifact.oren)"
arm64_macho_bind_impl="$(sed -n '/fn macho_build_bind_opcodes/,/fn macho_build_prefix_arm64/p' lib/compiler/arm64_macho.oren)"
arm64_macho_string_impl="$(sed -n '/fn _macho_push_string_bytes/,/fn push_uleb128/p; /fn _macho_push_utf8_aligned/,/fn emit_debug_info/p' lib/compiler/arm64_macho.oren)"
arm64_macho_file_impl="$(cat lib/compiler/arm64_macho.oren)"
x64_pe_ascii_impl="$(sed -n '/fn push_ascii_z/,/fn _pe_path_basename/p' lib/compiler/x64_pe.oren)"
if ! grep -Fq 'fn bytes_extend_string_z(b, s) { return artifact.bytes_extend_string_z(b, s) }' lib/compiler/arm64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return artifact.bytes_extend_string_z(b, s) }' lib/compiler/x64_elf.oren ||
  ! grep -Fq 'fn bytes_extend_string(b, s) { return artifact.bytes_extend_string(b, s) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return artifact.bytes_extend_string_z(b, s) }' lib/compiler/arm64_macho.oren ||
  ! grep -Fq 'fn bytes_extend_string_z(b, s) { return artifact.bytes_extend_string_z(b, s) }' lib/compiler/x64_pe.oren ||
  ! grep -Fq 'debugart.push_utf8_aligned(p, s)' <<<"$elf_artifact_string_impl" ||
  ! grep -Fq 'artifact.bytes_extend_string(p, s)' <<<"$native_debug_artifact_string_impl" ||
  ! grep -Fq 'var rem = artifact.int_mod(artifact.bytes_len(p), 8)' <<<"$native_debug_artifact_string_impl" ||
  ! grep -Fq 'if rem != 0 { artifact.bytes_extend_zeros(p, 8 - rem) }' <<<"$native_debug_artifact_string_impl" ||
  ! grep -Fq 'artifact.bytes_extend_string(buf, s)' <<<"$elf_artifact_string_impl" ||
  ! grep -Fq 'artifact.bytes_extend_string_z(buf, s)' <<<"$elf_artifact_string_impl" ||
  ! grep -Fq 'return elfart.push_string_bytes(buf, s)' <<<"$arm64_elf_string_impl" ||
  ! grep -Fq 'return elfart.bytes_add_str0(buf, s)' <<<"$arm64_elf_cstr_impl" ||
  ! grep -Fq 'return elfart.push_string_bytes(buf, s)' <<<"$x64_elf_string_impl" ||
  ! grep -Fq 'return elfart.bytes_add_str0(buf, s)' <<<"$x64_elf_cstr_impl" ||
  ! grep -Fq 'elfart.append_dynamic_prelude(data, "/lib/ld-linux-aarch64.so.1", is_shared_lib)' <<<"$arm64_elf_dynamic_impl" ||
  ! grep -Fq 'elfart.append_dynamic_prelude(data, "/lib64/ld-linux-x86-64.so.2", is_shared_lib)' <<<"$x64_elf_dynamic_impl" ||
  ! grep -Fq 'artifact.bytes_extend_zeros(dynstr, 1) // leading NUL' <<<"$elf_artifact_string_impl$elf_artifact_dyn_impl" ||
  ! grep -Fq 'bytes_extend_string_z(data, s)' <<<"$arm64_elf_data_cstr_impl" ||
  ! grep -Fq 'bytes_extend_zeros(shstr, 1)' <<<"$x64_elf_build_shstr_impl" ||
  test "$(grep -Fc 'bytes_extend_string_z(shstr,' <<<"$x64_elf_build_shstr_impl")" != "3" ||
  ! grep -Fq 'bytes_extend_string(buf, s)' <<<"$arm64_macho_string_impl" ||
  ! grep -Fq 'bytes_extend_string_z(buf, s)' <<<"$arm64_macho_string_impl" ||
  ! grep -Fq 'return debugart.push_utf8_aligned(p, s)' <<<"$arm64_macho_string_impl" ||
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
  grep -Fq 'var interp =' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'interp_off = bytes_len(data)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'bytes_extend_string_z(data, interp)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'push_u64_le(data, 0)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl" ||
  grep -Fq 'bytes_push(data, 0)' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl$arm64_elf_data_cstr_impl" ||
  grep -Fq 'bytes_push(dynstr, 0) // leading NUL' <<<"$arm64_elf_dynamic_impl$x64_elf_dynamic_impl$elf_artifact_dyn_impl" ||
  grep -Fq 'bytes_push(shstr, 0)' <<<"$x64_elf_build_shstr_impl" ||
  grep -Fq 'bytes_push(strtab, 0)' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'bytes_push(symtab, 0) // n_sect' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(bind_name' <<<"$arm64_macho_file_impl" ||
  grep -Fq 'oren_string_byte_at_unchecked(f_name' <<<"$arm64_macho_file_impl"; then
  echo "ERROR: compiler artifact string append helpers must use byte-builder string extension, not per-byte string loops" >&2
  exit 1
fi
