package orenlsp

import (
	"sort"
	"strings"

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

type memberTypeEnv struct {
	Types     map[string]typeInfo
	Functions map[string]string
	Params    map[string]map[string]string
	Prefix    string
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

func typedMemberCompletionItemsAt(text, uri string, pos position, importedDocs []documentSnapshot, aliasByURI map[string]string) ([]completionItem, bool) {
	receiver, partial, ok := memberCompletionTarget(text, pos)
	if !ok {
		return nil, false
	}
	program, env := typedMemberAnalysisEnv(text, uri, importedDocs, aliasByURI)
	typeName := parsedMemberTypeAt(text, uri, pos, importedDocs, aliasByURI)
	if typeName == "" {
		typeName = inferredReceiverExpressionTypeAt(program, receiver, pos, env)
	}
	if typeName == "" {
		recoveryText := textWithCompletionLinesBlanked(text, pos.Line)
		if recoveryText != text {
			recoveryProgram, recoveryEnv := typedMemberAnalysisEnv(recoveryText, uri, importedDocs, aliasByURI)
			typeName = inferredReceiverExpressionTypeAt(recoveryProgram, receiver, pos, recoveryEnv)
			env = recoveryEnv
		}
	}
	if typeName == "" {
		return []completionItem{}, true
	}
	return memberCompletionItemsForType(env, typeName, partial), true
}

func textWithCompletionLinesBlanked(text string, line int) string {
	if line < 0 {
		return text
	}
	lines := strings.Split(text, "\n")
	if line >= len(lines) {
		return text
	}
	changed := false
	for i, textLine := range lines {
		if i == line || strings.HasSuffix(strings.TrimSpace(textLine), ".") {
			if lines[i] != "" {
				lines[i] = ""
				changed = true
			}
		}
	}
	if !changed {
		return text
	}
	return strings.Join(lines, "\n")
}

func memberCompletionItemsForType(env memberTypeEnv, typeName, partial string) []completionItem {
	info, ok := env.Types[typeName]
	if !ok {
		return []completionItem{}
	}
	fields := make([]resolvedSymbol, 0, len(info.Fields))
	for _, field := range info.Fields {
		if partial != "" && !strings.HasPrefix(field.Symbol.Name, partial) {
			continue
		}
		fields = append(fields, field)
	}
	sort.Slice(fields, func(i, j int) bool {
		if fields[i].Symbol.Name == fields[j].Symbol.Name {
			return fields[i].Symbol.Detail < fields[j].Symbol.Detail
		}
		return fields[i].Symbol.Name < fields[j].Symbol.Name
	})
	items := make([]completionItem, 0, len(fields))
	for _, field := range fields {
		items = append(items, completionItem{Label: field.Symbol.Name, Kind: lspCompletionField, Detail: field.Symbol.Detail})
	}
	return items
}

func parsedMemberTypeAt(text, uri string, pos position, importedDocs []documentSnapshot, aliasByURI map[string]string) string {
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return ""
	}
	index := collectTypedMemberSymbols(text, uri, importedDocs, aliasByURI)
	match, ok := index.usesByLocation[locationKey(location{URI: uri, Range: rng})]
	if !ok || match.Symbol.Name != name {
		return ""
	}
	return strings.TrimSuffix(match.Symbol.Detail, " property")
}

func collectTypedMemberSymbols(text, uri string, importedDocs []documentSnapshot, aliasByURI map[string]string) typeFieldIndex {
	index := typeFieldIndex{
		usesByLocation: map[string]resolvedSymbol{},
		refsByDecl:     map[string][]location{},
	}
	program, env := typedMemberAnalysisEnv(text, uri, importedDocs, aliasByURI)
	if program == nil {
		return index
	}
	if len(env.Types) == 0 {
		return index
	}
	for _, info := range env.Types {
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
		collectTypedMemberStatement(stmt, uri, env, &stack, index)
	}
	return index
}

func typedMemberAnalysisEnv(text, uri string, importedDocs []documentSnapshot, aliasByURI map[string]string) (*ast.Program, memberTypeEnv) {
	p := parser.New(lexer.New(text))
	program := p.ParseProgram()
	if program == nil {
		return nil, memberTypeEnv{}
	}
	env := memberTypeEnv{Types: collectTypeInfos(program, uri, "")}
	for _, doc := range importedDocs {
		alias := aliasByURI[doc.URI]
		if alias == "" {
			continue
		}
		importProgram := parser.New(lexer.New(doc.Text)).ParseProgram()
		for key, info := range collectTypeInfos(importProgram, doc.URI, alias+".") {
			env.Types[key] = info
		}
	}
	env.Functions = collectFunctionReturnTypes(program, "", env.Types, nil)
	for _, doc := range importedDocs {
		alias := aliasByURI[doc.URI]
		if alias == "" {
			continue
		}
		importProgram := parser.New(lexer.New(doc.Text)).ParseProgram()
		for key, typeName := range collectFunctionReturnTypes(importProgram, alias+".", env.Types, nil) {
			env.Functions[key] = typeName
		}
	}
	env.Params = collectFunctionParamTypes(program, env)
	for key, typeName := range collectFunctionReturnTypes(program, "", env.Types, env.Params) {
		env.Functions[key] = typeName
	}
	return program, env
}

func inferredReceiverTypeAt(program *ast.Program, receiver string, pos position, env memberTypeEnv) string {
	return inferredReceiverExpressionTypeAt(program, receiver, pos, env)
}

func inferredReceiverExpressionTypeAt(program *ast.Program, receiver string, pos position, env memberTypeEnv) string {
	if program == nil || receiver == "" {
		return ""
	}
	var stack []map[string]string
	stack = append(stack, map[string]string{})
	for _, stmt := range program.Statements {
		collectInferredTypesUntil(stmt, pos, env, &stack)
	}
	expr := parseMemberReceiverExpression(receiver)
	if expr == nil {
		return ""
	}
	return inferExpressionType(expr, env, stack)
}

func memberCompletionTarget(text string, pos position) (receiver, partial string, ok bool) {
	lines := strings.Split(text, "\n")
	if pos.Line < 0 || pos.Line >= len(lines) {
		return "", "", false
	}
	line := []rune(lines[pos.Line])
	col := pos.Character
	if col < 0 {
		return "", "", false
	}
	if col > len(line) {
		col = len(line)
	}
	prefix := line[:col]
	partialStart := len(prefix)
	for partialStart > 0 && isIdentRune(prefix[partialStart-1]) {
		partialStart--
	}
	if partialStart == 0 || prefix[partialStart-1] != '.' {
		return "", "", false
	}
	receiverEnd := partialStart - 1
	receiverStart := memberReceiverStart(prefix, receiverEnd)
	if receiverStart < 0 || receiverStart == receiverEnd {
		return "", "", false
	}
	receiver = strings.TrimSpace(string(prefix[receiverStart:receiverEnd]))
	partial = string(prefix[partialStart:])
	return receiver, partial, true
}

func memberReceiverStart(prefix []rune, receiverEnd int) int {
	i := receiverEnd - 1
	for i >= 0 && isSpaceRune(prefix[i]) {
		i--
	}
	if i < 0 {
		return -1
	}
	depth := 0
	start := i + 1
	for ; i >= 0; i-- {
		ch := prefix[i]
		switch ch {
		case ')', ']', '}':
			depth++
		case '(', '[', '{':
			if depth == 0 {
				return i + 1
			}
			depth--
		}
		if depth == 0 && isMemberReceiverBoundary(ch) {
			return i + 1
		}
		start = i
	}
	return start
}

func isMemberReceiverBoundary(ch rune) bool {
	if isSpaceRune(ch) {
		return true
	}
	switch ch {
	case '=', '+', '-', '*', '/', '%', '!', '<', '>', '?', ':', ';', ',':
		return true
	}
	return false
}

func isSpaceRune(ch rune) bool {
	return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n'
}

func parseMemberReceiverExpression(src string) ast.Expression {
	src = strings.TrimSpace(src)
	if src == "" {
		return nil
	}
	program := parser.New(lexer.New("var __oren_lsp_receiver = " + src + "\n")).ParseProgram()
	if program == nil || len(program.Statements) != 1 {
		return nil
	}
	stmt, ok := program.Statements[0].(*ast.VarStatement)
	if !ok {
		return nil
	}
	return stmt.Value
}

func collectInferredTypesUntil(stmt ast.Statement, pos position, env memberTypeEnv, stack *[]map[string]string) {
	if stmt == nil || !statementStartsBeforeOrAt(stmt, pos) {
		return
	}
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.AssignStatement:
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.ExpressionStatement:
		collectInferredExpressionTypesUntil(stmt.Expression, pos, env, stack)
	case *ast.ReturnStatement:
		collectInferredExpressionTypesUntil(stmt.ReturnValue, pos, env, stack)
	case *ast.SetStatement:
		collectInferredExpressionTypesUntil(stmt.Left, pos, env, stack)
		collectInferredExpressionTypesUntil(stmt.Value, pos, env, stack)
	case *ast.WhileStatement:
		collectInferredExpressionTypesUntil(stmt.Condition, pos, env, stack)
		collectInferredBlockTypesUntil(stmt.Body, pos, env, stack)
	case *ast.ForStatement:
		collectInferredTypesUntil(stmt.Init, pos, env, stack)
		collectInferredExpressionTypesUntil(stmt.Condition, pos, env, stack)
		collectInferredTypesUntil(stmt.Post, pos, env, stack)
		collectInferredBlockTypesUntil(stmt.Body, pos, env, stack)
	case *ast.BlockStatement:
		collectInferredBlockTypesUntil(stmt, pos, env, stack)
	}
}

