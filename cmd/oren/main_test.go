package main

import "testing"

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
