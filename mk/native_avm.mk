# AVM test suite (bytecode build + avm run).
#
# Note:
# - Kept separate from default `make test` so native iteration stays extremely fast.
#
# AVM test selection:
# - Default: curated smoke list for iteration velocity.
# - Override for full coverage: `make test-avm AVM_TESTS="tests/avm/*.oren"`.
# - Per-fixture release policy lives in tests/avm/release_manifest.json.
AVM_TESTS ?= \
	tests/avm/test_smoke_suite.oren \
	tests/avm/test_closure_fn_values.oren \
	tests/avm/test_policy_scan.oren \
	tests/avm/test_job_scan.oren \
	tests/avm/test_snapshot_resume.oren \
	tests/avm/test_multiverse_invalid_obc.oren \
	tests/avm/test_multiverse_avm_domain.oren \
	tests/avm/test_multiverse_net_fixtures.oren \
	tests/avm/test_multiverse_proc_fixtures.oren \
	tests/avm/test_multiverse_vfs_fixtures.oren \
	tests/avm/test_multiverse_vfs_inherit.oren \
	tests/avm/test_std_time_avm.oren \
	tests/avm/test_time_rng_deterministic.oren \
	tests/avm/test_time_rng_record_replay_mem.oren \
	tests/avm/test_record_replay_env.oren \
	tests/avm/test_record_replay_exit.oren \
	tests/avm/test_record_replay_fs.oren \
	tests/avm/test_record_replay_mem_fs.oren \
	tests/avm/test_record_replay_proc.oren \
	tests/avm/test_snapshot_resume_record_log.oren \
	tests/avm/test_snapshot_tasks_resume.oren \
	tests/avm/test_snapshot_vfs_resume.oren \
	tests/avm/test_budget_gas.oren \
	tests/avm/test_budget_timeout.oren \
	tests/avm/test_budget_io_fs.oren \
	tests/avm/test_budget_log_mem.oren \
	tests/avm/test_budget_mem.oren \
	tests/avm/test_call_depth_limit.oren \
	tests/avm/test_call_stack_discipline.oren \
	tests/avm/test_arith_invalid.oren \
	tests/avm/test_vfs_no_host_fs.oren \
	tests/avm/test_capability_deny_fs.oren \
	tests/avm/test_capsule_allow_fs.oren \
	tests/avm/test_capsule_defaults.oren \
	tests/avm/test_error_read_file.oren \
	tests/avm/test_fs_helpers_vfs.oren \
	tests/avm/test_fs_mounts_host_backend.oren \
	tests/avm/test_oren_env_bridge_capsule.oren \
	tests/avm/test_read_bytes_roundtrip.oren \
	tests/avm/test_vproc_no_host_proc.oren \
	tests/avm/test_vnet_no_host_net.oren \
	tests/avm/test_avm_permission_request_v0.oren \
	tests/avm/test_avm_events_v0.oren \
	tests/avm/test_switch.oren \
	tests/avm/test_attributes_fields_params.oren \
	tests/avm/test_attributes_noop.oren \
	tests/avm/test_bool_bit_ops.oren \
	tests/avm/test_float_ops.oren \
	tests/avm/test_for_break_continue.oren \
	tests/avm/test_for_in_bytes.oren \
	tests/avm/test_for_in_list.oren \
	tests/avm/test_for_in_map_keys.oren \
	tests/avm/test_for_in_string.oren \
	tests/avm/test_generic_call_specialization.oren \
	tests/avm/test_varargs_call_spread.oren \
	tests/avm/test_varargs_spawn.oren \
	tests/avm/test_int_literal_bases.oren \
	tests/avm/test_int_casts.oren \
	tests/avm/test_list_append_grow.oren \
	tests/avm/test_map_iter_deterministic.oren \
	tests/avm/test_map_key_order.oren \
	tests/avm/test_map_key_types.oren \
	tests/avm/test_result_hash_repeat.oren \
	tests/avm/test_state_hash_repeat.oren \
	tests/avm/test_state_hash_includes_vfs.oren \
	tests/avm/test_trace_hash_repeat.oren \
	tests/avm/test_trace_bytes_repeat.oren \
	tests/avm/test_trace_events_native.oren \
	tests/avm/test_trace_bytes_truncate.oren \
	tests/avm/test_trace_bytes_mem_budget.oren \
	tests/avm/test_nested_containers.oren \
	tests/avm/test_pack_view.oren \
	tests/avm/test_struct_member_set.oren \
	tests/avm/test_list_sum_opcodes.oren \
	tests/avm/test_list_dot_opcodes.oren \
	tests/avm/test_list_int_basic.oren \
	tests/avm/test_float_to_string.oren \
	tests/avm/test_bytes_basic.oren \
	tests/avm/test_bytes_set_endian.oren \
	tests/avm/test_std_math_core.oren \
	tests/avm/test_std_math_pow.oren \
	tests/avm/test_std_math_decompose.oren \
	tests/avm/test_std_math_exp_log.oren \
	tests/avm/test_std_math_trig.oren \
	tests/avm/test_std_bytes_portable.oren \
	tests/avm/test_std_buffer_views_portable.oren \
	tests/avm/test_u8_buf_views.oren \
	tests/avm/test_int_casts_checked.oren \
	tests/avm/test_crypto_sha256_vectors.oren \
	tests/avm/test_iter_range.oren \
	tests/avm/test_list_freelist_env.oren \
	tests/avm/test_ui_color_v0.oren \
	tests/avm/test_ui_layout_v0.oren \
	tests/avm/test_ui_patch_v0.oren \
	tests/avm/test_ui_render_v0.oren \
	tests/avm/test_ui_raster_v0.oren \
	tests/avm/test_ui_2d_conformance_v0.oren \
	tests/avm/test_ui_3d_conformance_v0.oren \
	tests/avm/test_ui_scene3d_v0.oren \
	tests/avm/test_ui_scene3d_arch_shapes_v0.oren \
	tests/avm/test_ui_scene3d_grid_shapes_v0.oren \
	tests/avm/test_ui_scene3d_transforms_v0.oren \
	tests/avm/test_ui_scene3d_solid_shapes_v0.oren \
	tests/avm/test_ui_retained_3d_republish_v0.oren \
	tests/avm/test_ui_avm_mailbox_v0.oren \
	tests/avm/test_ui_avm_event_decode_v0.oren \
	tests/avm/test_ui_avm_protocol_validation_v0.oren \
	tests/avm/test_ui_avm_frame_budget_v0.oren \
	tests/avm/test_yield_stmt_v0.oren \
	tests/avm/test_yield_value_v0.oren \
	tests/avm/test_yield_exchange_v0.oren \
	tests/avm/test_generator_v0.oren \
	tests/avm/test_coroutine_v0.oren \
	tests/avm/test_task_v0.oren \
	tests/avm/test_task_group_v0.oren \
	tests/avm/test_spawn_join_timeout.oren \
	tests/avm/test_ui_ppm_v0.oren \
	tests/avm/test_ui_cmds_validate_v0.oren

