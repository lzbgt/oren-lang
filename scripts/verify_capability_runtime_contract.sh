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

require_regex() {
  local path="$1"
  local pattern="$2"
  grep -Eq -- "$pattern" "$path" || fail "missing regex in $path: $pattern"
}

contract="docs/CAPABILITY_RUNTIME_CONTRACT.md"
native_full="lib/runtime_native.oren"
native_core="lib/runtime_native_core.oren"
native_capsule="lib/runtime_native_capsule.oren"
native_consts="lib/runtime_native/010_channels_globals_consts.oren"
capsule_core="lib/runtime_native/040_capsule_core.oren"
env_runtime="lib/runtime_native/090_env.oren"
avm_domains="lib/compiler/codegen_bytecode/000_prelude.oren"
avm_native_map="lib/compiler/codegen_bytecode/010_codegen_a.oren"
arm64_profile="lib/compiler/arm64_native_program/090_program.oren"
x64_profile="lib/compiler/x64_native_program/090_program_entry/090_tail.oren"
compiler_cli="lib/compiler/compiler/000_prelude_body.oren"
metadata_compiler="lib/compiler/metadata.oren"
seed_script="scripts/build_rtobj_seed.sh"
metadata_guard="scripts/verify_capability_metadata.sh"
manifest_policy_guard="scripts/verify_capability_manifest_policy.sh"
package_policy_runner="scripts/run_package_policy.sh"
avm_policy_runner="scripts/run_avm_package_policy.sh"
avm_policy_runner_guard="scripts/verify_avm_package_policy_runner.sh"
native_policy_runner="scripts/run_native_package_policy.sh"
native_policy_runner_guard="scripts/verify_native_package_policy_runner.sh"

for f in \
  "$contract" \
  "$native_full" \
  "$native_core" \
  "$native_capsule" \
  "$native_consts" \
  "$capsule_core" \
  "$env_runtime" \
  "$avm_domains" \
  "$avm_native_map" \
  "$arm64_profile" \
  "$x64_profile" \
  "$compiler_cli" \
  "$metadata_compiler" \
  "$seed_script" \
  "$metadata_guard" \
  "$manifest_policy_guard" \
  "$package_policy_runner" \
  "$avm_policy_runner" \
  "$avm_policy_runner_guard" \
  "$native_policy_runner" \
  "$native_policy_runner_guard" \
  Makefile
do
  require_file "$f"
done

# Contract doc anchors.
require_literal "$contract" "## Native Runtime Profiles"
require_literal "$contract" "## Capability Layers"
require_literal "$contract" "## Source Metadata Manifest"
require_literal "$contract" "## Domain Contract"
require_literal "$contract" "## Failure Model"
require_literal "$contract" "## Verification Map"
require_literal "$contract" "make verify-capability-runtime-contract"
require_literal "$contract" "make verify-capability-metadata"
require_literal "$contract" "make verify-capability-manifest-policy"
require_literal "$contract" "make verify-effect-ledger-contract"
require_literal "$contract" "make verify-avm-effect-ledger-json"
require_literal "$contract" "make verify-avm-package-policy-runner"
require_literal "$contract" "make verify-native-package-policy-runner"
require_literal "$contract" "make test-native-capsule-smoke-stage2"
require_literal "$contract" "make test-avm"
require_literal "$contract" "make verify-backend-parity"
require_literal "$contract" "make test"
require_literal "$contract" "tests/fixtures/meta_capabilities_src.oren"
require_literal "$contract" "@oren.package"
require_literal "$contract" "dependency_domain_union_status"
require_literal "$contract" "source_package_check"
require_literal "$contract" "--enforce-package-policy"
require_literal "$contract" "OREN_ENFORCE_PACKAGE_POLICY"

