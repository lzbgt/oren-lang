package orenlsp

import (
	"fmt"
	"strings"

	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/parser"
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
	"parameter",
	"property",
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
	decls, symbols, refs := semanticMaps(text)
	lines := strings.Split(text, "\n")
	l := lexer.New(text)
	var tokens []semanticTokenInfo
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		if info, ok := classifySemanticToken(tok, lines, decls, symbols, refs); ok {
			tokens = append(tokens, info)
		}
	}
	return semanticTokensResult{Data: encodeSemanticTokens(tokens)}
}

func classifySemanticToken(tok token.Token, lines []string, decls map[string]string, symbols map[string]string, refs map[string]string) (semanticTokenInfo, bool) {
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
		if kind, ok := refs[key]; ok {
			return semanticTokenInfo{Line: line, Character: character, Length: length, Type: semanticKindIndex(kind)}, true
		}
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
	decls, _, _ := semanticMaps(text)
	return decls
}

func semanticSymbolKindMap(text string) map[string]string {
	_, symbols, _ := semanticMaps(text)
	return symbols
}

func semanticLocationKindMap(text string) map[string]string {
	_, _, refs := semanticMaps(text)
	return refs
}

func semanticMaps(text string) (map[string]string, map[string]string, map[string]string) {
	out := map[string]string{}
	symbols := map[string]string{}
	for _, sym := range collectSymbols(text) {
		out[tokenLocationKey(sym.Range.Start.Line, sym.Range.Start.Character)] = sym.Kind
		symbols[sym.Name] = sym.Kind
	}
	parserDecls, refs := parserSemanticMaps(text)
	for key, kind := range parserDecls {
		out[key] = kind
	}
	return out, symbols, refs
}

func parserSemanticMaps(text string) (map[string]string, map[string]string) {
	decls := map[string]string{}
	refs := map[string]string{}
	p := parser.New(lexer.New(text))
	program := p.ParseProgram()
	if program == nil {
		return decls, refs
	}
	for _, stmt := range program.Statements {
		collectParserStatementSemantic(stmt, map[string]bool{}, decls, refs)
	}
	return decls, refs
}

func collectParserStatementSemantic(stmt ast.Statement, params map[string]bool, decls, refs map[string]string) {
	switch stmt := stmt.(type) {
	case *ast.TypeStatement:
		for _, field := range stmt.Fields {
			addIdentifierDecl(field, "property", decls)
		}
	case *ast.VarStatement:
		collectParserExpressionSemantic(stmt.Value, params, decls, refs)
	case *ast.ReturnStatement:
		collectParserExpressionSemantic(stmt.ReturnValue, params, decls, refs)
	case *ast.ExpressionStatement:
		collectParserExpressionSemantic(stmt.Expression, params, decls, refs)
	case *ast.AssignStatement:
		addScopedIdentifierRef(stmt.Name, params, "parameter", refs)
		collectParserExpressionSemantic(stmt.Value, params, decls, refs)
	case *ast.SetStatement:
		collectParserExpressionSemantic(stmt.Left, params, decls, refs)
		collectParserExpressionSemantic(stmt.Value, params, decls, refs)
	case *ast.WhileStatement:
		collectParserExpressionSemantic(stmt.Condition, params, decls, refs)
		collectParserBlockSemantic(stmt.Body, params, decls, refs)
	case *ast.ForStatement:
		collectParserStatementSemantic(stmt.Init, params, decls, refs)
		collectParserExpressionSemantic(stmt.Condition, params, decls, refs)
		collectParserStatementSemantic(stmt.Post, params, decls, refs)
		collectParserBlockSemantic(stmt.Body, params, decls, refs)
	case *ast.BlockStatement:
		collectParserBlockSemantic(stmt, params, decls, refs)
	}
}

func collectParserBlockSemantic(block *ast.BlockStatement, params map[string]bool, decls, refs map[string]string) {
	if block == nil {
		return
	}
	for _, stmt := range block.Statements {
		collectParserStatementSemantic(stmt, params, decls, refs)
	}
}

func collectParserExpressionSemantic(expr ast.Expression, params map[string]bool, decls, refs map[string]string) {
	switch expr := expr.(type) {
	case *ast.Identifier:
		addScopedIdentifierRef(expr, params, "parameter", refs)
	case *ast.PrefixExpression:
		collectParserExpressionSemantic(expr.Right, params, decls, refs)
	case *ast.InfixExpression:
		collectParserExpressionSemantic(expr.Left, params, decls, refs)
		collectParserExpressionSemantic(expr.Right, params, decls, refs)
	case *ast.SpawnExpression:
		collectParserExpressionSemantic(expr.Call, params, decls, refs)
	case *ast.IfExpression:
		collectParserExpressionSemantic(expr.Condition, params, decls, refs)
		collectParserBlockSemantic(expr.Consequence, params, decls, refs)
		collectParserBlockSemantic(expr.Alternative, params, decls, refs)
	case *ast.FunctionLiteral:
		childParams := copyStringBoolMap(params)
		for _, param := range expr.Parameters {
			if addIdentifierDecl(param, "parameter", decls) {
				childParams[param.Value] = true
			}
		}
		collectParserBlockSemantic(expr.Body, childParams, decls, refs)
	case *ast.CallExpression:
		collectParserExpressionSemantic(expr.Function, params, decls, refs)
		for _, arg := range expr.Arguments {
			collectParserExpressionSemantic(arg, params, decls, refs)
		}
	case *ast.MemberExpression:
		collectParserExpressionSemantic(expr.Left, params, decls, refs)
		addIdentifierRef(expr.Property, "property", refs)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectParserExpressionSemantic(elem, params, decls, refs)
		}
	case *ast.IndexExpression:
		collectParserExpressionSemantic(expr.Left, params, decls, refs)
		collectParserExpressionSemantic(expr.Index, params, decls, refs)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectParserExpressionSemantic(key, params, decls, refs)
			collectParserExpressionSemantic(value, params, decls, refs)
		}
	}
}

func addScopedIdentifierRef(ident *ast.Identifier, params map[string]bool, kind string, refs map[string]string) {
	if ident == nil || !params[ident.Value] {
		return
	}
	addIdentifierRef(ident, kind, refs)
}

func addIdentifierDecl(ident *ast.Identifier, kind string, decls map[string]string) bool {
	if !validIdentifierToken(ident) {
		return false
	}
	decls[tokenLocationKey(ident.Token.Line-1, ident.Token.Column-1)] = kind
	return true
}

func addIdentifierRef(ident *ast.Identifier, kind string, refs map[string]string) {
	if !validIdentifierToken(ident) {
		return
	}
	refs[tokenLocationKey(ident.Token.Line-1, ident.Token.Column-1)] = kind
}

func validIdentifierToken(ident *ast.Identifier) bool {
	return ident != nil && ident.Token.Type == token.IDENT && ident.Token.Line > 0 && ident.Token.Column > 0
}

func copyStringBoolMap(in map[string]bool) map[string]bool {
	out := make(map[string]bool, len(in))
	for key, value := range in {
		out[key] = value
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
	case "parameter":
		return semanticTypeIndex("parameter")
	case "property":
		return semanticTypeIndex("property")
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
		token.AND, token.OR, token.BITAND, token.BITOR, token.BITXOR,
		token.DOT:
		return true
	default:
		return false
	}
}
