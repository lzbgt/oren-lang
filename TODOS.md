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
| AVM-IOS-GFX-METAL | P1 | W5 | doing | Add game-grade Metal/`MTKView` GUI path. Current slice adds an SDK `OrenAVMMetalView` draw-loop/input/screen-state adapter for the current `OGF0` drawing subset (`fill_rect`, `push_clip_rect`, `pop_clip`, `push_translate`, `pop_transform`, `push_opacity`, `pop_opacity`, `push_camera_ortho`, `pop_camera`, `stroke_line`, `stroke_rect`, `round_rect`, `circle`, `ellipse`, `polyline`, `fill_triangle`, `fill_triangles`, `mesh2d`, `draw_mesh2d`, `destroy_mesh2d`, `mesh3d`, `mesh3d_rgba`, `mesh3d_indexed`, `material3d`, `model3d`, `draw_mesh3d`, `draw_mesh3d_at`, `draw_mesh3d_material`, `draw_mesh3d_at_material`, `draw_model3d`, `destroy_mesh3d`, `destroy_material3d`, `destroy_model3d`, `text`/`text_bytes`, `text_resource`, `draw_text`, `draw_texts`, `destroy_text`, `image_rgba`, `draw_image`, `destroy_image`, `draw_image_rect`, `draw_image_rects`) with cached text textures, bounded text atlas packing plus same-atlas text-run coalescing, event-driven multicast frame wakeups, mutex-protected latest-frame mailbox reads, coalesced renderer main-queue reloads, coalesced virtual `frame_tick` and motion events, SDK-visible frame metrics, stable multi-pointer touch forwarding, compact gamepad/controller, focus, and IME/composition `OGE0` events, byte-native and retained text payloads for OBC hot paths, configurable measured CPU frame-budget gates, retained image/sprite/upload/draw/destroy/sub-rect/batched-atlas records, retained 2D mesh resource records, retained 3D mesh resource records with orthographic XY default projection, byte-native per-triangle RGBA payloads, indexed shared-vertex 3D meshes, retained material resources, retained model resources, pure OBC-side `std:ui/scene3d` retained-scene command builders plus JSON and byte-native `.os3d` package-asset loading with scene-level camera depth windows, named JSON mesh/material/model references, model templates, instances, grouped instances with parent transform composition, per-draw model/material/transform override objects, human-readable `position_xyz` or nested `transform` records, human-readable `vertices_xyz`/`vertices_xy` with `faces`/`quads` indexed meshes, builder-side glTF 2.0 JSON/GLB `gltf_source` plus inline JSON `gltf_json` with URI or BIN buffers, indices, sparse accessors, static `POSITION`/`COLOR_0` morph target weights, baked skinning through `JOINTS_n`/`WEIGHTS_n` and inverse bind matrices, sampled `gltf_animation`/`gltf_sample_time_milli` node translation/rotation/scale/morph-weight animations, material base colors multiplied by `COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix hierarchy selection, Wavefront OBJ `obj_source`/`obj_text`, binary-or-ASCII STL `stl_source`, inline ASCII STL `stl_text`, binary-or-ASCII PLY `ply_source`, and inline ASCII PLY `ply_text` mesh lowering, PLY face or averaged vertex colors into `mesh3d_rgba`, core 3MF `3mf_source` ZIP mesh/build plus basematerial `displaycolor` lowering and optional `3mf_triangle_set` subgroup selection, `triangles_xyz`/`quads_xyz` direct meshes, compact `boxes_xyz` cuboids, `prisms_xy` extruded polygons, bounded `heightfields_xy` terrain grids, bounded `surfaces_xyz` arbitrary surface grids, flat indexed `vertices_xy`, rectangular `planes_xy`/`rects_xy`, flat `triangles_xy`/`quads_xy`, flat per-triangle-color `triangles_xy_rgba`/`quads_xy_rgba`, filled `rounded_rects_xy`, flat `polygons_xy`, regular `regular_polygons_xy`, `stars_xy`, circular `discs_xy`/`rings_xy`, elliptical `ellipses_xy`/`ellipse_rings_xy`, thick `segments_xy`/`paths_xy` and sampled `beziers_xy`, partial `sectors_xy`/`arc_bands_xy`, sloped `ramps_xy`, solid `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, bounded `cylinders_z`/`cones_z`/`spheres_xyz`/`ellipsoids_xyz`/`toruses_xyz`/`capsules_z`, human-readable per-triangle `triangles_xyz_rgba` colors, richer material fields lowered to v0 RGBA colors, and sampled transform keyframes lowered to existing numeric byte-native assets/model records, deterministic painter-depth ordering, material override draws, per-draw and retained model translation/uniform scale via `draw_mesh3d_at`, and explicit orthographic camera depth windows via `push_camera_ortho`, Oren-side image upload budgets, SDK retained image count/pixel budgets, release-manifest whole-frame 2D and dedicated 3D raster conformance hashes, iOS SDK package-store conformance for mounted `.os3d` scene assets, drawable-independent Metal frame preparation metrics for retained 3D/resource frames, generated live-device 3D capture app build/signing preflight and on-phone physically rotated cube mesh proof via `make capture-ios-live-3d-performance`, phone-copied PNG snapshot capture, packed Metal shader vertex structs matching CPU upload strides, static SDK category linkage through `-ObjC`, Xcode-managed development-profile discovery, `stroke_rect`/`round_rect`/`ellipse`/`polyline`/batched-triangle/clip-stack/translation-stack/opacity-stack coverage across raster/CoreGraphics/Metal, and a package-format parity guard covering all current Oren-side human-readable mesh payload keys plus raw ABI and source-import paths; remaining work is broader game-grade GUI/Metal polish. | `make verify-libavm-ios && make test-avm` |
| AVM-IOS-STORE-DEMOS | P1 | W4 | done | Create curated demo OBC programs/packages for the `store.hubstack.cn` OBC store site so iOS host apps can download and run useful examples after GUI/network gates. Current demos build deterministic science/linalg, UI/GFX, and Scene3D package directories plus `.obc.zip` release bundles under `build/obc-store-demos`, with official source bundled as hashed assets and store-only deterministic 640x360 PNG screenshots published as release presentation metadata outside package manifests, client assets, and bundles. | `make verify-obc-store-demos && make verify-obc-store-service` |
| OBC-STORE-SERVICE | P1 | W4 | doing | Complete the `store.hubstack.cn` Go registry/API service. Current slice has publisher/package/release publish, signed public index with active key-id headers, rotation-capable public trust-bundle serving, host-facing package update checks, browser browse/detail/publisher/operator pages with release capabilities/source/permission/update metadata, store-only screenshot previews, server-rendered Oren source pages with syntax highlighting plus AST outline, authenticated `/ops/status` plus `/api/v0/ops/status` deployment summaries with build commit/time, aggregate release-ready/incomplete and missing-readiness counts plus data-dir writable/storage byte totals by metadata/payload/program/bundle/asset/screenshot/audit class, authenticated filterable `/ops/releases` plus `/api/v0/ops/releases` release lifecycle inventories by status/visibility/readiness with no-JS publish/yank/package-visibility forms, authenticated filterable `/ops/updates` plus `/api/v0/ops/updates` latest/superseded update inventories by publisher/package/visibility/superseded state with total/filtered counts, authenticated filterable `/ops/audit` plus `/api/v0/ops/audit` append-only mutation audit logs by action/actor/target with total/filtered counts, `/healthz` plus `/api/v0/health` for build-stamped deployment probes, public-by-default package visibility with publisher/admin private toggle, `.obc.zip` bundle upload/download/index metadata, SDK bundle-preferred install with expanded-artifact fallback, search/download, yanking, iOS SDK install/run smoke with persisted last-known update status, deploy-safe admin bearer auth, publisher-scoped bearer auth, token rotation/revocation APIs, systemd deployment on the cloud host, checked Dockerized Traefik dynamic route config plus deploy-time and live-route authenticated operator-status storage/readiness probes, admin-env host fallback plus explicit `sshpass -e` password mode for deployment, local data-dir backup/restore smoke for metadata plus artifacts, and live `oren-labs` demo releases for science, UI, and Scene3D; remaining work is live deployment/operator polish, currently blocked on corrected SSH credentials for replacing the live service. | `make verify-obc-store-service && make verify-obc-store-backup-restore && make verify-obc-store-deploy-script && make verify-obc-store-live-route && make verify-libavm-ios` |
| AVM-IOS-PERM-UX | P1 | W4 | done | Package permission prompt UX handoff for host apps. SDK has persisted grants, runtime NET grant/revocation application, decoded OBC permission requests, host-facing `OrenAVMPermissionPrompt` metadata for native UI, prompt-based decision recording, explicit package `permission_defaults` application, and Note now presents live source/OBC prompts with explicit Allow/Deny decisions persisted through `OrenAVMPermissionGrantStore` and applied before future live runs. | SDK verifier plus Note handoff verifier |
| AVM-RELEASE-MANIFEST | P1 | W4 | done | Add a manifest-driven AVM release runner covering fixture path, expected exit/error, budgets, backend policy, deterministic mode, host-effect expectations, setup builds, multi-phase record/replay and snapshot/resume runs, line-prefix captures, cross-phase assertions, and release-gate inclusion. `make test-avm` now runs through `tests/avm/release_manifest.json` while preserving `AVM_TESTS` overrides, every current `tests/avm/test_*.oren` fixture is present in the manifest, and bytecode/setup builds receive an explicit platform so parallel verification does not depend on host autodetect. | `make verify-avm-release-manifest && make test-avm` |
| AVM-STDLIB-COMPLETE | P1 | W4 | done | Replaced the representative stdlib smoke with manifest-driven coverage for every module imported by `lib/std/stdlib_avm.oren`; the gate now fails on bundle/manifest drift, host-only exclusion leaks, and missing app-facing OBC exports such as `STD_linalg_dot_f64`. | `make verify-avm-stdlib-obc-surface` |
| AVM-BYTES-HOTPATH | P1 | W3 | doing | Remove legacy list-of-byte/string conversions from hot AVM app-facing APIs; keep bytes as the performance path and text conversion only at explicit boundaries. Current slices add `std:ui/avm` `text_bytes`, direct text/composition event payload string slicing, and exact-size directly-returned `u8_buf` OGF0 frame encoding with direct string-byte writes for plain `text` commands, `std:ui/color` hex parsing over direct ASCII byte reads, `std:ui/scene3d` coordinate/face/color package asset packing through exact-size directly-returned `u8_buf` builders plus color hex emission through string slices, `std:net/avm/http.get(...).bytes()` over AVM NET op 8 for byte-native HTTP/VNET responses, native `std:net/http` response reads directly into reserved response storage plus `.bytes()` over cached typed body bytes for content-length responses and exact-sized decoded chunked bytes, direct `std:bytes.to_string` byte-slice conversion, `std:bytes.from_string`/`from_hex`, kernel `oren_bytes_from_string` byte-native u8-buffer output, direct `to_hex` exact-size lowercase hex emission plus C/native runtime hex/string/slice/unpack/pack/endian-read/write helpers reading or writing list/u8-buffer backing storage directly after one validation pass, and `std:strings` byte roundtrips over byte-native u8 buffers, `std:bytes` direct u8-buffer reads for get/unpack/concat/copy sources, exact-size u8-buffer `pack`, u8/endian writes, concat/copy u8-buffer spans, overlap-safe u8 `copy_into`, `std:buffer` view/matrix `copy_from_bytes` direct byte-carrier reads with contiguous slice/dense-matrix u8 destinations routed through `bytes.copy_into`, contiguous slice/dense-matrix byte/text exports routed through direct byte-slice conversion, raw u8 buffer loads/stores plus u8 slice/strided/matrix view loads/stores through direct pointer access after public validation, and `copy_into` u8-buffer destinations through raw pointer stores after public span checks, JSON full decode, scalar parse, tag equality, and escape output over direct source-string byte reads or exact-size `u8_buf` buffers, CBOR canonical key ordering/text encoding through growable `u8_buf` output plus u8-backed decode byte carriers, and full regex pattern/text matching over direct string byte reads, YAML comment stripping, quoted-scalar parse/escape, line/trim/key split, key sort, bare-identifier, prefix, and suffix helpers without list-of-byte reconstruction, XML/HTML parser literal matching, class-selector scans, DOM parsing, and streaming readers over direct source-string byte reads without repeated input byte-list materialization, WebSocket accept hashing through direct SHA-1 UTF-8 string hashing plus upgrade header reads directly into reserved header storage and unmasked frame sends streaming raw payload spans, Base64/Base64URL decode/encode exact-size output writes through direct u8-buffer stores, Base64 range decoders for PEM body spans without sliced/compacted temporary strings, per-byte position maps, or a separate strict-body validation pass, PPM header/body output and software raster clear/pixel writes through raw exact-size buffer stores, native `oren_write_file` direct string syswrites, compiler source-policy scans, cache line/number parsing, bounded scan-cache load/save and delimiter writes, C-runtime include scanning, manifest JSON escaping, bytecode metadata payload writing, bytecode final artifact return as `u8_buf`, compiler SHA digest hex routing through direct runtime bytes hex, OBC linker byte reads from `u8_buf` with overflow-safe shared byte-view spans and guarded unchecked readers, parsed OBC code and byte constants kept as `u8_buf`, builder-patched linked code, linked OBC final emission as `u8_buf`, plus malformed-OBC/OBX span guards, bytecode string constants, OBX string/prefix encoding through compact byte builders, AST binary v1 full-value raw writes plus bounded u8 decode reads, native Mach-O/ELF object string payloads, runtime-object debug-name blobs, x64 native debug-table names, ARM64 native panic-message payloads, shared compiler byte-builder append/list/string/set stores, lexer string-literal decoding through compact byte builders, and C identifier escaping over direct string byte reads plus raw exact-size output writes, AVM `oren_bytes_len`/`get_u8`/`pack` parity for byte-list and optimized int-list carriers, `std:buffer` u8 matrix packs through direct writes plus u8 view/matrix byte copies through `u8_buf` instead of unpacked lists, direct string-byte copy into raw u8 buffers, slice/strided views, whole u8 matrices, strided u8 and non-dense u8 matrix exports through direct gather into exact-size output, and u8 slice/strided/matrix stores through raw pointer writes after u8-carrier checks, `std:buffer` zero-copy Slice/Strided/Matrix wrapper methods for chainable view operations, canonical `std:buffer` facade plus raw/view/core/numeric/u8-matrix helper names, checked canonical matrix projection/view helpers, SHA-1/SHA-256 virtual padding over indexed byte access plus direct fixed-size digest `u8_buf` output through unchecked final stores, SHA-1/SHA-256 direct string hashing for UTF-8 string inputs, SHA hex helpers plus Windows Schannel certificate hash formatting through direct std bytes hex emission, Windows Schannel passphrase cache keys, native RNG bytes filled directly into result buffers, native IPv6 sockaddr address bytes copied directly from `u8_buf` or list backing storage, HPACK Huffman encode/decode, decoded-string boundaries, and full header-block encoding through exact-size `u8_buf` payloads or byte-slice conversion, native HTTP/2 content-length DATA bodies through exact-capacity `u8_buf` accumulation with mismatch checks, fragmented HEADERS writes through raw header-block spans, and inbound single-CONTINUATION header blocks through exact-size assembly, TLS ALPN decoded-byte strings through byte-slice conversion, PEM/base64 body handling without intermediate Oren byte lists plus strict PEM body raw exact-size writes, and canonical codec/parser/RNG/protocol/UI/crypto/string/list/linalg/iter/checked-cast fallible verbs or `{ok,...}` records instead of public `try_*` API names. | `make test-avm && make verify-libavm-ios` |
| NATIVE-NUMERIC-GENERICS | P1 | W3 | done | Native generic-helper numeric cast semantics now use backend-neutral direct-call numeric parameter trait inference. Monomorphic direct-call float/int evidence specializes helper parameters for native lowering, while mixed or unknown generic evidence does not guess from untagged runtime carriers. | native/AVM cast fixtures plus `make test` |
| AVM-EVENT-FS-PACKAGE | P2 | W3 | done | Added host-enqueued FS/package virtual events to the AVM `EVENT` bus. OBC watches them with `std:avm/events.watch_fs` / `watch_package`, and iOS SDK hosts enqueue them with `putVirtualEventWithKind:action:detail:flags:` without exposing file descriptors or package-store internals. | `make test-avm && make verify-libavm-ios` |
| AVM-COMPILERKIT-IOS | P2 | W3 | done | Added `OrenAVMCompilerKit`: host apps provide bundled `oren.obc` and `stdlib_bundle.obc`, then compile source through AVM VirtualFS/argv and receive output OBC plus compiler diagnostics without recreating the harness manually. | `make verify-compiler-in-avm-ios-chain && make verify-libavm-ios` |
| MATH-STDLIB-EXPAND | P2 | W3 | todo | Continue deterministic `std:math` expansion toward C/C++ mathlib breadth with native and AVM fixtures per function family. Current release-gated families include core predicates/rounding/fmod/remainder/remquo/modf/sign helpers, integer rounding aliases `lround`/`llround`/`lrint`/`llrint`, sign-bit `copysign`, NaN-aware `fabs`/`fmin`/`fmax`, tolerance predicates `isclose`/`isclose_abs`, finite `lerp`, range mapping helpers `inverse_lerp`/`remap`/`remap_clamped`, graphics scalar/interpolation helpers `sign`/`step`/`fract`/`clamp`/`saturate`/`smoothstep`/`smootherstep`, angle wrapping/interpolation helpers `wrap`/`wrap_degrees`/`wrap_radians`/`angle_delta_degrees`/`angle_delta_radians`/`lerp_angle_degrees`/`lerp_angle_radians`, pure `std:math/vec2` length/length_sq/length_squared/distance/distance_sq/distance_squared/dot/cross/normalize/normalize_or_zero/angle/rotate plus add/sub/scale/lerp/midpoint/isclose_abs/isclose/abs/sign/is_nan/isnan/is_inf/isinf/is_finite/isfinite/is_subnormal/is_normal/isnormal/fpclassify/isunordered/isgreater/isgreaterequal/isless/islessequal/islessgreater/signbit/copysign/fabs/fmin/fmax/fmod/remainder/remquo/sqrt/cbrt/powi/pow2i/ldexp/scalbn/scalbln/frexp/ilogb/logb/modf/fdim/nextafter/nexttoward/nextup/nextdown/pow/power/hypot/hypot3/erf/erfc/degrees/radians/wrap/wrap_degrees/wrap_radians/angle_delta_degrees/angle_delta_radians/lerp_angle_degrees/lerp_angle_radians/floor/ceil/round/round_even/nearbyint/rint/lround/llround/lrint/llrint/trunc/fract/saturate/step/smoothstep/smootherstep/inverse_lerp/remap/remap_clamped/exp/exp2/exp10/expm1/log/ln/log2/log10/log1p/sin/cos/tan/sin_cos/sincos/sinh/cosh/tanh/asinh/acosh/atanh/asin/acos/atan/atan2/min/max/clamp/project/reject/reflect/faceforward/refract/closest_point_on_segment/distance_to_segment helpers, pure `std:math/vec3` length/length_sq/length_squared/distance/distance_sq/distance_squared/dot/cross/normalize/normalize_or_zero/angle-between plus add/sub/scale/lerp/midpoint/isclose_abs/isclose/abs/sign/is_nan/isnan/is_inf/isinf/is_finite/isfinite/is_subnormal/is_normal/isnormal/fpclassify/isunordered/isgreater/isgreaterequal/isless/islessequal/islessgreater/signbit/copysign/fabs/fmin/fmax/fmod/remainder/remquo/sqrt/cbrt/powi/pow2i/ldexp/scalbn/scalbln/frexp/ilogb/logb/modf/fdim/nextafter/nexttoward/nextup/nextdown/pow/power/hypot/hypot3/erf/erfc/degrees/radians/wrap/wrap_degrees/wrap_radians/angle_delta_degrees/angle_delta_radians/lerp_angle_degrees/lerp_angle_radians/floor/ceil/round/round_even/nearbyint/rint/lround/llround/lrint/llrint/trunc/fract/saturate/step/smoothstep/smootherstep/inverse_lerp/remap/remap_clamped/exp/exp2/exp10/expm1/log/ln/log2/log10/log1p/sin/cos/tan/sin_cos/sincos/sinh/cosh/tanh/asinh/acosh/atanh/asin/acos/atan/atan2/min/max/clamp/project/reject/reflect/faceforward/refract/closest_point_on_segment/distance_to_segment helpers, pure `std:math/vec4` length/length_sq/length_squared/distance/distance_sq/distance_squared/dot/normalize/normalize_or_zero/angle-between plus add/sub/scale/lerp/midpoint/isclose_abs/isclose/abs/sign/is_nan/isnan/is_inf/isinf/is_finite/isfinite/is_subnormal/is_normal/isnormal/fpclassify/isunordered/isgreater/isgreaterequal/isless/islessequal/islessgreater/signbit/copysign/fabs/fmin/fmax/fmod/remainder/remquo/sqrt/cbrt/powi/pow2i/ldexp/scalbn/scalbln/frexp/ilogb/logb/modf/fdim/nextafter/nexttoward/nextup/nextdown/pow/power/hypot/hypot3/erf/erfc/degrees/radians/wrap/wrap_degrees/wrap_radians/angle_delta_degrees/angle_delta_radians/lerp_angle_degrees/lerp_angle_radians/floor/ceil/round/round_even/nearbyint/rint/lround/llround/lrint/llrint/trunc/fract/saturate/step/smoothstep/smootherstep/inverse_lerp/remap/remap_clamped/exp/exp2/exp10/expm1/log/ln/log2/log10/log1p/sin/cos/tan/sin_cos/sincos/sinh/cosh/tanh/asinh/acosh/atanh/asin/acos/atan/atan2/min/max/clamp/project/reject/reflect/faceforward/refract/closest_point_on_segment/distance_to_segment helpers, pure finite `std:math/quat` identity/length/length_sq/length_squared/normalize/normalize_or_identity/conjugate/dot/inverse/mul/multiply/from_axis_angle/axis_angle/rotate_vec3/rotate_vector/nlerp/slerp helpers, pure finite row-major `std:math/mat4` identity/translation/scale/rotation_x/rotation_y/rotation_z/from_axis_angle/rotation_axis/from_quat/from_quaternion rotation constructors, compose_trs/compose_transform TRS composition, ortho/orthographic/frustum/perspective projection, look-at/model-view-projection composition, mul/multiply, transpose/determinant/inverse, transform_point3/transform_point, transform_vec3/transform_vector, transform_normal3/transform_normal, project_point3/project_point, unproject_point3/unproject_point transforms plus normal-matrix extraction, plus overflow-aware `midpoint`, public ties-to-even rounding aliases, degree/radian angle conversion, normal/subnormal/`fpclassify` classification, component-wise ordered comparison predicates plus `signbit`/`copysign`, vector NaN-aware `fabs`/`fmin`/`fmax`, vector `fmod`/`remainder`/`remquo`, vector squared-length aliases, zero-normalize, vector `faceforward`/`refract`, vector segment projection/distance helpers, quaternion public aliases, ties-to-even and integer rounding aliases, `ilogb`/`logb`, `fdim`, `nextafter`/`nexttoward`/`nextup`/`nextdown`, pow/power, frexp/ldexp/scalbn decomposition and scaling, cbrt, scaled two- and three-argument hypotenuse, exp/log/ln/log2/log10/exp2/exp10 plus cancellation-aware expm1/log1p, hyperbolic sinh/cosh/tanh and inverse hyperbolic asinh/acosh/atanh, finite midpoint/isclose_abs/isclose/sqrt/cbrt/powi/pow2i/ldexp/scalbn/scalbln/frexp/ilogb/logb/modf/fdim/nextafter/nexttoward/nextup/nextdown/pow/power/hypot/hypot3/erf/erfc/degrees/radians/wrap/wrap_degrees/wrap_radians/angle_delta_degrees/angle_delta_radians/lerp_angle_degrees/lerp_angle_radians/exp/exp2/exp10/expm1/log/ln/log2/log10/log1p/sin/cos/tan/sin_cos/sincos/sinh/cosh/tanh/asinh/acosh/atanh/atan/atan2/asin/acos vector aliases for natural log and sincos, approximate real-valued erf/erfc, and a meaningful large-input Payne-Hanek trig vector at 2^40 now included in native quick; 2^53 periodicity is intentionally not asserted because `x + tau` rounds to `x + 6`, not `x + 2pi`. | focused math fixtures plus `make test-avm` |
| OREN-LSP-VSCODE | P2 | W3 | doing | Build a Go Oren language server plus VS Code extension for syntax highlighting, diagnostics, completion, navigation, and code intelligence. Current slices add a dependency-free `oren-lsp` JSON-RPC stdio server with `initialize`/`shutdown`, full-document sync, deterministic bracket/string diagnostics plus parser-backed diagnostics on open/change, clean close handling, keyword/local-symbol completion, direct imported-module alias completion, typed struct/class field completion after proven receivers, lexer-backed document symbols for imports, functions, variables, structs, and classes, same-file, opened-document cross-file, and import-resolved unopened-module definition navigation for relative and `std:` modules, lexer-backed hover and references over the same current/open/imported workspace graph, bounded transitive import traversal with cycle guards, scoped function-parameter definition/hover/reference navigation with nested shadowing, constructor-inferred same-file and direct-import-alias struct/class field definition/hover/reference navigation with direct variable-alias propagation, direct named factory-return inference including `return if/else` expression branches plus factory-return field-chain evidence, direct typed constructor/factory expression receiver field navigation/completion plus constructor-field and constructor-bound variable/member-path alias field-chain inference/completion, homogeneous list/hash indexed receiver evidence for field navigation and direct literal completions, list `for-in` loop element receiver evidence for field navigation/references, nested element field-chain completion/navigation, call-site parameter propagation, loop-element return inference, returned-list element field-chain inference, returned-map value field-chain inference, conditional returned-list/map field-chain inference, conditional assigned returned-container field-chain inference, imported returned-container and imported parameter-returned-container field-chain evidence, returned and imported parameter-returned nested list-of-map and map-of-list container field-chain inference, nested list-of-map and map-of-list indexed container field-chain inference, and indexed map value field-chain inference, recursive nested constructor-bound call-site parameter and parameter-return field-chain inference including imported identity-return call sites, source-brace scoped local/list-for-in receiver completions inside function blocks, consistent direct call-site parameter inference with conflict invalidation, direct parameter-return propagation, consistent conditional branch return and assignment inference, and unknown-assignment invalidation, conservative prepare/rename workspace edits for exact scoped parameters and same-document typed fields, a single-parse imported-document return-fact environment builder below the source-line guard, full-document semantic-token classification for declarations/references/literals/operators plus parser-derived parameter and property classes, plus a VS Code extension package with `.oren` language contribution, TextMate syntax grammar, language configuration, `vscode-languageclient` activation, and smoke verification; remaining work is richer member inference beyond direct constructor/alias/factory-expression/factory-return-field-chain/constructed-field/constructor-bound-alias-field-chain/call-site/parameter-return/recursive-nested-call-site/imported-call-site-return/imported-returned-container-field/imported-parameter-returned-container-field/conditional-branch/return-if/indexed-container/list-for-in/for-in-return/for-in-nested-field/returned-list-field/returned-map-value-field/conditional-returned-container-field/conditional-assigned-container-field/returned-nested-container-field/imported-parameter-returned-nested-container-field/nested-indexed-container-field/indexed-map-value-field/scoped-completion evidence. | `make verify-oren-lsp` |
| NATIVE-X64-ARCH-QI | P1 | W4 | done | Fixed the Linux x64 quick-integration failures on the dedicated Arch host `bruce@192.168.0.102`. Root causes were x64 unchecked list-int reduction intrinsics clobbering allocator-sensitive registers, x64 intrinsic tracked-node lookup ignoring arena nodes, and unsafe x64 LIST_INT sum/dot fast-loop matchers around safepoints. | Remote `tests/native/test_quick_integration_native.oren` x64-linux run on `bruce@192.168.0.102` exits `0` |
| NATIVE-X64-LIST-INT-FAST-SAFE | P1 | W3 | done | Restored x64 LIST_INT sum/dot loop fast paths with safepoint-safe state: the emitters now keep loop-local sum/cursor/value state in volatile registers, reload `idx`/`sum` after safepoints, and re-enable the matcher gate. | `OREN_TRACE_X64_LIST_FAST=1` x64-linux traces for commuted/temp/QI paths plus remote Arch execution exit `0` |
| NATIVE-X64-BOXED-DOT-FAST-SAFE | P1 | W3 | done | Rewrote and re-enabled the x64 boxed-list dot-product fast loop with the same safepoint-safe register contract as the typed `LIST_INT` dot path: loop-local state stays in volatile registers, `idx`/`sum` reload after safepoints, and allocator-sensitive `r12-r15` are avoided. | Remote Arch x64 boxed `dot_product` fast path exits `0` with `OREN_TRACE_X64_LIST_FAST=1` trace proof |
| LANG-ANON-IMPORT | P3 | W2 | todo | Add anonymous import syntax such as `import . "std:math"` after defining collision, visibility, import-cache, and fixture behavior. | parser/import/backend fixtures |

