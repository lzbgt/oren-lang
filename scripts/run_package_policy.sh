#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: scripts/run_package_policy.sh --backend avm|native <source.oren> [-- <run-args...>]

Dispatches package-policy execution to the backend-specific runner. This keeps
`@oren.package(...)` policy application discoverable as one command while the
AVM and native backends still have different enforcement surfaces.
EOF
}

backend=""
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--backend" ]]; then
  backend="${2:-}"
  shift 2
elif [[ "${1:-}" == --backend=* ]]; then
  backend="${1#--backend=}"
  shift
fi

if [[ -z "$backend" || "$#" -lt 1 ]]; then
  usage
  exit 2
fi

case "$backend" in
  avm|bytecode)
    exec "$ROOT/scripts/run_avm_package_policy.sh" "$@"
    ;;
  native)
    exec "$ROOT/scripts/run_native_package_policy.sh" "$@"
    ;;
  *)
    echo "ERROR: unsupported package-policy backend: $backend" >&2
    exit 2
    ;;
esac
