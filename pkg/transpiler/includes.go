package transpiler

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ExpandIncludes expands `// @include "path"` directives recursively.
//
// This is a purpose-built textual include used for splitting very large `.oren`
// files without changing module namespaces.
//
// It is intentionally *not* Oren's `import` system.
func ExpandIncludes(entryPath string) (string, error) {
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

			out.WriteString(line)
			if i != len(lines)-1 || strings.HasSuffix(src, "\n") {
				out.WriteString("\n")
			}
		}

		return out.String(), nil
	}

	return rec(entryPath, nil)
}

