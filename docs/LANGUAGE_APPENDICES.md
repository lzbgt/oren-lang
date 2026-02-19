# Language Appendices (Rolling)

This document consolidates advanced language features and runtime-model notes to keep the core manual/spec lean.

## Oren Attributes (Cookbook, Rolling)

Attributes are Oren’s **compile-time metadata channel**.

They exist to make the language/toolchain modern and ergonomic **without** introducing runtime reflection, hidden host effects, or nondeterminism (critical for AVM + multiverse).

## 1) Syntax (surface vs canonical)

Oren accepts a small set of ergonomic aliases in source code, and **canonicalizes** them before strict validation and before emitting metadata.

Recommended user-facing forms:

- `@pack` (packed byte views over `bytes`)
- `@abi` (ABI layout-only structs for FFI / `sizeof` / `offsetof`)
- `@json.*` (serde annotations for tooling / future codegen)
- `@doc("...")` (docs)
- `@cfg(...)` (conditional compilation)
- `@debug` / `@release` (build-profile shorthand for debug-only / release-only code)

Canonical names in metadata (what `oren meta` / `--metadata` exports):

- `oren.packed`
- `oren.abi`
- `serde.*`
- `doc`
- `oren.cfg`
- `oren.debug`
- `oren.release`

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
  - `@cfg("debug")` / `@cfg("release")` (build profile)
- Keyword (CSV strings; AND across keys):
  - `@cfg(os="linux,macos")`
  - `@cfg(arch="x64")`
  - `@cfg(platform="arm64-linux")`
  - Negation keys: `not_os`, `not_arch`, `not_platform`
  - `@cfg(debug=true)` / `@cfg(debug=false)`

Notes (important):

- `@cfg` is implemented for **declarations** (`fn`, `struct`, `ffi`, `var`) and **statements** inside blocks.
- `@cfg` is **not** a general “preprocessor”:
  - it does **not** apply to arbitrary expressions
- When using `@cfg` to provide platform variants (e.g. per‑OS implementations of the same `fn`), the variants must be **mutually exclusive**.
  - Otherwise multiple copies of the same declaration can survive the filter and cause duplicate symbol / duplicate definition errors.
  - A common pattern is to provide an explicit fallback via negation selectors such as `@cfg(not_os="windows,macos,linux")`.
- `@cfg` is **not supported on `import` yet**:
  - stage2 has a fast lexer-only import scan that cannot respect conditional imports
  - gate platform-specific declarations *inside* the imported module instead

Build-profile note:

- Debug/release selectors are driven by the compiler’s build profile:
  - Native builds default to **debug** (for readable stack traces).
  - `--no-debug` (or `OREN_NATIVE_NO_DEBUG=1`) selects **release**.
  - Shorthand attributes exist:
    - `@debug` ⇒ `@cfg("debug")`
    - `@release` ⇒ `@cfg("release")`
    - Both are **arg‑less** and follow the same statement/declaration rules as `@cfg`.
  - Block sugar exists for multi-line sections:
    - `debug { ... }` ⇒ `@debug { ... }`
    - `release { ... }` ⇒ `@release { ... }`
  - Statement sugar:
    - `dbg(...)` expands to `@debug print(...)` with a `file:line` prefix.
    - `dprint(...)` expands to `@debug print(...)` with no prefix.
  - Expression sugar (single-arg only):
    - `dbg(expr)` returns `expr` and prints it in **debug** builds (compiled out in release).
    - `dprint(expr)` returns `expr` and prints it in **debug** builds (compiled out in release).

Example (FFI library name differs per OS):

```oren
@cfg(os="windows")
ffi GetTickCount

@cfg(os="linux,macos")
ffi getpid
```

Related FFI ergonomics (rolling):

- The attribute form is the primary mechanism to attach a library/DLL:
  - `@ffi.link("libc.so.6") ffi { puts, atoi }`
  - `@ffi.dll("msvcrt.dll") ffi { puts, atoi }` (Windows convenience)
- A small portable alias exists for the platform C library (reduces `@cfg` boilerplate):
  - `@ffi.libc @ffi.ret("i32") ffi { puts, atoi }` (Tier‑1 maps to msvcrt/libc/libSystem)
- The parser also supports a small sugar that lowers to the portable `@ffi.link(...)`:
  - `ffi("libc.so.6") { puts, atoi }`

Guideline (rolling):

- Prefer keeping `@cfg` as a narrow boundary tool (OS-specific APIs, syscall ABI differences).
- If you find yourself using `@cfg` only to select different libc names, prefer `@ffi.libc` (portable) instead.

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

### 3.3.1 Portable libc alias (`@ffi.libc`) (rolling)

When the only cross-platform difference is the **C library name** (Windows vs Linux vs macOS),
the repo supports a compiler-level alias:

```oren
@ffi.libc
@ffi.ret("i32")
ffi { puts, atoi }
```

Tier‑1 mapping (rolling):

- Windows: `msvcrt.dll`
- Linux: `libc.so.6`
- macOS: `libSystem.B.dylib`

Notes:

- This is intentionally narrow (only libc) to keep resolution deterministic and auditable.
- For other libraries (OpenSSL, Win32 DLLs, macOS frameworks), keep using `@ffi.link("...")` / `@ffi.dll("...")`
  or prefer `std:ffi/*` wrapper modules.

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

#### 3.4.1 FFI group sugar (rolling)

When importing many FFI symbols from the same library, repeating `@ffi.dll(...)` / `@ffi.link(...)` / `@ffi.ret(...)` can be noisy.

Rolling sugar:

```oren
@cfg(os="windows")
@ffi.dll("secur32.dll")
@ffi.ret("i32")
ffi { AcquireCredentialsHandleA, FreeCredentialsHandle, InitializeSecurityContextA }
```

This expands to multiple `ffi <name>` declarations, each inheriting the same outer attributes (and doc comment, if present).

Per-item attributes are also allowed inside the group, and are merged with the outer attributes:

```oren
@cfg(os="linux")
@ffi.link("libc.so.6")
ffi {
    @ffi.ret("i32") atoi,
    @ffi.ret("void") free,
    puts
}
```

A practical example is Windows APIs where one DLL exports a mix of pointer-returning functions and `BOOL`/`SECURITY_STATUS` style `i32` functions:

```oren
@cfg(os="windows")
@ffi.dll("crypt32.dll")
ffi {
    PFXImportCertStore,
    CertEnumCertificatesInStore,
    @ffi.ret("i32") CertCloseStore,
    @ffi.ret("i32") CertFreeCertificateContext
}
```

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
  - `"ptr"`: pointer-sized return. On Tier‑1 (arm64/x64) this is 64-bit, so it does not require normalization today; it is still accepted as ABI metadata.
  - `"usize"`: `size_t`/`usize` return. On Tier‑1 (arm64/x64) this is 64-bit, so it does not require normalization today; it is still accepted as ABI metadata.
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

- This is currently consumed by:
  - **arm64-macos native backend** (Mach-O): exports the symbol so `dlsym(RTLD_DEFAULT, ...)` can locate callback entry points.
  - **arm64-linux native backend** (ELF, dynamic executables): exports the symbol into the ELF dynamic symbol table for `dlsym(RTLD_DEFAULT, ...)`.
  - **x64-linux native backend** (ELF, dynamic executables): same as arm64-linux.
  - **x64-windows native backend** (PE, executables): emits a PE Export Directory so `GetProcAddress(GetModuleHandle(NULL), ...)` can locate callback symbols.
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

## Traits & Polymorphism (Static-first, Dyn-opt-in)

