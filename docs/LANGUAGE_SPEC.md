# Oren Language Specification (Draft)

This document describes the **Oren v0** language as implemented by the C backend (the transpiler + `lib/runtime.[ch]`) and as required for self-hosting (`oren.oren`).

The Go interpreter (`cmd/oren run` / REPL) is a convenience tool and is **not** the reference implementation (it supports only a subset and differs in some semantics like scoping).

## Lexical Structure

### Whitespace
- Spaces, tabs, newlines, and carriage returns separate tokens.
- Newlines are not significant.

### Comments
- Line comments start with `//` and run to the end of the line.

### Keywords
`fn`, `var`, `true`, `false`, `if`, `else`, `return`, `while`, `for`, `break`, `continue`, `nil`, `ffi`, `import`, `struct`, `class`

### Identifiers
Identifiers are ASCII letters, digits, and `_`:
- Pattern: `[A-Za-z_][A-Za-z0-9_]*`

### Literals
- **Integer**: one or more digits: `[0-9]+`
- **Float**: digits, then `.`, then optional digits: `[0-9]+ "." [0-9]*`
- **String**: double-quoted characters: `"..."`  
  Escape sequences are supported:
  - `\\` (backslash)
  - `\"` (double quote)
  - `\n` (line feed)
  - `\r` (carriage return)
  - `\t` (tab)

## Syntax (EBNF)

```ebnf
program         = { statement } EOF ;

statement       = var_stmt
                | short_var_stmt
                | assignment
                | return_stmt
                | while_stmt
                | for_stmt
                | break_stmt
                | continue_stmt
                | import_stmt
                | type_stmt
                | ffi_stmt
                | expr_stmt ;

var_stmt        = "var" ident "=" expression [ ";" ] ;
short_var_stmt  = ident ":=" expression [ ";" ] ;
return_stmt     = "return" expression [ ";" ] ;
while_stmt      = "while" expression block ;
for_stmt        = "for" [ for_header ] block ;
break_stmt      = "break" [ ";" ] ;
continue_stmt   = "continue" [ ";" ] ;
import_stmt     = "import" ident string_lit [ ";" ] ;
type_stmt       = ("struct" | "class") ident "{" [ ident { "," ident } [ "," ] ] "}" [ ";" ] ;
ffi_stmt        = "ffi" ident [ ";" ] ;
expr_stmt       = expression [ ";" ] ;

for_header      = expression
                | [ for_init ] ";" [ expression ] ";" [ for_post ] ;
for_init        = var_stmt_no_semi
                | short_var_stmt_no_semi
                | assignment_no_semi
                | expression ;
for_post        = assignment_no_semi | expression ;
var_stmt_no_semi       = "var" ident "=" expression ;
short_var_stmt_no_semi = ident ":=" expression ;
assignment_no_semi     = assign_target "=" expression ;

assignment      = assign_target "=" expression [ ";" ] ;
assign_target   = ident | index_expr | member_expr ;

block           = "{" { statement } "}" ;

expression      = prefix_expr { infix_tail } ;
prefix_expr     = literal
                | ident
                | "(" expression ")"
                | if_expr
                | fn_lit
                | array_lit
                | map_lit
                | ("!" | "-" | "~") expression ;

infix_tail      = infix_op expression
                | call_suffix
                | member_suffix
                | index_suffix ;

if_expr         = "if" expression block [ "else" block ] ;
fn_lit          = "fn" [ ident ] "(" [ ident { "," ident } ] ")" block ;
call_suffix     = "(" [ expression { "," expression } ] ")" ;
member_suffix   = "." ident ;
index_suffix    = "[" expression "]" ;

array_lit       = "[" [ expression { "," expression } ] "]" ;
map_lit         = "{" [ expression ":" expression { "," expression ":" expression } ] "}" ;

literal         = int_lit | float_lit | string_lit | "true" | "false" | "nil" ;
ident           = /[A-Za-z_][A-Za-z0-9_]*/ ;
infix_op        = "+" | "-" | "*" | "/"
                | "<<" | ">>"
                | "==" | "!=" | "<" | ">" | "<=" | ">="
                | "&" | "^" | "|"
                | "&&" | "||" ;
```

