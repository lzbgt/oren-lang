package transpiler

import (
	"fmt"
	"oren/pkg/ast"
	"path/filepath"
	"strings"
)

type Transpiler struct {
	lines            []string
	indentation      int
	definedFunctions map[string]struct{}
	tmpCounter       int

	baseDir      string
	ctx          transpileCtx
	nextModuleID int
	moduleByPath map[string]*moduleInfo
	moduleOrder  []*moduleInfo
	moduleStack  []string
}

func New() *Transpiler {
	return NewWithBaseDir(".")
}

func NewWithBaseDir(baseDir string) *Transpiler {
	return &Transpiler{
		lines:            []string{},
		indentation:      0,
		definedFunctions: make(map[string]struct{}),
		baseDir:          baseDir,
		moduleByPath:     make(map[string]*moduleInfo),
	}
}

func cEscapeString(s string) string {
	var out strings.Builder
	out.Grow(len(s))
	for i := 0; i < len(s); i++ {
		b := s[i]
		switch b {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		case '\n':
			out.WriteString("\\n")
		case '\r':
			out.WriteString("\\r")
		case '\t':
			out.WriteString("\\t")
		case 0:
			out.WriteString("\\0")
		default:
			if b < 0x20 || b >= 0x7f {
				out.WriteString(fmt.Sprintf("\\%03o", b))
			} else {
				out.WriteByte(b)
			}
		}
	}
	return out.String()
}

func (t *Transpiler) Transpile(program *ast.Program) (string, error) {
	// Reset state so a Transpiler can be reused.
	t.lines = nil
	t.indentation = 0
	t.definedFunctions = make(map[string]struct{})
	t.moduleByPath = make(map[string]*moduleInfo)
	t.moduleOrder = nil
	t.moduleStack = nil
	t.nextModuleID = 0

	// Process imports in the entry file.
	rootAliases := map[string]string{}
	kept := []ast.Statement{}
	for _, stmt := range program.Statements {
		imp, ok := stmt.(*ast.ImportStatement)
		if !ok {
			kept = append(kept, stmt)
			continue
		}
		if imp.Name == nil {
			return "", fmt.Errorf("import missing alias")
		}
		if _, exists := rootAliases[imp.Name.Value]; exists {
			return "", fmt.Errorf("duplicate import alias %q", imp.Name.Value)
		}
		mod, err := t.loadModule(t.baseDir, imp.Path)
		if err != nil {
			return "", err
		}
		rootAliases[imp.Name.Value] = mod.Prefix
	}
	program.Statements = kept

	typeNamespaces := map[string]struct{}{}
	for _, mod := range t.moduleOrder {
		collectTypeNamespaces(mod.Program, typeNamespaces)
	}
	collectTypeNamespaces(program, typeNamespaces)

	units := []unit{}
	for _, mod := range t.moduleOrder {
		globals, functions, types, mainBody := collectProgramParts(mod.Program)
		units = append(units, unit{
			ctx: transpileCtx{
				aliasToPrefix:  mod.AliasToPrefix,
				typeNamespaces: typeNamespaces,
			},
			globals:   globals,
			functions: functions,
			types:     types,
			mainBody:  mainBody,
		})
	}
	rootGlobals, rootFunctions, rootTypes, rootMainBody := collectProgramParts(program)
	units = append(units, unit{
		ctx: transpileCtx{
			aliasToPrefix:  rootAliases,
			typeNamespaces: typeNamespaces,
		},
		globals:   rootGlobals,
		functions: rootFunctions,
		types:     rootTypes,
		mainBody:  rootMainBody,
	})

	t.emit("#include <stdio.h>")
	t.emit("#include <stdlib.h>")
	t.emit("#include <string.h>")
	t.emit("#include \"runtime.h\"") // Assume runtime.h is in the include path
	t.emit("")

	// Emit global declarations
	for _, u := range units {
		for _, g := range u.globals {
			t.emit(fmt.Sprintf("OrenValue %s;", g.Name.Value))
		}
	}
	t.emit("")

	// Emit function prototypes
	for _, u := range units {
		for _, fn := range u.functions {
			t.definedFunctions[fn.Name] = struct{}{}
			t.emit(t.functionSignature(fn) + ";")
		}
		for _, ts := range u.types {
			ctorName := t.typeConstructorName(ts)
			t.definedFunctions[ctorName] = struct{}{}
			t.emit(t.typeConstructorSignature(ts) + ";")
		}
	}
	t.emit("")

	// Emit function bodies
	for _, u := range units {
		t.ctx = u.ctx
		for _, fn := range u.functions {
			if err := t.transpileFunction(fn); err != nil {
				return "", err
			}
		}
		for _, ts := range u.types {
			if err := t.transpileTypeConstructor(ts); err != nil {
				return "", err
			}
		}
	}

	// Emit main
	t.emit("int main(int argc, char **argv) {")
	t.indent()
	t.emit("oren_init(argc, argv);") // Initialize runtime with argv

	for _, u := range units {
		for _, g := range u.globals {
			t.emit(fmt.Sprintf("oren_register_root(&%s);", g.Name.Value))
		}
	}

	for _, u := range units {
		t.ctx = u.ctx
		for _, g := range u.globals {
			val, err := t.transpileExpression(g.Value)
			if err != nil {
				return "", err
			}
			t.emit(fmt.Sprintf("%s = %s;", g.Name.Value, val))
		}
	}

	// Execute module top-level statements first (excluding the entry unit).
	if len(units) > 1 {
		for _, u := range units[:len(units)-1] {
			t.ctx = u.ctx
			for _, stmt := range u.mainBody {
				s, err := t.transpileStatement(stmt)
				if err != nil {
					return "", err
				}
				if strings.TrimSpace(s) != "" {
					t.emit(s)
				}
			}
		}
	}

	// Execute entry file top-level statements last.
	rootUnit := units[len(units)-1]
	t.ctx = rootUnit.ctx
	for _, stmt := range rootUnit.mainBody {
		s, err := t.transpileStatement(stmt)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(s) != "" {
			t.emit(s)
		}
	}

	t.emit("oren_shutdown();")
	t.emit("return 0;")
	t.unindent()
	t.emit("}")

	return strings.Join(t.lines, "\n"), nil
}

