package main

import (
	"bytes"
	"context"
	"crypto/sha256"
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

func fileSHA256Hex(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return fmt.Sprintf("%x", sum[:]), nil
}

func runSelfHostingGate(timeoutBin, gcArg string, buildTimeout time.Duration) error {
	// Rolling stability gate:
	// - Stage1 (./oren) builds Stage2 (a fresh ./oren_stage2)
	// - Stage1 and Stage2 must agree on deterministic dumps of the compiler source
	//
	// This catches "bootstrap breaks itself" regressions early.
	if os.Getenv("OREN_SKIP_SELFHOST") != "" {
		return nil
	}

	workdir := filepath.Join("build", "selfhost")
	_ = os.MkdirAll(workdir, 0o755)

	stage2Obc := filepath.Join(workdir, "oren_stage2.obc")
	stage1Graph := filepath.Join(workdir, "stage1.graph.json")
	stage2Graph := filepath.Join(workdir, "stage2.graph.json")
	stage1Meta := filepath.Join(workdir, "stage1.meta.json")
	stage2Meta := filepath.Join(workdir, "stage2.meta.json")

	logBuildObc := filepath.Join("build", "logs", "selfhost_build_stage2_obc.log")
	logG1 := filepath.Join("build", "logs", "selfhost_stage1_dump_graph.log")
	logG2 := filepath.Join("build", "logs", "selfhost_stage2_dump_graph.log")
	logM1 := filepath.Join("build", "logs", "selfhost_stage1_meta.log")
	logM2 := filepath.Join("build", "logs", "selfhost_stage2_meta.log")

	// Self-hosting builds can be slower than ordinary test compilation, especially on
	// cold caches or when the host toolchain is busy. Keep it bounded but generous.
	selfHostTimeout := buildTimeout
	if selfHostTimeout < 300*time.Second {
		selfHostTimeout = 300 * time.Second
	}

	// Self-hosting build strategy (rolling, pragmatic):
	//
	// - Building a full Stage2 native binary currently depends on a much larger native-runtime surface
	//   (syscall-first file I/O, float parsing, etc.) which is still evolving.
	// - Building a full Stage2 C backend binary can be extremely memory hungry (clang compiling a
	//   giant single-TU generated C file), and may be SIGKILL/OOM on developer machines.
	//
	// Therefore this gate uses the bytecode backend + AVM to validate self-hosting deterministically:
	// Stage1 emits Stage2 compiler as `.obc`, then AVM runs Stage2 to reproduce Stage1 outputs.
	buildObc := fmt.Sprintf("./oren build oren.oren --backend bytecode -o %q%s", stage2Obc, gcArg)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, buildObc, logBuildObc); rc != 0 {
		return fmt.Errorf("self-host gate: failed to build stage2 .obc (rc=%d), see %s", rc, logBuildObc)
	}

	// Dump module graph from Stage1 and Stage2 and require byte-for-byte match.
	g1 := fmt.Sprintf("./oren dump graph oren.oren --out %q", stage1Graph)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, g1, logG1); rc != 0 {
		return fmt.Errorf("self-host gate: stage1 dump graph failed (rc=%d), see %s", rc, logG1)
	}
	// Run Stage2 under AVM with a narrow FS allowlist:
	// - read: `oren.oren` + `lib/**`
	// - write: `build/**`
	//
	// Note: AVM passes args after `--`.
	fsAllow := "build/,lib/,oren.oren"
	// Important: the compiler strips argv[0] as the program name. AVM passes only args-after-`--`
	// (no implicit argv0), so we inject a dummy argv0 ("oren") here.
	g2 := fmt.Sprintf("./avm --fs-allow-prefixes %q %q -- oren dump graph oren.oren --out %q", fsAllow, stage2Obc, stage2Graph)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, g2, logG2); rc != 0 {
		return fmt.Errorf("self-host gate: stage2 (avm) dump graph failed (rc=%d), see %s", rc, logG2)
	}
	hg1, err := fileSHA256Hex(stage1Graph)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage1 graph: %w", err)
	}
	hg2, err := fileSHA256Hex(stage2Graph)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage2 graph: %w", err)
	}
	if hg1 != hg2 {
		return fmt.Errorf("self-host gate: module graph mismatch (stage1=%s stage2=%s); diff %s vs %s", hg1, hg2, stage1Graph, stage2Graph)
	}

	// Also compare metadata output (API surface) under --deterministic.
	m1 := fmt.Sprintf("./oren meta oren.oren --deterministic --out %q", stage1Meta)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, m1, logM1); rc != 0 {
		return fmt.Errorf("self-host gate: stage1 meta failed (rc=%d), see %s", rc, logM1)
	}
	m2 := fmt.Sprintf("./avm --fs-allow-prefixes %q %q -- oren meta oren.oren --deterministic --out %q", fsAllow, stage2Obc, stage2Meta)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, m2, logM2); rc != 0 {
		return fmt.Errorf("self-host gate: stage2 (avm) meta failed (rc=%d), see %s", rc, logM2)
	}
	hm1, err := fileSHA256Hex(stage1Meta)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage1 meta: %w", err)
	}
	hm2, err := fileSHA256Hex(stage2Meta)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage2 meta: %w", err)
	}
	if hm1 != hm2 {
		return fmt.Errorf("self-host gate: metadata mismatch (stage1=%s stage2=%s); diff %s vs %s", hm1, hm2, stage1Meta, stage2Meta)
	}

	return nil
}

func runNativeSelfHostingGate(timeoutBin, gcArg string, buildTimeout time.Duration, target, arch string) error {
	// Rolling stability gate (native backend):
	// - Stage1 (./oren) builds Stage2 as a native binary (Mach-O/ELF)
	// - Stage2 must be executable and responsive (basic smoke)
	//
	// This catches regressions in the syscall-first native runtime subset required to self-host.
	if os.Getenv("OREN_SKIP_SELFHOST_NATIVE") != "" {
		return nil
	}

	workdir := filepath.Join("build", "selfhost")
	_ = os.MkdirAll(workdir, 0o755)

	stage2Native := filepath.Join(workdir, "oren_stage2_native")

	logBuildNative := filepath.Join("build", "logs", "selfhost_build_stage2_native.log")
	logCodesign := filepath.Join("build", "logs", "selfhost_stage2_native_codesign.log")
	logHelp := filepath.Join("build", "logs", "selfhost_stage2_native_help.log")

	selfHostTimeout := buildTimeout
	// Native stage2 operations can be significantly slower than AVM, even for a small entry, because
	// the syscall-first native runtime currently has a larger constant-factor overhead (allocation,
	// hashing, map ops, etc). Keep this gate reliable by using a more generous floor.
	minTimeout := 600 * time.Second
	if selfHostTimeout < minTimeout {
		selfHostTimeout = minTimeout
	}

	// Build Stage2 native compiler (deterministic mode exercises hashing path too).
	buildNative := fmt.Sprintf("./oren build oren.oren --backend native --target %s --arch %s --deterministic -o %q%s", target, arch, stage2Native, gcArg)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, buildNative, logBuildNative); rc != 0 {
		return fmt.Errorf("native self-host gate: failed to build stage2 native (rc=%d), see %s", rc, logBuildNative)
	}

	// macOS: unsigned binaries may be killed at exec by Gatekeeper/AMFI policies even when built locally.
	// Use ad-hoc signing (`-s -`) so the stage2 native binary can be executed reliably in CI/dev.
	if runtime.GOOS == "darwin" {
		sign := fmt.Sprintf("codesign -s - -f %q", stage2Native)
		if rc := runWithTimeout(timeoutBin, selfHostTimeout, sign, logCodesign); rc != 0 {
			return fmt.Errorf("native self-host gate: failed to ad-hoc codesign stage2 native (rc=%d), see %s", rc, logCodesign)
		}
	}

	// Stage2 native must be executable and have a minimally correct syscall-first runtime surface.
	// Use `selftest-native` which is designed to be fast and avoids compiler pipelines.
	runTimeout := 60 * time.Second
	if runTimeout > selfHostTimeout {
		runTimeout = selfHostTimeout
	}
	selftest := fmt.Sprintf("%q selftest-native", stage2Native)
	if rc := runWithTimeout(timeoutBin, runTimeout, selftest, logHelp); rc != 0 {
		return fmt.Errorf("native self-host gate: stage2(native) selftest-native failed (rc=%d), see %s", rc, logHelp)
	}
	b, err := os.ReadFile(logHelp)
	if err == nil {
		if !bytes.Contains(b, []byte("selftest-native OK")) {
			return fmt.Errorf("native self-host gate: stage2(native) selftest-native output missing OK marker, see %s", logHelp)
		}
	}

	return nil
}

func hostNativeTarget() string {
	if runtime.GOOS == "darwin" {
		return "macos"
	}
	if runtime.GOOS == "linux" {
		return "linux"
	}
	return ""
}

func hostNativeArch() string {
	// Rolling policy: the native backend supports only arm64 today.
	return "arm64"
}

