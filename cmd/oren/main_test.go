package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestSplitPythonCmdEnv(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []string
	}{
		{"empty", "", nil},
		{"simple", "python3", []string{"python3"}},
		{"pyLauncher", "py -3", []string{"py", "-3"}},
		{"quotedExeOnly", "\"C:\\Path With Spaces\\python.exe\"", []string{"C:\\Path With Spaces\\python.exe"}},
		{"quotedExeArgs", "\"C:\\Path With Spaces\\python.exe\" -E -s", []string{"C:\\Path With Spaces\\python.exe", "-E", "-s"}},
		{"quotedExeArgsExtraSpace", "\"C:\\Path With Spaces\\python.exe\"    -E", []string{"C:\\Path With Spaces\\python.exe", "-E"}},
		{"posixQuoted", "\"/opt/py/bin/python\" -E", []string{"/opt/py/bin/python", "-E"}},
	}

	for _, tc := range cases {
		got := splitPythonCmdEnv(tc.in)
		if len(got) != len(tc.want) {
			t.Fatalf("%s: len=%d want=%d (got=%v)", tc.name, len(got), len(tc.want), got)
		}
		for i := range got {
			if got[i] != tc.want[i] {
				t.Fatalf("%s: idx %d got=%q want=%q", tc.name, i, got[i], tc.want[i])
			}
		}
	}
}

func TestDefaultTargetForHost(t *testing.T) {
	cases := []struct {
		goos string
		want string
	}{
		{goos: "darwin", want: "macos"},
		{goos: "linux", want: "linux"},
		{goos: "windows", want: "windows"},
		{goos: "plan9", want: "macos"},
	}

	for _, tc := range cases {
		if got := defaultTargetForHost(tc.goos); got != tc.want {
			t.Fatalf("goos=%q got=%q want=%q", tc.goos, got, tc.want)
		}
	}
}

func TestParseBuildOptionsDefaultsToHostTarget(t *testing.T) {
	t.Setenv("CC", "")
	t.Setenv("OREN_CODESIGN_ID", "")
	t.Setenv("OREN_NO_GC", "")
	t.Setenv("OREN_NOTARY_PROFILE", "")

	linuxCfg, rc, msg := parseBuildOptions("linux", "examples/hello.oren", nil)
	if rc != 0 || msg != "" {
		t.Fatalf("linux defaults unexpected rc=%d msg=%q", rc, msg)
	}
	if linuxCfg.target != "linux" {
		t.Fatalf("linux target got=%q want=linux", linuxCfg.target)
	}
	if linuxCfg.cc != "cc" {
		t.Fatalf("linux cc got=%q want=cc", linuxCfg.cc)
	}
	if linuxCfg.outFilename != "examples/hello" {
		t.Fatalf("linux out got=%q want=examples/hello", linuxCfg.outFilename)
	}

	windowsCfg, rc, msg := parseBuildOptions("windows", "examples/hello.oren", nil)
	if rc != 0 || msg != "" {
		t.Fatalf("windows defaults unexpected rc=%d msg=%q", rc, msg)
	}
	if windowsCfg.target != "windows" {
		t.Fatalf("windows target got=%q want=windows", windowsCfg.target)
	}
	if windowsCfg.cc != "cl.exe" {
		t.Fatalf("windows cc got=%q want=cl.exe", windowsCfg.cc)
	}
}

func TestParseBuildOptionsRejectsBadArgs(t *testing.T) {
	cases := []struct {
		name    string
		args    []string
		wantRC  int
		wantMsg string
	}{
		{name: "missingTargetValue", args: []string{"--target"}, wantRC: 2, wantMsg: "Missing value for --target"},
		{name: "missingOutputValue", args: []string{"-o"}, wantRC: 2, wantMsg: "Missing value for -o"},
		{name: "unknownArg", args: []string{"--backend", "native"}, wantRC: 2, wantMsg: "Unknown arg: --backend"},
	}

	for _, tc := range cases {
		_, rc, msg := parseBuildOptions("linux", "examples/hello.oren", tc.args)
		if rc != tc.wantRC {
			t.Fatalf("%s: rc=%d want=%d", tc.name, rc, tc.wantRC)
		}
		if msg != tc.wantMsg {
			t.Fatalf("%s: msg=%q want=%q", tc.name, msg, tc.wantMsg)
		}
	}
}

func TestRunCommandUsageAndFriendlyErrors(t *testing.T) {
	cases := []struct {
		name       string
		args       []string
		wantRC     int
		wantStdout string
		wantStderr string
	}{
		{
			name:       "runNeedsFile",
			args:       []string{"run"},
			wantRC:     2,
			wantStderr: "Usage: oren run <file.oren>",
		},
		{
			name:       "buildNeedsFile",
			args:       []string{"build"},
			wantRC:     2,
			wantStderr: "Usage: oren build <file.oren>",
		},
		{
			name:       "unknownCommand",
			args:       []string{"ship-it"},
			wantRC:     2,
			wantStderr: "Unknown command. Use 'oren run <file>', 'oren build <file>' or just run 'oren' for REPL.",
		},
		{
			name:       "buildMissingFileIsFriendly",
			args:       []string{"build", "tests/fixtures/does_not_exist.oren"},
			wantRC:     1,
			wantStderr: "ERROR: cannot read tests/fixtures/does_not_exist.oren:",
		},
		{
			name:       "runMissingFileIsFriendly",
			args:       []string{"run", "tests/fixtures/does_not_exist.oren"},
			wantRC:     1,
			wantStderr: "ERROR: cannot read tests/fixtures/does_not_exist.oren:",
		},
	}

	for _, tc := range cases {
		var stdout bytes.Buffer
		var stderr bytes.Buffer
		rc := runCommand("oren", tc.args, strings.NewReader(""), &stdout, &stderr)
		if rc != tc.wantRC {
			t.Fatalf("%s: rc=%d want=%d stderr=%q", tc.name, rc, tc.wantRC, stderr.String())
		}
		if tc.wantStdout != "" && !strings.Contains(stdout.String(), tc.wantStdout) {
			t.Fatalf("%s: stdout=%q missing %q", tc.name, stdout.String(), tc.wantStdout)
		}
		if tc.wantStderr != "" && !strings.Contains(stderr.String(), tc.wantStderr) {
			t.Fatalf("%s: stderr=%q missing %q", tc.name, stderr.String(), tc.wantStderr)
		}
	}
}