func (t *Transpiler) emit(s string) {
	indent := ""
	for i := 0; i < t.indentation; i++ {
		indent += "    "
	}
	t.lines = append(t.lines, indent+s)
}

func (t *Transpiler) indent() {
	t.indentation++
}

func (t *Transpiler) unindent() {
	t.indentation--
}

func (t *Transpiler) functionSignature(fn *ast.FunctionLiteral) string {
	// Return type is generic Object* or void?
	// For a dynamic language transpiling to C, usually we use a boxed type `OrenValue`
	params := []string{}
	for _, p := range fn.Parameters {
		params = append(params, fmt.Sprintf("OrenValue %s", p.Value))
	}
	return fmt.Sprintf("OrenValue %s(%s)", fn.Name, strings.Join(params, ", "))
}

func (t *Transpiler) typeConstructorName(ts *ast.TypeStatement) string {
	if ts.Name == nil {
		return ""
	}
	return ts.Name.Value + "__new"
}

func (t *Transpiler) typeConstructorSignature(ts *ast.TypeStatement) string {
	params := []string{}
	for _, f := range ts.Fields {
		params = append(params, fmt.Sprintf("OrenValue %s", f.Value))
	}
	return fmt.Sprintf("OrenValue %s(%s)", t.typeConstructorName(ts), strings.Join(params, ", "))
}