## Operator Precedence (highest to lowest)
1. Member access: `.` and indexing: `[]`
2. Call: `()`
3. Prefix: `!` `-`
4. Multiplicative: `*` `/`
5. Additive: `+` `-`
6. Shift: `<<` `>>`
7. Comparisons: `<` `>` `<=` `>=`
8. Equality: `==` `!=`
9. Bitwise AND: `&`
10. Bitwise XOR: `^`
11. Bitwise OR: `|`
12. Logical AND: `&&`
13. Logical OR: `||`

All infix operators are left-associative.

## Semantics

### Values and Types
The runtime is dynamically typed. Values include:
- `nil`
- `bool` (`true`/`false`)
- `int` (signed 64-bit in the C runtime)
- `float` (double in the C runtime)
- `string` (byte string)
- `list`
- `map`
- `python object` (opaque wrapper used by the optional Python FFI)

### Truthiness
- `nil` is falsey
- `false` is falsey
- everything else is truthy

### Variables and Scope
- `var name = expr` and `name := expr` declare a new variable in the current scope.
- `name = expr` assigns to an existing variable. Assigning to an undeclared name is an error.
- Scopes are **lexical**:
  - globals (top-level `var`)
  - function scope
  - block scope (`{ ... }`) where variables may shadow outer names

### Control Flow
- `if cond { ... } else { ... }` executes a block based on truthiness of `cond`.
  - The grammar treats `if` as an expression, but the C backend only supports it in statement position.
- `while cond { ... }` repeats while `cond` is truthy.
- `for` has two forms:
  - Condition-only: `for cond { ... }`
  - Three-clause: `for init; cond; post { ... }`
- `break` exits the nearest enclosing loop (`while`/`for`).
- `continue` skips to the next loop iteration.
- `return expr` returns from the current function. A return value is always required; use `return nil` if needed.

### Functions
- `fn name(params) { ... }` defines a named function (v0: only supported at top-level by the C backend).
- `fn(params) { ... }` parses as an anonymous function literal, but the C backend does not currently support first-class functions/closures.
- Calls: `f(x, y)`
  - Calls to Oren-defined functions compile to direct C calls.
  - Calls to Python objects use the runtime’s `oren_call_obj`.

### Operators
- `+ - * /`:
  - `int op int` yields `int` (and `int / int` is integer division).
  - If either operand is `float`, arithmetic is performed in `float`.
  - `string + string` concatenates.
- `==` / `!=` are type-strict in the runtime (e.g., `1 == 1.0` is false).
- `< > <= >=`:
  - defined for numeric comparisons (`int`/`float`, mixed allowed) and lexicographic `string` comparisons
  - any other type combination is a runtime error
- `&&` / `||`:
  - evaluate operands using truthiness rules
  - short-circuit (right operand is evaluated only if needed)
  - result is a boolean (`true`/`false`)
- `& | ^ << >> ~` (bitwise / shifts):
  - only defined for `int`
  - operate on the 64-bit two’s-complement bit pattern of the integer value
  - `>>` is a logical (zero-fill) right shift
  - results wrap to 64 bits (any higher bits are discarded)

### Lists
- List literal: `[a, b, c]`
- Indexing: `xs[i]` (0-based)
- Index assignment: `xs[i] = v` (must be in-bounds)

### Maps
- Map literal: `{key: value, ...}`
- Lookup: `m[key]`
  - missing keys yield `nil` in the runtime
- Assignment: `m[key] = value`
- Duplicate keys in a map literal are unspecified; avoid them.