## Current Done Evidence

- Legacy native `oren_read_bytes` remains as an explicit compatibility ABI, but it now stats the file once, preallocates a native `LIST_INT` result to observed size, rejects oversized list output, and fills slots directly from 1 MiB read chunks instead of growing from a zero-capacity list through 4 KiB syscalls or per-byte list pushes.
- Legacy C runtime `oren_read_bytes` still returns the compatibility boxed byte list, but it now fills that list from bounded 64 KiB read chunks and avoids the former extra full-file temporary buffer; AVM host `oren_read_bytes` also fills its returned `LIST_INT` from bounded chunks without a full-file byte mirror; native, C runtime, and AVM host list-input `oren_write_bytes` compatibility paths validate before opening/truncating destinations and then write bounded chunks instead of allocating full-size byte mirrors; AVM host and VFS `write_bytes` now accept `LIST_INT` carriers from `read_bytes` directly, VFS list/list-int writes fill final VFS storage through a shared owned-data path instead of building a duplicate byte mirror, AVM byte/endian setters mutate optimized `LIST_INT` carriers through the shared byte write-span helper, and AVM `oren_string_from_bytes` accepts optimized `LIST_INT` byte carriers directly instead of requiring boxed-list reconstruction.
- AVM byte/string slice conversion now shares checked bytes/list/`LIST_INT` copy-span helpers for full-buffer string conversion, `oren_string_from_bytes_slice`, `oren_u8_buf_from_bytes_slice`, `bytes_pack`, and `bytes_unpack`, and the native and legacy C runtimes now route the same full-buffer string, slice, pack, and unpack family through shared byte-span helpers, keeping byte carriers on the optimized path without duplicated boxed-list copy loops. Native, legacy C runtime, and AVM `oren_sha256_range` now batch boxed-list/list-int inputs through bounded 64 KiB stack chunks or shared 64-byte copy-span block fills instead of calling the SHA update routine once per byte or rejecting optimized `LIST_INT` carriers.
- Native HTTP/2 header-only `END_STREAM` responses now return an exact empty `u8_buf` before allocating DATA accumulators, while content-length DATA bodies still use exact-capacity accumulation with mismatch checks.
- Native WebSocket masked client sends now write the header/mask prefix and stream payloads through fixed-size masked chunks instead of allocating full payload-sized frame buffers.
- Native WebSocket binary sends/receives now expose unfragmented opcode-2 payloads as validated byte-backed `u8_buf` values, while fragmented binary assembly and ping/pong/close control payloads use scratch/accumulator storage until the exact-size returned byte buffer is required; >4096-byte masked binary plus fragmented text/binary loopback fixtures guard the byte-native path.
- `std:buffer` raw `u8_pack_into` now validates the full input list before mutating the destination and writes valid bytes directly into `u8_buf` storage before falling back to compatibility stores.
- `std:buffer` raw `u8_copy_from_string*` now validates the public destination/string span once, then writes string bytes directly into `u8_buf` storage before falling back to compatibility stores for non-optimized carriers.
- `std:buffer` u8 matrix pack helpers now write validated row-list/string-row payloads directly into fresh dense `u8_buf` storage; strided u8 view copies from byte carriers, `u8_buf`, and strings now validate the source span once, then write directly into strided `u8_buf` storage before falling back to checked per-element view stores; strided `u8_buf` exports and non-dense u8 matrix exports now gather directly into exact-size `u8_buf` output before string conversion.
- `std:buffer` contiguous u8 slice and dense u8 matrix copies from `u8_buf`, string, flat-list, or row-list sources now route through shared byte-span copy/direct byte-write paths before falling back to checked per-element view stores for strided or non-u8 carriers.
- Metal text cache misses now share a bounded view-owned UIKit attribute cache keyed by packed RGBA, so repeated text colors do not rebuild font/color/attribute dictionaries while cache hits still return before touching UIKit attributes.
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
- Windows x64 `sys_cancel_io_ex` lowering now delegates spill-state setup,
  `CancelIoEx` call emission, and BOOL/`GetLastError` mapping to focused
  helpers while preserving `ERROR_NOT_FOUND` as idempotent success and keeping
  invalid-parameter/invalid-handle/default errno mappings. The capped profile
  now exposes `_emit_intrinsic_sys_create_io_completion_port_windows_x64`
  (~70ms) as the next parser-body target.
- Windows x64 IOCP create-port lowering now delegates state setup,
  `CreateIoCompletionPort` call emission, and handle result normalization to
  focused helpers, and create/post/cancel share one invalid-parameter /
  invalid-handle / default-EIO mapper. The capped profile now exposes
  `native_compile_program_x64` (~80ms) as the next parser-body target.
- `native_compile_program_x64` now delegates context/timing start,
  runtime/function metadata preparation, debug/entry/function/finalize body
  emission, and trace-summary reporting to focused helpers. The capped profile
  now exposes `_emit_eval_native_alloc_intrinsic_x64` (~69ms) as the next
  parser-body target.
- X64 native allocation intrinsic lowering now delegates expected arity,
  `malloc_k` kind preservation, reuse-mode selection, and allocation tracking
  emission to focused helpers while preserving `malloc_raw` as the explicit
  no-tracking path. The capped profile now exposes
  `_x64_fast_lcg_emit_unsigned_setup` (~117ms) as the next parser-body target.
- X64 fast LCG unsigned setup now delegates invariant register materialization,
  loop-state loads, and `i % mod_i` setup to separate helpers while preserving
  the unsigned-loop register contract. The capped profile now exposes
  `_x64_index_set_emit_recv_kind_dispatch` (~68ms) as the next parser-body target.
- X64 `oren_index_set` receiver-kind dispatch now delegates tracked-node guards,
  tracked node-kind loads, known list/list-int routing, and dynamic fallback
  routing to focused helpers while preserving existing panic strings and branch
  targets. The capped profile now exposes `_x64_match_fast_list_int_push_while`
  (~70ms) as the next parser-body target.
- X64 fast LIST_INT and generic LIST push-loop matching now share counted-loop
  recognition, optional constant-bound handling, push-body validation, duplicate
  list rejection, and pushed-value dependency guards. The capped profile now
  exposes `_x64_collect_ffi_ret_attrs` (~70ms) as the next parser-body target.
- X64 FFI return-attribute collection now delegates return-map initialization,
  attribute argument extraction, duplicate-kind detection, and return-kind
  marking to focused helpers while preserving existing `ffi_ret_*` context maps.
  The capped profile now exposes `_x64_wsasend_normalize_result` (~76ms) as the
  next parser-body target.
- Windows x64 overlapped WSA result normalization is now shared across
  `WSARecv`, `WSARecvFrom`, and `WSASend`, preserving the immediate-success,
  `WSA_IO_PENDING`, and WSA errno mapping contract with per-intrinsic label
  prefixes. The capped profile now exposes `_x64_emit_linux_stat_copy_to_oren_v0`
  (~101ms) as the next parser-body target.
- Linux x64 stat-result normalization now delegates rc gating, low-register
  base setup, deterministic OrenStatV0 zeroing, size/mode copying, and
  sec+nsec timestamp packing to focused helpers while preserving all Linux
  `struct stat` and OrenStatV0 offsets. The capped profile now exposes
  `_x64_rtobj_encode_fixups_compact` (~73ms) as the next parser-body target.
- X64 runtime-object compact fixup encoding now uses explicit bucket state,
  per-fixup routing, and result materialization helpers while preserving the
  persisted compact metadata keys consumed by runtime-object replay. The capped
  profile now exposes `_x64_index_emit_list_path` (~67ms) as the next parser-body
  target.
- X64 list index lowering now splits checked list gets into focused magic,
  bounds, buffer, and element-load helpers, and the assume-list fast path shares
  the same buffer/value load emission. The capped profile now exposes
  `_emit_intrinsic_sys_close_windows_x64` (~67ms) as the next parser-body target.
- Windows x64 `sys_close` lowering now delegates fd spill/eval, capsule
  pre/post hooks, socket close attempt, handle fallback, and result mapping to
  focused helpers while preserving the socket-then-`CloseHandle` contract. The
  capped profile now exposes `_emit_stack_trace_linux_best_effort` (~65ms) as
  the next parser-body target.
- X64 best-effort stack tracing now shares frame guards, return-PC loading, and
  monotonic frame advance across Linux and Windows; Linux stack trace output is
  split into focused PC prefix, symbol, location, and offset-line emitters. The
  capped profile now exposes `_x64_emit_entry_register_thread_call` (~72ms) as
  the next parser-body target.
- X64 entry-thread registration now delegates active/skip routing, ABI stack
  argument setup, `oren_register_thread` fixup emission, Windows RSP drift
  diagnostics, and phase logging to focused helpers. The capped profile now
  exposes `_emit_intrinsic_sys_connect_windows_x64` (~67ms) as the next
  parser-body target.
- Windows x64 `sys_connect` lowering now delegates argument spill state,
  capsule prehook, `connect` dispatch, connect-specific WSA errno mapping, and
  capsule posthook emission to focused helpers while preserving nonblocking
  `WSAEWOULDBLOCK` to `-EINPROGRESS` normalization. The capped profile now
  exposes `_x64_emit_cmp_string_path` (~67ms) as the next parser-body target.
- X64 string-aware compare lowering now separates inline string-compare label
  creation, cursor setup, byte-loop emission, and normalized -1/0/+1 return
  emission while preserving caller-owned local fixup patching. The capped
  profile now exposes `_emit_intrinsic_sys_bind_windows_x64` (~73ms) as the
  next parser-body target.
- Windows x64 `sys_connect` / `sys_bind` lowering now shares fd/sockaddr/addrlen
  spill state, argument reload, capsule pre/post hook dispatch, IAT calls, and
  SOCKET_ERROR result normalization while keeping connect's nonblocking errno
  mapper explicit. The capped profile now exposes
  `_x64_fast_list_int_dot_emit_whole_helper` (~73ms) as the next parser-body
  target.
- X64 fast LIST_INT dot lowering now shares list-name lookup and temp-slot
  derivation between whole-list helper and per-step paths, and splits the
  whole-list helper into count guards, unchecked runtime call, and result
  writeback. The capped profile now exposes `_x64_expr_needs_literal_slots`
  (~67ms) as the next parser-body target.
- X64 literal-slot frame analysis now splits expression argument scanning,
  call/spawn walking, binary/index walking, and if-expression branch walking
  into focused helpers while preserving conservative unknown-shape allocation.
  The capped profile now exposes `_x64_prepare_runtime_global_slots` (~99ms)
  as the next parser-body target.
- X64 runtime-global slot preparation now separates GC-root env flag parsing,
  runtime-name collection, per-global zero-slot allocation/root bookkeeping,
  and phase logging while preserving the `g_storage` bootstrap exception. The
  capped profile now exposes `_data_finalize_symtab` (~67ms) as the next
  parser-body target.
- X64 symbol-table finalization now separates reserved-table decoding, entry
  offset/display-name collection, deterministic descending sort, and reserved
  region patching while preserving `__entry_stub__` offset-zero encoding. The
  capped profile now exposes `_x64_emit_top_string_global_batch_loop` (~71ms)
  as the next parser-body target.
- X64 top-level string global batch loop emission now separates data-base/table
  pointer setup, count setup, loop header/body emission, and local jump patching
  while preserving the fixed `.data` table layout. The capped profile now exposes
  `_emit_intrinsic_oren_call_obj_list_x64` (~66ms) as the next parser-body
  target.
- X64 callable-object list invocation now shares ABI register setup,
  nil-callee guarding, environment loading, and code-pointer call emission
  between the explicit `oren_call_obj_list` intrinsic and indirect function-value
  calls. The capped profile now exposes `_emit_intrinsic_sys_linux_open_x64`
  (~65ms) as the next parser-body target.
- Linux x64 `sys_open` lowering now mirrors the helper shape used by adjacent
  filesystem intrinsics: spill/eval state, capsule prehook, `openat` syscall
  setup, and capsule posthook are separate helpers while preserving flag
  translation. The capped profile now exposes `_x64_emit_sys_rename_x64`
  (~64ms) as the next parser-body target.
- Linux x64 `sys_rename` lowering now uses the same state/prehook/syscall/posthook
  decomposition as the rest of the path-family emitters while preserving the
  capsule bundle layout for from/to path rewrites. The capped profile now exposes
  `_emit_eval_mod_infix_to_rax` (~64ms) as the next parser-body target.
- X64 `%` infix lowering now separates the safe constant-RHS `idiv` fast path
  from runtime `oren_mod` argument spilling and ABI call emission, preserving
  deterministic modulo semantics for non-constant divisors. The capped profile
  now exposes `_x64_wsasend_spill_state` (~88ms) as the next parser-body target.
- Windows x64 overlapped WSA message lowering now shares the common six-argument
  spill state and WSABUF temp-slot setup across `WSARecv`, `WSARecvFrom`, and
  `WSASend`; `WSARecvFrom` layers only its sockaddr slots on top. The capped
  profile now exposes `_emit_intrinsic_sys_qpc_frequency_windows_x64` (~63ms) as
  the next parser-body target.
- Windows x64 `sys_qpc_frequency` lowering now delegates frequency-pointer
  spill state, null-pointer guard, `QueryPerformanceFrequency` IAT dispatch,
  and BOOL-to-errno result mapping to focused helpers. The capped profile now
  exposes `_x64_gqcsx_spill_state` (~94ms) as the next parser-body target.
- Windows x64 `GetQueuedCompletionStatusEx` lowering now separates temp-state
  allocation/validation from six-argument spill emission while preserving the
  Win64 stack-argument layout for timeout and alertable. The capped profile now
  exposes `_x64_win_cp_emit_wait` (~63ms) as the next parser-body target.
- Windows x64 `sys_win_createprocess` wait lowering now delegates timeout-mode
  dispatch, infinite wait, poll wait, timeout return, and shared Win32 wait-error
  mapping to focused helpers while preserving deterministic timeout-budget
  polling. The capped profile now exposes `_emit_float64_binop_x64` (~63ms) as
  the next parser-body target.
- X64 float64 arithmetic lowering now shares operand spill and XMM materialization
  with float comparison lowering, leaving `_emit_float64_binop_x64` as a thin
  arithmetic-dispatch/result-pack wrapper. The capped profile now exposes
  `_x64_emit_top_empty_container_batch_loop` (~78ms) as the next parser-body
  target.
- X64 top-level empty-container batch lowering now mirrors the string batch
  pipeline with separate runtime-symbol, ABI-argument, table setup, loop header,
  loop body, and patch helpers. The capped profile now exposes
  `_emit_intrinsic_sys_socket_windows_x64` (~67ms) as the next parser-body target.
- Windows x64 `sys_socket` lowering now delegates argument spill state, capsule
  prehook, `socket` IAT dispatch, `INVALID_SOCKET` result mapping, and capsule
  posthook to focused helpers. The capped profile now exposes
  `_x64_emit_windows_dll_return_path` (~90ms) as the next parser-body target.
- Windows x64 DLL entry return lowering now delegates TRUE epilogue emission,
  Win64 nonvolatile restore, DLL attach-gate fixup patching, and shared
  return-path finalization to focused helpers. The capped profile now exposes
  `_emit_intrinsic_sys_accept_windows_x64` (~62ms) as the next parser-body target.
- Windows x64 accept/getname fd-sockaddr lowering now reuses the shared
  three-argument sockaddr helper path, with accept-specific invalid-socket
  mapping and new-fd posthook emission isolated in focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~42.6s total / ~31.3s parse,
  with `_emit_gc_collect_visible_call_x64` (~63ms) as the next parser-body
  target.
- X64 GC-visible call lowering now emits register spill surfaces through shared
  push/pop helpers with cached surface metadata, preserving the safepoint and
  explicit-collect register contracts while avoiding repeated compile-time list
  allocation. The capped profile now shows `x64_native_program.oren` at ~42.7s
  total / ~31.2s parse, with `_x64_rtobj_print_build_summary` (~63ms) as the
  next parser-body target.
- X64 runtime-object build summary tracing now splits timing delta capture,
  build-count capture, and final log-line assembly into focused helpers while
  preserving the existing summary field order. The capped profile now shows
  `x64_native_program.oren` at ~42.4s total / ~30.9s parse, with
  `_emit_intrinsic_sys_windows_core_x64` (~61ms) as the next parser-body target.
- Windows x64 core intrinsic dispatch now routes shared-memory, read/write,
  filesystem, process-basics, and time/sync/random syscall families through
  focused helper routers while preserving dispatch order. The capped profile now
  shows `x64_native_program.oren` at ~43.9s total / ~32.2s parse, with
  `_emit_intrinsic_sys_select_windows_x64` (~63ms) as the next parser-body target.
- Windows x64 `sys_select` lowering now splits temp-state capture, Win64 arg5
  call setup, and SOCKET_ERROR-to-errno normalization into focused helpers while
  preserving the existing WinSock select ABI path. The capped profile now shows
  `x64_native_program.oren` at ~43.1s total / ~31.6s parse, with
  `_x64_prepare_user_global_slots` (~63ms) as the next parser-body target.
- X64 user-global slot preparation now uses an explicit prep-state object plus
  separate loop, path-accounting, and done-log helpers while preserving direct
  data init and runtime-zero slot behavior. The capped profile now shows
  `x64_native_program.oren` at ~42.7s total / ~31.3s parse, with
  `_x64_emit_list_int_push_validate` (~61ms) as the next parser-body target.
- X64 LIST_INT push validation now splits nil, tracked-node lookup, node-kind,
  and list-magic guards into focused helpers while preserving diagnostic footer
  calls. The capped profile now shows `x64_native_program.oren` at ~42.4s total
  / ~30.9s parse, with `_emit_eval_float_bits_call_intrinsic_x64` (~60ms) as the
  next parser-body target.
- X64 float-bit scalar intrinsics now share unary validation and split f64-to-f32,
  f32-to-f64, and identity bitcast emission while preserving handled-name routing.
  The capped profile now shows `x64_native_program.oren` at ~42.5s total /
  ~31.1s parse, with `_x64_emit_ffi_resolver_win64` (~60ms) as the next
  parser-body target.
