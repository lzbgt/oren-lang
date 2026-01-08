# Oren Language Specification (Draft)

**Last updated:** 2025-12-28

This document describes the **current Oren language** as accepted by the Stage1 compiler (`./oren`) and required for self-hosting (`oren.oren`).
It includes both:

- **normative “what exists today”** rules (grounded in compiler behavior and fixtures),
- **explicitly marked planned design direction** items (tied to `docs/TODOS.md` / `docs/ROADMAP.md`).

The Go interpreter (`cmd/oren run` / REPL) is a convenience tool and is **not** the reference implementation (it supports only a subset and differs in some semantics like scoping).

## How to read this spec (AI- and tool-friendly)

This repo is in rolling mode. To keep the spec precise for both humans and AI agents, we use the following status markers:

- **Implemented**: works today and should have fixture evidence (see `tests/**` and `docs/LANGUAGE_STATUS_AND_GAPS.md`).
- **Rolling**: implemented but not stabilized (ABI/format/details may change; still regression-tested).
- **Planned**: design intent; not implemented yet (must link to `docs/TODOS.md` or other canonical design docs).

If an AI agent needs the most “ground-truth” behavior, prioritize:

- `docs/LANGUAGE_MANUAL.md` (practical usage today),
- `docs/LANGUAGE_STATUS_AND_GAPS.md` (evidence-backed “what works today” + missing gaps),
- `docs/LANGUAGE_FEATURE_MATRIX.md` (feature → status → implementation → fixtures),
- the fixtures under `tests/native/fixtures/`, `tests/modules/`, `tests/avm/` (living spec).

## Non-normative: Implementation map (for maintainers and agents)

The spec defines syntax/semantics. This section exists to help AI agents locate the implementation that enforces a given rule.
It is **not** normative, but it should be kept accurate.

For a rolling “agent cache” of subtle internals (name resolution, lowering patterns, cross-backend contracts),
see `docs/IMPLEMENTATION_NOTES.md`.

Compiler pipeline (high level):

1) parse → AST (`lib/compiler/parser_parse/**`, `lib/compiler/ast.oren`)
2) link modules/imports → merged program (`lib/compiler/compiler/020_modules_linking.oren`)
3) deterministic lowering passes (`lib/compiler/**`)
4) backend codegen:
   - C: `lib/compiler/transpiler.oren` → C + `lib/runtime.[ch]`
   - bytecode: `lib/compiler/codegen_bytecode/**` → `.obc` + AVM runtime `lib/avm/**`
   - native: `lib/compiler/arm64_*`, `lib/compiler/x64_*` + runtime `lib/runtime_native/**`

When this spec says “Implemented/Rolling”, the expected evidence is one of:

- a regression fixture under `tests/**`,
- or an example under `examples/` that runs under `make examples-test`.

## Lexical Structure

### Whitespace
- Spaces, tabs, newlines, and carriage returns separate tokens.
- Newlines are not significant.

### Comments
- Line comments start with `//` and run to the end of the line.

### Keywords
Implemented today:

`fn`, `var`, `true`, `false`, `if`, `else`, `return`, `while`, `for`, `switch`, `case`, `default`, `break`, `continue`, `nil`, `ffi`, `import`, `struct`, `class`, `spawn`, `enum`, `trait`, `impl`, `test`, `match`, `as`

Planned (not implemented yet):

`yield`, `defer`, `assert`, `pub`

Rolling note: “planned keywords” are *design placeholders* and are not guaranteed to be reserved today.
Until a stabilization milestone, avoid using them as identifiers if you want forward compatibility.

Rolling note: `match` is a **contextual** keyword to preserve compatibility with code that uses
`match` as an identifier (variable/function name). The parser treats `match` as a statement only
when the following token sequence looks like a match statement, not an identifier usage.

### Identifiers
Identifiers are ASCII letters, digits, and `_`:
- Pattern: `[A-Za-z_][A-Za-z0-9_]*`

Rolling restriction (practical today):
- Prefixes `oren_` and `sys_` are **reserved** for runtime/compiler intrinsics.
- Prefix `__oren_` is reserved for compiler-generated internal symbols (wrappers, lambdas, etc.).

User code should not define variables/functions with these prefixes; the compiler may treat them as
special globals (for example, they are not captured as closure variables in native backends).

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
                | typed_short_var_stmt
                | assignment
                | return_stmt
                | while_stmt
                | for_stmt
                | switch_stmt
                | match_stmt
                | break_stmt
                | continue_stmt
                | import_stmt
                | type_stmt
                | trait_stmt
                | impl_stmt
                | enum_stmt
                | ffi_stmt
                | test_stmt
                | spawn_stmt
                | expr_stmt ;

var_stmt        = "var" ident [ ":" type_name ] "=" expression [ ";" ] ;
short_var_stmt  = ident ":=" expression [ ";" ] ;
typed_short_var_stmt = ident ":" type_name ":=" expression [ ";" ] ;
return_stmt     = "return" expression [ ";" ] ;
while_stmt      = "while" expression block ;
for_stmt        = "for" [ for_in_header | for_header ] block ;
switch_stmt     = "switch" expression "{" { case_clause } [ default_clause ] "}" ;
match_stmt      = "match" expression "{" { match_case } [ match_default ] "}" ;
case_clause     = "case" expression { "," expression } [ ":" ] block ;
default_clause  = "default" [ ":" ] block ;
match_case      = "case" match_pattern [ ":" ] block ;
match_default   = "default" [ ":" ] block ;
break_stmt      = "break" [ ";" ] ;
continue_stmt   = "continue" [ ";" ] ;
import_stmt     = "import" ident string_lit [ ";" ] ;
type_stmt       = ("struct" | "class") ident "{" [ field { "," field } [ "," ] ] "}" [ ";" ] ;
field           = { attr } ident [ ":" type_name ] ;
trait_stmt      = "trait" ident "{" { "fn" ident "(" [ param_list ] ")" [ ":" type_name ] ";" } "}" ;
impl_stmt       = "impl" dotted_name "for" type_name "{" { "fn" ident "(" [ param_list ] ")" [ ":" type_name ] block } "}" ;
enum_stmt       = "enum" ident "{" ident [ "(" [ ident { "," ident } ] ")" ] { "," ident [ "(" [ ident { "," ident } ] ")" ] } [ "," ] "}" ;
ffi_stmt        = "ffi" ident [ ";" ] ;
test_stmt       = "test" string_lit block ;
spawn_stmt      = "spawn" expression [ ";" ] ;
expr_stmt       = expression [ ";" ] ;

for_header      = expression
                | [ for_init ] ";" [ expression ] ";" [ for_post ] ;
for_in_header   = ident [ ":" type_name ] "in" expression ;
for_init        = var_stmt_no_semi
                | short_var_stmt_no_semi
                | typed_short_var_stmt_no_semi
                | assignment_no_semi
                | expression ;
for_post        = assignment_no_semi | expression ;
var_stmt_no_semi       = "var" ident [ ":" type_name ] "=" expression ;
short_var_stmt_no_semi = ident ":=" expression ;
typed_short_var_stmt_no_semi = ident ":" type_name ":=" expression ;
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
                | lambda_lit
                | spawn_expr
                | array_lit
                | map_lit
                | ("!" | "-" | "~") expression ;

