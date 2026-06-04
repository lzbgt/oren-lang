#!/usr/bin/env python3
"""3MF core mesh lowering helpers for make_scene3d_bin_v0.py."""

import pathlib
import io
import xml.etree.ElementTree as ET
import zipfile


THREEMF_UNITS_TO_MM = {
    "micron": 0.001,
    "millimeter": 1.0,
    "centimeter": 10.0,
    "inch": 25.4,
    "foot": 304.8,
    "meter": 1000.0,
}


def has_threemf_mesh(mesh):
    return mesh.get("3mf_source") is not None or mesh.get("threemf_source") is not None


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


def zip_part_name(name):
    raw = str(name).lstrip("/")
    rel = pathlib.PurePosixPath(raw)
    if raw == "" or rel.is_absolute() or ".." in rel.parts:
        raise SystemExit("scene 3MF package part path is unsafe")
    return "/".join(rel.parts)


def read_zip_part(zf, name):
    part = zip_part_name(name)
    try:
        return zf.read(part)
    except KeyError as exc:
        raise SystemExit(f"scene 3MF package missing part: {name}") from exc


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def child(elem, name):
    for item in list(elem):
        if local_name(item.tag) == name:
            return item
    return None


def children(elem, name):
    return [item for item in list(elem) if local_name(item.tag) == name]


def parse_color(value):
    raw = str(value or "")
    if not raw.startswith("#") or len(raw) not in (7, 9):
        raise SystemExit("scene 3MF basematerial displaycolor must be #RRGGBB or #RRGGBBAA")
    if len(raw) == 7:
        raw += "ff"
    try:
        return (
            int(raw[1:3], 16),
            int(raw[3:5], 16),
            int(raw[5:7], 16),
            int(raw[7:9], 16),
        )
    except ValueError as exc:
        raise SystemExit("scene 3MF basematerial displaycolor must be hexadecimal") from exc


def parse_resource_index(value, context):
    try:
        idx = int(value)
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"scene 3MF {context} index must be an integer") from exc
    if idx < 0:
        raise SystemExit(f"scene 3MF {context} index must be non-negative")
    return idx


def parse_basematerials(resources):
    groups = {}
    for group in children(resources, "basematerials"):
        group_id = group.get("id")
        if group_id is None:
            raise SystemExit("scene 3MF basematerials missing id")
        colors = []
        for base in children(group, "base"):
            colors.append(parse_color(base.get("displaycolor")))
        groups[group_id] = colors
    return groups


def material_color(groups, pid, pindex, context):
    if pid is None and pindex is None:
        return None
    if pid is None or pindex is None:
        raise SystemExit(f"scene 3MF {context} material must include pid and pindex")
    group = groups.get(pid)
    if group is None:
        return None
    idx = parse_resource_index(pindex, context)
    if idx < 0 or idx >= len(group):
        raise SystemExit(f"scene 3MF {context} material index out of bounds")
    return group[idx]


def threemf_source_bytes(mesh, base_dir):
    rel = mesh.get("3mf_source", mesh.get("threemf_source"))
    if rel is None:
        raise SystemExit("scene 3MF mesh must include 3mf_source")
    return read_relative_bytes(base_dir, rel, "3mf_source")


def threemf_root_model_path(zf):
    try:
        rels = ET.fromstring(zf.read("_rels/.rels"))
    except KeyError:
        rels = None
    if rels is not None:
        for rel in list(rels):
            if local_name(rel.tag) != "Relationship":
                continue
            typ = rel.get("Type", "")
            if typ.endswith("/3dmodel"):
                return zip_part_name(rel.get("Target", ""))
    return "3D/3dmodel.model"


def mat_identity():
    return (
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
        0.0, 0.0, 0.0,
    )


def parse_matrix(value):
    if value is None or str(value).strip() == "":
        return mat_identity()
    parts = [float(part) for part in str(value).split()]
    if len(parts) != 12:
        raise SystemExit("scene 3MF transform must contain 12 row-major values")
    return tuple(parts)


