# Oren: From Day 0 to Production (Beginner Guide)

**Status:** Canonical guide (beginner-friendly)  
**Last updated:** 2025-12-16  
**Scope:** Why Oren has multiple backends (Go bootstrapper, C backend, native syscall backend, AVM + VirtualFS/NET/PROC), and how they evolve together.

This document is a practical “tour” of the repo’s architecture and evolution path. It is meant for a new contributor who wants to understand:

- why there is a **Go bootstrap compiler**
- why there is a **C backend**
- why the native backend is **syscall-first** (no libc shims)
- why there is an **AVM** (bytecode interpreter) and **VirtualFS/VirtualNET/VirtualPROC**
- how these pieces form a coherent day0 → final-state plan

If you only want commands to build/test, see `docs/BUILD_AND_VERIFY.md`.

---

## 0) The core problem Oren is solving

Oren is “two products in one”:

1) A **native language** (server/desktop): compile `.oren` to a host executable (Mach-O on macOS, ELF on Linux) with strong control over OS boundaries and low dependencies.
2) An **agent-safe execution substrate** (mobile/edge/restricted): compile `.oren` to `.obc` and run on **AVM** (Agent Virtual Machine), with:
   - deterministic mode (TIME/RNG virtualization)
   - explicit capability domains (FS/NET/PROC/ENV/…)
   - Virtual* backends (no-host-effects simulation)
   - nested universes (AVM in AVM) for “Matrix” simulation and swarm verification

The key architectural bet:

> “Governed, replayable execution” matters more than “native peak speed” in v0.

But native performance and full system access must exist too (production/server), so Oren is built as a multi-backend compiler.

---

## 1) Repository components (what lives where)

### 1.1 Stage0 Go bootstrapper (why it exists)

File/entrypoint:

- `cmd/oren` (Go) → builds `oren_bootstrap`

Purpose:

- You cannot compile a compiler written in Oren until you already have *some* compiler.
- Stage0 is a small, stable starting point that compiles `oren.oren` into the stage1 compiler.

This is a standard “bootstrapping” technique used by many languages:

- Stage0 (simple, stable) builds Stage1 (self-hosted, evolves fast).

### 1.2 Stage1 self-hosted compiler (`oren.oren`)

File:

- `oren.oren` — the compiler written in Oren

Purpose:

- Once stage1 exists, Oren can evolve quickly without rewriting Go code.
- Most “language design work” and backend improvements happen here.

### 1.3 Backends (C, native, bytecode)

Oren compiles to different targets depending on goals:

- **C backend**: `.oren → .c → cc` (portable, great for bootstrapping)
- **Native backend**: `.oren → Mach-O/ELF` (fast startup and no C toolchain at runtime)
- **Bytecode backend**: `.oren → .obc` (portable, safe execution on AVM)

These are not competing ideas; they form an evolution ladder.

---

## 2) The C backend (what it is for, and why it stays)

Doc:

- `docs/C_BACKEND.md`

Purpose:

1) **Self-hosting reliability**
   - The C backend is a very practical “stable target” because `cc` exists everywhere.
2) **Portability**
   - It gives Oren a cross-platform story early (even when the native backend is incomplete).
3) **Debugging baseline**
   - If native backend miscompiles, the C backend provides a reference implementation path.

Tradeoffs:

- Requires a C toolchain (compile-time dependency).
- C runtime (`lib/runtime.c`) currently uses libc for many operations. That is acceptable for the C backend’s role.

Important: the production goal for the **native syscall-first runtime** is different. Don’t confuse the two:

- C backend runtime can use libc (it’s a portability/bootstrapping tool).
- native backend runtime must be syscall-first (independence goal).

---

## 3) The native backend (syscall-first, no libc shims)

Docs:

- `docs/NATIVE_BACKEND.md`
- `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`

What “syscall-first” means in this repo:

- Runtime services (`oren_*`) should not depend on libc/pthreads as the implementation substrate.
- OS interaction happens through a narrow `sys_*` boundary that the compiler lowers to real syscalls.

Why this matters:

- It prevents a predictable rewrite later (“use libc shims now, rewrite them out later”).
- It makes the runtime boundary explicit and auditable (critical for correctness and determinism).
- It aligns conceptually with AVM’s capability domains: “effects are explicit and governable”.

Current practical reality:

- macOS arm64 is the primary target.
- Linux arm64 exists but must be validated continuously (QEMU host is used for this).

### 3.1 How syscall-first relates to concurrency and networking

If Oren eventually wants:

- lightweight threads / coroutines
- native TCP/IP networking

…then it needs syscall-first “blocking primitives” and “event waiting” primitives:

- Linux: futex + poll/epoll
- macOS: ulock + kqueue/kevent (or poll/select; kqueue is usually the cleanest integration point)

That’s why the syscall boundary must be designed first and kept small.

---

## 4) AVM (Agent Virtual Machine) and `.obc`

Docs:

- `docs/AVM_SPEC.md` (bootstrap, implemented today)
- `docs/AVM_SPEC_V1.md` (next-gen plan)
- `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes` (nested universes)
- `docs/AVM_DESIGN.md#avm-swarm-consensus-agent-mobility-design-validation` (swarm validation/mobility)
- `docs/AVM_DESIGN.md#avm-concurrency-model-deterministic-syscall-first-aligned-multiverse-friendly` (deterministic tasks design)

AVM exists because there are real environments where:

- JIT is restricted/banned (iOS/App Store)
- shipping a native toolchain is not possible
- you want deterministic replay, policy scanning, and “no-host-effects” simulation by default

So Oren can compile to bytecode (`.obc`) and run under a VM with strong governance.

Important clarification (to avoid confusion with the native syscall-first backend):

- The **current AVM is a portable C implementation** (`lib/avm` + `./avm`).
- Like the **C backend**, the C AVM may use libc for convenience (CLI, buffers, parsing), because it is a *bootstrap/portability artifact*.
- The **“no libc shims” rule applies to the native backend runtime**, not to every bootstrap component.
- Long-term direction (documented elsewhere in this repo): AVM becomes an **Oren-native stdlib/syslib component**, and the “compiler-in-AVM” loop closes without requiring an OS toolchain on restricted devices.

### 4.1 Capability domains and Virtual backends

In AVM, effectful operations are explicit:

- FS domain
- NET domain
- PROC domain
- ENV domain
- TIME/RNG domains
- (and an AVM domain for nested universes)

Virtual* backends are the “safe simulation” mechanism:

- **VirtualFS**: in-memory filesystem, deterministic, no host FS effects
- **VirtualPROC**: deterministic subprocess fixtures, no host process spawn
- **VirtualNET**: deterministic network fixtures, no host network

This is the key to:

- running untrusted code as a capsule
- deterministic replay across nodes
- multiverse simulation (thousands of sandboxes inside one program)

---

## 5) Multiverse (AVM in AVM): why it’s not just a gimmick

Doc:

- `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`

“Nested universes” are a pragmatic agent primitive:

- outer agent runs N simulated candidate plans
- each plan runs in a child universe with VirtualFS/VirtualNET fixtures
- results are compared via hashes and trace summaries

This makes agent behavior:

- testable
- replayable
- governable

### 5.1 “Compiler in AVM” closes the loop

The “final” restricted deployment story is:

1) AVM runs `oren.obc` (the compiler as a bytecode capsule).
2) The compiler reads source code from VirtualFS.
3) It emits `.obc` into VirtualFS (or returns it as BYTES).
4) AVM runs the newly produced `.obc`.

This is the cleanest way to get “source → executable logic” on devices where:

- you cannot run `cc`
- you cannot download/exec native binaries dynamically

---

## 6) Day 0 → Final State (typical evolution path)

This is the guiding story of “how languages get built” applied to Oren’s goals.

### Day 0: get something working end-to-end

- Implement stage0 bootstrap compiler (Go).
- Implement enough language to compile a minimal program.
- Build stage1 compiler (`oren.oren`) so evolution is fast.

### Day 1: choose a stable portability substrate

- Use a C backend to make the self-hosting chain robust and portable.
- Keep language semantics stable enough that stage1 can rebuild itself.

### Day 2: add a real native backend (host binaries)

- Native codegen produces Mach-O/ELF directly.
- Runtime is injected (default: `lib/runtime_native.oren`, expanded from `lib/runtime_native/*.oren` via `// @include "..."`), not libc-based.
- Add tests to prevent hangs and ABI regressions (timeouts are mandatory).

### Day 3: add an agent-native execution substrate (AVM)

