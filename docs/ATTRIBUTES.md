# Oren Attributes (Cookbook, Rolling)

Attributes are Oren’s **compile-time metadata channel**.

They exist to make the language/toolchain modern and ergonomic **without** introducing runtime reflection, hidden host effects, or nondeterminism (critical for AVM + multiverse).

## 1) Syntax (surface vs canonical)

Oren accepts a small set of ergonomic aliases in source code, and **canonicalizes** them before strict validation and before emitting metadata.

Recommended user-facing forms:

- `@pack` (packed byte views over `bytes`)
- `@abi` (ABI layout-only structs for FFI / `sizeof` / `offsetof`)
- `@json.*` (serde annotations for tooling / future codegen)
- `@doc("...")` (docs)

Canonical names in metadata (what `oren meta` / `--metadata` exports):

- `oren.packed`
- `oren.abi`
- `serde.*`
- `doc`

This keeps source code terse but ensures tooling has a stable, non-colliding namespace.

## 2) Determinism rules (must-haves)

1) **Unknown attributes are inert by default**
   - Unknown attributes must not change codegen, execution, hashes, gas/time, policy scan results, etc.
   - Unknown attributes may be preserved in metadata for tooling.

2) **Attribute arguments are compile-time constants (v0)**
   - Allowed values: `int`, `bool`, `string`, `nil`
   - Not allowed: arbitrary expressions or function calls

3) **Reserved namespaces**
   - Tool/compiler reserved: `oren.*`, `avm.*`, `cap.*`, `ffi.*`, `codegen.*`, `trace.*`

## 2.1 Metadata shape (what tooling consumes)

The metadata emitted by:

- `./oren meta <file.oren> -o out.meta.json`, and
- `./oren build ... --metadata` (embedded + sidecar),

uses a simple, stable structure for attributes:

```json
{
  "attrs": [
    {
      "name": "serde.rename",
      "args": [
        {"key": null, "value": "user_id"}
      ]
    }
  ]
}
```

Notes:

- `args[*].key` is `null` for positional arguments; keyword args (future) would fill `key`.
- argument values are literal-only in v0.

## 3) Strict attribute mode (governance / auditing)

Strict attribute mode is implemented and enforced at parse-time:

- `--strict-attrs`: reject unknown attributes
- `--attr-allow-prefixes myorg.,acme.`: allowlist custom namespaces in strict mode

This is intended for audited builds and later swarm/consensus workflows.

## 4) Cookbook examples

### 4.1 Packed struct view over bytes (`@pack`)

Use `@pack` on a struct to define a deterministic view over a backing `bytes`/`u8[]` buffer.
Fields use **type annotations** (not attributes) to specify endian/width.

```oren
@pack
struct Ipv4Header {
    v_ihl: u8,
    tos: u8,
    len: u16be,
    src: u32be,
    dst: u32be
}
```

The compiler lowers reads/writes to `oren_bytes_get_*` / `oren_bytes_set_*` helpers (no allocations, no reflection).

### 4.2 ABI layout-only struct (`@abi`)

Use `@abi` to compute deterministic field offsets and sizes without depending on host SDK/system headers at build time.

```oren
@abi
struct SockAddrIn {
    sin_len: u8,
    sin_family: u8,
    sin_port: u16be,
    sin_addr: u32be
}
```

This is intended for syscall-first FFI and low-level networking codegen.

### 4.3 Serde metadata (`@json.*` / canonical `@serde.*`)

Serde attributes are supported as metadata (for tooling) and also have an **opt-in** JSON v1 codegen path.

```oren
struct User {
    @json.rename("user_id")
    id,

    @json.skip()
    internal_cache
}
```

Current behavior (rolling):

- `oren meta` / `--metadata` include these attrs in a structured form.
- `std/json` is a portable explicit `JsonValue` representation.

Opt-in JSON v1 codegen (implemented):

```oren
@json.derive("json")
struct User {
    @json.rename("user_id")
    id: i32,
    active: bool,
    name: string,

    // Skip requires a default so decode stays deterministic.
    @json.skip()
    @json.default(0)
    internal: i32
}
```

This generates (rolling names):

- `User__json_encode(x)` → JsonValue
- `User__json_decode(jv)` → `{ok, err?, v?}`

Planned next step:

- add attribute-driven serde codegen helpers (compiler phase or AVM metadata query) so libraries can implement ergonomic:
  - `json.encode(User{...})`
  - `json.decode(User, "...")`

## 5) Practical tooling

- `./oren meta <file.oren> -o out.meta.json` exports metadata including attributes
- `./oren dump tokens <file.oren> -o out.tokens.json` helps debug attribute parsing and spans

For the rolling rules and priorities, see `docs/TODOS.md`.