infix_tail      = infix_op expression
                | call_suffix
                | member_suffix
                | index_suffix
                | cast_suffix ;

if_expr         = "if" expression block [ "else" ( block | if_expr ) ] ;
fn_lit          = "fn" [ ident ] "(" [ param_list ] ")" block ;
lambda_lit      = "|" [ ident { "," ident } ] "|" ( expression | block ) ;
                // Note: for empty parameter lists, the source form `|| expr` is allowed (lexer emits a single `||` token).
                // Rolling note: lambda params are currently untyped identifiers (no attrs, no varargs).
spawn_expr      = "spawn" expression ;
                // v0 restriction (all backends): `spawn` currently requires a call expression,
                // e.g. `spawn f(x, y)`; it does not spawn arbitrary expressions.
call_suffix     = "(" [ expression { "," expression } ] ")" ;
member_suffix   = "." ident ;
index_suffix    = "[" expression "]" ;

	array_lit       = "[" [ expression { "," expression } ] "]" ;
	map_lit         = "{" [ expression ":" expression { "," expression ":" expression } ] "}" ;

	// Numeric literals (rolling):
	// - int literals may be decimal or prefixed base (0x/0b/0o)
	// - `_` separators are allowed and ignored
	//
	// NOTE: negative numbers are represented as prefix expressions (`-` token + int literal),
	// not as a signed literal token.
	int_lit         = dec_int | hex_int | bin_int | oct_int ;
	dec_int         = dec_digit (dec_digit | "_")* ;
	hex_int         = "0x" hex_digit (hex_digit | "_")* ;
	bin_int         = "0b" ("0" | "1") (("0" | "1") | "_")* ;
	oct_int         = "0o" oct_digit (oct_digit | "_")* ;
	float_lit       = dec_int "." dec_int [ exp_suffix ]
	              | dec_int exp_suffix ;
	exp_suffix      = ("e" | "E") [ "+" | "-" ] dec_int ;

	literal         = int_lit | float_lit | string_lit | "true" | "false" | "nil" ;
	ident           = /[A-Za-z_][A-Za-z0-9_]*/ ;
	dotted_name     = ident { "." ident } ;
	type_name       = [ "*" { "*" } ] type_atom { "[" int_lit "]" } ;
	type_atom       = dotted_name
	                | "[]" dotted_name ;
attr            = "@" dotted_name [ "(" { /* literal args only (v0) */ } ")" ] ;
param           = { attr } [ "..." ] ident [ ":" type_name ] ;
param_list      = param { "," param } ;
match_pattern   = dotted_name [ "(" [ ident { "," ident } ] ")" ] ;
	infix_op        = "+" | "-" | "*" | "/" | "%"
	                | "<<" | ">>"
	                | "==" | "!=" | "<" | ">" | "<=" | ">="
	                | "&" | "^" | "|"
	                | "&&" | "||" ;
cast_suffix     = "as" type_name ;
```

## Operator Precedence (highest to lowest)
1. Member access: `.` and indexing: `[]`
2. Call: `()`
3. Cast: `as <type>`
4. Prefix: `!` `-` `~`
5. Multiplicative: `*` `/` `%`
6. Additive: `+` `-`
7. Shift: `<<` `>>`
8. Comparisons: `<` `>` `<=` `>=`
9. Equality: `==` `!=`
10. Bitwise AND: `&`
11. Bitwise XOR: `^`
12. Bitwise OR: `|`
13. Logical AND: `&&`
14. Logical OR: `||`

All infix operators are left-associative.

## Semantics

### Program structure and entry semantics (rolling, current toolchain)

Oren is a module language: a file contains top-level statements and declarations.

Entry behavior (current implementation across backends):

- **Top-level statements execute** in source order as the module loads (lowered into an internal `__top_level__` function).
- If a user-defined `fn main()` exists, the runtime may call it automatically depending on backend:
  - bytecode backend appends a `CALL main` entry stub if `main` exists (see `lib/compiler/codegen_bytecode/030_tail.oren`),
  - native backends use an entry stub that calls `main` (or `__top_level__` if `main` is absent; see `lib/compiler/arm64_elf.oren` / `lib/compiler/arm64_macho.oren`),
  - C backend emits a host `int main(...)` that executes top-level statements in order and then calls user `fn main()` if present (see `lib/compiler/transpiler.oren`).

Practical rule:

- For **native** and **AVM** builds, do **not** write `main()` as a top-level call unless you intentionally want `main` to run twice.
- For the **C backend**, do **not** write `main()` as a top-level call unless you intentionally want `main` to run twice.

Implementation note (C backend):

- User `fn main()` is emitted as a different C symbol to avoid colliding with the host `int main(...)` entrypoint; this is an internal detail and should not affect Oren source code.

Program termination (rolling):

- Do not rely on the **return value of `main`** for an exit code; backends do not yet agree on whether it is used.
- Use `exit(code)` for deterministic, portable termination semantics across all backends.

### Notes on current (rolling) type annotations

Oren is still in rolling mode without a full static type checker, but the parser already supports
**explicit type annotation syntax** because it is required for:

- syscall-first network/FFI structs (`u16be`, `u32be`, pointers like `*u8`, fixed arrays like `u8[16]`)
- deterministic packed-byte views (`@pack` + field `name: u16be`)
- method sugar resolution (static-first): `x: Type; x.method(...)` can lower to an impl method

Where type annotations can appear today:

- locals: `var x: u64 = ...`
- typed short var: `x: u64 := ...`
- function params: `fn f(x: u64) { ... }`
- struct/class fields: `struct S { len: u16be, bytes: u8[16] }`
- imported types (alias-qualified): `import it \"mod.oren\"; var r: it.MyRange = it.new_range(...)`

#### Rolling v0 “kind annotations” for container sugar

While the full type system is still rolling, some backends require additional information
to lower builtin container method sugar deterministically (notably where runtime values are not
safely tagged).

Oren therefore allows a small set of *conventional* annotation spellings to act as container-kind hints:

- `: list` — list receiver (enables `xs.push(v)` / `xs.len()` lowering)
- `: map` — map receiver (enables `m.len()` lowering)
- `: buf` — typed buffer receiver kind (enables `b.len()` lowering when element width is not relevant)
- `: string` — string receiver (enables `s.len()` lowering)

These are hints used by compiler lowerings in rolling v0; they are not yet “real types” in the v1 sense.

Additionally (rolling, native backends):

- numeric annotations like `: int`, `: i64`, `: u64`, ... are treated as an **“int kind” hint** for deterministic map key-kind inference (avoids runtime pointer/int heuristics in x86_64 native bring-up)
- typed buffer annotations of the form `[]T` (e.g. `[]i32`, `[]f64`) are treated as a **“buf kind” hint** for receiver sugar like `b.len()`

Typed buffers also have a width-specialized type spelling used throughout the HPC stdlib:

- `[]i32`, `[]i64`, `[]f32`, `[]f64`, `[]u8`, ...

Example:

```oren
import buffer "std:buffer"

var b: []i32 = buffer.i32_new(16)
```

Type names like `u8`, `i32`, `f64`, `u16be`, etc. are **language-reserved tokens** intended to
become true explicit types as the v1 type system is stabilized (see later sections in this spec).

