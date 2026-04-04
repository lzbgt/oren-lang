.PHONY: all clean bootstrap test test-selfhost verify stage1 stage2 examples-test examples-test-inner
.PHONY: examples-cross-compile-smoke
.PHONY: test-native-quick test-native-quick-stage2 test-native-quick-flake-debug test-native-quick-green-cache-flake test-native-quick-gc-stw-focus-flake test-native-quick-green-tail-flake test-native-quick-green-join-waiters-stress-flake test-native-quick-stage2-flake-debug test-native-quick-arith-div0-flake test-native-capsule-smoke-stage2 verify-native-quick verify-native-quick-simd verify-green-world-lock-guarded verify-green-preworld-guarded verify-green-fairness-guarded verify-backend-parity verify-backend-parity-bytes verify-backend-parity-arith-panics verify-backend-parity-index-panics verify-runtime-robustness verify-simd-determinism verify-ui-smoke-macos verify-ui-smoke-windows verify-ui-smoke-linux readiness-report readiness-report-full readiness-report-minimal readiness-report-json readiness-report-index readiness-report-summary readiness-report-dashboard readiness-report-index-stats readiness-report-index-prune readiness-report-index-trim readiness-report-index-csv readiness-report-index-query readiness-report-index-rollup readiness-report-index-merge readiness-report-index-compact readiness-report-index-schema readiness-report-index-diff readiness-report-index-diff-summary readiness-report-index-gate readiness-report-index-lint readiness-report-index-split readiness-report-index-latest readiness-report-index-trend readiness-report-index-profiles readiness-report-index-tags readiness-report-index-audit readiness-report-index-audit-trend readiness-report-collect readiness-report-collect-list readiness-report-collect-pack readiness-report-sanitize readiness-pipeline status-snapshot status-snapshot-diff status-faq status-faq-diff status-matrix status-matrix-diff status-markdown verify-readiness-report verify-readiness-report-summary verify-readiness-report-dashboard verify-readiness-report-index-tools verify-readiness-report-index-csv verify-readiness-report-index-query-rollup verify-readiness-report-index-merge-compact verify-readiness-report-index-schema verify-readiness-report-index-diff verify-readiness-report-index-diff-summary verify-readiness-report-index-gate verify-readiness-report-index-lint verify-readiness-report-index-split verify-readiness-report-index-trim verify-readiness-report-index-latest verify-readiness-report-index-trend verify-readiness-report-index-profiles verify-readiness-report-index-tags verify-readiness-report-index-audit verify-readiness-report-index-audit-trend verify-readiness-report-collect verify-readiness-report-collect-list verify-readiness-report-collect-pack verify-readiness-report-sanitize verify-readiness-pipeline verify-status-snapshot verify-status-snapshot-diff verify-status-faq verify-status-faq-diff verify-status-matrix verify-status-matrix-diff verify-status-markdown benchmarks benchmarks-update
.PHONY: verify-native-x64-compile
.PHONY: verify-native-x64-selfhost-compile
.PHONY: verify-x64-linux-qemu
.PHONY: verify-x64-linux-qemu-net
.PHONY: verify-x64-linux-qemu-tls
.PHONY: setup-x64-linux-qemu
.PHONY: verify-native-matrix verify-native-matrix-skip-remote verify-native-net verify-native-net-skip-remote verify-selfhost-x64 verify-stage0-win verify-tier1
.PHONY: verify-stage2-win
.PHONY: build-orenui-win32
.PHONY: bench-native-compile
.PHONY: perf-guard-native-hit
.PHONY: perf-gate-native perf-gate-native-read-split perf-gate-native-steady perf-gate-list-int perf-gate-list-int-read-split perf-gate-list-int-steady perf-probe-list-int-unsafe perf-probe-list-int-packed-bridge perf-probe-list-int-slot-direct perf-probe-arm64-fast-loop-tick-masks perf-probe-arm64-fast-loop-tick-masks-steady perf-probe-arm64-fast-dot-single-pair-cursor-regs perf-probe-arm64-fast-dot-unroll2 perf-probe-arm64-fast-dot-dual-accum perf-probe-arm64-fast-dot-madd-exact perf-probe-arm64-native-hot-loop-disasm perf-probe-arm64-dot-acceptance perf-probe-native-gate-stability perf-smoke-native-fast-loops perf-debug-native-benchmark perf-smoke-list-int perf-smoke-list-int-packed-bridge perf-smoke-list-int-slot-direct perf-prebuild-list-int-packed-bridge perf-prebuild-dot-product-int-packed-bridge perf-prebuild-list-int-slot-direct perf-prebuild-dot-product-int-slot-direct verify-native-core-packed-bridge verify-native-slot-direct verify-native-list-int-fast-lowering
.PHONY: rtobj-seed
.PHONY: rtobj-seed-x64
.PHONY: astbin-seed

# Default target: Build Stage 1 compiler
all: oren

# Platform settings
UNAME_S := $(shell uname -s 2>/dev/null || echo "")
UNAME_M := $(shell uname -m 2>/dev/null || echo "")
CC ?= cc
CODESIGN_IDENTITY ?= -
MACOS_SYSTEM_PATH_PREFIX := /usr/bin:/bin:/usr/sbin:/sbin
MACOS_CODESIGN_BIN := /usr/bin/codesign

# GNU make on Windows can run under MSYS2/Git Bash/Cygwin, in which case `uname`
# is available but does not return `Linux`/`Darwin`. Detect Windows hosts via the
# common env + uname prefixes.
HOST_IS_WINDOWS :=
ifeq ($(OS),Windows_NT)
  HOST_IS_WINDOWS := 1
else ifneq ($(SystemRoot),)
  HOST_IS_WINDOWS := 1
else ifneq ($(WINDIR),)
  HOST_IS_WINDOWS := 1
else ifneq ($(COMSPEC),)
  HOST_IS_WINDOWS := 1
else ifneq ($(PATHEXT),)
  HOST_IS_WINDOWS := 1
else ifneq ($(PROCESSOR_ARCHITECTURE),)
  HOST_IS_WINDOWS := 1
else ifneq (,$(findstring MINGW,$(UNAME_S)))
  HOST_IS_WINDOWS := 1
else ifneq (,$(findstring MSYS,$(UNAME_S)))
  HOST_IS_WINDOWS := 1
else ifneq (,$(findstring CYGWIN,$(UNAME_S)))
  HOST_IS_WINDOWS := 1
endif

# Windows executable suffix:
# - Go and MSVC emit `.exe` outputs on Windows hosts.
# - Make rules should name the actual output file so incremental builds work.
EXE_EXT :=
ifeq ($(HOST_IS_WINDOWS),1)
  EXE_EXT := .exe
endif

