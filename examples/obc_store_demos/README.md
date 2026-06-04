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
human-readable `vertices_xyz` / `faces` or `quads` coordinate arrays, builder-side
glTF 2.0 JSON/GLB `gltf_source` plus inline JSON `gltf_json` with sparse accessors, static `POSITION` and `COLOR_0` morph target weights, baked skinning, sampled glTF animation, material×`COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix selection, Wavefront OBJ `obj_source` / `obj_text`,
binary-or-ASCII STL `stl_source`,
inline ASCII STL `stl_text`, binary-or-ASCII PLY `ply_source`,
inline ASCII PLY `ply_text`, PLY face/vertex colors lowered to `mesh3d_rgba`, and core 3MF `3mf_source` ZIP mesh/build plus basematerial `displaycolor` lowering, `triangles_xyz` or `quads_xyz` direct meshes, compact boxes/prisms and bounded
cylinders/cones/spheres/ellipsoids/toruses/capsules, per-triangle `triangles_xyz_rgba` colors,
richer material fields (`base_color`,
`opacity_milli`, `roughness_milli`, `metallic_milli`), and sampled transform
keyframes. The build helper validates face/quad indices/material scalar ranges and
lowers those fields plus draw overrides to compact numeric `.os3d` records using
`sample_time_milli`. The package declares a read-only package VFS mount, proving
OBC can load retained UI scene metadata from package assets without parsing JSON
in the hot runtime path.
