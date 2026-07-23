package orenlsp

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestServerDocumentLinksWorkspaceSymbolsAndFoldingRanges(t *testing.T) {
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
	extraPath := filepath.Join(tmp, "extra.oren")
	extraText := "struct Extra { value }\n"
	if err := os.WriteFile(extraPath, []byte(extraText), 0o644); err != nil {
		t.Fatalf("WriteFile extra: %v", err)
	}

	mainPath := filepath.Join(tmp, "main.oren")
	mainURI := fileURIFromPath(mainPath)
	mainText := strings.Join([]string{
		"import shapes \"shapes.oren\"",
		"import . \"extra.oren\"",
		"fn main() {",
		"  if true {",
		"    shapes.make_widget()",
		"    Extra(1)",
		"  }",
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
		"id":      100,
		"method":  "textDocument/documentLink",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      101,
		"method":  "workspace/symbol",
		"params": map[string]any{
			"query": "Extra",
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      102,
		"method":  "textDocument/foldingRange",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": mainURI},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())

	assertDocumentLinks(t, messageByID(t, msgs, 100)["result"].([]any), []documentLink{
		{Range: diagnosticRange{Start: position{Line: 0, Character: 14}, End: position{Line: 0, Character: 27}}, Target: fileURIFromPath(shapesPath)},
		{Range: diagnosticRange{Start: position{Line: 1, Character: 9}, End: position{Line: 1, Character: 21}}, Target: fileURIFromPath(extraPath)},
	})
	assertWorkspaceSymbolNames(t, messageByID(t, msgs, 101)["result"].([]any), []string{"Extra"})
	assertFoldingRanges(t, messageByID(t, msgs, 102)["result"].([]any), []foldingRange{
		{StartLine: 2, StartCharacter: 10, EndLine: 7, EndCharacter: 1, Kind: "region"},
		{StartLine: 3, StartCharacter: 10, EndLine: 6, EndCharacter: 3, Kind: "region"},
	})
}

func assertDocumentLinks(t *testing.T, got []any, want []documentLink) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("document links=%#v want %#v", got, want)
	}
	for i, raw := range got {
		link := raw.(map[string]any)
		if link["target"] != want[i].Target {
			t.Fatalf("document link[%d] target=%#v want %q", i, link["target"], want[i].Target)
		}
		assertRangeMap(t, link["range"].(map[string]any), want[i].Range)
	}
}

func assertWorkspaceSymbolNames(t *testing.T, got []any, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("workspace symbols=%#v want names %#v", got, want)
	}
	for i, raw := range got {
		sym := raw.(map[string]any)
		if sym["name"] != want[i] {
			t.Fatalf("workspace symbol[%d] name=%#v want %q", i, sym["name"], want[i])
		}
		loc := sym["location"].(map[string]any)
		if loc["uri"] == "" {
			t.Fatalf("workspace symbol[%d] missing location: %#v", i, sym)
		}
	}
}

func assertFoldingRanges(t *testing.T, got []any, want []foldingRange) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("folding ranges=%#v want %#v", got, want)
	}
	for i, raw := range got {
		fr := raw.(map[string]any)
		if int(fr["startLine"].(float64)) != want[i].StartLine ||
			int(fr["startCharacter"].(float64)) != want[i].StartCharacter ||
			int(fr["endLine"].(float64)) != want[i].EndLine ||
			int(fr["endCharacter"].(float64)) != want[i].EndCharacter ||
			fr["kind"] != want[i].Kind {
			t.Fatalf("folding range[%d]=%#v want %#v", i, fr, want[i])
		}
	}
}
