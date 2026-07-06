"""Flat radial/arc mesh packers for OS3D01 package authoring."""

import math


def i32(v):
    return int(v).to_bytes(4, "little", signed=True)


def pack_vertices_xyz(points):
    out = bytearray()
    for point in points:
        if not isinstance(point, list) or len(point) != 3:
            raise SystemExit("scene vertices_xyz entries must be [x,y,z]")
        out += i32(point[0]) + i32(point[1]) + i32(point[2])
    return bytes(out)


def pack_triangles_xyz(triangles):
    out = bytearray()
    for tri in triangles:
        if not isinstance(tri, list) or len(tri) != 3:
            raise SystemExit("scene triangles_xyz entries must contain 3 vertices")
        out += pack_vertices_xyz(tri)
    return bytes(out)


def round_half_away(value):
    if not math.isfinite(value):
        raise SystemExit("scene flat shape coordinate is not finite")
    if value >= 0.0:
        return int(math.floor(value + 0.5))
    return int(math.ceil(value - 0.5))


def flat_xy_pair(value, key, label):
    if not isinstance(value, list) or len(value) != 2:
        raise SystemExit(f"scene {key} {label} must be [x,y]")
    return int(value[0]), int(value[1])


def flat_xy_z(item, key):
    z = item.get("z", item.get("z_milli", 0))
    try:
        return int(z)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} z must be i32")


def flat_xy_rect_bounds(item, key):
    if not isinstance(item, dict):
        raise SystemExit(f"scene {key} entries must be objects")
    lo = item.get("min", item.get("min_xy"))
    hi = item.get("max", item.get("max_xy"))
    if lo is not None or hi is not None:
        x0, y0 = flat_xy_pair(lo, key, "min")
        x1, y1 = flat_xy_pair(hi, key, "max")
        z = flat_xy_z(item, key)
    else:
        origin = item.get("origin", item.get("origin_xyz"))
        if not isinstance(origin, list) or len(origin) != 3:
            raise SystemExit(f"scene {key} origin must be [x,y,z]")
        size = item.get("size", item.get("size_xy"))
        w, h = flat_xy_pair(size, key, "size")
        x0, y0, z = int(origin[0]), int(origin[1]), int(origin[2])
        x1, y1 = x0 + w, y0 + h
    if x1 <= x0 or y1 <= y0:
        raise SystemExit(f"scene {key} max must be greater than min")
    return x0, y0, x1, y1, z


def flat_shape_center(item, key):
    center = item.get("center", item.get("center_xy"))
    return flat_xy_pair(center, key, "center")


def flat_shape_positive_i32(item, key, primary, fallback=None, default=None):
    if primary in item:
        value = item[primary]
    elif fallback is not None and fallback in item:
        value = item[fallback]
    else:
        value = default
    try:
        value = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} {primary} must be positive i32")
    if value <= 0:
        raise SystemExit(f"scene {key} {primary} must be positive i32")
    return value


def flat_shape_radii(item, key, primary, fallback):
    radii = item.get(primary, item.get(fallback))
    rx, ry = flat_xy_pair(radii, key, primary)
    if rx <= 0 or ry <= 0:
        raise SystemExit(f"scene {key} {primary} must be positive [x,y]")
    return rx, ry


def flat_shape_segments(item, key, minimum=3, default=16, maximum=96, label="segments"):
    value = item.get(label, default)
    try:
        value = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} {label} must be {minimum}..{maximum}")
    if value < minimum or value > maximum:
        raise SystemExit(f"scene {key} {label} must be {minimum}..{maximum}")
    return value


def circle_xy(cx, cy, radius, segments, index):
    angle = math.tau * float(index) / float(segments)
    return (
        cx + round_half_away(math.cos(angle) * float(radius)),
        cy + round_half_away(math.sin(angle) * float(radius)),
    )


def ellipse_xy(cx, cy, rx, ry, segments, index):
    angle = math.tau * float(index) / float(segments)
    return (
        cx + round_half_away(math.cos(angle) * float(rx)),
        cy + round_half_away(math.sin(angle) * float(ry)),
    )


