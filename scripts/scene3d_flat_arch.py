"""Flat architectural mesh packers for OS3D01 package authoring."""

try:
    from scene3d_flat_curves import flat_xy_pair, pack_triangles_xyz, round_half_away
except ModuleNotFoundError:
    from scripts.scene3d_flat_curves import flat_xy_pair, pack_triangles_xyz, round_half_away


def required_i32(item, key, primary, fallback=None, label=None):
    if primary in item:
        value = item[primary]
    elif fallback is not None and fallback in item:
        value = item[fallback]
    else:
        raise SystemExit(f"scene {key} {label or primary} must be i32")
    try:
        return int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} {label or primary} must be i32")


def positive_i32(item, key, primary, fallback=None, default=None, label=None):
    if primary in item:
        value = item[primary]
    elif fallback is not None and fallback in item:
        value = item[fallback]
    else:
        value = default
    try:
        value = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"scene {key} {label or primary} must be positive i32")
    if value <= 0:
        raise SystemExit(f"scene {key} {label or primary} must be positive i32")
    return value


def xy_points(item, key, minimum, maximum, names=("points", "points_xy")):
    points = None
    for name in names:
        if item.get(name) is not None:
            points = item[name]
            break
    if not isinstance(points, list) or len(points) < minimum or len(points) > maximum:
        raise SystemExit(f"scene {key} points must contain {minimum}..{maximum} [x,y] entries")
    return [flat_xy_pair(point, key, "point") for point in points]


def segment_points(item, key, label):
    p0 = item.get("from", item.get("start"))
    p1 = item.get("to", item.get("end"))
    x0, y0 = flat_xy_pair(p0, key, f"{label} from")
    x1, y1 = flat_xy_pair(p1, key, f"{label} to")
    if x0 == x1 and y0 == y1:
        raise SystemExit(f"scene {key} {label} must be nonzero")
    return x0, y0, x1, y1


def line_width(item, key, label):
    return positive_i32(item, key, "width", "width_milli", 1, label)


def line_offset(dx, dy, width, key):
    length = (float(dx) * float(dx) + float(dy) * float(dy)) ** 0.5
    if length <= 0.0:
        raise SystemExit(f"scene {key} line segment must be nonzero")
    scale = float(width) * 0.5 / length
    ox = round_half_away((0.0 - float(dy)) * scale)
    oy = round_half_away(float(dx) * scale)
    if ox == 0 and oy == 0:
        raise SystemExit(f"scene {key} width rounds to zero")
    return ox, oy


def interp_i32(a, b, step, steps):
    return round_half_away(float(a) + (float(b - a) * float(step) / float(steps)))


def guard_budget(triangles, key):
    if len(triangles) > 4096:
        raise SystemExit(f"scene {key} exceed mesh3d triangle budget")


