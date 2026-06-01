# OBC Store Demos

Curated Oren programs intended to become first-party packages on
`store.hubstack.cn`.

Build and verify the generated package directories with:

```sh
make verify-obc-store-demos
```

Generated `.obc`, `package.json`, source assets, and `.obc.zip` release bundles
live under `build/obc-store-demos/` and are not committed.

The `scene3d-asset-demo` package derives `assets/scene3d_card.os3d` from the
reviewable JSON source in this directory. The JSON can use named mesh/material
references, model templates, instances, human-readable `position_xyz` model
transforms, and human-readable `vertices_xyz` / `faces` coordinate arrays; the
build helper validates face indices and lowers those fields to compact numeric
`.os3d` records. The package declares a read-only package VFS mount, proving OBC
can load retained UI scene metadata from package assets without parsing JSON in
the hot runtime path.
