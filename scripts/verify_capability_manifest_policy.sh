#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
meta_out="build/tmp/meta_capabilities_policy_${ts}.json"
c_out="build/tmp/capability_manifest_policy_${ts}"
log="build/logs/verify_capability_manifest_policy_${ts}.log"

cleanup() {
  rm -f "$meta_out" "$meta_out.manifest.json" "$c_out" "$c_out.manifest.json"
}
trap cleanup EXIT

{
  echo "writing metadata manifest policy: $meta_out"
  ./oren meta tests/fixtures/meta_capabilities_src.oren --manifest -o "$meta_out"

  echo "writing C artifact manifest policy: $c_out"
  ./oren build tests/fixtures/capability_manifest_policy_src.oren \
    --backend c \
    --manifest \
    --cap-allow-domains FS,ENV \
    -o "$c_out"

  python3 - "$meta_out.manifest.json" "$c_out.manifest.json" <<'PY'
import json
import sys

# Guard the policy.source_required_domains contract, not only the artifact hash fields.
meta_manifest, c_manifest = sys.argv[1], sys.argv[2]

def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def expect_common(path, data, kind):
    for key in ("version", "kind", "sha256", "size_bytes", "path", "target", "arch", "deterministic", "policy"):
        if key not in data:
            raise SystemExit(f"{path}: missing manifest key {key!r}")
    if data["version"] != 1:
        raise SystemExit(f"{path}: unexpected version {data['version']!r}")
    if data["kind"] != kind:
        raise SystemExit(f"{path}: unexpected kind {data['kind']!r}")
    if not isinstance(data["sha256"], str) or len(data["sha256"]) != 64:
        raise SystemExit(f"{path}: invalid sha256 {data['sha256']!r}")
    if not isinstance(data["size_bytes"], int) or data["size_bytes"] <= 0:
        raise SystemExit(f"{path}: invalid size_bytes {data['size_bytes']!r}")
    if data["deterministic"] is not False:
        raise SystemExit(f"{path}: expected deterministic false")

def expect_policy(path, policy, *, backend, runtime_profile, runtime_path, capsule, cap_allow, required):
    if not isinstance(policy, dict):
        raise SystemExit(f"{path}: policy must be an object")
    expected = {
        "version": 1,
        "backend": backend,
        "runtime_profile": runtime_profile,
        "runtime_path": runtime_path,
        "capsule": capsule,
        "cap_allow_domains": cap_allow,
        "source_required_domains": required,
        "budgets": {"version": 1, "declared": False},
    }
    if policy != expected:
        raise SystemExit(f"{path}: unexpected policy object: {policy!r}")

meta = load(meta_manifest)
expect_common(meta_manifest, meta, "meta")
expect_policy(
    meta_manifest,
    meta["policy"],
    backend="meta",
    runtime_profile="none",
    runtime_path="",
    capsule=False,
    cap_allow=[],
    required=["FS", "TIME", "RNG"],
)

c = load(c_manifest)
expect_common(c_manifest, c, "c")
expect_policy(
    c_manifest,
    c["policy"],
    backend="c",
    runtime_profile="none",
    runtime_path="",
    capsule=False,
    cap_allow=["FS", "ENV"],
    required=["ENV"],
)

print("capability manifest policy JSON verified")
PY

  echo "capability manifest policy verify OK"
} >"$log" 2>&1 || {
  cat "$log" >&2
  exit 1
}

cat "$log"
