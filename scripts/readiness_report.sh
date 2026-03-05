#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/readiness_report.sh [options]

Options:
  --profile <minimal|quick|full>  Selects the verification profile (default: quick).
  --minimal                       Alias for --profile minimal.
  --full                          Alias for --profile full.
  --out <path>                    Write the report markdown to <path>.
  --json [path]                   Write a JSON summary (default path if omitted).
  --index [path]                  Append a JSONL summary (default path if omitted).
  --tag <name>                    Attach a tag to the report (e.g., ci/nightly).
  --status-path <path>            STATUS.md path (default: docs/STATUS.md).
  --status-snapshot [dir]         Write status snapshot md/json (default: build/reports).
  --update-latest                 Write build/reports/readiness_latest.* (auto on real runs).
  --no-latest                     Skip latest report copies.
  --no-status-snippet             Omit docs/STATUS.md readiness sections.
  --include-env                   Include OREN_* environment variables in the report.
  --keep-going                    Run all steps even if one fails.
  --dry-run                       Print the plan without running commands.
  -h, --help                      Show this help.

Profiles:
  minimal: make verify-native-quick
  quick:   make verify-native-quick-simd + make verify-backend-parity
  full:    quick + make verify-native-quick-gc + make verify-runtime-robustness
EOF
}

profile="quick"
out_path=""
json_path=""
index_path=""
index_enabled=0
tag=""
update_latest=1
update_latest_requested=0
include_status=1
include_env=0
keep_going=0
dry_run=0
status_path="docs/STATUS.md"
status_snapshot_enabled=0
status_snapshot_dir=""
status_snapshot_md=""
status_snapshot_json=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --minimal)
      profile="minimal"
      shift
      ;;
    --full)
      profile="full"
      shift
      ;;
    --out)
      out_path="${2:-}"
      shift 2
      ;;
    --json)
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        json_path="$2"
        shift 2
      else
        json_path="auto"
        shift
      fi
      ;;
    --index)
      index_enabled=1
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        index_path="$2"
        shift 2
      else
        index_path="auto"
        shift
      fi
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --status-path)
      status_path="${2:-}"
      shift 2
      ;;
    --status-snapshot)
      status_snapshot_enabled=1
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
        status_snapshot_dir="$2"
        shift 2
      else
        shift
      fi
      ;;
    --update-latest)
      update_latest=1
      update_latest_requested=1
      shift
      ;;
    --no-latest)
      update_latest=0
      shift
      ;;
    --no-status-snippet)
      include_status=0
      shift
      ;;
    --include-env)
      include_env=1
      shift
      ;;
    --keep-going)
      keep_going=1
      shift
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

if [[ "$profile" != "minimal" && "$profile" != "quick" && "$profile" != "full" ]]; then
  echo "ERROR: invalid profile: $profile" >&2
  usage >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
report_dir="build/reports"
log_dir="build/logs/readiness_${timestamp}"

mkdir -p "$report_dir" "$log_dir"

if [[ -z "$out_path" ]]; then
  out_path="${report_dir}/readiness_report_${timestamp}.md"
else
  mkdir -p "$(dirname "$out_path")"
fi

if [[ -n "$json_path" ]]; then
  if [[ "$json_path" == "auto" ]]; then
    json_path="${report_dir}/readiness_report_${timestamp}.json"
  else
    mkdir -p "$(dirname "$json_path")"
  fi
fi

if [[ "$index_enabled" == "1" ]]; then
  if [[ -z "$index_path" || "$index_path" == "auto" ]]; then
    index_path="${report_dir}/readiness_index.jsonl"
  else
    mkdir -p "$(dirname "$index_path")"
  fi
fi

if [[ "$status_snapshot_enabled" == "1" ]]; then
  if [[ -z "$status_snapshot_dir" ]]; then
    status_snapshot_dir="$report_dir"
  fi
  mkdir -p "$status_snapshot_dir"
  status_snapshot_md="${status_snapshot_dir}/status_snapshot_${timestamp}.md"
  status_snapshot_json="${status_snapshot_dir}/status_snapshot_${timestamp}.json"
fi

if [[ "$dry_run" == "1" && "$update_latest_requested" == "0" ]]; then
  update_latest=0
fi

git_rev="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
git_status="$(git status --porcelain 2>/dev/null || true)"
git_dirty="clean"
if [[ -n "$git_status" ]]; then
  git_dirty="dirty"
fi

uname_s="$(uname -s)"
uname_m="$(uname -m)"

