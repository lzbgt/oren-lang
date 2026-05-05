.PHONY: all clean bootstrap test test-curated test-selfhost verify stage1 stage2 examples-test examples-test-inner
.PHONY: examples-cross-compile-smoke
.PHONY: test-native-quick test-native-quick-stage2 test-native-quick-flake-debug test-native-quick-green-cache-flake test-native-quick-green-local-ptr-flake test-native-quick-green-local-ptr-direct-flake test-native-quick-green-local-ptr-plain-flake test-native-quick-green-local-ptr-workers-flake test-native-quick-green-local-ptr-split-flake test-native-quick-green-fairness-flake test-native-quick-green-fairness-zeroarg-flake test-native-quick-green-fairness-onearg-flake test-native-quick-green-fairness-onearg-direct-flake test-native-quick-green-fairness-onearg-modes-flake test-native-quick-green-fairness-onearg-count-sweep-flake test-native-quick-green-fairness-modes-flake test-native-quick-gc-stw-focus-flake test-native-quick-green-tail-flake test-native-quick-green-join-waiters-stress-flake test-native-quick-stage2-flake-debug test-native-quick-arith-div0-flake test-native-capsule-smoke-stage2 verify-native-quick verify-native-quick-simd verify-native-quick-base-cold-seeded verify-native-quick-stage2-direct-autoseed verify-native-quick-green-local-ptr-guarded verify-green-world-lock-guarded verify-green-preworld-guarded verify-green-fairness-guarded verify-backend-parity verify-backend-semantic-diff verify-backend-semantic-diff-gas-calibration verify-backend-semantic-diff-gas-branch-calibration verify-backend-semantic-diff-gas-call-calibration verify-backend-semantic-diff-gas-alloc-calibration verify-backend-parity-bytes verify-backend-parity-arith-panics verify-backend-parity-index-panics verify-runtime-robustness verify-simd-determinism verify-ui-smoke-macos verify-ui-smoke-windows verify-ui-smoke-linux readiness-report readiness-report-full readiness-report-minimal readiness-report-json readiness-report-index readiness-report-summary readiness-report-dashboard readiness-report-index-stats readiness-report-index-prune readiness-report-index-trim readiness-report-index-csv readiness-report-index-query readiness-report-index-rollup readiness-report-index-merge readiness-report-index-compact readiness-report-index-schema readiness-report-index-diff readiness-report-index-diff-summary readiness-report-index-gate readiness-report-index-lint readiness-report-index-split readiness-report-index-latest readiness-report-index-trend readiness-report-index-profiles readiness-report-index-tags readiness-report-index-audit readiness-report-index-audit-trend readiness-report-collect readiness-report-collect-list readiness-report-collect-pack readiness-report-sanitize readiness-pipeline status-snapshot status-snapshot-diff status-faq status-faq-diff status-matrix status-matrix-diff status-markdown verify-readiness-report verify-readiness-report-summary verify-readiness-report-dashboard verify-readiness-report-index-tools verify-readiness-report-index-csv verify-readiness-report-index-query-rollup verify-readiness-report-index-merge-compact verify-readiness-report-index-schema verify-readiness-report-index-diff verify-readiness-report-index-diff-summary verify-readiness-report-index-gate verify-readiness-report-index-lint verify-readiness-report-index-split verify-readiness-report-index-trim verify-readiness-report-index-latest verify-readiness-report-index-trend verify-readiness-report-index-profiles verify-readiness-report-index-tags verify-readiness-report-index-audit verify-readiness-report-index-audit-trend verify-readiness-report-collect verify-readiness-report-collect-list verify-readiness-report-collect-pack verify-readiness-report-sanitize verify-readiness-pipeline verify-status-snapshot verify-status-snapshot-diff verify-status-faq verify-status-faq-diff verify-status-matrix verify-status-matrix-diff verify-status-markdown benchmarks benchmarks-update
.PHONY: verify-native-x64-compile
.PHONY: verify-oretest
.PHONY: verify-yield-lowering-v0 verify-yield-backend-parity-v0 verify-yield-value-surface-v0 verify-yield-exchange-surface-v0 verify-generator-surface-v0 verify-coroutine-surface-v0 verify-task-surface-v0 verify-task-group-surface-v0 verify-task-group-task-surface-v0 verify-generator-finalize-surface-v0 verify-generator-nested-green-resume-v0
.PHONY: verify-native-x64-selfhost-compile
.PHONY: verify-capability-runtime-contract verify-capability-metadata verify-capability-manifest-policy verify-effect-ledger-contract verify-avm-effect-ledger-json verify-avm-package-policy-runner verify-native-package-policy-runner verify-native-capsule-resource-checks verify-native-gas-accounting-modes verify-gas-surface-registry verify-public-readme-positioning verify-avm-spawn-channel-args verify-backend-gas-surface-calibration-set verify-backend-native-instruction-surface-decision
.PHONY: verify-x64-linux-qemu
.PHONY: verify-x64-linux-qemu-net
.PHONY: verify-x64-linux-qemu-tls
.PHONY: setup-x64-linux-qemu
.PHONY: verify-native-matrix verify-native-matrix-skip-remote verify-native-net verify-native-net-skip-remote verify-selfhost-x64 verify-stage0-win verify-tier1
.PHONY: verify-stage2-win
.PHONY: build-orenui-win32
.PHONY: bench-native-compile
.PHONY: perf-guard-native-hit
.PHONY: verify-native-arm64-dot-prefix-pair-loop-tail
.PHONY: perf-probe-arm64-fast-get-sum-vector-2d-decision verify-native-arm64-get-sum-vector-2d-tail
.PHONY: verify-native-arm64-slot64-simd-isa
.PHONY: perf-gate-native perf-gate-native-read-split perf-gate-native-steady perf-gate-list-int perf-gate-list-int-read-split perf-gate-list-int-steady perf-probe-list-int-unsafe perf-probe-list-int-packed-bridge perf-probe-list-int-packed-bridge-read-split perf-probe-list-int-packed-bridge-simd-reuse perf-probe-list-int-i32-buf-dot-ceiling perf-probe-list-int-i32-buf-read-split perf-probe-list-int-i32-buf-simd-reuse perf-probe-list-int-i32-buf-setup-breakdown perf-probe-list-int-i32-buf-unchecked-fill perf-probe-list-int-slot-direct perf-probe-list-int-slot-direct-read-split perf-probe-list-int-slot-surface-read-split perf-probe-list-int-slot-abi-ceiling perf-probe-list-int-slot-direct-fast-tick-decision perf-probe-list-int-slot-direct-pair-loop-decision perf-probe-list-int-c-ceiling perf-probe-list-int-dot-route-decision perf-probe-list-int-array-sum-c-breakdown perf-probe-list-int-fill-share-decision perf-probe-list-int-dot-ceiling perf-probe-list-int-specialization-gap perf-probe-list-int-specialization-read-split perf-probe-list-int-specialization-trace perf-probe-arm64-fast-loop-tick-masks perf-probe-arm64-fast-loop-tick-masks-steady perf-probe-arm64-fast-loop-pair-post perf-probe-arm64-fast-loop-prefix-zero perf-probe-arm64-fast-dot-prefix-zero perf-probe-arm64-fast-dot-prefix-zero-list-int perf-probe-arm64-fast-dot-prefix-pair-loop-decision perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int perf-probe-arm64-fast-dot-prefix-zero-specialization perf-probe-arm64-fast-dot-single-pair-cursor-regs perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int perf-probe-arm64-fast-get-sum-tick-mask-list-int perf-probe-arm64-fast-get-sum-tick-mask-decision perf-probe-arm64-fast-get-sum-unroll2-list-int perf-probe-arm64-fast-get-sum-unroll2-decision perf-probe-arm64-fast-get-sum-dual-accum-list-int perf-probe-arm64-fast-get-sum-dual-accum-decision perf-probe-arm64-fast-get-sum-pair-post-list-int perf-probe-arm64-fast-get-sum-pair-post-decision perf-probe-arm64-whole-list-get-sum-helper-decision perf-probe-arm64-fast-push-idx-expr-decision perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision perf-probe-arm64-fast-push-nonneg-linear-decision perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision perf-probe-arm64-fast-push-tick-mask-decision perf-probe-arm64-fast-push-fresh-exact-init-decision perf-probe-arm64-fast-push-fresh-exact-single-list-decision perf-probe-arm64-fast-push-native-list-hdr-decision perf-probe-arm64-fast-push-single-list-cursor-list-int perf-probe-arm64-fast-dot-unroll2 perf-probe-arm64-fast-dot-unroll2-list-int perf-probe-arm64-fast-dot-dual-accum perf-probe-arm64-fast-dot-dual-accum-list-int perf-probe-arm64-fast-dot-madd-exact perf-probe-arm64-fast-dot-madd-exact-list-int perf-probe-arm64-fast-dot-madd-exact-subpaths perf-probe-arm64-fast-dot-madd-exact-list-int-subpaths perf-probe-arm64-fast-dot-scalar-core-matrix perf-probe-arm64-fast-dot-scalar-core-matrix-list-int perf-probe-arm64-fast-dot-scalar-core-read-split perf-probe-arm64-fast-dot-scalar-core-read-split-list-int perf-probe-arm64-fast-dot-scalar-core-gate-stability perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int perf-probe-arm64-fast-dot-scalar-post-decision-list-int perf-probe-arm64-fast-dot-pair-post-madd-decision perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int perf-probe-arm64-fast-dot-dual-madd-decision perf-probe-arm64-fast-dot-dual-madd-decision-list-int perf-probe-arm64-fast-dot-low32-loads-decision perf-probe-arm64-fast-dot-low32-loads-decision-list-int perf-probe-arm64-fast-dot-madd-exact-double-sweep perf-probe-arm64-fast-dot-double-exit-snippet perf-probe-arm64-dot-vs-c-loop-compare perf-probe-arm64-dot-vs-c-loop-compare-list-int perf-probe-arm64-dot-vs-c-scalar-ceiling perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int perf-probe-arm64-native-hot-loop-disasm perf-probe-arm64-list-int-hot-loop-disasm perf-probe-arm64-list-int-fill-hot-loop-disasm perf-probe-arm64-fill-vs-c-loop-compare perf-probe-arm64-dot-acceptance perf-probe-arm64-list-int-acceptance perf-probe-native-gate-stability perf-smoke-native-fast-loops perf-debug-native-benchmark perf-smoke-list-int perf-smoke-list-int-packed-bridge perf-smoke-list-int-slot-direct perf-prebuild-list-int-packed-bridge perf-prebuild-dot-product-int-packed-bridge perf-prebuild-list-int-slot-direct perf-prebuild-dot-product-int-slot-direct verify-native-core-packed-bridge verify-native-slot-direct verify-native-list-int-fast-lowering verify-native-arm64-dot-madd-scalar-default
.PHONY: rtobj-seed
.PHONY: rtobj-seed-x64
.PHONY: astbin-seed
.PHONY: profile-bytecode-codegen profile-native-build-phases

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
		tests/avm/test_yield_stmt_v0.oren \
		tests/avm/test_yield_value_v0.oren \
		tests/avm/test_yield_exchange_v0.oren \
		tests/avm/test_generator_v0.oren \
		tests/avm/test_coroutine_v0.oren \
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
# Seed both core/full and non-debug/debug runtime objects because ordinary fixtures can escalate
# to the full runtime profile (for example std:linalg), while native quick integration uses `--debug`.
# Capsule seeds are also hash-keyed, so let the seed script no-op/copy on cache hits instead of
# force-refreshing `examples/hello` on every `make test`.
# Cross-compiler cold rtobj fills are intentionally refused by default because rolling native
# runtime-object compatibility is not keyed by compiler binary. The stage1 build-compiler argument
# below is therefore only a best-effort compatibility fallback for already-present matching cache
# entries; current host core/full seeds are generated with the requested stage2 compiler.
rtobj-seed: oren_stage2 astbin-seed
			@if [ -n "$(HOST_PLATFORM)" ]; then \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --no-debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --runtime-profile full --no-debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --runtime-profile full --debug || true; \
				./scripts/build_rtobj_seed.sh --platform "$(HOST_PLATFORM)" --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --capsule --no-debug || true; \
			else \
				echo "NOTE: host platform unknown; skipping rtobj seed"; \
		fi