BOOTSTRAP_BIN := oren_bootstrap$(EXE_EXT)
OREN_BIN := oren$(EXE_EXT)
OREN_STAGE2_BIN := oren_stage2$(EXE_EXT)
OREDOC_BIN := oredoc$(EXE_EXT)
ORENSIGN_BIN := orensign$(EXE_EXT)
AVM_BIN := avm$(EXE_EXT)
COMPILER_BUILD_LOCK := ./scripts/with_build_lock.sh build/locks/compiler-build.lock
OREN_RUNTIME_ROBUSTNESS_RUNS ?= 1
OREN_RUNTIME_ROBUSTNESS_COMPILER ?= ./$(OREN_STAGE2_BIN)
OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS ?=
OREN_RUNTIME_ROBUSTNESS_C_RUNS ?=
OREN_RUNTIME_ROBUSTNESS_C_FIXTURES ?=
OREN_RUNTIME_ROBUSTNESS_TRACE_ENV ?=
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
else ifeq ($(HOST_IS_WINDOWS),1)
  # Rolling intent: x64 Windows is Tier‑1. (arm64 Windows is not supported yet.)
  ifeq ($(UNAME_M),x86_64)
    HOST_PLATFORM := x64-windows
  else ifeq ($(UNAME_M),amd64)
    HOST_PLATFORM := x64-windows
  else ifeq ($(PROCESSOR_ARCHITECTURE),AMD64)
    HOST_PLATFORM := x64-windows
  endif
endif

HOST_PLATFORM_ARG :=
ifneq ($(strip $(HOST_PLATFORM)),)
  HOST_PLATFORM_ARG := --platform $(HOST_PLATFORM)
endif

# AVM C build flags (rolling):
# - Keep AVM deterministic across platforms (no fast-math, no FP contraction/FMA drift).
# - Keep this narrow: AVM consensus semantics depend on stable float behavior.
AVM_CFLAGS ?= -O3
AVM_DETERMINISM_CFLAGS ?= -fno-fast-math -ffp-contract=off
# AVM is a portable C program. Keep its toolchain independent from the stage0/stage1
# bring-up toolchain (which is MSVC on Windows by default).
#
# - On Unix-like hosts, `cc` is usually clang/gcc and works out of the box.
# - On Windows hosts, `cc` may not exist; set `AVM_CC=clang` (MSYS2) or another
#   gcc/clang-style compiler for AVM only.
AVM_CC ?= cc

# Test target selection (affects native backend + curated runner).
# - On macOS hosts, run native backend tests as `--target macos`.
# - On Linux hosts, run native backend tests as `--target linux`.
OREN_TEST_TARGET ?=
ifeq ($(strip $(OREN_TEST_TARGET)),)
  ifeq ($(UNAME_S),Darwin)
    OREN_TEST_TARGET := macos
  else ifeq ($(UNAME_S),Linux)
    OREN_TEST_TARGET := linux
  else ifeq ($(HOST_IS_WINDOWS),1)
    OREN_TEST_TARGET := windows
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

# Stage0 (Go bootstrap) uses the C backend to build stage1.
# - On Windows hosts, prefer MSVC `cl.exe` for stage1 bring-up (rolling goal).
OREN_BOOTSTRAP_CC ?=
ifeq ($(strip $(OREN_BOOTSTRAP_CC)),)
  ifeq ($(HOST_IS_WINDOWS),1)
    # Prefer explicit `cl.exe` (MSVC) for Windows host bring-up.
    # Stage0 auto-configures the VS environment via vswhere.exe + VsDevCmd/vcvars when `--cc cl{.exe}` is selected.
    OREN_BOOTSTRAP_CC := cl.exe
  else
    OREN_BOOTSTRAP_CC := $(CC)
  endif
endif
BOOTSTRAP_CC_ARG :=
ifneq ($(strip $(OREN_BOOTSTRAP_CC)),)
  BOOTSTRAP_CC_ARG := --cc $(OREN_BOOTSTRAP_CC)
endif

# Stage0 target OS selection (rolling):
# The stage0 bootstrap compiler defaults to `--target macos`, so make should explicitly
# set `--target` on non-macOS hosts to keep bootstrap behavior predictable.
OREN_BOOTSTRAP_TARGET ?=
ifeq ($(strip $(OREN_BOOTSTRAP_TARGET)),)
  ifeq ($(UNAME_S),Darwin)
    OREN_BOOTSTRAP_TARGET := macos
  else ifeq ($(UNAME_S),Linux)
    OREN_BOOTSTRAP_TARGET := linux
  else ifeq ($(HOST_IS_WINDOWS),1)
    OREN_BOOTSTRAP_TARGET := windows
  endif
endif
BOOTSTRAP_TARGET_ARG :=
ifneq ($(strip $(OREN_BOOTSTRAP_TARGET)),)
  BOOTSTRAP_TARGET_ARG := --target $(OREN_BOOTSTRAP_TARGET)
endif

# AVM test selection:
# - Default: curated smoke list for iteration velocity.
# - Override for full coverage: `make test-avm AVM_TESTS="tests/avm/*.oren"`
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
		tests/avm/test_switch.oren \
		tests/avm/test_list_sum_opcodes.oren \
		tests/avm/test_list_dot_opcodes.oren \
		tests/avm/test_list_int_basic.oren \
		tests/avm/test_list_freelist_env.oren \
		tests/avm/test_ui_color_v0.oren \
		tests/avm/test_ui_layout_v0.oren \
		tests/avm/test_ui_patch_v0.oren \
		tests/avm/test_ui_render_v0.oren \
		tests/avm/test_ui_raster_v0.oren \
		tests/avm/test_ui_ppm_v0.oren \
		tests/avm/test_ui_cmds_validate_v0.oren

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
ifeq ($(HOST_IS_WINDOWS),1)
oren_bootstrap: $(BOOTSTRAP_BIN)
endif

$(BOOTSTRAP_BIN): $(GO_SRC)
	@echo "Building Stage 0 (Bootstrap)..."
	@go build -o "$(BOOTSTRAP_BIN)" ./cmd/oren

# Go-based metadata-to-artifacts tool (OpenAPI, etc).
ifeq ($(HOST_IS_WINDOWS),1)
oredoc: $(OREDOC_BIN)
endif

$(OREDOC_BIN): $(GO_SRC)
	@echo "Building oredoc..."
	@go build -o "$(OREDOC_BIN)" ./cmd/oredoc

# Go-based signing utility (used by AVM signing fixtures).
ifeq ($(HOST_IS_WINDOWS),1)
orensign: $(ORENSIGN_BIN)
endif

$(ORENSIGN_BIN): $(GO_SRC)
	@echo "Building orensign..."
	@go build -o "$(ORENSIGN_BIN)" ./cmd/orensign

# Stage 1: Self-Hosted Compiler (Built by Stage 0)
ifeq ($(HOST_IS_WINDOWS),1)
oren: $(OREN_BIN)
endif

$(OREN_BIN): $(BOOTSTRAP_BIN) $(OREN_SRC) $(OREN_OREN_SRC) $(OREN_RUNTIME_INC)
	@echo "Building Stage 1 (Oren)..."
	@$(COMPILER_BUILD_LOCK) $(MAKE) --no-print-directory __oren_build_unlocked

__oren_build_unlocked:
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" ./$(BOOTSTRAP_BIN) build $(OREN_SRC) $(BOOTSTRAP_TARGET_ARG) $(BOOTSTRAP_CC_ARG) -o "$(OREN_BIN)" $(CODESIGN_ARG) $(GC_ARG); \
	else \
		./$(BOOTSTRAP_BIN) build $(OREN_SRC) $(BOOTSTRAP_TARGET_ARG) $(BOOTSTRAP_CC_ARG) -o "$(OREN_BIN)" $(CODESIGN_ARG) $(GC_ARG); \
	fi

#
# Stage 2: Self-Hosted Compiler (Built by Stage 1)
#
# Rolling policy:
# - Default `make stage2` must build stage2 via the **native backend** on arm64-macos too.
# - If you need the old C-backend bootstrap for bring-up, use:
#     make stage2 OREN_STAGE2_BACKEND=c
OREN_STAGE2_BACKEND ?= native

