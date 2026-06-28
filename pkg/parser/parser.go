package parser

import (
	"fmt"
	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/token"
	"strconv"
)

const (
	_ int = iota
	LOWEST
	OR          // ||
	AND         // &&
	BITOR       // |
	BITXOR      // ^
	BITAND      // &
	EQUALS      // ==
	LESSGREATER // > or <
	SHIFT       // << or >>
	SUM         // +
	PRODUCT     // *
	PREFIX      // -X or !X or ~X
	CALL        // myFunction(X)
	INDEX       // array[index] or obj.prop
)

var precedences = map[token.TokenType]int{
	token.DOT:      INDEX,
	token.LBRACKET: INDEX,
	token.EQ:       EQUALS,
	token.NOT_EQ:   EQUALS,
	token.AND:      AND,
	token.OR:       OR,
	token.BITOR:    BITOR,
	token.BITXOR:   BITXOR,
	token.BITAND:   BITAND,
	token.LT:       LESSGREATER,
	token.GT:       LESSGREATER,
	token.LTE:      LESSGREATER,
	token.GTE:      LESSGREATER,
	token.SHL:      SHIFT,
	token.SHR:      SHIFT,
	token.PLUS:     SUM,
	token.MINUS:    SUM,
	token.SLASH:    PRODUCT,
	token.ASTERISK: PRODUCT,
	token.LPAREN:   CALL,
}

type (
	prefixParseFn func() ast.Expression
	infixParseFn  func(ast.Expression) ast.Expression
)

type Parser struct {
	l      *lexer.Lexer
	errors []string

	curToken  token.Token
	peekToken token.Token

	prefixParseFns map[token.TokenType]prefixParseFn
	infixParseFns  map[token.TokenType]infixParseFn

	gensymCounter int
}

func New(l *lexer.Lexer) *Parser {
	p := &Parser{
		l:      l,
		errors: []string{},
	}

	p.prefixParseFns = make(map[token.TokenType]prefixParseFn)
	p.registerPrefix(token.IDENT, p.parseIdentifier)
	p.registerPrefix(token.INT, p.parseIntegerLiteral)
	p.registerPrefix(token.FLOAT, p.parseFloatLiteral)
	p.registerPrefix(token.STRING, p.parseStringLiteral)
	p.registerPrefix(token.BANG, p.parsePrefixExpression)
	p.registerPrefix(token.MINUS, p.parsePrefixExpression)
	p.registerPrefix(token.TILDE, p.parsePrefixExpression)
	p.registerPrefix(token.TRUE, p.parseBoolean)
	p.registerPrefix(token.FALSE, p.parseBoolean)
	p.registerPrefix(token.LPAREN, p.parseGroupedExpression)
	p.registerPrefix(token.IF, p.parseIfExpression)
	p.registerPrefix(token.FUNCTION, p.parseFunctionLiteral)
	p.registerPrefix(token.SPAWN, p.parseSpawnExpression)
	p.registerPrefix(token.LBRACKET, p.parseArrayLiteral)
	p.registerPrefix(token.LBRACE, p.parseHashLiteral)
	p.registerPrefix(token.NIL, p.parseNil)
	// Lambda literal: |params| expr_or_block
	// Token is `|` which is also BITOR infix; only used in prefix position.
	p.registerPrefix(token.BITOR, p.parseLambdaLiteral)
	// Empty-params lambda can be written as `|| expr` (lexer emits token.OR).
	p.registerPrefix(token.OR, p.parseLambdaLiteral)

	p.infixParseFns = make(map[token.TokenType]infixParseFn)
	p.registerInfix(token.PLUS, p.parseInfixExpression)
	p.registerInfix(token.MINUS, p.parseInfixExpression)
	p.registerInfix(token.SLASH, p.parseInfixExpression)
	p.registerInfix(token.ASTERISK, p.parseInfixExpression)
	p.registerInfix(token.EQ, p.parseInfixExpression)
	p.registerInfix(token.NOT_EQ, p.parseInfixExpression)
	p.registerInfix(token.AND, p.parseInfixExpression)
	p.registerInfix(token.OR, p.parseInfixExpression)
	p.registerInfix(token.BITOR, p.parseInfixExpression)
	p.registerInfix(token.BITXOR, p.parseInfixExpression)
	p.registerInfix(token.BITAND, p.parseInfixExpression)
	p.registerInfix(token.LT, p.parseInfixExpression)
	p.registerInfix(token.GT, p.parseInfixExpression)
	p.registerInfix(token.LTE, p.parseInfixExpression)
	p.registerInfix(token.GTE, p.parseInfixExpression)
	p.registerInfix(token.SHL, p.parseInfixExpression)
	p.registerInfix(token.SHR, p.parseInfixExpression)
	p.registerInfix(token.LPAREN, p.parseCallExpression)
	p.registerInfix(token.DOT, p.parseMemberExpression)
	p.registerInfix(token.LBRACKET, p.parseIndexExpression)

	// Read two tokens, so curToken and peekToken are both set
	p.nextToken()
	p.nextToken()

	return p
}

