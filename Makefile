.PHONY: all clean bootstrap test verify stage1 stage2

# Default target: Build Stage 1 compiler
all: oren

# Platform settings
UNAME_S := $(shell uname -s)
CODESIGN_IDENTITY ?= Developer ID Application: Zongbao Lu (US56HHF2Y4)
ifeq ($(UNAME_S),Darwin)
  CODESIGN_ARG := --codesign "$(CODESIGN_IDENTITY)"
else
  CODESIGN_ARG :=
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

# --- Build Stages ---

# Stage 0: Bootstrap Compiler (Go)
oren_bootstrap: $(GO_SRC)
	@echo "Building Stage 0 (Bootstrap)..."
	go build -o oren_bootstrap ./cmd/oren

# Stage 1: Self-Hosted Compiler (Built by Stage 0)
oren: oren_bootstrap $(OREN_SRC)
	@echo "Building Stage 1 (Oren)..."
	./oren_bootstrap build $(OREN_SRC) $(CODESIGN_ARG) $(GC_ARG)

# Stage 2: Self-Hosted Compiler (Built by Stage 1)
oren_stage2: oren $(OREN_SRC)
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
	@for t in tests/native/*.oren; do \
		name=$$(basename $$t .oren); \
		echo "Testing $$name..."; \
		if [ "$$name" = "linux_hello" ]; then \
			./oren build $$t --backend native -o build/$$name --target linux $(CODESIGN_ARG) $(GC_ARG); \
			file build/$$name | grep -q "ELF" || (echo "FAIL: $$name (No ELF)"; exit 1); \
		else \
			./oren build $$t --backend native -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			./build/$$name || (echo "FAIL: $$name (Exit code $$?)"; exit 1); \
		fi \
	done
	@# Module Tests (C Backend)
	@echo "Testing Module System..."
	@./oren build tests/modules/test_shapes.oren --backend c -o build/test_shapes $(CODESIGN_ARG) $(GC_ARG)
	@./build/test_shapes || (echo "FAIL: test_shapes"; exit 1)
	@echo "All Tests Passed."

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./oren_stage2 build tests/native/func.oren --backend native -o build/func_stage2 $(CODESIGN_ARG) $(GC_ARG)
	@./build/func_stage2 || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- Cleanup ---

clean:
	@echo "Cleaning workspace..."
	rm -rf oren_bootstrap oren oren_stage2 build/ *.c *.dSYM verify_full.sh run_tests.sh
