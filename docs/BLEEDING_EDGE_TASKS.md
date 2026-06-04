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
   - Current verdict: iOS `LibAVM.xcframework` packaging, macOS desktop
     `LibAVM.xcframework` packaging, Linux x64 static `LibAVM` packaging, Windows
     x64 static `LibAVM` packaging, and a C embedder API now exist. The public API includes argv, VFS input/output,
     VirtualNET fixture, VirtualPROC fixture/default, deterministic TIME by default,
     and stdout-capture helpers required by app-host compile/run bridges.
     `make verify-libavm-ios` now proves host compile-to-OBC, iOS C smoke linkage,
     host embedder
     argv/VFS/TIME/VNET/VPROC load/run, captured stdout retrieval/clear, and a
     nested compiler-in-AVM stdlib-OBC compile/run smoke, a shared app-scale
     CompilerKit fixture covering trait receiver methods, struct field chains,
     codec method chains, buffer/linalg APIs, and Scene3D package authoring,
     plus the public
     `OrenAVMCompilerKit` SDK helper that compiles source to OBC through AVM
     VirtualFS/argv.
   - Desktop SDK gate: `make verify-libavm-desktop` builds macOS arm64/x86_64
     `LibAVM.xcframework` slices, checks public embedder symbols in both archives,
     and runs local host C and Swift embedders against OBC bytes.
   - Linux x64 SDK gate: `make verify-libavm-linux-x64` cross-builds the C embedder
     static library with Zig, exports headers/module-map/pkg-config metadata, checks
     x86_64 ELF output and embedder symbols, and compiles a Linux x64 host embedder
     smoke. Runtime execution is QEMU-gated when an emulator is present.
   - Windows x64 SDK gate: `make verify-libavm-windows-x64` cross-builds the C
     embedder static library with Zig, exports headers/module-map metadata, checks
     amd64 COFF output and embedder symbols, and compiles a Windows x64 host
     embedder smoke. Runtime execution is Wine-gated when available.
   - AVM stdlib bundle policy: include portable pure/capability-backed stdlib modules
     by default, but expand through a manifest/size gate so bundle build time remains
     acceptable; keep host-only modules out until AVM shims exist.
   - Default AVM gate breadth now includes portable stdlib bytes/buffer views,
     u8 buffer iteration, checked integer casts, crypto hash vectors, iterator
     ranges, and Scene3D package assets.
   - Remaining required work: Note-side Swift UX integration, stderr or richer
     structured diagnostic capture if the Note UI needs it, larger multi-file
     compiler-in-AVM app suites, and CI coverage.
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
     interactive-default live NET callback for OBC `http.get(url).text()` /
     `http.get(url).bytes()` through `std:net/avm/http`
     backed by dynamic SDK enable/restrict/disable controls and a reusable SDK
     session, plus first `std:net/avm/socket.open/write/read/select/accept/close` TCP/UDP/WebSocket virtual
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
     `stroke_line`/`stroke_rect`/`circle`/`ellipse`/`polyline` subset, plus OBC-safe virtual DNS through
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
	     and coalesced motion events, focus records, and IME/composition records.
	     The `OGF0` frame header now includes
     sequence/native-drawable/target-refresh metadata, and AVM validates `OGF0`
     frames plus `OGE0` host input/media-query events before accepting them. OBC
     can read host-populated screen attributes at runtime through
     `std:ui/avm.screen(0)` and can consume media-change events through the same
     virtual event channel: logical size, native drawable size, scale, target
	     refresh, and host flags. Curated gates now
     cover malformed-frame rejection, op-count cap rejection, frame I/O-budget
     rejection, the host input queue depth cap, non-1000 resize scale propagation,
     latest-frame replacement/clear semantics, and FIFO pointer down/move/up
     ordering before mixed key/text events. Metal retained text now uses bounded
     SDK-side atlas packing plus same-atlas/scissor/opacity run coalescing so
     repeated and adjacent labels reduce texture churn and draw calls without
     changing the `OGF0` protocol.
   - High-priority cleanup: remove legacy stdlib byte/string conversion paths from
     hot AVM app-facing APIs. Raw bytes should stay the performance path; text helpers
     may convert at the boundary but must not force list-of-byte round trips.
     Rolling API design now favors scoped objects and method chaining over
     root-level convenience helpers: NET uses `http.get(url).text()` /
     socket scopes, and codecs/bytes expose `"{}".json().text()`,
     `"a: 1\n".yaml().text()`, `cbor.cint(7).bytes().cbor()`, and
     `"hi".bytes().text()` through stdlib source and OBC metadata.
     Base64 and crypto hashes now follow the same rule with
     `"hi".bytes().base64()`, `"aGk=".base64_bytes().text()`, and
     `bytes.from_string("abc").sha256_hex()` while keeping the byte hot
     path on exact-size `u8_buf` output. SHA-1/SHA-256 digest outputs and native
     RNG bytes now write directly into fixed-size/result `u8_buf` buffers. HPACK
     Huffman string encode/decode and full header-block encoding now write
     exact-size `u8_buf` payloads, and PEM/Base64 body handling avoids
     materializing Oren byte lists.
     Buffer views now expose wrapper objects over zero-copy slices,
     strides, and matrices, so callers can write `buf.slice(1, 3).text()` and
	     `buf.matrix(2, 3).row(1).text()` without explicit local annotations
	     instead of routing through root-level projection helpers.
	     `make verify-stdlib-api-shape` now blocks known bad root-helper regressions:
	     public fallible APIs should use the normal verb and return `value | oren_err`,
	     while syscall-style primitives use explicit `*_raw` names. The guard now covers
	     NET plus app-facing codec/parser/RNG helpers such as JSON/YAML/CBOR, Base64,
	     regex, PEM/X509, time parsing, crypto random bytes, HPACK/HTTP2 record
	     helpers, and UI color/PPM helpers.
     Native TCP/UDP/TLS/WebSocket and AVM virtual socket/TCP/UDP/WebSocket now
     follow the same session/object rule with examples like `conn.read_into(...)`,
     `socket.send_to(...)`, `conn.write_from(...)`, `conn.recv_text(...)`,
     `listener.accept(...)`, `session.recv_text(...)`, and
     `http2_client.new(...).request(...).text()`.
     XML/HTML follow the same rule with streaming readers first for large OBC
     payloads and DOM/query convenience on top. Native HTTP can use
     `response.html_reader()` / `response.html().find("title").text()`; AVM/OBC
     packages should opt into the parser explicitly and compose
     `response.text().html_reader()` to keep the default stdlib bundle inside
     iOS CompilerKit memory budgets.
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
	     by the iOS SDK installer with expanded-artifact fallback. Operator status
	     now exposes deployment gates plus bundle/source/signature/permission
	     readiness counts, and authenticated operator release lifecycle inventory
	     pages/APIs expose visibility, readiness, latest-published state,
	     publish/yank/visibility action URLs, no-JS browser forms for those
	     release/package mutations, authenticated update inventory page/API for
	     latest/superseded package versions, authenticated append-only audit
	     page/API for successful store mutations, checked Traefik dynamic route
	     generation for the cloud-host backend, a public live-route smoke target
	     with strict release-readiness mode, and a local data-dir backup/restore
	     smoke for metadata plus artifacts; live deployment polish remains.
     Design note:
     `project-doc/obc_store_distribution_design_20260529.md`.
     Curated demo package sources now live under `examples/obc_store_demos/`;
     `make verify-obc-store-demos` builds and AVM-runs
     `oren-labs/science-calculator@0.1.0`, `oren-labs/ui-card-demo@0.1.0`,
     and `oren-labs/scene3d-asset-demo@0.1.0` package directories plus
     deterministic `.obc.zip` release bundles under `build/obc-store-demos`.
     Official demos bundle source as hashed package assets so host apps can
     show or ignore it, while store-only deterministic 640x360 PNG screenshots
     are published as release presentation metadata outside package manifests,
     client runtime assets, and bundles. Package detail pages render declared
     Oren source in-browser with syntax highlighting and an AST outline.
	     Scene3D package assets now include compact `boxes_xyz` cuboid authoring,
	     `prisms_xy` extruded polygon authoring, and bounded
	     Wavefront OBJ, binary-or-ASCII STL source lowering, inline ASCII STL
	     text lowering, binary-or-ASCII PLY source lowering,
	     inline ASCII PLY text lowering, PLY face/vertex colors to `mesh3d_rgba`, plus
	     `cylinders_z`/`cones_z`/`spheres_xyz`/`ellipsoids_xyz`/`toruses_xyz`/`capsules_z` authoring that lower to existing
	     byte-native triangle mesh records for AVM/iOS without renderer ABI changes.
	     Curved solid packers are split into `std:ui/scene3d_shapes` so broader
	     package formats can keep growing without pushing `std:ui/scene3d` toward
	     the source-line guardrail.
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
     `0.2.0` update fixture. Sibling Note handoff/verifier updates now check
     the staged signed package/trust SDK surface and expose visible update-status
     checks plus trusted package updates in the package manager (`../note` commit
     `86efc55`).
     The store service now exposes a package update-check endpoint that returns
     latest published release metadata plus `update_available`, and the iOS SDK
     exposes `OrenAVMPackageUpdateStatus` so host apps can query it from an
     installed package or explicit update URL before applying an install policy.
     Remote installs persist their source index URL inside SDK install metadata, so
     update checks can survive app relaunch without duplicating source-store state
     in each host app. The SDK can also install the latest trusted update from
     that persisted source metadata, and successful installed-package checks persist
     a last-known update status/check timestamp for offline host UI recovery.
	     Remaining package-store work is live deployment polish.
   - 2026-06-01: `scripts/issue_obc_store_trust.sh` and
     `make issue-obc-store-trust` issue store/publisher P-256 keys and host-app
     trust bundles into an external directory such as `../oren-ca/`; private keys
     remain outside this repo. The tool can include previous store public keys in
     the bundle for root rotation, and the service publishes the active index
     signing key id through signature headers and operator status.
     `OrenAVMOBCTrustBundle` now loads the generated JSON and feeds signed-index
     package downloads directly.

