package main

import (
	"fmt"
	"strings"
)

func buildRuntimeFixtureCases(target string, gcArg string) []runtimeFixtureCase {
	arch := hostOrenArch()
	// Runtime diagnostics fixtures (expected non-zero exit, machine-readable header).
	runtimeFixtures := []runtimeFixtureCase{
		{
			name:  "system_shell_missing_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/system_shell_missing.oren", target, arch, targetsOutPath(target, arch, "native", "system_shell_missing_native"), gcArg),
			run:   "OREN_SYSTEM_SHELL=/no_such_shell ./" + targetsOutPath(target, arch, "native", "system_shell_missing_native"),
			log:   "build/logs/system_shell_missing_native.log",
			ok: func(rc int, out string) bool {
				return rc == 0
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "system_shell_missing_native")},
		},
		{
			name:  "diag_fail_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/diag_fail.oren", target, arch, targetsOutPath(target, arch, "native", "diag_fail_native"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "native", "diag_fail_native"),
			log:   "build/logs/diag_fail_native.log",
			ok: func(rc int, out string) bool {
				return rc == 42 && strings.Contains(out, "OREN_DIAG kind=fail code=42")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "diag_fail_native")},
		},
		{
			name:  "diag_fail_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/diag_fail.oren", target, arch, targetsOutPath(target, arch, "c", "diag_fail_c"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "c", "diag_fail_c"),
			log:   "build/logs/diag_fail_c.log",
			ok: func(rc int, out string) bool {
				return rc == 42 && strings.Contains(out, "OREN_DIAG kind=fail code=42")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "diag_fail_c")},
		},
		{
			name:  "arith_div0_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_div0.oren", target, arch, targetsOutPath(target, arch, "native", "arith_div0_native"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "native", "arith_div0_native"),
			log:   "build/logs/arith_div0_native.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "division by zero")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "arith_div0_native")},
		},
		{
			name:  "arith_div0_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_div0.oren", target, arch, targetsOutPath(target, arch, "c", "arith_div0_c"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "c", "arith_div0_c"),
			log:   "build/logs/arith_div0_c.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "division by zero")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "arith_div0_c")},
		},
		{
			name:  "arith_div_overflow_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_div_overflow.oren", target, arch, targetsOutPath(target, arch, "native", "arith_div_overflow_native"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "native", "arith_div_overflow_native"),
			log:   "build/logs/arith_div_overflow_native.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "division overflow (i64_min / -1)")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "arith_div_overflow_native")},
		},
		{
			name:  "arith_div_overflow_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_div_overflow.oren", target, arch, targetsOutPath(target, arch, "c", "arith_div_overflow_c"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "c", "arith_div_overflow_c"),
			log:   "build/logs/arith_div_overflow_c.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "division overflow (i64_min / -1)")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "arith_div_overflow_c")},
		},
		{
			name:  "arith_shift_oob_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_shift_oob.oren", target, arch, targetsOutPath(target, arch, "native", "arith_shift_oob_native"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "native", "arith_shift_oob_native"),
			log:   "build/logs/arith_shift_oob_native.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "shl shift count out of range (need 0..63)")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "arith_shift_oob_native")},
		},
		{
			name:  "arith_shift_oob_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/arith_shift_oob.oren", target, arch, targetsOutPath(target, arch, "c", "arith_shift_oob_c"), gcArg),
			run:   "./" + targetsOutPath(target, arch, "c", "arith_shift_oob_c"),
			log:   "build/logs/arith_shift_oob_c.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "shl shift count out of range (need 0..63)")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "arith_shift_oob_c")},
		},
		{
			name:  "call_depth_overflow_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/call_depth_overflow.oren", target, arch, targetsOutPath(target, arch, "c", "call_depth_overflow_c"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=64 ./" + targetsOutPath(target, arch, "c", "call_depth_overflow_c"),
			log:   "build/logs/call_depth_overflow_c.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "call_depth_overflow_c")},
		},
		{
			name:  "call_depth_overflow_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/call_depth_overflow.oren", target, arch, targetsOutPath(target, arch, "native", "call_depth_overflow_native"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=64 ./" + targetsOutPath(target, arch, "native", "call_depth_overflow_native"),
			log:   "build/logs/call_depth_overflow_native.log",
			ok: func(rc int, out string) bool {
				return rc != 0 && strings.Contains(out, "OREN_DIAG kind=panic code=1") && strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "call_depth_overflow_native")},
		},
		{
			name:  "tail_recursion_ok_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/tail_recursion_ok.oren", target, arch, targetsOutPath(target, arch, "c", "tail_recursion_ok_c"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=8 ./" + targetsOutPath(target, arch, "c", "tail_recursion_ok_c"),
			log:   "build/logs/tail_recursion_ok_c.log",
			ok: func(rc int, out string) bool {
				return rc == 0 && !strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "tail_recursion_ok_c")},
		},
		{
			name:  "tail_recursion_ok_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/tail_recursion_ok.oren", target, arch, targetsOutPath(target, arch, "native", "tail_recursion_ok_native"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=8 ./" + targetsOutPath(target, arch, "native", "tail_recursion_ok_native"),
			log:   "build/logs/tail_recursion_ok_native.log",
			ok: func(rc int, out string) bool {
				return rc == 0 && !strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "tail_recursion_ok_native")},
		},
		{
			name:  "non_tail_modconst_ok_c",
			build: fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/non_tail_modconst_ok.oren", target, arch, targetsOutPath(target, arch, "c", "non_tail_modconst_ok_c"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=8 ./" + targetsOutPath(target, arch, "c", "non_tail_modconst_ok_c"),
			log:   "build/logs/non_tail_modconst_ok_c.log",
			ok: func(rc int, out string) bool {
				return rc == 0 && !strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "c", "non_tail_modconst_ok_c")},
		},
		{
			name:  "non_tail_modconst_ok_native",
			build: fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/non_tail_modconst_ok.oren", target, arch, targetsOutPath(target, arch, "native", "non_tail_modconst_ok_native"), gcArg),
			run:   "OREN_CALL_DEPTH_MAX=8 ./" + targetsOutPath(target, arch, "native", "non_tail_modconst_ok_native"),
			log:   "build/logs/non_tail_modconst_ok_native.log",
			ok: func(rc int, out string) bool {
				return rc == 0 && !strings.Contains(out, "call depth exceeded")
			},
			cleanup: []string{targetsOutPath(target, arch, "native", "non_tail_modconst_ok_native")},
		},
	}

	return runtimeFixtures
}
