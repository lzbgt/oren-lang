#!/usr/bin/env python3
"""Build byte-native OS3D01 scene assets from reviewable JSON."""

import base64
import json
import math
import pathlib
import struct
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


def pack_quads(quads, vertex_count):
    faces = []
    for quad in quads:
        if not isinstance(quad, list) or len(quad) != 4:
            raise SystemExit("scene quads entries must be [a,b,c,d]")
        if any(int(idx) < 0 or int(idx) >= vertex_count for idx in quad):
            raise SystemExit("scene quad index out of bounds")
        faces.append([quad[0], quad[1], quad[2]])
        faces.append([quad[0], quad[2], quad[3]])
    return pack_faces(faces, vertex_count)


def has_obj_mesh(mesh):
    return mesh.get("obj_source") is not None or mesh.get("obj_text") is not None


def obj_source_text(mesh, base_dir):
    if mesh.get("obj_text") is not None:
        text = mesh["obj_text"]
        if not isinstance(text, str):
            raise SystemExit("scene obj_text must be a string")
        return text
    rel = mesh.get("obj_source")
    if rel is None:
        raise SystemExit("scene OBJ mesh must include obj_source or obj_text")
    if base_dir is None:
        raise SystemExit("scene obj_source requires a source directory")
    rel_path = pathlib.PurePosixPath(str(rel))
    if rel_path.is_absolute() or ".." in rel_path.parts:
        raise SystemExit("scene obj_source must be a safe relative path")
    path = base_dir / pathlib.Path(*rel_path.parts)
    if not path.is_file():
        raise SystemExit(f"scene obj_source not found: {rel}")
    return path.read_text(encoding="utf-8")


def parse_obj_vertex_index(token, vertex_count, line_no):
    raw = token.split("/")[0]
    if raw == "":
        raise SystemExit(f"scene OBJ face missing vertex index on line {line_no}")
    idx = int(raw)
    if idx == 0:
        raise SystemExit(f"scene OBJ indices are 1-based on line {line_no}")
    if idx < 0:
        idx = vertex_count + idx
    else:
        idx -= 1
    if idx < 0 or idx >= vertex_count:
        raise SystemExit(f"scene OBJ face index out of bounds on line {line_no}")
    return idx


def obj_mesh_data(mesh, base_dir):
    vertices = []
    faces = []
    for line_no, raw in enumerate(obj_source_text(mesh, base_dir).splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if line == "":
            continue
        parts = line.split()
        tag = parts[0]
        if tag == "v":
            if len(parts) < 4:
                raise SystemExit(f"scene OBJ vertex must have x y z on line {line_no}")
            vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
        elif tag == "f":
            if len(parts) < 4:
                raise SystemExit(f"scene OBJ face must have at least 3 vertices on line {line_no}")
            face = [parse_obj_vertex_index(tok, len(vertices), line_no) for tok in parts[1:]]
            for i in range(1, len(face) - 1):
                faces.append([face[0], face[i], face[i + 1]])
        elif tag in ("vt", "vn", "o", "g", "s", "usemtl", "mtllib"):
            continue
        else:
            raise SystemExit(f"unsupported scene OBJ line {line_no}: {tag}")
    if not vertices:
        raise SystemExit("scene OBJ mesh has no vertices")
    if not faces:
        raise SystemExit("scene OBJ mesh has no faces")
    return vertices, faces


def obj_transform_vertex(v, mesh):
    scale_milli = int(mesh.get("obj_scale_milli", 1000))
    if scale_milli <= 0:
        raise SystemExit("scene OBJ obj_scale_milli must be positive")
    offset = mesh.get("obj_offset_xyz", [0, 0, 0])
    if not isinstance(offset, list) or len(offset) != 3:
        raise SystemExit("scene OBJ obj_offset_xyz must be [x,y,z]")
    return [
        round_half_away(v[0] * scale_milli / 1000.0 + int(offset[0])),
        round_half_away(v[1] * scale_milli / 1000.0 + int(offset[1])),
        round_half_away(v[2] * scale_milli / 1000.0 + int(offset[2])),
    ]


def pack_obj_indexed(mesh, base_dir):
    vertices, faces = obj_mesh_data(mesh, base_dir)
    return pack_vertices_xyz([obj_transform_vertex(v, mesh) for v in vertices]), pack_faces(faces, len(vertices))


def pack_obj_triangles(mesh, base_dir):
    vertices, faces = obj_mesh_data(mesh, base_dir)
    points = [obj_transform_vertex(v, mesh) for v in vertices]
    return pack_triangles_xyz([[points[a], points[b], points[c]] for a, b, c in faces])


def has_gltf_mesh(mesh):
    return mesh.get("gltf_source") is not None or mesh.get("gltf_json") is not None


def safe_relative_path(rel, context):
    rel_path = pathlib.PurePosixPath(str(rel))
    if rel_path.is_absolute() or ".." in rel_path.parts:
        raise SystemExit(f"scene {context} must be a safe relative path")
    return rel_path


def read_relative_bytes(base_dir, rel, context):
    if base_dir is None:
        raise SystemExit(f"scene {context} requires a source directory")
    rel_path = safe_relative_path(rel, context)
    path = base_dir / pathlib.Path(*rel_path.parts)
    if not path.is_file():
        raise SystemExit(f"scene {context} not found: {rel}")
    return path.read_bytes()


def gltf_source_json(mesh, base_dir):
    if mesh.get("gltf_json") is not None:
        doc = mesh["gltf_json"]
        if isinstance(doc, str):
            return json.loads(doc)
        if isinstance(doc, dict):
            return doc
        raise SystemExit("scene gltf_json must be a JSON object or string")
    rel = mesh.get("gltf_source")
    if rel is None:
        raise SystemExit("scene glTF mesh must include gltf_source or gltf_json")
    data = read_relative_bytes(base_dir, rel, "gltf_source")
    if data.startswith(b"glTF"):
        return gltf_parse_glb(data)
    try:
        return json.loads(data.decode("utf-8"))
    except UnicodeDecodeError as exc:
        raise SystemExit("scene glTF source must be UTF-8 JSON") from exc


def gltf_parse_glb(data):
    if len(data) < 20:
        raise SystemExit("scene GLB payload truncated")
    magic, version, total_len = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise SystemExit("scene GLB header must be Binary glTF version 2")
    if total_len != len(data):
        raise SystemExit("scene GLB length mismatch")
    pos = 12
    json_chunk = None
    bin_chunk = None
    chunk_index = 0
    while pos < len(data):
        if pos + 8 > len(data):
            raise SystemExit("scene GLB chunk header truncated")
        chunk_len, chunk_type = struct.unpack_from("<II", data, pos)
        pos += 8
        if pos + chunk_len > len(data):
            raise SystemExit("scene GLB chunk payload truncated")
        chunk = data[pos:pos + chunk_len]
        pos += chunk_len
        if chunk_type == 0x4E4F534A:
            if chunk_index != 0 or json_chunk is not None:
                raise SystemExit("scene GLB JSON chunk must be first and unique")
            json_chunk = chunk.rstrip(b" \t\r\n")
        elif chunk_type == 0x004E4942:
            if json_chunk is None or bin_chunk is not None:
                raise SystemExit("scene GLB BIN chunk must follow JSON and be unique")
            bin_chunk = chunk
        chunk_index += 1
    if json_chunk is None:
        raise SystemExit("scene GLB missing JSON chunk")
    try:
        doc = json.loads(json_chunk.decode("utf-8"))
    except UnicodeDecodeError as exc:
        raise SystemExit("scene GLB JSON chunk must be UTF-8") from exc
    if bin_chunk is not None:
        doc["__oren_glb_bin"] = bin_chunk
    return doc


def gltf_decode_data_uri(uri):
    prefix = "data:"
    if not isinstance(uri, str) or not uri.startswith(prefix):
        return None
    meta, sep, payload = uri[len(prefix):].partition(",")
    if sep == "" or "base64" not in meta.split(";"):
        raise SystemExit("scene glTF data URI buffers must be base64")
    return base64.b64decode(payload, validate=True)


def gltf_buffer_bytes(doc, buffer_index, base_dir):
    buffers = doc.get("buffers", [])
    if buffer_index < 0 or buffer_index >= len(buffers):
        raise SystemExit("scene glTF buffer index out of bounds")
    buf = buffers[buffer_index]
    uri = buf.get("uri")
    if uri is None:
        if buffer_index != 0 or "__oren_glb_bin" not in doc:
            raise SystemExit("scene glTF JSON buffers must use uri data, relative paths, or GLB BIN chunk")
        data = doc["__oren_glb_bin"]
    else:
        data = gltf_decode_data_uri(uri)
        if data is None:
            data = read_relative_bytes(base_dir, uri, "gltf buffer uri")
    declared = buf.get("byteLength")
    if declared is not None and len(data) < int(declared):
        raise SystemExit("scene glTF buffer shorter than declared byteLength")
    return data


GLTF_COMPONENTS = {
    5120: ("b", 1, True),
    5121: ("B", 1, False),
    5122: ("h", 2, True),
    5123: ("H", 2, False),
    5125: ("I", 4, False),
    5126: ("f", 4, True),
}

GLTF_TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
}


