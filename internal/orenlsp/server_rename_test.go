package orenlsp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServerRenameExactScopedParameters(t *testing.T) {
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
	uri := "file:///rename-scoped.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      60,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      61,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
			"newName":      "inner_x",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      62,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
			"newName":      "fn",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 60)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 2, Character: 11},
		End:   position{Line: 2, Character: 12},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 61)["result"].(map[string]any), uri, "inner_x", []diagnosticRange{
		{Start: position{Line: 1, Character: 11}, End: position{Line: 1, Character: 12}},
		{Start: position{Line: 2, Character: 11}, End: position{Line: 2, Character: 12}},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 62)["result"].(map[string]any), uri, "fn", nil)
}

func TestServerRenameExactScopedLocals(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"fn main() {",
		"  var count = 1",
		"  count = count + 1",
		"  var field = count",
		"  point.count = count",
		"  fn inner(count) {",
		"    var local = count",
		"    return local",
		"  }",
		"  return count",
		"}",
		"var count = 99",
		"",
	}, "\n")
	uri := "file:///rename-scoped-locals.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      260,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 3},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      261,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 9, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      262,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 9, "character": 11},
			"context":      map[string]any{"includeDeclaration": false},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      263,
		"method":  "textDocument/hover",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 9, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      264,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 3},
			"newName":      "total",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 260)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 2, Character: 2},
		End:   position{Line: 2, Character: 7},
	})
	assertDefinition(t, messageByID(t, msgs, 261)["result"].([]any), uri, 1, 6, 11)
	assertLocations(t, messageByID(t, msgs, 262)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 2, Character: 2}, End: position{Line: 2, Character: 7}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 2, Character: 10}, End: position{Line: 2, Character: 15}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 3, Character: 14}, End: position{Line: 3, Character: 19}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 4, Character: 16}, End: position{Line: 4, Character: 21}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 9, Character: 9}, End: position{Line: 9, Character: 14}}},
	})
	hover := messageByID(t, msgs, 263)["result"].(map[string]any)
	value := hover["contents"].(map[string]any)["value"].(string)
	if !strings.Contains(value, "variable count") || !strings.Contains(value, "local variable") || !strings.Contains(value, uri) {
		t.Fatalf("hover value=%q missing local variable detail", value)
	}
	assertRangeMap(t, hover["range"].(map[string]any), diagnosticRange{
		Start: position{Line: 1, Character: 6},
		End:   position{Line: 1, Character: 11},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 264)["result"].(map[string]any), uri, "total", []diagnosticRange{
		{Start: position{Line: 1, Character: 6}, End: position{Line: 1, Character: 11}},
		{Start: position{Line: 2, Character: 2}, End: position{Line: 2, Character: 7}},
		{Start: position{Line: 2, Character: 10}, End: position{Line: 2, Character: 15}},
		{Start: position{Line: 3, Character: 14}, End: position{Line: 3, Character: 19}},
		{Start: position{Line: 4, Character: 16}, End: position{Line: 4, Character: 21}},
		{Start: position{Line: 9, Character: 9}, End: position{Line: 9, Character: 14}},
	})
}

func TestServerRenameExactTypedMembers(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"var p = Point(1, 2)",
		"fn main() {",
		"  return p.x + p.y",
		"}",
		"",
	}, "\n")
	uri := "file:///rename-members.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      63,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      64,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 3, "character": 11},
			"newName":      "x2",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 63)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 3, Character: 11},
		End:   position{Line: 3, Character: 12},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 64)["result"].(map[string]any), uri, "x2", []diagnosticRange{
		{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}},
		{Start: position{Line: 3, Character: 11}, End: position{Line: 3, Character: 12}},
	})
}

func TestServerRenameImportedTypedMembers(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	if err := os.WriteFile(shapesPath, []byte("struct Point { x, y }\n"), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"var p = shapes.Point(1, 2)",
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
		"id":      65,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      66,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
			"newName":      "x2",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 65)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 3, Character: 11},
		End:   position{Line: 3, Character: 12},
	})
	edit := messageByID(t, msgs, 66)["result"].(map[string]any)
	assertWorkspaceEditFileCount(t, edit, 2)
	assertWorkspaceEdit(t, edit, fileURIFromPath(shapesPath), "x2", []diagnosticRange{
		{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}},
	})
	assertWorkspaceEdit(t, edit, mainURI, "x2", []diagnosticRange{
		{Start: position{Line: 3, Character: 11}, End: position{Line: 3, Character: 12}},
	})
}

func TestServerRenameAnonymousImportedTypedMembers(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	if err := os.WriteFile(shapesPath, []byte("struct Point { x, y }\n"), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import . \"shapes.oren\"",
		"var p = Point(1, 2)",
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
		"id":      67,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      68,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 11},
			"newName":      "x2",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 67)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 3, Character: 11},
		End:   position{Line: 3, Character: 12},
	})
	edit := messageByID(t, msgs, 68)["result"].(map[string]any)
	assertWorkspaceEditFileCount(t, edit, 2)
	assertWorkspaceEdit(t, edit, fileURIFromPath(shapesPath), "x2", []diagnosticRange{
		{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}},
	})
	assertWorkspaceEdit(t, edit, mainURI, "x2", []diagnosticRange{
		{Start: position{Line: 3, Character: 11}, End: position{Line: 3, Character: 12}},
	})
}