- Windows x64 FFI resolver emission now separates function registration,
  callee-saved/shadow-space prologue, per-DLL LoadLibrary/GetProcAddress attempts,
  and epilogue emission while preserving the `__oren_ffi_resolve0` ABI. The capped
  profile now shows `x64_native_program.oren` at ~43.4s total / ~31.8s parse, with
  `_data_add_cstr0_cached` (~90ms) as the next parser-body target.
- X64 cached cstr0 data emission now splits MRU state setup, byte-equality lookup,
  and ring-buffer store helpers while preserving valid offset `0` handling with
  an explicit `-1` miss sentinel. The capped profile now shows
  `x64_native_program.oren` at ~45.1s total / ~33.1s parse, with
  `_emit_intrinsic_sys_ulock_wait_linux_x64` (~119ms) as the next parser-body target.
- Linux x64 `sys_ulock_wait` now delegates futex wait temp-state setup, argument
  spilling, futex argument emission, and timeout/result normalization to focused
  helpers while preserving the `FUTEX_WAIT_PRIVATE` ABI path. The capped profile
  now shows `x64_native_program.oren` at ~45.4s total / ~33.8s parse, with
  `_x64_emit_entry_debug_info` (~66ms) as the next parser-body target.
- X64 entry debug-info registration now delegates slot-offset decoding, static
  address reconstruction, ABI argument setup, runtime call emission, and phase
  logging to focused helpers while preserving the optional null-slot skip. The
  capped profile now shows `x64_native_program.oren` at ~45.4s total / ~33.7s
  parse, with `_emit_sys_open_windows_creation_stack_args_x64` (~65ms) as the
  next parser-body target.
- Windows x64 `sys_open` stack-argument lowering now delegates flag tests,
  CREAT/TRUNC disposition branches, and immediate Win64 stack-arg stores to
  focused helpers while preserving the `CreateFileA` argument layout. The capped
  profile now shows `x64_native_program.oren` at ~44.6s total / ~32.9s parse,
  with `_emit_intrinsic_sys_linux_epoll_pwait_x64` (~62ms) as the next
  parser-body target.
- Linux x64 `sys_epoll_pwait` lowering now delegates six-argument temp-state
  setup, argument spilling, capsule prehook register loading, and syscall
  dispatch to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~44.0s total / ~32.4s parse, with
  `_emit_translate_open_flags_linux_x64` (~62ms) as the next parser-body target.
- Linux x64 open-flag translation now delegates access-bit initialization and
  each optional Oren-to-Linux flag OR to focused helpers while preserving the
  stable Oren flag ABI. The capped profile now shows `x64_native_program.oren`
  at ~44.7s total / ~33.1s parse, with `_emit_intrinsic_sys_linux_fcntl_getfl_x64`
  (~96ms) as the next parser-body target.
- Linux x64 `sys_fcntl_getfl` lowering now delegates fd temp-state setup,
  F_GETFL argument loading, capsule pre/post hooks, syscall dispatch, and Oren
  flag normalization to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~44.7s total / ~32.7s parse, with
  `_x64_emit_sys_unlink_or_rmdir_x64` (~63ms) as the next parser-body target.
- Linux x64 `sys_unlink` / `sys_rmdir` lowering now delegates temp-state setup,
  capsule path resolution, `unlinkat` flag/syscall emission, and capsule
  posthook handling to focused helpers while preserving `AT_REMOVEDIR`
  selection. The capped profile now shows `x64_native_program.oren` at ~44.1s
  total / ~32.3s parse, with `_emit_intrinsic_sys_linux_net_fd2_x64` (~60ms) as
  the next parser-body target.
- Linux x64 `sys_listen` / `sys_shutdown` lowering now shares fd/argument
  spill state, capsule prehook dispatch, syscall-number selection, and listen
  posthook emission through focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~43.2s total / ~31.4s parse, with
  `_emit_intrinsic_sys_listen_windows_x64` (~58ms) as the next parser-body
  target.
- Windows x64 `sys_listen` / `sys_shutdown` lowering now shares fd/argument
  spill state, Win64 argument loads, IAT dispatch, and SOCKET_ERROR
  normalization helpers, with listen posthook emission kept as the only
  listen-specific tail. The capped profile now shows `x64_native_program.oren`
  at ~42.9s total / ~31.3s parse, with `_emit_intrinsic_sys_linux_dup23_x64`
  (~58ms) as the next parser-body target.
- Linux x64 `sys_dup2` / `sys_dup3` lowering now delegates arity selection,
  temp-slot state, fd-pair reloads, optional flags reload, syscall selection,
  and capsule pre/post hooks to focused helpers. The capped profile now shows
  `x64_native_program.oren` at ~43.1s total / ~31.5s parse, with
  `_x64_fast_list_push_emit_loop` (~58ms) as the next parser-body target.
- X64 fast LIST and LIST_INT push-loop emission now share per-push list lookup,
  temp-slot derivation, value lowering, and buffer store emission helpers while
  keeping typed/generic validation separate. The capped profile now shows
  `x64_native_program.oren` at ~43.5s total / ~31.8s parse, with
  `_x64_emit_sys_fstat_x64` (~58ms) as the next parser-body target.
- Linux x64 `sys_fstat` lowering now delegates host-stat temp layout, fd
  prehook/capture, stat-pointer spilling, syscall setup, and capsule posthook
  emission to focused helpers while preserving the 37-qword spill gap. The
  capped profile now shows `x64_native_program.oren` at ~43.9s total / ~32.1s
  parse, with `_x64_user_function_loop_options` (~60ms) as the next parser-body
  target.
- X64 user-function loop option normalization now shares nil/default option
  reads and mirrors compile-option grouping with progress, slow-function, and
  phase-detail helper packers. The capped profile now shows
  `x64_native_program.oren` at ~43.2s total / ~31.6s parse, with
  `_x64_emit_sys_getdirentries64_x64` (~57ms) as the next parser-body target.
- Linux x64 `sys_getdirentries64` lowering now delegates temp-slot setup, fd
  prehook/capture, buffer/size/ignored-position evaluation, `getdents64`
  syscall setup, and capsule posthook emission to focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~43.5s total / ~31.7s parse,
  with `_x64_emit_program_entry_sequence` (~59ms) as the next parser-body target.
- X64 program-entry sequence emission now delegates prologue/bootstrap/root state,
  entry-option packing, register/top/main/return emission, and done logging to
  focused helpers while preserving DLL/SO entry metadata. The capped profile now
  shows `x64_native_program.oren` at ~43.7s total / ~31.8s parse, with
  `_emit_ops_in_fn` (~58ms) as the next parser-body target.
- `_emit_ops_in_fn` now delegates one-op iteration orchestration to a focused
  helper while preserving reserve-skip, tracing, gas patching, prebuilt batch,
  regular-op, and slow-op accounting semantics. The capped profile now shows
  `x64_native_program.oren` at ~45.2s total / ~33.3s parse, with
  `_x64_emit_getentropy_windows_resolve_fp` (~61ms) as the next parser-body target.
- Windows x64 `sys_getentropy` function-pointer resolution now delegates cached
  pointer probing, `LoadLibraryA`, `GetProcAddress`, and cache-store emission to
  focused helpers while preserving the cached `r11` contract. The capped profile
  now shows `x64_native_program.oren` at ~44.3s total / ~32.6s parse, with
  `_x64_emit_function_body_ops` (~61ms) as the next parser-body target.
- X64 function-body op emission now delegates trace-env parsing, phase-log
  begin/end wiring, and `_emit_ops_in_fn` payload emission to focused helpers
  while preserving emit-ops trace cleanup. The capped profile now shows
  `x64_native_program.oren` at ~44.3s total / ~32.7s parse, with
  `_emit_fast_list_dot_while_x64` (~60ms) as the next parser-body target.
- X64 fast LIST dot-product while lowering now delegates generic fallback,
  loop-body finish, and slow-path emission to focused helpers while preserving
  validation cleanup and cursor contracts. The capped profile now shows
  `x64_native_program.oren` at ~44.3s total / ~32.6s parse, with
  `_x64_print_program_compile_summary` (~59ms) as the next parser-body target.
- X64 compile-summary emission now lives in a bounded program-entry helper
  fragment with separate platform, timing, count, and line-format helpers while
  keeping `090_tail.oren` under the source line ceiling. The capped profile now
  shows `x64_native_program.oren` at ~43.4s total / ~31.8s parse, with
  `_x64_fast_list_get_sum_emit_dynamic_add` (~60ms) as the next parser-body
  target.
- X64 fast LIST get-sum dynamic addition now delegates label allocation,
  string-entry gating, string-pointer checks, concat dispatch, and integer-add
  fallback to focused helpers while preserving register argument setup. The
  capped profile now shows `x64_native_program.oren` at ~45.0s total / ~33.0s
  parse, with `_x64_fast_lcg_prepare` (~62ms) as the next parser-body target.
- X64 fast LCG prepare now delegates input extraction, fastmod reciprocal
  setup, local-offset validation, temp-slot allocation, and prep-map packing
  to focused helpers while preserving downstream prep keys. The capped profile
  now shows `x64_native_program.oren` at ~44.2s total / ~32.4s parse, with
  `_x64_string_batch_append_table_and_emit` (~61ms) as the next parser-body
  target.
- X64 top string-batch table/emit finalization now separates data-done tracing,
  table serialization, table-done tracing, and top-loop code emission while
  preserving batch timing/result keys. The capped profile now shows
  `x64_native_program.oren` at ~43.5s total / ~31.6s parse, with
  `_x64_emit_named_call_intrinsic_or_spread_v0` (~56ms) as the next parser-body
  target.
- X64 named-call intrinsic/spread routing now separates statement-only
  rejection, core intrinsic dispatch, `oren_call_obj_list`, and spread-call
  lowering while preserving dispatch order. The capped profile now shows
  `x64_native_program.oren` at ~43.3s total / ~31.6s parse, with
  `_x64_rtobj_finalize_build` (~56ms) as the next parser-body target.
- X64 runtime-object build finalization now separates blob materialization,
  persisted metadata assembly, finalize-done logging, and result packing while
  preserving the rtobj metadata schema keys. The capped profile now shows
  `x64_native_program.oren` at ~44.4s total / ~32.5s parse, with
  `_emit_format_plus0x_u64_hex_line` (~57ms) as the next parser-body target.
- X64 panic stack-trace hex formatting now shares ASCII byte stores and the
  fixed-width 16-digit hex emission between `0x... ` PC prefixes and
  `+0x...\n` offsets. The capped profile now shows `x64_native_program.oren`
  at ~43.4s total / ~31.7s parse, with `_x64_emit_list_push_validate` (~54ms)
  as the next parser-body target.
- X64 generic LIST push validation now matches the LIST_INT push structure with
  separate nil, tracked-lookup, node, kind, and magic guards while preserving
  the list push register reload contract. The capped profile now shows
  `x64_native_program.oren` at ~43.4s total / ~31.7s parse, with
  `_x64_emit_list_int_get_validate_list` (~54ms) as the next parser-body target.
- X64 LIST_INT get validation now separates list reload, operand reload, nil,
  tracked-lookup, node, kind, and magic guards while preserving the bounds/load
  phases. The capped profile now shows `x64_native_program.oren` at ~45.2s
  total / ~33.1s parse, with `_x64_emit_function_frame_header` (~101ms) as the
  next parser-body target.
- X64 function frame-header emission now separates phase-state capture, locals
  logging, trace printing, frame diagnostics, stack allocation, and frame-done
  logging while preserving frame-size emission. The capped profile now shows
  `x64_native_program.oren` at ~45.0s total / ~33.0s parse, with
  `_x64_fast_list_int_push_prepare` (~57ms) as the next parser-body target.
- X64 fast LIST/LIST_INT push-loop preparation now shares ABI register lookup,
  loop input extraction, local-offset validation, temp-slot allocation, and
  prep-map packing, with LIST_INT layering only reserve tracing. The capped
  profile now shows `x64_native_program.oren` at ~44.4s total / ~32.6s parse,
  with `_x64_emit_ops_loop_state` (~56ms) as the next parser-body target.
- X64 emit-ops loop-state assembly now separates op-count, trace cadence,
  phase logging, slow-op tracing, and gas-mode flag setup while preserving the
  state map consumed by the emit loop. The capped profile now shows
  `x64_native_program.oren` at ~43.9s total / ~31.9s parse, with
  `_emit_eval_bitwise_infix_to_rax` (~54ms) as the next parser-body target.
- X64 bitwise and arithmetic integer infix lowering now share constant,
  identifier, and general-expression RHS emission, with small operation
  dispatch helpers preserving the existing immediate and register x64 forms.
  The capped profile now shows `x64_native_program.oren` at ~43.9s total /
  ~31.9s parse, with `_emit_list_int_len_unchecked_intrinsic_v0_x64` (~54ms)
  as the next parser-body target.
- X64 unchecked LIST_INT length lowering now separates argument validation,
  list spill/reload, label setup, nil-to-zero branching, and raw count loading
  while preserving the unchecked nil contract. The capped profile now shows
  `x64_native_program.oren` at ~45.3s total / ~33.0s parse, with
  `_x64_emit_regular_straightline_op` (~59ms) as the next parser-body target.
- X64 straight-line regular-op dispatch now routes declaration/global-init,
  value/expression, print, and return op families through focused helpers while
  preserving `nil`/`0`/`1` handled-status semantics. The capped profile now shows
  `x64_native_program.oren` at ~43.8s total / ~31.9s parse, with
  `_x64_collect_ffi_decls_from_stmt_list` (~54ms) as the next parser-body target.
- X64 FFI declaration collection now separates import-map setup, declaration
  name validation, registration/link-name persistence, and per-statement routing
  while preserving duplicate checks and FFI attr collection order. The capped
  profile now shows `x64_native_program.oren` at ~44.4s total / ~32.3s parse,
  with `_x64_prepare_simd_dot_i32_ptr` (~101ms) as the next parser-body target.
- X64 SIMD dot-i32 pointer preparation now separates arg validation,
  three-slot allocation, per-argument LTR evaluation/spilling, and final state
  packing while preserving the vector/scalar emitter state map. The capped
  profile now shows `x64_native_program.oren` at ~44.9s total / ~32.9s parse,
  with `_x64_expr_uses_ident` (~56ms) as the next parser-body target.
- X64 expression identifier-use scanning now separates list, hash, pair, and
  call recursion helpers while preserving conservative unknown-shape dependency
  behavior for fast-loop matching. The capped profile now shows
  `x64_native_program.oren` at ~44.5s total / ~32.4s parse, with
  `_x64_fast_lcg_emit_unsigned_step` (~54ms) as the next parser-body target.
- X64 fast LCG unsigned-step emission now separates x update, `x % mod`,
  `x % mod_x`, sum folding, and `i_mod` wrap helpers while preserving the
  unsigned-loop register contract. The capped profile now shows
  `x64_native_program.oren` at ~44.4s total / ~32.4s parse, with
  `_data_add_cstr0` (~84ms) as the next parser-body target.
- X64 cstr0 data emission now separates state initialization, invalid-argument
  diagnostics, dedup lookup, safety capping, raw byte append, and unique-offset
  recording while preserving offset-0 and truncated-string dedup semantics. The
  capped profile now shows `x64_native_program.oren` at ~44.6s total / ~32.5s
  parse, with `_emit_array_literal_expr` (~54ms) as the next parser-body target.
- X64 array literal lowering now separates element extraction, bounded tracing,
  unchecked push-call emission, and LTR element-loop emission while preserving
  the list allocation and return reload sequence. The capped profile now shows
  `x64_native_program.oren` at ~44.3s total / ~32.3s parse, with
  `_x64_emit_getentropy_windows_guards` (~63ms) as the next parser-body target.
- Windows x64 `sys_getentropy` guard emission now separates shared i32
  return-and-jump materialization, non-positive length fast return, and null
  buffer EFAULT checks while preserving local label/fixup routing. The capped
  profile now shows `x64_native_program.oren` at ~43.7s total / ~31.6s parse,
  with `_emit_panic_with_msg_ptr` (~52ms) as the next parser-body target.
- X64 panic message emission now separates callee-saved message preservation,
  Windows literal/dynamic diagnostic writes, Linux diagnostic writes, debug-stack
  gating, and platform abort finalization while preserving the emitted
  `OREN_DIAG` line sequence. The capped profile now shows
  `x64_native_program.oren` at ~44.0s total / ~31.9s parse, with
  `_emit_index_set_intrinsic_v0_x64` (~52ms) as the next parser-body target.
- X64 `oren_index_set` intrinsic lowering now separates validation, map-only
  dispatch, generic runtime fallback, and inline list/list-int state creation
  while preserving the existing spill and temp cleanup order. The capped profile
  now shows `x64_native_program.oren` at ~44.2s total / ~32.2s parse, with
  `_x64_rtobj_apply_imports_and_ffi` (~54ms) as the next parser-body target.
- X64 runtime-object import/FFI metadata application now separates import-list
  merging, single FFI link-name conflict handling, FFI link-name map iteration,
  and the top-level imports/FFI orchestration while preserving phase logging and
  conflict diagnostics. The capped profile now shows `x64_native_program.oren`
  at ~43.9s total / ~31.9s parse, with
  `_x64_windows_fstat_emit_handle_resolution` (~53ms) as the next parser-body
  target.
- Windows x64 `sys_fstat` handle resolution now shares std-fd `GetStdHandle`
  case emission and isolates handle validation while preserving stdin/stdout/
  stderr mapping and direct-handle fallback. The capped profile now shows
  `x64_native_program.oren` at ~45.4s total / ~33.1s parse, with
  `_x64_emit_list_int_set_validate` (~54ms) as the next parser-body target.
- X64 LIST_INT set validation now separates nil, tracked-node lookup, node,
  kind, and magic guards while preserving the LTR spill/reload contract. The
  capped profile now shows `x64_native_program.oren` at ~48.6s total / ~36.1s
  parse, with `_emit_index_expr_v0` (~123ms) as the next parser-body target.
- X64 index expression lowering now separates dynamic label state, nil-container
  guard emission, optional assume-list fast-path emission, and dynamic list/map
  path emission while preserving temp cleanup and patch order. The capped profile
  now shows `x64_native_program.oren` at ~45.0s total / ~32.8s parse, with
  `_x64_finalize_program_data` (~54ms) as the next parser-body target.
- X64 program-data finalization now separates debug lambda diagnostics, per-table
  finalizer/phase logging, and final codegen summary logging while preserving
  finalizer order and error stop points. The capped profile now shows
  `x64_native_program.oren` at ~46.8s total / ~34.6s parse, with
  `_emit_intrinsic_sys_linux_net_accept_x64` (~55ms) as the next parser-body
  target.
- Linux x64 `sys_accept` lowering now separates temp-state setup, shared
  fd/sockaddr/len argument loading, capsule prehook, syscall dispatch, and
  capsule posthook while preserving the accept syscall ABI. The capped profile
  now shows `x64_native_program.oren` at ~43.7s total / ~31.8s parse, with
  `_emit_intrinsic_sys_linux_fcntl_setfl_x64` (~52ms) as the next parser-body
  target.
- Linux x64 `sys_fcntl_setfl` lowering now separates temp-state setup, shared
  translated `F_SETFL` argument loading, capsule prehook, syscall dispatch, and
  capsule posthook while preserving Oren-to-Linux flag translation. The capped
  profile now shows `x64_native_program.oren` at ~63.3s total / ~46.1s parse,
  with `_x64_trace_global_slots` (~80ms) as the next parser-body target.
- X64 global-slot tracing now separates env enablement, filter parsing, header
  emission, per-entry match checks, and row emission while preserving the
  `OREN_TRACE_GLOBAL_SLOTS` output and name/off/index filters. The capped
  profile now shows `x64_native_program.oren` at ~62.3s total / ~45.1s parse,
  with `_x64_emit_simd_dot_i32_ptr_vector_loop` (~73ms) as the next parser-body
  target.
- X64 SIMD dot-i32 pointer vector-loop emission now separates vector setup,
  loop-body emission, jump patching, and horizontal sum extraction while
  preserving the SSE2 register contract and patch offsets. The capped profile
  now shows `x64_native_program.oren` at ~62.3s total / ~45.1s parse, with
  `_emit_intrinsic_sys_linux_net_socket_x64` (~73ms) as the next parser-body
  target.
- Linux x64 `sys_socket` lowering now separates temp-state setup, shared
  argument reloads, capsule prehook, syscall dispatch, and capsule posthook
  while preserving the socket syscall and capsule ABIs. The capped profile now
  shows `x64_native_program.oren` at ~62.7s total / ~45.4s parse, with
  `_emit_fast_list_int_push_while_x64` (~73ms) as the next parser-body target.
- X64 fast LIST_INT push-while lowering now separates cleanup/fallback handling
  and checked fast-path emission from the top-level slow-path label orchestration
  while preserving temp cleanup and generic fallback behavior. The capped profile
  now shows `x64_native_program.oren` at ~63.4s total / ~46.1s parse, with
  `_emit_intrinsic_sys_win_terminate_thread_windows_x64` (~101ms) as the next
  parser-body target.
- Windows x64 `sys_win_terminate_thread` lowering now separates temp-state
  setup, Win64 argument loading/IAT dispatch, and BOOL-to-`-1/0` result mapping
  while preserving the reserved call-area contract. The capped profile now shows
  `x64_native_program.oren` at ~64.7s total / ~47.2s parse, with
  `_x64_prepare_sys_write_windows_args` (~106ms) as the next parser-body target.
- Windows x64 `sys_write` argument preparation now separates temp-slot
  allocation, fd capsule prehook capture, and buffer/length spilling while
  preserving the `WriteFile` state map. The capped profile now shows
  `x64_native_program.oren` at ~63.9s total / ~46.4s parse, with
  `_emit_fast_list_push_while_x64` (~74ms) as the next parser-body target.
- X64 fast LIST push-while lowering now uses the same cleanup/fallback and
  checked-fast-path helper split as LIST_INT push while preserving slow-path
  label wiring and temp cleanup. The capped profile now shows
  `x64_native_program.oren` at ~64.5s total / ~47.0s parse, with
  `_emit_for_op_x64` (~75ms) as the next parser-body target.
- X64 for-loop lowering now separates label allocation, init emission,
  condition/gas/safepoint emission, body emission, and post/jump finalization
  while preserving continue-to-post and break-to-end semantics. The capped
  profile now shows `x64_native_program.oren` at ~63.3s total / ~46.1s parse,
  with `_emit_fast_list_dot_while_x64` (~80ms) as the next parser-body target.
- X64 fast LIST dot-product entry lowering now separates fast-path preparation
  from checked emission/fallback routing while preserving generic fallback
  behavior for nil locals, missing runtime injection, failed prep, and checked
  fallback. The capped profile now shows `x64_native_program.oren` at ~65.0s
  total / ~47.7s parse, with `_emit_intrinsic_sys_linux_ioctl_x64` (~157ms) as
  the next parser-body target.
- Linux x64 `sys_ioctl` lowering now separates temp-state capture, shared
  fd/request/argp argument loading, capsule prehook emission, and syscall
  dispatch while preserving the ioctl register ABI. The capped profile now
  shows `x64_native_program.oren` at ~63.7s total / ~46.2s parse, with
  `_x64_is_list_int_get_call` (~73ms) as the next parser-body target.
- X64 fast LIST/LIST_INT get matcher recognition now shares indexed-form,
  callee-name, argument, and accepted-name helpers while preserving LIST_INT's
  `recv_kind` guard and both call-name allowlists. The capped profile now
  shows `x64_native_program.oren` at ~66.6s total / ~49.0s parse, with
  `_x64_emit_resolve_symbol_scan_loop` (~115ms) as the next parser-body target.
