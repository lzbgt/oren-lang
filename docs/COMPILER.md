# Compiler Architecture (Rolling)

This document consolidates compiler architecture, IR notes, and implementation guidance.

## Scope

This document focuses on the compiler frontend and IR. Backend architecture and performance guidance live in `docs/BACKENDS.md`.

## Contents

- Compiler Architecture Notes (Rolling)
- IR and Compiler Internals (Rolling, AI-Friendly)
- Compiler Gotchas (Rolling)
- Implementation Notes (Rolling)

## Compiler Architecture Notes (Rolling)

**Last updated:** 2026-01-11

This document captures **high-signal invariants and mental models** for working on the Oren compiler
without re-learning the same failure modes repeatedly.

It is intentionally an index + checklist; deep dives live in the linked docs.

## 0) What “the compiler” is (today)

Oren has **one front-end** (parser + module linking + lowering passes) and can emit:

1) **Native binaries** (Tier‑1 targets: `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`)
2) **C backend outputs** (portable bring-up; relies on a host C toolchain)
3) **AVM bytecode** (`.obc`) for sandboxed deterministic execution

The bootstrapping story uses multiple stages:

- **stage0**: Go bootstrap (builds stage1 on the host; includes Windows VS2022/MSVC detection)
- **stage1**: Oren compiler built with the C backend (portable baseline)
- **stage2**: Oren compiler built with the native backend (self-host direction)

See:

- `docs/TOOLCHAIN.md`
- `docs/BACKENDS.md#native-backend-overview`

## 1) Artifact kinds and where they come from

- `--backend native`:
  - ELF (`.so`) for Linux `--lib`
  - PE (`.dll`) for Windows `--lib`
  - Mach‑O for macOS (executables / dylib where supported)
- `--backend c`: emits `.c` (and typically compiles+links it via `--cc`)
- `--backend bytecode`: emits `.obc`

The tool also supports header-based scanning for `--lib` outputs:

- `oren scan foo.{dylib,so,dll}` prefers parsing the generated `foo.h` (cross-platform).

See:

- `docs/TOOLCHAIN.md` (`--lib` output expectations and scan behavior)

## 2) Build pipeline phases (mental model)

When debugging failures, separate:

1) **Parse + AST** (syntax/grammar)
2) **Module linking** (imports, `@cfg` filtering, symbol binding)
3) **Lowering passes** (impl/trait lowering, pack-view lowering, sugar lowering, etc.)
4) **Backend-specific codegen** (native vs C vs bytecode)
5) **Runtime/toolchain integration** (native runtime bundles, C toolchain selection, dynamic linking)

Common “where it broke” questions:

- If something is platform-dependent, it usually lives in (4) or (5).
- If something is “same on all backends”, it should be caught in (1)–(3).

## 3) Guardrails (things we *must not regress*)

### 3.1 Scalar vs nil comparisons are correctness bugs

Rolling invariant:

- Do **not** treat numeric/bool scalars as optionals via `== nil`.

Enforcement:

- An always-on compiler pass rejects `bool/int/float == nil` when the scalar side is provable:
  - literals / casts / locally-proven scalars
  - calls to functions with explicit scalar return annotations (e.g. `fn f(): i64`)
  - “later scalar use” (best-effort scan, e.g. `i64(x)` after `if x == nil { ... }`)

Docs:

- `docs/COMPILER.md` (“Native value semantics: never rely on scalar == nil”)
- `docs/LANGUAGE_MANUAL.md`, `docs/LANGUAGE_SPEC.md` (guardrail wording)

Regression fixtures (must fail):

- `tests/fixtures/typecheck_bad_numeric_nil.oren`
- `tests/fixtures/typecheck_bad_bool_nil.oren`
- `tests/fixtures/nil_guard_bad_late_scalar_nil_compare.oren`
- `tests/fixtures/nil_guard_bad_late_scalar_nil_compare_top_level.oren`
- `tests/fixtures/nil_guard_bad_annotated_call_nil_compare.oren`

### 3.2 Spawn/join portability: workers return values (don’t `exit(...)`)

Rolling rule:

- Spawned workers should **return** values; `oren_join(_timeout)` is the portability boundary.
- Do not call `exit(...)` inside spawned workers (breaks join return semantics; unsafe on Windows).

Docs:

- `docs/LANGUAGE_MANUAL.md` (spawn notes)
- `docs/TOOLCHAIN.md` (why some fixtures use small `@cfg` glue)

### 3.3 Native string literals are constant-section data (not GC objects)

Rolling rule:

- Embedded literals are pooled into `cstr0` and must not be tracked as heap allocations.

Docs:

- `docs/COMPILER.md` (“Native strings: embedded literal pool must not hit GC tracking”)

## 4) Windows C backend toolchain selection (cl.exe vs cc)

Policy (Tier‑1 Windows host):

- Default C backend compiler is **MSVC `cl.exe`** (not `cc`).
- The compiler emits a temporary `.cmd` wrapper that:
  - resolves Visual Studio (direct probes + `vswhere.exe`)
  - runs `VsDevCmd.bat` / `vcvars64.bat`
  - invokes `cl.exe` with a minimal deterministic arg set
- Cross-compiling `--platform x64-windows --backend c` from a non-Windows host is **not**
  an implicit default; it requires an explicit `--cc` (e.g. MinGW) to opt in.

See:

- `docs/TOOLCHAIN.md` (Windows C backend policy)
- `docs/PLATFORMS.md` (Win11 (WSL2 optional) workflow)

## 5) Performance and hang-debugging entry points

Fast regression/diagnosis helpers:

- `make test` (native quick integration; bounded)
- `./scripts/bench_native_compile_one_file.sh` (bounded compile-one-file benchmark)

Primary playbook:

- `docs/BACKENDS.md#native-backend-performance-playbook`

When a build step “hangs”, prefer:

- adding **bounded trace markers** (opt-in env flags) over dumping huge logs
- using existing per-step timeouts in `scripts/*` and escalating only when necessary

## IR and Compiler Internals (Rolling, AI-Friendly)

**Last updated:** 2026-01-10  

This document is an **implementation map** for AI agents and maintainers:

- what “IR” means in this repo today (rolling reality),
- what the pipeline stages are,
- where the core data structures live,
- what **CoreIR** is intended to become (the semantics-owning boundary),
- and what has already landed (CoreIR v0 scaffold).

It complements:

- `docs/LANGUAGE_MANUAL.md` (user-facing “how to write Oren today”)
- `docs/LANGUAGE_SPEC.md` (grammar + semantics intent)
- `docs/BACKENDS.md` (high-level architecture + invariants)
- `docs/BACKENDS.md#native-backend-code-reuse-plan` (native backend reuse direction)

## 1) Terminology: “IR” in rolling v0

Oren is rolling. The word “IR” is used in two ways:

1) **Current reality (today):**
   - The compiler mostly operates on a **JSON-map AST** (mutable tree of `{type: ...}` nodes).
   - Most “lowering passes” are **AST rewrites** (backend-neutral).
   - Backends (C/native/bytecode) often still operate directly on this lowered AST.

2) **Target architecture (North Star):**
   - Introduce a canonical, backend-independent **CoreIR** that *owns semantics*.
   - Backends become thin adapters: `CoreIR -> BackendIR -> output`.

The goal is not “IR for its own sake”; the goal is:

- semantic parity across backends,
- maximal code reuse between arm64 and x86_64,
- deterministic behavior for AVM/multiverse workflows.

## 2) High-level pipeline (where to read code)

The pipeline is implemented in Oren itself under `lib/compiler/`.

Suggested “follow the code” order:

1) **Lexer / Parser**
   - Tokens: `lib/compiler/token.oren`
   - Lexer: `lib/compiler/lexer.oren`
   - Parser entry: `lib/compiler/parser.oren`
   - Parser internals: `lib/compiler/parser_core.oren`, `lib/compiler/parser_parse/**`
   - AST constructors (node shapes): `lib/compiler/ast.oren`

2) **Linking / modules**
   - Module linking: `lib/compiler/compiler/020_modules_linking.oren`
   - Generic specialization call rewrite: `lib/compiler/generic_call_lowering.oren`

3) **Name resolution / type hints / “static-first” rewrites**
   - Renamer: `lib/compiler/renamer.oren`
   - Type name resolve: `lib/compiler/type_name_resolve.oren`
   - Type annotation lowering: `lib/compiler/type_ann_lowering.oren`
   - Impl/traits lowering (method sugar, recv-kind hints, etc.): `lib/compiler/impl_lowering.oren`

4) **Optimizer (rolling)**
   - `lib/compiler/optimizer.oren`
   - Important note: optimizations must remain semantics-preserving under the chosen evaluation order.
   - Rolling fast path: inserts `oren_list_reserve(list, n)` before simple `while`/`for` push loops when
     `list` is a fresh literal (`[]`) and `n` is a known int literal in the same block.

5) **Backend selection**
   - Bytecode: `lib/compiler/codegen_bytecode/**`
   - C backend: `lib/compiler/transpiler.oren`
   - Native backends:
     - arm64 facade: `lib/compiler/codegen_arm64.oren`
     - x86_64 facade: `lib/compiler/codegen_x64.oren`

### Native runtime injection (compiler-side)

Both native backends ultimately want the same model:

- compile user program + the Oren “native runtime” sources into one output binary
- the runtime sources are modularized using a tiny include directive:
  - `// @include "relative/path.oren"`
- includes are expanded at compile time (compiler-side), then parsed as normal Oren source.

Implementation:

- Shared include expander: `lib/compiler/native_runtime_inject.oren`
- arm64 native injects runtime by default: `lib/compiler/arm64_native_program.oren`
- x86_64 native injects runtime by default: `lib/compiler/x64_native_program/090_program_entry.oren`
  - Tier‑1 rule: runtime injection is mandatory on x86_64; debug uses narrower fixtures/matrices rather than a runtime toggle.

- Shared injection + post-injection DCE: `lib/compiler/native_runtime_bundle.oren`
  - tags injected statements as runtime vs user (so backends do not rely on indices)
  - Tier-1 invariant: the injected runtime must not contain top-level executable statements
  - startup order: `native_runtime_init` runs first; then a synthesized `__top_level__` runs user global initializers and top-level statements
    - runtime global initializers are **not** executed in `__top_level__` (runtime init owns runtime globals)
  - compiler guardrail: constant-like runtime globals with non-zero initializers must be assigned in `native_runtime_init` (so Tier‑1 does not depend on top-level init order).

- the injected native runtime references syscall stubs (`sys_*`) that must be correctly lowered by the backend.

The CLI entry and dispatch live under `lib/compiler/compiler/**` (including `040_build_pipeline.oren`).

### Native FFI: internal name vs external symbol (module-exportability invariant)

Native backends support FFI declarations via `ffi name` (plus optional `@ffi.link(...)` / `@ffi.dll(...)` and `@ffi.ret(...)` attributes).

Rolling constraint that matters for stdlib and portability:

