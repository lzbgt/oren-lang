#!/usr/bin/env python3
"""Guard rolling stdlib API shape against known root-helper regressions."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("lib/std", "tests", "examples")
BANNED_TOKENS = (
    "try_get_text",
    "try_get_bytes",
    "try_request",
    "try_recv_text",
    "try_send_text",
    "try_send_text_client",
    "try_send_text_server",
)


def iter_sources() -> list[Path]:
    out: list[Path] = []
    for rel in SCAN_DIRS:
        base = ROOT / rel
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix in {".oren", ".json", ".md"} and path.is_file():
                out.append(path)
    return sorted(out)


def main() -> int:
    token_re = re.compile(r"\b(" + "|".join(re.escape(t) for t in BANNED_TOKENS) + r")\b")
    failures: list[str] = []
    for path in iter_sources():
        text = path.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), 1):
            match = token_re.search(line)
            if match:
                failures.append(f"{path.relative_to(ROOT)}:{line_no}: banned root-style helper `{match.group(1)}`")

    if failures:
        print("stdlib API shape guard failed:")
        for failure in failures:
            print(failure)
        print("Use scoped/object APIs such as http.get(url).text(), response.bytes(), or conn.recv_text(...).")
        return 1

    print("OK: stdlib API shape guard passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