test-avm: oren avm
	@python3 scripts/verify_avm_release_manifest.py --manifest tests/avm/release_manifest.json --tests $(AVM_TESTS)

test-native-all: oren
					@echo "=== Native Tests (All) ==="
				@mkdir -p build
				@mkdir -p build/logs
				@echo "Native parallelism: set NATIVE_TEST_JOBS=... (default: 4)."
			@set -e; \
				jobs="$(strip $(NATIVE_TEST_JOBS))"; \
				if [ "$$jobs" = "" ]; then jobs=4; fi; \
				if [ "$$jobs" -lt 1 ]; then jobs=1; fi; \
				set +e; \
				find tests/native -maxdepth 1 -name '*.oren' -print0 | \
					xargs -0 -n 1 -P "$$jobs" sh -c '\
						set -e; \
						t="$$1"; \
						name=$$(basename "$$t" .oren); \
						log="build/logs/native_all_$${name}.log"; \
						: > "$$log"; \
						echo "Testing $$name..."; \
						if [ "$(OREN_TEST_TARGET)" != "windows" ]; then \
							case "$$name" in ffi_windows_*) echo "SKIP: $$name (windows-only)"; echo "STATUS: skip (windows-only)" >> "$$log"; exit 0 ;; esac; \
						fi; \
						if [ "$(OREN_TEST_TARGET)" != "linux" ]; then \
							case "$$name" in ffi_linux_*) echo "SKIP: $$name (linux-only)"; echo "STATUS: skip (linux-only)" >> "$$log"; exit 0 ;; esac; \
						fi; \
						if [ "$$name" = "linux_hello" ]; then \
							$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build "$$t" --backend native --debug -o "build/$$name" --target linux $(CODESIGN_ARG) $(GC_ARG) >> "$$log" 2>&1 || { echo "STATUS: fail (build)" >> "$$log"; echo "--- $$name (build) ---"; tail -n 200 "$$log"; exit 1; }; \
							file "build/$$name" | grep -q "ELF" || { echo "STATUS: fail (not ELF)" >> "$$log"; echo "FAIL: $$name (No ELF)" | tee -a "$$log"; exit 1; }; \
						elif [ "$$name" = "test_debug_panic" ]; then \
							$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build "$$t" --backend native --debug -o "build/$$name" $(CODESIGN_ARG) $(GC_ARG) >> "$$log" 2>&1 || { echo "STATUS: fail (build)" >> "$$log"; echo "--- $$name (build) ---"; tail -n 200 "$$log"; exit 1; }; \
							outf="build/$$name.out"; \
							set +e; $(RUN_WITH_TIMEOUT) "./build/$$name" > "$$outf" 2>&1; rc=$$?; set -e; \
							cat "$$outf" >> "$$log"; \
							if [ "$$rc" -eq 0 ]; then \
								echo "STATUS: fail (expected panic)" >> "$$log"; \
								echo "FAIL: $$name (Expected panic)" | tee -a "$$log"; \
								exit 1; \
							elif [ "$$rc" -eq 124 ]; then \
								echo "STATUS: fail (timeout)" >> "$$log"; \
								echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)" | tee -a "$$log"; \
								exit 1; \
							fi; \
							grep -q "Runtime Panic" "$$outf" || { echo "STATUS: fail (missing panic header)" >> "$$log"; echo "FAIL: $$name (Missing panic header)" | tee -a "$$log"; exit 1; }; \
							grep -q "__top_level__" "$$outf" || { echo "STATUS: fail (missing __top_level__)" >> "$$log"; echo "FAIL: $$name (Missing __top_level__ in stack trace)" | tee -a "$$log"; exit 1; }; \
							! grep -q "__oren_fnwrap_crash_me (pc=" "$$outf" || { echo "STATUS: fail (host frame mislabeled)" >> "$$log"; echo "FAIL: $$name (Host frame mis-labeled as program symbol)" | tee -a "$$log"; exit 1; }; \
						elif [ "$$name" = "test_no_gc_mode" ]; then \
							$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build "$$t" --backend native --debug --no-gc -o "build/$$name" $(CODESIGN_ARG) >> "$$log" 2>&1 || { echo "STATUS: fail (build)" >> "$$log"; echo "--- $$name (build) ---"; tail -n 200 "$$log"; exit 1; }; \
							$(RUN_WITH_TIMEOUT) "./build/$$name" >> "$$log" 2>&1 || { echo "STATUS: fail (run)" >> "$$log"; echo "--- $$name (run) ---"; tail -n 200 "$$log"; exit 1; }; \
						else \
							$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build "$$t" --backend native --debug -o "build/$$name" $(CODESIGN_ARG) $(GC_ARG) >> "$$log" 2>&1 || { echo "STATUS: fail (build)" >> "$$log"; echo "--- $$name (build) ---"; tail -n 200 "$$log"; exit 1; }; \
							$(RUN_WITH_TIMEOUT) "./build/$$name" >> "$$log" 2>&1 || { echo "STATUS: fail (run)" >> "$$log"; echo "--- $$name (run) ---"; tail -n 200 "$$log"; exit 1; }; \
						fi; \
						echo "STATUS: pass" >> "$$log"' sh; \
				xargs_rc="$$?"; \
				set -e; \
				if [ "$$xargs_rc" -ne 0 ]; then \
					echo "=== Native Tests (All) FAILED ==="; \
					echo "Hint: failing logs are under build/logs/native_all_*.log"; \
					for t in tests/native/*.oren; do \
						name=$$(basename "$$t" .oren); \
						if [ "$(OREN_TEST_TARGET)" != "windows" ]; then \
							case "$$name" in ffi_windows_*) continue ;; esac; \
						fi; \
						if [ "$(OREN_TEST_TARGET)" != "linux" ]; then \
							case "$$name" in ffi_linux_*) continue ;; esac; \
						fi; \
						log="build/logs/native_all_$${name}.log"; \
						grep -q "^STATUS: pass$$" "$$log" 2>/dev/null || { \
							echo "--- $$name (log tail) ---"; \
							test -f "$$log" && tail -n 120 "$$log" || echo "(missing log: $$log)"; \
							echo ""; \
						}; \
					done; \
					exit "$$xargs_rc"; \
				fi; \
				echo "Native tests OK"

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./$(OREN_STAGE2_BIN) build tests/native/func.oren --backend native $(HOST_PLATFORM_ARG) -o build/func_stage2$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/func_stage2$(EXE_EXT) || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- AVM (experimental) ---

AVM_C_SRC := $(shell find lib/avm -maxdepth 1 -name '*.c' -print | sort) third_party/tweetnacl/tweetnacl.c
AVM_INC := $(shell find lib/avm -maxdepth 1 \( -name '*.h' -o -name '*.inc' \) -print | sort)

build/avm_root_pubkey.inc: tools/gen_avm_root_pubkeys_inc.sh
	@mkdir -p build
	@tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc

ifeq ($(HOST_IS_WINDOWS),1)
avm: $(AVM_BIN)
endif

$(AVM_BIN): $(AVM_C_SRC) $(AVM_INC) build/avm_root_pubkey.inc
	@echo "Building AVM..."
	@mkdir -p build
	@if [ "$(HOST_IS_WINDOWS)" = "1" ]; then \
		ccbase="$$(basename "$(AVM_CC)")"; \
		case "$$ccbase" in \
			cl|cl.exe|clang-cl|clang-cl.exe) \
				echo "ERROR: AVM build expects a gcc/clang-style compiler, not '$$ccbase'."; \
				echo "       Hint: install MSYS2 clang or llvm-mingw and run: make avm AVM_CC=clang"; \
				exit 2; \
			;; \
		esac; \
	fi
	@$(AVM_CC) $(AVM_CFLAGS) $(AVM_DETERMINISM_CFLAGS) -I lib/avm -I build -o "$(AVM_BIN)" $(AVM_C_SRC)

.PHONY: libavm-ios libavm-ios-xcframework libavm-desktop libavm-macos libavm-linux-x64 libavm-windows-x64 verify-libavm-desktop verify-libavm-linux-x64 verify-libavm-windows-x64 verify-libavm-ios verify-compiler-in-avm-ios-chain verify-avm-stdlib-obc-surface verify-libavm-ios-full-chain capture-ios-live-3d-performance
libavm-ios libavm-ios-xcframework: ; @./scripts/build_libavm_ios.sh

libavm-desktop libavm-macos: ; @./scripts/build_libavm_desktop.sh

libavm-linux-x64: ; @./scripts/build_libavm_linux_x64.sh

libavm-windows-x64: ; @./scripts/build_libavm_windows_x64.sh

verify-libavm-desktop: oren avm ; @./scripts/verify_libavm_desktop.sh

verify-libavm-linux-x64: oren avm ; @./scripts/verify_libavm_linux_x64.sh

verify-libavm-windows-x64: oren avm ; @./scripts/verify_libavm_windows_x64.sh

verify-libavm-ios: oren avm
	@./scripts/verify_libavm_ios.sh
	@python3 ./scripts/verify_ios_sdk_embed_byte_ownership.py
	@python3 ./scripts/verify_ios_compilerkit_source_bytes.py
	@python3 ./scripts/verify_ios_package_store_bytes.py
	@python3 ./scripts/verify_ios_sdk_network_sessions.py
	@python3 ./scripts/verify_ios_gfx_input_events.py
	@python3 ./scripts/verify_ios_graphics_frame.py
	@python3 ./scripts/verify_ios_graphics_geometry.py
	@python3 ./scripts/verify_ios_graphics_resources.py
	@python3 ./scripts/verify_ios_gfx_retained_painter.py
	@python3 ./scripts/verify_ios_metal_vertex_uploads.py
	@./scripts/verify_compiler_in_avm_ios_chain.sh
	@./scripts/verify_avm_stdlib_obc_surface.sh

verify-compiler-in-avm-ios-chain: oren avm ; @./scripts/verify_compiler_in_avm_ios_chain.sh

verify-avm-stdlib-obc-surface: oren avm ; @./scripts/verify_avm_stdlib_obc_surface.sh

verify-libavm-ios-full-chain: verify-libavm-ios

capture-ios-live-3d-performance: oren avm ; @./scripts/capture_ios_live_3d_performance.sh
