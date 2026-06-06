package orenlsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
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
		"id":      34,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      35,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 17},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      36,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 11},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      37,
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
	assertDefinition(t, messageByID(t, msgs, 34)["result"].([]any), shapesURI, 0, 15, 16)

	hover := messageByID(t, msgs, 35)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "property x") || !strings.Contains(value, "shapes.Point property") || !strings.Contains(value, shapesURI) {
		t.Fatalf("hover value=%q missing imported field detail", value)
	}

	assertLocations(t, messageByID(t, msgs, 36)["result"].([]any), []location{
		{URI: shapesURI, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 4, Character: 11}, End: position{Line: 4, Character: 12}}},
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 4, Character: 17}, End: position{Line: 4, Character: 18}}},
	})
	assertLocations(t, messageByID(t, msgs, 37)["result"].([]any), []location{
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
		"id":      38,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      39,
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
	assertDefinition(t, messageByID(t, msgs, 38)["result"].([]any), shapesURI, 0, 15, 16)
	hover := messageByID(t, msgs, 39)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "property x") || !strings.Contains(value, "shapes.Point property") || !strings.Contains(value, shapesURI) {
		t.Fatalf("hover value=%q missing imported factory field detail", value)
	}
}

func TestServerSemanticTokensFullClassifiesSymbols(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"import math \"std:math\"",
		"var answer = 42",
		"fn compute() {",
		"  return answer + 1",
		"}",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///semantic.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      19,
		"method":  "textDocument/semanticTokens/full",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///semantic.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	result := messageByID(t, msgs, 19)["result"].(map[string]any)
	got := expandSemanticTokenData(result["data"].([]any))
	want := []semanticTokenInfo{
		{Line: 0, Character: 0, Length: 6, Type: semanticTypeIndex("keyword")},
		{Line: 0, Character: 7, Length: 4, Type: semanticTypeIndex("namespace"), Modifiers: semanticModifierDeclaration},
		{Line: 0, Character: 12, Length: 10, Type: semanticTypeIndex("string")},
		{Line: 1, Character: 0, Length: 3, Type: semanticTypeIndex("keyword")},
		{Line: 1, Character: 4, Length: 6, Type: semanticTypeIndex("variable"), Modifiers: semanticModifierDeclaration},
		{Line: 1, Character: 11, Length: 1, Type: semanticTypeIndex("operator")},
		{Line: 1, Character: 13, Length: 2, Type: semanticTypeIndex("number")},
		{Line: 2, Character: 0, Length: 2, Type: semanticTypeIndex("keyword")},
		{Line: 2, Character: 3, Length: 7, Type: semanticTypeIndex("function"), Modifiers: semanticModifierDeclaration},
		{Line: 3, Character: 2, Length: 6, Type: semanticTypeIndex("keyword")},
		{Line: 3, Character: 9, Length: 6, Type: semanticTypeIndex("variable")},
		{Line: 3, Character: 16, Length: 1, Type: semanticTypeIndex("operator")},
		{Line: 3, Character: 18, Length: 1, Type: semanticTypeIndex("number")},
	}
	if len(got) != len(want) {
		t.Fatalf("semantic tokens=%#v want %#v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("semantic token[%d]=%#v want %#v; all=%#v", i, got[i], want[i], got)
		}
	}
}

func TestServerSemanticTokensFullClassifiesParserSymbols(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Vec2 { x, y }",
		"fn compute(x, y) {",
		"  return x + y + point.x",
		"}",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///parser-semantic.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      20,
		"method":  "textDocument/semanticTokens/full",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///parser-semantic.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	result := messageByID(t, msgs, 20)["result"].(map[string]any)
	got := expandSemanticTokenData(result["data"].([]any))
	want := []semanticTokenInfo{
		{Line: 0, Character: 0, Length: 6, Type: semanticTypeIndex("keyword")},
		{Line: 0, Character: 7, Length: 4, Type: semanticTypeIndex("type"), Modifiers: semanticModifierDeclaration},
		{Line: 0, Character: 14, Length: 1, Type: semanticTypeIndex("property"), Modifiers: semanticModifierDeclaration},
		{Line: 0, Character: 17, Length: 1, Type: semanticTypeIndex("property"), Modifiers: semanticModifierDeclaration},
		{Line: 1, Character: 0, Length: 2, Type: semanticTypeIndex("keyword")},
		{Line: 1, Character: 3, Length: 7, Type: semanticTypeIndex("function"), Modifiers: semanticModifierDeclaration},
		{Line: 1, Character: 11, Length: 1, Type: semanticTypeIndex("parameter"), Modifiers: semanticModifierDeclaration},
		{Line: 1, Character: 14, Length: 1, Type: semanticTypeIndex("parameter"), Modifiers: semanticModifierDeclaration},
		{Line: 2, Character: 2, Length: 6, Type: semanticTypeIndex("keyword")},
		{Line: 2, Character: 9, Length: 1, Type: semanticTypeIndex("parameter")},
		{Line: 2, Character: 11, Length: 1, Type: semanticTypeIndex("operator")},
		{Line: 2, Character: 13, Length: 1, Type: semanticTypeIndex("parameter")},
		{Line: 2, Character: 15, Length: 1, Type: semanticTypeIndex("operator")},
		{Line: 2, Character: 17, Length: 5, Type: semanticTypeIndex("variable")},
		{Line: 2, Character: 23, Length: 1, Type: semanticTypeIndex("property")},
	}
	if len(got) != len(want) {
		t.Fatalf("semantic tokens=%#v want %#v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("semantic token[%d]=%#v want %#v; all=%#v", i, got[i], want[i], got)
		}
	}
}