def gltf_accessor_values(doc, accessor_index, base_dir):
    accessors = doc.get("accessors", [])
    if accessor_index < 0 or accessor_index >= len(accessors):
        raise SystemExit("scene glTF accessor index out of bounds")
    accessor = accessors[accessor_index]
    if accessor.get("sparse") is not None:
        raise SystemExit("scene glTF sparse accessors are not supported")
    component_type = int(accessor.get("componentType"))
    if component_type not in GLTF_COMPONENTS:
        raise SystemExit("scene glTF accessor componentType unsupported")
    accessor_type = accessor.get("type")
    if accessor_type not in GLTF_TYPE_COMPONENTS:
        raise SystemExit("scene glTF accessor type unsupported")
    component_fmt, component_size, _ = GLTF_COMPONENTS[component_type]
    component_count = GLTF_TYPE_COMPONENTS[accessor_type]
    count = int(accessor.get("count", 0))
    if count < 0:
        raise SystemExit("scene glTF accessor count out of bounds")
    view_index = accessor.get("bufferView")
    if view_index is None:
        return [[0] * component_count for _ in range(count)]
    views = doc.get("bufferViews", [])
    view_index = int(view_index)
    if view_index < 0 or view_index >= len(views):
        raise SystemExit("scene glTF bufferView index out of bounds")
    view = views[view_index]
    data = gltf_buffer_bytes(doc, int(view["buffer"]), base_dir)
    view_offset = int(view.get("byteOffset", 0))
    view_len = int(view.get("byteLength", len(data) - view_offset))
    accessor_offset = int(accessor.get("byteOffset", 0))
    stride = int(view.get("byteStride", component_size * component_count))
    if stride < component_size * component_count:
        raise SystemExit("scene glTF accessor byteStride too small")
    start = view_offset + accessor_offset
    view_end = view_offset + view_len
    fmt = "<" + component_fmt * component_count
    item_size = struct.calcsize(fmt)
    values = []
    for i in range(count):
        pos = start + i * stride
        if pos < view_offset or pos + item_size > view_end or pos + item_size > len(data):
            raise SystemExit("scene glTF accessor payload truncated")
        value = struct.unpack_from(fmt, data, pos)
        values.append(list(value))
    return values


def gltf_transform_vertex(v, mesh):
    scale_milli = int(mesh.get("gltf_scale_milli", 1000))
    if scale_milli <= 0:
        raise SystemExit("scene glTF gltf_scale_milli must be positive")
    offset = mesh.get("gltf_offset_xyz", [0, 0, 0])
    if not isinstance(offset, list) or len(offset) != 3:
        raise SystemExit("scene glTF gltf_offset_xyz must be [x,y,z]")
    return [
        round_half_away(float(v[0]) * scale_milli / 1000.0 + int(offset[0])),
        round_half_away(float(v[1]) * scale_milli / 1000.0 + int(offset[1])),
        round_half_away(float(v[2]) * scale_milli / 1000.0 + int(offset[2])),
    ]


def gltf_indices_for_primitive(doc, primitive, vertex_count, base_dir):
    if primitive.get("indices") is None:
        return list(range(vertex_count))
    raw = gltf_accessor_values(doc, int(primitive["indices"]), base_dir)
    indices = [int(item[0]) for item in raw]
    for idx in indices:
        if idx < 0 or idx >= vertex_count:
            raise SystemExit("scene glTF primitive index out of bounds")
    return indices


def gltf_material_color(doc, primitive):
    material_index = primitive.get("material")
    if material_index is None:
        return (255, 255, 255, 255)
    materials = doc.get("materials", [])
    material_index = int(material_index)
    if material_index < 0 or material_index >= len(materials):
        raise SystemExit("scene glTF material index out of bounds")
    color = materials[material_index].get("pbrMetallicRoughness", {}).get("baseColorFactor")
    if color is None:
        return (255, 255, 255, 255)
    if not isinstance(color, list) or len(color) not in (3, 4):
        raise SystemExit("scene glTF baseColorFactor must be [r,g,b] or [r,g,b,a]")
    rgba = [round_half_away(max(0.0, min(1.0, float(v))) * 255.0) for v in color]
    if len(rgba) == 3:
        rgba.append(255)
    return tuple(rgba)


def gltf_accessor_color(doc, accessor_index, base_dir):
    accessors = doc.get("accessors", [])
    accessor = accessors[int(accessor_index)]
    values = gltf_accessor_values(doc, int(accessor_index), base_dir)
    component_type = int(accessor.get("componentType"))
    normalized = bool(accessor.get("normalized", False))
    out = []
    for value in values:
        channels = []
        for channel in value[:4]:
            if component_type == 5126:
                channels.append(round_half_away(max(0.0, min(1.0, float(channel))) * 255.0))
            elif normalized:
                if component_type == 5121:
                    channels.append(round_half_away(max(0, min(255, int(channel)))))
                elif component_type == 5123:
                    channels.append(round_half_away(max(0, min(65535, int(channel))) * 255.0 / 65535.0))
                else:
                    raise SystemExit("scene glTF normalized COLOR_0 componentType unsupported")
            else:
                channels.append(max(0, min(255, int(channel))))
        while len(channels) < 4:
            channels.append(255)
        out.append(tuple(channels[:4]))
    return out


