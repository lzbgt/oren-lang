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


def color_rgba_bytes(s):
    rgba = color_u32(s)
    return bytes([
        (rgba >> 24) & 0xFF,
        (rgba >> 16) & 0xFF,
        (rgba >> 8) & 0xFF,
        rgba & 0xFF,
    ])


def color_hex_from_rgba(r, g, b, a):
    return f"#{int(r):02x}{int(g):02x}{int(b):02x}{int(a):02x}"


def material_color_hex(item, context):
    color = item.get("color", item.get("base_color"))
    if color is None:
        raise SystemExit(f"{context} missing color")
    rgba = color_u32(color)
    r = (rgba >> 24) & 0xFF
    g = (rgba >> 16) & 0xFF
    b = (rgba >> 8) & 0xFF
    a = rgba & 0xFF
    opacity = item.get("opacity_milli")
    if opacity is not None:
        opacity = int(opacity)
        if opacity < 0 or opacity > 1000:
            raise SystemExit(f"{context} opacity_milli out of range")
        a = (a * opacity) // 1000
    for key in ("roughness_milli", "metallic_milli"):
        if item.get(key) is not None:
            v = int(item[key])
            if v < 0 or v > 1000:
                raise SystemExit(f"{context} {key} out of range")
    return color_hex_from_rgba(r, g, b, a)


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


def pack_faces(faces, vertex_count):
    out = bytearray()
    for face in faces:
        if not isinstance(face, list) or len(face) != 3:
            raise SystemExit("scene faces entries must be [a,b,c]")
        if any(int(idx) < 0 or int(idx) >= vertex_count for idx in face):
            raise SystemExit("scene face index out of bounds")
        out += u32(face[0]) + u32(face[1]) + u32(face[2])
    return bytes(out)


def pack_triangles_xyz(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, list) or len(tri) != 3:
            raise SystemExit("scene triangles_xyz entries must contain 3 vertices")
        out += pack_vertices_xyz(tri)
    return bytes(out)


def pack_triangles_xyz_rgba(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, dict):
            raise SystemExit("scene triangles_xyz_rgba entries must be objects")
        verts = tri.get("vertices")
        color = tri.get("color")
        if not isinstance(verts, list) or len(verts) != 3:
            raise SystemExit("scene triangles_xyz_rgba vertices must contain 3 points")
        if color is None:
            raise SystemExit("scene triangles_xyz_rgba entries must include color")
        out += pack_vertices_xyz(verts)
        out += color_rgba_bytes(color)
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


def apply_position(model):
    transform = model.get("transform") or {}
    if not isinstance(transform, dict):
        raise SystemExit("scene transform must be an object")
    pos = model.get("position_xyz", transform.get("position_xyz"))
    if pos is None:
        return
    if not isinstance(pos, list) or len(pos) != 3:
        raise SystemExit("scene position_xyz must be [x,y,z]")
    model["x"], model["y"], model["z"] = pos


def apply_transform(model):
    transform = model.get("transform") or {}
    if not isinstance(transform, dict):
        raise SystemExit("scene transform must be an object")
    apply_position(model)
    if model.get("scale_milli") is None and transform.get("scale_milli") is not None:
        model["scale_milli"] = transform["scale_milli"]
    if int(model.get("scale_milli", 1000)) <= 0:
        raise SystemExit("scene scale_milli must be positive")


def lerp_int(a, b, num, den):
    if den <= 0:
        return int(a)
    return int(a) + ((int(b) - int(a)) * int(num)) // int(den)


def key_axis(keyframe, axis, key, fallback):
    transform = keyframe.get("transform") or {}
    if not isinstance(transform, dict):
        raise SystemExit("scene animation transform must be an object")
    pos = keyframe.get("position_xyz", transform.get("position_xyz"))
    if pos is not None:
        if not isinstance(pos, list) or len(pos) != 3:
            raise SystemExit("scene animation position_xyz must be [x,y,z]")
        return pos[axis]
    return keyframe.get(key, fallback)


def key_scale(keyframe, fallback):
    transform = keyframe.get("transform") or {}
    if not isinstance(transform, dict):
        raise SystemExit("scene animation transform must be an object")
    scale = keyframe.get("scale_milli", transform.get("scale_milli", fallback))
    if int(scale) <= 0:
        raise SystemExit("scene animation scale_milli must be positive")
    return scale