# Generate/update rtobj seed for cross x64 targets (best-effort).
# This keeps `make verify-native-x64-compile` bounded even on a clean cache; the
# verifier keeps full QI / NET/TLS/HTTP2 / broad stage2 FFI sweeps behind explicit
# opt-in envs in `scripts/verify_native_x64_compile_only.sh`.
#
# Warm x64 astbin seeds first so cold capsule rtobj fills can inject the prebuilt runtime astbin
# directly instead of re-expanding the runtime on first miss.
# Cross targets remain best-effort: copy/no-op paths are cheap when compatible cache or fallback
# seed entries already exist, while unsafe stage1-vs-stage2 cold fills are refused by the helper.
rtobj-seed-x64: oren_stage2 astbin-seed-x64
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --runtime-profile full --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-linux --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --runtime-profile full --debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --runtime-profile full --no-debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --debug || true
			@./scripts/build_rtobj_seed.sh --platform x64-windows --compiler "./$(OREN_STAGE2_BIN)" --build-compiler "./$(OREN_BIN)" --runtime-profile full --debug || true
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
test-native-quick: oren avm
				@./scripts/guard_no_external_rg_dependency.sh
				@./scripts/guard_no_msvc_comment_line_continuation.sh
				@./scripts/run_native_quick_integration.sh "./$(OREN_BIN)"