func main() {
	var (
		target      = flag.String("target", "macos", "native backend target: macos|linux")
		noGC        = flag.Bool("no-gc", os.Getenv("OREN_NO_GC") != "", "disable GC scanning (also via env OREN_NO_GC=1)")
		jobs        = flag.Int("jobs", envInt("OREN_TEST_JOBS", runtime.NumCPU()), "parallel jobs for module+avm tests (env OREN_TEST_JOBS)")
		fixtureJobs = flag.Int("fixture-jobs", envInt("OREN_TEST_FIXTURE_JOBS", 0), "parallel jobs for fixtures (env OREN_TEST_FIXTURE_JOBS); default min(--jobs,4)")
		nativeJobs  = flag.Int("native-jobs", envInt("OREN_TEST_NATIVE_JOBS", 0), "parallel jobs for native tests (env OREN_TEST_NATIVE_JOBS); default min(--jobs,4)")
		full        = flag.Bool("full", envBool("OREN_TEST_FULL", false), "run the full curated suite (env OREN_TEST_FULL=1)")
		verbose     = flag.Bool("verbose", envBool("OREN_TEST_VERBOSE", false), "print per-test progress (env OREN_TEST_VERBOSE=1)")
		selfhost    = flag.Bool("selfhost", envBool("OREN_TEST_SELFHOST", false), "run self-hosting stability gate (env OREN_TEST_SELFHOST=1); implied by --full")
		selfhostNative = flag.Bool("selfhost-native", envBool("OREN_TEST_SELFHOST_NATIVE", false), "also run the native self-hosting gate (build+run a stage2 native compiler) (env OREN_TEST_SELFHOST_NATIVE=1); implied by --full")
	)
	flag.Parse()

	if *jobs < 1 {
		*jobs = 1
	}
	if *jobs > 32 {
		*jobs = 32
	}
	fixtureJobsEff := *fixtureJobs
	if fixtureJobsEff == 0 {
		fixtureJobsEff = *jobs
		if fixtureJobsEff > 4 {
			fixtureJobsEff = 4
		}
	}
	if fixtureJobsEff < 1 {
		fixtureJobsEff = 1
	}
	if fixtureJobsEff > 32 {
		fixtureJobsEff = 32
	}
	nativeJobsEff := *nativeJobs
	if nativeJobsEff == 0 {
		nativeJobsEff = *jobs
		if nativeJobsEff > 4 {
			nativeJobsEff = 4
		}
	}
	if nativeJobsEff < 1 {
		nativeJobsEff = 1
	}
	if nativeJobsEff > 32 {
		nativeJobsEff = 32
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
	if _, err := os.Stat("./oredoc"); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: ./oredoc not found; run `make oredoc` or `make test`.")
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
	if err := auditStdlibModernStyle(); err != nil {
		fmt.Fprintln(os.Stderr, "stdlib audit failed:", err)
		os.Exit(1)
	}
	if *full || *selfhost {
		if err := runSelfHostingGate(timeoutBin, gcArg, buildTimeout); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}

		// Optional native self-hosting gate (rolling; slower). This is separate from the bytecode
		// self-host gate because it requires the syscall-first native runtime surface to be present.
		enableNative := *full || *selfhostNative
		if enableNative {
			nt := hostNativeTarget()
			if nt == "" {
				fmt.Fprintln(os.Stderr, "WARN: native self-host gate skipped: unsupported host OS:", runtime.GOOS)
			} else if runtime.GOARCH != "arm64" {
				fmt.Fprintln(os.Stderr, "WARN: native self-host gate skipped: unsupported host arch:", runtime.GOARCH)
			} else {
				if err := runNativeSelfHostingGate(timeoutBin, gcArg, buildTimeout, nt, hostNativeArch()); err != nil {
					fmt.Fprintln(os.Stderr, err.Error())
					os.Exit(1)
				}
			}
		}
	}
	if err := auditRuntimeNativeModernStyle(); err != nil {
		fmt.Fprintln(os.Stderr, "runtime_native audit failed:", err)
		os.Exit(1)
	}
	if err := auditRepoModernStyle(); err != nil {
		fmt.Fprintln(os.Stderr, "repo style audit failed:", err)
		os.Exit(1)
	}
	if err := auditIncludeChunkCoherence(); err != nil {
		fmt.Fprintln(os.Stderr, "include chunk audit failed:", err)
		os.Exit(1)
	}
	if err := auditArm64AdrFixupSlots(); err != nil {
		fmt.Fprintln(os.Stderr, "arm64 adr fixup audit failed:", err)
		os.Exit(1)
	}
	if err := auditArm64MachoGotStubSlots(); err != nil {
		fmt.Fprintln(os.Stderr, "arm64 Mach-O GOT stub audit failed:", err)
		os.Exit(1)
	}

	// Curated lists: keep small and integration-first.
	nativeTests := []string{
		"tests/native/test_integration_suite.oren",
		"tests/native/test_simd_suite.oren",
		"tests/native/test_debug_panic.oren",
		// Pure-functional encoder goldens; no syscalls; should stay fast + deterministic.
		"tests/native/test_arm64_encoding.oren",
	}
	moduleTestsFast := []string{
		// Keep fast suite small: prefer a few integration-first programs.
		"tests/modules/test_integration_suite.oren",
		// Spawn/join timeout is a critical "no hangs" guard.
		"tests/modules/test_spawn_join_timeout.oren",
		// Deterministic "OOM-like" behavior guard for typed buffers.
		"tests/modules/test_buffer_payload_limit.oren",
	}
	moduleTestsFull := []string{
		"tests/modules/test_integration_suite.oren",
		"tests/modules/test_shapes.oren",
		"tests/modules/test_spawn.oren",
		"tests/modules/test_spawn_join_timeout.oren",
		"tests/modules/test_buffer_payload_limit.oren",
		"tests/modules/test_read_bytes.oren",
		"tests/modules/test_bytes_set_endian.oren",
		"tests/modules/test_int_casts.oren",
		"tests/modules/test_int_casts_checked.oren",
		"tests/modules/test_int_ops_wrap.oren",
		"tests/modules/test_float_ops.oren",
		"tests/modules/test_cast_sugar.oren",
		"tests/modules/test_cast_overflow.oren",
		"tests/modules/test_as_cast.oren",
		"tests/modules/test_bitcast.oren",
		"tests/modules/test_for_in_bytes_typed.oren",
		"tests/modules/test_iter_buffers.oren",
		"tests/modules/test_iter_range.oren",
		"tests/modules/test_typed_struct_fields.oren",
		"tests/modules/test_container_methods.oren",
		"tests/modules/test_list_slice_view.oren",
		"tests/modules/test_int_literal_bases.oren",
		"tests/modules/test_generic_call_specialization.oren",
		"tests/modules/test_generic_fn_monomorph_dot.oren",
		"tests/modules/test_generic_trait_constraints.oren",
		"tests/modules/test_mod.oren",
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
		"tests/modules/test_math.oren",
		"tests/modules/test_math_rounding.oren",
		"tests/modules/test_math_trig_huge.oren",
		"tests/modules/test_linalg.oren",
		"tests/modules/test_time_std.oren",
		"tests/modules/test_buffer_views.oren",
		"tests/modules/test_buffer_alignment.oren",
		"tests/modules/test_buffer_alloc_stress.oren",
		"tests/modules/test_u8_buf_bytes_helpers.oren",
		"tests/modules/test_alloc_gc_scale.oren",
		"tests/modules/test_regex.oren",
		"tests/modules/test_json.oren",
		"tests/modules/test_json_comments.oren",
		"tests/modules/test_json_serde_attrs.oren",
		"tests/modules/test_yaml_serde_attrs.oren",
		"tests/modules/test_yaml_comments.oren",
		"tests/modules/test_cbor_serde_attrs.oren",
		"tests/modules/test_cbor_sequence.oren",
		"tests/modules/test_cbor_serde_streaming.oren",
		"tests/modules/test_format_nested_roundtrip.oren",
		"tests/modules/test_switch.oren",
		"tests/modules/test_varargs.oren",
	}
	avmTestsFast := []string{
		// Broad smoke covers the common surface area quickly.
		"tests/avm/test_smoke_suite.oren",
		// Crypto primitives needed for signed artifact verification in AVM.
		"tests/avm/test_crypto_sha256_vectors.oren",
		// Snapshot/resume and multiverse are core AVM differentiators.
		"tests/avm/test_snapshot_tasks_resume.oren",
		"tests/avm/test_multiverse_invalid_obc.oren",
		// Determinism + sandbox guards.
		"tests/avm/test_time_rng_deterministic.oren",
		"tests/avm/test_vfs_no_host_fs.oren",
		"tests/avm/test_vproc_no_host_proc.oren",
		"tests/avm/test_vnet_no_host_net.oren",
	}
	avmTestsFull := []string{
		"tests/avm/test_smoke_suite.oren",
		"tests/avm/test_crypto_sha256_vectors.oren",
		"tests/avm/test_map_iter_deterministic.oren",
		"tests/avm/test_iter_range.oren",
		"tests/avm/test_int_literal_bases.oren",
		"tests/avm/test_generic_call_specialization.oren",
		"tests/avm/test_spawn_join_timeout.oren",
		"tests/avm/test_policy_scan.oren",
		"tests/avm/test_job_scan.oren",
		"tests/avm/test_snapshot_resume.oren",
		"tests/avm/test_snapshot_resume_record_log.oren",
		"tests/avm/test_snapshot_vfs_resume.oren",
		"tests/avm/test_state_hash_includes_vfs.oren",
		"tests/avm/test_snapshot_tasks_resume.oren",
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
		timeout time.Duration
		log     string
		ok      func(rc int) bool
		cleanup []string
	}{
		{
			name: "manifest_bytecode",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --target %s --deterministic --manifest -o %q > %q && "+
					"test -s %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Eq %q %q",
				"tests/modules/test_strings.oren",
				*target,
				"build/manifest_bytecode.obc",
				"build/manifest_bytecode.out",
				"build/manifest_bytecode.obc.manifest.json",
				"\"kind\":\"bytecode\"",
				"build/manifest_bytecode.obc.manifest.json",
				"\"deterministic\":true",
				"build/manifest_bytecode.obc.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				"build/manifest_bytecode.obc.manifest.json",
			),
			log:     "build/logs/manifest_bytecode.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/manifest_bytecode.obc", "build/manifest_bytecode.out", "build/manifest_bytecode.obc.manifest.json"},
		},
		{
			name: "manifest_meta",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --deterministic --manifest -o %q > %q && "+
					"test -s %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Eq %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				*target,
				"build/manifest_meta.meta.json",
				"build/manifest_meta.out",
				"build/manifest_meta.meta.json.manifest.json",
				"\"kind\":\"meta\"",
				"build/manifest_meta.meta.json.manifest.json",
				"\"deterministic\":true",
				"build/manifest_meta.meta.json.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				"build/manifest_meta.meta.json.manifest.json",
			),
			log:     "build/logs/manifest_meta.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/manifest_meta.meta.json", "build/manifest_meta.out", "build/manifest_meta.meta.json.manifest.json"},
		},
		{
			name: "signed_obc_verify_cli",
			cmd: fmt.Sprintf(
				"set -e; "+
					"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
					"echo \"[fixture] build orensign\"; "+
					"go build -o \"$wd/orensign\" ./cmd/orensign; "+
					"echo \"[fixture] keygen (ephemeral)\"; "+
					"\"$wd/orensign\" keygen --out \"$wd/ca\"; "+
					"echo \"[fixture] build unsigned obc\"; "+
					"./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] sign obc\"; "+
					"\"$wd/orensign\" sign-obc --sk \"$wd/ca/root_ed25519_sk.bin\" --in %q --out %q; "+
					"echo \"[fixture] verify + run signed\"; "+
					"./avm --require-sig --trusted-pubkey \"$wd/ca/root_ed25519_pk.bin\" %q > %q; "+
					"grep -Fq %q %q; "+
					"echo \"[fixture] verify unsigned must fail\"; "+
					"set +e; ./avm --require-sig --trusted-pubkey \"$wd/ca/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
					"test $rc -ne 0",
				"build/tmp/fixture_signed_obc_verify_cli",
				"tests/avm/fixtures/signed_obc_smoke.oren",
				*target,
				"build/tmp/fixture_signed_obc_verify_cli/signed_obc_smoke.obc",
				gcArg,
				"build/tmp/fixture_signed_obc_verify_cli/signed_obc_smoke.obc",
				"build/tmp/fixture_signed_obc_verify_cli/signed_obc_smoke.signed.obc",
				"build/tmp/fixture_signed_obc_verify_cli/signed_obc_smoke.signed.obc",
				"build/tmp/fixture_signed_obc_verify_cli/fixture_signed_obc_verify_cli.out",
				"signed obc OK",
				"build/tmp/fixture_signed_obc_verify_cli/fixture_signed_obc_verify_cli.out",
				"build/tmp/fixture_signed_obc_verify_cli/signed_obc_smoke.obc",
			),
			log: "build/logs/fixture_signed_obc_verify_cli.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/tmp/fixture_signed_obc_verify_cli",
			},
		},
		{
			name: "signed_obc_verify_cert_chain_cli",
			cmd: fmt.Sprintf(
				"set -e; "+
					"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
					"echo \"[fixture] build orensign\"; "+
					"go build -o \"$wd/orensign\" ./cmd/orensign; "+
					"echo \"[fixture] keygen root/org/dev (ephemeral)\"; "+
					"mkdir -p \"$wd/ca\"; "+
					"\"$wd/orensign\" keygen --out \"$wd/ca/root\"; "+
					"\"$wd/orensign\" keygen --out \"$wd/ca/org\"; "+
					"\"$wd/orensign\" keygen --out \"$wd/ca/dev\"; "+
					"echo \"[fixture] issue root->org (can_issue) and org->dev certs\"; "+
					"\"$wd/orensign\" issue-cert --issuer-sk \"$wd/ca/root/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/org/root_ed25519_pk.bin\" --out \"$wd/ca/org.cert\" --can-issue; "+
					"\"$wd/orensign\" issue-cert --issuer-sk \"$wd/ca/org/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/dev/root_ed25519_pk.bin\" --out \"$wd/ca/dev.cert\"; "+
					"echo \"[fixture] build unsigned obc\"; "+
					"./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] sign obc with dev key + embed leaf-first chain\"; "+
					"\"$wd/orensign\" sign-obc --sk \"$wd/ca/dev/root_ed25519_sk.bin\" --cert \"$wd/ca/dev.cert\" --cert \"$wd/ca/org.cert\" --in %q --out %q; "+
					"echo \"[fixture] verify + run (require chain)\"; "+
					"./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > %q; "+
					"grep -Fq %q %q; "+
					"echo \"[fixture] verify missing chain must fail\"; "+
					"\"$wd/orensign\" sign-obc --sk \"$wd/ca/dev/root_ed25519_sk.bin\" --in %q --out %q; "+
					"set +e; ./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
					"test $rc -ne 0; "+
					"echo \"[fixture] verify root-sign without chain must fail under require-cert-chain\"; "+
					"\"$wd/orensign\" sign-obc --sk \"$wd/ca/root/root_ed25519_sk.bin\" --in %q --out %q; "+
					"set +e; ./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
					"test $rc -ne 0",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli",
				"tests/avm/fixtures/signed_obc_smoke.oren",
				*target,
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.obc",
				gcArg,
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.devchain.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.devchain.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/fixture_signed_obc_verify_cert_chain_cli.out",
				"signed obc OK",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/fixture_signed_obc_verify_cert_chain_cli.out",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.dev_nocert.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.dev_nocert.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.root_nocert.obc",
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli/signed_obc_chain_smoke.root_nocert.obc",
			),
			log: "build/logs/fixture_signed_obc_verify_cert_chain_cli.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/tmp/fixture_signed_obc_verify_cert_chain_cli",
			},
		},
		{
			name: "bytecode_negative_int_constants",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --target %s --deterministic -o %q > %q && "+
					"./avm --disasm-consts %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/bytecode_neg_int_const.oren",
				*target,
				"build/bytecode_neg_int_const.obc",
				"build/bytecode_neg_int_const.build.out",
				"build/bytecode_neg_int_const.obc",
				"build/bytecode_neg_int_const.disasm.out",
				"=-4",
				"build/bytecode_neg_int_const.disasm.out",
				"=-3",
				"build/bytecode_neg_int_const.disasm.out",
			),
			log:     "build/logs/fixture_bytecode_negative_int_constants.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/bytecode_neg_int_const.obc", "build/bytecode_neg_int_const.build.out", "build/bytecode_neg_int_const.disasm.out"},
		},
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
			name: "oren_meta_globals_attrs",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && grep -Fq %q %q && grep -Fq %q %q",
				"tests/fixtures/meta_attrs_globals.oren",
				*target,
				"build/meta_attrs_globals.meta.json",
				"\"globals\": [",
				"build/meta_attrs_globals.meta.json",
				"myorg.global",
				"build/meta_attrs_globals.meta.json",
			),
			log:     "build/logs/oren_meta_globals_attrs.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/meta_attrs_globals.meta.json"},
		},
		{
			name: "oren_meta_serde_schema",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/modules/test_json_serde_attrs.oren",
				*target,
				"build/serde_schema.meta.json",
				"\"serde\": {\"version\": 1, \"format\": \"json\", \"tag\": \"User\"",
				"build/serde_schema.meta.json",
				"\"wire\": \"user_id\"",
				"build/serde_schema.meta.json",
				"\"skip\": true",
				"build/serde_schema.meta.json",
				"\"default\": 0",
				"build/serde_schema.meta.json",
				"\"ann_type\": \"i32\"",
				"build/serde_schema.meta.json",
			),
			log:     "build/logs/oren_meta_serde_schema.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/serde_schema.meta.json"},
		},
		{
			name: "oren_meta_serde_formats",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/meta_serde_formats.oren",
				*target,
				"build/serde_formats.meta.json",
				"\"serde\": {\"version\": 1, \"format\": \"json\", \"tag\": \"User\"",
				"build/serde_formats.meta.json",
				"\"formats\": [\"json\", \"yaml\"]",
				"build/serde_formats.meta.json",
			),
			log:     "build/logs/oren_meta_serde_formats.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/serde_formats.meta.json"},
		},
		{
			name: "oredoc_openapi_export",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && "+
					"./oredoc openapi %q -o %q --title %q --version %q --format %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/modules/test_json_serde_attrs.oren",
				*target,
				"build/openapi.meta.json",
				"build/openapi.meta.json",
				"build/openapi.json",
				"Oren API",
				"0.0.0",
				"json",
				"\"openapi\": \"3.1.0\"",
				"build/openapi.json",
				"\"components\": {",
				"build/openapi.json",
				"\"schemas\": {",
				"build/openapi.json",
				"\"User\": {",
				"build/openapi.json",
			),
			log:     "build/logs/oredoc_openapi_export.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/openapi.meta.json", "build/openapi.json"},
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
				"./oren build %q --backend native --target %s --metadata --deterministic --manifest -o %q > %q && "+
					"./oren build %q --backend native --target %s --metadata --deterministic --manifest -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q && "+
					"test -s %q && test -s %q && "+
					"grep -Fq %q %q && grep -Fq %q %q && grep -Eq %q %q && "+
					"grep -Fq %q %q && grep -Fq %q %q && grep -Eq %q %q",
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
				"build/deterministic_native_meta_1.meta.json.manifest.json",
				"build/deterministic_native_meta_2.meta.json.manifest.json",
				"\"kind\":\"meta\"",
				"build/deterministic_native_meta_1.meta.json.manifest.json",
				"\"deterministic\":true",
				"build/deterministic_native_meta_1.meta.json.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				"build/deterministic_native_meta_1.meta.json.manifest.json",
				"\"kind\":\"meta\"",
				"build/deterministic_native_meta_2.meta.json.manifest.json",
				"\"deterministic\":true",
				"build/deterministic_native_meta_2.meta.json.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				"build/deterministic_native_meta_2.meta.json.manifest.json",
			),
			log: "build/logs/deterministic_native_meta_hash.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/deterministic_native_meta_1",
				"build/deterministic_native_meta_1.meta.json",
				"build/deterministic_native_meta_1.out",
				"build/deterministic_native_meta_1.hash",
				"build/deterministic_native_meta_1.manifest.json",
				"build/deterministic_native_meta_1.meta.json.manifest.json",
				"build/deterministic_native_meta_2",
				"build/deterministic_native_meta_2.meta.json",
				"build/deterministic_native_meta_2.out",
				"build/deterministic_native_meta_2.hash",
				"build/deterministic_native_meta_2.manifest.json",
				"build/deterministic_native_meta_2.meta.json.manifest.json",
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
				name: "compiler_bytecode_assign_undefined_diag",
				cmd: fmt.Sprintf(
					"sh -c 'out=$(./oren build %q --backend bytecode --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\n\" \"$out\"; test $rc -ne 0; printf \"%%s\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"; printf \"%%s\n\" \"$out\" | grep -F \"Bytecode codegen errors:\"; printf \"%%s\n\" \"$out\" | grep -F \"undefined variable in assignment\"'",
					"tests/fixtures/bytecode_assign_undefined.oren",
					*target,
					"build/bytecode_assign_undefined.obc",
					gcArg,
				),
				log:     "build/logs/compiler_bytecode_assign_undefined_diag.log",
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{"build/bytecode_assign_undefined.obc"},
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
			name: "compiler_generic_call_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"unspecialized call to generic function\"'",
				"tests/native/fixtures/generic_unspecialized_call.oren",
				*target,
				"build/generic_unspecialized_call",
				gcArg,
			),
			log:     "build/logs/compiler_generic_call_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/generic_unspecialized_call"},
		},
		{
			name: "compiler_generic_constraint_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"missing impl for trait\"'",
				"tests/native/fixtures/generic_constraint_missing_impl.oren",
				*target,
				"build/generic_constraint_missing_impl",
				gcArg,
			),
			log:     "build/logs/compiler_generic_constraint_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/generic_constraint_missing_impl"},
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
				name: "build_cli_modern_equals_and_ordering",
				cmd: fmt.Sprintf(
					"./oren build --backend=native --target=%s --out=%q %q%s",
					*target,
					"build/cli_modern_eq",
					"tests/native/fixtures/struct_field_assign_ok.oren",
					gcArg,
				),
				log:     "build/logs/build_cli_modern_equals_and_ordering.log",
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{"build/cli_modern_eq"},
			},
			{
				name: "help_json_root",
				cmd:  "sh -c 'out=$(./oren --help=json 2>&1); rc=$?; printf \"%s\\n\" \"$out\"; test $rc -eq 0; printf \"%s\\n\" \"$out\" | grep -F \"\\\"name\\\":\\\"oren\\\"\"; printf \"%s\\n\" \"$out\" | grep -F \"\\\"commands\\\"\"'",
				log:  "build/logs/help_json_root.log",
				ok:   func(rc int) bool { return rc == 0 },
			},
			{
				name: "help_json_build",
				cmd:  "sh -c 'out=$(./oren build --help=json 2>&1); rc=$?; printf \"%s\\n\" \"$out\"; test $rc -eq 0; printf \"%s\\n\" \"$out\" | grep -F \"\\\"cmd\\\":\\\"build\\\"\"; printf \"%s\\n\" \"$out\" | grep -F \"\\\"options\\\"\"'",
				log:  "build/logs/help_json_build.log",
				ok:   func(rc int) bool { return rc == 0 },
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
			name: "typecheck_rejects_bad_cast",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --typecheck --target %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=typecheck code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"typecheck:\"'",
				"tests/fixtures/typecheck_bad_cast.oren",
				*target,
				"build/typecheck_bad_cast",
				gcArg,
			),
			log:     "build/logs/typecheck_rejects_bad_cast.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/typecheck_bad_cast"},
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
			name:    "struct_field_assign_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", "tests/native/fixtures/struct_field_assign_ok.oren", *target, "build/struct_field_assign_ok", gcArg),
			log:     "build/logs/struct_field_assign_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/struct_field_assign_ok"},
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

	if *full {
		fixtureEnv := sanitizedAllocatorEnvPrefix()
		// Compiler-in-AVM v1 smoke (VirtualFS, argv-as-data):
		//
		// Build the compiler to `.obc`, then run a small AVM harness which:
		// - runs the compiler as a *nested* universe via `avm.run_obc_bytes`
		// - feeds source via VirtualFS fixtures (no host FS reads inside the child)
		// - reads the produced `.obc` back via returned `vfs_snapshot` bytes
		// - runs the produced program as another nested universe
		//
		// This closes the "no host effects" loop for compilation while staying bootstrap-friendly.
		fixtures = append(fixtures, struct {
			name    string
			cmd     string
			timeout time.Duration
			log     string
			ok      func(rc int) bool
			cleanup []string
		}{
			name: "compiler_in_avm_smoke",
			cmd: fmt.Sprintf(
				"set -e; "+
					"echo \"[fixture] build compiler obc\"; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] build harness obc\"; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] run harness (host read build/ only)\"; "+
					"%s ./avm --deny-by-default --allow-domains \"0,1,6,8\" --fs-backend host --fs-allow-prefixes %q %q > %q; "+
					"grep -Fq %q %q || { echo \"[fixture] output:\"; cat %q; exit 1; }",
				fixtureEnv,
				"oren.oren",
				*target,
				"build/oren_compiler.obc",
				gcArg,
				fixtureEnv,
				"tests/avm/fixtures/compiler_in_avm_vfs_harness.oren",
				*target,
				"build/compiler_in_avm_vfs_harness.obc",
				gcArg,
				fixtureEnv,
				"build/",
				"build/compiler_in_avm_vfs_harness.obc",
				"build/fixture_compiler_in_avm_smoke.run.out",
				"compiler in avm vfs OK",
				"build/fixture_compiler_in_avm_smoke.run.out",
				"build/fixture_compiler_in_avm_smoke.run.out",
			),
			timeout: 8 * time.Minute,
			log:     "build/logs/fixture_compiler_in_avm_smoke.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/oren_compiler.obc",
				"build/compiler_in_avm_vfs_harness.obc",
				"build/fixture_compiler_in_avm_smoke.run.out",
			},
		})

		// Compiler-in-AVM v1 smoke (precompiled stdlib bundle `.obc` linking):
		// - build `lib/std/stdlib.oren` as a `.obc` library bundle (OBX exports)
		// - run the compiler as a nested universe using VFS fixtures
		// - compile a program that imports `std:math` with `--stdlib-mode obc`
		// - run the produced program as another nested universe
		fixtures = append(fixtures, struct {
			name    string
			cmd     string
			timeout time.Duration
			log     string
			ok      func(rc int) bool
			cleanup []string
		}{
			name: "compiler_in_avm_stdlib_obc_smoke",
			cmd: fmt.Sprintf(
				"set -e; "+
					"echo \"[fixture] build stdlib bundle obc\"; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q --obc-lib%s; "+
					"echo \"[fixture] build compiler obc\"; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] build harness obc\"; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q%s; "+
					"echo \"[fixture] run harness\"; "+
					"%s ./avm --deny-by-default --allow-domains \"0,1,6,8\" --fs-backend host --fs-allow-prefixes %q %q > %q; "+
					"grep -Fq %q %q || { echo \"[fixture] output:\"; cat %q; exit 1; }",
				fixtureEnv,
				"lib/std/stdlib.oren",
				*target,
				"build/stdlib_bundle.obc",
				gcArg,
				fixtureEnv,
				"oren.oren",
				*target,
				"build/oren_compiler.obc",
				gcArg,
				fixtureEnv,
				"tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren",
				*target,
				"build/compiler_in_avm_vfs_stdlib_obc_harness.obc",
				gcArg,
				fixtureEnv,
				"build/",
				"build/compiler_in_avm_vfs_stdlib_obc_harness.obc",
				"build/fixture_compiler_in_avm_stdlib_obc_smoke.run.out",
				"compiler in avm vfs stdlib obc OK",
				"build/fixture_compiler_in_avm_stdlib_obc_smoke.run.out",
				"build/fixture_compiler_in_avm_stdlib_obc_smoke.run.out",
			),
			timeout: 10 * time.Minute,
			log:     "build/logs/fixture_compiler_in_avm_stdlib_obc_smoke.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/stdlib_bundle.obc",
				"build/oren_compiler.obc",
				"build/compiler_in_avm_vfs_stdlib_obc_harness.obc",
				"build/fixture_compiler_in_avm_stdlib_obc_smoke.run.out",
			},
		})

		// Generic trait constraints must be enforced at monomorphization time.
		// This fixture expects compilation to fail with a clear diagnostic.
		fixtures = append(fixtures, struct {
			name    string
			cmd     string
			timeout time.Duration
			log     string
			ok      func(rc int) bool
			cleanup []string
		}{
			name: "generic_constraint_missing_impl",
			cmd: fmt.Sprintf(
				"set -e; "+
					"out=%q; "+
					"rm -f \"$out\"; "+
					"set +e; "+
					"%s ./oren build %q --backend bytecode --target %s -o %q%s > \"$out\" 2>&1; "+
					"rc=$?; "+
					"set -e; "+
					"if [ $rc -eq 0 ]; then echo \"[fixture] expected non-zero exit\"; cat \"$out\"; exit 1; fi; "+
					"grep -Fq %q \"$out\"",
				"build/fixture_generic_constraint_missing_impl.out",
				fixtureEnv,
				"tests/fixtures/generic_constraint_missing_impl.oren",
				*target,
				"build/tmp_generic_constraint_missing_impl.obc",
				gcArg,
				"missing impl for trait",
			),
			timeout: 2 * time.Minute,
			log:     "build/logs/fixture_generic_constraint_missing_impl.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{
				"build/fixture_generic_constraint_missing_impl.out",
				"build/tmp_generic_constraint_missing_impl.obc",
			},
		})
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

	// Run fixtures in parallel (bounded by --fixture-jobs).
	//
	// Fixtures are intended to be small, high-signal correctness guards. Most are
	// independent and safe to parallelize for wall-time reduction.
	type fixtureResult struct {
		name string
		log  string
		ok   bool
	}
	fixtureResults := make([]fixtureResult, len(fixtures))
	var wgFixtures sync.WaitGroup
	semFixtures := make(chan struct{}, fixtureJobsEff)
	for i := range fixtures {
		wgFixtures.Add(1)
		semFixtures <- struct{}{}
		go func(i int) {
			defer wgFixtures.Done()
			defer func() { <-semFixtures }()
			fx := fixtures[i]
			if *verbose {
				vprintln("fixture: " + fx.name)
			}
			t := buildTimeout
			if fx.timeout != 0 {
				t = fx.timeout
			}
			rc := runWithTimeout(timeoutBin, t, fx.cmd, fx.log)
			for _, c := range fx.cleanup {
				_ = os.RemoveAll(c)
			}
			fixtureResults[i] = fixtureResult{name: fx.name, log: fx.log, ok: fx.ok(rc)}
		}(i)
	}
	wgFixtures.Wait()
	for _, fr := range fixtureResults {
		if !fr.ok {
			fmt.Fprintf(os.Stderr, "fixture failed: %s (log: %s)\n", fr.name, fr.log)
			_ = catFile(os.Stderr, fr.log)
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
			_ = os.RemoveAll(c)
		}
	}

	// Native tests: parallel for wall-time reduction (bounded by --native-jobs).
	nativeRes := runNativeTests(timeoutBin, *target, gcArg, buildTimeout, runTimeout, *verbose, vprintln, nativeJobsEff, nativeTests)
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

