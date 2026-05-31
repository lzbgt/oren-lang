# Bleeding-Edge Goals and Current Tasks

**Last updated:** 2026-06-01

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
     nested compiler-in-AVM stdlib-OBC compile/run smoke, plus the public
     `OrenAVMCompilerKit` SDK helper that compiles source to OBC through AVM
     VirtualFS/argv.
   - AVM stdlib bundle policy: include portable pure/capability-backed stdlib modules
     by default, but expand through a manifest/size gate so bundle build time remains
     acceptable; keep host-only modules out until AVM shims exist.
   - Remaining required work: Note-side Swift UX integration, allocator ownership
     or explicit single-VM guard, stderr or richer structured diagnostic capture
     if the Note UI needs it, broader compiler/stdlib surface coverage, and CI
     coverage.
   - Gates: `make verify-libavm-ios` and `make verify-compiler-in-avm-ios-chain`.
   - Evidence: `project-doc/ios_avm_readiness_20260507.md`.
   - Stdlib OBC gate: `make verify-libavm-ios` now also runs
     `scripts/verify_avm_stdlib_obc_surface.sh`, which checks
     `tests/fixtures/avm_stdlib_obc_surface_manifest.json` against every import
     in `lib/std/stdlib_avm.oren`, rejects host-only exclusion leaks, generates
     the Oren smoke, and runs it against `build/plugins/stdlib_bundle.obc`.
     This prevents missing app-facing exports such as `STD_linalg_dot_f64` from
     reaching the iOS app.
   - SDK slices retained: `OrenAVMKit.xcframework` now provides deterministic and
     interactive configs, virtual FS/NET/PROC helpers, app file/directory mounts
     into VirtualFS, VFS export back to host files, live host-backed FS directory
     mounts for real app-owned file reads/writes during OBC execution, OBC run, stdout capture,
     verifier proof that interactive `std:time.sleep_ms` blocks the AVM worker on
     wall-clock time, an allowlisted `URLSession` prefetch bridge, and an
     interactive-default live NET callback for OBC `std:net/avm.try_get_text(url)`
     backed by dynamic SDK enable/restrict/disable controls and a reusable SDK
     session, plus first `std:net/avm.session_open/write/read/select/accept/close` TCP/UDP/WebSocket virtual
     session handles and `std:net/avm/tcp` / `std:net/avm/udp` convenience facades
     plus `std:net/avm/ws` over host-owned iOS sockets with readiness selection,
     plus the native `std:avm/events`
     virtual event-bus facade over AVM `EVENT` domain and `std:avm/permission`
     facade and OPR0 permission mailbox for host-visible OBC permission intent,
     plus binary
     GFX frame and input mailboxes for OBC-published `std:ui` frames and
     host-injected pointer/resize/key/text events with Oren-side decoded
     `std:ui/avm.next_event()` maps, and a default UIKit/CoreGraphics
     `OrenAVMGraphicsView` renderer for the current `fill_rect`/`text`/
     `stroke_line`/`circle` subset, plus OBC-safe virtual DNS through
     `std:net/avm/dns` and the iOS live-NET resolver callback, and SDK-enforced
     live VNET session-count/per-session-byte limits, plus host-requested VM
     cancellation through the embed/iOS SDK APIs, plus an
     `OrenAVMPermissionGrantStore` that persists decoded permission decisions and
     reapplies live VNET allowed-host grants/revocations at runtime, plus reviewed
	     TCP listener/accept virtual sessions for OBC server flows, plus
	     host-enqueued FS/package lifecycle events through the AVM `EVENT` bus.
	     Remaining SDK work: visible permission prompt UX, compiler helper
     package, signed package-store support, and the game-grade GUI path:
     display-link pacing, retained resource handles, budget gates, low-latency
	     input ordering, Metal/`MTKView`, richer drawing ops, compact gamepad/controller
	     events, and richer bidirectional input records for motion, focus, and
	     IME/composition helpers. The `OGF0` frame header now includes
     sequence/native-drawable/target-refresh metadata, and AVM validates `OGF0`
     frames plus `OGE0` host input/media-query events before accepting them. OBC
     can read host-populated screen attributes at runtime through
     `std:ui/avm.screen(0)` and can consume media-change events through the same
     virtual event channel: logical size, native drawable size, scale, target
     refresh, and host flags. Curated gates now
     cover malformed-frame rejection, op-count cap rejection, frame I/O-budget
     rejection, the host input queue depth cap, non-1000 resize scale propagation,
     latest-frame replacement/clear semantics, and FIFO pointer down/move/up
     ordering before mixed key/text events.
   - High-priority cleanup: remove legacy stdlib byte/string conversion paths from
     hot AVM app-facing APIs. Raw bytes should stay the performance path; text helpers
     may convert at the boundary but must not force list-of-byte round trips.
     Design notes: `project-doc/ios_avm_sdk_design_20260531.md`,
     `project-doc/avm_ui_render_performance_design_20260531.md`.
   - Follow-up distribution design: after the GUI bridge gate, publish a curated
     signed OBC store repo with package manifests, hashes, capability declarations,
     and iOS download/verify/run flow. Register demo OBC packages there so the
     iOS app has useful downloadable examples once GUI/network gates are ready.
     The intended public store site is `store.hubstack.cn`, with PyPI-like
     release/discovery/download pages backed by the same signed index/package
     schema. The first Go service slice now exists as `cmd/obc-store-server` /
     `internal/obcstore`, with publisher/package/release publish, list/search,
     signed index, browser browse/detail/operator pages, download, and yank APIs.
     Write endpoints now accept an
     external-hash bearer token for deployment automation, while Basic Auth is
     retained for local bring-up. Publisher package/version/release writes now
	     accept publisher-scoped bearer tokens limited to that publisher id, with
	     JSON APIs for token rotation and revocation. Packages are public by default;
	     publisher/admin visibility changes can make a package private, which removes
	     it from public browse/search/index/download surfaces while retaining
	     authenticated owner/admin access.
	     `make verify-libavm-ios` starts the Go service, publishes a signed package
	     through the HTTP API with publisher-scoped auth, and proves iOS SDK
	     install/run from that service. The deterministic `.obc.zip` release bundle
	     format is now specified, emitted by demo tooling, accepted by the service,
	     served by release download APIs, advertised in `index.json`, and preferred
	     by the iOS SDK installer with expanded-artifact fallback; live deployment
	     and richer operator/browser UX remain.
     Design note:
     `project-doc/obc_store_distribution_design_20260529.md`.
     Curated demo package sources now live under `examples/obc_store_demos/`;
     `make verify-obc-store-demos` builds and AVM-runs
     `oren-labs/science-calculator@0.1.0` and
     `oren-labs/ui-card-demo@0.1.0` package directories plus deterministic
     `.obc.zip` release bundles under `build/obc-store-demos`. Official demos
     bundle source as hashed package assets so host apps can show or ignore it.
   - 2026-06-01: first `OrenAVMPackageStore` slices exist and are verified:
     manifest schema/ABI/hash validation, capability/budget/time config derivation,
     read-only package asset mounting into VirtualFS, package OBC run, HTTP
     `index.json` fetch, manifest hash verification, OBC download, declared asset
     download with SHA-256 verification, signed `index.json.sig` verification,
     trusted P-256 publisher signature verification, install, and run. Signature
     enforcement remains host policy: apps can require trust or let users accept
     unsigned/untrusted OBC risk. Persisted app-directory list/load/remove helpers
     are implemented and verified, with staged remote install before final path
     replacement. Explicit install policy is implemented and verified for signed-index
     downloads: replace, keep-existing, and fail-if-installed, including a signed
     `0.2.0` update fixture. A sibling Note handoff/verifier update now checks
     the staged signed package/trust SDK surface (`../note` commit `35995ee`).
     Remaining package-store work is root trust rotation, richer update UX/
     persistence, and visible Note install/update/remove UX.
   - 2026-06-01: `scripts/issue_obc_store_trust.sh` and
     `make issue-obc-store-trust` issue store/publisher P-256 keys and host-app
     trust bundles into an external directory such as `../oren-ca/`; private keys
     remain outside this repo. `OrenAVMOBCTrustBundle` now loads the generated
     JSON and feeds signed-index package downloads directly.

2. **AVM full-suite manifest coverage**
   - `make test-avm` now runs through `tests/avm/release_manifest.json`, which records
     fixture path, expected rc/error, env budgets, backend policy, deterministic mode,
     host-effect checks, and release-gate inclusion.
   - Keep expanding manifest entries beyond the curated release-gate set before
     treating wildcard `AVM_TESTS="tests/avm/*.oren"` as release-grade.

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

5. **Oren language tooling**
   - After the current AVM/OBC store jobs land, build a Go language server and
     VS Code extension for Oren syntax highlighting, diagnostics, completion,
     navigation, and code intelligence.

## Closed/Do-Not-Repeat Families

- Do not re-open Mach-O resolver variants based on generic Oren maps, global sorting,
  future-name rewrites, fixup-side sid lists, or nested bucket structures unless a new
  profile proves they beat the retained first-byte bucket resolver.
- Do not route task-group runtime policy validation through `std:task` helpers until the
  bytecode latency issue is removed.
- Do not treat runtime-native single-occurrence private helpers as dead code without
  stage2 plus fixture-build proof; runtime bundle/rooting can depend on non-textual
  reachability.