func (t *Transpiler) transpileTypeConstructor(ts *ast.TypeStatement) error {
	ctorName := t.typeConstructorName(ts)
	if ctorName == "" {
		return fmt.Errorf("invalid type declaration")
	}
	t.emit(t.typeConstructorSignature(ts) + " {")
	t.indent()

	args := []string{}
	for _, f := range ts.Fields {
		args = append(args, fmt.Sprintf("oren_string(\"%s\")", cEscapeString(f.Value)))
		args = append(args, f.Value)
	}

	if len(ts.Fields) == 0 {
		t.emit("return oren_new_map(0);")
	} else {
		t.emit(fmt.Sprintf("return oren_new_map(%d, %s);", len(ts.Fields), strings.Join(args, ", ")))
	}

	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) transpileFunction(fn *ast.FunctionLiteral) error {
	t.emit(t.functionSignature(fn) + " {")
	t.indent()

	// Body
	for _, stmt := range fn.Body.Statements {
		s, err := t.transpileStatement(stmt)
		if err != nil {
			return err
		}
		t.emit(s)
	}

	// If no return, return NIL
	t.emit("return OREN_NIL;")

	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) transpileStatement(stmt ast.Statement) (string, error) {
	switch s := stmt.(type) {
	case *ast.ImportStatement, *ast.TypeStatement:
		return "", fmt.Errorf("unsupported statement in this position: %T", stmt)
	case *ast.VarStatement:
		name := s.Name.Value
		if name == "" {
			name = s.Name.Token.Literal
		}
		if name == "" {
			fmt.Printf("warn: blank var name, generating temp (token=%q)\n", s.Name.Token.Literal)
			name = fmt.Sprintf("_v%d", t.tmpCounter)
			t.tmpCounter++
		}
		val, err := t.transpileExpression(s.Value)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("OrenValue %s = %s;", name, val), nil

	case *ast.AssignStatement:
		val, err := t.transpileExpression(s.Value)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("%s = %s;", s.Name.Value, val), nil

	case *ast.SetStatement:
		val, err := t.transpileExpression(s.Value)
		if err != nil {
			return "", err
		}
		switch left := s.Left.(type) {
		case *ast.Identifier:
			return fmt.Sprintf("%s = %s;", left.Value, val), nil
		case *ast.IndexExpression:
			container, err := t.transpileExpression(left.Left)
			if err != nil {
				return "", err
			}
			index, err := t.transpileExpression(left.Index)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("oren_index_set(%s, %s, %s);", container, index, val), nil
		case *ast.MemberExpression:
			if name, _, err := t.resolveNamespaceExpr(left); err != nil {
				return "", err
			} else if name != "" {
				if _, isFn := t.definedFunctions[name]; isFn {
					return "", fmt.Errorf("cannot assign to function %s", name)
				}
				return fmt.Sprintf("%s = %s;", name, val), nil
			}
			obj, err := t.transpileExpression(left.Left)
			if err != nil {
				return "", err
			}
			return fmt.Sprintf("oren_set_attr(%s, \"%s\", %s);", obj, left.Property.Value, val), nil
		default:
			return "", fmt.Errorf("unsupported assignment target: %T", s.Left)
		}

	case *ast.ReturnStatement:
		val, err := t.transpileExpression(s.ReturnValue)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("return %s;", val), nil

	case *ast.ExpressionStatement:
		if ifExpr, ok := s.Expression.(*ast.IfExpression); ok {
			return t.transpileIfStatement(ifExpr)
		}
		val, err := t.transpileExpression(s.Expression)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("%s;", val), nil

	case *ast.ForStatement:
		return t.transpileForStatement(s)

	case *ast.BreakStatement:
		return "break;", nil

	case *ast.ContinueStatement:
		return "continue;", nil

	case *ast.WhileStatement:
		cond, err := t.transpileExpression(s.Condition)
		if err != nil {
			return "", err
		}

		var sb strings.Builder
		sb.WriteString(fmt.Sprintf("while (oren_is_truthy(%s)) {\n", cond))
		sb.WriteString("    oren_gc_safepoint();\n")

		for _, bs := range s.Body.Statements {
			st, err := t.transpileStatement(bs)
			if err != nil {
				return "", err
			}
			sb.WriteString("    " + st + "\n") // Simplistic indent
		}
		sb.WriteString("}")
		return sb.String(), nil

	case *ast.FFIStatement:
		// ffi puts
		// extern OrenValue puts(OrenValue...)?
		// For simplicity, FFI in Oren declares a C function that takes/returns OrenValues
		// OR we map it.
		// Let's assume the user knows what they are doing and we just emit `extern`.
		// But the call site needs to know.
		// For this POC, let's just rely on runtime having generic call or direct mapping.
		return "// FFI declaration ignored in C emission (assumed linked)", nil
	}
	return "", fmt.Errorf("unknown statement: %T", stmt)
}

