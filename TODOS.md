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
| AVM-IOS-GFX-METAL | P1 | W5 | todo | Add game-grade Metal/`MTKView` GUI path with retained resources, display-link pacing, richer drawing/input records, and frame budget gates. | `make verify-libavm-ios && make test-avm` |
| AVM-IOS-STORE-DEMOS | P1 | W4 | todo | Create curated demo OBC programs/packages for the `store.hubstack.cn` OBC store site so iOS host apps can download and run useful examples after GUI/network gates. | `make verify-libavm-ios` |
| OBC-STORE-SERVICE | P1 | W4 | doing | Complete the `store.hubstack.cn` Go registry/API service. First slice has publisher/package/release publish, public index/search/download, and yanking; remaining work is signed index generation, deployment, auth hardening, and SDK end-to-end install smoke. | `make verify-obc-store-service` plus SDK end-to-end install smoke |
| AVM-IOS-PERM-UX | P1 | W4 | todo | Package permission prompt UX handoff for host apps: persisted grants, runtime revocation, package-manifest defaults, and Note-side integration notes. | SDK verifier plus Note handoff verifier |
| AVM-RELEASE-MANIFEST | P1 | W4 | todo | Add a manifest-driven AVM release runner covering fixture path, expected exit/error, budgets, backend policy, deterministic mode, host-effect expectations, and release-gate inclusion. | new manifest gate plus `make test-avm` |
| AVM-STDLIB-COMPLETE | P1 | W4 | todo | Replace representative stdlib smoke with exported-symbol manifest coverage for every app-facing std module and explicit host-only exclusions. | `make verify-avm-stdlib-obc-surface` |
| AVM-BYTES-HOTPATH | P1 | W3 | todo | Remove legacy list-of-byte/string conversions from hot AVM app-facing APIs; keep bytes as the performance path and text conversion only at explicit boundaries. | `make test-avm && make verify-libavm-ios` |
| AVM-EVENT-FS-PACKAGE | P2 | W3 | todo | Add FS/package events to the virtual event bus without exposing raw OS descriptors. | `make test-avm && make verify-libavm-ios` |
| AVM-COMPILERKIT-IOS | P2 | W3 | todo | Add iOS CompilerKit helper API: source in, diagnostics/OBC out, stdlib bundle resources wired automatically. | `make verify-compiler-in-avm-ios-chain && make verify-libavm-ios` |
| MATH-STDLIB-EXPAND | P2 | W3 | todo | Continue deterministic `std:math` expansion toward C/C++ mathlib breadth with native and AVM fixtures per function family. | focused math fixtures plus `make test-avm` |
| LANG-ANON-IMPORT | P3 | W2 | todo | Add anonymous import syntax such as `import . "std:math"` after defining collision, visibility, import-cache, and fixture behavior. | parser/import/backend fixtures |

## Current Done Evidence

- iOS `OrenAVMKit` builds as an xcframework and verifies TIME, FS, VNET, VPROC,
  GFX/input, package store, trust bundle, permission grant persistence, and
  compiler-in-AVM smoke paths through `make verify-libavm-ios`.
- `stdlib_bundle.obc` includes the current app-facing AVM stdlib surface:
  buffers, bytes, JSON/CBOR/YAML/regex, crypto helpers, linalg, math, time,
  `std:net/avm` DNS/TCP/UDP/WebSocket facades, `std:ui/avm`,
  `std:avm/events`, and `std:avm/permission`.