def angle_xy(cx, cy, radius, angle_milli_deg):
    angle = math.tau * float(angle_milli_deg) / 360000.0
    return (
        cx + round_half_away(math.cos(angle) * float(radius)),
        cy + round_half_away(math.sin(angle) * float(radius)),
    )


def flat_angle_milli(item, key, primary, fallback, short):
    if primary in item:
        value = item[primary]
    elif fallback in item:
        value = item[fallback]
    elif short in item:
        value = item[short]
    else:
        raise SystemExit(f"scene {key} {primary} must be i32")
    try:
        return int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} {primary} must be i32")


def flat_angle_span(item, key):
    start = flat_angle_milli(item, key, "start_angle_milli_deg", "start_milli_deg", "start")
    end = flat_angle_milli(item, key, "end_angle_milli_deg", "end_milli_deg", "end")
    if end <= start:
        raise SystemExit(f"scene {key} end angle must be greater than start")
    if end - start > 360000:
        raise SystemExit(f"scene {key} angle span must be <= 360 degrees")
    return start, end


def guard_triangle_budget(triangles, key, limit=4096):
    if len(triangles) > limit:
        raise SystemExit(f"scene {key} exceed mesh3d triangle budget")


def pack_discs_xy(discs):
    triangles = []
    for disc in discs:
        if not isinstance(disc, dict):
            raise SystemExit("scene discs_xy entries must be objects")
        cx, cy = flat_shape_center(disc, "discs_xy")
        radius = flat_shape_positive_i32(disc, "discs_xy", "radius", "radius_xy")
        segments = flat_shape_segments(disc, "discs_xy")
        z = flat_xy_z(disc, "discs_xy")
        for i in range(segments):
            x0, y0 = circle_xy(cx, cy, radius, segments, i)
            x1, y1 = circle_xy(cx, cy, radius, segments, i + 1)
            triangles.append([[cx, cy, z], [x0, y0, z], [x1, y1, z]])
    guard_triangle_budget(triangles, "discs_xy")
    return pack_triangles_xyz(triangles)


def pack_ellipses_xy(ellipses):
    triangles = []
    for ellipse in ellipses:
        if not isinstance(ellipse, dict):
            raise SystemExit("scene ellipses_xy entries must be objects")
        cx, cy = flat_shape_center(ellipse, "ellipses_xy")
        rx, ry = flat_shape_radii(ellipse, "ellipses_xy", "radii", "radii_xy")
        segments = flat_shape_segments(ellipse, "ellipses_xy")
        z = flat_xy_z(ellipse, "ellipses_xy")
        for i in range(segments):
            x0, y0 = ellipse_xy(cx, cy, rx, ry, segments, i)
            x1, y1 = ellipse_xy(cx, cy, rx, ry, segments, i + 1)
            triangles.append([[cx, cy, z], [x0, y0, z], [x1, y1, z]])
    guard_triangle_budget(triangles, "ellipses_xy")
    return pack_triangles_xyz(triangles)


def pack_regular_polygons_xy(polygons):
    triangles = []
    for poly in polygons:
        if not isinstance(poly, dict):
            raise SystemExit("scene regular_polygons_xy entries must be objects")
        cx, cy = flat_shape_center(poly, "regular_polygons_xy")
        radius = flat_shape_positive_i32(poly, "regular_polygons_xy", "radius", "radius_xy")
        label = "sides" if "sides" in poly else "segments"
        sides = flat_shape_segments(poly, "regular_polygons_xy", 3, 6, 96, label)
        z = flat_xy_z(poly, "regular_polygons_xy")
        for i in range(sides):
            x0, y0 = circle_xy(cx, cy, radius, sides, i)
            x1, y1 = circle_xy(cx, cy, radius, sides, i + 1)
            triangles.append([[cx, cy, z], [x0, y0, z], [x1, y1, z]])
    guard_triangle_budget(triangles, "regular_polygons_xy")
    return pack_triangles_xyz(triangles)


