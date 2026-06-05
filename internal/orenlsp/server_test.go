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