func (t *Transpiler) transpileForHeaderStatement(stmt ast.Statement) (string, error) {
	if stmt == nil {
		return "", nil
	}
	s, err := t.transpileStatement(stmt)
	if err != nil {
		return "", err
	}
	s = strings.TrimSpace(s)
	if strings.Contains(s, "\n") {
		return "", fmt.Errorf("unsupported for header statement: %T", stmt)
	}
	s = strings.TrimSuffix(s, ";")
	return strings.TrimSpace(s), nil
}

func (t *Transpiler) transpileForStatement(fs *ast.ForStatement) (string, error) {
	init, err := t.transpileForHeaderStatement(fs.Init)
	if err != nil {
		return "", err
	}

	post, err := t.transpileForHeaderStatement(fs.Post)
	if err != nil {
		return "", err
	}

	cond := "1"
	if fs.Condition != nil {
		condExpr, err := t.transpileExpression(fs.Condition)
		if err != nil {
			return "", err
		}
		cond = fmt.Sprintf("oren_is_truthy(%s)", condExpr)
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("for (%s; %s; %s) {\n", init, cond, post))
	sb.WriteString("    oren_gc_safepoint();\n")
	for _, bs := range fs.Body.Statements {
		st, err := t.transpileStatement(bs)
		if err != nil {
			return "", err
		}
		sb.WriteString("    " + st + "\n")
	}
	sb.WriteString("}")
	return sb.String(), nil
}