def gltf_mesh_data(mesh, base_dir):
    doc = gltf_source_json(mesh, base_dir)
    asset = doc.get("asset", {})
    if str(asset.get("version", "")).split(".", 1)[0] != "2":
        raise SystemExit("scene glTF asset.version must be 2.x")
    mesh_index = int(mesh.get("gltf_mesh", 0))
    meshes = doc.get("meshes", [])
    if mesh_index < 0 or mesh_index >= len(meshes):
        raise SystemExit("scene glTF mesh index out of bounds")
    vertices = []
    faces = []
    vertex_colors = []
    face_colors = []
    for primitive in meshes[mesh_index].get("primitives", []):
        mode = int(primitive.get("mode", 4))
        if mode != 4:
            raise SystemExit("scene glTF only TRIANGLES primitives are supported")
        attributes = primitive.get("attributes", {})
        if attributes.get("POSITION") is None:
            raise SystemExit("scene glTF primitive missing POSITION accessor")
        positions = gltf_accessor_values(doc, int(attributes["POSITION"]), base_dir)
        base_vertex = len(vertices)
        vertices.extend(positions)
        colors = None
        if attributes.get("COLOR_0") is not None:
            colors = gltf_accessor_color(doc, int(attributes["COLOR_0"]), base_dir)
            if len(colors) != len(positions):
                raise SystemExit("scene glTF COLOR_0 count must match POSITION count")
        vertex_colors.extend(colors if colors is not None else [None] * len(positions))
        local_indices = gltf_indices_for_primitive(doc, primitive, len(positions), base_dir)
        if len(local_indices) % 3 != 0:
            raise SystemExit("scene glTF TRIANGLES index count must be a multiple of 3")
        material_color = gltf_material_color(doc, primitive)
        for i in range(0, len(local_indices), 3):
            face = [base_vertex + local_indices[i], base_vertex + local_indices[i + 1], base_vertex + local_indices[i + 2]]
            faces.append(face)
            face_colors.append(material_color if colors is None else None)
    if not vertices:
        raise SystemExit("scene glTF mesh has no vertices")
    if not faces:
        raise SystemExit("scene glTF mesh has no triangle faces")
    return vertices, faces, vertex_colors, face_colors


def pack_gltf_indexed(mesh, base_dir):
    vertices, faces, _, _ = gltf_mesh_data(mesh, base_dir)
    return pack_vertices_xyz([gltf_transform_vertex(v, mesh) for v in vertices]), pack_faces(faces, len(vertices))


def pack_gltf_triangles(mesh, base_dir):
    vertices, faces, _, _ = gltf_mesh_data(mesh, base_dir)
    points = [gltf_transform_vertex(v, mesh) for v in vertices]
    return pack_triangles_xyz([[points[a], points[b], points[c]] for a, b, c in faces])


def pack_gltf_triangles_rgba(mesh, base_dir):
    vertices, faces, vertex_colors, face_colors = gltf_mesh_data(mesh, base_dir)
    points = [gltf_transform_vertex(v, mesh) for v in vertices]
    triangles = []
    for i, face in enumerate(faces):
        color = face_colors[i]
        if color is None:
            color = ply_average_color([vertex_colors[idx] for idx in face])
        if color is None:
            raise SystemExit("scene glTF triangles_rgba mesh requires COLOR_0 or material baseColorFactor")
        triangles.append({
            "vertices": [points[face[0]], points[face[1]], points[face[2]]],
            "color": color_hex_from_rgba(color[0], color[1], color[2], color[3]),
        })
    return pack_triangles_xyz_rgba(triangles)


def has_ply_mesh(mesh):
    return mesh.get("ply_source") is not None or mesh.get("ply_text") is not None


def ply_source_bytes(mesh, base_dir):
    if mesh.get("ply_text") is not None:
        text = mesh["ply_text"]
        if not isinstance(text, str):
            raise SystemExit("scene ply_text must be a string")
        return text.encode("utf-8")
    rel = mesh.get("ply_source")
    if rel is None:
        raise SystemExit("scene PLY mesh must include ply_source or ply_text")
    if base_dir is None:
        raise SystemExit("scene ply_source requires a source directory")
    rel_path = pathlib.PurePosixPath(str(rel))
    if rel_path.is_absolute() or ".." in rel_path.parts:
        raise SystemExit("scene ply_source must be a safe relative path")
    path = base_dir / pathlib.Path(*rel_path.parts)
    if not path.is_file():
        raise SystemExit(f"scene ply_source not found: {rel}")
    return path.read_bytes()


def ply_transform_vertex(v, mesh):
    scale_milli = int(mesh.get("ply_scale_milli", 1000))
    if scale_milli <= 0:
        raise SystemExit("scene PLY ply_scale_milli must be positive")
    offset = mesh.get("ply_offset_xyz", [0, 0, 0])
    if not isinstance(offset, list) or len(offset) != 3:
        raise SystemExit("scene PLY ply_offset_xyz must be [x,y,z]")
    return [
        round_half_away(v[0] * scale_milli / 1000.0 + int(offset[0])),
        round_half_away(v[1] * scale_milli / 1000.0 + int(offset[1])),
        round_half_away(v[2] * scale_milli / 1000.0 + int(offset[2])),
    ]


PLY_SCALAR = {
    "char": ("b", int), "int8": ("b", int),
    "uchar": ("B", int), "uint8": ("B", int),
    "short": ("h", int), "int16": ("h", int),
    "ushort": ("H", int), "uint16": ("H", int),
    "int": ("i", int), "int32": ("i", int),
    "uint": ("I", int), "uint32": ("I", int),
    "float": ("f", float), "float32": ("f", float),
    "double": ("d", float), "float64": ("d", float),
}


def ply_parse_header(data):
    lines = []
    pos = 0
    while True:
        nl = data.find(b"\n", pos)
        if nl < 0:
            raise SystemExit("scene PLY missing end_header")
        raw = data[pos:nl]
        pos = nl + 1
        if raw.endswith(b"\r"):
            raw = raw[:-1]
        try:
            line = raw.decode("ascii")
        except UnicodeDecodeError as exc:
            raise SystemExit("scene PLY header must be ASCII") from exc
        lines.append(line)
        if line == "end_header":
            break
    if not lines or lines[0] != "ply":
        raise SystemExit("scene PLY source must start with ply")

    fmt = None
    elements = []
    current = None
    for line_no, line in enumerate(lines[1:], 2):
        if line == "" or line.startswith("comment "):
            continue
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "format":
            if len(parts) != 3 or parts[2] != "1.0":
                raise SystemExit(f"unsupported scene PLY format line {line_no}")
            fmt = parts[1]
            if fmt not in ("ascii", "binary_little_endian", "binary_big_endian"):
                raise SystemExit(f"unsupported scene PLY format: {fmt}")
        elif parts[0] == "element":
            if len(parts) != 3:
                raise SystemExit(f"invalid scene PLY element line {line_no}")
            current = {"name": parts[1], "count": int(parts[2]), "properties": []}
            if current["count"] < 0:
                raise SystemExit(f"invalid scene PLY element count on line {line_no}")
            elements.append(current)
        elif parts[0] == "property":
            if current is None:
                raise SystemExit(f"scene PLY property before element on line {line_no}")
            if len(parts) == 3:
                if parts[1] not in PLY_SCALAR:
                    raise SystemExit(f"unsupported scene PLY property type on line {line_no}: {parts[1]}")
                current["properties"].append(("scalar", parts[1], parts[2]))
            elif len(parts) == 5 and parts[1] == "list":
                if parts[2] not in PLY_SCALAR or parts[3] not in PLY_SCALAR:
                    raise SystemExit(f"unsupported scene PLY list type on line {line_no}")
                current["properties"].append(("list", parts[2], parts[3], parts[4]))
            else:
                raise SystemExit(f"invalid scene PLY property line {line_no}")
        elif parts[0] in ("obj_info", "end_header"):
            continue
        else:
            raise SystemExit(f"unsupported scene PLY header line {line_no}: {parts[0]}")
    if fmt is None:
        raise SystemExit("scene PLY missing format")
    return fmt, elements, pos


