#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
AVM_BIN="${AVM_BIN:-./avm}"
SPEC="${SPEC:-examples/obc_store_demos/packages.json}"
OUT_ROOT="${OUT_ROOT:-build/obc-store-demos}"
LOG_DIR="${LOG_DIR:-build/logs}"

mkdir -p "$OUT_ROOT" "$LOG_DIR"

python3 - "$OREN_COMPILER" "$AVM_BIN" "$SPEC" "$OUT_ROOT" "$LOG_DIR" <<'PY'
import json
import base64
import hashlib
import importlib.util
import math
import pathlib
import shutil
import struct
import subprocess
import sys
import zipfile
import zlib

compiler, avm, spec_path, out_root, log_dir = sys.argv[1:]
out_root = pathlib.Path(out_root)
log_dir = pathlib.Path(log_dir)
spec = json.loads(pathlib.Path(spec_path).read_text())
scene3d_spec = importlib.util.spec_from_file_location("make_scene3d_bin_v0", "scripts/make_scene3d_bin_v0.py")
scene3d_module = importlib.util.module_from_spec(scene3d_spec)
scene3d_spec.loader.exec_module(scene3d_module)

packages_root = out_root / "packages"
bundles_root = out_root / "bundles"
if packages_root.exists():
    shutil.rmtree(packages_root)
if bundles_root.exists():
    shutil.rmtree(bundles_root)
packages_root.mkdir(parents=True, exist_ok=True)
bundles_root.mkdir(parents=True, exist_ok=True)


def verify_scene3d_obj_lowering():
    obj_text = "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n"
    for kind in ("triangles", "indexed"):
        scene = {
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{"kind": kind, "id": 1, "obj_text": obj_text, "color": "#ffffffff"}],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
        if not data.startswith(b"OS3D01\x00\x00"):
            raise SystemExit(f"scene OBJ {kind} lowering did not produce OS3D01")


def verify_scene3d_flat_xy_lowering():
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{
            "kind": "triangles",
            "id": 1,
            "triangles_xy": [{"points": [[1, 0], [3, 0], [1, 2]], "z": 6}],
            "color": "#44cc88ff",
        }],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    triangle = b"".join(struct.pack("<iii", *v) for v in ((1, 0, 6), (3, 0, 6), (1, 2, 6)))
    if not data.startswith(b"OS3D01\x00\x00") or struct.pack("<I", 36) not in data or triangle not in data:
        raise SystemExit("scene triangles_xy lowering did not produce expected packed XYZ payload")

    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "quads_xy": [{"points_xy": [[2, 3], [6, 3], [6, 7], [2, 7]], "z_milli": 9}],
        "color": "#cc8844ff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    quad_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((2, 3, 9), (6, 3, 9), (6, 7, 9), (2, 3, 9), (6, 7, 9), (2, 7, 9))
    )
    if struct.pack("<I", 72) not in data or quad_payload not in data:
        raise SystemExit("scene quads_xy lowering did not produce expected two-triangle payload")

    scene["meshes"][0] = {
        "kind": "triangles_rgba",
        "id": 1,
        "triangles_xy_rgba": [{"points": [[0, 0], [4, 0], [0, 4]], "z": 5, "color": "#11223344"}],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<I", 40) not in data or b"\x11\x22\x33\x44" not in data:
        raise SystemExit("scene triangles_xy_rgba lowering did not produce expected RGBA payload")

    scene["meshes"][0] = {
        "kind": "triangles_rgba",
        "id": 1,
        "quads_xy_rgba": [{"points": [[0, 0], [4, 0], [4, 4], [0, 4]], "color": "#44556677"}],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<I", 80) not in data or data.count(b"\x44\x55\x66\x77") < 2:
        raise SystemExit("scene quads_xy_rgba lowering did not produce expected repeated RGBA payload")

    try:
        scene3d_module.scene3d_bin_v0(json.dumps({
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{
                "kind": "triangles",
                "id": 1,
                "triangles_xy": [{"points": [[0, 0], [1, 0]], "z": 0}],
                "color": "#ffffffff",
            }],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }))
    except SystemExit:
        pass
    else:
        raise SystemExit("scene malformed triangles_xy unexpectedly lowered")


def verify_scene3d_flat_shape_lowering():
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{
            "kind": "triangles",
            "id": 1,
            "planes_xy": [{"min_xy": [1, 2], "max_xy": [5, 6], "z_milli": 7}],
            "color": "#8899aaff",
        }],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    plane_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((1, 2, 7), (5, 2, 7), (5, 6, 7), (1, 2, 7), (5, 6, 7), (1, 6, 7))
    )
    if struct.pack("<I", 72) not in data or plane_payload not in data:
        raise SystemExit("scene planes_xy lowering did not produce expected rectangle payload")

    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "rects_xy": [{"origin_xyz": [2, 3, 4], "size_xy": [5, 6]}],
        "color": "#8899aaff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    rect_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((2, 3, 4), (7, 3, 4), (7, 9, 4), (2, 3, 4), (7, 9, 4), (2, 9, 4))
    )
    if struct.pack("<I", 72) not in data or rect_payload not in data:
        raise SystemExit("scene rects_xy lowering did not produce expected origin/size payload")

    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "polygons_xy": [{"points_xy": [[0, 0], [4, 0], [4, 4], [0, 4]], "z": 8}],
        "color": "#8899aaff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    polygon_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((0, 0, 8), (4, 0, 8), (4, 4, 8), (0, 0, 8), (4, 4, 8), (0, 4, 8))
    )
    if struct.pack("<I", 72) not in data or polygon_payload not in data:
        raise SystemExit("scene polygons_xy lowering did not produce expected fan payload")

    try:
        scene3d_module.scene3d_bin_v0(json.dumps({
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{
                "kind": "triangles",
                "id": 1,
                "polygons_xy": [{"points": [[0, 0], [1, 0]], "z": 0}],
                "color": "#ffffffff",
            }],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }))
    except SystemExit:
        pass
    else:
        raise SystemExit("scene malformed polygons_xy unexpectedly lowered")


