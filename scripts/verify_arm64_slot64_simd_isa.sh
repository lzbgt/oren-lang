#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/verify-arm64-slot64-simd-isa-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

log_path="$log_dir/verify_arm64_slot64_simd_isa_${ts}.log"
cc_bin="${CC:-cc}"

valid_src="$tmp_dir/valid_slot64_sum_and_packed_dot.s"
valid_obj="$tmp_dir/valid_slot64_sum_and_packed_dot.o"
invalid_src="$tmp_dir/invalid_slot64_mul_2d.s"
invalid_obj="$tmp_dir/invalid_slot64_mul_2d.o"
invalid_log="$tmp_dir/invalid_slot64_mul_2d.stderr.log"

cat >"$valid_src" <<'ASM'
.text
.globl _valid_slot64_sum_and_packed_dot
_valid_slot64_sum_and_packed_dot:
    ldr q0, [x0]
    ldr q1, [x1]
    add v2.2d, v0.2d, v1.2d
    addp v3.2d, v2.2d, v2.2d
    fmov x0, d3
    smull v4.2d, v0.2s, v1.2s
    smull2 v5.2d, v0.4s, v1.4s
    add v6.2d, v4.2d, v5.2d
    addp v6.2d, v6.2d, v6.2d
    fmov x1, d6
    ret
ASM

cat >"$invalid_src" <<'ASM'
.text
.globl _invalid_slot64_mul_2d
_invalid_slot64_mul_2d:
    ldr q0, [x0]
    ldr q1, [x1]
    mul v2.2d, v0.2d, v1.2d
    ret
ASM

{
    echo "arm64 slot64 SIMD ISA probe"
    echo "cc: $cc_bin"
    echo "valid_src: $valid_src"
    echo "invalid_src: $invalid_src"
    echo ""
    echo "[assemble valid slot64 add + packed i32 widening dot]"
    "$cc_bin" -c "$valid_src" -o "$valid_obj"
    echo "valid_assemble: ok"
    if command -v otool >/dev/null 2>&1; then
        echo ""
        echo "[valid disassembly]"
        otool -tvV "$valid_obj" | sed -n '1,120p'
    elif command -v objdump >/dev/null 2>&1; then
        echo ""
        echo "[valid disassembly]"
        objdump -d "$valid_obj" | sed -n '1,120p'
    else
        echo "valid_disassembly: skipped (no otool/objdump)"
    fi
    echo ""
    echo "[assemble invalid slot64 vector multiply]"
    if "$cc_bin" -c "$invalid_src" -o "$invalid_obj" >"$invalid_log" 2>&1; then
        echo "invalid_assemble: unexpected_success"
        exit 1
    fi
    echo "invalid_assemble: rejected"
    sed -n '1,80p' "$invalid_log"
    echo ""
    echo 'verdict: AdvSIMD accepts slot64 vector add/reduce and packed-i32 widening multiply/reduce, but rejects true 64-bit-lane vector multiply (`mul v*.2d`).'
} >"$log_path" 2>&1

if ! grep -q "valid_assemble: ok" "$log_path"; then
    echo "arm64 slot64 SIMD ISA probe failed: valid assembly did not assemble; log: $log_path" >&2
    exit 1
fi
if ! grep -q "invalid_assemble: rejected" "$log_path"; then
    echo "arm64 slot64 SIMD ISA probe failed: invalid slot64 vector multiply was not rejected; log: $log_path" >&2
    exit 1
fi

echo "arm64 slot64 SIMD ISA probe complete; log: $log_path"
