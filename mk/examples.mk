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
# - Keep Makefile aware of Tier-1 discrepancies by exercising shared-library output on all Tier-1 targets,
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
