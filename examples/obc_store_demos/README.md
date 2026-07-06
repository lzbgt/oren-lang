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
human-readable `vertices_xyz` / `vertices_xy` with `faces` or `quads` coordinate arrays, builder-side
glTF 2.0 JSON/GLB `gltf_source` plus inline JSON `gltf_json` with sparse accessors, static `POSITION` and `COLOR_0` morph target weights, baked skinning, sampled glTF animation, material×`COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix selection, Wavefront OBJ `obj_source` / `obj_text`,
binary-or-ASCII STL `stl_source`,
inline ASCII STL `stl_text`, binary-or-ASCII PLY `ply_source`,
inline ASCII PLY `ply_text`, PLY face/vertex colors lowered to `mesh3d_rgba`, and core 3MF `3mf_source` ZIP mesh/build plus basematerial `displaycolor` lowering and optional `3mf_triangle_set` selection, `triangles_xyz` / `quads_xyz` or flat `triangles_xy` / `quads_xy` direct meshes, flat per-triangle-color `triangles_xy_rgba` / `quads_xy_rgba`, rectangular `planes_xy` / `rects_xy`, filled `rounded_rects_xy`, flat `polygons_xy`, regular `regular_polygons_xy` / `stars_xy`, circular `discs_xy` / `rings_xy`, elliptical `ellipses_xy` / `ellipse_rings_xy`, thick `segments_xy` / `paths_xy`, sampled `beziers_xy`, partial `sectors_xy` / `arc_bands_xy`, sloped `ramps_xy` / `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, bounded `heightfields_xy` / `surfaces_xyz`, compact boxes/prisms and bounded
cylinders/cones/spheres/ellipsoids/toruses/capsules, per-triangle `triangles_xyz_rgba` colors,
richer material fields (`base_color`,
`opacity_milli`, `roughness_milli`, `metallic_milli`), and sampled transform
keyframes. The build helper validates face/quad indices/material scalar ranges and
lowers those fields plus draw overrides to compact numeric `.os3d` records using
`sample_time_milli`. The package declares a read-only package VFS mount, proving
OBC can load retained UI scene metadata from package assets without parsing JSON
in the hot runtime path.