**Status:** Design doc (rolling; implementation may evolve)
**Scope:** Oren language semantics + AVM determinism constraints

This repo targets a “modern systems language” experience while keeping AVM execution:

- deterministic (replayable / consensus-friendly)
- capability-governed (FS/NET/PROC/ENV/TIME)
- efficient (no hidden allocations, SIMD-friendly data types)

That combination strongly suggests a **two-tier polymorphism model**:

1) **Static (compile-time) polymorphism**: zero-cost, deterministic, preferred.
2) **Dynamic (runtime) polymorphism**: explicit opt-in, governed, and restricted where necessary.

This document explains why both are needed, and how to keep the model elegant.

---

## 1) Why both static and dynamic exist

### Static dispatch is best for “systems + determinism”

Static polymorphism is what you want for:

- syscall-first stdlib wrappers (hot paths)
- numeric kernels and typed buffers (`i32_buf`, `f32_buf`, …)
- compiler-in-AVM style pipelines (predictable semantics)
- deterministic hashing (trace/result hashes)

Because:

- calls can be inlined / specialized
- no runtime vtables are required
- behavior is determined by source + compilation output only

### Dynamic dispatch is best for “plugins + heterogeneous containers”

Dynamic polymorphism is what you want for:

- plugin-style tool interfaces selected at runtime
- heterogeneous containers (e.g. list of “things that implement Writer”)
- cross-module / cross-universe boundaries where concrete types are unknown upfront

But it must be **explicit** and **governed**, because hidden runtime dispatch makes
performance, debugging, and determinism harder.

---

## 2) The recommended Oren model (v1 direction)

### 2.1 `trait` means compile-time by default

**Rule:** `trait` is a compile-time contract. It does not imply a runtime representation.

The “happy path”:

```oren
trait Add {
    fn add(self, rhs)
}

impl Add for i32 {
    fn add(self, rhs) { return self + rhs }
}

fn f(x, y) {
    // static dispatch: compiler resolves the impl
    return x.add(y)
}
```

### 2.2 `dyn Trait` (or equivalent) is explicit runtime dispatch

**Rule:** runtime polymorphism must be opt-in (spelled in source), e.g.:

```oren
var w: dyn Writer = make_writer()
w.write("hi")
```

Exact syntax is rolling, but the property is non-negotiable:

- if dispatch is dynamic, the source must say so.

---

## 3) Determinism constraints for runtime trait objects

If AVM is used for consensus/replay/snapshots, “trait objects” cannot be “host pointers”.

### 3.1 Stable representation (no host-pointer identity)

A trait object must be a deterministic value, conceptually:

```
{ value, vtable_id }
```

Where `vtable_id` is derived from deterministic program identity, such as:

- module path
- trait name
- impl symbol set (methods)
- (optional) version hash of the impl body / symbol signature

Never derive it from:

- process address
- dynamic loader pointers
- host timestamps

### 3.2 Governance / policy

Some operations must be restricted or explicitly defined:

- Equality: comparing trait objects by pointer identity is non-deterministic across universes; avoid or forbid.
- Hashing: using trait objects as map keys must be forbidden unless a stable hash is defined.
- Serialization: crossing universe boundaries needs a stable encoding; otherwise forbid by policy.

A simple safe rule for early v1 is:

- trait objects are callable only,
- but not comparable and not hashable,
- and not allowed as map keys.

---

## 4) How this relates to AVM and “modern power”

### 4.1 Static traits give you zero-cost abstractions

Static traits cover most “modern language” use cases:

- iterators (compile-time lowering)
- numeric traits (`Add`, `Mul`, etc.)
- serialization helpers (derive-like expansion from metadata)

### 4.2 Dynamic traits enable agentic tool interfaces

When you need “a list of tools” chosen dynamically, `dyn Trait` becomes useful,
but it must integrate with:

- capability model (tool calls are effects)
- determinism (record/replay, hashes, snapshots)

Treat runtime polymorphism as a **VM feature**, not just “syntax sugar”.

---

## 5) Generic traits without per-type boilerplate (blanket impls + defaults)

The pain you’re pointing at is real: if Oren requires writing `impl Add for i32`, `impl Add for i64`, `impl Add for u64`, … for every trait, the model becomes noisy and *not* AI/agentic-friendly.

A modern, elegant way to avoid that is to support **generic trait mechanisms** at the *language* level, but keep them **deterministic** and **toolable**.

There are three complementary mechanisms; Oren should use **all three**, but staged.

### 5.1 Trait default methods (big win, minimal complexity)

Allow traits to provide **default method bodies**, expressed only in terms of:

- other trait methods
- pure operators on primitives
- whitelisted builtin helpers

Example direction:

```oren
trait Eq {
    fn eq(self, rhs)

    // default impl in terms of eq
    fn ne(self, rhs) { return !self.eq(rhs) }
}
```

Why it matters:

- you implement the “minimum core” (`eq`) once per type,
- you get a full surface (`ne`) for free,
- it does not require generics or a type checker.

Determinism note: defaults are just code; they compile like any other function and are deterministic.

### 5.2 Blanket impls / impl templates (“generic impl”) 

A **blanket impl** is an implementation that applies to a *family* of types.

This is how Rust avoids per-type boilerplate for `Option<T>`, `Vec<T>`, etc.

In Oren’s rolling world (where we’re still growing the type system), the *most future-proof* plan is:

- support generic impls over **nominal types** *once generics exist* (v1+), and
- in v0/v0.5, allow a limited “kind constraint” form for primitives/containers.

Rolling v0 (implemented today) also supports a minimal “catch-all” blanket:

```oren
// Applies to any runtime value.
// This is intentionally limited (no constraints yet) but unblocks ergonomic defaults.
impl Eq for any { fn eq(self, rhs) { ... } }
```

Resolution rule:

- If both `impl Trait for Type` and `impl Trait for any` exist, the concrete `Type` impl wins.

Conceptual examples (v1 direction):

```oren
// Applies to any T that is Eq.
impl[T] Eq for Option[T] where T: Eq {
    fn eq(self, rhs) {
        // ... compare tags and payloads ...
    }
}

// Applies to any T that is ToString.
impl[T] ToString for List[T] where T: ToString {
    fn to_string(self) { ... }
}
```

For primitives, you want “blanket over kinds”:

```oren
// Applies to all signed integer widths.
impl Eq for signed_int {
    fn eq(self, rhs) { return self == rhs }
}

// Applies to all floats.
impl Eq for float {
    fn eq(self, rhs) { return self == rhs }
}
```

We don’t have `signed_int`/`float` kind types yet — but *documenting this now* keeps the model coherent, and lets us add the syntax later without rewrites.

### 5.3 Derive-style expansion (attributes) for “data traits”

For traits that are purely structural (serde, hashing, comparisons), the most ergonomic solution is a derive.

Example:

```oren
@derive(Eq, Hash)
struct User { id: u64, name: string }
```

This is not runtime reflection.

It is **compile-time code generation** driven by metadata, which is deterministic and AVM-friendly.

---

## 6) Coherence + determinism rules for generic impls (non-negotiable)

Generic impls are powerful, but they can destroy determinism if resolution is ambiguous.

Oren should adopt a simple, strict **coherence rule** (Rust-like):

1) For any pair `(Trait, Type)`, there must be **at most one applicable impl**.
2) If multiple impls could apply, compilation is an error **unless** there is a single “most specific” impl by a well-defined subsumption rule.
3) Cross-module resolution must be deterministic:
   - the set of visible impls is determined by explicit imports/modules,
   - no runtime discovery, no reflection.

