package orenlsp

import "oren/pkg/ast"

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

func inferFunctionReturnFieldTypes(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	var stack []map[string]string
	stack = append(stack, inferredParamFrame(fn, env))
	return inferBlockReturnFieldTypes(fn.Body, env, &stack)
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
		return inferBlockReturnFieldTypes(stmt.Body, env, stack)
	}
	return nil
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
		setInferredVarExpression(stmt.Name, stmt.Value, env, *stack)
	case *ast.AssignStatement:
		if !validMemberIdentifier(stmt.Name) {
			return
		}
		typeName := inferExpressionType(stmt.Value, env, *stack)
		effects[stmt.Name.Value] = typeName
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
		if name, typeName, ok := inferForInElementBinding(stmt, env, *stack); ok {
			*stack = append(*stack, map[string]string{name: typeName})
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
