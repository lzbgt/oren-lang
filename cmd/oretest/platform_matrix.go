package main

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"
)

type platformSpec struct {
	arch string
	os   string
}

func parsePlatformSpec(s string) (platformSpec, bool) {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return platformSpec{}, false
	}
	// Legacy: allow just the native backend target OS.
	if s == "macos" || s == "linux" {
		return platformSpec{arch: "", os: s}, true
	}
	parts := strings.Split(s, "-")
	if len(parts) != 2 {
		return platformSpec{}, false
	}
	arch := parts[0]
	osName := parts[1]
	switch arch {
	case "arm64", "x64":
	default:
		return platformSpec{}, false
	}
	switch osName {
	case "macos", "linux", "windows":
	default:
		return platformSpec{}, false
	}
	return platformSpec{arch: arch, os: osName}, true
}

// applyPlatformSpec mutates the current process behavior to run the requested platform, when
// possible. Some platforms are "external":
// - arm64-linux from macOS is executed via the persistent Docker container runner.
// - x64-{windows,linux} are executed via the remote x64 batch fixture (Win11 + WSL2).
//
// Return values:
// - didExit: if true, the caller must os.Exit(exitCode) and not continue.
// - nativeTarget: updated oretest --target value (macos|linux) for local execution.
func applyPlatformSpec(timeoutBin string, raw string, nativeTarget string, passThroughArgs []string) (didExit bool, exitCode int, newNativeTarget string) {
	newNativeTarget = nativeTarget

	if strings.TrimSpace(raw) == "" {
		return false, 0, newNativeTarget
	}
	ps, ok := parsePlatformSpec(raw)
	if !ok {
		fmt.Fprintf(os.Stderr, "ERROR: invalid --platform %q (expected: macos|linux|arm64-macos|arm64-linux|x64-windows|x64-linux)\n", raw)
		return true, 2, newNativeTarget
	}

	// Legacy form: just the native target OS.
	if ps.arch == "" {
		if ps.os != "macos" && ps.os != "linux" {
			fmt.Fprintf(os.Stderr, "ERROR: unsupported --platform %q\n", raw)
			return true, 2, newNativeTarget
		}
		newNativeTarget = ps.os
		return false, 0, newNativeTarget
	}

	hostArch := hostOrenArch()
	hostOS := runtime.GOOS

	// Local host execution (same arch).
	if ps.arch == hostArch {
		switch ps.os {
		case "macos":
			if hostOS != "darwin" {
				fmt.Fprintf(os.Stderr, "ERROR: --platform %q requires darwin host (or use the appropriate external runner)\n", raw)
				return true, 2, newNativeTarget
			}
			newNativeTarget = "macos"
			return false, 0, newNativeTarget
		case "linux":
			if hostOS == "linux" {
				newNativeTarget = "linux"
				return false, 0, newNativeTarget
			}
			// External runner on macOS: use the persistent linux/arm64 docker container.
			// Enforce the same 3-minute budget per invocation.
			logPath := "build/logs/matrix_arm64_linux_docker.log"
			cmd := "OREN_LINUX_DOCKER_RESTART=0 OREN_LINUX_DOCKER_ALLOW_DIRTY=1 tools/oretest_linux_docker.sh"
			rc := runWithTimeout(timeoutBin, 3*time.Minute, cmd, logPath)
			if rc != 0 {
				fmt.Fprintf(os.Stderr, "FAIL: linux/arm64 docker run failed (log: %s)\n", logPath)
				return true, rc, newNativeTarget
			}
			return true, 0, newNativeTarget
		case "windows":
			fmt.Fprintf(os.Stderr, "ERROR: --platform %q cannot run locally; use x64-windows via remote gate\n", raw)
			return true, 2, newNativeTarget
		}
	}

	// Remote x64 gate (Win11 + WSL2): treated as the canonical execution environment for x64.
	if ps.arch == "x64" {
		os.Setenv("OREN_REMOTE_RUN", "1")
		switch ps.os {
		case "windows":
			os.Setenv("OREN_REMOTE_X64_RUN_KIND", "windows")
		case "linux":
			// linux/x64 in this project is validated via WSL2 on the remote Win11 host.
			os.Setenv("OREN_REMOTE_X64_RUN_KIND", "wsl")
		default:
			// Should be impossible due to parse constraints.
		}
		// Keep the local/native suite disabled in remote-gate mode (unless user opted into *_ALL).
		// We do not exit; we let the normal oretest code path execute the remote fixture.
		return false, 0, newNativeTarget
	}

	fmt.Fprintf(os.Stderr, "ERROR: unsupported --platform %q on this host\n", raw)
	return true, 2, newNativeTarget
}

func runTier1Matrix(timeoutBin string, includeOBCPortability bool) int {
	// Each step must stay within the default 3-minute budget.
	stepTimeout := 3 * time.Minute

	steps := []struct {
		name string
		cmd  string
		log  string
	}{
		{
			name: "arm64-macos",
			cmd:  "make test",
			log:  "build/logs/matrix_arm64_macos.log",
		},
		{
			name: "arm64-linux(docker)",
			cmd:  "OREN_LINUX_DOCKER_RESTART=0 OREN_LINUX_DOCKER_ALLOW_DIRTY=1 tools/oretest_linux_docker.sh",
			log:  "build/logs/matrix_arm64_linux_docker.log",
		},
		{
			name: "x64-remote(windows+wsl)",
			// By design, remote gate is fixture-only unless OREN_REMOTE_RUN_ALL=1.
			cmd: "OREN_REMOTE_RUN=1 ./oretest --target macos",
			log: "build/logs/matrix_x64_remote.log",
		},
	}

	for _, s := range steps {
		fmt.Fprintf(os.Stderr, "[matrix] %s\n", s.name)
		rc := runWithTimeout(timeoutBin, stepTimeout, s.cmd, s.log)
		if rc != 0 {
			fmt.Fprintf(os.Stderr, "FAIL: matrix step %s failed (log: %s)\n", s.name, s.log)
			return rc
		}
	}

	if includeOBCPortability {
		fmt.Fprintf(os.Stderr, "[matrix] obc-portability\n")
		rc := runOBCPortabilityGate(stepTimeout)
		if rc != 0 {
			fmt.Fprintf(os.Stderr, "FAIL: obc portability failed (log: build/logs/obc_portability.log)\n")
			return rc
		}
	}
	return 0
}
