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
    setup_builds = case.get("setup_builds", [])
    if not isinstance(setup_builds, list):
        raise SystemExit(f"{case['path']}: setup_builds must be list")
    for setup_build in setup_builds:
        if not isinstance(setup_build, dict):
            raise SystemExit(f"{case['path']}: setup_builds entries must be object")
        if not isinstance(setup_build.get("src"), str) or not setup_build["src"]:
            raise SystemExit(f"{case['path']}: setup_build src must be non-empty string")
        if not isinstance(setup_build.get("out"), str) or not setup_build["out"]:
            raise SystemExit(f"{case['path']}: setup_build out must be non-empty string")
    if not isinstance(case.get("host_effects"), list):
        raise SystemExit(f"{case['path']}: host_effects must be list")
    for effect in case["host_effects"]:
        if not isinstance(effect, dict) or effect.get("expect") not in {"absent", "present"}:
            raise SystemExit(f"{case['path']}: host_effects entries require expect absent/present")
        if not isinstance(effect.get("path"), str) or not effect["path"]:
            raise SystemExit(f"{case['path']}: host_effect path must be non-empty string")
    phases = case.get("phases", [])
    if not isinstance(phases, list):
        raise SystemExit(f"{case['path']}: phases must be list")
    seen_phase_names: set[str] = set()
    for phase in phases:
        validate_phase(case, phase, seen_phase_names)
    assertions = case.get("assertions", [])
    if not isinstance(assertions, list):
        raise SystemExit(f"{case['path']}: assertions must be list")
    for assertion in assertions:
        validate_assertion(case, assertion)


def validate_phase(case: dict[str, Any], phase: dict[str, Any], seen: set[str]) -> None:
    if not isinstance(phase, dict):
        raise SystemExit(f"{case['path']}: phase entries must be object")
    name = phase.get("name")
    if not isinstance(name, str) or not name:
        raise SystemExit(f"{case['path']}: phase.name must be non-empty string")
    if name in seen:
        raise SystemExit(f"{case['path']}: duplicate phase name: {name}")
    seen.add(name)
    if "avm_args" in phase and (
        not isinstance(phase["avm_args"], list) or not all(isinstance(x, str) for x in phase["avm_args"])
    ):
        raise SystemExit(f"{case['path']} phase {name}: avm_args must be list<string>")
    if "env" in phase and not isinstance(phase["env"], dict):
        raise SystemExit(f"{case['path']} phase {name}: env must be object")
    env_from = phase.get("env_from_captures", {})
    if not isinstance(env_from, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in env_from.items()):
        raise SystemExit(f"{case['path']} phase {name}: env_from_captures must be object<string,string>")
    if "expected" in phase:
        expected = phase["expected"]
        if not isinstance(expected, dict) or not isinstance(expected.get("exit_code"), int):
            raise SystemExit(f"{case['path']} phase {name}: expected.exit_code must be int")
        if not isinstance(expected.get("error_contains", ""), str):
            raise SystemExit(f"{case['path']} phase {name}: expected.error_contains must be string")
    cleanup_paths = phase.get("cleanup_paths", [])
    if not isinstance(cleanup_paths, list) or not all(isinstance(x, str) for x in cleanup_paths):
        raise SystemExit(f"{case['path']} phase {name}: cleanup_paths must be list<string>")
    host_effects = phase.get("host_effects", [])
    if not isinstance(host_effects, list):
        raise SystemExit(f"{case['path']} phase {name}: host_effects must be list")
    for effect in host_effects:
        if not isinstance(effect, dict) or effect.get("expect") not in {"absent", "present"}:
            raise SystemExit(f"{case['path']} phase {name}: host_effects entries require expect absent/present")
        if not isinstance(effect.get("path"), str) or not effect["path"]:
            raise SystemExit(f"{case['path']} phase {name}: host_effect path must be non-empty string")
    captures = phase.get("captures", [])
    if not isinstance(captures, list):
        raise SystemExit(f"{case['path']} phase {name}: captures must be list")
    for capture in captures:
        if not isinstance(capture, dict):
            raise SystemExit(f"{case['path']} phase {name}: capture entries must be object")
        if not isinstance(capture.get("name"), str) or not capture["name"]:
            raise SystemExit(f"{case['path']} phase {name}: capture.name must be non-empty string")
        if not isinstance(capture.get("prefix"), str) or not capture["prefix"]:
            raise SystemExit(f"{case['path']} phase {name}: capture.prefix must be non-empty string")
        if "required" in capture and not isinstance(capture["required"], bool):
            raise SystemExit(f"{case['path']} phase {name}: capture.required must be bool")


def validate_assertion(case: dict[str, Any], assertion: dict[str, Any]) -> None:
    if not isinstance(assertion, dict):
        raise SystemExit(f"{case['path']}: assertion entries must be object")
    op = assertion.get("op")
    if op not in {"eq", "ne", "present", "nonempty"}:
        raise SystemExit(f"{case['path']}: assertion.op must be eq/ne/present/nonempty")
    if op in {"eq", "ne"}:
        if not isinstance(assertion.get("left"), str) or not isinstance(assertion.get("right"), str):
            raise SystemExit(f"{case['path']}: {op} assertion requires left/right capture names")
    else:
        if not isinstance(assertion.get("capture"), str):
            raise SystemExit(f"{case['path']}: {op} assertion requires capture")


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


def default_phase(case: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": "run",
        "avm_args": case["avm_args"],
        "env": {},
        "expected": case["expected"],
        "host_effects": case["host_effects"],
    }


