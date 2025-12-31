package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"
)

type remoteX64Test struct {
	name            string
	artifact        string
	src             string
	env             string // space-separated KEY=VALUE pairs (no quoting)
	args            string // space-separated args (Tier-1: no quoting)
	expectExit      int
	expectSubstring string
}

type remoteX64BatchOptions struct {
	host      string
	proxyArgs []string

	remoteUnixRoot string
	remoteWinRoot  string
	remoteWslRoot  string

	// If 0, a conservative default is chosen.
	buildJobs int
	// If true, run Win + WSL in parallel (2 ssh sessions).
	parallelRuns bool
}

func remoteX64ProxyArgsExec() []string {
	// `remoteX64ProxyArg()` is historically a shell-escaped fragment to embed in `sh -c` commands
	// (it uses backslash-escaped spaces).
	//
	// For exec.Command we need a real argv slice. Keep this parsing intentionally simple for
	// the default proxy arg format.
	s := remoteX64ProxyArg()
	if s == "" {
		return nil
	}
	// Convert `\ ` back to literal space, preserving the ProxyCommand as a single `-o` value.
	s = strings.ReplaceAll(s, `\ `, " ")
	// Best-effort unescape of `\\` (common when users export env vars with extra escaping).
	s = strings.ReplaceAll(s, `\\`, `\`)
	s = strings.TrimSpace(s)

	// Default format is:
	//   -o ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002
	//
	// For exec.Command we must pass:
	//   []string{"-o", "ProxyCommand=socat - PROXY:..."}
	if strings.HasPrefix(s, "-o ") {
		rest := strings.TrimSpace(strings.TrimPrefix(s, "-o "))
		if rest != "" {
			return []string{"-o", rest}
		}
	}
	// Best-effort fallback (may break ProxyCommand if it contains spaces).
	return strings.Fields(s)
}

func remoteX64BatchDefaultOptions() remoteX64BatchOptions {
	// Building x64-native fixtures is CPU-heavy and the stage1 compiler is not tuned for
	// many concurrent `./oren build` processes. Prefer low parallelism by default.
	jobs := envInt("OREN_REMOTE_X64_BUILD_JOBS", 1)
	if jobs < 1 {
		jobs = 1
	}
	if jobs > runtime.NumCPU() {
		jobs = runtime.NumCPU()
	}
	if jobs > 8 {
		jobs = 8
	}
	return remoteX64BatchOptions{
		host:           remoteX64Host(),
		proxyArgs:      remoteX64ProxyArgsExec(),
		remoteUnixRoot: remoteX64RemoteUnixRoot(),
		remoteWinRoot:  remoteX64RemoteWinRoot(),
		remoteWslRoot:  remoteX64RemoteWslRoot(),
		buildJobs:      jobs,
		parallelRuns:   true,
	}
}

func remoteX64BatchRunID() (string, error) {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return fmt.Sprintf("batch_%d_%s", time.Now().Unix(), hex.EncodeToString(b[:])), nil
}

func remoteX64BatchSplitEnv(env string) []string {
	return remoteX64SplitEnvAssignments(env)
}

func remoteX64BatchWriteWinScript(path string, tests []remoteX64Test) error {
	// Script prints machine-readable markers so the local runner can parse + validate results.
	var b strings.Builder
	b.WriteString("@echo off\r\n")
	b.WriteString("setlocal EnableDelayedExpansion\r\n")
	b.WriteString("cd /d %~dp0\r\n")
	b.WriteString("set FAILED=0\r\n")
	b.WriteString("echo ::PLATFORM::windows\r\n")
	for _, t := range tests {
		art := t.artifact
		if art == "" {
			art = t.name
		}
		// Reset env each test so one case can't affect another.
		b.WriteString("set OREN_CALL_DEPTH_MAX=\r\n")
		b.WriteString("set OREN_ENABLE_SIMD=\r\n")
		b.WriteString("set OREN_SYSTEM_SHELL=\r\n")
		for _, kv := range remoteX64BatchSplitEnv(t.env) {
			b.WriteString("set ")
			b.WriteString(kv)
			b.WriteString("\r\n")
		}
		b.WriteString("echo ::BEGIN::")
		b.WriteString(t.name)
		b.WriteString("\r\n")
		// Run the program and stream output to stdout (captured by ssh).
		b.WriteString("win\\")
		b.WriteString(art)
		b.WriteString(".exe")
		if strings.TrimSpace(t.args) != "" {
			b.WriteString(" ")
			b.WriteString(t.args)
		}
		b.WriteString("\r\n")
		b.WriteString("set RC=!ERRORLEVEL!\r\n")
		b.WriteString("echo ::EXIT::")
		b.WriteString(t.name)
		b.WriteString("::!RC!\r\n")
	}
	b.WriteString("exit /b %FAILED%\r\n")
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

func remoteX64BatchWriteWslScript(path string, tests []remoteX64Test) error {
	var b strings.Builder
	b.WriteString("#!/usr/bin/env bash\n")
	b.WriteString("set -euo pipefail\n")
	b.WriteString("cd \"$(dirname \"$0\")\"\n")
	b.WriteString("echo ::PLATFORM::wsl\n")
	for _, t := range tests {
		art := t.artifact
		if art == "" {
			art = t.name
		}
		b.WriteString("unset OREN_CALL_DEPTH_MAX || true\n")
		b.WriteString("unset OREN_ENABLE_SIMD || true\n")
		b.WriteString("unset OREN_SYSTEM_SHELL || true\n")
		for _, kv := range remoteX64BatchSplitEnv(t.env) {
			parts := strings.SplitN(kv, "=", 2)
			if len(parts) != 2 {
				continue
			}
			k := parts[0]
			v := parts[1]
			// Tier-1: env values are numeric/simple; best-effort single-quote escaping.
			v = strings.ReplaceAll(v, `'`, `'\''`)
			b.WriteString("export ")
			b.WriteString(k)
			b.WriteString("='")
			b.WriteString(v)
			b.WriteString("'\n")
		}
		b.WriteString("echo ::BEGIN::")
		b.WriteString(t.name)
		b.WriteString("\n")
		// Run without `set -e` so we can capture non-zero exit codes for expected-failure fixtures.
		b.WriteString("set +e\n")
		b.WriteString("./linux/")
		b.WriteString(art)
		if strings.TrimSpace(t.args) != "" {
			b.WriteString(" ")
			b.WriteString(t.args)
		}
		b.WriteString("\n")
		b.WriteString("rc=$?\n")
		b.WriteString("set -e\n")
		b.WriteString("echo ::EXIT::")
		b.WriteString(t.name)
		b.WriteString("::$rc\n")
	}
	return os.WriteFile(path, []byte(b.String()), 0o755)
}

func remoteX64BatchTarGz(dst string, srcDir string) error {
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()

	gw := gzip.NewWriter(f)
	defer func() { _ = gw.Close() }()
	tw := tar.NewWriter(gw)
	defer func() { _ = tw.Close() }()

	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		hdr, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}
		hdr.Name = rel
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		in, err := os.Open(path)
		if err != nil {
			return err
		}
		defer func() { _ = in.Close() }()
		_, err = io.Copy(tw, in)
		return err
	})
}

func remoteX64BatchAppendLog(logPath string, s string) {
	_ = os.MkdirAll(filepath.Dir(logPath), 0o755)
	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	defer func() { _ = f.Close() }()
	_, _ = f.WriteString(s)
	if !strings.HasSuffix(s, "\n") {
		_, _ = f.WriteString("\n")
	}
}

func remoteX64BatchExecCapture(logPath string, timeout time.Duration, name string, args ...string) (int, string) {
	// Best-effort bounded exec with combined stdout/stderr.
	cmd := exec.Command(name, args...)
	if runtime.GOOS != "windows" {
		// Ensure timeouts can kill the entire process group (ssh/scp may spawn children).
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	}
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf

	done := make(chan error, 1)
	start := time.Now()
	if err := cmd.Start(); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[exec] start failed: %s %v: %v", name, args, err))
		return 127, buf.String()
	}
	go func() { done <- cmd.Wait() }()

	var err error
	if timeout > 0 {
		select {
		case err = <-done:
		case <-time.After(timeout):
			if cmd.Process != nil {
				if runtime.GOOS != "windows" {
					killProcessGroup(cmd.Process.Pid)
				} else {
					_ = cmd.Process.Kill()
				}
			}
			err = fmt.Errorf("timeout after %s", timeout)
		}
	} else {
		err = <-done
	}

	out := buf.String()
	rc := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			rc = ee.ExitCode()
		} else {
			rc = 124
		}
	}
	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[exec] %s %s (rc=%d, dur=%s)", name, strings.Join(args, " "), rc, time.Since(start)))
	if out != "" {
		remoteX64BatchAppendLog(logPath, out)
	}
	return rc, out
}

func remoteX64BatchRetry(logPath string, timeout time.Duration, tries int, name string, args ...string) (int, string) {
	if tries < 1 {
		tries = 1
	}
	var lastOut string
	var lastRC int
	for i := 0; i < tries; i++ {
		rc, out := remoteX64BatchExecCapture(logPath, timeout, name, args...)
		lastRC, lastOut = rc, out
		if rc == 0 {
			return rc, out
		}
		time.Sleep(1 * time.Second)
	}
	return lastRC, lastOut
}

func remoteX64BatchSSHArgs(opts remoteX64BatchOptions) []string {
	base := []string{
		"-o", "ConnectTimeout=15",
		"-o", "ServerAliveInterval=10",
		"-o", "ServerAliveCountMax=3",
	}
	base = append(base, opts.proxyArgs...)
	return base
}

func remoteX64BatchSCPArgs(opts remoteX64BatchOptions) []string {
	// scp uses ssh options too.
	base := []string{
		"-o", "ConnectTimeout=15",
		"-o", "ServerAliveInterval=10",
		"-o", "ServerAliveCountMax=3",
	}
	base = append(base, opts.proxyArgs...)
	return base
}

func remoteX64BatchParseOutput(out string, tests []remoteX64Test) (bool, string) {
	// Validate markers and expectations.
	//
	// Expected format (from scripts):
	//   ::PLATFORM::<name>
	//   ::BEGIN::<testname>
	//   ... program output ...
	//   ::EXIT::<testname>::<rc>
	sc := bufio.NewScanner(strings.NewReader(out))
	// Allow longer lines (stack traces).
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	type segment struct {
		body string
		rc   int
		ok   bool
	}
	seen := map[string]*segment{}

	curName := ""
	var curBuf strings.Builder

	flush := func(name string, rc int) {
		seg := seen[name]
		if seg == nil {
			seg = &segment{}
			seen[name] = seg
		}
		seg.body = curBuf.String()
		seg.rc = rc
		seg.ok = true
		curBuf.Reset()
		curName = ""
	}

	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "::BEGIN::") {
			curName = strings.TrimPrefix(line, "::BEGIN::")
			curBuf.Reset()
			continue
		}
		if strings.HasPrefix(line, "::EXIT::") {
			rest := strings.TrimPrefix(line, "::EXIT::")
			parts := strings.SplitN(rest, "::", 2)
			if len(parts) != 2 {
				return false, "malformed EXIT marker"
			}
			nm := parts[0]
			rcStr := parts[1]
			rc := 999999
			_, _ = fmt.Sscanf(rcStr, "%d", &rc)
			flush(nm, rc)
			continue
		}
		if curName != "" {
			curBuf.WriteString(line)
			curBuf.WriteString("\n")
		}
	}
	if err := sc.Err(); err != nil {
		return false, err.Error()
	}

	for _, t := range tests {
		seg := seen[t.name]
		if seg == nil || !seg.ok {
			return false, fmt.Sprintf("missing markers for %s", t.name)
		}
		expExit := t.expectExit
		if t.expectSubstring != "" {
			expExit = 0
		}
		if seg.rc != expExit {
			return false, fmt.Sprintf("%s: exit=%d want=%d", t.name, seg.rc, expExit)
		}
		if t.expectSubstring != "" && !strings.Contains(seg.body, t.expectSubstring) {
			return false, fmt.Sprintf("%s: missing substring %q", t.name, t.expectSubstring)
		}
	}
	return true, ""
}

func remoteX64BatchCopyFile(dst string, src string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer func() { _ = in.Close() }()

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()

	_, err = io.Copy(out, in)
	return err
}

func remoteX64BatchFileNonEmpty(path string) bool {
	st, err := os.Stat(path)
	if err != nil {
		return false
	}
	return st.Mode().IsRegular() && st.Size() > 0
}

func remoteX64BatchBuildArtifacts(logPath string, workdir string, tests []remoteX64Test, jobs int, deadline time.Time) (string, error) {
	_ = jobs
	// Produce:
	//   workdir/
	//     bundle/
	//       win/<name>.exe
	//       linux/<name>
	//       run_win.cmd
	//       run_wsl.sh
	//     bundle.tar.gz
	bundleDir := filepath.Join(workdir, "bundle")
	winDir := filepath.Join(bundleDir, "win")
	linuxDir := filepath.Join(bundleDir, "linux")
	if err := os.MkdirAll(winDir, 0o755); err != nil {
		return "", err
	}
	if err := os.MkdirAll(linuxDir, 0o755); err != nil {
		return "", err
	}

	// Build (or reuse) artifacts deterministically.
	//
	// Key property for speed:
	// - If `build/targets/x64-{linux,windows}/native/<artifact>` already exists, reuse it.
	// - Otherwise, build into that canonical path, then copy into the upload bundle.
	//
	// This makes `OREN_REMOTE_RUN=1 make test` fast when the local x64 smoke build fixture ran first.
	seen := map[string]string{} // artifact -> src (must be consistent)
	keys := []string{}
	for _, t := range tests {
		art := t.artifact
		if art == "" {
			art = t.name
		}
		if prev, ok := seen[art]; ok && prev != t.src {
			return "", fmt.Errorf("remote x64 batch: artifact %q has multiple sources (%q vs %q)", art, prev, t.src)
		}
		if _, ok := seen[art]; !ok {
			keys = append(keys, art)
		}
		seen[art] = t.src
	}
	// Stable order so logs are deterministic.
	sort.Strings(keys)

	timeLeft := func() time.Duration {
		d := time.Until(deadline)
		if d <= 0 {
			return 0
		}
		return d
	}
	for _, art := range keys {
		src := seen[art]
		linuxBuilt := targetsOutPath("linux", "x64", "native", art)
		winBuilt := targetsOutPath("windows", "x64", "native", art+".exe")
		if err := os.MkdirAll(filepath.Dir(linuxBuilt), 0o755); err != nil {
			return "", err
		}
		if err := os.MkdirAll(filepath.Dir(winBuilt), 0o755); err != nil {
			return "", err
		}

		if !remoteX64BatchFileNonEmpty(linuxBuilt) {
			if timeLeft() <= 0 {
				return "", fmt.Errorf("remote x64 batch: out of time while building linux artifact %q", art)
			}
			args := []string{"./oren", "build", src, "--backend", "native", "--target", "linux", "--arch", "x64", "-o", linuxBuilt}
			rc, _ := remoteX64BatchExecCapture(logPath, timeLeft(), args[0], args[1:]...)
			if rc != 0 {
				return "", fmt.Errorf("build failed: %s (linux)", art)
			}
		}
		if !remoteX64BatchFileNonEmpty(winBuilt) {
			if timeLeft() <= 0 {
				return "", fmt.Errorf("remote x64 batch: out of time while building windows artifact %q", art)
			}
			args := []string{"./oren", "build", src, "--backend", "native", "--target", "windows", "--arch", "x64", "-o", winBuilt}
			rc, _ := remoteX64BatchExecCapture(logPath, timeLeft(), args[0], args[1:]...)
			if rc != 0 {
				return "", fmt.Errorf("build failed: %s (windows)", art)
			}
		}

		if err := remoteX64BatchCopyFile(filepath.Join(linuxDir, art), linuxBuilt); err != nil {
			return "", err
		}
		if err := remoteX64BatchCopyFile(filepath.Join(winDir, art+".exe"), winBuilt); err != nil {
			return "", err
		}
	}

	if err := remoteX64BatchWriteWinScript(filepath.Join(bundleDir, "run_win.cmd"), tests); err != nil {
		return "", err
	}
	if err := remoteX64BatchWriteWslScript(filepath.Join(bundleDir, "run_wsl.sh"), tests); err != nil {
		return "", err
	}

	tarPath := filepath.Join(workdir, "bundle.tar.gz")
	if err := remoteX64BatchTarGz(tarPath, bundleDir); err != nil {
		return "", err
	}
	return tarPath, nil
}

func remoteX64BatchFixtureRunner(timeoutBin string, timeout time.Duration, logPath string, tests []remoteX64Test) int {
	start := time.Now()
	opts := remoteX64BatchDefaultOptions()
	// Start fresh per invocation; long-lived appended logs make failures hard to read.
	_ = os.Remove(logPath)

	if timeout <= 0 {
		timeout = 60 * time.Second
	}
	deadline := time.Now().Add(timeout)
	timeLeft := func() time.Duration {
		d := time.Until(deadline)
		if d < 0 {
			return 0
		}
		return d
	}

	runID, err := remoteX64BatchRunID()
	if err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("remote_x64_batch: run id error: %v", err))
		return 2
	}

	workdir := filepath.Join("build", "tmp", "fixture_remote_x64_batch_"+runID)
	if err := os.RemoveAll(workdir); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("remote_x64_batch: failed to clean workdir: %v", err))
		return 2
	}
	if err := os.MkdirAll(workdir, 0o755); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("remote_x64_batch: failed to mkdir workdir: %v", err))
		return 2
	}

	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] start (run_id=%s)", runID))

	tarPath, err := remoteX64BatchBuildArtifacts(logPath, workdir, tests, opts.buildJobs, deadline)
	if err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] build failed: %v", err))
		return 2
	}

	remoteUnixDir := opts.remoteUnixRoot + "/" + runID
	remoteWinDir := opts.remoteWinRoot + `\` + runID
	remoteWslDir := opts.remoteWslRoot + "/" + runID

	sshArgs := remoteX64BatchSSHArgs(opts)
	scpArgs := remoteX64BatchSCPArgs(opts)

	// 1) Ensure remote directory exists (Windows cmd).
	ensureCmd := fmt.Sprintf(`cmd.exe /c "if not exist %%USERPROFILE%%\tmp_oren\%s mkdir %%USERPROFILE%%\tmp_oren\%s"`, runID, runID)
	{
		if timeLeft() <= 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] out of time before ensure dir")
			return 2
		}
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, ensureCmd)
		rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "ssh", args...)
		if rc != 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] ensure dir failed")
			return 2
		}
	}

	// 2) Upload bundle tarball (single scp).
	remoteTar := remoteUnixDir + "/bundle.tar.gz"
	{
		if timeLeft() <= 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] out of time before scp upload")
			return 2
		}
		args := append([]string{}, scpArgs...)
		args = append(args, tarPath, fmt.Sprintf("%s:%s", opts.host, remoteTar))
		rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "scp", args...)
		if rc != 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] scp failed")
			return 2
		}
	}

	// 3) Extract on remote via WSL tar (produces win/ linux/ scripts inside the run dir).
	//
	// The OpenSSH `/Users/...` path maps to `C:\Users\...\tmp_oren`, so the tarball is visible
	// inside WSL via `/mnt/c/...`.
	extractCmd := fmt.Sprintf(`wsl.exe -e bash -lc "set -e; mkdir -p %s; cd %s; tar -xzf bundle.tar.gz; chmod +x run_wsl.sh linux/* || true"`, remoteWslDir, remoteWslDir)
	{
		if timeLeft() <= 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] out of time before extract")
			return 2
		}
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, extractCmd)
		rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "ssh", args...)
		if rc != 0 {
			remoteX64BatchAppendLog(logPath, "[remote_x64_batch] extract failed")
			return 2
		}
	}

	// 4) Run Windows + WSL scripts (optionally in parallel) and validate outputs locally.
	type runOut struct {
		kind string
		rc   int
		out  string
	}
	runTimeout := timeLeft()
	if runTimeout <= 0 {
		remoteX64BatchAppendLog(logPath, "[remote_x64_batch] out of time before remote run")
		return 2
	}

	winRunCmd := fmt.Sprintf(`cmd.exe /v:on /c "%s\run_win.cmd"`, remoteWinDir)
	wslRunCmd := fmt.Sprintf(`wsl.exe -e bash -lc "cd %s; ./run_wsl.sh"`, remoteWslDir)

	runOne := func(kind string, cmdString string) runOut {
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, cmdString)
		rc, out := remoteX64BatchRetry(logPath, runTimeout, 2, "ssh", args...)
		return runOut{kind: kind, rc: rc, out: out}
	}

	var outs []runOut
	if opts.parallelRuns {
		ch := make(chan runOut, 2)
		go func() { ch <- runOne("windows", winRunCmd) }()
		go func() { ch <- runOne("wsl", wslRunCmd) }()
		outs = append(outs, <-ch, <-ch)
	} else {
		outs = append(outs, runOne("windows", winRunCmd))
		outs = append(outs, runOne("wsl", wslRunCmd))
	}

	for _, ro := range outs {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] %s rc=%d", ro.kind, ro.rc))
		if ro.rc != 0 {
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] %s run failed (rc=%d)", ro.kind, ro.rc))
			return 2
		}
		ok, msg := remoteX64BatchParseOutput(ro.out, tests)
		if !ok {
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] %s output validation failed: %s", ro.kind, msg))
			return 2
		}
	}

	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] ok (dur=%s)", time.Since(start)))
	// Cleanup on success: keep tmp artifacts only when something fails.
	_ = os.RemoveAll(workdir)
	return 0
}

func remoteX64BatchFixture(tests []remoteX64Test) fixtureCase {
	// Keep a single log so failures contain everything needed to debug.
	logPath := "build/logs/fixture_remote_x64_batch.log"
	timeoutSecs := envInt("OREN_REMOTE_TIER1_TIMEOUT_SECS", 60)
	if timeoutSecs < 1 {
		timeoutSecs = 60
	}
	return fixtureCase{
		name:    "remote_x64_batch",
		timeout: time.Duration(timeoutSecs) * time.Second,
		log:     logPath,
		ok:      func(rc int) bool { return rc == 0 },
		run: func(timeoutBin string, timeout time.Duration, logPath string) int {
			// Use the fixture-provided timeout (if non-zero) as the outer budget.
			// Per-command timeouts are derived internally.
			_ = timeoutBin
			return remoteX64BatchFixtureRunner(timeoutBin, timeout, logPath, tests)
		},
		// Keep remote artifacts (and local build/tmp workdir) on failure for debugging.
		cleanup: []string{},
	}
}