# Native runtime profile entry files.
require_literal "$native_core" "core profile"
require_literal "$native_core" "// @include \"runtime_native/035_capsule_stubs.oren\""
require_literal "$native_core" "// @include \"runtime_native/200_typed_buffers_core.oren\""
require_literal "$native_full" "// Capsule policy:"
require_literal "$native_full" "// @include \"runtime_native/035_capsule_stubs.oren\""
require_literal "$native_full" "// @include \"runtime_native/240_tcp.oren\""
require_literal "$native_full" "// @include \"runtime_native/250_udp.oren\""
require_literal "$native_full" "// @include \"runtime_native/270_avm_bridge.oren\""
require_literal "$native_capsule" "capsule-enabled variant"
require_literal "$native_capsule" "// @include \"runtime_native/040_capsule_core.oren\""
require_literal "$native_capsule" "// @include \"runtime_native/050_capsule_fs_hooks.oren\""
require_literal "$native_capsule" "// @include \"runtime_native/070_capsule_net_hooks.oren\""
require_literal "$native_capsule" "// @include \"runtime_native/080_capsule_proc_misc_hooks.oren\""
require_literal "$native_capsule" "// @include \"runtime_native/270_avm_bridge.oren\""

# Native backend runtime selection.
for profile_file in "$arm64_profile" "$x64_profile"; do
  require_literal "$profile_file" "runtime_path = \"lib/runtime_native_capsule.oren\""
  require_literal "$profile_file" "OREN_NATIVE_RUNTIME_PROFILE"
  require_literal "$profile_file" "runtime_path = \"lib/runtime_native_core.oren\""
  require_literal "$profile_file" "runtime_path = \"lib/runtime_native.oren\""
  require_literal "$profile_file" "\"full\""
  require_literal "$profile_file" "\"core\""
  require_literal "$profile_file" "\"minimal\""
done
require_literal "$seed_script" "--capsule           seed the capsule runtime entry"
require_literal "$seed_script" "--runtime-profile <full|core|minimal>"
require_literal "$seed_script" "runtime_entry=\"lib/runtime_native_capsule.oren\""
require_literal "$seed_script" "runtime_entry=\"lib/runtime_native_core.oren\""
require_literal "$seed_script" "runtime_entry=\"lib/runtime_native.oren\""

# Native capability masks and env allowlists.
require_regex "$native_consts" 'var CAP_FS = 1$'
require_regex "$native_consts" 'var CAP_NET = 2$'
require_regex "$native_consts" 'var CAP_PROC = 4$'
require_regex "$native_consts" 'var CAP_ENV = 8$'
require_regex "$native_consts" 'var CAP_TIME = 16$'
require_regex "$native_consts" 'var CAP_RNG = 32$'
require_literal "$compiler_cli" "--capsule"
require_literal "$compiler_cli" "--cap-allow-domains"
require_literal "$compiler_cli" "OREN_CAP_ALLOW_DOMAINS"
require_literal "$capsule_core" "OREN_CAP_ALLOW_DOMAINS"
require_literal "$native_consts" "native_capsule_effect_gate_summary_json"
require_literal "$native_consts" "oren.native-capsule-effect-gates.v0"
require_literal "$native_consts" "native_capsule_resource_check_summary_json"
require_literal "$native_consts" "oren.native-capsule-resource-checks.v0"
require_literal "$capsule_core" "native_capsule_effect_gate_note"
require_literal "$capsule_core" "native_capsule_resource_check_note"
for knob in \
  OREN_FS_MOUNTS \
  OREN_FS_MOUNTS_READ \
  OREN_FS_MOUNTS_WRITE \
  OREN_FS_ALLOW_PREFIXES \
  OREN_FS_ALLOW_READ_PREFIXES \
  OREN_FS_ALLOW_WRITE_PREFIXES \
  OREN_NET_ALLOW_LOOPBACK \
  OREN_NET_ALLOW_TCP_CONNECT \
  OREN_NET_ALLOW_TCP_LISTEN \
  OREN_NET_TCP_CONNECT_MAP \
  OREN_NET_TCP_LISTEN_MAP \
  OREN_PROC_ALLOW_EXEC_PREFIXES \
  OREN_PROC_ALLOW_SYSTEM \
  OREN_PROC_INHERIT_ENV \
  OREN_PROC_ALLOW_ENV_KEYS \
  OREN_PROC_ALLOW_ARGV
do
  require_literal "$capsule_core" "$knob"