### Structs and Classes
- `struct Name { a, b, c }` and `class Name { a, b, c }` declare a nominal “shape” with a fixed set of field names.
- Instances are currently represented as runtime maps with string keys (so field access is a map lookup).
- Construction:
  - `Name.new(v1, v2, v3)` returns a new instance (keys `"a"`, `"b"`, `"c"` in declaration order).
  - `Name(v1, v2, v3)` is shorthand for `Name.new(...)`.
- Field access and assignment:
  - `p.a` reads the `"a"` field.
  - `p.a = v` writes the `"a"` field.

### Modules and Imports
- `import math "path/to/math.oren"` compiles the referenced file as a module and binds it to the identifier `math` as a **namespace**.
- Accessing module members uses member syntax:
  - `math.PI`
  - `math.sqrt(2.0)`
- Import paths are resolved relative to the directory of the importing file; absolute paths are allowed.
- Imports are resolved recursively at compile time; cyclic imports are an error.
- All top-level `var`, named `fn`, and `struct`/`class` declarations in an imported file are treated as module members.

## Evaluation Order
Expression evaluation order is currently not specified by the language. Avoid relying on side effects inside subexpressions (especially in function call arguments and binary operators) when targeting the C backend.

## Builtins (C Backend)
The C backend recognizes a few builtin functions and lowers them directly:
- `print(...)` → `oren_print(...)` / `oren_print_multi(...)`
- `py_import("name")` → `oren_py_import(...)`
- `system("cmd")` → `oren_system(...)`
- `exit(code)` → `oren_exit(...)`

## Runtime Builtins (Self-Hosting and Native Backend)
The self-hosted compiler and the (in-progress) native backend rely on a few additional runtime helpers:
- `oren_write_bytes(path, bytes)` writes a list of byte values (`0..255`) to a file (binary-safe).
- `oren_bytes_from_string(s)` converts a string to a list of byte values (`0..255`).
- `oren_sha256_range(bytes, start, length)` computes SHA-256 over a subrange of a byte list and returns a 32-byte list.
- `oren_chmod(path, mode)` calls `chmod(2)` (used to set the executable bit on generated binaries).

### Native Backend Intrinsics
The native ARM64 backend supports low-level intrinsics for performance and system access:
- **SIMD (NEON)**:
  - `simd_add_2d`, `simd_sub_2d`: 128-bit integer addition/subtraction.
  - `simd_mul_4s`: 4x32-bit integer multiplication.
  - `simd_and_2d`, `simd_orr_2d`, `simd_eor_2d`: 128-bit bitwise operations.
- **Memory**:
  - `malloc(size)`: Allocate raw memory (pages).
  - `ptr_get(ptr)`, `ptr_set(ptr, val)`: Read/Write 64-bit word.
  - `ptr_get_byte(ptr)`, `ptr_set_byte(ptr, val)`: Read/Write 8-bit byte.
- **Atomics (LSE)**:
  - `atomic_add(ptr, val)`: Atomic add, returns old value.
  - `atomic_cas(ptr, expected, new)`: Atomic compare-and-swap, returns old value.
- **FFI**:
  - `ffi symbol` statement declares an external symbol (e.g., `ffi puts`).

### Optional Python FFI
Python interop is only available when the runtime is built with Python embedding (`-DOREN_ENABLE_PYTHON` / compiler `--python`).
- Import: `var math = py_import("math")`
- Attribute access: `math.sqrt` (Python attribute get)
- Indexing: `obj[key]` (Python `__getitem__`)
- Calls: `obj(...)` (Python call)

## Standard Runtime Surface (Self-Hosting)
Self-hosting relies on a small runtime API (implemented in C, callable from Oren) including:
- `oren_args()` for CLI args
- `oren_read_file(path)` / `oren_write_file(path, content)` for I/O
- `oren_system(cmd)` / `oren_exit(code)` for building and exit status
- `oren_string_len(s)` / `oren_string_char_at(s, i)` / `oren_char(code)` for string/char work
- `oren_list_len(xs)` / `oren_list_push(xs, v)` for list work

## Not Implemented (v0)
- user-defined methods/inheritance (classes are currently data-only)
- dynamic/runtime module loading
