package orenlsp

import (
	"sort"
	"strings"

	"oren/pkg/lexer"
	"oren/pkg/token"
)

const (
	lspCompletionKeyword  = 14
	lspCompletionFunction = 3
	lspCompletionField    = 5
	lspCompletionVariable = 6
	lspCompletionClass    = 7
	lspCompletionModule   = 9
	lspCompletionStruct   = 22

	lspSymbolClass    = 5
	lspSymbolFunction = 12
	lspSymbolVariable = 13
	lspSymbolModule   = 2
	lspSymbolStruct   = 23
)

type sourceSymbol struct {
	Name   string
	Kind   string
	Detail string
	Range  diagnosticRange
}

type importSpec struct {
	Alias string
	Spec  string
}

type completionItem struct {
	Label  string `json:"label"`
	Kind   int    `json:"kind"`
	Detail string `json:"detail,omitempty"`
}

type documentSymbol struct {
	Name           string          `json:"name"`
	Kind           int             `json:"kind"`
	Range          diagnosticRange `json:"range"`
	SelectionRange diagnosticRange `json:"selectionRange"`
	Detail         string          `json:"detail,omitempty"`
}

type location struct {
	URI   string          `json:"uri"`
	Range diagnosticRange `json:"range"`
}

type resolvedSymbol struct {
	URI    string
	Symbol sourceSymbol
}

func completionItems(text string) []completionItem {
	items := make([]completionItem, 0, len(orenKeywords)+8)
	seen := map[string]bool{}
	for _, kw := range orenKeywords {
		items = append(items, completionItem{Label: kw, Kind: lspCompletionKeyword, Detail: "keyword"})
		seen[kw] = true
	}
	for _, sym := range collectSymbols(text) {
		if seen[sym.Name] {
			continue
		}
		seen[sym.Name] = true
		items = append(items, completionItem{Label: sym.Name, Kind: completionKind(sym.Kind), Detail: sym.Detail})
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Label == items[j].Label {
			return items[i].Detail < items[j].Detail
		}
		return items[i].Label < items[j].Label
	})
	return items
}

func completionItemsWithAnonymousImports(text string, importedDocs []documentSnapshot, aliasByURI map[string]string) []completionItem {
	items := completionItems(text)
	seen := map[string]bool{}
	for _, item := range items {
		seen[item.Label] = true
	}
	for _, doc := range importedDocs {
		alias, ok := aliasByURI[doc.URI]
		if !ok || alias != "" {
			continue
		}
		for _, sym := range collectSymbols(doc.Text) {
			if seen[sym.Name] {
				continue
			}
			seen[sym.Name] = true
			items = append(items, completionItem{Label: sym.Name, Kind: completionKind(sym.Kind), Detail: sym.Detail})
		}
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Label == items[j].Label {
			return items[i].Detail < items[j].Detail
		}
		return items[i].Label < items[j].Label
	})
	return items
}

func importedModuleCompletionItems(receiver, partial string, importedDocs []documentSnapshot, aliasByURI map[string]string) ([]completionItem, bool) {
	if receiver == "" {
		return nil, false
	}
	for _, doc := range importedDocs {
		if aliasByURI[doc.URI] != receiver {
			continue
		}
		syms := collectSymbols(doc.Text)
		items := make([]completionItem, 0, len(syms))
		seen := map[string]bool{}
		for _, sym := range syms {
			if seen[sym.Name] || (partial != "" && !strings.HasPrefix(sym.Name, partial)) {
				continue
			}
			seen[sym.Name] = true
			items = append(items, completionItem{Label: sym.Name, Kind: completionKind(sym.Kind), Detail: sym.Detail})
		}
		sort.Slice(items, func(i, j int) bool {
			if items[i].Label == items[j].Label {
				return items[i].Detail < items[j].Detail
			}
			return items[i].Label < items[j].Label
		})
		return items, true
	}
	return nil, false
}

func documentSymbols(text string) []documentSymbol {
	syms := collectSymbols(text)
	out := make([]documentSymbol, 0, len(syms))
	for _, sym := range syms {
		out = append(out, documentSymbol{
			Name:           sym.Name,
			Kind:           symbolKind(sym.Kind),
			Range:          sym.Range,
			SelectionRange: sym.Range,
			Detail:         sym.Detail,
		})
	}
	return out
}

func symbolDefinitionLocations(text, uri, name string) []location {
	if match, ok := symbolDefinition(text, uri, name); ok {
		return []location{{URI: match.URI, Range: match.Symbol.Range}}
	}
	return []location{}
}

func symbolDefinition(text, uri, name string) (resolvedSymbol, bool) {
	for _, sym := range collectSymbols(text) {
		if sym.Name == name {
			return resolvedSymbol{URI: uri, Symbol: sym}, true
		}
	}
	return resolvedSymbol{}, false
}

