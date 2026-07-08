package orenlsp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServerInitializeAndShutdown(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{}})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "id": 2, "method": "shutdown"})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	if len(msgs) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(msgs), msgs)
	}
	if msgs[0]["id"].(float64) != 1 {
		t.Fatalf("initialize id mismatch: %#v", msgs[0])
	}
	result := msgs[0]["result"].(map[string]any)
	caps := result["capabilities"].(map[string]any)
	if _, ok := caps["textDocumentSync"].(map[string]any); !ok {
		t.Fatalf("missing textDocumentSync capability: %#v", caps)
	}
	if _, ok := caps["completionProvider"].(map[string]any); !ok {
		t.Fatalf("missing completionProvider capability: %#v", caps)
	}
	if caps["documentSymbolProvider"] != true {
		t.Fatalf("missing documentSymbolProvider capability: %#v", caps)
	}
	if caps["definitionProvider"] != true {
		t.Fatalf("missing definitionProvider capability: %#v", caps)
	}
	if caps["hoverProvider"] != true {
		t.Fatalf("missing hoverProvider capability: %#v", caps)
	}
	if caps["referencesProvider"] != true {
		t.Fatalf("missing referencesProvider capability: %#v", caps)
	}
	renameProvider, ok := caps["renameProvider"].(map[string]any)
	if !ok || renameProvider["prepareProvider"] != true {
		t.Fatalf("missing renameProvider capability: %#v", caps)
	}
	semanticProvider, ok := caps["semanticTokensProvider"].(map[string]any)
	if !ok {
		t.Fatalf("missing semanticTokensProvider capability: %#v", caps)
	}
	legend := semanticProvider["legend"].(map[string]any)
	assertStringList(t, legend["tokenTypes"].([]any), semanticTokenTypes)
	assertStringList(t, legend["tokenModifiers"].([]any), semanticTokenModifiers)
}

func TestServerPublishesDiagnosticsOnDidOpenAndDidChange(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{
				"uri":  "file:///bad.oren",
				"text": "fn main() {\n  print(\"ok\")\n",
			},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didChange",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///bad.oren"},
			"contentChanges": []map[string]any{{
				"text": "fn main() {\n  print(\"ok\")\n}\n",
			}},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	if len(msgs) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(msgs), msgs)
	}
	first := diagnosticsFromMessage(t, msgs[0])
	if len(first) != 1 {
		t.Fatalf("first diagnostics mismatch: %#v", first)
	}
	firstDiag := first[0].(map[string]any)
	if !strings.Contains(firstDiag["message"].(string), "unclosed delimiter") {
		t.Fatalf("first diagnostics mismatch: %#v", first)
	}
	second := diagnosticsFromMessage(t, msgs[1])
	if len(second) != 0 {
		t.Fatalf("second diagnostics=%#v want none", second)
	}
}

func TestDiagnoseIgnoresLineCommentDelimiters(t *testing.T) {
	got := diagnose("fn main() {\n  // ignored }\n}\n")
	if len(got) != 0 {
		t.Fatalf("diagnostics=%#v want none", got)
	}
}

func TestDiagnoseIncludesParserErrors(t *testing.T) {
	got := diagnose("fn main( { return 1 }\n")
	parserDiags := diagnosticsWithSource(got, "oren-parser")
	if len(parserDiags) == 0 {
		t.Fatalf("diagnostics=%#v missing parser diagnostics", got)
	}
	if !strings.Contains(parserDiags[0].Message, "expected next token") {
		t.Fatalf("parser diagnostic=%#v missing parser message", parserDiags[0])
	}
	if parserDiags[0].Range.Start.Line != 0 || parserDiags[0].Range.Start.Character < 0 {
		t.Fatalf("parser diagnostic range=%#v", parserDiags[0].Range)
	}
}

func TestDiagnoseValidProgramHasNoParserErrors(t *testing.T) {
	got := diagnose("fn main() { return 1 }\n")
	if len(got) != 0 {
		t.Fatalf("diagnostics=%#v want none", got)
	}
}

