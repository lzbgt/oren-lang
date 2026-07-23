package orenlsp

import (
	"strings"

	"oren/pkg/ast"
)

func collectFunctionReturnElementElementFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionElementElementFields == nil {
		env.FunctionElementElementFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnElementElementFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionElementElementFields[key] = fields
		}
	}
	return out
}

func collectFunctionReturnMapValueMapValueFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionMapValueMapFields == nil {
		env.FunctionMapValueMapFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnMapValueMapValueFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionMapValueMapFields[key] = fields
		}
	}
	return out
}

func collectFunctionReturnElementMapValueFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionElementMapValueFields == nil {
		env.FunctionElementMapValueFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnElementMapValueFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionElementMapValueFields[key] = fields
		}
	}
	return out
}

func collectFunctionReturnMapValueElementFieldTypes(program *ast.Program, prefix string, env memberTypeEnv) map[string]map[string]string {
	out := map[string]map[string]string{}
	if program == nil {
		return out
	}
	env.Prefix = prefix
	if env.FunctionMapValueElementFields == nil {
		env.FunctionMapValueElementFields = map[string]map[string]string{}
	}
	for _, stmt := range program.Statements {
		fn := namedFunctionLiteral(stmt)
		if fn == nil || fn.Name == "" {
			continue
		}
		fields := inferFunctionReturnMapValueElementFieldTypes(fn, env)
		if len(fields) != 0 {
			key := prefix + fn.Name
			out[key] = fields
			env.FunctionMapValueElementFields[key] = fields
		}
	}
	return out
}

func inferFunctionReturnElementMapValueFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnElementMapValueFieldTypes(fn.Body, env, &stack)
}

func inferFunctionReturnMapValueElementFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnMapValueElementFieldTypes(fn.Body, env, &stack)
}

func inferFunctionReturnElementElementFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnElementElementFieldTypes(fn.Body, env, &stack)
}

func inferFunctionReturnMapValueMapValueFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnMapValueMapValueFieldTypes(fn.Body, env, &stack)
}

func inferIterableElementElementFieldTypes(expr ast.Expression, env memberTypeEnv, stack []map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.ArrayLiteral:
		return inferArrayElementElementFieldTypes(expr, env, stack)
	case *ast.CallExpression:
		return functionElementElementFieldTypesForCall(expr, env)
	case *ast.Identifier, *ast.MemberExpression:
		if path := memberExpressionPath(expr); path != "" {
			return inferredElementElementFieldTypes(path, stack)
		}
	case *ast.IfExpression:
		if expr == nil || expr.Consequence == nil || expr.Alternative == nil {
			return nil
		}
		consequenceStack := cloneTypeStack(stack)
		consequence := inferBlockReturnElementElementFieldTypes(expr.Consequence, env, &consequenceStack)
		alternativeStack := cloneTypeStack(stack)
		alternative := inferBlockReturnElementElementFieldTypes(expr.Alternative, env, &alternativeStack)
		return mergeFieldTypeFacts(consequence, alternative)
	}
	return nil
}

func inferArrayElementElementFieldTypes(expr *ast.ArrayLiteral, env memberTypeEnv, stack []map[string]string) map[string]string {
	if expr == nil || len(expr.Elements) == 0 {
		return nil
	}
	var inferred map[string]string
	for _, elem := range expr.Elements {
		fields := inferIterableElementFieldTypes(elem, env, stack)
		if len(fields) == 0 {
			return nil
		}
		if inferred == nil {
			inferred = cloneFieldTypes(fields)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, fields)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferBlockReturnElementElementFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferStatementReturnElementElementFieldTypes(stmt, env, stack)
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

func inferStatementReturnElementElementFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferIterableElementElementFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		if expr, ok := stmt.Expression.(*ast.IfExpression); ok {
			applyIfBranchAssignmentEffects(expr, env, stack)
		}
	}
	return nil
}

