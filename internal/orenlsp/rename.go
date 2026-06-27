package orenlsp

type textEdit struct {
	Range   diagnosticRange `json:"range"`
	NewText string          `json:"newText"`
}

type workspaceEdit struct {
	Changes map[string][]textEdit `json:"changes"`
}

func (s *Server) prepareRename(uri string, pos position) *diagnosticRange {
	_, rng, ok := s.exactRenameLocations(uri, pos)
	if !ok {
		return nil
	}
	return &rng
}

func (s *Server) rename(uri string, pos position, newName string) workspaceEdit {
	if !validRenameIdentifier(newName) {
		return workspaceEdit{Changes: map[string][]textEdit{}}
	}
	locs, _, ok := s.exactRenameLocations(uri, pos)
	if !ok {
		return workspaceEdit{Changes: map[string][]textEdit{}}
	}
	changes := map[string][]textEdit{}
	for _, loc := range locs {
		changes[loc.URI] = append(changes[loc.URI], textEdit{Range: loc.Range, NewText: newName})
	}
	return workspaceEdit{Changes: changes}
}

func (s *Server) exactRenameLocations(uri string, pos position) ([]location, diagnosticRange, bool) {
	text := s.docs[uri]
	name, rng := wordRangeAtPosition(text, pos)
	if name == "" {
		return nil, diagnosticRange{}, false
	}
	importedDocs := s.importedDocumentSnapshots(uri, text)
	aliasByURI := s.importedAliasByURI(uri, text)
	if refs, ok := typedMemberReferencesAt(text, uri, pos, true, importedDocs, aliasByURI); ok && sameDocumentLocations(refs, uri) {
		return refs, rng, true
	}
	if refs, ok := scopedParameterReferencesAt(text, uri, pos, true); ok {
		return refs, rng, true
	}
	return nil, diagnosticRange{}, false
}

func sameDocumentLocations(locs []location, uri string) bool {
	if len(locs) == 0 {
		return false
	}
	for _, loc := range locs {
		if loc.URI != uri {
			return false
		}
	}
	return true
}

func validRenameIdentifier(name string) bool {
	rs := []rune(name)
	if len(rs) == 0 || !isIdentStart(rs[0]) {
		return false
	}
	for i := 1; i < len(rs); i++ {
		if !isIdentRune(rs[i]) {
			return false
		}
	}
	for _, kw := range orenKeywords {
		if name == kw {
			return false
		}
	}
	return true
}