Rolling v0 enforcement (implemented):

- **Single impl block rule:** there must be exactly one `impl Trait for Type { ... }` block per `(Trait, Type)`.
  - Splitting methods across multiple impl blocks is rejected deterministically.
- **Blanket impl:** `impl Trait for any { ... }` is allowed as a catch-all.
  - Exact `impl Trait for SomeType` overrides the `any` blanket.

### 6.1 Practical staged enforcement (no big rewrite)

- v0/v0.5: keep current explicit `impl Trait for Type` lowering + method-sugar registry.
  - if multiple impls collide on the same `Type.method` name, error (already implemented).
- v1: add an *optional explicit qualification syntax* for ambiguity resolution.
  - example direction: `Trait.method(x, ...)` or `Type::Trait::method(x, ...)` (syntax TBD).
- v1+: introduce blanket impls with a strict overlap checker.

This staging keeps Oren **powerful** while maintaining a **solid foundation**.

## 5) Bootstrap reality (v0 rolling)

Current implementation status:

- `trait` and `impl` syntax exists and is accepted by the parser.
- `impl` is lowered deterministically into top-level functions (bootstrap strategy).
- No runtime trait objects exist yet.

See also:

- `docs/LANGUAGE_APPENDICES.md`
- `docs/LANGUAGE_SPEC.md`

## Reflection v1 (Plan, Rolling)

Oren is still in rolling mode with a v0 dynamic runtime surface, but multiple active tracks now require
**real, stable reflection**:

- **FFI** and syscall-first I/O: stable type/ABI boundaries (`@abi`, `@pack`, typed buffers, endian types).
- **Varargs and generic utilities**: formatting/logging needs to safely inspect “what is inside the rest-list”.
- **Serde** (binary formats, config): schema-driven encode/decode and versioning.
- **Tooling**: docs generation, IDE indexers, linting.

Today, Oren already emits a rich metadata graph (attributes are compile-time metadata, not runtime decorators).
Reflection v1 is the plan to turn that metadata into a **stable, queryable runtime surface** that works across:

- native backends (`arm64-*`, `x64-*`)
- C backend (bootstrap + portability)
- AVM bytecode (`.obc`)

This doc is a design plan; it is not claiming the full surface is implemented yet.

## 0.5) Current rolling v0 (implemented)

As an immediate, low-risk step toward reflection v1, the compiler now tags struct/type-constructor values
with a reserved map key (2026-01-10):

- Struct values are still **map-shaped** in v0 across backends (native, C backend, AVM bytecode):
  - `struct User { id, name }`
  - `User(1, "a")` lowers to: `{"__oren_type":"User","id":1,"name":"a"}`
- The reserved key is **`"__oren_type"`**.
  - User code may not declare a field named `__oren_type` (parser rejects it).
- `oren_type_name(v)` (native + C backend) checks for `__oren_type` when `v` is a map:
  - returns `"User"` for `User(...)`
  - still returns `"map"` for ordinary map literals without the tag.

In addition, the stdlib now exposes a minimal wrapper module:

- `lib/std/reflect.oren` (`std:reflect` in spirit; import path is still rolling)
  - `tag(v)` / `name(v)` wrappers (call through to `oren_type_tag` / `oren_type_name`)
  - stable tag constants (`TAG_NIL`, `TAG_STRING`, `TAG_LIST`, `TAG_FUNC`, …) matching `lib/runtime.h` `OrenType`
    - 2026-01-12: native backend now tags first-class function values as `TAG_FUNC` (guarded by `tests/native/test_quick_integration_native.oren`).
    - 2026-01-13: Tier‑1 native smoke now asserts the non-numeric tag/name contract under real x64 hosts:
      - `tests/fixtures/tier1_native_smoke_main.oren` checks `tag/name` for `nil/bool/int/string/func/list/map/u8_buf`
      - also checks that struct values expose a stable type name via `__oren_type` (even though structs remain map-shaped in v0)

This is intentionally **not** the final reflection design:

- it does not provide a stable `TypeId`
- it does not expose fields/attributes at runtime
- it is a pragmatic v0 affordance to make varargs/logging safer and more informative while the full
  type system and tagged value model are still converging.

## 0) Non-goals (keep scope bounded)

- No compile-time macros / arbitrary code execution in the compiler.
- No “full dependent typing”.
- No runtime `eval`.
- No promise of a final “v2” type system here; this is the minimum reflection layer needed for production stdlib.

## 1) Requirements (what reflection must answer)

Reflection v1 must provide enough information to implement the following *portably* (with the same source file):

1) **Value-level type identification**
   - “Given a runtime value `v`, what is its type?”
   - Must distinguish at least: `nil`, `bool`, `int`, `string`, `list`, `map`, typed buffers (`[]u8`, `[]i32`, …),
     and user-defined `struct` types.

2) **Type descriptor lookup**
   - “Given a `TypeId`, what is the type’s name, module path, and (for structs) fields?”
   - Must provide enough to implement:
     - `to_string` / formatting
     - generic JSON-ish debug printers
     - schema/serde for structs

3) **Field introspection (structs only, v1)**
   - Field name list
   - Field order (stable)
   - Field type ids
   - Optional: per-field attributes (`@doc`, `@serde.*`, `@pack`, `@abi`, …)

4) **Backend portability**
   - The same program should observe the same reflection results under:
     - C backend (stage0/stage1 bootstrap)
     - native backend
     - AVM bytecode
   - Implementation detail differences (value representation, pointer tagging, object layout) must not leak into the reflection API.

## 2) Constraints (what makes this hard in Oren)

Oren v0 is still in rolling mode without a full static type checker, and backends currently use different internal
value representations to get performance and bring-up velocity.

Relevant existing docs:

- Dynamic value representation work: `docs/BACKENDS.md#native-tagged-value-representation`
- Object model direction: `docs/LANGUAGE_APPENDICES.md`
- Type-system stabilization direction: `docs/STATUS_AND_ROADMAP.md`
- Attribute contract: `docs/LANGUAGE_APPENDICES.md`

Key constraints for reflection v1:

- **Performance:** reflection must not require 64-byte “fat values” everywhere.
  - Reflection data should be **out-of-line** (tables) and referenced by compact ids.
- **Determinism:** type ids must be stable and reproducible for a build (and ideally across builds when source is unchanged).
- **Cross-arch:** layout/ABI facts must be expressible without assuming one CPU ABI.

## 3) Proposed architecture (two layers)

Reflection v1 is split into two layers:

### 3.1 Compile-time metadata (already exists; formalize as a contract)

The compiler already canonicalizes attributes into deterministic metadata (example: `@cfg(...)` → `@oren.cfg(...)`).

Action for reflection:

- define a single “reflection metadata table” schema as a **compiler output contract**
  - minimal stable types (string, int, bool, list, map)
  - stable keys for common attributes

This table exists even if the program never calls `std:reflect`.

### 3.2 Runtime reflection API (`std:reflect`)

Expose a stable runtime-facing API that reads from the compiled metadata table:

- `type_id_of(v) -> u64`
- `type_info(id) -> TypeInfo`
- `fields_of(id) -> []FieldInfo` (only for structs in v1)

Important: the runtime API must hide how `v` is represented (tagged pointers, boxed objects, etc.).

## 4) Type identity (TypeId)

Introduce `TypeId` as a compact stable identifier:

- width: `u64` (portable across Tier‑1, easy to store in buffers and metadata)
- meaning: identifies a *type descriptor entry* in a per-program type table

