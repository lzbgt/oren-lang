# Bleeding-Edge Goals and Current Tasks

**Last updated:** 2026-05-31

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
   - 2026-05-29: native quick `Error 139` is fixed; runtime identity checks now avoid recursive string-aware equality.
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
     VirtualPROC fixture/default, deterministic TIME by default, and stdout-capture
     helpers required by app-host compile/run bridges. `make verify-libavm-ios`
     now proves host compile-to-OBC, iOS C smoke linkage, host embedder
     argv/VFS/TIME/VNET/VPROC load/run, captured stdout retrieval/clear, and a
     nested compiler-in-AVM stdlib-OBC compile/run smoke.
   - AVM stdlib bundle policy: include portable pure/capability-backed stdlib modules
     by default, but expand through a manifest/size gate so bundle build time remains
     acceptable; keep host-only modules out until AVM shims exist.
   - Remaining required work: Swift/Objective-C smoke host, allocator ownership or
     explicit single-VM guard, app-bundle resource loading coverage, stderr or
     structured diagnostic capture if the Note UI needs it, manifest AVM release
     gate, broader compiler/stdlib surface coverage, and CI coverage.
   - Gates: `make verify-libavm-ios` and `make verify-compiler-in-avm-ios-chain`.
   - Evidence: `project-doc/ios_avm_readiness_20260507.md`.
   - Stdlib OBC gate: `make verify-libavm-ios` now also runs
     `scripts/verify_avm_stdlib_obc_surface.sh`, compiling a representative app
     fixture against `build/plugins/stdlib_bundle.obc` and running it in AVM. The
     smoke imports `std:buffer`, `std:bytes`, `std:cbor`,
     `std:encoding/base64`, `std:crypto/pem`, `std:crypto/sha1`,
     `std:crypto/sha256`, `std:crypto/x509`, `std:json`, `std:linalg`,
     `std:math`, `std:net/avm`, `std:regex`, `std:strings`, `std:time`, `std:ui/avm`, and
     `std:yaml`, preventing missing app-facing exports such as
     `STD_linalg_dot_f64` from reaching the iOS app.
   - SDK slices retained: `OrenAVMKit.xcframework` now provides deterministic and
     interactive configs, virtual FS/NET/PROC helpers, app file/directory mounts
     into VirtualFS, VFS export back to host files, OBC run, stdout capture,
     verifier proof that interactive `std:time.sleep_ms` blocks the AVM worker on
     wall-clock time, an allowlisted `URLSession` prefetch bridge, and an
     interactive-default live NET callback for OBC `std:net/avm.try_get_text(url)`
     backed by dynamic SDK enable/restrict/disable controls and a reusable SDK
     session, plus first `std:net/avm.session_open/write/read/close` TCP virtual
     session handles over host-owned iOS sockets, plus binary
     GFX frame and input mailboxes for OBC-published `std:ui` frames and
     host-injected pointer/resize/key/text events with Oren-side decoded
     `std:ui/avm.next_event()` maps, and a default UIKit/CoreGraphics
     `OrenAVMGraphicsView` renderer for the current `fill_rect`/`text`/
     `stroke_line`/`circle` subset.
     Remaining SDK work: UDP/WebSocket/listen/accept/async readiness on the VNET
     session protocol without exposing raw sockets to OBC, compiler helper
     package, package store helper, and the game-grade GUI path:
     display-link pacing, retained resource handles, budget gates, low-latency
     input ordering, Metal/`MTKView`, richer drawing ops, and richer
     IME/composition input helpers. The `OGF0` frame header now includes
     sequence/native-drawable/target-refresh metadata, and AVM validates `OGF0`
     frames plus `OGE0` host input events before accepting them. Curated gates now
     cover malformed-frame rejection, op-count cap rejection, frame I/O-budget
     rejection, the host input queue depth cap, non-1000 resize scale propagation,
     latest-frame replacement/clear semantics, and FIFO pointer down/move/up
     ordering before mixed key/text events.
     Design notes: `project-doc/ios_avm_sdk_design_20260531.md`,
     `project-doc/avm_ui_render_performance_design_20260531.md`.
   - Follow-up distribution design: after the GUI bridge gate, publish a curated
     signed OBC store repo with package manifests, hashes, capability declarations,
     and iOS download/verify/run flow. Design note:
     `project-doc/obc_store_distribution_design_20260529.md`.

2. **AVM full-suite manifest runner**
   - Current `make test-avm` curated list passes, but wildcard `AVM_TESTS="tests/avm/*.oren"`
     is not a valid release gate because some fixtures require specific env budgets,
     expected errors, or backend policy.
   - Add a manifest with fixture path, expected rc/error, env, capability policy,
     deterministic mode, and release-gate inclusion.

3. **Cross-backend parity gates**
   - Expand only where current fixtures expose gaps.
   - Keep bytecode/C/native behavior aligned before adding new user-visible surfaces.

4. **Scientific stdlib math breadth**
   - Expand `std:math` toward C/C++ mathlib coverage without host-libm dependency.
   - Current retained surface includes `pow` / `power` for integer, negative,
     fractional positive-base, infinity edge, and negative-base real-domain cases.
   - Gate app-visible additions through AVM bytecode fixtures first, then native/C parity.

5. **Native scheduler / green-task integration**
   - Keep syscall-first constraints and focused green/runtime gates.
   - Do not treat flake-only probes as retained work unless they improve a default gate.

6. **Reserve + unchecked push generalization**
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
