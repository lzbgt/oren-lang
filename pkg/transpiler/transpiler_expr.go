package transpiler

import (
	"fmt"
	"oren/pkg/ast"
	"sort"
	"strings"
)

func (t *Transpiler) emitShortCircuitBool(op string, leftExpr, rightExpr ast.Expression) (string, error) {
	// Oren `&&` / `||` return a boolean value and must short-circuit.
	//
	// We still want deterministic evaluation order and explicit rooting:
	// - Evaluate LHS first (rooted).
	// - Evaluate RHS only inside the taken branch, under a temporary root-mark scope.
	leftVal, err := t.evalExprValue(leftExpr)
	if err != nil {
		return "", err
	}

	res := t.newCTmp("sc_")
	// Initialize to a sensible default (will be overwritten in all branches).
	if op == "&&" {
		t.emit(fmt.Sprintf("OrenValue %s = OREN_FALSE;", res))
	} else {
		t.emit(fmt.Sprintf("OrenValue %s = OREN_TRUE;", res))
	}
	t.emit(fmt.Sprintf("oren_roots_push(&%s);", res))

	switch op {
	case "&&":
		t.emit(fmt.Sprintf("if (oren_is_truthy(%s)) {", leftVal))
		t.indent()
		mark := t.newCTmp("sc_mark_")
		t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", mark))
		rightVal, err := t.evalExprValue(rightExpr)
		if err != nil {
			return "", err
		}
		t.emit(fmt.Sprintf("%s = oren_bool(oren_is_truthy(%s));", res, rightVal))
		t.emit(fmt.Sprintf("oren_roots_reset(%s);", mark))
		t.unindent()
		t.emit("} else {")
		t.indent()
		t.emit(fmt.Sprintf("%s = OREN_FALSE;", res))
		t.unindent()
		t.emit("}")
	case "||":
		t.emit(fmt.Sprintf("if (oren_is_truthy(%s)) {", leftVal))
		t.indent()
		t.emit(fmt.Sprintf("%s = OREN_TRUE;", res))
		t.unindent()
		t.emit("} else {")
		t.indent()
		mark := t.newCTmp("sc_mark_")
		t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", mark))
		rightVal, err := t.evalExprValue(rightExpr)
		if err != nil {
			return "", err
		}
		t.emit(fmt.Sprintf("%s = oren_bool(oren_is_truthy(%s));", res, rightVal))
		t.emit(fmt.Sprintf("oren_roots_reset(%s);", mark))
		t.unindent()
		t.emit("}")
	default:
		return "", fmt.Errorf("internal error: short-circuit op %q", op)
	}

	return res, nil
}