func collectInferredBlockTypesUntil(block *ast.BlockStatement, pos position, env memberTypeEnv, stack *[]map[string]string) {
	if block == nil || !tokenStartsBeforeOrAt(block.Token, pos) {
		return
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()
	for _, stmt := range block.Statements {
		collectInferredTypesUntil(stmt, pos, env, stack)
	}
}

func collectInferredExpressionTypesUntil(expr ast.Expression, pos position, env memberTypeEnv, stack *[]map[string]string) {
	switch expr := expr.(type) {
	case *ast.FunctionLiteral:
		if expr.Body == nil || !tokenStartsBeforeOrAt(expr.Token, pos) {
			return
		}
		*stack = append(*stack, inferredParamFrame(expr, env))
		defer func() { *stack = (*stack)[:len(*stack)-1] }()
		for _, stmt := range expr.Body.Statements {
			collectInferredTypesUntil(stmt, pos, env, stack)
		}
	case *ast.IfExpression:
		collectInferredExpressionTypesUntil(expr.Condition, pos, env, stack)
		collectInferredBlockTypesUntil(expr.Consequence, pos, env, stack)
		collectInferredBlockTypesUntil(expr.Alternative, pos, env, stack)
		applyIfBranchAssignmentEffects(expr, env, stack)
	case *ast.CallExpression:
		collectInferredExpressionTypesUntil(expr.Function, pos, env, stack)
		for _, arg := range expr.Arguments {
			collectInferredExpressionTypesUntil(arg, pos, env, stack)
		}
	case *ast.MemberExpression:
		collectInferredExpressionTypesUntil(expr.Left, pos, env, stack)
	case *ast.PrefixExpression:
		collectInferredExpressionTypesUntil(expr.Right, pos, env, stack)
	case *ast.InfixExpression:
		collectInferredExpressionTypesUntil(expr.Left, pos, env, stack)
		collectInferredExpressionTypesUntil(expr.Right, pos, env, stack)
	case *ast.SpawnExpression:
		collectInferredExpressionTypesUntil(expr.Call, pos, env, stack)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectInferredExpressionTypesUntil(elem, pos, env, stack)
		}
	case *ast.IndexExpression:
		collectInferredExpressionTypesUntil(expr.Left, pos, env, stack)
		collectInferredExpressionTypesUntil(expr.Index, pos, env, stack)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectInferredExpressionTypesUntil(key, pos, env, stack)
			collectInferredExpressionTypesUntil(value, pos, env, stack)
		}
	}
}

