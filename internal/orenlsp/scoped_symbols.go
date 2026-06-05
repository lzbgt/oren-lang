package orenlsp

import (
	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/parser"
	"oren/pkg/token"
)

type scopedSymbolIndex struct {
	usesByLocation map[string]resolvedSymbol
	refsByDecl     map[string][]location
}

func scopedParameterSymbolAt(text, uri string, pos position) (resolvedSymbol, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return resolvedSymbol{}, false
	}
	index := collectScopedParameterSymbols(text, uri)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name {
		return resolvedSymbol{}, false
	}
	return match, true
}

func scopedParameterReferencesAt(text, uri string, pos position, includeDeclaration bool) ([]location, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return nil, false
	}
	index := collectScopedParameterSymbols(text, uri)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name {
		return nil, false
	}
	decl := location{URI: match.URI, Range: match.Symbol.Range}
	refs := index.refsByDecl[locationKey(decl)]
	out := make([]location, 0, len(refs)+1)
	if includeDeclaration {
		out = append(out, decl)
	}
	out = append(out, refs...)
	return uniqueLocations(out), true
}

func collectScopedParameterSymbols(text, uri string) scopedSymbolIndex {
	index := scopedSymbolIndex{
		usesByLocation: map[string]resolvedSymbol{},
		refsByDecl:     map[string][]location{},
	}
	p := parser.New(lexer.New(text))
	program := p.ParseProgram()
	if program == nil {
		return index
	}
	var stack []map[string]resolvedSymbol
	for _, stmt := range program.Statements {
		collectScopedParameterStatement(stmt, uri, &stack, index)
	}
	return index
}

func collectScopedParameterStatement(stmt ast.Statement, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectScopedParameterExpression(stmt.Value, uri, stack, index)
	case *ast.ReturnStatement:
		collectScopedParameterExpression(stmt.ReturnValue, uri, stack, index)
	case *ast.ExpressionStatement:
		collectScopedParameterExpression(stmt.Expression, uri, stack, index)
	case *ast.AssignStatement:
		addScopedParameterRef(stmt.Name, uri, *stack, index)
		collectScopedParameterExpression(stmt.Value, uri, stack, index)
	case *ast.SetStatement:
		collectScopedParameterExpression(stmt.Left, uri, stack, index)
		collectScopedParameterExpression(stmt.Value, uri, stack, index)
	case *ast.WhileStatement:
		collectScopedParameterExpression(stmt.Condition, uri, stack, index)
		collectScopedParameterBlock(stmt.Body, uri, stack, index)
	case *ast.ForStatement:
		collectScopedParameterStatement(stmt.Init, uri, stack, index)
		collectScopedParameterExpression(stmt.Condition, uri, stack, index)
		collectScopedParameterStatement(stmt.Post, uri, stack, index)
		collectScopedParameterBlock(stmt.Body, uri, stack, index)
	case *ast.BlockStatement:
		collectScopedParameterBlock(stmt, uri, stack, index)
	}
}

func collectScopedParameterBlock(block *ast.BlockStatement, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex) {
	if block == nil {
		return
	}
	for _, stmt := range block.Statements {
		collectScopedParameterStatement(stmt, uri, stack, index)
	}
}

func collectScopedParameterExpression(expr ast.Expression, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex) {
	switch expr := expr.(type) {
	case *ast.Identifier:
		addScopedParameterRef(expr, uri, *stack, index)
	case *ast.PrefixExpression:
		collectScopedParameterExpression(expr.Right, uri, stack, index)
	case *ast.InfixExpression:
		collectScopedParameterExpression(expr.Left, uri, stack, index)
		collectScopedParameterExpression(expr.Right, uri, stack, index)
	case *ast.SpawnExpression:
		collectScopedParameterExpression(expr.Call, uri, stack, index)
	case *ast.IfExpression:
		collectScopedParameterExpression(expr.Condition, uri, stack, index)
		collectScopedParameterBlock(expr.Consequence, uri, stack, index)
		collectScopedParameterBlock(expr.Alternative, uri, stack, index)
	case *ast.FunctionLiteral:
		frame := map[string]resolvedSymbol{}
		for _, param := range expr.Parameters {
			if !validScopedParameterIdentifier(param) {
				continue
			}
			sym := resolvedSymbol{URI: uri, Symbol: sourceSymbol{
				Name:   param.Value,
				Kind:   "parameter",
				Detail: "parameter",
				Range:  tokenRange(param.Token),
			}}
			frame[param.Value] = sym
			decl := location{URI: uri, Range: sym.Symbol.Range}
			declKey := locationKey(decl)
			index.usesByLocation[declKey] = sym
			if _, ok := index.refsByDecl[declKey]; !ok {
				index.refsByDecl[declKey] = nil
			}
		}
		*stack = append(*stack, frame)
		collectScopedParameterBlock(expr.Body, uri, stack, index)
		*stack = (*stack)[:len(*stack)-1]
	case *ast.CallExpression:
		collectScopedParameterExpression(expr.Function, uri, stack, index)
		for _, arg := range expr.Arguments {
			collectScopedParameterExpression(arg, uri, stack, index)
		}
	case *ast.MemberExpression:
		collectScopedParameterExpression(expr.Left, uri, stack, index)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectScopedParameterExpression(elem, uri, stack, index)
		}
	case *ast.IndexExpression:
		collectScopedParameterExpression(expr.Left, uri, stack, index)
		collectScopedParameterExpression(expr.Index, uri, stack, index)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectScopedParameterExpression(key, uri, stack, index)
			collectScopedParameterExpression(value, uri, stack, index)
		}
	}
}

func addScopedParameterRef(ident *ast.Identifier, uri string, stack []map[string]resolvedSymbol, index scopedSymbolIndex) {
	if !validScopedParameterIdentifier(ident) {
		return
	}
	for i := len(stack) - 1; i >= 0; i-- {
		binding, ok := stack[i][ident.Value]
		if !ok {
			continue
		}
		ref := location{URI: uri, Range: tokenRange(ident.Token)}
		index.usesByLocation[locationKey(ref)] = binding
		declKey := locationKey(location{URI: binding.URI, Range: binding.Symbol.Range})
		index.refsByDecl[declKey] = append(index.refsByDecl[declKey], ref)
		return
	}
}

func validScopedParameterIdentifier(ident *ast.Identifier) bool {
	return ident != nil && ident.Token.Type == token.IDENT && ident.Token.Line > 0 && ident.Token.Column > 0
}
