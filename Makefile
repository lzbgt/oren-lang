.PHONY: all clean bootstrap test verify stage1 stage2 avm examples-test

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
TIMEOUT_BIN := $(shell command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")
ifneq ($(strip $(TIMEOUT_BIN)),)
  RUN_WITH_TIMEOUT = $(TIMEOUT_BIN) $(TEST_TIMEOUT_SECS)
else
  RUN_WITH_TIMEOUT =
endif

# Optional GC toggle (set NO_GC=1 or OREN_NO_GC in env to compile with -DOREN_NO_GC)
GC_ARG :=
ifeq ($(NO_GC),1)
  GC_ARG := --no-gc
else ifneq ($(OREN_NO_GC),)
  GC_ARG := --no-gc
endif

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
	@mkdir -p build
	@# Native Backend Tests
	@set -e; for t in tests/native/*.oren; do \
		name=$$(basename $$t .oren); \
		echo "Testing $$name..."; \
		if [ "$$name" = "linux_hello" ]; then \
			./oren build $$t --backend native -o build/$$name --target linux $(CODESIGN_ARG) $(GC_ARG); \
			file build/$$name | grep -q "ELF" || { echo "FAIL: $$name (No ELF)"; exit 1; }; \
		elif [ "$$name" = "test_debug_panic" ]; then \
			./oren build $$t --backend native -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			set +e; $(RUN_WITH_TIMEOUT) ./build/$$name; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected panic)"; exit 1; \
			elif [ $$rc -eq 124 ]; then \
				echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; exit 1; \
			fi; \
		else \
			./oren build $$t --backend native -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			$(RUN_WITH_TIMEOUT) ./build/$$name || { echo "FAIL: $$name (Exit code $$?)"; exit 1; }; \
		fi \
	done
	@# Module Tests (C Backend)
	@echo "Testing Module System..."
	@./oren build tests/modules/test_shapes.oren --backend c -o build/test_shapes $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_shapes || (echo "FAIL: test_shapes"; exit 1)
	@./oren build tests/modules/test_spawn.oren --backend c -o build/test_spawn $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_spawn || (echo "FAIL: test_spawn"; exit 1)
	@./oren build tests/modules/test_read_bytes.oren --backend c -o build/test_read_bytes $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_read_bytes || (echo "FAIL: test_read_bytes"; exit 1)
	@./oren build tests/modules/test_gc_threads.oren --backend c -o build/test_gc_threads $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_gc_threads || (echo "FAIL: test_gc_threads"; exit 1)
	@./oren build tests/modules/test_gc_stack_roots.oren --backend c -o build/test_gc_stack_roots $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_gc_stack_roots || (echo "FAIL: test_gc_stack_roots"; exit 1)
	@./oren build tests/modules/test_result.oren --backend c -o build/test_result $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/test_result || (echo "FAIL: test_result"; exit 1)
	@# AVM Tests (Bytecode backend + interpreter)
	@echo "Testing AVM..."
	@$(MAKE) avm >/dev/null
	@set -e; for t in tests/avm/*.oren; do \
		name=$$(basename $$t .oren); \
		echo "Testing avm $$name..."; \
		if [ "$$name" = "test_multiverse_avm_domain" ]; then \
			./oren build tests/avm/fixtures/multiverse_child.oren --backend bytecode -o build/multiverse_child.obc $(GC_ARG); \
		fi; \
		./oren build $$t --backend bytecode -o build/$$name.obc $(GC_ARG); \
		if [ "$$name" = "test_budget_gas" ]; then \
			set +e; AVM_GAS=20000 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected budget abort)"; exit 1; \
			fi; \
		elif [ "$$name" = "test_budget_mem" ]; then \
			set +e; AVM_MEM_BYTES=4096 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected mem budget abort)"; exit 1; \
			fi; \
		elif [ "$$name" = "test_budget_io_fs" ]; then \
			set +e; AVM_IO_BYTES=64 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc; rc=$$?; set -e; \
			if [ $$rc -eq 0 ]; then \
				echo "FAIL: $$name (Expected io budget abort)"; exit 1; \
			elif [ $$rc -eq 124 ]; then \
				echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)"; exit 1; \
			fi; \
		elif [ "$$name" = "test_policy_scan" ]; then \
			set +e; out=$$($(RUN_WITH_TIMEOUT) ./avm --print-policy build/$$name.obc); rc=$$?; set -e; \
			if [ $$rc -ne 0 ]; then \
				echo "FAIL: $$name (--print-policy exit code $$rc)"; echo "$$out"; exit 1; \
			fi; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=1 op=1$$" || { echo "FAIL: $$name (Missing FS write_file op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=5 op=0$$" || { echo "FAIL: $$name (Missing PROC system op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "^POLICY_USED_OP domain=7 op=0$$" || { echo "FAIL: $$name (Missing ENV env op)"; echo "$$out"; exit 1; }; \
			echo "$$out" | grep -q "RUN_POLICY_SCAN_SHOULD_NOT_EXECUTE" && { echo "FAIL: $$name (--print-policy executed bytecode)"; echo "$$out"; exit 1; }; \
		elif [ "$$name" = "test_capability_deny_fs" ]; then \
			AVM_ALLOW_DOMAINS=0 $(RUN_WITH_TIMEOUT) ./avm build/$$name.obc || { echo "FAIL: $$name"; exit 1; }; \
		elif [ "$$name" = "test_snapshot_resume" ]; then \
			snap=build/$$name.avms; rm -f $$snap; \
			set +e; $(RUN_WITH_TIMEOUT) ./avm --step-limit 2000 --snapshot-out $$snap build/$$name.obc; rc=$$?; set -e; \
			if [ $$rc -ne 2 ]; then \
				echo "FAIL: $$name (Expected pause exit code 2, got $$rc)"; exit 1; \
			fi; \
			$(RUN_WITH_TIMEOUT) ./avm --snapshot-in $$snap build/$$name.obc || { echo "FAIL: $$name (resume)"; exit 1; }; \
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
				$(RUN_WITH_TIMEOUT) ./avm build/$$name.obc || { echo "FAIL: $$name"; exit 1; }; \
			fi \
		done
	@echo "All Tests Passed."

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./oren_stage2 build tests/native/func.oren --backend native -o build/func_stage2 $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/func_stage2 || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- AVM (experimental) ---

avm: lib/avm/main.c lib/avm/avm.c lib/avm/avm.h lib/avm/sha256.c lib/avm/sha256.h
	@echo "Building AVM..."
	$(CC) -O2 -o avm lib/avm/main.c lib/avm/avm.c lib/avm/sha256.c

# --- Examples (verification) ---

examples-test: oren avm
	@echo "=== Running Examples ==="
	@mkdir -p build
	@# 1) C backend hello + modules + threading
	@./oren build examples/hello_c.oren --backend c -o build/ex_hello_c $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_hello_c
	@./oren build examples/module_app.oren --backend c -o build/ex_module_app $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_module_app
	@./oren build examples/spawn_c.oren --backend c -o build/ex_spawn_c $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_spawn_c
	@# 2) Native backend GC + FFI
	@./oren build examples/gc_native.oren --backend native -o build/ex_gc_native $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_gc_native
	@./oren build examples/ffi_test.oren --backend native -o build/ex_ffi_puts $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts >/dev/null
	@# 3) Native dylib export + header + scan + link
	@./oren build examples/libmath.oren --backend native --lib -o build/libmath.dylib $(CODESIGN_ARG) $(GC_ARG) --metadata
	@test -f build/libmath.h
	@$(RUN_WITH_TIMEOUT) ./oren scan build/libmath.dylib >/dev/null
	@./oren build examples/ffi_from_libmath.oren --backend native --link build/libmath.dylib -o build/ex_ffi_from_libmath $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_ffi_from_libmath
	@# 4) Bytecode + AVM
	@./oren build examples/hello.oren --backend bytecode -o build/ex_hello.obc
	@$(RUN_WITH_TIMEOUT) ./avm build/ex_hello.obc >/dev/null
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
