# Oren Language Manual (Rolling)

This is the **practical** guide to writing Oren today.

It is intentionally different from the formal spec:

- **Manual**: “how to use it” + idioms + examples (what works *now*).
- **Spec**: complete grammar + exact semantics (`docs/LANGUAGE_SPEC.md`).

Oren is in **rolling ABI mode**: until an explicit stabilization milestone is declared, backwards compatibility is not guaranteed.

## Reading guide (AI- and tool-friendly)

Oren is designed to be usable by **humans and AI agents**. In rolling mode, the most common failure mode is “docs drift” (a doc claim that is no longer true).
This manual therefore follows a strict grounding rule:

- **If you need the truth for execution semantics, trust code + fixtures first.**
  - Canonical “what works today” snapshot: `docs/LANGUAGE_STATUS_AND_GAPS.md`
  - AI-friendly feature index: `docs/LANGUAGE_FEATURE_MATRIX.md`
  - Living spec fixtures: `tests/native/fixtures/`, `tests/modules/`, `tests/avm/`
  - Runnable integrated examples: `examples/` (suite: `make examples-test`)

When you change behavior (compiler/runtime/stdlib):

- add or update a fixture,
- update the relevant section(s) in this manual and/or `docs/LANGUAGE_SPEC.md`,
- update `docs/TODOS.md` if a new gap is discovered.

## Implementation map (where semantics live)

This section is a brief “map” for AI agents (and maintainers) to connect a language feature to the implementation that enforces it.

For a rolling “agent cache” of subtle internals (name resolution, lowering patterns, cross-backend contracts),
see `docs/IMPLEMENTATION_NOTES.md`.

### Compiler front-end (parsing + AST)

- Tokens/lexer: `lib/compiler/token.oren`, `lib/compiler/lexer.oren`
- Parser entrypoints: `lib/compiler/parser_parse/000_prelude.oren`, `lib/compiler/parser_parse/020_parser_b.oren`
- AST node constructors: `lib/compiler/ast.oren`

### Module system (imports + whole-program linking)

- Import graph + whole-program merge + aliasing: `lib/compiler/compiler/020_modules_linking.oren`
- Name rewriting (import prefixing): `lib/compiler/renamer.oren`

### Lowering pipeline (rolling semantics)

Many “language features” in rolling v0 are implemented as deterministic lowerings into simpler core constructs.
Start from:

- Build pipeline entry: `lib/compiler/compiler/040_build_pipeline.oren`

And then follow the referenced passes (impl lowering, generic specialization, container sugar, etc.) under `lib/compiler/`.

### Backends (code generation)

- C backend (portable): `lib/compiler/transpiler.oren` (+ `lib/runtime.[ch]`)
- Bytecode backend (`.obc`): `lib/compiler/codegen_bytecode/` (compiler) + `lib/avm/` (runtime, C)
- Native backend (Tier‑1 intent):
  - arm64: `lib/compiler/arm64_macho.oren`, `lib/compiler/arm64_elf.oren`
  - x86_64: `lib/compiler/x64_elf.oren`, `lib/compiler/x64_pe.oren`, `lib/compiler/x64_native_program.oren`
  - Runtime support: `lib/runtime_native/`

### Tests as spec (recommended entrypoints)

- Compile/runtime diagnostic contracts: `tests/native/fixtures/`
- Module/trait behavior: `tests/modules/`
- AVM determinism + capability model: `tests/avm/`

## 0) What Oren is

Oren is an **agent-native**, syscall-first language and toolchain:

- **Native** mode (server/desktop): compiles to native binaries (no libc shims for the *native backend output*).
  - Tier‑1 targets (rolling intent): `arm64` and `x86_64` across **macOS / Linux / Windows**.
  - Practical reality today:
    - macOS `arm64` is the most feature-complete native backend surface.
    - Linux/Windows `x86_64` (`--arch x64`) is Tier‑1 intent but still a growing bring-up subset (see `docs/TODOS.md` and `docs/REMOTE_X64_ENV.md` for real-hardware validation).
- **Portable** mode: compiles to `.obc` bytecode executed by AVM, supporting determinism, snapshots, and capability-governed virtualized domains (FS/NET/PROC/ENV/TIME).

## 0.1) Compiler CLI quick reference (modern, machine-friendly)

The Stage1 compiler (`./oren`) is intended to behave like a modern tool (Python `click` style):

- Subcommands: `oren build`, `oren emit-c`, `oren meta`, `oren dump`, `oren scan`, `oren completion`
- Human help:
  - `oren --help`
  - `oren build --help`
- Machine-readable help (for tools/agents):
  - `oren --help=json`
- Shell completion (generate scripts):
  - `oren completion bash`
  - `oren completion zsh`

See `docs/CLI_COMPLETION.md` for activation instructions.

### 0.2) Quickstart: build + run (all backends)

Build and run a program on the **C backend** (portable via host toolchain):

```bash
./oren build your_prog.oren --backend c -o build/your_prog_c
./build/your_prog_c
```

Build and run a program on the **native backend** (Tier‑1 targets, rolling):

```bash
./oren build your_prog.oren --backend native -o build/your_prog_native
./build/your_prog_native
```

By default, the compiler picks the **runtime host platform** when `--platform` is not provided:

- `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`
- Override with `--platform <arch>-<os>` or env `OREN_PLATFORM=<arch>-<os>`
- `--target`/`--arch` are legacy and now accept `auto` (prefer `--platform`)

Cross-compile examples:

```bash
# Linux ELF (run it on Linux, or via the Win11+WSL2 workflow in `docs/REMOTE_X64_ENV.md`)
./oren build your_prog.oren --backend native --platform arm64-linux -o build/your_prog_linux

# Windows PE (run it on Windows)
./oren build your_prog.oren --backend native --platform x64-windows -o build/your_prog_win.exe
```

Note: `--platform arm64-linux` / `--platform x64-linux` outputs a Linux ELF; run it on Linux (or via the Win11+WSL2 remote workflow in `docs/REMOTE_X64_ENV.md`).

Build and run **bytecode** on AVM:

```bash
./oren build your_prog.oren --backend bytecode -o build/your_prog.obc
./avm build/your_prog.obc
```

Passing program arguments in AVM (convention: `--` separates AVM flags and program args):

```bash
./avm build/your_prog.obc -- --flag value
```

Stack safety knobs (rolling):

- AVM: `./avm --call-depth-max 64 build/your_prog.obc`
- Native backend: `OREN_CALL_DEPTH_MAX=64 ./build/your_prog_native` (runtime override)
  - Native compile-time default: `./oren build ... --backend native --call-depth-max 64`
- C backend: `OREN_CALL_DEPTH_MAX=64 ./build/your_prog_c`

To disable the deterministic recursion guard (unlimited): `OREN_CALL_DEPTH_MAX=0 ...`

## 1) Program structure

Oren files are modules. A typical program has a `main` function:

```oren
fn main() {
    print("hello")
    exit(0)
}
```

Entry semantics (rolling, by current toolchain implementation):

