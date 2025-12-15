#!/usr/bin/env bash
set -euo pipefail

# Local "swarm" harness (single machine): run an .obc multiple times and check k-of-n agreement
# on the AVM-reported STATE_HASH.
#
# Usage:
#   tools/avm_swarm_local.sh <file.obc> [n] [k] [mode]
#
#   mode:
#     state  (default)  -> --print-state-hash
#     result            -> --print-result-hash
#
# Notes:
# - This is a harness for deterministic consensus mode only (no real-world effects).
# - Configure capabilities via env vars if needed:
#     AVM_ALLOW_DOMAINS=0          # CORE only
#     AVM_VERIFY=1
#     AVM_GAS=...
#     AVM_TIMEOUT_MS=...

obc="${1:-}"
n="${2:-5}"
k="${3:-3}"
mode="${4:-state}"

if [[ -z "${obc}" ]]; then
  echo "usage: tools/avm_swarm_local.sh <file.obc> [n] [k] [mode]" >&2
  exit 2
fi

if [[ ! -f "${obc}" ]]; then
  echo "missing file: ${obc}" >&2
  exit 2
fi

if [[ "${k}" -gt "${n}" ]]; then
  echo "invalid: k (${k}) > n (${n})" >&2
  exit 2
fi

hashes=()
flag="--print-state-hash"
prefix="STATE_HASH"
if [[ "${mode}" == "result" ]]; then
  flag="--print-result-hash"
  prefix="RESULT_HASH"
elif [[ "${mode}" != "state" ]]; then
  echo "invalid mode: ${mode} (expected: state|result)" >&2
  exit 2
fi

for ((i=0; i<n; i++)); do
  out="$(./avm ${flag} --print-policy "${obc}")"
  h="$(echo "${out}" | awk -v p="${prefix}" '$1==p{print $2; exit 0}')"
  if [[ -z "${h}" ]]; then
    echo "run ${i}: missing ${prefix}" >&2
    echo "${out}" >&2
    exit 1
  fi
  hashes+=("${h}")
done

echo "Runs: ${n}"
printf "%s\n" "${hashes[@]}" | sort | uniq -c | sort -nr | head -n 10

top_count="$(printf "%s\n" "${hashes[@]}" | sort | uniq -c | sort -nr | head -n 1 | awk '{print $1}')"
top_hash="$(printf "%s\n" "${hashes[@]}" | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}')"

if [[ "${top_count}" -ge "${k}" ]]; then
  echo "CONSENSUS ok: ${top_count}/${n} agreed on ${top_hash}"
  exit 0
fi

echo "CONSENSUS fail: best agreement ${top_count}/${n} on ${top_hash} (< k=${k})" >&2
exit 1
