#!/usr/bin/env bash
set -euo pipefail

max_lines="${OREN_SOURCE_LINE_MAX:-2000}"
fail=0

while IFS= read -r -d '' path; do
  lines="$(wc -l <"$path" | tr -d ' ')"
  if [[ "$lines" -gt "$max_lines" ]]; then
    printf 'FAIL: %s has %s lines (max %s)\n' "$path" "$lines" "$max_lines" >&2
    fail=1
  fi
done < <(
  git ls-files -z -- \
    '*.oren' '*.py' '*.sh' '*.c' '*.h' '*.m' '*.mm' '*.swift' '*.go' '*.cpp' '*.hpp' 'Makefile' |
    python3 -c 'import sys
skip = ("docs/site/", "project-doc/web/", "third_party/", "build/", "node_modules/")
data = sys.stdin.buffer.read().split(b"\0")
for raw in data:
    if not raw:
        continue
    path = raw.decode("utf-8", "surrogateescape")
    if path.startswith(skip):
        continue
    sys.stdout.buffer.write(raw + b"\0")'
)

if [[ "$fail" != "0" ]]; then
  exit 1
fi

echo "OK: source line guard <= ${max_lines}"