def ply_ascii_value(token, typ):
    conv = PLY_SCALAR[typ][1]
    return conv(token)


def ply_record_from_ascii_tokens(props, tokens, line_no):
    pos = 0
    scalars = {}
    lists = {}
    for prop in props:
        if prop[0] == "scalar":
            if pos >= len(tokens):
                raise SystemExit(f"scene PLY record too short on line {line_no}")
            scalars[prop[2]] = ply_ascii_value(tokens[pos], prop[1])
            pos += 1
        else:
            if pos >= len(tokens):
                raise SystemExit(f"scene PLY list missing count on line {line_no}")
            n = int(ply_ascii_value(tokens[pos], prop[1]))
            pos += 1
            if n < 0 or pos + n > len(tokens):
                raise SystemExit(f"scene PLY list count out of bounds on line {line_no}")
            vals = [ply_ascii_value(tokens[pos + i], prop[2]) for i in range(n)]
            pos += n
            lists[prop[3]] = vals
    return scalars, lists


def ply_read_binary_scalar(data, pos, typ, endian):
    scalar_fmt = endian + PLY_SCALAR[typ][0]
    size = struct.calcsize(scalar_fmt)
    if pos + size > len(data):
        raise SystemExit("scene binary PLY payload truncated")
    return struct.unpack_from(scalar_fmt, data, pos)[0], pos + size


def ply_record_from_binary(data, pos, props, endian):
    scalars = {}
    lists = {}
    for prop in props:
        if prop[0] == "scalar":
            value, pos = ply_read_binary_scalar(data, pos, prop[1], endian)
            scalars[prop[2]] = value
        else:
            n, pos = ply_read_binary_scalar(data, pos, prop[1], endian)
            if n < 0:
                raise SystemExit("scene binary PLY list count negative")
            vals = []
            for _ in range(int(n)):
                value, pos = ply_read_binary_scalar(data, pos, prop[2], endian)
                vals.append(value)
            lists[prop[3]] = vals
    return scalars, lists, pos


def ply_color_from_scalars(scalars):
    r = scalars.get("red", scalars.get("r"))
    g = scalars.get("green", scalars.get("g"))
    b = scalars.get("blue", scalars.get("b"))
    if r is None or g is None or b is None:
        return None
    a = scalars.get("alpha", scalars.get("a", 255))
    color = (int(r), int(g), int(b), int(a))
    for channel in color:
        if channel < 0 or channel > 255:
            raise SystemExit("scene PLY color channels must be 0..255")
    return color


def ply_color_hex(color):
    return color_hex_from_rgba(color[0], color[1], color[2], color[3])


def ply_average_color(colors):
    if not colors or any(color is None for color in colors):
        return None
    n = len(colors)
    return (
        sum(color[0] for color in colors) // n,
        sum(color[1] for color in colors) // n,
        sum(color[2] for color in colors) // n,
        sum(color[3] for color in colors) // n,
    )


def ply_add_vertex(vertices, vertex_colors, scalars):
    if "x" not in scalars or "y" not in scalars or "z" not in scalars:
        raise SystemExit("scene PLY vertex element must include x/y/z properties")
    vertices.append((float(scalars["x"]), float(scalars["y"]), float(scalars["z"])))
    vertex_colors.append(ply_color_from_scalars(scalars))


def ply_add_faces(faces, face_colors, lists, vertex_count, scalars):
    indices = lists.get("vertex_indices", lists.get("vertex_index"))
    if indices is None and lists:
        indices = next(iter(lists.values()))
    if indices is None:
        raise SystemExit("scene PLY face element must include a vertex index list")
    if len(indices) < 3:
        return
    face = [int(v) for v in indices]
    for idx in face:
        if idx < 0 or idx >= vertex_count:
            raise SystemExit("scene PLY face index out of bounds")
    face_color = ply_color_from_scalars(scalars)
    for i in range(1, len(face) - 1):
        faces.append([face[0], face[i], face[i + 1]])
        face_colors.append(face_color)


def ply_mesh_data(mesh, base_dir):
    data = ply_source_bytes(mesh, base_dir)
    fmt, elements, body_start = ply_parse_header(data)
    vertices = []
    vertex_colors = []
    faces = []
    face_colors = []
    if fmt == "ascii":
        try:
            body_lines = data[body_start:].decode("utf-8").splitlines()
        except UnicodeDecodeError as exc:
            raise SystemExit("scene ASCII PLY body must be UTF-8") from exc
        line_idx = 0
        for element in elements:
            for _ in range(element["count"]):
                if line_idx >= len(body_lines):
                    raise SystemExit("scene ASCII PLY body truncated")
                raw = body_lines[line_idx]
                line_idx += 1
                while raw.strip() == "":
                    if line_idx >= len(body_lines):
                        raise SystemExit("scene ASCII PLY body truncated")
                    raw = body_lines[line_idx]
                    line_idx += 1
                scalars, lists = ply_record_from_ascii_tokens(element["properties"], raw.split(), line_idx)
                if element["name"] == "vertex":
                    ply_add_vertex(vertices, vertex_colors, scalars)
                elif element["name"] == "face":
                    ply_add_faces(faces, face_colors, lists, len(vertices), scalars)
    else:
        endian = "<" if fmt == "binary_little_endian" else ">"
        pos = body_start
        for element in elements:
            for _ in range(element["count"]):
                scalars, lists, pos = ply_record_from_binary(data, pos, element["properties"], endian)
                if element["name"] == "vertex":
                    ply_add_vertex(vertices, vertex_colors, scalars)
                elif element["name"] == "face":
                    ply_add_faces(faces, face_colors, lists, len(vertices), scalars)
    if not vertices:
        raise SystemExit("scene PLY mesh has no vertices")
    if not faces:
        raise SystemExit("scene PLY mesh has no faces")
    return vertices, faces, vertex_colors, face_colors


def pack_ply_indexed(mesh, base_dir):
    vertices, faces, _, _ = ply_mesh_data(mesh, base_dir)
    return pack_vertices_xyz([ply_transform_vertex(v, mesh) for v in vertices]), pack_faces(faces, len(vertices))


def pack_ply_triangles(mesh, base_dir):
    vertices, faces, _, _ = ply_mesh_data(mesh, base_dir)
    points = [ply_transform_vertex(v, mesh) for v in vertices]
    return pack_triangles_xyz([[points[a], points[b], points[c]] for a, b, c in faces])


