#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OREN_COMPILER="${OREN_COMPILER:-./oren}"
AVM_BIN="${AVM_BIN:-./avm}"
SPEC="${SPEC:-examples/obc_store_demos/packages.json}"
OUT_ROOT="${OUT_ROOT:-build/obc-store-demos}"
LOG_DIR="${LOG_DIR:-build/logs}"

mkdir -p "$OUT_ROOT" "$LOG_DIR"

python3 - "$OREN_COMPILER" "$AVM_BIN" "$SPEC" "$OUT_ROOT" "$LOG_DIR" <<'PY'
import json
import hashlib
import importlib.util
import math
import pathlib
import shutil
import struct
import subprocess
import sys
import zipfile
import zlib

compiler, avm, spec_path, out_root, log_dir = sys.argv[1:]
out_root = pathlib.Path(out_root)
log_dir = pathlib.Path(log_dir)
spec = json.loads(pathlib.Path(spec_path).read_text())
scene3d_spec = importlib.util.spec_from_file_location("make_scene3d_bin_v0", "scripts/make_scene3d_bin_v0.py")
scene3d_module = importlib.util.module_from_spec(scene3d_spec)
scene3d_spec.loader.exec_module(scene3d_module)

packages_root = out_root / "packages"
bundles_root = out_root / "bundles"
if packages_root.exists():
    shutil.rmtree(packages_root)
if bundles_root.exists():
    shutil.rmtree(bundles_root)
packages_root.mkdir(parents=True, exist_ok=True)
bundles_root.mkdir(parents=True, exist_ok=True)


def write_deterministic_zip(zip_path, files):
    with zipfile.ZipFile(
        zip_path,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as zf:
        for arcname, path in sorted(files):
            info = zipfile.ZipInfo(arcname)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())


def rgba_png(width, height, pixels):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        off = y * stride
        raw.extend(pixels[off:off + stride])

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def color(hex_color):
    s = hex_color.lstrip("#")
    if len(s) == 6:
        s += "ff"
    return tuple(int(s[i:i + 2], 16) for i in range(0, 8, 2))


def make_canvas(width=640, height=360, bg="#102820"):
    r, g, b, a = color(bg)
    return bytearray([r, g, b, a] * width * height)


def put_px(pixels, width, height, x, y, c):
    if 0 <= x < width and 0 <= y < height:
        off = (y * width + x) * 4
        pixels[off:off + 4] = bytes(c)


def rect(pixels, width, height, x, y, w, h, fill):
    c = color(fill)
    x0 = max(0, x)
    y0 = max(0, y)
    x1 = min(width, x + w)
    y1 = min(height, y + h)
    row = bytes(c) * max(0, x1 - x0)
    for yy in range(y0, y1):
        off = (yy * width + x0) * 4
        pixels[off:off + len(row)] = row


def circle(pixels, width, height, cx, cy, radius, fill):
    c = color(fill)
    rr = radius * radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rr:
                put_px(pixels, width, height, x, y, c)


