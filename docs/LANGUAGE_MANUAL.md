# Oren Language Manual (Rolling)

This is the **practical** guide to writing Oren today.

It is intentionally different from the formal spec:

- **Manual**: “how to use it” + idioms + examples (what works *now*).
- **Spec**: complete grammar + exact semantics (`docs/LANGUAGE_SPEC.md`).

Oren is in **rolling ABI mode**: until an explicit stabilization milestone is declared, backwards compatibility is not guaranteed.

## 0) What Oren is

Oren is an **agent-native**, syscall-first language and toolchain:

- **Native** mode (server/desktop): compiles to macOS/Linux arm64 binaries (no libc shims for the *native backend output*).
- **Portable** mode: compiles to `.obc` bytecode executed by AVM, supporting determinism, snapshots, and capability-governed virtualized domains (FS/NET/PROC/ENV/TIME).

## 1) Program structure

Oren files are modules. A typical program has a `main` function:

```oren
fn main() {
    print("hello")
    exit(0)
}
```

### Imports

Import with an alias:

```oren
import math "../../lib/std/math.oren"
import buffer "../../lib/std/buffer.oren"
```

Imported names can be qualified as `alias.symbol`.

## 2) Values and literals

### Integers

- Decimal: `123`, underscore separators allowed: `1_000_000`
- Prefixed bases:
  - hex: `0xFF`, `0xDEAD_BEEF`
  - bin: `0b1010_0110`
  - oct: `0o755`

Negative numbers are prefix expressions: `-1`, `-(a + b)`.

### Floats (`f64` container in v0)

Float literals are compiled as **f64 bit-pattern constants**.

Supported forms:

- Decimal: `12.5`, `0.125`
- Scientific notation: `1e3`, `5e-1`, `12.5E+2`

### Booleans and nil

- `true`, `false`
- `nil` is the canonical null value.

### Strings

Strings are double-quoted:

```oren
var s = "hello"
```

## 3) Variables and assignment

Declare with `var`:

```oren
var x = 10
x = x + 1
```

Oren also supports typed annotations in some contexts (see “Types” below).

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

### Lambdas

Lambdas use `|params| expr` or `|params| { block }`.

```oren
var f = |x| x + 1
var g = |x, y| { return x * y }
```

Lambdas capture values (capture-by-value in the current lowering model).

## 6) Types (practical)

Oren’s *runtime* (v0) is dynamically typed (boxed values), but the language includes **explicit width types** used for:

- ABI/layout and packed views
- typed buffers (`[]i32`, `[]f32`, `[]f64`, …)
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

## 7) Structs, attributes, and deterministic metadata

Structs:

```oren
struct Point {
    x: i32,
    y: i32
}
```

### Attributes

Attributes are compile-time metadata annotations. Unknown attributes are inert in rolling mode, but preserved for tooling.

Common builtins:

- `@abi` for ABI/layout metadata
- `@pack` for packed “view over bytes” structs (network packet parsing)
- `@serde(...)` for serialization metadata (json/yaml/cbor)

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

## 8) Typed buffers and HPC building blocks

Typed buffers are the canonical HPC container in Oren today:

```oren
import buffer "../../lib/std/buffer.oren"
import linalg "../../lib/std/linalg.oren"

var a: []f64 = buffer.f64_new(6)
var b: []f64 = buffer.f64_new(6)
// store elements using runtime helpers, then:
var out: []f64 = linalg.matmul_f64_buf(a, b, 2, 3, 2)
```

Design goals:

- avoid boxed list overhead in numeric kernels
- isolate hot loops so NEON microkernels can replace them without changing semantics
- deterministic accumulation order for consensus and testing

## 9) Deterministic math (no host libm)

The `std/math` module provides deterministic “libm-lite” functions implemented without calling host `libm`:

- rounding: `floor`, `ceil`, `round` (as float outputs)
- core: `sqrt`, `powi`, `exp2`, `exp`, `log2`, `ln`
- trig: `sin`, `cos`, `atan`, `atan2` (range-reduced, deterministic; some functions may error for huge |x| until Payne–Hanek reduction is added)

For exactness and determinism, tests often prefer:

- integer-representable float inputs
- explicit tolerances like `1e-12` (scientific literals are supported)

## 10) Concurrency (today)

Oren has `spawn` (rolling v0 restriction: spawns a call expression):

```oren
fn work(x) { return x + 1 }
var t = spawn work(10)
```

Concurrency in AVM differs from native mode; see:

- `docs/CONCURRENCY_MODEL.md`
- `docs/AVM_CONCURRENCY.md`

## 11) Tooling quick reference

The authoritative build/test workflow is in:

- `docs/BUILD_AND_VERIFY.md`
- `docs/TEST_SYSTEM.md`

In rolling mode, the canonical verification step is:

```sh
timeout 900 ./oretest --target macos
```

## 12) Where to go next

- Formal language spec: `docs/LANGUAGE_SPEC.md`
- Evolution narrative (day0 → “compiler-in-AVM”): `docs/EVOLUTION_GUIDE.md`
- Roadmap/phases: `docs/ROADMAP.md`
- Current task tracker (execution order): `docs/TODOS.md`

