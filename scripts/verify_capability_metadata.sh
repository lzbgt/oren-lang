#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
meta_out="build/tmp/meta_capabilities_src_${ts}.json"
pkg_out="build/tmp/capability_manifest_policy_meta_${ts}.json"
log="build/logs/verify_capability_metadata_${ts}.log"

{
  echo "writing $meta_out"
  ./oren meta tests/fixtures/meta_capabilities_src.oren -o "$meta_out"
  echo "writing $pkg_out"
  ./oren meta tests/fixtures/capability_manifest_policy_src.oren -o "$pkg_out"

  python3 - "$meta_out" "$pkg_out" <<'PY'
import json
import sys

src_path, pkg_path = sys.argv[1:3]

def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

data = load(src_path)

manifest = data.get("capabilities")
if not isinstance(manifest, dict):
    raise SystemExit("missing top-level capabilities object")

if manifest.get("version") != 1:
    raise SystemExit(f"unexpected capability manifest version: {manifest.get('version')!r}")

package = data.get("package")
expected_package = {
    "version": 1,
    "declared": False,
    "runtime_profile": None,
    "cap_allow_domains": [],
    "source_required_domains": ["FS", "TIME", "RNG"],
    "dependency_domain_union": ["FS", "TIME", "RNG"],
    "dependency_domain_union_status": "source_attrs_only",
    "budgets": {"version": 1, "declared": False},
}
if package != expected_package:
    raise SystemExit(f"unexpected package manifest: {package!r}")

required = manifest.get("required_domains")
if required != ["FS", "TIME", "RNG"]:
    raise SystemExit(f"unexpected required_domains: {required!r}")

functions = manifest.get("functions")
if not isinstance(functions, list):
    raise SystemExit("capabilities.functions must be a list")

by_name = {}
for item in functions:
    if not isinstance(item, dict):
        raise SystemExit(f"capabilities.functions entry is not an object: {item!r}")
    by_name[item.get("name")] = item.get("domains")

expected = {
    "read_fs": ["FS"],
    "timed_random": ["TIME", "RNG"],
}
if by_name != expected:
    raise SystemExit(f"unexpected capability function manifest: {by_name!r}")

raw_functions = {item.get("name"): item for item in data.get("functions", [])}
read_fs_attrs = raw_functions.get("read_fs", {}).get("attrs", [])
if not any(a.get("name") == "cap.requires" for a in read_fs_attrs):
    raise SystemExit("raw function attrs lost cap.requires entry for read_fs")

pkg = load(pkg_path)
pkg_package = pkg.get("package")
expected_pkg_package = {
    "version": 1,
    "declared": True,
    "runtime_profile": "capsule",
    "cap_allow_domains": ["ENV", "FS"],
    "source_required_domains": ["ENV"],
    "dependency_domain_union": ["ENV"],
    "dependency_domain_union_status": "source_attrs_only",
    "budgets": {
        "version": 1,
        "declared": True,
        "cpu_ms": 10,
        "heap_bytes": 4096,
    },
}
if pkg_package != expected_pkg_package:
    raise SystemExit(f"unexpected declared package manifest: {pkg_package!r}")

print("capability metadata JSON verified")
PY

  echo "capability metadata verify OK"
} >"$log" 2>&1 || {
  cat "$log" >&2
  exit 1
}

cat "$log"