func statementStartsBeforeOrAt(stmt ast.Statement, pos position) bool {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.ReturnStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.ExpressionStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.ImportStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.TypeStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.WhileStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.ForStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.AssignStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.SetStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.FFIStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	case *ast.BlockStatement:
		return tokenStartsBeforeOrAt(stmt.Token, pos)
	default:
		return false
	}
}

func tokenStartsBeforeOrAt(tok token.Token, pos position) bool {
	line := tok.Line - 1
	character := tok.Column - 1
	if line < 0 || character < 0 {
		return false
	}
	return line < pos.Line || (line == pos.Line && character <= pos.Character)
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

func collectFunctionReturnTypes(program *ast.Program, prefix string, types map[string]typeInfo, params map[string]map[string]string) map[string]string {
	out := map[string]string{}
	if program == nil {
		return out
	}
	env := memberTypeEnv{Types: types, Functions: map[string]string{}, Params: params, Prefix: prefix}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		typeName := inferFunctionReturnType(fn, env)
		if typeName != "" {
			out[prefix+fn.Name] = typeName
			env.Functions[prefix+fn.Name] = typeName
		}
	}
	return out
}

func collectFunctionParamTypes(program *ast.Program, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	functions := map[string]*ast.FunctionLiteral{}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn != nil && fn.Name != "" {
			functions[fn.Name] = fn
		}
	}
	if len(functions) == 0 {
		return out
	}
	conflicts := map[string]bool{}
	var stack []map[string]string
	stack = append(stack, map[string]string{})
	for _, stmt := range program.Statements {
		collectFunctionParamStatementTypes(stmt, env, functions, &stack, out, conflicts)
	}
	return out
}

