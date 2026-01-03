package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

func fileSHA256Hex(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return fmt.Sprintf("%x", sum[:]), nil
}

func stdlibModernizationAudit() error {
	// Rolling guardrails: keep stdlib usage modern and layered.
	//
	// Enforced today:
	// - No direct `oren_list_*` calls outside `lib/std/list.oren` (stdlib should use `std:list`).
	// - No legacy `string_concat(...)` usage inside `lib/std/**` (prefer `+`).
	allowOrenListCalls := map[string]bool{
		filepath.Clean("lib/std/list.oren"): true,
	}
	denySubstrings := []string{
		"string_concat(",
	}

	var violations []string
	root := filepath.Clean("lib/std")
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if filepath.Ext(path) != ".oren" {
			return nil
		}

		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rel := filepath.Clean(path)
		lines := bytes.Split(b, []byte("\n"))
		for i, line := range lines {
			ln := i + 1
			s := string(line)
			if strings.Contains(s, "oren_list_") && !allowOrenListCalls[rel] {
				violations = append(violations, fmt.Sprintf("%s:%d: stdlib must not call oren_list_* directly (use std:list)", rel, ln))
			}
			for _, bad := range denySubstrings {
				if strings.Contains(s, bad) {
					violations = append(violations, fmt.Sprintf("%s:%d: stdlib must not use %q (prefer modern syntax)", rel, ln, bad))
				}
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	if len(violations) > 0 {
		var b strings.Builder
		b.WriteString("stdlib modernization audit failed:\n")
		for _, v := range violations {
			b.WriteString("  - ")
			b.WriteString(v)
			b.WriteString("\n")
		}
		b.WriteString("fix: route list ops through `lib/std/list.oren` and prefer `+` over `string_concat`.\n")
		return fmt.Errorf("%s", b.String())
	}
	return nil
}

const remoteX64HostDefault = "lzbgt@pc.work"

// Use backslash-escaped spaces so this can be embedded safely into `sh -c` commands without
// nested-quote footguns.
const remoteX64ProxyArgDefault = "-o ProxyCommand=socat\\ -\\ PROXY:hubstack.cn:%h:%p,proxyport=6002"

const remoteX64RemoteUnixRootDefault = "/Users/lzbgt/tmp_oren"
const remoteX64RemoteWinRootDefault = `C:\Users\lzbgt\tmp_oren`
const remoteX64RemoteWslRootDefault = "/mnt/c/Users/lzbgt/tmp_oren"

func remoteX64Host() string {
	if v := os.Getenv("OREN_REMOTE_X64_HOST"); v != "" {
		return v
	}
	return remoteX64HostDefault
}

func remoteX64ProxyArg() string {
	// This is intentionally low-level: callers pass an ssh/scp arg fragment, already escaped
	// for embedding in a shell command string.
	//
	// Examples:
	//   export OREN_REMOTE_X64_PROXY_ARG='-o ProxyCommand=socat\\ -\\ PROXY:hubstack.cn:%h:%p,proxyport=6002'
	//   export OREN_REMOTE_X64_PROXY_ARG=''   # no proxy
	if v := os.Getenv("OREN_REMOTE_X64_PROXY_ARG"); v != "" {
		return v
	}
	// Allow explicit empty to disable proxy.
	if _, ok := os.LookupEnv("OREN_REMOTE_X64_PROXY_ARG"); ok {
		return ""
	}
	return remoteX64ProxyArgDefault
}

func remoteX64RemoteUnixRoot() string {
	if v := os.Getenv("OREN_REMOTE_X64_UNIX_ROOT"); v != "" {
		return v
	}
	return remoteX64RemoteUnixRootDefault
}

func remoteX64RemoteWinRoot() string {
	if v := os.Getenv("OREN_REMOTE_X64_WIN_ROOT"); v != "" {
		return v
	}
	return remoteX64RemoteWinRootDefault
}

func remoteX64RemoteWslRoot() string {
	if v := os.Getenv("OREN_REMOTE_X64_WSL_ROOT"); v != "" {
		return v
	}
	return remoteX64RemoteWslRootDefault
}

func remoteX64SplitEnvAssignments(env string) []string {
	// env is a space-separated list of KEY=VALUE pairs (no quoting).
	// Keep this intentionally simple for Tier‑1 remote gates.
	env = strings.TrimSpace(env)
	if env == "" {
		return nil
	}
	parts := strings.Fields(env)
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if strings.Contains(p, "=") {
			out = append(out, p)
		}
	}
	return out
}

func runSelfHostingGate(timeoutBin, gcArg string, buildTimeout time.Duration) error {
	// Rolling stability gate:
	// - Stage1 (./oren) builds Stage2 (a fresh ./oren_stage2)
	// - Stage1 and Stage2 must agree on deterministic dumps of the compiler source
	//
	// This catches "bootstrap breaks itself" regressions early.
	if os.Getenv("OREN_SKIP_SELFHOST") != "" {
		return nil
	}

	workdir := filepath.Join("build", "selfhost")
	_ = os.MkdirAll(workdir, 0o755)

	stage2Obc := filepath.Join(workdir, "oren_stage2.obc")
	stage1Graph := filepath.Join(workdir, "stage1.graph.json")
	stage2Graph := filepath.Join(workdir, "stage2.graph.json")
	stage1Meta := filepath.Join(workdir, "stage1.meta.json")
	stage2Meta := filepath.Join(workdir, "stage2.meta.json")

	logBuildObc := filepath.Join("build", "logs", "selfhost_build_stage2_obc.log")
	logG1 := filepath.Join("build", "logs", "selfhost_stage1_dump_graph.log")
	logG2 := filepath.Join("build", "logs", "selfhost_stage2_dump_graph.log")
	logM1 := filepath.Join("build", "logs", "selfhost_stage1_meta.log")
	logM2 := filepath.Join("build", "logs", "selfhost_stage2_meta.log")

	// Self-hosting builds can be slower than ordinary test compilation, especially on
	// cold caches or when the host toolchain is busy. Keep it bounded but generous.
	selfHostTimeout := buildTimeout
	if selfHostTimeout < 300*time.Second {
		selfHostTimeout = 300 * time.Second
	}

	// Self-hosting build strategy (rolling, pragmatic):
	//
	// - Building a full Stage2 native binary currently depends on a much larger native-runtime surface
	//   (syscall-first file I/O, float parsing, etc.) which is still evolving.
	// - Building a full Stage2 C backend binary can be extremely memory hungry (clang compiling a
	//   giant single-TU generated C file), and may be SIGKILL/OOM on developer machines.
	//
	// Therefore this gate uses the bytecode backend + AVM to validate self-hosting deterministically:
	// Stage1 emits Stage2 compiler as `.obc`, then AVM runs Stage2 to reproduce Stage1 outputs.
	buildObc := fmt.Sprintf("./oren build oren.oren --backend bytecode -o %q%s", stage2Obc, gcArg)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, buildObc, logBuildObc); rc != 0 {
		return fmt.Errorf("self-host gate: failed to build stage2 .obc (rc=%d), see %s", rc, logBuildObc)
	}

	// Dump module graph from Stage1 and Stage2 and require byte-for-byte match.
	g1 := fmt.Sprintf("./oren dump graph oren.oren --out %q", stage1Graph)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, g1, logG1); rc != 0 {
		return fmt.Errorf("self-host gate: stage1 dump graph failed (rc=%d), see %s", rc, logG1)
	}
	// Run Stage2 under AVM with a narrow FS allowlist:
	// - read: `oren.oren` + `lib/**`
	// - write: `build/**`
	//
	// Note: AVM passes args after `--`.
	fsAllow := "build/,lib/,oren.oren"
	// Important: the compiler strips argv[0] as the program name. AVM passes only args-after-`--`
	// (no implicit argv0), so we inject a dummy argv0 ("oren") here.
	g2 := fmt.Sprintf("./avm --fs-allow-prefixes %q %q -- oren dump graph oren.oren --out %q", fsAllow, stage2Obc, stage2Graph)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, g2, logG2); rc != 0 {
		return fmt.Errorf("self-host gate: stage2 (avm) dump graph failed (rc=%d), see %s", rc, logG2)
	}
	hg1, err := fileSHA256Hex(stage1Graph)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage1 graph: %w", err)
	}
	hg2, err := fileSHA256Hex(stage2Graph)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage2 graph: %w", err)
	}
	if hg1 != hg2 {
		return fmt.Errorf("self-host gate: module graph mismatch (stage1=%s stage2=%s); diff %s vs %s", hg1, hg2, stage1Graph, stage2Graph)
	}

	// Also compare metadata output (API surface) under --deterministic.
	m1 := fmt.Sprintf("./oren meta oren.oren --deterministic --out %q", stage1Meta)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, m1, logM1); rc != 0 {
		return fmt.Errorf("self-host gate: stage1 meta failed (rc=%d), see %s", rc, logM1)
	}
	m2 := fmt.Sprintf("./avm --fs-allow-prefixes %q %q -- oren meta oren.oren --deterministic --out %q", fsAllow, stage2Obc, stage2Meta)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, m2, logM2); rc != 0 {
		return fmt.Errorf("self-host gate: stage2 (avm) meta failed (rc=%d), see %s", rc, logM2)
	}
	hm1, err := fileSHA256Hex(stage1Meta)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage1 meta: %w", err)
	}
	hm2, err := fileSHA256Hex(stage2Meta)
	if err != nil {
		return fmt.Errorf("self-host gate: hash stage2 meta: %w", err)
	}
	if hm1 != hm2 {
		return fmt.Errorf("self-host gate: metadata mismatch (stage1=%s stage2=%s); diff %s vs %s", hm1, hm2, stage1Meta, stage2Meta)
	}

	return nil
}