# Fast native smoke (stage2): use stage2 compiler to build+run the same test.
#
# Warm the rtobj seed first: this path builds the quick-integration fixture with `--debug`,
# and the older 180s stage2 build budget now false-reds on healthy self-hosted debug rebuilds
# during the local BL resolve phase, so keep the target aligned with the wider proven headroom.
test-native-quick-stage2: oren_stage2 avm rtobj-seed-quick-stage2
		@OREN_NATIVE_BUILD_TIMEOUT_SECS=240 OREN_NATIVE_RUN_TIMEOUT_SECS=120 \
		  ./scripts/run_native_quick_integration.sh "./$(OREN_STAGE2_BIN)"

# Debug flake triage (stage1): run quick integration loop with spawn ring
# + list header ring guardrails enabled. Not part of default verify/test.
test-native-quick-flake-debug: oren
		@./scripts/triage_native_quick_flake_debug.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): run only the green-cache rerun path with STW/runq guards,
# no hidden inner reruns, and preserve per-run inner + phase logs.
test-native-quick-green-cache-flake: oren
					@./scripts/triage_native_quick_green_cache_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate the intermittent green-cache local-ptr path with
# no hidden inner reruns and a dedicated late-green prelude + stress loop.
test-native-quick-green-local-ptr-flake: oren
						@./scripts/triage_native_quick_green_local_ptr_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): build the mixed-mode local-ptr focused binary once and rerun the
# current blended both-mode slice directly.
test-native-quick-green-local-ptr-direct-flake: oren
						@./scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh 10 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate only the plain local-ptr half of the focused
# green-cache stress slice.
test-native-quick-green-local-ptr-plain-flake: oren
						@./scripts/triage_native_quick_green_local_ptr_plain_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate only the worker-mode local-ptr half of the focused
# green-cache stress slice.
test-native-quick-green-local-ptr-workers-flake: oren
					@./scripts/triage_native_quick_green_local_ptr_workers_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): run the split plain/workers local-ptr slices sequentially.
test-native-quick-green-local-ptr-split-flake: oren
						@./scripts/verify_native_quick_green_local_ptr_modes.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate the current global-runq fairness crash path under
# green-cache-only reruns with no inner retries.
test-native-quick-green-fairness-flake: oren
						@./scripts/triage_native_quick_green_fairness_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): mixed hog+short fairness with zero-arg short spawns,
# without topology. Keep alongside the one-arg slice because the active repro can shift.
test-native-quick-green-fairness-zeroarg-flake: oren
							@OREN_QI_GREEN_FAIRNESS_MODE=full OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=zero_arg OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 OREN_QI_LABEL=native_quick_green_fairness_full_notopology_zeroarg ./scripts/triage_native_quick_green_fairness_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): mixed hog+short fairness with one-arg short spawns,
# without topology. Keep alongside the zero-arg slice because the active repro can shift.
test-native-quick-green-fairness-onearg-flake: oren
								@OREN_QI_GREEN_FAIRNESS_MODE=full OREN_QI_GREEN_FAIRNESS_SHORT_ARG_MODE=one_arg OREN_QI_GREEN_FAIRNESS_INCLUDE_TOPOLOGY=0 OREN_QI_LABEL=native_quick_green_fairness_full_notopology_onearg ./scripts/triage_native_quick_green_fairness_flake.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): direct sharp fairness repro without the broader quick-integration
# harness. This builds the focused fairness binary once and reruns the current h8/s1 one-arg slice.
test-native-quick-green-fairness-onearg-direct-flake: oren
									@./scripts/triage_native_quick_green_fairness_onearg_h8_s1_direct_flake.sh 10 "./$(OREN_BIN)"

