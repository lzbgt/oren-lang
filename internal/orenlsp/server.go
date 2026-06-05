package orenlsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"

	"oren/pkg/lexer"
	"oren/pkg/parser"
)

type Server struct {
	in   *bufio.Reader
	out  io.Writer
	docs map[string]string
}

func NewServer(in io.Reader, out io.Writer) *Server {
	return &Server{in: bufio.NewReader(in), out: out, docs: map[string]string{}}
}

func (s *Server) Run() error {
	for {
		body, err := readMessage(s.in)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if err := s.handle(body); err == io.EOF {
			return nil
		} else if err != nil {
			return err
		}
	}
}

type request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   any             `json:"error,omitempty"`
}

func (s *Server) handle(body []byte) error {
	var req request
	if err := json.Unmarshal(body, &req); err != nil {
		return err
	}
	switch req.Method {
	case "initialize":
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: initializeResult()})
	case "shutdown":
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: nil})
	case "exit":
		return io.EOF
	case "textDocument/didOpen":
		var p didOpenParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		s.docs[p.TextDocument.URI] = p.TextDocument.Text
		return s.publishDiagnostics(p.TextDocument.URI, p.TextDocument.Text)
	case "textDocument/didChange":
		var p didChangeParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		if len(p.ContentChanges) > 0 {
			text := p.ContentChanges[len(p.ContentChanges)-1].Text
			s.docs[p.TextDocument.URI] = text
			return s.publishDiagnostics(p.TextDocument.URI, text)
		}
		return nil
	case "textDocument/didClose":
		var p didCloseParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		delete(s.docs, p.TextDocument.URI)
		return s.publishDiagnostics(p.TextDocument.URI, "")
	case "textDocument/completion":
		var p textDocumentParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: completionItems(s.docs[p.TextDocument.URI])})
	case "textDocument/documentSymbol":
		var p textDocumentParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: documentSymbols(s.docs[p.TextDocument.URI])})
	case "textDocument/definition":
		var p textDocumentParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		uri := p.TextDocument.URI
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: s.definitionLocations(uri, p.Position)})
	case "textDocument/hover":
		var p textDocumentParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: s.hover(p.TextDocument.URI, p.Position)})
	case "textDocument/references":
		var p referenceParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: s.references(p.TextDocument.URI, p.Position, p.Context.IncludeDeclaration)})
	case "textDocument/semanticTokens/full":
		var p textDocumentOnlyParams
		if err := json.Unmarshal(req.Params, &p); err != nil {
			return err
		}
		return s.write(response{JSONRPC: "2.0", ID: req.ID, Result: semanticTokens(s.docs[p.TextDocument.URI])})
	default:
		if len(req.ID) == 0 {
			return nil
		}
		return s.write(response{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error: map[string]any{
				"code":    -32601,
				"message": "method not found",
			},
		})
	}
}

func (s *Server) definitionLocations(uri string, pos position) []location {
	text := s.docs[uri]
	name := wordAtPosition(text, pos)
	if name == "" {
		return []location{}
	}
	if locs := symbolDefinitionLocations(text, uri, name); len(locs) > 0 {
		return locs
	}
	if locs := s.openDocumentDefinitionLocations(uri, name); len(locs) > 0 {
		return locs
	}
	if locs := s.importedDefinitionLocations(uri, text, name); len(locs) > 0 {
		return locs
	}
	return []location{}
}

func initializeResult() map[string]any {
	return map[string]any{
		"capabilities": map[string]any{
			"textDocumentSync": map[string]any{
				"openClose": true,
				"change":    1,
			},
			"completionProvider": map[string]any{
				"triggerCharacters": []string{".", ":"},
			},
			"documentSymbolProvider": true,
			"definitionProvider":     true,
			"hoverProvider":          true,
			"referencesProvider":     true,
			"semanticTokensProvider": map[string]any{
				"legend": map[string]any{
					"tokenTypes":     semanticTokenTypes,
					"tokenModifiers": semanticTokenModifiers,
				},
				"full":  true,
				"range": false,
			},
		},
		"serverInfo": map[string]any{
			"name":    "oren-lsp",
			"version": "0.1.0",
		},
	}
}

type didOpenParams struct {
	TextDocument struct {
		URI  string `json:"uri"`
		Text string `json:"text"`
	} `json:"textDocument"`
}

type didChangeParams struct {
	TextDocument struct {
		URI string `json:"uri"`
	} `json:"textDocument"`
	ContentChanges []struct {
		Text string `json:"text"`
	} `json:"contentChanges"`
}

type didCloseParams struct {
	TextDocument struct {
		URI string `json:"uri"`
	} `json:"textDocument"`
}

type textDocumentParams struct {
	TextDocument struct {
		URI string `json:"uri"`
	} `json:"textDocument"`
	Position position `json:"position"`
}

type textDocumentOnlyParams struct {
	TextDocument struct {
		URI string `json:"uri"`
	} `json:"textDocument"`
}

type referenceParams struct {
	TextDocument struct {
		URI string `json:"uri"`
	} `json:"textDocument"`
	Position position `json:"position"`
	Context  struct {
		IncludeDeclaration bool `json:"includeDeclaration"`
	} `json:"context"`
}