func (p *Parser) parseLambdaLiteral() ast.Expression {
	// Grammar:
	//   lambda_lit = "|" [ ident { "," ident } ] "|" ( expression | block ) ;
	//
	// We lower lambdas to FunctionLiteral with empty Name.
	lit := &ast.FunctionLiteral{Token: p.curToken, Name: ""}

	// Parse parameter list (between | ... |).
	params := []*ast.Identifier{}

	if p.curTokenIs(token.OR) {
		// `|| body` : empty params, delimiters already consumed by lexer/tokenizer.
	} else {
		// If next token is another |, it is an empty parameter list.
		if p.peekTokenIs(token.BITOR) {
			p.nextToken() // consume closing '|'
		} else {
			p.nextToken() // move to first param
			if p.curTokenIs(token.BITOR) {
				// allow `| |` style (should have been caught by peekTokenIs, but keep it safe)
			} else {
				ident := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
				params = append(params, ident)
				for p.peekTokenIs(token.COMMA) {
					p.nextToken() // comma
					p.nextToken() // ident
					ident2 := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
					params = append(params, ident2)
				}
			}
			if !p.expectPeek(token.BITOR) {
				return nil
			}
		}
	}
	lit.Parameters = params

	// Parse body: either { ... } or expression.
	p.nextToken()
	if p.curTokenIs(token.LBRACE) {
		lit.Body = p.parseBlockStatement()
		return lit
	}

	// Expression-bodied lambda: wrap as `{ return <expr>; }`
	expr := p.parseExpression(LOWEST)
	if expr == nil {
		return nil
	}
	retTok := token.Token{Type: token.RETURN, Literal: "return", Line: p.curToken.Line, Column: p.curToken.Column}
	ret := &ast.ReturnStatement{Token: retTok, ReturnValue: expr}
	bodyTok := token.Token{Type: token.LBRACE, Literal: "{", Line: p.curToken.Line, Column: p.curToken.Column}
	lit.Body = &ast.BlockStatement{Token: bodyTok, Statements: []ast.Statement{ret}}
	return lit
}

func (p *Parser) parseSpawnExpression() ast.Expression {
	tok := p.curToken
	// spawn <call-expr>
	p.nextToken()
	exp := p.parseExpression(LOWEST)
	call, ok := exp.(*ast.CallExpression)
	if !ok {
		msg := fmt.Sprintf("%d:%d spawn expects a call expression", tok.Line, tok.Column)
		p.errors = append(p.errors, msg)
		return nil
	}
	return &ast.SpawnExpression{Token: tok, Call: call}
}

func (p *Parser) nextToken() {
	p.curToken = p.peekToken
	p.peekToken = p.l.NextToken()
}

func (p *Parser) curTokenIs(t token.TokenType) bool {
	return p.curToken.Type == t
}

func (p *Parser) peekTokenIs(t token.TokenType) bool {
	return p.peekToken.Type == t
}

func (p *Parser) expectPeek(t token.TokenType) bool {
	if p.peekTokenIs(t) {
		p.nextToken()
		return true
	} else {
		p.peekError(t)
		return false
	}
}

func (p *Parser) Errors() []string {
	return p.errors
}

func (p *Parser) peekError(t token.TokenType) {
	msg := fmt.Sprintf("%d:%d expected next token to be %s, got %s instead",
		p.peekToken.Line, p.peekToken.Column, t, p.peekToken.Type)
	p.errors = append(p.errors, msg)
}

func (p *Parser) gensym() int {
	n := p.gensymCounter
	p.gensymCounter++
	return n
}

func (p *Parser) ParseProgram() *ast.Program {
	program := &ast.Program{}
	program.Statements = []ast.Statement{}

	for p.curToken.Type != token.EOF {
		stmt := p.parseStatement()
		if stmt != nil {
			program.Statements = append(program.Statements, stmt)
		}
		p.nextToken()
	}

	return program
}