func TestServerCompletionAndDocumentSymbols(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"import math \"std:math\"",
		"struct Vec2 { x, y }",
		"class Runner {}",
		"var answer = 42",
		"fn compute() { return answer }",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      7,
		"method":  "textDocument/documentSymbol",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      8,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren"},
			"position":     map[string]any{"line": 4, "character": 2},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	symbolResp := messageByID(t, msgs, 7)
	symbols := symbolResp["result"].([]any)
	assertLabels(t, symbols, []string{"math", "Vec2", "Runner", "answer", "compute"})
	if symbols[0].(map[string]any)["kind"].(float64) != 2 {
		t.Fatalf("first symbol=%#v want module kind", symbols[0])
	}
	completionResp := messageByID(t, msgs, 8)
	items := completionResp["result"].([]any)
	if !hasCompletion(items, "compute", 3) || !hasCompletion(items, "answer", 6) || !hasCompletion(items, "return", 14) {
		t.Fatalf("completion items missing expected entries: %#v", items)
	}
}

func TestServerCompletionUsesTypedMembers(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"var p = Point(1, 2)",
		"var value = p.",
		"var exact = p.x",
		"",
	}, "\n")
	uri := "file:///member-completion.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      9,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 14},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      10,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 3, "character": 15},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 9)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) {
		t.Fatalf("member completion items missing fields: %#v", items)
	}
	if hasCompletion(items, "return", 14) {
		t.Fatalf("member completion included global keyword: %#v", items)
	}
	filtered := messageByID(t, msgs, 10)["result"].([]any)
	if !hasCompletion(filtered, "x", 5) || hasCompletion(filtered, "y", 5) {
		t.Fatalf("filtered member completion mismatch: %#v", filtered)
	}
}

func TestServerCompletionUsesImportedModuleAlias(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := strings.Join([]string{
		"struct Point { x, y }",
		"fn make_point() { return Point(1, 2) }",
		"var origin = Point(0, 0)",
		"",
	}, "\n")
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("write shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainURI := fileURIFromPath(mainPath)
	mainLines := []string{
		`import shapes "shapes.oren"`,
		"var value = shapes.",
		"var filtered = shapes.ma",
		"",
	}
	text := strings.Join(mainLines, "\n")

	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      11,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 1, "character": len(mainLines[1])},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      12,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": len(mainLines[2])},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 11)["result"].([]any)
	if !hasCompletion(items, "Point", 22) || !hasCompletion(items, "make_point", 3) || !hasCompletion(items, "origin", 6) {
		t.Fatalf("module completion items missing imported symbols: %#v", items)
	}
	if hasCompletion(items, "return", 14) {
		t.Fatalf("module completion included global keyword: %#v", items)
	}
	filtered := messageByID(t, msgs, 12)["result"].([]any)
	if !hasCompletion(filtered, "make_point", 3) || hasCompletion(filtered, "Point", 22) || hasCompletion(filtered, "origin", 6) {
		t.Fatalf("filtered module completion mismatch: %#v", filtered)
	}
}

func TestServerDidCloseDropsDocumentSymbols(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren", "text": "fn stale() {}\n"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didClose",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      9,
		"method":  "textDocument/documentSymbol",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	symbols := messageByID(t, msgs, 9)["result"].([]any)
	if len(symbols) != 0 {
		t.Fatalf("symbols after close=%#v want none", symbols)
	}
}

