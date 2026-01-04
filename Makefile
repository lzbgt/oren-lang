.PHONY: all clean bootstrap test verify stage1 stage2 examples-test examples-test-inner
.PHONY: test-native-quick test-native-quick-stage2 verify-native-quick
.PHONY: verify-native-x64-compile
.PHONY: bench-native-compile
.PHONY: rtobj-seed

# Default target: Build Stage 1 compiler
all: oren

# Platform settings
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
CC ?= cc
CODESIGN_IDENTITY ?= -
MACOS_SYSTEM_PATH_PREFIX := /usr/bin:/bin:/usr/sbin:/sbin
MACOS_CODESIGN_BIN := /usr/bin/codesign
ifeq ($(UNAME_S),Darwin)
  ifeq ($(strip $(OREN_SKIP_CODESIGN)),1)
    $(error OREN_SKIP_CODESIGN=1 is not supported on macOS; unsigned native outputs may be killed by the OS)
  endif
  CODESIGN_ARG := --codesign "$(CODESIGN_IDENTITY)"
else
  CODESIGN_ARG :=
endif

# Host platform (preferred native-backend selector).
#
# Keep this in Makefile (not in compiler runtime detection) so:
# - `make verify` remains robust even if the native runtime cannot (or should not) shell out to `uname`
# - core gates are deterministic and don't depend on external commands
HOST_PLATFORM :=
ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),arm64)
    HOST_PLATFORM := arm64-macos
  else ifeq ($(UNAME_M),aarch64)
    HOST_PLATFORM := arm64-macos
  else ifeq ($(UNAME_M),x86_64)
    HOST_PLATFORM := x64-macos
  endif
else ifeq ($(UNAME_S),Linux)
  ifeq ($(UNAME_M),arm64)
    HOST_PLATFORM := arm64-linux
  else ifeq ($(UNAME_M),aarch64)
    HOST_PLATFORM := arm64-linux
  else ifeq ($(UNAME_M),x86_64)
    HOST_PLATFORM := x64-linux
  else ifeq ($(UNAME_M),amd64)
    HOST_PLATFORM := x64-linux
  endif
endif

HOST_PLATFORM_ARG :=
ifneq ($(strip $(HOST_PLATFORM)),)
  HOST_PLATFORM_ARG := --platform $(HOST_PLATFORM)
endif

# AVM C build flags (rolling):
# - Keep AVM deterministic across platforms (no fast-math, no FP contraction/FMA drift).
# - Keep this narrow: AVM consensus semantics depend on stable float behavior.
AVM_CFLAGS ?= -O2
AVM_DETERMINISM_CFLAGS ?= -fno-fast-math -ffp-contract=off

# Test target selection (affects native backend + curated runner).
# - On macOS hosts, run native backend tests as `--target macos`.
# - On Linux hosts, run native backend tests as `--target linux`.
OREN_TEST_TARGET ?=
ifeq ($(strip $(OREN_TEST_TARGET)),)
  ifeq ($(UNAME_S),Darwin)
    OREN_TEST_TARGET := macos
  else ifeq ($(UNAME_S),Linux)
    OREN_TEST_TARGET := linux
  else
    OREN_TEST_TARGET := macos
  endif
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

# Parser parallelism (self-hosting speed knob).
# Used by the compiler include-aggregator fast path (stage2 hotspot).
OREN_PARSE_JOBS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

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
		tests/avm/test_closure_fn_values.oren \
		tests/avm/test_policy_scan.oren \
		tests/avm/test_job_scan.oren \
		tests/avm/test_snapshot_resume.oren \
		tests/avm/test_multiverse_invalid_obc.oren \
		tests/avm/test_time_rng_deterministic.oren \
		tests/avm/test_time_rng_record_replay_mem.oren \
		tests/avm/test_budget_gas.oren \
		tests/avm/test_budget_timeout.oren \
		tests/avm/test_call_depth_limit.oren \
		tests/avm/test_arith_invalid.oren \
		tests/avm/test_vfs_no_host_fs.oren \
		tests/avm/test_vproc_no_host_proc.oren \
		tests/avm/test_vnet_no_host_net.oren \
		tests/avm/test_switch.oren

# Source files
OREN_SRC := oren.oren
$(OREN_SRC): ;
GO_SRC := $(shell find cmd pkg -name "*.go")
OREN_OREN_SRC := $(shell find lib -name "*.oren")
OREN_RUNTIME_INC := $(shell find lib/runtime -name "*.inc")

