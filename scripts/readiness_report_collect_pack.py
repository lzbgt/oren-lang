#!/usr/bin/env python3
import argparse
import os
import tarfile
from datetime import datetime
from typing import Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pack readiness collect directory into a tar.gz bundle."
    )
    parser.add_argument(
        "--dir",
        default="build/reports/readiness_collect",
        help="Collection directory to pack",
    )
    parser.add_argument(
        "--out",
        default="build/reports/readiness_collect.tar.gz",
        help="Output tar.gz path",
    )
    parser.add_argument(
        "--prefix",
        default="readiness_collect",
        help="Top-level prefix inside the archive",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def latest_mtime(path: str) -> Optional[float]:
    latest = None
    for root, _, files in os.walk(path):
        for name in files:
            full = os.path.join(root, name)
            try:
                mtime = os.path.getmtime(full)
            except OSError:
                continue
            if latest is None or mtime > latest:
                latest = mtime
    return latest


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.dir):
        print(f"ERROR: collection dir not found: {args.dir}")
        return 2
    ensure_parent_dir(args.out)

    with tarfile.open(args.out, "w:gz") as tar:
        tar.add(args.dir, arcname=args.prefix)

    mtime = latest_mtime(args.dir)
    stamp = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S") if mtime else "-"
    print(f"OK: wrote {args.out} (latest mtime {stamp})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