### Meta / Attributes (declaration annotations) (design direction)

Oren adopts a **unified attribute model** for “decorators” and “field annotations”.
The syntax is inspired by Python’s `@decorator`, but the semantics are intentionally different:

- **Python:** `@decorator` is runtime function transformation (`f = decorator(f)`).
- **Oren:** `@attr(...)` is **compile-time metadata**, not arbitrary code execution.

This design is chosen to preserve:

- deterministic builds
- AVM governance and policy scan safety (scan-before-execute)
- multiverse friendliness (metadata must not change semantics unless explicitly specified)

#### Syntax (conceptual)

Attributes attach to declarations:

- functions
- types (`struct` / future `enum` / future `trait`)
- impl blocks (future)
- parameters (future)
- fields (future)

Rolling status note (implementation reality):

- Attributes are implemented today for: functions, types, parameters, and fields.
- Some attributes are pure metadata, while a small reserved set are compiler directives
  (e.g. packed byte views / ABI layouts).

Example (function):

```oren
@trace("net.connect")
@cap.requires(domain="NET", ops=["tcp_connect"])
fn tcp_connect(ip, port, timeout_ms) { ... }
```

Example (field annotation):

```oren
struct User {
    @doc("database primary key")
    @serde.rename("user_id")
    id
}
```

#### Determinism rules (must-haves)

1) **Unknown attributes are allowed and inert by default**
   - If the compiler does not recognize an attribute, it must not change code generation, execution, verification, gas/time, or policy scan results.
   - Unknown attributes may be preserved for tooling (docs/IDE/disasm metadata), but are semantically ignored.

2) **Attribute arguments are compile-time constants (v0)**
   - Allowed: `int`, `bool`, `string`, `nil` (and later: constant list/map literals if/when const-literals are formalized).
   - Not allowed in v0: arbitrary expression evaluation or calling functions inside attribute arguments.

3) **Reserved namespaces**
   - Compiler/tool-reserved: `oren.*`, `avm.*`, `cap.*`, `ffi.*`, `codegen.*`, `trace.*`

4) **Ergonomic aliases (surface syntax)**
   - For readability, the compiler accepts a small set of short aliases and canonicalizes
     them before strict-mode validation and before emitting metadata.
   - Canonical form is what gets embedded into `.obc` metadata / `--metadata` JSON.
   - Current aliases:
     - `@pack` → `@oren.packed`
     - `@abi` → `@oren.abi`
     - `@json.*` → `@serde.*` (serde namespace is canonical for tooling + future codegen)

#### Stdlib impact: JSON serde (rolling plan)

The primary near-term reason attributes exist in this repo is **compile-time-governed serde**:

- `@serde.rename("wire_name")` for field/key remapping
- `@serde.skip()` to omit a field
- `@serde.default("...")` / `@serde.default(0)` (literal-only in v0) for missing fields

**Determinism rule:** serde attributes must not introduce runtime code execution. They are metadata only.

Implementation staging (rolling):

1) Preserve attrs through parsing/linking and expose them to tooling (native `--metadata`, and embedded `.obc` metadata).
2) Provide `std/json` that is portable across backends (no reliance on runtime reflection).
3) Add attribute-driven codegen helpers (compiler plugin phase / macro phase), or AVM metadata query primitives, to enable ergonomic `json.encode(User{...})` / `json.decode(User, "...")`.
   - Library/user metadata should use a vendor prefix (recommended): `myorg.*`, `acme.*`, etc.

4) **Strict attribute mode (governance)**
   - For audited builds (and later swarm consensus workflows), Oren should support a strict mode:
     - unknown attributes are a compile error unless explicitly declared/allowed
     - reserved namespace misuse is always an error

#### Hashing and artifact identity (important for swarm / consensus)

If/when `.obc` gains a metadata section that contains attributes:

- **Execution identity** (`program_hash`) must be derived from semantics (code + constants), not from inert metadata.
- Metadata may have its own hash (`meta_hash`) for auditing/debugging, but must not affect consensus execution identity.


#### Trait ergonomics (direction)

To avoid boilerplate (e.g. implementing `Eq`/`Add` for every integer width), Oren’s trait system should support:

- **default methods** in trait definitions
- **blanket impls / generic impl templates** (later) with strict coherence rules
- **derive-style expansion** (attribute-driven) for structural/data traits like serde

This stays compatible with AVM determinism because resolution is compile-time and overlap is forbidden (or must be explicitly disambiguated).

### Values and Types
The runtime is dynamically typed. Values include:
- `nil`
- `bool` (`true`/`false`)
- `int` (signed 64-bit in the C runtime; two’s complement)
- `float` (**IEEE-754 binary64 / float64**)

### Varargs (rolling)

Oren supports **varargs parameters** at the end of a parameter list:

```oren
fn sum(x, ...rest) {
    // `rest` is a list of extra arguments (possibly empty).
    return x
}
```

Semantics (v0 / rolling):

- Only one varargs parameter is allowed, and it must be the **last** parameter.
- The varargs binding is always a **list** (possibly empty).
- Calls may supply **zero or more** extra arguments:
  - `sum(1)` binds `rest = []`
  - `sum(1, 2, 3)` binds `rest = [2, 3]`

Backend note (rolling):

- Backends may lower varargs through wrapper calls or call-site packing, but the observable semantics
  must remain the same across C/native/AVM bytecode.
- `string` (byte string)
- `list` (ordered, **heterogeneous**)
- `map` (keyed, deterministic iteration order; see “deterministic maps contract”)
- `python object` (opaque wrapper used by the optional Python FFI)

#### Lists are heterogeneous (by design)

Oren `list` is a heap container of dynamic values (a `list<OrenValue>` conceptually):

- A list may contain mixed types: `[1, "two", nil, true]`.
- Indexing (`xs[i]`) returns a dynamic value.
- `for x in xs { ... }` iterates elements in index order.

If you need **homogeneous memory layout** (HPC/FFI/SIMD kernels), the v0 path is:

- **typed buffers** (planned/partial) rather than forcing `list` to become homogeneous.

#### Numeric model (important for cross-backend correctness)

Oren currently has *one* scalar floating-point type:

- `float` is **float64** (binary64).

Implementation reality today:

- **C backend:** stores `float` as a C `double` (`OREN_TYPE_FLOAT`).
- **Native backend (ARM64):** represents `float` values as the **raw 64-bit IEEE-754 bit pattern** in a 64-bit register; floating ops use dedicated intrinsics (`fadd/fsub/fmul/fdiv`) and preserve bit-level results.
- **AVM:** float64 is now wired end-to-end in the bytecode backend and VM:
  - float literals compile into `.obc` as **f64 bit-pattern constants**
  - arithmetic `+ - * /` and comparisons `< <= > >=` support numeric mixing (`int`/`float`) similar to the C runtime
  - `+` also supports string concatenation (`"a" + "b"`)

  This is still **rolling** (no stable ISA guarantee yet), but it is now covered by canonical AVM tests.

Important rolling note:

- Operator-level float arithmetic is rolling and was historically inconsistent across backends:
  - **C backend / AVM:** `+ - * /` on floats works directly.
  - **Native backend (ARM64):** `+ - * /` now lowers to FP ops when the compiler can prove the expression is “floaty” (float literals, float intrinsics, and locals/globals assigned from floaty expressions). Otherwise it remains integer/pointer arithmetic.

  This is a pragmatic v0 bridge until Oren has a stronger type story for numeric operators.

