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
to download, show, cache, or ignore source assets.

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
  "manifest": "packages/oren-labs/ui-card-demo/0.1.0/package.json",
  "manifest_sha256": "<hex>",
  "bundle": "bundles/oren-labs__ui-card-demo__0.1.0.obc.zip",
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

The initial iOS SDK package store path installs expanded packages from the store
index. ZIP upload/download support can be added to the Go service and SDK later
without changing the package manifest contract.
