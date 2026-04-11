# Oren Thesis and Differentiation

**Last updated:** 2026-04-11

This page is the concise product thesis for Oren. For the longer research note and archived
Zig source pages, see `project-doc/oren_vs_zig_positioning_20260411.md`.

## Position

Oren is not trying to be a Zig clone or a generic "small systems language".

The project thesis is:

> Oren is an agent-native, syscall-first language and toolchain for deterministic,
> capability-governed execution across native and AVM bytecode backends.

That means Oren should be judged by whether the same program can run under explicit effect
boundaries, reproduce behavior across backends, and produce machine-readable evidence that
humans and agents can use to build, test, repair, and audit the system.

## Distance From Zig

Oren is far from Zig as a production systems-language toolchain:

- Zig has a mature identity around explicit control flow, manual allocator discipline,
  `comptime`, C ABI/toolchain integration, and cross-compilation.
- Oren is still rolling. The native backend is most mature on macOS arm64, x64 Linux/Windows
  are still bring-up surfaces, typecheck remains conservative and opt-in, and W5 hot-loop
  parity remains active work.

Oren is not far from Zig in having an independent product thesis:

- Zig's center is a C-replacement/toolchain story.
- Oren's center should be deterministic native/bytecode execution with capability-governed
  effects and agent-readable tooling.

## Fork Zig Or Continue Oren?

Continue Oren as the mainline project. Do not fork Zig as the primary strategy.

A Zig fork only makes sense as a narrow experimental branch if the goal is to reuse Zig's mature
parser, type system, optimizer pipeline, C ABI integration, and cross-compilation stack. It is a
poor fit as the mainline because Oren's differentiator is not syntax or a better C replacement; it
is the capability-governed native/AVM execution contract. Putting that inside Zig would require
large invasive changes to Zig's language semantics, standard library assumptions, build model,
effect boundaries, runtime profiles, bytecode/VM story, and determinism guarantees.

The stronger strategy is:

- keep Oren independent as the product and semantic contract;
- selectively borrow proven ideas from Zig, especially explicitness, build ergonomics, C interop
  discipline, and compile-time safety constraints;
- keep `comptime`-like work deterministic, budgeted, and capability-scoped rather than copying
  arbitrary host-effectful compile-time execution;
- use Zig as a comparison benchmark and possible host toolchain reference, not as the substrate
  for Oren's language identity.

## Distinguishing Features To Build Around

1. Deterministic capability runtime.
   Programs should declare and run under explicit FS/NET/PROC/ENV/TIME/RNG capability surfaces
   and budgets. Effects should be auditable, replayable where practical, and blocked by default
   in restricted profiles.

2. Native plus AVM parity.
   Native code is for local/server/desktop performance. AVM bytecode is for deterministic,
   sandboxed, governed execution. The language contract should make cross-backend semantic
   parity visible rather than treating it as hidden CI infrastructure.

3. Agent-native toolchain.
   Compiler diagnostics, readiness reports, status matrices, and failure artifacts should be
   structured and machine-readable. This is a first-class developer experience requirement,
   not a side script.

4. Deterministic concurrency and GC interaction.
   Scheduler, channel, and GC behavior should use explicit budgets and reproducible modes where
   possible. This is a stronger differentiator than copying another language's manual memory
   management story.

5. Representation contracts with low-level escape hatches.
   `list<int>`, typed-buffer, packed-view, and SIMD work should converge on safe representation
   contracts that can be optimized directly. Do not ship scalar scheduling toggles as a substitute
   for the real representation fix when the measured gap is representation-level.

6. Capability-aware modules and runtime profiles.
   Imports and runtime profile choices should make effect surfaces visible. Native profiles such
   as `core`, `full`, and `capsule` are the right foundation for this direction. The current
   contract is pinned in `docs/CAPABILITY_RUNTIME_CONTRACT.md`.

## Non-Goals

- Do not lead with "Oren is like Zig, but ...". That positions Oren in someone else's frame.
- Do not copy arbitrary Zig-style `comptime` early. Oren's compile-time execution should be
  deterministic, budgeted, and capability-scoped so compiler-in-AVM remains viable.
- Do not make manual memory management the language identity. Oren can expose low-level lanes,
  but its main differentiation is governed deterministic execution, not forcing allocator
  plumbing into every program.
- Do not promote packed/list-int bridge paths just because they are theoretically attractive.
  Promote them only after stable decision surfaces beat the canonical path.

## Near-Term Proof Bar

Before claiming Zig-like systems-language maturity, Oren needs:

- bounded x64 compile-only verification that stays reliable by default;
- stable native runtime-object cache behavior across Linux/Windows x64;
- a clearer type-system story beyond the current conservative opt-in checker;
- sustained W5 hot-loop and allocation-heavy workload parity progress;
- source-level capability manifests and budget declarations that build on the current
  `docs/CAPABILITY_RUNTIME_CONTRACT.md` runtime-profile contract.
