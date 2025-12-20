package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

// oretest is the repo test runner.
//
// SOLID constraint: keep repo test orchestration out of the self-hosted compiler
// sources (lib/compiler/*.oren). This tool shells out to:
// - ./oren (stage1 self-hosted compiler) for compilation
// - ./avm (C-based VM) for running .obc tests
//
// It is macOS-first but avoids assumptions that would block Linux later.

type testCase struct {
	kind string // native|module|avm|fixture
	name string
	path string
}

type testResult struct {
	tc  testCase
	ok  bool
	log string
	msg string
}

type syscallBlock struct {
	sysNames []string
	text     string
}

func main() {
	var (
		target  = flag.String("target", "macos", "native backend target: macos|linux")
		noGC    = flag.Bool("no-gc", os.Getenv("OREN_NO_GC") != "", "disable GC scanning (also via env OREN_NO_GC=1)")
		jobs    = flag.Int("jobs", envInt("OREN_TEST_JOBS", runtime.NumCPU()), "parallel jobs for module+avm tests (env OREN_TEST_JOBS)")
		full    = flag.Bool("full", envBool("OREN_TEST_FULL", false), "run the full curated suite (env OREN_TEST_FULL=1)")
		verbose = flag.Bool("verbose", envBool("OREN_TEST_VERBOSE", false), "print per-test progress (env OREN_TEST_VERBOSE=1)")
	)
	flag.Parse()

	if *jobs < 1 {
		*jobs = 1
	}
	if *jobs > 32 {
		*jobs = 32
	}

	timeoutBin := detectTimeoutBin()
	if timeoutBin == "" {
		// Not fatal: we implement our own process-group kill based timeout.
		// On macOS, GNU coreutils `gtimeout` is not installed by default.
		fmt.Fprintln(os.Stderr, "WARN: `timeout`/`gtimeout` not found; oretest will use internal timeouts only.")
	}

	if _, err := os.Stat("./oren"); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: ./oren not found; run `make stage1` or `make test`.")
		os.Exit(2)
	}
	if _, err := os.Stat("./avm"); err != nil {
		// AVM is required for AVM tests; Makefile builds it before invoking oretest.
		fmt.Fprintln(os.Stderr, "ERROR: ./avm not found; run `make avm`.")
		os.Exit(2)
	}
	orenPath, _ := filepath.Abs("./oren")
	avmPath, _ := filepath.Abs("./avm")

	_ = os.MkdirAll("build/logs", 0o755)
	_ = os.MkdirAll("build/tmp", 0o755)

	// Timeouts: iteration-friendly defaults.
	buildTimeout := 60 * time.Second
	if *jobs > 1 {
		// Parallel builds can contend for CPU and take longer.
		buildTimeout = 120 * time.Second
	}
	runTimeout := 10 * time.Second

	gcArg := ""
	if *noGC {
		gcArg = " --no-gc"
	}

	var printMu sync.Mutex
	vprintln := func(msg string) {
		if !*verbose {
			return
		}
		printMu.Lock()
		defer printMu.Unlock()
		fmt.Println(msg)
	}

	if err := auditNativeCapsuleSyscallPrehooks(); err != nil {
		fmt.Fprintln(os.Stderr, "capsule audit failed:", err)
		os.Exit(1)
	}
	if err := auditNativeNoDirectSvcBypass(); err != nil {
		fmt.Fprintln(os.Stderr, "svc audit failed:", err)
		os.Exit(1)
	}

	// Curated lists: keep small and integration-first.
	nativeTests := []string{
		"tests/native/test_integration_suite.oren",
		"tests/native/test_sys_execve_fail_safe.oren",
		"tests/native/test_debug_panic.oren",
	}
	moduleTestsFast := []string{
		// Core language / execution sanity (C backend).
		"tests/modules/test_spawn_join_timeout.oren",
		"tests/modules/test_lambda_multiline.oren",
		"tests/modules/test_trait_impl.oren",
		"tests/modules/test_trait_qualified_calls.oren",
		"tests/modules/test_trait_cross_module_calls.oren",
		"tests/modules/test_trait_blanket_impl_any.oren",
		"tests/modules/test_optimizer_baseline.oren",
		"tests/modules/test_match_enum.oren",
		"tests/modules/test_int_ops_wrap.oren",
		// Typed annotations and packed views (critical for syscall-first parsing).
		"tests/modules/test_type_ann_fn_boundaries.oren",
		"tests/modules/test_typed_struct_fields.oren",
		"tests/modules/test_pack_view.oren",
		// ABI layouts (curated, no host headers).
		"tests/modules/test_abi_layout.oren",
		"tests/modules/test_abi_ptr_access.oren",
		"tests/modules/test_abi_socket_structs_v5.oren",
		// Stdlib building blocks.
		"tests/modules/test_result.oren",
		"tests/modules/test_argparse.oren",
		"tests/modules/test_json.oren",
		"tests/modules/test_varargs.oren",
	}
	moduleTestsFull := []string{
		"tests/modules/test_shapes.oren",
		"tests/modules/test_spawn.oren",
		"tests/modules/test_spawn_join_timeout.oren",
		"tests/modules/test_read_bytes.oren",
		"tests/modules/test_bytes_set_endian.oren",
		"tests/modules/test_int_casts.oren",
		"tests/modules/test_int_casts_checked.oren",
		"tests/modules/test_int_ops_wrap.oren",
		"tests/modules/test_float_ops.oren",
		"tests/modules/test_typed_struct_fields.oren",
		"tests/modules/test_type_ann_fn_boundaries.oren",
		"tests/modules/test_abi_layout.oren",
		"tests/modules/test_abi_ptr_access.oren",
		"tests/modules/test_abi_nested_arrays.oren",
		"tests/modules/test_abi_u128_layout.oren",
		"tests/modules/test_abi_sockaddr_in.oren",
		"tests/modules/test_abi_kevent.oren",
		"tests/modules/test_abi_stat.oren",
		"tests/modules/test_abi_epoll_event.oren",
		"tests/modules/test_abi_socket_structs_v5.oren",
		"tests/modules/test_function_values.oren",
		"tests/modules/test_lambda_closure.oren",
		"tests/modules/test_lambda_multiline.oren",
		"tests/modules/test_trait_impl.oren",
		"tests/modules/test_trait_qualified_calls.oren",
		"tests/modules/test_trait_cross_module_calls.oren",
		"tests/modules/test_trait_blanket_impl_any.oren",
		"tests/modules/test_optimizer_baseline.oren",
		"tests/modules/test_enum.oren",
		"tests/modules/test_match_enum.oren",
		"tests/modules/test_endian_casts.oren",
		"tests/modules/test_pack_view.oren",
		"tests/modules/test_gc_threads.oren",
		"tests/modules/test_gc_stack_roots.oren",
		"tests/modules/test_result.oren",
		"tests/modules/test_argparse.oren",
		"tests/modules/test_build_target_arch.oren",
		"tests/modules/test_strings.oren",
		"tests/modules/test_string_from_bytes.oren",
		"tests/modules/test_json.oren",
		"tests/modules/test_switch.oren",
		"tests/modules/test_varargs.oren",
	}
	avmTestsFast := []string{
		"tests/avm/test_smoke_suite.oren",
		"tests/avm/test_snapshot_resume.oren",
		"tests/avm/test_multiverse_invalid_obc.oren",
		"tests/avm/test_time_rng_deterministic.oren",
		"tests/avm/test_budget_timeout.oren",
		"tests/avm/test_call_depth_limit.oren",
		"tests/avm/test_arith_invalid.oren",
		"tests/avm/test_vfs_no_host_fs.oren",
		"tests/avm/test_vproc_no_host_proc.oren",
		"tests/avm/test_vnet_no_host_net.oren",
		"tests/avm/test_varargs_spawn.oren",
	}
	avmTestsFull := []string{
		"tests/avm/test_smoke_suite.oren",
		"tests/avm/test_spawn_join_timeout.oren",
		"tests/avm/test_policy_scan.oren",
		"tests/avm/test_job_scan.oren",
		"tests/avm/test_snapshot_resume.oren",
		"tests/avm/test_multiverse_invalid_obc.oren",
		"tests/avm/test_multiverse_vfs_inherit.oren",
		"tests/avm/test_fs_mounts_host_backend.oren",
		"tests/avm/test_fs_helpers_vfs.oren",
		"tests/avm/test_time_rng_deterministic.oren",
		"tests/avm/test_time_rng_record_replay_mem.oren",
		"tests/avm/test_budget_gas.oren",
		"tests/avm/test_budget_timeout.oren",
		"tests/avm/test_call_depth_limit.oren",
		"tests/avm/test_arith_invalid.oren",
		"tests/avm/test_vfs_no_host_fs.oren",
		"tests/avm/test_vproc_no_host_proc.oren",
		"tests/avm/test_vnet_no_host_net.oren",
		"tests/avm/test_oren_env_bridge_capsule.oren",
		"tests/avm/test_varargs_spawn.oren",
	}

	moduleTests := moduleTestsFast
	avmTests := avmTestsFast
	if *full {
		moduleTests = moduleTestsFull
		avmTests = avmTestsFull
	}

	// Compile-fail fixtures (portable semantics guards).
	fixtures := []struct {
		name    string
		cmd     string
		log     string
		ok      func(rc int) bool
		cleanup []string
	}{
		{
			name: "deterministic_bytecode_hash",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --target %s --deterministic -o %q > %q && "+
					"./oren build %q --backend bytecode --target %s --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=bytecode sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=bytecode sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/modules/test_strings.oren",
				*target,
				"build/deterministic_1.obc",
				"build/deterministic_1.out",
				"tests/modules/test_strings.oren",
				*target,
				"build/deterministic_2.obc",
				"build/deterministic_2.out",
				"build/deterministic_1.out",
				"build/deterministic_1.hash",
				"build/deterministic_2.out",
				"build/deterministic_2.hash",
				"build/deterministic_1.hash",
				"build/deterministic_2.hash",
			),
			log:     "build/logs/deterministic_bytecode_hash.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/deterministic_1.obc", "build/deterministic_2.obc", "build/deterministic_1.out", "build/deterministic_2.out", "build/deterministic_1.hash", "build/deterministic_2.hash"},
		},
		{
			name: "oren_meta_emit",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				*target,
				"build/meta_attrs.meta.json",
				"f: doc line 1",
				"build/meta_attrs.meta.json",
				"\"name\": \"Reader\"",
				"build/meta_attrs.meta.json",
				"serde.rename",
				"build/meta_attrs.meta.json",
				"\"traits\": [",
				"build/meta_attrs.meta.json",
			),
			log:     "build/logs/oren_meta_emit.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/meta_attrs.meta.json"},
		},
		{
			name: "deterministic_meta_hash",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --deterministic -o %q > %q && "+
					"./oren meta %q --target %s --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				*target,
				"build/deterministic_meta_1.meta.json",
				"build/deterministic_meta_1.out",
				"tests/fixtures/meta_attrs_src.oren",
				*target,
				"build/deterministic_meta_2.meta.json",
				"build/deterministic_meta_2.out",
				"build/deterministic_meta_1.out",
				"build/deterministic_meta_1.hash",
				"build/deterministic_meta_2.out",
				"build/deterministic_meta_2.hash",
				"build/deterministic_meta_1.hash",
				"build/deterministic_meta_2.hash",
			),
			log:     "build/logs/deterministic_meta_hash.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/deterministic_meta_1.meta.json", "build/deterministic_meta_2.meta.json", "build/deterministic_meta_1.out", "build/deterministic_meta_2.out", "build/deterministic_meta_1.hash", "build/deterministic_meta_2.hash"},
		},
		{
			name: "deterministic_native_meta_hash",
			cmd: fmt.Sprintf(
				"./oren build %q --backend native --target %s --metadata --deterministic -o %q > %q && "+
					"./oren build %q --backend native --target %s --metadata --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/modules/test_strings.oren",
				*target,
				"build/deterministic_native_meta_1",
				"build/deterministic_native_meta_1.out",
				"tests/modules/test_strings.oren",
				*target,
				"build/deterministic_native_meta_2",
				"build/deterministic_native_meta_2.out",
				"build/deterministic_native_meta_1.out",
				"build/deterministic_native_meta_1.hash",
				"build/deterministic_native_meta_2.out",
				"build/deterministic_native_meta_2.hash",
				"build/deterministic_native_meta_1.hash",
				"build/deterministic_native_meta_2.hash",
			),
			log:     "build/logs/deterministic_native_meta_hash.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/deterministic_native_meta_1",
				"build/deterministic_native_meta_1.meta.json",
				"build/deterministic_native_meta_1.out",
				"build/deterministic_native_meta_1.hash",
				"build/deterministic_native_meta_2",
				"build/deterministic_native_meta_2.meta.json",
				"build/deterministic_native_meta_2.out",
				"build/deterministic_native_meta_2.hash",
			},
		},
		{
			name: "compiler_parse_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=parse code=1\"'",
				"tests/native/fixtures/parse_error.oren",
				*target,
				"build/parse_error",
				gcArg,
			),
			log:     "build/logs/compiler_parse_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/parse_error"},
		},
		{
			name: "compiler_codegen_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend native --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"'",
				"tests/native/fixtures/codegen_error.oren",
				*target,
				"build/codegen_error",
				gcArg,
			),
			log:     "build/logs/compiler_codegen_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/codegen_error"},
		},
		{
			name: "compiler_bytecode_codegen_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend bytecode --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\n\" \"$out\"; test $rc -ne 0; printf \"%%s\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"; printf \"%%s\n\" \"$out\" | grep -F \"Bytecode codegen errors:\"'",
				"tests/native/fixtures/bytecode_codegen_error.oren",
				*target,
				"build/bytecode_codegen_err.obc",
				gcArg,
			),
			log:     "build/logs/compiler_bytecode_codegen_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/bytecode_codegen_err.obc"},
		},
		{
			name: "compiler_impl_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"'",
				"tests/native/fixtures/trait_impl_duplicate.oren",
				*target,
				"build/impl_err",
				gcArg,
			),
			log:     "build/logs/compiler_impl_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/impl_err"},
		},
		{
			name: "compiler_packview_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"Packview errors:\"'",
				"tests/native/fixtures/packview_error.oren",
				*target,
				"build/packview_err",
				gcArg,
			),
			log:     "build/logs/compiler_packview_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/packview_err"},
		},
		{
			name: "compiler_abi_layout_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"ABI layout errors:\"'",
				"tests/native/fixtures/abi_layout_error.oren",
				*target,
				"build/abi_layout_err",
				gcArg,
			),
			log:     "build/logs/compiler_abi_layout_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/abi_layout_err"},
		},
		{
			name: "missing_file_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"'",
				"tests/native/fixtures/__missing__.oren",
				*target,
				"build/missing_file",
				gcArg,
			),
			log:     "build/logs/missing_file_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/missing_file"},
		},
		{
			name: "unknown_backend_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend %q --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"; printf \"%%s\\n\" \"$out\" | grep -F \"Unknown backend:\"'",
				"tests/modules/test_strings.oren",
				"nope",
				*target,
				"build/unknown_backend",
				gcArg,
			),
			log:     "build/logs/unknown_backend_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/unknown_backend"},
		},
		{
			name: "dump_tokens_missing_file_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren dump tokens %q -o %q --target %s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"'",
				"tests/native/fixtures/__missing__.oren",
				"build/dump_tokens_missing.json",
				*target,
			),
			log:     "build/logs/dump_tokens_missing_file_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/dump_tokens_missing.json"},
		},
		{
			name: "build_missing_target_value_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"; printf \"%%s\\n\" \"$out\" | grep -F \"Missing value for --target\"'",
				"tests/modules/test_strings.oren",
			),
			log:     "build/logs/build_missing_target_value_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{},
		},
		{
			name: "build_emit_c_with_native_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend native --emit-c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"; printf \"%%s\\n\" \"$out\" | grep -F -- \"--emit-c is only supported\"'",
				"tests/modules/test_strings.oren",
				*target,
				"build/emit_c_native_bad",
				gcArg,
			),
			log:     "build/logs/build_emit_c_with_native_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/emit_c_native_bad"},
		},
		{
			name:    "strict_attrs_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --strict-attrs --attr-allow-prefixes myorg.%s", "tests/native/fixtures/strict_attrs_ok.oren", *target, "build/strict_attrs_ok", gcArg),
			log:     "build/logs/strict_attrs_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/strict_attrs_ok"},
		},
		{
			name:    "strict_attrs_bad",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --strict-attrs%s", "tests/native/fixtures/strict_attrs_bad.oren", *target, "build/strict_attrs_bad", gcArg),
			log:     "build/logs/strict_attrs_bad.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/strict_attrs_bad"},
		},
		{
			name:    "struct_field_assign_bad",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", "tests/native/fixtures/struct_field_assign_bad.oren", *target, "build/struct_field_assign_bad", gcArg),
			log:     "build/logs/struct_field_assign_bad.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/struct_field_assign_bad"},
		},
		{
			name:    "trait_impl_ambiguous_method",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_ambiguous_method.oren", *target, "build/trait_impl_ambiguous_method", gcArg),
			log:     "build/logs/trait_impl_ambiguous_method.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_ambiguous_method"},
		},
		{
			name:    "trait_impl_duplicate",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_duplicate.oren", *target, "build/trait_impl_duplicate", gcArg),
			log:     "build/logs/trait_impl_duplicate.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_duplicate"},
		},
		{
			name:    "trait_impl_split_blocks",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_split_blocks.oren", *target, "build/trait_impl_split_blocks", gcArg),
			log:     "build/logs/trait_impl_split_blocks.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_split_blocks"},
		},
		{
			name:    "capsule_ok_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_ok.oren", *target, "build/capsule_ok", gcArg),
			log:     "build/logs/capsule_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/capsule_ok"},
		},
		{
			name:    "capsule_bad_syscall_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_syscall.oren", *target, "build/capsule_bad_syscall", gcArg),
			log:     "build/logs/capsule_bad_syscall.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/capsule_bad_syscall"},
		},
		{
			name:    "capsule_bad_fs_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_fs.oren", *target, "build/capsule_bad_fs", gcArg),
			log:     "build/logs/capsule_bad_fs.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/capsule_bad_fs"},
		},
		{
			name:    "capsule_ok_fs_allow_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule --cap-allow-domains FS%s", "tests/native/fixtures/capsule_ok_fs_allow.oren", *target, "build/capsule_ok_fs_allow", gcArg),
			log:     "build/logs/capsule_ok_fs_allow.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/capsule_ok_fs_allow"},
		},
	}

	// Runtime diagnostics fixtures (expected non-zero exit, machine-readable header).
	runtimeFixtures := []struct {
		name    string
		build   string
		run     string
		log     string
		ok      func(rc int, out string) bool
		cleanup []string
	}{
		{
			name:  "diag_fail_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", "tests/native/fixtures/diag_fail.oren", *target, "build/diag_fail_native", gcArg),
			run:   "./build/diag_fail_native",
			log:   "build/logs/diag_fail_native.log",
			ok: func(rc int, out string) bool {
				return rc == 42 && strings.Contains(out, "OREN_DIAG kind=fail code=42")
			},
			cleanup: []string{"build/diag_fail_native"},
		},
		{
			name:  "diag_fail_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/diag_fail.oren", *target, "build/diag_fail_c", gcArg),
			run:   "./build/diag_fail_c",
			log:   "build/logs/diag_fail_c.log",
			ok: func(rc int, out string) bool {
				return rc == 42 && strings.Contains(out, "OREN_DIAG kind=fail code=42")
			},
			cleanup: []string{"build/diag_fail_c"},
		},
	}

	// Run fixtures sequentially (fast, high-signal).
	for _, fx := range fixtures {
		vprintln("fixture: " + fx.name)
		rc := runWithTimeout(timeoutBin, buildTimeout, fx.cmd, fx.log)
		for _, c := range fx.cleanup {
			_ = os.Remove(c)
		}
		if !fx.ok(rc) {
			fmt.Fprintf(os.Stderr, "fixture failed: %s (log: %s)\n", fx.name, fx.log)
			_ = catFile(os.Stderr, fx.log)
			os.Exit(1)
		}
	}

	// Run runtime diagnostics fixtures sequentially.
	for _, fx := range runtimeFixtures {
		vprintln("runtime fixture: " + fx.name)
		rc := runWithTimeout(timeoutBin, buildTimeout, fx.build, fx.log)
		if rc != 0 {
			fmt.Fprintf(os.Stderr, "runtime fixture build failed: %s (log: %s)\n", fx.name, fx.log)
			_ = catFile(os.Stderr, fx.log)
			os.Exit(1)
		}
		rc2 := runWithTimeout(timeoutBin, runTimeout, fx.run, fx.log)
		outb, _ := os.ReadFile(fx.log)
		if !fx.ok(rc2, string(outb)) {
			fmt.Fprintf(os.Stderr, "runtime fixture failed: %s (log: %s)\n", fx.name, fx.log)
			_ = catFile(os.Stderr, fx.log)
			os.Exit(1)
		}
		for _, c := range fx.cleanup {
			_ = os.Remove(c)
		}
	}

	// Native tests: compile+run sequentially (low count, avoids over-parallelizing codesign).
	nativeRes := runNativeTests(timeoutBin, *target, gcArg, buildTimeout, runTimeout, *verbose, vprintln, nativeTests)
	if !nativeRes.ok {
		os.Exit(1)
	}

	// Module + AVM tests: parallel for wall-time reduction.
	//
	// NOTE: These suites can run concurrently, but they must share the same total
	// job budget. If we ran both at `jobs`, we'd oversubscribe CPU (2*jobs) and
	// often get slower wall time.
	moduleJobs := *jobs / 2
	if moduleJobs < 1 {
		moduleJobs = 1
	}
	avmJobs := *jobs - moduleJobs
	if avmJobs < 1 {
		avmJobs = 1
	}

	var (
		moduleRes suiteResult
		avmRes    suiteResult
		wgSuites  sync.WaitGroup
	)
	wgSuites.Add(2)
	go func() {
		defer wgSuites.Done()
		moduleRes = runModuleTestsParallel(timeoutBin, *target, gcArg, buildTimeout, runTimeout, *verbose, vprintln, moduleJobs, moduleTests)
	}()
	go func() {
		defer wgSuites.Done()
		avmRes = runAVMTestsParallel(timeoutBin, orenPath, avmPath, gcArg, buildTimeout, runTimeout, *verbose, vprintln, avmJobs, avmTests)
	}()
	wgSuites.Wait()

	fmt.Printf("%d/%d native tests passed\n", nativeRes.pass, nativeRes.total)
	fmt.Printf("%d/%d module tests passed\n", moduleRes.pass, moduleRes.total)
	fmt.Printf("%d/%d avm tests passed\n", avmRes.pass, avmRes.total)

	if len(moduleRes.failed) > 0 {
		fmt.Println("module failed:")
		for _, f := range moduleRes.failed {
			fmt.Printf("  %s (log: %s)\n", f.tc.path, f.log)
			_ = catFile(os.Stdout, f.log)
		}
		os.Exit(1)
	}
	if len(avmRes.failed) > 0 {
		fmt.Println("avm failed:")
		for _, f := range avmRes.failed {
			fmt.Printf("  %s (log: %s)\n", f.tc.path, f.log)
			_ = catFile(os.Stdout, f.log)
		}
		os.Exit(1)
	}

	fmt.Println("All Tests Passed.")
}