# --- Build Stages ---

# GC tuning for self-hosting builds (rolling):
# - Keep stage2 within time/RSS budgets by avoiding full-stack scans.
# - Override per-host/CI as needed.
OREN_GC_STACK_SCAN_LIMIT_BYTES ?= 8388608

# Stage 0: Bootstrap Compiler (Go)
oren_bootstrap: $(GO_SRC)
	@echo "Building Stage 0 (Bootstrap)..."
	@go build -o oren_bootstrap ./cmd/oren

# Go-based metadata-to-artifacts tool (OpenAPI, etc).
oredoc: $(GO_SRC)
	@echo "Building oredoc..."
	@go build -o oredoc ./cmd/oredoc

# Go-based signing utility (used by AVM signing fixtures).
orensign: $(GO_SRC)
	@echo "Building orensign..."
	@go build -o orensign ./cmd/orensign

# Stage 1: Self-Hosted Compiler (Built by Stage 0)
oren: oren_bootstrap $(OREN_SRC) $(OREN_OREN_SRC) $(OREN_RUNTIME_INC)
	@echo "Building Stage 1 (Oren)..."
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" ./oren_bootstrap build $(OREN_SRC) $(CODESIGN_ARG) $(GC_ARG); \
	else \
		./oren_bootstrap build $(OREN_SRC) $(CODESIGN_ARG) $(GC_ARG); \
	fi

#
# Stage 2: Self-Hosted Compiler (Built by Stage 1)
#
# Rolling policy:
# - Default `make stage2` must build stage2 via the **native backend** on arm64-macos too.
# - If you need the old C-backend bootstrap for bring-up, use:
#     make stage2 OREN_STAGE2_BACKEND=c
OREN_STAGE2_BACKEND ?= native
oren_stage2: oren $(OREN_SRC) $(OREN_OREN_SRC) $(OREN_RUNTIME_INC)
	@echo "Building Stage 2 (Self-Hosted)..."
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
				arch=$$(uname -m); \
				if [ "$$arch" = "arm64" ] || [ "$$arch" = "aarch64" ]; then \
					PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./oren build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug -o oren_stage2 $(CODESIGN_ARG) $(GC_ARG)'; \
				else \
					PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_RAW_PTR_SCAN=0 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./oren build $(OREN_SRC) --backend native $(HOST_PLATFORM_ARG) --no-debug -o oren_stage2 $(CODESIGN_ARG) $(GC_ARG)'; \
				fi; \
			else \
					arch=$$(uname -m); \
					if [ "$$arch" = "arm64" ] || [ "$$arch" = "aarch64" ]; then \
						OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./oren build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug -o oren_stage2 $(CODESIGN_ARG) $(GC_ARG)'; \
					else \
						OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_RAW_PTR_SCAN=0 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./oren build $(OREN_SRC) --backend native $(HOST_PLATFORM_ARG) --no-debug -o oren_stage2 $(CODESIGN_ARG) $(GC_ARG)'; \
					fi; \
				fi

# Aliases
bootstrap: oren_bootstrap
stage1: oren
# `make stage2` is the primary rolling path; keep it fast on first-run by also ensuring
# a rtobj seed exists (best-effort, cheap copy).
stage2: oren_stage2 rtobj-seed

# Generate/update rtobj seed for the host platform (best-effort).
# This keeps first-run stage2-native builds fast even when the active rtobj cache dir is empty.
rtobj-seed: oren_stage2
	@if [ -n "$(HOST_PLATFORM)" ]; then \
		./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler ./oren_stage2 --no-debug || true; \
	else \
		echo "NOTE: host platform unknown; skipping rtobj seed"; \
	fi

# --- Testing & Verification ---

# Fast native smoke (stage1): build+run one self-contained integration test.
test-native-quick: oren
	@./scripts/run_native_quick_integration.sh ./oren

# Fast native smoke (stage2): use stage2 compiler to build+run the same test.
test-native-quick-stage2: oren_stage2
	@./scripts/run_native_quick_integration.sh ./oren_stage2

# Convenience target: verify stage1 then stage2 on the native quick integration test.
verify-native-quick: test-native-quick test-native-quick-stage2
	@echo "verify-native-quick OK"

