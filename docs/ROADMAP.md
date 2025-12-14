# Roadmap

This document captures the staged plan for turning Oren into a production-grade, modern language and toolchain.

## Goals
- Fast native codegen for macOS/Linux ARM64 (and x86_64), with a portable C backend for constrained targets.
- Robust type system (generics, interfaces/traits, enums/ADTs, pattern matching) with a sound checker.
- Predictable memory story: optional GC (desktop/server) and deterministic/manual mode (embedded).
- First-class developer ergonomics: formatter, linter, LSP, test runner, package manager, and debugging/profiling hooks.

## Near-Term (0–2 months)
- **Memory/GC**: Upgrade tracked allocs to a real collector (generational or tri-color mark/sweep), safepoints, per-frame roots, and refine collection locking (coarse mutex in place). Keep `OREN_NO_GC` minimal mode for embedded (STM32, etc.).
- **Concurrency**: Core threading primitives, channels/queues, atomics; ensure runtime data structures are thread-safe.
- **FFI/Linking**: Real PLT/GOT + `LC_LOAD_DYLIB`/`DT_NEEDED` support; stable C ABI surface; clean import resolution.
- **Native backend**: Managed struct allocation in the native runtime (no mmap-only path); consistent field layouts and nested struct support. Recent fixes: 4-byte function alignment, entry trampoline for `main`, and block-scoped stack cleanup to avoid loop leaks (fixes nested struct/value crashes on macOS).
- **Tooling**: CLI switches parity (codesign/notarize already), add `oren fmt` skeleton and lint scaffolding.

## Mid-Term (2–6 months)
- **Type system**: Full checker with generics/monomorphization, interfaces/traits, enums/ADTs, pattern matching, result/option-based error handling.
- **IR + Optimization**: SSA IR, register allocation, inlining, const-prop/DCE/CSE, loop opts, and better Mach-O/ELF emission; add x86_64 backend.
- **Testing & QA**: Built-in test runner, property testing, coverage hooks, fuzz entry points.
- **Package Management**: Module registry layout, vendoring, lockfiles, reproducible builds.
- **Tooling**: Language Server (LSP), debugger symbols (DWARF), profiler integration.

## Long-Term
- **Async/Tasks**: Async/await or lightweight tasks with a scheduler; GC/stack interaction.
- **Security/Trust**: Deterministic builds, supply-chain verification, signed artifacts, sandboxed exec.
- **Ecosystem**: Standard library build-out (collections, fs/net/crypto/time), cross-platform story (Windows), and polished docs/examples.
