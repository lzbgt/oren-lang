#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p build/reports
ts="$(date +%Y%m%d_%H%M%S)"
report="build/reports/gas_surface_registry_check_${ts}_$$.json"

python3 - "$report" <<'PY'
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])

files = {
    "registry": Path("docs/GAS_SURFACE_REGISTRY.md"),
    "effect_contract": Path("docs/EFFECT_LEDGER_CONTRACT.md"),
    "capability_contract": Path("docs/CAPABILITY_RUNTIME_CONTRACT.md"),
    "docs_index": Path("docs/README.md"),
    "status": Path("docs/STATUS.md"),
    "tasks": Path("docs/BLEEDING_EDGE_TASKS.md"),
    "avm_main": Path("lib/avm/main.c"),
    "native_prelude": Path("lib/runtime_native/000_prelude_sys.oren"),
    "semantic_runner": Path("scripts/run_backend_semantic_diff.sh"),
    "semantic_guard": Path("scripts/verify_backend_semantic_diff.sh"),
    "calibration_guard": Path("scripts/verify_backend_gas_surface_calibration_set.sh"),
    "instruction_guard": Path("scripts/verify_backend_native_instruction_surface_decision.sh"),
    "native_modes_guard": Path("scripts/verify_native_gas_accounting_modes.sh"),
    "native_policy_runner": Path("scripts/run_native_package_policy.sh"),
    "native_policy_guard": Path("scripts/verify_native_package_policy_runner.sh"),
    "avm_guard": Path("scripts/verify_avm_effect_ledger_json.sh"),
    "makefile": Path("Makefile"),
}

def read(name):
    path = files[name]
    if not path.exists():
        raise SystemExit(f"missing file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")

texts = {name: read(name) for name in files}

surfaces = [
    {
        "id": "avm_opcode_cost_v0",
        "backend": "bytecode",
        "unit_scope": "avm_canonical",
        "cross_arch_comparable": True,
        "conversion_ready": True,
        "avm_canonical": True,
        "required_files": ["registry", "effect_contract", "avm_main", "avm_guard", "semantic_guard", "calibration_guard", "instruction_guard"],
        "required_literals": ["avm_canonical", "conversion_ready", "cross_arch_comparable"],
    },
    {
        "id": "native_loop_safepoint_tick_v0",
        "backend": "native",
        "unit_scope": "backend_local",
        "cross_arch_comparable": False,
        "conversion_ready": False,
        "avm_canonical": False,
        "required_files": ["registry", "effect_contract", "native_prelude", "native_modes_guard"],
        "required_literals": ["native_loop_safepoint", "backend_local"],
    },
    {
        "id": "native_stmt_loop_tick_v0",
        "backend": "native",
        "unit_scope": "backend_local",
        "cross_arch_comparable": False,
        "conversion_ready": False,
        "avm_canonical": False,
        "required_files": ["registry", "effect_contract", "capability_contract", "native_prelude", "native_modes_guard", "native_policy_runner", "native_policy_guard"],
        "required_literals": ["native_statement_or_op", "not AVM-canonical opcode gas"],
    },
    {
        "id": "native_basic_block_tick_v0",
        "backend": "native",
        "unit_scope": "backend_local",
        "cross_arch_comparable": False,
        "conversion_ready": False,
        "avm_canonical": False,
        "required_files": ["registry", "effect_contract", "native_prelude", "native_modes_guard"],
        "required_literals": ["native_lowering_block", "basic-block"],
    },
    {
        "id": "native_block_weighted_tick_v0",
        "backend": "native",
        "unit_scope": "backend_local",
        "cross_arch_comparable": False,
        "conversion_ready": False,
        "avm_canonical": False,
        "required_files": ["registry", "effect_contract", "native_prelude", "native_modes_guard"],
        "required_literals": ["native_lowering_block_weight", "block-weighted"],
    },
    {
        "id": "native_dynamic_emitter_tick_v0",
        "backend": "native",
        "unit_scope": "backend_local",
        "cross_arch_comparable": False,
        "conversion_ready": False,
        "avm_canonical": False,
        "required_files": ["registry", "effect_contract", "capability_contract", "native_prelude", "semantic_guard", "calibration_guard", "instruction_guard", "native_modes_guard"],
        "required_literals": ["fixed_width_instruction_span", "emitted_byte_span", "dynamic-emitter"],
    },
]

checks = []
for surface in surfaces:
    sid = surface["id"]
    for file_name in surface["required_files"]:
        if sid not in texts[file_name]:
            raise SystemExit(f"{files[file_name]}: missing gas surface id {sid}")
        checks.append({"surface": sid, "file": str(files[file_name]), "literal": sid})
    for literal in surface["required_literals"]:
        if not any(literal in texts[file_name] for file_name in surface["required_files"]):
            raise SystemExit(f"{sid}: missing required literal {literal!r} in required files")
        checks.append({"surface": sid, "literal": literal})

global_literals = [
    ("registry", "make verify-gas-surface-registry"),
    ("docs_index", "docs/GAS_SURFACE_REGISTRY.md"),
    ("makefile", "verify-gas-surface-registry:"),
    ("makefile", "scripts/verify_gas_surface_registry.sh"),
    ("makefile", "verify-backend-semantic-diff-gas-alloc-calibration:"),
    ("semantic_runner", "alloc_heavy"),
    ("calibration_guard", "alloc_heavy"),
    ("instruction_guard", "alloc_heavy"),
    ("native_prelude", "native_runtime_backend_local_gas_surface_json"),
    ("avm_main", "unit_scope"),
    ("avm_main", "avm_canonical"),
]
for file_name, literal in global_literals:
    if literal not in texts[file_name]:
        raise SystemExit(f"{files[file_name]}: missing literal {literal!r}")
    checks.append({"file": str(files[file_name]), "literal": literal})

out = {
    "schema": "oren.gas-surface-registry-check.v0",
    "status": "pass",
    "surface_count": len(surfaces),
    "surfaces": surfaces,
    "checks": checks,
}
out_path.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"gas surface registry report: {out_path}")
print("gas surface registry verify OK")
PY