func sanitizedAllocatorEnvPrefix() string {
	// Tests must not be sensitive to a user's shell env.
	// Keep allocator policy stable unless a test explicitly opts in.
	//
	// Note: `env VAR=` sets VAR to empty string, which our runtimes treat as "unset".
	//
	// Also clear noisy debugging toggles so `oretest` output stays high-signal.
	return "env OREN_RAW_MMAP_THRESHOLD= OREN_BUF_ALIGN= OREN_BUF_FORCE_MMAP= OREN_BUF_PAYLOAD_LIMIT_BYTES= OREN_TRACE_PASSES= AVM_TRACE_BYTES="
}

type suiteResult struct {
	ok     bool
	pass   int
	total  int
	failed []testResult
}

func runNativeTests(timeoutBin, target, gcArg string, buildTimeout, runTimeout time.Duration, verbose bool, vprintln func(string), jobs int, tests []string) suiteResult {
	res := suiteResult{ok: true, total: len(tests)}
	envPrefix := sanitizedAllocatorEnvPrefix()
	results := runParallel(jobs, tests, func(path string) testResult {
		name := strings.TrimSuffix(filepath.Base(path), ".oren")
		if verbose {
			vprintln("native: " + path)
		}

		workdir := filepath.Join("build", "tmp", "native_"+name)
		_ = os.RemoveAll(workdir)
		_ = os.MkdirAll(filepath.Join(workdir, "build"), 0o755)

		out := filepath.Join(workdir, "build", name)
		log := filepath.Join("build", "logs", "native_"+name+".log")

		buildCmd := fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", path, target, out, gcArg)
		if rc := runWithTimeout(timeoutBin, buildTimeout, buildCmd, log); rc != 0 {
			_ = os.RemoveAll(workdir)
			return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: log}
		}

		rc := 0
		runLog := log

		switch name {
		case "test_simd_suite":
			// Validate scalar vs SIMD results by running the same binary twice with env toggles,
			// and comparing stable key/value outputs.
			scalarLog := log
			_ = os.Remove(scalarLog)
			scalarCmd := fmt.Sprintf("%s OREN_NO_SIMD=1 ./%s", envPrefix, out)
			rc = runWithTimeout(timeoutBin, runTimeout, scalarCmd, scalarLog)
			runLog = scalarLog
			if rc != 0 {
				break
			}

			sSIMD, okSIMD := extractValueFromLog(scalarLog, "SIMD_ENABLED=")
			if !okSIMD {
				_ = appendFileLine(scalarLog, "oretest: missing SIMD_ENABLED= output in scalar run")
				rc = 1
				break
			}
			if strings.TrimSpace(sSIMD) != "0" {
				_ = appendFileLine(scalarLog, "oretest: expected SIMD_ENABLED=0 in scalar run (OREN_NO_SIMD=1)")
				rc = 1
				break
			}

			wantKeys := []string{"DOT_I32=", "I32_ADD_SUM=", "I32_MUL_SUM=", "F32_ADD_HASH=", "F32_MUL_HASH=", "DOT_F32_BITS=", "GEMM_F64_4X4_HASH="}
			wantVals := map[string]string{}
			for _, k := range wantKeys {
				v, ok := extractValueFromLog(scalarLog, k)
				if !ok {
					_ = appendFileLine(scalarLog, "oretest: missing "+k+" output in scalar run")
					rc = 1
					break
				}
				wantVals[k] = strings.TrimSpace(v)
			}
			if rc != 0 {
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "native_"+name+"_simd.log")
				_ = os.Remove(simdLog)
				simdCmd := fmt.Sprintf("%s OREN_ENABLE_SIMD=1 ./%s", envPrefix, out)
				rc = runWithTimeout(timeoutBin, runTimeout, simdCmd, simdLog)
				runLog = simdLog
				if rc != 0 {
					break
				}

				tSIMD, okSIMD2 := extractValueFromLog(simdLog, "SIMD_ENABLED=")
				if !okSIMD2 {
					_ = appendFileLine(simdLog, "oretest: missing SIMD_ENABLED= output in SIMD run")
					rc = 1
					break
				}
				if strings.TrimSpace(tSIMD) != "1" {
					_ = appendFileLine(simdLog, "oretest: expected SIMD_ENABLED=1 in SIMD run (OREN_ENABLE_SIMD=1)")
					rc = 1
					break
				}

				for _, k := range wantKeys {
					tv, ok := extractValueFromLog(simdLog, k)
					if !ok {
						_ = appendFileLine(simdLog, "oretest: missing "+k+" output in SIMD run")
						rc = 1
						break
					}
					tv = strings.TrimSpace(tv)
					if tv != wantVals[k] {
						_ = appendFileLine(simdLog, "oretest: native SIMD mismatch for "+k)
						_ = appendFileLine(simdLog, "scalar "+k+wantVals[k])
						_ = appendFileLine(simdLog, "simd   "+k+tv)
						rc = 1
						break
					}
				}
			}
		case "test_simd_dot_i32_native":
			// Validate scalar vs SIMD results by running the same binary twice with env toggles.
			//
			// This is the native-backend analogue of the AVM SIMD determinism guard: the SIMD path must
			// preserve scalar semantics exactly.
			scalarLog := log
			_ = os.Remove(scalarLog)
			scalarCmd := fmt.Sprintf("%s OREN_NO_SIMD=1 ./%s", envPrefix, out)
			rc = runWithTimeout(timeoutBin, runTimeout, scalarCmd, scalarLog)
			if rc != 0 {
				runLog = scalarLog
				break
			}
			scalarDOT, okDOT := extractValueFromLog(scalarLog, "DOT=")
			scalarSIMD, okSIMD := extractValueFromLog(scalarLog, "SIMD_ENABLED=")
			if !okDOT || !okSIMD {
				_ = appendFileLine(scalarLog, "oretest: missing DOT=/SIMD_ENABLED= output in scalar run")
				rc = 1
				runLog = scalarLog
				break
			}
			if strings.TrimSpace(scalarSIMD) != "0" {
				_ = appendFileLine(scalarLog, "oretest: expected SIMD_ENABLED=0 in scalar run (OREN_NO_SIMD=1)")
				rc = 1
				runLog = scalarLog
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "native_"+name+"_simd.log")
				_ = os.Remove(simdLog)
				simdCmd := fmt.Sprintf("%s OREN_ENABLE_SIMD=1 ./%s", envPrefix, out)
				rc = runWithTimeout(timeoutBin, runTimeout, simdCmd, simdLog)
				if rc != 0 {
					runLog = simdLog
					break
				}
				simdDOT, okDOT2 := extractValueFromLog(simdLog, "DOT=")
				simdSIMD, okSIMD2 := extractValueFromLog(simdLog, "SIMD_ENABLED=")
				if !okDOT2 || !okSIMD2 {
					_ = appendFileLine(simdLog, "oretest: missing DOT=/SIMD_ENABLED= output in SIMD run")
					rc = 1
					runLog = simdLog
					break
				}
				if strings.TrimSpace(simdSIMD) != "1" {
					_ = appendFileLine(simdLog, "oretest: expected SIMD_ENABLED=1 in SIMD run (OREN_ENABLE_SIMD=1)")
					rc = 1
					runLog = simdLog
					break
				}
				if strings.TrimSpace(simdDOT) != strings.TrimSpace(scalarDOT) {
					_ = appendFileLine(simdLog, "oretest: native SIMD dot mismatch")
					_ = appendFileLine(simdLog, "scalar DOT "+strings.TrimSpace(scalarDOT))
					_ = appendFileLine(simdLog, "simd   DOT "+strings.TrimSpace(simdDOT))
					rc = 1
					runLog = simdLog
					break
				}
			}
		case "test_simd_i32_buf_ops_native":
			// Same pattern as simd_dot: run scalar vs SIMD and compare stable outputs.
			scalarLog := log
			_ = os.Remove(scalarLog)
			scalarCmd := fmt.Sprintf("%s OREN_NO_SIMD=1 ./%s", envPrefix, out)
			rc = runWithTimeout(timeoutBin, runTimeout, scalarCmd, scalarLog)
			runLog = scalarLog
			if rc != 0 {
				break
			}
			sAdd, okA := extractValueFromLog(scalarLog, "ADD_SUM=")
			sMul, okM := extractValueFromLog(scalarLog, "MUL_SUM=")
			sSIMD, okS := extractValueFromLog(scalarLog, "SIMD_ENABLED=")
			if !okA || !okM || !okS {
				_ = appendFileLine(scalarLog, "oretest: missing ADD_SUM=/MUL_SUM=/SIMD_ENABLED= output in scalar run")
				rc = 1
				break
			}
			if strings.TrimSpace(sSIMD) != "0" {
				_ = appendFileLine(scalarLog, "oretest: expected SIMD_ENABLED=0 in scalar run (OREN_NO_SIMD=1)")
				rc = 1
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "native_"+name+"_simd.log")
				_ = os.Remove(simdLog)
				simdCmd := fmt.Sprintf("%s OREN_ENABLE_SIMD=1 ./%s", envPrefix, out)
				rc = runWithTimeout(timeoutBin, runTimeout, simdCmd, simdLog)
				runLog = simdLog
				if rc != 0 {
					break
				}
				tAdd, okA2 := extractValueFromLog(simdLog, "ADD_SUM=")
				tMul, okM2 := extractValueFromLog(simdLog, "MUL_SUM=")
				tSIMD, okS2 := extractValueFromLog(simdLog, "SIMD_ENABLED=")
				if !okA2 || !okM2 || !okS2 {
					_ = appendFileLine(simdLog, "oretest: missing ADD_SUM=/MUL_SUM=/SIMD_ENABLED= output in SIMD run")
					rc = 1
					break
				}
				if strings.TrimSpace(tSIMD) != "1" {
					_ = appendFileLine(simdLog, "oretest: expected SIMD_ENABLED=1 in SIMD run (OREN_ENABLE_SIMD=1)")
					rc = 1
					break
				}
				if strings.TrimSpace(tAdd) != strings.TrimSpace(sAdd) || strings.TrimSpace(tMul) != strings.TrimSpace(sMul) {
					_ = appendFileLine(simdLog, "oretest: native SIMD i32 buf ops mismatch")
					_ = appendFileLine(simdLog, "scalar ADD_SUM "+strings.TrimSpace(sAdd))
					_ = appendFileLine(simdLog, "simd   ADD_SUM "+strings.TrimSpace(tAdd))
					_ = appendFileLine(simdLog, "scalar MUL_SUM "+strings.TrimSpace(sMul))
					_ = appendFileLine(simdLog, "simd   MUL_SUM "+strings.TrimSpace(tMul))
					rc = 1
					break
				}
			}
		case "test_simd_f32_buf_ops_native":
			// Same pattern: run scalar vs SIMD and compare stable outputs.
			scalarLog := log
			_ = os.Remove(scalarLog)
			scalarCmd := fmt.Sprintf("%s OREN_NO_SIMD=1 ./%s", envPrefix, out)
			rc = runWithTimeout(timeoutBin, runTimeout, scalarCmd, scalarLog)
			runLog = scalarLog
			if rc != 0 {
				break
			}
			sAdd, okA := extractValueFromLog(scalarLog, "ADD_HASH=")
			sMul, okM := extractValueFromLog(scalarLog, "MUL_HASH=")
			sSIMD, okS := extractValueFromLog(scalarLog, "SIMD_ENABLED=")
			if !okA || !okM || !okS {
				_ = appendFileLine(scalarLog, "oretest: missing ADD_HASH=/MUL_HASH=/SIMD_ENABLED= output in scalar run")
				rc = 1
				break
			}
			if strings.TrimSpace(sSIMD) != "0" {
				_ = appendFileLine(scalarLog, "oretest: expected SIMD_ENABLED=0 in scalar run (OREN_NO_SIMD=1)")
				rc = 1
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "native_"+name+"_simd.log")
				_ = os.Remove(simdLog)
				simdCmd := fmt.Sprintf("%s OREN_ENABLE_SIMD=1 ./%s", envPrefix, out)
				rc = runWithTimeout(timeoutBin, runTimeout, simdCmd, simdLog)
				runLog = simdLog
				if rc != 0 {
					break
				}
				tAdd, okA2 := extractValueFromLog(simdLog, "ADD_HASH=")
				tMul, okM2 := extractValueFromLog(simdLog, "MUL_HASH=")
				tSIMD, okS2 := extractValueFromLog(simdLog, "SIMD_ENABLED=")
				if !okA2 || !okM2 || !okS2 {
					_ = appendFileLine(simdLog, "oretest: missing ADD_HASH=/MUL_HASH=/SIMD_ENABLED= output in SIMD run")
					rc = 1
					break
				}
				if strings.TrimSpace(tSIMD) != "1" {
					_ = appendFileLine(simdLog, "oretest: expected SIMD_ENABLED=1 in SIMD run (OREN_ENABLE_SIMD=1)")
					rc = 1
					break
				}
				if strings.TrimSpace(tAdd) != strings.TrimSpace(sAdd) || strings.TrimSpace(tMul) != strings.TrimSpace(sMul) {
					_ = appendFileLine(simdLog, "oretest: native SIMD f32 buf ops mismatch")
					_ = appendFileLine(simdLog, "scalar ADD_HASH "+strings.TrimSpace(sAdd))
					_ = appendFileLine(simdLog, "simd   ADD_HASH "+strings.TrimSpace(tAdd))
					_ = appendFileLine(simdLog, "scalar MUL_HASH "+strings.TrimSpace(sMul))
					_ = appendFileLine(simdLog, "simd   MUL_HASH "+strings.TrimSpace(tMul))
					rc = 1
					break
				}
			}
		case "test_simd_dot_f32_native":
			// Scalar vs SIMD determinism check for f32 dot (returns f64 bits).
			scalarLog := log
			_ = os.Remove(scalarLog)
			scalarCmd := fmt.Sprintf("%s OREN_NO_SIMD=1 ./%s", envPrefix, out)
			rc = runWithTimeout(timeoutBin, runTimeout, scalarCmd, scalarLog)
			runLog = scalarLog
			if rc != 0 {
				break
			}
			sDot, okD := extractValueFromLog(scalarLog, "DOT_BITS=")
			sSIMD, okS := extractValueFromLog(scalarLog, "SIMD_ENABLED=")
			if !okD || !okS {
				_ = appendFileLine(scalarLog, "oretest: missing DOT_BITS=/SIMD_ENABLED= output in scalar run")
				rc = 1
				break
			}
			if strings.TrimSpace(sSIMD) != "0" {
				_ = appendFileLine(scalarLog, "oretest: expected SIMD_ENABLED=0 in scalar run (OREN_NO_SIMD=1)")
				rc = 1
				break
			}

			if shouldValidateSIMD() {
				simdLog := filepath.Join("build", "logs", "native_"+name+"_simd.log")
				_ = os.Remove(simdLog)
				simdCmd := fmt.Sprintf("%s OREN_ENABLE_SIMD=1 ./%s", envPrefix, out)
				rc = runWithTimeout(timeoutBin, runTimeout, simdCmd, simdLog)
				runLog = simdLog
				if rc != 0 {
					break
				}
				tDot, okD2 := extractValueFromLog(simdLog, "DOT_BITS=")
				tSIMD, okS2 := extractValueFromLog(simdLog, "SIMD_ENABLED=")
				if !okD2 || !okS2 {
					_ = appendFileLine(simdLog, "oretest: missing DOT_BITS=/SIMD_ENABLED= output in SIMD run")
					rc = 1
					break
				}
				if strings.TrimSpace(tSIMD) != "1" {
					_ = appendFileLine(simdLog, "oretest: expected SIMD_ENABLED=1 in SIMD run (OREN_ENABLE_SIMD=1)")
					rc = 1
					break
				}
				if strings.TrimSpace(tDot) != strings.TrimSpace(sDot) {
					_ = appendFileLine(simdLog, "oretest: native SIMD f32 dot mismatch")
					_ = appendFileLine(simdLog, "scalar DOT_BITS "+strings.TrimSpace(sDot))
					_ = appendFileLine(simdLog, "simd   DOT_BITS "+strings.TrimSpace(tDot))
					rc = 1
					break
				}
			}
		default:
			rc = runWithTimeout(timeoutBin, runTimeout, fmt.Sprintf("%s ./%s", envPrefix, out), log)
			runLog = log
		}

		_ = os.Remove(out)
		_ = os.RemoveAll(workdir)

		if name == "test_debug_panic" {
			// Expected-failure regression: panic output must be readable and include a stack trace.
			// We accept any non-zero exit except external timeout.
			if rc == 0 || rc == 124 {
				return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: runLog}
			}
			outb, err := os.ReadFile(runLog)
			if err != nil {
				return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: runLog}
			}
			s := string(outb)
			if !strings.Contains(s, "Traceback") || !strings.Contains(s, "crash_me") {
				return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: runLog}
			}
		} else {
			if rc != 0 {
				return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: false, log: runLog}
			}
		}
		return testResult{tc: testCase{kind: "native", name: name, path: path}, ok: true, log: runLog}
	})
	for _, r := range results {
		if r.ok {
			res.pass++
		} else {
			res.ok = false
			res.failed = append(res.failed, r)
		}
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
	envPrefix := sanitizedAllocatorEnvPrefix()
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
		runEnvPrefix := envPrefix
		if name == "test_integration_suite" {
			// Keep C-backend SIMD exercised in the fast suite.
			// Semantics must remain identical with/without SIMD.
			runEnvPrefix = runEnvPrefix + " OREN_ENABLE_SIMD=1"
		}
		if name == "test_buffer_payload_limit" {
			// Deterministic allocation failure without relying on host memory pressure.
			runEnvPrefix = "env OREN_RAW_MMAP_THRESHOLD= OREN_BUF_ALIGN= OREN_BUF_FORCE_MMAP= OREN_BUF_PAYLOAD_LIMIT_BYTES=1024"
		}
		if rc := runWithTimeout(timeoutBin, runTimeout, fmt.Sprintf("%s %q", runEnvPrefix, out), log); rc != 0 {
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
		case "test_map_iter_deterministic":
			// Map iteration order should be deterministic even under capsule-like configs.
			// Run in deterministic mode and deny-by-default (no host effects).
			cmd := fmt.Sprintf("env AVM_DETERMINISTIC=1 AVM_TIME_START_NS=0 AVM_TIME_STEP_NS=1 ./avm --deny-by-default --allow-domains \"0,6\" %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmd, log); rc != 0 {
				runOK = false
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
		case "test_snapshot_resume", "test_snapshot_resume_record_log":
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
		case "test_snapshot_tasks_resume":
			snap := filepath.Join("build", name+".avms")
			_ = os.Remove(snap)
			cmd := fmt.Sprintf("./avm --step-limit 200 --print-pause-json --snapshot-out %q %q", snap, obc)
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
		case "test_snapshot_vfs_resume":
			snap := filepath.Join("build", name+".avms")
			_ = os.Remove(snap)
			// First run: force VirtualFS; snapshot must capture backend kind and contents.
			cmd := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,1,6\" --fs-backend vfs --step-limit 2000 --print-pause-json --snapshot-out %q %q", snap, obc)
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
		case "test_state_hash_includes_vfs":
			_ = os.Remove("build/avm_state_hash_vfs.txt")
			cmdVfs := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,1,6\" --fs-backend vfs --print-state-hash %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmdVfs, log); rc != 0 {
				runOK = false
				break
			}
			h1, ok1 := extractHashFromLog(log, "STATE_HASH")
			if !ok1 {
				_ = appendFileLine(log, "oretest: missing STATE_HASH in vfs run output")
				runOK = false
				break
			}

			log2 := filepath.Join("build", "logs", "avm_"+name+"_host.log")
			_ = os.Remove(log2)
			cmdHost := fmt.Sprintf("./avm --deny-by-default --allow-domains \"0,1,6\" --fs-allow-prefixes \"build/\" --fs-backend host --print-state-hash %q", obc)
			if rc := runWithTimeout(timeoutBin, runTimeout, cmdHost, log2); rc != 0 {
				runOK = false
				log = log2
				break
			}
			h2, ok2 := extractHashFromLog(log2, "STATE_HASH")
			if !ok2 {
				_ = appendFileLine(log2, "oretest: missing STATE_HASH in host run output")
				runOK = false
				log = log2
				break
			}
			if h1 == h2 {
				_ = appendFileLine(log2, "oretest: expected STATE_HASH to differ between vfs and host backends")
				runOK = false
				log = log2
			}
			_ = os.Remove("build/avm_state_hash_vfs.txt")
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
		case "test_map_iter_deterministic":
			// Map iteration order should be deterministic even under capsule-like configs.
			// Run in deterministic mode and deny-by-default (no host effects).
			cmd := fmt.Sprintf("env AVM_DETERMINISTIC=1 AVM_TIME_START_NS=0 AVM_TIME_STEP_NS=1 %s --deny-by-default --allow-domains \"0,6\" %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmd), log); rc != 0 {
				runOK = false
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
		case "test_snapshot_resume", "test_snapshot_resume_record_log":
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
		case "test_snapshot_tasks_resume":
			snap := filepath.Join(workBuild, name+".avms")
			_ = os.Remove(snap)
			cmd := fmt.Sprintf("%s --step-limit 200 --print-pause-json --snapshot-out %q %q", avmPath, filepath.Join("build", name+".avms"), filepath.Join("build", name+".obc"))
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
		case "test_snapshot_vfs_resume":
			snap := filepath.Join(workBuild, name+".avms")
			_ = os.Remove(snap)
			cmd := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,1,6\" --fs-backend vfs --step-limit 2000 --print-pause-json --snapshot-out %q %q", avmPath, filepath.Join("build", name+".avms"), filepath.Join("build", name+".obc"))
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
		case "test_state_hash_includes_vfs":
			_ = os.Remove(filepath.Join(workBuild, "avm_state_hash_vfs.txt"))
			cmdVfs := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,1,6\" --fs-backend vfs --print-state-hash %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmdVfs), log); rc != 0 {
				runOK = false
				break
			}
			h1, ok1 := extractHashFromLog(log, "STATE_HASH")
			if !ok1 {
				_ = appendFileLine(log, "oretest: missing STATE_HASH in vfs run output")
				runOK = false
				break
			}

			log2 := filepath.Join("build", "logs", "avm_"+name+"_host.log")
			_ = os.Remove(log2)
			cmdHost := fmt.Sprintf("%s --deny-by-default --allow-domains \"0,1,6\" --fs-allow-prefixes \"build/\" --fs-backend host --print-state-hash %q", avmPath, filepath.Join("build", name+".obc"))
			if rc := runWithTimeout(timeoutBin, runTimeout, inDir(workdir, cmdHost), log2); rc != 0 {
				runOK = false
				log = log2
				break
			}
			h2, ok2 := extractHashFromLog(log2, "STATE_HASH")
			if !ok2 {
				_ = appendFileLine(log2, "oretest: missing STATE_HASH in host run output")
				runOK = false
				log = log2
				break
			}
			if h1 == h2 {
				_ = appendFileLine(log2, "oretest: expected STATE_HASH to differ between vfs and host backends")
				runOK = false
				log = log2
			}
			_ = os.Remove(filepath.Join(workBuild, "avm_state_hash_vfs.txt"))
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

