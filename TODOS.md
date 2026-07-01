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
| AVM-DESKTOP-SDK | P1 | W4 | done | Add platform-neutral desktop `LibAVM` SDK gates. Current slices build `build/libavm/desktop/LibAVM.xcframework` from the C embedder API for macOS arm64/x86_64, run host C, Swift, and one-shot `avm_runner` smokes, build Linux x64 `libavm.a` with header/module-map/pkg-config export, and build Windows x64 `libavm.a` with header/module-map export. Linux/Windows x64 gates use Zig for cross-build, symbol checks, and C link smokes through the same one-shot runner API; runtime smokes run when QEMU/Wine are available or required. | `make verify-libavm-desktop && make verify-libavm-linux-x64 && make verify-libavm-windows-x64` |
| AVM-IOS-GFX-METAL | P1 | W5 | doing | Add game-grade Metal/`MTKView` GUI path. Current slice adds an SDK `OrenAVMMetalView` draw-loop/input/screen-state adapter for the current `OGF0` drawing subset (`fill_rect`, `push_clip_rect`, `pop_clip`, `push_translate`, `pop_transform`, `push_opacity`, `pop_opacity`, `push_camera_ortho`, `pop_camera`, `stroke_line`, `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`, `mesh2d`, `draw_mesh2d`, `destroy_mesh2d`, `mesh3d`, `mesh3d_rgba`, `mesh3d_indexed`, `material3d`, `model3d`, `draw_mesh3d`, `draw_mesh3d_at`, `draw_mesh3d_material`, `draw_mesh3d_at_material`, `draw_model3d`, `destroy_mesh3d`, `destroy_material3d`, `destroy_model3d`, `text`/`text_bytes`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`, `image_rgba`, `draw_image`, `destroy_image`, `draw_image_rect`, `draw_image_rects`) with cached text textures, bounded text atlas packing plus same-atlas text-run coalescing, event-driven multicast frame wakeups, mutex-protected latest-frame mailbox reads, coalesced renderer main-queue reloads, coalesced virtual `frame_tick` and motion events, SDK-visible frame metrics, stable multi-pointer touch forwarding, compact gamepad/controller, focus, and IME/composition `OGE0` events, byte-native and retained text payloads for OBC hot paths, configurable measured CPU frame-budget gates, retained image/sprite/upload/draw/destroy/sub-rect/batched-atlas records, retained 2D mesh resource records, retained 3D mesh resource records with orthographic XY default projection, byte-native per-triangle RGBA payloads, indexed shared-vertex 3D meshes, retained material resources, retained model resources, pure OBC-side `std:ui/scene3d` retained-scene command builders plus JSON and byte-native `.os3d` package-asset loading with scene-level camera depth windows, named JSON mesh/material/model references, model templates, instances, grouped instances with parent transform composition, per-draw model/material/transform override objects, human-readable `position_xyz` or nested `transform` records, human-readable `vertices_xyz`/`faces`/`quads` indexed meshes, builder-side glTF 2.0 JSON/GLB `gltf_source` plus inline JSON `gltf_json` with URI or BIN buffers, indices, sparse accessors, static `POSITION`/`COLOR_0` morph target weights, baked skinning through `JOINTS_n`/`WEIGHTS_n` and inverse bind matrices, sampled `gltf_animation`/`gltf_sample_time_milli` node translation/rotation/scale/morph-weight animations, material base colors multiplied by `COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix hierarchy selection, Wavefront OBJ `obj_source`/`obj_text`, binary-or-ASCII STL `stl_source`, inline ASCII STL `stl_text`, binary-or-ASCII PLY `ply_source`, and inline ASCII PLY `ply_text` mesh lowering, PLY face or averaged vertex colors into `mesh3d_rgba`, core 3MF `3mf_source` ZIP mesh/build plus basematerial `displaycolor` lowering and optional `3mf_triangle_set` subgroup selection, `triangles_xyz`/`quads_xyz` direct meshes, compact `boxes_xyz` cuboids, `prisms_xy` extruded polygons, bounded `heightfields_xy` terrain grids, bounded `surfaces_xyz` arbitrary surface grids, rectangular `planes_xy`, filled `rounded_rects_xy`, flat `polygons_xy`, regular `regular_polygons_xy`, `stars_xy`, circular `discs_xy`/`rings_xy`, elliptical `ellipses_xy`/`ellipse_rings_xy`, thick `segments_xy`/`paths_xy` and sampled `beziers_xy`, partial `sectors_xy`/`arc_bands_xy`, sloped `ramps_xy`, solid `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, bounded `cylinders_z`/`cones_z`/`spheres_xyz`/`ellipsoids_xyz`/`toruses_xyz`/`capsules_z`, human-readable per-triangle `triangles_xyz_rgba` colors, richer material fields lowered to v0 RGBA colors, and sampled transform keyframes lowered to existing numeric byte-native assets/model records, deterministic painter-depth ordering, material override draws, per-draw and retained model translation/uniform scale via `draw_mesh3d_at`, and explicit orthographic camera depth windows via `push_camera_ortho`, Oren-side image upload budgets, SDK retained image count/pixel budgets, release-manifest whole-frame 2D and dedicated 3D raster conformance hashes, iOS SDK package-store conformance for mounted `.os3d` scene assets, drawable-independent Metal frame preparation metrics for retained 3D/resource frames, generated live-device 3D capture app build/signing preflight and on-phone physically rotated cube mesh proof via `make capture-ios-live-3d-performance`, phone-copied PNG snapshot capture, packed Metal shader vertex structs matching CPU upload strides, static SDK category linkage through `-ObjC`, Xcode-managed development-profile discovery, and `stroke_rect`/`round_rect`/`ellipse`/`polyline`/batched-triangle/clip-stack/translation-stack/opacity-stack coverage across raster/CoreGraphics/Metal; remaining work is broader package scene formats. | `make verify-libavm-ios && make test-avm` |
| AVM-IOS-STORE-DEMOS | P1 | W4 | done | Create curated demo OBC programs/packages for the `store.hubstack.cn` OBC store site so iOS host apps can download and run useful examples after GUI/network gates. Current demos build deterministic science/linalg, UI/GFX, and Scene3D package directories plus `.obc.zip` release bundles under `build/obc-store-demos`, with official source bundled as hashed assets and store-only deterministic 640x360 PNG screenshots published as release presentation metadata outside package manifests, client assets, and bundles. | `make verify-obc-store-demos && make verify-obc-store-service` |
| OBC-STORE-SERVICE | P1 | W4 | doing | Complete the `store.hubstack.cn` Go registry/API service. Current slice has publisher/package/release publish, signed public index with active key-id headers, rotation-capable public trust-bundle serving, host-facing package update checks, browser browse/detail/publisher/operator pages with release capabilities/source/permission/update metadata, store-only screenshot previews, server-rendered Oren source pages with syntax highlighting plus AST outline, authenticated `/ops/status` plus `/api/v0/ops/status` deployment summaries with build commit/time, aggregate release-ready/incomplete and missing-readiness counts plus data-dir writable/storage byte totals by metadata/payload/program/bundle/asset/screenshot/audit class, authenticated filterable `/ops/releases` plus `/api/v0/ops/releases` release lifecycle inventories by status/visibility/readiness with no-JS publish/yank/package-visibility forms, authenticated filterable `/ops/updates` plus `/api/v0/ops/updates` latest/superseded update inventories by publisher/package/visibility/superseded state with total/filtered counts, authenticated filterable `/ops/audit` plus `/api/v0/ops/audit` append-only mutation audit logs by action/actor/target with total/filtered counts, `/healthz` plus `/api/v0/health` for build-stamped deployment probes, public-by-default package visibility with publisher/admin private toggle, `.obc.zip` bundle upload/download/index metadata, SDK bundle-preferred install with expanded-artifact fallback, search/download, yanking, iOS SDK install/run smoke with persisted last-known update status, deploy-safe admin bearer auth, publisher-scoped bearer auth, token rotation/revocation APIs, systemd deployment on the cloud host, checked Dockerized Traefik dynamic route config plus deploy-time and live-route authenticated operator-status storage/readiness probes, admin-env host fallback plus explicit `sshpass -e` password mode for deployment, local data-dir backup/restore smoke for metadata plus artifacts, and live `oren-labs` demo releases for science, UI, and Scene3D; remaining work is live deployment/operator polish, currently blocked on corrected SSH credentials for replacing the live service. | `make verify-obc-store-service && make verify-obc-store-backup-restore && make verify-obc-store-deploy-script && make verify-obc-store-live-route && make verify-libavm-ios` |
| AVM-IOS-PERM-UX | P1 | W4 | done | Package permission prompt UX handoff for host apps. SDK has persisted grants, runtime NET grant/revocation application, decoded OBC permission requests, host-facing `OrenAVMPermissionPrompt` metadata for native UI, prompt-based decision recording, explicit package `permission_defaults` application, and Note now presents live source/OBC prompts with explicit Allow/Deny decisions persisted through `OrenAVMPermissionGrantStore` and applied before future live runs. | SDK verifier plus Note handoff verifier |
| AVM-RELEASE-MANIFEST | P1 | W4 | done | Add a manifest-driven AVM release runner covering fixture path, expected exit/error, budgets, backend policy, deterministic mode, host-effect expectations, setup builds, multi-phase record/replay and snapshot/resume runs, line-prefix captures, cross-phase assertions, and release-gate inclusion. `make test-avm` now runs through `tests/avm/release_manifest.json` while preserving `AVM_TESTS` overrides, every current `tests/avm/test_*.oren` fixture is present in the manifest, and bytecode/setup builds receive an explicit platform so parallel verification does not depend on host autodetect. | `make verify-avm-release-manifest && make test-avm` |
| AVM-STDLIB-COMPLETE | P1 | W4 | done | Replaced the representative stdlib smoke with manifest-driven coverage for every module imported by `lib/std/stdlib_avm.oren`; the gate now fails on bundle/manifest drift, host-only exclusion leaks, and missing app-facing OBC exports such as `STD_linalg_dot_f64`. | `make verify-avm-stdlib-obc-surface` |
| AVM-BYTES-HOTPATH | P1 | W3 | doing | Remove legacy list-of-byte/string conversions from hot AVM app-facing APIs; keep bytes as the performance path and text conversion only at explicit boundaries. Current slices add `std:ui/avm` `text_bytes`, direct text/composition event payload string slicing, and exact-size directly-returned `u8_buf` OGF0 frame encoding with direct string-byte writes for plain `text` commands, `std:ui/color` hex parsing over direct ASCII byte reads, `std:ui/scene3d` coordinate/face/color package asset packing through exact-size directly-returned `u8_buf` builders plus color hex emission through string slices, `std:net/avm/http.get(...).bytes()` over AVM NET op 8 for byte-native HTTP/VNET responses, native `std:net/http` response `.bytes()` over cached typed body bytes for content-length and chunked responses, direct `std:bytes.to_string` byte-slice conversion, `std:bytes.from_string`/`from_hex`, kernel `oren_bytes_from_string` byte-native u8-buffer output, direct `to_hex` exact-size lowercase hex emission plus C/native runtime hex/string/slice/unpack/pack/endian-read/write helpers reading or writing list/u8-buffer backing storage directly after one validation pass, and `std:strings` byte roundtrips over byte-native u8 buffers, `std:bytes` direct u8-buffer reads for get/unpack/concat/copy sources, exact-size u8-buffer `pack`, u8/endian writes, concat/copy u8-buffer spans, overlap-safe u8 `copy_into`, `std:buffer` view/matrix `copy_from_bytes` direct byte-carrier reads with contiguous slice/dense-matrix u8 destinations routed through `bytes.copy_into`, contiguous slice/dense-matrix byte/text exports routed through direct byte-slice conversion, raw u8 buffer loads/stores plus u8 slice/strided/matrix view loads/stores through direct pointer access after public validation, and `copy_into` u8-buffer destinations through raw pointer stores after public span checks, JSON full decode, scalar parse, tag equality, and escape output over direct source-string byte reads or exact-size `u8_buf` buffers, CBOR canonical key ordering/text encoding plus u8-backed decode byte carriers, and full regex pattern/text matching over direct string byte reads, YAML comment stripping, quoted-scalar parse/escape, line/trim/key split, key sort, bare-identifier, prefix, and suffix helpers without list-of-byte reconstruction, XML/HTML parser literal matching, class-selector scans, DOM parsing, and streaming readers over direct source-string byte reads without repeated input byte-list materialization, WebSocket accept hashing through direct SHA-1 UTF-8 string hashing, Base64/Base64URL decode/encode exact-size output writes through direct u8-buffer stores, PPM header/body output and software raster clear/pixel writes through raw exact-size buffer stores, native `oren_write_file` direct string syswrites, compiler source-policy scans, cache line/number parsing, scan-cache delimiter writes, C-runtime include scanning, manifest JSON escaping, bytecode metadata payload writing, bytecode final artifact return as `u8_buf`, compiler SHA digest hex routing through direct runtime bytes hex, OBC linker byte reads from `u8_buf`, parsed OBC code and byte constants kept as `u8_buf`, builder-patched linked code, linked OBC final emission as `u8_buf`, plus malformed-OBC/OBX span guards, bytecode string constants, OBX string/prefix encoding, AST binary v1 full-value raw writes, native Mach-O/ELF object string payloads, runtime-object debug-name blobs, x64 native debug-table names, ARM64 native panic-message payloads, shared compiler byte-builder append/list/string/set stores, lexer string-literal decoding through compact byte builders, and C identifier escaping over direct string byte reads plus raw exact-size output writes, AVM `oren_bytes_len`/`get_u8`/`pack` parity for byte-list and optimized int-list carriers, `std:buffer` u8 view/matrix byte copies through `u8_buf` instead of unpacked lists, direct string-byte copy into raw u8 buffers, slice/strided views, whole u8 matrices, and u8 slice/strided/matrix stores through raw pointer writes after u8-carrier checks, `std:buffer` zero-copy Slice/Strided/Matrix wrapper methods for chainable view operations, canonical `std:buffer` facade plus raw/view/core/numeric/u8-matrix helper names, checked canonical matrix projection/view helpers, SHA-1/SHA-256 virtual padding over indexed byte access plus direct fixed-size digest `u8_buf` output through unchecked final stores, SHA-1/SHA-256 direct string hashing for UTF-8 string inputs, SHA hex helpers plus Windows Schannel certificate hash formatting through direct std bytes hex emission, Windows Schannel passphrase cache keys, native RNG bytes filled directly into result buffers, native IPv6 sockaddr address bytes copied directly from `u8_buf` or list backing storage, HPACK Huffman encode/decode, decoded-string boundaries, and full header-block encoding through exact-size `u8_buf` payloads or byte-slice conversion, TLS ALPN decoded-byte strings through byte-slice conversion, PEM/base64 body handling without intermediate Oren byte lists plus strict PEM body raw exact-size writes, and canonical codec/parser/RNG/protocol/UI/crypto/string/list/linalg/iter/checked-cast fallible verbs or `{ok,...}` records instead of public `try_*` API names. | `make test-avm && make verify-libavm-ios` |
| NATIVE-NUMERIC-GENERICS | P1 | W3 | done | Native generic-helper numeric cast semantics now use backend-neutral direct-call numeric parameter trait inference. Monomorphic direct-call float/int evidence specializes helper parameters for native lowering, while mixed or unknown generic evidence does not guess from untagged runtime carriers. | native/AVM cast fixtures plus `make test` |
| AVM-EVENT-FS-PACKAGE | P2 | W3 | done | Added host-enqueued FS/package virtual events to the AVM `EVENT` bus. OBC watches them with `std:avm/events.watch_fs` / `watch_package`, and iOS SDK hosts enqueue them with `putVirtualEventWithKind:action:detail:flags:` without exposing file descriptors or package-store internals. | `make test-avm && make verify-libavm-ios` |
| AVM-COMPILERKIT-IOS | P2 | W3 | done | Added `OrenAVMCompilerKit`: host apps provide bundled `oren.obc` and `stdlib_bundle.obc`, then compile source through AVM VirtualFS/argv and receive output OBC plus compiler diagnostics without recreating the harness manually. | `make verify-compiler-in-avm-ios-chain && make verify-libavm-ios` |
| MATH-STDLIB-EXPAND | P2 | W3 | todo | Continue deterministic `std:math` expansion toward C/C++ mathlib breadth with native and AVM fixtures per function family. Current release-gated families include core predicates/rounding/fmod/remainder/remquo/modf/sign helpers, integer rounding aliases `lround`/`llround`/`lrint`/`llrint`, sign-bit `copysign`, NaN-aware `fabs`/`fmin`/`fmax`, tolerance predicates `isclose`/`isclose_abs`, finite `lerp`, range mapping helpers `inverse_lerp`/`remap`/`remap_clamped`, graphics scalar/interpolation helpers `sign`/`step`/`fract`/`clamp`/`saturate`/`smoothstep`/`smootherstep`, angle wrapping/interpolation helpers `wrap`/`wrap_degrees`/`wrap_radians`/`angle_delta_degrees`/`angle_delta_radians`/`lerp_angle_degrees`/`lerp_angle_radians`, pure finite `std:math/vec2` length/distance/dot/cross/normalize/angle/rotate plus add/sub/scale/lerp/project/reject/reflect helpers, pure finite `std:math/vec3` length/distance/dot/cross/normalize/angle-between plus add/sub/scale/lerp/project/reject/reflect helpers, pure finite `std:math/vec4` length/distance/dot/normalize/angle-between plus add/sub/scale/lerp/project/reject/reflect helpers, pure finite `std:math/quat` identity/length/normalize/conjugate/dot/inverse/multiply/axis-angle/vector-rotation/nlerp/slerp helpers, pure finite row-major `std:math/mat4` identity/translation/scale/quaternion-rotation/TRS-composition/orthographic/frustum/perspective projection/look-at/model-view-projection composition/multiply/transpose/determinant/inverse/point/vector/normal/screen project/unproject transforms plus normal-matrix extraction, plus overflow-aware `midpoint`, public ties-to-even rounding aliases, degree/radian angle conversion, normal/subnormal/`fpclassify` classification, `ilogb`/`logb`, `fdim`, `nextafter`/`nexttoward`/`nextup`/`nextdown`, pow/power, frexp/ldexp/scalbn decomposition and scaling, cbrt, scaled two- and three-argument hypotenuse, exp/log/log2/log10/exp2/exp10 plus cancellation-aware expm1/log1p, hyperbolic sinh/cosh/tanh and inverse hyperbolic asinh/acosh/atanh, finite sin/cos/tan/sincos/atan/atan2/asin/acos vectors, approximate real-valued erf/erfc, and a meaningful large-input Payne-Hanek trig vector at 2^40 now included in native quick; 2^53 periodicity is intentionally not asserted because `x + tau` rounds to `x + 6`, not `x + 2pi`. | focused math fixtures plus `make test-avm` |
| OREN-LSP-VSCODE | P2 | W3 | doing | Build a Go Oren language server plus VS Code extension for syntax highlighting, diagnostics, completion, navigation, and code intelligence. Current slices add a dependency-free `oren-lsp` JSON-RPC stdio server with `initialize`/`shutdown`, full-document sync, deterministic bracket/string diagnostics plus parser-backed diagnostics on open/change, clean close handling, keyword/local-symbol completion, direct imported-module alias completion, typed struct/class field completion after proven receivers, lexer-backed document symbols for imports, functions, variables, structs, and classes, same-file, opened-document cross-file, and import-resolved unopened-module definition navigation for relative and `std:` modules, lexer-backed hover and references over the same current/open/imported workspace graph, bounded transitive import traversal with cycle guards, scoped function-parameter definition/hover/reference navigation with nested shadowing, constructor-inferred same-file and direct-import-alias struct/class field definition/hover/reference navigation with direct variable-alias propagation, direct named factory-return inference including `return if/else` expression branches plus factory-return field-chain evidence, direct typed constructor/factory expression receiver field navigation/completion plus constructor-field and constructor-bound variable/alias field-chain inference/completion, homogeneous list/hash indexed receiver evidence for field navigation and direct literal completions, list `for-in` loop element receiver evidence for field navigation/references and call-site parameter propagation, source-brace scoped local/list-for-in receiver completions inside function blocks, consistent direct call-site parameter inference with conflict invalidation, direct parameter-return propagation, consistent conditional branch return and assignment inference, and unknown-assignment invalidation, conservative prepare/rename workspace edits for exact scoped parameters and same-document typed fields, full-document semantic-token classification for declarations/references/literals/operators plus parser-derived parameter and property classes, plus a VS Code extension package with `.oren` language contribution, TextMate syntax grammar, language configuration, `vscode-languageclient` activation, and smoke verification; remaining work is richer member inference beyond direct constructor/alias/factory-expression/factory-return-field-chain/constructed-field/constructor-bound-alias-field-chain/call-site/parameter-return/conditional-branch/return-if/indexed-container/list-for-in/scoped-completion evidence. | `make verify-oren-lsp` |
| LANG-ANON-IMPORT | P3 | W2 | todo | Add anonymous import syntax such as `import . "std:math"` after defining collision, visibility, import-cache, and fixture behavior. | parser/import/backend fixtures |

## Current Done Evidence

- Parallel module parsing now emits setup and per-module worker phase markers under
  `OREN_TRACE_BUILD_PHASES_PATH` for both thread and fork worker modes. Fresh x64
  self-host evidence shows the active macOS stage2 path is thread mode (`fork=0`),
  all sampled compiler modules were cold module-cache reads (`cache_hit=0`), and
  the largest completed parse costs were `lib/compiler/compiler.oren` (~15.8s),
  `parser_parse.oren` (~6.7s), and `codegen_bytecode.oren` (~6.1s); forced fork
  remains rejected because compiler-shaped ASTBIN worker encoding still stalls.
- Module discovery now emits bounded `link.discover_module.done` attribution
  markers for path resolution, import scanning, and dependency descent. Repo-owned
  `lib/compiler/**` and `lib/std/**` files use header-only import scanning after
  verifying all 1495 repo Oren files keep imports before code, and include
  aggregator detection now exits at the first real code line for ordinary
  children. Capped x64 self-host `link.discover.done` dropped from ~45.7s to
  ~26.8s after header scanning and then to ~0.675s after aggregator early exit.
- The Linux x64 syscall intrinsic dispatcher is split into smaller fs/proc/misc
  helper bodies. The capped x64 self-host parse profile for
  `x64_native_program.oren` moved from roughly 41.4s total / 30.4s parse to
  38.2s total / 27.8s parse, shifting the hot parse body from
  `_emit_intrinsic_sys_linux_x64` to `native_compile_program_x64`.
- `native_compile_program_x64` now delegates debug metadata and entry global-root
  table emission to helper bodies, keeping the entry orchestrator smaller. The
  capped self-host profile stayed essentially flat for total x64 module parse
  (~38.5s) and exposed `_emit_eval_int_to_rax` as the next large parser body.
- `_emit_eval_int_to_rax` now delegates prefix and infix expression lowering to
  helper bodies. Capped x64 self-host parse for `x64_native_program.oren` moved
  from ~38.5s total / ~27.9s parse to ~37.5s total / ~27.3s parse; the current
  exposed hot parser body is back in `native_compile_program_x64`.
- `native_compile_program_x64` now also delegates entry runtime bootstrap
  emission and the user-function compile loop to helper bodies. The valid
  reduced-arity helper shape keeps compiler-in-AVM verification compatible and
  leaves the final capped `x64_native_program.oren` profile at ~37.8s total /
  ~27.2s parse, with `native_compile_program_x64` narrowed to about 1.09s as the
  exposed hot parser body.
- X64 compile diagnostic/trace option parsing is now isolated in a small
  zero-argument helper plus local unpacking, avoiding another wide OBC call.
  The capped x64 self-host profile now shows `x64_native_program.oren` at
  ~38.0s total / ~27.4s parse, with the exposed hot parser body back at
  `_emit_eval_int_to_rax` (~1.06s).
- X64 call expression lowering now lives in a dedicated `_emit_eval_call_expr_to_rax`
  helper, while native program callable-use collection and lambda wrapper
  synthesis are split out of `native_compile_program_x64`. The capped profile
  now shows `x64_native_program.oren` at ~37.9s total / ~27.4s parse, with the
  exposed parser body shifted to `_emit_ops_in_fn` (~954ms).
- `_emit_ops_in_fn` now delegates while/for loop lowering and string-global
  batch fallback materialization to helper bodies, and `native_compile_program_x64`
  delegates wrapper/fnwrap compilation plus program-data finalization. The final
  capped x64 self-host profile moved the exposed x64 parser body back to
  `native_compile_program_x64` at ~880ms; wall/parse totals remain noisy, so the
  next concrete target is the remaining native program orchestration body.
- `native_compile_program_x64` now delegates entry register-thread emission,
  top/main entry calls, and platform return-path emission through small helper
  calls. The capped x64 self-host profile now exposes
  `_emit_intrinsic_sys_linux_fs_x64` at ~770ms as the next parser body, so the
  next concrete x64 compile-throughput task is splitting Linux FS syscall
  intrinsic lowering by syscall family.
- Linux x64 FS intrinsic lowering is now split into stat-family and path-family
  helpers. The capped x64 self-host profile shows `x64_native_program.oren` at
  ~37.4s total / ~27.4s parse, with `_emit_eval_call_expr_to_rax` exposed at
  ~659ms; the next concrete x64 parser target is call expression lowering.
- X64 call-expression runtime/generic fast-path classification is split out of
  `_emit_eval_call_expr_to_rax`. The capped x64 self-host profile now shows
  `x64_native_program.oren` at ~37.0s total / ~27.2s parse, with
  `_x64_collect_top_level_globals_and_stmts` exposed at ~606ms; the next
  concrete x64 parser target is top-level global collection/rewrite structure.
- X64 top-level global collection now delegates runtime slot reservation, user
  slot/fact preparation, and top-level initializer rewrite into helper bodies.
  The capped profile shows `x64_native_program.oren` at ~37.7s total / ~27.7s
  parse, with `_emit_ops_in_fn` exposed again at ~618ms as the next parser body.
- `_emit_ops_in_fn` now delegates `var_i32`, `assign_i32`, and top-level string
  init operation bodies to helpers, and Linux x64 net intrinsic lowering delegates
  epoll-family syscalls to a helper. The capped profile shows
  `x64_native_program.oren` at ~37.2s total / ~27.3s parse, with
  `_emit_intrinsic_sys_linux_misc_x64` exposed at ~557ms as the next parser body.
- Linux x64 misc syscall lowering now delegates fd-control syscalls (`fcntl`,
  `dup*`, `ioctl`, and related helpers) to a helper body. The capped profile
  shows `x64_native_program.oren` at ~37.4s total / ~27.3s parse, with
  `_emit_eval_call_expr_to_rax` exposed again at ~524ms as the next parser body.
- X64 call-expression lowering now delegates scalar conversion/bool intrinsics to
  `_emit_eval_scalar_call_intrinsic_x64`. The capped profile shows
  `x64_native_program.oren` at ~37.4s total / ~27.4s parse, with
  `native_compile_program_x64` exposed again at ~526ms as the next parser body.
- `native_compile_program_x64` now delegates entry prologue, stack scratch, and
  argv/env capture setup to `_x64_emit_entry_prologue_and_args`. The capped
  profile shows `x64_native_program.oren` at ~37.0s total / ~27.1s parse, with
  `_emit_eval_infix_to_rax` exposed at ~470ms as the next parser body.
- `_emit_eval_infix_to_rax` now delegates logical, comparison, modulo/division,
  shift, bitwise, and integer arithmetic lowering to focused helpers in
  `041_emit_infix_expr.oren`. The capped profile shows `x64_native_program.oren`
  at ~37.1s total / ~27.4s parse, with `_compile_function_v0` exposed at ~468ms
  as the next parser body.
- `_compile_function_v0` now delegates frame/local/intrinsic-temp sizing to
  `_x64_prepare_function_frame_v0`, and Linux x64 net syscall lowering now
  delegates fd2/accept/sockopt/message families to helper bodies. The capped
  profile shows `x64_native_program.oren` at ~37.6s total / ~27.8s parse, with
  `native_compile_program_x64` exposed again at ~445ms as the next parser body.
- `native_compile_program_x64` now delegates runtime-path/rtobj choice and
  runtime/user statement preparation to helpers while preserving the existing
  rtobj timing boundary. The capped profile shows `x64_native_program.oren` at
  ~37.8s total / ~28.0s parse, with `_x64_build_runtime_obj` exposed at ~435ms
  as the next parser body.
- `_x64_build_runtime_obj` now delegates runtime function metadata collection,
  local-function/lambda preparation, runtime/user splitting, and runtime-global
  slot allocation to helper bodies while preserving the existing rtobj phase
  markers. The capped profile shows `x64_native_program.oren` at ~37.2s total /
  ~27.5s parse, with `_emit_eval_call_expr_to_rax` exposed at ~412ms as the next
  parser body.
- X64 pointer/memory/native-allocation call intrinsics now live in
  `040_emit_call_intrinsics.oren` and `_emit_eval_call_expr_to_rax` delegates to
  compact classifier helpers after scalar intrinsics. The capped profile shows
  `x64_native_program.oren` at ~37.1s total / ~27.6s parse, with
  `_emit_fast_lcg_sum_while_x64` exposed at ~409ms as the next parser body.
- X64 fast LCG sum and list-int dot while emitters now delegate setup,
  repeated-step, list-validation, and whole-list helper blocks to narrower
  helper bodies. The capped profile shows `x64_native_program.oren` at ~37.1s
  total / ~27.5s parse, with `_emit_eval_int_to_rax` exposed at ~390ms as the
  next parser body.
- X64 expression evaluation now delegates literal, singleton, lambda, intrinsic
  temp, and identifier value lowering to helper bodies, and Linux x64 process
  syscalls delegate fork/exec/wait lowering to a process-family helper. The
  capped profile shows `x64_native_program.oren` at ~37.3s total / ~27.8s parse,
  with `_x64_build_runtime_obj` exposed at ~355ms as the next parser body.
- X64 runtime-object build now delegates runtime decl compilation, wrapper
  synthesis/compilation, and top-decl reporting, and `native_compile_program_x64`
  delegates function/global preparation to a compact helper. The capped profile
  shows `x64_native_program.oren` at ~37.4s total / ~27.8s parse, with
  `_emit_ops_in_fn` exposed at ~344ms as the next parser body.
- X64 op emission now delegates trace/progress, phase-progress, dynamic-gas
  patching, slow-op recording, and remaining regular dispatch helpers. Entry
  runtime bootstrap now delegates heap/frame setup, boot globals, argv/envp,
  runtime-init, static cstr/debug registration, args/envp, and capsule/GC setup
  to a bounded helper shard, and `_compile_function_v0` delegates spills,
  call-depth gating, GC tick init, body emission, and epilogue emission. The
  capped profile now shows `x64_native_program.oren` at ~36.4s total / ~27.2s
  parse, with `_emit_intrinsic_sys_linux_fd_misc_x64` exposed at ~312ms as the
  next parser body.
- Linux x64 fd-control syscall intrinsic lowering now delegates fcntl-family and
  dup/ioctl-family bodies to a dedicated include shard, and x64 user-global slot
  preparation now delegates alias-target collection, slow/progress tracing, and
  per-slot materialization to helpers. The capped profile now shows
  `x64_native_program.oren` at ~36.5s total / ~27.6s parse, with
  `_emit_intrinsic_stack_helpers_x64` exposed at ~303ms as the next parser body.
- X64 stack/diagnostic intrinsics now delegate code-address, context-init,
  context-switch, and symbol-resolution lowering to focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~36.7s total / ~27.9s parse,
  with `_emit_intrinsic_sys_linux_x64` exposed at ~303ms as the next parser body.
- Linux x64 top-level syscall lowering now delegates Windows-compat ENOSYS
  stubs, getrandom/getentropy, and ulock/futex paths to focused helpers while
  preserving validation early returns. The capped profile now shows
  `x64_native_program.oren` at ~38.8s total / ~29.8s parse, with
  `_emit_fast_list_int_get_sum_while_x64` exposed at ~311ms as the next parser
  body.
- X64 fast list-int get-sum while lowering now mirrors the dot fast-path split:
  preparation, list validation, optional whole-list helper, unrolled pair body,
  and single-step body are focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~36.7s total / ~27.7s parse, with
  `_emit_index_expr_v0` exposed at ~298ms as the next parser body.
- X64 index expression lowering now delegates operand spill/runtime fast paths,
  assumed-list indexing, receiver kind dispatch, and list/map emission to focused
  helpers. The capped profile now shows `x64_native_program.oren` at ~37.1s total /
  ~28.1s parse, with `_emit_intrinsic_sys_linux_misc_x64` exposed at ~279ms as the
  next parser body.
- Linux x64 misc syscall lowering now delegates signal, time, cwd/scheduler/sleep,
  fd, and net families instead of keeping those cases in one parser body. The capped
  profile now shows `x64_native_program.oren` at ~36.8s total / ~27.7s parse, with
  `_emit_fast_list_get_sum_while_x64` exposed at ~272ms as the next parser body.
- X64 fast list get-sum while lowering now mirrors the list-int split with
  preparation, sum-string flag, list-validation, and loop-body helpers. The capped
  profile now shows `x64_native_program.oren` at ~37.9s total / ~28.8s parse, with
  `native_compile_program_x64` exposed at ~285ms as the next parser body.
- `native_compile_program_x64` now delegates debug metadata setup, entry emission,
  function/backend tail compilation, and summary formatting to low-arity helpers.
  The capped profile now shows `x64_native_program.oren` at ~37.1s total /
  ~27.8s parse, with `_emit_generic_call_expr_v0` exposed at ~267ms as the next
  parser body.
- X64 generic named-call lowering now delegates intrinsic/spread dispatch, callee
  classification, and direct ABI call emission to focused helpers; Linux stat-family
  syscall lowering now shares host-stat to `OrenStatV0` translation and splits
  `stat`/`lstat` from `fstat`. The capped profile now shows
  `x64_native_program.oren` at ~37.4s total / ~28.3s parse, with
  `_emit_fast_lcg_sum_while_x64` exposed at ~268ms as the next parser body.
- X64 fast LCG sum while lowering now delegates entry gates, unsigned setup/loop,
  and signed full-mod loop emission to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~37.1s total / ~28.0s parse, with
  `_emit_intrinsic_sys_linux_proc_x64` exposed at ~263ms as the next parser body.
- X64 Linux proc syscall lowering now delegates memory mapping and clone/thread
  families to helpers, and Linux FS syscall lowering now delegates runtime stubs,
  pipe, and open/close/access families to helpers. The capped profile now shows
  `x64_native_program.oren` at ~37.4s total / ~28.2s parse, with
  `_emit_fast_list_int_push_while_x64` exposed at ~266ms as the next parser body.
- X64 fast list-int push while lowering now delegates preparation, list
  validation/reserve, loop stores, and final count updates to helper bodies. The
  capped profile now shows `x64_native_program.oren` at ~37.6s total / ~28.3s
  parse, with `_emit_global_string_init_batch_op_x64` exposed at ~260ms as the
  next parser body.
- X64 fallback global string-batch lowering now delegates trace setup, legacy item
  collection, per-item string data append, table/loop emission, and slow-op
  reporting to helper bodies. The capped profile now shows
  `x64_native_program.oren` at ~37.4s total / ~28.1s parse, with
  `_emit_intrinsic_sys_linux_path_family_x64` exposed at ~253ms as the next parser
  body.
- X64 Linux path-family syscall lowering now delegates unlink/rmdir, rename,
  mkdir/chmod, and getdirentries64 to helper bodies. The capped profile now shows
  `x64_native_program.oren` at ~37.0s total / ~27.6s parse, with
  `_emit_fast_list_push_while_x64` exposed at ~242ms as the next parser body.
- X64 generic list-push and list-int dot fast-loop lowering now delegate
  preparation, validation, cursor setup, loop headers, unrolled pairs, single-step
  bodies, and count/fixup updates through helper bodies, while local label fixup
  helpers write label positions to the function label map. The capped profile now
  shows `x64_native_program.oren` at ~37.7s total / ~28.3s parse, with
  `_emit_fast_list_dot_while_x64` exposed at ~244ms as the next parser body.
- X64 generic list-dot fast-loop lowering now delegates preparation, list
  validation, unique cursor setup, loop header, and single-step body emission
  through helper bodies. The capped profile now shows `x64_native_program.oren`
  at ~37.6s total / ~28.2s parse, with `_x64_rtobj_apply_code_to_ctx` exposed
  at ~240ms as the next parser body.
- X64 runtime-object apply now delegates data-tail, globals/imports/FFI/cstr,
  function-metadata, code append, function-offset, compact-fixup, legacy-fixup,
  and rip-data32 merge phases to helper bodies; Windows CreateProcess syscall
  lowering now delegates preparation, spill/zeroing, create-call, wait, exit
  status, and cleanup emission. The capped profile now shows
  `x64_native_program.oren` at ~38.1s total / ~28.6s parse, with
  `_x64_expr_is_floaty` exposed at ~217ms as the next parser body.
- X64 float-return classification, Windows entry argv synthesis, and spawn
  expression lowering now delegate their large parser bodies into focused helper
  shards while preserving the same runtime helper boundaries. The capped profile
  now shows `x64_native_program.oren` at ~38.1s total / ~28.7s parse, with
  `_compile_function_v0` exposed at ~211ms as the next parser body.
- X64 function compilation now delegates phase setup, context reset, ops
  analysis logging, frame prologue emission, call-depth entry hook emission, and
  done-phase detail formatting; entry global-root emission now delegates skip
  filtering, traced name emission, vector/map collection, root-table loop
  emission, and phase logging. The capped profile now shows
  `x64_native_program.oren` at ~38.4s total / ~28.7s parse, with
  `_emit_eval_pointer_call_intrinsic_x64` exposed at ~199ms as the next parser
  body.
- X64 pointer-call intrinsic lowering now delegates integer add, pointer loads,
  pointer stores, and unchecked u8-buffer loads to focused helpers; x64
  `oren_index_set` lowering now delegates operand spilling, map calls,
  receiver-kind dispatch, and list/map path emission through helper bodies. The
  capped profile now shows `x64_native_program.oren` at ~37.4s total / ~28.0s
  parse, with `_emit_list_int_push_intrinsic_v0_x64` exposed at ~189ms as the
  next parser body.
- X64 `oren_list_int_push` lowering now delegates argument spilling,
  list-int validation, value/header preparation, slow/fast push paths, and
  optional list-header tracing through helper bodies. The capped profile now
  shows `x64_native_program.oren` at ~37.6s total / ~28.0s parse, with
  `_x64_prepare_one_user_global_slot` exposed at ~188ms as the next parser
  body.
- X64 user-global slot preparation now delegates duplicate checks, direct
  `.data` initialization probes, fact collection, metadata registration, and
  slow-slot timing through helper bodies; `assign_i32` op lowering now delegates
  top-level string fast paths, empty-container fast paths, local/global facts,
  and global-slot stores. The capped profile now shows `x64_native_program.oren`
  at ~37.6s total / ~28.2s parse, with `_emit_intrinsic_sys_linux_net_x64`
  exposed at ~181ms as the next parser body.
- X64 Linux net syscall lowering now delegates socket and 3-argument address
  syscall families through focused helpers, making `_emit_intrinsic_sys_linux_net_x64`
  a router over the existing net helper bodies. The capped profile now shows
  `x64_native_program.oren` at ~37.2s total / ~27.8s parse, with
  `_emit_intrinsic_sys_read_x64` exposed at ~176ms as the next parser body.
- X64 `sys_read` lowering now delegates Windows `ReadFile` and Linux syscall
  emission through platform-specific helpers after shared validation. The capped
  profile now shows `x64_native_program.oren` at ~37.3s total / ~27.9s parse,
  with `_emit_list_push_intrinsic_v0_x64` exposed at ~176ms as the next parser
  body.
- X64 generic `oren_list_push` lowering now mirrors the list-int helper layout,
  delegating argument spilling, validation, header reads, slow/fast path
  emission, and optional header tracing through focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~38.0s total / ~28.3s parse,
  with `_x64_build_runtime_obj` exposed at ~180ms as the next parser body.
- X64 runtime-object build orchestration now delegates final blob/meta
  materialization and summary printing through focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~39.3s total / ~29.4s parse,
  with `_x64_build_top_level_init_stmts` exposed at ~190ms as the next parser
  body.
- X64 top-level initializer synthesis now delegates rewrite batch state,
  string literal batches, empty-container batches, Var rewrites, and progress
  logging through focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~38.2s total / ~28.6s parse, with
  `_emit_intrinsic_sys_stat_windows_x64` exposed at ~173ms as the next parser
  body.
- X64 Windows `sys_stat` / `sys_lstat` lowering now delegates OrenStatV0
  zeroing, directory-success emission, file-open emission, file-success
  translation/close, and capsule post hooks through focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~38.5s total / ~28.9s parse,
  with `_x64_emit_entry_return_path` exposed at ~173ms as the next parser body.
- X64 entry return-path emission now delegates Windows DLL, Windows executable,
  Linux `.so`, and Linux executable return paths through focused helpers and
  shares heap-spill emission. The capped profile now shows
  `x64_native_program.oren` at ~38.3s total / ~28.7s parse, with
  `_emit_intrinsic_sys_open_windows_x64` exposed at ~172ms as the next parser
  body.
- X64 Windows `sys_open` lowering now delegates capsule pre/post hooks, path
  normalization argument setup, desired-access mapping, creation-disposition
  stack args, and CreateFileA/error mapping through focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~37.8s total / ~28.3s parse,
  with `_emit_intrinsic_sys_linux_fcntl_x64` exposed at ~166ms as the next
  parser body.
- X64 Linux fd-control lowering now delegates raw `sys_fcntl`, `F_GETFL`,
  `F_SETFL`, and `getpath` fallback handling through focused helpers under the
  fd-misc router. The capped profile now shows `x64_native_program.oren` at
  ~38.2s total / ~28.6s parse, with `_emit_intrinsic_sys_write_x64` exposed at
  ~167ms as the next parser body.
- X64 `sys_write` lowering now delegates Windows `WriteFile` and Linux syscall
  paths through platform-specific helper bodies while preserving capsule
  prehook and zero-length write behavior. The capped profile now shows
  `x64_native_program.oren` at ~38.1s total / ~28.6s parse, with
  `_emit_malloc_size_in_rax` exposed at ~164ms as the next parser body.
- X64 malloc lowering now delegates 64KiB chunk sizing, Windows `VirtualAlloc`,
  Linux `mmap`, heap-register commit, fast bump allocation, and zero-size return
  through focused helpers while preserving the `malloc`/`malloc_raw`/`malloc_k`
  entry contract. The capped profile now shows `x64_native_program.oren` at
  ~37.9s total / ~28.3s parse, with
  `_emit_intrinsic_sys_linux_open_close_access_x64` exposed at ~163ms as the
  next parser body.
- Linux x64 open/close/access lowering now delegates `sys_open`, `sys_close`,
  and `sys_access` through focused helpers under the FS router. The capped
  profile now shows `x64_native_program.oren` at ~37.6s total / ~28.1s parse,
  with `_x64_prepare_function_frame_v0` exposed at ~162ms as the next parser
  body.
- X64 function-frame preparation now delegates parameter slot/type inference,
  reserved scratch slots, intrinsic-temp sizing, literal spill slots, and ABI
  layout calculation to focused helpers while preserving the same frame map
  contract. The capped profile now shows `x64_native_program.oren` at ~38.2s
  total / ~28.6s parse, with `_emit_intrinsic_sys_linux_ulock_x64` exposed at
  ~162ms as the next parser body.
- Linux x64 ulock/futex lowering now delegates shared futex syscall setup,
  timeout-timespec emission, timeout errno mapping, wait lowering, and wake
  lowering to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~40.1s total / ~30.3s parse, with
  `_x64_program_compile_options` exposed at ~203ms as the next parser body.
- X64 program compile option parsing now delegates progress/focus, entry toggles,
  slow-function ranking, and phase-detail limits to focused helpers while
  preserving the returned option map. The capped profile now shows
  `x64_native_program.oren` at ~39.2s total / ~29.5s parse, with
  `_emit_list_int_set_intrinsic_v0_x64` exposed at ~164ms as the next parser body.
- X64 `oren_list_int_set` lowering now delegates LTR argument spills, argument
  reloads, list-int validation, value/count checks, and slow/fast store emission
  through focused helper bodies. The capped profile now shows
  `x64_native_program.oren` at ~38.9s total / ~29.1s parse, with
  `_emit_intrinsic_sys_getentropy_windows_x64` exposed at ~159ms as the next
  parser body.
- Windows x64 `sys_getentropy` lowering now delegates entropy data assets,
  argument spills, buffer/length guards, dynamic `bcrypt` resolution, RNG call
  emission, and finish/error mapping to focused helpers. The resolver reloads
  the cached-function-pointer slot address after WinAPI calls before storing the
  resolved pointer, avoiding reliance on volatile `r10`. The capped profile now
  shows `x64_native_program.oren` at ~37.7s total / ~28.2s parse, with
  `_emit_stack_trace_best_effort` exposed at ~153ms as the next parser body.
- X64 best-effort panic stack-trace lowering now delegates Windows and Linux
  frame-walk/code-emission bodies to platform-specific helpers while keeping the
  shared scratch reservation wrapper small. The capped profile now shows
  `x64_native_program.oren` at ~38.0s total / ~28.5s parse, with
  `_emit_list_len_intrinsic_v0_x64` exposed at ~179ms as the next parser body.
- X64 `oren_list_len` lowering now delegates argument validation/spilling,
  label setup, nil handling, untracked-list fallback, and tracked LIST/LIST_INT
  count emission to focused helper bodies while preserving the same panic and
  magic-check paths. The capped profile now shows `x64_native_program.oren` at
  ~39.8s total / ~29.9s parse, with `_x64_compile_user_function_set` exposed at
  ~180ms as the next parser body.
- X64 user-function-set compilation now delegates option unpacking, per-function
  name/progress logging, detail toggling, slow-function live recording, and
  slow-summary emission to state-map helpers while preserving the low-arity loop
  call contract. The capped profile now shows `x64_native_program.oren` at
  ~39.5s total / ~29.8s parse, with `_emit_ops_in_fn` exposed at ~164ms as the
  next parser body.
- X64 function-op emission now delegates loop-state setup, gas-note charging,
  prebuilt top-level batch fast paths, post-op gas/slow logging, and body summary
  emission to focused helpers while preserving regular-op dispatch. The capped
  profile now shows `x64_native_program.oren` at ~38.3s total / ~28.6s parse,
  with `_emit_intrinsic_sys_linux_proc_clone_x64` exposed at ~150ms as the next
  parser body.
- Linux x64 proc/clone lowering now delegates raw `sys_clone`, `sys_thread_create`
  state/spill setup, clone syscall setup, and child start/exit emission to focused
  helpers while preserving `sys_gettid` dispatch and the clone capsule prehook.
  The capped profile now shows `x64_native_program.oren` at ~38.3s total /
  ~28.5s parse, with `_x64_emit_direct_named_call_v0` exposed at ~150ms as the
  next parser body.
- X64 direct named-call lowering now delegates explicit/default-`nil` argument
  spills, ABI register/stack loading, and call-fixup/FFI return normalization to
  focused helpers while leaving varargs on the fnobj ABI path. Linux x64 epoll
  lowering now delegates `sys_epoll_create1`, `sys_epoll_ctl`, and
  `sys_epoll_pwait` to syscall-family helpers. The capped profile now shows
  `x64_native_program.oren` at ~39.9s total / ~29.9s parse, with
  `_emit_stack_trace_windows_best_effort` exposed at ~160ms as the next parser
  body.
- Windows x64 best-effort stack tracing now delegates frame guards, raw return-PC
  line formatting/writing, and frame-chain advance to focused helpers while the
  wrapper retains label/fixup ownership. The capped profile now shows
  `x64_native_program.oren` at ~38.9s total / ~29.0s parse, with
  `_emit_intrinsic_sys_dispatch_x64` exposed at ~146ms as the next parser body.
- X64 syscall dispatch now keeps ABI-derived Windows target detection in a small
  helper and routes Windows syscalls through focused core/FS/time/entropy,
  net/IOCP/WinSock, and proc/thread/fcntl helper families before falling back to
  Linux lowering. The capped profile now shows `x64_native_program.oren` at
  ~38.7s total / ~28.9s parse, with `_emit_intrinsic_sys_wsarecvfrom_windows_x64`
  exposed at ~147ms as the next parser body.
- Windows x64 `WSARecvFrom` lowering now delegates argument spill/state setup,
  capsule pre/post hooks, WSABUF/IAT call emission, and pending/error result
  normalization to focused helpers while preserving the same `WSA_IO_PENDING`
  success mapping. The capped profile now shows `x64_native_program.oren` at
  ~38.6s total / ~28.8s parse, with `_emit_cmp_r64_r64_maybe_string_x64`
  exposed at ~178ms as the next parser body.
- X64 string-aware compare lowering now delegates spill-slot lookup, small-int
  fast path probes, string-pointer checks, inline strcmp lowering, and integer
  fallback emission to focused helpers, and runtime-object cache recovery now
  delegates cache identity, cache-hit apply, seed-hit apply, and store/apply
  finalization. The capped profile now shows `x64_native_program.oren` at
  ~40.2s total / ~30.3s parse, with `_emit_intrinsic_sys_linux_dup_ioctl_x64`
  exposed at ~152ms as the next parser body.
- Linux x64 dup/ioctl lowering now delegates raw `dup`, `dup2`/`dup3`, and
  `ioctl` syscall families to focused helpers while preserving capsule hook
  ordering and syscall register setup. The capped profile now shows
  `x64_native_program.oren` at ~39.7s total / ~29.8s parse, with
  `_emit_intrinsic_sys_fstat_windows_x64` exposed at ~145ms as the next parser
  body.
- Windows x64 `sys_fstat` lowering now delegates fd/st argument spill and
  capsule prehook, standard-handle resolution, stat materialization, and capsule
  posthook emission to focused helpers while preserving best-effort zero-size
  success for non-file handles. The capped profile now shows
  `x64_native_program.oren` at ~39.3s total / ~29.4s parse, with
  `_emit_list_int_get_intrinsic_v0_x64` exposed at ~142ms as the next parser
  body.
- X64 checked `oren_list_int_get` lowering now delegates argument spills, label
  setup, tracked LIST_INT validation, bounds checks, and element load emission
  to focused helpers while preserving the same panic strings and wrapper-owned
  fixup patching. The capped profile now shows `x64_native_program.oren` at
  ~39.1s total / ~29.0s parse, with
  `_emit_intrinsic_sys_linux_windows_compat_x64` exposed at ~149ms as the next
  parser body.
- Linux x64 lowering for Windows-only compatibility intrinsics now shares
  ENOSYS validation/emission and delegates QPC, IOCP/cancel, and WSA families
  to focused helpers while preserving validation errors and handled return
  values. The capped profile now shows `x64_native_program.oren` at ~39.0s
  total / ~28.9s parse, with `_emit_eval_call_runtime_or_fast_generic_x64`
  exposed at ~135ms as the next parser body.
- X64 call fast-path classification now delegates runtime-required generic
  calls, internal-prefix generic calls, and typed-buffer runtime name detection
  to focused helpers; native-call intrinsic lowering delegates `native_call1`,
  allocator, and panic paths; list-int unchecked dot-slot lowering delegates
  validation/spill setup and loop-body emission. The capped profile now shows
  `x64_native_program.oren` at ~39.4s total / ~29.2s parse, with
  `_emit_intrinsic_sys_write_windows_x64` exposed at ~133ms as the next parser
  body.
- Windows x64 `sys_write` lowering now delegates argument spill/prehook setup,
  standard-handle selection, and `WriteFile` result normalization to focused
  helpers. Missing fnwrap compilation delegates per-function synthesis/compile
  and phase logging, and the x64 SIMD dot intrinsic delegates argument setup,
  vector loop emission, and scalar tail emission. The capped profile now shows
  `x64_native_program.oren` at ~39.3s total / ~29.0s parse, with
  `_emit_intrinsic_sys_wsarecv_windows_x64` exposed at ~125ms as the next parser
  body.
- Windows x64 overlapped `WSARecv`/`WSASend` lowering now delegates state
  spilling, capsule pre/post hooks, IAT call setup, and pending/error
  normalization to focused helpers. Windows `getsockopt` lowering delegates
  spill state, capsule prehook, level/option translation, IAT call setup, and
  SO_ERROR normalization. The capped profile now shows
  `x64_native_program.oren` at ~41.2s total / ~30.8s parse, with
  `_compile_function_v0` exposed at ~134ms as the next parser body.
- `_compile_function_v0` now delegates phase-state setup, function entry
  registration, phase timestamp marks, and body/epilogue emission to focused
  helper bodies. Windows x64 `sys_read` now mirrors the `sys_write` helper shape
  for argument spill/prehook setup, handle selection, and `ReadFile` result
  normalization. Debug metadata setup now delegates display-label construction,
  runtime-object symbol collection, and symtab reservation. The capped profile
  now shows `x64_native_program.oren` at ~40.0s total / ~29.9s parse, with
  `_emit_intrinsic_sys_linux_cwd_sched_sleep_x64` exposed at ~121ms as the next
  parser body.
- Linux x64 cwd/scheduler/sleep syscall lowering now delegates `getcwd`,
  `sched_yield`, and `nanosleep` to focused helpers, with nanosleep's explicit
  stack-timespec syscall emission split out. Windows x64 `sys_gettimeofday`
  delegates argument spilling, capsule prehook, `tv` validation, wall-time
  materialization, and optional QPC emission. Checked x64 `oren_list_int_len`
  now mirrors the helperized `oren_list_len` validation shape. The capped
  profile now shows `x64_native_program.oren` at ~40.8s total / ~30.6s parse,
  with `_emit_intrinsic_sys_linux_proc_exec_x64` exposed at ~120ms as the next
  parser body.
- Linux x64 process syscall lowering now delegates `fork`, `execve`, and
  `wait4` to focused helpers while preserving capsule hook ordering. X64 context
  creation now delegates progress-trace detection, base map setup,
  alias/lambda state, runtime data-slot reservation, and debug trace flags. The
  capped profile now shows `x64_native_program.oren` at ~40.4s total / ~30.1s
  parse, with `_emit_indirect_call_via_fnobj_x64` exposed at ~120ms as the next
  parser body.
- X64 indirect fn-object calls now delegate argument spilling, args-list
  materialization, callee spilling, and wrapper-call emission to focused helpers.
  Fast list-int dot unroll2 lowering now delegates per-multiply slot lookup,
  unrolled pair emission, and loop-tail emission; fast list-int push validation
  now delegates entry gates, reserve emission, and per-list validation. The
  capped profile now shows `x64_native_program.oren` at ~40.3s total / ~30.0s
  parse, with `_emit_eval_scalar_call_intrinsic_x64` exposed at ~118ms as the
  next parser body.
- X64 scalar call intrinsics now delegate float bit-cast and bool-normalization
  lowering to focused helpers, and fallback top-level string-batch data append
  now delegates progress tracing plus per-item offset/value/data materialization.
  The capped profile now shows `x64_native_program.oren` at ~40.3s total /
  ~30.0s parse, with `_x64_emit_ctx_switch_intrinsic` exposed at ~116ms as the
  next parser body.
- X64 context switching now delegates GPR save/restore, resume-address capture,
  XMM save/restore, and next-context return emission to focused helpers. Windows
  x64 path normalization now splits scratch setup, local labels, copy loop, and
  finish patching, and Windows `sys_setsockopt` mirrors the helperized
  `getsockopt` shape for spill state, capsule prehook, WinSock constant
  translation, call setup, and result normalization. The capped profile now shows
  `x64_native_program.oren` at ~39.5s total / ~29.2s parse, with
  `_emit_intrinsic_sys_linux_net_addr3_x64` exposed at ~107ms as the next parser
  body.
- Linux x64 3-argument socket address syscalls now share addr3 helpers for
  intrinsic state spilling, capsule prehooks, syscall-number emission, and the
  connect/bind posthook paths while keeping getpeername/getsockname as no-post
  syscalls. The capped profile now shows `x64_native_program.oren` at ~39.6s
  total / ~29.4s parse, with `_x64_collect_top_level_globals_and_stmts` exposed
  at ~107ms as the next parser body.
- X64 top-level global collection now delegates debug top-level statement
  tracing, trace metadata formatting, slice-bound parsing, slice tracing, and
  slice application to focused helper bodies while preserving the
  `OREN_TRACE_TOP_LEVEL_*` and `OREN_TOP_LEVEL_*` debug environment contracts.
  The capped profile now shows `x64_native_program.oren` at ~39.8s total /
  ~29.4s parse, with `_x64_fast_list_push_validate_lists` exposed at ~107ms as
  the next parser body.
- X64 fast generic list-push validation now delegates loop-bound checks,
  per-list temporary-slot state, list capture, tracked LIST/magic validation,
  reserve emission, and count/buffer capture to focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~40.0s total / ~29.8s parse,
  with `_x64_emit_entry_prologue_and_args` exposed at ~105ms as the next parser
  body.
- X64 entry prologue emission now delegates platform-kind detection, DLL attach
  gating, Win64/SysV register preservation, executable stack alignment, stack
  layout/reservation, prologue phase logging, and Windows argv/env capture to
  focused helpers while preserving the returned entry setup map. The capped
  profile now shows `x64_native_program.oren` at ~40.2s total / ~29.7s parse,
  with `_x64_emit_ffi_stub_linux_dyn` exposed at ~104ms as the next parser body.
- Linux x64 dynamic FFI stubs now delegate data-cell/string materialization,
  cached function-pointer load, SysV argument spill/restore, resolver call,
  cache-store, target tailcall, and unresolved-symbol panic emission to focused
  helpers while preserving local fixup ownership. The capped profile now shows
  `x64_native_program.oren` at ~40.8s total / ~29.8s parse, with
  `_emit_varargs_named_call_via_fnobj_x64` exposed at ~117ms as the next parser
  body.
- X64 varargs named-call lowering now delegates state preparation, left-to-right
  explicit argument spills, spill-slot preparation, argument-list allocation,
  ordered list pushes, named fn-object spilling, and inline `oren_call_obj_list`
  emission to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~40.9s total / ~30.1s parse, with
  `_emit_fast_list_int_get_sum_while_x64` exposed at ~134ms as the next parser
  body.
- X64 fast list-int get-sum while lowering now delegates label setup, bounds
  checks, optional whole-list helper dispatch, loop header/unroll guarding,
  loop-body emission, and final jump fixup resolution to focused helpers. The
  capped profile now shows `x64_native_program.oren` at ~40.6s total / ~30.1s
  parse, with `_emit_intrinsic_sys_linux_proc_memory_x64` exposed at ~104ms as
  the next parser body.
- X64 Linux proc-memory syscall lowering now delegates private anonymous mmap
  and munmap emission to focused helpers with a shared ABI-kind probe while
  preserving capsule hook argument registers and Windows fallback emission. The
  capped profile now shows `x64_native_program.oren` at ~41.3s total / ~30.9s
  parse, with `_emit_intrinsic_sys_linux_access_x64` exposed at ~130ms as the
  next parser body.
- X64 Linux `sys_access` lowering now delegates argument spill state, capsule
  prehook pair handling, `faccessat` syscall register setup, and capsule posthook
  emission to focused helpers under the FS router. The capped profile now shows
  `x64_native_program.oren` at ~43.0s total / ~32.3s parse, with
  `_x64_fast_list_get_sum_emit_single` exposed at ~112ms as the next parser body.
- X64 generic list get-sum single-step lowering now delegates list-index
  resolution, element load emission, and integer/string-aware accumulation to
  focused helpers while preserving the fast-loop sum and index writeback
  contract. The capped profile now shows `x64_native_program.oren` at ~40.7s
  total / ~30.1s parse, with `_x64_compile_program_function_sequence` exposed at
  ~221ms as the next parser body.
- X64 program function-sequence orchestration now delegates top-level/rtobj
  setup, user-function loop option packing, and wrapper/fnwrap/FFI/panic tail
  emission to focused helpers while preserving the phase timing map returned to
  the compile summary. The capped profile now shows `x64_native_program.oren` at
  ~41.7s total / ~31.0s parse, with `_x64_emit_ffi_stub_win64` exposed at ~105ms
  as the next parser body.
- Native HTTP/2 client response header-block and DATA payload accumulation now uses amortized `u8_buf` builders, and header-only responses with `END_STREAM` terminate without waiting for a DATA frame.
- X64 conditional branch and SETcc instruction builders now decode condition strings through byte-based opcode helpers and expose direct opcode builders; the central label and compare-not emitters use the numeric path to avoid repeated string-equality dispatch in hot branch emission.
- Renamer scope lookup now caches positive and negative results per parent-linked scope frame and updates the active frame cache on declaration. The focused `renamer_scope_cache_shadow_main` fixture proves the hot false-then-declare shadowing path still resolves a later local over an earlier imported module alias.
- X64 native index get/set lowering now emits a map-only path for proven map receivers and string-literal keys, delegates checked map validation to runtime helpers, and delegates unknown dynamic receiver get/set through generic runtime helpers instead of inlining full list+map dispatch at every parameter-local access; focused Linux/Windows compile-only coverage includes dynamic parameter-local index helpers. Compiler phase logging now appends through `oren_append_file` instead of reading and rewriting the whole trace per phase; the refreshed no-cache self-host trace reaches `link.optimizer.done`, global DCE, and `x64.codegen.ctx.done`, with x64 runtime-object markers showing the current cold-cache gap inside `x64.rtobj.build.start`. X64 function progress is now configurable with `OREN_TRACE_X64_FNS_PROGRESS_INTERVAL`; renamer visitor caching reduced focused no-cache `collect_toplevel_rename_pairs` emit from roughly 16s to about 11.4s and `scope_push` from about 8.6s to about 5.7s. Default optimizer phase logging now gates deep per-node counters and hot-function rankings behind `OREN_TRACE_OPTIMIZER_DETAIL=1`, reducing optimizer summary emission from about 21s to about 2ms in a compiler-shaped x64 trace. X64 string literal lowering now uses a bounded 32-entry C-string MRU before the existing data dedup map, and `rename_stmt` uses independent early-return branches instead of one nested `else if` chain; the focused compiler-shaped x64 trace reduced `rename_stmt` from about 64.8s to about 12.1s and moved the active diagnostic past `rename_expr`. X64 backend instruction emission now calls `x64_core` instruction builders directly instead of compiling a duplicate prelude forwarding layer; the compiler-shaped trace reduced linked x64 functions from 2598 to 2501. X64 function frames now reserve dedicated list/map literal spill slots only when a conservative ops scan finds list/hash literals; focused frame probes show literal-free `__top_level__` at `literal_slots=0` and list-literal `main` at `literal_slots=16`. Statement/expression branch helpers now keep renamer dispatch bodies smaller, with focused x64 probe evidence at about 61ms for `rename_stmt` and 57ms for `rename_expr`; annotation builtin checks are split by category, replacing the former roughly 57ms monolithic checker with about 20ms/15ms/15ms/6ms helper bodies. X64 base-memory and displacement instruction builders now append ModRM/SIB/displacement bytes directly through `_emit_mem_base_modrm_sib_disp` instead of allocating per-instruction metadata maps; Linux/Windows x64 compile-only gates cover the MOV, atomic, MOVDQU, and MOVDQA surface. X64 intrinsic-temp sizing now includes the live call spill slots held by array/hash literal builders, with the nested-map literal fixture covered by the default Linux/Windows x64 compile-only matrix. ELF/PE local-fixup dispatch now caches the fixup count and each fixup kind once, and PE uses single-branch shape dispatch; the focused nested-map Linux x64 probe shows local fixups at about 26ms. Runtime-object call-fixup replay now caches sidecar pointers/base metadata once and uses raw pointer u64 sidecar reads, moving the 15,924-call focused replay from about 289ms to about 237ms. X64 instruction builders now use `low3`/`u8` bit-mask helpers for ModRM/REX register packing and signed-byte emission instead of calling general positive modulo in the hot encoder path; shared byte-builder u16/u32 little-endian writes now mask signed values once and have a focused negative-width layout fixture. Remaining x64 hotspots are traversal helpers and broader real `x64_core` instruction-builder/user-function emission.
- Base64 decode now rejects interior padding and third-character padding without
  fourth-character padding plus nonzero trailing pad bits while keeping decoded
  output as exact-size `u8_buf`; Base64URL encode/decode now uses the same
  direct byte-buffer path.
- Bytecode metadata constants are now formed as byte-native UTF-8 payloads, and
  direct/link bytecode emission gates use carrier-aware byte lengths for metadata
  and OBX payloads.
- iOS `OrenAVMKit` builds as an xcframework and verifies TIME, FS, VNET, VPROC,
  GFX/input, package store, trust bundle, permission grant persistence, and
  compiler-in-AVM smoke paths through `make verify-libavm-ios`.
- `std:ui/scene3d` package coordinate and generated primitive meshes now accept validated
  authoring-time `scale_xyz_milli`, `pivot_xyz`, `rotation_xyz_milli_deg`
  (with `rotation_z_milli_deg` shorthand), and `translation_xyz` transforms
  for `triangles_xyz`, `quads_xyz`, `vertices_xyz`, `triangles_xyz_rgba`,
  `boxes_xyz`, `prisms_xy`, bounded `heightfields_xy` terrain grids, bounded
	  `surfaces_xyz` arbitrary surface grids, rectangular `planes_xy`, filled `rounded_rects_xy`, flat `polygons_xy`,
	  regular `regular_polygons_xy`, `stars_xy`, circular `discs_xy`/`rings_xy`,
	  elliptical `ellipses_xy`/`ellipse_rings_xy`, thick `segments_xy`/`paths_xy`, sampled `beziers_xy`, partial
	  `sectors_xy`/`arc_bands_xy`, sloped `ramps_xy`, solid `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, and curved generated solids before
  byte-native packing, including translation-only generated meshes.
- Scene3D generated mesh packers are split across focused helpers
  (`std:ui/scene3d_shapes_flat`, `std:ui/scene3d_shapes`,
  `std:ui/scene3d_shapes_arch`, and `std:ui/scene3d_shapes_grid`) so package-format growth does not push
  `std:ui/scene3d` or one shape helper over the source-line guard.
- `std:sys` now provides pure AVM capability-domain id/name/mask helpers plus
  the default embedder domain mask, and is covered by the stdlib OBC surface gate.
- `std:env` now provides app-facing capability-gated environment get/fallback,
  presence, require, and truthy helpers over the existing runtime ENV policy surface.
- `std:net/url` now provides pure HTTP/WebSocket URL parsing, request-target
  path/query splitting, authority extraction, bracketed-IPv6 structure, explicit
  userinfo rejection, canonical HTTP/WebSocket origin/same-origin helpers, generic
  endpoint-origin, host/port authority construction, plus host-or-origin
  allow-list helpers, percent encode/decode, query param get/list, and exact-size
  query building/replacement/appending shared
  by native `std:net/http`, native `std:net/ws`, and AVM-safe app code; native
  and AVM HTTP request opts now route structured `query` / `append_query` pairs
  through the same composer, while
  native HTTP/WebSocket Host headers preserve parsed authority, and native wire
  requests plus AVM HTTP/session specs strip URL fragments at the NET boundary.
  Native IPv4/DNS-A connectors now reject IPv6 literals explicitly instead of
  treating them as hostnames, and iOS runtime/package URL fetch plus live session
  allow-lists accept canonical origins in addition to legacy host entries.
- `std:path` now provides pure slash-separated VFS/package path split, normalize,
  join, boundary-checked `join_under`, containment, dirname, basename, and extension
  helpers shared by AVM and desktop SDK code.
- `std:fs` now provides app-facing capability-gated text, byte-native `u8_buf`,
  legacy byte-list, exists, directory-list, and chmod facade helpers over the
  existing runtime FS policy surface, plus root-scoped `*_under` helpers that
  compose with `std:path.join_under` for traversal-safe VFS/package access.
- `std:proc` now provides app-facing capability-gated run/status/result helpers
  plus status-map `code`/`ok`/`require_ok` combinators over the existing runtime
  PROC policy surface and AVM VirtualPROC fixtures.
- `std:timer` now provides nanosecond-native deadline/watch/interval helpers plus
  explicit millisecond/nanosecond floor/ceil conversion helpers for host/event-loop
  adapters; native ARM64/x64 float-return heuristics no longer misclassify arbitrary
  `*_floor`/`*_ceil`/`*_round` integer helpers as f64 carriers, while `std:math`
  trig range reduction keeps f64 remainders out of ambiguous mixed-list native
  tuple returns on the hot medium path.
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
- Public `bytes.unpack` routes u8-buffer carriers through kernel byte intrinsics,
  and AVM returns optimized integer lists for unpacked byte buffers.
- `buffer.u8_unpack` now reuses the byte-native `bytes.unpack` path for u8
  buffers instead of re-reading each byte in the stdlib loop.
- `std:math` now includes deterministic C/C++ classification aliases
  (`isnan`, `isinf`, `isfinite`, `isnormal`, `isunordered`), ordered comparison
  aliases (`isgreater`, `isgreaterequal`, `isless`, `islessequal`,
  `islessgreater`), `fpclassify`, and `nan()`, backed by AVM and module-level
  backend fixtures.
- `std:math` now includes deterministic tolerance, graphics scalar/interpolation, and range-mapping
  helpers `isclose`, `isclose_abs`, `sign`, `step`, `fract`, `clamp`, `saturate`, `lerp`, `inverse_lerp`, `remap`,
  `remap_clamped`, `smoothstep`, `smootherstep`, angle wrapping, shortest-angle
  delta, shortest-path angle interpolation helpers, pure finite `std:math/vec2`
  helpers for common 2D graphics/vector operations, pure finite
  `std:math/vec3` helpers for common 3D vector operations, and pure finite
  `std:math/vec4` helpers for homogeneous/vector algebra, backed by native/C/
  bytecode and AVM fixtures.
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
  buffers, bytes, JSON/CBOR/YAML/regex, crypto helpers, linalg, math, time/timer,
  `std:net/url`, `std:path`, `std:net/avm` DNS/TCP/UDP/WebSocket facades, `std:ui/avm`,
  `std:avm/events`, and `std:avm/permission`.