Two design choices:

1) **Build-stable ids (recommended for v1)**
   - `TypeId = hash(module_path, type_name, shape_signature, abi_signature, compiler_version_tag)`
   - Pros: can be stable across builds if inputs are stable.
   - Cons: requires careful definition of the hashed inputs.

2) **Index-based ids**
   - `TypeId = index in type table`
   - Pros: simplest.
   - Cons: unstable under unrelated source edits; painful for caches and tooling.

Rolling recommendation: use build-stable hash ids for user-defined types and reserved fixed ids for builtins.

## 5) Minimum “type descriptor” schema

Define `TypeInfo` and `FieldInfo` (conceptual):

- `TypeInfo`:
  - `id: u64`
  - `kind: string` (example: `"nil"`, `"bool"`, `"int"`, `"string"`, `"list"`, `"map"`, `"buf"`, `"struct"`)
  - `name: string` (for structs and named builtins)
  - `module: string` (for structs)
  - `attrs: map` (optional; contains canonicalized `@oren.*` metadata)

- `FieldInfo`:
  - `name: string`
  - `type_id: u64`
  - `index: int` (stable order)
  - `attrs: map` (optional)

For v1, field offsets and sizes are intentionally out of scope unless `@abi` is present and the backend can
guarantee layout stability for the target ABI.

## 6) How this connects to varargs and “rest lists”

In Oren today, varargs calls are lowered by packing the “rest” arguments into a list.

Without reflection, generic utilities (like debug printers, structured logging, `printf`-style formatters)
can only treat rest elements as opaque “dynamic values”.

With reflection v1:

- the stdlib can implement `debug_any(v)` by switching on `type_info(type_id_of(v)).kind`
- `format("%v", v)` can become deterministic across backends
- varargs processing no longer depends on backend-specific heuristics (for example “is this pointer tagged?”)

## 7) Work plan (incremental, production-oriented)

### Phase A — lock the metadata contract (compiler-only)

- Define the reflection type table schema in docs (and enforce deterministic ordering).
- Ensure metadata is emitted consistently across backends (C/native/AVM).
- Add a tiny fixture that compiles under all backends and asserts a stable set of metadata keys exist.

### Phase B — add `std:reflect` and `TypeId` (runtime + stdlib)

- Implement `type_id_of(v)` for v0 dynamic values (native + C + AVM).
- Implement `type_info(id)` by looking up the compiled type table.

### Phase C — struct fields (first-class reflection)

- Emit field lists for `struct` declarations (name + type id + index).
- Implement `fields_of(id)` and add fixtures for “serde-like” traversal.

### Phase D — start consuming reflection in stdlib

- Update varargs utilities (logging/formatting) to use reflection rather than ad-hoc checks.
- Make “rest list element processing” portable and deterministic.

### Phase E — future: ABI-aware reflection (optional)

Once `@abi` structs have a stable per-target layout contract, reflection can optionally expose:

- field offsets
- field sizes
- total struct size

This is needed for safe “memcpy style” FFI tooling, but it must not leak into v1 prematurely.

## 8) Related work (tracked elsewhere)

- Value representation refactor targets: `docs/BACKENDS.md#native-tagged-value-representation`
- Type-system stabilization targets: `docs/STATUS_AND_ROADMAP.md`
- Stdlibrary layering (crypto/net split): `docs/STDLIB_AND_RUNTIME.md`

## Oren Object Model (Traits/Protocols + Composition)

**Status:** Draft (rolling)  
**Goal:** a modern, AI/agentic-friendly model that stays syscall-first and multiverse/AVM compatible.

This document defines the recommended object model for Oren:

- **Traits / protocols** for behavior
- **Composition** for code reuse
- **No inheritance-first design**
- **Sum types (ADTs)** for state machines (planned)

It is intentionally aligned with:

- syscall-first native runtime (no libc/pthreads shims)
- AVM determinism + multiverse execution (policy scan, replay, snapshot)

## 1) Principles (what we optimize for)

1) **Governability**
   - Effects (FS/NET/PROC/ENV/TIME) must be explicit and auditable.
2) **Determinism and replayability**
   - Especially for AVM: semantics must not depend on host clocks/schedulers.
3) **Toolability**
   - Disasm/debug/profiling should be able to attribute behavior and cost.
4) **No huge rewrites**
   - Prefer staged evolution; keep v0 bootstrapping possible.

## 2) Data vs behavior

Oren should treat these separately:

- **Data:** `struct` (and later `enum`) — stable shapes, predictable layout/encoding.
- **Behavior:** `trait` — capability/behavior contracts that types can implement.

This mirrors successful systems-language patterns (Rust/Swift/Go-like protocols) and avoids fragile class hierarchies.

## 3) Traits / protocols

A trait defines required functions (methods). Conceptually:

```oren
trait Reader {
    fn read(self, n)
}
```

### Primitives implementing traits (recommended: YES)

Oren should allow **all runtime value kinds**, including primitives, to implement traits:

- integers / floats
- strings / bytes
- lists / maps
- function values / closures
- user-defined structs/enums

Why this matters:

- it keeps the stdlib clean: `to_string(x)` / `hash(x)` / `iter(x)` are uniform
- it avoids special-casing primitives in the compiler and tooling
- it aligns with “protocols + composition” rather than “primitive exceptions”

Determinism note:

- “implements trait” is a **compile-time relation**. It must not depend on host state.
- method resolution must be deterministic given the program and its imports (no reflection-based late binding by default).

Example direction:

```oren
trait ToString { fn to_string(self) }

impl ToString for i64 { fn to_string(self) { return oren_int_to_string(self) } }
impl ToString for string { fn to_string(self) { return self } }
```

### Dispatch policy (recommended)

- Default: **static dispatch** (monomorphize / direct call) where types are known.
- Optional: **dynamic dispatch** via “trait objects” only when needed.

This keeps native performance good and keeps AVM semantics clear.

### Structural vs nominal conformance (rolling decision)

For Oren’s goals (auditable codegen, deterministic replay, self-hosting), prefer:

- **nominal conformance** as the default: `impl Trait for Type` is explicit
- optional **structural conformance** only as a later, opt-in feature (tooling-heavy; easy to make “too magic”)

Nominal `impl` keeps “what code runs” stable and obvious, which matters for consensus-like workflows.

## 4) Composition (preferred reuse mechanism)

Instead of inheritance, reuse behavior and data via:

- embedding fields (has-a)
- forwarding functions
- small traits composed together

Example idea:

```oren
struct TcpConn { fd }
struct BufferedReader { inner, buf }
```

This is more SOLID-aligned than inheritance:

- interfaces (traits) stay small
- data ownership is explicit

## 5) Capabilities as traits (syscall-first + AVM governance)

The most important use of traits in Oren is the OS boundary:

- FS
- NET
- PROC
- ENV
- TIME

Design direction:

- stdlib APIs should accept explicit capability objects (implementing these traits)
- AVM can inject VirtualFS/VirtualNET/VirtualPROC implementations
- native runtime can provide Host* implementations via syscall-first `sys_*`

This prevents “hidden host effects” and composes with nested universes.

## 6) Deterministic dispatch + trait objects

Static-first: prefer compile-time dispatch; use explicit trait objects only when required.

- `trait` is compile-time by default (no runtime rep).
- `dyn Trait` (syntax TBD) introduces a runtime representation `{value, vtable_id}` and must be capability/determinism-governed.
- In consensus jobs, trait objects should be callable but not comparable/hashable unless a stable semantics is defined.
Traits must not re-introduce nondeterminism.