func shouldValidateSIMD() bool {
	// SIMD validation is only meaningful when the test runner itself is on arm64.
	// (On non-arm64 hosts, NEON isn't available, and SIMD paths are compiled out.)
	return runtime.GOARCH == "arm64"
}

type suiteResult struct {
	ok     bool
	pass   int
	total  int
	failed []testResult
}

func runNativeTests(timeoutBin, target, gcArg string, buildTimeout, runTimeout time.Duration, verbose bool, vprintln func(string), tests []string) suiteResult {
	res := suiteResult{ok: true, total: len(tests)}
	for _, path := range tests {
		name := strings.TrimSuffix(filepath.Base(path), ".oren")
		if verbose {
			vprintln("native: " + path)
		}
		out := filepath.Join("build", name)
		log := filepath.Join("build", "logs", "native_"+name+".log")
		buildCmd := fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", path, target, out, gcArg)
		if rc := runWithTimeout(timeoutBin, buildTimeout, buildCmd, log); rc != 0 {
			res.ok = false
			res.failed = append(res.failed, testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log})
			continue
		}
		rc := runWithTimeout(timeoutBin, runTimeout, fmt.Sprintf("./%s", out), log)
		_ = os.Remove(out)
		if name == "test_debug_panic" {
			// Expected-failure regression: panic output must be readable and include a stack trace.
			// We accept any non-zero exit except external timeout.
			if rc == 0 || rc == 124 {
				res.ok = false
				res.failed = append(res.failed, testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log})
				continue
			}
			outb, err := os.ReadFile(log)
			if err != nil {
				res.ok = false
				res.failed = append(res.failed, testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log})
				continue
			}
			s := string(outb)
			if !strings.Contains(s, "Traceback") || !strings.Contains(s, "crash_me") {
				res.ok = false
				res.failed = append(res.failed, testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log})
				continue
			}
		} else {
			if rc != 0 {
				res.ok = false
				res.failed = append(res.failed, testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log})
				continue
			}
		}
		res.pass++
	}
	if !res.ok {
		fmt.Println("native failed:")
		for _, f := range res.failed {
			fmt.Printf("  %s (log: %s)\n", f.tc.path, f.log)
			_ = catFile(os.Stdout, f.log)
		}
	}
	return res
}

