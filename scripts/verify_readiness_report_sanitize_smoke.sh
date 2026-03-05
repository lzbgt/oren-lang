#!/usr/bin/env bash
set -euo pipefail

work_dir="build/tmp/readiness_report_sanitize_smoke"
report_in="${work_dir}/report.md"
json_in="${work_dir}/report.json"
report_out="${work_dir}/report_sanitized.md"
json_out="${work_dir}/report_sanitized.json"

rm -rf "$work_dir" 2>/dev/null || true
mkdir -p "$work_dir"

cat >"$report_in" <<'EOF_MD'
# Oren readiness report

- logs: /abs/path/to/logs
- json: /abs/path/to/report.json
- index: /abs/path/to/index.jsonl
- status_snapshot_md: /abs/path/to/status_snapshot.md
- status_snapshot_json: /abs/path/to/status_snapshot.json
- status_faq_md: /abs/path/to/status_faq.md
- status_faq_json: /abs/path/to/status_faq.json
- status_matrix_md: /abs/path/to/status_matrix.md
- status_matrix_json: /abs/path/to/status_matrix.json
- git: abcdef (dirty)

## Environment (OREN_*)

```
OREN_FOO=bar
```

## Workspace diff

```
foo
```

## Steps

- verify-native-quick: OK (1s)
  - cmd: `make verify-native-quick`
  - log: `/abs/path/to/logs/step.log`
EOF_MD

cat >"$json_in" <<'EOF_JSON'
{
  "git": {"rev": "abcdef", "status": [" M foo"], "diff_stat": "foo"},
  "paths": {"report": "/abs/path/report", "logs": "/abs/path/logs", "json": "/abs/path/report.json"},
  "steps": [{"name": "x", "log": "/abs/path/log"}],
  "env": ["OREN_FOO=bar"]
}
EOF_JSON

./scripts/readiness_report_sanitize.py --report "$report_in" --json "$json_in" --out-md "$report_out" --out-json "$json_out"

rg -n "<redacted>" "$report_out" >/dev/null
rg -n "status_snapshot_md: <redacted>" "$report_out" >/dev/null
rg -n "status_faq_md: <redacted>" "$report_out" >/dev/null
rg -n "status_matrix_md: <redacted>" "$report_out" >/dev/null
! rg -n "OREN_FOO" "$report_out" >/dev/null
! rg -n "Workspace diff" "$report_out" >/dev/null
rg -n "<redacted>" "$json_out" >/dev/null
rg -n "\"env\": \[\]" "$json_out" >/dev/null

echo "OK: readiness report sanitize smoke verified"