func namedFunctionLiteral(stmt ast.Statement) *ast.FunctionLiteral {
	es, ok := stmt.(*ast.ExpressionStatement)
	if !ok {
		return nil
	}
	fn, ok := es.Expression.(*ast.FunctionLiteral)
	if !ok || fn.Name == "" {
		return nil
	}
	return fn
}

func inferFunctionReturnType(fn *ast.FunctionLiteral, env memberTypeEnv) string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnType(fn.Body, env, &stack)
}

func inferBlockReturnType(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) string {
	if block == nil {
		return ""
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred string
	for _, stmt := range block.Statements {
		next := inferStatementReturnType(stmt, env, stack)
		if next == "" {
			continue
		}
		if inferred == "" {
			inferred = next
			continue
		}
		if inferred != next {
			return ""
		}
	}
	return inferred
}

func inferStatementReturnType(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.AssignStatement:
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.ReturnStatement:
		return inferExpressionType(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		return inferExpressionReturnType(stmt.Expression, env, stack)
	case *ast.BlockStatement:
		return inferBlockReturnType(stmt, env, stack)
	case *ast.WhileStatement:
		return inferBlockReturnType(stmt.Body, env, stack)
	case *ast.ForStatement:
		if stmt.Init != nil {
			_ = inferStatementReturnType(stmt.Init, env, stack)
		}
		if stmt.Post != nil {
			_ = inferStatementReturnType(stmt.Post, env, stack)
		}
		return inferBlockReturnType(stmt.Body, env, stack)
	}
	return ""
}

func inferExpressionReturnType(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string) string {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if typeName := inferIfExpressionType(expr, env, *stack); typeName != "" {
			return typeName
		}
		applyIfBranchAssignmentEffects(expr, env, stack)
	}
	return ""
}

func applyIfBranchAssignmentEffects(expr *ast.IfExpression, env memberTypeEnv, stack *[]map[string]string) {
	if expr == nil || expr.Consequence == nil || expr.Alternative == nil || stack == nil {
		return
	}
	consequence := collectBranchAssignmentEffects(expr.Consequence, env, *stack)
	alternative := collectBranchAssignmentEffects(expr.Alternative, env, *stack)
	for name, typeName := range mergeBranchAssignmentEffects(consequence, alternative) {
		setInferredNameType(name, typeName, *stack)
	}
}

func collectBranchAssignmentEffects(block *ast.BlockStatement, env memberTypeEnv, stack []map[string]string) map[string]string {
	effects := map[string]string{}
	if block == nil {
		return effects
	}
	localStack := append([]map[string]string{}, stack...)
	localStack = append(localStack, map[string]string{})
	for _, stmt := range block.Statements {
		collectStatementAssignmentEffects(stmt, env, &localStack, effects)
	}
	return effects
}

func collectStatementAssignmentEffects(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string, effects map[string]string) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.AssignStatement:
		if !validMemberIdentifier(stmt.Name) {
			return
		}
		typeName := inferExpressionType(stmt.Value, env, *stack)
		effects[stmt.Name.Value] = typeName
		setInferredNameType(stmt.Name.Value, typeName, *stack)
	case *ast.ExpressionStatement:
		collectExpressionAssignmentEffects(stmt.Expression, env, stack, effects)
	case *ast.BlockStatement:
		localStack := append(*stack, map[string]string{})
		for _, nested := range stmt.Statements {
			collectStatementAssignmentEffects(nested, env, &localStack, effects)
		}
	case *ast.ForStatement:
		collectStatementAssignmentEffects(stmt.Init, env, stack, effects)
		collectExpressionAssignmentEffects(stmt.Condition, env, stack, effects)
		collectStatementAssignmentEffects(stmt.Post, env, stack, effects)
	case *ast.SetStatement:
		collectExpressionAssignmentEffects(stmt.Left, env, stack, effects)
		collectExpressionAssignmentEffects(stmt.Value, env, stack, effects)
	case *ast.ReturnStatement:
		collectExpressionAssignmentEffects(stmt.ReturnValue, env, stack, effects)
	}
}

