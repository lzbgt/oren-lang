package obcstore

import (
	"fmt"
	"html"
	"html/template"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"unicode"
	"unicode/utf8"
)

const maxPortalSourceBytes = 512 * 1024

type SourceLine struct {
	Number int
	HTML   template.HTML
}

type SourceOutlineItem struct {
	Kind string
	Name string
	Line int
}

type SourceView struct {
	Meta    PackageMeta
	Release ReleaseMeta
	Source  SiteSourceLink
	Lines   []SourceLine
	Outline []SourceOutlineItem
}

type sourceToken struct {
	Kind string
	Text string
}

func sourceViewURL(pub, name, version, path string) string {
	return fmt.Sprintf("/packages/%s/%s/source?version=%s&path=%s", pub, name, url.QueryEscape(version), url.QueryEscape(path))
}

func (s *Service) handleSiteSource(w http.ResponseWriter, r *http.Request, pub, name string) {
	version := r.URL.Query().Get("version")
	path := r.URL.Query().Get("path")
	if !safeVersion(version) || !safeRelPath(path) || !strings.HasPrefix(path, "assets/") {
		http.NotFound(w, r)
		return
	}
	meta, err := readJSONFile[PackageMeta](s.packageMetaPath(pub, name))
	if err != nil || !packageIsPublic(meta) {
		http.NotFound(w, r)
		return
	}
	release, err := readJSONFile[ReleaseMeta](filepath.Join(s.releaseDir(pub, name, version), "release.json"))
	if err != nil || release.Status != "published" {
		http.NotFound(w, r)
		return
	}
	dir := s.releaseDir(pub, name, version)
	manifest, err := readJSONFile[map[string]any](filepath.Join(dir, "package.json"))
	if err != nil || !manifestDeclaresSource(manifest, path) || !releaseManifestDeclaresAsset(dir, path) {
		http.NotFound(w, r)
		return
	}
	body, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(path)))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if len(body) > maxPortalSourceBytes {
		http.Error(w, "source asset too large for portal rendering", http.StatusRequestEntityTooLarge)
		return
	}
	source := SiteSourceLink{
		Path:     path,
		Language: fmt.Sprint(sourceManifestField(manifest, path, "language")),
		Role:     fmt.Sprint(sourceManifestField(manifest, path, "role")),
		URL:      sourceViewURL(pub, name, version, path),
	}
	text := strings.ReplaceAll(string(body), "\r\n", "\n")
	renderHTML(w, siteSourceTemplate, SourceView{
		Meta:    meta,
		Release: release,
		Source:  source,
		Lines:   highlightOrenSource(text),
		Outline: outlineOrenSource(text),
	})
}

func manifestDeclaresSource(manifest map[string]any, path string) bool {
	rawSources, ok := manifest["sources"].([]any)
	if !ok {
		return false
	}
	for _, raw := range rawSources {
		src, ok := raw.(map[string]any)
		if ok && fmt.Sprint(src["path"]) == path {
			return true
		}
	}
	return false
}

func sourceManifestField(manifest map[string]any, path, field string) any {
	rawSources, _ := manifest["sources"].([]any)
	for _, raw := range rawSources {
		src, ok := raw.(map[string]any)
		if ok && fmt.Sprint(src["path"]) == path {
			return src[field]
		}
	}
	return ""
}

func highlightOrenSource(source string) []SourceLine {
	lines := strings.Split(source, "\n")
	out := make([]SourceLine, 0, len(lines))
	for i, line := range lines {
		tokens := classifyOrenTokens(lexOrenLine(line))
		var b strings.Builder
		for _, tok := range tokens {
			if tok.Kind == "space" {
				b.WriteString(html.EscapeString(tok.Text))
				continue
			}
			b.WriteString(`<span class="tok-`)
			b.WriteString(tok.Kind)
			b.WriteString(`">`)
			b.WriteString(html.EscapeString(tok.Text))
			b.WriteString(`</span>`)
		}
		out = append(out, SourceLine{Number: i + 1, HTML: template.HTML(b.String())})
	}
	return out
}

func outlineOrenSource(source string) []SourceOutlineItem {
	lines := strings.Split(source, "\n")
	out := make([]SourceOutlineItem, 0)
	for i, line := range lines {
		tokens := classifyOrenTokens(lexOrenLine(line))
		words := significantTokens(tokens)
		for j, tok := range words {
			if tok.Kind != "keyword" {
				continue
			}
			switch tok.Text {
			case "import":
				if j+1 < len(words) && (words[j+1].Kind == "decl" || words[j+1].Kind == "ident") {
					out = append(out, SourceOutlineItem{Kind: "import", Name: words[j+1].Text, Line: i + 1})
				}
			case "fn", "struct", "class", "trait":
				if j+1 < len(words) && (words[j+1].Kind == "decl" || words[j+1].Kind == "ident") {
					out = append(out, SourceOutlineItem{Kind: tok.Text, Name: words[j+1].Text, Line: i + 1})
				}
			case "impl":
				name := implOutlineName(words[j+1:])
				if name != "" {
					out = append(out, SourceOutlineItem{Kind: "impl", Name: name, Line: i + 1})
				}
			}
		}
	}
	return out
}

