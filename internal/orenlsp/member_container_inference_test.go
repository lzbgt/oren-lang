package orenlsp

import (
	"bytes"
	"strings"
	"testing"
)

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

func TestServerNavigationUsesIndexedMapValueFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn main() {",
		"  var by = {\"home\": Outer(Inner(Leaf(1, 2))), \"away\": Outer(Inner(Leaf(3, 4)))}",
		"  var mixed = {\"home\": Outer(Inner(Leaf(5, 6))), \"bad\": Outer(Other(7))}",
		"  var selected = by[\"home\"]",
		"  var c0 = by[\"home\"].inner.leaf.",
		"  var d0 = by[\"away\"].inner.leaf.x",
		"  var d1 = selected.inner.leaf.y",
		"  return mixed[\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-indexed-map-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      821,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 8, "character": len([]rune(lines[8]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      822,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 9, "character": strings.LastIndex(lines[9], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      823,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 10, "character": strings.LastIndex(lines[10], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      824,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 11, "character": strings.LastIndex(lines[11], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 821)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("indexed map value field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 822)["result"].([]any), uri, 0, 14, 15)
	assertDefinition(t, messageByID(t, msgs, 823)["result"].([]any), uri, 0, 17, 18)
	defs := messageByID(t, msgs, 824)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed indexed map value field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesReturnedMapValueFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_map(items) { return items }",
		"fn identity_map_bad(items) { return items }",
		"fn main() {",
		"  var by = {\"home\": Outer(Inner(Leaf(1, 2))), \"away\": Outer(Inner(Leaf(3, 4)))}",
		"  var mixed = {\"home\": Outer(Inner(Leaf(5, 6))), \"bad\": Outer(Other(7))}",
		"  var returned = identity_map(by)",
		"  var returned_mixed = identity_map_bad(mixed)",
		"  var selected = returned[\"home\"]",
		"  var c0 = returned[\"away\"].inner.leaf.",
		"  var d0 = selected.inner.leaf.x",
		"  return returned_mixed[\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-returned-map-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      825,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 12, "character": len([]rune(lines[12]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      826,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.LastIndex(lines[13], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      827,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 14, "character": strings.LastIndex(lines[14], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 825)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("returned map value field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 826)["result"].([]any), uri, 0, 14, 15)
	defs := messageByID(t, msgs, 827)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed returned map value field-chain definition=%#v want none", defs)
	}
}

func TestInferFunctionReturnTypeUsesForInElements(t *testing.T) {
	text := strings.Join([]string{
		"struct Point { x, y }",
		"fn first(points) {",
		"  for p in points {",
		"    return p",
		"  }",
		"}",
		"var points = [Point(1, 2), Point(3, 4)]",
		"var picked = first(points)",
		"",
	}, "\n")
	_, env := typedMemberAnalysisEnv(text, "file:///infer-for-in-return.oren", nil, nil)
	if got := env.Functions["first"]; got != "Point" {
		t.Fatalf("first return type=%q want Point; params=%#v", got, env.Params["first"])
	}
	if got := inferExpressionType(parseMemberReceiverExpression("picked"), env, []map[string]string{{"picked": env.Functions["first"]}}); got != "Point" {
		t.Fatalf("picked inferred type=%q want Point", got)
	}
}

func TestInferFunctionReturnMapValueFieldTypesUsesParams(t *testing.T) {
	text := strings.Join([]string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"fn identity_map(items) { return items }",
		"var by = {\"home\": Outer(Inner(Leaf(1, 2))), \"away\": Outer(Inner(Leaf(3, 4)))}",
		"var returned = identity_map(by)",
		"",
	}, "\n")
	_, env := typedMemberAnalysisEnv(text, "file:///infer-returned-map-values.oren", nil, nil)
	if got := env.Params["identity_map"]["items{}.inner.leaf"]; got != "Leaf" {
		t.Fatalf("identity_map param map-value leaf=%q want Leaf; params=%#v", got, env.Params["identity_map"])
	}
	if got := env.FunctionMapValueFields["identity_map"]["inner.leaf"]; got != "Leaf" {
		t.Fatalf("identity_map returned map-value leaf=%q want Leaf; fields=%#v", got, env.FunctionMapValueFields["identity_map"])
	}
	stack := []map[string]string{{"returned": env.Functions["identity_map"]}}
	setInferredMapValueFieldTypes("returned", env.FunctionMapValueFields["identity_map"], stack[0])
	if got := inferExpressionType(parseMemberReceiverExpression("returned[\"home\"].inner.leaf"), env, stack); got != "Leaf" {
		t.Fatalf("returned map nested value type=%q want Leaf", got)
	}
}

