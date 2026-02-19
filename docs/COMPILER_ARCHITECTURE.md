# Compiler Architecture Notes (Rolling)

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

- `docs/TOOLCHAIN_SELF_HOSTING.md`
- `docs/BUILD_AND_VERIFY.md`
- `docs/BACKEND_ARCHITECTURE.md#native-backend-overview`

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

- `docs/BUILD_AND_VERIFY.md` (`--lib` output expectations and scan behavior)

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

- `docs/COMPILER_GOTCHAS.md` (“Native value semantics: never rely on scalar == nil”)
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
- `docs/TEST_SYSTEM.md` (why some fixtures use small `@cfg` glue)

### 3.3 Native string literals are constant-section data (not GC objects)

Rolling rule:

- Embedded literals are pooled into `cstr0` and must not be tracked as heap allocations.

Docs:

- `docs/COMPILER_GOTCHAS.md` (“Native strings: embedded literal pool must not hit GC tracking”)

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

- `docs/BUILD_AND_VERIFY.md` (Windows C backend policy)
- `docs/REMOTE_X64_ENV.md` (Win11 (WSL2 optional) workflow)

## 5) Performance and hang-debugging entry points

Fast regression/diagnosis helpers:

- `make test` (native quick integration; bounded)
- `./scripts/bench_native_compile_one_file.sh` (bounded compile-one-file benchmark)

Primary playbook:

- `docs/BACKEND_ARCHITECTURE.md#native-backend-performance-playbook`

When a build step “hangs”, prefer:

- adding **bounded trace markers** (opt-in env flags) over dumping huge logs
- using existing per-step timeouts in `scripts/*` and escalating only when necessary

