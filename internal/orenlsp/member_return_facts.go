package orenlsp

import (
	"strings"

	"oren/pkg/ast"
)

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

func collectFunctionReturnFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionFields == nil {
		env.FunctionFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionFields[key] = fields
		}
	}
	return out
}

func collectFunctionReturnElementFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionElementFields == nil {
		env.FunctionElementFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnElementFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionElementFields[key] = fields
		}
	}
	return out
}

func collectFunctionReturnMapValueFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionMapValueFields == nil {
		env.FunctionMapValueFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnMapValueFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionMapValueFields[key] = fields
		}
	}
	return out
}

func collectFunctionParamTypes(program *ast.Program, env memberTypeEnv, functions map[string]*ast.FunctionLiteral) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	if functions == nil {
		functions = collectNamedFunctionLiterals(program, "")
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

func collectNamedFunctionLiterals(program *ast.Program, prefix string) map[string]*ast.FunctionLiteral {
	functions := map[string]*ast.FunctionLiteral{}
	if program == nil {
		return functions
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn != nil && fn.Name != "" {
			functions[prefix+fn.Name] = fn
		}
	}
	return functions
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

func inferFunctionReturnFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnFieldTypes(fn.Body, env, &stack)
}

func inferFunctionReturnElementFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnElementFieldTypes(fn.Body, env, &stack)
}

func inferFunctionReturnMapValueFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnMapValueFieldTypes(fn.Body, env, &stack)
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

func inferBlockReturnFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferStatementReturnFieldTypes(stmt, env, stack)
		if len(next) == 0 {
			continue
		}
		if inferred == nil {
			inferred = cloneFieldTypes(next)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, next)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferStatementReturnType(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
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
		if frame, ok := inferForInElementFrame(stmt, env, *stack); ok {
			*stack = append(*stack, frame)
			defer func() { *stack = (*stack)[:len(*stack)-1] }()
			return inferForInBodyReturnType(stmt.Body, env, stack)
		}
		return inferBlockReturnType(stmt.Body, env, stack)
	}
	return ""
}

func inferStatementReturnFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferExpressionFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		return inferExpressionReturnFieldTypes(stmt.Expression, env, stack)
	case *ast.BlockStatement:
		return inferBlockReturnFieldTypes(stmt, env, stack)
	case *ast.WhileStatement:
		return inferBlockReturnFieldTypes(stmt.Body, env, stack)
	case *ast.ForStatement:
		if stmt.Init != nil {
			_ = inferStatementReturnFieldTypes(stmt.Init, env, stack)
		}
		if stmt.Post != nil {
			_ = inferStatementReturnFieldTypes(stmt.Post, env, stack)
		}
		if frame, ok := inferForInElementFrame(stmt, env, *stack); ok {
			*stack = append(*stack, frame)
			defer func() { *stack = (*stack)[:len(*stack)-1] }()
			return inferForInBodyReturnFieldTypes(stmt.Body, env, stack)
		}
		return inferBlockReturnFieldTypes(stmt.Body, env, stack)
	}
	return nil
}

func inferStatementReturnElementFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferIterableElementFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		return inferExpressionReturnElementFieldTypes(stmt.Expression, env, stack)
	case *ast.BlockStatement:
		return inferBlockReturnElementFieldTypes(stmt, env, stack)
	case *ast.WhileStatement:
		return inferBlockReturnElementFieldTypes(stmt.Body, env, stack)
	case *ast.ForStatement:
		if stmt.Init != nil {
			_ = inferStatementReturnElementFieldTypes(stmt.Init, env, stack)
		}
		if stmt.Post != nil {
			_ = inferStatementReturnElementFieldTypes(stmt.Post, env, stack)
		}
		if frame, ok := inferForInElementFrame(stmt, env, *stack); ok {
			*stack = append(*stack, frame)
			defer func() { *stack = (*stack)[:len(*stack)-1] }()
			return inferForInBodyReturnElementFieldTypes(stmt.Body, env, stack)
		}
		return inferBlockReturnElementFieldTypes(stmt.Body, env, stack)
	}
	return nil
}

func inferStatementReturnMapValueFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferMapValueFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		return inferExpressionReturnMapValueFieldTypes(stmt.Expression, env, stack)
	case *ast.BlockStatement:
		return inferBlockReturnMapValueFieldTypes(stmt, env, stack)
	case *ast.WhileStatement:
		return inferBlockReturnMapValueFieldTypes(stmt.Body, env, stack)
	case *ast.ForStatement:
		if stmt.Init != nil {
			_ = inferStatementReturnMapValueFieldTypes(stmt.Init, env, stack)
		}
		if stmt.Post != nil {
			_ = inferStatementReturnMapValueFieldTypes(stmt.Post, env, stack)
		}
		if frame, ok := inferForInElementFrame(stmt, env, *stack); ok {
			*stack = append(*stack, frame)
			defer func() { *stack = (*stack)[:len(*stack)-1] }()
			return inferForInBodyReturnMapValueFieldTypes(stmt.Body, env, stack)
		}
		return inferBlockReturnMapValueFieldTypes(stmt.Body, env, stack)
	}
	return nil
}

func inferForInBodyReturnType(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) string {
	if block == nil {
		return ""
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred string
	for _, stmt := range block.Statements {
		next := inferGuardedIfReturnType(stmt, env, *stack)
		if next == "" {
			next = inferStatementReturnType(stmt, env, stack)
		}
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

func inferForInBodyReturnFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferGuardedIfReturnFieldTypes(stmt, env, *stack)
		if len(next) == 0 {
			next = inferStatementReturnFieldTypes(stmt, env, stack)
		}
		if len(next) == 0 {
			continue
		}
		if inferred == nil {
			inferred = cloneFieldTypes(next)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, next)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferForInBodyReturnElementFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferGuardedIfReturnElementFieldTypes(stmt, env, *stack)
		if len(next) == 0 {
			next = inferStatementReturnElementFieldTypes(stmt, env, stack)
		}
		if len(next) == 0 {
			continue
		}
		if inferred == nil {
			inferred = cloneFieldTypes(next)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, next)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferForInBodyReturnMapValueFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferGuardedIfReturnMapValueFieldTypes(stmt, env, *stack)
		if len(next) == 0 {
			next = inferStatementReturnMapValueFieldTypes(stmt, env, stack)
		}
		if len(next) == 0 {
			continue
		}
		if inferred == nil {
			inferred = cloneFieldTypes(next)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, next)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferGuardedIfReturnType(stmt ast.Statement, env memberTypeEnv, stack []map[string]string) string {
	exprStmt, ok := stmt.(*ast.ExpressionStatement)
	if !ok {
		return ""
	}
	ifExpr, ok := exprStmt.Expression.(*ast.IfExpression)
	if !ok || ifExpr.Consequence == nil || ifExpr.Alternative != nil {
		return ""
	}
	consequenceStack := cloneTypeStack(stack)
	return inferBlockReturnType(ifExpr.Consequence, env, &consequenceStack)
}

func inferGuardedIfReturnFieldTypes(stmt ast.Statement, env memberTypeEnv, stack []map[string]string) map[string]string {
	exprStmt, ok := stmt.(*ast.ExpressionStatement)
	if !ok {
		return nil
	}
	ifExpr, ok := exprStmt.Expression.(*ast.IfExpression)
	if !ok || ifExpr.Consequence == nil || ifExpr.Alternative != nil {
		return nil
	}
	consequenceStack := cloneTypeStack(stack)
	return inferBlockReturnFieldTypes(ifExpr.Consequence, env, &consequenceStack)
}

func inferGuardedIfReturnElementFieldTypes(stmt ast.Statement, env memberTypeEnv, stack []map[string]string) map[string]string {
	exprStmt, ok := stmt.(*ast.ExpressionStatement)
	if !ok {
		return nil
	}
	ifExpr, ok := exprStmt.Expression.(*ast.IfExpression)
	if !ok || ifExpr.Consequence == nil || ifExpr.Alternative != nil {
		return nil
	}
	consequenceStack := cloneTypeStack(stack)
	return inferBlockReturnElementFieldTypes(ifExpr.Consequence, env, &consequenceStack)
}

func inferGuardedIfReturnMapValueFieldTypes(stmt ast.Statement, env memberTypeEnv, stack []map[string]string) map[string]string {
	exprStmt, ok := stmt.(*ast.ExpressionStatement)
	if !ok {
		return nil
	}
	ifExpr, ok := exprStmt.Expression.(*ast.IfExpression)
	if !ok || ifExpr.Consequence == nil || ifExpr.Alternative != nil {
		return nil
	}
	consequenceStack := cloneTypeStack(stack)
	return inferBlockReturnMapValueFieldTypes(ifExpr.Consequence, env, &consequenceStack)
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

func inferExpressionReturnFieldTypes(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if fields := inferIfExpressionFieldTypes(expr, env, *stack); len(fields) != 0 {
			return fields
		}
		applyIfBranchAssignmentEffects(expr, env, stack)
	}
	return nil
}

func inferExpressionReturnElementFieldTypes(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if fields := inferIfExpressionElementFieldTypes(expr, env, *stack); len(fields) != 0 {
			return fields
		}
		applyIfBranchAssignmentEffects(expr, env, stack)
	}
	return nil
}

func inferExpressionReturnMapValueFieldTypes(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if fields := inferIfExpressionMapValueFieldTypes(expr, env, *stack); len(fields) != 0 {
			return fields
		}
		applyIfBranchAssignmentEffects(expr, env, stack)
	}
	return nil
}

func applyIfBranchAssignmentEffects(expr *ast.IfExpression, env memberTypeEnv, stack *[]map[string]string) {
	if expr == nil || expr.Consequence == nil || expr.Alternative == nil || stack == nil {
		return
	}
	consequence := collectBranchAssignmentEffects(expr.Consequence, env, *stack)
	alternative := collectBranchAssignmentEffects(expr.Alternative, env, *stack)
	for name, effect := range mergeBranchAssignmentEffects(consequence, alternative) {
		applyBranchAssignmentEffect(name, effect, *stack)
	}
}

type branchAssignmentEffect struct {
	TypeName           string
	FieldTypes         map[string]string
	ElementFieldTypes  map[string]string
	MapValueFieldTypes map[string]string
	ElementMapValues   map[string]string
	MapValueElements   map[string]string
}

func collectBranchAssignmentEffects(block *ast.BlockStatement, env memberTypeEnv, stack []map[string]string) map[string]branchAssignmentEffect {
	effects := map[string]branchAssignmentEffect{}
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

func collectStatementAssignmentEffects(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string, effects map[string]branchAssignmentEffect) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		if !validMemberIdentifier(stmt.Name) {
			return
		}
		effects[stmt.Name.Value] = inferBranchAssignmentEffect(stmt.Value, env, *stack)
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
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

func collectExpressionAssignmentEffects(expr ast.Expression, env memberTypeEnv, stack *[]map[string]string, effects map[string]branchAssignmentEffect) {
	switch expr := expr.(type) {
	case *ast.IfExpression:
		if expr.Consequence == nil || expr.Alternative == nil {
			return
		}
		for name, effect := range mergeBranchAssignmentEffects(
			collectBranchAssignmentEffects(expr.Consequence, env, *stack),
			collectBranchAssignmentEffects(expr.Alternative, env, *stack),
		) {
			effects[name] = effect
			applyBranchAssignmentEffect(name, effect, *stack)
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

func inferBranchAssignmentEffect(expr ast.Expression, env memberTypeEnv, stack []map[string]string) branchAssignmentEffect {
	return branchAssignmentEffect{
		TypeName:           inferExpressionType(expr, env, stack),
		FieldTypes:         cloneFieldTypes(inferExpressionFieldTypes(expr, env, stack)),
		ElementFieldTypes:  cloneFieldTypes(inferIterableElementFieldTypes(expr, env, stack)),
		MapValueFieldTypes: cloneFieldTypes(inferMapValueFieldTypes(expr, env, stack)),
		ElementMapValues:   cloneFieldTypes(inferIterableElementMapValueFieldTypes(expr, env, stack)),
		MapValueElements:   cloneFieldTypes(inferMapValueElementFieldTypes(expr, env, stack)),
	}
}

func applyBranchAssignmentEffect(name string, effect branchAssignmentEffect, stack []map[string]string) {
	if name == "" || len(stack) == 0 {
		return
	}
	setInferredNameType(name, effect.TypeName, stack)
	scope := stack[len(stack)-1]
	if len(effect.FieldTypes) != 0 {
		setInferredFieldTypes(name, effect.FieldTypes, scope)
	}
	if len(effect.ElementFieldTypes) != 0 {
		setInferredElementFieldTypes(name, effect.ElementFieldTypes, scope)
	}
	if len(effect.MapValueFieldTypes) != 0 {
		setInferredMapValueFieldTypes(name, effect.MapValueFieldTypes, scope)
	}
	if len(effect.ElementMapValues) != 0 {
		setInferredElementMapValueFieldTypes(name, effect.ElementMapValues, scope)
	}
	if len(effect.MapValueElements) != 0 {
		setInferredMapValueElementFieldTypes(name, effect.MapValueElements, scope)
	}
}

func mergeBranchAssignmentEffects(consequence, alternative map[string]branchAssignmentEffect) map[string]branchAssignmentEffect {
	merged := map[string]branchAssignmentEffect{}
	for name, consequenceEffect := range consequence {
		alternativeEffect, ok := alternative[name]
		if ok {
			merged[name] = mergeBranchAssignmentEffect(consequenceEffect, alternativeEffect)
			continue
		}
		merged[name] = branchAssignmentEffect{}
	}
	for name := range alternative {
		if _, ok := consequence[name]; !ok {
			merged[name] = branchAssignmentEffect{}
		}
	}
	return merged
}

func mergeBranchAssignmentEffect(consequence, alternative branchAssignmentEffect) branchAssignmentEffect {
	var merged branchAssignmentEffect
	if consequence.TypeName != "" && consequence.TypeName == alternative.TypeName {
		merged.TypeName = consequence.TypeName
	}
	merged.FieldTypes = mergeFieldTypeFacts(consequence.FieldTypes, alternative.FieldTypes)
	merged.ElementFieldTypes = mergeFieldTypeFacts(consequence.ElementFieldTypes, alternative.ElementFieldTypes)
	merged.MapValueFieldTypes = mergeFieldTypeFacts(consequence.MapValueFieldTypes, alternative.MapValueFieldTypes)
	merged.ElementMapValues = mergeFieldTypeFacts(consequence.ElementMapValues, alternative.ElementMapValues)
	merged.MapValueElements = mergeFieldTypeFacts(consequence.MapValueElements, alternative.MapValueElements)
	return merged
}

func collectFunctionParamStatementTypes(stmt ast.Statement, env memberTypeEnv, functions map[string]*ast.FunctionLiteral, stack *[]map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		collectFunctionParamExpressionTypes(stmt.Value, env, functions, stack, out, conflicts)
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		collectFunctionParamExpressionTypes(stmt.ReturnValue, env, functions, stack, out, conflicts)
	case *ast.ExpressionStatement:
		collectFunctionParamExpressionTypes(stmt.Expression, env, functions, stack, out, conflicts)
	case *ast.AssignStatement:
		collectFunctionParamExpressionTypes(stmt.Value, env, functions, stack, out, conflicts)
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
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
		if frame, ok := inferForInElementFrame(stmt, env, *stack); ok {
			*stack = append(*stack, frame)
			collectFunctionParamBlockTypes(stmt.Body, env, functions, stack, out, conflicts)
			*stack = (*stack)[:len(*stack)-1]
			return
		}
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
			mergeCallParamFieldTypes(fnName, param.Value, typeName, inferExpressionFieldTypes(arg, env, stack), env, out, conflicts)
			mergeCallParamElementFieldTypes(fnName, param.Value, typeName, inferIterableElementFieldTypes(arg, env, stack), out, conflicts)
			mergeCallParamMapValueFieldTypes(fnName, param.Value, typeName, inferMapValueFieldTypes(arg, env, stack), out, conflicts)
			mergeCallParamElementMapValueFieldTypes(fnName, param.Value, typeName, inferIterableElementMapValueFieldTypes(arg, env, stack), out, conflicts)
			mergeCallParamMapValueElementFieldTypes(fnName, param.Value, typeName, inferMapValueElementFieldTypes(arg, env, stack), out, conflicts)
			continue
		}
		delete(out[fnName], param.Value)
		deleteCallParamFieldTypes(param.Value, out[fnName])
		deleteCallParamElementFieldTypes(param.Value, out[fnName])
		deleteCallParamMapValueFieldTypes(param.Value, out[fnName])
		deleteCallParamElementMapValueFieldTypes(param.Value, out[fnName])
		deleteCallParamMapValueElementFieldTypes(param.Value, out[fnName])
		conflicts[paramKey] = true
	}
}

func mergeCallParamFieldTypes(fnName, paramName, typeName string, fields map[string]string, env memberTypeEnv, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || typeName == "" {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	if info, ok := env.Types[typeName]; ok {
		for _, field := range orderedTypeFields(info) {
			fieldName := field.Symbol.Name
			if fieldName == "" || fields[fieldName] != "" {
				continue
			}
			paramField := inferredFieldKey(paramName, fieldName)
			if out[fnName][paramField] != "" {
				delete(out[fnName], paramField)
				conflicts[fnName+"\x00"+paramField] = true
			}
		}
	}
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredFieldKey(paramName, field)
		conflictKey := fnName + "\x00" + paramField
		if conflicts[conflictKey] {
			continue
		}
		existing := out[fnName][paramField]
		if existing == "" || existing == typeName {
			out[fnName][paramField] = typeName
			continue
		}
		delete(out[fnName], paramField)
		conflicts[conflictKey] = true
	}
}

func mergeCallParamElementFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredListPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamElementFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredElementFieldKey(paramName, field)
		conflictKey := fnName + "\x00" + paramField
		if conflicts[conflictKey] {
			continue
		}
		existing := out[fnName][paramField]
		if existing == "" || existing == typeName {
			out[fnName][paramField] = typeName
			continue
		}
		delete(out[fnName], paramField)
		conflicts[conflictKey] = true
	}
}

func mergeCallParamMapValueFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredMapPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamMapValueFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredMapValueFieldKey(paramName, field)
		conflictKey := fnName + "\x00" + paramField
		if conflicts[conflictKey] {
			continue
		}
		existing := out[fnName][paramField]
		if existing == "" || existing == typeName {
			out[fnName][paramField] = typeName
			continue
		}
		delete(out[fnName], paramField)
		conflicts[conflictKey] = true
	}
}

func dropMissingCallParamMapValueFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}."
	for key := range params {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		field := strings.TrimPrefix(key, prefix)
		if field == "" || fields[field] != "" {
			continue
		}
		delete(params, key)
		conflicts[fnName+"\x00"+key] = true
	}
}

func dropMissingCallParamElementFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[]."
	for key := range params {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		field := strings.TrimPrefix(key, prefix)
		if field == "" || fields[field] != "" {
			continue
		}
		delete(params, key)
		conflicts[fnName+"\x00"+key] = true
	}
}

func dropMissingCallParamFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "."
	for key := range params {
		if !strings.HasPrefix(key, prefix) {
			continue
		}
		field := strings.TrimPrefix(key, prefix)
		if field == "" || fields[field] != "" {
			continue
		}
		delete(params, key)
		conflicts[fnName+"\x00"+key] = true
	}
}

func deleteCallParamFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func deleteCallParamElementFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[]."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func deleteCallParamMapValueFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func calledFunctionName(expr ast.Expression) string {
	return constructorTypeKey(expr)
}
