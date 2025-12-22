#!/usr/bin/env python3
"""
Include chunk analyzer for Oren's `// @include "..."` split files.

Goals:
- Show per-included-file brace balance (final balance and minimum prefix balance),
  ignoring braces in string literals and line comments.
- Detect when a top-level function spans multiple included files (common cause of
  "context overflow" during refactors, and why chunks become unbalanced).

This tool is intentionally conservative and heuristic-based; it is meant to
support refactors, not to be a language parser.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Tuple


@dataclass(frozen=True)
class Chunk:
    path: Path
    text: str


def _trim_left_ws(s: str) -> str:
    i = 0
    while i < len(s) and s[i] in (" ", "\t"):
        i += 1
    return s[i:]


def _include_path_from_line(line: str) -> str:
    # Matches compiler include directive:
    #   // @include "relative/or/absolute/path.oren"
    t = _trim_left_ws(line)
    if not t.startswith("// @include"):
        return ""
    # Find first quoted string.
    i = t.find('"')
    if i < 0:
        return ""
    j = t.find('"', i + 1)
    if j < 0:
        return ""
    return t[i + 1 : j]


def expand_includes_file(path: Path, stack: List[Path] | None = None) -> List[Chunk]:
    if stack is None:
        stack = []
    path = path.resolve()
    if path in stack:
        cycle = " -> ".join(str(p) for p in stack + [path])
        raise RuntimeError(f"include cycle detected: {cycle}")
    stack2 = stack + [path]

    src = path.read_text()
    out: List[Chunk] = []
    cur_lines: List[str] = []

    def flush_cur() -> None:
        if cur_lines:
            out.append(Chunk(path=path, text="".join(cur_lines)))
            cur_lines.clear()

    for raw_line in src.splitlines(True):
        inc = _include_path_from_line(raw_line)
        if inc:
            flush_cur()
            inc_path = Path(inc)
            if not inc_path.is_absolute():
                inc_path = (path.parent / inc_path).resolve()
            out.extend(expand_includes_file(inc_path, stack2))
        else:
            cur_lines.append(raw_line)
    flush_cur()
    return out


def iter_lines_with_sources(chunks: List[Chunk]) -> Iterable[Tuple[Path, str]]:
    for ch in chunks:
        for line in ch.text.splitlines(True):
            yield ch.path, line


def brace_delta_line(line: str, in_str_state: bool) -> Tuple[int, bool]:
    """
    Count '{' and '}' on the line, ignoring:
    - braces in "..." string literals (simple escape handling)
    - braces in // line comments
    """
    bal = 0
    in_str = in_str_state
    esc = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue

        if ch == '"':
            in_str = True
            i += 1
            continue

        # line comment
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break

        if ch == "{":
            bal += 1
        elif ch == "}":
            bal -= 1
        i += 1
    return bal, in_str


def scan_per_file_balance(chunks: List[Chunk]) -> List[Tuple[Path, int, int, int]]:
    # Returns: (path, lines, final_bal, min_bal)
    stats = {}
    in_str_by_file = {}

    # We want per-file independent scanning (reset string state each file) because
    # chunks are separate source files in editors.
    for ch in chunks:
        bal = 0
        min_bal = 0
        in_str = False
        line_count = 0
        for line in ch.text.splitlines(True):
            line_count += 1
            d, in_str = brace_delta_line(line, in_str)
            bal += d
            min_bal = min(min_bal, bal)
        prev = stats.get(ch.path)
        if prev is None:
            stats[ch.path] = [0, 0, 0]  # lines, bal, min
        stats[ch.path][0] += line_count
        stats[ch.path][1] += bal
        stats[ch.path][2] = min(stats[ch.path][2], min_bal)

    out = []
    for p, (lines, bal, min_bal) in sorted(stats.items(), key=lambda x: str(x[0])):
        out.append((p, lines, bal, min_bal))
    return out


def find_spanning_functions(chunks: List[Chunk]) -> List[str]:
    """
    Heuristic: detect `fn <name>(` starting at column 0 and report if its closing
    brace occurs in a different included file.
    """
    lines = list(iter_lines_with_sources(chunks))
    spans: List[str] = []

    # Scan with a simple brace depth, but only to match function bodies.
    i = 0
    while i < len(lines):
        path, line = lines[i]
        if line.startswith("fn "):
            # Parse name crudely.
            head = line.strip()
            name = head.split("(")[0].split()[1] if "(" in head else head.split()[1]
            start_path = path

            depth = 0
            in_str = False
            saw_open = False
            j = i
            while j < len(lines):
                p2, ln2 = lines[j]
                d, in_str = brace_delta_line(ln2, in_str)
                if "{" in ln2 and not ln2.lstrip().startswith("//"):
                    saw_open = True
                depth += d
                j += 1
                if saw_open and depth == 0:
                    end_path = p2
                    if end_path != start_path:
                        spans.append(f"{name}: {start_path} -> {end_path}")
                    break
            i = j
            continue
        i += 1

    return spans


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "root",
        type=Path,
        help='Root `.oren` file that contains `// @include "..."` directives (e.g. lib/compiler/arm64_native_expr.oren)',
    )
    ap.add_argument("--show-spans", action="store_true", help="Report top-level fn definitions that span multiple files")
    args = ap.parse_args()

    root = args.root.resolve()
    if not root.exists():
        raise SystemExit(f"not found: {root}")

    chunks = expand_includes_file(root)
    per_file = scan_per_file_balance(chunks)

    print(f"root: {root}")
    print(f"expanded chunk count: {len(chunks)}")
    print("")
    print("== Per-file brace balance (0/min>=0 is coherent) ==")
    for p, lines, bal, min_bal in per_file:
        flag = ""
        if bal != 0 or min_bal < 0:
            flag = "  UNBAL"
        print(f"{p}: lines={lines:5d} bal={bal:4d} min={min_bal:4d}{flag}")

    if args.show_spans:
        spans = find_spanning_functions(chunks)
        print("")
        print("== Top-level functions spanning multiple files ==")
        if not spans:
            print("(none)")
        else:
            for s in spans:
                print(s)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