- **Top-level statements execute** as the module loads (they compile into an internal `__top_level__` function).
- If `fn main()` exists, the runtime **calls it automatically** (native backend + AVM bytecode + C backend).
  - C backend implementation detail: the user `main` is emitted as a different C symbol to avoid colliding with the host `int main(...)` entrypoint.
- Avoid writing `main()` as a top-level call unless you intentionally want `main` to run twice.
- Program termination (rolling): **do not rely on `main` return value** for an exit code.
  - Different backends currently treat the `main` return value differently (some ignore it).
  - Use `exit(code)` for deterministic termination semantics across backends.

### Imports

Import with an alias:

```oren
import math "std:math"
import buffer "std:buffer"
```

Imported names can be qualified as `alias.symbol`.

Notes (rolling):

- `import` is intended as a **compile-time, module-level** declaration.
  - In practice, put `import ...` at **top level** (outside `fn` bodies / blocks).
  - The parser currently accepts `import` inside blocks, but backends treat imports as compile-time only; a block-scoped import is not meaningful and may become a compile error in the future.

### Stdlib import resolution (`std:` / `std/`)

The compiler supports a stable stdlib import scheme so user code does not need repo-relative paths like `../../lib/std/...`.

Supported stdlib specifier forms:

- `std:` scheme:
  - `import tcp "std:net/tcp"`
  - `import base64 "std:encoding/base64"`
- `std/` path form:
  - `import tcp "std/net/tcp"`
  - `import base64 "std/encoding/base64"`

Resolution rules (current compiler behavior):

- `.oren` extension is optional (`"std:net/tcp"` resolves to `.../net/tcp.oren`).
- The compiler finds the stdlib root directory (`STDLIB_ROOT`) in this priority order:
  1) `OREN_STDLIB_ROOT` environment variable (either `.../lib/std` or an install root containing `lib/std`)
  2) walk up from the importing file directory looking for `lib/std/argparse.oren`
  3) fallback: `lib/std` relative to the current working directory

If stdlib root cannot be resolved, `import "std:..."` is a hard compile error.

See also: `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md` (distribution story and future embedding).

### Selected stdlib modules (rolling; evidence-backed)

These stdlib modules exist today and are exercised by regression fixtures:

- CLI/strings:
  - `std:argparse` (smoke: `tests/native/test_argparse_smoke.oren`)
  - `std:strings` (used by `std:crypto/pem` smoke)
- Encoding / crypto helpers:
  - `std:encoding/base64` (TLS/HTTPS/WSS loopback fixtures)
  - `std:crypto/pem` (smoke: `tests/native/test_pem_decode_smoke.oren`)
  - `std:crypto/x509` (minimal helper layer; used by NET/TLS internals)
  - `std:crypto/tls` (TLS facade; alias-layer over `std:net/tls` while the TLS crypto-core split is implemented)
- Native NET stack (native backend; rolling Tier‑1 focus):
  - `std:net/tcp`, `std:net/udp`
  - `std:net/dns` (loopback fixtures + Windows default resolver smoke: `tests/fixtures/windows_dns_default_resolver_smoke.oren`)
  - `std:net/http` (structured response API; loopback fixtures)
  - `std:net/http2` (rolling: framing + loopback fixtures; covers SETTINGS/ACK + PING/ACK + CONTINUATION: `tests/native/test_http2_preface_loopback.oren`, `tests/native/test_http2_headers_loopback.oren`)
  - `std:net/http2_client` (rolling: minimal HTTP/2 client layer; handshake + single-stream request/response; exercised by `tests/native/test_http2_headers_loopback.oren`)
  - `std:net/hpack` (rolling: HPACK encode/decode v0 (includes Huffman); smokes: `tests/native/test_hpack_smoke.oren`, `tests/native/test_hpack_encode_rfc_c41.oren`)
  - `std:net/ws` (WebSocket v0; loopback fixtures)
  - `std:net/tls` (TLS wrapper; used by `https://` and `wss://` loopback fixtures)

For the detailed NET/TLS behavior and design constraints (determinism, pinning, providers), use the dedicated docs:

- `docs/NET_TLS.md`
- `docs/NET_HTTP2.md`
- `docs/NET_WEBSOCKET.md`
- `docs/ASYNC_IO_AND_SELECT.md`

### FFI symbols (`ffi name`)

Oren supports an `ffi` declaration statement to reference an external symbol:

```oren
ffi puts
puts("Hello FFI")
```

Recommended cross-platform form (native backend):

```oren
// Cross-platform C FFI example: call `puts`.
//
// On Linux, declare the libc dependency explicitly so the native backend emits a dynamic ELF.
// On Windows, attach the DLL used for symbol resolution.

@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi puts

@cfg(os="linux")
@ffi.link("libc.so.6")
ffi puts

@cfg(os="macos")
ffi puts
```

Grouping convenience (recommended when importing multiple symbols from the same library):

```oren
@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi { puts, strlen }

@cfg(os="linux")
@ffi.link("libc.so.6")
ffi { puts, strlen }
```

Rolling convenience:

- `ffi { sym1, sym2, ... }` expands to multiple `ffi sym` declarations, inheriting the same attributes.
- Per-item attributes are allowed inside the group and are merged with the outer attributes:
  - `@ffi.link("libc.so.6") ffi { @ffi.ret("i32") atoi, puts }`
  - This is especially useful when many symbols come from the same library but have different ABI return kinds, e.g. on Windows:
    - `@ffi.dll("crypt32.dll") ffi { PFXImportCertStore, @ffi.ret("i32") CertCloseStore, ... }`

Notes (rolling):

- `ffi` is a low-level escape hatch intended primarily for native interop and experiments.
- In **capsule** mode, `ffi` declarations are rejected (FFI bypasses capability gating).
  - Native backend:
    - **macOS** supports binding against `libSystem` for `ffi` calls (see `docs/NATIVE_BACKEND.md`).
    - **Windows x64** supports `ffi` via lazy `LoadLibraryA`/`GetProcAddress` stubs.
      - `--link` adds DLLs to the resolver search list (see `docs/NATIVE_BACKEND.md`).
      - `@ffi.link("...")` can attach a dynamic library directly to an `ffi` declaration (portable form; maps to `--link`).
      - `@ffi.dll("name.dll")` can also attach a DLL directly to an `ffi` declaration (Windows convenience; useful for stdlib).
      - `@ffi.ret("i32"|"u32"|"void")` can declare ABI return width/kind for some C-style APIs (signed int, unsigned u32, or void) so the native backend can normalize the return register to Oren’s i64 value model.
      - `@ffi.export` can export a top-level function symbol for callback-style interop (currently: arm64-macos + linux/arm64 + linux/x64 + windows/x64 native; see `docs/ATTRIBUTES.md`).
    - **Linux x64** supports `ffi` when `--link` is used (dynamic ELF + `dlsym` resolver). Without `--link`, calling an `ffi` symbol panics (see `docs/NATIVE_BACKEND.md`).
    - **Linux arm64** supports `ffi` when `--link` is used (dynamic ELF + `dlsym` resolver). Without `--link`, calling an `ffi` symbol panics (see `docs/NATIVE_BACKEND.md`).
  - C backend:
    - Oren does not have a stabilized “typed C FFI” surface yet, but you can still link extra C by compiling the emitted C yourself (see `docs/C_BACKEND.md`).

