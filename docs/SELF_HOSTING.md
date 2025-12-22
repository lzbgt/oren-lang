# Self-Hosting (Stage0 → Stage1 → Stage2)

Oren is a self-hosted language:

- **Stage0**: a small compiler written in Go (`./cmd/oren`) used only for bootstrapping.
- **Stage1**: the compiler written in Oren (`oren.oren`), built by Stage0.
- **Stage2+**: Stage1 rebuilds itself, proving self-hosting.

This repo intentionally supports multiple backends (C / native / bytecode). Self-hosting uses whichever backend is practical for the platform and phase.

Authoritative end-to-end instructions live in `docs/BUILD_AND_VERIFY.md` (this file is a conceptual overview).

## Backends (context)

### C backend (portable bootstrapping path)
The C backend transpiles Oren to C, then relies on the host C toolchain to compile/link. This is still the “most portable” path and remains useful as a fallback.

For details, see `docs/C_BACKEND.md`.

### Native backend (syscall-first, no host SDK headers)
The native backend emits Mach-O (macOS arm64) or ELF (Linux arm64) directly.

Design constraints and ABI tables are documented in `docs/NATIVE_BACKEND.md`.

### Bytecode backend (AVM)
The bytecode backend emits `.obc` for the AVM prototype.

## How the C backend targets C (historical + still relevant)
- **Boxed values**: every Oren value is an `OrenValue` (ints/floats/bools/strings, lists, maps, and optionally wrapped Python objects).
- **Generated C shape**:
  - `#include "runtime.h"`
  - `OrenValue` globals for top-level `var` declarations
  - forward declarations for named `fn`s
  - constructor functions for `struct`/`class` declarations (`Type__new`)
  - C functions for each named `fn` (each returns `OrenValue`)
  - `int main(int argc, char **argv)` which calls `oren_init(argc, argv);`, initializes globals, then runs top-level statements
- **Example lowering**:
  - Oren: `var x = 1 + 2; print(x)`
  - C (roughly): `x = oren_add(oren_int(1), oren_int(2)); oren_print(x);`
- **Lowering strategy**: expressions become calls to runtime helpers:
  - arithmetic/comparisons: `oren_add`, `oren_eq`, `oren_lt`, …
  - literals: `oren_int(...)`, `oren_float(...)`, `oren_string(...)`, `OREN_TRUE/OREN_FALSE/OREN_NIL`
  - list/map literals: `oren_new_list(n, ...)`, `oren_new_map(n, k1, v1, ...)`
  - indexing: `oren_list_get(container, index)`
  - index assignment: `oren_index_set(container, index, value)`
  - member access: `oren_get_attr(obj, "name")`
  - member assignment: `oren_set_attr(obj, "name", value)`
- **Optional Python FFI** (disabled by default):
  - build with `--python` (or compile with `-DOREN_ENABLE_PYTHON` and link libpython via `python3-config`)
  - `py_import("module")` becomes `oren_py_import(...)`
  - calls on Python objects route through `oren_call_obj(...)`

## Modules (`import`) at Compile Time
Oren modules are file-based and resolved at compile time:
- `import math "path/to/math.oren"` loads and transpiles that file, binding `math` as a **namespace**.
- All imported modules (and the entry file) are merged into **one** emitted C translation unit (`<entry>.oren.c`).
- To avoid global symbol collisions, each imported module is assigned a unique prefix (`m0`, `m1`, …) and its top-level symbols are renamed:
  - `var pi` in module `math.oren` might become `m0__pi` in C
  - `fn add(a,b)` might become `m0__add`
- Namespace member access lowers to the renamed symbol:
  - `math.pi` → `m0__pi`
  - `math.add(1, 2)` → `m0__add(oren_int(1), oren_int(2))`
- Import paths are resolved relative to the importing file’s directory; cyclic imports are rejected.

## Structs / Classes
`struct` and `class` are currently “data-only” and compile down to runtime maps:
- A declaration like `struct Point { x, y }` generates a constructor `Point__new(x, y)` that returns `oren_new_map(2, "x", x, "y", y)`.
- `Point(1, 2)` is shorthand for calling the constructor (`Point__new(1, 2)`).
- Field access uses the runtime attribute helpers:
  - `p.x` → `oren_get_attr(p, "x")`
  - `p.x = v` → `oren_set_attr(p, "x", v)`

## Self-Hosting Pipeline (Go only for stage0)
The intended flow is “stage0 builds stage1; stage1 rebuilds itself” (similar to Zig).

### One-command bootstrap
```sh
make bootstrap
```

### Manual bootstrap
1) Build the stage0 compiler (Go) as `oren_bootstrap`:
```sh
go build -o oren_bootstrap ./cmd/oren
```
2) Use stage0 to build the stage1 compiler (Oren) from `oren.oren`:
```sh
./oren_bootstrap build oren.oren   # produces ./oren
```
3) Use stage1 to rebuild itself (stage2) without Go:
```sh
./oren build oren.oren -o oren_stage2
```

Native backend option (syscall-first Mach-O/ELF emitter):
```sh
./oren build oren.oren --backend native --target macos -o build/oren_stage2_native
```

Notes:
- The native backend path depends on a small “compiler subset” of the native runtime being present (e.g. `oren_string_to_float_bits`, `oren_sha256_range`, `oren_chmod`, `oren_env`). This repo treats that subset as a self-hosting stability gate.

4) From here on, you can keep rebuilding without Go:
```sh
./oren_stage2 build oren.oren -o oren_stage3
```

## Using the Self-Hosted Compiler
Use `./oren build ...` explicitly. The default backend is intentionally configurable and may change during rolling development.

Recommended:

- C backend: `./oren build hello.oren --backend c -o hello`
- native backend: `./oren build hello.oren --backend native -o hello`
- bytecode backend: `./oren build hello.oren --backend bytecode -o hello.obc`

To emit C only (C backend):
```sh
./oren build hello.oren --backend c --emit-c
```

## How `oren` Builds a Binary
The high-level pipeline is:

1) Read `.oren` sources
2) Lex/parse into an AST
3) Resolve imports and link into a program model
4) Run lowering passes (attributes, ABI layout, packed-byte views, etc.)
5) Emit:
   - C (`--backend c`)
   - native Mach-O/ELF (`--backend native`)
   - AVM bytecode (`--backend bytecode`)

For the C backend, the toolchain invocation is explicit and overrideable (see `docs/C_BACKEND.md`).

If you prefer to compile the generated C yourself, use `--emit-c` and then run the compile/link step manually.

## Runtime Helpers Used By The Compiler
- `oren_args()` returns CLI args as a list of strings.
- `oren_read_file(path)` / `oren_write_file(path, content)` are used to implement a “compiler reads source, writes C” workflow.
- `oren_system(cmd)` is used to invoke the C compiler.
- `oren_exit(code)` is used to exit with a non-zero status on build failure.

## Notes on build artifacts (`*.oren.c`)
The C backend can write `*.oren.c` files (when `--emit-c` is used).

This repo’s canonical test runners avoid generating `*.oren.c` in-tree by default to prevent accidental Makefile implicit-rule coupling.
See `docs/TODOS.md` rule “Never generate `*.oren.c` next to sources” and `docs/TEST_SYSTEM.md` for the migration plan.