def verify_scene3d_flat_line_lowering():
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{
            "kind": "triangles",
            "id": 1,
            "segments_xy": [{"from": [1, 2], "to": [4, 2], "width": 2, "z": 1}],
            "color": "#44cc88ff",
        }],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    segment_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((1, 3, 1), (4, 3, 1), (4, 1, 1), (1, 3, 1), (4, 1, 1), (1, 1, 1))
    )
    if struct.pack("<I", 72) not in data or segment_payload not in data:
        raise SystemExit("scene segments_xy lowering did not produce expected thick-line payload")

    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "paths_xy": [{"points": [[1, 1], [4, 1], [4, 4]], "width": 2, "z": 1}],
        "color": "#8844ccff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    path_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((1, 2, 1), (4, 2, 1), (4, 0, 1), (1, 2, 1), (4, 0, 1), (1, 0, 1))
    )
    if struct.pack("<I", 144) not in data or path_payload not in data:
        raise SystemExit("scene paths_xy lowering did not produce expected first segment payload")

    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "beziers_xy": [{"points": [[1, 2], [2, 2], [4, 2]], "segments": 2, "width": 2, "z": 1}],
        "color": "#cc8844ff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    bezier_payload = b"".join(
        struct.pack("<iii", *v)
        for v in ((1, 3, 1), (2, 3, 1), (2, 1, 1), (1, 3, 1), (2, 1, 1), (1, 1, 1))
    )
    if struct.pack("<I", 144) not in data or bezier_payload not in data:
        raise SystemExit("scene beziers_xy lowering did not produce expected first segment payload")

    for mesh in (
        {"kind": "triangles", "id": 1, "segments_xy": [{"from": [0, 0], "to": [0, 0], "width": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "paths_xy": [{"points": [[0, 0], [0, 0]], "width": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "beziers_xy": [{"points": [[0, 0], [1, 1]], "segments": 2}], "color": "#ffffffff"},
    ):
        try:
            scene3d_module.scene3d_bin_v0(json.dumps({
                "schema": "oren.ui.scene3d.v0",
                "meshes": [mesh],
                "models": [{"id": 2, "mesh_id": 1}],
                "draw": [2],
            }))
        except SystemExit:
            pass
        else:
            raise SystemExit("scene malformed flat line shape unexpectedly lowered")


def packed_xyz(vertices):
    return b"".join(struct.pack("<iii", *v) for v in vertices)


def verify_scene3d_flat_curve_lowering():
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "color": "#44cc88ff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }

    cases = [
        (
            "discs_xy",
            [{"center": [2, 2], "radius": 1, "segments": 4, "z": 1}],
            144,
            ((2, 2, 1), (3, 2, 1), (2, 3, 1)),
        ),
        (
            "ellipses_xy",
            [{"center": [3, 2], "radii": [2, 1], "segments": 4, "z": 1}],
            144,
            ((3, 2, 1), (5, 2, 1), (3, 3, 1)),
        ),
        (
            "ellipse_rings_xy",
            [{"center": [3, 3], "inner_radii": [1, 1], "outer_radii": [3, 2], "segments": 4, "z": 1}],
            288,
            ((6, 3, 1), (3, 5, 1), (3, 4, 1), (6, 3, 1), (3, 4, 1), (4, 3, 1)),
        ),
        (
            "regular_polygons_xy",
            [{"center": [2, 2], "radius": 1, "sides": 4, "z": 1}],
            144,
            ((2, 2, 1), (3, 2, 1), (2, 3, 1)),
        ),
        (
            "stars_xy",
            [{"center": [3, 3], "inner_radius": 1, "outer_radius": 2, "points": 4, "z": 1}],
            288,
            ((3, 3, 1), (5, 3, 1), (4, 4, 1)),
        ),
        (
            "rings_xy",
            [{"center": [3, 3], "inner_radius": 1, "outer_radius": 2, "segments": 4, "z": 1}],
            288,
            ((5, 3, 1), (3, 5, 1), (3, 4, 1), (5, 3, 1), (3, 4, 1), (4, 3, 1)),
        ),
        (
            "sectors_xy",
            [{"center": [2, 2], "radius": 2, "start_milli_deg": 0, "end_milli_deg": 90000, "segments": 1, "z": 1}],
            36,
            ((2, 2, 1), (4, 2, 1), (2, 4, 1)),
        ),
        (
            "arc_bands_xy",
            [{"center": [3, 3], "inner_radius": 1, "outer_radius": 2, "start_milli_deg": 0, "end_milli_deg": 90000, "segments": 1, "z": 1}],
            72,
            ((5, 3, 1), (3, 5, 1), (3, 4, 1), (5, 3, 1), (3, 4, 1), (4, 3, 1)),
        ),
        (
            "rounded_rects_xy",
            [{"min": [1, 1], "max": [5, 5], "radius": 1, "corner_segments": 1, "z": 1}],
            288,
            ((3, 3, 1), (5, 4, 1), (4, 5, 1)),
        ),
    ]

    for key, items, payload_len, expected_vertices in cases:
        scene["meshes"][0] = {"kind": "triangles", "id": 1, key: items, "color": "#44cc88ff"}
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
        if struct.pack("<I", payload_len) not in data or packed_xyz(expected_vertices) not in data:
            raise SystemExit(f"scene {key} lowering did not produce expected flat curve payload")

    bad_meshes = [
        {"kind": "triangles", "id": 1, "discs_xy": [{"center": [0, 0], "radius": 1, "segments": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "ellipses_xy": [{"center": [0, 0], "radii": [1, 0]}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "ellipse_rings_xy": [{"center": [0, 0], "inner_radii": [2, 1], "outer_radii": [2, 2]}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "regular_polygons_xy": [{"center": [0, 0], "radius": 1, "sides": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "stars_xy": [{"center": [0, 0], "inner_radius": 2, "outer_radius": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "rings_xy": [{"center": [0, 0], "inner_radius": 2, "outer_radius": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "sectors_xy": [{"center": [0, 0], "radius": 1, "start_milli_deg": 90000, "end_milli_deg": 0}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "arc_bands_xy": [{"center": [0, 0], "inner_radius": 2, "outer_radius": 1, "start_milli_deg": 0, "end_milli_deg": 90000}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "rounded_rects_xy": [{"min": [0, 0], "max": [2, 2], "radius": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "rounded_rects_xy": [{"min": [0, 0], "max": [4, 4], "radius": 1, "corner_segments": 0}], "color": "#ffffffff"},
    ]
    for mesh in bad_meshes:
        try:
            scene3d_module.scene3d_bin_v0(json.dumps({
                "schema": "oren.ui.scene3d.v0",
                "meshes": [mesh],
                "models": [{"id": 2, "mesh_id": 1}],
                "draw": [2],
            }))
        except SystemExit:
            pass
        else:
            raise SystemExit("scene malformed flat curve shape unexpectedly lowered")


def verify_scene3d_flat_arch_lowering():
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "color": "#6688aaff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }

    cases = [
        (
            "walls_xy",
            [{"points": [[1, 1], [4, 1], [4, 3]], "z_min": 1, "z_max": 3}],
            144,
            ((1, 1, 1), (4, 1, 1), (4, 1, 3)),
        ),
        (
            "rooms_xy",
            [{"points": [[1, 1], [4, 1], [4, 3], [1, 3]], "z_min": 1, "z_max": 3}],
            432,
            ((1, 1, 1), (4, 3, 1), (4, 1, 1)),
        ),
        (
            "ramps_xy",
            [{"from": [1, 1], "to": [4, 1], "width": 2, "z_from": 1, "z_to": 3}],
            72,
            ((1, 2, 1), (4, 2, 3), (4, 0, 3)),
        ),
        (
            "solid_ramps_xy",
            [{"from": [1, 1], "to": [4, 1], "width": 2, "z_base": 0, "z_from": 1, "z_to": 3}],
            432,
            ((1, 2, 1), (4, 2, 3), (4, 0, 3)),
        ),
        (
            "posts_xy",
            [{"points": [[2, 2], [5, 2]], "width": 2, "z_min": 1, "z_max": 4}],
            864,
            ((1, 1, 1), (3, 1, 1), (3, 3, 1)),
        ),
        (
            "curbs_xy",
            [{"points": [[1, 1], [4, 1], [4, 3]], "width": 2, "z_min": 1, "z_max": 3}],
            864,
            ((1, 2, 3), (4, 2, 3), (4, 0, 3)),
        ),
        (
            "fences_xy",
            [{"points": [[2, 2], [4, 2]], "post_width": 2, "rail_width": 2, "z_min": 0, "z_max": 3, "rail_z_min": 1, "rail_z_max": 2}],
            1296,
            ((1, 1, 0), (3, 1, 0), (3, 3, 0)),
        ),
        (
            "stairs_xy",
            [{"from": [1, 1], "to": [5, 1], "width": 2, "z_from": 1, "z_to": 3, "steps": 2}],
            288,
            ((1, 2, 1), (1, 0, 1), (1, 0, 2)),
        ),
        (
            "gable_roofs_xy",
            [{"from": [1, 1], "to": [5, 1], "width": 2, "z_eave": 1, "z_ridge": 4}],
            216,
            ((1, 2, 1), (5, 2, 1), (5, 1, 4)),
        ),
        (
            "pyramids_xy",
            [{"points": [[1, 1], [4, 1], [4, 3], [1, 3]], "z_base": 1, "apex": [2, 2, 4]}],
            216,
            ((1, 1, 1), (4, 3, 1), (4, 1, 1)),
        ),
    ]

    for key, items, payload_len, expected_vertices in cases:
        scene["meshes"][0] = {"kind": "triangles", "id": 1, key: items, "color": "#6688aaff"}
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
        if struct.pack("<I", payload_len) not in data or packed_xyz(expected_vertices) not in data:
            raise SystemExit(f"scene {key} lowering did not produce expected architectural payload")

    bad_meshes = [
        {"kind": "triangles", "id": 1, "ramps_xy": [{"from": [0, 0], "to": [0, 0], "width": 1, "z_from": 0, "z_to": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "solid_ramps_xy": [{"from": [0, 0], "to": [1, 0], "width": 1, "z_base": 1, "z_from": 1, "z_to": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "posts_xy": [{"points": [], "width": 1, "z_min": 0, "z_max": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "curbs_xy": [{"points": [[0, 0], [0, 0]], "width": 1, "z_min": 0, "z_max": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "fences_xy": [{"points": [[0, 0], [1, 0]], "post_width": 1, "rail_width": 1, "z_min": 0, "z_max": 1, "rail_z_min": 1, "rail_z_max": 2}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "fences_xy": [{"points": [[0, 0], [1, 0]], "post_width": 1, "z_min": 0, "z_max": 1, "rails": []}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "stairs_xy": [{"from": [0, 0], "to": [1, 0], "width": 1, "z_from": 0, "z_to": 1, "steps": 0}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "gable_roofs_xy": [{"from": [0, 0], "to": [1, 0], "width": 1, "z_eave": 1, "z_ridge": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "pyramids_xy": [{"points": [[0, 0], [1, 0]], "z_base": 0, "apex": [0, 0, 1]}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "rooms_xy": [{"points": [[0, 0], [1, 0]], "z_min": 0, "z_max": 1}], "color": "#ffffffff"},
        {"kind": "triangles", "id": 1, "walls_xy": [{"points": [[0, 0]], "z_min": 0, "z_max": 1}], "color": "#ffffffff"},
    ]
    for mesh in bad_meshes:
        try:
            scene3d_module.scene3d_bin_v0(json.dumps({
                "schema": "oren.ui.scene3d.v0",
                "meshes": [mesh],
                "models": [{"id": 2, "mesh_id": 1}],
                "draw": [2],
            }))
        except SystemExit:
            pass
        else:
            raise SystemExit("scene malformed flat architectural shape unexpectedly lowered")


def verify_scene3d_gltf_lowering():
    payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        payload += struct.pack("<fff", *vertex)
    payload += struct.pack("<HHH", 0, 1, 2)
    for color in ((255, 32, 32, 255), (32, 255, 32, 255), (32, 32, 255, 255)):
        payload += bytes(color)
    uri = "data:application/octet-stream;base64," + base64.b64encode(payload).decode("ascii")
    gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": uri, "byteLength": len(payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6},
            {"buffer": 0, "byteOffset": 42, "byteLength": 12},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5121, "count": 3, "type": "VEC4", "normalized": True},
        ],
        "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.25, 0.5, 0.75, 1.0]}}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
    }
    for kind in ("triangles", "indexed"):
        scene = {
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{"kind": kind, "id": 1, "gltf_json": gltf, "color": "#ffffffff"}],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
        if not data.startswith(b"OS3D01\x00\x00"):
            raise SystemExit(f"scene glTF {kind} lowering did not produce OS3D01")

    scene["meshes"][0]["kind"] = "triangles_rgba"
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if not data.startswith(b"OS3D01\x00\x00") or b"\x40\x80\xbf\xff" not in data:
        raise SystemExit("scene glTF material-color RGBA lowering did not produce expected payload")

    gltf["meshes"][0]["primitives"][0]["attributes"]["COLOR_0"] = 2
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if not data.startswith(b"OS3D01\x00\x00") or b"\x1a\x35\x4f\xff" not in data:
        raise SystemExit("scene glTF material times vertex-color RGBA lowering did not produce averaged payload")

    sparse_payload = bytearray(b"\x01\x02\x00\x00")
    for vertex in ((5.0, 0.0, 0.0), (0.0, 7.0, 0.0)):
        sparse_payload += struct.pack("<fff", *vertex)
    sparse_uri = "data:application/octet-stream;base64," + base64.b64encode(sparse_payload).decode("ascii")
    sparse_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": sparse_uri, "byteLength": len(sparse_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 2},
            {"buffer": 0, "byteOffset": 4, "byteLength": 24},
        ],
        "accessors": [{
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "sparse": {
                "count": 2,
                "indices": {"bufferView": 0, "componentType": 5121},
                "values": {"bufferView": 1},
            },
        }],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
    }
    scene["meshes"][0] = {"kind": "triangles", "id": 1, "gltf_json": sparse_gltf, "color": "#ffffffff"}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    sparse_expected = (
        struct.pack("<iii", 0, 0, 0) +
        struct.pack("<iii", 5, 0, 0) +
        struct.pack("<iii", 0, 7, 0)
    )
    if sparse_expected not in data:
        raise SystemExit("scene glTF sparse POSITION accessor lowering did not produce expected triangle")

    morph_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        morph_payload += struct.pack("<fff", *vertex)
    for delta in ((10.0, 0.0, 0.0), (10.0, 0.0, 0.0), (10.0, 0.0, 0.0)):
        morph_payload += struct.pack("<fff", *delta)
    morph_uri = "data:application/octet-stream;base64," + base64.b64encode(morph_payload).decode("ascii")
    morph_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": morph_uri, "byteLength": len(morph_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 36},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
        ],
        "meshes": [{
            "weights": [0.5],
            "primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 1}]}],
        }],
        "nodes": [{"name": "morph", "mesh": 0, "weights": [0.25], "translation": [1.0, 0.0, 0.0]}],
    }
    scene["meshes"][0] = {"kind": "triangles", "id": 1, "gltf_json": morph_gltf, "color": "#ffffffff"}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<iii", 5, 0, 0) not in data:
        raise SystemExit("scene glTF mesh-weight POSITION morph lowering did not produce expected coordinates")
    scene["meshes"][0]["gltf_node"] = "morph"
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<iii", 4, 0, 0) not in data or struct.pack("<iii", 6, 0, 0) in data:
        raise SystemExit("scene glTF node-weight POSITION morph override did not produce expected coordinates")

    color_morph_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        color_morph_payload += struct.pack("<fff", *vertex)
    for color in ((0.0, 0.0, 0.0, 1.0), (0.25, 0.0, 0.0, 1.0), (0.0, 0.25, 0.0, 1.0)):
        color_morph_payload += struct.pack("<ffff", *color)
    for delta in ((0.5, 0.0, 0.0, 0.0), (0.5, 0.0, 0.0, 0.0), (0.0, 0.5, 0.0, 0.0)):
        color_morph_payload += struct.pack("<ffff", *delta)
    color_morph_uri = "data:application/octet-stream;base64," + base64.b64encode(color_morph_payload).decode("ascii")
    color_morph_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": color_morph_uri, "byteLength": len(color_morph_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 48},
            {"buffer": 0, "byteOffset": 84, "byteLength": 48},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC4"},
            {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"},
        ],
        "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.5, 1.0, 1.0, 1.0]}}],
        "meshes": [{
            "weights": [0.5],
            "primitives": [{
                "attributes": {"POSITION": 0, "COLOR_0": 1},
                "targets": [{"COLOR_0": 2}],
                "material": 0,
            }],
        }],
    }
    scene["meshes"][0] = {"kind": "triangles_rgba", "id": 1, "gltf_json": color_morph_gltf}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if b"\x20\x2a\x00\xff" not in data:
        raise SystemExit("scene glTF COLOR_0 morph target lowering did not produce expected averaged RGBA")

    topo_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (1.0, 1.0, 0.0)):
        topo_payload += struct.pack("<fff", *vertex)
    topo_uri = "data:application/octet-stream;base64," + base64.b64encode(topo_payload).decode("ascii")
    topo_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": topo_uri, "byteLength": len(topo_payload)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(topo_payload)}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "mode": 5}]}],
    }
    scene["meshes"][0] = {"kind": "triangles", "id": 1, "gltf_json": topo_gltf, "color": "#ffffffff"}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    strip_payload = b"".join(struct.pack("<iii", *v) for v in ((0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)))
    if strip_payload not in data:
        raise SystemExit("scene glTF TRIANGLE_STRIP lowering did not produce expected triangles")

    topo_gltf["meshes"][0]["primitives"][0]["mode"] = 6
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    fan_payload = b"".join(struct.pack("<iii", *v) for v in ((1, 0, 0), (0, 1, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 0)))
    if fan_payload not in data:
        raise SystemExit("scene glTF TRIANGLE_FAN lowering did not produce expected triangles")

    glb_doc = dict(gltf)
    glb_doc["buffers"] = [{"byteLength": len(payload)}]
    json_chunk = json.dumps(glb_doc, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
    bin_chunk = bytes(payload) + b"\0" * ((4 - len(payload) % 4) % 4)
    glb = (
        struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)) +
        struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk +
        struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
    )
    glb_path = out_root / "scene3d_gltf_smoke.glb"
    glb_path.write_bytes(glb)
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles_rgba", "id": 1, "gltf_source": glb_path.name}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if not data.startswith(b"OS3D01\x00\x00") or b"\x1a\x35\x4f\xff" not in data:
        raise SystemExit("scene GLB BIN-buffer material times vertex-color RGBA lowering did not produce expected payload")

    node_gltf = json.loads(json.dumps(gltf))
    node_gltf["nodes"] = [
        {"name": "root", "children": [1], "translation": [1.0, 2.0, 3.0], "scale": [2.0, 2.0, 2.0]},
        {"name": "child", "mesh": 0, "translation": [10.0, 20.0, 30.0], "scale": [2.0, 3.0, 4.0]},
    ]
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "gltf_json": node_gltf, "gltf_node": "child", "color": "#ffffffff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if (
        not data.startswith(b"OS3D01\x00\x00") or
        struct.pack("<iii", 21, 42, 63) not in data or
        struct.pack("<iii", 25, 42, 63) not in data
    ):
        raise SystemExit("scene glTF node transform lowering did not produce expected coordinates")

    rot_gltf = json.loads(json.dumps(gltf))
    rot_gltf["nodes"] = [
        {"name": "rot", "mesh": 0, "translation": [1.0, 2.0, 3.0], "rotation": [0.0, 0.0, 0.70710678118, 0.70710678118]},
    ]
    scene["meshes"][0]["gltf_json"] = rot_gltf
    scene["meshes"][0]["gltf_node"] = "rot"
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<iii", 1, 3, 3) not in data or struct.pack("<iii", 0, 2, 3) not in data:
        raise SystemExit("scene glTF node rotation lowering did not produce expected coordinates")

    matrix_gltf = json.loads(json.dumps(gltf))
    matrix_gltf["nodes"] = [
        {"name": "matrix", "mesh": 0, "matrix": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 7.0, 8.0, 9.0, 1.0]},
    ]
    scene["meshes"][0]["gltf_json"] = matrix_gltf
    scene["meshes"][0]["gltf_node"] = "matrix"
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<iii", 7, 8, 9) not in data or struct.pack("<iii", 8, 8, 9) not in data:
        raise SystemExit("scene glTF node matrix lowering did not produce expected coordinates")

    scene_gltf = json.loads(json.dumps(gltf))
    scene_gltf["nodes"] = [
        {"name": "left", "mesh": 0, "translation": [2.0, 0.0, 0.0]},
        {"name": "right", "mesh": 0, "translation": [0.0, 5.0, 0.0]},
    ]
    scene_gltf["scenes"] = [{"name": "all", "nodes": [0, 1]}]
    scene_gltf["scene"] = 0
    scene["meshes"][0] = {"kind": "triangles", "id": 1, "gltf_json": scene_gltf, "gltf_scene": "all", "color": "#ffffffff"}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if (
        struct.pack("<iii", 2, 0, 0) not in data or
        struct.pack("<iii", 3, 0, 0) not in data or
        struct.pack("<iii", 0, 5, 0) not in data or
        struct.pack("<iii", 0, 6, 0) not in data
    ):
        raise SystemExit("scene glTF scene lowering did not include all transformed mesh nodes")

    skin_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        skin_payload += struct.pack("<fff", *vertex)
    for _ in range(3):
        skin_payload += bytes((0, 0, 0, 0))
    for _ in range(3):
        skin_payload += bytes((255, 0, 0, 0))
    skin_payload += struct.pack(
        "<" + "f" * 16,
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    )
    skin_uri = "data:application/octet-stream;base64," + base64.b64encode(skin_payload).decode("ascii")
    skin_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": skin_uri, "byteLength": len(skin_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 12},
            {"buffer": 0, "byteOffset": 48, "byteLength": 12},
            {"buffer": 0, "byteOffset": 60, "byteLength": 64},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5121, "count": 3, "type": "VEC4"},
            {"bufferView": 2, "componentType": 5121, "count": 3, "type": "VEC4", "normalized": True},
            {"bufferView": 3, "componentType": 5126, "count": 1, "type": "MAT4"},
        ],
        "skins": [{"joints": [1], "inverseBindMatrices": 3}],
        "meshes": [{
            "primitives": [{"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2}}],
        }],
        "nodes": [
            {"name": "skinned", "mesh": 0, "skin": 0, "translation": [100.0, 0.0, 0.0]},
            {"name": "joint", "translation": [3.0, 4.0, 5.0]},
        ],
        "scenes": [{"name": "skin", "nodes": [0, 1]}],
        "scene": 0,
    }
    scene["meshes"][0] = {"kind": "triangles", "id": 1, "gltf_json": skin_gltf, "gltf_scene": "skin", "color": "#ffffffff"}
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    skin_expected = (
        struct.pack("<iii", 3, 4, 5) +
        struct.pack("<iii", 4, 4, 5) +
        struct.pack("<iii", 3, 5, 5)
    )
    if skin_expected not in data or struct.pack("<iii", 103, 4, 5) in data:
        raise SystemExit("scene glTF skinning lowering did not apply joint transform while ignoring mesh node transform")

    anim_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        anim_payload += struct.pack("<fff", *vertex)
    for delta in ((0.0, 2.0, 0.0), (0.0, 2.0, 0.0), (0.0, 2.0, 0.0)):
        anim_payload += struct.pack("<fff", *delta)
    anim_payload += struct.pack("<ff", 0.0, 1.0)
    anim_payload += struct.pack("<ffffff", 0.0, 0.0, 0.0, 6.0, 0.0, 0.0)
    anim_payload += struct.pack("<ffffffff", 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0)
    anim_payload += struct.pack("<ffffff", 1.0, 1.0, 1.0, 3.0, 3.0, 1.0)
    anim_payload += struct.pack("<ff", 0.0, 1.0)
    anim_uri = "data:application/octet-stream;base64," + base64.b64encode(anim_payload).decode("ascii")
    anim_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": anim_uri, "byteLength": len(anim_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 36},
            {"buffer": 0, "byteOffset": 72, "byteLength": 8},
            {"buffer": 0, "byteOffset": 80, "byteLength": 24},
            {"buffer": 0, "byteOffset": 104, "byteLength": 32},
            {"buffer": 0, "byteOffset": 136, "byteLength": 24},
            {"buffer": 0, "byteOffset": 160, "byteLength": 8},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0.0], "max": [1.0]},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 6, "componentType": 5126, "count": 2, "type": "SCALAR"},
        ],
        "meshes": [{
            "primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 1}]}],
        }],
        "nodes": [{"name": "animated", "mesh": 0}],
        "animations": [{
            "name": "sampled",
            "channels": [
                {"sampler": 0, "target": {"node": 0, "path": "translation"}},
                {"sampler": 1, "target": {"node": 0, "path": "rotation"}},
                {"sampler": 2, "target": {"node": 0, "path": "scale"}},
                {"sampler": 3, "target": {"node": 0, "path": "weights"}},
            ],
            "samplers": [
                {"input": 2, "output": 3, "interpolation": "LINEAR"},
                {"input": 2, "output": 4, "interpolation": "LINEAR"},
                {"input": 2, "output": 5, "interpolation": "LINEAR"},
                {"input": 2, "output": 6, "interpolation": "LINEAR"},
            ],
        }],
    }
    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "gltf_json": anim_gltf,
        "gltf_node": "animated",
        "gltf_animation": "sampled",
        "gltf_sample_time_milli": 500,
        "color": "#ffffffff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    anim_expected = (
        struct.pack("<iii", 1, 0, 0) +
        struct.pack("<iii", 1, 2, 0) +
        struct.pack("<iii", -1, 0, 0)
    )
    if anim_expected not in data:
        raise SystemExit("scene glTF animation sampling did not apply transform and morph channels")

    cubic_payload = bytearray()
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        cubic_payload += struct.pack("<fff", *vertex)
    cubic_payload += struct.pack("<ff", 0.0, 1.0)
    for value in (
        (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
        (0.0, 0.0, 0.0), (4.0, 0.0, 0.0), (0.0, 0.0, 0.0),
    ):
        cubic_payload += struct.pack("<fff", *value)
    cubic_uri = "data:application/octet-stream;base64," + base64.b64encode(cubic_payload).decode("ascii")
    cubic_gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"uri": cubic_uri, "byteLength": len(cubic_payload)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 8},
            {"buffer": 0, "byteOffset": 44, "byteLength": 72},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0.0], "max": [1.0]},
            {"bufferView": 2, "componentType": 5126, "count": 6, "type": "VEC3"},
        ],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        "nodes": [{"name": "cubic", "mesh": 0}],
        "animations": [{
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}],
            "samplers": [{"input": 1, "output": 2, "interpolation": "CUBICSPLINE"}],
        }],
    }
    scene["meshes"][0] = {
        "kind": "triangles",
        "id": 1,
        "gltf_json": cubic_gltf,
        "gltf_node": "cubic",
        "gltf_sample_time_milli": 500,
        "color": "#ffffffff",
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if struct.pack("<iii", 2, 0, 0) not in data or struct.pack("<iii", 3, 0, 0) not in data:
        raise SystemExit("scene glTF CUBICSPLINE animation sampling did not produce expected translation")


def verify_scene3d_stl_lowering():
    stl_text = "solid smoke\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid smoke\n"
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "stl_text": stl_text, "color": "#ffffffff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if not data.startswith(b"OS3D01\x00\x00"):
        raise SystemExit("scene ASCII STL lowering did not produce OS3D01")

    binary_path = out_root / "scene3d_binary_stl_smoke.stl"
    payload = bytearray(b"solid binary STL smoke".ljust(80, b"\0"))
    payload += struct.pack("<I", 1)
    payload += struct.pack(
        "<ffffffffffffH",
        0.0, 0.0, 1.0,
        0.0, 0.0, 0.0,
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0,
    )
    binary_path.write_bytes(payload)
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "stl_source": binary_path.name, "color": "#ffffffff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if not data.startswith(b"OS3D01\x00\x00"):
        raise SystemExit("scene binary STL lowering did not produce OS3D01")


def verify_scene3d_ply_lowering():
    ply_text = """ply
format ascii 1.0
element vertex 4
property float x
property float y
property float z
element face 1
property list uchar int vertex_indices
end_header
0 0 0
1 0 0
1 1 0
0 1 0
4 0 1 2 3
"""
    for kind in ("triangles", "indexed"):
        scene = {
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{"kind": kind, "id": 1, "ply_text": ply_text, "color": "#ffffffff"}],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
        if not data.startswith(b"OS3D01\x00\x00"):
            raise SystemExit(f"scene ASCII PLY {kind} lowering did not produce OS3D01")

    binary_path = out_root / "scene3d_binary_little_ply_smoke.ply"
    header = (
        "ply\n"
        "format binary_little_endian 1.0\n"
        "element vertex 3\n"
        "property float x\n"
        "property float y\n"
        "property float z\n"
        "element face 1\n"
        "property list uchar int vertex_indices\n"
        "end_header\n"
    ).encode("ascii")
    payload = bytearray(header)
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        payload += struct.pack("<fff", *vertex)
    payload += struct.pack("<Biii", 3, 0, 1, 2)
    binary_path.write_bytes(payload)
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles", "id": 1, "ply_source": binary_path.name, "color": "#ffffffff"}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if not data.startswith(b"OS3D01\x00\x00"):
        raise SystemExit("scene binary little-endian PLY lowering did not produce OS3D01")

    binary_be_path = out_root / "scene3d_binary_big_ply_smoke.ply"
    header = (
        "ply\n"
        "format binary_big_endian 1.0\n"
        "element vertex 3\n"
        "property float x\n"
        "property float y\n"
        "property float z\n"
        "element face 1\n"
        "property list uchar int vertex_indices\n"
        "end_header\n"
    ).encode("ascii")
    payload = bytearray(header)
    for vertex in ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)):
        payload += struct.pack(">fff", *vertex)
    payload += struct.pack(">Biii", 3, 0, 1, 2)
    binary_be_path.write_bytes(payload)
    scene["meshes"][0]["ply_source"] = binary_be_path.name
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if not data.startswith(b"OS3D01\x00\x00"):
        raise SystemExit("scene binary big-endian PLY lowering did not produce OS3D01")

    face_color_ply = """ply
format ascii 1.0
element vertex 3
property float x
property float y
property float z
element face 1
property list uchar int vertex_indices
property uchar red
property uchar green
property uchar blue
property uchar alpha
end_header
0 0 0
1 0 0
0 1 0
3 0 1 2 255 0 0 255
"""
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles_rgba", "id": 1, "ply_text": face_color_ply}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if not data.startswith(b"OS3D01\x00\x00") or b"\xff\x00\x00\xff" not in data:
        raise SystemExit("scene face-color PLY RGBA lowering did not produce expected payload")

    vertex_color_ply = """ply
format ascii 1.0
element vertex 3
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
element face 1
property list uchar int vertex_indices
end_header
0 0 0 30 60 90
1 0 0 60 90 120
0 1 0 90 120 150
3 0 1 2
"""
    scene["meshes"][0]["ply_text"] = vertex_color_ply
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene))
    if not data.startswith(b"OS3D01\x00\x00") or b"\x3c\x5a\x78\xff" not in data:
        raise SystemExit("scene vertex-color PLY RGBA lowering did not produce averaged payload")


def verify_scene3d_3mf_lowering():
    model_xml = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
  <resources>
    <basematerials id="1">
      <base name="red" displaycolor="#ff0000ff"/>
      <base name="green" displaycolor="#00ff00ff"/>
    </basematerials>
    <object id="2" type="model" name="tri" pid="1" pindex="0">
      <mesh>
        <vertices>
          <vertex x="0" y="0" z="0"/>
          <vertex x="1" y="0" z="0"/>
          <vertex x="0" y="1" z="0"/>
          <vertex x="1" y="1" z="0"/>
        </vertices>
        <triangles>
          <triangle v1="0" v2="1" v3="2"/>
          <triangle v1="1" v2="3" v3="2" pid="1" p1="1"/>
          <triangle v1="0" v2="3" v3="1"/>
        </triangles>
        <t:trianglesets xmlns:t="http://schemas.microsoft.com/3dmanufacturing/trianglesets/2021/07">
          <t:triangleset name="front" identifier="seg:front">
            <t:ref index="1"/>
            <t:ref index="1"/>
            <t:refrange startindex="2" endindex="2"/>
          </t:triangleset>
        </t:trianglesets>
      </mesh>
    </object>
    <object id="3" type="model" name="component-tri">
      <components>
        <component objectid="2" transform="1 0 0 0 1 0 0 0 1 3 4 5"/>
      </components>
    </object>
  </resources>
  <build>
    <item objectid="3" transform="1 0 0 0 1 0 0 0 1 7 8 9"/>
  </build>
</model>
"""
    rels_xml = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""
    source_path = out_root / "scene3d_3mf_smoke.3mf"
    with zipfile.ZipFile(source_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("_rels/.rels", rels_xml)
        zf.writestr("3D/3dmodel.model", model_xml)
    for kind in ("triangles", "indexed"):
        scene = {
            "schema": "oren.ui.scene3d.v0",
            "meshes": [{"kind": kind, "id": 1, "3mf_source": source_path.name, "color": "#ffffffff"}],
            "models": [{"id": 2, "mesh_id": 1}],
            "draw": [2],
        }
        data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
        if (
            not data.startswith(b"OS3D01\x00\x00") or
            struct.pack("<iii", 10, 12, 14) not in data or
            struct.pack("<iii", 11, 12, 14) not in data or
            struct.pack("<iii", 10, 13, 14) not in data
        ):
            raise SystemExit(f"scene 3MF {kind} lowering did not produce expected coordinates")
    scene = {
        "schema": "oren.ui.scene3d.v0",
        "meshes": [{"kind": "triangles_rgba", "id": 1, "3mf_source": source_path.name}],
        "models": [{"id": 2, "mesh_id": 1}],
        "draw": [2],
    }
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if not data.startswith(b"OS3D01\x00\x00") or b"\xff\x00\x00\xff" not in data or b"\x00\xff\x00\xff" not in data:
        raise SystemExit("scene 3MF basematerial RGBA lowering did not produce expected colors")
    scene["meshes"][0]["3mf_triangle_set"] = "front"
    data = scene3d_module.scene3d_bin_v0(json.dumps(scene), out_root)
    if (
        not data.startswith(b"OS3D01\x00\x00") or
        data.count(b"\x00\xff\x00\xff") != 1 or
        data.count(b"\xff\x00\x00\xff") != 1
    ):
        raise SystemExit("scene 3MF triangle-set RGBA lowering did not select expected colors")


verify_scene3d_obj_lowering()
verify_scene3d_flat_xy_lowering()
verify_scene3d_flat_shape_lowering()
verify_scene3d_flat_line_lowering()
verify_scene3d_flat_curve_lowering()
verify_scene3d_flat_arch_lowering()
verify_scene3d_gltf_lowering()
verify_scene3d_stl_lowering()
verify_scene3d_ply_lowering()
verify_scene3d_3mf_lowering()


def write_deterministic_zip(zip_path, files):
    with zipfile.ZipFile(
        zip_path,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as zf:
        for arcname, path in sorted(files):
            info = zipfile.ZipInfo(arcname)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())


def rgba_png(width, height, pixels):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        off = y * stride
        raw.extend(pixels[off:off + stride])

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def color(hex_color):
    s = hex_color.lstrip("#")
    if len(s) == 6:
        s += "ff"
    return tuple(int(s[i:i + 2], 16) for i in range(0, 8, 2))


def make_canvas(width=640, height=360, bg="#102820"):
    r, g, b, a = color(bg)
    return bytearray([r, g, b, a] * width * height)


def put_px(pixels, width, height, x, y, c):
    if 0 <= x < width and 0 <= y < height:
        off = (y * width + x) * 4
        pixels[off:off + 4] = bytes(c)


def rect(pixels, width, height, x, y, w, h, fill):
    c = color(fill)
    x0 = max(0, x)
    y0 = max(0, y)
    x1 = min(width, x + w)
    y1 = min(height, y + h)
    row = bytes(c) * max(0, x1 - x0)
    for yy in range(y0, y1):
        off = (yy * width + x0) * 4
        pixels[off:off + len(row)] = row


def circle(pixels, width, height, cx, cy, radius, fill):
    c = color(fill)
    rr = radius * radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rr:
                put_px(pixels, width, height, x, y, c)


FONT_5X7 = {
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    ",": ["00000", "00000", "00000", "00000", "01100", "01100", "01000"],
    "-": ["00000", "00000", "00000", "11110", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "/": ["00001", "00010", "00100", "01000", "10000", "00000", "00000"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "=": ["00000", "11110", "00000", "11110", "00000", "00000", "00000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "[": ["01110", "01000", "01000", "01000", "01000", "01000", "01110"],
    "]": ["01110", "00010", "00010", "00010", "00010", "00010", "01110"],
    "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "11100"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}


def draw_text(pixels, width, height, x, y, text, fill="#102820", scale=2, spacing=1):
    c = color(fill)
    cursor = x
    for ch in text.upper():
        glyph = FONT_5X7.get(ch, FONT_5X7[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    rect(pixels, width, height, cursor + gx * scale, y + gy * scale, scale, scale, fill)
        cursor += (5 + spacing) * scale


def draw_scaled_rect(pixels, width, height, x, y, w, h, fill, scale=2):
    rect(pixels, width, height, x * scale, y * scale, w * scale, h * scale, fill)


def draw_scaled_line(pixels, width, height, x0, y0, x1, y1, stroke, thickness=1, scale=2):
    line(pixels, width, height, x0 * scale, y0 * scale, x1 * scale, y1 * scale, stroke, thickness * scale)


def draw_scaled_circle(pixels, width, height, cx, cy, radius, fill, scale=2):
    circle(pixels, width, height, cx * scale, cy * scale, radius * scale, fill)


def line(pixels, width, height, x0, y0, x1, y1, stroke, thickness=1):
    c = color(stroke)
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        for oy in range(-(thickness // 2), thickness // 2 + 1):
            for ox in range(-(thickness // 2), thickness // 2 + 1):
                put_px(pixels, width, height, x0 + ox, y0 + oy, c)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def triangle(pixels, width, height, pts, fill):
    c = color(fill)
    (x0, y0), (x1, y1), (x2, y2) = pts
    min_x = max(0, min(x0, x1, x2))
    max_x = min(width - 1, max(x0, x1, x2))
    min_y = max(0, min(y0, y1, y2))
    max_y = min(height - 1, max(y0, y1, y2))
    area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
    if area == 0:
        return
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            w0 = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)
            w1 = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
            w2 = (x0 - x2) * (y - y2) - (y0 - y2) * (x - x2)
            if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
                put_px(pixels, width, height, x, y, c)


def render_demo_preview(name):
    w, h = 640, 360
    pixels = make_canvas(w, h, "#102820")
    rect(pixels, w, h, 0, 0, w, h, "#102820")
    if name == "science-calculator":
        rect(pixels, w, h, 40, 38, 560, 284, "#f5efe0")
        rect(pixels, w, h, 62, 62, 516, 236, "#17211f")
        draw_text(pixels, w, h, 86, 86, "STD:MATH + STD:LINALG", "#f5efe0", 3)
        draw_text(pixels, w, h, 86, 136, "POWER(2,-1) = 0.5", "#e38b29", 2)
        draw_text(pixels, w, h, 86, 168, "POWER(2,4.3) = 19.7", "#e38b29", 2)
        draw_text(pixels, w, h, 86, 200, "DOT([1,2,3],[4,5,6]) = 32", "#f5efe0", 2)
        draw_text(pixels, w, h, 86, 248, "SCIENCE-CALCULATOR OK", "#00d084", 2)
        for i, height_bar in enumerate([42, 78, 112]):
            rect(pixels, w, h, 446 + i * 34, 258 - height_bar, 22, height_bar, "#e38b29")
        line(pixels, w, h, 430, 258, 548, 258, "#f5efe0", 2)
    elif name == "scene3d-asset-demo":
        rect(pixels, w, h, 36, 36, 572, 292, "#f5efe0")
        rect(pixels, w, h, 56, 56, 532, 252, "#17211f")
        draw_text(pixels, w, h, 86, 82, "SCENE3D .OS3D ASSET", "#f5efe0", 3)
        grid_x, grid_y, cell = 92, 142, 44
        scene = [
            ["#102820", "#102820", "#102820", "#102820"],
            ["#102820", "#00ff00", "#00ff00", "#102820"],
            ["#102820", "#00ff00", "#ff0000", "#102820"],
            ["#102820", "#102820", "#102820", "#102820"],
        ]
        for yy, row in enumerate(scene):
            for xx, fill in enumerate(row):
                rect(pixels, w, h, grid_x + xx * cell, grid_y + yy * cell, cell - 3, cell - 3, fill)
        draw_text(pixels, w, h, 300, 146, "OBJ + STL + PLY", "#e38b29", 2)
        draw_text(pixels, w, h, 300, 182, "MESH + MATERIAL + MODEL", "#f5efe0", 2)
        draw_text(pixels, w, h, 300, 218, "PACKAGE VFS: ASSETS/", "#f5efe0", 2)
        draw_text(pixels, w, h, 300, 254, "RASTER CHECK 7X7 OK", "#00d084", 2)
    else:
        # Faithful 2x scale rendering of examples/obc_store_demos/ui_card.oren.
        draw_scaled_rect(pixels, w, h, 0, 0, 320, 180, "#102820")
        draw_scaled_rect(pixels, w, h, 18, 18, 284, 144, "#f5efe0")
        draw_scaled_line(pixels, w, h, 18, 128, 302, 128, "#146c5b", 2)
        draw_scaled_circle(pixels, w, h, 272, 58, 28, "#e38b29")
        draw_text(pixels, w, h, 68, 104, "OREN AVM UI", "#102820", 3)
        draw_text(pixels, w, h, 68, 184, "BINARY OGF0 FRAME DEMO", "#36584d", 2)
    return rgba_png(w, h, pixels)

seen = set()
index_packages = []
for item in spec:
    ident = (item["publisher"], item["name"], item["version"])
    if ident in seen:
        raise SystemExit(f"duplicate demo package: {ident}")
    seen.add(ident)
    source = pathlib.Path(item["source"])
    if not source.is_file():
        raise SystemExit(f"missing source: {source}")

    pkg_dir = packages_root / item["publisher"] / item["name"] / item["version"]
    pkg_dir.mkdir(parents=True, exist_ok=True)
    source_asset = pkg_dir / "assets" / "source" / "main.oren"
    source_asset.parent.mkdir(parents=True, exist_ok=True)
    source_bytes = source.read_bytes()
    source_asset.write_bytes(source_bytes)
    screenshot_asset = pkg_dir / "screenshots" / "preview.png"
    screenshot_asset.parent.mkdir(parents=True, exist_ok=True)
    screenshot_bytes = render_demo_preview(item["name"])
    screenshot_asset.write_bytes(screenshot_bytes)
    extra_assets = []
    for asset in item.get("assets", []):
        asset_source = pathlib.Path(asset["source"])
        asset_path = asset["path"]
        if not asset_source.is_file():
            raise SystemExit(f"missing asset source: {asset_source}")
        if asset_path.startswith("/") or ".." in pathlib.PurePosixPath(asset_path).parts:
            raise SystemExit(f"unsafe asset path: {asset_path}")
        asset_out = pkg_dir / asset_path
        asset_out.parent.mkdir(parents=True, exist_ok=True)
        asset_bytes = asset_source.read_bytes()
        if asset.get("format") == "scene3d_bin_v0":
            asset_bytes = scene3d_module.scene3d_bin_v0(asset_bytes, asset_source.parent)
        asset_out.write_bytes(asset_bytes)
        extra_assets.append((asset, asset_out, asset_bytes))
    obc_path = pkg_dir / "program.obc"
    build_log = log_dir / f"obc_store_demo_{item['publisher']}_{item['name']}_{item['version']}_build.log"
    run_log = log_dir / f"obc_store_demo_{item['publisher']}_{item['name']}_{item['version']}_run.log"

    with build_log.open("wb") as log:
        subprocess.check_call(
            [compiler, "build", str(source), "--backend", "bytecode", "-o", str(obc_path)],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    run_cmd = [avm, "--deny-by-default", "--allow-domains", item["run_allow_domains"], "--print-run-json"]
    if extra_assets:
        run_cmd.extend([
            "--fs-backend",
            "host",
            "--fs-allow-prefixes",
            "assets/",
            "--fs-mounts-read",
            f"assets/={pkg_dir / 'assets'}/",
        ])
    run_cmd.append(str(obc_path))
    with run_log.open("wb") as log:
        subprocess.check_call(run_cmd, stdout=log, stderr=subprocess.STDOUT)

    obc_sha = hashlib.sha256(obc_path.read_bytes()).hexdigest()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    asset_entries = [
        {
            "path": "assets/source/main.oren",
            "sha256": source_sha,
            "media_type": "text/x-oren",
            "role": "source",
        },
    ]
    for asset, _asset_out, asset_bytes in extra_assets:
        asset_entries.append({
            "path": asset["path"],
            "sha256": hashlib.sha256(asset_bytes).hexdigest(),
            "media_type": asset.get("media_type", "application/octet-stream"),
            "role": asset.get("role", "asset"),
        })

    manifest = {
        "schema": "oren.obc.package.v0",
        "publisher": item["publisher"],
        "name": item["name"],
        "version": item["version"],
        "title": item["title"],
        "summary": item["summary"],
        "entry_obc": "program.obc",
        "obc_sha256": obc_sha,
        "oren_min": "0.0.rolling",
        "avm_abi_min": 8,
        "capabilities": item["capabilities"],
        "tags": item["tags"],
        "assets": asset_entries,
        "sources": [
            {
                "path": "assets/source/main.oren",
                "language": "oren",
                "role": "main",
            }
        ],
        "time_mode": "deterministic",
        "budgets": {
            "gas": 5000000,
            "heap_bytes": 33554432,
            "io_bytes": 1048576,
            "frame_commands": 1024,
        },
    }
    if extra_assets:
        manifest["vfs_mounts"] = [
            {
                "virtual": "assets/",
                "package_path": "assets/",
                "read_only": True,
            }
        ]
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    (pkg_dir / "package.json").write_bytes(manifest_bytes)
    manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
    bundle_path = bundles_root / f"{item['publisher']}__{item['name']}__{item['version']}.obc.zip"
    bundle_files = [
        ("assets/source/main.oren", source_asset),
        ("package.json", pkg_dir / "package.json"),
        ("program.obc", obc_path),
    ]
    for asset, asset_out, _asset_bytes in extra_assets:
        bundle_files.append((asset["path"], asset_out))
    write_deterministic_zip(bundle_path, bundle_files)
    bundle_sha = hashlib.sha256(bundle_path.read_bytes()).hexdigest()
    index_packages.append({
        "id": item["publisher"] + "/" + item["name"],
        "version": item["version"],
        "bundle": f"bundles/{bundle_path.name}",
        "bundle_media_type": "application/vnd.oren.obc.release+zip",
        "bundle_sha256": bundle_sha,
        "manifest": f"packages/{item['publisher']}/{item['name']}/{item['version']}/package.json",
        "manifest_sha256": manifest_sha,
        "tags": item["tags"],
        "min_app": "0.1.0",
    })

index = {
    "schema": "oren.obc.store.index.v0",
    "generated_at": "1970-01-01T00:00:00Z",
    "packages": index_packages,
}
(out_root / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")

for entry in index_packages:
    manifest_path = out_root / entry["manifest"]
    bundle_path = out_root / entry["bundle"]
    if hashlib.sha256(manifest_path.read_bytes()).hexdigest() != entry["manifest_sha256"]:
        raise SystemExit(f"manifest hash mismatch: {manifest_path}")
    if hashlib.sha256(bundle_path.read_bytes()).hexdigest() != entry["bundle_sha256"]:
        raise SystemExit(f"bundle hash mismatch: {bundle_path}")
    with zipfile.ZipFile(bundle_path) as zf:
        names = sorted(zf.namelist())
        manifest = json.loads(zf.read("package.json"))
        expected_names = sorted(["package.json", "program.obc"] + [a["path"] for a in manifest.get("assets", [])])
        if names != expected_names:
            raise SystemExit(f"bad release bundle layout: {bundle_path}: {names}")
        if not any(a.get("role") == "source" and a.get("path") == "assets/source/main.oren" for a in manifest.get("assets", [])):
            raise SystemExit(f"missing source asset declaration: {bundle_path}")
        if any(a.get("role") == "screenshot" for a in manifest.get("assets", [])):
            raise SystemExit(f"screenshot leaked into package assets: {bundle_path}")
        if "screenshots/preview.png" in names:
            raise SystemExit(f"screenshot leaked into release bundle: {bundle_path}")
        if not any(s.get("path") == "assets/source/main.oren" for s in manifest.get("sources", [])):
            raise SystemExit(f"missing source declaration: {bundle_path}")
    screenshot_path = manifest_path.parent / "screenshots" / "preview.png"
    if not screenshot_path.is_file():
        raise SystemExit(f"missing portal screenshot: {screenshot_path}")
print(f"OBC store demo packages built under {out_root}")
PY