declare -a step_names
declare -a step_cmds
declare -a step_logs
declare -a step_results
declare -a step_durations

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

extract_status_section() {
  local title="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  awk -v title="$title" '
    $0 ~ "^#" {
      if (printing) exit
      header=$0
      sub(/^#+[[:space:]]+/, "", header)
      if (index(header, title) == 1) {
        printing=1
        print
        next
      }
    }
    printing { print }
  ' "$file"
}

add_step() {
  step_names+=("$1")
  step_cmds+=("$2")
}

case "$profile" in
  minimal)
    add_step "verify-native-quick" "make verify-native-quick"
    ;;
  quick)
    add_step "verify-native-quick-simd" "make verify-native-quick-simd"
    add_step "verify-backend-parity" "make verify-backend-parity"
    ;;
  full)
    add_step "verify-native-quick-simd" "make verify-native-quick-simd"
    add_step "verify-backend-parity" "make verify-backend-parity"
    add_step "verify-native-quick-gc" "make verify-native-quick-gc"
    add_step "verify-runtime-robustness" "make verify-runtime-robustness"
    ;;
esac

run_step() {
  local name="$1"
  local cmd="$2"
  local log="${log_dir}/${name}.log"
  local start_ts
  local end_ts
  local duration
  local rc=0

  start_ts="$(date +%s)"
  if [[ "$dry_run" == "1" ]]; then
    rc=0
  else
    set +e
    eval "$cmd" >"$log" 2>&1
    rc=$?
    set -e
  fi
  end_ts="$(date +%s)"
  duration="$((end_ts - start_ts))"

  step_logs+=("$log")
  step_durations+=("$duration")
  if [[ "$rc" -eq 0 ]]; then
    step_results+=("OK")
  else
    step_results+=("FAIL ($rc)")
  fi
  return "$rc"
}

had_failure=0
first_failure_rc=0
aborted=0

for i in "${!step_names[@]}"; do
  name="${step_names[$i]}"
  cmd="${step_cmds[$i]}"

  echo "== readiness: ${name} =="
  echo "cmd: ${cmd}"
  if [[ "$dry_run" == "1" ]]; then
    echo "dry-run: skipping execution"
  else
    echo "log: ${log_dir}/${name}.log"
  fi

  run_step "$name" "$cmd"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "result: OK"
  else
    echo "result: FAIL"
    had_failure=1
    if [[ "$first_failure_rc" -eq 0 ]]; then
      first_failure_rc="$rc"
    fi
    if [[ "$keep_going" != "1" ]]; then
      aborted=1
      break
    fi
  fi
done

overall="PASS"
if [[ "$had_failure" == "1" ]]; then
  overall="FAIL"
fi

total_duration=0
for d in "${step_durations[@]}"; do
  if [[ -n "$d" ]]; then
    total_duration=$((total_duration + d))
  fi
done

status_backend=""
status_feature=""
if [[ "$include_status" == "1" ]]; then
  status_prod="$(extract_status_section "Production readiness gap (rolling snapshot)" "$status_path")"
  status_backend="$(extract_status_section "Backend readiness (rolling snapshot)" "$status_path")"
  status_feature="$(extract_status_section "Feature readiness gaps (requested)" "$status_path")"
fi

git_diff_stat=""
if [[ "$git_dirty" == "dirty" ]]; then
  git_diff_stat="$(git diff --stat 2>/dev/null || true)"
fi

env_lines=""
if [[ "$include_env" == "1" ]]; then
  if command -v rg >/dev/null 2>&1; then
    env_lines="$(env | rg '^OREN_' | sort || true)"
  else
    env_lines="$(env | grep '^OREN_' | sort || true)"
  fi
fi

