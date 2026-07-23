# Oren

Oren is a rolling, self-hosted language and toolchain for programs that need to
run under explicit effect boundaries.

It is not a scripting toy or only a compiler experiment. Oren's center is a
single language surface that can target native code, portable C, and deterministic
AVM bytecode while preserving capability-governed execution, resource budgets,
and machine-readable verification evidence.

```oren
import http "std:net/avm/http"

fn main() {
    var title = http.get("https://note.local/data.json").text().json()["o"]["title"]["s"]
    print(title)
    exit(0)
}

main()
```

## Why Oren Exists

Most languages optimize for one of these surfaces: native performance, scripting
ergonomics, sandboxed execution, package distribution, or machine-readable
tooling. Oren is built around their intersection:

- **Native plus bytecode parity.** Build the same program through C, native
  machine code, or OBC bytecode for AVM.
- **Capability-governed effects.** FS, NET, PROC, ENV, TIME, RNG, GFX, and
  package permissions are explicit runtime-policy surfaces rather than hidden
  ambient access.
- **Deterministic app execution.** AVM provides VirtualFS, VirtualNET,
  VirtualPROC, virtual time, budgets, snapshots, UI mailboxes, and replayable
  host-effect boundaries.
- **Agent-readable engineering evidence.** Fixtures, manifests, readiness
  reports, status pages, and API-shape guards are part of the product surface,
  not afterthought scripts.

Oren is still rolling. The macOS arm64 native path is the most mature native
backend; x64 Linux/Windows and full production app lifecycle hardening remain
active work. See [docs/STATUS.md](docs/STATUS.md) for the current truth table.

## Showcases

Oren's current proof is not just syntax. The live OBC store publishes runnable
bytecode packages with source, screenshots, permissions, and installable
`.obc.zip` releases:

### Science Calculator

