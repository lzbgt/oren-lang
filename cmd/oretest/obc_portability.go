package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type obcHashes struct {
	result string
	trace  string
}

func parseAVMHashes(out string) (obcHashes, bool) {
	// `avm --print-result-hash --print-trace-hash` prints:
	//   RESULT_HASH <hex>
	//   TRACE_HASH <hex>
	//
	// For safety, accept extra noise and take the last occurrence of each.
	var h obcHashes
	for _, ln := range strings.Split(out, "\n") {
		ln = strings.TrimSpace(ln)
		if strings.HasPrefix(ln, "RESULT_HASH ") {
			h.result = strings.TrimSpace(strings.TrimPrefix(ln, "RESULT_HASH "))
		}
		if strings.HasPrefix(ln, "TRACE_HASH ") {
			h.trace = strings.TrimSpace(strings.TrimPrefix(ln, "TRACE_HASH "))
		}
	}
	if h.result == "" || h.trace == "" {
		return obcHashes{}, false
	}
	return h, true
}

func copyTree(dstDir, srcDir string) error {
	return filepath.WalkDir(srcDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		outPath := filepath.Join(dstDir, rel)
		if d.IsDir() {
			return os.MkdirAll(outPath, 0o755)
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		return remoteX64BatchCopyFile(outPath, path)
	})
}