# Focused flake triage (stage1): one-arg fairness matrix capturing the leaf control plus the
# mixed no-topology and topology variants in one serial run.
test-native-quick-green-fairness-onearg-modes-flake: oren
										@./scripts/verify_native_quick_green_fairness_onearg_modes.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): sweep mixed one-arg fairness under smaller hog/short counts to
# determine whether the current crash requires only the mixed shape or also enough mixed pressure.
test-native-quick-green-fairness-onearg-count-sweep-flake: oren
										@./scripts/verify_native_quick_green_fairness_onearg_count_sweep.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): split fairness into topology/full, full-only (zero/one-arg
# short spawns), short-only, and hogs-only slices to narrow current scheduler/runtime corruption.
test-native-quick-green-fairness-modes-flake: oren
									@./scripts/verify_native_quick_green_fairness_modes.sh 3 "./$(OREN_BIN)"

# Focused flake triage (stage1): isolate only the base quick-integration pass with per-test trace.
verify-native-quick-base-guarded: oren
						@./scripts/triage_native_quick_base_flake.sh 3 "./$(OREN_BIN)"
						@echo "verify-native-quick-base-guarded OK"

# Focused structural guard: prove the stage2 base quick path uses rtobj seed-hit on an empty
# active runtime cache instead of rebuilding the runtime object from scratch.
verify-native-quick-base-cold-seeded: oren_stage2
							@./scripts/verify_native_quick_base_seeded_cold.sh "./$(OREN_STAGE2_BIN)"
							@echo "verify-native-quick-base-cold-seeded OK"

# Focused structural guard: direct standalone stage2 quick integration must auto-prewarm
# the current runtime seed when active caches and seed dirs start empty. Keep the fixture
# intentionally small so default verification proves the seeded-cold path cheaply.
verify-native-quick-stage2-direct-autoseed: oren oren_stage2
							@./scripts/verify_native_quick_stage2_direct_autoseed.sh "./$(OREN_STAGE2_BIN)"
							@echo "verify-native-quick-stage2-direct-autoseed OK"

# Focused runtime guard (stage1): cover the stronger mixed both-mode local-ptr slice directly,
# while leaving the harness-based blended and split plain/workers surfaces available as triage.
verify-native-quick-green-local-ptr-guarded: oren
						@./scripts/triage_native_quick_green_local_ptr_both_direct_flake.sh 3 "./$(OREN_BIN)"
						@echo "verify-native-quick-green-local-ptr-guarded OK"

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

# Focused runtime guard (stage2): keep the green-only join-waiter repro and the OS-thread control
# split, so STW parked-count regressions cannot hide behind the combined quick-integration bundle.
verify-green-join-waiters-guarded: oren_stage2
	@./scripts/verify_native_quick_green_join_waiters_modes.sh 2 "./$(OREN_STAGE2_BIN)"
	@echo "verify-green-join-waiters-guarded OK"

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

# Native benchmark smoke: alloc_churn len128 specialized entrypoints must agree with the override path.
verify-alloc-churn-len128: oren_stage2
		@./scripts/verify_alloc_churn_len128_smoke.sh

# Runtime robustness smoke: reused alloc_churn list headers must stay tracked across checked ops.
verify-alloc-churn-tracking: oren_stage2
		@./scripts/verify_alloc_churn_tracking_smoke.sh "./$(OREN_STAGE2_BIN)"

# Current triage surface: aggressive alloc_churn GC-reuse / list-header instability reproducer.
triage-alloc-churn-bad-list-current: oren_stage2
			@RUNS="$${RUNS:-10}" BUILD="$${BUILD:-1}" EXTRA_TRACE="$${EXTRA_TRACE:-0}" CRASH_FOOTER="$${CRASH_FOOTER:-1}" \
				REPRO_BAD_LIST_CORRELATE="$${REPRO_BAD_LIST_CORRELATE:-0}" COMPILER="./$(OREN_STAGE2_BIN)" \
				bash ./scripts/repro_bad_list_alloc_churn.sh

# Runtime robustness guard: current alloc_churn broad triage surface must stay clean for the bounded run set.
verify-alloc-churn-broad-current: oren_stage2
			@RUNS="$${RUNS:-10}" BUILD="$${BUILD:-1}" EXTRA_TRACE="$${EXTRA_TRACE:-0}" CRASH_FOOTER="$${CRASH_FOOTER:-1}" \
				REPRO_BAD_LIST_CORRELATE="$${REPRO_BAD_LIST_CORRELATE:-0}" ./scripts/verify_alloc_churn_broad_current.sh "./$(OREN_STAGE2_BIN)"

# Native build cache smoke: build-affecting arm64 fast-list env toggles must invalidate cached artifacts.
verify-build-cache-native-env-surface: oren_stage2
		@./scripts/verify_build_cache_native_env_surface.sh "./$(OREN_STAGE2_BIN)"

# Convenience target: verify stage1 then stage2 on the native quick integration test.
verify-native-quick: test-native-quick test-native-quick-stage2 test-native-capsule-smoke-stage2 verify-native-quick-stage2-direct-autoseed verify-optimizer-list-reserve-branchy verify-alloc-churn-len128 verify-alloc-churn-tracking verify-build-cache-native-env-surface
	@echo "verify-native-quick OK"

# Wrapper smoke: keep ./oretest target mapping aligned with the documented fast/full flows.
verify-oretest:
	@./scripts/verify_oretest_smoke.sh

# Convenience: native quick verify plus SIMD determinism guard.
verify-native-quick-simd: verify-native-quick verify-simd-determinism
	@echo "verify-native-quick-simd OK"

# GC-stress verify: include forced-GC quick integration to catch tracking regressions.
verify-native-quick-gc: verify-native-quick test-native-quick-gc-stress-stage2
	@echo "verify-native-quick-gc OK"

# Guarded scheduler smoke: standalone world-lock repro with poll cache + entry/list tracing.
verify-green-world-lock-guarded: oren_stage2
	@./scripts/triage_green_two_workers_world_lock_smoke.sh 3 "./$(OREN_STAGE2_BIN)" OREN_GREEN_POLL_CACHE=1 OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1 OREN_TRACE_GREEN_ENTRY_ARGS=1 OREN_QI_TRACE_GREEN_LIST=1 OREN_TRACE_GREEN_WORLD_LOCK_SMOKE=1 OREN_TRACE_GREEN_LAST_OPS_EVERY_TICKS=50
	@echo "verify-green-world-lock-guarded OK"

# Guarded scheduler smoke: pre-world-lock quick integration / green-cache path only.
verify-green-preworld-guarded: oren_stage2
		@OREN_QI_STOP_BEFORE_WORLD_LOCK=1 OREN_NATIVE_BUILD_TIMEOUT_SECS=240 OREN_NATIVE_RUN_TIMEOUT_SECS=30 OREN_NATIVE_GREEN_CACHE_RUN_TIMEOUT_SECS=30 ./scripts/triage_stage2_quick_until_world_lock.sh 1 "./$(OREN_STAGE2_BIN)" OREN_TRACE_GREEN_RUNQ_GUARD=1 OREN_TRACE_GREEN_ARGS_STAMP=1
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

# Cross-backend semantic diff: emit machine-readable C/native/OBC result and native/OBC ledger evidence.
verify-backend-semantic-diff: oren_stage2 avm
	@./scripts/verify_backend_semantic_diff.sh

# Cross-backend gas-surface calibration point: same schema as semantic diff, on a loop-heavy fixture.
verify-backend-semantic-diff-gas-calibration: oren_stage2 avm
	@./scripts/verify_backend_semantic_diff.sh tests/fixtures/backend_semantic_diff_gas_calibration.oren

# Cross-backend gas-surface calibration point: same schema as semantic diff, on a branch-heavy fixture.
verify-backend-semantic-diff-gas-branch-calibration: oren_stage2 avm
	@./scripts/verify_backend_semantic_diff.sh tests/fixtures/backend_semantic_diff_gas_branch_calibration.oren

# Cross-backend gas-surface calibration point: same schema as semantic diff, on a function-call-heavy fixture.
verify-backend-semantic-diff-gas-call-calibration: oren_stage2 avm
	@./scripts/verify_backend_semantic_diff.sh tests/fixtures/backend_semantic_diff_gas_call_calibration.oren

# Cross-backend gas-surface calibration point: same schema as semantic diff, on an allocation-heavy fixture.
verify-backend-semantic-diff-gas-alloc-calibration: oren_stage2 avm
	@./scripts/verify_backend_semantic_diff.sh tests/fixtures/backend_semantic_diff_gas_alloc_calibration.oren

# Cross-backend gas-surface calibration set: proves current native/OBC gas ratios are fixture-sensitive evidence, not a conversion rule.
verify-backend-gas-surface-calibration-set: oren_stage2 avm
	@./scripts/verify_backend_gas_surface_calibration_set.sh

# Native instruction-surface decision: rejects whole-binary disasm counts as runtime gas conversion evidence.
verify-backend-native-instruction-surface-decision: oren_stage2 avm
	@./scripts/verify_backend_native_instruction_surface_decision.sh

# Cross-backend parity aggregate: run all parity smokes together.
verify-backend-parity: verify-backend-semantic-diff verify-backend-parity-boxed-list verify-backend-parity-list-int verify-backend-parity-bytes verify-backend-parity-tags verify-backend-parity-arith-panics verify-backend-parity-index-panics
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

verify-capability-runtime-contract:
	@./scripts/verify_capability_runtime_contract.sh

verify-capability-metadata: oren
	@./scripts/verify_capability_metadata.sh

verify-yield-metadata: oren
	@./scripts/verify_yield_metadata.sh

verify-yield-lowering-v0: oren_stage2
	@./scripts/verify_yield_lowering_v0.sh "./$(OREN_STAGE2_BIN)"

verify-yield-backend-parity-v0: oren_stage2 avm
	@./scripts/verify_yield_backend_parity_v0.sh "./$(OREN_STAGE2_BIN)"

verify-yield-value-surface-v0: oren_stage2 avm
	@./scripts/verify_yield_value_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-yield-exchange-surface-v0: oren_stage2 avm
	@./scripts/verify_yield_exchange_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-generator-surface-v0: oren_stage2 avm
	@./scripts/verify_generator_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-coroutine-surface-v0: oren_stage2 avm
	@./scripts/verify_coroutine_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-task-surface-v0: oren_stage2 avm
	@./scripts/verify_task_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-task-group-surface-v0: oren_stage2 avm
	@./scripts/verify_task_group_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-task-group-task-surface-v0: oren_stage2 avm
	@./scripts/verify_task_group_task_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-generator-finalize-surface-v0: oren_stage2
	@./scripts/verify_generator_finalize_surface_v0.sh "./$(OREN_STAGE2_BIN)"

verify-generator-import-yield-regression: oren_stage2
	@./scripts/probe_generator_import_yield_regression.sh "./$(OREN_STAGE2_BIN)"

verify-generator-nested-green-resume-v0: oren_stage2
	@./scripts/verify_generator_nested_green_resume_v0.sh "./$(OREN_STAGE2_BIN)"

verify-capability-manifest-policy: oren
	@./scripts/verify_capability_manifest_policy.sh

verify-effect-ledger-contract: verify-avm-effect-ledger-json
	@./scripts/verify_effect_ledger_contract.sh

verify-avm-effect-ledger-json: oren avm
	@./scripts/verify_avm_effect_ledger_json.sh

verify-avm-package-policy-runner: oren avm
	@./scripts/verify_avm_package_policy_runner.sh

verify-native-package-policy-runner: oren
	@./scripts/verify_native_package_policy_runner.sh

verify-native-capsule-resource-checks: oren
	@./scripts/verify_native_capsule_resource_checks.sh

verify-native-gas-accounting-modes: oren
	@./scripts/verify_native_gas_accounting_modes.sh

verify-gas-surface-registry:
	@./scripts/verify_gas_surface_registry.sh

verify-public-readme-positioning:
	@./scripts/verify_public_readme_positioning.sh

verify-avm-spawn-channel-args: oren avm
	@./scripts/verify_avm_spawn_channel_args.sh

verify-runtime-robustness: oren_stage2
		OREN_RUNTIME_ROBUSTNESS_BASE_RUNS="$(OREN_RUNTIME_ROBUSTNESS_BASE_RUNS)" \
		OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM="$(OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM)" \
		OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_TIMEOUT_SECS)" \
		OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER="$(OREN_RUNTIME_ROBUSTNESS_BASE_PREWARM_BUILD_COMPILER)" \
		OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_BASE_BUILD_TIMEOUT_SECS)" \
		OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS="$(OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUNS)" \
		OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_PREWORLD_BUILD_TIMEOUT_SECS)" \
		OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_PREWORLD_RUN_TIMEOUT_SECS)" \
		OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_PREWORLD_GREEN_CACHE_RUN_TIMEOUT_SECS)" \
	OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS="$(OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS)" \
	OREN_RUNTIME_ROBUSTNESS_STAGE2_BUILD_TIMEOUT_SECS="$(OREN_RUNTIME_ROBUSTNESS_STAGE2_BUILD_TIMEOUT_SECS)" \
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

