import os
from typing import Any, Dict, List, Tuple


SECTION_MATCHES = {
    "production_readiness_gap": "production readiness gap",
    "backend_readiness": "backend readiness",
    "feature_readiness_gaps": "feature readiness gaps",
}


def load_lines(path: str) -> List[str]:
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def is_heading(line: str) -> bool:
    return line.startswith("#") and line.lstrip().startswith("#")


def heading_text(line: str) -> str:
    return line.lstrip("# ").strip().lower()


def collect_section(lines: List[str], header_match: str) -> Tuple[str, List[str]]:
    current_title = ""
    collecting = False
    items: List[str] = []
    current_lines: List[str] = []
    for line in lines:
        if is_heading(line):
            title = heading_text(line)
            if header_match in title:
                collecting = True
                current_title = line.strip().lstrip("#").strip()
                continue
            if collecting:
                break
        if not collecting:
            continue
        if line.startswith("- "):
            if current_lines:
                items.append("\n".join(current_lines))
            current_lines = [line[2:].rstrip()]
            continue
        striped = line.strip()
        if not striped:
            continue
        if not current_lines:
            continue
        if line.startswith(" ") or line.startswith("\t"):
            current_lines.append(line.rstrip())
            continue
    if current_lines:
        items.append("\n".join(current_lines))
    return current_title, items


def item_lines(item: str) -> List[str]:
    return item.splitlines() if item else []


def structured_item(item: str) -> Dict[str, Any]:
    lines = item_lines(item)
    head = lines[0].strip() if lines else ""
    continuations = [line.rstrip() for line in lines[1:]]
    continuations_stripped = [line.strip() for line in continuations]
    has_nested_bullets = any(
        line.strip().startswith("- ") for line in continuations if line.strip()
    )
    return {
        "raw": item,
        "lines": lines,
        "head": head,
        "continuations": continuations,
        "continuations_stripped": continuations_stripped,
        "has_nested_bullets": has_nested_bullets,
    }


def structured_items(items: List[str]) -> List[Dict[str, Any]]:
    return [structured_item(item) for item in items]


def snapshot_from_lines(lines: List[str]) -> Dict[str, Dict[str, Any]]:
    payload: Dict[str, Dict[str, Any]] = {}
    for key, match in SECTION_MATCHES.items():
        title, items = collect_section(lines, match)
        payload[key] = {
            "title": title or match,
            "items": items,
            "items_structured": structured_items(items),
        }
    return payload


def snapshot_from_status(path: str) -> Dict[str, Dict[str, Any]]:
    return snapshot_from_lines(load_lines(path))