func TestServerDefinitionFindsLocalSymbol(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"import math \"std:math\"",
		"var answer = 42",
		"fn compute() {",
		"  return answer",
		"}",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///definition.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      10,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///definition.oren"},
			"position":     map[string]any{"line": 3, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      11,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///definition.oren"},
			"position":     map[string]any{"line": 3, "character": 15},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      12,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///definition.oren"},
			"position":     map[string]any{"line": 4, "character": 0},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	defs := messageByID(t, msgs, 10)["result"].([]any)
	assertDefinition(t, defs, "file:///definition.oren", 1, 4, 10)
	defsAtEnd := messageByID(t, msgs, 11)["result"].([]any)
	assertDefinition(t, defsAtEnd, "file:///definition.oren", 1, 4, 10)
	empty := messageByID(t, msgs, 12)["result"].([]any)
	if len(empty) != 0 {
		t.Fatalf("definition for non-word=%#v want none", empty)
	}
}

func TestServerDefinitionFindsOpenDocumentSymbol(t *testing.T) {
	var in bytes.Buffer
	mainText := strings.Join([]string{
		"import helper \"helper.oren\"",
		"fn main() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	helperText := strings.Join([]string{
		"var helper_value = 7",
		"fn helper_fn() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///main.oren", "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///helper.oren", "text": helperText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      13,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///main.oren"},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	defs := messageByID(t, msgs, 13)["result"].([]any)
	assertDefinition(t, defs, "file:///helper.oren", 0, 4, 16)
}

func TestServerDefinitionPrefersLocalOpenDocumentSymbol(t *testing.T) {
	var in bytes.Buffer
	mainText := strings.Join([]string{
		"var helper_value = 1",
		"fn main() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	helperText := "var helper_value = 7\n"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///main.oren", "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///helper.oren", "text": helperText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      14,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///main.oren"},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	defs := messageByID(t, msgs, 14)["result"].([]any)
	assertDefinition(t, defs, "file:///main.oren", 0, 4, 16)
}

func TestServerDefinitionFindsUnopenedImportedFileSymbol(t *testing.T) {
	tmp := t.TempDir()
	helperPath := filepath.Join(tmp, "modules", "helper.oren")
	if err := os.MkdirAll(filepath.Dir(helperPath), 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(helperPath, []byte("var helper_value = 7\n"), 0o644); err != nil {
		t.Fatalf("WriteFile helper: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import helper \"modules/helper.oren\"",
		"fn main() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(mainPath, []byte(mainText), 0o644); err != nil {
		t.Fatalf("WriteFile main: %v", err)
	}

	var in bytes.Buffer
	mainURI := fileURIFromPath(mainPath)
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      15,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	defs := messageByID(t, msgs, 15)["result"].([]any)
	assertDefinition(t, defs, fileURIFromPath(helperPath), 0, 4, 16)
}

func TestServerDefinitionFindsTransitiveImportedFileSymbol(t *testing.T) {
	tmp := t.TempDir()
	moduleDir := filepath.Join(tmp, "modules")
	if err := os.MkdirAll(moduleDir, 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	leafPath := filepath.Join(moduleDir, "leaf.oren")
	if err := os.WriteFile(leafPath, []byte("var leaf_value = 9\n"), 0o644); err != nil {
		t.Fatalf("WriteFile leaf: %v", err)
	}
	midPath := filepath.Join(moduleDir, "mid.oren")
	midText := strings.Join([]string{
		"import leaf \"leaf.oren\"",
		"fn mid() {",
		"  return leaf_value",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(midPath, []byte(midText), 0o644); err != nil {
		t.Fatalf("WriteFile mid: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import mid \"modules/mid.oren\"",
		"fn main() {",
		"  return leaf_value",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(mainPath, []byte(mainText), 0o644); err != nil {
		t.Fatalf("WriteFile main: %v", err)
	}

	var in bytes.Buffer
	mainURI := fileURIFromPath(mainPath)
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      16,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	defs := messageByID(t, msgs, 16)["result"].([]any)
	assertDefinition(t, defs, fileURIFromPath(leafPath), 0, 4, 14)
}

func TestImportedDocumentSnapshotsSkipsImportCycles(t *testing.T) {
	tmp := t.TempDir()
	mainPath := filepath.Join(tmp, "main.oren")
	helperPath := filepath.Join(tmp, "helper.oren")
	mainText := "import helper \"helper.oren\"\nfn main() { return helper_value }\n"
	helperText := "import main \"main.oren\"\nvar helper_value = 3\n"
	if err := os.WriteFile(mainPath, []byte(mainText), 0o644); err != nil {
		t.Fatalf("WriteFile main: %v", err)
	}
	if err := os.WriteFile(helperPath, []byte(helperText), 0o644); err != nil {
		t.Fatalf("WriteFile helper: %v", err)
	}
	s := NewServer(strings.NewReader(""), &bytes.Buffer{})
	docs := s.importedDocumentSnapshots(fileURIFromPath(mainPath), mainText)
	if len(docs) != 1 {
		t.Fatalf("imported docs=%#v want only helper", docs)
	}
	if docs[0].URI != fileURIFromPath(helperPath) {
		t.Fatalf("imported doc uri=%q want helper", docs[0].URI)
	}
}

func TestResolveImportPathStdSpec(t *testing.T) {
	got, ok := resolveImportPath("std:net/http.oren", "/tmp/project/app", "/tmp/project")
	if !ok {
		t.Fatalf("resolveImportPath returned !ok")
	}
	want := filepath.Join("/tmp/project", "lib", "std", "net", "http.oren")
	if got != want {
		t.Fatalf("path=%q want %q", got, want)
	}
}

func TestServerHoverAndReferencesUseWorkspaceSymbols(t *testing.T) {
	tmp := t.TempDir()
	helperPath := filepath.Join(tmp, "modules", "helper.oren")
	if err := os.MkdirAll(filepath.Dir(helperPath), 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	helperText := strings.Join([]string{
		"var helper_value = 7",
		"fn helper_fn() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(helperPath, []byte(helperText), 0o644); err != nil {
		t.Fatalf("WriteFile helper: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import helper \"modules/helper.oren\"",
		"fn main() {",
		"  return helper_value + helper_value",
		"}",
		"",
	}, "\n")
	peerText := strings.Join([]string{
		"fn peer() {",
		"  return helper_value",
		"}",
		"",
	}, "\n")
	mainURI := fileURIFromPath(mainPath)
	peerURI := fileURIFromPath(filepath.Join(tmp, "peer.oren"))
	helperURI := fileURIFromPath(helperPath)

	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": peerURI, "text": peerText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      16,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      17,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      18,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
			"context":      map[string]any{"includeDeclaration": false},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	hover := messageByID(t, msgs, 16)["result"].(map[string]any)
	contents := hover["contents"].(map[string]any)
	value := contents["value"].(string)
	if !strings.Contains(value, "variable helper_value") || !strings.Contains(value, helperURI) {
		t.Fatalf("hover value=%q missing symbol or URI", value)
	}

	withDecl := messageByID(t, msgs, 17)["result"].([]any)
	assertLocations(t, withDecl, []location{
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 24}, End: position{Line: 2, Character: 36}}},
		{URI: peerURI, Range: diagnosticRange{Start: position{Line: 1, Character: 9}, End: position{Line: 1, Character: 21}}},
		{URI: helperURI, Range: diagnosticRange{Start: position{Line: 0, Character: 4}, End: position{Line: 0, Character: 16}}},
		{URI: helperURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
	})

	withoutDecl := messageByID(t, msgs, 18)["result"].([]any)
	assertLocations(t, withoutDecl, []location{
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 24}, End: position{Line: 2, Character: 36}}},
		{URI: peerURI, Range: diagnosticRange{Start: position{Line: 1, Character: 9}, End: position{Line: 1, Character: 21}}},
		{URI: helperURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
	})
}

func TestServerNavigationUsesScopedParameters(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"fn outer(x) {",
		"  fn inner(x) {",
		"    return x",
		"  }",
		"  return x",
		"}",
		"",
	}, "\n")
	uri := "file:///scoped-params.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      19,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      20,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 4, "character": 9},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      21,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      22,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 9},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      23,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 1, "character": 11},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 19)["result"].([]any), uri, 1, 11, 12)
	assertDefinition(t, messageByID(t, msgs, 20)["result"].([]any), uri, 0, 9, 10)

	hover := messageByID(t, msgs, 21)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "parameter x") || !strings.Contains(value, uri) {
		t.Fatalf("hover value=%q missing parameter detail", value)
	}

	assertLocations(t, messageByID(t, msgs, 22)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 9}, End: position{Line: 0, Character: 10}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 4, Character: 9}, End: position{Line: 4, Character: 10}}},
	})
	assertLocations(t, messageByID(t, msgs, 23)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 1, Character: 11}, End: position{Line: 1, Character: 12}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 2, Character: 11}, End: position{Line: 2, Character: 12}}},
	})
}

func TestServerNavigationUsesConstructorInferredFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"var p = Point(1, 2)",
		"var q = Point(3, 4)",
		"var u = 0",
		"fn main() {",
		"  return p.x + q.x + p.y + u.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-members.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      24,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      25,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 17},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      26,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      27,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 23},
			"context":      map[string]any{"includeDeclaration": false},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      28,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 29},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 24)["result"].([]any), uri, 0, 15, 16)

	hover := messageByID(t, msgs, 25)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "property x") || !strings.Contains(value, "Point property") {
		t.Fatalf("hover value=%q missing field detail", value)
	}

	assertLocations(t, messageByID(t, msgs, 26)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 5, Character: 11}, End: position{Line: 5, Character: 12}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 5, Character: 17}, End: position{Line: 5, Character: 18}}},
	})
	assertLocations(t, messageByID(t, msgs, 27)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 5, Character: 23}, End: position{Line: 5, Character: 24}}},
	})
	defs := messageByID(t, msgs, 28)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("untyped member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesAliasedConstructorFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"var p = Point(1, 2)",
		"var alias = p",
		"var reset = p",
		"reset = 0",
		"fn main() {",
		"  return alias.x + reset.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-aliases.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      29,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": 15},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      30,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      31,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": 25},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 29)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 30)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 6, Character: 15}, End: position{Line: 6, Character: 16}}},
	})
	defs := messageByID(t, msgs, 31)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("reset member definition=%#v want none after unknown assignment", defs)
	}
}