If you need **float32** in v0, the recommended path is **typed buffers** (`F32_BUF`) rather than introducing a second scalar float tag immediately (see “Planned” below). This avoids a large cross-backend rewrite of the dynamic value representation.

#### Default widths vs explicit widths (recommended policy)

Oren is currently dynamically typed, but numeric *width* still matters for:

- scientific computing (typed buffers, SIMD kernels)
- stable cross-platform serialization
- FFI and system boundaries

Recommended policy (minimal rewrite, maximum clarity):

1) **Keep ergonomic defaults**
   - `int` is signed 64-bit (`i64`) in the reference runtime today.
   - `float` is `f64` (binary64) today.

   These defaults are chosen because they:
   - avoid “pointer-width drift” across targets
   - are easier to keep deterministic across backends (C/native/AVM)
   - are generally sufficient for orchestration logic (agent workflows)

2) **Add explicit fixed-width numeric types (for performance + correctness)**
   - Signed/unsigned integers: `i8/i16/i32/i64/i128` and `u8/u16/u32/u64/u128`
   - Floats: `f32` and `f64`

   These should be used for:
   - typed buffers (`F32_BUF`, `I32_BUF`, etc.)
   - binary protocols / hashing / stable encodings
   - FFI boundaries where exact size matters

3) **Treat `usize`/`isize` as “FFI/pointer boundary types” (optional, later)**
   - If introduced, `usize` must be defined precisely as “pointer width of the target”.
   - For deterministic `.obc` / AVM workflows, prefer fixed widths (`u64`) unless the program is explicitly declared “native-only”.

Design note:

- Introducing fixed-width numeric types does not require a full static type system on day 1.
  A staged approach can start with:
  - typed buffers and numeric ops that explicitly operate on `F32_BUF`/`I32_BUF`
  - literal suffixes for compile-time constants (e.g., `1u32`, `1i64`, `1.0f32`) later
  - explicit conversion builtins (`u32(x)`, `i64(x)`, `f32(x)`) once semantics are defined
  - only later (optional) a broader static type checker

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

#### Type-annotation syntax (rolling, hybrid semantics in v0)

Oren supports a universal type-annotation sugar:

- `var x: u64 = expr`
- `x: u64 := expr`
- `for x: T in iterable { ... }`
- `fn f(x: T, y: U) { ... }`
- `fn f(x: T): U { ... }`

In **v0**, annotations are a **rolling hybrid**:

- Oren remains dynamically typed at runtime, but the compiler already consumes some annotations in deterministic lowering passes.
- Annotations are **inert by default** unless a specific lowering pass defines deterministic semantics.

Current semantics (implementation reality):

- `bool`: deterministic normalization via `oren_bool_norm(x)` (avoids backend-specific “truthiness” mismatches)
- small integers (`u8/i8/u16/i16/u32/i32`): deterministic wrap/truncate casts at field init, local init, and function boundaries
  - integer casts accept **int or float** inputs
  - float inputs truncate toward zero first (via `oren_trunc_int(x)`), then wrap/truncate to the target width
    - `NaN` becomes `0`
    - float values outside int64 range clamp deterministically:
      - `+inf`/overflow → `INT64_MAX`
      - `-inf`/overflow → `INT64_MIN`
- `f32`: deterministic rounding boundary (via `oren_f32_round(x)`); `f64` remains the default float precision
- endian-tagged integer kinds (`u16be`, `u32le`, etc.) are treated as the same width for value casts, but matter for packed-byte views and ABI layouts

Other annotations are currently metadata-only and exist primarily for tooling and future stabilization (v1).

Type names like `u8`, `i32`, `f64`, `u16be`, etc. are **language-reserved type tokens** intended to become true explicit types as the v1 type system is stabilized.

Important rolling note on `i128/u128`:

- The syntax tokens exist and are usable in ABI/layout contexts (`@abi` structs, `sizeof`/`offsetof`).
- Full runtime-semantic `i128/u128` arithmetic is **not** stabilized yet; until it is, treat `i128/u128` as **ABI/layout-only** rather than as a general numeric type in expressions.

Implementation note (current compiler):

- The lexer recognizes these as dedicated tokens (not plain identifiers).
- The parser treats them as **identifier-like** in expression/dotted-name contexts, so existing code such as `ints.u8(x)` continues to work.

### Control Flow
- `if cond { ... } else { ... }` executes a block based on truthiness of `cond`.
  - The grammar treats `if` as an expression, but the C backend only supports it in statement position.
- `while cond { ... }` repeats while `cond` is truthy.
- `for` has two forms:
  - Condition-only: `for cond { ... }`
  - Three-clause: `for init; cond; post { ... }`
- `for <name> in <iterable> { ... }` is iterator sugar (rolling).
- `for <name>: <Type> in <iterable> { ... }` is the same, with an annotation on the loop binding:
  - in v0 this does **not** require `<iterable>` to be homogeneous
  - it is primarily for readability, tooling, and future type-checking
  - It is a source-level desugaring that relies on a runtime hook `oren_iter_next(iterable, idx, out_pair)`.
  - Iterator hook contract:
    - `oren_iter_next(container, idx:int, out_pair:list|nil) -> [ok:int, value]`
    - `out_pair` is a reusable list buffer (length ≥ 2) used to avoid per-iteration allocations
    - `ok == 1` means `value` is valid for this `idx`
    - `ok == 0` means iteration is complete
  - Current container coverage (rolling):
    - `list`: yields elements in index order
    - `map`: yields **keys** in deterministic key order (see deterministic maps contract)
    - `string`: yields byte codepoints (`0..255`), stopping at NUL terminator
    - `bytes` (AVM): yields `u8` values (`0..255`)
    - typed numeric buffers: yields element values (`i32/i64/f32/f64`) in index order
    - typed buffer view lists (portable stdlib encodings):
      - slice view: `[buf, off, len]`
      - strided view: `[buf, off, len, stride]`
      - these iterate element values (not metadata fields)
  - Streams / iterators beyond these built-ins (rolling):
    - v0 supports a minimal, portable “data iterable” protocol: an **iterable map** with the marker key `__iter`.
    - Backends may recognize these objects inside `oren_iter_next` to implement stream-like iteration
      without adding new VM value kinds.
    - Initial supported adaptor: `range` (stdlib helper `lib/std/iter.oren`):
      - `iter.range(n)` yields `0..(n-1)`
      - `iter.range3(start, end, step)` yields `start, start+step, ...` while:
        - `step > 0`: value `< end`
        - `step < 0`: value `> end`
        - `step == 0`: yields an empty sequence (deterministic; avoids hangs)
      - Representation (implementation detail, rolling):
        - `{"__iter":"range","start":0,"end":N,"step":1}`
  - Trait-based iterable extension (rolling v1, static-first, no vtables):
    - If the loop iterable is a **bare identifier** (e.g. `for x in it { ... }`) and `it` has a known
      type annotation in scope, the compiler may rewrite the underlying iterator hook call:
      - source desugaring: `oren_iter_next(it, idx, out_pair)`
      - rewrite (if available): `__oren_impl__Iterable__<Type>__iter_next(it, idx, out_pair)`
    - To opt in, define:
      - `trait Iterable { fn iter_next(self, idx, out_pair); }`
      - `impl Iterable for MyType { fn iter_next(self, idx, out_pair) { ... } }`
    - This allows custom deterministic iterables (streams/ranges/adaptors) without adding runtime value kinds,
      and without runtime vtables in hot loops.
    - If no `Iterable` impl is present, behavior falls back to the normal v0 hook (`oren_iter_next`).
