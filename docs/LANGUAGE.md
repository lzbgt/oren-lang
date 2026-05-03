# Language (Manual + Spec + Appendices)

**Last updated:** 2026-04-11

This file merges the former language manual, spec, and appendices into one canonical reference.
Use the manual for day‑to‑day programming, the spec for compiler‑level semantics, and the
appendices for deeper design notes and planned surface areas.

---

# Oren Language Manual (Rolling)

This is the **practical** guide to writing Oren today.

It is intentionally different from the formal spec:

- **Manual**: “how to use it” + idioms + examples (what works *now*).
- **Spec**: complete grammar + exact semantics (`docs/LANGUAGE.md`).

Oren is in **rolling ABI mode**: until an explicit stabilization milestone is declared, backwards compatibility is not guaranteed.

## Reading guide (AI- and tool-friendly)

Oren is designed to be usable by **humans and AI agents**. In rolling mode, the most common failure mode is “docs drift” (a doc claim that is no longer true).
This manual therefore follows a strict grounding rule:

- **If you need the truth for execution semantics, trust code + fixtures first.**
  - Canonical “what works today” snapshot: `docs/STATUS.md`
  - AI-friendly feature index: `docs/STATUS.md`
  - Living spec fixtures: `tests/native/fixtures/`, `tests/modules/`, `tests/avm/`
  - Runnable integrated examples: `examples/` (suite: `make examples-test`)

When you change behavior (compiler/runtime/stdlib):

- add or update a fixture,
- update the relevant section(s) in this manual and/or `docs/LANGUAGE.md`,
- update `docs/STATUS.md` if a new gap is discovered.

## Implementation map (where semantics live)

This section is a brief “map” for AI agents (and maintainers) to connect a language feature to the implementation that enforces it.

For a rolling “agent cache” of subtle internals (name resolution, lowering patterns, cross-backend contracts),
see `docs/DESIGN.md#backend-outputs`.

### Compiler front-end (parsing + AST)

- Tokens/lexer: `lib/compiler/token.oren`, `lib/compiler/lexer.oren`
- Parser entrypoints: `lib/compiler/parser_parse/000_prelude.oren`, `lib/compiler/parser_parse/020_parser_b.oren`
- AST node constructors: `lib/compiler/ast.oren`

### Module system (imports + whole-program linking)

- Import graph + whole-program merge + aliasing: `lib/compiler/compiler/020_modules_linking.oren`
- Name rewriting (import prefixing): `lib/compiler/renamer.oren`

### Lowering pipeline (rolling semantics)

Many “language features” in rolling v0 are implemented as deterministic lowerings into simpler core constructs.
Start from:

- Build pipeline entry: `lib/compiler/compiler/040_build_pipeline.oren`

And then follow the referenced passes (impl lowering, generic specialization, container sugar, etc.) under `lib/compiler/`.

### Backends (code generation)

- C backend (portable): `lib/compiler/transpiler.oren` (+ `lib/runtime.[ch]`)
- Bytecode backend (`.obc`): `lib/compiler/codegen_bytecode/` (compiler) + `lib/avm/` (runtime, C)
- Native backend (Tier‑1 intent):
  - arm64: `lib/compiler/arm64_macho.oren`, `lib/compiler/arm64_elf.oren`
  - x86_64: `lib/compiler/x64_elf.oren`, `lib/compiler/x64_pe.oren`, `lib/compiler/x64_native_program.oren`
  - Runtime support: `lib/runtime_native/`

### Tests as spec (recommended entrypoints)

- Compile/runtime diagnostic contracts: `tests/native/fixtures/`
- Module/trait behavior: `tests/modules/`
- AVM determinism + capability model: `tests/avm/`

## 0) What Oren is

Oren is an **agent-native**, syscall-first language and toolchain:

- **Native** mode (server/desktop): compiles to native binaries (no libc shims for the *native backend output*).
  - Tier‑1 targets (rolling intent): `arm64` and `x86_64` across **macOS / Linux / Windows**.
  - Practical reality today:
    - macOS `arm64` is the most feature-complete native backend surface.
    - Linux/Windows `x86_64` (`--arch x64`) is Tier‑1 intent but still a growing bring-up subset (see `docs/STATUS.md` and `docs/DESIGN.md` for real-hardware validation).
- **Portable** mode: compiles to `.obc` bytecode executed by AVM, supporting determinism, snapshots, and capability-governed virtualized domains (FS/NET/PROC/ENV/TIME).

## 0.1) Compiler CLI quick reference (modern, machine-friendly)

The Stage1 compiler (`./oren`) is intended to behave like a modern tool (Python `click` style):

- Subcommands: `oren build`, `oren test`, `oren emit-c`, `oren meta`, `oren dump`, `oren scan`, `oren completion`
- Human help:
  - `oren --help`
  - `oren build --help`
- Machine-readable help (for tools/agents):
  - `oren --help=json`
- Shell completion (generate scripts):
  - `oren completion bash`
  - `oren completion zsh`

See `docs/DESIGN.md` for activation instructions.

### 0.1.1) `--typecheck` mode (rolling, opt-in)

`oren build` supports an opt-in typecheck pass:

```bash
# Fail fast on type errors in annotated code (still builds on success).
./oren build your_prog.oren --backend bytecode --typecheck -o build/your_prog.obc
```

What `--typecheck` is for (today):

- A correctness gate for code that uses **type annotations** (function params/returns, typed short var decls, and cast-like boundaries).
- Catching obvious mistakes early without a full static type system yet.

What it checks (v0, conservative):

- Invalid casts (example: `f32("x")`).
- Invalid `as` casts (the parser lowers `x as T` into cast sugar calls; `--typecheck` validates the obvious-bad cases).
- Call/return mismatches when the function signature is annotated and the value is statically known (literals and simple arithmetic).

What it is *not* (yet):

- Full inference/unification/generics constraints.
- Proof of container element types (list/map contents are usually `unknown` to the v0 checker).

Important: some safety guardrails are **always-on** and do not require `--typecheck`:

- The compiler rejects `bool/int/float == nil` comparisons (`nil-compare guard:` diagnostics). See `docs/DESIGN.md#backend-outputs`.
  - Key rule: **scalars are never nil**. Comparing a numeric/bool value to `nil` is always a bug (even if the value originated from a dynamic source).
  - Safe pattern for “optional config”: compare the **dynamic** value to `nil`, then cast:
    - `var t = cfg["timeout_ms"]; var timeout_ms = 1000; if t != nil { timeout_ms = i64(t) }`

### 0.2) Quickstart: build + run (all backends)

Build and run a program on the **C backend** (portable via host toolchain):

```bash
./oren build your_prog.oren --backend c -o build/your_prog_c
./build/your_prog_c
```

Toolchain selection (C backend, rolling):

- Default C compiler is `cc` on POSIX hosts.
- On **Windows hosts**, if `--cc` is not provided, the compiler defaults to **MSVC** `cl.exe` and attempts to auto-configure the VS environment (vswhere + VsDevCmd/vcvars) so a Developer Prompt is not required.
  - Escape hatches: `OREN_MSVC_INSTALL_PATH` (pin VS install root), `OREN_MSVC_VSWHERE` (pin `vswhere.exe` path).
  - `--python` is supported under MSVC by querying Python’s `sysconfig` (the bootstrap path tries `python3`, `python`, then `py -3`; override via `OREN_PYTHON=/path/to/python`, `OREN_PYTHON="py -3"`, or `OREN_PYTHON="C:\Path With Spaces\python.exe -E"`).
  - When Python embedding is enabled, use `py_release(obj)` to drop long‑lived Python objects and avoid refcount leaks.
- For **cross-compiling** a C-backend Windows artifact from a non-Windows host, you must pass an explicit cross compiler via `--cc` (the compiler will not auto-pick `cl.exe` off-host).

You can also emit the generated C without compiling it:

```bash
./oren emit-c your_prog.oren -o build/your_prog_c   # alias for: build --backend c --emit-c
```

Build and run a program on the **native backend** (Tier‑1 targets, rolling):

```bash
./oren build your_prog.oren --backend native -o build/your_prog_native
./build/your_prog_native
```

By default, the compiler picks the **runtime host platform** when `--platform` is not provided:

- `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux`
- Override with `--platform <arch>-<os>` or env `OREN_PLATFORM=<arch>-<os>`
- `--target`/`--arch` are legacy and now accept `auto` (prefer `--platform`)

Cross-compile examples:

```bash
# Linux ELF (run it on Linux, or via the Win11 (WSL2 optional) workflow in `docs/DESIGN.md`)
./oren build your_prog.oren --backend native --platform arm64-linux -o build/your_prog_linux

# Windows PE (run it on Windows)
./oren build your_prog.oren --backend native --platform x64-windows -o build/your_prog_win.exe
```

Note: `--platform arm64-linux` / `--platform x64-linux` outputs a Linux ELF; run it on Linux (or via the Win11 (WSL2 optional) remote workflow in `docs/DESIGN.md`).

Build and run **bytecode** on AVM:

```bash
./oren build your_prog.oren --backend bytecode -o build/your_prog.obc
./avm build/your_prog.obc
```

Passing program arguments in AVM (convention: `--` separates AVM flags and program args):

```bash
./avm build/your_prog.obc -- --flag value
```

Stack safety knobs (rolling):

- AVM: `./avm --call-depth-max 64 build/your_prog.obc`
- Native backend: `OREN_CALL_DEPTH_MAX=64 ./build/your_prog_native` (runtime override)
  - Native compile-time default: `./oren build ... --backend native --call-depth-max 64`
- C backend: `OREN_CALL_DEPTH_MAX=64 ./build/your_prog_c`

To disable the deterministic recursion guard (unlimited): `OREN_CALL_DEPTH_MAX=0 ...`

## 1) Program structure

Oren files are modules. A typical program has a `main` function:

```oren
fn main() {
    print("hello")
    exit(0)
}
```

Entry semantics (rolling, by current toolchain implementation):

- **Top-level statements execute** as the module loads (they compile into an internal `__top_level__` function).
- If `fn main()` exists, the runtime **calls it automatically** (native backend + AVM bytecode + C backend).
  - C backend implementation detail: the user `main` is emitted as a different C symbol to avoid colliding with the host `int main(...)` entrypoint.
- Avoid writing `main()` as a top-level call unless you intentionally want `main` to run twice.
- Program termination (rolling): **do not rely on `main` return value** for an exit code.
  - Different backends currently treat the `main` return value differently (some ignore it).
  - Use `exit(code)` for deterministic termination semantics across backends.

### Imports

Import with an alias:

```oren
import math "std:math"
import buffer "std:buffer"
```

Imported names can be qualified as `alias.symbol`.

Notes (rolling):

- `import` is intended as a **compile-time, module-level** declaration.
  - In practice, put `import ...` at **top level** (outside `fn` bodies / blocks).
  - The parser currently accepts `import` inside blocks, but backends treat imports as compile-time only; a block-scoped import is not meaningful and may become a compile error in the future.

### Stdlib import resolution (`std:` / `std/`)

The compiler supports a stable stdlib import scheme so user code does not need repo-relative paths like `../../lib/std/...`.

Supported stdlib specifier forms:

- `std:` scheme:
  - `import tcp "std:net/tcp"`
  - `import base64 "std:encoding/base64"`
- `std/` path form:
  - `import tcp "std/net/tcp"`
  - `import base64 "std/encoding/base64"`

Resolution rules (current compiler behavior):

- `.oren` extension is optional (`"std:net/tcp"` resolves to `.../net/tcp.oren`).
- The compiler finds the stdlib root directory (`STDLIB_ROOT`) in this priority order:
  1) `OREN_STDLIB_ROOT` environment variable (either `.../lib/std` or an install root containing `lib/std`)
  2) walk up from the importing file directory looking for `lib/std/argparse.oren`
  3) fallback: `lib/std` relative to the current working directory

If stdlib root cannot be resolved, `import "std:..."` is a hard compile error.

See also: `docs/DESIGN.md#runtime-and-stdlib-layering` (distribution story and future embedding).

### Selected stdlib modules (rolling; evidence-backed)

These stdlib modules exist today and are exercised by regression fixtures:

- CLI/strings:
  - `std:argparse` (smoke: `tests/native/test_argparse_smoke.oren`)
  - `std:strings` (used by `std:crypto/pem` smoke)
  - `std:bytes` (smokes: `tests/native/qi/100_tests_basic.oren`, `tests/avm/test_smoke_suite.oren`)
- Encoding / crypto helpers:
  - `std:encoding/base64` (TLS/HTTPS/WSS loopback fixtures)
  - `std:crypto/pem` (smoke: `tests/native/test_pem_decode_smoke.oren`)
  - `std:crypto/x509` (minimal helper layer; used by NET/TLS internals)
  - `std:crypto/tls` (TLS facade; alias-layer over `std:net/tls` while the TLS crypto-core split is implemented)
- Native NET stack (native backend; rolling Tier‑1 focus):
  - `std:net/tcp`, `std:net/udp`
  - `std:net/dns` (loopback fixtures + Windows default resolver smoke: `tests/fixtures/windows_dns_default_resolver_smoke.oren`)
  - `std:net/http` (structured response API; loopback fixtures)
  - `std:net/http2` (rolling: framing + loopback fixtures; covers SETTINGS/ACK + PING/ACK + CONTINUATION: `tests/native/test_http2_preface_loopback.oren`, `tests/native/test_http2_headers_loopback.oren`)
  - `std:net/http2_client` (rolling: minimal HTTP/2 client layer; handshake + single-stream request/response; exercised by `tests/native/test_http2_headers_loopback.oren`)
  - `std:net/hpack` (rolling: HPACK encode/decode v0 (includes Huffman); smokes: `tests/native/test_hpack_smoke.oren`, `tests/native/test_hpack_encode_rfc_c41.oren`)
  - `std:net/ws` (WebSocket v0; loopback fixtures)
  - `std:net/tls` (TLS wrapper; used by `https://` and `wss://` loopback fixtures)

For the detailed NET/TLS behavior and design constraints (determinism, pinning, providers), use the dedicated docs:

- `docs/DESIGN.md#runtime-and-stdlib-layering`
- `docs/DESIGN.md#runtime-and-stdlib-layering`
- `docs/DESIGN.md#runtime-and-stdlib-layering`
- `docs/DESIGN.md#runtime-and-stdlib-layering`

### FFI symbols (`ffi name`)

Oren supports an `ffi` declaration statement to reference an external symbol:

```oren
ffi puts
puts("Hello FFI")
```

Recommended cross-platform form (native backend):

```oren
// Cross-platform C FFI example: call `puts`.
//
// On Linux, declare the libc dependency explicitly so the native backend emits a dynamic ELF.
// On Windows, attach the DLL used for symbol resolution.

@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi puts

@cfg(os="linux")
@ffi.link("libc.so.6")
ffi puts

@cfg(os="macos")
ffi puts
```

Portable shortcut (rolling): libc alias

```oren
// Same intent as above, but without per-OS library name boilerplate.
//
// `@ffi.libc` resolves to the platform C library name for the selected `--platform` target:
// - Windows: msvcrt.dll
// - Linux:   libc.so.6
// - macOS:   libSystem.B.dylib
@ffi.libc
@ffi.ret("i32")
ffi { puts as c_puts, atoi as c_atoi }
```

Grouping convenience (recommended when importing multiple symbols from the same library):

```oren
@cfg(os="windows")
@ffi.dll("msvcrt.dll")
ffi {
    puts
    strlen
}

@cfg(os="linux")
@ffi.link("libc.so.6")
ffi {
    puts
    strlen
}
```

Module-exported FFI bindings (recommended for stdlib wrappers):

```oren
import libc "std:ffi/libc"

fn main() {
    var n = libc.strlen("oren")
    if n != 4 { exit(1) }
    exit(0)
}
```

Windows-only stdlib wrapper example:

```oren
import k32 "std:ffi/kernel32"

@cfg(os="windows")
fn main() {
    var tid = k32.GetCurrentThreadId()
    if tid == 0 { exit(1) }

    // Win32 error slot round-trip (also exercises `@ffi.ret("void")`).
    var v0 = k32.SetLastError(123)
    if v0 != 0 { exit(2) }
    if k32.GetLastError() != 123 { exit(3) }
    exit(0)
}
```

Notes (rolling):

- The compiler may internally **prefix/rename** the declared symbol to keep modules separate (example internal label: `STD_ffi_libc_strlen`).
- The **external** symbol lookup name remains the source identifier (`strlen`), so `dlsym/GetProcAddress/dyld` binds the expected C ABI symbol even when the internal label is namespaced.

Stdlib convenience wrappers (rolling):

- Prefer `std:ffi/*` wrapper modules when a platform requires library-name or ABI return-kind details:
  - cross-platform libc: `std:ffi/libc`
  - Win32 basics: `std:ffi/kernel32`
  - Win32 network config (used by `std:net/dns`): `std:ffi/iphlpapi`
  - Win32 TLS plumbing (used by `std:net/tls_windows_schannel`): `std:ffi/secur32`, `std:ffi/crypt32`
  - Linux dynamic loader (used by `std:net/tls_linux_openssl`): `std:ffi/libdl`
  - macOS TLS frameworks (used by `std:net/tls_macos_securetransport`): `std:ffi/macos_security`, `std:ffi/macos_corefoundation`, `std:ffi/macos_dlfcn`

Rolling convenience:

- `ffi { sym1, sym2, ... }` expands to multiple `ffi sym` declarations, inheriting the same attributes.
  - In rolling v0, commas/semicolons between group items are optional: `ffi { sym1 sym2 }` (one-per-line) is also accepted.
- Per-item attributes are allowed inside the group and are merged with the outer attributes:
  - `@ffi.link("libc.so.6") ffi { @ffi.ret("i32") atoi, puts }`
  - This is especially useful when many symbols come from the same library but have different ABI return kinds.
- `@ffi.ret("...")` may also appear **before** the group as a default return kind:
  - `@ffi.link("libc.so.6") @ffi.ret("i32") ffi { atoi, puts, @ffi.ret("void") srand }`
  - Per-item `@ffi.ret("...")` overrides the group default (so you can set `i32` once and override rare `void`/`u32` cases).
- You can also alias an `ffi` declaration when the **Oren identifier** should differ from the **external symbol name**:
  - `ffi puts as c_puts`
  - `@ffi.link("libc.so.6") ffi { puts as c_puts, strlen as c_strlen }`
  - The left name is the external symbol (`dlsym` / `GetProcAddress`), the right name is the internal identifier you call.

Notes (rolling):

- `ffi` is a low-level escape hatch intended primarily for native interop and experiments.
- In **capsule** mode, `ffi` declarations are rejected (FFI bypasses capability gating).
  - Native backend:
    - **macOS** supports binding against `libSystem` for `ffi` calls (see `docs/DESIGN.md#native-backend-overview`).
    - **Windows x64** supports `ffi` via lazy `LoadLibraryA`/`GetProcAddress` stubs.
      - `--link` adds DLLs to the resolver search list (see `docs/DESIGN.md#native-backend-overview`).
      - `@ffi.link("...")` can attach a dynamic library directly to an `ffi` declaration (portable form; maps to `--link`).
      - `@ffi.dll("name.dll")` can also attach a DLL directly to an `ffi` declaration (Windows convenience; useful for stdlib).
      - `@ffi.ret("i32"|"u32"|"void"|"ptr"|"usize")` can declare ABI return width/kind for some C-style APIs:
        - `"i32"`: sign-extend the 32-bit return to i64.
        - `"u32"`: zero-extend the 32-bit return to i64.
        - `"void"`: force the return value to 0 for expression contexts.
        - `"ptr"` / `"usize"`: pointer-sized / `size_t` returns. On Tier‑1 (arm64/x64), these are 64-bit returns and do not require normalization, but the annotation is accepted as ABI metadata (and future 32-bit targets can lower it correctly).
      - `@ffi.export` can export a top-level function symbol for callback-style interop (currently: arm64-macos + linux/arm64 + linux/x64 + windows/x64 native; see `docs/LANGUAGE.md`).
    - **Linux x64** supports `ffi` when `--link` is used (dynamic ELF + `dlsym` resolver). Without `--link`, calling an `ffi` symbol panics (see `docs/DESIGN.md#native-backend-overview`).
    - **Linux arm64** supports `ffi` when `--link` is used (dynamic ELF + `dlsym` resolver). Without `--link`, calling an `ffi` symbol panics (see `docs/DESIGN.md#native-backend-overview`).
  - C backend:
    - Oren does not have a stabilized “typed C FFI” surface yet, but you can still link extra C by compiling the emitted C yourself (see `docs/DESIGN.md#c-backend-design-and-abi`).

FFI sugar (rolling ergonomics):

- You can attach a library to a single `ffi` declaration (or a whole `ffi { ... }` group) using the attribute form:
  - `@ffi.link("libc.so.6") ffi { puts, atoi }`
  - `@ffi.dll("msvcrt.dll") ffi { puts, atoi }` (Windows convenience)
- There is also a small sugar form which lowers to the portable `@ffi.link(...)`:
  - `ffi("libc.so.6") { puts, atoi }`
  - `ffi("msvcrt.dll") { puts as c_puts, atoi as c_atoi }` (Windows: `@ffi.link("msvcrt.dll")` is supported too)
  - Multiline item lists are allowed (diff-friendly):
    - `ffi("msvcrt.dll") { puts as c_puts atoi as c_atoi }`

### Conditional compilation (`@cfg(...)`)

Oren supports a **minimal conditional compilation** attribute:

- source form: `@cfg(...)`
- canonical form (what metadata uses): `@oren.cfg(...)`

`@cfg` is evaluated at compile time based on the selected target platform:

- `--platform <arch>-<os>` (preferred), or
- env fallback `OREN_PLATFORM=<arch>-<os>`

If the target platform is unknown/missing, `@cfg(...)` is a compile-time error.

Why `@cfg` exists (and when to use it):

- Prefer writing platform-independent code by depending on stdlib abstractions (`std:net/tcp`, `std:net/tls`, etc.).
- Use `@cfg` when the source must bind to platform-specific surfaces that stdlib cannot fully hide, for example:
  - OS-specific APIs / syscalls that genuinely do not exist across platforms (Win32 vs POSIX),
  - platform-specific constants/struct layouts at syscall boundaries,
  - platform-specific dynamic link library names **when there is no portable alias**.
  - host build/packaging details (e.g. Windows `.exe` naming in scripts).
- In tests/stdlib, `@cfg` is allowed as a **boundary tool**:
  - It should gate small platform-specific declarations (FFI library names, syscall structs), while the *public* API being tested stays stable (`std:net/*`, `std:crypto/*`, etc.).
  - If you see `@cfg` sprinkled through application logic, treat it as a signal that a missing stdlib abstraction should be added (rolling goal: keep `@cfg` rare).

Portability guide (recommended reading):

- `docs/DESIGN.md` explains the “keep `@cfg` at the boundary” rule and gives concrete patterns for tests and stdlib.

Rolling note (FFI ergonomics):

- For the platform C library, prefer `@ffi.libc` instead of per‑OS `@cfg` blocks.
  - This removes the common “Linux uses `libc.so.6`, macOS uses `libSystem.B.dylib`, Windows uses `msvcrt.dll`” boilerplate.

Supported selector forms (rolling v0):

- Positional string selector:
  - `@cfg("linux")` / `@cfg("macos")` / `@cfg("windows")`
  - `@cfg("x64")` / `@cfg("arm64")`
  - `@cfg("x64-windows")` / `@cfg("arm64-linux")`
  - `@cfg("debug")` / `@cfg("release")` (build profile)
- Keyword selectors (CSV strings; AND across keys):
  - `@cfg(os="linux,macos")`
  - `@cfg(arch="x64")`
  - `@cfg(platform="arm64-linux")`
  - Negation keys: `not_os`, `not_arch`, `not_platform`
  - `@cfg(debug=true)` / `@cfg(debug=false)`

Important limitations (current implementation):

- `@cfg` is implemented for **declarations** (`fn`, `struct`, `ffi`, `var`) and **statements** inside blocks.
- `@cfg` is **not** supported on arbitrary expressions (use statement-level form).
- If you use `@cfg` to provide multiple platform variants of the same declaration name, the variants must be **mutually exclusive** (otherwise you can get duplicate definitions).
- `@cfg` is **not supported on `import` yet** (the stage2 fast import scan cannot respect conditional imports).
  - Gate declarations *inside* the imported module instead.

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
    - `dbg(...)` is debug print sugar:
      - Statement form: expands to `@debug print(...)` with a `file:line` prefix.
      - Expression form (single-arg): `dbg(expr)` returns `expr` and prints it in **debug** builds (compiled out in release).
    - `dprint(...)` is the no-prefix variant:
      - Statement form: expands to `@debug print(...)` with **no prefix**.
      - Expression form (single-arg): `dprint(expr)` returns `expr` and prints it in **debug** builds (compiled out in release).

Example (debug-only trace without deleting code):

```oren
fn work() {
    @debug print("trace: entering work()")
    debug {
        print("trace: entering work() (block)")
    }
    // ... real logic ...
}
```

Example (debug-only print sugar):

```oren
fn work() {
    dbg("trace: entering work()") // compiled out in release builds
    dprint("trace: entering work() (no prefix)")
}
```

Example (expression form):

```oren
fn work() {
    var n = dbg(41)       // returns 41; prints only in debug builds
    var m = dprint(n + 1) // returns 42; prints only in debug builds
}
```

Example (safe per‑OS declaration variants with a fallback):

```oren
@cfg(os="windows") fn title() { return "hello (win)" }
@cfg(os="linux")   fn title() { return "hello (linux)" }
@cfg(os="macos")   fn title() { return "hello (macos)" }
@cfg(not_os="windows,linux,macos") fn title() { return "hello" }
```

### Arena loop annotations (rolling)

Oren supports opt‑in/out annotations for the arena auto‑loop rewrite:

- `@oren.arena` forces arena evaluation for the loop (still subject to safety checks).
- `@oren.arena_iter` forces per‑iteration arena push/pop for the loop (use for long‑lived loops).
- `@oren.noarena` disables auto wrapping for that loop.

Example:

```oren
@oren.arena
while i < n {
    var xs = [] // eligible for arena allocation
    xs.push(i)
    i = i + 1
}

@oren.noarena
while j < n {
    ys.push(j) // stays on GC heap
    j = j + 1
}

@oren.arena_iter
while true {
    var tmp = []
    tmp.push(i)
    i = i + 1
    if i == 10 { break }
}
```