def mat_mul(a, b):
    # Row-vector affine composition: p * (a*b) applies a, then b.
    out = []
    for col in range(3):
        out.append(a[0] * b[col] + a[1] * b[3 + col] + a[2] * b[6 + col])
    for col in range(3):
        out.append(a[3] * b[col] + a[4] * b[3 + col] + a[5] * b[6 + col])
    for col in range(3):
        out.append(a[6] * b[col] + a[7] * b[3 + col] + a[8] * b[6 + col])
    for col in range(3):
        out.append(a[9] * b[col] + a[10] * b[3 + col] + a[11] * b[6 + col] + b[9 + col])
    return tuple(out)


def mat_apply(m, point):
    x, y, z = float(point[0]), float(point[1]), float(point[2])
    return (
        x * m[0] + y * m[3] + z * m[6] + m[9],
        x * m[1] + y * m[4] + z * m[7] + m[10],
        x * m[2] + y * m[5] + z * m[8] + m[11],
    )


def mat_det3(m):
    return (
        m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6])
    )


def triangle_set_selector(mesh):
    ref = mesh.get("3mf_triangle_set", mesh.get("threemf_triangle_set"))
    if ref is None:
        return None
    return str(ref)


def selected_triangle_set_indices(mesh_elem, selector, triangle_count):
    if selector is None:
        return None
    sets_elem = child(mesh_elem, "trianglesets")
    if sets_elem is None:
        raise SystemExit("scene 3MF triangle set requested but mesh has no trianglesets")
    selected = None
    for set_index, tri_set in enumerate(children(sets_elem, "triangleset")):
        if selector in (str(set_index), tri_set.get("name"), tri_set.get("identifier")):
            selected = tri_set
            break
    if selected is None:
        raise SystemExit("scene 3MF triangle set not found")
    indices = []
    seen = set()
    for item in list(selected):
        name = local_name(item.tag)
        if name == "ref":
            refs = [parse_resource_index(item.get("index"), "triangle-set ref")]
        elif name == "refrange":
            start = parse_resource_index(item.get("startindex"), "triangle-set range")
            end = parse_resource_index(item.get("endindex"), "triangle-set range")
            if end < start:
                raise SystemExit("scene 3MF triangle-set range end must be >= start")
            refs = range(start, end + 1)
        else:
            continue
        for idx in refs:
            if idx >= triangle_count:
                raise SystemExit("scene 3MF triangle-set index out of bounds")
            if idx not in seen:
                seen.add(idx)
                indices.append(idx)
    if not indices:
        raise SystemExit("scene 3MF triangle set must reference at least one triangle")
    return set(indices)


def parse_mesh(object_elem, material_groups, unit_scale, matrix, inherited_property, triangle_selector, vertices, faces, face_colors):
    mesh = child(object_elem, "mesh")
    if mesh is None:
        return False
    vertices_elem = child(mesh, "vertices")
    triangles_elem = child(mesh, "triangles")
    if vertices_elem is None or triangles_elem is None:
        raise SystemExit("scene 3MF mesh must contain vertices and triangles")
    base = len(vertices)
    for vertex in children(vertices_elem, "vertex"):
        point = (
            float(vertex.get("x")) * unit_scale,
            float(vertex.get("y")) * unit_scale,
            float(vertex.get("z")) * unit_scale,
        )
        vertices.append(mat_apply(matrix, point))
    count = len(vertices) - base
    if count < 3:
        raise SystemExit("scene 3MF mesh must contain at least 3 vertices")
    default_pid = object_elem.get("pid", inherited_property[0])
    default_pindex = object_elem.get("pindex", inherited_property[1])
    flip = mat_det3(matrix) < 0.0
    triangles = children(triangles_elem, "triangle")
    selected_indices = selected_triangle_set_indices(mesh, triangle_selector, len(triangles))
    for tri_index, tri in enumerate(triangles):
        if selected_indices is not None and tri_index not in selected_indices:
            continue
        face = [
            parse_resource_index(tri.get("v1"), "triangle vertex"),
            parse_resource_index(tri.get("v2"), "triangle vertex"),
            parse_resource_index(tri.get("v3"), "triangle vertex"),
        ]
        if len(set(face)) != 3:
            raise SystemExit("scene 3MF triangle vertices must be distinct")
        if any(idx < 0 or idx >= count for idx in face):
            raise SystemExit("scene 3MF triangle index out of bounds")
        tri_pid = tri.get("pid", default_pid)
        p1 = tri.get("p1", default_pindex)
        p2 = tri.get("p2", p1)
        p3 = tri.get("p3", p1)
        if tri_pid in material_groups and (p1 != p2 or p1 != p3):
            raise SystemExit("scene 3MF basematerial gradients are unsupported by Core")
        color = material_color(material_groups, tri_pid, p1, "triangle")
        if flip:
            face = [face[0], face[2], face[1]]
        faces.append([base + idx for idx in face])
        face_colors.append(color)
    return True


