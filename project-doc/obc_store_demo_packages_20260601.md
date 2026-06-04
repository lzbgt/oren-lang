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
| `oren-labs/scene3d-asset-demo@0.1.0` | Loads a bundled JSON `std:ui/scene3d` asset through package VFS, raster-checks it, and publishes the retained 3D frame. | `CORE`, `FS`, `GFX`, `EXIT` |

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
build/obc-store-demos/packages/<publisher>/<name>/<version>/screenshots/preview.png
build/obc-store-demos/packages/oren-labs/scene3d-asset-demo/0.1.0/assets/scene3d_card.os3d
```

Official demo packages always bundle source code as a package asset so host apps
can show or ignore source independently from the executable OBC. The manifest
declares the source in both `assets` and `sources`; the store index declares the
ZIP bundle path, media type, and SHA-256. The store browser renders declared
Oren source through a syntax-highlighted source page with an AST outline instead
of making users download the source file. Official demo releases also write a
deterministic `screenshots/preview.png` image as store presentation metadata.
Screenshots are intentionally not package manifest assets and are not included in
the client-installable `.obc.zip` bundle. Demo packages may also bundle runtime
assets; `scene3d-asset-demo` derives a byte-native
`.os3d` asset from the reviewable JSON source with
`scripts/make_scene3d_bin_v0.py`, including scene-level camera depth metadata,
named mesh/material references, model templates, instances, human-readable
`position_xyz` or nested `transform` model transforms,
human-readable `vertices_xyz` / `faces` or `quads` coordinate arrays,
imported glTF mesh assets with sampled animation, `triangles_xyz` or
`quads_xyz` direct meshes, and per-triangle `triangles_xyz_rgba`
colors, richer material fields (`base_color`,
`opacity_milli`, `roughness_milli`, `metallic_milli`), plus sampled transform
keyframes. The builder validates face/quad indices/material scalar ranges, resolves
that authoring form into compact numeric `.os3d` records using `sample_time_milli`,
the package declares a read-only `assets/` VFS mount, and OBC proves it can load
retained UI scene metadata from package assets without JSON parsing in the hot
path. `make verify-libavm-ios` also carries an SDK-local
package-store fixture that mounts and raster-checks the same class of `.os3d`
asset through `OrenAVMPackageStore`, so host-app package install/run coverage
matches the demo bundle format.

These generated package artifacts are intentionally not committed. The live
`store.hubstack.cn` portal publishes the current first-party demo bundles with
their screenshot previews.
