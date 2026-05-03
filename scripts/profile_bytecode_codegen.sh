#!/usr/bin/env bash
set -euo pipefail

compiler="${OREN_PROFILE_BYTECODE_COMPILER:-./oren_stage2}"
src="${1:-${OREN_PROFILE_BYTECODE_SRC:-tests/fixtures/generator_surface_v0.oren}}"
platform="${OREN_PLATFORM:-arm64-macos}"
ts="${OREN_PROFILE_BYTECODE_TS:-$(date +%Y%m%d_%H%M%S)}"
out="${OREN_PROFILE_BYTECODE_OUT:-build/tmp/bytecode_codegen_profile_${ts}.obc}"
log="${OREN_PROFILE_BYTECODE_LOG:-build/logs/bytecode_codegen_profile_${ts}.log}"
phase_log="${OREN_PROFILE_BYTECODE_PHASE_LOG:-build/logs/bytecode_codegen_profile_${ts}.phases.log}"

mkdir -p "$(dirname "$out")" "$(dirname "$log")" "$(dirname "$phase_log")"

echo "== bytecode codegen profile =="
echo "compiler=$compiler"
echo "src=$src"
echo "platform=$platform"
echo "log=$log"
echo "phase_log=$phase_log"

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: missing executable compiler: $compiler" >&2
  echo "Hint: run make stage2 or set OREN_PROFILE_BYTECODE_COMPILER." >&2
  exit 2
fi
if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

/usr/bin/time -p env \
  OREN_TRACE_BYTECODE_CODEGEN=1 \
  OREN_TRACE_BUILD_PHASES_PATH="$phase_log" \
  "$compiler" build "$src" --backend bytecode --platform "$platform" --no-cache -o "$out" \
  >"$log" 2>&1

python3 - "$log" "$phase_log" <<'PY'
import re
import sys
from pathlib import Path

log = Path(sys.argv[1])
phase_log = Path(sys.argv[2])
section_re = re.compile(r"\[bc_codegen_profile\] section=([^ ]+) ms=([0-9]+)(?: count=([0-9]+))?")
fn_re = re.compile(r"\[bc_codegen_profile\] fn=(.*?) ms=([0-9]+) bytes=([0-9]+) locals=([0-9]+)")

sections = []
fns = []
for line in log.read_text(errors="replace").splitlines():
    m = section_re.search(line)
    if m:
        sections.append((m.group(1), int(m.group(2)), int(m.group(3) or 0)))
        continue
    m = fn_re.search(line)
    if m:
        fns.append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))))

print("== section summary ==")
for name, ms, count in sorted(sections, key=lambda item: item[1], reverse=True):
    suffix = f" count={count}" if count else ""
    print(f"{ms:8d} ms  {name}{suffix}")

if fns:
    print("== top functions ==")
    for name, ms, byte_count, locals_count in sorted(fns, key=lambda item: item[1], reverse=True)[:20]:
        print(f"{ms:8d} ms  bytes={byte_count:7d} locals={locals_count:4d}  {name}")
    print(f"function_count={len(fns)} function_ms_sum={sum(ms for _, ms, _, _ in fns)}")

if phase_log.exists():
    print("== build phases log ==")
    print(str(phase_log))
PY