# Compile-only sanity gate for x64 targets (does not run artifacts).
verify-native-x64-compile: oren_stage2
	@./scripts/verify_native_x64_compile_only.sh

# Perf smoke: benchmark stage2 native "compile one file" (rtobj miss -> hit).
bench-native-compile: oren_stage2
	@./scripts/bench_native_compile_one_file.sh

# Default "test" is now native-only and quick (no external test runner).
test: test-native-quick

test-native-all: oren
	@echo "=== Native Tests (All) ==="
	@mkdir -p build
	@mkdir -p build/logs
	@echo "Native parallelism: set NATIVE_TEST_JOBS=... (default: 4)."
	@set -e; \
		jobs="$(strip $(NATIVE_TEST_JOBS))"; \
		if [ "$$jobs" = "" ]; then jobs=4; fi; \
		if [ "$$jobs" -lt 1 ]; then jobs=1; fi; \
		find tests/native -maxdepth 1 -name '*.oren' -print0 | \
		xargs -0 -n 1 -P "$$jobs" sh -c '\
			set -e; \
			t="$$1"; \
			name=$$(basename "$$t" .oren); \
			log="build/logs/native_all_$${name}.log"; \
			echo "Testing $$name..."; \
			if [ "$$name" = "linux_hello" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build "$$t" --backend native --debug -o "build/$$name" --target linux $(CODESIGN_ARG) $(GC_ARG) > "$$log" 2>&1 || { echo "--- $$name (build) ---"; cat "$$log"; exit 1; }; \
				file "build/$$name" | grep -q "ELF" || { echo "FAIL: $$name (No ELF)" | tee -a "$$log"; exit 1; }; \
			elif [ "$$name" = "test_debug_panic" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build "$$t" --backend native --debug -o "build/$$name" $(CODESIGN_ARG) $(GC_ARG) > "$$log" 2>&1 || { echo "--- $$name (build) ---"; cat "$$log"; exit 1; }; \
				outf="build/$$name.out"; \
				set +e; $(RUN_WITH_TIMEOUT) "./build/$$name" > "$$outf" 2>&1; rc=$$?; set -e; \
				if [ $$rc -eq 0 ]; then \
					echo "FAIL: $$name (Expected panic)" | tee -a "$$log"; cat "$$outf"; exit 1; \
				elif [ $$rc -eq 124 ]; then \
					echo "FAIL: $$name (Timed out after $(TEST_TIMEOUT_SECS)s)" | tee -a "$$log"; cat "$$outf"; exit 1; \
				fi; \
				grep -q "Runtime Panic" "$$outf" || { echo "FAIL: $$name (Missing panic header)" | tee -a "$$log"; cat "$$outf"; exit 1; }; \
				grep -q "__top_level__" "$$outf" || { echo "FAIL: $$name (Missing __top_level__ in stack trace)" | tee -a "$$log"; cat "$$outf"; exit 1; }; \
				! grep -q "__oren_fnwrap_crash_me (pc=" "$$outf" || { echo "FAIL: $$name (Host frame mis-labeled as program symbol)" | tee -a "$$log"; cat "$$outf"; exit 1; }; \
			elif [ "$$name" = "test_no_gc_mode" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build "$$t" --backend native --debug --no-gc -o "build/$$name" $(CODESIGN_ARG) > "$$log" 2>&1 || { echo "--- $$name (build) ---"; cat "$$log"; exit 1; }; \
				$(RUN_WITH_TIMEOUT) "./build/$$name" >> "$$log" 2>&1 || { echo "--- $$name (run) ---"; cat "$$log"; exit 1; }; \
			else \
				$(RUN_BUILD_WITH_TIMEOUT) ./oren build "$$t" --backend native --debug -o "build/$$name" $(CODESIGN_ARG) $(GC_ARG) > "$$log" 2>&1 || { echo "--- $$name (build) ---"; cat "$$log"; exit 1; }; \
				$(RUN_WITH_TIMEOUT) "./build/$$name" >> "$$log" 2>&1 || { echo "--- $$name (run) ---"; cat "$$log"; exit 1; }; \
			fi' sh

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./oren_stage2 build tests/native/func.oren --backend native $(HOST_PLATFORM_ARG) -o build/func_stage2 $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/func_stage2 || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- AVM (experimental) ---