func collectExpressionAssignmentEffects(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string, effects map[string]string) {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if expr.Consequence == nil || expr.Alternative == nil {
			return
		}
		for name, typeName := range mergeBranchAssignmentEffects(
			collectBranchAssignmentEffects(expr.Consequence, env, *stack),
			collectBranchAssignmentEffects(expr.Alternative, env, *stack),
		) {
			effects[name] = typeName
			setInferredNameType(name, typeName, *stack)
		}
	case *ast.PrefixExpression:
		collectExpressionAssignmentEffects(expr.Right, env, stack, effects)
	case *ast.InfixExpression:
		collectExpressionAssignmentEffects(expr.Left, env, stack, effects)
		collectExpressionAssignmentEffects(expr.Right, env, stack, effects)
	case *ast.SpawnExpression:
		collectExpressionAssignmentEffects(expr.Call, env, stack, effects)
	case *ast.CallExpression:
		collectExpressionAssignmentEffects(expr.Function, env, stack, effects)
		for _, arg := range expr.Arguments {
			collectExpressionAssignmentEffects(arg, env, stack, effects)
		}
	case *ast.MemberExpression:
		collectExpressionAssignmentEffects(expr.Left, env, stack, effects)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectExpressionAssignmentEffects(elem, env, stack, effects)
		}
	case *ast.IndexExpression:
		collectExpressionAssignmentEffects(expr.Left, env, stack, effects)
		collectExpressionAssignmentEffects(expr.Index, env, stack, effects)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectExpressionAssignmentEffects(key, env, stack, effects)
			collectExpressionAssignmentEffects(value, env, stack, effects)
		}
	}
}

func mergeBranchAssignmentEffects(consequence, alternative map[string]string) map[string]string {
	merged := map[string]string{}
	for name, consequenceType := range consequence {
		alternativeType, ok := alternative[name]
		if ok && consequenceType != "" && consequenceType == alternativeType {
			merged[name] = consequenceType
			continue
		}
		merged[name] = ""
	}
	for name := range alternative {
		if _, ok := consequence[name]; !ok {
			merged[name] = ""
		}
	}
	return merged
}

func collectFunctionParamStatementTypes(stmt ast.Statement, env memberTypeEnv, functions map[string]*ast.FunctionLiteral, stack *[]map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectFunctionParamExpressionTypes(stmt.Value, env, functions, stack, out, conflicts)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.ReturnStatement:
		collectFunctionParamExpressionTypes(stmt.ReturnValue, env, functions, stack, out, conflicts)
	case *ast.ExpressionStatement:
		collectFunctionParamExpressionTypes(stmt.Expression, env, functions, stack, out, conflicts)
	case *ast.AssignStatement:
		collectFunctionParamExpressionTypes(stmt.Value, env, functions, stack, out, conflicts)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.SetStatement:
		collectFunctionParamExpressionTypes(stmt.Left, env, functions, stack, out, conflicts)
		collectFunctionParamExpressionTypes(stmt.Value, env, functions, stack, out, conflicts)
	case *ast.WhileStatement:
		collectFunctionParamExpressionTypes(stmt.Condition, env, functions, stack, out, conflicts)
		collectFunctionParamBlockTypes(stmt.Body, env, functions, stack, out, conflicts)
	case *ast.ForStatement:
		collectFunctionParamStatementTypes(stmt.Init, env, functions, stack, out, conflicts)
		collectFunctionParamExpressionTypes(stmt.Condition, env, functions, stack, out, conflicts)
		collectFunctionParamStatementTypes(stmt.Post, env, functions, stack, out, conflicts)
		collectFunctionParamBlockTypes(stmt.Body, env, functions, stack, out, conflicts)
	case *ast.BlockStatement:
		collectFunctionParamBlockTypes(stmt, env, functions, stack, out, conflicts)
	}
}

func collectFunctionParamBlockTypes(block *ast.BlockStatement, env memberTypeEnv, functions map[string]*ast.FunctionLiteral, stack *[]map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if block == nil {
		return
	}
	*stack = append(*stack, map[string]string{})
	for _, stmt := range block.Statements {
		collectFunctionParamStatementTypes(stmt, env, functions, stack, out, conflicts)
	}
	*stack = (*stack)[:len(*stack)-1]
}

