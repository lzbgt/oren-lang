package token

type TokenType string

type Token struct {
	Type    TokenType
	Literal string
	Line    int
	Column  int
}

const (
	ILLEGAL = "ILLEGAL"
	EOF     = "EOF"

	// Identifiers + literals
	IDENT  = "IDENT" // add, foobar, x, y, ...
	INT    = "INT"   // 1343456
	FLOAT  = "FLOAT" // 3.14
	STRING = "STRING"

	// Operators
	ASSIGN   = "="
	PLUS     = "+"
	MINUS    = "-"
	BANG     = "!"
	TILDE    = "~"
	ASTERISK = "*"
	SLASH    = "/"
	LT       = "<"
	GT       = ">"
	LTE      = "<="
	GTE      = ">="
	SHL      = "<<"
	SHR      = ">>"
	EQ       = "=="
	NOT_EQ   = "!="
	DECLARE  = ":="
	AND      = "&&"
	OR       = "||"
	BITAND   = "&"
	BITOR    = "|"
	BITXOR   = "^"
	AT       = "@"

	// Delimiters
	DOT       = "."
	COLON     = ":"
	COMMA     = ","
	SEMICOLON = ";"
	LPAREN    = "("
	RPAREN    = ")"
	LBRACE    = "{"
	RBRACE    = "}"
	LBRACKET  = "["
	RBRACKET  = "]"

	// Keywords
	FUNCTION = "FUNCTION"
	LET      = "LET" // var
	TRUE     = "TRUE"
	FALSE    = "FALSE"
	IF       = "IF"
	ELSE     = "ELSE"
	RETURN   = "RETURN"
	WHILE    = "WHILE"
	FOR      = "FOR"
	BREAK    = "BREAK"
	CONTINUE = "CONTINUE"
	IN       = "IN"
	IMPORT   = "IMPORT"
	STRUCT   = "STRUCT"
	CLASS    = "CLASS"
	NIL      = "NIL"
	FFI      = "FFI"
	SPAWN    = "SPAWN"
)

var keywords = map[string]TokenType{
	"fn":       FUNCTION,
	"var":      LET,
	"true":     TRUE,
	"false":    FALSE,
	"if":       IF,
	"else":     ELSE,
	"return":   RETURN,
	"while":    WHILE,
	"for":      FOR,
	"break":    BREAK,
	"continue": CONTINUE,
	"in":       IN,
	"import":   IMPORT,
	"struct":   STRUCT,
	"class":    CLASS,
	"nil":      NIL,
	"ffi":      FFI,
	"spawn":    SPAWN,
}

func LookupIdent(ident string) TokenType {
	if tok, ok := keywords[ident]; ok {
		return tok
	}
	return IDENT
}
