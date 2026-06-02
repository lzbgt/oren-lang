# Oren Language

**Last updated:** 2026-06-02

Oren is a rolling, self-hosted language and toolchain with three execution paths:
C, native machine code, and OBC bytecode for AVM. This page is the practical
language guide for writing correct Oren today. When an edge case matters, the
fixtures under `tests/` are the executable source of truth.

## Quick Start

```oren
import http "std:net/avm/http"
import json "std:json"

fn main() {
    var doc = http.get("https://note.local/data.json").text().json()
    if oren_is_err(doc) {
        print("request failed: " + oren_err_msg(doc))
        exit(1)
    }

    print(doc["o"]["title"]["s"])
    exit(0)
}

main()
```

Useful commands:

```bash
./oren build app.oren --backend native -o build/app
./oren build app.oren --backend c -o build/app_c
./oren build app.oren --backend bytecode -o build/app.obc
./avm build/app.obc
./oren build app.oren --typecheck
./oren dump linked app.oren
```

## Program Shape

Oren files are modules. Top-level statements execute in order after
compilation/linking, so scripts can be direct:

```oren
fn greet(name) {
    print("hello " + name)
}

greet("oren")
```

For applications, prefer an explicit `main()` and call it at the end.

## Values

Current value families include:

- `nil`
- booleans: `true`, `false`
- integers and floats
- strings
- lists: `[1, 2, 3]`
- maps: `{"name": "oren", "ok": true}`
- first-class functions and closures
- structs/classes with field access
- typed buffers: `[]u8`, `[]i32`, `[]i64`, `[]f32`, `[]f64`
- bytes (`bytes`) and direct `u8_buf` paths
- generator/coroutine handles
- structured errors (`oren_err`)

Runtime type helpers:

```oren
var tag = oren_type_tag(value)
var name = oren_type_name(value)
```

Do not depend on physical representation being identical across C/native/AVM.
Use the documented behavior and cross-backend fixtures as the contract.

## Variables and Control Flow

```oren
var x = 1
x = x + 1

if x > 1 {
    print("large")
} else {
    print("small")
}

while x < 10 {
    x = x + 1
}

for item in [1, 2, 3] {
    print(oren_int_to_string(item))
}
```

Blocks use braces. `var` introduces locals. Assignment updates existing
bindings.

## Functions and Closures

```oren
fn add(a, b) {
    return a + b
}

var twice = fn(x) {
    return x * 2
}

fn apply(x, f) {
    return f(x)
}

print(oren_int_to_string(apply(21, twice)))
```

Fixed-arity calls may omit trailing arguments. Missing trailing arguments
materialize as `nil` across C, native, and AVM:

```oren
fn connect(host, timeout_ms) {
    if timeout_ms == nil { timeout_ms = 1000 }
    return host + ":" + oren_int_to_string(timeout_ms)
}

connect("example.test")
```

Passing more than the declared arity remains invalid for fixed-arity direct
calls.

## Type Annotations

Annotations guide lowering, method resolution, and typed storage:

```oren
var count: i64 = 42
var data: []u8 = oren_u8_buf_new(16)

fn plus_one(x: i32): i32 {
    return x + 1
}
```

Scalar/nil safety is always on: comparing numeric or bool scalars directly to
`nil` is rejected. Check dynamic values before casting:

```oren
var raw = cfg["timeout_ms"]
var timeout_ms: i64 = 1000
if raw != nil {
    timeout_ms = i64(raw)
}
```

`oren build --typecheck` is conservative. It catches obvious invalid casts and
annotated call/return mismatches where values are statically known; it is not a
full global inference system.

## Structs and Classes

Struct/class values provide named fields and constructor calls:

```oren
struct Point { x, y }
class Rect { tl, br }

fn area(r: Rect): i64 {
    var w = r.br.x - r.tl.x
    var h = r.br.y - r.tl.y
    return w * h
}

var r = Rect(Point(0, 0), Point(10, 4))
print(oren_int_to_string(area(r)))
```

Field annotations normalize values at construction time:

```oren
struct Pixel {
    r: u8,
    g: u8,
    b: u8,
    a: u8
}

var p = Pixel(256 + 1, 2, 3, 255) // r becomes 1
```

Current rolling semantics treat struct/class values as immutable handles. Use
maps, buffers, or explicit replacement values for mutable data.

## Methods, Traits, and Generics

