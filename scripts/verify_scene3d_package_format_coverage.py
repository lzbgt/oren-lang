#!/usr/bin/env python3
"""Guard Scene3D Oren-side mesh formats against binary package-builder drift."""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]

OREN_SCENE3D = ROOT / "lib/std/ui/scene3d.oren"
BUILDER_FILES = [
    ROOT / "scripts/make_scene3d_bin_v0.py",
    ROOT / "scripts/scene3d_3mf.py",
    ROOT / "scripts/scene3d_flat_arch.py",
    ROOT / "scripts/scene3d_flat_curves.py",
    ROOT / "scripts/scene3d_gltf.py",
    ROOT / "scripts/scene3d_grid.py",
]

# Raw ABI payload escape hatches are intentionally not human-readable package formats.
RAW_ABI_KEYS = {
    "vertices",
    "indices",
    "faces",
    "quads",
    "triangles",
}

# Asset-source import keys are implemented in the Python package builder. They are
# not Oren-side `.os3d` binary loader fields, but are part of package authoring.
SOURCE_IMPORT_KEYS = {
    "obj_source",
    "obj_text",
    "obj_scale_milli",
    "obj_offset_xyz",
    "stl_source",
    "stl_text",
    "stl_scale_milli",
    "stl_offset_xyz",
    "ply_source",
    "ply_text",
    "ply_scale_milli",
    "ply_offset_xyz",
    "gltf_source",
    "gltf_json",
    "gltf_mesh",
    "gltf_node",
    "gltf_scene",
    "gltf_animation",
    "gltf_sample_time_milli",
    "gltf_scale_milli",
    "gltf_offset_xyz",
    "3mf_source",
    "3mf_object",
    "3mf_triangle_set",
    "3mf_scale_milli",
    "3mf_offset_xyz",
    "threemf_source",
    "threemf_object",
    "threemf_triangle_set",
    "threemf_scale_milli",
    "threemf_offset_xyz",
}

NON_FORMAT_FIELDS = {
    "base_color",
    "color",
    "id",
    "kind",
    "metallic_milli",
    "name",
    "opacity_milli",
    "pivot_xyz",
    "points",
    "points_xy",
    "position_xyz",
    "rotate_xyz_milli_deg",
    "rotate_z_milli_deg",
    "rotation_xyz_milli_deg",
    "rotation_z_milli_deg",
    "roughness_milli",
    "scale_milli",
    "scale_xyz_milli",
    "transform",
    "translate_xyz",
    "translation_xyz",
    "x",
    "y",
    "z",
} | RAW_ABI_KEYS

FORMAT_HINTS = (
    "vertices_",
    "triangles_",
    "quads_",
    "heightfields_",
    "surfaces_",
    "boxes_",
    "prisms_",
    "planes_",
    "rects_",
    "rounded_",
    "polygons_",
    "regular_",
    "stars_",
    "discs_",
    "rings_",
    "ellipses_",
    "ellipse_",
    "segments_",
    "paths_",
    "beziers_",
    "sectors_",
    "arc_",
    "ramps_",
    "solid_",
    "posts_",
    "curbs_",
    "fences_",
    "stairs_",
    "gable_",
    "pyramids_",
    "walls_",
    "rooms_",
    "cylinders_",
    "cones_",
    "spheres_",
    "ellipsoids_",
    "toruses_",
    "capsules_",
)


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def oren_mesh_payload_keys() -> set[str]:
    src = read(OREN_SCENE3D)
    keys = set(re.findall(r'm\["([A-Za-z0-9_]+)"\]', src))
    return {
        key
        for key in keys
        if key not in NON_FORMAT_FIELDS
        and (key.endswith("_xy") or key.endswith("_xyz") or key.endswith("_z") or any(h in key for h in FORMAT_HINTS))
    }


def builder_text() -> str:
    return "\n".join(read(path) for path in BUILDER_FILES)


def main() -> int:
    payload_keys = oren_mesh_payload_keys()
    text = builder_text()

    missing_payload = sorted(key for key in payload_keys if key not in text)
    missing_raw = sorted(key for key in RAW_ABI_KEYS if key not in text)
    missing_source = sorted(key for key in SOURCE_IMPORT_KEYS if key not in text)

    if missing_payload or missing_raw or missing_source:
        if missing_payload:
            print("missing Scene3D binary builder payload keys:", ", ".join(missing_payload), file=sys.stderr)
        if missing_raw:
            print("missing Scene3D binary builder raw ABI keys:", ", ".join(missing_raw), file=sys.stderr)
        if missing_source:
            print("missing Scene3D binary builder source-import keys:", ", ".join(missing_source), file=sys.stderr)
        return 1

    print(
        "scene3d package format coverage OK: "
        f"{len(payload_keys)} Oren mesh payload keys, "
        f"{len(RAW_ABI_KEYS)} raw ABI keys, "
        f"{len(SOURCE_IMPORT_KEYS)} source-import keys"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
