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
| AVM-DESKTOP-SDK | P1 | W4 | done | Add platform-neutral desktop `LibAVM` SDK gates. Current slices build `build/libavm/desktop/LibAVM.xcframework` from the C embedder API for macOS arm64/x86_64, run host C and Swift embedder smokes, build Linux x64 `libavm.a` with header/module-map/pkg-config export, and build Windows x64 `libavm.a` with header/module-map export. Linux/Windows x64 gates use Zig for cross-build, symbol checks, and C link smokes; runtime smokes run when QEMU/Wine are available or required. | `make verify-libavm-desktop && make verify-libavm-linux-x64 && make verify-libavm-windows-x64` |
| AVM-IOS-GFX-METAL | P1 | W5 | doing | Add game-grade Metal/`MTKView` GUI path. Current slice adds an SDK `OrenAVMMetalView` draw-loop/input/screen-state adapter for the current `OGF0` drawing subset (`fill_rect`, `push_clip_rect`, `pop_clip`, `push_translate`, `pop_transform`, `push_opacity`, `pop_opacity`, `push_camera_ortho`, `pop_camera`, `stroke_line`, `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`, `mesh2d`, `draw_mesh2d`, `destroy_mesh2d`, `mesh3d`, `mesh3d_rgba`, `mesh3d_indexed`, `material3d`, `model3d`, `draw_mesh3d`, `draw_mesh3d_at`, `draw_mesh3d_material`, `draw_mesh3d_at_material`, `draw_model3d`, `destroy_mesh3d`, `destroy_material3d`, `destroy_model3d`, `text`/`text_bytes`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`, `image_rgba`, `draw_image`, `destroy_image`, `draw_image_rect`, `draw_image_rects`) with cached text textures, coalesced virtual `frame_tick` and motion events, SDK-visible frame metrics, stable multi-pointer touch forwarding, compact gamepad/controller, focus, and IME/composition `OGE0` events, byte-native and retained text payloads for OBC hot paths, configurable measured CPU frame-budget gates, retained image/sprite/upload/draw/destroy/sub-rect/batched-atlas records, retained 2D mesh resource records, retained 3D mesh resource records with orthographic XY default projection, byte-native per-triangle RGBA payloads, indexed shared-vertex 3D meshes, retained material resources, retained model resources, pure OBC-side `std:ui/scene3d` retained-scene command builders plus JSON and byte-native `.os3d` package-asset loading with scene-level camera depth windows, named JSON mesh/material/model references, model templates, instances, grouped instances with parent transform composition, per-draw model/material/transform override objects, human-readable `position_xyz` or nested `transform` records, human-readable `vertices_xyz`/`faces`/`quads` indexed meshes, `triangles_xyz`/`quads_xyz` direct meshes, human-readable per-triangle `triangles_xyz_rgba` colors, richer material fields lowered to v0 RGBA colors, and sampled transform keyframes lowered to existing numeric byte-native assets/model records, deterministic painter-depth ordering, material override draws, per-draw and retained model translation/uniform scale via `draw_mesh3d_at`, and explicit orthographic camera depth windows via `push_camera_ortho`, Oren-side image upload budgets, SDK retained image count/pixel budgets, release-manifest whole-frame 2D and dedicated 3D raster conformance hashes, iOS SDK package-store conformance for mounted `.os3d` scene assets, drawable-independent Metal frame preparation metrics for retained 3D/resource frames, and `stroke_rect`/`round_rect`/`ellipse`/`polyline`/batched-triangle/clip-stack/translation-stack/opacity-stack coverage across raster/CoreGraphics/Metal; remaining work is live-device 3D performance capture plus broader package scene formats. | `make verify-libavm-ios && make test-avm` |
| AVM-IOS-STORE-DEMOS | P1 | W4 | done | Create curated demo OBC programs/packages for the `store.hubstack.cn` OBC store site so iOS host apps can download and run useful examples after GUI/network gates. Current demos build deterministic science/linalg, UI/GFX, and Scene3D package directories plus `.obc.zip` release bundles under `build/obc-store-demos`, with official source bundled as hashed assets and store-only deterministic 640x360 PNG screenshots published as release presentation metadata outside package manifests, client assets, and bundles. | `make verify-obc-store-demos && make verify-obc-store-service` |
| OBC-STORE-SERVICE | P1 | W4 | doing | Complete the `store.hubstack.cn` Go registry/API service. Current slice has publisher/package/release publish, signed public index with active key-id headers, rotation-capable public trust-bundle serving, host-facing package update checks, browser browse/detail/publisher/operator pages with release capabilities/source/permission/update metadata, store-only screenshot previews, server-rendered Oren source pages with syntax highlighting plus AST outline, authenticated `/ops/status` plus `/api/v0/ops/status` deployment summaries, authenticated `/ops/releases` plus `/api/v0/ops/releases` release lifecycle inventories with no-JS publish/yank/package-visibility forms, authenticated `/ops/updates` plus `/api/v0/ops/updates` latest/superseded update inventories, authenticated `/ops/audit` plus `/api/v0/ops/audit` append-only mutation audit logs, `/healthz` plus `/api/v0/health` for deployment probes, public-by-default package visibility with publisher/admin private toggle, `.obc.zip` bundle upload/download/index metadata, SDK bundle-preferred install with expanded-artifact fallback, search/download, yanking, iOS SDK install/run smoke with persisted last-known update status, deploy-safe admin bearer auth, publisher-scoped bearer auth, token rotation/revocation APIs, systemd deployment on the cloud host, checked Dockerized Traefik dynamic route config plus live route smoke for `https://store.hubstack.cn/`, local data-dir backup/restore smoke for metadata plus artifacts, and live `oren-labs` demo releases for science, UI, and Scene3D; remaining work is live deployment/operator polish. | `make verify-obc-store-service && make verify-obc-store-backup-restore && make verify-obc-store-deploy-script && make verify-obc-store-live-route && make verify-libavm-ios` |
| AVM-IOS-PERM-UX | P1 | W4 | done | Package permission prompt UX handoff for host apps. SDK has persisted grants, runtime NET grant/revocation application, decoded OBC permission requests, host-facing `OrenAVMPermissionPrompt` metadata for native UI, prompt-based decision recording, explicit package `permission_defaults` application, and Note now presents live source/OBC prompts with explicit Allow/Deny decisions persisted through `OrenAVMPermissionGrantStore` and applied before future live runs. | SDK verifier plus Note handoff verifier |
| AVM-RELEASE-MANIFEST | P1 | W4 | done | Add a manifest-driven AVM release runner covering fixture path, expected exit/error, budgets, backend policy, deterministic mode, host-effect expectations, setup builds, and release-gate inclusion. `make test-avm` now runs through `tests/avm/release_manifest.json` while preserving `AVM_TESTS` overrides, and release-gates nested multiverse AVM/VNET/VPROC/VFS plus VFS inheritance fixtures. | `make verify-avm-release-manifest && make test-avm` |
| AVM-STDLIB-COMPLETE | P1 | W4 | done | Replaced the representative stdlib smoke with manifest-driven coverage for every module imported by `lib/std/stdlib_avm.oren`; the gate now fails on bundle/manifest drift, host-only exclusion leaks, and missing app-facing OBC exports such as `STD_linalg_dot_f64`. | `make verify-avm-stdlib-obc-surface` |
| AVM-BYTES-HOTPATH | P1 | W3 | doing | Remove legacy list-of-byte/string conversions from hot AVM app-facing APIs; keep bytes as the performance path and text conversion only at explicit boundaries. Current slices add `std:ui/avm` `text_bytes`, direct text/composition event payload string slicing, and exact-size `u8_buf` OGF0 frame encoding, `std:ui/scene3d` coordinate/face/color asset packing through exact-size `u8_buf` builders, `std:net/avm/http.get(...).bytes()` over AVM NET op 8 for byte-native HTTP/VNET responses, direct `std:bytes.to_string` byte-slice conversion, AVM `oren_bytes_len`/`get_u8`/`pack` parity for byte-list and optimized int-list carriers, `std:buffer` u8 view/matrix byte copies through `u8_buf` instead of unpacked lists, `std:buffer` zero-copy Slice/Strided/Matrix wrapper methods for chainable view operations, canonical `std:buffer` facade plus raw/view/core/numeric/u8-matrix helper names, checked canonical matrix projection/view helpers, SHA-1/SHA-256 virtual padding over indexed byte access plus direct fixed-size digest `u8_buf` output, native RNG bytes filled directly into result buffers, HPACK Huffman encode/decode and full header-block encoding through exact-size `u8_buf` payloads, PEM/base64 body handling without intermediate Oren byte lists, and canonical codec/parser/RNG/protocol/UI/crypto/string/list/linalg/iter/checked-cast fallible verbs or `{ok,...}` records instead of public `try_*` API names. | `make test-avm && make verify-libavm-ios` |
| NATIVE-NUMERIC-GENERICS | P1 | W3 | done | Native generic-helper numeric cast semantics now use backend-neutral direct-call numeric parameter trait inference. Monomorphic direct-call float/int evidence specializes helper parameters for native lowering, while mixed or unknown generic evidence does not guess from untagged runtime carriers. | native/AVM cast fixtures plus `make test` |
| AVM-EVENT-FS-PACKAGE | P2 | W3 | done | Added host-enqueued FS/package virtual events to the AVM `EVENT` bus. OBC watches them with `std:avm/events.watch_fs` / `watch_package`, and iOS SDK hosts enqueue them with `putVirtualEventWithKind:action:detail:flags:` without exposing file descriptors or package-store internals. | `make test-avm && make verify-libavm-ios` |
| AVM-COMPILERKIT-IOS | P2 | W3 | done | Added `OrenAVMCompilerKit`: host apps provide bundled `oren.obc` and `stdlib_bundle.obc`, then compile source through AVM VirtualFS/argv and receive output OBC plus compiler diagnostics without recreating the harness manually. | `make verify-compiler-in-avm-ios-chain && make verify-libavm-ios` |
| MATH-STDLIB-EXPAND | P2 | W3 | todo | Continue deterministic `std:math` expansion toward C/C++ mathlib breadth with native and AVM fixtures per function family. Current release-gated families include core predicates/rounding/fmod/sign helpers, pow/power, exp/log/log2/log10/exp2/exp10, finite trig/atan vectors, and a meaningful large-input Payne-Hanek trig vector at 2^40; 2^53 periodicity is intentionally not asserted because `x + tau` rounds to `x + 6`, not `x + 2pi`. | focused math fixtures plus `make test-avm` |
| OREN-LSP-VSCODE | P2 | W3 | todo | Build a Go Oren language server plus VS Code extension for syntax highlighting, diagnostics, completion, navigation, and code intelligence after the current AVM/OBC store jobs land. | Go LSP tests plus VS Code extension smoke |
| LANG-ANON-IMPORT | P3 | W2 | todo | Add anonymous import syntax such as `import . "std:math"` after defining collision, visibility, import-cache, and fixture behavior. | parser/import/backend fixtures |

## Current Done Evidence

- iOS `OrenAVMKit` builds as an xcframework and verifies TIME, FS, VNET, VPROC,
  GFX/input, package store, trust bundle, permission grant persistence, and
  compiler-in-AVM smoke paths through `make verify-libavm-ios`.
- The main iOS verifier keeps reusable OBC smoke sources under
  `tests/fixtures/ios_avm/` instead of embedding large heredocs, preserving
  line-guardrail headroom for more GUI/Metal gates.
- `OrenAVMRuntimeConfig` and `OrenAVMRunResult` live in
  `OrenAVMRuntimeTypes.m`, keeping the core runtime implementation below the
  2000-line source guardrail as more iOS AVM providers are added.
- `OrenAVMGraphicsView` now lives in its own UIKit/CoreGraphics implementation
  file, keeping the runtime file focused on AVM execution/host bridges and
  restoring guardrail headroom for future GUI provider work.
- Fixed-arity direct calls now materialize omitted trailing arguments as real
  `nil` across C, native, and AVM backends; `tests/modules/test_omitted_args_nil.oren`
  is part of the native quick integration gate.
- `std:bytes`, `std:buffer`, `std:strings`, `std:list`, `std:linalg`,
  `std:iter`, `std:crypto`, `std:ui`, and checked
  `std:ints` / `std:casts` helpers now expose canonical
  fallible public verbs: `bytes.pack`, `bytes.get_u32_le`,
  `bytes.put_u32_le`, `buffer.load_i32`, `buffer.store_i32`,
  `buffer.mat_row_to_bytes`, `buffer.mat_col_strided`, `strings.slice`,
  `strings.trim`, `list.get`, `list.slice_copy`, `linalg.dot_f64_buf`,
  `linalg.matmul_f32_buf`, `iter.range`, `sha256.hex`, `ui_cmds.validate`,
  `ui_raster.rasterize`, `ppm.write_rgba_ppm`, `ints.checked_u8`,
  `casts.checked_u64`, and chainable `buf.slice(1, 3).text()` /
  `buf.matrix(2, 3).row(1).text()`.
  `std:buffer/raw`, `std:buffer/view`, `std:buffer/mat_core`,
  `std:buffer/mat_numeric`, and `std:buffer/mat_u8` also use canonical names
  at the importable helper boundary.
  `lib/std` no longer exposes or uses `try_*` helper names; checked fallible
  implementation helpers use private `_checked_*` names.
- `make verify-stdlib-api-shape` is part of the fast `make test` path and blocks
  known bad root-helper regressions. Public fallible stdlib APIs should use normal
  verbs returning `value | oren_err` or explicit `{ok,...}` records; numeric errno
  contracts belong under explicit `*_raw` primitives.
- `stdlib_bundle.obc` includes the current app-facing AVM stdlib surface:
  buffers, bytes, JSON/CBOR/YAML/regex, crypto helpers, linalg, math, time,
  `std:net/avm` DNS/TCP/UDP/WebSocket facades, `std:ui/avm`,
  `std:avm/events`, and `std:avm/permission`.
