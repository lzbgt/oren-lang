#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG_DIR="build/logs"
ts="$(date +%Y%m%d_%H%M%S)"
TMP="build/tmp/verify-native-capsule-resource-checks-${ts}"
RUNTIME_TMP="build/tmp/native_capsule_resource_checks"
mkdir -p "$TMP" "$LOG_DIR" "$RUNTIME_TMP/allowed" "$RUNTIME_TMP/denied"
trap 'rm -rf "$TMP" "$RUNTIME_TMP"' EXIT

allow_src="tests/fixtures/native_capsule_resource_fs_allow.oren"
deny_src="tests/fixtures/native_capsule_resource_fs_deny.oren"
allow_bin="$TMP/fs_allow"
deny_bin="$TMP/fs_deny"
allow_build_log="$LOG_DIR/verify_native_capsule_resource_checks_${ts}_allow_build.log"
deny_build_log="$LOG_DIR/verify_native_capsule_resource_checks_${ts}_deny_build.log"
allow_out="$TMP/fs_allow.out"
allow_err="$TMP/fs_allow.err"
deny_out="$TMP/fs_deny.out"
deny_err="$TMP/fs_deny.err"

printf 'ok\n' >"$RUNTIME_TMP/allowed/in.txt"
printf 'deny\n' >"$RUNTIME_TMP/denied/in.txt"

./oren build "$allow_src" --backend native --capsule --cap-allow-domains FS --no-debug --no-cache -o "$allow_bin" \
  >"$allow_build_log" 2>&1
./oren build "$deny_src" --backend native --capsule --cap-allow-domains FS --no-debug --no-cache -o "$deny_bin" \
  >"$deny_build_log" 2>&1

OREN_CAPSULE=1 \
OREN_CAP_ALLOW_DOMAINS=FS \
OREN_FS_ALLOW_READ_PREFIXES="$RUNTIME_TMP/allowed/" \
OREN_NATIVE_RUN_JSON=1 \
  "$allow_bin" >"$allow_out" 2>"$allow_err"

set +e
OREN_CAPSULE=1 \
OREN_CAP_ALLOW_DOMAINS=FS \
OREN_FS_ALLOW_READ_PREFIXES="$RUNTIME_TMP/allowed/" \
OREN_NATIVE_RUN_JSON=1 \
  "$deny_bin" >"$deny_out" 2>"$deny_err"
deny_rc=$?
set -e

python3 - "$allow_out" "$allow_err" "$deny_out" "$deny_err" "$deny_rc" <<'PY'
import json
import sys
from pathlib import Path

allow_out, allow_err, deny_out, deny_err = map(Path, sys.argv[1:5])
deny_rc = int(sys.argv[5])

def fail(msg):
    raise SystemExit(msg)

def json_lines(path):
    items = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            items.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return items

def require_native_run(path):
    for item in json_lines(path):
        if item.get("schema") == "oren.native-run.v0":
            return item
    fail(f"{path}: missing oren.native-run.v0 JSON line\nstdout:\n{path.read_text(encoding='utf-8')}")

def require_prefixed_json(path, prefix):
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith(prefix):
            continue
        return json.loads(line[len(prefix):])
    fail(f"{path}: missing prefix {prefix!r}\nstdout:\n{path.read_text(encoding='utf-8')}")

def check_resource_summary(summary, *, expect_denied):
    if summary.get("schema") != "oren.native-capsule-resource-checks.v0":
        fail(f"resource summary schema mismatch: {summary!r}")
    if summary.get("kind") != "resource_checks" or summary.get("available") is not True:
        fail(f"resource summary availability mismatch: {summary!r}")
    if summary.get("capsule") is not True:
        fail(f"expected capsule resource summary: {summary!r}")
    resources = summary.get("resources") or {}
    fs_path = resources.get("fs_path") or {}
    if expect_denied:
        if int(summary.get("denied") or 0) <= 0:
            fail(f"expected denied resource count: {summary!r}")
        if int(fs_path.get("denied") or 0) <= 0:
            fail(f"expected fs_path denied count: {summary!r}")
    else:
        if int(summary.get("total") or 0) <= 0:
            fail(f"expected positive resource count: {summary!r}")
        if int(summary.get("denied") or 0) != 0:
            fail(f"expected zero denied resources on allow path: {summary!r}")
        if int(fs_path.get("allowed") or 0) <= 0:
            fail(f"expected fs_path allowed count: {summary!r}")
        if int(fs_path.get("denied") or 0) != 0:
            fail(f"expected zero fs_path denied count: {summary!r}")

allow_direct = require_prefixed_json(allow_out, "native capsule resource checks ")
check_resource_summary(allow_direct, expect_denied=False)

allow_run = require_native_run(allow_out)
allow_summary = (((allow_run.get("effect_ledger_summary") or {}).get("resource_checks")) or {})
check_resource_summary(allow_summary, expect_denied=False)

if deny_rc != 78:
    fail(
        f"expected deny fixture rc=78, got {deny_rc}\n"
        f"stdout:\n{deny_out.read_text(encoding='utf-8')}\n"
        f"stderr:\n{deny_err.read_text(encoding='utf-8')}"
    )
if "CAPSULE DENY: FS_PATH" not in deny_out.read_text(encoding="utf-8"):
    fail(f"missing FS_PATH denial diagnostic in {deny_out}")

deny_run = require_native_run(deny_out)
if deny_run.get("exit_code") != 78:
    fail(f"expected native run JSON exit_code=78, got {deny_run!r}")
deny_summary = (((deny_run.get("effect_ledger_summary") or {}).get("resource_checks")) or {})
check_resource_summary(deny_summary, expect_denied=True)

print("native capsule resource-check JSON verified")
PY

echo "native capsule resource checks verify OK"
