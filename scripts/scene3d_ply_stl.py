#!/usr/bin/env python3
"""PLY/STL mesh source lowering for byte-native Scene3D OS3D assets."""

import pathlib
import struct
import math


def u32(v):
    return struct.pack("<I", int(v) & 0xFFFFFFFF)


def i32(v):
    return struct.pack("<i", int(v))


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
    return f"#{int(r) & 255:02x}{int(g) & 255:02x}{int(b) & 255:02x}{int(a) & 255:02x}"


def pack_vertices_xyz(points):
    out = bytearray()
    for p in points:
        if not isinstance(p, list) or len(p) != 3:
            raise SystemExit("scene vertices_xyz entries must be [x,y,z]")
        out += i32(p[0]) + i32(p[1]) + i32(p[2])
    return bytes(out)


def pack_faces(faces, vertex_count):
    out = bytearray()
    for face in faces:
        if not isinstance(face, list) or len(face) != 3:
            raise SystemExit("scene faces entries must be [i,j,k]")
        for idx in face:
            if int(idx) < 0 or int(idx) >= vertex_count:
                raise SystemExit("scene face index out of bounds")
            out += u32(idx)
    return bytes(out)


def pack_triangles_xyz(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, list) or len(tri) != 3:
            raise SystemExit("scene triangles_xyz entries must be [[x,y,z] x3]")
        for p in tri:
            if not isinstance(p, list) or len(p) != 3:
                raise SystemExit("scene triangles_xyz point must be [x,y,z]")
            out += i32(p[0]) + i32(p[1]) + i32(p[2])
    return bytes(out)


def pack_triangles_xyz_rgba(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, dict):
            raise SystemExit("scene triangles_xyz_rgba entries must be objects")
        verts = tri.get("vertices")
        if not isinstance(verts, list) or len(verts) != 3:
            raise SystemExit("scene triangles_xyz_rgba vertices must be length 3")
        for p in verts:
            if not isinstance(p, list) or len(p) != 3:
                raise SystemExit("scene triangles_xyz_rgba point must be [x,y,z]")
            out += i32(p[0]) + i32(p[1]) + i32(p[2])
        out += color_rgba_bytes(tri.get("color", "#ffffffff"))
    return bytes(out)


def round_half_away(value):
    if value >= 0:
        return int(math.floor(value + 0.5))
    return int(math.ceil(value - 0.5))


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