func collectFunctionParamExpressionTypes(expr ast.Expression, env memberTypeEnv, functions map[string]*ast.FunctionLiteral, stack *[]map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	switch expr := expr.(type) {
	case *ast.PrefixExpression:
		collectFunctionParamExpressionTypes(expr.Right, env, functions, stack, out, conflicts)
	case *ast.InfixExpression:
		collectFunctionParamExpressionTypes(expr.Left, env, functions, stack, out, conflicts)
		collectFunctionParamExpressionTypes(expr.Right, env, functions, stack, out, conflicts)
	case *ast.SpawnExpression:
		collectFunctionParamExpressionTypes(expr.Call, env, functions, stack, out, conflicts)
	case *ast.IfExpression:
		collectFunctionParamExpressionTypes(expr.Condition, env, functions, stack, out, conflicts)
		collectFunctionParamBlockTypes(expr.Consequence, env, functions, stack, out, conflicts)
		collectFunctionParamBlockTypes(expr.Alternative, env, functions, stack, out, conflicts)
		applyIfBranchAssignmentEffects(expr, env, stack)
	case *ast.FunctionLiteral:
		*stack = append(*stack, inferredParamFrame(expr, env))
		collectFunctionParamBlockTypes(expr.Body, env, functions, stack, out, conflicts)
		*stack = (*stack)[:len(*stack)-1]
	case *ast.CallExpression:
		collectCallParamTypes(expr, env, functions, *stack, out, conflicts)
		collectFunctionParamExpressionTypes(expr.Function, env, functions, stack, out, conflicts)
		for _, arg := range expr.Arguments {
			collectFunctionParamExpressionTypes(arg, env, functions, stack, out, conflicts)
		}
	case *ast.MemberExpression:
		collectFunctionParamExpressionTypes(expr.Left, env, functions, stack, out, conflicts)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectFunctionParamExpressionTypes(elem, env, functions, stack, out, conflicts)
		}
	case *ast.IndexExpression:
		collectFunctionParamExpressionTypes(expr.Left, env, functions, stack, out, conflicts)
		collectFunctionParamExpressionTypes(expr.Index, env, functions, stack, out, conflicts)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectFunctionParamExpressionTypes(key, env, functions, stack, out, conflicts)
			collectFunctionParamExpressionTypes(value, env, functions, stack, out, conflicts)
		}
	}
}

func collectCallParamTypes(call *ast.CallExpression, env memberTypeEnv, functions map[string]*ast.FunctionLiteral, stack []map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	fnName := calledFunctionName(call.Function)
	fn := functions[fnName]
	if fn == nil {
		return
	}
	for i, arg := range call.Arguments {
		if i >= len(fn.Parameters) {
			break
		}
		param := fn.Parameters[i]
		if !validMemberIdentifier(param) {
			continue
		}
		typeName := inferExpressionType(arg, env, stack)
		if typeName == "" {
			continue
		}
		paramKey := fnName + "\x00" + param.Value
		if conflicts[paramKey] {
			continue
		}
		if out[fnName] == nil {
			out[fnName] = map[string]string{}
		}
		existing := out[fnName][param.Value]
		if existing == "" || existing == typeName {
			out[fnName][param.Value] = typeName
			continue
		}
		delete(out[fnName], param.Value)
		conflicts[paramKey] = true
	}
}

func calledFunctionName(expr ast.Expression) string {
	ident, ok := expr.(*ast.Identifier)
	if !ok || !validMemberIdentifier(ident) {
		return ""
	}
	return ident.Value
}

func collectTypedMemberStatement(stmt ast.Statement, uri string, env memberTypeEnv, stack *[]map[string]string, index typeFieldIndex) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectTypedMemberExpression(stmt.Value, uri, env, stack, index)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.ReturnStatement:
		collectTypedMemberExpression(stmt.ReturnValue, uri, env, stack, index)
	case *ast.ExpressionStatement:
		collectTypedMemberExpression(stmt.Expression, uri, env, stack, index)
	case *ast.AssignStatement:
		collectTypedMemberExpression(stmt.Value, uri, env, stack, index)
		setInferredVarType(stmt.Name, inferExpressionType(stmt.Value, env, *stack), *stack)
	case *ast.SetStatement:
		collectTypedMemberExpression(stmt.Left, uri, env, stack, index)
		collectTypedMemberExpression(stmt.Value, uri, env, stack, index)
	case *ast.WhileStatement:
		collectTypedMemberExpression(stmt.Condition, uri, env, stack, index)
		collectTypedMemberBlock(stmt.Body, uri, env, stack, index)
	case *ast.ForStatement:
		collectTypedMemberStatement(stmt.Init, uri, env, stack, index)
		collectTypedMemberExpression(stmt.Condition, uri, env, stack, index)
		collectTypedMemberStatement(stmt.Post, uri, env, stack, index)
		collectTypedMemberBlock(stmt.Body, uri, env, stack, index)
	case *ast.BlockStatement:
		collectTypedMemberBlock(stmt, uri, env, stack, index)
	}
}

