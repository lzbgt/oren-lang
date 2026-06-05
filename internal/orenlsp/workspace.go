package orenlsp

import (
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type documentSnapshot struct {
	URI  string
	Text string
}

func (s *Server) openDocumentDefinitionLocations(uri, name string) []location {
	for _, doc := range s.openDocumentSnapshots(uri) {
		if locs := symbolDefinitionLocations(doc.Text, doc.URI, name); len(locs) > 0 {
			return locs
		}
	}
	return []location{}
}

func (s *Server) importedDefinitionLocations(uri, text, name string) []location {
	for _, doc := range s.importedDocumentSnapshots(uri, text) {
		if locs := symbolDefinitionLocations(doc.Text, doc.URI, name); len(locs) > 0 {
			return locs
		}
	}
	return []location{}
}

func (s *Server) openDocumentSnapshots(excludeURI string) []documentSnapshot {
	uris := make([]string, 0, len(s.docs))
	for candidateURI := range s.docs {
		if candidateURI != excludeURI {
			uris = append(uris, candidateURI)
		}
	}
	sort.Strings(uris)
	out := make([]documentSnapshot, 0, len(uris))
	for _, candidateURI := range uris {
		out = append(out, documentSnapshot{URI: candidateURI, Text: s.docs[candidateURI]})
	}
	return out
}

func (s *Server) importedDocumentSnapshots(uri, text string) []documentSnapshot {
	imports := collectImports(text)
	if len(imports) == 0 {
		return nil
	}
	currentPath, ok := filePathFromURI(uri)
	if !ok {
		return nil
	}
	currentDir := filepath.Dir(currentPath)
	repoRoot := findRepoRoot(currentDir)
	seen := map[string]bool{}
	var out []documentSnapshot
	for _, imp := range imports {
		path, ok := resolveImportPath(imp.Spec, currentDir, repoRoot)
		if !ok {
			continue
		}
		candidateURI := fileURIFromPath(path)
		if seen[candidateURI] {
			continue
		}
		seen[candidateURI] = true
		candidateText, ok := s.docs[candidateURI]
		if !ok {
			raw, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			candidateText = string(raw)
		}
		out = append(out, documentSnapshot{URI: candidateURI, Text: candidateText})
	}
	return out
}

func resolveImportPath(spec, currentDir, repoRoot string) (string, bool) {
	if spec == "" {
		return "", false
	}
	if strings.HasPrefix(spec, "std:") || strings.HasPrefix(spec, "std/") {
		if repoRoot == "" {
			return "", false
		}
		key := strings.TrimPrefix(spec, "std:")
		key = strings.TrimPrefix(key, "std/")
		key = strings.TrimSuffix(key, ".oren")
		return filepath.Join(repoRoot, "lib", "std", filepath.FromSlash(key)+".oren"), true
	}
	if filepath.IsAbs(spec) {
		return ensureOrenExt(filepath.Clean(spec)), true
	}
	return ensureOrenExt(filepath.Clean(filepath.Join(currentDir, filepath.FromSlash(spec)))), true
}

func ensureOrenExt(path string) string {
	if strings.HasSuffix(path, ".oren") {
		return path
	}
	return path + ".oren"
}

func findRepoRoot(start string) string {
	dir := filepath.Clean(start)
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func filePathFromURI(uri string) (string, bool) {
	u, err := url.Parse(uri)
	if err != nil || u.Scheme != "file" || u.Path == "" {
		return "", false
	}
	return filepath.Clean(filepath.FromSlash(u.Path)), true
}

func fileURIFromPath(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		abs = path
	}
	return (&url.URL{Scheme: "file", Path: filepath.ToSlash(abs)}).String()
}
