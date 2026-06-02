# OBC Release Bundle Format

**Date:** 2026-06-01

## Decision

An OBC store release should have a portable bundle artifact in addition to the
expanded store directory layout. The bundle format is a deterministic ZIP file
with media type:

```text
application/vnd.oren.obc.release+zip
```

Recommended extension:

```text
.obc.zip
```

The ZIP is the unit users and tools can download, mirror, archive, or upload.
The expanded directory remains the server/install layout used by the store and
host SDK after verification.

## Required ZIP Layout

The ZIP must be rootless and must not contain absolute paths, `..` segments, or
symlinks.

```text
package.json
program.obc
assets/
  source/
    main.oren
  ...
```

Required entries:

- `package.json`: `oren.obc.package.v0` manifest.
- `program.obc`: executable OBC referenced by `entry_obc`.

Optional entries:

- `assets/**`: read-only package assets declared by manifest `assets`.
- `assets/source/**`: source code assets. Official demos include source here.

## Source Policy

Source code is optional for third-party packages and required for official demos.
The OBC artifact remains the executable release payload; source assets are for
host-app display, audit, learning, or recompile workflows. A host app may choose
to download, show, cache, or ignore source assets. The browser store portal
renders declared Oren source assets with syntax highlighting and an AST-oriented
outline instead of presenting them as plain download links.

Official demos should declare bundled source in both places:

```json
{
  "assets": [
    {
      "path": "assets/source/main.oren",
      "sha256": "<hex>",
      "media_type": "text/x-oren",
      "role": "source"
    }
  ],
  "sources": [
    {
      "path": "assets/source/main.oren",
      "language": "oren",
      "role": "main"
    }
  ]
}
```

## Hashing And Signing

`package.json` contains hashes for `program.obc` and declared assets. The store
index contains hashes for externally fetched metadata and bundle artifacts:

```json
{
  "id": "oren-labs/ui-card-demo",
  "version": "0.1.0",
  "manifest": "packages/oren-labs/ui-card-demo/versions/0.1.0/package.json",
  "manifest_sha256": "<hex>",
  "bundle": "packages/oren-labs/ui-card-demo/versions/0.1.0/bundle.obc.zip",
  "bundle_sha256": "<hex>",
  "bundle_media_type": "application/vnd.oren.obc.release+zip"
}
```

Do not put `bundle_sha256` inside `package.json`; the ZIP contains the manifest,
so that would create a circular hash. Sign index/package metadata outside the
bundle using the existing store and publisher signature flow.

## Determinism

Bundle writers should emit deterministic ZIPs:

- stable file order;
- fixed timestamps;
- no platform-specific extra fields;
- normal file mode metadata only;
- compressed or stored entries are both valid, but official tooling uses DEFLATE.

The verifier should reject unsafe paths and should unpack into a temporary
directory before replacing an installed package.

## Current Tooling

`make verify-obc-store-demos` builds first-party demo packages and emits both
expanded directories and deterministic ZIP bundles under:

```text
build/obc-store-demos/packages/
build/obc-store-demos/bundles/
```

The Go store service accepts `release_bundle_base64` during version creation,
validates that the ZIP is rootless and contains `package.json` plus `program.obc`,
serves it at:

```text
/api/v0/packages/{publisher}/{name}/versions/{version}/bundle.obc.zip
```

and advertises `bundle`, `bundle_sha256`, and `bundle_media_type` in
`index.json`.

Official demo releases may also upload portal screenshots through the store
release `screenshots` field. Those images are presentation metadata served from
`/api/v0/packages/{publisher}/{name}/versions/{version}/screenshots/...`; they
are intentionally not declared in `package.json`, not included in `.obc.zip`, and
not mounted as client runtime assets.

The iOS SDK package store path now prefers the ZIP bundle when those index fields
are present. It verifies `bundle_sha256`, extracts only safe rootless entries,
rejects encrypted/unsupported/symlink paths, verifies the extracted
`package.json` hash against `manifest_sha256`, then runs the existing local
package verifier. If no bundle is listed, it falls back to expanded
`package.json`/`program.obc`/assets.
