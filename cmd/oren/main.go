package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"oren/pkg/eval"
	"oren/pkg/lexer"
	"oren/pkg/parser"
	"oren/pkg/transpiler"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const PROMPT = ">> "

func Start(in io.Reader, out io.Writer) {
	scanner := bufio.NewScanner(in)
	env := eval.NewEnvironment()

	for {
		fmt.Printf(PROMPT)
		scanned := scanner.Scan()
		if !scanned {
			return
		}

		line := scanner.Text()
		l := lexer.New(line)
		p := parser.New(l)

		program := p.ParseProgram()
		if len(p.Errors()) != 0 {
			printParserErrors(out, p.Errors())
			continue
		}

		evaluated := eval.Eval(program, env)
		if evaluated != nil {
			io.WriteString(out, evaluated.Inspect())
			io.WriteString(out, "\n")
		}
	}
}

func printParserErrors(out io.Writer, errors []string) {
	io.WriteString(out, "Woops! We ran into some monkey business here!\n")
	io.WriteString(out, " parser errors:\n")
	for _, msg := range errors {
		io.WriteString(out, "\t"+msg+"\n")
	}
}

func isMSVCCompiler(cc string) bool {
	ccBase := strings.ToLower(filepath.Base(cc))
	return ccBase == "cl" || ccBase == "cl.exe" || ccBase == "clang-cl" || ccBase == "clang-cl.exe"
}

func cmdQuote(s string) string {
	// Minimal quoting for cmd.exe /c strings.
	// This is not a full Windows command-line roundtripper, but is sufficient for the
	// bootstrap path (filenames + flags).
	if s == "" {
		return "\"\""
	}
	// If quotes appear, escape them for cmd by doubling (best-effort).
	needsQuote := strings.IndexAny(s, " \t") != -1
	if strings.Contains(s, "\"") {
		needsQuote = true
		s = strings.ReplaceAll(s, "\"", "\"\"")
	}
	if !needsQuote {
		return s
	}
	return "\"" + s + "\""
}

type pythonEmbedInfo struct {
	Include     string `json:"include"`
	PlatInclude string `json:"plat_include"`
	LibDir      string `json:"libdir"`
	LibPl       string `json:"libpl"`
	LdLibrary   string `json:"ldlibrary"`
	Library     string `json:"library"`
	BasePrefix  string `json:"base_prefix"`
	Prefix      string `json:"prefix"`
	Version     string `json:"version"`
}

func pythonEmbedInfoFromCmd(cmdArgs []string) (pythonEmbedInfo, error) {
	if len(cmdArgs) == 0 {
		return pythonEmbedInfo{}, fmt.Errorf("empty python command")
	}
	script := strings.Join([]string{
		"import json, sys, sysconfig",
		"def get(k):",
		"    v = sysconfig.get_config_var(k)",
		"    return v if v is not None else ''",
		"data = {",
		"    'include': sysconfig.get_path('include') or '',",
		"    'plat_include': sysconfig.get_path('platinclude') or '',",
		"    'libdir': get('LIBDIR'),",
		"    'libpl': get('LIBPL'),",
		"    'ldlibrary': get('LDLIBRARY'),",
		"    'library': get('LIBRARY'),",
		"    'base_prefix': getattr(sys, 'base_prefix', ''),",
		"    'prefix': getattr(sys, 'prefix', ''),",
		"    'version': sysconfig.get_python_version() or '',",
		"}",
		"print(json.dumps(data))",
	}, "\n")
	args := append([]string{}, cmdArgs[1:]...)
	args = append(args, "-c", script)
	out, err := exec.Command(cmdArgs[0], args...).CombinedOutput()
	if err != nil {
		return pythonEmbedInfo{}, fmt.Errorf("python embed probe failed (%s): %v (%s)", cmdArgs[0], err, strings.TrimSpace(string(out)))
	}
	var info pythonEmbedInfo
	if err := json.Unmarshal(out, &info); err != nil {
		return pythonEmbedInfo{}, fmt.Errorf("python embed probe returned invalid JSON: %v (%s)", err, strings.TrimSpace(string(out)))
	}
	return info, nil
}