func TestInferFunctionReturnContainerFieldTypesUsesBranches(t *testing.T) {
	text := strings.Join([]string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn choose_list(flag) {",
		"  if flag { return [Outer(Inner(Leaf(1, 2)))] } else { return [Outer(Inner(Leaf(3, 4)))] }",
		"}",
		"fn choose_map(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(1, 2)))} } else { return {\"away\": Outer(Inner(Leaf(3, 4)))} }",
		"}",
		"fn choose_map_bad(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(1, 2)))} } else { return {\"bad\": Outer(Other(7))} }",
		"}",
		"",
	}, "\n")
	_, env := typedMemberAnalysisEnv(text, "file:///infer-returned-container-branches.oren", nil, nil)
	if got := env.FunctionElementFields["choose_list"]["inner.leaf"]; got != "Leaf" {
		t.Fatalf("choose_list returned element leaf=%q want Leaf; fields=%#v", got, env.FunctionElementFields["choose_list"])
	}
	if got := env.FunctionMapValueFields["choose_map"]["inner.leaf"]; got != "Leaf" {
		t.Fatalf("choose_map returned map value leaf=%q want Leaf; fields=%#v", got, env.FunctionMapValueFields["choose_map"])
	}
	if got := env.FunctionMapValueFields["choose_map_bad"]["inner.leaf"]; got != "" {
		t.Fatalf("choose_map_bad returned map value leaf=%q want empty; fields=%#v", got, env.FunctionMapValueFields["choose_map_bad"])
	}
}

func TestServerNavigationUsesConditionalReturnedMapValueFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn choose_map(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(1, 2)))} } else { return {\"away\": Outer(Inner(Leaf(3, 4)))} }",
		"}",
		"fn choose_map_bad(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(5, 6)))} } else { return {\"bad\": Outer(Other(7))} }",
		"}",
		"fn main() {",
		"  var returned = choose_map(true)",
		"  var c0 = returned[\"home\"].inner.leaf.",
		"  var d0 = choose_map(false)[\"away\"].inner.leaf.x",
		"  return choose_map_bad(false)[\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-conditional-returned-map-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      828,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 12, "character": len([]rune(lines[12]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      829,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.LastIndex(lines[13], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      830,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 14, "character": strings.LastIndex(lines[14], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 828)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("conditional returned map field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 829)["result"].([]any), uri, 0, 14, 15)
	defs := messageByID(t, msgs, 830)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed conditional returned map field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesConditionalAssignedContainerFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn choose_list(flag) {",
		"  if flag { return [Outer(Inner(Leaf(1, 2)))] } else { return [Outer(Inner(Leaf(3, 4)))] }",
		"}",
		"fn choose_map(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(1, 2)))} } else { return {\"away\": Outer(Inner(Leaf(3, 4)))} }",
		"}",
		"fn choose_map_bad(flag) {",
		"  if flag { return {\"home\": Outer(Inner(Leaf(5, 6)))} } else { return {\"bad\": Outer(Other(7))} }",
		"}",
		"fn main(flag) {",
		"  var returned = {}",
		"  if flag { returned = choose_map(true) } else { returned = choose_map(false) }",
		"  var list = []",
		"  if flag { list = choose_list(true) } else { list = choose_list(false) }",
		"  for item in list {",
		"    var c0 = item.inner.leaf.",
		"  }",
		"  var d0 = returned[\"home\"].inner.leaf.x",
		"  var mixed = {}",
		"  if flag { mixed = choose_map(true) } else { mixed = choose_map_bad(false) }",
		"  return mixed[\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-conditional-assigned-container-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      831,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 19, "character": len([]rune(lines[19]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      832,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 21, "character": strings.LastIndex(lines[21], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      833,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 24, "character": strings.LastIndex(lines[24], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 831)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("conditional assigned list field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 832)["result"].([]any), uri, 0, 14, 15)
	defs := messageByID(t, msgs, 833)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed conditional assigned map field-chain definition=%#v want none", defs)
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

