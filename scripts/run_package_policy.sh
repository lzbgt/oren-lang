#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: scripts/run_package_policy.sh --backend avm|native [--gas-profile native-stmt|avm-sidecar|auto] <source.oren> [-- <run-args...>]

Dispatches package-policy execution to the backend-specific runner. This keeps
`@oren.package(...)` policy application discoverable as one command while the
AVM and native backends still have different enforcement surfaces.

--gas-profile applies only to the native backend:
  native-stmt   enforce budget_gas with native statement+loop gas
  avm-sidecar   enforce budget_gas with package-bound AVM canonical sidecar gas
  auto          choose avm-sidecar when the package declares budget_gas (dispatcher default)
EOF
}

backend=""
gas_profile=""
while [[ "$#" -gt 0 ]]; do
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --backend)
      if [[ "$#" -lt 2 ]]; then
        echo "ERROR: --backend requires avm|native" >&2
        usage
        exit 2
      fi
      backend="${2:-}"
      shift 2
      ;;
    --backend=*)
      backend="${1#--backend=}"
      shift
      ;;
    --gas-profile)
      if [[ "$#" -lt 2 ]]; then
        echo "ERROR: --gas-profile requires native-stmt|avm-sidecar|auto" >&2
        usage
        exit 2
      fi
      gas_profile="${2:-}"
      shift 2
      ;;
    --gas-profile=*)
      gas_profile="${1#--gas-profile=}"
      shift
      ;;
    --)
      break
      ;;
    -*)
      echo "ERROR: unsupported package-policy option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$backend" || "$#" -lt 1 ]]; then
  usage
  exit 2
fi

case "$backend" in
  avm|bytecode)
    if [[ -n "$gas_profile" ]]; then
      echo "ERROR: --gas-profile applies only to --backend native" >&2
      exit 2
    fi
    exec "$ROOT/scripts/run_avm_package_policy.sh" "$@"
    ;;
  native)
    if [[ -n "$gas_profile" ]]; then
      export OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE="$gas_profile"
    elif [[ -z "${OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE:-}" ]]; then
      export OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE="auto"
    fi
    exec "$ROOT/scripts/run_native_package_policy.sh" "$@"
    ;;
  *)
    echo "ERROR: unsupported package-policy backend: $backend" >&2
    exit 2
    ;;
esac