Recommended rules:

1) Static dispatch is pure: calling `T.foo(x)` must be the same across machines.
2) Dynamic dispatch is explicit:
   - “trait object” must be a distinct runtime representation (e.g. `{ v, vtable_id }`), not implicit reflection.
3) VTable identity must be stable:
   - derived from module path + trait name + impl symbol set, not host pointers
4) Cross-universe safety:
   - passing trait objects between universes must preserve semantics or be disallowed by policy.

## 7) Sum types (ADTs) + pattern matching (planned)

For agentic workflows, “closed world” state modeling matters more than class hierarchies.

Example direction:

```oren
enum State {
    Idle
    Running(job)
    Waiting(deadline_ms)
    Failed(err)
}
```

Then:

- `match state { ... }` ensures explicit handling
- later, exhaustiveness checking makes self-healing logic safer

## 8) Implementation reality today (bootstrap)

Current state in this repo:

- `struct`/`class` exist and are represented as runtime maps keyed by strings.
- no user-defined methods, no trait syntax yet
- concurrency primitives are in flux; avoid baking in inheritance assumptions

So this document is the **direction**: it guides evolution without forcing an immediate rewrite.

## 9) Staged implementation plan (minimal rewrite)

A key ergonomics requirement is avoiding per-type boilerplate for primitives and containers.
Oren should eventually support **blanket impls / generic impl templates** plus **trait default methods** and **derive-style expansion** (attribute-driven)
so most behavior can be implemented once and applied to many types deterministically.

1) Add `trait` declarations as compile-time contracts (doc + parser support first).
2) Add `impl Trait for Type` with static dispatch for:
   - core runtime types (string/list/map/int/float) first
   - then user-defined structs/enums
3) Add “trait objects” (explicit opt-in) only when needed (plugins / heterogeneous containers).
4) Add derive-style expansion via attributes (`@oren.derive(...)`) to reduce boilerplate.
5) Add a stabilized v1 type system pass (optional) once the core bootstrapping story is complete.

## Appendix: v0 lowering convention for `impl` (current implementation)

In v0 (rolling), `impl` blocks are lowered by the parser into plain top-level functions, so backends remain unchanged.

Convention:
- `impl Trait for Type { fn method(self, ...) { ... } }` lowers to:
  - `fn __oren_impl__Trait__Type__method(self, ...) { ... }`
- Dots in `Trait`/`Type` names are replaced by underscores in the lowered symbol name.

This is a temporary bootstrap mechanism until a stabilized trait dispatch model (static-first, optional trait objects) is implemented.

## Memory Model

**Last updated:** 2026-01-16

Oren’s native backend is **syscall-first** and **libc-free**. Memory management is designed so long-running programs do not grow memory unboundedly (no “leak by design”), while still supporting a deterministic/manual lane.

This doc is rolling: it records what the code does today and the constraints that fall out of that.

## Modes
- **Auto-managed (default)**: allocations are tracked and reclaimed via a conservative mark/sweep collector (`native_gc_collect()`).
- **Deterministic/Manual**: set `--no-gc` / `OREN_NO_GC=1` to disable GC scanning/collection. You still can explicitly release memory via `free(ptr)` (returns blocks to the reuse pool). This is the intended path for targets where pauses aren’t acceptable.

## What is managed
- In the native backend, heap allocations are performed by the compiler’s intrinsic `malloc(...)`, implemented directly on top of OS syscalls (not `libc malloc`).
- Runtime objects (strings/lists/maps/structs/function-closures) are tracked by the native runtime so GC can traverse container graphs and reuse freed blocks.
- **Runtime metadata** (globals storage, thread-list nodes, root-list nodes) is allocated with `malloc_raw(...)` so it is not subject to GC (prevents GC from reclaiming internal runtime bookkeeping).

Rolling detail (native GC correctness):

- Struct allocations tagged as kind=STRUCT are scanned **conservatively**:
  - every 8-byte slot in the allocation payload is treated as a potential pointer and marked if it refers to a tracked allocation
  - there is no type descriptor yet, so this is correctness-first (it can visit many non-pointers, but they fast-skip via alloc-index miss)
- The mark phase honors the mark bit to avoid infinite recursion on cyclic container graphs.

## Roots & collection
- The collector is cooperative: call `native_gc_collect()` at safe points to reclaim unreachable tracked allocations.
- Roots are for “stable address” slots used by the runtime/compiler; user code should not normally need to manipulate roots directly in v0.
- Result selection (`oren_set_result`) pins the selected value as a GC root in native, mirroring the C backend “tooling surface” contract.

## Disabling GC
- Builds can disable GC scanning by defining `OREN_NO_GC` (or passing `--no-gc` to the CLI). Stack scanning and mark/sweep become no-ops.
- Manual reclamation still works: `free(ptr)` removes the allocation from the tracked set and returns it to the reuse pool (so long-running programs can stay bounded even with GC disabled).

## Thread Safety
### C backend

- List/map operations in the C runtime take a coarse mutex, so concurrent reads/writes across threads are serialized.

### Native backend (important nuance)

Today, the native backend supports a **shared-address-space** concurrency substrate on POSIX via
**green tasks** (single OS thread, cooperative scheduling):

- Default (rolling): `spawn` on macOS/Linux prefers **in-process green tasks** (shared heap, no `fork`).
  - Escape hatch: set `OREN_NO_GREEN=1` to force the legacy **fork+pipe** path.
- In green-task mode, all tasks share one heap in one process:
  - this avoids the “locks don’t synchronize after fork” trap
  - it is required groundwork for a real OS-thread scheduler and a thread-safe GC story

Important remaining nuance:

- Green tasks today are **N:1** (one OS thread), so they do not introduce parallel data races yet.
- The runtime is still evolving toward **true OS threads** + **M:N scheduling**; once multiple OS threads
  exist, GC, allocator metadata, and shared runtime structures must be made concurrency-correct.

Rolling status (fact):

- macOS now has a **syscall-first OS-thread substrate** (bsdthread_register + bsdthread_create/terminate) as groundwork for Stage N2,
  but it is **not** the default `spawn` path yet (language `spawn` still defaults to green tasks unless explicitly overridden).
  - Darwin substrate: `lib/runtime_native/264_darwin_os_threads.oren`
  - Shared scheduler-facing OS-thread (“M”) abstraction: `lib/runtime_native/269_os_thread_m.oren`
- Linux now has a **syscall-first OS-thread substrate** (clone wrapper + futex join) as groundwork for Stage N2,
  but it is **not** the default `spawn` path yet (language `spawn` still defaults to green tasks unless explicitly overridden).
  - Linux clone(2) substrate: `lib/runtime_native/266_linux_os_threads.oren`
  - Shared scheduler-facing OS-thread (“M”) abstraction: `lib/runtime_native/269_os_thread_m.oren`
