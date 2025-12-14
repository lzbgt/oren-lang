# Oren Continuity Notes

## Status
- **Compiler**: Self-hosting (Stage 2 verified), default macOS codesign + notarize hooks.
- **Architecture**: Modularized (`lib/compiler/*.oren`).
- **Backends**: Native ARM64 (Mach-O / ELF) and C.
- **Runtime**: `lib/runtime_native.oren` for native backend; `lib/runtime.c` for C backend with tracked allocations + optional GC.

## Recent Achievements
- Added allocation registry + manual `oren_free` + mark/sweep (`oren_gc_collect`) for strings/lists/maps; globals register as roots.
- CLI/Makefile default to Developer ID signing with ad-hoc fallback; optional notarization wired via `notarytool`.
- Nested struct support is validated by native test.
- Field-offset consistency checks added across structs with the same field names.
- Native runtime gained basic string length/char helpers, list creation/push/get/index_set, and centralized struct allocation hook (`oren_alloc_struct`) for future native-only self-hosting.

## Known Issues
- **GC coverage**: Native backend struct/stack allocations are outside the managed heap; GC requires explicit safepoints.
- **Threading**: Runtime data structures are not yet thread-safe; no scheduler or safepoint protocol exists.
- **FFI**: Import stubs still exit; real dynamic linking (PLT/GOT or dyld) remains TODO.

## Next Steps
1. Wire native backend struct allocations into a managed allocator suitable for GC/ownership.
2. Add per-frame root tracking + safepoints and a concurrency story (thread-safe lists/maps, concurrent-friendly GC API).
3. Implement real FFI (PLT/GOT + `LC_LOAD_DYLIB` / `DT_NEEDED`), then expand analysis/type checking.
4. Move toward the production roadmap tracked in `docs/ROADMAP.md` (type system, tooling, package manager, async/tasks, x86_64 backend).

## Reference
- **Source**: `lib/compiler/*.oren`.
- **Runtime**: `lib/runtime_native.oren`.
- **Build**: `Makefile`.
