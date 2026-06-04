#!/usr/bin/env bash
set -euo pipefail

base_url="${OBC_STORE_PUBLIC_BASE_URL:-https://store.hubstack.cn}"
require_release_ready="${OBC_STORE_LIVE_REQUIRE_RELEASE_READY:-0}"

python3 - "$base_url" "$require_release_ready" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base_url = sys.argv[1].rstrip("/")
require_release_ready = sys.argv[2] == "1"
warnings = []


def fetch(path, *, want_json=True, required=True):
    url = f"{base_url}{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "oren-obc-store-live-verify/1"})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = resp.read()
            if resp.status < 200 or resp.status >= 300:
                raise RuntimeError(f"{url} returned HTTP {resp.status}")
            if want_json:
                return json.loads(data.decode("utf-8"))
            return data
    except Exception as exc:
        if required:
            raise RuntimeError(f"required endpoint failed: {url}: {exc}") from exc
        warnings.append(f"{path}: {exc}")
        return None


def check_health(path):
    doc = fetch(path)
    if doc.get("schema") != "oren.obc.store.index.v0" or doc.get("status") != "ok" or doc.get("service") != "obc-store":
        raise RuntimeError(f"{path} returned unexpected health payload: {doc}")


check_health("/healthz")
check_health("/api/v0/health")

index = fetch("/api/v0/index.json")
if index.get("schema") != "oren.obc.store.index.v0":
    raise RuntimeError(f"index schema mismatch: {index.get('schema')!r}")
packages = index.get("packages")
if not isinstance(packages, list) or not packages:
    raise RuntimeError("public index has no packages")
ids = {pkg.get("id") for pkg in packages if isinstance(pkg, dict)}
for want in ("oren-labs/science-calculator", "oren-labs/ui-card-demo", "oren-labs/scene3d-asset-demo"):
    if want not in ids:
        raise RuntimeError(f"public index missing demo package {want}")

fetch("/api/v0/index.json.sig", want_json=False, required=False)
fetch("/api/v0/trust/bundle.json", required=False)
update = fetch("/api/v0/packages/oren-labs/scene3d-asset-demo/update?current_version=0.0.0", required=False)
if update is not None:
    if update.get("schema") != "oren.obc.package.update.v0" or not update.get("update_available"):
        warnings.append(f"/api/v0/packages/.../update returned unexpected payload: {update}")

if warnings:
    print("OBC store live route OK with release-readiness warnings:")
    for item in warnings:
        print(f"  - {item}")
    if require_release_ready:
        raise SystemExit(1)
else:
    print("OBC store live route release-ready")
print(f"OBC store live route smoke OK: {base_url}")
PY
