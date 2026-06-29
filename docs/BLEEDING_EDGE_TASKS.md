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
     stdout-capture helpers required by app-host compile/run bridges, plus a
     one-shot `avm_runner` API for the common run/capture lifecycle.
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
     and runs local host C, Swift, and `avm_runner` embedders against OBC bytes.
   - Linux x64 SDK gate: `make verify-libavm-linux-x64` cross-builds the C embedder
     static library with Zig, exports headers/module-map/pkg-config metadata, checks
     x86_64 ELF output and embedder/runner symbols, and compiles a Linux x64 host
     `avm_runner` smoke. Runtime execution is QEMU-gated when an emulator is present.
   - Windows x64 SDK gate: `make verify-libavm-windows-x64` cross-builds the C
     embedder static library with Zig, exports headers/module-map metadata, checks
     amd64 COFF output and embedder/runner symbols, and compiles a Windows x64 host
     `avm_runner` smoke. Runtime execution is Wine-gated when available.
   - Native x64 compile gate: `make verify-native-x64-compile` now prewarms
     Linux/Windows x64 runtime-object seeds through an explicit bounded
     cross-compiler compatibility probe, avoiding slow stage2 cold-build
     prewarm hangs while preserving stage2 output checks.
	     The compiler now uses `oren.oren` as the single root for x64 self-host
	     compiler artifacts as well: import-level `@cfg(arch=...)` prunes inactive
	     backend imports during dependency discovery, replacing the former
	     `oren_x64.oren` / `compiler_x64.oren` wrapper files while preserving
	     lightweight arm64 backend stubs for x64 compiler builds.
		     x64 native emit now contributes build/codegen/ELF milestones to
		     `OREN_TRACE_BUILD_PHASES_PATH`. Cached x64 runtime-object fixups now
		     persist byte-native u64 sidecars for runtime call targets, RIP-data
		     patches, code-lea patches, and function-object pointers. Local
		     steady-state probing reduced cached runtime-object ELF replay from
		     roughly 31s to about 0.53s; remaining tiny-build emit time is now in
			     local/entry ELF fixups and final binary assembly. x64 now records
			     global-root name/offset/runtime lists in compiler ctx and new
			     runtime-object metadata, then emits entry root registration through
			     one offset-table loop instead of one `lea+call` sequence per root.
				     Cached x64 runtime-object entries now persist root/global metadata
				     sidecars and lazily derive them from legacy metadata once, so direct
				     unified `oren.oren` x64 self-host builds can adopt root lists without
				     rebuilding the runtime object or walking the legacy globals map in the
				     hot apply path. x64 function/body phase markers now narrow synthesized
				     `__top_level__` global initializer emission precisely. Integer constants
				     (including signed prefix literals and namespace aliases) plus nil/bool
				     singleton globals are materialized directly in `.data`; string global
				     `.data` relocation is explicit opt-in via `OREN_X64_GLOBAL_STRINGS_IN_DATA=1`
				     because capped self-host probes still show it dominating
					     `x64.codegen.top_globals.user_slots`. Default string literal global
					     assignments instead use a non-dedup byte-native cstr append path inside
					     synthesized `__top_level__`. Phase summaries count top-level string
					     fast-path candidates/hits plus direct global-slot path counts, and
					     `OREN_TRACE_X64_TOP_GLOBAL_SLOT_SLOW_MS` enables bounded per-slot
					     slow records for opt-in `.data` relocation probes. The no-dedup
					     cstr append path now extends the data builder directly from strings
					     instead of allocating temporary byte buffers. A focused x64
					     top-level string-global compile fixture guards the fast path.
							     Zero-result lambda collection now skips the full statement walk when no
							     local function/lambda candidates were found. Empty map/list globals stay
							     in `__top_level__` until static mutable container headers have an explicit
								     heap/GC ABI. Bounded slow-function rankings now persist in
								     `OREN_TRACE_BUILD_PHASES_PATH` logs. Phase logs also include
								     `link.parse_module.start`, so capped self-host probes identify the active
								     module even when it does not finish before timeout. Serial/thread module
								     ASTBIN writes are now explicit prewarm work via
								     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_MIN_MS`; `0` selects every parsed
									     module as a candidate and `false` disables serial-write candidates. Actual
									     serial ASTBIN writes stay opt-in behind
										     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_ASTBIN=1` and now use a
										     module-specialized v2 ASTBIN writer with known-key traversal, one-pass
										     cached-pointer body emission, and `OREN_TRACE_ASTBIN_MODULE` phase
										     tracing. Forced prewarm is bounded by
									     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_MAX_PARSE_MS` (default `250`;
									     `0`/`false` disables the parse-cost ceiling) plus the existing node budget.
									     Cache reads and fork-worker writes remain enabled, and explicit serial
									     prewarm now logs cache-write start/skip/encode/done phases. Module cache
									     directories still default to the compiler executable signature, and
									     controlled profiling runs can set
										     `OREN_MODULE_ASTBIN_CACHE_COMPILER_SIG` to reuse entries across stage2
											     rebuilds. `OREN_TRACE_ASTBIN_MODULE_SHAPES=1` prints the first bounded
											     full-vocabulary fallback map shapes for future module-writer profiling.
											     Focused no-artifact-cache proof: forced generator-import prewarm now writes
											     `std:result` in about 26ms, `std:time` in about 86ms, and `std:generator`
											     in about 247ms; the next process warm-hits all three with `cache_hit=1`
											     and `parse_ms=0`. Trait metadata maps are now covered by known-key
											     traversal instead of falling through to the full key vocabulary, so the
											     default parse budget remains a safety guard rather than a workaround for
											     these std modules. Capped full x64 self-host traces now complete module
								     parsing through `lib/compiler/compiler.oren`, finish the optimizer, and
								     reach x64 native emit. With direct string globals disabled,
									     `top_globals.user_slots` finishes in under a second; opt-in direct-string
									     probes now have direct string appends, slot counters, path/substep slow-slot
									     records, positive-only scalar fact metadata, and demand-driven data-constant
									     alias metadata, but compiler-shaped traces still show a per-slot direct
									     metadata/root bookkeeping cliff. The synthesized `__top_level__`
									     string-global assignment fast path now runs before generic expression
									     validation and local fact updates, so literal string globals bypass the
									     slow generic assignment path. Consecutive top-level string literal globals
									     now lower through a batched x64 op with direct encoded global-slot offsets,
									     reducing the compiler-shaped `__top_level__` statement count from 123 to
									     15; `OREN_TRACE_X64_EMIT_OP_SLOW_MS` records bounded slow op summaries.
									     The next concrete throughput target is the per-item emitter work inside
									     that batched string-global op before returning to post-`__top_level__`
									     x64 user-function codegen throughput.
	     Host `rtobj-seed` now uses the same bounded stage1 build-compiler fallback
	     when a compatible stage2 runtime-hash seed is missing, so local NET/native
     matrix prewarm does not burn the verifier budget on repeated stage2 cold
     seed probes. The ARM64 Linux Docker NET leg still keeps the 10s stage1 hang
     guard, but uses a 900s stage2 cross-build floor because active self-hosted
     Linux NET/HTTP2 fixture compiles exceeded both the generic 120s stage2
     floor and a 300s trial on the primary dev host.
     Stage1 native quick now fails if a timeout-triggered retry was needed, and
     the retry enables `OREN_QI_TRACE=1` so hang symptoms leave fixture-boundary
     evidence in the preserved log.
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
     pure `std:net/url` HTTP/WebSocket endpoint parsing shared by native and AVM-safe NET code,
     plus pure `std:sys` AVM capability-domain id/name/mask helpers,
     `std:env` capability-gated get/fallback/presence/truthy facade helpers,
     pure `std:path` slash-separated VFS/package path and traversal-safe root-join helpers,
     `std:fs` capability-gated text/byte/list-dir and root-scoped facade helpers,
     `std:proc` capability-gated run/status/result-combinator facade helpers,
     portable `std:timer` deadline/interval helpers and the native `std:avm/events`
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
     changing the `OGF0` protocol. `make capture-ios-live-3d-performance`
     now builds the generated iPhoneOS live 3D capture app, runs its OBC program
     concurrently with `OrenAVMMetalView`, and republishes animated 3D frames from
     host `frame_tick` events; install/launch is opt-in via
     `OREN_IOS_LIVE_INSTALL=1` because it requires a provisioning profile that
     matches both the bundle ID and the target device. The target now writes
     `build/ios-live-3d/signing-preflight.json` and fails before the iOS build
     when install is requested with a missing or non-installable development
     profile. The 2026-06-27 `blu-ip` phone run installed and launched the
     generated app with Xcode's managed wildcard development profile, linked SDK
     categories through `-ObjC`, fixed Metal shader/CPU vertex stride matching
     through packed shader structs, and completed a 120-frame physically rotated
     cube mesh capture with stable normal-based lighting, phone-copied PNG
     snapshots, and 0 over-budget frames.
   - High-priority cleanup: remove legacy stdlib byte/string conversion paths from
     hot AVM app-facing APIs. Raw bytes should stay the performance path; text helpers
     may convert at the boundary but must not force list-of-byte round trips.
     Rolling API design now favors scoped objects and method chaining over
     root-level convenience helpers: NET uses `http.get(url).text()` /
     socket scopes, and codecs/bytes expose `"{}".json().text()`,
     `"a: 1\n".yaml().text()`, `cbor.cint(7).bytes().cbor()`, and
     `"hi".bytes().text()` through stdlib source and OBC metadata.
     Base64 and crypto hashes now follow the same rule with
     `"hi".bytes().base64()`, `"aGk=".base64_bytes().text()`,
     `"TWE".base64_url_bytes().text()`, and
     `bytes.from_string("abc").sha256_hex()` while keeping the byte hot
     path on exact-size `u8_buf` output; plain UI `text` frame commands now also
     write string bytes directly into OGF0 payloads, and UI color parsing reads
     hex digits directly from ASCII string bytes. SHA-1/SHA-256 digest outputs and native
     RNG bytes now write directly into fixed-size/result `u8_buf` buffers. HPACK
     plain literal decode now slices the header block directly, while Huffman
     string encode/decode, decoded-string boundaries, and full header-block
     encoding use exact-size `u8_buf` payloads or byte-slice conversion; TLS
     ALPN decoded-byte strings also convert through byte slices. HTTP/2 client
     continuation/header-block and DATA response buffering now uses amortized
     `u8_buf` accumulators, and PEM/Base64 body handling avoids
     materializing Oren byte lists with strict PEM body concatenation through raw
     exact-size writes; Base64/Base64URL decode also rejects malformed padding and
     nonzero trailing pad bits before returning exact-size `u8_buf` decoded bytes. `std:strings` prefix/suffix/search/equality
     and trim helpers plus JSON full decode/tag equality, CBOR canonical key ordering/text
     encoding/decode byte carriers, and full regex
     pattern/text matching now use direct string
     byte reads/slices. YAML comment stripping, quoted-scalar parse/escape,
     line/trim/key split, key sort, bare-identifier, prefix, and suffix helpers
     also avoid list-of-byte reconstruction, while XML/HTML parser literal
     matching, class-selector scans, DOM parsing, and streaming readers no
     longer allocate input byte lists for syntax tokens. WebSocket accept
     hashing now feeds SHA-1 directly from UTF-8 string bytes, and native
     WebSocket header slices plus unmasked frame payloads copy with `oren_memcpy`;
     DNS QNAME labels and capsule NET IPv4 sockaddr reads/rewrites also copy
     through `oren_memcpy` after validation;
     Base64/Base64URL
     decode/encode writes exact-size output buffers directly, PPM header/body
     output and software raster clear/pixel writes use raw exact-size buffer stores, and native `std:net/http`
     caches typed response body bytes for `.bytes()` on content-length and
     chunked responses. Native `oren_write_file` writes strings directly
     through syscalls without a transient byte list, and SHA-1/SHA-256 string
     hashing now reads UTF-8 string bytes directly for WebSocket accept values,
     Windows Schannel passphrase cache keys, and callers that already hold text;
     SHA-1/SHA-256 digest buffers finalize through direct unchecked u8 stores
     after exact-size allocation, and native SHA-256 contiguous input remainders
     copy with `oren_memcpy`.
     Compiler source-policy
     scans, scan-cache line/number parsing and delimiter writes, C-runtime include scanning,
     compiler manifest JSON escaping, byte-native bytecode metadata payloads, OBX
     string/prefix encoding, AST binary v1 full-value raw writes, bytecode string
     constants, native Mach-O/ELF object string payloads, runtime-object
     debug-name blobs, x64 native debug-table names, ARM64 native panic-message
     payloads, native runtime string concat/intern/slice copies, native capsule
     mount path resolution, realpath segment output, readdir names, and
     UNIX-socket path copies through `oren_memcpy`, shared compiler byte-builder
     append/list/string/set stores, C
     identifier escaping with raw exact-size output writes, raw u8/view/u8-matrix
     string copy helpers, `std:bytes.from_string`/`from_hex`, `std:strings` byte roundtrips,
     `std:bytes` u8/endian writes, concat/copy u8-buffer spans, overlap-safe
     u8 `copy_into`, `std:buffer` view/matrix `copy_from_bytes` direct
     carrier reads, contiguous slice/dense-matrix byte/text exports, and
     raw u8-buffer load/store plus `copy_into` u8-buffer destinations, native byte-order writes,
     and `std:time` ISO-8601 UTC parsing now use direct source-string byte reads
     or exact-size/raw-pointer buffers too.
     Buffer views now expose wrapper objects over zero-copy slices,
     strides, and matrices, so callers can write `buf.slice(1, 3).text()` and
     `buf.matrix(2, 3).row(1).text()` without explicit local annotations
     instead of routing through root-level projection helpers.
     `make verify-stdlib-api-shape` now blocks known bad root-helper regressions:
     public fallible APIs should use the normal verb and return `value | oren_err`,
	     while syscall-style primitives use explicit `*_raw` names. The guard now covers
	     NET plus app-facing codec/parser/RNG helpers such as JSON/YAML/CBOR, Base64,
	     regex, PEM/X509, time parsing, crypto random bytes, HPACK/HTTP2 record
	     helpers, UI color/hex/PPM helpers, and `std:buffer` u8 view loads/stores.
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
		     now exposes deployment gates plus aggregate release-ready/incomplete counts,
		     missing bundle/source/signature/permission readiness counts, and data-dir
		     writable/storage byte totals by metadata/payload class, and
	     authenticated operator release lifecycle inventory
	     pages/APIs expose status/visibility/readiness filters, visibility,
	     readiness, latest-published state,
	     publish/yank/visibility action URLs, no-JS browser forms for those
		     release/package mutations, authenticated filterable update inventory page/API for
		     latest/superseded package versions by publisher/package/visibility/superseded state
		     with total/filtered counts, authenticated filterable append-only
		     audit page/API by action/actor/target with total/filtered counts, checked Traefik dynamic route
	     generation for the cloud-host backend, admin-env host fallback plus explicit
	     `sshpass -e` password mode for deployment, optional authenticated deploy-time
	     operator-status storage/readiness probes, public build-stamped health/status
	     metadata, a public live-route smoke target with strict build/release-readiness/operator-status modes, and a local data-dir backup/restore
	     smoke for metadata plus artifacts; live deployment replacement is currently
	     blocked by rejected SSH credentials for the configured admin host.
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
	     `prisms_xy` extruded polygon authoring, bounded `heightfields_xy` terrain grids,
		     bounded `surfaces_xyz` arbitrary surface grids, rectangular `planes_xy`, filled `rounded_rects_xy`, flat `polygons_xy`,
		     regular `regular_polygons_xy`, `stars_xy`, circular `discs_xy`/`rings_xy`,
	     elliptical `ellipses_xy`/`ellipse_rings_xy`, thick `segments_xy`/`paths_xy`, sampled `beziers_xy`, partial `sectors_xy`/`arc_bands_xy`, sloped `ramps_xy`, solid `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, and
	     glTF 2.0 JSON and GLB source lowering with URI/BIN buffers, sparse accessors, static `POSITION` and `COLOR_0` morph target weights, baked skinning through `JOINTS_n`/`WEIGHTS_n` and inverse bind matrices, sampled `gltf_animation` / `gltf_sample_time_milli` node translation/rotation/scale/morph-weight animations, material colors multiplied by `COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix hierarchy selection,
	     Wavefront OBJ, binary-or-ASCII STL source lowering, inline ASCII STL
	     text lowering, binary-or-ASCII PLY source lowering,
	     inline ASCII PLY text lowering, PLY face/vertex colors to `mesh3d_rgba`,
	     core 3MF ZIP mesh/build plus basematerial `displaycolor` lowering and
	     optional `3mf_triangle_set` subgroup selection,
	     package-authoring `scale_xyz_milli` pre-scaling, `pivot_xyz`, plus
	     `rotation_xyz_milli_deg` Euler rotation and `rotation_z_milli_deg`
	     shorthand, and `translation_xyz` for JSON coordinate and generated primitive meshes, plus
	     `cylinders_z`/`cones_z`/`spheres_xyz`/`ellipsoids_xyz`/`toruses_xyz`/`capsules_z` authoring that lower to existing
	     byte-native triangle mesh records for AVM/iOS without renderer ABI changes.
	     Procedural mesh packers are split into focused `std:ui/scene3d_shapes_flat`,
	     `std:ui/scene3d_shapes`, `std:ui/scene3d_shapes_arch`, and
	     `std:ui/scene3d_shapes_grid` helpers so broader package formats can
	     keep growing without pushing `std:ui/scene3d` or one shape helper toward
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
     `remainder`, `remquo`, `modf`, integer rounding aliases
     `lround`/`llround`/`lrint`/`llrint`, `copysign`, public ties-to-even rounding aliases, `ilogb`/`logb`,
     `fdim`, `nextafter`/`nexttoward`, `pow` / `power` for integer, negative, fractional
     positive-base, infinity edge, and negative-base real-domain cases,
     `cbrt` with normal/subnormal/`fpclassify` classification and sign/non-finite coverage,
     tolerance predicates `isclose`/`isclose_abs`, finite `lerp`, range mapping helpers `inverse_lerp`, `remap`, and
     `remap_clamped`, graphics scalar/interpolation helpers `sign`, `step`,
     `fract`, `clamp`, `saturate`, `smoothstep`, and `smootherstep`,
     angle wrapping, shortest-angle delta, and shortest-path angle interpolation,
     pure finite `std:math/vec2` helpers including projection/rejection/reflection,
     pure finite `std:math/vec3` helpers including projection/rejection/reflection,
     pure finite `std:math/vec4` helpers including projection/rejection/reflection,
     pure finite `std:math/quat` helpers for axis-angle rotation, inverse, and interpolation,
     pure finite row-major `std:math/mat4` algebra, transform, normal-matrix, normal transform, model-view-projection composition, orthographic/frustum/perspective projection, screen project/unproject, and view helpers,
     overflow-aware `midpoint`,
     scaled two- and three-argument hypotenuse, cancellation-aware
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
   - Build out `oren-lsp` and VS Code support for Oren syntax highlighting,
     diagnostics, completion, navigation, and code intelligence.
  - Current slices add a dependency-free Go JSON-RPC stdio language server with
    `initialize`/`shutdown`, full-document sync, deterministic bracket/string
    diagnostics plus parser-backed diagnostics on open/change, clean close
    handling, keyword/local-symbol completion, direct imported-module alias
    completion, typed struct/class field completion after proven receivers,
    and lexer-backed document symbols for imports, functions,
    variables, structs, and classes, same-file,
    opened-document cross-file, and import-resolved unopened-module definition
    navigation for relative and `std:` modules, plus lexer-backed hover and
    references over the same current/open/imported workspace graph with bounded
    transitive import traversal and cycle guards, scoped function-parameter
    definition/hover/reference navigation with nested shadowing,
    constructor-inferred same-file and direct-import-alias struct/class field
    definition/hover/reference navigation with direct variable-alias propagation,
    direct named factory-return inference including `return if/else` expression branches plus factory-return field-chain evidence, direct typed constructor/factory
    expression receiver field navigation/completion plus constructor-field
    and constructor-bound variable/alias field-chain inference/completion, homogeneous list/hash indexed receiver evidence for field navigation and direct literal completions,
    list `for-in` loop element receiver evidence for field navigation/references and call-site parameter propagation,
    nested constructor-bound call-site parameter field-chain inference,
    source-brace scoped local/list-for-in receiver completions inside function blocks,
    consistent direct call-site parameter inference with conflict
    invalidation, direct parameter-return propagation,
    consistent conditional branch return and assignment inference, unknown-assignment invalidation,
    and conservative prepare/rename workspace
    edits for exact scoped parameters and same-document typed fields, plus
    full-document semantic-token classification for declarations/references/literals/operators and parser-derived
    parameter/property classes.
  - Current VS Code package slice adds the `.oren` language contribution, TextMate
    syntax grammar, language configuration, `vscode-languageclient` activation, and
    a smoke verifier for manifest/grammar/config/entrypoint integrity.
  - Remaining work is richer member inference beyond direct constructor/alias/factory-expression/factory-return-field-chain/constructed-field/constructor-bound-alias-field-chain/call-site/parameter-return/conditional-branch/return-if/indexed-container/list-for-in/scoped-completion evidence.

## Closed/Do-Not-Repeat Families

- Do not re-open Mach-O resolver variants based on generic Oren maps, global sorting,
  future-name rewrites, fixup-side sid lists, or nested bucket structures unless a new
  profile proves they beat the retained first-byte bucket resolver.
- Do not route task-group runtime policy validation through `std:task` helpers until the
  bytecode latency issue is removed.
- Do not treat runtime-native single-occurrence private helpers as dead code without
  stage2 plus fixture-build proof; runtime bundle/rooting can depend on non-textual
  reachability.