func runOBCPortabilityGate(timeout time.Duration) int {
	logPath := "build/logs/obc_portability.log"
	_ = os.Remove(logPath)

	if timeout <= 0 {
		timeout = 3 * time.Minute
	}
	deadline := time.Now().Add(timeout)
	timeLeft := func() time.Duration {
		d := time.Until(deadline)
		if d < 0 {
			return 0
		}
		return d
	}

	_ = os.MkdirAll("build/tmp/obc_portability", 0o755)

	obcSrc := "tests/avm/test_smoke_suite.oren"
	obcPath := "build/tmp/obc_portability/test_smoke_suite.obc"

	remoteX64BatchAppendLog(logPath, "[obc_portability] build obc")
	if timeLeft() <= 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] out of time before build")
		return 2
	}
	if rc, _ := remoteX64BatchExecCapture(logPath, timeLeft(), "./oren", "build", obcSrc, "--backend", "bytecode", "-o", obcPath); rc != 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] obc build failed")
		return 2
	}

	remoteX64BatchAppendLog(logPath, "[obc_portability] run host avm")
	if timeLeft() <= 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] out of time before host run")
		return 2
	}
	rcHost, outHost := remoteX64BatchExecCapture(logPath, timeLeft(), "./avm", "--print-result-hash", "--print-trace-hash", obcPath)
	if rcHost != 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] host avm failed")
		return 2
	}
	hostHashes, ok := parseAVMHashes(outHost)
	if !ok {
		remoteX64BatchAppendLog(logPath, "[obc_portability] host avm missing RESULT_HASH/TRACE_HASH")
		return 2
	}
	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] host result=%s trace=%s", hostHashes.result, hostHashes.trace))

	// Ensure the generated include exists (used by AVM build) before bundling.
	remoteX64BatchAppendLog(logPath, "[obc_portability] gen build/avm_root_pubkey.inc")
	if timeLeft() <= 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] out of time before avm_root_pubkey.inc")
		return 2
	}
	if rc, _ := remoteX64BatchExecCapture(logPath, 30*time.Second, "sh", "-c", "mkdir -p build && tools/gen_avm_root_pubkeys_inc.sh > build/avm_root_pubkey.inc"); rc != 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] gen avm_root_pubkey.inc failed")
		return 2
	}

	// Build a minimal, portable AVM source bundle:
	// - lib/avm/** (C sources + includes)
	// - third_party/tweetnacl/tweetnacl.c
	// - build/avm_root_pubkey.inc (generated include)
	bundleDir := "build/tmp/obc_portability/avm_bundle"
	_ = os.RemoveAll(bundleDir)
	_ = os.MkdirAll(bundleDir, 0o755)
	if err := copyTree(filepath.Join(bundleDir, "lib", "avm"), "lib/avm"); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] copy lib/avm failed: %v", err))
		return 2
	}
	if err := os.MkdirAll(filepath.Join(bundleDir, "third_party", "tweetnacl"), 0o755); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] mkdir tweetnacl failed: %v", err))
		return 2
	}
	if err := remoteX64BatchCopyFile(filepath.Join(bundleDir, "third_party", "tweetnacl", "tweetnacl.c"), "third_party/tweetnacl/tweetnacl.c"); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] copy tweetnacl.c failed: %v", err))
		return 2
	}
	if err := remoteX64BatchCopyFile(filepath.Join(bundleDir, "third_party", "tweetnacl", "tweetnacl.h"), "third_party/tweetnacl/tweetnacl.h"); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] copy tweetnacl.h failed: %v", err))
		return 2
	}
	if err := os.MkdirAll(filepath.Join(bundleDir, "build"), 0o755); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] mkdir build failed: %v", err))
		return 2
	}
	if err := remoteX64BatchCopyFile(filepath.Join(bundleDir, "build", "avm_root_pubkey.inc"), "build/avm_root_pubkey.inc"); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] copy avm_root_pubkey.inc failed: %v", err))
		return 2
	}

	avmTar := "build/tmp/obc_portability/avm_src.tgz"
	if err := remoteX64BatchTarGz(avmTar, bundleDir); err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] tar avm bundle failed: %v", err))
		return 2
	}
	avmSrcSHA, err := remoteX64BatchSHA256File(avmTar)
	if err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] sha avm bundle failed: %v", err))
		return 2
	}
	obcSHA, err := remoteX64BatchSHA256File(obcPath)
	if err != nil {
		remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] sha obc failed: %v", err))
		return 2
	}

	// --- linux/arm64 docker (persistent container) ---
	dockerID := "c7e5f7bd9f5c"
	dockerKey := "obc_" + obcSHA[:16] + "_avm_" + avmSrcSHA[:16]

	remoteX64BatchAppendLog(logPath, "[obc_portability] run docker avm")
	if timeLeft() <= 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] out of time before docker")
		return 2
	}
	dockerScript := fmt.Sprintf(
		`set -euo pipefail; root=/work/obc_portability/%s; mkdir -p "$root"; `+
			`if [ ! -x "$root/avm" ]; then `+
			`rm -rf "$root/src"; mkdir -p "$root/src"; `+
			`tar -xzf /repo/%s -C "$root/src"; `+
			`srcs=$(ls "$root/src/lib/avm"/*.c 2>/dev/null | sort | tr '\n' ' '); `+
			`gcc -O2 -fno-fast-math -ffp-contract=off -I "$root/src/lib/avm" -I "$root/src/build" -o "$root/avm" $srcs "$root/src/third_party/tweetnacl/tweetnacl.c"; `+
			`fi; `+
			`"$root/avm" --print-result-hash --print-trace-hash /repo/%s`,
		dockerKey,
		avmTar,
		obcPath,
	)
	rcDocker, outDocker := remoteX64BatchExecCapture(logPath, timeLeft(), "docker", "exec", "-i", dockerID, "bash", "-lc", dockerScript)
	if rcDocker != 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] docker avm failed")
		return 2
	}
	dockerHashes, ok := parseAVMHashes(outDocker)
	if !ok {
		remoteX64BatchAppendLog(logPath, "[obc_portability] docker avm missing RESULT_HASH/TRACE_HASH")
		return 2
	}
	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] docker result=%s trace=%s", dockerHashes.result, dockerHashes.trace))

	// --- linux/x86_64 (WSL2 on remote Win11 host) ---
	remoteX64BatchAppendLog(logPath, "[obc_portability] run remote wsl avm")
	if timeLeft() <= 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] out of time before remote")
		return 2
	}
	opts := remoteX64BatchDefaultOptions()
	sshArgs := remoteX64BatchSSHArgs(opts)
	scpArgs := remoteX64BatchSCPArgs(opts)

	// Key the remote directory by AVM source SHA so the AVM binary can be reused across runs.
	remoteKey := "obc_port_avm_" + avmSrcSHA[:16]
	remoteUnixDir := opts.remoteUnixRoot + "/" + remoteKey
	remoteWinDir := opts.remoteWinRoot + `\` + remoteKey
	remoteWslDir := opts.remoteWslRoot + "/" + remoteKey

	ensureCmd := fmt.Sprintf(`cmd.exe /c "if not exist %s mkdir %s"`, remoteWinDir, remoteWinDir)
	{
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, ensureCmd)
		if rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "ssh", args...); rc != 0 {
			remoteX64BatchAppendLog(logPath, "[obc_portability] remote ensure dir failed")
			return 2
		}
	}

	// Determine whether the remote already has the AVM bundle (and compiled AVM) for this SHA,
	// and whether the current OBC is already uploaded.
	checkCmd := fmt.Sprintf(
		`wsl.exe -e bash -lc "set -euo pipefail; root=%s; `+
			`if [ -f $root/avm_src.sha256 ]; then cat $root/avm_src.sha256; fi; `+
			`if [ -f $root/obc.sha256 ]; then cat $root/obc.sha256; fi; `+
			`if [ -x $root/avm ]; then echo AVM_OK; fi"`,
		remoteWslDir,
	)
	haveAVM := false
	haveOBC := false
	{
		args := append([]string{}, sshArgs...)
		args = append(args, opts.host, checkCmd)
		rc, out := remoteX64BatchExecCapture(logPath, 15*time.Second, "ssh", args...)
		if rc == 0 {
			if strings.Contains(out, avmSrcSHA) && strings.Contains(out, "AVM_OK") {
				haveAVM = true
			}
			if strings.Contains(out, obcSHA) {
				haveOBC = true
			}
		}
	}

	if !haveAVM {
		remoteX64BatchAppendLog(logPath, "[obc_portability] upload avm bundle")
		args := append([]string{}, scpArgs...)
		args = append(args, avmTar, fmt.Sprintf("%s:%s/avm_src.tgz", opts.host, remoteUnixDir))
		if rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "scp", args...); rc != 0 {
			remoteX64BatchAppendLog(logPath, "[obc_portability] scp avm bundle failed")
			return 2
		}

		buildCmd := fmt.Sprintf(
			`wsl.exe -e bash -lc "set -euo pipefail; root=%s; `+
				`mkdir -p $root/src; rm -rf $root/src/*; `+
				`tar -xzf $root/avm_src.tgz -C $root/src; `+
				`srcs=$(ls $root/src/lib/avm/*.c 2>/dev/null | sort | tr '\n' ' '); `+
				`gcc -O2 -fno-fast-math -ffp-contract=off -I $root/src/lib/avm -I $root/src/build -o $root/avm $srcs $root/src/third_party/tweetnacl/tweetnacl.c; `+
				`chmod +x $root/avm; printf '%s\n' > $root/avm_src.sha256"`,
			remoteWslDir,
			avmSrcSHA,
		)
		args2 := append([]string{}, sshArgs...)
		args2 = append(args2, opts.host, buildCmd)
		if rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 2, "ssh", args2...); rc != 0 {
			remoteX64BatchAppendLog(logPath, "[obc_portability] remote avm build failed")
			return 2
		}
	}

	if !haveOBC {
		remoteX64BatchAppendLog(logPath, "[obc_portability] upload obc")
		args := append([]string{}, scpArgs...)
		args = append(args, obcPath, fmt.Sprintf("%s:%s/test_smoke_suite.obc", opts.host, remoteUnixDir))
		if rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 3, "scp", args...); rc != 0 {
			remoteX64BatchAppendLog(logPath, "[obc_portability] scp obc failed")
			return 2
		}
		stampCmd := fmt.Sprintf(`wsl.exe -e bash -lc "set -e; printf '%s\n' > %s/obc.sha256"`, obcSHA, remoteWslDir)
		args2 := append([]string{}, sshArgs...)
		args2 = append(args2, opts.host, stampCmd)
		if rc, _ := remoteX64BatchRetry(logPath, timeLeft(), 2, "ssh", args2...); rc != 0 {
			remoteX64BatchAppendLog(logPath, "[obc_portability] remote obc sha stamp failed")
			return 2
		}
	}

	runCmd := fmt.Sprintf(`wsl.exe -e bash -lc "set -euo pipefail; root=%s; $root/avm --print-result-hash --print-trace-hash $root/test_smoke_suite.obc"`, remoteWslDir)
	argsRun := append([]string{}, sshArgs...)
	argsRun = append(argsRun, opts.host, runCmd)
	rcWSL, outWSL := remoteX64BatchExecCapture(logPath, timeLeft(), "ssh", argsRun...)
	if rcWSL != 0 {
		remoteX64BatchAppendLog(logPath, "[obc_portability] remote wsl avm run failed")
		return 2
	}
	wslHashes, ok := parseAVMHashes(outWSL)
	if !ok {
		remoteX64BatchAppendLog(logPath, "[obc_portability] remote wsl missing RESULT_HASH/TRACE_HASH")
		return 2
	}
	remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] wsl result=%s trace=%s", wslHashes.result, wslHashes.trace))

	// Compare.
	type named struct {
		name string
		h    obcHashes
	}
	all := []named{
		{name: "host", h: hostHashes},
		{name: "docker", h: dockerHashes},
		{name: "wsl", h: wslHashes},
	}
	sort.Slice(all, func(i, j int) bool { return all[i].name < all[j].name })

	ref := all[0].h
	for _, n := range all {
		if n.h.result != ref.result || n.h.trace != ref.trace {
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] FAIL: %s hashes differ", n.name))
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] want result=%s trace=%s", ref.result, ref.trace))
			remoteX64BatchAppendLog(logPath, fmt.Sprintf("[obc_portability] got  result=%s trace=%s", n.h.result, n.h.trace))
			return 1
		}
	}
	remoteX64BatchAppendLog(logPath, "[obc_portability] OK")
	return 0
}
