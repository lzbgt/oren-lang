package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

type shellPrefix struct {
	argv0 string
	args  []string // includes argv0
}

func fileExistsAndExecutable(path string) bool {
	if path == "" {
		return false
	}
	st, err := os.Stat(path)
	if err != nil || st.IsDir() {
		return false
	}
	// Best-effort executable bit check on POSIX. On Windows this is meaningless.
	if runtime.GOOS == "windows" {
		return true
	}
	return st.Mode()&0o111 != 0
}

func detectShellPrefix() (shellPrefix, bool) {
	// `oretest` historically ran commands via `sh -c` to support env prefixes and simple chaining.
	// In minimal/container environments, `/bin/sh` may not exist.
	//
	// Deterministic shell discovery:
	// 1) ORETEST_SHELL (absolute path preferred; if set but invalid -> fail)
	// 2) SHELL (if absolute and executable)
	// 3) common absolute shells
	// 4) PATH search for sh/bash
	//
	// Note: we intentionally do NOT try to parse arbitrary user-provided shell+args;
	// ORETEST_SHELL must point to an executable that supports `-c <cmd>`.
	if v := os.Getenv("ORETEST_SHELL"); v != "" {
		// Treat any non-empty override as authoritative to avoid silently executing a different shell.
		if filepath.IsAbs(v) && fileExistsAndExecutable(v) {
			return shellPrefix{argv0: v, args: []string{v, "-c"}}, true
		}
		// Allow PATH-based override as a convenience (e.g. busybox-provided sh in PATH).
		if p, err := exec.LookPath(v); err == nil {
			return shellPrefix{argv0: p, args: []string{p, "-c"}}, true
		}
		return shellPrefix{}, false
	}

	if v := os.Getenv("SHELL"); v != "" {
		if filepath.IsAbs(v) && fileExistsAndExecutable(v) {
			return shellPrefix{argv0: v, args: []string{v, "-c"}}, true
		}
	}

	for _, p := range []string{"/bin/sh", "/usr/bin/sh", "/bin/bash", "/usr/bin/bash"} {
		if fileExistsAndExecutable(p) {
			return shellPrefix{argv0: p, args: []string{p, "-c"}}, true
		}
	}

	for _, name := range []string{"sh", "bash"} {
		if p, err := exec.LookPath(name); err == nil {
			return shellPrefix{argv0: p, args: []string{p, "-c"}}, true
		}
	}

	return shellPrefix{}, false
}

func runWithTimeout(timeoutBin string, d time.Duration, cmd string, logPath string) int {
	_ = os.MkdirAll(filepath.Dir(logPath), 0o755)
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()

	// Write logs directly to file to avoid buffering + pipe-copy deadlocks.
	//
	// If a command spawns a detached background process that inherits stdout/stderr,
	// capturing output via an in-memory buffer can hang forever waiting for EOF.
	f, err := os.Create(logPath)
	if err != nil {
		return 1
	}
	defer f.Close()
	_, _ = fmt.Fprintf(f, "[cmd] %s\n", cmd)

	// Keep behavior aligned with Makefile: enforce timeouts everywhere.
	// Important: run the actual command via `sh -c` so call sites can use shell syntax
	// (env vars, quoting, etc.) safely.
	//
	// Important: `exec.CommandContext` does not reliably kill child processes.
	// We always run each test in its own process group, and on timeout we kill the group.
	var c *exec.Cmd
	sh, ok := detectShellPrefix()
	if !ok {
		_, _ = f.WriteString("oretest: no POSIX shell found; set ORETEST_SHELL to an executable that supports `-c`\n")
		return 1
	}

	if timeoutBin != "" {
		// Keep using GNU timeout if available for parity with Makefile behavior, but
		// still rely on our internal process-group kill as the ultimate backstop.
		args := []string{"-k", "2", fmt.Sprintf("%d", int(d.Seconds()))}
		args = append(args, sh.args...)
		args = append(args, cmd)
		c = exec.CommandContext(ctx, timeoutBin, args...)
	} else {
		args := append(sh.args, cmd)
		c = exec.CommandContext(ctx, sh.argv0, args[1:]...)
	}
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	c.Stdout = f
	c.Stderr = f

	runErr := c.Start()
	if runErr != nil {
		_, _ = fmt.Fprintf(f, "oretest: start failed: %v\n", runErr)
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