func (p *Parser) parseStatement() ast.Statement {
	switch p.curToken.Type {
	case token.LET:
		return p.parseVarStatement()
	case token.RETURN:
		return p.parseReturnStatement()
	case token.WHILE:
		return p.parseWhileStatement()
	case token.FOR:
		return p.parseForStatement()
	case token.BREAK:
		return p.parseBreakStatement()
	case token.CONTINUE:
		return p.parseContinueStatement()
	case token.IMPORT:
		return p.parseImportStatement()
	case token.AT:
		return p.parseAttributedStatement()
	case token.STRUCT, token.CLASS:
		return p.parseTypeStatement()
	case token.FFI:
		return p.parseFFIStatement()
	case token.IDENT:
		if p.peekTokenIs(token.DECLARE) {
			return p.parseShortVarStatement()
		}
		return p.parseAssignOrExpressionStatement()
	default:
		return p.parseExpressionStatement()
	}
}

func (p *Parser) parseAttributedStatement() ast.Statement {
	attrs := p.parseAttributeList()
	if p.curToken.Type == token.EOF {
		return nil
	}
	stmt := p.parseStatement()
	if imp, ok := stmt.(*ast.ImportStatement); ok {
		imp.Attrs = append(imp.Attrs, attrs...)
	}
	return stmt
}

func (p *Parser) parseAttributeList() []ast.Attribute {
	attrs := []ast.Attribute{}
	for p.curTokenIs(token.AT) {
		if a, ok := p.parseAttribute(); ok {
			attrs = append(attrs, a)
		}
		p.nextToken()
	}
	return attrs
}

func normalizeAttributeName(name string) string {
	switch name {
	case "cfg":
		return "oren.cfg"
	case "debug":
		return "oren.debug"
	case "release":
		return "oren.release"
	default:
		return name
	}
}

func (p *Parser) parseAttribute() (ast.Attribute, bool) {
	attr := ast.Attribute{}
	if !p.expectPeek(token.IDENT) {
		return attr, false
	}
	name := p.curToken.Literal
	for p.peekTokenIs(token.DOT) {
		p.nextToken()
		if !p.expectPeek(token.IDENT) {
			return attr, false
		}
		name += "." + p.curToken.Literal
	}
	attr.Name = normalizeAttributeName(name)
	if !p.peekTokenIs(token.LPAREN) {
		return attr, true
	}
	p.nextToken()
	p.nextToken()
	if p.curTokenIs(token.RPAREN) {
		return attr, true
	}
	for {
		key := ""
		if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.ASSIGN) {
			key = p.curToken.Literal
			p.nextToken()
			p.nextToken()
		}
		value, ok := p.parseAttributeLiteral()
		if !ok {
			p.errors = append(p.errors, fmt.Sprintf("%d:%d attribute args must be compile-time literals", p.curToken.Line, p.curToken.Column))
			return attr, false
		}
		attr.Args = append(attr.Args, ast.AttributeArg{Key: key, Value: value})
		if p.peekTokenIs(token.COMMA) {
			p.nextToken()
			p.nextToken()
			continue
		}
		break
	}
	if !p.expectPeek(token.RPAREN) {
		return attr, false
	}
	return attr, true
}

func (p *Parser) parseAttributeLiteral() (interface{}, bool) {
	switch p.curToken.Type {
	case token.STRING:
		return p.curToken.Literal, true
	case token.TRUE:
		return true, true
	case token.FALSE:
		return false, true
	case token.INT:
		v, err := strconv.ParseInt(p.curToken.Literal, 10, 64)
		if err != nil {
			return nil, false
		}
		return v, true
	case token.FLOAT:
		v, err := strconv.ParseFloat(p.curToken.Literal, 64)
		if err != nil {
			return nil, false
		}
		return v, true
	case token.NIL:
		return nil, true
	default:
		return nil, false
	}
}

func (p *Parser) parseImportStatement() *ast.ImportStatement {
	stmt := &ast.ImportStatement{Token: p.curToken}
	if !p.expectPeek(token.IDENT) {
		return nil
	}
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	if !p.expectPeek(token.STRING) {
		return nil
	}
	stmt.Path = p.curToken.Literal

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}
	return stmt
}

func (p *Parser) parseTypeStatement() *ast.TypeStatement {
	stmt := &ast.TypeStatement{Token: p.curToken}

	if !p.expectPeek(token.IDENT) {
		return nil
	}
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	if !p.expectPeek(token.LBRACE) {
		return nil
	}

	stmt.Fields = []*ast.Identifier{}

	// Empty: struct Name {}
	if p.peekTokenIs(token.RBRACE) {
		p.nextToken()
		if p.peekTokenIs(token.SEMICOLON) {
			p.nextToken()
		}
		return stmt
	}

	p.nextToken()
	for !p.curTokenIs(token.RBRACE) && !p.curTokenIs(token.EOF) {
		if p.curToken.Type != token.IDENT {
			p.errors = append(p.errors, fmt.Sprintf("%d:%d expected field name, got %s", p.curToken.Line, p.curToken.Column, p.curToken.Type))
			return nil
		}
		stmt.Fields = append(stmt.Fields, &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal})

		if p.peekTokenIs(token.COMMA) {
			p.nextToken() // ,
			p.nextToken() // next field or }
			continue
		}
		if p.peekTokenIs(token.RBRACE) {
			p.nextToken()
			break
		}
		p.errors = append(p.errors, fmt.Sprintf("%d:%d expected ',' or '}', got %s", p.peekToken.Line, p.peekToken.Column, p.peekToken.Type))
		return nil
	}

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}
	return stmt
}