func runModuleTestsParallel(timeoutBin, target, gcArg string, buildTimeout, runTimeout time.Duration, verbose bool, vprintln func(string), jobs int, tests []string) suiteResult {
	res := suiteResult{ok: true, total: len(tests)}
	results := runParallel(jobs, tests, func(path string) testResult {
		name := strings.TrimSuffix(filepath.Base(path), ".oren")
		if verbose {
			vprintln("module: " + path)
		}
		workdir := filepath.Join("build", "tmp", "mod_"+name)
		_ = os.RemoveAll(workdir)
		_ = os.MkdirAll(filepath.Join(workdir, "build"), 0o755)
		log := filepath.Join("build", "logs", "mod_"+name+".log")

		out := filepath.Join(workdir, "build", name)
		// IMPORTANT: pass `--target` explicitly so running oretest on Linux doesn't
		// default to macOS and attempt codesigning.
		buildCmd := fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", path, target, out, gcArg)
		if rc := runWithTimeout(timeoutBin, buildTimeout, buildCmd, log); rc != 0 {
			return testResult{tc: testCase{kind: "module", name: name, path: path}, ok: false, log: log}
		}
		if rc := runWithTimeout(timeoutBin, runTimeout, out, log); rc != 0 {
			return testResult{tc: testCase{kind: "module", name: name, path: path}, ok: false, log: log}
		}
		_ = os.Remove(out)
		return testResult{tc: testCase{kind: "module", name: name, path: path}, ok: true, log: log}
	})
	for _, r := range results {
		if r.ok {
			res.pass++
		} else {
			res.ok = false
			res.failed = append(res.failed, r)
		}
	}
	return res
}

