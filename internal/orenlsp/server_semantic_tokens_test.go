package orenlsp

import (
	"bytes"
	"strings"
	"testing"
)

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

func TestServerSemanticTokensFullClassifiesAnonymousImportDot(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		`import . "std:bytes"`,
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///anonymous-import-semantic.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      21,
		"method":  "textDocument/semanticTokens/full",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///anonymous-import-semantic.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	result := messageByID(t, msgs, 21)["result"].(map[string]any)
	got := expandSemanticTokenData(result["data"].([]any))
	want := []semanticTokenInfo{
		{Line: 0, Character: 0, Length: 6, Type: semanticTypeIndex("keyword")},
		{Line: 0, Character: 7, Length: 1, Type: semanticTypeIndex("operator")},
		{Line: 0, Character: 9, Length: 11, Type: semanticTypeIndex("string")},
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
		{Line: 2, Character: 22, Length: 1, Type: semanticTypeIndex("operator")},
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
