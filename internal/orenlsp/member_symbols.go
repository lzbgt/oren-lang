package orenlsp

import (
	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/parser"
	"oren/pkg/token"
)

type typeFieldIndex struct {
	usesByLocation map[string]resolvedSymbol
	refsByDecl     map[string][]location
}

type typeInfo struct {
	Name   string
	Fields map[string]resolvedSymbol
}

func typedMemberSymbolAt(text, uri string, pos position, importedDocs []documentSnapshot, aliasByURI map[string]string) (resolvedSymbol, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return resolvedSymbol{}, false
	}
	index := collectTypedMemberSymbols(text, uri, importedDocs, aliasByURI)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name {
		return resolvedSymbol{}, false
	}
	return match, true
}

func typedMemberReferencesAt(text, uri string, pos position, includeDeclaration bool, importedDocs []documentSnapshot, aliasByURI map[string]string) ([]location, bool) {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return nil, false
	}
	index := collectTypedMemberSymbols(text, uri, importedDocs, aliasByURI)
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

func collectTypedMemberSymbols(text, uri string, importedDocs []documentSnapshot, aliasByURI map[string]string) typeFieldIndex {
	index := typeFieldIndex{
		usesByLocation: map[string]resolvedSymbol{},
		refsByDecl:     map[string][]location{},
	}
	p := parser.New(lexer.New(text))
	program := p.ParseProgram()
	if program == nil {
		return index
	}
	types := collectTypeInfos(program, uri, "")
	for _, doc := range importedDocs {
		alias := aliasByURI[doc.URI]
		if alias == "" {
			continue
		}
		importProgram := parser.New(lexer.New(doc.Text)).ParseProgram()
		for key, info := range collectTypeInfos(importProgram, doc.URI, alias+".") {
			types[key] = info
		}
	}
	if len(types) == 0 {
		return index
	}
	for _, info := range types {
		for _, field := range info.Fields {
			decl := location{URI: field.URI, Range: field.Symbol.Range}
			declKey := locationKey(decl)
			index.usesByLocation[declKey] = field
			if _, ok := index.refsByDecl[declKey]; !ok {
				index.refsByDecl[declKey] = nil
			}
		}
	}
	var stack []map[string]string
	stack = append(stack, map[string]string{})
	for _, stmt := range program.Statements {
		collectTypedMemberStatement(stmt, uri, types, &stack, index)
	}
	return index
}

func collectTypeInfos(program *ast.Program, uri, prefix string) map[string]typeInfo {
	out := map[string]typeInfo{}
	if program == nil {
		return out
	}
	for _, stmt := range program.Statements {
		ts, ok := stmt.(*ast.TypeStatement)
		if !ok || ts.Name == nil || ts.Name.Value == "" {
			continue
		}
		typeKey := prefix + ts.Name.Value
		info := typeInfo{Name: typeKey, Fields: map[string]resolvedSymbol{}}
		for _, field := range ts.Fields {
			if !validMemberIdentifier(field) {
				continue
			}
			sym := resolvedSymbol{URI: uri, Symbol: sourceSymbol{
				Name:   field.Value,
				Kind:   "property",
				Detail: typeKey + " property",
				Range:  tokenRange(field.Token),
			}}
			info.Fields[field.Value] = sym
		}
		out[typeKey] = info
	}
	return out
}

func collectTypedMemberStatement(stmt ast.Statement, uri string, types map[string]typeInfo, stack *[]map[string]string, index typeFieldIndex) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectTypedMemberExpression(stmt.Value, uri, types, stack, index)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, types, *stack), *stack)
	case *ast.ReturnStatement:
		collectTypedMemberExpression(stmt.ReturnValue, uri, types, stack, index)
	case *ast.ExpressionStatement:
		collectTypedMemberExpression(stmt.Expression, uri, types, stack, index)
	case *ast.AssignStatement:
		collectTypedMemberExpression(stmt.Value, uri, types, stack, index)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, types, *stack), *stack)
	case *ast.SetStatement:
		collectTypedMemberExpression(stmt.Left, uri, types, stack, index)
		collectTypedMemberExpression(stmt.Value, uri, types, stack, index)
	case *ast.WhileStatement:
		collectTypedMemberExpression(stmt.Condition, uri, types, stack, index)
		collectTypedMemberBlock(stmt.Body, uri, types, stack, index)
	case *ast.ForStatement:
		collectTypedMemberStatement(stmt.Init, uri, types, stack, index)
		collectTypedMemberExpression(stmt.Condition, uri, types, stack, index)
		collectTypedMemberStatement(stmt.Post, uri, types, stack, index)
		collectTypedMemberBlock(stmt.Body, uri, types, stack, index)
	case *ast.BlockStatement:
		collectTypedMemberBlock(stmt, uri, types, stack, index)
	}
}