# Stage2 C-backend toolchain selection (Windows host UX).
#
# When building stage2 via the C backend on a Windows host, `cc` often does not exist.
# The compiler can auto-default to MSVC in many cases, but Makefile should keep the
# "make stage2 OREN_STAGE2_BACKEND=c" path explicit and robust by default.
OREN_STAGE2_CC ?=
ifeq ($(strip $(OREN_STAGE2_CC)),)
  ifeq ($(HOST_IS_WINDOWS),1)
    OREN_STAGE2_CC := cl.exe
  endif
endif
STAGE2_CC_ARG :=
ifeq ($(OREN_STAGE2_BACKEND),c)
  ifneq ($(strip $(OREN_STAGE2_CC)),)
    STAGE2_CC_ARG := --cc $(OREN_STAGE2_CC)
  endif
endif
ifeq ($(HOST_IS_WINDOWS),1)
oren_stage2: $(OREN_STAGE2_BIN)
endif

$(OREN_STAGE2_BIN): $(OREN_BIN) $(OREN_SRC) $(OREN_OREN_SRC) $(OREN_RUNTIME_INC)
				@echo "Building Stage 2 (Self-Hosted)..."
				@$(COMPILER_BUILD_LOCK) $(MAKE) --no-print-directory __oren_stage2_build_unlocked

__oren_stage2_build_unlocked:
			@if [ "$(UNAME_S)" = "Darwin" ]; then \
						arch=$$(uname -m); \
							if [ "$$arch" = "arm64" ] || [ "$$arch" = "aarch64" ]; then \
								PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./$(OREN_BIN) build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug $(STAGE2_CC_ARG) -o $(OREN_STAGE2_BIN) $(CODESIGN_ARG) $(GC_ARG)'; \
							else \
								PATH="$(MACOS_SYSTEM_PATH_PREFIX):$$PATH" OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_RAW_PTR_SCAN=0 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./$(OREN_BIN) build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug $(STAGE2_CC_ARG) -o $(OREN_STAGE2_BIN) $(CODESIGN_ARG) $(GC_ARG)'; \
							fi; \
						else \
								arch=$$(uname -m); \
								if [ "$$arch" = "arm64" ] || [ "$$arch" = "aarch64" ]; then \
									OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./$(OREN_BIN) build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug $(STAGE2_CC_ARG) -o $(OREN_STAGE2_BIN) $(CODESIGN_ARG) $(GC_ARG)'; \
								else \
									OREN_PARSE_JOBS="$(OREN_PARSE_JOBS)" OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_RAW_PTR_SCAN=0 OREN_GC_STACK_SCAN_LIMIT_BYTES="$(OREN_GC_STACK_SCAN_LIMIT_BYTES)" sh -c 'trap "kill 0" TERM INT HUP QUIT; exec ./$(OREN_BIN) build $(OREN_SRC) --backend $(OREN_STAGE2_BACKEND) $(HOST_PLATFORM_ARG) --no-debug $(STAGE2_CC_ARG) -o $(OREN_STAGE2_BIN) $(CODESIGN_ARG) $(GC_ARG)'; \
								fi; \
								fi

# Aliases
bootstrap: oren_bootstrap
stage1: oren
# `make stage2` is the primary rolling path; keep it fast on first-run by also ensuring
# runtime-astbin and rtobj seeds exist (best-effort, cheap copy).
#
# Order matters for cold capsule fills: the rtobj seed builder can now point directly at the
# astbin seed to skip runtime include expansion/fingerprinting, so warm astbin first.
stage2: oren_stage2 astbin-seed rtobj-seed

# Generate/update rtobj seed for the host platform (best-effort).
# This keeps first-run stage2-native builds fast even when the active rtobj cache dir is empty.
# Seed both non-debug and debug runtime objects because native quick integration uses `--debug`.
# Capsule seeds are also hash-keyed, so let the seed script no-op/copy on cache hits instead of
# force-refreshing `examples/hello` on every `make test`.
# For the remaining cold capsule miss path, prefer the already-built stage1 compiler (`./oren`)
# to populate the cache key once; the seed artifact is keyed by runtime hash + backend sig, not by
# which compiler binary produced it.
rtobj-seed: oren_stage2 astbin-seed
			@if [ -n "$(HOST_PLATFORM)" ]; then \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --no-debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --capsule --no-debug || true; \
			else \
				echo "NOTE: host platform unknown; skipping rtobj seed"; \
		fi

# Generate/update rtobj seed for cross x64 targets (best-effort).
# This keeps `make verify-native-x64-compile` bounded even on a clean cache
# (the NET/TLS/HTTP2 smoke is intentionally large; see `scripts/verify_native_x64_compile_only.sh` for its timeout guard).
#
# Warm x64 astbin seeds first so cold capsule rtobj fills can inject the prebuilt runtime astbin
# directly instead of re-expanding the runtime on first miss.
# Prefer stage1 for the one-time cold fill; hit/no-op behavior still keys the final artifact by
# runtime hash + backend sig and still treats `./oren_stage2` as the requested compiler.
rtobj-seed-x64: oren_stage2 astbin-seed-x64
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --capsule --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --capsule --no-debug || true

# Generate/update only the host debug/core rtobj seed needed by stage2 native quick integration.
# Keep this narrow so the fast smoke doesn't pay the capsule seed refresh.
rtobj-seed-quick-stage2: oren_stage2
			@if [ -n "$(HOST_PLATFORM)" ]; then \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --debug || true; \
			else \
				echo "NOTE: host platform unknown; skipping stage2 quick rtobj seed"; \
			fi

# Generate/update runtime astbin seed for the host platform (best-effort).
astbin-seed: oren
		@if [ -n "$(HOST_PLATFORM)" ]; then \
			./scripts/build_runtime_astbin_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_BIN)" || true; \
		else \
			echo "NOTE: host platform unknown; skipping runtime astbin seed"; \
		fi

# Generate/update runtime astbin seed for cross x64 targets (best-effort).
# This keeps x64 compile-only verification bounded when runtime hashes change.
astbin-seed-x64: oren
		@./scripts/build_runtime_astbin_seed.sh --platform x64-linux --compiler "./$(OREN_BIN)" || true
		@./scripts/build_runtime_astbin_seed.sh --platform x64-windows --compiler "./$(OREN_BIN)" || true

# --- Testing & Verification ---

# Fast native smoke (stage1): build+run one self-contained integration test.
test-native-quick: oren
				@./scripts/guard_no_external_rg_dependency.sh
				@./scripts/guard_no_msvc_comment_line_continuation.sh
				@./scripts/run_native_quick_integration.sh "./$(OREN_BIN)"

# Fast native smoke (stage2): use stage2 compiler to build+run the same test.
#
# Warm the rtobj seed first: this path builds the quick-integration fixture with `--debug`,
# and the older 180s stage2 build budget now false-reds on healthy self-hosted debug rebuilds
# during the local BL resolve phase, so keep the target aligned with the wider proven headroom.
test-native-quick-stage2: oren_stage2 rtobj-seed-quick-stage2
		@OREN_NATIVE_BUILD_TIMEOUT_SECS=240 OREN_NATIVE_RUN_TIMEOUT_SECS=120 \
		  ./scripts/run_native_quick_integration.sh "./$(OREN_STAGE2_BIN)"