- `break` exits the nearest enclosing loop (`while`/`for`).
- `continue` skips to the next loop iteration.
- `for init; cond; post { ... }` three-clause form: `continue` executes the `post` clause before re-checking `cond`.
- `return expr` returns from the current function. A return value is always required; use `return nil` if needed.

### Builtin container method sugar (rolling)

Oren supports a small amount of container method sugar to keep code modern and readable,
while still lowering deterministically in v0:

- `xs.push(v)` → `oren_list_push(xs, v)` (**returns `nil`**)
- `xs.len()` → `oren_list_len(xs)`
- `m.set(k, v)` → `m[k] = v` (**statement-only sugar**)
- `m.get(k)` → `m[k]`
- `m.len()` → `oren_map_len(m)`
- `b.len()` → `oren_buf_len(b)`

Important: this is **best-effort** in rolling v0. The lowering only applies when the compiler
can infer the receiver kind from syntax/local assignments (needed because the native backend
runtime values are untagged).

### Concurrency (v0)
Rolling note: Oren has **multiple execution backends** (C, native, AVM). The syntax surface is shared,
but concurrency is still **rolling** and backend-specific.

#### `spawn` / `join` (exists today; backend-dependent)

- Surface syntax:
  - statement form: `spawn f(x, y)`
  - expression form: `var h = spawn f(x, y)`
- **Evaluation**: argument expressions are evaluated in the parent context before spawning.
- Return value: a backend-defined “handle” (opaque integer/pointer; treated as `Any` in v0).

Backend behavior (rolling):

- **AVM backend**: `spawn` creates a **deterministic VM task** (green thread) scheduled by the AVM runtime.
  - `oren_join(handle)` and `oren_yield()` are VM opcodes (portable, snapshot-safe).
  - See `docs/AVM_SPEC_V1.md` (tasks + channels + select).
- **C backend**: `spawn` uses `pthread_create` and returns a pointer-like handle.
  - `oren_join(handle)` waits and returns the spawned function’s return value.
  - `oren_detach(handle)` / `oren_join_all()` exist in the C runtime (rolling; not yet mirrored in native runtime).
- **Native backend (Tier‑1 bring-up)**: `spawn` is currently implemented syscall-first as **fork + pipe** on POSIX.
  - Handle layout (implementation detail): `[pid, read_fd]` stored in a small heap object.
  - `oren_join(handle)` waits for child termination and reads the return value from the pipe.
  - Windows does not support `fork`; native `spawn/join` is not Tier‑1 complete on Windows yet.
    Use PROC primitives (`oren_proc_spawn`, `oren_system`) for Windows process execution in the interim.

#### Channels + `oren_select*` (rolling; AVM + native macOS/Linux)

Two low-level concurrency primitives exist today as **runtime builtins** (not keywords):

- `oren_new_channel() -> ch`
- `oren_chan_send(ch, val) -> ok` (rolling: returns `1`)
- `oren_chan_recv(ch) -> val` (blocks if empty)
- `oren_select_recv([ch1, ch2, ...]) -> [idx, val]` (blocks until any channel has a queued value)
- `oren_select(cases) -> [idx, payload]` (blocks)
  - case encoding (data):
    - recv case: `[0, ch]`
    - send case: `[1, ch, val]`
  - payload:
    - recv: received value
    - send: `1` (rolling “ok” marker)

Backend behavior (rolling):

- **AVM backend**: channels + select are **VM opcodes** (deterministic + snapshot-safe).
- **Native backend**:
  - On macOS: implemented over **pipes + kqueue/kevent**.
  - On Linux: implemented over **pipes + epoll**.
  - On Windows: pipe-based channels/select are not implemented yet (needs IOCP or a new channel implementation).
  - See `lib/runtime_native/010_channels_globals_consts.oren` and `lib/runtime_native/245_select.oren`.

Design direction:

- A future language-level `select { case ... }` syntax is planned as sugar over `oren_select(...)`,
  after the CoreIR + scheduler model stabilizes (see `docs/CONCURRENCY_MODEL.md` and `docs/NATIVE_GMP_SCHEDULER.md`).

### Functions
- `fn name(params) { ... }` defines a named function.
- Calls: `f(x, y)`
  - Calls to Oren-defined functions compile to direct C/Native calls.
  - Calls to Python objects use the runtime’s `oren_call_obj`.

#### First-class functions and lambdas (v0)

- Functions are **first-class values**:
  - A function identifier in expression position yields a callable function value (usable as an argument, stored in variables, returned from other functions).
  - Lambdas are anonymous functions: `|x, y| x + y` and empty-params lambdas `|| expr`.
  - Lambdas can also have a **full block body** (multi-line, locals, control flow), using braces:
    - `|n| { var acc = 0; while acc < n { acc = acc + 1 }; return acc }`
- Calling a function value uses the normal call syntax: `f(1, 2)`.
- `spawn` also uses normal call syntax and can spawn calls to function values/closures (not only direct function symbols).

#### Lambdas and closure capture semantics (v0)

- Lambdas **auto-capture** free variables from their surrounding scope.
- Capture is **by value** (snapshot at lambda creation time), not by reference.
- The capture list order is deterministic (source-order of first use), which is important for replayability/consensus in deterministic modes.

#### Fixed arity vs variadic calls (rolling reality)

- User-defined Oren functions are **fixed-arity by default**, but **variadic parameters are implemented**:
  - Fixed arity: `fn f(a, b) { ... }` must be called as `f(x, y)` (exactly 2 args).
  - Variadic param (varargs): `fn f(...rest) { ... }` or `fn f(a, ...rest) { ... }`
    - `rest` is bound to a **list** of extra arguments (possibly empty).
- Some builtins are variadic (notably `print(...)`) and typically lower to a runtime helper that consumes a list of arguments.

**Status update (rolling):** call-site spread is implemented:
- Syntax: `f(xs...)` or `f(a, b, xs...)`
- `xs` must be a list at runtime (or `nil`).
- This supports variadic builtins and “apply-style” calls, and is also used by the implementation strategy for user-defined varargs across backends.

#### Runtime reflection helpers (rolling)

For varargs dispatch and debugging/logging, the runtime provides small reflection helpers:

- `oren_type_tag(v)` → int tag matching `lib/runtime.h` `OrenType` enum values.
- `oren_type_name(v)` → stable string name for that tag.

Native backend note:

- Until native value tagging is fully implemented, numeric immediates (`int`/`bool`/`float`) may be indistinguishable in native mode, so `oren_type_tag` is best-effort for those values.
  - Track: `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`

### Compile-time execution (“comptime”) (design direction)

Oren should treat compile-time evaluation as a first-class concept, but it must stay aligned with the core niche:

- deterministic builds
- governance/capability model consistency
- AVM “compiler-in-AVM” viability (no host toolchain, no host effects by default)

