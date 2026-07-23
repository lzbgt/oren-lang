package orenlsp

import "fmt"

type hoverResult struct {
	Contents hoverContents   `json:"contents"`
	Range    diagnosticRange `json:"range"`
}

type hoverContents struct {
	Kind  string `json:"kind"`
	Value string `json:"value"`
}

type documentHighlight struct {
	Range diagnosticRange `json:"range"`
	Kind  int             `json:"kind"`
}

const documentHighlightText = 1

func (s *Server) hover(uri string, pos position) any {
	text := s.docs[uri]
	name := wordAtPosition(text, pos)
	if name == "" {
		return nil
	}
	importedDocs := s.importedDocumentSnapshots(uri, text)
	aliasByURI := s.importedAliasByURI(uri, text)
	if match, ok := typedMemberSymbolAt(text, uri, pos, importedDocs, aliasByURI); ok {
		return hoverForResolvedSymbol(match)
	}
	if match, ok := scopedParameterSymbolAt(text, uri, pos); ok {
		return hoverForResolvedSymbol(match)
	}
	if match, ok := scopedLocalSymbolAt(text, uri, pos); ok {
		return hoverForResolvedSymbol(match)
	}
	match, ok := s.resolveSymbol(uri, text, name)
	if !ok {
		return nil
	}
	return hoverForResolvedSymbol(match)
}

func (s *Server) documentHighlights(uri string, pos position) []documentHighlight {
	if locs, _, ok := s.exactRenameLocations(uri, pos); ok {
		return documentHighlightsForURI(uri, locs)
	}
	return documentHighlightsForURI(uri, s.references(uri, pos, true))
}

func documentHighlightsForURI(uri string, locs []location) []documentHighlight {
	out := make([]documentHighlight, 0, len(locs))
	for _, loc := range uniqueLocations(locs) {
		if loc.URI != uri {
			continue
		}
		out = append(out, documentHighlight{Range: loc.Range, Kind: documentHighlightText})
	}
	return out
}

func hoverForResolvedSymbol(match resolvedSymbol) hoverResult {
	value := fmt.Sprintf("%s %s", match.Symbol.Kind, match.Symbol.Name)
	if match.Symbol.Detail != "" && match.Symbol.Detail != match.Symbol.Kind {
		value += "\n" + match.Symbol.Detail
	}
	value += "\n" + match.URI
	return hoverResult{
		Contents: hoverContents{Kind: "plaintext", Value: value},
		Range:    match.Symbol.Range,
	}
}

func (s *Server) references(uri string, pos position, includeDeclaration bool) []location {
	text := s.docs[uri]
	name := wordAtPosition(text, pos)
	if name == "" {
		return []location{}
	}
	importedDocs := s.importedDocumentSnapshots(uri, text)
	aliasByURI := s.importedAliasByURI(uri, text)
	if refs, ok := typedMemberReferencesAt(text, uri, pos, includeDeclaration, importedDocs, aliasByURI); ok {
		return refs
	}
	if refs, ok := scopedParameterReferencesAt(text, uri, pos, includeDeclaration); ok {
		return refs
	}
	if refs, ok := scopedLocalReferencesAt(text, uri, pos, includeDeclaration); ok {
		return refs
	}
	docs := append([]documentSnapshot{{URI: uri, Text: text}}, s.openDocumentSnapshots(uri)...)
	docs = appendUniqueDocuments(docs, s.importedDocumentSnapshots(uri, text))
	var out []location
	for _, doc := range docs {
		out = append(out, identifierLocations(doc.Text, doc.URI, name)...)
	}
	out = uniqueLocations(out)
	if includeDeclaration {
		return out
	}
	defs := s.definitionLocations(uri, pos)
	if len(defs) == 0 {
		return out
	}
	return filterLocations(out, defs)
}

func (s *Server) resolveSymbol(uri, text, name string) (resolvedSymbol, bool) {
	if match, ok := symbolDefinition(text, uri, name); ok {
		return match, true
	}
	for _, doc := range s.openDocumentSnapshots(uri) {
		if match, ok := symbolDefinition(doc.Text, doc.URI, name); ok {
			return match, true
		}
	}
	for _, doc := range s.importedDocumentSnapshots(uri, text) {
		if match, ok := symbolDefinition(doc.Text, doc.URI, name); ok {
			return match, true
		}
	}
	return resolvedSymbol{}, false
}

func appendUniqueDocuments(base, extra []documentSnapshot) []documentSnapshot {
	seen := map[string]bool{}
	for _, doc := range base {
		seen[doc.URI] = true
	}
	for _, doc := range extra {
		if seen[doc.URI] {
			continue
		}
		seen[doc.URI] = true
		base = append(base, doc)
	}
	return base
}

func uniqueLocations(in []location) []location {
	seen := map[string]bool{}
	out := make([]location, 0, len(in))
	for _, loc := range in {
		key := locationKey(loc)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, loc)
	}
	return out
}

func filterLocations(in, skip []location) []location {
	skipKeys := map[string]bool{}
	for _, loc := range skip {
		skipKeys[locationKey(loc)] = true
	}
	out := make([]location, 0, len(in))
	for _, loc := range in {
		if !skipKeys[locationKey(loc)] {
			out = append(out, loc)
		}
	}
	return out
}

func locationKey(loc location) string {
	return fmt.Sprintf("%s:%d:%d:%d:%d",
		loc.URI,
		loc.Range.Start.Line,
		loc.Range.Start.Character,
		loc.Range.End.Line,
		loc.Range.End.Character)
}
