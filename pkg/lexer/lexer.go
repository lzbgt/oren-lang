package lexer

import "oren/pkg/token"

type Lexer struct {
	input        string
	position     int  // current position in input (points to current char)
	readPosition int  // current reading position in input (after current char)
	ch           byte // current char under examination
	line         int
	column       int
}

func New(input string) *Lexer {
	l := &Lexer{input: input, line: 1, column: 0}
	l.readChar()
	return l
}

func (l *Lexer) readChar() {
	if l.readPosition >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = l.input[l.readPosition]
	}
	l.position = l.readPosition
	l.readPosition += 1

	if l.ch == '\n' {
		l.line += 1
		l.column = 0
	} else if l.ch != 0 {
		l.column += 1
	}
}

func (l *Lexer) NextToken() token.Token {
	var tok token.Token

	l.skipWhitespace()
	startLine, startCol := l.line, l.column

	switch l.ch {
	case '&':
		if l.peekChar() == '&' {
			l.readChar()
			tok = token.Token{Type: token.AND, Literal: "&&", Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.BITAND, l.ch, startLine, startCol)
		}
	case '|':
		if l.peekChar() == '|' {
			l.readChar()
			tok = token.Token{Type: token.OR, Literal: "||", Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.BITOR, l.ch, startLine, startCol)
		}
	case '^':
		tok = newToken(token.BITXOR, l.ch, startLine, startCol)
	case '=':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			literal := string(ch) + string(l.ch)
			tok = token.Token{Type: token.EQ, Literal: literal, Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.ASSIGN, l.ch, startLine, startCol)
		}
	case ':':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			literal := string(ch) + string(l.ch)
			tok = token.Token{Type: token.DECLARE, Literal: literal, Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.COLON, l.ch, startLine, startCol)
		}
	case '+':
		tok = newToken(token.PLUS, l.ch, startLine, startCol)
	case '-':
		tok = newToken(token.MINUS, l.ch, startLine, startCol)
	case '~':
		tok = newToken(token.TILDE, l.ch, startLine, startCol)
	case '!':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			literal := string(ch) + string(l.ch)
			tok = token.Token{Type: token.NOT_EQ, Literal: literal, Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.BANG, l.ch, startLine, startCol)
		}
	case '/':
		// TODO: Handle comments // and /* */ here if needed, or in skipWhitespace?
		// For simplicity, let's assume comments are stripped or handled here.
		// Let's implement single line comment //
		if l.peekChar() == '/' {
			l.skipSingleLineComment()
			return l.NextToken()
		} else {
			tok = newToken(token.SLASH, l.ch, startLine, startCol)
		}
	case '*':
		tok = newToken(token.ASTERISK, l.ch, startLine, startCol)
	case '<':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			literal := string(ch) + string(l.ch)
			tok = token.Token{Type: token.LTE, Literal: literal, Line: startLine, Column: startCol}
		} else if l.peekChar() == '<' {
			l.readChar()
			tok = token.Token{Type: token.SHL, Literal: "<<", Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.LT, l.ch, startLine, startCol)
		}
	case '>':
		if l.peekChar() == '=' {
			ch := l.ch
			l.readChar()
			literal := string(ch) + string(l.ch)
			tok = token.Token{Type: token.GTE, Literal: literal, Line: startLine, Column: startCol}
		} else if l.peekChar() == '>' {
			l.readChar()
			tok = token.Token{Type: token.SHR, Literal: ">>", Line: startLine, Column: startCol}
		} else {
			tok = newToken(token.GT, l.ch, startLine, startCol)
		}
	case ';':
		tok = newToken(token.SEMICOLON, l.ch, startLine, startCol)
	case '.':
		tok = newToken(token.DOT, l.ch, startLine, startCol)
	case ',':
		tok = newToken(token.COMMA, l.ch, startLine, startCol)
	case '(':
		tok = newToken(token.LPAREN, l.ch, startLine, startCol)
	case ')':
		tok = newToken(token.RPAREN, l.ch, startLine, startCol)
	case '{':
		tok = newToken(token.LBRACE, l.ch, startLine, startCol)
	case '}':
		tok = newToken(token.RBRACE, l.ch, startLine, startCol)
	case '[':
		tok = newToken(token.LBRACKET, l.ch, startLine, startCol)
	case ']':
		tok = newToken(token.RBRACKET, l.ch, startLine, startCol)
	case '"':
		tok.Type = token.STRING
		tok.Literal = l.readString()
		tok.Line = startLine
		tok.Column = startCol
	case 0:
		tok.Literal = ""
		tok.Type = token.EOF
		tok.Line = startLine
		tok.Column = startCol
	default:
		if isLetter(l.ch) {
			tok.Literal = l.readIdentifier()
			tok.Type = token.LookupIdent(tok.Literal)
			tok.Line = startLine
			tok.Column = startCol
			return tok
		} else if isDigit(l.ch) {
			num := l.readNumber()
			if l.ch == '.' {
				l.readChar() // consume dot
				frac := l.readNumber()
				tok.Type = token.FLOAT
				tok.Literal = num + "." + frac
			} else {
				tok.Type = token.INT
				tok.Literal = num
			}
			tok.Line = startLine
			tok.Column = startCol
			return tok
		} else {
			tok = newToken(token.ILLEGAL, l.ch, startLine, startCol)
		}
	}

	l.readChar()
	return tok
}

func (l *Lexer) skipWhitespace() {
	for l.ch == ' ' || l.ch == '\t' || l.ch == '\n' || l.ch == '\r' {
		l.readChar()
	}
}

func (l *Lexer) skipSingleLineComment() {
	for l.ch != '\n' && l.ch != 0 {
		l.readChar()
	}
	l.skipWhitespace()
}

func (l *Lexer) readIdentifier() string {
	position := l.position
	for isLetter(l.ch) || isDigit(l.ch) {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readNumber() string {
	position := l.position
	for isDigit(l.ch) {
		l.readChar()
	}
	return l.input[position:l.position]
}

func (l *Lexer) readString() string {
	var out []byte
	for {
		l.readChar()
		if l.ch == '"' || l.ch == 0 {
			break
		}
		if l.ch == '\\' {
			l.readChar()
			if l.ch == 0 {
				break
			}
			switch l.ch {
			case 'n':
				out = append(out, '\n')
			case 'r':
				out = append(out, '\r')
			case 't':
				out = append(out, '\t')
			case '"':
				out = append(out, '"')
			case '\\':
				out = append(out, '\\')
			default:
				out = append(out, l.ch)
			}
			continue
		}
		out = append(out, l.ch)
	}
	return string(out)
}

func isLetter(ch byte) bool {
	return 'a' <= ch && ch <= 'z' || 'A' <= ch && ch <= 'Z' || ch == '_'
}

func isDigit(ch byte) bool {
	return '0' <= ch && ch <= '9'
}

func newToken(tokenType token.TokenType, ch byte, line, col int) token.Token {
	return token.Token{Type: tokenType, Literal: string(ch), Line: line, Column: col}
}

func (l *Lexer) peekChar() byte {
	if l.readPosition >= len(l.input) {
		return 0
	}
	return l.input[l.readPosition]
}
