# OBC Store Demo Packages

**Date:** 2026-06-01

## Decision

The first public OBC store should ship with small first-party packages that prove
the iOS AVM path is useful before third-party packages exist.

## Current Demo Set

Sources live under `examples/obc_store_demos/`.

| Package | Purpose | Capabilities |
| --- | --- | --- |
| `oren-labs/science-calculator@0.1.0` | Deterministic `std:math.power(...)` and `std:linalg.dot_f64(...)` smoke for scientific calculation. | `CORE`, `EXIT` |
| `oren-labs/ui-card-demo@0.1.0` | Publishes a compact binary `OGF0` UI frame for host-rendered iOS UI/GFX demos. | `CORE`, `GFX`, `EXIT` |

## Build Gate

```sh
make verify-obc-store-demos
```

The gate builds each source to bytecode, runs each `.obc` under AVM with
deny-by-default capability flags, and writes generated package directories plus
deterministic ZIP release bundles under:

```text
build/obc-store-demos/
```

The generated output includes:

```text
build/obc-store-demos/index.json
build/obc-store-demos/bundles/<publisher>__<name>__<version>.obc.zip
build/obc-store-demos/packages/<publisher>/<name>/<version>/package.json
build/obc-store-demos/packages/<publisher>/<name>/<version>/program.obc
build/obc-store-demos/packages/<publisher>/<name>/<version>/assets/source/main.oren
```

Official demo packages always bundle source code as a package asset so host apps
can show or ignore source independently from the executable OBC. The manifest
declares the source in both `assets` and `sources`; the store index declares the
ZIP bundle path, media type, and SHA-256.

These generated package artifacts are intentionally not committed. They can be
published to `store.hubstack.cn` after live deployment/signing credentials are
available.
