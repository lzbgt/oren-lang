package orenlsp

import (
	"bytes"
	"strings"
	"testing"
)

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