func collectTypedMemberBlock(block *ast.BlockStatement, uri string, env memberTypeEnv, stack *[]map[string]string, index typeFieldIndex) {
	if block == nil {
		return
	}
	*stack = append(*stack, map[string]string{})
	for _, stmt := range block.Statements {
		collectTypedMemberStatement(stmt, uri, env, stack, index)
	}
	*stack = (*stack)[:len(*stack)-1]
}

func collectTypedMemberExpression(expr ast.Expression, uri string, env memberTypeEnv, stack *[]map[string]string, index typeFieldIndex) {
	switch expr := expr.(type) {
	case *ast.PrefixExpression:
		collectTypedMemberExpression(expr.Right, uri, env, stack, index)
	case *ast.InfixExpression:
		collectTypedMemberExpression(expr.Left, uri, env, stack, index)
		collectTypedMemberExpression(expr.Right, uri, env, stack, index)
	case *ast.SpawnExpression:
		collectTypedMemberExpression(expr.Call, uri, env, stack, index)
	case *ast.IfExpression:
		collectTypedMemberExpression(expr.Condition, uri, env, stack, index)
		collectTypedMemberBlock(expr.Consequence, uri, env, stack, index)
		collectTypedMemberBlock(expr.Alternative, uri, env, stack, index)
		applyIfBranchAssignmentEffects(expr, env, stack)
	case *ast.FunctionLiteral:
		*stack = append(*stack, inferredParamFrame(expr, env))
		collectTypedMemberBlock(expr.Body, uri, env, stack, index)
		*stack = (*stack)[:len(*stack)-1]
	case *ast.CallExpression:
		collectTypedMemberExpression(expr.Function, uri, env, stack, index)
		for _, arg := range expr.Arguments {
			collectTypedMemberExpression(arg, uri, env, stack, index)
		}
	case *ast.MemberExpression:
		collectTypedMemberExpression(expr.Left, uri, env, stack, index)
		addTypedMemberRef(expr, uri, env, *stack, index)
	case *ast.ArrayLiteral:
		for _, elem := range expr.Elements {
			collectTypedMemberExpression(elem, uri, env, stack, index)
		}
	case *ast.IndexExpression:
		collectTypedMemberExpression(expr.Left, uri, env, stack, index)
		collectTypedMemberExpression(expr.Index, uri, env, stack, index)
	case *ast.HashLiteral:
		for key, value := range expr.Pairs {
			collectTypedMemberExpression(key, uri, env, stack, index)
			collectTypedMemberExpression(value, uri, env, stack, index)
		}
	}
}

