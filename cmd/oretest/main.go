package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
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
	dur time.Duration
}

type syscallBlock struct {
	sysNames []string
	text     string
}

func main() {
	startWall := time.Now()
	defaultTarget := "macos"
	switch runtime.GOOS {
	case "linux":
		defaultTarget = "linux"
	case "darwin":
		defaultTarget = "macos"
	case "windows":
		defaultTarget = "windows"
	}
	var (
		target         = flag.String("target", defaultTarget, "legacy native backend OS target: macos|linux (prefer --platform <arch>-<os>)")
		platform       = flag.String("platform", os.Getenv("OREN_PLATFORM"), "platform selector (shorthand for host/remote runners): macos|linux|arm64-macos|arm64-linux|x64-windows|x64-linux (env OREN_PLATFORM)")
		matrix         = flag.String("matrix", os.Getenv("OREN_TEST_MATRIX"), "run a multi-platform matrix (host orchestrator): tier1|tier1-obc (env OREN_TEST_MATRIX)")
		noGC           = flag.Bool("no-gc", os.Getenv("OREN_NO_GC") != "", "disable GC scanning (also via env OREN_NO_GC=1)")
		jobs           = flag.Int("jobs", envInt("OREN_TEST_JOBS", runtime.NumCPU()), "parallel jobs for module+avm tests (env OREN_TEST_JOBS)")
		fixtureJobs    = flag.Int("fixture-jobs", envInt("OREN_TEST_FIXTURE_JOBS", 0), "parallel jobs for fixtures (env OREN_TEST_FIXTURE_JOBS); default min(--jobs,8)")
		nativeJobs     = flag.Int("native-jobs", envInt("OREN_TEST_NATIVE_JOBS", 0), "parallel jobs for native tests (env OREN_TEST_NATIVE_JOBS); default min(--jobs,8)")
		full           = flag.Bool("full", envBool("OREN_TEST_FULL", false), "run the full curated suite (env OREN_TEST_FULL=1)")
		verbose        = flag.Bool("verbose", envBool("OREN_TEST_VERBOSE", false), "print per-test progress (env OREN_TEST_VERBOSE=1)")
		profile        = flag.Bool("profile", envBool("OREN_TEST_PROFILE", false), "print slowest tests summary (env OREN_TEST_PROFILE=1)")
		selfhost       = flag.Bool("selfhost", envBool("OREN_TEST_SELFHOST", false), "run self-hosting stability gate (env OREN_TEST_SELFHOST=1); implied by --full")
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
		// Remote x64 fixtures (Win11+WSL2 over proxy+scp) are sensitive to concurrent
		// ssh/scp sessions and can fail spuriously (truncated uploads, remote dest open
		// failures). Keep the default remote-run behavior serialized unless the caller
		// explicitly opts into parallelism via --fixture-jobs / OREN_TEST_FIXTURE_JOBS.
		if os.Getenv("OREN_REMOTE_RUN") == "1" {
			fixtureJobsEff = 1
		}
		// Fixtures include some CPU-heavy cross-compilation (Tier‑1 x64 smoke builds),
		// and running too many concurrently can cause build timeouts under contention.
		// Keep the default ceiling conservative; callers can still override via
		// --fixture-jobs / OREN_TEST_FIXTURE_JOBS for beefier CI hosts.
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
		// Native tests do more compilation and produce binaries, so keep the default
		// ceiling slightly conservative but still higher than 4 for modern CPUs.
		if nativeJobsEff > 8 {
			nativeJobsEff = 8
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

	// Matrix mode is a host-side orchestrator. It is intended to be run from the dev host
	// (arm64 macOS) and will delegate to Docker and/or remote runners as needed.
	if strings.TrimSpace(*matrix) != "" {
		matrixKey := strings.ToLower(strings.TrimSpace(*matrix))
		includeOBC := false
		switch matrixKey {
		case "tier1":
			// ok
		case "tier1-obc":
			includeOBC = true
		default:
			fmt.Fprintf(os.Stderr, "ERROR: unknown --matrix %q (supported: tier1, tier1-obc)\n", *matrix)
			os.Exit(2)
		}
		_ = os.MkdirAll("build/logs", 0o755)
		_ = os.MkdirAll("build/tmp", 0o755)

		logPath := fmt.Sprintf("build/logs/oretest_matrix_%s.log", matrixKey)
		rcPath := fmt.Sprintf("build/logs/oretest_matrix_%s.rc", matrixKey)
		logFile, err := os.Create(logPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ERROR: failed to create matrix log %s: %v\n", logPath, err)
			os.Exit(2)
		}
		defer logFile.Close()

		out := io.MultiWriter(os.Stderr, logFile)
		matrixStart := time.Now()
		fmt.Fprintf(out, "[matrix] start name=%s at=%s host=%s/%s\n", matrixKey, matrixStart.Format(time.RFC3339), runtime.GOOS, runtime.GOARCH)
		rc := runTier1Matrix(timeoutBin, includeOBC, out)
		dur := time.Since(matrixStart)
		fmt.Fprintf(out, "[matrix] done name=%s rc=%d dur=%s\n", matrixKey, rc, dur)
		_ = os.WriteFile(rcPath, []byte(fmt.Sprintf("%d\n", rc)), 0o644)
		os.Exit(rc)
	}

	// Platform mode maps <arch>-<os> onto the Tier-1 suite structure:
	// - host-native builds always pass `--platform <host-arch>-<target-os>` to `./oren` (avoids default OS/arch drift)
	// - x64 execution runs through the remote Win11+WSL2 gate (OREN_REMOTE_RUN=1)
	// - linux/arm64 execution from macOS runs through the persistent Docker runner
	nativeTarget := *target
	if strings.TrimSpace(*platform) != "" {
		didExit, exitCode, newTarget := applyPlatformSpec(timeoutBin, *platform, nativeTarget, os.Args[1:])
		if didExit {
			os.Exit(exitCode)
		}
		nativeTarget = newTarget
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
	// Optional tools: only required when the corresponding fixtures are enabled.
	includeSigning := *full || os.Getenv("OREN_TEST_SIGNING") == "1"
	includeOredoc := *full || os.Getenv("OREN_TEST_OREDOC") == "1"
	if includeSigning {
		if _, err := os.Stat("./orensign"); err != nil {
			fmt.Fprintln(os.Stderr, "ERROR: ./orensign not found; run `make orensign` (or disable signing fixtures).")
			os.Exit(2)
		}
	}
	if includeOredoc {
		if _, err := os.Stat("./oredoc"); err != nil {
			fmt.Fprintln(os.Stderr, "ERROR: ./oredoc not found; run `make oredoc` (or disable oredoc fixtures).")
			os.Exit(2)
		}
	}
	if err := stdlibModernizationAudit(); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(2)
	}
	orenPath, _ := filepath.Abs("./oren")
	avmPath, _ := filepath.Abs("./avm")

	_ = os.MkdirAll("build/logs", 0o755)
	_ = os.MkdirAll("build/tmp", 0o755)

	// Timeouts: iteration-friendly defaults.
	//
	// Constraint (production iteration): keep the curated runner bounded and predictable.
	// If this is flaky on slow hosts, the fix is to reduce test count and/or speed up the compiler, not to inflate timeouts indefinitely.
	buildTimeout := 3 * time.Minute
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
			na := hostNativeArch()
			if nt == "" || na == "" {
				fmt.Fprintln(os.Stderr, "WARN: native self-host gate skipped: unsupported host platform:", runtime.GOOS, runtime.GOARCH)
			} else {
				if err := runNativeSelfHostingGate(timeoutBin, gcArg, buildTimeout, nt, na); err != nil {
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
		"tests/native/test_debug_panic.oren",
	}
	// SIMD determinism is a valuable guard but expensive; keep opt-in unless --full.
	// Enable via: OREN_TEST_SIMD=1 make test
	if *full || envBool("OREN_TEST_SIMD", false) {
		nativeTests = append(nativeTests, "tests/native/test_simd_suite.oren")
	}
	if *full {
		// Pure-functional encoder goldens; no syscalls; deterministic correctness guard.
		nativeTests = append(nativeTests, "tests/native/test_arm64_encoding.oren")
	}
	moduleTestsFast := []string{
		// Keep the default suite integration-first and under 1 minute wall time.
		"tests/modules/test_integration_suite.oren",
		// Critical no-hangs guard (spawn/join cancellation).
		"tests/modules/test_spawn_join_timeout.oren",
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
		"tests/modules/test_trait_impl_typed_buffer_receiver.oren",
		"tests/modules/test_type_name_resolve_slice_prefix_alias.oren",
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
		"tests/avm/test_smoke_suite.oren",
		// Determinism guard that doesn't depend on host wall clock.
		"tests/avm/test_time_rng_deterministic.oren",
	}
	avmTestsFull := []string{
		"tests/avm/test_smoke_suite.oren",
		"tests/avm/test_crypto_sha256_vectors.oren",
		"tests/avm/test_u8_buf_views.oren",
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

	// Fast-suite knobs: keep the default run under ~3 minutes wall time even on cold caches.
	// Enable additional suites only when needed.
	if !*full && !envBool("OREN_TEST_C", false) {
		moduleTestsFast = nil
	}
	if !*full && !envBool("OREN_TEST_AVM", false) {
		avmTestsFast = nil
	}

	moduleTests := moduleTestsFast
	avmTests := avmTestsFast
	if *full {
		moduleTests = moduleTestsFull
		avmTests = avmTestsFull
	}

	// Fixtures: portable semantics + determinism guards.
	fixtures := buildFixtureCases(nativeTarget, gcArg, *full)

	// Runtime diagnostics fixtures: validate OREN_DIAG headers.
	runtimeFixtures := []runtimeFixtureCase{}
	if *full || envBool("OREN_TEST_RUNTIME_FIXTURES", false) {
		runtimeFixtures = buildRuntimeFixtureCases(nativeTarget, gcArg)
	}

	remoteRun := envBool("OREN_REMOTE_RUN", false)
	remoteRunAll := envBool("OREN_REMOTE_RUN_ALL", false)
	if remoteRun && !remoteRunAll && !*full {
		// Opt-in Tier‑1 x86_64 gate mode: keep the run integration-first and avoid doing
		// a full host-native suite in the same invocation.
		//
		// Use OREN_REMOTE_RUN_ALL=1 if you explicitly want to run the entire local suite too.
		nativeTests = nil
		moduleTests = nil
		avmTests = nil
		runtimeFixtures = nil
	}

	tier1X64 := envBool("OREN_TEST_TIER1_X64", false)
	tier1X64All := envBool("OREN_TEST_TIER1_X64_ALL", false)
	if tier1X64 && !tier1X64All && !*full {
		// Tier‑1 x86_64 build gate mode (Linux ELF + Windows PE):
		// keep the invocation focused on the cross-arch build smoke so it can remain
		// within the default iteration budget.
		//
		// Use OREN_TEST_TIER1_X64_ALL=1 if you explicitly want to run the full local suite too.
		nativeTests = nil
		moduleTests = nil
		avmTests = nil
		runtimeFixtures = nil
	}

	// Run fixtures in parallel (bounded by --fixture-jobs).
	//
	// Fixtures are intended to be small, high-signal correctness guards. Most are
	// independent and safe to parallelize for wall-time reduction.
	type fixtureResult struct {
		name string
		log  string
		ok   bool
		dur  time.Duration
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
			start := time.Now()
			rc := 0
			if fx.run != nil {
				rc = fx.run(timeoutBin, t, fx.log)
			} else {
				rc = runWithTimeout(timeoutBin, t, fx.cmd, fx.log)
			}
			dur := time.Since(start)
			ok := fx.ok(rc)
			// Keep artifacts on failure to make debugging actionable (fixtures often redirect
			// compiler/runtime output into side files under build/).
			if ok {
				for _, c := range fx.cleanup {
					_ = os.RemoveAll(c)
				}
			}
			fixtureResults[i] = fixtureResult{name: fx.name, log: fx.log, ok: ok, dur: dur}
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

	// Run runtime diagnostics fixtures in parallel (bounded by --fixture-jobs).
	//
	// These are build+run pairs that validate deterministic diagnostic headers.
	// They are independent and safe to parallelize as long as output paths are distinct.
	type runtimeFixtureResult struct {
		name string
		log  string
		ok   bool
		msg  string
		dur  time.Duration
	}
	runtimeResults := make([]runtimeFixtureResult, len(runtimeFixtures))
	var wgRuntime sync.WaitGroup
	semRuntime := make(chan struct{}, fixtureJobsEff)
	for i := range runtimeFixtures {
		wgRuntime.Add(1)
		semRuntime <- struct{}{}
		go func(i int) {
			defer wgRuntime.Done()
			defer func() { <-semRuntime }()
			fx := runtimeFixtures[i]
			if *verbose {
				vprintln("runtime fixture: " + fx.name)
			}

			start := time.Now()
			rc := runWithTimeout(timeoutBin, buildTimeout, fx.build, fx.log)
			if rc != 0 {
				runtimeResults[i] = runtimeFixtureResult{name: fx.name, log: fx.log, ok: false, msg: "build failed", dur: time.Since(start)}
				return
			}

			rc2 := runWithTimeout(timeoutBin, runTimeout, fx.run, fx.log)
			outb, _ := os.ReadFile(fx.log)
			if !fx.ok(rc2, string(outb)) {
				runtimeResults[i] = runtimeFixtureResult{name: fx.name, log: fx.log, ok: false, msg: "run failed", dur: time.Since(start)}
				return
			}

			for _, c := range fx.cleanup {
				_ = os.RemoveAll(c)
			}
			runtimeResults[i] = runtimeFixtureResult{name: fx.name, log: fx.log, ok: true, dur: time.Since(start)}
		}(i)
	}
	wgRuntime.Wait()
	for _, rr := range runtimeResults {
		if !rr.ok {
			fmt.Fprintf(os.Stderr, "runtime fixture %s: %s (log: %s)\n", rr.name, rr.msg, rr.log)
			_ = catFile(os.Stderr, rr.log)
			os.Exit(1)
		}
	}

	// Native tests: parallel for wall-time reduction (bounded by --native-jobs).
	nativeRes := suiteResult{ok: true}
	if len(nativeTests) > 0 {
		nativeRes = runNativeTests(timeoutBin, nativeTarget, gcArg, buildTimeout, runTimeout, *verbose, vprintln, nativeJobsEff, nativeTests)
		if !nativeRes.ok {
			os.Exit(1)
		}
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
	if len(moduleTests) > 0 || len(avmTests) > 0 {
		wgSuites.Add(2)
		go func() {
			defer wgSuites.Done()
			if len(moduleTests) == 0 {
				moduleRes = suiteResult{ok: true}
				return
			}
			moduleRes = runModuleTestsParallel(timeoutBin, nativeTarget, gcArg, buildTimeout, runTimeout, *verbose, vprintln, moduleJobs, moduleTests)
		}()
		go func() {
			defer wgSuites.Done()
			if len(avmTests) == 0 {
				avmRes = suiteResult{ok: true}
				return
			}
			avmRes = runAVMTestsParallel(timeoutBin, orenPath, avmPath, gcArg, buildTimeout, runTimeout, *verbose, vprintln, avmJobs, avmTests)
		}()
		wgSuites.Wait()
	}

	if len(nativeTests) > 0 {
		fmt.Printf("%d/%d native tests passed\n", nativeRes.pass, nativeRes.total)
	}
	if len(moduleTests) > 0 {
		fmt.Printf("%d/%d module tests passed\n", moduleRes.pass, moduleRes.total)
	}
	if len(avmTests) > 0 {
		fmt.Printf("%d/%d avm tests passed\n", avmRes.pass, avmRes.total)
	}

	if *profile {
		type profRow struct {
			kind string
			path string
			log  string
			dur  time.Duration
		}
		rows := []profRow{}
		for _, fr := range fixtureResults {
			rows = append(rows, profRow{kind: "fixture", path: fr.name, log: fr.log, dur: fr.dur})
		}
		for _, rr := range runtimeResults {
			rows = append(rows, profRow{kind: "runtime_fixture", path: rr.name, log: rr.log, dur: rr.dur})
		}
		for _, tr := range nativeRes.all {
			rows = append(rows, profRow{kind: tr.tc.kind, path: tr.tc.path, log: tr.log, dur: tr.dur})
		}
		for _, tr := range moduleRes.all {
			rows = append(rows, profRow{kind: tr.tc.kind, path: tr.tc.path, log: tr.log, dur: tr.dur})
		}
		for _, tr := range avmRes.all {
			rows = append(rows, profRow{kind: tr.tc.kind, path: tr.tc.path, log: tr.log, dur: tr.dur})
		}

		// Note: these are per-test elapsed times; suites run in parallel so they do not sum to wall time.
		sort.Slice(rows, func(i, j int) bool { return rows[i].dur > rows[j].dur })
		n := 15
		if len(rows) < n {
			n = len(rows)
		}
		fmt.Println("")
		fmt.Printf("Slowest %d tests (per-test elapsed; parallel suites may overlap):\n", n)
		for i := 0; i < n; i++ {
			r := rows[i]
			fmt.Printf("  %6.2fs  %-14s  %s (log: %s)\n", r.dur.Seconds(), r.kind, r.path, r.log)
		}
	}

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

	// Enforce an iteration budget for the default runner.
	// Disable via: OREN_TEST_BUDGET_SECS=0
	if !*full {
		// Only enforce the wall-time budget for the default fast suite. When callers opt in to
		// additional suites (C backend, AVM, diag fixtures, x64 gates), they are explicitly asking
		// for more work.
		if envBool("OREN_TEST_C", false) || envBool("OREN_TEST_AVM", false) || envBool("OREN_TEST_DIAG", false) ||
			envBool("OREN_TEST_SIMD", false) {
			fmt.Println("All Tests Passed.")
			return
		}
		budget := envInt("OREN_TEST_BUDGET_SECS", 180)
		if budget > 0 && time.Since(startWall) > time.Duration(budget)*time.Second {
			fmt.Fprintf(os.Stderr, "ERROR: oretest exceeded time budget: dur=%s budget=%ds (set OREN_TEST_BUDGET_SECS=0 to disable)\n", time.Since(startWall), budget)
			os.Exit(1)
		}
	}

	fmt.Println("All Tests Passed.")
}
