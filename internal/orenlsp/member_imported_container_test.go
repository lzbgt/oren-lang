package orenlsp

import (
	"strings"
	"testing"
)

func TestTypedMemberAnalysisUsesImportedReturnedContainerFieldChains(t *testing.T) {
	shapesLines := []string{
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
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var returned = shapes.choose_map(true)",
		"var list = shapes.choose_list(false)",
		"fn main() {",
		"  var c0 = returned[\"home\"].inner.leaf.",
		"  for item in list {",
		"    var d0 = item.inner.leaf.x",
		"  }",
		"  return shapes.choose_map(false)[\"away\"].inner.leaf.y",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := "file:///main.oren"
	shapesURI := "file:///shapes.oren"
	importedDocs := []documentSnapshot{{URI: shapesURI, Text: shapesText}}
	aliasByURI := map[string]string{shapesURI: "shapes"}

	items, found := typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      4,
		Character: len([]rune(mainLines[4])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported returned map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(mainText, mainURI, position{
		Line:      6,
		Character: strings.LastIndex(mainLines[6], ".x") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "x" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported returned list field-chain x match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      8,
		Character: strings.LastIndex(mainLines[8], ".y") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported direct returned map field-chain y match=%#v ok=%v", match, ok)
	}
}

func TestTypedMemberAnalysisUsesImportedParameterReturnedContainerFieldChains(t *testing.T) {
	shapesLines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_list(items) { return items }",
		"fn identity_map(items) { return items }",
		"fn identity_map_mixed(items) { return items }",
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var list = [shapes.Outer(shapes.Inner(shapes.Leaf(1, 2))), shapes.Outer(shapes.Inner(shapes.Leaf(3, 4)))]",
		"var by = {\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(5, 6))), \"away\": shapes.Outer(shapes.Inner(shapes.Leaf(7, 8)))}",
		"var mixed = {\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(9, 10))), \"bad\": shapes.Outer(shapes.Other(11))}",
		"var returned_list = shapes.identity_list(list)",
		"var returned_map = shapes.identity_map(by)",
		"var returned_mixed = shapes.identity_map_mixed(mixed)",
		"fn main() {",
		"  for item in returned_list {",
		"    var c0 = item.inner.leaf.",
		"  }",
		"  var d0 = returned_map[\"home\"].inner.leaf.x",
		"  return returned_mixed[\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := "file:///main.oren"
	shapesURI := "file:///shapes.oren"
	importedDocs := []documentSnapshot{{URI: shapesURI, Text: shapesText}}
	aliasByURI := map[string]string{shapesURI: "shapes"}

	items, found := typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      9,
		Character: len([]rune(mainLines[9])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported parameter-returned list field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(mainText, mainURI, position{
		Line:      11,
		Character: strings.LastIndex(mainLines[11], ".x") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "x" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported parameter-returned map field-chain x match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      12,
		Character: strings.LastIndex(mainLines[12], ".x") + 1,
	}, importedDocs, aliasByURI)
	if ok {
		t.Fatalf("mixed imported parameter-returned map field-chain match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesImportedParameterReturnedNestedContainerFieldChains(t *testing.T) {
	shapesLines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn identity_groups(items) { return items }",
		"fn identity_by_group(items) { return items }",
		"fn identity_groups_mixed(items) { return items }",
		"fn identity_by_group_mixed(items) { return items }",
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var groups = [{\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(1, 2)))}, {\"away\": shapes.Outer(shapes.Inner(shapes.Leaf(3, 4)))}]",
		"var by_group = {\"team\": [shapes.Outer(shapes.Inner(shapes.Leaf(5, 6)))], \"away\": [shapes.Outer(shapes.Inner(shapes.Leaf(7, 8)))]}",
		"var mixed = [{\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(9, 10)))}, {\"bad\": shapes.Outer(shapes.Other(11))}]",
		"var mixed_by_group = {\"team\": [shapes.Outer(shapes.Inner(shapes.Leaf(12, 13)))], \"bad\": [shapes.Outer(shapes.Other(14))]}",
		"var returned_groups = shapes.identity_groups(groups)",
		"var returned_by_group = shapes.identity_by_group(by_group)",
		"var returned_mixed = shapes.identity_groups_mixed(mixed)",
		"var returned_by_mixed = shapes.identity_by_group_mixed(mixed_by_group)",
		"fn main() {",
		"  var c0 = returned_groups[0][\"home\"].inner.leaf.",
		"  var d0 = returned_by_group[\"team\"][0].inner.leaf.y",
		"  var bad0 = returned_mixed[0][\"bad\"].inner.leaf.x",
		"  return returned_by_mixed[\"bad\"][0].inner.leaf.y",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := "file:///main.oren"
	shapesURI := "file:///shapes.oren"
	importedDocs := []documentSnapshot{{URI: shapesURI, Text: shapesText}}
	aliasByURI := map[string]string{shapesURI: "shapes"}

	items, found := typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      10,
		Character: len([]rune(mainLines[10])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported returned list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(mainText, mainURI, position{
		Line:      11,
		Character: strings.LastIndex(mainLines[11], ".y") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported returned map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      12,
		Character: strings.LastIndex(mainLines[12], ".x") + 1,
	}, importedDocs, aliasByURI)
	if ok {
		t.Fatalf("mixed imported returned list-of-map field-chain match=%#v want none", match)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      13,
		Character: strings.LastIndex(mainLines[13], ".y") + 1,
	}, importedDocs, aliasByURI)
	if ok {
		t.Fatalf("mixed imported returned map-of-list field-chain match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesImportedConstructorFieldNestedContainerFieldChains(t *testing.T) {
	shapesLines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"struct Holder { groups, by_group }",
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var groups = [{\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(1, 2)))}, {\"away\": shapes.Outer(shapes.Inner(shapes.Leaf(3, 4)))}]",
		"var by_group = {\"team\": [shapes.Outer(shapes.Inner(shapes.Leaf(5, 6)))], \"away\": [shapes.Outer(shapes.Inner(shapes.Leaf(7, 8)))]}",
		"var mixed_groups = [{\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(9, 10)))}, {\"bad\": shapes.Outer(shapes.Other(11))}]",
		"var holder = shapes.Holder(groups, by_group)",
		"var mixed_holder = shapes.Holder(mixed_groups, by_group)",
		"fn main() {",
		"  var c0 = holder.groups[0][\"home\"].inner.leaf.",
		"  var d0 = holder.by_group[\"team\"][0].inner.leaf.y",
		"  var alias = holder",
		"  var c1 = alias.groups[1][\"away\"].inner.leaf.",
		"  return mixed_holder.groups[0][\"bad\"].inner.leaf.x",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := "file:///main.oren"
	shapesURI := "file:///shapes.oren"
	importedDocs := []documentSnapshot{{URI: shapesURI, Text: shapesText}}
	aliasByURI := map[string]string{shapesURI: "shapes"}

	items, found := typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      7,
		Character: len([]rune(mainLines[7])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported constructor list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(mainText, mainURI, position{
		Line:      8,
		Character: strings.LastIndex(mainLines[8], ".y") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported constructor map-of-list field-chain y match=%#v ok=%v", match, ok)
	}
	items, found = typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      10,
		Character: len([]rune(mainLines[10])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported constructor alias list-of-map field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      11,
		Character: strings.LastIndex(mainLines[11], ".x") + 1,
	}, importedDocs, aliasByURI)
	if ok {
		t.Fatalf("mixed imported constructor list-of-map field-chain match=%#v want none", match)
	}
}

func TestTypedMemberAnalysisUsesImportedReturnedNestedContainerSelectionFieldChains(t *testing.T) {
	shapesLines := []string{
		"struct Leaf { x, y }",
		"struct Inner { leaf }",
		"struct Outer { inner }",
		"struct Other { z }",
		"fn first_group_item(items) { return items[0][\"home\"] }",
		"fn first_team_item(items) { return items[\"team\"][0] }",
		"fn first_group_item_mixed(items) { return items[0][\"bad\"] }",
		"",
	}
	shapesText := strings.Join(shapesLines, "\n")
	mainLines := []string{
		"import shapes \"shapes.oren\"",
		"var groups = [{\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(1, 2)))}, {\"home\": shapes.Outer(shapes.Inner(shapes.Leaf(3, 4)))}]",
		"var by_group = {\"team\": [shapes.Outer(shapes.Inner(shapes.Leaf(5, 6)))], \"away\": [shapes.Outer(shapes.Inner(shapes.Leaf(7, 8)))]}",
		"var mixed = [{\"bad\": shapes.Outer(shapes.Other(9))}, {\"bad\": shapes.Outer(shapes.Other(10))}]",
		"var picked_group = shapes.first_group_item(groups)",
		"var picked_team = shapes.first_team_item(by_group)",
		"var picked_mixed = shapes.first_group_item_mixed(mixed)",
		"fn main() {",
		"  var c0 = picked_group.inner.leaf.",
		"  var d0 = picked_team.inner.leaf.y",
		"  return picked_mixed.inner.leaf.x",
		"}",
		"",
	}
	mainText := strings.Join(mainLines, "\n")
	mainURI := "file:///main.oren"
	shapesURI := "file:///shapes.oren"
	importedDocs := []documentSnapshot{{URI: shapesURI, Text: shapesText}}
	aliasByURI := map[string]string{shapesURI: "shapes"}

	items, found := typedMemberCompletionItemsAt(mainText, mainURI, position{
		Line:      8,
		Character: len([]rune(mainLines[8])),
	}, importedDocs, aliasByURI)
	if !found || !hasTypedCompletion(items, "x", lspCompletionField) || !hasTypedCompletion(items, "y", lspCompletionField) || hasTypedCompletion(items, "z", lspCompletionField) {
		t.Fatalf("imported returned list-of-map selection field-chain completion mismatch found=%v items=%#v", found, items)
	}
	match, ok := typedMemberSymbolAt(mainText, mainURI, position{
		Line:      9,
		Character: strings.LastIndex(mainLines[9], ".y") + 1,
	}, importedDocs, aliasByURI)
	if !ok || match.URI != shapesURI || match.Symbol.Name != "y" || match.Symbol.Range.Start.Line != 0 {
		t.Fatalf("imported returned map-of-list selection field-chain y match=%#v ok=%v", match, ok)
	}
	match, ok = typedMemberSymbolAt(mainText, mainURI, position{
		Line:      10,
		Character: strings.LastIndex(mainLines[10], ".x") + 1,
	}, importedDocs, aliasByURI)
	if ok {
		t.Fatalf("mixed imported returned nested selection field-chain match=%#v want none", match)
	}
}

func hasTypedCompletion(items []completionItem, label string, kind int) bool {
	for _, item := range items {
		if item.Label == label && item.Kind == kind {
			return true
		}
	}
	return false
}
