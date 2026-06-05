#!/usr/bin/env bash
set -euo pipefail

base_url="${OBC_STORE_PUBLIC_BASE_URL:-https://store.hubstack.cn}"
require_release_ready="${OBC_STORE_LIVE_REQUIRE_RELEASE_READY:-0}"
admin_username="${OBC_STORE_LIVE_ADMIN_USERNAME:-${OBC_STORE_ADMIN_USERNAME:-admin}}"
admin_password="${OBC_STORE_LIVE_ADMIN_PASSWORD:-${OBC_STORE_ADMIN_PASSWORD:-}}"
admin_bearer_token="${OBC_STORE_LIVE_ADMIN_BEARER_TOKEN:-${OBC_STORE_ADMIN_BEARER_TOKEN:-}}"
require_ops_status="${OBC_STORE_LIVE_REQUIRE_OPS_STATUS:-0}"

python3 - "$base_url" "$require_release_ready" "$admin_username" "$admin_password" "$admin_bearer_token" "$require_ops_status" <<'PY'
import base64
import json
import sys
import urllib.error
import urllib.request

base_url = sys.argv[1].rstrip("/")
require_release_ready = sys.argv[2] == "1"
admin_username = sys.argv[3]
admin_password = sys.argv[4]
admin_bearer_token = sys.argv[5]
require_ops_status = sys.argv[6] == "1"
warnings = []
health_build_commits = set()


def fetch(path, *, want_json=True, required=True):
    url = f"{base_url}{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "oren-obc-store-live-verify/1"})
    return fetch_request(req, url, want_json=want_json, required=required, path=path)


def fetch_request(req, url, *, want_json=True, required=True, path=""):
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
        warnings.append(f"{path or url}: {exc}")
        return None


def check_health(path):
    doc = fetch(path)
    if doc.get("schema") != "oren.obc.store.index.v0" or doc.get("status") != "ok" or doc.get("service") != "obc-store":
        raise RuntimeError(f"{path} returned unexpected health payload: {doc}")
    commit = doc.get("build_commit")
    if not isinstance(commit, str) or not commit:
        warnings.append(f"{path}: missing build_commit; live service may be an older unstamped binary")
    else:
        health_build_commits.add(commit)


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

if admin_bearer_token or admin_password:
    ops_url = f"{base_url}/api/v0/ops/status"
    req = urllib.request.Request(ops_url, headers={"User-Agent": "oren-obc-store-live-verify/1"})
    if admin_bearer_token:
        req.add_header("Authorization", "Bearer " + admin_bearer_token)
    else:
        raw = f"{admin_username}:{admin_password}".encode("utf-8")
        req.add_header("Authorization", "Basic " + base64.b64encode(raw).decode("ascii"))
    status = fetch_request(req, ops_url, required=True, path="/api/v0/ops/status")
    if status.get("service") != "obc-store" or status.get("admin_auth_configured") is not True:
        raise RuntimeError(f"operator status returned unexpected payload: {status}")
    status_commit = status.get("build_commit")
    if not isinstance(status_commit, str) or not status_commit:
        raise RuntimeError(f"operator status missing build_commit: {status}")
    if health_build_commits and status_commit not in health_build_commits:
        raise RuntimeError(f"operator status build {status_commit!r} does not match public health builds {sorted(health_build_commits)!r}")
    if status.get("data_dir_writable") is not True:
        raise RuntimeError(f"operator status reports unwritable data dir: {status}")
    if int(status.get("data_dir_file_count") or 0) <= 0 or int(status.get("data_dir_bytes") or 0) <= 0:
        raise RuntimeError(f"operator status storage counters are empty: {status}")
elif require_ops_status:
    raise RuntimeError("OBC_STORE_LIVE_REQUIRE_OPS_STATUS=1 requires OBC_STORE_LIVE_ADMIN_PASSWORD or OBC_STORE_LIVE_ADMIN_BEARER_TOKEN")

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