done
require_literal "$env_runtime" "@cap.requires(domain=\"ENV\")"
require_literal "$env_runtime" "if (allow & 8) == 0 { return 0 }"
require_literal "$metadata_compiler" "capabilities"
require_literal "$metadata_compiler" "cap_required_domains"
require_literal "$metadata_compiler" "json_package_manifest"
require_literal "$metadata_compiler" "json_package_policy_check"
require_literal "$metadata_compiler" "package_policy_check_status"
require_literal "$compiler_cli" "\"source_package\""
require_literal "$compiler_cli" "\"source_package_check\""
require_literal "$compiler_cli" "--enforce-package-policy"
require_literal "$compiler_cli" "OREN_ENFORCE_PACKAGE_POLICY"
require_literal "$compiler_cli" "_enforce_package_policy_if_requested"
require_literal "$metadata_guard" "meta_capabilities_src.oren"
require_literal "$metadata_guard" "capability_manifest_policy_src.oren"
require_literal "$compiler_cli" "_write_artifact_manifest_with_policy"
require_literal "$manifest_policy_guard" "capability_manifest_policy_src.oren"
require_literal "$manifest_policy_guard" "source_required_domains"
require_literal "$manifest_policy_guard" "source_package"
require_literal "$manifest_policy_guard" "source_package_check"
require_literal "$manifest_policy_guard" "--enforce-package-policy"
require_literal "$manifest_policy_guard" "OREN_ENFORCE_PACKAGE_POLICY"
require_literal "$package_policy_runner" "--backend avm|native"
require_literal "$avm_policy_runner" "AVM_GAS"
require_literal "$avm_policy_runner" "AVM_MEM_BYTES"
require_literal "$avm_policy_runner" "AVM_TIMEOUT_MS"
require_literal "$avm_policy_runner" "AVM_ALLOW_DOMAINS"
require_literal "$avm_policy_runner_guard" "avm_package_policy_runner_ok.oren"
require_literal "$native_policy_runner" "OREN_CAPSULE"
require_literal "$native_policy_runner" "OREN_CAP_ALLOW_DOMAINS"
require_literal "$native_policy_runner" "budget_wall_ms"
require_literal "$native_policy_runner" "budget_heap_bytes"
require_literal "$native_policy_runner" "OREN_NATIVE_PACKAGE_POLICY_RUN_JSON"
require_literal "$native_policy_runner" "OREN_NATIVE_RUN_JSON"
require_literal "$native_policy_runner" "oren.native-package-policy-run.v0"
require_literal "$native_policy_runner" "runner_wall_native_heap"
require_literal "$native_policy_runner" "runner_wall_child_cpu"
require_literal "$native_policy_runner" "runner_wall_native_gas"
require_literal "$native_policy_runner" "effect_ledger"
require_literal "$native_policy_runner" "native-run-json-live-scan"
require_literal "$native_policy_runner" "runner-child-rusage"
require_literal "$native_policy_runner" "native-run-json-stmt-loop-tick"
require_literal "$native_policy_runner" "OREN_NATIVE_GAS_ACCOUNTING"
require_literal "$native_policy_runner" "native_stmt_loop_tick_v0"
require_literal "$native_policy_runner" "gas_surface_id"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_ok.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_heap_ok.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_heap_fail.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_gas_ok.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_gas_fail.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_gas_stmt_fail.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_cpu_ok.oren"
require_literal "$native_policy_runner_guard" "native_package_policy_runner_cpu_fail.oren"
require_literal "$native_policy_runner_guard" "OREN_NATIVE_PACKAGE_POLICY_RUN_JSON"
require_literal "$native_policy_runner_guard" "oren.native-package-policy-run.v0"
require_literal "$native_policy_runner_guard" "runner_wall_only"
require_literal "$native_policy_runner_guard" "runner_wall_native_heap"
require_literal "$native_policy_runner_guard" "runner_wall_child_cpu"
require_literal "$native_policy_runner_guard" "runner_wall_native_gas"
require_literal "$native_policy_runner_guard" "oren.gas-surface.v0"
require_literal "$native_policy_runner_guard" "package native heap budget exceeded"
require_literal "$native_policy_runner_guard" "package native gas budget exceeded"
require_literal "$native_policy_runner_guard" "package native CPU budget exceeded"
require_literal Makefile "verify-native-gas-accounting-modes:"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "basic-block must stay distinct from statement gas"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "block-weighted must stay distinct from basic-block and statement gas"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "instruction-equivalent gas must stay reserved"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "native_stmt_loop_tick_v0"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "native_basic_block_tick_v0"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "native_block_weighted_tick_v0"
require_literal "scripts/verify_native_gas_accounting_modes.sh" "native_loop_safepoint_tick_v0"
require_literal "$native_policy_runner_guard" "oren.native-capsule-effect-gates.v0"
require_literal "$native_policy_runner_guard" "native capsule effect gates"
require_literal "$native_policy_runner_guard" "native package policy ok"

