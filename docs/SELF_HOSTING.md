# C Transpilation and Self-Hosting

This project emits C as an intermediate and links a small runtime (`lib/runtime.[ch]`). `oren.oren` is a compiler written in Oren, so once you have a stage0 bootstrap binary you can rebuild the compiler (and compile Oren programs) without Go.

For a focused explanation of the C backend and how it interacts with C source files, see `docs/C_BACKEND.md`.

## How Oren Targets C
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
4) From here on, you can keep rebuilding without Go:
```sh
./oren_stage2 build oren.oren -o oren_stage3
```

## Using the Self-Hosted Compiler
By default, `./oren <file.oren>` builds a native executable next to the source (and also writes a `<file.oren>.c` intermediate).

To emit C only:
```sh
./oren --emit-c hello.oren
```

## How `oren` Builds a Binary
The self-hosted compiler (`oren.oren`) follows this workflow:
1) Read `.oren` source (`oren_read_file`)
2) Lex/parse into an AST
3) Resolve imports (if any), then transpile to a single C translation unit that includes `lib/runtime.[ch]`
4) Write `<file>.oren.c` (`oren_write_file`)
5) Invoke the platform C toolchain via `oren_system("cc ... lib/runtime.c -Ilib")`

You can override the C compiler with `--cc clang` (or any other `cc`-compatible driver). If you enable Python FFI (`--python`), the compiler also adds `-DOREN_ENABLE_PYTHON` and the `python3-config` flags.

If you prefer to compile the generated C yourself, use `--emit-c` and then run the compile/link step manually.

## Runtime Helpers Used By The Compiler
- `oren_args()` returns CLI args as a list of strings.
- `oren_read_file(path)` / `oren_write_file(path, content)` are used to implement a “compiler reads source, writes C” workflow.
- `oren_system(cmd)` is used to invoke the C compiler.
- `oren_exit(code)` is used to exit with a non-zero status on build failure.

## Native Backend (Option B)
The long-term goal is to have `oren` produce host executables directly (Mach-O on macOS, ELF on Linux) without emitting C or invoking `cc/ld/codesign`.

Progress notes and design constraints are tracked in `docs/NATIVE_BACKEND.md`.
