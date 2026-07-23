package orenlsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"testing"
)

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

func assertStringList(t *testing.T, got []any, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("list=%#v want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("list[%d]=%#v want %q; list=%#v", i, got[i], want[i], got)
		}
	}
}

func expandSemanticTokenData(raw []any) []semanticTokenInfo {
	var out []semanticTokenInfo
	line := 0
	character := 0
	for i := 0; i+4 < len(raw); i += 5 {
		lineDelta := int(raw[i].(float64))
		charDelta := int(raw[i+1].(float64))
		if len(out) == 0 {
			line = lineDelta
			character = charDelta
		} else {
			line += lineDelta
			if lineDelta == 0 {
				character += charDelta
			} else {
				character = charDelta
			}
		}
		out = append(out, semanticTokenInfo{
			Line:      line,
			Character: character,
			Length:    int(raw[i+2].(float64)),
			Type:      int(raw[i+3].(float64)),
			Modifiers: int(raw[i+4].(float64)),
		})
	}
	return out
}

func assertDefinition(t *testing.T, defs []any, uri string, line, startChar, endChar float64) {
	t.Helper()
	if len(defs) != 1 {
		t.Fatalf("definitions=%#v want one", defs)
	}
	loc := defs[0].(map[string]any)
	if loc["uri"] != uri {
		t.Fatalf("definition uri=%#v want %q", loc["uri"], uri)
	}
	rng := loc["range"].(map[string]any)
	start := rng["start"].(map[string]any)
	end := rng["end"].(map[string]any)
	if start["line"] != line || start["character"] != startChar || end["line"] != line || end["character"] != endChar {
		t.Fatalf("definition range=%#v want line=%v chars=%v..%v", rng, line, startChar, endChar)
	}
}

func assertLocations(t *testing.T, got []any, want []location) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("locations=%#v want %#v", got, want)
	}
	for i, value := range got {
		loc := value.(map[string]any)
		if loc["uri"] != want[i].URI {
			t.Fatalf("location[%d] uri=%#v want %q; locations=%#v", i, loc["uri"], want[i].URI, got)
		}
		rng := loc["range"].(map[string]any)
		start := rng["start"].(map[string]any)
		end := rng["end"].(map[string]any)
		if int(start["line"].(float64)) != want[i].Range.Start.Line ||
			int(start["character"].(float64)) != want[i].Range.Start.Character ||
			int(end["line"].(float64)) != want[i].Range.End.Line ||
			int(end["character"].(float64)) != want[i].Range.End.Character {
			t.Fatalf("location[%d] range=%#v want %#v", i, rng, want[i].Range)
		}
	}
}

func assertRangeMap(t *testing.T, got map[string]any, want diagnosticRange) {
	t.Helper()
	start := got["start"].(map[string]any)
	end := got["end"].(map[string]any)
	if int(start["line"].(float64)) != want.Start.Line ||
		int(start["character"].(float64)) != want.Start.Character ||
		int(end["line"].(float64)) != want.End.Line ||
		int(end["character"].(float64)) != want.End.Character {
		t.Fatalf("range=%#v want %#v", got, want)
	}
}

func assertWorkspaceEdit(t *testing.T, got map[string]any, uri, newText string, want []diagnosticRange) {
	t.Helper()
	changes := got["changes"].(map[string]any)
	if len(want) == 0 {
		if len(changes) != 0 {
			t.Fatalf("workspace edit=%#v want no changes", got)
		}
		return
	}
	rawEdits, ok := changes[uri].([]any)
	if !ok {
		t.Fatalf("workspace edit changes=%#v missing uri %q", changes, uri)
	}
	if len(rawEdits) != len(want) {
		t.Fatalf("workspace edits=%#v want %d edits", rawEdits, len(want))
	}
	for i, raw := range rawEdits {
		edit := raw.(map[string]any)
		if edit["newText"] != newText {
			t.Fatalf("workspace edit[%d] newText=%#v want %q", i, edit["newText"], newText)
		}
		assertRangeMap(t, edit["range"].(map[string]any), want[i])
	}
}

func assertWorkspaceEditFileCount(t *testing.T, got map[string]any, want int) {
	t.Helper()
	changes := got["changes"].(map[string]any)
	if len(changes) != want {
		t.Fatalf("workspace edit changes=%#v want %d file(s)", changes, want)
	}
}

func diagnosticsWithSource(diags []diagnostic, source string) []diagnostic {
	out := []diagnostic{}
	for _, diag := range diags {
		if diag.Source == source {
			out = append(out, diag)
		}
	}
	return out
}
