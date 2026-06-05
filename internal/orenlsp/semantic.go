package orenlsp

import (
	"fmt"
	"strings"

	"oren/pkg/lexer"
	"oren/pkg/token"
)

const semanticModifierDeclaration = 1

var semanticTokenTypes = []string{
	"namespace",
	"type",
	"class",
	"function",
	"variable",
	"keyword",
	"string",
	"number",
	"operator",
}

var semanticTokenModifiers = []string{"declaration"}

type semanticTokensResult struct {
	Data []int `json:"data"`
}

type semanticTokenInfo struct {
	Line      int
	Character int
	Length    int
	Type      int
	Modifiers int
}

func semanticTokens(text string) semanticTokensResult {
	decls := semanticDeclarationMap(text)
	symbols := semanticSymbolKindMap(text)
	lines := strings.Split(text, "\n")
	l := lexer.New(text)
	var tokens []semanticTokenInfo
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		if info, ok := classifySemanticToken(tok, lines, decls, symbols); ok {
			tokens = append(tokens, info)
		}
	}
	return semanticTokensResult{Data: encodeSemanticTokens(tokens)}
}

func classifySemanticToken(tok token.Token, lines []string, decls map[string]string, symbols map[string]string) (semanticTokenInfo, bool) {
	line := tok.Line - 1
	character := tok.Column - 1
	if line < 0 || character < 0 {
		return semanticTokenInfo{}, false
	}
	length := semanticTokenLength(tok, lines, line, character)
	if length <= 0 {
		return semanticTokenInfo{}, false
	}
	key := tokenLocationKey(line, character)
	if kind, ok := decls[key]; ok {
		return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticKindIndex(kind), Modifiers: semanticModifierDeclaration}, true
	}
	switch tok.Type {
	case token.IDENT:
		kind := symbols[tok.Literal]
		if kind == "" {
			kind = "variable"
		}
		return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticKindIndex(kind)}, true
	case token.STRING:
		return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticTypeIndex("string")}, true
	case token.INT, token.FLOAT:
		return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticTypeIndex("number")}, true
	default:
		if isKeywordToken(tok.Type) {
			return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticTypeIndex("keyword")}, true
		}
		if isOperatorToken(tok.Type) {
			return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticTypeIndex("operator")}, true
		}
		return semanticTokenInfo{}, false
	}
}

func semanticDeclarationMap(text string) map[string]string {
	out := map[string]string{}
	for _, sym := range collectSymbols(text) {
		out[tokenLocationKey(sym.Range.Start.Line, sym.Range.Start.Character)] = sym.Kind
	}
	return out
}

func semanticSymbolKindMap(text string) map[string]string {
	out := map[string]string{}
	for _, sym := range collectSymbols(text) {
		out[sym.Name] = sym.Kind
	}
	return out
}

func encodeSemanticTokens(tokens []semanticTokenInfo) []int {
	out := make([]int, 0, len(tokens)*5)
	prevLine := 0
	prevChar := 0
	for i, tok := range tokens {
		lineDelta := tok.Line
		charDelta := tok.Character
		if i > 0 {
			lineDelta = tok.Line - prevLine
			if lineDelta == 0 {
				charDelta = tok.Character - prevChar
			}
		}
		out = append(out, lineDelta, charDelta, tok.Length, tok.Type, tok.Modifiers)
		prevLine = tok.Line
		prevChar = tok.Character
	}
	return out
}

func semanticTokenLength(tok token.Token, lines []string, line, character int) int {
	if tok.Type == token.STRING && line >= 0 && line < len(lines) {
		return stringSourceLength(lines[line], character)
	}
	return len(tok.Literal)
}

func stringSourceLength(line string, start int) int {
	if start < 0 || start >= len(line) {
		return 0
	}
	escaped := false
	for i := start + 1; i < len(line); i++ {
		if escaped {
			escaped = false
			continue
		}
		if line[i] == '\\' {
			escaped = true
			continue
		}
		if line[i] == '"' {
			return i - start + 1
		}
	}
	return len(line) - start
}

func semanticKindIndex(kind string) int {
	switch kind {
	case "module":
		return semanticTypeIndex("namespace")
	case "struct":
		return semanticTypeIndex("type")
	case "class":
		return semanticTypeIndex("class")
	case "function":
		return semanticTypeIndex("function")
	default:
		return semanticTypeIndex("variable")
	}
}

func semanticTypeIndex(name string) int {
	for i, typ := range semanticTokenTypes {
		if typ == name {
			return i
		}
	}
	return semanticTypeIndex("variable")
}

func tokenLocationKey(line, character int) string {
	return fmt.Sprintf("%d:%d", line, character)
}

func isKeywordToken(typ token.TokenType) bool {
	switch typ {
	case token.FUNCTION, token.LET, token.TRUE, token.FALSE, token.IF, token.ELSE,
		token.RETURN, token.WHILE, token.FOR, token.BREAK, token.CONTINUE,
		token.IN, token.IMPORT, token.STRUCT, token.CLASS, token.NIL, token.FFI,
		token.SPAWN:
		return true
	default:
		return false
	}
}

func isOperatorToken(typ token.TokenType) bool {
	switch typ {
	case token.ASSIGN, token.PLUS, token.MINUS, token.BANG, token.TILDE,
		token.ASTERISK, token.SLASH, token.LT, token.GT, token.LTE, token.GTE,
		token.SHL, token.SHR, token.EQ, token.NOT_EQ, token.DECLARE,
		token.AND, token.OR, token.BITAND, token.BITOR, token.BITXOR:
		return true
	default:
		return false
	}
}