- X64 panic symbol/location table scans now share loop entry, miss-advance,
  match-label, high32 string-pointer, and done-jump helpers while preserving the
  symbol offset and location pointer register contracts. The capped profile now
  shows `x64_native_program.oren` at ~63.1s total / ~45.8s parse, with
  `_x64_windows_select_state` (~93ms) as the next parser-body target.
- Windows x64 `sys_select` state setup now separates temporary slot allocation
  from five-argument LTR spill emission while preserving cleanup-on-error and the
  WinSock `select` ABI state map. The capped profile now shows
  `x64_native_program.oren` at ~63.8s total / ~46.4s parse, with
  `_x64_prepare_runtime_statement_sets` (~161ms) as the next parser-body target.
- X64 runtime statement-set preparation now separates injected-runtime setup,
  rtobj statement selection, runtime pruning, and phase-log count emission while
  preserving the returned statement map and `runtime_injected` contract. The
  capped profile now shows `x64_native_program.oren` at ~63.8s total / ~46.1s
  parse, with `_trace_x64_list_fast_loop` (~155ms) as the next parser-body
  target.
- X64 fast-list loop tracing now separates base-message construction from
  optional info-field appending while preserving the `[x64_list_fast]` key order.
  The capped profile now shows `x64_native_program.oren` at ~63.4s total /
  ~45.8s parse, with `_emit_track_alloc_x64` (~72ms) as the next parser-body
  target.
- X64 allocation tracking and allocation-trace request emission now share the
  three-argument ABI setup, spill, runtime-call, pointer-restore, and cleanup
  path while preserving each helper's validation contract. The capped profile now
  shows `x64_native_program.oren` at ~67.7s total / ~49.5s parse, with
  `_x64_compile_program_prepare_top` (~118ms) as the next parser-body target.
- X64 top-level program preparation now separates top-function validation,
  optional runtime-object code splicing, rtobj-code phase logging, and
  `__top_level__` compilation while preserving timing keys. The capped profile
  now shows `x64_native_program.oren` at ~62.8s total / ~45.6s parse, with
  `_data_finalize_linetab` (~71ms) as the next parser-body target.
- X64 line-table finalization now separates finalization validation, reserved
  header clearing, valid-entry collection, deterministic descending sort, and
  table serialization while preserving linetab layout. The capped profile now
  shows `x64_native_program.oren` at ~45.1s total / ~32.9s parse, with
  `_x64_rtobj_synthesize_wrappers` (~52ms) as the next parser-body target.
- X64 runtime-object wrapper synthesis now separates named function-use
  wrapper collection, arity decoding, and lambda wrapper collection while
  preserving wrapper order and diagnostics. The capped profile now shows
  `x64_native_program.oren` at ~45.0s total / ~32.7s parse, with
  `_emit_intrinsic_sys_linux_fcntl_raw_x64` (~50ms) as the next parser-body
  target.
- X64 Linux raw `sys_fcntl` lowering now follows the getfl/setfl helper shape,
  with separate temp-state setup, argument reload, capsule prehook, syscall, and
  capsule posthook helpers while preserving the three-argument ABI. The capped
  profile now shows `x64_native_program.oren` at ~48.9s total / ~36.4s parse,
  with `_x64_fast_lcg_unsigned_emit_safepoint` (~196ms) as the next parser-body
  target.
- X64 fast-LCG unsigned safepoint emission now separates throttle-guard
  emission, live-register spilling, safepoint call/reset, and live-register
  reload while preserving the 4096-iteration tick contract. The capped profile
  now shows `x64_native_program.oren` at ~44.5s total / ~32.1s parse, with
  `_emit_intrinsic_sys_mmap_private_anon_x64` (~49ms) as the next parser-body
  target.
- X64 private anonymous mmap lowering now separates length temp-state setup,
  ABI-specific capsule prehook argument loading, platform dispatch, and Linux
  mmap syscall argument emission while preserving the prehook length rewrite
  contract. The capped profile now shows `x64_native_program.oren` at ~44.8s
  total / ~32.5s parse, with `_emit_intrinsic_sys_linux_raw_clone_x64` (~50ms)
  as the next parser-body target.
- X64 Linux raw `clone` lowering now separates five-argument temp-state setup,
  optional capsule prehook emission, argument reload, and syscall dispatch while
  preserving raw clone register order. The capped profile now shows
  `x64_native_program.oren` at ~47.5s total / ~34.7s parse, with
  `_x64_emit_ctx_switch_save_gprs` (~99ms) as the next parser-body target.
- X64 context-switch GPR save emission now separates low and high register save
  groups while preserving the existing context slot layout and store order. The
  capped profile now shows `x64_native_program.oren` at ~49.5s total / ~36.0s
  parse, with `_x64_prepare_list_int_reduce_sum_slots_unchecked_intrinsic`
  (~115ms) as the next parser-body target.
- X64 LIST_INT unchecked reduce-sum slot preparation now separates intrinsic
  validation, temp-slot allocation, and list-argument spilling while preserving
  the single-list argument contract. The capped profile now shows
  `x64_native_program.oren` at ~45.3s total / ~32.8s parse, with
  `_emit_fast_list_int_get_sum_while_x64` (~50ms) as the next parser-body
  target.
- X64 fast LIST_INT get-sum while lowering now separates generic fallback,
  preparation fallback, checked-fast-path emission, and slow/done label
  finalization while preserving temp cleanup and runtime slow-path behavior. The
  capped profile now shows `x64_native_program.oren` at ~45.1s total / ~32.5s
  parse, with `_x64_fast_push_emit_value_store` (~62ms) as the next parser-body
  target.
- X64 fast LIST/LIST_INT push value stores now separate list-slot lookup, RHS
  lowering, and indexed buffer writes while preserving the shared push-loop
  store API. The capped profile now shows `x64_native_program.oren` at ~44.7s
  total / ~32.4s parse, with `_emit_list_int_get_intrinsic_v0_x64` (~49ms) as
  the next parser-body target.
- X64 checked LIST_INT get lowering now separates argument validation,
  label-state attachment, checked body emission, and finish cleanup while
  preserving tracked-node, magic, bounds, and value-load behavior. The capped
  profile now shows `x64_native_program.oren` at ~45.5s total / ~33.0s parse,
  with `_x64_call_name_is_float_exp_log` (~50ms) as the next parser-body target.
- X64 float exp/log call-name classification now separates root/power,
  scale/logb, exponential, and logarithmic alias families while preserving the
  public floaty-call predicate. The capped profile now shows
  `x64_native_program.oren` at ~59.8s total / ~44.4s parse, with
  `_x64_match_fast_dot_accumulate_body` (~206ms) as the next parser-body target.
- X64 fast dot-product matcher accumulation now separates sum-name validation,
  inty guards, list-local checks, unique-list recording, and multiply-pair
  recording while preserving LIST and LIST_INT matcher behavior. The capped
  profile now shows `x64_native_program.oren` at ~57.5s total / ~40.5s parse,
  with `_x64_prepare_injected_runtime_statement_sets` (~202ms) as the next
  parser-body target.
- X64 injected runtime statement-set preparation now lives in a dedicated
  program-entry fragment with separate runtime bundle options, bundle prepare,
  statement-list normalization, and result packing helpers. `090_tail.oren`
  drops below the source ceiling with more room, and the capped profile now
  shows `x64_native_program.oren` at ~45.0s total / ~32.6s parse, with
  `_x64_string_batch_append_one_data` (~49ms) as the next parser-body target.
- X64 string-batch per-item data append now separates sampled offset/value/size
  tracing, value normalization, data-buffer alignment, capped string-byte
  append, and data-done tracing while preserving the batched global string
  table layout. The capped profile now shows `x64_native_program.oren` at
  ~53.3s total / ~38.3s parse, with `_x64_call_name_is_float_trig` (~171ms) as
  the next parser-body target.
- X64 float trig call-name classification now separates hyperbolic,
  error/special constant, circular, and inverse/geometry alias families while
  preserving the public floaty-call predicate. The capped profile now shows
  `x64_native_program.oren` at ~46.8s total / ~34.2s parse, with
  `_x64_win_entry_args_emit_query_required` (~54ms) as the next parser-body
  target.
- X64 Windows entry argument conversion now shares WideCharToMultiByte prefix,
  IAT dispatch, nonzero-result guard, and distinct query/convert stack-argument
  helpers while preserving the argc/argv UTF-8 pool layout. The capped profile
  now shows `x64_native_program.oren` at ~44.9s total / ~32.6s parse, with
  `_x64_emit_regular_control_op` (~49ms) as the next parser-body target.
- X64 regular control-op lowering now delegates `if`, loop, and loop-jump
  lowering to focused helpers while preserving the regular-op `nil`/`0`
  dispatch contract. The capped profile now shows `x64_native_program.oren`
  at ~62.0s total / ~45.2s parse, with `_x64_string_batch_emit_top_loop`
  (~214ms) as the next parser-body target.
- X64 string-batch top-loop emission now separates slow-op timing, loop
  emission, and progress trace formatting while preserving the fixed `.data`
  table ABI. The capped profile now shows `x64_native_program.oren` at ~47.2s
  total / ~34.5s parse, with `_x64_rtobj_apply_legacy_fixups` (~52ms) as the
  next parser-body target.
- X64 runtime-object legacy fixup application now separates trace progress,
  legacy `rip_data32` handling, panic-helper marking, in-place regular fixup
  mutation, and phase logging while preserving old-cache fallback semantics.
  The capped profile now shows `x64_native_program.oren` at ~46.0s total /
  ~33.6s parse, with `_emit_map_wsa_eax_to_posix_errno_eax_x64` (~49ms) as the
  next parser-body target.
- X64 Windows SO_ERROR WSA-to-POSIX normalization now separates zero-preserve,
  known-code case emission, and EIO default handling while preserving the
  emitted WSAETIMEDOUT/ECONNREFUSED/EADDRINUSE/EINVAL mappings. The capped
  profile now shows `x64_native_program.oren` at ~48.6s total / ~34.3s parse,
  with `_x64_should_use_full_native_runtime_profile` (~83ms) as the next
  parser-body target.
- X64 native runtime-profile selection now separates full-runtime path matching
  from module-graph scanning while preserving safe defaults for missing linked
  or graph data. The capped profile now shows `x64_native_program.oren` at
  ~46.9s total / ~33.5s parse, with `_x64_prepare_function_params` (~57ms) as
  the next parser-body target.
- X64 function parameter preparation now separates parameter counting, slot
  binding, declared annotation marking, inferred-kind lookup, and per-parameter
  orchestration while preserving duplicate detection and slot order. The capped
  profile now shows `x64_native_program.oren` at ~52.2s total / ~38.4s parse,
  with `_x64_list_int_push_spill_args` (~126ms) as the next parser-body target.
- X64 LIST_INT push argument spilling now separates temp-slot setup, single-arg
  integer eval/spill, left-to-right two-arg spill orchestration, and final
  operand reload while preserving temp cleanup and rdx/r8 operand contracts. The
  capped profile now shows `x64_native_program.oren` at ~49.2s total / ~36.2s
  parse, with `_emit_strlen_cstr0_to_rdx` (~141ms) as the next parser-body
  target.
- X64 panic C-string length emission now separates label/fixup state setup,
  byte-scan loop emission, and loop-finalization patching while preserving the
  ptr-reg-to-r10 safety contract and rdx length output. The capped profile now
  shows `x64_native_program.oren` at ~55.6s total / ~39.7s parse, with
  `_x64_rtobj_compile_wrappers` (~188ms) as the next parser-body target.
- X64 runtime-object wrapper compilation now separates wrapper compile state,
  phase-log start/progress/done emission, per-wrapper compile/error handling,
  and trace-decl accounting while preserving wrapper order and top-decl
  accumulation. The capped profile now shows `x64_native_program.oren` at
  ~48.9s total / ~35.4s parse, with `_x64_emit_ffi_stubs` (~162ms) as the next
  parser-body target.
- X64 FFI stub emission now separates platform OS detection, shared error
  checks, explicit per-import mode dispatch, and Windows/Linux-dynamic/unresolved
  routing while preserving resolver setup and import order. The capped profile
  now shows `x64_native_program.oren` at ~51.9s total / ~38.4s parse, with
  `_x64_linux_net_msg_state` (~98ms) as the next parser-body target.
- X64 Linux sendto/recvfrom message state setup now separates six-slot temp
  allocation, left-to-right argument spilling, and state packing while preserving
  fd/buf/len/flags/addr/addrlen slot order and cleanup-on-error behavior. The
  capped profile now shows `x64_native_program.oren` at ~45.9s total / ~33.2s
  parse, with `_emit_intrinsic_sys_linux_epoll_ctl_x64` (~49ms) as the next
  parser-body target.
- X64 Linux `sys_epoll_ctl` lowering now separates four-slot state setup,
  left-to-right argument spilling, capsule prehook argument loading, and syscall
  emission while preserving `epfd/op/fd/event` slot order and the Linux x64
  `rdi/rsi/rdx/r10` syscall mapping. The capped profile now shows
  `x64_native_program.oren` at ~47.6s total / ~34.7s parse, with
  `_x64_index_prepare` (~69ms) as the next parser-body target.
- X64 index expression preparation now separates operand validation, runtime
  bundle validation, re-entrant temp-slot allocation, left/index operand
  spilling, and result packing while preserving nested index/call temp cleanup.
  The capped profile now shows `x64_native_program.oren` at ~46.1s total /
  ~33.2s parse, with `_x64_emit_runtime_oren_add_x64` (~48ms) as the next
  parser-body target.
- X64 runtime `oren_add` emission now separates runtime availability checking,
  two-slot temp allocation, left-to-right operand spilling, ABI argument register
  lookup, and call-fixup emission while preserving the shared `oren_add(a,b)`
  dispatch sequence. The capped profile now shows `x64_native_program.oren` at
  ~59.5s total / ~43.5s parse, with `_emit_win64_stat_open_file_x64` (~186ms)
  as the next parser-body target.
- X64 Windows `stat` file-open lowering now separates normalized-path argument
  restoration, `CreateFileA` register arguments, stack arguments, and
  invalid-handle failure routing while preserving path-normalization cleanup and
  local fixup labels. The capped profile now shows `x64_native_program.oren` at
  ~46.3s total / ~33.7s parse, with `_emit_intrinsic_sys_open_windows_x64`
  (~49ms) as the next parser-body target.
- X64 Windows `sys_open` lowering now separates validation, path/flags/mode
  spill-state setup, label/fixup state creation, core `CreateFileA` orchestration,
  and finish cleanup while preserving capsule pre/post hooks and Win32 errno
  mapping. The capped profile now shows `x64_native_program.oren` at ~47.9s total
  / ~34.9s parse, with `_x64_fast_list_dot_find_mul_slots` (~96ms) as the next
  parser-body target.
- X64 fast LIST dot-product slot lookup now shares the common fast-dot list-index
  and temp-slot helpers with LIST_INT, removing duplicated left/right list scans
  while preserving the `{left,right}` cursor-slot contract. The capped profile now
  shows `x64_native_program.oren` at ~49.0s total / ~35.3s parse, with
  `_emit_fast_list_int_dot_while_x64` (~121ms) as the next parser-body target.
- X64 fast LIST_INT dot-product entry lowering now separates prepare-state setup,
  checked fast-path emission, and generic fallback routing while preserving
  temp cleanup and slow-path label behavior. The capped profile now shows
  `x64_native_program.oren` at ~55.2s total / ~41.1s parse, with
  `_emit_list_int_get_unchecked_intrinsic_v0_x64` (~106ms) as the next
  parser-body target.
- X64 unchecked LIST_INT get lowering now separates argument validation, label
  attachment, and checked-body orchestration, reusing the shared get-intrinsic
  finish cleanup. The capped profile now shows `x64_native_program.oren` at
  ~51.3s total / ~37.6s parse, with `_emit_list_int_push_intrinsic_v0_x64`
  (~108ms) as the next parser-body target.
- X64 LIST_INT push lowering now separates argument validation, label
  attachment, checked-body emission, and final nil/label/temp cleanup while
  preserving fast-capacity and slow runtime fallback behavior. The capped
  profile now shows `x64_native_program.oren` at ~58.5s total / ~43.2s parse,
  with `_emit_cmp_r64_r64_maybe_string_x64` (~254ms) as the next parser-body
  target.
- X64 string-aware compare lowering now separates compare state preparation,
  operand spilling, string/int path emission, and final local-fixup patching
  while preserving the `cmp` flags contract for Jcc mapping. The capped profile
  now shows `x64_native_program.oren` at ~46.3s total / ~33.6s parse, with
  `_lit_array_trace` (~103ms) as the next parser-body target.
- X64 array-literal trace emission now separates trace reservation, function-name
  fallback, and message formatting while preserving the 16-event cap and
  `[x64_array_lit]` output keys. The capped profile now shows
  `x64_native_program.oren` at ~46.4s total / ~33.7s parse, with
  `_x64_prepare_sys_read_windows_args` (~81ms) as the next parser-body target.
- X64 Windows `sys_read` argument preparation now shares fd/buffer/length temp
  slot allocation with Windows `sys_write`, and splits fd capsule prehook handling
  from ptr/len spilling while preserving the `{base,tmp_fd,tmp_ptr,tmp_len}` state
  map. The capped profile now shows `x64_native_program.oren` at ~47.6s total /
  ~34.5s parse, with `_emit_intrinsic_sys_linux_wait4_x64` (~52ms) as the next
  parser-body target.
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
- Win64 x64 dynamic FFI stubs now delegate data materialization, cached fnptr
  load, shadow-space argument spill/restore, resolver call, cache-store,
  target tailcall, and unresolved-symbol panic emission to focused helpers. The
  capped profile now shows `x64_native_program.oren` at ~40.7s total / ~30.1s
  parse, with `_x64_emit_regular_op` exposed at ~101ms as the next parser body.
- X64 regular op dispatch now delegates straight-line declaration/expression/
  print/return ops and control-flow/loop ops to focused routers while preserving
  the existing `0`/`1` status contract for gas patching and fast-path skips. The
  capped profile now shows `x64_native_program.oren` at ~41.3s total / ~30.5s
  parse, with `_x64_emit_entry_top_and_main_calls` exposed at ~116ms as the next
  parser body.
- X64 entry top/main call emission now delegates top-level call/skip tracing and
  executable main-or-zero return setup to focused helpers while preserving DLL/SO
  no-main behavior and phase-log fixup counters. The capped profile now shows
  `x64_native_program.oren` at ~42.6s total / ~31.6s parse, with
  `_data_finalize_cstr0_table` exposed at ~140ms as the next parser body.
- X64 C-string static-table finalization now delegates reserved-slot decoding,
  runtime-object offset counting/appending, user literal offset appending, and
  slot patching to focused helpers while preserving the PIE-safe table layout.
  The capped profile now shows `x64_native_program.oren` at ~40.7s total /
  ~30.1s parse, with `_emit_eval_prefix_to_rax` exposed at ~100ms as the next
  parser body.
- X64 prefix expression lowering now delegates boolean singleton mapping,
  language-truthiness `!`, compare-infix `!`, and float/integer negation to
  focused helpers while preserving runtime singleton and IEEE sign-bit
  semantics. The capped profile now shows `x64_native_program.oren` at ~40.6s
  total / ~30.1s parse, with
  `_emit_intrinsic_sys_get_queued_completion_status_ex_windows_x64` exposed at
  ~96ms as the next parser body.
- Windows x64 `sys_get_queued_completion_status_ex` lowering now delegates
  six-argument spill state, Win64 stack-argument call setup, and GetLastError
  normalization to focused helpers while preserving timeout, invalid-parameter,
  invalid-handle, and default EIO mappings. The capped profile now shows
  `x64_native_program.oren` at ~40.8s total / ~30.1s parse, with
  `_data_finalize_dbginfo_table` exposed at ~97ms as the next parser body.
- X64 debug-info table finalization now delegates debug-build slot gating,
  function-entry collection/sorting, per-entry emission, display-name lookup,
  and reserved-slot patching to focused helpers while preserving the runtime
  symbolication table layout. The capped profile now shows
  `x64_native_program.oren` at ~42.8s total / ~32.0s parse, with
  `_x64_fast_lcg_emit_fullmod_loop` exposed at ~108ms as the next parser body.
- X64 fast LCG sum full-mod fallback now delegates loop condition, throttled
  safepoint, state reload, signed full-mod step, and writeback/increment to
  focused helpers while preserving signed `idiv` modulo behavior. The capped
  profile now shows `x64_native_program.oren` at ~41.2s total / ~30.6s parse,
  with `_emit_float_cmp_to_bool_x64` exposed at ~99ms as the next parser body.
- X64 float comparison lowering now delegates operand spilling, XMM load/convert,
  ordered/unordered condition dispatch, and bool result patching to focused
  helpers while preserving IEEE NaN behavior for each relation. The capped
  profile now shows `x64_native_program.oren` at ~40.8s total / ~29.9s parse,
  with `_emit_malloc_size_in_rax` exposed at ~141ms as the next parser body.
- X64 malloc core lowering now delegates `$tmp0` validation, allocation labels,
  size alignment, native reuse probing, heap fast-path probing, and platform
  slow-path routing to focused helpers while preserving heap register semantics.
  The capped profile now shows `x64_native_program.oren` at ~40.6s total /
  ~30.0s parse, with `_emit_call_spread_via_runtime_helper_fnexpr_x64` exposed
  at ~96ms as the next parser body.
- X64 spread-call lowering now delegates spill layout, left-to-right explicit
  argument spilling, fixed-list construction, spread/callee spilling, and
  `oren_call_obj_spread` emission to focused helpers while preserving injected
  runtime gating and temp cleanup on failure. The capped profile now shows
  `x64_native_program.oren` at ~43.0s total / ~31.8s parse, with
  `_emit_wsa_last_error_to_neg_errno_common_x64` exposed at ~124ms as the next
  parser body.
- X64 Windows WSA error normalization now shares the repeated compare/set/jump
  case emission between common socket-error and connect-specialized mappings
  while preserving POSIX errno translations and local fixup ownership. The
  capped profile now shows `x64_native_program.oren` at ~41.5s total /
  ~30.5s parse, with `_x64_emit_resolve_symbol_intrinsic` exposed at ~95ms as
  the next parser body.
- X64 `resolve_symbol` intrinsic lowering now delegates default `"???"`
  materialization, symtab offset decoding, range setup, and range-table loop
  emission to focused helpers while preserving embedded debug-symbol fallback
  semantics. The capped profile now shows `x64_native_program.oren` at ~41.1s
  total / ~30.3s parse, with `_emit_intrinsic_sys_ulock_wait_windows_x64`
  exposed at ~94ms as the next parser body.
- X64 Windows `sys_ulock_wait` lowering now delegates temp setup, argument
  spilling, timeout-us to timeout-ms conversion, `WaitOnAddress` call setup,
  and result/timeout errno mapping to focused helpers while preserving temp
  cleanup ownership. The capped profile now shows `x64_native_program.oren` at
  ~41.4s total / ~30.6s parse, with `_emit_cmp_from_cond` exposed at ~96ms as
  the next parser body.
- X64 condition compare lowering now delegates integer, identifier/global, and
  general-expression RHS paths plus truthy/prefix fallback into focused helpers
  while preserving string-aware compare routing. The capped profile now shows
  `x64_native_program.oren` at ~41.6s total / ~30.7s parse, with
  `_x64_index_emit_kind_dispatch` exposed at ~99ms as the next parser body.
- X64 index receiver kind dispatch now delegates tracked lookup, tracked guards,
  node-kind loading, and known list/list-int/map plus dynamic receiver branches
  to focused helpers while preserving panic messages and list/map branch labels.
  The capped profile now shows `x64_native_program.oren` at ~41.4s total /
  ~30.6s parse, with `_emit_list_int_get_unchecked_intrinsic_v0_x64` exposed at
  ~95ms as the next parser body.
