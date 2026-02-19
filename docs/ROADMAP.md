# Roadmap

This document captures the staged plan for turning Oren into a production-grade, modern language and toolchain. It specifically addresses the trade-offs highlighted in `docs/COMPARISON.md`.

**Rolling note (execution order):** the active, time-ordered priorities live in `docs/TODOS.md`.
Treat this roadmap as a longer‑horizon narrative; it may lag the rolling tracker.

## Goals
- Fast native codegen for macOS/Linux **arm64 first**, with a portable C backend for bootstrapping and constrained targets.
- Robust type system (generics, interfaces/traits, enums/ADTs, pattern matching) with a sound checker.
- Predictable memory story: optional GC (desktop/server) and deterministic/manual mode (embedded).
- First-class developer ergonomics: formatter, linter, LSP, test runner, package manager, and debugging/profiling hooks.

Agentic/production constraints that drive prioritization (rolling mode):
- **Syscall-first native runtime (no C shims)** for core runtime services on macOS/Linux.
- **Native TCP/IP** support for production server/desktop usage (with explicit timeouts/cancellation).
- **AVM virtualization + multiverse** for safe agent execution (VirtualFS/VirtualNET/VirtualPROC, nested universes).
- **Compiler-in-AVM** (“source → `.obc` inside the sandbox”) for closed-loop deployments without host toolchains.
- **Linux parity early** (validate on QEMU host) to avoid macOS-only drift.

## Mitigation Strategies (Addressing Disadvantages)
- **Runtime Performance**: Move from stack-machine codegen to a Register Allocator (Linear Scan or Graph Coloring) and keep a simple optimization pipeline (const-folding, DCE, peepholes) to close the perf gap with Zig/C.
- **Platform Limitations (rolling stance)**:
  - Tier‑1 native targets are **arm64** (macOS/Linux) and **x86_64** (Linux/Windows). Both are treated as first-class targets for the compiler toolchain.
  - Even with Tier‑1 x86_64, **syscall-first runtime semantics + determinism** remain the architectural drivers: new ISA/OS work must not regress capsule governance, record/replay, or cross-backend semantic parity.
- **Safety**: Transition from conservative stack scanning to **Precise GC** using stack maps generated at compile-time. This prevents integers from being mistaken for pointers (leaks) and enables moving collectors.
- **Ecosystem Split**: Define a `core` library subset that is guaranteed to work in `--no-gc` mode. Standard library modules will be explicitly marked if they require the managed heap.

## Phase 1
- **Memory/GC**: [DONE] Implemented conservative stack scanning and thread registry. Next: Upgrade to **Precise GC** with stack maps, add safepoints and per-frame roots. Refine collection locking.
- **Architecture**: Keep native backend architecture clean so new targets can be added later, but do not spend effort on new CPU/OS targets until syscall-first runtime surfaces are stable.
- **Tier‑1 parity**: keep arm64 and x86_64 aligned on:
  - callable/closure semantics
  - runtime-injection surface (lists/maps/strings, capsule gating)
  - test strategy (fixtures + opt-in remote runs)
- **Concurrency**: Core threading primitives + channels/select exist; current rolling focus is native M:N scheduler groundwork (see `docs/NATIVE_GMP_SCHEDULER.md`, `docs/TODOS.md`).
  - Fact (rolling): Stage N1 green tasks are in place, and Stage N2 worker-mode groundwork exists; true M:N remains a future milestone.
- **FFI/Linking**: [DONE] Implemented real dynamic linking on macOS (ARM64) with `LC_DYLD_INFO_ONLY` binding and GOT stubs. Linux `DT_NEEDED`/PLT pending but architecture is shared.
- **Native backend**: Managed struct allocation in the native runtime (done). Global variable support (done). Next: register allocator groundwork (IR definition).
- **Tooling**: CLI switches parity (codesign/notarize already), add `oren fmt` skeleton and lint scaffolding.

### Phase 1 (Syscall-First Native Runtime Track)
- **Syscall-first OS boundary**: expand/lock `sys_*` surface (FS/PROC/ENV/TIME + NET) and keep all core runtime services behind it.
- **Native TCP/IP (macOS arm64)**: minimal socket/connect/send/recv + timeout/cancellation story.
- **Linux arm64 parity**: implement the same syscall surface and run smoke tests on the trusted QEMU host early and continuously.
- **x86_64 Tier‑1 parity**: validate on real x86_64 continuously (Win11 (WSL2 optional) remote host; see `docs/REMOTE_X64_ENV.md`).