def sample_keyframes(keyframes, time_milli, model):
    if not isinstance(keyframes, list) or not keyframes:
        raise SystemExit("scene animation keyframes must be non-empty")
    prev = None
    prev_t = -1
    nxt = None
    next_t = -1
    for keyframe in keyframes:
        if not isinstance(keyframe, dict):
            raise SystemExit("scene animation keyframes must be objects")
        t = int(keyframe.get("time_milli", -1))
        if t < 0:
            raise SystemExit("scene animation keyframe time_milli must be non-negative")
        if t <= time_milli and (prev is None or t >= prev_t):
            prev = keyframe
            prev_t = t
        if t >= time_milli and (nxt is None or t <= next_t):
            nxt = keyframe
            next_t = t
    if prev is None:
        prev = nxt
        prev_t = next_t
    if nxt is None:
        nxt = prev
        next_t = prev_t
    base_x = model.get("x", 0)
    base_y = model.get("y", 0)
    base_z = model.get("z", 0)
    base_scale = model.get("scale_milli", 1000)
    ax = key_axis(prev, 0, "x", base_x)
    ay = key_axis(prev, 1, "y", base_y)
    az = key_axis(prev, 2, "z", base_z)
    ascale = key_scale(prev, base_scale)
    bx = key_axis(nxt, 0, "x", ax)
    by = key_axis(nxt, 1, "y", ay)
    bz = key_axis(nxt, 2, "z", az)
    bscale = key_scale(nxt, ascale)
    den = next_t - prev_t
    num = int(time_milli) - prev_t
    return {
        "x": lerp_int(ax, bx, num, den),
        "y": lerp_int(ay, by, num, den),
        "z": lerp_int(az, bz, num, den),
        "scale_milli": lerp_int(ascale, bscale, num, den),
    }


def apply_animations(models, animations, time_milli):
    model_by_name = {m["name"]: m for m in models if m.get("name") is not None}
    model_by_id = {m["id"]: m for m in models if m.get("id") is not None}
    for anim in animations or []:
        target = anim.get("target")
        target_id = anim.get("target_id")
        model = model_by_id.get(target_id) if target_id is not None else model_by_name.get(target)
        if model is None:
            raise SystemExit("scene animation target missing")
        model.update(sample_keyframes(anim.get("keyframes"), time_milli, model))


def draw_model_override(draw, models, model_names, mesh_names, material_names, generated_id):
    target = draw.get("model")
    target_id = draw.get("model_id")
    base = None
    if target_id is not None:
        base = next((m for m in models if m.get("id") == target_id), None)
    elif target is not None:
        base_id = model_names.get(target)
        base = next((m for m in models if m.get("id") == base_id), None)
    if (target is not None or target_id is not None) and base is None:
        raise SystemExit("unknown scene draw model")

    m = dict(base or {})
    m.update(draw)
    if m.get("mesh_id") is None and m.get("mesh") is None:
        raise SystemExit("scene draw object missing mesh/model")
    m["mesh_id"] = resolve_id(m, "mesh_id", "mesh", mesh_names)
    m["material_id"] = resolve_id(m, "material_id", "material", material_names, 0)
    if m.get("id") is None:
        m["id"] = generated_id
    apply_transform(m)
    return m


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
        apply_transform(m)
        models.append(m)

    for inst in scene.get("instances", []):
        tpl = templates.get(inst.get("template"), {})
        if inst.get("template") is not None and not tpl:
            raise SystemExit(f"unknown scene template: {inst.get('template')!r}")
        m = dict(tpl)
        m.update(inst)
        m["mesh_id"] = resolve_id(m, "mesh_id", "mesh", mesh_names)
        m["material_id"] = resolve_id(m, "material_id", "material", material_names, 0)
        apply_transform(m)
        models.append(m)

    if scene.get("animations") is not None:
        apply_animations(models, scene.get("animations"), int(scene.get("sample_time_milli", 0)))

    model_names = index_names(models)
    draws = []
    next_draw_model_id = max([0] + [int(m.get("id", 0)) for m in models]) + 1
    for draw in scene.get("draw", []):
        if isinstance(draw, str):
            if draw not in model_names:
                raise SystemExit(f"unknown scene draw model: {draw!r}")
            draws.append(model_names[draw])
        elif isinstance(draw, int):
            draws.append(draw)
        elif isinstance(draw, dict):
            if draw.get("op") is not None:
                raise SystemExit("scene binary draw objects must use model/mesh references, not op commands")
            m = draw_model_override(draw, models, model_names, mesh_names, material_names, next_draw_model_id)
            models.append(m)
            if m.get("name") is not None:
                model_names[m["name"]] = m["id"]
            draws.append(m["id"])
            if draw.get("id") is None:
                next_draw_model_id += 1
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
            if len(payload) % 12 != 0:
                raise SystemExit("scene indexed mesh vertex bytes must be multiple of 12")
            vertex_count = len(payload) // 12
            indices = pack_faces(mesh["faces"], vertex_count) if mesh.get("faces") is not None else bytes(mesh["indices"])
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
            payload = (
                pack_triangles_xyz_rgba(mesh["triangles_xyz_rgba"])
                if mesh.get("triangles_xyz_rgba") is not None
                else bytes(mesh["triangles"])
            )
            indices = b""
        else:
            raise SystemExit(f"unsupported scene mesh kind: {kind}")
        mesh_color = material_color_hex(mesh, "scene mesh") if kind_id != 3 else "#00000000"
        out += u32(mesh["id"]) + u32(kind_id) + u32(color_u32(mesh_color))
        out += u32(len(payload)) + u32(len(indices)) + payload + indices
    for material in materials:
        out += u32(material["id"]) + u32(color_u32(material_color_hex(material, "scene material")))
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