- X64 unchecked list-int get lowering now reuses the checked get argument-spill
  helper and delegates unchecked labels, nil validation, bounds checks, and final
  value load to focused helpers while preserving unchecked header semantics. The
  capped profile now shows `x64_native_program.oren` at ~41.1s total / ~30.2s
  parse, with `_x64_build_runtime_obj` exposed at ~93ms as the next parser body.
- X64 runtime-object build orchestration now delegates trace/timing setup,
  runtime parse/context setup, runtime input preparation, decl/wrapper
  compilation, and final result packaging to focused helpers. X64 false-branch
  condition lowering now delegates float compare, prefix-`!` float compare,
  prefix-`!` truthiness, and plain truthy-expression branches while preserving
  integer compare fallback. The capped profile now shows `x64_native_program.oren`
  at ~41.3s total / ~30.6s parse, with
  `_emit_resolve_symbol_ptr_and_off_best_effort` exposed at ~93ms as the next
  parser body.
- X64 best-effort symbol pointer/offset resolution now delegates default
  `"???"` materialization, symtab offset decoding, fixed-base symtab setup, and
  scan/match emission to focused helpers. Runtime-object global metadata apply
  now delegates root metadata extraction, whole-map adoption, root progress
  logging, per-global fallback merge, and final adopted/count logging. The capped
  profile now shows `x64_native_program.oren` at ~40.8s total / ~30.1s parse,
  with `_x64_emit_list_int_dot_slots_unchecked_body` exposed at ~92ms as the next
  parser body.
- X64 unchecked list-int dot-slots lowering now delegates label/fixup state,
  nil/length checks, pointer setup, and loop emission to focused helpers. The
  fast list-int dot single-step loop now reuses the mul-slot resolver and
  delegates unique cursor reads, indexed reads, and tail writeback. The capped
  profile now shows `x64_native_program.oren` at ~40.8s total / ~30.0s parse,
  with `_x64_match_fast_lcg_sum_while` exposed at ~87ms as the next parser body.
- X64 fast LCG sum-while matching now delegates condition/local-int gates,
  body-shape extraction, LCG/mod validation, and accumulator validation to
  focused helpers. X64 program function-set preparation now delegates local-fn
  rewrites, function/type-constructor collection, FFI/top-level global
  collection, callable-use scanning, and wrapper prep. Unchecked list-int
  reduce-sum slots lowering now delegates argument preparation, label state,
  nil/setup, loop emission, and finish/patching. The capped profile now shows
  `x64_native_program.oren` at ~41.5s total / ~30.7s parse, with
  `_emit_intrinsic_sys_linux_net_msg_x64` exposed at ~85ms as the next parser
  body.
- Linux x64 `sendto`/`recvfrom` message syscall lowering now delegates syscall
  name matching, six-argument spill state, capsule prehook argument loading,
  syscall argument loading, and syscall-number emission to focused helpers.
  Lambda literal lowering now delegates metadata/capture registration, env spill
  allocation, capture-env materialization, and `oren_func` object construction.
  The capped profile now shows `x64_native_program.oren` at ~41.8s total /
  ~30.8s parse, with `_emit_intrinsic_sys_stat_windows_x64` exposed at ~83ms as
  the next parser body.
- Windows x64 `sys_stat` / `sys_lstat` lowering now delegates argument spilling,
  capsule prehook path resolution, label/fixup setup, path normalization plus
  attribute probing, directory/file dispatch, and final patch/posthook cleanup.
  The capped profile now shows `x64_native_program.oren` at ~41.9s total /
  ~31.0s parse, with `_x64_expr_is_inty` exposed at ~84ms as the next parser
  body.
- X64 integer-expression classification now delegates identifier fact lookup,
  prefix recursion, integer infix recursion, list-int index recognition, and
  integer-returning call-name groups to focused helpers while preserving the
  float-exclusion gate. The capped profile now shows `x64_native_program.oren`
  at ~41.6s total / ~30.7s parse, with `_emit_intrinsic_sys_linux_time_x64`
  exposed at ~82ms as the next parser body.
- Linux x64 `sys_gettimeofday` lowering now delegates temp-state setup,
  argument spills, capsule prehook emission, raw `gettimeofday`, and optional
  monotonic `clock_gettime` synthesis to focused helpers while preserving the
  stable 3-argument runtime ABI. The capped profile now shows
  `x64_native_program.oren` at ~41.0s total / ~30.2s parse, with
  `_emit_print_stmt_str_x64` exposed at ~81ms as the next parser body.
- X64 print-string statement lowering now delegates expression evaluation,
  string-length materialization, reusable `sys_write` temp setup, write-arg
  storage, and newline literal emission to focused helpers while keeping the
  shared Linux/Windows `sys_write` path. The capped profile now shows
  `x64_native_program.oren` at ~42.2s total / ~31.3s parse, with
  `_emit_intrinsic_sys_fcntl_setfl_windows_x64` exposed at ~82ms as the next
  parser body.
- Windows x64 `sys_fcntl_setfl` lowering now delegates temp-state setup,
  capsule pre/post hooks, nonblocking `FIONBIO` mode materialization,
  `ioctlsocket`, and WSA errno normalization to focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~42.2s total / ~31.3s parse,
  with `_emit_intrinsic_sys_mkdir_or_chmod_windows_x64` exposed at ~82ms as the
  next parser body.
- Windows x64 `sys_mkdir` / `sys_chmod` lowering now delegates temp-state setup,
  capsule path resolution, CreateDirectory/no-op chmod operation emission,
  BOOL-to-errno normalization, and capsule posthooks to focused helpers. The
  capped profile now shows `x64_native_program.oren` at ~41.8s total /
  ~30.6s parse, with `_emit_intrinsic_sys_win_wait_single_object_windows_x64`
  exposed at ~81ms as the next parser body.
- Windows x64 `sys_win_wait_single_object` lowering now delegates temp-state
  setup, timeout-to-INFINITE argument normalization, the `WaitForSingleObject`
  IAT call, and WAIT-code result mapping to focused helpers while preserving
  the `0` / `-ETIMEDOUT` / `-1` contract. The capped profile now shows
  `x64_native_program.oren` at ~41.7s total / ~30.5s parse, with
  `_emit_intrinsic_sys_sendto_windows_x64` exposed at ~79ms as the next parser
  body.
- Windows x64 `sys_sendto` / `sys_recvfrom` lowering now shares six-argument
  socket message helpers for temp-state setup, Win64 stack-arg loading,
  capsule prehooks, IAT dispatch, and WSA errno normalization. The capped
  profile now shows `x64_native_program.oren` at ~42.4s total / ~31.4s parse,
  with `_x64_fast_list_dot_emit_single` exposed at ~82ms as the next parser
  body.
- Generic x64 LIST dot fast-loop single-step lowering now mirrors the LIST_INT
  split shape with focused helpers for multiplication slot resolution,
  unique-cursor reads, indexed reads, multiply/add emission, and tail writeback.
  The capped profile now shows `x64_native_program.oren` at ~41.2s total /
  ~30.3s parse, with `_emit_eval_call_expr_to_rax` exposed at ~79ms as the next
  parser body.
- X64 expression lowering now splits call target normalization, zero-arg GC
  calls, `oren_` prefix classification, intrinsic/syscall routing, shift
  count lowering, and LIST_INT get-sum validation substeps into focused helpers.
  The capped profile now shows `x64_native_program.oren` at ~42.4s total /
  ~31.1s parse, with `_x64_fast_list_dot_validate_lists` exposed at ~80ms as
  the next parser body.
- X64 LIST/LIST_INT dot fast-loop lowering now splits generic LIST validation
  into slot-state, capture, header, count, and buffer helpers, and keeps the
  LIST_INT dot wrapper as validation/helper, loop-core, and finish/slow-path
  orchestration helpers. The capped profile now shows `x64_native_program.oren`
  at ~43.6s total / ~32.3s parse, with
  `_emit_win32_last_error_to_neg_errno_common_x64` exposed at ~83ms as the next
  parser body.
- Windows x64 Win32 `GetLastError` errno lowering now shares the repeated
  compare/set/jump case emission through `_emit_win32_neg_errno_case_x64` while
  preserving the POSIX-style ENOENT, EACCES, EBADF, EBUSY, EEXIST, ENOTEMPTY,
  EXDEV, and fallback EIO mappings. The capped profile now shows
  `x64_native_program.oren` at ~41.4s total / ~30.5s parse, with
  `_emit_intrinsic_sys_rename_windows_x64` exposed at ~79ms as the next parser
  body.
- Windows x64 `sys_rename` lowering now mirrors the adjacent mkdir/chmod helper
  shape with focused state/eval, capsule prehook, `MoveFileExA`, BOOL-result,
  and capsule posthook helpers while preserving path normalization and
  replace-existing semantics. The capped profile now shows
  `x64_native_program.oren` at ~41.5s total / ~30.7s parse, with
  `_emit_resolve_loc_ptr_best_effort` exposed at ~85ms as the next parser body.
- X64 best-effort panic location resolution now mirrors the symbol resolver with
  focused default-location, linetab setup, and scan-loop helpers while preserving
  debug-only linetab fallback and unsigned fixed-base address checks. The capped
  profile now shows `x64_native_program.oren` at ~41.7s total / ~30.7s parse,
  with `_emit_infix_add_or_string_concat_x64` exposed at ~78ms as the next
  parser body.
- X64 infix `+` lowering now keeps the wrapper as a small router and delegates
  known-int direct add and injected-runtime `oren_add` fallback emission to
  focused helpers while preserving the handled/nil contract used by infix
  dispatch. The capped profile now shows `x64_native_program.oren` at ~42.1s
  total / ~31.1s parse, with `_x64_collect_callable_uses` exposed at ~79ms as
  the next parser body.
- X64 callable-use collection now separates lambda scanning/phase logging,
  optional `OREN_DEBUG_X64_LAMBDAS` reporting, and named function value-use
  discovery while preserving the same statement-set return and wrapper
  preparation contract. The capped profile now shows `x64_native_program.oren`
  at ~42.8s total / ~31.7s parse, with `_x64_rtobj_apply_function_offsets`
  exposed at ~80ms as the next parser body.
- X64 runtime-object function-offset replay now routes compact sidecar
  attachment and legacy map replay through focused helpers while preserving
  call-depth hook discovery, base-code adjustment, and phase-log path reporting.
  The capped profile now shows `x64_native_program.oren` at ~41.6s total /
  ~30.7s parse, with `_emit_intrinsic_sys_linux_net_sockopt_x64` exposed at
  ~77ms as the next parser body.
- Linux x64 `sys_getsockopt` / `sys_setsockopt` lowering now mirrors the
  adjacent Linux net-message helper shape with shared spill state, capsule
  prehook argument loading, syscall argument loading, and syscall-number
  dispatch helpers. The capped profile now shows `x64_native_program.oren` at
  ~42.1s total / ~31.1s parse, with `_emit_intrinsic_sys_nanosleep_windows_x64`
  exposed at ~78ms as the next parser body.
- Windows x64 `sys_nanosleep` lowering now delegates temp/eval setup, capsule
  prehook adjustment, nonpositive fast return, nanosecond-to-DWORD millisecond
  conversion, and `Sleep` call/result emission to focused helpers while
  preserving the best-effort no-EINTR contract. The capped profile now shows
  `x64_native_program.oren` at ~42.9s total / ~31.8s parse, with
  `_x64_emit_sys_stat_or_lstat_x64` exposed at ~77ms as the next parser body.
- Linux x64 `sys_stat` / `sys_lstat` lowering now delegates temp layout,
  capsule path resolution, host-stat buffer offset derivation, `newfstatat`
  setup, and capsule posthook emission to focused helpers while preserving the
  38-qword spill-gap layout that prevents kernel `struct stat` writes from
  clobbering spilled args. The capped profile now shows `x64_native_program.oren`
  at ~42.6s total / ~31.5s parse, with `_x64_fast_list_int_push_validate_one_list`
  exposed at ~77ms as the next parser body.
- X64 fast LIST_INT push validation now mirrors the generic LIST push helper
  shape with separate list-state capture, nil/list capture, tracked LIST_INT
  validation, reserve/count check, and buffer-slot capture helpers. The capped
  profile now shows `x64_native_program.oren` at ~41.8s total / ~30.7s parse,
  with `_emit_intrinsic_sys_linux_pipe_x64` exposed at ~74ms as the next parser
  body.
- Linux x64 `sys_pipe` lowering now delegates pointer/rc spill setup, capsule
  prehook, `pipe2` syscall setup, success-only int[2]-to-u64 fd widening, and
  capsule posthook emission to focused helpers while preserving the saved-rc
  RAX contract. The capped profile now shows `x64_native_program.oren` at
  ~42.0s total / ~30.9s parse, with `_x64_match_fast_list_int_dot_while`
  exposed at ~75ms as the next parser body.
- X64 fast LIST_INT/LIST dot-while matching now shares counted-loop validation,
  typed/generic dot step dispatch, and dot-body accumulation helpers while keeping
  the public matcher entrypoints tiny. The capped profile now shows
  `x64_native_program.oren` at ~43.0s total / ~31.6s parse, with
  `_x64_extract_type_constructors_v0` exposed at ~80ms as the next parser body.
- X64 synthesized type-constructor extraction now delegates linked-statement
  access, type-name validation, field parameter/hash shaping, function synthesis,
  and context registration to focused helpers while preserving function arity and
  declaration-order side effects. The capped profile now shows
  `x64_native_program.oren` at ~42.1s total / ~30.9s parse, with
  `_emit_fast_list_get_sum_while_x64` exposed at ~79ms as the next parser body.
- X64 fast LIST get-sum loop lowering now delegates label setup, entry gates,
  validation fallback, loop condition/body emission, and finish/slow-path
  orchestration to focused helpers while preserving the generic slow fallback.
  The capped profile now shows `x64_native_program.oren` at ~42.4s total /
  ~31.3s parse, with `_x64_ulock_wait_emit_result_windows` exposed at ~84ms as
  the next parser body.
- Windows x64 `sys_ulock_wait` result mapping now delegates label/fixup state,
  BOOL dispatch, `GetLastError` timeout dispatch, and success/timeout/failure
  return emission to focused helpers while preserving the `0` / `-ETIMEDOUT` /
  `-EIO` contract. The capped profile now shows `x64_native_program.oren` at
  ~42.9s total / ~31.6s parse, with `_x64_fast_list_get_sum_validate_lists`
  exposed at ~76ms as the next parser body.
- X64 fast LIST get-sum validation now delegates per-list temp state, list
  capture, tracked LIST kind validation, magic/count checks, and buffer capture
  to focused helpers while preserving slow-path jumps and temp cleanup on setup
  failure. The capped profile now shows `x64_native_program.oren` at ~42.1s
  total / ~31.1s parse, with
  `_emit_intrinsic_sys_post_queued_completion_status_windows_x64` exposed at
  ~74ms as the next parser body.
- Windows x64 `sys_post_queued_completion_status` lowering now delegates
  argument spill state, `PostQueuedCompletionStatus` call setup, BOOL dispatch,
  Win32 error mapping, success emission, and temp cleanup to focused helpers
  while preserving the `0` / `-EINVAL` / `-EBADF` / `-EIO` contract. The capped
  profile now shows `x64_native_program.oren` at ~43.4s total / ~32.1s parse,
  with `_x64_fast_list_int_dot_validate_lists` exposed at ~78ms as the next
  parser body.
- X64 fast LIST_INT dot validation now delegates per-list temp state, list
  capture, tracked LIST_INT kind validation, magic/count checks, and buffer
  capture to focused helpers while preserving slow-path jumps and temp cleanup
  on setup/compiler failure. The capped profile now shows
  `x64_native_program.oren` at ~45.0s total / ~33.5s parse, with
  `_x64_emit_compiled_function_body` exposed at ~81ms as the next parser body.
- X64 compiled function-body orchestration now delegates runtime entry setup,
  body-op emission, done-phase detail packing, and epilogue/reporting to focused
  helpers while preserving call-depth, GC tick, phase-log, and trace ordering.
  The capped profile now shows `x64_native_program.oren` at ~42.3s total /
  ~30.9s parse, with `_emit_intrinsic_sys_unlink_or_rmdir_windows_x64` exposed
  at ~73ms as the next parser body.
- Windows x64 `sys_unlink` / `sys_rmdir` lowering now delegates temp path state,
  capsule prehook, DeleteFile/RemoveDirectory dispatch, BOOL-to-errno mapping,
  and capsule posthook to focused helpers while preserving the resolved-path pair
  and rc posthook ordering. The capped profile now shows
  `x64_native_program.oren` at ~42.6s total / ~31.4s parse, with
  `_emit_eval_call_internal_fast_generic_x64` exposed at ~74ms as the next
  parser body.
- X64 internal fast-call routing now delegates generic-call emission, fixed-width
  prefix checks, `insn_`/`push_`, `set_`/`bytes_`, and `native_` handling to
  focused helpers while preserving the `native_call1` intrinsic escape hatch.
  The capped profile now shows `x64_native_program.oren` at ~42.5s total /
  ~31.2s parse, with `_x64_fast_lcg_emit_unsigned_loop` exposed at ~76ms as the
  next parser body.
- X64 fast LCG unsigned loop emission now mirrors the fullmod helper shape by
  delegating condition, throttled safepoint, unroll2 body, single-iteration tail,
  and final writeback/exit emission to focused helpers. The capped profile now
  shows `x64_native_program.oren` at ~43.1s total / ~31.6s parse, with
  `_x64_match_fast_list_int_get_sum_while` exposed at ~74ms as the next parser
  body.
- X64 counted fast-loop matching now shares one integer counted-loop recognizer
  across LIST_INT get-sum, generic LIST get-sum, and dot-product matchers, with
  LIST_INT/LIST get-sum accumulation split into focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~42.6s total / ~31.1s parse,
  with `_x64_emit_assign_top_string_fast` exposed at ~76ms as the next parser
  body.
- X64 top-level string assignment now shares one literal-store path between
  direct global-string init and assign-fast lowering, including global offset
  resolution, C-string table append timing, global-store emission, and slow-op
  phase logging. The capped profile now shows `x64_native_program.oren` at
  ~42.3s total / ~31.0s parse, with `_emit_hash_literal_expr` exposed at ~72ms
  as the next parser body.
- X64 list/hash literal lowering now shares cached literal-temp lookup,
  constructor allocation, depth cleanup, and error checks; hash literal insertion
  delegates pair validation and key-kind annotated map-set emission to focused
  helpers while preserving deterministic integer/string key lowering. The
  capped profile now shows `x64_native_program.oren` at ~42.3s total / ~31.0s
  parse, with `_x64_emit_sys_mkdir_or_chmod_x64` exposed at ~72ms as the next
  parser body.
- Linux x64 `sys_mkdir` / `sys_chmod` lowering now mirrors the platform FS helper
  shape by delegating spill-state setup, capsule path resolution, syscall
  selection, and capsule posthook emission to focused helpers. The capped
  profile now shows `x64_native_program.oren` at ~43.4s total / ~31.9s parse,
  with `_x64_emit_global_root_table_loop` exposed at ~74ms as the next parser
  body.
- X64 global-root table registration now separates root-offset data
  serialization, loop state creation, scratch initialization, loop header, and
  per-root registration step emission while preserving the one-table/one-loop
  runtime strategy. The capped profile now shows `x64_native_program.oren` at
  ~42.5s total / ~31.2s parse, with `_emit_intrinsic_sys_windows_net_x64`
  exposed at ~71ms as the next parser body.
- Windows x64 net syscall dispatch now routes through focused family helpers for
  WSA bootstrap/close, IOCP, socket lifecycle, sockopt/shutdown, message I/O,
  and overlapped WSA operations while preserving the existing syscall match
  order. The capped profile now shows `x64_native_program.oren` at ~42.6s total
  / ~31.1s parse, with `_x64_classify_named_call_v0` exposed at ~97ms as the
  next parser body.
- X64 named-call classification now separates shadow-aware direct/import lookup,
  varargs fixed-arity metadata lookup, wrapper/self-recursion suppression, and
  direct-call arity validation while preserving the downstream call-info map
  contract. The capped profile now shows `x64_native_program.oren` at ~43.2s
  total / ~31.7s parse, with `_emit_intrinsic_sys_read_linux_x64` exposed at
  ~106ms as the next parser body.
- Linux x64 `sys_read` / `sys_write` lowering now shares fd/pointer/length spill
  state setup, capsule prehook dispatch, and syscall argument reload helpers
  while preserving read passthrough semantics and write's nonpositive-length
  zero return. The capped profile now shows `x64_native_program.oren` at ~43.8s
  total / ~32.3s parse, with `_compile_function_v0` exposed at ~87ms as the
  next parser body.
- X64 function compilation now delegates function start/reset, ops analysis,
  frame preparation/header emission, function-state packing, and compile-option
  packing to focused helpers while keeping `_compile_function_v0` as a thin
  coordinator. The capped profile now shows `x64_native_program.oren` at ~42.7s
  total / ~31.1s parse, with `_emit_intrinsic_sys_cancel_io_ex_windows_x64`
  exposed at ~72ms as the next parser body.
- Linux x64 `sys_wait4` lowering now separates four-slot temp state setup,
  left-to-right argument spilling, optional capsule prehook emission, and syscall
  argument loading while preserving Linux x64 `rdi`/`rsi`/`rdx`/`r10` register
  order. The capped profile now shows `x64_native_program.oren` at ~48.7s total
  / ~35.5s parse, with `_emit_intrinsic_sys_linux_random_x64` exposed at ~89ms
  as the next parser body.
- Linux x64 random syscall lowering now separates getrandom temp-state setup,
  left-to-right argument spilling, and `rdi`/`rsi`/`rdx` syscall argument loading
  while preserving `sys_getentropy`'s Linux `-ENOSYS` fallback behavior. The
  capped profile now shows `x64_native_program.oren` at ~51.5s total / ~36.8s
  parse, with `_x64_fast_list_push_emit_checked_fast_path` exposed at ~150ms as
  the next parser body.
- X64 fast LIST push checked-path lowering now routes validation, loop emission,
  and post-loop count updates through focused fallback-aware helpers while
  preserving temp cleanup, error checks, and slow-path fallback order. The capped
  profile now shows `x64_native_program.oren` at ~47.8s total / ~34.4s parse,
  with `_x64_program_compile_options` exposed at ~78ms as the next parser body.
- X64 program compile-option assembly now separates base, progress, entry, slow
  function, and phase-detail option packing helpers while preserving the
  flattened option-map contract consumed by program entry and function loops. The
  capped profile now shows `x64_native_program.oren` at ~46.2s total / ~33.4s
  parse, with `_emit_intrinsic_sys_fcntl_getfl_windows_x64` exposed at ~48ms as
  the next parser body.
- Windows x64 `sys_fcntl_getfl` lowering now separates fd spill-state setup,
  shared `F_GETFL` argument loading, capsule pre/post hooks, and blocking-mode
  zero-result materialization while preserving the WinSock no-`F_GETFL` fallback.
  The capped profile now shows `x64_native_program.oren` at ~52.7s total / ~38.6s
  parse, with `_emit_ensure_tracked_ptr_kind_x64` exposed at ~102ms as the next
  parser body.
- X64 tracking runtime-call helpers now share locals/runtime validation and
  two-argument ABI lookup, while `oren_ensure_tracked` emission separates pointer
  spilling, runtime call fixup, and authoritative RAX result materialization. The
  capped profile now shows `x64_native_program.oren` at ~63.6s total / ~46.2s
  parse, with `_emit_panic_helper_fn_if_needed_x64` exposed at ~168ms as the next
  parser body.
