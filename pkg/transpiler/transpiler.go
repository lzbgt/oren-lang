package transpiler

import (
	"fmt"
	"oren/pkg/ast"
	"path/filepath"
	"sort"
	"strings"
)

type Transpiler struct {
	lines            []string
	indentation      int
	indentStr        string
	definedFunctions map[string]struct{}
	tmpCounter       int

	// Internal C-emission temp counter (for __oren_* identifiers).
	cTmpCounter int

	lambdaCounter int
	lambdaByPtr   map[*ast.FunctionLiteral]string
	lambdas       []lambdaInfo

	baseDir      string
	ctx          transpileCtx
	nextModuleID int
	moduleByPath map[string]*moduleInfo
	moduleOrder  []*moduleInfo
	moduleStack  []string

	// Statement emission context (per-function).
	curFuncRootMark string
	curReturnVar    string
	curReturnLabel  string
	loopMarkStack   []string // stack of per-iteration mark vars for break/continue cleanup
}

func New() *Transpiler {
	return NewWithBaseDir(".")
}

func NewWithBaseDir(baseDir string) *Transpiler {
	return &Transpiler{
		lines:            []string{},
		indentation:      0,
		indentStr:        "",
		definedFunctions: make(map[string]struct{}),
		lambdaByPtr:      make(map[*ast.FunctionLiteral]string),
		baseDir:          baseDir,
		moduleByPath:     make(map[string]*moduleInfo),
	}
}

