package transpiler

import (
	"fmt"
	"oren/pkg/ast"
	"strings"
)

type lambdaInfo struct {
	name     string
	lit      *ast.FunctionLiteral
	captures []string // capture-by-value, in deterministic order
	ctx      transpileCtx
}

func (t *Transpiler) lambdaBaseName(unitPrefix string) string {
	// Keep these names out of user namespace.
	n := t.lambdaCounter
	t.lambdaCounter++
	return fmt.Sprintf("__oren_lambda_%s_%d", unitPrefix, n)
}

func (t *Transpiler) lambdaWrapperSignature(name string) string {
	return fmt.Sprintf("OrenValue %s(void* env, int argc, OrenValue* argv)", name)
}

func (t *Transpiler) collectAllLambdas(units []unit) {
	for _, u := range units {
		// globals init
		for _, g := range u.globals {
			t.collectLambdasInExpression(u.prefix, u.ctx, g.Value)
		}
		// function bodies
		for _, fn := range u.functions {
			t.collectLambdasInBlock(u.prefix, u.ctx, fn.Body)
		}
		// type constructors have no body; field initializers are expressions in call-sites only.
		// module top-level
		for _, stmt := range u.mainBody {
			t.collectLambdasInStatement(u.prefix, u.ctx, stmt)
		}
	}
}

func isBuiltinIdentifier(name string) bool {
	switch name {
	case "print", "py_import", "system", "exit":
		return true
	default:
		return false
	}
}

func (t *Transpiler) collectLambda(unitPrefix string, ctx transpileCtx, lit *ast.FunctionLiteral) {
	if lit == nil || lit.Name != "" {
		return
	}
	if _, exists := t.lambdaByPtr[lit]; exists {
		return
	}
	name := t.lambdaBaseName(unitPrefix)
	t.lambdaByPtr[lit] = name
	captures := collectFreeVars(lit, t.definedFunctions)
	t.lambdas = append(t.lambdas, lambdaInfo{name: name, lit: lit, captures: captures, ctx: ctx})

	// Lambdas may contain nested lambdas; make sure they're collected too.
	t.collectLambdasInBlock(unitPrefix, ctx, lit.Body)
}

func (t *Transpiler) collectLambdasInStatement(unitPrefix string, ctx transpileCtx, stmt ast.Statement) {
	if stmt == nil {
		return
	}
	switch s := stmt.(type) {
	case *ast.VarStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.Value)
	case *ast.AssignStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.Value)
	case *ast.SetStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.Left)
		t.collectLambdasInExpression(unitPrefix, ctx, s.Value)
	case *ast.ReturnStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.ReturnValue)
	case *ast.ExpressionStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.Expression)
	case *ast.BlockStatement:
		t.collectLambdasInBlock(unitPrefix, ctx, s)
	case *ast.WhileStatement:
		t.collectLambdasInExpression(unitPrefix, ctx, s.Condition)
		t.collectLambdasInBlock(unitPrefix, ctx, s.Body)
	case *ast.ForStatement:
		t.collectLambdasInStatement(unitPrefix, ctx, s.Init)
		t.collectLambdasInExpression(unitPrefix, ctx, s.Condition)
		t.collectLambdasInStatement(unitPrefix, ctx, s.Post)
		t.collectLambdasInBlock(unitPrefix, ctx, s.Body)
	default:
		// Import/type statements are handled elsewhere; ignore.
	}
}

func (t *Transpiler) collectLambdasInBlock(unitPrefix string, ctx transpileCtx, blk *ast.BlockStatement) {
	if blk == nil {
		return
	}
	for _, st := range blk.Statements {
		t.collectLambdasInStatement(unitPrefix, ctx, st)
	}
}