func significantTokens(tokens []sourceToken) []sourceToken {
	out := make([]sourceToken, 0, len(tokens))
	for _, tok := range tokens {
		if tok.Kind != "space" && tok.Kind != "comment" {
			out = append(out, tok)
		}
	}
	return out
}

func implOutlineName(tokens []sourceToken) string {
	parts := make([]string, 0, 4)
	for _, tok := range tokens {
		if tok.Text == "{" {
			break
		}
		if tok.Kind == "ident" || tok.Kind == "decl" || tok.Kind == "keyword" || tok.Text == "." {
			parts = append(parts, tok.Text)
		}
	}
	return strings.Join(parts, "")
}

func classifyOrenTokens(tokens []sourceToken) []sourceToken {
	for i := range tokens {
		if tokens[i].Kind == "ident" && isOrenKeyword(tokens[i].Text) {
			tokens[i].Kind = "keyword"
		}
	}
	for i := range tokens {
		if tokens[i].Kind != "keyword" || !isDeclKeyword(tokens[i].Text) {
			continue
		}
		for j := i + 1; j < len(tokens); j++ {
			if tokens[j].Kind == "space" {
				continue
			}
			if tokens[j].Kind == "ident" {
				tokens[j].Kind = "decl"
			}
			break
		}
	}
	for i := range tokens {
		if tokens[i].Kind != "ident" {
			continue
		}
		if nextNonSpace(tokens, i) == "(" {
			if prevNonSpace(tokens, i) == "." {
				tokens[i].Kind = "method"
			} else {
				tokens[i].Kind = "call"
			}
		}
	}
	return tokens
}

func lexOrenLine(line string) []sourceToken {
	var out []sourceToken
	for i := 0; i < len(line); {
		r, n := runeAt(line, i)
		if unicode.IsSpace(r) {
			start := i
			i += n
			for i < len(line) {
				r2, n2 := runeAt(line, i)
				if !unicode.IsSpace(r2) {
					break
				}
				i += n2
			}
			out = append(out, sourceToken{Kind: "space", Text: line[start:i]})
			continue
		}
		if r == '/' && i+1 < len(line) && line[i+1] == '/' {
			out = append(out, sourceToken{Kind: "comment", Text: line[i:]})
			break
		}
		if r == '"' {
			start := i
			i += n
			escaped := false
			for i < len(line) {
				r2, n2 := runeAt(line, i)
				i += n2
				if escaped {
					escaped = false
					continue
				}
				if r2 == '\\' {
					escaped = true
					continue
				}
				if r2 == '"' {
					break
				}
			}
			out = append(out, sourceToken{Kind: "string", Text: line[start:i]})
			continue
		}
		if unicode.IsDigit(r) {
			start := i
			i += n
			for i < len(line) {
				r2, n2 := runeAt(line, i)
				if !unicode.IsDigit(r2) && r2 != '_' && r2 != '.' {
					break
				}
				i += n2
			}
			out = append(out, sourceToken{Kind: "number", Text: line[start:i]})
			continue
		}
		if isIdentStart(r) {
			start := i
			i += n
			for i < len(line) {
				r2, n2 := runeAt(line, i)
				if !isIdentPart(r2) {
					break
				}
				i += n2
			}
			out = append(out, sourceToken{Kind: "ident", Text: line[start:i]})
			continue
		}
		out = append(out, sourceToken{Kind: "punct", Text: line[i : i+n]})
		i += n
	}
	return out
}

func runeAt(s string, i int) (rune, int) {
	r, n := utf8.DecodeRuneInString(s[i:])
	if r == utf8.RuneError && n == 0 {
		return rune(s[i]), 1
	}
	return r, n
}

func isIdentStart(r rune) bool {
	return r == '_' || unicode.IsLetter(r)
}

func isIdentPart(r rune) bool {
	return r == '_' || unicode.IsLetter(r) || unicode.IsDigit(r)
}

func isDeclKeyword(s string) bool {
	return s == "fn" || s == "struct" || s == "class" || s == "trait" || s == "import" || s == "impl"
}

func isOrenKeyword(s string) bool {
	switch s {
	case "as", "break", "class", "continue", "defer", "else", "false", "fn", "for", "if", "impl", "import", "in", "nil", "return", "struct", "trait", "true", "var", "while", "yield":
		return true
	default:
		return false
	}
}

func nextNonSpace(tokens []sourceToken, i int) string {
	for j := i + 1; j < len(tokens); j++ {
		if tokens[j].Kind != "space" {
			return tokens[j].Text
		}
	}
	return ""
}

func prevNonSpace(tokens []sourceToken, i int) string {
	for j := i - 1; j >= 0; j-- {
		if tokens[j].Kind != "space" {
			return tokens[j].Text
		}
	}
	return ""
}