[![Science calculator preview](https://raw.githubusercontent.com/lzbgt/oren-lang/master/docs/assets/showcases/science-calculator.png)](https://store.hubstack.cn/packages/oren-labs/science-calculator)

Numeric/linalg stdlib, deterministic OBC packaging, source assets, and portal
presentation metadata.

### UI Card Demo

[![UI card demo preview](https://raw.githubusercontent.com/lzbgt/oren-lang/master/docs/assets/showcases/ui-card-demo.png)](https://store.hubstack.cn/packages/oren-labs/ui-card-demo)

Retained 2D UI commands, AVM raster conformance, iOS rendering paths, and
rendered Oren source with AST outline.

### Scene3D Asset Demo

[![Scene3D asset demo preview](https://raw.githubusercontent.com/lzbgt/oren-lang/master/docs/assets/showcases/scene3d-asset-demo.png)](https://store.hubstack.cn/packages/oren-labs/scene3d-asset-demo)

Byte-native `.os3d` package assets, compact cuboid/extruded-polygon/cylinder/cone/sphere
authoring, retained Scene3D meshes/materials/models, camera metadata, and
package VFS mounting.

Screenshots are store presentation metadata, not client runtime assets: they are
not declared in package manifests and are not included in downloaded OBC bundles.
Declared Oren source renders in the portal with syntax highlighting and an
AST-style outline, while host apps can still install and run the signed bundle.

## Language Shape

Oren is designed to feel like a modern language while keeping low-level control
available where it matters:

- **Functions, closures, structs/classes, maps, lists, generators, and
  coroutines** for application code.
- **Traits, generics, method syntax, and call chaining** with deterministic
  compile/link-time method lowering.
- **Typed buffers and byte-native paths** for efficient binary, graphics,
  crypto, and package-asset workloads.
- **Structured fallible APIs** using normal verbs that return values or
  `oren_err`; low-level numeric errno contracts are explicit `*_raw` APIs.
- **Feature-rich stdlib domains** for JSON, YAML, CBOR, XML/HTML readers,
  regex, base64, crypto, buffers, linalg, UI, Scene3D, HTTP, WebSocket, TCP,
  UDP, TLS, DNS, and host-neutral AVM services.

Example: method-style APIs and chaining are first-class, not compatibility
wrappers:

```oren
import bytes "std:bytes"
import sha256 "std:crypto/sha256"

fn main() {
    var digest = bytes.from_string("hello").sha256().hex()
    print(digest)
}

main()
```

Example: OBC packages can render UI/Scene3D through AVM without direct host
graphics access. The host owns policy; bytecode sees virtualized mailboxes and
budgets.

```oren
import scene3d "std:ui/scene3d"
import ui_avm "std:ui/avm"

fn main() {
    var commands = scene3d.commands_from_binary_file("assets/scene3d_card.os3d")
    if oren_is_err(commands) { exit(1) }

    var rc = ui_avm.present_frame(commands, 4, 4, {"strict_bounds": true})
    if oren_is_err(rc) { exit(1) }

    exit(0)
}

main()
```

For the practical language guide, start with [docs/LANGUAGE.md](docs/LANGUAGE.md).

## Toolchain

Oren currently has three execution paths:

| Path | Use | Status |
| --- | --- | --- |
| C backend | Portable bootstrap and cross-checking through a host C toolchain. | Useful baseline. |
| Native backend | Mach-O / ELF / PE output for local/server/desktop execution. | Most mature on macOS arm64; x64 is active bring-up. |
| OBC + AVM | Deterministic bytecode for capability-governed host apps. | Strong smoke/conformance gates; still rolling for production embedding. |
| Desktop SDK | macOS `LibAVM.xcframework` plus Linux/Windows x64 static `LibAVM` for C/C++/Swift hosts. | macOS runs C and Swift embedder smokes; Linux/Windows x64 are cross-built, symbol-checked, and link-smoked. |

Build native:

```bash
./oren build examples/hello.oren -o build/hello
./build/hello
```

Build and run bytecode:

```bash
./oren build examples/hello.oren --backend bytecode -o build/hello.obc
make avm
./avm build/hello.obc
```

Run the default high-signal verification path:

```bash
./oretest
```

`./oretest` is the repo-local fast entrypoint. Broader gates remain available
when needed:

```bash
make test
make test-avm
make verify-libavm-ios
make verify-libavm-desktop
make verify-libavm-linux-x64
make verify-libavm-windows-x64
make verify-obc-store-service
```

`make test` intentionally runs negative fixtures; parse/typecheck diagnostics in
the log are expected when the command exits successfully.

## AVM, iOS, and OBC Packages

AVM is Oren's deterministic bytecode runtime. It supports app-facing embedder
APIs, iOS xcframework packaging, compiler-in-AVM smoke coverage, VirtualFS,
VirtualNET, VirtualPROC, virtual time, UI/GFX frame mailboxes, input events,
permission prompts, and package install/run flows.

The public OBC store is live:

- Portal: <https://store.hubstack.cn/>
- Health: <https://store.hubstack.cn/healthz>
- Index: <https://store.hubstack.cn/api/v0/index.json>

The live store currently publishes first-party `oren-labs` demos for science,
2D UI, and Scene3D package assets. Host apps can install verified `.obc.zip`
bundles, mount package assets into VirtualFS, apply package permissions, and run
bytecode under AVM policy.

## Documentation Map

- [docs/LANGUAGE.md](docs/LANGUAGE.md): practical language guide.
- [docs/OREN_THESIS.md](docs/OREN_THESIS.md): product thesis and differentiation.
- [docs/CAPABILITY_RUNTIME_CONTRACT.md](docs/CAPABILITY_RUNTIME_CONTRACT.md):
  capability/runtime-profile contract.
- [docs/STATUS.md](docs/STATUS.md): current readiness and known gaps.
- [docs/README.md](docs/README.md): full documentation index.
- [benchmarks/README.md](benchmarks/README.md): benchmark usage.
- [benchmarks/RESULTS_LATEST.md](benchmarks/RESULTS_LATEST.md): latest benchmark snapshot.

## Engineering Standard

Oren is intentionally rolling, but not casual. Changes are expected to come with
fixtures, conformance gates, docs updates, and fast verification. "Small"
implementation means low resource consumption: CPU time, memory, disk,
bandwidth, build overhead, and runtime overhead. It does not mean toy features
or ad-hoc prototypes.

## License

Copyright (c) 2025 Lu Zongbao (rikusouhou@gmail.com).

This project is licensed under the Apache License, Version 2.0. See
[LICENSE](LICENSE).