- X64 shared panic-helper final emission now separates helper-needed/already-emitted
  gating, function offset registration, and platform argument-register selection
  while preserving the single `__oren_panic_helper` ABI. The capped profile now
  shows `x64_native_program.oren` at ~46.5s total / ~33.6s parse, with
  `_x64_emit_assign_top_empty_container` exposed at ~48ms as the next parser body.
- X64 top-level empty-container assignment now separates empty-list/map runtime
  symbol selection, alloc/store emission, and slow-op trace formatting while
  reusing the shared global-offset and source-location helpers. The capped profile
  now shows `x64_native_program.oren` at ~47.9s total / ~34.8s parse, with
  `_x64_emit_entry_static_cstr_table` exposed at ~52ms as the next parser body.
- X64 entry static C-string table initialization now separates reserved-slot
  lookup, PIE-safe table-pointer materialization, platform argument loading,
  runtime call emission, and phase/trace logging while preserving unconditional
  phase logging. The capped profile now shows `x64_native_program.oren` at ~46.4s
  total / ~33.7s parse, with `_x64_resolve_symbol_emit_range_setup` exposed at
  ~55ms as the next parser body.
- X64 `resolve_symbol` range setup now separates label-state creation,
  text-range guard emission, target-offset materialization, symtab pointer/data
  base setup, and scan-cursor initialization while preserving the `r8`/`r9`/
  `r10`/`r11`/`ecx` register contract. The capped profile now shows
  `x64_native_program.oren` at ~56.7s total / ~41.4s parse, with
  `_x64_list_len_spill_arg` exposed at ~108ms as the next parser body.
- X64 LIST/LIST_INT length lowering now shares one-argument validation and temp
  spill helpers across checked and unchecked length intrinsics, and `oren_list_len`
  now releases its temp slot on argument-evaluation errors like the LIST_INT path.
  The capped profile now shows `x64_native_program.oren` at ~54.1s total /
  ~39.9s parse, with `_emit_eval_logical_infix_to_rax` exposed at ~217ms as the
  next parser body.
- X64 logical infix expression lowering now separates short-circuit label state,
  false/end materialization, `&&` RHS emission, and `||` RHS emission while
  preserving truthiness checks and BOOL singleton results. The capped profile now
  shows `x64_native_program.oren` at ~62.3s total / ~45.0s parse, with
  `_x64_ops_need_literal_slots` exposed at ~198ms as the next parser body.
- X64 literal-slot need scanning now separates expression-op, `if`, `while`,
  `for`, and synthetic/simple op classification while preserving conservative
  unknown-op slot reservation. The capped profile now shows
  `x64_native_program.oren` at ~48.9s total / ~35.8s parse, with
  `_x64_emit_prebuilt_batch_op` exposed at ~50ms as the next parser body.
- X64 prebuilt top-level batch dispatch now shares slow-timing setup and splits
  string-table and empty-container table emission helpers while preserving
  table-backed fast-return behavior. The capped profile now shows
  `x64_native_program.oren` at ~45.6s total / ~32.9s parse, with
  `_x64_wsa_overlapped_msg_spill_base` exposed at ~46ms as the next parser body.
- X64 Windows WSA overlapped message spill setup now separates common temp-state
  allocation, slot validation, six-argument left-to-right spilling, and state
  packing while preserving `WSARecv`/`WSARecvFrom`/`WSASend` slot layout. The
  capped profile now shows `x64_native_program.oren` at ~48.3s total / ~34.4s
  parse, with `_emit_intrinsic_sys_nanosleep_windows_x64` exposed at ~51ms as
  the next parser body.
- X64 Windows `sys_nanosleep` lowering now separates validation, label/fixup
  state creation, sleep-path emission, and final patch/temp cleanup while
  preserving the `Sleep(DWORD)` best-effort contract. The capped profile now
  shows `x64_native_program.oren` at ~46.3s total / ~33.4s parse, with
  `_x64_win_cp_emit_create_call` exposed at ~47ms as the next parser body.
- X64 Windows `CreateProcessA` call emission now separates register argument
  materialization, Win64 stack argument layout, and result/failure routing while
  preserving cleanup-label behavior. The capped profile now shows
  `x64_native_program.oren` at ~55.9s total / ~41.2s parse, with
  `_emit_sys_open_windows_access_args_x64` exposed at ~105ms as the next parser
  body.
- X64 Windows `sys_open` access argument emission now separates access-mode
  dispatch labels, append override, and share/security argument materialization
  while preserving `CreateFileA` register semantics. The capped profile now
  shows `x64_native_program.oren` at ~46.2s total / ~33.4s parse, with
  `_emit_eval_int_to_rax` exposed at ~47ms as the next parser body.
- X64 expression evaluation dispatch now separates scalar/name cases from
  compound/control cases with an explicit handled-state contract while
  preserving all existing emitter callees. The capped profile now shows
  `x64_native_program.oren` at ~54.1s total / ~38.0s parse, with
  `_x64_emit_list_int_push_trace` exposed at ~141ms as the next parser body.
- X64 LIST and LIST_INT push trace emission now share local ABI argument
  lookup, header-call emission, and trace-gate helpers while preserving
  `list_push`/`list_int_push` event IDs. The capped profile now shows
  `x64_native_program.oren` at ~46.8s total / ~33.8s parse, with
  `_x64_flush_global_string_init_batch` exposed at ~52ms as the next parser
  body.
- X64 global string init batch flushing now separates first-token selection,
  compact table serialization, table-backed statement emission, and fallback
  statement construction while preserving both fast and fallback statement
  shapes. The capped profile now shows `x64_native_program.oren` at ~49.3s
  total / ~35.7s parse, with `_x64_emit_list_push_slow_or_fast` exposed at
  ~89ms as the next parser body.
- X64 LIST and LIST_INT push slow/fast lowering now share the capacity branch,
  runtime fallback call, indexed buffer store, and trace-header emission while
  preserving each runtime fallback symbol and event kind. The capped profile now
  shows `x64_native_program.oren` at ~45.9s total / ~33.1s parse, with
  `_x64_setup_runtime_object_choice` exposed at ~46ms as the next parser body.
- X64 runtime-object choice setup now separates runtime-object cache enablement,
  trace formatting, load/build attempt, and phase-log completion while preserving
  `OREN_NATIVE_RUNTIME_OBJ_CACHE` / `OREN_X64_SKIP_RTOBJ` semantics and trace
  strings. The capped profile now shows `x64_native_program.oren` at ~46.1s
  total / ~33.2s parse, with `_x64_getsockopt_translate_args` exposed at ~67ms
  as the next parser body.
- Windows x64 `setsockopt` and `getsockopt` lowering now share portable
  socket-level and option-name translation helpers while preserving call-site
  label prefixes, `rdx` level output, and `r8` optname output. The capped
  profile now shows `x64_native_program.oren` at ~50.9s total / ~37.6s parse,
  with `_x64_compile_user_function_set` exposed at ~129ms as the next parser
  body.
- X64 user-function set compilation now separates function-set start logging,
  per-function loop orchestration, and function-set done logging while
  preserving phase detail flags, slow-function tracking, progress logging, and
  early error return behavior. The capped profile now shows
  `x64_native_program.oren` at ~47.4s total / ~34.4s parse, with
  `_x64_emit_ops_one_in_fn` exposed at ~48ms as the next parser body.
- X64 function-body op emission now separates per-op preparation, prebuilt
  batch dispatch, and regular op dispatch/finish handling while preserving the
  `nil`-on-error and `0`-on-handled loop contract. The capped profile now shows
  `x64_native_program.oren` at ~47.3s total / ~34.4s parse, with
  `_emit_eval_div_infix_to_rax` exposed at ~47ms as the next parser body.
- X64 integer division infix lowering now separates operand preparation,
  divide-by-zero guard emission, overflow guard emission, and final `cqo/idiv`
  emission while preserving the `rax` dividend / `rcx` divisor contract. The
  capped profile now shows `x64_native_program.oren` at ~46.5s total / ~33.7s
  parse, with `_x64_match_fast_counted_int_loop_bound` exposed at ~46ms as the
  next parser body.
- X64 fast counted-int loop matching now separates condition extraction, bound
  parsing, local/int-kind validation, and body increment validation while
  preserving the returned `{idx,n,n_const,body,body_n}` matcher shape. The capped
  profile now shows `x64_native_program.oren` at ~53.3s total / ~38.9s parse,
  with `_emit_intrinsic_sys_linux_nanosleep_x64` exposed at ~79ms as the next
  parser body.
- Linux x64 `sys_nanosleep` lowering now separates temp-state setup, capsule
  prehook adjustment, and skip-or-syscall routing while preserving the `ns <= 0`
  fast return and stack-local timespec syscall path. The capped profile now shows
  `x64_native_program.oren` at ~46.7s total / ~33.9s parse, with
  `_emit_intrinsic_atomic_cas_x64` exposed at ~45ms as the next parser body.
- X64 `atomic_add` and `atomic_cas` lowering now share atomic argument
  validation, pointer/expected temp-state setup, and eval-to-temp spill helpers
  while preserving `lock xadd` and `lock cmpxchg` register contracts. The capped
  profile now shows `x64_native_program.oren` at ~64.8s total / ~46.3s parse,
  with `_data_cstr0_ensure_state` exposed at ~251ms as the next parser body.
- X64 C-string data setup now separates shared data-blob, dedup-offset map, and
  literal-offset list initialization helpers, and the no-dedup string append path
  reuses the common blob/list setup. The capped profile now shows
  `x64_native_program.oren` at ~46.0s total / ~33.2s parse, with
  `_x64_spawn_expand_spread_loop` exposed at ~45ms as the next parser body.
- X64 spawn spread-argument expansion now separates loop label/fixup state,
  bounds guard emission, spread-element spilling, list push emission, and index
  increment/back-edge emission while preserving the existing temp cleanup on
  expression errors. The capped profile now shows `x64_native_program.oren` at
  ~49.1s total / ~36.1s parse, with `_linetab_record_tok` exposed at ~50ms as
  the next parser body.
- X64 debug line-table token recording now separates activation/capacity checks,
  token-to-location formatting, location C-string interning, duplicate-line
  suppression, and entry append while preserving the `off+1` encoded-offset
  contract. The capped profile now shows `x64_native_program.oren` at ~47.2s
  total / ~34.4s parse, with `_x64_fast_lcg_emit_entry_gates` exposed at ~47ms
  as the next parser body.
- X64 fast LCG entry gating now separates modulus materialization, nonnegative
  `i/n/x/sum` state guards, and sum-cap guard emission while preserving the
  `r12`/`r9` and `idx/n/x/sum` register contracts. The capped profile now shows
  `x64_native_program.oren` at ~47.3s total / ~34.5s parse, with
  `_x64_collect_top_level_globals_and_stmts` exposed at ~47ms as the next parser
  body.
- X64 top-level global collection now splits runtime/user statement
  classification, split phase logging, global-slot/init-statement preparation,
  and final trace/slice packing while preserving the synthesized
  `top_level_fn`/`top_stmt_count` contract. The capped profile now shows
  `x64_native_program.oren` at ~55.3s total / ~39.8s parse, with
  `_x64_emit_direct_named_call_v0` exposed at ~180ms as the next parser body.
- X64 direct named-call emission now separates varargs callable-ABI routing from
  fixed direct-call spill/load/fixup cleanup while preserving direct call
  arity, import return normalization, and temp-slot cleanup behavior. The capped
  profile now shows `x64_native_program.oren` at ~50.1s total / ~36.3s parse,
  with `_x64_match_fast_push_loop_body` exposed at ~107ms as the next parser
  body.
- X64 fast LIST/LIST_INT push-loop matching now separates push-call
  classification, per-step validation, matched-list recording, and pushed-value
  independence checks while preserving the `{lists,pushes}` matcher result. The
  capped profile now shows `x64_native_program.oren` at ~53.5s total / ~39.1s
  parse, with `_emit_list_int_set_intrinsic_v0_x64` exposed at ~121ms as the
  next parser body.
- X64 LIST_INT set lowering now separates argument validation, label-state
  attachment, checked-body orchestration, and finish cleanup while preserving
  tracked-node, value-check, slow-runtime fallback, and in-bounds store
  behavior. The capped profile now shows `x64_native_program.oren` at ~47.6s
  total / ~34.5s parse, with `_x64_rtobj_apply_compact_fixups` exposed at
  ~50ms as the next parser body.
- X64 runtime-object compact fixup application now separates compact sidecar
  attachment, nil-safe fixup counting, RIP fixup aggregation, and phase-log
  emission while preserving compact fixup context keys and panic-helper
  detection. The capped profile now shows `x64_native_program.oren` at ~46.6s
  total / ~33.6s parse, with
  `_x64_prepare_list_int_dot_slots_unchecked_intrinsic` exposed at ~44ms as the
  next parser body.
- X64 LIST_INT unchecked dot-slot preparation now separates argument validation,
  temp-slot allocation, single-argument spilling, and two-argument spill
  orchestration while preserving left-to-right evaluation and temp cleanup on
  expression errors. The capped profile now shows `x64_native_program.oren` at
  ~51.7s total / ~38.0s parse, with `_x64_try_load_or_build_runtime_obj`
  exposed at ~54ms as the next parser body.
- X64 runtime-object load/build routing now separates cache-enable state,
  identity attachment, cache/seed hit routing, miss build, and build-apply
  timing while preserving cache key selection, seed fallback, store/apply, and
  phase markers. The capped profile now shows `x64_native_program.oren` at
  ~46.5s total / ~33.6s parse, with `_x64_match_sum_mod_update` exposed at
  ~45ms as the next parser body.
- X64 fast-LCG sum modulo matching now separates modulo RHS validation, add-term
  classification, duplicate tracking, and final matcher packing while preserving
  the `{mod_x, mod_i}` result. The capped profile now shows
  `x64_native_program.oren` at ~53.5s total / ~39.1s parse, with
  `_x64_fast_list_int_dot_prepare` exposed at ~170ms as the next parser body.
- X64 LIST/LIST_INT dot-loop preparation now shares input unpacking,
  local-offset validation, list/mul counts, uniqueness detection, and temp-base
  allocation while keeping LIST_INT whole-list-helper policy separate. The
  capped profile now shows `x64_native_program.oren` at ~46.7s total / ~33.7s
  parse, with `_x64_expr_int_const` exposed at ~45ms as the next parser body.
- X64 integer-constant lookup now exposes direct name/global helpers and uses
  them in the fast LIST_INT dot/get whole-list gates, avoiding synthetic
  identifier expression maps while preserving literal, identifier, member, and
  prefix constant handling. The capped profile now shows
  `x64_native_program.oren` at ~47.5s total / ~34.3s parse, with
  `_emit_intrinsic_sys_linux_execve_x64` exposed at ~45ms as the next parser
  body.
- X64 Linux `sys_execve` lowering now separates temp-state setup, left-to-right
  argument spilling, capsule prehook/envp rewrite, and syscall register loading
  while preserving `rdi/rsi/rdx` syscall semantics. The capped profile now shows
  `x64_native_program.oren` at ~46.6s total / ~33.6s parse, with
  `_emit_intrinsic_sys_wsa_startup_windows_x64` exposed at ~44ms as the next
  parser body.
- Windows x64 `sys_wsa_startup` lowering now separates WSADATA pointer spill
  state, `WSAStartup(MAKEWORD(2,2), wsadata)` call setup, and return-code
  normalization while preserving the `-EIO` best-effort failure contract. The
  capped profile now shows `x64_native_program.oren` at ~50.6s total / ~36.3s
  parse, with `_x64_win_entry_args_emit_parse` exposed at ~87ms as the next
  parser body.
- Windows x64 entry argument parsing now separates `GetCommandLineW`,
  `CommandLineToArgvW`, and parsed-argc routing helpers while preserving
  `rbx`/`r10` handoff and `LocalFree` cleanup labels. The capped profile now
  shows `x64_native_program.oren` at ~50.8s total / ~37.3s parse, with
  `_x64_spawn_prepare_spread_slots` exposed at ~118ms as the next parser body.
- X64 spawn spread-slot preparation now separates spread/idx/len/elem slot
  layout, frame-offset lookup, and state packing while preserving the
  `args_slot+1..4` spill contract and missing-slot cleanup behavior. The
  capped profile now shows `x64_native_program.oren` at ~47.0s total / ~33.8s
  parse, with `_emit_intrinsic_sys_munmap_x64` exposed at ~44ms as the next
  parser body.
- X64 `sys_munmap` lowering now separates temp-state setup, ABI-specific
  capsule prehook argument loading, and Linux/Windows syscall dispatch while
  preserving left-to-right address/length spilling and `VirtualFree` fallback
  routing. The capped profile now shows `x64_native_program.oren` at ~52.6s
  total / ~37.9s parse, with `_emit_win64_path_norm_loop_x64` exposed at ~81ms
  as the next parser body.
- Windows x64 path-normalization loop emission now separates loop-state packing,
  byte load/termination guards, slash-to-backslash conversion, and store/cursor
  advancement while preserving the exact label and branch sequence used by the
  scratch-buffer normalizer. The capped profile now shows
  `x64_native_program.oren` at ~51.3s total / ~37.7s parse, with
  `_collect_locals_from_ops` exposed at ~89ms as the next parser body.
- X64 local-slot collection now separates per-op dispatch, `var_i32` slot
  binding, generic sequence recursion, and `if`/`for` traversal helpers while
  preserving name-based slot reuse and the original then/else/body visit order.
  The capped profile now shows `x64_native_program.oren` at ~47.9s total /
  ~34.7s parse, with `_x64_emit_entry_boot_globals` exposed at ~46ms as the next
  parser body.
- X64 entry boot-global initialization now separates reserved-offset validation,
  RIP-relative storage pointer materialization, and boot storage link emission
  while preserving the `g_storage`/boot globals fixup order and runtime layout
  stores. The capped profile now shows `x64_native_program.oren` at ~49.7s
  total / ~35.9s parse, with `_emit_intrinsic_sys_win_createthread_windows_x64`
  exposed at ~56ms as the next parser body.
- Windows x64 `sys_win_createthread` lowering now separates argument temp-state
  setup, Win64 `CreateThread(NULL,0,start,arg,0,NULL)` argument materialization,
  and the IAT call while preserving the function call-area stack slots and
  handle-in-`rax` result contract. The capped profile now shows
  `x64_native_program.oren` at ~47.0s total / ~33.8s parse, with
  `_emit_find_tracked_node_x64` exposed at ~43ms as the next parser body.
- X64 tracked-node lookup now separates runtime-injection validation, branch-label
  state, null/small-carrier guards, ABI argument loading, runtime index call
  emission, and local-fixup patching while preserving the
  `native_alloc_index_get(ptr)` recursion-avoidance contract. The capped profile
  now shows `x64_native_program.oren` at ~47.4s total / ~34.0s parse, with
  `_x64_emit_list_int_push_magic_guard` exposed at ~56ms as the next parser body.
- X64 list magic validation now shares the `*(list+24) == list_magic()` compare
  sequence across LIST/LIST_INT len, push, get, and set guards while preserving
  each guard's label, fallback, and panic-footer behavior. The capped profile now
  shows `x64_native_program.oren` at ~47.4s total / ~34.2s parse, with
  `_x64_collect_global_roots_from_vectors` exposed at ~63ms as the next parser
  body.
- X64 global-root vector collection now separates vector source validation,
  vector runtime-root classification, runtime-root skip policy, and shared
  trace+append emission across vector and map fallback paths while preserving
  scanned-count and fallback semantics. The capped profile now shows
  `x64_native_program.oren` at ~52.5s total / ~38.8s parse, with
  `_x64_spill_direct_call_args_v0` exposed at ~103ms as the next parser body.
- X64 fixed direct-call argument spilling now separates spill/call arity
  shaping, explicit left-to-right argument evaluation, and nil-padding for fixed
  direct arity while preserving temp-slot cleanup ownership and full-width value
  spills. The capped profile now shows `x64_native_program.oren` at ~46.9s total
  / ~33.7s parse, with `_emit_jcc_false_for_cond_x64` exposed at ~54ms as the
  next parser body.
- X64 conditional false-branch emission now separates argument validation and
  final cmp/Jcc fallback emission from the float, prefix-not, and truthy
  short-circuit paths while preserving branch polarity and false-label fixup
  behavior. The capped profile now shows `x64_native_program.oren` at ~48.5s
  total / ~35.0s parse, with `_x64_prepare_function_frame_v0` exposed at ~86ms
  as the next parser body.
- X64 function-frame preparation now separates local/temp/literal slot
  reservation, ABI frame-layout computation, and frame-map packing while
  preserving the no-code-emission contract and outgoing call-area sizing. The
  capped profile now shows `x64_native_program.oren` at ~52.2s total / ~37.7s
  parse, with `_emit_list_push_intrinsic_v0_x64` exposed at ~150ms as the next
  parser body.
- X64 LIST and LIST_INT push entry lowering now share two-argument validation,
  left-to-right spill/reload setup, fast/done label attachment, and nil-return
  cleanup while keeping type-specific checked bodies separate. The capped
  profile now shows `x64_native_program.oren` at ~46.9s total / ~33.8s parse,
  with `_emit_malloc_slow_windows_x64` exposed at ~55ms as the next parser body.
- Windows x64 malloc slow-path lowering now separates `VirtualAlloc` argument
  materialization, IAT call emission, and null-result guard routing while
  preserving heap-commit seeding and abort exit behavior. The capped profile now
  shows `x64_native_program.oren` at ~47.0s total / ~33.8s parse, with
  `_x64_fast_lcg_prepare_offsets` exposed at ~60ms as the next parser body.
- X64 fast-LCG preparation now lives in its own `057_emit_ops_while_lcg_prepare`
  module and splits local-offset lookup, offset validation, and GC-tick
  availability checks, reducing `057_emit_ops_while_emit.oren` to 1863 lines.
  The capped profile now shows `x64_native_program.oren` at ~49.3s total /
  ~34.2s parse, with `_x64_native_program_prepare_inputs` exposed at ~114ms as
  the next parser body.
- X64 fast list-get-sum while lowering now lives in
  `057_emit_ops_while_list_get_sum.oren`, preserving the original include-order
  boundary while reducing `057_emit_ops_while_emit.oren` to 1615 lines.
- X64 native-program input preparation now lives in `089_prepare_inputs` and
  separates runtime-object choice, runtime statement preparation, function-set
  preparation, and final prepare-state packing while preserving declaration
  order at the original tail include site. The capped profile now shows
  `x64_native_program.oren` at ~59.5s total / ~42.8s parse, with
  `_x64_fast_list_int_push_validate_tracked_list` exposed at ~225ms as the next
  parser body.
- X64 fast LIST/LIST_INT push validation now shares tracked-node lookup,
  expected-kind probing, and list-magic comparison helpers while preserving each
  fast path's slow-label routing and error return contract. The capped profile
  now shows `x64_native_program.oren` at ~62.4s total / ~45.0s parse, with
  `_x64_emit_top_string_batch_loop_body` exposed at ~148ms as the next parser
  body.
- X64 top-level string batch loop emission now separates slot-pointer
  materialization, C-string pointer storage, and loop cursor advancement while
  preserving the same table-walk instruction order and jump patch contract. The
  capped profile now shows `x64_native_program.oren` at ~49.0s total / ~35.2s
  parse, with `_x64_emit_resolve_symbol_symtab_setup` exposed at ~84ms as the
  next parser body.
