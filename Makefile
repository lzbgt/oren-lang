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
			if ./build/$$name; then \
				echo "FAIL: $$name (Expected panic)"; exit 1; \
			fi; \
		else \
			./oren build $$t --backend native -o build/$$name $(CODESIGN_ARG) $(GC_ARG); \
			./build/$$name || { echo "FAIL: $$name (Exit code $$?)"; exit 1; }; \
		fi \
	done
	@# Module Tests (C Backend)
	@echo "Testing Module System..."
	@./oren build tests/modules/test_shapes.oren --backend c -o build/test_shapes $(CODESIGN_ARG) $(GC_ARG)
	@./build/test_shapes || (echo "FAIL: test_shapes"; exit 1)
	@./oren build tests/modules/test_spawn.oren --backend c -o build/test_spawn $(CODESIGN_ARG) $(GC_ARG)
	@./build/test_spawn || (echo "FAIL: test_spawn"; exit 1)
	@./oren build tests/modules/test_gc_threads.oren --backend c -o build/test_gc_threads $(CODESIGN_ARG) $(GC_ARG)
	@./build/test_gc_threads || (echo "FAIL: test_gc_threads"; exit 1)
	@./oren build tests/modules/test_gc_stack_roots.oren --backend c -o build/test_gc_stack_roots $(CODESIGN_ARG) $(GC_ARG)
	@./build/test_gc_stack_roots || (echo "FAIL: test_gc_stack_roots"; exit 1)
	@echo "All Tests Passed."

# Full Verification: Clean -> Bootstrap -> Stage 1 -> Stage 2 -> Validation
verify: clean oren_stage2
	@echo "=== Verifying Stage 2 Compiler ==="
	@mkdir -p build
	@./oren_stage2 build tests/native/func.oren --backend native -o build/func_stage2 $(CODESIGN_ARG) $(GC_ARG)
	@./build/func_stage2 || (echo "FAIL: Stage 2 Verification"; exit 1)
	@echo "Verification Successful: Stage 2 is functional."

# --- AVM (experimental) ---

avm: lib/avm/main.c lib/avm/avm.c lib/avm/avm.h
	@echo "Building AVM..."
	$(CC) -O2 -o avm lib/avm/main.c lib/avm/avm.c

# --- Examples (verification) ---

examples-test: oren avm
	@echo "=== Running Examples ==="
	@mkdir -p build
	@# 1) C backend hello + modules + threading
	@./oren build examples/hello_c.oren --backend c -o build/ex_hello_c $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_hello_c
	@./oren build examples/module_app.oren --backend c -o build/ex_module_app $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_module_app
	@./oren build examples/spawn_c.oren --backend c -o build/ex_spawn_c $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_spawn_c
	@# 2) Native backend GC + FFI
	@./oren build examples/gc_native.oren --backend native -o build/ex_gc_native $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_gc_native
	@./oren build examples/ffi_test.oren --backend native -o build/ex_ffi_puts $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_ffi_puts >/dev/null
	@# 3) Native dylib export + header + scan + link
	@./oren build examples/libmath.oren --backend native --lib -o build/libmath.dylib $(CODESIGN_ARG) $(GC_ARG) --metadata
	@test -f build/libmath.h
	@./oren scan build/libmath.dylib >/dev/null
	@./oren build examples/ffi_from_libmath.oren --backend native --link build/libmath.dylib -o build/ex_ffi_from_libmath $(CODESIGN_ARG) $(GC_ARG)
	@./build/ex_ffi_from_libmath
	@# 4) Bytecode + AVM
	@./oren build examples/hello.oren --backend bytecode -o build/ex_hello.obc
	@./avm build/ex_hello.obc >/dev/null
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