- 2026-01-15: the native runtime gained a minimal **stop-the-world GC safepoint protocol** so manual collection is no longer “single-thread only”:
  - Collector: `oren_gc_collect()` requests STW, runs `native_gc_collect()`, then releases.
  - Mutators: `oren_gc_safepoint()` checks the STW state and **parks** the OS thread when requested.
  - GC stack scanning uses the thread node’s `saved_sp` field to scan parked threads safely.
  - Current-thread stack selection for **OS threads** uses `sys_gettid()` identity (not an SP/top heuristic), avoiding adjacent-stack misidentification crashes.
  - Guard: `tests/native/test_gc_stw_os_thread_collect.oren` (object reachable only from parked thread’s stack must survive).
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_deadlock_with_os_thread_join_waiter`) (STW GC must not deadlock while another OS thread is blocked in `oren_os_thread_join_timeout(..., timeout_us=0)`).
  - Guard: `tests/native/test_quick_integration_native.oren` (`test_gc_collect_does_not_wait_for_exited_os_threads_win`) (Windows: exited OS threads must be marked DEAD on exit so STW does not wait for them).
  - Rolling constraint: any runtime path that can block in a kernel wait must either be bounded or poll `oren_gc_safepoint()` periodically, otherwise STW can deadlock.

Practical consequence:

- As soon as true OS threads are introduced, runtime bookkeeping allocations that were “safe enough” under single-threaded execution
  must be made thread-safe (or moved to syscall-first allocations). For example, the native thread registration list node is allocated
  via `mmap` so it does not depend on any allocator-internal locks that are not yet OS-thread safe.

This is one reason OS-thread + scheduler work (and a coherent thread-safe GC model) is considered P0 for scaling compilation and agentic workloads.

## Limitations & next steps
- Native backend participates in the same *tracked-heap + mark/sweep* approach as the C backend:
  - allocations are registered in a tracking list
  - collection is conservative (stack scan + optional registered roots)
  - collection is explicit today (`native_gc_collect()`), and higher-level safepoints can be added later
- The deterministic/manual lane is available on native too:
  - compile with `--no-gc` to make GC scanning/collection a no-op by default
  - runtime override: `OREN_NO_GC=1` disables scanning/collection (useful for production rollouts)
- Collection locking is coarse today; per-object locking or lock-free structures plus a concurrency-compatible GC/safepoint story are still needed.
- The collector is stop-the-world and can be invoked manually today; in multi-threaded programs it currently relies on **cooperative safepoints**
  (threads must reach `oren_gc_safepoint()` in bounded time). Automatic triggers exist in limited form and still default to single-OS-thread mode.

## Oren Concurrency & IPC Model (Rolling)

This doc describes:

- what exists today (facts, grounded in code), and
- what the intended direction is (design, tracked in `docs/TODOS.md`).

Oren is rolling; compatibility is not the priority. Accuracy is.

**Last updated:** 2026-01-17

## 1) Core primitives (current reality)

### 1. `spawn` + `join` (today: platform-specific substrate)

`spawn` exists in the language surface today, but it is **not yet** a unified “lightweight task” abstraction.

Current native backend behavior (rolling, fact):

- **macOS/Linux (POSIX v0 → Stage N1):** `spawn` prefers **in-process green tasks** (**N:1**, one OS thread).
  - This is shared-address-space concurrency (required groundwork for any coherent GC/locks story).
  - Escape hatch: set `OREN_NO_GREEN=1` to force the legacy **fork + pipe** fallback.
  - Fork+pipe semantics (fallback):
    - the child computes the return value, writes 8 bytes to the pipe, and exits
    - the parent joins by reading those 8 bytes and reaping the child
    - STW GC safety (rolling, 2026-01-17): POSIX fork+pipe `join/join_timeout` is **poll + safepoint** based (no infinite kernel blocking)
      so stop-the-world collectors on other OS threads cannot deadlock waiting for a joining host thread to reach a safepoint.
- **Windows x64 Tier‑1:** `spawn` prefers **in-process green tasks** (**N:1**, one OS thread), same as POSIX.
  - Escape hatch: `OREN_NO_GREEN=1` disables green tasks; Windows then falls back to a runtime-owned OS-thread spawn (CreateThread).
  - Join handles are either:
    - a green-task pointer (preferred; `oren_green_is_g(handle)`), or
    - an OS-thread join handle (fallback; wraps a Win32 HANDLE + result pointer).

Additional substrate (not wired into `spawn` yet):

- **Linux syscall-first OS threads:** a minimal clone(2) wrapper + CLONE_CHILD_CLEARTID join exists as Stage N2 groundwork
  (see `lib/runtime_native/266_linux_os_threads.oren`). This will be used by the upcoming N:M scheduler, not by v0 `spawn`.
- **Green-task background workers (Stage N2 groundwork):** the green scheduler can optionally run on background OS threads via:
  - `oren_green_start_workers(n)` (runtime: `lib/runtime_native/263_green_tasks.oren`)
  - This is not a full GMP/netpoller yet (no true async IO), but it is the “M” substrate needed to move beyond N:1.
  - Guardrail (rolling): `oren_green_start_workers` must be called from a host thread (not while executing a green task), otherwise it returns `-1`.
  - Rolling Stage N3 plumbing: `P` count is now configurable before workers start:
    - `oren_green_set_p_count(n)` grows scheduler `P` objects (no shrink; rejected once workers started).
    - `oren_green_p_count()` reports the current `P` count.
    - `oren_green_bind_p(p_id)` re-binds the current OS thread to a specific `P` (bring-up/testing; rejected in-green and once workers started).
    - `oren_green_current_p_id()` reports the current thread’s bound `P` id (diagnostic/fixtures).
    - Low-level host-thread scheduler drive hooks (bring-up/tests; rejected once workers started):
      - `oren_green_poll_until(deadline_ns)` drives the scheduler until idle or deadline.
      - `oren_green_poll_steps(n)` drives at most `n` context switches (used for deterministic fixtures).

### 1.2 Wait-on-address (`sys_ulock_wait/sys_ulock_wake`) (portable lock/park substrate)

The native runtime treats `sys_ulock_wait` / `sys_ulock_wake` as a *portable* “wait on memory address” primitive.

Facts (rolling, verified by tests):

- **macOS:** lowers to the ulock syscalls (`ulock_wait` / `ulock_wake`).
- **Linux:** lowers to `futex(FUTEX_WAIT_PRIVATE/FUTEX_WAKE_PRIVATE)`.
  - Timeout behavior is normalized to Oren’s portable `-60` timeout code (Darwin ETIMEDOUT),
    even though Linux futex uses `-ETIMEDOUT` (`-110`) as the raw errno.
- **Windows:** lowers to `WaitOnAddress` / `WakeByAddressAll` (KERNELBASE import).
- **Oren-level semantics (portable API):** `oren_wait_on_addr(addr, expected, timeout_us)` is “wait while equal”.
  - If `*addr != expected`, it returns `0` immediately (no blocking).
  - If the underlying primitive reports a value mismatch/spurious wake (e.g. Linux futex `-EAGAIN`), it is normalized to `0`
    because callers are structured as “check → wait → retry”.
  - Green-task nuance (rolling, 2026-01-17): when called from inside a green task, the runtime must not kernel-block the scheduler OS thread
    in the wait-on-address primitive (either forever or with bounded timeout).
    - Current implementation: parks the current `G` on a scheduler-owned “word wait” list and wakes it via `oren_wake_all_addr(addr)`
      (wake-driven; no polling; timeouts return portable `-60`).
    - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_in_green_does_not_block_scheduler`)
    - Guard: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_timeout_in_green_does_not_block_scheduler`)

Why this matters:

- This is the basic building block for:
  - parking/unparking idle scheduler threads (`M`), and
  - non-busy-wait locks in a libc-free runtime.

Source of truth / guards:

- Runtime wrapper (portable API): `lib/runtime_native/267_wait_on_addr.oren` (`oren_wait_on_addr`, `oren_wake_all_addr`)
- OS-thread (M) substrate uses the wait-on-address primitive for parking (no busy spin):
  - `lib/runtime_native/269_os_thread_m.oren` (`oren_m_park_word_wait`, `oren_m_park_word_wake`, `oren_os_thread_spawn`, `oren_os_thread_join_timeout`)
- Portable timeout smoke: `tests/native/test_ulock_timeout_portable.oren` (expects `-60`, skips `-38`/ENOSYS)
- Linux timeout normalization smoke: `tests/native/test_ulock_timeout_linux.oren` (skips on non-Linux; asserts `-110` normalizes to `-60`)
- OS-thread substrate smokes:
  - `tests/native/test_os_thread_park_unpark_smoke.oren` (macOS/Linux/Windows; park/unpark + bounded join)
  - `tests/native/test_os_thread_spawn_many_smoke.oren` (macOS/Linux/Windows; spawn/join-many bounded stress)
- Tier-1 lock handshake: `tests/fixtures/tier1_native_spawn_join_main.oren`
  - Quick integration regression: `tests/native/test_quick_integration_native.oren` (`test_wait_on_addr_mismatch_is_success`)

Implementation guardrails (native backend contributors):

- The native runtime “rtobj” cache stores compiled machine code for the injected runtime. If native codegen changes (ABI layout,
  syscall lowering, instruction encoding), bump the backend signature in `lib/compiler/native_runtime_obj_cache.oren` or you can
  accidentally keep old runtime machine code alive on cache hits.
- Linux/aarch64 syscall ABI nuance: raw `clone(2)` argument order is `clone(flags, stack, ptid, tls, ctid)` (TLS and ctid are swapped
  vs x64 conventions). `sys_thread_create` lowering must follow that when using `CLONE_*TID` flags.

Implications:

- There is no **production-grade** GMP/netpoller (true async IO + channels/select across Tier‑1) in native yet.
  - However, macOS/Linux already have an early green-task scheduler + netpoll integration for pipe/socket readiness (rolling; see `docs/STDLIB_AND_RUNTIME.md`).
  - Windows has a correctness-first in-memory channel implementation so `oren_select` works for channels even without IOCP (see `docs/NETWORKING_IO.md`).
  - Windows also has a rolling v0 socket netpoll path (WinSock `select()` over a small watched set) so green-task `oren_fd_wait_*` can be scheduler-driven, but IOCP is still the intended long-term implementation.
- A “mutex” cannot coordinate across `spawn` on POSIX v0, because forked processes do not share the address space.

Source of truth:

- POSIX fork+pipe join handle: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`
- Windows CreateThread path: `lib/runtime_native/120_first_class_fn.oren`, `lib/runtime_native/260_threads.oren`

