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

See `docs/SELF_HOSTING.md` for more details on the lowering rules.

## Working With Your Own C Source Files
Oren does not have a stable C FFI surface yet, but you can still link extra C code by compiling the generated C yourself:
```sh
./oren --emit-c hello.oren
cc -o hello hello.oren.c lib/runtime.c -Ilib path/to/your.c
```

This is useful for experiments, but the long-term goal is “Option B” (native backend) where Oren produces executables directly without emitting or compiling C.