## 2) Values and literals

### Integers

- Decimal: `123`, underscore separators allowed: `1_000_000`
- Prefixed bases:
  - hex: `0xFF`, `0xDEAD_BEEF`
  - bin: `0b1010_0110`
  - oct: `0o755`

Negative numbers are prefix expressions: `-1`, `-(a + b)`.

Integer arithmetic (rolling v0):

- `+ - * / %` are defined for `int`.
- `int / int` is signed integer division with truncation toward zero.
- `int % int` is the signed remainder consistent with trunc-toward-zero division (remainder has the same sign as the dividend).
- Invalid cases are deterministic runtime panics:
  - division by zero
  - modulo by zero
  - signed overflow (`i64_min / -1`)
  - modulo overflow (`i64_min % -1`)

Examples:

```oren
if 7 / 3 != 2 { exit(1) }
if -7 / 3 != -2 { exit(2) }
if 7 % 3 != 1 { exit(3) }
if -7 % 3 != -1 { exit(4) }
```

### Bitwise ops and shifts (`& | ^ ~ << >>`)

- Bitwise ops operate on the 64-bit two’s-complement bit pattern of `int`.
- `>>` is a logical (zero-fill) right shift in rolling v0.
- Shift counts must be in `0..63`; out-of-range shift counts are a deterministic runtime panic (consistent across AVM/C/native backends).

### Floats (`f64` container in v0)

Float literals are compiled as **f64 bit-pattern constants**.

Supported forms:

- Decimal: `12.5`, `0.125`
- Scientific notation: `1e3`, `5e-1`, `12.5E+2`

Rolling notes (important for backends):

- Oren’s `float` value is represented as a **64-bit IEEE‑754 bit pattern** (an `f64` container) in v0.
- Casts like `f32(x)` / `f64(x)` are **numeric conversions** (rounding / widening), not bit reinterprets.
- For bit-level reinterpretation (useful for typed buffers and serialization), the native toolchain exposes:
  - `oren_f32_to_u32_bits(f32) -> u32` and `oren_u32_bits_to_f32(u32) -> f32`
  - `oren_f64_to_u64_bits(f64) -> u64` and `oren_u64_bits_to_f64(u64) -> f64`

Example (bit-cast roundtrip):

```oren
var bits = oren_f64_to_u64_bits(1.0)      // 0x3ff0_0000_0000_0000
var x = oren_u64_bits_to_f64(bits)
if i64(x) != 1 { exit(1) }
```

### Booleans and nil

- `true`, `false`
- `nil` is the canonical null value.

### Strings

Strings are double-quoted:

```oren
var s = "hello"
```

Rolling semantics (today):

- Strings are **immutable byte strings** (UTF‑8 by convention).
- All current backends store strings as **NUL‑terminated byte sequences** internally.
  - Practical consequence: embedded `\\0` is not supported as a stable cross-backend value.

Common operations:

- Concatenation uses `+`:

  ```oren
  var s = "hello" + " " + "world"
  ```

- Length uses `s.len()` (when the receiver is known as `: string`) or the explicit helper:

  ```oren
  var n = s.len()
  // or:
  var n2 = oren_string_len(s)
  ```

- Slice uses `oren_string_slice(s, start, end)`:
  - indices clamp to `[0, len]`
  - empty/out-of-range slices return `""`

  ```oren
  var mid = oren_string_slice("abcdef", 1, 5) // "bcde"
  ```

- Single-byte char extraction uses `oren_string_char_at(s, i)` (returns a 1-byte string).

Notes:

- Legacy code sometimes uses `string_concat(a, b)` directly; prefer `a + b` in modern Oren so
  backends can choose the optimal lowering.

- Native backend implementation note (performance/GC):
  - String literals like `"hello"` are **pooled** in the native output: identical literals are de-duplicated into a single constant byte pool, and their pointers are stable within the binary.
  - These embedded literals live in the binary’s constant/data segment and are **not tracked as GC heap allocations** (they are “static”).
  - Dynamically created strings (concatenation, slicing, parsing) still allocate and are GC-managed as usual.
  - References:
    - `docs/DESIGN.md#native-runtime-layout` (literal pool + runtime init)
    - `docs/DESIGN.md#native-backend-performance-playbook` (why this matters for hot paths)

## 3) Variables and assignment

Declare with `var`:

```oren
var x = 10
x = x + 1
```

### Short declarations (`:=`) (rolling)

Oren also supports a Go-like short declaration form:

```oren
x := 10        // sugar for: var x = 10
y := x + 2
```

And a typed variant (annotation sugar):

```oren
// typed short declaration (still non-semantic in rolling v0):
b: u16be := 6
```

Rolling notes:

- `:=` is a **declaration**, not an assignment.
- Type annotations are **non-semantic** in rolling v0: they must not change runtime behavior (they primarily enable deterministic lowering + tooling).
- `for ...; ...; post {}` does **not** allow `:=` in `post` (use `=` there).

This is exercised by `tests/avm/test_smoke_suite.oren` (`test_type_annotations_sugar`).

## 4) Control flow

### `if / else / else if`

Oren supports `else if` chains (no extra braces required):

```oren
if x < 0 {
    print("neg")
} else if x == 0 {
    print("zero")
} else {
    print("pos")
}
```

### `while`

```oren
var i = 0
while i < 10 {
    print(oren_int_to_string(i))
    i = i + 1
}
```

### `for` (C-style in v0)

```oren
for var i = 0; i < 10; i = i + 1 {
    // ...
}
```

Rolling note: there are two additional `for` forms that are supported by the parser and are
commonly used in low-level code:

- Infinite loop: `for { ... }` (equivalent to `while true { ... }`)
- Condition-only: `for cond { ... }` (equivalent to `while cond { ... }`)

### `break` / `continue`

Oren supports `break` and `continue` inside loops.

- `break` exits the **nearest** enclosing loop.
- `continue` skips to the next loop iteration.
  - In `for var i=...; ...; post { ... }`, `continue` still executes the `post` expression
    before re-checking the loop condition (this avoids “continue hangs” and is enforced by tests).

This behavior is exercised by:

- `tests/native/test_for_break_continue.oren`
- `tests/avm/test_for_break_continue.oren`

### `for x in iterable` (trait-based iteration sugar)

Oren supports a higher-level iteration form:

```oren
for x in xs { ... }
for x: i32 in xs { ... }
```

This is **source-level sugar** that desugars into repeated calls to the runtime hook:

- `oren_iter_next(iterable, idx, out_pair) -> [ok:int, value]`
  - `out_pair` is a reusable list buffer (length ≥ 2) used to avoid per-iteration allocations
  - `ok == 1` means “yield `value`”
  - `ok == 0` means “stop iteration”

Iteration proceeds in deterministic **index order** (`idx = 0, 1, 2, ...`) and stops at the first `ok == 0`.

#### Trait-based extension: `trait Iterable`

In rolling mode, Oren also supports a static-first trait extension for iteration:

```oren
trait Iterable {
    fn iter_next(self, idx, out_pair)
}
```

If the loop iterable is a bare identifier and an `impl Iterable for <Type>` exists, the compiler can rewrite the loop to call that impl (avoiding runtime vtables and keeping hot loops predictable).

Practical example (range-like iterable):

```oren
trait Iterable { fn iter_next(self, idx, out_pair) }

struct MyRange { start: i32, end: i32, step: i32 }

impl Iterable for MyRange {
    fn iter_next(self, idx, out_pair) {
        var ok = 0
        var val = nil
        if idx >= 0 && self.step != 0 {
            var v = self.start + idx * self.step
            var ok2 = (self.step > 0 && v < self.end) || (self.step < 0 && v > self.end)
            if ok2 { ok = 1; val = v }
        }
        var out = out_pair
        if out == nil { out = [0, nil] }
        out[0] = ok
        out[1] = val
        return out
    }
}

var r: MyRange = MyRange(0, 10, 1)
var sum = 0
for x: i32 in r { sum = sum + x }
```

For deeper details and the long-term polymorphism plan (static-first, optional `dyn Trait` later), see `docs/LANGUAGE.md`.

### `switch` / `case` (multi-branch dispatch)

Oren supports `switch` statements for multi-branch control flow:

```oren
var x = 3
var y = 0

switch x {
    case 1 { y = 10 }
    case 2, 3 { y = 20 }      // multiple match values
    default { y = 30 }
}
```

Notes (rolling behavior, as exercised by tests):

- The `switch <expr>` expression is evaluated **exactly once** (useful when `<expr>` has effects).
- `case` can list multiple values separated by commas.
- A colon after the case list is accepted in rolling mode:
  - `case 2, 3: { ... }` (see `tests/modules/test_switch.oren`)
- `default` is optional; if present, it matches when no earlier case matches.

### `match` / `case` (pattern match sugar)

Oren supports `match` with `case` patterns (especially for enum sugar).

Important: **`match` is a contextual keyword**. You can still use `match` as an identifier unless the parser sees the statement form:

```oren
var match = 1  // valid
```

Statement form:

```oren
match v {
    case Option.None { print("none") }
    case Option.Some(x) { print("some=" + oren_int_to_string(x)) }
    default { print("unknown") }
}
```

This expands into a deterministic tag-dispatch chain internally (see the spec for details).

## 5) Functions and lambdas

### Functions

```oren
fn add(a, b) {
    return a + b
}
```

### Generic functions (rolling v0.1)

Oren supports **generic templates** with bracket type parameters:

```oren
fn id[T](x: T): T {
    return x
}
```

In the current rolling model, **generic calls must be explicitly specialized**:

```oren
var a = id[i64](1)
var b = id[u32](7)
```

Calling `id(1)` without `[...]` is a compile-time error (see `tests/native/fixtures/generic_unspecialized_call.oren`).

### Lambdas

Lambdas use `|params| expr` or `|params| { block }`.

```oren
var f = |x| x + 1
var g = |x, y| { return x * y }
```

Lambdas capture values (capture-by-value in the current lowering model).

### Varargs and call-site spread (`...`)

Oren supports two related features:

1) **Varargs parameters** (bind extra arguments into a list)
2) **Call-site spread** (pass a list as multiple arguments)

Varargs parameters:

```oren
fn count(...rest) {
    // `rest` is a list of extra args (possibly empty)
    return oren_list_len(rest)
}

fn sum1(x, ...rest) {
    var s = x
    var i = 0
    while i < oren_list_len(rest) {
        s = s + rest[i]
        i = i + 1
    }
    return s
}
```

Rules (rolling):

- Only one varargs parameter is allowed, and it must be the **last** parameter.
- The varargs binding is always a **list** (possibly empty).

Runtime type tags (useful for varargs dispatch):

- `oren_type_tag(v)` → int (stable tag numbers; see below)
- `oren_type_name(v)` → string (stable names for tags; intended for logging and simple branching)
- `lib/std/reflect.oren` provides `tag(v)` / `name(v)` wrappers and stable tag constants, so user code does not need to hardcode numeric tags.

Tag values (stable; matches `lib/runtime.h` `OrenType` enum):

- `0` `nil`
- `1` `int`
- `2` `float`
- `3` `bool`
- `4` `string`
- `6` `list`
- `7` `map`
- `8` `func`
- `9..13` typed buffers (`u8_buf`, `i32_buf`, `i64_buf`, `f32_buf`, `f64_buf`)

Rolling note (native backend):

- `nil`, `false`, and `true` are **runtime singleton values** in native mode (not raw `0/1`).
  - This keeps `0` (int zero) distinct from `nil`/`false`, matching the language’s type-strict equality goals.
- `oren_type_tag` / `oren_type_name` are still best-effort until full tagged values land:
  - `nil` and `bool` are reliably distinguishable (tags `0` and `3`).
  - Numeric immediates are still a rolling area: `int`/`float` may be indistinguishable in some native-mode paths (so both may report tag `1`).
- Rolling reflection v0 for structs: user-defined `struct` values are map-shaped today, but constructors tag them with `{"__oren_type":"TypeName", ...}`, so `oren_type_name(TypeName(...))` returns `"TypeName"` instead of `"map"`.
  - `__oren_type` is a **reserved** struct key; user code must not declare a field named `__oren_type` (compile-time error).
- Guardrail (2026-01-10): the compiler rejects `bool/int/float == nil` comparisons when the scalar side is statically known (literals, casts, locally-proven scalars, or calls to functions with explicit scalar return annotations), and also when a value is later proven scalar by best-effort scan (e.g. `i64(x)` / `x & 255`, or arithmetic-with-literal like `x + 1` after `if x == nil { ... }`).
  - This is a correctness feature: scalars are not “optionals”; treat missing values explicitly (e.g. `{"ok":1,"v":...}` / `{"ok":0}`), or use a tag-based check on truly dynamic values:
    - `if oren_type_tag(x) == 0 { ... }`
  - This guard is **always-on** (it does not require `--typecheck`). Diagnostics are tagged as `nil-compare guard: ...` so regressions are easy to spot in CI logs.
- Beyond `oren_type_tag` / `oren_type_name`, full runtime reflection (fields/layout/type metadata) is not yet implemented and is tracked as a larger refactor in `docs/STATUS.md`.

Call-site spread (apply-style call):

```oren
fn add3(a, b, c) { return a + b + c }
var xs = [2, 3]
var r = add3(1, xs...) // expands to add3(1, 2, 3)
```

This is exercised by:

- `tests/modules/test_varargs.oren` (varargs + spawn/join)
- `tests/native/test_integration_suite.oren` and `tests/avm/test_smoke_suite.oren` (spread calls)

## 6) Types (practical)

Oren’s *runtime* (v0) is dynamically typed (boxed values), but the language includes **explicit width types** used for:

- ABI/layout and packed views
- typed buffers (`[]i32`, `[]f32`, `[]f64`, …) (HPC buffers; not boxed lists)
- deterministic casts at type boundaries

Common width tokens (non-exhaustive):

- ints: `u8 u16 u32 u64 u128`, `i8 i16 i32 i64 i128`
- floats: `f32 f64`
- `bool`
- endian tokens for packed views: `u16be`, `u32be`, etc.

### Casts

Casts are written as `Type(x)`:

```oren
var a = u8(256 + 5)  // wrap to 5
var b = i32(-1.9)    // truncate toward zero then wrap to width
```

The compiler lowers these to deterministic runtime primitives (not “user-level” function calls).

### Rolling v0: container kind hints (`list` / `map` / `buf` / `string`)

Oren’s type system is still rolling without a full static checker, but some sugar relies on
**receiver kind hints** so lowering stays deterministic across backends (especially the native backends).

In practice, you may see (or choose to use) annotations like:

```oren
var xs: list = [1, 2, 3]     // list receiver hint
var m: map = {"a": 1}        // map receiver hint
var s: string = "hello"      // string receiver hint
// import buffer "std:buffer"
// var b: []i32 = buffer.i32_new(16)  // typed-buffer receiver hint
```

These annotations are **compiler hints** in rolling v0, not stable “v1 types”.
See `docs/LANGUAGE.md` (“kind annotations”) for the normative description.

Rolling note (native backends):

- numeric annotations like `: i64`, `: u64`, `: int` are treated as an “int kind” hint so map indexing `m[k]` can infer whether `k` is an integer key without relying on runtime pointer/int heuristics
- typed buffer annotations like `[]i32` / `[]f64` are treated as a “buf kind” hint for receiver sugar like `b.len()`

### Traits and `impl` (practical)

Oren supports `trait` declarations and `impl Trait for Type` blocks as a **compile-time** mechanism.
Today, the most visible use is trait-based iteration for `for x in iterable { ... }` (see above).

The broader design goal is:

- **static dispatch by default** (good for HPC and deterministic AVM execution)
- optional explicit runtime polymorphism later (e.g. `dyn Trait`) only where needed

#### Method call sugar + qualified calls

Trait methods are lowered to deterministic symbol names like:

- `__oren_impl__<Trait>__<Type>__<method>(...)`

The compiler also supports **method-call sugar**:

- `Type.method(args...)` calls the impl for that `Type`
- `x.method(args...)` calls the impl if `x` has a known type annotation in scope

When multiple traits define the same method name for the same receiver type, unqualified `x.method(...)` is **ambiguous** and rejected.

In that case (and in general for clarity), use a **trait-qualified call**:

```oren
trait AddLike { fn op(self, x); }
trait MulLike { fn op(self, x); }

impl AddLike for i64 { fn op(self, x) { return self + x } }
impl MulLike for i64 { fn op(self, x) { return self * x } }

var a: i64 = 3
var r0 = AddLike.op(a, 4) // 7
var r1 = MulLike.op(a, 4) // 12
```

See `tests/modules/test_trait_qualified_calls.oren` and `tests/native/fixtures/trait_impl_ambiguous_method.oren`.

#### Coherence (one impl per Trait×Type)

Rolling coherence rules enforced by the compiler:

- A given `(Trait, Type)` pair must have **exactly one** `impl` block.
- Duplicate impls are rejected.
- Splitting methods across multiple impl blocks is rejected deterministically.

See `tests/native/fixtures/trait_impl_duplicate.oren` and `tests/native/fixtures/trait_impl_split_blocks.oren`.

#### Blanket impls (`any`) (fallback impl; not a value type)

Rolling v0 supports a minimal blanket impl form:

```oren
trait Z { fn z(self); }

impl Z for any { fn z(self) { return 0 } }
impl Z for i64 { fn z(self) { return 7 } }
```

Exact impls (like `i64`) override blanket `any` impls deterministically.
See `tests/modules/test_trait_blanket_impl_any.oren`.

Notes (rolling):

- `any` is currently **only** meaningful in `impl <Trait> for any { ... }` as a “fallback receiver”.
  It is not a general “top type”, and you should not assume you can write `var x: any = ...` as a
  stable feature.
- This is still **compile-time rewriting** (no vtable / no dynamic dispatch). Do not confuse it with
  the planned `dyn Trait` direction.

See `docs/LANGUAGE.md` for the design rationale and constraints.

## 7) Structs, attributes, and deterministic metadata

Structs:

```oren
struct Point {
    x: i32,
    y: i32
}
```

Classes (rolling; legacy object-shaped values):

```oren
class Rect { tl, br }

var r = Rect(Point(0, 0), Point(10, 20))
var w = r.br.x - r.tl.x
```

In the current rolling implementation, `class` is similar to `struct`:

- Constructor syntax is the same (`Rect(...)`).
- Field access is the same (`r.tl`, `r.br`).
- Values are represented as runtime map-shaped objects (see `docs/LANGUAGE.md`).

Oren’s long-term direction is “traits + composition”, not inheritance-first OOP; consider `class` a compatibility/ergonomics feature rather than a design center.

Enums (rolling “tagged map” sugar):

```oren
enum Option {
    None,
    Some(x),
    Pair(a, b),
}

var a = Option.None
var b = Option.Some(123)
var c = Option.Pair(7, 9)

// All enum values are maps with:
// - a string tag like "Option.Some"
// - positional payload fields ._0, ._1, ...
if b.tag != "Option.Some" { exit(1) }
if b._0 != 123 { exit(2) }
```

Enum values are designed to work naturally with `match` patterns like:

```oren
match b {
    case Option.None { print("none") }
    case Option.Some(x) { print("x=" + oren_int_to_string(x)) }
    default { print("unknown") }
}
```

See `tests/modules/test_enum.oren` and `tests/modules/test_match_enum.oren`.

### Attributes

Attributes are compile-time metadata annotations. Unknown attributes are inert in rolling mode, but preserved for tooling.

Attribute syntax:

- `@name`
- `@ns.name(...)` (dotted names are allowed)

They can appear on:

- declarations (`struct`, `fn`, `var`)
- local `var` declarations inside blocks
- struct fields
- parameters

Example (parameter attribute):

```oren
fn f(@json(rename="x") a) { return a }
```

Common builtins:

- `@abi` for ABI/layout metadata
- `@pack` for packed “view over bytes” structs (network packet parsing)
- `@serde(...)` for serialization metadata (json/yaml/cbor)
- `@cfg(...)` for conditional compilation by target platform (`--platform`) — see `docs/LANGUAGE.md`

## 8) Containers (lists, maps, buffers)

Oren has three “container families” in rolling v0:

1) **Lists**: `[]` (dynamic, boxed values)
2) **Maps**: `{...}` (dynamic keys/values)
3) **Typed buffers**: `[]i32 / []f32 / []f64 / ...` (HPC-oriented numeric arrays; runtime tags include `I32_BUF`, `F32_BUF`, `F64_BUF`, etc.)

### Lists (dynamic)

Lists are dynamic sequences. Literal forms:

```oren
var xs = [1, 2, 3]
var ys = []
```

Indexing and assignment:

```oren
var x0 = xs[0]
xs[1] = 9
```

Rolling note: lists are **boxed** at runtime. Even if you conceptually treat `xs` as “list of ints”, elements are still stored as generic runtime values. If you need stable numeric performance and layout, use typed buffers (see below).

#### std:list helpers (recommended)

Prefer `std:list` for ergonomics and for keeping stdlib/internal code off kernel intrinsics:

```oren
import list "std:list"

var xs = [1, 2, 3]
list.push(xs, 4)
var n = list.len(xs)
var tail = list.slice_copy(xs, 1, n - 1)
```

`std:list` also provides:

- `list.clone(xs)` — **shallow clone** (new list; elements are not deep-copied)
- `list.slice_copy(xs, off, n)` — copy out a sub-range (returns `Err` on invalid ranges)
- `list.slice_view(xs, off, n)` — cheap O(1) iterable *view*
- `list.slice_copy` rejects wrong-type non-nil `off`/`n` with `Err`, while malformed
  `list.slice_view` arguments still normalize to an empty iterable instead of crashing
  across native and AVM

#### Slice views (cheap; iterable-only)

`list.slice_view(xs, off, n)` returns an “iterable map” consumed by `for x in it {}` via the runtime hook `oren_iter_next(container, idx, out_pair)`.

This is designed for “fast iteration without copy”:

```oren
import list "std:list"

var xs = [10, 20, 30, 40]
var view = list.slice_view(xs, 1, 2) // 20, 30

var sum = 0
for x: i64 in view {
    sum = sum + x
}
```

Rolling semantics:

- Slice views are **not** general-purpose “lists” (they are iterable objects).
- The view reflects the underlying list values at iteration time (no copy).
- Malformed views iterate as an empty sequence (deterministic; avoids crashes).
  - In the native backend, the iterable-map marker (`__iter`) is only interpreted when it is a valid string value
    (guarded by `oren_is_string`), and tags are compared by string bytes (not pointer identity).

### Maps (dynamic)

Maps use `{k: v, ...}` syntax, and can be indexed:

```oren
var m = {"a": 1, "b": 2}
var v = m["a"]
m["c"] = 3
```

Rolling notes (native backends, v0):

- **Key kinds must be deterministic** for native codegen. Today the portable, fully-supported key kinds are:
  - `string` keys (e.g. `"a"`, `"field"`)
  - `int` keys (e.g. `0`, `42`)
- If you write `m[key]` or `m[key] = v` and `key` is a **variable**, the native backends may require the compiler to infer whether `key` is an `int` key or a `string` key.
  - Rolling behavior: if the key kind is not inferable statically, the compiler emits a **runtime dispatch**:
    - if `key` is a tracked heap string (`oren_find_node(key).kind == STRING`), treat it as a string key
    - otherwise treat it as an int key
  - This avoids unsafe numeric-range heuristics, but it is still an interim design until Oren has a fully tagged value representation for native execution.
- When you know the key is a string at runtime (common in parsers/codecs), you can use the explicit runtime helpers:
  - `oren_map_get_str(m, key)` / `oren_map_set_str(m, key, value)`
  - `oren_map_get_int(m, key)` / `oren_map_set_int(m, key, value)`
  - `oren_map_set_*` returns the written value (matches `xs[i] = v` returning `v`).

Example (dynamic string key):

```oren
var m = {}
var key = "hello"
oren_map_set_str(m, key, 123)
print(oren_int_to_string(oren_map_get_str(m, key)))
```

Rolling note: map keys are restricted to a small set of runtime types (see `docs/DESIGN.md#avm-and-obc-bootstrap-spec-summary` and runtime code for the exact set).

### Typed buffers (HPC)

Typed buffers are the performance-oriented container family used by the SIMD and linalg layers.
They are created via intrinsics (or std wrappers) and support deterministic numeric kernels.

Examples of native/AVM intrinsics include:

- `oren_i32_buf_new(len)`
- `oren_f32_buf_new(len)`
- `oren_buf_load_f32(buf, idx)`
- `oren_buf_store_f32(buf, idx, val)`

See `docs/STATUS.md` and `docs/DESIGN.md#avm-neon-mapping-plan-arm64-no-jit-first` for direction and design constraints.
- `@cap.requires(domain="...")` for capsule/capability gating of host-effectful APIs (see below)

#### Strict attribute mode (compiler option)

For “lint-like” strictness (useful for production toolchains and schema-driven metadata), the compiler supports:

- `./oren build ... --strict-attrs`
- `./oren build ... --attr-allow-prefixes myorg.` (repeatable allowlist of custom namespaces)

In strict mode:

- unknown/forbidden attribute prefixes are rejected at compile time

See `tests/native/fixtures/strict_attrs_ok.oren` / `strict_attrs_bad.oren` (these fixtures can be exercised via the native test targets, e.g. `make test-native-all`).

#### Strict identifier prefix mode (compiler option)

For reserved identifier enforcement (avoid user-defined `oren_` / `sys_` / `__oren_` symbols):

- `./oren build ... --strict-ident-prefixes`
- `./oren build ... --ident-allow-prefixes myorg.,acme.` (allowlist prefixes in strict mode)

#### ABI layout example

```oren
@abi
struct ABI1 {
    a: u8,
    b: u32,
    c: u16
}
```

You can query layout through syslib intrinsics:

```oren
oren_abi_sizeof("ABI1")
oren_abi_offsetof("ABI1", "b")
```

Note (multi-module builds):

- After module linking, type names may be linker-prefixed to avoid collisions.
- The `oren_abi_*` builtins accept **bare source names** (like `"ABI1"`) and the compiler resolves them by a unique suffix match.
  - If multiple ABI types share the same suffix, pass the fully-qualified linked name (the compiler will report an ambiguity error).

Invalid ABI queries (unknown type/field) are compile-time errors and emit machine-readable `OREN_DIAG` lines (see `tests/native/fixtures/abi_layout_error.oren`).

#### Packed view example (network parsing story)