def line(pixels, width, height, x0, y0, x1, y1, stroke, thickness=1):
    c = color(stroke)
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        for oy in range(-(thickness // 2), thickness // 2 + 1):
            for ox in range(-(thickness // 2), thickness // 2 + 1):
                put_px(pixels, width, height, x0 + ox, y0 + oy, c)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def triangle(pixels, width, height, pts, fill):
    c = color(fill)
    (x0, y0), (x1, y1), (x2, y2) = pts
    min_x = max(0, min(x0, x1, x2))
    max_x = min(width - 1, max(x0, x1, x2))
    min_y = max(0, min(y0, y1, y2))
    max_y = min(height - 1, max(y0, y1, y2))
    area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
    if area == 0:
        return
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            w0 = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)
            w1 = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
            w2 = (x0 - x2) * (y - y2) - (y0 - y2) * (x - x2)
            if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0):
                put_px(pixels, width, height, x, y, c)


def render_demo_preview(name):
    w, h = 640, 360
    pixels = make_canvas(w, h, "#102820")
    rect(pixels, w, h, 0, 0, w, h, "#102820")
    rect(pixels, w, h, 34, 34, 572, 292, "#f5efe0")
    rect(pixels, w, h, 48, 48, 544, 264, "#fffaf0")
    if name == "science-calculator":
        for x in range(76, 560, 48):
            line(pixels, w, h, x, 250, x, 88, "#d7cdbb", 1)
        for y in range(96, 260, 32):
            line(pixels, w, h, 76, y, 560, y, "#d7cdbb", 1)
        pts = []
        for i in range(0, 480):
            x = 76 + i
            t = i / 479.0
            y = 252 - int(145 * (math.sin(t * math.pi * 1.4) * 0.35 + t * 0.65))
            pts.append((x, y))
        for a, b in zip(pts, pts[1:]):
            line(pixels, w, h, a[0], a[1], b[0], b[1], "#146c5b", 3)
        for i, height_bar in enumerate([78, 118, 168]):
            rect(pixels, w, h, 406 + i * 46, 252 - height_bar, 28, height_bar, "#e38b29")
        circle(pixels, w, h, 130, 118, 22, "#36584d")
    elif name == "scene3d-asset-demo":
        rect(pixels, w, h, 76, 76, 488, 236, "#17211f")
        triangle(pixels, w, h, [(165, 260), (344, 74), (490, 260)], "#00ff00")
        triangle(pixels, w, h, [(386, 104), (520, 104), (386, 238)], "#ff0000")
        line(pixels, w, h, 165, 260, 344, 74, "#f5efe0", 2)
        line(pixels, w, h, 344, 74, 490, 260, "#f5efe0", 2)
        line(pixels, w, h, 490, 260, 165, 260, "#f5efe0", 2)
        circle(pixels, w, h, 344, 74, 12, "#e38b29")
    else:
        rect(pixels, w, h, 36, 36, 568, 288, "#102820")
        rect(pixels, w, h, 70, 70, 500, 220, "#f5efe0")
        line(pixels, w, h, 70, 238, 570, 238, "#146c5b", 4)
        circle(pixels, w, h, 494, 124, 54, "#e38b29")
        rect(pixels, w, h, 110, 118, 230, 18, "#102820")
        rect(pixels, w, h, 110, 170, 320, 16, "#36584d")
        rect(pixels, w, h, 110, 198, 250, 12, "#36584d")
    return rgba_png(w, h, pixels)

seen = set()
index_packages = []
for item in spec:
    ident = (item["publisher"], item["name"], item["version"])
    if ident in seen:
        raise SystemExit(f"duplicate demo package: {ident}")
    seen.add(ident)
    source = pathlib.Path(item["source"])
    if not source.is_file():
        raise SystemExit(f"missing source: {source}")

    pkg_dir = packages_root / item["publisher"] / item["name"] / item["version"]
    pkg_dir.mkdir(parents=True, exist_ok=True)
    source_asset = pkg_dir / "assets" / "source" / "main.oren"
    source_asset.parent.mkdir(parents=True, exist_ok=True)
    source_bytes = source.read_bytes()
    source_asset.write_bytes(source_bytes)
    screenshot_asset = pkg_dir / "screenshots" / "preview.png"
    screenshot_asset.parent.mkdir(parents=True, exist_ok=True)
    screenshot_bytes = render_demo_preview(item["name"])
    screenshot_asset.write_bytes(screenshot_bytes)
    extra_assets = []
    for asset in item.get("assets", []):
        asset_source = pathlib.Path(asset["source"])
        asset_path = asset["path"]
        if not asset_source.is_file():
            raise SystemExit(f"missing asset source: {asset_source}")
        if asset_path.startswith("/") or ".." in pathlib.PurePosixPath(asset_path).parts:
            raise SystemExit(f"unsafe asset path: {asset_path}")
        asset_out = pkg_dir / asset_path
        asset_out.parent.mkdir(parents=True, exist_ok=True)
        asset_bytes = asset_source.read_bytes()
        if asset.get("format") == "scene3d_bin_v0":
            asset_bytes = scene3d_module.scene3d_bin_v0(asset_bytes)
        asset_out.write_bytes(asset_bytes)
        extra_assets.append((asset, asset_out, asset_bytes))
    obc_path = pkg_dir / "program.obc"
    build_log = log_dir / f"obc_store_demo_{item['publisher']}_{item['name']}_{item['version']}_build.log"
    run_log = log_dir / f"obc_store_demo_{item['publisher']}_{item['name']}_{item['version']}_run.log"

    with build_log.open("wb") as log:
        subprocess.check_call(
            [compiler, "build", str(source), "--backend", "bytecode", "-o", str(obc_path)],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    run_cmd = [avm, "--deny-by-default", "--allow-domains", item["run_allow_domains"], "--print-run-json"]
    if extra_assets:
        run_cmd.extend([
            "--fs-backend",
            "host",
            "--fs-allow-prefixes",
            "assets/",
            "--fs-mounts-read",
            f"assets/={pkg_dir / 'assets'}/",
        ])
    run_cmd.append(str(obc_path))
    with run_log.open("wb") as log:
        subprocess.check_call(run_cmd, stdout=log, stderr=subprocess.STDOUT)

    obc_sha = hashlib.sha256(obc_path.read_bytes()).hexdigest()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    asset_entries = [
        {
            "path": "assets/source/main.oren",
            "sha256": source_sha,
            "media_type": "text/x-oren",
            "role": "source",
        },
    ]
    for asset, _asset_out, asset_bytes in extra_assets:
        asset_entries.append({
            "path": asset["path"],
            "sha256": hashlib.sha256(asset_bytes).hexdigest(),
            "media_type": asset.get("media_type", "application/octet-stream"),
            "role": asset.get("role", "asset"),
        })

    manifest = {
        "schema": "oren.obc.package.v0",
        "publisher": item["publisher"],
        "name": item["name"],
        "version": item["version"],
        "title": item["title"],
        "summary": item["summary"],
        "entry_obc": "program.obc",
        "obc_sha256": obc_sha,
        "oren_min": "0.0.rolling",
        "avm_abi_min": 8,
        "capabilities": item["capabilities"],
        "tags": item["tags"],
        "assets": asset_entries,
        "sources": [
            {
                "path": "assets/source/main.oren",
                "language": "oren",
                "role": "main",
            }
        ],
        "time_mode": "deterministic",
        "budgets": {
            "gas": 5000000,
            "heap_bytes": 33554432,
            "io_bytes": 1048576,
            "frame_commands": 1024,
        },
    }
    if extra_assets:
        manifest["vfs_mounts"] = [
            {
                "virtual": "assets/",
                "package_path": "assets/",
                "read_only": True,
            }
        ]
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    (pkg_dir / "package.json").write_bytes(manifest_bytes)
    manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
    bundle_path = bundles_root / f"{item['publisher']}__{item['name']}__{item['version']}.obc.zip"
    bundle_files = [
        ("assets/source/main.oren", source_asset),
        ("package.json", pkg_dir / "package.json"),
        ("program.obc", obc_path),
    ]
    for asset, asset_out, _asset_bytes in extra_assets:
        bundle_files.append((asset["path"], asset_out))
    write_deterministic_zip(bundle_path, bundle_files)
    bundle_sha = hashlib.sha256(bundle_path.read_bytes()).hexdigest()
    index_packages.append({
        "id": item["publisher"] + "/" + item["name"],
        "version": item["version"],
        "bundle": f"bundles/{bundle_path.name}",
        "bundle_media_type": "application/vnd.oren.obc.release+zip",
        "bundle_sha256": bundle_sha,
        "manifest": f"packages/{item['publisher']}/{item['name']}/{item['version']}/package.json",
        "manifest_sha256": manifest_sha,
        "tags": item["tags"],
        "min_app": "0.1.0",
    })

index = {
    "schema": "oren.obc.store.index.v0",
    "generated_at": "1970-01-01T00:00:00Z",
    "packages": index_packages,
}
(out_root / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")

for entry in index_packages:
    manifest_path = out_root / entry["manifest"]
    bundle_path = out_root / entry["bundle"]
    if hashlib.sha256(manifest_path.read_bytes()).hexdigest() != entry["manifest_sha256"]:
        raise SystemExit(f"manifest hash mismatch: {manifest_path}")
    if hashlib.sha256(bundle_path.read_bytes()).hexdigest() != entry["bundle_sha256"]:
        raise SystemExit(f"bundle hash mismatch: {bundle_path}")
    with zipfile.ZipFile(bundle_path) as zf:
        names = sorted(zf.namelist())
        manifest = json.loads(zf.read("package.json"))
        expected_names = sorted(["package.json", "program.obc"] + [a["path"] for a in manifest.get("assets", [])])
        if names != expected_names:
            raise SystemExit(f"bad release bundle layout: {bundle_path}: {names}")
        if not any(a.get("role") == "source" and a.get("path") == "assets/source/main.oren" for a in manifest.get("assets", [])):
            raise SystemExit(f"missing source asset declaration: {bundle_path}")
        if any(a.get("role") == "screenshot" for a in manifest.get("assets", [])):
            raise SystemExit(f"screenshot leaked into package assets: {bundle_path}")
        if "screenshots/preview.png" in names:
            raise SystemExit(f"screenshot leaked into release bundle: {bundle_path}")
        if not any(s.get("path") == "assets/source/main.oren" for s in manifest.get("sources", [])):
            raise SystemExit(f"missing source declaration: {bundle_path}")
    screenshot_path = manifest_path.parent / "screenshots" / "preview.png"
    if not screenshot_path.is_file():
        raise SystemExit(f"missing portal screenshot: {screenshot_path}")
print(f"OBC store demo packages built under {out_root}")
PY
