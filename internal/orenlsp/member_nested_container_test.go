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
		"  var home = groups[0][\"home\"]",
		"  var c1 = home.inner.leaf.",
		"  var team = by_group[\"team\"]",
		"  var d1 = team[0].inner.leaf.y",
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
		t.Fatalf("aliased list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      14,
		Character: strings.LastIndex(lines[14], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("aliased map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(text, uri, position{
		Line:      16,
		Character: len([]rune(lines[16])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("map-of-list field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      18,
		Character: strings.LastIndex(lines[18], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      19,
		Character: strings.LastIndex(lines[19], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed list-of-map field-chain match=%#v want none", match)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      20,
		Character: strings.LastIndex(lines[20], ".y") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed map-of-list field-chain match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesConstructorFieldNestedContainerFieldChains(t *testing.T) {
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"struct Holder { groups, by_group }",
		"var groups = [{\"home\": Outer(Inner(Leaf(1, 2)))}, {\"away\": Outer(Inner(Leaf(3, 4)))}]",
		"var by_group = {\"team\": [Outer(Inner(Leaf(5, 6)))], \"away\": [Outer(Inner(Leaf(7, 8)))]}",
		"var mixed_groups = [{\"home\": Outer(Inner(Leaf(9, 10)))}, {\"bad\": Outer(Other(11))}]",
		"var holder = Holder(groups, by_group)",
		"var mixed_holder = Holder(mixed_groups, by_group)",
		"fn main() {",
		"  var c0 = holder.groups[0][\"home\"].inner.leaf.",
		"  var d0 = holder.by_group[\"team\"][0].inner.leaf.y",
		"  var alias = holder",
		"  var c1 = alias.groups[1][\"away\"].inner.leaf.",
		"  return mixed_holder.groups[0][\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///constructor-field-nested-container-field-chain.oren"

	items, found := typedMemberCompletionItemsAt(text, uri, position{
		Line:      11,
		Character: len([]rune(lines[11])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("constructor field list-of-map completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(text, uri, position{
		Line:      12,
		Character: strings.LastIndex(lines[12], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("constructor field map-of-list y match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(text, uri, position{
		Line:      14,
		Character: len([]rune(lines[14])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("aliased constructor field list-of-map completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      15,
		Character: strings.LastIndex(lines[15], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed constructor field nested container match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesReturnedNestedContainerFieldChains(t *testing.T) {
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_groups(items) { return items }",
		"fn identity_by_group(items) { return items }",
		"fn identity_groups_mixed(items) { return items }",
		"fn identity_by_group_mixed(items) { return items }",
		"var groups = [{\"home\": Outer(Inner(Leaf(1, 2)))}, {\"away\": Outer(Inner(Leaf(3, 4)))}]",
		"var by_group = {\"team\": [Outer(Inner(Leaf(5, 6)))], \"away\": [Outer(Inner(Leaf(7, 8)))]}",
		"var mixed_groups = [{\"home\": Outer(Inner(Leaf(9, 10)))}, {\"bad\": Outer(Other(11))}]",
		"var mixed_by_group = {\"team\": [Outer(Inner(Leaf(12, 13)))], \"bad\": [Outer(Other(14))]}",
		"var returned_groups = identity_groups(groups)",
		"var returned_by_group = identity_by_group(by_group)",
		"var returned_mixed = identity_groups_mixed(mixed_groups)",
		"var returned_by_mixed = identity_by_group_mixed(mixed_by_group)",
		"fn main() {",
		"  var c0 = returned_groups[0][\"home\"].inner.leaf.",
		"  var d0 = returned_by_group[\"team\"][0].inner.leaf.y",
		"  var bad0 = returned_mixed[0][\"bad\"].inner.leaf.x",
		"  return returned_by_mixed[\"bad\"][0].inner.leaf.y",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///returned-nested-container-field-chain.oren"

	items, found := typedMemberCompletionItemsAt(text, uri, position{
		Line:      17,
		Character: len([]rune(lines[17])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("returned list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(text, uri, position{
		Line:      18,
		Character: strings.LastIndex(lines[18], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("returned map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      19,
		Character: strings.LastIndex(lines[19], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed returned list-of-map field-chain match=%#v want none", match)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      20,
		Character: strings.LastIndex(lines[20], ".y") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed returned map-of-list field-chain match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesReturnedNestedContainerSelectionFieldChains(t *testing.T) {
	lines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn first_group_item(items) { return items[0][\"home\"] }",
		"fn first_team_item(items) { return items[\"team\"][0] }",
		"fn first_group_item_mixed(items) { return items[0][\"bad\"] }",
		"var groups = [{\"home\": Outer(Inner(Leaf(1, 2)))}, {\"home\": Outer(Inner(Leaf(3, 4)))}]",
		"var by_group = {\"team\": [Outer(Inner(Leaf(5, 6)))], \"away\": [Outer(Inner(Leaf(7, 8)))]}",
		"var mixed_groups = [{\"bad\": Outer(Other(9))}, {\"bad\": Outer(Other(10))}]",
		"var picked_group = first_group_item(groups)",
		"var picked_team = first_team_item(by_group)",
		"var picked_mixed = first_group_item_mixed(mixed_groups)",
		"fn main() {",
		"  var c0 = picked_group.inner.leaf.",
		"  var d0 = picked_team.inner.leaf.y",
		"  return picked_mixed.inner.leaf.x",
		"}",
		"",
	}
	text := strings.Join(lines, "\n")
	uri := "file:///returned-nested-container-selection-field-chain.oren"

	items, found := typedMemberCompletionItemsAt(text, uri, position{
		Line:      14,
		Character: len([]rune(lines[14])),
	}, nil, nil)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("returned list-of-map selection field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(text, uri, position{
		Line:      15,
		Character: strings.LastIndex(lines[15], ".y") + 1,
	}, nil, nil)
	if !ok || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("returned map-of-list selection field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(text, uri, position{
		Line:      16,
		Character: strings.LastIndex(lines[16], ".x") + 1,
	}, nil, nil)
	if ok {
		t.Fatalf("mixed returned nested selection field-chain match=%#v want none", match)
	}
}