type lambdaInfo struct {
	name     string
	lit      *ast.FunctionLiteral
	captures []string // capture-by-value, in deterministic order
	ctx      transpileCtx
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
	t.indentStr = ""
	t.definedFunctions = make(map[string]struct{})
	t.lambdaCounter = 0
	t.lambdaByPtr = make(map[*ast.FunctionLiteral]string)
	t.lambdas = nil
	t.cTmpCounter = 0
	t.curFuncRootMark = ""
	t.curReturnVar = ""
	t.curReturnLabel = ""
	t.loopMarkStack = nil
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
			prefix: mod.Prefix,
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
		prefix: "root",
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

	// Collect all lambdas before emitting prototypes (C requires prototypes for calls in strict modes).
	// Pre-populate known function symbols so lambda capture analysis can avoid
	// generating invalid captures for raw C symbols (e.g. `oren_*`).
	for _, u := range units {
		for _, fn := range u.functions {
			t.definedFunctions[fn.Name] = struct{}{}
		}
		for _, ts := range u.types {
			ctorName := t.typeConstructorName(ts)
			t.definedFunctions[ctorName] = struct{}{}
		}
	}

	t.collectAllLambdas(units)

	// Emit function prototypes
	for _, u := range units {
		for _, fn := range u.functions {
			t.emit(t.functionSignature(fn) + ";")
			t.emit(t.functionWrapperSignature(fn.Name) + ";")
		}
		for _, ts := range u.types {
			ctorName := t.typeConstructorName(ts)
			t.emit(t.typeConstructorSignature(ts) + ";")
			t.emit(t.functionWrapperSignature(ctorName) + ";")
		}
	}
	for _, li := range t.lambdas {
		t.emit(t.lambdaWrapperSignature(li.name) + ";")
	}
	t.emit("")

	// Emit function bodies
	for _, li := range t.lambdas {
		if err := t.transpileLambda(li); err != nil {
			return "", err
		}
	}
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

	// Emit main (stack-safe):
	// Run the actual Oren entrypoint in a worker OS thread with a larger stack.
	// This avoids crashing on macOS/Linux default stacks for large recursive workloads
	// (notably: the self-hosted compiler's native backend codegen).
	t.emit("static int __oren_main_body(int argc, char **argv) {")
	t.indent()
	t.emit("oren_init(argc, argv);") // Initialize runtime with argv
	mainMark := t.newCTmp("main_mark_")
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", mainMark))

	for _, u := range units {
		for _, g := range u.globals {
			t.emit(fmt.Sprintf("oren_register_root(&%s);", g.Name.Value))
		}
	}

	for _, u := range units {
		t.ctx = u.ctx
		for _, g := range u.globals {
			stmtMark := t.newCTmp("main_stmt_mark_")
			t.emit("{")
			t.indent()
			t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", stmtMark))
			val, err := t.evalExprValue(g.Value)
			if err != nil {
				return "", err
			}
			t.emit(fmt.Sprintf("%s = %s;", g.Name.Value, val))
			t.emit(fmt.Sprintf("oren_roots_reset(%s);", stmtMark))
			t.unindent()
			t.emit("}")
		}
	}

	// Execute module top-level statements first (excluding the entry unit).
	if len(units) > 1 {
		for _, u := range units[:len(units)-1] {
			t.ctx = u.ctx
			for _, stmt := range u.mainBody {
				stmtMark := t.newCTmp("main_stmt_mark_")
				t.emit("{")
				t.indent()
				t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", stmtMark))
				if err := t.emitStatement(stmt); err != nil {
					return "", err
				}
				t.emit(fmt.Sprintf("oren_roots_reset(%s);", stmtMark))
				t.unindent()
				t.emit("}")
			}
		}
	}

	// Execute entry file top-level statements last.
	rootUnit := units[len(units)-1]
	t.ctx = rootUnit.ctx
	for _, stmt := range rootUnit.mainBody {
		stmtMark := t.newCTmp("main_stmt_mark_")
		t.emit("{")
		t.indent()
		t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", stmtMark))
		if err := t.emitStatement(stmt); err != nil {
			return "", err
		}
		t.emit(fmt.Sprintf("oren_roots_reset(%s);", stmtMark))
		t.unindent()
		t.emit("}")
	}

	t.emit(fmt.Sprintf("oren_roots_reset(%s);", mainMark))
	t.emit("oren_shutdown();")
	t.emit("return 0;")
	t.unindent()
	t.emit("}")
	t.emit("")
	t.emit("int main(int argc, char **argv) {")
	t.indent()
	t.emit("return oren_run_main_threaded(argc, argv, __oren_main_body);")
	t.unindent()
	t.emit("}")

	return strings.Join(t.lines, "\n"), nil
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

func (t *Transpiler) emit(s string) {
	t.lines = append(t.lines, t.indentStr+s)
}

func (t *Transpiler) indent() {
	t.indentation++
	t.indentStr += "    "
}

func (t *Transpiler) unindent() {
	t.indentation--
	if len(t.indentStr) >= 4 {
		t.indentStr = t.indentStr[:len(t.indentStr)-4]
	} else {
		t.indentStr = ""
	}
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

func (t *Transpiler) functionWrapperName(name string) string {
	// Reserved suffix for compiler-generated wrapper entrypoints used by first-class function values.
	// Note: module renaming ensures global uniqueness of `name` across imports.
	return name + "__oren_fnwrap"
}

func (t *Transpiler) functionWrapperSignature(name string) string {
	return fmt.Sprintf("OrenValue %s(void* env, int argc, OrenValue* argv)", t.functionWrapperName(name))
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

	// Precise root stack for this call frame.
	t.curFuncRootMark = t.newCTmp("root_mark_")
	t.curReturnVar = t.newCTmp("ret_")
	t.curReturnLabel = t.newCTmp("return_")
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", t.curFuncRootMark))
	t.emit(fmt.Sprintf("OrenValue %s = OREN_NIL;", t.curReturnVar))
	// Root parameters (taking address forces spills even under -O2).
	for _, f := range ts.Fields {
		if f != nil && f.Value != "" {
			t.emit(fmt.Sprintf("oren_roots_push(&%s);", f.Value))
		}
	}

	if len(ts.Fields) == 0 {
		t.emit(fmt.Sprintf("%s = oren_new_map(0);", t.curReturnVar))
	} else {
		args := []string{}
		for _, f := range ts.Fields {
			keyVar := t.materializeAndRoot(fmt.Sprintf("oren_string(\"%s\")", cEscapeString(f.Value)))
			args = append(args, keyVar, f.Value)
		}
		t.emit(fmt.Sprintf("%s = oren_new_map_from_pairs(%d, (OrenValue[]){%s});", t.curReturnVar, len(ts.Fields), strings.Join(args, ", ")))
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

	// Uniform-call wrapper for first-class function values (constructors are functions too).
	t.emit(t.functionWrapperSignature(ctorName) + " {")
	t.indent()
	t.emit("(void)env;")
	t.emit(fmt.Sprintf("if (argc != %d) { oren_panic(\"arity mismatch\"); }", len(ts.Fields)))
	args2 := []string{}
	for i := 0; i < len(ts.Fields); i++ {
		args2 = append(args2, fmt.Sprintf("argv[%d]", i))
	}
	t.emit(fmt.Sprintf("return %s(%s);", ctorName, strings.Join(args2, ", ")))
	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) transpileFunction(fn *ast.FunctionLiteral) error {
	t.emit(t.functionSignature(fn) + " {")
	t.indent()

	// Precise root stack for this call frame.
	t.curFuncRootMark = t.newCTmp("root_mark_")
	t.curReturnVar = t.newCTmp("ret_")
	t.curReturnLabel = t.newCTmp("return_")
	t.loopMarkStack = nil
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", t.curFuncRootMark))
	t.emit(fmt.Sprintf("OrenValue %s = OREN_NIL;", t.curReturnVar))
	// Root parameters (taking address forces spills even under -O2).
	for _, p := range fn.Parameters {
		if p != nil && p.Value != "" {
			t.emit(fmt.Sprintf("oren_roots_push(&%s);", p.Value))
		}
	}

	for _, stmt := range fn.Body.Statements {
		if err := t.emitStatement(stmt); err != nil {
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

	// Emit a uniform-call wrapper so this function can be stored in an OrenValue and invoked via oren_call_obj.
	t.emit(t.functionWrapperSignature(fn.Name) + " {")
	t.indent()
	t.emit("(void)env;")
	t.emit(fmt.Sprintf("if (argc != %d) { oren_panic(\"arity mismatch\"); }", len(fn.Parameters)))
	args2 := []string{}
	for i := 0; i < len(fn.Parameters); i++ {
		args2 = append(args2, fmt.Sprintf("argv[%d]", i))
	}
	t.emit(fmt.Sprintf("return %s(%s);", fn.Name, strings.Join(args2, ", ")))
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
			return fmt.Sprintf("oren_closure(%s, 0)", name), nil
		}
		args := make([]string, 0, len(captures))
		for _, capName := range captures {
			// Reuse identifier transpilation so captured function symbols become function values.
			capExpr, err := t.transpileExpression(&ast.Identifier{Value: capName})
			if err != nil {
				return "", err
			}
			args = append(args, capExpr)
		}
		return fmt.Sprintf("oren_closure_from_array(%s, %d, (OrenValue[]){%s})", name, len(args), strings.Join(args, ", ")), nil
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
		// First-class function values (C backend): if this identifier names a known user-defined function,
		// treat it as a value of type OREN_TYPE_FUNC (callable via oren_call_obj).
		//
		// Direct calls are handled in the CallExpression case to preserve the existing fast path.
		if _, ok := t.definedFunctions[e.Value]; ok {
			return fmt.Sprintf("oren_func(%s, NULL)", t.functionWrapperName(e.Value)), nil
		}
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
		fnExpr, err := t.transpileExpression(call.Function)
		if err != nil {
			return "", err
		}
		args := []string{}
		for _, a := range call.Arguments {
			arg, err := t.transpileExpression(a)
			if err != nil {
				return "", err
			}
			args = append(args, arg)
		}
		if len(args) == 0 {
			return fmt.Sprintf("oren_spawn_call_list(%s, oren_new_list(0))", fnExpr), nil
		}
		return fmt.Sprintf("oren_spawn_call_list(%s, oren_new_list_from_array(%d, (OrenValue[]){%s}))", fnExpr, len(args), strings.Join(args, ", ")), nil
	case *ast.CallExpression:
		// Decide whether this is a direct call (known function symbol) or an indirect call (OrenValue) via oren_call_obj.
		// We intentionally avoid transpiling the function expression first, because identifiers that name known functions
		// compile to `oren_func(...)` (a value) and would break direct calls.
		directSym := ""
		switch callee := e.Function.(type) {
		case *ast.Identifier:
			if _, exists := t.definedFunctions[callee.Value]; exists {
				directSym = callee.Value
			} else if strings.HasPrefix(callee.Value, "oren_") {
				directSym = callee.Value
			}
		case *ast.MemberExpression:
			if name, _, err := t.resolveNamespaceExpr(callee); err != nil {
				return "", err
			} else if name != "" {
				if _, exists := t.definedFunctions[name]; exists {
					directSym = name
				}
			}
		}

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

		// Low-level integer intrinsics used pervasively in the self-host compiler sources.
		//
		// The stage0 bootstrap transpiler does not represent first-class functions as OrenValue,
		// so these must lower to direct runtime calls rather than `oren_call_obj_argv(...)`.
		if fn == "iadd" {
			if len(args) != 2 {
				return "", fmt.Errorf("iadd expects 2 arguments")
			}
			// Use the runtime's deterministic i64 wrap semantics.
			return fmt.Sprintf("oren_add(%s, %s)", args[0], args[1]), nil
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
		if directSym != "" {
			useCallObj = false
			fn = directSym
		} else if _, exists := t.definedFunctions[fn]; exists {
			// Legacy fallback: if the transpiled function expression equals a known symbol, use direct call.
			useCallObj = false
		}

		if useCallObj {
			if len(args) == 0 {
				return fmt.Sprintf("oren_call_obj_argv(%s, 0, NULL)", fn), nil
			}
			return fmt.Sprintf("oren_call_obj_argv(%s, %d, (OrenValue[]){%s})", fn, len(args), strings.Join(args, ", ")), nil
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
		// oren_new_list_from_array(count, (OrenValue[]){items...})
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
		return fmt.Sprintf("oren_new_list_from_array(%d, (OrenValue[]){%s})", len(elements), strings.Join(elements, ", ")), nil

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
		// oren_new_map_from_pairs(count, (OrenValue[]){k1,v1,k2,v2,...})
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
		return fmt.Sprintf("oren_new_map_from_pairs(%d, (OrenValue[]){%s})", len(e.Pairs), strings.Join(args, ", ")), nil

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

// --- Root-safe statement/expression emission (rolling) ---
//
// The stage2 self-hosting compiler runs with auto-GC enabled and can execute in multiple
// OS threads (parallel module parsing). Relying on conservative stack/register scanning
// for correctness is fragile under -O2 and argument passing conventions.
//
// This emitter:
// - forces deterministic evaluation order
// - materializes pointer-backed intermediates into rooted temporaries
// - uses the runtime's per-thread root stack (oren_roots_mark/push/reset)

func (t *Transpiler) newCTmp(prefix string) string {
	n := t.cTmpCounter
	t.cTmpCounter++
	// Keep these names out of user namespace.
	return fmt.Sprintf("__oren_%s%d", prefix, n)
}

func (t *Transpiler) pushLoopMark(markVar string) {
	t.loopMarkStack = append(t.loopMarkStack, markVar)
}

func (t *Transpiler) popLoopMark() {
	if len(t.loopMarkStack) == 0 {
		return
	}
	t.loopMarkStack = t.loopMarkStack[:len(t.loopMarkStack)-1]
}

func (t *Transpiler) curLoopMark() (string, bool) {
	if len(t.loopMarkStack) == 0 {
		return "", false
	}
	return t.loopMarkStack[len(t.loopMarkStack)-1], true
}

func (t *Transpiler) materializeAndRoot(expr string) string {
	tmp := t.newCTmp("tmp_")
	t.emit(fmt.Sprintf("OrenValue %s = %s;", tmp, expr))
	// Root temporaries by value to avoid forcing every temp into a distinct stack slot.
	// (Taking the address of every temp can explode stack frame size in large functions,
	// observed as stack overflows in the self-hosted compiler codegen passes.)
	t.emit(fmt.Sprintf("oren_roots_push_value(%s);", tmp))
	return tmp
}

func (t *Transpiler) emitScopedBlock(stmts []ast.Statement) error {
	mark := t.newCTmp("mark_")
	t.emit("{")
	t.indent()
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", mark))
	for _, st := range stmts {
		if err := t.emitStatement(st); err != nil {
			return err
		}
	}
	t.emit(fmt.Sprintf("oren_roots_reset(%s);", mark))
	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) emitIfStatementRooted(ie *ast.IfExpression) error {
	if ie == nil {
		return nil
	}
	mark := t.newCTmp("if_mark_")
	t.emit("{")
	t.indent()
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", mark))
	cond, err := t.evalExprValue(ie.Condition)
	if err != nil {
		return err
	}
	t.emit(fmt.Sprintf("if (oren_is_truthy(%s)) {", cond))
	t.indent()
	for _, s := range ie.Consequence.Statements {
		if err := t.emitStatement(s); err != nil {
			return err
		}
	}
	t.unindent()
	if ie.Alternative != nil {
		t.emit("} else {")
		t.indent()
		for _, s := range ie.Alternative.Statements {
			if err := t.emitStatement(s); err != nil {
				return err
			}
		}
		t.unindent()
		t.emit("}")
	} else {
		t.emit("}")
	}
	t.emit(fmt.Sprintf("oren_roots_reset(%s);", mark))
	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) emitWhileStatement(ws *ast.WhileStatement) error {
	if ws == nil {
		return nil
	}
	iterMark := t.newCTmp("while_mark_")
	t.emit("while (1) {")
	t.indent()
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", iterMark))
	t.pushLoopMark(iterMark)

	cond, err := t.evalExprValue(ws.Condition)
	if err != nil {
		return err
	}
	t.emit(fmt.Sprintf("if (!oren_is_truthy(%s)) { oren_roots_reset(%s); break; }", cond, iterMark))
	t.emit("oren_gc_safepoint();")
	for _, st := range ws.Body.Statements {
		if err := t.emitStatement(st); err != nil {
			return err
		}
	}
	t.emit(fmt.Sprintf("oren_roots_reset(%s);", iterMark))
	t.popLoopMark()
	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) emitForStatement(fs *ast.ForStatement) error {
	if fs == nil {
		return nil
	}
	outerMark := t.newCTmp("for_mark_")
	t.emit("{")
	t.indent()
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", outerMark))

	// init (once)
	if fs.Init != nil {
		if err := t.emitStatement(fs.Init); err != nil {
			return err
		}
	}

	iterMark := t.newCTmp("for_iter_mark_")
	t.emit("while (1) {")
	t.indent()
	t.emit(fmt.Sprintf("size_t %s = oren_roots_mark();", iterMark))
	t.pushLoopMark(iterMark)

	// cond
	if fs.Condition != nil {
		cond, err := t.evalExprValue(fs.Condition)
		if err != nil {
			return err
		}
		t.emit(fmt.Sprintf("if (!oren_is_truthy(%s)) { oren_roots_reset(%s); break; }", cond, iterMark))
	}

	t.emit("oren_gc_safepoint();")
	for _, st := range fs.Body.Statements {
		if err := t.emitStatement(st); err != nil {
			return err
		}
	}

	// post
	if fs.Post != nil {
		if err := t.emitStatement(fs.Post); err != nil {
			return err
		}
	}

	t.emit(fmt.Sprintf("oren_roots_reset(%s);", iterMark))
	t.popLoopMark()
	t.unindent()
	t.emit("}")

	t.emit(fmt.Sprintf("oren_roots_reset(%s);", outerMark))
	t.unindent()
	t.emit("}")
	return nil
}

func (t *Transpiler) emitStatement(stmt ast.Statement) error {
	if stmt == nil {
		return nil
	}
	switch s := stmt.(type) {
	case *ast.ImportStatement, *ast.TypeStatement:
		return fmt.Errorf("unsupported statement in this position: %T", stmt)
	case *ast.VarStatement:
		name := ""
		if s.Name != nil {
			name = s.Name.Value
			if name == "" {
				name = s.Name.Token.Literal
			}
		}
		if name == "" {
			name = fmt.Sprintf("_v%d", t.tmpCounter)
			t.tmpCounter++
		}
		val, err := t.evalExprValue(s.Value)
		if err != nil {
			return err
		}
		t.emit(fmt.Sprintf("OrenValue %s = %s;", name, val))
		t.emit(fmt.Sprintf("oren_roots_push(&%s);", name))
		return nil
	case *ast.AssignStatement:
		val, err := t.evalExprValue(s.Value)
		if err != nil {
			return err
		}
		t.emit(fmt.Sprintf("%s = %s;", s.Name.Value, val))
		return nil
	case *ast.SetStatement:
		val, err := t.evalExprValue(s.Value)
		if err != nil {
			return err
		}
		switch left := s.Left.(type) {
		case *ast.Identifier:
			t.emit(fmt.Sprintf("%s = %s;", left.Value, val))
			return nil
		case *ast.IndexExpression:
			container, err := t.evalExprValue(left.Left)
			if err != nil {
				return err
			}
			index, err := t.evalExprValue(left.Index)
			if err != nil {
				return err
			}
			t.emit(fmt.Sprintf("oren_index_set(%s, %s, %s);", container, index, val))
			return nil
		case *ast.MemberExpression:
			if name, _, err := t.resolveNamespaceExpr(left); err != nil {
				return err
			} else if name != "" {
				if _, isFn := t.definedFunctions[name]; isFn {
					return fmt.Errorf("cannot assign to function %s", name)
				}
				t.emit(fmt.Sprintf("%s = %s;", name, val))
				return nil
			}
			obj, err := t.evalExprValue(left.Left)
			if err != nil {
				return err
			}
			t.emit(fmt.Sprintf("oren_set_attr(%s, \"%s\", %s);", obj, left.Property.Value, val))
			return nil
		default:
			return fmt.Errorf("unsupported assignment target: %T", s.Left)
		}
	case *ast.ReturnStatement:
		if t.curReturnLabel == "" || t.curReturnVar == "" {
			return fmt.Errorf("return outside function context")
		}
		val, err := t.evalExprValue(s.ReturnValue)
		if err != nil {
			return err
		}
		t.emit(fmt.Sprintf("%s = %s;", t.curReturnVar, val))
		t.emit(fmt.Sprintf("goto %s;", t.curReturnLabel))
		return nil
	case *ast.ExpressionStatement:
		if ifExpr, ok := s.Expression.(*ast.IfExpression); ok {
			return t.emitIfStatementRooted(ifExpr)
		}
		_, err := t.evalExprValue(s.Expression)
		return err
	case *ast.BlockStatement:
		return t.emitScopedBlock(s.Statements)
	case *ast.WhileStatement:
		return t.emitWhileStatement(s)
	case *ast.ForStatement:
		return t.emitForStatement(s)
	case *ast.BreakStatement:
		m, ok := t.curLoopMark()
		if !ok {
			return fmt.Errorf("break outside loop")
		}
		t.emit(fmt.Sprintf("oren_roots_reset(%s);", m))
		t.emit("break;")
		return nil
	case *ast.ContinueStatement:
		m, ok := t.curLoopMark()
		if !ok {
			return fmt.Errorf("continue outside loop")
		}
		t.emit(fmt.Sprintf("oren_roots_reset(%s);", m))
		t.emit("continue;")
		return nil
	case *ast.FFIStatement:
		t.emit("// FFI declaration ignored in C emission (assumed linked)")
		return nil
	default:
		return fmt.Errorf("unknown statement: %T", stmt)
	}
}

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

// Need to update transpileStatement to call transpileIfStatement for ExpressionStatement that holds IfExpression
// This logic needs to be cleaner.
// In `transpileStatement`, we check `*ast.ExpressionStatement`.
// Inside that case:
/*
   if ifExpr, ok := s.Expression.(*ast.IfExpression); ok {
       return t.transpileIfStatement(ifExpr)
   }
*/