def pack_stars_xy(stars):
    triangles = []
    for star in stars:
        if not isinstance(star, dict):
            raise SystemExit("scene stars_xy entries must be objects")
        cx, cy = flat_shape_center(star, "stars_xy")
        inner = flat_shape_positive_i32(star, "stars_xy", "inner_radius", "radius_inner")
        outer = flat_shape_positive_i32(star, "stars_xy", "outer_radius", "radius_outer")
        if outer <= inner:
            raise SystemExit("scene stars_xy outer_radius must be greater than inner_radius")
        points = flat_shape_segments(star, "stars_xy", 3, 5, 48, "points")
        vertices = points * 2
        z = flat_xy_z(star, "stars_xy")
        for i in range(vertices):
            r0 = outer if i % 2 == 0 else inner
            r1 = outer if (i + 1) % 2 == 0 else inner
            x0, y0 = circle_xy(cx, cy, r0, vertices, i)
            x1, y1 = circle_xy(cx, cy, r1, vertices, i + 1)
            triangles.append([[cx, cy, z], [x0, y0, z], [x1, y1, z]])
    guard_triangle_budget(triangles, "stars_xy")
    return pack_triangles_xyz(triangles)


def ring_triangles(cx, cy, inner, outer, segments, z, key):
    if outer <= inner:
        raise SystemExit(f"scene {key} outer_radius must be greater than inner_radius")
    triangles = []
    for i in range(segments):
        ox0, oy0 = circle_xy(cx, cy, outer, segments, i)
        ox1, oy1 = circle_xy(cx, cy, outer, segments, i + 1)
        ix0, iy0 = circle_xy(cx, cy, inner, segments, i)
        ix1, iy1 = circle_xy(cx, cy, inner, segments, i + 1)
        triangles.append([[ox0, oy0, z], [ox1, oy1, z], [ix1, iy1, z]])
        triangles.append([[ox0, oy0, z], [ix1, iy1, z], [ix0, iy0, z]])
    return triangles


def pack_rings_xy(rings):
    triangles = []
    for ring in rings:
        if not isinstance(ring, dict):
            raise SystemExit("scene rings_xy entries must be objects")
        cx, cy = flat_shape_center(ring, "rings_xy")
        inner = flat_shape_positive_i32(ring, "rings_xy", "inner_radius", "radius_inner")
        outer = flat_shape_positive_i32(ring, "rings_xy", "outer_radius", "radius_outer")
        segments = flat_shape_segments(ring, "rings_xy")
        triangles.extend(ring_triangles(cx, cy, inner, outer, segments, flat_xy_z(ring, "rings_xy"), "rings_xy"))
    guard_triangle_budget(triangles, "rings_xy")
    return pack_triangles_xyz(triangles)


def pack_ellipse_rings_xy(rings):
    triangles = []
    for ring in rings:
        if not isinstance(ring, dict):
            raise SystemExit("scene ellipse_rings_xy entries must be objects")
        cx, cy = flat_shape_center(ring, "ellipse_rings_xy")
        irx, iry = flat_shape_radii(ring, "ellipse_rings_xy", "inner_radii", "radii_inner")
        orx, ory = flat_shape_radii(ring, "ellipse_rings_xy", "outer_radii", "radii_outer")
        if orx <= irx or ory <= iry:
            raise SystemExit("scene ellipse_rings_xy outer_radii must be greater than inner_radii")
        segments = flat_shape_segments(ring, "ellipse_rings_xy")
        z = flat_xy_z(ring, "ellipse_rings_xy")
        for i in range(segments):
            ox0, oy0 = ellipse_xy(cx, cy, orx, ory, segments, i)
            ox1, oy1 = ellipse_xy(cx, cy, orx, ory, segments, i + 1)
            ix0, iy0 = ellipse_xy(cx, cy, irx, iry, segments, i)
            ix1, iy1 = ellipse_xy(cx, cy, irx, iry, segments, i + 1)
            triangles.append([[ox0, oy0, z], [ox1, oy1, z], [ix1, iy1, z]])
            triangles.append([[ox0, oy0, z], [ix1, iy1, z], [ix0, iy0, z]])
    guard_triangle_budget(triangles, "ellipse_rings_xy")
    return pack_triangles_xyz(triangles)