### Conditional compilation (`@cfg(...)`)

Oren supports a **minimal conditional compilation** attribute:

- source form: `@cfg(...)`
- canonical form (what metadata uses): `@oren.cfg(...)`

`@cfg` is evaluated at compile time based on the selected target platform:

- `--platform <arch>-<os>` (preferred), or
- env fallback `OREN_PLATFORM=<arch>-<os>`

If the target platform is unknown/missing, `@cfg(...)` is a compile-time error.

Why `@cfg` exists (and when to use it):

- Prefer writing platform-independent code by depending on stdlib abstractions (`std:net/tcp`, `std:net/tls`, etc.).
- Use `@cfg` when the source must bind to platform-specific surfaces that stdlib cannot fully hide, for example:
  - FFI library names / frameworks (`@ffi.dll("...")` on Windows vs `@ffi.link("...")` on Linux/macOS),
  - platform-specific constants/struct layouts at syscall boundaries,
  - host build/packaging details (e.g. Windows `.exe` naming in scripts).

Supported selector forms (rolling v0):

- Positional string selector:
  - `@cfg("linux")` / `@cfg("macos")` / `@cfg("windows")`
  - `@cfg("x64")` / `@cfg("arm64")`
  - `@cfg("x64-windows")` / `@cfg("arm64-linux")`
- Keyword selectors (CSV strings; AND across keys):
  - `@cfg(os="linux,macos")`
  - `@cfg(arch="x64")`
  - `@cfg(platform="arm64-linux")`
  - Negation keys: `not_os`, `not_arch`, `not_platform`

Important limitations (current implementation):

- `@cfg` is implemented for **declarations** (`fn`, `struct`, `ffi`, `var`).
- `@cfg` is **not supported on `import` yet** (the stage2 fast import scan cannot respect conditional imports).
  - Gate declarations *inside* the imported module instead.

## 2) Values and literals

### Integers

- Decimal: `123`, underscore separators allowed: `1_000_000`
- Prefixed bases:
  - hex: `0xFF`, `0xDEAD_BEEF`
  - bin: `0b1010_0110`
  - oct: `0o755`

Negative numbers are prefix expressions: `-1`, `-(a + b)`.

Integer arithmetic (rolling v0):

- `+ - * / %` are defined for `int`.
- `int / int` is signed integer division with truncation toward zero.
- `int % int` is the signed remainder consistent with trunc-toward-zero division (remainder has the same sign as the dividend).
- Invalid cases are deterministic runtime panics:
  - division by zero
  - signed overflow (`i64_min / -1`)

Examples:

```oren
if 7 / 3 != 2 { exit(1) }
if -7 / 3 != -2 { exit(2) }
if 7 % 3 != 1 { exit(3) }
if -7 % 3 != -1 { exit(4) }
```

### Bitwise ops and shifts (`& | ^ ~ << >>`)

- Bitwise ops operate on the 64-bit two’s-complement bit pattern of `int`.
- `>>` is a logical (zero-fill) right shift in rolling v0.
- Shift counts must be in `0..63`; out-of-range shift counts are a deterministic runtime panic (consistent across AVM/C/native backends).

### Floats (`f64` container in v0)

Float literals are compiled as **f64 bit-pattern constants**.

Supported forms:

- Decimal: `12.5`, `0.125`
- Scientific notation: `1e3`, `5e-1`, `12.5E+2`

Rolling notes (important for backends):

- Oren’s `float` value is represented as a **64-bit IEEE‑754 bit pattern** (an `f64` container) in v0.
- Casts like `f32(x)` / `f64(x)` are **numeric conversions** (rounding / widening), not bit reinterprets.
- For bit-level reinterpretation (useful for typed buffers and serialization), the native toolchain exposes:
  - `oren_f32_to_u32_bits(f32) -> u32` and `oren_u32_bits_to_f32(u32) -> f32`
  - `oren_f64_to_u64_bits(f64) -> u64` and `oren_u64_bits_to_f64(u64) -> f64`

Example (bit-cast roundtrip):

```oren
var bits = oren_f64_to_u64_bits(1.0)      // 0x3ff0_0000_0000_0000
var x = oren_u64_bits_to_f64(bits)
if i64(x) != 1 { exit(1) }
```

### Booleans and nil

- `true`, `false`
- `nil` is the canonical null value.

### Strings

Strings are double-quoted:

```oren
var s = "hello"
```

Rolling semantics (today):

- Strings are **immutable byte strings** (UTF‑8 by convention).
- All current backends store strings as **NUL‑terminated byte sequences** internally.
  - Practical consequence: embedded `\\0` is not supported as a stable cross-backend value.

Common operations:

- Concatenation uses `+`:

  ```oren
  var s = "hello" + " " + "world"
  ```

- Length uses `s.len()` (when the receiver is known as `: string`) or the explicit helper:

  ```oren
  var n = s.len()
  // or:
  var n2 = oren_string_len(s)
  ```

- Slice uses `oren_string_slice(s, start, end)`:
  - indices clamp to `[0, len]`
  - empty/out-of-range slices return `""`

  ```oren
  var mid = oren_string_slice("abcdef", 1, 5) // "bcde"
  ```

- Single-byte char extraction uses `oren_string_char_at(s, i)` (returns a 1-byte string).

Notes:

- Legacy code sometimes uses `string_concat(a, b)` directly; prefer `a + b` in modern Oren so
  backends can choose the optimal lowering.

## 3) Variables and assignment

Declare with `var`:

```oren
var x = 10
x = x + 1
```

### Short declarations (`:=`) (rolling)

Oren also supports a Go-like short declaration form:

```oren
x := 10        // sugar for: var x = 10
y := x + 2
```

And a typed variant (annotation sugar):

```oren
// typed short declaration (still non-semantic in rolling v0):
b: u16be := 6
```

Rolling notes:

- `:=` is a **declaration**, not an assignment.
- Type annotations are **non-semantic** in rolling v0: they must not change runtime behavior (they primarily enable deterministic lowering + tooling).
- `for ...; ...; post {}` does **not** allow `:=` in `post` (use `=` there).

This is exercised by `tests/avm/test_smoke_suite.oren` (`test_type_annotations_sugar`).

## 4) Control flow

### `if / else / else if`

Oren supports `else if` chains (no extra braces required):

```oren
if x < 0 {
    print("neg")
} else if x == 0 {
    print("zero")
} else {
    print("pos")
}
```

### `while`

```oren
var i = 0
while i < 10 {
    print(oren_int_to_string(i))
    i = i + 1
}
```

### `for` (C-style in v0)

```oren
for var i = 0; i < 10; i = i + 1 {
    // ...
}
```

Rolling note: there are two additional `for` forms that are supported by the parser and are
commonly used in low-level code:

- Infinite loop: `for { ... }` (equivalent to `while true { ... }`)
- Condition-only: `for cond { ... }` (equivalent to `while cond { ... }`)