def pack_ply_triangles_rgba(mesh, base_dir):
    vertices, faces, vertex_colors, face_colors = ply_mesh_data(mesh, base_dir)
    points = [ply_transform_vertex(v, mesh) for v in vertices]
    triangles = []
    for i, face in enumerate(faces):
        color = face_colors[i]
        if color is None:
            color = ply_average_color([vertex_colors[idx] for idx in face])
        if color is None:
            raise SystemExit("scene PLY triangles_rgba mesh requires face or vertex colors")
        triangles.append({
            "vertices": [points[face[0]], points[face[1]], points[face[2]]],
            "color": ply_color_hex(color),
        })
    return pack_triangles_xyz_rgba(triangles)


def has_stl_mesh(mesh):
    return mesh.get("stl_source") is not None or mesh.get("stl_text") is not None


def stl_source_bytes(mesh, base_dir):
    if mesh.get("stl_text") is not None:
        text = mesh["stl_text"]
        if not isinstance(text, str):
            raise SystemExit("scene stl_text must be a string")
        return text.encode("utf-8")
    rel = mesh.get("stl_source")
    if rel is None:
        raise SystemExit("scene STL mesh must include stl_source or stl_text")
    if base_dir is None:
        raise SystemExit("scene stl_source requires a source directory")
    rel_path = pathlib.PurePosixPath(str(rel))
    if rel_path.is_absolute() or ".." in rel_path.parts:
        raise SystemExit("scene stl_source must be a safe relative path")
    path = base_dir / pathlib.Path(*rel_path.parts)
    if not path.is_file():
        raise SystemExit(f"scene stl_source not found: {rel}")
    return path.read_bytes()


def stl_transform_vertex(v, mesh):
    scale_milli = int(mesh.get("stl_scale_milli", 1000))
    if scale_milli <= 0:
        raise SystemExit("scene STL stl_scale_milli must be positive")
    offset = mesh.get("stl_offset_xyz", [0, 0, 0])
    if not isinstance(offset, list) or len(offset) != 3:
        raise SystemExit("scene STL stl_offset_xyz must be [x,y,z]")
    return [
        round_half_away(v[0] * scale_milli / 1000.0 + int(offset[0])),
        round_half_away(v[1] * scale_milli / 1000.0 + int(offset[1])),
        round_half_away(v[2] * scale_milli / 1000.0 + int(offset[2])),
    ]


def is_binary_stl(data):
    if len(data) < 84:
        return False
    tri_count = struct.unpack_from("<I", data, 80)[0]
    return 84 + tri_count * 50 == len(data)


def binary_stl_triangles(mesh, data):
    tri_count = struct.unpack_from("<I", data, 80)[0]
    triangles = []
    offset = 84
    for _ in range(tri_count):
        values = struct.unpack_from("<ffffffffffffH", data, offset)
        triangles.append([
            stl_transform_vertex(values[3:6], mesh),
            stl_transform_vertex(values[6:9], mesh),
            stl_transform_vertex(values[9:12], mesh),
        ])
        offset += 50
    if not triangles:
        raise SystemExit("scene binary STL mesh has no triangles")
    return triangles


def ascii_stl_triangles(mesh, data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SystemExit("scene STL source is neither binary STL nor UTF-8 ASCII STL") from exc
    vertices = []
    triangles = []
    saw_solid = False
    for line_no, raw in enumerate(text.splitlines(), 1):
        parts = raw.strip().split()
        if not parts:
            continue
        tag = parts[0].lower()
        if tag == "solid":
            saw_solid = True
        elif tag == "vertex":
            if len(parts) != 4:
                raise SystemExit(f"scene STL vertex must have x y z on line {line_no}")
            vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
            if len(vertices) == 3:
                triangles.append([stl_transform_vertex(v, mesh) for v in vertices])
                vertices = []
        elif tag in ("facet", "outer", "endloop", "endfacet", "endsolid"):
            continue
        else:
            raise SystemExit(f"unsupported scene STL line {line_no}: {parts[0]}")
    if not saw_solid:
        raise SystemExit("scene ASCII STL mesh must start with solid")
    if vertices:
        raise SystemExit("scene STL facet has incomplete vertex list")
    if not triangles:
        raise SystemExit("scene STL mesh has no triangles")
    return triangles


def stl_triangles(mesh, base_dir):
    data = stl_source_bytes(mesh, base_dir)
    if is_binary_stl(data):
        return binary_stl_triangles(mesh, data)
    return ascii_stl_triangles(mesh, data)


def pack_stl_triangles(mesh, base_dir):
    return pack_triangles_xyz(stl_triangles(mesh, base_dir))


def pack_triangles_xyz(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, list) or len(tri) != 3:
            raise SystemExit("scene triangles_xyz entries must contain 3 vertices")
        out += pack_vertices_xyz(tri)
    return bytes(out)


def pack_quads_xyz(quads):
    triangles = []
    for quad in quads:
        if not isinstance(quad, list) or len(quad) != 4:
            raise SystemExit("scene quads_xyz entries must contain 4 vertices")
        triangles.append([quad[0], quad[1], quad[2]])
        triangles.append([quad[0], quad[2], quad[3]])
    return pack_triangles_xyz(triangles)


def box_min_max(box):
    if not isinstance(box, dict):
        raise SystemExit("scene boxes_xyz entries must be objects")
    lo = box.get("min", box.get("min_xyz"))
    hi = box.get("max", box.get("max_xyz"))
    if not isinstance(lo, list) or not isinstance(hi, list) or len(lo) != 3 or len(hi) != 3:
        raise SystemExit("scene boxes_xyz entries must include min/max [x,y,z]")
    x0, y0, z0 = (int(lo[0]), int(lo[1]), int(lo[2]))
    x1, y1, z1 = (int(hi[0]), int(hi[1]), int(hi[2]))
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        raise SystemExit("scene boxes_xyz max must be greater than min")
    return x0, y0, z0, x1, y1, z1


def pack_boxes_xyz(boxes):
    triangles = []
    for box in boxes:
        x0, y0, z0, x1, y1, z1 = box_min_max(box)
        triangles.extend(
            [
                [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0]],
                [[x0, y0, z0], [x1, y1, z0], [x0, y1, z0]],
                [[x0, y0, z1], [x1, y1, z1], [x1, y0, z1]],
                [[x0, y0, z1], [x0, y1, z1], [x1, y1, z1]],
                [[x0, y0, z0], [x0, y1, z0], [x0, y1, z1]],
                [[x0, y0, z0], [x0, y1, z1], [x0, y0, z1]],
                [[x1, y0, z0], [x1, y0, z1], [x1, y1, z1]],
                [[x1, y0, z0], [x1, y1, z1], [x1, y1, z0]],
                [[x0, y1, z0], [x1, y1, z0], [x1, y1, z1]],
                [[x0, y1, z0], [x1, y1, z1], [x0, y1, z1]],
                [[x0, y0, z0], [x0, y0, z1], [x1, y0, z1]],
                [[x0, y0, z0], [x1, y0, z1], [x1, y0, z0]],
            ]
        )
    return pack_triangles_xyz(triangles)