# Debug flake triage (stage1): run quick integration loop with spawn ring
# + list header ring guardrails enabled. Not part of default verify/test.
test-native-quick-flake-debug: oren
		@./scripts/triage_native_quick_flake_debug.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): run only the green-cache rerun path with STW/runq guards
# enabled and preserve per-run inner + phase logs.
test-native-quick-green-cache-flake: oren
		@./scripts/triage_native_quick_green_cache_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): run the quick-integration prefix through the GC/STW
# netpoll wake regression point with waiter diagnostics enabled.
test-native-quick-gc-stw-focus-flake: oren
		@./scripts/triage_native_quick_gc_stw_focus_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate the late green-worker/STW/join/select tail under
# green-cache-only reruns with STW waiter dumps enabled.
test-native-quick-green-tail-flake: oren
		@./scripts/triage_native_quick_green_tail_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): stress just the two GC join-waiter regressions in-process under
# green-cache-only reruns to amplify the first `expected=3` / `expected=4` STW waits cheaply.
test-native-quick-green-join-waiters-stress-flake: oren
	@./scripts/triage_native_quick_green_join_waiters_stress_flake.sh 5 "./$(OREN_BIN)"

# Debug flake triage (stage2): run the stage2 quick integration loop with spawn ring
# + list header ring guardrails enabled. Not part of default verify/test.
test-native-quick-stage2-flake-debug: oren_stage2
		@./scripts/triage_native_quick_stage2_flake_debug.sh 3 "./$(OREN_STAGE2_BIN)"

# Debug C-backend build flake (arith_div0): loop builds with list header ring guardrails.
test-native-quick-arith-div0-flake: oren_stage2
		@./scripts/triage_arith_div0_c_build_flake.sh 3 "./$(OREN_STAGE2_BIN)"

# GC-stress native quick integration (stage2): force frequent GC to catch tracking issues.
test-native-quick-gc-stress-stage2: oren_stage2
		@OREN_NATIVE_BUILD_TIMEOUT_SECS=60 OREN_NATIVE_RUN_TIMEOUT_SECS=60 \
		  OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=20000 \
		  ./scripts/run_native_quick_integration.sh "./$(OREN_STAGE2_BIN)"

# Capsule smoke (stage2): build+run a minimal pure-compute capsule fixture.
test-native-capsule-smoke-stage2: oren_stage2 rtobj-seed astbin-seed
		@OREN_NATIVE_BUILD_TIMEOUT_SECS=180 OREN_NATIVE_RUN_TIMEOUT_SECS=60 \
			./scripts/run_native_capsule_smoke.sh "./$(OREN_STAGE2_BIN)"

# Optimizer smoke: branchy if/switch list pushes must still get reserve + unchecked rewrites.
verify-optimizer-list-reserve-branchy: oren_stage2
		@./scripts/verify_optimizer_list_reserve_branchy.sh

# Convenience target: verify stage1 then stage2 on the native quick integration test.
verify-native-quick: test-native-quick test-native-quick-stage2 test-native-capsule-smoke-stage2 verify-optimizer-list-reserve-branchy
	@echo "verify-native-quick OK"

# Convenience: native quick verify plus SIMD determinism guard.
verify-native-quick-simd: verify-native-quick verify-simd-determinism
	@echo "verify-native-quick-simd OK"

# GC-stress verify: include forced-GC quick integration to catch tracking regressions.
verify-native-quick-gc: verify-native-quick test-native-quick-gc-stress-stage2
	@echo "verify-native-quick-gc OK"

# Guarded scheduler smoke: standalone world-lock repro with poll cache + args-list guards.
verify-green-world-lock-guarded: oren_stage2
	@./scripts/triage_green_two_workers_world_lock_smoke.sh 3 "./$(OREN_STAGE2_BIN)" OREN_GREEN_POLL_CACHE=1 OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1
	@echo "verify-green-world-lock-guarded OK"

# Guarded scheduler smoke: pre-world-lock quick integration / green-cache path only.
verify-green-preworld-guarded: oren_stage2
	@OREN_QI_STOP_BEFORE_WORLD_LOCK=1 OREN_NATIVE_RUN_TIMEOUT_SECS=30 OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=30 ./scripts/triage_stage2_quick_until_world_lock.sh 1 "./$(OREN_STAGE2_BIN)" OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1
	@echo "verify-green-preworld-guarded OK"

# Guarded scheduler smoke: stage2 quick integration stops after global-runq fairness.
verify-green-fairness-guarded: oren_stage2
	@OREN_QI_STOP_AFTER_GREEN_FAIRNESS=1 OREN_QI_STOP_AFTER_GREEN_CACHE=1 OREN_NATIVE_BUILD_TIMEOUT_SECS=120 OREN_NATIVE_RUN_TIMEOUT_SECS=60 OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=60 ./scripts/triage_native_quick_stage2_flake.sh 1 "./$(OREN_STAGE2_BIN)" OREN_TRACE_GREEN_FAIRNESS=1
	@echo "verify-green-fairness-guarded OK"

# Cross-backend parity smoke: boxed list sum/dot output must match (C/native/OBC).
verify-backend-parity-boxed-list: oren_stage2 avm
	@./scripts/verify_backend_parity_boxed_list.sh

# Cross-backend parity smoke: list<int> sum/dot output must match (C/native/OBC).
verify-backend-parity-list-int: oren_stage2 avm
	@./scripts/verify_backend_parity_list_int.sh

# Cross-backend parity smoke: bytes helpers output must match (C/native/OBC).
verify-backend-parity-bytes: oren_stage2 avm
	@./scripts/verify_backend_parity_bytes.sh

# Cross-backend parity smoke: tagged values + type names must match (C/native/OBC).
verify-backend-parity-tags: oren_stage2 avm
	@./scripts/verify_backend_parity_tags.sh

# Cross-backend parity smoke: arithmetic panic semantics (div0/div_overflow/mod0/mod_overflow/shift_oob).
verify-backend-parity-arith-panics: oren_stage2 avm
	@./scripts/verify_backend_parity_arith_panics.sh

# Cross-backend parity smoke: index panic semantics (negative index assignment, get out-of-bounds, non-container get, map key unsupported get/set).
verify-backend-parity-index-panics: oren_stage2 avm
	@./scripts/verify_backend_parity_index_panics.sh

# Cross-backend parity aggregate: run all parity smokes together.
verify-backend-parity: verify-backend-parity-boxed-list verify-backend-parity-list-int verify-backend-parity-bytes verify-backend-parity-tags verify-backend-parity-arith-panics verify-backend-parity-index-panics
	@echo "verify-backend-parity OK"

# Readiness report (markdown + logs under build/).
readiness-report:
	@./scripts/readiness_report.sh

readiness-report-full:
	@./scripts/readiness_report.sh --full

readiness-report-minimal:
	@./scripts/readiness_report.sh --minimal

readiness-report-json:
	@./scripts/readiness_report.sh --json

readiness-report-index:
	@./scripts/readiness_report.sh --index

readiness-report-summary:
	@./scripts/readiness_report_summary.py

readiness-report-dashboard:
	@./scripts/readiness_report_dashboard.py

readiness-report-index-stats:
	@./scripts/readiness_report_index_stats.py

readiness-report-index-prune:
	@./scripts/readiness_report_index_prune.py

readiness-report-index-trim:
	@./scripts/readiness_report_index_trim.py

