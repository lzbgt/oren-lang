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

func TestTypedMemberAnalysisUsesMemberAssignmentFieldTypes(t *testing.T) {
	lines := []string{
		"struct Inner { x, y }",
		"struct Other { z }",
		"struct Holder { inner, items, rows }",
		"fn unknown() { return 0 }",
		"fn main() {",
		"  var holder = Holder(Other(0), [Other(1)], [[Other(2)]])",
		"  holder.inner = Inner(1, 2)",
		"  holder.items = [Inner(3, 4)]",
		"  holder.rows = [[Inner(5, 6)]]",
		"  var c0 = holder.inner.",
		"  var d0 = holder.inner.x",
		"  var c1 = holder.items[0].",
		"  var d1 = holder.items[0].y",
		"  var c2 = holder.rows[0][0].",
		"  var d2 = holder.rows[0][0].x",
		"  holder.inner = unknown()",
		"  return holder.inner.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-member-assignment.oren"

	items, found := typedMemberCompletionItemsAt(text, uri, position{
		Line:      9,
		Character: len([]rune(lines[9])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("member assignment field completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(text, uri, position{
		Line:      10,
		Character: strings.LastIndex(lines[10], ".x") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "x" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("member assignment field definition mismatch match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(text, uri, position{
		Line:      11,
		Character: len([]rune(lines[11])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("member assignment list field completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      12,
		Character: strings.LastIndex(lines[12], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("member assignment list field definition mismatch match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(text, uri, position{
		Line:      13,
		Character: len([]rune(lines[13])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("member assignment nested list completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      14,
		Character: strings.LastIndex(lines[14], ".x") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "x" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("member assignment nested list definition mismatch match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      16,
		Character: strings.LastIndex(lines[16], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("unknown member reassignment definition=%#v want none", match)
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

func TestServerNavigationUsesConstructorBoundFieldChains(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Inner { x, y }",
		"struct Outer { inner, label }",
		"struct Other { x }",
		"var outer = Outer(Inner(1, 2), \"a\")",
		"var alias = outer",
		"var rebound = Outer(Inner(3, 4), \"b\")",
		"rebound = Other(9)",
		"fn main() {",
		"  var c = alias.inner.",
		"  var nested = alias.inner",
		"  return alias.inner.x + nested.y + rebound.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-constructor-bound-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      211,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": 22},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      212,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": 21},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      213,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": 32},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      214,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": 44},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 211)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) {
		t.Fatalf("constructor-bound field-chain completion missing Inner fields: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 212)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 213)["result"].([]any), uri, 0, 18, 19)
	assertDefinition(t, messageByID(t, msgs, 214)["result"].([]any), uri, 2, 15, 16)
}

func TestServerNavigationUsesFactoryReturnFieldChains(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Inner { x, y }",
		"struct Outer { inner, label }",
		"struct Other { x }",
		"fn make_outer() {",
		"  return Outer(Inner(1, 2), \"a\")",
		"}",
		"fn choose_outer(ok) {",
		"  return if ok {",
		"    return Outer(Inner(3, 4), \"b\")",
		"  } else {",
		"    return Outer(Inner(5, 6), \"c\")",
		"  }",
		"}",
		"fn conflict(ok) {",
		"  return if ok {",
		"    return Outer(Inner(7, 8), \"d\")",
		"  } else {",
		"    return Outer(Other(9), \"e\")",
		"  }",
		"}",
		"fn main() {",
		"  var direct = make_outer().inner.",
		"  var outer = make_outer()",
		"  var chosen = choose_outer(true)",
		"  var conflicted = conflict(true)",
		"  return make_outer().inner.x + outer.inner.y + chosen.inner.x + conflicted.inner.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-factory-return-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      221,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 21, "character": 35},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      222,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": 28},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      223,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": 44},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      224,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": 61},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      225,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": 82},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 221)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) {
		t.Fatalf("factory-return field-chain completion missing Inner fields: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 222)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 223)["result"].([]any), uri, 0, 18, 19)
	assertDefinition(t, messageByID(t, msgs, 224)["result"].([]any), uri, 0, 15, 16)
	defs := messageByID(t, msgs, 225)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting factory-return field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesCallSiteParameterFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Inner { x, y }",
		"struct Outer { inner, label }",
		"struct Other { z }",
		"fn unknown() { return 0 }",
		"fn use_outer(o) {",
		"  var c = o.inner.",
		"  return o.inner.x",
		"}",
		"fn identity_outer(o) {",
		"  return o",
		"}",
		"fn use_conflict(o) {",
		"  return o.inner.x",
		"}",
		"var good = Outer(Inner(1, 2), \"a\")",
		"var alias = good",
		"var weak = Outer(unknown(), \"b\")",
		"var bad = Outer(Other(9), \"c\")",
		"var a = use_outer(alias)",
		"var b = use_outer(Outer(Inner(3, 4), \"d\"))",
		"var c = use_conflict(good)",
		"var d = use_conflict(bad)",
		"var e = identity_outer(good)",
		"fn main() {",
		"  var from_return = e.inner.",
		"  return e.inner.y + weak.inner.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-call-param-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      231,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": len([]rune(lines[5]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      232,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": strings.Index(lines[6], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      233,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      234,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 12, "character": strings.Index(lines[12], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      235,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 24, "character": len([]rune(lines[24]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      236,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": strings.Index(lines[25], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      237,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": strings.Index(lines[25], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 231)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("call-site parameter field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 232)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 233)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 6, Character: strings.Index(lines[6], ".x") + 1}, End: position{Line: 6, Character: strings.Index(lines[6], ".x") + 2}}},
	})
	defs := messageByID(t, msgs, 234)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting call-site parameter field-chain definition=%#v want none", defs)
	}
	returned := messageByID(t, msgs, 235)["result"].([]any)
	if !hasCompletion(returned, "x", 5) || !hasCompletion(returned, "y", 5) || hasCompletion(returned, "z", 5) {
		t.Fatalf("returned parameter field-chain completion mismatch: %#v", returned)
	}
	assertDefinition(t, messageByID(t, msgs, 236)["result"].([]any), uri, 0, 18, 19)
	defs = messageByID(t, msgs, 237)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("weak call-site field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesNestedCallSiteParameterFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf, label }",
		"struct Outer { inner, other }",
		"struct Other { z }",
		"fn unknown() { return 0 }",
		"fn use_outer(o) {",
		"  var c = o.inner.leaf.",
		"  return o.inner.leaf.x",
		"}",
		"fn identity_outer(o) {",
		"  return o",
		"}",
		"fn use_conflict(o) {",
		"  return o.inner.leaf.x",
		"}",
		"var good = Outer(Inner(Leaf(1, 2), \"a\"), Other(9))",
		"var alias = good",
		"var weak = Outer(Inner(unknown(), \"b\"), Other(10))",
		"var bad = Outer(Inner(Other(11), \"c\"), Other(12))",
		"var a = use_outer(alias)",
		"var b = use_outer(Outer(Inner(Leaf(3, 4), \"d\"), Other(13)))",
		"var c = use_conflict(good)",
		"var d = use_conflict(bad)",
		"var e = identity_outer(good)",
		"fn main() {",
		"  var from_return = e.inner.leaf.",
		"  return e.inner.leaf.y + weak.inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-nested-call-param-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      241,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": len([]rune(lines[6]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      242,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": strings.LastIndex(lines[7], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      243,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.LastIndex(lines[13], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      244,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 25, "character": len([]rune(lines[25]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      245,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 26, "character": strings.Index(lines[26], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      246,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 26, "character": strings.LastIndex(lines[26], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 241)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("nested call-site parameter field-chain completion mismatch: %#v", items)
	}
	leafX := float64(strings.Index(lines[0], "x"))
	assertDefinition(t, messageByID(t, msgs, 242)["result"].([]any), uri, 0, leafX, leafX+1)
	defs := messageByID(t, msgs, 243)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting nested call-site field-chain definition=%#v want none", defs)
	}
	returned := messageByID(t, msgs, 244)["result"].([]any)
	if !hasCompletion(returned, "x", 5) || !hasCompletion(returned, "y", 5) || hasCompletion(returned, "z", 5) {
		t.Fatalf("returned nested parameter field-chain completion mismatch: %#v", returned)
	}
	leafY := float64(strings.Index(lines[0], "y"))
	assertDefinition(t, messageByID(t, msgs, 245)["result"].([]any), uri, 0, leafY, leafY+1)
	defs = messageByID(t, msgs, 246)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("weak nested call-site field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesReturnIfExpressionReceiverFields(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Point { x, y }",
		"struct Other { z }",
		"fn choose(ok) {",
		"  return if ok {",
		"    return Point(1, 2)",
		"  } else {",
		"    return Point(3, 4)",
		"  }",
		"}",
		"fn choose_conflict(ok) {",
		"  return if ok {",
		"    return Point(1, 2)",
		"  } else {",
		"    return Other(9)",
		"  }",
		"}",
		"fn main() {",
		"  var p = choose(true).",
		"  return choose(true).x + choose_conflict(true).z",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-return-if-expression.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      251,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 17, "character": 23},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      252,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 18, "character": 22},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      253,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      254,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 18, "character": 48},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 251)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("return-if completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 252)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 253)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 18, Character: 22}, End: position{Line: 18, Character: 23}}},
	})
	defs := messageByID(t, msgs, 254)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("conflicting return-if member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesConstructedFieldReceiverTypes(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Inner { x }",
		"struct Outer { inner }",
		"fn main() {",
		"  var nested = Outer(Inner(2)).inner",
		"  return Outer(Inner(1)).inner.x + nested.x",
		"}",
		"",
	}, "\n")
	uri := "file:///typed-member-constructed-field.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      301,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 4, "character": 31},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      302,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 4, "character": 42},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      303,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      304,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 1, "character": 15},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 301)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 302)["result"].([]any), uri, 0, 15, 16)
	assertLocations(t, messageByID(t, msgs, 303)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 4, Character: 31}, End: position{Line: 4, Character: 32}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 4, Character: 42}, End: position{Line: 4, Character: 43}}},
	})
	assertLocations(t, messageByID(t, msgs, 304)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 1, Character: 15}, End: position{Line: 1, Character: 20}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 3, Character: 31}, End: position{Line: 3, Character: 36}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 4, Character: 25}, End: position{Line: 4, Character: 30}}},
	})
}