def prism_points(prism):
    if not isinstance(prism, dict):
        raise SystemExit("scene prisms_xy entries must be objects")
    points = prism.get("points", prism.get("points_xy"))
    if not isinstance(points, list) or len(points) < 3:
        raise SystemExit("scene prisms_xy points must contain at least 3 [x,y] entries")
    for point in points:
        if not isinstance(point, list) or len(point) != 2:
            raise SystemExit("scene prisms_xy points must be [x,y]")
        int(point[0])
        int(point[1])
    return points


def prism_z(prism, primary, fallback):
    if primary in prism:
        return int(prism[primary])
    if fallback in prism:
        return int(prism[fallback])
    raise SystemExit(f"scene prisms_xy entries must include {primary}")


def pack_prisms_xy(prisms):
    triangles = []
    for prism in prisms:
        points = prism_points(prism)
        z0 = prism_z(prism, "z_min", "min_z")
        z1 = prism_z(prism, "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene prisms_xy z_max must be greater than z_min")
        p0 = points[0]
        for i in range(1, len(points) - 1):
            p1 = points[i]
            p2 = points[i + 1]
            triangles.append(
                [[p0[0], p0[1], z0], [p2[0], p2[1], z0], [p1[0], p1[1], z0]]
            )
            triangles.append(
                [[p0[0], p0[1], z1], [p1[0], p1[1], z1], [p2[0], p2[1], z1]]
            )
        for i, a in enumerate(points):
            b = points[(i + 1) % len(points)]
            triangles.append([[a[0], a[1], z0], [b[0], b[1], z0], [b[0], b[1], z1]])
            triangles.append([[a[0], a[1], z0], [b[0], b[1], z1], [a[0], a[1], z1]])
    return pack_triangles_xyz(triangles)


def cylinder_center(cyl):
    center = cyl.get("center", cyl.get("center_xy"))
    if not isinstance(center, list) or len(center) != 2:
        raise SystemExit("scene cylinders_z center must be [x,y]")
    return int(center[0]), int(center[1])


def cylinder_radius(cyl):
    radius = cyl.get("radius", cyl.get("radius_xy"))
    if radius is None:
        raise SystemExit("scene cylinders_z entries must include radius")
    radius = int(radius)
    if radius <= 0:
        raise SystemExit("scene cylinders_z radius must be positive")
    return radius


def cylinder_z(cyl, primary, fallback):
    if primary in cyl:
        return int(cyl[primary])
    if fallback in cyl:
        return int(cyl[fallback])
    raise SystemExit(f"scene cylinders_z entries must include {primary}")


def cylinder_segments(cyl):
    segments = int(cyl.get("segments", 16))
    if segments < 3 or segments > 96:
        raise SystemExit("scene cylinders_z segments must be 3..96")
    return segments


def round_half_away(x):
    if x >= 0:
        return math.floor(x + 0.5)
    return math.ceil(x - 0.5)


def cylinder_point(cx, cy, radius, segments, idx, z):
    angle = math.tau * idx / segments
    x = round_half_away(cx + radius * math.cos(angle))
    y = round_half_away(cy + radius * math.sin(angle))
    return [x, y, z]


def pack_cylinders_z(cylinders):
    triangles = []
    for cyl in cylinders:
        if not isinstance(cyl, dict):
            raise SystemExit("scene cylinders_z entries must be objects")
        cx, cy = cylinder_center(cyl)
        radius = cylinder_radius(cyl)
        z0 = cylinder_z(cyl, "z_min", "min_z")
        z1 = cylinder_z(cyl, "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene cylinders_z z_max must be greater than z_min")
        segments = cylinder_segments(cyl)
        for i in range(segments):
            nxt = 0 if i + 1 == segments else i + 1
            a0 = cylinder_point(cx, cy, radius, segments, i, z0)
            b0 = cylinder_point(cx, cy, radius, segments, nxt, z0)
            a1 = cylinder_point(cx, cy, radius, segments, i, z1)
            b1 = cylinder_point(cx, cy, radius, segments, nxt, z1)
            triangles.append([[cx, cy, z0], b0, a0])
            triangles.append([[cx, cy, z1], a1, b1])
            triangles.append([a0, b0, b1])
            triangles.append([a0, b1, a1])
    return pack_triangles_xyz(triangles)


def pack_cones_z(cones):
    triangles = []
    for cone in cones:
        if not isinstance(cone, dict):
            raise SystemExit("scene cones_z entries must be objects")
        cx, cy = cylinder_center(cone)
        radius = cylinder_radius(cone)
        z0 = cylinder_z(cone, "z_min", "min_z")
        z1 = cylinder_z(cone, "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene cones_z z_max must be greater than z_min")
        segments = cylinder_segments(cone)
        for i in range(segments):
            nxt = 0 if i + 1 == segments else i + 1
            a0 = cylinder_point(cx, cy, radius, segments, i, z0)
            b0 = cylinder_point(cx, cy, radius, segments, nxt, z0)
            triangles.append([[cx, cy, z0], b0, a0])
            triangles.append([a0, b0, [cx, cy, z1]])
    return pack_triangles_xyz(triangles)


def sphere_center(sphere, label="spheres_xyz"):
    center = sphere.get("center", sphere.get("center_xyz"))
    if not isinstance(center, list) or len(center) != 3:
        raise SystemExit(f"scene {label} center must be [x,y,z]")
    return int(center[0]), int(center[1]), int(center[2])


def sphere_radius(sphere):
    radius = sphere.get("radius")
    if radius is None:
        raise SystemExit("scene spheres_xyz entries must include radius")
    radius = int(radius)
    if radius <= 0:
        raise SystemExit("scene spheres_xyz radius must be positive")
    return radius


def ellipsoid_radii(ellipsoid):
    radii = ellipsoid.get("radii", ellipsoid.get("radii_xyz"))
    if radii is not None:
        if not isinstance(radii, list) or len(radii) != 3:
            raise SystemExit("scene ellipsoids_xyz radii must be [rx,ry,rz]")
        rx, ry, rz = int(radii[0]), int(radii[1]), int(radii[2])
    else:
        if not all(k in ellipsoid for k in ("radius_x", "radius_y", "radius_z")):
            raise SystemExit("scene ellipsoids_xyz entries must include radii or radius_x/y/z")
        rx = int(ellipsoid["radius_x"])
        ry = int(ellipsoid["radius_y"])
        rz = int(ellipsoid["radius_z"])
    if rx <= 0 or ry <= 0 or rz <= 0:
        raise SystemExit("scene ellipsoids_xyz radii must be positive")
    return rx, ry, rz


def sphere_segments(sphere):
    segments = int(sphere.get("segments", 16))
    if segments < 4 or segments > 96:
        raise SystemExit("scene spheres_xyz segments must be 4..96")
    return segments


def sphere_rings(sphere):
    rings = int(sphere.get("rings", 8))
    if rings < 2 or rings > 48:
        raise SystemExit("scene spheres_xyz rings must be 2..48")
    return rings


