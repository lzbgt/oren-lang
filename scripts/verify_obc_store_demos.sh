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
import pathlib
import shutil
import subprocess
import sys
import zipfile

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
        }
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
        if not any(s.get("path") == "assets/source/main.oren" for s in manifest.get("sources", [])):
            raise SystemExit(f"missing source declaration: {bundle_path}")
print(f"OBC store demo packages built under {out_root}")
PY
