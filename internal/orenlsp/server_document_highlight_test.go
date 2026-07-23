package orenlsp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServerDocumentHighlightExactSymbols(t *testing.T) {
	tmp := t.TempDir()
	shapesPath := filepath.Join(tmp, "shapes.oren")
	shapesText := strings.Join([]string{
		"struct Widget { label }",
		"fn make_widget(): Widget {",
		"  return Widget(1)",
		"}",
		"",
	}, "\n")
	if err := os.WriteFile(shapesPath, []byte(shapesText), 0o644); err != nil {
		t.Fatalf("WriteFile shapes: %v", err)
	}

	mainPath := filepath.Join(tmp, "main.oren")
	mainURI := fileURIFromPath(mainPath)
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"fn main() {",
		"  var count = 1",
		"  count = count + 1",
		"  point.count = count",
		"  var widget = shapes.make_widget()",
		"  var field = shapes.Widget(2)",
		"  fn inner(count) {",
		"    return count",
		"  }",
		"  return count",
		"}",
		"",
	}, "\n")

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
		"id":      90,
		"method":  "textDocument/documentHighlight",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 10, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      91,
		"method":  "textDocument/documentHighlight",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 5, "character": 22},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      92,
		"method":  "textDocument/documentHighlight",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
			"position":     map[string]any{"line": 6, "character": 14},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())

	assertHighlights(t, messageByID(t, msgs, 90)["result"].([]any), []diagnosticRange{
		{Start: position{Line: 2, Character: 6}, End: position{Line: 2, Character: 11}},
		{Start: position{Line: 3, Character: 2}, End: position{Line: 3, Character: 7}},
		{Start: position{Line: 3, Character: 10}, End: position{Line: 3, Character: 15}},
		{Start: position{Line: 4, Character: 16}, End: position{Line: 4, Character: 21}},
		{Start: position{Line: 10, Character: 9}, End: position{Line: 10, Character: 14}},
	})
	assertHighlights(t, messageByID(t, msgs, 91)["result"].([]any), []diagnosticRange{
		{Start: position{Line: 5, Character: 22}, End: position{Line: 5, Character: 33}},
	})
	assertHighlights(t, messageByID(t, msgs, 92)["result"].([]any), []diagnosticRange{
		{Start: position{Line: 0, Character: 7}, End: position{Line: 0, Character: 13}},
		{Start: position{Line: 5, Character: 15}, End: position{Line: 5, Character: 21}},
		{Start: position{Line: 6, Character: 14}, End: position{Line: 6, Character: 20}},
	})
}

func assertHighlights(t *testing.T, got []any, want []diagnosticRange) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("highlights=%#v want %#v", got, want)
	}
	for i, raw := range got {
		item := raw.(map[string]any)
		if item["kind"] != float64(documentHighlightText) {
			t.Fatalf("highlight[%d] kind=%#v want %d", i, item["kind"], documentHighlightText)
		}
		assertRangeMap(t, item["range"].(map[string]any), want[i])
	}
}