func TestServerNavigationUsesForInReturnReceiverFields(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Point { x, y }",
		"struct Other { z }",
		"fn first(points) {",
		"  for p in points {",
		"    return p",
		"  }",
		"}",
		"var points = [Point(1, 2), Point(3, 4)]",
		"var mixed = [Point(1, 2), Other(9)]",
		"var picked = first(points)",
		"var bad = first(mixed)",
		"fn main() {",
		"  var direct = first(points).",
		"  return picked.x + first(points).y + bad.z",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-for-in-return.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      758,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 12, "character": len([]rune(lines[12]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      759,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.Index(lines[13], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      760,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.Index(lines[13], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      761,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 13, "character": strings.Index(lines[13], ".z") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 758)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("for-in return completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 759)["result"].([]any), uri, 0, 15, 16)
	assertDefinition(t, messageByID(t, msgs, 760)["result"].([]any), uri, 0, 18, 19)
	defs := messageByID(t, msgs, 761)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed for-in return member definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesForInElementFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn first_leaf(items) {",
		"  for item in items {",
		"    return item.inner.leaf",
		"  }",
		"}",
		"fn first_leaf_bad(items) {",
		"  for item in items {",
		"    return item.inner.leaf",
		"  }",
		"}",
		"var outers = [Outer(Inner(Leaf(1, 2))), Outer(Inner(Leaf(3, 4)))]",
		"var mixed = [Outer(Inner(Leaf(5, 6))), Outer(Other(7))]",
		"var picked = first_leaf(outers)",
		"var bad = first_leaf_bad(mixed)",
		"fn main() {",
		"  for item in outers {",
		"    var comp = item.inner.leaf.",
		"    var direct = item.inner.leaf.x",
		"  }",
		"  return picked.y + first_leaf(outers).x + bad.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-for-in-element-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      762,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 20, "character": len([]rune(lines[20]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      763,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 21, "character": strings.LastIndex(lines[21], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      764,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": strings.Index(lines[23], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      765,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": strings.Index(lines[23], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      766,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": strings.LastIndex(lines[23], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 762)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("for-in element field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 763)["result"].([]any), uri, 0, 14, 15)
	assertDefinition(t, messageByID(t, msgs, 764)["result"].([]any), uri, 0, 17, 18)
	assertDefinition(t, messageByID(t, msgs, 765)["result"].([]any), uri, 0, 14, 15)
	defs := messageByID(t, msgs, 766)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed for-in element field-chain definition=%#v want none", defs)
	}
}

func TestServerNavigationUsesReturnedListElementFieldChains(t *testing.T) {
	var in bytes.Buffer
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_list(items) {",
		"  return items",
		"}",
		"fn identity_bad(items) {",
		"  return items",
		"}",
		"var outers = [Outer(Inner(Leaf(1, 2))), Outer(Inner(Leaf(3, 4)))]",
		"var mixed = [Outer(Inner(Leaf(5, 6))), Outer(Other(7))]",
		"var returned = identity_list(outers)",
		"var bad = identity_bad(mixed)",
		"fn main() {",
		"  for item in identity_list(outers) {",
		"    var comp = item.inner.leaf.",
		"    var direct = item.inner.leaf.x",
		"  }",
		"  for from_return in returned {",
		"    var assigned = from_return.inner.leaf.y",
		"  }",
		"  for bad_item in bad {",
		"    var blocked = bad_item.inner.leaf.x",
		"  }",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///typed-member-returned-list-element-field-chain.oren"
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri, "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      767,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 16, "character": len([]rune(lines[16]))},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      768,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 17, "character": strings.LastIndex(lines[17], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      769,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 20, "character": strings.LastIndex(lines[20], ".y") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      770,
		"method":  "textDocument/definition",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": uri},
			"position":     map[string]any{"line": 23, "character": strings.LastIndex(lines[23], ".x") + 1},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	items := messageByID(t, msgs, 767)["result"].([]any)
	if !hasCompletion(items, "x", 5) || !hasCompletion(items, "y", 5) || hasCompletion(items, "z", 5) {
		t.Fatalf("returned-list element field-chain completion mismatch: %#v", items)
	}
	assertDefinition(t, messageByID(t, msgs, 768)["result"].([]any), uri, 0, 14, 15)
	assertDefinition(t, messageByID(t, msgs, 769)["result"].([]any), uri, 0, 17, 18)
	defs := messageByID(t, msgs, 770)["result"].([]any)
	if len(defs) != 0 {
		t.Fatalf("mixed returned-list element field-chain definition=%#v want none", defs)
	}
}
