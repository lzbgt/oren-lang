# Oren Active Task Tracker

Rolling tracker for concrete work. Historical status lives in `docs/STATUS.md`;
design evidence lives under `project-doc/`.

## Format

- `ID`: stable short identifier.
- `Priority`: `P0` highest, then `P1`, `P2`, `P3`.
- `Weight`: `W5` highest leverage, then `W4`, `W3`, `W2`, `W1`.
- `Status`: `todo`, `doing`, `blocked`, or `done`.
- `Gate`: verification command that must pass before marking done.

## Active

| ID | Priority | Weight | Status | Task | Gate |
| --- | --- | --- | --- | --- | --- |
| AVM-IOS-VNET-ACCEPT | P1 | W4 | done | Finish host-backed VNET listen/accept for OBC server flows without exposing raw sockets. | `make verify-libavm-ios` |
| AVM-IOS-GFX-METAL | P1 | W5 | doing | Add game-grade Metal/`MTKView` GUI path. Current slice adds an SDK `OrenAVMMetalView` draw-loop/input/screen-state adapter for the current `OGF0` drawing subset (`fill_rect`, `push_clip_rect`, `pop_clip`, `push_translate`, `pop_transform`, `push_opacity`, `pop_opacity`, `stroke_line`, `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`, `text`/`text_bytes`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`, `image_rgba`, `draw_image`, `destroy_image`, `draw_image_rect`, `draw_image_rects`) with cached text textures, coalesced virtual `frame_tick` and motion events, SDK-visible frame metrics, stable multi-pointer touch forwarding, compact gamepad/controller, focus, and IME/composition `OGE0` events, byte-native and retained text payloads for OBC hot paths, configurable measured CPU frame-budget gates, retained image/sprite upload/draw/destroy/sub-rect/batched-atlas records, Oren-side image upload budgets, SDK retained image count/pixel budgets, release-manifest whole-frame 2D raster conformance hash, and `stroke_rect`/`round_rect`/`ellipse`/`polyline`/batched-triangle/clip-stack/translation-stack/opacity-stack coverage across raster/CoreGraphics/Metal; remaining work is richer drawing records and Metal/3D conformance gates. | `make verify-libavm-ios && make test-avm` |
| AVM-IOS-STORE-DEMOS | P1 | W4 | done | Create curated demo OBC programs/packages for the `store.hubstack.cn` OBC store site so iOS host apps can download and run useful examples after GUI/network gates. Current demos build deterministic science/linalg and UI/GFX package directories plus `.obc.zip` release bundles under `build/obc-store-demos`, with official source bundled as hashed assets. | `make verify-obc-store-demos` |
| OBC-STORE-SERVICE | P1 | W4 | doing | Complete the `store.hubstack.cn` Go registry/API service. Current slice has publisher/package/release publish, signed public index, browser browse/detail/operator pages, `/healthz` plus `/api/v0/health` for deployment probes, public-by-default package visibility with publisher/admin private toggle, `.obc.zip` bundle upload/download/index metadata, SDK bundle-preferred install with expanded-artifact fallback, search/download, yanking, iOS SDK install/run smoke, deploy-safe admin bearer auth, publisher-scoped bearer auth, token rotation/revocation APIs, and an opt-in systemd deploy path with remote health smoke; remaining work is live deployment after SSH auth plus richer operator/browser UX. | `make verify-obc-store-service && make verify-obc-store-deploy-script && make verify-libavm-ios` |
| AVM-IOS-PERM-UX | P1 | W4 | doing | Package permission prompt UX handoff for host apps. Current SDK has persisted grants, runtime NET grant/revocation application, decoded OBC permission requests, and explicit package `permission_defaults` application; remaining work is richer prompt UI handoff and Note-side integration. | SDK verifier plus Note handoff verifier |
| AVM-RELEASE-MANIFEST | P1 | W4 | done | Add a manifest-driven AVM release runner covering fixture path, expected exit/error, budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion. `make test-avm` now runs through `tests/avm/release_manifest.json` while preserving `AVM_TESTS` overrides. | `make verify-avm-release-manifest && make test-avm` |
| AVM-STDLIB-COMPLETE | P1 | W4 | done | Replaced the representative stdlib smoke with manifest-driven coverage for every module imported by `lib/std/stdlib_avm.oren`; the gate now fails on bundle/manifest drift, host-only exclusion leaks, and missing app-facing OBC exports such as `STD_linalg_dot_f64`. | `make verify-avm-stdlib-obc-surface` |
| AVM-BYTES-HOTPATH | P1 | W3 | doing | Remove legacy list-of-byte/string conversions from hot AVM app-facing APIs; keep bytes as the performance path and text conversion only at explicit boundaries. Current slices add `std:ui/avm` `text_bytes` for frame text payloads, `std:net/avm.try_get_bytes` over AVM NET op 8 for byte-native HTTP/VNET responses, and direct `std:bytes.to_string` byte-slice conversion instead of legacy list materialization. | `make test-avm && make verify-libavm-ios` |
| AVM-EVENT-FS-PACKAGE | P2 | W3 | done | Added host-enqueued FS/package virtual events to the AVM `EVENT` bus. OBC watches them with `std:avm/events.watch_fs` / `watch_package`, and iOS SDK hosts enqueue them with `putVirtualEventWithKind:action:detail:flags:` without exposing file descriptors or package-store internals. | `make test-avm && make verify-libavm-ios` |
| AVM-COMPILERKIT-IOS | P2 | W3 | done | Added `OrenAVMCompilerKit`: host apps provide bundled `oren.obc` and `stdlib_bundle.obc`, then compile source through AVM VirtualFS/argv and receive output OBC plus compiler diagnostics without recreating the harness manually. | `make verify-compiler-in-avm-ios-chain && make verify-libavm-ios` |
| MATH-STDLIB-EXPAND | P2 | W3 | todo | Continue deterministic `std:math` expansion toward C/C++ mathlib breadth with native and AVM fixtures per function family. | focused math fixtures plus `make test-avm` |
| OREN-LSP-VSCODE | P2 | W3 | todo | Build a Go Oren language server plus VS Code extension for syntax highlighting, diagnostics, completion, navigation, and code intelligence after the current AVM/OBC store jobs land. | Go LSP tests plus VS Code extension smoke |
| LANG-ANON-IMPORT | P3 | W2 | todo | Add anonymous import syntax such as `import . "std:math"` after defining collision, visibility, import-cache, and fixture behavior. | parser/import/backend fixtures |

## Current Done Evidence

- iOS `OrenAVMKit` builds as an xcframework and verifies TIME, FS, VNET, VPROC,
  GFX/input, package store, trust bundle, permission grant persistence, and
  compiler-in-AVM smoke paths through `make verify-libavm-ios`.
- The main iOS verifier keeps reusable OBC smoke sources under
  `tests/fixtures/ios_avm/` instead of embedding large heredocs, preserving
  line-guardrail headroom for more GUI/Metal gates.
- `stdlib_bundle.obc` includes the current app-facing AVM stdlib surface:
  buffers, bytes, JSON/CBOR/YAML/regex, crypto helpers, linalg, math, time,
  `std:net/avm` DNS/TCP/UDP/WebSocket facades, `std:ui/avm`,
  `std:avm/events`, and `std:avm/permission`.
