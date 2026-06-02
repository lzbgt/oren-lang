# OBC Store Demos

Curated Oren programs intended to become first-party packages on
`store.hubstack.cn`.

Build and verify the generated package directories with:

```sh
make verify-obc-store-demos
```

Generated `.obc`, `package.json`, source assets, portal screenshot previews, and
`.obc.zip` release bundles live under `build/obc-store-demos/` and are not
committed. Screenshots are store presentation metadata under `screenshots/`; they
are intentionally not declared as package assets and are not included in the
client-installable `.obc.zip` bundle.

The `scene3d-asset-demo` package derives `assets/scene3d_card.os3d` from the
reviewable JSON source in this directory. The JSON can use named mesh/material
references, model templates, instances, per-draw model/material/transform override
objects, human-readable `position_xyz` or nested `transform` model transforms,
human-readable `vertices_xyz` / `faces` coordinate arrays, per-triangle
`triangles_xyz_rgba` colors, richer material fields (`base_color`,
`opacity_milli`, `roughness_milli`, `metallic_milli`), and sampled transform
keyframes. The build helper validates face indices/material scalar ranges and
lowers those fields plus draw overrides to compact numeric `.os3d` records using
`sample_time_milli`. The package declares a read-only package VFS mount, proving
OBC can load retained UI scene metadata from package assets without parsing JSON
in the hot runtime path.