def collect_object(object_id, objects, material_groups, unit_scale, matrix, inherited_property, triangle_selector, vertices, faces, face_colors, stack):
    if object_id in stack:
        raise SystemExit("scene 3MF component cycle")
    obj = objects.get(object_id)
    if obj is None:
        raise SystemExit("scene 3MF object reference not found")
    if parse_mesh(obj, material_groups, unit_scale, matrix, inherited_property, triangle_selector, vertices, faces, face_colors):
        return
    comps = child(obj, "components")
    if comps is None:
        raise SystemExit("scene 3MF object must contain mesh or components")
    next_stack = stack | {object_id}
    for comp in children(comps, "component"):
        child_id = comp.get("objectid")
        if child_id is None:
            raise SystemExit("scene 3MF component missing objectid")
        collect_object(
            child_id,
            objects,
            material_groups,
            unit_scale,
            mat_mul(parse_matrix(comp.get("transform")), matrix),
            inherited_property,
            triangle_selector,
            vertices,
            faces,
            face_colors,
            next_stack,
        )


def selected_object_id(mesh, objects):
    ref = mesh.get("3mf_object", mesh.get("threemf_object"))
    if ref is None:
        return None
    raw = str(ref)
    if raw in objects:
        return raw
    for object_id, obj in objects.items():
        if obj.get("name") == raw:
            return object_id
    raise SystemExit("scene 3MF object not found")


def threemf_mesh_data(mesh, base_dir):
    data = threemf_source_bytes(mesh, base_dir)
    vertices = []
    faces = []
    face_colors = []
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        model = ET.fromstring(read_zip_part(zf, threemf_root_model_path(zf)))
    unit = model.get("unit", "millimeter")
    if unit not in THREEMF_UNITS_TO_MM:
        raise SystemExit("scene 3MF model unit unsupported")
    resources = child(model, "resources")
    if resources is None:
        raise SystemExit("scene 3MF model missing resources")
    material_groups = parse_basematerials(resources)
    objects = {obj.get("id"): obj for obj in children(resources, "object") if obj.get("id") is not None}
    tri_selector = triangle_set_selector(mesh)
    target_object = selected_object_id(mesh, objects)
    if target_object is not None:
        collect_object(target_object, objects, material_groups, THREEMF_UNITS_TO_MM[unit], mat_identity(), (None, None), tri_selector, vertices, faces, face_colors, set())
    else:
        build = child(model, "build")
        if build is None:
            raise SystemExit("scene 3MF model missing build")
        items = children(build, "item")
        if not items:
            raise SystemExit("scene 3MF build has no items")
        for item in items:
            object_id = item.get("objectid")
            if object_id is None:
                raise SystemExit("scene 3MF build item missing objectid")
            collect_object(
                object_id,
                objects,
                material_groups,
                THREEMF_UNITS_TO_MM[unit],
                parse_matrix(item.get("transform")),
                (item.get("pid"), item.get("pindex")),
                tri_selector,
                vertices,
                faces,
                face_colors,
                set(),
            )
    if not vertices:
        raise SystemExit("scene 3MF mesh has no vertices")
    if not faces:
        raise SystemExit("scene 3MF mesh has no triangle faces")
    return vertices, faces, face_colors
