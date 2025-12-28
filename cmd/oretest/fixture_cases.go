package main

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func buildFixtureCases(target string, gcArg string, full bool) []fixtureCase {
	// Keep `make test` iteration-friendly:
	// - fast suite: high-signal, low-cost fixtures only
	// - full suite: includes heavier security/tooling gates (signing, OpenAPI export, compiler-in-AVM)
	includeSigning := full || os.Getenv("OREN_TEST_SIGNING") == "1"
	includeOredoc := full || os.Getenv("OREN_TEST_OREDOC") == "1"

	// Compile-fail fixtures (portable semantics guards).
	fixtures := []fixtureCase{
		{
			name: "bootstrap_else_if_parse",
			cmd: fmt.Sprintf(
				"sh -c 'set -e; wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
					"cat > \"$wd/main.oren\" <<\"EOF\"\n"+
					"fn main() {\n"+
					"    var x = 0\n"+
					"    if x == 0 {\n"+
					"        exit(0)\n"+
					"    } else if x == 1 {\n"+
					"        exit(1)\n"+
					"    } else {\n"+
					"        exit(2)\n"+
					"    }\n"+
					"}\n"+
					"EOF\n"+
					"./oren_bootstrap build \"$wd/main.oren\" --emit-c > \"$wd/out.txt\" 2>&1; "+
					"test -s \"$wd/main.oren.c\"; "+
					"grep -Fq \"Wrote\" \"$wd/out.txt\"'",
				"build/tmp/fixture_bootstrap_else_if_parse",
			),
			log:     "build/logs/bootstrap_else_if_parse.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/tmp/fixture_bootstrap_else_if_parse"},
		},
		{
			name: "manifest_bytecode",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --target %s --deterministic --manifest -o %q > %q && "+
					"test -s %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Eq %q %q",
				"tests/modules/test_strings.oren",
				target,
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
				target,
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
			name: "bytecode_negative_int_constants",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --target %s --deterministic -o %q > %q && "+
					"./avm --disasm-consts %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/bytecode_neg_int_const.oren",
				target,
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
				target,
				"build/deterministic_1.obc",
				"build/deterministic_1.out",
				"tests/modules/test_strings.oren",
				target,
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
			name: "native_x64_tier1_smoke_builds",
			cmd: fmt.Sprintf(
				"./oren build %q --backend native --target linux --arch x64 -o %q > %q && "+
					"file %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"strings %q > %q && "+
					"grep -Fq %q %q && "+
					"./oren build %q --backend native --target windows --arch x64 -o %q > %q && "+
					"file %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"strings %q > %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/tier1_native_smoke_main.oren",
				"build/tier1_native_smoke_x64_linux",
				"build/tier1_native_smoke_x64_linux.build.out",
				"build/tier1_native_smoke_x64_linux",
				"build/tier1_native_smoke_x64_linux.file.out",
				"ELF 64-bit",
				"build/tier1_native_smoke_x64_linux.file.out",
				"x86-64",
				"build/tier1_native_smoke_x64_linux.file.out",
				"build/tier1_native_smoke_x64_linux",
				"build/tier1_native_smoke_x64_linux.strings.out",
				"tier1 smoke ok",
				"build/tier1_native_smoke_x64_linux.strings.out",
				"tests/fixtures/tier1_native_smoke_main.oren",
				"build/tier1_native_smoke_x64_win.exe",
				"build/tier1_native_smoke_x64_win.build.out",
				"build/tier1_native_smoke_x64_win.exe",
				"build/tier1_native_smoke_x64_win.file.out",
				"PE32+",
				"build/tier1_native_smoke_x64_win.file.out",
				"x86-64",
				"build/tier1_native_smoke_x64_win.file.out",
				"build/tier1_native_smoke_x64_win.exe",
				"build/tier1_native_smoke_x64_win.strings.out",
				"tier1 smoke ok",
				"build/tier1_native_smoke_x64_win.strings.out",
			),
			log:     "build/logs/native_x64_tier1_smoke_builds.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/tier1_native_smoke_x64_linux", "build/tier1_native_smoke_x64_linux.build.out", "build/tier1_native_smoke_x64_linux.file.out", "build/tier1_native_smoke_x64_linux.strings.out", "build/tier1_native_smoke_x64_win.exe", "build/tier1_native_smoke_x64_win.build.out", "build/tier1_native_smoke_x64_win.file.out", "build/tier1_native_smoke_x64_win.strings.out"},
		},

		{
			name: "oren_meta_emit",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				target,
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
				target,
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
				target,
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
				target,
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
			name: "deterministic_meta_hash",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --deterministic -o %q > %q && "+
					"./oren meta %q --target %s --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				target,
				"build/deterministic_meta_1.meta.json",
				"build/deterministic_meta_1.out",
				"tests/fixtures/meta_attrs_src.oren",
				target,
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
				target,
				"build/deterministic_native_meta_1",
				"build/deterministic_native_meta_1.out",
				"tests/modules/test_strings.oren",
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
				target,
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
			name: "version_flag",
			cmd:  "sh -c 'out=$(./oren --version 2>&1); rc=$?; printf \"%s\\n\" \"$out\"; test $rc -eq 0; printf \"%s\\n\" \"$out\" | grep -F \"oren 0.0.0-rolling\"'",
			log:  "build/logs/version_flag.log",
			ok:   func(rc int) bool { return rc == 0 },
		},
		{
			name: "completion_bash",
			cmd:  "sh -c 'out=$(./oren completion bash 2>&1); rc=$?; printf \"%s\\n\" \"$out\"; test $rc -eq 0; printf \"%s\\n\" \"$out\" | grep -F \"complete -F _oren oren\"; printf \"%s\\n\" \"$out\" | grep -F \"tokens linked graph\"; printf \"%s\\n\" \"$out\" | grep -F \"compgen -f\"'",
			log:  "build/logs/completion_bash.log",
			ok:   func(rc int) bool { return rc == 0 },
		},
		{
			name: "completion_zsh",
			cmd:  "sh -c 'out=$(./oren completion zsh 2>&1); rc=$?; printf \"%s\\n\" \"$out\"; test $rc -eq 0; printf \"%s\\n\" \"$out\" | grep -F \"#compdef oren\"; printf \"%s\\n\" \"$out\" | grep -F \"compdef _oren oren\"; printf \"%s\\n\" \"$out\" | grep -F \"tokens linked graph\"; printf \"%s\\n\" \"$out\" | grep -F \"compadd -f\"'",
			log:  "build/logs/completion_zsh.log",
			ok:   func(rc int) bool { return rc == 0 },
		},
		{
			name: "dump_tokens_missing_file_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren dump tokens %q -o %q --target %s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"'",
				"tests/native/fixtures/__missing__.oren",
				"build/dump_tokens_missing.json",
				target,
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
				target,
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
				target,
				"build/typecheck_bad_cast",
				gcArg,
			),
			log:     "build/logs/typecheck_rejects_bad_cast.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/typecheck_bad_cast"},
		},
		{
			name:    "strict_attrs_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --strict-attrs --attr-allow-prefixes myorg.%s", "tests/native/fixtures/strict_attrs_ok.oren", target, "build/strict_attrs_ok", gcArg),
			log:     "build/logs/strict_attrs_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/strict_attrs_ok"},
		},
		{
			name:    "strict_attrs_bad",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --strict-attrs%s", "tests/native/fixtures/strict_attrs_bad.oren", target, "build/strict_attrs_bad", gcArg),
			log:     "build/logs/strict_attrs_bad.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/strict_attrs_bad"},
		},
		{
			name:    "struct_field_assign_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q%s", "tests/native/fixtures/struct_field_assign_ok.oren", target, "build/struct_field_assign_ok", gcArg),
			log:     "build/logs/struct_field_assign_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/struct_field_assign_ok"},
		},
		{
			name:    "trait_impl_ambiguous_method",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_ambiguous_method.oren", target, "build/trait_impl_ambiguous_method", gcArg),
			log:     "build/logs/trait_impl_ambiguous_method.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_ambiguous_method"},
		},
		{
			name:    "trait_impl_duplicate",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_duplicate.oren", target, "build/trait_impl_duplicate", gcArg),
			log:     "build/logs/trait_impl_duplicate.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_duplicate"},
		},
		{
			name:    "trait_impl_split_blocks",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s -o %q%s", "tests/native/fixtures/trait_impl_split_blocks.oren", target, "build/trait_impl_split_blocks", gcArg),
			log:     "build/logs/trait_impl_split_blocks.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/trait_impl_split_blocks"},
		},
		{
			name:    "capsule_ok_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_ok.oren", target, "build/capsule_ok", gcArg),
			log:     "build/logs/capsule_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/capsule_ok"},
		},
		{
			name:    "capsule_bad_syscall_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_syscall.oren", target, "build/capsule_bad_syscall", gcArg),
			log:     "build/logs/capsule_bad_syscall.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/capsule_bad_syscall"},
		},
		{
			name:    "capsule_bad_fs_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_fs.oren", target, "build/capsule_bad_fs", gcArg),
			log:     "build/logs/capsule_bad_fs.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{"build/capsule_bad_fs"},
		},
		{
			name:    "capsule_ok_fs_allow_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s -o %q --capsule --cap-allow-domains FS%s", "tests/native/fixtures/capsule_ok_fs_allow.oren", target, "build/capsule_ok_fs_allow", gcArg),
			log:     "build/logs/capsule_ok_fs_allow.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/capsule_ok_fs_allow"},
		},
	}

	// Security fixtures (signing/cert-chain): useful, but expensive. Keep them out of the default
	// iteration suite unless explicitly requested.
	if includeSigning {
		fixtures = append(fixtures,
			fixtureCase{
				name: "signed_obc_verify_cli",
				cmd: fmt.Sprintf(
					"set -e; "+
						"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
						"echo \"[fixture] keygen (ephemeral)\"; "+
						"./orensign keygen --out \"$wd/ca\"; "+
						"echo \"[fixture] build unsigned obc\"; "+
						"./oren build %q --backend bytecode --target %s -o %q%s; "+
						"echo \"[fixture] sign obc\"; "+
						"./orensign sign-obc --sk \"$wd/ca/root_ed25519_sk.bin\" --in %q --out %q; "+
						"echo \"[fixture] verify + run signed\"; "+
						"./avm --require-sig --trusted-pubkey \"$wd/ca/root_ed25519_pk.bin\" %q > %q; "+
						"grep -Fq %q %q; "+
						"echo \"[fixture] verify unsigned must fail\"; "+
						"set +e; ./avm --require-sig --trusted-pubkey \"$wd/ca/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
						"test $rc -ne 0",
					"build/tmp/fixture_signed_obc_verify_cli",
					"tests/avm/fixtures/signed_obc_smoke.oren",
					target,
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
			fixtureCase{
				name: "signed_obc_verify_cli_multi_root_hex",
				cmd: fmt.Sprintf(
					"set -e; "+
						"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
						"echo \"[fixture] keygen root + wrong (ephemeral)\"; "+
						"./orensign keygen --out \"$wd/ca\"; "+
						"./orensign keygen --out \"$wd/wrong\"; "+
						"echo \"[fixture] build unsigned obc\"; "+
						"./oren build %q --backend bytecode --target %s -o %q%s; "+
						"echo \"[fixture] sign obc\"; "+
						"./orensign sign-obc --sk \"$wd/ca/root_ed25519_sk.bin\" --in %q --out %q; "+
						"echo \"[fixture] verify + run signed with hex list (wrong,correct)\"; "+
						"bad=$(xxd -p -c 256 \"$wd/wrong/root_ed25519_pk.bin\" | tr -d '\\n'); "+
						"good=$(xxd -p -c 256 \"$wd/ca/root_ed25519_pk.bin\" | tr -d '\\n'); "+
						"./avm --require-sig --trusted-pubkey-hex \"${bad},${good}\" %q > %q; "+
						"grep -Fq %q %q",
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex",
					"tests/avm/fixtures/signed_obc_smoke.oren",
					target,
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/signed_obc_smoke.obc",
					gcArg,
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/signed_obc_smoke.obc",
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/signed_obc_smoke.signed.obc",
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/signed_obc_smoke.signed.obc",
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/fixture_signed_obc_verify_cli_multi_root_hex.out",
					"signed obc OK",
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex/fixture_signed_obc_verify_cli_multi_root_hex.out",
				),
				timeout: 4 * time.Minute,
				log:     "build/logs/fixture_signed_obc_verify_cli_multi_root_hex.log",
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{
					"build/tmp/fixture_signed_obc_verify_cli_multi_root_hex",
				},
			},
			fixtureCase{
				name: "signed_obc_verify_cert_chain_cli",
				cmd: fmt.Sprintf(
					"set -e; "+
						"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
						"echo \"[fixture] keygen root/org/dev (ephemeral)\"; "+
						"mkdir -p \"$wd/ca\"; "+
						"./orensign keygen --out \"$wd/ca/root\"; "+
						"./orensign keygen --out \"$wd/ca/org\"; "+
						"./orensign keygen --out \"$wd/ca/dev\"; "+
						"echo \"[fixture] issue root->org (can_issue) and org->dev certs\"; "+
						"./orensign issue-cert --issuer-sk \"$wd/ca/root/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/org/root_ed25519_pk.bin\" --out \"$wd/ca/org.cert\" --can-issue; "+
						"./orensign issue-cert --issuer-sk \"$wd/ca/org/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/dev/root_ed25519_pk.bin\" --out \"$wd/ca/dev.cert\"; "+
						"echo \"[fixture] build unsigned obc\"; "+
						"./oren build %q --backend bytecode --target %s -o %q%s; "+
						"echo \"[fixture] sign obc with dev key + embed leaf-first chain\"; "+
						"./orensign sign-obc --sk \"$wd/ca/dev/root_ed25519_sk.bin\" --cert \"$wd/ca/dev.cert\" --cert \"$wd/ca/org.cert\" --in %q --out %q; "+
						"echo \"[fixture] verify + run (require chain)\"; "+
						"./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > %q; "+
						"grep -Fq %q %q; "+
						"echo \"[fixture] verify missing chain must fail\"; "+
						"./orensign sign-obc --sk \"$wd/ca/dev/root_ed25519_sk.bin\" --in %q --out %q; "+
						"set +e; ./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
						"test $rc -ne 0; "+
						"echo \"[fixture] verify root-sign without chain must fail under require-cert-chain\"; "+
						"./orensign sign-obc --sk \"$wd/ca/root/root_ed25519_sk.bin\" --in %q --out %q; "+
						"set +e; ./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > /dev/null 2>&1; rc=$?; set -e; "+
						"test $rc -ne 0",
					"build/tmp/fixture_signed_obc_verify_cert_chain_cli",
					"tests/avm/fixtures/signed_obc_smoke.oren",
					target,
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
			fixtureCase{
				name: "signed_obc_verify_cert_chain_allow_domains",
				cmd: fmt.Sprintf(
					"set -e; "+
						"wd=%q; rm -rf \"$wd\"; mkdir -p \"$wd\"; "+
						"echo \"[fixture] keygen root/org/dev (ephemeral)\"; "+
						"mkdir -p \"$wd/ca\"; "+
						"./orensign keygen --out \"$wd/ca/root\"; "+
						"./orensign keygen --out \"$wd/ca/org\"; "+
						"./orensign keygen --out \"$wd/ca/dev\"; "+
						"echo \"[fixture] issue root->org (can_issue, allow CORE-only) and org->dev (inherit) certs\"; "+
						"./orensign issue-cert --issuer-sk \"$wd/ca/root/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/org/root_ed25519_pk.bin\" --out \"$wd/ca/org.cert\" --can-issue --allow-domains CORE; "+
						"./orensign issue-cert --issuer-sk \"$wd/ca/org/root_ed25519_sk.bin\" --subject-pk \"$wd/ca/dev/root_ed25519_pk.bin\" --out \"$wd/ca/dev.cert\"; "+
						"echo \"[fixture] build unsigned obc (uses FS)\"; "+
						"./oren build %q --backend bytecode --target %s -o %q%s; "+
						"echo \"[fixture] sign obc with dev key + embed leaf-first chain\"; "+
						"./orensign sign-obc --sk \"$wd/ca/dev/root_ed25519_sk.bin\" --cert \"$wd/ca/dev.cert\" --cert \"$wd/ca/org.cert\" --in %q --out %q; "+
						"echo \"[fixture] verify must fail due to cert allow_domains\"; "+
						"set +e; ./avm --require-sig --require-cert-chain --trusted-pubkey \"$wd/ca/root/root_ed25519_pk.bin\" %q > %q 2>&1; rc=$?; set -e; "+
						"test $rc -ne 0; "+
						"grep -Fq %q %q",
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains",
					"tests/avm/fixtures/signed_obc_uses_fs.oren",
					target,
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/signed_obc_uses_fs.obc",
					gcArg,
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/signed_obc_uses_fs.obc",
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/signed_obc_uses_fs.devchain.obc",
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/signed_obc_uses_fs.devchain.obc",
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/fixture_signed_obc_verify_cert_chain_allow_domains.out",
					"cert policy failed",
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains/fixture_signed_obc_verify_cert_chain_allow_domains.out",
				),
				log: "build/logs/fixture_signed_obc_verify_cert_chain_allow_domains.log",
				ok:  func(rc int) bool { return rc == 0 },
				cleanup: []string{
					"build/tmp/fixture_signed_obc_verify_cert_chain_allow_domains",
				},
			},
		)
	}

	// Tooling fixtures (OpenAPI export): keep out of fast suite by default.
	if includeOredoc {
		fixtures = append(fixtures, fixtureCase{
			name: "oredoc_openapi_export",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s -o %q && "+
					"./oredoc openapi %q -o %q --title %q --version %q --format %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/modules/test_json_serde_attrs.oren",
				target,
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
		})
	}

	if full {
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
		fixtures = append(fixtures, fixtureCase{
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
				target,
				"build/oren_compiler.obc",
				gcArg,
				fixtureEnv,
				"tests/avm/fixtures/compiler_in_avm_vfs_harness.oren",
				target,
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
		fixtures = append(fixtures, fixtureCase{
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
				target,
				"build/stdlib_bundle.obc",
				gcArg,
				fixtureEnv,
				"oren.oren",
				target,
				"build/oren_compiler.obc",
				gcArg,
				fixtureEnv,
				"tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren",
				target,
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
		fixtures = append(fixtures, fixtureCase{
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
				target,
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

	if envBool("OREN_REMOTE_RUN", false) {
		// Opt-in remote-run gate for x86_64 artifacts (Win11 + WSL2).
		// See docs/REMOTE_X64_ENV.md for the proxy access workflow.
		remoteX64 := []struct {
			name            string
			src             string
			expectExit      int
			expectSubstring string
			timeout         time.Duration
		}{
			{name: "remote_x64_run_tier1_smoke_print", src: "tests/fixtures/tier1_native_smoke_main.oren", expectSubstring: "tier1 smoke ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_abort_contract", src: "tests/fixtures/tier1_native_abort_contract_main.oren", expectExit: 1, timeout: 5 * time.Minute},
		}

		for _, rf := range remoteX64 {
			workdir := filepath.Join("build", "tmp", "fixture_"+rf.name)
			cmd := ""
			if rf.expectSubstring != "" {
				cmd = remoteX64RunPrintFixtureCmd(workdir, rf.src, rf.expectSubstring)
			} else {
				cmd = remoteX64RunExitcodeFixtureCmd(workdir, rf.src, rf.expectExit)
			}

			t := rf.timeout
			if t == 0 {
				t = 5 * time.Minute
			}

			fixtures = append(fixtures, fixtureCase{
				name:    rf.name,
				cmd:     cmd,
				timeout: t,
				log:     fmt.Sprintf("build/logs/fixture_%s.log", rf.name),
				ok:      func(rc int) bool { return rc == 0 },
				cleanup: []string{workdir},
			})
		}
	}

	return fixtures
}