def pack_sectors_xy(sectors):
    triangles = []
    for sector in sectors:
        if not isinstance(sector, dict):
            raise SystemExit("scene sectors_xy entries must be objects")
        cx, cy = flat_shape_center(sector, "sectors_xy")
        radius = flat_shape_positive_i32(sector, "sectors_xy", "radius", "radius_xy")
        start, end = flat_angle_span(sector, "sectors_xy")
        segments = flat_shape_segments(sector, "sectors_xy", 1, 16, 96)
        z = flat_xy_z(sector, "sectors_xy")
        for i in range(segments):
            a0 = start + (end - start) * i // segments
            a1 = start + (end - start) * (i + 1) // segments
            x0, y0 = angle_xy(cx, cy, radius, a0)
            x1, y1 = angle_xy(cx, cy, radius, a1)
            triangles.append([[cx, cy, z], [x0, y0, z], [x1, y1, z]])
    guard_triangle_budget(triangles, "sectors_xy")
    return pack_triangles_xyz(triangles)


def pack_arc_bands_xy(arcs):
    triangles = []
    for arc in arcs:
        if not isinstance(arc, dict):
            raise SystemExit("scene arc_bands_xy entries must be objects")
        cx, cy = flat_shape_center(arc, "arc_bands_xy")
        inner = flat_shape_positive_i32(arc, "arc_bands_xy", "inner_radius", "radius_inner")
        outer = flat_shape_positive_i32(arc, "arc_bands_xy", "outer_radius", "radius_outer")
        if outer <= inner:
            raise SystemExit("scene arc_bands_xy outer_radius must be greater than inner_radius")
        start, end = flat_angle_span(arc, "arc_bands_xy")
        segments = flat_shape_segments(arc, "arc_bands_xy", 1, 16, 96)
        z = flat_xy_z(arc, "arc_bands_xy")
        for i in range(segments):
            a0 = start + (end - start) * i // segments
            a1 = start + (end - start) * (i + 1) // segments
            ox0, oy0 = angle_xy(cx, cy, outer, a0)
            ox1, oy1 = angle_xy(cx, cy, outer, a1)
            ix0, iy0 = angle_xy(cx, cy, inner, a0)
            ix1, iy1 = angle_xy(cx, cy, inner, a1)
            triangles.append([[ox0, oy0, z], [ox1, oy1, z], [ix1, iy1, z]])
            triangles.append([[ox0, oy0, z], [ix1, iy1, z], [ix0, iy0, z]])
    guard_triangle_budget(triangles, "arc_bands_xy")
    return pack_triangles_xyz(triangles)


def rounded_rect_vertex(x0, y0, x1, y1, radius, corner_segments, index):
    points_per_corner = corner_segments + 1
    corner = index // points_per_corner
    step = index - corner * points_per_corner
    if corner == 0:
        cx, cy, start = x1 - radius, y1 - radius, 0
    elif corner == 1:
        cx, cy, start = x0 + radius, y1 - radius, 90000
    elif corner == 2:
        cx, cy, start = x0 + radius, y0 + radius, 180000
    else:
        cx, cy, start = x1 - radius, y0 + radius, 270000
    angle = start + 90000 * step // corner_segments
    return angle_xy(cx, cy, radius, angle)


def pack_rounded_rects_xy(rects):
    triangles = []
    for rect in rects:
        x0, y0, x1, y1, z = flat_xy_rect_bounds(rect, "rounded_rects_xy")
        radius = flat_shape_positive_i32(rect, "rounded_rects_xy", "radius", "corner_radius")
        if radius * 2 > x1 - x0 or radius * 2 > y1 - y0:
            raise SystemExit("scene rounded_rects_xy radius must fit inside bounds")
        label = "corner_segments" if "corner_segments" in rect else "segments"
        corner_segments = flat_shape_segments(rect, "rounded_rects_xy", 1, 4, 24, label)
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2
        total = (corner_segments + 1) * 4
        for i in range(total):
            px0, py0 = rounded_rect_vertex(x0, y0, x1, y1, radius, corner_segments, i)
            px1, py1 = rounded_rect_vertex(x0, y0, x1, y1, radius, corner_segments, (i + 1) % total)
            triangles.append([[cx, cy, z], [px0, py0, z], [px1, py1, z]])
    guard_triangle_budget(triangles, "rounded_rects_xy")
    return pack_triangles_xyz(triangles)
