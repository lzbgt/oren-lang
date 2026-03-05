#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_index_lint_smoke"
index_path="${work_dir}/readiness_index.jsonl"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$index_path" <<'EOF'
{"timestamp":"20260305_020000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
{"timestamp":"20260305_010000","profile":"quick","overall":"PASS","dry_run":false,"total_duration_sec":40,"git_rev":"abcd1234","git_dirty":"clean","report":"a","json":"a","log_dir":"a","tag":"nightly"}
EOF

set +e
./scripts/readiness_report_index_lint.py --index "$index_path"
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "expected lint to warn on out-of-order timestamps" >&2
  exit 2
fi

echo "OK: readiness index lint smoke verified"