func (p *Parser) parseBreakStatement() *ast.BreakStatement {
	stmt := &ast.BreakStatement{Token: p.curToken}
	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}
	return stmt
}

func (p *Parser) parseContinueStatement() *ast.ContinueStatement {
	stmt := &ast.ContinueStatement{Token: p.curToken}
	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}
	return stmt
}

func (p *Parser) parseVarStatement() *ast.VarStatement {
	stmt := &ast.VarStatement{Token: p.curToken}

	if !p.expectPeek(token.IDENT) {
		return nil
	}

	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	if !p.expectPeek(token.ASSIGN) {
		return nil
	}

	p.nextToken()

	stmt.Value = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	return stmt
}

func (p *Parser) parseShortVarStatement() *ast.VarStatement {
	// IDENT := value
	stmt := &ast.VarStatement{Token: token.Token{Type: token.LET, Literal: "var"}}
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	p.nextToken() // move to :=
	p.nextToken() // move to value

	stmt.Value = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	return stmt
}

func (p *Parser) parseAssignStatement() *ast.AssignStatement {
	// IDENT = value
	stmt := &ast.AssignStatement{Token: p.peekToken} // The '=' token
	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	p.nextToken() // move to =
	p.nextToken() // move to value

	stmt.Value = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	return stmt
}

func (p *Parser) parseAssignOrExpressionStatement() ast.Statement {
	startToken := p.curToken
	leftExp := p.parseExpression(LOWEST)

	if p.peekTokenIs(token.ASSIGN) {
		assignTok := p.peekToken
		p.nextToken() // move to =
		p.nextToken() // move to value
		value := p.parseExpression(LOWEST)

		if p.peekTokenIs(token.SEMICOLON) {
			p.nextToken()
		}

		if ident, ok := leftExp.(*ast.Identifier); ok {
			return &ast.AssignStatement{Token: assignTok, Name: ident, Value: value}
		}
		return &ast.SetStatement{Token: assignTok, Left: leftExp, Value: value}
	}

	stmt := &ast.ExpressionStatement{Token: startToken, Expression: leftExp}
	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}
	return stmt
}

func (p *Parser) parseReturnStatement() *ast.ReturnStatement {
	stmt := &ast.ReturnStatement{Token: p.curToken}

	p.nextToken()

	stmt.ReturnValue = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	return stmt
}

func (p *Parser) parseWhileStatement() *ast.WhileStatement {
	stmt := &ast.WhileStatement{Token: p.curToken}

	p.nextToken()
	stmt.Condition = p.parseExpression(LOWEST)

	if !p.expectPeek(token.LBRACE) {
		return nil
	}

	stmt.Body = p.parseBlockStatement()

	return stmt
}

