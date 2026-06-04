#!/usr/bin/env python3
"""Run AVM release fixtures from a manifest.

The manifest is intentionally data-first: fixture path, expected result, budget
env, backend policy, deterministic mode, and host-effect assertions live in
tests/avm/release_manifest.json instead of Makefile case arms.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import pathlib
import subprocess
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = copy.deepcopy(value)
    return out


def load_manifest(path: pathlib.Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != "oren.avm.release_manifest.v0":
        raise SystemExit(f"unsupported AVM release manifest schema in {path}")
    defaults = data.get("defaults")
    cases = data.get("cases")
    if not isinstance(defaults, dict) or not isinstance(cases, list):
        raise SystemExit("manifest requires object defaults and list cases")
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in cases:
        if not isinstance(raw, dict):
            raise SystemExit("manifest case must be object")
        case = deep_merge(defaults, raw)
        path_value = case.get("path")
        if not isinstance(path_value, str) or not path_value:
            raise SystemExit("manifest case requires non-empty path")
        if path_value in seen:
            raise SystemExit(f"duplicate AVM manifest path: {path_value}")
        seen.add(path_value)
        validate_case(case)
        merged.append(case)
    return defaults, merged


def validate_case(case: dict[str, Any]) -> None:
    expected = case.get("expected")
    if not isinstance(expected, dict) or not isinstance(expected.get("exit_code"), int):
        raise SystemExit(f"{case['path']}: expected.exit_code must be int")
    if not isinstance(expected.get("error_contains", ""), str):
        raise SystemExit(f"{case['path']}: expected.error_contains must be string")
    if not isinstance(case.get("env"), dict):
        raise SystemExit(f"{case['path']}: env must be object")
    if not isinstance(case.get("avm_args"), list) or not all(isinstance(x, str) for x in case["avm_args"]):
        raise SystemExit(f"{case['path']}: avm_args must be list<string>")
    if not isinstance(case.get("deterministic"), bool):
        raise SystemExit(f"{case['path']}: deterministic must be bool")
    if not isinstance(case.get("backend_policy"), str) or not case["backend_policy"]:
        raise SystemExit(f"{case['path']}: backend_policy must be non-empty string")
    if not isinstance(case.get("budgets"), dict):
        raise SystemExit(f"{case['path']}: budgets must be object")
    setup_dirs = case.get("setup_dirs", [])
    if not isinstance(setup_dirs, list) or not all(isinstance(x, str) for x in setup_dirs):
        raise SystemExit(f"{case['path']}: setup_dirs must be list<string>")
    if not isinstance(case.get("host_effects"), list):
        raise SystemExit(f"{case['path']}: host_effects must be list")
    for effect in case["host_effects"]:
        if not isinstance(effect, dict) or effect.get("expect") not in {"absent", "present"}:
            raise SystemExit(f"{case['path']}: host_effects entries require expect absent/present")
        if not isinstance(effect.get("path"), str) or not effect["path"]:
            raise SystemExit(f"{case['path']}: host_effect path must be non-empty string")


def default_case(defaults: dict[str, Any], fixture_path: str) -> dict[str, Any]:
    case = deep_merge(defaults, {"path": fixture_path})
    validate_case(case)
    return case


def run_cmd(cmd: list[str], log_path: pathlib.Path, env: dict[str, str] | None = None, timeout: int = 180) -> int:
    with log_path.open("w", encoding="utf-8") as log:
        proc = subprocess.run(
            cmd,
            cwd=ROOT,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    return proc.returncode


def sanitize_name(path_value: str) -> str:
    return pathlib.Path(path_value).stem.replace("/", "_").replace(" ", "_")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="tests/avm/release_manifest.json")
    parser.add_argument("--oren-bin", default="./oren")
    parser.add_argument("--avm-bin", default="./avm")
    parser.add_argument("--build-dir", default="build")
    parser.add_argument("--log-dir", default="build/logs")
    parser.add_argument("--tests", nargs="*", default=None)
    args = parser.parse_args()

    manifest_path = ROOT / args.manifest
    defaults, cases = load_manifest(manifest_path)
    by_path = {case["path"]: case for case in cases}
    selected = [case for case in cases if case.get("release_gate", True)]
    if args.tests:
        selected = [by_path.get(path_value, default_case(defaults, path_value)) for path_value in args.tests]
    if not selected:
        raise SystemExit("AVM release manifest selected no cases")

    build_dir = ROOT / args.build_dir
    log_dir = ROOT / args.log_dir
    build_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    print("=== AVM Tests (Manifest) ===")
    for case in selected:
        fixture = ROOT / case["path"]
        if not fixture.exists():
            raise SystemExit(f"missing AVM fixture: {case['path']}")
        name = sanitize_name(case["path"])
        obc = build_dir / f"avm_{name}.obc"
        build_log = log_dir / f"avm_{name}.log"
        run_log = log_dir / f"avm_{name}.out"
        print(f"Testing {name}...")
        build_rc = run_cmd(
            [args.oren_bin, "build", case["path"], "--backend", "bytecode", "-o", str(obc.relative_to(ROOT))],
            build_log,
            timeout=180,
        )
        if build_rc != 0:
            sys.stderr.write(f"--- {name} (build) ---\n{build_log.read_text(encoding='utf-8', errors='replace')}")
            return 1

        for dir_value in case.get("setup_dirs", []):
            (ROOT / dir_value).mkdir(parents=True, exist_ok=True)
        for effect in case["host_effects"]:
            target = ROOT / effect["path"]
            if effect["expect"] == "absent" and target.exists():
                target.unlink()

        env = os.environ.copy()
        for key, value in case["env"].items():
            env[str(key)] = str(value)
        run_rc = run_cmd([args.avm_bin, *case["avm_args"], str(obc.relative_to(ROOT))], run_log, env=env, timeout=180)
        combined = run_log.read_text(encoding="utf-8", errors="replace")
        expected = case["expected"]
        if run_rc != expected["exit_code"]:
            sys.stderr.write(f"--- {name} (run rc={run_rc}, expected {expected['exit_code']}) ---\n{combined}")
            return 1
        needle = expected.get("error_contains", "")
        if needle and needle not in combined:
            sys.stderr.write(f"--- {name} (missing expected error {needle!r}) ---\n{combined}")
            return 1
        for effect in case["host_effects"]:
            target = ROOT / effect["path"]
            if effect["expect"] == "absent" and target.exists():
                sys.stderr.write(f"--- {name} (host artifact exists) ---\nexpected absent: {effect['path']}\n")
                return 1
            if effect["expect"] == "present" and not target.exists():
                sys.stderr.write(f"--- {name} (host artifact missing) ---\nexpected present: {effect['path']}\n")
                return 1
        with build_log.open("a", encoding="utf-8") as log:
            log.write(combined)
            log.write(
                f"\nmanifest: deterministic={case['deterministic']} "
                f"backend_policy={case['backend_policy']} budgets={json.dumps(case['budgets'], sort_keys=True)}\n"
            )

    print("AVM manifest tests OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
