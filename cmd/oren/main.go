package main

import (
	"bufio"
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
			dat, err := os.ReadFile(os.Args[2])
			if err != nil {
				panic(err)
			}
			l := lexer.New(string(dat))
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
				cc = "cc"
			}
			codesignID := os.Getenv("OREN_CODESIGN_ID")
			if codesignID == "" && runtime.GOOS == "darwin" {
				codesignID = "Developer ID Application: Zongbao Lu (US56HHF2Y4)"
			}
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

			dat, err := os.ReadFile(filename)
			if err != nil {
				panic(err)
			}
			l := lexer.New(string(dat))
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

			args := []string{"-o", outFilename, cFilename, "lib/runtime.c", "-Ilib", "-pthread"}
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

			cmd := exec.Command(cc, args...)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			err = cmd.Run()
			if err != nil {
				fmt.Printf("Compilation failed: %v\n", err)
				os.Exit(1)
			}

			if target == "macos" && codesignID != "" {
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
