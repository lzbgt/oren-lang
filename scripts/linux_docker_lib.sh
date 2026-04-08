#!/usr/bin/env bash

# Shared helpers for resolving the repo's persistent Linux toolchain container.
#
# Contract:
# - `OREN_LINUX_DOCKER_ID` may be a container name, a full ID, or an unambiguous ID prefix.
# - default ref remains the documented persistent container name: `c7e5f7bd9f5c`
# - callers receive the resolved running container ID for `docker exec/cp`

linux_docker_default_ref() {
  printf '%s\n' "${OREN_LINUX_DOCKER_ID:-c7e5f7bd9f5c}"
}

linux_docker_running_table() {
  docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}'
}

linux_docker_describe_running() {
  linux_docker_running_table | while IFS=$'\t' read -r cid cname cimage cstatus; do
    [[ -n "$cid" ]] || continue
    printf '  - %s (%s) image=%s status=%s\n' "$cname" "$cid" "$cimage" "$cstatus"
  done
}

linux_docker_resolve_running() {
  local ref="${1:-}"
  local table=""
  local exact_id=""
  local exact_name=""
  local prefix_matches=""
  local match_count=0

  if [[ -z "$ref" ]]; then
    ref="$(linux_docker_default_ref)"
  fi

  table="$(linux_docker_running_table)"

  exact_id="$(printf '%s\n' "$table" | awk -F '\t' -v ref="$ref" '$1 == ref { print $1; exit }')"
  if [[ -n "$exact_id" ]]; then
    printf '%s\n' "$exact_id"
    return 0
  fi

  exact_name="$(printf '%s\n' "$table" | awk -F '\t' -v ref="$ref" '$2 == ref { print $1; exit }')"
  if [[ -n "$exact_name" ]]; then
    printf '%s\n' "$exact_name"
    return 0
  fi

  prefix_matches="$(printf '%s\n' "$table" | awk -F '\t' -v ref="$ref" 'index($1, ref) == 1 { print $1 }')"
  if [[ -n "$prefix_matches" ]]; then
    match_count="$(printf '%s\n' "$prefix_matches" | awk 'NF { n += 1 } END { print n + 0 }')"
    if [[ "$match_count" == "1" ]]; then
      printf '%s\n' "$prefix_matches"
      return 0
    fi
    echo "ERROR: OREN_LINUX_DOCKER_ID matched multiple running container IDs: ${ref}" >&2
    linux_docker_describe_running >&2 || true
    return 2
  fi

  return 1
}

linux_docker_require_running() {
  local ref="${1:-}"
  local resolved=""

  if [[ -z "$ref" ]]; then
    ref="$(linux_docker_default_ref)"
  fi

  if resolved="$(linux_docker_resolve_running "$ref")"; then
    printf '%s\n' "$resolved"
    return 0
  fi

  echo "ERROR: required Linux container is not running or could not be resolved: ${ref}" >&2
  echo "hint: OREN_LINUX_DOCKER_ID accepts a container name, full ID, or unambiguous ID prefix." >&2
  echo "running containers:" >&2
  linux_docker_describe_running >&2 || true
  return 2
}