func inferMapValueMapValueFieldTypes(expr ast.Expression, env memberTypeEnv, stack []map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.HashLiteral:
		return inferHashValueMapValueFieldTypes(expr, env, stack)
	case *ast.CallExpression:
		return functionMapValueMapValueFieldTypesForCall(expr, env)
	case *ast.Identifier, *ast.MemberExpression:
		if path := memberExpressionPath(expr); path != "" {
			return inferredMapValueMapValueFieldTypes(path, stack)
		}
	case *ast.IfExpression:
		if expr == nil || expr.Consequence == nil || expr.Alternative == nil {
			return nil
		}
		consequenceStack := cloneTypeStack(stack)
		consequence := inferBlockReturnMapValueMapValueFieldTypes(expr.Consequence, env, &consequenceStack)
		alternativeStack := cloneTypeStack(stack)
		alternative := inferBlockReturnMapValueMapValueFieldTypes(expr.Alternative, env, &alternativeStack)
		return mergeFieldTypeFacts(consequence, alternative)
	}
	return nil
}

func inferHashValueMapValueFieldTypes(expr *ast.HashLiteral, env memberTypeEnv, stack []map[string]string) map[string]string {
	if expr == nil || len(expr.Pairs) == 0 {
		return nil
	}
	var inferred map[string]string
	for _, value := range expr.Pairs {
		fields := inferMapValueFieldTypes(value, env, stack)
		if len(fields) == 0 {
			return nil
		}
		if inferred == nil {
			inferred = cloneFieldTypes(fields)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, fields)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferBlockReturnMapValueMapValueFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferStatementReturnMapValueMapValueFieldTypes(stmt, env, stack)
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

func inferStatementReturnMapValueMapValueFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferMapValueMapValueFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		if expr, ok := stmt.Expression.(*ast.IfExpression); ok {
			applyIfBranchAssignmentEffects(expr, env, stack)
		}
	}
	return nil
}

func inferIterableElementMapValueFieldTypes(expr ast.Expression, env memberTypeEnv, stack []map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.ArrayLiteral:
		return inferArrayElementMapValueFieldTypes(expr, env, stack)
	case *ast.CallExpression:
		return functionElementMapValueFieldTypesForCall(expr, env)
	case *ast.Identifier, *ast.MemberExpression:
		if path := memberExpressionPath(expr); path != "" {
			return inferredElementMapValueFieldTypes(path, stack)
		}
	case *ast.IfExpression:
		if expr == nil || expr.Consequence == nil || expr.Alternative == nil {
			return nil
		}
		consequenceStack := cloneTypeStack(stack)
		consequence := inferBlockReturnElementMapValueFieldTypes(expr.Consequence, env, &consequenceStack)
		alternativeStack := cloneTypeStack(stack)
		alternative := inferBlockReturnElementMapValueFieldTypes(expr.Alternative, env, &alternativeStack)
		return mergeFieldTypeFacts(consequence, alternative)
	}
	return nil
}

func inferArrayElementMapValueFieldTypes(expr *ast.ArrayLiteral, env memberTypeEnv, stack []map[string]string) map[string]string {
	if expr == nil || len(expr.Elements) == 0 {
		return nil
	}
	var inferred map[string]string
	for _, elem := range expr.Elements {
		fields := inferMapValueFieldTypes(elem, env, stack)
		if len(fields) == 0 {
			return nil
		}
		if inferred == nil {
			inferred = cloneFieldTypes(fields)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, fields)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferBlockReturnElementMapValueFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferStatementReturnElementMapValueFieldTypes(stmt, env, stack)
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

func inferStatementReturnElementMapValueFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferIterableElementMapValueFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		if expr, ok := stmt.Expression.(*ast.IfExpression); ok {
			applyIfBranchAssignmentEffects(expr, env, stack)
		}
	}
	return nil
}

