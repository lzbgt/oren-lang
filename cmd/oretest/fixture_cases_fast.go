package main

import (
	"fmt"
	"time"
)

func buildFixtureCasesFast(target string, gcArg string) []fixtureCase {
	arch := hostOrenArch()
	plat := platformKey(target, arch)
	fixtures := []fixtureCase{}

	// Compiler diagnostic contract (machine-readable OREN_DIAG headers).
	// Opt-in to keep the default suite within the 3-minute wall-time budget even on cold caches.
	if envBool("OREN_TEST_DIAG", false) && !envBool("OREN_REMOTE_RUN", false) {
		fixtures = append(fixtures,
			fixtureCase{
				name: "compiler_parse_diag",
				cmd: fmt.Sprintf(
					"sh -c 'out=$(./oren build %q --backend c --platform %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=parse code=1\"'",
					"tests/native/fixtures/parse_error.oren",
					plat,
					targetsOutPath(target, arch, "c", "parse_error"),
					gcArg,
				),
				log:     "build/logs/compiler_parse_diag.log",
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{targetsOutPath(target, arch, "c", "parse_error")},
			},
			fixtureCase{
				name: "compiler_codegen_diag",
				cmd: fmt.Sprintf(
					"sh -c 'out=$(./oren build %q --backend native --platform %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"'",
					"tests/native/fixtures/codegen_error.oren",
					plat,
					targetsOutPath(target, arch, "native", "codegen_error"),
					gcArg,
				),
				log:     "build/logs/compiler_codegen_diag.log",
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{targetsOutPath(target, arch, "native", "codegen_error")},
			},
		)
	}

	// Tier‑1 x86_64 build smoke (Linux ELF + Windows PE). Opt-in by default because cross-compiling
	// for x64 on an arm64 dev machine is CPU-heavy.
	//
	// Enable via:
	//   OREN_TEST_TIER1_X64=1 make test
	if envBool("OREN_TEST_TIER1_X64", false) {
		keepArtifacts := false
		cleanup := []string{
			"build/tmp/tier1_native_smoke_x64_linux.build.out",
			"build/tmp/tier1_native_smoke_x64_linux.file.out",
			"build/tmp/tier1_native_smoke_x64_linux.strings.out",
			"build/tmp/tier1_native_smoke_x64_win.build.out",
			"build/tmp/tier1_native_smoke_x64_win.file.out",
			"build/tmp/tier1_native_smoke_x64_win.strings.out",
		}
		if !keepArtifacts {
			// When not doing remote-run, keep the repo clean by removing the generated binaries.
			cleanup = append(cleanup,
				targetsOutPath("linux", "x64", "native", "tier1_native_smoke"),
				targetsOutPath("windows", "x64", "native", "tier1_native_smoke.exe"),
			)
		}
		fixtures = append(fixtures, fixtureCase{
			name: "native_x64_tier1_smoke_builds",
			cmd: fmt.Sprintf(
				"./oren build %q --backend native --platform x64-linux -o %q > %q 2>&1 && "+
					"file %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"strings %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"./oren build %q --backend native --platform x64-windows -o %q > %q 2>&1 && "+
					"file %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"strings %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/tier1_native_smoke_main.oren",
				targetsOutPath("linux", "x64", "native", "tier1_native_smoke"),
				"build/tmp/tier1_native_smoke_x64_linux.build.out",
				targetsOutPath("linux", "x64", "native", "tier1_native_smoke"),
				"build/tmp/tier1_native_smoke_x64_linux.file.out",
				"ELF 64-bit",
				"build/tmp/tier1_native_smoke_x64_linux.file.out",
				"x86-64",
				"build/tmp/tier1_native_smoke_x64_linux.file.out",
				targetsOutPath("linux", "x64", "native", "tier1_native_smoke"),
				"build/tmp/tier1_native_smoke_x64_linux.strings.out",
				"tier1 smoke ok",
				"build/tmp/tier1_native_smoke_x64_linux.strings.out",
				"tier1 smoke proc ok",
				"build/tmp/tier1_native_smoke_x64_linux.strings.out",
				"tier1 spawn join ok",
				"build/tmp/tier1_native_smoke_x64_linux.strings.out",
				"tests/fixtures/tier1_native_smoke_main.oren",
				targetsOutPath("windows", "x64", "native", "tier1_native_smoke.exe"),
				"build/tmp/tier1_native_smoke_x64_win.build.out",
				targetsOutPath("windows", "x64", "native", "tier1_native_smoke.exe"),
				"build/tmp/tier1_native_smoke_x64_win.file.out",
				"PE32+",
				"build/tmp/tier1_native_smoke_x64_win.file.out",
				"x86-64",
				"build/tmp/tier1_native_smoke_x64_win.file.out",
				targetsOutPath("windows", "x64", "native", "tier1_native_smoke.exe"),
				"build/tmp/tier1_native_smoke_x64_win.strings.out",
				"tier1 smoke ok",
				"build/tmp/tier1_native_smoke_x64_win.strings.out",
				"tier1 smoke proc ok",
				"build/tmp/tier1_native_smoke_x64_win.strings.out",
				"tier1 spawn join ok",
				"build/tmp/tier1_native_smoke_x64_win.strings.out",
			),
			timeout: 3 * time.Minute,
			log:     "build/logs/native_x64_tier1_smoke_builds.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: cleanup,
		})
	}

	// Opt-in remote-run gate for x86_64 artifacts (Win11 + WSL2).
	//
	// Keep the default remote gate minimal and integration-first:
	// - one program (`tier1_native_smoke_main.oren`) covers most Tier‑1 semantics
	// - re-run the same artifact with env/args to validate runtime propagation
	if envBool("OREN_REMOTE_RUN", false) {
		baseEnv := "OREN_ENABLE_SIMD=1"
		if envBool("OREN_DEBUG_JOIN_TIMEOUT", false) {
			baseEnv += " OREN_DEBUG_JOIN_TIMEOUT=1"
		}
		if envBool("OREN_DEBUG_SLEEP", false) {
			baseEnv += " OREN_DEBUG_SLEEP=1"
		}
		if envBool("OREN_DEBUG_SLEEP_ALL", false) {
			baseEnv += " OREN_DEBUG_SLEEP_ALL=1"
		}
		tests := []remoteX64Test{
			{
				name: "tier1_native_smoke",
				src:  "tests/fixtures/tier1_native_smoke_main.oren",
				env:  baseEnv,
				args: "ARG_A ARG_B",
				expectSubstrings: []string{
					"tier1 smoke ok",
					"tier1 spawn join ok",
					"tier1 local fn ok",
					"tier1 args ok",
					"SIMD_ENABLED=1",
					"tier1 typed buffers ok",
					"tier1 forin typed buffers ok",
					"tier1 atomics ok",
					"tier1 stack trace ok",
					"stacktrace_leaf@tests/fixtures/tier1_native_smoke_main.oren",
					"tier1 proc ok",
				},
			},
			{
				name:       "tier1_native_abort_contract",
				artifact:   "tier1_native_smoke",
				src:        "tests/fixtures/tier1_native_smoke_main.oren",
				args:       "ARG_A ARG_B MODE_ABORT",
				expectExit: 1,
			},
			{
				name:       "tier1_native_call_depth_env_override",
				artifact:   "tier1_native_smoke",
				src:        "tests/fixtures/tier1_native_smoke_main.oren",
				env:        "OREN_CALL_DEPTH_MAX=8",
				args:       "ARG_A ARG_B MODE_CALL_DEPTH",
				expectExit: 1,
			},
			{
				name:       "tier1_native_modulo_by_zero_contract",
				artifact:   "tier1_native_smoke",
				src:        "tests/fixtures/tier1_native_smoke_main.oren",
				args:       "ARG_A ARG_B MODE_MOD0",
				expectExit: 1,
				expectSubstrings: []string{
					"modulo by zero",
				},
			},
		}
		fixtures = append(fixtures, remoteX64BatchFixture(tests))

		// Optional remote native self-hosting gate (x64):
		// Build a stage2 native compiler for x64-linux (WSL2) and/or x64-windows, then run
		// its `selftest-native` command remotely.
		if envBool("OREN_TEST_SELFHOST_NATIVE", false) {
			selfhostTests := []remoteX64Test{
				{
					name:       "remote_stage2_native_selftest",
					artifact:   "oren_stage2_native",
					src:        "oren.oren",
					args:       "selftest-native",
					expectExit: 0,
					expectSubstrings: []string{
						"selftest-native OK",
					},
				},
			}
			fixtures = append(fixtures, remoteX64SelfhostNativeFixture(selfhostTests))
		}
	}

	return fixtures
}