2. **AVM full-suite manifest coverage**
   - `make test-avm` now runs through `tests/avm/release_manifest.json`, which records
     fixture path, expected rc/error, env budgets, backend policy, deterministic mode,
     host-effect checks, and release-gate inclusion.
   - The manifest runner now supports multi-phase cases with per-phase env/args,
     cleanup, host-effect checks, line-prefix captures, and cross-phase assertions.
   - Nested multiverse AVM/VNET/VPROC/VFS fixtures and VFS inheritance are now
     release-gated with explicit setup builds and deny-default host policy.
   - Existing `tests/avm/test_*.oren` fixtures are now all present in the manifest;
     future work should add release metadata when new AVM fixtures are introduced.

3. **Cross-backend parity gates**
   - Expand only where current fixtures expose gaps.
   - Keep bytecode/C/native behavior aligned before adding new user-visible surfaces.
   - Verification should stay proportional to the touched surface: run focused
     feature/performance fixtures first, then the affected release or SDK gate.
     Avoid blanket platform sweeps unless ABI, packaging, or embedder code changed.

4. **Scientific stdlib math breadth**
   - Expand `std:math` toward C/C++ mathlib coverage without host-libm dependency.
   - Current retained surface includes `fmod`, IEEE-style nearest-even
     `remainder`, `modf`, public ties-to-even rounding aliases, `ilogb`/`logb`,
     `fdim`, `nextafter`/`nexttoward`, `pow` / `power` for integer, negative, fractional
     positive-base, infinity edge, and negative-base real-domain cases,
     `cbrt` with normal/subnormal classification and sign/non-finite coverage, cancellation-aware
     `expm1`/`log1p`, release-gated hyperbolic `sinh`, `cosh`, and `tanh`,
     inverse hyperbolic `asinh`, `acosh`, and `atanh`, plus release-gated
     `sin`, `cos`, `tan`, `atan`, `atan2`, `asin`, `acos`, and approximate
     real-valued `erf`/`erfc` bytecode coverage.
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
   - No source file should exceed 2000 lines; `make verify-source-line-guard`
     enforces this for tracked first-party source files.
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
