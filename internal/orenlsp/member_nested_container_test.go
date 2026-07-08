package orenlsp

import (
	"strings"
	"testing"
)

func TestTypedMemberAnalysisUsesNestedContainerFieldChains(t *testing.T) {
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"var groups = [{\"home\": Outer(Inner(Leaf(1, 2)))}, {\"away\": Outer(Inner(Leaf(3, 4)))}]",
		"var mixed_groups = [{\"home\": Outer(Inner(Leaf(5, 6)))}, {\"bad\": Outer(Other(7))}]",
		"var by_group = {\"team\": [Outer(Inner(Leaf(8, 9)))], \"away\": [Outer(Inner(Leaf(10, 11)))]}",
		"var mixed_by_group = {\"team\": [Outer(Inner(Leaf(12, 13)))], \"bad\": [Outer(Other(14))]}",
		"fn main() {",
		"  var c0 = groups[0][\"home\"].inner.leaf.",
		"  var d0 = groups[1][\"away\"].inner.leaf.x",
		"  for item in by_group[\"team\"] {",
		"    var e0 = item.inner.leaf.",
		"  }",
		"  var f0 = by_group[\"away\"][0].inner.leaf.y",
		"  var bad0 = mixed_groups[0][\"home\"].inner.leaf.x",
		"  return mixed_by_group[\"bad\"][0].inner.leaf.y",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///nested-container-field-chain.oren"

	items, found := typedMemberCompletionItemsAt(text, uri, position{
		Line:      9,
		Character: len([]rune(lines[9])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(text, uri, position{
		Line:      10,
		Character: strings.LastIndex(lines[10], ".x") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "x" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("list-of-map field-chain x match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(text, uri, position{
		Line:      12,
		Character: len([]rune(lines[12])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("map-of-list field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      14,
		Character: strings.LastIndex(lines[14], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      15,
		Character: strings.LastIndex(lines[15], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed list-of-map field-chain match=%#v want none", match)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      16,
		Character: strings.LastIndex(lines[16], ".y") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed map-of-list field-chain match=%#v want none", match)
	}
}
