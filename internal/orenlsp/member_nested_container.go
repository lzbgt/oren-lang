package orenlsp

import (
	"strings"

	"oren/pkg/ast"
)

func inferIterableElementMapValueFieldTypes(expr ast.Expression, env memberTypeEnv, stack []map[string]string) map[string]string {
	switch expr := expr.(type) {
	case *ast.ArrayLiteral:
		return inferArrayElementMapValueFieldTypes(expr, env, stack)
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
