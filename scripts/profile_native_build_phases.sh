#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

compiler="${OREN_PROFILE_NATIVE_COMPILER:-./oren_stage2}"
src="${1:-${OREN_PROFILE_NATIVE_SRC:-tests/fixtures/generator_surface_v0.oren}}"
platform="${OREN_PLATFORM:-arm64-macos}"
ts="${OREN_PROFILE_NATIVE_TS:-$(date +%Y%m%d_%H%M%S)}"
out="${OREN_PROFILE_NATIVE_OUT:-build/tmp/native_build_phase_profile_${ts}.native}"
log="${OREN_PROFILE_NATIVE_LOG:-build/logs/native_build_phase_profile_${ts}.log}"
phase_log="${OREN_PROFILE_NATIVE_PHASE_LOG:-build/logs/native_build_phase_profile_${ts}.phases.log}"
timeout_secs="${OREN_PROFILE_NATIVE_TIMEOUT_SECS:-180}"

mkdir -p "$(dirname "$out")" "$(dirname "$log")" "$(dirname "$phase_log")"

echo "== native build phase profile =="
echo "compiler=$compiler"
echo "src=$src"
echo "platform=$platform"
echo "log=$log"
echo "phase_log=$phase_log"

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: missing executable compiler: $compiler" >&2
  echo "Hint: run make stage2 or set OREN_PROFILE_NATIVE_COMPILER." >&2
  exit 2
fi
if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

source scripts/verify_parallel_jobs.sh

native_astbin_seed="$(verify_native_astbin_seed_path "$platform" "$log" || true)"
if [[ -n "$native_astbin_seed" ]]; then
  echo "native_runtime_astbin_seed=$native_astbin_seed" >>"$log"
fi
verify_native_rtobj_seed_prewarm "$platform" "$log" "$compiler" || true

start_s="$(date +%s)"
export OREN_TRACE_BUILD_PHASES_PATH="$phase_log"
if ! run_native_build_timeout_logged "$timeout_secs" "$compiler" build "$src" \
  --backend native --platform "$platform" --no-cache --no-debug -o "$out" >>"$log" 2>&1; then
  echo "ERROR: native build failed; see $log" >&2
  exit 1
fi
end_s="$(date +%s)"
echo "real $((end_s - start_s))" >>"$log"

python3 - "$phase_log" <<'PY'
import re
import sys
from pathlib import Path

phase_log = Path(sys.argv[1])
phase_re = re.compile(r"phase=([^ ]+) now_ns=([0-9]+)(.*)$")

events = []
for line in phase_log.read_text(errors="replace").splitlines():
    match = phase_re.search(line)
    if not match:
        continue
    events.append((match.group(1), int(match.group(2)), match.group(3).strip()))

if len(events) < 2:
    print("WARNING: insufficient phase data")
    raise SystemExit(0)

print("== adjacent phase deltas ==")
deltas = []
for idx in range(1, len(events)):
    prev_name, prev_ns, _ = events[idx - 1]
    name, ns, detail = events[idx]
    ms = (ns - prev_ns) / 1_000_000
    deltas.append((ms, prev_name, name, detail))
for ms, prev_name, name, detail in deltas:
    suffix = f" {detail}" if detail else ""
    print(f"{ms:10.3f} ms  {prev_name} -> {name}{suffix}")

print("== top adjacent phase deltas ==")
for ms, prev_name, name, detail in sorted(deltas, reverse=True)[:15]:
    suffix = f" {detail}" if detail else ""
    print(f"{ms:10.3f} ms  {prev_name} -> {name}{suffix}")
PY