## Phase 2
- **Optimization**: Implement **Register Allocation** (replace stack PUSH/POP with usage of X0-X28). Add basic inlining and const-prop.
- **Concurrency (Core)**: Atomics done. Channels/select implemented (see `docs/LANGUAGE_STATUS_AND_GAPS.md`). OS thread spawn/join exists; next is M:N scheduler + async IO (see `docs/NATIVE_GMP_SCHEDULER.md`).
- **Type system**: Full checker with generics/monomorphization, interfaces/traits, enums/ADTs, pattern matching, result/option-based error handling.
- **Testing & QA**: Built-in test runner, property testing, coverage hooks, fuzz entry points.
- **Package Management**: Module registry layout, vendoring, lockfiles, reproducible builds.
- **Tooling**: Language Server (LSP), debugger symbols (DWARF) for basic stepping support.

## Phase 3
- **AI Readiness**: Implement agent-native features from `docs/AGENTIC_REQUIREMENTS.md` (metadata export, verification, deterministic workflows).
- **Concurrency (Advanced)**: **M:N Scheduler** (Coroutines), **Pub/Sub**, **Fan-Out**, and **Parallel Iterators** (see `docs/CONCURRENCY_MODEL.md`).
- **Targets (future, non-goal by default)**:
  - Oren is explicitly trying to **avoid the WASM toolchain bloat** as a primary deployment story.
  - If WASM is used at all, the intent is **“AVM hosted in WASM”** (run the portable AVM interpreter inside an existing WASM sandbox),
    not “Oren → WASM backend” as a first-class compilation target.
  - This keeps the core niche: small toolchain, syscall-first native binaries, and an agent-safe VM (`.obc`) with VirtualFS/NET/PROC.
- **Async/Tasks**: Async/await or lightweight tasks with a scheduler; GC/stack interaction.
- **Security/Trust**: Deterministic builds, supply-chain verification, signed artifacts, sandboxed exec.
- **Ecosystem**: Standard library build-out (collections, fs/net/crypto/time), cross-platform story (Windows), and polished docs/examples.

### Stdlib direction (rolling)

The stdlib is intentionally built “from the bottom up” without libc shims:

- deterministic parsing/encoding building blocks (`std/json`, `std/yaml`, `std/cbor`)
- deterministic text tooling (`std/regex`)
- small portable math helpers (`std/math`)

Higher-level libraries (HTTP/WebSocket, etc.) will be layered on top of the syscall-first `NET` and AVM VirtualNET domains once those are fully stabilized.

## Agent-Native Track (AVM + Bytecode)
This track is defined in `docs/OREN_EVOLUTION.md` and complements the phases above by targeting restricted environments (iOS/Web/Edge) where native exec toolchains may be unavailable.

- **Phase A (AVM Core)**: Implement `libavm` (C) stack-machine interpreter; define OBC bytecode format + instruction set; validate with a hand-written OBC program.
- **Phase B (Bytecode Backend)**: Add `lib/compiler/codegen_bytecode.oren` (may be composed from smaller parts via `// @include "..."`) and a CLI target to emit `.obc` from the shared AST.
- **Phase C (Inception / Self-Hosting on AVM)**: Stage0 produces `oren.obc`; run compiler-in-bytecode under `libavm` to compile and run user scripts (OBC → AVM).
- **Phase D (`libagent`)**: Safe agent standard library (`fs`, `net/http`, `semantic`, `proc` where allowed) mapped to AVM host primitives.

### Design note: “source → `.obc` inside AVM” closes the loop

The “inception” step is not only for iOS convenience; it is the core agent-native primitive:

- ship source as data
- compile inside a deterministic, budgeted, capability-scoped universe
- validate artifacts by hashes (compiler capsule + produced `.obc`)

This enables swarm governance and self-healing workflows (see `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes` and `docs/AVM_DESIGN.md#avm-swarm-consensus-agent-mobility-design-validation`).

### Next-Gen AVM (No-JIT-First, ML-Oriented)

- Spec draft (Next-Gen plan section): `docs/AVM_SPEC.md`
- Agentic requirements (end-to-end): `docs/AGENTIC_REQUIREMENTS.md`
- Language stability / feature rollout rules (self-hosting): `docs/LANGUAGE_EVOLUTION.md`

Compatibility stance:

- Keep moving fast: **until a stability milestone is explicitly declared, everything is rolling/ABI-unstable**.
- When stability is declared later, the VM/bytecode can introduce explicit versioning and a compatibility policy then.