# Focused W5 perf gate sweep + refresh benchmarks/RESULTS_LATEST.md from the resulting JSONs.
perf-gate-native-refresh-latest: oren_stage2
		@OREN_BENCH_UPDATE_LATEST=1 OREN_BENCH_UPDATE_LATEST_PRUNE=0 ./scripts/run_perf_gate_native.sh

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

perf-probe-list-int-packed-bridge-read-split: oren_stage2
	@./scripts/run_perf_probe_list_int_packed_bridge_read_split.sh

perf-probe-list-int-packed-bridge-simd-reuse: oren_stage2
	@./scripts/run_perf_probe_list_int_packed_bridge_simd_reuse.sh

perf-probe-list-int-i32-buf-dot-ceiling: oren_stage2
	@./scripts/run_perf_probe_list_int_i32_buf_dot_ceiling.sh

perf-probe-list-int-i32-buf-read-split: oren_stage2
	@./scripts/run_perf_probe_list_int_i32_buf_read_split.sh

perf-probe-list-int-i32-buf-simd-reuse: oren_stage2
	@./scripts/run_perf_probe_list_int_i32_buf_simd_reuse.sh

perf-probe-list-int-i32-buf-setup-breakdown: oren_stage2
	@./scripts/run_perf_probe_list_int_i32_buf_setup_breakdown.sh

