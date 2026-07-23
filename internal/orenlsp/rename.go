package orenlsp

import (
	"oren/pkg/lexer"
	"oren/pkg/token"
)

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
	if refs, ok := importAliasRenameLocationsAt(text, uri, name, rng); ok {
		return refs, rng, true
	}
	importedDocs := s.importedDocumentSnapshots(uri, text)
	aliasByURI := s.importedAliasByURI(uri, text)
	if refs, ok := typedMemberReferencesAt(text, uri, pos, true, importedDocs, aliasByURI); ok {
		return refs, rng, true
	}
	if refs, ok := scopedParameterReferencesAt(text, uri, pos, true); ok {
		return refs, rng, true
	}
	return nil, diagnosticRange{}, false
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

func importAliasRenameLocationsAt(text, uri, name string, rng diagnosticRange) ([]location, bool) {
	if name == "" {
		return nil, false
	}
	tokens := sourceTokens(text)
	var locs []location
	selected := false
	for i, tok := range tokens {
		if tok.Type == token.IMPORT && i+2 < len(tokens) && tokens[i+1].Type == token.IDENT && tokens[i+2].Type == token.STRING && tokens[i+1].Literal == name {
			loc := location{URI: uri, Range: tokenRange(tokens[i+1])}
			locs = append(locs, loc)
			if rangeEqual(loc.Range, rng) {
				selected = true
			}
			continue
		}
		if tok.Type == token.IDENT && tok.Literal == name && i+1 < len(tokens) && tokens[i+1].Type == token.DOT {
			loc := location{URI: uri, Range: tokenRange(tok)}
			locs = append(locs, loc)
			if rangeEqual(loc.Range, rng) {
				selected = true
			}
		}
	}
	if !selected || len(locs) == 0 {
		return nil, false
	}
	return uniqueLocations(locs), true
}

func sourceTokens(text string) []token.Token {
	l := lexer.New(text)
	var tokens []token.Token
	for {
		tok := l.NextToken()
		if tok.Type == token.EOF {
			break
		}
		tokens = append(tokens, tok)
	}
	return tokens
}

func rangeEqual(a, b diagnosticRange) bool {
	return a.Start.Line == b.Start.Line &&
		a.Start.Character == b.Start.Character &&
		a.End.Line == b.End.Line &&
		a.End.Character == b.End.Character
}
