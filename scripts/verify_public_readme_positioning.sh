#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pattern='Zig|zig|ZIG'

matches="$(
  rg -n "$pattern" . \
    --glob 'README*.md' \
    --glob '!project-doc/**' \
    --glob '!docs/refs/**' \
    --glob '!build/**' || true
)"

if [[ -n "$matches" ]]; then
  echo "ERROR: public README files should use mainstream-language positioning, not explicit Zig comparison." >&2
  echo "$matches" >&2
  exit 1
fi

echo "public README positioning verify OK"