### `break` / `continue`

Oren supports `break` and `continue` inside loops.

- `break` exits the **nearest** enclosing loop.
- `continue` skips to the next loop iteration.
  - In `for var i=...; ...; post { ... }`, `continue` still executes the `post` expression
    before re-checking the loop condition (this avoids “continue hangs” and is enforced by tests).

This behavior is exercised by:

- `tests/native/test_for_break_continue.oren`
- `tests/avm/test_for_break_continue.oren`

### `for x in iterable` (trait-based iteration sugar)

Oren supports a higher-level iteration form:

```oren
for x in xs { ... }
for x: i32 in xs { ... }
```

This is **source-level sugar** that desugars into repeated calls to the runtime hook:

- `oren_iter_next(iterable, idx, out_pair) -> [ok:int, value]`
  - `out_pair` is a reusable list buffer (length ≥ 2) used to avoid per-iteration allocations
  - `ok == 1` means “yield `value`”
  - `ok == 0` means “stop iteration”

Iteration proceeds in deterministic **index order** (`idx = 0, 1, 2, ...`) and stops at the first `ok == 0`.

#### Trait-based extension: `trait Iterable`

In rolling mode, Oren also supports a static-first trait extension for iteration:

```oren
trait Iterable {
    fn iter_next(self, idx, out_pair)
}
```

If the loop iterable is a bare identifier and an `impl Iterable for <Type>` exists, the compiler can rewrite the loop to call that impl (avoiding runtime vtables and keeping hot loops predictable).

Practical example (range-like iterable):

```oren
trait Iterable { fn iter_next(self, idx, out_pair) }

struct MyRange { start: i32, end: i32, step: i32 }

impl Iterable for MyRange {
    fn iter_next(self, idx, out_pair) {
        var ok = 0
        var val = nil
        if idx >= 0 && self.step != 0 {
            var v = self.start + idx * self.step
            var ok2 = (self.step > 0 && v < self.end) || (self.step < 0 && v > self.end)
            if ok2 { ok = 1; val = v }
        }
        var out = out_pair
        if out == nil { out = [0, nil] }
        out[0] = ok
        out[1] = val
        return out
    }
}

var r: MyRange = MyRange(0, 10, 1)
var sum = 0
for x: i32 in r { sum = sum + x }
```

For deeper details and the long-term polymorphism plan (static-first, optional `dyn Trait` later), see `docs/TRAITS_AND_POLYMORPHISM.md`.

### `switch` / `case` (multi-branch dispatch)

Oren supports `switch` statements for multi-branch control flow:

```oren
var x = 3
var y = 0

switch x {
    case 1 { y = 10 }
    case 2, 3 { y = 20 }      // multiple match values
    default { y = 30 }
}
```

Notes (rolling behavior, as exercised by tests):

- The `switch <expr>` expression is evaluated **exactly once** (useful when `<expr>` has effects).
- `case` can list multiple values separated by commas.
- A colon after the case list is accepted in rolling mode:
  - `case 2, 3: { ... }` (see `tests/modules/test_switch.oren`)
- `default` is optional; if present, it matches when no earlier case matches.

### `match` / `case` (pattern match sugar)

Oren supports `match` with `case` patterns (especially for enum sugar).

Important: **`match` is a contextual keyword**. You can still use `match` as an identifier unless the parser sees the statement form:

```oren
var match = 1  // valid
```

Statement form:

```oren
match v {
    case Option.None { print("none") }
    case Option.Some(x) { print("some=" + oren_int_to_string(x)) }
    default { print("unknown") }
}
```

This expands into a deterministic tag-dispatch chain internally (see the spec for details).

## 5) Functions and lambdas

### Functions

```oren
fn add(a, b) {
    return a + b
}
```

### Generic functions (rolling v0.1)

Oren supports **generic templates** with bracket type parameters:

```oren
fn id[T](x: T): T {
    return x
}
```

In the current rolling model, **generic calls must be explicitly specialized**:

```oren
var a = id[i64](1)
var b = id[u32](7)
```

Calling `id(1)` without `[...]` is a compile-time error (see `tests/native/fixtures/generic_unspecialized_call.oren`).

### Lambdas

Lambdas use `|params| expr` or `|params| { block }`.

```oren
var f = |x| x + 1
var g = |x, y| { return x * y }
```

Lambdas capture values (capture-by-value in the current lowering model).

### Varargs and call-site spread (`...`)

Oren supports two related features:

1) **Varargs parameters** (bind extra arguments into a list)
2) **Call-site spread** (pass a list as multiple arguments)

Varargs parameters:

```oren
fn count(...rest) {
    // `rest` is a list of extra args (possibly empty)
    return oren_list_len(rest)
}

fn sum1(x, ...rest) {
    var s = x
    var i = 0
    while i < oren_list_len(rest) {
        s = s + rest[i]
        i = i + 1
    }
    return s
}
```

Rules (rolling):

- Only one varargs parameter is allowed, and it must be the **last** parameter.
- The varargs binding is always a **list** (possibly empty).

Runtime type tags (useful for varargs dispatch):

- `oren_type_tag(v)` → int (stable tag numbers; see below)
- `oren_type_name(v)` → string (stable names for tags; intended for logging and simple branching)

Tag values (stable; matches `lib/runtime.h` `OrenType` enum):

- `0` `nil`
- `1` `int`
- `2` `float`
- `3` `bool`
- `4` `string`
- `6` `list`
- `7` `map`
- `8` `func`
- `9..13` typed buffers (`u8_buf`, `i32_buf`, `i64_buf`, `f32_buf`, `f64_buf`)

Rolling note (native backend):

- Until native value tagging is fully implemented, numeric immediates are best-effort:
  `int`/`bool`/`float` may all report as `int` (tag `1`) in native mode.
- Historically, the native backend used an untagged “i64 carrier” value model, which could cause type-unsafe equality:
  - `0 == nil` (and `0 == false`) could evaluate true in native mode.
  - Mitigation (2026-01-09): the compiler optimizer folds type-mismatched `==`/`!=` on literals, and folds `id == nil` / `id != nil` for locals trivially proven non-nil (regression-gated in quick integration).
  - Guardrail (rolling): `./oren --typecheck` rejects `bool/int/float == nil` comparisons when the scalar side is statically known (literals, casts, or annotated locals). `make test` includes smoke fixtures to prevent regressions.
  - Remaining: comparisons involving values of unknown dynamic type (e.g. map lookups, function parameters, FFI returns) can still observe native-mode aliasing until full tagged values land (`docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`).
    - Do **not** write `if x == nil { ... }` when `x` is numeric/bool (or you expect it to be).
    - Do not use `0` as an “optional/missing” sentinel in native mode unless you fully control the value flow and types.
- Beyond `oren_type_tag` / `oren_type_name`, full runtime reflection (fields/layout/type metadata) is not yet implemented and is tracked as a larger refactor in `docs/TODOS.md`.

Call-site spread (apply-style call):

```oren
fn add3(a, b, c) { return a + b + c }
var xs = [2, 3]
var r = add3(1, xs...) // expands to add3(1, 2, 3)
```