Recommended staged model (minimal rewrite):

#### Stage C0: constant evaluation (pure, deterministic)

- Compile-time evaluation exists, but is limited to:
  - pure expression evaluation (numeric ops, string ops, bytes packing/unpacking helpers)
  - constant folding and constant propagation
- Forbidden at compile time:
  - FS/NET/PROC/ENV access
  - host time and nondeterministic RNG
- Compile-time evaluation is budgeted (gas/step cap) to prevent “compiler hangs”.

#### Stage C1: comptime functions (pure-only)

- Allow a restricted subset of function calls at compile time, with rules:
  - must be pure and deterministic
  - no host effects (capabilities default to CORE-only)
  - explicitly budgeted (gas/mem)

#### Stage C2: comptime reflection (bounded)

- Add only what is needed for tooling and safe codegen:
  - type queries (`type_of`)
  - field enumeration for structs (once structs become more than maps)
  - metadata generation

#### Stage C3 (optional, later): effectful comptime (explicit opt-in + recorded)

- If compile-time effects are ever allowed, they must be:
  - explicitly capability-scoped
  - record/replayable (like AVM effects)
  - bound into a “build job hash” so builds are auditable

Non-goal:

- Do not implement “arbitrary Zig-style comptime with host IO by default” early; that creates nondeterministic builds and forces large cross-backend rewrites.

### Lambdas (Closures)
- **Syntax**: `|params| expression` or `|params| { block }`
- **Semantics**:
  - Lambdas are first-class values.
  - They capture variables from their enclosing lexical scope (closures).
- **Examples**:
  ```oren
  var add = |a, b| a + b
  var x = 10
  var adder = |y| {
      return x + y  // captures x
  }
  ```

### Operators
- `+ - * / %`:
  - `int op int` yields `int`.
  - `int / int` is **signed** integer division with truncation toward zero.
  - `int % int` is the signed remainder consistent with trunc-toward-zero division (i.e. `a == (a / b) * b + (a % b)` and the remainder has the same sign as `a`).
  - Invalid cases are deterministic runtime panics:
    - division by zero
    - signed overflow (`i64_min / -1`)
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
  - shift counts must be in `0..63`; out-of-range is a deterministic runtime panic
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

Rolling (important for native backends):

- The cross-backend, production-intent key kinds today are **`int`** and **`string`**.
  - C backend and AVM currently support additional key kinds (`nil`/`bool`) but native backends intentionally stay conservative until native value tagging is complete.
- Native backends must choose a key-compare strategy (`==` vs `strcmp`) deterministically.
  - If a key is a literal (`"name"` or `123`), the compiler can lower it deterministically.
  - If a key is a variable and the compiler cannot infer whether it is an `int` key or a `string` key, the native backends fail deterministically (panic) rather than guessing.
- Explicit runtime helpers exist to remove ambiguity when you know the key kind:
  - `oren_map_get_str(m, key)` / `oren_map_set_str(m, key, value)`
  - `oren_map_get_int(m, key)` / `oren_map_set_int(m, key, value)`
  - `oren_map_set_*` returns the written value (matches `xs[i] = v` returning `v`).

### Structs and Classes
- `struct Name { a, b, c }` and `class Name { a, b, c }` declare a nominal “shape” with a fixed set of field names.
- Construction:
  - `Name(v1, v2, v3)` constructs a new instance (fields in declaration order).
- Field access:
  - `p.a` reads field `a`.
- Field assignment:
  - Supported in v0:
    - `p.a = v` mutates the field (equivalent to `p["a"] = v` at runtime).

Notes (rolling reality):

- **v0 representation is map-shaped across backends**:
  - `struct` values behave like maps keyed by field name (`string`), but retain a nominal type name for tooling/metadata.
  - This avoids backend-dependent field-offset tricks until a stable static layout exists.
- For deterministic layout/view use-cases (FFI / packet parsing / HPC views):
  - use `@abi` (layout-only) and `@pack` (packed byte views); do not rely on v0 struct layout.

### Object Model (recommended direction)

Oren’s long-term object model is:

- **traits / protocols + composition** as the primary abstraction mechanism
- **no inheritance-first design** (avoid fragile class hierarchies)
- **ADTs (sum types)** + pattern matching for closed-world modeling (agent state machines, workflows) (planned)

Rationale:

- traits/protocols align naturally with syscall-first and capability-based design:
  - FS / NET / PROC / ENV / TIME should be explicit “capability objects” rather than implicit globals
- composition keeps data layout and ownership clearer across backends (C/native/AVM)
- sum types make “self-healing agent loops” more robust by encoding states explicitly

Implementation reality today (bootstrap):

- `struct`/`class` are currently **data-only** shapes backed by runtime maps.
- There is no method syntax and no inheritance.

Planned evolution (minimal rewrite):

1) Introduce `trait` (protocol) declarations as compile-time contracts.
2) Add `impl Trait for Type` (or structural conformance rules) with mostly static dispatch.
3) Add optional dynamic dispatch via “trait objects” only where needed (plugin systems).
4) Add `enum` + `match` for sum types and exhaustiveness checking (later milestone).

**Status update (rolling):** `enum` and `match` are now implemented as **syntax sugar** (no static type checker yet).
- The parser expands `enum` declarations into a set of constructor `fn`s that return tagged maps.
- `match` expands into a tag-switching `if/else` chain and optional payload bindings.
- Exhaustiveness checking remains a later milestone.

`match` is a **contextual keyword**: it may still be used as an identifier (e.g. `var match = 1`) unless the parser sees the statement form `match <expr> { ... }`.
**Status update (rolling):** `trait` and `impl` syntax are now accepted by the parser as compile-time-only constructs.
- `trait` declarations have no runtime effect yet.
- `impl Trait for Type { ... }` is lowered deterministically into plain top-level `fn`s (see `docs/OBJECT_MODEL.md`).
- Design direction: Oren is **static-first** (`trait` = compile-time dispatch) with **explicit opt-in** runtime polymorphism (`dyn Trait`) when needed. See `docs/TRAITS_AND_POLYMORPHISM.md`.

#### Rolling extension: blanket impl (`impl Trait for any`)

Rolling v0 also supports a minimal **blanket impl** syntax:

```oren
trait Z { fn z(self); }

impl Z for any { fn z(self) { return 0 } }
impl Z for i64 { fn z(self) { return 7 } }
```

Semantics (rolling, deterministic):

- `any` acts as a **fallback receiver** in the *impl receiver position only*.
  It is best treated as a **contextual keyword**: special in `impl <Trait> for any { ... }`, otherwise not a “real type”.
- Resolution prefers the most specific impl:
  - exact `(Trait, Type)` impl wins if present
  - otherwise use the `(Trait, any)` blanket impl if present
  - otherwise: compile-time error (“missing impl”)
- This is still **compile-time rewriting** (no vtables / no dynamic dispatch).

Evidence: `tests/modules/test_trait_blanket_impl_any.oren`.


Example:
```oren
enum Option { None, Some(x) }
var a = Option.None
var b = Option.Some(123)
print(a.tag)      // "Option.None"
print(b.tag)      // "Option.Some"
print(b._0)       // 123
```

