# Oren Language

**Last updated:** 2026-06-02

This is the concise current language reference. Oren is rolling: code and fixtures are
the execution source of truth when a detail matters.

## Implementation Map

- Lexer/tokens: `lib/compiler/token.oren`, `lib/compiler/lexer.oren`
- Parser: `lib/compiler/parser_parse/`
- AST constructors: `lib/compiler/ast.oren`
- Build pipeline: `lib/compiler/compiler/040_build_pipeline.oren`
- Module linking: `lib/compiler/compiler/020_modules_linking.oren`
- C backend: `lib/compiler/transpiler.oren`, `lib/runtime.[ch]`
- Native backend: `lib/compiler/arm64_*`, `lib/compiler/x64_*`, `lib/runtime_native/`
- Bytecode backend: `lib/compiler/codegen_bytecode/`, `lib/avm/`

## Program Shape

```oren
fn main() {
    print("hello")
    exit(0)
}

main()
```

Oren files are modules. Top-level statements execute in order after compilation/linking.

## Values

Current value families:

- `nil`
- booleans
- integers
- floats
- strings
- lists and list-int optimized paths
- maps
- first-class functions/closures
- typed buffers: u8/i32/i64/f32/f64
- generator/coroutine handles and contexts
- structured errors

Backend value representations are not fully converged yet. Use `oren_type_tag` and the
cross-backend parity fixtures as the behavioral contract rather than assuming identical
physical representation across C/native/AVM.

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

for item in xs {
    print(item)
}
```

Blocks use braces. `var` introduces locals. Assignment updates existing bindings.

## Functions

```oren
fn add(a, b) {
    return a + b
}

var f = fn(x) {
    return x * 2
}
```

Closures are supported. Function/generic/lowering behavior is still rolling; use fixtures
for exact edge cases.

Fixed-arity calls may omit trailing arguments; omitted trailing arguments materialize as
`nil` across C, native, and AVM backends. Passing more than the declared arity remains
invalid for fixed-arity direct calls.

## Modules

```oren
import math "std:math"

fn main() {
    print(math.sqrt(9))
    print(math.power(2.0, -1.0))
    print(math.power(2.0, 4.3))
}
```

Imports are resolved by the compiler/linker pipeline. `std:*` modules are shipped with
the repo and remain part of the rolling stdlib surface. `std:math` is deterministic
and portable rather than host-`libm` backed; current power APIs are `pow(x, y)`,
`power(x, y)`, and exact integer-exponent `powi(x, n)`.

## Errors

Structured errors use the current runtime helpers:

- `oren_err(code, msg)`
- `oren_is_err(v)`
- `oren_err_code(v)`
- `oren_err_msg(v)`

Stdlib result helpers build on this convention. Cross-backend error behavior is guarded
by parity fixtures, not by a frozen external ABI.

## Type Checks

`oren_type_tag(v)` and `oren_type_name(v)` expose runtime type information. Native tagged
value convergence is still in progress; parity fixtures define what is guaranteed today.

Always-on scalar/nil safety: numeric and bool scalar comparisons with `nil` are rejected
by the compiler. Check the dynamic value first, then cast:

```oren
var raw = cfg["timeout_ms"]
var timeout_ms = 1000
if raw != nil {
    timeout_ms = i64(raw)
}
```

## Typecheck Mode

`oren build --typecheck` is opt-in and conservative. It checks obvious invalid casts and
annotated call/return mismatches where values are statically known. It is not a full
inference/unification system.

## Yield, Generators, and Coroutines

Current shipped surfaces:

- bare `yield`
- `yield <value>`
- explicit exchange: `yield expr in (yield_ch, resume_ch)`
- `std:generator`
- `std:coroutine`

The compiler records yield metadata and the bytecode backend consumes the current
prepared bare-yield subset. C/native execute the shared helper surface. The full
generator/coroutine model is a rolling library/runtime contract, not a frozen language ABI.

## Capabilities and Effects

The project tracks effect domains for filesystem, network, process, environment, time,
randomness, and related runtime actions. AVM supports capability-gated deterministic
fixtures and budgets. Native/C capability parity is guarded by dedicated contract tests.

See `docs/CAPABILITY_RUNTIME_CONTRACT.md` and `docs/EFFECT_LEDGER_CONTRACT.md`.

## CLI

Common commands:

```bash
./oren build file.oren --backend c -o build/file_c
./oren build file.oren --backend native -o build/file_native
./oren build file.oren --backend bytecode -o build/file.obc
./avm build/file.obc
./oren meta file.oren
./oren dump linked file.oren
```

## Tests as Spec

- Native fixtures: `tests/native/fixtures/`
- Module fixtures: `tests/modules/`
- AVM fixtures: `tests/avm/`
- Cross-backend fixtures: `tests/fixtures/`

When behavior changes, update the relevant fixture first, then update this document and
`docs/STATUS.md`.