func inferMapValueElementFieldTypes(expr ast.Expression, env memberTypeEnv, stack []map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.HashLiteral:
		return inferHashValueElementFieldTypes(expr, env, stack)
	case *ast.CallExpression:
		return functionMapValueElementFieldTypesForCall(expr, env)
	case *ast.Identifier, *ast.MemberExpression:
		if path := memberExpressionPath(expr); path != "" {
			return inferredMapValueElementFieldTypes(path, stack)
		}
	case *ast.IfExpression:
		if expr == nil || expr.Consequence == nil || expr.Alternative == nil {
			return nil
		}
		consequenceStack := cloneTypeStack(stack)
		consequence := inferBlockReturnMapValueElementFieldTypes(expr.Consequence, env, &consequenceStack)
		alternativeStack := cloneTypeStack(stack)
		alternative := inferBlockReturnMapValueElementFieldTypes(expr.Alternative, env, &alternativeStack)
		return mergeFieldTypeFacts(consequence, alternative)
	}
	return nil
}

func inferHashValueElementFieldTypes(expr *ast.HashLiteral, env memberTypeEnv, stack []map[string]string) map[string]string {
	if expr == nil || len(expr.Pairs) == 0 {
		return nil
	}
	var inferred map[string]string
	for _, value := range expr.Pairs {
		fields := inferIterableElementFieldTypes(value, env, stack)
		if len(fields) == 0 {
			return nil
		}
		if inferred == nil {
			inferred = cloneFieldTypes(fields)
			continue
		}
		inferred = mergeFieldTypeFacts(inferred, fields)
		if len(inferred) == 0 {
			return nil
		}
	}
	return inferred
}

func inferBlockReturnMapValueElementFieldTypes(block *ast.BlockStatement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	if block == nil {
		return nil
	}
	*stack = append(*stack, map[string]string{})
	defer func() { *stack = (*stack)[:len(*stack)-1] }()

	var inferred map[string]string
	for _, stmt := range block.Statements {
		next := inferStatementReturnMapValueElementFieldTypes(stmt, env, stack)
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

func inferStatementReturnMapValueElementFieldTypes(stmt ast.Statement, env memberTypeEnv, stack *[]map[string]string) map[string]string {
	switch stmt := stmt.(type) {
	case *ast.VarStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.ReturnStatement:
		return inferMapValueElementFieldTypes(stmt.ReturnValue, env, *stack)
	case *ast.ExpressionStatement:
		if expr, ok := stmt.Expression.(*ast.IfExpression); ok {
			applyIfBranchAssignmentEffects(expr, env, stack)
		}
	}
	return nil
}

func setInferredElementMapValueFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredElementMapValueFieldKey(name, field)] = typeName
		}
	}
}

func setInferredMapValueElementFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredMapValueElementFieldKey(name, field)] = typeName
		}
	}
}

func setInferredElementElementFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredElementElementFieldKey(name, field)] = typeName
		}
	}
}

func setInferredMapValueMapValueFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredMapValueMapValueFieldKey(name, field)] = typeName
		}
	}
}

func functionElementElementFieldTypesForCall(call *ast.CallExpression, env memberTypeEnv) map[string]string {
	if call == nil || len(env.FunctionElementElementFields) == 0 {
		return nil
	}
	typeKey := constructorTypeKey(call.Function)
	if typeKey == "" {
		return nil
	}
	if fields := env.FunctionElementElementFields[typeKey]; len(fields) != 0 {
		return fields
	}
	if env.Prefix != "" {
		return env.FunctionElementElementFields[env.Prefix+typeKey]
	}
	return nil
}

func functionMapValueMapValueFieldTypesForCall(call *ast.CallExpression, env memberTypeEnv) map[string]string {
	if call == nil || len(env.FunctionMapValueMapFields) == 0 {
		return nil
	}
	typeKey := constructorTypeKey(call.Function)
	if typeKey == "" {
		return nil
	}
	if fields := env.FunctionMapValueMapFields[typeKey]; len(fields) != 0 {
		return fields
	}
	if env.Prefix != "" {
		return env.FunctionMapValueMapFields[env.Prefix+typeKey]
	}
	return nil
}

func functionElementMapValueFieldTypesForCall(call *ast.CallExpression, env memberTypeEnv) map[string]string {
	if call == nil || len(env.FunctionElementMapValueFields) == 0 {
		return nil
	}
	typeKey := constructorTypeKey(call.Function)
	if typeKey == "" {
		return nil
	}
	if fields := env.FunctionElementMapValueFields[typeKey]; len(fields) != 0 {
		return fields
	}
	if env.Prefix != "" {
		return env.FunctionElementMapValueFields[env.Prefix+typeKey]
	}
	return nil
}