func TestServerNavigationUsesAliasedNestedMemberFields(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf, label }",
		"struct Outer { inner }",
		"var outer = Outer(Inner(Leaf(1, 2), \"a\"))",
		"var inner = outer.inner",
		"fn main() {",
		"  var comp = inner.leaf.",
		"  return inner.leaf.y",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-nested-alias.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      70,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": len([]rune(lines[6]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      71,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": strings.Index(lines[7], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      72,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": strings.Index(lines[0], "y")},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 70)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "label", 5) {
		t.Fatalf("aliased nested member completion mismatch: %#v", items)
	}
	leafY := float64(strings.Index(lines[0], "y"))
	assertDefinition(t, messageByID(t, msgs, 71)["result"].([]any), uri, 0, leafY, leafY+1)
	assertLocations(t, messageByID(t, msgs, 72)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: int(leafY)}, End: position{Line: 0, Character: int(leafY) + 1}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 7, Character: strings.Index(lines[7], ".y") + 1}, End: position{Line: 7, Character: strings.Index(lines[7], ".y") + 2}}},
	})
}

func TestServerNavigationUsesFactoryReturnFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"fn make_point() {",
		"  var p = Point(1, 2)",
		"  return p",
		"}",
		"var p = make_point()",
		"fn main() {",
		"  return p.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-factory.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      32,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      33,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 32)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 33)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 7, Character: 11}, End: position{Line: 7, Character: 12}}},
	})
}

func TestServerNavigationUsesConditionalFactoryReturnFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"struct Other { x }",
		"fn choose_point(flag) {",
		"  if flag {",
		"    return Point(1, 2)",
		"  } else {",
		"    var p = Point(3, 4)",
		"    return p",
		"  }",
		"}",
		"fn choose_conflict(flag) {",
		"  if flag {",
		"    return Point(1, 2)",
		"  } else {",
		"    return Other(9)",
		"  }",
		"}",
		"var p = choose_point(true)",
		"var c = choose_conflict(true)",
		"fn main() {",
		"  return p.x + c.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-conditional-return.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      67,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 20, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      68,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      69,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 20, "character": 17},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 67)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 68)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 20, Character: 11}, End: position{Line: 20, Character: 12}}},
	})
	defs := messageByID(t, msgs, 69)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting conditional return member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesCallSiteParameterFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"struct Other { x }",
		"fn use_point(p) {",
		"  return p.x",
		"}",
		"fn use_conflict(v) {",
		"  return v.x",
		"}",
		"var p = Point(1, 2)",
		"var q = Point(3, 4)",
		"var o = Other(9)",
		"var a = use_point(p)",
		"var b = use_point(q)",
		"var c = use_conflict(p)",
		"var d = use_conflict(o)",
		"",
	}, "\n")
	uri := "file:///typed-member-parameters.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      34,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      35,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      36,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 34)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 35)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 3, Character: 11}, End: position{Line: 3, Character: 12}}},
	})
	defs := messageByID(t, msgs, 36)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting parameter member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesCallSiteParameterReturnFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"fn identity(p) {",
		"  return p",
		"}",
		"var p = Point(1, 2)",
		"var q = identity(p)",
		"fn main() {",
		"  return q.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-param-return.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      37,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      38,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 37)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 38)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 7, Character: 11}, End: position{Line: 7, Character: 12}}},
	})
}

