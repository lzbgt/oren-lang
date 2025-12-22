## Active Tracker (Keep Short)

This file tracks only the highest-priority active items (5–10 total). Detailed history and older plans live in `docs/TODOS_ARCHIVE.md`.

### P0 (Now)

1) **Split `lib/compiler/arm64_native_expr_syscalls.oren` via `// @include`** (L)
   - Why P0: it’s ~4k lines and the syscall/capsule policy “center of gravity”.
   - DoD: move to `lib/compiler/arm64_native_expr_syscalls/*.oren` parts + manifest, with `make test` green.

2) **Refactor remaining huge compiler files via `// @include`** (M)
   - DoD: split remaining >2000-line compiler modules into `lib/compiler/<name>/...` parts while keeping builds + `make test` green.
   - Next files: `lib/compiler/codegen_bytecode.oren`, `lib/compiler/parser_parse.oren`, `lib/compiler/compiler.oren`.

3) **SIMD correctness unblock** (M)
   - DoD: make `simd_dot_f32_4_ptr` / `simd_gemm_f32_4x4_ptr` pass correctness suites (or keep them disabled but add an explicit tracked failing test with a minimal reproducer).

### P1 (Soon)

4) **Native networking hardening** (M)
   - DoD: expand syscall-first TCP/UDP readiness + timeouts, keep capsule gating comprehensive on both macOS and Linux.

5) **Docs parity pass** (S)
   - DoD: update any docs referencing old single-file layouts after refactors (compiler/runtime).

### Notes

- Archived snapshot of the previous long TODO list is appended to `docs/TODOS_ARCHIVE.md` (dated 2025-12-22).
     - Governance hooks exist for module load policies (capsule-style).
     - Still no host FS effects when running compiler in a child universe (VirtualFS only).
   - Current rolling note:
     - `oren build` / `oren meta` now support `--manifest` to emit `<out>.manifest.json` with a stable `sha256` record (use with `--deterministic` for content-addressed builds).
     - When `oren build --backend native --metadata` is used, `--manifest` also emits a manifest for the metadata sidecar (`<out>.meta.json.manifest.json`).
     - `./oretest` has integration fixtures that assert `--manifest` output exists (and includes `size_bytes`) for bytecode builds, `oren meta`, and native `--metadata` sidecars.
     - Manifests now include `size_bytes` (deterministic) to support artifact caching/GC.

### C) Libraries + Ecosystem (important, but not blocking core correctness)

1) **[stdlib][serde] Serde adaptors: tighten v1 surfaces**
   - Goal: keep the current JSON/YAML/CBOR v1 useful for real apps without pulling in a heavy toolchain.
   - DoD:
     - JSON/YAML decode: comment tolerance stays deterministic (already supported); improve diagnostics on malformed inputs.
     - CBOR: keep canonical map ordering and RFC 8742 sequence support; add roundtrip fixtures for nested shapes.
     - Ensure serde-generated helpers cover nested arrays/maps and preserve deterministic ordering.
