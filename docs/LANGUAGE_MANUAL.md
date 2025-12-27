# Oren Language Manual (Rolling)

This is the **practical** guide to writing Oren today.

It is intentionally different from the formal spec:

- **Manual**: “how to use it” + idioms + examples (what works *now*).
- **Spec**: complete grammar + exact semantics (`docs/LANGUAGE_SPEC.md`).

Oren is in **rolling ABI mode**: until an explicit stabilization milestone is declared, backwards compatibility is not guaranteed.

## 0) What Oren is

Oren is an **agent-native**, syscall-first language and toolchain:

- **Native** mode (server/desktop): compiles to native binaries (no libc shims for the *native backend output*).
  - Primary/production path today: macOS `arm64` (syscall-first runtime surface is most complete here).
  - Rolling bring-up path: Linux/Windows `x86_64` (`--arch x64`) is Tier‑1 intent, but currently a growing “bring-up subset” (feature surface is expanding rapidly; see `docs/TODOS.md` and `docs/REMOTE_X64_ENV.md` for real-hardware validation).
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
import math "std:math"
import buffer "std:buffer"
```

Imported names can be qualified as `alias.symbol`.

### FFI symbols (`ffi name`)

Oren supports an `ffi` declaration statement to reference an external symbol:

```oren
ffi puts
puts("Hello FFI")
```

Notes (rolling):

- `ffi` is a low-level escape hatch intended primarily for native interop and experiments.
- In **capsule** mode, `ffi` declarations are rejected (FFI bypasses capability gating).
- Native backend:
  - **macOS** supports binding against `libSystem` for `ffi` calls (see `docs/NATIVE_BACKEND.md`).
  - **Linux** does not yet have a full dynamic-linking story in the native backend; unresolved imports are currently stubbed (see `docs/NATIVE_BACKEND.md`).
- C backend:
  - Oren does not have a stabilized “typed C FFI” surface yet, but you can still link extra C by compiling the emitted C yourself (see `docs/C_BACKEND.md`).

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

- `oren_iter_next(iterable, idx) -> [ok:int, value]`
  - `ok == 1` means “yield `value`”
  - `ok == 0` means “stop iteration”

Iteration proceeds in deterministic **index order** (`idx = 0, 1, 2, ...`) and stops at the first `ok == 0`.

#### Trait-based extension: `trait Iterable`

In rolling mode, Oren also supports a static-first trait extension for iteration:

```oren
trait Iterable {
    fn iter_next(self, idx)
}
```

If the loop iterable is a bare identifier and an `impl Iterable for <Type>` exists, the compiler can rewrite the loop to call that impl (avoiding runtime vtables and keeping hot loops predictable).

Practical example (range-like iterable):

```oren
trait Iterable { fn iter_next(self, idx) }

struct MyRange { start: i32, end: i32, step: i32 }

impl Iterable for MyRange {
    fn iter_next(self, idx) {
        if idx < 0 { return [0, nil] }
        if self.step == 0 { return [0, nil] }
        var v = self.start + idx * self.step
        var ok = (self.step > 0 && v < self.end) || (self.step < 0 && v > self.end)
        if ok { return [1, v] }
        return [0, nil]
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

#### Blanket impls (`any`)

Rolling v0 supports a minimal blanket impl form:

```oren
trait Z { fn z(self); }

impl Z for any { fn z(self) { return 0 } }
impl Z for i64 { fn z(self) { return 7 } }
```

Exact impls (like `i64`) override blanket `any` impls deterministically.
See `tests/modules/test_trait_blanket_impl_any.oren`.

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
- `@cap.requires(domain="...")` for capsule/capability gating of host-effectful APIs (see below)

#### Strict attribute mode (compiler option)

For “lint-like” strictness (useful for production toolchains and schema-driven metadata), the compiler supports:

- `./oren build ... --strict-attrs`
- `./oren build ... --attr-allow-prefixes myorg.` (repeatable allowlist of custom namespaces)

In strict mode:

- unknown/forbidden attribute prefixes are rejected at compile time

See `tests/native/fixtures/strict_attrs_ok.oren` / `strict_attrs_bad.oren` and the oretest fixture harness in `cmd/oretest/main.go`.

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

- In capsule mode, calls to functions annotated with `@cap.requires(domain="FS|NET|PROC|ENV|TIME")`
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
  - `OREN_PROC_ALLOW_SYSTEM=1` (enables `/bin/sh` only; convenience for bootstrapping)
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

To wait for a spawned task:

```oren
var r = oren_join(t) // returns the worker’s return value (or panics if the worker panicked)
```

Timeout join is also available:

```oren
// timeout_ms < 0 means “wait forever” (equivalent to oren_join).
var r2 = oren_join_timeout(t, 20)
```

See `tests/modules/test_spawn_join_timeout.oren` and `tests/native/test_spawn_join_timeout.oren`.

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