func runAVMTestsSequential(timeoutBin, gcArg string, buildTimeout, runTimeout time.Duration, tests []string) suiteResult {
	res := suiteResult{ok: true, total: len(tests)}
	_ = os.MkdirAll("build", 0o755)
	for _, path := range tests {
		name := strings.TrimSuffix(filepath.Base(path), ".oren")
		log := filepath.Join("build", "logs", "avm_"+name+".log")
		obc := filepath.Join("build", name+".obc")

		buildCmd := fmt.Sprintf("./oren build %q --backend bytecode -o %q%s", path, obc, gcArg)
		if rc := runWithTimeout(timeoutBin, buildTimeout, buildCmd, log); rc != 0 {
			res.ok = false
			res.failed = append(res.failed, testResult{tc: testCase{kind: "avm", name: name, path: path}, ok: false, log: log})
			_ = os.Remove(obc)
			continue
		}

		runOK := true
		switch name {
		case "test_smoke_suite":
			// Determinism guard (same host, same binary, repeated run).
			//
			// This catches:
			// - uninitialized memory included in hashing
			// - pointer-order dependence in RESULT_HASH / TRACE_HASH
			cmd1 := fmt.Sprintf("./avm --print-result-hash --print-trace-hash %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd1, log); rc != 0 {
				runOK = false
				break
			}
			scalarResultHash, okR := extractHashFromLog(log, "RESULT_HASH")
			scalarTraceHash, okT := extractHashFromLog(log, "TRACE_HASH")
			if !okR || !okT {
				_ = appendFileLine(log, "oretest: missing RESULT_HASH/TRACE_HASH in scalar run output")
				runOK = false
				break
			}

			rerunLog := filepath.Join("build", "logs", "avm_"+name+"_rerun.log")
			_ = os.Remove(rerunLog)
			cmd2 := fmt.Sprintf("./avm --print-result-hash --print-trace-hash %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd2, rerunLog); rc != 0 {
				runOK = false
				log = rerunLog
				break
			}
			rerunResultHash, okR2 := extractHashFromLog(rerunLog, "RESULT_HASH")
			rerunTraceHash, okT2 := extractHashFromLog(rerunLog, "TRACE_HASH")
			if !okR2 || !okT2 {
				_ = appendFileLine(rerunLog, "oretest: missing RESULT_HASH/TRACE_HASH in rerun output")
				runOK = false
				log = rerunLog
				break
			}
			if rerunResultHash != scalarResultHash || rerunTraceHash != scalarTraceHash {
				_ = appendFileLine(rerunLog, "oretest: repeated-run determinism guard failed (hash mismatch)")
				_ = appendFileLine(rerunLog, "first RESULT_HASH "+scalarResultHash)
				_ = appendFileLine(rerunLog, "rerun RESULT_HASH "+rerunResultHash)
				_ = appendFileLine(rerunLog, "first TRACE_HASH "+scalarTraceHash)
				_ = appendFileLine(rerunLog, "rerun TRACE_HASH "+rerunTraceHash)
				runOK = false
				log = rerunLog
				break
			}
		case "test_multiverse_vfs_inherit":
			// Build nested-universe fixtures (bytecode programs consumed as data by the test).
			fx := []struct {
				src string
				dst string
			}{
				{"tests/avm/fixtures/multiverse_grandchild_read_x.oren", "build/multiverse_grandchild_read_x.obc"},
				{"tests/avm/fixtures/multiverse_child_vfs_inherit.oren", "build/multiverse_child_vfs_inherit.obc"},
				{"tests/avm/fixtures/multiverse_child_host_fs_prefix_probe.oren", "build/multiverse_child_host_fs_prefix_probe.obc"},
			}
			for _, f := range fx {
				cmd := fmt.Sprintf("./oren build %q --backend bytecode -o %q%s", f.src, f.dst, gcArg)
				if rc := runWithTimeout(timeoutBin, buildTimeout, cmd, log); rc != 0 {
					runOK = false
					break
				}
			}
			if runOK {
				runCmd := fmt.Sprintf("./avm --fs-allow-prefixes \"build/\" %q", obc)
				if rc := runWithTimeout(timeoutBin, runTimeout, runCmd, log); rc != 0 {
					runOK = false
				}
			}
			_ = os.Remove("build/multiverse_grandchild_read_x.obc")
			_ = os.Remove("build/multiverse_child_vfs_inherit.obc")
			_ = os.Remove("build/multiverse_child_host_fs_prefix_probe.obc")
		case "test_policy_scan":
			_ = os.Remove("build/avm_policy_scan_should_not_write.txt")
			_ = os.Remove("build/avm_policy_scan_should_not_write2.txt")
			runCmd := fmt.Sprintf("./avm --print-policy %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, runCmd, log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat("build/avm_policy_scan_should_not_write.txt"); err == nil {
				runOK = false
			}
			if _, err := os.Stat("build/avm_policy_scan_should_not_write2.txt"); err == nil {
				runOK = false
			}
			_ = os.Remove("build/avm_policy_scan_should_not_write.txt")
			_ = os.Remove("build/avm_policy_scan_should_not_write2.txt")
		case "test_job_scan":
			_ = os.Remove("build/avm_job_scan_should_not_write.txt")
			_ = os.Remove("build/avm_job_scan_should_not_write2.txt")
			runCmd := fmt.Sprintf("./avm --print-job %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, runCmd, log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat("build/avm_job_scan_should_not_write.txt"); err == nil {
				runOK = false
			}
			if _, err := os.Stat("build/avm_job_scan_should_not_write2.txt"); err == nil {
				runOK = false
			}
			_ = os.Remove("build/avm_job_scan_should_not_write.txt")
			_ = os.Remove("build/avm_job_scan_should_not_write2.txt")
		case "test_snapshot_resume":
			snap := filepath.Join("build", name+".avms")
			_ = os.Remove(snap)
			// Expect pause exit code 2 (paused), then resume.
			cmd := fmt.Sprintf("./avm --step-limit 2000 --print-pause-json --snapshot-out %q %q", snap, obc)
			rc := runWithTimeout(timeoutBin, runTimeout, cmd, log)
			if rc != 2 {
				runOK = false
			} else {
				rc2 := runWithTimeout(timeoutBin, runTimeout, fmt.Sprintf("./avm --snapshot-in %q %q", snap, obc), log)
				if rc2 != 0 {
					runOK = false
				}
			}
			_ = os.Remove(snap)
		case "test_budget_gas":
			// Expected: AVM exits non-zero due to internal gas budget (not external timeout).
			cmd := fmt.Sprintf("env AVM_GAS=20000 ./avm %q", obc)
			rc := runWithTimeout(timeoutBin, runTimeout, cmd, log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_call_depth_limit":
			// Expected: non-zero due to call depth limit (not external timeout).
			cmd := fmt.Sprintf("./avm --call-depth-max 32 %q", obc)
			rc := runWithTimeout(timeoutBin, runTimeout, cmd, log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_budget_timeout":
			// Expected: non-zero due to internal deadline (not external timeout).
			cmd := fmt.Sprintf("./avm --timeout-ms 10 %q", obc)
			rc := runWithTimeout(timeoutBin, runTimeout, cmd, log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_arith_invalid":
			// Expected: non-zero due to deterministic arithmetic validation (not external timeout).
			cmd := fmt.Sprintf("./avm %q", obc)
			rc := runWithTimeout(timeoutBin, runTimeout, cmd, log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_fs_mounts_host_backend":
			_ = os.RemoveAll("build/mnt_avm")
			_ = os.MkdirAll("build/mnt_avm", 0o755)
			_ = os.Remove("build/avm_mount_deny.txt")
			_ = os.Remove("build/mnt_avm/out.txt")
			_ = os.Remove("build/mnt_avm/out_host.txt")
			cmd := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,1,6\" --fs-backend host --fs-mounts-read \"v/=build/mnt_avm/\" --fs-mounts-write \"v/=build/mnt_avm/\" %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
			}
			_ = os.RemoveAll("build/mnt_avm")
			_ = os.Remove("build/avm_mount_deny.txt")
		case "test_vfs_no_host_fs", "test_fs_helpers_vfs":
			_ = os.Remove("build/avm_vfs_should_not_write.bin")
			cmd := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,1,6\" --fs-allow-prefixes \"build/\" --fs-backend vfs %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat("build/avm_vfs_should_not_write.bin"); err == nil {
				runOK = false
			}
			_ = os.Remove("build/avm_vfs_should_not_write.bin")
		case "test_oren_env_bridge_capsule":
			_ = os.Remove("build/avm_oren_bridge_should_not_write.txt")
			cmd := fmt.Sprintf("env OREN_CAPSULE=1 ./avm %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat("build/avm_oren_bridge_should_not_write.txt"); err == nil {
				runOK = false
			}
			_ = os.Remove("build/avm_oren_bridge_should_not_write.txt")
		case "test_vproc_no_host_proc":
			_ = os.Remove("build/avm_vproc_should_not_touch.txt")
			cmd := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,5,6\" --proc-backend vproc --proc-exit-code 0 %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat("build/avm_vproc_should_not_touch.txt"); err == nil {
				runOK = false
			}
			_ = os.Remove("build/avm_vproc_should_not_touch.txt")
		case "test_vnet_no_host_net":
			hex := "41564d4e45543031010000000100000075020000006f6b"
			cmd := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,4,6\" --net-backend vnet --net-fixtures-hex %q %q", hex, obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
			}
		default:
			if rc := runWithTimeout(timeoutBin, runTimeout, fmt.Sprintf("./avm %q", obc), log); rc != 0 {
				runOK = false
			}
		}

		_ = os.Remove(obc)
		if runOK {
			res.pass++
		} else {
			res.ok = false
			res.failed = append(res.failed, testResult{tc: testCase{kind: "avm", name: name, path: path}, ok: false, log: log})
		}
	}
	return res
}