readiness-report-index-csv:
	@./scripts/readiness_report_index_export_csv.py

readiness-report-index-query:
	@./scripts/readiness_report_index_query.py

readiness-report-index-rollup:
	@./scripts/readiness_report_index_rollup.py

readiness-report-index-merge:
	@./scripts/readiness_report_index_merge.py

readiness-report-index-compact:
	@./scripts/readiness_report_index_compact.py

readiness-report-index-schema:
	@./scripts/readiness_report_index_validate_schema.py

readiness-report-index-diff:
	@./scripts/readiness_report_index_diff.py

readiness-report-index-diff-summary:
	@./scripts/readiness_report_index_diff_summary.py

readiness-report-index-gate:
	@./scripts/readiness_report_index_gate.py

readiness-report-index-lint:
	@./scripts/readiness_report_index_lint.py

readiness-report-index-split:
	@./scripts/readiness_report_index_split.py

readiness-report-index-latest:
	@./scripts/readiness_report_index_latest.py

readiness-report-index-trend:
	@./scripts/readiness_report_index_trend.py

readiness-report-index-profiles:
	@./scripts/readiness_report_index_profiles.py

readiness-report-index-tags:
	@./scripts/readiness_report_index_tags.py

readiness-report-index-audit:
	@./scripts/readiness_report_index_audit.py

readiness-report-index-audit-trend:
	@./scripts/readiness_report_index_audit_trend.py

readiness-report-collect:
	@./scripts/readiness_report_collect.py

readiness-report-collect-list:
	@./scripts/readiness_report_collect_list.py

readiness-report-collect-pack:
	@./scripts/readiness_report_collect_pack.py

readiness-report-sanitize:
	@./scripts/readiness_report_sanitize.py

readiness-pipeline:
	@./scripts/readiness_pipeline.sh

status-snapshot:
	@./scripts/status_snapshot.py

status-snapshot-diff:
	@./scripts/status_snapshot_diff.py

status-faq:
	@./scripts/status_faq.py

status-faq-diff:
	@./scripts/status_faq_diff.py

status-matrix:
	@./scripts/status_matrix.py

status-matrix-diff:
	@./scripts/status_matrix_diff.py

status-markdown:
	@./scripts/status_markdown_render.py

verify-readiness-report:
	@./scripts/verify_readiness_report_dry_run.sh

verify-readiness-report-summary:
	@./scripts/verify_readiness_report_summary_smoke.sh

verify-readiness-report-dashboard:
	@./scripts/verify_readiness_report_dashboard_smoke.sh

verify-readiness-report-index-tools:
	@./scripts/verify_readiness_report_index_tools_smoke.sh

verify-readiness-report-index-csv:
	@./scripts/verify_readiness_report_index_export_csv_smoke.sh

verify-readiness-report-index-query-rollup:
	@./scripts/verify_readiness_report_index_query_rollup_smoke.sh

verify-readiness-report-index-merge-compact:
	@./scripts/verify_readiness_report_index_merge_compact_smoke.sh

verify-readiness-report-index-schema:
	@./scripts/verify_readiness_report_index_schema_smoke.sh

verify-readiness-report-index-diff:
	@./scripts/verify_readiness_report_index_diff_smoke.sh

verify-readiness-report-index-diff-summary:
	@./scripts/verify_readiness_report_index_diff_summary_smoke.sh

verify-readiness-report-index-gate:
	@./scripts/verify_readiness_report_index_gate_smoke.sh

verify-readiness-report-index-lint:
	@./scripts/verify_readiness_report_index_lint_smoke.sh

verify-readiness-report-index-split:
	@./scripts/verify_readiness_report_index_split_smoke.sh

verify-readiness-report-index-trim:
	@./scripts/verify_readiness_report_index_trim_smoke.sh

verify-readiness-report-index-latest:
	@./scripts/verify_readiness_report_index_latest_smoke.sh

verify-readiness-report-index-trend:
	@./scripts/verify_readiness_report_index_trend_smoke.sh

verify-readiness-report-index-profiles:
	@./scripts/verify_readiness_report_index_profiles_smoke.sh

verify-readiness-report-index-tags:
	@./scripts/verify_readiness_report_index_tags_smoke.sh

verify-readiness-report-index-audit:
	@./scripts/verify_readiness_report_index_audit_smoke.sh

verify-readiness-report-index-audit-trend:
	@./scripts/verify_readiness_report_index_audit_trend_smoke.sh

verify-readiness-report-collect:
	@./scripts/verify_readiness_report_collect_smoke.sh

verify-readiness-report-collect-list:
	@./scripts/verify_readiness_report_collect_list_smoke.sh

verify-readiness-report-collect-pack:
	@./scripts/verify_readiness_report_collect_pack_smoke.sh

verify-readiness-report-sanitize:
	@./scripts/verify_readiness_report_sanitize_smoke.sh

verify-readiness-pipeline:
	@./scripts/verify_readiness_pipeline_smoke.sh

verify-status-snapshot:
	@./scripts/verify_status_snapshot_smoke.sh

verify-status-snapshot-diff:
	@./scripts/verify_status_snapshot_diff_smoke.sh

verify-status-faq:
	@./scripts/verify_status_faq_smoke.sh

verify-status-faq-diff:
	@./scripts/verify_status_faq_diff_smoke.sh

verify-status-matrix:
	@./scripts/verify_status_matrix_smoke.sh

verify-status-matrix-diff:
	@./scripts/verify_status_matrix_diff_smoke.sh

verify-status-markdown:
	@./scripts/verify_status_markdown_smoke.sh

verify-runtime-robustness: oren_stage2
	OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS="$(OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS)" \
	OREN_RUNTIME_ROBUSTNESS_C_RUNS="$(OREN_RUNTIME_ROBUSTNESS_C_RUNS)" \
	OREN_RUNTIME_ROBUSTNESS_C_FIXTURES="$(OREN_RUNTIME_ROBUSTNESS_C_FIXTURES)" \
	OREN_RUNTIME_ROBUSTNESS_TRACE_ENV="$(OREN_RUNTIME_ROBUSTNESS_TRACE_ENV)" \
	./scripts/verify_runtime_robustness_w5.sh $(OREN_RUNTIME_ROBUSTNESS_RUNS) $(OREN_RUNTIME_ROBUSTNESS_COMPILER)

# SIMD determinism guard (scalar vs SIMD output must match).
verify-simd-determinism: oren_stage2
	@./scripts/verify_simd_determinism.sh

# GUI bring-up smoke (headful, opt-in).
# This is intentionally NOT part of `make test` or `make verify` because it requires a GUI session.
verify-ui-smoke-macos: oren
	@./scripts/verify_ui_smoke_macos.sh ./$(OREN_BIN)

# Windows GUI bring-up smoke (headful, opt-in).
# Requires a Windows GUI session.
verify-ui-smoke-windows: oren_stage2
	@./scripts/verify_ui_smoke_windows.sh ./$(OREN_STAGE2_BIN)

# Linux GUI bring-up smoke (headful; X11; opt-in).
verify-ui-smoke-linux: oren_stage2
	@./scripts/verify_ui_smoke_linux.sh ./$(OREN_STAGE2_BIN)

