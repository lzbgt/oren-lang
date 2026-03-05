#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/readiness_pipeline.sh [options]

Options:
  --profile <minimal|quick|full>   Verification profile (default: quick).
  --tag <name>                     Attach a tag to the report/index.
  --index <path>                   Index path (default: build/reports/readiness_index.jsonl).
  --include-env                    Include OREN_* env vars in report.
  --keep-going                     Run all steps even if one fails (report step only).
  --summary-limit <n>              Max entries in summary (default: 20).
  --stats-limit <n>                Max entries in stats (default: 200; 0=all).
  --no-csv                         Skip CSV export.
  --rollup-days <n>                Rollup days (default: 30; 0=all).
  --no-dashboard                   Skip HTML dashboard.
  --no-schema                      Skip JSON schema validation.
  --prune <n>                       Prune index to last N entries after run (0=skip).
  --log <path>                      Write pipeline log to path (default: build/logs/readiness_pipeline_<ts>.log).
  --diff-against <path>             Compare index with another JSONL and emit summary diff.
  --gate-pass-rate <pct>            Fail if pass rate is below pct (windowed).
  --gate-window <n>                 Gate window size (default: 0=all).
  --gate-max-fail-streak <n>        Fail if consecutive FAIL streak exceeds n.
  --gate-max-fail-count <n>         Fail if fail count exceeds n.
  --gate-allow-empty                Allow empty index in gate.
  --status-path <path>              STATUS.md path for snapshot (default: docs/STATUS.md).
  --no-status-snapshot              Skip status snapshot output.
  --status-diff-against <path>      Diff status snapshot against STATUS.md or snapshot JSON.
  --no-latest-summary               Skip index latest summary output.
  --trend-window <n>                Trend window size for index trend (default: 20).
  --no-trend                        Skip trend output.
  --no-profile-summary              Skip profile summary output.
  --no-tag-summary                  Skip tag summary output.
  --audit                           Run index audit (checks for missing report/json/log_dir paths).
  --audit-allow-missing             Audit reports missing paths but does not fail.
  --audit-max-missing <n>           Fail audit if missing_any exceeds n (default: -1).
  --collect <n>                     Collect last N readiness reports (0=skip, default: 0).
  --collect-dir <path>              Output directory for collected snapshots.
  --collect-include-dry-run         Include dry_run entries in collection.
  --collect-copy-logs               Copy log_dir contents into snapshot.
  --collect-pack                    Pack collected snapshots into tar.gz.
  --collect-pack-out <path>         Output tar.gz path (default: build/reports/readiness_collect.tar.gz).
  --trim-since <ts>                 Trim index to entries >= ts (YYYYMMDD_HHMMSS).
  --trim-until <ts>                 Trim index to entries <= ts (YYYYMMDD_HHMMSS).
  --trim-since-days <n>             Trim to last N days (local time).
  --trim-until-days <n>             Trim to entries up to N days ago (local time).
  --dry-run                        Dry-run report; writes to *_dry_run outputs.
  -h, --help                       Show help.
EOF
}

