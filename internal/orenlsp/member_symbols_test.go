package orenlsp

import (
	"bytes"
	"strings"
	"testing"
)

func TestServerNavigationUsesConditionalAssignmentFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"struct Other { x }",
		"fn unknown() {",
		"  return 0",
		"}",
		"var p = unknown()",
		"if true {",
		"  p = Point(1, 2)",
		"} else {",
		"  p = Point(3, 4)",
		"}",
		"var c = Point(0, 0)",
		"if true {",
		"  c = Point(1, 2)",
		"} else {",
		"  c = Other(9)",
		"}",
		"if true {",
		"  var local = Point(1, 2)",
		"} else {",
		"  var local = Point(3, 4)",
		"}",
		"fn main() {",
		"  return p.x + c.x + local.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-conditional-assign.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      101,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": 11},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      102,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      103,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": 17},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      104,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": 27},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 101)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 102)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 23, Character: 11}, End: position{Line: 23, Character: 12}}},
	})
	defs := messageByID(t, msgs, 103)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting conditional assignment member definition=%#v want none", defs)
	}
	defs = messageByID(t, msgs, 104)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("branch-local conditional assignment member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesExpressionReceiverFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"fn make_point() {",
		"  return Point(3, 4)",
		"}",
		"fn main() {",
		"  return Point(1, 2).x + make_point().x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-expression-receiver.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      201,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 21},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      202,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": 38},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      203,
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
	assertDefinition(t, messageByID(t, msgs, 201)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 202)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 203)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 5, Character: 21}, End: position{Line: 5, Character: 22}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 5, Character: 38}, End: position{Line: 5, Character: 39}}},
	})
}