- X64 panic symbol-table resolution setup now separates label/fixup state,
  fixed-base address guarding, symtab/data-base materialization, and scan-cursor
  initialization while preserving `r9` target-offset, `r8` data-base, `r10`
  count, `r11` entries-base, and `rbx` index contracts. The capped profile now
  shows `x64_native_program.oren` at ~47.4s total / ~34.1s parse, with
  `_x64_windows_fstat_emit_success` exposed at ~43ms as the next parser body.
- Windows x64 `sys_fstat` success emission now separates EBADF routing,
  `GetFileSizeEx` best-effort size probing, `OrenStatV0` zero/fill writes, and
  zero return-code setup while preserving console/pipe success-with-size-zero
  behavior. The capped profile now shows `x64_native_program.oren` at ~46.8s
  total / ~33.9s parse, with `_x64_windows_msg6_state` exposed at ~42ms as the
  next parser body.
- Windows x64 sendto/recvfrom six-argument state setup now matches the Linux
  msg path shape by separating temp-slot allocation, left-to-right argument
  spilling, and state-map packing while preserving temp cleanup on spill errors.
  The capped profile now shows `x64_native_program.oren` at ~46.5s total /
  ~33.6s parse, with `_emit_windows_write_cstr` exposed at ~43ms as the next
  parser body.
- Windows x64 literal C-string writing now separates C-string data registration,
  local Win64 shadow-space framing, stdout handle acquisition, WriteFile
  argument materialization, and IAT call emission while preserving the emitted
  instruction/fixup order. The capped profile now shows `x64_native_program.oren`
  at ~46.6s total / ~33.6s parse, with `_emit_var_i32_op_x64` exposed at ~43ms
  as the next parser body.
- X64 `var_i32` op emission now separates local-slot diagnostics, local fact-map
  updates, expression evaluation, and stack-slot storage while preserving the
  existing check/eval/store order. The capped profile now shows
  `x64_native_program.oren` at ~47.7s total / ~34.6s parse, with
  `_x64_fast_lcg_fullmod_emit_step` exposed at ~44ms as the next parser body.
- X64 fast-LCG full-mod step emission now separates `x` update, `x % mod`
  reduction, `x`/`i` term extraction, and sum reduction helpers while preserving
  the signed `cqo`/`idiv` arithmetic sequence and register contract. The capped
  profile now shows `x64_native_program.oren` at ~47.8s total / ~34.6s parse,
  with `_emit_while_op_x64` exposed at ~43ms as the next parser body.
- X64 `while` op emission now routes fast LCG, push, dot, and get specializations
  through focused handled/unhandled helpers before the generic fallback while
  preserving matcher priority. The capped profile now shows
  `x64_native_program.oren` at ~46.8s total / ~33.8s parse, with
  `_x64_match_fast_list_int_get_sum_body` exposed at ~43ms as the next parser
  body.
- X64 fast LIST/LIST_INT get-sum matching now shares step selection, sum-name
  consistency, local/list validation, load recording, and body finalization
  while preserving the LIST_INT-only inty proof checks. The capped profile now
  shows `x64_native_program.oren` at ~46.9s total / ~33.9s parse, with
  `_emit_intrinsic_sys_win_close_handle_windows_x64` exposed at ~42ms as the
  next parser body.
- Windows x64 `sys_win_close_handle` lowering now separates one-argument temp
  state setup, `CloseHandle` IAT call emission, and BOOL-to-`-EIO` result
  normalization while preserving the `rcx` handle ABI contract. The capped
  profile now shows `x64_native_program.oren` at ~47.5s total / ~34.3s parse,
  with `_x64_setup_symtab_display` exposed at ~107ms as the next parser body.
- X64 debug symtab display setup now lives in `089_symtab_display.oren`, splitting
  entry initialization, user function display formatting, generated-wrapper
  labels, and FFI labels while reducing `090_tail.oren` to 1915 lines. The
  capped profile now shows `x64_native_program.oren` at ~47.1s total / ~33.8s
  parse, with `_data_add_fnobj` exposed at ~41ms as the next parser body.
- X64 program debug metadata and global-root registration now live in
  `089_debug_roots.oren`, preserving the existing tail include order while
  reducing `090_tail.oren` to 1590 lines.
- X64 function-object data emission now separates data/map state setup,
  existing-offset decode, zeroed 16-byte object append, and code-pointer fixup
  registration while using the shared u64 data writer for both placeholder
  slots. The capped profile now shows `x64_native_program.oren` at ~46.9s
  total / ~33.9s parse, with `_x64_rtobj_allocate_runtime_globals` exposed at
  ~42ms as the next parser body.
- X64 runtime-object runtime-global allocation now separates name validation,
  reserved `g_storage` handling, duplicate detection, data-slot/root metadata
  recording, and completion logging while preserving allocation order. The
  capped profile now shows `x64_native_program.oren` at ~47.5s total / ~34.3s
  parse, with `_x64_rtobj_compile_runtime_decls` exposed at ~42ms as the next
  parser body.
- X64 runtime-object runtime-declaration compilation now mirrors the wrapper
  compiler loop with explicit state packing, start/progress/done logging,
  single-declaration compile routing, and top-declaration trace recording while
  preserving `_compile_function_v0` call order. The capped profile now shows
  `x64_native_program.oren` at ~47.8s total / ~34.5s parse, with
  `_emit_eval_infix_to_rax` exposed at ~42ms as the next parser body.
- X64 infix expression dispatch now separates float/string-concat pre-dispatch
  from scalar operator routing, keeping the hot infix evaluator as a thin
  dispatcher without changing operator lowering order. The capped profile now
  shows `x64_native_program.oren` at ~47.9s total / ~34.4s parse, with
  `_x64_gqcsx_normalize_result` exposed at ~41ms as the next parser body.
- Windows x64 `GetQueuedCompletionStatusEx` result normalization now separates
  result-label state, BOOL dispatch, timeout-aware `GetLastError` mapping,
  success emission, and final fixup patching while reusing the shared IOCP
  invalid-parameter/invalid-handle/default errno mapper. The capped profile now
  shows `x64_native_program.oren` at ~47.4s total / ~34.3s parse, with
  `_emit_named_function_value_to_rax` exposed at ~42ms as the next parser body.
- X64 named-function value lowering now separates wrapper-name construction,
  injected-runtime `oren_func` ABI setup, and static fnobj data materialization
  while preserving the handled/unknown return contract. The capped profile now
  shows `x64_native_program.oren` at ~49.6s total / ~36.1s parse, with
  `_emit_eval_ptr_store_intrinsic_x64` exposed at ~43ms as the next parser body.
- X64 pointer-store intrinsic lowering now separates two-argument validation,
  pointer spill, value evaluation, and width-specific store emission while
  preserving left-to-right evaluation and temp cleanup ownership. The capped
  profile now shows `x64_native_program.oren` at ~47.4s total / ~34.0s parse,
  with `_x64_emit_sys_write_windows_handle` exposed at ~41ms as the next parser
  body.
- Windows x64 `sys_write` handle routing now separates fd branch classification
  from `GetStdHandle` materialization and reuses the shared IAT-call helper for
  stdout/stderr handles while preserving direct HANDLE fd behavior. The capped
  profile now shows `x64_native_program.oren` at ~50.8s total / ~37.2s parse,
  with `_x64_fast_list_int_get_sum_emit_unroll2` exposed at ~46ms as the next
  parser body.
- X64 fast LIST_INT get-sum unroll-2 emission now separates list-index lookup,
  temp-slot resolution, two-value buffer load/advance, and loop-iteration finish
  helpers while preserving the existing r10/r13 cursor and sum contracts. The
  capped profile now shows `x64_native_program.oren` at ~47.3s total / ~34.1s
  parse, with `_x64_fast_list_int_get_sum_emit_single` exposed at ~41ms as the
  next parser body.
- X64 fast LIST_INT get-sum single-iteration emission now separates unique-list
  sequential loads, indexed loads, per-load accumulation, and loop-iteration
  finish helpers while reusing the shared list-index/temp-slot lookup helpers.
  The capped profile now shows `x64_native_program.oren` at ~47.7s total /
  ~34.5s parse, with `_x64_emit_sys_read_windows_readfile` exposed at ~40ms as
  the next parser body.
- Windows x64 `ReadFile`/`WriteFile` byte-count emission now shares buffer
  argument materialization, IAT call routing, byte-count loadback, and `-EIO`
  normalization helpers while preserving the read/write handle paths. The
  capped profile now shows `x64_native_program.oren` at ~47.7s total / ~34.5s
  parse, with `_x64_emit_resolve_loc_table_setup` exposed at ~41ms as the next
  parser body.
- X64 panic symbol/location table setup now shares resolver table state,
  fixed-text-base guards, data-base materialization, and cursor initialization
  while keeping `sym_*` and `loc_*` label prefixes intact. The capped profile
  now shows `x64_native_program.oren` at ~49.9s total / ~36.3s parse, with
  `_x64_string_batch_append_data` exposed at ~44ms as the next parser body.
- X64 top-level string-batch data append now separates data-state setup,
  per-item progress/timing/list recording, and final result packing while
  preserving item trace order and cstr0 list updates. The capped profile now
  shows `x64_native_program.oren` at ~47.1s total / ~33.7s parse, with
  `_emit_intrinsic_sys_linux_dup_x64` exposed at ~40ms as the next parser body.
- Linux x64 `sys_dup` lowering now mirrors the adjacent dup2/dup3 helper shape
  with temp-state setup, capsule prehook/spill, syscall emission, and capsule
  posthook helpers while preserving cleanup ownership. The capped profile now
  shows `x64_native_program.oren` at ~48.3s total / ~34.7s parse, with
  `_x64_emit_simd_dot_i32_ptr_scalar_tail` exposed at ~41ms as the next parser
  body.
- X64 SIMD i32 pointer dot scalar-tail emission now separates odd-count guard,
  last-element pointer advancement, scalar multiply-add accumulation, and jump
  patching while preserving the SSE2 vector-loop result in `rax`. The capped
  profile now shows `x64_native_program.oren` at ~48.2s total / ~34.9s parse,
  with `_emit_intrinsic_sys_linux_close_x64` exposed at ~41ms as the next parser
  body.
- Linux x64 `sys_close` lowering now separates arity/spread validation, fd temp
  state setup, fd evaluation plus capsule prehook spilling, syscall emission,
  and capsule posthook routing while preserving temp cleanup ownership. The
  capped profile now shows `x64_native_program.oren` at ~48.5s total / ~35.4s
  parse, with `_x64_prepare_sys_rw_linux_args` exposed at ~41ms as the next
  parser body.
- Linux x64 read/write argument preparation now separates shared temp-slot
  allocation, fd evaluation with capsule prehook spilling, and pointer/length
  left-to-right spilling while preserving cleanup on expression errors. The
  capped profile now shows `x64_native_program.oren` at ~52.0s total / ~38.4s
  parse, with `_x64_fast_list_int_get_sum_prepare` exposed at ~46ms as the next
  parser body.
- X64 fast LIST_INT get-sum preparation now separates name extraction,
  local-offset validation, loop-shape selection, whole-list helper gating,
  trace/temp-base allocation, and final state packing while preserving the
  returned prepare map. The capped profile now shows `x64_native_program.oren`
  at ~47.8s total / ~34.4s parse, with `_x64_match_fast_lcg_source` exposed at
  ~66ms as the next parser body.
- X64 fast-LCG source matching now separates assigned-variable validation,
  LCG update extraction, modulo source validation, and result packing while
  preserving index/count/source/mod conflict rejection. The capped profile now
  shows `x64_native_program.oren` at ~48.3s total / ~34.9s parse, with
  `_emit_global_string_init_batch_op_x64` exposed at ~41ms as the next parser
  body.
- X64 top-level global string batch emission now separates input/trace state
  preparation from data/table/code emission while preserving batch item
  collection, slow-op timing, and compact loop emission. The capped profile now
  shows `x64_native_program.oren` at ~48.0s total / ~34.7s parse, with
  `_x64_emit_lambda_literal_env` exposed at ~40ms as the next parser body.
- X64 lambda literal environment emission now separates empty-env storage,
  runtime list allocation, per-capture push lowering, and capture-loop routing
  while preserving temp cleanup on allocation/push errors. The capped profile
  now shows `x64_native_program.oren` at ~47.8s total / ~34.4s parse, with
  `_emit_eval_ptr_load_intrinsic_x64` exposed at ~40ms as the next parser body.
- X64 pointer-load intrinsic lowering now shares one-argument validation,
  pointer evaluation, and width-specific load emission across `ptr_get`,
  `ptr_get_byte`, and `oren_ptr_get_i32_le`. The capped profile now shows
  `x64_native_program.oren` at ~48.9s total / ~35.5s parse, with
  `_emit_intrinsic_sys_linux_signal_x64` exposed at ~40ms as the next parser
  body.
- Linux x64 `sys_kill` lowering now separates argument/spread validation,
  pid/signum temp-state setup, argument spilling, capsule prehook emission, and
  syscall emission while preserving handled/unhandled routing. The capped
  profile now shows `x64_native_program.oren` at ~51.1s total / ~37.3s parse,
  with `_x64_rtobj_apply_compact_function_offsets` exposed at ~46ms as the next
  parser body.
- Native HTTP/2 client response header-block and unknown-length DATA payload
  accumulation now uses amortized `u8_buf` builders, fragmented outbound HEADERS
  writes stream raw header-block spans instead of copied split buffers,
  single-CONTINUATION inbound header blocks exact-combine without an overcapacity
  finish copy, `content-length` DATA bodies use exact-capacity `u8_buf`
  accumulation with mismatch checks, and header-only responses with `END_STREAM`
  terminate without waiting for a DATA frame.
- X64 conditional branch and SETcc instruction builders now decode condition strings through byte-based opcode helpers and expose direct opcode builders; the central label and compare-not emitters use the numeric path to avoid repeated string-equality dispatch in hot branch emission.
- Renamer scope lookup now caches positive and negative results per parent-linked scope frame and updates the active frame cache on declaration. The focused `renamer_scope_cache_shadow_main` fixture proves the hot false-then-declare shadowing path still resolves a later local over an earlier imported module alias.
- X64 native index get/set lowering now emits a map-only path for proven map receivers and string-literal keys, delegates checked map validation to runtime helpers, and delegates unknown dynamic receiver get/set through generic runtime helpers instead of inlining full list+map dispatch at every parameter-local access; focused Linux/Windows compile-only coverage includes dynamic parameter-local index helpers. Compiler phase logging now appends through `oren_append_file` instead of reading and rewriting the whole trace per phase; the refreshed no-cache self-host trace reaches `link.optimizer.done`, global DCE, and `x64.codegen.ctx.done`, with x64 runtime-object markers showing the current cold-cache gap inside `x64.rtobj.build.start`. X64 function progress is now configurable with `OREN_TRACE_X64_FNS_PROGRESS_INTERVAL`; renamer visitor caching reduced focused no-cache `collect_toplevel_rename_pairs` emit from roughly 16s to about 11.4s and `scope_push` from about 8.6s to about 5.7s. Default optimizer phase logging now gates deep per-node counters and hot-function rankings behind `OREN_TRACE_OPTIMIZER_DETAIL=1`, reducing optimizer summary emission from about 21s to about 2ms in a compiler-shaped x64 trace. X64 string literal lowering now uses a bounded 32-entry C-string MRU before the existing data dedup map, and `rename_stmt` uses independent early-return branches instead of one nested `else if` chain; the focused compiler-shaped x64 trace reduced `rename_stmt` from about 64.8s to about 12.1s and moved the active diagnostic past `rename_expr`. X64 backend instruction emission now calls `x64_core` instruction builders directly instead of compiling a duplicate prelude forwarding layer; the compiler-shaped trace reduced linked x64 functions from 2598 to 2501. X64 function frames now reserve dedicated list/map literal spill slots only when a conservative ops scan finds list/hash literals; focused frame probes show literal-free `__top_level__` at `literal_slots=0` and list-literal `main` at `literal_slots=16`. Statement/expression branch helpers now keep renamer dispatch bodies smaller, with focused x64 probe evidence at about 61ms for `rename_stmt` and 57ms for `rename_expr`; annotation builtin checks are split by category, replacing the former roughly 57ms monolithic checker with about 20ms/15ms/15ms/6ms helper bodies. X64 base-memory and displacement instruction builders now append ModRM/SIB/displacement bytes directly through `_emit_mem_base_modrm_sib_disp` instead of allocating per-instruction metadata maps; Linux/Windows x64 compile-only gates cover the MOV, atomic, MOVDQU, and MOVDQA surface. X64 intrinsic-temp sizing now includes the live call spill slots held by array/hash literal builders, with the nested-map literal fixture covered by the default Linux/Windows x64 compile-only matrix. ELF/PE local-fixup dispatch now caches the fixup count and each fixup kind once, and PE uses single-branch shape dispatch; the focused nested-map Linux x64 probe shows local fixups at about 26ms. Runtime-object call-fixup replay now caches sidecar pointers/base metadata once and uses raw pointer u64 sidecar reads, moving the 15,924-call focused replay from about 289ms to about 237ms. X64 instruction builders now use `low3`/`u8` bit-mask helpers for ModRM/REX register packing and signed-byte emission instead of calling general positive modulo in the hot encoder path; shared byte-builder u16/u32 little-endian writes now mask signed values once and have a focused negative-width layout fixture. Remaining x64 hotspots are traversal helpers and broader real `x64_core` instruction-builder/user-function emission.
- Base64 decode now rejects interior padding and third-character padding without
  fourth-character padding plus nonzero trailing pad bits while keeping decoded
  output as exact-size `u8_buf`; strict Base64 decode sizes exactly and validates
  inline instead of pre-scanning then delegating to the whitespace-tolerant path.
  Base64/Base64URL encode now reads `u8_buf` inputs directly after one length
  check, and Base64URL decode uses the same direct byte-buffer output path.
- SHA-1/SHA-256 digest input validation now skips redundant per-byte scans for
  `u8_buf` carriers and virtual padded message expansion reads their backing
  bytes directly, while boxed byte-list fallback validation remains covered.
- HPACK header block encoding now carries Huffman string-literal byte lengths
  from the exact-size sizing pass into the write pass through `list_int`
  metadata, avoiding a second length-only scan and boxed per-literal length
  metadata while preserving exact-size `u8_buf` output and dynamic-table simulation.
- `std:ui/avm` frame payload appends now copy `u8_buf` command payloads directly
  into exact-size OGF0 frame buffers, keeping list-compatible payload fallback for
  non-u8 byte carriers.
- `std:ui/avm` event decoding now caches u8 event-buffer pointers for OGE0
  magic/opcode/payload-length reads while retaining list-compatible byte input.
- `std:cbor` byte-string encoding plus recursive and sequence decoding now carry
  one cached byte view with length and optional u8 carrier pointer per operation
  while retaining list-compatible byte input fallback.
- `std:bytes` now exposes shared big-endian byte-view readers, and CBOR decode
  uses them directly instead of maintaining local endian read wrappers.
- `std:ui/commands` validation now caches u8 payload pointers for geometry,
  indexed-mesh, text-position, and image-rect byte fields while retaining
  list-compatible byte input fallback.
- `std:ui/raster` now caches byte views for polyline, triangle, 3D mesh,
  text-position, image RGBA, mesh RGBA, and image-rect byte reads, calls shared
  `std:bytes` unchecked view readers directly inside guarded hot loops, and keeps
  explicit image-data length guards before pointer-backed sampling.
- `std:ui/scene3d` binary `.os3d` package magic, header, table reads, and
  payload slices now reuse one cached byte view with length and optional u8
  pointer while keeping list-compatible byte input fallback.
- `std:ui/ppm` now reuses one cached u8 input pointer while emitting P6 RGB
  bodies, avoiding per-channel input pointer lookups for u8 RGBA sources.
- `std:ui/avm` OGE0 event decoding now reads magic, opcode, payload length, and
  little-endian payload fields through shared `std:bytes` view readers after
  event/header/payload length checks.
- `std:buffer` slice/strided/matrix byte-copy fallbacks now cache u8 source
  pointers for non-contiguous destinations while retaining list-compatible byte
  fallback.
- Bytecode metadata constants are now formed as byte-native UTF-8 payloads, and
  direct/link bytecode emission gates use carrier-aware byte lengths for metadata
  and OBX payloads.
- OBC/OBX parsing, global-count scanning, opcode-length dispatch, and linked-code
  patching now reuse one cached byte view per carrier, avoiding repeated u8-buffer
  type, pointer, and length lookups while preserving list-compatible byte input.
- Compiler-in-AVM VirtualFS fixture snapshots now build AVMVFS01 payloads with
  exact-size `u8_buf` writes and return matched bodies through byte-buffer slices
  instead of boxed byte lists.
- iOS `OrenAVMKit` builds as an xcframework and verifies TIME, FS, VNET, VPROC,
  GFX/input, package store, trust bundle, permission grant persistence, and
  compiler-in-AVM smoke paths through `make verify-libavm-ios`.
- `std:ui/scene3d` package coordinate and generated primitive meshes now accept validated
  authoring-time `scale_xyz_milli`, `pivot_xyz`, `rotation_xyz_milli_deg`
  (with `rotation_z_milli_deg` shorthand), and `translation_xyz` transforms
  for `triangles_xyz`, `quads_xyz`, `vertices_xyz`, flat indexed `vertices_xy`, `triangles_xyz_rgba`,
  `boxes_xyz`, `prisms_xy`, bounded `heightfields_xy` terrain grids, bounded
	  `surfaces_xyz` arbitrary surface grids, flat indexed `vertices_xy`, flat `triangles_xy`/`quads_xy`, flat per-triangle-color `triangles_xy_rgba`/`quads_xy_rgba`, rectangular `planes_xy`/`rects_xy`, filled `rounded_rects_xy`, flat `polygons_xy`,
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
- AVM `oren_bytes_get_u8` and endian read/write intrinsics now share
  overflow-safe byte-span checks across byte buffers, boxed byte lists, and
  packed `LIST_INT` read carriers; `tests/avm/test_bytes_set_endian.oren`
  covers direct endian reads.
- Native-runtime byte-order helpers now use the same overflow-safe byte-span
  predicate for boxed byte lists and u8 buffers, and endian reads accept packed
  `LIST_INT` carriers; `tests/native/test_bytes_set_endian.oren` and native
  quick integration cover direct and `pack_view`-generated paths.
- Native-runtime byte helper APIs now include packed `LIST_INT` carriers in
  `bytes_len`, `bytes_pack`, `bytes_unpack`, hex, and slice conversions, with
  overflow-safe slice range checks in the string/u8-buffer slice helpers.
- C-runtime byte slice helpers now share the same overflow-safe range predicate,
  with module coverage proving list-int byte carriers across length, endian
  reads, pack/unpack, hex, string slices, and u8-buffer slices.
- AVM byte helper intrinsics now match that list-int carrier surface for hex and
  slice conversion, keeping the module fixture green across native, C, and
  bytecode backends.
- ARM64 native runtime debug-info records now include the required zero
  parameter-count word, and the ARM64 rtobj backend signature invalidates stale
  debug sidecars; `scripts/verify_arm64_macho_debug_table.py` verifies the
  emitted Mach-O table shape for postmortem native-QI symbolication.
- Compiler byte builders now expose one `bytes_extend_carrier` path for u8
  buffers, byte lists, and packed `LIST_INT` carriers; bytecode and OBC
  emitters use it for length-prefixed `Bytes` constants and final code payloads.
- OBC linker unpatched code-span copies now append directly from cached u8
  pointers through `bytes_extend_ptr`, preserving byte-list fallback for legacy
  carriers while avoiding per-byte runtime helper calls on parsed OBC code.
- AVM `oren_sha256_range` now matches native/C byte-carrier parity for u8
  buffers, boxed byte lists, and packed `LIST_INT` carriers; the tail native
  cases live in a separate include so `avm_native.inc` stays below the source
  guardrail.