profile="quick"
tag=""
index_path=""
include_env=0
keep_going=0
summary_limit=20
stats_limit=200
prune_keep=0
emit_csv=1
rollup_days=30
emit_dashboard=1
emit_schema=1
dry_run=0
log_path=""
diff_against=""
gate_pass_rate="-1"
gate_window=0
gate_max_fail_streak="-1"
gate_max_fail_count="-1"
gate_allow_empty=0
trim_since=""
trim_until=""
trim_since_days="-1"
trim_until_days="-1"
status_path="docs/STATUS.md"
emit_status_snapshot=1
status_diff_against=""
emit_latest_summary=1
trend_window=20
emit_trend=1
emit_profile_summary=1
emit_tag_summary=1
emit_audit=0
audit_allow_missing=0
audit_max_missing=-1
collect_count=0
collect_dir="build/reports/readiness_collect"
collect_include_dry_run=0
collect_copy_logs=0
collect_pack=0
collect_pack_out="build/reports/readiness_collect.tar.gz"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --index)
      index_path="${2:-}"
      shift 2
      ;;
    --include-env)
      include_env=1
      shift
      ;;
    --keep-going)
      keep_going=1
      shift
      ;;
    --summary-limit)
      summary_limit="${2:-}"
      shift 2
      ;;
    --stats-limit)
      stats_limit="${2:-}"
      shift 2
      ;;
    --no-csv)
      emit_csv=0
      shift
      ;;
    --rollup-days)
      rollup_days="${2:-}"
      shift 2
      ;;
    --no-dashboard)
      emit_dashboard=0
      shift
      ;;
    --no-schema)
      emit_schema=0
      shift
      ;;
    --log)
      log_path="${2:-}"
      shift 2
      ;;
    --diff-against)
      diff_against="${2:-}"
      shift 2
      ;;
    --gate-pass-rate)
      gate_pass_rate="${2:-}"
      shift 2
      ;;
    --gate-window)
      gate_window="${2:-}"
      shift 2
      ;;
    --gate-max-fail-streak)
      gate_max_fail_streak="${2:-}"
      shift 2
      ;;
    --gate-max-fail-count)
      gate_max_fail_count="${2:-}"
      shift 2
      ;;
    --gate-allow-empty)
      gate_allow_empty=1
      shift
      ;;
    --status-path)
      status_path="${2:-}"
      shift 2
      ;;
    --no-status-snapshot)
      emit_status_snapshot=0
      shift
      ;;
    --status-diff-against)
      status_diff_against="${2:-}"
      shift 2
      ;;
    --no-latest-summary)
      emit_latest_summary=0
      shift
      ;;
    --trend-window)
      trend_window="${2:-}"
      shift 2
      ;;
    --no-trend)
      emit_trend=0
      shift
      ;;
    --no-profile-summary)
      emit_profile_summary=0
      shift
      ;;
    --no-tag-summary)
      emit_tag_summary=0
      shift
      ;;
    --audit)
      emit_audit=1
      shift
      ;;
    --audit-allow-missing)
      audit_allow_missing=1
      shift
      ;;
    --audit-max-missing)
      audit_max_missing="${2:-}"
      shift 2
      ;;
    --collect)
      collect_count="${2:-}"
      shift 2
      ;;
    --collect-dir)
      collect_dir="${2:-}"
      shift 2
      ;;
    --collect-include-dry-run)
      collect_include_dry_run=1
      shift
      ;;
    --collect-copy-logs)
      collect_copy_logs=1
      shift
      ;;
    --collect-pack)
      collect_pack=1
      shift
      ;;
    --collect-pack-out)
      collect_pack_out="${2:-}"
      shift 2
      ;;
    --trim-since)
      trim_since="${2:-}"
      shift 2
      ;;
    --trim-until)
      trim_until="${2:-}"
      shift 2
      ;;
    --trim-since-days)
      trim_since_days="${2:-}"
      shift 2
      ;;
    --trim-until-days)
      trim_until_days="${2:-}"
      shift 2
      ;;
    --prune)
      prune_keep="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$index_path" ]]; then
  if [[ "$dry_run" == "1" ]]; then
    index_path="build/reports/readiness_index_dry_run.jsonl"
  else
    index_path="build/reports/readiness_index.jsonl"
  fi
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
log_dir="build/logs"
mkdir -p "$log_dir" "build/reports"
if [[ -n "$log_path" ]]; then
  log="$log_path"
  mkdir -p "$(dirname "$log")"
else
  log="${log_dir}/readiness_pipeline_${timestamp}.log"
fi

summary_md="build/reports/readiness_summary.md"
summary_html="build/reports/readiness_summary.html"
stats_md="build/reports/readiness_index_stats.md"
stats_json="build/reports/readiness_index_stats.json"
csv_path="build/reports/readiness_index.csv"
rollup_md="build/reports/readiness_rollup.md"
rollup_json="build/reports/readiness_rollup.json"
dashboard_html="build/reports/readiness_dashboard.html"
diff_summary_md="build/reports/readiness_index_diff_summary.md"
diff_summary_json="build/reports/readiness_index_diff_summary.json"
status_snapshot_md="build/reports/status_snapshot.md"
status_snapshot_json="build/reports/status_snapshot.json"
status_snapshot_diff_md="build/reports/status_snapshot_diff.md"
status_snapshot_diff_json="build/reports/status_snapshot_diff.json"
latest_md="build/reports/readiness_index_latest.md"
latest_json="build/reports/readiness_index_latest.json"
trend_md="build/reports/readiness_index_trend.md"
trend_json="build/reports/readiness_index_trend.json"
profiles_md="build/reports/readiness_index_profiles.md"
profiles_json="build/reports/readiness_index_profiles.json"
tags_md="build/reports/readiness_index_tags.md"
tags_json="build/reports/readiness_index_tags.json"
audit_md="build/reports/readiness_index_audit.md"
audit_json="build/reports/readiness_index_audit.json"