func TestServerNavigationUsesImportedConstructorFields(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := "struct Point { x, y }\n"
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"var p = shapes.Point(1, 2)",
		"var q = shapes.Point(3, 4)",
		"fn main() {",
		"  return p.x + q.x + p.y",
		"}",
		"",
	}, "\n")
	mainURI := fileURIFromPath(mainPath)
	shapesURI := fileURIFromPath(shapesPath)

	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      39,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      40,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 17},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      41,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 11},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      42,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 23},
			"context":      map[string]any{"includeDeclaration": false},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 39)["result"].([]any), shapesURI, 0, 15, 16)

	hover := messageByID(t, msgs, 40)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "property x") || !strings.Contains(value, "shapes.Point property") || !strings.Contains(value, shapesURI) {
		t.Fatalf("hover value=%q missing imported field detail", value)
	}

	assertLocations(t, messageByID(t, msgs, 41)["result"].([]any), []location{
		{URI: shapesURI, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 4, Character: 11}, End: position{Line: 4, Character: 12}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 4, Character: 17}, End: position{Line: 4, Character: 18}}},
	})
	assertLocations(t, messageByID(t, msgs, 42)["result"].([]any), []location{
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 4, Character: 23}, End: position{Line: 4, Character: 24}}},
	})
}

func TestServerNavigationUsesImportedFactoryReturnFields(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := strings.Join([]string{
		"struct Point { x, y }",
		"fn make_point() {",
		"  return Point(1, 2)",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"var p = shapes.make_point()",
		"fn main() {",
		"  return p.x",
		"}",
		"",
	}, "\n")
	mainURI := fileURIFromPath(mainPath)
	shapesURI := fileURIFromPath(shapesPath)

	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      43,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      44,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 43)["result"].([]any), shapesURI, 0, 15, 16)
	hover := messageByID(t, msgs, 44)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "property x") || !strings.Contains(value, "shapes.Point property") || !strings.Contains(value, shapesURI) {
		t.Fatalf("hover value=%q missing imported factory field detail", value)
	}
}

func TestServerNavigationUsesImportedCallSiteParameterReturnFields(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesLines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf, label }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_outer(o) {",
		"  return o",
		"}",
		"fn identity_conflict(o) {",
		"  return o",
		"}",
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var good = shapes.Outer(shapes.Inner(shapes.Leaf(1, 2), \"a\"))",
		"var bad = shapes.Outer(shapes.Inner(shapes.Other(9), \"b\"))",
		"var id = shapes.identity_outer(good)",
		"var also = shapes.identity_outer(shapes.Outer(shapes.Inner(shapes.Leaf(3, 4), \"c\")))",
		"var conflict = shapes.identity_conflict(good)",
		"var conflict_bad = shapes.identity_conflict(bad)",
		"fn main() {",
		"  var comp = id.inner.leaf.",
		"  return id.inner.leaf.y + also.inner.leaf.x + conflict.inner.leaf.x",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := fileURIFromPath(mainPath)
	shapesURI := fileURIFromPath(shapesPath)

	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI, "text": mainText},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      45,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 8, "character": len([]rune(mainLines[8]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      46,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 9, "character": strings.Index(mainLines[9], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      47,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 9, "character": strings.Index(mainLines[9], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      48,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 9, "character": strings.LastIndex(mainLines[9], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 45)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("imported call-site parameter completion mismatch: %#v", items)
	}
	leafY := float64(strings.Index(shapesLines[0], "y"))
	assertDefinition(t, messageByID(t, msgs, 46)["result"].([]any), shapesURI, 0, leafY, leafY+1)
	leafX := float64(strings.Index(shapesLines[0], "x"))
	assertDefinition(t, messageByID(t, msgs, 47)["result"].([]any), shapesURI, 0, leafX, leafX+1)
	defs := messageByID(t, msgs, 48)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting imported call-site parameter definition=%#v want none", defs)
	}
}