func (p *Parser) parseForStatement() *ast.ForStatement {
	stmt := &ast.ForStatement{Token: p.curToken}

	// for { ... }
	if p.peekTokenIs(token.LBRACE) {
		p.nextToken()
		stmt.Body = p.parseBlockStatement()
		return stmt
	}

	// Move to first token after `for`.
	p.nextToken()

	// Iterator sugar: `for <ident> in <expr> { ... }`
	//
	// Desugars to a 3-clause `for` using an internal state list and a runtime iterator hook:
	//   var __oren_forin_N = [<expr>, 0, 1, [0, 0]]
	//   for ; __oren_forin_N[2] != 0; __oren_forin_N[1] = __oren_forin_N[1] + 1 {
	//       var __oren_forinr_N = oren_iter_next(__oren_forin_N[0], __oren_forin_N[1], __oren_forin_N[3]) // -> [ok, value]
	//       __oren_forin_N[3] = __oren_forinr_N
	//       __oren_forin_N[2] = __oren_forinr_N[0]
	//       if __oren_forin_N[2] != 0 {
	//           var <ident> = __oren_forinr_N[1]
	//           <body>
	//       }
	//   }
	//
	// Internal temporaries:
	// - Must be valid identifiers for all backends (including the C transpiler).
	// - We use a reserved `__oren_` prefix to avoid collisions with user code.
	if p.curTokenIs(token.IDENT) && p.peekTokenIs(token.IN) {
		userVar := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		stateName := fmt.Sprintf("__oren_forin_%d", p.gensym())
		resName := fmt.Sprintf("__oren_forinr_%d", p.gensym())
		stateIdent := &ast.Identifier{Token: token.Token{Type: token.IDENT, Literal: stateName}, Value: stateName}
		resIdent := &ast.Identifier{Token: token.Token{Type: token.IDENT, Literal: resName}, Value: resName}

		// consume 'in'
		p.nextToken()
		// move to iterable expr
		p.nextToken()
		iterable := p.parseExpression(LOWEST)
		if iterable == nil {
			return nil
		}

		if !p.expectPeek(token.LBRACE) {
			return nil
		}
		userBody := p.parseBlockStatement()

		zero := &ast.IntegerLiteral{Token: token.Token{Type: token.INT, Literal: "0"}, Value: 0}
		one := &ast.IntegerLiteral{Token: token.Token{Type: token.INT, Literal: "1"}, Value: 1}
		two := &ast.IntegerLiteral{Token: token.Token{Type: token.INT, Literal: "2"}, Value: 2}
		three := &ast.IntegerLiteral{Token: token.Token{Type: token.INT, Literal: "3"}, Value: 3}
		pairInit := &ast.ArrayLiteral{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Elements: []ast.Expression{zero, zero}}

		// Optimization: when iterable is a bare identifier, do not stash it in the state list.
		// This preserves the identifier shape for later lowering passes (e.g. Iterable trait rewrite).
		_, iterableIsIdent := iterable.(*ast.Identifier)

		var containerExpr ast.Expression
		var stIdx ast.Expression
		var stOk ast.Expression
		var stPair ast.Expression
		var okSlotIdx ast.Expression
		var idxSlotIdx ast.Expression
		var pairSlotIdx ast.Expression

		if iterableIsIdent {
			// init: var @forin = [0, 1, [0,0]]
			stateInit := &ast.ArrayLiteral{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Elements: []ast.Expression{zero, one, pairInit}}
			stmt.Init = &ast.VarStatement{Token: token.Token{Type: token.LET, Literal: "var"}, Name: stateIdent, Value: stateInit}
			containerExpr = iterable
			stIdx = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: zero}
			stOk = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: one}
			stPair = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: two}
			idxSlotIdx = zero
			okSlotIdx = one
			pairSlotIdx = two
		} else {
			// init: var @forin = [iterable, 0, 1, [0,0]]
			stateInit := &ast.ArrayLiteral{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Elements: []ast.Expression{iterable, zero, one, pairInit}}
			stmt.Init = &ast.VarStatement{Token: token.Token{Type: token.LET, Literal: "var"}, Name: stateIdent, Value: stateInit}
			containerExpr = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: zero}
			stIdx = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: one}
			stOk = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: two}
			stPair = &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: three}
			idxSlotIdx = one
			okSlotIdx = two
			pairSlotIdx = three
		}

		// cond: @forin[2] != 0
		stmt.Condition = &ast.InfixExpression{Token: token.Token{Type: token.NOT_EQ, Literal: "!="}, Left: stOk, Operator: "!=", Right: zero}

		// post: @forin[1] = @forin[1] + 1
		inc := &ast.InfixExpression{Token: token.Token{Type: token.PLUS, Literal: "+"}, Left: stIdx, Operator: "+", Right: one}
		stmt.Post = &ast.SetStatement{
			Token: token.Token{Type: token.ASSIGN, Literal: "="},
			Left:  &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: idxSlotIdx},
			Value: inc,
		}

		// body:
		//   var @forinr = oren_iter_next(container, idx, @forin[pair])
		//   @forin[pair] = @forinr
		//   @forin[ok] = @forinr[0]
		//   if @forin[2] != 0 { var user = @forinr[1]; <user_body> }
		callNext := &ast.CallExpression{
			Token:    token.Token{Type: token.LPAREN, Literal: "("},
			Function: &ast.Identifier{Token: token.Token{Type: token.IDENT, Literal: "oren_iter_next"}, Value: "oren_iter_next"},
			Arguments: []ast.Expression{
				containerExpr,
				stIdx,
				stPair,
			},
		}
		bindRes := &ast.VarStatement{Token: token.Token{Type: token.LET, Literal: "var"}, Name: resIdent, Value: callNext}

		res0 := &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: resIdent, Index: zero}
		res1 := &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: resIdent, Index: one}

		// @forin[pair] = @forinr
		setPair := &ast.SetStatement{
			Token: token.Token{Type: token.ASSIGN, Literal: "="},
			Left:  &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: pairSlotIdx},
			Value: resIdent,
		}

		// @forin[ok] = @forinr[0]
		setOk := &ast.SetStatement{
			Token: token.Token{Type: token.ASSIGN, Literal: "="},
			Left:  &ast.IndexExpression{Token: token.Token{Type: token.LBRACKET, Literal: "["}, Left: stateIdent, Index: okSlotIdx},
			Value: res0,
		}

		guardCond := &ast.InfixExpression{Token: token.Token{Type: token.NOT_EQ, Literal: "!="}, Left: stOk, Operator: "!=", Right: zero}
		bindUser := &ast.VarStatement{Token: token.Token{Type: token.LET, Literal: "var"}, Name: userVar, Value: res1}
		guardBlock := &ast.BlockStatement{Token: token.Token{Type: token.LBRACE, Literal: "{"}}
		guardBlock.Statements = append(guardBlock.Statements, bindUser)
		guardBlock.Statements = append(guardBlock.Statements, userBody.Statements...)
		guardIf := &ast.IfExpression{Token: token.Token{Type: token.IF, Literal: "if"}, Condition: guardCond, Consequence: guardBlock, Alternative: nil}
		guardIfStmt := &ast.ExpressionStatement{Token: token.Token{Type: token.IF, Literal: "if"}, Expression: guardIf}

		stmt.Body = &ast.BlockStatement{Token: token.Token{Type: token.LBRACE, Literal: "{"}}
		stmt.Body.Statements = append(stmt.Body.Statements, bindRes)
		stmt.Body.Statements = append(stmt.Body.Statements, setPair)
		stmt.Body.Statements = append(stmt.Body.Statements, setOk)
		stmt.Body.Statements = append(stmt.Body.Statements, guardIfStmt)
		return stmt
	}

	// `for cond { ... }` or `for init; cond; post { ... }`
	if !p.curTokenIs(token.SEMICOLON) {
		first := p.parseForInitStatement()
		if first == nil {
			return nil
		}

		// Condition-only form: `for <expr> { ... }`
		if es, ok := first.(*ast.ExpressionStatement); ok && p.peekTokenIs(token.LBRACE) {
			stmt.Condition = es.Expression
			p.nextToken()
			stmt.Body = p.parseBlockStatement()
			return stmt
		}

		stmt.Init = first

		// Three-clause form requires a `;` delimiter after init.
		if !p.curTokenIs(token.SEMICOLON) {
			if !p.expectPeek(token.SEMICOLON) {
				return nil
			}
		}
	}

	// Parse condition (may be empty): after first `;` up to second `;`.
	p.nextToken()
	if p.curTokenIs(token.SEMICOLON) {
		stmt.Condition = nil
	} else {
		stmt.Condition = p.parseExpression(LOWEST)
		if !p.expectPeek(token.SEMICOLON) {
			return nil
		}
	}

	// Parse post (may be empty) up to `{`.
	p.nextToken()
	if p.curTokenIs(token.LBRACE) {
		stmt.Post = nil
		stmt.Body = p.parseBlockStatement()
		return stmt
	}

	stmt.Post = p.parseForPostStatement()
	if stmt.Post == nil {
		return nil
	}

	if !p.expectPeek(token.LBRACE) {
		return nil
	}

	stmt.Body = p.parseBlockStatement()
	return stmt
}

