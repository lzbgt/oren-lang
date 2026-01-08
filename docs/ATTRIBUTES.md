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

### 2.2 Normalized serde schema (what libraries/tooling want)

In addition to the raw attribute list, `oren meta` also emits a **normalized** serde schema per struct when any `@serde...` / `@json...` attributes are present.

This is designed so libraries can implement JSON/YAML/TOML/etc on top of a stable metadata contract (without importing compiler internals and without runtime reflection).

Shape (rolling, v1):

```json
{
  "name": "User",
  "serde": {
    "version": 1,
    "format": "json",
    "tag": "User",
    "fields": [
      {"name":"id","ann_type":"i32","wire":"user_id","skip":false,"default":null}
    ]
  }
}
```

## 3) Strict attribute mode (governance / auditing)

Strict attribute mode is implemented and enforced at parse-time:

- `--strict-attrs`: reject unknown attributes
- `--attr-allow-prefixes myorg.,acme.`: allowlist custom namespaces in strict mode

This is intended for audited builds and later swarm/consensus workflows.

## 3.2 Conditional compilation (`@cfg` / canonical `@oren.cfg`)

`@cfg(...)` is Oren’s **minimal conditional compilation** mechanism.

It is evaluated at compile time based on the selected target platform:

- `--platform <arch>-<os>` (preferred), or
- `--target/--arch` (legacy), or
- env fallback `OREN_PLATFORM=<arch>-<os>`.

If a declaration does not match its `@cfg`, it is **removed from the program** before later compiler passes.

Supported forms (rolling v0):

- Positional (string selector):
  - `@cfg("x64-windows")`
  - `@cfg("linux")`
  - `@cfg("arm64")`
- Keyword (CSV strings; AND across keys):
  - `@cfg(os="linux,macos")`
  - `@cfg(arch="x64")`
  - `@cfg(platform="arm64-linux")`
  - Negation keys: `not_os`, `not_arch`, `not_platform`

Notes (important):

- `@cfg` is implemented for **declarations** (`fn`, `struct`, `ffi`, `var`).
- `@cfg` is **not supported on `import` yet**:
  - stage2 has a fast lexer-only import scan that cannot respect conditional imports
  - gate platform-specific declarations *inside* the imported module instead

Example (FFI library name differs per OS):

```oren
@cfg(os="windows")
ffi GetTickCount

@cfg(os="linux,macos")
ffi getpid
```

### 3.3 FFI link dependencies (`@ffi.link(...)`) (native backend)

The native backend supports dynamic linking for FFI in a platform-specific way:

- **macOS (Mach-O):** additional dylibs are loaded via `LC_LOAD_DYLIB`.
- **Linux (ELF):** dynamic linking is enabled when at least one `--link` library exists; `ffi` is then resolved via a lazy `dlsym` resolver.
- **Windows (PE):** `ffi` is resolved via lazy `LoadLibraryA` + `GetProcAddress`; `--link` supplies DLL search names/paths.

For stdlib and portable libraries, it’s often undesirable to require every consumer to pass `--link`.
To support this, an `ffi` declaration may attach an explicit link dependency:

```oren
@cfg(os="linux")
@ffi.link("libc.so.6")
ffi strlen
```

Notes:

- The argument must be a single string literal (v0 determinism rule).
- `@ffi.link("...")` is treated as if the user passed `--link ...` on the command line.

### 3.4 FFI library attachment (`@ffi.dll(...)`) (Windows native backend)

On Windows, `ffi` symbols are resolved lazily via `LoadLibraryA` + `GetProcAddress`.

By default, the resolver searches:

- any DLLs passed via `--link ...`, then
- a built-in fallback `kernel32.dll`

For stdlib code (and portable libraries), it’s often undesirable to require every consumer to pass `--link`.
To support this, an `ffi` declaration may attach an explicit DLL name:

```oren
@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi puts

fn main() {
    puts("hello")
}
```

Notes:

- This attribute is currently consumed only by the **x64-windows native backend**.
- The argument must be a single string literal (v0 determinism rule).
  - On other native targets, prefer `@ffi.link("...")` for portability.

### 3.5 FFI return typing (`@ffi.ret(...)`) (native backend)

Some foreign functions return narrow integer types at the ABI level (most commonly C `int`, i.e. signed 32-bit).
Native ABIs do not require the upper 32 bits of the return register to be sign-extended for such functions.

Oren uses 64-bit value carriers, so the native backend needs an explicit hint to lower the return correctly.

Example (Linux):

```oren
@cfg(os="linux")
@ffi.link("libc.so.6")
@ffi.ret("i32")
ffi atoi

if atoi("-1") != -1 { exit(1) }
```

Notes (rolling v0):

- The argument must be a single string literal (v0 determinism rule).
- Currently supported return kinds:
  - `"i32"`: sign-extend the 32-bit return to a signed 64-bit value.
  - `"u32"`: zero-extend the 32-bit return to an unsigned 64-bit value (0..4294967295).
  - `"void"`: treat as no return value; force the return register to `0` for expression contexts.