func pythonEmbedInfoDetect() (pythonEmbedInfo, error) {
	if env := strings.TrimSpace(os.Getenv("OREN_PYTHON")); env != "" {
		env = strings.Trim(env, "\"")
		if _, err := os.Stat(env); err == nil {
			return pythonEmbedInfoFromCmd([]string{env})
		}
		cmd := strings.Fields(env)
		if len(cmd) > 0 {
			return pythonEmbedInfoFromCmd(cmd)
		}
	}
	candidates := [][]string{
		{"python3"},
		{"python"},
		{"py", "-3"},
	}
	var lastErr error
	for _, cmd := range candidates {
		info, err := pythonEmbedInfoFromCmd(cmd)
		if err == nil {
			return info, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no python interpreter found")
	}
	return pythonEmbedInfo{}, lastErr
}

func pythonEmbedFlagsMSVC() ([]string, error) {
	info, err := pythonEmbedInfoDetect()
	if err != nil {
		return nil, err
	}
	includes := []string{}
	if info.Include != "" {
		includes = append(includes, info.Include)
	}
	if info.PlatInclude != "" && info.PlatInclude != info.Include {
		includes = append(includes, info.PlatInclude)
	}
	if len(includes) == 0 {
		return nil, fmt.Errorf("python embed probe did not report include paths")
	}
	libName := info.LdLibrary
	if libName == "" {
		libName = info.Library
	}
	if libName == "" && info.Version != "" {
		verParts := strings.Split(info.Version, ".")
		if len(verParts) >= 2 {
			libName = "python" + verParts[0] + verParts[1] + ".lib"
		}
	}
	if libName == "" {
		return nil, fmt.Errorf("python embed probe did not report library name")
	}
	libDirs := []string{}
	for _, d := range []string{info.LibPl, info.LibDir} {
		if d != "" {
			libDirs = append(libDirs, d)
		}
	}
	if info.Prefix != "" {
		libDirs = append(libDirs, filepath.Join(info.Prefix, "libs"))
	}
	if info.BasePrefix != "" && info.BasePrefix != info.Prefix {
		libDirs = append(libDirs, filepath.Join(info.BasePrefix, "libs"))
	}
	uniqLibDirs := []string{}
	seen := map[string]bool{}
	for _, d := range libDirs {
		if d == "" {
			continue
		}
		if seen[d] {
			continue
		}
		seen[d] = true
		uniqLibDirs = append(uniqLibDirs, d)
	}
	libDirs = uniqLibDirs
	if len(libDirs) == 0 {
		return nil, fmt.Errorf("python embed probe did not report library directories (set OREN_PYTHON to a Python with dev headers)")
	}
	flags := []string{"/DOREN_ENABLE_PYTHON"}
	for _, inc := range includes {
		flags = append(flags, "/I"+inc)
	}
	flags = append(flags, "/link")
	for _, dir := range libDirs {
		flags = append(flags, "/LIBPATH:"+dir)
	}
	flags = append(flags, libName)
	return flags, nil
}

type msvcDevCmd struct {
	path string
	args []string
}

func msvcDevCmdFromInstallPath(installPath string) (msvcDevCmd, error) {
	vsDevCmd := filepath.Join(installPath, "Common7", "Tools", "VsDevCmd.bat")
	if _, err := os.Stat(vsDevCmd); err == nil {
		return msvcDevCmd{
			path: vsDevCmd,
			// VsDevCmd supports selecting host + target arch.
			args: []string{"-arch=amd64", "-host_arch=amd64", "-no_logo"},
		}, nil
	}
	vcvars64 := filepath.Join(installPath, "VC", "Auxiliary", "Build", "vcvars64.bat")
	if _, err := os.Stat(vcvars64); err == nil {
		// vcvars64 sets up a 64-bit target environment and does not accept VsDevCmd-style args.
		return msvcDevCmd{path: vcvars64}, nil
	}
	return msvcDevCmd{}, fmt.Errorf("found VS install at %q but could not find VsDevCmd.bat or vcvars64.bat", installPath)
}

func msvcDevCmdFromExplicitPath(p string) (msvcDevCmd, error) {
	p = strings.TrimSpace(p)
	if p == "" {
		return msvcDevCmd{}, fmt.Errorf("empty MSVC devcmd path")
	}
	if _, err := os.Stat(p); err != nil {
		return msvcDevCmd{}, fmt.Errorf("MSVC devcmd path not found: %q (%v)", p, err)
	}
	base := strings.ToLower(filepath.Base(p))
	// VsDevCmd supports selecting host + target arch.
	if base == "vsdevcmd.bat" {
		return msvcDevCmd{
			path: p,
			args: []string{"-arch=amd64", "-host_arch=amd64", "-no_logo"},
		}, nil
	}
	// vcvars64 sets up a 64-bit target environment and does not accept VsDevCmd-style args.
	if base == "vcvars64.bat" {
		return msvcDevCmd{path: p}, nil
	}
	// Accept other batch files too (best-effort).
	return msvcDevCmd{path: p}, nil
}

func findMSVCDevCmd() (msvcDevCmd, error) {
	// Escape hatch: force the exact devcmd script path directly.
	// This is useful for custom VS install paths and CI images.
	if devCmd := strings.TrimSpace(os.Getenv("OREN_MSVC_DEV_CMD")); devCmd != "" {
		return msvcDevCmdFromExplicitPath(devCmd)
	}

	// Escape hatch: allow pinning the VS installation path directly, so bootstrap works
	// even if vswhere.exe is missing/unreachable in the environment.
	if installPath := strings.TrimSpace(os.Getenv("OREN_MSVC_INSTALL_PATH")); installPath != "" {
		return msvcDevCmdFromInstallPath(installPath)
	}

	// Prefer vswhere.exe in the standard installer location.
	var candidates []string
	if v := strings.TrimSpace(os.Getenv("OREN_MSVC_VSWHERE")); v != "" {
		candidates = append(candidates, v)
	}
	if pf86 := os.Getenv("ProgramFiles(x86)"); pf86 != "" {
		candidates = append(candidates, filepath.Join(pf86, "Microsoft Visual Studio", "Installer", "vswhere.exe"))
	}
	if pf := os.Getenv("ProgramFiles"); pf != "" {
		candidates = append(candidates, filepath.Join(pf, "Microsoft Visual Studio", "Installer", "vswhere.exe"))
	}
	if p, err := exec.LookPath("vswhere.exe"); err == nil {
		candidates = append(candidates, p)
	}

	var vswhere string
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			vswhere = c
			break
		}
	}
	if vswhere == "" {
		return msvcDevCmd{}, fmt.Errorf("vswhere.exe not found (install Visual Studio 2022 Build Tools / VS2022, or set PATH; override with OREN_MSVC_VSWHERE or OREN_MSVC_INSTALL_PATH)")
	}

	out, err := exec.Command(vswhere,
		"-latest",
		"-products", "*",
		"-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
		"-property", "installationPath",
	).Output()
	if err != nil {
		return msvcDevCmd{}, fmt.Errorf("vswhere.exe failed: %w", err)
	}
	installPath := strings.TrimSpace(string(out))
	if installPath == "" {
		return msvcDevCmd{}, fmt.Errorf("vswhere.exe did not return an installationPath (MSVC toolchain not installed?)")
	}

	return msvcDevCmdFromInstallPath(installPath)
}

