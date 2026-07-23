package orenlsp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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

func TestServerDefinitionFindsAnonymousImportedFileSymbol(t *testing.T) {
	tmp := t.TempDir()
	helperPath := filepath.Join(tmp, "helper.oren")
	helperText := strings.Join([]string{
		"var helper_value = 7",
		"fn helper_call() { return helper_value }",
		"",
	}, "\n")
	if err := os.WriteFile(helperPath, []byte(helperText), 0o644); err != nil {
		t.Fatalf("WriteFile helper: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import . \"helper.oren\"",
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
		"id":      17,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      18,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 9},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      19,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      20,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 12},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      21,
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
	defs := messageByID(t, msgs, 17)["result"].([]any)
	assertDefinition(t, defs, fileURIFromPath(helperPath), 0, 4, 16)
	items := messageByID(t, msgs, 18)["result"].([]any)
	if !hasCompletion(items, "helper_value", 6) || !hasCompletion(items, "helper_call", 3) {
		t.Fatalf("anonymous import completion missing imported symbols: %#v", items)
	}
	hover := messageByID(t, msgs, 19)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "variable helper_value") || !strings.Contains(value, fileURIFromPath(helperPath)) {
		t.Fatalf("anonymous import hover value=%q missing imported symbol detail", value)
	}
	assertLocations(t, messageByID(t, msgs, 20)["result"].([]any), []location{
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
		{URI: fileURIFromPath(helperPath), Range: diagnosticRange{Start: position{Line: 0, Character: 4}, End: position{Line: 0, Character: 16}}},
		{URI: fileURIFromPath(helperPath), Range: diagnosticRange{Start: position{Line: 1, Character: 26}, End: position{Line: 1, Character: 38}}},
	})
	assertLocations(t, messageByID(t, msgs, 21)["result"].([]any), []location{
		{URI: mainURI, Range: diagnosticRange{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 21}}},
		{URI: fileURIFromPath(helperPath), Range: diagnosticRange{Start: position{Line: 1, Character: 26}, End: position{Line: 1, Character: 38}}},
	})
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

func TestServerNavigationUsesAnonymousImportedConstructorFields(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := "struct Point { x, y }\n"
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import . \"shapes.oren\"",
		"var p = Point(1, 2)",
		"var value = p.",
		"fn main() {",
		"  return p.x",
		"}",
		"",
	}, "\n")
	mainURI := fileURIFromPath(mainPath)

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
		"id":      19,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": len("var value = p.")},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      20,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": len("  return p.x")},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 19)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) {
		t.Fatalf("anonymous imported member completion missing fields: %#v", items)
	}
	defs := messageByID(t, msgs, 20)["result"].([]any)
	assertDefinition(t, defs, fileURIFromPath(shapesPath), 0, 15, 16)
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