Oren has trait-backed method syntax. Calls such as `x.method(y)` are lowered
deterministically to plain functions at compile/link time; there is no hidden
runtime vtable cost in the current model.

```oren
trait Add1 {
    fn add1(self, rhs);
}

impl Add1 for i32 {
    fn add1(self, rhs) { return self + rhs }
}

fn plus_one[T: Add1](x: T): T {
    return x.add1(1)
}

print(oren_int_to_string(plus_one[i32](41)))
```

Multiple constraints and chaining are supported:

```oren
trait Mul1 {
    fn mul1(self, rhs);
}

impl Mul1 for i32 {
    fn mul1(self, rhs) { return self * rhs }
}

fn scale_then_add[T: Mul1 + Add1](x: T): T {
    return x.mul1(2).add1(1)
}
```

Blanket impls are available for generic fallback behavior:

```oren
trait Describe {
    fn describe(self);
}

impl Describe for any {
    fn describe(self) { return "value" }
}

impl Describe for i64 {
    fn describe(self) { return "int" }
}
```

When multiple traits define the same method for the same receiver type, use
trait-qualified calls:

```oren
var out = Describe.describe(123)
```

Receiver typing is static. Builtin receiver types and linked stdlib metadata
make common chains work without local annotations, for example:

```oren
"{}".json().text()
"hi".bytes().base64()
"TWFu".base64_bytes().text()
```

When writing your own generic/object APIs, add annotations where they clarify
receiver type and improve cross-backend lowering.

## Container and Buffer Methods

Common containers support method-style operations:

```oren
var xs = []
xs.push(1)
xs.push(2)
print(oren_int_to_string(xs.len()))

var m = {}
m.set("answer", 42)
print(oren_int_to_string(m.get("answer")))
```

Typed buffers are the resource-efficient path for large byte/numeric data:

```oren
import buffer "std:buffer"

var b: []u8 = buffer.u8_new(6)
buffer.try_u8_copy_from_string(b, "abcdef")

print(b.slice(1, 3).text())          // bcd
print(b.strided(0, 3, 2).text())     // ace
print(b.matrix(2, 3).row(1).text())  // def
```

Prefer buffer/bytes APIs over list-of-byte materialization for large payloads.
"Small implementation" means low CPU/memory/disk/bandwidth overhead, not
reduced features.

## Modules and Visibility

```oren
import math "std:math"
import bytes "std:bytes"

fn main() {
    var b = bytes.from_string("abc")
    print(b.hex())
    print(math.sqrt(9))
}
```

`std:*` modules are shipped with the repo and are part of the rolling stdlib
surface. Module linking resolves imports, whole-program trait impls, and OBX
metadata for precompiled OBC libraries.

Visibility is enforced for imported module surfaces. Use `pub` for declarations
that should be accessible outside the defining module; nested `pub` declarations
are rejected.

## Errors and Result Style

Structured errors use:

```oren
oren_err(code, msg)
oren_is_err(v)
oren_err_code(v)
oren_err_msg(v)
```

Public fallible APIs should use normal verbs and return `value | oren_err`:

```oren
var body = http.get(url).text()
if oren_is_err(body) {
    print(oren_err_msg(body))
    return body
}
```

Do not infer fallibility from names like `try_get_text`. Oren's rolling stdlib
uses canonical verbs (`parse`, `connect`, `read_into`, `decode_bytes`) and
reserves `*_raw` for low-level numeric errno contracts. APIs where success
metadata is part of the domain result can return `{ok, ...}` records; for
example, `argparse.parse` returns a structured parse/help/error map.

## Standard Library Overview

The stdlib is feature-rich and organized by domain:

- `std:bytes`: byte/text conversion, hex, slicing, concat, direct `u8_buf` paths
- `std:buffer`: typed buffers, slices, strided views, matrix views
- `std:json`, `std:yaml`, `std:cbor`: parse/encode and method-style codecs
- `std:xml`, `std:html`: DOM/query APIs plus streaming readers
- `std:encoding/base64`: Base64 encode/decode and receiver methods
- `std:crypto/sha1`, `std:crypto/sha256`, `std:crypto/rand`, `std:crypto/pem`,
  `std:crypto/x509`
- `std:net/http`, `std:net/ws`, `std:net/tcp`, `std:net/udp`, `std:net/tls`,
  `std:net/http2`, `std:net/hpack`
- `std:net/avm/*`: AVM-safe virtual networking facades for OBC programs
- `std:ui` and `std:ui/scene3d`: retained 2D/3D UI command records and package
  Scene3D helpers
