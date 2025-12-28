package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

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
