#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: scripts/run_backend_semantic_diff.sh [source.oren]

Builds the source with C, native, and bytecode backends, runs all three, and
writes an agent-readable semantic-diff JSON report under build/reports/.

Environment:
  OREN_BACKEND_SEMANTIC_DIFF_SRC          default source when no arg is given
  OREN_BACKEND_SEMANTIC_DIFF_EXPECT_LINE  required normalized stdout line
  OREN_BACKEND_SEMANTIC_DIFF_KEEP_ARTIFACTS=1 keeps generated binaries/obc
  OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS  build timeout, default 120
  OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS    run timeout, default 5
  OREN_BACKEND_PARITY_TRACE_ENV           optional env forwarded to build/run
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

src="${1:-${OREN_BACKEND_SEMANTIC_DIFF_SRC:-tests/fixtures/backend_semantic_diff_smoke.oren}}"
expect_line="${OREN_BACKEND_SEMANTIC_DIFF_EXPECT_LINE:-ok: semantic diff}"

if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"
timeout_kill_secs="${OREN_TIMEOUT_KILL_SECS:-2}"
build_timeout_secs="${OREN_BACKEND_PARITY_BUILD_TIMEOUT_SECS:-120}"
run_timeout_secs="${OREN_BACKEND_PARITY_RUN_TIMEOUT_SECS:-5}"

run_with_timeout() {
  local secs="$1"
  shift
  if [[ -n "$timeout_bin" ]]; then
    "$timeout_bin" -k "$timeout_kill_secs" "$secs" "$@"
  else
    "$@"
  fi
}

trace_env="${OREN_BACKEND_PARITY_TRACE_ENV:-}"
trace_env_arr=()
if [[ -n "$trace_env" ]]; then
  # shellcheck disable=SC2206
  trace_env_arr=($trace_env)
fi

uname_s="$(uname -s)"
uname_m="$(uname -m)"

case "$uname_s" in
  Darwin) os_key="macos" ;;
  Linux) os_key="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os_key="windows" ;;
  *) echo "unsupported host OS: $uname_s" >&2; exit 2 ;;
esac

case "$uname_m" in
  arm64|aarch64) arch_key="arm64" ;;
  x86_64|amd64) arch_key="x64" ;;
  *) echo "unsupported host arch: $uname_m" >&2; exit 2 ;;
esac

platform="${arch_key}-${os_key}"
exe_ext=""
if [[ "$os_key" == "windows" ]]; then
  exe_ext=".exe"
fi

mkdir -p build/tmp build/logs build/reports

COMPILER="${OREN_COMPILER:-./oren_stage2}"
if [[ ! -x "$COMPILER" ]]; then
  echo "== ensure: stage2 compiler ($COMPILER) ==" >&2
  make stage2
fi
if [[ ! -x ./avm ]]; then
  echo "== ensure: avm ==" >&2
  make avm
fi

ts="$(date +%Y%m%d_%H%M%S)"
base="$(basename "$src" .oren | tr -c 'A-Za-z0-9_-' '_')"
prefix="backend_semantic_diff_${base}_${ts}"
tmp_prefix="build/tmp/${prefix}"
log_prefix="build/logs/${prefix}"
report="build/reports/${prefix}.json"

out_c="${tmp_prefix}_c${exe_ext}"
out_native="${tmp_prefix}_native${exe_ext}"
out_obc="${tmp_prefix}.obc"

build_c="${log_prefix}_c_build.log"
build_native="${log_prefix}_native_build.log"
build_obc="${log_prefix}_obc_build.log"
run_c_out="${log_prefix}_c.stdout"
run_c_err="${log_prefix}_c.stderr"
run_native_out="${log_prefix}_native.stdout"
run_native_err="${log_prefix}_native.stderr"
run_obc_out="${log_prefix}_obc.stdout"
run_obc_err="${log_prefix}_obc.stderr"

cleanup_artifacts=1
if [[ -n "${OREN_BACKEND_SEMANTIC_DIFF_KEEP_ARTIFACTS:-}" ]]; then
  cleanup_artifacts=0
fi