def sphere_point(cx, cy, cz, radius, segments, rings, seg, ring):
    theta = math.pi * ring / rings
    phi = math.tau * seg / segments
    x = round_half_away(cx + radius * math.sin(theta) * math.cos(phi))
    y = round_half_away(cy + radius * math.sin(theta) * math.sin(phi))
    z = round_half_away(cz + radius * math.cos(theta))
    return [x, y, z]


def ellipsoid_point(cx, cy, cz, rx, ry, rz, segments, rings, seg, ring):
    theta = math.pi * ring / rings
    phi = math.tau * seg / segments
    x = round_half_away(cx + rx * math.sin(theta) * math.cos(phi))
    y = round_half_away(cy + ry * math.sin(theta) * math.sin(phi))
    z = round_half_away(cz + rz * math.cos(theta))
    return [x, y, z]


def pack_spheres_xyz(spheres):
    triangles = []
    for sphere in spheres:
        if not isinstance(sphere, dict):
            raise SystemExit("scene spheres_xyz entries must be objects")
        cx, cy, cz = sphere_center(sphere)
        radius = sphere_radius(sphere)
        segments = sphere_segments(sphere)
        rings = sphere_rings(sphere)
        for ring in range(rings):
            next_ring = ring + 1
            for seg in range(segments):
                next_seg = 0 if seg + 1 == segments else seg + 1
                a = sphere_point(cx, cy, cz, radius, segments, rings, seg, ring)
                b = sphere_point(cx, cy, cz, radius, segments, rings, next_seg, next_ring)
                c = sphere_point(cx, cy, cz, radius, segments, rings, next_seg, ring)
                d = sphere_point(cx, cy, cz, radius, segments, rings, seg, next_ring)
                triangles.append([a, b, c])
                triangles.append([a, d, b])
    return pack_triangles_xyz(triangles)


def pack_ellipsoids_xyz(ellipsoids):
    triangles = []
    for ellipsoid in ellipsoids:
        if not isinstance(ellipsoid, dict):
            raise SystemExit("scene ellipsoids_xyz entries must be objects")
        cx, cy, cz = sphere_center(ellipsoid, "ellipsoids_xyz")
        rx, ry, rz = ellipsoid_radii(ellipsoid)
        segments = sphere_segments(ellipsoid)
        rings = sphere_rings(ellipsoid)
        for ring in range(rings):
            next_ring = ring + 1
            for seg in range(segments):
                next_seg = 0 if seg + 1 == segments else seg + 1
                a = ellipsoid_point(cx, cy, cz, rx, ry, rz, segments, rings, seg, ring)
                b = ellipsoid_point(cx, cy, cz, rx, ry, rz, segments, rings, next_seg, next_ring)
                c = ellipsoid_point(cx, cy, cz, rx, ry, rz, segments, rings, next_seg, ring)
                d = ellipsoid_point(cx, cy, cz, rx, ry, rz, segments, rings, seg, next_ring)
                triangles.append([a, b, c])
                triangles.append([a, d, b])
    return pack_triangles_xyz(triangles)


def torus_radius(torus, primary, fallback, label):
    radius = torus.get(primary, torus.get(fallback))
    if radius is None:
        raise SystemExit(f"scene toruses_xyz entries must include {primary}")
    radius = int(radius)
    if radius <= 0:
        raise SystemExit(f"scene toruses_xyz {label} must be positive")
    return radius


def torus_segments(torus, primary, fallback, default_value, min_segments, max_segments, label):
    segments = int(torus.get(primary, torus.get(fallback, default_value)))
    if segments < min_segments or segments > max_segments:
        raise SystemExit(f"scene toruses_xyz {label} must be {min_segments}..{max_segments}")
    return segments


def torus_point(cx, cy, cz, major_radius, minor_radius, segments, tube_segments, seg, tube):
    theta = math.tau * seg / segments
    phi = math.tau * tube / tube_segments
    ring_radius = major_radius + minor_radius * math.cos(phi)
    x = round_half_away(cx + ring_radius * math.cos(theta))
    y = round_half_away(cy + ring_radius * math.sin(theta))
    z = round_half_away(cz + minor_radius * math.sin(phi))
    return [x, y, z]


def pack_toruses_xyz(toruses):
    triangles = []
    for torus in toruses:
        if not isinstance(torus, dict):
            raise SystemExit("scene toruses_xyz entries must be objects")
        cx, cy, cz = sphere_center(torus, "toruses_xyz")
        major_radius = torus_radius(torus, "major_radius", "radius", "major_radius")
        minor_radius = torus_radius(torus, "minor_radius", "tube_radius", "minor_radius")
        if minor_radius >= major_radius:
            raise SystemExit("scene toruses_xyz minor_radius must be smaller than major_radius")
        segments = torus_segments(torus, "major_segments", "segments", 16, 4, 96, "major_segments")
        tube_segments = torus_segments(torus, "minor_segments", "tube_segments", 8, 3, 48, "minor_segments")
        for seg in range(segments):
            next_seg = 0 if seg + 1 == segments else seg + 1
            for tube in range(tube_segments):
                next_tube = 0 if tube + 1 == tube_segments else tube + 1
                a = torus_point(cx, cy, cz, major_radius, minor_radius, segments, tube_segments, seg, tube)
                b = torus_point(cx, cy, cz, major_radius, minor_radius, segments, tube_segments, next_seg, next_tube)
                c = torus_point(cx, cy, cz, major_radius, minor_radius, segments, tube_segments, next_seg, tube)
                d = torus_point(cx, cy, cz, major_radius, minor_radius, segments, tube_segments, seg, next_tube)
                triangles.append([a, b, c])
                triangles.append([a, d, b])
    return pack_triangles_xyz(triangles)


def capsule_center(capsule):
    center = capsule.get("center", capsule.get("center_xy"))
    if not isinstance(center, list) or len(center) != 2:
        raise SystemExit("scene capsules_z center must be [x,y]")
    return int(center[0]), int(center[1])


def capsule_radius(capsule):
    radius = capsule.get("radius", capsule.get("radius_xy"))
    if radius is None:
        raise SystemExit("scene capsules_z entries must include radius")
    radius = int(radius)
    if radius <= 0:
        raise SystemExit("scene capsules_z radius must be positive")
    return radius


def capsule_z(capsule, primary, fallback):
    if primary in capsule:
        return int(capsule[primary])
    if fallback in capsule:
        return int(capsule[fallback])
    raise SystemExit(f"scene capsules_z entries must include {primary}")


def capsule_segments(capsule):
    segments = int(capsule.get("segments", 16))
    if segments < 4 or segments > 96:
        raise SystemExit("scene capsules_z segments must be 4..96")
    return segments


def capsule_rings(capsule):
    rings = int(capsule.get("rings", 4))
    if rings < 1 or rings > 48:
        raise SystemExit("scene capsules_z rings must be 1..48")
    return rings


def capsule_cap_point(cx, cy, zc, radius, segments, rings, seg, ring, top):
    theta = (math.pi * 0.5) * ring / rings
    phi = math.tau * seg / segments
    radial = radius * math.sin(theta)
    x = round_half_away(cx + radial * math.cos(phi))
    y = round_half_away(cy + radial * math.sin(phi))
    z_delta = radius * math.cos(theta)
    z = round_half_away(zc + z_delta if top else zc - z_delta)
    return [x, y, z]


