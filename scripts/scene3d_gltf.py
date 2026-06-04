#!/usr/bin/env python3
"""glTF 2.0 mesh lowering helpers for make_scene3d_bin_v0.py."""

import base64
import json
import math
import pathlib
import struct


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
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
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
    component_fmt, component_size = GLTF_COMPONENTS[component_type]
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
        values.append(list(struct.unpack_from(fmt, data, pos)))
    return values


def gltf_indices_for_primitive(doc, primitive, vertex_count, base_dir):
    if primitive.get("indices") is None:
        return list(range(vertex_count))
    raw = gltf_accessor_values(doc, int(primitive["indices"]), base_dir)
    indices = [int(item[0]) for item in raw]
    for idx in indices:
        if idx < 0 or idx >= vertex_count:
            raise SystemExit("scene glTF primitive index out of bounds")
    return indices


def gltf_primitive_faces(local_indices, mode):
    if len(local_indices) < 3:
        raise SystemExit("scene glTF triangle-based primitive needs at least 3 indices")
    if mode == 4:
        if len(local_indices) % 3 != 0:
            raise SystemExit("scene glTF TRIANGLES index count must be a multiple of 3")
        return [
            [local_indices[i], local_indices[i + 1], local_indices[i + 2]]
            for i in range(0, len(local_indices), 3)
        ]
    if mode == 5:
        return [
            [local_indices[i], local_indices[i + 1 + (i % 2)], local_indices[i + 2 - (i % 2)]]
            for i in range(0, len(local_indices) - 2)
        ]
    if mode == 6:
        return [
            [local_indices[i + 1], local_indices[i + 2], local_indices[0]]
            for i in range(0, len(local_indices) - 2)
        ]
    raise SystemExit("scene glTF only TRIANGLES, TRIANGLE_STRIP, and TRIANGLE_FAN primitives are supported")


def round_half_away(v):
    return int(math.floor(v + 0.5)) if v >= 0 else int(math.ceil(v - 0.5))


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


def gltf_multiply_rgba(a, b):
    return tuple(round_half_away(float(a[i]) * float(b[i]) / 255.0) for i in range(4))


def mat_identity():
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def mat_mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def mat_translate(t):
    m = mat_identity()
    m[0][3], m[1][3], m[2][3] = t
    return m


def mat_scale(s):
    m = mat_identity()
    m[0][0], m[1][1], m[2][2] = s
    return m


def mat_from_gltf_column_major(values):
    if not isinstance(values, list) or len(values) != 16:
        raise SystemExit("scene glTF node matrix must contain 16 values")
    return [[float(values[c * 4 + r]) for c in range(4)] for r in range(4)]