func (t *Transpiler) collectLambdasInExpression(unitPrefix string, ctx transpileCtx, expr ast.Expression) {
	if expr == nil {
		return
	}
	switch e := expr.(type) {
	case *ast.FunctionLiteral:
		t.collectLambda(unitPrefix, ctx, e)
	case *ast.CallExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Function)
		for _, a := range e.Arguments {
			t.collectLambdasInExpression(unitPrefix, ctx, a)
		}
	case *ast.InfixExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Left)
		t.collectLambdasInExpression(unitPrefix, ctx, e.Right)
	case *ast.PrefixExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Right)
	case *ast.IfExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Condition)
		t.collectLambdasInBlock(unitPrefix, ctx, e.Consequence)
		t.collectLambdasInBlock(unitPrefix, ctx, e.Alternative)
	case *ast.MemberExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Left)
		// Property is not an expression (do not traverse)
	case *ast.IndexExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Left)
		t.collectLambdasInExpression(unitPrefix, ctx, e.Index)
	case *ast.ArrayLiteral:
		for _, el := range e.Elements {
			t.collectLambdasInExpression(unitPrefix, ctx, el)
		}
	case *ast.HashLiteral:
		for k, v := range e.Pairs {
			t.collectLambdasInExpression(unitPrefix, ctx, k)
			t.collectLambdasInExpression(unitPrefix, ctx, v)
		}
	case *ast.SpawnExpression:
		t.collectLambdasInExpression(unitPrefix, ctx, e.Call)
	default:
		// literals / identifiers
	}
}

func (t *Transpiler) transpileLambda(li lambdaInfo) error {
	// Lambdas are emitted as OrenFn-ABI wrapper functions:
	//   OrenValue __oren_lambda_...(void* env, int argc, OrenValue* argv)
	// The closure environment is a list of captured values (capture-by-value).

	t.ctx = li.ctx
	t.emit(t.lambdaWrapperSignature(li.name) + " {")
	t.indent()

	// Precise root stack for this call frame.
	t.curFuncRootMark = t.newCTmp("root_mark_")
	t.curReturnVar = t.newCTmp("ret_")
	t.curReturnLabel = t.newCTmp("return_")
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", t.curFuncRootMark))
	t.emit(fmt.Sprintf("OrenValue %s = OREN_NIL;", t.curReturnVar))

	if len(li.captures) == 0 {
		t.emit("(void)env;")
	} else {
		// Keep the closure environment alive for the duration of this call, independent of
		// conservative stack/register scanning.
		envRoot := t.newCTmp("env_")
		t.emit(fmt.Sprintf("OrenValue %s; %s.type = OREN_TYPE_LIST; %s.as.list_val = (OrenList*)env;", envRoot, envRoot, envRoot))
		t.emit(fmt.Sprintf("oren_roots_push(&%s);", envRoot))
		t.emit("OrenList* __env = (OrenList*)env;")
		t.emit(fmt.Sprintf("if (!__env || __env->count != %d) { oren_panic(\"closure env mismatch\"); }", len(li.captures)))
		for i, name := range li.captures {
			t.emit(fmt.Sprintf("OrenValue %s = __env->items[%d];", name, i))
			t.emit(fmt.Sprintf("oren_roots_push(&%s);", name))
		}
	}

	if len(li.lit.Parameters) == 0 {
		t.emit("(void)argc;")
		t.emit("(void)argv;")
	} else {
		t.emit(fmt.Sprintf("if (argc != %d) { oren_panic(\"arity mismatch\"); }", len(li.lit.Parameters)))
		for i, p := range li.lit.Parameters {
			t.emit(fmt.Sprintf("OrenValue %s = argv[%d];", p.Value, i))
			t.emit(fmt.Sprintf("oren_roots_push(&%s);", p.Value))
		}
	}

	// Body
	for _, st := range li.lit.Body.Statements {
		if err := t.emitStatement(st); err != nil {
			return err
		}
	}
	t.emit(fmt.Sprintf("goto %s;", t.curReturnLabel))
	t.emit(fmt.Sprintf("%s:", t.curReturnLabel))
	t.emit(fmt.Sprintf("oren_roots_reset(%s);", t.curFuncRootMark))
	t.emit(fmt.Sprintf("return %s;", t.curReturnVar))

	t.unindent()
	t.emit("}")
	t.curFuncRootMark = ""
	t.curReturnVar = ""
	t.curReturnLabel = ""
	t.loopMarkStack = nil
	return nil
}

