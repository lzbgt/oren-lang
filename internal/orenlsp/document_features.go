package orenlsp

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"oren/pkg/token"
)

type documentLink struct {
	Range  diagnosticRange `json:"range"`
	Target string          `json:"target"`
}

type workspaceSymbol struct {
	Name          string   `json:"name"`
	Kind          int      `json:"kind"`
	Location      location `json:"location"`
	ContainerName string   `json:"containerName,omitempty"`
}

type foldingRange struct {
	StartLine      int    `json:"startLine"`
	StartCharacter int    `json:"startCharacter,omitempty"`
	EndLine        int    `json:"endLine"`
	EndCharacter   int    `json:"endCharacter,omitempty"`
	Kind           string `json:"kind,omitempty"`
}

func (s *Server) documentLinks(uri string) []documentLink {
	text := s.docs[uri]
	currentPath, ok := filePathFromURI(uri)
	if !ok {
		return []documentLink{}
	}
	currentDir := filepath.Dir(currentPath)
	repoRoot := findRepoRoot(currentDir)
	tokens := sourceTokens(text)
	links := make([]documentLink, 0)
	for i, tok := range tokens {
		if tok.Type != token.IMPORT || i+2 >= len(tokens) {
			continue
		}
		if tokens[i+1].Type != token.IDENT && tokens[i+1].Type != token.DOT {
			continue
		}
		spec := tokens[i+2]
		if spec.Type != token.STRING || spec.Literal == "" {
			continue
		}
		path, ok := resolveImportPath(spec.Literal, currentDir, repoRoot)
		if !ok {
			continue
		}
		if _, err := os.Stat(path); err != nil {
			continue
		}
		links = append(links, documentLink{Range: stringTokenRange(text, spec), Target: fileURIFromPath(path)})
	}
	return links
}

func (s *Server) workspaceSymbols(query string) []workspaceSymbol {
	query = strings.ToLower(strings.TrimSpace(query))
	docs := s.workspaceSymbolDocuments()
	out := make([]workspaceSymbol, 0)
	for _, doc := range docs {
		for _, sym := range collectSymbols(doc.Text) {
			if query != "" && !strings.Contains(strings.ToLower(sym.Name), query) {
				continue
			}
			out = append(out, workspaceSymbol{
				Name:          sym.Name,
				Kind:          symbolKind(sym.Kind),
				Location:      location{URI: doc.URI, Range: sym.Range},
				ContainerName: doc.URI,
			})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Name != out[j].Name {
			return out[i].Name < out[j].Name
		}
		if out[i].Location.URI != out[j].Location.URI {
			return out[i].Location.URI < out[j].Location.URI
		}
		return out[i].Location.Range.Start.Line < out[j].Location.Range.Start.Line
	})
	return out
}

func (s *Server) workspaceSymbolDocuments() []documentSnapshot {
	uris := make([]string, 0, len(s.docs))
	for uri := range s.docs {
		uris = append(uris, uri)
	}
	sort.Strings(uris)
	docs := make([]documentSnapshot, 0, len(uris))
	seen := map[string]bool{}
	for _, uri := range uris {
		text := s.docs[uri]
		docs = append(docs, documentSnapshot{URI: uri, Text: text})
		seen[uri] = true
		for _, imported := range s.importedDocumentSnapshots(uri, text) {
			if seen[imported.URI] {
				continue
			}
			seen[imported.URI] = true
			docs = append(docs, imported)
		}
	}
	return docs
}

func foldingRanges(text string) []foldingRange {
	tokens := sourceTokens(text)
	stack := make([]token.Token, 0)
	out := make([]foldingRange, 0)
	for _, tok := range tokens {
		switch tok.Type {
		case token.LBRACE:
			stack = append(stack, tok)
		case token.RBRACE:
			if len(stack) == 0 {
				continue
			}
			open := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			start := tokenRange(open)
			end := tokenRange(tok)
			if end.Start.Line <= start.Start.Line {
				continue
			}
			out = append(out, foldingRange{
				StartLine:      start.Start.Line,
				StartCharacter: start.Start.Character,
				EndLine:        end.End.Line,
				EndCharacter:   end.End.Character,
				Kind:           "region",
			})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].StartLine != out[j].StartLine {
			return out[i].StartLine < out[j].StartLine
		}
		return out[i].StartCharacter < out[j].StartCharacter
	})
	return out
}

func stringTokenRange(text string, tok token.Token) diagnosticRange {
	startLine := tok.Line - 1
	startChar := tok.Column - 1
	endChar := startChar + len(tok.Literal) + 2
	lines := strings.Split(text, "\n")
	if startLine >= 0 && startLine < len(lines) {
		line := []rune(lines[startLine])
		if startChar >= 0 && startChar < len(line) && line[startChar] == '"' {
			escaped := false
			for i := startChar + 1; i < len(line); i++ {
				if escaped {
					escaped = false
					continue
				}
				if line[i] == '\\' {
					escaped = true
					continue
				}
				if line[i] == '"' {
					endChar = i + 1
					break
				}
			}
		}
	}
	return diagnosticRange{
		Start: position{Line: startLine, Character: startChar},
		End:   position{Line: startLine, Character: endChar},
	}
}