func runNativeSelfHostingGate(timeoutBin, gcArg string, buildTimeout time.Duration, target, arch string) error {
	// Rolling stability gate (native backend):
	// - Stage1 (./oren) builds Stage2 as a native binary (Mach-O/ELF)
	// - Stage2 must be executable and responsive (basic smoke)
	//
	// This catches regressions in the syscall-first native runtime subset required to self-host.
	if os.Getenv("OREN_SKIP_SELFHOST_NATIVE") != "" {
		return nil
	}

	workdir := filepath.Join("build", "selfhost")
	_ = os.MkdirAll(workdir, 0o755)

	stage2Native := filepath.Join(workdir, "oren_stage2_native")

	logBuildNative := filepath.Join("build", "logs", "selfhost_build_stage2_native.log")
	logCodesign := filepath.Join("build", "logs", "selfhost_stage2_native_codesign.log")
	logHelp := filepath.Join("build", "logs", "selfhost_stage2_native_help.log")

	selfHostTimeout := buildTimeout
	// Native stage2 operations can be significantly slower than AVM, even for a small entry, because
	// the syscall-first native runtime currently has a larger constant-factor overhead (allocation,
	// hashing, map ops, etc). Keep this gate reliable by using a more generous floor.
	minTimeout := 600 * time.Second
	if selfHostTimeout < minTimeout {
		selfHostTimeout = minTimeout
	}

	// Build Stage2 native compiler (rolling):
	// - default: keep this gate fast and runnable (no-debug reduces symbol-table generation overhead)
	// - optional: enable deterministic mode if you want to exercise the hashing path too
	//
	// IMPORTANT: we still codesign explicitly below on macOS to ensure executability.
	deterministicArg := ""
	if os.Getenv("OREN_SELFHOST_NATIVE_DETERMINISTIC") == "1" {
		deterministicArg = " --deterministic"
	}

	// Match the repo stage2 stability knobs (also used by the Makefile stage2 build).
	// Keep this as an env prefix so it applies regardless of `--no-gc` flags.
	envPrefix := "OREN_GC_AUTO=1 OREN_GC_ALLOC_THRESHOLD=4000000 OREN_GC_RAW_PTR_SCAN=0 OREN_GC_STACK_SCAN_LIMIT_BYTES=8388608 "

	buildNative := fmt.Sprintf("%s./oren build oren.oren --backend native --platform %s --no-cache --no-debug%s -o %q%s",
		envPrefix, platformKey(target, arch), deterministicArg, stage2Native, gcArg)
	if rc := runWithTimeout(timeoutBin, selfHostTimeout, buildNative, logBuildNative); rc != 0 {
		return fmt.Errorf("native self-host gate: failed to build stage2 native (rc=%d), see %s", rc, logBuildNative)
	}

	// macOS: unsigned binaries may be killed at exec by Gatekeeper/AMFI policies even when built locally.
	// Use ad-hoc signing (`-s -`) so the stage2 native binary can be executed reliably in CI/dev.
	if runtime.GOOS == "darwin" {
		sign := fmt.Sprintf("codesign -s - -f %q", stage2Native)
		if rc := runWithTimeout(timeoutBin, selfHostTimeout, sign, logCodesign); rc != 0 {
			return fmt.Errorf("native self-host gate: failed to ad-hoc codesign stage2 native (rc=%d), see %s", rc, logCodesign)
		}
	}

	// Stage2 native must be executable and have a minimally correct syscall-first runtime surface.
	// Use `selftest-native` which is designed to be fast and avoids compiler pipelines.
	runTimeout := 60 * time.Second
	if runTimeout > selfHostTimeout {
		runTimeout = selfHostTimeout
	}
	selftest := fmt.Sprintf("%q selftest-native", stage2Native)
	if rc := runWithTimeout(timeoutBin, runTimeout, selftest, logHelp); rc != 0 {
		return fmt.Errorf("native self-host gate: stage2(native) selftest-native failed (rc=%d), see %s", rc, logHelp)
	}
	b, err := os.ReadFile(logHelp)
	if err == nil {
		if !bytes.Contains(b, []byte("selftest-native OK")) {
			return fmt.Errorf("native self-host gate: stage2(native) selftest-native output missing OK marker, see %s", logHelp)
		}
	}

	return nil
}

func hostNativeTarget() string {
	// Only return targets that the native backend supports on the current host OS.
	switch runtime.GOOS {
	case "darwin":
		// Rolling: native backend supports macOS only on arm64 today.
		if runtime.GOARCH == "arm64" {
			return "macos"
		}
		return ""
	case "linux":
		return "linux"
	case "windows":
		return "windows"
	default:
		return ""
	}
}

func hostNativeArch() string {
	// Return the native backend arch string for the current host arch, but only
	// for host OS combinations we actually support.
	switch runtime.GOARCH {
	case "arm64":
		return "arm64"
	case "amd64":
		// Rolling: x64 native backend targets linux+windows today (ELF+PE).
		if runtime.GOOS == "linux" || runtime.GOOS == "windows" {
			return "x64"
		}
		return ""
	default:
		return ""
	}
}