func main() {
	prog := filepath.Base(os.Args[0])
	// If args are provided, we should run file or build.
	// For now, let's just default to REPL if no args.
	if len(os.Args) == 1 {
		fmt.Printf("Hello! This is the Oren programming language!\n")
		fmt.Printf("Feel free to type in commands\n")
		Start(os.Stdin, os.Stdout)
	} else {
		// Simple file runner
		if os.Args[1] == "run" {
			// Read file
			src, err := transpiler.ExpandIncludes(os.Args[2])
			if err != nil {
				panic(err)
			}
			l := lexer.New(src)
			p := parser.New(l)
			program := p.ParseProgram()
			if len(p.Errors()) != 0 {
				printParserErrors(os.Stderr, p.Errors())
				os.Exit(1)
			}
			env := eval.NewEnvironment()
			eval.Eval(program, env)
		} else if os.Args[1] == "build" {
			if len(os.Args) < 3 {
				fmt.Printf("Usage: %s build <file.oren>\n", prog)
				os.Exit(1)
			}
			filename := os.Args[2]

				cc := os.Getenv("CC")
				if cc == "" {
					// Rolling Tier‑1 policy: on Windows hosts, prefer MSVC `cl.exe` by default so
					// stage0 bootstrap works from a plain shell (auto-configured via vswhere + VsDevCmd/vcvars).
					if runtime.GOOS == "windows" {
						cc = "cl.exe"
					} else {
						cc = "cc"
					}
				}
			codesignID := os.Getenv("OREN_CODESIGN_ID")
			noGC := os.Getenv("OREN_NO_GC") != ""
			notarize := false
			notaryProfile := os.Getenv("OREN_NOTARY_PROFILE")
			enablePython := false
			emitC := false
			target := "macos"
			outFilename := strings.TrimSuffix(filename, ".oren")

			i := 3
			for i < len(os.Args) {
				switch os.Args[i] {
				case "--emit-c":
					emitC = true
					i++
				case "--python":
					enablePython = true
					i++
				case "--target":
					if i+1 >= len(os.Args) {
						fmt.Printf("Missing value for --target\n")
						os.Exit(1)
					}
					target = os.Args[i+1]
					i += 2
				case "--cc":
					if i+1 >= len(os.Args) {
						fmt.Printf("Missing value for --cc\n")
						os.Exit(1)
					}
					cc = os.Args[i+1]
					i += 2
				case "--codesign":
					if i+1 >= len(os.Args) {
						fmt.Printf("Missing value for --codesign\n")
						os.Exit(1)
					}
					codesignID = os.Args[i+1]
					i += 2
				case "--notarize":
					notarize = true
					i++
				case "--notary-profile":
					if i+1 >= len(os.Args) {
						fmt.Printf("Missing value for --notary-profile\n")
						os.Exit(1)
					}
					notaryProfile = os.Args[i+1]
					i += 2
				case "--no-gc":
					noGC = true
					i++
				case "-o":
					if i+1 >= len(os.Args) {
						fmt.Printf("Missing value for -o\n")
						os.Exit(1)
					}
					outFilename = os.Args[i+1]
					i += 2
				default:
					fmt.Printf("Unknown arg: %s\n", os.Args[i])
					os.Exit(1)
				}
			}

			if runtime.GOOS == "darwin" && target == "macos" && os.Getenv("OREN_SKIP_CODESIGN") == "1" {
				fmt.Printf("OREN_SKIP_CODESIGN=1 is not supported on macOS; unsigned native outputs may be killed by the OS\n")
				os.Exit(2)
			}
			if runtime.GOOS == "darwin" && target == "macos" && codesignID == "" {
				// Default to ad-hoc signing so the output is runnable without a certificate.
				codesignID = "-"
			}
			if notarize && target == "macos" && (codesignID == "" || codesignID == "-") {
				fmt.Printf("Notarization requested but codesign is disabled (set --codesign or OREN_CODESIGN_ID)\n")
				os.Exit(1)
			}

			src, err := transpiler.ExpandIncludes(filename)
			if err != nil {
				panic(err)
			}
			l := lexer.New(src)
			p := parser.New(l)
			program := p.ParseProgram()
			if len(p.Errors()) != 0 {
				printParserErrors(os.Stderr, p.Errors())
				os.Exit(1)
			}

			t := transpiler.NewWithBaseDir(filepath.Dir(filename))
			cCode, err := t.Transpile(program)
			if err != nil {
				fmt.Printf("Transpilation error: %v\n", err)
				os.Exit(1)
			}

			// Write to temporary C file
			cFilename := filename + ".c"
			err = os.WriteFile(cFilename, []byte(cCode), 0644)
			if err != nil {
				panic(err)
			}

			if emitC {
				fmt.Printf("Wrote %s\n", cFilename)
				return
			}

			isMSVC := isMSVCCompiler(cc)

			var args []string
				if isMSVC {
					// MSVC `cl` does compile+link in one step by default.
					// Keep this minimal and deterministic: stage0 is a bootstrap path.
					args = []string{"/nologo", "/std:c11", "/Fe:" + outFilename, cFilename, "lib/runtime.c", "lib/runtime_buf.c", "/Ilib"}
					if noGC {
						args = append(args, "/DOREN_NO_GC")
					}
					if enablePython {
						pyFlags, err := pythonEmbedFlagsMSVC()
						if err != nil {
							fmt.Printf("ERROR: --python MSVC setup failed: %v\n", err)
							os.Exit(2)
						}
						args = append(args, pyFlags...)
					}
				} else {
				args = []string{"-o", outFilename, cFilename, "lib/runtime.c", "lib/runtime_buf.c", "-Ilib", "-pthread"}
				if noGC {
					args = append(args, "-DOREN_NO_GC")
				}

				if enablePython {
					args = append(args, "-DOREN_ENABLE_PYTHON")

					pyCFlagsCmd := exec.Command("python3-config", "--cflags")
					pyCFlagsOut, err := pyCFlagsCmd.Output()
					if err != nil {
						panic(err)
					}
					pyLdFlagsCmd := exec.Command("python3-config", "--embed", "--ldflags")
					pyLdFlagsOut, err := pyLdFlagsCmd.Output()
					if err != nil {
						panic(err)
					}

					cFlags := strings.Fields(string(pyCFlagsOut))
					ldFlags := strings.Fields(string(pyLdFlagsOut))
					args = append(args, cFlags...)
					args = append(args, ldFlags...)
				}
			}

			var cmd *exec.Cmd
			if isMSVC && runtime.GOOS == "windows" {
				// `cl.exe` is typically not in PATH unless you're in a VS Developer Prompt.
				// In rolling mode, `make oren` on Windows should be able to find VS2022 and run `cl`.
				devCmd, err := findMSVCDevCmd()
				if err != nil {
					fmt.Printf("ERROR: MSVC toolchain setup failed: %v\n", err)
					os.Exit(2)
				}

				// IMPORTANT: avoid embedding quotes in the `cmd.exe /c "<...>"` argument itself.
				// Go's Windows process spawning escapes embedded quotes with backslashes, and cmd.exe
				// does not treat `\"` as a quoting mechanism. Use a temporary `.cmd` file instead.
				wd, err := os.Getwd()
				if err != nil {
					fmt.Printf("ERROR: cannot get cwd for MSVC bootstrap: %v\n", err)
					os.Exit(2)
				}
				f, err := os.CreateTemp(wd, "oren_msvc_build_*.cmd")
				if err != nil {
					fmt.Printf("ERROR: cannot create MSVC bootstrap script: %v\n", err)
					os.Exit(2)
				}
				scriptPath := f.Name()
				scriptName := filepath.Base(scriptPath)
				defer os.Remove(scriptPath)

				var b strings.Builder
				b.WriteString("@echo off\r\n")
				b.WriteString("call ")
				b.WriteString(cmdQuote(devCmd.path))
				for _, a := range devCmd.args {
					b.WriteString(" ")
					b.WriteString(cmdQuote(a))
				}
				b.WriteString("\r\n")
				b.WriteString("if errorlevel 1 exit /b %errorlevel%\r\n")
				b.WriteString(cmdQuote(cc))
				for _, a := range args {
					b.WriteString(" ")
					b.WriteString(cmdQuote(a))
				}
				b.WriteString("\r\n")
				b.WriteString("exit /b %errorlevel%\r\n")

				if _, err := f.WriteString(b.String()); err != nil {
					_ = f.Close()
					fmt.Printf("ERROR: cannot write MSVC bootstrap script: %v\n", err)
					os.Exit(2)
				}
				if err := f.Close(); err != nil {
					fmt.Printf("ERROR: cannot close MSVC bootstrap script: %v\n", err)
					os.Exit(2)
				}

				cmd = exec.Command("cmd.exe", "/d", "/c", scriptName)
				cmd.Dir = wd
			} else {
				cmd = exec.Command(cc, args...)
			}
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			err = cmd.Run()
			if err != nil {
				fmt.Printf("Compilation failed: %v\n", err)
				os.Exit(1)
			}

			if runtime.GOOS == "darwin" && target == "macos" && codesignID != "" {
				cs := exec.Command("codesign", "-s", codesignID, "--force", outFilename)
				cs.Stdout = os.Stdout
				cs.Stderr = os.Stderr
				if err := cs.Run(); err != nil {
					fmt.Printf("codesign failed with %q (%v), retrying ad-hoc...\n", codesignID, err)
					ad := exec.Command("codesign", "-s", "-", "--force", outFilename)
					ad.Stdout = os.Stdout
					ad.Stderr = os.Stderr
					if err2 := ad.Run(); err2 != nil {
						fmt.Printf("codesign fallback failed: %v\n", err2)
						os.Exit(1)
					}
				}
			}

			if target == "macos" && notarize {
				var args []string
				if notaryProfile != "" {
					args = []string{"notarytool", "submit", outFilename, "--keychain-profile", notaryProfile, "--wait"}
				} else {
					appleID := os.Getenv("APPLE_ID")
					applePass := os.Getenv("APPLE_ID_PASS")
					teamID := os.Getenv("APPLE_TEAM_ID")
					if appleID == "" || applePass == "" || teamID == "" {
						fmt.Printf("Notarization requested but APPLE_ID/APPLE_ID_PASS/APPLE_TEAM_ID or --notary-profile not set\n")
						os.Exit(1)
					}
					args = []string{"notarytool", "submit", outFilename, "--apple-id", appleID, "--password", applePass, "--team-id", teamID, "--wait"}
				}
				nt := exec.Command(args[0], args[1:]...)
				nt.Stdout = os.Stdout
				nt.Stderr = os.Stderr
				if err := nt.Run(); err != nil {
					fmt.Printf("notarization failed: %v\n", err)
					os.Exit(1)
				}
				staple := exec.Command("stapler", "staple", outFilename)
				staple.Stdout = os.Stdout
				staple.Stderr = os.Stderr
				if err := staple.Run(); err != nil {
					fmt.Printf("staple failed: %v\n", err)
					os.Exit(1)
				}
			}

			fmt.Printf("Build successful: %s\n", outFilename)

		} else {
			fmt.Printf("Unknown command. Use '%s run <file>', '%s build <file>' or just run '%s' for REPL.\n", prog, prog, prog)
		}
	}
}