# Build the Win32 OrenUI shim DLL (headful runtime; build is safe in CI).
# Notes:
# - Requires a Windows host.
# - Auto-configures VS2022 MSVC environment via `scripts/win_msvc_cmd.cmd`.
# - This is not part of `make test`/`make verify` since it does not run anything.
build-orenui-win32:
ifeq ($(HOST_IS_WINDOWS),1)
	@mkdir -p build/tmp
	@echo "== build: orenui_win32.dll (Win32/GDI) =="
	@cmd.exe /v:on /c "setlocal && call scripts\\win_msvc_cmd.cmd cl.exe /nologo /O2 /LD /DORENUI_EXPORTS native\\orenui\\win32\\orenui_win32.c /I native\\orenui user32.lib gdi32.lib /link /OUT:build\\tmp\\orenui_win32.dll"
else
	@echo "ERROR: build-orenui-win32 requires a Windows host (HOST_IS_WINDOWS=1)."
	@exit 2
endif

# Compile-only sanity gate for x64 targets (does not run artifacts).
verify-native-x64-compile: oren_stage2 rtobj-seed-x64 astbin-seed-x64
			@./scripts/verify_native_x64_compile_only.sh

# Higher-signal compile-only gate: compile the compiler program for x64 targets and validate artifact kinds.
# - Default source: `oren_x64.oren` (x64-focused; avoids compiling arm64 native backends into x64 artifacts)
# - Override: `OREN_SELFHOST_SRC=oren.oren make verify-native-x64-selfhost-compile`
#
# This is intentionally not part of `make test` (it can be slower than the small-fixture suite).
# Tune timeout with: OREN_SELFHOST_BUILD_TIMEOUT_SECS=...
verify-native-x64-selfhost-compile: oren_stage2
			@./scripts/verify_native_x64_selfhost_compile_only.sh

# Local execution smoke for x64-linux artifacts under QEMU in the persistent Linux container.
# This is a higher-signal guard than compile-only, but still does not require remote WSL2.
verify-x64-linux-qemu: oren_stage2
			@./scripts/verify_x64_linux_qemu_smoke.sh

# Local execution smoke for x64-linux NET fixtures (loopback-only) under QEMU.
# Requires `make setup-x64-linux-qemu` once to install an amd64 glibc loader in the container.
verify-x64-linux-qemu-net: oren_stage2
			@./scripts/verify_x64_linux_qemu_net_smoke.sh

# Local execution smoke for x64-linux TLS/HTTPS/WSS fixtures (loopback-only) under QEMU.
# Requires `OREN_X64_LINUX_QEMU_INSTALL_OPENSSL=1 make setup-x64-linux-qemu` once to install amd64 OpenSSL.
verify-x64-linux-qemu-tls: oren_stage2
			@./scripts/verify_x64_linux_qemu_tls_smoke.sh

# One-time environment setup: install an amd64 glibc loader inside the persistent Linux container
# so qemu-x86_64 can execute dynamically-linked x64-linux binaries.
setup-x64-linux-qemu:
			@./scripts/setup_x64_linux_qemu_sysroot.sh

# Tier‑1 verification shortcuts (rolling).
#
# These targets wrap the purpose-built scripts under `scripts/`:
# - `verify-native-matrix`: stage1 + stage2 native quick integration across Tier‑1 targets
# - `verify-native-net`: loopback NET matrix across Tier‑1 targets (TCP/UDP + HTTP + WebSocket)
# - `verify-selfhost-x64`: run the compiler itself on remote x86_64 (Win11 + WSL2)
verify-native-matrix: oren_stage2
	@./scripts/verify_native_matrix.sh

verify-native-matrix-skip-remote: oren_stage2
	@# When remote Win11/WSL2 is unavailable, still keep x64-linux runtime coverage via qemu-x86_64 in the linux container.
	@./scripts/verify_native_matrix.sh --skip-remote --targets local,arm64-linux,x64-linux-qemu

verify-native-net: oren_stage2
	@./scripts/verify_native_net_matrix.sh

verify-native-net-skip-remote: oren_stage2
	@./scripts/verify_native_net_matrix.sh --skip-remote

verify-selfhost-x64: oren_stage2
	@./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win

verify-stage0-win:
	@./scripts/verify_stage0_windows_bootstrap.sh

# Optional: prove native Windows can build stage2 (stage0 -> stage1 -> stage2) and run a tiny program.
verify-stage2-win:
	@./scripts/verify_windows_stage2_from_stage1.sh

verify-tier1: oren_stage2
	@./scripts/verify_native_matrix.sh --targets stage0,stage1,stage2,local,arm64-linux,x64-win,x64-wsl,x64-win-tier1,x64-wsl-tier1
	@./scripts/verify_native_net_matrix.sh
	@echo "verify-tier1 OK"

# Perf smoke: benchmark stage2 native "compile one file" (rtobj miss -> hit).
bench-native-compile: oren_stage2
		@./scripts/bench_native_compile_one_file.sh

# Full benchmark sweep + snapshot update (logs to build/logs/benchmarks-all-*.log).
benchmarks: oren_stage2
		@./scripts/run_benchmarks_all.sh

# Focused W5 perf gate sweep: just the hot-loop + alloc/GC native-vs-C benchmarks.
perf-gate-native: oren_stage2
		@./scripts/run_perf_gate_native.sh

# Focused native read split: estimate fill/setup vs repeated read-loop cost for array_sum/dot_product.
perf-gate-native-read-split: oren_stage2
		@./scripts/run_perf_gate_native_read_split.sh

# Focused native steady-state sweep: repeated read-loop medians for array_sum/dot_product.
perf-gate-native-steady: oren_stage2
		@./scripts/run_perf_gate_native_steady.sh

# Focused list<int> perf gate sweep: shared list<int> hot loops across C/Oren C/native/OBC.
perf-gate-list-int: oren_stage2
		@./scripts/run_perf_gate_list_int.sh

# Focused list<int> split sweep: estimate fill/setup vs steady read-loop cost.
perf-gate-list-int-read-split: oren_stage2
	@./scripts/run_perf_gate_list_int_read_split.sh

perf-gate-list-int-steady: oren_stage2
	@./scripts/run_perf_gate_list_int_steady.sh

perf-probe-list-int-unsafe: oren_stage2
	@./scripts/run_perf_probe_list_int_unsafe.sh

perf-probe-list-int-packed-bridge: oren_stage2
	@./scripts/run_perf_probe_list_int_packed_bridge.sh

perf-probe-list-int-slot-direct: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_direct.sh

perf-probe-arm64-fast-loop-tick-masks: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_tick_masks.sh

perf-probe-arm64-fast-loop-tick-masks-steady: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_tick_masks_steady.sh

perf-probe-arm64-fast-dot-single-pair-cursor-regs: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_single_pair_cursor_regs.sh

perf-probe-arm64-fast-dot-unroll2: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_unroll2.sh

perf-probe-arm64-fast-dot-dual-accum: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_dual_accum.sh

perf-probe-arm64-fast-dot-madd-exact: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact.sh

perf-probe-arm64-native-hot-loop-disasm: oren_stage2
	@./scripts/run_perf_probe_arm64_native_hot_loop_disasm.sh

perf-probe-arm64-dot-acceptance: oren_stage2
	@./scripts/run_perf_probe_arm64_dot_acceptance.sh

perf-probe-native-gate-stability: oren_stage2
	@./scripts/run_perf_probe_native_gate_stability.sh

perf-smoke-native-fast-loops: oren_stage2
	@./scripts/run_perf_smoke_native_fast_loops.sh