func isNonCapturableIdentifier(name string) bool {
	if name == "" {
		return true
	}
	if isBuiltinIdentifier(name) {
		return true
	}
	// These are reserved runtime/syscall namespaces in the C backend; capturing them
	// would produce invalid C identifiers-as-values.
	if strings.HasPrefix(name, "oren_") || strings.HasPrefix(name, "sys_") {
		return true
	}
	return false
}

func collectFreeVars(lit *ast.FunctionLiteral, _ map[string]struct{}) []string {
	if lit == nil || lit.Body == nil {
		return nil
	}

	declared := map[string]struct{}{}
	for _, p := range lit.Parameters {
		if p != nil && p.Value != "" {
			declared[p.Value] = struct{}{}
		}
	}

	// Collect all `var` declarations inside the lambda (any depth), excluding nested lambdas.
	collectDeclaredInBlock(lit.Body, declared)

	out := []string{}
	seen := map[string]struct{}{}
	collectUsedInBlock(lit.Body, declared, seen, &out)
	return out
}

func collectDeclaredInBlock(blk *ast.BlockStatement, declared map[string]struct{}) {
	if blk == nil {
		return
	}
	for _, st := range blk.Statements {
		collectDeclaredInStatement(st, declared)
	}
}

func collectDeclaredInStatement(stmt ast.Statement, declared map[string]struct{}) {
	if stmt == nil {
		return
	}
	switch s := stmt.(type) {
	case *ast.VarStatement:
		if s.Name != nil && s.Name.Value != "" {
			declared[s.Name.Value] = struct{}{}
		}
		collectDeclaredInExpression(s.Value, declared)
	case *ast.AssignStatement:
		collectDeclaredInExpression(s.Value, declared)
	case *ast.SetStatement:
		collectDeclaredInExpression(s.Left, declared)
		collectDeclaredInExpression(s.Value, declared)
	case *ast.ReturnStatement:
		collectDeclaredInExpression(s.ReturnValue, declared)
	case *ast.ExpressionStatement:
		collectDeclaredInExpression(s.Expression, declared)
	case *ast.BlockStatement:
		collectDeclaredInBlock(s, declared)
	case *ast.WhileStatement:
		collectDeclaredInExpression(s.Condition, declared)
		collectDeclaredInBlock(s.Body, declared)
	case *ast.ForStatement:
		collectDeclaredInStatement(s.Init, declared)
		collectDeclaredInExpression(s.Condition, declared)
		collectDeclaredInStatement(s.Post, declared)
		collectDeclaredInBlock(s.Body, declared)
	default:
	}
}

func collectDeclaredInExpression(expr ast.Expression, declared map[string]struct{}) {
	if expr == nil {
		return
	}
	switch e := expr.(type) {
	case *ast.FunctionLiteral:
		// Nested lambdas are their own scopes; do not treat their vars as local here.
		return
	case *ast.CallExpression:
		collectDeclaredInExpression(e.Function, declared)
		for _, a := range e.Arguments {
			collectDeclaredInExpression(a, declared)
		}
	case *ast.InfixExpression:
		collectDeclaredInExpression(e.Left, declared)
		collectDeclaredInExpression(e.Right, declared)
	case *ast.PrefixExpression:
		collectDeclaredInExpression(e.Right, declared)
	case *ast.IfExpression:
		collectDeclaredInExpression(e.Condition, declared)
		collectDeclaredInBlock(e.Consequence, declared)
		collectDeclaredInBlock(e.Alternative, declared)
	case *ast.MemberExpression:
		collectDeclaredInExpression(e.Left, declared)
	case *ast.IndexExpression:
		collectDeclaredInExpression(e.Left, declared)
		collectDeclaredInExpression(e.Index, declared)
	case *ast.ArrayLiteral:
		for _, el := range e.Elements {
			collectDeclaredInExpression(el, declared)
		}
	case *ast.HashLiteral:
		for k, v := range e.Pairs {
			collectDeclaredInExpression(k, declared)
			collectDeclaredInExpression(v, declared)
		}
	case *ast.SpawnExpression:
		collectDeclaredInExpression(e.Call, declared)
	default:
	}
}

