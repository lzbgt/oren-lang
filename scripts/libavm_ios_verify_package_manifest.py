#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def parse_bool(value):
    if value == "true":
        return True
    if value == "false":
        return False
    raise ValueError(f"expected true/false, got {value!r}")


def parse_asset(value):
    parts = value.split("|")
    if len(parts) not in (2, 3):
        raise ValueError("--asset expects path|sha256 or path|sha256|media_type")
    asset = {
        "path": parts[0],
        "sha256": parts[1],
    }
    if len(parts) == 3 and parts[2]:
        asset["media_type"] = parts[2]
    return asset


def parse_permission(value):
    parts = value.split("|")
    if len(parts) != 4:
        raise ValueError("--permission-default expects domain|action|detail|true/false")
    return {
        "domain": parts[0],
        "action": parts[1],
        "detail": parts[2],
        "granted": parse_bool(parts[3]),
    }


def parse_mount(value):
    parts = value.split("|")
    if len(parts) != 3:
        raise ValueError("--mount expects virtual|package_path|true/false")
    return {
        "virtual": parts[0],
        "package_path": parts[1],
        "read_only": parse_bool(parts[2]),
    }


def main():
    parser = argparse.ArgumentParser(description="Write deterministic libavm iOS verifier package manifests.")
    parser.add_argument("--out", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--publisher", default="oren-labs")
    parser.add_argument("--version", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--entry-obc", default="program.obc")
    parser.add_argument("--obc-sha256", required=True)
    parser.add_argument("--oren-min", default="0.0.rolling")
    parser.add_argument("--avm-abi-min", type=int, default=8)
    parser.add_argument("--capabilities", required=True, help="Comma-separated capability list.")
    parser.add_argument("--asset", action="append", default=[], help="path|sha256 or path|sha256|media_type.")
    parser.add_argument("--permission-default", action="append", default=[], help="domain|action|detail|true/false.")
    parser.add_argument("--time-mode", default="deterministic")
    parser.add_argument("--gas", type=int, default=5000000)
    parser.add_argument("--heap-bytes", type=int, default=33554432)
    parser.add_argument("--io-bytes", type=int, default=1048576)
    parser.add_argument("--frame-commands", type=int, default=1024)
    parser.add_argument("--mount", action="append", default=[], help="virtual|package_path|true/false.")
    args = parser.parse_args()

    manifest = {
        "schema": "oren.obc.package.v0",
        "name": args.name,
        "publisher": args.publisher,
        "version": args.version,
        "title": args.title,
        "summary": args.summary,
        "entry_obc": args.entry_obc,
        "obc_sha256": args.obc_sha256,
        "oren_min": args.oren_min,
        "avm_abi_min": args.avm_abi_min,
        "capabilities": [part for part in args.capabilities.split(",") if part],
    }
    assets = [parse_asset(value) for value in args.asset]
    if assets:
        manifest["assets"] = assets
    permissions = [parse_permission(value) for value in args.permission_default]
    if permissions:
        manifest["permission_defaults"] = permissions
    manifest["time_mode"] = args.time_mode
    manifest["budgets"] = {
        "gas": args.gas,
        "heap_bytes": args.heap_bytes,
        "io_bytes": args.io_bytes,
        "frame_commands": args.frame_commands,
    }
    mounts = [parse_mount(value) for value in args.mount]
    if mounts:
        manifest["vfs_mounts"] = mounts

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