### 1.3 Stop-the-world GC safepoints (native runtime; minimal Tier‑1 protocol)

Oren’s native runtime GC is a conservative mark/sweep collector. Once more than one OS thread exists, stack scanning
must be coordinated or the collector can miss live references.

Current native behavior (rolling, fact):

- `oren_gc_collect()` uses a minimal **stop-the-world at safepoints** protocol:
  - collector thread requests STW, waits for other OS threads to park, scans stacks, then resumes the world
  - parked OS threads publish a `saved_sp` so the collector can scan their stacks safely
- Safepoints are **cooperative** today:
  - compiler backends insert throttled `oren_gc_safepoint()` polling in loop headers
  - long-running non-loop code remains a limitation until a stronger/preemptive scheme exists
- To keep STW bounded even when threads are blocked in kernel readiness waits:
  - STW begin/end call `native_netpoll_wake()` so OS threads blocked in kevent/epoll/select are broken out and can observe STW

Source of truth / guards:

- Runtime: `lib/runtime_native/100_time_gc_stw.oren` (`native_gc_stw_begin/native_gc_stw_poll_and_park/native_gc_stw_end`)
- Guards:
  - `tests/native/test_gc_stw_os_thread_collect.oren` (standalone smoke; stack scanning on parked thread)
  - `tests/native/test_quick_integration_native.oren` (`test_gc_stw_os_thread_collect_scans_parked_stack`)
  - `tests/native/test_quick_integration_native.oren` (`test_gc_stw_wakes_netpoll_blocked_threads`)

### 1.1 `oren_yield()` (rolling: green-yield when available; OS yield otherwise)

`oren_yield()` is the best-effort “yield” surface used by both:

- the Stage N1 green-task runtime (as a cooperative scheduler yield), and
- non-green paths (as a best-effort OS yield hint).

Current behavior (native runtime, rolling):

- If green tasks are enabled: `oren_yield()` routes to `oren_green_yield()` (scheduler yield).
- Otherwise:
  - **Linux:** calls `sched_yield(2)` via syscall-first `sys_sched_yield()`.
  - **Windows:** calls `Sleep(0)` via `sys_sched_yield()` shim.
  - **macOS:** currently a best-effort `sys_sched_yield()` (no-op on older bring-up paths).

Source of truth:

- `lib/runtime_native/262_yield.oren`
- Linux syscall numbers are repo-owned in `docs/refs/linux_*` and wired via `lib/compiler/*_abi_linux.oren`.

### 2. Channels + `oren_select` (today: data-driven, backend-shared)

Channels exist today, but their implementation is currently a bring-up substrate:

- Native channels are platform-dependent today (rolling):
  - **macOS/Linux:** pipe pairs `[rfd, wfd]` (`oren_new_channel()` returns a list)
  - **Windows:** in-memory channels (a GC-tracked struct; `oren_new_channel()` returns a pointer)
- AVM has proper channels as VM objects.
- `oren_select_recv` / `oren_select` exist as **functions** (not syntax) and have a shared encoding across AVM and native.

Source of truth:

- Native: `lib/runtime_native/010_channels_globals_consts.oren`, `lib/runtime_native/011_channels_mem.oren`, `lib/runtime_native/245_select.oren`
- AVM: `lib/avm/avm_vm.c` opcodes `SELECT_RECV` / `SELECT`
- Docs: `docs/NETWORKING_IO.md`

### 3. Atomics (native)

Atomics exist as native intrinsics and are the right “foundation layer” for future shared-memory concurrency:

- `atomic_add`
- `atomic_cas`

These are necessary (but not sufficient) for:

- a real native thread scheduler
- mutex/condvar/channel implementations that do not require host libc

## 2) Synchronization primitives (what is *not* true yet)

The following are *design goals* but are not implemented today as stable primitives:

- “green threads” / coroutines
- a portable, shared-memory `mutex`/`lock` that works across macOS/Linux/Windows without libc
- structured concurrency (`task_group`, cancellation propagation)
- pub/sub or multicast channels
- data-parallel iterators (`par_map`, `par_reduce`)

## 3) Roadmap (high-level)

Implementation plan is tracked in `docs/TODOS.md` and the deeper design docs:

- `docs/STDLIB_AND_RUNTIME.md`
- `docs/NETWORKING_IO.md`
- `docs/AVM_ROADMAP.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`

## 4) AVM notes

For AVM execution (interpreter-only environments), concurrency primitives must:

- support cancellation/timeouts (to stop work when a better plan exists)
- be compatible with snapshot/restore (pause and resume tasks)
- be compatible with capability gating (NET/PROC may be disabled)

See:

- `docs/AVM_ROADMAP.md` (Next-Gen plan section)
- `docs/STATUS_AND_ROADMAP.md`

## Stack Safety (Recursion, Call Depth, and Deterministic Failure)

Oren targets **Tier‑1** `arm64` and `x86_64` on **macOS / Linux / Windows** with consistent
semantics across:

- native backend (Mach‑O/ELF/PE),
- C backend,
- bytecode backend + AVM.

Stack safety is part of that contract: programs must fail **deterministically** when they
exceed a configured budget, rather than crashing the host process with an OS stack overflow.

