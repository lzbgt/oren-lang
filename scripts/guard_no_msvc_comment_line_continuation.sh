#!/usr/bin/env bash
set -euo pipefail

# Guardrail: prevent MSVC-only C parser hazards where a `// ... \` comment line
# continuation corrupts the following line.
#
# Why:
# - MSVC can treat a trailing `\` at end-of-line as a line continuation even in `//` comments
#   (C4010 warning + follow-on syntax errors).
# - This has broken stage0->stage1 bootstrap on real Win11 bring-up.
#
# Scope:
# - C runtime sources used by stage0/stage1 bootstraps and helper shims:
#   - lib/runtime*.c
#   - lib/runtime/*.inc
#   - native/**/*.c, native/**/*.h
#
# This guard is intentionally conservative: it flags any `// ... \` where `\` is the
# last non-newline character (allowing trailing whitespace).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

tmp="${TMPDIR:-/tmp}/oren_no_msvc_comment_continuation.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

{
  find lib -maxdepth 1 -type f \( -name 'runtime*.c' -o -name 'runtime*.h' \) -print 2>/dev/null || true
  find lib/runtime -type f -name '*.inc' -print 2>/dev/null || true
  find native -type f \( -name '*.c' -o -name '*.h' \) -print 2>/dev/null || true
} >"$tmp"

pat='//.*\\[[:space:]]*$'

found=0

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if grep -nE "$pat" "$f" >/dev/null 2>&1; then
    found=1
    break
  fi
done <"$tmp"

if [[ "$found" -ne 0 ]]; then
  echo "ERROR: found trailing '\\' at end-of-line in // comments (MSVC line-continuation hazard)." >&2
  echo "Fix by ensuring the comment line ends with a non-\\\\ character (example: add ' (UNC root)')." >&2
  echo "--- matches (first 80) ---" >&2
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    grep -nE "$pat" "$f" 2>/dev/null || true
  done <"$tmp" | head -n 80 >&2 || true
  exit 1
fi

echo "OK: no MSVC // comment line-continuation hazards found"
