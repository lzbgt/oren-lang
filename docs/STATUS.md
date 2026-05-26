# Oren Status

**Last updated:** 2026-05-26

This is the current implementation status. It replaces the former rolling log with a
small source-of-truth snapshot. Use code, fixtures, and build logs for raw evidence.

## Overall Verdict

Oren is not yet production-stable at the level of industrial compilers such as
LLVM/rustc/GCC/zig/go. It is a rolling self-hosted compiler with meaningful working
surfaces, but the following blockers remain:

- native tagged-value convergence is incomplete;
- allocator/GC/runtime robustness is still a W5 gate;
- Tier-1 platform breadth is uneven;
- AVM is not production-ready as an iOS embeddable library;
- compiler-in-AVM is fixture-level rather than a packaged production pipeline.

## Backend Readiness

| Backend | Current state | Production posture |
| --- | --- | --- |
| C | Portable bootstrap path through host C toolchain. | Useful baseline, not a stabilized external ABI promise. |
| Native arm64 macOS | Most mature native path; broadest profile and fixture history. | Rolling Tier-1 intent. |
| Native x64 Linux/Windows | Active bring-up with compile/runtime gates. | Not fully mature. |
| Bytecode / AVM | Deterministic VM with capability gates, budgets, snapshots, VFS/VPROC/VNET fixtures, coroutine/generator surfaces. | Experimental for production embedding. |

## AVM and iOS Readiness

Current verdict: **not production-ready for iOS app embedding**.

Facts from the 2026-05-07 inspection:

- The repo has no iOS app/Xcode/Swift integration target for `libavm`.
- `make avm` builds a host arm64 Mach-O executable, not a static library,
  framework, xcframework, or Swift package.
- `lib/avm/avm.h` still exposes fixed global/frame/stack limits and rolling
  capability/budget fields.
- `lib/avm/avm_alloc.c` uses global allocation-owner state, which is not a polished
  reentrant embedder story.
- `avm_free` aborts on leaked heap allocations; this is useful during development
  but is not the expected production iOS failure model.
- Curated `make avm && make test-avm` passes.
- Wildcard `AVM_TESTS="tests/avm/*.oren"` is not a valid release gate today because
  fixture-specific env/expected-error policy is encoded only in selected Makefile cases.
- A direct `AVM_IO_BYTES=128` run of `test_budget_io_fs` returns the expected
  `AVM_ERR_BUDGET`, proving that specific runtime behavior while exposing harness debt.

Detailed note: `project-doc/ios_avm_readiness_20260507.md`.

## Compiler-in-AVM

Current verdict: **fixture-level bootstrap only**.

Working evidence:

- `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren` loads
  `build/oren_compiler.obc` into a nested AVM universe and compiles a small program
  through VFS.
- `tests/avm/fixtures/compiler_in_avm_vfs_stdlib_obc_harness.oren` additionally
  passes `build/stdlib_bundle.obc` as a stdlib OBC resource.

Missing for production:

- stable compiler `.obc` artifact target;
- stdlib OBC resource packaging;
- default release gate for nested compile/run;
- iOS resource-loading and embedder lifecycle coverage.

## Current P0 / W5 Work

1. **Runtime robustness**
   - Keep allocator, GC/reuse, green runtime, and capability gates trustworthy.
   - Verification entry: `make verify-runtime-robustness` plus `make test`.

2. **Performance parity**
   - Track hot loop and allocation profiles through existing benchmark/perf scripts.
   - Retain only measured aggregate wins; many narrow codegen probes have been rejected
     because they moved labels without moving wall time.

3. **Tagged value convergence**
   - Preserve cross-backend `oren_type_tag`, equality, truthiness, and panic parity.
   - Fixture gates remain the migration guard.

## Current P1 / W4 Work

1. **AVM iOS embeddability + compiler-in-AVM release gate**
   - Add iOS simulator/device library packaging.
   - Add Swift/Objective-C smoke host.
   - Make embedder lifecycle and errors deterministic and non-aborting in production mode.
   - Package compiler/stdlib OBC resources and gate nested compile/run.

2. **AVM fixture manifest runner**
   - Replace wildcard `AVM_TESTS` release expectations with manifest-driven per-fixture
     policy: env, expected rc/error, capabilities, deterministic mode, and gate inclusion.

3. **Cross-backend parity**
   - Expand only around real gaps; keep C/native/OBC fixtures aligned.

4. **Native scheduler and green-task maturity**
   - Keep focused runtime gates cheap and deterministic.

## Current P2 / W3 Work

- AVM allocation slabs and list-int lowering.
- Deterministic AVM child-universe scheduling and snapshot/restore maturity.
- Platform breadth for Linux/Windows/x64 paths.
- Documentation and source-file guardrails.

## Key Verification Entrypoints

```bash
./oretest
./oretest --selfhost
make test
make test-curated
make avm
make test-avm
make verify-backend-parity
make verify-runtime-robustness
make docs-site
```

## Documentation Guardrail

Canonical docs should describe current implementation and live blockers only. Do not
paste rolling turn logs into `docs/STATUS.md` or `docs/BLEEDING_EDGE_TASKS.md`; keep raw
evidence in `build/logs/` and short dated conclusions in focused `project-doc/` files.
