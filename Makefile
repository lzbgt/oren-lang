.PHONY: all clean bootstrap test test-inner verify stage1 stage2 avm examples-test examples-test-inner

# Default target: Build Stage 1 compiler
all: oren

# Platform settings
UNAME_S := $(shell uname -s)
CC ?= cc
CODESIGN_IDENTITY ?= Developer ID Application: Zongbao Lu (US56HHF2Y4)
ifeq ($(UNAME_S),Darwin)
  CODESIGN_ARG := --codesign "$(CODESIGN_IDENTITY)"
else
  CODESIGN_ARG :=
endif

# Test runner settings
TEST_TIMEOUT_SECS ?= 10
# Build steps can legitimately take longer than executing tests, especially when
# the C backend invokes `cc`/`ld`/codesign. Still, they must not hang forever in
# rolling mode.
BUILD_TIMEOUT_SECS ?= 120
# Global failsafe for the whole suite. Per-test timeouts should catch most hangs;
# this prevents the entire run from blocking forever if something slips through.
SUITE_TIMEOUT_SECS ?= 900
TIMEOUT_KILL_SECS ?= 2
TIMEOUT_BIN := $(shell command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")
ifneq ($(strip $(TIMEOUT_BIN)),)
  RUN_WITH_TIMEOUT = $(TIMEOUT_BIN) -k $(TIMEOUT_KILL_SECS) $(TEST_TIMEOUT_SECS)
  RUN_BUILD_WITH_TIMEOUT = $(TIMEOUT_BIN) -k $(TIMEOUT_KILL_SECS) $(BUILD_TIMEOUT_SECS)
  RUN_SUITE_WITH_TIMEOUT = $(TIMEOUT_BIN) -k $(TIMEOUT_KILL_SECS) $(SUITE_TIMEOUT_SECS)
else
  RUN_WITH_TIMEOUT =
  RUN_BUILD_WITH_TIMEOUT =
  RUN_SUITE_WITH_TIMEOUT =
endif

# Output control:
# - Default is quiet to avoid huge logs during rolling development.
# - Set TEST_QUIET=0 to print full compiler/runtime output.
TEST_QUIET ?= 1

# Optional GC toggle (set NO_GC=1 or OREN_NO_GC in env to compile with -DOREN_NO_GC)
GC_ARG :=
ifeq ($(NO_GC),1)
  GC_ARG := --no-gc
else ifneq ($(OREN_NO_GC),)
  GC_ARG := --no-gc
endif

# AVM test selection:
# - Default: curated smoke list for iteration velocity.
# - Override for full coverage: `make test AVM_TESTS="tests/avm/*.oren"`
AVM_TESTS ?= \
	tests/avm/test_smoke_suite.oren \
	tests/avm/test_policy_scan.oren \
	tests/avm/test_job_scan.oren \
	tests/avm/test_snapshot_resume.oren \
	tests/avm/test_time_rng_deterministic.oren \
	tests/avm/test_time_rng_record_replay_mem.oren \
	tests/avm/test_budget_gas.oren \
	tests/avm/test_budget_timeout.oren \
	tests/avm/test_vfs_no_host_fs.oren \
	tests/avm/test_vproc_no_host_proc.oren \
	tests/avm/test_vnet_no_host_net.oren

# Source files
OREN_SRC := oren.oren
$(OREN_SRC): ;
GO_SRC := $(shell find cmd pkg -name "*.go")
OREN_OREN_SRC := $(shell find lib -name "*.oren")

# --- Build Stages ---

# Stage 0: Bootstrap Compiler (Go)
oren_bootstrap: $(GO_SRC)
	@echo "Building Stage 0 (Bootstrap)..."
	go build -o oren_bootstrap ./cmd/oren

# Stage 1: Self-Hosted Compiler (Built by Stage 0)
oren: oren_bootstrap $(OREN_SRC) $(OREN_OREN_SRC)
	@echo "Building Stage 1 (Oren)..."
	./oren_bootstrap build $(OREN_SRC) $(CODESIGN_ARG) $(GC_ARG)

# Stage 2: Self-Hosted Compiler (Built by Stage 1)
oren_stage2: oren $(OREN_SRC) $(OREN_OREN_SRC)
	@echo "Building Stage 2 (Self-Hosted)..."
	./oren build $(OREN_SRC) -o oren_stage2 $(CODESIGN_ARG) $(GC_ARG)

# Aliases
bootstrap: oren_bootstrap
stage1: oren
stage2: oren_stage2

# --- Testing & Verification ---

# Run all tests using Stage 1 compiler
test: oren
	@echo "=== Running Tests ==="
	@# Hard requirement in rolling mode: tests must not be able to hang forever.
	@[ -n "$(TIMEOUT_BIN)" ] || { echo "ERROR: 'timeout' not found. Install coreutils (macOS: brew install coreutils) or provide gtimeout/timeout in PATH."; exit 2; }
	@# Global failsafe: wrap the entire suite.
	@$(RUN_SUITE_WITH_TIMEOUT) $(MAKE) test-inner || { \
		rc=$$?; \
		if [ $$rc -eq 124 ]; then echo "FAIL: test suite timed out after $(SUITE_TIMEOUT_SECS)s"; fi; \
		exit $$rc; \
	}

test-inner: oren
	@mkdir -p build
	@mkdir -p build/logs
	@# Native Backend Tests
	@# Keep `make test` fast by running a curated list; `make test-native-all` runs the full glob.
	@NATIVE_TESTS="\
tests/native/add.oren \
tests/native/atomic.oren \
tests/native/cmp.oren \
tests/native/exit.oren \
tests/native/ffi.oren \
tests/native/func.oren \
tests/native/if.oren \
tests/native/linux_hello.oren \
tests/native/malloc.oren \
tests/native/nested_struct.oren \
tests/native/print.oren \
tests/native/print_value.oren \
tests/native/shapes.oren \
tests/native/simd.oren \
tests/native/test_args.oren \
tests/native/test_atomics.oren \
tests/native/test_attributes_fields_params.oren \
tests/native/test_attributes_noop.oren \
tests/native/test_block.oren \
tests/native/test_call_stack_args.oren \
tests/native/test_channel.oren \
tests/native/test_comments.oren \
tests/native/test_debug_panic.oren \
tests/native/test_endian_casts.oren \
tests/native/test_env_execve_getenv.oren \
tests/native/test_float_manual.oren \
tests/native/test_gc.oren \
tests/native/test_gc_reuse_tracking.oren \
tests/native/test_getenv_malformed_key.oren \
tests/native/test_indexing.oren \
tests/native/test_list_append_grow.oren \
tests/native/test_nested_containers.oren \
tests/native/test_net_suite.oren \
tests/native/test_smoke_suite.oren \
tests/native/test_no_gc_mode.oren \
tests/native/test_pipe_direct.oren \
tests/native/test_plus_string.oren \
tests/native/test_read_bytes.oren \
tests/native/test_simple.oren \
tests/native/test_system_timeout.oren \
tests/native/test_time_suite.oren \
tests/native/test_tid.oren \
tests/native/test_write_string.oren \
tests/native/var.oren \
tests/native/while.oren \
"; \
	set -e; pass=0; total=0; for t in $$NATIVE_TESTS; do \
		total=$$((total+1)); \
		name=$$(basename $$t .oren); \
		log=build/logs/native_$$name.log; \
		if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing $$name..."; fi; \
		if [ "$$name" = "linux_hello" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name --target linux $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build)"; cat $$log; exit 1; }; \
			file build/$$name | grep -q "ELF" || { echo "FAIL: $$name (No ELF)"; exit 1; }; \
		elif [ "$$name" = "test_debug_panic" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build)"; cat $$log; exit 1; }; \
			outf=build/$$name.out; \
			set +e; $(RUN_WITH_TIMEOUT) ./build/$$name > $$outf 2>&1; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected panic)"; cat $$outf; exit 1; \
			elif [ $$rc -eq 124 ]; then \
				echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; cat $$outf; exit 1; \
			fi; \
			grep -q "Runtime Panic" $$outf || { echo "FAIL: $$name (Missing panic header)"; cat $$outf; exit 1; }; \
			grep -q "__top_level__" $$outf || { echo "FAIL: $$name (Missing __top_level__ in stack trace)"; cat $$outf; exit 1; }; \
			! grep -q "__oren_fnwrap_crash_me (pc=" $$outf || { echo "FAIL: $$name (Host frame mis-labeled as program symbol)"; cat $$outf; exit 1; }; \
		elif [ "$$name" = "test_no_gc_mode" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug --no-gc -o build/$$name $(CODESIGN_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build)"; cat $$log; exit 1; }; \
			$(RUN_WITH_TIMEOUT) ./build/$$name > $$log 2>&1 || { echo "FAIL: $$name (run exit code $$?)"; cat $$log; exit 1; }; \
		else \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build)"; cat $$log; exit 1; }; \
			$(RUN_WITH_TIMEOUT) ./build/$$name > $$log 2>&1 || { echo "FAIL: $$name (run exit code $$?)"; cat $$log; exit 1; }; \
			fi; \
			pass=$$((pass+1)); \
		done; \
		if [ "$(TEST_QUIET)" = "1" ]; then echo "$$pass/$$total native tests passed"; fi
	@# Compiler CLI / parser regression: strict attribute mode must be testable and deterministic.
	@if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing strict attributes..."; fi
	@log=build/logs/strict_attrs_ok.log; OREN_STRICT_ATTRS=1 OREN_ATTR_ALLOW_PREFIXES="myorg." $(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/native/fixtures/strict_attrs_ok.oren --backend native -o build/strict_attrs_ok $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1 || { echo "FAIL: strict_attrs_ok (build)"; cat $$log; exit 1; }
	@log=build/logs/strict_attrs_bad.log; set +e; OREN_STRICT_ATTRS=1 $(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/native/fixtures/strict_attrs_bad.oren --backend native -o build/strict_attrs_bad $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1; rc=$$?; set -e; \
		if [ $$rc -eq 0 ]; then \
			echo "FAIL: strict_attrs_bad (Expected compile error in strict mode)"; cat $$log; exit 1; \
		elif [ $$rc -eq 124 ]; then \
			echo "FAIL: strict_attrs_bad (Timed out after $(BUILD_TIMEOUT_SECS)s)"; cat $$log; exit 1; \
		fi
	@# Struct fields are immutable: `obj.field = v` must be rejected at parse-time (portable across backends).
	@if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing struct field assignment rejection..."; fi
	@log=build/logs/struct_field_assign_bad.log; set +e; $(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/native/fixtures/struct_field_assign_bad.oren --backend native -o build/struct_field_assign_bad $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1; rc=$$?; set -e; \
		if [ $$rc -eq 0 ]; then \
			echo "FAIL: struct_field_assign_bad (Expected compile error: struct fields immutable)"; cat $$log; exit 1; \
		elif [ $$rc -eq 124 ]; then \
			echo "FAIL: struct_field_assign_bad (Timed out after $(BUILD_TIMEOUT_SECS)s)"; cat $$log; exit 1; \
		fi
	@# Module Tests (C Backend)
	@if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing Module System..."; fi
	@pass=0; total=0; \
		for t in tests/modules/test_shapes.oren tests/modules/test_spawn.oren tests/modules/test_read_bytes.oren tests/modules/test_function_values.oren tests/modules/test_lambda_closure.oren tests/modules/test_lambda_multiline.oren tests/modules/test_endian_casts.oren tests/modules/test_gc_threads.oren tests/modules/test_gc_stack_roots.oren tests/modules/test_result.oren; do \
			total=$$((total+1)); \
			name=$$(basename $$t .oren); \
			log=build/logs/mod_$$name.log; \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend c -o build/$$name $(CODESIGN_ARG) $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build)"; cat $$log; exit 1; }; \
			$(RUN_WITH_TIMEOUT) ./build/$$name > $$log 2>&1 || { echo "FAIL: $$name (run exit code $$?)"; cat $$log; exit 1; }; \
			pass=$$((pass+1)); \
		done; \
		if [ "$(TEST_QUIET)" = "1" ]; then echo "$$pass/$$total module tests passed"; fi
	@# AVM Tests (Bytecode backend + interpreter)
	@if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing AVM..."; fi
	@$(RUN_BUILD_WITH_TIMEOUT) $(MAKE) avm >/dev/null
	@set -e; pass=0; total=0; for t in $(AVM_TESTS); do \
			total=$$((total+1)); \
			name=$$(basename $$t .oren); \
			log=build/logs/avm_$$name.log; \
			if [ "$(TEST_QUIET)" = "0" ]; then echo "Testing avm $$name..."; fi; \
			if [ "$$name" = "test_multiverse_avm_domain" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/multiverse_child.oren --backend bytecode -o build/multiverse_child.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
			elif [ "$$name" = "test_multiverse_net_fixtures" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/multiverse_child_net.oren --backend bytecode -o build/multiverse_child_net.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
			elif [ "$$name" = "test_multiverse_proc_fixtures" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/multiverse_child_proc.oren --backend bytecode -o build/multiverse_child_proc.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
			elif [ "$$name" = "test_multiverse_vfs_fixtures" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/multiverse_child_vfs.oren --backend bytecode -o build/multiverse_child_vfs.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
				elif [ "$$name" = "test_map_key_order" ]; then \
					$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/map_order_child_ab.oren --backend bytecode -o build/map_order_child_ab.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
					$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/map_order_child_cba.oren --backend bytecode -o build/map_order_child_cba.obc $(GC_ARG) >> $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
				elif [ "$$name" = "test_map_key_types" ]; then \
					$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/map_key_types_child1.oren --backend bytecode -o build/map_key_types_child1.obc $(GC_ARG) > $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
					$(RUN_BUILD_WITH_TIMEOUT) ./oren build tests/avm/fixtures/map_key_types_child2.oren --backend bytecode -o build/map_key_types_child2.obc $(GC_ARG) >> $$log 2>&1 || { echo "FAIL: $$name (build fixture)"; cat $$log; exit 1; }; \
			fi; \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend bytecode -o build/$$name.obc $(GC_ARG) >> $$log 2>&1 || { echo "FAIL: $$name (bytecode build)"; cat $$log; exit 1; }; \
			if [ "$$name" = "test_budget_gas" ]; then \
				set +e; AVM_GAS=20000 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected budget abort)"; cat $$log; exit 1; \
				fi; \
			elif [ "$$name" = "test_budget_mem" ]; then \
				set +e; AVM_MEM_BYTES=4096 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected mem budget abort)"; cat $$log; exit 1; \
				fi; \
			elif [ "$$name" = "test_budget_timeout" ]; then \
				set +e; $(RUN_WITH_TIMEOUT) ./avm --timeout-ms 10 build/$$name.obc > $$log 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected timeout abort)"; cat $$log; exit 1; \
				elif [ $$rc -eq 124 ]; then \
					echo "FAIL: $$name (External timeout fired; expected AVM to abort first)"; cat $$log; exit 1; \
				fi; \
			elif [ "$$name" = "test_budget_io_fs" ]; then \
				set +e; AVM_IO_BYTES=64 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected io budget abort)"; cat $$log; exit 1; \
				elif [ $$rc -eq 124 ]; then \
					echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; cat $$log; exit 1; \
				fi; \
			elif [ "$$name" = "test_budget_log_mem" ]; then \
				rm -f build/avm_log_budget_should_not_write.txt; \
				set +e; AVM_RECORD_MEM=1 AVM_LOG_BYTES=64 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected log budget abort)"; cat $$log; exit 1; \
				elif [ $$rc -eq 124 ]; then \
					echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; cat $$log; exit 1; \
				fi; \
				if [ -f build/avm_log_budget_should_not_write.txt ]; then \
					echo "FAIL: $$name (Host FS effect executed despite log budget abort)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_policy_scan" ]; then \
				set +e; out=$$($(RUN_WITH_TIMEOUT) ./avm --print-policy build/$$name.obc); rc=$$?; set -e; \
				if [ $$rc -ne 0 ]; then \
					echo "FAIL: $$name (--print-policy exit code $$rc)"; echo "$$out"; exit 1; \
				fi; \
				dout=$$($(RUN_WITH_TIMEOUT) ./avm --disasm build/$$name.obc); \
			echo "$$dout" | grep -q "CALL_NATIVE " && { echo "FAIL: $$name (Bytecode contains legacy CALL_NATIVE opcode)"; echo "$$dout"; exit 1; }; \
			set +e; dj=$$($(RUN_WITH_TIMEOUT) ./avm --disasm-json build/$$name.obc); drc=$$?; set -e; \
			if [ $$drc -ne 0 ]; then \
				echo "FAIL: $$name (--disasm-json exit code $$drc)"; echo "$$dj"; exit 1; \
			fi; \
			echo "$$dj" | grep -q "\"schema\":\"avm.disasm.v1\"" || { echo "FAIL: $$name (disasm json missing schema)"; echo "$$dj"; exit 1; }; \
			echo "$$dj" | grep -q "\"code_len\":" || { echo "FAIL: $$name (disasm json missing code_len)"; echo "$$dj"; exit 1; }; \
			echo "$$dj" | grep -q "RUN_POLICY_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--disasm-json executed bytecode)"; echo "$$dj"; exit 1; }; \
			ph=$$(echo "$$out" | awk '/^POLICY_HASH_SHA256 /{print $$2; exit 0}'); \
			echo "$$ph" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid POLICY_HASH_SHA256)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=1 op=1$$" || { echo "FAIL: $$name (Missing FS write_file op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=5 op=0$$" || { echo "FAIL: $$name (Missing PROC system op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=7 op=0$$" || { echo "FAIL: $$name (Missing ENV env op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "RUN_POLICY_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--print-policy executed bytecode)"; echo "$$out"; exit 1; }; \
			set +e; iout=$$($(RUN_WITH_TIMEOUT) ./avm --inspect-json build/$$name.obc); irc=$$?; set -e; \
			if [ $$irc -ne 0 ]; then \
				echo "FAIL: $$name (--inspect-json exit code $$irc)"; echo "$$iout"; exit 1; \
			fi; \
			echo "$$iout" | grep -q "\"schema\":\"avm.obc.v1\"" || { echo "FAIL: $$name (inspect json missing schema)"; echo "$$iout"; exit 1; }; \
			echo "$$iout" | grep -q "\"program_hash_sha256\":\"" || { echo "FAIL: $$name (inspect json missing program_hash_sha256)"; echo "$$iout"; exit 1; }; \
			echo "$$iout" | grep -q "\"code_len\":" || { echo "FAIL: $$name (inspect json missing code_len)"; echo "$$iout"; exit 1; }; \
			echo "$$iout" | grep -q "RUN_POLICY_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--inspect-json executed bytecode)"; echo "$$iout"; exit 1; }; \
			set +e; outj=$$($(RUN_WITH_TIMEOUT) ./avm --print-policy-json build/$$name.obc); rcj=$$?; set -e; \
			if [ $$rcj -ne 0 ]; then \
				echo "FAIL: $$name (--print-policy-json exit code $$rcj)"; echo "$$outj"; exit 1; \
			fi; \
			echo "$$outj" | grep -q "\"schema\":\"avm.policy.v1\"" || { echo "FAIL: $$name (JSON missing schema)"; echo "$$outj"; exit 1; }; \
			echo "$$outj" | grep -q "\"policy_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing policy_hash_sha256)"; echo "$$outj"; exit 1; }; \
			echo "$$outj" | grep -q "\"domain\":1" || { echo "FAIL: $$name (JSON missing domain=1)"; echo "$$outj"; exit 1; }; \
			echo "$$outj" | grep -q "\"domain\":5" || { echo "FAIL: $$name (JSON missing domain=5)"; echo "$$outj"; exit 1; }; \
			echo "$$outj" | grep -q "\"domain\":7" || { echo "FAIL: $$name (JSON missing domain=7)"; echo "$$outj"; exit 1; }; \
			echo "$$outj" | grep -q "RUN_POLICY_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--print-policy-json executed bytecode)"; echo "$$outj"; exit 1; }; \
			elif [ "$$name" = "test_job_scan" ]; then \
			rm -f build/avm_job_scan_should_not_write.txt build/avm_job_scan_should_not_write2.txt; \
			set +e; jout=$$($(RUN_WITH_TIMEOUT) ./avm --print-job build/$$name.obc); rc=$$?; set -e; \
			if [ $$rc -ne 0 ]; then \
				echo "FAIL: $$name (--print-job exit code $$rc)"; echo "$$jout"; exit 1; \
			fi; \
			dout=$$($(RUN_WITH_TIMEOUT) ./avm --disasm build/$$name.obc); \
			echo "$$dout" | grep -q "CALL_NATIVE " && { echo "FAIL: $$name (Bytecode contains legacy CALL_NATIVE opcode)"; echo "$$dout"; exit 1; }; \
			jh=$$(echo "$$jout" | awk '/^JOB_HASH_SHA256 /{print $$2; exit 0}'); \
			ph=$$(echo "$$jout" | awk '/^POLICY_HASH_SHA256 /{print $$2; exit 0}'); \
			ih=$$(echo "$$jout" | awk '/^INPUT_HASH_SHA256 /{print $$2; exit 0}'); \
			prh=$$(echo "$$jout" | awk '/^PROGRAM_HASH_SHA256 /{print $$2; exit 0}'); \
			ch=$$(echo "$$jout" | awk '/^EXEC_HASH_SHA256 /{print $$2; exit 0}'); \
			echo "$$jh" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid JOB_HASH_SHA256)"; echo "$$jout"; exit 1; }; \
			echo "$$ph" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid POLICY_HASH_SHA256)"; echo "$$jout"; exit 1; }; \
			echo "$$ih" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid INPUT_HASH_SHA256)"; echo "$$jout"; exit 1; }; \
			echo "$$prh" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid PROGRAM_HASH_SHA256)"; echo "$$jout"; exit 1; }; \
			echo "$$ch" | grep -Eq "^[0-9a-f]{64}$$" || { echo "FAIL: $$name (Missing/invalid EXEC_HASH_SHA256)"; echo "$$jout"; exit 1; }; \
			echo "$$jout" | grep -q "^POLICY_USED_OP domain=1 op=1$$" || { echo "FAIL: $$name (Missing FS write_file op)"; echo "$$jout"; exit 1; }; \
			echo "$$jout" | grep -q "^POLICY_USED_OP domain=5 op=0$$" || { echo "FAIL: $$name (Missing PROC system op)"; echo "$$jout"; exit 1; }; \
			echo "$$jout" | grep -q "^POLICY_USED_OP domain=7 op=0$$" || { echo "FAIL: $$name (Missing ENV env op)"; echo "$$jout"; exit 1; }; \
			echo "$$jout" | grep -q "RUN_JOB_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--print-job executed bytecode)"; echo "$$jout"; exit 1; }; \
			set +e; joutj=$$($(RUN_WITH_TIMEOUT) ./avm --print-job-json build/$$name.obc); rcj=$$?; set -e; \
			if [ $$rcj -ne 0 ]; then \
				echo "FAIL: $$name (--print-job-json exit code $$rcj)"; echo "$$joutj"; exit 1; \
			fi; \
				echo "$$joutj" | grep -q "\"schema\":\"avm.job.v7\"" || { echo "FAIL: $$name (JSON missing schema)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "\"job_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing job_hash_sha256)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "\"input_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing input_hash_sha256)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "\"program_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing program_hash_sha256)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "\"exec_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing exec_hash_sha256)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "\"policy_hash_sha256\":\"" || { echo "FAIL: $$name (JSON missing policy_hash_sha256)"; echo "$$joutj"; exit 1; }; \
			echo "$$joutj" | grep -q "RUN_JOB_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--print-job-json executed bytecode)"; echo "$$joutj"; exit 1; }; \
				if [ -f build/avm_job_scan_should_not_write.txt ] || [ -f build/avm_job_scan_should_not_write2.txt ]; then \
					echo "FAIL: $$name (Host effects executed during print-job)"; exit 1; \
				fi; \
				elif [ "$$name" = "test_vfs_no_host_fs" ]; then \
					rm -f build/avm_vfs_should_not_write.bin; \
					$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,1,6" --fs-allow-prefixes "build/" --fs-backend vfs build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (vfs run)"; cat $$log; exit 1; }; \
					if [ -f build/avm_vfs_should_not_write.bin ]; then \
						echo "FAIL: $$name (VFS touched host filesystem)"; exit 1; \
					fi; \
				elif [ "$$name" = "test_vproc_no_host_proc" ]; then \
					rm -f build/avm_vproc_should_not_touch.txt; \
					$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,5,6" --proc-backend vproc --proc-exit-code 0 build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (vproc run)"; cat $$log; exit 1; }; \
					if [ -f build/avm_vproc_should_not_touch.txt ]; then \
						echo "FAIL: $$name (VPROC touched host filesystem via subprocess)"; exit 1; \
					fi; \
				elif [ "$$name" = "test_vproc_fixtures" ]; then \
					hex="41564d505243303101000000070000006563686f20686900000000"; \
					$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,5,6" --proc-backend vproc --proc-exit-code 7 --proc-fixtures-hex "$$hex" build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (vproc fixtures run)"; cat $$log; exit 1; }; \
				elif [ "$$name" = "test_vnet_no_host_net" ]; then \
					hex="41564d4e45543031010000000100000075020000006f6b"; \
					$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,4,6" --net-backend vnet --net-fixtures-hex "$$hex" build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (vnet run)"; cat $$log; exit 1; }; \
				elif [ "$$name" = "test_capsule_defaults" ]; then \
					rm -f build/avm_capsule_should_not_write.txt build/avm_capsule_should_not_write2.txt; \
					$(RUN_WITH_TIMEOUT) ./avm --capsule build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (capsule)"; cat $$log; exit 1; }; \
					if [ -f build/avm_capsule_should_not_write.txt ] || [ -f build/avm_capsule_should_not_write2.txt ]; then \
						echo "FAIL: $$name (Capsule touched host filesystem)"; exit 1; \
					fi; \
			elif [ "$$name" = "test_capsule_allow_fs" ]; then \
				rm -f build/avm_capsule_allow_fs.txt; \
				$(RUN_WITH_TIMEOUT) ./avm --capsule --allow-domains "0,1,6" --fs-allow-prefixes "build/" --fs-backend host build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (capsule allow fs)"; cat $$log; exit 1; }; \
				if [ ! -f build/avm_capsule_allow_fs.txt ]; then \
					echo "FAIL: $$name (Expected file not created)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_capability_deny_fs" ]; then \
				AVM_ALLOW_DOMAINS=0 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name"; cat $$log; exit 1; }; \
			elif [ "$$name" = "test_snapshot_resume" ]; then \
				snap=build/$$name.avms; rm -f $$snap; \
				set +e; pout=$$($(RUN_WITH_TIMEOUT) ./avm --step-limit 2000 --print-pause-json --snapshot-out $$snap build/$$name.obc); rc=$$?; set -e; \
				if [ $$rc -ne 2 ]; then \
					echo "FAIL: $$name (Expected pause exit code 2, got $$rc)"; echo "$$pout"; exit 1; \
				fi; \
				echo "$$pout" | grep -q "\"schema\":\"avm.pause.v1\"" || { echo "FAIL: $$name (Missing pause json schema)"; echo "$$pout"; exit 1; }; \
				echo "$$pout" | grep -q "\"paused\":true" || { echo "FAIL: $$name (Expected paused=true)"; echo "$$pout"; exit 1; }; \
				$(RUN_WITH_TIMEOUT) ./avm --snapshot-in $$snap build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name (resume)"; cat $$log; exit 1; }; \
				elif [ "$$name" = "test_state_hash_repeat" ]; then \
					h1=$$($(RUN_WITH_TIMEOUT) ./avm --print-state-hash build/$$name.obc | awk '/^STATE_HASH /{print $$2; exit 0}'); \
				h2=$$($(RUN_WITH_TIMEOUT) ./avm --print-state-hash build/$$name.obc | awk '/^STATE_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing STATE_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_result_hash_repeat" ]; then \
				h1=$$($(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				h2=$$($(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_trace_hash_repeat" ]; then \
				h1=$$($(RUN_WITH_TIMEOUT) ./avm --print-trace-hash build/$$name.obc | awk '/^TRACE_HASH /{print $$2; exit 0}'); \
				h2=$$($(RUN_WITH_TIMEOUT) ./avm --print-trace-hash build/$$name.obc | awk '/^TRACE_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing TRACE_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
				elif [ "$$name" = "test_trace_bytes_repeat" ]; then \
					b1=$$($(RUN_WITH_TIMEOUT) ./avm --print-trace-bytes-hex build/$$name.obc | awk '/^TRACE_BYTES_HEX /{print $$2; exit 0}'); \
					b2=$$($(RUN_WITH_TIMEOUT) ./avm --print-trace-bytes-hex build/$$name.obc | awk '/^TRACE_BYTES_HEX /{print $$2; exit 0}'); \
					if [ "$$b1" = "" ] || [ "$$b2" = "" ]; then \
						echo "FAIL: $$name (Missing TRACE_BYTES_HEX)"; exit 1; \
					fi; \
					if [ "$$b1" != "$$b2" ]; then \
						echo "FAIL: $$name (Trace bytes mismatch)"; exit 1; \
					fi; \
				elif [ "$$name" = "test_trace_bytes_truncate" ]; then \
					out=$$(AVM_TRACE_BYTES=8 $(RUN_WITH_TIMEOUT) ./avm --print-trace-bytes-hex build/$$name.obc); \
					tr=$$(echo "$$out" | awk '/^TRACE_TRUNCATED /{print $$2; exit 0}'); \
					hex=$$(echo "$$out" | awk '/^TRACE_BYTES_HEX /{print $$2; exit 0}'); \
					if [ "$$tr" != "1" ]; then \
						echo "FAIL: $$name (Expected TRACE_TRUNCATED 1, got $$tr)"; exit 1; \
					fi; \
					if [ "$$hex" != "41564d5452433032" ]; then \
						echo "FAIL: $$name (Expected header-only trace bytes, got $$hex)"; exit 1; \
					fi; \
				elif [ "$$name" = "test_trace_bytes_mem_budget" ]; then \
					out=$$(AVM_MEM_BYTES=1024 AVM_TRACE_BYTES=1048576 $(RUN_WITH_TIMEOUT) ./avm --print-trace-bytes-hex build/$$name.obc); \
					tr=$$(echo "$$out" | awk '/^TRACE_TRUNCATED /{print $$2; exit 0}'); \
					if [ "$$tr" != "0" ]; then \
						echo "FAIL: $$name (Unexpected TRACE_TRUNCATED $$tr)"; exit 1; \
					fi; \
				elif [ "$$name" = "test_trace_events_native" ]; then \
					hex=$$($(RUN_WITH_TIMEOUT) ./avm --print-trace-bytes-hex build/$$name.obc | awk '/^TRACE_BYTES_HEX /{print $$2; exit 0}'); \
					python3 tools/trace_decode_check.py "$$hex" || { echo "FAIL: $$name (trace decode)"; exit 1; }; \
				elif [ "$$name" = "test_record_replay_fs" ]; then \
					log=build/$$name.avmlog; rm -f $$log; rm -f build/avm_rr_fs.txt; \
				h1=$$(AVM_RECORD_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				rm -f build/avm_rr_fs.txt; \
				h2=$$(AVM_REPLAY_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
				if [ -f build/avm_rr_fs.txt ]; then \
					echo "FAIL: $$name (Replay touched filesystem unexpectedly)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_record_replay_proc" ]; then \
				log=build/$$name.avmlog; rm -f $$log; rm -f build/avm_rr_proc.txt; \
				h1=$$(AVM_RECORD_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ ! -f build/avm_rr_proc.txt ]; then \
					echo "FAIL: $$name (Record did not execute system command)"; exit 1; \
				fi; \
				rm -f build/avm_rr_proc.txt; \
				h2=$$(AVM_REPLAY_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
				if [ -f build/avm_rr_proc.txt ]; then \
					echo "FAIL: $$name (Replay executed system command unexpectedly)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_record_replay_exit" ]; then \
				log=build/$$name.avmlog; rm -f $$log; \
				h1=$$(AVM_RECORD_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				h2=$$(AVM_REPLAY_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_record_replay_env" ]; then \
				log=build/$$name.avmlog; rm -f $$log; \
				h1=$$(AVM_RR_ENV_KEY=hello AVM_RECORD_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				h2=$$(AVM_REPLAY_LOG=$$log $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_record_replay_mem_fs" ]; then \
				rm -f build/avm_rr_mem_fs.txt; \
				out=$$(AVM_RECORD_MEM=1 $(RUN_WITH_TIMEOUT) ./avm --print-result-hash --print-record-log-hex build/$$name.obc); \
				h1=$$(echo "$$out" | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				loghex=$$(echo "$$out" | awk '/^RECORD_LOG_HEX /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$loghex" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH or RECORD_LOG_HEX)"; echo "$$out"; exit 1; \
				fi; \
				rm -f build/avm_rr_mem_fs.txt; \
				out2=$$(AVM_REPLAY_LOG_HEX=$$loghex $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc); \
				h2=$$(echo "$$out2" | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; echo "$$out2"; exit 1; \
				fi; \
				if [ -f build/avm_rr_mem_fs.txt ]; then \
					echo "FAIL: $$name (Replay touched filesystem unexpectedly)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_time_rng_deterministic" ]; then \
				h1=$$(AVM_DETERMINISTIC=1 AVM_TIME_START_NS=100 AVM_TIME_STEP_NS=7 AVM_RNG_SEED=123 $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				h2=$$(AVM_DETERMINISTIC=1 AVM_TIME_START_NS=100 AVM_TIME_STEP_NS=7 AVM_RNG_SEED=123 $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Deterministic hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
			elif [ "$$name" = "test_time_rng_record_replay_mem" ]; then \
				out=$$(AVM_RECORD_MEM=1 $(RUN_WITH_TIMEOUT) ./avm --print-result-hash --print-record-log-hex build/$$name.obc); \
				h1=$$(echo "$$out" | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				loghex=$$(echo "$$out" | awk '/^RECORD_LOG_HEX /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$loghex" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH or RECORD_LOG_HEX)"; echo "$$out"; exit 1; \
				fi; \
				out2=$$(AVM_REPLAY_LOG_HEX=$$loghex $(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc); \
				h2=$$(echo "$$out2" | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Record/replay hash mismatch $$h1 != $$h2)"; echo "$$out2"; exit 1; \
				fi; \
			elif [ "$$name" = "test_multiverse_avm_domain" ]; then \
				h1=$$($(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				h2=$$($(RUN_WITH_TIMEOUT) ./avm --print-result-hash build/$$name.obc | awk '/^RESULT_HASH /{print $$2; exit 0}'); \
				if [ "$$h1" = "" ] || [ "$$h2" = "" ]; then \
					echo "FAIL: $$name (Missing RESULT_HASH)"; exit 1; \
				fi; \
				if [ "$$h1" != "$$h2" ]; then \
					echo "FAIL: $$name (Deterministic hash mismatch $$h1 != $$h2)"; exit 1; \
				fi; \
				else \
					$(RUN_WITH_TIMEOUT) ./avm build/$$name.obc > $$log 2>&1 || { echo "FAIL: $$name"; cat $$log; exit 1; }; \
				fi; \
				pass=$$((pass+1)); \
			done; \
			if [ "$(TEST_QUIET)" = "1" ]; then echo "$$pass/$$total avm tests passed"; fi
	@echo "All Tests Passed."

test-native-all: oren
	@echo "=== Native Tests (All) ==="
	@mkdir -p build
	@set -e; for t in tests/native/*.oren; do \
		name=$$(basename $$t .oren); \
		echo "Testing $$name..."; \
		if [ "$$name" = "linux_hello" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name --target linux $(CODESIGN_ARG) $(GC_ARG); \
			file build/$$name | grep -q "ELF" || { echo "FAIL: $$name (No ELF)"; exit 1; }; \
		elif [ "$$name" = "test_debug_panic" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			outf=build/$$name.out; \
			set +e; $(RUN_WITH_TIMEOUT) ./build/$$name > $$outf 2>&1; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected panic)"; exit 1; \
			elif [ $$rc -eq 124 ]; then \
				echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; exit 1; \
			fi; \
			grep -q "Runtime Panic" $$outf || { echo "FAIL: $$name (Missing panic header)"; cat $$outf; exit 1; }; \
			grep -q "__top_level__" $$outf || { echo "FAIL: $$name (Missing __top_level__ in stack trace)"; cat $$outf; exit 1; }; \
			! grep -q "__oren_fnwrap_crash_me (pc=" $$outf || { echo "FAIL: $$name (Host frame mis-labeled as program symbol)"; cat $$outf; exit 1; }; \
		elif [ "$$name" = "test_no_gc_mode" ]; then \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug --no-gc -o build/$$name $(CODESIGN_ARG); \
			$(RUN_WITH_TIMEOUT) ./build/$$name || { echo "FAIL: $$name (Exit code $$?)"; exit 1; }; \
		else \
			$(RUN_BUILD_WITH_TIMEOUT) ./oren build $$t --backend native --debug -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			$(RUN_WITH_TIMEOUT) ./build/$$name || { echo "FAIL: $$name (Exit code $$?)"; exit 1; }; \
		fi \
	done

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./oren_stage2 build tests/native/func.oren --backend native -o build/func_stage2 $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/func_stage2 || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- AVM (experimental) ---

avm: lib/avm/main.c lib/avm/avm.h lib/avm/avm_internal.h lib/avm/sha256.c lib/avm/sha256.h \
     lib/avm/avm_alloc.c lib/avm/avm_budget.c lib/avm/avm_bytes_mem.c lib/avm/avm_containers.c \
     lib/avm/avm_errors.c lib/avm/avm_fixtures.c lib/avm/avm_host.c lib/avm/avm_native.c \
     lib/avm/avm_state.c lib/avm/avm_trace.c lib/avm/avm_vm.c
	@echo "Building AVM..."
	$(CC) -O2 -o avm lib/avm/main.c lib/avm/avm_alloc.c lib/avm/avm_budget.c lib/avm/avm_bytes_mem.c \
		lib/avm/avm_containers.c lib/avm/avm_errors.c lib/avm/avm_fixtures.c lib/avm/avm_host.c \
		lib/avm/avm_native.c lib/avm/avm_state.c lib/avm/avm_trace.c lib/avm/avm_vm.c lib/avm/sha256.c

# --- Examples (verification) ---

examples-test: oren avm
	@echo "=== Running Examples ==="
	@# Examples are not allowed to hang (rolling mode). Require timeout tooling.
	@[ -n "$(TIMEOUT_BIN)" ] || { echo "ERROR: 'timeout' not found. Install coreutils (macOS: brew install coreutils) or provide gtimeout/timeout in PATH."; exit 2; }
	@# Global failsafe: wrap the entire examples suite too.
	@$(RUN_SUITE_WITH_TIMEOUT) $(MAKE) examples-test-inner || { \
		rc=$$?; \
		if [ $$rc -eq 124 ]; then echo "FAIL: examples suite timed out after $(SUITE_TIMEOUT_SECS)s"; fi; \
		exit $$rc; \
	}

examples-test-inner: oren avm
	@mkdir -p build
	@# 1) C backend hello + modules + threading
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/hello_c.oren --backend c -o build/ex_hello_c $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_hello_c
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/module_app.oren --backend c -o build/ex_module_app $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_module_app
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/spawn_c.oren --backend c -o build/ex_spawn_c $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_spawn_c
	@# 2) Native backend GC + FFI
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/gc_native.oren --backend native -o build/ex_gc_native $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_gc_native
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/ffi_test.oren --backend native -o build/ex_ffi_puts $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts >/dev/null
	@# 3) Native dylib export + header + scan + link
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/libmath.oren --backend native --lib -o build/libmath.dylib $(CODESIGN_ARG) $(GC_ARG) --metadata
	@test -f build/libmath.h
	@$(RUN_WITH_TIMEOUT) ./oren scan build/libmath.dylib >/dev/null
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/ffi_from_libmath.oren --backend native --link build/libmath.dylib -o build/ex_ffi_from_libmath $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_ffi_from_libmath
	@# 4) Bytecode + AVM
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/hello.oren --backend bytecode -o build/ex_hello.obc
	@$(RUN_WITH_TIMEOUT) ./avm build/ex_hello.obc >/dev/null
	@# 5) AVM Virtual backends demos (VFS / VPROC / VNET)
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/avm_vfs_demo.oren --backend bytecode -o build/ex_avm_vfs_demo.obc
	@rm -f build/ex_avm_vfs_demo.bin
	@$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,1,6" --fs-allow-prefixes "build/" --fs-backend vfs build/ex_avm_vfs_demo.obc
	@test ! -f build/ex_avm_vfs_demo.bin
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/avm_vproc_demo.oren --backend bytecode -o build/ex_avm_vproc_demo.obc
	@rm -f build/ex_avm_vproc_should_not_touch.txt
	@$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,5,6" --proc-backend vproc --proc-exit-code 0 build/ex_avm_vproc_demo.obc
	@test ! -f build/ex_avm_vproc_should_not_touch.txt
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/avm_vnet_demo.oren --backend bytecode -o build/ex_avm_vnet_demo.obc
	@hex="41564d4e45543031010000000100000075020000006f6b"; \
		$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,4,6" --net-backend vnet --net-fixtures-hex "$$hex" build/ex_avm_vnet_demo.obc
	@# 6) AVM multiverse demo (parent runs child with VirtualNET fixtures)
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/avm_fixtures/multiverse_child_net.oren --backend bytecode -o build/ex_multiverse_child_net.obc
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/avm_multiverse_net_demo.oren --backend bytecode -o build/ex_avm_multiverse_net_demo.obc
	@$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,1,8,6" --fs-allow-prefixes "build/" --fs-backend host build/ex_avm_multiverse_net_demo.obc >/dev/null
	@echo "Examples OK"

# --- Cleanup ---

clean:
	@echo "Cleaning workspace..."
	rm -rf build/ *.dSYM verify_full.sh run_tests.sh
	rm -f oren_bootstrap oren oren_stage2 oren_stage3 avm
	rm -f *.oren.c *.obc *.otool *.dylib *.so
	@# Remove local test binaries (keep .oren sources)
	@find tests/native -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
	@find tests/modules -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