func runAVMTestsParallel(timeoutBin, orenPath, avmPath, gcArg string, buildTimeout, runTimeout time.Duration, verbose bool, vprintln func(string), jobs int, tests []string) suiteResult {
	res := suiteResult{ok: true, total: len(tests)}
	results := runParallel(jobs, tests, func(path string) testResult {
		name := strings.TrimSuffix(filepath.Base(path), ".oren")
		if verbose {
			vprintln("avm: " + path)
		}
		workdir := filepath.Join("build", "tmp", "avm_"+name)
		_ = os.RemoveAll(workdir)
		_ = os.MkdirAll(filepath.Join(workdir, "build"), 0o755)
		log := filepath.Join("build", "logs", "avm_"+name+".log")

		obc := filepath.Join(workdir, "build", name+".obc")
		buildCmd := fmt.Sprintf("%s build %q --backend bytecode -o %q%s", orenPath, path, obc, gcArg)
		if rc := runWithTimeout(timeoutBin, buildTimeout, buildCmd, log); rc != 0 {
			return testResult{tc: testCase{kind: "avm", name: name, path: path}, ok: false, log: log}
		}

		runOK := true
		workBuild := filepath.Join(workdir, "build")

		switch name {
		case "test_smoke_suite":
			// Run the scalar path (default) first, then validate the SIMD path (arm64 only).
			//
			// Determinism guard:
			// - compare RESULT_HASH + TRACE_HASH with SIMD off/on
			// - compare scalar run vs scalar rerun (same host, same binary)
			// The smoke suite includes SIMD-sensitive typed-buffer kernels (f32_buf ops), so this is high-signal.
			cmd := fmt.Sprintf("%s --print-result-hash --print-trace-hash %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
				break
			}
			scalarResultHash, okR := extractHashFromLog(log, "RESULT_HASH")
			scalarTraceHash, okT := extractHashFromLog(log, "TRACE_HASH")
			if !okR || !okT {
				_ = appendFileLine(log, "oretest: missing RESULT_HASH/TRACE_HASH in scalar run output")
				runOK = false
				break
			}

			// Re-run the scalar path and ensure hashes match (same host determinism).
			rerunLog := filepath.Join("build", "logs", "avm_"+name+"_rerun.log")
			_ = os.Remove(rerunLog)
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), rerunLog); rc != 0 {
				runOK = false
				log = rerunLog
				break
			}
			rerunResultHash, okR2 := extractHashFromLog(rerunLog, "RESULT_HASH")
			rerunTraceHash, okT2 := extractHashFromLog(rerunLog, "TRACE_HASH")
			if !okR2 || !okT2 {
				_ = appendFileLine(rerunLog, "oretest: missing RESULT_HASH/TRACE_HASH in scalar rerun output")
				runOK = false
				log = rerunLog
				break
			}
			if rerunResultHash != scalarResultHash || rerunTraceHash != scalarTraceHash {
				_ = appendFileLine(rerunLog, "oretest: repeated-run determinism guard failed (hash mismatch)")
				_ = appendFileLine(rerunLog, "first RESULT_HASH "+scalarResultHash)
				_ = appendFileLine(rerunLog, "rerun RESULT_HASH "+rerunResultHash)
				_ = appendFileLine(rerunLog, "first TRACE_HASH "+scalarTraceHash)
				_ = appendFileLine(rerunLog, "rerun TRACE_HASH "+rerunTraceHash)
				runOK = false
				log = rerunLog
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "avm_"+name+"_simd.log")
				simdCmd := fmt.Sprintf("env AVM_ENABLE_SIMD=1 %s --print-result-hash --print-trace-hash %q", avmPath, filepath.Join("build", name+".obc"))
				if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, simdCmd), simdLog); rc != 0 {
					runOK = false
					// Swap the log to the SIMD run log for clearer failure output.
					log = simdLog
				} else {
					simdResultHash, okR2 := extractHashFromLog(simdLog, "RESULT_HASH")
					simdTraceHash, okT2 := extractHashFromLog(simdLog, "TRACE_HASH")
					if !okR2 || !okT2 {
						_ = appendFileLine(simdLog, "oretest: missing RESULT_HASH/TRACE_HASH in SIMD run output")
						runOK = false
						log = simdLog
					} else if simdResultHash != scalarResultHash || simdTraceHash != scalarTraceHash {
						_ = appendFileLine(simdLog, "oretest: SIMD determinism guard failed (hash mismatch)")
						_ = appendFileLine(simdLog, "scalar RESULT_HASH "+scalarResultHash)
						_ = appendFileLine(simdLog, "simd   RESULT_HASH "+simdResultHash)
						_ = appendFileLine(simdLog, "scalar TRACE_HASH "+scalarTraceHash)
						_ = appendFileLine(simdLog, "simd   TRACE_HASH "+simdTraceHash)
						runOK = false
						log = simdLog
					}
				}
			}
		case "test_multiverse_vfs_inherit":
			fx := []struct {
				src string
				dst string
			}{
				{"tests/avm/fixtures/multiverse_grandchild_read_x.oren", filepath.Join(workBuild, "multiverse_grandchild_read_x.obc")},
				{"tests/avm/fixtures/multiverse_child_vfs_inherit.oren", filepath.Join(workBuild, "multiverse_child_vfs_inherit.obc")},
				{"tests/avm/fixtures/multiverse_child_host_fs_prefix_probe.oren", filepath.Join(workBuild, "multiverse_child_host_fs_prefix_probe.obc")},
			}
			for _, f := range fx {
				cmd := fmt.Sprintf("%s build %q --backend bytecode -o %q%s", orenPath, f.src, f.dst, gcArg)
				if rc := runWithTimeout(timeoutBin, buildTimeout, cmd, log); rc != 0 {
					runOK = false
					break
				}
			}
			if runOK {
				runCmd := fmt.Sprintf("%s --fs-allow-prefixes \"build/\" %q", avmPath, filepath.Join("build", name+".obc"))
				if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, runCmd), log); rc != 0 {
					runOK = false
				}
			}
			_ = os.Remove(filepath.Join(workBuild, "multiverse_grandchild_read_x.obc"))
			_ = os.Remove(filepath.Join(workBuild, "multiverse_child_vfs_inherit.obc"))
			_ = os.Remove(filepath.Join(workBuild, "multiverse_child_host_fs_prefix_probe.obc"))
		case "test_policy_scan":
			deny1 := filepath.Join(workBuild, "avm_policy_scan_should_not_write.txt")
			deny2 := filepath.Join(workBuild, "avm_policy_scan_should_not_write2.txt")
			_ = os.Remove(deny1)
			_ = os.Remove(deny2)
			runCmd := fmt.Sprintf("%s --print-policy %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, runCmd), log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat(deny1); err == nil {
				runOK = false
			}
			if _, err := os.Stat(deny2); err == nil {
				runOK = false
			}
			_ = os.Remove(deny1)
			_ = os.Remove(deny2)
		case "test_job_scan":
			deny1 := filepath.Join(workBuild, "avm_job_scan_should_not_write.txt")
			deny2 := filepath.Join(workBuild, "avm_job_scan_should_not_write2.txt")
			_ = os.Remove(deny1)
			_ = os.Remove(deny2)
			runCmd := fmt.Sprintf("%s --print-job %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, runCmd), log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat(deny1); err == nil {
				runOK = false
			}
			if _, err := os.Stat(deny2); err == nil {
				runOK = false
			}
			_ = os.Remove(deny1)
			_ = os.Remove(deny2)
		case "test_snapshot_resume":
			snap := filepath.Join(workBuild, name+".avms")
			_ = os.Remove(snap)
			cmd := fmt.Sprintf("%s --step-limit 2000 --print-pause-json --snapshot-out %q %q", avmPath, filepath.Join("build", name+".avms"), filepath.Join("build", name+".obc"))
			rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log)
			if rc != 2 {
				runOK = false
			} else {
				rc2 := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, fmt.Sprintf("%s --snapshot-in %q %q", avmPath, filepath.Join("build", name+".avms"), filepath.Join("build", name+".obc"))), log)
				if rc2 != 0 {
					runOK = false
				}
			}
			_ = os.Remove(snap)
			if runOK && shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "avm_"+name+"_simd.log")
				snap2 := filepath.Join(workBuild, name+".simd.avms")
				_ = os.Remove(snap2)
				cmdSimd := fmt.Sprintf("env AVM_ENABLE_SIMD=1 %s --step-limit 2000 --print-pause-json --snapshot-out %q %q", avmPath, filepath.Join("build", name+".simd.avms"), filepath.Join("build", name+".obc"))
				rcSimd := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmdSimd), simdLog)
				if rcSimd != 2 {
					runOK = false
					log = simdLog
				} else {
					rc2Simd := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, fmt.Sprintf("env AVM_ENABLE_SIMD=1 %s --snapshot-in %q %q", avmPath, filepath.Join("build", name+".simd.avms"), filepath.Join("build", name+".obc"))), simdLog)
					if rc2Simd != 0 {
						runOK = false
						log = simdLog
					}
				}
				_ = os.Remove(snap2)
			}
		case "test_budget_gas":
			cmd := fmt.Sprintf("env AVM_GAS=20000 %s %q", avmPath, filepath.Join("build", name+".obc"))
			rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_call_depth_limit":
			cmd := fmt.Sprintf("%s --call-depth-max 32 %q", avmPath, filepath.Join("build", name+".obc"))
			rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_budget_timeout":
			cmd := fmt.Sprintf("%s --timeout-ms 10 %q", avmPath, filepath.Join("build", name+".obc"))
			rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_arith_invalid":
			// Expected: non-zero due to deterministic arithmetic validation (not external timeout).
			cmd := fmt.Sprintf("%s %q", avmPath, filepath.Join("build", name+".obc"))
			rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log)
			if rc == 0 || rc == 124 {
				runOK = false
			}
		case "test_fs_mounts_host_backend":
			mnt := filepath.Join(workBuild, "mnt_avm")
			_ = os.RemoveAll(mnt)
			_ = os.MkdirAll(mnt, 0o755)
			_ = os.Remove(filepath.Join(workBuild, "avm_mount_deny.txt"))
			_ = os.Remove(filepath.Join(mnt, "out.txt"))
			_ = os.Remove(filepath.Join(mnt, "out_host.txt"))
			cmd := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,1,6\" --fs-backend host --fs-mounts-read \"v/=build/mnt_avm/\" --fs-mounts-write \"v/=build/mnt_avm/\" %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
			_ = os.RemoveAll(mnt)
			_ = os.Remove(filepath.Join(workBuild, "avm_mount_deny.txt"))
		case "test_vfs_no_host_fs", "test_fs_helpers_vfs":
			deny := filepath.Join(workBuild, "avm_vfs_should_not_write.bin")
			_ = os.Remove(deny)
			cmd := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,1,6\" --fs-allow-prefixes \"build/\" --fs-backend vfs %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat(deny); err == nil {
				runOK = false
			}
			_ = os.Remove(deny)
		case "test_oren_env_bridge_capsule":
			deny := filepath.Join(workBuild, "avm_oren_bridge_should_not_write.txt")
			_ = os.Remove(deny)
			cmd := fmt.Sprintf("env OREN_CAPSULE=1 %s %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat(deny); err == nil {
				runOK = false
			}
			_ = os.Remove(deny)
		case "test_vproc_no_host_proc":
			deny := filepath.Join(workBuild, "avm_vproc_should_not_touch.txt")
			_ = os.Remove(deny)
			cmd := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,5,6\" --proc-backend vproc --proc-exit-code 0 %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
			if _, err := os.Stat(deny); err == nil {
				runOK = false
			}
			_ = os.Remove(deny)
		case "test_vnet_no_host_net":
			hex := "41564d4e45543031010000000100000075020000006f6b"
			cmd := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,4,6\" --net-backend vnet --net-fixtures-hex %q %q", avmPath, hex, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
		case "test_spawn_join_timeout":
			// Deterministic TIME is required so timeouts don't depend on host scheduling jitter.
			// Use a large per-step time to keep the test fast (virtual time advances quickly).
			cmd := fmt.Sprintf("env AVM_DETERMINISTIC=1 AVM_TIME_START_NS=0 AVM_TIME_STEP_NS=1000000 %s %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
		default:
			cmd := fmt.Sprintf("%s %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
			}
		}

		_ = os.Remove(obc)
		if runOK {
			_ = os.RemoveAll(workdir)
			return testResult{tc: testCase{kind: "avm", name: name, path: path}, ok: true, log: log}
		}
		return testResult{tc: testCase{kind: "avm", name: name, path: path}, ok: false, log: log}
	})
	for _, r := range results {
		if r.ok {
			res.pass++
		} else {
			res.ok = false
			res.failed = append(res.failed, r)
		}
	}
	return res
}

