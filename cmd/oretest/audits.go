package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

func auditNativeCapsuleSyscallPrehooks() error {
	// Purpose: prevent “capsule bypass” regressions by ensuring every syscall intrinsic
	// lowered by the native backend has a capsule pre-hook call in the lowering.
	//
	// This is intentionally a static audit (no compilation). It is cheap, fast,
	// and catches bypasses introduced by refactors.
	compilerPaths := []string{
		// arm64 syscall lowering module (Darwin/Linux).
		filepath.Join("lib", "compiler", "arm64_native_expr_syscalls.oren"),
		// x86_64 syscall lowering module (Linux/Windows).
		filepath.Join("lib", "compiler", "x64_native_program", "046_emit_sys_intrinsics.oren"),
	}
	runtimePath := filepath.Join("lib", "runtime_native.oren")

	rt, err := expandOrenIncludes(runtimePath)
	if err != nil {
		return fmt.Errorf("expand includes %s: %w", runtimePath, err)
	}

	// Collect all defined capsule pre-hooks in the native runtime.
	runtimePrehooks := map[string]bool{}
	for _, line := range strings.Split(rt, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "fn native_capsule_sys_") {
			continue
		}
		// fn native_capsule_sys_open_pre(...)
		name := strings.TrimPrefix(line, "fn ")
		if i := strings.IndexByte(name, '('); i >= 0 {
			name = name[:i]
		}
		if strings.HasSuffix(name, "_pre") {
			runtimePrehooks[name] = true
		}
	}

	// Exceptions: sys_exit is always permitted as an immediate termination.
	// (Capsule governance can still choose to restrict PROC usage at higher layers.)
	exempt := map[string]bool{
		"sys_exit": true,
		// Internal runtime primitives:
		// - sys_gettid is needed for the runtime's own locking/GC bookkeeping.
		// - ulock is a kernel scheduling primitive used by the runtime lock.
		// These are not part of the host-effect domains (FS/NET/PROC/ENV/TIME).
		"sys_gettid":     true,
		"sys_ulock_wait": true,
		"sys_ulock_wake": true,
	}

	// Some Oren "sys_*" intrinsics are aliases that intentionally lower to other
	// host syscalls, but still need capsule gating. This maps intrinsic name to
	// the expected capsule prehook symbol(s).
	//
	// Default rule (when missing from this map):
	//   sys_foo -> native_capsule_sys_foo_pre
	//
	// NOTE: keep this list small and explicit; the point of the audit is to force
	// deliberate review when new intrinsics are introduced.
	prehookAlias := map[string][]string{
		// fcntl wrappers
		"sys_fcntl_getfl":   {"native_capsule_sys_fcntl_pre"},
		"sys_fcntl_setfl":   {"native_capsule_sys_fcntl_pre"},
		"sys_fcntl_getpath": {"native_capsule_sys_fcntl_pre"},
		// dup3 lowers via dup2-style capsule hooks (oldfd/newfd semantics).
		"sys_dup3": {"native_capsule_sys_dup2_pre"},
		// send/recv lower to sendto/recvfrom with NULL addr.
		"sys_send": {"native_capsule_sys_sendto_pre"},
		"sys_recv": {"native_capsule_sys_recvfrom_pre"},
	}

	var missing []string
	for _, compilerPath := range compilerPaths {
		compilerExpanded, err := expandOrenIncludes(compilerPath)
		if err != nil {
			return fmt.Errorf("expand includes %s: %w", compilerPath, err)
		}
		blocks := parseSyscallBlocks(compilerPath, compilerExpanded)
		if len(blocks) == 0 {
			return fmt.Errorf("no syscall blocks found in %s (unexpected)", compilerPath)
		}

		for _, b := range blocks {
			usesSyscall := strings.Contains(b.text, "emit_svc_preserve_heap") ||
				strings.Contains(b.text, "abi.darwin_sys_") ||
				strings.Contains(b.text, "labi.linux_sys_") ||
				strings.Contains(b.text, "insn_svc(")
			if !usesSyscall {
				continue
			}
			for _, sysName := range b.sysNames {
				if exempt[sysName] {
					continue
				}

				expected := prehookAlias[sysName]
				if len(expected) == 0 {
					expected = []string{"native_capsule_" + sysName + "_pre"}
				}

				ok := false
				for _, want := range expected {
					if strings.Contains(b.text, want) {
						ok = true
						break
					}
				}
				if !ok {
					missing = append(missing, sysName+" ("+filepath.ToSlash(compilerPath)+")")
				}
			}

			// Also ensure every referenced prehook actually exists in runtime_native.oren.
			for _, pre := range extractPrehookNames(b.text) {
				if !runtimePrehooks[pre] {
					return fmt.Errorf("lowering references %s but runtime does not define it (%s)", pre, runtimePath)
				}
			}
		}
	}

	if len(missing) > 0 {
		sort.Strings(missing)
		// Dedupe.
		uniq := missing[:0]
		for i, s := range missing {
			if i == 0 || s != missing[i-1] {
				uniq = append(uniq, s)
			}
		}
		return fmt.Errorf("missing capsule prehook call in lowering blocks for: %s", strings.Join(uniq, ", "))
	}

	return nil
}