This is exercised by:

- `tests/modules/test_varargs.oren` (varargs + spawn/join)
- `tests/native/test_integration_suite.oren` and `tests/avm/test_smoke_suite.oren` (spread calls)

## 6) Types (practical)

Oren’s *runtime* (v0) is dynamically typed (boxed values), but the language includes **explicit width types** used for:

- ABI/layout and packed views
- typed buffers (`[]i32`, `[]f32`, `[]f64`, …) (HPC buffers; not boxed lists)
- deterministic casts at type boundaries

Common width tokens (non-exhaustive):

- ints: `u8 u16 u32 u64 u128`, `i8 i16 i32 i64 i128`
- floats: `f32 f64`
- `bool`
- endian tokens for packed views: `u16be`, `u32be`, etc.

### Casts

Casts are written as `Type(x)`:

```oren
var a = u8(256 + 5)  // wrap to 5
var b = i32(-1.9)    // truncate toward zero then wrap to width
```

The compiler lowers these to deterministic runtime primitives (not “user-level” function calls).

### Rolling v0: container kind hints (`list` / `map` / `buf` / `string`)

Oren’s type system is still rolling without a full static checker, but some sugar relies on
**receiver kind hints** so lowering stays deterministic across backends (especially the native backends).

In practice, you may see (or choose to use) annotations like:

```oren
var xs: list = [1, 2, 3]     // list receiver hint
var m: map = {"a": 1}        // map receiver hint
var s: string = "hello"      // string receiver hint
// import buffer "std:buffer"
// var b: []i32 = buffer.i32_new(16)  // typed-buffer receiver hint
```

These annotations are **compiler hints** in rolling v0, not stable “v1 types”.
See `docs/LANGUAGE_SPEC.md` (“kind annotations”) for the normative description.

Rolling note (native backends):

- numeric annotations like `: i64`, `: u64`, `: int` are treated as an “int kind” hint so map indexing `m[k]` can infer whether `k` is an integer key without relying on runtime pointer/int heuristics
- typed buffer annotations like `[]i32` / `[]f64` are treated as a “buf kind” hint for receiver sugar like `b.len()`

### Traits and `impl` (practical)

Oren supports `trait` declarations and `impl Trait for Type` blocks as a **compile-time** mechanism.
Today, the most visible use is trait-based iteration for `for x in iterable { ... }` (see above).

The broader design goal is:

- **static dispatch by default** (good for HPC and deterministic AVM execution)
- optional explicit runtime polymorphism later (e.g. `dyn Trait`) only where needed

#### Method call sugar + qualified calls

Trait methods are lowered to deterministic symbol names like:

- `__oren_impl__<Trait>__<Type>__<method>(...)`

The compiler also supports **method-call sugar**:

- `Type.method(args...)` calls the impl for that `Type`
- `x.method(args...)` calls the impl if `x` has a known type annotation in scope

When multiple traits define the same method name for the same receiver type, unqualified `x.method(...)` is **ambiguous** and rejected.

In that case (and in general for clarity), use a **trait-qualified call**:

```oren
trait AddLike { fn op(self, x); }
trait MulLike { fn op(self, x); }

impl AddLike for i64 { fn op(self, x) { return self + x } }
impl MulLike for i64 { fn op(self, x) { return self * x } }

var a: i64 = 3
var r0 = AddLike.op(a, 4) // 7
var r1 = MulLike.op(a, 4) // 12
```

See `tests/modules/test_trait_qualified_calls.oren` and `tests/native/fixtures/trait_impl_ambiguous_method.oren`.

#### Coherence (one impl per Trait×Type)

Rolling coherence rules enforced by the compiler:

- A given `(Trait, Type)` pair must have **exactly one** `impl` block.
- Duplicate impls are rejected.
- Splitting methods across multiple impl blocks is rejected deterministically.

See `tests/native/fixtures/trait_impl_duplicate.oren` and `tests/native/fixtures/trait_impl_split_blocks.oren`.

#### Blanket impls (`any`) (fallback impl; not a value type)

Rolling v0 supports a minimal blanket impl form:

```oren
trait Z { fn z(self); }

impl Z for any { fn z(self) { return 0 } }
impl Z for i64 { fn z(self) { return 7 } }
```

Exact impls (like `i64`) override blanket `any` impls deterministically.
See `tests/modules/test_trait_blanket_impl_any.oren`.

Notes (rolling):

- `any` is currently **only** meaningful in `impl <Trait> for any { ... }` as a “fallback receiver”.
  It is not a general “top type”, and you should not assume you can write `var x: any = ...` as a
  stable feature.
- This is still **compile-time rewriting** (no vtable / no dynamic dispatch). Do not confuse it with
  the planned `dyn Trait` direction.

See `docs/TRAITS_AND_POLYMORPHISM.md` for the design rationale and constraints.

## 7) Structs, attributes, and deterministic metadata

Structs:

```oren
struct Point {
    x: i32,
    y: i32
}
```

Classes (rolling; legacy object-shaped values):

```oren
class Rect { tl, br }

var r = Rect(Point(0, 0), Point(10, 20))
var w = r.br.x - r.tl.x
```

In the current rolling implementation, `class` is similar to `struct`:

- Constructor syntax is the same (`Rect(...)`).
- Field access is the same (`r.tl`, `r.br`).
- Values are represented as runtime map-shaped objects (see `docs/OBJECT_MODEL.md`).

Oren’s long-term direction is “traits + composition”, not inheritance-first OOP; consider `class` a compatibility/ergonomics feature rather than a design center.

Enums (rolling “tagged map” sugar):

```oren
enum Option {
    None,
    Some(x),
    Pair(a, b),
}

var a = Option.None
var b = Option.Some(123)
var c = Option.Pair(7, 9)

// All enum values are maps with:
// - a string tag like "Option.Some"
// - positional payload fields ._0, ._1, ...
if b.tag != "Option.Some" { exit(1) }
if b._0 != 123 { exit(2) }
```

Enum values are designed to work naturally with `match` patterns like:

```oren
match b {
    case Option.None { print("none") }
    case Option.Some(x) { print("x=" + oren_int_to_string(x)) }
    default { print("unknown") }
}
```

See `tests/modules/test_enum.oren` and `tests/modules/test_match_enum.oren`.

### Attributes

Attributes are compile-time metadata annotations. Unknown attributes are inert in rolling mode, but preserved for tooling.

Attribute syntax:

- `@name`
- `@ns.name(...)` (dotted names are allowed)

They can appear on:

- declarations (`struct`, `fn`, `var`)
- local `var` declarations inside blocks
- struct fields
- parameters

Example (parameter attribute):

```oren
fn f(@json(rename="x") a) { return a }
```

Common builtins:

- `@abi` for ABI/layout metadata
- `@pack` for packed “view over bytes” structs (network packet parsing)
- `@serde(...)` for serialization metadata (json/yaml/cbor)
- `@cfg(...)` for conditional compilation by target platform (`--platform`) — see `docs/ATTRIBUTES.md`