{
  echo "# Oren readiness report"
  echo ""
  echo "- timestamp: ${timestamp}"
  echo "- profile: ${profile}"
  if [[ -n "$tag" ]]; then
    echo "- tag: ${tag}"
  fi
  echo "- host: ${uname_s} ${uname_m}"
  echo "- git: ${git_rev} (${git_dirty})"
  echo "- logs: ${log_dir}"
  if [[ -n "$json_path" ]]; then
    echo "- json: ${json_path}"
  fi
  if [[ "$index_enabled" == "1" ]]; then
    echo "- index: ${index_path}"
  fi
  if [[ "$status_snapshot_enabled" == "1" ]]; then
    echo "- status_snapshot_md: ${status_snapshot_md}"
    echo "- status_snapshot_json: ${status_snapshot_json}"
  fi
  echo "- total_duration_sec: ${total_duration}"
  echo "- dry-run: ${dry_run}"
  echo ""
  echo "## Summary"
  echo ""
  echo "- overall: ${overall}"
  if [[ "$aborted" == "1" ]]; then
    echo "- note: aborted early on first failure (use --keep-going to run all steps)"
  fi
  echo ""
  echo "## Steps"
  echo ""
  for i in "${!step_names[@]}"; do
    name="${step_names[$i]}"
    cmd="${step_cmds[$i]}"
    log="${step_logs[$i]:-}"
    result="${step_results[$i]:-SKIPPED}"
    duration="${step_durations[$i]:-0}"
    if [[ "$dry_run" == "1" ]]; then
      echo "- ${name}: ${result} (${duration}s)"
      echo "  - cmd: \`${cmd}\`"
    else
      echo "- ${name}: ${result} (${duration}s)"
      echo "  - cmd: \`${cmd}\`"
      echo "  - log: \`${log}\`"
    fi
  done
  if [[ "$include_status" == "1" && ( -n "$status_prod" || -n "$status_backend" || -n "$status_feature" ) ]]; then
    echo ""
    echo "## Status snapshot (docs/STATUS.md)"
    echo ""
    if [[ -n "$status_prod" ]]; then
      echo "$status_prod"
      echo ""
    fi
    if [[ -n "$status_backend" ]]; then
      echo "$status_backend"
      echo ""
    fi
    if [[ -n "$status_feature" ]]; then
      echo "$status_feature"
      echo ""
    fi
  fi
  if [[ "$include_env" == "1" ]]; then
    echo ""
    echo "## Environment (OREN_*)"
    echo ""
    if [[ -n "$env_lines" ]]; then
      echo '```'
      echo "$env_lines"
      echo '```'
    else
      echo "- none"
    fi
  fi
  if [[ "$git_dirty" == "dirty" && -n "$git_diff_stat" ]]; then
    echo ""
    echo "## Workspace diff"
    echo ""
    echo '```'
    echo "$git_diff_stat"
    echo '```'
  fi
} >"$out_path"

if [[ "$status_snapshot_enabled" == "1" ]]; then
  ./scripts/status_snapshot.py --status "$status_path" --out-md "$status_snapshot_md" --out-json "$status_snapshot_json"
fi

