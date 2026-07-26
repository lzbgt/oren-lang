#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

x64_sys_data_split_impl="$(sed -n '/fn _x64_fcntl_getfl_translate_nonblock/,/fn _x64_sys_rw_linux_slots/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/000_prelude.oren)
$(sed -n '/fn _x64_emit_sys_write_windows_writefile/,/fn _emit_intrinsic_sys_write_linux_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/000_prelude.oren)
$(sed -n '/fn _x64_emit_fcntl_setfl_windows_prehook/,/fn _x64_iocp_emit_invalid_param_handle_eio/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren)
$(sed -n '/fn _x64_gettimeofday_windows_call_filetime/,/fn _x64_gettimeofday_windows_new_labels/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_gettimeofday_windows_new_labels/,/fn _emit_sys_open_windows_capsule_pre_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_emit_getentropy_windows_rng_args/,/fn _x64_emit_getentropy_windows_finish/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _x64_win_wait_single_object_result_labels/,/fn _emit_intrinsic_sys_win_wait_single_object_windows_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_threads.oren)
$(sed -n '/fn _x64_linux_epoll_create1_state/,/fn _x64_linux_epoll_ctl_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_linux_net.oren)
$(sed -n '/fn _x64_wsa_store_wsabuf_local/,/fn _x64_wsarecv_normalize_result/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren) $(sed -n '/fn _x64_cancel_io_ex_result_labels/,/fn _emit_intrinsic_sys_cancel_io_ex_windows_x64/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_net_iocp.oren)
$(sed -n '/fn _emit_win64_stat_regular_file_mode_x64/,/fn _x64_windows_stat_finish/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren)
$(sed -n '/fn _x64_windows_fstat_labels/,/fn _x64_unlink_rmdir_windows_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren)
$(sed -n '/fn _emit_nanosleep_timespec_syscall_x64/,/fn _x64_linux_nanosleep_state/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/090_tail.oren) $(sed -n '/fn _x64_linux_pipe_widen_labels/,/fn _x64_emit_linux_thread_child_path/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics/090_tail.oren) $(sed -n '/fn _x64_windows_open_alloc_state/,/fn _x64_windows_open_labels/p' lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren)
$(sed -n '/fn _emit_windows_write_ptr_len/,/fn _emit_panic_preserve_msg_reg/p' lib/compiler/x64_native_program/071_panic.oren)
$(sed -n '/fn _data_cstr0_normalize_sentinel/,/fn _data_add_fnobj/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_reserve_u64_table_region/,/fn _x64_data_rtobj_decode_enc0/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_store_linetab_reservation/,/fn _data_finalize_linetab/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _data_dbginfo_entry_offsets/,/fn _data_finalize_linetab_table/p' lib/compiler/x64_native_program/010_data_io.oren)
$(sed -n '/fn _x64_ffi_resolver_linux_name/,/fn _x64_ffi_stub_linux_dyn_data/p' lib/compiler/x64_native_program/072_ffi.oren) $(sed -n '/fn _x64_emit_ffi_stub_linux_dyn_cached_load/,/fn _x64_emit_ffi_stubs/p' lib/compiler/x64_native_program/072_ffi.oren)
$(sed -n '/fn _x64_new_ctx_base_buffers/,/fn _x64_new_ctx_aliases/p' lib/compiler/x64_native_program/090_program_entry/000_prelude.oren)
$(sed -n '/fn _x64_new_ctx_runtime_cstr_slot/,/fn _x64_new_ctx_trace_flags/p' lib/compiler/x64_native_program/090_program_entry/000_prelude.oren)"
if ! grep -Fq 'fn _x64_gettimeofday_windows_emit_body(ctx, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_gettimeofday_windows_call_filetime(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_gettimeofday_windows_filetime_to_unix(ctx)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_qpc_frequency_labels(ctx)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_qpc_frequency_emit_body_windows(ctx, state, lab)' <<<"$x64_sys_data_split_impl" ||
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
  ! grep -Fq 'fn _x64_emit_sys_write_windows_finish(ctx, labels, local_fixups, l_ret0, l_done, base)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_sys_write_linux_labels(ctx)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_emit_sys_write_linux_body(ctx, st, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_fcntl_setfl_windows_labels()' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_emit_fcntl_setfl_windows_body(ctx, state, capsule, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_finish_fcntl_setfl_windows(ctx, state, lab)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_win64_stat_file_size_probe_x64(ctx, tmp_st, tmp_handle)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_stat_emit_attr_prepare(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_windows_fstat_labels(ctx)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_windows_fstat_emit_body(ctx, locals, state, flab, labels, fixups)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_fstat_emit_done(ctx, labels, fixups, capsule, base, l_done)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_nanosleep_timespec_on_stack_x64(ctx, tmp_ns)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_linux_pipe_emit_widen_body(ctx, st, lab)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_emit_linux_thread_clone_setup(ctx, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_open_alloc_state(ctx, locals)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_windows_open_spill_args(ctx, locals, args, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _data_cstr0_normalize_sentinel(s)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _data_dbginfo_entry_offsets(entries, i, code_len)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _emit_windows_writefile_stdout_handle(ctx, ptr_reg, len_reg)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_reserve_u64_table_region(ctx, count)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_store_linetab_reservation(ctx, linetab_off, cap_entries)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_emit_cstr0_table(ctx, state)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_fcntl_getfl_translate_success(ctx, labels, fixups)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_emit_sys_read_windows_stdin_handle(ctx, local_fixups, tmp_fd, l_have_handle)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _data_emit_dbginfo_table(ctx, platform, entries)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_ffi_resolver_linux_emit_body(ctx, got_dlsym)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_emit_ffi_stub_win64_body(ctx, data, resolver_name, labels, local_fixups)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_new_ctx_base_functions(ctx)' <<<"$x64_sys_data_split_impl" || ! grep -Fq 'fn _x64_new_ctx_trace_env_flag(ctx, env_name, key)' <<<"$x64_sys_data_split_impl" ||
  ! grep -Fq 'fn _x64_new_ctx_runtime_boot_globals(ctx, trace_ctx)' <<<"$x64_sys_data_split_impl"; then
  echo "ERROR: x64 system read/write/fcntl/stat/panic/data-table reservation/emission, FFI, and context setup codegen must keep split focused helper bodies" >&2
  exit 1
fi
