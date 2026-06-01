# OBC Store Demos

Curated Oren programs intended to become first-party packages on
`store.hubstack.cn`.

Build and verify the generated package directories with:

```sh
make verify-obc-store-demos
```

Generated `.obc`, `package.json`, source assets, and `.obc.zip` release bundles
live under `build/obc-store-demos/` and are not committed.

The `scene3d-asset-demo` package also bundles `assets/scene3d_card.json` and
declares a read-only package VFS mount, proving OBC can load retained UI scene
metadata from package assets instead of hard-coding every mesh in source.