- This attribute is currently consumed by:
  - `arm64-*` native backend
  - `x64-*` native backend

### 3.6 FFI exports (`@ffi.export`) (native backend; callback interop)

Some OS APIs require **C-style callbacks**, i.e. the library expects a *raw function pointer* to a symbol in the program image.

To support this in a controlled way, a top-level function may be marked as exported:

```oren
@cfg(os="macos")
@ffi.export
fn my_callback(arg0, arg1) {
    // ...
}
```

Notes (rolling):

- This is currently consumed only by the **arm64-macos native backend**.
  - On other targets, it is ignored (no export table is generated yet).
- The exported symbol name is the *linked* top-level name (module-prefixed).
  - For stdlib modules imported as `std:...`, the module prefix is stable.
- This attribute is primarily used internally by stdlib providers (e.g. `std:net/tls` SecureTransport IO callbacks via `dlsym(RTLD_DEFAULT, ...)`).

## 3.1 Compiler/runtime internal attributes (reserved)

These are **not** intended for user code. They exist to keep the compiler + Tier‑1 native runtime maintainable while still running whole-program DCE.

### `@oren.keep` (pin as a DCE root)

`@oren.keep` pins a top-level function as a **global DCE root**, even if the function is not reachable from `main` / `__top_level__` in the linked AST.

Why this exists (Tier‑1 native backends):

- Entry stubs can call runtime init helpers (not visible in the AST).
- Some compiler passes can emit calls via **codegen fixups** (direct calls by symbol name) without emitting a corresponding AST call expression.

Without `@oren.keep`, whole-program DCE can delete these functions, causing native codegen/linking to fail with an undefined symbol.

Notes:

- Capsule syscall hook functions are also treated as an internal ABI surface and are kept by name prefix (`native_capsule_sys_*`) in the DCE pass, because syscall lowering may reference them without emitting AST calls.
- This is a rolling mechanism; longer-term, the goal is to make these dependencies explicit in a shared CoreIR boundary so DCE does not need backend-specific knowledge.

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
// Prefer `@serde(...)` (canonical namespace). `@json(...)` remains supported as an alias.
@serde(format="json")
struct User {
    @serde(rename="user_id")
    id: i32,
    active: bool,
    name: string,

    // Skip requires a default so decode stays deterministic.
    @serde(skip=true, default=0)
    internal: i32
}
```

This generates (rolling names):

- `User__json_encode(x)` → JsonValue
- `User__json_decode(jv)` → `{ok, err?, v?}`

Multi-format derive (rolling):

```oren
@serde(formats="json,yaml,cbor", tag="User")
struct User {
    id: i32,
    name: string
}
```

This generates the corresponding pairs for each requested format:

- `User__json_encode` / `User__json_decode`
- `User__yaml_encode` / `User__yaml_decode`
- `User__cbor_encode` / `User__cbor_decode`

Note: the normalized `meta.serde` schema now includes `"formats": [...]` when `@serde(formats=...)` is used. Tooling should still read raw `attrs` if it needs to preserve unknown/custom attributes.

Other supported serde formats (rolling, v1):

- `@serde(format="cbor")` generates:
  - `User__cbor_encode(x)` → CborValue (tagged; see `lib/std/cbor.oren`)
  - `User__cbor_decode(cv)` → `{ok, err?, v?}`
- `@serde(format="yaml")` generates:
  - `User__yaml_encode(x)` → YamlValue (tagged; see `lib/std/yaml.oren`)
  - `User__yaml_decode(yv)` → `{ok, err?, v?}`

YAML decode (config tolerance):

- `std/yaml.decode(...)` accepts YAML `# ...` comments and also C/JSON-style `// ...` and `/* ... */` comments.
- Comment detection is restricted (start/whitespace rule) to avoid breaking values like `http://example.com`.
  Encoders remain canonical (no comments).

CBOR streaming (rolling, v1):

- `lib/std/cbor.oren` implements CBOR Sequences (RFC 8742) for streaming:
  - `cbor.encode_sequence([CborValue...]) -> bytes` (concatenation)
  - `cbor.decode_next(bytes, pos) -> {ok, err?, v?, pos}` (incremental)
  - `cbor.decode_sequence(bytes) -> {ok, err?, v:[CborValue...], pos}`
  - serde-friendly typed helpers:
    - `cbor.encode_sequence_typed(items, Type__cbor_encode) -> bytes`
    - `cbor.decode_next_typed(bytes, pos, Type__cbor_decode) -> {ok, err?, v:<T>, pos}`
    - `cbor.decode_sequence_typed(bytes, Type__cbor_decode) -> {ok, err?, v:[T...], pos}`

Planned next step:

- add attribute-driven serde codegen helpers (compiler phase or AVM metadata query) so libraries can implement ergonomic:
  - `json.encode(User{...})`
  - `json.decode(User, "...")`

## 5) Practical tooling

- `./oren meta <file.oren> -o out.meta.json` exports metadata including attributes
- `./oren dump tokens <file.oren> -o out.tokens.json` helps debug attribute parsing and spans

For the rolling rules and priorities, see `docs/TODOS.md`.
