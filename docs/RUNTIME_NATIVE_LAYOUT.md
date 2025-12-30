# Native Runtime Layout (Overflow-Proof) — `lib/runtime_native/*` (Rolling)

The native backend injects a “runtime” into every native build. Historically this lived in one large file.
In rolling mode we keep it **split into small modules** to avoid review/context overflow.

## Where to edit

- Include-root: `lib/runtime_native.oren`
  - This file is intentionally tiny.
  - It contains a list of `// @include "runtime_native/NNN_name.oren"` directives.
- Real implementation: `lib/runtime_native/*.oren`
  - Each file is a cohesive “slice” (time, tcp, byte order, capsule hooks, etc).

The compiler expands `// @include` directives at compile time, so the injected runtime behaves like a single
translation unit, but stays maintainable in source form.

## Why this avoids context overflow

- Each chunk stays small (hundreds of lines, not thousands).
- You can review/edit one subsystem at a time without loading the entire runtime.
- `oretest` enforces include-chunk coherence so we don’t accidentally regress back into a monolith.

## How to add a new runtime module

1) Create a new chunk file under `lib/runtime_native/`:
   - Use a numeric prefix to keep ordering obvious (e.g. `270_crypto.oren`).
   - Keep it focused; if a chunk grows too large, split it again.
2) Add a corresponding include line to `lib/runtime_native.oren`.
3) Run `make test` to ensure the include expansion and runtime audits stay green.

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
