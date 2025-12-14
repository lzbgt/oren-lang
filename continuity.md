# Oren Continuity Notes

## 🚨 STRATEGIC PIVOT (Dec 2025)
**We have redefined Oren as the "First AI-Native Language" (Synth-Origin).**
The goal is to build **AVM (Agent Virtual Machine)**: a hybrid runtime that supports Native execution (Servers) and Interpreted Bytecode (iOS/Edge).
*   **Vision:** "PostScript for Agents." Safe, Resumable ("Pause and Heal"), and Mobile-Compliant.
*   **Current State:** The `libavm` (Bytecode VM) project is **PAUSED**.
*   **Blocker:** The Native Backend (`codegen_arm64.oren`) lacks critical features (Floats, Indexing, String Ops).

---

## Status
- Self-hosting chain: Go stage0 (`cmd/oren`) builds stage1 `oren`; Makefile target `oren_stage2` exercises stage2. Default backend is C; native ARM64 Mach-O/ELF is available via `--backend native` (with `--target linux`).
- Compiler is split across `lib/compiler/*.oren` (lexer, parser, ast, analysis, codegen, transpiler, metadata). Module loader prefixes imports, checks alias conflicts, and enforces consistent struct field offsets before merging.
- C backend uses `lib/runtime.c` (tracked mark/sweep GC with mutexed list/map ops). Native backend injects `lib/runtime_native.oren` (bump-pointer heap + reuse list, conservative GC hooks, thread registry, inline syscalls).
- CLI: codesign/notarize flags on macOS, `--metadata` writes `<out>.meta.json` (functions/structs), `--analyze` prints scope info. `--emit-c` is only supported for the C backend.

