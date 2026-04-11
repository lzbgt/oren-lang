#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/logs build/tmp
ts="$(date +%Y%m%d_%H%M%S)"
meta_out="build/tmp/meta_capabilities_policy_${ts}.json"
c_out="build/tmp/capability_manifest_policy_${ts}"
c_mismatch_out="build/tmp/capability_manifest_policy_mismatch_${ts}"
log="build/logs/verify_capability_manifest_policy_${ts}.log"

cleanup() {
  rm -f "$meta_out" "$meta_out.manifest.json" "$c_out" "$c_out.manifest.json" "$c_mismatch_out" "$c_mismatch_out.manifest.json"
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

  echo "writing C artifact manifest policy mismatch observation: $c_mismatch_out"
  ./oren build tests/fixtures/capability_manifest_policy_src.oren \
    --backend c \
    --manifest \
    --cap-allow-domains FS \
    -o "$c_mismatch_out"

  python3 - "$meta_out.manifest.json" "$c_out.manifest.json" "$c_mismatch_out.manifest.json" <<'PY'
import json
import sys

# Guard the policy.source_required_domains contract, not only the artifact hash fields.
meta_manifest, c_manifest, c_mismatch_manifest = sys.argv[1:4]

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
    for key, value in {
        "version": 1,
        "backend": backend,
        "runtime_profile": runtime_profile,
        "runtime_path": runtime_path,
        "capsule": capsule,
        "cap_allow_domains": cap_allow,
        "source_required_domains": required,
        "budgets": {"version": 1, "declared": False},
    }.items():
        if policy.get(key) != value:
            raise SystemExit(f"{path}: unexpected policy.{key}: {policy.get(key)!r}")

def expect_package(path, policy, *, declared, runtime_profile, cap_allow, budgets):
    pkg = policy.get("source_package")
    if not isinstance(pkg, dict):
        raise SystemExit(f"{path}: policy.source_package must be an object")
    expected = {
        "version": 1,
        "declared": declared,
        "runtime_profile": runtime_profile,
        "cap_allow_domains": cap_allow,
        "source_required_domains": policy.get("source_required_domains"),
        "dependency_domain_union": policy.get("source_required_domains"),
        "dependency_domain_union_status": "source_attrs_only",
        "budgets": budgets,
    }
    if pkg != expected:
        raise SystemExit(f"{path}: unexpected source_package: {pkg!r}")

def expect_package_check(path, policy, *, declared, status, runtime_declared, runtime_actual, runtime_status, cap_declared, cap_actual, cap_missing, cap_status, budget_status):
    chk = policy.get("source_package_check")
    if not isinstance(chk, dict):
        raise SystemExit(f"{path}: policy.source_package_check must be an object")
    expected = {
        "version": 1,
        "declared": declared,
        "status": status,
        "runtime_profile": {
            "declared": runtime_declared,
            "actual": runtime_actual,
            "status": runtime_status,
        },
        "cap_allow_domains": {
            "declared": cap_declared,
            "actual": cap_actual,
            "missing": cap_missing,
            "status": cap_status,
        },
        "budget_status": budget_status,
    }
    if chk != expected:
        raise SystemExit(f"{path}: unexpected source_package_check: {chk!r}")

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
expect_package(
    meta_manifest,
    meta["policy"],
    declared=False,
    runtime_profile=None,
    cap_allow=[],
    budgets={"version": 1, "declared": False},
)
expect_package_check(
    meta_manifest,
    meta["policy"],
    declared=False,
    status="not_declared",
    runtime_declared=None,
    runtime_actual="none",
    runtime_status="not_declared",
    cap_declared=[],
    cap_actual=[],
    cap_missing=[],
    cap_status="not_declared",
    budget_status="not_declared",
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
expect_package(
    c_manifest,
    c["policy"],
    declared=True,
    runtime_profile="capsule",
    cap_allow=["ENV", "FS"],
    budgets={"version": 1, "declared": True, "cpu_ms": 10, "heap_bytes": 4096},
)
expect_package_check(
    c_manifest,
    c["policy"],
    declared=True,
    status="mismatch_observed",
    runtime_declared="capsule",
    runtime_actual="none",
    runtime_status="backend_not_runtime_profiled",
    cap_declared=["ENV", "FS"],
    cap_actual=["FS", "ENV"],
    cap_missing=[],
    cap_status="covers",
    budget_status="declared_not_enforced",
)

c_mismatch = load(c_mismatch_manifest)
expect_common(c_mismatch_manifest, c_mismatch, "c")
expect_policy(
    c_mismatch_manifest,
    c_mismatch["policy"],
    backend="c",
    runtime_profile="none",
    runtime_path="",
    capsule=False,
    cap_allow=["FS"],
    required=["ENV"],
)
expect_package(
    c_mismatch_manifest,
    c_mismatch["policy"],
    declared=True,
    runtime_profile="capsule",
    cap_allow=["ENV", "FS"],
    budgets={"version": 1, "declared": True, "cpu_ms": 10, "heap_bytes": 4096},
)
expect_package_check(
    c_mismatch_manifest,
    c_mismatch["policy"],
    declared=True,
    status="mismatch_observed",
    runtime_declared="capsule",
    runtime_actual="none",
    runtime_status="backend_not_runtime_profiled",
    cap_declared=["ENV", "FS"],
    cap_actual=["FS"],
    cap_missing=["ENV"],
    cap_status="missing",
    budget_status="declared_not_enforced",
)

print("capability manifest policy JSON verified")
PY

  echo "capability manifest policy verify OK"
} >"$log" 2>&1 || {
  cat "$log" >&2
  exit 1
}

cat "$log"
