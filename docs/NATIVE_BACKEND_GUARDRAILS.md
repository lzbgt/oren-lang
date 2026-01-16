# Native Backend Guardrails (Tier‑1, Rolling)

This document is a short “do not regress” checklist for Oren’s **native backend** and **native runtime**.
It is intentionally practical:

- each item states the invariant (what must stay true),
- why it exists (failure mode),
- and the regression gate that should catch it.

If you change an invariant, update this file *and* the gate.

## How to verify quickly

- Local fast gate (arm64-macos): `make test`
- Local + container (no remote required): `make verify-native-net-skip-remote`
- Cross-target buildability (no remote required): `make verify-native-x64-compile`
- Local x64-linux runtime (no remote required): `make verify-x64-linux-qemu`
- Full Tier‑1 matrix (requires remote Win11/WSL2): `make verify-tier1`

## 1) Never call string ops on untagged non-strings

Invariant:

- Native values are not fully tagged yet. Runtime helpers must not call `strcmp` / string scanning on a value
  unless it is proven to be a valid string pointer.

Why:

- On native backends, integers can look like pointers (and vice versa). Calling `strcmp` on an integer value
  can segfault or run off into unmapped memory.

Rule of thumb:

- Use `oren_is_string(v)` (backed by `native_is_string_ptr`) before `strcmp`.

Regression:

- `make test` (native quick integration exercises iterable-map protocol tags and other map/string flows).

## 2) Iterable-map protocol tags must be byte-matched (not pointer-identity)

Invariant:

- The iterable-map protocol uses a marker key `__iter` and a tag string such as `"range"` / `"list_slice"`.
- The runtime must treat tags as strings **by bytes**, guarded by `oren_is_string(__iter)`.
- Literal pointer equality may be used as a fast path, but must not be required for correctness.

Why:

- Depending on build caches/rtobj merges/linking, “equal string” values can be represented by different pointers.
- A user can also construct an equal heap string (`"ra"+"nge"`) that is not pointer-equal to the literal `"range"`.

Regression:

- `make test` includes a regression where `{"__iter": "ra"+"nge", ...}` must iterate correctly.

## 3) Embedded string literals are constant-section data, not GC allocations

Invariant:

- String literals in native output are emitted into a single `cstr0` pool in the binary’s data segment.
- They must not be tracked as GC allocations (no alloc nodes).
- The runtime builds a **literal membership set** at entry (`oren_init_static_cstr0_table`) so `oren_is_string`
  can recognize literal pointers safely.
- Even if compiler/codegen mistakenly attempts to track a literal, the runtime must treat it as a no-op:
  - `oren_track_alloc(lit, ..., kind=STRING)` must not create a node.
  - `oren_track_static(lit, kind=STRING)` must not create a node.

Why:

- Tracking literals as alloc nodes makes GC work explode in compiler workloads (many literal keys in maps).
- Allocating tracking metadata per literal is a startup hotspot for large binaries.

Regression:

- `make test`
- `make verify-native-net-skip-remote` (stresses compiler runtime + NET/TLS loops)

## 4) Alloc-index internals must avoid `==`/`!=` pointer comparisons

Invariant:

- The alloc-index (`oren_find_node` / `native_alloc_index_get`) must not use `==/!=` between non-constant values
  when those operators can lower to string-aware comparisons.
- Prefer arithmetic compares (`(a - b) == 0`) for pointer identity checks.

Why:

- If a string-aware compare re-enters the alloc-index, it can recurse and crash during early init.

Regression:

- `make test` (compiler workloads drive alloc-index usage)

## 5) Windows bring-up: stage0 + stage1/2 C backend should prefer MSVC `cl.exe`

Invariant:

- On Windows hosts, the default C toolchain for stage0->stage1 bring-up is **MSVC `cl.exe`**.
- Toolchain setup is auto-configured via `vswhere.exe` → `VsDevCmd.bat` / `vcvars64.bat` when `--cc cl` is selected.
- Do not default to `cl.exe` when *cross-compiling* Windows from non-Windows hosts; require explicit `--cc`.

Why:

- Tier‑1 Windows users should be able to build without MSYS2/MinGW assumptions.
- Cross-compiling Windows C outputs from macOS/Linux is a separate (explicit) path.