```oren
@pack
struct H {
    v: u8,
    t: u8,
    len: u16be,
    src: u32be,
    dst: u32be
}

var bytes = [69, 0, 0, 84, 192, 168, 0, 1, 8, 8, 8, 8]
var h = pack_view("H", bytes, 0)
print(oren_int_to_string(h.src))
```

Packed views are designed to avoid heap pressure: they are “structured access over bytes”, not per-packet struct allocations.

## 7.5) Capsule mode and capability-gated APIs (native backend)

Oren has a rolling “capsule” model to make **host effects explicit**.
This is primarily a **compiler mode** plus a convention for annotating runtime APIs:

For the current capability domain and native runtime-profile contract, see
`docs/CAPABILITY_RUNTIME_CONTRACT.md`.

- In capsule mode, calls to functions annotated with `@cap.requires(domain="FS|NET|PROC|ENV|TIME|RNG")`
  are rejected unless that domain is explicitly allowlisted.
- Direct syscall intrinsics (`sys_*`) are always rejected from user code in capsule mode.
- `ffi` declarations are rejected in capsule mode (FFI bypasses capability gating).
- `oren meta` and native `--metadata` emit a normalized top-level `capabilities`
  manifest that lists required domains by source function, plus a normalized top-level
  `package` manifest for package-policy intent. This is a tooling contract; enforcement
  remains the capsule compiler/runtime policy.
- `--manifest` artifact manifests include a `policy` block with backend, runtime-profile
  request, capsule flag, allowlisted domains, source-required domains, and an explicit
  budget-declaration marker. In native `auto` mode, the manifest records `backend-auto`
  rather than pretending the backend heuristic has a source-level package declaration.
- `@oren.package(...)` can attach a metadata-only package-policy marker to a top-level
  declaration. The current fields are `runtime_profile`, `cap_allow_domains`, and budget
  defaults such as `budget_cpu_ms`, `budget_wall_ms`, `budget_heap_bytes`, and `budget_gas`.
  This marker normalizes into metadata/artifact manifests; it does not silently change
  normal compiler backend selection. Artifact manifests also include
  `policy.source_package_check`, an observe-only comparison of the package marker against
  actual build flags and runtime-profile selection. Use `--enforce-package-policy` or
  `OREN_ENFORCE_PACKAGE_POLICY=1` to fail builds when that check reports `mismatch_observed`.
  Use `scripts/run_package_policy.sh --backend avm` or
  `scripts/run_avm_package_policy.sh` when bytecode execution should actually apply the
  source package policy: it maps package capsule intent to AVM capsule/deny-by-default
  execution, `budget_gas` to `AVM_GAS`, `budget_heap_bytes` to `AVM_MEM_BYTES`, and
  `budget_wall_ms` to `AVM_TIMEOUT_MS`, with a pre-execution bytecode used-domain check
  against the package allowlist. Use `scripts/run_package_policy.sh --backend native`
  when native capsule execution should consume the same marker: it builds with package
  capsule/domain policy, runs with matching `OREN_CAPSULE` / `OREN_CAP_ALLOW_DOMAINS`,
  enforces `budget_wall_ms` with a process watchdog, enforces `budget_heap_bytes` from native-run
  JSON live-heap scan evidence, and enforces `budget_cpu_ms` from child process resource usage
  where available. It also enforces `budget_gas` from native-run JSON
  `native_stmt_loop_tick_v0` evidence after building and running with
  `OREN_NATIVE_GAS_ACCOUNTING=stmt`. Backend statement/op boundaries charge one tick, backend loop
  poll sites charge their mask interval when they fire, and direct/manual native safepoints charge
  one tick; this remains statement+loop-granular rather than instruction-equivalent, and the native
  run JSON gas object identifies that unit with `surface.schema="oren.gas-surface.v0"` and
	  `surface.id="native_stmt_loop_tick_v0"`, while also marking it `unit_scope="backend_local"`,
	  `unit_family="native_statement_or_op"`, `conversion_ready=false`, and `avm_canonical=false`.
		  Setting `OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1` asks the native package-policy runner to
		  build a bytecode sidecar from the same source/package manifest, run it under the declared AVM
		  budgets, and record package-bound `oren.avm-canonical-sidecar-gas.v0` AVM opcode gas when stdout
		  and exit status match the native run or when the sidecar itself reports AVM canonical gas budget
		  exhaustion. The record includes normalized stdout/stderr hashes, `certification_status`, and
		  `certification_failure_reasons`; this remains sidecar AVM evidence, not native gas conversion. Setting
		  `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar`, or using
		  `scripts/run_package_policy.sh --backend native --gas-profile avm-sidecar`, upgrades that
		  package-bound sidecar into the native runner's `budget_gas` enforcement profile: the runner
		  enforces the AVM canonical `avm_opcode_cost_v0` sidecar budget, reports
		  `runner_wall_avm_canonical_gas`, and records `enforcement_profile="avm-sidecar"` while still
		  keeping `native_runtime_conversion=false`. The `auto` profile chooses that same sidecar profile
		  when the package declares `budget_gas` and records `requested_enforcement_profile="auto"`;
		  the shared dispatcher uses `auto` as its native default unless the caller passes another
		  profile or already set `OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE`.
	  `OREN_NATIVE_GAS_ACCOUNTING=statement` is an exact synonym
  for `stmt`; `OREN_NATIVE_GAS_ACCOUNTING=basic-block` selects the distinct
  `native_basic_block_tick_v0` native lowering-block evidence surface, and
  `OREN_NATIVE_GAS_ACCOUNTING=block-weighted` selects the stronger
  `native_block_weighted_tick_v0` weighted lowering-block evidence surface, and
  `OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter` selects runtime path-aware
	  `native_dynamic_emitter_tick_v0` emitter-span evidence. Direct native package-policy gas
	  budgets still default to statement+loop gas, while the shared dispatcher defaults to `auto` so
	  gas-budgeted packages use package-bound AVM canonical gas rather than converting any native
	  surface. Every native
  gas-surface descriptor is marked `unit_scope="backend_local"`, includes `target_arch` and
  `unit_family`, and sets `cross_arch_comparable=false`, `conversion_ready=false`, and
  `avm_canonical=false`, so tools must not treat it as architecture-neutral instruction gas. Set
  `OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path>` to capture runner-observed native wall-budget
  evidence plus any captured runtime ledger summary as `oren.native-package-policy-run.v0`. Set
  `OREN_NATIVE_RUN_JSON=1` on native executables for runtime-observed `oren.native-run.v0`
  stdout with compact `effect_ledger_summary` evidence; it currently reports native wall
  elapsed time, capsule domain-gate counters, selected FS/NET/PROC resource-check counters, and
  `heap_bytes.used` from a report-time scan of live tracked native heap nodes, plus default
  `native_loop_safepoint_tick_v0` gas ticks, `native_stmt_loop_tick_v0` when
  `OREN_NATIVE_GAS_ACCOUNTING=stmt` / `statement` is used for matching build/run invocations, or
  `native_basic_block_tick_v0` under `OREN_NATIVE_GAS_ACCOUNTING=basic-block`, or
  `native_block_weighted_tick_v0` under `OREN_NATIVE_GAS_ACCOUNTING=block-weighted`, or
  `native_dynamic_emitter_tick_v0` under `OREN_NATIVE_GAS_ACCOUNTING=dynamic-emitter`. Native build cache
  keys include the normalized gas-accounting mode, so cached native artifacts do not cross those
  compile-time gas surfaces.
  AVM run JSON reports top-level `status` / structured `error` fields plus the applied gas, heap, and wall budget fields through
  `effect_ledger_summary.budgets`, including `wall_ms.limit`, and marks its gas surface as
  canonical `avm_opcode_cost_v0` opcode-dispatch gas with
		  `unit_scope="avm_canonical"`, `runtime_path_aware=true`, `cross_arch_comparable=true`,
		  `conversion_ready=true`, and `avm_canonical=true`. Semantic-diff tooling keeps native and AVM gas
		  non-comparable while the native surface cannot target that AVM unit honestly. It also records
		  `oren.avm-canonical-sidecar-gas.v0` as same-source OBC canonical gas evidence beside native runtime gas,
			  with normalized output hashes, `certification_status`, `certification_failure_reasons`, and
			  `package_policy_may_use=false` because semantic-diff fixtures are not package/input-bound.
			  The native package-policy runner's separate `avm-sidecar` gas profile is the package-bound path
		  that can use AVM canonical sidecar evidence for `budget_gas`, and the shared dispatcher exposes it
		  with `--backend native --gas-profile avm-sidecar` and defaults native dispatch to `auto`,
		  which selects that path when `budget_gas` is declared. The gas-surface
		  inventory and conversion status are tracked in `docs/GAS_SURFACE_REGISTRY.md` and guarded by
		  `make verify-gas-surface-registry`.
  The `source_required_domains` / `dependency_domain_union` fields are currently
  `source_attrs_only`, meaning they come from linked `@cap.requires` attributes rather than
  a complete stdlib/runtime effect proof.

Enable capsule mode at compile time:

```sh
./oren build your_prog.oren --backend native --capsule
```

Allow domains explicitly (comma-separated list):

```sh
./oren build your_prog.oren --backend native --capsule --cap-allow-domains FS,NET
```

Fixtures showing expected behavior:

- Capsule OK (pure compute): `tests/native/fixtures/capsule_ok.oren`
- Capsule BAD (direct syscall): `tests/native/fixtures/capsule_bad_syscall.oren`
- Capsule BAD (FS not enrolled): `tests/native/fixtures/capsule_bad_fs.oren`
- Capsule OK with FS enrolled: `tests/native/fixtures/capsule_ok_fs_allow.oren`

### Runtime policy knobs (env var driven)

Capsule mode is a **compile-time** capability gate, but the syscall-first native runtime also has a
**runtime** allowlist layer for “what exactly is permitted inside each domain”.

This is intentionally configured via environment variables so parent processes / “multiverse”
parents can safely constrain child universes without recompiling the child program.

These knobs are exercised by the “capsule runtime” fixtures under `tests/native/fixtures/`:

- **FS mounts**
  - `OREN_FS_MOUNTS="v/=build/mnt/"` (legacy: applies to both read+write)
  - `OREN_FS_MOUNTS_READ="v/=build/mnt/"` (read-only mounts)
  - `OREN_FS_MOUNTS_WRITE="v/=build/mnt/"` (write-enabled mounts)
  - The `v/` prefix is a *virtual path prefix*; the runtime rewrites `v/...` into the mounted host path.
  - Examples: `tests/native/fixtures/capsule_runtime_fs_prog.oren`,
    `tests/native/fixtures/capsule_runtime_fs_syscall_open_read_prog.oren`,
    `tests/native/fixtures/capsule_runtime_fs_syscall_open_write_prog.oren`.

- **FS allow prefixes** (alternative to mounts)
  - `OREN_FS_ALLOW_PREFIXES="build/mnt/,/tmp/"` (legacy: applies to both)
  - `OREN_FS_ALLOW_READ_PREFIXES="..."`, `OREN_FS_ALLOW_WRITE_PREFIXES="..."`
  - Use mounts when you want stable virtual paths; use allow-prefixes when you want direct host paths.

- **NET allowlists**
  - `OREN_NET_ALLOW_LOOPBACK=1` enables loopback endpoints (for local services / tests).
  - `OREN_NET_ALLOW_TCP_CONNECT="127.0.0.1:8080,10.0.0.1:*"`
  - `OREN_NET_ALLOW_TCP_LISTEN="127.0.0.1:*"`
  - Map-driven variants exist for multiverse use cases (see `OREN_NET_TCP_CONNECT_MAP` / `OREN_NET_TCP_LISTEN_MAP`).
  - Examples: `tests/native/fixtures/capsule_runtime_net_connect_prog.oren`,
    `tests/native/fixtures/capsule_runtime_net_listen_prog.oren`,
    `tests/native/fixtures/capsule_runtime_net_syscall_map_prog.oren`.

- **PROC allowlists**
  - `OREN_PROC_ALLOW_EXEC_PREFIXES="/usr/bin/,/bin/"` (CSV path prefixes)
  - `OREN_PROC_ALLOW_SYSTEM=1` (enables `oren_system(_timeout)`; shell-based convenience)
    - POSIX shell selection (rolling):
      - if `OREN_SYSTEM_SHELL` is set, it must be an absolute executable path (otherwise `oren_system_timeout` returns `-2`)
      - else `SHELL` is used if it is an absolute executable path
      - else fall back to common shells (`/bin/sh`, `/usr/bin/sh`, `/bin/bash`, `/usr/bin/bash`)
  - Env inheritance controls:
    - `OREN_PROC_INHERIT_ENV=1` inherit all parent env vars (**dangerous**, use sparingly)
    - `OREN_PROC_ALLOW_ENV_KEYS="PATH,HOME,OREN_TEST_SECRET"` only allow specific keys
  - Argv allowlists:
    - `OREN_PROC_ALLOW_ARGV="<path>|<argv0>[|<arg1>...],<path>|..."`
    - `|` is used as the argv delimiter inside each spec.
  - Examples: `tests/native/fixtures/capsule_runtime_proc_spawn_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_spawn_join_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_env_prog.oren`,
    `tests/native/fixtures/capsule_runtime_proc_system_prog.oren`.

Notes:

- The runtime prints “CAPSULE DENY: ...” errors with hints pointing at these env vars when a call is blocked.
- In AVM/bytecode mode, the same high-level domains exist, but the allowlists are modeled as VM config rather than host env vars.

## 8) Typed buffers and HPC building blocks

Typed buffers are the canonical HPC container in Oren today:

```oren
import buffer "std:buffer"
import linalg "std:linalg"

var a: []f64 = buffer.f64_new(6)
var b: []f64 = buffer.f64_new(6)
// store elements using runtime helpers, then:
var out: []f64 = linalg.matmul_f64_buf(a, b, 2, 3, 2)
```

Design goals:

- avoid boxed list overhead in numeric kernels
- isolate hot loops so NEON microkernels can replace them without changing semantics
- deterministic accumulation order for consensus and testing

SIMD (Tier‑1 HPC: arm64 NEON now, x86_64 SSE/AVX next) in the native runtime (rolling):

- SIMD is **opt-in** and must not change semantics (scalar results are authoritative).
- Enable/disable (native backend outputs only):
  - `OREN_ENABLE_SIMD=1` enables SIMD fast paths when available.
  - `OREN_NO_SIMD=1` disables SIMD (wins over enable).
- Determinism guard: scalar vs SIMD paths must remain bit-identical for the covered kernels.
  - Primary regression suite: `tests/native/test_simd_suite.oren`.
  - Current reality: arm64 NEON fast paths are the most mature (macOS + Linux). x86_64 SIMD (SSE2 baseline, AVX2 optional) is planned once the x64 backend reaches full Tier‑1 semantic parity.

## 9) Deterministic math (no host libm)

The `std/math` module provides deterministic “libm-lite” functions implemented without calling host `libm`:

- rounding: `floor`, `ceil`, `round` (as float outputs)
- core: `sqrt`, `powi`, `exp2`, `exp`, `log2`, `ln`
- trig: `sin`, `cos`, `atan`, `atan2` (range-reduced, deterministic; `sin/cos` use Payne–Hanek-style reduction for huge |x|)

For exactness and determinism, tests often prefer:

- integer-representable float inputs
- explicit tolerances like `1e-12` (scientific literals are supported)

## 10) Concurrency (today)

Oren has `spawn` (rolling v0 restriction: spawns a call expression):

```oren
fn work(x) { return x + 1 }
var t = spawn work(10)
```

Call-site spread (`...`) works in `spawn` just like normal calls:

```oren
var xs = [10]
var t2 = spawn work(xs...)
```

To wait for a spawned task:

```oren
var r = oren_join(t) // returns the worker’s return value (or panics if the worker panicked)
```

Timeout join is also available:

```oren
// timeout_ms < 0 means “wait forever” (equivalent to oren_join).
// timeout_ms == 0 is a non-blocking probe (returns -60 if not done yet).
// timeout_ms > 0 waits up to a rolling join budget and returns -60 on timeout.
var r2 = oren_join_timeout(t, 20)
```

See `tests/modules/test_spawn_join_timeout.oren` and `tests/native/test_spawn_join_timeout.oren`.

Important portability note (native backend, rolling):

- On **macOS/Linux**, native `spawn` is currently implemented as **fork + pipe** (process-based).
- On **Windows x64**, native `spawn` is currently implemented as **CreateThread** (thread-based).

This means “spawned code” is not fully uniform across OS yet. In particular:

- On POSIX v0, a spawned worker does **not** share address space with the parent (it is a child process).
- On Windows, a spawned worker **does** share address space (it is a thread), so calling `exit(...)` inside the worker would terminate the whole process.

Practical guidance (portable style, rolling):

- **Do not call `exit(...)` inside a spawned worker** if you want the program to be portable across OS.
  - Prefer returning a status code and collecting it via `oren_join(...)` / `oren_join_timeout(...)`.
- In rolling v0, the spawned callable’s **return value** is the portable contract (it is carried to the joiner via a pipe on POSIX, and via a shared result slot on Windows). Prefer that over process exit codes.

```oren
fn server_impl() { /* shared logic */ return 0 }

fn server_worker() { return server_impl() } // portable: return status, join collects it
```

Some Tier‑1 fixtures still use small `@cfg(os=...)` glue for other OS differences (notably macOS fork-safety around Security/CoreFoundation, where loopback TLS servers use a fork+exec pattern), but the spawned worker itself should not call `exit(...)`.

Concurrency in AVM differs from native mode; see:

- `docs/LANGUAGE.md`
- `docs/DESIGN.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`

### Channels + select (rolling; AVM + native macOS/Linux)

Oren also exposes low-level **channel primitives** (runtime builtins; not keywords yet):

- `oren_new_channel() -> ch`
- `oren_chan_send(ch, val) -> ok` (rolling: `1`)
- `oren_chan_recv(ch) -> val` (blocks if empty)
- `oren_select_recv([ch1, ch2, ...]) -> [idx, val]` (blocks)
- `oren_select(cases) -> [idx, payload]` (blocks)
  - recv case: `[0, ch]`
  - send case: `[1, ch, val]`
  - payload is the received value (recv) or `1` (send)

Example (recv-only select):

```oren
var c1 = oren_new_channel()
var c2 = oren_new_channel()
oren_chan_send(c2, 111)

var r = oren_select_recv([c1, c2])
// r == [1, 111]
```

Backend notes (rolling):

- AVM: channels + select are deterministic VM opcodes.
- Native: implemented over pipe fds (macOS: kqueue, Linux: epoll). Windows support is pending.

## 11) Tooling quick reference

The authoritative build/test workflow is in:

- `docs/DESIGN.md`
- `docs/DESIGN.md`

### Machine-readable diagnostics (`OREN_DIAG`)

Both the compiler and runtime emit stable, machine-readable **single-line** diagnostics intended
for tooling and AI agents.

Format:

- `OREN_DIAG kind=<kind> code=<code> msg=<sanitized>`

Examples:

- Compile-time errors (parse/compile/codegen/typecheck) print an `OREN_DIAG` line to stderr and exit non-zero.
- Runtime failures (like `oren_fail(code, "msg")`) emit `OREN_DIAG kind=fail code=<code> ...` and exit with that code.
- Panics emit `OREN_DIAG kind=panic code=1 ...` (and may print a stack trace depending on backend/runtime).

Fixtures covering this contract:

- Runtime fail header: `tests/native/fixtures/diag_fail.oren`
- ABI/packview compile errors: `tests/native/fixtures/abi_layout_error.oren`, `tests/native/fixtures/packview_error.oren`

In rolling mode, a fast native verification step is:

```sh
make verify-native-quick
```

## 12) Test fixtures are a living spec (recommended)

The language and runtime evolve quickly in rolling mode. The most accurate “what works today” source is:

- `tests/native/fixtures/` (native + C backends; compile-time and runtime diagnostics)
- `tests/fixtures/` (targeted bring-up fixtures, including x86_64 native)
- `tests/modules/` (stdlib and module-level behavior)
- `tests/avm/` (AVM semantics and sandbox/determinism constraints)

This is intentional: fixtures are small, high-signal, and regression-friendly.

### Useful fixture groups (native backend)

- **Machine-readable compile errors** (`OREN_DIAG kind=compile|parse|codegen`):
  - Parse error contract: `tests/native/fixtures/parse_error.oren`
  - Codegen error contract: `tests/native/fixtures/codegen_error.oren`
  - Bytecode codegen error contract: `tests/native/fixtures/bytecode_codegen_error.oren`
  - Generic constraint failures: `tests/native/fixtures/generic_constraint_missing_impl.oren`

- **Deterministic runtime panics** (`OREN_DIAG kind=panic code=1`):
  - Division by zero: `tests/native/fixtures/arith_div0.oren`
  - Signed overflow (`i64_min / -1`): `tests/native/fixtures/arith_div_overflow.oren`
  - Modulo by zero: `tests/native/fixtures/arith_mod0.oren`
  - Modulo overflow (`i64_min % -1`): `tests/native/fixtures/arith_mod_overflow.oren`
  - Shift count out of range (SHL/SHR): `tests/native/fixtures/arith_shift_oob.oren`, `tests/native/fixtures/arith_shift_oob_shr.oren`
  - Negative index assignment: `tests/native/fixtures/index_set_negative.oren`
  - Index get out-of-bounds: `tests/native/fixtures/index_get_oob.oren`
  - Index get on non-container: `tests/native/fixtures/index_get_non_container.oren`
  - Map index set with unsupported key: `tests/native/fixtures/index_set_map_bad_key.oren`
  - Map index get with unsupported key: `tests/native/fixtures/index_get_map_bad_key.oren`
  - Deterministic recursion guard (call depth): `tests/native/fixtures/call_depth_overflow.oren`

- **Struct field assignment (rolling semantics)**:
  - OK path: `tests/native/fixtures/struct_field_assign_ok.oren`
  - Error path: `tests/native/fixtures/struct_field_assign_bad.oren`

### Capsule runtime fixture naming conventions

There are many “capsule runtime” fixtures. They are intentionally verbose so a failing case points at
exactly one syscall/domain edge.

- **FS (filesystems / mounts / syscalls)**:
  - High-level helpers: `tests/native/fixtures/capsule_runtime_fs_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_read_prog.oren`
  - Mount behavior: `tests/native/fixtures/capsule_runtime_fs_mount_read_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_mount_write_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_fs_syscall_open_read_prog.oren`, `tests/native/fixtures/capsule_runtime_fs_syscall_unlink_prog.oren`, etc.

- **NET (tcp connect/listen + raw socket syscalls)**:
  - High-level: `tests/native/fixtures/capsule_runtime_net_connect_prog.oren`, `tests/native/fixtures/capsule_runtime_net_listen_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_net_syscall_connect_prog.oren`, `tests/native/fixtures/capsule_runtime_net_syscall_read_socket_prog.oren`, etc.

- **PROC (spawn/exec/system/env)**:
  - High-level: `tests/native/fixtures/capsule_runtime_proc_spawn_prog.oren`, `tests/native/fixtures/capsule_runtime_proc_system_prog.oren`
  - Syscall edges: `tests/native/fixtures/capsule_runtime_proc_syscall_execve_true_prog.oren`, `tests/native/fixtures/capsule_runtime_proc_syscall_pipe_prog.oren`
  - Nested capsule behavior: `tests/native/fixtures/capsule_runtime_proc_child_capsule_parent.oren`, `tests/native/fixtures/capsule_runtime_proc_child_capsule_child.oren`

- **TIME (determinism constraints)**:
  - Syscall edges: `tests/native/fixtures/capsule_runtime_time_syscall_gettimeofday_prog.oren`, `tests/native/fixtures/capsule_runtime_time_syscall_nanosleep_prog.oren`

### x86_64 native bring-up fixtures (Tier‑1 roadmap)

The x86_64 native backend is Tier‑1, but still in bring-up. The x64 fixtures in `tests/fixtures/`
are the canonical incremental contract for what the x64 backend supports today:

- `tests/fixtures/x64_*_main.oren` are intended to compile under the native backend for Linux ELF + Windows PE (`./oren build ... --backend native --platform x64-linux` / `x64-windows`).
- Remote execution (Win11, WSL2 optional) is opt-in and can be done by copying the built artifact to a real x86_64 host.
- High-signal Tier‑1 fixtures (remote x86_64 gate; run via `scripts/verify_native_matrix.sh --targets x64-win-tier1` / `x64-wsl-tier1` with `--tier1-src <fixture>`; see `docs/DESIGN.md`):
  - Closures + varargs: `tests/fixtures/tier1_native_lambda_varargs_main.oren`
  - Maps (empty map + dynamic string key kind): `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren`
  - Strings (`+`, `len`, `slice`): `tests/fixtures/tier1_native_string_ops_main.oren`

## 13) Where to go next

- Formal language spec: `docs/LANGUAGE.md`
- Evolution narrative + roadmap (day0 -> compiler-in-AVM, phases): `docs/STATUS.md`
- Current task tracker (execution order): `docs/STATUS.md`


---

# Oren Language Specification (Draft)


This document describes the **current Oren language** as accepted by the Stage1 compiler (`./oren`) and required for self-hosting (`oren.oren`).
It includes both:

- **normative “what exists today”** rules (grounded in compiler behavior and fixtures),
- **explicitly marked planned design direction** items (tied to `docs/STATUS.md` / `docs/STATUS.md`).

The Go interpreter (`cmd/oren run` / REPL) is a convenience tool and is **not** the reference implementation (it supports only a subset and differs in some semantics like scoping).

## How to read this spec (AI- and tool-friendly)

This repo is in rolling mode. To keep the spec precise for both humans and AI agents, we use the following status markers:

- **Implemented**: works today and should have fixture evidence (see `tests/**` and `docs/STATUS.md`).
- **Rolling**: implemented but not stabilized (ABI/format/details may change; still regression-tested).
- **Planned**: design intent; not implemented yet (must link to `docs/STATUS.md` or other canonical design docs).

If an AI agent needs the most “ground-truth” behavior, prioritize:

- `docs/LANGUAGE.md` (practical usage today),
- `docs/STATUS.md` (evidence-backed “what works today” + missing gaps),
- `docs/STATUS.md` (feature → status → implementation → fixtures),
- the fixtures under `tests/native/fixtures/`, `tests/modules/`, `tests/avm/` (living spec).

## Non-normative: Implementation map (for maintainers and agents)

