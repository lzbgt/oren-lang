# Bleeding-Edge Goals and Current Tasks

**Last updated:** 2026-05-28

This file is the concise task view. Detailed implementation status lives in
`docs/STATUS.md`; dated investigation notes live in `project-doc/`.

## Goals

- Deterministic execution with capability-gated effects across native, C, and AVM.
- Cross-backend semantic parity guarded by fixtures and targeted verification.
- Native performance approaching C on hot loops and allocation-heavy workloads.
- Production-grade runtime robustness: allocator, GC/reuse, scheduler, and effect domains.
- AVM portable bytecode suitable for sandboxed execution once embedding and release
  gates are mature.
- Documentation and tooling that stay small enough to navigate quickly.

## P0 / W5

1. **Runtime robustness and allocator correctness**
   - Keep `make verify-runtime-robustness` and `make test` green.
   - Treat GC/reuse/list-header integrity as a blocking production concern.

2. **Native performance parity**
   - Track hot-loop and allocation gates through the existing performance scripts.
   - Do not retain local codegen probes unless profiles prove aggregate wall-time wins.

3. **Tagged value convergence**
   - Preserve cross-backend `oren_type_tag`, equality, truthiness, and panic parity.
   - Continue migration through compatibility fixtures rather than unguarded ABI rewrites.

## P1 / W4

1. **AVM iOS embeddability and compiler-in-AVM release gate**
   - Current verdict: iOS `LibAVM.xcframework` packaging and a C embedder API now
     exist. The public API includes argv, VFS input/output, VirtualNET fixture,
     VirtualPROC fixture/default, and stdout-capture helpers required by
     app-host compile/run bridges. `make verify-libavm-ios` now proves host
     compile-to-OBC, iOS C smoke linkage, host embedder argv/VFS/VNET/VPROC
     load/run, captured stdout retrieval/clear, and a nested compiler-in-AVM
     stdlib-OBC compile/run smoke.
   - Remaining required work: Swift/Objective-C smoke host, allocator ownership or
     explicit single-VM guard, app-bundle resource loading coverage, stderr or
     structured diagnostic capture if the Note UI needs it, manifest AVM release
     gate, broader compiler/stdlib surface coverage, and CI coverage.
   - Gates: `make verify-libavm-ios` and `make verify-compiler-in-avm-ios-chain`.
   - Evidence: `project-doc/ios_avm_readiness_20260507.md`.

2. **AVM full-suite manifest runner**
   - Current `make test-avm` curated list passes, but wildcard `AVM_TESTS="tests/avm/*.oren"`
     is not a valid release gate because some fixtures require specific env budgets,
     expected errors, or backend policy.
   - Add a manifest with fixture path, expected rc/error, env, capability policy,
     deterministic mode, and release-gate inclusion.

3. **Cross-backend parity gates**
   - Expand only where current fixtures expose gaps.
   - Keep bytecode/C/native behavior aligned before adding new user-visible surfaces.

4. **Native scheduler / green-task integration**
   - Keep syscall-first constraints and focused green/runtime gates.
   - Do not treat flake-only probes as retained work unless they improve a default gate.

5. **Reserve + unchecked push generalization**
   - Continue from measured optimizer/list-int evidence only.

## P2 / W3

1. **AVM allocation slabs, typed buffers, and list-int lowering**
   - Important for performance, but not sufficient for production iOS readiness without
     embedding/package/harness gates.

2. **Deterministic AVM scheduler maturity**
   - Continue budgeted child-universe scheduling and snapshot/restore work after the
     release harness can prove current behavior.

3. **Platform breadth**
   - Keep x64 Linux/Windows and arm64 Linux bring-up behind focused compile/runtime gates.

4. **Docs and source guardrails**
   - No source file should exceed 2000 lines.
   - Keep canonical docs concise; archive raw history in logs or focused project notes.

## Closed/Do-Not-Repeat Families

- Do not re-open Mach-O resolver variants based on generic Oren maps, global sorting,
  future-name rewrites, fixup-side sid lists, or nested bucket structures unless a new
  profile proves they beat the retained first-byte bucket resolver.
- Do not route task-group runtime policy validation through `std:task` helpers until the
  bytecode latency issue is removed.
- Do not treat runtime-native single-occurrence private helpers as dead code without
  stage2 plus fixture-build proof; runtime bundle/rooting can depend on non-textual
  reachability.