`match` example:
```oren
var v = Option.Some(7)
match v {
    case Option.None { print("none") }
    case Option.Some(x) { print("some=" + oren_int_to_string(x)) }
    default { print("other") }
}
```

### Modules and Imports
- `import math "path/to/math.oren"` compiles the referenced file as a module and binds it to the identifier `math` as a **namespace**.
- Accessing module members uses member syntax:
  - `math.PI`
  - `math.sqrt(2.0)`
- Import paths are resolved at compile time using the compiler’s module resolver:
  - **Filesystem imports**: relative to the directory of the importing file; absolute paths are allowed.
  - **Stdlib imports (recommended for users)**:
    - `import math "std:math"` (canonical scheme form)
    - `import json "std/json"` (path form; accepted as an alias of `std:json`)
    - The `.oren` extension is optional (e.g. `"std:json"` or `"std/json"` may resolve to `lib/std/json.oren` depending on the stdlib layout).
- Imports are resolved recursively at compile time; cyclic imports are an error.
- All top-level `var`, named `fn`, and `struct`/`class` declarations in an imported file are treated as module members.

Rolling restriction (current behavior):

- `import` is **compile-time only** and only meaningful at **module top level**.
  - The parser may accept `import` inside blocks, but backends treat imports as compile-time only; a block-scoped import is not meaningful.
  - This is expected to become a compile-time error in a future rolling milestone (so tools and AI agents should always emit top-level imports).

## Evaluation Order
Expression evaluation order is currently not specified by the language (rolling v0).

Status:

- **Rolling**: current compilers/backends are free to choose internal evaluation strategies.
- **Planned**: specify a stable evaluation order (or an explicit effect model) so optimizations are semantics-preserving across backends. Track: `docs/TODOS.md` (P0.2).

Practical guidance (all backends):

- Avoid relying on side effects inside subexpressions (especially in function call arguments and binary operators).
- If order matters, write explicit sequencing using `var` bindings:
  - prefer:
    - `var a = f()`
    - `var b = g()`
    - `h(a, b)`
  - over:
    - `h(f(), g())`

This matters even more in rolling mode because compilers may apply safe transforms like tail-call elimination (stackless recursion) and other normalizations, and without a specified order there is no portable “happens-before” guarantee inside an expression.

## Builtins (C Backend)
The C backend recognizes a few builtin functions and lowers them directly:
- `print(...)` → `oren_print(...)` / `oren_print_multi(...)`
- `py_import("name")` → `oren_py_import(...)`
- `system("cmd")` → `oren_system(...)`
- `exit(code)` → `oren_exit(...)`

## Runtime Builtins (Self-Hosting and Native Backend)
The self-hosted compiler and the (in-progress) native backend rely on a few additional runtime helpers:
- `oren_write_bytes(path, bytes)` writes a list of byte values (`0..255`) to a file (binary-safe).
- `oren_read_bytes(path)` reads a file as a list of byte values (`0..255`) (binary-safe; preserves `0x00`).
- `oren_bytes_from_string(s)` converts a string to a list of byte values (`0..255`).
- `oren_sha256_range(bytes, start, length)` computes SHA-256 over a subrange of a byte list and returns a 32-byte list.
- `oren_chmod(path, mode)` calls `chmod(2)` (used to set the executable bit on generated binaries).

### Endian-aware byte casting (network order)

Parsing network packets is a core requirement for syscall-first `.oren` libraries. Oren provides **deterministic**, **libc-free** helpers for reading integers from byte sequences with explicit endianness.

Current v0 reality:

- “bytes” are commonly represented as `list<int 0..255>` (from `oren_read_bytes`, sockets, etc.).
- Integers are currently dynamic `int` (signed 64-bit across backends).

Helpers (v0):

- `oren_bytes_get_u16_be(bytes, off)` / `oren_bytes_get_u16_le(bytes, off)`
- `oren_bytes_get_i16_be(bytes, off)` / `oren_bytes_get_i16_le(bytes, off)`
- `oren_bytes_get_u32_be(bytes, off)` / `oren_bytes_get_u32_le(bytes, off)`
- `oren_bytes_get_i32_be(bytes, off)` / `oren_bytes_get_i32_le(bytes, off)`
- `oren_bytes_get_u64_be(bytes, off)` / `oren_bytes_get_u64_le(bytes, off)`
- `oren_bytes_get_i64_be(bytes, off)` / `oren_bytes_get_i64_le(bytes, off)`
- `oren_bytes_put_u16_be(bytes, off, v)` / `oren_bytes_put_u16_le(bytes, off, v)`
- `oren_bytes_put_u32_be(bytes, off, v)` / `oren_bytes_put_u32_le(bytes, off, v)`
- `oren_bytes_set_u64_be(bytes, off, v)` / `oren_bytes_set_u64_le(bytes, off, v)` (mask/truncate semantics)

Example:

```oren
// IPv4 header layout (partial):
//   u8  ver_ihl
//   u8  dscp_ecn
//   u16 total_len (BE)
//   ...
var pkt = oren_read_bytes("ip.bin")
var total_len = oren_bytes_get_u16_be(pkt, 2)
```

Error behavior (portable rule):

- On invalid arguments (wrong type, out-of-bounds, byte out of range), these helpers return a **structured error object** (`oren_err(OREN_ERR_INVALID_ARG, "...")`), not UB.

Future direction (syntax sugar; no rewrite required):

- Add cast syntax that can specify byte order explicitly, e.g.:
  - `total_len = bytes[2..4] as u16@be`
  - `total_len = u16@be(bytes, 2)`

Until fixed-width scalar types are stabilized across all backends, these helpers are the portable, production-friendly way to parse protocol headers.

## Value Model: v0 “Mutable Handles” (and the future direction)

Oren v0 is **dynamically typed at runtime** and uses a pragmatic value model:

- Scalar values (`int`, `bool`, `float`) are immediate.
- Compound values (`string`, `bytes`, `list`, `map`, `struct`, `closure`) are **handles** to heap objects.
  - Passing a value copies the handle (pointer-sized), not a deep copy.
  - Lists/maps/structs are **mutable** in v0 (mutation is observable through shared handles).
  - Strings are immutable (treat them as values).

This makes v0 productive and keeps the compiler/backends simple while the language is still rolling.

### Long-term direction (not enforced in v0)

For large-scale agentic and HPC workloads, we may evolve toward:

- “immutability-by-default” at the language level (opt-in mutability), and/or
- compiler-driven copy elision / uniqueness optimization, and/or
- specialized layout-stable structs for FFI/HPC (separate from v0 map-shaped structs).

Those are orthogonal milestones and should not block making v0 correct and consistent across backends.

### Implications for networking and endian casting

For packet parsing, the ideal long-term ergonomics is to avoid allocations entirely:

- introduce **packed struct views** over a byte slice, with explicit endianness:
  - design idea:
    - declare a packed schema (metadata-only) and treat a “header value” as `{bytes, offset}`
    - reading `hdr.total_len` performs endian conversion from the underlying bytes
    - the view is immutable, bounds-checked, and deterministic

Proposed (not implemented) sketch using attributes:

```oren
@net.packed(endian="be")
struct Ipv4Hdr { total_len, proto, src, dst }

fn demo(pkt) {
    // view: zero allocation; just a handle to (pkt, 0)
    var hdr = pack_view(Ipv4Hdr, pkt, 0)
    var len = hdr.total_len
    return len
}
```