func expandOrenIncludes(entryPath string) (string, error) {
	// Purpose-built preprocessor for repo-owned Oren sources.
	//
	// Directive form (single-line comment):
	//   // @include "relative/or/absolute/path.oren"
	//
	// This is intentionally *not* Oren's `import` system; it's used for cases where
	// we need literal textual inlining (e.g. the native runtime, which must define
	// symbols in the global namespace).
	var rec func(path string, stack []string) (string, error)
	rec = func(path string, stack []string) (string, error) {
		clean := filepath.Clean(path)
		for _, p := range stack {
			if p == clean {
				return "", fmt.Errorf("oren include cycle detected: %s", clean)
			}
		}
		stack2 := append(append([]string(nil), stack...), clean)

		b, err := os.ReadFile(clean)
		if err != nil {
			return "", err
		}
		src := string(b)
		lines := strings.Split(src, "\n")

		var out strings.Builder
		for i, line := range lines {
			trim := strings.TrimSpace(line)
			if strings.HasPrefix(trim, "// @include") {
				i1 := strings.IndexByte(trim, '"')
				i2 := strings.LastIndexByte(trim, '"')
				if i1 >= 0 && i2 > i1 {
					inc := trim[i1+1 : i2]
					incPath := inc
					if !filepath.IsAbs(incPath) {
						incPath = filepath.Join(filepath.Dir(clean), incPath)
					}
					incPath = filepath.Clean(incPath)
					expanded, eerr := rec(incPath, stack2)
					if eerr != nil {
						return "", eerr
					}
					out.WriteString(expanded)
					if !strings.HasSuffix(expanded, "\n") {
						out.WriteString("\n")
					}
				}
				continue
			}

			// Preserve original text (including empty final line).
			out.WriteString(line)
			if i != len(lines)-1 || strings.HasSuffix(src, "\n") {
				out.WriteString("\n")
			}
		}
		return out.String(), nil
	}

	return rec(entryPath, nil)
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

func extractValueFromLog(logPath string, prefix string) (string, bool) {
	b, err := os.ReadFile(logPath)
	if err != nil {
		return "", false
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix)), true
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

	compilerExpanded, err := expandOrenIncludes(compilerPath)
	if err != nil {
		return fmt.Errorf("expand includes %s: %w", compilerPath, err)
	}
	rt, err := expandOrenIncludes(runtimePath)
	if err != nil {
		return fmt.Errorf("expand includes %s: %w", runtimePath, err)
	}

	// Collect all defined capsule pre-hooks in the native runtime.
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

	src := compilerExpanded
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

	// When a large compiler module is split via `// @include`, we scan only the
	// top-level entry file and skip the included parts directory. The entry file
	// is expanded before scanning so policy checks still see the real code.
	skipDirs := map[string]bool{
		filepath.Join("lib", "compiler", "arm64_native_expr"):          true,
		filepath.Join("lib", "compiler", "arm64_native_expr_syscalls"): true,
	}

	var offenders []string

	err := filepath.WalkDir(filepath.Join("lib", "compiler"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if skipDirs[path] {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}

		src, rerr := expandOrenIncludes(path)
		if rerr != nil {
			return rerr
		}
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

func auditStdlibModernStyle() error {
	// Purpose: keep `lib/std` in sync with rolling language idioms.
	//
	// This is intentionally a cheap static scan (no compilation), intended to
	// prevent regressions during rolling refactors.
	type rule struct {
		name        string
		pattern     string
		allowInFile func(path string) bool
		allowInLine func(trimmedLine string) bool
	}
	rules := []rule{
		{
			name:    "no string_concat in stdlib (prefer `+`)",
			pattern: "string_concat(",
			allowInLine: func(trimmedLine string) bool {
				// Allow mention in comments/docstrings, but not in code.
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no direct oren_list_* in stdlib (prefer container methods / std:list)",
			pattern: "oren_list_",
			allowInFile: func(path string) bool {
				// std/list.oren is the single allowlisted wrapper module.
				return filepath.Clean(path) == filepath.Join("lib", "std", "list.oren")
			},
			allowInLine: func(trimmedLine string) bool {
				// Allow mention in comments/docstrings, but not in code.
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no legacy @forin internal identifiers",
			pattern: "@forin_",
		},
		{
			name:    "no legacy @forinr internal identifiers",
			pattern: "@forinr_",
		},
	}

	var offenders []string
	err := filepath.WalkDir(filepath.Join("lib", "std"), func(path string, d os.DirEntry, err error) error {
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
		lines := strings.Split(src, "\n")
		for i, line := range lines {
			trim := strings.TrimSpace(line)
			for _, r := range rules {
				if !strings.Contains(line, r.pattern) {
					continue
				}
				if r.allowInFile != nil && r.allowInFile(path) {
					continue
				}
				if r.allowInLine != nil && r.allowInLine(trim) {
					continue
				}
				offenders = append(offenders, fmt.Sprintf("%s:%d: %s (found %q)", path, i+1, r.name, r.pattern))
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("stdlib style violations:\n%s", strings.Join(offenders, "\n"))
	}

	return nil
}

func auditRuntimeNativeModernStyle() error {
	// Purpose: keep `lib/runtime_native` in sync with rolling language idioms for higher-level helpers.
	//
	// The runtime can contain low-level primitives, but we still want to avoid reintroducing
	// legacy patterns in user-facing helpers (notably `string_concat` call-chains).
	allowStringConcatIn := map[string]bool{
		filepath.Join("lib", "runtime_native", "160_iteration.oren"):      true, // defines `string_concat`
		filepath.Join("lib", "runtime_native", "120_first_class_fn.oren"): true, // operator plumbing may rely on it
	}

	var offenders []string
	err := filepath.WalkDir(filepath.Join("lib", "runtime_native"), func(path string, d os.DirEntry, err error) error {
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
		lines := strings.Split(src, "\n")
		for i, line := range lines {
			if !strings.Contains(line, "string_concat(") {
				continue
			}
			trim := strings.TrimSpace(line)
			if strings.HasPrefix(trim, "//") {
				continue
			}
			if allowStringConcatIn[path] {
				continue
			}
			offenders = append(offenders, fmt.Sprintf("%s:%d: no string_concat callsites in runtime_native (prefer `+`) (found %q)", path, i+1, "string_concat("))
		}
		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("runtime_native style violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditArm64AdrFixupSlots() error {
	// Purpose: protect the rolling migration from ADR (±1MB) to ADRP+ADD (±4GB pages)
	// for native backend fixups.
	//
	// The native backend emits placeholder instruction words at each `adr_*` fixup site.
	// Once we patch those fixups as a 2-instruction sequence, any new site that only
	// reserves 1 slot will cause silent code corruption (pos+4 overwrites the next insn).
	//
	// Keep this audit intentionally small and specific to the compiler lowering modules.
	type fixupKind struct {
		name    string
		pattern string
	}
	kinds := []fixupKind{
		{name: "adr_data", pattern: "\"type\": \"adr_data\""},
		{name: "adr_code", pattern: "\"type\": \"adr_code\""},
	}

	var paths []string
	paths = append(paths, filepath.Join("lib", "compiler", "arm64_native_stmt.oren"))

	exprDir := filepath.Join("lib", "compiler", "arm64_native_expr")
	if err := filepath.WalkDir(exprDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}
		paths = append(paths, path)
		return nil
	}); err != nil {
		return err
	}

	var offenders []string
	for _, path := range paths {
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		for i := range lines {
			line := lines[i]
			for _, k := range kinds {
				if !strings.Contains(line, k.pattern) {
					continue
				}

				// Heuristic: find the nearest preceding `var adr_pos` (or similar) and count
				// reserved u32 slots up to the fixup push.
				start := i - 20
				if start < 0 {
					start = 0
				}
				for j := i; j >= start; j-- {
					if strings.Contains(lines[j], "var adr_pos") {
						start = j
						break
					}
				}

				slotCount := 0
				for j := start; j <= i; j++ {
					if strings.Contains(lines[j], "push_u32_le(ctx[\"code\"], 0)") {
						slotCount++
					}
				}
				if slotCount < 2 {
					offenders = append(offenders, fmt.Sprintf("%s:%d: %s fixup must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, k.name, slotCount))
				}
			}
		}
	}

	// Debug hook placeholder is emitted in the entry stub (not near fixup pushes),
	// but it is patched via `adr_data` later (Mach-O/ELF emitters). Ensure it also reserves 2 slots.
	if err := func() error {
		path := filepath.Join("lib", "compiler", "arm64_native_program.oren")
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		for i := range lines {
			if !strings.Contains(lines[i], "ctx[\"debug_fixup_pos\"]") {
				continue
			}
			start := i - 8
			if start < 0 {
				start = 0
			}
			slotCount := 0
			for j := start; j <= i; j++ {
				if strings.Contains(lines[j], "push_u32_le(ctx[\"code\"], 0)") {
					slotCount++
				}
			}
			if slotCount < 2 {
				offenders = append(offenders, fmt.Sprintf("%s:%d: debug_fixup_pos must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, slotCount))
			}
		}
		return nil
	}(); err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("arm64 fixup slot violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditArm64MachoGotStubSlots() error {
	// Purpose: Mach-O imports use a small stub sequence that gets patched by `got_load` fixups.
	// The stub placeholder must reserve 2 u32 words (ADRP + ADD). If it reserves 1, the patcher
	// will overwrite the next instruction (LDR/BR) and corrupt the stub silently.
	path := filepath.Join("lib", "compiler", "arm64_macho.oren")
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(b), "\n")

	var offenders []string
	for i := range lines {
		if !strings.Contains(lines[i], "\"type\": \"got_load\"") {
			continue
		}
		start := i - 30
		if start < 0 {
			start = 0
		}
		slotCount := 0
		for j := start; j <= i; j++ {
			if strings.Contains(lines[j], "push_u32_le(code, 0)") {
				slotCount++
			}
		}
		if slotCount < 2 {
			offenders = append(offenders, fmt.Sprintf("%s:%d: got_load stub must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, slotCount))
		}
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		return fmt.Errorf("arm64 Mach-O got stub violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditRepoModernStyle() error {
	// Purpose: keep the repo moving toward a consistent modern surface syntax.
	//
	// This is intentionally a simple textual scan, enforced via oretest, to prevent
	// reintroducing deprecated patterns during rolling refactors.
	//
	// Exceptions:
	// - `string_concat` exists as a low-level helper for the native runtime and for operator plumbing.
	allowStringConcatIn := map[string]bool{
		filepath.Join("lib", "runtime_native", "160_iteration.oren"):      true, // defines `string_concat`
		filepath.Join("lib", "runtime_native", "120_first_class_fn.oren"): true, // operator plumbing may rely on it
	}

	type rule struct {
		name        string
		pattern     string
		allowInFile func(path string) bool
		allowInLine func(trimmedLine string) bool
	}
	rules := []rule{
		{
			name:    "no string_concat callsites (prefer `+`)",
			pattern: "string_concat(",
			allowInFile: func(path string) bool {
				return allowStringConcatIn[path]
			},
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			// Rolling syntax modernization: prefer `if cond { ... }` over legacy `if (cond) { ... }`.
			//
			// Note: this scan is intentionally heuristic. We only flag when the trimmed line begins
			// with the legacy construct, so string literals like `emit("if (x) {")` don't trip it.
			name:    "no legacy if (...) condition parentheses",
			pattern: "if (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "if (")
			},
		},
		{
			name:    "no legacy if(...) condition parentheses",
			pattern: "if(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "if(")
			},
		},
		{
			name:    "no legacy else if (...) condition parentheses",
			pattern: "else if (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "else if (") && !strings.HasPrefix(trimmedLine, "} else if (")
			},
		},
		{
			name:    "no legacy else if(...) condition parentheses",
			pattern: "else if(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "else if(") && !strings.HasPrefix(trimmedLine, "} else if(")
			},
		},
		{
			// Rolling syntax modernization: prefer `while cond { ... }` over legacy `while (cond) { ... }`.
			name:    "no legacy while (...) condition parentheses",
			pattern: "while (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "while (")
			},
		},
		{
			name:    "no legacy while(...) condition parentheses",
			pattern: "while(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "while(")
			},
		},
		{
			// Rolling syntax modernization: prefer `for x in xs { ... }` or `for init; cond; post { ... }`
			// over legacy `for (<header>) { ... }`.
			name:    "no legacy for (...) header parentheses",
			pattern: "for (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "for (")
			},
		},
		{
			name:    "no legacy for(...) header parentheses",
			pattern: "for(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "for(")
			},
		},
		{
			// Rolling syntax modernization: prefer `switch expr { ... }` over legacy `switch (expr) { ... }`.
			name:    "no legacy switch (...) expression parentheses",
			pattern: "switch (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "switch (")
			},
		},
		{
			name:    "no legacy switch(...) expression parentheses",
			pattern: "switch(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "switch(")
			},
		},
		{
			// Rolling syntax modernization: prefer `match expr { ... }` over legacy `match (expr) { ... }`.
			name:    "no legacy match (...) expression parentheses",
			pattern: "match (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "match (")
			},
		},
		{
			name:    "no legacy match(...) expression parentheses",
			pattern: "match(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "match(")
			},
		},
		{
			name:    "no legacy @forin internal identifiers",
			pattern: "@forin_",
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no legacy @forinr internal identifiers",
			pattern: "@forinr_",
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
	}

	var offenders []string
	// Also enforce source size limits for C runtime include chunks. These chunks exist
	// specifically to avoid context overflow; keep them under the same 2000-line guardrail.
	{
		type sizeRule struct {
			root      string
			ext       string
			maxLines  int
			desc      string
			allowFile func(path string) bool
		}
		sizeRules := []sizeRule{
			{
				root:     filepath.Join("lib", "runtime"),
				ext:      ".inc",
				maxLines: 2000,
				desc:     "C runtime include chunk too large",
			},
			{
				root:     filepath.Join("lib", "runtime_buf"),
				ext:      ".inc",
				maxLines: 2000,
				desc:     "C runtime_buf include chunk too large",
			},
		}
		for _, sr := range sizeRules {
			if _, err := os.Stat(sr.root); err != nil {
				continue
			}
			err := filepath.WalkDir(sr.root, func(path string, d os.DirEntry, err error) error {
				if err != nil {
					return err
				}
				if d.IsDir() {
					return nil
				}
				if !strings.HasSuffix(path, sr.ext) {
					return nil
				}
				if sr.allowFile != nil && sr.allowFile(path) {
					return nil
				}
				b, rerr := os.ReadFile(path)
				if rerr != nil {
					return rerr
				}
				lines := 0
				for _, ch := range b {
					if ch == '\n' {
						lines++
					}
				}
				// Count last line if non-empty.
				if len(b) > 0 && b[len(b)-1] != '\n' {
					lines++
				}
				if lines > sr.maxLines {
					offenders = append(offenders, fmt.Sprintf("%s:1: %s (%d lines > %d)", path, sr.desc, lines, sr.maxLines))
				}
				return nil
			})
			if err != nil {
				return err
			}
		}
	}

	roots := []string{filepath.Join("lib"), filepath.Join("tests"), filepath.Join("examples")}
	for _, root := range roots {
		if _, err := os.Stat(root); err != nil {
			continue
		}
		err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
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
			// Size guard: keep `.oren` sources reviewable without context overflow.
			// This is enforced repo-wide in rolling mode: split large files into modules.
			//
			// Note: keep this simple and deterministic; count '\n' as line separators.
			if len(b) > 0 {
				lines := 1
				for _, ch := range b {
					if ch == '\n' {
						lines++
					}
				}
				if lines > 2000 {
					offenders = append(offenders, fmt.Sprintf("%s:1: file too large (%d lines > 2000); split into modules", path, lines))
				}
			}
			lines := strings.Split(string(b), "\n")
			for i, line := range lines {
				trim := strings.TrimSpace(line)
				for _, r := range rules {
					if !strings.Contains(line, r.pattern) {
						continue
					}
					if r.allowInFile != nil && r.allowInFile(path) {
						continue
					}
					if r.allowInLine != nil && r.allowInLine(trim) {
						continue
					}
					offenders = append(offenders, fmt.Sprintf("%s:%d: %s (found %q)", path, i+1, r.name, r.pattern))
				}
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 50 {
			offenders = append(offenders[:50], fmt.Sprintf("... (%d more)", len(offenders)-50))
		}
		return fmt.Errorf("repo style violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditIncludeChunkCoherence() error {
	// Purpose: prevent `// @include`-based Oren sources from splitting mid-block,
	// which makes individual include chunks unreadable and prone to context overflow.
	//
	// This is a cheap static scan: it does not parse Oren fully; it just checks per-file
	// brace balance while ignoring braces inside string literals and line comments.
	type fileStat struct {
		path string
		bal  int
		min  int
	}
	type rootResult struct {
		root  string
		stats []fileStat
		miss  []string
	}

	// Find roots: any `.oren` file under `lib/` containing a `// @include "..."` directive line.
	var roots []string
	err := filepath.WalkDir(filepath.Join("lib"), func(path string, d os.DirEntry, err error) error {
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
		// Be strict: only treat it as a root if there is an actual directive at the
		// beginning of a (trimmed) line. This avoids false positives from comments like:
		//   // NOTE: uses includes (`// @include "..."`)
		lines := strings.Split(string(b), "\n")
		for _, line := range lines {
			if strings.HasPrefix(strings.TrimSpace(line), "// @include \"") {
				roots = append(roots, path)
				break
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	sort.Strings(roots)
	if len(roots) == 0 {
		return nil
	}

	var offenders []string
	var allMissing []string

	for _, root := range roots {
		visited := map[string]bool{}
		// Traverse include tree (relative to the including file's directory).
		var stack []string
		stack = append(stack, root)
		var missing []string
		var stats []fileStat

		for len(stack) > 0 {
			cur := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			cur = filepath.Clean(cur)
			if visited[cur] {
				continue
			}
			visited[cur] = true

			b, rerr := os.ReadFile(cur)
			if rerr != nil {
				// If we can't read a root, hard fail; otherwise record missing include.
				missing = append(missing, fmt.Sprintf("%s (read error: %v)", cur, rerr))
				continue
			}

			bal, min := braceBalanceOren(b)
			stats = append(stats, fileStat{path: cur, bal: bal, min: min})
			if bal != 0 || min < 0 {
				offenders = append(offenders, fmt.Sprintf("%s: unbalanced braces (bal=%d, min=%d) under root %s", cur, bal, min, root))
			}
			if first := firstSignificantOrenLine(b); first != "" {
				if !isAllowedIncludeChunkStart(first) {
					offenders = append(offenders, fmt.Sprintf("%s: suspicious include chunk start %q under root %s (likely mid-block split)", cur, first, root))
				}
			}

			// Parse include directives for recursion.
			dir := filepath.Dir(cur)
			lines := strings.Split(string(b), "\n")
			for _, line := range lines {
				trim := strings.TrimSpace(line)
				if !strings.HasPrefix(trim, "// @include \"") {
					continue
				}
				rest := strings.TrimPrefix(trim, "// @include \"")
				q := strings.IndexByte(rest, '"')
				if q < 0 {
					continue
				}
				rel := rest[:q]
				next := filepath.Clean(filepath.Join(dir, rel))
				if _, err := os.Stat(next); err != nil {
					missing = append(missing, fmt.Sprintf("%s includes missing %s", cur, next))
					continue
				}
				stack = append(stack, next)
			}
		}

		// If includes are missing, report them (but keep output bounded).
		if len(missing) > 0 {
			sort.Strings(missing)
			allMissing = append(allMissing, missing...)
		}
	}

	if len(allMissing) > 0 {
		sort.Strings(allMissing)
		if len(allMissing) > 30 {
			allMissing = append(allMissing[:30], fmt.Sprintf("... (%d more)", len(allMissing)-30))
		}
		return fmt.Errorf("include chunk missing files:\n%s", strings.Join(allMissing, "\n"))
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("include chunk coherence violations:\n%s", strings.Join(offenders, "\n"))
	}

	return nil
}

func firstSignificantOrenLine(src []byte) string {
	// Returns the first non-empty, non-`//` comment line (trimmed).
	// We intentionally ignore block comments because Oren doesn't currently standardize them.
	lines := strings.Split(string(src), "\n")
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if trim == "" {
			continue
		}
		if strings.HasPrefix(trim, "//") {
			continue
		}
		return trim
	}
	return ""
}

func isAllowedIncludeChunkStart(trimmedLine string) bool {
	// Heuristic: include chunks should begin at a top-level declaration boundary.
	// This catches mid-function splits that could still be brace-balanced.
	//
	// Allow:
	// - attributes (`@...`)
	// - module imports and global vars
	// - top-level declarations (fn/struct/class/trait/impl/enum/ffi/test)
	//
	// Disallow:
	// - statements like `if ...`, `while ...`, `return ...`, `x = ...`
	// - closers like `}` or `else` which indicate we split at an interior boundary
	allowedPrefixes := []string{
		"@",
		"import ",
		"var ",
		"fn ",
		"struct ",
		"class ",
		"trait ",
		"impl ",
		"enum ",
		"ffi ",
		"test ",
	}
	for _, p := range allowedPrefixes {
		if strings.HasPrefix(trimmedLine, p) {
			return true
		}
	}
	return false
}

func braceBalanceOren(src []byte) (bal int, min int) {
	// Heuristic scanner:
	// - ignores braces inside double-quoted string literals
	// - ignores braces after `//` comment starts (when not in a string)
	inString := false
	escape := false
	min = 0
	for i := 0; i < len(src); i++ {
		ch := src[i]

		if inString {
			if escape {
				escape = false
				continue
			}
			if ch == '\\' {
				escape = true
				continue
			}
			if ch == '"' {
				inString = false
			}
			continue
		}

		// Line comment
		if ch == '/' && i+1 < len(src) && src[i+1] == '/' {
			// Skip to end of line (or EOF).
			for i < len(src) && src[i] != '\n' {
				i++
			}
			continue
		}

		if ch == '"' {
			inString = true
			escape = false
			continue
		}

		if ch == '{' {
			bal++
			continue
		}
		if ch == '}' {
			bal--
			if bal < min {
				min = bal
			}
			continue
		}
	}
	return bal, min
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
