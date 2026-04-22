#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/list_int_fast_lowering"
mkdir -p "$log_dir" "$tmp_dir"
log_path="$log_dir/verify_native_list_int_fast_lowering_${ts}.log"
build_seq=0
last_build_log=""

run_build() {
  local label="$1"
  local src="$2"
  local out="$3"
  shift 3
  build_seq=$((build_seq + 1))
  last_build_log="${tmp_dir}/trace_${build_seq}.log"

  {
    echo "== ${label} =="
    echo "src=${src}"
    echo "out=${out}"
    "$@"
  } >"$last_build_log" 2>&1
  cat "$last_build_log" >>"$log_path"
}

check_expect() {
  local label="$1"
  local expect="$2"

  if ! grep -Eq "$expect" "$last_build_log"; then
    echo "verify_native_list_int_fast_lowering: missing expected trace for ${label}" | tee -a "$log_path" >&2
    echo "expected regex: ${expect}" | tee -a "$log_path" >&2
    exit 1
  fi
}

check_push_tick_reg_contract() {
  local label="$1"
  local prefix="$2"

  python3 - "$last_build_log" "$prefix" <<'PY'
import re
import sys

path, prefix = sys.argv[1], sys.argv[2]
range_re = re.compile(r"\[arm64_loop_range\] kind=([^\s]+) start=(\d+) end=(\d+) bytes=(\d+)")
addr_re = re.compile(r"^([0-9a-fA-F]{16})\b")
branch_target_re = re.compile(r"\b0x([0-9a-fA-F]+)\b")
allowed_tick_re = re.compile(r"\bsubs\s+x9,\s*x9,\s*#(?:0x)?(?:1|4)\b")
wide_tick_re = re.compile(r"\bsubs\s+x9,\s*x9,\s*#(?:0x)?4\b")
wide_bump_re = re.compile(r"\badd\s+x20,\s*x20,\s*#(?:0x)?4\b")
wide_store_res = [
    re.compile(r"\bstr\s+x12,\s*\[x19\]"),
    re.compile(r"\bstr\s+x13,\s*\[x19,\s*#(?:0x)?8\]"),
    re.compile(r"\bstr\s+x14,\s*\[x19,\s*#(?:0x)?10\]"),
    re.compile(r"\bstr\s+x15,\s*\[x19,\s*#(?:0x)?18\]"),
]


def load_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def first_text_addr(lines):
    for line in lines:
        m = addr_re.match(line)
        if m:
            return int(m.group(1), 16)
    return None


def find_range(lines, prefix):
    matches = []
    for line in lines:
        m = range_re.search(line)
        if not m:
            continue
        kind = m.group(1)
        if kind == prefix or kind.startswith(prefix + "_"):
            matches.append((kind, int(m.group(2)), int(m.group(3))))
    if not matches:
        return None
    return matches[-1]


def collect_range_insns(lines, base_addr, start_off, end_off):
    start_abs = base_addr + start_off
    end_abs = base_addr + end_off
    insns = []
    for line in lines:
        m = addr_re.match(line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        if not (start_abs <= addr < end_abs):
            continue
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        mnemonic = parts[1]
        target = None
        if len(parts) >= 3:
            tm = branch_target_re.search(parts[2])
            if tm:
                target = int(tm.group(1), 16)
        insns.append({"addr": addr, "mnemonic": mnemonic, "line": line, "target": target})
    return insns


def collect_cold_gc_tick_blocks(insns):
    cold_addrs = set()
    for insn in insns:
        if insn["mnemonic"] != "b.ne" or insn["target"] is None or insn["target"] <= insn["addr"]:
            continue
        skipped = [cand for cand in insns if insn["addr"] < cand["addr"] < insn["target"]]
        if not any(cand["mnemonic"] == "bl" for cand in skipped):
            continue
        for cand in skipped:
            cold_addrs.add(cand["addr"])
    return cold_addrs


lines = load_lines(path)
base = first_text_addr(lines)
if base is None:
    print(f"verify_native_list_int_fast_lowering: no disassembly addresses found in {path}", file=sys.stderr)
    sys.exit(1)

found = find_range(lines, prefix)
if found is None:
    print(f"verify_native_list_int_fast_lowering: no arm64 loop range found for {prefix}", file=sys.stderr)
    sys.exit(1)

_, start_off, end_off = found
insns = collect_range_insns(lines, base, start_off, end_off)
if not insns:
    print(f"verify_native_list_int_fast_lowering: no disassembly instructions found inside {prefix}", file=sys.stderr)
    sys.exit(1)

cold_addrs = collect_cold_gc_tick_blocks(insns)
hot_insns = [insn for insn in insns if insn["addr"] not in cold_addrs]
offenders = []
allowed_tick_seen = False
wide_tick_seen = False
wide_bump_seen = False
wide_store_seen = [False, False, False, False]
for insn in hot_insns:
    line = insn["line"]
    if not re.search(r"\bx9\b", line):
        if wide_bump_re.search(line):
            wide_bump_seen = True
        for idx, store_re in enumerate(wide_store_res):
            if store_re.search(line):
                wide_store_seen[idx] = True
        continue
    if allowed_tick_re.search(line):
        allowed_tick_seen = True
        if wide_tick_re.search(line):
            wide_tick_seen = True
        continue
    offenders.append(line)

if not allowed_tick_seen:
    print(f"verify_native_list_int_fast_lowering: missing hot-loop x9 countdown in {prefix}", file=sys.stderr)
    sys.exit(1)

if offenders:
    print(f"verify_native_list_int_fast_lowering: unexpected hot-loop x9 use in {prefix}", file=sys.stderr)
    for line in offenders:
        print(line, file=sys.stderr)
    sys.exit(1)

if not wide_tick_seen:
    print(f"verify_native_list_int_fast_lowering: missing 4-wide hot-loop x9 countdown in {prefix}", file=sys.stderr)
    sys.exit(1)

if not wide_bump_seen:
    print(f"verify_native_list_int_fast_lowering: missing 4-wide idx bump in {prefix}", file=sys.stderr)
    sys.exit(1)

if not all(wide_store_seen):
    print(f"verify_native_list_int_fast_lowering: missing 4-wide slot stores in {prefix}", file=sys.stderr)
    sys.exit(1)
PY
}

build_and_check() {
  local label="$1"
  local src="$2"
  local out="$3"
  local expect="$4"
  shift 4

  run_build "$label" "$src" "$out" "$@"
  check_expect "$label" "$expect"
}

build_and_check \
  "arm64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_arm64" \
  'fast_list_int_get_sum_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/array_sum_int_arm64"

run_build \
  "arm64 canonical array_sum auto-list<int> lowerings" \
  "benchmarks/array_sum/array_sum.oren" \
  "${tmp_dir}/array_sum_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 OREN_TRACE_LIST_RESERVE=1 ./oren_stage2 build benchmarks/array_sum/array_sum.oren --backend native --no-debug --no-cache -o "${tmp_dir}/array_sum_arm64"
check_expect "arm64 canonical array_sum push lowering" 'fast_list_int_push_while(_no_tick)?'
check_expect "arm64 canonical array_sum get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'
check_expect "arm64 canonical array_sum reserve insertion" '\[opt\] list_int_reserve name=xs n=n'
check_expect "arm64 canonical array_sum unchecked push rewrite" '\[opt\] list_int_push_unchecked name=xs'

build_and_check \
  "arm64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_arm64" \
  'fast_list_int_dot_while(_no_tick)?' \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build benchmarks/dot_product_int/dot_product_int.oren --backend native --no-debug --no-cache -o "${tmp_dir}/dot_product_int_arm64"

run_build \
  "arm64 canonical dot_product auto-list<int> lowerings" \
  "benchmarks/dot_product/dot_product.oren" \
  "${tmp_dir}/dot_product_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 OREN_TRACE_LIST_RESERVE=1 ./oren_stage2 build benchmarks/dot_product/dot_product.oren --backend native --no-debug --no-cache -o "${tmp_dir}/dot_product_arm64"
check_expect "arm64 canonical dot_product push lowering" 'fast_list_int_push_while(_no_tick)?'
check_expect "arm64 canonical dot_product dot lowering" 'fast_list_int_dot_while(_no_tick)?'
check_expect "arm64 canonical dot_product reserve insertion a" '\[opt\] list_int_reserve name=a n=n'
check_expect "arm64 canonical dot_product reserve insertion b" '\[opt\] list_int_reserve name=b n=n'
check_expect "arm64 canonical dot_product unchecked push rewrite a" '\[opt\] list_int_push_unchecked name=a'
check_expect "arm64 canonical dot_product unchecked push rewrite b" '\[opt\] list_int_push_unchecked name=b'

build_and_check \
  "x64 array_sum_int fast get-sum lowering" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_get_sum_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/array_sum_int/array_sum_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/array_sum_int_x64_linux"

build_and_check \
  "x64 canonical array_sum auto-list<int> get-sum lowering" \
  "benchmarks/array_sum/array_sum.oren" \
  "${tmp_dir}/array_sum_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_get_sum_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_TRACE_LIST_RESERVE=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/array_sum/array_sum.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/array_sum_x64_linux"
check_expect "x64 canonical array_sum reserve insertion" '\[opt\] list_int_reserve name=xs n=n'
check_expect "x64 canonical array_sum unchecked push rewrite" '\[opt\] list_int_push_unchecked name=xs'

build_and_check \
  "x64 dot_product_int fast dot lowering" \
  "benchmarks/dot_product_int/dot_product_int.oren" \
  "${tmp_dir}/dot_product_int_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_dot_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/dot_product_int/dot_product_int.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/dot_product_int_x64_linux"

build_and_check \
  "x64 canonical dot_product auto-list<int> dot lowering" \
  "benchmarks/dot_product/dot_product.oren" \
  "${tmp_dir}/dot_product_x64_linux" \
  '\[x64_list_fast\].*kind=fast_list_int_dot_while' \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_TRACE_LIST_RESERVE=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build benchmarks/dot_product/dot_product.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/dot_product_x64_linux"
check_expect "x64 canonical dot_product reserve insertion a" '\[opt\] list_int_reserve name=a n=n'
check_expect "x64 canonical dot_product reserve insertion b" '\[opt\] list_int_reserve name=b n=n'
check_expect "x64 canonical dot_product unchecked push rewrite a" '\[opt\] list_int_push_unchecked name=a'
check_expect "x64 canonical dot_product unchecked push rewrite b" '\[opt\] list_int_push_unchecked name=b'

run_build \
  "arm64 commuted list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_commuted.oren" \
  "${tmp_dir}/list_int_fast_lowering_commuted_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build tests/fixtures/list_int_fast_lowering_commuted.oren --backend native --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_commuted_arm64"
check_expect "arm64 commuted list<int> get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'
check_expect "arm64 commuted list<int> dot lowering" 'fast_list_int_dot_while(_no_tick)?'

run_build \
  "x64 commuted list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_commuted.oren" \
  "${tmp_dir}/list_int_fast_lowering_commuted_x64_linux" \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build tests/fixtures/list_int_fast_lowering_commuted.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_commuted_x64_linux"
check_expect "x64 commuted list<int> get-sum lowering" '\[x64_list_fast\].*kind=fast_list_int_get_sum_while'
check_expect "x64 commuted list<int> dot lowering" '\[x64_list_fast\].*kind=fast_list_int_dot_while'

run_build \
  "arm64 temp-normalized list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_temp.oren" \
  "${tmp_dir}/list_int_fast_lowering_temp_arm64" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 ./oren_stage2 build tests/fixtures/list_int_fast_lowering_temp.oren --backend native --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_temp_arm64"
check_expect "arm64 temp-normalized list<int> get-sum lowering" 'fast_list_int_get_sum_while(_no_tick)?'
check_expect "arm64 temp-normalized list<int> dot lowering" 'fast_list_int_dot_while(_no_tick)?'

run_build \
  "arm64 array_sum_int push lowering disasm tick-reg contract" \
  "benchmarks/array_sum_int/array_sum_int.oren" \
  "${tmp_dir}/array_sum_int_arm64_disasm" \
  env OREN_TRACE_ARM64_LOOP_STACK=1 OREN_TRACE_ARM64_LOOP_RANGES=1 ./oren_stage2 build benchmarks/array_sum_int/array_sum_int.oren --backend native --no-debug --no-cache --disasm -o "${tmp_dir}/array_sum_int_arm64_disasm"
check_expect "arm64 array_sum_int push lowering disasm tick-reg contract" 'fast_list_int_push_while(_no_tick)?'
check_push_tick_reg_contract "arm64 array_sum_int push lowering disasm tick-reg contract" 'fast_list_int_push_while'

run_build \
  "x64 temp-normalized list<int> fast lowerings" \
  "tests/fixtures/list_int_fast_lowering_temp.oren" \
  "${tmp_dir}/list_int_fast_lowering_temp_x64_linux" \
  env OREN_TRACE_X64_LIST_FAST=1 OREN_PARSE_FORK_PARALLEL=1 OREN_PARSE_JOBS="${OREN_PARSE_JOBS:-8}" ./oren build tests/fixtures/list_int_fast_lowering_temp.oren --backend native --platform x64-linux --no-debug --no-cache -o "${tmp_dir}/list_int_fast_lowering_temp_x64_linux"
check_expect "x64 temp-normalized list<int> get-sum lowering" '\[x64_list_fast\].*kind=fast_list_int_get_sum_while'
check_expect "x64 temp-normalized list<int> dot lowering" '\[x64_list_fast\].*kind=fast_list_int_dot_while'

echo "native list<int> fast-lowering verify complete; log: $log_path"