def pack_capsules_z(capsules):
    triangles = []
    for capsule in capsules:
        if not isinstance(capsule, dict):
            raise SystemExit("scene capsules_z entries must be objects")
        cx, cy = capsule_center(capsule)
        radius = capsule_radius(capsule)
        z0 = capsule_z(capsule, "z_min", "min_z")
        z1 = capsule_z(capsule, "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene capsules_z z_max must be greater than z_min")
        segments = capsule_segments(capsule)
        rings = capsule_rings(capsule)
        for seg in range(segments):
            next_seg = 0 if seg + 1 == segments else seg + 1
            a0 = cylinder_point(cx, cy, radius, segments, seg, z0)
            b0 = cylinder_point(cx, cy, radius, segments, next_seg, z0)
            a1 = cylinder_point(cx, cy, radius, segments, seg, z1)
            b1 = cylinder_point(cx, cy, radius, segments, next_seg, z1)
            triangles.append([a0, b0, b1])
            triangles.append([a0, b1, a1])
            for ring in range(rings):
                next_ring = ring + 1
                top_a = capsule_cap_point(cx, cy, z1, radius, segments, rings, seg, ring, True)
                top_b = capsule_cap_point(cx, cy, z1, radius, segments, rings, next_seg, next_ring, True)
                top_c = capsule_cap_point(cx, cy, z1, radius, segments, rings, next_seg, ring, True)
                top_d = capsule_cap_point(cx, cy, z1, radius, segments, rings, seg, next_ring, True)
                triangles.append([top_a, top_b, top_c])
                triangles.append([top_a, top_d, top_b])
                bot_a = capsule_cap_point(cx, cy, z0, radius, segments, rings, seg, next_ring, False)
                bot_b = capsule_cap_point(cx, cy, z0, radius, segments, rings, next_seg, next_ring, False)
                bot_c = capsule_cap_point(cx, cy, z0, radius, segments, rings, next_seg, ring, False)
                bot_d = capsule_cap_point(cx, cy, z0, radius, segments, rings, seg, ring, False)
                triangles.append([bot_a, bot_b, bot_c])
                triangles.append([bot_a, bot_c, bot_d])
    return pack_triangles_xyz(triangles)


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


def normalize_instance(inst, templates, mesh_names, material_names):
    tpl = templates.get(inst.get("template"), {})
    if inst.get("template") is not None and not tpl:
        raise SystemExit(f"unknown scene template: {inst.get('template')!r}")
    m = dict(tpl)
    m.update(inst)
    m["mesh_id"] = resolve_id(m, "mesh_id", "mesh", mesh_names)
    m["material_id"] = resolve_id(m, "material_id", "material", material_names, 0)
    apply_transform(m)
    return m


def compose_group_model(model, group):
    g = dict(group)
    apply_transform(g)
    gx = int(g.get("x", 0))
    gy = int(g.get("y", 0))
    gz = int(g.get("z", 0))
    gscale = int(g.get("scale_milli", 1000))
    scale = (int(model.get("scale_milli", 1000)) * gscale) // 1000
    if scale <= 0:
        raise SystemExit("scene instance_group composed scale_milli must be positive")
    model["x"] = gx + (int(model.get("x", 0)) * gscale) // 1000
    model["y"] = gy + (int(model.get("y", 0)) * gscale) // 1000
    model["z"] = gz + (int(model.get("z", 0)) * gscale) // 1000
    model["scale_milli"] = scale
    return model


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
        models.append(normalize_instance(inst, templates, mesh_names, material_names))

    for group in scene.get("instance_groups", []):
        instances = group.get("instances")
        if not isinstance(instances, list):
            raise SystemExit("scene instance_group must contain instances")
        for inst in instances:
            models.append(compose_group_model(
                normalize_instance(inst, templates, mesh_names, material_names),
                group,
            ))

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


def scene3d_bin_v0(scene_bytes, base_dir=None):
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
            if has_gltf_mesh(mesh):
                payload, indices = pack_gltf_indexed(mesh, base_dir)
            elif has_obj_mesh(mesh):
                payload, indices = pack_obj_indexed(mesh, base_dir)
            elif has_ply_mesh(mesh):
                payload, indices = pack_ply_indexed(mesh, base_dir)
            else:
                payload = (
                    pack_vertices_xyz(mesh["vertices_xyz"])
                    if mesh.get("vertices_xyz") is not None
                    else bytes(mesh["vertices"])
                )
                if len(payload) % 12 != 0:
                    raise SystemExit("scene indexed mesh vertex bytes must be multiple of 12")
                vertex_count = len(payload) // 12
                if mesh.get("faces") is not None:
                    indices = pack_faces(mesh["faces"], vertex_count)
                elif mesh.get("quads") is not None:
                    indices = pack_quads(mesh["quads"], vertex_count)
                else:
                    indices = bytes(mesh["indices"])
        elif kind == "triangles":
            kind_id = 2
            if has_gltf_mesh(mesh):
                payload = pack_gltf_triangles(mesh, base_dir)
            elif has_obj_mesh(mesh):
                payload = pack_obj_triangles(mesh, base_dir)
            elif has_ply_mesh(mesh):
                payload = pack_ply_triangles(mesh, base_dir)
            elif has_stl_mesh(mesh):
                payload = pack_stl_triangles(mesh, base_dir)
            elif mesh.get("triangles_xyz") is not None:
                payload = pack_triangles_xyz(mesh["triangles_xyz"])
            elif mesh.get("quads_xyz") is not None:
                payload = pack_quads_xyz(mesh["quads_xyz"])
            elif mesh.get("boxes_xyz") is not None:
                payload = pack_boxes_xyz(mesh["boxes_xyz"])
            elif mesh.get("prisms_xy") is not None:
                payload = pack_prisms_xy(mesh["prisms_xy"])
            elif mesh.get("cylinders_z") is not None:
                payload = pack_cylinders_z(mesh["cylinders_z"])
            elif mesh.get("cones_z") is not None:
                payload = pack_cones_z(mesh["cones_z"])
            elif mesh.get("spheres_xyz") is not None:
                payload = pack_spheres_xyz(mesh["spheres_xyz"])
            elif mesh.get("ellipsoids_xyz") is not None:
                payload = pack_ellipsoids_xyz(mesh["ellipsoids_xyz"])
            elif mesh.get("toruses_xyz") is not None:
                payload = pack_toruses_xyz(mesh["toruses_xyz"])
            elif mesh.get("capsules_z") is not None:
                payload = pack_capsules_z(mesh["capsules_z"])
            else:
                payload = bytes(mesh["triangles"])
            indices = b""
        elif kind == "triangles_rgba":
            kind_id = 3
            if has_gltf_mesh(mesh):
                payload = pack_gltf_triangles_rgba(mesh, base_dir)
            elif has_ply_mesh(mesh):
                payload = pack_ply_triangles_rgba(mesh, base_dir)
            elif mesh.get("triangles_xyz_rgba") is not None:
                payload = pack_triangles_xyz_rgba(mesh["triangles_xyz_rgba"])
            else:
                payload = bytes(mesh["triangles"])
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
    out.write_bytes(scene3d_bin_v0(src.read_text(encoding="utf-8"), src.parent))


if __name__ == "__main__":
    main(sys.argv)