def mat_from_quat(q):
    if not isinstance(q, list) or len(q) != 4:
        raise SystemExit("scene glTF node rotation must be [x,y,z,w]")
    x, y, z, w = (float(q[0]), float(q[1]), float(q[2]), float(q[3]))
    n = math.sqrt(x * x + y * y + z * z + w * w)
    if n <= 0.0:
        raise SystemExit("scene glTF node rotation quaternion must be nonzero")
    x, y, z, w = x / n, y / n, z / n, w / n
    return [
        [1.0 - 2.0 * y * y - 2.0 * z * z, 2.0 * x * y - 2.0 * z * w, 2.0 * x * z + 2.0 * y * w, 0.0],
        [2.0 * x * y + 2.0 * z * w, 1.0 - 2.0 * x * x - 2.0 * z * z, 2.0 * y * z - 2.0 * x * w, 0.0],
        [2.0 * x * z - 2.0 * y * w, 2.0 * y * z + 2.0 * x * w, 1.0 - 2.0 * x * x - 2.0 * y * y, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def gltf_node_vec3(node, key, default):
    value = node.get(key, default)
    if not isinstance(value, list) or len(value) != 3:
        raise SystemExit(f"scene glTF node {key} must be [x,y,z]")
    return (float(value[0]), float(value[1]), float(value[2]))


def gltf_node_local_matrix(node):
    if node.get("matrix") is not None:
        if any(node.get(k) is not None for k in ("translation", "rotation", "scale")):
            raise SystemExit("scene glTF node cannot mix matrix and TRS transforms")
        return mat_from_gltf_column_major(node["matrix"])
    translation = gltf_node_vec3(node, "translation", [0.0, 0.0, 0.0])
    scale = gltf_node_vec3(node, "scale", [1.0, 1.0, 1.0])
    rotation = mat_from_quat(node.get("rotation", [0.0, 0.0, 0.0, 1.0]))
    return mat_mul(mat_mul(mat_translate(translation), rotation), mat_scale(scale))


def gltf_node_index(doc, mesh):
    node_ref = mesh.get("gltf_node")
    if node_ref is None:
        return None
    nodes = doc.get("nodes", [])
    if isinstance(node_ref, int):
        if node_ref < 0 or node_ref >= len(nodes):
            raise SystemExit("scene glTF node index out of bounds")
        return node_ref
    for i, node in enumerate(nodes):
        if node.get("name") == node_ref:
            return i
    raise SystemExit("scene glTF node not found")


def gltf_scene_index(doc, mesh):
    scenes = doc.get("scenes", [])
    scene_ref = mesh.get("gltf_scene", doc.get("scene", 0))
    if not scenes:
        raise SystemExit("scene glTF scene selection requires scenes")
    if isinstance(scene_ref, int):
        if scene_ref < 0 or scene_ref >= len(scenes):
            raise SystemExit("scene glTF scene index out of bounds")
        return scene_ref
    for i, scene in enumerate(scenes):
        if scene.get("name") == scene_ref:
            return i
    raise SystemExit("scene glTF scene not found")


def gltf_node_parent_map(nodes):
    parents = {}
    for parent_idx, node in enumerate(nodes):
        for child in node.get("children", []):
            child_idx = int(child)
            if child_idx < 0 or child_idx >= len(nodes):
                raise SystemExit("scene glTF child node index out of bounds")
            if child_idx in parents:
                raise SystemExit("scene glTF node has multiple parents")
            parents[child_idx] = parent_idx
    return parents


def gltf_node_global_matrix(doc, node_index):
    nodes = doc.get("nodes", [])
    parents = gltf_node_parent_map(nodes)
    chain = []
    seen = set()
    idx = node_index
    while idx is not None:
        if idx in seen:
            raise SystemExit("scene glTF node hierarchy cycle")
        seen.add(idx)
        chain.append(idx)
        idx = parents.get(idx)
    m = mat_identity()
    for idx in reversed(chain):
        m = mat_mul(m, gltf_node_local_matrix(nodes[idx]))
    return m


def gltf_apply_node_transform(v, matrix):
    x, y, z = float(v[0]), float(v[1]), float(v[2])
    w = matrix[3][0] * x + matrix[3][1] * y + matrix[3][2] * z + matrix[3][3]
    if w == 0.0:
        raise SystemExit("scene glTF node transform produced zero homogeneous coordinate")
    return [
        (matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z + matrix[0][3]) / w,
        (matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z + matrix[1][3]) / w,
        (matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z + matrix[2][3]) / w,
    ]


def gltf_append_mesh(doc, mesh_index, node_matrix, base_dir, vertices, faces, vertex_colors, face_colors):
    meshes = doc.get("meshes", [])
    if mesh_index < 0 or mesh_index >= len(meshes):
        raise SystemExit("scene glTF mesh index out of bounds")
    for primitive in meshes[mesh_index].get("primitives", []):
        mode = int(primitive.get("mode", 4))
        attributes = primitive.get("attributes", {})
        if attributes.get("POSITION") is None:
            raise SystemExit("scene glTF primitive missing POSITION accessor")
        positions = gltf_accessor_values(doc, int(attributes["POSITION"]), base_dir)
        base_vertex = len(vertices)
        vertices.extend([gltf_apply_node_transform(pos, node_matrix) for pos in positions])
        colors = None
        if attributes.get("COLOR_0") is not None:
            colors = gltf_accessor_color(doc, int(attributes["COLOR_0"]), base_dir)
            if len(colors) != len(positions):
                raise SystemExit("scene glTF COLOR_0 count must match POSITION count")
        vertex_colors.extend(colors if colors is not None else [None] * len(positions))
        local_indices = gltf_indices_for_primitive(doc, primitive, len(positions), base_dir)
        local_faces = gltf_primitive_faces(local_indices, mode)
        material_color = gltf_material_color(doc, primitive)
        if colors is not None:
            colors = [gltf_multiply_rgba(color, material_color) for color in colors]
            vertex_colors[base_vertex:base_vertex + len(colors)] = colors
        for local_face in local_faces:
            face = [base_vertex + idx for idx in local_face]
            faces.append(face)
            face_colors.append(material_color if colors is None else None)


def gltf_collect_scene_targets(doc, scene_index):
    scenes = doc.get("scenes", [])
    nodes = doc.get("nodes", [])
    scene = scenes[scene_index]
    roots = scene.get("nodes", [])
    if not isinstance(roots, list):
        raise SystemExit("scene glTF scene nodes must be a list")
    targets = []

    def walk(node_index, parent_matrix, path):
        if node_index < 0 or node_index >= len(nodes):
            raise SystemExit("scene glTF scene node index out of bounds")
        if node_index in path:
            raise SystemExit("scene glTF node hierarchy cycle")
        node = nodes[node_index]
        matrix = mat_mul(parent_matrix, gltf_node_local_matrix(node))
        if node.get("mesh") is not None:
            targets.append((int(node["mesh"]), matrix))
        next_path = path | {node_index}
        for child in node.get("children", []):
            walk(int(child), matrix, next_path)

    for root in roots:
        walk(int(root), mat_identity(), set())
    if not targets:
        raise SystemExit("scene glTF scene has no mesh nodes")
    return targets


def gltf_mesh_targets(doc, mesh):
    node_index = gltf_node_index(doc, mesh)
    if node_index is not None:
        node = doc.get("nodes", [])[node_index]
        if node.get("mesh") is None:
            raise SystemExit("scene glTF node does not reference a mesh")
        return [(int(node["mesh"]), gltf_node_global_matrix(doc, node_index))]
    if mesh.get("gltf_scene") is not None or (mesh.get("gltf_mesh") is None and doc.get("scenes") is not None):
        return gltf_collect_scene_targets(doc, gltf_scene_index(doc, mesh))
    return [(int(mesh.get("gltf_mesh", 0)), mat_identity())]


def gltf_mesh_data(mesh, base_dir):
    doc = gltf_source_json(mesh, base_dir)
    asset = doc.get("asset", {})
    if str(asset.get("version", "")).split(".", 1)[0] != "2":
        raise SystemExit("scene glTF asset.version must be 2.x")
    vertices = []
    faces = []
    vertex_colors = []
    face_colors = []
    for mesh_index, node_matrix in gltf_mesh_targets(doc, mesh):
        gltf_append_mesh(doc, mesh_index, node_matrix, base_dir, vertices, faces, vertex_colors, face_colors)
    if not vertices:
        raise SystemExit("scene glTF mesh has no vertices")
    if not faces:
        raise SystemExit("scene glTF mesh has no triangle faces")
    return vertices, faces, vertex_colors, face_colors