- Oren’s module system **prefixes** top-level symbols to avoid collisions (example: `STD_ffi_libc_strlen`).
- But the OS dynamic loader / resolver (`dlsym`, `GetProcAddress`, Mach‑O binds) must look up the **original external symbol** (example: `"strlen"`).

To make FFI declarations module-exportable, the compiler stores both names on `FFI` AST nodes:

- `name.value`: the **internal** symbol name after renaming (what call sites refer to)
- `link_name`: the **external** symbol name used for resolution (stable; not renamed)

This enables the stdlib to provide platform-neutral wrappers like:

- `lib/std/ffi/libc.oren` (platform-gated library attachment, call sites stay `libc.strlen(...)`)
- `tests/native/test_std_ffi_libc_smoke.oren` (regression fixture)

If you touch module renaming / namespace resolution / FFI lowering, keep this invariant and re-run:

- `make verify-x64-linux-qemu` (covers x64-linux + the libc smoke)

Implementation pointers:

- AST node shape: `lib/compiler/ast.oren` (`FFI` now has `link_name`)
- Renaming: `lib/compiler/renamer.oren` (renames `FFI.name`, never touches `link_name`)
- x64 backend: `lib/compiler/x64_native_program/072_ffi.oren` + call emission in `lib/compiler/x64_native_program/040_emit_expr.oren`
- arm64 backend: `lib/compiler/arm64_native_stmt.oren` + platform object writers (`lib/compiler/arm64_macho.oren`, `lib/compiler/arm64_elf.oren`)

## 3) Current “IR”: AST and LinkedProgram shapes

### 3.1 AST node shape (rolling)

AST nodes are plain maps, typically with:

- `type`: a string tag (`"Function"`, `"Call"`, `"If"`, …)
- `token`: optional token metadata (file/line/col)
- node-specific fields (e.g., `"left"`, `"right"`, `"body"`, `"params"`, …)

Canonical constructors are in `lib/compiler/ast.oren`.

### 3.2 LinkedProgram shape (rolling)

Module linking produces a “linked” program map that backends consume.

The exact fields evolve, but common keys include:

- `statements`: flattened top-level statement list after module resolution
- `aliases`: import alias map (used by capture analysis to avoid capturing module names)
- `type_ns`: type namespace map (used by type-name resolution / impl lowering)

Backends should treat unknown fields as “future expansion” and avoid relying on map iteration order.

## 4) CoreIR: what it is supposed to mean

CoreIR is the intended semantics-owning boundary:

- It encodes evaluation order and short-circuit rules explicitly.
- It owns container operation semantics (`xs[i]`, `xs[i]=v`, `len`, `push`) in a backend-neutral way.
- It owns callable semantics (closures + varargs + spread + indirect calls).
- It exposes a stable “effect model” surface so AVM/capsules/native share the same conceptual domains.

Backends should not “decide what `for` means” or “how `...rest` is represented”.
Those decisions must be centralized, deterministic, and regression-tested.

References:

- Architecture: `docs/BACKENDS.md`
- Native reuse direction: `docs/BACKENDS.md#native-backend-code-reuse-plan`

## 5) CoreIR v0 scaffold (what exists today)

We are introducing CoreIR incrementally.

The first landed piece is a minimal **CoreIR v0 scaffold**:

- `lib/compiler/coreir.oren`

What it does (today):

- deterministic extraction of top-level function declarations
- collects metadata needed by multiple backends:
  - `declared_functions` (map)
  - `func_decl_order` (list; source order)
  - `func_arity` (map)
  - `func_varargs_fixed` (map)

Initial consumer (today):

- x86_64 native backend prepass:
  - `lib/compiler/x64_native_program/080_functions_compile.oren`
- Bytecode backend prepass (declared funcs + varargs map):
  - `lib/compiler/codegen_bytecode/030_tail.oren`
- C backend transpiler prepass (direct-call + varargs lowering metadata):
  - `lib/compiler/transpiler.oren`

Why this matters:

- It removes the first piece of duplicated semantic metadata extraction.
- It makes arm64 and x86_64 converge on the same deterministic function/varargs facts.
- It is a safe stepping stone toward moving call canonicalization into CoreIR next.

## 6) Next CoreIR expansions (prioritized)

This is the suggested “rolling-safe” order to expand CoreIR while continuously keeping backends working:

1) **Call canonicalization**
   - Represent every call as one of:
     - `CallDirect(name, args...)`
     - `CallIndirect(fn_value, args_list)`
     - `CallSpreadDirect(name, fixed_args..., spread_list)`
     - `CallSpreadIndirect(fn_value, fixed_args..., spread_list)`
   - Lower varargs (`...rest`) and spread (`xs...`) deterministically at CoreIR boundary.
   - Motivation: this is the highest cross-backend coupling surface (C/native/bytecode/AVM).

2) **Container ops canonicalization**
   - Treat `xs[i]`, `xs[i]=v`, `len(xs)`, `push(xs, v)` as CoreIR ops with deterministic error behavior.
   - Ensure “hot path is not a stdlib call” for builtins.
   - Motivation: performance and semantic parity across backends.

3) **Effect model encoding**
   - Encode effectful operations as domain/op calls (conceptually aligned with AVM) so:
     - AVM enforces by policy
     - native/C enforce via capsule runtime policy and deterministic errors

4) **NativeIR extraction for arm64+x86_64 reuse**
   - Once CoreIR is stable for “meaning”, lower to a machine-ish NativeIR for ISA selection:
     - `Load/StoreLocal`, `Const`, `BinOp`, `Cmp`, `Branch`, `Call`, `Return`, …
   - This reduces duplication between `arm64_native_*` and `x64_native_program/**`.