func runParallel[T any](jobs int, items []string, fn func(string) T) []T {
	if jobs < 1 {
		jobs = 1
	}
	out := make([]T, len(items))
	var wg sync.WaitGroup
	sem := make(chan struct{}, jobs)
	for i := range items {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int) {
			defer wg.Done()
			defer func() { <-sem }()
			out[i] = fn(items[i])
		}(i)
	}
	wg.Wait()
	return out
}

func runWithTimeout(timeoutBin string, d time.Duration, cmd string, logPath string) int {
	_ = os.MkdirAll(filepath.Dir(logPath), 0o755)
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()

	// Keep behavior aligned with Makefile: enforce timeouts everywhere.
	// Important: run the actual command via `sh -c` so call sites can use shell syntax
	// (env vars, quoting, etc.) safely.
	//
	// Important: `exec.CommandContext` does not reliably kill child processes.
	// We always run each test in its own process group, and on timeout we kill the group.
	var c *exec.Cmd
	if timeoutBin != "" {
		// Keep using GNU timeout if available for parity with Makefile behavior, but
		// still rely on our internal process-group kill as the ultimate backstop.
		c = exec.CommandContext(ctx, timeoutBin, "-k", "2", fmt.Sprintf("%d", int(d.Seconds())), "sh", "-c", cmd)
	} else {
		c = exec.Command("sh", "-c", cmd)
	}
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var buf bytes.Buffer
	c.Stdout = &buf
	c.Stderr = &buf

	runErr := c.Start()
	if runErr != nil {
		// Ensure the log is actionable even when the process failed to start.
		if buf.Len() == 0 {
			_, _ = buf.WriteString(runErr.Error())
			_, _ = buf.WriteString("\n")
		}
		_ = os.WriteFile(logPath, buf.Bytes(), 0o644)
		return 1
	}

	waitCh := make(chan error, 1)
	go func() { waitCh <- c.Wait() }()

	timedOut := false
	select {
	case runErr = <-waitCh:
		// done
	case <-ctx.Done():
		timedOut = true
		killProcessGroup(c.Process.Pid)
		runErr = <-waitCh
	}

	_ = os.WriteFile(logPath, buf.Bytes(), 0o644)

	if timedOut || ctx.Err() == context.DeadlineExceeded {
		// GNU timeout uses 124; align on that.
		return 124
	}
	if c.ProcessState == nil {
		return 1
	}
	return c.ProcessState.ExitCode()
}