func collectTypedMemberBlock(block *ast.BlockStatement, uri string, types map[string]typeInfo, stack *[]map[string]string, index typeFieldIndex) {
	if block == nil {
		return
	}
	*stack = append(*stack, map[string]string{})
	for _, stmt := range block.Statements {
		collectTypedMemberStatement(stmt, uri, types, stack, index)
	}
	*stack = (*stack)[:len(*stack)-1]
}

func collectTypedMemberExpression(expr ast.Expression, uri string, types map[string]typeInfo, stack *[]map[string]string, index typeFieldIndex) {
	switch expr := expr.(type) {
	case *ast.PrefixExpression:
		collectTypedMemberExpression(expr.Right, uri, types, stack, index)
	case *ast.InfixExpression:
		collectTypedMemberExpression(expr.Left, uri, types, stack, index)
		collectTypedMemberExpression(expr.Right, uri, types, stack, index)
	case *ast.SpawnExpression:
		collectTypedMemberExpression(expr.Call, uri, types, stack, index)
	case *ast.IfExpression:
		collectTypedMemberExpression(expr.Condition, uri, types, stack, index)
		collectTypedMemberBlock(expr.Consequence, uri, types, stack, index)
		collectTypedMemberBlock(expr.Alternative, uri, types, stack, index)
	case *ast.FunctionLiteral:
		*stack = append(*stack, map[string]string{})
		collectTypedMemberBlock(expr.Body, uri, types, stack, index)
		*stack = (*stack)[:len(*stack)-1]
	case *ast.CallExpression:
		collectTypedMemberExpression(expr.Function, uri, types, stack, index)
		for _, arg := range expr.Arguments {
			collectTypedMemberExpression(arg, uri, types, stack, index)
		}
	case *ast.MemberExpression:
		collectTypedMemberExpression(expr.Left, uri, types, stack, index)
		addTypedMemberRef(expr, uri, types, *stack, index)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectTypedMemberExpression(elem, uri, types, stack, index)
		}
	case *ast.IndexExpression:
		collectTypedMemberExpression(expr.Left, uri, types, stack, index)
		collectTypedMemberExpression(expr.Index, uri, types, stack, index)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectTypedMemberExpression(key, uri, types, stack, index)
			collectTypedMemberExpression(value, uri, types, stack, index)
		}
	}
}

func addTypedMemberRef(expr *ast.MemberExpression, uri string, types map[string]typeInfo, stack []map[string]string, index typeFieldIndex) {
	if expr == nil || !validMemberIdentifier(expr.Property) {
		return
	}
	left, ok := expr.Left.(*ast.Identifier)
	if !ok || !validMemberIdentifier(left) {
		return
	}
	typeName := lookupInferredVarType(left.Value, stack)
	if typeName == "" {
		return
	}
	info, ok := types[typeName]
	if !ok {
		return
	}
	field, ok := info.Fields[expr.Property.Value]
	if !ok {
		return
	}
	ref := location{URI: uri, Range: tokenRange(expr.Property.Token)}
	index.usesByLocation[locationKey(ref)] = field
	decl := location{URI: field.URI, Range: field.Symbol.Range}
	declKey := locationKey(decl)
	index.refsByDecl[declKey] = append(index.refsByDecl[declKey], ref)
}

func inferExpressionType(expr ast.Expression, types map[string]typeInfo, stack []map[string]string) string {
	switch expr := expr.(type) {
	case *ast.Identifier:
		return lookupInferredVarType(expr.Value, stack)
	case *ast.CallExpression:
		typeKey := constructorTypeKey(expr.Function)
		if _, ok := types[typeKey]; ok {
			return typeKey
		}
	}
	return ""
}

func constructorTypeKey(expr ast.Expression) string {
	switch expr := expr.(type) {
	case *ast.Identifier:
		if validMemberIdentifier(expr) {
			return expr.Value
		}
	case *ast.MemberExpression:
		left, ok := expr.Left.(*ast.Identifier)
		if ok && validMemberIdentifier(left) && validMemberIdentifier(expr.Property) {
			return left.Value + "." + expr.Property.Value
		}
	}
	return ""
}

func setInferredVarType(ident *ast.Identifier, typeName string, stack []map[string]string) {
	if !validMemberIdentifier(ident) || len(stack) == 0 {
		return
	}
	scope := stack[len(stack)-1]
	if typeName == "" {
		delete(scope, ident.Value)
		return
	}
	scope[ident.Value] = typeName
}

func lookupInferredVarType(name string, stack []map[string]string) string {
	for i := len(stack) - 1; i >= 0; i-- {
		if typeName := stack[i][name]; typeName != "" {
			return typeName
		}
	}
	return ""
}

func validMemberIdentifier(ident *ast.Identifier) bool {
	return ident != nil && ident.Token.Type == token.IDENT && ident.Token.Line > 0 && ident.Token.Column > 0
}
