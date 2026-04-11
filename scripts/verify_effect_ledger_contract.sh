#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing file: $path"
}

require_literal() {
  local path="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$path" || fail "missing literal in $path: $needle"
}

contract="docs/EFFECT_LEDGER_CONTRACT.md"
cap_contract="docs/CAPABILITY_RUNTIME_CONTRACT.md"
docs_index="docs/README.md"
status_doc="docs/STATUS.md"
tasks_doc="docs/BLEEDING_EDGE_TASKS.md"
thesis_doc="docs/OREN_THESIS.md"
horizon_doc="project-doc/oren_feature_horizon_20260412.md"
bets_doc="project-doc/oren_language_system_bets_20260412.md"
avm_main="lib/avm/main.c"
avm_json_guard="scripts/verify_avm_effect_ledger_json.sh"
semantic_diff_runner="scripts/run_backend_semantic_diff.sh"
semantic_diff_guard="scripts/verify_backend_semantic_diff.sh"
native_policy_runner="scripts/run_native_package_policy.sh"

for f in \
  "$contract" \
  "$cap_contract" \
  "$docs_index" \
  "$status_doc" \
  "$tasks_doc" \
  "$thesis_doc" \
  "$horizon_doc" \
  "$bets_doc" \
  "$avm_main" \
  "$avm_json_guard" \
  "$semantic_diff_runner" \
  "$semantic_diff_guard" \
  "$native_policy_runner" \
  Makefile
do
  require_file "$f"
done

require_literal "$contract" "# Effect Ledger Contract"
require_literal "$contract" "schema and tooling"
require_literal "$contract" "## Effect Ledger v0"
require_literal "$contract" "\"schema\": \"oren.effect-ledger.v0\""
require_literal "$contract" "\"determinism_grade\": \"replayable-host\""
require_literal "$contract" "\"domain\": \"FS\""
require_literal "$contract" "\"operation\": \"read_file\""
require_literal "$contract" "\"decision\": \"allow\""
require_literal "$contract" "\"denial_reason\": null"
require_literal "$contract" "\"budget_delta\""
require_literal "$contract" "\"input_digest\""
require_literal "$contract" "\"output_digest\""
require_literal "$contract" "\"redaction\""
require_literal "$contract" "\"replay_mode\""
require_literal "$contract" "\"schedule_epoch\""
require_literal "$contract" "\"source_span\""
require_literal "$contract" "Denial is data"
require_literal "$contract" "backend-comparable"
require_literal "$contract" "make verify-effect-ledger-contract"
require_literal "$contract" "make verify-avm-effect-ledger-json"
require_literal "$contract" "effect_ledger_summary"
require_literal "$contract" "oren.effect-ledger-summary.v0"
require_literal "$contract" "\"determinism\""
require_literal "$contract" "\"wall_ms\""
require_literal "$contract" "oren.semantic-diff.v0"
require_literal "$contract" "oren.native-package-policy-run.v0"

require_literal "$cap_contract" "docs/EFFECT_LEDGER_CONTRACT.md"
require_literal "$cap_contract" "make verify-effect-ledger-contract"
require_literal "$docs_index" "docs/EFFECT_LEDGER_CONTRACT.md"
require_literal "$tasks_doc" "docs/EFFECT_LEDGER_CONTRACT.md"
require_literal "$status_doc" "Effect ledger contract"
require_literal "$status_doc" "make verify-backend-semantic-diff"
require_literal "$thesis_doc" "effect ledgers"
require_literal "$horizon_doc" "Effect-ledger"
require_literal "$bets_doc" "effect-ledger schema"
require_literal "$bets_doc" "scripts/run_backend_semantic_diff.sh"
require_literal Makefile "verify-effect-ledger-contract:"
require_literal Makefile "verify-avm-effect-ledger-json:"
require_literal Makefile "verify-backend-semantic-diff:"
require_literal Makefile "scripts/verify_effect_ledger_contract.sh"
require_literal Makefile "scripts/verify_avm_effect_ledger_json.sh"
require_literal Makefile "verify-effect-ledger-contract: verify-avm-effect-ledger-json"
require_literal Makefile "./scripts/verify_backend_semantic_diff.sh"
require_literal Makefile "test: verify-capability-runtime-contract verify-capability-metadata verify-capability-manifest-policy verify-effect-ledger-contract verify-avm-package-policy-runner verify-native-package-policy-runner verify-avm-spawn-channel-args test-native-quick"
require_literal "$avm_main" "print_effect_ledger_summary_json"
require_literal "$avm_main" "effect_ledger_summary"
require_literal "$avm_main" "oren.effect-ledger-summary.v0"
require_literal "$avm_main" "runtime_profile"
require_literal "$avm_main" "\\\"wall_ms\\\""
require_literal "scripts/verify_avm_effect_ledger_json.sh" "effect_ledger_summary"
require_literal "scripts/verify_avm_effect_ledger_json.sh" "AVM_LOG_BYTES=4"
require_literal "scripts/verify_avm_effect_ledger_json.sh" "AVM_TIMEOUT_MS=1000"
require_literal "scripts/verify_avm_effect_ledger_json.sh" "wall_ms"
require_literal "$semantic_diff_runner" "oren.semantic-diff.v0"
require_literal "$semantic_diff_runner" "stdout_sha256"
require_literal "$semantic_diff_runner" "expected_line_present_all"
require_literal "$semantic_diff_runner" "effect_ledger_summary"
require_literal "$semantic_diff_runner" "budget_deltas"
require_literal "$semantic_diff_runner" "obc_run_json_schema_ok"
require_literal "$semantic_diff_runner" "obc_effect_ledger_summary_schema_ok"
require_literal "$semantic_diff_runner" "ledger_available_backends"
require_literal "$semantic_diff_runner" "ledger_missing_backends"
require_literal "$semantic_diff_runner" "build/reports/"
require_literal "$semantic_diff_guard" "oren.semantic-diff.v0"
require_literal "$semantic_diff_guard" "obc_run_json_schema_ok"
require_literal "$semantic_diff_guard" "obc_effect_ledger_summary_schema_ok"
require_literal "$semantic_diff_guard" "budget_deltas_comparable_all_backends"
require_literal "$semantic_diff_guard" "backend run JSON ledger export is not implemented"
require_literal "$native_policy_runner" "oren.native-package-policy-run.v0"
require_literal "$native_policy_runner" "effect_ledger"
require_literal "$native_policy_runner" "runner_wall_only"

echo "effect ledger contract verify OK"