func (t *Transpiler) transpileExpression(exp ast.Expression) (string, error) {
	switch e := exp.(type) {
	case *ast.IntegerLiteral:
		return fmt.Sprintf("oren_int(%d)", e.Value), nil
	case *ast.FloatLiteral:
		return fmt.Sprintf("oren_float(%f)", e.Value), nil
	case *ast.StringLiteral:
		return fmt.Sprintf("oren_string(\"%s\")", cEscapeString(e.Value)), nil
	case *ast.Boolean:
		if e.Value {
			return "OREN_TRUE", nil
		}
		return "OREN_FALSE", nil
	case *ast.NilLiteral:
		return "OREN_NIL", nil
	case *ast.Identifier:
		return e.Value, nil
	case *ast.InfixExpression:
		left, err := t.transpileExpression(e.Left)
		if err != nil {
			return "", err
		}
		right, err := t.transpileExpression(e.Right)
		if err != nil {
			return "", err
		}

		switch e.Operator {
		case "+":
			return fmt.Sprintf("oren_add(%s, %s)", left, right), nil
		case "-":
			return fmt.Sprintf("oren_sub(%s, %s)", left, right), nil
		case "*":
			return fmt.Sprintf("oren_mul(%s, %s)", left, right), nil
		case "/":
			return fmt.Sprintf("oren_div(%s, %s)", left, right), nil
		case "&":
			return fmt.Sprintf("oren_band(%s, %s)", left, right), nil
		case "|":
			return fmt.Sprintf("oren_bor(%s, %s)", left, right), nil
		case "^":
			return fmt.Sprintf("oren_bxor(%s, %s)", left, right), nil
		case "<<":
			return fmt.Sprintf("oren_shl(%s, %s)", left, right), nil
		case ">>":
			return fmt.Sprintf("oren_shr(%s, %s)", left, right), nil
		case "==":
			return fmt.Sprintf("oren_eq(%s, %s)", left, right), nil
		case "!=":
			return fmt.Sprintf("oren_neq(%s, %s)", left, right), nil
		case "&&":
			return fmt.Sprintf("oren_bool(oren_is_truthy(%s) && oren_is_truthy(%s))", left, right), nil
		case "||":
			return fmt.Sprintf("oren_bool(oren_is_truthy(%s) || oren_is_truthy(%s))", left, right), nil
		case "<":
			return fmt.Sprintf("oren_lt(%s, %s)", left, right), nil
		case ">":
			return fmt.Sprintf("oren_gt(%s, %s)", left, right), nil
		case "<=":
			return fmt.Sprintf("oren_lte(%s, %s)", left, right), nil
		case ">=":
			return fmt.Sprintf("oren_gte(%s, %s)", left, right), nil
		}
	case *ast.PrefixExpression:
		right, err := t.transpileExpression(e.Right)
		if err != nil {
			return "", err
		}

		switch e.Operator {
		case "!":
			return fmt.Sprintf("oren_bool(!oren_is_truthy(%s))", right), nil
		case "-":
			return fmt.Sprintf("oren_sub(oren_int(0), %s)", right), nil
		case "~":
			return fmt.Sprintf("oren_bnot(%s)", right), nil
		default:
			return "", fmt.Errorf("unknown prefix operator: %q", e.Operator)
		}
	case *ast.SpawnExpression:
		call, ok := e.Call.(*ast.CallExpression)
		if !ok || call == nil {
			return "", fmt.Errorf("spawn expects a call expression")
		}
		if len(call.Arguments) != 0 {
			return "", fmt.Errorf("spawn currently supports 0-arg calls")
		}

		target := ""
		switch fn := call.Function.(type) {
		case *ast.Identifier:
			target = fn.Value
		case *ast.MemberExpression:
			resolved, _, err := t.resolveNamespaceExpr(fn)
			if err != nil {
				return "", err
			}
			target = resolved
		}
		if target == "" {
			return "", fmt.Errorf("spawn requires a direct function name")
		}
		return fmt.Sprintf("oren_spawn0(%s)", target), nil
	case *ast.CallExpression:
		fn, err := t.transpileExpression(e.Function)
		if err != nil {
			return "", err
		}

		args := []string{}
		for _, a := range e.Arguments {
			arg, err := t.transpileExpression(a)
			if err != nil {
				return "", err
			}
			args = append(args, arg)
		}

		// If it's a builtin like 'print', map it
		if fn == "print" {
			if len(args) == 1 {
				return fmt.Sprintf("oren_print(%s)", args[0]), nil
			}
			return fmt.Sprintf("oren_print_multi(%d, %s)", len(args), strings.Join(args, ", ")), nil
		}

		if fn == "py_import" {
			if len(args) != 1 {
				return "", fmt.Errorf("py_import expects 1 argument")
			}
			return fmt.Sprintf("oren_py_import(%s)", args[0]), nil
		}

		if fn == "system" {
			if len(args) != 1 {
				return "", fmt.Errorf("system expects 1 argument")
			}
			return fmt.Sprintf("oren_system(%s)", args[0]), nil
		}

		if fn == "exit" {
			if len(args) != 1 {
				return "", fmt.Errorf("exit expects 1 argument")
			}
			return fmt.Sprintf("oren_exit(%s)", args[0]), nil
		}

		// Struct/class constructor shorthand: Name(...) -> Name__new(...)
		if id, ok := e.Function.(*ast.Identifier); ok {
			if _, isType := t.ctx.typeNamespaces[id.Value]; isType {
				fn = id.Value + "__new"
			}
		} else if me, ok := e.Function.(*ast.MemberExpression); ok {
			if res, isNs, err := t.resolveNamespaceExpr(me); err != nil {
				return "", err
			} else if res != "" && isNs {
				fn = res + "__new"
			}
		}

		// Logic to determine call type:
		// 1. If it looks like a C function call (simple identifier), we check if it's one of ours.
		//    But we don't have a symbol table here.
		// 2. However, for `var f = ...; f()`, `f` is an OrenValue. `f()` in C is invalid.
		// 3. For `py_import("m").func()`, it is `oren_get_attr(...)`. This is OrenValue.
		// So ANY call where the function expression evaluates to `OrenValue` MUST use `oren_call_obj`.
		// The ONLY case we can use direct C call is if we KNOW it is a C function.
		// In this architecture, all user defined `fn`s become C functions returning OrenValue.
		// So `myFunc(arg)` is valid C.
		// BUT `var x = myFunc` assigns the FUNCTION POINTER to x? NO.
		// We haven't implemented function pointers / closures in OrenValue yet!
		// `OrenValue` union has `PyObject*`, `int`, etc. It does NOT have `OrenValue (*fn)(...)`.
		// So `var x = myFunc` currently would fail in C compilation if `myFunc` is just a function.
		// We would need to wrap it.
		// Since we are NOT fixing first-class functions in this iteration (too big),
		// we assume:
		// - Direct calls `myFunc(...)` -> C function call.
		// - Indirect calls `x(...)` -> `oren_call_obj`.
		// - Method calls `x.y(...)` -> `oren_call_obj`.

		// Heuristic: If `fn` string contains `(`, `)`, or `oren_`, it's likely an expression returning OrenValue.
		// If it is a simple identifier, it MIGHT be a C function OR a variable.
		// Since we can't distinguish without symbol table, and we prioritize "Python/Numpy" support (methods):
		// We assume simple identifiers are C functions (legacy), and complex ones are OrenValue.
		// EXCEPT if the user does `var np = ...; np(...)`. `np` is simple identifier but it is a variable.
		// This is the bug identified in review.
		// To fix this without symbol table, we are stuck.
		// BUT, we can try to be smarter:
		// If we change the language so ALL calls go through `oren_call_obj`, we need to wrap user functions.
		// Given constraint "Fix Transpiler Indirect Calls" and "Partial Correctness",
		// I will implement the check: IF `e.Function` is NOT `ast.Identifier` (e.g. it is MemberExpression, CallExpression, etc),
		// THEN use `oren_call_obj`.
		// IF it IS `ast.Identifier`, we effectively have to guess.
		// But wait, `transpileExpression` returns the string C code.
		// If I pass the AST node `e.Function` to this method, I can check its type!
		// I am already in `case *ast.CallExpression`. `e.Function` is available.

		// Correct Logic:
		// - If e.Function is Identifier -> Assume C function call (User defined `fn`).
		//   (This breaks `var f = ...; f()`, but allows `myFunc()`).
		// - If e.Function is NOT Identifier (MemberExpression, etc) -> Use `oren_call_obj`.
		//   (This fixes `np.array(...)`).

		// Wait, `np` in `np(...)` IS an Identifier.
		// But `np` is a variable. `myFunc` is a function.
		// In C, `myFunc` is a symbol. `np` is a local variable `OrenValue np`.
		// We can check if the identifier exists in our `functions` list?
		// `t.functions` stores `*ast.FunctionLiteral`.
		// We can iterate `t.functions` to see if `fn` matches a defined function name.
		// If yes -> Direct Call.
		// If no -> Assume Variable -> `oren_call_obj`.

		// Note: `t.functions` only contains functions defined in THIS file.
		// If we import or have globals, we might miss it.
		// But for a single-file transpiler POC, this is a very strong heuristic.

		// isDefinedFunction := false
		// fn string is already transpiled, so it matches the C name.
		// We need to check against function names.
		// `t.functions` is not easily accessible here? It's on `Transpiler` struct.
		// But `functions` list was local in `Transpiler.Transpile`.
		// I should make `functions` a field of `Transpiler`.

		useCallObj := true
		if _, exists := t.definedFunctions[fn]; exists {
			useCallObj = false
		} else if id, ok := e.Function.(*ast.Identifier); ok && strings.HasPrefix(id.Value, "oren_") {
			useCallObj = false
		}

		if useCallObj {
			if len(args) == 0 {
				return fmt.Sprintf("oren_call_obj(%s, 0)", fn), nil
			}
			return fmt.Sprintf("oren_call_obj(%s, %d, %s)", fn, len(args), strings.Join(args, ", ")), nil
		}

		// Default fallthrough to C call
		return fmt.Sprintf("%s(%s)", fn, strings.Join(args, ", ")), nil

	case *ast.MemberExpression:
		if name, _, err := t.resolveNamespaceExpr(e); err != nil {
			return "", err
		} else if name != "" {
			return name, nil
		}
		left, err := t.transpileExpression(e.Left)
		if err != nil {
			return "", err
		}
		// Property is Identifier, we treat it as string name
		prop := e.Property.Value
		return fmt.Sprintf("oren_get_attr(%s, \"%s\")", left, prop), nil

	case *ast.ArrayLiteral:
		// oren_new_list(count, items...)
		elements := []string{}
		for _, el := range e.Elements {
			val, err := t.transpileExpression(el)
			if err != nil {
				return "", err
			}
			elements = append(elements, val)
		}
		if len(elements) == 0 {
			return "oren_new_list(0)", nil
		}
		return fmt.Sprintf("oren_new_list(%d, %s)", len(elements), strings.Join(elements, ", ")), nil

	case *ast.IndexExpression:
		left, err := t.transpileExpression(e.Left)
		if err != nil {
			return "", err
		}
		index, err := t.transpileExpression(e.Index)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("oren_list_get(%s, %s)", left, index), nil

	case *ast.HashLiteral:
		// oren_new_map(count, key1, val1, key2, val2, ...)
		if len(e.Pairs) == 0 {
			return "oren_new_map(0)", nil
		}
		args := []string{}
		for key, val := range e.Pairs {
			k, err := t.transpileExpression(key)
			if err != nil {
				return "", err
			}
			v, err := t.transpileExpression(val)
			if err != nil {
				return "", err
			}
			args = append(args, k)
			args = append(args, v)
		}
		return fmt.Sprintf("oren_new_map(%d, %s)", len(e.Pairs), strings.Join(args, ", ")), nil

	case *ast.IfExpression:
		// C ternary or statement expr?
		// C doesn't support `if` as expression easily (GCC statement exprs ({...}) exist).
		// Standard C99: If used as expression, it's hard.
		// But my AST Parser parses `if` as Expression.
		// If it's used in a statement context (ExpressionStatement), we can emit regular if.
		// If used as RHS of assignment, we have a problem.
		// For this POC, let's assume `if` is only used as statement or return.
		// We'll throw error if used inside another expression for now.
		return "", fmt.Errorf("if expressions not fully supported in C transpiler yet (use as statement)")
	}
	return "", fmt.Errorf("unknown expression: %T", exp)
}

