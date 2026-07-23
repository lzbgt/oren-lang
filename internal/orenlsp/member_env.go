package orenlsp

import (
	"oren/pkg/ast"
	"oren/pkg/lexer"
	"oren/pkg/parser"
)

type memberImportedProgram struct {
	Alias   string
	URI     string
	Program *ast.Program
}

func parseMemberImportedPrograms(importedDocs []documentSnapshot, aliasByURI map[string]string) []memberImportedProgram {
	imports := make([]memberImportedProgram, 0, len(importedDocs))
	for _, doc := range importedDocs {
		alias, ok := aliasByURI[doc.URI]
		if !ok {
			continue
		}
		imports = append(imports, memberImportedProgram{
			Alias:   alias,
			URI:     doc.URI,
			Program: parser.New(lexer.New(doc.Text)).ParseProgram(),
		})
	}
	return imports
}

func newMemberTypeEnv(program *ast.Program, uri string, imports []memberImportedProgram) memberTypeEnv {
	env := memberTypeEnv{
		Types:                         collectTypeInfos(program, uri, ""),
		FunctionFields:                map[string]map[string]string{},
		FunctionElementFields:         map[string]map[string]string{},
		FunctionMapValueFields:        map[string]map[string]string{},
		FunctionElementMapValueFields: map[string]map[string]string{},
		FunctionMapValueElementFields: map[string]map[string]string{},
	}
	for _, imported := range imports {
		for key, info := range collectTypeInfos(imported.Program, imported.URI, imported.Prefix()) {
			env.Types[key] = info
		}
	}
	return env
}

func (imported memberImportedProgram) Prefix() string {
	if imported.Alias == "" {
		return ""
	}
	return imported.Alias + "."
}

func addMemberFunctionReturnTypes(env *memberTypeEnv, program *ast.Program, prefix string, params map[string]map[string]string) {
	if env == nil {
		return
	}
	if env.Functions == nil {
		env.Functions = map[string]string{}
	}
	for key, typeName := range collectFunctionReturnTypes(program, prefix, env.Types, params) {
		env.Functions[key] = typeName
	}
}

func addImportedMemberFunctionReturnTypes(env *memberTypeEnv, imports []memberImportedProgram, params map[string]map[string]string) {
	for _, imported := range imports {
		addMemberFunctionReturnTypes(env, imported.Program, imported.Prefix(), params)
	}
}

func addMemberReturnFieldFacts(env *memberTypeEnv, program *ast.Program, prefix string) {
	if env == nil {
		return
	}
	factEnv := *env
	factEnv.Prefix = prefix
	for key, fields := range collectFunctionReturnFieldTypes(program, prefix, factEnv) {
		env.FunctionFields[key] = fields
	}
	for key, fields := range collectFunctionReturnElementFieldTypes(program, prefix, factEnv) {
		env.FunctionElementFields[key] = fields
	}
	for key, fields := range collectFunctionReturnMapValueFieldTypes(program, prefix, factEnv) {
		env.FunctionMapValueFields[key] = fields
	}
	for key, fields := range collectFunctionReturnElementMapValueFieldTypes(program, prefix, factEnv) {
		env.FunctionElementMapValueFields[key] = fields
	}
	for key, fields := range collectFunctionReturnMapValueElementFieldTypes(program, prefix, factEnv) {
		env.FunctionMapValueElementFields[key] = fields
	}
}

func addImportedMemberReturnFieldFacts(env *memberTypeEnv, imports []memberImportedProgram) {
	for _, imported := range imports {
		addMemberReturnFieldFacts(env, imported.Program, imported.Prefix())
	}
}

func collectMemberFunctionLiterals(program *ast.Program, imports []memberImportedProgram) map[string]*ast.FunctionLiteral {
	functions := collectNamedFunctionLiterals(program, "")
	for _, imported := range imports {
		for key, fn := range collectNamedFunctionLiterals(imported.Program, imported.Prefix()) {
			functions[key] = fn
		}
	}
	return functions
}
