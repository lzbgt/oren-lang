package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

type remoteX64Test struct {
	name             string
	artifact         string
	src              string
	env              string // space-separated KEY=VALUE pairs (no quoting)
	args             string // space-separated args (Tier-1: no quoting)
	expectExit       int
	expectSubstrings []string
}

type remoteX64BatchOptions struct {
	host      string
	proxyArgs []string

	remoteUnixRoot string
	remoteWinRoot  string
	remoteWslRoot  string

	// If 0, a conservative default is chosen.
	buildJobs int
	// If true, run Win + WSL in parallel (single ssh session; remote concurrency).
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
	// many concurrent `./oren build` processes. Prefer low parallelism by default, but keep
	// enough concurrency to overlap the Linux+Windows cross-compiles.
	jobs := envInt("OREN_REMOTE_X64_BUILD_JOBS", 2)
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

	// Tier-1 remote gate is latency-sensitive; optimize for speed over compression ratio.
	gw, err := gzip.NewWriterLevel(f, gzip.BestSpeed)
	if err != nil {
		return err
	}
	// Determinism: gzip headers default to "now" which breaks cache keys.
	gw.Header.ModTime = time.Unix(0, 0)
	defer func() { _ = gw.Close() }()

	tw := tar.NewWriter(gw)
	defer func() { _ = tw.Close() }()

	type ent struct {
		abs string
		rel string
		inf os.FileInfo
	}
	ents := []ent{}

	if err := filepath.WalkDir(srcDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		rel, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		ents = append(ents, ent{abs: path, rel: rel, inf: info})
		return nil
	}); err != nil {
		return err
	}

	sort.Slice(ents, func(i, j int) bool { return ents[i].rel < ents[j].rel })
	for _, e := range ents {
		hdr := &tar.Header{
			Name:    e.rel,
			Mode:    int64(e.inf.Mode().Perm()),
			Size:    e.inf.Size(),
			ModTime: time.Unix(0, 0),
			Uid:     0,
			Gid:     0,
		}
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		in, err := os.Open(e.abs)
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(tw, in)
		_ = in.Close()
		if copyErr != nil {
			return copyErr
		}
	}
	return nil
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

func remoteX64BatchParseOutput(out string, tests []remoteX64Test, wantPlatforms []string) (bool, string) {
	// Validate markers and expectations.
	//
	// Expected format (from scripts):
	//   ::PLATFORM::<name>
	//   ::BEGIN::<testname>
	//   ... program output ...
	//   ::EXIT::<testname>::<rc>
	//
	// Note: when we run both Windows + WSL in a single remote batch, the output contains
	// two platform sections. We validate per-platform so each target remains a hard gate.
	want := map[string]bool{}
	for _, p := range wantPlatforms {
		p = strings.ToLower(strings.TrimSpace(p))
		if p == "" {
			continue
		}
		want[p] = true
	}

	sc := bufio.NewScanner(strings.NewReader(out))
	// Allow longer lines (stack traces).
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	type segment struct {
		body string
		rc   int
		ok   bool
	}
	// key: platform + "\x00" + testname
	seen := map[string]*segment{}

	curPlatform := ""
	curName := ""
	curSegPlatform := ""
	var curBuf strings.Builder

	flush := func(platform, name string, rc int) {
		key := platform + "\x00" + name
		seg := seen[key]
		if seg == nil {
			seg = &segment{}
			seen[key] = seg
		}
		seg.body = curBuf.String()
		seg.rc = rc
		seg.ok = true
		curBuf.Reset()
		curName = ""
		curSegPlatform = ""
	}

	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "::PLATFORM::") {
			curPlatform = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(line, "::PLATFORM::")))
			continue
		}
		if strings.HasPrefix(line, "::BEGIN::") {
			curName = strings.TrimPrefix(line, "::BEGIN::")
			curSegPlatform = curPlatform
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

			plat := curSegPlatform
			if plat == "" && len(want) == 1 {
				for k := range want {
					plat = k
					break
				}
			}
			flush(plat, nm, rc)
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

	// Determine which platforms to validate.
	required := []string{}
	if len(want) > 0 {
		for p := range want {
			required = append(required, p)
		}
		sort.Strings(required)
	} else {
		// Infer from output.
		plats := map[string]bool{}
		for k := range seen {
			parts := strings.SplitN(k, "\x00", 2)
			if len(parts) == 2 {
				plats[parts[0]] = true
			}
		}
		for p := range plats {
			if p == "" {
				continue
			}
			required = append(required, p)
		}
		sort.Strings(required)
		if len(required) == 0 {
			return false, "missing ::PLATFORM:: markers"
		}
	}

	for _, plat := range required {
		for _, t := range tests {
			key := plat + "\x00" + t.name
			seg := seen[key]
			if seg == nil || !seg.ok {
				return false, fmt.Sprintf("%s: missing markers for %s", plat, t.name)
			}
			expExit := t.expectExit
			if len(t.expectSubstrings) > 0 && t.expectExit == 0 {
				expExit = 0
			}
			if seg.rc != expExit {
				return false, fmt.Sprintf("%s/%s: exit=%d want=%d", plat, t.name, seg.rc, expExit)
			}
			for _, sub := range t.expectSubstrings {
				if sub == "" {
					continue
				}
				if !strings.Contains(seg.body, sub) {
					return false, fmt.Sprintf("%s/%s: missing substring %q", plat, t.name, sub)
				}
			}
		}
	}
	return true, ""
}

