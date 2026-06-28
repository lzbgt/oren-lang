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

func TestServerNavigationUsesConstructorBoundFieldChains(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"struct Inner { x, y }",
		"struct Outer { inner, label }",
		"struct Other { x }",
		"var outer = Outer(Inner(1, 2), \"a\")",
		"var rebound = Outer(Inner(3, 4), \"b\")",
		"rebound = Other(9)",
		"fn main() {",
		"  var c = outer.inner.",
		"  return outer.inner.x + rebound.x",
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
			"position":     map[string]any{"line": 7, "character": 22},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      212,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": 21},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      213,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": 33},
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
	assertDefinition(t, messageByID(t, msgs, 213)["result"].([]any), uri, 2, 15, 16)
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

func TestServerNavigationUsesIndexedContainerReceiverFields(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Point { x, y }",
		"struct Other { z }",
		"fn main() {",
		"  var points = [Point(1, 2), Point(3, 4)]",
		"  var by = {\"home\": Point(5, 6), \"away\": Point(7, 8)}",
		"  var mixed = [Point(1, 2), Other(9)]",
		"  var c0 = [Point(1, 2), Point(3, 4)][0].",
		"  var c1 = {\"home\": Point(5, 6), \"away\": Point(7, 8)}[\"home\"].",
		"  return points[1].x + by[\"away\"].y + mixed[0].z",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-indexed-container.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      701,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": len([]rune(lines[6]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      702,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": strings.LastIndex(lines[7], ".") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      703,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": strings.Index(lines[8], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      704,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": strings.Index(lines[8], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      705,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": strings.Index(lines[8], ".z") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	listItems := messageByID(t, msgs, 701)["result"].([]any)
	if !hasCompletion(listItems, "x", 5) || !hasCompletion(listItems, "y", 5) || hasCompletion(listItems, "z", 5) {
		t.Fatalf("indexed list completion mismatch: %#v", listItems)
	}
	mapItems := messageByID(t, msgs, 702)["result"].([]any)
	if !hasCompletion(mapItems, "x", 5) || !hasCompletion(mapItems, "y", 5) || hasCompletion(mapItems, "z", 5) {
		t.Fatalf("indexed map completion mismatch: %#v", mapItems)
	}
	assertDefinition(t, messageByID(t, msgs, 703)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 704)["result"].([]any), uri, 0, 18, 19)
	defs := messageByID(t, msgs, 705)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed indexed container definition=%#v want none", defs)
	}
}

func TestInferExpressionTypeUsesIndexedContainers(t *testing.T) {
	text := strings.Join([]string{
		"struct Point { x, y }",
		"struct Other { z }",
		"",
	}, "\n")
	_, env := typedMemberAnalysisEnv(text, "file:///infer-indexed-container.oren", nil, nil)
	stack := []map[string]string{{"points": inferredListPrefix + "Point", "by": inferredMapPrefix + "Point"}}
	if got := inferExpressionType(parseMemberReceiverExpression("points[0]"), env, stack); got != "Point" {
		t.Fatalf("points[0] inferred type=%q want Point", got)
	}
	if got := inferExpressionType(parseMemberReceiverExpression("by[\"home\"]"), env, stack); got != "Point" {
		t.Fatalf("by[home] inferred type=%q want Point", got)
	}
	if got := inferExpressionType(parseMemberReceiverExpression("[Point(1, 2), Point(3, 4)][0]"), env, nil); got != "Point" {
		t.Fatalf("literal list indexed type=%q want Point", got)
	}
	if got := inferExpressionType(parseMemberReceiverExpression("[Point(1, 2), Other(9)][0]"), env, nil); got != "" {
		t.Fatalf("mixed literal list indexed type=%q want empty", got)
	}
}

