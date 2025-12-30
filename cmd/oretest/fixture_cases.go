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
	arch := hostOrenArch()

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
				"./oren build %q --backend bytecode --deterministic --manifest -o %q > %q && "+
					"test -s %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Eq %q %q",
				"tests/modules/test_strings.oren",
				"build/targets/avm/bytecode/manifest_bytecode.obc",
				"build/tmp/manifest_bytecode.out",
				"build/targets/avm/bytecode/manifest_bytecode.obc.manifest.json",
				"\"kind\":\"bytecode\"",
				"build/targets/avm/bytecode/manifest_bytecode.obc.manifest.json",
				"\"deterministic\":true",
				"build/targets/avm/bytecode/manifest_bytecode.obc.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				"build/targets/avm/bytecode/manifest_bytecode.obc.manifest.json",
			),
			log:     "build/logs/manifest_bytecode.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/targets/avm/bytecode/manifest_bytecode.obc", "build/tmp/manifest_bytecode.out", "build/targets/avm/bytecode/manifest_bytecode.obc.manifest.json"},
		},
		{
			name: "manifest_meta",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s --deterministic --manifest -o %q > %q && "+
					"test -s %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Eq %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "manifest_meta"),
				"build/tmp/manifest_meta.out",
				targetsMetaPath(target, arch, "manifest_meta")+".manifest.json",
				"\"kind\":\"meta\"",
				targetsMetaPath(target, arch, "manifest_meta")+".manifest.json",
				"\"deterministic\":true",
				targetsMetaPath(target, arch, "manifest_meta")+".manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				targetsMetaPath(target, arch, "manifest_meta")+".manifest.json",
			),
			log:     "build/logs/manifest_meta.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsMetaPath(target, arch, "manifest_meta"), "build/tmp/manifest_meta.out", targetsMetaPath(target, arch, "manifest_meta") + ".manifest.json"},
		},
		{
			name: "bytecode_negative_int_constants",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --deterministic -o %q > %q && "+
					"./avm --disasm-consts %q > %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/bytecode_neg_int_const.oren",
				"build/targets/avm/bytecode/bytecode_neg_int_const.obc",
				"build/tmp/bytecode_neg_int_const.build.out",
				"build/targets/avm/bytecode/bytecode_neg_int_const.obc",
				"build/tmp/bytecode_neg_int_const.disasm.out",
				"=-4",
				"build/tmp/bytecode_neg_int_const.disasm.out",
				"=-3",
				"build/tmp/bytecode_neg_int_const.disasm.out",
			),
			log:     "build/logs/fixture_bytecode_negative_int_constants.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/targets/avm/bytecode/bytecode_neg_int_const.obc", "build/tmp/bytecode_neg_int_const.build.out", "build/tmp/bytecode_neg_int_const.disasm.out"},
		},
		{
			name: "deterministic_bytecode_hash",
			cmd: fmt.Sprintf(
				"./oren build %q --backend bytecode --deterministic -o %q > %q && "+
					"./oren build %q --backend bytecode --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=bytecode sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=bytecode sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/modules/test_strings.oren",
				"build/targets/avm/bytecode/deterministic_1.obc",
				"build/tmp/deterministic_1.out",
				"tests/modules/test_strings.oren",
				"build/targets/avm/bytecode/deterministic_2.obc",
				"build/tmp/deterministic_2.out",
				"build/tmp/deterministic_1.out",
				"build/tmp/deterministic_1.hash",
				"build/tmp/deterministic_2.out",
				"build/tmp/deterministic_2.hash",
				"build/tmp/deterministic_1.hash",
				"build/tmp/deterministic_2.hash",
			),
			log:     "build/logs/deterministic_bytecode_hash.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{"build/targets/avm/bytecode/deterministic_1.obc", "build/targets/avm/bytecode/deterministic_2.obc", "build/tmp/deterministic_1.out", "build/tmp/deterministic_2.out", "build/tmp/deterministic_1.hash", "build/tmp/deterministic_2.hash"},
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
			),
			log: "build/logs/native_x64_tier1_smoke_builds.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				targetsOutPath("linux", "x64", "native", "tier1_native_smoke"),
				"build/tmp/tier1_native_smoke_x64_linux.build.out",
				"build/tmp/tier1_native_smoke_x64_linux.file.out",
				"build/tmp/tier1_native_smoke_x64_linux.strings.out",
				targetsOutPath("windows", "x64", "native", "tier1_native_smoke.exe"),
				"build/tmp/tier1_native_smoke_x64_win.build.out",
				"build/tmp/tier1_native_smoke_x64_win.file.out",
				"build/tmp/tier1_native_smoke_x64_win.strings.out",
			},
		},

		{
			name: "oren_meta_emit",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s -o %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q && grep -Fq %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "meta_attrs"),
				"f: doc line 1",
				targetsMetaPath(target, arch, "meta_attrs"),
				"\"name\": \"Reader\"",
				targetsMetaPath(target, arch, "meta_attrs"),
				"serde.rename",
				targetsMetaPath(target, arch, "meta_attrs"),
				"\"traits\": [",
				targetsMetaPath(target, arch, "meta_attrs"),
			),
			log:     "build/logs/oren_meta_emit.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsMetaPath(target, arch, "meta_attrs")},
		},
		{
			name: "oren_meta_globals_attrs",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s -o %q && grep -Fq %q %q && grep -Fq %q %q",
				"tests/fixtures/meta_attrs_globals.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "meta_attrs_globals"),
				"\"globals\": [",
				targetsMetaPath(target, arch, "meta_attrs_globals"),
				"myorg.global",
				targetsMetaPath(target, arch, "meta_attrs_globals"),
			),
			log:     "build/logs/oren_meta_globals_attrs.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsMetaPath(target, arch, "meta_attrs_globals")},
		},
		{
			name: "oren_meta_serde_schema",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s -o %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/modules/test_json_serde_attrs.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "serde_schema"),
				"\"serde\": {\"version\": 1, \"format\": \"json\", \"tag\": \"User\"",
				targetsMetaPath(target, arch, "serde_schema"),
				"\"wire\": \"user_id\"",
				targetsMetaPath(target, arch, "serde_schema"),
				"\"skip\": true",
				targetsMetaPath(target, arch, "serde_schema"),
				"\"default\": 0",
				targetsMetaPath(target, arch, "serde_schema"),
				"\"ann_type\": \"i32\"",
				targetsMetaPath(target, arch, "serde_schema"),
			),
			log:     "build/logs/oren_meta_serde_schema.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsMetaPath(target, arch, "serde_schema")},
		},
		{
			name: "oren_meta_serde_formats",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s -o %q && "+
					"grep -Fq %q %q && "+
					"grep -Fq %q %q",
				"tests/fixtures/meta_serde_formats.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "serde_formats"),
				"\"serde\": {\"version\": 1, \"format\": \"json\", \"tag\": \"User\"",
				targetsMetaPath(target, arch, "serde_formats"),
				"\"formats\": [\"json\", \"yaml\"]",
				targetsMetaPath(target, arch, "serde_formats"),
			),
			log:     "build/logs/oren_meta_serde_formats.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsMetaPath(target, arch, "serde_formats")},
		},
		{
			name: "deterministic_meta_hash",
			cmd: fmt.Sprintf(
				"./oren meta %q --target %s --arch %s --deterministic -o %q > %q && "+
					"./oren meta %q --target %s --arch %s --deterministic -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q",
				"tests/fixtures/meta_attrs_src.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "deterministic_meta_1"),
				"build/tmp/deterministic_meta_1.out",
				"tests/fixtures/meta_attrs_src.oren",
				target,
				arch,
				targetsMetaPath(target, arch, "deterministic_meta_2"),
				"build/tmp/deterministic_meta_2.out",
				"build/tmp/deterministic_meta_1.out",
				"build/tmp/deterministic_meta_1.hash",
				"build/tmp/deterministic_meta_2.out",
				"build/tmp/deterministic_meta_2.hash",
				"build/tmp/deterministic_meta_1.hash",
				"build/tmp/deterministic_meta_2.hash",
			),
			log: "build/logs/deterministic_meta_hash.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				targetsMetaPath(target, arch, "deterministic_meta_1"),
				targetsMetaPath(target, arch, "deterministic_meta_2"),
				"build/tmp/deterministic_meta_1.out",
				"build/tmp/deterministic_meta_2.out",
				"build/tmp/deterministic_meta_1.hash",
				"build/tmp/deterministic_meta_2.hash",
			},
		},
		{
			name: "deterministic_native_meta_hash",
			cmd: fmt.Sprintf(
				"./oren build %q --backend native --target %s --arch %s --metadata --deterministic --manifest -o %q > %q && "+
					"./oren build %q --backend native --target %s --arch %s --metadata --deterministic --manifest -o %q > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"grep -E '^OREN_ARTIFACT kind=meta sha256=' %q | sed 's/^.* sha256=\\([0-9a-f]*\\) path=.*$/\\1/' > %q && "+
					"diff -q %q %q && "+
					"test -s %q && test -s %q && "+
					"grep -Fq %q %q && grep -Fq %q %q && grep -Eq %q %q && "+
					"grep -Fq %q %q && grep -Fq %q %q && grep -Eq %q %q",
				"tests/modules/test_strings.oren",
				target,
				arch,
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1"),
				"build/tmp/deterministic_native_meta_1.out",
				"tests/modules/test_strings.oren",
				target,
				arch,
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2"),
				"build/tmp/deterministic_native_meta_2.out",
				"build/tmp/deterministic_native_meta_1.out",
				"build/tmp/deterministic_native_meta_1.hash",
				"build/tmp/deterministic_native_meta_2.out",
				"build/tmp/deterministic_native_meta_2.hash",
				"build/tmp/deterministic_native_meta_1.hash",
				"build/tmp/deterministic_native_meta_2.hash",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1")+".meta.json.manifest.json",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2")+".meta.json.manifest.json",
				"\"kind\":\"meta\"",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1")+".meta.json.manifest.json",
				"\"deterministic\":true",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1")+".meta.json.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1")+".meta.json.manifest.json",
				"\"kind\":\"meta\"",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2")+".meta.json.manifest.json",
				"\"deterministic\":true",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2")+".meta.json.manifest.json",
				"\\\"size_bytes\\\":[1-9][0-9]*",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2")+".meta.json.manifest.json",
			),
			log: "build/logs/deterministic_native_meta_hash.log",
			ok:  func(rc int) bool { return rc == 0 },
			cleanup: []string{
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1"),
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1") + ".meta.json",
				"build/tmp/deterministic_native_meta_1.out",
				"build/tmp/deterministic_native_meta_1.hash",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1") + ".manifest.json",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_1") + ".meta.json.manifest.json",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2"),
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2") + ".meta.json",
				"build/tmp/deterministic_native_meta_2.out",
				"build/tmp/deterministic_native_meta_2.hash",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2") + ".manifest.json",
				targetsOutPath(target, arch, "native", "deterministic_native_meta_2") + ".meta.json.manifest.json",
			},
		},
		{
			name: "compiler_parse_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=parse code=1\"'",
				"tests/native/fixtures/parse_error.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "parse_error"),
				gcArg,
			),
			log:     "build/logs/compiler_parse_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "parse_error")},
		},
		{
			name: "compiler_codegen_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend native --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"'",
				"tests/native/fixtures/codegen_error.oren",
				target,
				arch,
				targetsOutPath(target, arch, "native", "codegen_error"),
				gcArg,
			),
			log:     "build/logs/compiler_codegen_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "codegen_error")},
		},
		{
			name: "compiler_bytecode_codegen_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend bytecode -o %q%s 2>&1); rc=$?; printf \"%%s\n\" \"$out\"; test $rc -ne 0; printf \"%%s\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"; printf \"%%s\n\" \"$out\" | grep -F \"Bytecode codegen errors:\"'",
				"tests/native/fixtures/bytecode_codegen_error.oren",
				targetsOutPath("avm", "avm64", "bytecode", "bytecode_codegen_err"),
				gcArg,
			),
			log:     "build/logs/compiler_bytecode_codegen_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath("avm", "avm64", "bytecode", "bytecode_codegen_err")},
		},
		{
			name: "compiler_bytecode_assign_undefined_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend bytecode -o %q%s 2>&1); rc=$?; printf \"%%s\n\" \"$out\"; test $rc -ne 0; printf \"%%s\n\" \"$out\" | grep -F \"OREN_DIAG kind=codegen code=1\"; printf \"%%s\n\" \"$out\" | grep -F \"Bytecode codegen errors:\"; printf \"%%s\n\" \"$out\" | grep -F \"undefined variable in assignment\"'",
				"tests/fixtures/bytecode_assign_undefined.oren",
				targetsOutPath("avm", "avm64", "bytecode", "bytecode_assign_undefined"),
				gcArg,
			),
			log:     "build/logs/compiler_bytecode_assign_undefined_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath("avm", "avm64", "bytecode", "bytecode_assign_undefined")},
		},
		{
			name: "compiler_impl_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"'",
				"tests/native/fixtures/trait_impl_duplicate.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "impl_err"),
				gcArg,
			),
			log:     "build/logs/compiler_impl_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "impl_err")},
		},
		{
			name: "compiler_packview_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"Packview errors:\"'",
				"tests/native/fixtures/packview_error.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "packview_err"),
				gcArg,
			),
			log:     "build/logs/compiler_packview_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "packview_err")},
		},
		{
			name: "compiler_abi_layout_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"ABI layout errors:\"'",
				"tests/native/fixtures/abi_layout_error.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "abi_layout_err"),
				gcArg,
			),
			log:     "build/logs/compiler_abi_layout_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "abi_layout_err")},
		},
		{
			name: "compiler_generic_call_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"unspecialized call to generic function\"'",
				"tests/native/fixtures/generic_unspecialized_call.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "generic_unspecialized_call"),
				gcArg,
			),
			log:     "build/logs/compiler_generic_call_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "generic_unspecialized_call")},
		},
		{
			name: "compiler_generic_constraint_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"missing impl for trait\"'",
				"tests/native/fixtures/generic_constraint_missing_impl.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "generic_constraint_missing_impl"),
				gcArg,
			),
			log:     "build/logs/compiler_generic_constraint_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "generic_constraint_missing_impl")},
		},
		{
			name: "missing_file_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"'",
				"tests/native/fixtures/__missing__.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "missing_file"),
				gcArg,
			),
			log:     "build/logs/missing_file_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "missing_file")},
		},
		{
			name: "unknown_backend_diag",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend %q --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"; printf \"%%s\\n\" \"$out\" | grep -F \"Unknown backend:\"'",
				"tests/modules/test_strings.oren",
				"nope",
				target,
				arch,
				targetsOutPath(target, arch, "c", "unknown_backend"),
				gcArg,
			),
			log:     "build/logs/unknown_backend_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "unknown_backend")},
		},
		{
			name: "build_cli_modern_equals_and_ordering",
			cmd: fmt.Sprintf(
				"./oren build --backend=native --target=%s --arch=%s --out=%q %q%s",
				target,
				arch,
				targetsOutPath(target, arch, "native", "cli_modern_eq"),
				"tests/native/fixtures/struct_field_assign_ok.oren",
				gcArg,
			),
			log:     "build/logs/build_cli_modern_equals_and_ordering.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "cli_modern_eq")},
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
				"sh -c 'out=$(./oren build %q --backend native --emit-c --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=compile code=2\"; printf \"%%s\\n\" \"$out\" | grep -F -- \"--emit-c is only supported\"'",
				"tests/modules/test_strings.oren",
				target,
				arch,
				targetsOutPath(target, arch, "native", "emit_c_native_bad"),
				gcArg,
			),
			log:     "build/logs/build_emit_c_with_native_diag.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "emit_c_native_bad")},
		},
		{
			name: "typecheck_rejects_bad_cast",
			cmd: fmt.Sprintf(
				"sh -c 'out=$(./oren build %q --backend c --typecheck --target %s --arch %s -o %q%s 2>&1); rc=$?; printf \"%%s\\n\" \"$out\"; test $rc -ne 0; printf \"%%s\\n\" \"$out\" | grep -F \"OREN_DIAG kind=typecheck code=1\"; printf \"%%s\\n\" \"$out\" | grep -F \"typecheck:\"'",
				"tests/fixtures/typecheck_bad_cast.oren",
				target,
				arch,
				targetsOutPath(target, arch, "c", "typecheck_bad_cast"),
				gcArg,
			),
			log:     "build/logs/typecheck_rejects_bad_cast.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "c", "typecheck_bad_cast")},
		},
		{
			name:    "strict_attrs_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --strict-attrs --attr-allow-prefixes myorg.%s", "tests/native/fixtures/strict_attrs_ok.oren", target, arch, targetsOutPath(target, arch, "native", "strict_attrs_ok"), gcArg),
			log:     "build/logs/strict_attrs_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "strict_attrs_ok")},
		},
		{
			name:    "strict_attrs_bad",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --strict-attrs%s", "tests/native/fixtures/strict_attrs_bad.oren", target, arch, targetsOutPath(target, arch, "native", "strict_attrs_bad"), gcArg),
			log:     "build/logs/strict_attrs_bad.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "native", "strict_attrs_bad")},
		},
		{
			name:    "struct_field_assign_ok",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q%s", "tests/native/fixtures/struct_field_assign_ok.oren", target, arch, targetsOutPath(target, arch, "native", "struct_field_assign_ok"), gcArg),
			log:     "build/logs/struct_field_assign_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "struct_field_assign_ok")},
		},
		{
			name:    "trait_impl_ambiguous_method",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/trait_impl_ambiguous_method.oren", target, arch, targetsOutPath(target, arch, "c", "trait_impl_ambiguous_method"), gcArg),
			log:     "build/logs/trait_impl_ambiguous_method.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "c", "trait_impl_ambiguous_method")},
		},
		{
			name:    "trait_impl_duplicate",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/trait_impl_duplicate.oren", target, arch, targetsOutPath(target, arch, "c", "trait_impl_duplicate"), gcArg),
			log:     "build/logs/trait_impl_duplicate.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "c", "trait_impl_duplicate")},
		},
		{
			name:    "trait_impl_split_blocks",
			cmd:     fmt.Sprintf("./oren build %q --backend c --target %s --arch %s -o %q%s", "tests/native/fixtures/trait_impl_split_blocks.oren", target, arch, targetsOutPath(target, arch, "c", "trait_impl_split_blocks"), gcArg),
			log:     "build/logs/trait_impl_split_blocks.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "c", "trait_impl_split_blocks")},
		},
		{
			name:    "capsule_ok_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --capsule%s", "tests/native/fixtures/capsule_ok.oren", target, arch, targetsOutPath(target, arch, "native", "capsule_ok"), gcArg),
			log:     "build/logs/capsule_ok.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "capsule_ok")},
		},
		{
			name:    "capsule_bad_syscall_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_syscall.oren", target, arch, targetsOutPath(target, arch, "native", "capsule_bad_syscall"), gcArg),
			log:     "build/logs/capsule_bad_syscall.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "native", "capsule_bad_syscall")},
		},
		{
			name:    "capsule_bad_fs_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --capsule%s", "tests/native/fixtures/capsule_bad_fs.oren", target, arch, targetsOutPath(target, arch, "native", "capsule_bad_fs"), gcArg),
			log:     "build/logs/capsule_bad_fs.log",
			ok:      func(rc int) bool { return rc != 0 && rc != 124 },
			cleanup: []string{targetsOutPath(target, arch, "native", "capsule_bad_fs")},
		},
		{
			name:    "capsule_ok_fs_allow_compile",
			cmd:     fmt.Sprintf("./oren build %q --backend native --target %s --arch %s -o %q --capsule --cap-allow-domains FS%s", "tests/native/fixtures/capsule_ok_fs_allow.oren", target, arch, targetsOutPath(target, arch, "native", "capsule_ok_fs_allow"), gcArg),
			log:     "build/logs/capsule_ok_fs_allow.log",
			ok:      func(rc int) bool { return rc == 0 },
			cleanup: []string{targetsOutPath(target, arch, "native", "capsule_ok_fs_allow")},
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
			env             string
			expectExit      int
			expectSubstring string
			timeout         time.Duration
		}{
			{name: "remote_x64_run_tier1_smoke_print", src: "tests/fixtures/tier1_native_smoke_main.oren", expectSubstring: "tier1 smoke ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_atomics_print", src: "tests/fixtures/tier1_native_atomics_main.oren", expectSubstring: "tier1 atomics ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_typed_buffers_print", src: "tests/fixtures/tier1_native_typed_buffers_main.oren", expectSubstring: "tier1 typed buffers ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_forin_typed_buffers_print", src: "tests/fixtures/tier1_native_forin_typed_buffers_main.oren", expectSubstring: "tier1 forin typed buffers ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_lambda_varargs_print", src: "tests/fixtures/tier1_native_lambda_varargs_main.oren", expectSubstring: "tier1 lambda varargs ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_map_dynamic_keykind_print", src: "tests/fixtures/tier1_native_map_dynamic_keykind_main.oren", expectSubstring: "tier1 map dynamic keykind ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_map_get_dynamic_key_print", src: "tests/fixtures/tier1_native_map_get_dynamic_key_main.oren", expectSubstring: "tier1 map get dynamic key ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_string_ops_print", src: "tests/fixtures/tier1_native_string_ops_main.oren", expectSubstring: "tier1 string ops ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_float_ops_print", src: "tests/fixtures/tier1_native_float_ops_main.oren", expectSubstring: "tier1 float ops ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_globals_top_level_print", src: "tests/fixtures/tier1_native_globals_top_level_main.oren", expectSubstring: "tier1 globals top-level ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_no_main_top_level_only_print", src: "tests/fixtures/tier1_native_no_main_top_level_only.oren", expectSubstring: "tier1 no-main ok", timeout: 5 * time.Minute},
			{name: "remote_x64_run_tier1_abort_contract", src: "tests/fixtures/tier1_native_abort_contract_main.oren", expectExit: 1, timeout: 5 * time.Minute},
			// Validate runtime env override parity (x64 entry stubs):
			// - Without env, this fixture should return 0.
			// - With OREN_CALL_DEPTH_MAX=8, it should deterministically abort(1) via the call depth guard.
			{name: "remote_x64_run_call_depth_env_override", src: "tests/fixtures/tier1_native_call_depth_env_override_main.oren", env: "OREN_CALL_DEPTH_MAX=8", expectExit: 1, timeout: 5 * time.Minute},
		}

		for _, rf := range remoteX64 {
			workdir := filepath.Join("build", "tmp", "fixture_"+rf.name)
			cmd := ""
			if rf.expectSubstring != "" {
				if rf.env != "" {
					cmd = remoteX64RunPrintFixtureCmdEnv(workdir, rf.src, rf.expectSubstring, rf.env)
				} else {
					cmd = remoteX64RunPrintFixtureCmd(workdir, rf.src, rf.expectSubstring)
				}
			} else {
				if rf.env != "" {
					cmd = remoteX64RunExitcodeFixtureCmdEnv(workdir, rf.src, rf.expectExit, rf.env)
				} else {
					cmd = remoteX64RunExitcodeFixtureCmd(workdir, rf.src, rf.expectExit)
				}
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
