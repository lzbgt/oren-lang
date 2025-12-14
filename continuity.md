# Oren Continuity Notes

## Strategy (Dec 2025)
Oren is evolving toward an “agent-native” toolchain (see `docs/OREN_EVOLUTION.md`): a hybrid system that can run in both native environments (servers/desktops) and restricted environments (AVM + bytecode).
Fact check (repo state): there is no `libavm` implementation in this repo yet; the AVM/OBC track is a planned next milestone, not an active codepath.

---

## Status
- **Self-hosting:** Go stage0 (`cmd/oren`) -> Stage 1 `oren` -> Stage 2 (Verified).
- **Backends:**
  - **C:** Mainline for self-hosting and semantics. Supports Maps, Lists, GC, and OS threads (`spawn` + join/detach).
  - **Native (ARM64):** Fast but incomplete. Supports SIMD, Atomics, basic GC hooks, syscalls; missing float codegen, general indexing semantics, and full type/print behavior parity.
- **Runtime:**
  - C backend uses `lib/runtime.c` (mutexed, heavy).
  - Native backend uses `lib/runtime_native.oren` (bump-pointer, lightweight).
- **CLI:** codesign/notarize flags on macOS, `--metadata` writes `<out>.meta.json`.

## 🛑 Critical Gaps (Immediate Blockers)
These issues prevent the Native Backend from being "Production Ready":
1.  **No Floating Point:** The Native backend has **zero** support for float literals or math (`1.5 + 2.0`). This blocks all scientific/AI workloads.
2.  **No Collection Access:** While you can *create* Lists/Maps, the compiler cannot generate code to *index* them (`list[0]` or `map["key"]`).
3.  **No String Operations:** Basic concatenation (`"a" + "b"`) is unimplemented in the native code generator.

---

## Recent Achievements
- **Threads + GC (C backend):** `spawn` returns a handle; `oren_join(handle)` / `oren_detach(handle)` implemented. GC now supports stop-the-world safepoints (`oren_gc_safepoint`) and conservative stack scanning so locals can act as roots.
- **Native Heap:** Bump-pointer allocator backed by `mmap` (min 64KB) with free-list reuse and allocation tracking.
- **Syscall Surface:** Inline `sys_write/read/pipe/clone` paths; atomics lowered to ARM64 `LDADD` / `CAS`; SIMD intrinsics fall back to scalar ops when needed.
- **Language Features:** C-style block comments, `for` loops, short `:=` bindings, `test "name" {}` syntax.
- **Native UX:** Native `print("literal")` emits `sys_write` directly.
- **Modules/Tests:** Module system validated via `tests/modules/*`; native suite covers atomics, GC, pipe/channel, SIMD.

## Known Issues (Pitfalls)
- **Native threads:** `sys_clone` (threads) only targets Linux; macOS path returns `-1`. Native backend has no `spawn`.
- **Native runtime GC lifecycle:** `native_gc_unregister_root` unimplemented; `native_gc_shutdown` does no release; GC is conservative without type tags.
- **Native I/O:** Non-literal strings (and other non-int values) still print as raw integers/pointers unless compiled via a specialized path.
- **Semantics parity:** native `&&`/`||` is non-short-circuit today; C backend short-circuits via C lowering.

## ⏭️ Next Steps

### Immediate Priority (Production Semantics + Self-Hosting Safety)
1. **Move from conservative to precise roots** (stack maps / typed IR) to reduce leaks and enable moving GC.
2. **Strengthen thread API** (return values, `is_done`, errors), and add stress tests (concurrent GC, churn).
3. **Lock semantics** in tests (short-circuit, scoping, indexing bounds) so all backends converge on the same behavior.

### Native Backend Parity (Still Needed)
4. **Thread support on macOS** (native backend: thread creation + registry integration).
5. **Native runtime GC lifecycle hooks.**
6. **AVM/OBC track**: implement `libavm` + bytecode backend as per `docs/OREN_EVOLUTION.md` once language core semantics are stable.

### Completed
- **FFI/Linking:** Implemented real dynamic linking on macOS (ARM64) with `LC_DYLD_INFO_ONLY` binding info generation and GOT-based stubs. FFI calls to `libc` (e.g. `puts`) now work correctly.
- **Memory Safety:** Fixed `malloc` implementation to save/restore registers across syscalls, preventing heap corruption.
- **Runtime Init:** Fixed Mach-O entry point to ensure runtime initialization shim is executed, correcting uninitialized globals crash.
- **Indexing:** Implemented `Index` (get) and `Set` (index set) in native backend.
- **SIMD:** Implemented real ARM64 NEON instructions for `simd_*` intrinsics.
- **Float:** Implemented `Float` literal support and `fadd/fsub/fmul/fdiv` intrinsics (native backend).
- **Thread API:** `is_done`, return values, error reporting.

---

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
  - per-thread return value (done)
  - error reporting (done)

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
- **Strategy:** `docs/OREN_EVOLUTION.md` (Read this first!)
- **Source:** `lib/compiler/*.oren`
- **Native Runtime:** `lib/runtime_native.oren`