if [[ "$dry_run" == "1" ]]; then
  summary_md="build/reports/readiness_summary_dry_run.md"
  summary_html="build/reports/readiness_summary_dry_run.html"
  stats_md="build/reports/readiness_index_stats_dry_run.md"
  stats_json="build/reports/readiness_index_stats_dry_run.json"
  csv_path="build/reports/readiness_index_dry_run.csv"
  rollup_md="build/reports/readiness_rollup_dry_run.md"
  rollup_json="build/reports/readiness_rollup_dry_run.json"
  dashboard_html="build/reports/readiness_dashboard_dry_run.html"
  diff_summary_md="build/reports/readiness_index_diff_summary_dry_run.md"
  diff_summary_json="build/reports/readiness_index_diff_summary_dry_run.json"
  status_snapshot_md="build/reports/status_snapshot_dry_run.md"
  status_snapshot_json="build/reports/status_snapshot_dry_run.json"
  status_snapshot_diff_md="build/reports/status_snapshot_diff_dry_run.md"
  status_snapshot_diff_json="build/reports/status_snapshot_diff_dry_run.json"
  latest_md="build/reports/readiness_index_latest_dry_run.md"
  latest_json="build/reports/readiness_index_latest_dry_run.json"
  trend_md="build/reports/readiness_index_trend_dry_run.md"
  trend_json="build/reports/readiness_index_trend_dry_run.json"
  profiles_md="build/reports/readiness_index_profiles_dry_run.md"
  profiles_json="build/reports/readiness_index_profiles_dry_run.json"
  tags_md="build/reports/readiness_index_tags_dry_run.md"
  tags_json="build/reports/readiness_index_tags_dry_run.json"
  audit_md="build/reports/readiness_index_audit_dry_run.md"
  audit_json="build/reports/readiness_index_audit_dry_run.json"
fi

report_args=(--profile "$profile" --json --index "$index_path")
if [[ -n "$tag" ]]; then
  report_args+=(--tag "$tag")
fi
if [[ -n "$status_path" ]]; then
  report_args+=(--status-path "$status_path")
fi
if [[ -n "$status_diff_against" ]]; then
  emit_status_snapshot=1
fi
if [[ "$include_env" == "1" ]]; then
  report_args+=(--include-env)
fi
if [[ "$keep_going" == "1" ]]; then
  report_args+=(--keep-going)
fi
if [[ "$dry_run" == "1" ]]; then
  report_args+=(--dry-run --no-latest)
fi

