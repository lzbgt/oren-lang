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
	index := collectScopedSymbols(text, uri, false)
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
	index := collectScopedSymbols(text, uri, false)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name {
		return nil, false
	}
	return scopedSymbolReferencesForMatch(index, match, includeDeclaration), true
}

func scopedLocalSymbolAt(text, uri string, pos position) (resolvedSymbol, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return resolvedSymbol{}, false
	}
	index := collectScopedSymbols(text, uri, true)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name || match.Symbol.Kind != "variable" {
		return resolvedSymbol{}, false
	}
	return match, true
}

func scopedLocalReferencesAt(text, uri string, pos position, includeDeclaration bool) ([]location, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return nil, false
	}
	index := collectScopedSymbols(text, uri, true)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name || match.Symbol.Kind != "variable" {
		return nil, false
	}
	return scopedSymbolReferencesForMatch(index, match, includeDeclaration), true
}

func scopedSymbolReferencesForMatch(index scopedSymbolIndex, match resolvedSymbol, includeDeclaration bool) []location {
	decl := location{URI: match.URI, Range: match.Symbol.Range}
	refs := index.refsByDecl[locationKey(decl)]
	out := make([]location, 0, len(refs)+1)
	if includeDeclaration {
		out = append(out, decl)
	}
	out = append(out, refs...)
	return uniqueLocations(out)
}

func collectScopedSymbols(text, uri string, includeLocals bool) scopedSymbolIndex {
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
		collectScopedSymbolStatement(stmt, uri, &stack, index, includeLocals)
	}
	return index
}

func collectScopedSymbolStatement(stmt ast.Statement, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex, includeLocals bool) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectScopedSymbolExpression(stmt.Value, uri, stack, index, includeLocals)
		if includeLocals {
			addScopedLocalBinding(stmt.Name, uri, stack, index)
		}
	case *ast.ReturnStatement:
		collectScopedSymbolExpression(stmt.ReturnValue, uri, stack, index, includeLocals)
	case *ast.ExpressionStatement:
		collectScopedSymbolExpression(stmt.Expression, uri, stack, index, includeLocals)
	case *ast.AssignStatement:
		addScopedSymbolRef(stmt.Name, uri, *stack, index)
		collectScopedSymbolExpression(stmt.Value, uri, stack, index, includeLocals)
	case *ast.SetStatement:
		collectScopedSymbolExpression(stmt.Left, uri, stack, index, includeLocals)
		collectScopedSymbolExpression(stmt.Value, uri, stack, index, includeLocals)
	case *ast.WhileStatement:
		collectScopedSymbolExpression(stmt.Condition, uri, stack, index, includeLocals)
		collectScopedSymbolBlock(stmt.Body, uri, stack, index, includeLocals)
	case *ast.ForStatement:
		if includeLocals {
			*stack = append(*stack, map[string]resolvedSymbol{})
			defer func() { *stack = (*stack)[:len(*stack)-1] }()
		}
		collectScopedSymbolStatement(stmt.Init, uri, stack, index, includeLocals)
		collectScopedSymbolExpression(stmt.Condition, uri, stack, index, includeLocals)
		collectScopedSymbolStatement(stmt.Post, uri, stack, index, includeLocals)
		collectScopedSymbolBlock(stmt.Body, uri, stack, index, includeLocals)
	case *ast.BlockStatement:
		collectScopedSymbolBlock(stmt, uri, stack, index, includeLocals)
	}
}

func collectScopedSymbolBlock(block *ast.BlockStatement, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex, includeLocals bool) {
	if block == nil {
		return
	}
	if includeLocals {
		*stack = append(*stack, map[string]resolvedSymbol{})
		defer func() { *stack = (*stack)[:len(*stack)-1] }()
	}
	for _, stmt := range block.Statements {
		collectScopedSymbolStatement(stmt, uri, stack, index, includeLocals)
	}
}

func collectScopedSymbolExpression(expr ast.Expression, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex, includeLocals bool) {
	switch expr := expr.(type) {
	case *ast.Identifier:
		addScopedSymbolRef(expr, uri, *stack, index)
	case *ast.PrefixExpression:
		collectScopedSymbolExpression(expr.Right, uri, stack, index, includeLocals)
	case *ast.InfixExpression:
		collectScopedSymbolExpression(expr.Left, uri, stack, index, includeLocals)
		collectScopedSymbolExpression(expr.Right, uri, stack, index, includeLocals)
	case *ast.SpawnExpression:
		collectScopedSymbolExpression(expr.Call, uri, stack, index, includeLocals)
	case *ast.IfExpression:
		collectScopedSymbolExpression(expr.Condition, uri, stack, index, includeLocals)
		collectScopedSymbolBlock(expr.Consequence, uri, stack, index, includeLocals)
		collectScopedSymbolBlock(expr.Alternative, uri, stack, index, includeLocals)
	case *ast.FunctionLiteral:
		frame := map[string]resolvedSymbol{}
		for _, param := range expr.Parameters {
			if !validScopedIdentifier(param) {
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
		collectScopedSymbolBlock(expr.Body, uri, stack, index, includeLocals)
		*stack = (*stack)[:len(*stack)-1]
	case *ast.CallExpression:
		collectScopedSymbolExpression(expr.Function, uri, stack, index, includeLocals)
		for _, arg := range expr.Arguments {
			collectScopedSymbolExpression(arg, uri, stack, index, includeLocals)
		}
	case *ast.MemberExpression:
		collectScopedSymbolExpression(expr.Left, uri, stack, index, includeLocals)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectScopedSymbolExpression(elem, uri, stack, index, includeLocals)
		}
	case *ast.IndexExpression:
		collectScopedSymbolExpression(expr.Left, uri, stack, index, includeLocals)
		collectScopedSymbolExpression(expr.Index, uri, stack, index, includeLocals)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectScopedSymbolExpression(key, uri, stack, index, includeLocals)
			collectScopedSymbolExpression(value, uri, stack, index, includeLocals)
		}
	}
}

func addScopedLocalBinding(ident *ast.Identifier, uri string, stack *[]map[string]resolvedSymbol, index scopedSymbolIndex) {
	if !validScopedIdentifier(ident) || len(*stack) == 0 {
		return
	}
	sym := resolvedSymbol{URI: uri, Symbol: sourceSymbol{
		Name:   ident.Value,
		Kind:   "variable",
		Detail: "local variable",
		Range:  tokenRange(ident.Token),
	}}
	(*stack)[len(*stack)-1][ident.Value] = sym
	decl := location{URI: uri, Range: sym.Symbol.Range}
	declKey := locationKey(decl)
	index.usesByLocation[declKey] = sym
	if _, ok := index.refsByDecl[declKey]; !ok {
		index.refsByDecl[declKey] = nil
	}
}

func addScopedSymbolRef(ident *ast.Identifier, uri string, stack []map[string]resolvedSymbol, index scopedSymbolIndex) {
	if !validScopedIdentifier(ident) {
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

func validScopedIdentifier(ident *ast.Identifier) bool {
	return ident != nil && ident.Token.Type == token.IDENT && ident.Token.Line > 0 && ident.Token.Column > 0
}