Track these items in `docs/TODOS.md` (CoreIR boundary section).

## 7) Practical guidance (for contributors / agents)

When you modify semantics in a lowering pass:

- update the relevant section(s) in:
  - `docs/LANGUAGE_SPEC.md` (normative intent)
  - `docs/LANGUAGE_MANUAL.md` (practical usage)
  - `docs/STATUS_AND_ROADMAP.md` (status + evidence)
- ensure there is a fixture or integration test that exercises the semantic contract.

When you add a new backend feature:

- first add/extend a shared lowering pass or CoreIR rule if the feature is semantic,
- then add the backend implementation,
- then add fixtures that run under multiple backends (where possible).


## Compiler Gotchas (Rolling)

This doc captures **non-obvious invariants** that have caused regressions during self-host bring-up.
Keep it short and actionable; link to the deeper design docs when needed.

## Windows: `oren_system(...)` must preserve cmd.exe semantics

On Windows, `oren_system(cmd)` is implemented as `cmd.exe /C <cmd>`.

Important:

- Do **not** reconstruct `cmd` via `argv[]` → “MSVC quoting rules” → CreateProcess command line.
  `cmd.exe` frequently re-parses the **raw** command line and CRT-style escaping (notably `\"`)
  can break quoted paths and redirections (`>nul 2>nul`).
- The native runtime therefore passes the `cmd` string through to `cmd.exe` **without** re-escaping.

Implementation reference: `lib/runtime_native/260_threads.oren` (`oren_system_timeout`, Windows branch).

Regression gate: `make verify-stage2-win` (ensures `ensure_dir(...)` works for default `build/targets/...` outputs).

## Windows: native backend must accept portable `'/'` paths

Oren compiler/runtime code is allowed to use POSIX-style paths (`build/targets/...`) even on Windows.
The x64-windows native backend normalizes `'/'` → `'\\'` at the syscall intrinsic boundary for Win32 APIs:

- `sys_open` (CreateFileA)
- `sys_stat`/`sys_lstat` (CreateFileA-based probe)
- `sys_unlink`/`sys_rmdir` (DeleteFileA/RemoveDirectoryA)
- `sys_rename` (MoveFileExA)
- `sys_mkdir` (CreateDirectoryA)

Implementation reference:

- `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren`
- `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows_fs.oren`

Return convention note (important for actionable diagnostics):

- `sys_open(path, flags, mode)` returns:
  - **success**: a Win32 `HANDLE` value in `rax` (treated as a “fd-like” integer by the runtime)
  - **failure**: **`-errno`**, mapped from Win32 `GetLastError()` (not just `-1`)

## Windows: do not rely on `OS=Windows_NT` for path parsing

In rolling mode, scripts and shells can execute the compiler in environments where `OS=Windows_NT`
is missing or overridden (PowerShell/SSH sessions, minimal envs, etc.).

Hard rule:

- Path helper functions used for output naming (`basename`, `dirname`) must treat both `/` and `\\`
  as separators, regardless of `OS` env var presence.

## Windows: MSVC wrapper batch scripts and variable expansion

When generating `.cmd` wrappers for MSVC (`VsDevCmd.bat` / `vcvars64.bat`), avoid this pitfall:

- In `cmd.exe`, `%VAR%` expansions inside a parenthesized block are evaluated when the block is parsed,
  so “set then use” within the same `(...)` block can silently read the old value.

Prefer linear `if ...`/`goto` flow, or use delayed expansion (`!VAR!`) carefully.

Implementation reference: `lib/compiler/compiler/040_build_pipeline.oren` (Windows `--backend c` MSVC path).

## Windows: MSVC treats `// ... \` as a line continuation (C4010)

MSVC can treat a trailing backslash at the end of a `//` comment line as a **line continuation**.
This can accidentally comment-out / corrupt the next line and produce confusing errors like
“undeclared identifier” or “syntax error” far away from the real cause.

Hard rule:

- Do **not** end a `//` comment line with `\` in any C runtime sources (`lib/runtime*.c`, `lib/runtime/*.inc`, etc.).
  If you need to show a UNC path, ensure the comment ends with a non-`\` character (example: `... (UNC root)`).

Regression incident:

- `lib/runtime/050_io_misc.inc` had `// UNC prefix: \\server\share\` (ended with `\`), which broke stage0→stage1 bootstrap on Win11/MSVC.

## Windows: `WaitOnAddress` is in `KERNELBASE.dll` (not `KERNEL32.dll`)

The native runtime uses `sys_ulock_wait/sys_ulock_wake` as a portable “wait-on-address” primitive
for its global lock (it parks after bounded spinning).

Non-obvious Windows ABI detail (observed on Win11 `10.0.26220.x`):

- `WaitOnAddress` / `WakeByAddressAll` can be missing as exports from `KERNEL32.dll`.
- If an exe imports them from `KERNEL32.dll`, process startup can fail with `0xC0000139` (`STATUS_ENTRYPOINT_NOT_FOUND`).
- Import them from `KERNELBASE.dll` (or resolve dynamically via `GetProcAddress` on `kernelbase.dll`).

Implementation reference: `lib/compiler/x64_pe.oren` (PE import table) + `lib/compiler/x64_native_program/046_emit_sys_intrinsics_windows.oren` (lowering).

## arm64: rtobj fixups must preserve `reg` (or you can crash at startup)

The arm64 runtime-object cache (rtobj) stores precompiled runtime machine code plus a list of relocation fixups.

Non-obvious invariant:

- For `adr_data` fixups (ADRP+ADD), the destination register matters.
  - Some hot runtime helpers load `g_storage` into scratch registers like `x9`.
  - If the rtobj meta drops `reg`, the final fixup applier defaults to `x0` and the emitted code can end up as:
    - `adrp x0, ...; add x0, x0, ...; ldr x9, [x9]`
    - which dereferences an uninitialized register and typically crashes at startup (`EXC_BAD_ACCESS`, often at `0x1000`).

Rolling rules:

- If you change rtobj fixup encoding/decoding, bump the arm64 rtobj backend signature in `lib/compiler/native_runtime_obj_cache.oren` so stale cache entries are not reused.
- Keep a fast regression check: `./scripts/bench_native_compile_one_file.sh --no-debug` should show a working miss→hit sequence (isolated rtobj dir; seed disabled).

## x64: stale rtobj can mask (or preserve) codegen bugs

The x64 runtime-object cache stores precompiled runtime machine code. If x64 codegen changes in a way that affects runtime correctness, but the x64 rtobj backend signature is not bumped, old cached runtime machine code can keep a fixed bug “alive” (or reintroduce it) even though the source was corrected.

Rolling rules:

- If you change x64 native codegen that can affect emitted runtime code/data bytes, bump `RUNTIME_OBJ_BACKEND_SIG_X64` in `lib/compiler/native_runtime_obj_cache.oren`.
- For debugging, you can force a clean comparison between “rtobj hit” and “no rtobj” builds by setting `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`.
- Diagnostic hygiene: x64 native codegen errors are deduplicated by message (still fatal) to avoid huge logs from repeated sites; if you see one, treat it as a real correctness failure and fix it at the source.
- Regression gates:
  - Fast: `make verify-native-x64-compile` (small fixtures, compile-only, ~10s per build timeout)
  - Higher-signal: `make verify-native-x64-selfhost-compile` (compiles the compiler program for x64 targets; compile-only)
    - Defaults to `oren_x64.oren` (x64-focused; avoids compiling arm64 native backends into x64 artifacts)
    - Override: `OREN_SELFHOST_SRC=oren.oren make verify-native-x64-selfhost-compile`

## Native value semantics: never rely on `scalar == nil`

Rolling invariant (until `docs/BACKENDS.md#native-tagged-value-representation` lands):

- The native backend is still rolling toward a fully tagged value model; do not treat scalars as “optionals” via `nil`.
- Native mode now uses **runtime singleton values** for `nil/false/true` (distinct non-zero pointers stored in globals), which removes the worst historical `0/nil/false` aliasing footguns.
- Guardrail (2026-01-10): the compiler rejects `bool/int/float == nil` comparisons when the scalar side is:
  - statically known (literals, casts, or locally-proven scalars), **or**
  - later proven scalar by best-effort scan (e.g. `var t = cfg["x"]; if t == nil { ... }; i64(t)`, or `t & 255`).
  - Regression fixtures: `tests/fixtures/typecheck_bad_numeric_nil.oren`, `tests/fixtures/typecheck_bad_bool_nil.oren`, `tests/fixtures/nil_guard_bad_late_scalar_nil_compare.oren`, `tests/fixtures/nil_guard_bad_late_bitwise_nil_compare.oren`, `tests/fixtures/nil_guard_bad_late_scalar_nil_compare_top_level.oren`, `tests/fixtures/nil_guard_bad_annotated_call_nil_compare.oren`, `tests/fixtures/nil_guard_bad_param_arith_literal_nil_compare.oren`
  - Fast gate: `make test`
  - Diagnostic: failures are tagged as `nil-compare guard:` (this is always-on; it does not require `--typecheck`).

Concrete rule (treat as a correctness bug in rolling native builds):

- Do **not** write `if x == nil { ... }` when `x` is numeric/bool (or you *expect* it to be).
  - Example footgun: `var x = cfg["timeout_ms"]; if x == nil { x = 1000 }`
  - If you intentionally accept `nil` as “missing” for a numeric/bool parameter (optional arg style), prefer a tag-based check on truly dynamic values:
    - `if oren_type_tag(x) == 0 { x = 0 }`
  - Prefer explicit “optional” shapes instead (e.g. return `{"ok":1,"v":...}` / `{"ok":0}`), or keep the value as `nil`/non-`nil` reference types and avoid using `0`/`false` as “missing” sentinels.
  - Similar footgun for environment variables:
    - Do **not** write `if oren_env("NAME") != 0 { ... }` as a “present” check in rolling native builds.
    - Under singleton-`nil` semantics, a missing env var can return `nil`, and `nil != 0` is true.
    - Preferred: `v != nil && v != 0 && v != ""` (or a small helper that treats `nil/0/""` as “missing”).
  - Guard detail (rolling): the guard’s “later proven scalar” inference is intentionally conservative.
    - It **does** treat arithmetic-with-literal patterns (e.g. `x + 1`, `x * 2`, `x - 1`, `x / 10`) as scalar evidence (covers common dynamic config reads like `cfg["timeout_ms"]`, and also plain locals/params).
      - This catches the common bug pattern: `var t = cfg["timeout_ms"]; if t == nil { ... }; var u = t + 1` (where `t` is clearly being used as numeric later).
      - Regression fixtures: `tests/fixtures/nil_guard_bad_late_arith_literal_nil_compare.oren`, `tests/fixtures/nil_guard_bad_param_arith_literal_nil_compare.oren`
    - For general dynamic values, prefer an explicit cast in the scalar path (e.g. `i64(x)` / `f64(x)`) so the guard can treat it as scalar-likely without over-flagging intentional nil-coalescing idioms in core code.

Practical compiler-internal corollary (x64 emitters):

- If you store a **byte offset** (where `0` is a valid payload) inside a map/dict (e.g. fixup records, offset caches), you must protect `0` from “missing” ambiguity.
  - Current preferred: store the raw `u8` value `0..255`, and use `nil` for “absent”.
  - The legacy “`off+1`” pattern existed only when `nil` was effectively `0` in some rolling-native paths; treat any remaining uses as tech-debt to unwind (example: x64 disp8 encoding).

### Native runtime booleans are singleton values (not `0/1`)

Under the **native backend runtime** (rolling), `nil`, `false`, and `true` are represented as **runtime singletons** stored in the runtime globals block (distinct, non-zero values).

This has a direct consequence for runtime helper APIs:

- `native_value_is_nil(x)` returns the **boolean singleton** `true` or `false`, not numeric `1/0`.
- Therefore:
  - ✅ `if native_value_is_nil(x) { ... }` is correct
  - ✅ `if native_value_is_nil(x) != true { ... }` is correct
  - ❌ `if native_value_is_nil(x) == 0 { ... }` is **always wrong** (both `true` and `false` are non-zero)

Similarly, many “miss” sentinels in the native runtime are `nil`, not `0`:

- `oren_map_get_int(m, k)` returns `nil` on miss (not `0`) in the native runtime.
  - Treat both `0` and `nil` as “missing” unless the API promises otherwise.

## Native strings: embedded literal pool must not hit GC tracking

The self-hosted compiler contains **many** string literals. In native mode, tracking each literal as a heap object (or even creating per-literal metadata nodes) can become a real startup and GC hotspot.

Rolling invariants:

- Native codegen de-duplicates `"literal"` bytes into a single NUL-terminated pool (`cstr0`) embedded in the binary data blob.
- The native entry stub calls `oren_init_static_cstr0_table(...)` once at startup to build a membership set for the literal start pointers.
  - This makes `native_is_string_ptr(...)` safe and fast **without** heap-copying literals.
- String literals must **not** be treated as GC-managed heap allocations:
  - Do not root them (`native_gc_register_root`) and do not “intern” them into heap strings.
  - When you need an owned, tracked string, copy into a heap string explicitly (example helper: `oren_intern_cstr`).

Implementation references:

- cstr0 membership set + init: `lib/runtime_native/100_time.oren` (`oren_init_static_cstr0_table`, `native_cstr0_set_has`)
- string helpers + intern cache: `lib/runtime_native/150_strings.oren`
- safety guard for tracking: `lib/runtime_native/110_mem_diag.oren` (`oren_ensure_tracked`, string kind branch)

Engineering note (self-hosting hygiene):

- Avoid adding new dependencies on external host tools (e.g. `rg`/ripgrep) inside the compiler runtime path.
  - If you need pattern matching for compiler tooling, prefer Oren stdlib modules (regex/tokenization) so the compiler remains self-contained on Tier‑1 targets.

## Oren Implementation Notes (Agent Cache)

This document is a **succinct, rolling “cache”** of important implementation details that are easy to forget and expensive to rediscover by re-reading code.

It is intended for:

- AI agents working on the compiler/runtime/stdlib (to avoid context overflow),
- maintainers reviewing changes across backends,
- power users debugging “why did this lower that way?”

This file is **non-normative**:

- For formal semantics: `docs/LANGUAGE_SPEC.md`
- For practical usage: `docs/LANGUAGE_MANUAL.md`
- For feature maturity + gaps: `docs/STATUS_AND_ROADMAP.md`, `docs/TODOS.md`

---

## 1) Naming + module aliasing: `std:*` → `STD_*` (stable)

### 1.1 Stable stdlib prefix

The module linker uses a **stable prefix** for stdlib modules:

- `std:list` → `STD_list_`
- `std:net/http` → `STD_net_http_`

Implementation:

- `lib/compiler/compiler/020_modules_linking.oren` → `_stable_std_prefix(path)`

### 1.2 Why “alias names” look weird (`M5_list`)

Within a module, an import like:

```oren
import list "std:list"
list.push(xs, 1)
```

is rewritten so the alias is **namespaced by the importing module prefix**:

- `list` becomes `M5_list` (example)
- The call becomes `M5_list.push(xs, 1)` in the merged program AST

This prevents collisions when all modules are merged into one program.

Implementation:

- `lib/compiler/compiler/020_modules_linking.oren` (import alias namespace + `renamer.rename_program_in_place`)

### 1.3 Global alias map: “module-local alias” → “target module prefix”

After linking/merging, the compiler has a global alias map:

- `linked["aliases"]` is a map from `alias_ns` to `dep_prefix`
- Example mapping:
  - `M5_list` → `STD_list_`

This map is used by multiple passes (capsule scanning, impl lowering, bytecode codegen) to resolve
expressions like `M5_list.push` into a **fully-qualified symbol** string.

---

## 2) Namespace expression resolution: `M5_list.push` → `STD_list_push`

Many passes work on AST nodes like:

```json
{"type":"Member","left":...,"prop":...}
```

To resolve imported-module member calls, the compiler uses a helper that:

1) resolves the left side through `linked["aliases"]`, then
2) joins names with underscores to build a **symbol string**.

Example:

- `M5_list.push`
- `aliases["M5_list"] = "STD_list_"`
- result: `STD_list_push`

Implementation:

- `lib/compiler/impl_lowering.oren` → `resolve_ns_name(aliases, expr)`

Note:

- This function trims trailing `_` on prefixes and always joins with `_` so it’s robust across prefix forms.

---

## 3) Container ops: what lowers to what (today)

### 3.1 Method sugar (`xs.push(v)`) is a lowering, not a type system

In rolling v0, builtin container method sugar is implemented as a deterministic rewrite when the
compiler can infer the receiver “kind” from syntax/local flow:

- `xs.push(v)` → `oren_list_push(xs, v)`
- `xs.len()` → `oren_list_len(xs)`

Implementation:

- `lib/compiler/impl_lowering.oren` → builtin container method sugar (`rewrite_expr_in_place` path)

### 3.2 Hot stdlib wrapper inlining (`std:list.push`)

Stdlib exports ergonomic wrappers:

- `std:list.push(xs, v)` returns `nil`
- `std:list.len(xs)` returns int

But in hot loops we want **no wrapper call overhead**. The impl lowering pass recognizes these wrapper calls
via the linked alias map and rewrites:

- `STD_list_push(xs, v)` → `oren_list_push(xs, v)`
- `STD_list_len(xs)` → `oren_list_len(xs)`

Implementation:

- `lib/compiler/impl_lowering.oren` → `rewrite_call_expr(...)` (“Inline stdlib thin wrappers”)

---

## 4) `oren_list_push` return value contract (IMPORTANT)

**Contract (rolling):** `oren_list_push(list, value) -> nil`

Rationale:

- `push` is a statement-like container operation in the language surface (and stdlib wrapper returns `nil`).
- Returning the list header pointer is not needed (the list object identity is stable).
- Keeping a single contract across backends avoids subtle portability bugs when backends inline it differently.

Backends/runtime behavior (source of truth locations):

- Native runtime (native backends): `lib/runtime_native/170_lists.oren`
- C runtime (C backend): `lib/runtime/040_lists_maps.inc`
- AVM: `lib/avm/avm_native.inc` (native id `13` leaves default `nil`)
- Native arm64 inliner: `lib/compiler/arm64_native_expr/030_lowering_c.oren`
- Native x64 inliner: `lib/compiler/x64_native_program/040_emit_expr.oren`

Naming note:

- Stable stdlib symbols use the `STD_*` prefix (`STD_list_push`, `STD_list_len`).
- Legacy lowercase `std_list_*` spellings are not part of the current linking scheme and should not be relied on.

Docs that reference this contract:

- `docs/LANGUAGE_SPEC.md` (builtin container sugar section)
- `docs/AVM_SPEC.md` (native id map)

---

## 5) Native `STACK_TRACE` debug info (arm64 + x64)

### 5.1 What “debug info” means in rolling native

Native backends do not yet emit DWARF/PDB. Instead they embed **best-effort tables** so panics can print readable stack traces.

Current Tier‑1 behavior:

- `oren_panic(msg)` prints a stable `OREN_DIAG ...` line, then prints `STACK_TRACE`, then aborts.
- `STACK_TRACE` is based on a frame-pointer chain (`FP`/`LR` on arm64; `RBP` on x86_64).
- Symbolication uses embedded tables (best-effort; fixed-base emitters on x64).

Implementation (x86_64 native v0 bring-up):

- Stack trace printing: `lib/compiler/x64_native_program/071_panic.oren`
- Symtab storage/fill: `lib/compiler/x64_native_program/010_data_io.oren` (`_data_reserve_symtab`, `_data_finalize_symtab`)
- Call-site linetab storage/fill (debug builds): `lib/compiler/x64_native_program/010_data_io.oren` (`_data_reserve_linetab`, `_data_finalize_linetab`)
- Call-site linetab resolve + printing: `lib/compiler/x64_native_program/071_panic.oren` (`_emit_resolve_loc_ptr_best_effort` + stack-trace loop)

### 5.2 How to enable/disable native debug info

Rolling compiler UX policy:

- Native builds embed stack-trace debug info **by default**.
- Disable with `--no-debug` (or env `OREN_NATIVE_NO_DEBUG=1`).
- Use `--debug` to force-enable (but `--debug` and `--no-debug` together is an error).

Note:

- x64 call-site `@file:line` mapping depends on embedding the linetab (debug mode).
- Function definition locations (`fn@file:line`) come from tokens on function nodes during symtab display synthesis.

### 5.3 Native integer canonicalization (goal + current guard)

**Goal (Tier‑1 invariant):** treat Oren “int” values as **canonical i64** in both registers and stack slots.

- **Registers**: carry full 64-bit values (no “upper bits undefined” model).
- **Stack locals / spills**: use **8-byte slots**; any store must fully initialize all 8 bytes.

Why this matters:

- Many host ABIs and syscalls use 32-bit ints (Windows `DWORD`/`BOOL`, POSIX `int`, socket `socklen_t`, etc).
- Partial-width stores (or reading 8 bytes back from a 4-byte out-param) can create “high 32-bit garbage” values.
- These show up first as **timeout/length/port** corruption and can cause hangs or flaky timeouts on x86_64.

**Current state (rolling):**

- The native runtime includes an i32 canonicalization guard (`native_canon_i32_arg` / `native_canon_timeout_ms_arg`) on some syscall-first NET and thread-timeout entrypoints.
- Debug hook: set `OREN_DEBUG_CANON_I32=1` to emit a single warning when the guard sees a non-canonical i32-ish value (helps catch regressions without dumping huge logs).
- Hard-fail hook: set `OREN_CANON_I32_ABORT=1` to immediately abort on the first non-canonical i32-ish value (exit code `86`).
  - This is the preferred mode for CI / remote Tier‑1 gates because it is high-signal and bounded (no log spam).

**Policy:**

- Treat any guard-trigger as a **native backend correctness bug** to fix at the root.
- Keep the high-signal regression gate green across the matrix:
  - `scripts/verify_native_net_matrix.sh` (NET + loopback services)
  - `scripts/verify_selfhost_x64_compiler.sh` (x86_64 self-host)

---

### 5.4 Pitfall: pointer relational compares can recurse (x86_64)

Background:

- On the x86_64 native backend, some compare lowerings are **string-aware**:
  - if both operands are classified as strings (`native_is_string_ptr(...) != 0`), the backend lowers compares via a byte-wise string compare
  - otherwise it lowers as an integer compare

Pitfall:

- If the runtime uses **pointer relational operators** (`<`, `>`, `<=`, `>=`) as part of string-classification bookkeeping (example: checking whether a pointer is inside the embedded `cstr0` literal pool), the compare lowering can call back into string classification and recurse.

Rolling rule of thumb:

- For address-range checks in the runtime, avoid direct pointer order compares in code paths that can be reached from `native_is_string_ptr`.
- Prefer arithmetic-with-zero forms that stay in integer space and do not trigger string-aware compare lowering (e.g. `(p - min) < 0`, `(p - max) >= 0`, or explicit helpers that compare integer offsets).

## 6) Quick debugging checklist (fast “where is this implemented?”)

Suggested grep/ripgrep pivots (avoid requiring `rg` in minimal environments):

```bash
# Where do stdlib stable prefixes come from?
grep -n \"_stable_std_prefix\\(\" lib/compiler/compiler/020_modules_linking.oren

# How does alias.member resolve to a symbol string?
grep -n \"fn resolve_ns_name\" lib/compiler/impl_lowering.oren

# Where are container wrappers inlined?
grep -n \"Inline stdlib \\\"thin wrappers\\\"\" lib/compiler/impl_lowering.oren

# Where do backends inline list ops?
grep -n \"oren_list_push\" lib/compiler/arm64_native_expr/030_lowering_c.oren lib/compiler/x64_native_program/040_emit_expr.oren

# AVM native id mapping
grep -n \"case 13\" lib/avm/avm_native.inc
```

Shell note (zsh): if you put backticks in an unquoted command string, zsh treats them as command substitution.
Prefer code fences in docs, or escape backticks when running commands interactively.

---

## 7) Platform selection defaults (host auto-detection)

Rolling policy:

- Prefer `--platform <arch>-<os>` for native backend selection.
- Fallback: env `OREN_PLATFORM=<arch>-<os>`.
- If neither is provided, the compiler defaults to the **runtime host platform** (so the same compiler binary can run on macOS/Linux/Windows and "do the right thing" by default).

Implementation:

- Host detection helper: `lib/compiler/compiler/010_cli_helpers.oren` → `detect_host_platform()`
  - Windows: `OS=Windows_NT` + `PROCESSOR_ARCHITECTURE` (`AMD64`/`ARM64`)
  - POSIX-ish: `uname -s` / `uname -m`
- Effective selection is applied in the build pipeline for `build`/`meta`/`dump`:
  - `lib/compiler/compiler/040_build_pipeline.oren`

Regression gate:

- `scripts/verify_selfhost_x64_compiler.sh` intentionally omits `--platform` when running the x64 compiler binaries on Win11 (WSL2 optional), so the gate proves host auto-detection (not just codegen correctness).

---

## 8) Runtime reflection helpers (`oren_type_tag`, `oren_type_name`)

For basic reflection and varargs dispatch, the runtime provides:

- `oren_type_tag(v)` → int tag (matches `lib/runtime.h` `OrenType` enum values)
- `oren_type_name(v)` → stable string name for that tag (logging/branching convenience)

Implementation:

- C runtime: `lib/runtime/040_lists_maps.inc`
- Native runtime: `lib/runtime_native/130_printing.oren`

Rolling note (native backend):

- Native values are not fully tagged yet; numeric immediates (`int`/`bool`/`float`) may be indistinguishable in native mode (so `oren_type_tag` can return `1` for multiple numeric kinds).
- Track the full fix: `docs/BACKENDS.md#native-tagged-value-representation`

Evidence:

- Native quick integration includes a varargs + reflection smoke: `tests/native/test_quick_integration_native.oren` (`test_type_tag_varargs`).

---

## 9) String equality: avoid `==` in compiler passes (stage1 vs stage2)

Oren currently has **multiple runtimes** that execute compiler/tooling code:

- Stage1 compiler: built via the C backend (C runtime semantics)
- Stage2 compiler: built via the native backend (native runtime semantics)

In rolling mode, do **not** assume `==` on strings behaves identically across these runtimes.
In particular, some native-runtime paths historically relied on **interning / pointer identity** as a fast path,
which can break checks that compare:

- a string built via concatenation/slice (non-interned), with
- a string coming from config/env/CLI (often interned), or a literal.

Practical rule (compiler-side code):

- Prefer **byte-wise equality** using `oren_string_len` + `oren_string_byte_at_unchecked` in any pass that must behave the same in stage1 and stage2.

Native runtime note:

- Runtime protocol tags (e.g. iterable-map `__iter`) are now matched by string bytes, guarded by `oren_is_string(...)`,
  so correctness does not depend on literal pointer identity.

Reference implementations:

- Stable helper used in hot compiler code: `lib/compiler/x64_core.oren` → `string_eq_bytes(a,b)`
- `@cfg(...)` evaluation uses its own byte-wise helper to stay portable: `lib/compiler/cfg_lowering.oren` → `_cfg_str_eq(a,b)`
