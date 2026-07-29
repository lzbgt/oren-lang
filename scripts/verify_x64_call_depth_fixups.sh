#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

src="lib/compiler/x64_native_program/080_functions_compile.oren"
impl="$(sed -n '/fn _x64_emit_function_call_depth_exit/,/fn _x64_emit_function_restore_regs/p; /fn _x64_emit_function_call_depth_enter/,/fn _x64_function_done_phase_detail/p' "$src")"

if ! grep -Fq '_emit_call_rel32_named_x64(ctx, "oren_call_depth_enter")' <<<"$impl" ||
   ! grep -Fq '_emit_call_rel32_named_x64(ctx, "oren_call_depth_exit")' <<<"$impl"; then
  echo "ERROR: x64 call-depth hooks must use named call_rel32 fixups" >&2
  exit 1
fi

if grep -Eq 'call_depth_(enter|exit)_fixups|bytes_push\(ctx\["code"\], 232\)|push_u32_le\(ctx\["code"\], 0\)' <<<"$impl"; then
  echo "ERROR: x64 function call-depth hooks must not emit raw untracked call placeholders" >&2
  exit 1
fi

echo "OK: x64 call-depth hooks use named fixups"