func (s *Server) publishDiagnostics(uri, text string) error {
	return s.write(map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/publishDiagnostics",
		"params": map[string]any{
			"uri":         uri,
			"diagnostics": diagnose(text),
		},
	})
}

type diagnostic struct {
	Range    diagnosticRange `json:"range"`
	Severity int             `json:"severity"`
	Source   string          `json:"source"`
	Message  string          `json:"message"`
}

type diagnosticRange struct {
	Start position `json:"start"`
	End   position `json:"end"`
}

type position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

func diagnose(text string) []diagnostic {
	out := []diagnostic{}
	var stack []runeFrame
	line, col := 0, 0
	inString := false
	stringStart := position{}
	escaped := false
	rs := []rune(text)
	for idx := 0; idx < len(rs); idx++ {
		r := rs[idx]
		if r == '\n' {
			line++
			col = 0
			escaped = false
			continue
		}
		pos := position{Line: line, Character: col}
		if inString {
			if escaped {
				escaped = false
			} else if r == '\\' {
				escaped = true
			} else if r == '"' {
				inString = false
			}
			col++
			continue
		}
		if r == '"' {
			inString = true
			stringStart = pos
			col++
			continue
		}
		if r == '/' && idx+1 < len(rs) && rs[idx+1] == '/' {
			for idx < len(rs) && rs[idx] != '\n' {
				idx++
			}
			if idx < len(rs) && rs[idx] == '\n' {
				line++
				col = 0
			}
			continue
		}
		if closerFor(r) != 0 {
			stack = append(stack, runeFrame{r: r, pos: pos})
		} else if open := openerFor(r); open != 0 {
			if len(stack) == 0 || stack[len(stack)-1].r != open {
				out = append(out, diag(pos, pos, "unmatched closing delimiter"))
			} else {
				stack = stack[:len(stack)-1]
			}
		}
		col++
	}
	if inString {
		out = append(out, diag(stringStart, position{Line: line, Character: col}, "unterminated string literal"))
	}
	for i := len(stack) - 1; i >= 0; i-- {
		fr := stack[i]
		out = append(out, diag(fr.pos, fr.pos, "unclosed delimiter"))
	}
	out = append(out, parserDiagnostics(text)...)
	return out
}

func parserDiagnostics(text string) []diagnostic {
	p := parser.New(lexer.New(text))
	p.ParseProgram()
	errs := p.Errors()
	out := make([]diagnostic, 0, len(errs))
	for _, err := range errs {
		out = append(out, parserDiagnostic(err))
	}
	return out
}

func parserDiagnostic(msg string) diagnostic {
	line, col, rest := splitParserError(msg)
	pos := position{Line: line, Character: col}
	return diagWithSource(pos, pos, "oren-parser", rest)
}

func splitParserError(msg string) (int, int, string) {
	line, col := 0, 0
	rest := msg
	first, tail, ok := strings.Cut(msg, ":")
	if !ok {
		return line, col, rest
	}
	second, tail2, ok := strings.Cut(tail, " ")
	if !ok {
		return line, col, rest
	}
	parsedLine, lineErr := strconv.Atoi(first)
	parsedCol, colErr := strconv.Atoi(strings.TrimSuffix(second, ":"))
	if lineErr != nil || colErr != nil {
		return line, col, rest
	}
	if parsedLine > 0 {
		line = parsedLine - 1
	}
	if parsedCol > 0 {
		col = parsedCol - 1
	}
	return line, col, tail2
}

type runeFrame struct {
	r   rune
	pos position
}

func closerFor(r rune) rune {
	switch r {
	case '(':
		return ')'
	case '[':
		return ']'
	case '{':
		return '}'
	default:
		return 0
	}
}

func openerFor(r rune) rune {
	switch r {
	case ')':
		return '('
	case ']':
		return '['
	case '}':
		return '{'
	default:
		return 0
	}
}

func diag(start, end position, msg string) diagnostic {
	return diagWithSource(start, end, "oren-lsp", msg)
}

func diagWithSource(start, end position, source, msg string) diagnostic {
	if end.Line == start.Line && end.Character == start.Character {
		end.Character++
	}
	return diagnostic{
		Range:    diagnosticRange{Start: start, End: end},
		Severity: 1,
		Source:   source,
		Message:  msg,
	}
}

func (s *Server) write(v any) error {
	body, err := json.Marshal(v)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(s.out, "Content-Length: %d\r\n\r\n%s", len(body), body)
	return err
}

func readMessage(r *bufio.Reader) ([]byte, error) {
	contentLength := -1
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
		if line == "" {
			break
		}
		name, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(name), "Content-Length") {
			n, err := strconv.Atoi(strings.TrimSpace(value))
			if err != nil {
				return nil, err
			}
			contentLength = n
		}
	}
	if contentLength < 0 {
		return nil, fmt.Errorf("missing Content-Length")
	}
	body := make([]byte, contentLength)
	if _, err := io.ReadFull(r, body); err != nil {
		return nil, err
	}
	return body, nil
}

func EncodeMessage(v any) ([]byte, error) {
	body, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	var out bytes.Buffer
	fmt.Fprintf(&out, "Content-Length: %d\r\n\r\n", len(body))
	out.Write(body)
	return out.Bytes(), nil
}