func remoteX64BatchParallelRunCmd(remoteWinDir, remoteWslDir string) string {
	// Run the Windows + WSL batches concurrently on the remote host, but keep
	// transport simple by using a single ssh session.
	//
	// Implementation strategy:
	// - invoke one `wsl.exe -e bash -lc ...` session
	// - inside WSL, start the Windows cmd batch via interop (cmd.exe) in the background
	// - run the WSL batch concurrently
	// - wait for both, then print concatenated outputs
	//
	// This avoids flakey concurrent ssh sessions over the proxy transport.
	winDir := strings.ReplaceAll(remoteWinDir, `\`, `/`)
	winCmd := fmt.Sprintf(`cmd.exe /v:on /c %s/run_win.cmd`, winDir)
	bash := fmt.Sprintf(
		`cd %s; rm -f out_win.txt out_wsl.txt; `+
			`(%s > out_win.txt 2>&1) & pid_win=$!; `+
			`(./run_wsl.sh > out_wsl.txt 2>&1) & pid_wsl=$!; `+
			`wait $pid_win; rc_win=$?; `+
			`wait $pid_wsl; rc_wsl=$?; `+
			`cat out_win.txt || true; cat out_wsl.txt || true; `+
			`exit 0`,
		remoteWslDir,
		winCmd,
	)
	return fmt.Sprintf(`wsl.exe -e bash -lc "%s"`, bash)
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

func remoteX64BatchBuildID() string {
	// A fast, deterministic invalidation key for reusing cached x64 cross-compile artifacts.
	//
	// Goals:
	// - avoid re-building on repeated remote runs when nothing changed
	// - never reuse artifacts across different git states or compiler rebuilds
	//
	// We intentionally avoid hashing full file contents here (can be huge); instead we hash:
	// - git HEAD (if available)
	// - list of modified files (staged+unstaged) with size+mtime
	// - ./oren binary size+mtime
	head := "nogit"
	if rc, out := remoteX64BatchExecCapture("", 2*time.Second, "git", "rev-parse", "HEAD"); rc == 0 {
		h := strings.TrimSpace(out)
		if h != "" {
			head = h
		}
	}

	changed := map[string]bool{}
	addChanged := func(args ...string) {
		rc, out := remoteX64BatchExecCapture("", 2*time.Second, "git", args...)
		if rc != 0 {
			return
		}
		for _, ln := range strings.Split(out, "\n") {
			ln = strings.TrimSpace(ln)
			if ln == "" {
				continue
			}
			changed[ln] = true
		}
	}
	addChanged("diff", "--name-only")
	addChanged("diff", "--name-only", "--cached")

	var lines []string
	lines = append(lines, "HEAD="+head)
	keys := make([]string, 0, len(changed))
	for k := range changed {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, p := range keys {
		st, err := os.Stat(p)
		if err != nil {
			lines = append(lines, "CHG "+p+" DEL")
			continue
		}
		lines = append(lines, fmt.Sprintf("CHG %s %d %d", p, st.Size(), st.ModTime().UnixNano()))
	}
	if st, err := os.Stat("./oren"); err == nil {
		lines = append(lines, fmt.Sprintf("OREN %d %d", st.Size(), st.ModTime().UnixNano()))
	}

	sum := sha256.Sum256([]byte(strings.Join(lines, "\n")))
	return head + ":" + hex.EncodeToString(sum[:])
}

func remoteX64BatchBuildIDPath(target string, artifact string) string {
	// Store sidecar build IDs next to the native artifacts.
	// Example:
	//   build/targets/x64-linux/native/tier1_native_smoke.orebuildid
	return targetsOutPath(target, "x64", "native", artifact+".orebuildid")
}

func remoteX64BatchShouldReuse(target string, artifact string, buildID string) bool {
	out := targetsOutPath(target, "x64", "native", artifact)
	if !remoteX64BatchFileNonEmpty(out) {
		return false
	}
	stamp := remoteX64BatchBuildIDPath(target, artifact)
	b, err := os.ReadFile(stamp)
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(b)) == buildID
}

func remoteX64BatchWriteBuildID(target string, artifact string, buildID string) {
	_ = os.WriteFile(remoteX64BatchBuildIDPath(target, artifact), []byte(buildID+"\n"), 0o644)
}

type remoteX64BuildTask struct {
	target    string // linux|windows
	artifact  string
	src       string
	outPath   string
	buildArgs []string
}

func remoteX64BatchBuildArtifacts(logPath string, workdir string, tests []remoteX64Test, jobs int, deadline time.Time) (string, error) {
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

	buildID := remoteX64BatchBuildID()

	timeLeft := func() time.Duration {
		d := time.Until(deadline)
		if d <= 0 {
			return 0
		}
		return d
	}
	if jobs < 1 {
		jobs = 1
	}
	if jobs > 8 {
		jobs = 8
	}

	tasks := []remoteX64BuildTask{}
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

		if !remoteX64BatchShouldReuse("linux", art, buildID) {
			tasks = append(tasks, remoteX64BuildTask{
				target:    "linux",
				artifact:  art,
				src:       src,
				outPath:   linuxBuilt,
				buildArgs: []string{"./oren", "build", src, "--backend", "native", "--platform", "x64-linux", "-o", linuxBuilt},
			})
		}
		if !remoteX64BatchShouldReuse("windows", art+".exe", buildID) {
			tasks = append(tasks, remoteX64BuildTask{
				target:    "windows",
				artifact:  art + ".exe",
				src:       src,
				outPath:   winBuilt,
				buildArgs: []string{"./oren", "build", src, "--backend", "native", "--platform", "x64-windows", "-o", winBuilt},
			})
		}
	}

	if len(tasks) > 0 {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] building %d x64 artifacts (jobs=%d)", len(tasks), jobs))
	}

	type taskRes struct {
		task remoteX64BuildTask
		rc   int
	}
	taskCh := make(chan remoteX64BuildTask, len(tasks))
	resCh := make(chan taskRes, len(tasks))
	for _, t := range tasks {
		taskCh <- t
	}
	close(taskCh)

	var wg sync.WaitGroup
	for i := 0; i < jobs; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for t := range taskCh {
				if timeLeft() <= 0 {
					resCh <- taskRes{task: t, rc: 2}
					continue
				}
				remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] build %s %s", t.target, t.artifact))
				rc, _ := remoteX64BatchExecCapture(logPath, timeLeft(), t.buildArgs[0], t.buildArgs[1:]...)
				resCh <- taskRes{task: t, rc: rc}
			}
		}()
	}
	wg.Wait()
	close(resCh)

	for r := range resCh {
		if r.rc != 0 {
			return "", fmt.Errorf("build failed: %s (%s)", r.task.artifact, r.task.target)
		}
	}

	// Record build IDs after successful builds so subsequent remote runs can reuse.
	for _, art := range keys {
		remoteX64BatchWriteBuildID("linux", art, buildID)
		remoteX64BatchWriteBuildID("windows", art+".exe", buildID)
	}

	// Copy into upload bundle.
	for _, art := range keys {
		linuxBuilt := targetsOutPath("linux", "x64", "native", art)
		winBuilt := targetsOutPath("windows", "x64", "native", art+".exe")
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

func remoteX64BatchSHA256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func remoteX64BatchRemoteHasBundle(logPath string, sshArgs []string, host string, remoteUnixDir string, wantSHA string, timeout time.Duration) bool {
	// Fast path: check if the remote directory already has the exact same bundle SHA.
	args := append([]string{}, sshArgs...)
	args = append(args, host, fmt.Sprintf(`cmd.exe /c "if exist %%USERPROFILE%%\\tmp_oren\\%s\\bundle.sha256 type %%USERPROFILE%%\\tmp_oren\\%s\\bundle.sha256"`, filepath.Base(remoteUnixDir), filepath.Base(remoteUnixDir)))
	rc, out := remoteX64BatchExecCapture(logPath, timeout, "ssh", args...)
	if rc != 0 {
		return false
	}
	return strings.Contains(out, wantSHA)
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

	bundleSHA, err := remoteX64BatchSHA256File(tarPath)
	if err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] sha256 failed: %v", err))
		return 2
	}
	remoteKey := "bundle_" + bundleSHA[:16]
	remoteUnixDir := opts.remoteUnixRoot + "/" + remoteKey
	remoteWinDir := opts.remoteWinRoot + `\` + remoteKey
	remoteWslDir := opts.remoteWslRoot + "/" + remoteKey

	sshArgs := remoteX64BatchSSHArgs(opts)
	scpArgs := remoteX64BatchSCPArgs(opts)

	// 1) Fast path: reuse remote bundle if already uploaded/extracted for this SHA.
	if !remoteX64BatchRemoteHasBundle(logPath, sshArgs, opts.host, remoteUnixDir, bundleSHA, 10*time.Second) {
		// Ensure remote directory exists (Windows cmd).
		ensureCmd := fmt.Sprintf(`cmd.exe /c "if not exist %%USERPROFILE%%\tmp_oren\%s mkdir %%USERPROFILE%%\tmp_oren\%s"`, remoteKey, remoteKey)
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

		// Upload bundle tarball (single scp).
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

		// Extract on remote via WSL tar (produces win/ linux/ scripts inside the run dir).
		//
		// The OpenSSH `/Users/...` path maps to `C:\Users\...\tmp_oren`, so the tarball is visible
		// inside WSL via `/mnt/c/...`.
		extractCmd := fmt.Sprintf(`wsl.exe -e bash -lc "set -e; mkdir -p %s; cd %s; tar -xzf bundle.tar.gz; chmod +x run_wsl.sh linux/* || true; printf '%s\n' > bundle.sha256"`, remoteWslDir, remoteWslDir, bundleSHA)
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
	} else {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] reuse remote bundle (sha=%s)", bundleSHA[:16]))
	}

	// 4) Run Windows + WSL scripts and validate outputs locally.
	runTimeout := timeLeft()
	if runTimeout <= 0 {
		remoteX64BatchAppendLog(logPath, "[remote_x64_batch] out of time before remote run")
		return 2
	}

	winRunCmd := fmt.Sprintf(`cmd.exe /v:on /c "%s\\run_win.cmd"`, remoteWinDir)
	wslRunCmd := fmt.Sprintf(`wsl.exe -e bash -lc "cd %s; ./run_wsl.sh"`, remoteWslDir)

	runKind := strings.ToLower(strings.TrimSpace(os.Getenv("OREN_REMOTE_X64_RUN_KIND")))
	wantWin := runKind == "" || runKind == "both" || runKind == "windows" || runKind == "win"
	wantWsl := runKind == "" || runKind == "both" || runKind == "wsl" || runKind == "linux"
	if !wantWin && !wantWsl {
		wantWin, wantWsl = true, true
	}

	wantPlatforms := []string{}
	if wantWin {
		wantPlatforms = append(wantPlatforms, "windows")
	}
	if wantWsl {
		wantPlatforms = append(wantPlatforms, "wsl")
	}

	runSSH := func(cmdString string) (int, string) {
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, cmdString)
		return remoteX64BatchRetry(logPath, runTimeout, 2, "ssh", args...)
	}

	var outAll strings.Builder
	if wantWin && wantWsl && opts.parallelRuns {
		bothCmd := remoteX64BatchParallelRunCmd(remoteWinDir, remoteWslDir)
		rc, out := runSSH(bothCmd)
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] remote both rc=%d", rc))
		if rc != 0 {
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] remote both run failed (rc=%d)", rc))
			return 2
		}
		outAll.WriteString(out)
	} else {
		if wantWin {
			rc, out := runSSH(winRunCmd)
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] windows rc=%d", rc))
			if rc != 0 {
				remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] windows run failed (rc=%d)", rc))
				return 2
			}
			outAll.WriteString(out)
			outAll.WriteString("\n")
		}
		if wantWsl {
			rc, out := runSSH(wslRunCmd)
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] wsl rc=%d", rc))
			if rc != 0 {
				remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] wsl run failed (rc=%d)", rc))
				return 2
			}
			outAll.WriteString(out)
			outAll.WriteString("\n")
		}
	}

	ok, msg := remoteX64BatchParseOutput(outAll.String(), tests, wantPlatforms)
	if !ok {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] output validation failed: %s", msg))
		return 2
	}
	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[remote_x64_batch] ok (dur=%s)", time.Since(start)))
	// Cleanup on success: keep tmp artifacts only when something fails.
	_ = os.RemoveAll(workdir)
	return 0
}

func remoteX64BatchFixture(tests []remoteX64Test) fixtureCase {
	// Keep a single log so failures contain everything needed to debug.
	logPath := "build/logs/fixture_remote_x64_batch.log"
	timeoutSecs := envInt("OREN_REMOTE_TIER1_TIMEOUT_SECS", 180)
	if timeoutSecs < 1 {
		timeoutSecs = 180
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