if [[ -n "$json_path" ]]; then
  readarray -t git_status_lines <<<"$git_status"
  readarray -t env_entries <<<"$env_lines"
  {
    echo "{"
    echo "  \"timestamp\": \"$(json_escape "$timestamp")\","
    echo "  \"profile\": \"$(json_escape "$profile")\","
    echo "  \"host\": {"
    echo "    \"os\": \"$(json_escape "$uname_s")\","
    echo "    \"arch\": \"$(json_escape "$uname_m")\""
    echo "  },"
    echo "  \"git\": {"
    echo "    \"rev\": \"$(json_escape "$git_rev")\","
    if [[ "$git_dirty" == "dirty" ]]; then
      echo "    \"dirty\": true,"
    else
      echo "    \"dirty\": false,"
    fi
    echo "    \"status\": ["
    for i in "${!git_status_lines[@]}"; do
      line="${git_status_lines[$i]}"
      comma=","
      if [[ "$i" -eq $((${#git_status_lines[@]} - 1)) ]]; then
        comma=""
      fi
      echo "      \"$(json_escape "$line")\"${comma}"
    done
    echo "    ],"
    echo "    \"diff_stat\": \"$(json_escape "$git_diff_stat")\""
    echo "  },"
    echo "  \"paths\": {"
    echo "    \"report\": \"$(json_escape "$out_path")\","
    echo "    \"logs\": \"$(json_escape "$log_dir")\","
    echo "    \"json\": \"$(json_escape "$json_path")\""
    if [[ "$index_enabled" == "1" ]]; then
      echo "    ,\"index\": \"$(json_escape "$index_path")\""
    fi
    if [[ "$status_snapshot_enabled" == "1" ]]; then
      echo "    ,\"status_snapshot_md\": \"$(json_escape "$status_snapshot_md")\""
      echo "    ,\"status_snapshot_json\": \"$(json_escape "$status_snapshot_json")\""
    fi
    echo "  },"
    if [[ -n "$tag" ]]; then
      echo "  \"tag\": \"$(json_escape "$tag")\","
    fi
    if [[ "$dry_run" == "1" ]]; then
      echo "  \"dry_run\": true,"
    else
      echo "  \"dry_run\": false,"
    fi
    echo "  \"overall\": \"$(json_escape "$overall")\","
    echo "  \"total_duration_sec\": ${total_duration},"
    echo "  \"steps\": ["
    for i in "${!step_names[@]}"; do
      name="${step_names[$i]}"
      cmd="${step_cmds[$i]}"
      log="${step_logs[$i]:-}"
      result="${step_results[$i]:-SKIPPED}"
      duration="${step_durations[$i]:-0}"
      comma=","
      if [[ "$i" -eq $((${#step_names[@]} - 1)) ]]; then
        comma=""
      fi
      echo "    {"
      echo "      \"name\": \"$(json_escape "$name")\","
      echo "      \"cmd\": \"$(json_escape "$cmd")\","
      echo "      \"result\": \"$(json_escape "$result")\","
      echo "      \"duration_sec\": ${duration},"
      echo "      \"log\": \"$(json_escape "$log")\""
      echo "    }${comma}"
    done
    echo "  ]"
    if [[ "$include_status" == "1" ]]; then
      echo "  ,\"status_snapshot\": {"
      echo "    \"production_readiness_gap\": \"$(json_escape "$status_prod")\","
      echo "    \"backend_readiness\": \"$(json_escape "$status_backend")\","
      echo "    \"feature_gaps\": \"$(json_escape "$status_feature")\""
      echo "  }"
    fi
    if [[ "$include_env" == "1" ]]; then
      echo "  ,\"env\": ["
      for i in "${!env_entries[@]}"; do
        line="${env_entries[$i]}"
        comma=","
        if [[ "$i" -eq $((${#env_entries[@]} - 1)) ]]; then
          comma=""
        fi
        echo "    \"$(json_escape "$line")\"${comma}"
      done
      echo "  ]"
    fi
    echo "}"
  } >"$json_path"
fi

if [[ "$index_enabled" == "1" ]]; then
  idx_json="{\"timestamp\":\"$(json_escape "$timestamp")\",\"profile\":\"$(json_escape "$profile")\",\"overall\":\"$(json_escape "$overall")\",\"dry_run\":"
  if [[ "$dry_run" == "1" ]]; then
    idx_json+="true"
  else
    idx_json+="false"
  fi
  idx_json+=",\"total_duration_sec\":${total_duration},\"git_rev\":\"$(json_escape "$git_rev")\",\"git_dirty\":\"$(json_escape "$git_dirty")\",\"report\":\"$(json_escape "$out_path")\",\"json\":\"$(json_escape "$json_path")\",\"log_dir\":\"$(json_escape "$log_dir")\""
  if [[ "$status_snapshot_enabled" == "1" ]]; then
    idx_json+=",\"status_snapshot_md\":\"$(json_escape "$status_snapshot_md")\",\"status_snapshot_json\":\"$(json_escape "$status_snapshot_json")\""
  fi
  if [[ -n "$tag" ]]; then
    idx_json+=",\"tag\":\"$(json_escape "$tag")\""
  fi
  idx_json+="}"
  echo "$idx_json" >>"$index_path"
fi

if [[ "$update_latest" == "1" ]]; then
  latest_md="${report_dir}/readiness_latest.md"
  cp -f "$out_path" "$latest_md"
  if [[ -n "$json_path" ]]; then
    latest_json="${report_dir}/readiness_latest.json"
    cp -f "$json_path" "$latest_json"
  fi
  {
    echo "timestamp=${timestamp}"
    echo "profile=${profile}"
    if [[ -n "$tag" ]]; then
      echo "tag=${tag}"
    fi
    echo "overall=${overall}"
    echo "dry_run=${dry_run}"
    echo "total_duration_sec=${total_duration}"
    echo "report=${out_path}"
    if [[ -n "$json_path" ]]; then
      echo "json=${json_path}"
    fi
    if [[ "$status_snapshot_enabled" == "1" ]]; then
      echo "status_snapshot_md=${status_snapshot_md}"
      echo "status_snapshot_json=${status_snapshot_json}"
    fi
    if [[ "$index_enabled" == "1" ]]; then
      echo "index=${index_path}"
    fi
    echo "log_dir=${log_dir}"
  } >"${report_dir}/readiness_latest.meta"
fi

echo "== readiness report =="
echo "report: ${out_path}"
if [[ -n "$json_path" ]]; then
  echo "json: ${json_path}"
fi
if [[ "$index_enabled" == "1" ]]; then
  echo "index: ${index_path}"
fi
echo "overall: ${overall}"

if [[ "$had_failure" == "1" ]]; then
  exit "${first_failure_rc:-1}"
fi