def box_triangles(x0, y0, z0, x1, y1, z1):
    return [
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


def curb_segment_triangles(p0, p1, width, z0, z1, key):
    ox, oy = line_offset(p1[0] - p0[0], p1[1] - p0[1], width, key)
    l0x, l0y = p0[0] + ox, p0[1] + oy
    l1x, l1y = p1[0] + ox, p1[1] + oy
    r1x, r1y = p1[0] - ox, p1[1] - oy
    r0x, r0y = p0[0] - ox, p0[1] - oy
    return [
        [[l0x, l0y, z1], [l1x, l1y, z1], [r1x, r1y, z1]],
        [[l0x, l0y, z1], [r1x, r1y, z1], [r0x, r0y, z1]],
        [[l0x, l0y, z0], [r1x, r1y, z0], [l1x, l1y, z0]],
        [[l0x, l0y, z0], [r0x, r0y, z0], [r1x, r1y, z0]],
        [[l0x, l0y, z0], [l1x, l1y, z0], [l1x, l1y, z1]],
        [[l0x, l0y, z0], [l1x, l1y, z1], [l0x, l0y, z1]],
        [[r0x, r0y, z0], [r1x, r1y, z1], [r1x, r1y, z0]],
        [[r0x, r0y, z0], [r0x, r0y, z1], [r1x, r1y, z1]],
        [[l0x, l0y, z0], [l0x, l0y, z1], [r0x, r0y, z1]],
        [[l0x, l0y, z0], [r0x, r0y, z1], [r0x, r0y, z0]],
        [[l1x, l1y, z0], [r1x, r1y, z1], [l1x, l1y, z1]],
        [[l1x, l1y, z0], [r1x, r1y, z0], [r1x, r1y, z1]],
    ]


def post_triangles(point, width, z0, z1):
    half = width // 2
    x0 = point[0] - half
    x1 = point[0] + (width - half)
    y0 = point[1] - half
    y1 = point[1] + (width - half)
    return box_triangles(x0, y0, z0, x1, y1, z1)


def pack_walls_xy(walls):
    triangles = []
    for wall in walls:
        if not isinstance(wall, dict):
            raise SystemExit("scene walls_xy entries must be objects")
        points = xy_points(wall, "walls_xy", 2, 128)
        z0 = required_i32(wall, "walls_xy", "z_min", "min_z")
        z1 = required_i32(wall, "walls_xy", "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene walls_xy z_max must be greater than z_min")
        for i in range(1, len(points)):
            p0, p1 = points[i - 1], points[i]
            if p0 == p1:
                raise SystemExit("scene walls_xy segment must be nonzero")
            triangles.append([[p0[0], p0[1], z0], [p1[0], p1[1], z0], [p1[0], p1[1], z1]])
            triangles.append([[p0[0], p0[1], z0], [p1[0], p1[1], z1], [p0[0], p0[1], z1]])
    guard_budget(triangles, "walls_xy")
    return pack_triangles_xyz(triangles)


def pack_rooms_xy(rooms):
    triangles = []
    for room in rooms:
        if not isinstance(room, dict):
            raise SystemExit("scene rooms_xy entries must be objects")
        points = xy_points(room, "rooms_xy", 3, 128)
        z0 = required_i32(room, "rooms_xy", "z_min", "min_z")
        z1 = required_i32(room, "rooms_xy", "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene rooms_xy z_max must be greater than z_min")
        for i, point in enumerate(points):
            nxt = points[(i + 1) % len(points)]
            if point == nxt:
                raise SystemExit("scene rooms_xy edge must be nonzero")
        p0 = points[0]
        for i in range(1, len(points) - 1):
            p1, p2 = points[i], points[i + 1]
            triangles.append([[p0[0], p0[1], z0], [p2[0], p2[1], z0], [p1[0], p1[1], z0]])
            triangles.append([[p0[0], p0[1], z1], [p1[0], p1[1], z1], [p2[0], p2[1], z1]])
        for i, point in enumerate(points):
            nxt = points[(i + 1) % len(points)]
            triangles.append([[point[0], point[1], z0], [nxt[0], nxt[1], z0], [nxt[0], nxt[1], z1]])
            triangles.append([[point[0], point[1], z0], [nxt[0], nxt[1], z1], [point[0], point[1], z1]])
    guard_budget(triangles, "rooms_xy")
    return pack_triangles_xyz(triangles)


def ramp_corners(item, key, label):
    x0, y0, x1, y1 = segment_points(item, key, label)
    width = line_width(item, key, label)
    ox, oy = line_offset(x1 - x0, y1 - y0, width, key)
    return x0 + ox, y0 + oy, x1 + ox, y1 + oy, x1 - ox, y1 - oy, x0 - ox, y0 - oy


def pack_ramps_xy(ramps):
    triangles = []
    for ramp in ramps:
        if not isinstance(ramp, dict):
            raise SystemExit("scene ramps_xy entries must be objects")
        l0x, l0y, l1x, l1y, r1x, r1y, r0x, r0y = ramp_corners(ramp, "ramps_xy", "ramp")
        z0 = required_i32(ramp, "ramps_xy", "z_from", "start_z")
        z1 = required_i32(ramp, "ramps_xy", "z_to", "end_z")
        triangles.append([[l0x, l0y, z0], [l1x, l1y, z1], [r1x, r1y, z1]])
        triangles.append([[l0x, l0y, z0], [r1x, r1y, z1], [r0x, r0y, z0]])
    guard_budget(triangles, "ramps_xy")
    return pack_triangles_xyz(triangles)


def pack_solid_ramps_xy(ramps):
    triangles = []
    for ramp in ramps:
        if not isinstance(ramp, dict):
            raise SystemExit("scene solid_ramps_xy entries must be objects")
        l0x, l0y, l1x, l1y, r1x, r1y, r0x, r0y = ramp_corners(ramp, "solid_ramps_xy", "solid ramp")
        zb = required_i32(ramp, "solid_ramps_xy", "z_base", "base_z")
        z0 = required_i32(ramp, "solid_ramps_xy", "z_from", "start_z")
        z1 = required_i32(ramp, "solid_ramps_xy", "z_to", "end_z")
        if z0 <= zb or z1 <= zb:
            raise SystemExit("scene solid_ramps_xy top z must be above z_base")
        if z0 == z1:
            raise SystemExit("scene solid_ramps_xy z_to must differ from z_from")
        triangles.extend([
            [[l0x, l0y, z0], [l1x, l1y, z1], [r1x, r1y, z1]],
            [[l0x, l0y, z0], [r1x, r1y, z1], [r0x, r0y, z0]],
            [[l0x, l0y, zb], [r1x, r1y, zb], [l1x, l1y, zb]],
            [[l0x, l0y, zb], [r0x, r0y, zb], [r1x, r1y, zb]],
            [[l0x, l0y, zb], [l1x, l1y, zb], [l1x, l1y, z1]],
            [[l0x, l0y, zb], [l1x, l1y, z1], [l0x, l0y, z0]],
            [[r0x, r0y, zb], [r1x, r1y, z1], [r1x, r1y, zb]],
            [[r0x, r0y, zb], [r0x, r0y, z0], [r1x, r1y, z1]],
            [[l0x, l0y, zb], [l0x, l0y, z0], [r0x, r0y, z0]],
            [[l0x, l0y, zb], [r0x, r0y, z0], [r0x, r0y, zb]],
            [[l1x, l1y, zb], [r1x, r1y, z1], [l1x, l1y, z1]],
            [[l1x, l1y, zb], [r1x, r1y, zb], [r1x, r1y, z1]],
        ])
    guard_budget(triangles, "solid_ramps_xy")
    return pack_triangles_xyz(triangles)


def pack_stairs_xy(stairs):
    triangles = []
    for stair in stairs:
        if not isinstance(stair, dict):
            raise SystemExit("scene stairs_xy entries must be objects")
        x0, y0, x1, y1 = segment_points(stair, "stairs_xy", "stair run")
        width = line_width(stair, "stairs_xy", "stair")
        ox, oy = line_offset(x1 - x0, y1 - y0, width, "stairs_xy")
        z0 = required_i32(stair, "stairs_xy", "z_from", "start_z")
        z1 = required_i32(stair, "stairs_xy", "z_to", "end_z")
        if z0 == z1:
            raise SystemExit("scene stairs_xy z_to must differ from z_from")
        steps = positive_i32(stair, "stairs_xy", "steps", "count", None, "steps")
        if steps > 128:
            raise SystemExit("scene stairs_xy steps must be 1..128")
        for step in range(1, steps + 1):
            px0 = interp_i32(x0, x1, step - 1, steps)
            py0 = interp_i32(y0, y1, step - 1, steps)
            px1 = interp_i32(x0, x1, step, steps)
            py1 = interp_i32(y0, y1, step, steps)
            sz0 = interp_i32(z0, z1, step - 1, steps)
            sz1 = interp_i32(z0, z1, step, steps)
            lx0, ly0, rx0, ry0 = px0 + ox, py0 + oy, px0 - ox, py0 - oy
            lx1, ly1, rx1, ry1 = px1 + ox, py1 + oy, px1 - ox, py1 - oy
            triangles.extend([
                [[lx0, ly0, sz0], [rx0, ry0, sz0], [rx0, ry0, sz1]],
                [[lx0, ly0, sz0], [rx0, ry0, sz1], [lx0, ly0, sz1]],
                [[lx0, ly0, sz1], [lx1, ly1, sz1], [rx1, ry1, sz1]],
                [[lx0, ly0, sz1], [rx1, ry1, sz1], [rx0, ry0, sz1]],
            ])
    guard_budget(triangles, "stairs_xy")
    return pack_triangles_xyz(triangles)


def pack_gable_roofs_xy(roofs):
    triangles = []
    for roof in roofs:
        if not isinstance(roof, dict):
            raise SystemExit("scene gable_roofs_xy entries must be objects")
        x0, y0, x1, y1 = segment_points(roof, "gable_roofs_xy", "gable roof ridge")
        width = line_width(roof, "gable_roofs_xy", "gable roof")
        ox, oy = line_offset(x1 - x0, y1 - y0, width, "gable_roofs_xy")
        z0 = required_i32(roof, "gable_roofs_xy", "z_eave", "eave_z")
        z1 = required_i32(roof, "gable_roofs_xy", "z_ridge", "ridge_z")
        if z1 <= z0:
            raise SystemExit("scene gable_roofs_xy z_ridge must be greater than z_eave")
        l0x, l0y, l1x, l1y = x0 + ox, y0 + oy, x1 + ox, y1 + oy
        r0x, r0y, r1x, r1y = x0 - ox, y0 - oy, x1 - ox, y1 - oy
        triangles.extend([
            [[l0x, l0y, z0], [l1x, l1y, z0], [x1, y1, z1]],
            [[l0x, l0y, z0], [x1, y1, z1], [x0, y0, z1]],
            [[r0x, r0y, z0], [x0, y0, z1], [x1, y1, z1]],
            [[r0x, r0y, z0], [x1, y1, z1], [r1x, r1y, z0]],
            [[l0x, l0y, z0], [r0x, r0y, z0], [x0, y0, z1]],
            [[l1x, l1y, z0], [x1, y1, z1], [r1x, r1y, z0]],
        ])
    guard_budget(triangles, "gable_roofs_xy")
    return pack_triangles_xyz(triangles)


def pyramid_apex(pyr):
    if pyr.get("apex") is not None:
        apex = pyr["apex"]
        if not isinstance(apex, list) or len(apex) != 3:
            raise SystemExit("scene pyramids_xy apex must be [x,y,z]")
        return int(apex[0]), int(apex[1]), int(apex[2])
    xy = pyr.get("apex_xy", pyr.get("center"))
    ax, ay = flat_xy_pair(xy, "pyramids_xy", "apex_xy")
    return ax, ay, required_i32(pyr, "pyramids_xy", "z_apex", "apex_z")


def pack_pyramids_xy(pyramids):
    triangles = []
    for pyr in pyramids:
        if not isinstance(pyr, dict):
            raise SystemExit("scene pyramids_xy entries must be objects")
        points = xy_points(pyr, "pyramids_xy", 3, 128)
        z_base = required_i32(pyr, "pyramids_xy", "z_base", "base_z")
        apex = pyramid_apex(pyr)
        if apex[2] == z_base:
            raise SystemExit("scene pyramids_xy apex z must differ from z_base")
        for i, point in enumerate(points):
            if point == points[(i + 1) % len(points)]:
                raise SystemExit("scene pyramids_xy edge must be nonzero")
        p0 = points[0]
        for i in range(1, len(points) - 1):
            p1, p2 = points[i], points[i + 1]
            triangles.append([[p0[0], p0[1], z_base], [p2[0], p2[1], z_base], [p1[0], p1[1], z_base]])
        for i, point in enumerate(points):
            nxt = points[(i + 1) % len(points)]
            triangles.append([[point[0], point[1], z_base], [nxt[0], nxt[1], z_base], [apex[0], apex[1], apex[2]]])
    guard_budget(triangles, "pyramids_xy")
    return pack_triangles_xyz(triangles)


def pack_posts_xy(posts):
    triangles = []
    for post in posts:
        if not isinstance(post, dict):
            raise SystemExit("scene posts_xy entries must be objects")
        points = xy_points(post, "posts_xy", 1, 512, ("points", "points_xy", "centers", "centers_xy"))
        width = positive_i32(post, "posts_xy", "width", "width_milli", None, "post width")
        z0 = required_i32(post, "posts_xy", "z_min", "min_z")
        z1 = required_i32(post, "posts_xy", "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene posts_xy z_max must be greater than z_min")
        for point in points:
            triangles.extend(post_triangles(point, width, z0, z1))
    guard_budget(triangles, "posts_xy")
    return pack_triangles_xyz(triangles)


def pack_curbs_xy(curbs):
    triangles = []
    for curb in curbs:
        if not isinstance(curb, dict):
            raise SystemExit("scene curbs_xy entries must be objects")
        points = xy_points(curb, "curbs_xy", 2, 128)
        width = line_width(curb, "curbs_xy", "curb")
        z0 = required_i32(curb, "curbs_xy", "z_min", "min_z")
        z1 = required_i32(curb, "curbs_xy", "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene curbs_xy z_max must be greater than z_min")
        for i in range(1, len(points)):
            if points[i - 1] == points[i]:
                raise SystemExit("scene curbs_xy segment must be nonzero")
            triangles.extend(curb_segment_triangles(points[i - 1], points[i], width, z0, z1, "curbs_xy"))
    guard_budget(triangles, "curbs_xy")
    return pack_triangles_xyz(triangles)


def fence_width(item, rail, primary, fallback, label):
    if rail is not None and rail.get("width") is not None:
        return positive_i32(rail, "fences_xy", "width", "width_milli", None, label)
    if rail is not None and rail.get("width_milli") is not None:
        return positive_i32(rail, "fences_xy", "width", "width_milli", None, label)
    if item.get(primary) is not None or item.get(fallback) is not None:
        return positive_i32(item, "fences_xy", primary, fallback, None, label)
    return positive_i32(item, "fences_xy", "width", None, 1, label)


def fence_z(item, rail, primary, fallback, default_value, label):
    if rail is not None:
        if primary in rail:
            return required_i32(rail, "fences_xy", primary, None, label)
        if fallback in rail:
            return required_i32(rail, "fences_xy", fallback, None, label)
    if primary in item:
        return required_i32(item, "fences_xy", primary, None, label)
    if fallback in item:
        return required_i32(item, "fences_xy", fallback, None, label)
    return default_value


def fence_rails(fence):
    rails = fence.get("rails")
    if rails is None:
        return [None]
    if not isinstance(rails, list) or len(rails) < 1 or len(rails) > 8:
        raise SystemExit("scene fences_xy rails must contain 1..8 entries")
    for rail in rails:
        if not isinstance(rail, dict):
            raise SystemExit("scene fences_xy rail must be object")
    return rails


def pack_fences_xy(fences):
    triangles = []
    for fence in fences:
        if not isinstance(fence, dict):
            raise SystemExit("scene fences_xy entries must be objects")
        points = xy_points(fence, "fences_xy", 2, 128)
        post_width = positive_i32(fence, "fences_xy", "post_width", "post_width_milli", None, "post width")
        z0 = required_i32(fence, "fences_xy", "z_min", "min_z")
        z1 = required_i32(fence, "fences_xy", "z_max", "max_z")
        if z1 <= z0:
            raise SystemExit("scene fences_xy z_max must be greater than z_min")
        rails = fence_rails(fence)
        for rail in rails:
            rw = fence_width(fence, rail, "rail_width", "rail_width_milli", "rail width")
            rz0 = fence_z(fence, rail, "z_min" if rail is not None else "rail_z_min", "min_z" if rail is not None else "rail_min_z", z0, "rail z_min")
            rz1 = fence_z(fence, rail, "z_max" if rail is not None else "rail_z_max", "max_z" if rail is not None else "rail_max_z", z1, "rail z_max")
            if rw <= 0 or rz1 <= rz0 or rz0 < z0 or rz1 > z1:
                raise SystemExit("scene fences_xy rail z range must be inside z_min..z_max")
        for i, point in enumerate(points):
            triangles.extend(post_triangles(point, post_width, z0, z1))
            if i == 0:
                continue
            if points[i - 1] == point:
                raise SystemExit("scene fences_xy segment must be nonzero")
            for rail in rails:
                rw = fence_width(fence, rail, "rail_width", "rail_width_milli", "rail width")
                rz0 = fence_z(fence, rail, "z_min" if rail is not None else "rail_z_min", "min_z" if rail is not None else "rail_min_z", z0, "rail z_min")
                rz1 = fence_z(fence, rail, "z_max" if rail is not None else "rail_z_max", "max_z" if rail is not None else "rail_max_z", z1, "rail z_max")
                triangles.extend(curb_segment_triangles(points[i - 1], point, rw, rz0, rz1, "fences_xy"))
    guard_budget(triangles, "fences_xy")
    return pack_triangles_xyz(triangles)