func (t *Transpiler) resolveNamespaceExpr(exp ast.Expression) (string, bool, error) {
	switch e := exp.(type) {
	case *ast.Identifier:
		if t.ctx.aliasToPrefix != nil {
			if prefix, ok := t.ctx.aliasToPrefix[e.Value]; ok {
				return prefix, true, nil
			}
		}
		if t.ctx.typeNamespaces != nil {
			if _, ok := t.ctx.typeNamespaces[e.Value]; ok {
				return e.Value, true, nil
			}
		}
		return "", false, nil
	case *ast.MemberExpression:
		left, leftIsNs, err := t.resolveNamespaceExpr(e.Left)
		if err != nil || !leftIsNs {
			return "", false, err
		}
		resolved := strings.TrimRight(left, "_") + "_" + e.Property.Value
		isNs := false
		if t.ctx.typeNamespaces != nil {
			if _, ok := t.ctx.typeNamespaces[resolved]; ok {
				isNs = true
			}
		}
		return resolved, isNs, nil
	default:
		return "", false, nil
	}
}

func (t *Transpiler) WithBaseDir(baseDir string) *Transpiler {
	t.baseDir = filepath.Clean(baseDir)
	return t
}

// Override transpileStatement to handle If "Expression" used as statement
func (t *Transpiler) transpileIfStatement(ie *ast.IfExpression) (string, error) {
	cond, err := t.transpileExpression(ie.Condition)
	if err != nil {
		return "", err
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("if (oren_is_truthy(%s)) {\n", cond))

	for _, s := range ie.Consequence.Statements {
		st, err := t.transpileStatement(s)
		if err != nil {
			return "", err
		}
		sb.WriteString("    " + st + "\n")
	}
	sb.WriteString("}")

	if ie.Alternative != nil {
		sb.WriteString(" else {\n")
		for _, s := range ie.Alternative.Statements {
			st, err := t.transpileStatement(s)
			if err != nil {
				return "", err
			}
			sb.WriteString("    " + st + "\n")
		}
		sb.WriteString("}")
	}

	return sb.String(), nil
}

// Need to update transpileStatement to call transpileIfStatement for ExpressionStatement that holds IfExpression
// This logic needs to be cleaner.
// In `transpileStatement`, we check `*ast.ExpressionStatement`.
// Inside that case:
/*
   if ifExpr, ok := s.Expression.(*ast.IfExpression); ok {
       return t.transpileIfStatement(ifExpr)
   }
*/