func TestServerNavigationUsesForInReceiverFields(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Point { x, y }",
		"struct Other { z }",
		"fn id(v) { return v }",
		"fn main() {",
		"  var points = [Point(1, 2), Point(3, 4)]",
		"  for p in points {",
		"    var px = p.x",
		"    var via = id(p).y",
		"  }",
		"  for lit in [Point(5, 6), Point(7, 8)] {",
		"    var ly = lit.y",
		"  }",
		"  for bad in [Point(1, 2), Other(9)] {",
		"    var bz = bad.z",
		"  }",
		"  for key in {\"home\": Point(1, 2)} {",
		"    var kx = key.x",
		"  }",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-for-in.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      752,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": strings.Index(lines[6], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      753,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": strings.Index(lines[7], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      754,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": strings.Index(lines[10], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      755,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.Index(lines[13], ".z") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      756,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 16, "character": strings.Index(lines[16], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      757,
		"method":  "textDocument/references",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 0, "character": strings.Index(lines[0], "x")},
			"context":      map[string]any{"includeDeclaration": true},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	assertDefinition(t, messageByID(t, msgs, 752)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 753)["result"].([]any), uri, 0, 18, 19)
	assertDefinition(t, messageByID(t, msgs, 754)["result"].([]any), uri, 0, 18, 19)
	defs := messageByID(t, msgs, 755)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed for-in member definition=%#v want none", defs)
	}
	defs = messageByID(t, msgs, 756)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("map-key for-in member definition=%#v want none", defs)
	}
	assertLocations(t, messageByID(t, msgs, 757)["result"].([]any), []location{
		{URI: uri, Range: diagnosticRange{Start: position{Line: 0, Character: 15}, End: position{Line: 0, Character: 16}}},
		{URI: uri, Range: diagnosticRange{Start: position{Line: 6, Character: strings.Index(lines[6], ".x") + 1}, End: position{Line: 6, Character: strings.Index(lines[6], ".x") + 2}}},
	})
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

func TestServerCompletionUsesExpressionReceiverFields(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Point { x, y }",
		"struct Inner { x, z }",
		"struct Outer { inner, other }",
		"fn make_point() { return Point(3, 4) }",
		"fn main() {",
		"  var direct = Point(1, 2).",
		"  var factory = make_point().x",
		"  var nested = Outer(Inner(1), Point(0, 0)).inner.",
		"  var nested_exact = Outer(Inner(1), Point(0, 0)).inner.x",
		"  var local = Point(9, 10)",
		"  var local_comp = local.",
		"  var points = [Point(1, 2), Point(3, 4)]",
		"  for p in points {",
		"    var loop_comp = p.",
		"  }",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-expression-completion.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      401,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 5, "character": strings.LastIndex(lines[5], ".") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      402,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 6, "character": len([]rune(lines[6]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      403,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 7, "character": strings.LastIndex(lines[7], ".") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      404,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": len([]rune(lines[8]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      405,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": strings.LastIndex(lines[10], ".") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      406,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.LastIndex(lines[13], ".") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	direct := messageByID(t, msgs, 401)["result"].([]any)
	if !hasCompletion(direct, "x", 5) || !hasCompletion(direct, "y", 5) || hasCompletion(direct, "return", 14) {
		t.Fatalf("direct expression completion mismatch: %#v", direct)
	}
	factory := messageByID(t, msgs, 402)["result"].([]any)
	if !hasCompletion(factory, "x", 5) || hasCompletion(factory, "y", 5) {
		t.Fatalf("factory expression completion mismatch: %#v", factory)
	}
	nested := messageByID(t, msgs, 403)["result"].([]any)
	if !hasCompletion(nested, "x", 5) || !hasCompletion(nested, "z", 5) || hasCompletion(nested, "other", 5) {
		t.Fatalf("constructed-field completion mismatch: %#v", nested)
	}
	nestedExact := messageByID(t, msgs, 404)["result"].([]any)
	if !hasCompletion(nestedExact, "x", 5) || hasCompletion(nestedExact, "z", 5) {
		t.Fatalf("constructed-field filtered completion mismatch: %#v", nestedExact)
	}
	local := messageByID(t, msgs, 405)["result"].([]any)
	if !hasCompletion(local, "x", 5) || !hasCompletion(local, "y", 5) || hasCompletion(local, "z", 5) {
		t.Fatalf("local receiver completion mismatch: %#v", local)
	}
	loop := messageByID(t, msgs, 406)["result"].([]any)
	if !hasCompletion(loop, "x", 5) || !hasCompletion(loop, "y", 5) || hasCompletion(loop, "z", 5) {
		t.Fatalf("for-in receiver completion mismatch: %#v", loop)
	}
}
