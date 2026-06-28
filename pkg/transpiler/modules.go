package transpiler

import (
	"fmt"
	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/parser"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type transpileCtx struct {
	aliasToPrefix  map[string]string
	typeNamespaces map[string]struct{}
}

type moduleInfo struct {
	Prefix        string
	Path          string
	Program       *ast.Program
	AliasToPrefix map[string]string
	addedToOrder  bool
}

type unit struct {
	prefix    string
	ctx       transpileCtx
	globals   []*ast.VarStatement
	functions []*ast.FunctionLiteral
	types     []*ast.TypeStatement
	mainBody  []ast.Statement
}

func parseProgram(src string) (*ast.Program, []string) {
	l := lexer.New(src)
	p := parser.New(l)
	prog := p.ParseProgram()
	return prog, p.Errors()
}

func (t *Transpiler) resolveImportPath(importerDir, importPath string) string {
	// Bootstrap transpiler import resolver (rolling):
	// - Supports absolute/relative filesystem imports (legacy).
	// - Supports stdlib scheme imports:
	//     import math "std:math"
	//     import json "std/json"
	//     import common "std:linalg/common"
	//
	// The stdlib root is resolved by:
	// - OREN_STDLIB_ROOT, if set, else
	// - searching upward from importerDir for a `lib/std` directory.
	if filepath.IsAbs(importPath) {
		return filepath.Clean(importPath)
	}

	if strings.HasPrefix(importPath, "std:") || strings.HasPrefix(importPath, "std/") {
		rest := importPath
		if strings.HasPrefix(importPath, "std:") {
			rest = strings.TrimPrefix(importPath, "std:")
		} else {
			rest = strings.TrimPrefix(importPath, "std/")
		}
		rest = strings.TrimPrefix(rest, "/")
		if !strings.HasSuffix(rest, ".oren") {
			rest += ".oren"
		}

		root := os.Getenv("OREN_STDLIB_ROOT")
		if root == "" {
			root = findStdlibRoot(importerDir)
		}
		// If we still can't find it, keep a deterministic fallback so the error
		// message points at the intended path.
		if root == "" {
			root = filepath.Join(importerDir, "lib", "std")
		}
		return filepath.Clean(filepath.Join(root, rest))
	}

	return filepath.Clean(filepath.Join(importerDir, importPath))
}