## Recent Achievements
- Native heap: bump-pointer allocator backed by `mmap` (min 64KB) with free-list reuse and allocation tracking; `oren_alloc_struct` centralizes struct buffers for GC accounting.
- GC plumbing: runtime globals initialized at entry, main thread registered before user code, conservative stack scan over registered threads, mark/sweep over tracked lists/maps/strings, and block-scope cleanup in codegen to restore stack slots.
- Syscall surface: inline `sys_write/read/pipe/clone` paths (macOS uses X16 + SVC #128; Linux uses X8 + SVC #0); atomics lowered to ARM64 `LDADD` / `CAS`; SIMD intrinsics fall back to scalar ops when needed.
- Language/runtime: C-style block comments, `for` loops (init/cond/post), short `:=` bindings, `test "name" {}` lowered to `fn test_name`, writable data segment for globals/string literals, metadata export implemented.
- Native UX: native backend now captures `argc/argv` and implements `oren_args()`. Native `print("literal")` emits `sys_write` directly so string-literal output is readable (variables are still untyped).
- Concurrency (C backend): added `spawn` for zero-arg functions (`spawn foo()`) backed by `pthread_create`. `spawn` returns a handle (`OrenValue` int) and can be synchronized via `oren_join(handle)` / `oren_detach(handle)` (with `oren_join_all()` used for coarse shutdown).
- Modules/tests: module system validated via `tests/modules/*`; native suite covers atomics, GC, pipe/channel, SIMD, maps/lists/structs; Makefile drives bootstrap + native/C test runs.

## Known Issues
- **Native Backend Holes (CRITICAL):**
    - **No Floating Point:** Compiler crashes or errors on float literals/math.
    - **No Collection Access:** Can create Lists/Maps but cannot read from them (`Index` expr missing).
    - **No String Concatenation:** `+` operator only handles integers.
- `sys_pipe` SIGILL (macOS ARM64) was traced to a native backend `&&`/`||` codegen bug that corrupted the emitted instruction stream; fixed in `lib/compiler/codegen_arm64.oren`. `test_pipe`/`test_pipe_direct` now run to completion in `make test`.
- Threads: `sys_clone` only targets Linux; macOS path returns `-1`, and there is no `spawn` wrapper or thread registry hookup beyond the main thread.
- Native backend has no `spawn` yet (would require thread creation + stack registration without relying on dynamic linking).
- Native runtime gaps: `native_gc_unregister_root` unimplemented; `native_gc_shutdown` does no release; GC is conservative without type tags/stack maps, so integers or non-heap pointers may be skipped or mis-marked.
- Native I/O/printing has no type tags; non-literal strings (and other non-int values) still print as raw integers/pointers unless compiled via a specialized path.
- FFI/import stubs just return `0` (see native import stub generation); no PLT/GOT or dyld linking; metadata export only lists function names/args and struct fields.

## Next Steps
1. **[IMMEDIATE] Native Backend Stabilization:**
   - Implement `Index` expressions (`list[0]`) in `codegen_arm64.oren`.
   - Implement Floating Point (Literals + NEON instructions).
   - Implement String Concatenation (Runtime calls).
2. Add a `spawn` wrapper and macOS thread-creation path, wiring new threads into the registry/stack scanner.
3. Finish native GC lifecycle hooks (`native_gc_unregister_root`, `native_gc_shutdown`), then move toward precise roots (stack maps / typed values).
4. Build a test runner that enumerates and runs `test_` functions (or generates a `main` runner when tests are present).
5. Expand native runtime ergonomics beyond string literals (printing, diagnostics) and broaden syscall coverage (files, sockets, etc.).

## Prioritized TODOs
This list is derived from:
- `docs/ROADMAP.md` (production language/toolchain roadmap)
- `docs/OREN_EVOLUTION.md` (agent-native / AVM + bytecode strategy)
- Current implementation state (C backend is the “mainline” backend for self-hosting; native backend is WIP).

### P0 — Production Safety & Correctness

#### Concurrency + GC correctness (C backend first)
- Make GC safe with long-lived threads (C backend).
  - Implemented: cooperative stop-the-world handshake (`oren_gc_safepoint()`), loop safepoint injection, and conservative per-thread stack scanning so locals can act as roots.
  - Still P0 hardening:
    - Define invariants (what must be safe at safepoints; which runtime ops require safepoints).
    - Add stress tests (more threads, concurrent `oren_gc_collect()`, allocation churn).
    - Upgrade from conservative scanning to precise roots (stack maps / typed IR) to avoid leaks and enable moving GC.
- Evolve thread API to a production surface:
  - `spawn` returns a handle (done)
  - `join(handle)` / `detach(handle)` (done)
  - `is_done(handle)` (done)
  - `per-thread return value` (done)
  - `error reporting` (done)

#### Spec/behavior conformance tests (must gate regressions)
- Add tests for language semantics that diverge across backends:
  - `&&` / `||` short-circuit behavior (native currently evaluates both sides; C backend short-circuits via C).
  - `for` variants, scoping/shadowing, assignment targets, list bounds, map literals.
- Add negative tests (expected compile errors) so parser/transpiler behavior is deterministic.

#### Build/test ergonomics (self-hosting guardrails)
- Keep stage1 rebuild correctness (Stage1 should rebuild when `lib/**/*.oren` changes).
- Keep `make test` failing on the first failing test.
- Add a first-class test runner (`oren test` or generated runner for `test "name" {}` blocks).

### P1 — Toolchain & Ecosystem

#### FFI/linking story
- C backend: define/document a stable FFI surface (how to link extra `.o` / `.a` / system libs).
- Native backend: implement real dynamic linking:
  - macOS: `LC_LOAD_DYLIB`, stubs + lazy binding (or minimal dyld-compatible approach)
  - Linux: `DT_NEEDED`, PLT/GOT relocations

#### Tooling
- Formatter skeleton (`oren fmt`)
- Linter scaffolding
- LSP minimal set (go-to-def, hover) using metadata, then expand metadata beyond names/fields.

### P2 — Native Backend Maturity (Correctness → Performance)
- Implement missing runtime primitives needed for parity (threads/spawn, richer printing/diagnostics).
- Align semantics with C backend (especially short-circuiting and runtime behavior).
- Then performance work: register allocation + peephole opts (per `docs/ROADMAP.md`).
- **[NEW] Implement Floating Point, Indexing, and String Ops (See Next Steps).**

### P3 — Agent-Native Evolution (AVM + Bytecode)

#### Phase 1: AVM Core (`libavm`)
- Implement `libavm` in C as a small stack machine interpreter.
- Define the OBC instruction set + binary format (versioned).
- Validate by running a hand-written “hello world” OBC program under `libavm`.

#### Phase 2: Bytecode backend (`codegen_bytecode.oren`)
- Add `lib/compiler/codegen_bytecode.oren` and a CLI target (e.g. `--backend bytecode`).
- Emit `.obc` from the shared AST.

#### Phase 3: “Inception” (self-host inside AVM)
- Stage0 produces `oren.obc` (compiler-in-bytecode).
- Run `oren.obc` under `libavm` to compile user scripts to OBC, then execute under `libavm`.

#### Phase 4+: `libagent` standard library + LLM guide
- Build safe agent primitives on top of AVM host capabilities (`fs`, `net/http`, `semantic`, `proc` where allowed).
- Create `LLM_GUIDE.md` focused on token efficiency and reliable prompting for Oren.

## Reference
- Source/compiler: `lib/compiler/*.oren`
- Native runtime: `lib/runtime_native.oren`
- C runtime: `lib/runtime.c`
- Build/Test: `Makefile`, `tests/*`