perf-probe-list-int-i32-buf-unchecked-fill: oren_stage2
	@./scripts/run_perf_probe_list_int_i32_buf_unchecked_fill.sh

perf-probe-list-int-slot-direct: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_direct.sh

perf-probe-list-int-slot-direct-read-split: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_direct_read_split.sh

perf-probe-list-int-slot-surface-read-split: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_surface_read_split.sh

perf-probe-list-int-slot-abi-ceiling: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_abi_ceiling.sh

perf-probe-list-int-slot-direct-fast-tick-decision: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_direct_fast_tick_decision.sh

perf-probe-list-int-slot-direct-pair-loop-decision: oren_stage2
	@./scripts/run_perf_probe_list_int_slot_direct_pair_loop_decision.sh

perf-probe-list-int-c-ceiling: oren_stage2
	@./scripts/run_perf_probe_list_int_c_ceiling.sh

perf-probe-list-int-dot-route-decision: oren_stage2
	@./scripts/run_perf_probe_list_int_dot_route_decision.sh

perf-probe-list-int-array-sum-c-breakdown: oren_stage2
	@./scripts/run_perf_probe_list_int_array_sum_c_breakdown.sh

perf-probe-list-int-fill-share-decision: oren_stage2
	@./scripts/run_perf_probe_list_int_fill_share_decision.sh

perf-probe-list-int-dot-ceiling: oren_stage2
	@./scripts/run_perf_probe_list_int_dot_ceiling.sh

perf-probe-list-int-dot-ceiling-stability: oren_stage2
	@./scripts/run_perf_probe_list_int_dot_ceiling_stability.sh

perf-probe-list-int-specialization-gap: oren_stage2
	@./scripts/run_perf_probe_list_int_specialization_gap.sh

perf-probe-arm64-fast-loop-tick-masks: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_tick_masks.sh

perf-probe-arm64-fast-loop-tick-masks-steady: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_tick_masks_steady.sh

perf-probe-arm64-fast-loop-pair-post: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_pair_post.sh

perf-probe-arm64-fast-loop-prefix-zero: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_loop_prefix_zero.sh

perf-probe-arm64-fast-dot-prefix-zero: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_zero.sh

perf-probe-arm64-fast-dot-prefix-zero-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_zero_list_int.sh

perf-probe-arm64-fast-dot-prefix-pair-loop-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_pair_loop_decision.sh

perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_pair_loop_stability_decision.sh

perf-probe-arm64-fast-dot-prefix-pair-loop-stability-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_pair_loop_stability_decision_list_int.sh

perf-probe-arm64-fast-dot-prefix-zero-specialization: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_prefix_zero_specialization.sh

perf-probe-arm64-fast-dot-single-pair-cursor-regs: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_single_pair_cursor_regs.sh

perf-probe-arm64-fast-dot-single-pair-cursor-regs-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_single_pair_cursor_regs_list_int.sh

perf-probe-arm64-fast-get-sum-single-list-cursor-regs-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_single_list_cursor_regs_list_int.sh

perf-probe-arm64-fast-get-sum-tick-mask-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_tick_mask_list_int.sh

perf-probe-arm64-fast-get-sum-tick-mask-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_tick_mask_decision.sh