func findStdlibRoot(fromDir string) string {
	dir := fromDir
	for {
		candidate := filepath.Join(dir, "lib", "std")
		if st, err := os.Stat(candidate); err == nil && st.IsDir() {
			// Lightweight sanity check: stdlib root should contain stdlib.oren in this repo.
			if _, err2 := os.Stat(filepath.Join(candidate, "stdlib.oren")); err2 == nil {
				return candidate
			}
			// Allow stdlib roots without stdlib.oren as long as the directory exists (install layouts may differ).
			return candidate
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func (t *Transpiler) loadModule(importerDir, importPath string) (*moduleInfo, error) {
	absPath := t.resolveImportPath(importerDir, importPath)

	for _, p := range t.moduleStack {
		if p == absPath {
			return nil, fmt.Errorf("cyclic import detected: %s", absPath)
		}
	}

	if mod, ok := t.moduleByPath[absPath]; ok {
		return mod, nil
	}

	src, err := ExpandIncludes(absPath)
	if err != nil {
		return nil, fmt.Errorf("read import %q: %w", absPath, err)
	}

	prog, errs := parseProgram(src)
	if len(errs) > 0 {
		return nil, fmt.Errorf("parse import %q: %s", absPath, errs[0])
	}

	mod := &moduleInfo{
		Prefix:        fmt.Sprintf("m%d", t.nextModuleID),
		Path:          absPath,
		Program:       prog,
		AliasToPrefix: map[string]string{},
	}
	t.nextModuleID++
	t.moduleByPath[absPath] = mod

	t.moduleStack = append(t.moduleStack, absPath)
	defer func() { t.moduleStack = t.moduleStack[:len(t.moduleStack)-1] }()

	// Load module dependencies first and record alias->prefix mapping.
	moduleDir := filepath.Dir(absPath)
	for _, stmt := range prog.Statements {
		imp, ok := stmt.(*ast.ImportStatement)
		if !ok {
			continue
		}
		keep, err := importAttrsKeep(imp.Attrs)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", absPath, err)
		}
		if !keep {
			continue
		}
		if _, exists := mod.AliasToPrefix[imp.Name.Value]; exists {
			return nil, fmt.Errorf("duplicate import alias %q in %s", imp.Name.Value, absPath)
		}
		dep, err := t.loadModule(moduleDir, imp.Path)
		if err != nil {
			return nil, err
		}
		mod.AliasToPrefix[imp.Name.Value] = dep.Prefix
	}

	// Prefix the module's own top-level symbols so they don't collide globally.
	mapping, err := collectTopLevelRenameMap(prog, mod.Prefix)
	if err != nil {
		return nil, fmt.Errorf("collect exports for %s: %w", absPath, err)
	}
	for alias := range mod.AliasToPrefix {
		if _, conflicts := mapping[alias]; conflicts {
			return nil, fmt.Errorf("import alias %q conflicts with top-level name in %s", alias, absPath)
		}
	}
	if err := renameProgramInPlace(prog, mapping); err != nil {
		return nil, fmt.Errorf("rename module %s: %w", absPath, err)
	}

	// Add to init order after dependencies.
	if !mod.addedToOrder {
		mod.addedToOrder = true
		t.moduleOrder = append(t.moduleOrder, mod)
	}
	return mod, nil
}

func bootstrapArch() string {
	switch runtime.GOARCH {
	case "amd64":
		return "x64"
	case "arm64":
		return "arm64"
	default:
		return runtime.GOARCH
	}
}

func bootstrapOS() string {
	switch runtime.GOOS {
	case "darwin":
		return "macos"
	default:
		return runtime.GOOS
	}
}

func importAttrsKeep(attrs []ast.Attribute) (bool, error) {
	keep := true
	for _, attr := range attrs {
		switch attr.Name {
		case "oren.cfg":
			ok, err := evalImportCfg(attr)
			if err != nil {
				return false, err
			}
			if !ok {
				keep = false
			}
		case "oren.debug":
			keep = false
		case "oren.release":
		default:
		}
	}
	return keep, nil
}

func evalImportCfg(attr ast.Attribute) (bool, error) {
	if len(attr.Args) == 0 {
		return false, fmt.Errorf("@cfg on import requires a selector")
	}
	arch := bootstrapArch()
	osName := bootstrapOS()
	platform := arch + "-" + osName
	if len(attr.Args) == 1 && attr.Args[0].Key == "" {
		s, ok := attr.Args[0].Value.(string)
		if !ok {
			return false, fmt.Errorf("@cfg positional import selector must be a string")
		}
		switch s {
		case arch, osName, platform:
			return true, nil
		case "debug":
			return false, nil
		case "release":
			return true, nil
		default:
			return false, nil
		}
	}
	for _, arg := range attr.Args {
		s, isString := arg.Value.(string)
		switch arg.Key {
		case "arch":
			if !isString {
				return false, fmt.Errorf("@cfg(arch=...) import selector must be a string")
			}
			if !csvContains(s, arch) {
				return false, nil
			}
		case "os":
			if !isString {
				return false, fmt.Errorf("@cfg(os=...) import selector must be a string")
			}
			if !csvContains(s, osName) {
				return false, nil
			}
		case "platform":
			if !isString {
				return false, fmt.Errorf("@cfg(platform=...) import selector must be a string")
			}
			if !csvContains(s, platform) {
				return false, nil
			}
		case "not_arch":
			if !isString {
				return false, fmt.Errorf("@cfg(not_arch=...) import selector must be a string")
			}
			if csvContains(s, arch) {
				return false, nil
			}
		case "not_os":
			if !isString {
				return false, fmt.Errorf("@cfg(not_os=...) import selector must be a string")
			}
			if csvContains(s, osName) {
				return false, nil
			}
		case "not_platform":
			if !isString {
				return false, fmt.Errorf("@cfg(not_platform=...) import selector must be a string")
			}
			if csvContains(s, platform) {
				return false, nil
			}
		case "debug":
			v, ok := arg.Value.(bool)
			if !ok {
				return false, fmt.Errorf("@cfg(debug=...) import selector must be a bool")
			}
			if v {
				return false, nil
			}
		default:
			return false, fmt.Errorf("@cfg import selector has unsupported key %q", arg.Key)
		}
	}
	return true, nil
}

func csvContains(csv, want string) bool {
	for _, part := range strings.Split(csv, ",") {
		if strings.TrimSpace(part) == want {
			return true
		}
	}
	return false
}

func collectTopLevelRenameMap(program *ast.Program, prefix string) (map[string]string, error) {
	mapping := map[string]string{}
	for _, stmt := range program.Statements {
		switch s := stmt.(type) {
		case *ast.VarStatement:
			mapping[s.Name.Value] = prefix + "_" + s.Name.Value
		case *ast.ExpressionStatement:
			if fn, ok := s.Expression.(*ast.FunctionLiteral); ok && fn.Name != "" {
				mapping[fn.Name] = prefix + "_" + fn.Name
			}
		case *ast.TypeStatement:
			mapping[s.Name.Value] = prefix + "_" + s.Name.Value
		}
	}
	return mapping, nil
}

type renameScope map[string]struct{}

func scopeHas(stack []renameScope, name string) bool {
	for i := len(stack) - 1; i >= 0; i-- {
		if _, ok := stack[i][name]; ok {
			return true
		}
	}
	return false
}

func scopeDeclare(stack []renameScope, name string) {
	if len(stack) == 0 {
		return
	}
	stack[len(stack)-1][name] = struct{}{}
}

func renameProgramInPlace(program *ast.Program, mapping map[string]string) error {
	stack := []renameScope{}
	for _, stmt := range program.Statements {
		if err := renameStatement(stmt, mapping, stack, true); err != nil {
			return err
		}
	}
	return nil
}

func renameStatement(stmt ast.Statement, mapping map[string]string, stack []renameScope, atTopLevel bool) error {
	switch s := stmt.(type) {
	case *ast.ImportStatement:
		return nil
	case *ast.TypeStatement:
		if atTopLevel && s.Name != nil {
			if nn, ok := mapping[s.Name.Value]; ok {
				s.Name.Value = nn
				s.Name.Token.Literal = nn
			}
		}
		return nil
	case *ast.VarStatement:
		if s.Name != nil {
			if atTopLevel {
				if nn, ok := mapping[s.Name.Value]; ok {
					s.Name.Value = nn
					s.Name.Token.Literal = nn
				}
			} else {
				scopeDeclare(stack, s.Name.Value)
			}
		}
		if s.Value != nil {
			return renameExpression(s.Value, mapping, stack)
		}
		return nil
	case *ast.AssignStatement:
		if s.Name != nil {
			if nn, ok := mapping[s.Name.Value]; ok && !scopeHas(stack, s.Name.Value) {
				s.Name.Value = nn
				s.Name.Token.Literal = nn
			}
		}
		if s.Value != nil {
			return renameExpression(s.Value, mapping, stack)
		}
		return nil
	case *ast.SetStatement:
		if s.Left != nil {
			if err := renameExpression(s.Left, mapping, stack); err != nil {
				return err
			}
		}
		if s.Value != nil {
			return renameExpression(s.Value, mapping, stack)
		}
		return nil
	case *ast.ReturnStatement:
		if s.ReturnValue != nil {
			return renameExpression(s.ReturnValue, mapping, stack)
		}
		return nil
	case *ast.ExpressionStatement:
		if fn, ok := s.Expression.(*ast.FunctionLiteral); ok && fn.Name != "" && atTopLevel {
			if nn, ok := mapping[fn.Name]; ok {
				fn.Name = nn
			}
		}
		if s.Expression != nil {
			return renameExpression(s.Expression, mapping, stack)
		}
		return nil
	case *ast.BlockStatement:
		next := append(stack, renameScope{})
		for _, st := range s.Statements {
			if err := renameStatement(st, mapping, next, false); err != nil {
				return err
			}
		}
		return nil
	case *ast.WhileStatement:
		if s.Condition != nil {
			if err := renameExpression(s.Condition, mapping, stack); err != nil {
				return err
			}
		}
		if s.Body != nil {
			return renameStatement(s.Body, mapping, stack, false)
		}
		return nil
	case *ast.ForStatement:
		next := append(stack, renameScope{})
		if s.Init != nil {
			if err := renameStatement(s.Init, mapping, next, false); err != nil {
				return err
			}
		}
		if s.Condition != nil {
			if err := renameExpression(s.Condition, mapping, next); err != nil {
				return err
			}
		}
		if s.Post != nil {
			if err := renameStatement(s.Post, mapping, next, false); err != nil {
				return err
			}
		}
		if s.Body != nil {
			return renameStatement(s.Body, mapping, next, false)
		}
		return nil
	case *ast.BreakStatement, *ast.ContinueStatement, *ast.FFIStatement:
		return nil
	default:
		return fmt.Errorf("rename: unsupported statement %T", stmt)
	}
}

func renameExpression(exp ast.Expression, mapping map[string]string, stack []renameScope) error {
	switch e := exp.(type) {
	case *ast.Identifier:
		if nn, ok := mapping[e.Value]; ok && !scopeHas(stack, e.Value) {
			e.Value = nn
			e.Token.Literal = nn
		}
		return nil
	case *ast.IntegerLiteral, *ast.FloatLiteral, *ast.StringLiteral, *ast.Boolean, *ast.NilLiteral:
		return nil
	case *ast.PrefixExpression:
		if e.Right != nil {
			return renameExpression(e.Right, mapping, stack)
		}
		return nil
	case *ast.InfixExpression:
		if e.Left != nil {
			if err := renameExpression(e.Left, mapping, stack); err != nil {
				return err
			}
		}
		if e.Right != nil {
			return renameExpression(e.Right, mapping, stack)
		}
		return nil
	case *ast.CallExpression:
		if e.Function != nil {
			if err := renameExpression(e.Function, mapping, stack); err != nil {
				return err
			}
		}
		for _, a := range e.Arguments {
			if err := renameExpression(a, mapping, stack); err != nil {
				return err
			}
		}
		return nil
	case *ast.MemberExpression:
		if e.Left != nil {
			return renameExpression(e.Left, mapping, stack)
		}
		return nil
	case *ast.ArrayLiteral:
		for _, el := range e.Elements {
			if err := renameExpression(el, mapping, stack); err != nil {
				return err
			}
		}
		return nil
	case *ast.IndexExpression:
		if e.Left != nil {
			if err := renameExpression(e.Left, mapping, stack); err != nil {
				return err
			}
		}
		if e.Index != nil {
			return renameExpression(e.Index, mapping, stack)
		}
		return nil
	case *ast.HashLiteral:
		for k, v := range e.Pairs {
			if err := renameExpression(k, mapping, stack); err != nil {
				return err
			}
			if err := renameExpression(v, mapping, stack); err != nil {
				return err
			}
		}
		return nil
	case *ast.IfExpression:
		if e.Condition != nil {
			if err := renameExpression(e.Condition, mapping, stack); err != nil {
				return err
			}
		}
		if e.Consequence != nil {
			if err := renameStatement(e.Consequence, mapping, stack, false); err != nil {
				return err
			}
		}
		if e.Alternative != nil {
			if err := renameStatement(e.Alternative, mapping, stack, false); err != nil {
				return err
			}
		}
		return nil
	case *ast.FunctionLiteral:
		next := append(stack, renameScope{})
		for _, p := range e.Parameters {
			if p != nil {
				scopeDeclare(next, p.Value)
			}
		}
		if e.Body != nil {
			return renameStatement(e.Body, mapping, next, false)
		}
		return nil
	case *ast.SpawnExpression:
		if e.Call != nil {
			return renameExpression(e.Call, mapping, stack)
		}
		return nil

	default:
		return fmt.Errorf("rename: unsupported expression %T", exp)
	}
}

func collectTypeNamespaces(program *ast.Program, out map[string]struct{}) {
	for _, stmt := range program.Statements {
		ts, ok := stmt.(*ast.TypeStatement)
		if !ok || ts.Name == nil {
			continue
		}
		out[ts.Name.Value] = struct{}{}
	}
}

func collectProgramParts(program *ast.Program) (globals []*ast.VarStatement, functions []*ast.FunctionLiteral, types []*ast.TypeStatement, mainBody []ast.Statement) {
	for _, stmt := range program.Statements {
		switch s := stmt.(type) {
		case *ast.ImportStatement:
			// compile-time only
		case *ast.TypeStatement:
			types = append(types, s)
		case *ast.VarStatement:
			globals = append(globals, s)
		case *ast.ExpressionStatement:
			if fn, ok := s.Expression.(*ast.FunctionLiteral); ok && fn.Name != "" {
				functions = append(functions, fn)
			} else {
				mainBody = append(mainBody, s)
			}
		default:
			mainBody = append(mainBody, s)
		}
	}
	return globals, functions, types, mainBody
}