func inDir(dir, cmd string) string {
	return "cd " + shellQuote(dir) + " && " + cmd
}

func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	// POSIX shell single-quote escaping: close, escape, reopen.
	return "'" + strings.ReplaceAll(s, "'", `'"'"'`) + "'"
}

func detectTimeoutBin() string {
	if _, err := exec.LookPath("timeout"); err == nil {
		return "timeout"
	}
	if _, err := exec.LookPath("gtimeout"); err == nil {
		return "gtimeout"
	}
	return ""
}

func killProcessGroup(pid int) {
	if pid <= 0 {
		return
	}

	// Send TERM first (best effort), then KILL. Group kill requires Setpgid=true.
	_ = syscall.Kill(-pid, syscall.SIGTERM)
	_ = syscall.Kill(pid, syscall.SIGTERM)

	time.Sleep(200 * time.Millisecond)

	_ = syscall.Kill(-pid, syscall.SIGKILL)
	_ = syscall.Kill(pid, syscall.SIGKILL)
}

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n := 0
	for _, ch := range v {
		if ch < '0' || ch > '9' {
			return def
		}
		n = n*10 + int(ch-'0')
	}
	if n <= 0 {
		return def
	}
	return n
}

func envBool(key string, def bool) bool {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return def
	}
}

func catFile(w *os.File, path string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	_, err = w.Write(b)
	return err
}

func extractHashFromLog(logPath string, prefix string) (string, bool) {
	b, err := os.ReadFile(logPath)
	if err != nil {
		return "", false
	}
	s := string(b)
	lines := strings.Split(s, "\n")
	want := prefix + " "
	for _, ln := range lines {
		ln = strings.TrimSpace(ln)
		if strings.HasPrefix(ln, want) {
			return strings.TrimSpace(strings.TrimPrefix(ln, want)), true
		}
	}
	return "", false
}

func appendFileLine(path string, line string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if !strings.HasSuffix(line, "\n") {
		line += "\n"
	}
	_, err = f.WriteString(line)
	return err
}

func auditNativeCapsuleSyscallPrehooks() error {
	// Purpose: prevent “capsule bypass” regressions by ensuring every syscall intrinsic
	// lowered by the native backend has a capsule pre-hook call in the lowering.
	//
	// This is intentionally a static audit (no compilation). It is cheap, fast,
	// and catches bypasses introduced by refactors.
	compilerPath := filepath.Join("lib", "compiler", "arm64_native_expr_syscalls.oren")
	runtimePath := filepath.Join("lib", "runtime_native.oren")

	compilerSrc, err := os.ReadFile(compilerPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", compilerPath, err)
	}
	runtimeSrc, err := os.ReadFile(runtimePath)
	if err != nil {
		return fmt.Errorf("read %s: %w", runtimePath, err)
	}

	// Collect all defined capsule pre-hooks in the native runtime.
	rt := string(runtimeSrc)
	runtimePrehooks := map[string]bool{}
	for _, line := range strings.Split(rt, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "fn native_capsule_sys_") {
			continue
		}
		// fn native_capsule_sys_open_pre(...)
		name := strings.TrimPrefix(line, "fn ")
		if i := strings.IndexByte(name, '('); i >= 0 {
			name = name[:i]
		}
		if strings.HasSuffix(name, "_pre") {
			runtimePrehooks[name] = true
		}
	}

	src := string(compilerSrc)
	blocks := parseSyscallBlocks(src)
	if len(blocks) == 0 {
		return fmt.Errorf("no syscall blocks found in %s (unexpected)", compilerPath)
	}

	// Exceptions: sys_exit is always permitted as an immediate termination.
	// (Capsule governance can still choose to restrict PROC usage at higher layers.)
	exempt := map[string]bool{
		"sys_exit": true,
		// Internal runtime primitives:
		// - sys_gettid is needed for the runtime's own locking/GC bookkeeping.
		// - ulock is a kernel scheduling primitive used by the runtime lock.
		// These are not part of the host-effect domains (FS/NET/PROC/ENV/TIME).
		"sys_gettid":     true,
		"sys_ulock_wait": true,
		"sys_ulock_wake": true,
	}

	// Some Oren "sys_*" intrinsics are aliases that intentionally lower to other
	// host syscalls, but still need capsule gating. This maps intrinsic name to
	// the expected capsule prehook symbol(s).
	//
	// Default rule (when missing from this map):
	//   sys_foo -> native_capsule_sys_foo_pre
	//
	// NOTE: keep this list small and explicit; the point of the audit is to force
	// deliberate review when new intrinsics are introduced.
	prehookAlias := map[string][]string{
		// fcntl wrappers
		"sys_fcntl_getfl":   {"native_capsule_sys_fcntl_pre"},
		"sys_fcntl_setfl":   {"native_capsule_sys_fcntl_pre"},
		"sys_fcntl_getpath": {"native_capsule_sys_fcntl_pre"},
		// dup3 lowers via dup2-style capsule hooks (oldfd/newfd semantics).
		"sys_dup3": {"native_capsule_sys_dup2_pre"},
		// send/recv lower to sendto/recvfrom with NULL addr.
		"sys_send": {"native_capsule_sys_sendto_pre"},
		"sys_recv": {"native_capsule_sys_recvfrom_pre"},
	}

	var missing []string
	for _, b := range blocks {
		usesSyscall := strings.Contains(b.text, "emit_svc_preserve_heap") ||
			strings.Contains(b.text, "abi.darwin_sys_") ||
			strings.Contains(b.text, "labi.linux_sys_") ||
			strings.Contains(b.text, "insn_svc(")
		if !usesSyscall {
			continue
		}
		for _, sysName := range b.sysNames {
			if exempt[sysName] {
				continue
			}

			expected := prehookAlias[sysName]
			if len(expected) == 0 {
				expected = []string{"native_capsule_" + sysName + "_pre"}
			}

			ok := false
			for _, want := range expected {
				if strings.Contains(b.text, want) {
					ok = true
					break
				}
			}
			if !ok {
				missing = append(missing, sysName)
			}
		}

		// Also ensure every referenced prehook actually exists in runtime_native.oren.
		for _, pre := range extractPrehookNames(b.text) {
			if !runtimePrehooks[pre] {
				return fmt.Errorf("lowering references %s but runtime does not define it (%s)", pre, runtimePath)
			}
		}
	}

	if len(missing) > 0 {
		sort.Strings(missing)
		// Dedupe.
		uniq := missing[:0]
		for i, s := range missing {
			if i == 0 || s != missing[i-1] {
				uniq = append(uniq, s)
			}
		}
		return fmt.Errorf("missing capsule prehook call in lowering blocks for: %s", strings.Join(uniq, ", "))
	}

	return nil
}