The spec defines syntax/semantics. This section exists to help AI agents locate the implementation that enforces a given rule.
It is **not** normative, but it should be kept accurate.

For a rolling “agent cache” of subtle internals (name resolution, lowering patterns, cross-backend contracts),
see `docs/DESIGN.md#backend-outputs`.

Compiler pipeline (high level):

1) parse → AST (`lib/compiler/parser_parse/**`, `lib/compiler/ast.oren`)
2) link modules/imports → merged program (`lib/compiler/compiler/020_modules_linking.oren`)
3) deterministic lowering passes (`lib/compiler/**`)
4) backend codegen:
   - C: `lib/compiler/transpiler.oren` → C + `lib/runtime.[ch]`
   - bytecode: `lib/compiler/codegen_bytecode/**` → `.obc` + AVM runtime `lib/avm/**`
   - native: `lib/compiler/arm64_*`, `lib/compiler/x64_*` + runtime `lib/runtime_native/**`

When this spec says “Implemented/Rolling”, the expected evidence is one of:

- a regression fixture under `tests/**`,
- or an example under `examples/` that runs under `make examples-test`.

## Lexical Structure

### Whitespace
- Spaces, tabs, newlines, and carriage returns separate tokens.
- Newlines are not significant.

### Comments
- Line comments start with `//` and run to the end of the line.

### Keywords
Implemented today:

`fn`, `var`, `true`, `false`, `if`, `else`, `return`, `while`, `for`, `switch`, `case`, `default`, `break`, `continue`, `yield`, `nil`, `ffi`, `import`, `struct`, `class`, `spawn`, `enum`, `trait`, `impl`, `test`, `assert`, `match`, `as`, `pub`

Contextual generator syntax:

- `defer` is now recognized as a statement-only, generator-finalization keyword in these forms:
  - explicit workers: `defer { ... } in co`
  - `@oren.generator` declarations: `defer { ... }`
- outside those generator contexts, plain `defer { ... }` is rejected unless it includes
  `in co`

Rolling note: `yield` is now reserved as a statement keyword. `defer` is still **not** a
globally reserved keyword; it is only contextual in the generator-finalization forms above.

Rolling note: `match` is a **contextual** keyword to preserve compatibility with code that uses
`match` as an identifier (variable/function name). The parser treats `match` as a statement only
when the following token sequence looks like a match statement, not an identifier usage.

### Identifiers
Identifiers are ASCII letters, digits, and `_`:
- Pattern: `[A-Za-z_][A-Za-z0-9_]*`

Rolling restriction (practical today):
- Prefixes `oren_` and `sys_` are **reserved** for runtime/compiler intrinsics.
- Prefix `__oren_` is reserved for compiler-generated internal symbols (wrappers, lambdas, etc.).

User code should not define variables/functions with these prefixes; the compiler may treat them as
special globals (for example, they are not captured as closure variables in native backends).

Practical guidance (today):

- Treat `oren_*` / `sys_*` as **low-level intrinsics**. Use them when you need the exact runtime hook,
  or when you are writing stdlib/runtime code.
- For user-facing code, prefer `std:*` modules and language sugar. If a wrapper doesn’t exist yet,
  consider defining a local alias with a clearer name:

```oren
fn yield_now() { return oren_yield() }
```

  Examples using stdlib wrappers:

```oren
import strings "std:strings"
import list "std:list"

fn first_byte(s) {
    var bs = strings.to_bytes(s)
    if list.len(bs) == 0 { return nil }
    return bs[0]
}
```

### Literals
- **Integer**: one or more digits: `[0-9]+`
- **Float**: digits, then `.`, then optional digits: `[0-9]+ "." [0-9]*`
- **String**: double-quoted characters: `"..."`  
  Escape sequences are supported:
  - `\\` (backslash)
  - `\"` (double quote)
  - `\n` (line feed)
  - `\r` (carriage return)
  - `\t` (tab)

## Syntax (EBNF)

```ebnf
program         = { statement } EOF ;

statement       = var_stmt
                | short_var_stmt
                | typed_short_var_stmt
                | assignment
                | return_stmt
                | while_stmt
                | for_stmt
                | switch_stmt
                | match_stmt
                | break_stmt
                | continue_stmt
                | import_stmt
                | type_stmt
                | trait_stmt
                | impl_stmt
                | enum_stmt
                | ffi_stmt
                | test_stmt
                | spawn_stmt
                | expr_stmt ;

var_stmt        = "var" ident [ ":" type_name ] "=" expression [ ";" ] ;
short_var_stmt  = ident ":=" expression [ ";" ] ;
typed_short_var_stmt = ident ":" type_name ":=" expression [ ";" ] ;
return_stmt     = "return" expression [ ";" ] ;
while_stmt      = "while" expression block ;
for_stmt        = "for" [ for_in_header | for_header ] block ;
switch_stmt     = "switch" expression "{" { case_clause } [ default_clause ] "}" ;
match_stmt      = "match" expression "{" { match_case } [ match_default ] "}" ;
case_clause     = "case" expression { "," expression } [ ":" ] block ;
default_clause  = "default" [ ":" ] block ;
match_case      = "case" match_pattern [ ":" ] block ;
match_default   = "default" [ ":" ] block ;
break_stmt      = "break" [ ";" ] ;
continue_stmt   = "continue" [ ";" ] ;
import_stmt     = "import" ident string_lit [ ";" ] ;
type_stmt       = ("struct" | "class") ident "{" [ field { "," field } [ "," ] ] "}" [ ";" ] ;
field           = { attr } ident [ ":" type_name ] ;
trait_stmt      = "trait" ident "{" { "fn" ident "(" [ param_list ] ")" [ ":" type_name ] ";" } "}" ;
impl_stmt       = "impl" dotted_name "for" type_name "{" { "fn" ident "(" [ param_list ] ")" [ ":" type_name ] block } "}" ;
enum_stmt       = "enum" ident "{" ident [ "(" [ ident { "," ident } ] ")" ] { "," ident [ "(" [ ident { "," ident } ] ")" ] } [ "," ] "}" ;
ffi_stmt        = "ffi" ( ffi_one | "{" ffi_item { ( "," | ";" ) ffi_item } "}" ) [ ";" ] ;
ffi_one         = ident [ "as" ident ] ;
ffi_item        = { attr } ident [ "as" ident ] ;
test_stmt       = "test" string_lit block ;
spawn_stmt      = "spawn" expression [ ";" ] ;
expr_stmt       = expression [ ";" ] ;

for_header      = expression
                | [ for_init ] ";" [ expression ] ";" [ for_post ] ;
for_in_header   = ident [ ":" type_name ] "in" expression ;
for_init        = var_stmt_no_semi
                | short_var_stmt_no_semi
                | typed_short_var_stmt_no_semi
                | assignment_no_semi
                | expression ;
for_post        = assignment_no_semi | expression ;
var_stmt_no_semi       = "var" ident [ ":" type_name ] "=" expression ;
short_var_stmt_no_semi = ident ":=" expression ;
typed_short_var_stmt_no_semi = ident ":" type_name ":=" expression ;
assignment_no_semi     = assign_target "=" expression ;

assignment      = assign_target "=" expression [ ";" ] ;
assign_target   = ident | index_expr | member_expr ;

block           = "{" { statement } "}" ;

expression      = prefix_expr { infix_tail } ;
prefix_expr     = literal
                | ident
                | "(" expression ")"
                | if_expr
                | fn_lit
                | lambda_lit
                | spawn_expr
                | array_lit
                | map_lit
                | ("!" | "-" | "~") expression ;

infix_tail      = infix_op expression
                | call_suffix
                | member_suffix
                | index_suffix
                | cast_suffix ;

if_expr         = "if" expression block [ "else" ( block | if_expr ) ] ;
fn_lit          = "fn" [ ident ] "(" [ param_list ] ")" block ;
lambda_lit      = "|" [ ident { "," ident } ] "|" ( expression | block ) ;
                // Note: for empty parameter lists, the source form `|| expr` is allowed (lexer emits a single `||` token).
                // Rolling note: lambda params are currently untyped identifiers (no attrs, no varargs).
spawn_expr      = "spawn" expression ;
                // v0 restriction (all backends): `spawn` currently requires a call expression,
                // e.g. `spawn f(x, y)`; it does not spawn arbitrary expressions.
call_suffix     = "(" [ expression { "," expression } ] ")" ;
member_suffix   = "." ident ;
index_suffix    = "[" expression "]" ;

	array_lit       = "[" [ expression { "," expression } ] "]" ;
	map_lit         = "{" [ expression ":" expression { "," expression ":" expression } ] "}" ;

	// Numeric literals (rolling):
	// - int literals may be decimal or prefixed base (0x/0b/0o)
	// - `_` separators are allowed and ignored
	//
	// NOTE: negative numbers are represented as prefix expressions (`-` token + int literal),
	// not as a signed literal token.
	int_lit         = dec_int | hex_int | bin_int | oct_int ;
	dec_int         = dec_digit (dec_digit | "_")* ;
	hex_int         = "0x" hex_digit (hex_digit | "_")* ;
	bin_int         = "0b" ("0" | "1") (("0" | "1") | "_")* ;
	oct_int         = "0o" oct_digit (oct_digit | "_")* ;
	float_lit       = dec_int "." dec_int [ exp_suffix ]
	              | dec_int exp_suffix ;
	exp_suffix      = ("e" | "E") [ "+" | "-" ] dec_int ;

	literal         = int_lit | float_lit | string_lit | "true" | "false" | "nil" ;
	ident           = /[A-Za-z_][A-Za-z0-9_]*/ ;
	dotted_name     = ident { "." ident } ;
	type_name       = [ "*" { "*" } ] type_atom { "[" int_lit "]" } ;
	type_atom       = dotted_name
	                | "[]" dotted_name ;
attr            = "@" dotted_name [ "(" { /* literal args only (v0) */ } ")" ] ;
param           = { attr } [ "..." ] ident [ ":" type_name ] ;
param_list      = param { "," param } ;
match_pattern   = dotted_name [ "(" [ ident { "," ident } ] ")" ] ;
	infix_op        = "+" | "-" | "*" | "/" | "%"
	                | "<<" | ">>"
	                | "==" | "!=" | "<" | ">" | "<=" | ">="
	                | "&" | "^" | "|"
	                | "&&" | "||" ;
cast_suffix     = "as" type_name ;
```

## Operator Precedence (highest to lowest)
1. Member access: `.` and indexing: `[]`
2. Call: `()`
3. Cast: `as <type>`
4. Prefix: `!` `-` `~`
5. Multiplicative: `*` `/` `%`
6. Additive: `+` `-`
7. Shift: `<<` `>>`
8. Comparisons: `<` `>` `<=` `>=`
9. Equality: `==` `!=`
10. Bitwise AND: `&`
11. Bitwise XOR: `^`
12. Bitwise OR: `|`
13. Logical AND: `&&`
14. Logical OR: `||`

All infix operators are left-associative.

## Semantics

### Program structure and entry semantics (rolling, current toolchain)

Oren is a module language: a file contains top-level statements and declarations.

Entry behavior (current implementation across backends):

- **Top-level statements execute** in source order as the module loads (lowered into an internal `__top_level__` function).
- If a user-defined `fn main()` exists, the runtime may call it automatically depending on backend:
  - bytecode backend appends a `CALL main` entry stub if `main` exists (see `lib/compiler/codegen_bytecode/030_tail.oren`),
  - native backends use an entry stub that calls `main` (or `__top_level__` if `main` is absent; see `lib/compiler/arm64_elf.oren` / `lib/compiler/arm64_macho.oren`),
  - C backend emits a host `int main(...)` that executes top-level statements in order and then calls user `fn main()` if present (see `lib/compiler/transpiler.oren`).

Practical rule:

- For **native** and **AVM** builds, do **not** write `main()` as a top-level call unless you intentionally want `main` to run twice.
- For the **C backend**, do **not** write `main()` as a top-level call unless you intentionally want `main` to run twice.

Implementation note (C backend):

- User `fn main()` is emitted as a different C symbol to avoid colliding with the host `int main(...)` entrypoint; this is an internal detail and should not affect Oren source code.

Program termination (rolling):

- Do not rely on the **return value of `main`** for an exit code; backends do not yet agree on whether it is used.
- Use `exit(code)` for deterministic, portable termination semantics across all backends.

### C backend host toolchain selection (tooling contract; `--cc`)

The C backend produces a `.c` file and then invokes a host C toolchain to compile+link it.

- Toolchain selection is controlled by `oren build ... --backend c --cc <compiler>`.
- Default `--cc` behavior (rolling):
  - On POSIX hosts, default is `cc`.
  - On Windows hosts, default is MSVC `cl.exe` (and the compiler attempts to auto-configure a VS environment via `vswhere.exe` + `VsDevCmd.bat`/`vcvars64.bat` so a VS Developer Prompt is not required).
  - Cross-compiling a Windows C-backend artifact from a non-Windows host is not a first-class path; require an explicit `--cc` (e.g. MinGW cross compiler) to opt in.

### Stdlib import resolution (`std:` / `std/`) (toolchain contract)

The `import` statement stores a string module specifier. The compiler resolves that specifier at compile time.

In addition to filesystem-relative imports, the compiler implements a stdlib scheme:

- `std:` scheme form:
  - `import tcp "std:net/tcp"`
  - `import base64 "std:encoding/base64"`
- `std/` path form:
  - `import tcp "std/net/tcp"`

Resolution rules (current implementation; see `lib/compiler/compiler/010_cli_helpers.oren`):

- `.oren` extension is optional (it is appended when the last path segment has no `.`).
- The compiler resolves `STDLIB_ROOT` by:
  1) `OREN_STDLIB_ROOT` (either `.../lib/std` or an install root containing `lib/std`)
  2) walking up from the importing file directory looking for `lib/std/argparse.oren`
  3) falling back to `lib/std` relative to the current working directory
- If stdlib root cannot be resolved, `import "std:..."` / `import "std/..."` is a compile-time error.

This is a compile-time mechanism (there is no runtime module loading in v0).

### Target platform configuration (toolchain contract; affects `@cfg`)

While the language grammar is platform-neutral, some compile-time behavior depends on the **selected target platform**:

- native backend codegen selection (`arm64-*` vs `x64-*`)
- conditional compilation via `@cfg(...)` / `@oren.cfg(...)`

The compiler chooses the platform using this priority order:

1) CLI: `--platform <arch>-<os>` (preferred)
2) Env fallback: `OREN_PLATFORM=<arch>-<os>`
3) If neither is provided: host auto-detection (Windows uses env; POSIX uses `uname`)

Rolling Tier‑1 platforms (current project intent / regression focus):

- `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`

### Conditional compilation (`@cfg(...)` / canonical `@oren.cfg`)

`@cfg` is a compiler directive attribute used for **minimal conditional compilation**.

Status: **Rolling (implemented)**.

Semantics:

- `@cfg(...)` is evaluated at compile time using the selected target platform (see above).
- If a declaration or statement does not match its `@cfg`, it is **removed** from the program before later passes and before codegen.
- If the target platform is unknown/missing, using `@cfg` is a compile-time error.

Non-normative guidance (rolling):

- Prefer platform-independent APIs in stdlib. `@cfg` exists for *boundary bindings* that cannot be fully abstracted (FFI library names, syscall layouts, per-OS constants).
- In tests, `@cfg` is acceptable when it gates tiny platform-specific declarations, but the behavior under test should remain consistent across Tier‑1 platforms whenever possible.
- If broad algorithmic code needs heavy `@cfg`, treat it as a design smell and consider lifting the platform differences into a dedicated stdlib module.
- See `docs/DESIGN.md` for concrete “keep `@cfg` at the boundary” patterns.

Supported attachment sites (rolling v0):

- Declarations: `fn`, `struct`, `ffi`, `var`
- Statements inside blocks (e.g., `@cfg("debug") print("...")` or `@debug print("...")`)
- Not supported: arbitrary expressions (use statement-level form)
- Not supported yet: `import`
  - Reason: stage2 has a lexer-only fast import scan that cannot respect conditional imports.
  - Workaround: keep imports stable and gate platform-specific declarations *inside* imported modules.

Constraint (rolling, practical):

- When `@cfg` is used to define multiple platform variants of the same declaration name, the variants must be mutually exclusive; otherwise multiple variants can survive filtering and produce duplicate definitions.

Selector forms (rolling v0):

- Positional selector string (exactly one positional arg):
  - OS match: `@cfg("linux")` / `@cfg("macos")` / `@cfg("windows")`
  - Arch match: `@cfg("x64")` / `@cfg("arm64")`
  - Platform match: `@cfg("x64-windows")`, `@cfg("arm64-linux")`, etc.
  - Build profile: `@cfg("debug")` / `@cfg("release")`
- Keyword selectors (CSV strings; AND across keys):
  - `@cfg(os="linux,macos")`
  - `@cfg(arch="x64")`
  - `@cfg(platform="arm64-linux")`
  - Negation keys: `not_os`, `not_arch`, `not_platform`
  - Build profile: `@cfg(debug=true)` / `@cfg(debug=false)`

Build-profile note (rolling):

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

Note on naming:

- The compiler canonicalizes `@cfg` to `@oren.cfg` in metadata.
- The compiler canonicalizes `@debug` / `@release` to `@oren.debug` / `@oren.release`.

Addendum: `ffi("...")` sugar (rolling, parser-only)

- The parser accepts `ffi("lib") <sym>` and `ffi("lib") { ... }` as sugar for attaching a dynamic library to one or more `ffi` declarations.
- Semantics: `ffi("lib") ...` lowers as if the user wrote `@ffi.link("lib") ffi ...` (portable form).
- This does not introduce a new attribute; it is a syntax convenience for fixtures and quick bindings.
  - Note: group items accept the same rolling separators as `ffi { ... }`:
    - commas/semicolons are optional
    - one-symbol-per-line blocks are valid (implicit separators between items)

### Notes on current (rolling) type annotations

Oren is still in rolling mode without a full static type checker, but the parser already supports
**explicit type annotation syntax** because it is required for:

- syscall-first network/FFI structs (`u16be`, `u32be`, pointers like `*u8`, fixed arrays like `u8[16]`)
- deterministic packed-byte views (`@pack` + field `name: u16be`)
- method sugar resolution (static-first): `x: Type; x.method(...)` can lower to an impl method

Where type annotations can appear today:

- locals: `var x: u64 = ...`
- typed short var: `x: u64 := ...`
- function params: `fn f(x: u64) { ... }`
- struct/class fields: `struct S { len: u16be, bytes: u8[16] }`
- imported types (alias-qualified): `import it \"mod.oren\"; var r: it.MyRange = it.new_range(...)`

#### Rolling v0 “kind annotations” for container sugar

While the full type system is still rolling, some backends require additional information
to lower builtin container method sugar deterministically (notably where runtime values are not
safely tagged).

Oren therefore allows a small set of *conventional* annotation spellings to act as container-kind hints:

- `: list` — list receiver (enables `xs.push(v)` / `xs.len()` lowering)
- `: map` — map receiver (enables `m.len()` lowering)
- `: buf` — typed buffer receiver kind (enables `b.len()` lowering when element width is not relevant)
- `: string` — string receiver (enables `s.len()` lowering)

These are hints used by compiler lowerings in rolling v0; they are not yet “real types” in the v1 sense.

Additionally (rolling, native backends):

- numeric annotations like `: int`, `: i64`, `: u64`, ... are treated as an **“int kind” hint** for deterministic map key-kind inference (avoids runtime pointer/int heuristics in x86_64 native bring-up)
- typed buffer annotations of the form `[]T` (e.g. `[]i32`, `[]f64`) are treated as a **“buf kind” hint** for receiver sugar like `b.len()`

Typed buffers also have a width-specialized type spelling used throughout the HPC stdlib:

- `[]i32`, `[]i64`, `[]f32`, `[]f64`, `[]u8`, ...

Example:

```oren
import buffer "std:buffer"

var b: []i32 = buffer.i32_new(16)
```

Type names like `u8`, `i32`, `f64`, `u16be`, etc. are **language-reserved tokens** intended to
become true explicit types as the v1 type system is stabilized (see later sections in this spec).

### Meta / Attributes (declaration annotations) (design direction)

Oren adopts a **unified attribute model** for “decorators” and “field annotations”.
The syntax is inspired by Python’s `@decorator`, but the semantics are intentionally different:

- **Python:** `@decorator` is runtime function transformation (`f = decorator(f)`).
- **Oren:** `@attr(...)` is **compile-time metadata**, not arbitrary code execution.

This design is chosen to preserve:

- deterministic builds
- AVM governance and policy scan safety (scan-before-execute)
- multiverse friendliness (metadata must not change semantics unless explicitly specified)

#### Syntax (conceptual)

Attributes attach to declarations:

- functions
- types (`struct` / future `enum` / future `trait`)
- impl blocks (future)
- parameters (future)
- fields (future)

Rolling status note (implementation reality):

- Attributes are implemented today for: functions, types, parameters, and fields.
- Some attributes are pure metadata, while a small reserved set are compiler directives
  (e.g. packed byte views / ABI layouts).

Example (function):

```oren
@trace("net.connect")
@cap.requires(domain="NET", ops=["tcp_connect"])
fn tcp_connect(ip, port, timeout_ms) { ... }
```

Example (field annotation):

```oren
struct User {
    @doc("database primary key")
    @serde.rename("user_id")
    id
}
```

#### Determinism rules (must-haves)

1) **Unknown attributes are allowed and inert by default**
   - If the compiler does not recognize an attribute, it must not change code generation, execution, verification, gas/time, or policy scan results.
   - Unknown attributes may be preserved for tooling (docs/IDE/disasm metadata), but are semantically ignored.

2) **Attribute arguments are compile-time constants (v0)**
   - Allowed: `int`, `bool`, `string`, `nil` (and later: constant list/map literals if/when const-literals are formalized).
   - Not allowed in v0: arbitrary expression evaluation or calling functions inside attribute arguments.

3) **Reserved namespaces**
   - Compiler/tool-reserved: `oren.*`, `avm.*`, `cap.*`, `ffi.*`, `codegen.*`, `trace.*`

  4) **Ergonomic aliases (surface syntax)**
   - For readability, the compiler accepts a small set of short aliases and canonicalizes
     them before strict-mode validation and before emitting metadata.
   - Canonical form is what gets embedded into `.obc` metadata / `--metadata` JSON.
   - Current aliases:
     - `@pack` → `@oren.packed`
     - `@abi` → `@oren.abi`
     - `@json.*` → `@serde.*` (serde namespace is canonical for tooling + future codegen)

     - `@cfg` → `@oren.cfg` (conditional compilation directive)

#### Stdlib impact: JSON serde (rolling plan)

The primary near-term reason attributes exist in this repo is **compile-time-governed serde**:

- `@serde.rename("wire_name")` for field/key remapping
- `@serde.skip()` to omit a field
- `@serde.default("...")` / `@serde.default(0)` (literal-only in v0) for missing fields

**Determinism rule:** serde attributes must not introduce runtime code execution. They are metadata only.

Implementation staging (rolling):

1) Preserve attrs through parsing/linking and expose them to tooling (native `--metadata`, and embedded `.obc` metadata).
2) Provide `std/json` that is portable across backends (no reliance on runtime reflection).
3) Add attribute-driven codegen helpers (compiler plugin phase / macro phase), or AVM metadata query primitives, to enable ergonomic `json.encode(User{...})` / `json.decode(User, "...")`.
   - Library/user metadata should use a vendor prefix (recommended): `myorg.*`, `acme.*`, etc.

4) **Strict attribute mode (governance)**
   - For audited builds (and later swarm consensus workflows), Oren should support a strict mode:
     - unknown attributes are a compile error unless explicitly declared/allowed
     - reserved namespace misuse is always an error

#### Hashing and artifact identity (important for swarm / consensus)

If/when `.obc` gains a metadata section that contains attributes:

- **Execution identity** (`program_hash`) must be derived from semantics (code + constants), not from inert metadata.
- Metadata may have its own hash (`meta_hash`) for auditing/debugging, but must not affect consensus execution identity.


#### Trait ergonomics (direction)

To avoid boilerplate (e.g. implementing `Eq`/`Add` for every integer width), Oren’s trait system should support:

- **default methods** in trait definitions
- **blanket impls / generic impl templates** (later) with strict coherence rules
- **derive-style expansion** (attribute-driven) for structural/data traits like serde

This stays compatible with AVM determinism because resolution is compile-time and overlap is forbidden (or must be explicitly disambiguated).

### Values and Types
The runtime is dynamically typed. Values include:
- `nil`
- `bool` (`true`/`false`)
- `int` (signed 64-bit in the C runtime; two’s complement)
- `float` (**IEEE-754 binary64 / float64**)

### Varargs (rolling)

Oren supports **varargs parameters** at the end of a parameter list:

```oren
fn sum(x, ...rest) {
    // `rest` is a list of extra arguments (possibly empty).
    return x
}
```

Semantics (v0 / rolling):

- Only one varargs parameter is allowed, and it must be the **last** parameter.
- The varargs binding is always a **list** (possibly empty).
- Calls may supply **zero or more** extra arguments:
  - `sum(1)` binds `rest = []`
  - `sum(1, 2, 3)` binds `rest = [2, 3]`

Backend note (rolling):

- Backends may lower varargs through wrapper calls or call-site packing, but the observable semantics
  must remain the same across C/native/AVM bytecode.
- `string` (byte string)
- `list` (ordered, **heterogeneous**)
- `map` (keyed, deterministic iteration order; see “deterministic maps contract”)
- `python object` (opaque wrapper used by the optional Python FFI)

#### Lists are heterogeneous (by design)

Oren `list` is a heap container of dynamic values (a `list<OrenValue>` conceptually):

- A list may contain mixed types: `[1, "two", nil, true]`.
- Indexing (`xs[i]`) returns a dynamic value.
- `for x in xs { ... }` iterates elements in index order.

If you need **homogeneous memory layout** (HPC/FFI/SIMD kernels), the v0 path is:

- **typed buffers** (planned/partial) rather than forcing `list` to become homogeneous.

#### Numeric model (important for cross-backend correctness)

Oren currently has *one* scalar floating-point type:

- `float` is **float64** (binary64).

Implementation reality today:

- **C backend:** stores `float` as a C `double` (`OREN_TYPE_FLOAT`).
- **Native backend (ARM64):** represents `float` values as the **raw 64-bit IEEE-754 bit pattern** in a 64-bit register; floating ops use dedicated intrinsics (`fadd/fsub/fmul/fdiv`) and preserve bit-level results.
- **AVM:** float64 is now wired end-to-end in the bytecode backend and VM:
  - float literals compile into `.obc` as **f64 bit-pattern constants**
  - arithmetic `+ - * /` and comparisons `< <= > >=` support numeric mixing (`int`/`float`) similar to the C runtime
  - `+` also supports string concatenation (`"a" + "b"`)

  This is still **rolling** (no stable ISA guarantee yet), but it is now covered by canonical AVM tests.

Important rolling note:

- Operator-level float arithmetic is rolling and was historically inconsistent across backends:
  - **C backend / AVM:** `+ - * /` on floats works directly.
  - **Native backend (ARM64):** `+ - * /` now lowers to FP ops when the compiler can prove the expression is “floaty” (float literals, float intrinsics, and locals/globals assigned from floaty expressions). Otherwise it remains integer/pointer arithmetic.

  This is a pragmatic v0 bridge until Oren has a stronger type story for numeric operators.

If you need **float32** in v0, the recommended path is **typed buffers** (`F32_BUF`) rather than introducing a second scalar float tag immediately (see “Planned” below). This avoids a large cross-backend rewrite of the dynamic value representation.

#### Default widths vs explicit widths (recommended policy)

Oren is currently dynamically typed, but numeric *width* still matters for:

- scientific computing (typed buffers, SIMD kernels)
- stable cross-platform serialization
- FFI and system boundaries

Recommended policy (minimal rewrite, maximum clarity):

1) **Keep ergonomic defaults**
   - `int` is signed 64-bit (`i64`) in the reference runtime today.
   - `float` is `f64` (binary64) today.

   These defaults are chosen because they:
   - avoid “pointer-width drift” across targets
   - are easier to keep deterministic across backends (C/native/AVM)
   - are generally sufficient for orchestration logic (agent workflows)

2) **Add explicit fixed-width numeric types (for performance + correctness)**
   - Signed/unsigned integers: `i8/i16/i32/i64/i128` and `u8/u16/u32/u64/u128`
   - Floats: `f32` and `f64`

   These should be used for:
   - typed buffers (`F32_BUF`, `I32_BUF`, etc.)
   - binary protocols / hashing / stable encodings
   - FFI boundaries where exact size matters

3) **Treat `usize`/`isize` as “FFI/pointer boundary types” (optional, later)**
   - If introduced, `usize` must be defined precisely as “pointer width of the target”.
   - For deterministic `.obc` / AVM workflows, prefer fixed widths (`u64`) unless the program is explicitly declared “native-only”.

Design note:

- Introducing fixed-width numeric types does not require a full static type system on day 1.
  A staged approach can start with:
  - typed buffers and numeric ops that explicitly operate on `F32_BUF`/`I32_BUF`
  - literal suffixes for compile-time constants (e.g., `1u32`, `1i64`, `1.0f32`) later
  - explicit conversion builtins (`u32(x)`, `i64(x)`, `f32(x)`) once semantics are defined
  - only later (optional) a broader static type checker

### Truthiness
- `nil` is falsey
- `false` is falsey
- everything else is truthy

### Variables and Scope
- `var name = expr` and `name := expr` declare a new variable in the current scope.
- `name = expr` assigns to an existing variable. Assigning to an undeclared name is an error.
- Scopes are **lexical**:
  - globals (top-level `var`)
  - function scope
  - block scope (`{ ... }`) where variables may shadow outer names

#### Type-annotation syntax (rolling, hybrid semantics in v0)

Oren supports a universal type-annotation sugar:

- `var x: u64 = expr`
- `x: u64 := expr`
- `for x: T in iterable { ... }`
- `fn f(x: T, y: U) { ... }`
- `fn f(x: T): U { ... }`

In **v0**, annotations are a **rolling hybrid**:

- Oren remains dynamically typed at runtime, but the compiler already consumes some annotations in deterministic lowering passes.
- Annotations are **inert by default** unless a specific lowering pass defines deterministic semantics.

Current semantics (implementation reality):

- `bool`: deterministic normalization via `oren_bool_norm(x)` (avoids backend-specific “truthiness” mismatches)
- small integers (`u8/i8/u16/i16/u32/i32`): deterministic wrap/truncate casts at field init, local init, and function boundaries
  - integer casts accept **int or float** inputs
  - float inputs truncate toward zero first (via `oren_trunc_int(x)`), then wrap/truncate to the target width
    - `NaN` becomes `0`
    - float values outside int64 range clamp deterministically:
      - `+inf`/overflow → `INT64_MAX`
      - `-inf`/overflow → `INT64_MIN`
- `f32`: deterministic rounding boundary (via `oren_f32_round(x)`); `f64` remains the default float precision
- endian-tagged integer kinds (`u16be`, `u32le`, etc.) are treated as the same width for value casts, but matter for packed-byte views and ABI layouts

Other annotations are currently metadata-only and exist primarily for tooling and future stabilization (v1).

Type names like `u8`, `i32`, `f64`, `u16be`, etc. are **language-reserved type tokens** intended to become true explicit types as the v1 type system is stabilized.

Important rolling note on `i128/u128`:

- The syntax tokens exist and are usable in ABI/layout contexts (`@abi` structs, `sizeof`/`offsetof`).
- Full runtime-semantic `i128/u128` arithmetic is **not** stabilized yet; until it is, treat `i128/u128` as **ABI/layout-only** rather than as a general numeric type in expressions.

Implementation note (current compiler):

- The lexer recognizes these as dedicated tokens (not plain identifiers).
- The parser treats them as **identifier-like** in expression/dotted-name contexts, so existing code such as `ints.u8(x)` continues to work.

### Control Flow
- `if cond { ... } else { ... }` executes a block based on truthiness of `cond`.
  - The grammar treats `if` as an expression, but the C backend only supports it in statement position.
- `while cond { ... }` repeats while `cond` is truthy.
- `for` has two forms:
  - Condition-only: `for cond { ... }`
  - Three-clause: `for init; cond; post { ... }`
- `for <name> in <iterable> { ... }` is iterator sugar (rolling).
- `for <name>: <Type> in <iterable> { ... }` is the same, with an annotation on the loop binding:
  - in v0 this does **not** require `<iterable>` to be homogeneous
  - it is primarily for readability, tooling, and future type-checking
  - It is a source-level desugaring that relies on a runtime hook `oren_iter_next(iterable, idx, out_pair)`.
  - Iterator hook contract:
    - `oren_iter_next(container, idx:int, out_pair:list|nil) -> [ok:int, value]`
    - `out_pair` is a reusable list buffer (length ≥ 2) used to avoid per-iteration allocations
    - `ok == 1` means `value` is valid for this `idx`
    - `ok == 0` means iteration is complete
  - Current container coverage (rolling):
    - `list`: yields elements in index order
    - `map`: yields **keys** in deterministic key order (see deterministic maps contract)
    - `string`: yields byte codepoints (`0..255`), stopping at NUL terminator
    - `bytes` (AVM): yields `u8` values (`0..255`)
    - `generator`: resumes with implicit `nil` and yields each produced value until completion
    - typed numeric buffers: yields element values (`i32/i64/f32/f64`) in index order
    - typed buffer view lists (portable stdlib encodings):
      - slice view: `[buf, off, len]`
      - strided view: `[buf, off, len, stride]`
      - these iterate element values (not metadata fields)
  - Streams / iterators beyond these built-ins (rolling):
    - v0 supports a minimal, portable “data iterable” protocol: an **iterable map** with the marker key `__iter`.
    - Backends may recognize these objects inside `oren_iter_next` to implement stream-like iteration
      without adding new VM value kinds.
    - Safety rule (native backend): because values are not tagged at runtime, implementations must not call
      string functions (e.g. `strcmp`) on non-strings. In practice, the runtime treats `__iter` as a tag only
      when it is a valid string value (and compares tags by string bytes, not pointer identity).
    - Initial supported adaptor: `range` (stdlib helper `lib/std/iter.oren`):
      - `iter.range(n)` yields `0..(n-1)`
      - `iter.range3(start, end, step)` yields `start, start+step, ...` while:
        - `step > 0`: value `< end`
        - `step < 0`: value `> end`
        - `step == 0`: yields an empty sequence (deterministic; avoids hangs)
      - Representation (implementation detail, rolling):
        - `{"__iter":"range","start":0,"end":N,"step":1}`
  - Trait-based iterable extension (rolling v1, static-first, no vtables):
    - If the loop iterable is a **bare identifier** (e.g. `for x in it { ... }`) and `it` has a known
      type annotation in scope, the compiler may rewrite the underlying iterator hook call:
      - source desugaring: `oren_iter_next(it, idx, out_pair)`
      - rewrite (if available): `__oren_impl__Iterable__<Type>__iter_next(it, idx, out_pair)`
    - To opt in, define:
      - `trait Iterable { fn iter_next(self, idx, out_pair); }`
      - `impl Iterable for MyType { fn iter_next(self, idx, out_pair) { ... } }`
    - This allows custom deterministic iterables (streams/ranges/adaptors) without adding runtime value kinds,
      and without runtime vtables in hot loops.
    - If no `Iterable` impl is present, behavior falls back to the normal v0 hook (`oren_iter_next`).
- `break` exits the nearest enclosing loop (`while`/`for`).
- `continue` skips to the next loop iteration.
- `for init; cond; post { ... }` three-clause form: `continue` executes the `post` clause before re-checking `cond`.
- `return expr` returns from the current function. A return value is always required; use `return nil` if needed.

### Builtin container method sugar (rolling)

Oren supports a small amount of container method sugar to keep code modern and readable,
while still lowering deterministically in v0:

- `xs.push(v)` → `oren_list_push(xs, v)` (**returns `nil`**)
- `xs.len()` → `oren_list_len(xs)`
- `m.set(k, v)` → `m[k] = v` (**statement-only sugar**)
- `m.get(k)` → `m[k]`
- `m.len()` → `oren_map_len(m)`
- `b.len()` → `oren_buf_len(b)`

Important: this is **best-effort** in rolling v0. The lowering only applies when the compiler
can infer the receiver kind from syntax/local assignments (needed because the native backend
runtime values are untagged).

### Concurrency (v0)
Rolling note: Oren has **multiple execution backends** (C, native, AVM). The syntax surface is shared,
but concurrency is still **rolling** and backend-specific.

#### `spawn` / `join` (exists today; backend-dependent)

- Surface syntax:
  - statement form: `spawn f(x, y)`
  - expression form: `var h = spawn f(x, y)`
- **Evaluation**: argument expressions are evaluated in the parent context before spawning.
- Return value: a backend-defined “handle” (opaque integer/pointer; treated as `Any` in v0).

Backend behavior (rolling):

- **AVM backend**: `spawn` creates a **deterministic VM task** (green thread) scheduled by the AVM runtime.
  - `oren_join(handle)` and `oren_yield()` are VM opcodes (portable, snapshot-safe).
  - See `docs/DESIGN.md#avm-and-obc-bootstrap-spec-summary` (Next-Gen plan section: tasks + channels + select).
	- **C backend**: `spawn` uses `pthread_create` and returns a pointer-like handle.
	  - `oren_join(handle)` waits and returns the spawned function’s return value.
	  - `oren_detach(handle)` / `oren_join_all()` exist in the C runtime (rolling; not yet mirrored in native runtime).
		- **Native backend (Tier‑1, rolling)**:
		  - **POSIX (macOS/Linux)**: `spawn` **prefers in-process green tasks** (shared heap), and falls back to syscall-first **fork + pipe**
		    when green tasks are disabled/unavailable.
		    - Escape hatch: `OREN_NO_GREEN=1` forces legacy fork+pipe (bring-up/debugging).
		    - Fork+pipe handle layout (implementation detail): `[pid, read_fd]` stored in a small heap object.
		    - `oren_join(handle)` waits for child termination and reads the return value from the pipe.
		  - **Windows x64**: `spawn` is implemented via **CreateThread** (no `fork` on Windows), routed through the same native runtime helper
		    (`oren_spawn_call_list`) as POSIX.
		    - `oren_join(handle)` waits via `WaitForSingleObject` and returns the worker’s result.
		    - `oren_join_timeout(handle, timeout_ms)` exists and returns `-60` on timeout (rolling contract).
		  - Note: this is a rolling convergence surface; the long-term direction is a unified thread-based substrate on all native targets (see `docs/LANGUAGE.md`).

#### Channels + `oren_select*` (rolling; AVM + native)

Two low-level concurrency primitives exist today as **runtime builtins** (not keywords):

- `oren_new_channel() -> ch`
- `oren_chan_send(ch, val) -> ok` (rolling: returns `1`)
- `oren_chan_recv(ch) -> val` (blocks if empty)
- `oren_select_recv([ch1, ch2, ...]) -> [idx, val]` (blocks until any channel has a queued value)
- `oren_select(cases) -> [idx, payload]` (blocks)
  - case encoding (data):
    - recv case: `[0, ch]`
    - send case: `[1, ch, val]`
  - payload:
    - recv: received value
    - send: `1` (rolling “ok” marker)

Backend behavior (rolling):

- **AVM backend**: channels + select are **VM opcodes** (deterministic + snapshot-safe).
- **Native backend**:
  - On macOS: implemented over **pipes + kqueue/kevent**.
  - On Linux: implemented over **pipes + epoll**.
  - On Windows: implemented over **in-memory channels** (pipe-fd readiness/select is POSIX-only; Windows has a rolling select-v0 socket netpoll path, but IOCP is still the intended long-term “real netpoller”).
  - See `lib/runtime_native/010_channels_globals_consts.oren`, `lib/runtime_native/011_channels_mem.oren`, and `lib/runtime_native/245_select.oren`.

Design direction:

- A future language-level `select { case ... }` syntax is planned as sugar over `oren_select(...)`,
  after the CoreIR + scheduler model stabilizes (see `docs/LANGUAGE.md` and `docs/DESIGN.md#runtime-and-stdlib-layering`).

### Functions
- `fn name(params) { ... }` defines a named function.
- Calls: `f(x, y)`
  - Calls to Oren-defined functions compile to direct C/Native calls.
  - Calls to Python objects use the runtime’s `oren_call_obj`.

#### First-class functions and lambdas (v0)

- Functions are **first-class values**:
  - A function identifier in expression position yields a callable function value (usable as an argument, stored in variables, returned from other functions).
  - Lambdas are anonymous functions: `|x, y| x + y` and empty-params lambdas `|| expr`.
  - Lambdas can also have a **full block body** (multi-line, locals, control flow), using braces:
    - `|n| { var acc = 0; while acc < n { acc = acc + 1 }; return acc }`
- Calling a function value uses the normal call syntax: `f(1, 2)`.
- `spawn` also uses normal call syntax and can spawn calls to function values/closures (not only direct function symbols).

#### Lambdas and closure capture semantics (v0)

- Lambdas **auto-capture** free variables from their surrounding scope.
- Capture is **by value** (snapshot at lambda creation time), not by reference.
- The capture list order is deterministic (source-order of first use), which is important for replayability/consensus in deterministic modes.

#### Fixed arity vs variadic calls (rolling reality)

- User-defined Oren functions are **fixed-arity by default**, but **variadic parameters are implemented**:
  - Fixed arity: `fn f(a, b) { ... }` must be called as `f(x, y)` (exactly 2 args).
  - Variadic param (varargs): `fn f(...rest) { ... }` or `fn f(a, ...rest) { ... }`
    - `rest` is bound to a **list** of extra arguments (possibly empty).
- Some builtins are variadic (notably `print(...)`) and typically lower to a runtime helper that consumes a list of arguments.

**Status update (rolling):** call-site spread is implemented:
- Syntax: `f(xs...)` or `f(a, b, xs...)`
- `xs` must be a list at runtime (or `nil`).
- This supports variadic builtins and “apply-style” calls, and is also used by the implementation strategy for user-defined varargs across backends.

#### Runtime reflection helpers (rolling)

For varargs dispatch and debugging/logging, the runtime provides small reflection helpers:

- `oren_type_tag(v)` → int tag matching `lib/runtime.h` `OrenType` enum values.
- `oren_type_name(v)` → stable string name for that tag.

Stdlib wrapper (rolling):

- `lib/std/reflect.oren` provides `tag(v)` / `name(v)` wrappers and stable `TAG_*` constants.

Native backend note:

  - Until native value tagging is fully implemented, numeric immediates (`int`/`float`) may still be indistinguishable in some native-mode paths, so `oren_type_tag` is best-effort for those values.
    - Track: `docs/DESIGN.md#native-tagged-value-representation`
    - Rolling implementation detail: `nil`, `false`, and `true` are **runtime singleton values** in native mode (not raw `0/1`), so `0` (int zero) remains distinct from `nil`/`false` in the common case.
    - Rolling reflection v0 for structs: user-defined `struct` values are map-shaped today, but constructors tag them with `{"__oren_type":"TypeName", ...}`, so `oren_type_name(TypeName(...))` returns `"TypeName"` instead of `"map"`.
      - `__oren_type` is a **reserved** struct key; user code must not declare a field named `__oren_type` (compile-time error).
  - Guardrail (2026-01-10): the compiler rejects `bool/int/float == nil` comparisons when the scalar side is statically known (literals, casts, locally-proven scalars, or calls to functions with explicit scalar return annotations), and also when a value is later proven scalar by best-effort scan (e.g. `i64(x)` / `x & 255`, or arithmetic-with-literal on “maybe-nil” index-sourced values like `cfg["timeout_ms"]` after `if x == nil { ... }`).
    - This is intentional: scalars are not “optionals”; model missing values explicitly (`{"ok":1,"v":...}` / `{"ok":0}`) or use a tag-based check on truly dynamic values:
      - `if oren_type_tag(x) == 0 { ... }`
    - This guard is **always-on** (it does not require `--typecheck`). Diagnostics are tagged as `nil-compare guard: ...` so regressions are easy to spot.
    - Tooling note: `--typecheck` is an `oren build` option that enables an additional opt-in validation pass for annotated code (casts and annotated call/return boundaries). It is not required for the nil-compare guard.

### Compile-time execution (“comptime”) (design direction)

Oren should treat compile-time evaluation as a first-class concept, but it must stay aligned with the core niche:

- deterministic builds
- governance/capability model consistency
- AVM “compiler-in-AVM” viability (no host toolchain, no host effects by default)

Recommended staged model (minimal rewrite):

#### Stage C0: constant evaluation (pure, deterministic)

- Compile-time evaluation exists, but is limited to:
  - pure expression evaluation (numeric ops, string ops, bytes packing/unpacking helpers)
  - constant folding and constant propagation
- Forbidden at compile time:
  - FS/NET/PROC/ENV access
  - host time and nondeterministic RNG
- Compile-time evaluation is budgeted (gas/step cap) to prevent “compiler hangs”.

#### Stage C1: comptime functions (pure-only)

- Allow a restricted subset of function calls at compile time, with rules:
  - must be pure and deterministic
  - no host effects (capabilities default to CORE-only)
  - explicitly budgeted (gas/mem)

#### Stage C2: comptime reflection (bounded)

- Add only what is needed for tooling and safe codegen:
  - type queries (`type_of`)
  - field enumeration for structs (once structs become more than maps)
  - metadata generation

#### Stage C3 (optional, later): effectful comptime (explicit opt-in + recorded)

- If compile-time effects are ever allowed, they must be:
  - explicitly capability-scoped
  - record/replayable (like AVM effects)
  - bound into a “build job hash” so builds are auditable

Non-goal:

- Do not implement “arbitrary Zig-style comptime with host IO by default” early; that creates nondeterministic builds and forces large cross-backend rewrites.

### Lambdas (Closures)
- **Syntax**: `|params| expression` or `|params| { block }`
- **Semantics**:
  - Lambdas are first-class values.
  - They capture variables from their enclosing lexical scope (closures).
- **Examples**:
  ```oren
  var add = |a, b| a + b
  var x = 10
  var adder = |y| {
      return x + y  // captures x
  }
  ```

### Operators
- `+ - * / %`:
  - `int op int` yields `int`.
  - `int / int` is **signed** integer division with truncation toward zero.
  - `int % int` is the signed remainder consistent with trunc-toward-zero division (i.e. `a == (a / b) * b + (a % b)` and the remainder has the same sign as `a`).
  - Invalid cases are deterministic runtime panics:
    - division by zero
    - modulo by zero
    - signed overflow (`i64_min / -1`)
    - modulo overflow (`i64_min % -1`)
  - If either operand is `float`, arithmetic is performed in `float`.
  - `string + string` concatenates.
- `==` / `!=` are type-strict in the runtime (e.g., `1 == 1.0` is false).
- `< > <= >=`:
  - defined for numeric comparisons (`int`/`float`, mixed allowed) and lexicographic `string` comparisons
  - any other type combination is a runtime error
- `&&` / `||`:
  - evaluate operands using truthiness rules
  - short-circuit (right operand is evaluated only if needed)
  - result is a boolean (`true`/`false`)
- `& | ^ << >> ~` (bitwise / shifts):
  - only defined for `int`
  - operate on the 64-bit two’s-complement bit pattern of the integer value
  - `>>` is a logical (zero-fill) right shift
  - shift counts must be in `0..63`; out-of-range is a deterministic runtime panic
  - results wrap to 64 bits (any higher bits are discarded)

### Lists
- List literal: `[a, b, c]`
- Indexing: `xs[i]` (0-based; out-of-bounds or non-container access is a runtime panic)
- Index assignment: `xs[i] = v` (grows list to length `i+1`; new slots are `nil`; negative indices are a runtime panic)

### Maps
- Map literal: `{key: value, ...}`
- Lookup: `m[key]`
  - missing keys yield `nil` in the runtime
- Assignment: `m[key] = value`
- Duplicate keys in a map literal are unspecified; avoid them.

Rolling (important for native backends):

- The cross-backend, production-intent key kinds today are **`int`** and **`string`**.
  - C backend and AVM currently support additional key kinds (`nil`/`bool`) but native backends intentionally stay conservative until native value tagging is complete.
- Native backends must choose a key-compare strategy (`==` vs `strcmp`) deterministically.
  - If a key is a literal (`"name"` or `123`), the compiler can lower it deterministically.
  - If a key is a variable and the compiler cannot infer whether it is an `int` key or a `string` key, the native backends fail deterministically (panic) rather than guessing.
- Explicit runtime helpers exist to remove ambiguity when you know the key kind:
  - `oren_map_get_str(m, key)` / `oren_map_set_str(m, key, value)`
  - `oren_map_get_int(m, key)` / `oren_map_set_int(m, key, value)`
  - `oren_map_set_*` returns the written value (matches `xs[i] = v` returning `v`).

### Structs and Classes
- `struct Name { a, b, c }` and `class Name { a, b, c }` declare a nominal “shape” with a fixed set of field names.
- Construction:
  - `Name(v1, v2, v3)` constructs a new instance (fields in declaration order).
- Field access:
  - `p.a` reads field `a`.
- Field assignment:
  - Supported in v0:
    - `p.a = v` mutates the field (equivalent to `p["a"] = v` at runtime).

Notes (rolling reality):

- **v0 representation is map-shaped across backends**:
  - `struct` values behave like maps keyed by field name (`string`), but retain a nominal type name for tooling/metadata.
  - This avoids backend-dependent field-offset tricks until a stable static layout exists.
- For deterministic layout/view use-cases (FFI / packet parsing / HPC views):
  - use `@abi` (layout-only) and `@pack` (packed byte views); do not rely on v0 struct layout.

### Object Model (recommended direction)

Oren’s long-term object model is:

- **traits / protocols + composition** as the primary abstraction mechanism
- **no inheritance-first design** (avoid fragile class hierarchies)
- **ADTs (sum types)** + pattern matching for closed-world modeling (agent state machines, workflows) (planned)

Rationale:

- traits/protocols align naturally with syscall-first and capability-based design:
  - FS / NET / PROC / ENV / TIME should be explicit “capability objects” rather than implicit globals
- composition keeps data layout and ownership clearer across backends (C/native/AVM)
- sum types make “self-healing agent loops” more robust by encoding states explicitly

Implementation reality today (bootstrap):

- `struct`/`class` are currently **data-only** shapes backed by runtime maps.
- There is no method syntax and no inheritance.

Planned evolution (minimal rewrite):

1) Introduce `trait` (protocol) declarations as compile-time contracts.
2) Add `impl Trait for Type` (or structural conformance rules) with mostly static dispatch.
3) Add optional dynamic dispatch via “trait objects” only where needed (plugin systems).
4) Add `enum` + `match` for sum types and exhaustiveness checking (later milestone).

**Status update (rolling):** `enum` and `match` are now implemented as **syntax sugar** (no static type checker yet).
- The parser expands `enum` declarations into a set of constructor `fn`s that return tagged maps.
- `match` expands into a tag-switching `if/else` chain and optional payload bindings.
- Exhaustiveness checking remains a later milestone.

`match` is a **contextual keyword**: it may still be used as an identifier (e.g. `var match = 1`) unless the parser sees the statement form `match <expr> { ... }`.
**Status update (rolling):** `trait` and `impl` syntax are now accepted by the parser as compile-time-only constructs.
- `trait` declarations have no runtime effect yet.
- `impl Trait for Type { ... }` is lowered deterministically into plain top-level `fn`s (see `docs/LANGUAGE.md`).
- Design direction: Oren is **static-first** (`trait` = compile-time dispatch) with **explicit opt-in** runtime polymorphism (`dyn Trait`) when needed. See `docs/LANGUAGE.md`.

#### Rolling extension: blanket impl (`impl Trait for any`)

Rolling v0 also supports a minimal **blanket impl** syntax:

```oren
trait Z { fn z(self); }

impl Z for any { fn z(self) { return 0 } }
impl Z for i64 { fn z(self) { return 7 } }
```

Semantics (rolling, deterministic):

- `any` acts as a **fallback receiver** in the *impl receiver position only*.
  It is best treated as a **contextual keyword**: special in `impl <Trait> for any { ... }`, otherwise not a “real type”.
- Resolution prefers the most specific impl:
  - exact `(Trait, Type)` impl wins if present
  - otherwise use the `(Trait, any)` blanket impl if present
  - otherwise: compile-time error (“missing impl”)
- This is still **compile-time rewriting** (no vtables / no dynamic dispatch).

Evidence: `tests/modules/test_trait_blanket_impl_any.oren`.


Example:
```oren
enum Option { None, Some(x) }
var a = Option.None
var b = Option.Some(123)
print(a.tag)      // "Option.None"
print(b.tag)      // "Option.Some"
print(b._0)       // 123
```