- `std:math`, `std:linalg`, `std:time`, `std:argparse`, `std:result`
- `std:generator`, `std:coroutine`

Examples:

```oren
// JSON/YAML/CBOR method style
var title = "{\"title\":\"Hello\"}".json()["o"]["title"]["s"]
var yaml_text = "{\"answer\":42}".json().text().yaml().text()
var cbor_value = cbor.cint(7).bytes().cbor()

// HTML/XML DOM and streaming
var page = "<a id=\"home\" href=\"/\">Home</a>".html()
print(page.find("#home").attr("href"))

var reader = "<root><item>A</item><item>B</item></root>".xml_reader()
var ev = reader.next()
while ev != nil {
    if ev["kind"] == "text" { print(ev["text"]) }
    ev = reader.next()
}
```

For large XML/HTML, prefer streaming readers to keep OBC memory bounded. Use DOM
only when the payload size and query pattern justify holding a tree.

## Network API Shape

Network APIs are scoped by protocol and object:

```oren
import http "std:net/avm/http"

var response = http.get("https://note.local/data.json")
var doc = response.text().json()
```

Socket/session APIs put IO on the connection/session value:

```oren
import bytes "std:bytes"
import tcp "std:net/tcp"

var conn = tcp.connect("127.0.0.1", 9000)
if oren_is_err(conn) { return conn }

var out = "ping".bytes()
conn.write_from(out, 0, bytes.try_len(out))
conn.close()
```

AVM/OBC programs do not receive raw host sockets. They use virtual session
handles and capability-gated providers controlled by the host.

## AVM, OBC, and Capabilities

OBC bytecode runs in AVM with explicit capabilities and budgets. Host effects
are grouped by domains such as FS, NET, PROC, TIME, RNG, ENV, and GFX. This is
central to writing portable Oren programs:

- Use `std:net/avm/*` for OBC-visible virtual networking.
- Use package VirtualFS assets for bundled resources.
- Keep large binary/scene assets byte-native instead of list-native.
- Treat capability denials as normal fallible results.

See:

- `docs/CAPABILITY_RUNTIME_CONTRACT.md`
- `docs/EFFECT_LEDGER_CONTRACT.md`
- `docs/DESIGN.md`

## Yield, Generators, and Coroutines

Current shipped surfaces:

- bare `yield`
- `yield <value>`
- explicit exchange: `yield expr in (yield_ch, resume_ch)`
- `std:generator`
- `std:coroutine`

The compiler records yield metadata and the runtime libraries implement the
current generator/coroutine contract. Treat this as rolling but usable; update
fixtures when changing semantics.

## Implementation Map

- Lexer/tokens: `lib/compiler/token.oren`, `lib/compiler/lexer.oren`
- Parser: `lib/compiler/parser_parse/`
- AST constructors: `lib/compiler/ast.oren`
- Build pipeline: `lib/compiler/compiler/040_build_pipeline.oren`
- Module linking: `lib/compiler/compiler/020_modules_linking.oren`
- Trait/generic/method lowering: `lib/compiler/` lowering passes
- C backend: `lib/compiler/transpiler.oren`, `lib/runtime.[ch]`
- Native backend: `lib/compiler/arm64_*`, `lib/compiler/x64_*`,
  `lib/runtime_native/`
- Bytecode backend: `lib/compiler/codegen_bytecode/`, `lib/avm/`

## Tests as Spec

Use these fixtures to confirm behavior:

- Language basics and integration: `tests/modules/test_integration_suite.oren`
- Traits/methods/generics: `tests/modules/test_trait_impl.oren`,
  `tests/modules/test_generic_trait_constraints.oren`,
  `tests/modules/test_trait_blanket_impl_any.oren`
- Container and buffer methods: `tests/modules/test_container_methods.oren`,
  `tests/modules/test_buffer_method_views.oren`
- Struct/class fields: `tests/modules/test_typed_struct_fields.oren`,
  `tests/modules/shapes.oren`
- Codec and parser stdlib: `tests/modules/test_json.oren`,
  `tests/modules/test_yaml_comments.oren`,
  `tests/modules/test_cbor_sequence.oren`,
  `tests/modules/test_xml_html_dom.oren`
- AVM/OBC behavior: `tests/avm/`, `tests/fixtures/`

When behavior changes, update the relevant fixture first, then update this page
and `docs/STATUS.md`.