This document describes:

1) what exists today (facts),
2) what “stack safe” means for Oren,
3) the staged plan to make native/C match AVM behavior.

## Current State (Facts)

### AVM

AVM enforces a **call depth limit**:

- configured via `AVM_CALL_DEPTH_MAX` or `--call-depth-max`
- exercised by:
  - `tests/avm/test_call_depth_limit.oren`
  - `tests/avm/test_call_stack_discipline.oren`

This prevents recursion from consuming unbounded host stack (AVM is an interpreter with its
own call stack model).

### Native + C backends

Native and C binaries execute on the host’s call stack.

Today, both backends have a **deterministic recursion guard** (rolling):

- **C backend**
  - runtime implements `oren_call_depth_enter/exit()` with a per-thread counter + max
  - configured via env: `OREN_CALL_DEPTH_MAX` (default 8192; `0` disables the guard)
  - validated by `tests/native/fixtures/call_depth_overflow.oren` (compile+run under both backends)

- **Native backend (arm64 + x86_64)**
  - compiler inserts `oren_call_depth_enter()` on user-function entry and `oren_call_depth_exit()` on return
    (injected native runtime sources are intentionally excluded to keep bootstrap stable and low-overhead)
  - configured via env: `OREN_CALL_DEPTH_MAX` (default 8192; `0` disables the guard)
  - validated by the same fixture under `--backend native`
  - call depth is tracked per-thread via the registered native thread nodes (rolling v0:
    thread selection is based on the same SP-vs-top heuristic used by the GC stack scanner)

Practical note:

- Many Tier‑1 Linux environments (including WSL2) have a default `ulimit -s` of **8 MiB**.
  The call-depth hooks must stay extremely lightweight, and the compiler must never instrument
  the injected runtime itself with those hooks (or it can cause stack blowups during bootstrap).
- If you change native call-depth instrumentation rules (or other native codegen that affects the
  injected runtime), you must bump the rtobj backend signature in
  `lib/compiler/native_runtime_obj_cache.oren` so stale cached runtime objects are not reused.
  For debugging you can also force a “no rtobj” build by setting `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`.

## What “Stack Safe” Means for Oren

For production maturity, we want:

1) **Deterministic failure mode**
   - Exceeding the configured call depth should produce a stable, machine-readable
     diagnostic (consistent with the `OREN_DIAG` contracts used elsewhere).

2) **Backend parity**
   - The same program + same call-depth budget should behave the same on:
     - AVM (bytecode),
     - C backend,
     - native backend (arm64/x64).

3) **Low overhead by default**
   - The default configuration should be safe for development, but production builds should
     be able to choose a budget appropriate to their service.

3b) **Stackless when possible**
   - Direct **tail recursion** should compile to a loop (no host stack growth).
   - This is both a correctness feature (avoid OS stack overflow) and a performance feature
     (avoid call/ret overhead and repeated prologues).

4) **No secrets / no “security theater”**
   - Stack safety is about correctness and reliability (preventing host crashes),
     not anti-tamper.

## Design Options

### Option A — Compiler-inserted call depth counter (recommended v0)

Mechanism:

- Add a per-thread (or per-capsule) `call_depth` counter and `call_depth_max` limit.
- On function entry:
  - `call_depth += 1`
  - if `call_depth > call_depth_max`: abort with deterministic `OREN_DIAG`.
- On function exit:
  - `call_depth -= 1`

Where the counter lives (tiered):

- **AVM:** already exists in the VM implementation.
- **Native runtime:** store in runtime state (or TLS if/when we have threads).
- **C backend runtime:** store in a runtime global / TLS.

Key properties:

- deterministic across OS/arch (it does not depend on host stack size)
- easy to test and fuzz

Costs:

- adds a few instructions per function call (can be optimized later)

### Option B — OS stack probing / guard pages (not enough alone)

Relying on OS stack overflow behavior is not acceptable for parity:

- stack sizes differ across platforms (Windows vs Linux vs macOS),
- failures are not guaranteed to be catchable,
- behavior is not deterministic and can corrupt host state.

OS stack probing still matters for correctness in some ABIs (notably Windows), but it is a
separate problem from deterministic recursion limits.

### Option C — Tail call optimization (TCO) for tail recursion (v1+)

TCO can make many recursive functions stack-safe by converting tail calls into loops.

This is valuable but should not be the only guard because:

- not all recursion is tail-recursive,
- indirect calls + closures make TCO harder,
- it does not address deep mutual recursion unless we do more advanced transforms.

Rolling status (today):

- The compiler performs **direct self tail recursion** elimination (conservative):
  - rewrites `return f(args...)` where `f` is the current function into parameter rebinding + loop `continue`
  - only when the tail return is not nested inside another loop (`while`/`for`) because we have no labeled continue
  - only for fixed-arity calls (no spread / varargs yet)
- The compiler can also eliminate a narrow subset of **non-tail** self recursion (tail recursion modulo constant):
  - rewrites `return f(args...) + <int>` and `return f(args...) - <int>` into a loop with an accumulator
  - only for a restrictive function shape (one `if` base return + one recursive return) and only when the base/cond contain no calls
- Fixture: `tests/native/fixtures/tail_recursion_ok.oren` (expected to succeed under low `OREN_CALL_DEPTH_MAX`)
  - Fixture: `tests/native/fixtures/non_tail_modconst_ok.oren`

### Option D — Heap-backed call frames (future; for non-TCO recursion)

Goal:

- For recursive calls that cannot be TCO-optimized, avoid consuming unbounded **host** stack by
  moving the “logical call stack” into heap-managed frames.

High-level approach (Tier‑1 direction):

- **Explicit heap call-frames** (stackless execution):
  - lower calls to a loop over a heap stack of frames (similar to how AVM works)
  - most deterministic across OS/arch, and naturally works with per-capsule budgets
  - requires a well-defined calling convention at the IR boundary (closures/varargs/spread) and
    runtime support for frame allocation and unwinding diagnostics

Status:

- Not implemented yet; tracked as a future production maturity item once CoreIR callables converge and
  the native runtime injection surface stabilizes.

## Staged Plan (Rolling, Production-Oriented)

### P0 — Parity knob and deterministic diagnostic

1) Add a call-depth budget knob across backends:
   - AVM: `--call-depth-max` / `AVM_CALL_DEPTH_MAX` (already exists)
   - C backend: `OREN_CALL_DEPTH_MAX` env (already exists)
   - native backend: `OREN_CALL_DEPTH_MAX` env (runtime override) and `oren build --call-depth-max <n>` (compile-time default)
2) Lower the budget knob into a runtime-visible limit in a single, shared contract (so “default vs override” behaves the same everywhere).
3) Implement entry/exit instrumentation in shared lowering (CoreIR boundary), so all
   backends inherit the same semantics.
4) Add a cross-backend fixture:
   - same source compiled under `--backend bytecode`, `--backend c`, `--backend native`
   - proves consistent failure once depth exceeds budget.

### P1 — Reduce overhead (safe optimizations)

- elide instrumentation for known-leaf functions (no calls)
- allow “no depth checks” for internal runtime helpers that cannot recurse

### P2 — Tail-call optimization (optional, but valuable)

- implement TCO for direct tail calls first
- then extend to closure tail calls once callables converge on the canonical `{code_ptr, env_ptr}` ABI

## Related Work / Constraints

- Backend unification direction: `docs/BACKENDS.md`
- AVM semantics + determinism: `docs/AVM_SPEC.md`