func addTypedMemberRef(expr *ast.MemberExpression, uri string, env memberTypeEnv, stack []map[string]string, index typeFieldIndex) {
	if expr == nil || !validMemberIdentifier(expr.Property) {
		return
	}
	typeName := inferExpressionType(expr.Left, env, stack)
	if typeName == "" {
		return
	}
	info, ok := env.Types[typeName]
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

func inferExpressionType(expr ast.Expression, env memberTypeEnv, stack []map[string]string) string {
	switch expr := expr.(type) {
	case *ast.Identifier:
		return lookupInferredVarType(expr.Value, stack)
	case *ast.CallExpression:
		typeKey := constructorTypeKey(expr.Function)
		if _, ok := env.Types[typeKey]; ok {
			return typeKey
		}
		if env.Prefix != "" {
			prefixedTypeKey := env.Prefix + typeKey
			if _, ok := env.Types[prefixedTypeKey]; ok {
				return prefixedTypeKey
			}
		}
		if typeName := env.Functions[typeKey]; typeName != "" {
			return typeName
		}
		if env.Prefix != "" {
			if typeName := env.Functions[env.Prefix+typeKey]; typeName != "" {
				return typeName
			}
		}
	case *ast.MemberExpression:
		return inferConstructedFieldType(expr, env, stack)
	case *ast.IfExpression:
		return inferIfExpressionType(expr, env, stack)
	case *ast.ArrayLiteral:
		return inferArrayLiteralType(expr, env, stack)
	case *ast.HashLiteral:
		return inferHashLiteralType(expr, env, stack)
	case *ast.IndexExpression:
		return inferIndexedExpressionType(expr, env, stack)
	}
	return ""
}

const (
	inferredListPrefix = "[]"
	inferredMapPrefix  = "{}"
)

func inferArrayLiteralType(expr *ast.ArrayLiteral, env memberTypeEnv, stack []map[string]string) string {
	if expr == nil || len(expr.Elements) == 0 {
		return ""
	}
	elemType := ""
	for _, elem := range expr.Elements {
		next := inferExpressionType(elem, env, stack)
		if next == "" {
			return ""
		}
		if elemType == "" {
			elemType = next
			continue
		}
		if elemType != next {
			return ""
		}
	}
	return inferredListPrefix + elemType
}

func inferHashLiteralType(expr *ast.HashLiteral, env memberTypeEnv, stack []map[string]string) string {
	if expr == nil || len(expr.Pairs) == 0 {
		return ""
	}
	valueType := ""
	for _, value := range expr.Pairs {
		next := inferExpressionType(value, env, stack)
		if next == "" {
			return ""
		}
		if valueType == "" {
			valueType = next
			continue
		}
		if valueType != next {
			return ""
		}
	}
	return inferredMapPrefix + valueType
}

func inferIndexedExpressionType(expr *ast.IndexExpression, env memberTypeEnv, stack []map[string]string) string {
	if expr == nil {
		return ""
	}
	containerType := inferExpressionType(expr.Left, env, stack)
	if strings.HasPrefix(containerType, inferredListPrefix) {
		return strings.TrimPrefix(containerType, inferredListPrefix)
	}
	if strings.HasPrefix(containerType, inferredMapPrefix) {
		return strings.TrimPrefix(containerType, inferredMapPrefix)
	}
	return ""
}

func inferIfExpressionType(expr *ast.IfExpression, env memberTypeEnv, stack []map[string]string) string {
	if expr == nil || expr.Consequence == nil || expr.Alternative == nil {
		return ""
	}
	consequenceStack := cloneTypeStack(stack)
	consequence := inferBlockReturnType(expr.Consequence, env, &consequenceStack)
	alternativeStack := cloneTypeStack(stack)
	alternative := inferBlockReturnType(expr.Alternative, env, &alternativeStack)
	if consequence != "" && alternative != "" && consequence == alternative {
		return consequence
	}
	return ""
}

func cloneTypeStack(stack []map[string]string) []map[string]string {
	out := make([]map[string]string, len(stack))
	for i, frame := range stack {
		next := make(map[string]string, len(frame))
		for name, typeName := range frame {
			next[name] = typeName
		}
		out[i] = next
	}
	return out
}

func inferConstructedFieldType(expr *ast.MemberExpression, env memberTypeEnv, stack []map[string]string) string {
	if expr == nil || !validMemberIdentifier(expr.Property) {
		return ""
	}
	call, ok := expr.Left.(*ast.CallExpression)
	if !ok {
		return ""
	}
	typeName := inferExpressionType(call, env, stack)
	info, ok := env.Types[typeName]
	if !ok {
		return ""
	}
	fieldIndex := constructorFieldIndex(info, expr.Property.Value)
	if fieldIndex < 0 || fieldIndex >= len(call.Arguments) {
		return ""
	}
	return inferExpressionType(call.Arguments[fieldIndex], env, stack)
}

func constructorFieldIndex(info typeInfo, fieldName string) int {
	if fieldName == "" {
		return -1
	}
	fields := make([]resolvedSymbol, 0, len(info.Fields))
	for _, field := range info.Fields {
		fields = append(fields, field)
	}
	sort.Slice(fields, func(i, j int) bool {
		if fields[i].Symbol.Range.Start.Line == fields[j].Symbol.Range.Start.Line {
			return fields[i].Symbol.Range.Start.Character < fields[j].Symbol.Range.Start.Character
		}
		return fields[i].Symbol.Range.Start.Line < fields[j].Symbol.Range.Start.Line
	})
	for i, field := range fields {
		if field.Symbol.Name == fieldName {
			return i
		}
	}
	return -1
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
	setInferredNameType(ident.Value, typeName, stack)
}

func setInferredNameType(name, typeName string, stack []map[string]string) {
	if name == "" || len(stack) == 0 {
		return
	}
	scope := stack[len(stack)-1]
	if typeName == "" {
		delete(scope, name)
		return
	}
	scope[name] = typeName
}

func inferredParamFrame(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	frame := map[string]string{}
	if fn == nil || fn.Name == "" {
		return frame
	}
	for name, typeName := range env.Params[fn.Name] {
		if typeName != "" {
			frame[name] = typeName
		}
	}
	return frame
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