func collectUsedInBlock(blk *ast.BlockStatement, declared map[string]struct{}, seen map[string]struct{}, out *[]string) {
	if blk == nil {
		return
	}
	for _, st := range blk.Statements {
		collectUsedInStatement(st, declared, seen, out)
	}
}

func collectUsedInStatement(stmt ast.Statement, declared map[string]struct{}, seen map[string]struct{}, out *[]string) {
	if stmt == nil {
		return
	}
	switch s := stmt.(type) {
	case *ast.VarStatement:
		collectUsedInExpression(s.Value, declared, seen, out)
	case *ast.AssignStatement:
		if s.Name != nil && s.Name.Value != "" {
			maybeAddCapture(s.Name.Value, declared, seen, out)
		}
		collectUsedInExpression(s.Value, declared, seen, out)
	case *ast.SetStatement:
		switch left := s.Left.(type) {
		case *ast.Identifier:
			maybeAddCapture(left.Value, declared, seen, out)
		default:
			collectUsedInExpression(s.Left, declared, seen, out)
		}
		collectUsedInExpression(s.Value, declared, seen, out)
	case *ast.ReturnStatement:
		collectUsedInExpression(s.ReturnValue, declared, seen, out)
	case *ast.ExpressionStatement:
		collectUsedInExpression(s.Expression, declared, seen, out)
	case *ast.BlockStatement:
		collectUsedInBlock(s, declared, seen, out)
	case *ast.WhileStatement:
		collectUsedInExpression(s.Condition, declared, seen, out)
		collectUsedInBlock(s.Body, declared, seen, out)
	case *ast.ForStatement:
		collectUsedInStatement(s.Init, declared, seen, out)
		collectUsedInExpression(s.Condition, declared, seen, out)
		collectUsedInStatement(s.Post, declared, seen, out)
		collectUsedInBlock(s.Body, declared, seen, out)
	default:
	}
}

func collectUsedInExpression(expr ast.Expression, declared map[string]struct{}, seen map[string]struct{}, out *[]string) {
	if expr == nil {
		return
	}
	switch e := expr.(type) {
	case *ast.Identifier:
		maybeAddCapture(e.Value, declared, seen, out)
	case *ast.FunctionLiteral:
		// Nested lambdas are their own closures; do not capture their internals here.
		return
	case *ast.CallExpression:
		collectUsedInExpression(e.Function, declared, seen, out)
		for _, a := range e.Arguments {
			collectUsedInExpression(a, declared, seen, out)
		}
	case *ast.InfixExpression:
		collectUsedInExpression(e.Left, declared, seen, out)
		collectUsedInExpression(e.Right, declared, seen, out)
	case *ast.PrefixExpression:
		collectUsedInExpression(e.Right, declared, seen, out)
	case *ast.IfExpression:
		collectUsedInExpression(e.Condition, declared, seen, out)
		collectUsedInBlock(e.Consequence, declared, seen, out)
		collectUsedInBlock(e.Alternative, declared, seen, out)
	case *ast.MemberExpression:
		collectUsedInExpression(e.Left, declared, seen, out)
		// Property is not a variable use.
	case *ast.IndexExpression:
		collectUsedInExpression(e.Left, declared, seen, out)
		collectUsedInExpression(e.Index, declared, seen, out)
	case *ast.ArrayLiteral:
		for _, el := range e.Elements {
			collectUsedInExpression(el, declared, seen, out)
		}
	case *ast.HashLiteral:
		for k, v := range e.Pairs {
			collectUsedInExpression(k, declared, seen, out)
			collectUsedInExpression(v, declared, seen, out)
		}
	case *ast.SpawnExpression:
		collectUsedInExpression(e.Call, declared, seen, out)
	default:
	}
}

func maybeAddCapture(name string, declared map[string]struct{}, seen map[string]struct{}, out *[]string) {
	if isNonCapturableIdentifier(name) {
		return
	}
	if _, isLocal := declared[name]; isLocal {
		return
	}
	if _, already := seen[name]; already {
		return
	}
	seen[name] = struct{}{}
	*out = append(*out, name)
}