func (p *Parser) parseForInitStatement() ast.Statement {
	switch p.curToken.Type {
	case token.LET:
		return p.parseVarStatement()
	case token.IDENT:
		if p.peekTokenIs(token.DECLARE) {
			return p.parseShortVarStatement()
		}
		return p.parseAssignOrExpressionStatement()
	default:
		return p.parseExpressionStatement()
	}
}

func (p *Parser) parseForPostStatement() ast.Statement {
	switch p.curToken.Type {
	case token.LET:
		p.errors = append(p.errors, fmt.Sprintf("%d:%d for post does not allow var declarations", p.curToken.Line, p.curToken.Column))
		return nil
	case token.IDENT:
		if p.peekTokenIs(token.DECLARE) {
			p.errors = append(p.errors, fmt.Sprintf("%d:%d for post does not allow :=", p.peekToken.Line, p.peekToken.Column))
			return nil
		}
		return p.parseAssignOrExpressionStatement()
	default:
		return p.parseExpressionStatement()
	}
}

func (p *Parser) parseFFIStatement() *ast.FFIStatement {
	stmt := &ast.FFIStatement{Token: p.curToken}

	if !p.expectPeek(token.IDENT) {
		return nil
	}

	stmt.Name = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}

	return stmt
}

func (p *Parser) parseExpressionStatement() *ast.ExpressionStatement {
	stmt := &ast.ExpressionStatement{Token: p.curToken}

	stmt.Expression = p.parseExpression(LOWEST)

	if p.peekTokenIs(token.SEMICOLON) {
		p.nextToken()
	}

	return stmt
}