cleanup() {
  if [[ "$cleanup_artifacts" == "1" ]]; then
    rm -f "$out_c" "$out_native" "$out_obc"
  fi
}
trap cleanup EXIT

echo "== semantic diff build: C ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" "$COMPILER" build "$src" --backend c -o "$out_c" >"$build_c" 2>&1
test -f "$out_c" || { echo "FAIL: missing $out_c" >&2; tail -n 120 "$build_c" >&2 || true; exit 3; }

echo "== semantic diff build: native ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" "$COMPILER" build "$src" --backend native --platform "$platform" --no-debug -o "$out_native" >"$build_native" 2>&1
test -f "$out_native" || { echo "FAIL: missing $out_native" >&2; tail -n 120 "$build_native" >&2 || true; exit 4; }

echo "== semantic diff build: bytecode ==" >&2
run_with_timeout "$build_timeout_secs" env "${trace_env_arr[@]}" "$COMPILER" build "$src" --backend bytecode -o "$out_obc" >"$build_obc" 2>&1
test -f "$out_obc" || { echo "FAIL: missing $out_obc" >&2; tail -n 120 "$build_obc" >&2 || true; exit 5; }

set +e
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" "$out_c" >"$run_c_out" 2>"$run_c_err"
rc_c=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" "$out_native" >"$run_native_out" 2>"$run_native_err"
rc_native=$?
run_with_timeout "$run_timeout_secs" env "${trace_env_arr[@]}" ./avm "$out_obc" >"$run_obc_out" 2>"$run_obc_err"
rc_obc=$?
set -e

python3 - "$report" "$src" "$expect_line" \
  c "$rc_c" "$run_c_out" "$run_c_err" "$build_c" \
  native "$rc_native" "$run_native_out" "$run_native_err" "$build_native" \
  obc "$rc_obc" "$run_obc_out" "$run_obc_err" "$build_obc" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

report = Path(sys.argv[1])
src = sys.argv[2]
expect_line = sys.argv[3]
items = sys.argv[4:]

def read_text(path_s):
    return Path(path_s).read_text(encoding="utf-8", errors="replace")

def normalize(text):
    text = text.replace("\r", "")
    return "\n".join(line.rstrip() for line in text.splitlines())

def sha256_s(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

backends = {}
for i in range(0, len(items), 5):
    name = items[i]
    rc = int(items[i + 1])
    stdout_path = items[i + 2]
    stderr_path = items[i + 3]
    build_log = items[i + 4]
    stdout = read_text(stdout_path)
    stderr = read_text(stderr_path)
    stdout_norm = normalize(stdout)
    stderr_norm = normalize(stderr)
    backends[name] = {
        "exit_code": rc,
        "stdout_sha256": sha256_s(stdout_norm),
        "stderr_sha256": sha256_s(stderr_norm),
        "stdout_normalized": stdout_norm,
        "stderr_normalized": stderr_norm,
        "stdout_log": stdout_path,
        "stderr_log": stderr_path,
        "build_log": build_log,
        "expected_line_present": expect_line in stdout_norm.splitlines(),
    }

order = ["c", "native", "obc"]
stdout_equal = len({backends[name]["stdout_normalized"] for name in order}) == 1
exit_equal = len({backends[name]["exit_code"] for name in order}) == 1
all_ok = all(backends[name]["exit_code"] == 0 for name in order)
expect_ok = all(backends[name]["expected_line_present"] for name in order)
status = "pass" if stdout_equal and exit_equal and all_ok and expect_ok else "fail"

out = {
    "schema": "oren.semantic-diff.v0",
    "source": src,
    "backend_order": order,
    "status": status,
    "checks": {
        "stdout_equal": stdout_equal,
        "exit_code_equal": exit_equal,
        "all_exit_zero": all_ok,
        "expected_line": expect_line,
        "expected_line_present_all": expect_ok,
    },
    "backends": backends,
}

report.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"semantic diff report: {report}")
if status != "pass":
    print(json.dumps(out["checks"], indent=2, sort_keys=True), file=sys.stderr)
    raise SystemExit(1)
PY

echo "OK: backend semantic diff (C/native/obc)" >&2
