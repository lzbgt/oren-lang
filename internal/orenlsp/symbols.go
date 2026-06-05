package orenlsp

import (
	"sort"

	"oren/pkg/lexer"
	"oren/pkg/token"
)

const (
	lspCompletionKeyword  = 14
	lspCompletionFunction = 3
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
			if name := l.NextToken(); name.Type == token.IDENT {
				detail := "import"
				if spec := l.NextToken(); spec.Type == token.STRING && spec.Literal != "" {
					detail = "import " + spec.Literal
				}
				out = append(out, newSourceSymbol(name, "module", detail))
			}
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

func newSourceSymbol(tok token.Token, kind, detail string) sourceSymbol {
	start := position{Line: tok.Line - 1, Character: tok.Column - 1}
	end := position{Line: start.Line, Character: start.Character + len(tok.Literal)}
	return sourceSymbol{
		Name:   tok.Literal,
		Kind:   kind,
		Detail: detail,
		Range:  diagnosticRange{Start: start, End: end},
	}
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