func (p *Parser) parseExpression(precedence int) ast.Expression {
	prefix := p.prefixParseFns[p.curToken.Type]
	if prefix == nil {
		p.noPrefixParseFnError(p.curToken.Type)
		return nil
	}
	leftExp := prefix()

	for !p.peekTokenIs(token.SEMICOLON) && precedence < p.peekPrecedence() {
		infix := p.infixParseFns[p.peekToken.Type]
		if infix == nil {
			return leftExp
		}

		p.nextToken()

		leftExp = infix(leftExp)
	}

	return leftExp
}

func (p *Parser) peekPrecedence() int {
	if p, ok := precedences[p.peekToken.Type]; ok {
		return p
	}
	return LOWEST
}

func (p *Parser) curPrecedence() int {
	if p, ok := precedences[p.curToken.Type]; ok {
		return p
	}
	return LOWEST
}

func (p *Parser) parseIdentifier() ast.Expression {
	return &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parseIntegerLiteral() ast.Expression {
	lit := &ast.IntegerLiteral{Token: p.curToken}

	value, err := strconv.ParseInt(p.curToken.Literal, 0, 64)
	if err != nil {
		msg := fmt.Sprintf("%d:%d could not parse %q as integer", p.curToken.Line, p.curToken.Column, p.curToken.Literal)
		p.errors = append(p.errors, msg)
		return nil
	}

	lit.Value = value
	return lit
}

func (p *Parser) parseFloatLiteral() ast.Expression {
	lit := &ast.FloatLiteral{Token: p.curToken}

	value, err := strconv.ParseFloat(p.curToken.Literal, 64)
	if err != nil {
		msg := fmt.Sprintf("%d:%d could not parse %q as float", p.curToken.Line, p.curToken.Column, p.curToken.Literal)
		p.errors = append(p.errors, msg)
		return nil
	}

	lit.Value = value
	return lit
}

func (p *Parser) parseStringLiteral() ast.Expression {
	return &ast.StringLiteral{Token: p.curToken, Value: p.curToken.Literal}
}

func (p *Parser) parsePrefixExpression() ast.Expression {
	expression := &ast.PrefixExpression{
		Token:    p.curToken,
		Operator: p.curToken.Literal,
	}

	p.nextToken()

	expression.Right = p.parseExpression(PREFIX)

	return expression
}

func (p *Parser) parseInfixExpression(left ast.Expression) ast.Expression {
	expression := &ast.InfixExpression{
		Token:    p.curToken,
		Operator: p.curToken.Literal,
		Left:     left,
	}

	precedence := p.curPrecedence()
	p.nextToken()
	expression.Right = p.parseExpression(precedence)

	return expression
}

func (p *Parser) parseBoolean() ast.Expression {
	return &ast.Boolean{Token: p.curToken, Value: p.curTokenIs(token.TRUE)}
}

func (p *Parser) parseNil() ast.Expression {
	return &ast.NilLiteral{Token: p.curToken}
}

func (p *Parser) parseGroupedExpression() ast.Expression {
	p.nextToken()
	exp := p.parseExpression(LOWEST)

	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return exp
}

func (p *Parser) parseIfExpression() ast.Expression {
	expression := &ast.IfExpression{Token: p.curToken}

	p.nextToken()
	expression.Condition = p.parseExpression(LOWEST)

	if !p.expectPeek(token.LBRACE) {
		return nil
	}

	expression.Consequence = p.parseBlockStatement()

	if p.peekTokenIs(token.ELSE) {
		p.nextToken()
		elseTok := p.curToken

		// Rolling grammar: allow `else if ... { ... }` chains.
		// Represent as `else { if ... { ... } else { ... } }` at the AST level so
		// existing backends (C transpiler) remain correct without structural changes.
		if p.peekTokenIs(token.IF) {
			p.nextToken() // move to 'if'
			nested := p.parseIfExpression()
			if nested == nil {
				return nil
			}
			if nestedIf, ok := nested.(*ast.IfExpression); ok {
				altTok := token.Token{Type: token.LBRACE, Literal: "{", Line: elseTok.Line, Column: elseTok.Column}
				es := &ast.ExpressionStatement{Token: nestedIf.Token, Expression: nestedIf}
				expression.Alternative = &ast.BlockStatement{Token: altTok, Statements: []ast.Statement{es}}
			} else {
				p.errors = append(p.errors, fmt.Sprintf("%d:%d expected if expression after else, got %T", elseTok.Line, elseTok.Column, nested))
				return nil
			}
		} else {
			if !p.expectPeek(token.LBRACE) {
				return nil
			}
			expression.Alternative = p.parseBlockStatement()
		}
	}

	return expression
}

func (p *Parser) parseBlockStatement() *ast.BlockStatement {
	block := &ast.BlockStatement{Token: p.curToken}
	block.Statements = []ast.Statement{}

	p.nextToken()

	for !p.curTokenIs(token.RBRACE) && !p.curTokenIs(token.EOF) {
		stmt := p.parseStatement()
		if stmt != nil {
			block.Statements = append(block.Statements, stmt)
		}
		p.nextToken()
	}

	return block
}

func (p *Parser) parseHashLiteral() ast.Expression {
	hash := &ast.HashLiteral{Token: p.curToken}
	hash.Pairs = make(map[ast.Expression]ast.Expression)

	for !p.peekTokenIs(token.RBRACE) {
		p.nextToken()
		key := p.parseExpression(LOWEST)

		if !p.expectPeek(token.COLON) {
			return nil
		}

		p.nextToken()
		value := p.parseExpression(LOWEST)

		hash.Pairs[key] = value

		if !p.peekTokenIs(token.RBRACE) && !p.expectPeek(token.COMMA) {
			return nil
		}
	}

	if !p.expectPeek(token.RBRACE) {
		return nil
	}

	return hash
}

func (p *Parser) parseFunctionLiteral() ast.Expression {
	lit := &ast.FunctionLiteral{Token: p.curToken}

	if p.peekTokenIs(token.IDENT) {
		p.nextToken()
		lit.Name = p.curToken.Literal
	}

	if !p.expectPeek(token.LPAREN) {
		return nil
	}

	lit.Parameters = p.parseFunctionParameters()

	if !p.expectPeek(token.LBRACE) {
		return nil
	}

	lit.Body = p.parseBlockStatement()

	return lit
}

func (p *Parser) parseFunctionParameters() []*ast.Identifier {
	identifiers := []*ast.Identifier{}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
		return identifiers
	}

	p.nextToken()

	ident := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	identifiers = append(identifiers, ident)

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		ident := &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
		identifiers = append(identifiers, ident)
	}

	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return identifiers
}

