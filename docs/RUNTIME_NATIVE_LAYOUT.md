# Native Runtime Layout (Overflow-Proof) — `lib/runtime_native/*` (Rolling)

The native backend injects a “runtime” into every native build. Historically this lived in one large file.
In rolling mode we keep it **split into small modules** to avoid review/context overflow.

## Where to edit

- Include-root (default, non-capsule): `lib/runtime_native.oren`
  - For capsule builds, the runtime entry file is `lib/runtime_native_capsule.oren`.
  - This file is intentionally tiny.
  - It contains a list of `// @include "runtime_native/NNN_name.oren"` directives.
- Real implementation: `lib/runtime_native/*.oren`
  - Each file is a cohesive “slice” (time, tcp, byte order, capsule hooks, etc).

The compiler expands `// @include` directives at compile time, so the injected runtime behaves like a single
translation unit, but stays maintainable in source form.

## Why this avoids context overflow

- Each chunk stays small (hundreds of lines, not thousands).
- You can review/edit one subsystem at a time without loading the entire runtime.
- Repo audits should enforce include-chunk coherence so we don’t accidentally regress back into a monolith.

## How to add a new runtime module

1) Create a new chunk file under `lib/runtime_native/`:
   - Use a numeric prefix to keep ordering obvious (e.g. `270_crypto.oren`).
   - Keep it focused; if a chunk grows too large, split it again.
2) Add a corresponding include line to the appropriate runtime entry file:
   - default (non-capsule): `lib/runtime_native.oren`
   - capsule builds: `lib/runtime_native_capsule.oren`
3) Run `make test-native-all` (or at least `make test-native-quick`) to ensure include expansion and runtime behavior stay green.

## Early-init guardrails (must stay robust cross‑OS)

The native runtime runs during **program entry** before any user code. In rolling mode, assume:

- global initializers may not reliably run before `native_runtime_init`
- some “fast path” intrinsics may temporarily be buggy on new targets

Hard rule: early-init code must not segfault just because a raw allocator returns garbage.

Implementation guardrail:

- `lib/runtime_native/015_raw_alloc.oren` defines `native_malloc_raw_or_mmap(size)`.
  - It validates the native-backend `malloc_raw` intrinsic result.
  - If invalid, it falls back to `sys_mmap_private_anon`.
  - `native_runtime_init` and envp construction use this helper so `scripts/verify_native_matrix.sh --targets arm64-linux`
    can compile+run artifacts in the Linux container reliably.

## Oren-owned stable ABIs (recommended)

Some low-level “syscall-first” APIs expose raw buffers for performance. In rolling mode we prefer an
**Oren-owned stable layout** rather than mirroring host C structs, so tests and libraries remain
OS/arch neutral.

Current example:

- **OrenStatV0** (used by `sys_stat/sys_lstat/sys_fstat`):
  - Compiler-side layout source: `lib/compiler/native_stat_abi.oren`
  - Runtime-side helpers: `lib/runtime_native/215_stat.oren`

## Notes / Footguns

- Prefer modern surface syntax in higher-level helpers:
  - string concatenation: use `+` rather than `string_concat(...)` chains
  - list operations: use container method sugar where possible
- Do not edit generated `.c` artifacts (they are build outputs / debug aids).

## Embedded string literals (constant pool)

Native-backend string literals are intentionally treated as **static data**, not GC heap objects:

- The code generator de-duplicates string-literal bytes into a `cstr0` pool in the appended data blob.
- The program entry stub calls `oren_init_static_cstr0_table(table_ptr)` once at startup to register all embedded literals
  as **static-kind STRING** for safe container ops (maps infer key kind from `oren_find_node(ptr).kind`).
- The GC mark path (`oren_mark_value`) explicitly skips static-kind strings (size=0) so literals do not inflate GC roots or
  participate in mark/sweep.

The quick native integration fixture asserts these properties:
- `tests/native/test_quick_integration_native.oren` (`test_string_literals_static`).