func identifierLocations(text, uri, name string) []location {
	if name == "" {
		return []location{}
	}
	l := lexer.New(text)
	var out []location
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		if tok.Type != token.IDENT || tok.Literal != name {
			continue
		}
		out = append(out, location{URI: uri, Range: tokenRange(tok)})
	}
	return out
}

func wordAtPosition(text string, pos position) string {
	word, _ := wordRangeAtPosition(text, pos)
	return word
}

func wordRangeAtPosition(text string, pos position) (string, diagnosticRange) {
	lines := strings.Split(text, "\n")
	if pos.Line < 0 || pos.Line >= len(lines) {
		return "", diagnosticRange{}
	}
	line := []rune(lines[pos.Line])
	if len(line) == 0 {
		return "", diagnosticRange{}
	}
	col := pos.Character
	if col < 0 {
		return "", diagnosticRange{}
	}
	if col >= len(line) {
		col = len(line) - 1
	}
	if !isIdentRune(line[col]) && col > 0 && isIdentRune(line[col-1]) {
		col--
	}
	if !isIdentRune(line[col]) {
		return "", diagnosticRange{}
	}
	start := col
	for start > 0 && isIdentRune(line[start-1]) {
		start--
	}
	end := col + 1
	for end < len(line) && isIdentRune(line[end]) {
		end++
	}
	word := string(line[start:end])
	if !isIdentStart(rune(word[0])) {
		return "", diagnosticRange{}
	}
	rng := diagnosticRange{
		Start: position{Line: pos.Line, Character: start},
		End:   position{Line: pos.Line, Character: end},
	}
	return word, rng
}

func isIdentRune(r rune) bool {
	return isIdentStart(r) || (r >= '0' && r <= '9')
}

func isIdentStart(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
}

func collectSymbols(text string) []sourceSymbol {
	l := lexer.New(text)
	var out []sourceSymbol
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		switch tok.Type {
		case token.FUNCTION:
			if name := l.NextToken(); name.Type == token.IDENT {
				out = append(out, newSourceSymbol(name, "function", "function"))
			}
		case token.LET:
			if name := l.NextToken(); name.Type == token.IDENT {
				out = append(out, newSourceSymbol(name, "variable", "variable"))
			}
		case token.IMPORT:
			name := l.NextToken()
			if name.Type != token.IDENT {
				continue
			}
			detail := "import"
			if spec := l.NextToken(); spec.Type == token.STRING && spec.Literal != "" {
				detail = "import " + spec.Literal
			}
			out = append(out, newSourceSymbol(name, "module", detail))
		case token.STRUCT:
			if name := l.NextToken(); name.Type == token.IDENT {
				out = append(out, newSourceSymbol(name, "struct", "struct"))
			}
		case token.CLASS:
			if name := l.NextToken(); name.Type == token.IDENT {
				out = append(out, newSourceSymbol(name, "class", "class"))
			}
		}
	}
	return out
}

func collectImports(text string) []importSpec {
	l := lexer.New(text)
	var out []importSpec
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		if tok.Type != token.IMPORT {
			continue
		}
		name := l.NextToken()
		if name.Type != token.IDENT && name.Type != token.DOT {
			continue
		}
		spec := l.NextToken()
		if spec.Type != token.STRING || spec.Literal == "" {
			continue
		}
		alias := name.Literal
		anonymous := name.Type == token.DOT
		if anonymous {
			alias = ""
		}
		out = append(out, importSpec{Alias: alias, Spec: spec.Literal})
	}
	return out
}

func newSourceSymbol(tok token.Token, kind, detail string) sourceSymbol {
	rng := tokenRange(tok)
	return sourceSymbol{
		Name:   tok.Literal,
		Kind:   kind,
		Detail: detail,
		Range:  rng,
	}
}

func tokenRange(tok token.Token) diagnosticRange {
	start := position{Line: tok.Line - 1, Character: tok.Column - 1}
	end := position{Line: start.Line, Character: start.Character + len(tok.Literal)}
	return diagnosticRange{Start: start, End: end}
}

func completionKind(kind string) int {
	switch kind {
	case "function":
		return lspCompletionFunction
	case "variable":
		return lspCompletionVariable
	case "module":
		return lspCompletionModule
	case "struct":
		return lspCompletionStruct
	case "class":
		return lspCompletionClass
	default:
		return lspCompletionVariable
	}
}

func symbolKind(kind string) int {
	switch kind {
	case "function":
		return lspSymbolFunction
	case "variable":
		return lspSymbolVariable
	case "module":
		return lspSymbolModule
	case "struct":
		return lspSymbolStruct
	case "class":
		return lspSymbolClass
	default:
		return lspSymbolVariable
	}
}

var orenKeywords = []string{
	"break",
	"class",
	"continue",
	"else",
	"false",
	"ffi",
	"fn",
	"for",
	"if",
	"import",
	"in",
	"nil",
	"return",
	"spawn",
	"struct",
	"true",
	"var",
	"while",
}
