# Oren Continuity Notes

## Status
- Self-hosting chain: Go stage0 (`cmd/oren`) builds stage1 `oren`; Makefile target `oren_stage2` exercises stage2. Default backend is C; native ARM64 Mach-O/ELF is available via `--backend native` (with `--target linux`).
- Compiler is split across `lib/compiler/*.oren` (lexer, parser, ast, analysis, codegen, transpiler, metadata). Module loader prefixes imports, checks alias conflicts, and enforces consistent struct field offsets before merging.
- C backend uses `lib/runtime.c` (tracked mark/sweep GC with mutexed list/map ops). Native backend injects `lib/runtime_native.oren` (bump-pointer heap + reuse list, conservative GC hooks, thread registry, inline syscalls).
- CLI: codesign/notarize flags on macOS, `--metadata` writes `<out>.meta.json` (functions/structs), `--analyze` prints scope info. `--emit-c` is only supported for the C backend.

## Recent Achievements
- Native heap: bump-pointer allocator backed by `mmap` (min 64KB) with free-list reuse and allocation tracking; `oren_alloc_struct` centralizes struct buffers for GC accounting.
- GC plumbing: runtime globals initialized at entry, main thread registered before user code, conservative stack scan over registered threads, mark/sweep over tracked lists/maps/strings, and block-scope cleanup in codegen to restore stack slots.
- Syscall surface: inline `sys_write/read/pipe/clone` paths (macOS uses X16 + SVC #128; Linux uses X8 + SVC #0); atomics lowered to ARM64 `LDADD` / `CAS`; SIMD intrinsics fall back to scalar ops when needed.
- Language/runtime: C-style block comments, `for` loops (init/cond/post), short `:=` bindings, `test "name" {}` lowered to `fn test_name`, writable data segment for globals/string literals, metadata export implemented.
- Modules/tests: module system validated via `tests/modules/*`; native suite covers atomics, GC, pipe/channel, SIMD, maps/lists/structs; Makefile drives bootstrap + native/C test runs.

## Known Issues
- `sys_pipe` / channel path remains unstable (Roadmap: “Channels implemented, debugging sys_pipe”); `make test` currently SIGILLs on macOS ARM64 (`test_pipe`, `test_pipe_direct`), so pipe/channel behavior is untrustworthy.
- Threads: `sys_clone` only targets Linux; macOS path returns `-1`, and there is no `spawn` wrapper or thread registry hookup beyond the main thread.
- Native runtime gaps: `oren_args` returns an empty list; `native_gc_unregister_root` unimplemented; `native_gc_shutdown` does no release; GC is conservative without type tags/stack maps, so integers or non-heap pointers may be skipped or mis-marked.
- Native I/O/printing is integer-only; richer printing and type-aware traces are missing.
- FFI/import stubs just return `0` (see native import stub generation); no PLT/GOT or dyld linking; metadata export only lists function names/args and struct fields.

## Next Steps
1. Debug/fix `sys_pipe` on macOS ARM64 (compare against a minimal C pipe/pipe2) and re-enable channel/pipe validation.
2. Add a `spawn` wrapper and macOS thread-creation path, wiring new threads into the registry/stack scanner.
3. Surface argv into the native runtime and finish GC lifecycle hooks (root unregister, shutdown freeing, better root precision/stack maps).
4. Build a test runner that enumerates and runs `test_` functions; expand metadata export to carry docs/types once stable.

## Reference
- Source/compiler: `lib/compiler/*.oren`
- Native runtime: `lib/runtime_native.oren`
- C runtime: `lib/runtime.c`
- Build/Test: `Makefile`, `tests/*`