perf-probe-arm64-fast-get-sum-unroll2-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_unroll2_list_int.sh

perf-probe-arm64-fast-get-sum-unroll2-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_unroll2_decision.sh

perf-probe-arm64-fast-get-sum-dual-accum-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_dual_accum_list_int.sh

perf-probe-arm64-fast-get-sum-dual-accum-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_dual_accum_decision.sh

perf-probe-arm64-fast-get-sum-pair-post-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_pair_post_list_int.sh

perf-probe-arm64-fast-get-sum-pair-post-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_pair_post_decision.sh

perf-probe-arm64-fast-get-sum-vector-2d-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_get_sum_vector_2d_decision.sh

perf-probe-arm64-whole-list-get-sum-helper-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_whole_list_get_sum_helper_decision.sh

perf-probe-arm64-fast-push-idx-expr-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-idx-expr-cursor-regs-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push idx-expr cursor-regs decision summary' \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=disabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_IDX_EXPR_CURSOR_REGS=0 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-nonneg-linear-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-nonneg-linear-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push nonneg-linear decision summary' \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=disabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR=0 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-nonneg-linear-unroll4-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push nonneg-linear unroll4 decision summary' \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=disabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4=0 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-exact-fill-mix:
	@./scripts/run_perf_probe_arm64_fast_push_exact_fill_mix.sh

perf-probe-arm64-fast-push-single-list-family-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_push_single_list_family_decision.sh

perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_TAG=perf-probe-arm64-fast-push-nonneg-linear-unroll4-single-list-decision \
	 OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_TITLE='arm64 fast list<int> push nonneg-linear unroll4 single-list family decision summary' \
	 OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_VARIANT_LABEL=disabled \
	 OREN_ARM64_FAST_PUSH_SINGLE_LIST_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_NONNEG_LINEAR_UNROLL4=0 \
	 ./scripts/run_perf_probe_arm64_fast_push_single_list_family_decision.sh

perf-probe-arm64-fast-push-tick-mask-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_push_tick_mask_decision.sh

perf-probe-arm64-fast-push-fresh-exact-init-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-fresh-exact-init-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push fresh exact init decision summary' \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=enabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_INIT=1 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-fresh-exact-single-list-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-fresh-exact-single-list-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push fresh exact single-list decision summary' \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=enabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_ARM64_FAST_LIST_INT_PUSH_FRESH_EXACT_SINGLE_LIST=1 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-native-list-hdr-decision: oren_stage2
	@OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TAG=perf-probe-arm64-fast-push-native-list-hdr-decision \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_TITLE='arm64 fast list<int> push native list header trace decision summary' \
	 OREN_PERF_BUILD_USE_CACHE=1 \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_LABEL=trace_enabled \
	 OREN_ARM64_FAST_PUSH_IDX_EXPR_DECISION_VARIANT_ENV=OREN_TRACE_NATIVE_LIST_HDR=1 \
	 ./scripts/run_perf_probe_arm64_fast_push_idx_expr_decision.sh

perf-probe-arm64-fast-push-single-list-cursor-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_push_single_list_cursor_list_int.sh

perf-probe-arm64-fast-dot-unroll2: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_unroll2.sh

perf-probe-arm64-fast-dot-unroll2-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_unroll2_list_int.sh

perf-probe-arm64-fast-dot-dual-accum: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_dual_accum.sh

perf-probe-arm64-fast-dot-dual-accum-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_dual_accum_list_int.sh

perf-probe-arm64-fast-dot-madd-exact: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact.sh

perf-probe-arm64-fast-dot-madd-exact-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact_list_int.sh

perf-probe-arm64-fast-dot-madd-exact-subpaths: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact_subpaths.sh

perf-probe-arm64-fast-dot-madd-exact-list-int-subpaths: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact_list_int_subpaths.sh

perf-probe-arm64-fast-dot-scalar-core-matrix: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_matrix.sh

perf-probe-arm64-fast-dot-scalar-core-matrix-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_matrix_list_int.sh

perf-probe-arm64-fast-dot-scalar-core-read-split: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_read_split.sh

perf-probe-arm64-fast-dot-scalar-core-read-split-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_read_split_list_int.sh

perf-probe-arm64-fast-dot-scalar-core-gate-stability: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_gate_stability.sh

perf-probe-arm64-fast-dot-scalar-core-gate-stability-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_core_gate_stability_list_int.sh

perf-probe-arm64-fast-dot-unroll2-scalar-core-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_unroll2_scalar_core_decision_list_int.sh

perf-probe-arm64-fast-dot-whole-list-helper-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_whole_list_helper_decision.sh

perf-probe-arm64-fast-dot-scalar-post-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_scalar_post_decision_list_int.sh

perf-probe-arm64-fast-dot-pair-post-madd-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_pair_post_madd_decision.sh

perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_pair_post_madd_decision_list_int.sh

perf-probe-arm64-fast-dot-dual-madd-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_dual_madd_decision.sh

perf-probe-arm64-fast-dot-dual-madd-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_dual_madd_decision_list_int.sh

perf-probe-arm64-fast-dot-low32-loads-decision: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_low32_loads_decision.sh

perf-probe-arm64-fast-dot-low32-loads-decision-list-int: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_low32_loads_decision_list_int.sh

perf-probe-arm64-fast-dot-madd-exact-double-sweep: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_madd_exact_double_sweep.sh

perf-probe-arm64-fast-dot-double-exit-snippet: oren_stage2
	@./scripts/run_perf_probe_arm64_fast_dot_double_exit_snippet.sh

perf-probe-arm64-dot-vs-c-loop-compare: oren_stage2
	@./scripts/run_perf_probe_arm64_dot_vs_c_loop_compare.sh