Constraints the design must enforce (for determinism + safety):

- only fixed-width scalar fields in v0 (u8/u16/u32/u64 and signed variants; bool later)
- explicit byte order at the schema or field level (no implicit host endianness)
- no unaligned host loads (must be bytewise reads so semantics are stable under interpreter/JIT/native)
- bounds checks are mandatory (out-of-bounds returns an error object, not UB)
- views must be non-owning (bytes slice outlives the view handle)

Until then, the endian helpers (`oren_bytes_get_u16_be`, etc.) are the stable base primitive.

### Native Backend Intrinsics
The native backend supports low-level **compiler/runtime intrinsics** for performance and system access.

Intrinsics are part of the “reserved surface” (prefix `oren_`, `sys_`) and may be lowered differently by each native backend, but must preserve **deterministic semantics**.

**Portable native intrinsics (Tier‑1 intent: ARM64 + x86_64):**

- **Float bit-casts (bitwise, no numeric conversion):**
  - `oren_f32_to_u32_bits(f32) -> u32`
  - `oren_u32_bits_to_f32(u32) -> f32`
  - `oren_f64_to_u64_bits(f64) -> u64`
  - `oren_u64_bits_to_f64(u64) -> f64`
- **Atomics (deterministic semantics; 64-bit word):**
  - `atomic_add(ptr, val) -> old` (fetch-add)
  - `atomic_cas(ptr, expected, new) -> old` (compare-and-swap)
- **Memory:**
  - `malloc(size)`: Allocate raw memory (pages).
  - `ptr_get(ptr)`, `ptr_set(ptr, val)`: Read/Write 64-bit word.
  - `ptr_get_byte(ptr)`, `ptr_set_byte(ptr, val)`: Read/Write 8-bit byte.
- **FFI:**
  - `ffi symbol` statement declares an external symbol (e.g., `ffi puts`).
  - Native backend may attach compile-time FFI metadata via attributes on the `ffi` declaration:
    - `@ffi.link("...")`: declare a dynamic library dependency (portable; maps to `--link ...`).
    - `@ffi.dll("name.dll")`: Windows convenience form for attaching a DLL to a single symbol.
    - `@ffi.ret("i32")`: declare an ABI-level signed 32-bit return so the backend can sign-extend to i64.

**ARM64-only today (rolling):**

- **SIMD (NEON)**:
  - `simd_add_2d`, `simd_sub_2d`: 128-bit integer addition/subtraction.
  - `simd_mul_4s`: 4x32-bit integer multiplication.
  - `simd_and_2d`, `simd_orr_2d`, `simd_eor_2d`: 128-bit bitwise operations.
- **Atomics (LSE)**: ARM64 backend may lower the portable atomics to LSE instructions when available,
  but must preserve the same semantics as the portable intrinsic contract.

SIMD enablement (rolling):

- SIMD is an **optimization only**; semantics must match the scalar reference behavior.
- Tier‑1 direction: x86_64 will expose a matching intrinsic family mapped to SSE2 (baseline) and optionally AVX2, but this is not treated as implemented until it has parity tests and stable feature detection across Linux+Windows.
- Native runtime uses env gating for native backend outputs:
  - `OREN_ENABLE_SIMD=1` enables SIMD fast paths when available.
  - `OREN_NO_SIMD=1` disables SIMD (wins over enable).
- Determinism is enforced by regression tests that compare scalar vs SIMD paths (bit-identical for covered kernels):
  - `tests/native/test_simd_suite.oren`
  - Implementation: `lib/runtime_native/040_capsule_core.oren` (env parse) + `lib/runtime_native/typed_buffers/**` (dispatch/wrappers) + `lib/compiler/arm64_native_expr/**` (NEON lowering).

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
- **Strings / chars (portable core surface):**
  - `oren_string_len(s)`
  - `oren_string_char_at(s, i)` (returns a 1-byte string)
  - `oren_string_slice(s, start, end)` (clamps indices; empty/out-of-range returns `""`)
  - `oren_char(code)` (build 1-byte string from `0..255`)
- **String concatenation (portable syntax):**
  - use `a + b` (backends lower to the appropriate helper; do not rely on `string_concat(...)` existing outside native mode)
- `oren_list_len(xs)` / `oren_list_push(xs, v)` for list work
- `oren_new_map(pairs...)` / `oren_map_len(m)`
- `oren_map_get(m, key)` / `oren_map_set(m, key, value)` (key-kind aware: `int` vs `string`)
- `oren_map_get_str/int` / `oren_map_set_str/int` (explicit key-kind, used by stdlib + native backends)

Native backend note (rolling):

- Some helper symbols exist in the syscall-first native runtime (e.g. `oren_string_eq`, `oren_int_from_string`, `string_concat`) to support bring-up and stdlib glue.
- These should be treated as **native-only** unless/until we standardize them across C + AVM + native.

## Not Implemented (Yet)
- user-defined methods / inheritance (classes are currently data-only; long-term direction is traits + composition)
- dynamic/runtime module loading

## Planned (Essential Modern Language Features)

This section lists **missing but essential** features for a modern, AI-first language. These are proposals and must be implemented across backends (C/native/bytecode) before being treated as stable.

### 1) `yield` and stackless coroutines (async building block)

Motivation:

- enables lightweight tasks and structured concurrency without requiring OS threads for every unit of work
- makes agent pipelines (fan-out/fan-in, streaming) practical

Design direction:

- implement `yield` via compiler lowering to a state machine (“stackless coroutines”) first
- later, consider `async/await` syntax as sugar on top of the same lowering

### 2) Built-in verification: `assert` and `test`

Motivation:

- agents need “generate → test → fix” loops as first-class workflows

Design direction:

- `assert(cond, msg?)` in core language
- `test "name" { ... }` blocks collected by a test runner

### 3) Structured error model (self-healing support)

Current v0 behavior:

- many failures are runtime panics

Planned direction:

- add a standardized `Result`-style convention (or explicit `try`/`catch`) so libraries can recover
- define a stable error value shape (code/message/context)

### 4) Visibility and module boundaries

Motivation:

- large agentic codebases need clean APIs and governance

Planned direction:

- `pub`/private visibility for module members
- avoid leaking internals across imports

### 5) Bytes + typed buffers (for ML-ish workloads)

Motivation:

- efficient byte and numeric buffer handling is required for:
  - bytecode loading
  - hashing
  - embeddings/vector math

Planned direction:

- a first-class `bytes` value type (packed)
- typed numeric buffers (`f32[]`, `i32[]`) with bulk ops

### 6) Variadic ergonomics (without a huge ABI rewrite)

Motivation:

- Many agent workflows need “collect arguments and forward them” patterns:
  - logging/tracing utilities
  - wrapper functions that forward to `print(...)` / formatting

Recommended staged design:

1) **Call-site spread/splat for variadic builtins**
   - Example: `print(xs...)` where `xs` is a `list` of values.
   - This does not require changing the calling convention for user-defined functions.
2) **User-defined variadic functions (optional, later)**
   - Example syntax: `fn f(a, ...rest) { ... }` where `rest` is a `list`.
   - Requires defining a stable cross-backend calling convention (likely “argc + argv” or “rest list packing”).