AVM_C_SRC := $(shell find lib/avm -maxdepth 1 -name '*.c' -print | sort) third_party/tweetnacl/tweetnacl.c
AVM_INC := $(shell find lib/avm -maxdepth 1 -name '*.inc' -print | sort)

build/avm_root_pubkey.inc: tools/gen_avm_root_pubkeys_inc.sh
	@mkdir -p build
	@tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc

avm: $(AVM_C_SRC) $(AVM_INC) build/avm_root_pubkey.inc
	@echo "Building AVM..."
	@mkdir -p build
	@$(CC) $(AVM_CFLAGS) $(AVM_DETERMINISM_CFLAGS) -I lib/avm -I build -o avm $(AVM_C_SRC)

# --- Example Builds ---

examples-test: oren avm
	@echo "=== Running Examples ==="
	@# Prefer an outer suite timeout when `timeout`/`gtimeout` exists. If missing, proceed:
	@# example binaries are short-lived and the inner tooling has timeouts.
	@if [ -z "$(TIMEOUT_BIN)" ]; then \
		echo "WARN: 'timeout'/'gtimeout' not found; running without outer suite timeout."; \
	fi
	@# Global failsafe: wrap the entire suite.
	@$(RUN_SUITE_WITH_TIMEOUT) $(MAKE) examples-test-inner || { \
			rc=$$?; \
			if [ $$rc -eq 124 ]; then echo "FAIL: examples suite timed out after $(SUITE_TIMEOUT_SECS)s"; fi; \
			exit $$rc; \
		}

examples-test-inner: oren avm
	@mkdir -p build
	@# 1) Native hello world
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/hello.oren --backend native -o build/ex_hello_native $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_hello_native >/dev/null
	@# 1b) Native module import + stdlib import
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/module_app.oren --backend native -o build/ex_module_app_native $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_module_app_native >/dev/null
	@# 2) GC suite (native)
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/gc_test.oren --backend native -o build/ex_gc_native $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_gc_native
	@# 2b/3) Native FFI + dylib export (macOS only today)
	@# - macOS: FFI works (dyld binding + LC_LOAD_DYLIB)
	@# - Linux: ELF dynamic linking is not implemented in the native backend yet
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/ffi_test.oren --backend native -o build/ex_ffi_puts $(CODESIGN_ARG) $(GC_ARG); \
		$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts >/dev/null; \
		$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/libmath.oren --backend native --lib -o build/libmath.dylib $(CODESIGN_ARG) $(GC_ARG) --metadata; \
		test -f build/libmath.h; \
		$(RUN_WITH_TIMEOUT) ./oren scan build/libmath.dylib >/dev/null; \
		$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/ffi_from_libmath.oren --backend native --link build/libmath.dylib -o build/ex_ffi_from_libmath $(CODESIGN_ARG) $(GC_ARG); \
		$(RUN_WITH_TIMEOUT) ./build/ex_ffi_from_libmath; \
	else \
		echo "INFO: skipping macOS-only native FFI/dylib examples on $(UNAME_S)"; \
	fi
	@# 4) Bytecode + AVM
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/hello.oren --backend bytecode -o build/ex_hello.obc
	@$(RUN_WITH_TIMEOUT) ./avm build/ex_hello.obc >/dev/null
	@$(RUN_BUILD_WITH_TIMEOUT) ./oren build examples/module_app.oren --backend bytecode -o build/ex_module_app.obc
	@$(RUN_WITH_TIMEOUT) ./avm build/ex_module_app.obc >/dev/null
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
	@$(RUN_WITH_TIMEOUT) ./avm --deny-by-default --allow-domains "0,1,4,6,8" --fs-allow-prefixes "build/" --fs-backend host build/ex_avm_multiverse_net_demo.obc >/dev/null
	@echo "Examples OK"

# Verify `.obc` portability across AVM hosts (rolling).
# This is an integration-style gate and may use Docker + remote Win11+WSL2.
obc-portability: oren avm
	@tools/verify_obc_portability.sh

# --- Cleanup ---

clean:
	@echo "Cleaning workspace..."
	rm -rf build/ *.dSYM verify_full.sh run_tests.sh
	rm -f oren_bootstrap oren oren_stage2 oren_stage3 avm
	rm -f orensign
	rm -f *.oren.c *.obc *.otool *.dylib *.so
	@# Remove local test binaries (keep .oren sources)
	@find tests/native -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
	@find tests/modules -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