perf-probe-arm64-dot-vs-c-loop-compare-list-int: oren_stage2
	@OREN_ARM64_DOT_VS_C_TAG=perf-probe-arm64-dot-vs-c-loop-compare-list-int \
	 OREN_ARM64_DOT_VS_C_TITLE='arm64 dot_product_int Oren-vs-C loop compare' \
	 OREN_ARM64_DOT_VS_C_PROGRAM=dot_product_int \
	 OREN_ARM64_DOT_VS_C_C_SOURCE=benchmarks/dot_product_int/dot_product_int.c \
	 OREN_ARM64_DOT_VS_C_OREN_PROBE_TARGET=perf-probe-arm64-list-int-hot-loop-disasm \
	 OREN_ARM64_DOT_VS_C_OREN_SUMMARY_PREFIX=perf-probe-arm64-list-int-hot-loop-disasm- \
	 ./scripts/run_perf_probe_arm64_dot_vs_c_loop_compare.sh

perf-probe-arm64-dot-vs-c-scalar-ceiling: oren_stage2
	@./scripts/run_perf_probe_arm64_dot_vs_c_scalar_ceiling.sh

perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int: oren_stage2
	@OREN_ARM64_DOT_CEILING_TAG=perf-probe-arm64-dot-vs-c-scalar-ceiling-list-int \
	 OREN_ARM64_DOT_CEILING_TITLE='arm64 dot_product_int vector-vs-scalar C ceiling probe' \
	 OREN_ARM64_DOT_CEILING_PROGRAM=dot_product_int \
	 OREN_ARM64_DOT_CEILING_OREN_SOURCE=benchmarks/dot_product_int/dot_product_int.oren \
	 OREN_ARM64_DOT_CEILING_C_SOURCE=benchmarks/dot_product_int/dot_product_int.c \
	 ./scripts/run_perf_probe_arm64_dot_vs_c_scalar_ceiling.sh

perf-probe-arm64-native-hot-loop-disasm: oren_stage2
	@./scripts/run_perf_probe_arm64_native_hot_loop_disasm.sh

perf-probe-arm64-list-int-hot-loop-disasm: oren_stage2
	@./scripts/run_perf_probe_arm64_list_int_hot_loop_disasm.sh

perf-probe-arm64-list-int-fill-hot-loop-disasm: oren_stage2
	@./scripts/run_perf_probe_arm64_list_int_fill_hot_loop_disasm.sh

perf-probe-arm64-fill-vs-c-loop-compare: oren_stage2
	@./scripts/run_perf_probe_arm64_fill_vs_c_loop_compare.sh

perf-probe-arm64-dot-acceptance: oren_stage2
	@./scripts/run_perf_probe_arm64_dot_acceptance.sh

perf-probe-arm64-list-int-acceptance: oren_stage2
	@./scripts/run_perf_probe_arm64_list_int_acceptance.sh

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

perf-probe-list-int-specialization-read-split: oren_stage2
	@./scripts/run_perf_probe_list_int_specialization_read_split.sh

perf-probe-list-int-specialization-trace: oren_stage2
	@./scripts/run_perf_probe_list_int_specialization_trace.sh

verify-native-core-packed-bridge: oren_stage2
	@OREN_PERF_SMOKE_LIST_INT_PACKED_BRIDGE_BACKEND=native ./scripts/run_perf_smoke_list_int_packed_bridge.sh

verify-native-slot-direct: oren_stage2
	@./scripts/run_perf_smoke_list_int_slot_direct.sh

verify-native-list-int-fast-lowering: oren_stage2
	@./scripts/verify_native_list_int_fast_lowering.sh
	@./scripts/verify_arm64_dot_madd_scalar_default.sh

verify-native-arm64-dot-madd-scalar-default: oren_stage2
	@./scripts/verify_arm64_dot_madd_scalar_default.sh

verify-native-arm64-dot-prefix-pair-loop-tail: oren_stage2
	@./scripts/verify_arm64_dot_prefix_pair_loop_tail.sh

verify-native-arm64-get-sum-vector-2d-tail: oren_stage2
	@./scripts/verify_arm64_get_sum_vector_2d_tail.sh

verify-native-arm64-slot64-simd-isa:
	@./scripts/verify_arm64_slot64_simd_isa.sh

# Update the latest benchmark snapshot from existing result JSON files.
benchmarks-update:
		@python3 benchmarks/update_latest.py --prune

# Lightweight rolling perf tripwire: ensure rtobj-hit compile-one-file stays under threshold.
perf-guard-native-hit: oren_stage2
		@./scripts/perf_guard_native_compile_one_file_hit.sh

profile-bytecode-codegen: oren_stage2
		@./scripts/profile_bytecode_codegen.sh

profile-native-build-phases: oren_stage2
		@./scripts/profile_native_build_phases.sh

# Default "test" is the fast stage1 native quick smoke.
#
# Keep the heavier curated self-host/surface bundle explicit so the common local gate stays
# aligned with the repo's <3 minute contract. Use `make test-curated`, `make test-selfhost`,
# or `make verify-native-quick` when the stage2/capsule/optimizer/surface coverage is desired.
test: test-native-quick

test-curated: verify-capability-runtime-contract verify-capability-metadata verify-yield-metadata verify-yield-lowering-v0 verify-yield-backend-parity-v0 verify-yield-value-surface-v0 verify-yield-exchange-surface-v0 verify-generator-surface-v0 verify-coroutine-surface-v0 verify-task-surface-v0 verify-task-group-surface-v0 verify-task-group-task-surface-v0 verify-generator-finalize-surface-v0 verify-generator-import-yield-regression verify-generator-nested-green-resume-v0 verify-capability-manifest-policy verify-effect-ledger-contract verify-avm-package-policy-runner verify-native-package-policy-runner verify-native-capsule-resource-checks verify-native-gas-accounting-modes verify-gas-surface-registry verify-public-readme-positioning verify-avm-spawn-channel-args verify-oretest verify-native-quick-stage2-direct-autoseed test-native-quick

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