{
  echo "== readiness pipeline =="
  echo "timestamp=${timestamp}"
  echo "profile=${profile}"
  echo "tag=${tag}"
  echo "index=${index_path}"
  echo "dry_run=${dry_run}"
  echo "summary_limit=${summary_limit}"
  echo "stats_limit=${stats_limit}"
  echo "prune_keep=${prune_keep}"
  echo "trim_since=${trim_since}"
  echo "trim_until=${trim_until}"
  echo "trim_since_days=${trim_since_days}"
  echo "trim_until_days=${trim_until_days}"
  echo "status_path=${status_path}"
  echo "status_snapshot=${emit_status_snapshot}"
  echo "status_diff_against=${status_diff_against}"
  echo "latest_summary=${emit_latest_summary}"
  echo "trend_window=${trend_window}"
  echo "trend=${emit_trend}"
  echo "profiles=${emit_profile_summary}"
  echo "tags=${emit_tag_summary}"
  echo "audit=${emit_audit}"
  echo "audit_allow_missing=${audit_allow_missing}"
  echo "audit_max_missing=${audit_max_missing}"
  echo "collect_count=${collect_count}"
  echo "collect_dir=${collect_dir}"
  echo "collect_include_dry_run=${collect_include_dry_run}"
  echo "collect_copy_logs=${collect_copy_logs}"
  echo "collect_pack=${collect_pack}"
  echo "collect_pack_out=${collect_pack_out}"
  echo ""
  ./scripts/readiness_report.sh "${report_args[@]}"
  if [[ -n "$trim_since" || -n "$trim_until" || "$trim_since_days" != "-1" || "$trim_until_days" != "-1" ]]; then
    trim_args=(--index "$index_path")
    if [[ -n "$trim_since" ]]; then
      trim_args+=(--since "$trim_since")
    fi
    if [[ -n "$trim_until" ]]; then
      trim_args+=(--until "$trim_until")
    fi
    if [[ "$trim_since_days" != "-1" ]]; then
      trim_args+=(--since-days "$trim_since_days")
    fi
    if [[ "$trim_until_days" != "-1" ]]; then
      trim_args+=(--until-days "$trim_until_days")
    fi
    ./scripts/readiness_report_index_trim.py "${trim_args[@]}"
  fi
  ./scripts/readiness_report_summary.py --index "$index_path" --limit "$summary_limit" \
    --out-md "$summary_md" --out-html "$summary_html"
  ./scripts/readiness_report_index_stats.py --index "$index_path" --limit "$stats_limit" \
    --out-md "$stats_md" --out-json "$stats_json"
  ./scripts/readiness_report_index_rollup.py --index "$index_path" --limit-days "$rollup_days" \
    --out-md "$rollup_md" --out-json "$rollup_json"
  if [[ "$emit_dashboard" == "1" ]]; then
    ./scripts/readiness_report_dashboard.py --index "$index_path" --out-html "$dashboard_html" \
      --limit "$summary_limit" --rollup-days "$rollup_days" --trend-json "$trend_json" \
      --profiles-json "$profiles_json" --tags-json "$tags_json"
  fi
  if [[ "$emit_schema" == "1" ]]; then
    ./scripts/readiness_report_index_validate_schema.py --index "$index_path" --schema "docs/readiness_index.schema.json"
  fi
  if [[ "$emit_latest_summary" == "1" ]]; then
    ./scripts/readiness_report_index_latest.py --index "$index_path" --out-md "$latest_md" --out-json "$latest_json"
  fi
  if [[ "$emit_trend" == "1" ]]; then
    ./scripts/readiness_report_index_trend.py --index "$index_path" --window "$trend_window" \
      --out-md "$trend_md" --out-json "$trend_json"
  fi
  if [[ "$emit_profile_summary" == "1" ]]; then
    ./scripts/readiness_report_index_profiles.py --index "$index_path" --out-md "$profiles_md" --out-json "$profiles_json"
  fi
  if [[ "$emit_tag_summary" == "1" ]]; then
    ./scripts/readiness_report_index_tags.py --index "$index_path" --out-md "$tags_md" --out-json "$tags_json"
  fi
  if [[ "$emit_audit" == "1" ]]; then
    audit_args=(--index "$index_path" --out-md "$audit_md" --out-json "$audit_json")
    if [[ "$audit_allow_missing" == "1" ]]; then
      audit_args+=(--allow-missing)
    fi
    if [[ "$audit_max_missing" != "-1" ]]; then
      audit_args+=(--max-missing "$audit_max_missing")
    fi
    if [[ "$dry_run" == "1" ]]; then
      audit_args+=(--include-dry-run)
    fi
    ./scripts/readiness_report_index_audit.py "${audit_args[@]}"
  fi
  if [[ "$collect_count" =~ ^[0-9]+$ && "$collect_count" -gt 0 ]]; then
    collect_args=(--index "$index_path" --out-dir "$collect_dir" --limit "$collect_count" --overwrite)
    if [[ "$collect_include_dry_run" == "1" ]]; then
      collect_args+=(--include-dry-run)
    fi
    if [[ "$collect_copy_logs" == "1" ]]; then
      collect_args+=(--copy-logs)
    fi
    ./scripts/readiness_report_collect.py "${collect_args[@]}"
    ./scripts/readiness_report_collect_list.py --dir "$collect_dir" --out "$collect_dir/readiness_collect_index.md" \
      --out-json "$collect_dir/readiness_collect_index.json"
    if [[ "$collect_pack" == "1" ]]; then
      ./scripts/readiness_report_collect_pack.py --dir "$collect_dir" --out "$collect_pack_out" --prefix "readiness_collect"
    fi
  fi
  if [[ "$emit_status_snapshot" == "1" ]]; then
    ./scripts/status_snapshot.py --status "$status_path" --out-md "$status_snapshot_md" --out-json "$status_snapshot_json"
  fi
  if [[ -n "$status_diff_against" ]]; then
    ./scripts/status_snapshot_diff.py --left "$status_diff_against" --right "$status_path" \
      --out-md "$status_snapshot_diff_md" --out-json "$status_snapshot_diff_json"
  fi
  if [[ -n "$diff_against" ]]; then
    ./scripts/readiness_report_index_diff_summary.py --left "$diff_against" --right "$index_path" \
      --out-md "$diff_summary_md" --out-json "$diff_summary_json"
  fi
  if [[ "$gate_pass_rate" != "-1" || "$gate_max_fail_streak" != "-1" || "$gate_max_fail_count" != "-1" ]]; then
    gate_args=(--index "$index_path" --window "$gate_window")
    if [[ "$gate_pass_rate" != "-1" ]]; then
      gate_args+=(--min-pass-rate "$gate_pass_rate")
    fi
    if [[ "$gate_max_fail_streak" != "-1" ]]; then
      gate_args+=(--max-fail-streak "$gate_max_fail_streak")
    fi
    if [[ "$gate_max_fail_count" != "-1" ]]; then
      gate_args+=(--max-fail-count "$gate_max_fail_count")
    fi
    if [[ "$gate_allow_empty" == "1" ]]; then
      gate_args+=(--allow-empty)
    fi
    ./scripts/readiness_report_index_gate.py "${gate_args[@]}"
  fi
  if [[ "$emit_csv" == "1" ]]; then
    ./scripts/readiness_report_index_export_csv.py --index "$index_path" --out-csv "$csv_path"
  fi
  ./scripts/readiness_report_index_validate.py --index "$index_path"
  if [[ "$prune_keep" =~ ^[0-9]+$ && "$prune_keep" -gt 0 ]]; then
    ./scripts/readiness_report_index_prune.py --index "$index_path" --keep "$prune_keep"
  fi
} >"$log" 2>&1

echo "OK: readiness pipeline completed"
echo "log: ${log}"
