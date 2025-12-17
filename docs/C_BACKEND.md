# C Backend (Transpile-to-C)

Oren’s current “production” backend is a **transpiler to C** plus a small C runtime in `lib/runtime.[ch]`.

## What Happens When You Build
Given `hello.oren`, both the stage0 (`oren_bootstrap`) and the self-hosted compiler (`oren`) do:
1) Read and parse `hello.oren` into an AST
2) Transpile the AST into a single C translation unit `hello.oren.c`
3) Invoke a C toolchain to compile and link:
   - the generated `hello.oren.c`
   - `lib/runtime.c`

The default compiler driver is `cc`, but you can override it with `--cc` (or `$CC` in stage0).

## Output Files
- `hello.oren.c`: generated C source (use `--emit-c` to stop here)
- `hello`: the final native executable built by `cc`

## How Oren Maps to C
The generated C program:
- includes `lib/runtime.h`
- lowers Oren operations into calls like `oren_add`, `oren_print`, `oren_list_get`, `oren_new_map`, …
- defines `main()` which calls `oren_init(argc, argv)` then runs the top-level statements

## First-class Functions and Lambdas (C Backend)

The C backend supports **first-class function values** and **closure lambdas** via a uniform callable ABI:

- Runtime value type: `OREN_TYPE_FUNC` (in `lib/runtime.h`).
- Callable ABI: `OrenFn fn(void* env, int argc, OrenValue* argv)`.
  - `env` is reserved for closure environments (captured values).
  - Named functions and constructors get an auto-generated wrapper entrypoint:
    - `name__oren_fnwrap(void* env, int argc, OrenValue* argv)`
- Lambdas compile to compiler-generated wrapper functions like:
  - `__oren_lambda_<unit>_<n>(void* env, int argc, OrenValue* argv)`
  - and construct a closure value with capture-by-value using `oren_closure(...)`.

### Calling and Spawning Callables

- Indirect calls (function values / closures) go through `oren_call_obj(...)` / `oren_call_obj_list(...)`.
- `spawn` lowers to `oren_spawn_call_list(fn_value, args_list)` so it can spawn:
  - direct named functions,
  - function values stored in variables,
  - lambdas/closures with captured environments.

See `docs/SELF_HOSTING.md` for more details on the lowering rules.

## Working With Your Own C Source Files
Oren does not have a stable C FFI surface yet, but you can still link extra C code by compiling the generated C yourself:
```sh
./oren --emit-c hello.oren
cc -o hello hello.oren.c lib/runtime.c -Ilib path/to/your.c
```

This is useful for experiments, but the long-term goal is “Option B” (native backend) where Oren produces executables directly without emitting or compiling C.