## 8) Containers (lists, maps, buffers)

Oren has three “container families” in rolling v0:

1) **Lists**: `[]` (dynamic, boxed values)
2) **Maps**: `{...}` (dynamic keys/values)
3) **Typed buffers**: `[]i32 / []f32 / []f64 / ...` (HPC-oriented numeric arrays; runtime tags include `I32_BUF`, `F32_BUF`, `F64_BUF`, etc.)

### Lists (dynamic)

Lists are dynamic sequences. Literal forms:

```oren
var xs = [1, 2, 3]
var ys = []
```

Indexing and assignment:

```oren
var x0 = xs[0]
xs[1] = 9
```

Rolling note: lists are **boxed** at runtime. Even if you conceptually treat `xs` as “list of ints”, elements are still stored as generic runtime values. If you need stable numeric performance and layout, use typed buffers (see below).

#### std:list helpers (recommended)

Prefer `std:list` for ergonomics and for keeping stdlib/internal code off kernel intrinsics:

```oren
import list "std:list"

var xs = [1, 2, 3]
list.push(xs, 4)
var n = list.len(xs)
var tail = list.slice_copy(xs, 1, n - 1)
```

`std:list` also provides:

- `list.clone(xs)` — **shallow clone** (new list; elements are not deep-copied)
- `list.slice_copy(xs, off, n)` — copy out a sub-range (returns `Err` on invalid ranges)
- `list.slice_view(xs, off, n)` — cheap O(1) iterable *view*

#### Slice views (cheap; iterable-only)

`list.slice_view(xs, off, n)` returns an “iterable map” consumed by `for x in it {}` via the runtime hook `oren_iter_next(container, idx, out_pair)`.

This is designed for “fast iteration without copy”:

```oren
import list "std:list"

var xs = [10, 20, 30, 40]
var view = list.slice_view(xs, 1, 2) // 20, 30

var sum = 0
for x: i64 in view {
    sum = sum + x
}
```

Rolling semantics:

- Slice views are **not** general-purpose “lists” (they are iterable objects).
- The view reflects the underlying list values at iteration time (no copy).
- Malformed views iterate as an empty sequence (deterministic; avoids crashes).

### Maps (dynamic)

Maps use `{k: v, ...}` syntax, and can be indexed:

```oren
var m = {"a": 1, "b": 2}
var v = m["a"]
m["c"] = 3
```

Rolling notes (native backends, v0):

- **Key kinds must be deterministic** for native codegen. Today the portable, fully-supported key kinds are:
  - `string` keys (e.g. `"a"`, `"field"`)
  - `int` keys (e.g. `0`, `42`)
- If you write `m[key]` or `m[key] = v` and `key` is a **variable**, the native backends may require the compiler to infer whether `key` is an `int` key or a `string` key.
  - Rolling behavior: if the key kind is not inferable statically, the compiler emits a **runtime dispatch**:
    - if `key` is a tracked heap string (`oren_find_node(key).kind == STRING`), treat it as a string key
    - otherwise treat it as an int key
  - This avoids unsafe numeric-range heuristics, but it is still an interim design until Oren has a fully tagged value representation for native execution.
- When you know the key is a string at runtime (common in parsers/codecs), you can use the explicit runtime helpers:
  - `oren_map_get_str(m, key)` / `oren_map_set_str(m, key, value)`
  - `oren_map_get_int(m, key)` / `oren_map_set_int(m, key, value)`
  - `oren_map_set_*` returns the written value (matches `xs[i] = v` returning `v`).

Example (dynamic string key):

```oren
var m = {}
var key = "hello"
oren_map_set_str(m, key, 123)
print(oren_int_to_string(oren_map_get_str(m, key)))
```

Rolling note: map keys are restricted to a small set of runtime types (see `docs/AVM_SPEC.md` and runtime code for the exact set).

### Typed buffers (HPC)

Typed buffers are the performance-oriented container family used by the SIMD and linalg layers.
They are created via intrinsics (or std wrappers) and support deterministic numeric kernels.

Examples of native/AVM intrinsics include:

- `oren_i32_buf_new(len)`
- `oren_f32_buf_new(len)`
- `oren_buf_load_f32(buf, idx)`
- `oren_buf_store_f32(buf, idx, val)`

See `docs/HPC_SERVER_PLAN.md` and `docs/AVM_NEON_MAPPING_PLAN.md` for direction and design constraints.
- `@cap.requires(domain="...")` for capsule/capability gating of host-effectful APIs (see below)

#### Strict attribute mode (compiler option)

For “lint-like” strictness (useful for production toolchains and schema-driven metadata), the compiler supports:

- `./oren build ... --strict-attrs`
- `./oren build ... --attr-allow-prefixes myorg.` (repeatable allowlist of custom namespaces)

In strict mode:

- unknown/forbidden attribute prefixes are rejected at compile time

See `tests/native/fixtures/strict_attrs_ok.oren` / `strict_attrs_bad.oren` (these fixtures can be exercised via the native test targets, e.g. `make test-native-all`).

#### ABI layout example

```oren
@abi
struct ABI1 {
    a: u8,
    b: u32,
    c: u16
}
```

You can query layout through syslib intrinsics:

```oren
oren_abi_sizeof("ABI1")
oren_abi_offsetof("ABI1", "b")
```

Note (multi-module builds):

- After module linking, type names may be linker-prefixed to avoid collisions.
- The `oren_abi_*` builtins accept **bare source names** (like `"ABI1"`) and the compiler resolves them by a unique suffix match.
  - If multiple ABI types share the same suffix, pass the fully-qualified linked name (the compiler will report an ambiguity error).

Invalid ABI queries (unknown type/field) are compile-time errors and emit machine-readable `OREN_DIAG` lines (see `tests/native/fixtures/abi_layout_error.oren`).

#### Packed view example (network parsing story)

```oren
@pack
struct H {
    v: u8,
    t: u8,
    len: u16be,
    src: u32be,
    dst: u32be
}

var bytes = [69, 0, 0, 84, 192, 168, 0, 1, 8, 8, 8, 8]
var h = pack_view("H", bytes, 0)
print(oren_int_to_string(h.src))
```

Packed views are designed to avoid heap pressure: they are “structured access over bytes”, not per-packet struct allocations.

## 7.5) Capsule mode and capability-gated APIs (native backend)

Oren has a rolling “capsule” model to make **host effects explicit**.
This is primarily a **compiler mode** plus a convention for annotating runtime APIs:

- In capsule mode, calls to functions annotated with `@cap.requires(domain="FS|NET|PROC|ENV|TIME|RNG")`
  are rejected unless that domain is explicitly allowlisted.
- Direct syscall intrinsics (`sys_*`) are always rejected from user code in capsule mode.
- `ffi` declarations are rejected in capsule mode (FFI bypasses capability gating).

Enable capsule mode at compile time:

```sh
./oren build your_prog.oren --backend native --capsule
```

Allow domains explicitly (comma-separated list):

```sh
./oren build your_prog.oren --backend native --capsule --cap-allow-domains FS,NET
```

Fixtures showing expected behavior:

- Capsule OK (pure compute): `tests/native/fixtures/capsule_ok.oren`
- Capsule BAD (direct syscall): `tests/native/fixtures/capsule_bad_syscall.oren`
- Capsule BAD (FS not enrolled): `tests/native/fixtures/capsule_bad_fs.oren`
- Capsule OK with FS enrolled: `tests/native/fixtures/capsule_ok_fs_allow.oren`

### Runtime policy knobs (env var driven)

Capsule mode is a **compile-time** capability gate, but the syscall-first native runtime also has a
**runtime** allowlist layer for “what exactly is permitted inside each domain”.

This is intentionally configured via environment variables so parent processes / “multiverse”
parents can safely constrain child universes without recompiling the child program.

These knobs are exercised by the “capsule runtime” fixtures under `tests/native/fixtures/`:

- **FS mounts**
  - `OREN_FS_MOUNTS="v/=build/mnt/"` (legacy: applies to both read+write)
  - `OREN_FS_MOUNTS_READ="v/=build/mnt/"` (read-only mounts)
  - `OREN_FS_MOUNTS_WRITE="v/=build/mnt/"` (write-enabled mounts)
  - The `v/` prefix is a *virtual path prefix*; the runtime rewrites `v/...` into the mounted host path.
  - Examples: `tests/native/fixtures/capsule_runtime_fs_prog.oren`,
    `tests/native/fixtures/capsule_runtime_fs_syscall_open_read_prog.oren`,
    `tests/native/fixtures/capsule_runtime_fs_syscall_open_write_prog.oren`.

- **FS allow prefixes** (alternative to mounts)
  - `OREN_FS_ALLOW_PREFIXES="build/mnt/,/tmp/"` (legacy: applies to both)
  - `OREN_FS_ALLOW_READ_PREFIXES="..."`, `OREN_FS_ALLOW_WRITE_PREFIXES="..."`
  - Use mounts when you want stable virtual paths; use allow-prefixes when you want direct host paths.

- **NET allowlists**
  - `OREN_NET_ALLOW_LOOPBACK=1` enables loopback endpoints (for local services / tests).
  - `OREN_NET_ALLOW_TCP_CONNECT="127.0.0.1:8080,10.0.0.1:*"`
  - `OREN_NET_ALLOW_TCP_LISTEN="127.0.0.1:*"`
  - Map-driven variants exist for multiverse use cases (see `OREN_NET_TCP_CONNECT_MAP` / `OREN_NET_TCP_LISTEN_MAP`).
  - Examples: `tests/native/fixtures/capsule_runtime_net_connect_prog.oren`,
    `tests/native/fixtures/capsule_runtime_net_listen_prog.oren`,
    `tests/native/fixtures/capsule_runtime_net_syscall_map_prog.oren`.

- **PROC allowlists**
  - `OREN_PROC_ALLOW_EXEC_PREFIXES="/usr/bin/,/bin/"` (CSV path prefixes)
  - `OREN_PROC_ALLOW_SYSTEM=1` (enables `oren_system(_timeout)`; shell-based convenience)
    - POSIX shell selection (rolling):
      - if `OREN_SYSTEM_SHELL` is set, it must be an absolute executable path (otherwise `oren_system_timeout` returns `-2`)
      - else `SHELL` is used if it is an absolute executable path
      - else fall back to common shells (`/bin/sh`, `/usr/bin/sh`, `/bin/bash`, `/usr/bin/bash`)
  - Env inheritance controls:
    - `OREN_PROC_INHERIT_ENV=1` inherit all parent env vars (**dangerous**, use sparingly)
    - `OREN_PROC_ALLOW_ENV_KEYS="PATH,HOME,OREN_TEST_SECRET"` only allow specific keys
  - Argv allowlists:
    - `OREN_PROC_ALLOW_ARGV="<path>|<argv0>[|<arg1>...],<path>|..."`
    - `|` is used as the argv delimiter inside each spec.
  - Examples: `tests/native/fixtures/capsule_runtime_proc_spawn_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_spawn_join_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_env_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_system_prog.oren`.

Notes:

- The runtime prints “CAPSULE DENY: ...” errors with hints pointing at these env vars when a call is blocked.
- In AVM/bytecode mode, the same high-level domains exist, but the allowlists are modeled as VM config rather than host env vars.

## 8) Typed buffers and HPC building blocks

Typed buffers are the canonical HPC container in Oren today:

```oren
import buffer "std:buffer"
import linalg "std:linalg"

var a: []f64 = buffer.f64_new(6)
var b: []f64 = buffer.f64_new(6)
// store elements using runtime helpers, then:
var out: []f64 = linalg.matmul_f64_buf(a, b, 2, 3, 2)
```

Design goals:

- avoid boxed list overhead in numeric kernels
- isolate hot loops so NEON microkernels can replace them without changing semantics
- deterministic accumulation order for consensus and testing

SIMD (Tier‑1 HPC: arm64 NEON now, x86_64 SSE/AVX next) in the native runtime (rolling):

- SIMD is **opt-in** and must not change semantics (scalar results are authoritative).
- Enable/disable (native backend outputs only):
  - `OREN_ENABLE_SIMD=1` enables SIMD fast paths when available.
  - `OREN_NO_SIMD=1` disables SIMD (wins over enable).
- Determinism guard: scalar vs SIMD paths must remain bit-identical for the covered kernels.
  - Primary regression suite: `tests/native/test_simd_suite.oren`.
  - Current reality: arm64 NEON fast paths are the most mature (macOS + Linux). x86_64 SIMD (SSE2 baseline, AVX2 optional) is planned once the x64 backend reaches full Tier‑1 semantic parity.

## 9) Deterministic math (no host libm)

The `std/math` module provides deterministic “libm-lite” functions implemented without calling host `libm`:

- rounding: `floor`, `ceil`, `round` (as float outputs)
- core: `sqrt`, `powi`, `exp2`, `exp`, `log2`, `ln`
- trig: `sin`, `cos`, `atan`, `atan2` (range-reduced, deterministic; `sin/cos` use Payne–Hanek-style reduction for huge |x|)

For exactness and determinism, tests often prefer:

- integer-representable float inputs
- explicit tolerances like `1e-12` (scientific literals are supported)

## 10) Concurrency (today)

Oren has `spawn` (rolling v0 restriction: spawns a call expression):

```oren
fn work(x) { return x + 1 }
var t = spawn work(10)
```

Call-site spread (`...`) works in `spawn` just like normal calls:

```oren
var xs = [10]
var t2 = spawn work(xs...)
```

To wait for a spawned task:

```oren
var r = oren_join(t) // returns the worker’s return value (or panics if the worker panicked)
```

Timeout join is also available:

```oren
// timeout_ms < 0 means “wait forever” (equivalent to oren_join).
// timeout_ms == 0 is a non-blocking probe (returns -60 if not done yet).
// timeout_ms > 0 waits up to a rolling join budget and returns -60 on timeout.
var r2 = oren_join_timeout(t, 20)
```

See `tests/modules/test_spawn_join_timeout.oren` and `tests/native/test_spawn_join_timeout.oren`.

