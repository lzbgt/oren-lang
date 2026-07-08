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

func TestServerRenameRejectsImportedTypedMembers(t *testing.T) {
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
	if result := messageByID(t, msgs, 65)["result"]; result != nil {
		t.Fatalf("prepareRename for imported field returned result: %#v", messageByID(t, msgs, 65))
	}
	assertWorkspaceEdit(t, messageByID(t, msgs, 66)["result"].(map[string]any), mainURI, "x2", nil)
}