func functionMapValueElementFieldTypesForCall(call *ast.CallExpression, env memberTypeEnv) map[string]string {
	if call == nil || len(env.FunctionMapValueElementFields) == 0 {
		return nil
	}
	typeKey := constructorTypeKey(call.Function)
	if typeKey == "" {
		return nil
	}
	if fields := env.FunctionMapValueElementFields[typeKey]; len(fields) != 0 {
		return fields
	}
	if env.Prefix != "" {
		return env.FunctionMapValueElementFields[env.Prefix+typeKey]
	}
	return nil
}

func copyInferredElementElementFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "[][]."
	dstPrefix := dst + "[][]."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func copyInferredMapValueMapValueFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "{}{}."
	dstPrefix := dst + "{}{}."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func copyInferredElementMapValueFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "[]{}."
	dstPrefix := dst + "[]{}."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func copyInferredMapValueElementFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "{}[]."
	dstPrefix := dst + "{}[]."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func inferredElementElementFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "[][]."
	out := map[string]string{}
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, prefix) && typeName != "" {
				out[strings.TrimPrefix(key, prefix)] = typeName
			}
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func inferredMapValueMapValueFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "{}{}."
	out := map[string]string{}
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, prefix) && typeName != "" {
				out[strings.TrimPrefix(key, prefix)] = typeName
			}
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func inferredElementMapValueFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "[]{}."
	out := map[string]string{}
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, prefix) && typeName != "" {
				out[strings.TrimPrefix(key, prefix)] = typeName
			}
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func inferredMapValueElementFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "{}[]."
	out := map[string]string{}
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, prefix) && typeName != "" {
				out[strings.TrimPrefix(key, prefix)] = typeName
			}
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func clearInferredElementElementFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "[][]."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func clearInferredMapValueMapValueFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "{}{}."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func clearInferredElementMapValueFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "[]{}."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func clearInferredMapValueElementFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "{}[]."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func inferredElementMapValueFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "[]{}." + field
}

func inferredMapValueElementFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "{}[]." + field
}

func inferredElementElementFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "[][]." + field
}

func inferredMapValueMapValueFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "{}{}." + field
}

func mergeCallParamElementElementFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredListPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamElementElementFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredElementElementFieldKey(paramName, field)
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

func mergeCallParamMapValueMapValueFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredMapPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamMapValueMapValueFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredMapValueMapValueFieldKey(paramName, field)
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

func mergeCallParamElementMapValueFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredListPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamElementMapValueFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredElementMapValueFieldKey(paramName, field)
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

func mergeCallParamMapValueElementFieldTypes(fnName, paramName, typeName string, fields map[string]string, out map[string]map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || !strings.HasPrefix(typeName, inferredMapPrefix) {
		return
	}
	if out[fnName] == nil {
		out[fnName] = map[string]string{}
	}
	dropMissingCallParamMapValueElementFieldTypes(fnName, paramName, fields, out[fnName], conflicts)
	for field, typeName := range fields {
		if field == "" || typeName == "" {
			continue
		}
		paramField := inferredMapValueElementFieldKey(paramName, field)
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

func dropMissingCallParamElementElementFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[][]."
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

func dropMissingCallParamMapValueMapValueFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}{}."
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

func dropMissingCallParamElementMapValueFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[]{}."
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

func dropMissingCallParamMapValueElementFieldTypes(fnName, paramName string, fields map[string]string, params map[string]string, conflicts map[string]bool) {
	if fnName == "" || paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}[]."
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

func deleteCallParamElementElementFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[][]."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func deleteCallParamMapValueMapValueFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}{}."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func deleteCallParamElementMapValueFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "[]{}."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}

func deleteCallParamMapValueElementFieldTypes(paramName string, params map[string]string) {
	if paramName == "" || len(params) == 0 {
		return
	}
	prefix := paramName + "{}[]."
	for key := range params {
		if strings.HasPrefix(key, prefix) {
			delete(params, key)
		}
	}
}