Concurrency in AVM differs from native mode; see:

- `docs/CONCURRENCY_MODEL.md`
- `docs/AVM_CONCURRENCY.md`

### Channels + select (rolling; AVM + native macOS/Linux)

Oren also exposes low-level **channel primitives** (runtime builtins; not keywords yet):

- `oren_new_channel() -> ch`
- `oren_chan_send(ch, val) -> ok` (rolling: `1`)
- `oren_chan_recv(ch) -> val` (blocks if empty)
- `oren_select_recv([ch1, ch2, ...]) -> [idx, val]` (blocks)
- `oren_select(cases) -> [idx, payload]` (blocks)
  - recv case: `[0, ch]`
  - send case: `[1, ch, val]`
  - payload is the received value (recv) or `1` (send)

Example (recv-only select):

```oren
var c1 = oren_new_channel()
var c2 = oren_new_channel()
oren_chan_send(c2, 111)

var r = oren_select_recv([c1, c2])
// r == [1, 111]
```

Backend notes (rolling):

- AVM: channels + select are deterministic VM opcodes.
- Native: implemented over pipe fds (macOS: kqueue, Linux: epoll). Windows support is pending.

## 11) Tooling quick reference

The authoritative build/test workflow is in:

- `docs/BUILD_AND_VERIFY.md`
- `docs/TEST_SYSTEM.md`

### Machine-readable diagnostics (`OREN_DIAG`)

Both the compiler and runtime emit stable, machine-readable **single-line** diagnostics intended
for tooling and AI agents.

Format:

- `OREN_DIAG kind=<kind> code=<code> msg=<sanitized>`

Examples:

- Compile-time errors (parse/compile/codegen/typecheck) print an `OREN_DIAG` line to stderr and exit non-zero.
- Runtime failures (like `oren_fail(code, "msg")`) emit `OREN_DIAG kind=fail code=<code> ...` and exit with that code.
- Panics emit `OREN_DIAG kind=panic code=1 ...` (and may print a stack trace depending on backend/runtime).

Fixtures covering this contract:

- Runtime fail header: `tests/native/fixtures/diag_fail.oren`
- ABI/packview compile errors: `tests/native/fixtures/abi_layout_error.oren`, `tests/native/fixtures/packview_error.oren`

In rolling mode, a fast native verification step is:

```sh
make verify-native-quick
```

## 12) Test fixtures are a living spec (recommended)

The language and runtime evolve quickly in rolling mode. The most accurate “what works today” source is:

- `tests/native/fixtures/` (native + C backends; compile-time and runtime diagnostics)
- `tests/fixtures/` (targeted bring-up fixtures, including x86_64 native)
- `tests/modules/` (stdlib and module-level behavior)
- `tests/avm/` (AVM semantics and sandbox/determinism constraints)

This is intentional: fixtures are small, high-signal, and regression-friendly.

### Useful fixture groups (native backend)

- **Machine-readable compile errors** (`OREN_DIAG kind=compile|parse|codegen`):
  - Parse error contract: `tests/native/fixtures/parse_error.oren`
  - Codegen error contract: `tests/native/fixtures/codegen_error.oren`
  - Bytecode codegen error contract: `tests/native/fixtures/bytecode_codegen_error.oren`
  - Generic constraint failures: `tests/native/fixtures/generic_constraint_missing_impl.oren`

- **Deterministic runtime panics** (`OREN_DIAG kind=panic code=1`):
  - Division by zero: `tests/native/fixtures/arith_div0.oren`
  - Signed overflow (`i64_min / -1`): `tests/native/fixtures/arith_div_overflow.oren`
  - Shift count out of range: `tests/native/fixtures/arith_shift_oob.oren`
  - Deterministic recursion guard (call depth): `tests/native/fixtures/call_depth_overflow.oren`

- **Struct field assignment (rolling semantics)**:
  - OK path: `tests/native/fixtures/struct_field_assign_ok.oren`
  - Error path: `tests/native/fixtures/struct_field_assign_bad.oren`

### Capsule runtime fixture naming conventions

There are many “capsule runtime” fixtures. They are intentionally verbose so a failing case points at
exactly one syscall/domain edge.

- **FS (filesystems / mounts / syscalls)**:
  - High-level helpers: `tests/native/fixtures/capsule_runtime_fs_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_read_prog.oren`
  - Mount behavior: `tests/native/fixtures/capsule_runtime_fs_mount_read_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_mount_write_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_fs_syscall_open_read_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_syscall_unlink_prog.oren`, etc.

- **NET (tcp connect/listen + raw socket syscalls)**:
  - High-level: `tests/native/fixtures/capsule_runtime_net_connect_prog.oren`, `tests/native/fixtures/capsule_runtime_net_listen_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_net_syscall_connect_prog.oren`, `tests/native/fixtures/capsule_runtime_net_syscall_read_socket_prog.oren`, etc.

- **PROC (spawn/exec/system/env)**:
  - High-level: `tests/native/fixtures/capsule_runtime_proc_spawn_prog.oren`, `tests/native/fixtures/capsule_runtime_proc_system_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_proc_syscall_execve_true_prog.oren`, `tests/native/fixtures/capsule_runtime_proc_syscall_pipe_prog.oren`
  - Nested capsule behavior: `tests/native/fixtures/capsule_runtime_proc_child_capsule_parent.oren`, `tests/native/fixtures/capsule_runtime_proc_child_capsule_child.oren`

- **TIME (determinism constraints)**:
  - Syscall edges: `tests/native/fixtures/capsule_runtime_time_syscall_gettimeofday_prog.oren`, `tests/native/fixtures/capsule_runtime_time_syscall_nanosleep_prog.oren`

### x86_64 native bring-up fixtures (Tier‑1 roadmap)

The x86_64 native backend is Tier‑1, but still in bring-up. The x64 fixtures in `tests/fixtures/`
are the canonical incremental contract for what the x64 backend supports today:

- `tests/fixtures/x64_*_main.oren` are intended to compile under the native backend for Linux ELF + Windows PE (`./oren build ... --backend native --platform x64-linux` / `x64-windows`).
- Remote execution (Win11 + WSL2) is opt-in and can be done by copying the built artifact to a real x86_64 host.
- High-signal Tier‑1 fixtures (remote x86_64 gate; run via `scripts/verify_native_matrix.sh --targets x64-win-tier1` / `x64-wsl-tier1` with `--tier1-src <fixture>`; see `docs/REMOTE_X64_ENV.md`):
  - Closures + varargs: `tests/fixtures/tier1_native_lambda_varargs_main.oren`
  - Maps (empty map + dynamic string key kind): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren`
  - Strings (`+`, `len`, `slice`): `tests/fixtures/tier1_native_string_ops_main.oren`

## 13) Where to go next

- Formal language spec: `docs/LANGUAGE_SPEC.md`
- Evolution narrative (day0 → “compiler-in-AVM”): `docs/EVOLUTION_GUIDE.md`
- Roadmap/phases: `docs/ROADMAP.md`
- Current task tracker (execution order): `docs/TODOS.md`
