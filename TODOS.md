# TODOs

This file is a concise pointer for active reweighted work. Detailed historical status remains in `docs/STATUS.md`, and focused evidence notes live under `project-doc/`.

## P1 / W4 - AVM iOS Production Readiness

- Keep the new `make verify-libavm-ios` gate green. It now builds `LibAVM.xcframework`, exports the embedder headers, compiles a tiny Oren source to `.obc`, links that bytecode into iOS device/simulator smoke binaries, and runs the same `.obc` through the host embed API with argv plus VirtualFS input/output, VirtualNET fixtures, VirtualPROC fixtures/default exits, and captured stdout retrieval/clear.
- Keep `make verify-compiler-in-avm-ios-chain` green. It now builds `stdlib_bundle.obc` and `oren.obc`, runs the compiler `.obc` inside AVM with VirtualFS stdlib resources, extracts `out.obc`, and runs the compiled output.
- Continue the iOS host-adapter SDK (`OrenAVMKit`) after the retained TIME-first slice. Current SDK package builds `OrenAVMKit.xcframework`, exposes deterministic and interactive app defaults, runs OBC on virtual FS/NET/PROC with stdout capture, and verifies wall-clock `time.sleep_ms` through the SDK smoke. Next: explicit app-sandbox FileProvider, URLSession allowlist NetworkProvider, compiler helper package, and GFX last after the mailbox exists. Design note: `project-doc/ios_avm_sdk_design_20260531.md`.
- Add a Swift/Objective-C iOS smoke host that opens `AvmEmbedHandle`, loads bundled `.obc` resources, feeds source/stdlib files through `avm_embed_vfs_put`, extracts `out.obc` through `avm_embed_vfs_get`, injects optional deterministic network/process fixtures with `avm_embed_vnet_put` and `avm_embed_vproc_put`, runs with virtual FS/PROC/NET, and reports `AvmEmbedResult` plus captured stdout into the Note UI.
- Design and gate an AVM graphics bridge for iOS: Oren emits deterministic 2D/3D command buffers; `libavm` validates capability/budgeted frame and input mailboxes; host apps can use Oren-maintained platform adapter SDK components instead of hand-writing every UIKit/Metal bridge. Design note: `project-doc/avm_ios_graphics_design_20260529.md`.
- After the GUI bridge release gate, create a curated signed public OBC store repo so the iOS app can download, verify, and run OBC app experiences. Design note: `project-doc/obc_store_distribution_design_20260529.md`.
- Add an AVM fixture manifest runner: fixture path, expected return code/error, required env budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion.
- Add an AVM stdlib-bundle manifest: include portable pure/capability-backed modules by default, record excluded host-only modules with reasons, and gate bundle size/build time plus an OBC-link smoke for each exported module. `std:time` is now required because app code can link `STD_time_sleep_ms` through `--stdlib-mode obc`.
- Expand compiler-in-AVM packaging from the current smoke gate to app-bundle resource loading and broader compiler/stdlib surface coverage.
- Finish embedder lifecycle hardening: make allocator ownership reentrant or explicitly single-VM guarded, define app-level failure policy for teardown leaks, and keep host-only subprocess paths unavailable in iOS builds.

Evidence and verdict: `project-doc/ios_avm_readiness_20260507.md`.

## P1 / W4 - Scientific Math Stdlib

- Keep `std:math` host-libm-free and bytecode/AVM-gated for app embedding. `pow` / `power` now cover integer, negative, and fractional positive-base exponents including `power(2,-1)` and `power(2,4.3)`.
- Continue expanding toward C/C++ mathlib breadth with focused fixtures for each function family before exposing it as app-stable.

## P3 / W2 - Language Ergonomics

- Add anonymous imports after higher-priority AVM app surfaces are gated. Proposed syntax: `import . "std:math"` to bring public module entities into the current namespace; optionally consider `use "std:math"` only if it does not conflict with existing grammar or dependency scanning. The implementation must define collision rules, visibility behavior, cache/import-scan support, and cross-backend fixtures before retention.
