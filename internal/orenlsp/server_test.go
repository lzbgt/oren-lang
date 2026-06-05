package orenlsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"strings"
	"testing"
)

func TestServerInitializeAndShutdown(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{}})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "id": 2, "method": "shutdown"})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	if len(msgs) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(msgs), msgs)
	}
	if msgs[0]["id"].(float64) != 1 {
		t.Fatalf("initialize id mismatch: %#v", msgs[0])
	}
	result := msgs[0]["result"].(map[string]any)
	caps := result["capabilities"].(map[string]any)
	if _, ok := caps["textDocumentSync"].(map[string]any); !ok {
		t.Fatalf("missing textDocumentSync capability: %#v", caps)
	}
	if _, ok := caps["completionProvider"].(map[string]any); !ok {
		t.Fatalf("missing completionProvider capability: %#v", caps)
	}
	if caps["documentSymbolProvider"] != true {
		t.Fatalf("missing documentSymbolProvider capability: %#v", caps)
	}
}

func TestServerPublishesDiagnosticsOnDidOpenAndDidChange(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{
				"uri":  "file:///bad.oren",
				"text": "fn main() {\n  print(\"ok\")\n",
			},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didChange",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///bad.oren"},
			"contentChanges": []map[string]any{{
				"text": "fn main() {\n  print(\"ok\")\n}\n",
			}},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	if len(msgs) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(msgs), msgs)
	}
	first := diagnosticsFromMessage(t, msgs[0])
	if len(first) != 1 {
		t.Fatalf("first diagnostics mismatch: %#v", first)
	}
	firstDiag := first[0].(map[string]any)
	if !strings.Contains(firstDiag["message"].(string), "unclosed delimiter") {
		t.Fatalf("first diagnostics mismatch: %#v", first)
	}
	second := diagnosticsFromMessage(t, msgs[1])
	if len(second) != 0 {
		t.Fatalf("second diagnostics=%#v want none", second)
	}
}

func TestDiagnoseIgnoresLineCommentDelimiters(t *testing.T) {
	got := diagnose("fn main() {\n  // ignored }\n}\n")
	if len(got) != 0 {
		t.Fatalf("diagnostics=%#v want none", got)
	}
}

func TestServerCompletionAndDocumentSymbols(t *testing.T) {
	var in bytes.Buffer
	text := strings.Join([]string{
		"import math \"std:math\"",
		"struct Vec2 { x, y }",
		"class Runner {}",
		"var answer = 42",
		"fn compute() { return answer }",
		"",
	}, "\n")
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren", "text": text},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      7,
		"method":  "textDocument/documentSymbol",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      8,
		"method":  "textDocument/completion",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///symbols.oren"},
			"position":     map[string]any{"line": 4, "character": 2},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	symbolResp := messageByID(t, msgs, 7)
	symbols := symbolResp["result"].([]any)
	assertLabels(t, symbols, []string{"math", "Vec2", "Runner", "answer", "compute"})
	if symbols[0].(map[string]any)["kind"].(float64) != 2 {
		t.Fatalf("first symbol=%#v want module kind", symbols[0])
	}
	completionResp := messageByID(t, msgs, 8)
	items := completionResp["result"].([]any)
	if !hasCompletion(items, "compute", 3) || !hasCompletion(items, "answer", 6) || !hasCompletion(items, "return", 14) {
		t.Fatalf("completion items missing expected entries: %#v", items)
	}
}

func TestServerDidCloseDropsDocumentSymbols(t *testing.T) {
	var in bytes.Buffer
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didOpen",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren", "text": "fn stale() {}\n"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/didClose",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{
		"jsonrpc": "2.0",
		"id":      9,
		"method":  "textDocument/documentSymbol",
		"params": map[string]any{
			"textDocument": map[string]any{"uri": "file:///closed.oren"},
		},
	})
	writeTestMessage(t, &in, map[string]any{"jsonrpc": "2.0", "method": "exit"})

	var out bytes.Buffer
	if err := NewServer(&in, &out).Run(); err != nil {
		t.Fatalf("Run error: %v", err)
	}
	msgs := readTestMessages(t, out.Bytes())
	symbols := messageByID(t, msgs, 9)["result"].([]any)
	if len(symbols) != 0 {
		t.Fatalf("symbols after close=%#v want none", symbols)
	}
}

func writeTestMessage(t *testing.T, w *bytes.Buffer, v any) {
	t.Helper()
	msg, err := EncodeMessage(v)
	if err != nil {
		t.Fatalf("EncodeMessage: %v", err)
	}
	w.Write(msg)
}

func readTestMessages(t *testing.T, raw []byte) []map[string]any {
	t.Helper()
	r := bufio.NewReader(bytes.NewReader(raw))
	var out []map[string]any
	for {
		body, err := readMessage(r)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("readMessage: %v", err)
		}
		var msg map[string]any
		if err := json.Unmarshal(body, &msg); err != nil {
			t.Fatalf("json: %v", err)
		}
		out = append(out, msg)
	}
	return out
}

func diagnosticsFromMessage(t *testing.T, msg map[string]any) []any {
	t.Helper()
	if msg["method"] != "textDocument/publishDiagnostics" {
		t.Fatalf("method=%#v want publishDiagnostics", msg["method"])
	}
	params := msg["params"].(map[string]any)
	return params["diagnostics"].([]any)
}

func messageByID(t *testing.T, msgs []map[string]any, id float64) map[string]any {
	t.Helper()
	for _, msg := range msgs {
		if msgID, ok := msg["id"].(float64); ok && msgID == id {
			return msg
		}
	}
	t.Fatalf("missing response id=%v in %#v", id, msgs)
	return nil
}

func assertLabels(t *testing.T, values []any, want []string) {
	t.Helper()
	if len(values) != len(want) {
		t.Fatalf("values=%#v want labels %#v", values, want)
	}
	for i, value := range values {
		got := value.(map[string]any)["name"].(string)
		if got != want[i] {
			t.Fatalf("label[%d]=%q want %q; values=%#v", i, got, want[i], values)
		}
	}
}

func hasCompletion(items []any, label string, kind float64) bool {
	for _, item := range items {
		obj := item.(map[string]any)
		if obj["label"] == label && obj["kind"] == kind {
			return true
		}
	}
	return false
}