func writeTestMessage(t *testing.T, w *bytes.Buffer, v any) {
	t.Helper()
	msg, err := EncodeMessage(v)
	if err != nil {
		t.Fatalf("EncodeMessage: %v", err)
	}
	w.Write(msg)
}

func readTestMessages(t *testing.T, raw []byte) []map[string]any {
	t.Helper()
	r := bufio.NewReader(bytes.NewReader(raw))
	var out []map[string]any
	for {
		body, err := readMessage(r)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("readMessage: %v", err)
		}
		var msg map[string]any
		if err := json.Unmarshal(body, &msg); err != nil {
			t.Fatalf("json: %v", err)
		}
		out = append(out, msg)
	}
	return out
}

func diagnosticsFromMessage(t *testing.T, msg map[string]any) []any {
	t.Helper()
	if msg["method"] != "textDocument/publishDiagnostics" {
		t.Fatalf("method=%#v want publishDiagnostics", msg["method"])
	}
	params := msg["params"].(map[string]any)
	return params["diagnostics"].([]any)
}

func messageByID(t *testing.T, msgs []map[string]any, id float64) map[string]any {
	t.Helper()
	for _, msg := range msgs {
		if msgID, ok := msg["id"].(float64); ok && msgID == id {
			return msg
		}
	}
	t.Fatalf("missing response id=%v in %#v", id, msgs)
	return nil
}

func assertLabels(t *testing.T, values []any, want []string) {
	t.Helper()
	if len(values) != len(want) {
		t.Fatalf("values=%#v want labels %#v", values, want)
	}
	for i, value := range values {
		got := value.(map[string]any)["name"].(string)
		if got != want[i] {
			t.Fatalf("label[%d]=%q want %q; values=%#v", i, got, want[i], values)
		}
	}
}

func hasCompletion(items []any, label string, kind float64) bool {
	for _, item := range items {
		obj := item.(map[string]any)
		if obj["label"] == label && obj["kind"] == kind {
			return true
		}
	}
	return false
}

func assertStringList(t *testing.T, got []any, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("list=%#v want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("list[%d]=%#v want %q; list=%#v", i, got[i], want[i], got)
		}
	}
}

func expandSemanticTokenData(raw []any) []semanticTokenInfo {
	var out []semanticTokenInfo
	line := 0
	character := 0
	for i := 0; i+4 < len(raw); i += 5 {
		lineDelta := int(raw[i].(float64))
		charDelta := int(raw[i+1].(float64))
		if len(out) == 0 {
			line = lineDelta
			character = charDelta
		} else {
			line += lineDelta
			if lineDelta == 0 {
				character += charDelta
			} else {
				character = charDelta
			}
		}
		out = append(out, semanticTokenInfo{
			Line:      line,
			Character: character,
			Length:    int(raw[i+2].(float64)),
			Type:      int(raw[i+3].(float64)),
			Modifiers: int(raw[i+4].(float64)),
		})
	}
	return out
}

func assertDefinition(t *testing.T, defs []any, uri string, line, startChar, endChar float64) {
	t.Helper()
	if len(defs) != 1 {
		t.Fatalf("definitions=%#v want one", defs)
	}
	loc := defs[0].(map[string]any)
	if loc["uri"] != uri {
		t.Fatalf("definition uri=%#v want %q", loc["uri"], uri)
	}
	rng := loc["range"].(map[string]any)
	start := rng["start"].(map[string]any)
	end := rng["end"].(map[string]any)
	if start["line"] != line || start["character"] != startChar || end["line"] != line || end["character"] != endChar {
		t.Fatalf("definition range=%#v want line=%v chars=%v..%v", rng, line, startChar, endChar)
	}
}

func assertLocations(t *testing.T, got []any, want []location) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("locations=%#v want %#v", got, want)
	}
	for i, value := range got {
		loc := value.(map[string]any)
		if loc["uri"] != want[i].URI {
			t.Fatalf("location[%d] uri=%#v want %q; locations=%#v", i, loc["uri"], want[i].URI, got)
		}
		rng := loc["range"].(map[string]any)
		start := rng["start"].(map[string]any)
		end := rng["end"].(map[string]any)
		if int(start["line"].(float64)) != want[i].Range.Start.Line ||
			int(start["character"].(float64)) != want[i].Range.Start.Character ||
			int(end["line"].(float64)) != want[i].Range.End.Line ||
			int(end["character"].(float64)) != want[i].Range.End.Character {
			t.Fatalf("location[%d] range=%#v want %#v", i, rng, want[i].Range)
		}
	}
}

func diagnosticsWithSource(diags []diagnostic, source string) []diagnostic {
	out := []diagnostic{}
	for _, diag := range diags {
		if diag.Source == source {
			out = append(out, diag)
		}
	}
	return out
}