func (t *Transpiler) evalExprValue(exp ast.Expression) (string, error) {
	if exp == nil {
		return "OREN_NIL", nil
	}

	switch e := exp.(type) {
	case *ast.IntegerLiteral:
		return fmt.Sprintf("oren_int(%d)", e.Value), nil
	case *ast.FloatLiteral:
		return fmt.Sprintf("oren_float(%f)", e.Value), nil
	case *ast.StringLiteral:
		// String literals are immutable and can be represented as static C strings.
		// This avoids per-literal heap allocations (massive win for AST-heavy programs
		// like the self-hosted compiler) and reduces allocator/GC pressure under parallel builds.
		return fmt.Sprintf("oren_string_const(\"%s\")", cEscapeString(e.Value)), nil
	case *ast.Boolean:
		if e.Value {
			return "OREN_TRUE", nil
		}
		return "OREN_FALSE", nil
	case *ast.NilLiteral:
		return "OREN_NIL", nil
	case *ast.Identifier:
		if _, ok := t.definedFunctions[e.Value]; ok {
			// First-class function value.
			return fmt.Sprintf("oren_func(%s, NULL)", t.functionWrapperName(e.Value)), nil
		}
		return e.Value, nil
	case *ast.FunctionLiteral:
		if e.Name != "" {
			return "", fmt.Errorf("named function literal is not a first-class expression")
		}
		name, ok := t.lambdaByPtr[e]
		if !ok || name == "" {
			return "", fmt.Errorf("internal error: lambda was not collected before transpile")
		}
		captures := collectFreeVars(e, t.definedFunctions)
		if len(captures) == 0 {
			return t.materializeAndRoot(fmt.Sprintf("oren_closure(%s, 0)", name)), nil
		}
		args := make([]string, 0, len(captures))
		for _, capName := range captures {
			capExpr, err := t.evalExprValue(&ast.Identifier{Value: capName})
			if err != nil {
				return "", err
			}
			args = append(args, capExpr)
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_closure_from_array(%s, %d, (OrenValue[]){%s})", name, len(args), strings.Join(args, ", "))), nil
	case *ast.ArrayLiteral:
		if len(e.Elements) == 0 {
			return t.materializeAndRoot("oren_new_list_from_array(0, NULL)"), nil
		}
		els := make([]string, 0, len(e.Elements))
		for _, el := range e.Elements {
			v, err := t.evalExprValue(el)
			if err != nil {
				return "", err
			}
			els = append(els, v)
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_new_list_from_array(%d, (OrenValue[]){%s})", len(els), strings.Join(els, ", "))), nil
	case *ast.HashLiteral:
		// NOTE (rolling determinism):
		// The AST currently stores pairs as a Go map, which does not preserve source order.
		// To keep builds deterministic, emit pairs in a stable order based on key pretty-print.
		if len(e.Pairs) == 0 {
			return t.materializeAndRoot("oren_new_map(0)"), nil
		}
		type kv struct {
			k       ast.Expression
			v       ast.Expression
			sortKey string
		}
		stableKey := func(k ast.Expression) string {
			switch kk := k.(type) {
			case *ast.StringLiteral:
				return "S:" + kk.Value
			case *ast.IntegerLiteral:
				return fmt.Sprintf("I:%d", kk.Value)
			case *ast.Boolean:
				if kk.Value {
					return "B:1"
				}
				return "B:0"
			case *ast.NilLiteral:
				return "N:"
			case *ast.Identifier:
				return "ID:" + kk.Value
			default:
				// Fallback: type name only. This still produces deterministic output for
				// the common case (literal/identifier keys) and keeps behavior stable.
				return "T:" + fmt.Sprintf("%T", k)
			}
		}
		kvs := make([]kv, 0, len(e.Pairs))
		for k, v := range e.Pairs {
			kvs = append(kvs, kv{k: k, v: v, sortKey: stableKey(k)})
		}
		sort.Slice(kvs, func(i, j int) bool { return kvs[i].sortKey < kvs[j].sortKey })
		args := []string{}
		for _, p := range kvs {
			kk, err := t.evalExprValue(p.k)
			if err != nil {
				return "", err
			}
			vv, err := t.evalExprValue(p.v)
			if err != nil {
				return "", err
			}
			args = append(args, kk, vv)
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_new_map_from_pairs(%d, (OrenValue[]){%s})", len(args)/2, strings.Join(args, ", "))), nil
	case *ast.InfixExpression:
		// IMPORTANT (correctness): `&&` / `||` must short-circuit.
		//
		// Our expression emitter generally materializes subexpressions into temporaries
		// to keep evaluation order deterministic and to make GC rooting explicit.
		// For `&&` and `||`, eagerly evaluating both sides breaks semantics (the right
		// side may rely on the left side being true/false before it is safe to run).
		if e.Operator == "&&" || e.Operator == "||" {
			return t.emitShortCircuitBool(e.Operator, e.Left, e.Right)
		}

		left, err := t.evalExprValue(e.Left)
		if err != nil {
			return "", err
		}
		right, err := t.evalExprValue(e.Right)
		if err != nil {
			return "", err
		}
		var call string
		switch e.Operator {
		case "+":
			call = fmt.Sprintf("oren_add(%s, %s)", left, right)
		case "-":
			call = fmt.Sprintf("oren_sub(%s, %s)", left, right)
		case "*":
			call = fmt.Sprintf("oren_mul(%s, %s)", left, right)
		case "/":
			call = fmt.Sprintf("oren_div(%s, %s)", left, right)
		case "&":
			call = fmt.Sprintf("oren_band(%s, %s)", left, right)
		case "|":
			call = fmt.Sprintf("oren_bor(%s, %s)", left, right)
		case "^":
			call = fmt.Sprintf("oren_bxor(%s, %s)", left, right)
		case "<<":
			call = fmt.Sprintf("oren_shl(%s, %s)", left, right)
		case ">>":
			call = fmt.Sprintf("oren_shr(%s, %s)", left, right)
		case "==":
			call = fmt.Sprintf("oren_eq(%s, %s)", left, right)
		case "!=":
			call = fmt.Sprintf("oren_neq(%s, %s)", left, right)
		case "<":
			call = fmt.Sprintf("oren_lt(%s, %s)", left, right)
		case ">":
			call = fmt.Sprintf("oren_gt(%s, %s)", left, right)
		case "<=":
			call = fmt.Sprintf("oren_lte(%s, %s)", left, right)
		case ">=":
			call = fmt.Sprintf("oren_gte(%s, %s)", left, right)
		default:
			return "", fmt.Errorf("unknown infix operator: %q", e.Operator)
		}
		return t.materializeAndRoot(call), nil
	case *ast.PrefixExpression:
		right, err := t.evalExprValue(e.Right)
		if err != nil {
			return "", err
		}
		switch e.Operator {
		case "!":
			return t.materializeAndRoot(fmt.Sprintf("oren_bool(!oren_is_truthy(%s))", right)), nil
		case "-":
			return t.materializeAndRoot(fmt.Sprintf("oren_sub(oren_int(0), %s)", right)), nil
		case "~":
			return t.materializeAndRoot(fmt.Sprintf("oren_bnot(%s)", right)), nil
		default:
			return "", fmt.Errorf("unknown prefix operator: %q", e.Operator)
		}
	case *ast.MemberExpression:
		if name, _, err := t.resolveNamespaceExpr(e); err != nil {
			return "", err
		} else if name != "" {
			return name, nil
		}
		left, err := t.evalExprValue(e.Left)
		if err != nil {
			return "", err
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_get_attr(%s, \"%s\")", left, e.Property.Value)), nil
	case *ast.IndexExpression:
		left, err := t.evalExprValue(e.Left)
		if err != nil {
			return "", err
		}
		index, err := t.evalExprValue(e.Index)
		if err != nil {
			return "", err
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_list_get(%s, %s)", left, index)), nil
	case *ast.SpawnExpression:
		call, ok := e.Call.(*ast.CallExpression)
		if !ok || call == nil {
			return "", fmt.Errorf("spawn expects a call expression")
		}
		fnVal, err := t.evalExprValue(call.Function)
		if err != nil {
			return "", err
		}
		args := []string{}
		for _, a := range call.Arguments {
			v, err := t.evalExprValue(a)
			if err != nil {
				return "", err
			}
			args = append(args, v)
		}
		argsList := "oren_new_list_from_array(0, NULL)"
		if len(args) > 0 {
			argsList = fmt.Sprintf("oren_new_list_from_array(%d, (OrenValue[]){%s})", len(args), strings.Join(args, ", "))
		}
		argsVar := t.materializeAndRoot(argsList)
		return t.materializeAndRoot(fmt.Sprintf("oren_spawn_call_list(%s, %s)", fnVal, argsVar)), nil
	case *ast.CallExpression:
		// Builtins first.
		if id, ok := e.Function.(*ast.Identifier); ok {
			switch id.Value {
			case "print":
				args := []string{}
				for _, a := range e.Arguments {
					v, err := t.evalExprValue(a)
					if err != nil {
						return "", err
					}
					args = append(args, v)
				}
				if len(args) == 0 {
					t.emit("oren_print(OREN_NIL);")
					return "OREN_NIL", nil
				}
				if len(args) == 1 {
					t.emit(fmt.Sprintf("oren_print(%s);", args[0]))
					return "OREN_NIL", nil
				}
				// Avoid varargs with OrenValue structs (UB): use list-based printing.
				listExpr := fmt.Sprintf("oren_new_list_from_array(%d, (OrenValue[]){%s})", len(args), strings.Join(args, ", "))
				argsList := t.materializeAndRoot(listExpr)
				t.emit(fmt.Sprintf("oren_print_list(%s);", argsList))
				return "OREN_NIL", nil
			case "py_import":
				if len(e.Arguments) != 1 {
					return "", fmt.Errorf("py_import expects 1 argument")
				}
				a0, err := t.evalExprValue(e.Arguments[0])
				if err != nil {
					return "", err
				}
				return t.materializeAndRoot(fmt.Sprintf("oren_py_import(%s)", a0)), nil
			case "system":
				if len(e.Arguments) != 1 {
					return "", fmt.Errorf("system expects 1 argument")
				}
				a0, err := t.evalExprValue(e.Arguments[0])
				if err != nil {
					return "", err
				}
				return t.materializeAndRoot(fmt.Sprintf("oren_system(%s)", a0)), nil
			case "exit":
				if len(e.Arguments) != 1 {
					return "", fmt.Errorf("exit expects 1 argument")
				}
				a0, err := t.evalExprValue(e.Arguments[0])
				if err != nil {
					return "", err
				}
				return t.materializeAndRoot(fmt.Sprintf("oren_exit(%s)", a0)), nil
			case "iadd":
				if len(e.Arguments) != 2 {
					return "", fmt.Errorf("iadd expects 2 arguments")
				}
				a0, err := t.evalExprValue(e.Arguments[0])
				if err != nil {
					return "", err
				}
				a1, err := t.evalExprValue(e.Arguments[1])
				if err != nil {
					return "", err
				}
				return t.materializeAndRoot(fmt.Sprintf("oren_add(%s, %s)", a0, a1)), nil
			}
		}

		// Constructor shorthand.
		directSym := ""
		if id, ok := e.Function.(*ast.Identifier); ok {
			if t.ctx.typeNamespaces != nil {
				if _, isType := t.ctx.typeNamespaces[id.Value]; isType {
					directSym = id.Value + "__new"
				}
			}
		} else if me, ok := e.Function.(*ast.MemberExpression); ok {
			if res, isNs, err := t.resolveNamespaceExpr(me); err != nil {
				return "", err
			} else if res != "" && isNs {
				directSym = res + "__new"
			}
		}

		// Direct call detection for known symbols.
		switch callee := e.Function.(type) {
		case *ast.Identifier:
			if directSym == "" {
				if _, exists := t.definedFunctions[callee.Value]; exists {
					directSym = callee.Value
				} else if strings.HasPrefix(callee.Value, "oren_") {
					directSym = callee.Value
				}
			}
		case *ast.MemberExpression:
			if directSym == "" {
				if name, _, err := t.resolveNamespaceExpr(callee); err != nil {
					return "", err
				} else if name != "" {
					if _, exists := t.definedFunctions[name]; exists {
						directSym = name
					}
				}
			}
		}

		args := []string{}
		for _, a := range e.Arguments {
			v, err := t.evalExprValue(a)
			if err != nil {
				return "", err
			}
			args = append(args, v)
		}

		if directSym != "" {
			// Some runtime entrypoints are void-returning but are used as statement-level calls in Oren.
			// Treat them as producing `nil` to keep codegen robust.
			switch directSym {
			case "oren_print", "oren_print_list", "oren_print_fmt_list", "oren_print_spread", "oren_print_fmt_spread", "oren_print_fmt",
				"oren_gc_collect", "oren_gc_safepoint", "oren_shutdown":
				t.emit(fmt.Sprintf("%s(%s);", directSym, strings.Join(args, ", ")))
				return "OREN_NIL", nil
			default:
				return t.materializeAndRoot(fmt.Sprintf("%s(%s)", directSym, strings.Join(args, ", "))), nil
			}
		}

		// Indirect call via OrenValue.
		fnVal, err := t.evalExprValue(e.Function)
		if err != nil {
			return "", err
		}
		if len(args) == 0 {
			return t.materializeAndRoot(fmt.Sprintf("oren_call_obj_argv(%s, 0, NULL)", fnVal)), nil
		}
		return t.materializeAndRoot(fmt.Sprintf("oren_call_obj_argv(%s, %d, (OrenValue[]){%s})", fnVal, len(args), strings.Join(args, ", "))), nil
	case *ast.IfExpression:
		return "", fmt.Errorf("if expressions not supported in C expression context (use as statement)")
	default:
		return "", fmt.Errorf("unknown expression: %T", exp)
	}
}