func TestServerRenameImportAlias(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"var p = shapes.Point(1, 2)",
		"fn main() {",
		"  return shapes.make().x + p.x",
		"}",
		"",
	}, "\n")
	uri := "file:///rename-import-alias.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      69,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 8},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      70,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 1, "character": 10},
			"newName":      "geo",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      71,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 1, "character": 10},
			"newName":      "bad-name",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 69)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 0, Character: 7},
		End:   position{Line: 0, Character: 13},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 70)["result"].(map[string]any), uri, "geo", []diagnosticRange{
		{Start: position{Line: 0, Character: 7}, End: position{Line: 0, Character: 13}},
		{Start: position{Line: 1, Character: 8}, End: position{Line: 1, Character: 14}},
		{Start: position{Line: 3, Character: 9}, End: position{Line: 3, Character: 15}},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 71)["result"].(map[string]any), uri, "bad-name", nil)
}

func TestServerRenameTopLevelFunctionAndTypes(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Box { v }",
		"fn make_box(): Box {",
		"  return Box(1)",
		"}",
		"fn use(make_box) {",
		"  return make_box",
		"}",
		"var b = make_box()",
		"",
	}, "\n")
	uri := "file:///rename-top-level.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      72,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": 10},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      73,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": 10},
			"newName":      "build_box",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      74,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 2, "character": 11},
			"newName":      "Crate",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertRangeMap(t, messageByID(t, msgs, 72)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 7, Character: 8},
		End:   position{Line: 7, Character: 16},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 73)["result"].(map[string]any), uri, "build_box", []diagnosticRange{
		{Start: position{Line: 1, Character: 3}, End: position{Line: 1, Character: 11}},
		{Start: position{Line: 7, Character: 8}, End: position{Line: 7, Character: 16}},
	})
	assertWorkspaceEdit(t, messageByID(t, msgs, 74)["result"].(map[string]any), uri, "Crate", []diagnosticRange{
		{Start: position{Line: 0, Character: 7}, End: position{Line: 0, Character: 10}},
		{Start: position{Line: 1, Character: 15}, End: position{Line: 1, Character: 18}},
		{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 12}},
	})
}

func TestServerRenameImportedTopLevelFunctionAndTypes(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := strings.Join([]string{
		"struct Widget { label }",
		"fn make_widget(): Widget {",
		"  return Widget(1)",
		"}",
		"fn keep(make_widget) {",
		"  return make_widget",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}
	extraPath := filepath.Join(tmp, "extra.oren")
	extraText := strings.Join([]string{
		"struct Extra { v }",
		"fn new_extra(): Extra {",
		"  return Extra(1)",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(extraPath, []byte(extraText), 0o644); err != nil {
		t.Fatalf("WriteFile extra: %v", err)
	}
	mainPath := filepath.Join(tmp, "main.oren")
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"import . \"extra.oren\"",
		"var a = shapes.make_widget()",
		"var b = shapes.Widget(1)",
		"var c = Extra(1)",
		"fn main(make_widget) {",
		"  return make_widget",
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
		"id":      75,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 20},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      76,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 2, "character": 20},
			"newName":      "build_widget",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      77,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 18},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      78,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 3, "character": 18},
			"newName":      "Gizmo",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      79,
		"method":  "textDocument/prepareRename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 10},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      80,
		"method":  "textDocument/rename",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 4, "character": 10},
			"newName":      "Thing",
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())

	assertRangeMap(t, messageByID(t, msgs, 75)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 2, Character: 15},
		End:   position{Line: 2, Character: 26},
	})
	edit := messageByID(t, msgs, 76)["result"].(map[string]any)
	assertWorkspaceEditFileCount(t, edit, 2)
	assertWorkspaceEdit(t, edit, fileURIFromPath(shapesPath), "build_widget", []diagnosticRange{
		{Start: position{Line: 1, Character: 3}, End: position{Line: 1, Character: 14}},
	})
	assertWorkspaceEdit(t, edit, mainURI, "build_widget", []diagnosticRange{
		{Start: position{Line: 2, Character: 15}, End: position{Line: 2, Character: 26}},
	})

	assertRangeMap(t, messageByID(t, msgs, 77)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 3, Character: 15},
		End:   position{Line: 3, Character: 21},
	})
	edit = messageByID(t, msgs, 78)["result"].(map[string]any)
	assertWorkspaceEditFileCount(t, edit, 2)
	assertWorkspaceEdit(t, edit, fileURIFromPath(shapesPath), "Gizmo", []diagnosticRange{
		{Start: position{Line: 0, Character: 7}, End: position{Line: 0, Character: 13}},
		{Start: position{Line: 1, Character: 18}, End: position{Line: 1, Character: 24}},
		{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 15}},
	})
	assertWorkspaceEdit(t, edit, mainURI, "Gizmo", []diagnosticRange{
		{Start: position{Line: 3, Character: 15}, End: position{Line: 3, Character: 21}},
	})

	assertRangeMap(t, messageByID(t, msgs, 79)["result"].(map[string]any), diagnosticRange{
		Start: position{Line: 4, Character: 8},
		End:   position{Line: 4, Character: 13},
	})
	edit = messageByID(t, msgs, 80)["result"].(map[string]any)
	assertWorkspaceEditFileCount(t, edit, 2)
	assertWorkspaceEdit(t, edit, fileURIFromPath(extraPath), "Thing", []diagnosticRange{
		{Start: position{Line: 0, Character: 7}, End: position{Line: 0, Character: 12}},
		{Start: position{Line: 1, Character: 16}, End: position{Line: 1, Character: 21}},
		{Start: position{Line: 2, Character: 9}, End: position{Line: 2, Character: 14}},
	})
	assertWorkspaceEdit(t, edit, mainURI, "Thing", []diagnosticRange{
		{Start: position{Line: 4, Character: 8}, End: position{Line: 4, Character: 13}},
	})
}
