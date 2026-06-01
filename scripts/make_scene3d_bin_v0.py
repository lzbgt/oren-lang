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


def pack_vertices_xyz(points):
    out = bytearray()
    for point in points:
        if not isinstance(point, list) or len(point) != 3:
            raise SystemExit("scene vertices_xyz entries must be [x,y,z]")
        out += i32(point[0]) + i32(point[1]) + i32(point[2])
    return bytes(out)


def pack_faces(faces):
    out = bytearray()
    for face in faces:
        if not isinstance(face, list) or len(face) != 3:
            raise SystemExit("scene faces entries must be [a,b,c]")
        out += u32(face[0]) + u32(face[1]) + u32(face[2])
    return bytes(out)


def pack_triangles_xyz(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, list) or len(tri) != 3:
            raise SystemExit("scene triangles_xyz entries must contain 3 vertices")
        out += pack_vertices_xyz(tri)
    return bytes(out)


def index_names(items):
    out = {}
    for item in items or []:
        name = item.get("name")
        item_id = item.get("id")
        if name is not None and item_id is not None:
            out[name] = item_id
    return out


def resolve_id(item, id_key, name_key, names, fallback=None):
    if item.get(id_key) is not None:
        return item[id_key]
    name = item.get(name_key)
    if name is None:
        return fallback
    if name not in names:
        raise SystemExit(f"unknown scene {name_key}: {name!r}")
    return names[name]


def normalize_scene(scene):
    meshes = scene.get("meshes", [])
    materials = scene.get("materials", [])
    mesh_names = index_names(meshes)
    material_names = index_names(materials)
    templates = {m["name"]: m for m in scene.get("model_templates", []) if m.get("name") is not None}

    models = []
    for model in scene.get("models", []):
        m = dict(model)
        m["mesh_id"] = resolve_id(m, "mesh_id", "mesh", mesh_names)
        m["material_id"] = resolve_id(m, "material_id", "material", material_names, 0)
        models.append(m)

    for inst in scene.get("instances", []):
        tpl = templates.get(inst.get("template"), {})
        if inst.get("template") is not None and not tpl:
            raise SystemExit(f"unknown scene template: {inst.get('template')!r}")
        m = dict(tpl)
        m.update(inst)
        m["mesh_id"] = resolve_id(m, "mesh_id", "mesh", mesh_names)
        m["material_id"] = resolve_id(m, "material_id", "material", material_names, 0)
        models.append(m)

    model_names = index_names(models)
    draws = []
    for draw in scene.get("draw", []):
        if isinstance(draw, str):
            if draw not in model_names:
                raise SystemExit(f"unknown scene draw model: {draw!r}")
            draws.append(model_names[draw])
        else:
            draws.append(draw)

    out = dict(scene)
    out["models"] = models
    out["draw"] = draws
    return out


def scene3d_bin_v0(scene_bytes):
    scene = normalize_scene(json.loads(scene_bytes))
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
            payload = (
                pack_vertices_xyz(mesh["vertices_xyz"])
                if mesh.get("vertices_xyz") is not None
                else bytes(mesh["vertices"])
            )
            indices = pack_faces(mesh["faces"]) if mesh.get("faces") is not None else bytes(mesh["indices"])
        elif kind == "triangles":
            kind_id = 2
            payload = (
                pack_triangles_xyz(mesh["triangles_xyz"])
                if mesh.get("triangles_xyz") is not None
                else bytes(mesh["triangles"])
            )
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
