#!/usr/bin/env python3
"""Build byte-native OS3D01 scene assets from reviewable JSON."""

import json
import pathlib
import sys


def color_u32(s):
    if not isinstance(s, str) or not s.startswith("#") or len(s) not in (7, 9):
        raise SystemExit(f"invalid scene color: {s!r}")
    if len(s) == 7:
        s += "ff"
    return int(s[1:], 16)


def u32(v):
    return int(v).to_bytes(4, "little", signed=False)


def i32(v):
    return int(v).to_bytes(4, "little", signed=True)


def scene3d_bin_v0(scene_bytes):
    scene = json.loads(scene_bytes)
    out = bytearray(b"OS3D01\x00\x00")
    meshes = scene.get("meshes", [])
    materials = scene.get("materials", [])
    models = scene.get("models", [])
    draws = scene.get("draw", [])
    camera = scene.get("camera")
    out += u32(len(meshes)) + u32(len(materials)) + u32(len(models)) + u32(len(draws))
    flags = 1 if scene.get("destroy") else 0
    if camera is not None:
        flags |= 2
    out += u32(flags)
    if camera is not None:
        out += i32(camera.get("near_z", 0)) + i32(camera.get("far_z", 0))
    for mesh in meshes:
        kind = mesh.get("kind", "triangles")
        if kind == "indexed":
            kind_id = 1
            payload = bytes(mesh["vertices"])
            indices = bytes(mesh["indices"])
        elif kind == "triangles":
            kind_id = 2
            payload = bytes(mesh["triangles"])
            indices = b""
        elif kind == "triangles_rgba":
            kind_id = 3
            payload = bytes(mesh["triangles"])
            indices = b""
        else:
            raise SystemExit(f"unsupported scene mesh kind: {kind}")
        out += u32(mesh["id"]) + u32(kind_id) + u32(color_u32(mesh.get("color", "#00000000")))
        out += u32(len(payload)) + u32(len(indices)) + payload + indices
    for material in materials:
        out += u32(material["id"]) + u32(color_u32(material["color"]))
    for model in models:
        out += (
            u32(model["id"]) + u32(model["mesh_id"]) + u32(model.get("material_id", 0)) +
            i32(model.get("x", 0)) + i32(model.get("y", 0)) + i32(model.get("z", 0)) +
            u32(model.get("scale_milli", 1000))
        )
    for draw in draws:
        out += u32(draw)
    return bytes(out)


def main(argv):
    if len(argv) != 3:
        raise SystemExit("usage: make_scene3d_bin_v0.py <scene.json> <out.os3d>")
    src = pathlib.Path(argv[1])
    out = pathlib.Path(argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(scene3d_bin_v0(src.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main(sys.argv)