# AVM domain ids and selected domain mappings.
require_regex "$avm_domains" 'var AVM_DOMAIN_CORE = 0$'
require_regex "$avm_domains" 'var AVM_DOMAIN_FS = 1$'
require_regex "$avm_domains" 'var AVM_DOMAIN_TIME = 2$'
require_regex "$avm_domains" 'var AVM_DOMAIN_RNG = 3$'
require_regex "$avm_domains" 'var AVM_DOMAIN_NET = 4$'
require_regex "$avm_domains" 'var AVM_DOMAIN_PROC = 5$'
require_regex "$avm_domains" 'var AVM_DOMAIN_EXIT = 6$'
require_regex "$avm_domains" 'var AVM_DOMAIN_ENV = 7$'
require_regex "$avm_domains" 'var AVM_DOMAIN_AVM = 8$'
require_literal "$avm_native_map" "if name == \"oren_env\" { native_domain = AVM_DOMAIN_ENV; native_op = 0 }"
require_literal "$avm_native_map" "if name == \"oren_time_now_ns\" { native_domain = AVM_DOMAIN_TIME; native_op = 0 }"
require_literal "$avm_native_map" "if name == \"oren_rand_u64\" { native_domain = AVM_DOMAIN_RNG; native_op = 0 }"
require_literal "$avm_native_map" "if name == \"oren_net_get\" { native_domain = AVM_DOMAIN_NET; native_op = 0 }"
require_literal "$avm_native_map" "if name == \"oren_read_file\" { native_domain = AVM_DOMAIN_FS; native_op = 0 }"
require_literal "$avm_native_map" "if name == \"oren_avm_run_obc_bytes\" { native_domain = AVM_DOMAIN_AVM; native_op = 0 }"

# Makefile verification hooks.
require_literal Makefile ".PHONY: verify-capability-runtime-contract"
require_literal Makefile ".PHONY: verify-capability-runtime-contract verify-capability-metadata verify-capability-manifest-policy"
require_literal Makefile "verify-capability-runtime-contract:"
require_literal Makefile "verify-capability-metadata:"
require_literal Makefile "verify-capability-manifest-policy:"
require_literal Makefile "verify-effect-ledger-contract:"
require_literal Makefile "verify-avm-effect-ledger-json:"
require_literal Makefile "verify-avm-package-policy-runner:"
require_literal Makefile "verify-native-package-policy-runner:"
require_literal Makefile "verify-native-capsule-resource-checks:"
require_literal Makefile "./scripts/verify_capability_runtime_contract.sh"
require_literal Makefile "./scripts/verify_capability_metadata.sh"
require_literal Makefile "./scripts/verify_capability_manifest_policy.sh"
require_literal Makefile "./scripts/verify_effect_ledger_contract.sh"
require_literal Makefile "./scripts/verify_avm_effect_ledger_json.sh"
require_literal Makefile "./scripts/verify_avm_package_policy_runner.sh"
require_literal Makefile "./scripts/verify_native_package_policy_runner.sh"
require_literal Makefile "./scripts/verify_native_capsule_resource_checks.sh"
require_literal Makefile "test-native-capsule-smoke-stage2:"
require_literal Makefile "test-avm: oren avm"
require_literal Makefile "verify-backend-parity:"
require_literal Makefile "test: verify-capability-runtime-contract verify-capability-metadata verify-capability-manifest-policy verify-effect-ledger-contract verify-avm-package-policy-runner verify-native-package-policy-runner verify-native-capsule-resource-checks verify-native-gas-accounting-modes verify-public-readme-positioning verify-avm-spawn-channel-args test-native-quick"

echo "capability runtime contract verify OK"