perf-debug-native-benchmark: oren_stage2
	@bash ./scripts/run_perf_debug_native_benchmark.sh

perf-smoke-list-int: oren_stage2
	@./scripts/run_perf_smoke_list_int.sh

perf-smoke-list-int-packed-bridge: oren_stage2
	@./scripts/run_perf_smoke_list_int_packed_bridge.sh

perf-smoke-list-int-slot-direct: oren_stage2
	@./scripts/run_perf_smoke_list_int_slot_direct.sh

perf-prebuild-list-int-packed-bridge: oren_stage2
	@./scripts/build_perf_artifacts_list_int_packed_bridge.sh

perf-prebuild-dot-product-int-packed-bridge: oren_stage2
	@OREN_PERF_PREBUILD_PROGRAMS=dot_product_int_packed_bridge ./scripts/build_perf_artifacts_list_int_packed_bridge.sh

perf-prebuild-list-int-slot-direct: oren_stage2
	@./scripts/build_perf_artifacts_list_int_slot_direct.sh

perf-prebuild-dot-product-int-slot-direct: oren_stage2
	@OREN_PERF_PREBUILD_PROGRAMS=dot_product_int_slot_direct ./scripts/build_perf_artifacts_list_int_slot_direct.sh

verify-native-core-packed-bridge: oren_stage2
	@OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND=native ./scripts/run_perf_smoke_list_int_packed_bridge.sh

verify-native-slot-direct: oren_stage2
	@./scripts/run_perf_smoke_list_int_slot_direct.sh

verify-native-list-int-fast-lowering: oren_stage2
	@./scripts/verify_native_list_int_fast_lowering.sh

# Update the latest benchmark snapshot from existing result JSON files.
benchmarks-update:
		@python3 benchmarks/update_latest.py --prune

# Lightweight rolling perf tripwire: ensure rtobj-hit compile-one-file stays under threshold.
perf-guard-native-hit: oren_stage2
		@./scripts/perf_guard_native_compile_one_file_hit.sh

# Default "test" is the fast stage1 native quick smoke.
#
# Keep the heavier self-host bundle explicit so the common local gate stays aligned with the
# repo's <3 minute contract. Use `make test-selfhost` or `make verify-native-quick` when the
# stage2/capsule/optimizer coverage is desired.
test: test-native-quick

# Heavier self-host/local production smoke bundle.
test-selfhost: verify-native-quick

# AVM test suite (bytecode build + avm run).
#
# Note:
# - Kept separate from default `make test` so native iteration stays extremely fast.
# - The curated AVM_TESTS list is intentionally small; override it for full coverage.
test-avm: oren avm
	@echo "=== AVM Tests (Curated) ==="
	@mkdir -p build
	@mkdir -p build/logs
	@set -e; \
		for t in $(AVM_TESTS); do \
			name=$$(basename "$$t" .oren); \
			obc="build/avm_$${name}.obc"; \
			log="build/logs/avm_$${name}.log"; \
			echo "Testing $$name..."; \
			$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build "$$t" --backend bytecode -o "$$obc" > "$$log" 2>&1 || { echo "--- $$name (build) ---"; cat "$$log"; exit 1; }; \
			expect_rc=0; expect_err=""; avm_env=""; avm_args="--print-run-json"; post_absent=""; \
			case "$$name" in \
				test_budget_gas) expect_rc=1; expect_err="AVM error: code=9"; avm_env="AVM_GAS=20000" ;; \
				test_budget_timeout) expect_rc=1; expect_err="AVM error: code=5"; avm_args="--timeout-ms 5 --print-run-json" ;; \
				test_arith_invalid) expect_rc=1; expect_err="AVM error: code=4" ;; \
				test_vfs_no_host_fs) \
					avm_args="--deny-by-default --allow-domains 0,1,6 --fs-backend vfs --fs-allow-prefixes build/ --print-run-json"; \
					post_absent="build/avm_vfs_should_not_write.bin" ;; \
				test_vproc_no_host_proc) \
					avm_args="--deny-by-default --allow-domains 0,5,6 --proc-backend vproc --proc-exit-code 0 --print-run-json"; \
					post_absent="build/avm_vproc_should_not_touch.txt" ;; \
				test_vnet_no_host_net) \
					avm_args="--deny-by-default --allow-domains 0,4,6 --net-backend vnet --net-fixtures-hex 41564d4e45543031010000000100000075020000006f6b --print-run-json" ;; \
				test_vproc_fixtures) \
					avm_args="--deny-by-default --allow-domains 0,5,6 --proc-backend vproc --proc-exit-code 7 --proc-fixtures-hex 41564d505243303101000000070000006563686f20686900000000 --print-run-json" ;; \
				test_list_freelist_env) avm_env="AVM_LIST_FREELIST=1 AVM_LIST_FREELIST_BYTES=1048576 AVM_LIST_FREELIST_MAX_BLOCK_BYTES=65536" ;; \
			esac; \
			outf="build/logs/avm_$${name}.out"; \
			set +e; \
			env $$avm_env $(RUN_WITH_TIMEOUT) ./$(AVM_BIN) $$avm_args "$$obc" > "$$outf" 2>&1; \
			rc=$$?; \
			set -e; \
			cat "$$outf" >> "$$log"; \
			if [ "$$expect_rc" -eq 0 ]; then \
				if [ "$$rc" -ne 0 ]; then echo "--- $$name (run) ---"; cat "$$log"; exit 1; fi; \
				if [ -n "$$post_absent" ]; then \
					test ! -f "$$post_absent" || { echo "--- $$name (run, host artifact exists) ---"; echo "expected absent: $$post_absent" >> "$$log"; cat "$$log"; exit 1; }; \
				fi; \
			else \
				if [ "$$rc" -eq 0 ]; then echo "--- $$name (run, expected failure) ---"; cat "$$log"; exit 1; fi; \
				if [ -n "$$expect_err" ]; then \
					grep -q "$$expect_err" "$$outf" || { echo "--- $$name (run, missing expected error) ---"; cat "$$log"; exit 1; }; \
				fi; \
			fi; \
		done; \
		echo "AVM tests OK"

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
AVM_INC := $(shell find lib/avm -maxdepth 1 -name '*.inc' -print | sort)

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
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/hello.oren --backend native -o build/ex_hello_native$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_hello_native$(EXE_EXT) >/dev/null
	@# 1b) Native module import + stdlib import
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/module_app.oren --backend native -o build/ex_module_app_native$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_module_app_native$(EXE_EXT) >/dev/null
	@# 2) GC suite (native)
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/gc_test.oren --backend native -o build/ex_gc_native$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG)
	@$(RUN_WITH_TIMEOUT) ./build/ex_gc_native$(EXE_EXT)
		@# 2b/3) Native FFI + dylib export
		@# - macOS: FFI works (dyld binding + LC_LOAD_DYLIB); dylib export is supported.
		@# - Windows x64: FFI works via lazy LoadLibraryA/GetProcAddress (dll attachment via `@ffi.dll`).
		@# - Linux: FFI works via ELF dynamic linking + `dlsym` resolver (link deps can be declared via `@ffi.link`).
			@if [ "$(UNAME_S)" = "Darwin" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/ffi_test.oren --backend native -o build/ex_ffi_puts$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG); \
				$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts$(EXE_EXT) >/dev/null; \
				$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/libmath.oren --backend native --lib -o build/libmath.dylib $(CODESIGN_ARG) $(GC_ARG) --metadata; \
				test -f build/libmath.h; \
				$(RUN_WITH_TIMEOUT) ./$(OREN_BIN) scan build/libmath.dylib >/dev/null; \
				$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/ffi_from_libmath.oren --backend native --link build/libmath.dylib -o build/ex_ffi_from_libmath$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG); \
				$(RUN_WITH_TIMEOUT) ./build/ex_ffi_from_libmath$(EXE_EXT); \
			elif [ "$(UNAME_S)" = "Linux" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/ffi_test.oren --backend native -o build/ex_ffi_puts$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG); \
				$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts$(EXE_EXT) >/dev/null; \
			elif [ "$(HOST_IS_WINDOWS)" = "1" ]; then \
				$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/ffi_test.oren --backend native -o build/ex_ffi_puts$(EXE_EXT) $(CODESIGN_ARG) $(GC_ARG); \
				$(RUN_WITH_TIMEOUT) ./build/ex_ffi_puts$(EXE_EXT) >/dev/null; \
			else \
				echo "INFO: skipping native FFI examples on $(UNAME_S)"; \
			fi
		@# 4) Bytecode + AVM
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/hello.oren --backend bytecode -o build/ex_hello.obc
		@$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) build/ex_hello.obc >/dev/null
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/module_app.oren --backend bytecode -o build/ex_module_app.obc
		@$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) build/ex_module_app.obc >/dev/null
	@# 5) AVM Virtual backends demos (VFS / VPROC / VNET)
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/avm_vfs_demo.oren --backend bytecode -o build/ex_avm_vfs_demo.obc
	@rm -f build/ex_avm_vfs_demo.bin
		@$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) --deny-by-default --allow-domains "0,1,6" --fs-allow-prefixes "build/" --fs-backend vfs build/ex_avm_vfs_demo.obc
	@test ! -f build/ex_avm_vfs_demo.bin
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/avm_vproc_demo.oren --backend bytecode -o build/ex_avm_vproc_demo.obc
	@rm -f build/ex_avm_vproc_should_not_touch.txt
		@$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) --deny-by-default --allow-domains "0,5,6" --proc-backend vproc --proc-exit-code 0 build/ex_avm_vproc_demo.obc
	@test ! -f build/ex_avm_vproc_should_not_touch.txt
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/avm_vnet_demo.oren --backend bytecode -o build/ex_avm_vnet_demo.obc
	@hex="41564d4e45543031010000000100000075020000006f6b"; \
			$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) --deny-by-default --allow-domains "0,4,6" --net-backend vnet --net-fixtures-hex "$$hex" build/ex_avm_vnet_demo.obc
	@# 6) AVM multiverse demo (parent runs child with VirtualNET fixtures)
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/avm_fixtures/multiverse_child_net.oren --backend bytecode -o build/ex_multiverse_child_net.obc
		@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_BIN) build examples/avm_multiverse_net_demo.oren --backend bytecode -o build/ex_avm_multiverse_net_demo.obc
		@$(RUN_WITH_TIMEOUT) ./$(AVM_BIN) --deny-by-default --allow-domains "0,1,4,6,8" --fs-allow-prefixes "build/" --fs-backend host build/ex_avm_multiverse_net_demo.obc >/dev/null
		@echo "Examples OK"