def capture_output(case: dict[str, Any], phase: dict[str, Any], combined: str, captures: dict[str, str]) -> None:
    phase_name = phase["name"]
    for capture in phase.get("captures", []):
        prefix = capture["prefix"]
        value = None
        for line in combined.splitlines():
            if line.startswith(prefix):
                value = line[len(prefix):].strip()
        if value is None:
            if capture.get("required", True):
                raise RuntimeError(f"{case['path']} phase {phase_name}: missing capture prefix {prefix!r}")
            continue
        captures[f"{phase_name}.{capture['name']}"] = value


def check_assertions(case: dict[str, Any], captures: dict[str, str]) -> None:
    for assertion in case.get("assertions", []):
        op = assertion["op"]
        if op in {"present", "nonempty"}:
            key = assertion["capture"]
            if key not in captures:
                raise RuntimeError(f"{case['path']}: missing capture {key!r}")
            if op == "nonempty" and captures[key] == "":
                raise RuntimeError(f"{case['path']}: capture {key!r} is empty")
            continue
        left_key = assertion["left"]
        right_key = assertion["right"]
        if left_key not in captures or right_key not in captures:
            raise RuntimeError(f"{case['path']}: missing captures for assertion {left_key!r} {op} {right_key!r}")
        left = captures[left_key]
        right = captures[right_key]
        if op == "eq" and left != right:
            raise RuntimeError(f"{case['path']}: expected {left_key} == {right_key}, got {left!r} != {right!r}")
        if op == "ne" and left == right:
            raise RuntimeError(f"{case['path']}: expected {left_key} != {right_key}, both were {left!r}")


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

        for index, setup_build in enumerate(case.get("setup_builds", []), start=1):
            setup_src = ROOT / setup_build["src"]
            setup_out = ROOT / setup_build["out"]
            if not setup_src.exists():
                raise SystemExit(f"{case['path']}: missing setup_build src: {setup_build['src']}")
            setup_out.parent.mkdir(parents=True, exist_ok=True)
            setup_log = log_dir / f"avm_{name}_setup_{index}.log"
            setup_rc = run_cmd(
                [
                    args.oren_bin,
                    "build",
                    setup_build["src"],
                    "--backend",
                    "bytecode",
                    "-o",
                    str(setup_out.relative_to(ROOT)),
                ],
                setup_log,
                timeout=180,
            )
            if setup_rc != 0:
                sys.stderr.write(f"--- {name} (setup build {index}) ---\n")
                sys.stderr.write(setup_log.read_text(encoding="utf-8", errors="replace"))
                return 1

        phases = case.get("phases") or [default_phase(case)]
        captures: dict[str, str] = {}
        with build_log.open("a", encoding="utf-8") as log:
            for phase in phases:
                phase_name = phase["name"]
                phase_log = run_log if len(phases) == 1 else log_dir / f"avm_{name}_{phase_name}.out"
                for dir_value in case.get("setup_dirs", []):
                    (ROOT / dir_value).mkdir(parents=True, exist_ok=True)
                for path_value in phase.get("cleanup_paths", []):
                    target = ROOT / path_value
                    if target.exists():
                        target.unlink()
                phase_effects = phase.get("host_effects", case["host_effects"])
                for effect in phase_effects:
                    target = ROOT / effect["path"]
                    if effect["expect"] == "absent" and target.exists():
                        target.unlink()

                env = os.environ.copy()
                for key, value in case["env"].items():
                    env[str(key)] = str(value)
                for key, value in phase.get("env", {}).items():
                    env[str(key)] = str(value)
                for key, capture_key in phase.get("env_from_captures", {}).items():
                    if capture_key not in captures:
                        sys.stderr.write(f"--- {name} phase {phase_name} (missing env capture) ---\n{capture_key}\n")
                        return 1
                    env[str(key)] = captures[capture_key]

                phase_args = phase.get("avm_args", case["avm_args"])
                run_rc = run_cmd([args.avm_bin, *phase_args, str(obc.relative_to(ROOT))], phase_log, env=env, timeout=180)
                combined = phase_log.read_text(encoding="utf-8", errors="replace")
                expected = phase.get("expected", case["expected"])
                if run_rc != expected["exit_code"]:
                    sys.stderr.write(
                        f"--- {name} phase {phase_name} (run rc={run_rc}, expected {expected['exit_code']}) ---\n{combined}"
                    )
                    return 1
                needle = expected.get("error_contains", "")
                if needle and needle not in combined:
                    sys.stderr.write(f"--- {name} phase {phase_name} (missing expected error {needle!r}) ---\n{combined}")
                    return 1
                for effect in phase_effects:
                    target = ROOT / effect["path"]
                    if effect["expect"] == "absent" and target.exists():
                        sys.stderr.write(f"--- {name} phase {phase_name} (host artifact exists) ---\nexpected absent: {effect['path']}\n")
                        return 1
                    if effect["expect"] == "present" and not target.exists():
                        sys.stderr.write(f"--- {name} phase {phase_name} (host artifact missing) ---\nexpected present: {effect['path']}\n")
                        return 1
                try:
                    capture_output(case, phase, combined, captures)
                except RuntimeError as exc:
                    sys.stderr.write(f"--- {name} phase {phase_name} (capture) ---\n{exc}\n{combined}")
                    return 1
                log.write(f"\n--- phase {phase_name} ---\n")
                log.write(combined)
            try:
                check_assertions(case, captures)
            except RuntimeError as exc:
                sys.stderr.write(f"--- {name} (assertion) ---\n{exc}\n")
                return 1
            log.write(
                f"\nmanifest: deterministic={case['deterministic']} "
                f"backend_policy={case['backend_policy']} budgets={json.dumps(case['budgets'], sort_keys=True)}\n"
            )

    print("AVM manifest tests OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