- Bytecode backend emits `.obc`.
- AVM runs `.obc` with:
  - verifier and policy scanner (scan before execute)
  - budgets and deterministic mode
  - VirtualFS/VirtualNET/VirtualPROC

### Day 4: unify it into a production story

- Native syscall-first runtime grows real TCP/IP + concurrency primitives.
- Linux parity becomes continuous (QEMU smoke tests).
- AVM gains deterministic cooperative tasks (agent-grade concurrency).
- AVM becomes embeddable as a “library of Oren” (a stable `libavm` API + Oren bindings).
- Compiler-in-AVM enables closed-loop compilation for restricted deployments.

---

## 7) Where to look next (practical)

- “What to do next”: `docs/TODOS.md`
- “How to build/test”: `docs/BUILD_AND_VERIFY.md`
- “Syscall-first runtime plan”: `docs/SYSCALL_FIRST_RUNTIME_PLAN.md`
- “AVM bootstrap spec”: `docs/AVM_SPEC.md`
- “Multiverse design”: `docs/AVM_DESIGN.md#avm-in-avm-multiverse-design-nested-virtual-universes`

---

## 8) Blue-ocean opportunities (what Oren should focus on)

This section captures “advanced but feasible” opportunities that fit Oren’s core niche:

> deterministic, capability-governed, multiverse-executable agent software,
> where code + execution context + traces are portable artifacts that a swarm can validate.

These are intentionally *not* “general purpose language ecosystem parity” goals.

### 8.1 Capsules/jobs as the unit of software distribution

AVM already has the primitives to make “what you ship” a verifiable capsule:

- program (`.obc`) + `PROGRAM_HASH_SHA256`
- policy scan + `POLICY_HASH_SHA256`
- execution context binding (`EXEC_HASH_SHA256`)
- inputs binding (`INPUT_HASH_SHA256`)
- outputs: `RESULT_HASH`, `STATE_HASH`, optionally `TRACE_HASH`

This can evolve into:

- content-addressed caches for agent runs (“don’t recompute what’s already verified”)
- swarm validation workflows (“k-of-n agreement on hashes”)
- supply-chain governance (pin allowed module hashes + capability domains)

### 8.2 Deterministic trace as the primary debugging interface (agent-first)

Instead of “logs for humans”, AVM’s trace stream should be treated as:

- machine-readable evidence (for agents)
- diffable between runs (“first divergence point”)
- budgeted and semantics-preserving (“diagnostics must not change results”)

This is a natural complement to self-healing loops (run → evidence → patch → replay).

### 8.3 Multiverse simulation as a planning primitive

Nested universes + VirtualFS/VirtualNET fixtures enable:

- evaluate many candidate plans safely (no host effects)
- deterministic replays across nodes
- hierarchical budgets to prevent denial-of-service

This is a “Matrix sandbox” engine built into the runtime model, not a bolt-on test harness.

### 8.4 Compiler-in-AVM closes the loop (governed in-memory compilation)

A strong restricted deployment story is:

- AVM runs `oren.obc` (compiler capsule)
- compiler reads source from VirtualFS
- compiler emits `.obc` into VirtualFS or returns BYTES
- child universe runs the produced `.obc` under strict caps + budgets

This makes compilation:

- deterministic (when deterministic mode is enabled)
- auditable (policy + job hashes bind the context)
- sandboxed (no host toolchain)

### 8.5 “No-JIT-first, service-side acceleration later” (semantics preserved by gas)

AVM should stay interpreter-first to keep the iOS/edge story clean.

Later, a server-side accelerator (AOT/JIT) can exist *as an implementation detail* if:

- the semantic gas model is stable enough that different engines charge the same “work”
- deterministic mode remains deterministic (TIME derived from gas + explicit sleep, RNG seeded)

### 8.6 What we are **not** optimizing for (by design, for a long time)

To preserve focus and avoid infinite rewrites, Oren/AVM should **not** chase near-term goals like:

- “AVM is a universal runtime for mainstream languages” (Wasm already owns this ecosystem)
- “full language feature parity with Rust/Go” before the execution substrate is solid
- “peak microbenchmark performance” ahead of determinism/governance/multiverse reliability

Instead, Oren’s differentiator is that it is designed for agentic workflows:

- deterministic replay
- explicit capability domains and virtualization
- nested universes and swarm validation