func (p *Parser) parseCallExpression(function ast.Expression) ast.Expression {
	exp := &ast.CallExpression{Token: p.curToken, Function: function}
	exp.Arguments = p.parseCallArguments()
	return exp
}

func (p *Parser) parseMemberExpression(left ast.Expression) ast.Expression {
	exp := &ast.MemberExpression{Token: p.curToken, Left: left}

	if !p.expectPeek(token.IDENT) {
		return nil
	}

	exp.Property = &ast.Identifier{Token: p.curToken, Value: p.curToken.Literal}
	return exp
}

func (p *Parser) parseArrayLiteral() ast.Expression {
	array := &ast.ArrayLiteral{Token: p.curToken}

	array.Elements = p.parseExpressionList(token.RBRACKET)

	return array
}

func (p *Parser) parseExpressionList(end token.TokenType) []ast.Expression {
	list := []ast.Expression{}

	if p.peekTokenIs(end) {
		p.nextToken()
		return list
	}

	p.nextToken()
	list = append(list, p.parseExpression(LOWEST))

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		list = append(list, p.parseExpression(LOWEST))
	}

	if !p.expectPeek(end) {
		return nil
	}

	return list
}

func (p *Parser) parseIndexExpression(left ast.Expression) ast.Expression {
	exp := &ast.IndexExpression{Token: p.curToken, Left: left}

	p.nextToken()
	exp.Index = p.parseExpression(LOWEST)

	if !p.expectPeek(token.RBRACKET) {
		return nil
	}

	return exp
}

func (p *Parser) parseCallArguments() []ast.Expression {
	args := []ast.Expression{}

	if p.peekTokenIs(token.RPAREN) {
		p.nextToken()
		return args
	}

	p.nextToken()
	args = append(args, p.parseExpression(LOWEST))

	for p.peekTokenIs(token.COMMA) {
		p.nextToken()
		p.nextToken()
		args = append(args, p.parseExpression(LOWEST))
	}

	if !p.expectPeek(token.RPAREN) {
		return nil
	}

	return args
}

func (p *Parser) registerPrefix(tokenType token.TokenType, fn prefixParseFn) {
	p.prefixParseFns[tokenType] = fn
}

func (p *Parser) registerInfix(tokenType token.TokenType, fn infixParseFn) {
	p.infixParseFns[tokenType] = fn
}

func (p *Parser) noPrefixParseFnError(t token.TokenType) {
	msg := fmt.Sprintf("%d:%d no prefix parse function for %s found", p.curToken.Line, p.curToken.Column, t)
	p.errors = append(p.errors, msg)
}