func auditNativeNoDirectSvcBypass() error {
	// Purpose: prevent “capsule bypass” regressions by ensuring the native backend
	// does not start emitting direct `svc` instructions in new places.
	//
	// Policy:
	// - Syscall lowering belongs in `arm64_native_expr_syscalls.oren` (where capsule
	//   prehooks are enforced).
	// - A small number of `svc` sites are allowed for internal plumbing:
	//     - entry stub `exit` (arm64_native_program.oren)
	//     - early heap mapping `mmap` + fail-fast `exit` (arm64_native_expr.oren)
	//     - Mach-O tooling helper `exit` (arm64_macho.oren)
	//
	// Anything else is almost certainly a regression and should be moved to the
	// syscall lowering module with explicit capsule hooks.
	allowedFiles := map[string]bool{
		filepath.Join("lib", "compiler", "arm64_native_expr_syscalls.oren"): true,
		filepath.Join("lib", "compiler", "arm64_native_program.oren"):       true, // entry stub exit
		filepath.Join("lib", "compiler", "arm64_native_expr.oren"):          true, // heap mmap + fail-fast exit
		filepath.Join("lib", "compiler", "arm64_macho.oren"):                true, // tooling helper exit
	}
	allowedSyms := map[string]bool{
		"sys_exit": true,
		"sys_mmap": true,
	}

	var offenders []string

	err := filepath.WalkDir(filepath.Join("lib", "compiler"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}

		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		src := string(b)
		if !strings.Contains(src, "insn_svc(") && !strings.Contains(src, "abi.darwin_sys_") && !strings.Contains(src, "labi.linux_sys_") {
			return nil
		}

		// We only care about *emitting* an svc instruction into generated code.
		// The compiler core defines helper functions like `fn insn_svc(...)` which
		// are not syscall emissions.
		emitsSVC := false
		for _, line := range strings.Split(src, "\n") {
			if strings.Contains(line, "push_u32_le(") && strings.Contains(line, "insn_svc(") {
				// Avoid false positives from string constants used in grep/audit patterns.
				// Heuristic: if the match appears inside a quoted string on the line, ignore it.
				if strings.Contains(line, "\"push_u32_le(") || strings.Contains(line, "\"insn_svc(") {
					continue
				}
				emitsSVC = true
				break
			}
		}

		if emitsSVC {
			if !allowedFiles[path] {
				offenders = append(offenders, fmt.Sprintf("%s: emits insn_svc()", path))
				return nil
			}

			// For allowed files other than the dedicated syscall lowering module,
			// ensure the direct svc sites are only for `sys_exit`/`sys_mmap`.
			if strings.HasSuffix(path, "arm64_native_expr_syscalls.oren") {
				return nil
			}
			lines := strings.Split(src, "\n")
			for i, line := range lines {
				if !(strings.Contains(line, "push_u32_le(") && strings.Contains(line, "insn_svc(")) {
					continue
				}
				if strings.Contains(line, "\"push_u32_le(") || strings.Contains(line, "\"insn_svc(") {
					continue
				}
				ok := false
				// Look back a few lines for the syscall number load.
				start := i - 8
				if start < 0 {
					start = 0
				}
				window := strings.Join(lines[start:i+1], "\n")
				for sym := range allowedSyms {
					if strings.Contains(window, sym) {
						ok = true
						break
					}
				}
				if !ok {
					offenders = append(offenders, fmt.Sprintf("%s:%d: svc emission not tied to allowed sys_* (only sys_exit/sys_mmap allowed here)", path, i+1))
				}
			}
		}

		// Also ensure no new direct sysno references appear outside the syscall module.
		// Only allow sys_exit/sys_mmap in the few whitelisted internal files.
		if strings.Contains(src, "abi.darwin_sys_") || strings.Contains(src, "labi.linux_sys_") {
			if !allowedFiles[path] {
				offenders = append(offenders, fmt.Sprintf("%s: contains abi.darwin_sys_ / labi.linux_sys_", path))
				return nil
			}
			if strings.HasSuffix(path, "arm64_native_expr_syscalls.oren") {
				return nil
			}
			for _, line := range strings.Split(src, "\n") {
				if !strings.Contains(line, "abi.darwin_sys_") && !strings.Contains(line, "labi.linux_sys_") {
					continue
				}
				// Avoid false positives from string constants used for audits/tools.
				if strings.Contains(line, "\"abi.darwin_sys_") || strings.Contains(line, "\"labi.linux_sys_") {
					continue
				}
				// Heuristic: require the line to mention an allowed sys_* symbol.
				ok := false
				for sym := range allowedSyms {
					if strings.Contains(line, sym) {
						ok = true
						break
					}
				}
				if !ok {
					offenders = append(offenders, fmt.Sprintf("%s: disallowed direct sysno reference: %s", path, strings.TrimSpace(line)))
				}
			}
		}

		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 20 {
			offenders = offenders[:20]
		}
		return fmt.Errorf("direct svc/sysno emission outside syscall lowering module; first offenders:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func parseSyscallBlocks(src string) []syscallBlock {
	// Heuristic parser: split the syscall lowering function into blocks beginning at:
	//   if fn_name == "sys_..."
	// The Oren source is stable enough for this audit, and we don't want a full parser here.
	//
	// Important: only treat *top-level* syscall cases as block starts.
	// In `arm64_native_expr_syscalls.oren`, nested `if fn_name == ...` checks can appear
	// inside a larger syscall block (e.g. `sys_send`/`sys_recv`). Those must not split blocks.
	//
	// Convention today: top-level syscall cases are indented by exactly 8 spaces.
	var starts []int
	lines := strings.SplitAfter(src, "\n")
	offset := 0
	for _, line := range lines {
		if strings.HasPrefix(line, "        if fn_name == \"sys_") {
			starts = append(starts, offset)
		}
		offset += len(line)
	}
	if len(starts) == 0 {
		return nil
	}

	var blocks []syscallBlock
	for i := range starts {
		start := starts[i]
		end := len(src)
		if i+1 < len(starts) {
			end = starts[i+1]
		}
		txt := src[start:end]
		headerEnd := strings.IndexByte(txt, '\n')
		header := txt
		if headerEnd >= 0 {
			header = txt[:headerEnd]
		}
		sysNames := extractSysNamesFromHeader(header)
		if len(sysNames) == 0 {
			continue
		}
		blocks = append(blocks, syscallBlock{sysNames: sysNames, text: txt})
	}
	return blocks
}

func extractSysNamesFromHeader(header string) []string {
	// Header examples:
	//   if fn_name == "sys_open" {
	//   if fn_name == "sys_getpeername" || fn_name == "sys_getsockname" {
	var out []string
	for _, part := range strings.Split(header, "\"") {
		if strings.HasPrefix(part, "sys_") {
			out = append(out, part)
		}
	}
	return out
}

func extractPrehookNames(text string) []string {
	// Extract references like:
	//   "name": "native_capsule_sys_open_pre"
	// Keep simple and deterministic.
	var out []string
	const needle = `native_capsule_sys_`
	for off := 0; ; {
		i := strings.Index(text[off:], needle)
		if i < 0 {
			break
		}
		pos := off + i
		rest := text[pos:]
		end := 0
		for end < len(rest) {
			ch := rest[end]
			if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' {
				end++
				continue
			}
			break
		}
		name := rest[:end]
		if strings.HasSuffix(name, "_pre") {
			out = append(out, name)
		}
		off = pos + 1
	}
	// Dedupe deterministically.
	sort.Strings(out)
	uniq := out[:0]
	for i, s := range out {
		if i == 0 || s != out[i-1] {
			uniq = append(uniq, s)
		}
	}
	return uniq
}

func init() {
	// Ensure stable behavior in macOS where PATH may differ between shells.
	if runtime.GOOS == "darwin" {
		// no-op; placeholder for future if needed.
	}
}