# Compile-only example smoke for non-host platforms (rolling).
#
# Goal:
# - Keep Makefile aware of Tier‑1 discrepancies by exercising shared-library output on all Tier‑1 targets,
#   even when the host cannot execute the produced binaries.
# - Use `./oren_stage2 scan` (header-based for Oren `--lib`) to sanity-check the exported API
#   without running foreign artifacts.
#
# Notes:
# - This is compile-only and safe to run on arm64-macos hosts.
# - It is not part of `make test` (keep iteration fast); run explicitly or wire into higher-signal gates.
examples-cross-compile-smoke: oren_stage2
	@mkdir -p build/tmp
	@# arm64-linux shared object (.so)
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_STAGE2_BIN) build examples/libmath.oren --backend native --platform arm64-linux --lib --no-debug -o build/tmp/libmath_stage2_arm64_linux.so --metadata $(GC_ARG)
	@test -f build/tmp/libmath_stage2_arm64_linux.h
	@grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_arm64_linux.h >/dev/null
	@grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_arm64_linux.h >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_arm64_linux.so | grep -F '| add |' >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_arm64_linux.so | grep -F '| mul |' >/dev/null
	@file build/tmp/libmath_stage2_arm64_linux.so | grep -Ei 'ELF 64-bit.*(shared object.*(ARM aarch64|aarch64)|(ARM aarch64|aarch64).*shared object)' >/dev/null
	@# x64-linux shared object (.so)
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_STAGE2_BIN) build examples/libmath.oren --backend native --platform x64-linux --lib --no-debug -o build/tmp/libmath_stage2_x64_linux.so --metadata $(GC_ARG)
	@test -f build/tmp/libmath_stage2_x64_linux.h
	@grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_x64_linux.h >/dev/null
	@grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_x64_linux.h >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_x64_linux.so | grep -F '| add |' >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_x64_linux.so | grep -F '| mul |' >/dev/null
	@file build/tmp/libmath_stage2_x64_linux.so | grep -Ei 'ELF 64-bit.*(shared object.*x86-64|x86-64.*shared object)' >/dev/null
	@# x64-windows DLL (.dll)
	@$(RUN_BUILD_WITH_TIMEOUT) ./$(OREN_STAGE2_BIN) build examples/libmath.oren --backend native --platform x64-windows --lib --no-debug -o build/tmp/libmath_stage2_x64_windows.dll --metadata $(GC_ARG)
	@test -f build/tmp/libmath_stage2_x64_windows.h
	@grep -F 'extern int64_t add(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_x64_windows.h >/dev/null
	@grep -F 'extern int64_t mul(int64_t arg0, int64_t arg1);' build/tmp/libmath_stage2_x64_windows.h >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_x64_windows.dll | grep -F '| add |' >/dev/null
	@./$(OREN_STAGE2_BIN) scan build/tmp/libmath_stage2_x64_windows.dll | grep -F '| mul |' >/dev/null
	@file build/tmp/libmath_stage2_x64_windows.dll | grep -F 'PE32+ executable (DLL)' >/dev/null
	@python3 scripts/pe_exports_check.py build/tmp/libmath_stage2_x64_windows.dll --contains add --contains mul
	@echo "examples-cross-compile-smoke OK"

# Verify `.obc` portability across AVM hosts (rolling).
# This is an integration-style gate and may use Docker + remote Win11+WSL2.
obc-portability: oren avm
	@tools/verify_obc_portability.sh

# --- Cleanup ---

clean:
	@echo "Cleaning workspace..."
	rm -rf build/ *.dSYM verify_full.sh run_tests.sh
	rm -f "$(BOOTSTRAP_BIN)" "$(OREN_BIN)" "$(OREN_STAGE2_BIN)" "oren_stage3$(EXE_EXT)" "$(AVM_BIN)" "$(OREDOC_BIN)" "$(ORENSIGN_BIN)"
	rm -f *.oren.c *.obc *.otool *.dylib *.so
	@# Remove local test binaries (keep .oren sources)
	@find tests/native -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
	@find tests/modules -maxdepth 1 -type f ! -name '*.oren' -delete 2>/dev/null || true