func auditNativeNoDirectSvcBypass() error {
	// Purpose: prevent “capsule bypass” regressions by ensuring the native backend
	// does not start emitting direct `svc` instructions in new places.
	//
	// Policy:
	// - Syscall number references belong in the dedicated syscall lowering modules
	//   (where capsule prehooks are enforced).
	// - A small number of `svc` sites are allowed for internal plumbing:
	//     - entry stub `exit` (arm64_native_program.oren)
	//     - early heap mapping `mmap` + fail-fast `exit` (arm64_native_expr.oren)
	//     - Mach-O tooling helper `exit` (arm64_macho.oren)
	//
	// Anything else is almost certainly a regression and should be moved to the
	// syscall lowering module with explicit capsule hooks.
	allowedFiles := map[string]bool{
		filepath.Join("lib", "compiler", "arm64_native_expr_syscalls.oren"): true,
		filepath.Join("lib", "compiler", "arm64_native_program.oren"):       true, // entry stub exit
		filepath.Join("lib", "compiler", "arm64_native_expr.oren"):          true, // heap mmap + fail-fast exit
		filepath.Join("lib", "compiler", "arm64_macho.oren"):                true, // tooling helper exit
		// x86_64 native backend syscall lowering (Linux/Windows sys_* intrinsics).
		filepath.Join("lib", "compiler", "x64_native_program", "046_emit_sys_intrinsics.oren"): true,
	}
	allowedSyms := map[string]bool{
		"sys_exit": true,
		"sys_mmap": true,
	}

	isSyscallLoweringModule := func(path string) bool {
		if strings.HasSuffix(path, "arm64_native_expr_syscalls.oren") {
			return true
		}
		if strings.HasSuffix(path, filepath.Join("x64_native_program", "046_emit_sys_intrinsics.oren")) {
			return true
		}
		return false
	}

	// When a large compiler module is split via `// @include`, we scan only the
	// top-level entry file and skip the included parts directory. The entry file
	// is expanded before scanning so policy checks still see the real code.
	skipDirs := map[string]bool{
		filepath.Join("lib", "compiler", "arm64_native_expr"):          true,
		filepath.Join("lib", "compiler", "arm64_native_expr_syscalls"): true,
	}

	var offenders []string

	err := filepath.WalkDir(filepath.Join("lib", "compiler"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if skipDirs[path] {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}
		// `x64_native_program.oren` is a thin include-wrapper; scanning its expanded form
		// would duplicate checks against the real chunk files and cause false positives.
		if filepath.Clean(path) == filepath.Join("lib", "compiler", "x64_native_program.oren") {
			return nil
		}

		src, rerr := expandOrenIncludes(path)
		if rerr != nil {
			return rerr
		}
		if !strings.Contains(src, "insn_svc(") && !strings.Contains(src, "abi.darwin_sys_") && !strings.Contains(src, "labi.linux_sys_") {
			return nil
		}

		// We only care about *emitting* an svc instruction into generated code.
		// The compiler core defines helper functions like `fn insn_svc(...)` which
		// are not syscall emissions.
		emitsSVC := false
		for _, line := range strings.Split(src, "\n") {
			if strings.Contains(line, "push_u32_le(") && strings.Contains(line, "insn_svc(") {
				// Avoid false positives from string constants used in grep/audit patterns.
				// Heuristic: if the match appears inside a quoted string on the line, ignore it.
				if strings.Contains(line, "\"push_u32_le(") || strings.Contains(line, "\"insn_svc(") {
					continue
				}
				emitsSVC = true
				break
			}
		}

		if emitsSVC {
			if !allowedFiles[path] {
				offenders = append(offenders, fmt.Sprintf("%s: emits insn_svc()", path))
				return nil
			}

			// For allowed files other than the dedicated syscall lowering module,
			// ensure the direct svc sites are only for `sys_exit`/`sys_mmap`.
			if isSyscallLoweringModule(path) {
				return nil
			}
			lines := strings.Split(src, "\n")
			for i, line := range lines {
				if !(strings.Contains(line, "push_u32_le(") && strings.Contains(line, "insn_svc(")) {
					continue
				}
				if strings.Contains(line, "\"push_u32_le(") || strings.Contains(line, "\"insn_svc(") {
					continue
				}
				ok := false
				// Look back a few lines for the syscall number load.
				start := i - 8
				if start < 0 {
					start = 0
				}
				window := strings.Join(lines[start:i+1], "\n")
				for sym := range allowedSyms {
					if strings.Contains(window, sym) {
						ok = true
						break
					}
				}
				if !ok {
					offenders = append(offenders, fmt.Sprintf("%s:%d: svc emission not tied to allowed sys_* (only sys_exit/sys_mmap allowed here)", path, i+1))
				}
			}
		}

		// Also ensure no new direct sysno references appear outside the syscall module.
		// Only allow sys_exit/sys_mmap in the few whitelisted internal files.
		if strings.Contains(src, "abi.darwin_sys_") || strings.Contains(src, "labi.linux_sys_") {
			if !allowedFiles[path] {
				offenders = append(offenders, fmt.Sprintf("%s: contains abi.darwin_sys_ / labi.linux_sys_", path))
				return nil
			}
			if isSyscallLoweringModule(path) {
				return nil
			}
			for _, line := range strings.Split(src, "\n") {
				if !strings.Contains(line, "abi.darwin_sys_") && !strings.Contains(line, "labi.linux_sys_") {
					continue
				}
				// Avoid false positives from string constants used for audits/tools.
				if strings.Contains(line, "\"abi.darwin_sys_") || strings.Contains(line, "\"labi.linux_sys_") {
					continue
				}
				// Heuristic: require the line to mention an allowed sys_* symbol.
				ok := false
				for sym := range allowedSyms {
					if strings.Contains(line, sym) {
						ok = true
						break
					}
				}
				if !ok {
					offenders = append(offenders, fmt.Sprintf("%s: disallowed direct sysno reference: %s", path, strings.TrimSpace(line)))
				}
			}
		}

		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 20 {
			offenders = offenders[:20]
		}
		return fmt.Errorf("direct svc/sysno emission outside syscall lowering module; first offenders:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditStdlibModernStyle() error {
	// Purpose: keep `lib/std` in sync with rolling language idioms.
	//
	// This is intentionally a cheap static scan (no compilation), intended to
	// prevent regressions during rolling refactors.
	type rule struct {
		name        string
		pattern     string
		allowInFile func(path string) bool
		allowInLine func(trimmedLine string) bool
	}
	rules := []rule{
		{
			name:    "no string_concat in stdlib (prefer `+`)",
			pattern: "string_concat(",
			allowInLine: func(trimmedLine string) bool {
				// Allow mention in comments/docstrings, but not in code.
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no direct oren_list_* in stdlib (prefer container methods / std:list)",
			pattern: "oren_list_",
			allowInFile: func(path string) bool {
				// std/list.oren is the single allowlisted wrapper module.
				return filepath.Clean(path) == filepath.Join("lib", "std", "list.oren")
			},
			allowInLine: func(trimmedLine string) bool {
				// Allow mention in comments/docstrings, but not in code.
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no legacy @forin internal identifiers",
			pattern: "@forin_",
		},
		{
			name:    "no legacy @forinr internal identifiers",
			pattern: "@forinr_",
		},
	}

	var offenders []string
	err := filepath.WalkDir(filepath.Join("lib", "std"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}

		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		src := string(b)
		lines := strings.Split(src, "\n")
		for i, line := range lines {
			trim := strings.TrimSpace(line)
			for _, r := range rules {
				if !strings.Contains(line, r.pattern) {
					continue
				}
				if r.allowInFile != nil && r.allowInFile(path) {
					continue
				}
				if r.allowInLine != nil && r.allowInLine(trim) {
					continue
				}
				offenders = append(offenders, fmt.Sprintf("%s:%d: %s (found %q)", path, i+1, r.name, r.pattern))
			}
		}
		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("stdlib style violations:\n%s", strings.Join(offenders, "\n"))
	}

	return nil
}

func auditRuntimeNativeModernStyle() error {
	// Purpose: keep `lib/runtime_native` in sync with rolling language idioms for higher-level helpers.
	//
	// The runtime can contain low-level primitives, but we still want to avoid reintroducing
	// legacy patterns in user-facing helpers (notably `string_concat` call-chains).
	allowStringConcatIn := map[string]bool{
		filepath.Join("lib", "runtime_native", "160_iteration.oren"):      true, // defines `string_concat`
		filepath.Join("lib", "runtime_native", "120_first_class_fn.oren"): true, // operator plumbing may rely on it
	}

	var offenders []string
	err := filepath.WalkDir(filepath.Join("lib", "runtime_native"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}

		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		src := string(b)
		lines := strings.Split(src, "\n")
		for i, line := range lines {
			if !strings.Contains(line, "string_concat(") {
				continue
			}
			trim := strings.TrimSpace(line)
			if strings.HasPrefix(trim, "//") {
				continue
			}
			if allowStringConcatIn[path] {
				continue
			}
			offenders = append(offenders, fmt.Sprintf("%s:%d: no string_concat callsites in runtime_native (prefer `+`) (found %q)", path, i+1, "string_concat("))
		}
		return nil
	})
	if err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("runtime_native style violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditArm64AdrFixupSlots() error {
	// Purpose: protect the rolling migration from ADR (±1MB) to ADRP+ADD (±4GB pages)
	// for native backend fixups.
	//
	// The native backend emits placeholder instruction words at each `adr_*` fixup site.
	// Once we patch those fixups as a 2-instruction sequence, any new site that only
	// reserves 1 slot will cause silent code corruption (pos+4 overwrites the next insn).
	//
	// Keep this audit intentionally small and specific to the compiler lowering modules.
	type fixupKind struct {
		name    string
		pattern string
	}
	kinds := []fixupKind{
		{name: "adr_data", pattern: "\"type\": \"adr_data\""},
		{name: "adr_code", pattern: "\"type\": \"adr_code\""},
	}

	var paths []string
	paths = append(paths, filepath.Join("lib", "compiler", "arm64_native_stmt.oren"))

	exprDir := filepath.Join("lib", "compiler", "arm64_native_expr")
	if err := filepath.WalkDir(exprDir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}
		paths = append(paths, path)
		return nil
	}); err != nil {
		return err
	}

	var offenders []string
	for _, path := range paths {
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		for i := range lines {
			line := lines[i]
			for _, k := range kinds {
				if !strings.Contains(line, k.pattern) {
					continue
				}

				// Heuristic: find the nearest preceding `var adr_pos` (or similar) and count
				// reserved u32 slots up to the fixup push.
				start := i - 20
				if start < 0 {
					start = 0
				}
				for j := i; j >= start; j-- {
					if strings.Contains(lines[j], "var adr_pos") {
						start = j
						break
					}
				}

				slotCount := 0
				for j := start; j <= i; j++ {
					if strings.Contains(lines[j], "push_u32_le(ctx[\"code\"], 0)") {
						slotCount++
					}
				}
				if slotCount < 2 {
					offenders = append(offenders, fmt.Sprintf("%s:%d: %s fixup must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, k.name, slotCount))
				}
			}
		}
	}

	// Debug hook placeholder is emitted in the entry stub (not near fixup pushes),
	// but it is patched via `adr_data` later (Mach-O/ELF emitters). Ensure it also reserves 2 slots.
	if err := func() error {
		path := filepath.Join("lib", "compiler", "arm64_native_program.oren")
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		for i := range lines {
			if !strings.Contains(lines[i], "ctx[\"debug_fixup_pos\"]") {
				continue
			}
			start := i - 8
			if start < 0 {
				start = 0
			}
			slotCount := 0
			for j := start; j <= i; j++ {
				if strings.Contains(lines[j], "push_u32_le(ctx[\"code\"], 0)") {
					slotCount++
				}
			}
			if slotCount < 2 {
				offenders = append(offenders, fmt.Sprintf("%s:%d: debug_fixup_pos must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, slotCount))
			}
		}
		return nil
	}(); err != nil {
		return err
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("arm64 fixup slot violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditArm64MachoGotStubSlots() error {
	// Purpose: Mach-O imports use a small stub sequence that gets patched by `got_load` fixups.
	// The stub placeholder must reserve 2 u32 words (ADRP + ADD). If it reserves 1, the patcher
	// will overwrite the next instruction (LDR/BR) and corrupt the stub silently.
	path := filepath.Join("lib", "compiler", "arm64_macho.oren")
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(b), "\n")

	var offenders []string
	for i := range lines {
		if !strings.Contains(lines[i], "\"type\": \"got_load\"") {
			continue
		}
		start := i - 30
		if start < 0 {
			start = 0
		}
		slotCount := 0
		for j := start; j <= i; j++ {
			if strings.Contains(lines[j], "push_u32_le(code, 0)") {
				slotCount++
			}
		}
		if slotCount < 2 {
			offenders = append(offenders, fmt.Sprintf("%s:%d: got_load stub must reserve 2 u32 slots (ADRP+ADD), found %d", path, i+1, slotCount))
		}
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		return fmt.Errorf("arm64 Mach-O got stub violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditRepoModernStyle() error {
	// Purpose: keep the repo moving toward a consistent modern surface syntax.
	//
	// This is intentionally a simple textual scan, enforced via oretest, to prevent
	// reintroducing deprecated patterns during rolling refactors.
	//
	// Exceptions:
	// - `string_concat` exists as a low-level helper for the native runtime and for operator plumbing.
	allowStringConcatIn := map[string]bool{
		filepath.Join("lib", "runtime_native", "160_iteration.oren"):      true, // defines `string_concat`
		filepath.Join("lib", "runtime_native", "120_first_class_fn.oren"): true, // operator plumbing may rely on it
	}

	type rule struct {
		name        string
		pattern     string
		allowInFile func(path string) bool
		allowInLine func(trimmedLine string) bool
	}
	rules := []rule{
		{
			name:    "no string_concat callsites (prefer `+`)",
			pattern: "string_concat(",
			allowInFile: func(path string) bool {
				return allowStringConcatIn[path]
			},
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			// Rolling syntax modernization: prefer `if cond { ... }` over legacy `if (cond) { ... }`.
			//
			// Note: this scan is intentionally heuristic. We only flag when the trimmed line begins
			// with the legacy construct, so string literals like `emit("if (x) {")` don't trip it.
			name:    "no legacy if (...) condition parentheses",
			pattern: "if (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "if (")
			},
		},
		{
			name:    "no legacy if(...) condition parentheses",
			pattern: "if(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "if(")
			},
		},
		{
			name:    "no legacy else if (...) condition parentheses",
			pattern: "else if (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "else if (") && !strings.HasPrefix(trimmedLine, "} else if (")
			},
		},
		{
			name:    "no legacy else if(...) condition parentheses",
			pattern: "else if(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "else if(") && !strings.HasPrefix(trimmedLine, "} else if(")
			},
		},
		{
			// Rolling syntax modernization: prefer `while cond { ... }` over legacy `while (cond) { ... }`.
			name:    "no legacy while (...) condition parentheses",
			pattern: "while (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "while (")
			},
		},
		{
			name:    "no legacy while(...) condition parentheses",
			pattern: "while(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "while(")
			},
		},
		{
			// Rolling syntax modernization: prefer `for x in xs { ... }` or `for init; cond; post { ... }`
			// over legacy `for (<header>) { ... }`.
			name:    "no legacy for (...) header parentheses",
			pattern: "for (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "for (")
			},
		},
		{
			name:    "no legacy for(...) header parentheses",
			pattern: "for(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "for(")
			},
		},
		{
			// Rolling syntax modernization: prefer `switch expr { ... }` over legacy `switch (expr) { ... }`.
			name:    "no legacy switch (...) expression parentheses",
			pattern: "switch (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "switch (")
			},
		},
		{
			name:    "no legacy switch(...) expression parentheses",
			pattern: "switch(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "switch(")
			},
		},
		{
			// Rolling syntax modernization: prefer `match expr { ... }` over legacy `match (expr) { ... }`.
			name:    "no legacy match (...) expression parentheses",
			pattern: "match (",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "match (")
			},
		},
		{
			name:    "no legacy match(...) expression parentheses",
			pattern: "match(",
			allowInLine: func(trimmedLine string) bool {
				return !strings.HasPrefix(trimmedLine, "match(")
			},
		},
		{
			name:    "no legacy @forin internal identifiers",
			pattern: "@forin_",
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
		{
			name:    "no legacy @forinr internal identifiers",
			pattern: "@forinr_",
			allowInLine: func(trimmedLine string) bool {
				return strings.HasPrefix(trimmedLine, "//")
			},
		},
	}

	var offenders []string
	// Also enforce source size limits for C runtime include chunks. These chunks exist
	// specifically to avoid context overflow; keep them under the same 2000-line guardrail.
	{
		type sizeRule struct {
			root      string
			ext       string
			maxLines  int
			desc      string
			allowFile func(path string) bool
		}
		sizeRules := []sizeRule{
			{
				root:     filepath.Join("lib", "runtime"),
				ext:      ".inc",
				maxLines: 2000,
				desc:     "C runtime include chunk too large",
			},
			{
				root:     filepath.Join("lib", "runtime_buf"),
				ext:      ".inc",
				maxLines: 2000,
				desc:     "C runtime_buf include chunk too large",
			},
		}
		for _, sr := range sizeRules {
			if _, err := os.Stat(sr.root); err != nil {
				continue
			}
			err := filepath.WalkDir(sr.root, func(path string, d os.DirEntry, err error) error {
				if err != nil {
					return err
				}
				if d.IsDir() {
					return nil
				}
				if !strings.HasSuffix(path, sr.ext) {
					return nil
				}
				if sr.allowFile != nil && sr.allowFile(path) {
					return nil
				}
				b, rerr := os.ReadFile(path)
				if rerr != nil {
					return rerr
				}
				lines := 0
				for _, ch := range b {
					if ch == '\n' {
						lines++
					}
				}
				// Count last line if non-empty.
				if len(b) > 0 && b[len(b)-1] != '\n' {
					lines++
				}
				if lines > sr.maxLines {
					offenders = append(offenders, fmt.Sprintf("%s:1: %s (%d lines > %d)", path, sr.desc, lines, sr.maxLines))
				}
				return nil
			})
			if err != nil {
				return err
			}
		}
	}

	roots := []string{filepath.Join("lib"), filepath.Join("tests"), filepath.Join("examples")}
	for _, root := range roots {
		if _, err := os.Stat(root); err != nil {
			continue
		}
		err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				return nil
			}
			if !strings.HasSuffix(path, ".oren") {
				return nil
			}

			b, rerr := os.ReadFile(path)
			if rerr != nil {
				return rerr
			}
			// Size guard: keep `.oren` sources reviewable without context overflow.
			// This is enforced repo-wide in rolling mode: split large files into modules.
			//
			// Note: keep this simple and deterministic; count '\n' as line separators.
			if len(b) > 0 {
				lines := 1
				for _, ch := range b {
					if ch == '\n' {
						lines++
					}
				}
				if lines > 2000 {
					offenders = append(offenders, fmt.Sprintf("%s:1: file too large (%d lines > 2000); split into modules", path, lines))
				}
			}
			lines := strings.Split(string(b), "\n")
			for i, line := range lines {
				trim := strings.TrimSpace(line)
				for _, r := range rules {
					if !strings.Contains(line, r.pattern) {
						continue
					}
					if r.allowInFile != nil && r.allowInFile(path) {
						continue
					}
					if r.allowInLine != nil && r.allowInLine(trim) {
						continue
					}
					offenders = append(offenders, fmt.Sprintf("%s:%d: %s (found %q)", path, i+1, r.name, r.pattern))
				}
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 50 {
			offenders = append(offenders[:50], fmt.Sprintf("... (%d more)", len(offenders)-50))
		}
		return fmt.Errorf("repo style violations:\n%s", strings.Join(offenders, "\n"))
	}
	return nil
}

func auditIncludeChunkCoherence() error {
	// Purpose: prevent `// @include`-based Oren sources from splitting mid-block,
	// which makes individual include chunks unreadable and prone to context overflow.
	//
	// This is a cheap static scan: it does not parse Oren fully; it just checks per-file
	// brace balance while ignoring braces inside string literals and line comments.
	type fileStat struct {
		path string
		bal  int
		min  int
	}
	type rootResult struct {
		root  string
		stats []fileStat
		miss  []string
	}

	// Find roots: any `.oren` file under `lib/` containing a `// @include "..."` directive line.
	var roots []string
	err := filepath.WalkDir(filepath.Join("lib"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".oren") {
			return nil
		}
		b, rerr := os.ReadFile(path)
		if rerr != nil {
			return rerr
		}
		// Be strict: only treat it as a root if there is an actual directive at the
		// beginning of a (trimmed) line. This avoids false positives from comments like:
		//   // NOTE: uses includes (`// @include "..."`)
		lines := strings.Split(string(b), "\n")
		for _, line := range lines {
			if strings.HasPrefix(strings.TrimSpace(line), "// @include \"") {
				roots = append(roots, path)
				break
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	sort.Strings(roots)
	if len(roots) == 0 {
		return nil
	}

	var offenders []string
	var allMissing []string

	for _, root := range roots {
		visited := map[string]bool{}
		// Traverse include tree (relative to the including file's directory).
		var stack []string
		stack = append(stack, root)
		var missing []string
		var stats []fileStat

		for len(stack) > 0 {
			cur := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			cur = filepath.Clean(cur)
			if visited[cur] {
				continue
			}
			visited[cur] = true

			b, rerr := os.ReadFile(cur)
			if rerr != nil {
				// If we can't read a root, hard fail; otherwise record missing include.
				missing = append(missing, fmt.Sprintf("%s (read error: %v)", cur, rerr))
				continue
			}

			bal, min := braceBalanceOren(b)
			stats = append(stats, fileStat{path: cur, bal: bal, min: min})
			if bal != 0 || min < 0 {
				offenders = append(offenders, fmt.Sprintf("%s: unbalanced braces (bal=%d, min=%d) under root %s", cur, bal, min, root))
			}
			if first := firstSignificantOrenLine(b); first != "" {
				if !isAllowedIncludeChunkStart(first) {
					offenders = append(offenders, fmt.Sprintf("%s: suspicious include chunk start %q under root %s (likely mid-block split)", cur, first, root))
				}
			}

			// Parse include directives for recursion.
			dir := filepath.Dir(cur)
			lines := strings.Split(string(b), "\n")
			for _, line := range lines {
				trim := strings.TrimSpace(line)
				if !strings.HasPrefix(trim, "// @include \"") {
					continue
				}
				rest := strings.TrimPrefix(trim, "// @include \"")
				q := strings.IndexByte(rest, '"')
				if q < 0 {
					continue
				}
				rel := rest[:q]
				next := filepath.Clean(filepath.Join(dir, rel))
				if _, err := os.Stat(next); err != nil {
					missing = append(missing, fmt.Sprintf("%s includes missing %s", cur, next))
					continue
				}
				stack = append(stack, next)
			}
		}

		// If includes are missing, report them (but keep output bounded).
		if len(missing) > 0 {
			sort.Strings(missing)
			allMissing = append(allMissing, missing...)
		}
	}

	if len(allMissing) > 0 {
		sort.Strings(allMissing)
		if len(allMissing) > 30 {
			allMissing = append(allMissing[:30], fmt.Sprintf("... (%d more)", len(allMissing)-30))
		}
		return fmt.Errorf("include chunk missing files:\n%s", strings.Join(allMissing, "\n"))
	}

	if len(offenders) > 0 {
		sort.Strings(offenders)
		if len(offenders) > 30 {
			offenders = append(offenders[:30], fmt.Sprintf("... (%d more)", len(offenders)-30))
		}
		return fmt.Errorf("include chunk coherence violations:\n%s", strings.Join(offenders, "\n"))
	}

	return nil
}

func firstSignificantOrenLine(src []byte) string {
	// Returns the first non-empty, non-`//` comment line (trimmed).
	// We intentionally ignore block comments because Oren doesn't currently standardize them.
	lines := strings.Split(string(src), "\n")
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if trim == "" {
			continue
		}
		if strings.HasPrefix(trim, "//") {
			continue
		}
		return trim
	}
	return ""
}

func isAllowedIncludeChunkStart(trimmedLine string) bool {
	// Heuristic: include chunks should begin at a top-level declaration boundary.
	// This catches mid-function splits that could still be brace-balanced.
	//
	// Allow:
	// - attributes (`@...`)
	// - module imports and global vars
	// - top-level declarations (fn/struct/class/trait/impl/enum/ffi/test)
	//
	// Disallow:
	// - statements like `if ...`, `while ...`, `return ...`, `x = ...`
	// - closers like `}` or `else` which indicate we split at an interior boundary
	allowedPrefixes := []string{
		"@",
		"import ",
		"var ",
		"fn ",
		"struct ",
		"class ",
		"trait ",
		"impl ",
		"enum ",
		"ffi ",
		"test ",
	}
	for _, p := range allowedPrefixes {
		if strings.HasPrefix(trimmedLine, p) {
			return true
		}
	}
	return false
}

func braceBalanceOren(src []byte) (bal int, min int) {
	// Heuristic scanner:
	// - ignores braces inside double-quoted string literals
	// - ignores braces after `//` comment starts (when not in a string)
	inString := false
	escape := false
	min = 0
	for i := 0; i < len(src); i++ {
		ch := src[i]

		if inString {
			if escape {
				escape = false
				continue
			}
			if ch == '\\' {
				escape = true
				continue
			}
			if ch == '"' {
				inString = false
			}
			continue
		}

		// Line comment
		if ch == '/' && i+1 < len(src) && src[i+1] == '/' {
			// Skip to end of line (or EOF).
			for i < len(src) && src[i] != '\n' {
				i++
			}
			continue
		}

		if ch == '"' {
			inString = true
			escape = false
			continue
		}

		if ch == '{' {
			bal++
			continue
		}
		if ch == '}' {
			bal--
			if bal < min {
				min = bal
			}
			continue
		}
	}
	return bal, min
}

func parseSyscallBlocks(path string, src string) []syscallBlock {
	// Heuristic parser: split the syscall lowering function into blocks beginning at:
	//   if fn_name == "sys_..."
	// The Oren source is stable enough for this audit, and we don't want a full parser here.
	//
	// Important: only treat *top-level* syscall cases as block starts.
	// In `arm64_native_expr_syscalls.oren`, nested `if fn_name == ...` checks can appear
	// inside a larger syscall block (e.g. `sys_send`/`sys_recv`). Those must not split blocks.
	//
	//
	// Convention today:
	// - arm64: top-level syscall cases are indented by exactly 8 spaces:
	//     `        if fn_name == "sys_..."`
	// - x86_64: syscall cases in the syscall lowering chunk are indented by exactly 4 spaces:
	//     `    if nm == "sys_..."`
	//
	// Keep these conventions stable because they are part of the capsule regression guardrail.
	cleanPath := filepath.Clean(path)
	var prefixes []string
	if strings.HasSuffix(cleanPath, "arm64_native_expr_syscalls.oren") {
		prefixes = []string{"        if fn_name == \"sys_"}
	} else if strings.HasSuffix(cleanPath, filepath.Join("x64_native_program", "046_emit_sys_intrinsics.oren")) {
		prefixes = []string{"    if nm == \"sys_"}
	} else {
		return nil
	}

	var starts []int
	lines := strings.SplitAfter(src, "\n")
	offset := 0
	for _, line := range lines {
		for _, p := range prefixes {
			if strings.HasPrefix(line, p) {
				starts = append(starts, offset)
				break
			}
		}
		offset += len(line)
	}
	if len(starts) == 0 {
		return nil
	}

	var blocks []syscallBlock
	for i := range starts {
		start := starts[i]
		end := len(src)
		if i+1 < len(starts) {
			end = starts[i+1]
		}
		txt := src[start:end]
		headerEnd := strings.IndexByte(txt, '\n')
		header := txt
		if headerEnd >= 0 {
			header = txt[:headerEnd]
		}
		sysNames := extractSysNamesFromHeader(header)
		if len(sysNames) == 0 {
			continue
		}
		blocks = append(blocks, syscallBlock{sysNames: sysNames, text: txt})
	}
	return blocks
}

func extractSysNamesFromHeader(header string) []string {
	// Header examples:
	//   if fn_name == "sys_open" {
	//   if fn_name == "sys_getpeername" || fn_name == "sys_getsockname" {
	var out []string
	for _, part := range strings.Split(header, "\"") {
		if strings.HasPrefix(part, "sys_") {
			out = append(out, part)
		}
	}
	return out
}

func extractPrehookNames(text string) []string {
	// Extract references like:
	//   "name": "native_capsule_sys_open_pre"
	// Keep simple and deterministic.
	var out []string
	const needle = `native_capsule_sys_`
	for off := 0; ; {
		i := strings.Index(text[off:], needle)
		if i < 0 {
			break
		}
		pos := off + i
		rest := text[pos:]
		end := 0
		for end < len(rest) {
			ch := rest[end]
			if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' {
				end++
				continue
			}
			break
		}
		name := rest[:end]
		if strings.HasSuffix(name, "_pre") {
			out = append(out, name)
		}
		off = pos + 1
	}
	// Dedupe deterministically.
	sort.Strings(out)
	uniq := out[:0]
	for i, s := range out {
		if i == 0 || s != out[i-1] {
			uniq = append(uniq, s)
		}
	}
	return uniq
}

func init() {
	// Ensure stable behavior in macOS where PATH may differ between shells.
	if runtime.GOOS == "darwin" {
		// no-op; placeholder for future if needed.
	}
}
