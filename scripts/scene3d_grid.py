"""Grid and flat-indexed mesh packers for OS3D01 package authoring."""

try:
    from scene3d_flat_curves import flat_xy_pair, pack_triangles_xyz, pack_vertices_xyz
except ModuleNotFoundError:
    from scripts.scene3d_flat_curves import flat_xy_pair, pack_triangles_xyz, pack_vertices_xyz


def pack_vertices_xy(points):
    if not isinstance(points, list):
        raise SystemExit("scene vertices_xy must be list")
    vertices = []
    for point in points:
        x, y = flat_xy_pair(point, "vertices_xy", "vertex")
        vertices.append([x, y, 0])
    return pack_vertices_xyz(vertices)


def positive_pair(value, key, label):
    x, y = flat_xy_pair(value, key, label)
    if x <= 0 or y <= 0:
        raise SystemExit(f"scene {key} {label} must contain positive i32")
    return x, y


def heightfield_origin(item):
    origin = item.get("origin", item.get("origin_xy", [0, 0]))
    return flat_xy_pair(origin, "heightfields_xy", "origin")


def heightfield_step(item):
    step = item.get("step_xy", item.get("cell_size_xy"))
    if step is not None:
        return positive_pair(step, "heightfields_xy", "step_xy")
    cell = item.get("cell_size", item.get("step", 1))
    try:
        cell = int(cell)
    except (TypeError, ValueError):
        raise SystemExit("scene heightfields_xy cell_size must be positive i32")
    if cell <= 0:
        raise SystemExit("scene heightfields_xy cell_size must be positive i32")
    return cell, cell


def heightfield_rows(item):
    rows = item.get("z_values", item.get("heights"))
    if not isinstance(rows, list) or len(rows) < 2 or len(rows) > 31:
        raise SystemExit("scene heightfields_xy rows must be 2..31")
    if not isinstance(rows[0], list) or len(rows[0]) < 2 or len(rows[0]) > 31:
        raise SystemExit("scene heightfields_xy columns must be 2..31")
    width = len(rows[0])
    out = []
    for row in rows:
        if not isinstance(row, list) or len(row) != width:
            raise SystemExit("scene heightfields_xy rows must have equal width")
        out_row = []
        for value in row:
            try:
                out_row.append(int(value))
            except (TypeError, ValueError):
                raise SystemExit("scene heightfields_xy heights must be i32")
        out.append(out_row)
    return out


def pack_heightfields_xy(heightfields):
    triangles = []
    for item in heightfields:
        if not isinstance(item, dict):
            raise SystemExit("scene heightfields_xy entries must be objects")
        ox, oy = heightfield_origin(item)
        sx, sy = heightfield_step(item)
        rows = heightfield_rows(item)
        for r in range(len(rows) - 1):
            y0 = oy + r * sy
            y1 = y0 + sy
            for c in range(len(rows[0]) - 1):
                x0 = ox + c * sx
                x1 = x0 + sx
                z00 = rows[r][c]
                z10 = rows[r][c + 1]
                z01 = rows[r + 1][c]
                z11 = rows[r + 1][c + 1]
                triangles.append([[x0, y0, z00], [x1, y0, z10], [x1, y1, z11]])
                triangles.append([[x0, y0, z00], [x1, y1, z11], [x0, y1, z01]])
        if len(triangles) > 1820:
            raise SystemExit("scene heightfields_xy exceed mesh3d triangle budget")
    return pack_triangles_xyz(triangles)


def surface_rows(item):
    rows = item.get("vertices", item.get("vertices_xyz", item.get("points", item.get("points_xyz"))))
    if not isinstance(rows, list) or len(rows) < 2 or len(rows) > 31:
        raise SystemExit("scene surfaces_xyz rows must be 2..31")
    if not isinstance(rows[0], list) or len(rows[0]) < 2 or len(rows[0]) > 31:
        raise SystemExit("scene surfaces_xyz columns must be 2..31")
    width = len(rows[0])
    out = []
    for row in rows:
        if not isinstance(row, list) or len(row) != width:
            raise SystemExit("scene surfaces_xyz rows must have equal width")
        out_row = []
        for point in row:
            if not isinstance(point, list) or len(point) != 3:
                raise SystemExit("scene surfaces_xyz vertex must be [x,y,z]")
            out_row.append([int(point[0]), int(point[1]), int(point[2])])
        out.append(out_row)
    return out


def pack_surfaces_xyz(surfaces):
    triangles = []
    for item in surfaces:
        if not isinstance(item, dict):
            raise SystemExit("scene surfaces_xyz entries must be objects")
        rows = surface_rows(item)
        for r in range(len(rows) - 1):
            for c in range(len(rows[0]) - 1):
                p00 = rows[r][c]
                p10 = rows[r][c + 1]
                p01 = rows[r + 1][c]
                p11 = rows[r + 1][c + 1]
                triangles.append([p00, p10, p11])
                triangles.append([p00, p11, p01])
        if len(triangles) > 1820:
            raise SystemExit("scene surfaces_xyz exceed mesh3d triangle budget")
    return pack_triangles_xyz(triangles)
