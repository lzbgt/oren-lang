# Oren Stdlib Layers (Builtin vs Shipped)

**Status:** Rolling (macOS-first, avoid blocking Linux)  
**Goal:** keep Oren syscall-first and libc-independent while still enabling a modern, batteries-included ecosystem.

This document defines the separation of concerns between:

1) **Compiler/runtime intrinsics** (compiler-known primitives)
2) **Builtin syslib** (shipped with the toolchain, minimal + stable)
3) **Shipped stdlib** (source modules, optional compiled artifacts)
4) **Third-party libraries** (user code)

The key constraint is that Oren is designed to:

- remain **independent of libc shims** for the native backend runtime
- support **AVM multiverse determinism** (replay, snapshot, governance)
- evolve in **rolling ABI** mode until a stabilized v1

## 1) Layer 0 — Intrinsics (compiler-known)

**Definition:** operations that the compiler and/or runtime implement directly and that are not “just a library function”.

Examples (current / expected direction):

- `oren_string_len`, `oren_string_slice`, `oren_string_char_at`
- `oren_list_len`, `oren_list_push`
- core allocation hooks used by the native backend runtime
- AVM bytecode ops (TIME/RNG/task/etc in `.obc`)

**Rules:**

- Intrinsics are small and carefully governed; they are the “machine model”.
- Intrinsics must have stable, deterministic semantics once v1 stabilizes.
- For AVM: intrinsic-effect domains (FS/NET/PROC/ENV/TIME) must be explicit and capability-governed.

## 2) Layer 1 — Builtin Syslib (shipped with toolchain)

**Definition:** a small set of `.oren` modules shipped with the compiler/AVM that:

- are required by the toolchain itself, and/or
- are required to bootstrap higher-level libs,
- and are kept intentionally minimal to avoid “everything becomes builtin”.

**Examples (intended):**

- `std/strings` (basic string helpers)
- `std/bytes` (byte helpers, endian reads/writes; used by packet parsing)
- `std/result` (small error/value helpers used across stdlib)
- `std/argparse` (used by `./oren` and `./avm` CLIs)
- `std/math` (portable helpers: abs/min/max/clamp + `is_nan`)
- `std/regex` (deterministic Thompson NFA; no catastrophic backtracking)
- `std/json` (portable explicit `JsonValue`; tolerant decode for config text)
- `std/yaml` (deterministic subset; tolerant decode for common config text)
- `std/cbor` (deterministic subset + CBOR Sequences streaming helpers)

**Rules:**

- Syslib should not silently take host effects.
- Syslib should accept explicit capability objects for host effects (or remain pure).
- Syslib must remain usable by both:
  - native backend (syscall-first substrate)
  - AVM backend (virtualized domains)

## 3) Layer 2 — Shipped Stdlib (source modules)

**Definition:** “batteries included” libraries that are shipped as source and imported normally, but are not required for bootstrapping the compiler.

Examples:

- HTTP/WebSocket libraries on top of `NET`
- higher-level filesystem path libraries on top of `FS`
- JSON schema tooling (if not required by the compiler itself)

**Rules:**

- Can evolve faster than syslib.
- Should be kept modular (SOLID): avoid monolith “mega stdlib”.
- Still must respect capability-driven IO for governance and nested universes.

## 4) Layer 3 — Third-party libraries

**Definition:** user modules (source or compiled) distributed outside the repo.

Design goal:

- unknown attributes in user code must remain inert by default (determinism),
  but preserved for tooling/policy scan and future governance rules.

## 5) Attributes & Stdlib (why attributes are “syslib-adjacent”)

Attributes are compile-time metadata (not runtime decorators). They matter for stdlib because:

- JSON serde wants field-level rename/skip/default
- networking wants packed struct “views” over bytes
- governance wants capability declarations and policy scanning

### Determinism + “config ergonomics”

Oren accepts some common config conveniences while keeping output canonical and deterministic:

- `std/json.decode(...)` tolerates C-style comments (`// ...` and `/* ... */`) for config compatibility.
- `std/yaml.decode(...)` tolerates:
  - YAML `# ...` comments, and
  - C/JSON `// ...` and `/* ... */` comments,
  using a whitespace/start rule to avoid breaking values like `http://example.com`.

Encoders remain canonical and deterministic (they do not emit comments).

### Determinism rules (v0, current implementation)

- Attribute arguments are restricted to literals: `int`, `float`, `bool`, `string`, `nil`.
- Unknown attributes are allowed and inert in rolling mode.
- A strict mode exists for enforcing allowlists (for governance and controlled builds).

Current implementation locations:

- parser parses `@attr(...)` into `Attr` nodes with literal args (`lib/compiler/parser_core.oren` + `lib/compiler/parser_parse.oren`)
- native backend supports `--metadata` output (`<out>.meta.json`) for tooling
- strict attribute mode is implemented and enforced at parse-time (`--strict-attrs` + `--attr-allow-prefixes`, see `./oren build --help`)

Ergonomics (rolling):

- reserved compiler directives:
  - `@pack` (canonical in metadata: `oren.packed`)
  - `@abi` (canonical in metadata: `oren.abi`)
- serde namespace (canonical for tooling/codegen):
  - accept `@json.*` as a frontend alias, canonicalize to `@serde.*`

## 6) Recommended placement guide (quick reference)

Put it in:

- **Intrinsic**: if the compiler must understand it to compile programs at all.
- **Syslib**: if it’s required by the compiler/AVM tooling, or required for bootstrapping core libs.
- **Stdlib**: if it’s useful for apps but not required for toolchain correctness.
- **Third-party**: if it’s domain-specific or rapidly evolving.

Example calls:

- `print`: syslib (tooling depends on it)
- JSON: syslib or stdlib (depends on whether the compiler/AVM need it)
- HTTP/WebSocket: stdlib (built atop NET)
