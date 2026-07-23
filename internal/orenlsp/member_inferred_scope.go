package orenlsp

import (
	"strings"

	"oren/pkg/ast"
	"oren/pkg/token"
)

func setInferredFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredFieldKey(name, field)] = typeName
		}
	}
}

func setInferredElementFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredElementFieldKey(name, field)] = typeName
		}
	}
}

func setInferredMapValueFieldTypes(name string, fields map[string]string, scope map[string]string) {
	if name == "" || len(fields) == 0 || len(scope) == 0 {
		return
	}
	for field, typeName := range fields {
		if field != "" && typeName != "" {
			scope[inferredMapValueFieldKey(name, field)] = typeName
		}
	}
}

func setInferredConstructorFieldContainerTypes(name string, expr ast.Expression, env memberTypeEnv, stack []map[string]string, scope map[string]string) {
	call, ok := expr.(*ast.CallExpression)
	if !ok || name == "" || len(scope) == 0 {
		return
	}
	typeKey := constructorTypeKey(call.Function)
	if typeKey == "" {
		return
	}
	info, ok := env.Types[typeKey]
	if !ok && env.Prefix != "" {
		info, ok = env.Types[env.Prefix+typeKey]
	}
	if !ok {
		return
	}
	fields := orderedTypeFields(info)
	for i, field := range fields {
		if i >= len(call.Arguments) {
			break
		}
		fieldName := field.Symbol.Name
		if fieldName == "" {
			continue
		}
		fieldPath := inferredFieldKey(name, fieldName)
		arg := call.Arguments[i]
		if facts := inferIterableElementFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredElementFieldTypes(fieldPath, facts, scope)
		}
		if facts := inferMapValueFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredMapValueFieldTypes(fieldPath, facts, scope)
		}
		if facts := inferIterableElementElementFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredElementElementFieldTypes(fieldPath, facts, scope)
		}
		if facts := inferMapValueMapValueFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredMapValueMapValueFieldTypes(fieldPath, facts, scope)
		}
		if facts := inferIterableElementMapValueFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredElementMapValueFieldTypes(fieldPath, facts, scope)
		}
		if facts := inferMapValueElementFieldTypes(arg, env, stack); len(facts) != 0 {
			setInferredMapValueElementFieldTypes(fieldPath, facts, scope)
		}
	}
}

func copyInferredFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "."
	dstPrefix := dst + "."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func copyInferredElementFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "[]."
	dstPrefix := dst + "[]."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func copyInferredMapValueFieldTypes(dst, src string, stack []map[string]string) {
	if dst == "" || src == "" || len(stack) == 0 {
		return
	}
	srcPrefix := src + "{}."
	dstPrefix := dst + "{}."
	scope := stack[len(stack)-1]
	for _, frame := range stack {
		for key, typeName := range frame {
			if strings.HasPrefix(key, srcPrefix) && typeName != "" {
				scope[dstPrefix+strings.TrimPrefix(key, srcPrefix)] = typeName
			}
		}
	}
}

func inferredFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "."
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

func inferredElementFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "[]."
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

func inferredMapValueFieldTypes(name string, stack []map[string]string) map[string]string {
	if name == "" || len(stack) == 0 {
		return nil
	}
	prefix := name + "{}."
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

func setInferredNameType(name, typeName string, stack []map[string]string) {
	if name == "" || len(stack) == 0 {
		return
	}
	scope := stack[len(stack)-1]
	clearInferredFieldTypes(name, scope)
	clearInferredElementFieldTypes(name, scope)
	clearInferredMapValueFieldTypes(name, scope)
	clearInferredElementElementFieldTypes(name, scope)
	clearInferredMapValueMapValueFieldTypes(name, scope)
	clearInferredElementMapValueFieldTypes(name, scope)
	clearInferredMapValueElementFieldTypes(name, scope)
	if typeName == "" {
		delete(scope, name)
		return
	}
	scope[name] = typeName
}

func clearInferredFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func clearInferredElementFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "[]."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func clearInferredMapValueFieldTypes(name string, scope map[string]string) {
	if name == "" || len(scope) == 0 {
		return
	}
	prefix := name + "{}."
	for key := range scope {
		if strings.HasPrefix(key, prefix) {
			delete(scope, key)
		}
	}
}

func inferredFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "." + field
}

func inferredElementFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "[]." + field
}

func inferredMapValueFieldKey(name, field string) string {
	if name == "" || field == "" {
		return ""
	}
	return name + "{}." + field
}

func memberExpressionPath(expr ast.Expression) string {
	switch expr := expr.(type) {
	case *ast.Identifier:
		if validMemberIdentifier(expr) {
			return expr.Value
		}
	case *ast.MemberExpression:
		if !validMemberIdentifier(expr.Property) {
			return ""
		}
		left := memberExpressionPath(expr.Left)
		if left == "" {
			return ""
		}
		return inferredFieldKey(left, expr.Property.Value)
	}
	return ""
}

func mergeNestedFieldTypes(out map[string]string, fieldName string, fields map[string]string) {
	if len(out) == 0 || fieldName == "" || len(fields) == 0 {
		return
	}
	for nested, typeName := range fields {
		if nested != "" && typeName != "" {
			out[inferredFieldKey(fieldName, nested)] = typeName
		}
	}
}

func inferredParamFrame(fn *ast.FunctionLiteral, env memberTypeEnv) map[string]string {
	frame := map[string]string{}
	if fn == nil || fn.Name == "" {
		return frame
	}
	params := env.Params[fn.Name]
	if len(params) == 0 && env.Prefix != "" {
		params = env.Params[env.Prefix+fn.Name]
	}
	for name, typeName := range params {
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
