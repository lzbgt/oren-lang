#!/usr/bin/env bash
set -euo pipefail

# Guardrail: the compiler/runtime must not depend on external host tools like `rg` (ripgrep).
#
# Rationale:
# - Tier‑1 includes Windows and minimal environments where `rg` is often not installed.
# - The compiler should be self-contained (stdlib + syscalls) for core tooling paths.
#
# This guard scans only Oren sources (`*.oren`, `*.inc`) under `lib/` for suspicious
# shell-outs that invoke `rg` / ripgrep.
#
# NOTE: this is not a style preference: it prevents hard-to-debug parity failures on
# remote Win11/WSL2 bring-up and in minimal containers.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="${TMPDIR:-/tmp}/oren_no_rg_scan.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

find lib -type f \( -name '*.oren' -o -name '*.inc' \) -print0 >"$tmp"

pat='(oren_system|sys_system|sys_exec|sys_spawn)[[:space:]]*\([^)]*\<(rg|ripgrep)\>'

if xargs -0 grep -nE "$pat" <"$tmp" >/dev/null 2>&1; then
  echo "ERROR: compiler/runtime sources appear to shell out to rg/ripgrep." >&2
  echo "Fix by using in-language scanning/regex, or keep this in developer scripts only." >&2
  echo "--- matches ---" >&2
  xargs -0 grep -nE "$pat" <"$tmp" | head -n 80 >&2 || true
  exit 1
fi

echo "OK: no rg/ripgrep dependency found in lib/ compiler/runtime sources"