`match` example:
```oren
var v = Option.Some(7)
match v {
    case Option.None { print("none") }
    case Option.Some(x) { print("some=" + oren_int_to_string(x)) }
    default { print("other") }
}
```

### Modules and Imports
- `import math "path/to/math.oren"` compiles the referenced file as a module and binds it to the identifier `math` as a **namespace**.
- Accessing module members uses member syntax:
  - `math.PI`
  - `math.sqrt(2.0)`
- Import paths are resolved at compile time using the compiler’s module resolver:
  - **Filesystem imports**: relative to the directory of the importing file; absolute paths are allowed.
  - **Stdlib imports (recommended for users)**:
    - `import math "std:math"` (canonical scheme form)
    - `import json "std/json"` (path form; accepted as an alias of `std:json`)
    - The `.oren` extension is optional (e.g. `"std:json"` or `"std/json"` may resolve to `lib/std/json.oren` depending on the stdlib layout).
- Imports are resolved recursively at compile time; cyclic imports are an error.
- All top-level `var`, named `fn`, and `struct`/`class` declarations in an imported file are treated as module members.

Rolling restriction (current behavior):

- `import` is **compile-time only** and only meaningful at **module top level**.
  - The parser may accept `import` inside blocks, but backends treat imports as compile-time only; a block-scoped import is not meaningful.
  - This is expected to become a compile-time error in a future rolling milestone (so tools and AI agents should always emit top-level imports).

## Evaluation Order
Expression evaluation order is currently not specified by the language (rolling v0).

Status:

- **Rolling**: current compilers/backends are free to choose internal evaluation strategies.
- **Planned**: specify a stable evaluation order (or an explicit effect model) so optimizations are semantics-preserving across backends. Track: `docs/STATUS.md` (P0.2).

Practical guidance (all backends):

- Avoid relying on side effects inside subexpressions (especially in function call arguments and binary operators).
- If order matters, write explicit sequencing using `var` bindings:
  - prefer:
    - `var a = f()`
    - `var b = g()`
    - `h(a, b)`
  - over:
    - `h(f(), g())`

This matters even more in rolling mode because compilers may apply safe transforms like tail-call elimination (stackless recursion) and other normalizations, and without a specified order there is no portable “happens-before” guarantee inside an expression.

## Builtins (C Backend)
The C backend recognizes a few builtin functions and lowers them directly:
- `print(...)` → `oren_print(...)` / `oren_print_multi(...)`
- `py_import("name")` → `oren_py_import(...)`
- `system("cmd")` → `oren_system(...)`
- `exit(code)` → `oren_exit(...)`

## Runtime Builtins (Self-Hosting and Native Backend)
The self-hosted compiler and the (in-progress) native backend rely on a few additional runtime helpers:
- `oren_write_bytes(path, bytes)` writes bytes (`list<int 0..255>` or `u8_buf`) to a file (binary-safe).
- `oren_read_bytes(path)` reads a file as a list of byte values (`0..255`) (binary-safe; preserves `0x00`).
- `oren_bytes_from_string(s)` converts a string to a list of byte values (`0..255`).
- `oren_sha256_range(bytes, start, length)` computes SHA-256 over a subrange of a byte list and returns a 32-byte list.
- `oren_chmod(path, mode)` calls `chmod(2)` (used to set the executable bit on generated binaries).

### Endian-aware byte casting (network order)

Parsing network packets is a core requirement for syscall-first `.oren` libraries. Oren provides **deterministic**, **libc-free** helpers for reading integers from byte sequences with explicit endianness.

Current v0 reality:

- “bytes” are commonly represented as `list<int 0..255>` (from `oren_read_bytes`, sockets, etc.).
- Integers are currently dynamic `int` (signed 64-bit across backends).

Helpers (v0):

- `oren_bytes_get_u16_be(bytes, off)` / `oren_bytes_get_u16_le(bytes, off)`
- `oren_bytes_get_i16_be(bytes, off)` / `oren_bytes_get_i16_le(bytes, off)`
- `oren_bytes_get_u32_be(bytes, off)` / `oren_bytes_get_u32_le(bytes, off)`
- `oren_bytes_get_i32_be(bytes, off)` / `oren_bytes_get_i32_le(bytes, off)`
- `oren_bytes_get_u64_be(bytes, off)` / `oren_bytes_get_u64_le(bytes, off)`
- `oren_bytes_get_i64_be(bytes, off)` / `oren_bytes_get_i64_le(bytes, off)`
- `oren_bytes_put_u16_be(bytes, off, v)` / `oren_bytes_put_u16_le(bytes, off, v)`
- `oren_bytes_put_u32_be(bytes, off, v)` / `oren_bytes_put_u32_le(bytes, off, v)`
- `oren_bytes_set_u64_be(bytes, off, v)` / `oren_bytes_set_u64_le(bytes, off, v)` (mask/truncate semantics)

Example:

```oren
// IPv4 header layout (partial):
//   u8  ver_ihl
//   u8  dscp_ecn
//   u16 total_len (BE)
//   ...
var pkt = oren_read_bytes("ip.bin")
var total_len = oren_bytes_get_u16_be(pkt, 2)
```

Error behavior (portable rule):

- On invalid arguments (wrong type, out-of-bounds, byte out of range), these helpers return a **structured error object** (`oren_err(OREN_ERR_INVALID_ARG, "...")`), not UB.
- Use `oren_is_err(v) -> bool` to test for this in a backend-portable way:
  - `if oren_is_err(x) { ... }`
  - Do **not** treat numeric `0/1` as booleans: in Oren, `0` is truthy; only `nil` and `false` are falsey.
- Stdlib note: `std:result.is_err(v)` canonicalizes backend error probes to a real Oren boolean
  (`true` / `false`), so comparisons such as `result.is_err(x) == true` stay portable across
  native and AVM.
- Stdlib note: `std:bytes` now exposes checked wrappers for the common packet, slice/copy, and
  conversion helpers, including signed and 64-bit writes such as `bytes.try_get_u16_be`,
  `bytes.try_get_u32_le`, `bytes.try_put_i16_le`, `bytes.try_put_i32_be`, `bytes.try_put_u64_le`,
  `bytes.try_put_i64_be`, `bytes.try_set_i32_le`, plus conversion helpers such as
  `bytes.try_from_string`, `bytes.try_to_string`, `bytes.try_pack`, `bytes.try_unpack`,
  `bytes.try_slice`, `bytes.try_concat`, `bytes.try_copy_into`, `bytes.try_from_u8_buf`,
  `bytes.try_to_u8_buf`, `bytes.try_to_string_slice`, and `bytes.try_to_u8_buf_slice`, so
  application code can stay on the portable structured-error surface instead of calling raw
  `oren_bytes_*` helpers directly.

Future direction (syntax sugar; no rewrite required):

- Add cast syntax that can specify byte order explicitly, e.g.:
  - `total_len = bytes[2..4] as u16@be`
  - `total_len = u16@be(bytes, 2)`

Until fixed-width scalar types are stabilized across all backends, these helpers are the portable, production-friendly way to parse protocol headers.

## Value Model: v0 “Mutable Handles” (and the future direction)

Oren v0 is **dynamically typed at runtime** and uses a pragmatic value model:

- Scalar values (`int`, `bool`, `float`) are immediate.
- Compound values (`string`, `bytes`, `list`, `map`, `struct`, `closure`) are **handles** to heap objects.
  - Passing a value copies the handle (pointer-sized), not a deep copy.
  - Lists/maps/structs are **mutable** in v0 (mutation is observable through shared handles).
  - Strings are immutable (treat them as values).

This makes v0 productive and keeps the compiler/backends simple while the language is still rolling.

### Long-term direction (not enforced in v0)

For large-scale agentic and HPC workloads, we may evolve toward:

- “immutability-by-default” at the language level (opt-in mutability), and/or
- compiler-driven copy elision / uniqueness optimization, and/or
- specialized layout-stable structs for FFI/HPC (separate from v0 map-shaped structs).

Those are orthogonal milestones and should not block making v0 correct and consistent across backends.

### Implications for networking and endian casting

For packet parsing, the ideal long-term ergonomics is to avoid allocations entirely:

- introduce **packed struct views** over a byte slice, with explicit endianness:
  - design idea:
    - declare a packed schema (metadata-only) and treat a “header value” as `{bytes, offset}`
    - reading `hdr.total_len` performs endian conversion from the underlying bytes
    - the view is immutable, bounds-checked, and deterministic

Proposed (not implemented) sketch using attributes:

```oren
@net.packed(endian="be")
struct Ipv4Hdr { total_len, proto, src, dst }

fn demo(pkt) {
    // view: zero allocation; just a handle to (pkt, 0)
    var hdr = pack_view(Ipv4Hdr, pkt, 0)
    var len = hdr.total_len
    return len
}
```

Constraints the design must enforce (for determinism + safety):

- only fixed-width scalar fields in v0 (u8/u16/u32/u64 and signed variants; bool later)
- explicit byte order at the schema or field level (no implicit host endianness)
- no unaligned host loads (must be bytewise reads so semantics are stable under interpreter/JIT/native)
- bounds checks are mandatory (out-of-bounds returns an error object, not UB)
- views must be non-owning (bytes slice outlives the view handle)

Until then, the endian helpers (`oren_bytes_get_u16_be`, etc.) are the stable base primitive.

### Native Backend Intrinsics
The native backend supports low-level **compiler/runtime intrinsics** for performance and system access.

Intrinsics are part of the “reserved surface” (prefix `oren_`, `sys_`) and may be lowered differently by each native backend, but must preserve **deterministic semantics**.

**Portable native intrinsics (Tier‑1 intent: ARM64 + x86_64):**

- **Float bit-casts (bitwise, no numeric conversion):**
  - `oren_f32_to_u32_bits(f32) -> u32`
  - `oren_u32_bits_to_f32(u32) -> f32`
  - `oren_f64_to_u64_bits(f64) -> u64`
  - `oren_u64_bits_to_f64(u64) -> f64`
- **Atomics (deterministic semantics; 64-bit word):**
  - `atomic_add(ptr, val) -> old` (fetch-add)
  - `atomic_cas(ptr, expected, new) -> old` (compare-and-swap)
- **Memory:**
  - `malloc(size)`: Allocate raw memory (pages).
  - `ptr_get(ptr)`, `ptr_set(ptr, val)`: Read/Write 64-bit word.
  - `ptr_get_byte(ptr)`, `ptr_set_byte(ptr, val)`: Read/Write 8-bit byte.
  - **FFI:**
    - `ffi symbol` statement declares an external symbol (e.g., `ffi puts`).
    - The compiler may rename the **internal** symbol label for module namespacing, but the **external** lookup name remains the source identifier (used for dyld binds / `dlsym` / `GetProcAddress`).
    - Native backend may attach compile-time FFI metadata via attributes on the `ffi` declaration:
      - `@ffi.link("...")`: declare a dynamic library dependency (portable; maps to `--link ...`).
      - `@ffi.dll("name.dll")`: Windows convenience form for attaching a DLL to a single symbol.
      - `@ffi.libc`: portable alias for the platform C library (Tier‑1 maps to `msvcrt.dll` / `libc.so.6` / `libSystem.B.dylib`).
      - `@ffi.ret("i32")`: ABI signed 32-bit return (sign-extend to i64).
      - `@ffi.ret("u32")`: ABI unsigned 32-bit return (zero-extend to i64).
      - `@ffi.ret("void")`: ABI void return (force return register to 0 for expression contexts).
      - `@ffi.ret("ptr")`: ABI pointer-sized return (Tier‑1: 64-bit; no normalization today).
      - `@ffi.ret("usize")`: ABI `size_t`/`usize` return (Tier‑1: 64-bit; no normalization today).
      - `@ffi.export`: export a top-level function symbol for callback-style interop (native backend only; see `docs/LANGUAGE.md` for platform status and requirements like `@oren.keep`).

    Rolling sugar:

      - `ffi { sym1, sym2, ... }`: expand to multiple `ffi sym` declarations, each inheriting the same outer attributes.
        - In rolling v0, commas/semicolons between group items are optional: `ffi { sym1 sym2 }` (one-per-line) is also accepted.
      - `ffi { @ffi.ret("i32") atoi, @ffi.ret("void") srand, puts }`: per-item attrs inside the group (merged with outer attrs).
      - `@ffi.ret("i32") ffi { atoi, puts, @ffi.ret("void") srand }`: group default return-kind, with per-item override (avoid duplication).

**ARM64-only today (rolling):**

- **SIMD (NEON)**:
  - `simd_add_2d`, `simd_sub_2d`: 128-bit integer addition/subtraction.
  - `simd_mul_4s`: 4x32-bit integer multiplication.
  - `simd_and_2d`, `simd_orr_2d`, `simd_eor_2d`: 128-bit bitwise operations.
- **Atomics (LSE)**: ARM64 backend may lower the portable atomics to LSE instructions when available,
  but must preserve the same semantics as the portable intrinsic contract.

SIMD enablement (rolling):

- SIMD is an **optimization only**; semantics must match the scalar reference behavior.
- Tier‑1 direction: x86_64 will expose a matching intrinsic family mapped to SSE2 (baseline) and optionally AVX2, but this is not treated as implemented until it has parity tests and stable feature detection across Linux+Windows.
- Native runtime uses env gating for native backend outputs:
  - `OREN_ENABLE_SIMD=1` enables SIMD fast paths when available.
  - `OREN_NO_SIMD=1` disables SIMD (wins over enable).
- Determinism is enforced by regression tests that compare scalar vs SIMD paths (bit-identical for covered kernels):
  - `tests/native/test_simd_suite.oren`
  - Implementation: `lib/runtime_native/040_capsule_core.oren` (env parse) + `lib/runtime_native/typed_buffers/**` (dispatch/wrappers) + `lib/compiler/arm64_native_expr/**` (NEON lowering).

### Optional Python FFI
Python interop is only available when the runtime is built with Python embedding (`-DOREN_ENABLE_PYTHON` / compiler `--python`).
- Windows note: MSVC and non‑MSVC C-backend paths derive include/lib flags from `python`/`python3`/`py -3` via `sysconfig` (override with `OREN_PYTHON`).
- Import: `var math = py_import("math")`
- Attribute access: `math.sqrt` (Python attribute get)
- Indexing: `obj[key]` (Python `__getitem__`)
- Calls: `obj(...)` (Python call)
- Release: `py_release(obj)` decrements the Python refcount and returns `nil` (use to drop long‑lived Python objects).

Rolling note: Oren does not GC Python refcounts; `py_obj` wrappers hold a strong reference until you
explicitly release them (or the process exits).

## Standard Runtime Surface (Self-Hosting)
Self-hosting relies on a small runtime API (implemented in C, callable from Oren) including:
- `oren_args()` for CLI args
- `oren_read_file(path)` / `oren_write_file(path, content)` for I/O
- `oren_system(cmd)` / `oren_exit(code)` for building and exit status
- **Strings / chars (portable core surface):**
  - `oren_string_len(s)`
  - `oren_string_char_at(s, i)` (returns a 1-byte string)
  - `oren_string_slice(s, start, end)` (clamps indices; empty/out-of-range returns `""`)
  - `oren_char(code)` (build 1-byte string from `0..255`)
- **String concatenation (portable syntax):**
  - use `a + b` (backends lower to the appropriate helper; do not rely on `string_concat(...)` existing outside native mode)
- `oren_list_len(xs)` / `oren_list_push(xs, v)` for list work
- `oren_new_map(pairs...)` / `oren_map_len(m)`
- `oren_map_get(m, key)` / `oren_map_set(m, key, value)` (key-kind aware: `int` vs `string`)
- `oren_map_get_str/int` / `oren_map_set_str/int` (explicit key-kind, used by stdlib + native backends)

Native backend note (rolling):

- Some helper symbols exist in the syscall-first native runtime (e.g. `oren_string_eq`, `oren_int_from_string`, `string_concat`) to support bring-up and stdlib glue.
- These should be treated as **native-only** unless/until we standardize them across C + AVM + native.

## Not Implemented (Yet)
- user-defined methods / inheritance (classes are currently data-only; long-term direction is traits + composition)
- dynamic/runtime module loading

## Planned (Essential Modern Language Features)

This section lists **missing but essential** features for a modern, AI-first language. These are
proposals and must be implemented across backends (C/native/bytecode) before being treated as
stable.

### 1) `yield` and stackless coroutines (async building block)

Motivation:

- enables lightweight tasks and structured concurrency without requiring OS threads for every unit of work
- makes agent pipelines (fan-out/fan-in, streaming) practical

Rolling status:

- Implemented (2026-04-22): bare statement `yield` now parses on the shared front-end and lowers
  directly to `oren_yield_stmt()`.
- New (2026-04-22): `yield <value>` and expression/result-position `yield` now lower through the
  backend-shared helper `oren_yield_value(value)`. That helper yields cooperatively / via the host
  hint and then resumes with the same local value, so:
  - `yield` statement returns `nil`
  - `(yield)` resumes as `nil`
  - `(yield expr)` resumes as the value of `expr`
  - `return yield expr` and `fn(x) { return add1(yield x) }` now work across bytecode, C, and
    native
- New (2026-04-22): `oren meta` / native `--metadata` now expose per-function `contains_yield`,
  `yield_stmt_count`, and `yield_stmt_sites` so the next lowering pass can discover real source
  bare-`yield` statements without guessing from lowered helper calls.
- New (2026-04-22): `oren meta` / native `--metadata` now also expose the shipped value-yield
  helper surface separately via `contains_yield_value`, `yield_value_count`, `yield_value_sites`,
  and `yield_value_surface`. That surface now also carries per-site consumer context
  (`yield_points[*].context`) plus the de-duplicated `consumer_kinds` list, so the metadata records
  where resumed values are consumed instead of only counting sites. This keeps the bare-statement
  `yield_lowering` plan honest instead of pretending it also models caller-visible value flow.
- New (2026-04-22): `oren meta` / native `--metadata` / `oren dump linked` now also expose the
  explicit helper protocol `oren_yield_exchange(yield_ch, resume_ch, value)` separately via
  `contains_yield_exchange`, `yield_exchange_count`, `yield_exchange_sites`, and
  `yield_exchange_surface`. That surface records the current `channel_resume_v0` contract plus
  per-site consumer context.
- New (2026-04-22): function metadata also carries a rolling `yield_lowering` plan object with an
  explicit entry state, resume states, yield-point -> resume-state mapping, and a conservative
  `locals_across_yield` list for bare-statement `yield` functions.
- New (2026-04-22): that same `yield_lowering` object now emits a narrow v0 lowering gate:
  `lowering_v0` marks the currently implemented bare-statement `yield` surface as `ready`
  (`bare_yield_dispatch_v0`: top-level bare `yield`, multiple top-level yield sites, branch/block/
  loop-nested bare `yield`, and functions that also contain nested function literals, including
  live locals/params that remain across the suspension point). That metadata plan is still about
  bare-statement coroutine lowering; the remaining unsupported surface is caller-visible resume /
  generator semantics beyond the new helper-based local value contract.
- New (2026-04-22): for `lowering_v0.ready` functions, metadata now also emits
  `yield_lowering.prepared_v0`, either an explicit split-dispatch lowering shape with entry/resume
  segments or a direct-passthrough prepared shape for ready branch/block cases. Metadata keeps the
  same segment summaries for both so backend verifiers can assert the exact path taken.
- New (2026-04-22): `oren dump linked` now surfaces the same per-function `yield_lowering` object
  in `function_details`, and the bytecode verification path now reads `yield_lowering` back out of
  the built `.obc` metadata blob instead of trusting `oren meta` alone.
- New (2026-04-22): `oren build|meta|dump --strict-yield-lowering-v0` now enforces that v0 gate
  against the full parsed source program, not just the reachable post-link graph. That keeps dead
  top-level yielding functions from slipping through builds, and strict mode intentionally skips
  artifact-cache restore so cached non-strict outputs cannot bypass the policy.
- New (2026-04-22): the AVM bytecode backend now consumes `yield_lowering.prepared_v0` for the
  exact `lowering_v0.ready` subset and lowers it into an explicit in-function split-dispatch state
  machine when top-level yield segments exist, or a direct prepared passthrough when the function
  only contains control-flow-nested yields. This now covers multiple top-level yield sites, live
  top-level locals/params, loop/branch/block control flow, and functions that also contain nested
  function literals because the AVM function frame survives `AVM_YIELD`. Native/C backends do not
  yet consume `prepared_v0` as an explicit lowering path.
- New (2026-04-22): the same `lowering_v0.ready` fixture is now parity-verified under bytecode,
  C, and native builds. AVM reaches it through explicit `prepared_v0` split-dispatch/direct
  lowering, while C/native currently execute the same ready subset through direct
  `oren_yield_stmt()` calls on their existing stackful/runtime call surfaces.
- New (2026-04-22): value-carrying `yield` is now parity-verified too. The shipped value model is
  intentionally local and backend-shared:
  - `oren_yield_value(v)` yields, then resumes with `v`
  - no caller-supplied resume value exists yet
  - the shipped generator handle is now compiler-managed and tagged as `generator`, but its worker
    protocol still uses explicit exchange channels under the hood
- New (2026-04-22): explicit caller-visible yield/resume channels now also exist through
  `oren_yield_exchange(yield_ch, resume_ch, value)`. The same contract now also has a first-class
  source syntax on the shared front-end:
  - `yield expr in (yield_ch, resume_ch)`
  - `yield in (yield_ch, resume_ch)` for implicit `nil` outward values
  - `yield expr in co` / `yield in co` for compiler-managed generator-context exchange
  That syntax is parity-verified under bytecode, C, and the default native green/runtime path.
  On native host threads with green runtime already active and no background workers, `oren_yield()`
  now drives one cooperative green scheduling step before falling back to the OS yield hint. The
  first reusable source-level abstraction above it is now `std:generator`, whose
  `start/next/send/close/cancel/request_cancel/request_cancel_after/cancel_after/request_cancel_at/cancel_at/stop_after/stop_at/delegate/is_started/is_done/is_closed/current_step/return_value/terminal_error/terminal_result/collect/is_cancel_requested/cancel_reason` surface is
  now a thin facade over compiler-injected
  `oren_generator_*` helpers and a compiler-managed `generator` handle. That handle is intentionally
  opaque at the language contract level: workers use `yield ... in co`, helpers validate generator
  handles / generator contexts, and the generator substrate no longer depends on map semantics at
  all. The shipped handle/context now ride on hidden list capsules rather than public map fields
  like `yield_ch`, `resume_ch`, `done_ch`, `worker`, `task`, `started`, `done`, and `return`. The
  shared channel/select runtime still carries the underlying exchange, but the remaining gap is
  broader coroutine/generator protocol above that first compiler-managed handle, not first
  availability of source syntax or reusable generator helpers.