- iOS `OrenAVMMetalView` retained 3D painter ordering now builds one compact
  visible-triangle order buffer and sorts by depth with original-index ties,
  avoiding per-triangle Objective-C allocations and repeated full rescans in
  the frame path; small retained 3D draws use stack order storage, and large
  draws use raw heap order buffers freed after sorting/drawing.
- iOS `OrenAVMGraphicsView` retained 3D painter ordering now uses the same
  compact visible-triangle order buffer for indexed and packed 3D meshes,
  removing per-triangle `NSNumber`/`NSMutableSet` allocations and repeated
  full rescans from the CoreGraphics fallback path; it also uses stack order
  storage for small retained 3D draws and raw heap order buffers for larger
  draws.
- `make verify-libavm-ios` now guards the CoreGraphics retained-3D fallback
  against regressing to boxed set-based painter tracking or Objective-C data
  wrappers for large order buffers.
- iOS `OrenAVMMetalView` live drawing and drawable-independent
  `prepareFrameResourcesWithError:` now share one prepared-frame path for
  vertex/image/text run construction, text-run coalescing, clear color, and
  frame metric counts so verifier and live renderer behavior cannot drift.
- iOS `OrenAVMMetalView` now keeps small vertex uploads inline but promotes
  large geometry/image/text vertex payloads to transient `MTLBuffer` objects
  retained through command completion, avoiding unbounded `setVertexBytes`
  usage for retained meshes and batches.
- `make verify-libavm-ios` now guards that Metal vertex uploads keep direct
  `setVertexBytes` usage inside the bounded helper and retain large transient
  `MTLBuffer` uploads through command completion.
- Metal large transient vertex uploads now retain their existing per-command
  buffer tracking array through command completion instead of copying that array
  after encoding.
- Metal geometry vertex-run flushing now transfers raw growable vertex buffers
  into run ownership instead of retaining `NSMutableData` wrappers at
  clip/transform/opacity/camera boundaries.
- Metal geometry vertex builders now stay lazy but reserve a small
  op-count-bounded initial capacity on first append instead of growing from a
  zero-capacity buffer.
- Metal batched text-run construction now writes positioned glyph quads directly
  into one raw run-owned vertex buffer instead of wrapping variable vertices in
  `NSMutableData`.
- Metal text-run coalescing now reuses prepared run objects for non-merged
  groups, keeps their inline or raw heap vertex data, and only grows raw
  run-owned storage when a same-texture/scissor/opacity run actually merges.
- Metal coalescing appends adjacent compatible text runs into the first run's
  raw vertex buffer, avoiding Objective-C data wrappers on batched text merges.
- Metal text cache hits now return before constructing UIKit color/attribute
  objects, keeping repeated labels on the cached texture path.
- Metal text cache misses now render glyphs into raw temporary pixel buffers
  instead of allocating `NSMutableData` wrappers before texture upload.
- Metal text atlas creation now avoids a full zeroed atlas upload buffer and
  clears only the transparent padding texels around packed glyph regions.
- Metal frame preparation now keeps run capacity byte-bounded while allocating
  geometry/text/image run arrays lazily only when the frame actually contains
  those records.
- Retained Metal mesh, material, and text resource colors now store 4-byte RGBA
  values as scalars instead of allocating `NSData` wrappers for each color.
- Retained Metal 3D material override draws now unbox the material RGBA once per
  draw instead of sending `NSNumber.unsignedIntValue` inside triangle loops.
- CoreGraphics retained mesh/material fallback records now use typed mesh
  resources, scalar-key mesh lookup, and scalar RGBA material values instead of
  dictionary payloads, boxed mesh IDs, and retained `UIColor` material objects.
- CoreGraphics and Metal retained mesh payloads now live in raw resource-owned
  buffers instead of retained `NSData` wrappers, preserving lifetime safety while
  removing per-mesh payload objects from retained draw paths.
- CoreGraphics immediate primitive draws now set fill/stroke colors from raw
  RGBA bytes instead of allocating per-draw `UIColor` wrappers.
- CoreGraphics retained text fallback records now use typed resources with
  cached attributed strings instead of dictionary payloads, separate resource
  attribute dictionaries, per-draw attributes dictionaries, or boxed retained
  text ID lookup.
- CoreGraphics immediate and retained text paths now cache UIKit text
  attributes by RGBA value instead of rebuilding `UIColor`/attribute
  dictionaries for repeated text colors, with a scalar one-entry MRU before
  scalar-key cache lookup and storage.
- CoreGraphics retained image fallback records now use typed resources for image
  plus pixel accounting instead of parallel image/pixel dictionaries, with
  overflow-safe retained sub-rect bounds checks, shared checked sub-rect drawing,
  scalar-key retained image lookup, cached image dimensions for batched atlas
  rects, and provider-owned raw upload bytes instead of intermediate `NSData`
  wrappers.
- Retained Metal image resources now use typed texture/pixel records instead of
  parallel texture/pixel dictionaries, with overflow-safe upload accounting and
  sub-rect UV bounds checks, scalar-key retained image lookup, and cached texture
  dimensions for batched image rects.
- Metal retained 2D/3D mesh resources now use scalar-key maps instead of boxed
  mesh ID dictionary keys.
- CoreGraphics and Metal retained model resources now use typed resource records
  instead of string-keyed dictionaries, removing per-draw model field lookups and
  boxed model ID lookups.
- CoreGraphics and Metal retained material resources now use scalar-key/scalar
  value maps instead of boxed material ID and RGBA `NSNumber` objects.
- Single Metal image texture quads now stay inline in fixed image-run storage,
  while text texture quads append into caller-owned run buffers instead of
  allocating tiny `NSData` wrappers from stack vertices.
- Metal text cache misses now share a typed view-owned UIKit attribute cache
  with a scalar one-entry MRU before scalar-key cache lookup and storage, and
  CoreGraphics/Metal retained text resources use scalar-key lookup for text IDs.
- Private Metal retained run/resource records and the raw payload-copy helper now
  live in `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1874 lines
  and preserving source-line guardrail headroom for continued renderer work.
- Metal primitive vertex/RGBA geometry helpers now live in
  `OrenAVMMetalGeometry`, reducing `OrenAVMMetalView.m` to 1585 lines while
  keeping draw-command parsing and run flushing in the view.
- Metal shader and render-pipeline setup now lives in `OrenAVMMetalPipeline`,
  reducing `OrenAVMMetalView.m` to 1680 lines while keeping frame parsing and
  draw submission in the view.
- Metal frame byte/scissor/run-array and bounded vertex-upload helpers now live
  in `OrenAVMMetalFrame`, reducing `OrenAVMMetalView.m` to 1522 lines while
  keeping command decoding in the view.
- Metal retained-resource scalar key and lookup helpers now live in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1464 lines while
  keeping resource lifetime callbacks with the resource model types.
- Metal retained-3D painter ordering, depth-window, and model-coordinate helpers
  now live in `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to
  1394 lines while keeping per-frame draw decisions in the view.
- Metal frame timing and target-budget helpers now live in
  `OrenAVMMetalFrame`, reducing `OrenAVMMetalView.m` to 1384 lines while
  keeping lifecycle, input, and draw decisions in the view.
- Metal image-run sub-rect validation and quad construction now lives in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1357 lines while
  keeping retained image upload budgets and pixel accounting in the view.
- Metal retained-image upload/remove helpers now live in `OrenAVMMetalResources`,
  reducing `OrenAVMMetalView.m` to 1328 lines while keeping view-owned budget
  configuration and scalar-map lifetime ownership intact.
- Metal retained text/material/model resource upload/remove helpers now live in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1307 lines while
  keeping per-frame retained draw decisions in the view.
- Metal retained 2D/3D mesh resource copy/store/remove helpers now live in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1292 lines while
  leaving command payload validation and retained draw decisions in the view.
- Metal retained 2D mesh draw payload expansion now lives in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1276 lines while
  keeping retained draw opcode routing in the view.
- Metal retained 3D mesh/model/material draw payload expansion now lives in
  `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 1165 lines while
  keeping retained 3D opcode routing in the view.
- Metal immediate primitive draw payload expansion now lives in
  `OrenAVMMetalGeometry`, reducing `OrenAVMMetalView.m` to 1033 lines while
  keeping full-frame clear-color policy, state stacks, and opcode routing in
  the view.
- Metal retained-image upload/remove/draw/sub-rect/batched image opcode handling
  now lives in `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to
  915 lines while keeping retained image budget configuration in the view.
- Metal immediate and retained text upload/draw/batched/destroy opcode handling
  now lives in `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to
  833 lines while keeping the text cache, atlas, and attribute-cache ownership
  in the view.
- Metal retained mesh/material/model upload/draw/remove opcode handling now
  lives in `OrenAVMMetalResources`, reducing `OrenAVMMetalView.m` to 747 lines
  while keeping frame transforms, depth windows, and vertex output in the view.
- Metal clip/transform/opacity/camera state stacks and opcodes now live in
  `OrenAVMMetalFrame`, reducing `OrenAVMMetalView.m` to 676 lines while keeping
  per-frame resource/text/image command routing in the view.
- Metal full-frame clear-color detection now lives in `OrenAVMMetalFrame`,
  reducing `OrenAVMMetalView.m` to 663 lines while keeping per-frame
  resource/text/image command routing in the view.
- Metal prepared geometry/image/text draw submission now lives in
  `OrenAVMMetalFrame`, reducing `OrenAVMMetalView.m` to 628 lines while keeping
  MTKView lifecycle, prepared-run orchestration, and input forwarding in the view.
- Metal OGF0 command traversal now lives in `OrenAVMMetalFrame` behind a
  context struct that carries view-owned caches and retained resource maps,
  reducing `OrenAVMMetalView.m` to 544 lines while keeping MTKView lifecycle,
  prepared-run orchestration, and input forwarding in the view.
- CoreGraphics and Metal UIKit touch forwarding now share `OrenAVMGFXInput`
  scalar touch-ID helpers, keeping per-view `CFMutableDictionary` ownership
  while reducing `OrenAVMMetalView.m` to 510 lines and `OrenAVMGraphicsView.m`
  to 1249 lines.
- CoreGraphics retained resource models, scalar map keys/lookups, raw payload
  copy, and retained-3D painter ordering helpers now live in
  `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to 1070 lines
  while keeping frame traversal and CoreGraphics draw decisions in the view.
- CoreGraphics retained image RGBA upload, count/pixel budget mutation,
  removal accounting, and checked sub-rect drawing now live in
  `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to 983 lines
  while keeping image opcode routing in the view.
- CoreGraphics text attribute cache lookup plus immediate/retained text
  upload, draw, batched draw, and destroy helpers now live in
  `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to 922 lines
  while keeping text opcode routing in the view.
- CoreGraphics retained 2D/3D mesh, material, and model upload/remove helpers
  now live in `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to
  889 lines while keeping retained draw decisions in the view.
- CoreGraphics retained 2D mesh draw payload expansion now lives in
  `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to 876 lines
  while keeping retained draw opcode routing in the view.
- CoreGraphics retained 3D mesh/model/material draw payload expansion now lives
  in `OrenAVMGraphicsResources`, reducing `OrenAVMGraphicsView.m` to 761 lines
  while keeping retained 3D opcode routing in the view.
- CoreGraphics immediate primitive payload expansion now lives in
  `OrenAVMGraphicsGeometry`, reducing `OrenAVMGraphicsView.m` to 615 lines
  while keeping frame state stacks and retained resource routing in the view.
- CoreGraphics frame validation plus clip/transform/opacity/camera state-stack
  opcodes now live in `OrenAVMGraphicsFrame`, reducing
  `OrenAVMGraphicsView.m` to 527 lines while keeping retained resource
  routing in the view.
- CoreGraphics OGF0 command traversal now lives in `OrenAVMGraphicsFrame`
  behind a draw-context struct carrying view-owned retained resource maps,
  attribute caches, and image budgets, reducing `OrenAVMGraphicsView.m` to
  310 lines while preserving UIKit ownership in the view.
- AVM deadline-backed scheduler wait scanning now lives in
  `avm_vm_deadline_waits.inc`, reducing `avm_vm.c` to 1961 lines, and the iOS
  verifier now shares `scripts/obc_to_c_header.py` for embedded OBC fixture
  headers, reducing `verify_libavm_ios.sh` to 1923 lines.
- AVM VM helper definitions now live in `avm_vm_helpers.inc`, reducing
  `avm_vm.c` to 1828 lines while keeping dispatch-loop control flow in place.
- AVM VM call, closure, spawn, indirect-call, and spread-construction opcode
  cases now live in `avm_vm_call_spread_cases.inc`, reducing `avm_vm.c` to
  1424 lines while preserving dispatch case order.
- AVM native typed-buffer dot slice/strided cases now live in
  `avm_native_buffer_cases_e.inc`, reducing `avm_native_buffer_cases_b.inc` to
  1583 lines while preserving native-op case order.
- AVM CLI argument parsing now lives in `avm_main_parse_args.inc`, reducing
  `main.c` to 1608 lines while preserving the existing parse/return flow.
- AVM native byte/iterator conversion cases now live in
  `avm_native_byte_iter_cases.inc`, reducing `avm_native.inc` to 1434 lines and
  keeping byte-hotpath compatibility cases in one review boundary.
- Scene3D PLY/STL source lowering now lives in `scripts/scene3d_ply_stl.py`,
  reducing `make_scene3d_bin_v0.py` to 1523 lines while preserving byte-identical
  `.os3d` output for the package demo asset.
- iOS SDK verifier local NET/TCP/UDP/WebSocket/static-package helper servers
  now live in `scripts/libavm_ios_verify_net_helpers.py`, reducing
  `verify_libavm_ios.sh` to 1761 lines while keeping the same network smokes.
- Windows runtime once/atomic compatibility shims now live in
  `010_prelude_windows_once_atomics.inc`, reducing `010_prelude.inc` to 1990
  lines while keeping the platform-specific prelude boundary explicit.
- Runtime GC marking and spawn-entry helpers now live in
  `010_prelude_gc_mark_spawn.inc`, reducing `010_prelude.inc` to 1805 lines and
  restoring headroom for prelude changes.
- Runtime SHA-256 helpers now live in `050_io_misc_sha256.inc`, reducing
  `050_io_misc.inc` to 1705 lines while preserving IO/misc include order.
- Example build and cross-compile smoke targets now live in `mk/examples.mk`,
  reducing the top-level `Makefile` to 1883 lines and preserving source-line
  guardrail headroom as verification targets continue to grow.
- Native all-test, full verify, AVM build, and libavm verification targets now
  live in `mk/native_avm.mk`, reducing the top-level `Makefile` to 1732 lines
  while preserving the existing target names and include-time variable scope.
- Native quick integration math/module/codec follow-on smokes now live in
  `scripts/native_quick_math_followon_smokes.sh`, reducing
  `run_native_quick_integration.sh` to 1578 lines while preserving the same
  sourced retry and logging context.
- Scene3D invalid JSON/package validation assertions now live in
  `tests/avm/includes/test_ui_scene3d_invalid_cases.oren`, reducing
  `test_ui_scene3d_v0.oren` to 1782 lines without changing the curated AVM
  fixture entrypoint.
- Std math inverse-trig and hypotenuse helpers now live in
  `std/math/atan_hypot.oren`, reducing `std/math.oren` to 1738 lines while
  preserving the `std:math` import surface through compile-time include
  expansion.
- iOS SDK symbol verification now caches `nm` output once per archive and
  greps files instead of SIGPIPE-prone `nm | grep -q` pipelines.
- AVM `oren_read_u8_buf` now maps to a byte-native FS capability op that reads
  host and VFS files directly into AVM byte buffers instead of bridging through
  a boxed `list<int>` byte array.
- `std:ui/scene3d.commands_from_binary_file` now loads `.os3d` assets through
  that byte-native read path instead of materializing a legacy `list<int>`.
- AVM VFS and multiverse demo paths plus the iOS host-FS chain fixture now use
  `oren_read_u8_buf` directly for binary payload reads instead of
  `oren_read_bytes` plus list-shaped validation or repacking.
- The PPM write roundtrip fixture now reads generated binary image output through
  `oren_read_u8_buf` instead of the legacy `oren_read_bytes` list bridge.
- The AVM VFS no-host-FS fixture now validates in-memory VFS binary reads through
  `oren_read_u8_buf` instead of the legacy list bridge.
- Native capsule FS read/mount fixtures now validate binary reads through
  `oren_read_u8_buf`, preserving FS policy coverage without boxing bytes.
- Legacy native `oren_read_bytes` still exists for explicit compatibility callers,
  but it now fills a stat-sized native `LIST_INT` directly from 1 MiB read chunks
  instead of per-byte `oren_list_push` growth.
- Legacy AVM host and VFS `oren_read_bytes` compatibility paths now also
  materialize pre-sized `LIST_INT` carriers directly instead of boxed `AvmValue`
  byte-list entries; the host path now fills the returned `LIST_INT` directly
  from bounded 64 KiB file chunks instead of allocating a full-size AVM heap
  byte mirror first.
- Legacy AVM host `oren_write_bytes` now keeps list-input compatibility but
  validates list bytes before opening the destination and streams bounded
  64 KiB stack chunks instead of allocating a full-size AVM heap byte mirror.
- Legacy AVM VFS list-backed `write_bytes` now stores bytes directly into the
  final VFS entry buffer instead of first building a full-size temporary byte
  mirror and then copying it into VFS storage.
- Legacy C runtime `oren_read_bytes` still returns a boxed compatibility byte
  list, but now fills that list from bounded 64 KiB read chunks instead of
  allocating a second full-file temporary byte buffer before list materialization.
- Legacy C runtime `oren_write_bytes` now keeps list-input compatibility but
  validates the full list before opening/truncating the destination and writing
  bounded 64 KiB stack chunks, avoiding the former full-size temporary byte
  mirror while preserving invalid-input no-clobber behavior.
- Legacy native `oren_write_bytes` now mirrors that contract for self-hosted
  tests: it validates list bytes and allocates only a bounded scratch chunk
  before opening/truncating the destination, then streams short-write-safe
  chunks instead of materializing a full-size byte mirror.
- `std:fs` now exposes explicit `read_u8_buf`/`read_u8_buf_under` facades for
  new byte-buffer callers while keeping `read_byte_list` as the legacy list ABI.
- The iOS SDK now transfers embedder-returned stdout, VFS, GFX frame, and
  permission-request byte buffers directly into `NSData` ownership instead of
  copying the bytes and then freeing the original buffer.
- The iOS SDK live VNET session maps now store socket fds, session kinds, and
  byte counters through scalar-key CF dictionaries instead of boxed `NSNumber`
  session dictionaries.
- The iOS SDK host-backed WebSocket handshake path now generates keys, sends the
  ASCII upgrade request, and accumulates the response header through raw
  stack-first buffers instead of transient `NSData`/`NSMutableData` wrappers.
- iOS host-backed WebSocket session writes and reads now use typed AVM embed
  payload callbacks so string writes/`recv_text` use opcode-1 text frames,
  byte writes/`recv`/`recv_bytes` use opcode-2 binary frames, and outbound
  frames use small masked stack-first buffers before heap fallback.
- `OrenAVMRunResult` now preserves immutable no-copy stdout data without
  recopying it, while still copying mutable inputs defensively.
- The iOS package installer now borrows stored ZIP entry byte slices directly
  from the release bundle during CRC/write instead of copying each stored entry.
- iOS package-store hex decode, raw-deflate inflation, and publisher signature
  message wrapping now use raw/no-copy buffers instead of `NSMutableData` or
  string-to-`NSData` copy helpers.
- CompilerKit `compileSource` now encodes source strings into stack-first raw
  UTF-8 buffers before the synchronous VFS copy instead of using
  `dataUsingEncoding`.
- `make verify-libavm-ios` now guards the SDK embed-byte ownership contract so
  hot returned byte buffers do not regress to copy/free handoff.
- Metal single texture-quad emission now appends the six text/image vertices
  directly into caller-owned run buffers, avoiding tiny `NSData` wrappers and a
  temporary mutable-data append/copy pair for common single-run draws.
- Metal text texture cache lookups now use typed immutable cache keys instead
  of formatted strings that copy the full label into every lookup key.
- iOS SDK typed GFX input helpers now build fixed-size `OGE0` events on stack
  and enqueue raw bytes directly; text/composition events use segmented
  stack-first construction, encode UTF-8 directly into the final event buffer,
  and use one raw heap event fallback, not an Objective-C data wrapper, only
  for large payloads.
- CoreGraphics and Metal touch tracking now store active touch pointer IDs as
  raw scalar values instead of retaining per-touch `NSNumber` boxes, and both
  renderers now share the `OrenAVMGFXInput` touch forwarding helper while
  keeping their per-view maps.
- CoreGraphics retained resource models, scalar map keys/lookups, raw payload
  copy, and retained-3D painter ordering helpers now live in
  `OrenAVMGraphicsResources`, matching the Metal resource-module boundary.
- CoreGraphics retained image upload/remove/sub-rect helpers now also live in
  `OrenAVMGraphicsResources`, keeping budget accounting with the resource map.
- CoreGraphics text attribute cache lookup and retained text upload/draw/remove
  helpers now live in `OrenAVMGraphicsResources`, matching the Metal retained
  text resource-module boundary.
- CoreGraphics retained mesh/material/model mutation helpers now also live in
  `OrenAVMGraphicsResources`, keeping typed resource construction and raw
  payload ownership with the resource model types.
- CoreGraphics retained 2D mesh drawing now also lives in
  `OrenAVMGraphicsResources`, matching the Metal retained 2D mesh draw boundary.
- CoreGraphics retained 3D mesh/model/material drawing now also lives in
  `OrenAVMGraphicsResources`, matching the Metal retained 3D draw boundary.
- Bytecode final artifact writes now report the original `u8_buf`
  `oren_write_bytes` error directly instead of unpacking the entire generated
  bytecode into a legacy `list<int>` fallback on any write failure; the
  bytecode-link smoke now guards that the fallback stays removed.
- Runtime-object cache metadata check endian reads now validate each u8-buffer
  span once and read through one cached pointer, instead of revalidating and
  reloading the buffer pointer for every byte.
- Runtime-object cache metadata check magic validation now reuses the already
  validated check-buffer pointer instead of routing each magic byte through the
  checked byte helper.
- Runtime-object cache metadata check magic/version/length/hash reads now use
  the shared compiler byte-view readers instead of carrying local u8-only endian
  helpers.
- `make verify-avm-bytes-hotpath-guards` now centralizes byte-hotpath source
  invariants, including the removed bytecode final-write list fallback and the
  removed runtime-object per-byte checked metadata helper. It also prevents
  `std:ui/commands`, `std:ui/raster`, and `std:ui/avm` from reintroducing local
  byte-view/read aliases instead of using shared `std:bytes` views directly.
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
  delta, shortest-path angle interpolation helpers, pure `std:math/vec2`
  helpers for common 2D graphics/vector operations including component rounding, interpolation, range-mapping, direction/move-toward navigation, segment projection/distance, angle wrapping/interpolation, trig/sin_cos, and inverse-trig helpers,
  pure `std:math/vec3` helpers for common 3D vector operations including component rounding, interpolation, range-mapping, direction/move-toward navigation, segment projection/distance, angle wrapping/interpolation, trig/sin_cos, and inverse-trig helpers, and pure finite
  `std:math/vec4` helpers for homogeneous/vector algebra including component rounding, interpolation, range-mapping, direction/move-toward navigation, segment projection/distance, angle wrapping/interpolation, trig/sin_cos, and inverse-trig helpers, backed by native/C/
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