Regression:

- Remote: `make verify-stage0-win` and `make verify-stage2-win` (requires reachable Win11 host).

## 6) Keep scripts bounded and log output small

Invariant:

- CI/rolling development must not hang indefinitely:
  - per-build and per-test timeouts are enforced,
  - scripts print bounded tails/snippets (avoid dumping megabytes).

Why:

- The fastest way to lose velocity is “hung build with no signal”.

Regression:

- `make test` should stay fast by default (and the scripts should always have bounded output).

## 7) x64-windows: validate exports via PE Export Directory (not string search)

Invariant:

- When the native backend is expected to export symbols on **x64-windows** (both):
  - `--lib` outputs (`.dll` exports like `add`, `mul`), and
  - `@ffi.export` callback-style exports on `.exe`,
  the symbol names must appear in the **PE Export Directory**.

Why:

- A byte/string search is not proof of export correctness:
  - the name could appear in debug strings, metadata, or pooled literals,
  - while the export table is missing or malformed.
- Real consumers (`GetProcAddress`) consult the export table, not random bytes.

Regression:

- `make verify-native-x64-compile` (compile-only gate)
  - Uses `scripts/pe_exports_check.py` to parse the PE export directory (no external deps).
- `make examples-cross-compile-smoke` (compile-only `--lib` API sanity)

## 8) x64-linux: shared library + FFI resolution must run under QEMU

Invariant:

- On **x64-linux**, the native backend must be able to:
  - emit a shared library via `--lib` (`.so`), and
  - emit an executable that links/resolves symbols from that `.so` via `--link`,
  and the result must run correctly (not just compile).

Why:

- “Compile-only” checks miss runtime/linker/FFI resolution failures (e.g. missing export table, wrong resolver behavior, wrong calling convention).
- This is a high-signal parity gate for the x64 backend without requiring a remote WSL2 host.

Regression:

- `make verify-x64-linux-qemu` runs `examples/libmath.oren --lib` + `examples/ffi_from_libmath.oren` under `qemu-x86_64` in the persistent Linux container.

## 9) FFI bindings must remain module-exportable (internal name ≠ external symbol)

Invariant:

- A module may declare `ffi foo`, and callers may access it as a module member:
  - `import m "std:ffi/libc"` then `m.strlen("oren")`
- Module namespacing/prefixing may rewrite the **internal** function label (e.g. `STD_ffi_libc_strlen`),
  but the **external** symbol name used for loader lookup must remain the source identifier (`strlen`).

Why:

- Without this split, module prefixing breaks FFI (call sites reference the prefixed label, but the resolver/binder searches for the prefixed external symbol which does not exist).
- Stdlib needs this to hide `@cfg` + `@ffi.link/@ffi.dll` boilerplate behind a stable API surface.

Regression:

- `scripts/verify_native_matrix.sh` executes `tests/native/test_std_ffi_libc_smoke.oren` on Tier‑1 targets (stage1 + stage2).
- `make verify-x64-linux-qemu` also builds/runs the same fixture under `qemu-x86_64` (local, no remote required).

## 10) Debug-info symbolication must never crash (debug builds)

Invariant:

- Debug-info tables and symbol resolvers (`oren_set_debug_info`, `oren_resolve_symbol`) are **best-effort diagnostics**.
- Malformed/corrupted tables must not crash the process (bail out / return `"???"`), even in debug mode.

Why:

- Many Tier‑1 smokes compile with `--debug` (including `make test`), so a debug-info parsing crash blocks iteration.
- Diagnostics must not turn a recoverable bug into a hard segfault.

Regression:

- `make test` (native quick integration is built with `--debug` and installs debug info at entry)

## 11) Green ctx-switch must preserve long-lived locals across yields

Invariant:

- A local pointer kept live across many `oren_green_yield()` points must remain valid and stable.

Why:

- If ctx-switch lowering or backend stack/register discipline is wrong, locals can collapse to small/misaligned integers
  and later crash in `ptr_get`/`ptr_set`.

Regression:

- `make test` via `tests/native/test_quick_integration_native.oren`:
  - `test_green_local_ptr_survives_yields`
  - `test_green_workers_local_ptr_survives_yields`