- New (2026-04-23): that same shipped generator/coroutine substrate now also carries a two-layer
  cancellation contract above forced `close()`:
  - `request_cancel(target, reason)` marks a sticky cancel request on a generator handle or context
  - `cancel(target, reason)` records that sticky request on a generator handle or active generator
    context and then forces the existing deterministic `close()` path
  - `is_cancel_requested(target)` and `cancel_reason(target)` expose that sticky state
  - the first request wins; later requests do not overwrite the recorded reason
  - the state remains observable after natural completion or explicit `close()`
  - active `yield from` / delegation chains propagate the request down to the current delegated child
  - `request_cancel(...)` remains cooperative state only; it does not inject a hidden cancellation
    exception or forcibly unwind user code
  - `cancel(...)` is the shipped hard-stop layer for the current helper path: live handles become
    `done` + `closed`, keep the first cancellation reason, and then surface the same deterministic
    post-`close()` state across bytecode, C, and native
  - `request_cancel_after(target, timeout_ms, reason)` spawns a joinable watcher task that sleeps
    for `timeout_ms` and then records the same cooperative sticky request state
  - `cancel_after(target, timeout_ms, reason)` spawns a joinable watcher task that sleeps and then
    applies the same first-write-wins hard-stop `cancel(...)` protocol
  - `request_cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` /
    `cancel_after_wait(target, timeout_ms, reason, join_timeout_ms)` are the synchronous stdlib
    forms above those watcher helpers: they spawn the same watcher and then wait on it through the
    shipped `oren_join_timeout(...)` contract
  - `timeout_ms == nil` defaults to `0`, negative timeouts clamp to `0`, and invalid non-`int`
    timeout arguments return an immediate `err`
  - for live targets the watcher join result is `nil`; if `cancel_after(...)` runs after the target
    is already done, the watcher surfaces the cached terminal result instead of rewriting
    cancellation state
  - `join_timeout_ms == nil` or any negative `join_timeout_ms` value uses a derived wait budget
    instead of a raw infinite join: relative helpers wait for `timeout_ms + 2000`, absolute
    helpers wait for `max(deadline_ns - time.now_ns(), 0)` plus `2000`, and stop helpers add
    `grace_ms` into that same default budget; invalid non-`int` join-timeout arguments return an
    immediate `err`
  - `request_cancel_at(target, deadline_ns, reason)` / `cancel_at(target, deadline_ns, reason)`
    apply that same watcher protocol against an absolute `deadline_ns` in the `time.now_ns()`
    domain
  - `request_cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` /
    `cancel_at_wait(target, deadline_ns, reason, join_timeout_ms)` are the matching synchronous
    absolute-deadline forms
    - `deadline_ns <= time.now_ns()` triggers immediately
    - `deadline_ns == nil` defaults to immediate
    - invalid non-`int` deadlines return an immediate argument `err`
  - `stop_after(target, timeout_ms, grace_ms, reason)` layers scheduler-facing stop policy above
    the watcher helpers:
    - after `timeout_ms`, it records the cooperative sticky cancel request
    - after an additional `grace_ms`, it applies the shipped hard-stop `cancel(...)` path
    - `timeout_ms == nil` and `grace_ms == nil` both default to `0`
    - negative timeout/grace values clamp to `0`
    - invalid non-`int` timeout/grace arguments return an immediate argument `err`
  - `stop_after_wait(target, timeout_ms, grace_ms, reason, join_timeout_ms)` synchronously applies
    that same soft-then-hard policy and waits for the watcher result through `oren_join_timeout(...)`
    using either the explicit `join_timeout_ms` budget or the derived `timeout_ms + grace_ms + 2000`
    default
  - `stop_at(target, deadline_ns, grace_ms, reason)` applies that same soft-then-hard stop policy
    against an absolute `deadline_ns` in the `time.now_ns()` domain
  - `stop_at_wait(target, deadline_ns, grace_ms, reason, join_timeout_ms)` is the matching
    synchronous absolute-deadline stop form
    - `deadline_ns <= time.now_ns()` triggers immediately
    - `deadline_ns == nil` defaults to immediate
    - invalid non-`int` deadlines return an immediate argument `err`
  - `stop_policy(target, policy)` / `stop_policy_wait(target, policy)` now ship as the first
    map-shaped scheduler/deadline policy layer above that flat helper family
    - `policy["mode"]` accepts `request_cancel`, `cancel`, or `stop` (default `stop`; `request`
      aliases `request_cancel`)
    - `policy["timeout_ms"]` and `policy["deadline_ns"]` are mutually exclusive when both are
      non-`nil`
    - `policy["grace_ms"]` is only meaningful for `mode=stop`; positive grace with other modes
      returns an immediate `err`
    - `policy["reason"]` is forwarded unchanged
    - `stop_policy(...)` always returns the joinable watcher handle for the normalized policy, even
      when that policy is immediate
    - `stop_policy_wait(...)` applies the same normalized policy synchronously; when
      `policy["join_timeout_ms"]` is missing or negative it uses the same derived wait-budget rules
      as the existing `*_wait(...)` helpers
  - New (2026-04-23): `std:task` now ships as the first safe facade over generic language-level
    `spawn` handles:
    - `task.is_handle(...)` and `std:reflect.is_task(...)` expose the reflected task predicate
    - `task.is_done(...)` is the safe non-consuming completion probe
    - `task.current()` returns the current safe task handle inside a scheduler-backed spawned task
      and `nil` elsewhere
    - `task.request_cancel(handle, reason)`, `task.is_cancel_requested(handle)`, and
      `task.cancel_reason(handle)` now ship as the first cooperative cancellation-request surface
      for generic `spawn` handles
      - the request is sticky and first-write-wins; it records state only and does not force-stop the
        task
      - if the request lands before the task reaches its first instruction, that task may observe
        `is_cancel_requested(self) == true` on its first step
    - `task.request_cancel_after(...)`, `request_cancel_after_wait(...)`, `request_cancel_at(...)`,
      and `request_cancel_at_wait(...)` layer timeout/deadline helpers above that cooperative state
      - zero-delay / already-expired `*_wait(...)` calls apply the request synchronously before they
        return instead of relying on a watcher task eventually being scheduled
      - zero-delay async helpers still return a joinable watcher handle, but they record the sticky
        cancel request before returning that handle
    - `task.join(...)`, `task.join_timeout(...)`, `task.detach(...)`, and `task.join_all(...)`
      wrap the raw join/detach surface with handle validation
      - `task.join_timeout(...)` returning `-60` does not consume, detach, or invalidate the handle;
        later `join(...)`, `request_cancel(...)`, or `detach(...)` calls still apply to that same
        live task
    - `task.cancel(...)`, `cancel_after(...)`, `cancel_after_wait(...)`, `cancel_at(...)`, and
      `cancel_at_wait(...)` now ship as the bounded task-cancel surface
      - cancellation records the same sticky cooperative request first, then uses the safe
        join/detach path rather than an unsafe preemptive thread kill
      - the `*_wait(...)` forms accept `join_timeout_ms` as an explicit wait budget after the request
    - `task.stop_after(...)`, `stop_after_wait(...)`, `stop_at(...)`, `stop_at_wait(...)`,
      `stop_policy(...)`, and `stop_policy_wait(...)` now ship as the shared task-shaped
      deadline/stop surface for generic `spawn` handles
      - `mode="request_cancel"`, `mode="cancel"`, and `mode="stop"` are accepted for task handles
        (`request` aliases `request_cancel`)
      - `mode="request_cancel"` uses the cooperative sticky request state only; generic `spawn` work
        is not stopped or detached by that mode
      - `mode="cancel"` records the cooperative request at the timeout/deadline and then immediately
        applies the bounded join/detach stop path
      - `mode="stop"` records the cooperative request at the timeout/deadline, then waits the grace
        window before detaching if the task is still live
      - `stop_policy(...)` always returns a joinable watcher handle for the normalized task policy
      - `stop_policy_wait(...)` returns `nil` for `mode="request_cancel"` and returns the
        `{status, result, reason, detach_result}` map for `mode="cancel"` or `mode="stop"`;
        `join_timeout_ms`, when present, overrides the derived synchronous wait budget
      - a zero-budget task stop may still report `joined` when the scheduler can finish the task in
        the immediate step; otherwise it reports `detached`
    - current native scope is the default scheduler-backed green-task path; legacy native raw
      fallback handles still use low-level `oren_join(_timeout)` directly
  - New (2026-04-23): `std:task_group` now ships as the first group-shaped structured-concurrency
    layer above the generator/coroutine stop-policy stack and the generic task facade
    - `task_group.new(default_policy)` / `task_group.from_list(targets, default_policy)` create a
      mutable group over generator/coroutine handles, active contexts, or safe task handles
    - `task_group.add(...)`, `extend(...)`, `members(...)`, `count(...)`, `default_policy(...)`,
      `set_default_policy(...)`, and `snapshot(...)` expose the basic membership and default-policy surface
    - `task_group.stop_policy(group, policy)` / `stop_policy_wait(...)` now dispatch by member kind
      in stdlib map-backed groups too:
      - generator/coroutine handles and active contexts keep the full generator-backed stop-policy
        semantics
      - safe task handles use the shared `std:task` stop contract
    - direct group helpers mirror the per-handle policy family and avoid caller-side map boilerplate:
      `request_cancel(group, reason)`, `request_cancel_wait(group, reason, join_timeout_ms)`,
      `cancel(group, reason)`, `cancel_wait(group, reason, join_timeout_ms)`,
      `stop_after(group, timeout_ms, grace_ms, reason)`,
      `stop_after_wait(group, timeout_ms, grace_ms, reason, join_timeout_ms)`,
      `stop_at(group, deadline_ns, grace_ms, reason)`, and
      `stop_at_wait(group, deadline_ns, grace_ms, reason, join_timeout_ms)`
    - `task_group.join_all(group, join_timeout_ms)` joins task-handle-only groups and returns the
      per-member results; missing or negative `join_timeout_ms` defaults to `2000`
    - `task_group.join_watchers(...)` keeps the explicit watcher-list join surface and validates each
      watcher as a safe task handle before joining
    - `task_group.terminal_results(group)` remains the generator-handle terminal-result collector
      and rejects task handles or context-only members
    - New (2026-04-23): runtime-backed task groups now also ship for generic safe task handles and
      mixed runtime-backed membership:
      - `task_group.new_runtime()` creates an empty runtime-owned group
      - `task_group.new_runtime_with_policy(default_policy)` creates the same runtime-backed group
        with an attached default stop-policy map
      - `task_group.from_task_list(targets)` creates the same runtime-backed group from existing
        safe task handles
      - `task_group.from_task_list_with_policy(targets, default_policy)` is the matching
        constructor for existing safe task handles plus a stored default stop-policy map
      - `task_group.from_runtime_list(targets, default_policy)` creates a runtime-backed group from
        a mixed list of safe task handles plus generator/coroutine handles or active contexts, and
        runtime groups now also accept those same non-task members through `add(...)` / `extend(...)`
      - `task_group.is_runtime_group(group)` distinguishes that runtime-backed shape, while
        `task_group.is_group(...)` and `std:reflect.is_task_group(...)` now accept both runtime and
        stdlib map-backed groups
      - `task_group.default_policy(group)` / `set_default_policy(group, policy)` now also ship for
        runtime-backed groups and round-trip a cloned stored policy map
      - `task_group.member_kinds(group)` returns the normalized member-kind vector (`"task"`,
        `"generator"`, or `"generator_context"`); runtime-backed groups compute this from a single
        runtime-owned member snapshot so stop/join/terminal paths do not race separate
        `members(...)` and kind-classification calls
      - `task_group.snapshot(group)` returns a map with cloned `members`, `member_kinds`, and
        `default_policy`; runtime-backed groups source those three fields from one runtime-owned
        snapshot so stop paths no longer race separate default-policy and member reads
      - runtime-backed `stop_policy(...)` / `stop_policy_wait(...)` now consume members through an
        atomic runtime-owned take-snapshot after policy preflight validation; invalid overrides leave
        the group intact, while valid stop operations claim and clear the participating members before
        typed dispatch starts
      - runtime-backed mixed membership, stored default policy, and member/kind/policy snapshotting are
        now owned by the runtime group state itself across C, native, and AVM rather than by stdlib
        sidecar maps
      - `task_group.spawn_call_list(group, fn_obj, args_list)` spawns directly into the runtime
        group on AVM, C, and the default native green-task scheduler
      - `task_group.stop_policy(group, policy)` / `stop_policy_wait(...)` now also ship for
        runtime-backed groups, with the same member-kind dispatch:
        - the stored runtime-group default policy is merged before override validation
        - generator/coroutine handles and active contexts keep the full generator-backed
          stop-policy behavior
        - safe task handles use the same shared `std:task` contract, including `mode="request_cancel"`,
          bounded `mode="cancel"`, `mode="stop"`, and `join_timeout_ms` override on the synchronous path;
          immediate zero-budget task cancel/stop execution is now runtime-owned through
          `oren_task_cancel_now(...)`
      - `std:task.stop_capabilities()` exposes the current runtime stop-execution boundary as a stable
        map: `immediate_cancel_now=true`, `cancel_request_state=true`, `bounded_wait_native_call` is
        backend-specific (`true` on C/native, `false` on AVM), and `delayed_wait_native_call` is
        backend-specific in the same way
      - `task_group.join_all(...)` and `detach_all(...)` remain task-handle-only runtime-group
        operations and reject extra generator/coroutine members
      - `task_group.terminal_results(group)` now also works for runtime-backed groups that contain
        only generator/coroutine handles; it still rejects task handles and context-only members
    - the remaining boundary is now narrower: runtime-backed groups are already unified and
      runtime-owned for mixed membership, stored default policy, and atomic member/kind/policy
      snapshot-and-take semantics, and generic task cancellation is now shipped as cooperative request
      plus bounded stop/detach; immediate task stop execution is runtime-owned, C/native bounded and
      delayed synchronous cancel waits are now runtime-owned through `oren_task_cancel_wait(...)` and
      `oren_task_cancel_after_wait(...)`, and AVM deliberately keeps the opcode-level `JOIN_TIMEOUT`
      fallback because ordinary native calls cannot suspend the AVM scheduler; AVM delayed task waits
      and generator/coroutine typed stop execution still live in stdlib rather than wholly in the
      runtime scheduler itself, with `std:task.stop_capabilities()` as the programmatic guardrail for
      that boundary
  - `terminal_result(gen)` exposes the final handle result directly:
    - it accepts only a done generator handle, not a generator context
    - it returns the sticky terminal error when one exists
    - otherwise it returns the cached `return_value(gen)`
    - invalid or still-live handles return an immediate `err`
- New (2026-04-23): `std:coroutine` now also ships as a thin facade over that same compiler-managed
  `generator` handle/context contract. It keeps the same worker shape (`worker(co, args_list)`) and
  exchange surface (`yield ... in co`), but exposes coroutine-oriented runtime names
  (`start/resume/next/send/on_finalize/on_close/close/cancel/request_cancel/request_cancel_after/request_cancel_after_wait/cancel_after/cancel_after_wait/request_cancel_at/request_cancel_at_wait/cancel_at/cancel_at_wait/stop_after/stop_after_wait/stop_at/stop_at_wait/stop_policy/stop_policy_wait/delegate/delegate_step/is_started/is_done/is_closed/current_step/return_value/terminal_error/terminal_result/collect/is_cancel_requested/cancel_reason`)
  plus `std:reflect.is_coroutine(v)` and `std:reflect.is_coroutine_context(v)` as the matching
  handle/context tag checks.
- New (2026-04-22): the parser now also ships the first language-level generator declaration sugar
  on top of that same protocol:
  - `@oren.generator fn counter(seed) { var r = yield (seed + 1); return r + 5 }`
  - `@oren.generator var counter = fn(seed) { var r = yield (seed + 1); return r + 5 }`
  - `@oren.generator var counter = |seed| { var r = yield (seed + 1); return r + 5 }`
  - New (2026-04-23): `@oren.coroutine` is now accepted as source-level parser sugar for the same
    shipped declaration family:
    - `@oren.coroutine fn counter(seed) { ... }`
    - `@oren.coroutine var counter = fn(seed) { ... }`
    - `@oren.coroutine var counter = |seed| { ... }`
  - the declaration lowers to a wrapper that returns `oren_generator_start(...)`
  - the alias is intentionally parser-only:
    - runtime handle kind remains `generator`
    - `std:coroutine` and `std:generator` both operate on that same handle/context substrate
    - metadata remains canonical on the generator surface (`generator_decl_surface.syntax=attr_oren.generator`)
  - plain `yield` / `yield expr` inside that declaration are rewritten to the shared
    `generator_context_v0` exchange contract (`yield ... in co`)
  - source-level delegation now also ships on top of the same handle/context contract:
    - inside explicit generator workers: `yield from inner in co`
    - inside `@oren.generator` and `@oren.coroutine` declarations: `yield from inner`
    - the `from` surface is contextual after `yield`; it is not a reserved identifier in the
      general language
  - source-level generator finalization now also ships on top of that same contract:
    - inside explicit generator workers: `defer { ... } in co`
    - inside `@oren.generator` and `@oren.coroutine` declarations: `defer { ... }`
    - the `defer` surface is contextual; it is not reserved outside those generator forms
  - metadata now reports that object contract as `compiler_generator_object_v7` with
    `generator_handle_v2`, `dedicated_generator_object_kind_v1`, declaration-form metadata via
    `generator_decl_surface.decl_forms`, and iterable metadata via `iter_surface=for_in_v0`,
    `iter_api=oren_iter_next_v0`, `iter_resume=implicit_nil_v0`, and explicit resume/delegation
    metadata through `resume_surface=next_send_finalize_defer_close_cancel_delegate_yield_from_v9`,
    `delegate_api=oren_generator_delegate_v1`,
    `close_api=oren_generator_close_v1`,
    `cancel_api=oren_generator_cancel_v1`,
    `request_cancel_api=oren_generator_request_cancel_v1`,
    `started_api=oren_generator_is_started_v1`,
    `closed_api=oren_generator_is_closed_v1`,
    `current_step_api=oren_generator_current_step_v1`,
    `cancel_requested_api=oren_generator_is_cancel_requested_v1`,
    `cancel_reason_api=oren_generator_cancel_reason_v1`,
    `terminal_error_api=oren_generator_terminal_error_v1`,
    `finalize_source_syntaxes=["defer_v0","defer_in_context_v0","on_finalize_call_v1","on_close_call_alias_v1"]`,
    `delegate_source_syntaxes=["yield_from_v0","yield_from_in_context_v0"]`, plus
    `close_mode=propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5`, plus
    `delegate_mode=track_active_chain_inline_fresh_or_cached_started_step_v3`
  - generator declaration metadata is now `version=23` and records
    `finalize_surface=generator_finalize_v0`
  - per-function `meta`, `dump linked`, and OBC metadata now also expose generator finalization
    sites directly through:
    - `contains_generator_finalize`
    - `generator_finalize_count`
    - `generator_finalize_sites`
    - `generator_finalize_surface`
  - `generator_finalize_surface` currently reports:
    - `version=1`
    - `surface=generator_finalize_v0`
    - `lifecycle=on_done_or_close_v1`
    - `hook_arity=zero_arg`
    - `syntax_kinds`, `api_kinds`, `consumer_kinds`
    - `finalize_points`
  - the focused cross-surface parity guard for that metadata is now
    `verify-generator-finalize-surface-v0`
  - internally, raw generator slot numbers are now isolated to named injected helper accessors, so
    the remaining representation swap is a single substrate seam instead of every resume/close path
  - the same v0 surface is now verified for both top-level and block-local declarations/bindings across
    bytecode, C, and native, with block-local lowering reusing the shared local named-function
    sugar `fn name(...) { ... } -> var name = fn (...) { ... }`
  - the remaining boundary is narrower: `@oren.generator` now requires a named binding site
    (named function declaration or function-valued `var` binding); it does not apply to
    bare anonymous function literals or arbitrary non-function statements
- Not implemented yet: full resumable state-machine lowering for value-carrying coroutine/generator
  semantics beyond the current local value-stable helper path, plus any distinct coroutine object
  kind / metadata surface above the current shipped parser alias + `std:coroutine` facade.

Design direction for the remaining backlog:

- extend `yield` from statement sugar into compiler lowering to a resumable state machine first
- later, consider `async/await` syntax as sugar on top of the same lowering

### 2) Built-in verification: `assert` and `test`

Motivation:

- agents need “generate → test → fix” loops as first-class workflows

Design direction:

- `assert(cond, msg?)` in core language
- `test "name" { ... }` blocks collected by a test runner

Rolling status:

- Implemented: core `assert(cond, msg?)` statement lowers to `oren_fail`.
- Implemented: `oren test` runs `test "name" { ... }` blocks (lowered to `test_<name>` funcs).
- `std:assert` provides lightweight helpers in the stdlib:
  `assert`, `assert_eq`, `assert_ne`, `assert_streq`, `assert_err`, `assert_ok`.

Example:

```oren
test "smoke" {
    assert(1 + 1 == 2, "math ok")
}
```

Run:

```bash
./oren test path/to/file.oren --backend native
```

### 3) Structured error model (self-healing support)

Rolling status:

- The core value-or-error convention is already shipped:
  - `oren_err(code, msg)`
  - `oren_is_err(v)`
  - `oren_err_code(v)`
  - `oren_err_msg(v)`
  - `std:result` helpers such as `is_err`, `is_ok`, `unwrap`, `expect`, `unwrap_or`,
    `ok_or_errno`, and `with_context`
- Checked stdlib surfaces already use that convention on current rolling builds, including
  `std:list`, `std:bytes`, `std:buffer`, `std:crypto/rand`, `std:ui/commands`,
  `std:ui/color`, and `std:ui/raster`.
- Remaining migration work is mostly library cleanup: several older codec/network modules still
  return ad-hoc `{ok, err}` maps, but that is no longer a missing core language/runtime feature.
- Design + migration notes: `docs/design/structured_error_model.md`

Planned direction (later, optional):

- add sugar such as `try expr` / local recovery forms after the plain value-or-error convention is
  fully settled across backends and stdlib surfaces

### 4) Visibility and module boundaries

Motivation:

- large agentic codebases need clean APIs and governance

Planned direction:

- `pub`/private visibility for module members
- avoid leaking internals across imports

Rolling status:

- `pub` now works on top-level `fn`, `var`, `struct`/`class`, `enum` sugar expansions, and
  `ffi` declarations.
- Modules that declare at least one `pub` member are closed-by-default to imports: cross-module
  `alias.member` access only succeeds for exported members.
- Modules with no `pub` members remain legacy-open during the rolling migration, so existing stdlib
  and repo-local imports keep compiling until each module opts into an explicit surface.
- Same-module direct access is unchanged; visibility is enforced only across imports.

### 5) Bytes + typed buffers (for ML-ish workloads)

Motivation:

- efficient byte and numeric buffer handling is required for:
  - bytecode loading
  - hashing
  - embeddings/vector math

Planned direction:

- a first-class `bytes` value type (packed)
- typed numeric buffers (`f32[]`, `i32[]`) with bulk ops

Rolling status:

- `std:bytes` already exposes checked packet-style helpers over `list<int>` and `u8_buf`, plus
  checked slice/concat/copy and `[]u8` bridge helpers.
- `std:buffer` already exposes checked typed-buffer helpers for `u8`, `i32`, `i64`, `f32`, and `f64`
  loads/stores via `try_len`, `try_load_*`, and `try_store_*`, plus checked zero-copy view helpers
  such as `try_slice_new`, `try_slice_load_i32`, `try_strided_new`, `try_mat_view_new`,
  `try_mat_rows`, `try_mat_cols`, `try_mat_row_stride`, `try_mat_row_slice`,
  `try_mat_col_strided`, `try_mat_subview`, `try_mat_diag_strided`, `try_mat_load/store_u8`,
  `try_mat_load/store_i32`, `try_mat_load/store_i64`, `try_mat_load/store_f32`, and
  `try_mat_load/store_f64`, plus
  checked conversion helpers such as `try_u8_pack`, `try_u8_unpack`, `try_u8_from_string`,
  `try_u8_from_string_slice`, `try_u8_to_string`, `try_u8_from_bytes`, `try_u8_from_bytes_slice`,
  `try_u8_to_bytes`, `try_u8_copy_from_u8_buf`, `try_u8_copy_from_bytes`,
  `try_u8_copy_from_bytes_slice`, `try_u8_copy_from_string`, and
  `try_u8_copy_from_string_slice`,
  `try_i32_pack_list_int`, `try_i32_unpack_list`, `try_i32_copy_from_i32_buf`,
  `try_i64_pack_list_int`, `try_i64_unpack_list`, `try_i64_copy_from_i64_buf`,
  `try_f32_pack_list`, `try_f32_unpack_list`, `try_f32_copy_from_f32_buf`,
  `try_f64_pack_list`, `try_f64_unpack_list`, `try_f64_copy_from_f64_buf`, `try_i32_mat_pack_rows`,
  `try_i32_mat_unpack_rows`, `try_i32_mat_copy_from_rows`, `try_i64_mat_pack_rows`,
  `try_i64_mat_unpack_rows`, `try_i64_mat_copy_from_rows`, `try_f32_mat_pack_rows`,
  `try_f32_mat_unpack_rows`, `try_f32_mat_copy_from_rows`, `try_f64_mat_pack_rows`,
  `try_f64_mat_unpack_rows`, `try_f64_mat_copy_from_rows`, `try_u8_mat_pack_rows`,
  `try_u8_mat_unpack_rows`, `try_u8_mat_pack_strings`, and `try_u8_mat_unpack_strings`,
  plus checked whole-matrix numeric flatten/refill helpers such as `try_i32_mat_unpack_flat`,
  `try_i32_mat_copy_from_flat`, `try_i64_mat_unpack_flat`, `try_i64_mat_copy_from_flat`,
  `try_f32_mat_unpack_flat`, `try_f32_mat_copy_from_flat`, `try_f64_mat_unpack_flat`, and
  `try_f64_mat_copy_from_flat`, plus checked whole-matrix `[]u8` flatten/refill helpers such as
  `try_u8_mat_unpack_flat` and `try_u8_mat_copy_from_flat`, plus checked whole-matrix typed-buffer bridges such as
  `try_i32_mat_to_i32_buf`, `try_i32_mat_copy_from_i32_buf`, `try_i64_mat_to_i64_buf`,
  `try_i64_mat_copy_from_i64_buf`, `try_f32_mat_to_f32_buf`, `try_f32_mat_copy_from_f32_buf`,
  `try_f64_mat_to_f64_buf`, and `try_f64_mat_copy_from_f64_buf` (which reject mismatched typed-buffer
  kinds instead of attempting raw loads), plus checked matrix-row/column
  `[]u8` bridge helpers such as `try_mat_row_to_string`, `try_mat_row_copy_from_string`,
  `try_mat_row_copy_from_string_slice`, `try_mat_col_to_string`, `try_mat_col_copy_from_string`,
  `try_mat_col_copy_from_string_slice`, `try_mat_diag_to_string`, `try_mat_diag_copy_from_string`,
  and `try_mat_diag_copy_from_string_slice`, plus checked whole-matrix `[]u8` flatten/copy helpers
  such as `try_u8_mat_to_bytes`, `try_u8_mat_to_u8_buf`, `try_u8_mat_to_string`,
  `try_u8_mat_copy_from_bytes`, `try_u8_mat_copy_from_u8_buf`, `try_u8_mat_copy_from_string`,
  `try_u8_mat_copy_from_string_slice`, `try_u8_mat_copy_from_bytes_slice`,
  `try_u8_mat_copy_from_flat`, `try_u8_mat_copy_from_rows`, and
  `try_u8_mat_copy_from_strings`, plus checked numeric
  slice/strided list bridges such as
  `try_slice_unpack_i32`, `try_slice_copy_from_list_i32`, `try_strided_unpack_i64`, and
  `try_strided_copy_from_list_f64`, checked numeric slice/strided typed-buffer bridges such as
  `try_slice_to_i32_buf`, `try_slice_copy_from_i32_buf`, `try_strided_to_i64_buf`, and
  `try_strided_copy_from_f64_buf`, checked numeric matrix row/column list bridges such as
  `try_mat_row_unpack_i32`, `try_mat_row_copy_from_list_f32`, `try_mat_col_unpack_i64`,
  `try_mat_col_copy_from_list_f64`, `try_mat_diag_unpack_i32`, and
  `try_mat_diag_copy_from_list_f64`, and checked numeric matrix row/column/diagonal typed-buffer
  bridges such as `try_mat_row_to_i32_buf`, `try_mat_row_copy_from_i64_buf`,
  `try_mat_col_to_f32_buf`, `try_mat_col_copy_from_f64_buf`, `try_mat_diag_to_i32_buf`, and
  `try_mat_diag_copy_from_f64_buf`, which reuse the checked slice/strided bridge surface instead of
  rebuilding row/column/diagonal loops, plus checked `[]u8` view bridges such as
  `try_slice_unpack_u8`, `try_slice_to_bytes`, `try_slice_to_u8_buf`, `try_slice_to_string`,
  `try_slice_copy_from_bytes`, `try_slice_copy_from_bytes_slice`, `try_slice_copy_from_u8_buf`,
  `try_slice_copy_from_string`, `try_slice_copy_from_string_slice`, `try_strided_unpack_u8`,
  `try_strided_to_bytes`, `try_strided_to_u8_buf`, `try_strided_to_string`,
  `try_strided_copy_from_bytes`, `try_strided_copy_from_bytes_slice`,
  `try_strided_copy_from_u8_buf`, `try_strided_copy_from_string`, and
  `try_strided_copy_from_string_slice`.

### 6) Variadic ergonomics (without a huge ABI rewrite)

Motivation:

- Many agent workflows need “collect arguments and forward them” patterns:
  - logging/tracing utilities
  - wrapper functions that forward to `print(...)` / formatting

Recommended staged design:

Rolling status:

- Implemented (rolling): call-site spread for variadic builtins and user-defined varargs across backends.
- Evidence: `tests/fixtures/tier1_native_spread_smoke_main.oren`,
  `tests/modules/test_varargs.oren`, `tests/avm/test_varargs_spawn.oren`.
- Constraint: spread must be last argument (only one spread per call).

1) **Call-site spread/splat for variadic builtins**
   - Example: `print(xs...)` where `xs` is a `list` of values.
   - This does not require changing the calling convention for user-defined functions.
2) **User-defined variadic functions (optional, later)**
   - Example syntax: `fn f(a, ...rest) { ... }` where `rest` is a `list`.
   - Requires defining a stable cross-backend calling convention (likely “argc + argv” or “rest list packing”).


---

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
- Function entries also expose rolling coroutine-discovery fields:
  - `contains_yield`: `true` when the function body contains source-level bare `yield` statements.
  - `yield_stmt_count`: count of those source-level `yield` statements in the function body.
  - `yield_stmt_sites`: source sites for those `yield` statements as `file:line:col`.
- Function entries also expose the shipped value-yield helper surface separately:
  - `contains_yield_value`: `true` when the function body contains source-level value/result-position
    `yield` that lowers through `oren_yield_value(v)`.
  - `yield_value_count`: count of those source-level value-yield sites.
  - `yield_value_sites`: source sites for those value-yield sites as `file:line:col`.
  - `yield_value_surface`: machine-readable statement of the current contract
    (`local_value_resume_v0`, implicit-nil + explicit-value support, no caller resume value, no
    generator channel), including `consumer_kinds` plus per-point `context` for where the resumed
    value is consumed (`var_init`, `return_value`, `call_arg`, `expr_stmt`, etc.).
- Function entries also expose the explicit channel-based helper surface separately:
  - `contains_yield_exchange`: `true` when the function body contains explicit channel-based
    yield/resume sites, either direct `oren_yield_exchange(yield_ch, resume_ch, value)` calls or the
    shared-front-end source syntax `yield [expr] in (yield_ch, resume_ch)` / `yield [expr] in co`.
  - `yield_exchange_count`: count of those explicit channel exchange sites.
  - `yield_exchange_sites`: source sites for those exchange sites as `file:line:col`.
  - `yield_exchange_surface`: machine-readable statement of the current explicit contract
    (`channel_resume_v0`, explicit yielded/resumed values, and binding-sensitive channel/context
    argument positions), including `binding_kinds`, `consumer_kinds`, `syntax_kinds`, plus per-point
    `context`, `syntax`, `binding`, and `explicit_value`.
- Generator declaration sugar is exposed separately too:
  - `is_generator_decl`: `true` for functions declared with `@oren.generator`
  - `generator_decl_surface`: machine-readable statement of the current generator object protocol
    (`compiler_generator_object_v7`, `version=23`, syntax `attr_oren.generator`, helper API
    `oren_generator_start_v2`, caller handle `generator_handle_v2`, object type `generator`,
    underlying yield surface `generator_context_v0`, finalization surface `generator_finalize_v0`,
    iterable surface `for_in_v0` with implicit-`nil` resume, explicit
    resume/delegation/finalization surface `next_send_finalize_defer_close_cancel_delegate_yield_from_v9`,
    lifecycle APIs `oren_generator_cancel_v1` / `oren_generator_request_cancel_v1` / `oren_generator_is_started_v1` /
    `oren_generator_is_closed_v1` / `oren_generator_is_cancel_requested_v1` /
    `oren_generator_current_step_v1` / `oren_generator_terminal_error_v1` /
    `oren_generator_cancel_reason_v1`
    (`next_api=oren_generator_next_v2`, `send_api=oren_generator_send_v2`,
    `on_finalize_api=oren_generator_on_finalize_v1`,
    `on_close_api=oren_generator_on_close_v1`,
    `close_api=oren_generator_close_v1`,
    `cancel_api=oren_generator_cancel_v1`,
    `delegate_api=oren_generator_delegate_v1`,
    `delegate_step_api=oren_generator_delegate_step_v1`,
    `finalize_source_syntaxes=["defer_v0","defer_in_context_v0","on_finalize_call_v1","on_close_call_alias_v1"]`,
    `delegate_source_syntaxes=["yield_from_v0","yield_from_in_context_v0"]`,
    `close_mode=propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5`,
    `delegate_mode=track_active_chain_inline_fresh_or_cached_started_step_v3`),
    state layout `dedicated_generator_object_kind_v1`,
    worker context type `generator_context`, declaration forms
    `["named_function_decl", "function_valued_var"]`)
- Functions that contain source-level `yield` also expose `yield_lowering`, a rolling internal plan
  object with:
  - `entry_state`
  - `state_count`
  - `yield_points[*]` (`site`, `resume_state`)
  - `states[*]` (`entry` + one `resume` state per yield site)
  - `locals_across_yield` (conservative local/parameter names that stay in scope across at least one
    `yield` and are referenced later)
  - `lowering_v0` (`ready`/`blocked` plus blocker strings for the first executable
    bare-statement-yield lowering target)
- These fields intentionally split the two shipped surfaces:
  - `contains_yield` / `yield_lowering` describe bare-statement `yield`
  - `contains_yield_value` / `yield_value_surface` describe helper-based value/result-position
    `yield`
  - `contains_yield_exchange` / `yield_exchange_surface` describe the explicit channel-based
    yield/resume helper
- They do not infer from raw user-written `oren_yield()` / `oren_yield_stmt()` / `oren_yield_value()`
  calls, and outer functions do not inherit `yield`s that appear only inside nested function
  literals.

### 2.2 Normalized capability manifest

In addition to raw function attrs, `oren meta` / native `--metadata` emit a top-level
capability manifest for functions annotated with `@cap.requires(domain="...")`.

Shape (rolling, v1):

```json
{
  "capabilities": {
    "version": 1,
    "required_domains": ["FS", "TIME", "RNG"],
    "functions": [
      { "name": "read_fs", "domains": ["FS"] },
      { "name": "timed_random", "domains": ["TIME", "RNG"] }
    ]
  }
}
```

Domains are normalized to uppercase and deduplicated per function and across the source
file. This manifest is for tooling and build policy; capsule enforcement still uses the
compiler/runtime capability gates described in `docs/CAPABILITY_RUNTIME_CONTRACT.md`.

When `--manifest` is requested, the artifact manifest also embeds the required source
domains in `policy.source_required_domains` alongside backend/runtime-profile policy inputs.
That artifact manifest is guarded by `make verify-capability-manifest-policy`.

### 2.3 Normalized package policy manifest

Package-policy metadata is declared with `@oren.package(...)` on a top-level declaration:

```oren
@oren.package(runtime_profile="capsule", cap_allow_domains="FS,ENV", budget_gas=100000, budget_heap_bytes=1048576, budget_wall_ms=1000)
var package_policy = 1
```

Shape (rolling, v1):

```json
{
  "package": {
    "version": 1,
    "declared": true,
    "runtime_profile": "capsule",
    "cap_allow_domains": ["FS", "ENV"],
    "source_required_domains": ["ENV"],
    "dependency_domain_union": ["ENV"],
    "dependency_domain_union_status": "source_attrs_only",
    "budgets": { "version": 1, "declared": true, "gas": 100000, "wall_ms": 1000, "heap_bytes": 1048576 }
  }
}
```

The marker is intentionally not implicit enforcement. It gives package tooling, artifact
manifests, and agents a stable source-declared policy surface to compare with actual build
flags and runtime profiles. Artifact `--manifest` output additionally carries
`policy.source_package_check` with `observe_only` / `mismatch_observed` status, runtime-profile
comparison, cap-allow coverage, and budget declaration status. The check is diagnostic by
default; `--enforce-package-policy` / `OREN_ENFORCE_PACKAGE_POLICY=1` promotes
`mismatch_observed` into a build error. For execution, `scripts/run_package_policy.sh` dispatches
to backend-specific policy runners. The AVM path consumes the bytecode artifact manifest and maps
package capsule/gas/heap/wall declarations onto AVM runtime knobs before execution. It also uses
the AVM policy scanner to reject bytecode whose static used domains exceed the package allowlist,
rather than relying on denied native calls becoming values at runtime. The native path builds with
package capsule/domain policy, runs with matching native capsule env, enforces `budget_wall_ms`
with a process watchdog, enforces `budget_heap_bytes` from captured native-run JSON live-heap scan
evidence, enforces `budget_cpu_ms` from child process resource usage where available, and enforces
`budget_gas` from captured `native_stmt_loop_tick_v0` runtime evidence after building and running
with `OREN_NATIVE_GAS_ACCOUNTING=stmt`; captured gas JSON includes backend-local,
non-conversion-ready `oren.gas-surface.v0` metadata so tools do not confuse native statement+loop
ticks with AVM opcode gas. The fine native gas
spellings today are exact `1`, `stmt`, `statement`, `basic-block`, `block-weighted`, and `dynamic-emitter`;
`basic-block` is distinct native lowering-block evidence and `block-weighted` is weighted
native lowering-block evidence, while `dynamic-emitter` is backend-local runtime path-aware emitter-span evidence.
The exact spelling `instruction-equivalent` is reserved and guarded not to alias any current
fine-grained gas surface.
The gas-surface inventory is guarded separately by `make verify-gas-surface-registry`, so package-policy
and semantic-diff tooling cannot silently treat native backend-local gas as AVM-canonical gas.
When callers set
`OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path>`, the native runner writes
`oren.native-package-policy-run.v0` with runner-observed wall-budget timing and captured
`effect_ledger` summary when available. Native capsule runtime separately exposes
`oren.native-capsule-effect-gates.v0` domain-gate counters and
`oren.native-capsule-resource-checks.v0` resource-check counters, so tooling can distinguish
runtime-owned capsule evidence from external runner watchdog timing. When callers request
`--print-run-json`, the AVM effect-ledger summary reports the applied `budget_wall_ms` as
`budgets.wall_ms.limit` and records measured wall elapsed nanoseconds.

### 2.4 Normalized serde schema (what libraries/tooling want)

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

### Strict identifier prefix mode

Reserved identifier prefixes can be enforced at parse-time:

- `--strict-ident-prefixes`: reject user-defined identifiers starting with `oren_`, `sys_`, or `__oren_`
- `--ident-allow-prefixes myorg.,acme.`: allowlist prefixes in strict mode

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

For the rolling rules and priorities, see `docs/STATUS.md`.

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

- `docs/LANGUAGE.md`
- `docs/LANGUAGE.md`

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

- Dynamic value representation work: `docs/DESIGN.md#native-tagged-value-representation`
- Object model direction: `docs/LANGUAGE.md`
- Type-system stabilization direction: `docs/STATUS.md`
- Attribute contract: `docs/LANGUAGE.md`

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

- Value representation refactor targets: `docs/DESIGN.md#native-tagged-value-representation`
- Type-system stabilization targets: `docs/STATUS.md`
- Stdlibrary layering (crypto/net split): `docs/DESIGN.md#runtime-and-stdlib-layering`

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
  - Bytecode/AVM note (rolling): `oren_gc_collect()` is currently a **no-op** on the bytecode backend (no explicit AVM GC hook yet).

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
- what the intended direction is (design, tracked in `docs/STATUS.md`).

Oren is rolling; compatibility is not the priority. Accuracy is.


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
  - However, macOS/Linux already have an early green-task scheduler + netpoll integration for pipe/socket readiness (rolling; see `docs/DESIGN.md#runtime-and-stdlib-layering`).
  - Windows has a correctness-first in-memory channel implementation so `oren_select` works for channels even without IOCP (see `docs/DESIGN.md#runtime-and-stdlib-layering`).
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

### 1.1 `oren_yield()` / `oren_yield_stmt()` / `oren_yield_value()` / `oren_yield_exchange()` (rolling)

`oren_yield()` is the low-level best-effort “yield” surface used by both:

- the Stage N1 green-task runtime (as a cooperative scheduler yield), and
- non-green paths (as a best-effort OS yield hint).

Current behavior (native runtime, rolling):

- Language sugar: bare statement `yield` lowers directly to `oren_yield_stmt()`.
- `oren_yield_stmt()` is the normalized statement helper:
  - yields cooperatively / via OS hint using `oren_yield()`
  - always returns `nil`
- `oren_yield_value(v)` is the normalized value helper:
  - yields cooperatively / via OS hint using `oren_yield()`
  - always resumes with the provided local value `v`
- `oren_yield_exchange(yield_ch, resume_ch, v)` is the explicit caller-visible helper:
  - same contract is also available as source syntax:
    `yield expr in (yield_ch, resume_ch)` and `yield in (yield_ch, resume_ch)`
  - sends `v` to `yield_ch`
  - yields cooperatively / via OS hint using `oren_yield()`
  - resumes by reading and returning the next value from `resume_ch`
  - on the default native host-green runtime, the final `resume_ch` wait is scheduler-aware:
    responder green tasks may themselves `yield` before replying, because the wait routes through
    `oren_select_recv([resume_ch])` rather than a raw blocking recv
- `_oren_generator_context_exchange(co, v)` is the compiler-managed generator-context helper:
  - source syntax: `yield expr in co` and `yield in co`
  - intended for compiler-generated generator worker bodies and parser-lowered generator
    declarations, not general manual use
  - validates that `co` is a `generator_context`, then forwards to the same underlying explicit
    exchange channels
- `std:generator` is the first reusable source-level abstraction on top of that explicit helper:
  - `gen.start(worker, args_list)` creates a generator handle
  - worker contract is `worker(co, args_list)` where `co` is an opaque generator context and worker
    yields use `yield [expr] in co`
  - `gen.next(gen)` resumes with `nil`
  - `gen.send(gen, value)` resumes with `value`
  - `gen.is_started(gen)` reports whether the handle has ever been resumed
  - `gen.is_closed(gen)` reports whether the handle reached terminal state through explicit
    `close(gen)` rather than natural completion
  - `gen.current_step(gen)` returns the currently cached yielded step map while the handle is
    suspended at a yield, otherwise `nil`
  - `gen.terminal_error(gen)` returns the sticky terminal `err` captured during
    close/finalization, otherwise `nil`
  - `gen.request_cancel(target, reason)` marks a sticky cooperative cancel request on a generator
    handle or `generator_context`
    - the first request wins and later requests do not overwrite the reason
    - the request propagates down the currently active delegated child chain
    - it remains visible after natural completion or explicit `close()`
    - this does not force the worker to stop; user code must observe the request cooperatively
  - `gen.cancel(target, reason)` is the shipped hard-stop layer above that request state
    - it first records the same first-write-wins sticky cancellation request across the active
      delegated child chain
    - it then forces the deterministic `close()` path on the outer live handle
    - if the handle is already done, it returns the cached terminal result and does not rewrite the
      recorded cancellation state
  - `gen.request_cancel_after(target, timeout_ms, reason)` starts a joinable watcher task above that
    same request state
    - `timeout_ms == nil` defaults to `0`
    - negative timeouts clamp to `0`
    - non-`int` timeout values return an immediate argument `err`
    - when the target is live, joining the watcher returns `nil` after the cooperative request is
      recorded
  - `gen.cancel_after(target, timeout_ms, reason)` starts a joinable watcher task above the same
    hard-stop protocol
    - it sleeps, records the same first-write-wins cancellation reason, and then forces `close()`
    - when the target is live, joining the watcher returns `nil`
    - if the target already finished, joining the watcher returns the cached terminal result without
      rewriting cancellation state
  - `gen.request_cancel_at(target, deadline_ns, reason)` / `gen.cancel_at(target, deadline_ns, reason)`
    provide the same policy against an absolute deadline in the `time.now_ns()` domain
    - `deadline_ns <= time.now_ns()` fires immediately
    - `deadline_ns == nil` defaults to immediate
    - invalid non-`int` deadlines return an immediate argument `err`
  - `gen.is_cancel_requested(target)` reports whether that sticky cooperative request was recorded
  - `gen.cancel_reason(target)` returns the first recorded cooperative cancellation reason, otherwise
    `nil`
  - `gen.collect(gen)` drains yielded values into a list
  - `gen.on_finalize(co, hook)` / `oren_generator_on_finalize(co, hook)` register deterministic
    finalization hooks on an explicit worker context
    - `gen.on_close(...)` / `oren_generator_on_close(...)` remain as aliases of the same hook list
    - `hook` must be a zero-argument callable
    - hooks run in LIFO order
    - hooks now run on both explicit `close()` and ordinary natural completion
    - if a hook returns `err`, the first such `err` becomes the terminal generator result after still
      finishing cleanup
  - `gen.close(gen)` explicitly seals a generator handle done
    - if the generator already finished, it returns the cached final return value unless a terminal
      finalizer error was recorded, in which case it returns that `err`
    - if it has not finished yet, it first recursively closes the currently active delegated child
      chain, if any, then runs registered finalization hooks, and then marks the handle done with
      `return_value == nil`
    - for started generators it detaches the live worker handle instead of trying to resume user
      code with a hidden close sentinel; this keeps `close()` deterministic across bytecode, C, and
      native even when the worker would otherwise yield again
  - terminal finalizer errors are sticky:
    - after natural completion with a hook error, `next()` / `send()` / `collect()` return that `err`
    - `return_value(gen)` still preserves the generator’s cached ordinary return value
  - `gen.delegate(co, inner)` delegates through the outer `generator_context`, yielding directly on
    that outer context and returning the inner generator’s final return value
  - fresh inner generators inline directly
  - already-started generators now also delegate without manual step maps when the handle still
    carries its current cached yielded step
  - already-completed inner handles return their cached final value
  - `for x in gen { ... }` now also works directly for generator handles, using the same yielded
    values while resuming each step with implicit `nil`
  - under the C backend this now depends on the shared POSIX `oren_select` / `oren_select_recv`
    surface over pipe-backed channels instead of a generator-specific workaround
- `std:coroutine` now also ships as a naming-layer facade over that same handle/context substrate:
  - `coro.start(worker, args_list)` creates the same tagged `generator` handle
  - `coro.resume(co)` / `coro.next(co)` resume with implicit `nil`
  - `coro.send(co, value)` resumes with `value`
  - `coro.on_finalize(co, hook)` / `coro.on_close(co, hook)` are aliases of the same deterministic
    zero-argument finalization hook list
  - `coro.close(co)`, `coro.cancel(co, reason)`, `coro.request_cancel(co, reason)`,
    `coro.request_cancel_after(co, timeout_ms, reason)`, `coro.cancel_after(co, timeout_ms, reason)`,
    `coro.request_cancel_at(co, deadline_ns, reason)`, `coro.cancel_at(co, deadline_ns, reason)`,
    `coro.delegate(co, inner)`,
    `coro.delegate_step(co, inner, step)`, `coro.is_started(co)`, `coro.is_done(co)`,
    `coro.is_closed(co)`, `coro.current_step(co)`, `coro.return_value(co)`,
    `coro.terminal_error(co)`, `coro.is_cancel_requested(co)`, `coro.cancel_reason(co)`, and
    `coro.collect(co)` forward to the same underlying `oren_generator_*` contract
  - `std:reflect.is_coroutine(v)` / `std:reflect.is_coroutine_context(v)` are currently the same
    tag checks as `is_generator(v)` / `is_generator_context(v)`
  - `@oren.coroutine` now ships as parser sugar for the same declaration lowering as
    `@oren.generator`, including lambda-valued `var` bindings plus declaration-local `yield from`
    and `defer`
  - this still does **not** imply a separate coroutine metadata/runtime kind; the canonical
    declaration metadata remains `attr_oren.generator`
- First language-level declaration sugar now also ships on top of that same generator handle:
  - `@oren.generator fn counter(seed) { ... }`
  - `@oren.generator var counter = fn(seed) { ... }`
  - `@oren.generator var counter = |seed| { ... }`
  - calling `counter(seed)` returns the same tagged `generator` handle shape as `gen.start(...)`
  - plain `yield` / `yield expr` inside the declaration are lowered to the shared
    `yield ... in co` contract, so `gen.send(...)` supplies the resumed value
  - declaration bodies may now also use `yield from inner` for generator delegation without
    spelling `delegate(...)` or passing explicit step maps
  - generator finalization can now also be written directly in source syntax:
    - explicit workers: `defer { ... } in co`
    - declaration bodies: `defer { ... }`
    - `defer` remains contextual and is not reserved outside these generator forms
  - declaration bodies may register finalization hooks through `gen.on_finalize(hook)` or
    `oren_generator_on_finalize(hook)`, and `gen.on_close(hook)` /
    `oren_generator_on_close(hook)` remain aliases of that same zero-argument, LIFO contract
  - v0 boundary: generator declarations require a named binding site (named function declaration
    or function-valued `var` binding); bare anonymous function literals and arbitrary non-function
    statements are rejected
- Language sugar now uses those helpers consistently:
  - `yield` statement -> `oren_yield_stmt()`
  - `(yield)` -> `oren_yield_value(nil)`
  - `yield expr` / `(yield expr)` -> `oren_yield_value(expr)`
  - `yield expr in (yield_ch, resume_ch)` -> `oren_yield_exchange(yield_ch, resume_ch, expr)`
  - `yield in (yield_ch, resume_ch)` -> `oren_yield_exchange(yield_ch, resume_ch, nil)`
  - `yield expr in co` -> `_oren_generator_context_exchange(co, expr)`
  - `yield in co` -> `_oren_generator_context_exchange(co, nil)`
  - `yield from inner in co` -> `oren_generator_delegate(co, inner)`
  - `yield from inner` inside `@oren.generator` -> `oren_generator_delegate(co, inner)`
  - `defer { ... } in co` -> `oren_generator_on_finalize(co, || { ... })`
  - `defer { ... }` inside `@oren.generator` -> `oren_generator_on_finalize(co, || { ... })`
- The shipped helper contracts are now:
  - `oren_yield_value(v)`: local value-stable resume
  - `oren_yield_exchange(yield_ch, resume_ch, v)`: explicit yielded/resumed values via channel args
  - `_oren_generator_context_exchange(co, v)`: compiler-managed generator-context exchange over the
    same underlying explicit channel protocol
  - `oren_generator_delegate(co, inner)`: manual generator composition over the same
    `generator_context` protocol, exposed as `gen.delegate(co, inner)`, with
    `delegate_mode=track_active_chain_inline_fresh_or_cached_started_step_v3`
  - `oren_generator_delegate_step(co, inner, step)`: resumes a partially-started inner generator from
    its current yielded `step`, exposed as `gen.delegate_step(co, inner, step)`
  - `oren_generator_on_finalize(co, hook)`: registers a finalization hook, exposed as
    `gen.on_finalize(...)`, with `on_finalize_mode=lifo_zero_arg_on_done_or_close_v1`
  - `oren_generator_on_close(co, hook)`: alias of `oren_generator_on_finalize(co, hook)`, exposed as
    `gen.on_close(...)`, with `on_close_mode=alias_of_on_finalize_v1`
  - `oren_generator_close(gen)`: explicit handle finalization, exposed as `gen.close(gen)`, with
    `close_mode=propagate_active_delegate_chain_run_finalize_hooks_on_done_or_close_detach_live_task_v5`
- Still missing: broader coroutine protocol above these shipped source/helper/library forms
  (for example, stronger hard-cancellation/finalization semantics beyond the current explicit
  close+detach contract and lifecycle affordances beyond the current
  `is_started/is_closed/current_step/terminal_error` introspection surface).

- If running inside a green task: `oren_yield()` routes to `oren_green_yield()` (scheduler yield).
- If green runtime is already active on a host thread and background workers are not running:
  `oren_yield()` drives one cooperative host-side green polling step.
- Otherwise:
  - **Linux:** calls `sched_yield(2)` via syscall-first `sys_sched_yield()`.
  - **Windows:** calls `Sleep(0)` via `sys_sched_yield()` shim.
  - **macOS:** currently a best-effort `sys_sched_yield()` (no-op on older bring-up paths).

Source of truth:

- `lib/runtime_native/262_yield.oren`
- `lib/runtime/021_channels.inc`
- `lib/std/generator.oren`
- Linux syscall numbers are repo-owned in `docs/refs/linux_*` and wired via `lib/compiler/*_abi_linux.oren`.

### 2. Channels + `oren_select` (today: data-driven, backend-shared)

Channels exist today, but their implementation is currently a bring-up substrate:

- Native channels are platform-dependent today (rolling):
  - **macOS/Linux:** pipe pairs `[rfd, wfd]` (`oren_new_channel()` returns a list)
  - **Windows:** in-memory channels (a GC-tracked struct; `oren_new_channel()` returns a pointer)
- C backend channels now also exist for the basic `oren_new_channel` / `oren_chan_send` /
  `oren_chan_recv` surface, represented as same-process `[read_fd, write_fd]` pairs.
- AVM has proper channels as VM objects.
- `oren_select_recv` / `oren_select` exist as **functions** (not syntax) and have a shared encoding across AVM and native.

Source of truth:

- Native: `lib/runtime_native/010_channels_globals_consts.oren`, `lib/runtime_native/011_channels_mem.oren`, `lib/runtime_native/245_select.oren`
- AVM: `lib/avm/avm_vm.c` opcodes `SELECT_RECV` / `SELECT`
- Docs: `docs/DESIGN.md#runtime-and-stdlib-layering`

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
- fully runtime-executed structured concurrency across generic `spawn` handles and generator/coroutine
  workers (runtime-backed mixed task groups now own membership, default policy, and member-kind
  snapshots, but the per-kind stop execution still routes through stdlib helper calls)
- pub/sub or multicast channels
- data-parallel iterators (`par_map`, `par_reduce`)

## 3) Roadmap (high-level)

Implementation plan is tracked in `docs/STATUS.md` and the deeper design docs:

- `docs/DESIGN.md#runtime-and-stdlib-layering`
- `docs/DESIGN.md#runtime-and-stdlib-layering`
- `docs/DESIGN.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly`

## 4) AVM notes

For AVM execution (interpreter-only environments), concurrency primitives must:

- support cancellation/timeouts (to stop work when a better plan exists)
- be compatible with snapshot/restore (pause and resume tasks)
- be compatible with capability gating (NET/PROC may be disabled)

See:

- `docs/DESIGN.md#avm-and-obc-bootstrap-spec-summary` (Next-Gen plan section)
- `docs/STATUS.md`

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

- Backend unification direction: `docs/DESIGN.md#backend-outputs`
- AVM semantics + determinism: `docs/DESIGN.md#avm-and-obc-bootstrap-spec-summary`
